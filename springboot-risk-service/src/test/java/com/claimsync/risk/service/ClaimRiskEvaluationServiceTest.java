package com.claimsync.risk.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import com.claimsync.risk.dto.ClaimEvaluationResponse;
import com.claimsync.risk.rules.AnomalyKeywordRule;
import com.claimsync.risk.rules.CoverageUtilizationRule;
import com.claimsync.risk.rules.EarlyPolicyInceptionRule;
import com.claimsync.risk.rules.HighValueClaimRule;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ClaimRiskEvaluationServiceTest {

    private ClaimRiskEvaluationService service;

    @BeforeEach
    void setUp() {
        service = new ClaimRiskEvaluationService(List.of(
                new HighValueClaimRule(),
                new CoverageUtilizationRule(),
                new AnomalyKeywordRule(),
                new EarlyPolicyInceptionRule()
        ));
    }

    @Test
    @DisplayName("Low-value routine claim on seasoned policy should be Auto-Approved")
    void shouldAutoApproveLowRiskClaim() {
        ClaimEvaluationRequest request = new ClaimEvaluationRequest(
                "a01000000000001AAA",
                "CLM-00001",
                "POL-AUTO-1001",
                new BigDecimal("1200.00"),
                new BigDecimal("50000.00"),
                LocalDate.now().minusDays(5),
                LocalDate.now().minusDays(180),
                "Minor windshield chip repair on highway."
        );

        ClaimEvaluationResponse response = service.evaluateClaim(request);

        assertEquals("Approved", response.recommendedStatus());
        assertEquals(new BigDecimal("15"), response.riskScore());
        assertTrue(response.triggeredRules().isEmpty());
    }

    @Test
    @DisplayName("High-value claim with SIU anomaly keywords and early policy inception should be Flagged for Adjuster")
    void shouldFlagHighRiskClaimForAdjuster() {
        ClaimEvaluationRequest request = new ClaimEvaluationRequest(
                "a01000000000002AAA",
                "CLM-00002",
                "POL-AUTO-1002",
                new BigDecimal("42000.00"),
                new BigDecimal("50000.00"),
                LocalDate.now().minusDays(2),
                LocalDate.now().minusDays(10),
                "Unwitnessed total loss collision late at night."
        );

        ClaimEvaluationResponse response = service.evaluateClaim(request);

        assertEquals("Flagged for Adjuster", response.recommendedStatus());
        assertTrue(response.riskScore().compareTo(new BigDecimal("60")) >= 0);
        assertFalse(response.triggeredRules().isEmpty());
    }

    @Test
    @DisplayName("Moderate-value claim with single risk factor should route to Under Review")
    void shouldRouteModerateRiskClaimToUnderReview() {
        ClaimEvaluationRequest request = new ClaimEvaluationRequest(
                "a01000000000003AAA",
                "CLM-00003",
                "POL-AUTO-1003",
                new BigDecimal("12500.00"),
                new BigDecimal("50000.00"),
                LocalDate.now().minusDays(3),
                LocalDate.now().minusDays(120),
                "Hail damage to roof and siding."
        );

        ClaimEvaluationResponse response = service.evaluateClaim(request);

        assertEquals("Under Review", response.recommendedStatus());
        assertEquals(new BigDecimal("35"), response.riskScore());
    }
}
