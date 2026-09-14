import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

// Apex methods
import getCaseContext from '@salesforce/apex/CaseTriageController.getCaseContext';
import getTriageResult from '@salesforce/apex/CaseTriageController.getTriageResult';
import generateAIDraft from '@salesforce/apex/CaseTriageController.generateAIDraft';
import takeAction from '@salesforce/apex/CaseTriageController.takeAction';
import saveTriageLog from '@salesforce/apex/CaseTriageController.saveTriageLog';
import getRecentTriageLogs from '@salesforce/apex/CaseTriageController.getRecentTriageLogs';

export default class CaseTriageCopilot extends LightningElement {
    @api recordId; // Case ID from record page

    // Data
    @track context;
    @track triage;
    @track draftText = '';
    @track recentLogs = [];

    // Loading states
    loadingContext = false;
    loadingTriage = false;
    isGeneratingDraft = false;
    isSavingLog = false;
    isActionInProgress = false;

    // Error handling
    errorMessage = '';

    // Actions taken during this session (for logging)
    actionsTaken = [];

    // Wired results for refresh
    wiredContextResult;
    wiredTriageResult;
    wiredLogsResult;

    // Accordion sections
    activeSections = ['emails'];

    // ===== WIRE ADAPTERS =====

    @wire(getCaseContext, { caseId: '$recordId' })
    wiredContext(result) {
        this.wiredContextResult = result;
        this.loadingContext = true;
        
        if (result.data) {
            this.context = result.data;
            this.loadingContext = false;
            this.errorMessage = '';
        } else if (result.error) {
            this.loadingContext = false;
            this.errorMessage = this.extractErrorMessage(result.error);
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    @wire(getTriageResult, { caseId: '$recordId' })
    wiredTriage(result) {
        this.wiredTriageResult = result;
        this.loadingTriage = true;
        
        if (result.data) {
            this.triage = result.data;
            this.loadingTriage = false;
        } else if (result.error) {
            this.loadingTriage = false;
            this.showToast('Error', 'Failed to compute triage: ' + this.extractErrorMessage(result.error), 'error');
        }
    }

    @wire(getRecentTriageLogs, { caseId: '$recordId' })
    wiredLogs(result) {
        this.wiredLogsResult = result;
        
        if (result.data) {
            this.recentLogs = result.data.map(log => ({
                ...log,
                formattedTimestamp: this.formatDateTime(log.Triage_Timestamp__c)
            }));
        } else if (result.error) {
            console.error('Error loading triage logs:', result.error);
        }
    }

    // ===== COMPUTED PROPERTIES =====

    get isLoading() {
        return this.loadingContext || this.loadingTriage;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get priorityScore() {
        return this.triage?.priorityScore || 0;
    }

    get priorityBand() {
        return this.triage?.priorityBand || 'Low';
    }

    get recommendedRouting() {
        return this.triage?.recommendedRouting || 'L1 Support';
    }

    get triageReasons() {
        return this.triage?.reasons || [];
    }

    get hasReasons() {
        return this.triageReasons.length > 0;
    }

    get suggestedActions() {
        return this.triage?.suggestedActions || [];
    }

    get hasSuggestedActions() {
        return this.suggestedActions.length > 0;
    }

    get recentEmails() {
        if (!this.context?.recentEmails) return [];
        return this.context.recentEmails.map(email => ({
            ...email,
            formattedDate: this.formatDateTime(email.messageDate)
        }));
    }

    get hasEmails() {
        return this.recentEmails.length > 0;
    }

    get recentComments() {
        if (!this.context?.recentComments) return [];
        return this.context.recentComments.map(comment => ({
            ...comment,
            formattedDate: this.formatDateTime(comment.createdDate)
        }));
    }

    get hasComments() {
        return this.recentComments.length > 0;
    }

    get hasRecentLogs() {
        return this.recentLogs.length > 0;
    }

    get scoreBadgeClass() {
        const score = this.priorityScore;
        let colorClass = 'score-badge';
        if (score >= 80) colorClass += ' score-critical';
        else if (score >= 60) colorClass += ' score-high';
        else if (score >= 30) colorClass += ' score-medium';
        else colorClass += ' score-low';
        return colorClass;
    }

    get bandBadgeClass() {
        const band = this.priorityBand;
        switch (band) {
            case 'Critical': return 'slds-badge_inverse badge-critical';
            case 'High': return 'slds-badge_inverse badge-high';
            case 'Medium': return 'slds-badge_inverse badge-medium';
            default: return 'slds-badge_inverse badge-low';
        }
    }

    get isCopyDisabled() {
        return !this.draftText || this.isGeneratingDraft;
    }

    get isSaveDisabled() {
        return this.isSavingLog || this.isGeneratingDraft;
    }

    get isActionDisabled() {
        return this.isActionInProgress || this.isSavingLog;
    }

    // ===== EVENT HANDLERS =====

    handleDraftChange(event) {
        this.draftText = event.target.value;
    }

    async handleGenerateDraft() {
        this.isGeneratingDraft = true;
        
        try {
            const result = await generateAIDraft({ caseId: this.recordId });
            console.log('AI Draft Result:', JSON.stringify(result));
            
            if (result && result.success) {
                if (result.draftText && result.draftText.trim()) {
                    this.draftText = result.draftText;
                    this.showToast('Success', 'AI draft generated successfully', 'success');
                } else {
                    this.showToast('Warning', 'AI returned empty response', 'warning');
                }
            } else {
                this.showToast('Warning', result?.error || 'Failed to generate draft', 'warning');
            }
        } catch (error) {
            console.error('AI Draft Error:', error);
            this.showToast('Error', 'Failed to generate AI draft: ' + this.extractErrorMessage(error), 'error');
        } finally {
            this.isGeneratingDraft = false;
        }
    }

    async handleCopyDraft() {
        if (!this.draftText) {
            this.showToast('Warning', 'No draft text to copy', 'warning');
            return;
        }

        try {
            await navigator.clipboard.writeText(this.draftText);
            this.showToast('Success', 'Draft copied to clipboard', 'success');
        } catch (error) {
            // Fallback for browsers that don't support clipboard API
            this.fallbackCopyToClipboard(this.draftText);
        }
    }

    fallbackCopyToClipboard(text) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        document.body.appendChild(textArea);
        textArea.select();
        
        try {
            document.execCommand('copy');
            this.showToast('Success', 'Draft copied to clipboard', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to copy to clipboard', 'error');
        }
        
        document.body.removeChild(textArea);
    }

    async handleSaveLog() {
        this.isSavingLog = true;
        
        try {
            const triageJson = JSON.stringify(this.triage);
            const snapshotJson = this.buildDataSnapshot();
            const actionJson = JSON.stringify({ actions: this.actionsTaken });
            const aiUsed = !!this.draftText;

            await saveTriageLog({
                caseId: this.recordId,
                triageJson: triageJson,
                draftReply: this.draftText,
                aiUsed: aiUsed,
                actionJson: actionJson,
                snapshotJson: snapshotJson,
                errorMsg: null
            });

            this.showToast('Success', 'Triage log saved successfully', 'success');
            
            // Refresh logs
            await refreshApex(this.wiredLogsResult);
            
            // Clear actions taken
            this.actionsTaken = [];
            
        } catch (error) {
            this.showToast('Error', 'Failed to save triage log: ' + this.extractErrorMessage(error), 'error');
        } finally {
            this.isSavingLog = false;
        }
    }

    async handleCreateTask() {
        await this.executeAction('CREATE_TASK', 'Task created successfully');
    }

    async handleEscalate() {
        await this.executeAction('ESCALATE', 'Case escalated successfully');
    }

    async handleUpdateStatus() {
        await this.executeAction('UPDATE_STATUS', 'Status updated successfully');
    }

    async executeAction(actionType, successMessage) {
        this.isActionInProgress = true;
        
        try {
            const result = await takeAction({ 
                caseId: this.recordId, 
                actionType: actionType 
            });
            
            if (result.success) {
                this.showToast('Success', result.message || successMessage, 'success');
                this.actionsTaken.push(actionType);
                
                // Notify the platform that the Case record has changed
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                
                // Force refresh of wired data
                await Promise.all([
                    refreshApex(this.wiredContextResult),
                    refreshApex(this.wiredTriageResult),
                    refreshApex(this.wiredLogsResult)
                ]);
            } else {
                this.showToast('Error', result.message || 'Action failed', 'error');
            }
        } catch (error) {
            console.error('Action error:', error);
            this.showToast('Error', 'Action failed: ' + this.extractErrorMessage(error), 'error');
        } finally {
            this.isActionInProgress = false;
        }
    }

    // ===== UTILITY METHODS =====

    buildDataSnapshot() {
        const snapshot = {
            subject: this.context?.caseRecord?.Subject,
            status: this.context?.caseRecord?.Status,
            priority: this.context?.caseRecord?.Priority,
            origin: this.context?.caseRecord?.Origin,
            emailCount: this.recentEmails.length,
            commentCount: this.recentComments.length,
            lastEmailSnippet: this.recentEmails[0]?.textBody?.substring(0, 200),
            timestamp: new Date().toISOString()
        };
        return JSON.stringify(snapshot);
    }

    formatDateTime(dateTimeString) {
        if (!dateTimeString) return '';
        try {
            const date = new Date(dateTimeString);
            return date.toLocaleString('en-US', {
                month: 'short',
                day: 'numeric',
                year: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
        } catch (error) {
            return dateTimeString;
        }
    }

    extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        return 'An unexpected error occurred';
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: variant === 'error' ? 'sticky' : 'dismissable'
        });
        this.dispatchEvent(event);
    }
}
