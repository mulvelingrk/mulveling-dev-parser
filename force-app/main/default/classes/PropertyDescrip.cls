/*
 * Mike Ulveling
 */
global class PropertyDescrip {
    // all descriptors:
    global Boolean isAccessor; // true for accessor, false for data, null for generic
    global Boolean configurable;
    global Boolean enumerable;
    // used by the PlainObject.enumerateOwn method to order enumerable non-integer-able property names within the same PlainObject instance:
    global Integer localOrdinal;
    
    // data descriptors only:
    global Boolean writable;
    // a data descriptor has a value if either value != null OR hasValue == true; this allows for data descriptors that carry a property value of undefined
    global Object value;
    public Boolean hasValue;
    
    // accessor descriptors only:
    global PlainObject getter;
    global PlainObject setter; // goddamned apex reserved words (which will probably never get implemented) include "set"
    
    public static Boolean ACCESSOR = true;
    public static Boolean DATA = false;
    
    public static PropertyDescrip DataAllPrivs = new PropertyDescrip(false);
    public static PropertyDescrip DataWritePrivs = new PropertyDescrip(false);
    public static PropertyDescrip DataConfigWritePrivs = new PropertyDescrip(false);
    public static PropertyDescrip DataEnumWritePrivs = new PropertyDescrip(false);
    public static PropertyDescrip DataNoPrivs = new PropertyDescrip(false);
    
    public static PropertyDescrip AccessorAllPrivs = new PropertyDescrip(true);
    public static PropertyDescrip AccessorNoPrivs = new PropertyDescrip(true);
    
    public static PropertyDescrip Generic = new PropertyDescrip(null);
    
    static {
        DataAllPrivs.configurable = true;
        DataAllPrivs.enumerable = true;
        DataAllPrivs.writable = true;
        DataAllPrivs.hasValue = true;
        
        DataWritePrivs.configurable = false;
        DataWritePrivs.enumerable = false;
        DataWritePrivs.writable = true;
        DataWritePrivs.hasValue = true;
        
        DataConfigWritePrivs.configurable = true;
        DataConfigWritePrivs.enumerable = false;
        DataConfigWritePrivs.writable = true;
        DataConfigWritePrivs.hasValue = true;
        
        DataEnumWritePrivs.configurable = false;
        DataEnumWritePrivs.enumerable = true;
        DataEnumWritePrivs.writable = true;
        DataEnumWritePrivs.hasValue = true;
        
        DataNoPrivs.configurable = false;
        DataNoPrivs.enumerable = false;
        DataNoPrivs.writable = false;
        DataNoPrivs.hasValue = true;
        
        AccessorAllPrivs.configurable = true;
        AccessorAllPrivs.enumerable = true;
        
        AccessorNoPrivs.configurable = false;
        AccessorNoPrivs.enumerable = false;
    }
    
    public PropertyDescrip() {
        this.isAccessor = false;
    }
    
    public PropertyDescrip(Boolean isAccessor) {
        this.isAccessor = isAccessor;
    }
    
    // !! des must be a fully-populated, non-generic descriptor:
    global static PlainObject fromPropertyDescriptor(Context ctx, PropertyDescrip des) {
        if (des == null)
            return null;
        
        PlainObject obj = new PlainObject(ctx);
        PropertyDescrip res;
        if (des.isAccessor == false) {
            obj.props.put('value', res = DataAllPrivs.clone());
            res.value = des.value;
            res.hasValue = true;
            obj.props.put('writable', res = DataAllPrivs.clone());
            res.value = des.writable;
        } else if (des.isAccessor == true) {
            obj.props.put('get', res = DataAllPrivs.clone());
            res.value = des.getter;
            obj.props.put('set', res = DataAllPrivs.clone());
            res.value = des.setter;
        }
        obj.props.put('configurable', res = DataAllPrivs.clone());
        res.value = des.configurable;
        obj.props.put('enumerable', res = DataAllPrivs.clone());
        res.value = des.enumerable;
        return obj;
    }
    
    global static PropertyDescrip toPropertyDescriptor(Context ctx, Object o) {
        if (o == null || !(o instanceof PlainObject))
            Utils.typeError(ctx, Utils.valueTypeToString(ctx, o) + ' cannot be converted to a Property Descriptor');
        
        PlainObject obj = (PlainObject) o;
        PropertyDescrip des = new PropertyDescrip();
        if (obj.hasProperty(ctx, 'enumerable'))
            des.enumerable = Utils.toBoolean(ctx, obj.get(ctx, 'enumerable'));
        if (obj.hasProperty(ctx, 'configurable'))
            des.configurable = Utils.toBoolean(ctx, obj.get(ctx, 'configurable'));
        if (obj.hasProperty(ctx, 'writable'))
            des.writable = Utils.toBoolean(ctx, obj.get(ctx, 'writable'));
        if (obj.hasProperty(ctx, 'value')) {
            des.value = obj.get(ctx, 'value');
            des.hasValue = true;
        }
        
        if (obj.hasProperty(ctx, 'get')) {
            Object f = obj.get(ctx, 'get');
            if (f == null || !(f instanceof Callable))
                Utils.typeError(ctx, Utils.valueTypeToString(ctx, f) + ' cannot be used as a getter');
            des.getter = (PlainObject) f;
        }
        if (obj.hasProperty(ctx, 'set')) {
            Object f = obj.get(ctx, 'set');
            if (f == null || !(f instanceof Callable))
                Utils.typeError(ctx, Utils.valueTypeToString(ctx, f) + ' cannot be used as a setter');
            des.setter = (PlainObject) f;
        }
        
        if (des.getter != null || des.setter != null)
            des.isAccessor = true;
        if (des.hasValue == true || des.writable != null) {
            if (des.isAccessor == true)
                Utils.typeError(ctx, 'Property Descriptor may not have combine data and accessor attributes');
            else
                des.isAccessor = false;
        }
        
        return des;
    }
}