#include "RuntimeContextGuard.h"

#include "SafetyPolicy.h"
#include "Trace.h"
#include "UiaController.h"
#include "WindowFinder.h"

#include <UIAutomation.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <regex>
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

bool ArgExists(int argc, wchar_t** argv, const std::wstring& name) {
    for (int i = 2; i < argc; ++i) {
        if (argv[i] == name) return true;
    }
    return false;
}

std::vector<std::wstring> ArgValues(int argc, wchar_t** argv, const std::wstring& name) {
    std::vector<std::wstring> values;
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            values.push_back(argv[i + 1]);
            ++i;
        }
    }
    return values;
}

bool ParseBoolArg(int argc, wchar_t** argv, const std::wstring& name, bool& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    error = name + L" must be true or false.";
    return false;
}

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return false;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
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

bool MatchesPattern(const std::wstring& haystack, const std::wstring& pattern) {
    if (pattern.empty()) return true;
    try {
        std::wregex regex(pattern, std::regex_constants::icase);
        return std::regex_search(haystack, regex);
    } catch (...) {
        return ContainsInsensitive(haystack, pattern);
    }
}

bool AnyPatternMatches(const std::wstring& haystack, const std::vector<std::wstring>& patterns, std::wstring& matched) {
    for (const auto& pattern : patterns) {
        if (MatchesPattern(haystack, pattern)) {
            matched = pattern;
            return true;
        }
    }
    return false;
}

bool AllMarkersPresent(const std::wstring& haystack, const std::vector<std::wstring>& markers, std::wstring& missing) {
    for (const auto& marker : markers) {
        if (!MatchesPattern(haystack, marker)) {
            missing = marker;
            return false;
        }
    }
    return true;
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

std::wstring RectJsonOrNull(bool hasRect, const RECT& rect) {
    if (!hasRect) return L"null";
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring BuildUiaHaystack(HWND hwnd) {
    std::wstring text;
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) return text;
    for (const auto& element : tree.elements) {
        if (!element.name.empty()) text += L"\nname:" + element.name;
        if (!element.value.empty()) text += L"\nvalue:" + element.value;
        if (!element.controlType.empty()) text += L"\ncontrol_type:" + element.controlType;
        if (!element.automationId.empty()) text += L"\nautomation_id:" + element.automationId;
        if (!element.className.empty()) text += L"\nclass_name:" + element.className;
    }
    return text;
}

void ReadFocusedElement(std::wstring& name, std::wstring& controlType) {
    name.clear();
    controlType.clear();
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    bool initialized = SUCCEEDED(init);
    if (init == RPC_E_CHANGED_MODE) {
        initialized = false;
    }

    IUIAutomation* automation = nullptr;
    if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation))) || !automation) {
        if (initialized) CoUninitialize();
        return;
    }
    IUIAutomationElement* element = nullptr;
    if (SUCCEEDED(automation->GetFocusedElement(&element)) && element) {
        BSTR rawName = nullptr;
        if (SUCCEEDED(element->get_CurrentName(&rawName)) && rawName) {
            name = rawName;
            SysFreeString(rawName);
        }
        CONTROLTYPEID typeId = 0;
        if (SUCCEEDED(element->get_CurrentControlType(&typeId))) {
            controlType = std::to_wstring(typeId);
        }
        element->Release();
    }
    automation->Release();
    if (initialized) CoUninitialize();
}

void Fail(RuntimeContextGuardResult& result, const std::wstring& stopCode, const std::wstring& reason) {
    result.ok = false;
    result.stopCode = stopCode;
    result.reason = reason;
    result.continuedActionAfterWrongContext = false;
}

}  // namespace

ExpectedContextSpec ParseExpectedContextSpecFromArgs(int argc, wchar_t** argv, std::wstring& error) {
    ExpectedContextSpec spec;
    ArgValue(argc, argv, L"--expected-process-pattern", spec.expectedProcessPattern);
    ArgValue(argc, argv, L"--expected-title-pattern", spec.expectedTitlePattern);
    spec.requiredMarkers = ArgValues(argc, argv, L"--required-marker");
    spec.wrongPagePatterns = ArgValues(argc, argv, L"--wrong-page-pattern");
    spec.activeProtectionPatterns = ArgValues(argc, argv, L"--active-protection-pattern");
    spec.automationPatterns = ArgValues(argc, argv, L"--automation-pattern");
    spec.loadingOrOverlayPatterns = ArgValues(argc, argv, L"--loading-overlay-pattern");
    ArgValue(argc, argv, L"--expected-focus-marker", spec.expectedFocusMarker);
    ArgValue(argc, argv, L"--guard-trace-jsonl", spec.guardTraceJsonl);
    ArgValue(argc, argv, L"--guard-result-json", spec.guardResultJson);

    if (!ParseBoolArg(argc, argv, L"--stop-on-wrong-context", spec.stopOnFailure, error) ||
        !ParseBoolArg(argc, argv, L"--require-target-rect", spec.requireTargetRect, error) ||
        !ParseBoolArg(argc, argv, L"--require-target-current", spec.requireTargetFromCurrentObserve, error) ||
        !ParseBoolArg(argc, argv, L"--require-target-unique", spec.requireTargetUnique, error) ||
        !ParseBoolArg(argc, argv, L"--require-target-inside-viewport", spec.requireTargetInsideViewport, error) ||
        !ParseBoolArg(argc, argv, L"--allow-safe-overlay-normalization", spec.allowSafeOverlayNormalization, error)) {
        return spec;
    }

    spec.enabled =
        !spec.expectedProcessPattern.empty() ||
        !spec.expectedTitlePattern.empty() ||
        !spec.requiredMarkers.empty() ||
        !spec.wrongPagePatterns.empty() ||
        !spec.activeProtectionPatterns.empty() ||
        !spec.automationPatterns.empty() ||
        !spec.loadingOrOverlayPatterns.empty() ||
        spec.requireTargetRect ||
        spec.requireTargetFromCurrentObserve ||
        spec.requireTargetUnique ||
        spec.requireTargetInsideViewport ||
        !spec.expectedFocusMarker.empty();
    return spec;
}

RuntimeTargetContext ParseRuntimeTargetContextFromArgs(int argc, wchar_t** argv) {
    RuntimeTargetContext context;
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
    bool hasAll = ParseIntArg(argc, argv, L"--target-rect-left", left) &&
                  ParseIntArg(argc, argv, L"--target-rect-top", top) &&
                  ParseIntArg(argc, argv, L"--target-rect-right", right) &&
                  ParseIntArg(argc, argv, L"--target-rect-bottom", bottom);
    if (hasAll) {
        context.hasTargetRect = true;
        context.targetRect.left = left;
        context.targetRect.top = top;
        context.targetRect.right = right;
        context.targetRect.bottom = bottom;
    }
    std::wstring error;
    ParseBoolArg(argc, argv, L"--target-from-current-observe", context.targetFromCurrentObserve, error);
    ParseBoolArg(argc, argv, L"--target-unique", context.targetUnique, error);
    ParseBoolArg(argc, argv, L"--target-inside-viewport", context.targetInsideViewport, error);
    return context;
}

bool RuntimeContextGuardArgsPresent(const ExpectedContextSpec& spec) {
    return spec.enabled;
}

RuntimeContextGuardResult EvaluateRuntimeContextGuard(
    const ExpectedContextSpec& spec,
    const RuntimeTargetContext& targetContext) {
    RuntimeContextGuardResult result;
    result.hasTargetRect = targetContext.hasTargetRect;
    result.targetRect = targetContext.targetRect;
    result.targetFromCurrentObserve = targetContext.targetFromCurrentObserve;
    result.targetUnique = targetContext.targetUnique;
    result.targetInsideViewport = targetContext.targetInsideViewport;
    result.continuedActionAfterWrongContext = false;

    if (!spec.enabled) {
        return result;
    }

    WindowInfo foreground;
    if (!ActiveWindowInfo(foreground)) {
        result.foregroundOk = false;
        Fail(result, L"STOP_FOREGROUND_CHANGED", L"No foreground window was available.");
        return result;
    }
    result.foregroundHwnd = foreground.hwnd;
    result.foregroundTitle = foreground.title;
    result.foregroundProcess = ProcessNameForPid(foreground.pid);

    std::wstring haystack = L"title:" + result.foregroundTitle + L"\nprocess:" + result.foregroundProcess + BuildUiaHaystack(foreground.hwnd);
    ReadFocusedElement(result.focusedElementName, result.focusedElementControlType);
    if (!result.focusedElementName.empty()) {
        haystack += L"\nfocused_name:" + result.focusedElementName;
    }
    if (!result.focusedElementControlType.empty()) {
        haystack += L"\nfocused_control_type:" + result.focusedElementControlType;
    }

    if (!spec.expectedProcessPattern.empty() && !MatchesPattern(result.foregroundProcess, spec.expectedProcessPattern)) {
        result.foregroundOk = false;
        Fail(result, L"STOP_FOREGROUND_CHANGED", L"Foreground process did not match expected process pattern.");
        return result;
    }
    if (!spec.expectedTitlePattern.empty() && !MatchesPattern(result.foregroundTitle, spec.expectedTitlePattern)) {
        result.foregroundOk = false;
        Fail(result, L"STOP_FOREGROUND_CHANGED", L"Foreground title did not match expected title pattern.");
        return result;
    }

    std::wstring matched;
    if (AnyPatternMatches(haystack, spec.activeProtectionPatterns, matched)) {
        result.activeProtectionDetected = true;
        Fail(result, L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK", L"Active protection or login blocker matched: " + matched);
        return result;
    }
    if (AnyPatternMatches(haystack, spec.automationPatterns, matched)) {
        result.automationDetected = true;
        Fail(result, L"STOP_AUTOMATION_DETECTED", L"Automation detection marker matched: " + matched);
        return result;
    }
    if (AnyPatternMatches(haystack, spec.wrongPagePatterns, matched)) {
        result.wrongPageDetected = true;
        Fail(result, L"STOP_WRONG_PAGE", L"Wrong page marker matched: " + matched);
        return result;
    }
    if (AnyPatternMatches(haystack, spec.loadingOrOverlayPatterns, matched)) {
        result.loadingOrOverlayBlocking = true;
        Fail(result, L"STOP_LOADING_OR_OVERLAY_BLOCKING", L"Loading or overlay marker matched: " + matched);
        return result;
    }

    std::wstring missing;
    if (!AllMarkersPresent(haystack, spec.requiredMarkers, missing)) {
        result.markersOk = false;
        Fail(result, L"STOP_WRONG_CONTEXT", L"Required marker was not found: " + missing);
        return result;
    }

    if (spec.requireTargetRect && !targetContext.hasTargetRect) {
        Fail(result, L"STOP_TARGET_STALE", L"Target rect was required but not provided.");
        return result;
    }
    if (spec.requireTargetFromCurrentObserve && !targetContext.targetFromCurrentObserve) {
        result.targetFromCurrentObserve = false;
        Fail(result, L"STOP_TARGET_STALE", L"Target was not produced by the current observe pass.");
        return result;
    }
    if (spec.requireTargetUnique && !targetContext.targetUnique) {
        result.targetUnique = false;
        Fail(result, L"STOP_TARGET_NOT_UNIQUE", L"Target was not unique.");
        return result;
    }
    if (spec.requireTargetInsideViewport && !targetContext.targetInsideViewport) {
        result.targetInsideViewport = false;
        Fail(result, L"STOP_TARGET_OUTSIDE_VIEWPORT", L"Target was outside the viewport.");
        return result;
    }

    if (!spec.expectedFocusMarker.empty()) {
        std::wstring focusHaystack = result.focusedElementName + L"\n" + result.focusedElementControlType;
        if (!MatchesPattern(focusHaystack, spec.expectedFocusMarker)) {
            Fail(result, L"STOP_WRONG_FIELD_FOCUS", L"Focused element did not match expected focus marker.");
            return result;
        }
    }

    result.ok = true;
    return result;
}

std::wstring RuntimeContextGuardResultJson(const RuntimeContextGuardResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"stop_code\":" << JsonString(result.stopCode)
         << L",\"reason\":" << JsonString(result.reason)
         << L",\"foreground_hwnd\":" << (result.foregroundHwnd ? JsonString(FormatHwnd(result.foregroundHwnd)) : L"null")
         << L",\"foreground_title\":" << JsonString(result.foregroundTitle)
         << L",\"foreground_process\":" << JsonString(result.foregroundProcess)
         << L",\"foreground_ok\":" << (result.foregroundOk ? L"true" : L"false")
         << L",\"markers_ok\":" << (result.markersOk ? L"true" : L"false")
         << L",\"wrong_page_detected\":" << (result.wrongPageDetected ? L"true" : L"false")
         << L",\"active_protection_detected\":" << (result.activeProtectionDetected ? L"true" : L"false")
         << L",\"automation_detected\":" << (result.automationDetected ? L"true" : L"false")
         << L",\"loading_or_overlay_blocking\":" << (result.loadingOrOverlayBlocking ? L"true" : L"false")
         << L",\"target_rect\":" << RectJsonOrNull(result.hasTargetRect, result.targetRect)
         << L",\"target_from_current_observe\":" << (result.targetFromCurrentObserve ? L"true" : L"false")
         << L",\"target_unique\":" << (result.targetUnique ? L"true" : L"false")
         << L",\"target_inside_viewport\":" << (result.targetInsideViewport ? L"true" : L"false")
         << L",\"focused_element_name\":" << JsonString(result.focusedElementName)
         << L",\"focused_element_control_type\":" << JsonString(result.focusedElementControlType)
         << L",\"screenshot_path\":" << JsonString(result.screenshotPath)
         << L",\"continued_action_after_wrong_context\":false}";
    return json.str();
}

std::wstring RuntimeContextGuardEnvelopeJson(
    bool enabled,
    const RuntimeContextGuardResult& result,
    bool actionExecuted,
    const std::wstring& extraFieldsJson) {
    std::wstringstream json;
    json << L"{\"context_guard_enabled\":" << (enabled ? L"true" : L"false")
         << L",\"context_guard_result\":" << RuntimeContextGuardResultJson(result)
         << L",\"action_executed\":" << (actionExecuted ? L"true" : L"false")
         << L",\"continued_action_after_wrong_context\":false";
    if (!extraFieldsJson.empty()) {
        json << L"," << extraFieldsJson;
    }
    json << L"}";
    return json.str();
}

bool WriteRuntimeGuardTextFile(const std::wstring& path, const std::wstring& value) {
    if (path.empty()) return false;
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) return false;
    fwprintf(file, L"%ls", value.c_str());
    fclose(file);
    return true;
}

void PersistRuntimeContextGuardResult(
    const ExpectedContextSpec& spec,
    const RuntimeContextGuardResult& result,
    const std::wstring& command,
    bool actionExecuted) {
    std::wstring payload = RuntimeContextGuardEnvelopeJson(spec.enabled, result, actionExecuted);
    if (!spec.guardResultJson.empty()) {
        WriteRuntimeGuardTextFile(spec.guardResultJson, payload);
    }
    if (!spec.guardTraceJsonl.empty()) {
        FILE* file = nullptr;
        if (_wfopen_s(&file, spec.guardTraceJsonl.c_str(), L"a, ccs=UTF-8") == 0 && file) {
            fwprintf(
                file,
                L"{\"ts\":%ls,\"command\":%ls,\"context_guard_enabled\":%ls,\"context_guard_result\":%ls,\"action_executed\":%ls,\"continued_action_after_wrong_context\":false}\n",
                JsonString(NowTimestamp()).c_str(),
                JsonString(command).c_str(),
                spec.enabled ? L"true" : L"false",
                RuntimeContextGuardResultJson(result).c_str(),
                actionExecuted ? L"true" : L"false");
            fclose(file);
        }
    }
}
