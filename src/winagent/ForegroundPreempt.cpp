#include "ForegroundPreempt.h"

#include "SimpleJson.h"
#include "WindowFinder.h"

#include <sstream>

namespace {

long long Elapsed(ULONGLONG start) {
    return static_cast<long long>(GetTickCount64() - start);
}

bool RectValid(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

bool RectsIntersect(const RECT& a, const RECT& b) {
    return RectValid(a) && RectValid(b) &&
           a.left < b.right && a.right > b.left &&
           a.top < b.bottom && a.bottom > b.top;
}

bool GetRect(HWND hwnd, RECT& rect) {
    rect = {};
    return hwnd && IsWindow(hwnd) && GetWindowRect(hwnd, &rect) && RectValid(rect);
}

std::wstring HwndJson(HWND hwnd) {
    return hwnd ? simplejson::Quote(FormatHwnd(hwnd)) : L"null";
}

struct LightweightForegroundState {
    HWND foreground = nullptr;
    bool agentHostDetected = false;
    bool agentHostOverlappedTarget = false;
    RECT targetRect = {};
};

LightweightForegroundState CaptureLightweightForegroundState(HWND targetHwnd) {
    LightweightForegroundState state;
    state.foreground = GetForegroundWindow();
    WindowInfo host;
    state.agentHostDetected = DetectAgentHostWindow(state.foreground, host);
    RECT targetRect = {};
    if (targetHwnd && GetRect(targetHwnd, targetRect)) {
        state.targetRect = targetRect;
        state.agentHostOverlappedTarget = state.agentHostDetected && targetHwnd != host.hwnd && RectsIntersect(host.rect, targetRect);
    } else {
        state.agentHostOverlappedTarget = state.agentHostDetected;
    }
    return state;
}

void StoreCache(ForegroundPreemptCache& cache, HWND targetHwnd, const LightweightForegroundState& state) {
    cache.hasSnapshot = true;
    cache.targetHwnd = targetHwnd;
    cache.foregroundHwnd = state.foreground;
    cache.agentHostOverlappedTarget = state.agentHostOverlappedTarget;
    cache.agentHostDetected = state.agentHostDetected;
    cache.targetRect = state.targetRect;
}

ForegroundPreemptResult CachedOk(
    bool firstObservation,
    bool eachAction,
    const LightweightForegroundState& state,
    const std::wstring& mode,
    const std::wstring& reason,
    long long durationMs) {
    ForegroundPreemptResult result;
    result.ok = true;
    result.preemptRun = false;
    result.beforeFirstObservation = firstObservation;
    result.beforeEachAction = eachAction;
    result.agentHostNotCoveringTarget = !state.agentHostOverlappedTarget;
    result.foregroundPreemptMode = mode;
    result.foregroundPreemptReason = reason;
    result.durationMs = durationMs;
    result.preparation.ok = true;
    result.preparation.attempted = false;
    result.preparation.foregroundBefore = state.foreground;
    result.preparation.foregroundAfter = state.foreground;
    result.preparation.agentHostDetected = state.agentHostDetected;
    result.preparation.agentHostOverlappedTarget = state.agentHostOverlappedTarget;
    result.preparation.durationMs = durationMs;
    return result;
}

ForegroundPreemptResult RunFullPreempt(
    ForegroundPreemptCache& cache,
    HWND targetHwnd,
    bool dryRun,
    bool firstObservation,
    bool eachAction,
    const std::wstring& reason,
    bool overlapChanged,
    bool foregroundChanged,
    ULONGLONG start) {
    ForegroundPreemptResult result = firstObservation
        ? prepare_before_first_observation(targetHwnd, dryRun)
        : prepare_before_each_action(targetHwnd, dryRun);
    LightweightForegroundState state = CaptureLightweightForegroundState(targetHwnd);
    StoreCache(cache, targetHwnd, state);
    result.foregroundPreemptMode = L"full";
    result.foregroundPreemptReason = reason;
    result.agentHostOverlapChanged = overlapChanged;
    result.targetForegroundChanged = foregroundChanged;
    result.durationMs = Elapsed(start);
    if (result.preparation.durationMs <= 0) {
        result.preparation.durationMs = result.durationMs;
    }
    return result;
}

ForegroundPreemptResult OkDryRun(bool firstObservation, bool eachAction) {
    ForegroundPreemptResult result;
    result.ok = true;
    result.preemptRun = true;
    result.beforeFirstObservation = firstObservation;
    result.beforeEachAction = eachAction;
    result.agentHostNotCoveringTarget = true;
    result.dryRun = true;
    result.foregroundPreemptMode = L"full";
    result.foregroundPreemptReason = firstObservation ? L"first_observation" : L"before_each_action";
    return result;
}

ForegroundPreemptResult FromPreparation(const ForegroundPreparationResult& prep, bool firstObservation, bool eachAction) {
    ForegroundPreemptResult result;
    result.ok = prep.ok;
    result.errorCode = prep.errorCode;
    result.errorMessage = prep.errorMessage;
    result.preemptRun = prep.attempted;
    result.beforeFirstObservation = firstObservation;
    result.beforeEachAction = eachAction;
    result.agentHostNotCoveringTarget = !prep.agentHostOverlappedTarget || prep.cliMinimizeSucceeded || prep.moveAwaySucceeded || prep.targetForegroundAfter;
    result.preparation = prep;
    result.foregroundPreemptMode = L"full";
    result.foregroundPreemptReason = firstObservation ? L"first_observation" : L"before_each_action";
    result.durationMs = prep.durationMs;
    if (!result.ok && result.errorCode.empty()) {
        result.errorCode = L"BLOCKED_AGENT_HOST_OBSTRUCTING_TARGET";
    }
    if (!result.ok && result.errorMessage.empty()) {
        result.errorMessage = L"Foreground preempt could not clear the agent host from the target.";
    }
    return result;
}

}  // namespace

ForegroundPreemptResult detect_agent_host_windows() {
    return prepare_before_first_observation(nullptr, true);
}

ForegroundPreemptResult detect_agent_host_overlap_with_target(HWND targetHwnd) {
    return prepare_before_first_observation(targetHwnd, true);
}

ForegroundPreemptResult minimize_agent_host_windows(HWND targetHwnd) {
    return prepare_before_first_observation(targetHwnd, false);
}

ForegroundPreemptResult move_agent_host_windows_away(HWND targetHwnd) {
    return prepare_before_first_observation(targetHwnd, false);
}

ForegroundPreemptResult activate_target_window(HWND targetHwnd) {
    return prepare_before_each_action(targetHwnd, false);
}

ForegroundPreemptResult prepare_before_first_observation(HWND targetHwnd, bool dryRun) {
    if (dryRun) {
        return OkDryRun(true, false);
    }
    return FromPreparation(PrepareForegroundForVisibleUiTask(targetHwnd), true, false);
}

ForegroundPreemptResult prepare_before_each_action(HWND targetHwnd, bool dryRun) {
    if (dryRun) {
        return OkDryRun(false, true);
    }
    return FromPreparation(PrepareForegroundForVisibleUiTask(targetHwnd), false, true);
}

ForegroundPreemptResult prepare_before_first_observation_cached(ForegroundPreemptCache& cache, HWND targetHwnd, bool dryRun) {
    ULONGLONG start = GetTickCount64();
    LightweightForegroundState state = CaptureLightweightForegroundState(targetHwnd);
    if (!cache.hasSnapshot) {
        return RunFullPreempt(cache, targetHwnd, dryRun, true, false, L"first_observation", false, false, start);
    }
    bool sameTarget = cache.targetHwnd == targetHwnd;
    bool foregroundChanged = cache.foregroundHwnd != state.foreground;
    bool overlapChanged = cache.agentHostOverlappedTarget != state.agentHostOverlappedTarget;
    if (sameTarget && !foregroundChanged && !overlapChanged) {
        return CachedOk(true, false, state, L"cached_validation", L"target_foreground_and_overlap_unchanged", Elapsed(start));
    }
    std::wstring reason = !sameTarget ? L"target_hwnd_changed" : (foregroundChanged ? L"foreground_changed" : L"agent_host_overlap_changed");
    return RunFullPreempt(cache, targetHwnd, dryRun, true, false, reason, overlapChanged, foregroundChanged, start);
}

ForegroundPreemptResult prepare_before_each_action_cached(ForegroundPreemptCache& cache, HWND targetHwnd, bool dryRun) {
    ULONGLONG start = GetTickCount64();
    LightweightForegroundState state = CaptureLightweightForegroundState(targetHwnd);
    if (!cache.hasSnapshot) {
        return RunFullPreempt(cache, targetHwnd, dryRun, false, true, L"cache_empty_before_action", false, false, start);
    }
    bool sameTarget = cache.targetHwnd == targetHwnd;
    bool foregroundChanged = cache.foregroundHwnd != state.foreground;
    bool overlapChanged = cache.agentHostOverlappedTarget != state.agentHostOverlappedTarget;
    if (sameTarget && !foregroundChanged && !overlapChanged) {
        ForegroundPreemptResult result = CachedOk(false, true, state, L"cached_validation", L"target_foreground_and_overlap_unchanged", Elapsed(start));
        result.agentHostOverlapChanged = false;
        result.targetForegroundChanged = false;
        return result;
    }
    std::wstring reason = !sameTarget ? L"target_hwnd_changed" : (foregroundChanged ? L"foreground_changed" : L"agent_host_overlap_changed");
    return RunFullPreempt(cache, targetHwnd, dryRun, false, true, reason, overlapChanged, foregroundChanged, start);
}

bool verify_agent_host_not_covering_target(const ForegroundPreemptResult& result) {
    return result.ok && result.preemptRun && result.agentHostNotCoveringTarget;
}

std::wstring ForegroundPreemptJson(const ForegroundPreemptResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"preempt_run\":" + simplejson::Bool(result.preemptRun);
    json += L",\"before_first_observation\":" + simplejson::Bool(result.beforeFirstObservation);
    json += L",\"before_each_action\":" + simplejson::Bool(result.beforeEachAction);
    json += L",\"agent_host_not_covering_target\":" + simplejson::Bool(result.agentHostNotCoveringTarget);
    json += L",\"dry_run\":" + simplejson::Bool(result.dryRun);
    json += L",\"foreground_preempt_mode\":" + simplejson::Quote(result.foregroundPreemptMode);
    json += L",\"foreground_preempt_reason\":" + simplejson::Quote(result.foregroundPreemptReason);
    json += L",\"agent_host_overlap_changed\":" + simplejson::Bool(result.agentHostOverlapChanged);
    json += L",\"target_foreground_changed\":" + simplejson::Bool(result.targetForegroundChanged);
    json += L",\"duration_ms\":" + std::to_wstring(result.durationMs);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"preparation\":" + ForegroundPreparationJson(result.preparation);
    json += L"}";
    return json;
}
