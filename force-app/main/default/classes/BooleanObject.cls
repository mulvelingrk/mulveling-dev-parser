/*
 * Mike Ulveling
 */
global class BooleanObject extends PrimitiveObject {
    
    global BooleanObject(Context ctx, Boolean value) {
        super(ctx, 'Boolean', value);
        this.extensible = true;
        if (ctx.BooleanProto != null)
            this.proto = ctx.BooleanProto;
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'Boolean', 1, ctx.BooleanProto);
        }
        
        global virtual override Object call(Context ctx, Object thisArg, Object[] argv) {
            return argv.size() > 0 ? Utils.toBoolean(ctx, argv[0]) : false;
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return new BooleanObject(ctx, argv.size() > 0 ? Utils.toBoolean(ctx, argv[0]) : false);
        }
    }
}