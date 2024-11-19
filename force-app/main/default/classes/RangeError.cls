/*
 * Mike Ulveling
 */
global class RangeError extends Error {
    global RangeError(Context ctx, Object message) {
        super(ctx, message);
        
        // if this is not the prototype instance, then set this.proto=ctx.ReferenceErrorProto; this will override the super constructor's
        // assignment that was this.proto=Error.Prototype:
        if (ctx.RangeErrorProto != null)
            this.proto = ctx.RangeErrorProto;
        // else, this is the prototype instance (i.e. ctx.ReferenceErrorProto); note that ctx.ReferenceErrorProto.proto will have been set to
        // ctx.ErrorProto in the super constructor, and that's what we want in this case, in order to "fallthrough" to the default message (empty
        // string) and toString properties...
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            // supplyThisOnConstruct=false:
            super(ctx, 'RangeError', 1, ctx.RangeErrorProto);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            return new RangeError(ctx, argv.size() > 0 && argv[0] != null ? argv[0] : null);
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return call(ctx, null, argv);
        }
    }
}