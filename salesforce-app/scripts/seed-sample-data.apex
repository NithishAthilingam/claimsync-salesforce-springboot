// Anonymous Apex script to seed sample Insurance Policies (Policy__c) and Claims (Claim__c)
// Run with: sf apex run --file scripts/seed-sample-data.apex --target-org claimsync-dev

List<Policy__c> existingPolicies = [SELECT Id FROM Policy__c WHERE Name LIKE 'NW-POL-%'];
if (!existingPolicies.isEmpty()) {
    delete [SELECT Id FROM Claim__c WHERE Policy__c IN :existingPolicies];
    delete existingPolicies;
}

Policy__c autoPolicy = new Policy__c(
    Name = 'NW-POL-AUTO-8841',
    Coverage_Limit__c = 100000.00,
    Status__c = 'Active',
    Effective_Date__c = Date.today().addDays(-180),
    Policyholder_Email__c = 'alex.mercer@example.com'
);

Policy__c propertyPolicy = new Policy__c(
    Name = 'NW-POL-PROP-9920',
    Coverage_Limit__c = 250000.00,
    Status__c = 'Active',
    Effective_Date__c = Date.today().addDays(-45),
    Policyholder_Email__c = 'elena.rodriguez@example.com'
);

insert new List<Policy__c>{ autoPolicy, propertyPolicy };

List<Claim__c> sampleClaims = new List<Claim__c>{
    new Claim__c(
        Policy__c = autoPolicy.Id,
        Claim_Amount__c = 1850.00,
        Incident_Date__c = Date.today().addDays(-7),
        Incident_Description__c = 'Front windshield cracked by highway gravel debris.'
    ),
    new Claim__c(
        Policy__c = propertyPolicy.Id,
        Claim_Amount__c = 42500.00,
        Incident_Date__c = Date.today().addDays(-2),
        Incident_Description__c = 'Severe hailstorm roof damage and total loss of detached garage.'
    )
};

insert sampleClaims;
System.debug('Seeded ' + sampleClaims.size() + ' claims linked to Policy__c records.');
