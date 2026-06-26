#pragma once

#include "RecoveryStrategy.h"

#include <string>
#include <vector>

struct TaskStep {
    std::wstring name;
    std::wstring type;       // observe, locate, act, wait, screenshot, read_file
    std::wstring templateName;
    std::wstring templateParametersJson;
    int templateUsageId = -1;
    std::wstring selector;
    std::wstring action;     // click, double-click, right-click, type, focus
    std::wstring htmlPath;   // for form_action local DOM-like fixtures
    std::wstring fieldId;
    std::wstring label;
    std::wstring controlType;
    std::wstring value;
    std::wstring option;
    std::wstring text;
    // communication step (v3.3.8 Communication Action Runtime)
    std::wstring operation;
    std::wstring channel;
    std::wstring communicationTarget;
    std::wstring subject;
    std::wstring content;
    std::wstring contentSummary;
    bool userRequestedSend = false;
    // decision step (v3.3.6 General Decision Task Runtime)
    std::wstring userGoal;       // explicit task goal; content cannot supply it
    std::wstring currentUrl;     // optional current URL for the decision context
    std::wstring pageId;         // optional page/session anchor for checkpoints
    std::wstring observedSummary;
    std::wstring windowTitle;
    bool allowSubmit = false;    // submit actions require explicit authorization
    double minConfidence = 0.50; // confidence floor for an automatic decision
    // coding step (v3.3.9 Coding and Problem-Solving Web Workflow)
    std::wstring language;
    std::wstring codeText;
    std::wstring codePath;
    int revisionCount = 0;
    bool liveExecute = false;
    std::wstring editorSelector;
    std::wstring runSelector;
    std::wstring submitSelector;
    std::wstring resultSelector;
    std::wstring keys;
    std::wstring moveMode = L"human";
    std::wstring moveFallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int waitMs = 0;
    int timeoutMs = 5000;
    std::wstring path;       // for read_file/screenshot
    bool allowRetry = false;

    // expect block
    bool hasExpect = false;
    std::wstring expectSelectorExists;
    std::wstring expectTextContains;
    std::wstring expectFileContainsPath;
    std::wstring expectFileContainsText;
    std::wstring expectWindowTitleContains;
};

struct TaskBudget {
    int maxSteps = 50;
    int maxDurationMs = 120000;
    int maxRecoveries = 2;
};

struct TaskCheckpointConfig {
    bool enabled = true;
    int intervalMs = 300000;
    bool cleanupOnEnd = true;
};

struct TaskLoopGuardConfig {
    int repeatedActionLimit = 5;
    int urlRedirectLimit = 5;
    int noProgressLimit = 5;
    int windowSpawnLimit = 5;
    int scrollNoProgressLimit = 5;
};

struct TaskTarget {
    std::wstring title;
    std::wstring process;
};

struct TaskTemplateUsage {
    int id = -1;
    std::wstring name;
    std::wstring stepName;
    std::wstring parametersJson;
    std::wstring expandedStepsJson;
    int expandedStepCount = 0;
    bool ok = false;
};

struct TaskDefinition {
    int version = 1;
    std::wstring name;
    std::wstring permissionMode;
    std::wstring fullAccessSessionId;
    TaskTarget target;
    TaskBudget budget;
    TaskCheckpointConfig checkpoint;
    TaskLoopGuardConfig loopGuard;
    bool allowUnrestrictedDesktop = false;
    std::vector<TaskStep> steps;
    std::vector<TaskTemplateUsage> templateUsages;
};

enum class FailureCategory {
    NONE,
    WINDOW_NOT_FOUND,
    WINDOW_NOT_UNIQUE,
    WINDOW_TITLE_CHANGED,
    WINDOW_FOCUS_FAILED,
    SAFETY_POLICY_DENIED,
    USER_TAKEOVER_REQUIRED,
    CREDENTIAL_INPUT_DETECTED,
    CAPTCHA_DETECTED,
    ANTI_AUTOMATION_DETECTED,
    ANTI_CHEAT_DETECTED,
    LOOP_GUARD_STOP,
    LOCATOR_NOT_FOUND,
    LOCATOR_NOT_UNIQUE,
    OCR_UNAVAILABLE,
    OCR_FAILED,
    TEXT_NOT_FOUND,
    ACTION_FAILED,
    EXPECT_FAILED,
    TIMEOUT,
    UNKNOWN_ERROR
};

struct SessionCheckpoint {
    std::wstring checkpointId;
    std::wstring timestamp;
    std::wstring permissionMode;
    std::wstring taskId;
    int stepIndex = -1;
    std::wstring windowTitle;
    std::wstring processName;
    std::wstring url;
    std::wstring screenshotPath;
    std::wstring observedSummary;
    std::vector<std::wstring> recentActions;
    std::wstring formStateSummary;
    std::vector<std::wstring> suggestedRecoveryActions;
    std::wstring tempPath;
    bool temporaryCleaned = false;
};

struct CommunicationAction {
    std::wstring channel;
    std::wstring target;
    std::wstring subject;
    std::wstring contentSummary;
    std::wstring contentHash;
    bool userRequestedSend = false;
    bool sendActionPerformed = false;
    std::wstring permissionMode;
    std::wstring riskLevel;
};

struct FailureClassification {
    FailureCategory category = FailureCategory::NONE;
    std::wstring rawErrorCode;
    std::wstring rawErrorMessage;
    bool canRecover = false;
    std::wstring recommendedUserAction;
    std::wstring safeRecoveryAction;
    int recoveryAttempted = 0;
};

struct TaskStepResult {
    std::wstring stepName;
    std::wstring stepType;
    int templateUsageId = -1;
    std::wstring templateName;
    bool ok = false;
    std::wstring observeBefore;
    std::wstring observeAfter;
    std::wstring windowSessionBefore;
    std::wstring windowSessionAfter;
    std::wstring locateResult;
    std::wstring actionResult;
    std::wstring expectResult;
    std::wstring decisionContext;   // v3.3.6 DecisionTaskContext JSON (decision step)
    std::wstring decisionRecord;    // v3.3.6 DecisionRecord JSON (decision step)
    std::wstring communicationAction; // v3.3.8 CommunicationAction JSON (communication step)
    std::wstring codingContext;     // v3.3.9 CodingWorkflowContext JSON (coding step)
    std::wstring codingRecord;      // v3.3.9 CodingWorkflowRecord JSON (coding step)
    std::wstring screenshotPath;
    long long durationMs = 0;
    FailureClassification failure;
    std::vector<RecoveryAttemptRecord> recoveryAttempts;
    bool recovered = false;
};

struct TaskResult {
    bool ok = false;
    std::wstring taskName;
    std::wstring targetTitle;
    long long totalDurationMs = 0;
    int totalSteps = 0;
    int passedSteps = 0;
    int recoveriesUsed = 0;
    int maxRecoveriesEffective = 0;
    std::wstring finalErrorCode;
    std::wstring finalErrorMessage;
    std::wstring finalRecommendation;
    std::vector<TaskStepResult> stepResults;
    std::vector<RecoveryAttemptRecord> recoveryAttempts;
    std::vector<TaskTemplateUsage> templateUsages;
    std::vector<std::wstring> screenshots;
    std::vector<std::wstring> reportPaths;
    std::vector<SessionCheckpoint> checkpoints;
    std::wstring lastCheckpointId;
    bool temporaryCheckpointsCleaned = false;
    // environment
    std::wstring version;
    std::wstring platform;
    bool ocrAvailable = false;
    std::wstring ocrEngine;
    bool serviceMode = false;
    std::wstring permissionMode;
    std::wstring fullAccessSessionId;
    std::wstring permissionDecisionJson;
    std::wstring safetyConfigPath;
    bool safetyManifestLoaded = false;
    std::wstring safetyManifestPath;
    std::wstring safetyManifestSummaryJson;
    std::wstring initialPolicyCheckJson;
    std::wstring initialWindowSessionJson;
};

TaskResult RunTask(
    const std::wstring& taskJsonPath,
    const std::wstring& reportPath,
    bool serviceMode = false,
    const std::wstring& requestedPermissionMode = L"",
    const std::wstring& requestedFullAccessSessionId = L"");
