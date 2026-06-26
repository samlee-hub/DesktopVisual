#include "BrowserSurfaceNormalizer.h"

#include "InputController.h"
#include "RuntimeContextGuard.h"
#include "SafetyPolicy.h"
#include "Trace.h"
#include "UiaController.h"
#include "WindowFinder.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool ActiveWindowInfo(WindowInfo& info) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return false;
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

bool ResolveBrowserWindow(const std::wstring& title, WindowInfo& selected) {
    if (!title.empty()) {
        std::vector<WindowInfo> matches = FindWindowsByTitleSubstring(title);
        for (const auto& candidate : matches) {
            std::wstring process = ToLowerInvariant(ProcessNameForPid(candidate.pid));
            if (process == L"chrome.exe" || process == L"msedge.exe") {
                selected = candidate;
                return true;
            }
        }
        if (!matches.empty()) {
            selected = matches.front();
            return true;
        }
        return false;
    }
    WindowInfo active;
    if (!ActiveWindowInfo(active)) return false;
    selected = active;
    return true;
}

std::wstring BrowserHaystack(HWND hwnd, const std::wstring& title, const std::wstring& process) {
    std::wstring text = L"title:" + title + L"\nprocess:" + process;
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (tree.ok) {
        for (const auto& element : tree.elements) {
            text += L"\n" + element.name + L" " + element.value + L" " + element.controlType + L" " + element.automationId + L" " + element.className;
        }
    }
    return text;
}

bool RectValid(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

long long RectArea(const RECT& rect) {
    if (!RectValid(rect)) return 0;
    return static_cast<long long>(rect.right - rect.left) * static_cast<long long>(rect.bottom - rect.top);
}

bool RectCenterInside(const RECT& child, const RECT& parent) {
    if (!RectValid(child) || !RectValid(parent)) return false;
    LONG x = child.left + (child.right - child.left) / 2;
    LONG y = child.top + (child.bottom - child.top) / 2;
    return x >= parent.left && x <= parent.right && y >= parent.top && y <= parent.bottom;
}

bool IsBrowserChromeElement(const UiaElementInfo& element) {
    return element.controlType == L"Tab" ||
           element.controlType == L"TabItem" ||
           element.controlType == L"ToolBar" ||
           element.controlType == L"TitleBar" ||
           element.controlType == L"MenuBar";
}

std::wstring BrowserPageHaystack(HWND hwnd, const std::wstring& title, const std::wstring& process) {
    std::wstring text = L"title:" + title + L"\nprocess:" + process;
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) return text;

    RECT documentRect = {};
    long long bestArea = 0;
    for (const auto& element : tree.elements) {
        if (element.controlType == L"Document" && !element.offscreen) {
            long long area = RectArea(element.rect);
            if (area > bestArea) {
                bestArea = area;
                documentRect = element.rect;
            }
        }
    }

    if (!RectValid(documentRect)) return text;

    for (const auto& element : tree.elements) {
        if (element.offscreen || IsBrowserChromeElement(element)) continue;
        if (element.controlType != L"Document" && !RectCenterInside(element.rect, documentRect)) continue;
        text += L"\n" + element.name + L" " + element.value + L" " + element.controlType + L" " + element.automationId + L" " + element.className;
    }
    return text;
}

bool HasActiveProtection(const std::wstring& text) {
    return ContainsInsensitive(text, L"captcha") ||
           ContainsInsensitive(text, L"recaptcha") ||
           ContainsInsensitive(text, L"hcaptcha") ||
           ContainsInsensitive(text, L"verify you are human") ||
           ContainsInsensitive(text, L"human verification") ||
           ContainsInsensitive(text, L"bot challenge") ||
           ContainsInsensitive(text, L"security verification") ||
           ContainsInsensitive(text, L"account risk") ||
           ContainsInsensitive(text, L"risk verification") ||
           ContainsInsensitive(text, L"login verification") ||
           ContainsInsensitive(text, L"password required");
}

bool HasAutomationDetection(const std::wstring& text) {
    return ContainsInsensitive(text, L"automation detected") ||
           ContainsInsensitive(text, L"bot detected") ||
           ContainsInsensitive(text, L"automated queries") ||
           ContainsInsensitive(text, L"suspicious traffic");
}

bool HasBrowserSurfaceBlocker(const std::wstring& text) {
    return ContainsInsensitive(text, L"omnibox suggestion") ||
           ContainsInsensitive(text, L"suggestions") ||
           ContainsInsensitive(text, L"search suggestions") ||
           ContainsInsensitive(text, L"translate") ||
           ContainsInsensitive(text, L"save password") ||
           ContainsInsensitive(text, L"password manager");
}

void Fail(BrowserSurfaceNormalizeResult& result, const std::wstring& code, const std::wstring& reason) {
    result.ok = false;
    result.stopCode = code;
    result.reason = reason;
}

}  // namespace

BrowserSurfaceNormalizeOptions ParseBrowserSurfaceNormalizeOptionsFromArgs(int argc, wchar_t** argv) {
    BrowserSurfaceNormalizeOptions options;
    ArgValue(argc, argv, L"--title", options.title);
    ArgValue(argc, argv, L"--mode", options.mode);
    if (options.mode.empty()) options.mode = L"conservative";
    ArgValue(argc, argv, L"--guard-result-json", options.guardResultJson);
    return options;
}

bool BrowserNormalizeBeforeActionRequested(int argc, wchar_t** argv) {
    std::wstring raw;
    if (!ArgValue(argc, argv, L"--browser-normalize-before-action", raw)) return false;
    return raw == L"true" || raw == L"1";
}

std::wstring BrowserNormalizeModeFromArgs(int argc, wchar_t** argv) {
    std::wstring mode;
    ArgValue(argc, argv, L"--browser-normalize-mode", mode);
    return mode.empty() ? L"conservative" : mode;
}

BrowserSurfaceNormalizeResult NormalizeBrowserSurface(const BrowserSurfaceNormalizeOptions& options) {
    BrowserSurfaceNormalizeResult result;
    WindowInfo selected;
    if (!ResolveBrowserWindow(options.title, selected)) {
        Fail(result, L"STOP_BROWSER_SURFACE_BLOCKING", L"No browser window was available for normalization.");
        if (!options.guardResultJson.empty()) WriteRuntimeGuardTextFile(options.guardResultJson, BrowserSurfaceNormalizeResultJson(result));
        return result;
    }
    result.hwnd = selected.hwnd;
    result.title = selected.title;
    result.process = ProcessNameForPid(selected.pid);
    std::wstring processLower = ToLowerInvariant(result.process);
    if (processLower != L"chrome.exe" && processLower != L"msedge.exe") {
        result.ok = true;
        result.reason = L"Target is not Chrome or Edge; no browser surface normalization needed.";
        if (!options.guardResultJson.empty()) {
            WriteRuntimeGuardTextFile(options.guardResultJson, BrowserSurfaceNormalizeResultJson(result));
        }
        return result;
    }

    std::wstring before = BrowserHaystack(selected.hwnd, selected.title, result.process);
    std::wstring beforePage = BrowserPageHaystack(selected.hwnd, selected.title, result.process);
    if (HasActiveProtection(beforePage)) {
        result.activeProtectionDetected = true;
        Fail(result, L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK", L"Login, captcha, or human-verification surface detected; normalization refused.");
        if (!options.guardResultJson.empty()) WriteRuntimeGuardTextFile(options.guardResultJson, BrowserSurfaceNormalizeResultJson(result));
        return result;
    }
    if (HasAutomationDetection(beforePage)) {
        result.automationDetected = true;
        Fail(result, L"STOP_AUTOMATION_DETECTED", L"Automation detection surface detected; normalization refused.");
        if (!options.guardResultJson.empty()) WriteRuntimeGuardTextFile(options.guardResultJson, BrowserSurfaceNormalizeResultJson(result));
        return result;
    }

    bool blockerBefore = HasBrowserSurfaceBlocker(before);
    if (options.mode == L"off") {
        result.ok = !blockerBefore;
        result.blockerStillPresent = blockerBefore;
        if (!result.ok) {
            result.stopCode = L"STOP_BROWSER_SURFACE_BLOCKING";
            result.reason = L"Browser surface blocker detected and normalization mode is off.";
        }
        if (!options.guardResultJson.empty()) WriteRuntimeGuardTextFile(options.guardResultJson, BrowserSurfaceNormalizeResultJson(result));
        return result;
    }

    if (blockerBefore) {
        ActionResult esc = PressKeyGlobal(L"ESC");
        result.escSent = esc.ok;
        Sleep(150);
    }

    WindowInfo afterWindow;
    ActiveWindowInfo(afterWindow);
    if (afterWindow.hwnd) {
        result.hwnd = afterWindow.hwnd;
        result.title = afterWindow.title;
        result.process = ProcessNameForPid(afterWindow.pid);
    }
    std::wstring after = BrowserHaystack(result.hwnd, result.title, result.process);
    std::wstring afterPage = BrowserPageHaystack(result.hwnd, result.title, result.process);
    if (HasActiveProtection(afterPage)) {
        result.activeProtectionDetected = true;
        Fail(result, L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK", L"Login, captcha, or human-verification surface remained after normalization.");
    } else if (HasAutomationDetection(afterPage)) {
        result.automationDetected = true;
        Fail(result, L"STOP_AUTOMATION_DETECTED", L"Automation detection surface remained after normalization.");
    } else if (HasBrowserSurfaceBlocker(after) && blockerBefore) {
        result.blockerStillPresent = true;
        result.loadingOrOverlayBlocking = ContainsInsensitive(after, L"loading");
        Fail(result, result.loadingOrOverlayBlocking ? L"STOP_LOADING_OR_OVERLAY_BLOCKING" : L"STOP_BROWSER_SURFACE_BLOCKING", L"Browser surface blocker remained after conservative ESC normalization.");
    } else {
        result.ok = true;
        result.reason = blockerBefore ? L"Browser surface normalized with ESC." : L"No browser surface blocker detected.";
    }

    if (!options.guardResultJson.empty()) {
        WriteRuntimeGuardTextFile(options.guardResultJson, BrowserSurfaceNormalizeResultJson(result));
    }
    return result;
}

std::wstring BrowserSurfaceNormalizeResultJson(const BrowserSurfaceNormalizeResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"stop_code\":" << JsonString(result.stopCode)
         << L",\"reason\":" << JsonString(result.reason)
         << L",\"hwnd\":" << (result.hwnd ? JsonString(FormatHwnd(result.hwnd)) : L"null")
         << L",\"title\":" << JsonString(result.title)
         << L",\"process\":" << JsonString(result.process)
         << L",\"esc_sent\":" << (result.escSent ? L"true" : L"false")
         << L",\"overlay_closed\":" << (result.overlayClosed ? L"true" : L"false")
         << L",\"blocker_still_present\":" << (result.blockerStillPresent ? L"true" : L"false")
         << L",\"active_protection_detected\":" << (result.activeProtectionDetected ? L"true" : L"false")
         << L",\"automation_detected\":" << (result.automationDetected ? L"true" : L"false")
         << L",\"loading_or_overlay_blocking\":" << (result.loadingOrOverlayBlocking ? L"true" : L"false")
         << L"}";
    return json.str();
}
