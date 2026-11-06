/**
 * @description HttpCalloutMock implementation simulating the Java Spring Boot
 *              Fraud & Underwriting Risk Scoring microservice (/api/v1/claims/evaluate).
 */
@isTest
public class ClaimRiskCalloutMock implements HttpCalloutMock {

    private final Integer statusCode;
    private final Boolean throwCalloutException;

    public ClaimRiskCalloutMock() {
        this(200, false);
    }

    public ClaimRiskCalloutMock(Integer statusCode) {
        this(statusCode, false);
    }

    public ClaimRiskCalloutMock(Integer statusCode, Boolean throwCalloutException) {
        this.statusCode = statusCode;
        this.throwCalloutException = throwCalloutException;
    }

    public HttpResponse respond(HttpRequest req) {
        System.assertEquals('POST', req.getMethod(), 'Expected POST request to Spring Boot Risk API.');
        System.assert(
            req.getEndpoint().contains('/api/v1/claims/evaluate'),
            'Endpoint should target /api/v1/claims/evaluate.'
        );

        if (throwCalloutException) {
            CalloutException ex = new CalloutException();
            ex.setMessage('Simulated connection timeout to Spring Boot microservice');
            throw ex;
        }

        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode);

        if (statusCode != 200) {
            res.setBody('{"error":"Service Temporarily Unavailable"}');
            return res;
        }

        Map<String, Object> requestMap = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
        Decimal claimAmount = requestMap.get('claimAmount') != null
            ? Decimal.valueOf(String.valueOf(requestMap.get('claimAmount')))
            : 0;
        String description = requestMap.get('incidentDescription') != null
            ? String.valueOf(requestMap.get('incidentDescription')).toLowerCase()
            : '';

        ClaimRiskScoringQueueable.ClaimEvaluationResponse mockBody =
            new ClaimRiskScoringQueueable.ClaimEvaluationResponse();

        if (claimAmount >= 10000 || description.contains('total loss') || description.contains('unwitnessed')) {
            mockBody.riskScore = 85.0;
            mockBody.recommendedStatus = 'Flagged for Adjuster';
            mockBody.evaluationSummary = 'High-Risk Flag (85/100): High severity claim amount or anomaly keywords detected.';
        } else {
            mockBody.riskScore = 15.0;
            mockBody.recommendedStatus = 'Approved';
            mockBody.evaluationSummary = 'Auto-Approved (15/100): Within standard underwriting risk tolerances.';
        }

        res.setBody(JSON.serialize(mockBody));
        return res;
    }
}
