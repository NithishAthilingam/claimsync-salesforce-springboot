package com.claimsync.risk.controller;

import com.claimsync.risk.dto.ClaimEvaluationRequest;
import com.claimsync.risk.dto.ClaimEvaluationResponse;
import com.claimsync.risk.service.ClaimRiskEvaluationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/claims")
@Tag(name = "Insurance Claims Risk Scoring API", description = "Evaluates Salesforce Claim__c payloads for fraud and underwriting risk")
public class ClaimEvaluationController {

    private final ClaimRiskEvaluationService evaluationService;

    public ClaimEvaluationController(ClaimRiskEvaluationService evaluationService) {
        this.evaluationService = evaluationService;
    }

    @PostMapping("/evaluate")
    @Operation(summary = "Evaluate a Salesforce insurance claim and return a composite fraud/risk score")
    public ResponseEntity<ClaimEvaluationResponse> evaluateClaim(
            @Valid @RequestBody ClaimEvaluationRequest request) {
        return ResponseEntity.ok(evaluationService.evaluateClaim(request));
    }

    @GetMapping("/health")
    @Operation(summary = "Liveness and readiness probe for the ClaimSync Risk Scoring Service")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of(
                "status", "UP",
                "service", "claimsync-springboot-risk-service"
        ));
    }
}
