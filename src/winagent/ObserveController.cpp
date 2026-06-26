#include "ObserveController.h"

#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Screenshot.h"
#include "Trace.h"
#include "UiaController.h"
#include "WindowSession.h"

#include <windows.h>

#include <sstream>
#include <vector>

namespace {

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring WindowJson(const WindowInfo& window) {
    std::wstringstream json;
    json << L"{\"title\":" << JsonString(window.title)
         << L",\"hwnd\":" << JsonString(FormatHwnd(window.hwnd))
         << L",\"pid\":" << window.pid
         << L",\"process_name\":" << JsonString(ProcessNameForPid(window.pid))
         << L",\"rect\":" << RectJson(window.rect)
         << L"}";
    return json.str();
}

bool ActiveWindowInfo(WindowInfo& info) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) {
        return false;
    }
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        if (window.hwnd == hwnd) {
            info = window;
            return true;
        }
    }
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
    return true;
}

std::wstring ObserveScreenshotPath() {
    SYSTEMTIME time = {};
    GetLocalTime(&time);
    wchar_t buffer[128] = {};
    swprintf_s(
        buffer,
        L"observe_%04u%02u%02u_%02u%02u%02u_%03u.bmp",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds);
    return ArtifactsPath(buffer);
}

std::wstring WarningArrayJson(const std::vector<std::wstring>& warnings) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < warnings.size(); ++i) {
        if (i != 0) {
            json << L",";
        }
        json << JsonString(warnings[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring UiaElementJson(int index, const UiaElementInfo& element) {
    std::wstringstream json;
    json << L"{\"index\":" << index
         << L",\"name\":" << JsonString(element.name)
         << L",\"value\":" << JsonString(element.value)
         << L",\"control_type\":" << JsonString(element.controlType)
         << L",\"rect\":" << RectJson(element.rect)
         << L",\"enabled\":" << (element.enabled ? L"true" : L"false")
         << L",\"offscreen\":" << (element.offscreen ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring UiaJson(const UiaQueryResult& uia, int maxElements, int& returnedCount) {
    returnedCount = 0;
    std::wstringstream json;
    json << L"{\"available\":" << (uia.ok ? L"true" : L"false")
         << L",\"element_count\":";
    if (!uia.ok) {
        json << L"0,\"elements\":[]}";
        return json.str();
    }

    int limit = maxElements < 0 ? 0 : maxElements;
    int count = static_cast<int>(uia.elements.size());
    int toWrite = count < limit ? count : limit;
    returnedCount = toWrite;
    json << toWrite << L",\"elements\":[";
    for (int i = 0; i < toWrite; ++i) {
        if (i != 0) {
            json << L",";
        }
        json << UiaElementJson(i, uia.elements[static_cast<size_t>(i)]);
    }
    json << L"]}";
    return json.str();
}

}  // namespace

ObserveResult ObserveWindow(const std::wstring& title, bool includeScreenshot, bool includeUia, int maxElements, const std::wstring& process) {
    ObserveResult result;
    if (title.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"observe requires --title.";
        return result;
    }

    WindowSessionResult sessionResult = ResolveWindowSession(title, process);
    if (!sessionResult.ok) {
        result.errorCode = sessionResult.errorCode;
        result.errorMessage = sessionResult.errorMessage;
        result.dataJson = sessionResult.dataJson;
        return result;
    }
    result.target = sessionResult.session.window;
    result.focusVerified = GetForegroundWindow() == result.target.hwnd;

    std::vector<std::wstring> warnings;
    POINT mouse = {};
    bool hasMouse = GetCursorPos(&mouse) != FALSE;
    if (!hasMouse) {
        warnings.push_back(L"GetCursorPos failed.");
    }

    WindowInfo active;
    bool hasActive = ActiveWindowInfo(active);
    if (!hasActive) {
        warnings.push_back(L"GetForegroundWindow failed.");
    }

    std::wstring screenshotJson = L"{\"path\":\"\",\"method\":\"none\"}";
    if (includeScreenshot) {
        result.screenshotPath = ObserveScreenshotPath();
        ScreenshotResult shot = CaptureWindowToBmp(result.target.hwnd, result.screenshotPath);
        if (shot.ok) {
            result.screenshotMethod = shot.method;
            screenshotJson = L"{\"path\":" + JsonString(result.screenshotPath)
                + L",\"method\":" + JsonString(shot.method) + L"}";
        } else {
            result.screenshotMethod = L"none";
            warnings.push_back(L"Screenshot failed: " + shot.error);
            screenshotJson = L"{\"path\":" + JsonString(result.screenshotPath)
                + L",\"method\":\"none\"}";
        }
    }

    std::wstring uiaJson = L"{\"available\":false,\"element_count\":0,\"elements\":[]}";
    if (includeUia) {
        UiaQueryResult uia = ReadUiaTree(result.target.hwnd);
        if (!uia.ok) {
            warnings.push_back(L"UIA failed: " + (uia.errorCode.empty() ? uia.errorMessage : uia.errorCode + L" " + uia.errorMessage));
        }
        uiaJson = UiaJson(uia, maxElements, result.uiaElementCount);
    }

    SafetyPolicy policy = LoadSafetyPolicy();
    std::wstring activeJson = hasActive ? WindowJson(active) : L"null";
    std::wstring mouseJson = hasMouse
        ? (L"{\"screen_x\":" + std::to_wstring(mouse.x) + L",\"screen_y\":" + std::to_wstring(mouse.y) + L"}")
        : L"{\"screen_x\":null,\"screen_y\":null}";

    std::wstringstream data;
    data << L"{\"target_window\":" << WindowJson(result.target)
         << L",\"window_session\":" << WindowSessionJson(sessionResult.session)
         << L",\"active_window\":" << activeJson
         << L",\"focus_verified\":" << (result.focusVerified ? L"true" : L"false")
         << L",\"mouse\":" << mouseJson
         << L",\"screenshot\":" << screenshotJson
         << L",\"uia\":" << uiaJson
         << L",\"safety\":" << SafetyPolicySummaryJson(policy)
         << L",\"warnings\":" << WarningArrayJson(warnings)
         << L"}";

    result.ok = true;
    result.dataJson = data.str();
    return result;
}
