#pragma once

#include <string>

struct VisibleOperationPolicyOptions {
    std::wstring operationId;
    std::wstring operationType;
    std::wstring backendFallbackKind;
    std::wstring finalModeUsed;
    std::wstring attempt1Mode;
    std::wstring attempt2Mode;
    std::wstring attempt3Mode;

    bool visibleMouseKeyboardAttempted = false;
    std::wstring attempt1Result;
    std::wstring attempt1FailureReason;
    int visibleAttemptCount = 0;
    int minVisibleAttemptsBeforeShortcut = 2;
    bool preActionCheckpointPresent = false;
    bool boundedRecoveryAttempted = false;
    bool postRecoveryObserved = false;
    bool sameSurfaceAfterRecovery = false;
    bool surfaceImpossible = false;
    std::wstring surfaceImpossibleReason;
    bool surfaceImpossibleEvidencePresent = false;

    bool keyboardShortcutAttempted = false;
    std::wstring attempt2Result;
    std::wstring attempt2FailureReason;

    bool backendFallbackUsed = false;
    std::wstring backendFallbackReason;
    std::wstring attempt3Result;

    bool explicitBackendRequested = false;
    bool maxAttemptsExceeded = false;

    bool vlmAssistEnabled = false;
    std::wstring vlmCapabilityStatus = L"VLM_UNKNOWN";
    std::wstring vlmSessionId;
    bool vlmAssistAttempted = false;
    std::wstring vlmAssistTriggerReason;
    std::wstring vlmAssistStage = L"none";
    std::wstring vlmProvider;
    std::wstring vlmRawResponsePath;
    bool vlmCandidateAccepted = false;
    std::wstring vlmCandidateRejectedReason;
    bool vlmActionExecuted = false;
    bool vlmAfterBackendAttempted = false;
    std::wstring fallbackStageBeforeVlm;
    std::wstring fallbackStageAfterVlm;
};

struct VisibleOperationPolicyResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring operationId;
    std::wstring operationType;
    std::wstring attempt1Mode = L"visible_mouse_keyboard";
    std::wstring attempt1Result = L"not_attempted";
    std::wstring attempt1FailureReason;
    std::wstring attempt2Mode = L"keyboard_shortcut_fallback";
    std::wstring attempt2Result = L"not_attempted";
    std::wstring attempt2FailureReason;
    std::wstring attempt3Mode = L"backend_fallback";
    std::wstring attempt3Result = L"not_attempted";
    std::wstring finalModeUsed = L"visible_mouse_keyboard";
    bool visibleMouseKeyboardAttempted = false;
    int visibleAttemptCount = 0;
    int minVisibleAttemptsBeforeShortcut = 2;
    bool preActionCheckpointPresent = false;
    bool boundedRecoveryAttempted = false;
    bool postRecoveryObserved = false;
    bool sameSurfaceAfterRecovery = false;
    bool surfaceImpossible = false;
    std::wstring surfaceImpossibleReason;
    bool surfaceImpossibleEvidencePresent = false;
    bool visibleStageSatisfiedForFallback = false;
    bool keyboardShortcutAttempted = false;
    bool backendFallbackUsed = false;
    std::wstring backendFallbackReason;
    bool backendFallbackReasonPresent = false;
    bool priorityViolation = false;
    bool maxAttemptsExceeded = false;
    bool explicitBackendRequested = false;
    bool windowSwitchPrimaryAltTabSkipped = false;
    std::wstring acceptanceGateFailureCode;
    std::wstring finalResult = L"BLOCKED";

    bool vlmAssistEnabled = false;
    std::wstring vlmCapabilityStatus = L"VLM_UNKNOWN";
    std::wstring vlmSessionId;
    bool vlmAssistAttempted = false;
    std::wstring vlmAssistTriggerReason;
    std::wstring vlmAssistStage = L"none";
    std::wstring vlmProvider;
    std::wstring vlmRawResponsePath;
    bool vlmCandidateAccepted = false;
    std::wstring vlmCandidateRejectedReason;
    bool vlmActionExecuted = false;
    bool vlmAfterBackendAttempted = false;
    std::wstring fallbackStageBeforeVlm;
    std::wstring fallbackStageAfterVlm;
};

std::wstring visible_operation_backend_violation_code(const std::wstring& operationType, const std::wstring& backendFallbackKind);
VisibleOperationPolicyResult enforce_visible_operation_priority(const VisibleOperationPolicyOptions& options);
std::wstring VisibleOperationPolicyJson(const VisibleOperationPolicyResult& result);
