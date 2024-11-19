/*
 * Mike Ulveling
 */
global class MFunction extends Function implements Constructible {
    public Environment scope;
    public CodeContext.Function code;

    public MFunction(Context ctx, Environment scope, CodeContext.Function code) {
        // supplyThisOnConstruct=true;
        // note that we create a new PlainObject() instance for each function's "prototype" property, and that it is writable:
        super(ctx, code.name, code.formalParams.size(), new PlainObject(ctx), PropertyDescrip.DataWritePrivs);
        this.scope = scope;
        this.code = code;
    }
    
    global override Object call(Context ctx, Object thisArg, Object[] argv){
        System.assert(false, 'Internal [[call]] method of MFunction should not be invoked');
        return null;
    }
    
    global Object construct(Context ctx, Object[] argv) {
        System.assert(false, 'Internal [[construct]] method of MFunction should not be invoked');
        return null;
    }
}