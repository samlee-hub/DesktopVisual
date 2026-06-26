#pragma once

// DecisionEngine - v3.3.6 General Decision Task Runtime
//
// The Decision Engine performs deterministic, auditable content decisions on
// behalf of a General Decision Task. Given an explicit user goal, the active
// permission mode, and the current page/control context, it classifies the task
// and chooses a single safe action mapping for one target field.
//
// It is intentionally NOT an autonomous planner:
//   - Page/chat/web content can never override the user's original goal.
//   - Unknown or low-confidence fields stop instead of guessing.
//   - Critical submit actions require explicit user authorization in the task.
//   - Captcha/credential/anti-automation content stops immediately.
//
// The engine itself does not send input, focus windows, or relax any permission
// or safety boundary. TaskRunner remains responsible for permission gating
// (content_decision capability), window/foreground checks, and execution.

#include <string>
#include <vector>

// Decision context assembled before choosing an action. Mirrors the documented
// DecisionTaskContext fields.
struct DecisionTaskContext {
    std::wstring userGoal;
    std::wstring permissionMode;          // DEFAULT | FULL_ACCESS
    std::wstring currentWindow;
    std::wstring currentUrl;              // optional, may be empty
    std::wstring observedContentSummary;
    std::vector<std::wstring> allowedActions;
    std::vector<std::wstring> deniedActions;
    std::wstring riskLevel;               // low | medium | high
};

// One auditable decision. Mirrors the documented DecisionRecord fields.
struct DecisionRecord {
    std::wstring decisionType;            // select | fill | click | submit | stop
    std::wstring source;                  // user_goal | page_content | mixed
    std::wstring reason;
    std::wstring selectedAction;          // mapped action, or stop code reason
    std::wstring targetFieldId;
    std::wstring targetLabel;
    std::wstring controlType;
    std::wstring chosenValue;             // value/option chosen (never a secret)
    double confidence = 0.0;
    bool userGoalPreserved = true;
    std::wstring safetyCheckResult;       // ok | <STOP_CODE>
    std::wstring timestamp;
};

// Result of a single-field decision evaluation.
struct DecisionEvalResult {
    bool ok = false;
    std::wstring errorCode;               // empty on success; a stop code on stop
    std::wstring errorMessage;
    DecisionTaskContext context;
    DecisionRecord record;
};

// Inputs for a single-field decision. The caller (decision-eval CLI or
// TaskRunner decision step) supplies the user goal, the target field, the
// requested value/option, whether submit is explicitly authorized, and the
// permission mode / window for the audit context.
struct DecisionInput {
    std::wstring userGoal;
    std::wstring permissionMode;
    std::wstring currentWindow;
    std::wstring currentUrl;
    std::wstring htmlPath;                // local HTML/DOM-like fixture
    std::wstring fieldId;
    std::wstring label;
    std::wstring controlTypeHint;         // optional explicit control type
    std::wstring value;
    std::wstring option;
    std::wstring text;
    bool allowSubmit = false;             // submit must be explicitly allowed
    double minConfidence = 0.50;
};

// Runs read_context -> classify_task -> choose_action -> record_decision for one
// field. Returns ok=true with a populated DecisionRecord when an action is
// chosen, or ok=false with a stop errorCode (CAPTCHA_DETECTED,
// ANTI_AUTOMATION_DETECTED, CREDENTIAL_INPUT_DETECTED, USER_TAKEOVER_REQUIRED,
// FIELD_CONFIDENCE_LOW, FIELD_NOT_UNIQUE, LOCATOR_NOT_FOUND, FILE_READ_FAILED).
DecisionEvalResult EvaluateDecision(const DecisionInput& input);

std::wstring DecisionTaskContextJson(const DecisionTaskContext& context);
std::wstring DecisionRecordJson(const DecisionRecord& record);
