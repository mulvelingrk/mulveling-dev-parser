/*
 * Mike Ulveling
 * 
 * NEW Design!!!
 * Functional-stype vector processing utilities for Apex. Inspired heavily by MuleSoft's DataWeave.
 * 
 */

/*
 * TODOs:
 * 0. For fuck's sake, please make Program a singleton! This will yield much value and 
 *    give nice, COMPLETE DebugTraces for scenarios with recursive trigger firings.
 *    a. Also, add a close() method to Args (i.e. a runtime Frame) as a convenience...
 * 1. Implement orderBy(), pluck(), joinBy(). These are great transformers that nicely 
 *    round out a good initial operator set.
 * 2. See how much we can "unwind" our reliance on Apex-recursion for:
 *    a. Backwards operation chaining (PipedProducer.upstream?.produce())
 *    b. Nested-inner operations
 *    c. Flatten operation
 *    <hot opinion>:
 *    Do-While-True loops are always better - they're more CPU efficient, don't glut up 
 *    Apex Stack Traces, and can actually be quite elegant!
 * 3. Quality-of-Life Feature Enhancements:
 *    a. Easy RefLambda call / handle to resolve reference expressions (like Args.ref(String path))
 *    b. Premade IsNotNull, IsNotBlank, IsTruthy, and IsFalsey lambdas
 *    c. More PipedProducer As{DataType} transformers, like AsString()
 *    d. PipedProucer CatchNull(Lambda | ReferenceExpr | LiteralValue) -> converts a 
 *       forwarded null to a different value!
 * 4. Alias PipedProducer.pipe(Lambda | PipedProducer | String{ReferenceExpr}) to then()?
 * 5. Review Cat operation - can this also work with Array concatenation?
 * 6.a. Can we have an Args.dispatchOnDolla() (and dispatchOnDollaDolla()) which will 
 *    normalize the  MapObject Iterator issue on Map-Objects ("item" is a KeyValuePair and 
 *    "value" is the mapped value)? Or should we revisit the MapObject Iterator's use of 
 *    KeyValuePair items?
 *   b. Args should add `<T> dollaAs{T}()` and `<T> dollaDollaAs{T}()` convenience methods
 * 7. Consider re-engineering contexts by the concepts of: hostContext, parentContext and 
 *    rootContext. See other notes. The goal here is that every operation in a processing 
 *    chain should share the same hostContext, this context can be named (for identity in 
 *    debug traces), and dispatches have a hostContext that points to their parent 
 *    hostContext (and can include its name via dot-qualification). The top hostContext can 
 *    be called rootContext. Recursive triggers can init new rootContext, but must use the 
 *    same Program stack / runtime, because it is (will be a) singleton! This will allow 
 *    debug traces to be VERY descriptive and complete
 *    DO WE GET ANY VALUE FROM CONTEXTS OTHER THAN NAMING?? Maybe some sorts of runtime 
 *    config / settings?
 * 8. Exceptions (IllegalArgument etc) should pull the Program Singleton for their context.
 *    This way they can show debug trace even during compilation phases, if they occur in a 
 *    nested lambda. 
 * 9. Flatten should have its recursive behavior made configurable (to any depth)
 * 10. Rename class KeyValue -> KeyValuePair? 
 * 11. Null fowarding sort of "breaks" debug tracing. Is that OK?
 * 12. Expand SObjectTemplate to work generically for Objects, not just sObjects. Should take
 *    a System.Type as well as an sObjectType. Should also be able to take special "Type" 
 *    properties(?) for dynamic type determination (lambda or ref expr values). Default type,
 *    when not specified, is Map<String, Object>. Consider a FieldWritable interface that 
 *    could be used to fill in fields for custom Apex object. If the target Type does not 
 *    implement FieldWritable, then we can only attempt a JSON.deserialize and hope for the 
 *    best (i.e. no instance variables declared to abstract types) - maybe allow this choice 
 *    to be specified up front. 
 * 13. Explore pre-compilation or "compile once" for nested chains (lambdas). 
 * 
 */

/* EXAMPLES:

    Object output = Func.JSON(
        '[[1, 2], [3, [4,5,6,[7,8,9]], 10], 11]')
            .coalesce(2)
            .forEachCat(':')
            .cat('|')
            .go();
    System.assertEquals('1:2|3:4|5:6|7:8|9:10|11', output);

    Object output = Func.JSON(
        '[[1, 2], [3, [4,5,6,[7,8,9]], 10], 11]')
            .coalesce(2)
            .pipe(new Func.Cat('|')
                .inner(new Func.Cat(':')))
            .go();
    System.assertEquals('1:2|3:4|5:6|7:8|9:10|11', output);

    Object output = Func.SOQL(
        'SELECT * FROM MDU_Test__c ORDER BY Key__c')
            // Streamlined version:
            .forEach('$.Key__c')
            // Generic pipe version:
            //.pipe(
            //    new Func.Mapper(new Func.ReferenceExprLambda('$.Key__c')))
            .coalesce(2)
            // Streamlined version:
            .mapCat(':')
            // Generic pipe version:
            //.pipe(
            //    new Func.Mapper()
            //    	.inner(new Func.Cat(':')))
            .go();
    System.assert(false, output);

    Func.Triggered()
        .triggerEventsFilter(Schema.MDU_Test__c.sObjectType, 'after-new')
        // TriggerRecordPair {current, old} tuple version, instead of plain sObjects:
        .triggerRecordsOnFieldChange('Version__c')
        .forEach('$.current.Key__c')
        .coalesce(3)
        .forEachCat(',')
        .forEachMintSObject(Schema.Process_Request__c.sObjectType, new Map<String, Object> {
            'Looper_Key__c' => 'MDU_Test',
            'Strategy__c' => 'Increment',
            'Scope__c' => '$'
        })
        .dmlInsert()
        .go();

    //=====================================================================

    String inputJSON = '[' 
        + '{"Looper_Key__c": "MDU_Test", "Scope__c": [1, 2, 3]},' 
        + '{"Looper_Key__c": "ACS_Occurrances", "Scope__c": ["C", "B"]},' 
        + '{"Looper_Key__c": "ACS_Claims", "Scope__c": ["001", "002"]},' 
        + '{"Looper_Key__c": "MDU_Test", "Scope__c": [6, 7]},' 
        + '{"Looper_Key__c": "ACS_Occurrances", "Scope__c": ["A"]}'
        //+ '{"Looper_Key__c": "ACS_Occurrances", "Scope__c": ["X", "Y"]}' 
    + ']';
    System.assert(false, 
        Func.JSON(inputJSON)
            .groupBy('$.Looper_Key__c')
            .forEach(new ScopeCoalesce())
            //.forEachMintSObject(Schema.Process_Request__c.sObjectType, new Map<String, Object>{
            //    'Looper_Key__c' => '$(key)',
            //    'Scope__c' => '$(value)'
            //})
            .debugTrace('BAZ')
            .forEachForEach(new NestedLambda())
            .valuesOf()
            .flatten()
            .go());

    public class ScopeCoalesce implements Func.Lambda {
        public Object eval(Func.Args argv) {
            return
                // This lambda operates on a MapObject iterator, so "item"
                // is going to be a KeyValuePair and "value" is the mapped
                // value (KeyValuePair.value).
                // TODO: can we have an Args.dispatchOnAnon$() which will 
                // normalize this?
                argv.dispatchOnValue()
                    .debugTrace('FOO')
                    .forEach('$.Scope__c')
                    .debugTrace('BAR')
                    .flatten()
                    .coalesce(3)
                    .forEachCat(':')
                    .go();
        }
    }

    public class NestedLambda implements Func.Lambda {
        public Object eval(Func.Args argv) {
            argv.debugTrace('Quux');
            //return argv.value;
            return argv.item;
        }
    }

    //=====================================================================
    // Nested-looping example:

    Func.JSON('[' 
        + '{ "Target_Type__c": "claim", "Insured_Account__c": 1 },' 
        + '{ "Target_Type__c": "occur", "Insured_Account__c": 101 },' 
        + '{ "Target_Type__c": "claim", "Insured_Account__c": 2 },' 
        + '{ "Target_Type__c": "claim", "Insured_Account__c": 3 },'
        + '{ "Target_Type__c": "occur", "Insured_Account__c": 102 },' 
        + '{ "Target_Type__c": "occur", "Insured_Account__c": 103 },'
        + '{ "Target_Type__c": "claim", "Insured_Account__c": 4 },' 
        + '{ "Target_Type__c": "claim", "Insured_Account__c": 5 }' 
    + ']')
        .groupBy('$.Target_Type__c')
        .forEachForEach('$.Insured_Account__c')
        .forEach(new Func.Coalesce(2))
        .forEachForEach(new Func.Cat(':'))
        .forEachForEach(new Func.SObjectTemplate(Schema.Process_Request__c.sObjectType, new Map<String, Object>{
            'Scope__c' => '$',
            // !! new outer-scope references!!
            'Looper_Key__c' => '$(outer.outer.$$)', //new DebugLambda(), //'$$',
            'Worker_Strategy__c' => 'ByAccount'
        }))
        .debugTrace()
        .go();

    public class DebugLambda implements Func.Lambda {
        public Object eval(Func.Args argv) {
            argv.debugTrace('LooperKey');
            //argv.parent.debugTrace('LooperKey.parent');
            System.debug('RefEval: [' + new Func.ReferenceExprLambda('outer.outer.$$').eval(argv) + ']');
            return argv.item;
        }
    }

*/

/*
// Awesome Example:

// Func.SOQL uses SOQL Compiler for extended SOQL syntax:
Func.SOQL('SELECT * FROM ACS_Assignment__c')
    // Uncomment this next line to examine Func's automatic DebugTrace, 
    // when an error is thrown out. You can also manually invoke a 
    // DebugTrace at any step in your processing:
    //.forEach(new CorruptTargetLambda())

    // Pre-processing to resolve Target_Type__c = "ALL" to all available 
    // Looper targets. Each ACS_Assignment__c element returned from SOQL 
    // will be transformed by ResolveTargetsLambda into to a vector of 1 
    // or more "account" objects, for example: 
    // [ 
    //    { looperKey: "ACS_Claims", accountId: "abc123" }, 
    //    { looperKey: "ACS_Occurrences", accountId: "abc123" }
    // ]
    .forEach(new ResolveTargetsLambda())
    // The prior step returns a vector-of-vectors, and we want to flatten
    // it again to a vector of "account" objects:
    .flatten()
    // Group the account objects by their looperKey property. This will
    // result in a map of all distinct looperKey values to its 
    // corresponding vector of accounts:
    .groupBy('$.looperKey')
    // Maintaining the outer map structure, chunk the inner vectors' 
    // account ids by groups of 2 (or whatever chunk size we choose). This 
    // will result in a map of vector-of-vectors:
    .forEachForEach('$.accountId')
    // Maintaining the outer map structure, chunk the inner vectors' 
    // account ids by groups of 2. This will result in a map of vector-
    // of-vectors:
    .forEach(new Func.Coalesce(2))
    // Reduce the inner vector-of-vector elements each to a vector of 
    // string-concatenated account ids (comma-delimited). Now we will 
    // have a map of vectors, where each vector contains 1 or more 
    // string elements (each a comma-delimited id list):
    .forEachForEach(new Func.Cat(','))
    // For each inner string element (id list), mint a new 
    // Process_Request__c. Its scope is the id list (accounts), and its 
    // looper key is referenced from the outer map's key value:
    .forEachForEach(new Func.SObjectTemplate(
            Schema.Process_Request__c.sObjectType, new Map<String, Object>{
        // Anonymous parameters $, $$, and $$ are defined by the 
        // immediate outer iterator. In this case, the inner forEach, 
        // which is a Mapper (vector iterator), and its $ slot is assigned
        // to the currently iterated vector element. $$ is assigned to the 
        // element index:
        'Scope__c' => '$',
        // !! new outer-scope references allow referencing arguments of 
        // outer scopes - in this case we want the outer map iterator's 
        // key value. We have to use $() enclosing syntax here, to break 
        // ambuiguity versus string-literal values:
        'Looper_Key__c' => '$(outer.outer.$$)',
        'Worker_Strategy__c' => 'ByAccount'
    }))
    // Debug tracing prints out Func's own internally maintained 
    // program-stack at that point!
    .debugTrace()
    // We have a vector of Process_Request__c from prior steps, and now 
    // we can insert them!
    .dmlInsert()
    // A .go() call is what kicks off processing:
    .go();

// Define a Lambda when you need to inject custom logic inside an iterator 
// that cannot be covered by a simple Reference Expression. In this case 
// we need to call Looper.ResolveLooperTargets to resolve the "ALL" target
// type to all available Looper targets:
public class ResolveTargetsLambda implements Func.Lambda {
    public Object eval(Func.Args argv) {
        ACS_Assignment__c assign = (ACS_Assignment__c) argv.itemAsSObject();
        String unresolvedTargetType = assign.Target_Type__c;
        Looper.LooperTargetDesc[] targets = 
            Looper.ResolveLooperTargets(unresolvedTargetType);
        if (targets == null) {
            // Exceptions thrown out from Func executions will cause Func 
            // to record a full DEBUG trace, showing its program stack at 
            // time of throw!
            argv.illegalArgument('Assignment [' + assign.Id 
                + '] has unrecognized target type [' 
                + unresolvedTargetType + ']');
        }
        // !! Note we could recursively dispatch a new (nested) Func chain 
        // here instead of using this Apex for-loop!
        Object[] marshalled = new Object[]{};
        for (Looper.LooperTargetDesc target : targets) {
            marshalled.add(new Map<String, Object>{
                'looperKey' => target.looperKey,
                'accountId' => assign.Insured_Account__c
            });
        }
        return marshalled;
    }
}

// This is just to simulate a condition that causes ResolveTargetsLambda 
// to throw out IllegalArgumentException, so we can inspect Func's DebugTrace 
// feature:
public class CorruptTargetLambda implements Func.Lambda {
    public Object eval(Func.Args argv) {
        ACS_Assignment__c assign = (ACS_Assignment__c) argv.itemAsSObject();
        assign.Target_Type__c = 'FooBarBaz'; // Bad value!!
        return assign;
    }
}
*/

// ===============================================================
// (DONE!) Outer Scopes:
// ===============================================================
/*
The idea of "Outer Scopes" is that operations are generally iterators (e.g. ForEach, Once, Map, MapObject, 
GroupBy, Filter etc) which maintain their own variables { value, item, key, index } in their per-invocation 
minted Args frame. These operations can be nested (e.g. forEachForEach), and in cases the inner-most operations 
and Lambdas may wish access to a specific outer iterator's variables (e.g. outer-most loop's "index" or "key"). 

To solve for this, we will make `Args outerScope` a recursive property on class Args. Any operation that mints 
a new Args Frame (e.g. pipeIn() implementations) can choose to either forward along its own inherited outerScope, 
OR provide a new one (e.g. the operation's own minted Args Frame, which itself is pointed to the inherited 
outerScope), OR to pass null (if for some reason it wanted to break the scope-inheritance chain). 
NOTE THAT MINTING A NEW Args() MEANS YOU ARE DOING AN OPERATION/FUNCTION DISPATCH 

At this point, "Outer Scopes" will act like a pseudo-Variable Environment, except without the masking behavior.

class Args changes:
> New self-recursive instance variable: Args outerScope
> Update the `get(String)` method (FieldAccessible impl) to return this.outerScope for property "outer"
> Maybe add `Args outerScope` to Args<init> constructor signature(s)?

pipeIn() changes (per impl):
> pipeIn(Program program, Object pipedInput) signature needs changing to:
  pipeIn(Program program, Object pipedInput, Args outerScope)
  Maybe go ahead and also remove `Program arg` since it's moving to a singleton?
> Immediately upon minting `thisOpFrame`, set `thisOpFrame.outerScope = outerScope`. It is OK if this was 
  passed in as null. If we added `Args outerScope` to Args<init>, then just set it that way.
> Set anon param bindings on `thisOpFrame` to mirror what you bind in `lambdaFrame` => Args.anonBindings()
> Immediately upon minting `lambdaFrame` (from PipedProducer.lambda), set `lambdaFrame.outerScope = thisOpFrame`. 
  It is OK if this was passed in as null. If we added `Args outerScope` to Args<init>, then just set it that way.
>> Just call thisOpFrame.dispatchLambda() to mint `lambdaFrame`; it will handle all the necessary lambda-Frame 
   minting logic for you...

pipeIn().{marshalHelper}() changes (per impl):
> Every pipeIn()'s "marshal" method should add `Args operationFrame` to its method signature, and this must be 
  provided in each call to it from its corresponding pipeIn() impl (= thisOpFrame)
> BEFORE doing anything else in this method, set the appropriate formal arg values { value, item, key, index }
  onto `thisOpFrame`
> When dispatching operation.nestedInner.pipeIn(), ensure you pass through the new `operationFrame` parameter
  in as the 2nd argument. 
> If operation.nestedInner.pipeIn() mutates a formal arg like "value" and "item", then this must be updated in 
  operationFrame.
> Before invoking `lambdaFrame`.eval(), call `lambdaFrame`.copyFormalArgsFrom(operationFrame). This will copy
  the formal args we've maintained on operation frame, before the Lambda.eval() dispatch.  
> The `lambdaFrame` already contains its correct outerScope link, and any logic in this Lambda that resolves 
  reference expressions will be enabled for "outer" reference resolving, even nested (e.g. "$(outer.outer.$$)")!
*/

public class Func {
    static final SOQLContext SystemSOQL;
    static {
        SystemSOQL = SOQLContext.newSystemMode();
    }

    static void then() {
        
    }

    private static SOQLContext StartSOQL() {
        return startSOQL(false);
    }

    private static SOQLContext StartSOQL(Boolean forUpdate) {
        SystemSOQL.clearBindings();
        SystemSOQL.forUpdate(forUpdate == true);
        return SystemSOQL;
    }

    static void IllegalArgument(String msg) {
        IllegalArgument(null, null, msg);
    }

    static void IllegalArgument(Args argv, String msg) {
        IllegalArgument(argv, null, msg);
    }

    static void IllegalArgument(PipedProducer operation, String msg) {
        IllegalArgument(null, operation, msg);
    }

    static void IllegalArgument(Args argv, PipedProducer operation, String msg) {
        IllegalArgumentException argErr = new IllegalArgumentException(msg);
        argErr.setMessage(msg);
        argErr.argv = argv;
        argErr.operation = operation;
        throw argErr;
    }

    static void IllegalState(String msg) {
        IllegalState(null, null, msg);
    }

    static void IllegalState(Args argv, String msg) {
        IllegalState(argv, null, msg);
    }

    static void IllegalState(PipedProducer operation, String msg) {
        IllegalState(null, operation, msg);
    }

    static void IllegalState(Args argv, PipedProducer operation, String msg) {
        IllegalStateException stateErr = new IllegalStateException(msg);
        stateErr.setMessage(msg);
        stateErr.argv = argv;
        stateErr.operation = operation;
        throw stateErr;
    }

    static void ReferenceError(String msg) {
        ReferenceError(null, null, msg);
    }

    static void ReferenceError(Args argv, String msg) {
        ReferenceError(argv, null, msg);
    }

    static void ReferenceError(PipedProducer operation, String msg) {
        ReferenceError(null, operation, msg);
    }

    static void ReferenceError(Args argv, PipedProducer operation, String msg) {
        ReferenceException refErr = new ReferenceException(msg);
        refErr.setMessage(msg);
        refErr.argv = argv;
        refErr.operation = operation;
        throw refErr;
    }

    public virtual class FuncException extends Exception {
        // Yep, Program / runtime needs to be made a Singleton...
        public Program runtime {get{
            return this.argv == null ? this.operation == null ? null : this.operation.root : this.argv.program;
        }}
        public Args argv;
        public PipedProducer operation;

        public void debugTrace(String title) {
            if (this.runtime != null) {
                if (runtime.top >= 0) {
                    Args topFrame = this.runtime.stack[this.runtime.top];
                    if (topFrame.operation != null) {
                        // Includes pipedInput:
                        topFrame.operation.debugTrace(title);
                    } else {
                        // Includes Args elements (item, value, key, index):
                        topFrame.debugTrace(title);
                    }
                } else {
                    System.debug(this.getTypeName() + ': Func.Program is not running!');
                }
            } else {
                System.debug(this.getTypeName() 
                    + ': Compile Error; no Func.Program set for for runtime debugTrace.');
            }
        }
    }

    public class IllegalStateException extends FuncException {}
    public class IllegalArgumentException extends FuncException {}
    public class ReferenceException extends FuncException {}

    public interface FieldAccessible {
        Object get(String fieldName);
    }

    public interface MapIterable {
        // Enumeration:
        KeyValue[] keyValues();

        // Random Access:
        Object get(String key);
    }

    // !! Made this NOT MapIterable, because that was lame...
    public class KeyValue implements FieldAccessible { //, MapIterable {
        public String key;
        public Object value;
        public Integer index;

        public KeyValue(String key, Object value, Integer index) {
            this.key = key;
            this.value = value;
            this.index = index;
        }

        public KeyValue(String key, Object value) {
            this(key, value, null);
        }

        public KeyValue[] keyValues() {
            return new KeyValue[]{ this };
        }

        public Object get(String requestedKey) {
            // TODO: Even though KeyValue has a { key, value } and could be accessed like a Map[key => value}, 
            // it should NOT be accessible like a map. Its only accessible properties are "key" and "value"...

            // Case-sensitive keys:
            // TODO: Consider case-insensitive keys at some point?
            switch on requestedKey {
                when 'key' {
                    return this.key;
                }
                when 'value' {
                    return this.value;
                }
                when else {
                    ReferenceError('KeyValue[key="' + this.key 
                        + '"] does not have field [' + requestedKey + ']');
                }
            }
            return null; // unreachable
        }
    }

    static final Integer STARTING_STACK_SIZE = 20;
    static Program[] Programs = new Program[]{};

    static final String EmSpace = ' '; // Unicode fixed-width space char
    static final String TraceIndent = EmSpace.repeat(2);

    public class Program {
        Context context;
        Args[] stack;
        Integer top;
        Integer len;
        Integer programIndex;

        private Args currentFrame {get{
            return this.stack[this.top];
        }}

        private Program(Context context) {
            this.programIndex = Programs.size();
            Programs.add(this);
            this.context = context;
            this.stack = new List<Args>(STARTING_STACK_SIZE);
            this.top = -1;
            this.len = this.stack.size();
        }

        private void add(Args frame) {
            if (this.top >= this.len - 1) {
                Integer newSlots = Math.min(STARTING_STACK_SIZE, this.len);
                for (Integer i = 0; i < newSlots; i++) {
                    this.stack.add(null);
                }
                this.len = this.stack.size();
            }
            this.stack[++this.top] = frame;
            frame.stackIndex = this.top;
        }

        // TODO: Args should be able to close itself; Args.close()
        private void close(Args closingFrame) {
            // No-op if we got a null frame:
            if (closingFrame == null) {
                return;
            }
            // Manually null-out all the reclaimed Frame slots to prevent memory leaks (though 
            // unlikely to occur before the stack blows out):
            while (this.top >= closingFrame.stackIndex) {
                this.stack[this.top--] = null;
            }
        }

        private void closeAfter(Args newTopFrame) {
            while (this.top > newTopFrame.stackIndex) {
                this.stack[this.top--] = null;
            }
        }

        private void debugTrace(Integer lastStackPosition) {
            Integer lineNum = 0;
            // Tracks when we have consecutive non-lambda operations:
            PipedProducer prevFrameOp;
            final String sequenceArrow = ' 🡢 '; // → ⭢ 🠦 🠪 🡢 🠖 
            lastStackPosition = Math.min(lastStackPosition ?? this.top, this.top);
            // IFF the Frame atop stack is a DebugTrace, we should render that DebugTrace's upstream 
            // operations, but NOT the DebugTrace operation itself. We flag this by marking the stack 
            // index to which this applies. All other DebugTrace instances should be ignored and witheld
            // from rendering:
            Integer showDebugUpstreamAtIndex;
            if (lastStackPosition >= 0 && this.stack[lastStackPosition].operation instanceof DebugTrace) {
                showDebugUpstreamAtIndex = lastStackPosition;
            }
            for (Integer i = 0; i <= lastStackPosition; i++) {
                Args frame = this.stack[i];
                String line = '<No-Op>';
                String dispatchArrow = i > 0 ? '↪ ' : ''; // ↪ ↳ ➥ ⤷ 
                if (frame?.operation != null) {
                    // The rendered list of operation names for the "current" ops chain, in order from 
                    // first to last:
                    String[] renderedOps = new String[]{'<EndChain>'};

                    // DebugTrace special-handling logic:
                    if (frame?.operation instanceof DebugTrace) {
                        // If this Frame is a DebugTrace AND it's the special one flagged above, then
                        // explicitly add(0) it to the rendered op chain (it will end up last in the 
                        // rendered list), since it will be ignored in the subsequent chained-operations 
                        // loop:
                        if (i == showDebugUpstreamAtIndex) {
                            renderedOps.add(0, frame.operation.name);
                        // Else this DebugTrace is NOT the special one flagged above, and should NOT be
                        // rendered, so we skip it:
                        } else {
                            continue;
                        }
                    }

                    // Chained-operations loop: iterates backwards through the operations chain from the 
                    // last op frame (atop stack, or the stack index we are tracing from), and inserts 
                    // each op name at index 0 to reverse the reversed order (i.e. generates proper order).
                    // Note that in all cases, DebugTrace operations are witheld from rendering (excepting
                    // the DebugTrace special-handling logic above):
                    if (prevFrameOp == null) {
                        PipedProducer opItem = frame.operation;
                        do {
                            if (!(opItem instanceof DebugTrace)) {
                                renderedOps.add(0, opItem.name);
                            }
                            opItem = opItem.upstream;
                        } while (opItem != null);
                    } else if (!(frame.operation instanceof DebugTrace)) {
                        renderedOps.add(0, frame.operation.name);
                    }
                    prevFrameOp = frame.operation;

                    // TODO: Leave the <No-Op> line if this was a lone DebugTrace operation atop the stack?
                    // Can that even happen, with the DebugTrace special-handling logic above?
                    if (renderedOps.size() > 1) {
                        renderedOps.remove(renderedOps.size() - 1);
                    }
                    line = dispatchArrow + String.join(renderedOps, sequenceArrow);
                } else if (frame?.lambda != null) {
                    prevFrameOp = null;
                    line = dispatchArrow + frame.getFrameName(); //'Lambda[' + getClassName(frame.lambda) + ']';
                } else {
                    prevFrameOp = null;
                }
                // These are 2 unicode "em" spaces, not normal spaces:
                System.debug(TraceIndent.repeat(lineNum) + (line ?? ''));
                lineNum++;
            }
        }
    }

    // Args currently serves dual purpose:
    // 1. As arguments for Lambdas
    // 2. As an execution Frame in the Program Stack. 
    // TODO: Consider if these roles need to be split into separate classes, but I'm going with 
    // simplicity for now:
    public class Args implements FieldAccessible {
        // TODO: This needs to be made a Singleton. There can only be one:
        Program program;
        // Outer scopes - analogous to static block scopes in traditional languages:
        // TODO: Consider implicit inheritance and masking to fully emulate traditional scoping...
        Args outerScope;

        // A Frame can represent either an Operation OR a Lambda, but not both!
        PipedProducer operation;
        Lambda lambda;
        
        // Upon minting this Frame, stackIndex is assigned to its position atop the Program Stack:
        Integer stackIndex;

        // "Formal" parameters that are common across many different Lambda use-cases:
        public Object value;
        public Object item;
        public String key;
        public Integer index;

        // Anonymous parameters: $, $$, and $$$
        String anonBind1; // $
        String anonBind2; // $$
        String anonBind3; // $$$

        public Map<String, ReferenceExprLambda> refLambdaCache;

        // !! Note the constructors are private. Only internal Func logic should mint new Args, 
        // because its constructor manipulates the Program Stack!
        
        Args(Program program, Args outerScope, PipedProducer operation) {
            this(program, outerScope, operation, null);
        }

        Args(Program program, Args outerScope, PipedProducer operation, Object value) {
            this.program = program;
            this.outerScope = outerScope;
            this.operation = operation;
            this.value = value;
            program.add(this);
        }

        Args(Program program, Args outerScope, Lambda lambda, Object value) {
            this.program = program;
            this.outerScope = outerScope;
            this.lambda = lambda;
            this.value = value;
            program.add(this);
        }

        Args(Program program, Args outerScope, Lambda lambda) {
            this(program, outerScope, lambda, null);
        }

        public String getFrameName() {
            if (this.operation != null) {
                return this.operation.name;
            } else if (this.lambda != null) {
                return 'Lambda[' + getClassName(this.lambda) + ']';
            }
            return 'No-Op';
        }

        public void illegalArgument(String message) {
            IllegalArgument(this, message);
        }

        // Takes a reference path and resolves it against this Args as its scope. Args implement ref
        // caching to save CPU from repetitively compiling these references, since this ref() call is 
        // likely to be used in Lambdas for looping:
        public Object ref(String refPath) {
            if (refLambdaCache == null) {
                this.refLambdaCache = new Map<String, ReferenceExprLambda>();
            }
            ReferenceExprLambda refLambda = this.refLambdaCache.get(refPath);
            if (refLambda == null) {
                this.refLambdaCache.put(refPath, refLambda = new ReferenceExprLambda(refPath));
            }
            return refLambda.eval(this);
        }

        // Convenience method to easily spawn & dispatch a new lambda-Frame for an operation's lambda 
        // function, derived from that operation's own Frame (this Frame). Most properties are copied, 
        // but a few are reset as necessary:
        public Args dispatchLambdaFrame() {
            if (this.operation == null) {
                IllegalState(this, 
                    'Method Args.dispatchLambdaFrame() may only be called on an operation-Frame');
            } else if (this.operation.lambda == null) {
                return null;
            }
            Args lambdaFrame = this.clone();
            lambdaFrame.operation = null;
            lambdaFrame.lambda = this.operation.lambda;
            lambdaFrame.outerScope = this;
            // This will update lambdaFrame.stackIndex:
            program.add(lambdaFrame);
            return lambdaFrame;
        }

        public Args copyFormalArgsFrom(Args sourceArgs) {
            this.value = sourceArgs.value;
            this.item = sourceArgs.item;
            this.key = sourceArgs.key;
            this.index = sourceArgs.index;
            return this;
        }

        public Args anonBindings(String customField1, String customField2, String customField3) {
            this.anonBind1 = customField1;
            this.anonBind2 = customField2;
            this.anonBind3 = customField3;
            return this;
        }

        public Object resolveAnonSlot(Integer slot) {
            String bindField;
            switch on slot {
                when 1 {
                    bindField = this.anonBind1;
                }
                when 2 {
                    bindField = this.anonBind2;
                }
                when 3 {
                    bindField = this.anonBind3;
                }
            }
            if (bindField == null) {
                String slotName = 'Slot[' + (slot == null ? '<Null>' : String.valueOf(slot)) + ']';
                if (slot != null && slot > 0 && slot <= 5) {
                    slotName = '$'.repeat(slot);
                }
                ReferenceError(this, 'Lambda ' + this.getLambdaName() 
                    + ' does not define anonymous parameter ' + slotName);
            }
            // Uses the FieldAccessible implementation:
            return this.get(bindField);
        }

        public PipedProducer dispatchOn(SourceProducer source) {
            source.root = this.program;
            source.rootContext = this.program.context;
            return source;
        }

        public PipedProducer dispatchOnItem() {
            return dispatchOn(Func.Literal(this.item));
        }

        public PipedProducer dispatchOnValue() {
            return dispatchOn(Func.Literal(this.value));
        }

        public String getLambdaName() {
            return getClassName(this.lambda);
        }

        public String itemToString() {
            return this.item?.toString();
        }

        public String valueToString() {
            return this.value?.toString();
        }

        private void itemAsViolation(String expectedTypeName) {
            IllegalArgument(this, 'Lambda ' + this.getLambdaName() 
                + ' expected ' + expectedTypeName + ' as "item" argument, got ' + this.item);
        }

        private void valueAsViolation(String expectedTypeName) {
            IllegalArgument(this, 'Lambda ' + this.getLambdaName() 
                + ' expected ' + expectedTypeName + ' as "value" argument, got ' + this.value);
        }

        // Not-null assertion:
        public Object itemIsNotNull() {
            if (this.item == null) {
                IllegalArgument(this, 'Lambda ' + this.getLambdaName() 
                    + ' rejects a Null "item" argument');
            }
            return this.item;
        }

        public Object valueIsNotNull() {
            if (this.value == null) {
                IllegalArgument(this, 'Lambda ' + this.getLambdaName() 
                    + ' rejects a Null "value" argument');
            }
            return this.value;
        }

        public Object[] itemAsVector() {
            if (this.item != null && !(this.item instanceof Object[])) {
                itemAsViolation('Vector');
            }
            return (Object[]) this.item;
        }

        public Object[] valueAsVector() {
            if (this.value != null && !(this.value instanceof Object[])) {
                valueAsViolation('Vector');
            }
            return (Object[]) this.value;
        }

        public String itemAsString() {
            if (this.item != null && !(this.item instanceof String)) {
                itemAsViolation('String');
            }
            return (String) this.item;
        }

        public String valueAsString() {
            if (this.value != null && !(this.value instanceof String)) {
                valueAsViolation('String');
            }
            return (String) this.value;
        }

        public Map<String, Object> itemAsMap() {
            if (this.item != null && !(this.item instanceof Map<String, Object>)) {
                itemAsViolation('Map');
            }
            return (Map<String, Object>) this.item;
        }

        public Map<String, Object> valueAsMap() {
            if (this.value != null && !(this.value instanceof Map<String, Object>)) {
                valueAsViolation('Map');
            }
            return (Map<String, Object>) this.value;
        }

        public TriggerRecordPair itemAsTriggerPair() {
            if (this.item != null && !(this.item instanceof TriggerRecordPair)) {
                itemAsViolation('TriggerRecordPair');
            }
            return (TriggerRecordPair) this.item;
        }

        public TriggerRecordPair valueAsTriggerPair() {
            if (this.value != null && !(this.value instanceof TriggerRecordPair)) {
                valueAsViolation('TriggerRecordPair');
            }
            return (TriggerRecordPair) this.value;
        }

        public sObject itemAsSObject() {
            if (this.item != null && !(this.item instanceof sObject)) {
                itemAsViolation('sObject');
            }
            return (sObject) this.item;
        }

        public sObject valueAsSObject() {
            if (this.value != null && !(this.value instanceof sObject)) {
                valueAsViolation('sObject');
            }
            return (sObject) this.value;
        }

        public sObject[] itemAsSObjects() {
            if (this.item != null && !(this.item instanceof sObject[])) {
                itemAsViolation('Vector of sObjects');
            }
            return (sObject[]) this.item;
        }

        public sObject[] valueAsSObjects() {
            if (this.value != null && !(this.value instanceof sObject[])) {
                valueAsViolation('Vector of sObjects');
            }
            return (sObject[]) this.value;
        }

        public KeyValue keyValue() {
            return new KeyValue(this.key, this.item, this.index);
        }

        // FieldAccessible implementation:
        public Object get(String field) {
            switch on field {
                when '$', '$$', '$$$' {
                    Integer anonSlot = field.length(); // lol
                    return this.resolveAnonSlot(anonSlot);
                }
                when 'value' {
                    return this.value;
                }
                when 'item' {
                    return this.item;
                }
                when 'key' {
                    return this.key;
                }
                when 'index' {
                    return this.index;
                }
                when 'args' {
                    return this;
                }
                // Outer scopes - analogous to static block scopes in traditional languages:
                when 'outer' {
                    return this.outerScope;
                }
                // Yeah, this was a baaaad idea lol:
                //when 'parent' {
                //    if (this.stackIndex > 0) {
                //        return this.program.stack[this.stackIndex - 1];
                //    }
                //    return null;
                //}
                when else {
                    // TODO: as a last resort, try to resolve field as a variable in 
                    // this.context's Environment!

                    ReferenceError(this, 'Args illegal field [' + field + ']');
                }
            }
            return null; // unreachable
        }

        public void debugTrace() {
            this.debugTrace(null);
        }

        public void debugTrace(String title) {
            String traceTitle = title != null ? title : 'Anon';
            System.debug('TRACE<' + traceTitle + '>');

            String thisCallTitle = 'This Call Frame' + (this.outerScope == null ? '<ROOT>' : '') 
                + ': ' + this.getFrameName();
            if (this.outerScope != null) {
                thisCallTitle += ', Parent Scope: ' + this.outerScope.getFrameName();
            }
            System.debug(thisCallTitle);

            String[] formalArgs = new String[]{};
            String[] nullFormalArgs = new String[]{};
            if (this.value != null) {
                formalArgs.add(TraceIndent + 'value: ' + this.value);
            } else {
                nullFormalArgs.add('value');
            }
            if (this.item != null) {
                formalArgs.add(TraceIndent + 'item: ' + this.item);
            } else {
                nullFormalArgs.add('item');
            }
            if (this.key != null) {
                formalArgs.add(TraceIndent + 'key: ' + this.key);
            } else {
                nullFormalArgs.add('key');
            }
            if (this.index != null) {
                formalArgs.add(TraceIndent + 'index: ' + this.index);
            } else {
                nullFormalArgs.add('index');
            }

            String formalArgsTitle = 'Formal Arguments:';
            if (nullFormalArgs.size() > 0) {
                formalArgsTitle = 'Formal Arguments<undefined: ' + String.join(nullFormalArgs, ',') + '>:';
            }
            System.debug(formalArgsTitle);
            for (String formalArg : formalArgs) {
                System.debug(formalArg);
            }

            String[] anonBinds = new String[]{};
            if (String.isNotBlank(this.anonBind1)) {
                anonBinds.add('$ 🡢 ' + this.anonBind1);
            }
            if (String.isNotBlank(this.anonBind2)) {
                anonBinds.add('$$ 🡢 ' + this.anonBind2);
            }
            if (String.isNotBlank(this.anonBind3)) {
                anonBinds.add('$$$ 🡢 ' + this.anonBind3);
            }
            if (anonBinds.size() > 0) {
                System.debug('Anonymous Bindings: ' + String.join(anonBinds, ', '));
            }

            System.debug('Stack Trace:');
            program.debugTrace(this.stackIndex);
            System.debug('END_TRACE<' + traceTitle + '>');
        }
    }

    public interface Lambda {
        Object eval(Args argv);
    }

    public class LiteralLambda implements Lambda {
        Object literalValue;

        public LiteralLambda(Object anyLiteralValue) {
            this.literalValue = anyLiteralValue;
        }

        public Object eval(Args argv) {
            return this.literalValue;
        }
    }

    public interface InitializingLambda extends Lambda {
        Object init(Args argv);
    }

    public interface ReduceLambda extends InitializingLambda {
        //Object init(Args argv);
    }
    
    public class Context {
        Integer top = -1;
        Object[] stashStack = new Object[]{};
        Map<String, Object> saveMap = new Map<String, Object>();

        public Integer push(Object result) {
            this.stashStack.add(result);
            return ++this.top;
        }

        public Object pop() {
            return this.top >= 0 ? this.stashStack[this.top--] : null;
        }

        public Object save(String name, Object result) {
            return this.saveMap.put(name, result);
        }

        public Object recall(String name) {
            return this.saveMap.get(name);
        }
    }

    public interface Producer {
        Program getRoot();

        Context getRootContext();

        Context getContext();

        Object produce();

        Object pipeIn(Program program, Args outerScope, Object input);

        Object[] mintMutableVector();
    }

    public abstract class PipedProducer implements Producer {
        String name;
        Program root;
        // Maintains the chaining of sequenced operations as a backwards-linked list:
        PipedProducer upstream;
        // Inner operation that is a nested PipedProducer (operation). Can be nested an arbitrary 
        // number of levels deep (recursive):
        PipedProducer nestedInner;
        // Inner operation / transformer that is "just" a lambda:
        Lambda lambda;
        
        Context rootContext;
        Context localContext;
        // TODO: "vectorType" is a completely wrong name for this now:
        System.Type vectorType;
        Boolean preserveUpstreamVectorType;
        
        public PipedProducer(String name) {
            this.name = name;
            this.preserveUpstreamVectorType = false;
        }

        public PipedProducer(String name, Lambda lambda) {
            this.name = name;
            this.lambda = lambda;
            this.preserveUpstreamVectorType = false;
        }

        /*
        public PipedProducer(String name, PipedProducer upstream) {
            this.name = name;
            this.upstream = upstream;
            this.preserveUpstreamVectorType = false;
        }
        */

        public Program getRoot() {
            return this.root;
        }

        public Context getRootContext() {
            return this.rootContext;
        }

        public Context getContext() {
            return this.localContext ?? this.rootContext;
        }

        public PipedProducer inner(PipedProducer nestedProducer) {
            this.nestedInner = nestedProducer;
            nestedProducer.root = this.root;
            nestedProducer.rootContext = this.rootContext;
            if (this.root != null) {
                nestedProducer.distributeRoot();
            }
            return this;
        }

        private void setUpstream(PipedProducer upstreamProducer) {
            if (this.upstream != null) {
                IllegalState('Upstream producer cannot be redefined on PiperProducer');
            }
            // TODO: ??
            this.root = upstreamProducer.root;
            this.upstream = upstreamProducer;
            this.rootContext = upstreamProducer.getRootContext();
        }

        public PipedProducer debugTrace() {
            return this.pipe(new DebugTrace());
        }

        public PipedProducer debugTrace(String header) {
            return this.pipe(new DebugTrace(header));
        }

        // Trigger conveniences:

        public PipedProducer triggerEventsFilter(String flagsExpression) {
            return this.triggerEventsFilter(null, flagsExpression);
        }

        public PipedProducer triggerEventsFilter(Schema.sObjectType targetType) {
            return this.filter(triggerEventsLambda(targetType, null));
        }

        public PipedProducer triggerEventsFilter(Schema.sObjectType targetType, String eventsExpression) {
            return this.filter(triggerEventsLambda(targetType, eventsExpression));
        }

        private Lambda triggerEventsLambda(Schema.sObjectType targetType, String eventsExpression) {
            TriggerFlagsLambda[] allFlags = new TriggerFlagsLambda[]{};
            if (String.isNotBlank(eventsExpression)) {
                for (String eventTerm : eventsExpression.split('\\s*+,\\s*+')) {
                    String normalizedTerm = eventTerm.replaceAll('[^a-zA-Z]++', '').toLowerCase();
                    String[] tokens;
                    switch on normalizedTerm {
                        when 'beforenew' {
                            tokens = new String[]{ 'beforeinsert', 'beforeupdate' };
                        }
                        when 'afternew' {
                            tokens = new String[]{ 'afterinsert', 'afterupdate', 'afterundelete' };
                        }
                        when else {
                            tokens = new String[]{ normalizedTerm };
                        }
                    }

                    for (String token : tokens) {
                        TriggerFlagsLambda flags = new TriggerFlagsLambda(targetType);
                        allFlags.add(flags);
                        if (token.startsWith('before')) {
                            flags.isBefore = true;
                        }
                        if (token.startsWith('after')) {
                            flags.isAfter = true;
                        }
                        switch on token {
                            when 'beforeinsert', 'afterinsert' {
                                flags.isInsert = true;
                            }
                            when 'beforeupdate', 'afterupdate' {
                                flags.isUpdate = true;
                            }
                            when 'beforedelete', 'afterdelete' {
                                flags.isDelete = true;
                            }
                            when 'afterundelete' {
                                flags.isUndelete = true;
                            } when else {
                                IllegalArgument(this, 'Invalid trigger event [' + eventTerm 
                                    + '] from expression [' + eventsExpression + ']');
                            }
                        }
                    }
                }
            }
            if (allFlags.size() > 1) {
                AnyOfLambda anyOf = new AnyOfLambda();
                for (Lambda flags : allFlags) {
                    anyOf.add(flags);
                }
                return anyOf;
            } else if (allFlags.size() == 1) {
                return allFlags[0];
            } else {
                return null;
            }
        }

        public PipedProducer triggerSObjectsOnFieldChange(String fieldsCat) {
            return this.triggerSObjectsOnFieldChange(fieldsCat, false);
        }

        // Convenience version of triggerRecordsOnFieldChange() that returns the current sObject 
        // versions, rather than the { current, old } record tuples:
        public PipedProducer triggerSObjectsOnFieldChange(String fieldsCat, Boolean includeOnDelete) {
            return triggerRecordsOnFieldChange(fieldsCat, includeOnDelete)
                .pipe(new Mapper(new ReferenceExprLambda('$.current')));
        }

        public PipedProducer triggerSObjectsOnFieldChange(String[] fields) {
            return this.triggerSObjectsOnFieldChange(fields, false);
        }

        // Convenience version of triggerRecordsOnFieldChange() that returns the current sObject 
        // versions, rather than the { current, old } record tuples:
        public PipedProducer triggerSObjectsOnFieldChange(String[] fields, Boolean includeOnDelete) {
            return triggerRecordsOnFieldChange(fields, includeOnDelete)
                .pipe(new Mapper(new ReferenceExprLambda('$.current')));
        }

        public PipedProducer triggerRecordsOnFieldChange(String fieldsCat) {
            return this.triggerRecordsOnFieldChange(fieldsCat, false);
        }

        // Returns { current, old } TriggerRecordPair tuples for all records in Trigger context that 
        // show a change on any of the specified fields. "fieldCat" is a comma-delimited list of
        // fields to track changes on:
        public PipedProducer triggerRecordsOnFieldChange(String fieldsCat, Boolean includeOnDelete) {
            String[] fieldsList;
            if (String.isNotBlank(fieldsCat)) {
                fieldsList = fieldsCat.split('\\s*+,\\s*+');
            }
            return this.triggerRecordsOnFieldChange(fieldsList, includeOnDelete);
        }

        public PipedProducer triggerRecordsOnFieldChange(String[] fields) {
            return this.triggerRecordsOnFieldChange(fields, false);
        }
        
        // Returns { current, old } TriggerRecordPair tuples for all records in Trigger context that 
        // show a change on any of the specified "fields":
        public PipedProducer triggerRecordsOnFieldChange(String[] fields, Boolean includeOnDelete) {
            if (fields != null && fields.size() > 0) {
                for (Integer i = 0; i < fields.size(); i++) {
                    if (String.isBlank(fields[i])) {
                        fields.remove(i--);
                    }
                }
                if (fields.size() > 0) {
                    return this.pipe(new Mapper(
                        new TriggerRecordsChangedByField(fields)
                            .includeOnDelete(includeOnDelete == true)));
                }
            }
            // If there are no fields to track, default to the identity mapper:
            return this.pipe(new Mapper());
        }

        // Type coercions:

        public PipedProducer asString() {
            return this.pipe(new StringCoerce());
        }

        // DML conveniences:

        public PipedProducer dmlInsert() {
            return this.pipe(new DmlStatement(DML_Action.DML_Insert));
        }

        public PipedProducer dmlUpdate() {
            return this.pipe(new DmlStatement(DML_Action.DML_Update));
        }

        public PipedProducer dmlUpsert() {
            return this.pipe(new DmlStatement(DML_Action.DML_Upsert));
        }

        public PipedProducer dmlDelete() {
            return this.pipe(new DmlStatement(DML_Action.DML_Delete));
        }

        public PipedProducer flatten() {
            return this.pipe(new Flatten());
        }

        public PipedProducer coalesce(Integer coalesceLimit) {
            return this.pipe(new Coalesce(coalesceLimit));
        }

        public PipedProducer cat() {
            return this.cat(null);
        }

        public PipedProducer cat(String separator) {
            return this.pipe(new Cat(separator));
        }

        // SOQLEvaluator filtering!
        public PipedProducer soqlFilter(String soqlCondition) {
            return this.filter(new SOQLFilter(soqlCondition));
        }

        // SOQLEvaluator filtering!
        public PipedProducer soqlFilter(Schema.sObjectType fromClauseType, String soqlCondition) {
            return this.filter(new SOQLFilter(fromClauseType, soqlCondition));
        }

        //public PipedProducer filter(Lambda lambda) {
        //    return this.pipe(new Filter(lambda));
        //}

        // Argument "refExprInnerOpLambda" may be:
        // > A String that starts with a "$" is interpreted as a ReferenceExpression, and mints a new 
        //   Func.ReferenceExprLambda for the Filter's lambda.
        // > An inner operation - (instanceof PipedProducer)
        // > Any lambda function (instanceof Func.Lambda)
        // > Any OTHER type of value, including Strings that do not begin with "$", is interpreted as 
        //   a constant literal value, and will be wrapped in a Func.LiteralLambda. It's unclear what
        //   use cases might need this.
        public PipedProducer filter(Object refExprInnerOpLambda) {
            return this.thenOp(new Filter(lambda), refExprInnerOpLambda);
        }

        public PipedProducer filterNot(Object refExprInnerOpLambda) {
            return this.thenOp(new Filter(lambda).negate(), refExprInnerOpLambda);
        }

        public PipedProducer reduce(Reduce reducer) {
            return this.pipe(reducer);
        }

        public PipedProducer reduce(ReduceLambda lambda) {
            return this.pipe(new Reduce(lambda));
        }

        /* Deprecated:
        public PipedProducer mapGet(String fieldExpression) {
            return this.pipe(new Mapper(new GetItemField(fieldExpression)));
        }
        */

        public PipedProducer mapCat() {
            return this.mapCat(null);
        }

        public PipedProducer mapCat(String separator) {
            return this.pipe(new Mapper().inner(new Cat(separator)));
        }

        public PipedProducer forEachCat() {
            return this.forEachCat(null);
        }

        public PipedProducer forEachCat(String separator) {
            return this.pipe(new ForEach().inner(new Cat(separator)));
        }

        public PipedProducer onceCat() {
            return this.onceCat(null);
        }

        public PipedProducer onceCat(String separator) {
            return this.pipe(new Once().inner(new Cat(separator)));
        }

        public PipedProducer mapFlatten() {
            return this.pipe(new Mapper().inner(new Flatten()));
        }

        public PipedProducer forEachFlatten() {
            return this.pipe(new ForEach().inner(new Flatten()));
        }

        public PipedProducer onceFlatten() {
            return this.pipe(new Once().inner(new Flatten()));
        }

        // Compound map-{nested transform} operations:
        // TODO: Add overloads that allow specification of an outerLambda...

        public PipedProducer mapFilter(Filter innerFiltering) {
            return this.pipe(new Mapper().inner(innerFiltering));
        }

        public PipedProducer mapFilter(Lambda innerLambda) {
            return this.mapFilter(new Filter(innerLambda));
        }

        public PipedProducer forEachFilter(Filter innerFiltering) {
            return this.pipe(new ForEach().inner(innerFiltering));
        }

        public PipedProducer forEachFilter(Lambda innerLambda) {
            return this.forEachFilter(new Filter(innerLambda));
        }

        public PipedProducer onceFilter(Filter innerFiltering) {
            return this.pipe(new Once().inner(innerFiltering));
        }

        public PipedProducer onceFilter(Lambda innerLambda) {
            return this.onceFilter(new Filter(innerLambda));
        }

        public PipedProducer mapReduce(Reduce innerReduce) {
            return this.pipe(new Mapper().inner(innerReduce));
        }

        public PipedProducer mapReduce(ReduceLambda innerLambda) {
            return this.mapReduce(new Reduce(innerLambda));
        }

        public PipedProducer forEachReduce(Reduce innerReduce) {
            return this.pipe(new ForEach().inner(innerReduce));
        }

        public PipedProducer forEachReduce(ReduceLambda innerLambda) {
            return this.forEachReduce(new Reduce(innerLambda));
        }

        public PipedProducer onceReduce(Reduce innerReduce) {
            return this.pipe(new Once().inner(innerReduce));
        }

        public PipedProducer onceReduce(ReduceLambda innerLambda) {
            return this.onceReduce(new Reduce(innerLambda));
        }

        // TODO: Decide on nomenclature for sObject-templating, and more generic Object-
        // templating. "New", "Mint", etc...
        public PipedProducer mapNewSObject(Schema.sObjectType mintType, 
                Map<String, Object> fieldTemplates) {
            return this.mapMintSObject(mintType, fieldTemplates);
        }

        public PipedProducer mapMintSObject(Schema.sObjectType mintType, 
                Map<String, Object> fieldTemplates) {
            return this.mapMintSObject(new SObjectTemplate(mintType, fieldTemplates));
        }

        public PipedProducer mapMintSObject(SObjectTemplate template) {
            Mapper m = new Mapper(template);
            m.outputsTo(sObject[].class);
            return this.pipe(m);
        }

        public PipedProducer forEachMintSObject(Schema.sObjectType mintType, 
                Map<String, Object> fieldTemplates) {
            return this.forEachMintSObject(new SObjectTemplate(mintType, fieldTemplates));
        }

        public PipedProducer forEachMintSObject(SObjectTemplate template) {
            ForEach m = new ForEach(template);
            m.outputsTo(sObject[].class);
            return this.pipe(m);
        }

        public PipedProducer onceMintSObject(Schema.sObjectType mintType, 
                Map<String, Object> fieldTemplates) {
            return this.onceMintSObject(new SObjectTemplate(mintType, fieldTemplates));
        }

        public PipedProducer onceMintSObject(SObjectTemplate template) {
            Once m = new Once(template);
            m.outputsTo(sObject[].class);
            return this.pipe(m);
        }

        public PipedProducer mapObject(MapObject mapper) {
            return this.pipe(mapper);
        }

        public PipedProducer mapObject(Lambda lambda) {
            return this.mapObject(new MapObject(lambda));
        }

        public PipedProducer groupBy(Object innerOp) {
            return this.thenOp(new GroupBy(), innerOp);
        }

        /*
        public PipedProducer groupBy(String referenceExpression) {
            return this.pipe(new GroupBy(referenceExpression));
        }

        public PipedProducer groupBy(Lambda groupByLambda) {
            return this.pipe(new GroupBy(groupByLambda));
        }
        */

        public PipedProducer keysOf() {
            return this.pipe(new KeysOf());
        }

        public PipedProducer valuesOf() {
            return this.pipe(new ValuesOf());
        }

        public PipedProducer mapp(Mapper mapping) {
            return this.pipe(mapping);
        }

        public PipedProducer mapp(Lambda lambda) {
            return this.pipe(new Mapper(lambda));
        }

        // =================================================================================================

        // Generic helper method for attaching a "next" processor / transformer operation. Note that while 
        // "outerOp" must be a PipedProducer that is not previously attached, "innerOp" allows for a wide 
        // range of interpretation!
        private PipedProducer thenOp(PipedProducer outerOp, Object innerOp) {
            return this.pipe(this.compositeOp(outerOp, innerOp));
        }

        private PipedProducer compositeOp(PipedProducer outerOp, Object innerOp) {
            if (innerOp != null) {
                if (innerOp instanceof String) {
                    // If innerOp is a String, then we try to parse it as a reference-expression Lambda, and
                    // failing that we either throw an error (ambiguous syntax) or mints it as a string-literal 
                    // Lambda. 
                    // I.e. if we make it to this step, then we either rewrite the sneech as a Lambda, or fail
                    // with a thrown out ReferenceException: 
                    innerOp = parseRefOrLitToLambda(null, this, (String) innerOp);
                }

                if (innerOp instanceof Lambda) {
                    // If innerOp is a Lambda (including conversion fom String - see above) then we're good
                    // to wrap it directly into the outer operation:
                    outerOp.lambda = (Lambda) innerOp;
                } else if (innerOp instanceof PipedProducer) {
                    // Else If innerOp is another Operation, then we set it as the nested "inner" operation 
                    // in this outer operation:
                    // TODO: guard that (detachedOuterOp !== innerOp)?
                    outerOp.inner((PipedProducer) innerOp);
                } else {
                    // Else If innerOp is not Lambda nor Operation, then we have to treat it as a literal 
                    // value - wrap it into a LiteralLambda, and then directly into the outer operation:
                    outerOp.lambda = new LiteralLambda(innerOp);
                }
            }
            return outerOp;
        }

        // Takes: (PipedProducer<InnerOperation> | Lambda<Innerlambda> | String<InnerReferenceExpr> 
        //     | Object<InnerConstantLiteral>)
        public PipedProducer forEach(Object innerOp) {
            return this.thenOp(new ForEach(), innerOp);
        }

        // Takes: (PipedProducer<InnerOperation> | Lambda<Innerlambda> | String<InnerReferenceExpr> 
        //     | Object<InnerConstantLiteral>)
        public PipedProducer once(Object innerOp) {
            return this.thenOp(new Once(), innerOp);
        }

        // Takes: (PipedProducer<InnerOperation> | Lambda<Innerlambda> | String<InnerReferenceExpr> 
        //     | Object<InnerConstantLiteral>)
        public PipedProducer forEachForEach(Object innerInnerOp) {
            return this.thenOp(new ForEach(), 
                // Inner operation of the outer ForEach operation, is another ForEach op:
                this.compositeOp(new ForEach(), 
                    // Nested inner op of the inner ForEach op, can be anything:
                    innerInnerOp));
        }

        public PipedProducer forEachOnce(Object innerInnerOp) {
            return this.thenOp(new ForEach(), 
                // Inner operation of the outer ForEach operation, is a Once op:
                this.compositeOp(new Once(), 
                    // Nested inner op of the inner Once op, can be anything:
                    innerInnerOp));
        }

        public PipedProducer onceForEach(Object innerInnerOp) {
            return this.thenOp(new Once(), 
                // Inner operation of the outer Once operation, is a ForEach op:
                this.compositeOp(new ForEach(), 
                    // Nested inner op of the inner ForEach op, can be anything:
                    innerInnerOp));
        }

        public PipedProducer onceOnce(Object innerInnerOp) {
            return this.thenOp(new Once(), 
                // Inner operation of the outer Once operation, is another Once op:
                this.compositeOp(new Once(), 
                    // Nested inner op of the inner Once op, can be anything:
                    innerInnerOp));
        }

        // =================================================================================================

        // Aliased map-{nested transform} operations:

        public PipedProducer mapp(Filter innerFilter) {
            return this.mapFilter(innerFilter);
        }

        //public PipedProducer mapp(FilterLambda innerLambda) {
        //    return this.mapFilter(innerLambda);
        //}

        public PipedProducer mapp(Reduce innerReduce) {
            return this.mapReduce(innerReduce);
        }

        public PipedProducer mapp(ReduceLambda innerLambda) {
            return this.mapReduce(innerLambda);
        }

        // Convenience methods for 2-level (nested) iteration:

        public PipedProducer mapMap(Mapper innerMapping) {
            return this.pipe(new Mapper().inner(innerMapping));
        }

        public PipedProducer mapMap(Lambda innerLambda) {
            return this.pipe(new Mapper().inner(new Mapper(innerLambda)));
        }

        public PipedProducer outputsTo(System.Type outputType) {
            this.vectorType = outputType;
            return this;
        }

        public PipedProducer pipe(PipedProducer downstream) {
            downstream.setUpstream(this);
            return downstream;
        }

        public virtual Object[] mintMutableVector() {
            if (this.vectorType != null) {
                Object rawVector = this.vectorType.newInstance();
                // TODO: we need to move away from Object[] declarations to Iterable<Object>...
                if (!(rawVector instanceof Object[])) {
                    IllegalArgument(this, 'Producer was specified a non-vector output type: ' + this.vectorType.getName());
                }
                return (Object[]) rawVector;
            }
            // Default is vector<ANY>:
            return new Object[]{};
        }

        // !! This method should be called by Func clients to kickoff execution, instead of 
        // produce(), since it ensures a root Program has been minted and set uniformly across 
        // the entire operation sequence:
        public Object go() {
            // If the root Program has not been set, mint a brand new Program and set it through 
            // the entire operation sequence, working backwards:
            Boolean setsRoot = false;
            if (this.root == null) {
                setsRoot = true;
                this.root = new Program(this.localContext ?? this.rootContext);
                this.distributeRoot();
            }

            if (setsRoot) {
                try {
                    return this.produce();
                } catch (FuncException funcError) {
                    funcError.debugTrace(funcError.getTypeName() + ': ' + funcError.getMessage());
                    throw funcError;
                } catch (Exception unexpectedError) {
                    // TODO: Factor out this trace header stuff:
                    String traceTitle = 'Unexpected ' + unexpectedError.getTypeName() 
                        + ': ' + unexpectedError.getMessage();
                    System.debug('TRACE<' + traceTitle + '>');
                    this.root.debugTrace(null);
                    System.debug('END_TRACE<' + traceTitle + '>');
                    throw unexpectedError;
                }
            } else {
                return this.produce();
            }
        }

        private void distributeRoot() {
            PipedProducer chainLink = this;
            do {
                if (chainLink.nestedInner != null && chainLink.nestedInner.root != this.root) {
                    chainLink.nestedInner.root = this.root;
                    chainLink.nestedInner.distributeRoot();
                }

                chainLink = chainLink.upstream;
                if (chainLink == null || chainLink.root == this.root) {
                    break;
                } else {
                    chainLink.root = this.root;
                }
            } while (true);
        }

        // TODO: Do we even need this method anymore? Just migrate its chaining logic to go()?
        public virtual Object produce() {
            // !! TODO: The Apex stack traces are getting NASTY, so unwind this chaining recursion with a 
            // do-while-true loop...actually, could we unwind ALL the recursion, including nestedInners?
            // Even if we needed a compile() phase? The less Apex-recursion we rely on, the better...
            Object pipedInput = this.upstream?.produce();

            // !! ALL implementors of this.pipeIn(Program, Object) are expected to handle the "nestedInner".
            // Their pipeIn(Object) implementation could be utilizing a vector-iterator, map-iterator, 
            // or scalar-iterator for it logic, and the exact invocation of "this.nestedInner" will be 
            // contingent upon this.
            return this.pipeIn(this.root, null, pipedInput);
        }

        // !! ALL implementors of this.pipeIn(Program, Object) are expected to handle the "nestedInner".
        public abstract Object pipeIn(Program program, Args outerScope, Object pipedInput);
    }

    public abstract class SourceProducer extends PipedProducer {
        public SourceProducer(String name) {
            super(name);
            this.initContext();
        }

        // A Source producer can be injected anywhere in the transformation chain, and it will 
        // override the piped input at that point.
        // TODO: consider stashing the overriden piped input in root context...
        public virtual override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // TODO: If pipedInput is null but we have a nested inner transformer, then give it a chance 
            // to magically produce something...

            // Ignore the piped input and simply supply this source provider's prescribed output:
            return this.produce();
        }

        public virtual void initContext() {
            this.rootContext = this.localContext = new Context();
        }

        public virtual override Object produce() {
            IllegalState('SourceProducer must implement produce()');
            return null;
        }
    }

    // Alias of Literal():
    public static LiteralSource Apex(Object literalValue) {
        return new LiteralSource(literalValue);
    }

    // Alias of Literal():
    public static LiteralSource Value(Object literalValue) {
        return new LiteralSource(literalValue);
    }

    public static LiteralSource Literal(Object literalValue) {
        return new LiteralSource(literalValue);
    }

    public virtual class LiteralSource extends SourceProducer {
        Object literalValue;

        public LiteralSource(Object literalValue) {
            super('ApexValue');
            this.literalValue = literalValue;
        }

        public override Object produce() {
            return this.literalValue;
        }
    }

    public static JSONSource JSON(String jsonString) {
        return new JSONSource(jsonString);
    }

    public virtual class JSONSource extends SourceProducer {
        Object jsonValue;

        public JSONSource(String jsonString) {
            super('JSON');
            if (String.isNotBlank(jsonString)) {
                try {
                    this.jsonValue = JSON.deserializeUntyped(jsonString);
                } catch (JSONException parseError) {
                    IllegalArgument(this, 'Invalid JSON string: ' + parseError.getMessage());
                }
            }
        }

        public override Object produce() {
            return this.jsonValue;
        }
    }

    public static SOQLSource SOQL(String soqlQuery) {
        return new SOQLSource(soqlQuery);
    }

    public class SOQLSource extends SourceProducer {
        String soqlQuery;
        Object[] anonBinds = new Object[]{};
        Map<String, Object> namedBinds;

        public SOQLSource(String soqlQuery) {
            super('SOQL');
            this.soqlQuery = soqlQuery;
        }

        public SOQLSource bind(Object anonVal) {
            this.anonBinds.add(anonVal);
            return this;
        }

        public SOQLSource bindAll(Object[] anonBinds) {
            this.anonBinds.addAll(anonBinds ?? new Object[]{});
            return this;
        }

        public SOQLSource bindAll(Map<String, Object> namedBinds) {
            this.namedBinds = namedBinds;
            return this;
        }

        public override Object produce() {
            SOQLContext context = StartSOQL();
            for (Object anonBind : this.anonBinds) {
                context.bind(anonBind);
            }
            if (this.namedBinds != null && this.namedBinds.keySet().size() > 0) {
                context.bindAll(this.namedBinds);
            }
            return context.query(this.soqlQuery);
        }
    }

    // Composite / delegating operation that chooses between Mapper, MapObject, and Once iterators 
    // depending on its piped input type:
    // > Vector input => Mapper iterator
    // > Map or Object input => MapObject iterator
    // > Scalar input => Once iterator
    public class ForEach extends PipedProducer {
        //Object constOutputItem;
        Mapper mapDelegate;
        MapObject mapObjectDelegate;
        Once onceDelegate;
        
        public ForEach() {
            this(null);
        }

        public ForEach(Lambda lambda) {
            super('ForEach', lambda);
        }

        //public ForEach setConstantOutputItem(Object sneech) {
        //    this.constOutputItem = sneech;
        //    return this;
        //}

        public Mapper getMapper() {
            if (this.mapDelegate == null) {
                this.mapDelegate = new Mapper(this.lambda);
                this.setDelegateProperties(this.mapDelegate);
            }
            return this.mapDelegate; 
        }

        private MapObject getMapObject() {
            if (this.mapObjectDelegate == null) {
                this.mapObjectDelegate = new MapObject(this.lambda);
                this.setDelegateProperties(this.mapObjectDelegate);
            }
            return this.mapObjectDelegate; 
        }

        private Once getOnce() {
            if (this.onceDelegate == null) {
                this.onceDelegate = new Once(this.lambda);
                this.setDelegateProperties(this.onceDelegate);
            }
            return this.onceDelegate; 
        }

        private void setDelegateProperties(PipedProducer delegate) {
            //// TODO: need to implement "constOutputItem" on each delegate...
            //if (this.constOutputItem != null) {
            //    IllegalArgument(this, 'ForEach does not yet implement marshalling a constant literal value');
            //}

            delegate.nestedInner = this.nestedInner;
            delegate.localContext = this.localContext;
            delegate.vectorType = this.vectorType;
            //delegate.rootContext = this.rootContext;
            // TODO: is this really necessary?
            if (this.upstream != null) {
                delegate.setUpstream(this.upstream);
            } else {
                delegate.rootContext = this.rootContext;
            }
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            } else {
                // Last 4 args: (value=pipedInput, item=null, key=null, index=null):
                Args thisOpFrame = new Args(program, outerScope, this, pipedInput);
                Object output;

                // !! Note that as we invoke a destination iterator operation below, we forward along 
                // the `outerScope` instead of the newly minted ForEach scope `thisOpFrame`. That is 
                // intentional, so we don't add an extra parent scope to the chain for "$(outer.)" 
                // reference expressions to have to reach through. 

                // Any vector invokes map() (Mapper - i.e. array iteration):
                if (pipedInput instanceof Iterable<Object>) {
                    output = this.getMapper().pipeIn(program, outerScope, pipedInput);
                // Any Map structure (with iterable keys/values) invokes mapObject(), i.e. key-value 
                // iteration:
                } else if (pipedInput instanceof Map<String, Object> || pipedInput instanceof KeyValue 
                        || pipedInput instanceof MapIterable || pipedInput instanceof sObject) {
                    output = this.getMapObject().pipeIn(program, outerScope, pipedInput);
                // Scalar invokes once(), i.e. a 1-it iteration:
                } else {
                    output = this.getOnce().pipeIn(program, outerScope, pipedInput);
                }

                // Frame-closing and return:
                program.close(thisOpFrame);
                return output;
            }
        }
    }

    public virtual class Mapper extends PipedProducer {
        public Mapper() {
            this(null);
        }

        public Mapper(Lambda lambda) {
            super('Map<Vector-Iterator>', lambda);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }
            // Last 4 args: (value=pipedInput, item=null, key=null, index=null). "value" == "item" 
            // and "index" will be set per-iteration before lambda execution:
            Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                // $ => item, $$ => index:
                .anonBindings('item', 'index', null);
            Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();
            
            Object output;
            // Generic vector:
            if (pipedInput instanceof Iterable<Object>) {
                Object[] marshalled;
                // Generic read-write vector:
                if (this.preserveUpstreamVectorType && pipedInput instanceof Object[]) {
                    // Preserve original collection-type by cloning and then clearing:
                    output = marshalled = ((Object[]) pipedInput).clone();
                    marshalled.clear();
                // Generic read-only vector:
                } else {
                    // Ask this instance to mint its preferred vector collection-type; default is 
                    // vector<ANY> (a.k.a. Object[]): 
                    output = marshalled = this.mintMutableVector();
                }
                
                Integer index = 0;
                for (Object pipedElmt : (Iterable<Object>) pipedInput) {
                    // Set the appropriate formal arg values for this iteration:
                    thisOpFrame.value = pipedElmt;
                    thisOpFrame.item = pipedElmt;
                    thisOpFrame.index = index;
                    if (this.nestedInner != null) {
                        // To perform a nested-inner operation:
                        // 1. Save the current stack Frame that will serve as parent to the inner op's Frame
                        // 2. Dispatch the inner op - it will internally mint its own Frame(s)
                        // 3. Restore Program Stack to the Frame from step 1
                        Args parentFrame = program.currentFrame; // program.stack[program.top];
                        pipedElmt = this.nestedInner.pipeIn(program, thisOpFrame, pipedElmt);
                        // Update the "value", "item" formal args if it was mutated by the nested-inner op:
                        thisOpFrame.value = thisOpFrame.item = pipedElmt;
                        program.closeAfter(parentFrame);
                    }
                    if (lambdaFrame != null) {
                        // Copy the formal args we've maintained in thisOpFrame over to the lambdaFrame:
                        lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                        marshalled.add(this.lambda.eval(lambdaFrame));
                    } else {
                        marshalled.add(pipedElmt);
                    }
                    index++;
                }
                // Fallthrough to close this Frame - marshalled was already assigned into output...
            
            // Scalar:
            } else {
                // Set the appropriate formal arg values for this iteration:
                thisOpFrame.value = pipedInput;
                thisOpFrame.item = pipedInput;
                thisOpFrame.index = 0;
                if (this.nestedInner != null) {
                    // See above comment on safe nested-inner op dispatch
                    // TODO: need to factor out this dispatch logic as it is a common problem...
                    Args parentFrame = program.currentFrame;
                    pipedInput = this.nestedInner.pipeIn(program, thisOpFrame, pipedInput);
                    // Update the "value", "item" formal args if it was mutated by the nested-inner op:
                    thisOpFrame.value = thisOpFrame.item = pipedInput;
                    program.closeAfter(parentFrame);
                }
                if (lambdaFrame != null) {
                    // Copy the formal args we've maintained in thisOpFrame over to the lambdaFrame:
                    lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                    output = this.lambda.eval(lambdaFrame);
                } else {
                    // A scalar value with no lambda degrades to the identity transformation:
                    output = pipedInput;
                }
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return output;
        }
    }

    public virtual class MapObject extends PipedProducer {
        public MapObject() {
            this(null);
        }

        public MapObject(Lambda lambda) {
            super('MapObject', lambda);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Input must be: NULL, MapIterable, KeyValue, Map<String, Object> or sObject
            if (pipedInput == null) {
                // Null forwarding:
                return null;
            } else {
                // Last 4 args: (value=pipedInput, item=null, key=null, index=null):
                Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                    // $ => value, $$ => key, $$$ => index:
                    // !! Note how we leave "item", a KeyValuePair, out of anon bindings!
                    .anonBindings('value', 'key', 'index');
                Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();
                
                //Map<String, Object> marshalled = new Map<String, Object>();
                Map<String, Object> marshalled;
                if (this.vectorType == null) {
                    marshalled = new Map<String, Object>();
                } else {
                    // If we were given an invalid vectorType (which is a misnomer here), this will throw 
                    // a ClassCastException:
                    marshalled = (Map<String, Object>) this.vectorType.newInstance();
                }
                if (pipedInput instanceof Map<String, Object>) {
                    Map<String, Object> inputMap = (Map<String, Object>) pipedInput;
                    for (String key : inputMap.keySet()) {
                        mapObjectMarshal(program, thisOpFrame, this, lambdaFrame, key, inputMap.get(key), null, marshalled);
                    }
                } else if (pipedInput instanceof KeyValue) {
                    mapObjectMarshal(program, thisOpFrame, this, lambdaFrame, (KeyValue) pipedInput, marshalled);
                } else if (pipedInput instanceof MapIterable) {
                    MapIterable inputMapIterable = (MapIterable) pipedInput;
                    for (KeyValue kv : inputMapIterable.keyValues()) {
                        mapObjectMarshal(program, thisOpFrame, this, lambdaFrame, kv, marshalled);
                    }
                } else if (pipedInput instanceof sObject) {
                    Map<String, Object> inputMap = ((sObject) pipedInput).getPopulatedFieldsAsMap();
                    for (String key : inputMap.keySet()) {
                        mapObjectMarshal(program, thisOpFrame, this, lambdaFrame, key, inputMap.get(key), null, marshalled);
                    }
                } else {
                    IllegalArgument(this, 'MapObject expected Map or Object input, got: ' + pipedInput);
                }

                // Frame-closing and return:
                program.close(thisOpFrame);
                return marshalled;
            }
        }
    }

    static void mapObjectMarshal(Program program, Args operationFrame, MapObject operation, Args lambdaFrame, 
            KeyValue kv, Map<String, Object> marshalled) {
                mapObjectMarshal(program, operationFrame, operation, lambdaFrame, kv.key, kv.value, kv.index, marshalled);
    }

    static void mapObjectMarshal(Program program, Args operationFrame, MapObject operation, Args lambdaFrame, 
            String key, Object itemValue, Integer index,
            Map<String, Object> marshalled) {

        // Set the appropriate formal arg values for this iteration:
        operationFrame.item = new KeyValue(key, itemValue); // itemValue;
        operationFrame.key = key;
        operationFrame.value = itemValue;
        operationFrame.index = index;
        
        if (operation.nestedInner != null) {
            // To perform a nested-inner operation:
            // 1. Save the current stack Frame that will serve as parent to the inner op's Frame
            // 2. Dispatch the inner op - it will internally mint its own Frame
            // 3. Restore Program Stack to the Frame from step 1
            Args parentFrame = program.currentFrame; // program.stack[program.top];
            // !! Though we only directly route "itemValue" into the nested-inner op, outer-scope values are
            // accessible via $(outer.) reference syntax: 
            itemValue = operation.nestedInner.pipeIn(program, operationFrame, itemValue);
            // Update the "value" and "item" formal args if mutated by the nested-inner op:
            operationFrame.item = new KeyValue(key, itemValue);
            operationFrame.value = itemValue;
            program.closeAfter(parentFrame);
        }
        if (lambdaFrame != null) {
            // Copy the formal args we've maintained in operationFrame over to the lambdaFrame:
            lambdaFrame.copyFormalArgsFrom(operationFrame);
            Object output = operation.lambda.eval(lambdaFrame);
            if (output instanceof KeyValue) {
                KeyValue keyValOut = (KeyValue) output;
                marshalled.put(keyValOut.key, keyValOut.value);
            } else if (output instanceof Map<String, Object>) {
                Map<String, Object> mapOut = (Map<String, Object>) output;
                for (String keyOut : mapOut.keySet()) {
                    marshalled.put(keyOut, mapOut.get(keyOut));
                }
            } else if (output instanceof MapIterable) {
                MapIterable mapItOut = (MapIterable) output;
                for (KeyValue keyValOut : mapItOut.keyValues()) {
                    marshalled.put(keyValOut.key, keyValOut.value);
                }
            } else {
                // !! TODO: What IF when "output" is a scalar value, we marshalled it out under the original key?
                //    This is not DataWeave beahvior (which strictly enforces MapObjectLambda returning a Map / Object 
                //    type), but I kind of like it!
                // !! TODO: Should this behavior be an option / directive on the Context? OR should this be switched 
                //    ON for the more flexible ForEach iterator, and OFF for the more strict MapObject?
                //IllegalArgument(operation, 'MapObject expected Map output from MappedObjectLambda, got: ' + output);
                marshalled.put(key, output);
            }
        } else {
            marshalled.put(key, itemValue);
        }
    }

    public virtual class Once extends PipedProducer {
        public Once() {
            this(null);
        }

        public Once(Lambda lambda) {
            super('Once', lambda);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            Object scalar;
            // Any vector evals on just the 1st element:
            if (pipedInput instanceof Iterable<Object>) {
                for (Object elmt : (Iterable<Object>) pipedInput) {
                    scalar = elmt;
                    break;
                }
            // Any Map structure (with iterable keys/values) evals just once on the whole map. 
            // This does NOT iterate on its key-values - i.e. it's treated exactly as a scalar value, 
            // along with other custom class structures and primitive value types:
            } else {
                scalar = pipedInput;
            }

            // "value", "item" and "index" will be set at the start of each marshal():
            Args thisOpFrame = new Args(program, outerScope, this)
                // $ => item, $$ => index == 0:
                .anonBindings('item', 'index', null);
            Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

            // The marshal() method would start here, if we needed one for once():
            thisOpFrame.item = scalar;
            thisOpFrame.index = 0;

            if (this.nestedInner != null) {
                Args parentFrame = program.currentFrame;
                scalar = this.nestedInner.pipeIn(program, thisOpFrame, scalar);
                // Update the "value" and "item" formal args if scalar was mutated by the nested-
                // inner operation:
                thisOpFrame.value = scalar;
                thisOpFrame.item = scalar;
                program.closeAfter(parentFrame);
            }

            Object output;
            if (lambdaFrame != null) {
                // Copy formal args from the operation frame to its lambda frame:
                lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                output = this.lambda.eval(lambdaFrame);
            } else {
                // A scalar value with no lambda degrades to the identity transformation:
                output = scalar;
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return output;
        }
    }

    public virtual class Reduce extends PipedProducer {
        public Reduce() {
            this(null);
        }

        public Reduce(ReduceLambda lambda) {
            super('Reduce', lambda);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // !! Inner lambdas should only apply INSIDE the outer operation's iterator, and since NO
            // interation occurs for a null input, the inner lambda should NOT be evaluated in that 
            // case...

            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            // "value", "item" and "index" will be set immediately before eval:
            Args thisOpFrame = new Args(program, outerScope, this)
                // $ => item, $$ => value, $$$ => index:
                // "value" maps to the accumulator
                .anonBindings('item', 'value', 'index');
            Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

            Object aggregator;
            // The init() phase of reduce sets up the aggregator, and has to happen even before any 
            // nested-inner:
            thisOpFrame.value = null;
            thisOpFrame.index = -1;
            if (lambdaFrame != null) {
                lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                if (this.lambda instanceof InitializingLambda) {
                    // The return of init() is used as the aggregator value (which maps to Args.value)!
                    aggregator = ((InitializingLambda) this.lambda).init(lambdaFrame);
                }
                // Update the "value" formal arg for both operation and lambda frames, upon its 
                // initialization:
                thisOpFrame.value = lambdaFrame.value = aggregator;
            
            // If no Lambda, then aggregator gets set to the whole pipedInput value and this operation 
            // will effectively degrade to no-op (forwards pipedInput as-is), in the absence of a 
            // nested-inner op:
            } else {
                // TODO: is this right? It will retain the original value if there is no lambda...
                aggregator = thisOpFrame.value = pipedInput;
            }

            // !! TODO: A nested-inner op, in the absence of a lambda, will be executed (per element) but
            // its results will be ignored, and the pipedInputs will be forwarded out with no mutations - 
            // despite the inner op's efforts. It might be worth considering how this scenario could be 
            // handled by allowing the inner op to transform elements, and returning a new Vector (or 
            // Scalar) of these transformed elements...

            // Vector input:
            if (pipedInput instanceof Iterable<Object>) {
                Integer index = 0;
                for (Object pipedElmt : (Iterable<Object>) pipedInput) {
                    thisOpFrame.item = pipedElmt;
                    thisOpFrame.index = index;
                    // Note that nested-inner can only mutate the next "item" for ReduceLambda.eval; it 
                    // never directly affects the accumulator value. Therefore, when this.lambda is null,
                    // this reduce() operation will be a no-op even if the nested-inner does something. 
                    if (this.nestedInner != null) {
                        Args parentFrame = program.currentFrame;
                        pipedElmt = this.nestedInner.pipeIn(program, thisOpFrame, pipedElmt);
                        // Update the "item" formal arg if it was mutated by the nested-inner op:
                        thisOpFrame.item = pipedElmt;
                        program.closeAfter(parentFrame);
                    }
                    if (lambdaFrame != null) {
                        // Copy the formal args we've maintained in thisOpFrame over to the lambdaFrame:
                        lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                        // Args.value is how the ReduceLambda.eval accesses the aggregator value:
                        aggregator = thisOpFrame.value = lambdaFrame.value = this.lambda.eval(lambdaFrame);
                    }
                    index++;
                }
            // Map, Object, or Scalar input:
            } else {
                thisOpFrame.item = pipedInput;
                thisOpFrame.index = 0;
                // Note that nested-inner can only mutate the next "item" for ReduceLambda.eval; it 
                // never directly affects the accumulator value. Therefore, when this.lambda is null,
                // this reduce() operation will be a no-op even if the nested-inner does something. 
                if (this.nestedInner != null) {
                    Args parentFrame = program.currentFrame;
                    pipedInput = this.nestedInner.pipeIn(program, thisOpFrame, pipedInput);
                    // Update the "item" formal arg if it was mutated by the nested-inner op:
                    thisOpFrame.item = pipedInput;
                    program.closeAfter(parentFrame);
                }
                if (lambdaFrame != null) {
                    // Copy the formal args we've maintained in thisOpFrame over to the lambdaFrame:
                    lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                    // Args.value is how the ReduceLambda.eval accesses the aggregator value:
                    aggregator = thisOpFrame.value = lambdaFrame.value = this.lambda.eval(lambdaFrame);
                }
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return aggregator;
        }
    }

    // =================================================================================================

    // !! We now parse $(ReferenceExpression) syntax instead of automatically interpreting every string 
    // as a Reference Expression. The ref expression resolves against an Args context, where the GroupBy 
    // (item, index) is set in Args.item and Args.index. If the $() syntax is invalid (e.g. unclosed) 
    // then a ReferenceException is thrown out. If the "literalOrEnclosedRefExpr" does NOT start with a 
    // `$(` char sequence, then it is interpreted as a literal group name, and the output of this 
    // operation will be a Map with single key set to that literal, and value set to the array 
    // concatenation of all items.
    public virtual class GroupBy extends PipedProducer {
        public GroupBy() {
            this(null);
        }

        public GroupBy(Lambda lambda) {
            super('GroupBy', lambda);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Input must be: NULL, MapIterable, KeyValue, Map<String, Object> or sObject
            if (pipedInput == null) {
                // Null forwarding:
                return null;
            } else {
                // "value", "item", "key", and "index" will be set immediately before eval:
                Args thisOpFrame = new Args(program, outerScope, this)
                    // $ => item, $$ => index:
                    .anonBindings('item', 'index', null);
                Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

                Map<String, Object[]> vectorMarshalled;
                Map<String, Map<String, Object>> mapMarshalled;
                if (pipedInput instanceof Iterable<Object>) {
                    vectorMarshalled = new Map<String, Object[]>();
                    Integer index = 0;
                    for (Object pipedElmt : (Iterable<Object>) pipedInput) {
                        groupByMarshal(program, thisOpFrame, this, lambdaFrame, 
                            pipedElmt, String.valueOf(index), index, vectorMarshalled, null);
                        index++;
                    }
                } else {
                    mapMarshalled = new Map<String, Map<String, Object>>();
                    if (pipedInput instanceof Map<String, Object>) {
                        Map<String, Object> inputMap = (Map<String, Object>) pipedInput;
                        Integer index = 0;
                        for (String key : inputMap.keySet()) {
                            // TODO: this index may not be consistent!
                            groupByMarshal(program, thisOpFrame, this, lambdaFrame, 
                                inputMap.get(key), key, index, null, mapMarshalled);
                            index++;
                        }
                    } else if (pipedInput instanceof KeyValue) {
                        groupByMarshal(program, thisOpFrame, this, lambdaFrame, 
                            (KeyValue) pipedInput, null, mapMarshalled);
                    } else if (pipedInput instanceof MapIterable) {
                        MapIterable inputMapIterable = (MapIterable) pipedInput;
                        for (KeyValue kv : inputMapIterable.keyValues()) {
                            groupByMarshal(program, thisOpFrame, this, lambdaFrame, 
                                kv, null, mapMarshalled);
                        }
                    } else if (pipedInput instanceof sObject) {
                        Map<String, Object> inputMap = ((sObject) pipedInput).getPopulatedFieldsAsMap();
                        Integer index = 0;
                        for (String key : inputMap.keySet()) {
                            groupByMarshal(program, thisOpFrame, this, lambdaFrame, 
                                inputMap.get(key), key, index++, null, mapMarshalled);
                        }
                    } else {
                        IllegalArgument(this, 
                            'GroupBy expected input Vector, Map, or Object; got: ' + pipedInput);
                    }
                }

                // Frame-closing and return:
                program.close(thisOpFrame);
                return (Object) vectorMarshalled ?? (Object) mapMarshalled;
            }
        }
    }

    static void groupByMarshal(Program program, Args operationFrame, GroupBy operation, 
            Args groupNameFrame, 
            KeyValue keyValueItem, 
            Map<String, Object[]> vectorMarshalled, 
            Map<String, Map<String, Object>> mapMarshalled) {
        groupByMarshal(program, operationFrame, operation, groupNameFrame, 
            keyValueItem.value, keyValueItem.key, keyValueItem.index, 
            vectorMarshalled, mapMarshalled);
    }

    static void groupByMarshal(Program program, Args operationFrame, GroupBy operation, 
            Args groupNameFrame, 
            Object item, String key, Integer index,
            Map<String, Object[]> vectorMarshalled, 
            Map<String, Map<String, Object>> mapMarshalled) {
        
        // Set the appropriate formal arg values for this iteration:
        operationFrame.value = item;
        operationFrame.item = item;
        operationFrame.key = key;
        operationFrame.index = index;

        if (operation.nestedInner != null) {
            Args parentFrame = program.currentFrame;
            item = operation.nestedInner.pipeIn(program, operationFrame, item);
            // Update the "value" and "item" formal args if it was mutated by the nested-inner op:
            operationFrame.value = operationFrame.item = item;
            program.closeAfter(parentFrame);
        }
        
        String groupName;
        // If we have a group-name lambda, evaluate it now to get the item's corresponding 
        // group-name key:
        if (groupNameFrame != null) {
            // Copy the formal args we've maintained in operationFrame over to the lambdaFrame 
            // before its eval(): 
            groupNameFrame.copyFormalArgsFrom(operationFrame);
            Object groupKey = groupNameFrame.lambda.eval(groupNameFrame);
            if (groupKey instanceof String) {
                groupName = (String) groupKey;
            // !! TODO: This represents a notable break from DataWeave beahvior: 
            // 1. Stringify an sObject by its Id (empty string if null)
            // 2. Stringify ANY other object type using Object.toString()
            // 3. Stringify null to the empty string "":
            } else if (groupKey instanceof sObject) {
                groupName = ((sObject) groupKey).Id ?? '';
            } else {
                // TODO: Should we throw an IllegalArgument for certain types, or just continue 
                // allowing stringification of any type?
                groupName = groupKey?.toString() ?? '';
            }
        // Else group-name defaults to the empty string :-(
        } else {
            groupName = ''; //groupNameConst ?? '';
        }

        if (vectorMarshalled != null) {
            Object[] vectorGroup = vectorMarshalled.get(groupName);
            if (vectorGroup == null) {
                vectorMarshalled.put(groupName, vectorGroup = new Object[]{});
            }
            // Add the original "item" to the target vectorGroup. Note "item" may only have 
            // been mutated by an operation.nestedInner:
            vectorGroup.add(item);
        } else if (mapMarshalled != null) {
            Map<String, Object> mapGroup = mapMarshalled.get(groupName);
            if (mapGroup == null) {
                mapMarshalled.put(groupName, mapGroup = new Map<String, Object>());
            }
            // Put the original { key, item } pair in the target mapGroup. Note "item" may only 
            // have been mutated by an operation.nestedInner:
            mapGroup.put(key, item);
        }
    }

    // =================================================================================================

    public virtual class KeysOf extends PipedProducer {
        public KeysOf() {
            this(null);
        }

        public KeysOf(Lambda lambda) {
            super('KeysOf', lambda);
            this.outputsTo(String[].class);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            // "item" and "index" will be set immediately before eval:
            Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                // $ => item, $$ => index:
                .anonBindings('item', 'index', null);
            // Get the raw keys in a vector. For this initial phase, a generic vector<ANY> will do:
            Object[] preMarshalled = new Object[]{};
            // Input must be Map or Object:
            if (pipedInput instanceof Map<String, Object>) {
                // Ugh, look at what Apex makes us do to convert Set<String> to List<Object>:
                preMarshalled.addAll(
                    (Object[]) new List<String>(
                        ((Map<String, Object>) pipedInput).keySet()));
            } else if (pipedInput instanceof KeyValue) {
                preMarshalled.add(((KeyValue) pipedInput).key);
            } else if (pipedInput instanceof MapIterable) {
                for (KeyValue kv : ((MapIterable) pipedInput).keyValues()) {
                    preMarshalled.add(kv.key);
                }
            } else if (pipedInput instanceof sObject) {
                // Ugh, look at what Apex makes us do to convert Set<String> to List<Object>:
                preMarshalled.addAll(
                    (Object[]) new List<String>(
                        ((sObject) pipedInput).getPopulatedFieldsAsMap().keySet()));
            } else {
                IllegalArgument(this, 'KeysOf expected input Map or Object, got: ' + pipedInput);
            }

            Object[] marshalled = this.mintMutableVector();
            if (this.nestedInner != null || this.lambda != null) {
                Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

                // Marshal the values one-by-one, invoking nested-inner and/or lambda as necessary:
                Integer index = 0;
                for (Object item : preMarshalled) {
                    keyOrValueMarshal(program, thisOpFrame, this, lambdaFrame, item, null, index, marshalled);
                    index++;
                }
            } else {
                // Else if there is no nested-inner nor lambda, we can simply copy all keys over 
                // to the marshalled output vector:
                marshalled.addAll(preMarshalled);
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return marshalled;
        }
    }

    public virtual class ValuesOf extends PipedProducer {
        public ValuesOf() {
            this(null);
        }

        public ValuesOf(Lambda lambda) {
            super('ValuesOf', lambda);
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            // "item" and "index" will be set immediately before eval:
            Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                // $ => item, $$ => index:
                .anonBindings('item', 'index', null);
            // Get the raw values in a vector. For this initial phase, a generic vector<ANY> will do:
            Object[] preMarshalled = new Object[]{};
            // Input must be Map or Object:
            if (pipedInput instanceof Map<String, Object>) {
                preMarshalled.addAll(((Map<String, Object>) pipedInput).values());
            } else if (pipedInput instanceof KeyValue) {
                preMarshalled.add(((KeyValue) pipedInput).value);
            } else if (pipedInput instanceof MapIterable) {
                for (KeyValue kv : ((MapIterable) pipedInput).keyValues()) {
                    preMarshalled.add(kv.value);
                }
            } else if (pipedInput instanceof sObject) {
                preMarshalled.addAll(((sObject) pipedInput).getPopulatedFieldsAsMap().values());
            } else {
                IllegalArgument(this, 'ValuesOf expected input Map or Object, got: ' + pipedInput);
            }

            Object[] marshalled = this.mintMutableVector();
            if (this.nestedInner != null || this.lambda != null) {
                Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

                // Marshal the values one-by-one, invoking nested-inner and/or lambda as necessary:
                Integer index = 0;
                for (Object item : preMarshalled) {
                    keyOrValueMarshal(program, thisOpFrame, this, lambdaFrame, item, null, index, marshalled);
                    index++;
                }
            } else {
                // Else if there is no nested-inner nor lambda, we can simply copy all values over 
                // to the marshalled output vector:
                marshalled.addAll(preMarshalled);
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return marshalled;
        }
    }

    static void keyOrValueMarshal(Program program, Args operationFrame, PipedProducer operation, Args lambdaFrame, 
            Object item, String key, Integer index, Object[] marshalled) {
        
        // Set the appropriate formal arg values for this iteration:
        operationFrame.item = item;
        operationFrame.key = key;
        operationFrame.index = index;

        if (operation.nestedInner != null) {
            Args parentFrame = program.currentFrame;
            item = operation.nestedInner.pipeIn(program, operationFrame, item);
            // Update the "item" formal arg if it was mutated by the nested-inner op:
            operationFrame.item = item;
            program.closeAfter(parentFrame);
        }
        if (lambdaFrame != null) {
            // Copy the formal args we've maintained in operationFrame over to the lambdaFrame 
            // before its eval(): 
            lambdaFrame.copyFormalArgsFrom(operationFrame);
            item = lambdaFrame.lambda.eval(lambdaFrame);
        }
        marshalled.add(item);
    }

    public virtual class Filter extends PipedProducer {
        Boolean negate = false;

        public Filter() {
            this(null);
        }

        public Filter(Lambda lambda) {
            super('Filter', lambda);
            this.preserveUpstreamVectorType = true;
        }

        // Turns this operation into a filterNot():
        public Filter negate() {
            this.negate = !this.negate;
            return this;
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            // "item" and "index" will be set immediately before eval:
            Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                // $ => item, $$ => index:
                .anonBindings('item', 'index', null);
            Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

            Object output;
            // Vector input:
            if (pipedInput instanceof Iterable<Object>) {
                Object[] marshalled;
                if (this.preserveUpstreamVectorType && pipedInput instanceof Object[]) {
                    // Preserve original collection-type by cloning and then clearing:
                    marshalled = ((Object[]) pipedInput).clone();
                    marshalled.clear();
                } else {
                    marshalled = this.mintMutableVector();
                }
                output = marshalled;
                Integer index = 0;
                for (Object pipedElmt : (Iterable<Object>) pipedInput) {
                    filteredMarshal(program, thisOpFrame, this, lambdaFrame, pipedElmt, index, marshalled);
                    index++;
                }
    
            // Map, Object, or Scalar input:
            } else {
                Object[] scalarBox = new Object[]{};
                filteredMarshal(program, thisOpFrame, this, lambdaFrame, pipedInput, 0, scalarBox);
                output = scalarBox.isEmpty() ? null : scalarBox[0];
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return output;
        }
    }

    static void filteredMarshal(Program program, Args operationFrame, Filter operation, Args lambdaFrame, 
            Object item, Integer index, Object[] marshalled) {
        
        // Set the appropriate formal arg values for this iteration:
        operationFrame.item = item;
        operationFrame.index = index;

        if (operation.nestedInner != null) {
            Args parentFrame = program.currentFrame;
            item = operation.nestedInner.pipeIn(program, operationFrame, item);
            // Update the "item" formal arg if it was mutated by the nested-inner op:
            operationFrame.item = item;
            program.closeAfter(parentFrame);
        }
        if (lambdaFrame != null) {
            // Copy the formal args we've maintained in operationFrame over to the lambdaFrame 
            // before its eval():
            lambdaFrame.copyFormalArgsFrom(operationFrame);
            Object testResult = lambdaFrame.lambda.eval(lambdaFrame);
            // Inspired by ECMAScript's truthy / falsey logic to convert ANY type to Boolean:
            Boolean boolResult = testResult == true 
                || (testResult != null && testResult != false && testResult != 0.0 && testResult != '');
            // Result must be flipped if negation flag was set:
            if (boolResult == !operation.negate) {
                marshalled.add(item);
            }
        } else {
            marshalled.add(item);
        }
    }

    public virtual class DebugTrace extends PipedProducer {
        String title;

        public DebugTrace() {
            this(null);
        }

        public DebugTrace(String title) {
            super('DebugTrace');
            this.title = title;
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {            
            String traceTitle = this.title != null ? this.title : 'Anon';
            System.debug('TRACE<' + traceTitle + '>');
            System.debug('Input: ' + (pipedInput ?? (Object) '<Forwarded Null>'));

            Args thisOp = new Args(program, outerScope, this, pipedInput);
            program.debugTrace(null);
            program.close(thisOp);
            System.debug('END_TRACE<' + traceTitle + '>');

            return pipedInput;
        }
    }

    static final Pattern ClassNamePatt = Pattern.compile('[a-zA-Z][a-zA-Z0-9_]*+');

    static String getClassName(Object customType) {
        if (customType == null) {
            return 'Null';
        }
        String name = String.valueOf(customType);
        if (String.isNotBlank(name)) {
            Matcher m = ClassNamePatt.matcher(name);
            if (m.find()) {
                return m.group(0);
            }
        }
        return '<UnknownType>';
    }

    // TODO: implement outerScope beyond this point...

    // Flatten is similar to Reduce and could have been implemented that way, but decided to 
    // instead make a custom derivation of PipedProducer because of its inherently recursive 
    // nature:
    public virtual class Flatten extends PipedProducer {
        public Flatten() {
            this(null);
        }

        public Flatten(Lambda lambda) {
            super('Flatten', lambda);
        }

        public virtual override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            // "item" and "index" will be set immediately before eval:
            Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                // $ => item, $$ => index:
                .anonBindings('item', 'index', null);

            Iterable<Object> preMarshalled;
            // Vector input:
            if (pipedInput instanceof Iterable<Object>) {
                preMarshalled = (Iterable<Object>) pipedInput;
            // Map, Object, or Scalar input:
            } else {
                preMarshalled = new Object[]{ pipedInput };
            }

            Object[] marshalled = this.mintMutableVector();
            Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();
            Integer index = 0;
            for (Object item : preMarshalled) {
                flattenMarshal(program, thisOpFrame, this, lambdaFrame, item, index, marshalled);
                index++;
            }

            // Frame-closing and return:
            program.close(thisOpFrame);
            return marshalled;
        }
    }

    public static void flattenMarshal(Program program, Args operationFrame, PipedProducer operation, Args lambdaFrame, 
            Object item, Integer index, Object[] marshalled) {

        // Set the appropriate formal arg values for this iteration:
        operationFrame.item = item;
        operationFrame.index = index;

        if (operation.nestedInner != null) {
            Args parentFrame = program.currentFrame;
            item = operation.nestedInner.pipeIn(program, operationFrame, item);
            // Update the "item" formal arg if it was mutated by the nested-inner op:
            operationFrame.item = item;
            program.closeAfter(parentFrame);
        }
        if (lambdaFrame != null) {
            // Copy the formal args we've maintained in operationFrame over to the lambdaFrame 
            // before its eval():
            lambdaFrame.copyFormalArgsFrom(operationFrame);
            item = lambdaFrame.lambda.eval(lambdaFrame);
        }

        // If item is itself a Vector, we must recurse on its elements!
        if (item instanceof Iterable<Object>) {

            // !! Instead of dispatching a new nestedLambdaFrame for each recursion depth, we re-use 
            // the existing lambdaFrame. The lambdaFrame's formal arguments { item, index } can be 
            // overwritten by the recursion(s), as we do not need them again here. However, if we DID 
            // need them again, we could simply re-set them upon returning from the recursive call!
            Integer nestedIndex = 0;
            for (Object nestedItem : (Iterable<Object>) item) {
                flattenMarshal(program, operationFrame, operation, lambdaFrame, 
                    nestedItem, nestedIndex, marshalled);
                nestedIndex++;
            }

        // Else item is a Map, Object, or Scalar - and we can directly marshal it out as 1 element:
        } else {
            marshalled.add(item);
        }
    }

    // TODO: Not sure I really want this to always start with a recursive Flatten - it might be 
    // better as a switchable option, or the ability to turn off recursive Flattening...
    public class Coalesce extends Flatten {
        Integer coalesceLimit = 200;

        public Coalesce() {
            this(null);
        }

        public Coalesce(Integer lmt) {
            this.name = 'Coalesce';
            this.lmt(lmt);
        }
        
        public Coalesce lmt(Integer lmt) {
            this.coalesceLimit = lmt ?? 200;
            return this;
        }

        public override Object pipeIn(Program program, Args outerScope, Object input) {
            // Null forwarding:
            if (input == null) {
                return null;
            }
            // TODO: We're adding a Frame for this Coalesce, and then Flatten operation will stack
            // atop that as it executes and clean itself up by the time its super.pipeIn() call 
            // returns. Is that what we want here, or will it be confusing?
            Args thisOpFrame = new Args(program, outerScope, this, input);
            // TODO: No anonymous param bindings here?
            // !! Note this coalesce op doesn't dispatch its own lambdaFrame, but its (superclass) 
            // Flatten.pipeIn() will do so.
            // TODO: consider if we really need a Coalesce -> Flatten on the program stack, or will
            // just "Coalesce" do, and how best to clean that up? Note that a Lambda which tries to 
            // access Args / scope outside the Coalesce will need an extra ".outer" to reach past 
            // the inner Flatten :-(
            Object flattened = super.pipeIn(program, thisOpFrame, input);
            Iterable<Object> preMarshalled;
            Object[] groupPrototype;
            // Flattened result is a Vector:
            if (flattened instanceof Iterable<Object>) {
                preMarshalled = (Iterable<Object>) flattened;
                if (this.preserveUpstreamVectorType && flattened instanceof Object[]) {
                    groupPrototype = ((Object[]) flattened).clone();
                    groupPrototype.clear(); 
                }
            // Flattened result is a Map, Object, or Scalar:
            } else if (flattened != null) {
                preMarshalled = new Object[]{ flattened };
            // Flattened result is null :-(
            } else {
                preMarshalled = new Object[]{};
            }

            if (groupPrototype == null) {
                groupPrototype = this.mintMutableVector();
            }
            //List<Object[]> outputGroups = new List<Object[]>();
            Object[] marshalled = new Object[]{};
            Object[] currentGroup;
            for (Object item : preMarshalled) {
                if (currentGroup == null || currentGroup.size() >= this.coalesceLimit) {
                    currentGroup = groupPrototype.clone();
                    marshalled.add(currentGroup);
                }
                currentGroup.add(item);
            }

            program.close(thisOpFrame);
            return marshalled;
        }
    }

    // TODO: Should Cat be able to be recursive, like Flatten? Then it would need to be a 
    // custom PipedProducer derivation. And then, we might be looking at a new 
    // RecursivePipedProducer base class...
    public class Cat extends Reduce {
        public Cat() {
            this(null);
        }

        public Cat(String separator) {
            super(new CatLambda(separator));
            this.name = 'Cat';
        }
    }

    public class CatLambda implements ReduceLambda {
        String[] words;
        String separator;

        public CatLambda() {
            this(null);
        }

        public CatLambda(String sep) {
            this.separator = sep ?? '';
        }

        public Object init(Args argv) {
            this.words = new String[]{};
            return '';
        }

        public Object eval(Args argv) {
            if (argv.item != null) {
                this.words.add(argv.itemToString());
            }
            // TODO: It's not really efficient to do the join() after EVERY reduce item. 
            // Maybe add a "numItems" property to Args for use by these kind of ReduceLambdas?
            return String.join(this.words, this.separator);
        }
    }

    static Lambda parseRefOrLitToLambda(Args hostFrame, PipedProducer hostOp, 
            String refExprOrLiteral) {
        Lambda lambda = parseDollaRefExpr(hostFrame, hostOp, refExprOrLiteral);
        // If the passed string successfully parses as a "dolla-ref" expression, then "lambda" will 
        // presently hold the Lambda impl (instanceof ReferenceExprLambda) that can evaluate it. 
        // Else If the string does NOT parse, then the parseDollaRefExpr() call will either:
        // 1. Throw a ReferenceException if it started with a "$", "$$", "$$$", or "$(" by was NOT 
        //    valid ref syntax
        // 2. Return null if it didn't start like a ref (i.e. didn't start with a "$" and therefore 
        //    doesn't look like a ref) - then it can be unambigupously interpreted as a string 
        //    literal value.
        if (lambda == null) {
            // Wrap the (unambiguous) string literal value in a Lambda:
            lambda = new LiteralLambda(refExprOrLiteral);
        }
        return lambda;
    }
    
    // Parses a path expression out of format: $({PathExpression}) and captures the full enclosed path:
    private static final Pattern EnclosedPathExpressionPatt = Pattern.compile('\\$\\(([^\\)]++)\\)$');
    // Parses a path expression out of format: {AnonymousParameter}.{PathExpression} and captures both 
    // the anonymous parameter lexeme and the full path after it:
    private static final Pattern DollaPathExpressionPatt = Pattern.compile('(\\${1,})((?:\\.[^\\.]++)*+)$');

    static ReferenceExprLambda parseDollaRefExpr(PipedProducer hostOp, String refExprCandidate) {
        return parseDollaRefExpr(null, hostOp, refExprCandidate);
    }

    static ReferenceExprLambda parseDollaRefExpr(Args hostFrame, PipedProducer hostOp, String refExprCandidate) {
        if (refExprCandidate != null) {
            if (refExprCandidate.startsWith('$(')) {
                Matcher m = EnclosedPathExpressionPatt.matcher(refExprCandidate);
                if (!m.find()) {
                    ReferenceError(hostFrame, hostOp,
                        'Invalid Reference[' + refExprCandidate 
                            + ']: Expected well-formed $({PathExpression})');
                }
                // Else if we reach here, the "$({PathExpression})" parsed successfully, and we forward 
                // the stripped {PathExpression} path:
                String refExpr = m.group(1);
                return new ReferenceExprLambda(refExpr);
            } else if (refExprCandidate.startsWith('$')) {
                Matcher m = DollaPathExpressionPatt.matcher(refExprCandidate);
                if (!m.find()) {
                    ReferenceError(hostFrame, hostOp,
                        'Invalid Reference[' + refExprCandidate 
                            + ']: Expected well-formed {AnonymousParameter}.{PathExpression}');
                }
                String anonParam = m.group(1);
                Integer anonSlot;
                switch on anonParam {
                    when '$' {
                        anonSlot = 1;
                    }
                    when '$$' {
                        anonSlot = 2;
                    }
                    when '$$$' {
                        anonSlot = 3;
                    }
                }
                if (anonSlot == null) {
                    ReferenceError(hostFrame, hostOp,
                        'Invalid Reference['
                            + refExprCandidate + ']: Expected anonymous parameter $, $$, or $$$');
                }
                String pathExpr = m.group(2);
                // Strip leading "." off the path expression:
                if (string.isNotBlank(pathExpr) && pathExpr.startsWith('.')) {
                    pathExpr = pathExpr.substring(1);
                }
                // E.g. ("$$", "foo.bar.baz"):
                return new ReferenceExprLambda(anonSlot, pathExpr);
            }
        }
        return null;
    }

    // Evaluates a reference expression against Args (runtime Frame) as the scope environment. Expressions 
    // can express either 1 of the three "anonymous" variables: $, $$, $$$ - OR - a dot-delimited path 
    // expression where the root part is resolved against Arg's FieldAccessible implementation, with these 
    // defined fields: args, parent item, value:
    public virtual class ReferenceExprLambda implements Lambda {
        // When expression starts with an anonymous parameter slot, its exact slot will be populated here:
        // 1 => "$", 2 => "$$", 3 => "$$$"
        Integer anonymousSlot;

        // The raw dot-delimited Path Expression (sans enclosure). When an anonymousSlot is also populated,
        // this is interpreted as a relative path off that anon parameter. Otherwise, if anonymousSlot is 
        // null, the path is relative to the Lambda's Args (argv) object:
        String pathExpr;

        Boolean compiled = false;

        // When we have a PathExpression, the following are guaranteed to be populated (non-null) after 
        // the compile() phase:
        Boolean pathIsSimple;
        String[] pathParts;
        Integer pathLast;

        public String expression {get{
            if (this.anonymousSlot != null) {
                return '$'.repeat(Math.min(6, this.anonymousSlot)) 
                    + (String.isNotBlank(this.pathExpr) ?  '.' + this.pathExpr : '');
            } else {
                return '$(' + this.pathExpr + ')';
            }
        }}

        public ReferenceExprLambda(String fullPathExpr) {
            this(null, fullPathExpr);
        }

        public ReferenceExprLambda(Integer anonymousSlot, String relativePathExpr) {
            if (anonymousSlot == null && String.isBlank(relativePathExpr)) {
                // Revert to anonymous slot 1 "$" if path was blank:
                this.anonymousSlot = 1;
                this.pathExpr = null;
            } else  {
                this.anonymousSlot = anonymousSlot;
                this.pathExpr = relativePathExpr;
            }
        }

        public void compile(Args hostFrame) {
            this.compiled = true;
            if (this.anonymousSlot != null) {
                // Assert we have a valid anonymous slot:
                if (this.anonymousSlot < 1 || this.anonymousSlot > 3) {
                    ReferenceError(hostFrame, 'Reference[' + this.expression + '] specifies anonymous slot [' 
                        + this.anonymousSlot + ']. Valid slots are 1 - 3.');
                }
            } 
            if (String.isNotBlank(pathExpr)) {
                if (this.pathExpr.contains('.')) {
                    this.pathIsSimple = false;
                    // Note the possessive quantifiers!
                    this.pathParts = this.pathExpr.split('\\s*+\\.\\s*+');
                } else {
                    this.pathIsSimple = true;
                    this.pathParts = new String[]{ this.pathExpr };
                }
                this.pathLast = this.pathParts.size() - 1;
            }
        }

        String getPartialPath(Args argv, Integer pathIndex) {
            // Error, current holder is not a recognized map or object type:
            String at = this.getStartHolderName(argv);
            if (pathIndex > 0) {
                for (Integer i = 0; i < pathIndex; i++) {
                    at += '.' + this.pathParts[pathIndex];
                }
            }
            return at;
        }

        public virtual Object getStartHolder(Args argv) {
            return argv;
        }

        public virtual String getStartHolderName(Args argv) {
            return this.anonymousSlot == null ? '{Args}' : '$'.repeat(this.anonymousSlot);
        }

        public Object eval(Args argv) {
            if (!this.compiled) {
                this.compile(argv);
            }

            // The starting holder is either the designated anonymous parameter slot OR the starting
            // holder defined by virtual method getStartHolderName() (which is wired to return Lambda's
            // Args object for this base implementation):
            Object holder;
            if (this.anonymousSlot != null) {
                holder = argv.resolveAnonSlot(this.anonymousSlot);
            } else {
                holder = this.getStartHolder(argv);
            }

            // If we have a PathExpression to iteratively resolve against holder, then this.pathParts 
            // will be non-null:
            if (this.pathParts != null) {
                Integer pathIndex = 0;
                do {
                    String field = this.pathParts[pathIndex];
                    if (holder == null) {
                        // TODO: maybe we can have directives that specify whether this is an 
                        // error or a safe null return:
                        return null;
                    } else if (holder instanceof FieldAccessible) {
                        try {
                            holder = ((FieldAccessible) holder).get(field);
                        } catch (FuncException funcError) {
                            funcError.argv = argv;
                            throw funcError;
                        }
                    } else if (holder instanceof Map<String, Object>) {
                        holder = ((Map<String, Object>) holder).get(field);
                    } else if (holder instanceof sObject) {
                        // Generic sObject access logic, much-wow:
                        do {
                            Exception plainFieldError;
                            // First we try to resolve the current path part as a "plain" Field value, but only
                            // IFF we're on the last part of the path AND it doesn't have an "__r" (custom 
                            // relationship) suffix:
                            if (pathIndex == this.pathLast && !this.pathParts[pathIndex].endsWithIgnoreCase('__r')) {
                                try {
                                    holder = ((sObject) holder).get(field);
                                    // If we reach here then path part resolved as a plain Field:
                                    break;
                                } catch (SObjectException fieldError) {
                                    plainFieldError = fieldError;
                                    // Fallthrough to try and resolve this path part as a Parent or Child 
                                    // Relationship...
                                }
                            }

                            try {
                                // Try to resolve path part as a Parent Relationship:
                                holder = ((sObject) holder).getSObject(field);
                            } catch (SObjectException parentRelError) {
                                try {
                                    // Try to resolve path part as a Child Relationship:
                                    holder = ((sObject) holder).getSObjects(field);
                                } catch (SObjectException childRelError) {
                                    // TODO: This doesn't yet differentiate between whether the access 
                                    // failed because the reference was invalid (not a Parent nor Child 
                                    // Relationship), OR if it's a valid Relationship but the sObject came 
                                    // from a query that did not SELECT it:
                                    ReferenceError(argv, 'Field[' + field 
                                        + '] of [' + this.expression 
                                        + ']: Expected sObject Parent or Child relationship at [' 
                                        + getPartialPath(argv, pathIndex) + ']: ' 
                                        + (plainFieldError ?? parentRelError).getMessage());
                                }
                            }
                            // If we reach here then path part resolved as either a Parent or Child 
                            // Relationship and its value will be set into "holder":
                            break;
                        } while (true); // lol
                    } else if (holder instanceof MapIterable) {
                        holder = ((MapIterable) holder).get(field);
                    } else {
                        // Error, current holder is not a recognized map or object type:
                        ReferenceError(argv, 'Field[' + field 
                            + '] of [' + this.expression + ']: Expected Map or Object type at [' 
                            + getPartialPath(argv, pathIndex) + ']; got: ' + holder);
                    }

                    // Increment pathIndex; break after we've processed the last path part:
                    if (++pathIndex > this.pathLast) {
                        break;
                    }
                // My do-while-true loops always terminate, because "trust me, bro":
                } while (true);
            } // pathExpr

            return holder;
        }
    }

    public class TemplateKeyValue {
        String keyString;
        Lambda keyLambda;
        Object valueLiteral;
        Lambda valueLambda;

        TemplateKeyValue(Args hostFrame, String key, Object value) {
            this.keyString = key;
            this.valueLiteral = value;
            this.compile(hostFrame);
        }

        void compile(Args hostFrame) {
            this.keyLambda = parseDollaRefExpr(hostFrame, null, this.keyString);
            if (this.valueLiteral instanceof String) {
                this.valueLambda = parseDollaRefExpr(hostFrame, null, (String) this.valueLiteral);
            } else if (this.valueLiteral instanceof Lambda) {
                this.valueLambda = (Lambda) this.valueLiteral;
            }
        }
    }

    public class SObjectTemplate implements Lambda {
        Schema.sObjectType mintType;
        Map<String, Object> rawEntries;
        Boolean compiled = false;
        TemplateKeyValue[] compiledKeyValues;
        
        public SObjectTemplate(Id mintId, Map<String, Object> rawEntries) {
            this(mintId?.getSObjectType(), rawEntries);
            Object oldId = this.rawEntries.get('Id');
            if (oldId != mintId) {
                IllegalArgument('SObjectTemplate Supplied "Id" field value [' 
                    + oldId + '] clashes with minting Id [' + mintId + ']');
            }
            this.rawEntries.put('Id', mintId);
        }

        public SObjectTemplate(Schema.sObjectType mintType, Map<String, Object> rawEntries) {
            if (mintType == null) {
                IllegalArgument('SObjectTemplate requires a minting SObjectType to be specified');
            }
            this.mintType = mintType;
            this.rawEntries = rawEntries ?? new Map<String, Object>();
        }

        void compile(Args argv) {
            this.compiled = true;
            this.compiledKeyValues = new TemplateKeyValue[]{};
            for (String rawKey : this.rawEntries.keySet()) {
                this.compiledKeyValues.add(
                    new TemplateKeyValue(argv, rawKey, this.rawEntries.get(rawKey)));
            }
        }

        public Object eval(Args argv) {
            if (!this.compiled) {
                this.compile(argv);
            }
            if (argv.item == null) {
                //System.debug('Bypassing sObjectTemplate because of null input...');
                return null;
            }
            //System.debug('Minting sObjectTemplate from input: [' + argv.item + ']');
            sObject sob = this.mintType.newSObject();
            Integer index = 0;
            Program program = argv.program;
            for (TemplateKeyValue kv : this.compiledKeyValues) {
                String keyOutput;
                if (kv.keyLambda != null) {
                    // !! TODO: If SObjectTemplate is used in a MapObject iterator, the "$" and "item" bindings
                    // will be to the KeyValuePair (not the mapped value), which could be confusing!
                    // Should we switch to $ => "value", or allow binding through parent $ => "parent.$"?
                    Args keyFrame = new Args(program, argv.outerScope, kv.keyLambda, argv.item)
                        // $ => item, $$ => key, $$$ => index:
                        .anonBindings('item', 'key', 'index');
                    keyFrame.item = argv.item;
                    keyFrame.key = kv.keyString;
                    keyFrame.index = index;
                    Object keyEval = kv.keyLambda.eval(keyFrame);
                    program.close(keyFrame);
                    if (keyEval instanceof String) {
                        keyOutput = (String) keyEval;
                    } else {
                        IllegalArgument(argv, 'sObjectTemplate key expression [' + kv.keyString 
                            + '] expected String result; got ' + (keyEval ?? '<Null>'));
                    }
                } else {
                    keyOutput = kv.keyString;
                }
                Object valueOutput;
                if (kv.valueLambda != null) {
                    // !! TODO: If SObjectTemplate is used in a MapObject iterator, the "$" and "item" bindings
                    // will be to the KeyValuePair (not the mapped value), which could be confusing!
                    // Should we switch to $ => "value", or allow binding through parent $ => "parent.$"?
                    Args valueFrame = new Args(program, argv.outerScope, kv.valueLambda, argv.item)
                        // $ => item, $$ => key, $$$ => index:
                        .anonBindings('item', 'key', 'index');
                    valueFrame.item = argv.item;
                    valueFrame.key = keyOutput;
                    valueFrame.index = index;
                    valueOutput = kv.valueLambda.eval(valueFrame);
                    program.close(valueFrame);
                } else {
                    valueOutput = kv.valueLiteral;
                }

                index++;
                try {
                    sob.put(keyOutput, valueOutput);
                } catch (SObjectException fieldError) {
                    IllegalArgument(argv, 
                        'SObjectTemplate encountered sObject error in Put on field [' 
                            + keyOutput + ']: ' + fieldError.getMessage());
                }
            }
            return sob;
        }
    }

    public abstract class CompositeFilter implements Lambda {
        Lambda[] children = new Lambda[]{};

        public CompositeFilter add(Lambda child) {
            this.children.add(child);
            return this;
        }

        public abstract Object eval(Args argv);
    }

    public class AnyOfLambda extends CompositeFilter {
        public override Object eval(Args argv) {
            Object lastTestResult;
            for (Lambda child : this.children) {
                if (child != null) {
                    Object testResult = child.eval(argv);
                    // Inspired by ECMAScript truthy/falsey:
                    if (testResult == true 
                            || (testResult != null && testResult != false && testResult != 0.0 && testResult != '')) {
                        // Like ECMAScript, we shall return the last evaluated term's actual result, 
                        // short circuiting upon the 1st "Truthy" result:
                        //return true;
                        return testResult;
                    }
                    // "Falsey" results don't short-circuit; retain the last such result for fallthrough:
                    lastTestResult = testResult;
                }
            }
            // Fallthrough: return the last term's (Falsey) result:
            //return false;
            return lastTestResult;
        }
    }

    public class AllOfLambda extends CompositeFilter {
        public override Object eval(Args argv) {
            //Boolean hasPass = false;
            Object lastTestResult;
            for (Lambda child : this.children) {
                if (child == null) {
                    continue;
                } else {
                    Object testResult = child.eval(argv);
                    // Inspired by ECMAScript truthy/falsey:
                    if (testResult == true 
                            || (testResult != null && testResult != false && testResult != 0.0 && testResult != '')) {
                        //hasPass = true;
                        // "Truthy" results don't short-circuit; retain the last such result for fallthrough:
                        lastTestResult = testResult;
                    } else {
                        // Like ECMAScript, we shall return the last evaluated term's actual result, 
                        // short circuiting upon the 1st "Falsey" result:
                        //return false;
                        return testResult;
                    }
                }
            }
            // Fallthrough: return the last term's (Truthy) result:
            // return hasPass;
            return lastTestResult;
        }
    }

    public class SOQLFilter implements Lambda {
        Schema.sObjectType fromClauseType;
        String soqlCond;
        SOQLEvaluator evaluator;

        // TODO: can we lazy-detect fromClauseType the 1st time we're asked to conditional() 
        // on an item?

        public SOQLFilter(String soqlCond) {
            this(null, soqlCond);
        }

        public SOQLFilter(Schema.sObjectType fromClauseType, String soqlCond) {
            this.fromClauseType = fromClauseType;
            this.soqlCond = soqlCond;
            if (fromClauseType != null) {
                this.compile(fromClauseType);
            }
        }

        void compile(Schema.sObjectType fromClauseType) {
            if (this.evaluator == null) {
                if (fromClauseType == null) {
                    IllegalArgument('SOQLFilter cannot initialize to a null FROM-clause type');
                } else if (this.fromClauseType != null && this.fromClauseType != fromClauseType) {
                    IllegalArgument('SOQLFilter cannot re-initialize to ' + fromClauseType 
                        + ' after it has already declared for ' + this.fromClauseType);
                }
                this.fromClauseType = fromClauseType;
                // TODO: need to enable evaluator bindings...
                String whereClause = 'FROM ' + fromClauseType + ' WHERE ' + soqlCond;
                this.evaluator = StartSOQL().getEvaluatorWithoutBinds(whereClause);
            }
        }

        public Object eval(Args argv) {
            if (argv.item == null) {
                // TODO: Should this return false or null (falsey)?
                return false; // null;
            } else if (argv.item instanceof sObject) {
                sObject targetRecord = (sObject) argv.item;
                if (this.evaluator == null) {
                    this.compile(targetRecord.getSObjectType());
                } else if (targetRecord.getSObjectType() != this.fromClauseType) {
                    IllegalArgument(argv, 'SOQLFilter expected an input of type ' 
                        + this.fromClauseType + '; got ' + targetRecord.getSObjectType());
                }
                return this.evaluator.eval(targetRecord);
            } else {
                IllegalArgument(argv, 'SOQLFilter expected an sObject input; got ' + argv.item);
            }
            return false; // unreachable
        }
    }

    // Convenience static constructors to reduce need for "new" operator:

    public static Mapper Identity() {
        return new Mapper(null);
    }

    public static Reduce Cat() {
        return Cat(null);
    }

    public static Reduce Cat(String sep) {
        return new Reduce(new CatLambda(sep));
    }

    // Trigger utilities:

    public static TriggerContextSource Triggered() {
        return new TriggerContextSource();
    }

    public static PipedProducer Triggered(String flagsExpression) {
        return new TriggerContextSource().triggerEventsFilter(null, flagsExpression);
    }

    public static PipedProducer Triggered(Schema.sObjectType targetType) {
        return new TriggerContextSource().triggerEventsFilter(targetType, null);
    }

    public static PipedProducer Triggered(Schema.sObjectType targetType, String eventsExpression) {
        return new TriggerContextSource().triggerEventsFilter(targetType, eventsExpression);
    }

    public class TriggerContextSource extends SourceProducer {
        TriggerContextSource() {
            super('Trigger_Context[' 
                + (getTriggerSObjectType() == null 
                    ? 'NOT Trigger' 
                    : String.valueOf(getTriggerSObjectType())) 
                + ']');
        }

        public override Object produce() {
            if (Trigger.isExecuting) {
                return new TriggerContext();
            }
            return null;
        }
    }

    public class TriggerContext implements FieldAccessible {
        TriggerRecordPair[] cachedPairs;
        
        public TriggerRecordPair[] getPairs() {
            if (this.cachedPairs == null) {
                this.cachedPairs = new TriggerRecordPair[]{};
                if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
                    for (sObject current : Trigger.new) {
                        TriggerRecordPair rec = new TriggerRecordPair();
                        this.cachedPairs.add(rec);
                        rec.current = current;
                        if (Trigger.oldMap != null) {
                            rec.old = Trigger.oldMap.get(current.Id);
                        }
                    }
                } else if (Trigger.isDelete) {
                    for (sObject del : Trigger.old) {
                        TriggerRecordPair rec = new TriggerRecordPair();
                        this.cachedPairs.add(rec);
                        rec.current = del;
                    }
                }
            }
            return this.cachedPairs;
        }

        public TriggerRecordPair[] records {get{
            return this.getPairs();
        }}

        public TriggerRecordPair[] pairs {get{
            return this.getPairs();
        }}

        public sObject[] current {get{
            if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
                return Trigger.new;
            } else if (Trigger.isDelete) {
                return Trigger.old;
            } else {
                return null;
            }
        }}

        public sObject[] old {get{
            if (Trigger.isUpdate) {
                return Trigger.old;
            } else {
                return null;
            }
        }}

        public Object get(String field) {
            switch on field {
                when 'records', 'pairs' {
                    return this.getPairs();
                }
                when 'current', 'new', 'newest' {
                    return this.current;
                }
                when 'old', 'oldest' {
                    return this.old;
                }
                when else {
                    ReferenceError('TriggerContext illegal field [' + field + ']');
                }
            }
            return null; // unreachable
        }
    }

    public class TriggerRecordPair implements FieldAccessible {
        public sObject current;
        public sObject old;

        // Aliased properties:
        public sObject newest {get{ return this.current; }}
        // Can't provide "new" getter because this name cannot be used as an Apex identifier :(
        public sObject oldest {get{ return this.old; }}

        public Object get(String field) {
            switch on field {
                when 'current', 'new', 'newest' {
                    return this.current;
                }
                when 'old', 'oldest' {
                    return this.old;
                }
                when else {
                    ReferenceError('TriggerRecordPair illegal field [' + field + ']');
                }
            }
            return null; // unreachable
        }
    }

    static Schema.SObjectType getTriggerSObjectType() {
        if (Trigger.isExecuting) {
            if (Trigger.new != null) {
                return Trigger.new[0].getSObjectType();
            } else if (Trigger.old != null) {
                return Trigger.old[0].getSObjectType();
            }
        }
        return null;
    }

    public class TriggerFlagsLambda implements Lambda {
        Schema.sObjectType targetType;
        Boolean isInsert;
        Boolean isUpdate;
        Boolean isDelete;
        Boolean isUndelete;
        Boolean isBefore;
        Boolean isAfter;

        public TriggerFlagsLambda() {
            this(null);
        }

        public TriggerFlagsLambda(Schema.sObjectType targetType) {
            this.targetType = targetType;
        }

        public Object eval(Args argv) {
            Object input = argv.value;
            if (input == null) {
                return false;
            // !! Note this filter lambda requires the input to be a value of type TriggerContext, 
            // but doesn't actually use it! This logic gets flag values directly from the global 
            // "Trigger" variable:
            } else if (!(input instanceof TriggerContext)) {
                IllegalArgument(argv, 'TriggerFlagsLambda expected input of type' 
                    + ' TriggerContext; got [' + input + ']');
            }
            //TriggerContext triggerCtxt = (TriggerContext) input;
            if (this.targetType != null) {
                if (getTriggerSObjectType() != this.targetType) {
                    return false;
                }
            }
            if (this.isInsert != null && this.isInsert != Trigger.isInsert) {
                return false;
            }
            if (this.isUpdate != null && this.isUpdate != Trigger.isUpdate) {
                return false;
            }
            if (this.isDelete != null && this.isDelete != Trigger.isDelete) {
                return false;
            }
            if (this.isUndelete != null && this.isUndelete != Trigger.isUndelete) {
                return false;
            }
            if (this.isBefore != null && this.isBefore != Trigger.isBefore) {
                return false;
            }
            if (this.isAfter != null && this.isAfter != Trigger.isAfter) {
                return false;
            }
            return true;
        }
    }

    public class TriggerRecordsChangedByField implements Lambda {
        String[] trackedFields;
        Boolean includeOnDelete;
        
        public TriggerRecordsChangedByField(String[] fields) {
            this.trackedFields = fields;
            this.includeOnDelete = false;
        }

        public TriggerRecordsChangedByField includeOnDelete(Boolean onDeleteFlag) {
            this.includeOnDelete = onDeleteFlag == true;
            return this;
        }

        public Object eval(Args argv) {
            Object input = argv.value;
            if (input == null) {
                return null;
            } else if (!(input instanceof TriggerContext)) {
                IllegalArgument(argv, 'TriggerRecordsChangedByField expected input of type' 
                    + ' TriggerContext; got [' + input + ']');
            }
            TriggerContext trigg = (TriggerContext) input;
            if (Trigger.isInsert || Trigger.isUndelete || this.includeOnDelete && Trigger.isDelete) {
                return trigg.getPairs(); //trigg.current;
            }
            TriggerRecordPair[] changed = new TriggerRecordPair[]{};
            if (Trigger.isUpdate) {
                for (TriggerRecordPair record : trigg.records) {
                    for (String field : this.trackedFields) {
                        try {
                            Object currentVal = record.current.get(field);
                            Object oldVal = record.old?.get(field);
                            if (currentVal != oldVal) {
                                changed.add(record);
                                // How the fuck did I miss including a break when I first wrote this:
                                break;
                            }
                        } catch (SObjectException fieldError) {
                            IllegalArgument(argv,
                                'TriggerRecordsChangedByField encountered illegal field access [' 
                                    + field + ']: ' + fieldError.getMessage());
                        }
                    }
                }
            }
            return changed;
        }
    }

    public enum DML_Action { DML_Delete, DML_Insert, DML_Update, DML_Upsert }
    
    public class DmlStatement extends PipedProducer {
        DML_Action action;

        public DmlStatement(DML_Action action) {
            this(action, null);
        }

        public DmlStatement(DML_Action action, Lambda lambda) {
            super(action?.name() ?? 'DML_<Unspecified>', lambda);
            this.action = action;
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            // value=pipedInput; "item" and "index" will be set immediately before eval:
            Args thisOpFrame = new Args(program, outerScope, this, pipedInput)
                // $ => item, $$ => index
                .anonBindings('item', 'index', null);
            Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();

            sObject[] marshalled = new sObject[]{};
            Boolean scalar = false;
            if (pipedInput instanceof Iterable<Object>) {
                Integer index = 0;
                for (Object inputElmt : (Iterable<Object>) pipedInput) {
                    dmlMarshal(program, thisOpFrame, this, lambdaFrame, inputElmt, index, marshalled);
                    index++;
                }
            } else if (pipedInput instanceof sObject) {
                scalar = true;
                dmlMarshal(program, thisOpFrame, this, lambdaFrame, pipedInput, 0, marshalled);
            }
            if (marshalled.size() > 0) {
                switch on this.action {
                    when DML_Delete {
                        delete marshalled;
                    }
                    when DML_Insert {
                        insert marshalled;
                    }
                    when DML_Update {
                        update marshalled;
                    }
                    when DML_Upsert {
                        upsert marshalled;
                    }
                    when else {
                        IllegalArgument(this,
                            'DmlStatement specifies unrecognized action [' 
                                + this.action + ']');
                    }
                }

                // Frame-closing and return:
                program.close(thisOpFrame);
                return scalar ? (Object) marshalled[0] : (Object) marshalled;
            }

            // TODO: need to review this; should we throw an error when we get non-sObject elements?
            return null;
        }
    }

    static void dmlMarshal(Program program, Args operationFrame, PipedProducer operation, Args lambdaFrame, 
            Object item, Integer index, Object[] marshalled) {
        
        // Set the appropriate formal arg values for this iteration:
        operationFrame.item = item;
        operationFrame.index = index;
        
        if (operation.nestedInner != null) {
            Args parentFrame = program.currentFrame;
            item = operation.nestedInner.pipeIn(program, operationFrame, item);
            // Update the "item" formal arg if it was mutated by the nested-inner op:
            operationFrame.item = item;
            program.closeAfter(parentFrame);
        }
        if (lambdaFrame != null) {
            // Copy the formal args we've maintained in operationFrame over to the lambdaFrame 
            // before its eval():
            lambdaFrame.copyFormalArgsFrom(operationFrame);
            item = lambdaFrame.lambda.eval(lambdaFrame);
        }
        // TODO: need to review this; should we throw an error when we get non-sObject elements?
        if (!(item instanceof sObject)) {
            IllegalArgument(operation, 
                'DmlStatement encountered non-sObject item at index[' + index + ']: ' + item);
        }
        marshalled.add(item);
    }

    public class StringCoerce extends PipedProducer {
        public StringCoerce() {
            super('AsString');
        }

        public override Object pipeIn(Program program, Args outerScope, Object pipedInput) {
            // Null forwarding:
            if (pipedInput == null) {
                return null;
            }

            if (pipedInput instanceof String) {
                return (String) pipedInput;
            } else if (pipedInput instanceof Double || pipedInput instanceof Boolean) {
                return String.valueOf(pipedInput);
            } else {
                return pipedInput.toString();
            }
        }
    }
}