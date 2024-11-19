/*
 * Mike Ulveling
 * 
 * Base class for MFunction and custom host/native implementations
 */
global abstract class Function extends PlainObject implements Callable {
    // if initialPrototype is null (ECMAScript undefined), then this function instance is flagged as not constructible and in that case the last
    // param (prototypeDataPropProto -- i.e. what defines the "prototype"'s data property priviledges) is ignored:
    public Function(Context ctx, String name, Integer length, PlainObject initialPrototype, PropertyDescrip prototypeDataPropProto) {
        // pass our desired [[className]] to the PlainObject constructor:
        super(ctx, 'Function');
        
        // Prototype will only be null during construction of the Prototype instance (i.e. the Empty func); for that instance we must keep [[proto]]
        // bound to the value of ctx.ObjectProto, and we also don't define a "prototype" property:
        if (ctx.FunctionProto != null) {
            // set [[proto]]:
            this.proto = ctx.FunctionProto;
            if (initialPrototype != null)
                // use the supplied configurable/enumerable/writable feature bits to define the "prototype" property:
                this.clobberOwnProperty(ctx, 'prototype', initialPrototype, prototypeDataPropProto);
        }
        
        // the following properties are not configurable, enumerable, nor writable:
        this.defineOwnDataProperties(ctx, new Map<String, Object>{
                'name' => name == null ? '' : name,    
                'length' => (Double) length
            }, PropertyDescrip.DataNoPrivs, false);
    }
    
    // use this signature for constructible native functions that should have their "prototype" property defined without configurable/enumerable/
    // writable features (supply a non-null initialPrototype):
    global Function(Context ctx, String name, Integer length, PlainObject initialPrototype) {
        this(ctx, name, length, initialPrototype, PropertyDescrip.DataNoPrivs);
    }
    
    // use this signature for non-constructible native functions:
    global Function(Context ctx, String name, Integer length) {
        this(ctx, name, length, null, null);
    }
    
    // Context.FunctionProto, which is itself a Function:
    global class EmptyFunc extends Function {
        public EmptyFunc(Context ctx) {
            // the Empty func is not constructible:
            super(ctx, 'Empty', 0);
        }
        
        global override Object call(Context ctx, Object thisBinding, Object[] argv) {
            return null;
        }
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            // the Function constructor's "prototype" property is set to: "function Empty() {}" (i.e. Function.Prototype):
            super(ctx, 'Function', 1, ctx.FunctionProto);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            // TODO:
            throw new InternalException('TODO: Function.ConstructorImpl.call');
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return call(ctx, null, argv);
        }
    }
    
    global virtual Object call(Context ctx, Object thisArg, Object[] argv){
        System.assert(false, 'Internal [[call]] method not implemented');
        return null;
    }
    
    global virtual override Boolean hasInstance(Context ctx, Object v) {
        if (v == null || !(v instanceof PlainObject))
            return false;
        
        PropertyDescrip protoDesc;
        Object o;
        // we take a shortcut if "prototype" is a data property directly on this Function object (which is the case the vast majority of the time):
        if ((protoDesc = this.props.get('prototype')) != null && !protoDesc.isAccessor)
            o = protoDesc.value;
        // else, invoke the more expensive but thorough [[Get]] call:
        else
            o = this.get(ctx, 'prototype');
        
        if (o == null || !(o instanceof PlainObject))
            Utils.TypeError(ctx, 'Expected Function prototype to be an object for instanceof check, but got ' + Utils.toString(ctx, o));
        
        PlainObject funcProto = (PlainObject) o;
        PlainObject nextValProto = ((PlainObject) v).proto;
        do {
            if (nextValProto === funcProto)
                return true;
            else if (nextValProto == null)
                return false;
            
            nextValProto = nextValProto.proto;
        } while (true);
        
        return false; // unreachable
    }
}