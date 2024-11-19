/*
 * Mike Ulveling
 */
global class SyntaxError extends Error {
    global SyntaxError(Context ctx, Object message) {
        super(ctx, message);
        
        // if this is not the prototype instance, then set this.proto=ctx.SyntaxErrorProto; this will override the super constructor's
        // assignment that was this.proto=ctx.ErrorProto:
        if (ctx.SyntaxErrorProto != null)
            this.proto = ctx.SyntaxErrorProto;
        // else, this is the prototype instance (i.e. ctx.SyntaxErrorProto); note that ctx.SyntaxErrorProto.proto will have been set to
        // ctx.ErrorProto in the super constructor, and that's what we want in this case, in order to "fallthrough" to the default message (empty
        // string) and toString properties...
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            // supplyThisOnConstruct=false:
            super(ctx, 'SyntaxError', 1, ctx.SyntaxErrorProto);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            return new SyntaxError(ctx, argv.size() > 0 && argv[0] != null ? argv[0] : null);
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return call(ctx, null, argv);
        }
    }
}