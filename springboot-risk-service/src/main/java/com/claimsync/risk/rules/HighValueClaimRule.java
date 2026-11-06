package com.claimsync.risk.rules;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import java.math.BigDecimal;
import java.util.Optional;
import org.springframework.stereotype.Component;

@Component
public class HighValueClaimRule implements RiskScoringRule {

    private static final BigDecimal HIGH_VALUE_THRESHOLD = new BigDecimal("10000.00");
    private static final BigDecimal SEVERE_VALUE_THRESHOLD = new BigDecimal("25000.00");

    @Override
    public int calculateRiskPoints(ClaimEvaluationRequest request) {
        if (request.claimAmount() == null) {
            return 0;
        }
        if (request.claimAmount().compareTo(SEVERE_VALUE_THRESHOLD) >= 0) {
            return 40;
        }
        if (request.claimAmount().compareTo(HIGH_VALUE_THRESHOLD) >= 0) {
            return 25;
        }
        return 5;
    }

    @Override
    public Optional<String> describeFinding(ClaimEvaluationRequest request) {
        int points = calculateRiskPoints(request);
        if (points >= 25) {
            return Optional.of("HIGH_VALUE_CLAIM: Requested settlement ($" + request.claimAmount() + ") exceeds standard auto-adjudication threshold");
        }
        return Optional.empty();
    }
}
