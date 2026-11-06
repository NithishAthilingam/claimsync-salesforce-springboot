package com.claimsync.risk.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDate;

public record ClaimEvaluationRequest(
        @NotBlank(message = "claimId is required")
        String claimId,
        String claimNumber,
        @NotBlank(message = "policyNumber is required")
        String policyNumber,
        @NotNull(message = "claimAmount is required")
        @DecimalMin(value = "0.01", message = "claimAmount must be positive")
        BigDecimal claimAmount,
        @NotNull(message = "coverageLimit is required")
        @DecimalMin(value = "0.01", message = "coverageLimit must be positive")
        BigDecimal coverageLimit,
        LocalDate incidentDate,
        LocalDate policyEffectiveDate,
        String incidentDescription
) {
}
