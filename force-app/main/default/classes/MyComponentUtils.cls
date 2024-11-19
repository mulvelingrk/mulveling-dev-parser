public without sharing class MyComponentUtils {
    public static Boolean TriggersBypass = false;

    public static void processTrigger() {
        if (context == null) {
            context = getTriggerContext();
        }
        if (context == null) {
            return;
        }

        switch on context.startMode {
            when 'insert-specifics' {
                switch on context.phase {
                    when 'init' {
                        System.assert(Trigger.isBefore, 'Processing mode insert-specific.init must execute in a before-insert');
                        mintGeneralCompFromSpecifics(context);
                    }
                    when 'link-generals' {
                        System.assert(Trigger.isAfter, 'Processing mode insert-specific.link-generals must execute in an after-insert');
                        
                        // TODO:
                        SObject[] linkSpecs = new SObject[]{};
                        My_Component__c[] linkGens = new My_Component__c[]{};
                        for (Integer i=0; i < context.srcSpecifics.size(); i++) {
                            SObject spec = context.srcSpecifics[i];
                            SObject linkSpec = context.srcSpecificsType.newSObject(spec.Id);
                            My_Component__c mintGen = context.mintGenerals[i]; 
                            linkSpec.put('My_Component__c', mintGen.Id);
                            linkSpecs.add(linkSpec);
                            My_Component__c linkGen = new My_Component__c(Id = mintGen.Id);
                            linkGens.add(linkGen);
                            // derive specific lookup AP name by the record type name:
                            // TODO: namespace?
                            linkGen.put(context.srcSpecificsRecType.getDeveloperName() + '__c', spec.Id);
                        }

                        Boolean oldBypass = TriggersBypass == true;
                        TriggersBypass = true;
                        try {
                            update linkGens;
                            update linkSpecs;
                            context.phase = 'done';
                        } finally {
                            TriggersBypass = oldBypass;
                        }
                    }
                }
            }

            when 'insert-generals' {
                switch on context.phase {
                    when 'init' {
                        System.assert(Trigger.isBefore, 'Processing mode insert-generals.init must execute in a before-insert');
                        mintSpecificCompFromGenerals(context);
                    }
                    when 'link-specifics' {
                    
                    }
                }
            }

        }
    }
    

    public static void syncSpecificCompFromGenerals(SyncContext ctxt) {

    }

    public static void syncGeneralCompFromSpecifics(SyncContext ctxt) {

    }

    public static void mintSpecificCompFromGenerals(SyncContext ctxt) {
        
    }

    // This should occur before-insert?
    public static void mintGeneralCompFromSpecifics(SyncContext ctxt) {
        Map<String, Schema.SObjectField> genFields = Schema.My_Component__c.SObjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> specFields = ctxt.srcSpecificsType.getDescribe().fields.getMap();
        ctxt.mintGenerals = new My_Component__c[]{};
        for (SObject spec : ctxt.srcSpecifics) {
            My_Component__c newGen = new My_Component__c(RecordTypeId = ctxt.srcSpecificsRecType.getRecordTypeId());
            ctxt.mintGenerals.add(newGen);
            for (String fname : specFields.keySet()) {
                if (fname.endsWith('__c') || fname == 'Name') {
                    Schema.SObjectField ftok = specFields.get(fname);
                    Schema.DescribeFieldResult f = ftok.getDescribe();
                    if (!f.isCalculated() && genFields.containsKey(fname)) {
                        newGen.put(fname, spec.get(ftok));
                    }
                }
            }
        }

        Boolean oldBypass = TriggersBypass == true;
        TriggersBypass = true;
        try {
            insert ctxt.mintGenerals;
            ctxt.phase = 'link-generals';
        } finally {
            TriggersBypass = oldBypass;
        }
    }

    static SyncContext context;

    public class SyncContext {
        String startMode;
        String phase = 'init';
        My_Component__c[] srcGenerals;
        My_Component__c[] mintGenerals;
        SObject[] srcSpecifics;
        Schema.SObjectType srcSpecificsType;
        RecordTypeInfo srcSpecificsRecType; // My_Component__c RecordType
        
        void save() {

        }
    }

    public static SyncContext getTriggerContext() {
        SyncContext ctxt = new SyncContext();
        if (!Trigger.isExecuting) {
            return null;
        }
        Schema.SObjectType objType = Trigger.new[0].getSObjectType();
        if (objType == Schema.My_Component__c.SObjectType) {
            ctxt.srcGenerals = (My_Component__c[]) Trigger.new;
            ctxt.startMode = (Trigger.isInsert ? 'insert' : Trigger.isUpdate ? 'update' : Trigger.isDelete ? 'delete' : '?') + '-generals';
        } else {
            ctxt.srcSpecificsType = objType;
            ctxt.srcSpecificsRecType = getRecordTypeFor(objType);
            if (ctxt.srcSpecificsRecType == null) {
                return null;
            }
            ctxt.startMode = (Trigger.isInsert ? 'insert' : Trigger.isUpdate ? 'update' : Trigger.isDelete ? 'delete' : '?') + '-specifics';
        }
        return ctxt;
    }

    public static RecordTypeInfo getRecordTypeFor(Schema.SObjectType specificType) {
        // TODO: strip namespace?
        return specificType.getDescribe().getRecordTypeInfosByDeveloperName().get('' + specificType);
    }

    public static Id forkSystem(Id srcSystemId, String newSystemName) {
        Audio_System__c srcSys = (Audio_System__c) Database.query(
            'SELECT ' + getFieldsSel(Schema.Audio_System__c.SObjectType) + 
            ' FROM Audio_System__c' + 
            ' WHERE Id = :srcSystemId');
        Audio_System__c forkSys = srcSys.clone(false, false);
        forkSys.Name = newSystemName;
        forkSys.Version_Of__c = srcSystemId;
        forkSys.Version_Notes__c = null;
        Boolean oldBypass = TriggersBypass == true;
        TriggersBypass = true;
        try {
            insert forkSys;
        } finally {
            TriggersBypass = oldBypass;
        }

        // Clone child System_Component__c records:
        Map<Id, System_Component__c> srcToDestComp = new Map<Id, System_Component__c>();
        for (System_Component__c srcComp : (System_Component__c[]) Database.query(
                'SELECT ' + getFieldsSel(Schema.System_Component__c.SObjectType) + 
                ' FROM System_Component__c' + 
                ' WHERE Audio_System__c = :srcSystemId')) {
            System_Component__c destComp;
            srcToDestComp.put(srcComp.Id, destComp = srcComp.clone(false, false));
        }

        // Reconcile System_Component__c and Audio_System__c lookups to new dest values.
        // Pass 1 to record all src lookups to src System_Component__c Id's - these cannot be initially inserted becasue the filter 
        // to match Audio_System__c parent will fire (it has changed from src to dest) so we record all these lookup values, null
        // them out on the new dest components, and resolve + update them in a subsequent pass:
        final Map<String, Schema.SObjectField> sysCompFields = Schema.System_Component__c.SObjectType.getDescribe().fields.getMap();
        Map<String, Id> lkpKeyToSrcId = new Map<String, Id>();
        for (Schema.SObjectField ftok : sysCompFields.values()) {
            DescribeFieldResult fdesc = ftok.getDescribe();
            if (fdesc.getName().endsWith('__c') && fdesc.getType() == Schema.DisplayType.REFERENCE) {
                Schema.SObjectType refTo = fdesc.getReferenceTo()[0];
                for (Id srcCompId : srcToDestComp.keySet()) {
                    System_Component__c destComp = srcToDestComp.get(srcCompId);
                    switch on String.valueOf(refTo) {
                        when 'System_Component__c' { 
                            Id lkpSrcCompId = (Id) destComp.get(ftok);
                            if (lkpSrcCompId != null) {
                                //destComp.put(ftok, srcToDestComp.get(srcCompId).Id);
                                lkpKeyToSrcId.put(ftok + '.' + srcCompId, lkpSrcCompId);
                                destComp.put(ftok, null);
                            }
                        }
                        when 'Audio_System__c' {
                            if (destComp.get(ftok) == srcSystemId) {
                                destComp.put(ftok, forkSys.Id);
                            }
                        }
                    }
                }
            }
        }
        oldBypass = TriggersBypass == true;
        TriggersBypass = true;
        try {
           insert srcToDestComp.values();
        } finally {
            TriggersBypass = oldBypass;
        }

        // Pass 2: resolve and update all the System_Component__c lookup field values we witheld from the prior insert:
        Map<Id, System_Component__c> sysCompUpdates = new Map<Id, System_Component__c>();
        for (String lkpKey : lkpKeyToSrcId.keySet()) {
            String[] parts = lkpKey.split('\\.');
            Id srcLkpId = lkpKeyToSrcId.get(lkpKey);
            Id srcHolderId = Id.valueOf(parts[1]);

            System_Component__c destHolder = srcToDestComp.get(srcHolderId);
            System_Component__c destLkpComp = srcToDestComp.get(srcLkpId);

            String lkpField = parts[0];
            System_Component__c updates = sysCompUpdates.get(destHolder.Id);
            if (updates == null) {
                sysCompUpdates.put(destHolder.Id, updates = new System_Component__c(Id = destHolder.Id));
            }
            updates.put(lkpField, destLkpComp?.Id);
        }
        oldBypass = TriggersBypass == true;
        TriggersBypass = true;
        try {
           update sysCompUpdates.values();
        } finally {
            TriggersBypass = oldBypass;
        }

        // Clone child Component_Relationship__c records:
        Map<Id, Component_Relationship__c> srcToDestRel = new Map<Id, Component_Relationship__c>();
        for (Component_Relationship__c srcRel : (Component_Relationship__c[]) Database.query(
                'SELECT ' + getFieldsSel(Schema.Component_Relationship__c.SObjectType) + 
                ' FROM Component_Relationship__c' + 
                ' WHERE Audio_System__c = :srcSystemId')) {
            Component_Relationship__c destRel;
            srcToDestRel.put(srcRel.Id, destRel = srcRel.clone(false, false));
        }

        final Map<String, Schema.SObjectField> relFields = Schema.Component_Relationship__c.SObjectType.getDescribe().fields.getMap();
        lkpKeyToSrcId = new Map<String, Id>();
        for (Schema.SObjectField ftok : relFields.values()) {
            DescribeFieldResult fdesc = ftok.getDescribe();
            if (fdesc.getName().endsWith('__c') && fdesc.getType() == Schema.DisplayType.REFERENCE) {
                Schema.SObjectType refTo = fdesc.getReferenceTo()[0];
                for (Id srcRelId : srcToDestRel.keySet()) {
                    Component_Relationship__c destRel = srcToDestRel.get(srcRelId);
                    switch on String.valueOf(refTo) {
                        when 'Component_Relationship__c' { 
                            Id lkpSrcRelId = (Id) destRel.get(ftok);
                            if (lkpSrcRelId != null) {
                                lkpKeyToSrcId.put(ftok + '.' + srcRelId, lkpSrcRelId);
                                destRel.put(ftok, null);
                            }
                        }
                        when 'System_Component__c' {
                            Id srcCompId = (Id) destRel.get(ftok); 
                            destRel.put(ftok, srcToDestComp.get(srcCompId)?.Id);
                        }
                        when 'Audio_System__c' {
                            if (destRel.get(ftok) == srcSystemId) {
                                destRel.put(ftok, forkSys.Id);
                            }
                        }
                    }
                }
            }
        }
        oldBypass = TriggersBypass == true;
        TriggersBypass = true;
        try {
           insert srcToDestRel.values();
        } finally {
            TriggersBypass = oldBypass;
        }

        // Pass 2: resolve and update all the Component_Relationship__c lookup field values we witheld from the prior insert:
        Map<Id, Component_Relationship__c> relUpdates = new Map<Id, Component_Relationship__c>();
        for (String lkpKey : lkpKeyToSrcId.keySet()) {
            String[] parts = lkpKey.split('\\.');
            Id srcLkpId = lkpKeyToSrcId.get(lkpKey);
            Id srcHolderId = Id.valueOf(parts[1]);

            Component_Relationship__c destHolder = srcToDestRel.get(srcHolderId);
            Component_Relationship__c destLkpComp = srcToDestRel.get(srcLkpId);

            String lkpField = parts[0];
            Component_Relationship__c updates = new Component_Relationship__c(Id = destHolder.Id);
            updates.put(lkpField, destLkpComp?.Id);
            relUpdates.put(updates.Id, updates);
        }
        oldBypass = TriggersBypass == true;
        TriggersBypass = true;
        try {
           update relUpdates.values();
        } finally {
            TriggersBypass = oldBypass;
        }

        return forkSys.Id;
    }

    static String getFieldsSel(Schema.SObjectType objType) {
        String[] fields = new String[]{};
        for (Schema.SObjectField ftok : objType.getDescribe().fields.getMap().values()) {
            fields.add('' + ftok);
        }
        return String.join(fields, ', ');
    }
}