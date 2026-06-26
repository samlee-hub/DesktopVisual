#include "VisibleOperationPolicy.h"

#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool EqNoCase(const std::wstring& a, const std::wstring& b) {
    return Lower(a) == Lower(b);
}

std::wstring NormalizeResult(const std::wstring& value, bool attempted) {
    if (value.empty()) return attempted ? L"attempted" : L"not_attempted";
    return Lower(value);
}

bool FailedWithReason(bool attempted, const std::wstring& result, const std::wstring& reason) {
    return attempted && EqNoCase(result, L"failed") && !reason.empty();
}

bool Succeeded(const std::wstring& result) {
    return EqNoCase(result, L"succeeded") || EqNoCase(result, L"success") || EqNoCase(result, L"ok");
}

bool IsWeakSurfaceImpossibleReason(const std::wstring& reason) {
    std::wstring lower = Lower(reason);
    return lower == L"target_not_found" ||
           lower == L"uia_not_found" ||
           lower == L"ocr_not_found" ||
           lower == L"click_failed" ||
           lower == L"uia_element_not_found" ||
           lower == L"ui_element_not_found" ||
           lower == L"visible_target_not_found";
}

bool SurfaceImpossibleEvidenceStrict(const VisibleOperationPolicyResult& result) {
    return result.surfaceImpossible &&
           !result.surfaceImpossibleReason.empty() &&
           result.surfaceImpossibleEvidencePresent &&
           !IsWeakSurfaceImpossibleReason(result.surfaceImpossibleReason);
}

bool BoundedVisibleAttemptEvidencePresent(const VisibleOperationPolicyResult& result, bool attempt1Failed) {
    return attempt1Failed &&
           result.visibleAttemptCount >= result.minVisibleAttemptsBeforeShortcut &&
           result.preActionCheckpointPresent &&
           result.boundedRecoveryAttempted &&
           result.postRecoveryObserved &&
           result.sameSurfaceAfterRecovery;
}

bool BackendFallbackReasonDisallowed(const std::wstring& reason) {
    std::wstring lower = Lower(reason);
    return lower.find(L"convenience") != std::wstring::npos ||
           lower.find(L"speed") != std::wstring::npos ||
           lower.find(L"test shortcut") != std::wstring::npos ||
           lower.find(L"test_shortcut") != std::wstring::npos ||
           lower.find(L"test-only") != std::wstring::npos ||
           lower.find(L"test only") != std::wstring::npos;
}

bool IsAllowedVlmStage(const std::wstring& stage) {
    std::wstring lower = Lower(stage);
    return lower.empty() ||
           lower == L"none" ||
           lower == L"visible_attempt_1_recovery" ||
           lower == L"keyboard_state_verify";
}

void Fail(VisibleOperationPolicyResult& result, const std::wstring& code, const std::wstring& message, bool priorityViolation = true) {
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.priorityViolation = priorityViolation;
    result.acceptanceGateFailureCode = L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION";
    result.finalResult = priorityViolation ? L"RESULT_INVALID_DUE_TO_VISIBLE_FIRST_VIOLATION" : L"FAILED";
}

bool IsShowDesktopOperation(const std::wstring& operationType) {
    return EqNoCase(operationType, L"show_desktop") || EqNoCase(operationType, L"reveal_desktop");
}

bool IsWindowSwitchOperation(const std::wstring& operationType) {
    return EqNoCase(operationType, L"window_switch") || EqNoCase(operationType, L"focus") || EqNoCase(operationType, L"window_focus");
}

bool ModeIs(const std::wstring& mode, const std::wstring& expected) {
    return EqNoCase(mode, expected);
}

bool ModeMatchesAttempt2(const VisibleOperationPolicyResult& result) {
    return ModeIs(result.finalModeUsed, result.attempt2Mode) ||
           ModeIs(result.finalModeUsed, L"keyboard_shortcut_fallback") ||
           ModeIs(result.finalModeUsed, L"win_d_keyboard_shortcut_fallback");
}

std::wstring DefaultAttempt1Mode(const VisibleOperationPolicyOptions& options) {
    if (!options.attempt1Mode.empty()) return Lower(options.attempt1Mode);
    if (IsShowDesktopOperation(options.operationType)) return L"visible_mouse_click_show_desktop";
    if (IsWindowSwitchOperation(options.operationType)) return L"alt_tab_keyboard_switch";
    return L"visible_mouse_keyboard";
}

std::wstring DefaultAttempt2Mode(const VisibleOperationPolicyOptions& options) {
    if (!options.attempt2Mode.empty()) return Lower(options.attempt2Mode);
    if (IsShowDesktopOperation(options.operationType)) return L"win_d_keyboard_shortcut_fallback";
    if (IsWindowSwitchOperation(options.operationType)) return L"visible_taskbar_or_window_click";
    return L"keyboard_shortcut_fallback";
}

std::wstring DefaultAttempt3Mode(const VisibleOperationPolicyOptions& options) {
    if (!options.attempt3Mode.empty()) return Lower(options.attempt3Mode);
    if (IsShowDesktopOperation(options.operationType)) return L"backend_show_desktop_fallback";
    if (IsWindowSwitchOperation(options.operationType)) return L"backend_focus_fallback";
    return L"backend_fallback";
}

std::wstring NormalizeFinalMode(const VisibleOperationPolicyOptions& options, const VisibleOperationPolicyResult& result) {
    if (!options.finalModeUsed.empty()) return Lower(options.finalModeUsed);
    if (options.backendFallbackUsed) return result.attempt3Mode;
    if (Succeeded(result.attempt2Result)) return result.attempt2Mode;
    return result.attempt1Mode;
}

}  // namespace

std::wstring visible_operation_backend_violation_code(const std::wstring& operationType, const std::wstring& backendFallbackKind) {
    if (EqNoCase(backendFallbackKind, L"clipboard") || EqNoCase(backendFallbackKind, L"clipboard_paste") || EqNoCase(backendFallbackKind, L"clipboard_set")) {
        return L"FAIL_CLIPBOARD_PRIORITY_VIOLATION";
    }
    if (EqNoCase(operationType, L"app_launch") || EqNoCase(operationType, L"launch")) {
        return L"BLOCKED_BACKEND_LAUNCH_USED_BEFORE_VISIBLE_LAUNCH";
    }
    if (EqNoCase(operationType, L"pycharm_launch")) {
        return L"BLOCKED_PYCHARM_BACKEND_LAUNCH_PRIORITY_VIOLATION";
    }
    if (IsShowDesktopOperation(operationType) || EqNoCase(backendFallbackKind, L"backend_show_desktop")) {
        return L"BLOCKED_BACKEND_SHOW_DESKTOP_USED_BEFORE_VISIBLE_AND_SHORTCUT";
    }
    if (IsWindowSwitchOperation(operationType)) {
        return L"BLOCKED_BACKEND_FOCUS_USED_BEFORE_ALT_TAB_AND_VISIBLE_CLICK";
    }
    if (EqNoCase(operationType, L"browser_navigation") || EqNoCase(operationType, L"browser_nav")) {
        return L"BLOCKED_BACKEND_BROWSER_NAV_USED_BEFORE_VISIBLE_NAV";
    }
    if (EqNoCase(operationType, L"page_navigation") || EqNoCase(operationType, L"page_nav")) {
        return L"BLOCKED_BACKEND_PAGE_NAV_USED_BEFORE_VISIBLE_NAV";
    }
    if (EqNoCase(operationType, L"tab_switch") || EqNoCase(operationType, L"panel_switch") || EqNoCase(operationType, L"ide_panel_switch")) {
        return L"BLOCKED_BACKEND_TAB_SWITCH_USED_BEFORE_VISIBLE_SWITCH";
    }
    return L"FAIL_BACKEND_PRIORITY_VIOLATION";
}

VisibleOperationPolicyResult enforce_visible_operation_priority(const VisibleOperationPolicyOptions& options) {
    VisibleOperationPolicyResult result;
    result.operationId = options.operationId;
    result.operationType = options.operationType.empty() ? L"visible_ui_operation" : options.operationType;
    result.attempt1Mode = DefaultAttempt1Mode(options);
    result.attempt2Mode = DefaultAttempt2Mode(options);
    result.attempt3Mode = DefaultAttempt3Mode(options);
    result.visibleMouseKeyboardAttempted = options.visibleMouseKeyboardAttempted;
    result.keyboardShortcutAttempted = options.keyboardShortcutAttempted;
    result.backendFallbackUsed = options.backendFallbackUsed;
    result.backendFallbackReason = options.backendFallbackReason;
    result.backendFallbackReasonPresent = !options.backendFallbackReason.empty();
    result.explicitBackendRequested = options.explicitBackendRequested;
    result.maxAttemptsExceeded = options.maxAttemptsExceeded;
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
    result.attempt1Result = NormalizeResult(options.attempt1Result, options.visibleMouseKeyboardAttempted);
    result.attempt1FailureReason = options.attempt1FailureReason;
    result.minVisibleAttemptsBeforeShortcut = options.minVisibleAttemptsBeforeShortcut > 0 ? options.minVisibleAttemptsBeforeShortcut : 2;
    result.visibleAttemptCount = options.visibleAttemptCount > 0
        ? options.visibleAttemptCount
        : (options.visibleMouseKeyboardAttempted ? 1 : 0);
    result.preActionCheckpointPresent = options.preActionCheckpointPresent;
    result.boundedRecoveryAttempted = options.boundedRecoveryAttempted;
    result.postRecoveryObserved = options.postRecoveryObserved;
    result.sameSurfaceAfterRecovery = options.sameSurfaceAfterRecovery;
    result.surfaceImpossible = options.surfaceImpossible;
    result.surfaceImpossibleReason = options.surfaceImpossibleReason;
    result.surfaceImpossibleEvidencePresent = options.surfaceImpossibleEvidencePresent;
    result.attempt2Result = NormalizeResult(options.attempt2Result, options.keyboardShortcutAttempted);
    result.attempt2FailureReason = options.attempt2FailureReason;
    result.attempt3Result = NormalizeResult(options.attempt3Result, options.backendFallbackUsed);
    result.finalModeUsed = NormalizeFinalMode(options, result);

    if (result.vlmActionExecuted) {
        Fail(result, L"FAIL_VLM_DIRECT_ACTION_FORBIDDEN", L"VLM assist must not directly execute mouse, keyboard, command, or backend actions.");
        return result;
    }
    if (result.vlmAfterBackendAttempted) {
        Fail(result, L"FAIL_VLM_AFTER_BACKEND_FORBIDDEN", L"VLM assist must not run after backend fallback has started.");
        return result;
    }
    if (!IsAllowedVlmStage(result.vlmAssistStage)) {
        Fail(result, L"FAIL_VLM_STAGE_INVALID", L"VLM assist stage must be visible_attempt_1_recovery, keyboard_state_verify, or none.");
        return result;
    }

    if (result.maxAttemptsExceeded) {
        Fail(result, L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION", L"Operation exceeded the three-stage visible-first priority chain.");
        return result;
    }

    bool attempt1Failed = FailedWithReason(result.visibleMouseKeyboardAttempted, result.attempt1Result, result.attempt1FailureReason);
    bool attempt2Failed = FailedWithReason(result.keyboardShortcutAttempted, result.attempt2Result, result.attempt2FailureReason);
    bool surfaceImpossibleStrict = SurfaceImpossibleEvidenceStrict(result);
    if (result.surfaceImpossible && !surfaceImpossibleStrict) {
        std::wstring code = result.surfaceImpossibleReason.empty() || !result.surfaceImpossibleEvidencePresent
            ? L"FAIL_SURFACE_IMPOSSIBLE_EVIDENCE_MISSING"
            : L"FAIL_SURFACE_IMPOSSIBLE_REASON_WEAK";
        Fail(result, code, L"surfaceImpossible requires a strict reason and explicit evidence; ordinary target_not_found, uia_not_found, ocr_not_found, or click_failed evidence is insufficient.");
        return result;
    }
    result.visibleStageSatisfiedForFallback = surfaceImpossibleStrict || BoundedVisibleAttemptEvidencePresent(result, attempt1Failed);

    if (IsShowDesktopOperation(result.operationType)) {
        if (result.backendFallbackUsed && !options.explicitBackendRequested &&
            (!result.visibleStageSatisfiedForFallback || !attempt2Failed || result.backendFallbackReason.empty())) {
            Fail(result, L"BLOCKED_BACKEND_SHOW_DESKTOP_USED_BEFORE_VISIBLE_AND_SHORTCUT", L"Backend show desktop was used before bottom-right visible click and Win+D fallback failures were recorded.");
            return result;
        }
        bool firstStepSkipped = !result.visibleMouseKeyboardAttempted &&
            (result.keyboardShortcutAttempted || result.backendFallbackUsed ||
             ModeIs(result.finalModeUsed, result.attempt2Mode) ||
             ModeIs(result.finalModeUsed, result.attempt3Mode) ||
             ModeIs(result.finalModeUsed, L"keyboard_shortcut_fallback") ||
             ModeIs(result.finalModeUsed, L"backend_fallback"));
        if (firstStepSkipped) {
            Fail(result, L"FAIL_SHOW_DESKTOP_VISIBLE_CLICK_NOT_ATTEMPTED", L"Show desktop must first attempt the bottom-right visible Show Desktop click target.");
            return result;
        }
        if (ModeMatchesAttempt2(result) && !result.visibleStageSatisfiedForFallback && !ModeIs(result.finalModeUsed, result.attempt1Mode)) {
            Fail(result, L"FAIL_SHOW_DESKTOP_VISIBLE_CLICK_NOT_ATTEMPTED", L"Win+D fallback cannot be used before bottom-right visible Show Desktop click failure evidence.");
            return result;
        }
    }

    if (IsWindowSwitchOperation(result.operationType)) {
        bool finalVisibleClick = ModeIs(result.finalModeUsed, L"visible_taskbar_or_window_click") || ModeIs(result.finalModeUsed, result.attempt2Mode);
        bool attempt1IsAltTab = ModeIs(result.attempt1Mode, L"alt_tab_keyboard_switch");
        if (finalVisibleClick && (!attempt1IsAltTab || !attempt1Failed)) {
            result.windowSwitchPrimaryAltTabSkipped = true;
        }
    }

    if (result.backendFallbackUsed && !options.explicitBackendRequested) {
        if (!result.visibleStageSatisfiedForFallback || !attempt2Failed || result.backendFallbackReason.empty()) {
            std::wstring code = visible_operation_backend_violation_code(result.operationType, options.backendFallbackKind);
            Fail(result, code, L"Backend fallback was used before visible mouse/keyboard and keyboard shortcut failures were recorded.");
            return result;
        }
        if (BackendFallbackReasonDisallowed(result.backendFallbackReason)) {
            std::wstring code = visible_operation_backend_violation_code(result.operationType, options.backendFallbackKind);
            Fail(result, code, L"Backend fallback reason cannot be convenience, speed, or a test shortcut.");
            return result;
        }
    }

    if (!IsWindowSwitchOperation(result.operationType) && ModeMatchesAttempt2(result)) {
        if (!result.visibleStageSatisfiedForFallback && !ModeIs(result.finalModeUsed, result.attempt1Mode)) {
            Fail(result, L"FAIL_KEYBOARD_SHORTCUT_PRIORITY_VIOLATION", L"Keyboard shortcut fallback requires two bounded visible attempts or strict surface-impossible evidence.");
            return result;
        }
    }

    if (result.backendFallbackUsed && EqNoCase(result.attempt3Result, L"failed")) {
        result.ok = false;
        result.errorCode = L"all_operation_modes_failed";
        result.errorMessage = L"Visible mouse/keyboard, keyboard shortcut fallback, and backend fallback all failed.";
        result.finalResult = L"FAILED";
        return result;
    }

    result.ok = true;
    result.finalResult = Succeeded(result.attempt1Result) || Succeeded(result.attempt2Result) || Succeeded(result.attempt3Result)
        ? L"PASS"
        : L"POLICY_PASS";
    return result;
}

std::wstring VisibleOperationPolicyJson(const VisibleOperationPolicyResult& result) {
    std::wstring json = L"{";
    json += L"\"operation_id\":" + simplejson::Quote(result.operationId);
    json += L",\"operation_type\":" + simplejson::Quote(result.operationType);
    json += L",\"attempt_1_mode\":" + simplejson::Quote(result.attempt1Mode);
    json += L",\"attempt_1_result\":" + simplejson::Quote(result.attempt1Result);
    json += L",\"attempt_1_failure_reason\":" + simplejson::Quote(result.attempt1FailureReason);
    json += L",\"attempt_2_mode\":" + simplejson::Quote(result.attempt2Mode);
    json += L",\"attempt_2_result\":" + simplejson::Quote(result.attempt2Result);
    json += L",\"attempt_2_failure_reason\":" + simplejson::Quote(result.attempt2FailureReason);
    json += L",\"attempt_3_mode\":" + simplejson::Quote(result.attempt3Mode);
    json += L",\"attempt_3_result\":" + simplejson::Quote(result.attempt3Result);
    json += L",\"final_mode_used\":" + simplejson::Quote(result.finalModeUsed);
    json += L",\"visible_mouse_keyboard_attempted\":" + simplejson::Bool(result.visibleMouseKeyboardAttempted);
    json += L",\"visible_attempt_count\":" + std::to_wstring(result.visibleAttemptCount);
    json += L",\"min_visible_attempts_before_shortcut\":" + std::to_wstring(result.minVisibleAttemptsBeforeShortcut);
    json += L",\"pre_action_checkpoint_present\":" + simplejson::Bool(result.preActionCheckpointPresent);
    json += L",\"bounded_recovery_attempted\":" + simplejson::Bool(result.boundedRecoveryAttempted);
    json += L",\"post_recovery_observed\":" + simplejson::Bool(result.postRecoveryObserved);
    json += L",\"same_surface_after_recovery\":" + simplejson::Bool(result.sameSurfaceAfterRecovery);
    json += L",\"surface_impossible\":" + simplejson::Bool(result.surfaceImpossible);
    json += L",\"surface_impossible_reason\":" + simplejson::Quote(result.surfaceImpossibleReason);
    json += L",\"surface_impossible_evidence_present\":" + simplejson::Bool(result.surfaceImpossibleEvidencePresent);
    json += L",\"visible_stage_satisfied_for_fallback\":" + simplejson::Bool(result.visibleStageSatisfiedForFallback);
    json += L",\"keyboard_shortcut_attempted\":" + simplejson::Bool(result.keyboardShortcutAttempted);
    json += L",\"backend_fallback_used\":" + simplejson::Bool(result.backendFallbackUsed);
    json += L",\"backend_fallback_reason\":" + simplejson::Quote(result.backendFallbackReason);
    json += L",\"backend_fallback_reason_present\":" + simplejson::Bool(result.backendFallbackReasonPresent);
    json += L",\"explicit_backend_requested\":" + simplejson::Bool(result.explicitBackendRequested);
    json += L",\"priority_violation\":" + simplejson::Bool(result.priorityViolation);
    json += L",\"max_attempts_exceeded\":" + simplejson::Bool(result.maxAttemptsExceeded);
    json += L",\"window_switch_primary_alt_tab_skipped\":" + simplejson::Bool(result.windowSwitchPrimaryAltTabSkipped);
    json += L",\"acceptance_gate_failure_code\":" + simplejson::Quote(result.acceptanceGateFailureCode);
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
    json += L"}";
    return json;
}
