/**
 * Rule-based Case Triage Engine
 * Computes priority score (0-100) and recommends routing based on:
 * - Case priority and status
 * - Keywords in subject, description, and emails
 * - Case origin
 * - Angry language detection
 * 
 * Scoring is deterministic and testable without AI dependency.
 */
public with sharing class CaseTriageEngine {
    
    // Priority scoring constants
    private static final Map<String, Integer> PRIORITY_SCORES = new Map<String, Integer>{
        'Urgent' => 40,
        'High' => 25,
        'Medium' => 10,
        'Normal' => 10,
        'Low' => 0
    };
    
    // Critical keywords - highest priority
    private static final Map<String, Integer> CRITICAL_KEYWORDS = new Map<String, Integer>{
        'breach' => 30,
        'security' => 25,
        'phishing' => 30,
        'fraud' => 30,
        'down' => 20,
        'outage' => 25,
        'urgent' => 15,
        'asap' => 10,
        'immediately' => 15,
        'critical' => 20,
        'emergency' => 25
    };
    
    // High priority keywords
    private static final Map<String, Integer> HIGH_KEYWORDS = new Map<String, Integer>{
        'bug' => 15,
        'error' => 12,
        'broken' => 15,
        'not working' => 12,
        'crash' => 18,
        'api' => 8,
        'failed' => 12,
        'failure' => 12,
        'exception' => 10,
        '500' => 10,
        '404' => 8
    };
    
    // Billing-related keywords
    private static final Map<String, Integer> BILLING_KEYWORDS = new Map<String, Integer>{
        'refund' => 10,
        'invoice' => 8,
        'charge' => 8,
        'payment' => 8,
        'billing' => 10,
        'subscription' => 5,
        'cancel' => 8,
        'overcharge' => 12,
        'credit' => 6,
        'receipt' => 5
    };
    
    // Engineering/Technical keywords
    private static final Map<String, Integer> ENGINEERING_KEYWORDS = new Map<String, Integer>{
        'api' => 10,
        'integration' => 8,
        'webhook' => 10,
        'endpoint' => 8,
        'sdk' => 8,
        'code' => 6,
        'developer' => 6,
        'technical' => 5,
        'documentation' => 4,
        'bug' => 12
    };
    
    // Security-related keywords
    private static final Map<String, Integer> SECURITY_KEYWORDS = new Map<String, Integer>{
        'breach' => 20,
        'security' => 15,
        'phishing' => 20,
        'fraud' => 20,
        'hack' => 20,
        'unauthorized' => 15,
        'suspicious' => 12,
        'compromised' => 18,
        'malware' => 20,
        'virus' => 15
    };
    
    // Angry language indicators
    private static final Set<String> ANGRY_INDICATORS = new Set<String>{
        'unacceptable',
        'ridiculous',
        'terrible',
        'worst',
        'lawsuit',
        'attorney',
        'lawyer',
        'complaint',
        'angry',
        'furious',
        'frustrated',
        'disappointed',
        'horrible',
        'useless',
        'incompetent',
        'demand',
        'refund now',
        'cancel immediately'
    };
    
    // Origin scoring
    private static final Map<String, Integer> ORIGIN_SCORES = new Map<String, Integer>{
        'Phone' => 5,
        'Email' => 3,
        'Web' => 0,
        'Chat' => 2
    };
    
    /**
     * Main method to compute triage for a Case
     * @param caseId The ID of the Case to triage
     * @return TriageResultDTO containing score, band, routing, and reasons
     */
    public static TriageResultDTO computeTriage(Id caseId) {
        // Query the case with related data
        Case caseRecord = queryCase(caseId);
        List<EmailMessage> emails = queryEmails(caseId);
        
        return computeTriageFromData(caseRecord, emails);
    }
    
    /**
     * Compute triage from pre-fetched data (useful for testing)
     */
    public static TriageResultDTO computeTriageFromData(Case caseRecord, List<EmailMessage> emails) {
        TriageResultDTO result = new TriageResultDTO();
        
        if (caseRecord == null) {
            result.addReason('Case not found');
            return result;
        }
        
        // Build combined text for analysis
        String combinedText = buildCombinedText(caseRecord, emails);
        String lowerText = combinedText.toLowerCase();
        
        // 1. Base score from Case Priority
        Integer baseScore = calculatePriorityScore(caseRecord.Priority, result);
        result.priorityScore = baseScore;
        
        // 2. Add keyword scores
        Integer keywordScore = calculateKeywordScore(lowerText, result);
        result.priorityScore += keywordScore;
        
        // 3. Add origin score
        Integer originScore = calculateOriginScore(caseRecord.Origin, result);
        result.priorityScore += originScore;
        
        // 4. Add angry language score
        Integer angryScore = calculateAngryLanguageScore(lowerText, result);
        result.priorityScore += angryScore;
        
        // 5. Status-based adjustments
        Integer statusScore = calculateStatusScore(caseRecord.Status, result);
        result.priorityScore += statusScore;
        
        // Cap score at 100
        if (result.priorityScore > 100) {
            result.priorityScore = 100;
        }
        
        // Calculate band from score
        result.calculateBand();
        
        // Determine routing
        result.recommendedRouting = determineRouting(lowerText, result);
        
        // Add suggested actions
        addSuggestedActions(result);
        
        return result;
    }
    
    /**
     * Query Case record with necessary fields
     */
    private static Case queryCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, Subject, Description, Priority, Status, Origin,
                   SuppliedEmail, ContactId, AccountId, OwnerId,
                   CreatedDate, LastModifiedDate, CaseNumber
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return cases.isEmpty() ? null : cases[0];
    }
    
    /**
     * Query EmailMessages for the Case
     */
    private static List<EmailMessage> queryEmails(Id caseId) {
        return [
            SELECT Id, Subject, TextBody, HtmlBody, FromAddress, ToAddress,
                   MessageDate, Incoming
            FROM EmailMessage
            WHERE ParentId = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY MessageDate DESC
            LIMIT 3
        ];
    }
    
    /**
     * Build combined text from case and emails for analysis
     */
    private static String buildCombinedText(Case caseRecord, List<EmailMessage> emails) {
        String text = '';
        
        if (String.isNotBlank(caseRecord.Subject)) {
            text += caseRecord.Subject + ' ';
        }
        
        if (String.isNotBlank(caseRecord.Description)) {
            text += caseRecord.Description + ' ';
        }
        
        for (EmailMessage email : emails) {
            if (String.isNotBlank(email.Subject)) {
                text += email.Subject + ' ';
            }
            if (String.isNotBlank(email.TextBody)) {
                text += email.TextBody + ' ';
            } else if (String.isNotBlank(email.HtmlBody)) {
                // Strip HTML for analysis
                text += email.HtmlBody.replaceAll('<[^>]+>', ' ') + ' ';
            }
        }
        
        return text;
    }
    
    /**
     * Calculate score from Case Priority
     */
    private static Integer calculatePriorityScore(String priority, TriageResultDTO result) {
        Integer score = 0;
        
        if (String.isNotBlank(priority) && PRIORITY_SCORES.containsKey(priority)) {
            score = PRIORITY_SCORES.get(priority);
            result.addReason('Case Priority: ' + priority + ' (+' + score + ')');
        }
        
        return score;
    }
    
    /**
     * Calculate score from keywords found in text
     */
    private static Integer calculateKeywordScore(String lowerText, TriageResultDTO result) {
        Integer totalScore = 0;
        Set<String> foundKeywords = new Set<String>();
        
        // Check critical keywords
        for (String keyword : CRITICAL_KEYWORDS.keySet()) {
            if (lowerText.contains(keyword) && !foundKeywords.contains(keyword)) {
                Integer score = CRITICAL_KEYWORDS.get(keyword);
                totalScore += score;
                foundKeywords.add(keyword);
                result.addReason('Critical keyword "' + keyword + '" detected (+' + score + ')');
            }
        }
        
        // Check high keywords
        for (String keyword : HIGH_KEYWORDS.keySet()) {
            if (lowerText.contains(keyword) && !foundKeywords.contains(keyword)) {
                Integer score = HIGH_KEYWORDS.get(keyword);
                totalScore += score;
                foundKeywords.add(keyword);
                result.addReason('High-priority keyword "' + keyword + '" detected (+' + score + ')');
            }
        }
        
        // Cap keyword score contribution
        if (totalScore > 50) {
            totalScore = 50;
        }
        
        return totalScore;
    }
    
    /**
     * Calculate score from Case Origin
     */
    private static Integer calculateOriginScore(String origin, TriageResultDTO result) {
        Integer score = 0;
        
        if (String.isNotBlank(origin) && ORIGIN_SCORES.containsKey(origin)) {
            score = ORIGIN_SCORES.get(origin);
            if (score > 0) {
                result.addReason('Origin: ' + origin + ' (+' + score + ')');
            }
        }
        
        return score;
    }
    
    /**
     * Calculate score from angry language indicators
     */
    private static Integer calculateAngryLanguageScore(String lowerText, TriageResultDTO result) {
        Integer angryCount = 0;
        
        for (String indicator : ANGRY_INDICATORS) {
            if (lowerText.contains(indicator)) {
                angryCount++;
            }
        }
        
        Integer score = 0;
        if (angryCount >= 3) {
            score = 15;
            result.addReason('Multiple frustrated language indicators detected (+15)');
        } else if (angryCount >= 1) {
            score = 8;
            result.addReason('Frustrated language detected (+8)');
        }
        
        return score;
    }
    
    /**
     * Calculate score based on Case Status
     */
    private static Integer calculateStatusScore(String status, TriageResultDTO result) {
        Integer score = 0;
        
        if (String.isNotBlank(status)) {
            if (status.toLowerCase().contains('escalat')) {
                score = 15;
                result.addReason('Case is escalated (+15)');
            } else if (status.toLowerCase().contains('hold') || status.toLowerCase().contains('waiting')) {
                score = 5;
                result.addReason('Case is on hold/waiting (+5)');
            }
        }
        
        return score;
    }
    
    /**
     * Determine routing based on keywords and score
     */
    private static String determineRouting(String lowerText, TriageResultDTO result) {
        // Count category keywords
        Integer securityCount = countKeywords(lowerText, SECURITY_KEYWORDS.keySet());
        Integer billingCount = countKeywords(lowerText, BILLING_KEYWORDS.keySet());
        Integer engineeringCount = countKeywords(lowerText, ENGINEERING_KEYWORDS.keySet());
        
        // Priority routing based on keyword dominance and criticality
        
        // Security takes highest priority
        if (securityCount >= 2) {
            result.addReason('Routing: Security concerns identified');
            return 'Security';
        }
        
        // High score or escalated goes to L2
        if (result.priorityScore >= 80) {
            result.addReason('Routing: Critical priority requires L2 Support');
            return 'L2 Support';
        }
        
        // Billing if billing keywords dominate
        if (billingCount >= 2 && billingCount > engineeringCount) {
            result.addReason('Routing: Billing-related inquiry');
            return 'Billing';
        }
        
        // Engineering if technical keywords dominate
        if (engineeringCount >= 2 && engineeringCount > billingCount) {
            result.addReason('Routing: Technical/Engineering issue');
            return 'Engineering';
        }
        
        // Medium-high scores go to L2
        if (result.priorityScore >= 60) {
            result.addReason('Routing: High priority requires L2 Support');
            return 'L2 Support';
        }
        
        // Default to L1 Support
        result.addReason('Routing: Standard support inquiry');
        return 'L1 Support';
    }
    
    /**
     * Count how many keywords from a set are found in text
     */
    private static Integer countKeywords(String text, Set<String> keywords) {
        Integer count = 0;
        for (String keyword : keywords) {
            if (text.contains(keyword)) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * Add suggested actions based on triage result
     */
    private static void addSuggestedActions(TriageResultDTO result) {
        if (result.priorityScore >= 80) {
            result.addSuggestedAction('Escalate immediately to senior support');
            result.addSuggestedAction('Notify team lead of critical case');
        }
        
        if (result.priorityBand == 'High' || result.priorityBand == 'Critical') {
            result.addSuggestedAction('Create follow-up task within 4 hours');
        } else {
            result.addSuggestedAction('Create follow-up task within 24 hours');
        }
        
        if (result.recommendedRouting == 'Security') {
            result.addSuggestedAction('Review for security incident protocol');
        }
        
        if (result.recommendedRouting == 'Billing') {
            result.addSuggestedAction('Check customer account billing history');
        }
        
        if (result.recommendedRouting == 'Engineering') {
            result.addSuggestedAction('Collect technical details and logs');
        }
        
        result.addSuggestedAction('Update case status to In Progress');
    }
}
