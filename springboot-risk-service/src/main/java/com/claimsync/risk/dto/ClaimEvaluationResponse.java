package com.claimsync.risk.dto;

import java.math.BigDecimal;
import java.util.List;

public record ClaimEvaluationResponse(
        String claimId,
        BigDecimal riskScore,
        String recommendedStatus,
        String evaluationSummary,
        List<String> triggeredRules
) {
}
