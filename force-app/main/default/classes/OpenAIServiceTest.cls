/**
 * Test class for OpenAIService
 * Uses HttpCalloutMock to simulate OpenAI API responses
 */
@isTest
private class OpenAIServiceTest {
    
    /**
     * Set up test config for OpenAI
     */
    private static void setupTestConfig() {
        OpenAI_Config__mdt config = new OpenAI_Config__mdt(
            DeveloperName = 'Default',
            Label = 'Default',
            Model__c = 'gpt-4o',
            MaxTokens__c = 500,
            Endpoint__c = '/v1/chat/completions',
            API_Key__c = 'test-api-key-12345'
        );
        OpenAIService.testConfig = config;
    }
    
    /**
     * Create test context and triage data
     */
    private static CaseContextDTO createTestContext() {
        CaseContextDTO context = new CaseContextDTO();
        
        // Create a mock case record
        Case testCase = new Case(
            Subject = 'Test Case Subject',
            Description = 'Test case description for AI draft generation.',
            Priority = 'Medium',
            Status = 'New'
        );
        insert testCase;
        
        // Query the case to get all fields
        context.caseRecord = [SELECT Id, Subject, Description, Priority, Status FROM Case WHERE Id = :testCase.Id];
        
        // Add a mock email
        CaseContextDTO.EmailMessageDTO email = new CaseContextDTO.EmailMessageDTO();
        email.subject = 'Help needed';
        email.textBody = 'I am having trouble with my account. Please help me resolve this issue.';
        email.fromAddress = 'customer@test.com';
        email.incoming = true;
        email.messageDate = Datetime.now();
        context.recentEmails.add(email);
        
        return context;
    }
    
    private static TriageResultDTO createTestTriage() {
        TriageResultDTO triage = new TriageResultDTO();
        triage.priorityScore = 45;
        triage.priorityBand = 'Medium';
        triage.recommendedRouting = 'L1 Support';
        triage.addReason('Standard support inquiry');
        return triage;
    }
    
    /**
     * Test successful draft generation
     */
    @isTest
    static void testSuccessfulDraftGeneration() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(200, OpenAIMockCallout.getSuccessResponseBody()));
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should be successful');
        System.assert(String.isNotBlank(result.draftText), 'Draft text should not be blank');
        System.assertEquals('gpt-4o', result.model, 'Model should be gpt-4o');
        System.assert(result.tokensUsed > 0, 'Tokens used should be > 0');
        System.assert(String.isBlank(result.error), 'Error should be blank on success');
    }
    
    /**
     * Test unauthorized (401) response
     */
    @isTest
    static void testUnauthorized401() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(401, OpenAIMockCallout.getUnauthorizedResponseBody()));
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful');
        System.assert(result.error.contains('Authentication'), 'Error should mention authentication');
    }
    
    /**
     * Test rate limited (429) response
     */
    @isTest
    static void testRateLimited429() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(429, OpenAIMockCallout.getRateLimitResponseBody()));
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful');
        System.assert(result.error.toLowerCase().contains('rate limit'), 'Error should mention rate limit');
    }
    
    /**
     * Test server error (500) response
     */
    @isTest
    static void testServerError500() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(500, OpenAIMockCallout.getServerErrorResponseBody()));
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful');
        System.assert(String.isNotBlank(result.error), 'Error should not be blank');
    }
    
    /**
     * Test malformed JSON response
     */
    @isTest
    static void testMalformedResponse() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(200, OpenAIMockCallout.getMalformedResponseBody()));
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful with malformed response');
        System.assert(result.error.contains('parse'), 'Error should mention parsing');
    }
    
    /**
     * Test empty choices response
     */
    @isTest
    static void testEmptyChoicesResponse() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(200, OpenAIMockCallout.getEmptyChoicesResponseBody()));
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful with empty choices');
        System.assert(result.error.contains('No response'), 'Error should mention no response');
    }
    
    /**
     * Test timeout handling
     */
    @isTest
    static void testTimeout() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(true)); // Simulate timeout
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful on timeout');
        System.assert(result.error.toLowerCase().contains('connection') || result.error.toLowerCase().contains('error'), 
                      'Error should mention connection issue');
    }
    
    /**
     * Test with null context
     */
    @isTest
    static void testNullContext() {
        setupTestConfig();
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(200, OpenAIMockCallout.getSuccessResponseBody()));
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(null, null);
        Test.stopTest();
        
        // Should handle gracefully
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    /**
     * Test without API key configured
     */
    @isTest
    static void testNoApiKey() {
        // Set config without API key
        OpenAI_Config__mdt config = new OpenAI_Config__mdt(
            DeveloperName = 'Default',
            Label = 'Default',
            Model__c = 'gpt-4o',
            MaxTokens__c = 500,
            Endpoint__c = '/v1/chat/completions',
            API_Key__c = ''  // Empty API key
        );
        OpenAIService.testConfig = config;
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful without API key');
        System.assert(result.error.contains('API key'), 'Error should mention API key');
    }
    
    /**
     * Test with no config at all
     */
    @isTest
    static void testNoConfig() {
        // Don't set any config
        OpenAIService.testConfig = null;
        
        CaseContextDTO context = createTestContext();
        TriageResultDTO triage = createTestTriage();
        
        Test.startTest();
        AIDraftDTO result = OpenAIService.generateDraft(context, triage);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful without config');
        System.assert(result.error.contains('configuration'), 'Error should mention configuration');
    }
    
    /**
     * Test AIDraftDTO factory methods
     */
    @isTest
    static void testAIDraftDTOFactoryMethods() {
        // Test success factory
        AIDraftDTO successDTO = AIDraftDTO.success('Test draft', 'gpt-4o', 100);
        System.assertEquals(true, successDTO.success, 'Success should be true');
        System.assertEquals('Test draft', successDTO.draftText, 'Draft text should match');
        System.assertEquals('gpt-4o', successDTO.model, 'Model should match');
        System.assertEquals(100, successDTO.tokensUsed, 'Tokens should match');
        
        // Test error factory
        AIDraftDTO errorDTO = AIDraftDTO.error('Test error');
        System.assertEquals(false, errorDTO.success, 'Success should be false');
        System.assertEquals('Test error', errorDTO.error, 'Error should match');
        
        // Test error factory with model
        AIDraftDTO errorWithModelDTO = AIDraftDTO.error('Test error', 'gpt-4o');
        System.assertEquals(false, errorWithModelDTO.success, 'Success should be false');
        System.assertEquals('gpt-4o', errorWithModelDTO.model, 'Model should match');
    }
}
