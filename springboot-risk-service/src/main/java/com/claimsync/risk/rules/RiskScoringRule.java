package com.claimsync.risk.rules;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import java.util.Optional;

/**
 * Strategy interface for modular insurance fraud and underwriting risk scoring rules.
 */
public interface RiskScoringRule {

    int calculateRiskPoints(ClaimEvaluationRequest request);

    Optional<String> describeFinding(ClaimEvaluationRequest request);
}
