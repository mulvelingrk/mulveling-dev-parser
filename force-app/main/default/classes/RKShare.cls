/*
    NOTE: This utility does not account for CRUD/FLS security.
        It ONLY accounts for record-level access by User/Entity.
        CRUD/FLS should be handled outside of this utility, prior to calling
        into this utility.

    Tuned specifically for scenarios that could occur in QF or Portal Framework.

        Some example scenarios:
            Questionnaire_Form__c
                * Should be able to Create/Read/Update
                * Config:
                    * Add sharing rule for read-only access
                    * Configure profile to allow Create/Read/Update

            Question_Response__c
                * Should be able to Create/Read/Update
                * Config:
                    * Add sharing rule for read-only access
                    * Configure profile to allow Create/Read/Update

            rkl__RK_Hierarchy_Node__c
                * Should be able to Read
                * Config:
                    * Add sharing rule for read-only access
                    * Configure profile to allow Read

            Contact
                * Should be able to Read
                * Config:
                    * Add sharing rule for read-only access
                    * Configure profile to allow Read


        Controlling access is two-fold:
            * Use sharing rules to enable/disable Guest user access on a per-object basis
                * Sharing rule formula can be tuned to restrict access further if necessary.
                    For most scenarios, all-or-nothing record-level access will be sufficient.
            * Use Profile config to restrict Create/Read/Update/Delete access


        Technical Specifications - Related to Above Config Requirements
            * C/R/U/D access
                * Already handled by RKSecurity
                * Distinction between "Public Read Only" and "Public Read Write" is handled here
            * Enable/Disable access to Guest user via Sharing Rules
                * Handled by RKShare
                    * Create
                        * Always allowed (Assuming C enabled at Profile level)
                    * Read/Update/Delete
                        * Only allowed if UserRecordAccess table lists "Read" access to target record/s


        === BONUS ===
        Planned Enhancement - Emulate Entity<->Record Access for Non-User Entities (Contact, Employee__c, etc)
            * Improved security for products relying on Guest user with custom auth layer
            * High-Level Goals
                * Sharing Access Per Object
                    * Private
                        * C/R/U/D access for owners
                        * C access for others
                    * Public Read Only
                        * C/R/U/D access for owners
                        * C/R access for others
                    * Public Read/Write
                        * C/R/U/D access for owners
                        * C/R/U access for others
                    * Public Full Access
                        * C/R/U/D access for all

                    * Selective access using direct share table? (Complex, High Performance Impact)

                * Sharing Access Rules Grouped and Swappable
                    * Allows for separate configuration per-application or per-environment

                * Sharing Rules and Groups Deployable

            * Requirements Breakdown
                * Deployable storage of access level per object
                * Deployable storage of grouped access levels per object
                * Configuration UI for Access Levels and Groupings (Accessible via Classic and Lightning)
                * Storage of access b/w Entity<->Record

            * Technical Specifications
                * Data-Model
                    * Custom Metadata Types
                        * RKSharing_Profile__mdt
                            * Groups sharing settings by name
                        * RKSharing_Setting__mdt
                            * Stores sharing model per-object

                    * Custom Objects
                        * RKSharing_Access__c
                            * Stores Entity<->Record access per-profile

                    * LWC
                        * Profile/Setting Editor UI (Lightning)

                    * VisualForce
                        * Lightning Out -> LWC UI (Classic)

                    * Apex
                        * RKShare
                            * Interfaces for DML and SOQL
                            * Swappable implementation for UserRecordAccess vs RKSharing_Access__c
                            * Swappable implementation for resolving entity id
                                * Use built-in implementation for resolving standard User object
                                * Use external implementation for custom auth


    TODOS:
        * Check all class/method accessors. Reduce to minimum required.
        * Write test code (moreso for custom sharing)
*/
public without sharing virtual class RKShare {
    //Extension of bind pool max sharing size so that efficiency reaches 2n rules (RKDEV-15099)
    public static final Integer MAX_FILTER_SIZE = 3000; //RKDEV-32328

    public static SOQLParser.LocalReBindPool mintReBindPool() {
        return new SOQLParser.LocalReBindPool('RKShare');
    }

    private static RKShare.SecurityModel SafeSharing;
    private static RKShare.SecurityModel SystemSharing;
    private static RKShare.SecurityModel PlatformSharing;

    public static SecurityModel SafeSharing() {
        if (SafeSharing != null) {
            return SafeSharing;
        }
/* mulveling-dev
        return SafeSharing = isGuestUser ? (SecurityModel) new WithoutPlatformSharing(siteCustomAccess()) : (SecurityModel) new WithPlatformSharing();
*/
        return SafeSharing = (SecurityModel) new WithPlatformSharing();
    }

    public static SecurityModel SystemSharing() {
        if (SystemSharing != null) {
            return SystemSharing;
        }
        return SystemSharing = new WithoutPlatformSharing(null);
    }

    public static SecurityModel PlatformSharing() {
        if (PlatformSharing != null) {
            return PlatformSharing;
        }
        return PlatformSharing = new WithPlatformSharing();
    }

    // TODO: Determine if we'd rather pass in an RKShare_Profile__mdt name, and store the AuthResolver class name as a field on that object
    //public static RKShare customSharing(AuthResolver authResolver, String profileName) {
    //    return new RKShare(new CustomAccessResolver(authResolver, profileName));
    //}

    public interface SecurityModel {
		
        // RKDEV-31007 JAK and MDU: uses AccessResolver to determine if Designated User is active
        Boolean isDesignatedUserActive();
        
        Boolean hasCustomAccess();

        Set<Id> filterReadable(Set<Id> scope);

        SObject[] query(String soql, SOQLParser.LocalReBindPool reBindPool);

        Integer countQuery(String soql, SOQLParser.LocalReBindPool reBindPool);

        Database.QueryLocator getQueryLocator(String soql, SOQLParser.LocalReBindPool reBindPool);

        SObject[] doInsert(SObject[] records);

        SObject[] doUpdate(SObject[] records);

        SObject[] doUpdate(SObject[] records, Boolean checkTransfer);
        
        void doDelete(SObject[] records);
    }

    public without sharing class WithoutPlatformSharing implements SecurityModel {
        // Custom access checks
        public AccessResolver customAccess;

        public WithoutPlatformSharing(AccessResolver customAccess) {
            this.customAccess = customAccess;
        }
        
         // RKDEV-31007 JAK and MDU: Without PlatformSharing needs to use AccessResolver to determine if Designated User is active
        public Boolean isDesignatedUserActive(){
            return customAccess != null ? customAccess.isDesignatedUserActive() : false;
        }

        public Boolean hasCustomAccess() {
            return customAccess != null;
        }

        public Set<Id> filterReadable(Set<Id> scope) {
            return (this.customAccess != null ? this.customAccess : StandardPlatformAccess()).filterReadable(scope);
        }

        public SObject[] query(String soql, SOQLParser.LocalReBindPool reBindPool) {
            SOQLParser.assertReBindCompatibility(reBindPool, RKShare.mintReBindPool());
            sObject[] recs0 = reBindPool.getRecArray(0);
            sObject[] recs1 = reBindPool.getRecArray(1);
            sObject[] recs2 = reBindPool.getRecArray(2);

            Id[] ids0 = reBindPool.getIdArray(0);
            Id[] ids1 = reBindPool.getIdArray(1);
            Id[] ids2 = reBindPool.getIdArray(2);

            String[] strs0 = reBindPool.getStrArray(0);
            String[] strs1 = reBindPool.getStrArray(1);
            String[] strs2 = reBindPool.getStrArray(2);
            
            sObject[] results = Database.query(soql);
            if (customAccess != null) {
                Set<Id> scope = new Set<Id>();
                for (sObject rec : results) {
                    // TODO: What to do about parent and child records returned by SOQL queries??
                    // Ideally this needs to be handled by SOQLParser, which would know metadata 
                    // on the SELECT'd relationships. However, it would still be a challenge to 
                    // filter out the parent and child relationships from query-returned sObjects.
                    // A better integration with VirtualObjects may allow a more complete solution 
                    // to the parent & child record security issue. For now, I think we'll have to
                    // stick with just filtering the primary records (ignore parents & children).
                    scope.add(rec.Id);
                }
                Set<Id> readables = customAccess.filterReadable(scope);
                sObject[] filtered = new sObject[]{};
                for (sObject rec : results) {
                    if (readables.contains(rec.Id)) {
                        filtered.add(rec);
                    }
                }
                return filtered;
            } else {
                return results;
            }
        }

        public Integer countQuery(String soql, SOQLParser.LocalReBindPool reBindPool) {
            if (customAccess != null) {
                accessErr('Cannot use custom access in conjunction with count SOQL query');
            }

            SOQLParser.assertReBindCompatibility(reBindPool, RKShare.mintReBindPool());
            sObject[] recs0 = reBindPool.getRecArray(0);
            sObject[] recs1 = reBindPool.getRecArray(1);
            sObject[] recs2 = reBindPool.getRecArray(2);

            Id[] ids0 = reBindPool.getIdArray(0);
            Id[] ids1 = reBindPool.getIdArray(1);
            Id[] ids2 = reBindPool.getIdArray(2);

            String[] strs0 = reBindPool.getStrArray(0);
            String[] strs1 = reBindPool.getStrArray(1);
            String[] strs2 = reBindPool.getStrArray(2);
            
            return Database.countQuery(soql);
        }

        public Database.QueryLocator getQueryLocator(String soql, SOQLParser.LocalReBindPool reBindPool) {
            if (customAccess != null) {
                accessErr('Cannot use custom access in conjunction with SOQL QueryLocator');
            }

            SOQLParser.assertReBindCompatibility(reBindPool, RKShare.mintReBindPool());
            sObject[] recs0 = reBindPool.getRecArray(0);
            sObject[] recs1 = reBindPool.getRecArray(1);
            sObject[] recs2 = reBindPool.getRecArray(2);
    
            Id[] ids0 = reBindPool.getIdArray(0);
            Id[] ids1 = reBindPool.getIdArray(1);
            Id[] ids2 = reBindPool.getIdArray(2);
    
            String[] strs0 = reBindPool.getStrArray(0);
            String[] strs1 = reBindPool.getStrArray(1);
            String[] strs2 = reBindPool.getStrArray(2);
            
            return Database.getQueryLocator(soql);
        }

        public SObject[] doInsert(SObject[] records) {
            insert records;
            return records;
        }

        public SObject[] doUpdate(SObject[] records) {
            return doUpdate(records, false);
        }

        public SObject[] doUpdate(SObject[] records, Boolean checkTransfer) {
            if (this.customAccess != null) {
                Id[] recordIds = getRecordIds(records);
                // assert updateable:
                checkMultiResponse(recordIds, this.customAccess.hasEdit(recordIds));
                if (checkTransfer == true) {
                    Id[] transferCandidateIds = new Id[]{};
                    Map<Id, Map<String, Object>> transferCandidateKeyVals = new Map<Id, Map<String, Object>>();
                    for (SObject record : records) {
                        // TODO: Review
                        // MDU: If record was returned from a SOQL query that did not SELECT OwnerId, then pulling its field 
                        // value will result in a QueryException - it's safer to get a generic map of key/value pairs and look
                        // for OwnerId there, but of course this will eat up CPU.
                        Map<String, Object> keyValuePairs = record.getPopulatedFieldsAsMap();
                        Id newOwnerId = (Id) keyValuePairs.get('OwnerId');
                        if (newOwnerId != null) {
                            transferCandidateIds.add(record.Id);
                            transferCandidateKeyVals.put(record.Id, keyValuePairs);
                        }
                    }

                    if (transferCandidateIds.size() > 0) {
                        Id[] transferIds = new Id[]{};
                        // TODO: Could some standard sObjectTypes not have an OwnerId field? Then this query would fail:
                        Map<Id, SObject> oldRecordsById = new Map<Id, SObject>(Database.query(
                            'SELECT OwnerId FROM ' + records[0].getSObjectType() +
                            ' WHERE Id IN: transferCandidateIds'
                        ));

                        //Map<Id, SObject> newRecordsById = new Map<Id, SObject>(records);

                        for (Id transferId : transferIds) {
                            Map<String, Object> newKeyValuePairs = transferCandidateKeyVals.get(transferId);
                            SObject oldRecord = oldRecordsById.get(transferId);
                            //SObject newRecord = newRecordsById.get(transferId),
                            //    oldRecord = oldRecordsById.get(transferId);

                            //if (newRecord.OwnerId != oldRecord.OwnerId) {
                            if (newKeyValuePairs.get('OwnerId') != oldRecord.get('OwnerId')) {
                                transferIds.add(transferId);
                            }
                        }

                        // assert trasferable:
                        checkMultiResponse(recordIds, this.customAccess.hasTransfer(recordIds));
                    }
                }
            }
            update records;
            return records;
        }

        public void doDelete(SObject[] records) {
            if (this.customAccess != null) {
                Id[] recordIds = getRecordIds(records);
                // assert deleteable:
                checkMultiResponse(recordIds, this.customAccess.hasDelete(recordIds));
            }
            delete records;
        }
    }

    /*
        Standard sharing implementation. Trying to get back some performance by relying on "with sharing" instead
        of manually checking the UserRecordAccess table (which should be functionally equivalent)
    */
    public with sharing class WithPlatformSharing implements SecurityModel {
        public Boolean hasCustomAccess() {
            return false;
        }

        public Set<Id> filterReadable(Set<Id> scope) {
            return StandardPlatformAccess().filterReadable(scope);
        }
        
        // RKDEV-31007 JAK and MDU: WithPlatformSharing does not run with a designated user
        public Boolean isDesignatedUserActive(){
            return false;
        }

        public SObject[] query(String soql, SOQLParser.LocalReBindPool reBindPool) {
            SOQLParser.assertReBindCompatibility(reBindPool, RKShare.mintReBindPool());
            sObject[] recs0 = reBindPool.getRecArray(0);
            sObject[] recs1 = reBindPool.getRecArray(1);
            sObject[] recs2 = reBindPool.getRecArray(2);

            Id[] ids0 = reBindPool.getIdArray(0);
            Id[] ids1 = reBindPool.getIdArray(1);
            Id[] ids2 = reBindPool.getIdArray(2);

            String[] strs0 = reBindPool.getStrArray(0);
            String[] strs1 = reBindPool.getStrArray(1);
            String[] strs2 = reBindPool.getStrArray(2);
            
            return Database.query(soql);
        }

        public Integer countQuery(String soql, SOQLParser.LocalReBindPool reBindPool) {
            SOQLParser.assertReBindCompatibility(reBindPool, RKShare.mintReBindPool());
            sObject[] recs0 = reBindPool.getRecArray(0);
            sObject[] recs1 = reBindPool.getRecArray(1);
            sObject[] recs2 = reBindPool.getRecArray(2);

            Id[] ids0 = reBindPool.getIdArray(0);
            Id[] ids1 = reBindPool.getIdArray(1);
            Id[] ids2 = reBindPool.getIdArray(2);

            String[] strs0 = reBindPool.getStrArray(0);
            String[] strs1 = reBindPool.getStrArray(1);
            String[] strs2 = reBindPool.getStrArray(2);
            
            return Database.countQuery(soql);
        }

        public Database.QueryLocator getQueryLocator(String soql, SOQLParser.LocalReBindPool reBindPool) {
            SOQLParser.assertReBindCompatibility(reBindPool, RKShare.mintReBindPool());
            sObject[] recs0 = reBindPool.getRecArray(0);
            sObject[] recs1 = reBindPool.getRecArray(1);
            sObject[] recs2 = reBindPool.getRecArray(2);
    
            Id[] ids0 = reBindPool.getIdArray(0);
            Id[] ids1 = reBindPool.getIdArray(1);
            Id[] ids2 = reBindPool.getIdArray(2);
    
            String[] strs0 = reBindPool.getStrArray(0);
            String[] strs1 = reBindPool.getStrArray(1);
            String[] strs2 = reBindPool.getStrArray(2);
            
            return Database.getQueryLocator(soql);
        }

        public SObject[] doInsert(SObject[] records) {
            insert records;
            return records;
        }

        public SObject[] doUpdate(SObject[] records) {
            update records;
            return records;
        }

        public SObject[] doUpdate(SObject[] records, Boolean checkTransfer) {
            update records;
            return records;
        }

        public void doDelete(SObject[] records) {
            delete records;
        }
    }


    // === Utilities ===
    private static Id[] getRecordIds(SObject[] records) {
        Id[] recordIds = new Id[]{};
        for (SObject record : records) {
            recordIds.add(record.Id);
        }
        return recordIds;
    }

    
    // === Validation and Logging ===
    // TODO: RKSecurity-like (or just hook into what RKSecurity already has) logging of access exceptions for debugging purposes?
    public class AccessException extends Exception {}

    private static final String INSUFFICIENT_ACCESS_MESSAGE = 'Insufficient access on record: {0}';
    private static final String INSUFFICIENT_ACCESS_MULTIPLE_MESSAGE = 'Insufficient access on records: {0}';

    public static void accessErr(Id recordId) {
        throw new AccessException(String.format(INSUFFICIENT_ACCESS_MESSAGE, new String[]{recordId}));
    }

    public static void accessErr(Id[] recordIds) {
        throw new AccessException(String.format(
            recordIds.size() != 1 ? INSUFFICIENT_ACCESS_MULTIPLE_MESSAGE : INSUFFICIENT_ACCESS_MESSAGE, new String[]{String.join(recordIds, ',')}));
    }


    public class RKShareConfigException extends Exception {}

    private static final String NO_RKSHARE_SETTINGS_MESSAGE = 'No applicable RKShare_Settings__c instance detected.';
    private static final String NO_DESIGNATED_USER_MESSAGE = 'Designated user Id for not specified on settings record: {0}.';
    private static final String MALFORMED_DESIGNATED_USER_MESSAGE = 'Malformed designated user Id "{0}" on settings record: {1}.';
    private static final String DESIGNATED_USER_NOT_FOUND_MESSAGE = 'No designated user found by Id "{0}" for settings record: {1}.';
    private static final String MISSING_SHARING_RULE_MESSAGE = 'Missing sharing rule for object: {0}.';
    private static final String MISSING_SHARING_RULES_MESSAGE = 'Missing sharing rules for objects: {0}.';

    public static void noRKShareSettingsErr() {
        throw new RKShareConfigException(NO_RKSHARE_SETTINGS_MESSAGE);
    }

    public static void noDesignatedUserErr(Id settingsId) {
        throw new RKShareConfigException(String.format(NO_DESIGNATED_USER_MESSAGE, new String[]{settingsId}));
    }

    public static void malformedDesignatedUserErr(String designatedUserId, Id settingsId) {
        throw new RKShareConfigException(String.format(MALFORMED_DESIGNATED_USER_MESSAGE, new String[]{designatedUserId, settingsId}));
    }

    public static void designatedUserNotFound(Id designatedUserId, Id settingsId) {
        throw new RKShareConfigException(String.format(DESIGNATED_USER_NOT_FOUND_MESSAGE, new String[]{designatedUserId, settingsId}));
    }

    public static void missingSharingRuleErr(Schema.SObjectType sObjectType) {
        missingSharingRuleErr('' + sObjectType);
    }

    public static void missingSharingRuleErr(String sObjectAPI) {
        throw new RKShareConfigException(String.format(MISSING_SHARING_RULE_MESSAGE, new String[]{sObjectAPI}));
    }

    public static void missingSharingRuleErr(Set<Schema.SObjectType> sObjectTypes) {
        missingSharingRuleErr(new List<Schema.SObjectType>(sObjectTypes));
    }

    public static void missingSharingRuleErr(Schema.SObjectType[] sObjectTypes) {
        if (sObjectTypes.size() == 1) {
            missingSharingRuleErr(sObjectTypes[0]);
        }

        String[] sObjectAPIs = new String[]{};
        for (Schema.SObjectType sObjectType : sObjectTypes) {
            sObjectAPIs.add('' + sObjectType);
        }
        missingSharingRuleErr(sObjectAPIs);
    }

    public static void missingSharingRuleErr(String[] sObjectAPIs) {
        throw new RKShareConfigException(String.format(MISSING_SHARING_RULES_MESSAGE, new String[]{String.join(sObjectAPIs, ', ')}));
    }


    public class TooManyRecordsException extends Exception {}

    private static final String TOO_MANY_RECORDS_MESSAGE = 'Too many records. Cannot determine access for more than {1} records.';

    public static void tooManyRecordsErr(Integer maxRecordsReturned) {
        throw new TooManyRecordsException(String.format(TOO_MANY_RECORDS_MESSAGE, new String[]{'' + maxRecordsReturned}));
    }

    private static void checkMultiResponse(Id[] recordIds, Boolean[] hasAccess) {
        Id[] inaccessibleIds = new Id[]{};
        for (Integer i = 0; i < hasAccess.size(); i++) {
            if (hasAccess[i] == false) {
                inaccessibleIds.add(recordIds[i]);
            }
        }

        if (inaccessibleIds.size() > 0) {
            accessErr(inaccessibleIds);
        }
    }

    public abstract class AccessResolver {
        public Set<Schema.sObjectType> bypassTypes;

        AccessResolver(Set<Schema.sObjectType> bypassTypes) {
            this.bypassTypes = bypassTypes != null ? bypassTypes : new Set<Schema.sObjectType>();
        }

        public abstract Map<Id, AccessElmt> getAccessMap(Id[] recordIds);
        
        public virtual Boolean isDesignatedUserActive(){
            return false;
        }

        public virtual Set<Id> filterReadable(Set<Id> scope) {
            Map<Id, AccessElmt> accessMap = scope != null ? getAccessMap(new List<Id>(scope)) : new Map<Id, AccessElmt>();
            Set<Id> filtered = new Set<Id>();
            for (Id recId : scope) {
                if (accessMap.get(recId).hasRead) {
                    filtered.add(recId);
                }
            }
            return filtered;
        }

        public Boolean hasAll(Id recordId) {
            return hasAll(new Id[]{ recordId })[0];
        }

        public virtual Boolean[] hasAll(Id[] recordIds) {
            Map<Id, AccessElmt> accessMap = getAccessMap(recordIds);
            Boolean[] res = new Boolean[]{};
            for (Id recId : recordIds) {
                res.add(accessMap.get(recId).hasAll);
            }
            return res;
        }

        public Boolean hasDelete(Id recordId) {
            return hasDelete(new Id[]{ recordId })[0];
        }

        public virtual Boolean[] hasDelete(Id[] recordIds) {
            Map<Id, AccessElmt> accessMap = getAccessMap(recordIds);
            Boolean[] res = new Boolean[]{};
            for (Id recId : recordIds) {
                res.add(accessMap.get(recId).hasDelete);
            }
            return res;
        }

        public Boolean hasEdit(Id recordId) {
            return hasEdit(new Id[]{ recordId })[0];
        }

        public virtual Boolean[] hasEdit(Id[] recordIds) {
            Map<Id, AccessElmt> accessMap = getAccessMap(recordIds);
            Boolean[] res = new Boolean[]{};
            for (Id recId : recordIds) {
                res.add(accessMap.get(recId).hasEdit);
            }
            return res;
        }

        public Boolean hasTransfer(Id recordId) {
            return hasTransfer(new Id[]{ recordId })[0];
        }

        public virtual Boolean[] hasTransfer(Id[] recordIds) {
            Map<Id, AccessElmt> accessMap = getAccessMap(recordIds);
            Boolean[] res = new Boolean[]{};
            for (Id recId : recordIds) {
                res.add(accessMap.get(recId).hasTransfer);
            }
            return res;
        }

        public Boolean hasRead(Id recordId) {
            return hasRead(new Id[]{ recordId })[0];
        }

        public virtual Boolean[] hasRead(Id[] recordIds) {
            Map<Id, AccessElmt> accessMap = getAccessMap(recordIds);
            Boolean[] res = new Boolean[]{};
            for (Id recId : recordIds) {
                res.add(accessMap.get(recId).hasRead);
            }
            return res;
        }
    }

    // TODO: Refine this list as necessary:
    public static final Set<Schema.sObjectType> RecordAccessBypassTypes = new Set<Schema.sObjectType>{ 
        Schema.sObjectType.RecordType.getSObjectType(), // RecordType sObjectType metadata is a bit weird
        Schema.ContentVersion.sObjectType, Schema.ContentDocument.sObjectType, Schema.ContentDocumentLink.sObjectType,
        Schema.Attachment.sObjectType 
    };

    // Static constructor for SiteGuestAccessResolver:
    static AccessResolver siteCustomAccess() {
/* mulveling-dev
        // Attempt to retrieve designated owner Id from RKShare_Settings__c instance
        // TODO: Query from __mdt or custom setting for the designated user...
        RKShare_Settings__c settingsInstance = RKShare_Settings__c.getInstance();
        if (settingsInstance == null) {
            noRKShareSettingsErr();
        }

        if (String.isBlank(settingsInstance.Designated_User_for_Guest_User_Records__c)) {
            noDesignatedUserErr(settingsInstance.Id);
        }
        
        Id designatedUserId = null;
        try {
            designatedUserId = Id.valueOf(settingsInstance.Designated_User_for_Guest_User_Records__c);
        } catch (StringException e) {
            malformedDesignatedUserErr(settingsInstance.Designated_User_for_Guest_User_Records__c, settingsInstance.Id);
        }

        User[] matchingUsers = [SELECT Name FROM User WHERE Id =: designatedUserId];
        if (matchingUsers.size() == 0) {
            designatedUserNotFound(designatedUserId, settingsInstance.Id);
        }

        return new DesignatedUserAccessResolver(RecordAccessBypassTypes, matchingUsers[0]);
*/
        System.assert(false, 'Site Custom Access not currently supported');
        return null;
    }

    public without sharing virtual class DesignatedUserAccessResolver extends AccessResolver {
        User designatedUser;

        public DesignatedUserAccessResolver(Set<Schema.sObjectType> bypassTypes, User designatedUser) {
            super(bypassTypes);
            this.designatedUser = designatedUser;
        }
        
         public virtual override Boolean isDesignatedUserActive(){
            return designatedUser != null;
        }
         
        public virtual override Map<Id, AccessElmt> getAccessMap(Id[] recordIds) {
            if (recordIds != null && recordIds.size() > MAX_FILTER_SIZE) {
                tooManyRecordsErr(MAX_FILTER_SIZE);
            }

            // TODO: Re-evaluate. I think is accurate enough for now, but could cause problems as this utility is enhanced. Performance in particular as we allow larger record sets.
            Map<Schema.SObjectType, Boolean> couldRetrieveAccess = new Map<Schema.SObjectType, Boolean>();
            for (Id recordId : recordIds) {
                Schema.SObjectType sObjectType = recordId.getSobjectType();
                if (!couldRetrieveAccess.containsKey(sObjectType)) {
                    couldRetrieveAccess.put(sObjectType, false);
                }
            }
            
            Map<Id, AccessElmt> accessMap = new Map<Id, AccessElmt>();
            final Integer len = Math.min(MAX_FILTER_SIZE, recordIds.size());
            Integer curs = 0;
            
            while (curs < len) {
                Id[] scope = new Id[]{};
                Integer i = curs;
                for (; i < len && scope.size() < 200; i++) {
                    Id recId = recordIds[i];
                    if (recId == null || bypassTypes.contains(recId.getSObjectType())) {
                        accessMap.put(recId, AllAccessElmt);
                    } else {
                        accessMap.put(recId, NoAccessElmt);
                        scope.add(recId);
                    }
                }
                
                if (designatedUser != null && designatedUser.Id != null) {
                    UserRecordAccess[] uras = [
                        SELECT RecordId, HasReadAccess, HasEditAccess, HasTransferAccess, HasDeleteAccess, HasAllAccess
                        FROM UserRecordAccess 
                        WHERE UserId = :this.designatedUser.Id AND RecordId IN :scope
                    ];
                   
                    for (UserRecordAccess ura : uras) {
                        accessMap.put(ura.RecordId, new AccessElmt(ura));
                        
                        Schema.SObjectType sObjectType = Id.valueOf(ura.RecordId).getSObjectType();
                        couldRetrieveAccess.put(sObjectType, true);
                    }
                }
                curs = i;
            }

            Set<Schema.SObjectType> inaccessibleTypes = new Set<Schema.SObjectType>();
            for (Schema.SObjectType sObjectType : couldRetrieveAccess.keySet()) {
                // JLB - RKDEV-14091 + RKDEV-14092 - Resolved bug caused by not accounting
                //   for bypass types in the detection of this configuration error
                if (couldRetrieveAccess.get(sObjectType) == false && !bypassTypes.contains(sObjectType)) {
                    inaccessibleTypes.add(sObjectType);
                }
            }

            if (!inaccessibleTypes.isEmpty()) {
                missingSharingRuleErr(inaccessibleTypes);
            }

            return accessMap;
        }
    }

    // The DesignatedUserAccessResolver with a null designated User degrades to just the standard platform's 
    // UseRecordAccess table:
    public without sharing class StandardPlatformAccessResolver extends DesignatedUserAccessResolver {
        StandardPlatformAccessResolver(Set<Schema.sObjectType> bypassTypes) {
            super(bypassTypes, null);
        }

        // TODO: Refactor this logic into a re-usable method. 99% of this logic is the same as DesignatedUserAccessResolver, minus the
        //      sharing rule validation in DesignatedUserAccessResolver.getAccessMap
        public virtual override Map<Id, AccessElmt> getAccessMap(Id[] recordIds) {
            if (recordIds != null && recordIds.size() > MAX_FILTER_SIZE) {
                tooManyRecordsErr(MAX_FILTER_SIZE);
            }

            Map<Id, AccessElmt> accessMap = new Map<Id, AccessElmt>();
            final Integer len = Math.min(MAX_FILTER_SIZE, recordIds.size());
            Integer curs = 0;
            
            while (curs < len) {
                Id[] scope = new Id[]{};
                Integer i = curs;
                for (; i < len && scope.size() < 200; i++) {
                    Id recId = recordIds[i];
                    if (recId == null || bypassTypes.contains(recId.getSObjectType())) {
                        accessMap.put(recId, AllAccessElmt);
                    } else {
                        accessMap.put(recId, NoAccessElmt);
                        scope.add(recId);
                    }
                }
                
                UserRecordAccess[] uras = [
                    SELECT RecordId, HasReadAccess, HasEditAccess, HasTransferAccess, HasDeleteAccess, HasAllAccess
                    FROM UserRecordAccess 
                    WHERE UserId = :UserInfo.getUserId() AND RecordId IN :scope
                ];

                for (UserRecordAccess ura : uras) {
                    accessMap.put(ura.RecordId, new AccessElmt(ura));
                }
                curs = i;
            }

            return accessMap;
        }
    }

    static StandardPlatformAccessResolver StandardPlatformAccessInstance;

    static AccessResolver StandardPlatformAccess() {
        if (StandardPlatformAccessInstance == null) {
            return StandardPlatformAccessInstance = new StandardPlatformAccessResolver(RecordAccessBypassTypes);
        }
        return StandardPlatformAccessInstance;
    }

    class AccessElmt {
        Boolean hasRead;
        Boolean hasEdit;
        Boolean hasTransfer;
        Boolean hasDelete;
        Boolean hasAll;

        AccessElmt(UserRecordAccess ura) {
            this.hasRead = ura.HasReadAccess;
            this.hasEdit = ura.HasEditAccess;
            this.hasTransfer = ura.HasTransferAccess;
            this.hasDelete = ura.HasDeleteAccess;
            this.hasAll = ura.HasAllAccess;
        }

        AccessElmt(Boolean allAccess) {
            this.hasRead = allAccess == true;
            this.hasEdit = allAccess == true;
            this.hasTransfer = allAccess == true;
            this.hasDelete = allAccess == true;
            this.hasAll = allAccess == true;
        }

        void addAccess(UserRecordAccess ura) {
            if (!hasRead && ura.HasReadAccess) {
                this.hasRead = true;
            }
            if (!hasEdit && ura.HasEditAccess) {
                this.hasEdit = true;
            }
            if (!hasTransfer && ura.HasTransferAccess) {
                this.hasTransfer = true;
            }
            if (!hasDelete && ura.HasDeleteAccess) {
                this.hasDelete = true;
            }
            if (!hasAll && ura.HasAllAccess) {
                this.hasAll = true;
            }
        }
    }

    static AccessElmt NoAccessElmt = new AccessElmt(false);
    static AccessElmt AllAccessElmt = new AccessElmt(true);

    // May not be the right way of going about this.
    // Seeing references to a UserType of "Guest" online, but not in the documentation. Will test on sites/communities to be sure.
    private static Boolean isGuestUser;
    static {
        isGuestUser = UserInfo.getUserType() == 'Guest';
    }
}