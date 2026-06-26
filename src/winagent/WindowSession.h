#pragma once

#include "WindowFinder.h"

#include <string>
#include <vector>

struct MonitorSessionInfo {
    std::wstring deviceName;
    RECT rect = {};
    RECT workRect = {};
    bool primary = false;
};

struct WindowSessionInfo {
    std::wstring requestedTitle;
    std::wstring requestedProcess;
    WindowInfo window;
    std::wstring processName;
    bool visible = false;
    bool iconic = false;
    bool foreground = false;
    bool foregroundControllable = false;
    UINT dpi = 0;
    MonitorSessionInfo monitor;
};

struct WindowSessionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    WindowSessionInfo session;
    std::vector<WindowSessionInfo> candidates;
};

WindowSessionResult ResolveWindowSession(const std::wstring& requestedTitle, const std::wstring& requestedProcess = L"");
WindowSessionResult ReconfirmWindowSession(const WindowSessionInfo& previous);
std::wstring WindowSessionJson(const WindowSessionInfo& session);
std::wstring WindowSessionCandidateJson(const std::vector<WindowSessionInfo>& candidates);
