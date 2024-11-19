trigger SystemComponentTrigger on System_Component__c (before insert) {
    Map<Id, Audio_Component__c> compMap = new Map<Id, Audio_Component__c>();
    for (System_Component__c  sc : Trigger.new) {
        compMap.put(sc.Audio_Component__c, null);
    }
    
    /*
    final Map<String, String> srcToDestTypeMappings = new Map<String, String>{
        'interconnect' => 'Cable',
        'speaker_cable' => 'Cable',
        'headshell_leads' => 'Cable',
        'power_cable' => 'Cable',
        'amplifier' => 'Powered',
        'preamplifier' => 'Powered',
        'phono_stage' => 'Powered',
        'turntable' => 'Powered',
        'speaker' => 'Passive',
        'sut' => 'Passive',
        'tonearm' => 'Passive',
        'wall_socket' => 'Power_Source',
        'power_center' => 'Power_Source',
        'tube' => 'Tube',
        'rack' => 'Support',
        'shelf' => 'Support',
        'feet' => 'Support',
        'armboard' => 'Support',
        'accessory' => 'Other'
    };
    */
    
    //final Map<String, RecordTypeInfo> srcTypesByName = Schema.Audio_Component__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
    final Map<String, RecordTypeInfo> destTypesByName = Schema.System_Component__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
    
    compMap = new Map<Id, Audio_Component__c>([ SELECT Name, RecordType.DeveloperName FROM Audio_Component__c WHERE Id IN :(compMap.keySet()) ]);
    for (System_Component__c  sc : Trigger.new) {
        Audio_Component__c ac = compMap.get(sc.Audio_Component__c);
        if (ac != null) {
            sc.Name = ac.Name;
            RecordTypeInfo destType = destTypesByName.get(ac.RecordType.DeveloperName);
            if (destType == null) {
                destType = destTypesByName.get('Other');
            }
            if (destType != null) {
                sc.RecordTypeId = destType.getRecordTypeId();
            }
        }
    }
}