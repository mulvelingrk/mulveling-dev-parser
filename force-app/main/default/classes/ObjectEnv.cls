/*
 * Mike Ulveling
 */
global class ObjectEnv extends Environment {
    public PlainObject bindings;
    public Boolean provideThisBinding;
    
    public ObjectEnv(Environment parent, PlainObject bindings) {
        this.envType = Environment.ENV_TYPE_OBJECT;
        this.parent = parent;
        this.bindings = bindings;
        this.provideThisBinding = false;
    }
    
    public ObjectEnv(Environment parent, PlainObject bindings, Boolean provideThisBinding) {
        this.envType = Environment.ENV_TYPE_OBJECT;
        this.parent = parent;
        this.bindings = bindings;
        this.provideThisBinding = provideThisBinding;
    }
    
    global override Boolean hasBinding(Context ctx, String key) {
        return bindings.hasProperty(ctx, key);
    }
    
    global override void createMutableBinding(Context ctx, String name, Boolean deletable) {
        PropertyDescrip des = PropertyDescrip.DataAllPrivs.clone();
        des.configurable = deletable == true;
        des.hasValue = true;
        bindings.defineOwnProperty(ctx, name, des, true);
    }
    
    global override void setMutableBinding(Context ctx, String name, Object value, Boolean strict) {
        bindings.put(ctx, name, value, strict);
    }
    
    global override Object getBindingValue(Context ctx, String name, Boolean strict) {
        if (bindings.hasProperty(ctx, name))
            return bindings.get(ctx, name);
        else if (strict)
            return Utils.referenceError(ctx, name + ' is not defined');
        else    
            return null;
    }

    global override Boolean deleteBinding(Context ctx, String name) {
        return bindings.deleteProperty(ctx, name, false);
    }
    
    global override Object implicitThisValue(Context ctx) {
        if (provideThisBinding)
            return bindings;
        else
            return null;
    }
}