trigger AudioSystemTrigger on Audio_System__c (before delete) {
    delete [ SELECT Id FROM Component_Relationship__c WHERE Audio_System__c IN :Trigger.oldMap.keySet() ];
    delete [ SELECT Id FROM System_Component__c WHERE Audio_System__c IN :Trigger.oldMap.keySet() ];
}