#include "ForegroundPreparation.h"

#include "SafetyPolicy.h"
#include "Trace.h"

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

bool ContainsInsensitive(const std::wstring& value, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLower(value).find(ToLower(needle)) != std::wstring::npos;
}

std::wstring WindowTitle(HWND hwnd) {
    int length = GetWindowTextLengthW(hwnd);
    if (length <= 0) return L"";
    std::wstring title(static_cast<size_t>(length) + 1, L'\0');
    int copied = GetWindowTextW(hwnd, title.data(), length + 1);
    title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    return title;
}

bool WindowInfoFromAnyHwnd(HWND hwnd, WindowInfo& info) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    info.hwnd = hwnd;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    info.title = WindowTitle(hwnd);
    return true;
}

bool RectValid(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

bool RectsIntersect(const RECT& a, const RECT& b) {
    return RectValid(a) && RectValid(b) &&
           a.left < b.right && a.right > b.left &&
           a.top < b.bottom && a.bottom > b.top;
}

RECT VirtualDesktopRect() {
    RECT rect{
        GetSystemMetrics(SM_XVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN),
        GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    return rect;
}

bool IntersectsVirtualDesktop(const RECT& rect) {
    return RectsIntersect(rect, VirtualDesktopRect());
}

bool IsAgentHostClass(HWND hwnd) {
    wchar_t className[256] = {};
    if (GetClassNameW(hwnd, className, 256) <= 0) {
        return false;
    }
    std::wstring cls = ToLower(className);
    return cls.find(L"consolewindowclass") != std::wstring::npos ||
           cls.find(L"cascadia_hosting_window_class") != std::wstring::npos ||
           cls.find(L"virtualconsoleclass") != std::wstring::npos;
}

bool IsAgentHostText(const std::wstring& title, const std::wstring& processName) {
    const std::wstring haystack = ToLower(title + L" " + processName);
    const wchar_t* needles[] = {
        L"windows terminal",
        L"powershell",
        L"pwsh",
        L"cmd.exe",
        L"command prompt",
        L"openai codex",
        L"codex",
        L"terminal",
        L"conhost",
        L"openconsole",
        L"wt.exe"};
    for (const wchar_t* needle : needles) {
        if (haystack.find(needle) != std::wstring::npos) return true;
    }
    return false;
}

bool IsTargetVisible(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd) || !IsWindowVisible(hwnd) || IsIconic(hwnd)) {
        return false;
    }
    RECT rect = {};
    if (!GetWindowRect(hwnd, &rect)) return false;
    return IntersectsVirtualDesktop(rect);
}

bool ShowAndActivate(HWND hwnd, int timeoutMs, HWND& foregroundBefore, HWND& foregroundAfter) {
    foregroundBefore = GetForegroundWindow();
    if (!hwnd || !IsWindow(hwnd)) {
        foregroundAfter = foregroundBefore;
        return false;
    }

    if (IsIconic(hwnd)) {
        ShowWindow(hwnd, SW_RESTORE);
    } else {
        ShowWindow(hwnd, SW_SHOW);
    }

    DWORD targetThread = GetWindowThreadProcessId(hwnd, nullptr);
    DWORD currentThread = GetCurrentThreadId();
    HWND foreground = GetForegroundWindow();
    DWORD foregroundThread = foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
    bool attachedTarget = targetThread && targetThread != currentThread && AttachThreadInput(currentThread, targetThread, TRUE);
    bool attachedForeground = foregroundThread && foregroundThread != currentThread && foregroundThread != targetThread && AttachThreadInput(currentThread, foregroundThread, TRUE);

    BringWindowToTop(hwnd);
    SetActiveWindow(hwnd);
    SetForegroundWindow(hwnd);

    ULONGLONG start = GetTickCount64();
    int waitMs = timeoutMs <= 0 ? 1500 : timeoutMs;
    do {
        foregroundAfter = GetForegroundWindow();
        if (foregroundAfter == hwnd) break;
        BringWindowToTop(hwnd);
        SetForegroundWindow(hwnd);
        Sleep(30);
    } while (GetTickCount64() - start < static_cast<ULONGLONG>(waitMs));

    if (attachedForeground) AttachThreadInput(currentThread, foregroundThread, FALSE);
    if (attachedTarget) AttachThreadInput(currentThread, targetThread, FALSE);

    foregroundAfter = GetForegroundWindow();
    return foregroundAfter == hwnd;
}

std::wstring HwndOrNull(HWND hwnd) {
    return hwnd ? JsonString(FormatHwnd(hwnd)) : L"null";
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

}  // namespace

bool DetectAgentHostWindow(HWND hwnd, WindowInfo& info) {
    if (!WindowInfoFromAnyHwnd(hwnd, info)) return false;
    std::wstring processName = ProcessNameForPid(info.pid);
    return IsAgentHostText(info.title, processName) || IsAgentHostClass(hwnd);
}

bool MinimizeAgentHostWindow(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    ShowWindow(hwnd, SW_MINIMIZE);
    Sleep(80);
    return IsIconic(hwnd) || GetForegroundWindow() != hwnd;
}

bool MoveAgentHostWindowToCorner(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    RECT current = {};
    GetWindowRect(hwnd, &current);
    int width = current.right > current.left ? current.right - current.left : 520;
    int height = current.bottom > current.top ? current.bottom - current.top : 260;
    if (width > 560) width = 560;
    if (height > 320) height = 320;
    RECT work = {};
    if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
        work = VirtualDesktopRect();
    }
    int x = work.right - width - 8;
    int y = work.bottom - height - 8;
    if (x < work.left) x = work.left;
    if (y < work.top) y = work.top;
    BOOL moved = SetWindowPos(hwnd, HWND_BOTTOM, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    Sleep(60);
    return moved != FALSE;
}

bool RestoreAgentHostWindowIfNeeded(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    if (IsIconic(hwnd)) {
        ShowWindow(hwnd, SW_RESTORE);
        Sleep(80);
    }
    return IsWindowVisible(hwnd) != FALSE;
}

bool VerifyTargetWindowVisible(HWND hwnd) {
    return IsTargetVisible(hwnd);
}

bool ActivateWindowForeground(HWND hwnd, int timeoutMs, HWND& foregroundBefore, HWND& foregroundAfter) {
    return ShowAndActivate(hwnd, timeoutMs, foregroundBefore, foregroundAfter);
}

ForegroundPreparationResult PrepareForegroundForVisibleUiTask(HWND targetHwnd, int timeoutMs) {
    ULONGLONG start = GetTickCount64();
    ForegroundPreparationResult result;
    result.attempted = true;
    result.targetHwnd = targetHwnd;
    result.targetProvided = targetHwnd != nullptr;
    result.foregroundBefore = GetForegroundWindow();

    WindowInfo target;
    if (targetHwnd && WindowInfoFromAnyHwnd(targetHwnd, target)) {
        result.targetWindowTitle = target.title;
        result.targetProcessName = ProcessNameForPid(target.pid);
        result.targetVisibleBefore = VerifyTargetWindowVisible(targetHwnd);
    }

    WindowInfo host;
    if (DetectAgentHostWindow(result.foregroundBefore, host)) {
        result.agentHostDetected = true;
        result.agentHostWasForeground = true;
        result.agentHostHwnd = host.hwnd;
        result.agentHostTitle = host.title;
        result.agentHostProcessName = ProcessNameForPid(host.pid);
        result.agentHostOverlappedTarget = !targetHwnd || (targetHwnd != host.hwnd && RectsIntersect(host.rect, target.rect));
    }

    if (result.agentHostWasForeground && (!targetHwnd || targetHwnd != result.agentHostHwnd) && result.agentHostOverlappedTarget) {
        result.cliMinimizeAttempted = true;
        result.cliMinimizeSucceeded = MinimizeAgentHostWindow(result.agentHostHwnd);
        result.cliMinimizeFailed = !result.cliMinimizeSucceeded;
        if (!result.cliMinimizeSucceeded) {
            result.moveAwayAttempted = true;
            result.moveAwaySucceeded = MoveAgentHostWindowToCorner(result.agentHostHwnd);
            result.fallbackMoveAwayOrFocusTarget = true;
            result.fallback = result.moveAwaySucceeded ? L"move_away_or_focus_target" : L"focus_target";
        }
    }

    if (targetHwnd) {
        HWND before = nullptr;
        HWND after = nullptr;
        bool activated = ActivateWindowForeground(targetHwnd, timeoutMs, before, after);
        (void)before;
        result.foregroundAfter = after;
        result.targetForegroundAfter = activated && after == targetHwnd;
        result.targetVisibleAfter = VerifyTargetWindowVisible(targetHwnd);
        if (!result.targetForegroundAfter) {
            result.ok = false;
            result.errorCode = L"WINDOW_FOCUS_FAILED";
            result.errorMessage = L"Target window was not foreground after foreground preparation.";
        } else if (!result.targetVisibleAfter) {
            result.ok = false;
            result.errorCode = L"WINDOW_NOT_VISIBLE";
            result.errorMessage = L"Target window was not visible after foreground preparation.";
        } else {
            result.ok = true;
        }
    } else {
        result.foregroundAfter = GetForegroundWindow();
        result.ok = true;
    }

    result.backendFallbackUsed = false;
    result.durationMs = ElapsedMs(start);
    return result;
}

ForegroundPreparationResult PrepareForegroundForVisibleUiTask(const WindowInfo& target, int timeoutMs) {
    return PrepareForegroundForVisibleUiTask(target.hwnd, timeoutMs);
}

std::wstring ForegroundPreparationJson(const ForegroundPreparationResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << BoolJson(result.ok)
         << L",\"attempted\":" << BoolJson(result.attempted)
         << L",\"target_provided\":" << BoolJson(result.targetProvided)
         << L",\"target_hwnd\":" << HwndOrNull(result.targetHwnd)
         << L",\"target_window_title\":" << JsonString(result.targetWindowTitle)
         << L",\"target_process_name\":" << JsonString(result.targetProcessName)
         << L",\"target_visible_before\":" << BoolJson(result.targetVisibleBefore)
         << L",\"target_visible_after\":" << BoolJson(result.targetVisibleAfter)
         << L",\"target_foreground_after\":" << BoolJson(result.targetForegroundAfter)
         << L",\"foreground_before\":" << HwndOrNull(result.foregroundBefore)
         << L",\"foreground_after\":" << HwndOrNull(result.foregroundAfter)
         << L",\"agent_host_detected\":" << BoolJson(result.agentHostDetected)
         << L",\"agent_host_was_foreground\":" << BoolJson(result.agentHostWasForeground)
         << L",\"agent_host_hwnd\":" << HwndOrNull(result.agentHostHwnd)
         << L",\"agent_host_title\":" << JsonString(result.agentHostTitle)
         << L",\"agent_host_process_name\":" << JsonString(result.agentHostProcessName)
         << L",\"agent_host_overlapped_target\":" << BoolJson(result.agentHostOverlappedTarget)
         << L",\"cli_minimize_attempted\":" << BoolJson(result.cliMinimizeAttempted)
         << L",\"cli_minimize_succeeded\":" << BoolJson(result.cliMinimizeSucceeded)
         << L",\"cli_minimize_failed\":" << BoolJson(result.cliMinimizeFailed)
         << L",\"move_away_attempted\":" << BoolJson(result.moveAwayAttempted)
         << L",\"move_away_succeeded\":" << BoolJson(result.moveAwaySucceeded)
         << L",\"fallback_move_away_or_focus_target\":" << BoolJson(result.fallbackMoveAwayOrFocusTarget)
         << L",\"fallback\":" << JsonString(result.fallback)
         << L",\"backend_fallback_used\":" << BoolJson(result.backendFallbackUsed)
         << L",\"duration_ms\":" << result.durationMs;
    if (!result.errorCode.empty()) {
        json << L",\"error\":{\"code\":" << JsonString(result.errorCode)
             << L",\"message\":" << JsonString(result.errorMessage) << L"}";
    }
    json << L"}";
    return json.str();
}
