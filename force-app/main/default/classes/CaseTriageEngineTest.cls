/**
 * Test class for CaseTriageEngine
 * Tests scoring logic, band calculation, and routing determination
 */
@isTest
private class CaseTriageEngineTest {
    
    /**
     * Create test data
     */
    @testSetup
    static void setupTestData() {
        // Create test cases with different scenarios
        List<Case> testCases = new List<Case>();
        
        // Low priority case
        testCases.add(new Case(
            Subject = 'General inquiry about features',
            Description = 'I would like to know more about your product features.',
            Priority = 'Low',
            Status = 'New',
            Origin = 'Web'
        ));
        
        // Security breach case
        testCases.add(new Case(
            Subject = 'Security breach detected - urgent',
            Description = 'We noticed unauthorized access to our account. Possible phishing attack.',
            Priority = 'High',
            Status = 'New',
            Origin = 'Phone'
        ));
        
        // Billing case
        testCases.add(new Case(
            Subject = 'Refund request for invoice #12345',
            Description = 'I was overcharged on my last billing cycle. Please process a refund.',
            Priority = 'Medium',
            Status = 'New',
            Origin = 'Email'
        ));
        
        // Engineering/API case
        testCases.add(new Case(
            Subject = 'API error 500 on integration',
            Description = 'Our webhook integration is failing with a bug. The endpoint returns errors.',
            Priority = 'High',
            Status = 'New',
            Origin = 'Web'
        ));
        
        // Angry customer case
        testCases.add(new Case(
            Subject = 'Unacceptable service - demand refund',
            Description = 'This is ridiculous! Your terrible service has caused us problems. I will contact my attorney.',
            Priority = 'Medium',
            Status = 'New',
            Origin = 'Email'
        ));
        
        // Escalated case
        testCases.add(new Case(
            Subject = 'Product not working',
            Description = 'The product stopped working yesterday.',
            Priority = 'Medium',
            Status = 'Escalated',
            Origin = 'Phone'
        ));
        
        insert testCases;
    }
    
    /**
     * Test low priority case scoring
     */
    @isTest
    static void testLowPriorityCase() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'General inquiry about features' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        System.assert(result.priorityScore < 30, 'Low priority case should have score < 30');
        System.assertEquals('Low', result.priorityBand, 'Band should be Low');
        System.assertEquals('L1 Support', result.recommendedRouting, 'Should route to L1 Support');
    }
    
    /**
     * Test security breach case - should be critical
     */
    @isTest
    static void testHighPrioritySecurityCase() {
        Case testCase = [SELECT Id FROM Case WHERE Subject LIKE '%Security breach%' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        System.assert(result.priorityScore >= 60, 'Security case should have high score');
        System.assertEquals('Security', result.recommendedRouting, 'Should route to Security team');
        System.assert(result.reasons.size() > 0, 'Should have reasons');
    }
    
    /**
     * Test billing keywords routing
     */
    @isTest
    static void testBillingKeywords() {
        Case testCase = [SELECT Id FROM Case WHERE Subject LIKE '%Refund request%' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        System.assertEquals('Billing', result.recommendedRouting, 'Should route to Billing team');
        
        // Check that billing keywords were detected in reasons
        Boolean foundBillingReason = false;
        for (String reason : result.reasons) {
            if (reason.toLowerCase().contains('billing') || reason.toLowerCase().contains('refund')) {
                foundBillingReason = true;
                break;
            }
        }
        System.assert(foundBillingReason, 'Should mention billing/refund in reasons');
    }
    
    /**
     * Test engineering keywords routing
     */
    @isTest
    static void testEngineeringKeywords() {
        Case testCase = [SELECT Id FROM Case WHERE Subject LIKE '%API error%' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        System.assertEquals('Engineering', result.recommendedRouting, 'Should route to Engineering team');
    }
    
    /**
     * Test angry language detection
     */
    @isTest
    static void testAngryLanguage() {
        Case testCase = [SELECT Id FROM Case WHERE Subject LIKE '%Unacceptable%' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        // Should have boosted score due to angry language
        System.assert(result.priorityScore >= 30, 'Angry case should have elevated score');
        
        // Check for frustrated language reason
        Boolean foundAngryReason = false;
        for (String reason : result.reasons) {
            if (reason.toLowerCase().contains('frustrated') || reason.toLowerCase().contains('language')) {
                foundAngryReason = true;
                break;
            }
        }
        System.assert(foundAngryReason, 'Should detect frustrated language');
    }
    
    /**
     * Test phone origin scoring
     */
    @isTest
    static void testPhoneOrigin() {
        Case testCase = [SELECT Id FROM Case WHERE Origin = 'Phone' AND Subject LIKE '%Security%' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        // Check that origin was factored in reasons
        Boolean foundOriginReason = false;
        for (String reason : result.reasons) {
            if (reason.toLowerCase().contains('origin') && reason.toLowerCase().contains('phone')) {
                foundOriginReason = true;
                break;
            }
        }
        System.assert(foundOriginReason, 'Should mention phone origin in reasons');
    }
    
    /**
     * Test band boundaries
     */
    @isTest
    static void testBandBoundaries() {
        // Test the TriageResultDTO band calculation directly
        TriageResultDTO result = new TriageResultDTO();
        
        // Test Low boundary (0-29)
        result.priorityScore = 29;
        result.calculateBand();
        System.assertEquals('Low', result.priorityBand, 'Score 29 should be Low');
        
        // Test Medium boundary (30-59)
        result.priorityScore = 30;
        result.calculateBand();
        System.assertEquals('Medium', result.priorityBand, 'Score 30 should be Medium');
        
        result.priorityScore = 59;
        result.calculateBand();
        System.assertEquals('Medium', result.priorityBand, 'Score 59 should be Medium');
        
        // Test High boundary (60-79)
        result.priorityScore = 60;
        result.calculateBand();
        System.assertEquals('High', result.priorityBand, 'Score 60 should be High');
        
        result.priorityScore = 79;
        result.calculateBand();
        System.assertEquals('High', result.priorityBand, 'Score 79 should be High');
        
        // Test Critical boundary (80-100)
        result.priorityScore = 80;
        result.calculateBand();
        System.assertEquals('Critical', result.priorityBand, 'Score 80 should be Critical');
        
        result.priorityScore = 100;
        result.calculateBand();
        System.assertEquals('Critical', result.priorityBand, 'Score 100 should be Critical');
    }
    
    /**
     * Test escalated status scoring
     */
    @isTest
    static void testEscalatedStatus() {
        Case testCase = [SELECT Id FROM Case WHERE Status = 'Escalated' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        // Check that escalated status was factored in
        Boolean foundEscalatedReason = false;
        for (String reason : result.reasons) {
            if (reason.toLowerCase().contains('escalat')) {
                foundEscalatedReason = true;
                break;
            }
        }
        System.assert(foundEscalatedReason, 'Should detect escalated status');
    }
    
    /**
     * Test suggested actions are populated
     */
    @isTest
    static void testSuggestedActions() {
        Case testCase = [SELECT Id FROM Case WHERE Subject LIKE '%Security breach%' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageEngine.computeTriage(testCase.Id);
        Test.stopTest();
        
        System.assert(result.suggestedActions != null, 'Suggested actions should not be null');
        System.assert(result.suggestedActions.size() > 0, 'Should have suggested actions');
    }
    
    /**
     * Test TriageResultDTO JSON serialization
     */
    @isTest
    static void testTriageResultDTOSerialization() {
        TriageResultDTO result = new TriageResultDTO();
        result.priorityScore = 75;
        result.priorityBand = 'High';
        result.recommendedRouting = 'Engineering';
        result.addReason('Test reason');
        result.addSuggestedAction('Test action');
        
        String jsonString = result.toJson();
        System.assert(String.isNotBlank(jsonString), 'JSON should not be blank');
        
        TriageResultDTO deserialized = TriageResultDTO.fromJson(jsonString);
        System.assertEquals(75, deserialized.priorityScore, 'Score should deserialize correctly');
        System.assertEquals('High', deserialized.priorityBand, 'Band should deserialize correctly');
    }
    
    /**
     * Test with null case ID
     */
    @isTest
    static void testNullCase() {
        Test.startTest();
        // Create a fake ID that doesn't exist
        Id fakeId = '500000000000000AAA';
        TriageResultDTO result = CaseTriageEngine.computeTriage(fakeId);
        Test.stopTest();
        
        System.assertEquals(0, result.priorityScore, 'Score should be 0 for non-existent case');
    }
}
