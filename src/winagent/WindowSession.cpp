#include "WindowSession.h"

#include "SafetyPolicy.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) {
        return false;
    }
    return ToLower(haystack).find(ToLower(needle)) != std::wstring::npos;
}

bool EqualsInsensitive(const std::wstring& left, const std::wstring& right) {
    return ToLower(left) == ToLower(right);
}

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

WindowInfo WindowInfoFromHwnd(HWND hwnd) {
    WindowInfo info;
    info.hwnd = hwnd;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);

    int length = GetWindowTextLengthW(hwnd);
    if (length > 0) {
        std::wstring title(static_cast<size_t>(length) + 1, L'\0');
        int copied = GetWindowTextW(hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
        info.title = title;
    }
    return info;
}

MonitorSessionInfo ReadMonitorInfo(HWND hwnd) {
    MonitorSessionInfo monitor;
    HMONITOR handle = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (!handle) {
        return monitor;
    }

    MONITORINFOEXW mi = {};
    mi.cbSize = sizeof(mi);
    if (GetMonitorInfoW(handle, &mi)) {
        monitor.deviceName = mi.szDevice;
        monitor.rect = mi.rcMonitor;
        monitor.workRect = mi.rcWork;
        monitor.primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
    }
    return monitor;
}

UINT ReadWindowDpi(HWND hwnd) {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32) {
        using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
        auto getDpiForWindow = reinterpret_cast<GetDpiForWindowFn>(GetProcAddress(user32, "GetDpiForWindow"));
        if (getDpiForWindow) {
            UINT dpi = getDpiForWindow(hwnd);
            if (dpi > 0) {
                return dpi;
            }
        }
    }

    HWND dcHwnd = hwnd;
    HDC dc = GetDC(dcHwnd);
    if (!dc) {
        dcHwnd = nullptr;
        dc = GetDC(dcHwnd);
    }
    UINT dpi = 96;
    if (dc) {
        int value = GetDeviceCaps(dc, LOGPIXELSX);
        if (value > 0) {
            dpi = static_cast<UINT>(value);
        }
        ReleaseDC(dcHwnd, dc);
    }
    return dpi;
}

WindowSessionInfo BuildSession(const WindowInfo& window, const std::wstring& requestedTitle, const std::wstring& requestedProcess) {
    WindowSessionInfo session;
    session.requestedTitle = requestedTitle;
    session.requestedProcess = requestedProcess;
    session.window = window;
    session.processName = ProcessNameForPid(window.pid);
    session.visible = IsWindow(window.hwnd) && IsWindowVisible(window.hwnd);
    session.iconic = IsWindow(window.hwnd) && IsIconic(window.hwnd);
    session.foreground = GetForegroundWindow() == window.hwnd;
    session.foregroundControllable = IsWindow(window.hwnd) && session.visible;
    session.dpi = ReadWindowDpi(window.hwnd);
    session.monitor = ReadMonitorInfo(window.hwnd);
    return session;
}

std::wstring FailureData(const std::wstring& title, const std::wstring& process, const std::vector<WindowSessionInfo>& candidates) {
    std::wstringstream data;
    data << L"{\"requested_title\":" << JsonString(title)
         << L",\"requested_process\":" << JsonString(process)
         << L",\"candidates\":" << WindowSessionCandidateJson(candidates)
         << L"}";
    return data.str();
}

}  // namespace

std::wstring WindowSessionCandidateJson(const std::vector<WindowSessionInfo>& candidates) {
    std::wstringstream data;
    data << L"[";
    for (size_t i = 0; i < candidates.size(); ++i) {
        if (i != 0) {
            data << L",";
        }
        const auto& session = candidates[i];
        data << L"{\"title\":" << JsonString(session.window.title)
             << L",\"hwnd\":" << JsonString(FormatHwnd(session.window.hwnd))
             << L",\"pid\":" << session.window.pid
             << L",\"process_name\":" << JsonString(session.processName)
             << L",\"rect\":" << RectJson(session.window.rect)
             << L"}";
    }
    data << L"]";
    return data.str();
}

std::wstring WindowSessionJson(const WindowSessionInfo& session) {
    std::wstringstream json;
    json << L"{\"requested_title\":" << JsonString(session.requestedTitle)
         << L",\"requested_process\":" << JsonString(session.requestedProcess)
         << L",\"title\":" << JsonString(session.window.title)
         << L",\"hwnd\":" << JsonString(FormatHwnd(session.window.hwnd))
         << L",\"pid\":" << session.window.pid
         << L",\"process_name\":" << JsonString(session.processName)
         << L",\"rect\":" << RectJson(session.window.rect)
         << L",\"visible\":" << (session.visible ? L"true" : L"false")
         << L",\"iconic\":" << (session.iconic ? L"true" : L"false")
         << L",\"foreground\":{\"is_foreground\":" << (session.foreground ? L"true" : L"false")
         << L",\"foreground_controllable\":" << (session.foregroundControllable ? L"true" : L"false")
         << L"}"
         << L",\"dpi\":" << session.dpi
         << L",\"monitor\":{\"device_name\":" << JsonString(session.monitor.deviceName)
         << L",\"primary\":" << (session.monitor.primary ? L"true" : L"false")
         << L",\"rect\":" << RectJson(session.monitor.rect)
         << L",\"work_rect\":" << RectJson(session.monitor.workRect)
         << L"}}";
    return json.str();
}

WindowSessionResult ResolveWindowSession(const std::wstring& requestedTitle, const std::wstring& requestedProcess) {
    WindowSessionResult result;
    if (requestedTitle.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"--title is required.";
        result.dataJson = FailureData(requestedTitle, requestedProcess, {});
        return result;
    }

    std::vector<WindowSessionInfo> titleMatches;
    for (const auto& window : FindWindowsByTitleSubstring(requestedTitle)) {
        titleMatches.push_back(BuildSession(window, requestedTitle, requestedProcess));
    }

    if (titleMatches.empty()) {
        result.errorCode = L"WINDOW_NOT_FOUND";
        result.errorMessage = L"Target window was not found.";
        result.dataJson = FailureData(requestedTitle, requestedProcess, {});
        return result;
    }

    std::vector<WindowSessionInfo> matches;
    for (const auto& session : titleMatches) {
        if (requestedProcess.empty() || EqualsInsensitive(session.processName, requestedProcess)) {
            matches.push_back(session);
        }
    }

    if (matches.empty()) {
        result.errorCode = L"WINDOW_NOT_FOUND";
        result.errorMessage = L"Target window was not found for the requested process.";
        result.candidates = titleMatches;
        result.dataJson = FailureData(requestedTitle, requestedProcess, titleMatches);
        return result;
    }
    if (matches.size() > 1) {
        result.errorCode = L"WINDOW_NOT_UNIQUE";
        result.errorMessage = L"Target window matched multiple visible windows.";
        result.candidates = matches;
        result.dataJson = FailureData(requestedTitle, requestedProcess, matches);
        return result;
    }

    result.ok = true;
    result.session = matches.front();
    result.dataJson = L"{\"window_session\":" + WindowSessionJson(result.session) + L"}";
    return result;
}

WindowSessionResult ReconfirmWindowSession(const WindowSessionInfo& previous) {
    if (previous.window.hwnd && IsWindow(previous.window.hwnd)) {
        WindowInfo current = WindowInfoFromHwnd(previous.window.hwnd);
        if (!ContainsInsensitive(current.title, previous.requestedTitle)) {
            WindowSessionResult result;
            result.errorCode = L"WINDOW_TITLE_CHANGED";
            result.errorMessage = L"Target window title changed and no longer matches the requested title.";
            WindowSessionInfo changed = BuildSession(current, previous.requestedTitle, previous.requestedProcess);
            result.candidates.push_back(changed);
            result.dataJson = L"{\"requested_title\":" + JsonString(previous.requestedTitle)
                + L",\"requested_process\":" + JsonString(previous.requestedProcess)
                + L",\"previous_title\":" + JsonString(previous.window.title)
                + L",\"current_title\":" + JsonString(current.title)
                + L",\"window_session\":" + WindowSessionJson(changed) + L"}";
            return result;
        }
    }
    return ResolveWindowSession(previous.requestedTitle, previous.requestedProcess);
}
