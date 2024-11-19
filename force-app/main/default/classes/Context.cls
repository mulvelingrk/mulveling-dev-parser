/*
 * Mike Ulveling
 * 
 * Yup, this is the all-important "context" object that needs to be passed into everything related to runtime operations. I decided this was better
 * than relying on awful statics. Contains the reference Prototype and Constructor instances for each of the ECMAScript built-in types.
 */
global class Context {
    public Context parent;
    // the host vm:
    public VirtualMachine vm;
    global ObjectEnv globalEnv;
    global PlainObject globalObj; // the exposed (for convenience) bindings of globalEnv
    
    global PlainObject ObjectProto;
    global Function ObjectConstruct;
    global Function ObjectToString;
    
    global Function FunctionProto;
    global Function FunctionConstruct;
    
    global Error ErrorProto;
    global Function ErrorConstruct;
    
    global SyntaxError SyntaxErrorProto;
    global Function SyntaxErrorConstruct;
    
    global TypeError TypeErrorProto;
    global Function TypeErrorConstruct;
    
    global ReferenceError ReferenceErrorProto;
    global Function ReferenceErrorConstruct;
    
    global RangeError RangeErrorProto;
    global Function RangeErrorConstruct;
    
    global ApexError ApexErrorProto;
    global Function ApexErrorConstruct;
    
    global Function ArgsThrowTypeError;
    
    global StringObject StringProto;
    global Function StringConstruct;
    
    global BooleanObject BooleanProto;
    global Function BooleanConstruct;
    
    global NumberObject NumberProto;
    global Function NumberConstruct;
    
    global ArrayObject ArrayProto;
    global Function ArrayConstruct;
    
    // TODO:
//    global RangeError RangeErrorProto;
//    global Function RangeErrorConstruct;
    
    // TODO: RegExp, ArrayObject, DateObject, NumberObject, StringObject, BooleanObject
    
    global Context() {
        ObjectProto = new PlainObject(this);
        // !! the function prototype must be instantiated before we create any of the constructor function instances:
        FunctionProto = new Function.EmptyFunc(this);
        
        ObjectConstruct = new PlainObject.Constructor(this);
        ObjectToString = new PlainObject.ToString(this);
        // define properties that are exclusive to the prototype instance:
        // the following properties are configurable and writable but NOT enumerable:
        ObjectProto.clobberOwnProperties(this, new Map<String, Object>{
            'constructor' => ObjectConstruct,
            'toString' => ObjectToString
            // TODO: valueOf(), hasOwnProperty(), isPrototypeOf(), propertyIsEnumerable(), toLocaleString()
            
        }, PropertyDescrip.DataConfigWritePrivs);
        // the following properties are configurable and writable but NOT enumerable:
        ObjectConstruct.clobberOwnProperties(this, new Map<String, Object>{
            // TODO: getPrototypeOf(), getOwnPropertyDescriptor(), getOwnPropertyNames(), create(), defineProperty(), defineProperties(), seal(),
            // freeze(), preventExtensions(), isSealed(), isFrozen(), isExtensible(), keys()
        }, PropertyDescrip.DataConfigWritePrivs);
        
        FunctionConstruct = new Function.Constructor(this);
        FunctionProto.clobberOwnProperties(this, new Map<String, Object>{
            'constructor' => FunctionConstruct
            // TODO: toString(), apply(), call(), bind()
        }, PropertyDescrip.DataConfigWritePrivs);
        
        ErrorProto = new Error(this, null);
        ErrorConstruct = new Error.Constructor(this);
        ErrorProto.clobberOwnProperties(this, new Map<String, Object>{
            'name' => 'Error',
            'message' => '',
            'constructor' => ErrorConstruct,
            'toString' => new Error.ToString(this)
        }, PropertyDescrip.DataConfigWritePrivs);
        
        SyntaxErrorProto = new SyntaxError(this, null); // note that SyntaxErrorProto will not have its own "message" property
        SyntaxErrorConstruct = new SyntaxError.Constructor(this);
            // the following properties are configurable and writable but NOT enumerable:
        SyntaxErrorProto.clobberOwnProperties(this, new Map<String, Object>{
            // !! note that we don't need to define message (empty String) nor toString since they will be inherited from Error.prototype one more
            // link up the prototype chain:
            'name' => 'SyntaxError',
            'constructor' => SyntaxErrorConstruct
        }, PropertyDescrip.DataConfigWritePrivs);
        
        TypeErrorProto = new TypeError(this, null); // note that TypeErrorProto will not have its own "message" property
        TypeErrorConstruct = new TypeError.Constructor(this);
            // the following properties are configurable and writable but NOT enumerable:
        TypeErrorProto.clobberOwnProperties(this, new Map<String, Object>{
            // !! note that we don't need to define message (empty String) nor toString since they will be inherited from Error.prototype one more
            // link up the prototype chain:
            'name' => 'TypeError',
            'constructor' => TypeErrorConstruct
        }, PropertyDescrip.DataConfigWritePrivs);
        
        ReferenceErrorProto = new ReferenceError(this, null); // note that ReferenceErrorProto will not have its own "message" property
        ReferenceErrorConstruct = new ReferenceError.Constructor(this);
        // the following properties are configurable and writable but NOT enumerable:
        ReferenceErrorProto.clobberOwnProperties(this, new Map<String, Object>{
            // !! note that we don't need to define message (empty String) nor toString since they will be inherited from Error.prototype one more
            // link up the prototype chain:
            'name' => 'ReferenceError',
            'constructor' => ReferenceErrorConstruct
        }, PropertyDescrip.DataConfigWritePrivs);
        
        RangeErrorProto = new RangeError(this, null);
        RangeErrorConstruct = new RangeError.Constructor(this);
        // the following properties are configurable and writable but NOT enumerable:
        RangeErrorProto.clobberOwnProperties(this, new Map<String, Object>{
            // !! note that we don't need to define message (empty String) nor toString since they will be inherited from Error.prototype one more
            // link up the prototype chain:
            'name' => 'RangeError',
            'constructor' => RangeErrorConstruct
        }, PropertyDescrip.DataConfigWritePrivs);
        
        ApexErrorProto = new ApexError(this, null);
        ApexErrorConstruct = new ApexError.Constructor(this);
        ApexErrorProto.clobberOwnProperties(this, new Map<String, Object>{
            'name' => 'ApexError',
            'constructor' => ApexErrorConstruct
        }, PropertyDescrip.DataConfigWritePrivs);
        
        // used by the Arguments class to disallow the access of caller/callee properties in strict mode code:
        ArgsThrowTypeError = new ArgsThrowTypeErrorSingleton(this);
        
        StringProto = new StringObject(this, '');
        StringConstruct = new StringObject.Constructor(this);
        StringProto.clobberOwnProperties(this, new Map<String, Object>{
            'constructor' => StringConstruct
            
            // TODO: string methods
            
        }, PropertyDescrip.DataConfigWritePrivs);
        
        BooleanProto = new BooleanObject(this, false);
        BooleanConstruct = new BooleanObject.Constructor(this);
        BooleanProto.clobberOwnProperties(this, new Map<String, Object>{
            'constructor' => BooleanConstruct
            
            // TODO: boolean methods
            
        }, PropertyDescrip.DataConfigWritePrivs);
        
        ArrayProto = new ArrayObject(this);
        ArrayConstruct = new ArrayObject.Constructor(this);
        ArrayProto.clobberOwnProperties(this, new Map<String, Object>{
            'constructor' => ArrayConstruct
            
            // TODO: array methods
            
        }, PropertyDescrip.DataConfigWritePrivs);
        
        // TODO: globalEnv, globalObj
        
        // TODO: RegExp, DateObject, NumberObject
        
    }
    
    // forks the given context and instantiates a new virtual machine to host the forked context:
    global static Context fork(Context ctx) {
        VirtualMachine fvm = new VirtualMachine(ctx.clone());
        fvm.ctx.parent = ctx;
        return fvm.ctx;
    }
    
    global class ArgsThrowTypeErrorSingleton extends Function {
        ArgsThrowTypeErrorSingleton(Context ctx) {
            super(ctx, 'ArgumentsThrowTypeError', 0);
            this.extensible = false;
        }
        
        global override Object call(Context ctx, Object thisBinding, Object[] argv) {
            return Utils.typeError(ctx, 'The \'caller\', \'callee\', and \'arguments\' properties may not be accessed on ' 
                    + 'strict mode functions or the arguments objects for calls to them');
        }
    }
}