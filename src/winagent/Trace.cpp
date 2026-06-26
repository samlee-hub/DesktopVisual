#include "Trace.h"

#include "ProjectRoot.h"
#include "UserAbortController.h"

#include <cstdio>
#include <iomanip>
#include <sstream>

TraceTarget NoTraceTarget() {
    return TraceTarget{};
}

TraceTarget MakeTraceTarget(const WindowInfo& window) {
    TraceTarget target;
    target.hasTarget = true;
    target.title = window.title;
    target.hwnd = FormatHwnd(window.hwnd);
    target.pid = window.pid;
    return target;
}

std::wstring NowTimestamp() {
    SYSTEMTIME time;
    GetLocalTime(&time);
    wchar_t buffer[32] = {};
    swprintf_s(
        buffer,
        L"%04u-%02u-%02u %02u:%02u:%02u",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond);
    return buffer;
}

long long ElapsedMs(ULONGLONG startTick) {
    return static_cast<long long>(GetTickCount64() - startTick);
}

std::wstring JsonEscape(const std::wstring& value) {
    std::wstring escaped;
    for (wchar_t ch : value) {
        switch (ch) {
            case L'\\':
                escaped += L"\\\\";
                break;
            case L'"':
                escaped += L"\\\"";
                break;
            case L'\n':
                escaped += L"\\n";
                break;
            case L'\r':
                escaped += L"\\r";
                break;
            case L'\t':
                escaped += L"\\t";
                break;
            default:
                if (ch < 0x20 || ch > 0x7e) {
                    std::wstringstream stream;
                    stream << L"\\u" << std::hex << std::setw(4) << std::setfill(L'0') << static_cast<int>(ch);
                    escaped += stream.str();
                } else {
                    escaped += ch;
                }
                break;
        }
    }
    return escaped;
}

std::wstring JsonString(const std::wstring& value) {
    return L"\"" + JsonEscape(value) + L"\"";
}

std::wstring ErrorMessageForCode(const std::wstring& code) {
    if (code == L"WINDOW_NOT_FOUND") return L"Target window was not found.";
    if (code == L"WINDOW_NOT_UNIQUE") return L"Target window title matched multiple windows.";
    if (code == L"WINDOW_NOT_VISIBLE") return L"Target window was not visible.";
    if (code == L"WINDOW_FOCUS_FAILED") return L"Target window could not be focused.";
    if (code == L"INVALID_ARGUMENT") return L"Invalid command argument.";
    if (code == L"INVALID_SELECTOR") return L"Invalid selector.";
    if (code == L"LOCATOR_NOT_FOUND") return L"Selector locator found no matches.";
    if (code == L"LOCATOR_NOT_UNIQUE") return L"Selector locator matched multiple targets.";
    if (code == L"SCREENSHOT_FAILED") return L"Screenshot failed.";
    if (code == L"CURSOR_MOVE_FAILED") return L"Cursor movement failed.";
    if (code == L"SEND_INPUT_FAILED") return L"SendInput failed.";
    if (code == L"FILE_NOT_FOUND") return L"File was not found.";
    if (code == L"FILE_READ_FAILED") return L"File could not be read.";
    if (code == L"ASSERTION_FAILED") return L"Case assertion failed.";
    if (code == L"CASE_PARSE_FAILED") return L"Case file could not be parsed.";
    if (code == L"CASE_STEP_LIMIT_EXCEEDED") return L"Case exceeded the maximum step count.";
    if (code == L"UIA_INIT_FAILED") return L"UI Automation initialization failed.";
    if (code == L"UIA_TREE_FAILED") return L"UI Automation tree read failed.";
    if (code == L"UIA_ELEMENT_NOT_FOUND") return L"UI Automation element was not found.";
    if (code == L"UIA_ELEMENT_NOT_UNIQUE") return L"UI Automation element match was not unique.";
    if (code == L"OCR_INIT_FAILED") return L"OCR initialization failed.";
    if (code == L"OCR_UNAVAILABLE") return L"OCR is unavailable in this build.";
    if (code == L"OCR_LANGUAGE_UNAVAILABLE") return L"No usable Windows OCR language is available.";
    if (code == L"OCR_TEXT_NOT_FOUND") return L"OCR text was not found.";
    if (code == L"OCR_TEXT_NOT_UNIQUE") return L"OCR text match was not unique.";
    if (code == L"OCR_FAILED") return L"OCR failed.";
    if (code == L"IMAGE_FILE_NOT_FOUND") return L"Image file was not found.";
    if (code == L"IMAGE_UNSUPPORTED_FORMAT") return L"Image format is unsupported.";
    if (code == L"IMAGE_MATCH_NOT_FOUND") return L"Image template match was not found.";
    if (code == L"IMAGE_MATCH_NOT_UNIQUE") return L"Image template match was not unique.";
    if (code == L"IMAGE_MATCH_FAILED") return L"Image template matching failed.";
    if (code == L"MOTION_PROFILE_NOT_FOUND") return L"Operator motion profile was not found.";
    if (code == L"MOTION_PROFILE_INVALID") return L"Operator motion profile is invalid.";
    if (code == L"MOTION_PROFILE_INSUFFICIENT_SAMPLES") return L"Operator motion profile has insufficient samples.";
    if (code == L"MOTION_PROFILE_NOT_HUMAN") return L"Operator motion profile is not a human profile.";
    if (code == L"MOTION_PROFILE_SOURCE_REQUIRED") return L"Operator motion profile source is required.";
    if (code == L"MOTION_PROFILE_TEST_ONLY") return L"Operator motion profile is test-only unless explicitly allowed.";
    if (code == L"EMERGENCY_STOPPED") return L"Emergency stop key stopped motion recording.";
    if (code == L"FULL_ACCESS_SESSION_REQUIRED") return L"FULL_ACCESS requires a valid temporary session.";
    if (code == L"FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION") return L"FULL_ACCESS requires local interactive CLI confirmation.";
    if (code == L"STOP_ACTIVE_PROTECTION") return L"Active protection was detected; stop without bypass.";
    if (code == L"USER_TAKEOVER_REQUIRED") return L"User takeover is required.";
    if (code == L"CREDENTIAL_INPUT_DETECTED") return L"Credential input was detected.";
    if (code == L"CAPTCHA_DETECTED") return L"Captcha or verification challenge was detected.";
    if (code == L"ANTI_AUTOMATION_DETECTED") return L"Anti-automation or AI-detection control was detected.";
    if (code == L"ANTI_CHEAT_DETECTED") return L"Anti-cheat protected software was detected.";
    if (code == L"PROTECTED_DESKTOP_DETECTED") return L"Protected desktop or UAC surface was detected.";
    if (code == L"LOOP_GUARD_STOP") return L"Loop guard stopped the action.";
    if (code == L"WINDOW_SPAWN_LOOP") return L"Window spawn loop guard stopped the action.";
    if (code == L"URL_REDIRECT_LOOP") return L"URL redirect loop guard stopped navigation.";
    if (code == L"NO_PROGRESS_DETECTED") return L"No progress was detected.";
    if (code == L"REPEATED_ACTION_LIMIT") return L"Repeated action limit was reached.";
    if (code == L"STOP_SESSION_TARGET_STALE") return L"Runtime session target is stale.";
    if (code == L"STOP_SESSION_WINDOW_CLOSED") return L"Runtime session target window was closed.";
    if (code == L"STOP_SESSION_FOREGROUND_CHANGED") return L"Runtime session foreground context changed.";
    if (code == L"STOP_SESSION_EXPIRED") return L"Runtime session expired.";
    if (code == L"STOP_SESSION_NOT_FOUND") return L"Runtime session was not found.";
    if (code == L"STOP_SESSION_CLOSED") return L"Runtime session is closed.";
    if (code == UserAbortStopCode()) return UserAbortMessage();
    if (code == L"STOP_TARGET_STALE") return L"Target is stale.";
    if (code == L"FIELD_NOT_UNIQUE") return L"Form field was not unique.";
    if (code == L"FIELD_CONFIDENCE_LOW") return L"Form field confidence was too low.";
    if (code == L"AUDIT_LOG_FAILED") return L"Audit log write failed.";
    return L"Unknown error.";
}

std::wstring TargetJson(const TraceTarget& target) {
    if (!target.hasTarget) {
        return L"null";
    }

    std::wstringstream json;
    json << L"{\"title\":" << JsonString(target.title)
         << L",\"hwnd\":" << JsonString(target.hwnd)
         << L",\"pid\":" << target.pid
         << L"}";
    return json.str();
}

std::wstring CommandSuccessJson(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& dataJson) {
    std::wstringstream json;
    json << L"{\"ok\":true"
         << L",\"command\":" << JsonString(command)
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << ElapsedMs(startTick)
         << L",\"target\":" << TargetJson(target)
         << L",\"data\":" << (dataJson.empty() ? L"{}" : dataJson)
         << L"}";
    return json.str();
}

std::wstring CommandFailureJson(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson) {
    std::wstring outputData = IsUserAbortStopCode(errorCode)
        ? MergeUserAbortEvidenceJson(dataJson)
        : (dataJson.empty() ? L"{}" : dataJson);
    std::wstringstream json;
    json << L"{\"ok\":false"
         << L",\"command\":" << JsonString(command)
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << ElapsedMs(startTick)
         << L",\"target\":" << TargetJson(target)
         << L",\"error\":{\"code\":" << JsonString(errorCode)
         << L",\"message\":" << JsonString(errorMessage.empty() ? ErrorMessageForCode(errorCode) : errorMessage)
         << L"}"
         << L",\"data\":" << outputData
         << L"}";
    return json.str();
}

std::wstring AuditEscape(const std::wstring& value) {
    std::wstring escaped;
    for (wchar_t ch : value) {
        if (ch == L'\\' || ch == L'"') {
            escaped += L'\\';
            escaped += ch;
        } else if (ch == L'\r' || ch == L'\n' || ch == L'\t') {
            escaped += L' ';
        } else {
            escaped += ch;
        }
    }
    return escaped;
}

bool AppendAuditLine(
    const std::wstring& command,
    const std::wstring& targetTitle,
    const std::wstring& result,
    const std::wstring& errorCode,
    long long durationMs,
    const std::wstring& data) {
    FILE* file = nullptr;
    EnsureDirectoryPath(ArtifactsPath());
    std::wstring auditPath = ArtifactsPath(L"agent_audit.log");
    if (_wfopen_s(&file, auditPath.c_str(), L"a, ccs=UTF-8") != 0 || !file) {
        return false;
    }

    fwprintf(
        file,
        L"timestamp=\"%ls\" command=\"%ls\" target_title=\"%ls\" result=\"%ls\" error_code=\"%ls\" duration_ms=%lld data=\"%ls\"\n",
        AuditEscape(NowTimestamp()).c_str(),
        AuditEscape(command).c_str(),
        AuditEscape(targetTitle).c_str(),
        AuditEscape(result).c_str(),
        AuditEscape(errorCode).c_str(),
        durationMs,
        AuditEscape(data).c_str());
    fclose(file);
    return true;
}
