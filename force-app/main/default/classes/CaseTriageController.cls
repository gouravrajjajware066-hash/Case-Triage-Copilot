/**
 * Apex Controller for Case Triage Copilot LWC
 * Provides methods for fetching case context, computing triage,
 * generating AI drafts, taking actions, and saving triage logs.
 * 
 * All methods enforce CRUD/FLS security checks.
 */
public with sharing class CaseTriageController {
    
    /**
     * Get case context including related emails and comments
     * @param caseId The Case record ID
     * @return CaseContextDTO with case data and related records
     */
    @AuraEnabled(cacheable=true)
    public static CaseContextDTO getCaseContext(Id caseId) {
        CaseContextDTO context = new CaseContextDTO();
        
        // Query Case record
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, Origin,
                   SuppliedEmail, ContactId, AccountId, OwnerId,
                   CreatedDate, LastModifiedDate
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case not found');
        }
        
        context.caseRecord = cases[0];
        
        // Query recent EmailMessages (latest 3)
        List<EmailMessage> emails = [
            SELECT Id, Subject, TextBody, HtmlBody, FromAddress, ToAddress,
                   MessageDate, Incoming
            FROM EmailMessage
            WHERE ParentId = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY MessageDate DESC
            LIMIT 3
        ];
        
        for (EmailMessage email : emails) {
            context.recentEmails.add(new CaseContextDTO.EmailMessageDTO(email));
        }
        
        // Query recent CaseComments (latest 3)
        List<CaseComment> comments = [
            SELECT Id, CommentBody, CreatedDate, IsPublished
            FROM CaseComment
            WHERE ParentId = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 3
        ];
        
        for (CaseComment comment : comments) {
            context.recentComments.add(new CaseContextDTO.CaseCommentDTO(comment));
        }
        
        return context;
    }
    
    /**
     * Get triage result with priority score, band, and routing
     * @param caseId The Case record ID
     * @return TriageResultDTO with scoring and routing information
     */
    @AuraEnabled(cacheable=true)
    public static TriageResultDTO getTriageResult(Id caseId) {
        return CaseTriageEngine.computeTriage(caseId);
    }
    
    /**
     * Generate AI draft reply using OpenAI
     * @param caseId The Case record ID
     * @return AIDraftDTO with generated draft or error
     */
    @AuraEnabled
    public static AIDraftDTO generateAIDraft(Id caseId) {
        try {
            // Get context and triage
            CaseContextDTO context = getCaseContext(caseId);
            TriageResultDTO triage = CaseTriageEngine.computeTriage(caseId);
            
            // Generate draft via OpenAI
            return OpenAIService.generateDraft(context, triage);
            
        } catch (Exception e) {
            return AIDraftDTO.error('Failed to generate draft: ' + e.getMessage());
        }
    }
    
    /**
     * Take action on a case (Create Task, Escalate, Update Status)
     * @param caseId The Case record ID
     * @param actionType The action type: CREATE_TASK, ESCALATE, UPDATE_STATUS
     * @return ActionResultDTO with result of the action
     */
    @AuraEnabled
    public static ActionResultDTO takeAction(Id caseId, String actionType) {
        // Validate CRUD permissions
        if (!Schema.sObjectType.Case.isUpdateable()) {
            return ActionResultDTO.error('You do not have permission to update Cases.');
        }
        
        try {
            switch on actionType {
                when 'CREATE_TASK' {
                    return createFollowUpTask(caseId);
                }
                when 'ESCALATE' {
                    return escalateCase(caseId);
                }
                when 'UPDATE_STATUS' {
                    return updateCaseStatus(caseId);
                }
                when else {
                    return ActionResultDTO.error('Unknown action type: ' + actionType);
                }
            }
        } catch (Exception e) {
            return ActionResultDTO.error('Action failed: ' + e.getMessage());
        }
    }
    
    /**
     * Create a follow-up task for the case
     */
    private static ActionResultDTO createFollowUpTask(Id caseId) {
        // Check Task CRUD
        if (!Schema.sObjectType.Task.isCreateable()) {
            return ActionResultDTO.error('You do not have permission to create Tasks.');
        }
        
        // Get case owner for task assignment
        Case caseRecord = [
            SELECT Id, OwnerId, Subject, CaseNumber
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        Task newTask = new Task(
            WhatId = caseId,
            OwnerId = caseRecord.OwnerId,
            Subject = 'Follow-up: ' + (String.isNotBlank(caseRecord.Subject) ? caseRecord.Subject : 'Case ' + caseRecord.CaseNumber),
            Description = 'Follow-up task created by Case Triage Copilot.\n\nPlease review and respond to the customer.',
            ActivityDate = Date.today().addDays(1),
            Priority = 'High',
            Status = 'Not Started'
        );
        
        // Check FLS for fields
        checkFieldCreateAccess('Task', new List<String>{'WhatId', 'OwnerId', 'Subject', 'Description', 'ActivityDate', 'Priority', 'Status'});
        
        insert newTask;
        
        return ActionResultDTO.success('Follow-up task created successfully.', newTask.Id);
    }
    
    /**
     * Escalate the case - update priority and optionally reassign to queue
     */
    private static ActionResultDTO escalateCase(Id caseId) {
        Case caseRecord = [
            SELECT Id, Priority, Status, OwnerId
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        // Update priority to High/Urgent
        caseRecord.Priority = 'High';
        
        // Set status to Escalated if available, otherwise Working
        caseRecord.Status = 'Escalated';
        
        // Try to find Escalations queue
        List<Group> escalationsQueue = [
            SELECT Id 
            FROM Group 
            WHERE Type = 'Queue' 
            AND Name = 'Escalations'
            LIMIT 1
        ];
        
        String message = 'Case escalated to High priority.';
        
        if (!escalationsQueue.isEmpty()) {
            caseRecord.OwnerId = escalationsQueue[0].Id;
            message += ' Assigned to Escalations queue.';
        }
        
        // Check FLS for fields
        checkFieldUpdateAccess('Case', new List<String>{'Priority', 'Status', 'OwnerId'});
        
        update caseRecord;
        
        return ActionResultDTO.success(message);
    }
    
    /**
     * Update case status to In Progress or Waiting on Customer
     */
    private static ActionResultDTO updateCaseStatus(Id caseId) {
        Case caseRecord = [
            SELECT Id, Status
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        // Toggle between In Progress and Waiting on Customer
        String newStatus;
        if (caseRecord.Status == 'In Progress' || caseRecord.Status == 'Working') {
            newStatus = 'Waiting on Customer';
        } else {
            newStatus = 'In Progress';
        }
        
        caseRecord.Status = newStatus;
        
        // Check FLS
        checkFieldUpdateAccess('Case', new List<String>{'Status'});
        
        update caseRecord;
        
        return ActionResultDTO.success('Status updated to: ' + newStatus);
    }
    
    /**
     * Save triage log record
     * @param caseId The Case record ID
     * @param triageJson JSON string of TriageResultDTO
     * @param draftReply The AI-generated draft reply
     * @param aiUsed Whether AI was used
     * @param actionJson JSON string of actions taken
     * @param snapshotJson JSON string of data snapshot
     * @param errorMsg Any error message to log
     * @return Id of the created Case_Triage__c record
     */
    @AuraEnabled
    public static Id saveTriageLog(
        Id caseId,
        String triageJson,
        String draftReply,
        Boolean aiUsed,
        String actionJson,
        String snapshotJson,
        String errorMsg
    ) {
        // Check CRUD permission
        if (!Schema.sObjectType.Case_Triage__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create Case Triage records.');
        }
        
        // Parse triage result
        TriageResultDTO triage = new TriageResultDTO();
        if (String.isNotBlank(triageJson)) {
            triage = TriageResultDTO.fromJson(triageJson);
        }
        
        // Get config for AI model
        String aiModel = '';
        if (aiUsed) {
            OpenAI_Config__mdt config = [
                SELECT Model__c 
                FROM OpenAI_Config__mdt 
                WHERE DeveloperName = 'Default' 
                LIMIT 1
            ];
            if (config != null) {
                aiModel = config.Model__c;
            }
        }
        
        // Build recommendation reason string
        String reasonsText = '';
        if (triage.reasons != null && !triage.reasons.isEmpty()) {
            reasonsText = String.join(triage.reasons, '\n');
        }
        
        Case_Triage__c triageLog = new Case_Triage__c(
            Case__c = caseId,
            Triage_Timestamp__c = Datetime.now(),
            Priority_Score__c = triage.priorityScore,
            Priority_Band__c = triage.priorityBand,
            Recommended_Routing__c = triage.recommendedRouting,
            Recommendation_Reason__c = reasonsText,
            AI_Draft_Reply__c = draftReply,
            AI_Model__c = aiModel,
            AI_Used__c = aiUsed != null ? aiUsed : false,
            Actions_Taken__c = actionJson,
            Data_Snapshot__c = snapshotJson,
            Error__c = errorMsg
        );
        
        // Check FLS for all fields
        checkFieldCreateAccess('Case_Triage__c', new List<String>{
            'Case__c', 'Triage_Timestamp__c', 'Priority_Score__c', 'Priority_Band__c',
            'Recommended_Routing__c', 'Recommendation_Reason__c', 'AI_Draft_Reply__c',
            'AI_Model__c', 'AI_Used__c', 'Actions_Taken__c', 'Data_Snapshot__c', 'Error__c'
        });
        
        insert triageLog;
        
        return triageLog.Id;
    }
    
    /**
     * Get recent triage logs for a case
     * @param caseId The Case record ID
     * @return List of recent Case_Triage__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Case_Triage__c> getRecentTriageLogs(Id caseId) {
        return [
            SELECT Id, Name, Triage_Timestamp__c, Priority_Score__c, Priority_Band__c,
                   Recommended_Routing__c, AI_Used__c, Actions_Taken__c
            FROM Case_Triage__c
            WHERE Case__c = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY Triage_Timestamp__c DESC
            LIMIT 5
        ];
    }
    
    /**
     * Check field-level create access
     */
    private static void checkFieldCreateAccess(String objectName, List<String> fieldNames) {
        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
        if (sObjType == null) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }
        
        Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (!fieldDescribe.isCreateable()) {
                    throw new AuraHandledException('You do not have permission to set field: ' + fieldName);
                }
            }
        }
    }
    
    /**
     * Check field-level update access
     */
    private static void checkFieldUpdateAccess(String objectName, List<String> fieldNames) {
        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
        if (sObjType == null) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }
        
        Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (!fieldDescribe.isUpdateable()) {
                    throw new AuraHandledException('You do not have permission to update field: ' + fieldName);
                }
            }
        }
    }
}
