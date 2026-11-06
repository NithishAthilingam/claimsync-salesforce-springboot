package com.claimsync.risk.rules;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import org.springframework.stereotype.Component;

@Component
public class EarlyPolicyInceptionRule implements RiskScoringRule {

    private static final long EARLY_CLAIM_WINDOW_DAYS = 30L;

    @Override
    public int calculateRiskPoints(ClaimEvaluationRequest request) {
        if (request.incidentDate() == null || request.policyEffectiveDate() == null) {
            return 0;
        }
        long daysSinceInception = ChronoUnit.DAYS.between(
                request.policyEffectiveDate(),
                request.incidentDate()
        );
        if (daysSinceInception >= 0 && daysSinceInception <= EARLY_CLAIM_WINDOW_DAYS) {
            return 20;
        }
        return 5;
    }

    @Override
    public Optional<String> describeFinding(ClaimEvaluationRequest request) {
        if (calculateRiskPoints(request) >= 20) {
            return Optional.of("EARLY_POLICY_INCEPTION: Claim filed within 30 days of policy effective date");
        }
        return Optional.empty();
    }
}
