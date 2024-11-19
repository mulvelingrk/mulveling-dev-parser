/*
 * Mike Ulveling
 * 
 * ECMAScript Object; we use the name "PlainObject" because obviously "Object" is reserved in Apex
 */
global virtual class PlainObject {
    // !! all "own" properties of this Object MUST be found in this map:
    public Map<String, PropertyDescrip> props;
    // the ECMAScript Object.[[class]] internal property; we use "className" because obviously "class" is reserved in Apex:
    public String className;
    // the ECMAScript Object.[[prototype]] internal property; we use "proto" to avoid confusion with the exposed "prototype" property:
    public PlainObject proto;
    // the ECMAScript Object.[[extensible]] internal property
    public Boolean extensible;
    
    // the following boolean flags are used to implement certain optimizations:
    
    // set to true for builtin classes which implement custom hasOwnProperty logic (e.g. on StringObject, to add index properties)
    // !! when customGetOwnProp is set to true, it must be inherited down the proto chain -- this is implemented VirtualMachine.dispatchConstruct,
    // and the builtin Object.create method:
    public Boolean customGetOwnProp;
    
    // TODO:
    public Boolean inheritsCutsomGetOwn;
    public Boolean customDefineOwn;
    
    // this constructor should only be used in special cases, like PrimitiveObject:
    public PlainObject() {}
    
    global PlainObject(Context ctx, String className) {
        this.className = className;
        // ctx.ObjectProto will not be null because its instance is instantiated with the 0-arg constructor:
        this.proto = ctx.ObjectProto;
        // !! extensible=true will be desired the vast majority of the time; special-case extensions will need to override this:
        this.extensible = true;
        this.props = new Map<String, PropertyDescrip>();
    }
    
    global PlainObject(Context ctx) {
        this.className = 'Object';
        // ctx.ObjectProto will only be null during construction of the Prototype instance; for that instance we must keep [[proto]] set to null:
        if (ctx.ObjectProto != null)
            this.proto = ctx.ObjectProto;
        else
            // TODO:
            // !! ECMAScript spec says this value should be the ECMAScript value null, not undefined, but that would cause us to cast a lot more than
            // necessary (since NullSingleton.NUL is not an instanceof PlainObject, so we'd have to declare proto as Object), so we'll use undefined
            // and then try to make sure we convert it to ECMAScript null for externally facing APIs (e.g. the non-spec'd "__proto__" property):
            this.proto = null;
        
        // !! extensible=true will be desired the vast majority of the time; special-case extensions will need to override this:
        this.extensible = true;
        this.props = new Map<String, PropertyDescrip>();
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'Object', 1, ctx.ObjectProto);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            return new PlainObject(ctx);
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return call(ctx, null, argv);
        }
    }
    
    global class ToString extends Function {
        public ToString(Context ctx) {
            super(ctx, 'toString', 0);
        }
        
        global override Object call(Context ctx, Object thisBinding, Object[] argv) {
            if (thisBinding instanceof PlainObject)
                return '[object ' + ((PlainObject) thisBinding).className + ']';
            else if (thisBinding == null)
                return '[object Undefined]';
            else if (thisBinding instanceof Double)
                return '[object Number]';
            else if (thisBinding instanceof String)
                return '[object String]';
            else if (thisBinding instanceof Boolean)
                return '[object Boolean]';
            else if (thisBinding == NullSingleton.NUL)
                return '[object Null]';
            
            throw new InternalException('Illegal \'this\' type for Object.prototype.toString: ' + thisBinding);
        }
    }
    
    // !! ECMAScript specifies that a clone of the property descriptor must be returned, however I don't see instances where this would be necessary;
    // if it turns out to be needed in a particular scenario, then the client code may invoke a clone() on this method's result:
    global virtual PropertyDescrip getOwnProperty(Context ctx, String name) {
        return props.get(name);
    }
    
    // !! ECMAScript specifies that a clone of the property descriptor must be returned, however I don't see instances where this would be necessary;
    // if it turns out to be needed in a particular scenario, then the client code may invoke a clone() on this method's result:
    global virtual PropertyDescrip getProperty(Context ctx, String p) {
        PropertyDescrip prop;
        // the literal implementation of spec:
        if (customGetOwnProp == true) {
            prop = getOwnProperty(ctx, p);
            if (prop != null)
                return prop;
            
            if (this.proto != null)
                return this.proto.getProperty(ctx, p);
        // else if we don't have to deal with custom "own" prop logic, then we can implement a more efficient loop search:
        } else {
            PlainObject next = this;
            do {
                prop = next.props.get(p);
                if (prop != null)
                    return prop;
                
                next = next.proto;
            } while (next != null);
        }
        return null;
    }
    
    global virtual Object get(Context ctx, String p) {
        PropertyDescrip prop;
        // the literal implementation of spec:
        if (customGetOwnProp == true) {
            prop = getProperty(ctx, p);
        // else if we don't have to deal with custom "own" prop logic, then we can inline a more efficient loop search:
        } else {
            PlainObject next = this;
            do {
                prop = next.props.get(p);
                if (prop != null)
                    break;
                
                next = next.proto;
            } while (next != null);
        }
        
        if (prop == null)
            return null;
        else if (prop.isAccessor == false)
            return prop.value;
        else if (prop.getter != null)
            return VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, prop.getter, this, Utils.EMPTY_ARGV);
        else 
            return null;
    }
    
    global virtual Boolean canPut(Context ctx, String p) {
        PropertyDescrip prop;
        // the literal implementation of spec:
        if (customGetOwnProp == true)
            prop = getOwnProperty(ctx, p);
        else
            prop = props.get(p);
        
        if (prop != null) {
            if (prop.isAccessor == true)
                return prop.setter != null;
            else
                return prop.writable;
        } else {
            if (this.proto == null) {
                return this.extensible;
            } else {
                PropertyDescrip inherited;
                if (customGetOwnProp == true) {
                    inherited = getProperty(ctx, p);
                } else {
                    PlainObject next = this.proto;
                    while (next != null) {
                        inherited = next.props.get(p);
                        if (inherited != null)
                            break;
                        
                        next = next.proto;
                    }
                }
                
                if (inherited == null)
                    return this.extensible;
                else if (inherited.isAccessor == true)
                    return inherited.setter != null;
                else
                    return this.extensible && inherited.writable;
            }
        }
    }
    
    // !! subclasses that override [[DefineOwnProperty]] should also override this method:
    global virtual void put(Context ctx, String p, Object v, Boolean throwError) {
        if (customGetOwnProp == true) {
            // generic (more rigorous) but slower implementation:
            if (!canPut(ctx, p))
                if (throwError)
                    Utils.typeError(ctx, 'Cannot write to property ' + p);
                else return;
            
            PropertyDescrip ownDesc = getOwnProperty(ctx, p);
            // if it's an existing own data prop, then submit the new value and return:
            if (ownDesc != null && ownDesc.isAccessor == false) {
                PropertyDescrip valueDesc = new PropertyDescrip(PropertyDescrip.DATA);
                valueDesc.value = v;
                valueDesc.hasValue = true;
                defineOwnProperty(ctx, p, valueDesc, throwError);
                return;
            }
            PropertyDescrip des;
            // else it may be either an own accessor prop, or an inherited data or accessor prop:
            if (ownDesc != null)
                // it's an own accessor prop:
                des = ownDesc;
            else if (this.proto != null)
                // look for an inherited data or accessor prop:
                des = this.proto.getProperty(ctx, p);
            
            if (des != null) {
                // own or inherited accessor; dispatch its "set" method:
                if (des.isAccessor == true) {
                    // the setter must be defined, because we passed the canPut() checks above:
                    VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, des.setter, this, new Object[]{ v });
                    return;
                // else it's an inherited data prop; we must check its writability before creating a new own data prop (all privs):
                } else {
                    if (!des.writable) {
                        if (throwError)
                            Utils.TypeError(ctx, 'Cannot write to property ' + p + ' that is not writable');
                        else return;
                    }
                    // fallthrough to create new own data prop...
                }
            }
            // else no own or inherited prop currently exists; fallthrough to create a new own data prop (all privs)...
            
            PropertyDescrip newDesc = PropertyDescrip.DataAllPrivs.clone();
            newDesc.value = v;
            defineOwnProperty(ctx, p, newDesc, throwError);
        } else {
            // in order to improve efficiency -- in cases where we don't have to deal with custom getOwnProperty or defineOwnProperty anywhere in the
            // proto chain -- this implementation of [[Put]] 8.12.4 combines and inlines logic from [[CanPut]] 8.12.5 and [[DefineOwnProperty]] 8.12.9
            // rather than calling those methods. note that this implementation also provides better errors messages in cases where this [[Put]] is
            // not allowed:
            PlainObject host = this;
            PropertyDescrip des;
            do {
                des = host.props.get(p);
                if (des != null)
                    break;
                
                host = host.proto;
            } while (host != null);
            
            // if we didn't find an own prop nor an inherited one, then put-ability is contingent upon this object's extensibility:
            if (des == null) {
                if (!this.extensible) {
                    if (throwError)
                        Utils.TypeError(ctx, 'Cannot create property ' + p + ' on object that is not extensible');
                    else return;
                }
                // create a new own data prop with all privs:
                this.props.put(p, des = PropertyDescrip.DataAllPrivs.clone());
                des.value = v;
                des.localOrdinal = Utils.OrdinalCounter++;
                
            // else if the existing prop is an accessor -- no difference between an own vs. inherited property in this case:
            } else if (des.isAccessor) {
                if (des.setter == null) {
                    if (throwError)
                        Utils.TypeError(ctx, 'Cannot write to accessor ' + p + ' without a setter');
                    else return;
                }
                VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, des.setter, this, new Object[]{ v });
                
            // else we have an existing data prop; there's an additional extensibility check in the case of an inherited prop; a prop is an "own"
            // prop if and only if host object is the same as this object:
            } else {
                if (!des.writable) {
                    if (throwError)
                        Utils.TypeError(ctx, 'Cannot write to property ' + p + ' that is not writable');
                    else return;
                }
                // if we have an inherited data prop, then create a new "own" data prop with all priviledges and the given value:
                if (host !== this) {
                    if (!this.extensible) {
                        if (throwError)
                            Utils.TypeError(ctx, 'Cannot create property ' + p + ' on object that is not extensible');
                        else return;
                    }
                    this.props.put(p, des = PropertyDescrip.DataAllPrivs.clone());
                    des.value = v;
                    des.localOrdinal = Utils.OrdinalCounter++;
                // else we have an existing own data prop, so simply set the value:
                } else {
                    des.value = v;
                }
            }
        }
    }
    
    global virtual Boolean hasProperty(Context ctx, String p) {
        if (customGetOwnProp == true) {
            return getProperty(ctx, p) != null;
        } else {
            PlainObject next = this;
            do {
                if (next.props.get(p) != null)
                    return true;
                
                next = next.proto;
            } while (next != null);
            return false;
        }
    }
    
    global virtual Boolean deleteProperty(Context ctx, String p, Boolean throwError) {
        PropertyDescrip ownDesc;
        if (customGetOwnProp == true)
            ownDesc = getOwnProperty(ctx, p);
        else
            ownDesc = props.get(p);
        
        if (ownDesc == null)
            return true;
        else if (ownDesc.configurable) {
            props.remove(p);
            return true;
        } else if (throwError)
            Utils.typeError(ctx, 'Cannot delete non-configurable property ' + p);
        
        return false;
    }
    
    // oh hooray, yet another uselessly reserved word in Apex: "hint" => "hnt"
    global virtual Object defaultValue(Context ctx, Integer hnt) {
        Object f, val;
        if (hnt == Utils.STRING_HINT) {
            f = this.get(ctx, 'toString');
            if (f != null && f instanceof Callable) {
                val = VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, f, this, Utils.EMPTY_ARGV);
                if (val == null || !(val instanceof PlainObject))
                    return val;
                else if (val != null && val instanceof PrimitiveObject)
                    return ((PrimitiveObject) val).primitiveValue;
            }
            f = this.get(ctx, 'valueOf');
            if (f != null && f instanceof Callable) {
                val = VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, f, this, Utils.EMPTY_ARGV);
                if (val == null || !(val instanceof PlainObject))
                    return val;
                else if (val != null && val instanceof PrimitiveObject)
                    return ((PrimitiveObject) val).primitiveValue;
            }
            return Utils.typeError(ctx, 'Default value for ' + className + ' did not resolve to a primitive value');
        // else, Number hint (the default):
        } else {
            f = this.get(ctx, 'valueOf');
            if (f != null && f instanceof Callable) {
                val = VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, f, this, Utils.EMPTY_ARGV);
                if (val == null || !(val instanceof PlainObject))
                    return val;
                else if (val != null && val instanceof PrimitiveObject)
                    return ((PrimitiveObject) val).primitiveValue;
            }
            f = this.get(ctx, 'toString');
            if (f != null && f instanceof Callable) {
                val = VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, f, this, Utils.EMPTY_ARGV);
                if (val == null || !(val instanceof PlainObject))
                    return val;
                else if (val != null && val instanceof PrimitiveObject)
                    return ((PrimitiveObject) val).primitiveValue;
            }
            return Utils.typeError(ctx, 'Default value for ' + className + ' did not resolve to a primitive value');
        }
    }
    
    // !! subclasses that override this method should also override [[Put]]:
    // !! note that checking for des.hasValue==true allows us to change an existing data property to the value undefined:
    global virtual Boolean defineOwnProperty(Context ctx, String p, PropertyDescrip des, Boolean throwError) {
        PropertyDescrip curr;
        if (customGetOwnProp == true)
            curr = getOwnProperty(ctx, p);
        else
            curr = props.get(p);
            
        if (curr == null) {
            if (!this.extensible) {
                if (throwError)
                    Utils.typeError(ctx, 'Cannot create property ' + p + ' on object that is not extensible');
                else return false;
            } else if (des.isAccessor == true)
               curr = PropertyDescrip.AccessorNoPrivs.clone();
            else
               curr = PropertyDescrip.DataNoPrivs.clone();
            
            curr.localOrdinal = Utils.OrdinalCounter++;
            props.put(p, curr);
            // fallthrough to overwrite curr with properties provided by des...
        } else {
            
            // !! note that the "return true" no-op checks described by the spec are redundant because the subsequent validation checks perform the
            // same guards (e.g. Utils.sameValue), so we skip them to save all those comparison ops...
            
            if (!curr.configurable) {
                if (des.configurable == true) {
                    if (throwError)
                        Utils.typeError(ctx, 'Cannot convert ' + p + ' to a configurable property');
                    else return false;
                }
                if (des.enumerable != null && des.enumerable != curr.enumerable) {
                    if (throwError)
                        Utils.typeError(ctx, 'Cannot convert ' + p + ' to an enumerable property');
                    else return false;
                }
            }
            
            // generic descriptors have completed all necessary validation; continue validation for data and accessor descriptors:
            if (des.isAccessor != null) {
                if (des.isAccessor != curr.isAccessor) {
                    if (!curr.configurable) {
                        if (throwError)
                            Utils.typeError(ctx, 'Cannot convert property ' + p + ' from ' 
                                    + (curr.isAccessor ? 'accessor' : 'data') + ' to ' 
                                    + (des.isAccessor ? 'accessor' : 'data'));
                        else return false;
                    }
                    PropertyDescrip oldCurr = curr;
                    // convert to accessor or data:
                    if (des.isAccessor)
                        curr = PropertyDescrip.AccessorNoPrivs.clone();
                    else
                        curr = PropertyDescrip.DataNoPrivs.clone();
                    
                    curr.configurable = true; // obviously, the property was/is configurable
                    curr.enumerable = oldCurr.enumerable;
                    curr.localOrdinal = Utils.OrdinalCounter++;
                    props.put(p, curr);
                    // fallthrough to overwrite curr with properties provided by des...
                
                // a configurable prop accepts all changes; if not configurable then we must do the following additional validation for the
                // incoming data or accessor prop; if configurable then simply fallthrough to overwrite curr with properties provided by des...
                } else if (!curr.configurable) {
                    if (curr.isAccessor == false) {
                        if (!curr.writable) {
                            if (des.writable == true) {
                                if (throwError)
                                    Utils.typeError(ctx, 'Cannot convert ' + p + ' to a writable property');
                                else return false;
                            } else if ((des.value != null || des.hasValue == true) && !Utils.sameValue(ctx, des.value, curr.value)) {
                                if (throwError)
                                    Utils.typeError(ctx, 'Cannot write into read-only property ' + p);
                                else return false;
                            }
                        }
                    } else {
                        if (des.getter != null && !Utils.sameValue(ctx, des.getter, curr.getter)) {
                            if (throwError)
                                Utils.typeError(ctx, 'Cannot change getter for non-configurable property ' + p);
                            else return false;
                        }
                        if (des.setter != null && !Utils.sameValue(ctx, des.setter, curr.setter)) {
                            if (throwError)
                                Utils.typeError(ctx, 'Cannot change setter for non-configurable property ' + p);
                            else return false;
                        }
                    }
                }
            }
        }
        
        if (des.configurable != null) curr.configurable = des.configurable;
        if (des.enumerable != null) curr.enumerable = des.enumerable;
        if (des.isAccessor == false) {
            if (des.writable != null) curr.writable = des.writable;
            // checking for hasValue==true allows us to change an existing data property to the value undefined:
            if (des.value != null || des.hasValue == true) {
                curr.value = des.value;
                // TODO: the following may be redundant because data descriptors in an object are presumed to be fully populated (i.e. assumed
                // to have a value):
                //curr.hasValue = true;
            }
        } else if (des.isAccessor == true) {
            if (des.getter != null) curr.getter = des.getter;
            if (des.setter != null) curr.setter = des.setter;
        }
        
        return true;
    }
    
    // subclasses of PlainObject that implement ECMAScript's [[HasInstance]] internal method (e.g. Function) must override this; this default
    // implementation throws a TypeError to follow ECMAScript's specified behavior for objects not implementing [[HasInstance]]:
    global virtual Boolean hasInstance(Context ctx, Object v) {
        Utils.TypeError(ctx, 'Expecting a function in instanceof check, but got ' + Utils.toString(ctx, v));
        return false;
    }
    
//    global virtual void enumerate(String[] enumList, Map<String, PlainObject> nameToOwner) {
//        enumerateOwn(enumList, nameToOwner);
//        if (proto != null)
//            proto.enumerate(enumList, nameToOwner);
//    }
    
    // !! this should be overridden if you're going to set customGetOwnProp=true in the constructor (e.g. StringObject)
    //
    // the enumeration algorithm is NOT fully specified by ECMAScript5; it's largely left up to implementors, besides a few key details (e.g.
    // inherited property masking) that are outlined in 12.6.4
    // our algorithm attempts to output a sensible & consistent ordering, using Google V8 as an example. our algorithm is as follows:
    // 
    //    create an Integer[] intNames
    //    create a Map<Integer, String[]> txtNames
    //    for each "own property" tuple { String, PropertyDescriptor } => { name, desc } on this object:
    //       add name to enumSet and let isMasked be the boolean negation of the result
    //       if isMasked is true, then this property is masked by a previously traversed link in the proto chain; continue
    //       if desc.enumerable is false, then continue
    //       if name is the exact string representation of a 32-bit signed integer, then add its integer value to intNames
    //       else add name into the txtNames map bucket under desc.localOrdinal (which may be null); if the bucket is null then instantiate it
    //    add to enumList the string representation of each value in intNames, maintaining order
    //    let ordinals (String[]) be the sorted keys of the txtNames map
    //    for each ordKey in ordinals (maintaining order):
    //        add to enumList all members of the bucket under txtNames[ordKey], maintaining order
    global virtual void enumerateOwn(String[] enumList, Map<String, PlainObject> nameToOwner) {
        Integer[] intNames;
        Map<Integer, String[]> txtNames;
        for (String p: props.keySet()) {
            // note that this property may mask subsequent instances (of the same name) further up the proto chain, even if it's not enumerable:
            PlainObject maskingObj = nameToOwner.put(p, this);
            if (maskingObj != null) {
                // this property of the current object has been masked by an owner object further down the proto chain; put back the masking object:
                nameToOwner.put(p, maskingObj);
                continue;
            }
            
            PropertyDescrip des = props.get(p);
            if (des.enumerable) {
                Integer pint;
                if (p.isNumeric()) {
                    try {
                        pint = Integer.valueOf(p);
                        if (String.valueOf(pint) != p)
                            pint = null;
                    } catch (System.TypeException ignore) { }
                }
                
                if (pint != null) {
                    if (intNames == null)
                        intNames = new Integer[]{ pint };
                    else 
                        intNames.add(pint);
                } else {
                    if (txtNames == null) {
                        txtNames = new Map<Integer, String[]>{ des.localOrdinal => new String[]{ p } };
                    } else {
                        // get the list of all non-int names sharing the local ordinal as this property:
                        String[] siblings = txtNames.get(des.localOrdinal);
                        if (siblings == null)
                            txtNames.put(des.localOrdinal, new String[]{ p });
                        else
                            siblings.add(p);
                    }
                }
            }
        }
        
        if (intNames != null) {
            intNames.sort();
            for (Integer i: intNames)
                enumList.add(String.valueOf(i));
        }
        
        if (txtNames != null) {
            Integer[] ordinals = new List<Integer>(txtNames.keySet());
            ordinals.sort();
            for (Integer ord: ordinals)
                enumList.addAll(txtNames.get(ord));
        }
    }
    
    public void defineOwnAccessorProperty(Context ctx, String p, Function getter, Function setter, PropertyDescrip accessorProto, Boolean throwError) {
        PropertyDescrip newDesc = accessorProto.clone();
        newDesc.getter = getter;
        newDesc.setter = setter;
        defineOwnProperty(ctx, p, newDesc, throwError);
    }
    
    public void defineOwnDataProperty(Context ctx, String p, Object v, PropertyDescrip dataProto, Boolean throwError) {
        PropertyDescrip newDesc = dataProto.clone();
        newDesc.value = v;
        defineOwnProperty(ctx, p, newDesc, throwError);
    }
    
    public void defineOwnDataProperties(Context ctx, Map<String, Object> values, PropertyDescrip dataProto, Boolean throwError) {
        for (String p: values.keySet()) {
            PropertyDescrip newDesc = dataProto.clone();
            newDesc.value = values.get(p);
            defineOwnProperty(ctx, p, newDesc, throwError);
        }
    }
    
    // forces the given data property definition -- in full, regardless of any existing property descriptor under that name, and also disregarding
    // the [[extensible]] internal property of this Object -- onto the given property name. useful for the initialization of builtin proptotype &
    // constructor instance properties:
    public void clobberOwnProperty(Context ctx, String name, Object value, PropertyDescrip dataProto) {
        PropertyDescrip data = dataProto.clone();
        data.value = value;
        data.localOrdinal = Utils.OrdinalCounter++;
        props.put(name, data);
    }
    
    // performs clobberOwnProperty() for each key-value pair in the values map:
    public void clobberOwnProperties(Context ctx, Map<String, Object> values, PropertyDescrip dataProto) {
        for (String name: values.keySet()) {
            PropertyDescrip data = dataProto.clone();
            data.value = values.get(name);
            data.localOrdinal = Utils.OrdinalCounter++;
            props.put(name, data);
        }
    }
    
    // forces the given accessor property definition -- in full, regardless of any prior property descriptor under that name, and also disregarding
    // the [[extensible]] internal property of this Object -- onto the given property name. useful for the initialization of builtin proptotype &
    // constructor instance properties:
    public void clobberOwnProperty(Context ctx, String name, Function getter, Function setter, PropertyDescrip accessorProto) {
        PropertyDescrip accessor = accessorProto.clone();
        accessor.getter = getter;
        accessor.setter = setter;
        accessor.localOrdinal = Utils.OrdinalCounter++;
        props.put(name, accessor);
    }
}