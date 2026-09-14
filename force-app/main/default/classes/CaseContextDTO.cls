/**
 * Data Transfer Object for Case context information
 * Contains the Case record along with related EmailMessages and CaseComments
 */
public class CaseContextDTO {
    @AuraEnabled public Case caseRecord;
    @AuraEnabled public List<EmailMessageDTO> recentEmails;
    @AuraEnabled public List<CaseCommentDTO> recentComments;
    
    public CaseContextDTO() {
        this.recentEmails = new List<EmailMessageDTO>();
        this.recentComments = new List<CaseCommentDTO>();
    }
    
    /**
     * Inner class representing an EmailMessage record
     */
    public class EmailMessageDTO {
        @AuraEnabled public Id emailId;
        @AuraEnabled public String subject;
        @AuraEnabled public String textBody;
        @AuraEnabled public String fromAddress;
        @AuraEnabled public String toAddress;
        @AuraEnabled public Datetime messageDate;
        @AuraEnabled public Boolean incoming;
        
        public EmailMessageDTO() {}
        
        public EmailMessageDTO(EmailMessage email) {
            this.emailId = email.Id;
            this.subject = email.Subject;
            this.textBody = stripHtml(email.TextBody != null ? email.TextBody : email.HtmlBody);
            this.fromAddress = email.FromAddress;
            this.toAddress = email.ToAddress;
            this.messageDate = email.MessageDate;
            this.incoming = email.Incoming;
        }
        
        /**
         * Strip HTML tags from content for safe display
         */
        private String stripHtml(String htmlContent) {
            if (String.isBlank(htmlContent)) {
                return '';
            }
            // Remove HTML tags
            String stripped = htmlContent.replaceAll('<[^>]+>', ' ');
            // Remove extra whitespace
            stripped = stripped.replaceAll('\\s+', ' ').trim();
            // Limit length for display
            if (stripped.length() > 2000) {
                stripped = stripped.substring(0, 2000) + '...';
            }
            return stripped;
        }
    }
    
    /**
     * Inner class representing a CaseComment record
     */
    public class CaseCommentDTO {
        @AuraEnabled public Id commentId;
        @AuraEnabled public String commentBody;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean isPublished;
        
        public CaseCommentDTO() {}
        
        public CaseCommentDTO(CaseComment comment) {
            this.commentId = comment.Id;
            this.commentBody = comment.CommentBody;
            this.createdDate = comment.CreatedDate;
            this.isPublished = comment.IsPublished;
        }
    }
}
