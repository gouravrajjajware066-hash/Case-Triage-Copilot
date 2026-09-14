/**
 * Data Transfer Object for triage scoring and routing results
 * Contains the computed priority score, band, routing recommendation, and reasons
 */
public class TriageResultDTO {
    @AuraEnabled public Integer priorityScore;
    @AuraEnabled public String priorityBand;
    @AuraEnabled public String recommendedRouting;
    @AuraEnabled public List<String> reasons;
    @AuraEnabled public List<String> suggestedActions;
    
    public TriageResultDTO() {
        this.priorityScore = 0;
        this.priorityBand = 'Low';
        this.recommendedRouting = 'L1 Support';
        this.reasons = new List<String>();
        this.suggestedActions = new List<String>();
    }
    
    /**
     * Set priority band based on score
     * 0-29: Low, 30-59: Medium, 60-79: High, 80-100: Critical
     */
    public void calculateBand() {
        if (this.priorityScore >= 80) {
            this.priorityBand = 'Critical';
        } else if (this.priorityScore >= 60) {
            this.priorityBand = 'High';
        } else if (this.priorityScore >= 30) {
            this.priorityBand = 'Medium';
        } else {
            this.priorityBand = 'Low';
        }
    }
    
    /**
     * Add a reason to the reasons list
     */
    public void addReason(String reason) {
        if (String.isNotBlank(reason)) {
            this.reasons.add(reason);
        }
    }
    
    /**
     * Add a suggested action
     */
    public void addSuggestedAction(String action) {
        if (String.isNotBlank(action)) {
            this.suggestedActions.add(action);
        }
    }
    
    /**
     * Serialize to JSON for storage
     */
    public String toJson() {
        return JSON.serialize(this);
    }
    
    /**
     * Deserialize from JSON
     */
    public static TriageResultDTO fromJson(String jsonString) {
        if (String.isBlank(jsonString)) {
            return new TriageResultDTO();
        }
        return (TriageResultDTO) JSON.deserialize(jsonString, TriageResultDTO.class);
    }
}
