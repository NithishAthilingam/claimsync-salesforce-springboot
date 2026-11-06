package com.claimsync.risk.rules;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Optional;
import org.springframework.stereotype.Component;

@Component
public class CoverageUtilizationRule implements RiskScoringRule {

    private static final BigDecimal HIGH_UTILIZATION_RATIO = new BigDecimal("0.60");

    @Override
    public int calculateRiskPoints(ClaimEvaluationRequest request) {
        if (request.claimAmount() == null || request.coverageLimit() == null
                || request.coverageLimit().compareTo(BigDecimal.ZERO) <= 0) {
            return 0;
        }
        BigDecimal ratio = request.claimAmount()
                .divide(request.coverageLimit(), 4, RoundingMode.HALF_UP);
        if (ratio.compareTo(HIGH_UTILIZATION_RATIO) >= 0) {
            return 25;
        }
        return 5;
    }

    @Override
    public Optional<String> describeFinding(ClaimEvaluationRequest request) {
        if (calculateRiskPoints(request) >= 25) {
            return Optional.of("HIGH_COVERAGE_UTILIZATION: Claim consumes >=60% of policy coverage limit");
        }
        return Optional.empty();
    }
}
