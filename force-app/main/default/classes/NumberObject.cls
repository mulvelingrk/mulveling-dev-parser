/*
 * Mike Ulveling
 */
global class NumberObject extends PrimitiveObject {
    
    global NumberObject(Context ctx, Double value) {
        super(ctx, 'Number', value);
        this.extensible = true;
        if (ctx.NumberProto != null)
            this.proto = ctx.NumberProto;
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'Number', 1, ctx.NumberProto);
        }
        
        global virtual override Object call(Context ctx, Object thisArg, Object[] argv) {
            return argv.size() > 0 ? Utils.toNumber(ctx, argv[0]) : 0;
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return new NumberObject(ctx, argv.size() > 0 ? Utils.toNumber(ctx, argv[0]) : 0);
        }
    }
}