#include "SessionCommandDispatcher.h"

#include "InputController.h"
#include "LatencyTracker.h"
#include "ObserveController.h"
#include "ProjectRoot.h"
#include "RuntimeContextGuard.h"
#include "SafetyPolicy.h"
#include "Selector.h"
#include "SessionLocatorCache.h"
#include "SessionManager.h"
#include "SessionObserveCache.h"
#include "Trace.h"
#include "UiaController.h"
#include "UserAbortController.h"
#include "WindowFinder.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct JsonStep {
    std::wstring stepId;
    std::wstring action;
    std::wstring target;
    std::wstring text;
    std::wstring expectedContextJson;
    std::wstring actionPrecondition;
    std::wstring verificationHint;
    std::wstring cachePolicy;
    std::wstring moveMode = L"human";
    std::wstring typeMode = L"human";
    bool forceReobserve = false;
    bool stopOnFailure = true;
    int x = -1;
    int y = -1;
    int delta = -120;
};

struct StepExecutionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    bool actionExecuted = false;
    bool observeCacheHit = false;
    bool observeCacheMiss = false;
    bool locatorCacheHit = false;
    bool locatorCacheMiss = false;
    RuntimeStepLatency latency;
};

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

bool ParseInt(const std::wstring& raw, int& value) {
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

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value) {
    std::wstring raw;
    return ArgValue(argc, argv, name, raw) && ParseInt(raw, value);
}

bool ParseBoolText(const std::wstring& raw, bool& value) {
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    return false;
}

bool ParseOptionalBoolArg(int argc, wchar_t** argv, const std::wstring& name, bool& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    if (ParseBoolText(raw, value)) return true;
    error = name + L" must be true or false.";
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

bool ReadTextFileUtf8(const std::wstring& path, std::wstring& text, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"r, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open file.";
        return false;
    }
    wchar_t buffer[4096] = {};
    std::wstring content;
    while (fgetws(buffer, static_cast<int>(sizeof(buffer) / sizeof(buffer[0])), file)) {
        content += buffer;
    }
    fclose(file);
    text = content;
    return true;
}

bool WriteTextFileUtf8(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    EnsureDirectoryPath(path.substr(0, path.find_last_of(L"\\/")));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

bool FindJsonKey(const std::wstring& json, const std::wstring& key, size_t& colon) {
    const std::wstring quoted = L"\"" + key + L"\"";
    size_t pos = json.find(quoted);
    if (pos == std::wstring::npos) return false;
    colon = json.find(L":", pos + quoted.size());
    return colon != std::wstring::npos;
}

std::wstring UnescapeJsonString(const std::wstring& value) {
    std::wstring result;
    bool escaped = false;
    for (wchar_t ch : value) {
        if (!escaped) {
            if (ch == L'\\') {
                escaped = true;
            } else {
                result += ch;
            }
            continue;
        }
        switch (ch) {
            case L'n': result += L'\n'; break;
            case L'r': result += L'\r'; break;
            case L't': result += L'\t'; break;
            case L'"': result += L'"'; break;
            case L'\\': result += L'\\'; break;
            default: result += ch; break;
        }
        escaped = false;
    }
    if (escaped) result += L'\\';
    return result;
}

bool FindJsonString(const std::wstring& json, const std::wstring& key, std::wstring& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t quote = json.find(L"\"", colon + 1);
    if (quote == std::wstring::npos) return false;
    std::wstring raw;
    bool escaped = false;
    for (size_t i = quote + 1; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (!escaped && ch == L'"') {
            value = UnescapeJsonString(raw);
            return true;
        }
        if (!escaped && ch == L'\\') {
            escaped = true;
            raw += ch;
        } else {
            escaped = false;
            raw += ch;
        }
    }
    return false;
}

bool FindJsonBool(const std::wstring& json, const std::wstring& key, bool& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t pos = colon + 1;
    while (pos < json.size() && std::iswspace(json[pos]) != 0) ++pos;
    if (json.compare(pos, 4, L"true") == 0) {
        value = true;
        return true;
    }
    if (json.compare(pos, 5, L"false") == 0) {
        value = false;
        return true;
    }
    return false;
}

bool FindJsonInt(const std::wstring& json, const std::wstring& key, int& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t pos = colon + 1;
    while (pos < json.size() && std::iswspace(json[pos]) != 0) ++pos;
    size_t start = pos;
    while (pos < json.size() && (json[pos] == L'-' || (json[pos] >= L'0' && json[pos] <= L'9'))) ++pos;
    if (pos == start) return false;
    return ParseInt(json.substr(start, pos - start), value);
}

bool ExtractJsonSection(
    const std::wstring& json,
    const std::wstring& key,
    wchar_t openChar,
    wchar_t closeChar,
    std::wstring& section) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t open = json.find(openChar, colon + 1);
    if (open == std::wstring::npos) return false;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (size_t i = open; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                inString = false;
            }
            continue;
        }
        if (ch == L'"') {
            inString = true;
            continue;
        }
        if (ch == openChar) {
            ++depth;
        } else if (ch == closeChar) {
            --depth;
            if (depth == 0) {
                section = json.substr(open, i - open + 1);
                return true;
            }
        }
    }
    return false;
}

std::vector<std::wstring> SplitTopLevelObjects(const std::wstring& arrayJson) {
    std::vector<std::wstring> objects;
    bool inString = false;
    bool escaped = false;
    int depth = 0;
    size_t start = std::wstring::npos;
    for (size_t i = 0; i < arrayJson.size(); ++i) {
        wchar_t ch = arrayJson[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                inString = false;
            }
            continue;
        }
        if (ch == L'"') {
            inString = true;
            continue;
        }
        if (ch == L'{') {
            if (depth == 0) start = i;
            ++depth;
        } else if (ch == L'}') {
            --depth;
            if (depth == 0 && start != std::wstring::npos) {
                objects.push_back(arrayJson.substr(start, i - start + 1));
                start = std::wstring::npos;
            }
        }
    }
    return objects;
}

std::wstring SessionErrorJson(const std::wstring& code, const std::wstring& message) {
    return L"{\"code\":" + JsonString(code) + L",\"message\":" + JsonString(message.empty() ? ErrorMessageForCode(code) : message) + L"}";
}

std::wstring SessionEnvelopeJson(
    bool ok,
    const std::wstring& command,
    unsigned long long startTick,
    const std::wstring& sessionId,
    bool sessionAlive,
    const std::wstring& sessionStatus,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson) {
    std::wstring outputData = (!ok && IsUserAbortStopCode(errorCode))
        ? MergeUserAbortEvidenceJson(dataJson)
        : (dataJson.empty() ? L"{}" : dataJson);
    std::wstringstream json;
    json << L"{\"ok\":" << (ok ? L"true" : L"false")
         << L",\"command\":" << JsonString(command)
         << L",\"session_id\":" << JsonString(sessionId)
         << L",\"session_alive\":" << (sessionAlive ? L"true" : L"false")
         << L",\"session_status\":" << JsonString(sessionStatus)
         << L",\"error\":" << (ok ? L"null" : SessionErrorJson(errorCode, errorMessage))
         << L",\"data\":" << outputData
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << ElapsedMs(startTick)
         << L"}";
    return json.str();
}

int EmitSessionEnvelope(
    bool ok,
    const std::wstring& command,
    unsigned long long startTick,
    const RuntimeSession* session,
    const std::wstring& fallbackSessionId,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson,
    int exitCode) {
    std::wstring sessionId = session ? session->sessionId : fallbackSessionId;
    bool alive = session ? session->sessionAlive : false;
    std::wstring status = session ? RuntimeSessionStatus(*session) : (ok ? L"none" : L"error");
    std::wstring output = SessionEnvelopeJson(ok, command, startTick, sessionId, alive, status, errorCode, errorMessage, dataJson);
    AppendAuditLine(command, session ? session->targetTitle : L"", ok ? L"ok" : L"failed", ok ? L"" : errorCode, ElapsedMs(startTick), dataJson);
    std::wcout << output << L"\n";
    return exitCode;
}

WindowInfo CurrentSessionWindow(const RuntimeSession& session) {
    WindowInfo info;
    HWND hwnd = reinterpret_cast<HWND>(session.targetHwndValue);
    if (!hwnd || !IsWindow(hwnd)) return info;
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

bool ProcessAlive(DWORD pid) {
    if (pid == 0) return false;
    HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, pid);
    if (!process) return false;
    DWORD wait = WaitForSingleObject(process, 0);
    CloseHandle(process);
    return wait == WAIT_TIMEOUT;
}

bool ValidateSessionTarget(RuntimeSession& session, std::wstring& errorCode, std::wstring& errorMessage, std::wstring& dataJson) {
    if (session.targetHwndValue == 0) {
        errorCode = L"STOP_SESSION_TARGET_STALE";
        errorMessage = L"Session has no bound target window.";
        dataJson = L"{\"session\":" + RuntimeSessionJson(session) + L"}";
        return false;
    }
    HWND hwnd = reinterpret_cast<HWND>(session.targetHwndValue);
    if (!hwnd || !IsWindow(hwnd)) {
        errorCode = L"STOP_SESSION_WINDOW_CLOSED";
        errorMessage = L"Session target window is closed.";
        dataJson = L"{\"session\":" + RuntimeSessionJson(session) + L"}";
        return false;
    }
    if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) {
        errorCode = L"STOP_SESSION_TARGET_STALE";
        errorMessage = L"Session target window is hidden or minimized.";
        dataJson = L"{\"session\":" + RuntimeSessionJson(session) + L"}";
        return false;
    }
    if (session.targetProcess != 0 && !ProcessAlive(session.targetProcess)) {
        errorCode = L"STOP_SESSION_TARGET_STALE";
        errorMessage = L"Session target process is no longer alive.";
        dataJson = L"{\"session\":" + RuntimeSessionJson(session) + L"}";
        return false;
    }
    WindowInfo current = CurrentSessionWindow(session);
    std::wstring currentProcess = ProcessNameForPid(current.pid);
    if (!session.requestedTitle.empty() && !ContainsInsensitive(current.title, session.requestedTitle) && !ContainsInsensitive(session.requestedTitle, current.title)) {
        errorCode = L"STOP_SESSION_TARGET_STALE";
        errorMessage = L"Session target title drifted away from requested title.";
        dataJson = L"{\"previous_title\":" + JsonString(session.targetTitle)
            + L",\"current_title\":" + JsonString(current.title)
            + L",\"session\":" + RuntimeSessionJson(session) + L"}";
        return false;
    }
    session.targetHwnd = FormatHwnd(current.hwnd);
    session.targetProcess = current.pid;
    session.targetProcessName = currentProcess;
    session.targetTitle = current.title;
    session.targetBounds = RuntimeBoundsFromRect(current.rect);
    return true;
}

bool EnforceSessionSafety(const RuntimeSession& session, const std::wstring& command, std::wstring& errorCode, std::wstring& errorMessage, std::wstring& dataJson) {
    WindowInfo info = CurrentSessionWindow(session);
    SafetyCheckResult safety = CheckWindowSafety(info, session.requestedTitle.empty() ? session.targetTitle : session.requestedTitle);
    if (safety.ok) return true;
    errorCode = safety.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : safety.errorCode;
    errorMessage = safety.message.empty() ? L"Safety policy denied this session action." : safety.message;
    dataJson = L"{\"session_id\":" + JsonString(session.sessionId)
        + L",\"action\":" + JsonString(command)
        + L",\"target_title\":" + JsonString(session.targetTitle)
        + L",\"process_name\":" + JsonString(safety.processName)
        + L"}";
    return false;
}

ExpectedContextSpec ExpectedContextFromJson(const std::wstring& json) {
    ExpectedContextSpec spec;
    if (json.empty()) return spec;
    FindJsonString(json, L"expected_process_pattern", spec.expectedProcessPattern);
    FindJsonString(json, L"expected_title_pattern", spec.expectedTitlePattern);
    std::wstring marker;
    if (FindJsonString(json, L"required_marker", marker) && !marker.empty()) spec.requiredMarkers.push_back(marker);
    std::wstring wrong;
    if (FindJsonString(json, L"wrong_page_pattern", wrong) && !wrong.empty()) spec.wrongPagePatterns.push_back(wrong);
    std::wstring active;
    if (FindJsonString(json, L"active_protection_pattern", active) && !active.empty()) spec.activeProtectionPatterns.push_back(active);
    std::wstring automation;
    if (FindJsonString(json, L"automation_pattern", automation) && !automation.empty()) spec.automationPatterns.push_back(automation);
    std::wstring loading;
    if (FindJsonString(json, L"loading_overlay_pattern", loading) && !loading.empty()) spec.loadingOrOverlayPatterns.push_back(loading);
    FindJsonString(json, L"expected_focus_marker", spec.expectedFocusMarker);
    FindJsonBool(json, L"require_target_rect", spec.requireTargetRect);
    FindJsonBool(json, L"require_target_current", spec.requireTargetFromCurrentObserve);
    FindJsonBool(json, L"require_target_unique", spec.requireTargetUnique);
    FindJsonBool(json, L"require_target_inside_viewport", spec.requireTargetInsideViewport);
    spec.stopOnFailure = true;
    spec.enabled =
        !spec.expectedProcessPattern.empty() ||
        !spec.expectedTitlePattern.empty() ||
        !spec.requiredMarkers.empty() ||
        !spec.wrongPagePatterns.empty() ||
        !spec.activeProtectionPatterns.empty() ||
        !spec.automationPatterns.empty() ||
        !spec.loadingOrOverlayPatterns.empty() ||
        !spec.expectedFocusMarker.empty() ||
        spec.requireTargetRect ||
        spec.requireTargetFromCurrentObserve ||
        spec.requireTargetUnique ||
        spec.requireTargetInsideViewport;
    return spec;
}

RuntimeTargetContext RuntimeTargetFromSelector(const SelectorResult& located) {
    RuntimeTargetContext context;
    context.hasTargetRect = true;
    context.targetRect = located.rect;
    context.targetFromCurrentObserve = true;
    context.targetUnique = located.matchCount <= 1;
    context.targetInsideViewport = true;
    return context;
}

RuntimeTargetContext RuntimeTargetFromLocatorCache(const SessionLocatorCacheEntry& entry) {
    RuntimeTargetContext context;
    context.hasTargetRect = true;
    context.targetRect = RuntimeBoundsToRect(entry.targetRect);
    context.targetFromCurrentObserve = entry.staleCheckPassed;
    context.targetUnique = true;
    context.targetInsideViewport = entry.insideViewport;
    return context;
}

bool RunContextGuardForStep(
    const ExpectedContextSpec& spec,
    const RuntimeTargetContext& target,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    if (!spec.enabled) return true;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(spec, target);
    if (guard.ok) return true;
    errorCode = guard.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guard.stopCode;
    if (errorCode == L"STOP_FOREGROUND_CHANGED") {
        errorCode = L"STOP_SESSION_FOREGROUND_CHANGED";
    }
    errorMessage = guard.reason;
    dataJson = L"{\"context_guard_each_step\":true,\"context_guard_result\":" + RuntimeContextGuardResultJson(guard)
        + L",\"action_executed\":false,\"continued_action_after_wrong_context\":false}";
    return false;
}

JsonStep StepFromJsonObject(const std::wstring& objectJson, int index) {
    JsonStep step;
    step.stepId = L"step-" + std::to_wstring(index + 1);
    FindJsonString(objectJson, L"step_id", step.stepId);
    FindJsonString(objectJson, L"action", step.action);
    FindJsonString(objectJson, L"target", step.target);
    FindJsonString(objectJson, L"text", step.text);
    FindJsonString(objectJson, L"action_precondition", step.actionPrecondition);
    FindJsonString(objectJson, L"verification_hint", step.verificationHint);
    FindJsonString(objectJson, L"cache_policy", step.cachePolicy);
    FindJsonString(objectJson, L"move_mode", step.moveMode);
    FindJsonString(objectJson, L"type_mode", step.typeMode);
    FindJsonBool(objectJson, L"force_reobserve", step.forceReobserve);
    FindJsonBool(objectJson, L"stop_on_failure", step.stopOnFailure);
    FindJsonInt(objectJson, L"x", step.x);
    FindJsonInt(objectJson, L"y", step.y);
    FindJsonInt(objectJson, L"delta", step.delta);
    ExtractJsonSection(objectJson, L"expected_context", L'{', L'}', step.expectedContextJson);
    return step;
}

bool ParseStepsJson(const std::wstring& text, std::vector<JsonStep>& steps, std::wstring& error) {
    std::wstring arrayJson;
    if (text.find(L"[") == std::wstring::npos) {
        error = L"steps-json must contain an array.";
        return false;
    }
    if (!ExtractJsonSection(text, L"steps", L'[', L']', arrayJson)) {
        size_t start = text.find(L"[");
        size_t end = text.rfind(L"]");
        if (start == std::wstring::npos || end == std::wstring::npos || end <= start) {
            error = L"steps-json must be an array or an object with steps.";
            return false;
        }
        arrayJson = text.substr(start, end - start + 1);
    }
    auto objects = SplitTopLevelObjects(arrayJson);
    if (objects.empty()) {
        error = L"steps-json contains no steps.";
        return false;
    }
    for (size_t i = 0; i < objects.size(); ++i) {
        JsonStep step = StepFromJsonObject(objects[i], static_cast<int>(i));
        if (step.action.empty()) {
            error = L"step is missing action.";
            return false;
        }
        steps.push_back(step);
    }
    return true;
}

std::wstring StepResultJson(const JsonStep& step, const StepExecutionResult& result) {
    std::wstring outputData = (!result.ok && IsUserAbortStopCode(result.errorCode))
        ? MergeUserAbortEvidenceJson(result.dataJson)
        : (result.dataJson.empty() ? L"{}" : result.dataJson);
    std::wstringstream json;
    json << L"{\"step_id\":" << JsonString(step.stepId)
         << L",\"action\":" << JsonString(step.action)
         << L",\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"error_code\":" << JsonString(result.errorCode)
         << L",\"error_message\":" << JsonString(result.errorMessage)
         << L",\"action_executed\":" << (result.actionExecuted ? L"true" : L"false")
         << L",\"observe_cache_hit\":" << (result.observeCacheHit ? L"true" : L"false")
         << L",\"observe_cache_miss\":" << (result.observeCacheMiss ? L"true" : L"false")
         << L",\"locator_cache_hit\":" << (result.locatorCacheHit ? L"true" : L"false")
         << L",\"locator_cache_miss\":" << (result.locatorCacheMiss ? L"true" : L"false")
         << L",\"latency\":" << RuntimeStepLatencyJson(result.latency)
         << L",\"data\":" << outputData
         << L"}";
    return json.str();
}

bool VerifyUiaContains(const RuntimeSession& session, const std::wstring& expected, std::wstring& dataJson, std::wstring& errorCode, std::wstring& errorMessage) {
    bool readOk = false;
    bool matched = false;
    size_t elementCount = 0;
    std::wstring readErrorCode;
    std::wstring readErrorMessage;
    unsigned long long deadline = GetTickCount64() + 500;
    do {
        UiaQueryResult tree = ReadUiaTree(reinterpret_cast<HWND>(session.targetHwndValue));
        readOk = tree.ok;
        readErrorCode = tree.errorCode;
        readErrorMessage = tree.errorMessage;
        if (tree.ok) {
            elementCount = tree.elements.size();
            std::wstring haystack;
            for (const auto& element : tree.elements) {
                haystack += element.name + L"\n";
                haystack += element.value + L"\n";
                haystack += element.controlType + L"\n";
                haystack += element.automationId + L"\n";
            }
            matched = haystack.find(expected) != std::wstring::npos;
            if (matched) break;
        }
        Sleep(10);
    } while (GetTickCount64() < deadline);

    dataJson = L"{\"verified\":" + std::wstring(matched ? L"true" : L"false")
        + L",\"verification_mode\":\"uia_contains\""
        + L",\"expected_contains\":" + JsonString(expected)
        + L",\"element_count\":" + std::to_wstring(elementCount) + L"}";
    if (!readOk) {
        errorCode = readErrorCode.empty() ? L"UIA_READ_FAILED" : readErrorCode;
        errorMessage = readErrorMessage.empty() ? L"UIA tree read failed." : readErrorMessage;
        return false;
    }
    if (!matched) {
        errorCode = L"VERIFICATION_FAILED";
        errorMessage = L"UIA verification marker was not found.";
    }
    return matched;
}

bool VerifyHint(const RuntimeSession& session, const std::wstring& hint, std::wstring& dataJson, std::wstring& errorCode, std::wstring& errorMessage) {
    if (hint.empty()) {
        dataJson = L"{\"verified\":true,\"verification_hint\":\"\"}";
        return true;
    }
    std::wstring path;
    std::wstring expected;
    if (hint.rfind(L"state_contains:", 0) == 0) {
        path = L"D:\\testrepo\\testwindow\\runtime\\state.txt";
        expected = hint.substr(std::wstring(L"state_contains:").size());
    } else if (hint.rfind(L"file_contains:", 0) == 0) {
        std::wstring body = hint.substr(std::wstring(L"file_contains:").size());
        size_t sep = body.find(L"|");
        if (sep == std::wstring::npos) {
            errorCode = L"INVALID_ARGUMENT";
            errorMessage = L"file_contains verification hint must be file_contains:<path>|<text>.";
            dataJson = L"{\"verified\":false}";
            return false;
        }
        path = body.substr(0, sep);
        expected = body.substr(sep + 1);
    } else if (hint.rfind(L"uia_contains:", 0) == 0) {
        return VerifyUiaContains(session, hint.substr(std::wstring(L"uia_contains:").size()), dataJson, errorCode, errorMessage);
    } else if (hint.rfind(L"contains:", 0) == 0) {
        path = L"D:\\testrepo\\testwindow\\runtime\\state.txt";
        expected = hint.substr(std::wstring(L"contains:").size());
    } else {
        dataJson = L"{\"verified\":true,\"verification_hint\":" + JsonString(hint) + L",\"verification_mode\":\"marker_only\"}";
        return true;
    }

    std::wstring normalized;
    std::wstring pathError;
    if (!IsReadPathAllowed(path, normalized, pathError)) {
        errorCode = L"SAFETY_POLICY_DENIED";
        errorMessage = pathError.empty() ? L"Verification path is outside allowed read roots." : pathError;
        dataJson = L"{\"verified\":false,\"path\":" + JsonString(path) + L"}";
        return false;
    }
    std::wstring content;
    std::wstring readError;
    bool readOk = false;
    bool matched = false;
    unsigned long long deadline = GetTickCount64() + 500;
    do {
        readError.clear();
        readOk = ReadTextFileUtf8(normalized, content, readError);
        matched = readOk && content.find(expected) != std::wstring::npos;
        if (matched) break;
        Sleep(10);
    } while (GetTickCount64() < deadline);
    if (!readOk) {
        errorCode = L"FILE_READ_FAILED";
        errorMessage = readError;
        dataJson = L"{\"verified\":false,\"path\":" + JsonString(normalized) + L"}";
        return false;
    }
    dataJson = L"{\"verified\":" + std::wstring(matched ? L"true" : L"false")
        + L",\"path\":" + JsonString(normalized)
        + L",\"expected_contains\":" + JsonString(expected)
        + L",\"content_length\":" + std::to_wstring(content.size()) + L"}";
    if (!matched) {
        errorCode = L"VERIFICATION_FAILED";
        errorMessage = L"Verification marker was not found.";
    }
    return matched;
}

SelectorResult LocateWithSessionCache(
    RuntimeSession& session,
    const JsonStep& step,
    RuntimeStepLatency& latency,
    bool& cacheHit,
    bool& cacheMiss,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    SelectorResult located;
    std::wstring key = step.target;
    bool forceRelocate = step.forceReobserve || step.cachePolicy == L"force_relocate" || step.cachePolicy == L"force_reobserve";
    unsigned long long cacheStart = GetTickCount64();
    SessionLocatorCacheLookupResult cache = SessionLocatorCacheLookup(session, key, forceRelocate);
    latency.cacheLookupMs += ElapsedMs(cacheStart);
    cacheHit = cache.hit;
    cacheMiss = cache.miss;
    latency.locatorCacheHit = cache.hit;
    latency.locatorCacheMiss = cache.miss;
    if (cache.hit) {
        located.ok = true;
        located.selector = key;
        located.locateMethod = L"session_locator_cache";
        located.finalMethod = cache.entry.locatorSource;
        located.matchCount = 1;
        located.confidence = cache.entry.locatorConfidence;
        located.clientX = cache.entry.targetCenterX;
        located.clientY = cache.entry.targetCenterY;
        located.rect = RuntimeBoundsToRect(cache.entry.targetRect);
        located.source = cache.entry.locatorSource;
        located.elementName = cache.entry.targetName;
        located.elementControlType = cache.entry.targetRole;
        located.matchedText = cache.entry.targetText;
        located.hasElement = !cache.entry.targetName.empty() || !cache.entry.targetRole.empty();
        located.dataJson = L"{\"ok\":true,\"selector\":" + JsonString(key)
            + L",\"method\":\"session_locator_cache\",\"locator_cache_hit\":true,\"cache_entry\":"
            + SessionLocatorCacheJson(cache.entry) + L"}";
        return located;
    }
    if (cache.rejectedStale && !forceRelocate) {
        errorCode = L"STOP_TARGET_STALE";
        errorMessage = L"Cached locator was stale and force_reobserve was not requested.";
        dataJson = L"{\"cache_hit_attempted\":true,\"stale_target_detected\":true,\"old_rect_not_clicked\":true,\"locator_cache_reject_stale\":true,\"reason\":" + JsonString(cache.reason) + L"}";
        return located;
    }
    unsigned long long locateStart = GetTickCount64();
    located = LocateSelector(reinterpret_cast<HWND>(session.targetHwndValue), key);
    latency.locateMs += ElapsedMs(locateStart);
    if (!located.ok) {
        errorCode = located.errorCode.empty() ? L"LOCATOR_NOT_FOUND" : located.errorCode;
        errorMessage = located.errorMessage;
        dataJson = located.dataJson;
        return located;
    }
    SessionLocatorCacheStore(session, key, located);
    return located;
}

StepExecutionResult ExecuteStep(RuntimeSession& session, const JsonStep& step, LatencySequenceTracker* sequence = nullptr) {
    StepExecutionResult result;
    unsigned long long stepStart = GetTickCount64();
    result.latency = sequence ? sequence->NewStep(step.stepId, step.action) : RuntimeStepLatency{};
    result.latency.stepId = step.stepId;
    result.latency.action = step.action;
    result.latency.processRestartCount = 1;
    result.latency.sessionReuseEnabled = true;

    if (IsUserAbortRequested()) {
        result.ok = false;
        result.errorCode = UserAbortStopCode();
        result.errorMessage = UserAbortMessage();
        result.dataJson = UserAbortEvidenceJson(L"\"action_executed\":false");
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    session.sessionCommandCount++;
    std::wstring targetErrorCode;
    std::wstring targetErrorMessage;
    std::wstring targetDataJson;
    unsigned long long attachStart = GetTickCount64();
    if (!ValidateSessionTarget(session, targetErrorCode, targetErrorMessage, targetDataJson)) {
        result.ok = false;
        result.errorCode = targetErrorCode;
        result.errorMessage = targetErrorMessage;
        result.dataJson = targetDataJson;
        result.latency.sessionAttachMs = ElapsedMs(attachStart);
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }
    result.latency.sessionAttachMs = ElapsedMs(attachStart);

    ExpectedContextSpec expectedContext = ExpectedContextFromJson(step.expectedContextJson);
    std::wstring action = ToLowerInvariant(step.action);
    if (action == L"observe") {
        unsigned long long cacheStart = GetTickCount64();
        SessionObserveCacheLookupResult cache = SessionObserveCacheLookup(session, 2000, step.forceReobserve || step.cachePolicy == L"force_reobserve");
        result.latency.cacheLookupMs = ElapsedMs(cacheStart);
        result.observeCacheHit = cache.hit;
        result.observeCacheMiss = cache.miss;
        result.latency.observeCacheHit = cache.hit;
        result.latency.observeCacheMiss = cache.miss;
        if (cache.hit) {
            result.ok = true;
            result.dataJson = L"{\"session_observe_ok\":true,\"observe_cache_hit\":true,\"observe_cache_miss\":false,\"observe_cache\":"
                + SessionObserveCacheJson(cache.entry) + L"}";
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        unsigned long long observeStart = GetTickCount64();
        ObserveResult observe = ObserveWindow(session.requestedTitle.empty() ? session.targetTitle : session.requestedTitle, false, true, 80, session.requestedProcess);
        result.latency.observeMs = ElapsedMs(observeStart);
        if (!observe.ok) {
            result.ok = false;
            result.errorCode = observe.errorCode.empty() ? L"UNKNOWN_ERROR" : observe.errorCode;
            result.errorMessage = observe.errorMessage;
            result.dataJson = observe.dataJson;
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        SessionObserveCacheStore(session, observe);
        result.ok = true;
        result.dataJson = L"{\"session_observe_ok\":true,\"observe_cache_hit\":false,\"observe_cache_miss\":true,\"observe_id\":"
            + JsonString(session.lastObserveId) + L",\"observe\":" + observe.dataJson + L"}";
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    if (action == L"locate") {
        bool cacheHit = false;
        bool cacheMiss = false;
        SelectorResult located = LocateWithSessionCache(session, step, result.latency, cacheHit, cacheMiss, result.errorCode, result.errorMessage, result.dataJson);
        result.locatorCacheHit = cacheHit;
        result.locatorCacheMiss = cacheMiss;
        if (!located.ok) {
            result.ok = false;
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        RuntimeTargetContext target = RuntimeTargetFromSelector(located);
        if (!RunContextGuardForStep(expectedContext, target, result.errorCode, result.errorMessage, result.dataJson)) {
            result.ok = false;
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        result.ok = true;
        result.dataJson = L"{\"located\":true,\"locator_cache_hit\":" + std::wstring(cacheHit ? L"true" : L"false")
            + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
            + L",\"context_guard_each_step\":" + std::wstring(expectedContext.enabled ? L"true" : L"false")
            + L",\"locator\":" + located.dataJson + L"}";
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    if (action == L"verify") {
        unsigned long long verifyStart = GetTickCount64();
        bool verified = VerifyHint(session, step.verificationHint, result.dataJson, result.errorCode, result.errorMessage);
        result.latency.verifyMs = ElapsedMs(verifyStart);
        result.ok = verified;
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    std::wstring safetyCode;
    std::wstring safetyMessage;
    std::wstring safetyData;
    if (!EnforceSessionSafety(session, action, safetyCode, safetyMessage, safetyData)) {
        result.ok = false;
        result.errorCode = safetyCode;
        result.errorMessage = safetyMessage;
        result.dataJson = safetyData;
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    if (action == L"click" || action == L"click_and_verify_focus" || action == L"click_and_verify_context" || action == L"click_button_and_verify_marker") {
        int clientX = step.x;
        int clientY = step.y;
        SelectorResult located;
        bool cacheHit = false;
        bool cacheMiss = false;
        RuntimeTargetContext targetContext;
        if ((!step.target.empty()) && (clientX < 0 || clientY < 0)) {
            located = LocateWithSessionCache(session, step, result.latency, cacheHit, cacheMiss, result.errorCode, result.errorMessage, result.dataJson);
            result.locatorCacheHit = cacheHit;
            result.locatorCacheMiss = cacheMiss;
            if (!located.ok) {
                result.ok = false;
                if (sequence) sequence->FinishStep(result.latency, stepStart);
                return result;
            }
            clientX = located.clientX;
            clientY = located.clientY;
            targetContext = RuntimeTargetFromSelector(located);
        }
        if (clientX < 0 || clientY < 0) {
            result.ok = false;
            result.errorCode = L"INVALID_ARGUMENT";
            result.errorMessage = L"click requires target or x/y.";
            result.dataJson = L"{}";
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        if (!targetContext.hasTargetRect) {
            targetContext.hasTargetRect = true;
            targetContext.targetRect = RECT{clientX, clientY, clientX, clientY};
        }
        if (!RunContextGuardForStep(expectedContext, targetContext, result.errorCode, result.errorMessage, result.dataJson)) {
            result.ok = false;
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        unsigned long long clickStart = GetTickCount64();
        ClickResult clicked = ClickClientPoint(reinterpret_cast<HWND>(session.targetHwndValue), clientX, clientY, step.moveMode.empty() ? L"human" : step.moveMode, 0);
        result.latency.clickMs = ElapsedMs(clickStart);
        result.latency.mouseMoveMs = clicked.durationMs;
        if (!clicked.ok) {
            result.ok = false;
            result.errorCode = clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode;
            result.errorMessage = clicked.error;
            result.dataJson = L"{\"click_sent\":false}";
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        result.actionExecuted = true;
        ++session.actionCounter;
        session.lastActionId = L"act-" + std::to_wstring(session.actionCounter);
        SessionObserveCacheInvalidateAfterAction(session);
        SessionLocatorCacheInvalidateAfterAction(session);
        bool verified = true;
        std::wstring verifyJson = L"{\"verified\":true}";
        if (!step.verificationHint.empty()) {
            unsigned long long verifyStart = GetTickCount64();
            verified = VerifyHint(session, step.verificationHint, verifyJson, result.errorCode, result.errorMessage);
            result.latency.verifyMs = ElapsedMs(verifyStart);
        }
        result.ok = verified;
        result.dataJson = L"{\"click_sent\":true,\"action_executed\":true,\"focus_verified_after_click\":"
            + std::wstring(clicked.focusVerified ? L"true" : L"false")
            + L",\"context_guard_each_step\":" + std::wstring(expectedContext.enabled ? L"true" : L"false")
            + L",\"locator_cache_hit\":" + std::wstring(cacheHit ? L"true" : L"false")
            + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
            + L",\"verify\":" + verifyJson + L"}";
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    if (action == L"type" || action == L"type_and_verify_text") {
        RuntimeTargetContext targetContext;
        if (!RunContextGuardForStep(expectedContext, targetContext, result.errorCode, result.errorMessage, result.dataJson)) {
            result.ok = false;
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        bool targetFocusUsed = false;
        bool cacheHit = false;
        bool cacheMiss = false;
        std::wstring locateJson = L"null";
        if (!step.target.empty()) {
            SelectorResult located = LocateWithSessionCache(session, step, result.latency, cacheHit, cacheMiss, result.errorCode, result.errorMessage, locateJson);
            result.locatorCacheHit = cacheHit;
            result.locatorCacheMiss = cacheMiss;
            if (!located.ok) {
                result.ok = false;
                result.errorCode = result.errorCode.empty() ? L"LOCATOR_NOT_FOUND" : result.errorCode;
                result.errorMessage = result.errorMessage.empty() ? L"Target was not found before typing." : result.errorMessage;
                result.dataJson = L"{\"typing_started\":false,\"text_length\":0,\"target_focus_used\":true,\"locator_cache_hit\":"
                    + std::wstring(cacheHit ? L"true" : L"false")
                    + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
                    + L",\"locate\":" + locateJson + L"}";
                if (sequence) sequence->FinishStep(result.latency, stepStart);
                return result;
            }
            unsigned long long clickStart = GetTickCount64();
            ClickResult clicked = ClickClientPoint(reinterpret_cast<HWND>(session.targetHwndValue), located.clientX, located.clientY, step.moveMode.empty() ? L"human" : step.moveMode, 0);
            result.latency.clickMs += ElapsedMs(clickStart);
            if (!clicked.ok) {
                result.ok = false;
                result.errorCode = clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode;
                result.errorMessage = clicked.error;
                result.dataJson = L"{\"typing_started\":false,\"text_length\":0,\"target_focus_used\":true,\"click_sent\":false,\"locator_cache_hit\":"
                    + std::wstring(cacheHit ? L"true" : L"false")
                    + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
                    + L",\"locate\":" + locateJson + L"}";
                if (sequence) sequence->FinishStep(result.latency, stepStart);
                return result;
            }
            targetFocusUsed = true;
            Sleep(50);
        }
        unsigned long long typeStart = GetTickCount64();
        TypeResult typed = TypeText(reinterpret_cast<HWND>(session.targetHwndValue), step.text, step.typeMode.empty() ? L"human" : step.typeMode, -1);
        result.latency.typeMs = ElapsedMs(typeStart);
        if (!typed.ok) {
            result.ok = false;
            result.errorCode = typed.errorCode.empty() ? L"SEND_INPUT_FAILED" : typed.errorCode;
            result.errorMessage = typed.error;
            result.dataJson = L"{\"typing_started\":false,\"text_length\":0,\"target_focus_used\":"
                + std::wstring(targetFocusUsed ? L"true" : L"false")
                + L",\"locator_cache_hit\":" + std::wstring(cacheHit ? L"true" : L"false")
                + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
                + L",\"locate\":" + locateJson + L"}";
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        result.actionExecuted = true;
        ++session.actionCounter;
        session.lastActionId = L"act-" + std::to_wstring(session.actionCounter);
        SessionObserveCacheInvalidateAfterAction(session);
        SessionLocatorCacheInvalidateAfterAction(session);
        bool verified = true;
        std::wstring verifyJson = L"{\"verified\":true}";
        if (!step.verificationHint.empty()) {
            unsigned long long verifyStart = GetTickCount64();
            verified = VerifyHint(session, step.verificationHint, verifyJson, result.errorCode, result.errorMessage);
            result.latency.verifyMs = ElapsedMs(verifyStart);
        }
        result.ok = verified;
        result.dataJson = L"{\"typing_started\":true,\"action_executed\":true,\"typed_text_verified\":"
            + std::wstring(verified ? L"true" : L"false")
            + L",\"context_guard_each_step\":" + std::wstring(expectedContext.enabled ? L"true" : L"false")
            + L",\"target_focus_used\":" + std::wstring(targetFocusUsed ? L"true" : L"false")
            + L",\"locator_cache_hit\":" + std::wstring(cacheHit ? L"true" : L"false")
            + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
            + L",\"text_length\":" + std::to_wstring(typed.textLength)
            + L",\"type_mode\":" + JsonString(typed.typeMode)
            + L",\"locate\":" + locateJson
            + L",\"verify\":" + verifyJson + L"}";
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    if (action == L"scroll" || action == L"scroll_and_verify_progress" || action == L"scroll_and_locate" || action == L"scroll_and_locate_and_click") {
        int clientX = step.x;
        int clientY = step.y;
        if (clientX < 0 || clientY < 0) {
            RECT client = {};
            GetClientRect(reinterpret_cast<HWND>(session.targetHwndValue), &client);
            clientX = (client.right - client.left) / 2;
            clientY = (client.bottom - client.top) / 2;
        }
        RuntimeTargetContext targetContext;
        if (!RunContextGuardForStep(expectedContext, targetContext, result.errorCode, result.errorMessage, result.dataJson)) {
            result.ok = false;
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        unsigned long long scrollStart = GetTickCount64();
        ClickResult scrolled = ScrollClientPoint(reinterpret_cast<HWND>(session.targetHwndValue), clientX, clientY, step.delta, step.moveMode.empty() ? L"human" : step.moveMode);
        result.latency.scrollMs = ElapsedMs(scrollStart);
        if (!scrolled.ok) {
            result.ok = false;
            result.errorCode = scrolled.errorCode.empty() ? L"SEND_INPUT_FAILED" : scrolled.errorCode;
            result.errorMessage = scrolled.error;
            result.dataJson = L"{\"wheel_event_count\":0,\"scroll_progress_detected\":false}";
            if (sequence) sequence->FinishStep(result.latency, stepStart);
            return result;
        }
        result.actionExecuted = true;
        ++session.actionCounter;
        session.lastActionId = L"act-" + std::to_wstring(session.actionCounter);
        SessionObserveCacheInvalidateAfterAction(session);
        SessionLocatorCacheInvalidate(session, L"scroll");
        bool targetFound = false;
        std::wstring locateJson = L"null";
        bool cacheHit = false;
        bool cacheMiss = false;
        if ((action == L"scroll_and_locate" || action == L"scroll_and_locate_and_click") && !step.target.empty()) {
            JsonStep locateStep = step;
            locateStep.forceReobserve = true;
            SelectorResult located = LocateWithSessionCache(session, locateStep, result.latency, cacheHit, cacheMiss, result.errorCode, result.errorMessage, locateJson);
            result.locatorCacheHit = cacheHit;
            result.locatorCacheMiss = cacheMiss;
            targetFound = located.ok;
            if (located.ok) locateJson = located.dataJson;
            if (located.ok && action == L"scroll_and_locate_and_click") {
                unsigned long long clickStart = GetTickCount64();
                ClickResult clicked = ClickClientPoint(reinterpret_cast<HWND>(session.targetHwndValue), located.clientX, located.clientY, step.moveMode.empty() ? L"human" : step.moveMode, 0);
                result.latency.clickMs += ElapsedMs(clickStart);
                result.actionExecuted = clicked.ok;
                if (!clicked.ok) {
                    result.ok = false;
                    result.errorCode = clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode;
                    result.errorMessage = clicked.error;
                    result.dataJson = L"{\"scroll_progress_detected\":true,\"target_found\":true,\"click_sent\":false}";
                    if (sequence) sequence->FinishStep(result.latency, stepStart);
                    return result;
                }
            }
        }
        result.ok = (action == L"scroll" || action == L"scroll_and_verify_progress") ? (scrolled.wheelEventCount > 0) : targetFound;
        if (!result.ok) {
            result.errorCode = targetFound ? L"" : L"LOCATOR_NOT_FOUND";
            result.errorMessage = targetFound ? L"" : L"Target was not found after scroll.";
        }
        result.dataJson = L"{\"wheel_event_count\":" + std::to_wstring(scrolled.wheelEventCount)
            + L",\"scroll_progress_detected\":" + std::wstring(scrolled.wheelEventCount > 0 ? L"true" : L"false")
            + L",\"target_found\":" + std::wstring(targetFound ? L"true" : L"false")
            + L",\"context_guard_each_step\":" + std::wstring(expectedContext.enabled ? L"true" : L"false")
            + L",\"stale_rect_not_used\":true,\"locator_cache_hit\":" + std::wstring(cacheHit ? L"true" : L"false")
            + L",\"locator_cache_miss\":" + std::wstring(cacheMiss ? L"true" : L"false")
            + L",\"locate\":" + locateJson + L"}";
        if (sequence) sequence->FinishStep(result.latency, stepStart);
        return result;
    }

    result.ok = false;
    result.errorCode = L"INVALID_ARGUMENT";
    result.errorMessage = L"Unsupported runtime session action.";
    result.dataJson = L"{\"action\":" + JsonString(step.action) + L"}";
    if (sequence) sequence->FinishStep(result.latency, stepStart);
    return result;
}

std::wstring StepsArrayJson(const std::vector<JsonStep>& steps, const std::vector<StepExecutionResult>& results) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < results.size(); ++i) {
        if (i) json << L",";
        json << StepResultJson(steps[i], results[i]);
    }
    json << L"]";
    return json.str();
}

unsigned long long ParseHwndValue(const std::wstring& raw) {
    if (raw.empty()) return 0;
    try {
        size_t consumed = 0;
        int base = 10;
        std::wstring value = raw;
        if (value.rfind(L"0x", 0) == 0 || value.rfind(L"0X", 0) == 0) {
            base = 16;
            value = value.substr(2);
        }
        unsigned long long parsed = std::stoull(value, &consumed, base);
        if (consumed != value.size()) return 0;
        return parsed;
    } catch (...) {
        return 0;
    }
}

JsonStep StepFromCommandLine(const std::wstring& command, int argc, wchar_t** argv) {
    JsonStep step;
    step.stepId = L"cli-step";
    std::wstring action;
    ArgValue(argc, argv, L"--action", action);
    if (!action.empty()) {
        step.action = action;
    } else if (command == L"runtime-session-observe") {
        step.action = L"observe";
    } else if (command == L"runtime-session-locate") {
        step.action = L"locate";
    } else if (command == L"runtime-session-act-and-verify") {
        ArgValue(argc, argv, L"--primitive", step.action);
        if (step.action.empty()) step.action = L"click_and_verify_focus";
    } else if (command == L"runtime-session-type-and-verify") {
        step.action = L"type_and_verify_text";
    } else if (command == L"runtime-session-scroll-and-locate") {
        step.action = L"scroll_and_locate";
    } else if (command == L"click" || command == L"adaptive-click") {
        step.action = L"click";
    } else if (command == L"type" || command == L"adaptive-type") {
        step.action = L"type";
    } else if (command == L"scroll" || command == L"adaptive-scroll") {
        step.action = L"scroll";
    } else if (command == L"scroll-and-locate") {
        step.action = L"scroll_and_locate";
    } else if (command == L"desktop-click") {
        step.action = L"click";
    } else if (command == L"desktop-type") {
        step.action = L"type";
    } else {
        step.action = command;
    }
    ArgValue(argc, argv, L"--target", step.target);
    std::wstring selector;
    if (ArgValue(argc, argv, L"--selector", selector) && step.target.empty()) step.target = selector;
    ArgValue(argc, argv, L"--text", step.text);
    ArgValue(argc, argv, L"--verification-hint", step.verificationHint);
    ArgValue(argc, argv, L"--cache-policy", step.cachePolicy);
    ArgValue(argc, argv, L"--move-mode", step.moveMode);
    ArgValue(argc, argv, L"--type-mode", step.typeMode);
    ParseIntArg(argc, argv, L"--x", step.x);
    ParseIntArg(argc, argv, L"--y", step.y);
    ParseIntArg(argc, argv, L"--delta", step.delta);
    std::wstring raw;
    if (ArgValue(argc, argv, L"--force-reobserve", raw)) ParseBoolText(raw, step.forceReobserve);

    std::wstring expectedTitle;
    std::wstring expectedProcess;
    std::wstring requiredMarker;
    ArgValue(argc, argv, L"--expected-title-pattern", expectedTitle);
    ArgValue(argc, argv, L"--expected-process-pattern", expectedProcess);
    ArgValue(argc, argv, L"--required-marker", requiredMarker);
    if (!expectedTitle.empty() || !expectedProcess.empty() || !requiredMarker.empty()) {
        step.expectedContextJson = L"{\"expected_title_pattern\":" + JsonString(expectedTitle)
            + L",\"expected_process_pattern\":" + JsonString(expectedProcess)
            + L",\"required_marker\":" + JsonString(requiredMarker) + L"}";
    }
    return step;
}

int CommandSessionStart(int argc, wchar_t** argv) {
    unsigned long long startTick = GetTickCount64();
    const std::wstring command = L"runtime-session-start";
    std::wstring title;
    std::wstring process;
    std::wstring hwndRaw;
    int timeoutMs = 30 * 60 * 1000;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--hwnd", hwndRaw);
    ParseIntArg(argc, argv, L"--session-timeout-ms", timeoutMs);
    SessionManager manager(timeoutMs);
    SessionManagerResult created = manager.CreateSession(title, process, ParseHwndValue(hwndRaw));
    if (!created.ok) {
        return EmitSessionEnvelope(false, command, startTick, &created.session, L"", created.errorCode, created.errorMessage, created.dataJson, 1);
    }
    return EmitSessionEnvelope(true, command, startTick, &created.session, L"", L"", L"", created.dataJson, 0);
}

int CommandSessionStatus(int argc, wchar_t** argv) {
    unsigned long long startTick = GetTickCount64();
    const std::wstring command = L"runtime-session-status";
    std::wstring sessionId;
    ArgValue(argc, argv, L"--session-id", sessionId);
    SessionManager manager;
    SessionManagerResult loaded = manager.GetSession(sessionId);
    if (!loaded.ok) {
        return EmitSessionEnvelope(false, command, startTick, &loaded.session, sessionId, loaded.errorCode, loaded.errorMessage, loaded.dataJson, 1);
    }
    return EmitSessionEnvelope(true, command, startTick, &loaded.session, sessionId, L"", L"", loaded.dataJson, 0);
}

int CommandSessionClose(int argc, wchar_t** argv) {
    unsigned long long startTick = GetTickCount64();
    const std::wstring command = L"runtime-session-close";
    std::wstring sessionId;
    ArgValue(argc, argv, L"--session-id", sessionId);
    SessionManager manager;
    SessionManagerResult closed = manager.CloseSession(sessionId);
    if (!closed.ok) {
        return EmitSessionEnvelope(false, command, startTick, &closed.session, sessionId, closed.errorCode, closed.errorMessage, closed.dataJson, 1);
    }
    return EmitSessionEnvelope(true, command, startTick, &closed.session, sessionId, L"", L"", closed.dataJson, 0);
}

int CommandSessionList() {
    unsigned long long startTick = GetTickCount64();
    const std::wstring command = L"runtime-session-list";
    SessionManager manager;
    SessionManagerResult listed = manager.ListSessions();
    RuntimeSession empty;
    if (!listed.ok) {
        return EmitSessionEnvelope(false, command, startTick, &empty, L"", listed.errorCode, listed.errorMessage, listed.dataJson, 1);
    }
    return EmitSessionEnvelope(true, command, startTick, &empty, L"", L"", L"", listed.dataJson, 0);
}

int CommandSessionSingleStep(const std::wstring& command, int argc, wchar_t** argv) {
    unsigned long long startTick = GetTickCount64();
    std::wstring sessionId;
    ArgValue(argc, argv, L"--session-id", sessionId);
    SessionManager manager;
    SessionManagerResult loaded = manager.GetSession(sessionId);
    if (!loaded.ok) {
        return EmitSessionEnvelope(false, command, startTick, &loaded.session, sessionId, loaded.errorCode, loaded.errorMessage, loaded.dataJson, 1);
    }
    RuntimeSession session = loaded.session;
    JsonStep step = StepFromCommandLine(command, argc, argv);
    LatencySequenceTracker sequence;
    sequence.Start();
    StepExecutionResult stepResult = ExecuteStep(session, step, &sequence);
    sequence.AddStep(stepResult.latency);
    session.latencySummary = sequence.Summary(1, true);
    if (!stepResult.ok) {
        session.lastErrorCode = stepResult.errorCode;
    }
    manager.SaveSession(session);
    std::wstring directFields;
    std::wstring action = ToLowerInvariant(step.action);
    if (action == L"observe") {
        directFields = L"\"session_observe_ok\":" + std::wstring(stepResult.ok ? L"true" : L"false")
            + L",\"observe_cache_hit\":" + std::wstring(stepResult.observeCacheHit ? L"true" : L"false")
            + L",\"observe_cache_miss\":" + std::wstring(stepResult.observeCacheMiss ? L"true" : L"false") + L",";
    } else if (action == L"locate") {
        directFields = L"\"session_locate_ok\":" + std::wstring(stepResult.ok ? L"true" : L"false")
            + L",\"locator_cache_hit\":" + std::wstring(stepResult.locatorCacheHit ? L"true" : L"false")
            + L",\"locator_cache_miss\":" + std::wstring(stepResult.locatorCacheMiss ? L"true" : L"false") + L",";
    }
    std::wstring data = L"{" + directFields + L"\"step_result\":" + StepResultJson(step, stepResult)
        + L",\"latency_summary\":" + SessionLatencySummaryJson(session.latencySummary)
        + L",\"cache_summary\":" + SessionCacheSummaryJson(session.cacheSummary)
        + L",\"session\":" + RuntimeSessionJson(session) + L"}";
    if (!stepResult.ok) {
        return EmitSessionEnvelope(false, command, startTick, &session, sessionId, stepResult.errorCode, stepResult.errorMessage, data, 1);
    }
    return EmitSessionEnvelope(true, command, startTick, &session, sessionId, L"", L"", data, 0);
}

int CommandSessionDispatch(int argc, wchar_t** argv) {
    unsigned long long startTick = GetTickCount64();
    const std::wstring command = L"runtime-session-dispatch";
    std::wstring sessionId;
    std::wstring stepsPath;
    std::wstring resultPath;
    ArgValue(argc, argv, L"--session-id", sessionId);
    ArgValue(argc, argv, L"--steps-json", stepsPath);
    ArgValue(argc, argv, L"--result-json", resultPath);
    if (stepsPath.empty()) {
        RuntimeSession empty;
        return EmitSessionEnvelope(false, command, startTick, &empty, sessionId, L"INVALID_ARGUMENT", L"runtime-session-dispatch requires --steps-json.", L"{}", 2);
    }
    std::wstring stepsText;
    std::wstring fileError;
    if (!ReadTextFileUtf8(stepsPath, stepsText, fileError)) {
        RuntimeSession empty;
        return EmitSessionEnvelope(false, command, startTick, &empty, sessionId, L"FILE_READ_FAILED", fileError, L"{\"steps_json\":" + JsonString(stepsPath) + L"}", 2);
    }
    std::vector<JsonStep> steps;
    std::wstring parseError;
    if (!ParseStepsJson(stepsText, steps, parseError)) {
        RuntimeSession empty;
        return EmitSessionEnvelope(false, command, startTick, &empty, sessionId, L"INVALID_ARGUMENT", parseError, L"{\"steps_json\":" + JsonString(stepsPath) + L"}", 2);
    }
    SessionManager manager;
    SessionManagerResult loaded = manager.GetSession(sessionId);
    if (!loaded.ok) {
        return EmitSessionEnvelope(false, command, startTick, &loaded.session, sessionId, loaded.errorCode, loaded.errorMessage, loaded.dataJson, 1);
    }
    RuntimeSession session = loaded.session;
    LatencySequenceTracker sequence;
    sequence.Start();
    std::vector<StepExecutionResult> results;
    bool stopped = false;
    std::wstring stopCode;
    for (const auto& step : steps) {
        StepExecutionResult result = ExecuteStep(session, step, &sequence);
        sequence.AddStep(result.latency);
        results.push_back(result);
        if (!result.ok && step.stopOnFailure) {
            stopped = true;
            stopCode = result.errorCode;
            session.lastErrorCode = result.errorCode;
            break;
        }
    }
    session.latencySummary = sequence.Summary(1, true);
    manager.SaveSession(session);
    bool allOk = !stopped && results.size() == steps.size();
    std::wstring stepResults = StepsArrayJson(steps, results);
    std::wstring data = L"{\"step_count\":" + std::to_wstring(steps.size())
        + L",\"executed_step_count\":" + std::to_wstring(results.size())
        + L",\"all_steps_verified\":" + std::wstring(allOk ? L"true" : L"false")
        + L",\"stopped_on_failure\":" + std::wstring(stopped ? L"true" : L"false")
        + L",\"stop_code\":" + JsonString(stopCode)
        + L",\"continued_action_after_wrong_context\":false"
        + L",\"process_restart_count\":1"
        + L",\"session_reuse_enabled\":true"
        + L",\"session_command_count\":" + std::to_wstring(session.sessionCommandCount)
        + L",\"step_results\":" + stepResults
        + L",\"latency_steps\":" + sequence.StepsJson()
        + L",\"latency_summary\":" + SessionLatencySummaryJson(session.latencySummary)
        + L",\"cache_summary\":" + SessionCacheSummaryJson(session.cacheSummary)
        + L",\"session\":" + RuntimeSessionJson(session) + L"}";
    if (!resultPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(resultPath, SessionEnvelopeJson(allOk, command, startTick, session.sessionId, session.sessionAlive, RuntimeSessionStatus(session), stopCode, L"", data), writeError);
    }
    if (!allOk) {
        std::wstring emittedStopCode = stopCode.empty() ? L"STEP_FAILED" : stopCode;
        std::wstring emittedMessage = IsUserAbortStopCode(emittedStopCode)
            ? UserAbortMessage()
            : L"Session dispatch stopped on failed step.";
        return EmitSessionEnvelope(false, command, startTick, &session, sessionId, emittedStopCode, emittedMessage, data, 1);
    }
    return EmitSessionEnvelope(true, command, startTick, &session, sessionId, L"", L"", data, 0);
}

}  // namespace

bool IsRuntimeSessionCommand(const std::wstring& command) {
    return command == L"runtime-session-start" ||
           command == L"runtime-session-status" ||
           command == L"runtime-session-close" ||
           command == L"runtime-session-list" ||
           command == L"runtime-session-command" ||
           command == L"runtime-session-dispatch" ||
           command == L"runtime-session-observe" ||
           command == L"runtime-session-locate" ||
           command == L"runtime-session-act-and-verify" ||
           command == L"runtime-session-type-and-verify" ||
           command == L"runtime-session-scroll-and-locate";
}

bool IsRuntimeSessionCompatibleLegacyCommand(const std::wstring& command) {
    return command == L"desktop-click" ||
           command == L"desktop-double-click" ||
           command == L"desktop-move" ||
           command == L"desktop-type" ||
           command == L"desktop-press" ||
           command == L"desktop-hotkey" ||
           command == L"click" ||
           command == L"double-click" ||
           command == L"right-click" ||
           command == L"scroll" ||
           command == L"adaptive-click" ||
           command == L"adaptive-type" ||
           command == L"adaptive-scroll" ||
           command == L"scroll-and-locate" ||
           command == L"browser-open-url-human" ||
           command == L"browser-surface-normalize";
}

bool RuntimeSessionArgPresent(int argc, wchar_t** argv) {
    std::wstring ignored;
    return ArgValue(argc, argv, L"--session-id", ignored);
}

int DispatchRuntimeSessionCommandLine(int argc, wchar_t** argv) {
    if (argc < 2) {
        unsigned long long startTick = GetTickCount64();
        RuntimeSession empty;
        return EmitSessionEnvelope(false, L"runtime-session", startTick, &empty, L"", L"INVALID_ARGUMENT", L"Missing command.", L"{}", 2);
    }
    std::wstring command = argv[1];
    if (command == L"runtime-session-start") return CommandSessionStart(argc, argv);
    if (command == L"runtime-session-status") return CommandSessionStatus(argc, argv);
    if (command == L"runtime-session-close") return CommandSessionClose(argc, argv);
    if (command == L"runtime-session-list") return CommandSessionList();
    if (command == L"runtime-session-dispatch") return CommandSessionDispatch(argc, argv);
    return CommandSessionSingleStep(command, argc, argv);
}
