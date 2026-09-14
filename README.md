# Case Triage Copilot

[![Salesforce](https://img.shields.io/badge/Salesforce-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white)](https://salesforce.com)
[![Lightning Web Components](https://img.shields.io/badge/LWC-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white)](https://developer.salesforce.com/docs/component-library/documentation/en/lwc)
[![OpenAI](https://img.shields.io/badge/OpenAI-412991?style=for-the-badge&logo=openai&logoColor=white)](https://openai.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

An intelligent Salesforce Lightning Web Component (LWC) that helps support agents triage cases efficiently using rule-based scoring and optional AI-powered draft reply generation.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Data Model](#data-model)
- [Security](#security)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Future Enhancements](#future-enhancements)

---

## Features

### Automated Priority Scoring (0-100)

The rule-based scoring engine analyzes multiple factors:

| Factor | Score Impact |
|--------|--------------|
| **Case Priority** | Urgent (+40), High (+25), Medium (+10), Low (0) |
| **Critical Keywords** | "breach" (+30), "security" (+25), "outage" (+25), "urgent" (+15) |
| **Origin Channel** | Phone (+5), Email (+3), Web (0) |
| **Sentiment** | Frustrated language detected (+8 to +15) |
| **Status** | Escalated cases (+15) |

### Priority Bands

| Score | Band | Visual |
|-------|------|--------|
| 80-100 | Critical | Red |
| 60-79 | High | Orange |
| 30-59 | Medium | Yellow |
| 0-29 | Low | Green |

### Smart Routing

Automatically recommends the appropriate team based on case content:

- **Security** - breach, phishing, fraud, unauthorized access
- **Billing** - refund, invoice, payment, subscription
- **Engineering** - API, bug, error, integration
- **L2 Support** - High priority or escalated cases
- **L1 Support** - Standard inquiries

### AI-Powered Draft Replies

Optional OpenAI integration generates professional reply drafts:
- Context-aware responses based on case details
- Follows support best practices
- Includes clarifying questions and next steps
- Server-side API calls (key never exposed to client)

### Quick Actions

One-click actions for common operations:
- **Create Follow-up Task** - Creates a task assigned to the case owner
- **Escalate** - Sets priority to High, reassigns to Escalations queue
- **Update Status** - Toggles between "In Progress" and "Waiting on Customer"

### Audit Trail

Every triage session can be saved to `Case_Triage__c` for:
- Compliance and reporting
- Performance analytics
- Quality assurance reviews

---

## Installation

### Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) (v2.x or later)
- Salesforce org (Developer Edition, Sandbox, or Scratch Org)
- [OpenAI API key](https://platform.openai.com/api-keys) (for AI features)

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/case-triage-copilot.git
cd case-triage-copilot

# 2. Authenticate with your Salesforce org
sf org login web --alias MyOrg

# 3. Deploy to your org
sf project deploy start --source-dir force-app --target-org MyOrg

# 4. Run tests (optional)
sf apex run test --target-org MyOrg --test-level RunLocalTests --result-format human
```

---

## Configuration

### Step 1: Configure OpenAI API Key

1. Go to **Setup** → search for **Custom Metadata Types**
2. Click **OpenAI Config** → **Manage Records**
3. Click **Edit** on the **Default** record
4. Fill in the fields:

| Field | Value |
|-------|-------|
| **API Key** | Your OpenAI API key (e.g., `sk-...`) |
| **Model** | `gpt-4o` or `gpt-4o-mini` (or newer) |
| **Max Tokens** | `2000` (recommended) |
| **Endpoint** | `/v1/chat/completions` |

5. Click **Save**

### Step 2: Add Component to Case Page

1. Go to **Setup** → **Object Manager** → **Case** → **Lightning Record Pages**
2. Click **New** or edit an existing page
3. Search for **"Case Triage Copilot"** in the components panel
4. Drag it onto the page layout
5. Click **Save** → **Activation** → **Assign as Org Default**

### Step 3: (Optional) Create Escalations Queue

For the Escalate action to reassign cases:

1. Go to **Setup** → **Queues**
2. Click **New**
3. Name: `Escalations`
4. Add **Case** to Supported Objects
5. Add queue members
6. Click **Save**

---

## Usage

### Quick Demo (2 minutes)

1. **Open any Case record** - The component loads automatically

2. **Review Triage Summary**:
   - Priority Score (0-100)
   - Priority Band (Low/Medium/High/Critical)
   - Recommended Routing
   - Analysis Reasons

3. **Generate AI Draft** (optional):
   - Click **"Generate Draft (AI)"**
   - Review and edit the generated response
   - Click **Copy** to use it in your reply

4. **Take Quick Actions**:
   - **Create Follow-up Task** - Adds a task to Activity timeline
   - **Escalate** - Changes priority and assigns to queue
   - **Update Status** - Toggles case status

5. **Save to Log** - Persists the triage session for audit

### Test Scenarios

Try creating cases with different content to see scoring in action:

| Case Subject | Expected Result |
|--------------|-----------------|
| "Urgent security breach detected" | Critical (80+), Security routing |
| "Need refund for invoice #123" | Medium, Billing routing |
| "API returning 500 errors" | High, Engineering routing |
| "General question about features" | Low, L1 Support routing |

---

## Project Structure

```
case-triage-copilot/
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/                    # Apex classes
│           │   ├── CaseTriageController.cls    # LWC controller
│           │   ├── CaseTriageEngine.cls        # Scoring engine
│           │   ├── OpenAIService.cls           # AI integration
│           │   ├── *DTO.cls                    # Data transfer objects
│           │   └── *Test.cls                   # Test classes
│           ├── lwc/
│           │   └── caseTriageCopilot/      # Lightning Web Component
│           ├── objects/
│           │   ├── Case_Triage__c/         # Audit log object
│           │   └── OpenAI_Config__mdt/     # Configuration metadata
│           ├── customMetadata/             # Default config values
│           ├── layouts/                    # Page layouts
│           └── remoteSiteSettings/         # OpenAI endpoint whitelist
├── sfdx-project.json
├── README.md
└── LICENSE
```

---

## Data Model

### Case_Triage__c (Custom Object)

Stores triage session data for audit and reporting.

| Field | Type | Description |
|-------|------|-------------|
| `Case__c` | Lookup(Case) | Reference to the triaged case |
| `Triage_Timestamp__c` | DateTime | When triage was performed |
| `Priority_Score__c` | Number(3,0) | Computed score (0-100) |
| `Priority_Band__c` | Picklist | Low, Medium, High, Critical |
| `Recommended_Routing__c` | Picklist | Team recommendation |
| `Recommendation_Reason__c` | Long Text | Analysis reasons |
| `AI_Draft_Reply__c` | Long Text | Generated draft reply |
| `AI_Model__c` | Text(80) | OpenAI model used |
| `AI_Used__c` | Checkbox | Whether AI was invoked |
| `Actions_Taken__c` | Long Text | JSON of actions taken |
| `Data_Snapshot__c` | Long Text | JSON snapshot of inputs |
| `Error__c` | Long Text | Any errors encountered |

### OpenAI_Config__mdt (Custom Metadata)

Configuration for OpenAI integration.

| Field | Type | Description |
|-------|------|-------------|
| `API_Key__c` | Text(255) | OpenAI API key |
| `Model__c` | Text(80) | Model name (e.g., gpt-4o) |
| `MaxTokens__c` | Number | Max completion tokens |
| `Endpoint__c` | Text(255) | API endpoint path |

---

## Security

### API Key Protection
- OpenAI API key stored in Custom Metadata (server-side only)
- Never exposed to client-side JavaScript
- All API calls made via Apex callouts

### CRUD/FLS Enforcement
- All SOQL queries use `WITH SECURITY_ENFORCED`
- Explicit `Schema.sObjectType` checks before DML
- Field-level security validation

### Data Sanitization
- HTML stripped from email content before display
- Safe rendering of all user-generated content

---

## Testing

### Run All Tests

```bash
sf apex run test --target-org MyOrg --test-level RunLocalTests --result-format human --code-coverage
```

### Test Classes

| Class | Coverage |
|-------|----------|
| `CaseTriageEngineTest` | Scoring rules, routing logic, band boundaries |
| `OpenAIServiceTest` | API callouts with HttpCalloutMock |
| `CaseTriageControllerTest` | Controller methods, actions, CRUD |

### Test Scenarios Covered

- Low/Medium/High/Critical score calculations
- Keyword detection (security, billing, engineering)
- Angry language detection
- API success/error/timeout handling
- CRUD permission enforcement

---

## Troubleshooting

### "OpenAI API key not configured"

1. Go to **Setup** → **Custom Metadata Types** → **OpenAI Config**
2. Click **Manage Records** → Edit **Default**
3. Enter your API key and save

### "Empty response from AI" or "finish_reason: length"

The max tokens is too low. Increase **Max Tokens** to `2000` or higher in OpenAI Config.

### Component not showing on Case page

1. Verify deployment: `sf project deploy start --source-dir force-app`
2. Add component to Lightning Record Page in App Builder
3. Ensure the page is activated

### "Authentication failed"

1. Verify API key is correct
2. Check OpenAI account has available credits
3. Ensure Remote Site Setting for `api.openai.com` is active

---

## Future Enhancements

- [ ] **Sentiment Analysis** - Deeper NLP analysis of customer tone
- [ ] **SLA Breach Prediction** - Warn when cases risk breaching SLA
- [ ] **Similar Case Search** - RAG-based retrieval of resolved cases
- [ ] **Multilingual Support** - Generate replies in customer's language
- [ ] **Bulk Triage** - Triage multiple cases from list view
- [ ] **Custom Rules Builder** - Admin UI for routing rules
- [ ] **Knowledge Integration** - Suggest relevant articles
- [ ] **Slack/Teams Notifications** - Alert on critical cases

---

### Development Setup

```bash
# Create a scratch org
sf org create scratch --definition-file config/project-scratch-def.json --alias CopilotDev

# Push source
sf project deploy start --target-org CopilotDev

# Run tests
sf apex run test --target-org CopilotDev --test-level RunLocalTests
```

---
