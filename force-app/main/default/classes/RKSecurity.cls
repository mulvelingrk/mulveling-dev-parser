/*
 * Mike Ulveling
 * 
 * RKDEV-29932
 */
public with sharing class RKSecurity {

    public static final Integer BYPASS_FLS_CRUD           = -1;
    public static final Integer FILTER_FLS_CRUD           =  0;
    public static final Integer FILTER_FLS_THROW_CRUD     =  1;
    //public static final Integer ALL_OR_NONE_TRANSACTIONAL =  2;
    public static final Integer ALL_OR_NONE               =  2; //3;

    private static Integer SecurityMode = FILTER_FLS_THROW_CRUD;
    private static Boolean SecurityModeTransactional = false;

    private static Map<Schema.sObjectType, Integer> CRUDMissMap;
    private static Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>> FLSMissMap;

    public static RKShare.SecurityModel SafeSharingModel = RKShare.SafeSharing();
    public static RKShare.SecurityModel SystemSharingModel = RKShare.SystemSharing();

    public static SOQLParser.SOQL soql(String query) {
        return new SOQLParser.SOQL(query)
            // Uses a LocalReBindPool, e.g. Id[] ids0, ids1, ids2:
            .reBindPool(RKShare.mintReBindPool());
    }

    public static void transactionalThrow() {
        SecurityModeTransactional = true;
    }

    public static void setSecurityMode(Integer newMode) {
        System.assert(newMode >= BYPASS_FLS_CRUD && newMode <= ALL_OR_NONE, 'Invalid security mode specified [' + newMode + ']');
        SecurityMode = newMode;
        resetSecurityLog(false);
    }

    public static void setSafeSharing(RKShare.SecurityModel securityModel) {
        SafeSharingModel = securityModel;
    }

    public static void setSystemSharing(RKShare.SecurityModel securityModel) {
        SystemSharingModel = securityModel;
    }

    // Forces all subsequent RKShare safe operations to execute in System mode for both CRUD/FLS and record sharing.
    // Returns a Savepoint, from right before this override, that can restore the prior settings and mode of operation 
    // via an RKShare.restore() call that is passed that Savepoint:
    public static SecuritySavepoint startSystemMode() {
        SecuritySavepoint sp = new SecuritySavepoint();
        SecurityMode = BYPASS_FLS_CRUD;
        SafeSharingModel = SystemSharingModel;
        return sp;
    }

    // Works like startSystemMode(), but only acts like System mode with regard to record sharing, not CRUD/FLS:
    public static SecuritySavepoint startSystemSharingMode() {
        SecuritySavepoint sp = new SecuritySavepoint();
        SafeSharingModel = SystemSharingModel;
        return sp;
    }

    public static void restore(SecuritySavepoint state) {
        SecurityMode = state.secMode;
        SecurityModeTransactional = state.transactional;
        CRUDMissMap = state.crudMiss;
        FLSMissMap = state.flsMiss;
        SafeSharingModel = state.safeShare;
        SystemSharingModel = state.systemShare;
    }

    public class SecuritySavepoint {
        Integer secMode;
        Boolean transactional;
        Map<Schema.sObjectType, Integer> crudMiss;
        Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>> flsMiss;
        RKShare.SecurityModel safeShare;
        RKShare.SecurityModel systemShare;

        public SecuritySavepoint() {
            this.secMode = SecurityMode;
            this.transactional = SecurityModeTransactional == true;
            this.crudMiss = CRUDMissMap != null ? CRUDMissMap : new Map<Schema.sObjectType, Integer>();
            this.flsMiss = FLSMissMap != null ? FLSMissMap : new Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>>();
            this.safeShare = SafeSharingModel != null ? SafeSharingModel : RKShare.SafeSharing();
            this.systemShare = SystemSharingModel != null ? SystemSharingModel : RKShare.SystemSharing();
        }
    }

    public static void resetSecurityLog() {
        resetSecurityLog(false);
    }

    public static void resetSecurityLog(Boolean internalCall) { //Raghil: Changed from private to public
        //if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityMode == ALL_OR_NONE_TRANSACTIONAL) {
        if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityModeTransactional == true) {
            return;
        }
        CRUDMissMap = new Map<Schema.sObjectType, Integer>();
        FLSMissMap = new Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>>();
    }

    static {
        if (Test.isRunningTest()) {
            // TODO:
            setSecurityMode(ALL_OR_NONE);
        } else {
/* mulveling-dev
            RKQF_Settings__c sett = RKQF_Settings__c.getInstance();
            if (sett != null && sett.Security_Mode__c != null) {
                Integer iMode = sett.Security_Mode__c.intValue();
                if (sett.Security_Mode__c >= BYPASS_FLS_CRUD && sett.Security_Mode__c <= ALL_OR_NONE) {
                    setSecurityMode(iMode);
                }
            }
*/
        }
        resetSecurityLog(false);
    }

    public final static Integer ACCESS_READ = 1; //Raghil: Changed from private to public
    public final static Integer ACCESS_CREATE = 2; //Raghil: Changed from private to public
    public final static Integer ACCESS_UPDATE = 4; //Raghil: Changed from private to public
    public final static Integer ACCESS_DELETE = 8; //Raghil: Changed from private to public

    @TestVisible
    public static void logSecurityMiss(Schema.sObjectType sobjType, Integer accessType) { //Raghil: Changed from private to public
        if (SecurityMode <= FILTER_FLS_CRUD) {
            return;
        }
        Integer accessBits = CRUDMissMap.get(sobjType);
        if (accessBits == null) {
            accessBits = 0;
        }
        CRUDMissMap.put(sobjType, accessBits | accessType);
    }

    @TestVisible
    public static void logSecurityMiss(Schema.sObjectType sobjType, Schema.sObjectField field, Integer accessType) { //Raghil: Changed from private to public
        if (SecurityMode <= FILTER_FLS_THROW_CRUD) { //FILTER_FLS_CRUD) {
            return;
        }
        Map<Schema.sObjectField, Integer> fieldMap = FLSMissMap.get(sobjType);
        if (fieldMap == null) {
            FLSMissMap.put(sobjType, fieldMap = new Map<Schema.sObjectField, Integer>());
        }
        Integer accessBits = fieldMap.get(field);
        if (accessBits == null) {
            accessBits = 0;
        }
        fieldMap.put(field, accessBits | accessType);
    }

    public static void throwSecurityViolations() {
        throwSecurityViolations(false);
    }

    public static void throwSecurityViolations(Boolean internalCall) { //Raghil: Changed from private to public
        //if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityMode == ALL_OR_NONE_TRANSACTIONAL) {
        if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityModeTransactional == true) {
            return;
        }
        String[] parts = new String[]{};
        String[] crud = new String[]{};
        for (Schema.sObjectType sobjType : CRUDMissMap.keySet()) {
            Integer accessBits = CRUDMissMap.get(sobjType);
            crud.add(sobjType + '[' + printAccess(accessBits) + ']');
        }
        if (crud.size() > 0) {
            parts.add('Missing access for Object' + (crud.size() == 1 ? '' : 's') + ': ' + 
                String.join(crud, ', '));
        }
        Integer numFLS =  0;
        for (Schema.sObjectType sobjType : FLSMissMap.keySet()) {
            Map<Schema.sObjectField, Integer> fieldMap = FLSMissMap.get(sobjType);
            String[] fls_obj = new String[]{};
            for (Schema.sObjectField field : fieldMap.keySet()) {
                Integer accessBits = fieldMap.get(field);
                fls_obj.add(field + '[' + printAccess(accessBits) + ']');
                numFLS++;
            }
            parts.add('Missing access for ' + sobjType + ' field' + (fls_obj.size() == 1 ? '' : 's') + ': ' + 
                String.join(fls_obj, ', '));
        }
        if (parts.size() > 0) {
            String msg = String.join(parts, '. ');
            //AuraHandledException e = new AuraHandledException(msg);
            //e.setMessage(msg);
            SOQLContext.AccessException e = new SOQLContext.AccessException(msg);
            e.setMessage(msg);
            e.numCRUD = crud.size();
            e.numFLS = numFLS;
            throw e;
        }
    }

    @TestVisible
    static String printAccess(Integer accessBits) {
        String[] types = new String[]{};
        if ((accessBits & ACCESS_CREATE) > 0) {
            types.add('Create');
        }
        if ((accessBits & ACCESS_READ) > 0) {
            types.add('Read');
        }
        if ((accessBits & ACCESS_UPDATE) > 0) {
            types.add('Update');
        }
        if ((accessBits & ACCESS_DELETE) > 0) {
            types.add('Delete');
        }
        return String.join(types, ', ');
    }

    // By default the filterSObject methods will "mirror" field entities from this same package under their qualified 
    // and unqualified name keys, e.g. rkqf__Foo_Field__c's value gets written under both 'rkqf__Foo_Field__c' and 
    // 'Foo_Field__c' keys in the resultant generic map. However, same-package parent and child relationship entities 
    // (sObject and List<sObject> values, respectively) are NOT mirrored; by default they are only written under their 
    // unqualified API names. This is to prevent a potentially exponential increase in the serialized map size. This
    // space-saving behavior can be overridden by setting this FilterSObject_NSMirrorChildAndParentRels flag to `true`:

    // JLB - Deprecated in favor of more efficient data mirroring technique (props to Mike for suggestion!)
    //public static Boolean FilterSObject_NSMirrorChildAndParentRels = false;

    /* 
        JLB - Added to facilitate new data mirroring technique.
        New technique will mirror parent and child relationship entities under both their qualified and unqualified
        API names. However, it will not map nested parent and child relationship entities under both API names. Nested
        entities are mapped according to the mapping technique used by the parent context (Qualified vs Unqualified).
        
        For example, suppose you're mapping a nested relationship field with the following fully qualified field path: rkqf__Obj1__r.rkqf__Obj2__r
        The old mapping technique would have resulted in the following object structure:
        {
            rkqf__Obj1__r: {
                rkqf__Obj2__r: {
                    ...
                },
                Obj2__r: {
                    ...
                }
            },
            Obj1__r: {
                rkqf__Obj2__r: {
                    ...
                },
                Obj2__r: {
                    ...
                }
            }
        }

        The new approach maps this data as follows:
        {
            rkqf__Obj1__r: {
                rkqf__Obj2__r: {
                    ...
                }
            },
            Obj1__r: {
                Obj2__r: {
                    ...
                }
            }
        }
    */
    private enum DataMirrorMode {
        Qualified,
        UnQualified,
        BOTH
    }

    // primitive bind types:
    public static final Integer BIND_DYNAMIC = 0;
    public static final Integer BIND_PKG_STATIC = 1;
    public static final Integer BIND_ORG_STATIC = 2;
    // compound bind types below here:
    public static final Integer BIND_PGK_STATIC_THEN_DYNAMIC = 3;
    public static final Integer BIND_ORG_STATIC_THEN_DYNAMIC = 4;
    public static final Integer BIND_DYNAMIC_THEN_PKG_STATIC = 5;
    public static final Integer BIND_DYNAMIC_THEN_ORG_STATIC = 6;

    private static final List<Integer[]> BindStrategyStack = new List<Integer[]>{ new Integer[]{ BIND_PKG_STATIC, BIND_DYNAMIC } };

    @TestVisible
    private static Integer[] resolvePrimitiveBindTypes(Integer bindType) {
        if (bindType == BIND_PGK_STATIC_THEN_DYNAMIC) {
            return new Integer[]{ BIND_PKG_STATIC, BIND_DYNAMIC };
        } else if (bindType == BIND_ORG_STATIC_THEN_DYNAMIC) {
            return new Integer[]{ BIND_ORG_STATIC, BIND_DYNAMIC };
        } else if (bindType == BIND_DYNAMIC_THEN_PKG_STATIC) {
            return new Integer[]{ BIND_DYNAMIC, BIND_PKG_STATIC };
        } else if (bindType == BIND_DYNAMIC_THEN_ORG_STATIC) {
            return new Integer[]{ BIND_DYNAMIC, BIND_ORG_STATIC };
        } else if (bindType != null && bindType >= 0 && bindType <= 2) {
            return new Integer[]{ bindType };
        } else {
            bindTypeInvalidErr(bindType);
            return null; // unreachable
        }
    }
    @TestVisible
    static void bindTypeInvalidErr(Integer badBindType) {
        throw new AuraHandledException('Binding type ' + badBindType + ' is invalid');
    }

    public static void startBinding(Integer bindingType) {
        BindStrategyStack.add(resolvePrimitiveBindTypes(bindingType));
    }

    public static void revertBinding() {
        if (BindStrategyStack.size() > 1) {
            BindStrategyStack.remove(BindStrategyStack.size() - 1);
        }
    }

    public static void revertToDefaultBinding() {
        while (BindStrategyStack.size() > 1) {
            BindStrategyStack.remove(1);
        }
    }

    private static String PackageNamespace;
    private static String OrgNamespace;
    private static Pattern ObjFieldPatt = Pattern.compile('(?i)^(?:([a-z][a-z0-9]*)__)?([a-z](?:[a-z0-9]|_(?!_))++(?:__c|__r|__latitude__s|__longitude__s))$');
    private static Pattern NamespaceQualifiedObjFieldPatt = Pattern.compile('(?i)^([a-z][a-z0-9]++)__([a-z](?:[a-z0-9]|_(?!_))++(?:__c|__r|__latitude__s|__longitude__s))$');
    private static Pattern NamespaceQualifiedFieldSetOrRecordTypePatt = Pattern.compile('(?i)^([a-z][a-z0-9]++)__([a-z](?:[a-z0-9]|_(?!_|$))++)$');
    // pattern for crudely macthing anything that "looks like" and API name path, including some invalid ones (e.g. valid: Foo__r.Bar__c; invalid: __Foo__c, 0Foo__c)
    public static Pattern CrudeIdentifyApiPathPatt = Pattern.compile('(?i)[a-z_0-9]++(?:\\.[a-z_0-9]++)*+');

    public static String getPackageNamespace() {
        if (PackageNamespace == null) {

/* mulveling-dev
            String qualifiedName = '' + Schema.Template_Question__c.sObjectType;
*/
            //String qualifiedName = '' + Schema.Audio_Component__c.sObjectType;

            // TODO:
            //String qualifiedName = '' + Schema.RKUX_Mock_Object__c.sObjectType;
            String qualifiedName = '' + Schema.System_Component__c.sObjectType;

            Matcher m = NamespaceQualifiedObjFieldPatt.matcher(qualifiedName);
            if (m.matches()) {
                PackageNamespace = m.group(1);
                if (String.isBlank(PackageNamespace)) {
                    PackageNamespace = 'c';
                }
            } else {
                PackageNamespace = 'c';
            }
        }
        return PackageNamespace == 'c' ? null : PackageNamespace;
    }

    public static String getOrgNamespace() {
        if (OrgNamespace == null) {
            OrgNamespace = [ SELECT NamespacePrefix FROM Organization LIMIT 1].NamespacePrefix;
            if (String.isBlank(OrgNamespace)) {
                OrgNamespace = 'c';
            }
        }
        return OrgNamespace == 'c' ? null : OrgNamespace;
    }

    /*
    // Removes the namespace portion of a fully qualified API name that points to a 
    // managed object within this package, if that is what is supplied to the method.
    // Otherwise, it simply returns what was passed. Names that refer to external package
    // entities, or local org entities are left unaffected.
    public static String stripThisNamespace(String entityAPIName) {
        Matcher m = NamespaceQualifiedObjFieldPatt.matcher(entityAPIName);
        if (m.matches()) {
            String entityNamespace = m.group(1);

            // Only necessary to strip the namespace if the referenced entity exists within the package.
            // Stripping the namespace from external references would break things downstream
            if (String.isNotBlank(entityNamespace) && entityNamespace == getPackageNamespace()) {
                return m.group(2);
            }
        } else {
            // Probably should throw an exception here, since an invalid API name would have to have been passed to reach this point.
        }

        return entityAPIName;
    }
    */

    // TODO: Deprecated; instead, use startSystemMode() or startSystemSharingMode() with a finally { restore(Savepoint) }...
    // Call this method immediately before a safeUpdate/safeDelete call, in the rare instance where your need to 
    // perform DML with Apex record sharing turned OFF (e.g. perform an update on a record for which the context 
    // user does not have "Edit" sharing permission). You must be able to justify the use of this bypass, and 
    // comment it in your code. One call is good for one bypass; RKSecurity will automatically revert back to 
    // standard "with sharing" behavior immediately upon completion of your bypassed safeInsert/safeUpdate/
    // safeDelete call, whether is was succeeded or not:
    public static void sharingOFF() {
        Exec.systemModeOneTime = true;
    }

    // TODO: Deprecated; instead, use startSystemMode() or startSystemSharingMode() with a finally { restore(Savepoint) }...
    public static void sharingOffOneTime() {
        Exec.systemModeOneTime = true;
    }

    public class Deserializer {
        String sobjJSON;
        Object sobjUntyped;
        public Boolean plural {get; private set;}

        Schema.sObjectType defaultType;
        @testVisible
        DeserObj[] objs;

        private Deserializer(Schema.sObjectType defaultType) {
            this.objs = new DeserObj[]{};
            this.defaultType = defaultType;
            this.plural = false;
        }

        public sObject[] doSafeInsert() {
            sObject[] results = new sObject[]{};
            sObject[] dmls = new sObject[]{};

            // CRUD/FLS security violations:
            resetSecurityLog(true);
            for (DeserObj obj : this.objs) {
                sObject sobj;
                if (obj.checkInsertable()) {
                    dmls.add(sobj = obj.toSObject(CreateChecker));
                }
                results.add(sobj);
            }
            // CRUD/FLS security violations:
            throwSecurityViolations(true);

            if (dmls.size() > 0) {
                try {
                    // TODO: Should we extend the "one time system sharing mode" bypass to here? Extend it 
                    // further to toSafeReadables() / filterSObject() / SOQLParser.SOQL.safeQuery calls?
                    (Exec.systemModeOneTime == true ? SystemSharingModel : SafeSharingModel).doInsert(dmls);
                } catch (DMLException err) {
                    handleDMLError(err, 'Insert');
                } catch (RKShare.AccessException ax) { 
                    throwAccessViolation(ax);
                } finally {
                    Exec.systemModeOneTime = false;
                    resetDMLTransients();
                }
            }
            return results;
        }

        /* added debug logs : Shruthishree */
        public sObject[] doSafeUpdate() {
            sObject[] results = new sObject[]{};
            sObject[] dmls = new sObject[]{};
            // CRUD/FLS security violations:
            resetSecurityLog(true);
            for (DeserObj obj : this.objs) {
                sObject sobj;
                if (obj.checkUpdateable()) {
                    dmls.add(sobj = obj.toSObject(UpdateChecker));
                }
                results.add(sobj);
            }
            // CRUD/FLS security violations:
            throwSecurityViolations(true);

            if (dmls.size() > 0) {
                try {
                    //update dmls;
                    // TODO: Should we extend the "one time system sharing mode" bypass to here? Extend it 
                    // further to toSafeReadables() / filterSObject() / SOQLParser.SOQL.safeQuery calls?
                    (Exec.systemModeOneTime == true ? SystemSharingModel : SafeSharingModel).doUpdate(dmls);
                } catch (DMLException err) {
                    handleDMLError(err, 'Update');
                } catch (RKShare.AccessException ax) {
                    throwAccessViolation(ax);
                } finally {
                    Exec.systemModeOneTime = false;
                    resetDMLTransients();
                }
            }
            return results;
        }

        /*
        public sObject[] doSafeUpsert() {
            sObject[] results = new sObject[]{};
            sObject[] dmls = new sObject[]{};
            for (DeserObj obj : this.objs) {
                sObject sobj;
                if (obj.checkUpsertable()) {
                    dmls.add(sobj = obj.toSObject(obj.recordId != null ? 
                        (CheckPermissions) UpdateChecker : (CheckPermissions) CreateChecker));
                }
                results.add(sobj);
            }
            if (dmls.size() > 0) {
                //upsert dmls;
                try {
                    upsert dmls;
                } catch (DMLException err) {
                    handleDMLError(err, 'Upsert');
                } finally {
                    resetDMLTransients();
                }
            }
            return results;
        }
        */

        public sObject toSafeReadable() {
            sObject[] desers = new sObject[]{};
            Set<Id> scope = new Set<Id>();

            // CRUD/FLS security violations:
            resetSecurityLog(true);
            for (DeserObj obj : this.objs) {
                if (obj.checkReadable()) {
                    sObject deser = obj.toSObject(ReadChecker);
                    desers.add(deser);
                    scope.add(deser.Id);
                } else {
                    desers.add(null);
                }
            }
            // CRUD/FLS security violations:
            throwSecurityViolations(true);

            if (desers.isEmpty()) {
                deserErr('Single Readable cannot be returned from an empty set: \'' + sobjJSON + '\'');
            } else if (desers.size() > 1) {
                deserErr('Single Readable cannot be returned because the set holds ' + desers.size() + ' elements');
            }

            final Id readId = desers[0].Id;
            if (readId != null) {
                Set<Id> filtered = RKShare.SafeSharing().filterReadable(new Set<Id>{ readId });
                // Access exception:
                if (!filtered.contains(readId)) {
                    //deserErr('Readable cannot be returned because of record security');
                    throwAccessViolation(readId);
                }
            }
            return desers[0];
        }

        public sObject[] toSystemReadables() {
            sObject[] results = new sObject[]{};
            for (DeserObj obj : this.objs) {
                results.add(obj.toSObject(null));
            }
            return results;
        }

        public sObject toSystemReadable() {
            sObject[] results = new sObject[]{};
            for (DeserObj obj : this.objs) {
                results.add(obj.toSObject(null));
            }
            if (results.isEmpty()) {
                deserErr('Single Readable cannot be returned from an empty set: \'' + sobjJSON + '\'');
            } else if (results.size() > 1) {
                deserErr('Single Readable cannot be returned because the set holds ' + results.size() + ' elements');
            }
            return results[0];
        }
    }

    public static Deserializer deserialize(Object sobjJSONOrUntyped) {
        return deserialize(sobjJSONOrUntyped, null);
    }

    public static Deserializer deserialize(Object sobjJSONOrUntyped, Schema.sObjectType defaultType) {
        Deserializer deser = new Deserializer(defaultType);
        if (sobjJSONOrUntyped == null || sobjJSONOrUntyped == 'null') {
            return deser;
        } else if (sobjJSONOrUntyped instanceof String) {
            deser.sobjJSON = (String) sobjJSONOrUntyped;
            try {
                deser.sobjUntyped = JSON.deserializeUntyped(deser.sobjJSON);
            } catch (JSONException e) {
                deserErr('Input cannot be parsed as JSON: ' + e.getMessage());
            }
        } else if (sobjJSONOrUntyped instanceof Object[] || sobjJSONOrUntyped instanceof Map<String, Object>) {
            deser.sobjUntyped = sobjJSONOrUntyped;
        } else {
            deserErr('Input is neither an sObject map structure or an Array of sObjects [' + jsonType(deser.sobjUntyped) + ']');
        }
        List<Map<String, Object>> sobjRaws = new List<Map<String, Object>>();
        if (deser.sobjUntyped instanceof Map<String, Object>) {
            sobjRaws = new List<Map<String, Object>> { (Map<String, Object>) deser.sobjUntyped };
        } else if (deser.sobjUntyped instanceof Object[]) {
            deser.plural = true;
            sobjRaws = new List<Map<String, Object>>();
            Object[] inList = (Object[]) deser.sobjUntyped;
            for (Integer i=0; i < inList.size(); i++) {
                Object elmt = inList[i];
                if (elmt instanceof Map<String, Object>) {
                    sobjRaws.add((Map<String, Object>) elmt);
                } else {
                    deserErr('Input element at index ' + i + ' is not an sObject map structure [' + jsonType(elmt) + ']');
                }
            } 
        } else {
            deserErr('Input is neither an sObject map structure or an Array of sObjects [' + jsonType(deser.sobjUntyped) + ']');
        }

        for (Integer i=0; i < sobjRaws.size(); i++) {
            Map<String, Object> raw = sobjRaws[i];
            DeserObj obj = new DeserObj(deser, deser.plural ? i : null);
            deser.objs.add(obj);
            // 1st-pass scan for sobjectType or Id properties (case-insensitive):
            for (String srcKey : raw.keySet().clone()) {
                if (srcKey == 'Id') {
                    new RecordIdProp(obj, srcKey, raw.remove(srcKey));
                } else if (srcKey == 'sobjectType') {
                    new sObjectTypeProp(obj, srcKey, raw.remove(srcKey));
                }
            }
            if (obj.sobjType == null) {
                if (deser.defaultType == null) {
                    deserErr(obj, null, 
                        'Input sObject does not specify an sObjectType, and no Deserializer default sObjectType has been defined');
                }
                obj.sobjType = deser.defaultType;
            }

            // 2nd pass we compile all other properties:
            for (String srcKey : raw.keySet()) {
                if (srcKey == 'RecordTypeId') {
                    new RecordTypeProp(obj, srcKey, raw.get(srcKey));
                } else {
/* mulveling-dev
                    String fieldName = RKMock.resolveMockKey(obj.sobjType, srcKey);
                    Schema.sObjectField field;
                    if (fieldName != null) {
                        field = resolveField(obj.sobjType, fieldName);
                        if (field == null) {
                            deserErr(obj, srcKey, 'Property is resolved by RKMock to ' + obj.sobjType + '.' + 
                                fieldName + ', but this field does not exist');
                        }
                        // mock key/value pairs are assigned the highest priority 1:
                        obj.setField(srcKey, field, raw.get(srcKey), 1);
                    } else {
*/
                    Schema.sObjectField field = resolveField(obj.sobjType, srcKey);
                    if (field != null) {
                        Integer priority = 2;
                        String pkg = getPackageNamespace();
                        if (pkg != null) {
                            Matcher m = NamespaceQualifiedObjFieldPatt.matcher(srcKey);
                            // if the source key was namespace-qualified to this package's namespace, then we de-prioritize 
                            // it relative to an unqualified field name that resolves to the same package-field:
                            if (m.matches() && m.group(1) == pkg) {
                                priority = 3;
                            }
                        }
                        obj.setField(srcKey, field, raw.get(srcKey), priority);
                    }
                        // !! note we ignore properties that cannot be resolved to a field, keeping in line with the Lightning-
                        // to-Apex sObject deserializer...
/* mulveling-dev
                    }
*/
                }
            }
        }

        return deser;
    }

    public class DeserObj {
        Deserializer deser;
        public Integer srcIndex {get; private set;}
        Schema.sObjectType sobjType;
        Id recordId;
        Id recordTypeId;
        SObjectTypeProp sobjTypeProp;
        RecordIdProp recordIdProp;
        RecordTypeProp recordTypeProp;
        // map of lower-case'd destKey to prop:
        Map<String, FieldProp> fieldProps = new Map<String, FieldProp>();

        public Boolean failedCRUD {get; private set;}
        public sObject sobj {get; private set;}

        @TestVisible
        DeserObj(Deserializer deser, Integer srcIndex) {
            this.deser = deser;
            this.srcIndex = srcIndex;
            this.failedCRUD = false;
        }

        void setSObjectType(SObjectTypeProp prop) {
            if (this.sobjTypeProp != null) {
                deserErr(prop, 'sobjectType cannot be specified multiple times in different letter-casing [' + this.sobjTypeProp.srcKey + 
                    ', ' + prop.srcKey + ']');
            }
            this.sobjTypeProp = prop;
            Schema.sObjectType newType = (Schema.sObjectType) prop.destVal();
            if (newType == null) {
                deserErr(prop, 'sobjectType cannot be set to null');
            }
            if (recordIdProp != null && this.sobjType != null && this.sobjType != newType) {
                deserErr(prop, 'sobjectType ' +  newType + ' clashes with Record Id type ' + this.sobjType);
            }
            this.sobjType = newType;
        }

        void setRecordId(RecordIdProp prop) {
            if (this.recordIdProp != null) {
                deserErr(prop, 'Record Id cannot be specified multiple times in different letter-casing [' + 
                    recordIdProp.srcKey + ', ' + prop.srcKey+ ']');
            }
            this.recordIdProp = prop;
            this.recordId = (Id) prop.destVal();
            if (this.sobjTypeProp != null && this.recordId != null) {
                if (this.recordId.getSObjectType() != this.sobjType) {
                    deserErr(prop, 'Record Id type ' + this.recordId.getSObjectType() + ' clashes with sobjectType ' + sobjType);
                }
            }
            if (this.recordId != null) {
                this.sobjType = this.recordId.getSObjectType();
            }
        }

        void setRecordType(RecordTypeProp prop) {
            if (this.recordTypeProp != null) {
                deserErr(prop, 'Record Type cannot be specified multiple times in different letter-casing [' + 
                    recordTypeProp.srcKey + ', ' + prop.srcKey+ ']');
            }
            this.recordTypeProp = prop;
            this.recordTypeId = (Id) prop.destVal();
        }

        void setField(String srcKey, Schema.sObjectField field, Object srcVal, Integer priority) {
            Schema.DescribeFieldResult fieldDesc = field.getDescribe();
            Schema.SOAPType soap = fieldDesc.getSoapType();
            if (soap == Schema.SOAPType.STRING) {
                new StringProp(this, srcKey, fieldDesc, priority, srcVal);
            } else if (soap == Schema.SOAPType.BOOLEAN) {
                new BooleanProp(this, srcKey, fieldDesc, priority, srcVal);
            } else if (soap == Schema.SOAPType.DOUBLE || soap == Schema.SOAPType.INTEGER) {
                new NumberProp(this, srcKey, fieldDesc, priority, srcVal);
            } else if (soap == Schema.SOAPType.DATE) {
                new DateProp(this, srcKey, fieldDesc, priority, srcVal);
            } else {
                Schema.DisplayType type = fieldDesc.getType();
                if (type == Schema.DisplayType.Reference) {
                    new LookupIdProp(this, srcKey, fieldDesc, priority, srcVal);
                } else {
                    // TODO: we may need to add support for additional field types, e.g. Base64...
                    deserErr(this, srcKey, 'Unsupported field type ' + type.name());
                }
            }
        }

/*
        Boolean checkUpsertable() {
            return this.recordId == null && CreateChecker.checkCRUD(this.sobjType) || this.recordId != null && UpdateChecker.checkCRUD(this.sobjType);
        }
*/

        Boolean checkInsertable() {
            if (this.recordId != null) {
                deserErr(this.recordIdProp, 'sObject with Id property cannot be inserted');
            }
            return CreateChecker.checkCRUD(this.sobjType);
        }

        Boolean checkUpdateable() {
            if (this.recordId == null) {
                deserErr(this, 'Id', 'sObject without Id property cannot be updated');
            }
            return UpdateChecker.checkCRUD(this.sobjType);
        }

        @testVisible
        Boolean checkReadable() {
            return ReadChecker.checkCRUD(this.sobjType);
        }

        sObject toSObject(CheckPermissions checkPerms) {
            //this.sobj = this.recordId != null ? sobjType.newSObject(this.recordId) : sobjType.newSObject();
            this.sobj = sobjType.newSObject();
            if (this.recordTypeId != null) {
                sobj.put('RecordTypeId', recordTypeId);
            }

            // JLB - Workaround for master-detail field bug. Platform is attempting to replicate DB-level
            // insert vs update field-validation logic at runtime on SObject.put. Of course, they only
            // did this in a half-baked form and failed to maintain it as new layers of DB validation
            // were added. In this case specifically, its related to master-detail fields with "reparentable"
            // enabled. SObject.put doesn't respect this at all, and immediately throws an exception if you
            // attempt to call "put" on an SObject that already has the "Id" field populated (lazy way of
            // discerning between insert vs update). The workaround? Only populate the "Id" field once all
            // other fields have been populated so it thinks the master-detail population is happening during
            // insert.
            FieldProp idFieldProp;
            for (FieldProp prop : fieldProps.values()) {
                if (prop.destKey != null) {
                    if (prop.destKey != 'Id') {
                        if (!prop.fieldDesc.isAutoNumber() && !prop.fieldDesc.isCalculated()) {
                            Boolean ok = checkPerms == null || checkPerms.checkFLS(this.sobjType, prop.destKey);
                            if (ok) {
                                Object destVal = prop.destVal();
                                if (destVal == null && !prop.fieldDesc.isNillable()) {
                                    deserErr(prop, 'Field value is not Nillable');
                                } else {
                                    sobj.put(prop.destKey, prop.destVal());
                                }
                            }
                        }
                    } else {
                        idFieldProp = prop;
                    }
                }
            }

            // Populate Id field last to prevent faulty "edit" validation from firing
            if (idFieldProp != null) {
                sobj.put(idFieldProp.destKey, idFieldProp.destVal());
            } else if (this.recordId != null) {
                sobj.put('Id', this.recordId);
            }

            return this.sobj;
        }
    }

    abstract class DeserProp {
        DeserObj obj;
        String srcKey;
        String destKey;
        Object srcVal;

        DeserProp(DeserObj obj, String srcKey, Object srcVal) {
            this.obj = obj;
            this.srcKey = srcKey;
            this.srcVal = srcVal;
        }

        virtual Object destVal() {
            return srcVal;
        }
    }

    class RecordIdProp extends DeserProp {
        RecordIdProp(DeserObj obj, String srcKey, Object srcVal) {
            super(obj, srcKey, srcVal);
            obj.setRecordId(this);
        }

        override Object destVal() {
            if (srcVal instanceof String) {
                try {
                    return Id.valueOf((String) srcVal);
                } catch ( Exception e) {
                    deserErr(this, 'Record Id has invalid format [' + String.valueOf(srcVal) + ']');
                }
            } else if (srcVal != null) {
                deserErr(this, 'Record Id must be string; got ' + jsonType(srcVal));
            }
            return null;
        }
    }

    class SObjectTypeProp extends DeserProp {
        SObjectTypeProp(DeserObj obj, String srcKey, Object srcVal) {
            super(obj, srcKey, srcVal);
            obj.setSObjectType(this);
        }

        override Object destVal() {
            Schema.sObjectType sobjType;
            if (srcVal instanceof String) {
                sobjType = resolveSObjectType((String) srcVal);
                if (sobjType == null) {
                    deserErr(this, 'sObjectType "' + srcVal + '" does not exist');
                }
            } else if (srcVal != null) {
                deserErr(this, 'sobjectType must be string; got ' + jsonType(srcVal));
            }
            return sobjType;
        }
    }

    class RecordTypeProp extends DeserProp {
        RecordTypeProp(DeserObj obj, String srcKey, Object srcVal) {
            super(obj, srcKey, srcVal);
            obj.setRecordType(this);
        }

        override Object destVal() {
            // TODO: optionally resolve srcValue as a DeveloperName or Name string...
            Id recTypeId;
            if (srcVal instanceof String) {
                if (String.isBlank((String) srcVal)) {
                    return null;
                }
                try {
                    recTypeId = Id.valueOf((String) srcVal);
                } catch ( Exception e) {
                    deserErr(this, 'Record Type has invalid format [' + String.valueOf(srcVal) + ']');
                }
            } else if (srcVal != null) {
                deserErr(this, 'Record Type must be string; got ' + jsonType(srcVal));
            }
            if (recTypeId != null) {
                Map<Id, Schema.RecordTypeInfo> infoMap = obj.sobjType.getDescribe().getRecordTypeInfosById();
                if (infoMap == null || infoMap.get(recTypeId) == null) {
                    deserErr(this, 'Record Type ' + recTypeId + ' is not valid for Object type ' + this.obj.sobjType);
                }
            }
            return recTypeId;
        }
    }

    abstract class FieldProp extends DeserProp {
        Schema.DescribeFieldResult fieldDesc;
        Integer priority;

        FieldProp(DeserObj obj, String srcKey, Schema.DescribeFieldResult fieldDesc, Integer priority, Object srcVal) {
            super(obj, srcKey, srcVal);
            this.fieldDesc = fieldDesc;
            this.priority = priority;
            String qualKey = '' + fieldDesc.getSObjectField();
            FieldProp clash = obj.fieldProps.get(qualKey);
            if (clash == null || this.priority < clash.priority) {
                this.destKey = qualKey;
                obj.fieldProps.put(qualKey, this);
            }
        }
    }

    class StringProp extends FieldProp {
        StringProp(DeserObj obj, String srcKey, Schema.DescribeFieldResult fieldDesc, Integer priority, Object srcVal) {
            super(obj, srcKey, fieldDesc, priority, srcVal);
        }

        override Object destVal() {
            if (srcVal == null) {
                return null;
            }
            String str = String.valueOf(srcVal).trim();
            return str.length() > 0 ? str : null;
        }
    }

    class LookupIdProp extends FieldProp {
        LookupIdProp(DeserObj obj, String srcKey, Schema.DescribeFieldResult fieldDesc, Integer priority, Object srcVal) {
            super(obj, srcKey, fieldDesc, priority, srcVal);
        }

        override Object destVal() {
            Id lkp;
            if (srcVal instanceof String) {
                if (String.isBlank((String) srcVal)) {
                    return null;
                }
                try {
                    lkp = Id.valueOf((String) srcVal);
                } catch ( Exception e) {
                    deserErr(this, 'Lookup Id has invalid format [' + String.valueOf(srcVal) + ']');
                }
            } else if (srcVal != null) {
                deserErr(this, 'Lookup Id must be string; got ' + jsonType(srcVal));
            }
            if (lkp != null) {
                // verify that the lkp id value is of a compatible sObjectType:
                Schema.sObjectType matchType = lkp.getSObjectType();
                for (Schema.sObjectType refTo : fieldDesc.getReferenceTo()) {
                    if (refTo == matchType) {
                        return lkp;
                    }
                }
                String[] types = new String[]{};
                for (Schema.sObjectType refTo : fieldDesc.getReferenceTo()) {
                    types.add('' + refTo);
                }
                deserErr(this, 'Lookup Id expected to be for sObjectType ' + String.join(types, ',') + '; got ' + lkp.getSObjectType());
            }
            return null;
        }
    }

    static final Pattern ISODatePatt = Pattern.compile('(\\d{4}+)-(\\d{1,2}+)-(\\d{1,2}+)');

    class DateProp extends FieldProp {
        DateProp(DeserObj obj, String srcKey, Schema.DescribeFieldResult fieldDesc, Integer priority, Object srcVal) {
            super(obj, srcKey, fieldDesc, priority, srcVal);
        }

        override Object destVal() {
            if (srcVal == null) {
                return null;
            } else if (srcVal instanceof String) {
                if (String.isBlank((String) srcVal)) {
                    return null;
                }
                Matcher m = ISODatePatt.matcher((String) srcVal);
                if (m.find()) {
                    return Date.newInstance(Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)), Integer.valueOf(m.group(3)));
                }
                deserErr(this, 'Date field expects an ISO-formatted value; got: ' + jsonType(srcVal));
            }
            deserErr(this, 'Date field expects an ISO-formatted string value; got: ' + jsonType(srcVal));
            return srcVal;
        }
    }

    @TestVisible
    class NumberProp extends FieldProp {
        @TestVisible
        NumberProp(DeserObj obj, String srcKey, Schema.DescribeFieldResult fieldDesc, Integer priority, Object srcVal) {
            super(obj, srcKey, fieldDesc, priority, srcVal);
        }
        @TestVisible
        override Object destVal() {
            String floatErr;
            if (srcVal == null) {
                return null;
            } else if (srcVal instanceof Decimal) {
                return srcVal;
            } else if (srcVal instanceof String) {
                if (String.isBlank((String) srcVal)) {
                    return null;
                }
                // try to parse a string as a number:
                Decimal dval;
                try {
                    dval = Decimal.valueOf((String) srcVal);
                } catch (Exception fe){
                    floatErr = fe.getMessage();
                }
                if (dval != null) {
                    return dval;
                }
                // else fallthrough to error...
            }
            deserErr(this, 
                'Number field has incompatible right-hand value: ' + 
                jsonType(srcVal) + 
                (floatErr != null ? '; reason: ' + floatErr : ''));
            return srcVal; // unreachable
        }
    }

    class BooleanProp extends FieldProp {
        BooleanProp(DeserObj obj, String srcKey, Schema.DescribeFieldResult fieldDesc, Integer priority, Object srcVal) {
            super(obj, srcKey, fieldDesc, priority, srcVal);
        }

        override Object destVal() {
            if (srcVal == true || srcVal == 'true') {
                return true;
            } else if (srcVal == null || srcVal == false || srcVal == 'false') {
                return false;
            } else if (srcVal instanceof Decimal) {
                Decimal decVal = (Decimal) srcVal;
                return decVal != 0;
            }
            deserErr(this, 'Boolean field has incompatible right-hand value: ' + jsonType(srcVal));
            return srcVal;
        }
    }

    static String jsonType(Object elmt) {
        return elmt == null ? 'null' : elmt instanceof Object[] ? 'Array' : elmt instanceof Map<String, Object> ? 'Object' : 
            elmt instanceof Decimal ? 'number' : elmt instanceof String ? 'string' : elmt instanceof Boolean ? 'boolean' : '' + elmt;
    }

    static void deserErr(String msg) {
        msg = 'sObject Deserialize Error: ' + msg;
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        throw ae;
    }

    static void deserErr(DeserObj obj, String srcKey, String msg) {
        String loc = obj.srcIndex != null ? ' @ sObject[' + obj.srcIndex + ']' + (srcKey != null ? '.' + srcKey : '') : (srcKey != null ? ' @ ' + srcKey : '');
        msg = 'sObject Deserialize Error' + loc + ': ' + msg;
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        throw ae;
    }

    static void deserErr(DeserProp prop, String msg) {
        String loc = prop.obj.srcIndex != null ? ' @ sObject[' + prop.obj.srcIndex + '].' + prop.srcKey : ' @ ' + prop.srcKey;
        msg = 'sObject Deserialize Error' + loc + ': ' + msg;
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        throw ae;
    }

    /* === normalizeSObject ===
        - Receives an SObject or SObject[] instance as an input.
        - Returns a Map<String, Object> or List<Map<String, Object>> instance as an output.
        - The output map/s will contain all readable fields within the input SObjects, with those values
            duplicated under both the fully qualifed, and non-namespaced versions of each field.

        * NOTE: The idea is to use this function as the LAST step in an AuraEnabled method, prior to
            returning any queried records to the client. This allows the preceding logic in the AuraEnabled
            method to operate in a "system" context, while still ensuring that non-readable objects/fields
            are not returned to the client.

        === Example Input/Output ===
        INPUT (SObject): {
            Id: "...",
            rkqf__Field1__c: "FIELD1 VALUE",
            rkqf__ChildRel__r: [{
                Id: "...",
                rkqf__ChildField1__c: "CHILD1 FIELD1 VALUE"
            }, {
                Id: "...",
                rkqf__ChildField1__c: "CHILD2 FIELD1 VALUE"
            }],
            rkqf__Lookup__r: {
                Id: "...",
                rkqf__OtherField1__c: "LOOKUP FIELD1 VALUE"
            }
        }

        OUTPUT (Map<String, Object>): {
            Id: "...",
            rkqf__Field1__c: "FIELD1 VALUE",
            Field1__c: "FIELD1 VALUE",
            rkqf__ChildRel__r: [{
                Id: "...",
                rkqf__ChildField1__c: "CHILD1 FIELD1 VALUE",
                ChildField1__c: "CHILD1 FIELD1 VALUE"
            }, {
                Id: "...",
                rkqf__ChildField1__c: "CHILD2 FIELD1 VALUE",
                ChildField1__c: "CHILD2 FIELD1 VALUE"
            }],
            ChildRel__r: [{
                Id: "...",
                rkqf__ChildField1__c: "CHILD1 FIELD1 VALUE",
                ChildField1__c: "CHILD1 FIELD1 VALUE"
            }, {
                Id: "...",
                rkqf__ChildField1__c: "CHILD2 FIELD1 VALUE",
                ChildField1__c: "CHILD2 FIELD1 VALUE"
            }],
            rkqf__Lookup__r: {
                Id: "...",
                rkqf__OtherField1__c: "LOOKUP FIELD1 VALUE",
                OtherField1__c: "LOOKUP FIELD1 VALUE"
            },
            Lookup__r: {
                Id: "...",
                rkqf__OtherField1__c: "LOOKUP FIELD1 VALUE",
                OtherField1__c: "LOOKUP FIELD1 VALUE"
            }
        }
    */

    public static CRUD checkCRUD(Schema.sObjectType sobjType) {
        RKSecurity.SecuritySavepoint sp = new RKSecurity.SecuritySavepoint();
        try {
            RKSecurity.setSecurityMode(RKSecurity.FILTER_FLS_CRUD);
            CRUD perms = new CRUD();
            perms.C = assertCreateable(sobjType);
            perms.R = assertReadable(sobjType);
            perms.U = assertUpdateable(sobjType);
            perms.D = assertDeletable(sobjType);
            return perms;
        } finally {
            RKSecurity.restore(sp);
        }
    }

    public class CRUD {
        @AuraEnabled
        public Boolean C {get; private set;}
        @AuraEnabled
        public Boolean R {get; private set;}
        @AuraEnabled
        public Boolean U {get; private set;}
        @AuraEnabled
        public Boolean D {get; private set;}
    }

    private static CheckPermsRead ReadChecker = new CheckPermsRead();
    private static CheckPermsInsert CreateChecker = new CheckPermsInsert();
    private static CheckPermsUpdate UpdateChecker = new CheckPermsUpdate();

    public static Boolean assertDeletable(Schema.sObjectType sobjType) {
        resetSecurityLog(true);
        Boolean ok = sobjType.getDescribe().isDeletable();
        if (!ok) {
            logSecurityMiss(sobjType, ACCESS_DELETE);
        }
        throwSecurityViolations(true);
        return ok;
    }

    public static Boolean assertUpdateable(Schema.sObjectType sobjType) {
        resetSecurityLog(true);
        Boolean ok = UpdateChecker.checkCRUD(sobjType);
        throwSecurityViolations(true);
        return ok;
    }

    public static Boolean assertCreateable(Schema.sObjectType sobjType) {
        resetSecurityLog(true);
        Boolean ok = CreateChecker.checkCRUD(sobjType);
        throwSecurityViolations(true);
        return ok;
    }

    public static Boolean assertReadable(Schema.sObjectType sobjType) {
        resetSecurityLog(true);
        Boolean ok = ReadChecker.checkCRUD(sobjType);
        throwSecurityViolations(true);
        return ok;
    }

    public static Boolean assertReadable(String sobjTypeName) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        return assertReadable(sobjType);
    }

    // Verifies CRUD access on the sObjectType and FLS-read access on the supplied fields (NOTE: does NOT currently support 
    // compound paths or FieldSet names). This is intended to help secure SOQL queries that have WHERE clause filters bound 
    // to client-supplied field values.
    public static Boolean assertReadable(Schema.sObjectType sobjType, String[] fields) {
        resetSecurityLog(true);
        Boolean ok = ReadChecker.checkCRUD(sobjType);
        for (String f : fields) {
            Schema.sObjectField fieldTok = resolveField(sobjType, f);
            if (fieldTok != null) {
                // make sure we only pass fully qualified field names:

                // MDU RKDEV-34615 - changed the order of "ok" and "checkFLS" in the following "&&"" condition because the 
                // short-circuiting was preventing error logging from reporting all field security violations in one message:
                //ok = ok && ReadChecker.checkFLS(sobjType, '' + fieldTok);
                ok = ReadChecker.checkFLS(sobjType, '' + fieldTok) && ok;
            } else { // if (f.containsAny('.,: \t\n\r')) {
                throw new ReferenceException('Invalid sObject Field [' + f + '] on Object ' + sobjType);
            }
        }
        throwSecurityViolations(true);
        return ok;
    }

    public static Boolean assertReadable(String sobjTypeName, String[] fields) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        return assertReadable(sobjType, fields);
    }
  
    public static Boolean assertReadable(Schema.sObjectType sobjType, String field) {
        return assertReadable(sobjType, new String[]{ field });
    }

    public static Boolean assertReadable(String sobjTypeName, String field) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        return assertReadable(sobjType, new String[]{ field });
    }

    public static Boolean isReadable(Schema.sObjectType sobjType) {
        return ReadChecker.checkCRUD(sobjType);
    }

    public static Boolean isReadable(String sobjTypeName) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        return ReadChecker.checkCRUD(sobjType);
    }

    // Filters the records' fields for FLS "Read" AND filters records for sharing "Read" access:
    public static List<Map<String, Object>> filterSObjectSafeReadables(SObject[] records) {
        return filterSObject(records, true);
    }

    // Filters the records' fields for FLS "Read", but does NOT filter records for sharing "Read" access:
    public static List<Map<String, Object>> filterSObject(SObject[] records) {
        return filterSObject(records, false);
    }

    public static List<Map<String, Object>> filterSObject(SObject[] records, Boolean applyRecordSecurity) {
        resetSecurityLog(true);
        FilterContext ctxt = new FilterContext();
        ctxt.scope=new Set<Id>();
        List<Map<String, Object>> res = filterSObject(records, ctxt);
        throwSecurityViolations(true);
          
        if (applyRecordSecurity == true) {
            return filterForReadable(res, ctxt.getReadableScope());
        } else {
            return res;
        }
    }

    private static List<Map<String, Object>> filterSObject(SObject[] records, FilterContext ctxt) {
        List<Map<String, Object>> filteredRecords = new List<Map<String, Object>>();
        if (records != null) {
            for (SObject record : records) {
                filteredRecords.add(filterSObject(record, ctxt));
            }
        }
        return filteredRecords;
    }

    // Filters the record's fields for FLS "Read" AND filters the record itself for sharing "Read" access:
    public static Map<String, Object> filterSObjectSafeReadable(SObject record) {
        return filterSObject(record, true);
    }

    // Filters the record's fields for FLS "Read", but does NOT filter the record for sharing "Read" access:
    public static Map<String, Object> filterSObject(SObject record) {
        return filterSObject(record, false);
    }

    public static Map<String, Object> filterSObject(SObject record, Boolean applyRecordSecurity) {
        resetSecurityLog(true);
        FilterContext ctxt = new FilterContext();
        Map<String, Object> res = filterSObject(record, ctxt);
        throwSecurityViolations(true);

        if (applyRecordSecurity == true && record != null && record.Id != null) {
            List<Map<String, Object>> readable = filterForReadable(
                new List<Map<String, Object>>{ res }, ctxt.getReadableScope());
            if (readable.isEmpty()) {
                // Access exception:
                throwAccessViolation(record.Id);
                return null;
            } else {
                return readable[0];
            }
        } else {
            return res;
        }
    }

    private static Map<String, Object> filterSObject(SObject record, FilterContext ctxt) {
        if (record.Id != null) {
            Integer refRepCount = 0;
            for (Id refId : ctxt.refStack) {
                if (refId == record.Id) {
                    if (++refRepCount > 1) {
                        return new Map<String, Object>{ 'Id' => record.Id };
                    }
                }
            }
        }
        // Push this record Id onto the reference stack
        Integer stackTop = ctxt.refStack.size();
        ctxt.refStack.add(record.Id);
        ctxt.scope.add(record.Id);
        Map<String, Object> normalizedFields = new Map<String, Object>();
        try {
            final String packageNamespace = getPackageNamespace();
            Map<String, Object> recordFields = record.getPopulatedFieldsAsMap();
            for (String fieldName : recordFields.keySet()) {
                // inline logic from stripThisNamespace() to parse out an explicit namespace from the base API name:
                Matcher m = ObjFieldPatt.matcher(fieldName);
                String entityNamespace;
                //String strippedFieldName = fieldName;
                String pkgUnqualifiedName = fieldName;
                String checkPackageMaskingEntity;
                if (m.matches()) {
                    entityNamespace = m.group(1);
                    // if this entity carries an explicit namespace that matches the package namespace, then derive the base API name and store this into
                    // `strippedFieldName`: 
                    if (String.isNotBlank(entityNamespace) && packageNamespace != null && entityNamespace == packageNamespace) {
                        pkgUnqualifiedName = m.group(2);
                    }
                    // if this entity carries no explicit namespace (i.e. org deafult namespace), then we check to see if there is a package version with the same
                    // base API name; in that case the latter package entity will "mask" the local non-namespaced entity in order to fully replicate the behavior
                    // of dynamic Apex (Database.query, sObject.get/put) running in package code:
                    if (String.isBlank(entityNamespace) && packageNamespace != null) {
                        checkPackageMaskingEntity = packageNamespace + '__' + fieldName;
                    }
                }
                Object fieldValue = recordFields.get(fieldName);
                Object qualifiedFieldValue, unqualifiedFieldValue;
                
                // Could use pattern matching for __r vs __c here to detect fields/child rels,
                // but that would require additional edge case checking for child rels on standard lookup fields.
                // Erred on the side of dynamic type checking instead to handle all cases in one go.
                Boolean pkgUnqualifiedOnly = false;
                if (fieldValue instanceof List<SObject>) {
                    Schema.ChildRelationship childRel = getChildRelationship(String.valueOf(record.getSObjectType()), fieldName);
                    //Schema.ChildRelationship childRel = resolveChildRelOrThrow(record.getSObjectType(), fieldName);
                    // Check for read access on related object
                    if (!ReadChecker.checkCRUD(childRel.getChildSObject())) {
                        continue;
                    }
                    // Check for read access on lookup field (on child)
                    if (!ReadChecker.checkFLS(childRel.getChildSObject(), childRel.getField().getDescribe().getName())) {
                        continue;
                    }
                    // Check for a masking child-relationship in the package:
                    if (checkPackageMaskingEntity != null && 
                            getChildRelationship(String.valueOf(record.getSObjectType()), checkPackageMaskingEntity) != null) {
                            //resolveChildRelOrThrow(record.getSObjectType(), checkPackageMaskingEntity) != null) {
                        continue;
                    }

                    // Make sure the original child rel list is normalized as well
                    //pkgUnqualifiedOnly = !FilterSObject_NSMirrorChildAndParentRels;
                    //fieldValue = filterSObject((List<SObject>) fieldValue, refStack);

                    if (ctxt.mirrorMode != DataMirrorMode.UnQualified) {
                        qualifiedFieldValue = filterSObject((List<SObject>) fieldValue, ctxt.fork(DataMirrorMode.Qualified));
                    }
                    if (ctxt.mirrorMode != DataMirrorMode.Qualified) {
                        unqualifiedFieldValue = filterSObject((List<SObject>) fieldValue, ctxt.fork(DataMirrorMode.UnQualified));
                    }
                } else if (fieldValue instanceof SObject) {
                    // Ensure read access on lookup field
                    String lkp = fieldName.replaceFirst('__r$', '__c');
                    if (!lkp.endsWith('__c')) {
                        lkp = lkp + 'Id';
                    }
                    if (!ReadChecker.checkFLS(record.getSObjectType(), lkp)) {
                        continue;
                    }
                    // Check for a masking lookup in the package:
                    if (checkPackageMaskingEntity != null && 
                            getCachedField(record.getSObjectType(), packageNamespace + '__' + lkp) != null) {
                        continue;
                    }

                    // Ensure read access on related object/s
                    //String[] relatedTypes = getReferenceTo(String.valueOf(record.getSObjectType()), fieldName);
                    // TODO - review:
                    Schema.sObjectType[] relatedTypes = resolveFieldOrThrow(record.getSObjectType(), lkp).getDescribe().getReferenceTo();

                    // Replace with labeled loop?
                    Boolean hasAccessToAll = true;
                    //for (String relatedType : relatedTypes) {
                    for (Schema.sObjectType relatedType : relatedTypes) {
                        //if (!ReadChecker.checkCRUD(getSObjectType(relatedType))) {
                        if (!ReadChecker.checkCRUD(relatedType)) {
                            hasAccessToAll = false;
                            break;
                        }
                    }
                    if (!hasAccessToAll) {
                        continue;
                    }
                    //pkgUnqualifiedOnly = !FilterSObject_NSMirrorChildAndParentRels;
                    //fieldValue = filterSObject((SObject) fieldValue, refStack);
                    
                    if (ctxt.mirrorMode != DataMirrorMode.UnQualified) {
                        qualifiedFieldValue = filterSObject((SObject) fieldValue, ctxt.fork(DataMirrorMode.Qualified));
                    }
                    if (ctxt.mirrorMode != DataMirrorMode.Qualified) {
                        unqualifiedFieldValue = filterSObject((SObject) fieldValue, ctxt.fork(DataMirrorMode.UnQualified));
                    }
                } else {
                    if (!ReadChecker.checkFLS(record.getSObjectType(), fieldName)) {
                        // No read access at field level (primitive value type, not related record or child rel)
                        continue;
                    }
                    // Check for a masking field in the package:
                    if (checkPackageMaskingEntity != null && 
                            getCachedField(record.getSObjectType(), checkPackageMaskingEntity) != null) {
                        continue;
                    }

                    qualifiedFieldValue = fieldValue;
                    unqualifiedFieldValue = fieldValue;
                }

                // Re-Place the cleaned field value under the original field name, and the non-namespaced field name
                /*if (!pkgUnqualifiedOnly) {
                    normalizedFields.put(fieldName, fieldValue);
                }*/
                // Save a bit of processing power here if the "stripped" name was unaffected
                /*if (pkgUnqualifiedOnly || pkgUnqualifiedName != fieldName) {
                    normalizedFields.put(pkgUnqualifiedName, fieldValue);
                }*/

                // JLB - Updated to facilitate new data mirror technique
                if (ctxt.mirrorMode != DataMirrorMode.UnQualified) {
                    normalizedFields.put(fieldName, qualifiedFieldValue);
                }
                if (ctxt.mirrorMode != DataMirrorMode.Qualified) {
                    normalizedFields.put(pkgUnqualifiedName, unqualifiedFieldValue);
                }
            }
        } finally {

/* mulveling-dev
            // Apply mock bindings if applicable
            RKMock.applyMockBindings(record.getSObjectType(), normalizedFields);
*/

            // Pop this record Id off the reference stack
            while (ctxt.refStack.size() > stackTop) {
                ctxt.refStack.remove(stackTop);
            }
        }

        return normalizedFields;
    }

    class FilterContext {
        Id[] refStack = new Id[]{};
        Set<Id> scope = new Set<Id>();
        DataMirrorMode mirrorMode = DataMirrorMode.BOTH;

        FilterContext fork(DataMirrorMode newMode) {
            if (newMode != this.mirrorMode) {
                // !! Note: this is not a deep clone on purpose; the Id collections MUST be transfered by reference:
                FilterContext fork = this.clone();
                fork.mirrorMode = newMode;
                return fork;
            }
            return this;
        }

        Set<Id> getReadableScope() {
            return SafeSharingModel.filterReadable(scope);
        }
    }

    private static List<Map<String, Object>> filterForReadable(List<Map<String, Object>> records, Set<Id> readableScope) {
        Map<String, Object> struct = new Map<String, Object>{ 'recs' => records };
        filterForReadableRelations(struct, readableScope, false);
        return (List<Map<String, Object>>) struct.get('recs');
    }

    private static Map<String, Object> filterForReadableRelations(Map<String, Object> rec, Set<Id> readableScope, 
            Boolean removeEmptyChildren) {
        for (String field : rec.keySet()) {
            Object val = rec.get(field);
            // If field value is a parent relationship we need to determine if the parent record should be removed or not, 
            // and if it remains then we must recursively filter it:
            if (val instanceof Map<String, Object>) {
                Map<String, Object> parent = (Map<String, Object>) val;
                Id parentId = (Id) parent.get('Id');
                if (parentId == null || readableScope.contains(parentId)) {
                    filterForReadableRelations(parent, readableScope, true);
                } else {
                    rec.remove(field);
                }
            // Else if field value is a child relationship we need to filter the children list, and then recursively 
            // filter each child record that remains:
            } else if (val instanceof List<Map<String, Object>>) {
                List<Map<String, Object>> children = (List<Map<String, Object>>) val;
                for (Integer i=0; i < children.size(); i++) {
                    Map<String, Object> child = children[i];
                    Id childId = (Id) child.get('Id');
                    if (childId == null || readableScope.contains(childId)) {
                        filterForReadableRelations(child, readableScope, true);
                    } else {
                        children.remove(i--);
                    }
                }
                if (children.isEmpty() && removeEmptyChildren) {
                    rec.remove(field);
                }
            }
        }
        return rec;
    }

    public static String joinSelect(String selsLeft, String selsRight) {
        selsLeft = selsLeft != null ? selsLeft.replaceAll('\\s++', '').replaceAll('^[,]++|[,]++$', '') : null;
        selsRight = selsRight != null ? selsRight.replaceAll('\\s++', '').replaceAll('^[,]++|[,]++$', '') : null;
        if (String.isNotBlank(selsLeft) && String.isNotBLank(selsRight)) {
            return selsLeft + ',' + selsRight;
        } else if (String.isNotBlank(selsLeft)) {
            return selsLeft;
        } else if (String.isNotBlank(selsRight)) {
            return selsRight;
        } else {
            return 'Id';
        }
    }

    // For the safeSelect calls below, a "selectElement" can be any of the following:
    //   * A Field API name e.g. 'My_Field__c'
    //   * A field path e.g. 'Parent_Lookup__r.My_Other_Field__c'
    //   * A FieldSet name e.g. 'My_Field_Set'
    //   * A delimited list of any of the above - any combination of spaces, commas, colons, semicolons etc can be used as delimiters 
    //     e.g. 'My_Field__c, Parent_Lookup__r.My_Other_Field__c, My_Field_Set'
    // 
    // All safeSelect methods return a comma-delimited list of field names that can be used as the target of a SOQL SELECT clause; FieldSets will be 
    // automatically expanded. Field-Level Security and CRUD permissions will be enforced for the context user (TODO: soon); fields for which the 
    // user is lacking visibility will simply be stripped from the result string.
    //
    // Example usage:
    // Database.query('SELECT ' + RKSecurity.safeSelect(Schema.My_Table__c.sObjectType, 'My_Field__c, Parent_Lookup__r.My_Other_Field__c, My_Field_Set') + ' FROM My_Table__c'); 

    public static String systemSelect(String sobjTypeName, String selectElement) {
        return systemSelect(sobjTypeName, new List<String>{ selectElement }, null);
    }

    public static String systemSelect(String sobjTypeName, String selectElement, Integer oneTimeBindingStratregy) {
        return systemSelect(sobjTypeName, new List<String>{ selectElement }, oneTimeBindingStratregy);
    }

    public static String systemSelect(String sobjTypeName, List<String> selectElements) {
        return systemSelect(sobjTypeName, selectElements, null);
    }

    public static String systemSelect(String sobjTypeName, List<String> selectElements, Integer oneTimeBindingStratregy) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        final Boolean SecureAccessMode = false;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }

    public static String systemSelect(Schema.sObjectType sobjType, String selectElement) {
        final Boolean SecureAccessMode = false;
        return selectLogic(SecureAccessMode, sobjType, new List<String>{ selectElement }, null);
    }

    public static String systemSelect(Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy) {
        final Boolean SecureAccessMode = false;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }
    
    public static String safeSelect(String sobjTypeName, String selectElement) {
        return safeSelect(sobjTypeName, new List<String>{ selectElement }, null);
    }

    public static String safeSelect(String sobjTypeName, String selectElement, Integer oneTimeBindingStratregy) {
        return safeSelect(sobjTypeName, new List<String>{ selectElement }, oneTimeBindingStratregy);
    }

    public static String safeSelect(String sobjTypeName, List<String> selectElements) {
        return safeSelect(sobjTypeName, selectElements, null);
    }

    public static String safeSelect(String sobjTypeName, List<String> selectElements, Integer oneTimeBindingStratregy) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        final Boolean SecureAccessMode = true;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }

    public static String safeSelect(Schema.sObjectType sobjType, String selectElement) {
        final Boolean SecureAccessMode = true;
        return selectLogic(SecureAccessMode, sobjType, new List<String>{ selectElement }, null);
    }

    public static String safeSelect(Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy) {
        final Boolean SecureAccessMode = true;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }

    public static String selectLogic(Boolean isSafeMode, Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy) {
        Set<String> sels = selectSetLogic(isSafeMode, true, sobjType, selectElements, oneTimeBindingStratregy);
        return String.join(new List<String>(sels), ',');
    }

    public static Set<String> selectSetLogic(Boolean isSafeMode, Boolean crudCheck, Schema.sObjectType sobjType, 
            List<String> selectElements, Integer oneTimeBindingStratregy) {

        Map<String, PathPart> selMap = selectMapLogic(isSafeMode, crudCheck, sobjType, selectElements, oneTimeBindingStratregy);
        if (selMap.keySet().isEmpty()) {
            return new Set<String>{ 'Id' };
        } else {
            return selMap.keySet();
        }
    }

    // Note that the PathParts returned will be the leaves, i.e. terminating fields:
    public static Map<String, PathPart> selectMapLogic(Boolean isSafeMode, Boolean crudCheck, Schema.sObjectType sobjType, 
            List<String> selectElements, Integer oneTimeBindingStratregy) {

        resetSecurityLog(true);
        if (oneTimeBindingStratregy != null) {
            startBinding(oneTimeBindingStratregy);
        }
        try {
            if (isSafeMode == true && crudCheck == true && !ReadChecker.checkCRUD(sobjType)) {
                // TODO: fix this
                return new Map<String, PathPart>{ 'NO_CRUD_READ_ACCESS_' + sobjType => null };
            }
            Map<String, PathPart> resolvedFields = new Map<String, PathPart>(); // new Set<String>{ 'Id' };
            // parse out anything that looks like a valid SFDC api name:
            String elmtCat = String.join(selectElements, ','); //+ ',' + String.join(openSelElmts, ',');
            Matcher m = CrudeIdentifyApiPathPatt.matcher(elmtCat);
            PathPart[] headParts = new PathPart[]{};
            while (m.find()) {
                String elmt = m.group(0);
                // compound field paths will have their path parts delimited by the dot-operator:
                String[] rawPathParts = elmt.split('\\.');
                PathPart headPart = new PathPart(sobjType);
                try {
                    resolvePathBranch(headPart, rawPathParts, 0);
                } catch (Exception e) {
                    outErr(e);
                }
                headParts.add(headPart);
            }
            if (headParts.size() > 0) {
                Map<String, PathPart> resolvedPaths;
                if (isSafeMode == true) {
                    resolvedPaths = getSafeAccessPathsMap(headParts);
                } else {
                    resolvedPaths = getSystemAccessPathsMap(headParts);
                }
                resolvedFields.putAll(resolvedPaths);
            }
            return resolvedFields;
        } finally {
            if (oneTimeBindingStratregy != null) {
                revertBinding();
            }
            throwSecurityViolations(true);
        }
    }

    // !! NEW: Trying out SOQLParser *-selector functionality:
    public static Map<String, PathPart> selectStarLogic(Boolean isSafeMode, Schema.sObjectType sobjType) {
        String[] sels = new String[]{};
        Schema.DescribeSObjectResult sobjDesc = sobjType.getDescribe();
        Schema.RecordTypeInfo[] recTypes = sobjDesc.getRecordTypeInfos();
        Boolean hasRecordTypes = recTypes.size() > 0;
        if (recTypes.size() == 1 && recTypes[0].getDeveloperName() == 'Master') {
            hasRecordTypes = false;
        }
        if (hasRecordTypes) {
            sels.addAll(new String[]{ 'RecordTypeId', 'RecordType.DeveloperName', 'RecordType.Name' });
        }

        // Custom Metadata Objects ending in __mdt:
        if (sobjDesc.getName().endsWithIgnoreCase('__mdt')) {
            sels.addAll(new String[]{ 'MasterLabel', 'DeveloperName' });
        // Custom Objects ending in __c:
        } else if (sobjDesc.isCustom()) {
            sels.addAll(new String[]{ 'Name', 'CreatedDate' });
        // Specializations for Standard Objects:
        // TODO: these would be better defined in an external resource file...
        } else {
            switch on ('' + sobjType) {
                when 'Contact' {
                    sels.addAll(new String[]{ 
                        'RecordTypeId', 'RecordType.DeveloperName', 'Name', 'Email', 'Birthdate', 'AccountId', 'Account.Name',
                        'Department', 'Description', 'FirstName', 'LastName', 'GenderIdentity', 'Title', 
                        'MailingAddress', 'MailingCountry', 'MailingPostalCode' });
                }
                when 'AsyncApexJob' {
                    sels.addAll(new String[]{ 
                        'Status', 'ExtendedStatus', 'JobType', 'JobItemsProcessed', 'TotalJobItems', 
                        'CompletedDate', 'MethodName', 'NumberOfErrors', 'ParentJobId', 'CronTriggerId',
                        'ApexClassId', 'ApexClass.Name', 'ApexClass.NamespacePrefix' });
                }
                // TODO: more standard objects we'll want to support...
            }
        }
        // TODO: do Custom Metadata objects require special handling?
        for (Schema.SObjectField fieldTok : sobjDesc.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDesc = fieldTok.getDescribe();
            if (fieldDesc.isCustom() && fieldDesc.getType() != Schema.DisplayType.BASE64) {
                sels.add(fieldDesc.getName());
            }
        }
        
        if (isSafeMode) {
            // !! Since caller is not explicitly specifying the fields expanded by a "*" selector, safe mode should 
            // temporarily switch into FILTER mode rather than THROW, for handling insufficient access on expanded 
            // fields (access being relative to the current ExecutionContext). In other words, if an expanded field 
            // doesn't have access, if should be silently excluded from the resuling expansion list rather than 
            // throwing a security exception:
            SecuritySavepoint sp = new SecuritySavepoint(); 
            try {
                resetSecurityLog(true);
                setSecurityMode(FILTER_FLS_CRUD);
                return selectMapLogic(isSafeMode, false, sobjType, sels, null);
            } finally {
                // !! always restore the original security mode settings and security logs (accumulates field 
                // access violations):
                restore(sp);
            }
        } else {
            return selectMapLogic(isSafeMode, false, sobjType, sels, null);
        }
    }

    public static String getSafePath(Schema.sObjectType sobjType, String rawPath) {
        if (String.isNotBlank(rawPath) && ReadChecker.checkCRUD(sobjType)) {
            String[] rawPathParts = rawPath.split('\\.');
            PathPart headPart = new PathPart(sobjType);
            resolvePathBranch(headPart, rawPathParts, 0);
            Set<String> resolvedPaths = getSafeAccessPaths(new PathPart[]{ headPart });
            if (resolvedPaths != null && resolvedPaths.size() > 0) {
                return new List<String>(resolvedPaths)[0];
            }
        }
        return null;
    }
    
    public static PathPart getPathMeta(Schema.sObjectType rootType, String rawPath) {
        String[] rawPathParts = rawPath.split('\\.');
        PathPart headPart = new PathPart(rootType); //Schema.Questionnaire_Form__c.sObjectType);
        resolvePathBranch(headPart, rawPathParts, 0);
        return headPart;
    }

    public static PathPart getPathMeta(String rawPath, String sobjectName) {  //RKDEV-34816
        String[] rawPathParts = rawPath.split('\\.');
/* mulveling-dev
        Schema.SObjectType sObjectType = String.isBlank(sobjectName) ? Schema.Questionnaire_Form__c.sObjectType : getSObjectType(sObjectName);
*/
        System.assert(sObjectName != null, 'RKSecurity.getPathMeta(): sobjectName cannot be blank');
        Schema.SObjectType sObjectType = getSObjectType(sObjectName);

        PathPart headPart = new PathPart(sObjectType);
        resolvePathBranch(headPart, rawPathParts, 0);
        return headPart;
    }
    
/* mulveling-dev
    public static PathPart getPathMeta(String rawPath) {
        String[] rawPathParts = rawPath.split('\\.');
        PathPart headPart = new PathPart(Schema.Questionnaire_Form__c.sObjectType);
        resolvePathBranch(headPart, rawPathParts, 0);
        return headPart;
    }
*/

    public class PathPart {
        public PathPart head {get; private set;}
        public PathPart parent {get; private set;}
        public sObjectType holder {get; private set;}
        // next.size() is greater than 1 in the case of a fieldSet OR a field that is a polymorphic lookup:
        public PathPart[] next {get; private set;}
        public Schema.FieldSet fieldSet {get; private set;}
        public Schema.DescribeFieldResult fieldDesc {get; private set;}
        public String lex {get; private set;} // field or field set, with letter casing and suffix directly as pulled from the path string

        public Boolean isCompound {get{
            return this.next != null;
        }}

        public PathPart terminatingPart {get{
            if (terminatingPart == null) {
                PathPart term = this;
                while (term.next != null) {
                    term = term.next[0];
                }
                this.terminatingPart = term;
            }
            return terminatingPart;
        } private set; }

        private Boolean notSafeAccessible = false;

        public String safeAccessPath {get{
            if (safeAccessPath == null && !notSafeAccessible) {
                Set<String> safePaths = getSafeAccessPaths(new PathPart[]{ this });
                if (safePaths != null && safePaths.size() > 0) {
                    this.safeAccessPath = new List<String>(safePaths)[0];
                }
                this.notSafeAccessible = true;
            }
            return safeAccessPath;
        } private set; }

        // local accessibility flag, updated via the AccessibilityCompiler and AccessibilityCompilerPass2:
        Boolean accessible = false;

        PathPart(sObjectType holder) {
            this.head = this;
            this.holder = holder;
        }

        PathPart(PathPart parent, sObjectType holder) {
            this.head = parent.head;
            this.parent = parent;
            this.holder = holder;
        }

        void traverse(PathVisitor visitor) {
            if (visitor.visit(this) != false) {
                if (next != null) {
                    for (PathPart n : next) {
                        n.traverse(visitor);
                    }
                }
                if (visitor.doAfterVisit == true) {
                    visitor.afterVisit(this);
                }
            }
        }

        // Serializes the path from root to this specific node (not necessarily a leaf node):
        public String toNormalizedPath() {
            String[] revParts = new String[]{};
            PathPart part = this;
            // the node that this method is called on is the acting/effective tail part:
            Boolean onEffectiveTailPart = true;
            do {
                if (part.fieldDesc != null) {
                    String normName = part.fieldDesc.getName();
                    // even if this is a parent-ref __r part in the full path, if this the the acting tail part from being the initial method caller,
                    // it should serialize as a __c:
                    Boolean isRef = !onEffectiveTailPart && part.next != null;
                    if (isRef) {
                        if (normName.endsWith('Id') && normName != 'Id') {
                            revParts.add(normName.substring(0, normName.length() - 2));
                        } else if (normName.endsWithIgnoreCase('__c')) {
                            revParts.add(normName.substring(0, normName.length() - 3) + '__r');
                        } else {
                            revParts.add(normName);
                        }
                    } else {
                        revParts.add(normName);
                    }
                    onEffectiveTailPart = false;
                }
                part = part.parent;
            } while (part != null);
            // reverse the reverse-ordered parts before serialization:
            Integer len = revParts.size();
            for (Integer i=0; i < len / 2; i++) {
                String tmp = revParts[i];
                Integer counterpart = len - 1 - i;
                revParts[i] = revParts[counterpart];
                revParts[counterpart] = tmp;
            }
            return String.join(revParts, '.');
        }

        // JLB - Behaves pretty much the same as toNormalizedPath, but it additionally resolves any field names
        // with mock entries to their mock name. Useful for passing configurable field names to the client side
        // to allow dynamic field access
        public String toMockPath() {
            String[] revParts = new String[]{};
            PathPart part = this;
            // the node that this method is called on is the acting/effective tail part:
            Boolean onEffectiveTailPart = true;
            do {
                if (part.fieldDesc != null) {
                    String normName = part.fieldDesc.getName();
                    // even if this is a parent-ref __r part in the full path, if this the the acting tail part from being the initial method caller,
                    // it should serialize as a __c:
                    Boolean isRef = !onEffectiveTailPart && part.next != null;
                    if (isRef) {
                        if (normName.endsWith('Id') && normName != 'Id') {
                            normName = normName.substring(0, normName.length() - 2);
                        } else if (normName.endsWithIgnoreCase('__c')) {
                            normName = normName.substring(0, normName.length() - 3) + '__r';
                        }
                    }

                    // Resolve mock field name (will return originally passed value is no match found)
/* mulveling-dev
                    normName = RKMock.resolveToMockKey(part.holder, normName);
*/
                    revParts.add(normName);

                    onEffectiveTailPart = false;
                }
                part = part.parent;
            } while (part != null);
            // reverse the reverse-ordered parts before serialization:
            Integer len = revParts.size();
            for (Integer i=0; i < len / 2; i++) {
                String tmp = revParts[i];
                Integer counterpart = len - 1 - i;
                revParts[i] = revParts[counterpart];
                revParts[counterpart] = tmp;
            }
            return String.join(revParts, '.');
        }

        public Object getValue(sObject sobj, Boolean safeAccessFlag) {
            ValueGetter getter = new ValueGetter(sobj).safeAccess(safeAccessFlag);
            getter.exec(new PathPart[]{ this });
            return getter.leafValue;
        }
    }

    abstract class PathVisitor {
        Boolean doAfterVisit;

        PathVisitor(Boolean doAfterVisit) {
            this.doAfterVisit = doAfterVisit == true;
        }

        virtual void exec(PathPart[] headParts) {
            for (PathPart headPart : headParts) {
                System.assert(headPart.head === headPart, 'Visitor exec can only be called on head parts');
                headPart.traverse(this);
            }
        }
        
        virtual Boolean visit(PathPart part) { return true; } // no-op by default

        virtual void afterVisit(PathPart part) {} // no-op by default
    }

    // TODO: this seems redundant to getSystemAccessPaths()...
    @TestVisible
    static Set<String> getAllPaths(PathPart[] headParts) {
        SystemAccessCompiler compiler = new SystemAccessCompiler();
        compiler.exec(headParts);
        return compiler.fullPathsMap.keySet();
    }

    public static String getSystemAccessPath(PathPart headPart) {
        Set<String> path = getSystemAccessPaths(new PathPart[]{ headPart });
        return path != null && !path.isEmpty() ? new List<String>(path)[0] : null; 
    }

    public static Set<String> getSystemAccessPaths(PathPart[] headParts) {
        return getSystemAccessPathsMap(headParts).keySet();
    }

    public static Map<String, PathPart> getSystemAccessPathsMap(PathPart[] headParts) {
        SystemAccessCompiler compiler = new SystemAccessCompiler();
        compiler.exec(headParts);
        return compiler.fullPathsMap;
    }

    public static Map<String, PathPart> getSafeAccessPathsMap(PathPart[] headParts) {
        resetSecurityLog(true);
        new SafeAccessCompiler().exec(headParts);
        SafeAccessPass2 pass2 = new SafeAccessPass2();
        pass2.exec(headParts);
        throwSecurityViolations(true);
        return pass2.safePathsMap;
    }

    public static Set<String> getSafeAccessPaths(PathPart[] headParts) {
        return getSafeAccessPathsMap(headParts).keySet();
    }

    class SystemAccessCompiler extends PathVisitor {
        //Set<String> fullPaths = new Set<String>();
        Map<String, PathPart> fullPathsMap = new Map<String, PathPart>();

        SystemAccessCompiler() {
            super(false);
        }

        override Boolean visit(PathPart part) {
            if (part.fieldDesc != null && part.next == null) {
                //fullPaths.add(part.toNormalizedPath());
                // !! Note that we return the leaf (i.e. terminating) part of the path, useful for field describe metadata:
                fullPathsMap.put(part.toNormalizedPath(), part);
            }
            return true;
        }
    }

    class SafeAccessCompiler extends PathVisitor {
        SafeAccessCompiler() {
            super(true);
        }

        override Boolean visit(PathPart part) {
            Boolean parentAccessible = part.parent != null ? part.parent.accessible : true;
            // a child cannot be accessed if any of the parent lookup relationships in its field path are not accessible:
            if (!parentAccessible) {
                part.accessible = false;
            } else {
                // note that FieldSets get a pass-through because they don't have their own security 
                if (part.fieldDesc != null) {
                    // TODO: check CRUD "R" access on the part's holder object type...
                    part.accessible = part.fieldDesc.isAccessible();
                    if (!part.accessible) {
                        logSecurityMiss(part.holder, part.fieldDesc.getSObjectField(), ACCESS_READ);
                    }
                // field sets are always pass-through accessiblity becasue they do not have their own security:
                } else if (part.fieldSet != null) {
                    part.accessible = true;
                }
            }
            // short-circuit further traversal if this path node has been deemed non-accessible:
            return part.accessible;
        }

        override void afterVisit(PathPart part) {
            // polymorphic lookups require ALL of their 'next' fields be accessible; if they are not, then we correct its accessibility to false in this phase:
            if (part.accessible && part.fieldDesc != null && part.next != null && part.next.size() > 1) {
                for (PathPart next : part.next) {
                    if (!next.accessible) {                        
                        part.accessible = false;
                        break;
                    }
                }
            }
        }
    }

    class SafeAccessPass2 extends PathVisitor {
        //Set<String> safePaths = new Set<String>();
        Map<String, PathPart> safePathsMap = new Map<String, PathPart>();

        SafeAccessPass2() {
            super(false);
        }

        override Boolean visit(PathPart part) {
            Boolean parentAccessible = part.parent != null ? part.parent.accessible : true;
            // inaccessible parents re-cascade their inaaccessibility down towards their leaf descendants - note that this re-cascade in pass 2 is only necessary 
            // becasue of polymorphic lookups:
            if (!parentAccessible) {
                part.accessible = false;
            }
            // if this is a leaf node, and it's flagged as accessible at this point, then its full path has been determined to be accessible and we can add it to
            // the final result set:
            if (part.accessible && part.next == null) {
                //safePaths.add(part.toNormalizedPath());
                // !! Note that we return the leaf (i.e. terminating) part of the path, useful for field describe metadata:
                safePathsMap.put(part.toNormalizedPath(), part);
            }
            // again, short circuit traversal when we determine a path node to be inaccessible:
            return part.accessible;
        }
    }

    class ValueGetter extends PathVisitor {
        Boolean safeAccess = true;
        Object leafValue;
        sObject leafHolder;
        sObject[] holderStack = new sObject[]{};

        ValueGetter(sObject headHolder) {
            super(true);
            this.holderStack = new sObject[]{ headHolder };
        }

        ValueGetter safeAccess(Boolean safeAccess) {
            this.safeAccess = safeAccess == true;
            return this;
        }

        override Boolean visit(PathPart part) {
            if (part.fieldDesc != null) {
                if (safeAccess && !part.fieldDesc.isAccessible()) {
                    logSecurityMiss(part.holder, part.fieldDesc.getSObjectField(), ACCESS_READ);
                    return false;
                }
                Integer top = holderStack.size() - 1;
                sObject holder = holderStack[top];
                if (part.next == null) { // if leaf field
                    this.leafValue = holder != null ? holder.get(part.fieldDesc.getName()) : null;
                    this.leafHolder = holder;
                } else {
                    String relName = part.fieldDesc.getName().replaceFirst('(?i)Id$', '').replaceFirst('(?i)__c$', '__r');
                    holderStack.add(holder != null ? holder.getSObject(relName) : null);
                }
            }
            return true;
        }

        override void afterVisit(PathPart part) {
            if (part.fieldDesc != null) {
                if (part.next != null) { // if not leaf field
                    holderStack.remove(holderStack.size() - 1);
                }
            }
        }
    }

    // throws FieldPathException
    static void resolvePathBranch(PathPart currentPart, String[] rawParts, Integer rawIndex) { //, Map<String, Schema.sObjectType> polyLkpHints) {
        final Integer rawLen = rawParts.size();
        do {
            // MDU: Updated to automatically resolve aliases on fields and parent relationships, for use by the enhanced SOQLParser:
            String lexRaw = currentPart.lex = rawParts[rawIndex];

/* mulveling-dev
            String lexMapped = RKMock.resolveMockKey(currentPart.holder, lexRaw);
            String lex = lexMapped != null ? lexMapped : lexRaw;
*/
            String lex = lexRaw;

            Boolean isRef = rawIndex < rawLen - 1;
            // if this lex token is not he the terminating token of the path, then it must be a parent reference:
            if (isRef) {
                String lkp;
                if (lex.endsWithIgnoreCase('__r')) {
                    lkp = lex.replaceFirst('(?i)__r$', '__c');
                } else if (!lex.endsWithIgnoreCase('Id') && !lex.endsWithIgnoreCase('__c')) {
                    lkp = lex + 'Id';
                } else {
                    lkp = lex;
                }
                Schema.sObjectField lkpField = resolveField(currentPart.holder, lkp);
                if (lkpField == null) {
                    throw new FieldPathException(
                        'Reference ' + (rawIndex > 0 ? '{' + currentPart.holder + '}.' : '') + lexRaw + (rawIndex > 0 ? ', in path "' + 
                            String.join(rawParts, '.') + '",' : '') + ' does not match a parent relationship');
                }
                currentPart.fieldDesc = lkpField.getDescribe();
                if (currentPart.fieldDesc.getType() != Schema.DisplayType.REFERENCE) {
                    throw new FieldPathException(
                        'Reference ' + (rawIndex > 0 ? '{' + currentPart.holder + '}.' : '') + lexRaw + (rawIndex > 0 ? ', in path "' + 
                        String.join(rawParts, '.') + '",' : '') + ' was expected to match a parent relationship; got ' + 
                        currentPart.fieldDesc.getType().name().toLowerCase() + ' field');
                }
                Schema.sObjectType[] refTos = currentPart.fieldDesc.getReferenceTo();
                // polymorphic lookup; we have to resort to recursion to resolve every possible parent object type:
                if (refTos.size() > 1) {
                    currentPart.next = new PathPart[]{};
                    for (Schema.sObjectType refTo : refTos) {
                        PathPart altPart = new PathPart(currentPart, refTo);
                        currentPart.next.add(altPart);
                        resolvePathBranch(altPart, rawParts, rawIndex + 1);
                    }
                    // the recursion will complete resolving the paths for all alternative parent types, so when we reach here we're done with 
                    // this loop:
                    break;
                // else, single-parent type lookup; we can setup next iteration and stay in this loops without recursing:
                } else {
                    rawIndex ++;
                    PathPart nextPart = new PathPart(currentPart, refTos[0]);
                    currentPart.next = new PathPart[]{ nextPart };
                    currentPart = nextPart;
                    continue;
                }
                // unreachable...
            // else lex is the terminating token of this path (though it could still be a FieldSet!):
            } else {
                Schema.sObjectField field = resolveField(currentPart.holder, lex);
                if (field == null) {
                    Schema.FieldSet fieldSet = resolveFieldSet(currentPart.holder, lex);
                    if (fieldSet == null) {
                        if (rawIndex > 0) {
                            throw new FieldPathException(
                                'Terminating identifier ' + lexRaw + ' for path "' + String.join(rawParts, '.') + 
                                    '" does not match an existing Field or FieldSet on Object type ' + currentPart.holder);
                        } else {
                            throw new FieldPathException(
                                'Identifier ' + lexRaw + ' does not match an existing Field or FieldSet on Object type ' + currentPart.holder);
                        }
                    }
                    currentPart.fieldSet = fieldSet;
                    currentPart.next = new PathPart[]{}; //new PathPart(currentPart.head, currenPart.holder);
                    for (Schema.FieldSetMember mem : fieldSet.getFields()) {
                        PathPart recursePart = new PathPart(currentPart, currentPart.holder);
                        currentPart.next.add(recursePart);
                        String[] recurseRawParts = rawParts.clone();
                        recurseRawParts.addAll(mem.getFieldPath().split('\\.'));
                        resolvePathBranch(recursePart, recurseRawParts, rawIndex + 1);
                    }
                    // the recursion will complete resolving the paths for all alternative parent types, so when we reach here we're done with 
                    // this loop:
                    break;
                } else {
                    currentPart.fieldDesc = field.getDescribe();
                    //if (currentPart.fieldDesc == null) {
                    //    Assert.fail(
                    //            'Identifier ' + lexRaw + ' could not resolve from SObjectField to FieldDescribResult on ' + currentPart.holder);
                    //}
                    break;
                }
                // unreachable...
            }
            // unreachable...
        } while (true);
    }

    /*
    static void outErr(String prefix, Exception e) {
        if (e instanceof PathExpressionException) {
            outErr((String.isNotBlank(prefix) ? prefix + ': ' : 'Invalid field expression: ') + e.getMessage());
        } else if (e instanceof FieldPathException) {
            outErr((String.isNotBlank(prefix) ? prefix + ': ' : 'Invalid field: ') + e.getMessage());
        } else if (e instanceof sObjectException) {
            outErr((String.isNotBlank(prefix) ? prefix + ': ' : '') + e.getMessage());
        } else {
            //auraErr((String.isNotBlank(prefix) ? prefix + ' unexpected error: ' : 'Unexpected error: ') + e.getMessage());
            throw e;
        }
    }
    */

    static void outErr(Exception e) {
        if (!Test.isRunningTest()) {
            AuraHandledException ae = new AuraHandledException(e.getMessage());
            ae.setMessage(e.getMessage());
            throw ae;
        } else {
            throw e;
        }
    }

    public class PathExpressionException extends Exception {}
    public class FieldPathException extends Exception {}
    //public class SOQLBuilderException extends Exception {}
    public class sObjectException extends Exception {}

    // =======================================================================================================================================================
    // =======================================================================================================================================================

    // Use the safeUpdate/safeInsert/safeDelete methods below to perform DML insert/update/delete operations, respectively. Field-Level Security and CRUD 
    // permissions will be enforced for the context user (TODO: soon); fields for which the user is lacking createable/updateable premissions will simply 
    // be stripped from the sObject before the DML operation. Record-level sharing will be enforced unless you've explicitly turned it off via
    // RKSecurity.sharingOFF().
    
    // Use the safeInsertables/safeUpdateables alternatives below if you need to post-populate system-calculated field values, for fields which the context 
    // user might NOT have Field-Level Security access to - in this case, you will need to manaually invoke the desired DML statement on the returned 
    // sObjects.

    public static void safeUpdate(sObject[] writables) {
        Exec.doUpdate(writables);
    }

    public static void safeUpdate(sObject writable) {
        Exec.doUpdate(new sObject[]{ writable });
    }

    /*
    public static sObject[] safeUpdateables(sObject[] writables) {
        return writables;
    }

    public static sObject safeUpdateable(sObject writable) {
        return writable;
    }
    */

    public static void safeInsert(sObject[] createables) {
        Exec.doInsert(createables);
    }

    public static void safeInsert(sObject createable) {
        Exec.doInsert(new sObject[]{ createable });
    }

    /*
    public static sObject[] safeInsertables(sObject[] createables) {
        return createables;
    }

    public static sObject safeInsertable(sObject createable) {
        return createable;
    }
    */

    public static void safeDelete(sObject[] tossables) {
        Exec.doDelete(tossables);
    }

    public static void safeDelete(sObject tossable) {
        Exec.doDelete(new sObject[]{ tossable });
    }

    public static void put(sObject sobj, String fieldName, Object value) {
        Schema.sObjectField field = resolveField(sobj.getSObjectType(), fieldName);
        if (field == null) {
            try {
                throw new sObjectException('sObject put error: Field ' + fieldName + ' not found on ' + sobj.getSObjectType());
            } catch (sObjectException e) {
                outErr(e);
            }
        }
        sobj.put('' + field, value);
    }

    public static Object get(sObject sobj, String fieldPath) {
        return get(sobj, fieldPath, false);
    }

    public static Object safeAccessGet(sObject sobj, String fieldPath) {
        resetSecurityLog(true);
        Object val = get(sobj, fieldPath, true);
        throwSecurityViolations(true);
        return val;
    }

    private static Object get(sObject sobj, String fieldPath, Boolean safeAccessFlag) {
        if (sobj == null) {
            return null;
        }
        if (fieldPath.contains('.')) {
            String[] rawPathParts = fieldPath.replaceAll('\\s++', '').split('\\.');
            PathPart pathHead = new PathPart(sobj.getSObjectType());
            try {
                resolvePathBranch(pathHead, rawPathParts, 0);
                ValueGetter getter = new ValueGetter(sobj).safeAccess(safeAccessFlag);
                getter.exec(new PathPart[]{ pathHead });
                return getter.leafValue;
            } catch (FieldPathException e) {
                try {
                    throw new sObjectException('sObject get error: ' + e.getMessage());
                } catch (sObjectException se) {
                    outErr(se);
                }
            }
        } else {
            Schema.sObjectField field = resolveField(sobj.getSObjectType(), fieldPath);
            if (field == null) {
                try {
                    throw new sObjectException('sObject get error: Field ' + fieldPath + ' not found on ' + sobj.getSObjectType());
                } catch (sObjectException e) {
                    outErr(e);
                }
            }
            return sobj.get('' + field);
        }
        return null; // unreachable
    }

    private static Map<Schema.sObjectType, Map<String, Schema.RecordTypeInfo>> RecordTypeCache = new Map<Schema.sObjectType, Map<String, Schema.RecordTypeInfo>>();
    private static Map<Schema.sObjectType, Map<String, Schema.FieldSet>> FieldSetCache = new Map<Schema.sObjectType, Map<String, Schema.FieldSet>>();
    private static Map<Schema.sObjectType, Map<String, Schema.sObjectField>> FieldCache = new Map<Schema.sObjectType, Map<String, Schema.sObjectField>>();

    private static Schema.sObjectField getCachedField(Schema.sObjectType sobjType, String qualifiedFieldName) {
        Map<String, Schema.sObjectField> fMap = FieldCache.get(sobjType);
        if (fmap == null) {
            Schema.DescribeSObjectResult sDesc = sobjType.getDescribe();
            Map<String, Schema.FieldSet> fsMap = sDesc.fieldSets.getMap();
            if (fsMap == null) {
                fsMap = new Map<String, Schema.FieldSet>();
            }
            FieldSetCache.put(sobjType, fsMap);
            fMap = sDesc.fields.getMap();
            if (fMap == null) {
                fMap = new Map<String, Schema.sObjectField>();
            }
            FieldCache.put(sobjType, fMap);
        }

        // JLB - 12/12/2018 - Patch for Schema.DescribeSObjectResult.fields.getMap()
        // keys incorrectly indexing unmanaged fields by their "fully qualified" variant,
        // where the object's namespace is used in place of the field's true namespace (none).
        // Converting the resulting Schema.SObjectField token to a string reveals the correct
        // fully qualified name of the resulting token. This is used to verify that a false
        // match was not returned. Props to Mike U. for discovering this, and a few other,
        // workarounds for this annoying platform bug.
        Schema.SObjectField cachedField = fMap.get(qualifiedFieldName);
        if (cachedField != null && '' + cachedField != qualifiedFieldName) {
            return null;
        }
        return cachedField;
    }

    public static Schema.sObjectType resolveSObjectType(String typeName) {
        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.sObjectType resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedFieldSetOrRecordTypePatt.matcher(typeName);
                // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
                // it as-is:
                if (m.matches()) {
                    resolved = /*DescribeHandler.*/getGlobalDescribe().get(typeName);
                // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                // which will differ from the namespace of any install/client target org that invokes this code: 
                } else {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    //resolved = fsMap.get((ns != null ? ns + '__' : '') + fieldSetName);
                    resolved = /*DescribeHandler.*/getGlobalDescribe().get((ns != null ? ns + '__' : '') + typeName);
                }
            } else { // BIND_DYNAMIC
                resolved = /*DescribeHandler.*/getGlobalDescribe().get(typeName);
            }
        } while (resolved == null && bindStrat.size() > 0);

        return resolved;
    }

    public static Schema.sObjectType resolveSObjectTypeOrThrow(String sobjTypeName) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        return sobjType;
    }

    public static Schema.RecordTypeInfo resolveRecordType(Schema.sObjectType sobjType, String recordTypeName) {
        Map<String, Schema.RecordTypeInfo> rtMap = RecordTypeCache.get(sobjType);
        if (rtMap == null) {
            Schema.DescribeSObjectResult sDesc = sobjType.getDescribe();
            rtMap = sDesc.getRecordTypeInfosByDeveloperName();
            if (rtMap == null) {
                rtMap = new Map<String, Schema.RecordTypeInfo>();
            }
            RecordTypeCache.put(sobjType, rtMap);
        }

        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.RecordTypeInfo resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedFieldSetOrRecordTypePatt.matcher(recordTypeName);
                // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
                // it as-is:
                if (m.matches()) {
                    resolved = rtMap.get(recordTypeName);
                    // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                    // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                    // which will differ from the namespace of any install/client target org that invokes this code: 
                } else {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    resolved = rtMap.get((ns != null ? ns + '__' : '') + recordTypeName);
                }
            } else { // BIND_DYNAMIC
                resolved = rtMap.get(recordTypeName);
            }
        } while (resolved == null && bindStrat.size() > 0);

        return resolved;
    }

    public static Schema.RecordTypeInfo resolveRecordTypeOrThrow(Schema.sObjectType sobjType, String recordTypeName) {
        Schema.RecordTypeInfo rtInfo = resolveRecordType(sobjType, recordTypeName);
        if (rtInfo == null) {
            throw new ReferenceException('Invalid RecordType [' + recordTypeName + ']');
        }
        return rtInfo;
    }

    public static Schema.RecordTypeInfo resolveRecordTypeOrThrow(String sobjTypeName, String recordTypeName) {
        return resolveRecordTypeOrThrow(resolveSObjectTypeOrThrow(sobjTypeName), recordTypeName);
    }

    public static Schema.FieldSet resolveFieldSet(Schema.sObjectType sobjType, String fieldSetName) {
        Map<String, Schema.FieldSet> fsMap = FieldSetCache.get(sobjType);
        if (fsMap == null) {
            Schema.DescribeSObjectResult sDesc = sobjType.getDescribe();
            fsMap = sDesc.fieldSets.getMap();
            if (fsMap == null) {
                fsMap = new Map<String, Schema.FieldSet>();
            }
            FieldSetCache.put(sobjType, fsMap);
            //Map<String, Schema.sObjectField> fMap = sDesc.fields.getMap();
            //if (fMap == null) {
            //    fMap = new Map<String, Schema.sObjectField>();
            //}
            //FieldCache.put(sobjType, fMap);
        }

        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.FieldSet resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedFieldSetOrRecordTypePatt.matcher(fieldSetName);
                // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
                // it as-is:
                if (m.matches()) {
                    resolved = fsMap.get(fieldSetName);
                // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                // which will differ from the namespace of any install/client target org that invokes this code: 
                } else {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    resolved = fsMap.get((ns != null ? ns + '__' : '') + fieldSetName);
                }
            } else { // BIND_DYNAMIC
                resolved = fsMap.get(fieldSetName);
            }
        } while (resolved == null && bindStrat.size() > 0);

        return resolved;
    }

    public static Schema.FieldSet resolveFieldSetOrThrow(Schema.sObjectType sobjType, String fieldSetName) {
        Schema.FieldSet fSet = resolveFieldSet(sobjType, fieldSetName);
        if (fSet == null) {
            throw new ReferenceException('Invalid FieldSet [' + fieldSetName + ']');
        }
        return fSet;
    }

    public static Schema.FieldSet resolveFieldSetOrThrow(String sobjTypeName, String fieldSetName) {
        return resolveFieldSetOrThrow(resolveSObjectTypeOrThrow(sobjTypeName), fieldSetName);
    }

    public static Schema.sObjectField resolveField(Schema.sObjectType sobjType, String fieldName) {
        Map<String, Schema.sObjectField> fMap = FieldCache.get(sobjType);
        if (fMap == null) {
            Schema.DescribeSObjectResult sDesc = sobjType.getDescribe();
            //Map<String, Schema.FieldSet> fsMap = sDesc.fieldSets.getMap();
            //if (fsMap == null) {
            //    fsMap = new Map<String, Schema.FieldSet>();
            //}
            //FieldSetCache.put(sobjType, fsMap);
            fMap = sDesc.fields.getMap();
            if (fMap == null) {
                fMap = new Map<String, Schema.sObjectField>();
            }
            FieldCache.put(sobjType, fMap);
        }

        // !! Disabling the following "alternative binding" logic because it's very slow when repeated at high iterations (1000+),
        // especially due to the Pattern / Matcher it utilizes. We could wire this back in as an optional feature (explicit turn-
        // on only), but for now: configuration containing references to namespace'd entities MUST be fully qualified with the 
        // namespace prefix...
        /*
        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.sObjectField resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            
            //if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
            //    Matcher m = NamespaceQualifiedObjFieldPatt.matcher(fieldName);
            //    // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
            //    // it as-is:
            //    if (m.matches() && String.isNotBlank(m.group(1))) {
            //        resolved = fMap.get(fieldName);

                // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                // which will differ from the namespace of any install/client target org that invokes this code: 
            //    } else {
            //        String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
            //        resolved = fMap.get((ns != null ? ns + '__' : '') + fieldName);
            //    }
            //} else { // BIND_DYNAMIC
            //    resolved = fMap.get(fieldName);
            //}

            String mapKeyName = fieldName;
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedObjFieldPatt.matcher(fieldName);
                if (!m.matches() || String.isBlank(m.group(1))) {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    mapKeyName = (ns != null ? ns + '__' : '') + fieldName;
                }
            }
            // MDU - 12/12/2018:
            // Added logic to detect a bogus field map key; it has been discovered that some local-only fields on package objects (e.g. 
            // Hierarchy__c on rkqf__Template_Question__c) will be dual-keyed, in the DescribeSObjectResult.fields.getMap() result, under 
            // the package namespace'd key (e.g. 'rkqf__Hierarchy__c'), even when no such package field counterpart exists. By stringifying 
            // the sObjectField token returned from the fields map (the stringified feld path is always correct), we can determine if this 
            // key value is really legit:
            resolved = fMap.get(mapKeyName);
            if (resolved != null && '' + resolved != mapKeyName) {
                resolved = null;
            }
        } while (resolved == null && bindStrat.size() > 0);
        return resolved;
        */

        return fMap.get(fieldName);
    }

    public static Schema.sObjectField resolveFieldOrThrow(Schema.sObjectType sobjType, String fieldName) {
        Schema.sObjectField field = resolveField(sobjType, fieldName);
        if (field == null) {
            throw new ReferenceException('Invalid sObject Field [' + fieldName + '] on Object ' + sobjType);
        }
        return field;
    }

    public static Schema.sObjectField resolveFieldOrThrow(String sobjTypeName, String fieldName) {
        return resolveFieldOrThrow(resolveSObjectTypeOrThrow(sobjTypeName), fieldName);
    }

    public static Schema.DescribeFieldResult resolveFieldDescOrThrow(Schema.sObjectType sobjType, String fieldName) {
        return resolveFieldOrThrow(sobjType, fieldName).getDescribe();
    }

    // MDU: added for SOQLParser enhancements:
    public static Schema.ChildRelationship resolveChildRelFromParent(Schema.sObjectType parentType, String childRelName) {
        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.ChildRelationship resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedFieldSetOrRecordTypePatt.matcher(childRelName);
                // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
                // it as-is:
                if (m.matches()) {
                    for (Schema.ChildRelationship childRel : parentType.getDescribe().getChildRelationships()) {
                        if (childRel.getRelationshipName() == childRelName) {
                            resolved = childRel;
                            break;
                        }
                    }

                // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                // which will differ from the namespace of any install/client target org that invokes this code: 
                } else {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    for (Schema.ChildRelationship childRel : parentType.getDescribe().getChildRelationships()) {
                        if (childRel.getRelationshipName() == (ns != null ? ns + '__' : '') + childRelName) {
                            resolved = childRel;
                            break;
                        }
                    }
                }
            } else { // BIND_DYNAMIC
                for (Schema.ChildRelationship childRel : parentType.getDescribe().getChildRelationships()) {
                    if (childRel.getRelationshipName() == childRelName) {
                        resolved = childRel;
                        break;
                    }
                }
            }
        } while (resolved == null && bindStrat.size() > 0);

        return resolved;
    }

    // MDU: added for SOQLParser enhancements:
    public static Schema.ChildRelationship resolveChildRelFromParentOrThrow(Schema.sObjectType parentType, String childRelName) {
        Schema.ChildRelationship childRel = resolveChildRelFromParent(parentType, childRelName);
        if (childRel == null) {
            throw new ReferenceException('Invalid ChildRelationship [' + parentType + '.' + childRelName + ']');
        }
        return childRel;
    }

    public static Schema.ChildRelationship resolveChildRel(Schema.sObjectType childType, String lkpField) {
        // MDU: Pulled this logic in from DescribeHandler to ensure that we're using RKSecurity-style namespace binding 
        // logic everywhere:
        Schema.ChildRelationship childRel;
        Schema.sObjectField lkp = RKSecurity.resolveField(childType, lkpField);
        if (lkp == null) {
            return null;
        }
        Schema.DescribeFieldResult lkpDesc = lkp.getDescribe();
        Schema.sObjectType[] refTos = lkpDesc.getReferenceTo();
        if (refTos.size() > 1) {
            throw new ReferenceException('Child Relationship Field ' + childType + '.' + lkp + 
                ' is Polymorphic; this is not currently supported.');
        } else if (refTos == null || refTos.size() == 0) {
            throw new ReferenceException('Child Relationship Field ' + childType + '.' + lkp + 
                ' must be a Reference type; got ' + lkpDesc.getType().name() + '.');
        }
        Schema.sObjectType refTo = refTos[0];
        for (Schema.ChildRelationship childRelOnParent : refTo.getDescribe().getChildRelationships()) {
            if (childRelOnParent.getChildSObject() == childType &&
                    childRelOnParent.getField() == lkp) {
                return childRelOnParent;
            }
        }
        return null;
    }

    public static Schema.ChildRelationship resolveChildRelOrThrow(Schema.sObjectType childType, String lkpField) {
        Schema.ChildRelationship childRel = resolveChildRel(childType, lkpField);
        if (childRel == null) {
            throw new ReferenceException('Invalid Child Relationship Field [' + lkpField + '] on Object ' + childType);
        }
        return childRel;
    }

//    private static DMLExecutor Exec = new WithSharing();
    private static DMLExecutor Exec = new DMLExecutor();

//    interface DMLExecutor {
//        void doInsert(sObject[] insertables);
//        void doUpdate(sObject[] updateables);
//        void doDelete(sObject[] deleteables);
//    }

    abstract class CheckPermissions {
        Map<Schema.sObjectType, Boolean> cachedCRUD = new Map<Schema.sObjectType, Boolean>();
        Map<Schema.sObjectType, Map<String, Boolean>> cachedFLS = new Map<Schema.sObjectType, Map<String, Boolean>>();

        abstract Boolean checkCRUD(Schema.sObjectType sobjType);
        abstract Boolean checkFLS(Schema.sObjectType sobjType, String qualifiedFieldName);

        virtual Boolean checkRecordType(Schema.sObjectType sobjType, Id recordTypeId) {
            Schema.RecordTypeInfo recTypeInfo = sobjType.getDescribe().getRecordTypeInfosById().get(recordTypeId);
            return recTypeInfo != null && recTypeInfo.isAvailable() && this.checkFLS(sobjType, 'RecordTypeId');
        }
    }

    class CheckPermsRead extends CheckPermissions {
        public override Boolean checkCRUD(Schema.sObjectType sobjType) {
            Boolean ok = cachedCRUD.get(sobjType);
            if (ok == null) {
                cachedCRUD.put(sobjType, ok = sobjType.getDescribe().isAccessible());
                if (!ok) {
                    logSecurityMiss(sobjType, ACCESS_READ);
                }
            }
            return ok;
        }
        
        public override Boolean checkFLS(Schema.sObjectType sobjType, String qualifiedFieldName) {
            Map<String, Boolean> flsMap = cachedFLS.get(sobjType);
            if (flsMap == null) {
                cachedFLS.put(sobjType, flsMap = new Map<String, Boolean>());
            }
            Boolean ok = flsMap.get(qualifiedFieldName);
            if (ok == null) {
                Schema.sObjectField field = getCachedField(sobjType, qualifiedFieldName);
                if (field == null) {
                    throw new ReferenceException('Invalid sObject Field [' + qualifiedFieldName + '] on Object ' + sobjType);
                }
                flsMap.put(qualifiedFieldName, ok = field.getDescribe().isAccessible());
                if (!ok) {
                    logSecurityMiss(sobjType, getCachedField(sobjType, qualifiedFieldName), ACCESS_READ);
                }
            }
            return ok;
        }
    }

    class CheckPermsInsert extends CheckPermissions {
        public override Boolean checkCRUD(Schema.sObjectType sobjType) {
            Boolean ok = cachedCRUD.get(sobjType);
            if (ok == null) {
                cachedCRUD.put(sobjType, ok = sobjType.getDescribe().isCreateable());
                if (!ok) {
                    logSecurityMiss(sobjType, ACCESS_CREATE);
                }
            }
            return ok;
        }
        
        public override Boolean checkFLS(Schema.sObjectType sobjType, String qualifiedFieldName) {
            if (qualifiedFieldName == 'Id') {
                return true;
            }
            Map<String, Boolean> flsMap = cachedFLS.get(sobjType);
            if (flsMap == null) {
                cachedFLS.put(sobjType, flsMap = new Map<String, Boolean>());
            }
            Boolean ok = flsMap.get(qualifiedFieldName);
            if (ok == null) {
                Schema.sObjectField field = getCachedField(sobjType, qualifiedFieldName);
                // if field is a miss:
                if (field == null) {
                    if (qualifiedFieldName.endsWithIgnoreCase('__c') || qualifiedFieldName.endsWithIgnoreCase('__s') || qualifiedFieldName.endsWithIgnoreCase('Id')) {
                         throw new ReferenceException('Invalid sObject Field [' + qualifiedFieldName + '] on Object ' + sobjType);
                    }
                    // for now we simply give non-custom parent relationships, child relationshipa, and invalid fields a bypass (but not writable):
                    return false;
                    /*
                    Schema.ChildRelationship childRel = sobjType.getDescribe().getChildRelationships.get(qualifiedFieldName);
                    if (childRel == null) {
                        String lkp;
                        if (field.endsWith('__r')) {
                            lkp = field.replaceFirst('__r$', '__c');
                        } else if (!field.endsWith('__c') && !field.endsWith('__s')) {
                            lkp = field + 'Id';
                        }
                        Schema.sObjectField lkpField;
                        if (lkp != null) {
                            lkpField = getCachedField(sobjType, lkp);
                        }
                        if (lkpField == null) {
                            throw new ReferenceException('Invalid sObject Field [' + qualifiedFieldName + '] on Object ' + sobjType);
                        }
                    }
                    return false;
                    */
                }
                flsMap.put(qualifiedFieldName, ok = field.getDescribe().isCreateable());
                if (!ok) {
                    logSecurityMiss(sobjType, getCachedField(sobjType, qualifiedFieldName), ACCESS_CREATE);
                }
            }
            return ok;
        }
    }

    class CheckPermsUpdate extends CheckPermissions {
        public override Boolean checkCRUD(Schema.sObjectType sobjType) {
            Boolean ok = cachedCRUD.get(sobjType);
            if (ok == null) {
                //RKDEV-30014
                ok = (UserInfo.getUserType() == 'Guest') ? sobjType.getDescribe().isCreateable() :sobjType.getDescribe().isUpdateable();
                cachedCRUD.put(sobjType, ok);
                if (!ok) {
                    logSecurityMiss(sobjType, ACCESS_UPDATE);
                }
            }
            return ok;
        }
        
        public override Boolean checkFLS(Schema.sObjectType sobjType, String qualifiedFieldName) {
            if (qualifiedFieldName == 'Id') {
                return true;
            }
            Map<String, Boolean> flsMap = cachedFLS.get(sobjType);
            if (flsMap == null) {
                cachedFLS.put(sobjType, flsMap = new Map<String, Boolean>());
            }
            Boolean ok = flsMap.get(qualifiedFieldName);
            if (ok == null) {
                Schema.sObjectField field = getCachedField(sobjType, qualifiedFieldName);
                // if field is a miss, then try to resolve it as a parent or child relationship - otherwise it is an invalid property:
                if (field == null) {
                    if (qualifiedFieldName.endsWithIgnoreCase('__c') || qualifiedFieldName.endsWithIgnoreCase('__s') || qualifiedFieldName.endsWithIgnoreCase('Id')) {
                         throw new ReferenceException('Invalid sObject Field [' + qualifiedFieldName + '] on Object ' + sobjType);
                    }
                    // for now we simply give non-custom parent relationships, child relationshipa, and invalid fields a bypass (but not writable):
                    return false;
                }
                DescribeFieldResult fieldDesc = field.getDescribe();
                //RKDEV-29932
                ok = (UserInfo.getUserType() == 'Guest') ? fieldDesc.isCreateable() : fieldDesc.isUpdateable();
                flsMap.put(qualifiedFieldName, ok);
                // only log a security miss/violation if this update field is flagged as "isPermissionable" and is NOT an auto-number, otherwise we 
                // always silently filter it out (e.g. ContenetVersion read-only fields like COntentDocumentId and FileExtension are non-
                // permissionable; auto-number fields should always be stripped from update sObjects, etc):
                if (!ok && fieldDesc.isPermissionable() && !fieldDesc.isAutoNumber()) {
                    logSecurityMiss(sobjType, getCachedField(sobjType, qualifiedFieldName), ACCESS_UPDATE);
                }
            }
            return ok;
        }
    }

    // RKDEV-10354 - MDU: Validation failure messaging:
    public static String DMLErrorExpr = null;
    public static RowLabelResolver DMLRowLabelStrat = null;
    static String[] DMLErrorLog = new String[]{};

    public interface LabelDecorator {
        String decorate(String label);
    }

    public class PoundDecorator implements LabelDecorator {
        public String decorate(String label) {
            return String.isNotBlank(label) ? '#' + label : null;
        }
    }

    public class QuoteDecorator implements LabelDecorator {
        public String decorate(String label) {
            return String.isNotBlank(label) ? '"' + label + '"' : null;
        }
    }

    public abstract class RowLabelResolver {
        public LabelDecorator dec {get; private set;}

        RowLabelResolver() {}

        public RowLabelResolver(LabelDecorator dec) {
            this.dec = dec;
        }

        public RowLabelResolver decorator(LabelDecorator dec) {
            this.dec = dec;
            return this;
        }

        public String decorate(String label) {
            return dec != null ? dec.decorate(label) : label;
        }

        public abstract String[] getRowLabels(DMLException err);
    }

    public class NumberedRowResolver extends RowLabelResolver {
        sObject[] upserts;

        public NumberedRowResolver(sObject[] upserts) {
            super(new PoundDecorator());
            this.upserts = upserts;
        }

        public override String[] getRowLabels(DMLException err) {
            String[] labels = new String[]{};
            for (Integer i=0; i < err.getNumDml(); i++) {
                labels.add(decorate('' + (err.getDMLIndex(i) + 1)));
            }
            return labels;
        }
    }

    public class NamedInsertRowResolver extends RowLabelResolver {
        sObject[] inserts;
        String nameField;

        public NamedInsertRowResolver(sObject[] inserts, String nameField) {
            super(new QuoteDecorator());
            this.inserts = inserts;
            this.nameField = nameField;
        }

        public override String[] getRowLabels(DMLException err) {
            String[] labels = new String[]{};
            for (Integer i=0; i < err.getNumDml(); i++) {
                labels.add(decorate((String) inserts[err.getDMLIndex(i)].get(nameField)));
            }
            return labels;
        }
    }

    public class NamedUpdateRowResolver extends RowLabelResolver {
        Map<Id, sObject> updates;
        String nameField;
        Boolean doQuery = false;

        public NamedUpdateRowResolver(sObject[] updates, String nameField) {
            this(new Map<Id, sObject>(updates), nameField);
        }

        public NamedUpdateRowResolver(Map<Id, sObject> updates, String nameField) {
            super(new QuoteDecorator());
            this.updates = updates;
            this.nameField = nameField;
        }

        public NamedUpdateRowResolver doQuery(Boolean flag) {
            this.doQuery = flag == true;
            return this;
        }

        public override String[] getRowLabels(DMLException err) {
            Map<Id, sObject> readables = updates;
            if (doQuery) {
                Set<Id> scope = updates.keySet();
                // TODO: safeFilter on sObjects in case context user doesn't have read access on designated name field?
                readables = new Map<Id, sObject>(
                    Database.query(
                        'SELECT ' + nameField + 
                        ' FROM ' + updates.values()[0].getSObjectType() + 
                        ' WHERE Id IN :scope'));
            }
            String[] labels = new String[]{};
            // RKDEV-10354 - MDU: Validation failure messaging:
            for (Integer i=0; i < err.getNumDml(); i++) {
                sObject sobj = readables.get(err.getDmlId(i));
                labels.add(decorate(sobj != null ? (String) sobj.get(nameField) : null));
            }
            return labels;
        }
    }
    
    public static void resetDMLTransients() {
        DMLErrorExpr = null;
        DMLRowLabelStrat = null;
    }
    
    // RKDEV-10354 - MDU: Validation failure messaging:
    // "Cannot{OP} option{ROW}:{MSG}", where MSG is either custom validation text or "Value required for{FIELDS}"
    public static void handleDMLError(DMLException err, String dmlOp) {
        Integer unhandledRows = 0;
        String[] rowLabels = new String[err.getNumDML()];
        if (DMLRowLabelStrat != null) {
            rowLabels = DMLRowLabelStrat.getRowLabels(err);
        }
        for (Integer errIndex=0; errIndex < err.getNumDml(); errIndex++) {
            String[] fieldNames = err.getDMLFieldNames(errIndex);
            String fields;
            if (fieldNames != null && fieldNames.size() > 0) {
                fields = 'Field' + (fieldNames.size() == 1 ? '' : 's') + ': ' + String.join(fieldNames, ', ');
            }
            String msg;
            Boolean unhandled = false;
            if (err.getDmlType(errIndex) == System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
                msg = err.getDMLMessage(errIndex);
            } else if (err.getDmlType(errIndex) == System.StatusCode.REQUIRED_FIELD_MISSING) {
                msg = 'Value required for{FIELDS}';
            } else {
                unhandled = true;
            }
            DMLErrorLog.add(evalDMLExpr(String.isNotBlank(DMLErrorExpr) ? DMLErrorExpr : 'Validation error on{OP}:{MSG}', 
                dmlOp, msg, rowLabels[errIndex], fields));
            if (unhandled) {
                unhandledRows++;
            } else {
                // TODO: if current mode is to report only the 1st error, then return now...
                //break;
            }
        }
        if (unhandledRows > 0 && unhandledRows == err.getNumDml()) {
            throw err;
        } else {
            throwDMLViolations(true);
        }
    }

    // RKDEV-10354 - MDU: Validation failure messaging:
    static String evalDMLExpr(String expr, String dmlOp, String dmlMsg, String dmlRow, String dmlFields) {
        return expr
            .replace('{OP}', ' ' + dmlOp)
            .replace('{MSG}', ' ' + dmlMsg)
            .replace('{ROW}', String.isNotBlank(dmlRow) ? ' ' + dmlRow : '')
            .replace('{FIELDS}', String.isNotBlank(dmlFields) ? ' ' + dmlFields : '');
    }

    // RKDEV-10354 - MDU: Validation failure messaging:
    private static void throwDMLViolations(Boolean internalCall) {
        if (DMLErrorLog.size() > 0) {
            if (DMLErrorLog.size() > 1) {
                for (Integer i=0; i < DMLErrorLog.size(); i++) {
                    DMLErrorLog[i] = 'Error #' + (i + 1) + ': ' + DMLErrorLog[i];
                }
            }
            String msg = String.join(DMLErrorLog, ' ');
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            DMLErrorLog.clear();
            throw e;
        }
    }

    // TODO: There needs to be a cleaner way than this:
    @TestVisible
    private static void throwAccessViolation(Id recordId) {
        try {
            RKShare.accessErr(recordId);
        } catch (RKShare.AccessException ax) {
            throwAccessViolation(ax);
        }
    }

    private static void throwAccessViolation(RKShare.AccessException ax) {
        String msg = ax.getMessage();
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        throw ae;
    }
    
    class DMLExecutor {
        Boolean systemModeOneTime = false;

        void processUpsert(Boolean isInsert, sObject[] sobjs) {
            try {
                if (sobjs == null) {
                    return;
                }
                resetSecurityLog(true);
                final Boolean isUpdate = !isInsert;
                sObject[] safeObjs = new sObject[]{};
                CheckPermissions checkPerms = isInsert ? (CheckPermissions) new CheckPermsInsert() : (CheckPermissions) new CheckPermsUpdate();
                Schema.sObjectType sobjType;
                Map<Integer, Integer> srcToDestIndex = new Map<Integer, Integer>();
                for (Integer i=0; i < sobjs.size(); i++) {
                    sObject srcObj = sobjs[i];
                    if (srcObj == null) { //|| srcObj.Id != null && isInsert || srcObj.Id == null && isUpdate) {
                        continue;
                    } else if (sobjType != srcObj.getSObjectType()) {
                        sobjType = srcObj.getSObjectType();
                    }
                    if (!checkPerms.checkCRUD(sobjType)) {
                        continue;
                    }
                    sObject safeObj = isInsert ? sobjType.newSObject() : sobjType.newSObject(srcObj.Id);
                    srcToDestIndex.put(i, safeObjs.size());
                    safeObjs.add(safeObj);
                    Map<String, Object> propMap = srcObj.getPopulatedFieldsAsMap();
                    for (String prop : propMap.keySet()) {
                        if (prop == 'RecordTypeId') {
                            String rawRecTypeId = (String) propMap.get('RecordTypeId');
                            if (String.isNotBlank(rawRecTypeId)) {
                                Id recTypeId = Id.valueOf(rawRecTypeId);
                                if (checkPerms.checkRecordType(sobjType, recTypeId)) {
                                    safeObj.put('RecordTypeId', recTypeId);
                                }
                            }
                        } else {
                            // ignore properties that look like parent or child relationships:
                            if (prop.endsWith('__r')) { //|| prop.endsWith('__s') || !prop.endsWith('__c') && !prop.endsWith('Id')) {
                                continue;
                            } else if (checkPerms.checkFLS(sobjType, prop)) {
                                safeObj.put(prop, propMap.get(prop));
                            }
                        }
                    }
                }
                if (safeObjs.size() > 0) {
                    if (isInsert) {
                        try {
                            //insert safeObjs;
                            (systemModeOneTime == true ? SystemSharingModel : SafeSharingModel).doInsert(safeObjs);
                        } catch (DMLException err) {
                            handleDMLError(err, 'Insert');
                        } catch (RKShare.AccessException ax) { 
                            throwAccessViolation(ax);
                        } finally {
                            resetDMLTransients();
                        }
                        for (Integer srcIndex : srcToDestIndex.keySet()) {
                            Integer destIndex = srcToDestIndex.get(srcIndex);
                            sobjs[srcIndex].put('Id', safeObjs[destIndex].Id);
                        }
                    } else {
                        try {
                            //update safeObjs;
                            (systemModeOneTime == true ? SystemSharingModel : SafeSharingModel).doUpdate(safeObjs);
                        } catch (DMLException err) {
                            handleDMLError(err, 'Update');
                        } catch (RKShare.AccessException ax) { 
                            throwAccessViolation(ax);
                        } finally {
                            resetDMLTransients();
                        }
                    }
                }
                //sobjs.clear();
                //sobjs.addAll(safeObjs);
                throwSecurityViolations(true);
            } finally {
                this.systemModeOneTime = false;
            }
        }

        public void doInsert(sObject[] sobjs) {
            processUpsert(true, sobjs);
        }
        
        public void doUpdate(sObject[] sobjs) {
            processUpsert(false, sobjs);
        }
        
        public void doDelete(sObject[] sobjs) {
            try {
                if (sobjs == null) {
                    return;
                }
                resetSecurityLog(true);
                sObject[] safeObjs = new sObject[]{};
                Schema.sObjectType sobjType;
                Schema.DescribeSObjectResult sobjDesc;
                Map<Schema.sObjectType, Boolean> checkedCrud = new Map<Schema.sObjectType, Boolean>();
                for (Integer i=0; i < sobjs.size(); i++) {
                    sObject srcObj = sobjs[i];
                    if (srcObj == null || srcObj.Id == null) {
                        continue;
                    } else if (sobjType != srcObj.getSObjectType()) {
                        sobjType = srcObj.getSObjectType();
                        sobjDesc = sobjType.getDescribe();
                    }
                    Boolean crudOk = checkedCrud.get(sobjType);
                    if (crudOk == null) {
                        // Original CRUD check:
                        //checkedCrud.put(sobjType, crudOk = sobjDesc.isDeletable());
                        
                        // RKDEV-31007 JAK and MDU: bypass this secondary CRUD check below if designated user is active
                        // when designated user is active, this list of sobjs have already been confirmed as available for the operation
                        //checkedCrud.put(sobjType, crudOk = (systemModeOneTime == true ? SystemSharingModel : SafeSharingModel).isDesignatedUserActive() || sobjDesc.isDeletable());
                        
                        // RKDEV-33886 MDU: CRUD checks should be fully bypassed when system mode is engaged:
                        checkedCrud.put(sobjType, crudOk = systemModeOneTime == true || SafeSharingModel.isDesignatedUserActive() || sobjDesc.isDeletable());
                    }
                    if (crudOk) {
                        safeObjs.add(srcObj);
                    } else {
                        logSecurityMiss(sobjType, ACCESS_DELETE);
                    }
                }
                if (safeObjs.size() > 0) {
                    try {
                        //delete safeObjs;
                        (systemModeOneTime == true ? SystemSharingModel : SafeSharingModel).doDelete(safeObjs);
                    } catch (DMLException err) {
                        handleDMLError(err, 'Delete');
                    } catch (RKShare.AccessException ax) { 
                        throwAccessViolation(ax);
                    } finally {
                        resetDMLTransients();
                    }
                }
                //sobjs.clear();
                //sobjs.addAll(safeObjs);
                throwSecurityViolations(true);
            } finally {
                this.systemModeOneTime = false;
            }
        }
    }

    public class ReferenceException extends Exception {}

    // ==============================================================================================================================================
    // Old DescribeHandler class:

    public class InvalidParameterException extends Exception {}
    public class NoMatchingSObjectTypeException extends Exception {}
    public class NoMatchingFieldException extends Exception {}
    public class NoMatchingFieldSetException extends Exception {}
    public class DescribeLookupException extends Exception {}

    private static Map<String, Schema.SObjectType> globalDescribe;
    private static Map<String, Schema.ChildRelationship> childRelationships = new Map<String, Schema.ChildRelationship>();

    public static NoMatchingSObjectTypeException noMatchingSObjectTypeException(String sObjectType) {
        return new NoMatchingSObjectTypeException('No sObjectType found by name "' + sObjectType + '".');
    }
    public static NoMatchingFieldException noMatchingFieldException(String sObjectType, String field) {
        return new NoMatchingFieldException('No field found by name "' + sObjectType + '.' + field + '".');
    }
    public static NoMatchingFieldSetException noMatchingFieldSetException(String sObjectType, String fieldSet) {
        return new NoMatchingFieldSetException('No fieldset found by name "' + sObjectType + '.' + fieldSet + '".');
    }
    public static InvalidParameterException invalidParameterException(String paramName, String paramValue, String paramInvalidMsg) {
        return new InvalidParameterException('Invalid [' + paramName + ']: ' + paramValue + ', ' + paramInvalidMsg);
    }
    
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
        Schema.DescribeSObjectResult sObjectDescribe = getSObjectDescribe(sObjectName);
        String sObjectProperName = sObjectDescribe.getName().toLowerCase();
        Integer namespaceEnd = sObjectProperName.indexOf(sObjectDescribe.getLocalName().toLowerCase());
        if (namespaceEnd > -1) {
            return sObjectProperName.substring(0, namespaceEnd);
        }
        return '';
    }

    public static Schema.SObjectField getSObjectField(String sObjectName, String fieldName) {
        return getSObjectDescribe(sObjectName).fields.getMap().get(fieldName);
    }

    public static Schema.SObjectField[] getSObjectFields(String sObjectName) {
        return getSObjectDescribe(sObjectName).fields.getMap().values();
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
        return getGlobalDescribe().get(sObjectName).getDescribe().fields.getMap().get(fieldName.replaceFirst('__r$', '__c')).getDescribe();
    }

    public static Boolean isEncrypted(String sObjectName, String fieldName) {
        return getFieldDescribe(sObjectName, fieldName).isEncrypted();
    }

    public static Schema.PicklistEntry[] getPicklistValues(String sObjectName, String fieldName) {
        return getFieldDescribe(sObjectName, fieldName).getPicklistValues();
    }

    public static String[] getReferenceTo(String sObjectName, String fieldName) {
        String[] referenceTos = new String[]{};
        Schema.SObjectType[] referenceTosRAW = getFieldDescribe(sObjectName, fieldName).getReferenceTo();
        for (Schema.SObjectType referenceToRAW : referenceTosRAW) {
            referenceTos.add(String.valueOf(referenceToRAW).toLowerCase());
        }
        return referenceTos;
    }

    public static Map<String, Schema.FieldSet> getFieldSetDescribes(String sObjectName) {
        Map<String, Schema.FieldSet> fieldSets = new Map<String, Schema.FieldSet>();
        Map<String, Schema.FieldSet> fieldSetsRAW = getSObjectDescribe(sObjectName).fieldSets.getMap();
        for (String fieldSetName : fieldSetsRAW.keySet()) {
            fieldSets.put(fieldSetName.toLowerCase(), fieldSetsRAW.get(fieldSetName));
        }
        return fieldSets;
    }

    public static Schema.FieldSet getFieldSetDescribe(String sObjectName, String fieldSetName) {
        return getFieldSetDescribes(sObjectName).get(fieldSetName.toLowerCase());
    }

    public static Map<String, Schema.FieldSetMember> getFieldSetFields(String sObjectName, String fieldSetName) {
        Map<String, Schema.FieldSetMember> fieldSetFields = new Map<String, Schema.FieldSetMember>();
        Schema.FieldSet fieldSet = getFieldSetDescribe(sObjectName, fieldSetName);
        for (Schema.FieldSetMember fieldSetField : fieldSet.getFields()) {
            fieldSetFields.put(fieldSetField.getFieldPath().toLowerCase(), fieldSetField);
        }
        return fieldSetFields;
    }

    public static String[] getOrderedFieldSetFieldNames(String sObjectName, String fieldSetName) {
        Schema.FieldSet fieldSet = getFieldSetDescribe(sObjectName, fieldSetName);
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
            Schema.ChildRelationship[] childRelsOnObject = getSObjectDescribe(sObjectName).getChildRelationships();
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

    // Polymorphic relationships unsupported - for now
    public static Schema.ChildRelationship getChildRelationshipFromRelationship(String childSObjectName, String relationshipField) {
        String cacheKey = 'fromchild.' + (childSObjectName + '.' + relationshipField).toLowerCase();

        Schema.ChildRelationship childRel = childRelationships.get(cacheKey);

        if (childRel == null) {
            String[] referenceTos = getReferenceTo(childSObjectName, relationshipField);
            if (referenceTos.size() > 1) {
                throw invalidParameterException('Relationship Field', childSObjectName + '.' + relationshipField, 'Polymorphic relationships are not currently supported.');
            }

            String referenceTo = referenceTos[0];
            Schema.ChildRelationship[] childRelsOnParent = getSObjectDescribe(referenceTo).getChildRelationships();
            for (Schema.ChildRelationship childRelOnParent : childRelsOnParent) {

                // May need some additional logic here to support partial vs fully qualified entity names
                if (String.valueOf(childRelOnParent.getChildSObject()).equalsIgnoreCase(childSObjectName) &&
                    String.valueOf(childRelOnParent.getField()).equalsIgnoreCase(relationshipField)) {
                    childRel = childRelOnParent;
                    childRelationships.put(cacheKey, childRel);
                    childRelationships.put((referenceTo + '.' + String.valueOf(childRelOnParent.getRelationshipName())).toLowerCase(), childRel);
                    break;
                }
            }
        }

        return childRel;
    }
    
    //Added by Raghil
    // TODO:
    //public static final Vobj.SchemaDesc DefaultSchema = Vobj.getSchema(null, Schema.RKUX_Mock_Object__c.sObjectType);
    public static final Vobj.SchemaDesc DefaultSchema = Vobj.getSchema(null, Schema.System_Component__c.sObjectType);

    private static Vobj.SchemaDesc[] SchemaStack;
    private static Integer SchemaStackTop = 0;
    private static Integer SchemaStackLen;
    static {
        SchemaStack = new Vobj.SchemaDesc[]{ DefaultSchema, null, null, null, null };
        SchemaStackLen = SchemaStack.size();
    }
    
    public static void setSchema(Vobj.SchemaDesc schemaToEnact) {
        if (++SchemaStackTop == SchemaStackLen) {
            SchemaStack.add(schemaToEnact);
            SchemaStackLen++;
        } else {
            SchemaStack[SchemaStackTop] = schemaToEnact;
        }
    }
    
    public static void revertSchema() {
        if (--SchemaStackTop < 0) {
            SchemaStackTop = 0;
        }
    }

    public static Vobj.SchemaDesc getActiveSchema() {
        return SchemaStack[SchemaStackTop];
    }
    
    public static String getNamespace(Schema.sObjectType packageObject) {
        String qualifiedName = '' + packageObject;
        Matcher m = NamespaceQualifiedObjFieldPatt.matcher(qualifiedName);
        if (m.matches()) {
            return m.group(1);
        }
        return null;
    }
    
    public static Map<String, Object> filterSObject(Vobj.SchemaDesc V, SObject record) {
        resetSecurityLog(true);
        Map<String, Object> res = filterSObject(V, record, new Id[]{});
        throwSecurityViolations(true);
        return res;
    }
    
    public static Map<String, Object> filterSObject(Vobj.SchemaDesc V, SObject record, Id[] refStack) {
        return filterSObject(V, record, refStack, null);
    }
    
    public static Map<String, Object> filterSObject(Vobj.SchemaDesc V, SObject record, Id[] refStack, RKSecurity.DataMirrorMode dataMirrorMode) {
        if (record.Id != null) {
            Integer refRepCount = 0;
            for (Id refId : refStack) {
                if (refId == record.Id) {
                    if (++refRepCount > 1) {
                        return new Map<String, Object>{ 'Id' => record.Id };
                    }
                }
            }
        }
        Integer stackTop = refStack.size();
        // if we got a non-null SchemaDesc argument this call, and this is the root call (i.e. not recursive), then set it:
        final Boolean enactSchemaDesc = V != null; //stackTop == 0 && V != null;
        if (enactSchemaDesc) {
            RKSecurity.setSchema(V);
        } else {
            V = SchemaStack[SchemaStackTop];
        }
        Map<String, Object> normalizedFields = new Map<String, Object>();
        try {
            final String maskingNamespace = V.maskingNamespace;
            // Push this record Id onto the reference stack
            refStack.add(record.Id);
            //final String packageNamespace = ActiveMaskingNamespace; //getPackageNamespace();
            Map<String, Object> recordFields = record.getPopulatedFieldsAsMap();
            for (String fieldName : recordFields.keySet()) {
                // inline logic from stripThisNamespace() to parse out an explicit namespace from the base API name:
                Matcher m = ObjFieldPatt.matcher(fieldName);
                String entityNamespace;
                //String strippedFieldName = fieldName;
                String pkgUnqualifiedName = fieldName;
                String checkPackageMaskingEntity;
                if (m.matches()) {
                    entityNamespace = m.group(1);
                    // if this entity carries an explicit namespace that matches the package namespace, then derive the base API name and store this into
                    // `strippedFieldName`: 
                    if (String.isNotBlank(entityNamespace) && maskingNamespace != null && entityNamespace == maskingNamespace) {
                        pkgUnqualifiedName = m.group(2);
                    }
                    // if this entity carries no explicit namespace (i.e. org deafult namespace), then we check to see if there is a package version with the same
                    // base API name; in that case the latter package entity will "mask" the local non-namespaced entity in order to fully replicate the behavior
                    // of dynamic Apex (Database.query, sObject.get/put) running in package code:
                    if (String.isBlank(entityNamespace) && maskingNamespace != null) {
                        checkPackageMaskingEntity = maskingNamespace + '__' + fieldName;
                    }
                }
                Object fieldValue = recordFields.get(fieldName);
                Object qualifiedFieldValue, unqualifiedFieldValue;
                
                // Could use pattern matching for __r vs __c here to detect fields/child rels,
                // but that would require additional edge case checking for child rels on standard lookup fields.
                // Erred on the side of dynamic type checking instead to handle all cases in one go.
                Boolean pkgUnqualifiedOnly = false;
                if (fieldValue instanceof List<SObject>) {
                    // First step, attempt to retrieve the ChildRel definition via direct matching
                    // Schema.ChildRelationship childRel = resolveChildRel(record.getSObjectType(), fieldName);
                    Schema.ChildRelationship childRel = DescribeHandler.getChildRelationship(String.valueOf(record.getSObjectType()), fieldName);

                    // Second step, check if there is a matching child rel definition on the target record that resides under
                    // the masking namespace
                    // if (checkPackageMaskingEntity != null && resolveChildRel(record.getSObjectType(), checkPackageMaskingEntity) != null) {
                    //     continue;
                    // }
                    if (checkPackageMaskingEntity != null &&
                        DescribeHandler.getChildRelationship(String.valueOf(record.getSObjectType()), checkPackageMaskingEntity) != null
                    ) {
                        continue;
                    }

                    System.debug('childRel is:'+childRel);
                    System.debug('record.getSObjectType is:'+record.getSObjectType());
                    System.debug('fieldName is:'+fieldName);
                    // Check for read access on related object
                    if (!ReadChecker.checkCRUD(childRel.getChildSObject())) {
                        continue;
                    }

                    // Check for read access on lookup field (on child)
                    if (!ReadChecker.checkFLS(childRel.getChildSObject(), childRel.getField().getDescribe().getName())) {
                        continue;
                    }

                    // Make sure the original child rel list is normalized as well
                    //pkgUnqualifiedOnly = !FilterSObject_NSMirrorChildAndParentRels;
                    //fieldValue = filterSObject((List<SObject>) fieldValue, refStack);

                    if (dataMirrorMode == null || dataMirrorMode == RKSecurity.DataMirrorMode.Qualified) {
                        // recursive calls will pull from SchemaDesc from SchemaStack[SchemaStackTop]:
                        qualifiedFieldValue = filterSObject(null, (List<SObject>) fieldValue, refStack, RKSecurity.DataMirrorMode.Qualified);
                    }
                    if (dataMirrorMode == null || dataMirrorMode == RKSecurity.DataMirrorMode.UnQualified) {
                        // recursive calls will pull from SchemaDesc from SchemaStack[SchemaStackTop]:
                        unqualifiedFieldValue = filterSObject(null, (List<SObject>) fieldValue, refStack, RKSecurity.DataMirrorMode.UnQualified);
                    }
                } else if (fieldValue instanceof SObject) {
                    // Ensure read access on lookup field
                    String lkp = fieldName.replaceFirst('__r$', '__c');
                    if (!lkp.endsWith('__c')) {
                        lkp = lkp + 'Id';
                    }
                    if (!ReadChecker.checkFLS(record.getSObjectType(), lkp)) {
                        continue;
                    }
                    // Check for a masking lookup in the package:
                    if (checkPackageMaskingEntity != null && 
                            getCachedField(record.getSObjectType(), maskingNamespace + '__' + lkp) != null) {
                        continue;
                    }

                    // Ensure read access on related object/s
                    //String[] relatedTypes = DescribeHandler.getReferenceTo(String.valueOf(record.getSObjectType()), fieldName);
                    // TODO - review:
                    Schema.sObjectType[] relatedTypes = resolveFieldOrThrow(record.getSObjectType(), lkp).getDescribe().getReferenceTo();

                    // Replace with labeled loop?
                    Boolean hasAccessToAll = true;
                    //for (String relatedType : relatedTypes) {
                    for (Schema.sObjectType relatedType : relatedTypes) {
                        //if (!ReadChecker.checkCRUD(DescribeHandler.getSObjectType(relatedType))) {
                        if (!ReadChecker.checkCRUD(relatedType)) {
                            hasAccessToAll = false;
                            break;
                        }
                    }
                    if (!hasAccessToAll) {
                        continue;
                    }
                    //pkgUnqualifiedOnly = !FilterSObject_NSMirrorChildAndParentRels;
                    //fieldValue = filterSObject((SObject) fieldValue, refStack);
                    
                    if (dataMirrorMode == null || dataMirrorMode == RKSecurity.DataMirrorMode.Qualified) {
                        // recursive calls will pull from SchemaDesc from SchemaStack[SchemaStackTop]:
                        qualifiedFieldValue = filterSObject(null, (SObject) fieldValue, refStack, RKSecurity.DataMirrorMode.Qualified);
                    }
                    if (dataMirrorMode == null || dataMirrorMode == RKSecurity.DataMirrorMode.UnQualified) {
                        // recursive calls will pull from SchemaDesc from SchemaStack[SchemaStackTop]:
                        unqualifiedFieldValue = filterSObject(null, (SObject) fieldValue, refStack, RKSecurity.DataMirrorMode.UnQualified);
                    }
                } else {
                    if (!ReadChecker.checkFLS(record.getSObjectType(), fieldName)) {
                        // No read access at field level (primitive value type, not related record or child rel)
                        continue;
                    }
                    // Check for a masking field in the package:
                    if (checkPackageMaskingEntity != null && 
                            getCachedField(record.getSObjectType(), checkPackageMaskingEntity) != null) {
                        continue;
                    }

                    qualifiedFieldValue = fieldValue;
                    unqualifiedFieldValue = fieldValue;
                }

                // Re-Place the cleaned field value under the original field name, and the non-namespaced field name
                /*if (!pkgUnqualifiedOnly) {
                    normalizedFields.put(fieldName, fieldValue);
                }*/
                // Save a bit of processing power here if the "stripped" name was unaffected
                /*if (pkgUnqualifiedOnly || pkgUnqualifiedName != fieldName) {
                    normalizedFields.put(pkgUnqualifiedName, fieldValue);
                }*/

                // JLB - Updated to facilitate new data mirror technique
                if (dataMirrorMode == null || dataMirrorMode == RKSecurity.DataMirrorMode.Qualified) {
                    normalizedFields.put(fieldName, qualifiedFieldValue);
                }
                if (dataMirrorMode == null || dataMirrorMode == RKSecurity.DataMirrorMode.UnQualified) {
                    normalizedFields.put(pkgUnqualifiedName, unqualifiedFieldValue);
                }
            }
        } finally {
            //// Apply mock bindings if applicable
            //RKMock.applyMockBindings(record.getSObjectType(), normalizedFields);
            V.applyAliasesShallow(record.getSObjectType(), normalizedFields);
            // Pop this record Id off the reference stack
            while (refStack.size() > stackTop) {
                refStack.remove(stackTop);
            }
            // if we set a passed-in SchemaDesc, then revert it now:
            if (enactSchemaDesc) {
                RKSecurity.revertSchema();
            }
        }

        return normalizedFields;
    }
    
    private static List<Map<String, Object>> filterSObject(Vobj.SchemaDesc V, SObject[] records, Id[] refStack, RKSecurity.DataMirrorMode dataMirrorMode) {
        List<Map<String, Object>> filteredRecords = new List<Map<String, Object>>();
        if (records != null) {
            for (SObject record : records) {
                filteredRecords.add(filterSObject(V, record, refStack, dataMirrorMode));
            }
        }
        return filteredRecords;
    }
    
    public static List<Map<String, Object>> filterSObject(Vobj.SchemaDesc V, SObject[] records) {
        resetSecurityLog(true);
        List<Map<String, Object>> res = filterSObject(V, records, new Id[]{});
        throwSecurityViolations(true);
        return res;
    }
    
    private static List<Map<String, Object>> filterSObject(Vobj.SchemaDesc V, SObject[] records, Id[] refStack) {
        return filterSObject(V, records, refStack, null);
    }
    //End: Raghil
}