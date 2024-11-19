// sObjectDescs need a reference to Environment (for dynamic sObjectType provisioning), but do ClassDesc or other types need this 
// reference too (yes, I think so)?
global class Environ {
    global static Environ env;
    // public variables for easy reference of core types, e.g. String, Number, Object, sObject, Array, etc...
/*
    public ObjectDesc ObjectClass;
    public AbsoluteNullDesc AbsoluteNullClass;
    public IdDesc IdClass;
    public StringDesc StringClass;
    public NumberDesc NumberClass;
    public BooleanDesc BooleanClass;
    public DateDesc DateClass;
    public DateTimeDesc DateTimeClass;
    public sObjectDesc sObjectClass; // abstract sObject base class
*/
//    // TODO: arrays need an element type; should we store generic Object[] Array class here?
//    public ArrayDesc ArrayClass;

    public Value AbsoluteNullValue;
    public Value TrueValue;
    public Value FalseValue;

    Map<String, DataDesc> typesMap = new Map<String, DataDesc>();
    // the global scope object:
    Value scope;

    // TODO:
    // * core types to be created and sealed upon TypeManager instantiation (e.g. base sObjectType, etc)
    // * concrete sObjectTypes provisioned on demand, but Schema.getGlobalDescribe should be used to block custom types of 
    //   clashing names
    // * custom types (custom classes extending Object) to be created by programmer and registered here
    // * should some type names be reserved? what about reserving 1st token in qualified name? (e.g. "Schema")

    // define a new type that's not been previously registered -- note that if newType has not yet been sealed, it will be
    // seal()'d now:
    public void register(DataDesc newType) {
        // register this new type in the map
        DataDesc oldType = typesMap.put(newType.typeName, newType);
        if (oldType != null) {
            typesMap.put(newType.typeName, oldType);
            throw new DataDescException('A data type named "' + newType.typeName +  '" has already been defined'); // what error type for this?
        }
        // types need a back reference to their TypeManager once they're instantiated
        newType.env = this;
    }

    // retrieve a type that's been previously registered -- with special accommodation made for "Schema.My_sObjectType" 
    // types which match Schema.getGlobalDescribe, which are concrete sObjectType that are automatically provisioned/registered 
    // as needed:
    public DataDesc forName(String qualifiedName) {
    	System.assert(false, 'TODO: not implemented');
    	return null;
    }

/*
    // convenience method for retrieving sObject types (concrete or abstract); goes through forName():
    public sObjectDesc getSObjectType(Schema.sObjectType sobjType) {
    	System.assert(false, 'TODO: not implemented');
    	return null;
    }

    // convenience method for retrieving Id types (concrete or abstract); goes through forName():
    public IdDesc getIdType(Schema.sObjectType sobjType) {
    	System.assert(false, 'TODO: not implemented');
    	return null;
    }
*/

    public void setScope(Value scope) {
    	System.assert(false, 'TODO: not implemented');
        // TODO:
    }
}