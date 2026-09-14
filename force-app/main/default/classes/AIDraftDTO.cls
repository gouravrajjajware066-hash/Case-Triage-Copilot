/**
 * Data Transfer Object for AI-generated draft reply
 * Contains the draft text, model information, and any errors
 */
public class AIDraftDTO {
    @AuraEnabled public String draftText;
    @AuraEnabled public String model;
    @AuraEnabled public Integer tokensUsed;
    @AuraEnabled public String error;
    @AuraEnabled public Boolean success;
    
    public AIDraftDTO() {
        this.draftText = '';
        this.model = '';
        this.tokensUsed = 0;
        this.error = '';
        this.success = false;
    }
    
    /**
     * Create a successful response
     */
    public static AIDraftDTO success(String draftText, String model, Integer tokensUsed) {
        AIDraftDTO dto = new AIDraftDTO();
        dto.draftText = draftText;
        dto.model = model;
        dto.tokensUsed = tokensUsed;
        dto.success = true;
        return dto;
    }
    
    /**
     * Create an error response
     */
    public static AIDraftDTO error(String errorMessage) {
        AIDraftDTO dto = new AIDraftDTO();
        dto.error = errorMessage;
        dto.success = false;
        return dto;
    }
    
    /**
     * Create an error response with partial data
     */
    public static AIDraftDTO error(String errorMessage, String model) {
        AIDraftDTO dto = new AIDraftDTO();
        dto.error = errorMessage;
        dto.model = model;
        dto.success = false;
        return dto;
    }
}
