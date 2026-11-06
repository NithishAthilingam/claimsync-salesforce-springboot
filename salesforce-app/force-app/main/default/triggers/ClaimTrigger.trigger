/**
 * @description Apex Trigger on Claim__c delegating all domain validation and async
 *              Spring Boot risk-scoring callouts to ClaimTriggerHandler.
 */
trigger ClaimTrigger on Claim__c (before insert, before update, after insert) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            ClaimTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            ClaimTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    } else if (Trigger.isAfter && Trigger.isInsert) {
        ClaimTriggerHandler.handleAfterInsert(Trigger.new);
    }
}
