package com.claimsync.risk.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class ClaimEvaluationControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("POST /api/v1/claims/evaluate returns 200 OK and risk evaluation payload")
    void shouldEvaluateClaimViaRestEndpoint() throws Exception {
        String payload = """
                {
                  "claimId": "a01000000000099AAA",
                  "claimNumber": "CLM-00099",
                  "policyNumber": "POL-AUTO-9001",
                  "claimAmount": 38000.00,
                  "coverageLimit": 50000.00,
                  "incidentDate": "2026-10-25",
                  "policyEffectiveDate": "2026-10-10",
                  "incidentDescription": "Unwitnessed total loss vehicle fire."
                }
                """;

        mockMvc.perform(post("/api/v1/claims/evaluate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.claimId").value("a01000000000099AAA"))
                .andExpect(jsonPath("$.recommendedStatus").value("Flagged for Adjuster"))
                .andExpect(jsonPath("$.riskScore").isNumber());
    }

    @Test
    @DisplayName("POST /api/v1/claims/evaluate returns 400 Bad Request when claimAmount is missing")
    void shouldRejectInvalidClaimPayload() throws Exception {
        String invalidPayload = """
                {
                  "claimId": "a01000000000099AAA",
                  "policyNumber": "POL-AUTO-9001"
                }
                """;

        mockMvc.perform(post("/api/v1/claims/evaluate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(invalidPayload))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("GET /api/v1/claims/health returns UP status")
    void shouldReturnHealthStatus() throws Exception {
        mockMvc.perform(get("/api/v1/claims/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
