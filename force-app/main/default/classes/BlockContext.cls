/*
 * Mike Ulveling
 */
public class BlockContext {
    
    // nested blocks:
    public static final Integer BLOCK_PLAIN         =  0;
    public static final Integer BLOCK_TRY           =  1;
    public static final Integer BLOCK_CATCH         =  2;
    public static final Integer BLOCK_FINALLY       =  3;
    public static final Integer BLOCK_LOOP          =  4;
    public static final Integer BLOCK_ENUM          =  5;
    public static final Integer BLOCK_SWITCH        =  6;
    public static final Integer BLOCK_WITH          =  7;
    // top-level blocks:
    public static final Integer BLOCK_GLOBAL        =  8;
    public static final Integer BLOCK_FUNCTION      =  9;
    public static final Integer BLOCK_EVAL          = 10;
    
    /*
     * the following attributes are initialized by block type, and will not vary after initialisation:
     */
    
    public Integer blockType;
    // only Try and Catch blocks are deferring:
    public Boolean isDeferring;

    // set to true only for global, function, and eval blocks:
    public Boolean isTopLevel;
    // set to true only for global, function, eval, and catch blocks in ECMAScript5:
    public Boolean isDeclarative;    
    // set to true only for function blocks and catch blocks in ECMAScript5; an eval block's local decs are not stack-convertible because they are
    // configurable (i.e. deletable), and the global object can have its bindings defined as accessors and/or can have its bindings dynamically
    // referenced by nested code units via an indirect-call eval:
    public Boolean isDeclarativeStackable;

    // defines whether this block can be targeted by continue stmts; true only for Loop and Enum blocks:
    public Boolean canContinue;
    // Loop, Enum, and Switch blocks provide an implicit empty label:
    public Boolean hasImplicitEmptyLabel;
    
    // the # of stack slots reserved for the given block type:
    //   1. finally blocks reserve 2 slots; 1 for an instruc return address and 1 for a curry value
    //   2. enum blocks reserve 1 slot for the enum object
    //   3. try, catch, and with blocks reserve 1 slot to store the current lexical env
    //   3.a. additionally note that catch block's total stack slot usage may increase to 2 if its error var is converted to a stack var
    //   4. global and eval blocks each reserve exactly 1 slot for the result; note that these blocks' local declarations are not stackable
    //   5. all other block types reserve 0 slots; their total stack slot usage will be 0 unless isDeclarativeStackable==true, in which case usage
    //      will be wholly determined by how many local decs are converted to stack vars
    public Integer reservedStackSlots = 0;
    
    /*
     * the following attributes are set/collected at the very beginning of this block's pass 1 compilation, and will be accessible during that pass:
     */
    
    // the top-level code unit; you may access the top-level block via: hostCode.topBlock
    public CodeContext hostCode;
    // the parent block that this block is directly nested within; for all top-level block types this must be null:
    public BlockContext outerBlock;
    
    // the local labels on this block; will apply to continue and/or break depending on the block type. this will be non-null if and only if this
    // block has at least 1 explicit non-empty label (i.e. the implicit empty label is not stored in this collection). the presence or absence of an
    // empty label on this block may only be determined by examining the "hasImplicitEmptyLabel" attribute.
    public Set<String> explicitLabels;
    
    /*
     * the following attributes are aggregation results compiled during pass 1 compilation; their results will not be complete and ready for
     * inspection until after the pass 1 processing of this block is completed (i.e. after the block is completely parsed):
     */
     
    // flagged to true if it's determined that this block must create a local environment record: 
    //   1. top-level global blocks always create an env (init to true on creation)
    //   2. top-level eval blocks create an env contingent upon being strict mode
    //   3. function blocks conditionally create an env based on information collected inside the block
    //   4. catch blocks conditionally create an env based on information collected inside the block
    public Boolean createsEnv = false;
    
    // flagged to true if this is a top-level block that contains a block-nested (not code-nested) direct-call to the built-in eval function:
    public Boolean topLevelEvalDirectCall = false;
    
    // flagged to true for any BlockContext that either directly or indirectly -- through any nesting of blocks and/or CodeContexts -- contains a direct-call
    // to the built-in eval function:
    public Boolean inheritsEvalDirectCall = false;
    // flagged to true -- for a top-level-block only -- when an instance of Instruc.EnvRef with the name of "arguments" occurs within this
    // block or any nested block (though NOT allowed to cross CodeContext boundaries).
    // ** note that a Function can bypass creation of the ArgumentsObject (during Declaration Binding Instantiation) if (but not only if; it can also
    // bypass creation if the "arguments" name is used by a FunctionDeclaration and/or Formal Parameter) its top-level block satisfies: 
    // !topLevelArgumentsRef && !inheritsEvalDirectCall
    public Boolean topLevelArgumentsRef = false;
    
    // for top-level blocks only: collects all instances of VarDeclarations and FunctionDeclarations that are local to this.hostCode (even if nested
    // many blocks deep), maintaining source order:
    public Lexer2.Token[] topLevelVarDecs;
    public CodeContext.Function[] topLevelFuncDecs;
    
    // JSR instrucs are block-controls that require special handling, so they're collected separately from the other block-controls. a JSR will have
    // a "hostBlock" and "deferringBlock" which define a block chain segment; by traversing the chain in pass 2 we can calculate the stack offsets for
    // lexEnv-restore and stack-restore, and also whether either or both of these restores can be bypassed:
    // e.g. if we didn't encounter any block with createsEnv==true along the chain (inclusive of endpoints), then the JSR can bypass the lexEnv-
    //      restore. 
    // e.g. if the deferringBlock.<stackAllocLen>==0 and hostBlock.segOffset==deferringBlock.segOffset, then the JSR can bypass the stack-restore.
    // ** note that if a particular JSR's SubRoutine jump can be bypassed (iff no Finally block) as well as its lexEnv-restore and stack-restore, then
    //    we can replace that JSR with a NOOP (TODO: determine the best mechanism for inline conversion of a JSR into a NOOP).
    
    // collects all break/continue/jsr/rsr/catch/rest instrucs local to this code unit for pass2 resolution:
    public Instruc.BlockControl[] topLevelBlockControls;
    
    // the following pseudo-code explains how the aggregateUp method processes the following 6 sets for nested blocks:
    // aggregateUp:
    //   localDecStackableNames := SUBTRACT(localDecNames, UNION(possibleWithBoundNames, crossingCodeNestedRefNames))
    //   stackRefsByName := every ref in candidateStackRefs where ref.name matches an element in localDecStackableNames
    //   outerBlock.possibleWithBoundNames.addAll(SUBTRACT(possibleWithBoundNames, localDecNames))
    //   outerBlock.crossingBlockNestedRefNames.addAll(SUBTRACT(crossingBlockNestedRefNames, localDecNames))
    //   outerBlock.crossingCodeNestedRefNames.addAll(SUBTRACT(crossingCodeNestedRefNames, localDecNames))
    //   outerBlock.candidateStackRefs.addAll(SUBTRACT(candidateStackRefs, every ref in candidateStackRefs where ref.name matches localDecNames))
    
    // collects all instances of environment refs that either came directly from this block (added directly to this block via parsedEnvironmentRef) or
    // from a nested block (i.e. added to this block via a nested block's aggregateUp()). candidateStackRefs are not allowed to propagate across
    // CodeContext boundaries (i.e. top-level blocks) nor with-blocks; also, candidateStackRefs in a block wrapping a nested with-block may be negated
    // by env refs (of the same name) within that with-block (see possibleWithBoundNames). once we determine the full set of local dec names to be
    // converted to stack vars (see localDecStackableNames), candidateStackRefs is iterated, and env refs matching one of these stackable names are
    // added into the stackRefsByName map, which will subsequently processed to mutate the held environment refs into stack refs.
    // !! this is an aggregateUp() collection intermediate, not to be used as an end-product of this block
    public Instruc.EnvRef[] candidateStackRefs;
    
    // a refinement of candidateStackRefs:
    // collects all instances of EnvRef type Instrucs (even if nested many blocks deep relative to this "stackBindingBlock", but not to
    // cross CodeContext boundaries) that have resolved to a stack-able local declaration of this block.
    // each member refs' stack slot will be resolved, allocated, and assigned during pass 2 (immediately before 1st Declaration Binding Instantiation
    // for CodeContext or BlockContext; the EnvRef's "stackBindingBlock" is key to the stack allocation process), and the stack slot
    // values will be initialized during Declaration Binding Instantiation:
    // ** TODO: we might also use this collection -- in conjunction with a "Boolean isAssignee" flag on Instruc.EnvRef, to be set by the
    //          parser -- to determine whether any of the converted references represent an immutable-binding PUT violation (in ECMAScript5, only
    //          "arguments" and a FunctionExpression's recusive name binding can possibly be immutable). any converted ref that's determined to be a
    //          violation will be flagged appropriately; when a PUSH op encounters such a reference, it will push a special instance of
    //          ImmutableStackVarViolation.
    // ** TODO: make this a MAP<String, Instruc.EnvRef[]> stackBindingRefsByName, of binding name to its references. this will make the
    //    pass2 and Declaration Binding Instantiaton process easier and more efficient: 
    // !! this is an end-product of this block, to be used by pass2 compilation for resolving Declaration Binding Instantations
    public Map<String, Instruc.EnvRef[]> stackRefsByName;
    
    // whenever we close a with-block, all enclosed candidateStackRefs become invalid (i.e. they aren't processed as candidates in that block, and
    // they don't propagate to the outer block). furthermore, the set of names represented by the invalidated candidateStackRefs gets added to the
    // outer block's possibleWithBoundNames set. when a declarative block type calls aggregateUp(), its candidateStackRefs will be cross-referenced
    // against its localDecNames and UNION(possibleWithBoundNames, crossingCodeNestedRefNames) as follows:
    //   if a local dec name is in the above UNION, then it cannot be added to localDecStackableNames/stackRefsByName
    // note that (aside from with-blocks) we currently don't filter the outer-block propagation of candidateStackRefs by possibleWithBoundNames;
    // instead we propagate possibleWithBoundNames in parallel with the candidateStackRefs -- though note that these sets are both filtered by that
    // block's localDecNames before propagation to outer. see above for a full pseudo-code description of the aggregateUp logic.
    // !! this is an aggregateUp() collection intermediate, not to be used as an end-product of this block
    public Set<String> possibleWithBoundNames;
    
    // the names of functions and variables which are declared locally in this block. FunctionDeclarations and VarDeclarations all get hoisted to
    // a top-level block through any # of nesting blocks (though not to cross code boundaries). also note that in ECMAScript5, the Catch block is
    // the only nestable block that has its own (non-hoisted) local variable, and Catch and With are the only non-top-level blocks that may create
    // their own lexEnv (a lexEnv is created unconditionally in the case of a with-block, and conditionally -- based on necessity -- in the case of
    // a catch):
    public Set<String> localDecNames;
    // the names of environment refs -- NOT crossing any CodeContext boundary before reaching this block, though it may cross any # of nested blocks
    // -- that MUST check this block's environment record (lexEnv) for identifier resolution. i.e. these environment refs may be resolved at this
    // block's lexEnv, or else they'll have to check outside this block for resolution, but it's already been determined they definitely will NOT be
    // resolved in any nested block:
    public Set<String> crossingBlockNestedRefNames;
    // the names of environment refs -- crossing at least 1 nested CodeContext boundary before reaching this block -- that MUST check this block's
    // environment record (lexEnv) for identifier resolution. i.e. these environment refs may be resolved at this block's lexEnv, or else they'll
    // have to check outside this block for resolution, but it's already been determined they definitely will NOT be resolved in any nested block or
    // CodeContext:
    public Set<String> crossingCodeNestedRefNames;
    
    // local declarations (i.e. members of localDecNames) that can be converted to stack-variables, because it has been determined that no nested
    // CodeContexts can possibly reference them:
    // ** note that if this block is an EvalBody, then NONE of the local declarations are stack-able (i.e. this set must be made empty), because the
    // eval CodeContext's environment record creates confgurable (i.e. deletable) bindings:
    public Set<String> localDecStackableNames;
    
    // all nestable blocks will record their endAddr:
    public Integer endAddr;
    // only loop and enum blocks will record their continueAddr:
    public Integer continueAddr;
    
    /*
     * the following attributes are calculated during pass 2 compilation, upon first dispatch of the host code unit (i.e. during 1st Declaration
     * Binding Instantiation):
     */
     
    // the segmented stack offset for this block (i.e. the top-level block always has segOffset=0; its actual stack segment start is determined
    // dynamically). this is calculated in pass 2 compilation (during the 1st Declaration Binding Instantiation):
    public Integer segOffset;
    
    // takes in a block that has just completed its pass1 parse; compiles local dec names which are to be converted to stack vars, and propagates
    // certain pieces of aggregated information to its next outer block (top-level blocks aggregate into their own "topLevel*" variables):
    public static void aggregateUp(BlockContext parsed) {
        
        // compute the set of local dec names that are stack-var convertible:
        // if we have local dec names, then in ECMAScript5 that means this must be either a top-level block or a catch block. also:
        //   1. blocks inheriting an eval direct call (any # of blocks or functions deep) cannot do any stack conversions because they must assume
        //      all of their local decs will be nested-code-bound (note we don't bother to set the parsed.hasLocalDecCodeBoundRef flag in this case 
        //      because the inheritsEvalDirectCall flag is either-or in all usages of these flags (e.g. the createsEnv determination)). 
        //   2. eval blocks don't allow for stack conversion of vars because the bindings are configurable:
                
        // only global-block, function-block, and catch-block are flagged isDeclarativeStackable=true (upon creation):
        if (parsed.isDeclarativeStackable && parsed.localDecNames != null && !parsed.inheritsEvalDirectCall) {
//        if (parsed.localDecNames != null && !parsed.inheritsEvalDirectCall && parsed.blockType != BLOCK_EVAL) {
            // if crossingCodeNestedRefNames and possibleWithBoundNames are both empty, then every local declaration is stack convertible:
            if (parsed.crossingCodeNestedRefNames == null && parsed.possibleWithBoundNames == null) {
                // !! note that we don't need to clone, because neither set will be modified past this point:
                parsed.localDecStackableNames = parsed.localDecNames; // .clone();
            // else we need to check each localDec against the crossingCodeNestedRefNames and possibleWithBoundNames sets:
            } else {
                for (String localDec: parsed.localDecNames) {
                    // localDecCodeBoundNames := INTERSECT(localDecNames, crossingCodeNestedRefNames)
                    // localDecPossibleWithBoundNames := INTERSECT(localDecNames, possibleWithBoundNames)
                    if (parsed.crossingCodeNestedRefNames != null && parsed.crossingCodeNestedRefNames.contains(localDec) 
                            || parsed.possibleWithBoundNames != null && parsed.possibleWithBoundNames.contains(localDec)) {
                        // note that global code unconditionally creates an env:
                        if (!parsed.createsEnv)
                            parsed.createsEnv = true;
                    // localDecStackableNames := SUBTRACT(localDecNames, UNION(localDecCodeBoundNames, localDecPossibleWithBoundNames))
                    } else {
                        if (parsed.localDecStackableNames == null)
                            parsed.localDecStackableNames = new Set<String>{ localDec };
                        else
                            parsed.localDecStackableNames.add(localDec);
                    }
                }
            }
        }
        
        if (parsed.isTopLevel) {
            // top-level function blocks implement special aggregation logic:
            if (parsed.blockType == BLOCK_FUNCTION) {            
                // static functions (!! excepting dynamic functions) are the only top-level block that have a compile-time determinable outer (i.e.
                // wrapping) block. note that the function parser will set this outerBlock reference:
                BlockContext wrappingBlock = parsed.outerBlock;
                
                // top-level function blocks create an env if it's got a code-bound or possible with-bound local dec name (see above) or if it
                // inherits an eval direct-call (note that the presence of topLevelOutgoingRefNames does not necessitate env creation for that
                // function block):
                if (parsed.inheritsEvalDirectCall) {
                    // top-level global blocks always create an env; top-level eval blocks create an env contingent upon being direct-call and
                    // strict mode; top-level function blocks create an env if it's got a code-bound or candidate with-bound local dec name (see
                    // above) or if it inherits an eval direct-call (note that the presence of topLevelOutgoingRefNames does not necessitate env
                    // creation for that function block):
                    parsed.createsEnv = true;
                    // wrappingBlock will be null for dynamic functions and non-null for static functions:
                    if (wrappingBlock != null)
                        wrappingBlock.inheritsEvalDirectCall = true;
                // !! if a non-strict function contains a reference to its Arguments object, and it has at least 1 formal param, then we must bind
                // all formal params to the LexicalEnvironment, and this of course also necessitates the creation of a lexEnv; this is because it's
                // possible for the Arguments object to be assigned out of this host function, and then have a mapped param referenced after the
                // host function has terminated (i.e. formal params cannot be stack bound in this scenario):
                // TODO: move the following logic to Declaration Binding Instantiation for Functions:
                //} else if (parsed.topLevelArgumentsRef && !parsed.hostCode.strict 
                //        && ((CodeContext.Function) parsed.hostCode).formalParams.size() > 0) {
                //    parsed.createsEnv = true;
                }
                
                // only perform the following outgoingRefNames => wrappingBlock logic for static functions (skip for dynamic functions, which will
                // not have a wrappingBlock reference):
                if (wrappingBlock != null) {
                    // this function block's crossingBlockNestedRefNames and crossingCodeNestedRefNames are union'd to form the set
                    // topLevelOutgoingRefNames; subtract from this union the function's local dec names, and then augment the wrapping block's
                    // crossingCodeNestedRefNames with this result set:
                    Set<String> topLevelOutgoingRefNames;
                    if (parsed.crossingCodeNestedRefNames != null)
                        topLevelOutgoingRefNames = parsed.crossingCodeNestedRefNames; // no clone() necessary
                    if (parsed.crossingBlockNestedRefNames != null) {
                        if (topLevelOutgoingRefNames == null)
                            topLevelOutgoingRefNames = parsed.crossingBlockNestedRefNames; // no clone() necessary
                        else
                            topLevelOutgoingRefNames.addAll(parsed.crossingBlockNestedRefNames);
                    }
                    
                    if (topLevelOutgoingRefNames != null && parsed.localDecNames != null)
                        topLevelOutgoingRefNames.removeAll(parsed.localDecNames);
                    if (topLevelOutgoingRefNames != null && topLevelOutgoingRefNames.size() > 0) {
                        if (wrappingBlock.crossingCodeNestedRefNames == null)
                            wrappingBlock.crossingCodeNestedRefNames = topLevelOutgoingRefNames; // no clone() necessary
                        else
                            wrappingBlock.crossingCodeNestedRefNames.addAll(topLevelOutgoingRefNames);
                    }
                    
                    // !! note that we need not propagate possibleWithBoundNames outwards to the wrappingBlock, because those same names are
                    // guaranteed to be included in the topLevelOutgoingRefNames set, which will add into any wrapping block's
                    // crossingCodeNestedRefNames, and there serve essentially the same purpose.
                }
            }
            // note that unlike static function blocks, global and eval blocks will never have a wrappingBlock reference...
            
            // pass1 parsing of this code unit is now complete; perform pass2 compilation:
            if (parsed.topLevelBlockControls != null) {
                for (Instruc.BlockControl blockCtrl: parsed.topLevelBlockControls) {
                    blockCtrl.resolvePass2();
                }
            }
            
            // TODO: compile Declaration Binding Instantiation sub-instructions:
            parsed.hostCode.compileDecBindSubInstrucs();

        // else this is a nested block:
        } else { // if (!parsed.isTopLevel) {
            // pass relevant information to the outer block:
            BlockContext outerBlock = parsed.outerBlock;
            if (parsed.inheritsEvalDirectCall)
                outerBlock.inheritsEvalDirectCall = true;
            
            // if we have crossing block-nested refs, then determine which (if any) should propagate to the outer block:
            if (parsed.crossingBlockNestedRefNames != null) {
                // remove all local dec names; they will bind to each matching parsed.crossingBlockNestedRefNames so that the ref cannot cross
                // outside of this block:
                if (parsed.localDecNames != null)
                    // !! note that we can mutate parsed.crossingBlockNestedRefNames, because it will not be referenced beyond this point:
                    parsed.crossingBlockNestedRefNames.removeAll(parsed.localDecNames);
                
                if (outerBlock.crossingBlockNestedRefNames == null)
                    outerBlock.crossingBlockNestedRefNames = parsed.crossingBlockNestedRefNames;
                else
                    outerBlock.crossingBlockNestedRefNames.addAll(parsed.crossingBlockNestedRefNames);            
            }
            // if we have crossing code-nested refs, then determine which (if any) should propagate to the outer block:
            if (parsed.crossingCodeNestedRefNames != null) {
                // remove all local dec names; they will bind to each matching parsed.crossingCodeNestedRefNames so that the ref cannot cross
                // outside of this block:
                if (parsed.localDecNames != null)
                    // !! note that we can mutate parsed.crossingCodeNestedRefNames, because it will not be referenced beyond this point:
                    parsed.crossingCodeNestedRefNames.removeAll(parsed.localDecNames);
                
                if (outerBlock.crossingCodeNestedRefNames == null)
                    outerBlock.crossingCodeNestedRefNames = parsed.crossingCodeNestedRefNames;
                else
                    outerBlock.crossingCodeNestedRefNames.addAll(parsed.crossingCodeNestedRefNames);
            }
            
            // below we handle the aggregation of candidateStackRefs and possibleWidthBoundNames, which are interactive sets:

            // with-blocks implement special handling for candidateStackRefs:
            if (parsed.blockType == BLOCK_WITH) {
                if (parsed.candidateStackRefs != null) {
                    // any refs that go through a with-block cannot be converted to stack vars; also note that:
                    //   1. a with block will have no local decs
                    //   2. none of this with-block's candidateStackRefs get propagated to the outer block
                    if (outerBlock.possibleWithBoundNames == null)
                        outerBlock.possibleWithBoundNames = new Set<String>();
                    for (Instruc.EnvRef envRef: parsed.candidateStackRefs) {
                        outerBlock.possibleWithBoundNames.add(envRef.strVal);
                    }
                }
            // other types of nested blocks all implement the same logic for aggregating candidateStackRefs and possibleWidthBoundNames:
            } else {
                // if there are no localDecNames in this block (i.e. all ECMAScript5 blocks other than top-level blocks and the Catch block), then
                // that implies there are also no stackable decs in this block, and we can propagate to the outer block:
                //   1. all candidate refs 
                //   2. all possibly with-block-bound names
                // i.e. none of the names in these 2 sets will bind to this block, and none will be masked either.
                // also note that this scenario will yield no stack refs for this block.
                if (parsed.localDecNames == null) {
                    
                    if (parsed.candidateStackRefs != null) {
                        if (outerBlock.candidateStackRefs == null)
                            // !! note that we don't need to clone, because parsed.candidateStackRefs will not be referenced past this point:
                            outerBlock.candidateStackRefs = parsed.candidateStackRefs;
                        else
                            outerBlock.candidateStackRefs.addAll(parsed.candidateStackRefs);
                    }
                    
                    if (parsed.possibleWithBoundNames != null) {
                        if (outerBlock.possibleWithBoundNames == null)
                            outerBlock.possibleWithBoundNames = parsed.possibleWithBoundNames; // no clone needed
                        else
                            outerBlock.possibleWithBoundNames.addAll(parsed.possibleWithBoundNames);
                    }
                
                // else, if there are localDecNames in this block, then we perform 2 actions in the subsequent code:
                //   1. calculate propagation (to outer block) of the candidateStackRefs and possibleWidthBoundNames sets, which are each reduced
                //      (i.e. masked) by the names in localDecNames
                //   2. find elements in this block's candidateStackRefs that match the previously calculated localDecStackableNames, and map these
                //      refs in stackRefsByName -- this latter set is 1 of this block's primary products for pass2 compilation
                } else {
                    
                    // iterate through the candidateStackRefs:
                    if (parsed.candidateStackRefs != null) {
                        for (Instruc.EnvRef envRef: parsed.candidateStackRefs) {
                            // localDecStackableNames is guaranteed to not include names that are code-bound or possibly with-block-bound:
                            if (parsed.localDecStackableNames != null && parsed.localDecStackableNames.contains(envRef.strVal)) {
                                // add this ref to the appropriate bucket under the this block's stackRefsByName map; the physical stack allocations will be
                                // calculated in pass2 compilation:
                                if (parsed.stackRefsByName == null)
                                    parsed.stackRefsByName = new Map<String, Instruc.EnvRef[]>{
                                            envRef.strVal => new Instruc.EnvRef[]{ envRef }
                                        };
                                else {
                                    Instruc.EnvRef[] ofSameName = parsed.stackRefsByName.get(envRef.strVal);
                                    if (ofSameName == null)
                                        parsed.stackRefsByName.put(envRef.strVal, new Instruc.EnvRef[]{ envRef });
                                    else
                                        ofSameName.add(envRef);
                                }
                                
                            // else no match to a local stack-able declaration; propagate this candidate to the outer block iff it isn't masked by a local
                            // declaration:
                            } else if (!parsed.localDecNames.contains(envRef.strVal)) {
                                // if it was not resolved to a stack-var in this block, but it also isn't a local declaration to this block, then propagate it
                                // to the next outer block for possible stack-ref conversion there.
                                // !! note that this allows converted refs to be nested any # of blocks deep relative to its stackBindingBlock, but we don't
                                // allow them to pass through top-level blocks or with-blocks:
                                if (outerBlock.candidateStackRefs == null)
                                    outerBlock.candidateStackRefs = new Instruc.EnvRef[]{ envRef };
                                else
                                    outerBlock.candidateStackRefs.add(envRef);
                            }
                        }
                    }
                    
                    if (parsed.possibleWithBoundNames != null) {
                        // outer.withBoundNames := UNION(outer.withBoundNames, SUBTRACT(parsed.withBoundNames, parsed.localDecNames))
                        Set<String> outgoingWithBoundNames;
                        if (parsed.localDecNames != null) {
                            parsed.possibleWithBoundNames.removeAll(parsed.localDecNames);
                        }
                        outgoingWithBoundNames = parsed.possibleWithBoundNames;
                            
                        if (outerBlock.possibleWithBoundNames == null)
                            outerBlock.possibleWithBoundNames = outgoingWithBoundNames;
                        else
                            outerBlock.possibleWithBoundNames.addAll(outgoingWithBoundNames);
                    }
                }
            }
        }
    }
    
    // this must not be called until after all aggregateUp() calls in the host code unit have completed, i.e. in pass2:
    public static Integer resolveSegOffset(BlockContext block) {
        if (block.segOffset != null)
            return block.segOffset;
        
        BlockContext outerBlock = block.outerBlock;
        // !! note that by using the stackRefsByName map to count stack vars, we don't count unreferenced local vars, so they must NOT be stack-
        // allocted during Declaration Binding Instantiation:
        return (outerBlock.segOffset != null ? outerBlock.segOffset : resolveSegOffset(outerBlock)) 
                // to the outer block's start offset we add its reserved slots plus any of its local bindings that have been converted to stack vars:
                + outerBlock.reservedStackSlots + outerBlock.stackRefsByName.keySet().size();
    }
    
    /*
    public static void parsedArgumentsRef(CodeContext hostCode) {
        hostCode.topLevel.topLevelArgumentsRef = true;
    }
    */
    
    public static void parsedEvalDirectCall(BlockContext hostBlock) {
        hostBlock.inheritsEvalDirectCall = true;
        hostBlock.hostCode.topLevel.topLevelEvalDirectCall = true;
    }
    
    // this one you may wish to inline in the expr parser, because it's going to be pretty common:
    public static void parsedEnvRef(BlockContext hostBlock, Instruc.EnvRef envRef) {
        if (hostBlock.candidateStackRefs == null)
            hostBlock.candidateStackRefs = new Instruc.EnvRef[]{ envRef };
        else 
            hostBlock.candidateStackRefs.add(envRef);
            
        if (hostBlock.crossingBlockNestedRefNames == null)
            hostBlock.crossingBlockNestedRefNames = new Set<String>{ envRef.strVal };
        else
            hostBlock.crossingBlockNestedRefNames.add(envRef.strVal);
        
        if (hostBlock.hostCode.topLevel.blockType == BLOCK_FUNCTION && envRef.intVal == Lexer2.IDENT_NAME_EVAL_OR_ARGUMENTS && 'arguments'.equals(envRef.strVal))
            hostBlock.hostCode.topLevel.topLevelArgumentsRef = true;
    }
    
    // TODO: determine whether you want to handle the initialiser ref separately (i.e. have client code explicitly call parsedEnvironmentRef for it):
    // !! I think we should keep the parsedVarDec and parsedEnvironmentRef calls separate; consider a for-var-in loop
    public static void parsedVarDec(BlockContext hostBlock, Lexer2.Token var, Instruc.EnvRef initialiserRef) {
        BlockContext topLevel = hostBlock.hostCode.topLevel;
        if (topLevel.topLevelVarDecs == null)
            topLevel.topLevelVarDecs = new Lexer2.Token[]{ var };
        else
            topLevel.topLevelVarDecs.add(var);
            
        if (topLevel.localDecNames == null)
            topLevel.localDecNames = new Set<String>{ var.lexeme };
        else    
            topLevel.localDecNames.add(var.lexeme);
        
        // var decs don't necessarily have a corresponding initialiser expr, but if they do, then the lhs is serialized as an environment ref. note:
        // the env ref's binding is determined by its host LexicalEnvironment, which can differ from the actual var dec's binding in the case of a
        // host catchBlock with an errorVar of the same name:
        if (initialiserRef != null)
            // note that a var w/initialiser in a catch block of the same name as the error variable will have its initialiser ref bind to the catch
            // block's error var, not the top-level var declared as a result of that very same var declaration!
            parsedEnvRef(hostBlock, initialiserRef);
    }
    
    public static void parsedFunctionDec(BlockContext hostBlock, CodeContext.Function funcCode) {
        BlockContext topLevel = hostBlock.hostCode.topLevel;
        if (topLevel.topLevelFuncDecs == null)
            topLevel.topLevelFuncDecs = new CodeContext.Function[]{ funcCode };
        else
            topLevel.topLevelFuncDecs.add(funcCode);
        
        if (topLevel.localDecNames == null)
            topLevel.localDecNames = new Set<String>{ funcCode.name };
        else    
            topLevel.localDecNames.add(funcCode.name);
    }
    
    // the Parser should use this method to create REST_BLOCK instrucs; as block controls, they need to be registered with the top-level block:
    public static Instruc.RestBlock createRestBlock(BlockContext targetBlock) {
        Instruc.RestBlock restBlock = new Instruc.RestBlock(); // we don't need to tag REST_BLOCK with a loc
        restBlock.targetBlock = targetBlock;
        
        BlockContext topLevel = targetBlock.hostCode.topLevel;
        if (topLevel.topLevelBlockControls == null)
            topLevel.topLevelBlockControls = new Instruc.BlockControl[]{ restBlock };
        else
            topLevel.topLevelBlockControls.add(restBlock);
        
        return restBlock;
    }
        
    // breaks are tricky; each deferring block we encounter on the way to the enclosing target block will cause the serialization of a "guarding" JSR
    // instruc. throws ParseException (i.e. SyntaxError) if no enclosing target block was found before hitting a top-level block:
    public static void serializeBreak(BlockContext hostBlock, Lexer2.Token targetLabel, Lexer2.Token breakTok) {
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        Boolean foundTarget = false;
        BlockContext topLevel = hostBlock.hostCode.topLevel,
              startBlock = hostBlock,
              currBlock = hostBlock;
        // quit if we hit a top-level block; breaks cannot target across code boundaries, nor can they target a top-level block:
        while (!currBlock.isTopLevel) {
            // each enclosing try or catch block we encounter causes a new JSR to be serialized; these JSR's can only be fully resolved in pass2.
            // !! note that the target block cannot -- by definition -- also be deferring (note: an explicit label or labels on a try stmt causes the
            // creation of a wrapper PlainBlock around the try/catch/finally blocks), so we don't have to handle these two cases in tandem:
            if (currBlock.isDeferring) {
                Instruc.JSR jsr = new Instruc.JSR();
                jsr.loc = breakTok;
                // this JSR op will be dispatched somewhere within the execution state of the startBlock, meaning:
                //   1. the vm stack will have advanced startBlock.reservedStackSlots + startBlock.localDecStackableNames.size()) slots beyond the
                //      startBlock's (segmented) start offset
                //   2. if the start block creates an env, then the old lexEnv will be stored on the stack at the block's start offset
                // pass2 will iterate from this JSR's startBlock to targetBlock, aggregating the outer-most stored lexEnv (only from blocks for which
                // createsEnv=true) and stack start offset to be restored. note that pass2 resolves the lexEnv/stack restores each to an Integer offset in
                // the stack segment for the host execution context, and also resolves the JSR's jumpAddr:
                jsr.startBlock = startBlock;
                // for a JSR, the targetBlock represents:
                //   1. the try or catch block (i.e. deferring block) from which will jump to its corresponding finally block (if any)
                //   2. the outer-most block to be rest'd (lexEnv and stack) by this JSR. 
                // the JSR targetBlock also enables pass2 to derive the JSR's jumpAddr by way of: targetBlock.finallyBlock.startAddr. note that if
                // finallyBlock==null, then the jump portion of the JSR will be flagged as a no-op (i.e. the lexEnv & stack restore still needs to occur,
                // but the jump to the jumpAddr will be skipped):
                jsr.targetBlock = currBlock;
                jsr.boolVal = false; // JSR's guarding a break or continue never curry a value
                instrucs.add(jsr);
                // point to the next op, whether it be a subsequent guarding JSR or the BREAK itself:
                jsr.returnAddr = instrucs.size();
                
                // all "block control" type instrucs -- including any issued JSR's -- are collected in the host code unit's top-level block, so that
                // pass2 can resolve the lexEnv & stack restore indexes:
                if (topLevel.topLevelBlockControls == null)
                    topLevel.topLevelBlockControls = new Instruc.BlockControl[]{ jsr };
                else
                    topLevel.topLevelBlockControls.add(jsr);
                
                currBlock = startBlock = currBlock.outerBlock;
                
            } else if (targetLabel == null && currBlock.hasImplicitEmptyLabel 
                    || targetLabel != null && currBlock.explicitLabels != null && currBlock.explicitLabels.contains(targetLabel.lexeme)) {
                foundTarget = true;
                break;
            } else {
                currBlock = currBlock.outerBlock;
            }
        }
        
        if (!foundTarget)
            throw new ParseException('break control is not enclosed in a ' 
                    + (targetLabel != null ? 'loop, switch, or code block bearing the target label \'' + targetLabel.lexeme 
                    + '\'' : 'loop or switch block'), breakTok);
    
        Instruc.BreakControl brk = new Instruc.BreakControl();
        brk.loc = breakTok;
        brk.startBlock = startBlock;
        brk.targetBlock = currBlock;
        instrucs.add(brk);
        
        // a break instruc's intVal addr is set in resolvePass2() as the target block's endAddr, which is set appropriately by the parser for each
        // block type:
        if (topLevel.topLevelBlockControls == null)
            topLevel.topLevelBlockControls = new Instruc.BlockControl[]{ brk };
        else
            topLevel.topLevelBlockControls.add(brk);
    }
    
    // outputs 0 or more JSR instrucs, as necessary, before serializing the CONTINUE
    // throws SyntaxError if no enclosing continue target block was found before hitting a top-level block
    public static void serializeContinue(BlockContext hostBlock, Lexer2.Token targetLabel, Lexer2.Token continueTok) {
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        Boolean foundTarget = false;
        BlockContext topLevel = hostBlock.hostCode.topLevel,
              startBlock = hostBlock,
              currBlock = hostBlock;
        // quit if we hit a top-level block; breaks cannot target across code boundaries, nor can they target a top-level block:
        while (!currBlock.isTopLevel) {
            // each enclosing try or catch block we encounter causes a new JSR to be serialized; these JSR's can only be fully resolved in pass2.
            // !! note that the target block cannot -- by definition -- also be deferring (note: an explicit label or labels on a try stmt causes the
            // creation of a wrapper PlainBlock around the try/catch/finally blocks), so we don't have to handle these two cases in tandem:
            if (currBlock.isDeferring) {
                Instruc.JSR jsr = new Instruc.JSR();
                jsr.loc = continueTok;
                // this JSR op will be dispatched somewhere within the execution state of the startBlock, meaning:
                //   1. the vm stack will have advanced startBlock.reservedStackSlots + startBlock.localDecStackableNames.size()) slots beyond the
                //      startBlock's (segmented) start offset
                //   2. if the start block creates an env, then the old lexEnv will be stored on the stack at the block's start offset
                // pass2 will iterate from this JSR's startBlock to targetBlock, aggregating the outer-most stored lexEnv (only from blocks for which
                // createsEnv=true) and stack start offset to be restored. note that pass2 resolves the lexEnv/stack restores each to an Integer offset in
                // the stack segment for the host execution context, and also resolves the JSR's jumpAddr:
                jsr.startBlock = startBlock;
                // for a JSR, the targetBlock represents:
                //   1. the try or catch block (i.e. deferring block) from which will jump to its corresponding finally block (if any)
                //   2. the outer-most block to be rest'd (lexEnv and stack) by this JSR. 
                // the JSR targetBlock also enables pass2 to derive the JSR's jumpAddr by way of: targetBlock.finallyBlock.startAddr. note that if
                // finallyBlock==null, then the jump portion of the JSR will be flagged as a no-op (i.e. the lexEnv & stack restore still needs to occur,
                // but the jump to the jumpAddr will be skipped):
                jsr.targetBlock = currBlock;
                jsr.boolVal = false; // JSR's guarding a break or continue never curry a value
                instrucs.add(jsr);
                // point to the next op, whether it be a subsequent guarding JSR or the BREAK itself:
                jsr.returnAddr = instrucs.size();
                
                // all "block control" type instrucs -- including any issued JSR's -- are collected in the host code unit's top-level block, so that
                // pass2 can resolve the lexEnv & stack restore indexes:
                if (topLevel.topLevelBlockControls == null)
                    topLevel.topLevelBlockControls = new Instruc.BlockControl[]{ jsr };
                else
                    topLevel.topLevelBlockControls.add(jsr);
                
                currBlock = startBlock = currBlock.outerBlock;
                
            // here we must add a necessary condition vs. break; the potential target block must be continue-able (i.e. a loop block or enum block):
            } else if (currBlock.canContinue && (targetLabel == null && currBlock.hasImplicitEmptyLabel 
                    || targetLabel != null && currBlock.explicitLabels != null && currBlock.explicitLabels.contains(targetLabel.lexeme))) {
                foundTarget = true;
                break;
            } else {
                currBlock = currBlock.outerBlock;
            }
        }
        
        if (!foundTarget)
            throw new ParseException('continue control is not enclosed in a ' 
                    + (targetLabel != null ? 'loop bearing the target label \'' + targetLabel.lexeme 
                    + '\'' : 'loop'), continueTok);
    
        Instruc.ContinueControl cont = new Instruc.ContinueControl();
        cont.loc = continueTok;
        cont.startBlock = startBlock;
        cont.targetBlock = currBlock;
        instrucs.add(cont);
        
        // a continue instruc's intVal addr is set in resolvePass2() as the target block's continueAddr, which is set appropriately by the parser for
        // each loop type:
        if (topLevel.topLevelBlockControls == null)
            topLevel.topLevelBlockControls = new Instruc.BlockControl[]{ cont };
        else
            topLevel.topLevelBlockControls.add(cont);
    }
    
    // outputs 0 or more JSR instrucs (curry-value flag set to true), as necessary, before serializing the RETURN
    // throws SyntaxError if no hostCode is not a function
    public static void serializeReturn(BlockContext hostBlock, Boolean hasExplicitValueExpr, Lexer2.Token returnTok) {
        Instruc[] instrucs = hostBlock.hostCode.instrucs;
        BlockContext startBlock = hostBlock,
              currBlock = hostBlock;
        // quit if we hit a top-level block; breaks cannot target across code boundaries, nor can they target a top-level block:
        while (!currBlock.isTopLevel) {
            // each enclosing try or catch block we encounter causes a new JSR to be serialized; these JSR's can only be fully resolved in pass2.
            // !! note that the target block cannot -- by definition -- also be deferring (note: an explicit label or labels on a try stmt causes the
            // creation of a wrapper PlainBlock around the try/catch/finally blocks), so we don't have to handle these two cases in tandem:
            if (currBlock.isDeferring) {
                Instruc.JSR jsr = new Instruc.JSR();
                jsr.loc = returnTok;
                // this JSR op will be dispatched somewhere within the execution state of the startBlock, meaning:
                //   1. the vm stack will have advanced startBlock.reservedStackSlots + startBlock.localDecStackableNames.size()) slots beyond the
                //      startBlock's (segmented) start offset
                //   2. if the start block creates an env, then the old lexEnv will be stored on the stack at the block's start offset
                // pass2 will iterate from this JSR's startBlock to targetBlock, aggregating the outer-most stored lexEnv (only from blocks for which
                // createsEnv=true) and stack start offset to be restored. note that pass2 resolves the lexEnv/stack restores each to an Integer offset in
                // the stack segment for the host execution context, and also resolves the JSR's jumpAddr:
                jsr.startBlock = startBlock;
                // for a JSR, the targetBlock represents:
                //   1. the try or catch block (i.e. deferring block) from which will jump to its corresponding finally block (if any)
                //   2. the outer-most block to be rest'd (lexEnv and stack) by this JSR. 
                // the JSR targetBlock also enables pass2 to derive the JSR's jumpAddr by way of: targetBlock.finallyBlock.startAddr. note that if
                // finallyBlock==null, then the jump portion of the JSR will be flagged as a no-op (i.e. the lexEnv & stack restore still needs to occur,
                // but the jump to the jumpAddr will be skipped):
                jsr.targetBlock = currBlock;
                jsr.boolVal = hasExplicitValueExpr; // JSR's guarding a return curry a value iff that return has an explicit value expr
                instrucs.add(jsr);
                // point to the next op, whether it be a subsequent guarding JSR or the BREAK itself:
                jsr.returnAddr = instrucs.size();
                
                currBlock = startBlock = currBlock.outerBlock;
            } else {
                currBlock = currBlock.outerBlock;
            }
        }
        
        if (hasExplicitValueExpr) {
            instrucs.add(Parser2.RET_EXP);
        } else {
            instrucs.add(Parser2.RET_DEF);
        }
        //Instruc ins = new Instruc.FunctionReturn(hasExplicitValueExpr);
        //ins.loc = returnTok;
        //instrucs.add(ins);
    }
    
    static BlockContext Proto; // tmp var
    
    public static BlockContext GlobalProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_GLOBAL;
        Proto.isTopLevel = true;
        Proto.createsEnv = true;
        Proto.isDeclarative = true;
//        Proto.isDeclarativeStackable = true;
        // bindings in the global env/obj are not stackable, for 2 reasons:
        //   1. an indirect eval call may be anywhere, and these indirect eval calls will use the global env as their scope
        //   2. even if the global code var-declares a variable "foo", that binding may be defined as an accessor property since the global object is
        //      referenceable via the this-binding of env-ref direct function calls. 
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 1; // 1 reserved slot to serve as the target for a RESULT instruc
        Proto.segOffset = 0; // top-level blocks always start at a 0-offset relative to their stack segment
    }
    
    public static BlockContext startGlobalBlock(CodeContext.GlobalCode globalCode) {
        BlockContext globalBlock = GlobalProto.clone();
        globalBlock.hostCode = globalCode;
        globalCode.topLevel = globalBlock;
        return globalBlock;
    }
    
    public static BlockContext FunctionProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_FUNCTION;
        Proto.isTopLevel = true;
        Proto.createsEnv = false; // starts out false, but may change to true over the course of aggregation (see aggregateUp())
        Proto.isDeclarative = true;
        Proto.isDeclarativeStackable = true;
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 0; // no reserved slots for top-level function block; a function unit cannot hold a RESULT instruc
        Proto.segOffset = 0; // top-level blocks always start at a 0-offset relative to their stack segment
    }
    
    // !! wrapperBlock will be null for dynamic functions (i.e. those created via the built-in Function constructor), and non-null for static
    // functions (i.e. FunctionExpression, FunctionDeclaration, FunctionGetter, FunctionSetter):
    public static BlockContext startFunctionBlock(BlockContext wrapperBlock, CodeContext.Function funcCode) {
        BlockContext funcBlock = FunctionProto.clone();
        // all functions locally declare "arguments"
        funcBlock.localDecNames = new Set<String>{ 'arguments' };
        // all functions locally declare each formal parameter:
        for (Lexer2.Token param: funcCode.formalParams) {
            funcBlock.localDecNames.add(param.lexeme);
        }
        // only FunctionExpressions with an explicit name (i.e. the recursive name reference) will locally declare their function name:
        if (funcCode.codeType == CodeContext.FUNC_EXPR && funcCode.name != null) {
            funcBlock.localDecNames.add(funcCode.name);
        }
        funcBlock.hostCode = funcCode;
        funcBlock.outerBlock = wrapperBlock;
        funcCode.topLevel = funcBlock;
        return funcBlock;
    }
    
    public static BlockContext EvalProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_EVAL;
        Proto.isTopLevel = true;
        Proto.createsEnv = false; // ignored; this determination is made elsewhere based on strict mode
        Proto.isDeclarative = true;
        Proto.isDeclarativeStackable = false; // because an eval block's bindings are configurable
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 1; // 1 reserved slot to serve as the target for a RESULT instruc
        Proto.segOffset = 0; // top-level blocks always start at a 0-offset relative to their stack segment
    }
    
    public static BlockContext startEvalBlock(CodeContext.Eval evalCode) {
        BlockContext evalBlock = EvalProto.clone();
        evalBlock.hostCode = evalCode;
        evalCode.topLevel = evalBlock;
        return evalBlock;
    }
    
    public static BlockContext PlainProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_PLAIN;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 0;
    }
    
    public static BlockContext startPlainBlock(BlockContext hostBlock) {
        BlockContext plainBlock = PlainProto.clone();
        plainBlock.hostCode = hostBlock.hostCode;
        plainBlock.outerBlock = hostBlock;
        return plainBlock;
    }
    
    public static BlockContext TryProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_TRY;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = true;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 1; // 1 slot to store the active frame's lex env
    }
    
    // hostBlock is the common parent block for a try stmt's tryBlock, catchBlock, and finallyBlock:
    public static BlockContext startTryBlock(BlockContext hostBlock) {
        BlockContext tryBlock = TryProto.clone();
        tryBlock.hostCode = hostBlock.hostCode;
        tryBlock.outerBlock = hostBlock;
        return tryBlock;
    }
    
    public static BlockContext CatchProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_CATCH;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // starts out false, but may change to true over the course of aggregation
        Proto.isDeclarative = true;
        Proto.isDeclarativeStackable = true;
        Proto.isDeferring = true;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 1; // 1 slot to store the active frame's lex env
    }
    
    // hostBlock is the common parent block for a try stmt's tryBlock, catchBlock, and finallyBlock:
    public static BlockContext startCatchBlock(BlockContext hostBlock) {
        BlockContext catchBlock = CatchProto.clone();
        catchBlock.hostCode = hostBlock.hostCode;
        catchBlock.outerBlock = hostBlock;
        return catchBlock;
    }
    
    public static BlockContext FinallyProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_FINALLY;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        Proto.reservedStackSlots = 3; // 3 slots: [<JSR.returnAddr>, <curry return: flag>, <curry return: value>]
    }
    
    // hostBlock is the common parent block for a try stmt's tryBlock, catchBlock, and finallyBlock:
    public static BlockContext startFinallyBlock(BlockContext hostBlock) {
        BlockContext finallyBlock = FinallyProto.clone();
        finallyBlock.hostCode = hostBlock.hostCode;
        finallyBlock.outerBlock = hostBlock;
        return finallyBlock;
    }
    
    public static BlockContext WithProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_WITH;
        Proto.isTopLevel = false;
        Proto.createsEnv = true; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = false;
        // 1 stack slot for the storing the previous lexEnv; the with-block's newly created ObjectEnv is written into active.lexEnv, so that does not
        // require an additional slot:
        Proto.reservedStackSlots = 1;
    }
    
    public static BlockContext startWithBlock(BlockContext hostBlock) {
        BlockContext withBlock = WithProto.clone();
        withBlock.hostCode = hostBlock.hostCode;
        withBlock.outerBlock = hostBlock;
        return withBlock;
    }
    
    // while, do-while, and canonical for loops:
    public static BlockContext LoopProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_LOOP;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = true;
        Proto.hasImplicitEmptyLabel = true;
        Proto.reservedStackSlots = 0;
    }
    
    public static BlockContext startLoopBlock(BlockContext hostBlock) {
        BlockContext loopBlock = LoopProto.clone();
        loopBlock.hostCode = hostBlock.hostCode;
        loopBlock.outerBlock = hostBlock;
        return loopBlock;
    }
    
    // for-in loops:
    public static BlockContext EnumProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_ENUM;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = true;
        Proto.hasImplicitEmptyLabel = true;
        // 1 slot for the for-in loop's enum-object (converted to a String[] after ENUM_START, and shift()'d per ENUM_NEXT)
        Proto.reservedStackSlots = 1;
    }
    
    public static BlockContext startEnumBlock(BlockContext hostBlock) {
        BlockContext enumBlock = EnumProto.clone();
        enumBlock.hostCode = hostBlock.hostCode;
        enumBlock.outerBlock = hostBlock;
        return enumBlock;
    }
    
    public static void mutateLoopBlockToEnum(BlockContext loopBlock) {
        loopBlock.blockType = BLOCK_ENUM;
        loopBlock.reservedStackSlots = 1;
    }
    
    public static BlockContext SwitchProto = Proto = new BlockContext();
    static {
        Proto.blockType = BLOCK_SWITCH;
        Proto.isTopLevel = false;
        Proto.createsEnv = false; // immutable
        Proto.isDeclarative = false;
        Proto.isDeclarativeStackable = false;
        Proto.isDeferring = false;
        Proto.canContinue = false;
        Proto.hasImplicitEmptyLabel = true;
        // 0 stack slots; even though we push the switch expr value onto the stack, it is essentially an expr-level intermediate that will be cleared
        // off the stack before any subsequent stmt -- more importantly, we can guarantee it will not be on the stack during execution of any
        // BlockControl-type instruc:
        Proto.reservedStackSlots = 0;
    }
    
    public static BlockContext startSwitchBlock(BlockContext hostBlock) {
        BlockContext switchBlock = SwitchProto.clone();
        switchBlock.hostCode = hostBlock.hostCode;
        switchBlock.outerBlock = hostBlock;
        return switchBlock;
    }
}