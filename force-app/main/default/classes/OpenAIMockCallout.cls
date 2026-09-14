/**
 * Mock HTTP Callout class for OpenAI API testing
 * Supports various response scenarios: success, errors, rate limits
 */
@isTest
public class OpenAIMockCallout implements HttpCalloutMock {
    
    private Integer statusCode;
    private String responseBody;
    private Boolean simulateTimeout;
    
    /**
     * Constructor for standard mock
     */
    public OpenAIMockCallout(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.simulateTimeout = false;
    }
    
    /**
     * Constructor for timeout simulation
     */
    public OpenAIMockCallout(Boolean simulateTimeout) {
        this.simulateTimeout = simulateTimeout;
        this.statusCode = 0;
        this.responseBody = '';
    }
    
    /**
     * Implement the respond method
     */
    public HttpResponse respond(HttpRequest req) {
        if (simulateTimeout) {
            throw new CalloutException('Read timed out');
        }
        
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        res.setHeader('Content-Type', 'application/json');
        return res;
    }
    
    /**
     * Get a successful OpenAI response body
     */
    public static String getSuccessResponseBody() {
        return '{"id":"chatcmpl-123","object":"chat.completion","created":1677652288,"model":"gpt-4o",' +
               '"choices":[{"index":0,"message":{"role":"assistant","content":"Thank you for reaching out regarding your inquiry.\\n\\n' +
               'I understand your concern and want to help resolve this as quickly as possible.\\n\\n' +
               'Next steps:\\n1. Please provide your account number\\n2. Share any relevant screenshots\\n3. Confirm the date this issue started\\n\\n' +
               'Best regards,\\nSupport Team"},"finish_reason":"stop"}],' +
               '"usage":{"prompt_tokens":100,"completion_tokens":75,"total_tokens":175}}';
    }
    
    /**
     * Get a 401 unauthorized response body
     */
    public static String getUnauthorizedResponseBody() {
        return '{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}';
    }
    
    /**
     * Get a 429 rate limit response body
     */
    public static String getRateLimitResponseBody() {
        return '{"error":{"message":"Rate limit exceeded. Please retry after 60 seconds.","type":"rate_limit_error","code":"rate_limit_exceeded"}}';
    }
    
    /**
     * Get a 500 server error response body
     */
    public static String getServerErrorResponseBody() {
        return '{"error":{"message":"Internal server error","type":"server_error","code":"server_error"}}';
    }
    
    /**
     * Get malformed JSON response
     */
    public static String getMalformedResponseBody() {
        return '{"invalid json structure';
    }
    
    /**
     * Get empty choices response
     */
    public static String getEmptyChoicesResponseBody() {
        return '{"id":"chatcmpl-123","object":"chat.completion","choices":[],"usage":{"total_tokens":0}}';
    }
}
