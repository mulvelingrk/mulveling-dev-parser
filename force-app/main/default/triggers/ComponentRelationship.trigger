trigger ComponentRelationship on Component_Relationship__c (before insert) {
    if (MyCOmponentUtils.TriggersBypass == true) {
        return;
    }
    ComponentRelationshipTriggerHandler.handle();
}