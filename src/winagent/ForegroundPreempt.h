#pragma once

#include "ForegroundPreparation.h"

#include <windows.h>

#include <string>
#include <vector>

struct ForegroundPreemptResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool preemptRun = false;
    bool beforeFirstObservation = false;
    bool beforeEachAction = false;
    bool agentHostNotCoveringTarget = false;
    bool dryRun = false;
    ForegroundPreparationResult preparation;
    std::wstring foregroundPreemptMode;
    std::wstring foregroundPreemptReason;
    bool agentHostOverlapChanged = false;
    bool targetForegroundChanged = false;
    long long durationMs = 0;
};

struct ForegroundPreemptCache {
    bool hasSnapshot = false;
    HWND targetHwnd = nullptr;
    HWND foregroundHwnd = nullptr;
    bool agentHostOverlappedTarget = false;
    bool agentHostDetected = false;
    RECT targetRect = {};
};

ForegroundPreemptResult detect_agent_host_windows();
ForegroundPreemptResult detect_agent_host_overlap_with_target(HWND targetHwnd);
ForegroundPreemptResult minimize_agent_host_windows(HWND targetHwnd);
ForegroundPreemptResult move_agent_host_windows_away(HWND targetHwnd);
ForegroundPreemptResult activate_target_window(HWND targetHwnd);
ForegroundPreemptResult prepare_before_first_observation(HWND targetHwnd, bool dryRun = false);
ForegroundPreemptResult prepare_before_each_action(HWND targetHwnd, bool dryRun = false);
ForegroundPreemptResult prepare_before_first_observation_cached(ForegroundPreemptCache& cache, HWND targetHwnd, bool dryRun = false);
ForegroundPreemptResult prepare_before_each_action_cached(ForegroundPreemptCache& cache, HWND targetHwnd, bool dryRun = false);
bool verify_agent_host_not_covering_target(const ForegroundPreemptResult& result);
std::wstring ForegroundPreemptJson(const ForegroundPreemptResult& result);
