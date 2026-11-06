/**
 * @description Enterprise OOP Trigger Handler for Insurance Claims (Claim__c).
 *              Enforces bulkified policy coverage validations prior to DML commitment
 *              and dispatches asynchronous Queueable callouts to the Java Spring Boot
 *              Fraud & Underwriting Risk Scoring microservice.
 */
public with sharing class ClaimTriggerHandler {

    public static final Decimal HIGH_VALUE_THRESHOLD = 10000.00;
    public static Boolean bypassTrigger = false;

    /**
     * @description Handles before insert context: validates claims against parent Policy__c
     *              and sets initial lifecycle status.
     */
    public static void handleBeforeInsert(List<Claim__c> newClaims) {
        if (bypassTrigger || newClaims == null || newClaims.isEmpty()) {
            return;
        }
        Map<Id, Policy__c> policyMap = queryParentPolicies(newClaims);
        for (Claim__c claim : newClaims) {
            validateClaimAgainstPolicy(claim, policyMap.get(claim.Policy__c));
            if (String.isBlank(claim.Status__c) || claim.Status__c == 'Submitted') {
                if (claim.Claim_Amount__c != null && claim.Claim_Amount__c >= HIGH_VALUE_THRESHOLD) {
                    claim.Status__c = 'Under Review';
                } else {
                    claim.Status__c = 'Submitted';
                }
            }
        }
    }

    /**
     * @description Handles before update context: re-validates claim amount and policy bounds
     *              when financial or policy fields are modified.
     */
    public static void handleBeforeUpdate(List<Claim__c> newClaims, Map<Id, Claim__c> oldClaimMap) {
        if (bypassTrigger || newClaims == null || newClaims.isEmpty()) {
            return;
        }
        Map<Id, Policy__c> policyMap = queryParentPolicies(newClaims);
        for (Claim__c claim : newClaims) {
            Claim__c oldClaim = oldClaimMap != null ? oldClaimMap.get(claim.Id) : null;
            Boolean amountOrPolicyChanged = (oldClaim == null)
                || (claim.Claim_Amount__c != oldClaim.Claim_Amount__c)
                || (claim.Policy__c != oldClaim.Policy__c)
                || (claim.Incident_Date__c != oldClaim.Incident_Date__c);

            if (amountOrPolicyChanged) {
                validateClaimAgainstPolicy(claim, policyMap.get(claim.Policy__c));
            }
        }
    }

    /**
     * @description Handles after insert context: enqueues asynchronous risk scoring callout
     *              to the Spring Boot microservice for newly submitted claims.
     */
    public static void handleAfterInsert(List<Claim__c> newClaims) {
        if (bypassTrigger || newClaims == null || newClaims.isEmpty()) {
            return;
        }
        List<Id> claimIdsForScoring = new List<Id>();
        for (Claim__c claim : newClaims) {
            if (claim.Id != null) {
                claimIdsForScoring.add(claim.Id);
            }
        }

        if (!claimIdsForScoring.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new ClaimRiskScoringQueueable(claimIdsForScoring));
        }
    }

    /**
     * @description Bulkified SOQL lookup of parent Policy__c records to avoid SOQL-in-loop governor limits.
     */
    private static Map<Id, Policy__c> queryParentPolicies(List<Claim__c> claims) {
        Set<Id> policyIds = new Set<Id>();
        for (Claim__c claim : claims) {
            if (claim.Policy__c != null) {
                policyIds.add(claim.Policy__c);
            }
        }
        if (policyIds.isEmpty()) {
            return new Map<Id, Policy__c>();
        }
        return new Map<Id, Policy__c>([
            SELECT Id, Name, Coverage_Limit__c, Status__c, Effective_Date__c
            FROM Policy__c
            WHERE Id IN :policyIds
        ]);
    }

    /**
     * @description Domain validation logic enforcing policy status, positive claim amount,
     *              coverage ceiling, and effective date boundaries.
     */
    private static void validateClaimAgainstPolicy(Claim__c claim, Policy__c policy) {
        if (claim.Claim_Amount__c == null || claim.Claim_Amount__c <= 0) {
            claim.Claim_Amount__c.addError('Claim Amount must be greater than $0.00.');
            return;
        }
        if (policy == null) {
            claim.Policy__c.addError('A valid Insurance Policy is required to submit a claim.');
            return;
        }
        if (policy.Status__c != 'Active') {
            claim.addError('Claims cannot be filed against a policy with status: ' + policy.Status__c + '.');
            return;
        }
        if (policy.Coverage_Limit__c != null && claim.Claim_Amount__c > policy.Coverage_Limit__c) {
            claim.Claim_Amount__c.addError(
                'Claim Amount ($' + claim.Claim_Amount__c.format() +
                ') exceeds policy Coverage Limit ($' + policy.Coverage_Limit__c.format() + ').'
            );
            return;
        }
        if (claim.Incident_Date__c != null && policy.Effective_Date__c != null &&
            claim.Incident_Date__c < policy.Effective_Date__c) {
            claim.Incident_Date__c.addError(
                'Incident Date cannot precede the policy Effective Date (' +
                String.valueOf(policy.Effective_Date__c) + ').'
            );
        }
    }
}
