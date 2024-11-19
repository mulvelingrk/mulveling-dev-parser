global virtual class DataDesc {
	// host environment:
    public Environ env;
    // DT_REFERENCE, DT_BASE_OBJECT, DT_ABSOLUTE_NULL, DT_STRING, DT_ID, DT_NUMBER, DT_BOOLEAN, DT_DATE, DT_DATETIME, 
    // DT_OBJECT, DT_SOBJECT, DT_ARRAY:
    public Integer typeEnum;
    // typeName must be of the format: /[$_a-z][$_a-z0-9]+(\.[$_a-zA-Z][$_a-z0-9]+)*/i (note this allows for dot-delimited 
    // compound type names. the host environment maintains a type registry that prevents typeName conflicts -- each unique name 
    // (case-insensitive) can only be declared once:
    public String typeName;
    //// set to true only for DT_STRING, DT_ARRAY:
    //public Boolean indexable

    public Boolean sealed = false;
    public DataDesc superClass;
    // map of property key (lower-case'd property name) to its property descriptor (contains type information)
    public Map<String, PropDesc> propsLC = new Map<String, PropDesc>();
    // when this class is sealed, its props will be serialized into the following ptable. note that for all subclasses, inherited 
    // props must occupy the same index slot as allocated in their superclass!
    public PropDesc[] ptable;
    // Synchronized with ptable slots to define default property values. Generated upon sealing of this class. This Value array 
    // will be shallow-cloned and copied into each newly minted Value instance of this class (Value.props). This array is also 
    // used to mint property values for the NullInstance of this type:
    public Value[] pinits;

    // Each FunctionGroup represents an overloaded set of methods for a given function name (i.e. same scoped identifier; 
    // different formal args signature):
    public Map<String, FunctionGroup> funGroupsLC = new Map<String, FunctionGroup>();
    // When this class is sealed, its funcs (including constructors) will be serialized into the following vtable. Note that for 
    // all subclasses, inherited and override methods must occupy the same index slot!
    public FunctionDesc[] vtable;

    public DataDesc(Environ env, Integer typeEnum, String typeName) {
//        if (!QualifiedNamePatt.test(typeName))
//            DataDescError("Invalid type name " + typeName)
        this.env = env;
        this.typeEnum = typeEnum;
        this.typeName = typeName;
//        this.primitive = false;
//        this.indexable = false;
        // NOTE: We DON'T automatically register types, since we need to seal() a type upon registration. It is up to the 
        // instantiator of this DataDesc to register this type into env, after defining all properties/methods.
        //env.register(this)
    }

    // TODO:
    Value NullObject;
    Boolean supportsNullObject;
    global virtual Value getNullObject() { return null; }

    global void extend(DataDesc superClass) {
        extend(superClass, null);
    }

    // "mixins" is an optional array of data types. If passed, the mixins' properties and methods will be replicated and defined on
    // this data type, after the extension, but at a lower priority (any clash is resolved by giving priority to the superClass).
    // Note that mixins have no impact on any "instanceof" operation; this data type will NOT be an instanceof any of the mixin 
    // types. If multiple mixins are passed, the left-most elements are given highest priority (to resolve clashes). 
    global void extend(DataDesc superClass, DataDesc[] mixins) {
        if (sealed) {
            throw new DataDescException('Class ' + typeName + ' has been finalized and cannot be modified');
        }
        if (this.superClass != null) {
            throw new DataDescException('Class ' + typeName + ' already extends ' + this.superClass.typeName + 
                ' and cannot be changed to extend ' + superClass.typeName);
        }
        this.superClass = superClass;
        // once an ClassDesc instance (superClass) has subject to extension, it must be sealed (no future PropDesc changes allowed;
        // ptable / vtable generated and finalized):
        if (!superClass.sealed) {
            superClass.seal();
        }
        
        // import all props from superClass into their local equivalents -- note that this will indeed pull over the inherited ptable 
        // indexes:
        for (String identifierLC : superClass.propsLC.keySet()) {
            PropDesc inheritedProp = superClass.propsLC.get(identifierLC);
            // shallow clone works fine here:
            PropDesc localProp = inheritedProp.clone();
            this.propsLC.put(identifierLC, localProp);
            localProp.host = this; // note we leave the copied-over inheritedHost and pindex as-is
        }
        // import all function groups and their functions from superClass; vtable indexes are copied over:
        for (String identifierLC : superClass.funGroupsLC.keySet()) {
            FunctionGroup inheritedGroup = superClass.funGroupsLC.get(identifierLC);
            FunctionGroup localGroup = new FunctionGroup(this);
            this.funGroupsLC.put(identifierLC, localGroup);
            if (inheritedGroup.dynaFunc != null) {
                localGroup.dynaFunc = inheritedGroup.dynaFunc.clone();
                localGroup.dynaFunc.host = this; // note we leave the copied-over inheritedHost and vindex as-is
            }
            localGroup.funcs = new FunctionDesc[]{};
            for (FunctionDesc inheritedFunc : inheritedGroup.funcs) {
                FunctionDesc localFunc = inheritedFunc.clone();
                localFunc.host = this; // note we leave the copied-over inheritedHost and vindex as-is
                localGroup.funcs.add(localFunc);
            }
        }
        if (mixins != null) {
            for (DataDesc mixClass : mixins) {
                if (!mixClass.sealed) {
                    mixClass.seal();
                }
                for (String identLC : mixClass.propsLC.keySet()) {
                    if (this.propsLC.containsKey(identLC)) {
                        continue;
                    }
                    PropDesc mixProp = mixClass.propsLC.get(identLC);
                    // shallow clone works fine here:
                    PropDesc localProp = mixProp.clone();
                    this.propsLC.put(identLC, localProp);
                    localProp.host = this;
                    localProp.inheritedHost = this; 
                    localProp.pindex = null;
                }
                for (String identLC : mixClass.propsLC.keySet()) {
                    if (this.funGroupsLC.containsKey(identLC)) {
                        continue;
                    }
                    FunctionGroup mixGroup = mixClass.funGroupsLC.get(identLC);
                    FunctionGroup localGroup = new FunctionGroup(this);
                    this.funGroupsLC.put(identLC, localGroup);
                    if (mixGroup.dynaFunc != null) {
                        localGroup.dynaFunc = mixGroup.dynaFunc.clone();
                        localGroup.dynaFunc.host = this;
                        localGroup.dynaFunc.inheritedHost = this;
                    }
                    localGroup.funcs = new FunctionDesc[]{};
                    for (FunctionDesc mixFunc : mixGroup.funcs) {
                        FunctionDesc localFunc = mixFunc.clone();
                        localGroup.funcs.add(localFunc);
                        localFunc.host = this;
                        localFunc.inheritedHost = this;
                        localFunc.vindex = null;
                    }
                }
            }
        }
    }

    public void seal() {
    	System.assert(false, 'TODO: implement');
    }

   	/*
    // Defines a value property. No other property by this identifier name (case insensitive) may have been previously defined or 
    // inherited on this data type, or a DataDefError is thrown.
    DataDesc defineProp(DataDesc typeDesc, String identifier, Boolean writable):
        // TODO:

    // Defines an accessor property (i.e. property has an internal value, getter, and setter). No other property by this identifier 
    // name (case insensitive) may have been previously defined or inherited on this data type, or a DataDefError is thrown.
    DataDesc defineProp(DataDesc typeDesc, String identifier, Accessor getSet, Boolean writable):
        // TODO:

    DataDesc defineFun(DataDesc returnType, String identifier, Method invokable):
        // TODO:

    DataDesc defineFun(String identifier, DynamicReturnType invokable):
        // TODO:

    DataDesc overrideFun(DataDesc returnType, String identifier, Method invokable):
        // TODO:

    // Prerequisites:
    //    1. A property by the name of "identifier" (case-insensitive) must have been previously defined on this data type, or a
    //       DataDefError is thrown.
    //    2. "initVal" must either have the exact same data type as the property (strictly equals), OR it must be Apex null, in 
    //       which case it will be stored as a typed null value (typed to the property's declared type). An initVal of the wrong
    //       type will result in a DataDefError being thrown.
    // Note that initProp can be called at any time without restrictions, even after the data type has been sealed or has already 
    // minted instances! It may also be called for inherited properties.
    DataDesc initProp(String identifier, Value initVal):
        // TODO:

    void seal():
        if (this.sealed)
            return

        this.sealed = true

        // generate ptable:
        Integer plen = superClass == null ? 0 : superClass.ptable.size()
        this.ptable = new PropDesc[plen]
        this.pinits = new Value[plen]
        PropDesc[] newProps = new PropDesc[0];
        if (superClass != null)
            for (PropDesc prop : propsLC.values())
                // inherited prop:
                if (prop.pindex != null)
                    ptable[prop.pindex] = prop
                // new prop:
                else
                    newProps.add(prop)
        for (PropDesc newProp : newProps)
            newProp.pindex = ptable.size()
            ptable.add(newProp)
            newProp.host = this
            newProp.inheritedHost = this
            
        // generate pinits:
        this.pinits = new Value[ptable.size()]
        for (Integer i=0; i < ptable.size(); i++)
            PropDesc prop = ptable[i]
            // TODO: if initVal is non-null, then it must have been vetted for assignment compatibility (with valueOf 
            // conversion as necessary) by PropDesc when the initVal is set:
            pinits[i] = prop.initVal == null ? new NullValue(prop.typeDesc) : prop.initVal

        // generate vtable:
        this.vtable = new FunctionDesc[superClass == null ? 0 : superClass.vtable.size()]
        FunctionDesc[] newFuncs = new FunctionDesc[0]
        if (superClass != null)
            for (FunctionGroup funGroup : funGroupsLC.values())
                if (funGroup.dynaFunc != null)
                    FunctionDesc func = funGroup.dynaFunc
                    if (func.vindex != null)
                        vtable[func.vindex] = func
                    else
                        newFuncs.add(func)
                for (FunctionDesc func : funGroup.funcs)
                    // inherited function signature:
                    if (func.vindex != null)
                        vtable[func.vindex] = func
                    // new function signature:
                    else
                        newFuncs.add(func)

        for (FunctionDesc newFunc : newFuncs)
            newFunc.vindex = vtable.size()
            vtable.add(newFunc)
            newFunc.host = this
            newFunc.inheritedHost = this

    // The integer return value indicates whether a value of compile-time data type "rhsType" can be assigned to a variable 
    // of this data type:
    //    -1 => no compatibility; a compiler TypeError should be thrown to prevent this assignment
    //     0 => perfect compatibility; assignment is allowed with no conversion necessary on values of type "rhsType"
    //     1 => imperfect compatibility; assignment is allowed only after values of type "rhsType" are converted (at runtime) 
    //          via the this.valueOf method (corresponds to the VM "COVAL" [COnvert VALue] instruc)
    // NOTE: Below is a generic implementation, for reference. Subclasses may override to implement special features -- e.g.
    // String can accept Id assignment with conversion; Arrays will need special logic to allow assignment of a typed Array 
    // to a generic Base Object Array.
    virtual Integer assignmentCompatibility(DataDesc rhsType):
        // if lhs and rhs types are strictly equal, then by definition they are perfectly compatible:
        if (this === rhsType)
            return 0
        // lhs base object type has perfect compatibility with any rhs type:
        else if (this.typeEnum == DT_BASE_OBJECT)
            return 0
        // rhs absolute nulls must be converted to a typed null value, hence imperfectly compatible:
        else if (rhsType.typeEnum == DT_ABSOLUTE_NULL)
            return 1
        // check through all rhs superclasses for an ancestor that matches the lhs:
        else 
            while (rhsType = rhsType.superClass) != null)
                if (this === rhsType)
                    return 0
            return -1

    // Used for runtime value conversions. The "rhsValue" value will be converted to a value of this data type, within 
    // limitations of which conversions are allowed -- this method should only be called on rhsValues for which calling 
    // this.assignmentCompatible(rhsValue.typeDesc) returns 1 (i.e. imperfectly compatible) or 0 (perfectly compatible; no
    // conversion required). This default implementation returns the rhs value unmutated if its data type is strictly the 
    // same as this lhs, and disallows conversions for any rhs value of a different data type (throws TypeError). This method
    // will be called by the VM runtime (COVAL instruc) to perform runtime data conversions when needed by assignments, 
    // argument bindings, and operator operand processing.
    virtual Value valueOf(Value rhsValue):
        if (this.typeEnum == DT_BASE_OBJECT || this === rhsValue.typeDesc)
            return rhsValue
        else if (rhsType.typeEnum == DT_ABSOLUTE_NULL)
            // return a new typed-null instance from this lhs type:
            return new NullValue(this)
        else
            // look for common ancestry before we error out:
            DataDesc rhsType = rhsValue.typeDesc
            while (rhsType = rhsType.superClass) != null)
                if (this === rhsType)
                    return rhsValue

            TypeError('Conversion of ' + rhsValue.typeDesc.typeName + ' to ' + this.typeName + ' is not allowed')

////////////
TODO: rework mint methods; no more constructor funcs for now -- should it be "Value[] mintProps()" instead?...
TODO: need "getter" properties, e.g. length. "setter" properties (later on)?
TODO: allow property init values to be defined/redefined at any time, even after a class has been sealed...
TODO: is it possible to have properties/methods on the base Object class, when said props/funcs need to declare types that 
    extend the base Object class?! We would need to:
        1. Declare "empty" slots for props/funcs on the Base Object class. Register Object class in the Environment, but DO NOT 
           seal it yet (special Environment.register bypass). Call these empty slots UnresolvedProp/UnresolvedFunc? Have
           Environment track subclasses that have imported each unresolved prop/func? 
        2. Define all types that are needed to fill the Base Object's "empty" prop/func slots (e.g. String class for toString 
           method, Boolean class for the isNull property). Have them each extend the base Object class, with a special bypass
           to prevent sealing the Base Object class yet -- for now, just the "empty" prop/func slots will be copied over to the
           subclasses. Register the String/Boolean/etc subclasses in the Environment; they may be sealed at this time.
        3. Now the "empty" Object class prop/func slots can be filled with concrete definitions; do so. Clone and write these 
           new props/funcs over into the corresponding "empty" slots in affected subclasses (e.g. String, Boolean)
        4. Seal the Object class
///////////

    virtual Value mintNullInstance():
        assert(sealed)
        return mint()

    // Note: primitive classes like String may override this to NOT mint property values; in those cases prop values can be late-
    // minted on demand via the Value.toPropObject method.
    virtual Value mint():
        assert(sealed)
        Value minted = new Value(this)
        minted.props = pinits.clone()

    // If certain DataDesc subclasses need the ability to mint instances with various arguments (e.g. concrete sObjects may 
    // take an Id value to mint), then it can be implemented here:
    virtual Value mint(Value[] argv):
        assert(sealed)
        if (argv == null || arg.size() == 0)
            return mint()

        Value minted = new Value(this)
        minted.props = pinits.clone()

    */
}

// FunctionDesc, FunctionGroup, PropDesc, DataDescException