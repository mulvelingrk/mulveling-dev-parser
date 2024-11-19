/*
 * Mike Ulveling
 */
global virtual class Error extends PlainObject {
    public RuntimeException throwWrapper;
    
    global Error(Context ctx, Object message) {
        // pass our desired [[className]] to the PlainObject constructor; also note that we inherit extensible=true from PlainObject.<init>:
        super(ctx, 'Error');
        
        // Prototype will only be null during construction of the Prototype instance; for that instance we must keep [[proto]] bound to the value of
        // PlainObject.Prototype (as set in the super constructor):
        if (ctx.ErrorProto != null)
            this.proto = ctx.ErrorProto;
        
        // this Error only has its own "message" property if a value other than undefined was provided -- in the case of an undefined message, then
        // the empty-string valued "message" property on Error.prototype will come through:
        if (message != null)
            // message is configurable, NOT enumerable, and writable:
            this.clobberOwnProperty(ctx, 'message', message != null ? Utils.toString(ctx, message) : '', PropertyDescrip.DataConfigWritePrivs);
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'Error', 1, ctx.ErrorProto);
        }
        
        global virtual override Object call(Context ctx, Object thisBinding, Object[] argv) {
            return new Error(ctx, argv.size() > 0 && argv[0] != null ? argv[0] : null);
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return call(ctx, null, argv);
        }
    }
    
    global class ToString extends Function {
        public ToString(Context ctx) {
            super(ctx, 'toString', 0);
        }
        
        global override Object call(Context ctx, Object thisBinding, Object[] argv) {
            
            // TODO:
            throw new InternalException('TODO: Error.ToString.call');
        }
    }
}