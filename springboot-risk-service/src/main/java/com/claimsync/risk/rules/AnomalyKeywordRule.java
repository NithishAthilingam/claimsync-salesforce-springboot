package com.claimsync.risk.rules;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import org.springframework.stereotype.Component;

@Component
public class AnomalyKeywordRule implements RiskScoringRule {

    private static final List<String> ANOMALY_KEYWORDS = List.of(
            "total loss",
            "unwitnessed",
            "stolen",
            "cash only",
            "arson",
            "staged"
    );

    @Override
    public int calculateRiskPoints(ClaimEvaluationRequest request) {
        if (request.incidentDescription() == null || request.incidentDescription().isBlank()) {
            return 0;
        }
        String normalized = request.incidentDescription().toLowerCase(Locale.ROOT);
        long matches = ANOMALY_KEYWORDS.stream().filter(normalized::contains).count();
        if (matches >= 2) {
            return 30;
        }
        if (matches == 1) {
            return 20;
        }
        return 0;
    }

    @Override
    public Optional<String> describeFinding(ClaimEvaluationRequest request) {
        int points = calculateRiskPoints(request);
        if (points > 0) {
            return Optional.of("ANOMALY_KEYWORDS_DETECTED: Incident narrative contains special investigative unit (SIU) indicators");
        }
        return Optional.empty();
    }
}
