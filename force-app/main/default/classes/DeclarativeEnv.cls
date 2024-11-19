/*
 * Mike Ulveling
 */
global class DeclarativeEnv extends Environment {
    
    public Map<String, Object> bindingVals;
    // special markers:
    public Set<String> immutables;
    public Set<String> deletables;
    
    public DeclarativeEnv() {
        this.envType = Environment.ENV_TYPE_DECLARATIVE;
    }
    
    public DeclarativeEnv(Environment parent) {
        this.envType = Environment.ENV_TYPE_DECLARATIVE;
        this.parent = parent;
        this.bindingVals = new Map<String, Object>();
    }
    
    global override Boolean hasBinding(Context ctx, String name) {
        return bindingVals.containsKey(name);
    }
    
    global override void createMutableBinding(Context ctx, String name, Boolean d) {
        bindingVals.put(name, null);
        if (d) {
            if (deletables == null)
                deletables = new Set<String>{ name };
            else
                deletables.add(name);
        }
    }
    
    global override void setMutableBinding(Context ctx, String name, Object value, Boolean strict) {
        if (immutables != null && immutables.contains(name)) {
            if (strict)
                Utils.TypeError(ctx, 'Declared binding \'' + name + '\' is not writable');
        } else
            bindingVals.put(name, value);
    }
    
    global override Object getBindingValue(Context ctx, String name, Boolean strict) {
        return bindingVals.get(name);
    }
    
    global override Boolean deleteBinding(Context ctx, String name) {
        if (deletables != null && deletables.contains(name))
            return false;
        
        bindingVals.remove(name);
        return true;
    }
    
    global void createImmutableBinding(Context ctx, String name, Object initValue) {
        bindingVals.put(name, initValue);
        if (immutables == null)
            immutables = new Set<String>{ name };
        else
            immutables.add(name);
    }
    
    global override Object implicitThisValue(Context ctx) {
        return null;
    }
    
    public static DeclarativeEnv newInstance(Context ctx, Environment parent, 
            String firstBindingName, Object firstBindingVal, Boolean firstBindingMutable, Boolean firstBindingDeletable) {
        DeclarativeEnv env = new DeclarativeEnv();
        env.parent = parent;
        env.bindingVals = new Map<String, Object>{
            firstBindingName => firstBindingVal
        };
        
        if (!firstBindingMutable)
            env.immutables = new Set<String>{ firstBindingName };
        if (firstBindingDeletable)
            env.deletables = new Set<String>{ firstBindingName };
            
        return env;
    }
}