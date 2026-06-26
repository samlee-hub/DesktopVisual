#include "CaseRunner.h"

#include "InputController.h"
#include "ObserveController.h"
#include "OcrController.h"
#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Selector.h"
#include "Screenshot.h"
#include "Trace.h"
#include "UserAbortController.h"
#include "UiaController.h"
#include "WindowFinder.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) {
        return L"";
    }
    int required = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (required <= 0) {
        required = MultiByteToWideChar(CP_ACP, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
        if (required <= 0) {
            return L"";
        }
        std::wstring fallback(static_cast<size_t>(required), L'\0');
        MultiByteToWideChar(CP_ACP, 0, value.data(), static_cast<int>(value.size()), fallback.data(), required);
        return fallback;
    }

    std::wstring result(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), required);
    return result;
}

std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) {
        return "";
    }
    int required = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (required <= 0) {
        return "";
    }
    std::string result(static_cast<size_t>(required - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), required, nullptr, nullptr);
    return result;
}

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && (iswspace(value[first]) || value[first] == 0xFEFF)) {
        ++first;
    }
    size_t last = value.size();
    while (last > first && iswspace(value[last - 1])) {
        --last;
    }
    return value.substr(first, last - first);
}

std::vector<std::wstring> SplitWords(const std::wstring& value) {
    std::wistringstream stream(value);
    std::vector<std::wstring> words;
    std::wstring word;
    while (stream >> word) {
        words.push_back(word);
    }
    return words;
}

std::wstring RestAfterFirstWord(const std::wstring& value) {
    size_t firstSpace = value.find_first_of(L" \t");
    if (firstSpace == std::wstring::npos) {
        return L"";
    }
    return Trim(value.substr(firstSpace + 1));
}

std::wstring Basename(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return path;
    }
    return path.substr(slash + 1);
}

std::wstring ReplaceAll(std::wstring value, const std::wstring& needle, const std::wstring& replacement) {
    size_t pos = 0;
    while ((pos = value.find(needle, pos)) != std::wstring::npos) {
        value.replace(pos, needle.size(), replacement);
        pos += replacement.size();
    }
    return value;
}

std::wstring ExpandProjectRootVars(const std::wstring& value) {
    std::wstring expanded = ReplaceAll(value, L"${PROJECT_ROOT}", ProjectRootPath());
    expanded = ReplaceAll(expanded, L"%PROJECT_ROOT%", ProjectRootPath());
    return expanded;
}

bool ResolveUniqueWindow(const std::wstring& title, WindowInfo& selected, std::wstring& errorCode, std::wstring& error) {
    if (title.empty()) {
        errorCode = L"WINDOW_NOT_FOUND";
        error = L"target_title is required before this action.";
        return false;
    }

    auto matches = FindWindowsByTitleSubstring(title);
    if (matches.empty()) {
        errorCode = L"WINDOW_NOT_FOUND";
        error = L"No visible top-level window matched target_title.";
        return false;
    }
    if (matches.size() > 1) {
        errorCode = L"WINDOW_NOT_UNIQUE";
        error = L"Multiple visible top-level windows matched target_title.";
        return false;
    }

    selected = matches.front();
    return true;
}

bool EnforceWindowSafety(const WindowInfo& window, const std::wstring& requestedTitle, std::wstring& errorCode, std::wstring& error, std::wstring& dataJson) {
    SafetyCheckResult safety = CheckWindowSafety(window, requestedTitle);
    if (safety.ok) {
        return true;
    }
    errorCode = safety.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : safety.errorCode;
    error = safety.message.empty() ? L"Safety policy denied this action." : safety.message;
    dataJson = L"{\"target_title\":" + JsonString(requestedTitle)
        + L",\"actual_title\":" + JsonString(window.title)
        + L",\"process_name\":" + JsonString(safety.processName)
        + L"}";
    return false;
}

bool ParseInt(const std::wstring& value, int& parsed) {
    try {
        size_t consumed = 0;
        parsed = std::stoi(value, &consumed, 10);
        return consumed == value.size();
    } catch (...) {
        return false;
    }
}

std::wstring StepJson(bool ok, const std::wstring& errorCode, const std::wstring& message, const std::wstring& data) {
    std::wstringstream json;
    json << L"{\"ok\":" << (ok ? L"true" : L"false")
         << L",\"error_code\":" << JsonString(errorCode)
         << L",\"message\":" << JsonString(message)
         << L",\"data\":" << (data.empty() ? L"{}" : data)
         << L"}";
    return json.str();
}

void FinishStep(
    CaseReport& report,
    CaseStepRecord& step,
    ULONGLONG stepStartTick,
    bool ok,
    const std::wstring& errorCode,
    const std::wstring& message,
    const std::wstring& dataJson) {
    step.endedAt = CurrentTimestamp();
    step.durationMs = ElapsedMs(stepStartTick);
    step.ok = ok;
    step.errorCode = errorCode;
    step.message = message;
    step.jsonOutputSummary = StepJson(ok, errorCode, message, dataJson);
    report.steps.push_back(step);
    if (dataJson.find(L"\"focus_verified\"") != std::wstring::npos) {
        report.focusAndSafety.push_back(dataJson);
    }
    if (ok) {
        report.passedStepCount++;
    } else if (report.failureErrorCode.empty()) {
        report.failureErrorCode = errorCode;
        report.failureMessage = message;
        report.failedStepIndex = step.index;
    }
    AppendAuditLine(step.action, report.targetTitle, ok ? L"ok" : L"failed", errorCode, step.durationMs, dataJson.empty() ? message : dataJson);
}

void FinishUserAbortStep(CaseReport& report, CaseStepRecord& step, ULONGLONG stepStartTick) {
    FinishStep(report, step, stepStartTick, false, UserAbortStopCode(), UserAbortMessage(), UserAbortEvidenceJson());
}

bool SleepCaseInterruptible(DWORD totalMs) {
    DWORD slept = 0;
    while (slept < totalMs) {
        if (IsEmergencyStopPressed()) {
            ReleaseUserAbortInputState();
            return false;
        }
        DWORD chunk = (totalMs - slept) < 10 ? (totalMs - slept) : 10;
        Sleep(chunk);
        slept += chunk;
    }
    return !IsEmergencyStopPressed();
}

std::wstring FormatClickDetails(const ClickResult& action) {
    std::wstringstream details;
    details << L"target_client_x=" << action.targetClientX
            << L" target_client_y=" << action.targetClientY
            << L" target_screen_x=" << action.targetScreenX
            << L" target_screen_y=" << action.targetScreenY
            << L" cursor_before_x=" << action.cursorBeforeX
            << L" cursor_before_y=" << action.cursorBeforeY
            << L" cursor_after_x=" << action.cursorAfterX
            << L" cursor_after_y=" << action.cursorAfterY
            << L" move_mode=" << action.moveMode
            << L" move_duration_ms=" << action.moveDurationMs
            << L" move_steps=" << action.moveSteps
            << L" move_profile=" << action.moveProfile
            << L" path_type=" << action.pathType
            << L" distance_px=" << action.distancePx
            << L" duration_ms=" << action.durationMs
            << L" step_count=" << action.stepCount
            << L" emergency_stop_checked=" << (action.emergencyStopChecked ? L"true" : L"false");
    return details.str();
}

std::wstring FormatDragDetails(const DragResult& action) {
    std::wstringstream details;
    details << L"from_client_x=" << action.fromClientX
            << L" from_client_y=" << action.fromClientY
            << L" to_client_x=" << action.toClientX
            << L" to_client_y=" << action.toClientY
            << L" from_screen_x=" << action.fromScreenX
            << L" from_screen_y=" << action.fromScreenY
            << L" to_screen_x=" << action.toScreenX
            << L" to_screen_y=" << action.toScreenY
            << L" mouse_down_sent=" << (action.mouseDownSent ? L"true" : L"false")
            << L" mouse_up_sent=" << (action.mouseUpSent ? L"true" : L"false")
            << L" move_mode=" << action.moveMode
            << L" move_profile=" << action.moveProfile
            << L" path_type=" << action.pathType
            << L" distance_px=" << action.distancePx
            << L" duration_ms=" << action.durationMs
            << L" step_count=" << action.stepCount
            << L" emergency_stop_checked=" << (action.emergencyStopChecked ? L"true" : L"false");
    return details.str();
}

std::wstring FormatTypeDetails(const TypeResult& action) {
    std::wstringstream details;
    details << L"type_mode=" << action.typeMode
            << L" char_delay_ms=" << action.charDelayMs
            << L" text_length=" << action.textLength;
    return details.str();
}

bool IsMotionModeAllowed(const std::wstring& mode) {
    return mode == L"instant" || mode == L"human" || mode == L"fast-human" || mode == L"demo-human" || mode == L"operator-human";
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

std::wstring HwndJson(HWND hwnd) {
    return hwnd ? JsonString(FormatHwnd(hwnd)) : L"null";
}

std::wstring ActionFocusFields(
    const WindowInfo& window,
    const std::wstring& requestedTitle,
    HWND foregroundBefore,
    HWND foregroundAfter,
    bool focusVerified) {
    std::wstringstream fields;
    fields << L"\"requested_title\":" << JsonString(requestedTitle)
           << L",\"actual_title\":" << JsonString(window.title)
           << L",\"hwnd\":" << JsonString(FormatHwnd(window.hwnd))
           << L",\"pid\":" << window.pid
           << L",\"process_name\":" << JsonString(ProcessNameForPid(window.pid))
           << L",\"foreground_before\":" << HwndJson(foregroundBefore)
           << L",\"foreground_after\":" << HwndJson(foregroundAfter)
           << L",\"focus_verified\":" << (focusVerified ? L"true" : L"false");
    return fields.str();
}

bool ElementCenterClientPoint(HWND hwnd, const UiaElementInfo& element, int& clientX, int& clientY) {
    int screenX = element.rect.left + ((element.rect.right - element.rect.left) / 2);
    int screenY = element.rect.top + ((element.rect.bottom - element.rect.top) / 2);
    POINT point = {screenX, screenY};
    if (!ScreenToClient(hwnd, &point)) {
        return false;
    }
    clientX = point.x;
    clientY = point.y;
    return true;
}

std::wstring UiaActionData(
    const std::wstring& actionMethod,
    const UiaElementInfo& element,
    const std::wstring& result,
    const std::wstring& extra = L"") {
    std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":" + JsonString(actionMethod)
        + L",\"element_name\":" + JsonString(element.name)
        + L",\"control_type\":" + JsonString(element.controlType)
        + L",\"rect\":" + RectJson(element.rect)
        + L",\"result\":" + JsonString(result);
    if (!extra.empty()) {
        data += L"," + extra;
    }
    data += L"}";
    return data;
}

}  // namespace

FileReadResult ReadTextFile(const std::wstring& path) {
    FileReadResult result;
    DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        result.errorCode = L"FILE_NOT_FOUND";
        result.error = L"File does not exist.";
        return result;
    }

    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        result.errorCode = L"FILE_READ_FAILED";
        result.error = L"Could not open file.";
        return result;
    }

    std::string bytes;
    char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) {
            bytes.append(buffer, read);
        }
        if (read < sizeof(buffer)) {
            if (ferror(file)) {
                fclose(file);
                result.errorCode = L"FILE_READ_FAILED";
                result.error = L"Failed while reading file.";
                return result;
            }
            break;
        }
    }
    fclose(file);

    result.ok = true;
    result.content = Utf8ToWide(bytes);
    return result;
}

bool ReadAllowedTextFile(const std::wstring& path, FileReadResult& read, std::wstring& normalizedPath) {
    std::wstring safetyError;
    if (!IsReadPathAllowed(path, normalizedPath, safetyError)) {
        read.errorCode = L"SAFETY_POLICY_DENIED";
        read.error = safetyError;
        return false;
    }
    read = ReadTextFile(normalizedPath);
    return read.ok;
}

bool WriteUtf8TextFile(const std::wstring& path, const std::wstring& content, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || !file) {
        error = L"Could not open output file.";
        return false;
    }
    std::string bytes = WideToUtf8(content);
    bool ok = bytes.empty() || fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size();
    fclose(file);
    if (!ok) {
        error = L"Could not write output file.";
    }
    return ok;
}

// ===================================================================
// Case v2 parsing infrastructure
// ===================================================================
namespace {

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

struct V2Param {
    std::wstring key;
    std::wstring value;
};

std::wstring GetParam(const std::vector<V2Param>& params, const std::wstring& key, const std::wstring& defaultValue = L"") {
    for (const auto& p : params) {
        if (p.key == key) {
            return p.value;
        }
    }
    return defaultValue;
}

bool HasParam(const std::vector<V2Param>& params, const std::wstring& key) {
    for (const auto& p : params) {
        if (p.key == key) {
            return true;
        }
    }
    return false;
}

std::wstring SubstituteVars(const std::wstring& value, const std::map<std::wstring, std::wstring>& vars) {
    std::wstring result;
    result.reserve(value.size());
    for (size_t i = 0; i < value.size(); ++i) {
        if (value[i] == L'$' && i + 1 < value.size() && value[i + 1] == L'{') {
            size_t end = value.find(L'}', i + 2);
            if (end != std::wstring::npos) {
                std::wstring varName = value.substr(i + 2, end - i - 2);
                if (varName == L"PROJECT_ROOT") {
                    result += ProjectRootPath();
                    i = end;
                    continue;
                }
                auto it = vars.find(varName);
                if (it != vars.end()) {
                    result += it->second;
                }
                i = end;
                continue;
            }
        }
        result += value[i];
    }
    return result;
}

bool ParseV2Line(const std::wstring& line, std::wstring& command, std::vector<V2Param>& params, std::wstring& error) {
    params.clear();
    size_t pos = 0;
    size_t len = line.size();

    // Skip leading whitespace
    while (pos < len && iswspace(line[pos])) { ++pos; }
    if (pos >= len || line[pos] == L'#') {
        command = L"";
        return true;  // empty / comment line
    }

    // Read command (first word)
    size_t cmdStart = pos;
    while (pos < len && !iswspace(line[pos]) && line[pos] != L'=') { ++pos; }
    command = line.substr(cmdStart, pos - cmdStart);

    // Handle command=value syntax (unnamed first parameter)
    if (pos < len && line[pos] == L'=') {
        ++pos;  // skip '='
        if (pos >= len) {
            error = L"Missing value after '=' for command '" + command + L"'";
            return false;
        }
        std::wstring value;
        if (line[pos] == L'"') {
            ++pos;
            bool closed = false;
            while (pos < len) {
                if (line[pos] == L'\\' && pos + 1 < len) {
                    wchar_t next = line[pos + 1];
                    if (next == L'"') { value += L'"'; pos += 2; continue; }
                    if (next == L'\\') { value += L'\\'; pos += 2; continue; }
                    if (next == L'n') { value += L'\n'; pos += 2; continue; }
                    value += line[pos]; ++pos; continue;
                }
                if (line[pos] == L'"') { ++pos; closed = true; break; }
                value += line[pos];
                ++pos;
            }
            if (!closed) {
                error = L"Unclosed quoted string for command '" + command + L"'";
                return false;
            }
        } else {
            size_t valStart = pos;
            while (pos < len && !iswspace(line[pos]) && line[pos] != L'#') { ++pos; }
            value = line.substr(valStart, pos - valStart);
        }
        params.push_back({L"value", value});
    }

    // Parse key=value pairs
    while (pos < len) {
        // Skip whitespace
        while (pos < len && iswspace(line[pos])) { ++pos; }
        if (pos >= len || line[pos] == L'#') { break; }

        // Read key (or bare flag word)
        size_t keyStart = pos;
        while (pos < len && !iswspace(line[pos]) && line[pos] != L'=') { ++pos; }
        std::wstring key = line.substr(keyStart, pos - keyStart);
        if (key.empty()) { break; }

        // Bare word flag (no '=' follows) - treat as key with empty value
        if (pos >= len || line[pos] != L'=') {
            params.push_back({key, L""});
            continue;
        }
        ++pos;  // skip '='

        // Read value
        if (pos >= len) {
            error = L"Missing value for key '" + key + L"'";
            return false;
        }

        std::wstring value;
        if (line[pos] == L'"') {
            ++pos;  // skip opening "
            bool closed = false;
            while (pos < len) {
                if (line[pos] == L'\\' && pos + 1 < len) {
                    wchar_t next = line[pos + 1];
                    if (next == L'"') { value += L'"'; pos += 2; continue; }
                    if (next == L'\\') { value += L'\\'; pos += 2; continue; }
                    if (next == L'n') { value += L'\n'; pos += 2; continue; }
                    value += line[pos]; ++pos; continue;
                }
                if (line[pos] == L'"') { ++pos; closed = true; break; }
                value += line[pos];
                ++pos;
            }
            if (!closed) {
                error = L"Unclosed quoted string for key '" + key + L"'";
                return false;
            }
        } else {
            size_t valStart = pos;
            while (pos < len && !iswspace(line[pos]) && line[pos] != L'#') { ++pos; }
            value = line.substr(valStart, pos - valStart);
        }
        params.push_back({key, value});
    }

    return true;
}

int ParseIntParam(const std::vector<V2Param>& params, const std::wstring& key, int defaultValue) {
    std::wstring raw = GetParam(params, key);
    if (raw.empty()) { return defaultValue; }
    try {
        size_t consumed = 0;
        int val = std::stoi(raw, &consumed, 10);
        if (consumed == raw.size()) { return val; }
    } catch (...) {}
    return defaultValue;
}

bool ExecuteWaitUntilV2(
    CaseReport& report,
    CaseStepRecord& step,
    ULONGLONG stepStartTick,
    const std::vector<V2Param>& params,
    const std::wstring& targetTitle,
    const std::map<std::wstring, std::wstring>& vars,
    bool& failed) {

    std::wstring selector = SubstituteVars(GetParam(params, L"selector"), vars);
    std::wstring filePath = SubstituteVars(GetParam(params, L"path"), vars);
    std::wstring fileText = SubstituteVars(GetParam(params, L"text"), vars);
    std::wstring winTitle = SubstituteVars(GetParam(params, L"window_title_contains"), vars);
    std::wstring ocrText = SubstituteVars(GetParam(params, L"text_contains"), vars);
    int timeoutMs = ParseIntParam(params, L"timeout_ms", 5000);

    CaseV2WaitUntilRecord wr;
    wr.stepIndex = step.index;
    wr.timeoutMs = timeoutMs;

    ULONGLONG waitStart = GetTickCount64();
    bool conditionMet = false;

    if (!selector.empty()) {
        wr.conditionType = L"selector";
        wr.selector = selector;
        while (ElapsedMs(waitStart) < timeoutMs) {
            if (IsEmergencyStopPressed()) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
            WindowInfo w;
            std::wstring ec, em;
            if (ResolveUniqueWindow(targetTitle, w, ec, em)) {
                if (selector.rfind(L"text:", 0) == 0) {
                    std::wstring safetyData;
                    if (!EnforceWindowSafety(w, targetTitle, ec, em, safetyData)) {
                        FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                        failed = true;
                        return false;
                    }
                }
                SelectorResult sr = LocateSelector(w.hwnd, selector);
                if (sr.ok) { conditionMet = true; break; }
            }
            if (!SleepCaseInterruptible(200)) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
        }
    } else if (!filePath.empty() && !fileText.empty()) {
        wr.conditionType = L"file_contains";
        wr.path = filePath;
        wr.text = fileText;
        while (ElapsedMs(waitStart) < timeoutMs) {
            if (IsEmergencyStopPressed()) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
            FileReadResult fr;
            std::wstring normalizedPath;
            ReadAllowedTextFile(filePath, fr, normalizedPath);
            if (fr.ok && fr.content.find(fileText) != std::wstring::npos) { conditionMet = true; break; }
            if (!SleepCaseInterruptible(200)) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
        }
    } else if (!winTitle.empty()) {
        wr.conditionType = L"window_title_contains";
        wr.text = winTitle;
        while (ElapsedMs(waitStart) < timeoutMs) {
            if (IsEmergencyStopPressed()) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
            auto wins = FindWindowsByTitleSubstring(winTitle);
            if (!wins.empty()) { conditionMet = true; break; }
            if (!SleepCaseInterruptible(200)) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
        }
    } else if (!ocrText.empty()) {
        wr.conditionType = L"text_contains";
        wr.text = ocrText;
        while (ElapsedMs(waitStart) < timeoutMs) {
            if (IsEmergencyStopPressed()) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
            WindowInfo w;
            std::wstring ec, em;
            if (ResolveUniqueWindow(targetTitle, w, ec, em)) {
                std::wstring safetyData;
                if (!EnforceWindowSafety(w, targetTitle, ec, em, safetyData)) {
                    FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                    failed = true;
                    return false;
                }
                OcrTextResult ocrResult = FindTextInWindow(w.hwnd, ocrText);
                if (ocrResult.ok) { conditionMet = true; break; }
            }
            if (!SleepCaseInterruptible(200)) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                return false;
            }
        }
    } else {
        FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"wait_until requires selector, file_contains path+text, window_title_contains, or text_contains.", L"{}");
        failed = true;
        return false;
    }

    wr.elapsedMs = ElapsedMs(waitStart);
    wr.ok = conditionMet;
    report.waitResults.push_back(wr);

    if (!conditionMet) {
        FinishStep(report, step, stepStartTick, false, L"ASSERTION_FAILED", L"wait_until timed out after " + std::to_wstring(timeoutMs) + L"ms.", L"{}");
        failed = true;
        return false;
    }

    FinishStep(report, step, stepStartTick, true, L"", L"wait_until condition met in " + std::to_wstring(wr.elapsedMs) + L"ms.", L"{}");
    return true;
}

bool ExecuteExpectV2(
    CaseReport& report,
    CaseStepRecord& step,
    ULONGLONG stepStartTick,
    const std::vector<V2Param>& params,
    const std::wstring& targetTitle,
    const std::map<std::wstring, std::wstring>& vars,
    bool& failed) {

    std::wstring selector = SubstituteVars(GetParam(params, L"selector_exists"), vars);
    std::wstring filePath = SubstituteVars(GetParam(params, L"path"), vars);
    std::wstring fileText = SubstituteVars(GetParam(params, L"text"), vars);
    std::wstring winTitle = SubstituteVars(GetParam(params, L"active_window_title_contains"), vars);
    std::wstring ocrText = SubstituteVars(GetParam(params, L"text_contains"), vars);

    CaseV2ExpectRecord er;
    er.stepIndex = step.index;
    bool ok = true;

    if (!selector.empty()) {
        er.type = L"selector_exists";
        er.selector = selector;
        WindowInfo w;
        std::wstring ec, em;
        if (!ResolveUniqueWindow(targetTitle, w, ec, em)) {
            er.ok = false;
            er.detail = L"Target window not found: " + ec;
            ok = false;
        } else {
            if (selector.rfind(L"text:", 0) == 0) {
                std::wstring safetyData;
                if (!EnforceWindowSafety(w, targetTitle, ec, em, safetyData)) {
                    er.ok = false;
                    er.detail = em;
                    ok = false;
                    report.expectResults.push_back(er);
                    FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                    failed = true;
                    return false;
                }
            }
            SelectorResult sr = LocateSelector(w.hwnd, selector);
            er.ok = sr.ok;
            er.detail = sr.ok ? L"Selector found." : sr.errorMessage;
            ok = sr.ok;
        }
    } else if (!filePath.empty() && !fileText.empty()) {
        er.type = L"file_contains";
        er.path = filePath;
        er.text = fileText;
        FileReadResult fr;
        std::wstring normalizedPath;
        ReadAllowedTextFile(filePath, fr, normalizedPath);
        if (!fr.ok) {
            er.ok = false;
            er.detail = fr.error;
            ok = false;
        } else {
            bool found = fr.content.find(fileText) != std::wstring::npos;
            er.ok = found;
            er.detail = found ? L"Text found in file." : L"Text not found in file.";
            ok = found;
        }
    } else if (!winTitle.empty()) {
        er.type = L"active_window_title_contains";
        er.text = winTitle;
        WindowInfo active;
        if (!ActiveWindowInfo(active)) {
            er.ok = false;
            er.detail = L"No active window.";
            ok = false;
        } else {
            std::wstring lowerTitle = active.title;
            std::wstring lowerNeedle = winTitle;
            std::transform(lowerTitle.begin(), lowerTitle.end(), lowerTitle.begin(), ::towlower);
            std::transform(lowerNeedle.begin(), lowerNeedle.end(), lowerNeedle.begin(), ::towlower);
            bool found = lowerTitle.find(lowerNeedle) != std::wstring::npos;
            er.ok = found;
            er.detail = found ? L"Active window title matches." : L"Active window title does not match.";
            ok = found;
        }
    } else if (!ocrText.empty()) {
        er.type = L"text_contains";
        er.text = ocrText;
        WindowInfo w;
        std::wstring ec, em;
        if (!ResolveUniqueWindow(targetTitle, w, ec, em)) {
            er.ok = false;
            er.detail = L"Target window not found: " + ec;
            ok = false;
        } else {
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, targetTitle, ec, em, safetyData)) {
                er.ok = false;
                er.detail = em;
                ok = false;
                report.expectResults.push_back(er);
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                return false;
            }
            OcrTextResult ocrResult = FindTextInWindow(w.hwnd, ocrText);
            er.ok = ocrResult.ok;
            er.detail = ocrResult.ok ? L"OCR text found." : ocrResult.errorMessage;
            ok = ocrResult.ok;
        }
    } else {
        FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"expect requires selector_exists, file_contains path+text, active_window_title_contains, or text_contains.", L"{}");
        failed = true;
        return false;
    }

    report.expectResults.push_back(er);
    if (!ok) {
        FinishStep(report, step, stepStartTick, false, L"ASSERTION_FAILED", L"expect failed: " + er.detail, L"{}");
        failed = true;
        return false;
    }
    FinishStep(report, step, stepStartTick, true, L"", L"expect passed.", L"{}");
    return true;
}

bool RunPostActionExpects(
    CaseReport& report,
    const std::vector<V2Param>& params,
    const std::wstring& targetTitle,
    const std::map<std::wstring, std::wstring>& vars,
    int stepIndex) {

    std::wstring expectSelector = SubstituteVars(GetParam(params, L"expect_selector_exists"), vars);
    std::wstring expectFilePath = SubstituteVars(GetParam(params, L"expect_file_contains_path"), vars);
    std::wstring expectFileText = SubstituteVars(GetParam(params, L"expect_file_contains_text"), vars);

    CaseV2ExpectRecord er;
    er.stepIndex = stepIndex;
    bool ok = true;

    if (!expectSelector.empty()) {
        er.type = L"selector_exists";
        er.selector = expectSelector;
        WindowInfo w;
        std::wstring ec, em;
        if (!ResolveUniqueWindow(targetTitle, w, ec, em)) {
            er.ok = false;
            er.detail = L"Target window not found: " + ec;
            report.expectResults.push_back(er);
            return false;
        }
        if (expectSelector.rfind(L"text:", 0) == 0) {
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, targetTitle, ec, em, safetyData)) {
                er.ok = false;
                er.detail = em;
                report.expectResults.push_back(er);
                return false;
            }
        }
        SelectorResult sr = LocateSelector(w.hwnd, expectSelector);
        er.ok = sr.ok;
        er.detail = sr.ok ? L"Selector found." : sr.errorMessage;
        report.expectResults.push_back(er);
        return sr.ok;
    }

    if (!expectFilePath.empty() && !expectFileText.empty()) {
        er.type = L"file_contains";
        er.path = expectFilePath;
        er.text = expectFileText;
        FileReadResult fr;
        std::wstring normalizedPath;
        ReadAllowedTextFile(expectFilePath, fr, normalizedPath);
        if (!fr.ok) {
            er.ok = false;
            er.detail = fr.error;
            report.expectResults.push_back(er);
            return false;
        }
        bool found = fr.content.find(expectFileText) != std::wstring::npos;
        er.ok = found;
        er.detail = found ? L"Text found in file." : L"Text not found in file.";
        report.expectResults.push_back(er);
        return found;
    }

    return true;  // no expect specified
}

CaseRunResult RunCaseFileV2(const std::wstring& caseFilePath, const std::wstring& reportPath, const std::wstring& content) {
    ULONGLONG caseStartTick = GetTickCount64();
    CaseRunResult runResult;
    runResult.reportPath = reportPath;

    CaseReport report;
    report.caseFile = caseFilePath;
    report.caseName = Basename(caseFilePath);
    report.caseVersion = 2;
    report.startTime = CurrentTimestamp();

    SafetyPolicy safetyPolicy = LoadSafetyPolicy();

    std::map<std::wstring, std::wstring> vars;
    std::wistringstream lines(content);
    std::wstring line;
    int stepCount = 0;
    bool failed = false;

    // First pass: skip case_version=2 declaration line
    while (std::getline(lines, line)) {
        line = Trim(line);
        if (line.empty() || line[0] == L'#') { continue; }
        if (line == L"case_version=2") { break; }
    }

    while (std::getline(lines, line)) {
        line = Trim(line);
        if (line.empty() || line[0] == L'#') { continue; }

        if (IsEmergencyStopPressed()) {
            report.failureErrorCode = UserAbortStopCode();
            report.failureMessage = UserAbortMessage();
            report.failedStepIndex = stepCount + 1;
            failed = true;
            break;
        }
        if (ElapsedMs(caseStartTick) > safetyPolicy.maxDurationMs) {
            report.failureErrorCode = L"CASE_DURATION_LIMIT_EXCEEDED";
            report.failureMessage = L"Case exceeded safety max_duration_ms.";
            report.failedStepIndex = stepCount + 1;
            failed = true;
            break;
        }

        ++stepCount;
        if (stepCount > safetyPolicy.maxSteps) {
            report.failureErrorCode = L"CASE_STEP_LIMIT_EXCEEDED";
            report.failureMessage = L"Case exceeded safety max_steps.";
            report.failedStepIndex = stepCount;
            failed = true;
            break;
        }

        CaseStepRecord step;
        step.index = stepCount;
        step.startedAt = CurrentTimestamp();
        ULONGLONG stepStartTick = GetTickCount64();

        // Parse v2 line
        std::wstring command;
        std::vector<V2Param> params;
        std::wstring parseError;
        if (!ParseV2Line(line, command, params, parseError)) {
            step.action = L"parse_error";
            step.parameters = line;
            FinishStep(report, step, stepStartTick, false, L"CASE_PARSE_FAILED", parseError, L"{}");
            failed = true;
            break;
        }
        if (command.empty()) { --stepCount; continue; }

        step.action = command;
        step.parameters = line;

        // Substitute variables in all param values
        for (auto& p : params) {
            p.value = SubstituteVars(p.value, vars);
        }

        // Dispatch v2 commands
        if (command == L"set") {
            std::wstring name = GetParam(params, L"name");
            std::wstring value = GetParam(params, L"value");
            if (name.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"set requires name.", L"{}");
                failed = true;
                break;
            }
            vars[name] = value;
            report.variables.push_back({name, value});
            FinishStep(report, step, stepStartTick, true, L"", L"Variable set.", L"{\"name\":" + JsonString(name) + L",\"value\":" + JsonString(value) + L"}");
        } else if (command == L"target_title") {
            report.targetTitle = GetParam(params, L"title", GetParam(params, L"value", report.targetTitle));
            if (report.targetTitle.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"target_title requires a value.", L"{}");
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Target title set.", L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
        } else if (command == L"wait") {
            int ms = ParseIntParam(params, L"ms", 0);
            if (ms <= 0 || ms > 60000) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"wait requires ms between 1 and 60000.", L"{}");
                failed = true;
                break;
            }
            if (!SleepCaseInterruptible(static_cast<DWORD>(ms))) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Waited.", L"{\"wait_ms\":" + std::to_wstring(ms) + L"}");
        } else if (command == L"wait_until") {
            if (!ExecuteWaitUntilV2(report, step, stepStartTick, params, report.targetTitle, vars, failed)) {
                if (failed) break;
            }
        } else if (command == L"expect") {
            if (!ExecuteExpectV2(report, step, stepStartTick, params, report.targetTitle, vars, failed)) {
                if (failed) break;
            }
        } else if (command == L"screenshot") {
            std::wstring out = GetParam(params, L"out");
            if (out.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"screenshot requires out.", L"{}");
                failed = true;
                break;
            }
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            ScreenshotResult shot = CaptureWindowToBmp(w.hwnd, out);
            if (!shot.ok) {
                FinishStep(report, step, stepStartTick, false, L"SCREENSHOT_FAILED", shot.error, L"{\"out\":" + JsonString(out) + L"}");
                failed = true;
                break;
            }
            report.screenshotPaths.push_back(out);
            FinishStep(report, step, stepStartTick, true, L"", L"Screenshot saved.", L"{\"out\":" + JsonString(out) + L",\"method\":" + JsonString(shot.method) + L"}");
        } else if (command == L"observe") {
            std::wstring out = GetParam(params, L"out");
            ObserveResult obs = ObserveWindow(report.targetTitle, true, true, 80);
            if (!obs.ok) {
                FinishStep(report, step, stepStartTick, false, obs.errorCode.empty() ? L"UNKNOWN_ERROR" : obs.errorCode, obs.errorMessage, L"{}");
                failed = true;
                break;
            }
            if (!out.empty()) {
                std::wstring writeError;
                if (!WriteUtf8TextFile(out, obs.dataJson, writeError)) {
                    FinishStep(report, step, stepStartTick, false, L"FILE_READ_FAILED", writeError, L"{}");
                    failed = true;
                    break;
                }
            }
            CaseObservationRecord obsRec;
            obsRec.index = step.index;
            obsRec.screenshotPath = obs.screenshotPath;
            obsRec.uiaElementCount = obs.uiaElementCount;
            obsRec.focusVerified = obs.focusVerified;
            obsRec.outputPath = out;
            report.observations.push_back(obsRec);
            if (!obs.screenshotPath.empty()) { report.screenshotPaths.push_back(obs.screenshotPath); }
            FinishStep(report, step, stepStartTick, true, L"", L"Observed.", L"{\"uia_element_count\":" + std::to_wstring(obs.uiaElementCount) + L"}");
        } else if (command == L"locate") {
            std::wstring selector = GetParam(params, L"selector");
            if (selector.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"locate requires selector.", L"{}");
                failed = true;
                break;
            }
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            if (selector.rfind(L"text:", 0) == 0) {
                std::wstring safetyData;
                if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                    FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                    failed = true;
                    break;
                }
            }
            SelectorResult sr = LocateSelector(w.hwnd, selector);
            FinishStep(report, step, stepStartTick, sr.ok, sr.ok ? L"" : (sr.errorCode.empty() ? L"UNKNOWN_ERROR" : sr.errorCode), sr.ok ? L"Located." : sr.errorMessage, sr.dataJson);
            if (!sr.ok) { failed = true; break; }
        } else if (command == L"act") {
            std::wstring selector = GetParam(params, L"selector");
            std::wstring action = GetParam(params, L"action");
            std::wstring text = GetParam(params, L"text");

            if (selector.empty() || action.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"act requires selector and action.", L"{}");
                failed = true;
                break;
            }
            if (action != L"click" && action != L"double-click" && action != L"right-click" && action != L"type" && action != L"focus") {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"Unsupported act action: " + action, L"{}");
                failed = true;
                break;
            }
            if (action == L"type" && text.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"act type requires text.", L"{}");
                failed = true;
                break;
            }

            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }

            SelectorResult located = LocateSelector(w.hwnd, selector);
            if (!located.ok) {
                FinishStep(report, step, stepStartTick, false, located.errorCode.empty() ? L"UNKNOWN_ERROR" : located.errorCode, located.errorMessage, located.dataJson);
                failed = true;
                break;
            }

            bool actionOk = false;
            std::wstring actionErrorCode;
            std::wstring actionError;
            std::wstring actionMethod = L"";

            if (action == L"focus") {
                ActionResult focused = FocusTargetWindow(w.hwnd);
                actionOk = focused.ok;
                actionErrorCode = focused.errorCode;
                actionError = focused.error;
                actionMethod = L"focus_window";
            } else if (action == L"click" && located.locateMethod == L"uia" && located.uiaInvokeCandidate && !located.elementName.empty()) {
                UiaPatternActionResult invoked = InvokeUiaElementByName(w.hwnd, located.elementName);
                if (invoked.ok && invoked.patternAvailable) { actionOk = true; actionMethod = L"invoke_pattern"; }
            }
            if (!actionOk && action == L"type" && located.locateMethod == L"uia" && located.uiaValueCandidate && !located.elementName.empty()) {
                UiaPatternActionResult typed = SetUiaElementValueByName(w.hwnd, located.elementName, text);
                if (typed.ok && typed.patternAvailable) { actionOk = true; actionMethod = L"value_pattern"; }
            }
            if (!actionOk && action == L"click") {
                ClickResult click = ClickClientPoint(w.hwnd, located.clientX, located.clientY, L"human", 0);
                actionOk = click.ok; actionErrorCode = click.errorCode; actionError = click.error;
                actionMethod = L"mouse_click";
            } else if (!actionOk && action == L"double-click") {
                ClickResult click = DoubleClickClientPoint(w.hwnd, located.clientX, located.clientY, L"human", 0);
                actionOk = click.ok; actionErrorCode = click.errorCode; actionError = click.error;
                actionMethod = L"mouse_double_click";
            } else if (!actionOk && action == L"right-click") {
                ClickResult click = RightClickClientPoint(w.hwnd, located.clientX, located.clientY, L"human", 0);
                actionOk = click.ok; actionErrorCode = click.errorCode; actionError = click.error;
                actionMethod = L"mouse_right_click";
            } else if (!actionOk && action == L"type") {
                ClickResult click = ClickClientPoint(w.hwnd, located.clientX, located.clientY, L"human", 0);
                if (!click.ok) {
                    actionErrorCode = click.errorCode; actionError = click.error;
                } else {
                    ActionResult selectAll = SendHotkey(w.hwnd, L"CTRL+A");
                    if (!selectAll.ok) {
                        actionErrorCode = selectAll.errorCode; actionError = selectAll.error;
                    } else {
                        TypeResult typed = TypeText(w.hwnd, text, L"human", -1);
                        actionOk = typed.ok; actionErrorCode = typed.errorCode; actionError = typed.error;
                    }
                }
                actionMethod = L"mouse_center_type";
            }

            std::wstring data = located.dataJson.substr(0, located.dataJson.size() - 1)
                + L",\"action\":" + JsonString(action)
                + L",\"action_method\":" + JsonString(actionMethod)
                + L",\"text_length\":" + std::to_wstring(text.size()) + L"}";

            if (!actionOk) {
                FinishStep(report, step, stepStartTick, false, actionErrorCode.empty() ? L"UNKNOWN_ERROR" : actionErrorCode, actionError, data);
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Acted.", data);

            // Post-action expects
            if (!RunPostActionExpects(report, params, report.targetTitle, vars, step.index)) {
                report.failureErrorCode = L"ASSERTION_FAILED";
                report.failureMessage = L"Post-action expect failed.";
                report.failedStepIndex = step.index;
                failed = true;
                break;
            }
        } else if (command == L"click" || command == L"double_click" || command == L"right_click") {
            int x = ParseIntParam(params, L"x", -1);
            int y = ParseIntParam(params, L"y", -1);
            if (x < 0 || y < 0) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", command + L" requires non-negative x and y.", L"{}");
                failed = true;
                break;
            }
            std::wstring moveMode = GetParam(params, L"move_mode", L"human");
            int moveDurationMs = ParseIntParam(params, L"move_duration_ms", 0);

            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }

            ClickResult cr;
            if (command == L"double_click") {
                cr = DoubleClickClientPoint(w.hwnd, x, y, moveMode, moveDurationMs);
            } else if (command == L"right_click") {
                cr = RightClickClientPoint(w.hwnd, x, y, moveMode, moveDurationMs);
            } else {
                cr = ClickClientPoint(w.hwnd, x, y, moveMode, moveDurationMs);
            }
            if (!cr.ok) {
                FinishStep(report, step, stepStartTick, false, cr.errorCode.empty() ? L"UNKNOWN_ERROR" : cr.errorCode, cr.error, L"{}");
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", command + L" executed.", L"{}");
        } else if (command == L"scroll") {
            int x = ParseIntParam(params, L"x", -1);
            int y = ParseIntParam(params, L"y", -1);
            int delta = ParseIntParam(params, L"delta", 0);
            if (x < 0 || y < 0) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"scroll requires non-negative x and y.", L"{}");
                failed = true;
                break;
            }
            std::wstring moveMode = GetParam(params, L"move_mode", L"human");
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            ClickResult scr = ScrollClientPoint(w.hwnd, x, y, delta, moveMode);
            if (!scr.ok) {
                FinishStep(report, step, stepStartTick, false, scr.errorCode.empty() ? L"UNKNOWN_ERROR" : scr.errorCode, scr.error, L"{}");
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Scrolled.", L"{}");
        } else if (command == L"drag") {
            int fromX = ParseIntParam(params, L"from_x", -1);
            int fromY = ParseIntParam(params, L"from_y", -1);
            int toX = ParseIntParam(params, L"to_x", -1);
            int toY = ParseIntParam(params, L"to_y", -1);
            if (fromX < 0 || fromY < 0 || toX < 0 || toY < 0) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"drag requires non-negative from_x, from_y, to_x, to_y.", L"{}");
                failed = true;
                break;
            }
            std::wstring moveMode = GetParam(params, L"move_mode", L"human");
            int durationMs = ParseIntParam(params, L"duration_ms", 0);
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            DragResult dr = DragClientPoints(w.hwnd, fromX, fromY, toX, toY, moveMode, durationMs);
            if (!dr.ok) {
                FinishStep(report, step, stepStartTick, false, dr.errorCode.empty() ? L"UNKNOWN_ERROR" : dr.errorCode, dr.error, L"{}");
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Dragged.", L"{}");
        } else if (command == L"press") {
            std::wstring key = GetParam(params, L"key");
            if (key.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"press requires key.", L"{}");
                failed = true;
                break;
            }
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            ActionResult ar = PressKey(w.hwnd, key);
            FinishStep(report, step, stepStartTick, ar.ok, ar.ok ? L"" : (ar.errorCode.empty() ? L"UNKNOWN_ERROR" : ar.errorCode), ar.ok ? L"Pressed." : ar.error, L"{}");
            if (!ar.ok) { failed = true; break; }
        } else if (command == L"hotkey") {
            std::wstring keys = GetParam(params, L"keys");
            if (keys.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"hotkey requires keys.", L"{}");
                failed = true;
                break;
            }
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            ActionResult ar = SendHotkey(w.hwnd, keys);
            FinishStep(report, step, stepStartTick, ar.ok, ar.ok ? L"" : (ar.errorCode.empty() ? L"UNKNOWN_ERROR" : ar.errorCode), ar.ok ? L"Hotkey sent." : ar.error, L"{}");
            if (!ar.ok) { failed = true; break; }
        } else if (command == L"type") {
            std::wstring text = GetParam(params, L"text");
            std::wstring selector = GetParam(params, L"selector");
            if (text.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"type requires text.", L"{}");
                failed = true;
                break;
            }
            std::wstring typeMode = GetParam(params, L"type_mode", L"human");
            int charDelayMs = ParseIntParam(params, L"char_delay_ms", -1);
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            if (!selector.empty()) {
                SelectorResult sr = LocateSelector(w.hwnd, selector);
                if (!sr.ok) {
                    FinishStep(report, step, stepStartTick, false, sr.errorCode.empty() ? L"UNKNOWN_ERROR" : sr.errorCode, sr.errorMessage, sr.dataJson);
                    failed = true;
                    break;
                }
                ClickResult click = ClickClientPoint(w.hwnd, sr.clientX, sr.clientY, L"human", 0);
                if (!click.ok) {
                    FinishStep(report, step, stepStartTick, false, click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, L"{}");
                    failed = true;
                    break;
                }
                ActionResult selAll = SendHotkey(w.hwnd, L"CTRL+A");
                if (!selAll.ok) {
                    FinishStep(report, step, stepStartTick, false, selAll.errorCode.empty() ? L"UNKNOWN_ERROR" : selAll.errorCode, selAll.error, L"{}");
                    failed = true;
                    break;
                }
            }
            TypeResult tr = TypeText(w.hwnd, text, typeMode, charDelayMs);
            if (!tr.ok) {
                FinishStep(report, step, stepStartTick, false, tr.errorCode.empty() ? L"UNKNOWN_ERROR" : tr.errorCode, tr.error, L"{}");
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Typed.", L"{\"text_length\":" + std::to_wstring(tr.textLength) + L"}");
        } else if (command == L"focus") {
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            ActionResult ar = FocusTargetWindow(w.hwnd);
            FinishStep(report, step, stepStartTick, ar.ok, ar.ok ? L"" : (ar.errorCode.empty() ? L"UNKNOWN_ERROR" : ar.errorCode), ar.ok ? L"Focused." : ar.error, L"{}");
            if (!ar.ok) { failed = true; break; }
        } else if (command == L"clipboard_set") {
            std::wstring text = GetParam(params, L"text");
            ActionResult ar = SetClipboardUnicodeText(text);
            FinishStep(report, step, stepStartTick, ar.ok, ar.ok ? L"" : (ar.errorCode.empty() ? L"UNKNOWN_ERROR" : ar.errorCode), ar.ok ? L"Clipboard set." : ar.error, L"{\"text_length\":" + std::to_wstring(ar.textLength) + L"}");
            if (!ar.ok) { failed = true; break; }
        } else if (command == L"clipboard_paste") {
            std::wstring text = GetParam(params, L"text");
            WindowInfo w;
            std::wstring ec, em;
            if (!ResolveUniqueWindow(report.targetTitle, w, ec, em)) {
                FinishStep(report, step, stepStartTick, false, ec, em, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(w, report.targetTitle, ec, em, safetyData)) {
                FinishStep(report, step, stepStartTick, false, ec, em, safetyData);
                failed = true;
                break;
            }
            ActionResult ar = PasteClipboardText(w.hwnd, text, !text.empty());
            FinishStep(report, step, stepStartTick, ar.ok, ar.ok ? L"" : (ar.errorCode.empty() ? L"UNKNOWN_ERROR" : ar.errorCode), ar.ok ? L"Clipboard pasted." : ar.error, L"{}");
            if (!ar.ok) { failed = true; break; }
        } else if (command == L"read_text") {
            std::wstring out = GetParam(params, L"out");
            WindowInfo rtw;
            std::wstring rtec, rtem;
            if (!ResolveUniqueWindow(report.targetTitle, rtw, rtec, rtem)) {
                FinishStep(report, step, stepStartTick, false, rtec, rtem, L"{}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(rtw, report.targetTitle, rtec, rtem, safetyData)) {
                FinishStep(report, step, stepStartTick, false, rtec, rtem, safetyData);
                failed = true;
                break;
            }
            OcrResult ocr = ReadWindowText(rtw.hwnd, L"");
            if (!ocr.ok) {
                FinishStep(report, step, stepStartTick, false, ocr.errorCode.empty() ? L"OCR_FAILED" : ocr.errorCode, ocr.errorMessage, L"{}");
                failed = true;
                break;
            }
            if (!out.empty()) {
                std::wstring normalizedOut;
                std::wstring writeSafetyError;
                if (!IsWritePathAllowed(out, normalizedOut, writeSafetyError)) {
                    FinishStep(report, step, stepStartTick, false, L"SAFETY_POLICY_DENIED", writeSafetyError, L"{\"out\":" + JsonString(out) + L"}");
                    failed = true;
                    break;
                }
                std::wstring writeError;
                if (!WriteUtf8TextFile(normalizedOut, ocr.fullText, writeError)) {
                    FinishStep(report, step, stepStartTick, false, L"FILE_READ_FAILED", writeError, L"{}");
                    failed = true;
                    break;
                }
                out = normalizedOut;
            }
            step.content = ocr.fullText;
            if (!ocr.fullText.empty()) { report.readContents.push_back(ocr.fullText); }
            FinishStep(report, step, stepStartTick, true, L"", L"OCR read window text.", L"{\"text_length\":" + std::to_wstring(ocr.fullText.size()) + L",\"line_count\":" + std::to_wstring(ocr.lines.size()) + L"}");
        } else if (command == L"read_file") {
            std::wstring path = GetParam(params, L"path");
            if (path.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"read_file requires path.", L"{}");
                failed = true;
                break;
            }
            FileReadResult fr;
            std::wstring normPath;
            if (!ReadAllowedTextFile(path, fr, normPath)) {
                FinishStep(report, step, stepStartTick, false, fr.errorCode.empty() ? L"FILE_READ_FAILED" : fr.errorCode, fr.error, L"{}");
                failed = true;
                break;
            }
            step.content = fr.content;
            report.readContents.push_back(fr.content);
            FinishStep(report, step, stepStartTick, true, L"", L"Read file.", L"{\"path\":" + JsonString(normPath) + L"}");
        } else if (command == L"assert_file_contains") {
            std::wstring path = GetParam(params, L"path");
            std::wstring expected = GetParam(params, L"text");
            if (path.empty() || expected.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"assert_file_contains requires path and text.", L"{}");
                failed = true;
                break;
            }
            FileReadResult fr;
            std::wstring normPath;
            if (!ReadAllowedTextFile(path, fr, normPath)) {
                FinishStep(report, step, stepStartTick, false, fr.errorCode.empty() ? L"FILE_READ_FAILED" : fr.errorCode, fr.error, L"{}");
                failed = true;
                break;
            }
            bool contains = fr.content.find(expected) != std::wstring::npos;
            FinishStep(report, step, stepStartTick, contains, contains ? L"" : L"ASSERTION_FAILED", contains ? L"Assertion passed." : L"Expected text not found.", L"{}");
            if (!contains) { failed = true; break; }
        } else {
            FinishStep(report, step, stepStartTick, false, L"CASE_PARSE_FAILED", L"Unknown v2 command: " + command, L"{}");
            failed = true;
            break;
        }
    }

    if (!failed && ElapsedMs(caseStartTick) > safetyPolicy.maxDurationMs) {
        report.failureErrorCode = L"CASE_DURATION_LIMIT_EXCEEDED";
        report.failureMessage = L"Case exceeded safety max_duration_ms.";
        report.failedStepIndex = stepCount;
        failed = true;
    }

    report.stepCount = static_cast<int>(report.steps.size());
    report.ok = !failed && report.failureErrorCode.empty();
    if (!report.ok && report.failureErrorCode.empty()) {
        report.failureErrorCode = L"UNKNOWN_ERROR";
        report.failureMessage = L"Case failed.";
    }
    report.endTime = CurrentTimestamp();
    report.totalDurationMs = ElapsedMs(caseStartTick);

    std::wstring reportError;
    if (!WriteMarkdownReport(reportPath, report, reportError)) {
        runResult.errorCode = L"UNKNOWN_ERROR";
        runResult.error = L"Case finished but report write failed: " + reportError;
        return runResult;
    }

    runResult.ok = report.ok;
    runResult.errorCode = report.failureErrorCode;
    runResult.error = report.failureMessage;
    runResult.stepCount = report.stepCount;
    runResult.passedStepCount = report.passedStepCount;
    runResult.failedStepIndex = report.failedStepIndex;
    return runResult;
}

}  // namespace (v2)

CaseRunResult RunCaseFile(const std::wstring& caseFilePath, const std::wstring& reportPath) {
    ULONGLONG caseStartTick = GetTickCount64();
    CaseRunResult runResult;
    runResult.reportPath = reportPath;

    CaseReport report;
    report.caseFile = caseFilePath;
    report.caseName = Basename(caseFilePath);
    report.startTime = CurrentTimestamp();

    FileReadResult caseFile = ReadTextFile(caseFilePath);
    if (!caseFile.ok) {
        report.endTime = CurrentTimestamp();
        report.totalDurationMs = ElapsedMs(caseStartTick);
        report.failureErrorCode = caseFile.errorCode.empty() ? L"FILE_READ_FAILED" : caseFile.errorCode;
        report.failureMessage = L"Could not read case file: " + caseFile.error;
        std::wstring reportError;
        WriteMarkdownReport(reportPath, report, reportError);
        runResult.errorCode = report.failureErrorCode;
        runResult.error = report.failureMessage;
        return runResult;
    }

    // Detect case_version=2 in first non-comment line
    {
        std::wistringstream preview(caseFile.content);
        std::wstring previewLine;
        while (std::getline(preview, previewLine)) {
            std::wstring trimmed = Trim(previewLine);
            if (trimmed.empty() || trimmed[0] == L'#') {
                continue;
            }
            if (trimmed == L"case_version=2") {
                return RunCaseFileV2(caseFilePath, reportPath, caseFile.content);
            }
            break;
        }
    }

    SafetyPolicy safetyPolicy = LoadSafetyPolicy();
    std::wistringstream lines(caseFile.content);
    std::wstring line;
    int stepCount = 0;
    bool failed = false;

    while (std::getline(lines, line)) {
        line = Trim(line);
        if (line.empty() || line[0] == L'#') {
            continue;
        }

        if (IsEmergencyStopPressed()) {
            report.failureErrorCode = UserAbortStopCode();
            report.failureMessage = UserAbortMessage();
            report.failedStepIndex = stepCount + 1;
            failed = true;
            break;
        }
        if (ElapsedMs(caseStartTick) > safetyPolicy.maxDurationMs) {
            report.failureErrorCode = L"CASE_DURATION_LIMIT_EXCEEDED";
            report.failureMessage = L"Case exceeded safety max_duration_ms.";
            report.failedStepIndex = stepCount + 1;
            failed = true;
            break;
        }

        ++stepCount;
        if (stepCount > safetyPolicy.maxSteps) {
            report.failureErrorCode = L"CASE_STEP_LIMIT_EXCEEDED";
            report.failureMessage = L"Case exceeded safety max_steps.";
            report.failedStepIndex = stepCount;
            failed = true;
            break;
        }

        CaseStepRecord step;
        step.index = stepCount;
        step.startedAt = CurrentTimestamp();
        ULONGLONG stepStartTick = GetTickCount64();

        if (line.rfind(L"target_title=", 0) == 0) {
            report.targetTitle = Trim(line.substr(13));
            step.action = L"target_title";
            step.parameters = report.targetTitle;
            FinishStep(report, step, stepStartTick, !report.targetTitle.empty(), report.targetTitle.empty() ? L"CASE_PARSE_FAILED" : L"", report.targetTitle.empty() ? L"target_title cannot be empty." : L"Target title set.", L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
            failed = !step.ok;
            if (failed) break;
            continue;
        }

        std::vector<std::wstring> words = SplitWords(line);
        for (auto& word : words) {
            word = ExpandProjectRootVars(word);
        }
        if (words.empty()) {
            continue;
        }

        step.action = words[0];
        step.parameters = RestAfterFirstWord(line);

        if (words[0] == L"wait") {
            int ms = 0;
            if (words.size() != 2 || !ParseInt(words[1], ms) || ms < 0 || ms > 60000) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"wait requires milliseconds from 0 to 60000.", L"{}");
                failed = true;
                break;
            }
            if (!SleepCaseInterruptible(static_cast<DWORD>(ms))) {
                FinishUserAbortStep(report, step, stepStartTick);
                failed = true;
                break;
            }
            FinishStep(report, step, stepStartTick, true, L"", L"Waited.", L"{\"wait_ms\":" + std::to_wstring(ms) + L"}");
        } else if (words[0] == L"screenshot") {
            if (words.size() != 2) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"screenshot requires one output path.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            ScreenshotResult shot = CaptureWindowToBmp(window.hwnd, words[1]);
            if (!shot.ok) {
                FinishStep(report, step, stepStartTick, false, L"SCREENSHOT_FAILED", shot.error, L"{\"out\":" + JsonString(words[1]) + L"}");
                failed = true;
                break;
            }
            report.screenshotPaths.push_back(words[1]);
            FinishStep(report, step, stepStartTick, true, L"", L"Screenshot saved with " + shot.method + L".", L"{\"out\":" + JsonString(words[1]) + L",\"method\":" + JsonString(shot.method) + L"}");
        } else if (words[0] == L"observe") {
            if (words.size() > 2) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"observe requires zero or one output JSON path.", L"{}");
                failed = true;
                break;
            }
            ObserveResult observe = ObserveWindow(report.targetTitle, true, true, 80);
            if (!observe.ok) {
                FinishStep(report, step, stepStartTick, false, observe.errorCode.empty() ? L"UNKNOWN_ERROR" : observe.errorCode, observe.errorMessage, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring outputPath;
            if (words.size() == 2) {
                outputPath = words[1];
                std::wstring writeError;
                if (!WriteUtf8TextFile(outputPath, observe.dataJson, writeError)) {
                    FinishStep(report, step, stepStartTick, false, L"FILE_READ_FAILED", writeError, L"{\"out\":" + JsonString(outputPath) + L"}");
                    failed = true;
                    break;
                }
            }
            CaseObservationRecord observation;
            observation.index = step.index;
            observation.screenshotPath = observe.screenshotPath;
            observation.uiaElementCount = observe.uiaElementCount;
            observation.focusVerified = observe.focusVerified;
            observation.outputPath = outputPath;
            report.observations.push_back(observation);
            if (!observe.screenshotPath.empty()) {
                report.screenshotPaths.push_back(observe.screenshotPath);
            }
            std::wstring summary = L"{\"screenshot_path\":" + JsonString(observe.screenshotPath)
                + L",\"uia_element_count\":" + std::to_wstring(observe.uiaElementCount)
                + L",\"focus_verified\":" + (observe.focusVerified ? L"true" : L"false")
                + L",\"out\":" + JsonString(outputPath) + L"}";
            FinishStep(report, step, stepStartTick, true, L"", L"Observed target window.", summary);
        } else if (words[0] == L"locate") {
            std::wstring selector = RestAfterFirstWord(line);
            if (selector.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"locate requires a selector.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            SelectorResult located = LocateSelector(window.hwnd, selector);
            FinishStep(report, step, stepStartTick, located.ok, located.ok ? L"" : (located.errorCode.empty() ? L"UNKNOWN_ERROR" : located.errorCode), located.ok ? L"Located selector." : located.errorMessage, located.dataJson);
            failed = !located.ok;
            if (failed) break;
        } else if (words[0] == L"act") {
            std::wstring rest = RestAfterFirstWord(line);
            std::vector<std::wstring> actWords = SplitWords(rest);
            if (actWords.size() < 2) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"act requires: act selector action [text].", L"{}");
                failed = true;
                break;
            }
            std::wstring selector;
            std::wstring actionName;
            std::wstring text;
            std::wstring last = actWords.back();
            if (last == L"click" || last == L"double-click" || last == L"right-click" || last == L"focus") {
                actionName = last;
                size_t actionPos = rest.rfind(L" " + actionName);
                selector = Trim(rest.substr(0, actionPos));
            } else if (actWords.size() >= 3) {
                text = last;
                std::wstring possibleAction = actWords[actWords.size() - 2];
                if (possibleAction == L"type") {
                    actionName = possibleAction;
                    size_t actionPos = rest.rfind(L" " + actionName + L" " + text);
                    selector = Trim(rest.substr(0, actionPos));
                }
            }
            if (actionName != L"click" && actionName != L"double-click" && actionName != L"right-click" && actionName != L"type" && actionName != L"focus") {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"Unsupported act action.", L"{\"action\":" + JsonString(actionName) + L"}");
                failed = true;
                break;
            }
            if (actionName == L"type" && text.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"act type requires text.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            SelectorResult located = LocateSelector(window.hwnd, selector);
            if (!located.ok) {
                FinishStep(report, step, stepStartTick, false, located.errorCode.empty() ? L"UNKNOWN_ERROR" : located.errorCode, located.errorMessage, located.dataJson);
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            bool actionOk = false;
            std::wstring actionErrorCode;
            std::wstring actionError;
            std::wstring actionMethod = L"";
            if (actionName == L"focus") {
                ActionResult focused = FocusTargetWindow(window.hwnd);
                actionOk = focused.ok;
                actionErrorCode = focused.errorCode;
                actionError = focused.error;
                actionMethod = L"focus_window";
            } else if (actionName == L"click" && located.locateMethod == L"uia" && located.uiaInvokeCandidate && !located.elementName.empty()) {
                UiaPatternActionResult invoked = InvokeUiaElementByName(window.hwnd, located.elementName);
                if (invoked.ok && invoked.patternAvailable) {
                    actionOk = true;
                    actionMethod = L"invoke_pattern";
                }
            }
            if (!actionOk && actionName == L"type" && located.locateMethod == L"uia" && located.uiaValueCandidate && !located.elementName.empty()) {
                UiaPatternActionResult typed = SetUiaElementValueByName(window.hwnd, located.elementName, text);
                if (typed.ok && typed.patternAvailable) {
                    actionOk = true;
                    actionMethod = L"value_pattern";
                }
            }
            if (!actionOk && actionName == L"click") {
                ClickResult click = ClickClientPoint(window.hwnd, located.clientX, located.clientY, L"human", 0);
                actionOk = click.ok;
                actionErrorCode = click.errorCode;
                actionError = click.error;
                actionMethod = L"mouse_click";
            } else if (!actionOk && actionName == L"double-click") {
                ClickResult click = DoubleClickClientPoint(window.hwnd, located.clientX, located.clientY, L"human", 0);
                actionOk = click.ok;
                actionErrorCode = click.errorCode;
                actionError = click.error;
                actionMethod = L"mouse_double_click";
            } else if (!actionOk && actionName == L"right-click") {
                ClickResult click = RightClickClientPoint(window.hwnd, located.clientX, located.clientY, L"human", 0);
                actionOk = click.ok;
                actionErrorCode = click.errorCode;
                actionError = click.error;
                actionMethod = L"mouse_right_click";
            } else if (!actionOk && actionName == L"type") {
                ClickResult click = ClickClientPoint(window.hwnd, located.clientX, located.clientY, L"human", 0);
                if (!click.ok) {
                    actionErrorCode = click.errorCode;
                    actionError = click.error;
                } else {
                    ActionResult selectAll = SendHotkey(window.hwnd, L"CTRL+A");
                    if (!selectAll.ok) {
                        actionErrorCode = selectAll.errorCode;
                        actionError = selectAll.error;
                    } else {
                        TypeResult typed = TypeText(window.hwnd, text, L"human", -1);
                        actionOk = typed.ok;
                        actionErrorCode = typed.errorCode;
                        actionError = typed.error;
                    }
                }
                actionMethod = L"mouse_center_type";
            }
            std::wstring data = located.dataJson.substr(0, located.dataJson.size() - 1)
                + L",\"action\":" + JsonString(actionName)
                + L",\"action_method\":" + JsonString(actionMethod)
                + L",\"text_length\":" + std::to_wstring(text.size()) + L"}";
            FinishStep(report, step, stepStartTick, actionOk, actionOk ? L"" : (actionErrorCode.empty() ? L"UNKNOWN_ERROR" : actionErrorCode), actionOk ? L"Acted on selector." : actionError, data);
            failed = !actionOk;
            if (failed) break;
        } else if (words[0] == L"click") {
            int x = 0;
            int y = 0;
            std::wstring moveMode = L"human";
            int moveDurationMs = 0;
            if ((words.size() != 3 && words.size() != 4 && words.size() != 5) || !ParseInt(words[1], x) || !ParseInt(words[2], y)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"click requires: click x y [move_mode] [duration_ms].", L"{}");
                failed = true;
                break;
            }
            if (words.size() >= 4) {
                moveMode = words[3];
            }
            if (!IsMotionModeAllowed(moveMode)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"click move mode must be instant, fast-human, demo-human, human, or operator-human.", L"{}");
                failed = true;
                break;
            }
            if (words.size() == 5 && (!ParseInt(words[4], moveDurationMs) || moveDurationMs < 0)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"click duration must be a non-negative integer.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ClickResult action = ClickClientPoint(window.hwnd, x, y, moveMode, moveDurationMs);
            if (!action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.error, L"{}");
                failed = true;
                break;
            }
            std::wstring details = FormatClickDetails(action);
            FinishStep(report, step, stepStartTick, true, L"", L"Clicked. " + details, L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified) + L",\"details\":" + JsonString(details) + L"}");
            if (failed) break;
        } else if (words[0] == L"double_click" || words[0] == L"right_click") {
            int x = 0;
            int y = 0;
            std::wstring moveMode = L"human";
            int moveDurationMs = 0;
            if ((words.size() != 3 && words.size() != 4 && words.size() != 5) || !ParseInt(words[1], x) || !ParseInt(words[2], y)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", words[0] + L" requires: " + words[0] + L" x y [move_mode] [duration_ms].", L"{}");
                failed = true;
                break;
            }
            if (words.size() >= 4) {
                moveMode = words[3];
            }
            if (!IsMotionModeAllowed(moveMode)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", words[0] + L" move mode must be instant, fast-human, demo-human, human, or operator-human.", L"{}");
                failed = true;
                break;
            }
            if (words.size() == 5 && (!ParseInt(words[4], moveDurationMs) || moveDurationMs < 0)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", words[0] + L" duration must be a non-negative integer.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ClickResult action = words[0] == L"double_click"
                ? DoubleClickClientPoint(window.hwnd, x, y, moveMode, moveDurationMs)
                : RightClickClientPoint(window.hwnd, x, y, moveMode, moveDurationMs);
            if (!action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.error, L"{}");
                failed = true;
                break;
            }
            std::wstring details = FormatClickDetails(action);
            FinishStep(report, step, stepStartTick, true, L"", words[0] + L" executed. " + details, L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified) + L",\"details\":" + JsonString(details) + L"}");
        } else if (words[0] == L"scroll") {
            int x = 0;
            int y = 0;
            int delta = 0;
            std::wstring moveMode = L"human";
            if ((words.size() != 4 && words.size() != 5) || !ParseInt(words[1], x) || !ParseInt(words[2], y) || !ParseInt(words[3], delta)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"scroll requires: scroll x y delta [move_mode].", L"{}");
                failed = true;
                break;
            }
            if (words.size() == 5) {
                moveMode = words[4];
            }
            if (!IsMotionModeAllowed(moveMode)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"scroll move mode must be instant, fast-human, demo-human, human, or operator-human.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ClickResult action = ScrollClientPoint(window.hwnd, x, y, delta, moveMode);
            if (!action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.error, L"{}");
                failed = true;
                break;
            }
            std::wstring details = FormatClickDetails(action) + L" wheel_delta=" + std::to_wstring(action.wheelDelta);
            FinishStep(report, step, stepStartTick, true, L"", L"Scrolled. " + details, L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified) + L",\"details\":" + JsonString(details) + L"}");
        } else if (words[0] == L"drag") {
            int fromX = 0;
            int fromY = 0;
            int toX = 0;
            int toY = 0;
            std::wstring moveMode = L"human";
            int durationMs = 0;
            if ((words.size() < 5 || words.size() > 7) || !ParseInt(words[1], fromX) || !ParseInt(words[2], fromY) || !ParseInt(words[3], toX) || !ParseInt(words[4], toY)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"drag requires: drag from_x from_y to_x to_y [move_mode] [duration_ms].", L"{}");
                failed = true;
                break;
            }
            if (words.size() >= 6) {
                moveMode = words[5];
            }
            if (!IsMotionModeAllowed(moveMode)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"drag move mode must be instant, fast-human, demo-human, human, or operator-human.", L"{}");
                failed = true;
                break;
            }
            if (words.size() == 7 && (!ParseInt(words[6], durationMs) || durationMs < 0)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"drag duration must be a non-negative integer.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            DragResult action = DragClientPoints(window.hwnd, fromX, fromY, toX, toY, moveMode, durationMs);
            if (!action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.error, L"{}");
                failed = true;
                break;
            }
            std::wstring details = FormatDragDetails(action);
            FinishStep(report, step, stepStartTick, true, L"", L"Dragged. " + details, L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified) + L",\"details\":" + JsonString(details) + L"}");
        } else if (words[0] == L"press") {
            if (words.size() != 2) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"press requires one key.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ActionResult action = PressKey(window.hwnd, words[1]);
            std::wstring pressData = L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified)
                + L",\"key\":" + JsonString(words[1]) + L"}";
            FinishStep(report, step, stepStartTick, action.ok, action.ok ? L"" : (action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode), action.ok ? L"Pressed." : action.error, pressData);
            failed = !action.ok;
            if (failed) break;
        } else if (words[0] == L"hotkey") {
            if (words.size() != 2) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"hotkey requires one key combo.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ActionResult action = SendHotkey(window.hwnd, words[1]);
            std::wstring hotkeyData = L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified)
                + L",\"keys\":" + JsonString(words[1]) + L"}";
            FinishStep(report, step, stepStartTick, action.ok, action.ok ? L"" : (action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode), action.ok ? L"Hotkey sent." : action.error, hotkeyData);
            failed = !action.ok;
            if (failed) break;
        } else if (words[0] == L"clipboard_set") {
            std::wstring text = RestAfterFirstWord(line);
            ActionResult action = SetClipboardUnicodeText(text);
            std::wstring data = L"{\"text_length\":" + std::to_wstring(action.textLength) + L"}";
            FinishStep(report, step, stepStartTick, action.ok, action.ok ? L"" : (action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode), action.ok ? L"Clipboard text set." : action.error, data);
            failed = !action.ok;
            if (failed) break;
        } else if (words[0] == L"clipboard_paste") {
            std::wstring text = RestAfterFirstWord(line);
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ActionResult action = PasteClipboardText(window.hwnd, text, !text.empty());
            std::wstring pasteData = L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified)
                + L",\"pasted\":" + (action.pasted ? L"true" : L"false")
                + L",\"text_length\":" + std::to_wstring(action.textLength) + L"}";
            FinishStep(report, step, stepStartTick, action.ok, action.ok ? L"" : (action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode), action.ok ? L"Clipboard pasted." : action.error, pasteData);
            failed = !action.ok;
            if (failed) break;
        } else if (words[0] == L"focus") {
            if (words.size() != 1) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"focus takes no arguments.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            ActionResult action = FocusTargetWindow(window.hwnd);
            std::wstring focusData = L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified) + L"}";
            FinishStep(report, step, stepStartTick, action.ok, action.ok ? L"" : (action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode), action.ok ? L"Focused." : action.error, focusData);
            failed = !action.ok;
            if (failed) break;
        } else if (words[0] == L"uia_click") {
            std::wstring name = RestAfterFirstWord(line);
            if (name.empty()) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"uia_click requires an element name.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            UiaPatternActionResult action = InvokeUiaElementByName(window.hwnd, name);
            if (!action.found) {
                FinishStep(report, step, stepStartTick, false, action.errorCode, action.errorMessage, L"{\"locate_method\":\"uia\",\"requested_name\":" + JsonString(name) + L"}");
                failed = true;
                break;
            }
            std::wstring actionMethod = L"invoke_pattern";
            if (action.ok && action.patternAvailable) {
                if (!SleepCaseInterruptible(200)) {
                    FinishUserAbortStep(report, step, stepStartTick);
                    failed = true;
                    break;
                }
                FinishStep(report, step, stepStartTick, true, L"", L"UIA clicked.", UiaActionData(actionMethod, action.element, L"success"));
            } else if (action.patternAvailable && !action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.errorMessage, UiaActionData(actionMethod, action.element, L"failed"));
                failed = true;
                break;
            } else {
                actionMethod = L"mouse_center";
                int clientX = 0;
                int clientY = 0;
                if (!ElementCenterClientPoint(window.hwnd, action.element, clientX, clientY)) {
                    FinishStep(report, step, stepStartTick, false, L"UNKNOWN_ERROR", L"ScreenToClient failed for UIA element center.", UiaActionData(actionMethod, action.element, L"failed"));
                    failed = true;
                    break;
                }
                ClickResult click = ClickClientPoint(window.hwnd, clientX, clientY, L"human", 0);
                if (!click.ok) {
                    FinishStep(report, step, stepStartTick, false, click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, UiaActionData(actionMethod, action.element, L"failed"));
                    failed = true;
                    break;
                }
                FinishStep(report, step, stepStartTick, true, L"", L"UIA clicked.", UiaActionData(actionMethod, action.element, L"success", ActionFocusFields(window, report.targetTitle, click.foregroundBefore, click.foregroundAfter, click.focusVerified)));
            }
        } else if (words[0] == L"type") {
            if (words.size() < 2 || words.size() > 4) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"type requires: type text [type_mode] [char_delay_ms]. Text with spaces is not supported yet.", L"{}");
                failed = true;
                break;
            }
            std::wstring text = words[1];
            std::wstring typeMode = L"human";
            int charDelayMs = -1;
            if (words.size() >= 3) {
                typeMode = words[2];
            }
            if (!IsMotionModeAllowed(typeMode)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"type mode must be instant, fast-human, demo-human, or human.", L"{}");
                failed = true;
                break;
            }
            if (words.size() == 4 && (!ParseInt(words[3], charDelayMs) || charDelayMs < 0)) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"type char delay must be a non-negative integer.", L"{}");
                failed = true;
                break;
            }
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            TypeResult action = TypeText(window.hwnd, text, typeMode, charDelayMs);
            if (!action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.error, L"{}");
                failed = true;
                break;
            }
            std::wstring details = FormatTypeDetails(action);
            FinishStep(report, step, stepStartTick, true, L"", L"Typed text. " + details, L"{" + ActionFocusFields(window, report.targetTitle, action.foregroundBefore, action.foregroundAfter, action.focusVerified) + L",\"details\":" + JsonString(details) + L"}");
        } else if (words[0] == L"uia_type") {
            if (words.size() != 3) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"uia_type requires: uia_type name text. Text with spaces is not supported yet.", L"{}");
                failed = true;
                break;
            }
            std::wstring name = words[1];
            std::wstring text = words[2];
            WindowInfo window;
            std::wstring errorCode;
            std::wstring error;
            if (!ResolveUniqueWindow(report.targetTitle, window, errorCode, error)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, L"{\"target_title\":" + JsonString(report.targetTitle) + L"}");
                failed = true;
                break;
            }
            std::wstring safetyData;
            if (!EnforceWindowSafety(window, report.targetTitle, errorCode, error, safetyData)) {
                FinishStep(report, step, stepStartTick, false, errorCode, error, safetyData);
                failed = true;
                break;
            }
            UiaPatternActionResult action = SetUiaElementValueByName(window.hwnd, name, text);
            if (!action.found) {
                FinishStep(report, step, stepStartTick, false, action.errorCode, action.errorMessage, L"{\"locate_method\":\"uia\",\"requested_name\":" + JsonString(name) + L",\"text_length\":" + std::to_wstring(text.size()) + L"}");
                failed = true;
                break;
            }
            std::wstring actionMethod = L"value_pattern";
            std::wstring typeMode = L"value_pattern";
            if (action.ok && action.patternAvailable) {
                if (!SleepCaseInterruptible(200)) {
                    FinishUserAbortStep(report, step, stepStartTick);
                    failed = true;
                    break;
                }
                FinishStep(report, step, stepStartTick, true, L"", L"UIA typed.", UiaActionData(actionMethod, action.element, L"success", L"\"text_length\":" + std::to_wstring(text.size()) + L",\"type_mode\":" + JsonString(typeMode)));
            } else if (action.patternAvailable && !action.ok) {
                FinishStep(report, step, stepStartTick, false, action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.errorMessage, UiaActionData(actionMethod, action.element, L"failed", L"\"text_length\":" + std::to_wstring(text.size()) + L",\"type_mode\":" + JsonString(typeMode)));
                failed = true;
                break;
            } else {
                actionMethod = L"mouse_center_type";
                typeMode = L"human";
                int clientX = 0;
                int clientY = 0;
                if (!ElementCenterClientPoint(window.hwnd, action.element, clientX, clientY)) {
                    FinishStep(report, step, stepStartTick, false, L"UNKNOWN_ERROR", L"ScreenToClient failed for UIA element center.", UiaActionData(actionMethod, action.element, L"failed", L"\"text_length\":" + std::to_wstring(text.size()) + L",\"type_mode\":" + JsonString(typeMode)));
                    failed = true;
                    break;
                }
                ClickResult click = ClickClientPoint(window.hwnd, clientX, clientY, L"human", 0);
                if (!click.ok) {
                    FinishStep(report, step, stepStartTick, false, click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, UiaActionData(actionMethod, action.element, L"failed", L"\"text_length\":" + std::to_wstring(text.size()) + L",\"type_mode\":" + JsonString(typeMode)));
                    failed = true;
                    break;
                }
                TypeResult typed = TypeText(window.hwnd, text, L"human", -1);
                if (!typed.ok) {
                    FinishStep(report, step, stepStartTick, false, typed.errorCode.empty() ? L"UNKNOWN_ERROR" : typed.errorCode, typed.error, UiaActionData(actionMethod, action.element, L"failed", L"\"text_length\":" + std::to_wstring(text.size()) + L",\"type_mode\":" + JsonString(typeMode)));
                    failed = true;
                    break;
                }
                FinishStep(report, step, stepStartTick, true, L"", L"UIA typed.", UiaActionData(actionMethod, action.element, L"success", ActionFocusFields(window, report.targetTitle, typed.foregroundBefore, typed.foregroundAfter, typed.focusVerified) + L",\"text_length\":" + std::to_wstring(text.size()) + L",\"type_mode\":" + JsonString(typeMode)));
            }
        } else if (words[0] == L"read_file") {
            if (words.size() != 2) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"read_file requires one path.", L"{}");
                failed = true;
                break;
            }
            FileReadResult read;
            std::wstring normalizedPath;
            ReadAllowedTextFile(words[1], read, normalizedPath);
            step.content = read.content;
            if (read.ok) {
                report.readContents.push_back(read.content);
            }
            FinishStep(report, step, stepStartTick, read.ok, read.ok ? L"" : (read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode), read.ok ? L"Read file." : read.error, L"{\"path\":" + JsonString(normalizedPath.empty() ? words[1] : normalizedPath) + L"}");
            failed = !read.ok;
            if (failed) break;
        } else if (words[0] == L"assert_file_contains") {
            if (words.size() < 3) {
                FinishStep(report, step, stepStartTick, false, L"INVALID_ARGUMENT", L"assert_file_contains requires path and expected text.", L"{}");
                failed = true;
                break;
            }
            std::wstring expected = line.substr(line.find(words[1]) + words[1].size());
            expected = Trim(expected);
            FileReadResult read;
            std::wstring normalizedPath;
            ReadAllowedTextFile(words[1], read, normalizedPath);
            if (!read.ok) {
                FinishStep(report, step, stepStartTick, false, read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, read.error, L"{\"path\":" + JsonString(normalizedPath.empty() ? words[1] : normalizedPath) + L"}");
                failed = true;
                break;
            }
            bool contains = read.content.find(expected) != std::wstring::npos;
            FinishStep(report, step, stepStartTick, contains, contains ? L"" : L"ASSERTION_FAILED", contains ? L"Assertion passed." : L"Expected text not found: " + expected, L"{\"path\":" + JsonString(normalizedPath) + L",\"expected\":" + JsonString(expected) + L"}");
            failed = !contains;
            if (failed) break;
        } else {
            FinishStep(report, step, stepStartTick, false, L"CASE_PARSE_FAILED", L"Unknown case command: " + words[0], L"{}");
            failed = true;
            break;
        }
    }

    if (!failed && ElapsedMs(caseStartTick) > safetyPolicy.maxDurationMs) {
        report.failureErrorCode = L"CASE_DURATION_LIMIT_EXCEEDED";
        report.failureMessage = L"Case exceeded safety max_duration_ms.";
        report.failedStepIndex = stepCount;
        failed = true;
    }

    report.stepCount = static_cast<int>(report.steps.size());
    report.ok = !failed && report.failureErrorCode.empty();
    if (!report.ok && report.failureErrorCode.empty()) {
        report.failureErrorCode = L"UNKNOWN_ERROR";
        report.failureMessage = L"Case failed.";
    }
    report.endTime = CurrentTimestamp();
    report.totalDurationMs = ElapsedMs(caseStartTick);

    std::wstring reportError;
    if (!WriteMarkdownReport(reportPath, report, reportError)) {
        runResult.errorCode = L"UNKNOWN_ERROR";
        runResult.error = L"Case finished but report write failed: " + reportError;
        return runResult;
    }

    runResult.ok = report.ok;
    runResult.errorCode = report.failureErrorCode;
    runResult.error = report.failureMessage;
    runResult.stepCount = report.stepCount;
    runResult.passedStepCount = report.passedStepCount;
    runResult.failedStepIndex = report.failedStepIndex;
    return runResult;
}
