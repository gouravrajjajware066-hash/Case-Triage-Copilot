/**
 * Test class for CaseTriageController
 * Tests all controller methods including actions and triage logging
 */
@isTest
private class CaseTriageControllerTest {
    
    /**
     * Create test data
     */
    @testSetup
    static void setupTestData() {
        // Create test case
        Case testCase = new Case(
            Subject = 'Test Case for Controller',
            Description = 'This is a test case description for testing the controller.',
            Priority = 'Medium',
            Status = 'New',
            Origin = 'Email'
        );
        insert testCase;
        
        // Create EmailMessage
        EmailMessage testEmail = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Customer inquiry',
            TextBody = 'Hello, I need help with my account.',
            FromAddress = 'customer@test.com',
            ToAddress = 'support@company.com',
            MessageDate = Datetime.now(),
            Incoming = true
        );
        insert testEmail;
        
        // Create CaseComment
        CaseComment testComment = new CaseComment(
            ParentId = testCase.Id,
            CommentBody = 'This is a test comment on the case.',
            IsPublished = true
        );
        insert testComment;
    }
    
    /**
     * Test getCaseContext method
     */
    @isTest
    static void testGetCaseContext() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        CaseContextDTO context = CaseTriageController.getCaseContext(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, context, 'Context should not be null');
        System.assertNotEquals(null, context.caseRecord, 'Case record should not be null');
        System.assertEquals('Test Case for Controller', context.caseRecord.Subject, 'Subject should match');
        System.assertEquals(1, context.recentEmails.size(), 'Should have 1 email');
        System.assertEquals(1, context.recentComments.size(), 'Should have 1 comment');
    }
    
    /**
     * Test getCaseContext with invalid ID
     */
    @isTest
    static void testGetCaseContextInvalidId() {
        Id fakeId = '500000000000000AAA';
        
        Test.startTest();
        try {
            CaseContextDTO context = CaseTriageController.getCaseContext(fakeId);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not found'), 'Should mention not found');
        }
        Test.stopTest();
    }
    
    /**
     * Test getTriageResult method
     */
    @isTest
    static void testGetTriageResult() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        TriageResultDTO result = CaseTriageController.getTriageResult(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.priorityScore, 'Score should not be null');
        System.assertNotEquals(null, result.priorityBand, 'Band should not be null');
        System.assertNotEquals(null, result.recommendedRouting, 'Routing should not be null');
    }
    
    /**
     * Test generateAIDraft method
     */
    @isTest
    static void testGenerateAIDraft() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        // Set up mock
        Test.setMock(HttpCalloutMock.class, new OpenAIMockCallout(200, OpenAIMockCallout.getSuccessResponseBody()));
        
        Test.startTest();
        AIDraftDTO result = CaseTriageController.generateAIDraft(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.success, 'Should be successful');
        System.assert(String.isNotBlank(result.draftText), 'Draft text should not be blank');
    }
    
    /**
     * Test CREATE_TASK action
     */
    @isTest
    static void testCreateTaskAction() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        ActionResultDTO result = CaseTriageController.takeAction(testCase.Id, 'CREATE_TASK');
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should be successful');
        System.assertNotEquals(null, result.createdRecordId, 'Should have created record ID');
        System.assert(result.message.contains('task'), 'Message should mention task');
        
        // Verify task was created
        List<Task> tasks = [SELECT Id, Subject, WhatId FROM Task WHERE WhatId = :testCase.Id];
        System.assertEquals(1, tasks.size(), 'Should have created 1 task');
    }
    
    /**
     * Test ESCALATE action
     */
    @isTest
    static void testEscalateAction() {
        Case testCase = [SELECT Id, Priority, Status FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        ActionResultDTO result = CaseTriageController.takeAction(testCase.Id, 'ESCALATE');
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should be successful');
        System.assert(result.message.toLowerCase().contains('escalat'), 'Message should mention escalation');
        
        // Verify case was updated
        Case updatedCase = [SELECT Priority, Status FROM Case WHERE Id = :testCase.Id];
        System.assertEquals('High', updatedCase.Priority, 'Priority should be High');
    }
    
    /**
     * Test UPDATE_STATUS action
     */
    @isTest
    static void testUpdateStatusAction() {
        Case testCase = [SELECT Id, Status FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        ActionResultDTO result = CaseTriageController.takeAction(testCase.Id, 'UPDATE_STATUS');
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should be successful');
        System.assert(result.message.contains('Status'), 'Message should mention status');
        
        // Verify case status was updated
        Case updatedCase = [SELECT Status FROM Case WHERE Id = :testCase.Id];
        System.assertEquals('In Progress', updatedCase.Status, 'Status should be In Progress');
    }
    
    /**
     * Test UPDATE_STATUS toggle (from In Progress to Waiting)
     */
    @isTest
    static void testUpdateStatusToggle() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        testCase.Status = 'In Progress';
        update testCase;
        
        Test.startTest();
        ActionResultDTO result = CaseTriageController.takeAction(testCase.Id, 'UPDATE_STATUS');
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should be successful');
        
        Case updatedCase = [SELECT Status FROM Case WHERE Id = :testCase.Id];
        System.assertEquals('Waiting on Customer', updatedCase.Status, 'Status should toggle to Waiting on Customer');
    }
    
    /**
     * Test unknown action type
     */
    @isTest
    static void testUnknownActionType() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        ActionResultDTO result = CaseTriageController.takeAction(testCase.Id, 'INVALID_ACTION');
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should not be successful');
        System.assert(result.message.contains('Unknown'), 'Message should mention unknown action');
    }
    
    /**
     * Test saveTriageLog method
     */
    @isTest
    static void testSaveTriageLog() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        TriageResultDTO triage = new TriageResultDTO();
        triage.priorityScore = 50;
        triage.priorityBand = 'Medium';
        triage.recommendedRouting = 'L1 Support';
        triage.addReason('Test reason');
        
        String triageJson = triage.toJson();
        String draftReply = 'Test draft reply';
        String actionJson = '{"actions":["CREATE_TASK"]}';
        String snapshotJson = '{"subject":"Test Case"}';
        
        Test.startTest();
        Id logId = CaseTriageController.saveTriageLog(
            testCase.Id,
            triageJson,
            draftReply,
            true,
            actionJson,
            snapshotJson,
            null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, logId, 'Log ID should not be null');
        
        // Verify log was created
        Case_Triage__c log = [
            SELECT Case__c, Priority_Score__c, Priority_Band__c, Recommended_Routing__c,
                   AI_Draft_Reply__c, AI_Used__c, Actions_Taken__c, Data_Snapshot__c
            FROM Case_Triage__c
            WHERE Id = :logId
        ];
        
        System.assertEquals(testCase.Id, log.Case__c, 'Case ID should match');
        System.assertEquals(50, log.Priority_Score__c, 'Score should match');
        System.assertEquals('Medium', log.Priority_Band__c, 'Band should match');
        System.assertEquals('L1 Support', log.Recommended_Routing__c, 'Routing should match');
        System.assertEquals(draftReply, log.AI_Draft_Reply__c, 'Draft reply should match');
        System.assertEquals(true, log.AI_Used__c, 'AI Used should be true');
    }
    
    /**
     * Test saveTriageLog with error
     */
    @isTest
    static void testSaveTriageLogWithError() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        Test.startTest();
        Id logId = CaseTriageController.saveTriageLog(
            testCase.Id,
            '{}',
            null,
            false,
            null,
            null,
            'Test error message'
        );
        Test.stopTest();
        
        Case_Triage__c log = [SELECT Error__c FROM Case_Triage__c WHERE Id = :logId];
        System.assertEquals('Test error message', log.Error__c, 'Error should be saved');
    }
    
    /**
     * Test getRecentTriageLogs method
     */
    @isTest
    static void testGetRecentTriageLogs() {
        Case testCase = [SELECT Id FROM Case WHERE Subject = 'Test Case for Controller' LIMIT 1];
        
        // Create some triage logs
        List<Case_Triage__c> logs = new List<Case_Triage__c>();
        for (Integer i = 0; i < 7; i++) {
            logs.add(new Case_Triage__c(
                Case__c = testCase.Id,
                Triage_Timestamp__c = Datetime.now().addMinutes(-i),
                Priority_Score__c = 50 + i,
                Priority_Band__c = 'Medium',
                Recommended_Routing__c = 'L1 Support'
            ));
        }
        insert logs;
        
        Test.startTest();
        List<Case_Triage__c> recentLogs = CaseTriageController.getRecentTriageLogs(testCase.Id);
        Test.stopTest();
        
        System.assertEquals(5, recentLogs.size(), 'Should return only 5 logs');
        // Verify ordering (most recent first)
        System.assert(recentLogs[0].Priority_Score__c >= recentLogs[1].Priority_Score__c, 
                      'Logs should be ordered by timestamp descending');
    }
    
    /**
     * Test ActionResultDTO factory methods
     */
    @isTest
    static void testActionResultDTOFactoryMethods() {
        // Test success without record ID
        ActionResultDTO successDTO = ActionResultDTO.success('Success message');
        System.assertEquals(true, successDTO.success, 'Success should be true');
        System.assertEquals('Success message', successDTO.message, 'Message should match');
        System.assertEquals(null, successDTO.createdRecordId, 'Record ID should be null');
        
        // Test success with record ID
        Id fakeId = '00T000000000001AAA';
        ActionResultDTO successWithIdDTO = ActionResultDTO.success('Created', fakeId);
        System.assertEquals(fakeId, successWithIdDTO.createdRecordId, 'Record ID should match');
        
        // Test error
        ActionResultDTO errorDTO = ActionResultDTO.error('Error message');
        System.assertEquals(false, errorDTO.success, 'Success should be false');
        System.assertEquals('Error message', errorDTO.message, 'Error message should match');
    }
    
    /**
     * Test CaseContextDTO EmailMessageDTO
     */
    @isTest
    static void testEmailMessageDTO() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        EmailMessage email = [SELECT Id, Subject, TextBody, HtmlBody, FromAddress, ToAddress, MessageDate, Incoming 
                              FROM EmailMessage WHERE ParentId = :testCase.Id LIMIT 1];
        
        CaseContextDTO.EmailMessageDTO dto = new CaseContextDTO.EmailMessageDTO(email);
        
        System.assertEquals(email.Id, dto.emailId, 'Email ID should match');
        System.assertEquals(email.Subject, dto.subject, 'Subject should match');
        System.assertEquals(email.FromAddress, dto.fromAddress, 'From address should match');
        System.assertEquals(email.Incoming, dto.incoming, 'Incoming flag should match');
    }
    
    /**
     * Test CaseContextDTO CaseCommentDTO
     */
    @isTest
    static void testCaseCommentDTO() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        CaseComment comment = [SELECT Id, CommentBody, CreatedDate, IsPublished 
                               FROM CaseComment WHERE ParentId = :testCase.Id LIMIT 1];
        
        CaseContextDTO.CaseCommentDTO dto = new CaseContextDTO.CaseCommentDTO(comment);
        
        System.assertEquals(comment.Id, dto.commentId, 'Comment ID should match');
        System.assertEquals(comment.CommentBody, dto.commentBody, 'Comment body should match');
        System.assertEquals(comment.IsPublished, dto.isPublished, 'IsPublished should match');
    }
}
