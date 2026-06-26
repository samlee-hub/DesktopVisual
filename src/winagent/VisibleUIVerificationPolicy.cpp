#include "VisibleUIVerificationPolicy.h"

#include "SimpleJson.h"

namespace {

VisibleUIVerificationResult Validate(const VisibleUIVerificationOptions& options) {
    VisibleUIVerificationResult result;
    result.expectedOutputVisible = options.expectedOutputVisible;
    result.foregroundTargetConsistent = options.targetWindowLocked || options.allowGlobalDesktop;
    result.vlmAssistEnabled = options.vlmAssistEnabled;
    result.vlmCapabilityStatus = options.vlmCapabilityStatus.empty() ? L"VLM_UNKNOWN" : options.vlmCapabilityStatus;
    result.vlmSessionId = options.vlmSessionId;
    result.vlmAssistAttempted = options.vlmAssistAttempted;
    result.vlmAssistTriggerReason = options.vlmAssistTriggerReason;
    result.vlmAssistStage = options.vlmAssistStage.empty() ? L"none" : options.vlmAssistStage;
    result.vlmProvider = options.vlmProvider;
    result.vlmRawResponsePath = options.vlmRawResponsePath;
    result.vlmCandidateAccepted = options.vlmCandidateAccepted;
    result.vlmCandidateRejectedReason = options.vlmCandidateRejectedReason;
    result.vlmActionExecuted = options.vlmActionExecuted;
    result.vlmAfterBackendAttempted = options.vlmAfterBackendAttempted;
    result.fallbackStageBeforeVlm = options.fallbackStageBeforeVlm;
    result.fallbackStageAfterVlm = options.fallbackStageAfterVlm;

    VisibleOperationPolicyOptions priorityOptions;
    priorityOptions.operationType = options.operationType.empty() ? L"visible_ui_operation" : options.operationType;
    priorityOptions.backendFallbackUsed = options.backendFallbackUsed;
    priorityOptions.backendFallbackReason = options.backendFallbackReason;
    priorityOptions.backendFallbackKind = options.backendFallbackUsed ? L"backend" : L"";
    priorityOptions.visibleMouseKeyboardAttempted = options.visibleMouseKeyboardAttempted;
    priorityOptions.attempt1Result = options.visibleAttemptResult;
    priorityOptions.attempt1FailureReason = options.visibleFailureReason;
    priorityOptions.visibleAttemptCount = options.visibleAttemptCount;
    priorityOptions.minVisibleAttemptsBeforeShortcut = options.minVisibleAttemptsBeforeShortcut;
    priorityOptions.preActionCheckpointPresent = options.preActionCheckpointPresent;
    priorityOptions.boundedRecoveryAttempted = options.boundedRecoveryAttempted;
    priorityOptions.postRecoveryObserved = options.postRecoveryObserved;
    priorityOptions.sameSurfaceAfterRecovery = options.sameSurfaceAfterRecovery;
    priorityOptions.surfaceImpossible = options.surfaceImpossible;
    priorityOptions.surfaceImpossibleReason = options.surfaceImpossibleReason;
    priorityOptions.surfaceImpossibleEvidencePresent = options.surfaceImpossibleEvidencePresent;
    priorityOptions.keyboardShortcutAttempted = options.keyboardShortcutAttempted;
    priorityOptions.attempt2Result = options.keyboardShortcutResult;
    priorityOptions.attempt2FailureReason = options.keyboardShortcutFailureReason;
    priorityOptions.attempt3Result = options.backendFallbackUsed ? L"succeeded" : L"not_attempted";
    priorityOptions.finalModeUsed = !options.finalModeUsed.empty()
        ? options.finalModeUsed
        : (options.backendFallbackUsed ? L"backend_fallback" : L"visible_mouse_keyboard");
    priorityOptions.explicitBackendRequested = options.explicitBackendRequested;
    priorityOptions.maxAttemptsExceeded = options.maxAttemptsExceeded;
    priorityOptions.vlmAssistEnabled = options.vlmAssistEnabled;
    priorityOptions.vlmCapabilityStatus = options.vlmCapabilityStatus;
    priorityOptions.vlmSessionId = options.vlmSessionId;
    priorityOptions.vlmAssistAttempted = options.vlmAssistAttempted;
    priorityOptions.vlmAssistTriggerReason = options.vlmAssistTriggerReason;
    priorityOptions.vlmAssistStage = options.vlmAssistStage;
    priorityOptions.vlmProvider = options.vlmProvider;
    priorityOptions.vlmRawResponsePath = options.vlmRawResponsePath;
    priorityOptions.vlmCandidateAccepted = options.vlmCandidateAccepted;
    priorityOptions.vlmCandidateRejectedReason = options.vlmCandidateRejectedReason;
    priorityOptions.vlmActionExecuted = options.vlmActionExecuted;
    priorityOptions.vlmAfterBackendAttempted = options.vlmAfterBackendAttempted;
    priorityOptions.fallbackStageBeforeVlm = options.fallbackStageBeforeVlm;
    priorityOptions.fallbackStageAfterVlm = options.fallbackStageAfterVlm;
    result.operationPriority = enforce_visible_operation_priority(priorityOptions);
    result.priorityViolation = result.operationPriority.priorityViolation;
    if (!result.operationPriority.ok) {
        result.errorCode = result.operationPriority.errorCode;
        result.errorMessage = result.operationPriority.errorMessage;
        result.finalResult = result.operationPriority.finalResult;
        return result;
    }

    if (options.windowOnlyEvidence) {
        result.errorCode = L"FAIL_FINAL_EVIDENCE_WINDOW_ONLY";
        result.errorMessage = L"Window-only screenshots cannot be final PASS evidence.";
        return result;
    }
    if (!options.finalEvidenceGlobal) {
        result.errorCode = L"FAIL_FINAL_EVIDENCE_NOT_GLOBAL";
        result.errorMessage = L"Final PASS evidence requires a global DPI-aware frame.";
        return result;
    }
    if (!options.expectedOutputVisible) {
        result.errorCode = L"FAIL_FINAL_OUTPUT_NOT_VISIBLE";
        result.errorMessage = L"Expected visible output was not verified in the global frame.";
        return result;
    }
    if (options.rawCompleted) {
        result.errorCode = L"FAIL_RAW_COMPLETED_AS_PASS";
        result.errorMessage = L"Raw completed status is not sufficient for final PASS.";
        return result;
    }
    if (!result.foregroundTargetConsistent) {
        result.errorCode = L"FAIL_FINAL_OUTPUT_NOT_VISIBLE";
        result.errorMessage = L"Final evidence is not tied to a locked target or explicit global desktop target.";
        return result;
    }

    result.ok = true;
    result.finalResult = result.operationPriority.priorityViolation ? L"RESULT_INVALID_DUE_TO_VISIBLE_FIRST_VIOLATION" : L"PASS";
    return result;
}

}  // namespace

VisibleUIVerificationResult require_global_final_frame(const VisibleUIVerificationOptions& options) {
    return Validate(options);
}

VisibleUIVerificationResult reject_window_only_final_evidence(const VisibleUIVerificationOptions& options) {
    return Validate(options);
}

VisibleUIVerificationResult verify_expected_text_in_global_frame(const VisibleUIVerificationOptions& options) {
    return Validate(options);
}

VisibleUIVerificationResult verify_foreground_target_consistency(const VisibleUIVerificationOptions& options) {
    return Validate(options);
}

VisibleUIVerificationResult verify_action_result_not_raw_only(const VisibleUIVerificationOptions& options) {
    return Validate(options);
}

VisibleUIVerificationResult classify_final_result(const VisibleUIVerificationOptions& options) {
    return Validate(options);
}

std::wstring VisibleUIVerificationJson(const VisibleUIVerificationResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"global_final_frame_required\":" + simplejson::Bool(result.globalFinalFrameRequired);
    json += L",\"window_only_final_evidence_rejected\":" + simplejson::Bool(result.windowOnlyFinalEvidenceRejected);
    json += L",\"expected_output_visible\":" + simplejson::Bool(result.expectedOutputVisible);
    json += L",\"foreground_target_consistent\":" + simplejson::Bool(result.foregroundTargetConsistent);
    json += L",\"raw_completed_rejected\":" + simplejson::Bool(result.rawCompletedRejected);
    json += L",\"priority_violation\":" + simplejson::Bool(result.priorityViolation);
    json += L",\"final_result\":" + simplejson::Quote(result.finalResult);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"vlm_assist_enabled\":" + simplejson::Bool(result.vlmAssistEnabled);
    json += L",\"vlm_capability_status\":" + simplejson::Quote(result.vlmCapabilityStatus);
    json += L",\"vlm_session_id\":" + simplejson::Quote(result.vlmSessionId);
    json += L",\"vlm_assist_attempted\":" + simplejson::Bool(result.vlmAssistAttempted);
    json += L",\"vlm_assist_trigger_reason\":" + simplejson::Quote(result.vlmAssistTriggerReason);
    json += L",\"vlm_assist_stage\":" + simplejson::Quote(result.vlmAssistStage);
    json += L",\"vlm_provider\":" + simplejson::Quote(result.vlmProvider);
    json += L",\"vlm_raw_response_path\":" + simplejson::Quote(result.vlmRawResponsePath);
    json += L",\"vlm_candidate_accepted\":" + simplejson::Bool(result.vlmCandidateAccepted);
    json += L",\"vlm_candidate_rejected_reason\":" + simplejson::Quote(result.vlmCandidateRejectedReason);
    json += L",\"vlm_action_executed\":" + simplejson::Bool(result.vlmActionExecuted);
    json += L",\"vlm_after_backend_attempted\":" + simplejson::Bool(result.vlmAfterBackendAttempted);
    json += L",\"fallback_stage_before_vlm\":" + simplejson::Quote(result.fallbackStageBeforeVlm);
    json += L",\"fallback_stage_after_vlm\":" + simplejson::Quote(result.fallbackStageAfterVlm);
    json += L",\"operation_priority\":" + VisibleOperationPolicyJson(result.operationPriority);
    json += L"}";
    return json;
}
