#pragma once

#include "VisibleOperationPolicy.h"

#include <string>

struct VisibleUIVerificationOptions {
    bool finalEvidenceGlobal = false;
    bool windowOnlyEvidence = false;
    bool expectedOutputVisible = false;
    bool targetWindowLocked = false;
    bool allowGlobalDesktop = false;
    bool rawCompleted = false;
    bool backendFallbackUsed = false;
    std::wstring backendFallbackReason;
    std::wstring operationType = L"visible_ui_operation";
    bool visibleMouseKeyboardAttempted = false;
    std::wstring visibleAttemptResult;
    std::wstring visibleFailureReason;
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
    std::wstring keyboardShortcutResult;
    std::wstring keyboardShortcutFailureReason;
    bool explicitBackendRequested = false;
    bool maxAttemptsExceeded = false;
    std::wstring finalModeUsed;

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

struct VisibleUIVerificationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool globalFinalFrameRequired = true;
    bool windowOnlyFinalEvidenceRejected = true;
    bool expectedOutputVisible = false;
    bool foregroundTargetConsistent = false;
    bool rawCompletedRejected = true;
    std::wstring finalResult = L"BLOCKED";
    bool priorityViolation = false;
    VisibleOperationPolicyResult operationPriority;

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

VisibleUIVerificationResult require_global_final_frame(const VisibleUIVerificationOptions& options);
VisibleUIVerificationResult reject_window_only_final_evidence(const VisibleUIVerificationOptions& options);
VisibleUIVerificationResult verify_expected_text_in_global_frame(const VisibleUIVerificationOptions& options);
VisibleUIVerificationResult verify_foreground_target_consistency(const VisibleUIVerificationOptions& options);
VisibleUIVerificationResult verify_action_result_not_raw_only(const VisibleUIVerificationOptions& options);
VisibleUIVerificationResult classify_final_result(const VisibleUIVerificationOptions& options);
std::wstring VisibleUIVerificationJson(const VisibleUIVerificationResult& result);
