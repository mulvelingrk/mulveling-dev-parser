/*
 * Mike Ulveling
 */
global class ApexError extends Error {
    global ApexError(Context ctx, Object message) {
        super(ctx, message);
        
        // if this is not the prototype instance, then set this.proto=ctx.ApexErrorProto; this will override the super constructor's
        // assignment that was this.proto=ctx.ErrorProto:
        if (ctx.ApexErrorProto != null)
            this.proto = ctx.ApexErrorProto;
        // else, this is the prototype instance (i.e. ApexErrorProto); note that ctx.ApexErrorProto.proto will have been set to
        // ctx.ErrorProto in the super constructor, and that's what we want in this case, in order to "fallthrough" to the default message (empty
        // string) and toString properties...
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'ApexError', 1, ctx.ApexErrorProto);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            return new ApexError(ctx, argv.size() > 0 && argv[0] != null ? argv[0] : null);
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return call(ctx, null, argv);
        }
    }
}