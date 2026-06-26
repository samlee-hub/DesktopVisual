#pragma once

#include "WindowFinder.h"

#include <windows.h>

#include <string>

struct ForegroundPreparationResult {
    bool ok = false;
    bool attempted = false;
    bool targetProvided = false;
    HWND targetHwnd = nullptr;
    std::wstring targetWindowTitle;
    std::wstring targetProcessName;
    bool targetVisibleBefore = false;
    bool targetVisibleAfter = false;
    bool targetForegroundAfter = false;
    HWND foregroundBefore = nullptr;
    HWND foregroundAfter = nullptr;
    bool agentHostDetected = false;
    bool agentHostWasForeground = false;
    HWND agentHostHwnd = nullptr;
    std::wstring agentHostTitle;
    std::wstring agentHostProcessName;
    bool agentHostOverlappedTarget = false;
    bool cliMinimizeAttempted = false;
    bool cliMinimizeSucceeded = false;
    bool cliMinimizeFailed = false;
    bool moveAwayAttempted = false;
    bool moveAwaySucceeded = false;
    bool fallbackMoveAwayOrFocusTarget = false;
    bool backendFallbackUsed = false;
    std::wstring fallback;
    std::wstring errorCode;
    std::wstring errorMessage;
    long long durationMs = 0;
};

bool DetectAgentHostWindow(HWND hwnd, WindowInfo& info);
bool MinimizeAgentHostWindow(HWND hwnd);
bool MoveAgentHostWindowToCorner(HWND hwnd);
bool RestoreAgentHostWindowIfNeeded(HWND hwnd);
bool VerifyTargetWindowVisible(HWND hwnd);
bool ActivateWindowForeground(HWND hwnd, int timeoutMs, HWND& foregroundBefore, HWND& foregroundAfter);

ForegroundPreparationResult PrepareForegroundForVisibleUiTask(HWND targetHwnd, int timeoutMs = 1500);
ForegroundPreparationResult PrepareForegroundForVisibleUiTask(const WindowInfo& target, int timeoutMs = 1500);
std::wstring ForegroundPreparationJson(const ForegroundPreparationResult& result);
