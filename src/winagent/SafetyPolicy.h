#pragma once

#include "WindowFinder.h"

#include <string>
#include <vector>

struct SafetyPolicy {
    bool loaded = false;
    std::wstring configPath;
    std::vector<std::wstring> allowedTitles;
    std::vector<std::wstring> allowedProcesses;
    std::vector<std::wstring> allowedReadRoots;
    std::vector<std::wstring> allowedWriteRoots;
    int maxSteps = 100;
    int maxDurationMs = 120000;
    int emergencyStopVk = 0x7B;  // F12
    std::wstring emergencyStopKey = L"F12";
    bool allowAbsoluteScreenClick = false;
    std::vector<std::wstring> warnings;
};

struct SafetyCheckResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring message;
    std::wstring warning;
    std::wstring processName;
};

SafetyPolicy LoadSafetyPolicy();
SafetyCheckResult CheckWindowSafety(const WindowInfo& window, const std::wstring& requestedTitle);
std::wstring ProcessNameForPid(DWORD pid);
bool IsReadPathAllowed(const std::wstring& path, std::wstring& normalizedPath, std::wstring& errorMessage);
bool IsWritePathAllowed(const std::wstring& path, std::wstring& normalizedPath, std::wstring& errorMessage);
bool IsEmergencyStopPressed();
std::wstring SafetyPolicySummaryJson(const SafetyPolicy& policy);
