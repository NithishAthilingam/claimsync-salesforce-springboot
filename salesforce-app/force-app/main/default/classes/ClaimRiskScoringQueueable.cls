/**
 * @description Queueable Apex integration worker that sends newly created Claim__c payloads
 *              to the Java Spring Boot Fraud & Underwriting Risk Scoring REST API
 *              (/api/v1/claims/evaluate) and updates claim status and risk metrics.
 */
public with sharing class ClaimRiskScoringQueueable implements Queueable, Database.AllowsCallouts {

    public static final String RISK_API_ENDPOINT = 'https://claimsync-risk-api.example.com/api/v1/claims/evaluate';
    public static final Integer MAX_CALLOUTS_PER_TRANSACTION = 50;

    private final List<Id> claimIds;

    public class ClaimEvaluationRequest {
        public String claimId;
        public String claimNumber;
        public String policyNumber;
        public Decimal claimAmount;
        public Decimal coverageLimit;
        public Date incidentDate;
        public Date policyEffectiveDate;
        public String incidentDescription;
    }

    public class ClaimEvaluationResponse {
        public Decimal riskScore;
        public String recommendedStatus;
        public String evaluationSummary;
    }

    public ClaimRiskScoringQueueable(List<Id> claimIds) {
        this.claimIds = claimIds != null ? new List<Id>(claimIds) : new List<Id>();
    }

    public void execute(QueueableContext context) {
        if (claimIds.isEmpty()) {
            return;
        }

        List<Claim__c> claimsToScore = [
            SELECT Id, Name, Claim_Amount__c, Incident_Date__c, Incident_Description__c, Status__c,
                   Policy__r.Name, Policy__r.Coverage_Limit__c, Policy__r.Effective_Date__c
            FROM Claim__c
            WHERE Id IN :claimIds
        ];

        List<Claim__c> claimsToUpdate = new List<Claim__c>();
        Integer calloutsPerformed = 0;

        for (Claim__c claim : claimsToScore) {
            if (calloutsPerformed < MAX_CALLOUTS_PER_TRANSACTION &&
                Limits.getCallouts() < Limits.getLimitCallouts()) {
                ClaimEvaluationResponse apiResult = invokeSpringBootRiskApi(claim);
                calloutsPerformed++;

                claim.Risk_Score__c = apiResult.riskScore;
                claim.Status__c = apiResult.recommendedStatus;
                claim.Fraud_Evaluation_Notes__c = truncateNotes(apiResult.evaluationSummary);
            } else {
                // Governor-safe deterministic fallback when batch exceeds per-transaction callout budget
                ClaimEvaluationResponse fallback = evaluateLocallyForBulkOverflow(claim);
                claim.Risk_Score__c = fallback.riskScore;
                claim.Status__c = fallback.recommendedStatus;
                claim.Fraud_Evaluation_Notes__c = truncateNotes(fallback.evaluationSummary);
            }
            claimsToUpdate.add(claim);
        }

        if (!claimsToUpdate.isEmpty()) {
            ClaimTriggerHandler.bypassTrigger = true;
            try {
                update claimsToUpdate;
            } finally {
                ClaimTriggerHandler.bypassTrigger = false;
            }
        }
    }

    @TestVisible
    private static ClaimEvaluationResponse invokeSpringBootRiskApi(Claim__c claim) {
        ClaimEvaluationRequest payload = new ClaimEvaluationRequest();
        payload.claimId = String.valueOf(claim.Id);
        payload.claimNumber = claim.Name;
        payload.policyNumber = claim.Policy__r != null ? claim.Policy__r.Name : 'UNKNOWN';
        payload.claimAmount = claim.Claim_Amount__c;
        payload.coverageLimit = claim.Policy__r != null ? claim.Policy__r.Coverage_Limit__c : 0;
        payload.incidentDate = claim.Incident_Date__c;
        payload.policyEffectiveDate = claim.Policy__r != null ? claim.Policy__r.Effective_Date__c : null;
        payload.incidentDescription = claim.Incident_Description__c;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(RISK_API_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(15000);
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                ClaimEvaluationResponse parsed = (ClaimEvaluationResponse) JSON.deserialize(
                    res.getBody(),
                    ClaimEvaluationResponse.class
                );
                if (parsed != null && parsed.riskScore != null && String.isNotBlank(parsed.recommendedStatus)) {
                    return parsed;
                }
            }
            ClaimEvaluationResponse errorFallback = new ClaimEvaluationResponse();
            errorFallback.riskScore = 50.0;
            errorFallback.recommendedStatus = 'Under Review';
            errorFallback.evaluationSummary = 'Risk API HTTP ' + res.getStatusCode() + ': Routed to manual review.';
            return errorFallback;
        } catch (Exception ex) {
            ClaimEvaluationResponse exceptionFallback = new ClaimEvaluationResponse();
            exceptionFallback.riskScore = 50.0;
            exceptionFallback.recommendedStatus = 'Under Review';
            exceptionFallback.evaluationSummary = 'Risk API unreachable (' + ex.getMessage() + '). Routed to manual review.';
            return exceptionFallback;
        }
    }

    @TestVisible
    private static ClaimEvaluationResponse evaluateLocallyForBulkOverflow(Claim__c claim) {
        ClaimEvaluationResponse result = new ClaimEvaluationResponse();
        Boolean isHighValue = claim.Claim_Amount__c != null &&
            claim.Claim_Amount__c >= ClaimTriggerHandler.HIGH_VALUE_THRESHOLD;
        result.riskScore = isHighValue ? 75.0 : 20.0;
        result.recommendedStatus = isHighValue ? 'Flagged for Adjuster' : 'Approved';
        result.evaluationSummary = 'Bulk governor-safe evaluation completed.';
        return result;
    }

    private static String truncateNotes(String notes) {
        if (String.isBlank(notes)) {
            return '';
        }
        return notes.length() > 255 ? notes.substring(0, 255) : notes;
    }
}
