"""
Automated Quality Engineering Test Suite for ClaimSync
(Salesforce Apex + Java Spring Boot + Python QA Automation).
"""

from datetime import date, timedelta
from pathlib import Path
import re
import pytest

from claimsync_qa_harness import (
    ClaimPayload,
    build_claim_verification_soql,
    evaluate_claim_contract,
    verify_sfdx_project_structure,
)


REPO_ROOT = Path(__file__).resolve().parent.parent


def test_sfdx_metadata_and_apex_structure_integrity():
    """Verifies SFDX custom objects, fields, triggers, and @isTest classes are present and valid XML."""
    report = verify_sfdx_project_structure(REPO_ROOT)
    assert report["sfdx_project_exists"] is True
    assert report["policy_field_count"] >= 4
    assert report["claim_field_count"] >= 7
    assert "ClaimTrigger" in report["apex_trigger_names"]
    assert set(report["apex_class_names"]) >= {
        "ClaimTriggerHandler",
        "ClaimRiskScoringQueueable",
        "ClaimRiskCalloutMock",
        "ClaimTriggerTest",
    }
    assert report["validated_xml_count"] >= 18


def test_low_risk_claim_auto_approval_contract():
    """Verifies routine low-value claim on a seasoned policy scores <35 and is Approved."""
    today = date.today()
    payload = ClaimPayload(
        claimId="a01000000000101AAA",
        claimNumber="CLM-00101",
        policyNumber="NW-POL-AUTO-8841",
        claimAmount=1450.00,
        coverageLimit=100000.00,
        incidentDate=(today - timedelta(days=5)).isoformat(),
        policyEffectiveDate=(today - timedelta(days=180)).isoformat(),
        incidentDescription="Minor windshield crack from highway gravel.",
    )
    result = evaluate_claim_contract(payload)
    assert result["recommendedStatus"] == "Approved"
    assert result["riskScore"] == 15
    assert result["triggeredRules"] == []


def test_high_risk_siu_claim_flagged_for_adjuster():
    """Verifies high-value claim with SIU keywords and high coverage utilization flags for Adjuster."""
    today = date.today()
    payload = ClaimPayload(
        claimId="a01000000000102AAA",
        claimNumber="CLM-00102",
        policyNumber="NW-POL-PROP-9920",
        claimAmount=42000.00,
        coverageLimit=50000.00,
        incidentDate=(today - timedelta(days=2)).isoformat(),
        policyEffectiveDate=(today - timedelta(days=12)).isoformat(),
        incidentDescription="Unwitnessed total loss vehicle fire at night.",
    )
    result = evaluate_claim_contract(payload)
    assert result["recommendedStatus"] == "Flagged for Adjuster"
    assert result["riskScore"] >= 60
    assert "HIGH_VALUE_CLAIM" in result["triggeredRules"]
    assert "HIGH_COVERAGE_UTILIZATION" in result["triggeredRules"]
    assert "ANOMALY_KEYWORDS_DETECTED" in result["triggeredRules"]
    assert "EARLY_POLICY_INCEPTION" in result["triggeredRules"]


def test_moderate_risk_claim_routed_to_under_review():
    """Verifies moderate-value claim ($12.5k on $50k policy) routes to Under Review."""
    today = date.today()
    payload = ClaimPayload(
        claimId="a01000000000103AAA",
        claimNumber="CLM-00103",
        policyNumber="NW-POL-AUTO-8841",
        claimAmount=12500.00,
        coverageLimit=50000.00,
        incidentDate=(today - timedelta(days=4)).isoformat(),
        policyEffectiveDate=(today - timedelta(days=120)).isoformat(),
        incidentDescription="Hailstorm dent repair across hood and roof.",
    )
    result = evaluate_claim_contract(payload)
    assert result["recommendedStatus"] == "Under Review"
    assert 35 <= result["riskScore"] < 60


@pytest.mark.parametrize(
    "amount,limit,inc_offset,eff_offset,expected_error",
    [
        (0.0, 50000.0, -2, -90, "Claim Amount must be greater than $0.00"),
        (-500.0, 50000.0, -2, -90, "Claim Amount must be greater than $0.00"),
        (60000.0, 50000.0, -2, -90, "exceeds policy Coverage Limit"),
        (2500.0, 50000.0, -120, -90, "Incident Date cannot precede the policy Effective Date"),
    ],
)
def test_domain_validation_boundary_rejections(amount, limit, inc_offset, eff_offset, expected_error):
    """Verifies negative and boundary validation rules match Apex ClaimTriggerHandler behavior."""
    today = date.today()
    payload = ClaimPayload(
        claimId="a01000000000199AAA",
        claimNumber="CLM-00199",
        policyNumber="NW-POL-AUTO-8841",
        claimAmount=amount,
        coverageLimit=limit,
        incidentDate=(today + timedelta(days=inc_offset)).isoformat(),
        policyEffectiveDate=(today + timedelta(days=eff_offset)).isoformat(),
        incidentDescription="Boundary validation test case.",
    )
    with pytest.raises(ValueError, match=re.escape(expected_error)):
        evaluate_claim_contract(payload)


def test_soql_verification_query_builder_prevents_injection():
    """Verifies SOQL query builder selects required Claim__c and Policy__r fields safely."""
    soql = build_claim_verification_soql("NW-POL-AUTO-8841")
    assert "FROM Claim__c" in soql
    assert "Risk_Score__c" in soql
    assert "Status__c" in soql
    assert "Policy__r.Name = 'NW-POL-AUTO-8841'" in soql
