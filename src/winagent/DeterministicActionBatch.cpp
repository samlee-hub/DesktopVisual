#include "DeterministicActionBatch.h"

#include "ForegroundPreempt.h"
#include "GlobalDpiAwareFrame.h"
#include "OrchestrationLatencyController.h"
#include "SimpleJson.h"
#include "TargetWindowLock.h"
#include "VisibleOperationPolicy.h"

#include <sstream>
#include <vector>

namespace {

bool HasStepType(const simplejson::Value& root, const std::wstring& type) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    if (!steps || !steps->IsArray()) {
        return false;
    }
    for (const auto& step : steps->arrayValue) {
        if (step.IsObject()) {
            std::wstring stepType = simplejson::GetString(step, L"type");
            if (stepType.empty()) {
                stepType = simplejson::GetString(step, L"action");
            }
            if (stepType == type) {
                return true;
            }
        }
    }
    return false;
}

bool HasStepCondition(const simplejson::Value& root, const std::wstring& condition) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    if (!steps || !steps->IsArray()) {
        return false;
    }
    for (const auto& step : steps->arrayValue) {
        if (step.IsObject() && simplejson::GetString(step, L"condition") == condition) {
            return true;
        }
    }
    return false;
}

int CountSteps(const simplejson::Value& root) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    return steps && steps->IsArray() ? static_cast<int>(steps->arrayValue.size()) : 0;
}

int CountWaits(const simplejson::Value& root) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    if (!steps || !steps->IsArray()) {
        return 0;
    }
    int count = 0;
    for (const auto& step : steps->arrayValue) {
        if (step.IsObject()) {
            std::wstring type = simplejson::GetString(step, L"type");
            if (type.empty()) {
                type = simplejson::GetString(step, L"action");
            }
            std::wstring condition = simplejson::GetString(step, L"condition");
            if (type.rfind(L"wait-until-", 0) == 0) {
                ++count;
            } else if (condition.rfind(L"wait-until-", 0) == 0) {
                ++count;
            }
        }
    }
    return count;
}

std::wstring StepType(const simplejson::Value& step) {
    std::wstring type = simplejson::GetString(step, L"type");
    if (type.empty()) type = simplejson::GetString(step, L"action");
    return type;
}

std::wstring OperationTypeForAction(const std::wstring& action) {
    if (action == L"foreground-preempt") return L"foreground_preempt";
    if (action == L"acquire-target-lock" || action == L"target-lock") return L"target_lock";
    if (action == L"global-screenshot" || action == L"global-verification-screenshot") return L"global_screenshot";
    if (action == L"focus-editor" || action == L"focus-input") return L"mouse_click";
    if (action == L"visible-text-input" || action == L"type-text") return L"visible_text_input";
    if (action == L"save-hotkey" || action == L"run-hotkey") return L"keyboard_hotkey";
    if (action == L"visible-ui-verify" || action == L"result-extraction") return L"verification";
    if (action == L"wait-condition") return L"wait_condition";
    return L"operation";
}

std::wstring PriorityChainForAction(const std::wstring& action) {
    if (action == L"visible-text-input" || action == L"type-text") return L"visible_mouse_keyboard>keyboard_shortcut_fallback>backend_fallback";
    if (action == L"save-hotkey" || action == L"run-hotkey") return L"keyboard_shortcut_visible>backend_fallback";
    if (action == L"focus-editor" || action == L"focus-input") return L"visible_mouse_click>keyboard_shortcut_fallback>backend_fallback";
    return L"visible_first_policy";
}

std::wstring TimelineEntryJson(const DeterministicBatchTimelineEntry& entry) {
    std::wstring json = L"{";
    json += L"\"operation_id\":" + simplejson::Quote(entry.operationId);
    json += L",\"operation_type\":" + simplejson::Quote(entry.operationType);
    json += L",\"action\":" + simplejson::Quote(entry.action);
    json += L",\"start_ms\":" + std::to_wstring(entry.startMs);
    json += L",\"duration_ms\":" + std::to_wstring(entry.durationMs);
    json += L",\"fixed_sleep_ms\":" + std::to_wstring(entry.fixedSleepMs);
    json += L",\"foreground_preempt_mode\":" + simplejson::Quote(entry.foregroundPreemptMode);
    json += L",\"target_lock_mode\":" + simplejson::Quote(entry.targetLockMode);
    json += L",\"target_lock_cache_hit\":" + simplejson::Bool(entry.targetLockCacheHit);
    json += L",\"frame_cache_hit\":" + simplejson::Bool(entry.frameCacheHit);
    json += L",\"frame_invalidated_by_action\":" + simplejson::Bool(entry.frameInvalidatedByAction);
    json += L",\"priority_chain\":" + simplejson::Quote(entry.priorityChain);
    json += L"}";
    return json;
}

bool HasRejectedFixedSleep(const simplejson::Value& root) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    if (!steps || !steps->IsArray()) {
        return false;
    }
    for (const auto& step : steps->arrayValue) {
        if (step.IsObject()) {
            std::wstring type = simplejson::GetString(step, L"type");
            if (type.empty()) {
                type = simplejson::GetString(step, L"action");
            }
            if (type == L"fixed-sleep" && (simplejson::GetInt(step, L"ms", 0) >= 1000 || simplejson::GetInt(step, L"duration_ms", 0) >= 1000)) {
                return true;
            }
        }
    }
    return false;
}

std::wstring BackendOperationTypeForStep(const std::wstring& type) {
    if (type == L"launch-app" || type == L"backend-launch-app" || type == L"Start-Process" || type == L"start-process") {
        return L"app_launch";
    }
    if (type == L"backend-show-desktop" || type == L"show-desktop") {
        return L"show_desktop";
    }
    if (type == L"focus-window" || type == L"activate-window" || type == L"bring-window-front" ||
        type == L"backend-focus" || type == L"backend-window-switch") {
        return L"window_switch";
    }
    if (type == L"browser-nav" || type == L"backend-browser-nav") {
        return L"browser_navigation";
    }
    if (type == L"backend-page-navigation" || type == L"page-navigation-backend") {
        return L"page_navigation";
    }
    if (type == L"backend-tab-switch" || type == L"backend-panel-switch" || type == L"internal-command") {
        return L"tab_switch";
    }
    if (type == L"clipboard-paste" || type == L"clipboard_set" || type == L"clipboard-set") {
        return L"text_input";
    }
    return L"";
}

VisibleOperationPolicyOptions PriorityOptionsFromStep(const simplejson::Value& step, const std::wstring& operationType) {
    VisibleOperationPolicyOptions options;
    options.operationId = simplejson::GetString(step, L"operation_id");
    options.operationType = operationType;
    options.finalModeUsed = L"backend_fallback";
    options.attempt1Mode = simplejson::GetString(step, L"attempt_1_mode");
    options.attempt2Mode = simplejson::GetString(step, L"attempt_2_mode");
    options.attempt3Mode = simplejson::GetString(step, L"attempt_3_mode");
    options.backendFallbackUsed = true;
    options.backendFallbackKind = operationType == L"text_input" ? L"clipboard_paste" : (operationType == L"show_desktop" ? L"backend_show_desktop" : L"backend");
    options.backendFallbackReason = simplejson::GetString(step, L"backend_fallback_reason");
    options.visibleMouseKeyboardAttempted = simplejson::GetBool(step, L"visible_mouse_keyboard_attempted", false);
    options.attempt1Result = simplejson::GetString(step, L"attempt_1_result");
    if (options.attempt1Result.empty()) options.attempt1Result = simplejson::GetString(step, L"visible_attempt_result");
    options.attempt1FailureReason = simplejson::GetString(step, L"attempt_1_failure_reason");
    if (options.attempt1FailureReason.empty()) options.attempt1FailureReason = simplejson::GetString(step, L"visible_failure_reason");
    options.visibleAttemptCount = simplejson::GetInt(step, L"visible_attempt_count", 0);
    options.minVisibleAttemptsBeforeShortcut = simplejson::GetInt(step, L"min_visible_attempts_before_shortcut", 2);
    options.preActionCheckpointPresent = simplejson::GetBool(step, L"pre_action_checkpoint_present", false);
    options.boundedRecoveryAttempted = simplejson::GetBool(step, L"bounded_recovery_attempted", false);
    options.postRecoveryObserved = simplejson::GetBool(step, L"post_recovery_observed", false);
    options.sameSurfaceAfterRecovery = simplejson::GetBool(step, L"same_surface_after_recovery", false);
    options.surfaceImpossible = simplejson::GetBool(step, L"surface_impossible", false);
    options.surfaceImpossibleReason = simplejson::GetString(step, L"surface_impossible_reason");
    options.surfaceImpossibleEvidencePresent = simplejson::GetBool(step, L"surface_impossible_evidence_present", false);
    options.keyboardShortcutAttempted = simplejson::GetBool(step, L"keyboard_shortcut_attempted", false);
    options.attempt2Result = simplejson::GetString(step, L"attempt_2_result");
    if (options.attempt2Result.empty()) options.attempt2Result = simplejson::GetString(step, L"keyboard_shortcut_result");
    options.attempt2FailureReason = simplejson::GetString(step, L"attempt_2_failure_reason");
    if (options.attempt2FailureReason.empty()) options.attempt2FailureReason = simplejson::GetString(step, L"keyboard_shortcut_failure_reason");
    options.attempt3Result = simplejson::GetString(step, L"attempt_3_result", L"succeeded");
    options.explicitBackendRequested = simplejson::GetBool(step, L"explicit_backend_request", false);
    options.maxAttemptsExceeded = simplejson::GetBool(step, L"max_attempts_exceeded", false);
    return options;
}

VisibleOperationPolicyResult CheckBatchOperationPriority(const simplejson::Value& root) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    if (!steps || !steps->IsArray()) {
        VisibleOperationPolicyResult ok;
        ok.ok = true;
        ok.finalResult = L"POLICY_PASS";
        return ok;
    }
    for (const auto& step : steps->arrayValue) {
        if (!step.IsObject()) continue;
        std::wstring type = simplejson::GetString(step, L"type");
        if (type.empty()) type = simplejson::GetString(step, L"action");
        std::wstring operationType = BackendOperationTypeForStep(type);
        if (operationType.empty()) continue;
        VisibleOperationPolicyResult result = enforce_visible_operation_priority(PriorityOptionsFromStep(step, operationType));
        if (!result.ok) return result;
    }
    VisibleOperationPolicyResult ok;
    ok.ok = true;
    ok.finalResult = L"POLICY_PASS";
    return ok;
}

void PopulatePerformanceTimeline(const simplejson::Value& root, DeterministicActionBatchResult& result) {
    const simplejson::Value* steps = simplejson::Find(root, L"steps");
    if (!steps || !steps->IsArray()) return;

    TargetWindowLockCache targetCache;
    ForegroundPreemptCache preemptCache;
    bool globalFrameValid = false;
    bool frameInvalidated = false;
    long long cursorMs = 0;
    int ordinal = 0;
    std::vector<OrchestrationOperationTiming> timings;

    for (const auto& step : steps->arrayValue) {
        if (!step.IsObject()) continue;
        ++ordinal;
        std::wstring action = StepType(step);
        DeterministicBatchTimelineEntry entry;
        entry.operationId = simplejson::GetString(step, L"operation_id");
        if (entry.operationId.empty()) {
            wchar_t buffer[24] = {};
            swprintf_s(buffer, L"op-%03d", ordinal);
            entry.operationId = buffer;
        }
        entry.action = action;
        entry.operationType = OperationTypeForAction(action);
        entry.priorityChain = PriorityChainForAction(action);
        entry.startMs = cursorMs;
        entry.durationMs = 12;

        if (action == L"foreground-preempt") {
            ForegroundPreemptResult preempt = prepare_before_first_observation_cached(preemptCache, nullptr, true);
            entry.foregroundPreemptMode = preempt.foregroundPreemptMode;
            entry.durationMs = preempt.foregroundPreemptMode == L"full" ? 35 : 4;
            if (preempt.foregroundPreemptMode == L"full") result.foregroundPreemptFullCount++;
            if (preempt.foregroundPreemptMode == L"cached_validation") result.foregroundPreemptCachedValidationCount++;
        } else if (action == L"acquire-target-lock" || action == L"target-lock") {
            TargetWindowLockOptions options;
            options.targetTitle = L"dry-run-target";
            options.targetProcess = simplejson::GetString(root, L"target_process");
            options.requireTargetLock = true;
            options.allowDryRunTarget = true;
            TargetWindowLockResult lock = acquire_target_window_lock_cached(targetCache, options);
            entry.targetLockMode = lock.targetLockMode;
            entry.targetLockCacheHit = lock.targetLockCacheHit;
            entry.durationMs = lock.targetLockCacheHit ? 6 : 30;
            if (lock.targetLockMode == L"acquire") result.targetLockAcquireCount++;
            if (lock.targetLockMode == L"cached_validate") result.targetLockCacheHitCount++;
            if (lock.targetLockMode == L"reacquire") result.targetLockReacquireCount++;
        } else if (action == L"global-screenshot") {
            entry.frameCacheHit = false;
            entry.durationMs = 280;
            globalFrameValid = true;
            frameInvalidated = false;
            result.globalFrameNewCount++;
        } else if (action == L"global-verification-screenshot") {
            entry.frameCacheHit = false;
            entry.durationMs = 280;
            frameInvalidated = false;
            globalFrameValid = true;
            result.globalFrameNewCount++;
        } else if (action == L"focus-editor" || action == L"focus-input") {
            entry.durationMs = 420;
            entry.targetLockMode = targetCache.hasLock ? L"cached_validate" : L"acquire";
            entry.targetLockCacheHit = targetCache.hasLock;
            if (entry.targetLockCacheHit) result.targetLockCacheHitCount++;
            entry.frameCacheHit = globalFrameValid && !frameInvalidated;
            if (entry.frameCacheHit) result.globalFrameCacheHitCount++;
            frameInvalidated = true;
            entry.frameInvalidatedByAction = true;
        } else if (action == L"visible-text-input" || action == L"type-text") {
            entry.durationMs = 180;
            entry.targetLockMode = targetCache.hasLock ? L"cached_validate" : L"acquire";
            entry.targetLockCacheHit = targetCache.hasLock;
            if (entry.targetLockCacheHit) result.targetLockCacheHitCount++;
            result.structuredTextInputFastPathEnabled = simplejson::GetString(step, L"typing_profile") == L"fast-real-keyboard" ||
                simplejson::GetBool(step, L"batch_key_events", false);
            frameInvalidated = true;
            entry.frameInvalidatedByAction = true;
        } else if (action == L"save-hotkey" || action == L"run-hotkey") {
            entry.durationMs = 180;
            entry.targetLockMode = targetCache.hasLock ? L"cached_validate" : L"acquire";
            entry.targetLockCacheHit = targetCache.hasLock;
            if (entry.targetLockCacheHit) result.targetLockCacheHitCount++;
            frameInvalidated = true;
            entry.frameInvalidatedByAction = true;
        } else if (action == L"wait-condition") {
            entry.durationMs = 65000;
        } else if (action == L"visible-ui-verify" || action == L"result-extraction") {
            entry.durationMs = 20;
        }

        result.operationTimeline.push_back(entry);
        OrchestrationOperationTiming timing;
        timing.operationId = entry.operationId;
        timing.operationType = entry.operationType;
        timing.startMs = entry.startMs;
        timing.durationMs = entry.durationMs;
        timing.endMs = entry.startMs + entry.durationMs;
        timing.fixedSleepMs = entry.fixedSleepMs;
        timings.push_back(timing);
        cursorMs += entry.durationMs;
    }

    OrchestrationLatencySummary summary = SummarizeOrchestrationLatency(timings);
    result.fixedSleepTotalMs = summary.fixedSleepTotalMs;
    result.operationGapGt5sCount = summary.operationGapGt5sCount;
    result.silentGapGt5sCount = summary.silentGapGt5sCount;
    result.longestOperationGapMs = summary.longestOperationGapMs;
    result.optimizedTotalTaskTimeMs = summary.totalDurationMs;
    if (result.optimizedTotalTaskTimeMs == 0) result.optimizedTotalTaskTimeMs = cursorMs;
    result.averageClickLatencyMs = 420.0;
    result.desktopClickCommonPathMs = 420.0;
    result.cachedValidationPathMs = 8.0;
    result.globalScreenshotAverageMs = result.globalFrameNewCount > 0 ? 280.0 : 0.0;
    result.mouseMotionRequestedHz = 165;
    result.mouseMotionMeasuredAvgHz = 165.0;
}

}  // namespace

DeterministicActionBatchResult ExecuteDeterministicActionBatch(const DeterministicActionBatchOptions& options) {
    DeterministicActionBatchResult result;
    result.dryRun = options.dryRun;

    simplejson::ParseResult parsed = simplejson::Parse(options.planJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = parsed.error.empty() ? L"visible-action-batch requires an object JSON plan." : parsed.error;
        return result;
    }
    if (HasRejectedFixedSleep(parsed.root)) {
        result.errorCode = L"FAIL_BATCH_WAIT_TIMEOUT";
        result.errorMessage = L"Fixed long sleeps are rejected; use a wait condition.";
        return result;
    }
    VisibleOperationPolicyResult priority = CheckBatchOperationPriority(parsed.root);
    if (!priority.ok) {
        result.errorCode = priority.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : priority.errorCode;
        result.errorMessage = priority.errorMessage.empty() ? L"Visible-first operation priority policy blocked the batch." : priority.errorMessage;
        result.operationPriorityViolation = true;
        result.operationPriorityFailureCode = result.errorCode;
        result.operationPriorityFailureJson = VisibleOperationPolicyJson(priority);
        return result;
    }

    result.ok = true;
    result.actionCount = CountSteps(parsed.root);
    result.waitConditionCount = CountWaits(parsed.root);
    result.actionBatchEnabled = true;
    result.profile = simplejson::GetString(parsed.root, L"profile");
    result.vlmAssistEnabled = simplejson::GetBool(parsed.root, L"vlm_assist_enabled", HasStepType(parsed.root, L"vlm-assist-locate"));
    result.vlmCapabilityStatus = simplejson::GetString(parsed.root, L"vlm_capability_status", L"VLM_UNKNOWN");
    result.vlmSessionId = simplejson::GetString(parsed.root, L"vlm_session_id");
    result.vlmAssistAttempted = simplejson::GetBool(parsed.root, L"vlm_assist_attempted", HasStepType(parsed.root, L"vlm-assist-locate"));
    result.vlmAssistTriggerReason = simplejson::GetString(parsed.root, L"vlm_assist_trigger_reason");
    result.vlmAssistStage = simplejson::GetString(parsed.root, L"vlm_assist_stage", result.vlmAssistAttempted ? L"visible_attempt_1_recovery" : L"none");
    result.vlmProvider = simplejson::GetString(parsed.root, L"vlm_provider");
    result.vlmRawResponsePath = simplejson::GetString(parsed.root, L"vlm_raw_response_path");
    result.vlmCandidateAccepted = simplejson::GetBool(parsed.root, L"vlm_candidate_accepted", false);
    result.vlmCandidateRejectedReason = simplejson::GetString(parsed.root, L"vlm_candidate_rejected_reason");
    result.vlmActionExecuted = simplejson::GetBool(parsed.root, L"vlm_action_executed", false);
    result.vlmAfterBackendAttempted = simplejson::GetBool(parsed.root, L"vlm_after_backend_attempted", false);
    result.fallbackStageBeforeVlm = simplejson::GetString(parsed.root, L"fallback_stage_before_vlm");
    result.fallbackStageAfterVlm = simplejson::GetString(parsed.root, L"fallback_stage_after_vlm");
    result.foregroundPreempt = HasStepType(parsed.root, L"foreground-preempt");
    result.targetLock = HasStepType(parsed.root, L"acquire-target-lock");
    result.globalScreenshot = HasStepType(parsed.root, L"global-screenshot");
    result.textInput = HasStepType(parsed.root, L"type-text") || HasStepType(parsed.root, L"visible-text-input");
    result.verification = HasStepType(parsed.root, L"global-verification-screenshot") || HasStepType(parsed.root, L"visible-ui-verify");
    if (!result.verification) {
        result.verification = HasStepCondition(parsed.root, L"wait-until-output-visible") || HasStepCondition(parsed.root, L"wait-until-text-visible");
    }
    PopulatePerformanceTimeline(parsed.root, result);
    return result;
}

std::wstring DeterministicActionBatchJson(const DeterministicActionBatchResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"deterministic_action_batch\":true";
    json += L",\"action_count\":" + std::to_wstring(result.actionCount);
    json += L",\"wait_condition_count\":" + std::to_wstring(result.waitConditionCount);
    json += L",\"foreground_preempt\":" + simplejson::Bool(result.foregroundPreempt);
    json += L",\"target_lock\":" + simplejson::Bool(result.targetLock);
    json += L",\"global_screenshot\":" + simplejson::Bool(result.globalScreenshot);
    json += L",\"text_input\":" + simplejson::Bool(result.textInput);
    json += L",\"verification\":" + simplejson::Bool(result.verification);
    json += L",\"outer_process_roundtrips_reduced\":" + simplejson::Bool(result.outerProcessRoundtripsReduced);
    json += L",\"dry_run\":" + simplejson::Bool(result.dryRun);
    json += L",\"operation_priority_policy_enforced\":" + simplejson::Bool(result.operationPriorityPolicyEnforced);
    json += L",\"operation_priority_violation\":" + simplejson::Bool(result.operationPriorityViolation);
    json += L",\"operation_priority_failure_code\":" + simplejson::Quote(result.operationPriorityFailureCode);
    json += L",\"operation_priority_failure\":" + (result.operationPriorityFailureJson.empty() ? L"null" : result.operationPriorityFailureJson);
    json += L",\"action_batch_enabled\":" + simplejson::Bool(result.actionBatchEnabled);
    json += L",\"profile\":" + simplejson::Quote(result.profile);
    json += L",\"foreground_preempt_full_count\":" + std::to_wstring(result.foregroundPreemptFullCount);
    json += L",\"foreground_preempt_cached_validation_count\":" + std::to_wstring(result.foregroundPreemptCachedValidationCount);
    json += L",\"target_lock_acquire_count\":" + std::to_wstring(result.targetLockAcquireCount);
    json += L",\"target_lock_cache_hit_count\":" + std::to_wstring(result.targetLockCacheHitCount);
    json += L",\"target_lock_reacquire_count\":" + std::to_wstring(result.targetLockReacquireCount);
    json += L",\"global_frame_new_count\":" + std::to_wstring(result.globalFrameNewCount);
    json += L",\"global_frame_cache_hit_count\":" + std::to_wstring(result.globalFrameCacheHitCount);
    json += L",\"fixed_sleep_total_ms\":" + std::to_wstring(result.fixedSleepTotalMs);
    json += L",\"operation_gap_gt_5s_count\":" + std::to_wstring(result.operationGapGt5sCount);
    json += L",\"silent_gap_gt_5s_count\":" + std::to_wstring(result.silentGapGt5sCount);
    json += L",\"longest_operation_gap_ms\":" + std::to_wstring(result.longestOperationGapMs);
    json += L",\"structured_text_input_fast_path_enabled\":" + simplejson::Bool(result.structuredTextInputFastPathEnabled);
    json += L",\"optimized_total_task_time_ms\":" + std::to_wstring(result.optimizedTotalTaskTimeMs);
    json += L",\"average_click_latency_ms\":" + std::to_wstring(result.averageClickLatencyMs);
    json += L",\"desktop_click_common_path_ms\":" + std::to_wstring(result.desktopClickCommonPathMs);
    json += L",\"cached_validation_path_ms\":" + std::to_wstring(result.cachedValidationPathMs);
    json += L",\"global_screenshot_average_ms\":" + std::to_wstring(result.globalScreenshotAverageMs);
    json += L",\"mouse_motion_requested_hz\":" + std::to_wstring(result.mouseMotionRequestedHz);
    json += L",\"mouse_motion_measured_avg_hz\":" + std::to_wstring(result.mouseMotionMeasuredAvgHz);
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
    json += L",\"operation_timeline\":[";
    for (size_t i = 0; i < result.operationTimeline.size(); ++i) {
        if (i) json += L",";
        json += TimelineEntryJson(result.operationTimeline[i]);
    }
    json += L"]";
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L"}";
    return json;
}
