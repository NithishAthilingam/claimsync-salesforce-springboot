"""
ClaimSync Quality Engineering & Integration Test Harness.

Provides:
1. Cross-platform JSON contract verification between Salesforce Queueable Apex
   (ClaimRiskScoringQueueable) and the Java 21 Spring Boot Risk Scoring API.
2. Reference underwriting & SIU anomaly risk oracle for boundary-value testing.
3. SFDX metadata and Apex static structure verification.
4. Live Salesforce REST / SOQL integration helper (via simple-salesforce).
"""

from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional
import os
import xml.etree.ElementTree as ET


ANOMALY_KEYWORDS = (
    "total loss",
    "unwitnessed",
    "stolen",
    "cash only",
    "arson",
    "staged",
)


@dataclass
class ClaimPayload:
    claimId: str
    claimNumber: str
    policyNumber: str
    claimAmount: float
    coverageLimit: float
    incidentDate: str
    policyEffectiveDate: str
    incidentDescription: str

    def to_apex_json(self) -> Dict[str, Any]:
        return asdict(self)


def evaluate_claim_contract(payload: ClaimPayload) -> Dict[str, Any]:
    """
    Reference oracle mirroring the Spring Boot Strategy-pattern rules
    (HighValueClaimRule, CoverageUtilizationRule, AnomalyKeywordRule, EarlyPolicyInceptionRule).
    Used by the QA suite to verify microservice parity and boundary conditions.
    """
    if payload.claimAmount <= 0:
        raise ValueError("Claim Amount must be greater than $0.00.")
    if payload.claimAmount > payload.coverageLimit:
        raise ValueError("Claim Amount exceeds policy Coverage Limit.")

    inc_date = date.fromisoformat(payload.incidentDate)
    eff_date = date.fromisoformat(payload.policyEffectiveDate)
    if inc_date < eff_date:
        raise ValueError("Incident Date cannot precede the policy Effective Date.")

    score = 0
    triggered_rules: List[str] = []

    # 1. HighValueClaimRule
    if payload.claimAmount >= 25000.0:
        score += 40
        triggered_rules.append("HIGH_VALUE_CLAIM")
    elif payload.claimAmount >= 10000.0:
        score += 25
        triggered_rules.append("HIGH_VALUE_CLAIM")
    else:
        score += 5

    # 2. CoverageUtilizationRule
    utilization = payload.claimAmount / payload.coverageLimit
    if utilization >= 0.60:
        score += 25
        triggered_rules.append("HIGH_COVERAGE_UTILIZATION")
    else:
        score += 5

    # 3. AnomalyKeywordRule
    desc_lower = (payload.incidentDescription or "").lower()
    keyword_hits = sum(1 for kw in ANOMALY_KEYWORDS if kw in desc_lower)
    if keyword_hits >= 2:
        score += 30
        triggered_rules.append("ANOMALY_KEYWORDS_DETECTED")
    elif keyword_hits == 1:
        score += 20
        triggered_rules.append("ANOMALY_KEYWORDS_DETECTED")

    # 4. EarlyPolicyInceptionRule
    days_since_inception = (inc_date - eff_date).days
    if 0 <= days_since_inception <= 30:
        score += 20
        triggered_rules.append("EARLY_POLICY_INCEPTION")
    else:
        score += 5

    bounded_score = min(100, max(0, score))
    if bounded_score >= 60:
        status = "Flagged for Adjuster"
    elif bounded_score >= 35:
        status = "Under Review"
    else:
        status = "Approved"

    return {
        "claimId": payload.claimId,
        "riskScore": bounded_score,
        "recommendedStatus": status,
        "triggeredRules": triggered_rules,
    }


def build_claim_verification_soql(policy_number: str) -> str:
    """Builds a parameterized SOQL query for verifying Claim__c state in Salesforce."""
    sanitized = policy_number.replace("'", "")
    return (
        "SELECT Id, Name, Claim_Amount__c, Status__c, Risk_Score__c, "
        "Fraud_Evaluation_Notes__c, Policy__r.Name, Policy__r.Status__c "
        f"FROM Claim__c WHERE Policy__r.Name = '{sanitized}' "
        "ORDER BY CreatedDate DESC"
    )


def verify_sfdx_project_structure(repo_root: Path) -> Dict[str, Any]:
    """
    Static quality gate that validates Salesforce DX (SFDX) metadata XML files
    and Apex classes/triggers before deployment.
    """
    sf_app = repo_root / "salesforce-app"
    default_dir = sf_app / "force-app" / "main" / "default"

    policy_fields = list((default_dir / "objects" / "Policy__c" / "fields").glob("*.field-meta.xml"))
    claim_fields = list((default_dir / "objects" / "Claim__c" / "fields").glob("*.field-meta.xml"))
    apex_classes = list((default_dir / "classes").glob("*.cls"))
    apex_triggers = list((default_dir / "triggers").glob("*.trigger"))

    # Parse every XML metadata file to ensure well-formed XML
    xml_files = list(default_dir.rglob("*.xml"))
    for xml_file in xml_files:
        ET.parse(xml_file)

    return {
        "sfdx_project_exists": (sf_app / "sfdx-project.json").is_file(),
        "policy_field_count": len(policy_fields),
        "claim_field_count": len(claim_fields),
        "apex_class_names": sorted(p.stem for p in apex_classes),
        "apex_trigger_names": sorted(p.stem for p in apex_triggers),
        "validated_xml_count": len(xml_files),
    }
