//RKDEV-13337
public class DescribeHandler {
    public class InvalidParameterException extends Exception {}
    public class NoMatchingSObjectTypeException extends Exception {}
    public class NoMatchingFieldException extends Exception {}
    public class NoMatchingFieldSetException extends Exception {}
    public class DescribeLookupException extends Exception {}

    public static DescribeHandler.NoMatchingSObjectTypeException noMatchingSObjectTypeException(String sObjectType) {
        return new DescribeHandler.NoMatchingSObjectTypeException('No sObjectType found by name "' + sObjectType + '".');
    }
    public static DescribeHandler.NoMatchingFieldException noMatchingFieldException(String sObjectType, String field) {
        return new DescribeHandler.NoMatchingFieldException('No field found by name "' + sObjectType + '.' + field + '".');
    }
    public static DescribeHandler.NoMatchingFieldSetException noMatchingFieldSetException(String sObjectType, String fieldSet) {
        return new DescribeHandler.NoMatchingFieldSetException('No fieldset found by name "' + sObjectType + '.' + fieldSet + '".');
    }

    private static Map<String, Schema.SObjectType> globalDescribe;
    private static Map<String, Schema.ChildRelationship> childRelationships = new Map<String, Schema.ChildRelationship>();

    public static Map<String, Schema.SObjectType> getGlobalDescribe() {
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        return globalDescribe;
    }

    // Will be used by all public interfaces to ensure api name has been normalized, thus all private methods can assume the 
    // name passed in is proper. (rk_hierarchy_node__c -> rkl__rk_hierarchy_node__c)
    public static String getNormalizedSObjectName(String sObjectName) {
        return getGlobalDescribe().get(sObjectName).getDescribe().getName().toLowerCase();
    }

    public static Schema.SObjectType getSObjectType(String sObjectName) {
        return getGlobalDescribe().get(sObjectName);
    }

    public static Schema.DescribeSObjectResult getSObjectDescribe(String sObjectName) {
        return getGlobalDescribe().get(sObjectName).getDescribe();
    }

    public static String getSObjectNamespace(String sObjectName) {
        Schema.DescribeSObjectResult sObjectDescribe = DescribeHandler.getSObjectDescribe(sObjectName);
        String sObjectProperName = sObjectDescribe.getName().toLowerCase();
        Integer namespaceEnd = sObjectProperName.indexOf(sObjectDescribe.getLocalName().toLowerCase());
        if (namespaceEnd > -1) {
            return sObjectProperName.substring(0, namespaceEnd);
        }
        return '';
    }

    public static Schema.SObjectField getSObjectField(String sObjectName, String fieldName) {
        return DescribeHandler.getSObjectDescribe(sObjectName).fields.getMap().get(fieldName);
    }

    public static Schema.SObjectField[] getSObjectFields(String sObjectName) {
        return DescribeHandler.getSObjectDescribe(sObjectName).fields.getMap().values();
    }

    public static String[] getFields(String sObjectName) {
        String[] fields = new String[]{};
        Set<String> fieldsProper = getSObjectDescribe(sObjectName).fields.getMap().keySet();
        for (String fieldName : fieldsProper) {
            fields.add(fieldName.toLowerCase());
        }
        return fields;
    }

    public static Map<String, Schema.DescribeFieldResult> getFieldDescribes(String sObjectName) {
        Map<String, Schema.DescribeFieldResult> fieldDescribes = new Map<String, Schema.DescribeFieldResult>();
        Map<String, Schema.SObjectField> sObjectFields = getGlobalDescribe().get(sObjectName).getDescribe().fields.getMap();
        for (String fieldName : sObjectFields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = sObjectFields.get(fieldName).getDescribe();
            fieldDescribes.put(fieldDescribe.getName().toLowerCase(), fieldDescribe);
        }
        return fieldDescribes;
    }

    public static Schema.DescribeFieldResult getFieldDescribe(String sObjectName, String fieldName) {
        return getGlobalDescribe().get(sObjectName).getDescribe().fields.getMap().get(fieldName.replaceAll('__r$', '__c')).getDescribe();
    }

    public static Boolean isEncrypted(String sObjectName, String fieldName) {
        return DescribeHandler.getFieldDescribe(sObjectName, fieldName).isEncrypted();
    }

    public static Schema.PicklistEntry[] getPicklistValues(String sObjectName, String fieldName) {
        return DescribeHandler.getFieldDescribe(sObjectName, fieldName).getPicklistValues();
    }

    public static String[] getReferenceTo(String sObjectName, String fieldName) {
        String[] referenceTos = new String[]{};
        Schema.SObjectType[] referenceTosRAW = DescribeHandler.getFieldDescribe(sObjectName, fieldName).getReferenceTo();
        for (Schema.SObjectType referenceToRAW : referenceTosRAW) {
            referenceTos.add(String.valueOf(referenceToRAW).toLowerCase());
        }
        return referenceTos;
    }

    public static Map<String, Schema.FieldSet> getFieldSetDescribes(String sObjectName) {
        Map<String, Schema.FieldSet> fieldSets = new Map<String, Schema.FieldSet>();
        Map<String, Schema.FieldSet> fieldSetsRAW = DescribeHandler.getSObjectDescribe(sObjectName).fieldSets.getMap();
        for (String fieldSetName : fieldSetsRAW.keySet()) {
            fieldSets.put(fieldSetName.toLowerCase(), fieldSetsRAW.get(fieldSetName));
        }
        return fieldSets;
    }

    public static Schema.FieldSet getFieldSetDescribe(String sObjectName, String fieldSetName) {
        return DescribeHandler.getFieldSetDescribes(sObjectName).get(fieldSetName.toLowerCase());
    }

    public static Map<String, Schema.FieldSetMember> getFieldSetFields(String sObjectName, String fieldSetName) {
        Map<String, Schema.FieldSetMember> fieldSetFields = new Map<String, Schema.FieldSetMember>();
        Schema.FieldSet fieldSet = DescribeHandler.getFieldSetDescribe(sObjectName, fieldSetName);
        for (Schema.FieldSetMember fieldSetField : fieldSet.getFields()) {
            fieldSetFields.put(fieldSetField.getFieldPath().toLowerCase(), fieldSetField);
        }
        return fieldSetFields;
    }

    public static String[] getOrderedFieldSetFieldNames(String sObjectName, String fieldSetName) {
        Schema.FieldSet fieldSet = DescribeHandler.getFieldSetDescribe(sObjectName, fieldSetName);
        Schema.FieldSetMember[] fieldSetFields = fieldSet.getFields();
        String[] orderedFieldSetPathNames = new String[]{};
        for (Schema.FieldSetMember fieldSetField : fieldSetFields) {
            orderedFieldSetPathNames.add(fieldSetField.getFieldPath().toLowerCase());
        }
        return orderedFieldSetPathNames;
    }

    public static Schema.ChildRelationship getChildRelationship(String sObjectName, String childRelationshipName) {
        String cacheKey = (sObjectName + '.' + childRelationshipName).toLowerCase();
        
        // Attempt to find a Schema.ChildRelationship instance from the cache using <childRelationshipName> as it was passed in
        Schema.ChildRelationship childRel = childRelationships.get(cacheKey);
        
        // Try to retrieve a Schema.ChildRelationship instance from the cache with __r attached
        if (childRel == null) {
            childRel = childRelationships.get(cacheKey + '__r');
        }

        // Finally, if no match could be found in the cache, search through the describe info to find the right Schema.ChildRelationship
        if (childRel == null) {
            Schema.ChildRelationship[] childRelsOnObject = DescribeHandler.getSObjectDescribe(sObjectName).getChildRelationships();
            for (Schema.ChildRelationship childRelOnObject : childRelsOnObject) {
                if (childRelOnObject.getRelationshipName() != null) {
                    if (childRelOnObject.getRelationshipName().equalsIgnoreCase(childRelationshipName)) {
                        childRel = childRelOnObject;
                        childRelationships.put(cacheKey, childRel);
                    } else if (childRelOnObject.getRelationshipName().equalsIgnoreCase(childRelationshipName + '__r')) {
                        childRel = childRelOnObject;
                        childRelationships.put(cacheKey + '__r', childRel);
                    }
                }
            }
        }
        return childRel;
    }

    // Assumes the first match is intended in the case of polymorphic relationships
    public static Schema.ChildRelationship getChildRelationshipFromRelationship(String childSObjectName, String relationshipField) {
        String cacheKey = 'fromchild.' + (childSObjectName + '.' + relationshipField).toLowerCase();

        Schema.ChildRelationship childRel = childRelationships.get(cacheKey);

        if (childRel == null) {
            for (String referenceTo : DescribeHandler.getReferenceTo(childSObjectName, relationshipField)) {
                Schema.ChildRelationship[] childRelsOnParent = DescribeHandler.getSObjectDescribe(referenceTo).getChildRelationships();
                for (Schema.ChildRelationship childRelOnParent : childRelsOnParent) {
                    if (String.valueOf(childRelOnParent.getChildSObject()).equalsIgnoreCase(childSObjectName) &&
                        String.valueOf(childRelOnParent.getField()).equalsIgnoreCase(relationshipField)) {
                        childRelationships.put(cacheKey, childRelOnParent);
                        childRelationships.put((referenceTo + '.' + String.valueOf(childRelOnParent.getRelationshipName())).toLowerCase(), childRelOnParent);
                    }
                }
            }
        }

        return childRel;
    }
}