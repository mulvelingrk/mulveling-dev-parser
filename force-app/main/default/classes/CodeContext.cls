/*
 * Mike Ulveling
 */
public abstract class CodeContext {
    public static final Integer GLOBAL_CODE   = 0;
    public static final Integer EVAL_CODE     = 1;
    
    public static final Integer FUNC_CODE_MIN = 2;
    
    public static final Integer FUNC_DEC      = 2;
    public static final Integer FUNC_EXPR     = 3;
    public static final Integer FUNC_GETTER   = 4;
    public static final Integer FUNC_SETTER   = 5;
    public static final Integer FUNC_DYNAMIC  = 6;
    
    public Integer codeType;
    public Boolean strict;
    public Lexer2.Token loc; // null for global code
    
    // the top-level block for this code unit:
    public BlockContext topLevel;
    
// TODO: vars, funtionDecs, refsArguments, and inheritsEvalDirectCall deprecated on CodeContext in favor of topLevel BlockContext
//    // collected for the purpose of Declaration Binding Instantiation, a.k.a. "hoisting":
//    public Lexer2.Token[] vars;
//    public CodeContext.Function[] functionDecs;
//    public Boolean refsArguments;
//    public Boolean inheritsEvalDirectCall;
    
    
    // sub-instructs for performing Declaration Binding Instantiation:
    public SubInstruc[] subInstrucs;
    // the full serialization of vm instructions for this code segment:
    public Instruc[] instrucs;
    
    public virtual void compileDecBindSubInstrucs() {
        System.assert(false, 'compileDecBindSubInstrucs not implemented');
    }
    
    public class GlobalCode extends CodeContext {
        public GlobalCode(Boolean strict) {
            this.codeType = GLOBAL_CODE;
            this.strict = strict;
//            this.vars = new Lexer2.Token[]{};
//            this.functionDecs = new CodeContext.Function[]{};
//            this.refsArguments = false;
//            this.inheritsEvalDirectCall = false;
            this.instrucs = new Instruc[]{};
        }
        
        // this method compiles the sub-instructions necessary for performing the appropriate Declaration Binding Instantiation of this code unit.
        // this method should be called immediately following pass2 compiler processing on this code unit:
        public override void compileDecBindSubInstrucs() {
            // TODO:
            /*
            SubInstruc[] subInstrucs;
            SubInstruc createEnv;
            // track the binding names we've previously processed, at any given point in time:
            Set<String> boundNames;
            // maps a binding name to the segmented stack offset it's been bound to:
            Map<String, Integer> funcAndParamStackBindings;

            subInstrucs = new SubInstruc[]{};
            boundNames = new Set<String>();
            
            // !! it's implied that we must always create an env object as the 1st action for a global code unit, so we need not serialize a
            // sub-instruc for this
            
            Integer stackAllocLength = topLevel.reservedStackSlots; // reserved slots should always be 0 for a global code unit's topLevel
            if (topLevel.stackRefsByName != null) {
                stackAllocLength += topLevel.stackRefsByName.keySet().size();
            }
            // tracks the next available stack slot (as a segmented stack offset), incrementing as necessary:
            Integer nextAvailSegOffset;
            if (stackAllocLength > 0) {
                SubInstruc stackAlloc = SubInstruc.STACK_ALLOC.clone();
                stackAlloc.length = stackAllocLength;
                subInstrucs.add(stackAlloc);
                // we assign variable stack slots in reverse order starting from the end (rhs) of the allocation block:
                nextAvailSegOffset = stackAllocLength - 1;
                funcAndParamStackBindings = new Map<String, Integer>();
            }
            
            // bind function declarations (1st priority from right-to-left)
            SubInstruc bindInstruc;
            for (Integer i=topLevel.topLevelFuncDecs.size() - 1; i >= 0; i--) {
                String bindName = topLevel.topLevelFuncDecs[i].name;  
                
                // assert that we haven't previously processed this same binding name:
                if (boundNames.add(bindName)) {
                    // new binding; determine whether its destination is the stack, lexEnv, or unused:
                    Integer bindDest;
                    Integer bindSegOffset;
                    if (topLevel.stackRefsByName != null && topLevel.stackRefsByName.containsKey(bindName)) {
                        bindDest = SubInstruc.DEST_STACK;
                        bindSegOffset = nextAvailSegOffset--;
                        funcAndParamStackBindings.put(bindName, bindSegOffset);
                    // we may encounter bindings that are unused, so only bind them into the env if we created a lexEnv:
                    } else if (createEnv != null) {
                        bindDest = SubInstruc.DEST_ENV;
                        createEnv.uninitBindings.put(bindName, null);
                    // else this binding is unused:
                    } else {
                        continue;
                    }
                    
                    // if we have a prev bind instruc that is compatible with this bind, then expand it by 1 slot to the left:
                    if (bindInstruc != null && bindDest == bindInstruc.destination 
                            // make sure this is a slot adjacent to the prior one; i.e. a skipped slot must breakup this run:
                            && bindInstruc.rhsValueIndex + bindInstruc.lhsOffset == i + 1) {
                        bindInstruc.lhsOffset--;
                    // else create a new bind instruc:
                    } else {
                        bindInstruc = SubInstruc.BIND_FUNCS.clone();
                        bindInstruc.destination = bindDest;
                        bindInstruc.rhsValueIndex = i;
                        bindInstruc.rhsSegOffset = bindSegOffset;
                        bindInstruc.lhsOffset = 0;
                        subInstrucs.add(bindInstruc);
                    }
                }
                // else we don't need to bind this func dec, because its name has been bound to another func of higher precedence...
            }
            
            // resolve static references that have been bound to stack-convertible function decs and formal params: set segOffset and mutate
            // the op id from GID_ENV_REF to GID_ST_REF (note that these bindings are always mutable):
            for (String bindName: funcAndParamStackBindings.keySet()) {
                Integer segOffset = funcAndParamStackBindings.get(bindName);
                for (Instruc.PushEnvironmentRef ref: topLevel.stackRefsByName.get(bindName)) {
                    // mutate what was an env ref into a stack ref:
                    ref.gid = Instruc.GID_ST_REF;
                    // segOffset is an offset added to the active frame's segmented stack start index:
                    ref.segOffset = segOffset;
                }
            }
            
            // var dec bindings are always mutable and 4th priority. note that var dec bindings never generate sub-instrucs; they merely mutate
            // any associated environment refs (if converting to a stack ref) and add an entry to the uninitBindings map:
            if (topLevel.topLevelVarDecs != null) {
                for (Lexer2.Token var: topLevel.topLevelVarDecs) {
                    // assert that we haven't previously processed this same binding name:
                    if (boundNames.add(var.lexeme)) {
                        Instruc.PushEnvironmentRef[] bindingRefs;
                        if (topLevel.stackRefsByName != null && (bindingRefs = topLevel.stackRefsByName.get(var.lexeme)) != null) {
                            Integer varSegOffset = nextAvailSegOffset--;
                            for (Instruc.PushEnvironmentRef ref: bindingRefs) {
                                // mutate what was an env ref into a stack ref:
                                ref.gid = Instruc.GID_ST_REF;
                                ref.segOffset = varSegOffset;
                            }
                        } else if (createEnv != null) {
                            createEnv.uninitBindings.put(var.lexeme, null);
                        }
                    }
                }
            }
            */
        }
    }
    
    public class Eval extends CodeContext {
        public Eval(Boolean strict) {
            this.codeType = EVAL_CODE;
            this.strict = strict;
//            this.vars = new Lexer2.Token[]{};
//            this.functionDecs = new CodeContext.Function[]{};
//            this.refsArguments = false;
//            this.inheritsEvalDirectCall = false;
            this.instrucs = new Instruc[]{};
        }
    }
    
    public class Function extends CodeContext {
        // name is optional only for function-expr types. the name is usually -- but not necessarily -- the same as nameTok.lexeme; e.g. a getter
        // property that uses the hex-number token "0xff" becomes the name "255":
        public String name;
        public Lexer2.Token nameTok; 
        
        // when an explicit name is not provided, the lhsLexicalContext (read: left-hand side lexical assignee) -- when not null -- can be used to
        // construct a name for use in high-quality stack traces (e.g. "Object.foo.bar.baz" instead of "<anonymous>"):
        public String[] lhsLexicalContext;
        
        public Lexer2.Token[] formalParams;
        // the verbatim source code for this function, sans the "function" keyword -- used for the builtin toString:
        public String srcCode;
        
//        // compiled declarations information:
//        public Map<String, Object> decBindingVals;
//        // declarations compilation can only catch the "arguments" immutable, and won't catch any deletables (so we don't need decDeletables):
//        public Set<String> decImmutables;
//        public String[] decBindingArgNames;
//        public Boolean decBindingCreateArguments;
        
        public Function(Boolean strict, Integer functionType, Lexer2.Token loc) {
            this.codeType = functionType;
            this.strict = strict;
//            this.vars = new Lexer2.Token[]{};
//            this.functionDecs = new CodeContext.Function[]{};
//            this.refsArguments = false;
//            this.inheritsEvalDirectCall = false;
            this.instrucs = new Instruc[]{};
            this.loc = loc;
        }
            
        // returns the name that should represent this function in a stack trace; anonymous functions will attempt to compose a name from their
        // lexical context (if any). "asPropName" may optionally be provided by the runtime system (i.e. from the function ref's Reference.name
        // value):
        public String getTraceName(String asPropName) {
            if (name != null)
                return name;
            else if (lhsLexicalContext != null) {
                String iname = '';
                for (Integer i=0; i < lhsLexicalContext.size(); i++) {
                    String prop = lhsLexicalContext[i];
                    if (i == 0 && lhsLexicalContext.size() > 1 && prop != 'Object' && prop != '[[Call]]' && prop != '[[Construct]]')
                        iname = 'Object';
                        
                    if (prop == null)
                        iname += (iname.length() > 0 ? '.' : '') + '<dynamic>';
                    else if (prop != 'prototype' || i == 0)
                        iname += (iname.length() > 0 ? '.' : '') + prop;
                }
                
                if (asPropName != null && lhsLexicalContext[lhsLexicalContext.size() - 1] == null)
                    return iname + ' [as ' + asPropName + ']';
                else
                    return iname;
            } else 
                return '<anonymous>' + (asPropName != null ? ' [as ' + asPropName + ']' : '');
        }
        
        // this method compiles the sub-instructions necessary for performing the appropriate Declaration Binding Instantiation of this code unit.
        // this method should be called immediately following pass2 compiler processing on this code unit:
        public override void compileDecBindSubInstrucs() {
            // !! note that a direct-call eval that's local to this code unit (i.e. you may exclude eval calls that are inherited from a nested code
            // unit) may contain dynamic code that references this function's Arguments object, so we must also create the Arguments object in that
            // case:
            Boolean usesArgumentsObj = topLevel.topLevelArgumentsRef || topLevel.topLevelEvalDirectCall;
            // the compiled sub-instructions that, when executed at the beginning of a CALL or CONSTRUCT dispatch of this function, will perform the
            // appropriate Declaration Binding Instantiation for that invocation:
            //SubInstruc[] subInstrucs;
            SubInstruc createEnv;
            // track the binding names we've previously processed, at any given point in time:
            Set<String> boundNames;
            // maps a binding name to the segmented stack offset it's been bound to:
            Map<String, Integer> funcAndParamStackBindings;

            do {
                subInstrucs = new SubInstruc[]{};
                boundNames = new Set<String>();
                
                // mapped arguments are tricky to handle, but they're only applicable under the following circumstances.
                // !! if we find a function declaration name or formal param name of "arguments" (this is not allowed in strict mode), then we'll
                // bypass creation of the Arguments obj. if we'd already started processing with the assumption that mappedArgs==true, then we'll
                // have to set usesArgumentsObj = usesMappedArgs = false and restart processing:
                Boolean usesMappedArgs = usesArgumentsObj && !strict && formalParams.size() > 0;
                
                // the presence of any mapped args necessitates the creation of a new env:
                if (topLevel.createsEnv || usesMappedArgs) {
                    createEnv = SubInstruc.CREATE_ENV_OBJ.clone();
                    // maps a binding name to null (undefined) for all lexEnv bindings; serves as a prototype map that can be cloned as an early step
                    // of Declaration Binding Instantiation for this function:
                    createEnv.uninitBindings = new Map<String, Object>();
                    subInstrucs.add(createEnv);
                // if we don't create a new env for this function, then simply inherit the parent scope to use as the varEnv and the initial lexEnv:
                } else {
                    subInstrucs.add(SubInstruc.INHERIT_ENV.clone());
                }
                
                Integer stackAllocLength = topLevel.reservedStackSlots; // actually, reserved slots should always be 0 for a function's topLevel
                if (topLevel.stackRefsByName != null) {
                    // note: we must always allocate for the full # of convertible refs, whether or not we actually end up using them (e.g. a stack
                    // binding will go unused in the case of a formal param that is also a mapped arg):
                    stackAllocLength += topLevel.stackRefsByName.keySet().size();
                }
                // tracks the next available stack slot (as a segmented stack offset), incrementing as necessary:
                Integer nextAvailSegOffset;
                if (stackAllocLength > 0) {
                    SubInstruc stackAlloc = SubInstruc.STACK_ALLOC.clone();
                    stackAlloc.length = stackAllocLength;
                    subInstrucs.add(stackAlloc);
                    // we assign variable stack slots in reverse order starting from the end (rhs) of the allocation block:
                    nextAvailSegOffset = stackAllocLength - 1;
                    funcAndParamStackBindings = new Map<String, Integer>();
                }
                
                // bind function declarations (1st priority from right-to-left)
                SubInstruc bindInstruc;
                for (Integer i=topLevel.topLevelFuncDecs.size() - 1; i >= 0; i--) {
                    String bindName = topLevel.topLevelFuncDecs[i].name;  
                    
                    // assert that we haven't previously processed this same binding name:
                    if (boundNames.add(bindName)) {
                        // new binding; determine whether its destination is the stack, lexEnv, or unused:
                        Integer bindDest;
                        Integer bindSegOffset;
                        if (topLevel.stackRefsByName != null && topLevel.stackRefsByName.containsKey(bindName)) {
                            bindDest = SubInstruc.DEST_STACK;
                            bindSegOffset = nextAvailSegOffset--;
                            funcAndParamStackBindings.put(bindName, bindSegOffset);
                        // we may encounter bindings that are unused, so only bind them into the env if we created a lexEnv:
                        } else if (createEnv != null) {
                            bindDest = SubInstruc.DEST_ENV;
                            createEnv.uninitBindings.put(bindName, null);
                        // else this binding is unused:
                        } else {
                            continue;
                        }
                        
                        // if we have a prev bind instruc that is compatible with this bind, then expand it by 1 slot to the left:
                        if (bindInstruc != null && bindDest == bindInstruc.destination 
                                // make sure this is a slot adjacent to the prior one; i.e. a skipped slot must breakup this run:
                                && bindInstruc.rhsValueIndex + bindInstruc.lhsOffset == i + 1) {
                            bindInstruc.lhsOffset--;
                        // else create a new bind instruc:
                        } else {
                            bindInstruc = SubInstruc.BIND_FUNCS.clone();
                            bindInstruc.destination = bindDest;
                            bindInstruc.rhsValueIndex = i;
                            bindInstruc.rhsSegOffset = bindSegOffset;
                            bindInstruc.lhsOffset = 0;
                            subInstrucs.add(bindInstruc);
                        }
                    }
                    // else we don't need to bind this func dec, because its name has been bound to another func of higher precedence...
                }
                
                // bind formal parameters (2nd priority to function decs, then from right-to-left within the params list):
                bindInstruc = null;
                for (Integer i=formalParams.size() - 1; i >= 0; i--) {
                    String bindName = formalParams[i].lexeme;
                    
                    // assert that we haven't previously processed this same binding name:
                    if (boundNames.add(bindName)) {
                        // new binding; determine whether its destination is the stack, lexEnv, or unused:
                        Integer bindDest;
                        Integer bindSegOffset;
                        // !! it's very important to disallow the stack allocation of formal params when mapped args are in use:
                        if (!usesMappedArgs && topLevel.stackRefsByName != null && topLevel.stackRefsByName.containsKey(bindName)) {
                            bindDest = SubInstruc.DEST_STACK;
                            bindSegOffset = nextAvailSegOffset--;
                            funcAndParamStackBindings.put(bindName, bindSegOffset);
                        // we may encounter bindings that are unused, so only bind them into the env if we created a lexEnv:
                        } else if (createEnv != null) {
                            bindDest = SubInstruc.DEST_ENV;
                            createEnv.uninitBindings.put(bindName, null);
                        // else this binding is unused:
                        } else {
                            continue;
                        }
                        
                        // if we have a prev bind instruc that is compatible with the current bind instruc's parameters, then simply expand the prior
                        // instruc by 1 slot to the left:
                        if (bindInstruc != null && bindDest == bindInstruc.destination 
                                // make sure we're on a slot adjacent to the prior one; i.e. a skipped slot must breakup this streak:
                                && bindInstruc.rhsValueIndex + bindInstruc.lhsOffset == i + 1) {
                            bindInstruc.lhsOffset--;
                        // else create & serialize a new bind instruc:
                        } else {
                            bindInstruc = SubInstruc.BIND_PARAMS.clone();
                            bindInstruc.destination = bindDest;
                            bindInstruc.rhsValueIndex = i;
                            bindInstruc.rhsSegOffset = bindSegOffset;
                            bindInstruc.lhsOffset = 0;
                            subInstrucs.add(bindInstruc);
                        }
                    }
                    // else we don't need to bind this param, because its name has been bound to another func and/or param of higher precedence...
                
                }
                
                // TODO: ENVREF instrucs now hold a reference to their associated PUT; for each ENVREF we are mutating to STKREF, that is an 
                // immutable binding (only arguments and the recursive function ref can be immutable), mutate the associated PUT to IMMUT.
                // The ENVREF definition has been modified to eliminate the lhsAssignee boolVal flag.
                
                if (usesArgumentsObj) {
                    // assert that we haven't previously processed this same binding name:
                    if (boundNames.add('arguments')) {
                        // bind the Arguments obj (3rd priority to function decs and formal params)
                        bindInstruc = SubInstruc.BIND_ARGUMENTS_OBJ.clone();
                        subInstrucs.add(bindInstruc);
                        Instruc.EnvRef[] bindingRefs;
                        if (topLevel.stackRefsByName != null && (bindingRefs = topLevel.stackRefsByName.get('arguments')) != null) {
                            bindInstruc.destination = SubInstruc.DEST_STACK;
                            Integer argsSegOffset = nextAvailSegOffset--;
                            for (Instruc.EnvRef ref: bindingRefs) {
                                // mutate to a stack ref opCode:
                                ref.opCode = Instruc.OP_STKREF;
                                ref.intVal = argsSegOffset;
                                // !! mutate the associated PUT to an IMMUT; note that every ENVREF instruc is guaranteed to be associated with its
                                // own PUT op (1:1), because ENVREFs not associated with a PUT will have been converted to ENVVAL. note that IMMUT
                                // will throw a TypeError in strict mode and will act as a no-op in sloppy mode:
                                ref.putOp.opCode = Instruc.OP_IMMUT;
                                ref.putOp.strVal = ref.strVal;
                                /*
                                // the arguments reference is immutable, so we must flag its assignability appropriately:
                                if (this.strict) {
                                    // immutable assignee in strict mode; throw TypeError at runtime if an assignment is attempted:
                                    ref.boolVal = false;
                                } else {
                                    // immutable assignee in sloppy mode; any attempt to assign into this ref should become a no-op
                                    ref.boolVal = null;
                                }
                                */
                            }
                            
                        } else {
                            // here we're guaranteed that createEnv is not null, because the circumstances that necessitate Arguments object creation
                            // (and its binding to env) also imply the creation of an env:
                            // 1. any inherited eval direct-call sets topLovel.createsEnv=true; Arguments obj is needed when there is an eval direct-
                            //    call local to this code unit, which is a special case of an inherited eval direct-call
                            // OR 
                            // 2. any code-unit-local static "arguments" ref that was not converted to a stack ref would also set topLevel.createsEnv
                            //    = true; Arguments obj is needed when there is any static reference to "arguments" that is local to this code unit,
                            //    and when "arguments" binds to the Arguments object via env ref
                            bindInstruc.destination = SubInstruc.DEST_ENV;
                            createEnv.uninitBindings.put('arguments', null);
                            if (strict) {
                                createEnv.immutables = new Set<String>{ 'arguments' };
                            }
                        }
                    // else, "arguments" was used by a function dec and/or formal param, which has higher priority than the Arguments object:
                    } else {
                        // crap - we were running under the assumption of needing the Arguments object, but during this processing iteration we
                        // encountered a functionDec and/or formalParam named 'arguments' that overrides the standard Arguments binding. so, we reset
                        // our variables and restart the processing again, but now with the knowledge that we don't need to create the Arguments
                        // object (e.g. no more mapped args, and possibly some formal params may become stack bindings again): 
                        // TODO: can we enhance parser to eliminate the need for this 2-pass approach (i.e. it can detect when a formal param or
                        // function dec is named "arguments" in non-strict mode)?
                        usesArgumentsObj = false;
                        createEnv = null;
                        funcAndParamStackBindings = null;
                        continue;
                    }
                }
                
                // resolve static references that have been bound to stack-convertible function decs and formal params: set segOffset and mutate
                // the op id from ENVREF to STKREF (note that these bindings are always mutable):
                for (String bindName: funcAndParamStackBindings.keySet()) {
                    Integer segOffset = funcAndParamStackBindings.get(bindName);
                    for (Instruc.EnvRef ref: topLevel.stackRefsByName.get(bindName)) {
                        // mutate what was an env ref into a stack ref:
                        ref.opCode = Instruc.OP_STKREF;
                        // segOffset is an offset added to the active frame's segmented stack start index:
                        ref.intVal = segOffset;
                        // assignment is allowed (not necessary to set here since boolVal is already true from pass1 if this is a lhs assignee ref):
                        //ref.boolVal = true;
                    }
                }
                
                // var dec bindings are always mutable and 4th priority. note that var dec bindings never generate sub-instrucs; they merely mutate
                // any associated environment refs (if converting to a stack ref) or adds an entry to the uninitBindings map:
                if (topLevel.topLevelVarDecs != null) {
                    for (Lexer2.Token var: topLevel.topLevelVarDecs) {
                        // assert that we haven't previously processed this same binding name:
                        if (boundNames.add(var.lexeme)) {
                            Instruc.EnvRef[] bindingRefs;
                            if (topLevel.stackRefsByName != null && (bindingRefs = topLevel.stackRefsByName.get(var.lexeme)) != null) {
                                Integer varSegOffset = nextAvailSegOffset--;
                                for (Instruc.EnvRef ref: bindingRefs) {
                                    // mutate what was an env ref into a stack ref:
                                    ref.opCode = Instruc.OP_STKREF;
                                    ref.intVal = varSegOffset;
                                    // assignment is allowed (not necessary to set here since boolVal is already true from pass1 if this is a lhs
                                    // assignee ref):
                                    //ref.boolVal = true;
                                }
                            } else if (createEnv != null) {
                                createEnv.uninitBindings.put(var.lexeme, null);
                            }
                        }
                    }
                }
                
                // a FunctionExpression's recursive reference binding is always immutable and 5th (lowest) priority:
                if (codeType == CodeContext.FUNC_EXPR && this.name != null) {
                    // assert that we haven't previously processed this same binding name:
                    if (boundNames.add(this.name)) {
                        bindInstruc = SubInstruc.BIND_RECURSIVE_REF.clone();
                        subInstrucs.add(bindInstruc);
                        Instruc.EnvRef[] bindingRefs;
                        if (topLevel.stackRefsByName != null && (bindingRefs = topLevel.stackRefsByName.get(this.name)) != null) {
                            bindInstruc.destination = SubInstruc.DEST_STACK;
                            Integer segOffset = nextAvailSegOffset--;
                            for (Instruc.EnvRef ref: bindingRefs) {
                                // mutate to a stack ref opCode:
                                ref.opCode = Instruc.OP_STKREF;
                                ref.intVal = segOffset;
                                // !! mutate the associated PUT to an IMMUT; note that every ENVREF instruc is guaranteed to be associated with its
                                // own PUT op (1:1), because ENVREFs not associated with a PUT will have been converted to ENVVAL. note that IMMUT
                                // will throw a TypeError in strict mode and will act as a no-op in sloppy mode:
                                ref.putOp.opCode = Instruc.OP_IMMUT;
                                ref.putOp.strVal = ref.strVal;
                                /*
                                // the recursive function reference is immutable, so we must flag its assignability appropriately:
                                if (this.strict) {
                                    // immutable assignee in strict mode; throw TypeError at runtime if an assignment is attempted:
                                    ref.boolVal = false;
                                } else {
                                    // immutable assignee in sloppy mode; any attempt to assign into this ref should become a no-op
                                    ref.boolVal = null;
                                }
                                */
                            }
                        } else if (createEnv != null) {
                            bindInstruc.destination = SubInstruc.DEST_ENV;
                            createEnv.uninitBindings.put(this.name, null);
                            // the "immutables" set of an Environment object is checked by PutValue in order to throw a TypeError when a PUT is
                            // attempted on an immutable binding:
                            if (createEnv.immutables == null) {
                                createEnv.immutables = new Set<String>{ this.name };
                            } else {
                                createEnv.immutables.add(this.name);
                            }
                        }
                    }
                }
                
                break;
            } while (true);
        }
    }
}