/**
 * Data Transfer Object for action results
 * Used for CREATE_TASK, ESCALATE, and UPDATE_STATUS actions
 */
public class ActionResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public Id createdRecordId;
    
    public ActionResultDTO() {
        this.success = false;
        this.message = '';
        this.createdRecordId = null;
    }
    
    /**
     * Create a successful result without a created record
     */
    public static ActionResultDTO success(String message) {
        ActionResultDTO dto = new ActionResultDTO();
        dto.success = true;
        dto.message = message;
        return dto;
    }
    
    /**
     * Create a successful result with a created record ID
     */
    public static ActionResultDTO success(String message, Id recordId) {
        ActionResultDTO dto = new ActionResultDTO();
        dto.success = true;
        dto.message = message;
        dto.createdRecordId = recordId;
        return dto;
    }
    
    /**
     * Create an error result
     */
    public static ActionResultDTO error(String message) {
        ActionResultDTO dto = new ActionResultDTO();
        dto.success = false;
        dto.message = message;
        return dto;
    }
}
