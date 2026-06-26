#include "RecoveryStrategy.h"

RecoveryStrategy StrategyForError(const std::wstring& errorCode) {
    RecoveryStrategy strategy;
    strategy.errorCode = errorCode;

    if (errorCode == L"LOCATOR_NOT_FOUND") {
        strategy.strategyName = L"locator_not_found_reobserve_ocr_stop";
        strategy.steps = {L"re-observe", L"OCR fallback", L"stop"};
        strategy.canAttempt = true;
        strategy.stopReason = L"Stop if re-observe and OCR fallback cannot resolve exactly one target.";
        return strategy;
    }

    if (errorCode == L"WINDOW_NOT_FOUND") {
        strategy.strategyName = L"window_not_found_find_process_activate_stop";
        strategy.steps = {L"find process/window", L"activate", L"stop"};
        strategy.canAttempt = true;
        strategy.stopReason = L"Stop if the target process/window cannot be uniquely resolved and activated.";
        return strategy;
    }

    if (errorCode == L"LOCATOR_NOT_UNIQUE" || errorCode == L"FIELD_NOT_UNIQUE" || errorCode == L"OCR_TEXT_NOT_UNIQUE") {
        strategy.strategyName = L"requires explicit selector or nth";
        strategy.steps = {L"stop"};
        strategy.canAttempt = false;
        strategy.stopReason = L"Multiple targets matched; require explicit selector or nth. Do not auto choose.";
        return strategy;
    }

    if (errorCode == L"TEXT_NOT_FOUND" || errorCode == L"OCR_TEXT_NOT_FOUND") {
        strategy.strategyName = L"text_not_found_wait_reobserve_stop";
        strategy.steps = {L"wait", L"re-observe", L"stop"};
        strategy.canAttempt = true;
        strategy.stopReason = L"Stop if text is still missing after wait and re-observe.";
        return strategy;
    }

    if (errorCode == L"LOADING" || errorCode == L"TARGET_NOT_READY") {
        strategy.strategyName = L"dynamic_loading_wait_observe_loop";
        strategy.steps = {L"wait", L"observe-loop", L"target_ready or loading_finished", L"stop on timeout"};
        strategy.canAttempt = true;
        strategy.stopReason = L"Stop if target_ready or loading_finished is not observed within the bounded wait.";
        return strategy;
    }

    if (errorCode == L"DIALOG_OPEN") {
        strategy.strategyName = L"dynamic_dialog_classify_safe_route";
        strategy.steps = {L"classify dialog", L"do not click underlay", L"safe dialog route or human confirmation"};
        strategy.canAttempt = false;
        strategy.stopReason = L"Dialog handling requires explicit safe route or human confirmation.";
        return strategy;
    }

    if (errorCode == L"ELEMENT_MOVED" || errorCode == L"STALE_CANDIDATE" || errorCode == L"PAGE_REPAINT") {
        strategy.strategyName = L"dynamic_reobserve_relocate";
        strategy.steps = {L"invalidate cache", L"re-observe", L"re-locate by ElementGraph", L"stop if ambiguous"};
        strategy.canAttempt = true;
        strategy.stopReason = L"Stop if refreshed ElementGraph cannot resolve exactly one low-risk target.";
        return strategy;
    }

    if (errorCode == L"ERROR_APPEARED") {
        strategy.strategyName = L"dynamic_error_stop_or_escalate";
        strategy.steps = {L"record error", L"stop or escalate depending risk"};
        strategy.canAttempt = false;
        strategy.stopReason = L"Error state is not auto-clickable; require caller inspection or safe recovery route.";
        return strategy;
    }

    if (errorCode == L"BLOCKED" || errorCode == L"SAFETY_BLOCKED") {
        strategy.strategyName = L"blocked_stop_immediately";
        strategy.steps = {L"stop"};
        strategy.canAttempt = false;
        strategy.stopReason = L"Blocked state is final and must not be routed to VLM for bypass.";
        return strategy;
    }

    if (errorCode == L"SAFETY_POLICY_DENIED") {
        strategy.strategyName = L"stop_immediately";
        strategy.steps = {L"stop"};
        strategy.canAttempt = false;
        strategy.stopReason = L"Safety policy denial is final and cannot be recovered.";
        return strategy;
    }

    strategy.strategyName = L"legacy_bounded_recovery";
    strategy.steps = {L"configured safe recovery", L"stop"};
    strategy.canAttempt = true;
    strategy.stopReason = L"Stop if the configured recovery action fails or is not available.";
    return strategy;
}
