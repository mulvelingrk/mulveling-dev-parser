/*
 * Mike Ulveling
 */
global abstract class Environment {
    public static final Integer ENV_TYPE_DECLARATIVE = 1;
    public static final Integer ENV_TYPE_OBJECT = 2;
    
    public Integer envType;
    // the outer lexical environment:
    public Environment parent;
    
    public Environment() {}
    
    global abstract Boolean hasBinding(Context ctx, String name);
    
    global abstract void createMutableBinding(Context ctx, String name, Boolean deletable);
    
    global abstract void setMutableBinding(Context ctx, String name, Object value, Boolean strictMode);
    
    global abstract Object getBindingValue(Context ctx, String name, Boolean strict);
    
    global abstract Boolean deleteBinding(Context ctx, String name);
    
    global abstract Object implicitThisValue(Context ctx);
    
    public static Reference getIdentifierReference(Context ctx, Lexer2.Token loc, Environment lexEnv, String name, Boolean strict) {
        while (lexEnv != null) {
            if (lexEnv.envType == ENV_TYPE_DECLARATIVE)
                if (((DeclarativeEnv) lexEnv).bindingVals.containsKey(name))
                    return new Reference(loc, lexEnv, name, strict);
            // else, it must be an object environment:
            else
                if (((ObjectEnv) lexEnv).bindings.hasProperty(ctx, name))
                    return new Reference(loc, lexEnv, name, strict);
                
            // continue searching up the scope chain until we either locate a reference or reach past the top:
            lexEnv = lexEnv.parent;
        }
        // if not found by now, then this is an unresolvable reference (a base value of undefined implies an unresolvable reference):
        return new Reference(loc, null, name, strict);
    }
}