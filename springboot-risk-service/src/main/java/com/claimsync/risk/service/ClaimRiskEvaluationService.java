package com.claimsync.risk.service;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import com.claimsync.risk.dto.ClaimEvaluationResponse;
import com.claimsync.risk.rules.RiskScoringRule;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class ClaimRiskEvaluationService {

    public static final int ADJUSTER_ESCALATION_SCORE = 60;
    public static final int MANUAL_REVIEW_SCORE = 35;

    private final List<RiskScoringRule> scoringRules;

    public ClaimRiskEvaluationService(List<RiskScoringRule> scoringRules) {
        this.scoringRules = scoringRules;
    }

    public ClaimEvaluationResponse evaluateClaim(ClaimEvaluationRequest request) {
        int rawScore = 0;
        List<String> triggeredFindings = new ArrayList<>();

        for (RiskScoringRule rule : scoringRules) {
            rawScore += rule.calculateRiskPoints(request);
            rule.describeFinding(request).ifPresent(triggeredFindings::add);
        }

        int boundedScore = Math.min(100, Math.max(0, rawScore));
        String recommendedStatus;
        String summary;

        if (boundedScore >= ADJUSTER_ESCALATION_SCORE) {
            recommendedStatus = "Flagged for Adjuster";
            summary = "High-Risk Flag (" + boundedScore + "/100): " + String.join("; ", triggeredFindings);
        } else if (boundedScore >= MANUAL_REVIEW_SCORE) {
            recommendedStatus = "Under Review";
            summary = "Moderate Risk (" + boundedScore + "/100): Queued for standard underwriting review.";
        } else {
            recommendedStatus = "Approved";
            summary = "Auto-Approved (" + boundedScore + "/100): Within standard underwriting risk tolerances.";
        }

        return new ClaimEvaluationResponse(
                request.claimId(),
                BigDecimal.valueOf(boundedScore),
                recommendedStatus,
                summary,
                triggeredFindings
        );
    }
}
