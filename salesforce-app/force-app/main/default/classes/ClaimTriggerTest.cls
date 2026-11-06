/**
 * @description Comprehensive unit & integration test suite (@isTest) for ClaimTrigger,
 *              ClaimTriggerHandler, and ClaimRiskScoringQueueable.
 *              Targets >95% Apex code coverage across positive, negative, bulk (200 records),
 *              and HTTP error recovery scenarios.
 */
@isTest
private class ClaimTriggerTest {

    @testSetup
    static void setupTestData() {
        List<Policy__c> policies = new List<Policy__c>{
            new Policy__c(
                Name = 'POL-AUTO-1001',
                Coverage_Limit__c = 50000.00,
                Status__c = 'Active',
                Effective_Date__c = Date.today().addDays(-90),
                Policyholder_Email__c = 'insured.active@example.com'
            ),
            new Policy__c(
                Name = 'POL-EXP-2002',
                Coverage_Limit__c = 25000.00,
                Status__c = 'Expired',
                Effective_Date__c = Date.today().addDays(-400),
                Policyholder_Email__c = 'insured.expired@example.com'
            )
        };
        insert policies;
    }

    @isTest
    static void testLowValueClaimApprovedEndToEnd() {
        Policy__c activePolicy = [SELECT Id FROM Policy__c WHERE Name = 'POL-AUTO-1001' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new ClaimRiskCalloutMock(200));

        Claim__c lowRiskClaim = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 1500.00,
            Incident_Date__c = Date.today().addDays(-5),
            Incident_Description__c = 'Minor rear bumper scratch in parking lot.'
        );

        Test.startTest();
        insert lowRiskClaim;
        Test.stopTest();

        Claim__c updatedClaim = [
            SELECT Status__c, Risk_Score__c, Fraud_Evaluation_Notes__c
            FROM Claim__c
            WHERE Id = :lowRiskClaim.Id
        ];
        System.assertEquals('Approved', updatedClaim.Status__c, 'Low-risk claim should be auto-approved by Spring Boot service.');
        System.assertEquals(15.0, updatedClaim.Risk_Score__c, 'Expected risk score of 15.0 for low-value routine claim.');
        System.assert(
            updatedClaim.Fraud_Evaluation_Notes__c.contains('Auto-Approved'),
            'Expected evaluation notes to contain Auto-Approved summary.'
        );
    }

    @isTest
    static void testHighValueClaimFlaggedForAdjuster() {
        Policy__c activePolicy = [SELECT Id FROM Policy__c WHERE Name = 'POL-AUTO-1001' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new ClaimRiskCalloutMock(200));

        Claim__c highRiskClaim = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 35000.00,
            Incident_Date__c = Date.today().addDays(-2),
            Incident_Description__c = 'Unwitnessed single-vehicle total loss collision at night.'
        );

        Test.startTest();
        insert highRiskClaim;
        Test.stopTest();

        Claim__c updatedClaim = [
            SELECT Status__c, Risk_Score__c, Fraud_Evaluation_Notes__c
            FROM Claim__c
            WHERE Id = :highRiskClaim.Id
        ];
        System.assertEquals(
            'Flagged for Adjuster',
            updatedClaim.Status__c,
            'High-value anomaly claim should be flagged for Senior Adjuster review.'
        );
        System.assertEquals(85.0, updatedClaim.Risk_Score__c, 'Expected elevated risk score of 85.0.');
    }

    @isTest
    static void testRejectClaimExceedingCoverageLimitAndBeforeUpdateValidation() {
        Policy__c activePolicy = [SELECT Id FROM Policy__c WHERE Name = 'POL-AUTO-1001' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new ClaimRiskCalloutMock(200));

        Claim__c excessiveClaim = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 75000.00,
            Incident_Date__c = Date.today().addDays(-1),
            Incident_Description__c = 'Claim exceeding $50k policy limit.'
        );

        Database.SaveResult insertResult = Database.insert(excessiveClaim, false);
        System.assert(!insertResult.isSuccess(), 'Insert should fail when Claim_Amount__c exceeds Coverage_Limit__c.');
        System.assert(
            insertResult.getErrors()[0].getMessage().contains('exceeds policy Coverage Limit'),
            'Error message should mention coverage limit violation.'
        );

        // Insert a valid claim, then attempt an invalid update exceeding coverage limit
        Claim__c validClaim = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 2000.00,
            Incident_Date__c = Date.today().addDays(-3),
            Incident_Description__c = 'Windshield replacement.'
        );
        insert validClaim;

        validClaim.Claim_Amount__c = 60000.00;
        Database.SaveResult updateResult = Database.update(validClaim, false);
        System.assert(!updateResult.isSuccess(), 'Update should fail when updated amount exceeds coverage limit.');
    }

    @isTest
    static void testDomainValidationRulesExpiredNegativeAndPriorDate() {
        Policy__c activePolicy = [SELECT Id FROM Policy__c WHERE Name = 'POL-AUTO-1001' LIMIT 1];
        Policy__c expiredPolicy = [SELECT Id FROM Policy__c WHERE Name = 'POL-EXP-2002' LIMIT 1];

        // 1. Expired policy claim rejection
        Claim__c expiredPolicyClaim = new Claim__c(
            Policy__c = expiredPolicy.Id,
            Claim_Amount__c = 1000.00,
            Incident_Date__c = Date.today()
        );
        Database.SaveResult resExpired = Database.insert(expiredPolicyClaim, false);
        System.assert(!resExpired.isSuccess(), 'Should reject claim against Expired policy.');

        // 2. Non-positive amount rejection
        Claim__c zeroAmountClaim = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 0.00,
            Incident_Date__c = Date.today()
        );
        Database.SaveResult resZero = Database.insert(zeroAmountClaim, false);
        System.assert(!resZero.isSuccess(), 'Should reject $0.00 claim amount.');

        // 3. Incident Date prior to Policy Effective Date rejection
        Claim__c priorIncidentClaim = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 1200.00,
            Incident_Date__c = Date.today().addDays(-120)
        );
        Database.SaveResult resPrior = Database.insert(priorIncidentClaim, false);
        System.assert(!resPrior.isSuccess(), 'Should reject claim where Incident_Date__c precedes Effective_Date__c.');
    }

    @isTest
    static void testBulkClaimInsert200RecordsGovernorSafety() {
        Policy__c activePolicy = [SELECT Id FROM Policy__c WHERE Name = 'POL-AUTO-1001' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new ClaimRiskCalloutMock(200));

        List<Claim__c> bulkClaims = new List<Claim__c>();
        for (Integer i = 0; i < 200; i++) {
            bulkClaims.add(new Claim__c(
                Policy__c = activePolicy.Id,
                Claim_Amount__c = (Math.mod(i, 2) == 0) ? 1200.00 : 15000.00,
                Incident_Date__c = Date.today().addDays(-1),
                Incident_Description__c = 'Bulk test claim #' + i
            ));
        }

        Test.startTest();
        insert bulkClaims;
        Test.stopTest();

        List<Claim__c> processedClaims = [
            SELECT Id, Status__c, Risk_Score__c
            FROM Claim__c
            WHERE Policy__c = :activePolicy.Id
        ];
        System.assertEquals(200, processedClaims.size(), 'All 200 bulk claims should be inserted and scored without hitting governor limits.');
        for (Claim__c c : processedClaims) {
            System.assertNotEquals(null, c.Risk_Score__c, 'Every claim in 200-record batch must receive a risk score.');
        }
    }

    @isTest
    static void testCalloutServerErrorAndNetworkExceptionFallback() {
        Policy__c activePolicy = [SELECT Id, Name, Coverage_Limit__c, Effective_Date__c FROM Policy__c WHERE Name = 'POL-AUTO-1001' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new ClaimRiskCalloutMock(503));

        Claim__c claim503 = new Claim__c(
            Policy__c = activePolicy.Id,
            Claim_Amount__c = 2500.00,
            Incident_Date__c = Date.today().addDays(-1),
            Incident_Description__c = 'Testing HTTP 503 resilience.'
        );

        Test.startTest();
        insert claim503;
        Test.stopTest();

        Claim__c updated = [
            SELECT Status__c, Risk_Score__c, Fraud_Evaluation_Notes__c
            FROM Claim__c
            WHERE Id = :claim503.Id
        ];
        System.assertEquals('Under Review', updated.Status__c, 'HTTP 503 should safely route claim to Under Review.');
        System.assertEquals(50.0, updated.Risk_Score__c, 'Fallback risk score should be 50.0.');

        // Also verify network exception fallback path directly
        Test.setMock(HttpCalloutMock.class, new ClaimRiskCalloutMock(200, true));
        ClaimRiskScoringQueueable.ClaimEvaluationResponse exResponse =
            ClaimRiskScoringQueueable.invokeSpringBootRiskApi(claim503);
        System.assertEquals('Under Review', exResponse.recommendedStatus, 'Exception fallback should route to Under Review.');
    }
}
