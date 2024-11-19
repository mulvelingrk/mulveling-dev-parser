/*
 * Mike Ulveling
 * 
 * This is what the ECMAScript spec calls an ExecutionContext
 */
public abstract class Frame {
    // frame types:
    public static final Integer FT_MAIN = 0;
    public static final Integer FT_MFUNCTION = 1;
    public static final Integer FT_INTERNAL_CALL = 2;
    public static final Integer FT_INTERNAL_CONSTRUCT = 3;
    public static final Integer FT_EVAL = 4;
    
    public Integer frameType;
    
    // the op that was active at the time of this frame's dispatch. if this op directly caused the dispatch (i.e. CALL or CONSTRUCT), or was "close"
    // to the dispatch cause (e.g. a property or subscript instruc that causes an accessor[get] dispatch), then the op.loc will accurately represent
    // the dispatch's source code location. in cases where the calling frame is an InternalCall or InternalConstruct, then the op.loc may not be
    // accurate, and a stack trace should display "at <native code>" for the dispatch location. dispatchOp may aslo be null, and in those cases a
    // stack trace should also display "at <native code>":
    public Instruc dispatchOp;
    
    public Boolean strict;
    
    // the index of this frame on its host vm's calls stack:
    public Integer index;
    // used to locate the segment of the stack exclusive to this frame; vm.stack[this.segStartIndex] represents its "bottom-most" stack value:
    public Integer segStartIndex;
    // this may only be set to true for Function types; a true value indicates that this Frame's function was invoked as a constructor. the vm uses
    // this flag in the case of a RETURN op to translate the return value into a resultant value for this frame:
    public Boolean isConstruct;
    
    public Environment varEnv; // VariableEnvironment
    public Environment lexEnv; // LexicalEnvironment
    public Object thisBinding;
    
    // the fixed segment of instructions for this frame (pulled from code.instrucs):
    public Instruc[] segment;
    // points to the next instruction in this segment:
    public Integer next;
    // when not null, this is the defacto next op for the subsequent vm iteration, regardless of the "next" instruction in this segment; the injected
    // op, when not null, get copied into vm.op and then reset to null upon the start of each iteration (also note that active.next is not
    // incremented in this scenario):
    public Instruc injected;
    
    private Frame() {}
    
    public Frame(Context ctx, Integer frameType, Boolean isConstruct, Object thisBinding) {
        this.frameType = frameType;
        VirtualMachine vm = ctx.vm;
        vm.calls.add(this);
        vm.active = this;
        this.dispatchOp = vm.op;
        this.index = vm.calls.size();
        this.segStartIndex = vm.stack.size();
        this.isConstruct = isConstruct;
        this.thisBinding = thisBinding;
        this.next = 0;
    }
    
    // mscript global code:
    public class Main extends Frame {
        // !! the current context (which is what we want here) may differ from the global code's parse context, thus the context must be passed in as
        // a param rather than using moduleCode.ctx:
        public Main(Context ctx, CodeContext.GlobalCode globalCode) {
            super(ctx, FT_MAIN, false, 
                    // use the global object as this frame's "this" binding:
                    ctx.globalEnv.bindings);
            this.strict = globalCode.strict;
            this.varEnv = ctx.globalEnv;
            this.lexEnv = ctx.globalEnv;
            this.segment = globalCode.instrucs;
            
            // configurableBindings=false:
            declarationBindingInstantiationForGlobal(ctx, this, globalCode, false);
        }
    }
    
    // 10.5 declaration binding instantiation for global code and indirect-call eval code (which acts like global code); eval code should pass
    // configurableBindings=true:
    public static void declarationBindingInstantiationForGlobal(Context ctx, Frame globalOrEvalFrame, CodeContext.GlobalCode code, 
            Boolean configurableBindings) {
        
        /* TODO: rewrite
        PlainObject globalObj = ctx.globalObj;
        PropertyDescrip newPropPrivs = configurableBindings ? PropertyDescrip.DataAllPrivs : PropertyDescrip.DataEnumWritePrivs;
        for (CodeContext.Function funcCode: code.functionDecs) {
            String name = funcCode.name;
            MFunction funcObj = new MFunction(ctx, globalOrEvalFrame.varEnv, funcCode);
            PropertyDescrip existingProp = globalObj.getProperty(ctx, name);
            // if this property doesn't already exist in the global env:
            if (existingProp == null) {
                // note that we bypass ObjectEnv.createMutableBinding/ObjectEnv.setMutableBinding and PlainObject.defineOwnProperty, inlining the
                // equivalent logic since we know the global obj is extensible and that this property name is not yet defined; thus, we can write
                // directly into the props map:
                PropertyDescrip newProp = newPropPrivs.clone(); // enumerable & writable but not configurable
                newProp.value = funcObj;
                globalObj.props.put(name, newProp);
            } else {
                if (existingProp.configurable) {
                    // note that the replacement property (i.e. this function declaration) is not configurable:
                    PropertyDescrip newProp = newPropPrivs.clone();
                    newProp.hasValue = true;
                    globalObj.defineOwnProperty(ctx, name, newProp, true);
                } else if (existingProp.isAccessor || !existingProp.enumerable || !existingProp.writable) {
                    RuntimeException typeErr = new RuntimeException(ctx, new TypeError(ctx, 'Global function declaration \'' + name 
                            + '\' clashes with an existing ' 
                            + (existingProp.isAccessor 
                                    ? 'accessor' 
                                    : '[' + Utils.valueTypeToString(ctx, existingProp.value) + ']')
                            + ' property on the global object'));
                    // !! note how we override the loc property:
                    typeErr.loc = funcCode.loc;
                    throw typeErr;
                }
                // here we inline the logic of ObjectEnv.setMutableBinding:
                globalObj.put(ctx, name, funcObj, code.strict);
            }
        }
        */
//        for (Lexer2.Token var: code.vars) {
//            String name = var.lexeme;
//            if (!globalObj.hasProperty(ctx, name))
//                // again we bypass ObjectEnv.createMutableBinding/ObjectEnv.setMutableBinding and PlainObject.defineOwnProperty, inlining the
//                // equivalent logic; the new property is enumerable & writable but not configurable, and has an initial value of undefined:
//                globalObj.props.put(name, newPropPrivs.clone());
//        }
    }
    
    // mscript function code; here [[Call]] and [[Construct]] are treated exactly the same as they pertain to code execution; the 2 operations are
    // differentiated before (calculating the thisBinding) and after (processing return value) code execution by the virtual machine:
    public class MFunc extends Frame {
        public MFunction mfunc;
        // when the 1st Tail Call Elimination occurs on this frame, its tceCounter will be initialised to 1; each subsequent occurrence will
        // increment it by 1:
        public Integer tceCounter;
        
        // this constructor performs Declaration Binding Instantiation and is the signature that should be used in most cases:
        public MFunc(Context ctx, MFunction mfunc, Boolean isConstruct, Object thisBinding, Object[] argv) {
            super(ctx, FT_MFUNCTION, isConstruct, thisBinding);
            this.mfunc = mfunc;
            this.strict = mfunc.code.strict;
            this.segment = mfunc.code.instrucs;
            declarationBindingInstantiationForMFunc(ctx, this, argv);
        }
        
        // this constructor doesn't perform Declaration Binding Instantiation; it's used to create a reusable delegate frame by
        // VirtualMachine.newDelegator:
        public MFunc(Context ctx, MFunction mfunc, Boolean isConstruct, Object thisBinding) {
            super(ctx, FT_MFUNCTION, isConstruct, thisBinding);
            this.mfunc = mfunc;
            this.strict = mfunc.code.strict;
            this.segment = mfunc.code.instrucs;
        }
    }
    
    // 10.5 declaration binding instantiation for function code:
    public static void declarationBindingInstantiationForMFunc(Context ctx, Frame.MFunc mframe, Object[] argv) {
        /* TODO: rewrite
        CodeContext.Function code = mframe.mfunc.code;
        if (code.decBindingVals == null)
            code.compileDeclarationBindings();
        
        DeclarativeEnv env = new DeclarativeEnv();
        mframe.varEnv = env;
        mframe.lexEnv = env;
        env.parent = mframe.mfunc.scope;
        env.bindingVals = code.decBindingVals.clone();
        if (code.decImmutables != null)
            env.immutables = code.decImmutables.clone();
        // note that function declarations compilation doesn't find deletables, so we don't have to check for those...
            
        Integer numMappedArgs = Math.min(code.decBindingArgNames.size(), argv.size());
        for (Integer i=0; i < numMappedArgs; i++)
            env.bindingVals.put(code.decBindingArgNames[i], argv[i]);
        
        for (CodeContext.Function funcCode: code.functionDecs)
            env.bindingVals.put(funcCode.name, new MFunction(ctx, env, funcCode));
        
        if (code.decBindingCreateArguments)
            env.bindingVals.put('arguments', new Arguments(ctx, mframe.mfunc, argv, env));
        */
    }
    
    // utility method for seting up a delegate MFunc frame for a subsequent call to VirtualMachine.execDelegate:
    public static void prepareDelegate(VirtualMachine vm, MFunc delegate, Object thisArg, Object[] argv) {
        delegate.next = 0;
        delegate.injected = null;
        delegate.thisBinding = thisArg;
        declarationBindingInstantiationForMFunc(vm.ctx, delegate, argv);
    }

    // utility method for implementing the Tail Call Elimination (TCE) optimization when the caller has the exact same MFunction instance as callee
    public static void tailCallHijackSame(VirtualMachine vm, MFunc caller, MFunction callee, Object thisArg, Object[] argv) {
        // reset only the attributes that can change between a tail call of the same MFunction instance; this excludes: mfunc, strict, segment
        caller.dispatchOp = vm.op;
        caller.next = 0;
        caller.injected = null;
        caller.thisBinding = thisArg;
        
        // truncate the vm's stack to the caller (i.e. the frame we're hijacking) frame's starting state:
        for (Integer i=vm.stack.size() - 1; i >= caller.segStartIndex; i--)
            vm.stack.remove(i);
        
        if (caller.tceCounter == null)
            caller.tceCounter = 1;
        else
            caller.tceCounter++;
        
        declarationBindingInstantiationForMFunc(vm.ctx, caller, argv);
    }
    
    // represents the [[Call]] invocation of a Function. in a typical dispatchCall or dispatchConstruct, this frame is used only for stack trace
    // purposes and not for instruction dispatch nor return value currying. however, in the case of a delegate dispatch (see VirtualMachine.
    // execDelegate), the frame is used for return currying. thus, we setup a fixed segment with a single END instruction so that the frame may curry
    // its callee's return value to the parent vm, and thus to the delegate's consumer. a use-case of this seeming esoteric scenario would be an
    // MFunction wrapped via Function.prototype.bind and then passed in as the compare function for an Array.prototype.sort call. In that scenario,
    // the delegator vm's root InternalCall frame represents the bound comparison function, which will curry the result from the wrapped MFunction
    // back to the sort method's logic.
    public class InternalCall extends Frame {
        // thisCall must not be an instance of MFunction since we don't invoke the internal [[Call]] or [[Construct]] methods of an MFunction:
        public Callable thisCall;
        
        public InternalCall() {
            super();
            this.frameType = FT_INTERNAL_CALL;
            this.isConstruct = false;
            this.strict = false;
            // this segment should be a [RESULT, END] in order to curry the return value for a delegated call into the stack bottom:
            //this.segment = new Instruc[]{ new Instruc.Result(), new Instruc.ExecContextEnd() };
            this.segment = new Instruc[]{ Parser2.RET_NONE, Parser2.RET_NONE };
            this.next = 0;
            // !! a delegator vm instance, when constructed, will initialize a stack of size 1 with the initial value "undefined" -- this same stack
            // slot will be repeatedly reused to curry the delegate invocation's return value into the delegator vm's returnVal, which can in turn be
            // synchronously returned to the delegator's client (e.g. Array.prototype.sort)...
        }
    }
    
    // represents the [[Construct]] invocation of a Function; used for stack trace purposes and not for instruction dispatch into the vm:
    public class InternalConstruct extends Frame {
        // thisCall must not be an instance of MFunction since we don't invoke the internal [[Call]] or [[Construct]] methods of an MFunction:
        public Constructible thisConstruct;
        
        public InternalConstruct() {
            super();
            this.frameType = FT_INTERNAL_CONSTRUCT;
            this.isConstruct = true;
            this.strict = false;
        }
    }
    
    public static final InternalCall InternalCallProto = new InternalCall();
    public static final InternalConstruct InternalConstructProto = new InternalConstruct();
    
    public class Eval extends Frame {
        
        // use this constructor for eval code that should act as if it was a global execution context -- i.e. an indirect eval or an eval without any
        // calling execution context:
        public Eval(Context ctx, CodeContext.Eval evalCode) {
            super(ctx, FT_EVAL, false, ctx.globalObj);
            this.varEnv = ctx.globalEnv;
            this.lexEnv = ctx.globalEnv;
            this.strict = evalCode.strict;
            // configurableBindings=true:
            /*
            declarationBindingInstantiationForGlobal(ctx, this, evalCode, true);
            */
            
            System.assert(false, 'TODO');
        }
        
        // use this constructor for eval code that should inherit its environments & thisBinding from a calling execution context -- i.e. a direct
        // call to eval from an active execution context:
        public Eval(Context ctx, CodeContext.Eval evalCode, Environment varEnv, Environment lexEnv, Object thisBinding) {
            super(ctx, FT_EVAL, false, thisBinding);
            this.varEnv = varEnv;
            this.lexEnv = lexEnv;
            this.strict = evalCode.strict;
            
            System.assert(false, 'TODO');
            
            /* TODO: rewrite
            Environment env = varEnv;
            // 10.5 declaration binding instantiation for eval code:
            for (CodeContext.Function funcCode: evalCode.functionDecs) {
                String name = funcCode.name;
                MFunction funcObj = new MFunction(ctx, env, funcCode);
                Boolean funcAlreadyDeclared = env.hasBinding(ctx, name);
                // if this property doesn't already exist in the global env:
                if (!funcAlreadyDeclared)
                    env.createMutableBinding(ctx, name, true);
                
                env.setMutableBinding(ctx, name, funcObj, evalCode.strict);
            }
//            for (Lexer2.Token var: evalCode.vars) {
//                String name = var.lexeme;
//                if (!env.hasBinding(ctx, name)) {
//                    env.createMutableBinding(ctx, name, true);
//                    env.setMutableBinding(ctx, name, null, this.strict);
//                }
//            }
             */
        }
    }
}