/**
 * Service class for OpenAI API integration
 * Handles server-side callouts for AI draft generation
 * 
 * SECURITY: API key is stored in Custom Metadata and never exposed to client
 */
public with sharing class OpenAIService {
    
    private static final String OPENAI_ENDPOINT = 'https://api.openai.com';
    private static final Integer DEFAULT_TIMEOUT = 60000; // 60 seconds
    private static final Integer MAX_RETRIES = 1;
    
    // Test-visible config override for unit tests
    @TestVisible
    private static OpenAI_Config__mdt testConfig;
    
    /**
     * Generate AI draft reply for a case
     * @param context The case context DTO
     * @param triage The triage result DTO
     * @return AIDraftDTO containing the draft text or error
     */
    public static AIDraftDTO generateDraft(CaseContextDTO context, TriageResultDTO triage) {
        // Get configuration from Custom Metadata
        OpenAI_Config__mdt config = getConfig();
        
        if (config == null) {
            return AIDraftDTO.error('OpenAI configuration not found. Please configure OpenAI_Config__mdt.');
        }
        
        if (String.isBlank(config.API_Key__c)) {
            return AIDraftDTO.error('OpenAI API key not configured. Please set the API_Key__c field in OpenAI_Config__mdt.');
        }
        
        try {
            // Build the prompt
            String prompt = buildPrompt(context, triage);
            
            // Make the API call with retry logic
            return callOpenAI(prompt, config, 0);
            
        } catch (Exception e) {
            return AIDraftDTO.error('Unexpected error: ' + e.getMessage(), config.Model__c);
        }
    }
    
    /**
     * Get OpenAI configuration from Custom Metadata
     */
    @TestVisible
    private static OpenAI_Config__mdt getConfig() {
        // Allow test override
        if (Test.isRunningTest() && testConfig != null) {
            return testConfig;
        }
        
        List<OpenAI_Config__mdt> configs = [
            SELECT Model__c, MaxTokens__c, Endpoint__c, API_Key__c
            FROM OpenAI_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        
        return configs.isEmpty() ? null : configs[0];
    }
    
    /**
     * Build the prompt for OpenAI
     */
    @TestVisible
    private static String buildPrompt(CaseContextDTO context, TriageResultDTO triage) {
        String prompt = 'You are a professional customer support agent. Generate a draft reply for this support case.\n\n';
        
        // Case context
        prompt += 'CASE CONTEXT:\n';
        if (context != null && context.caseRecord != null) {
            prompt += '- Subject: ' + safeString(context.caseRecord.Subject) + '\n';
            prompt += '- Description: ' + truncateText(safeString(context.caseRecord.Description), 500) + '\n';
            prompt += '- Priority: ' + safeString(context.caseRecord.Priority) + '\n';
            prompt += '- Status: ' + safeString(context.caseRecord.Status) + '\n';
        }
        
        // Triage info
        if (triage != null) {
            prompt += '- Triage Score: ' + triage.priorityScore + '/100 (' + triage.priorityBand + ')\n';
            prompt += '- Recommended Routing: ' + triage.recommendedRouting + '\n';
        }
        
        prompt += '\n';
        
        // Latest customer message (inbound email)
        prompt += 'CUSTOMER\'S LAST MESSAGE:\n';
        String lastInboundEmail = getLastInboundEmail(context);
        if (String.isNotBlank(lastInboundEmail)) {
            prompt += truncateText(lastInboundEmail, 800) + '\n';
        } else {
            prompt += '(No recent email from customer)\n';
        }
        
        prompt += '\n';
        
        // Guidelines
        prompt += 'GUIDELINES:\n';
        prompt += '- Professional, concise, friendly tone\n';
        prompt += '- No promises of refunds or compensation\n';
        prompt += '- Ask 1-2 clarifying questions if needed\n';
        prompt += '- Provide numbered next steps\n';
        prompt += '- Keep under 150-200 words\n';
        prompt += '- Do not reference internal policies\n';
        prompt += '\nRespond with ONLY the email reply text, no additional commentary.';
        
        return prompt;
    }
    
    /**
     * Get the last inbound email from context
     */
    private static String getLastInboundEmail(CaseContextDTO context) {
        if (context == null || context.recentEmails == null || context.recentEmails.isEmpty()) {
            return null;
        }
        
        for (CaseContextDTO.EmailMessageDTO email : context.recentEmails) {
            if (email.incoming == true) {
                return email.textBody;
            }
        }
        
        // If no inbound email, return the most recent email body
        return context.recentEmails[0].textBody;
    }
    
    /**
     * Make the OpenAI API call with retry logic
     */
    private static AIDraftDTO callOpenAI(String prompt, OpenAI_Config__mdt config, Integer retryCount) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(OPENAI_ENDPOINT + config.Endpoint__c);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + config.API_Key__c);
        req.setTimeout(DEFAULT_TIMEOUT);
        
        // Build request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => config.Model__c,
            'messages' => new List<Map<String, String>>{
                new Map<String, String>{
                    'role' => 'user',
                    'content' => prompt
                }
            },
            'max_completion_tokens' => Integer.valueOf(config.MaxTokens__c)
        };
        
        req.setBody(JSON.serialize(requestBody));
        
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            return handleResponse(res, config, prompt, retryCount);
            
        } catch (System.CalloutException e) {
            if (e.getMessage().contains('Read timed out') && retryCount < MAX_RETRIES) {
                return callOpenAI(prompt, config, retryCount + 1);
            }
            return AIDraftDTO.error('Connection error: ' + e.getMessage(), config.Model__c);
        }
    }
    
    /**
     * Handle the API response
     */
    private static AIDraftDTO handleResponse(HttpResponse res, OpenAI_Config__mdt config, String prompt, Integer retryCount) {
        Integer statusCode = res.getStatusCode();
        
        // Success
        if (statusCode == 200) {
            return parseSuccessResponse(res.getBody(), config.Model__c);
        }
        
        // Rate limited - retry once
        if (statusCode == 429 && retryCount < MAX_RETRIES) {
            // Wait briefly before retry (note: actual wait would need @future or queueable)
            return callOpenAI(prompt, config, retryCount + 1);
        }
        
        // Handle various error codes
        String errorMessage;
        switch on statusCode {
            when 401 {
                errorMessage = 'Authentication failed. Please check your OpenAI API key in Custom Metadata.';
            }
            when 429 {
                errorMessage = 'Rate limit exceeded. Please try again later.';
            }
            when 500, 502, 503 {
                if (retryCount < MAX_RETRIES) {
                    return callOpenAI(prompt, config, retryCount + 1);
                }
                errorMessage = 'OpenAI service temporarily unavailable. Please try again.';
            }
            when else {
                errorMessage = 'API error (HTTP ' + statusCode + '): ' + parseErrorMessage(res.getBody());
            }
        }
        
        return AIDraftDTO.error(errorMessage, config.Model__c);
    }
    
    /**
     * Parse successful response from OpenAI
     */
    private static AIDraftDTO parseSuccessResponse(String responseBody, String model) {
        try {
            // Log raw response for debugging (first 500 chars)
            String debugResponse = responseBody.length() > 500 ? responseBody.substring(0, 500) + '...' : responseBody;
            System.debug('OpenAI Raw Response: ' + debugResponse);
            
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            List<Object> choices = (List<Object>) response.get('choices');
            if (choices == null || choices.isEmpty()) {
                return AIDraftDTO.error('No choices in response. Raw: ' + debugResponse, model);
            }
            
            Map<String, Object> firstChoice = (Map<String, Object>) choices[0];
            System.debug('First choice: ' + JSON.serialize(firstChoice));
            
            Map<String, Object> message = (Map<String, Object>) firstChoice.get('message');
            
            if (message == null) {
                return AIDraftDTO.error('No message in response. Choice: ' + JSON.serialize(firstChoice), model);
            }
            
            System.debug('Message object: ' + JSON.serialize(message));
            
            // Check for refusal
            if (message.containsKey('refusal') && message.get('refusal') != null) {
                String refusal = String.valueOf(message.get('refusal'));
                if (String.isNotBlank(refusal)) {
                    return AIDraftDTO.error('Request refused: ' + refusal, model);
                }
            }
            
            // Get content - could be string or array or null
            Object contentObj = message.get('content');
            System.debug('Content object type: ' + (contentObj != null ? String.valueOf(contentObj).substring(0, Math.min(100, String.valueOf(contentObj).length())) : 'NULL'));
            
            String content = '';
            
            if (contentObj == null) {
                // Check if there's output in a different field (some newer models use 'output')
                if (response.containsKey('output')) {
                    Object outputObj = response.get('output');
                    if (outputObj instanceof String) {
                        content = (String) outputObj;
                    } else if (outputObj instanceof List<Object>) {
                        List<Object> outputs = (List<Object>) outputObj;
                        for (Object o : outputs) {
                            if (o instanceof Map<String, Object>) {
                                Map<String, Object> oMap = (Map<String, Object>) o;
                                if (oMap.containsKey('content')) {
                                    Object oContent = oMap.get('content');
                                    if (oContent instanceof List<Object>) {
                                        for (Object c : (List<Object>) oContent) {
                                            if (c instanceof Map<String, Object>) {
                                                Map<String, Object> cMap = (Map<String, Object>) c;
                                                if (cMap.get('type') == 'output_text' || cMap.get('type') == 'text') {
                                                    content += String.valueOf(cMap.get('text'));
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (String.isBlank(content)) {
                    return AIDraftDTO.error('No content in response. Message keys: ' + message.keySet(), model);
                }
            } else if (contentObj instanceof String) {
                content = (String) contentObj;
            } else if (contentObj instanceof List<Object>) {
                // Handle array content (GPT-5 and multimodal responses)
                List<Object> contentParts = (List<Object>) contentObj;
                System.debug('Content parts count: ' + contentParts.size());
                for (Object part : contentParts) {
                    System.debug('Content part: ' + JSON.serialize(part));
                    if (part instanceof Map<String, Object>) {
                        Map<String, Object> partMap = (Map<String, Object>) part;
                        String partType = partMap.containsKey('type') ? String.valueOf(partMap.get('type')) : '';
                        System.debug('Part type: ' + partType);
                        // Handle various content types from different model versions
                        if (partType == 'text' || partType == 'output_text' || partType == 'text_delta') {
                            if (partMap.containsKey('text')) {
                                content += String.valueOf(partMap.get('text'));
                            } else if (partMap.containsKey('value')) {
                                content += String.valueOf(partMap.get('value'));
                            }
                        } else if (String.isBlank(partType) && partMap.containsKey('text')) {
                            // Fallback: if no type but has text field
                            content += String.valueOf(partMap.get('text'));
                        }
                    } else if (part instanceof String) {
                        content += (String) part;
                    }
                }
            } else {
                content = String.valueOf(contentObj);
            }
            
            if (String.isBlank(content)) {
                String msgJson = JSON.serialize(message);
                String responseSnippet = responseBody.length() > 400 ? responseBody.substring(0, 400) : responseBody;
                return AIDraftDTO.error('Empty content. Keys: ' + message.keySet() + ' | Response: ' + responseSnippet, model);
            }
            
            // Get token usage
            Integer tokensUsed = 0;
            if (response.containsKey('usage')) {
                Map<String, Object> usage = (Map<String, Object>) response.get('usage');
                if (usage != null && usage.containsKey('total_tokens')) {
                    tokensUsed = (Integer) usage.get('total_tokens');
                }
            }
            
            return AIDraftDTO.success(content.trim(), model, tokensUsed);
            
        } catch (Exception e) {
            return AIDraftDTO.error('Failed to parse response: ' + e.getMessage() + ' | Response: ' + responseBody.substring(0, Math.min(300, responseBody.length())), model);
        }
    }
    
    /**
     * Parse error message from response body
     */
    private static String parseErrorMessage(String responseBody) {
        try {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (response.containsKey('error')) {
                Map<String, Object> error = (Map<String, Object>) response.get('error');
                return (String) error.get('message');
            }
            return responseBody;
        } catch (Exception e) {
            return responseBody;
        }
    }
    
    /**
     * Safe string handling for null values
     */
    private static String safeString(String value) {
        return String.isBlank(value) ? '(not provided)' : value;
    }
    
    /**
     * Truncate text to maximum length
     */
    private static String truncateText(String text, Integer maxLength) {
        if (String.isBlank(text)) {
            return '';
        }
        if (text.length() <= maxLength) {
            return text;
        }
        return text.substring(0, maxLength) + '...';
    }
}
