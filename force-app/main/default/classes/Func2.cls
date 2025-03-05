/*
 * Mike Ulveling
 * 
 * Experimenting with predicate blocks for Func. Example:

    .ifBlock('$.isUpdate')
        .triggerSObjectsOnFieldChange('User__c, SOQL_Criteria__c, Disabled__c')
    .elseBlock()
        .triggerSObjects()
        .ifBlock('$')
            .debugTrace()
        .endIf()
        .filterNot('$.Disabled__c')
    .endIf()
*
*/

public class Func2 {

    /*
    .pipe(new Func.Then()
        .ifBlock('$.foo')
            .debugTrace()
        .endIf()
        .debugTrace())

    // Can .then(Operation nextOp) be aliased to .then() where a new Func.Then() is auto minted and returned?
    // Yes BUT there is no useful value to this because you would get SAME result by directly chaining to the prior op!
    .then()
    .ifBlock('$.foo')
        .debugTrace()
    .endIf()
    .debugTrace()

    // However, Func.Then is VERY useful for nested-inner operation chains:
    .forEach(new Func.Then()
        .ifBlock('$.flag')
            .debugTrace()
        .endIf()
    );
    
    .then(
        // !! MapObject mints a Block scope for its nested-inner and defines "item", "key", "value", "$", "$$" for it
        new Func.MapObject(
            new Func.Block()
                .ifBlock('$$')
                    .debugTrace()
                .endIf()))
    */

    // TODO:
    // > Rename PipedProducer to Operation; make this the base class and eliminate useless interface Producer.
    // > Alias Operation.pipe(Operation nextOp) to .then(Operation nextOp)
    // >> SourceProducer extends Operation - is the only use and implementation of method produce()
    // > Resolve else - elseif ambiguity:
    // >> If containing ControlIf already has an else block, then we must either error at that time OR keep
    //    looking for an outer ControlIf (not closed, and without an else) to attach to. 
    // > Operations like MapObject and Mapper should wrap their nested-inner ops in a block and define both
    //    formal args and anonymous parameters in it.
    // > Can we better combine the concepts of Args and Scope so that, for example:
    //   Lambdas can be minted to declare "no args scope" (de-scoping) and thus inherit from outer?
    // >> What about de-scoping *specific* formal arguments and/or anon params from Args? This is much more valuable...
    
/*
    Thought Experiment:

    Func
        .mapObject(
            new Func.Chain()
                .ifBlock('$(value)')
                    .debugTrace()
        );

    -----------------
    Outer-Op Scoping:
    -----------------
    RootBlock[outerRoot]
        MapObject -- Operation, NOT a scope!

    ---------------------
    Nested-Inner Scoping:
    ---------------------
    RootBlock[nestedInnerBlock]
        IfControlBlock
            PredicateBlock

    > The outer operation, when processing its nested-inner (construction phase), will call:
    > nestedInnerBlock.supplantParentBlock(outerRoot)
    > Which results in the following scope hierarchy:

    RootBlock[outerRoot]
        RootBlock[nestedInnerBlock]
            IfControlBlock
                PredicateBlock


    Does that look right? Or should operations like MapObject always mint their own scope:

    RootBlock[outerRoot]
        Block[mapObjectBlock]
            IfControlBlock
                PredicateBlock

    > Then mapObjectBlock could also define: "item", "key", "value", "$", "$$", "$$$"

    > If operations mint and define their own scope for nested-inner ops, these could equally be 
      used by their lambdas...BUT then lambdas would have to cede control over formal arg definitions...
    >> operations could mint a DIFFERENT scope for lambdas IF they implement an optional interface to 
       specify formal arg definitions "ala carte"...

    Does Block Scope need to implement FieldAccessible to allow recursive definitions like "args", 
    "outer" and "outerArgs"? How do we provide "outerArgs" functionality?

    .forEachForEach(new Func.SObjectTemplate(new Map<String, Object>{
        'foo' => 'outer.outer.$$' // key value from outermost for-each loop
    }))

    Could we instead do:
    .forEachBlock()
        .forEach(new Func.SObjectTemplate)
    .end()

    RootBlock[absoluteRoot]
        ForEachBlock[outerForEach]
            ForEachLambda[innerForEach] -- minted specifically for the SObjectTemplate lambda

    > Above, the forEachBlock's inner operations chain becomes its nested-inner; outer ForEachBlock 
      mints its own scope block and the inner block's parent/root is supplanted to this...
    > The SObjectTemplate lambda can access outer-forEach's key value by:
      args.outerArgs.key
      >> args is a self-reference to current lambda (args) scope, which is a Block scope that is FieldAccessible
      >> args.outerArgs is a reference to 1-up parent Block scope (outer forEach)

    !! Args should no longer directly implement FieldAccessible; its property staticScope must be used to 
       resolve references!
    
    ReferenceExprLambda:
    > 1st path part resolves against argv.staticScope
    >> E.g. "args" is defined on argv.staticScope when the latter is a Scope (of the inner forEach, minted 
       for its lambda), and it returns that very scope reference, which is flagged as an "Args" scope.
       >> Scope implements FieldAccessible, so it is OK to reference the next part "outerArgs", which
          returns a reference to the 1st outer static scope flagged as "Args", which is the outer ForEach's
          scope minted for its nestedInner / lambda.

    !! We might(?) need a virtual close() method on Block to allow subclasses like IfControlBlock and 
       ForEachBlock to implement ther own closing logic! 
    > end() and endIf() calls need to call this close()
    > closeToRoot() needs to call the close() method instead of simply setting .closed = true
*/

    // Good for starting a new op chain (utilizing convenient builder syntax, e.g. new Then().ifBlock()) for a nested-inner op:
    public class Chain /* Then */ extends PipedProducer {
        public Chain() {
            super('Then', null, null);
        }

        public virtual override Object pipeIn(Args outerScope, Object pipedInput) {
            // !! Skip null-forwarding in this case...
            // TODO: Do you even need to do this??
            Args thisOpFrame = new Args(outerScope, this, pipedInput)
                // $ => value:
                .anonBindings('value', null, null);
            thisOpFrame.value = pipedInput;
    
            thisOpFrame.close();
            return pipedInput;
        }
    }

    public virtual class Block extends PipedProducer {
        PipedProducer firstOp;
        PipedProducer lastOp;
        Boolean closed = false;

        Block(Block parentBlock) {
            super('PlainBlock', parentBlock, null);
        }

        Block(Block parentBlock, Object predicate_exprLambdaOpValue) {
            super('PlainBlock', parentBlock, predicate_exprLambdaOpValue);
        }

        Block(String blockName, Block parentBlock, Object predicate_exprLambdaOpValue) {
            super(blockName, parentBlock, predicate_exprLambdaOpValue);
        }

        public virtual override Object pipeIn(Args outerScope, Object pipedInput) {
            // !! Skip null-forwarding in this case...

            Args thisOpFrame = new Args(outerScope, this, pipedInput)
                // $ => value:
                .anonBindings('value', null, null);
            thisOpFrame.value = pipedInput;

            // Execute this block's op chain in sequence:
            PipedProducer nodeOp = this.firstOp;
            while (nodeOp != null) {
                pipedInput = nodeOp.pipeIn(thisOpFrame, pipedInput);
                thisOpFrame.value = pipedInput;
                nodeOp = nodeOp.nextOp;
            }
    
            thisOpFrame.close();
            return pipedInput;
        }

        public void close() {
            this.closed = true;
        }
    }

    public class RootBlock extends Block {
        RootBlock() {
            super('RootBlock', null, null);
        }
    }

    public class PredicateBlock extends Block {
        Boolean negate = false;

        // !! Either this.nestedInnerBlock OR this.lambda will be used for the predicate, with higher 
        // preference given to lambda. If both are null, "Truthy" logic is applied to the pipedInput...

        PredicateBlock(String predicateName, Block parentBlock, Object predicate_exprLambdaOpValue) {
            super(predicateName, parentBlock, predicate_exprLambdaOpValue);
        }

        public PredicateBlock negate() {
            this.negate = !this.negate;
            return this;
        }

        public Boolean evalPredicate(Args outerScope, Object outerPipedInput) {
            // TODO: need way to indicate this Frame is a predicate eval for DebugTrace?
            Args thisOpFrame = new Args(outerScope, this, pipedInput)
                // $ => value:
                .anonBindings('value', null, null);
            
            thisOpFrame.value = pipedInput;
            
            Object testResult = outerPipedInput;
            if (this.nestedInnerBlock != null) {
                testResult = this.evalNestedInner(thisOpFrame, outerPipedInput);
            } else if (this.lambda != null) {
                Args lambdaFrame = thisOpFrame.dispatchLambdaFrame();
                // Copy the formal args we've maintained in operationFrame over to the lambdaFrame 
                // before its eval():
                lambdaFrame.copyFormalArgsFrom(thisOpFrame);
                testResult = lambdaFrame.lambda.eval(lambdaFrame);
            }
            //Object testResult = evalInnerOpLambda(thisOpFrame, outerPipedInput);
    
            // Inspired by ECMAScript's truthy / falsey logic to convert ANY type to Boolean:
            Boolean boolResult = testResult == true 
                || (testResult != null && testResult != false && testResult != 0.0 && testResult != '');
    
            thisOpFrame.close();
            return boolResult == !this.negate;
        }
    }

    public class ControlIfBlock extends Block {
        PedicateBlock ifBlock;
        PedicateBlock[] elseIfBlocks = new Object[]{};
        Integer elseIfTop = -1;
        Block elseBlock;

        ControlIfBlock(Object if_exprLambdaOpValue) {
            this(null, if_exprLambdaOpValue);
        }
    
        ControlIfBlock(Block parentBlock, Object if_exprLambdaOpValue) {
            super('IfControl', parentBlock, null);
            this.ifBlock = new PedicateBlock('If', this, if_exprLambdaOpValue);
            this.ifBlock.parentBlock = this;
        }
    
        public PedicateBlock addElseIf(Object elseIf_exprLambdaOpValue) {
            // Close the prior "if" block:
            this.ifBlock.closed = true;
            // Close the prior "else if", if any:
            if (this.elseIfTop > -1) {
                this.elseIfBlocks[this.elseIfTop].closed = true;
            }
            PedicateBlock newElseIf = new PedicateBlock('ElseIf', this, elseIf_exprLambdaOpValue);
            newElseIf.parentBlock = this;
            this.elseIfBlocks.add(newElseIf);
            this.elseIfTop++;
            return newElseIf;
        }
    
        public PedicateBlock addElse() {
            if (this.elseBlock != null) {
                IllegalState('Cannot declare 2nd "else" for an "if" target');
            }
            // Close the prior "if" block:
            this.ifBlock.closed = true;
            // Close the prior "if else", if any:
            if (this.elseIfTop > -1) {
                this.elseIfBlocks[this.elseIfTop].closed = true;
            }
            this.elseBlock = new Block('Else', this, null);
            return this.elseBlock;
        }
    
        public ControlIfBlock endIf() {
            if (this.closed) {
                IllegalState('Target "if" has already been closed');
            }
            // Close the prior "if" block:
            this.ifBlock.closed = true;
            // Close the prior "if else", if any:
            if (this.elseIfTop > -1) {
                this.elseIfBlocks[this.elseIfTop].closed = true;
            }
            // Close the prior "else", if any:
            if (this.elseBlock != null) {
                this.elseBlock.closed = true;
            }
            // Close this outer if-control block:
            this.closed = true;
            return this;
        }
    
        public virtual override Object pipeIn(Args outerScope, Object pipedInput) {
            // !! Skip null-forwarding in this case...
            Args thisOpFrame = new Args(outerScope, this, pipedInput)
                // $ => value:
                .anonBindings('value', null, null);
            thisOpFrame.value = pipedInput;
    
            // Evaluate the predicates until we get a match, then pipe into the matching predicate block!
            Object entryBlockResult;
            Boolean entry = false;
            if (this.ifBlock.evalPredicate(thisOpFrame, pipedInput)) {
                entry = true;
                entryBlockResult = this.ifBlock.pipeIn(thisOpFrame, pipedInput);
            } else {
                for (PredicateBlock elseIf : this.elseIfBlocks) {
                    if (elseIf.evalPredicate(thisOpFrame, pipedInput)) {
                        entry = true;
                        entryBlockResult = elseIf.pipeIn(thisOpFrame, pipedInput);
                        break;
                    }
                }
                if (!entry && this.elseBlock != null) {
                    entry = true;
                    entryBlockResult = this.elseBlock.pipeIn(thisOpFrame, pipedInput);
                }
            }
    
            thisOpFrame.close();
            return entry ? entryBlockResult : pipedInput;
        }
    }

    public abstract class PipedProducer implements Producer {    
        // !! New property for operations directly inside an "if", "else if" or "else" predicate block:
        Block parentBlock;

        //PipedProducer upstream; 
        // New properties for a doubly-linked list:
        PipedProducer prevOp;
        PipedProducer nextOp;

        //PipedProducer nestedInner;
        // We store a reference to the nested inner's root block - now it will ALWAYS be wrapped in a block:
        Block nestedInnerBlock;

        // Inner operation / transformer that is "just" a lambda:
        Lambda lambda;

        public PipedProducer(String name) {
            this(name, null, null);
        }

        public PipedProducer(String name, Block parentBlock, Object exprLambdaOpValue) {
            this.name = name;
            // !! Note this condition - RootBlock construction uses this super-constructor, and it 
            // has to terminate!
            if (!(this instanceof RootBlock)) {
                // Mint a new root Block if no parent Block was supplied:
                this.parentBlock = parentBlock ?? new RootBlock();
            }
            this.parseInner_exprLambdaOpValue(exprLambdaOpValue);
            this.preserveUpstreamVectorType = false;
        }

        private void parseInner_exprLambdaOpValue(Object exprLambdaOpValue) {
            if (exprLambdaOpValue == null) {
                return;
            } else if (exprLambdaOpValue instanceof String) {
                String expr = (String) exprLambdaOpValue;
                if (expr.startsWith('$')) {
                    this.lambda = parseDollaRefExpr(this, expr);
                    return;
                }
            }

            if (exprLambdaOpValue instanceof Lambda) {
                this.lambda = (Lambda) exprLambdaOpValue;
            } else if (exprLambdaOpValue instanceof PipedProducer) {
                this.nestedInnerBlock = ((PipedProducer) exprLambdaOpValue).closeToRoot();
                // !! TODO: do we need to set parentBlock here for an inner op??
                if (this instanceof Block) {
                    this.nestedInnerBlock.supplantParentBlock((Block) this);
                } else {
                    this.nestedInnerBlock.supplantParentBlock(this.parentBlock);
                }
            } else {
                // As a final resort, wrap the value as literal lambda - i.e. a constant value 
                // to apply Truthy logic against:
                this.lambda = new LiteralLambda(exprLambdaOpValue);
            }
        }

        public PipedProducer pipe(PipedProducer newChainedOp) {
            Block attachToBlock;
            // Starting at the tail op, close all its containing blocks. E.g. this could be a dangling
            // open predicate block under a Control-If, and we would want to close both the predicate and
            // the Control-If:
            PipedProducer newChainRoot = newChainedOp.closeToRoot(); // returns the root containing block (also closed)
            PipedProducer newChainHead = newChainRoot.firstOp;
            PipedProducer newChainTail = newChainRoot.lastOp;

            // If this op is a Block AND it's not closed, then attach the new op to it: 
            if (this instanceof Block && !((Block) this).closed) {
                attachToBlock = (Block) this;
                if (attachToBlock.firstOp == null) {
                    attachToBlock.firstOp = newChainHead;
                }
            // Else reuse THIS op's parent block to attach the new op:
            } else {
                attachToBlock = this.parentBlock;
            }
            
            // At this point, we have to give up and throw if the attachToBlock is closed:
            if (attachToBlock.closed == true) {
                IllegalState(attachToBlock.name + ' is closed and cannot attach {' 
                    + newChainHead.name + '} operation');
            }
            //nextOp.setUpstream(this); // ugh
            newChainHead.prevOp = this;
            this.nextOp = newChainHead;
            // !! this.parentBlock, and thus attachToBlock, should NEVER be null
            attachToBlock.lastOp = newChainTail;
            // Note supplantParentBlock() works for any op in a block chain, so newChainHead or 
            // newChainTail would work equally here:
            newChainHead.supplantParentBlock(attachToBlock);

            return newChainTail;
        }

        // Closes all Blocks starting at this op (inclusive, if this is a Block), all the way 
        // to root Block (inclusive of root). Returns the root Block:
        private Block closeToRoot() {
            Block nextAncestor;
            if (this instanceof Block) {
                nextAncestor = (Block) this;
            } else if (this.parentBlock != null) {
                nextAncestor = this.parentBlock;
            } else {
                return null;
            }

            Block rootBlock;
            do {
                rootBlock = nextAncestor;
                rootBlock.close();
                nextAncestor = nextAncestor.parentBlock;
            } while (nextAncestor != null);
            
            return rootBlock;
        }

        private void supplantParentBlock(Block newParentBlock) {
            PipedProducer nodeOp = this.parentBlock?.firstOp;
            while (nodeOp != null) {
                nodeOp.parentBlock = newParentBlock;
                nodeOp = nodeOp.nextOp;
            }
            this.parentBlock = newParentBlock;
        }

        public Object evalNestedInner(Args opFrame, Object innerInputValue) {
            if (this.nestedInnerBlock == null) {
                return innerInputValue;
            }
            Args parentFrame = Runtime.stack[Runtime.top]; //getProgram().currentFrame;
            // !! Now we store the nested-nner's wrapper block and have that eval itself:
            Object innerOutputValue = this.nestedInnerBlock.pipeIn(opFrame, innerInputValue);
            //getProgram().closeAfter(parentFrame);
            Runtime.closeAfter(parentFrame);
            return innerOutputValue;
        }
    
        public abstract Object pipeIn(Args outerScope, Object pipedInput);
    
        public PredicateBlock ifBlock(Object if_exprLambdaOpValue) {
            ControlIfBlock newControl = new ControlIfBlock(if_exprLambdaOpValue);
            this.pipe(newControl);
            return newControl.ifBlock;
        }
    
        public PedicateBlock elseIfBlock(Object elseIf_exprLambdaOpValue) {
            // Find the nearest upstream ControlIfBlock; this will become the "else if" predicate's target:
            ControlIfBlock controlBlock = this.getContainingControlIf();
            if (controlBlock == null) {
                IllegalsState('Cannot declare "else if" without an "if" target');
            }
            return controlBlock.addElseIf(elseIf_exprLambdaOpValue);
        }
    
        public PedicateBlock elseBlock() {
            // Find the nearest upstream ControlIfBlock; this will become the "else if" predicate's target:
            ControlIfBlock controlBlock = this.getContainingControlIf();
            if (controlBlock == null) {
                IllegalsState('Cannot declare "else" without an "if" target');
            }
            return controlBlock.addElse();
        }
    
        public ControlIfBlock endIf() {
            // Find the nearest upstream ControlIfBlock; this will become the "else if" predicate's target:
            ControlIfBlock controlBlock = this.getContainingControlIf();
            if (controlBlock == null) {
                IllegalsState('Cannot find an "if" target to close');
            }
            controlBlock.endIf();
            return controlBlock;
        }

        public ControlIfBlock getContainingControlIf() {
            // !! Note that is THIS is an instance of ControlIfBlock, we DON'T return it, because it cannot be
            // its own container!
            Block ancestorBlock = this.parentBlock;
            while (ancestorBlock != null) {
                if (ancestorBlock instanceof ControlIfBlock) {
                    return (ControlIfBlock) ancestorBlock;
                }
                ancestorBlock = ancestorBlock.parentBlock;
            }
            return null;
        }

        public Object go() {
            Boolean isRoot = Runtime.top < 0;
            Object nextValue;
            try {
                // Find the root block; make sure we close all outstanding blocks along the way (including root):
                Block rootBlock = this.closeToRoot();
                PipedProducer nodeOp = rootBlock.firstOp;
                // TODO: Do we need a <root> Args frame?
                // No outerArgs scope on this root frame:
                Args outerArgs;
                Args rootBlockFrame = new Args(outerArgs, rootBlock, nextValue)
                    // $ => value:
                    .anonBindings('value', null, null);
                while (nodeOp != null) {
                    if (nodeOp instanceof SourceProducer) {
                        // SourceProducers implement produce() to create "something from nothing":
                        nextValue = ((SourceProducer) nodeOp).produce();
                    } else {
                        nextValue = nodeOp.pipeIn(rootBlockFrame, nextValue);
                    }
                    rootBlockFrame.value = nextValue;
                    nodeOp = nodeOp.nextOp;
                }

                rootBlockFrame.close();
                return nextValue;
            } catch (FuncException funcThrownOut) {
                if (isRoot) {
                    funcThrownOut.debugTrace(funcThrownOut.getTypeName() + ': ' + funcThrownOut.getMessage());
                }
                throw funcThrownOut; // re-throw
            } catch (Exception unexpectedThrownOut) {
                if (isRoot) {
                    // TODO: Factor out this trace header stuff:
                    String traceTitle = 'Unexpected ' + unexpectedError.getTypeName() 
                        + ': ' + unexpectedError.getMessage();
                    System.debug('TRACE<' + traceTitle + '>');
                    Runtime.debugTrace(null);
                    System.debug('END_TRACE<' + traceTitle + '>');
                }
                throw unexpectedThrownOut; // re-throw
            }
        }
    }

    public class Program {

    }
    // The singleton instance of Program now becomes the defacto runtime / VM:
    public static Program Runtime = new Program();

    // New variable-scoping logic:

    public interface Scope {
        Boolean hasOwnDefinition(String varName);

        void define(String varName, Object value);

        void assign(String varName, Object value);

        Object access(String varName);
    }

    // Block-variable scope:
    public class Block implements Scope {
        Block parentBlock;
        Map<String, Object> localVars = new Map<String, Object>();

        public Boolean hasOwnDefinition(String varName) {
            return this.localVars.containsKey(varName);
        }

        public void define(String varName, Object value) {
            if (this.localVars.containsKey(varName)) {
                ReferenceException('Cannot re-define variable {' + varName + '} in this scope');
            }
            this.localVars.put(varName, value);
        }

        public void assign(String varName, Object value) {
            // Find the nearest (inner-most) defining scope:
            Scope scope = this;
            while (scope != null) {
                //if (scope.hasOwnDefinition(varName)) {
                if (scope.localVars.containsKey(varName)) {
                    scope.localVars.put(varName, value);
                    return;
                }
                scope = scope.parentBlock;
            }
            // TODO: Should this be an implicit definition at the {root} level scope (like ECMAScript), 
            // or a ReferenceException?
            ReferenceException('Cannot assign undefined variable {' + varName + '}');
        }

        public Object access(String varName) {
            // Find the nearest (inner-most) defining scope:
            Scope scope = this;
            while (scope != null) {
                //if (scope.hasOwnDefinition(varName)) {
                if (scope.localVars.containsKey(varName)) {
                    return scope.localVars.get(varName);
                }
                scope = scope.parentBlock;
            }
            // TODO: Should default return be null, undefined, or ReferenceException (like ECMAScript)?
            //return null;
            ReferenceException('Cannot access undefined variable {' + varName + '}');
        }
    }

    // Args (runtime Frame) now implements the Scope interface:

    static final String ARGS_MASKING_VARS = '$ $$ $$$ value item key index args outer outerArgs';

    public class Args implements Scope {
        // Formerly named "outerScope" (ugh) this is actually *dynamic* scoping, NOT static scoping, which
        // is a bit dangerous and of limited/questionable value... 
        // !! TODO: Do we even need this when we could equally access as: Program.stack[this.stackIndex - 1]?
        Args outerArgs;

        // Every executing operation or lambda is bound to a static outer scope; note that in cases where 
        // (this.frameOp instanceof Block) <=> (this.frameOp === this.staticScope). 
        Block staticScope;
        // The following two are mutually axlcusive; exactly one MUST be populated:
        Operation frameOp;
        Lambda frameLambda;
        
        public Boolean hasOwnDefinition(String varName) {
            return ARGS_MASKING_VARS.indexOf(varName) > -1;
        }

        public void define(String varName, Object value) {
            ReferenceException('Cannot define variable {' + varName + '} in an Arguments scope');
        }

        public void assign(String varName, Object value) {
            if (ARGS_MASKING_VARS.indexOf(varName) > -1) {
                ReferenceException('Cannot re-assign variable {' + varName + '} in an Arguments scope');
            }
            this.staticScope.assign(varName, value);
        }

        public Object access(String varName) {
            if (ARGS_MASKING_VARS.indexOf(varName) > -1) {
                return this.get(varName);
            }
            return this.staticScope.access(varName);
        }

        // New convenience method. Returns new the runtime-stack top:
        public Integer close() {
            // Manually null-out all the reclaimed Frame slots to prevent memory leaks (though 
            // unlikely to occur before the stack blows out):
            while (Runtime.top >= this.stackIndex) {
                Runtime.stack[Runtime.top--] = null;
            }
            return Runtime.top;
        }
    }

    public interface ObjectScope extends Scope {
        
        // TODO: Not needed for now...

    }
    
    // Not needed for now...
    public class UndefinedValue {
        private UndefinedValue() {}
    }
    public static UndefinedValue Undefined = new UndefinedValue();
    
}