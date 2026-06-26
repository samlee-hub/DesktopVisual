#include "TaskSession.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include "AdaptiveHumanMode.h"
#include "CaseRunner.h"
#include "CompiledPlanExecutor.h"
#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Trace.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cwctype>
#include <cstdio>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <thread>
#include <vector>

namespace {

const wchar_t* kTaskSessionRuntimeVersion = L"5.10.2";
const wchar_t* kTaskSessionProtocolVersion = L"5.0";

std::wstring JsonGetString(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'"') return L"";
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) { ++pos; }
        value += json[pos];
        ++pos;
    }
    return value;
}

int JsonGetInt(const std::wstring& json, const std::wstring& key, int def = 0) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    try { return std::stoi(json.substr(pos)); } catch (...) { return def; }
}

bool JsonGetBool(const std::wstring& json, const std::wstring& key, bool def = false) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (json.substr(pos, 4) == L"true") return true;
    if (json.substr(pos, 5) == L"false") return false;
    return def;
}

std::wstring JsonGetObject(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'{') return L"";
    int depth = 1;
    size_t start = pos++;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'{') ++depth;
        else if (json[pos] == L'}') --depth;
        ++pos;
    }
    return depth == 0 ? json.substr(start, pos - start) : L"";
}

std::wstring JsonGetArray(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'[') return L"";
    int depth = 1;
    size_t start = pos++;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'[') ++depth;
        else if (json[pos] == L']') --depth;
        ++pos;
    }
    return depth == 0 ? json.substr(start, pos - start) : L"";
}

std::vector<std::wstring> JsonStringArrayValues(const std::wstring& arrayJson) {
    std::vector<std::wstring> values;
    if (arrayJson.empty() || arrayJson.front() != L'[') return values;
    size_t pos = 1;
    while (pos < arrayJson.size()) {
        while (pos < arrayJson.size() && (iswspace(arrayJson[pos]) || arrayJson[pos] == L',')) ++pos;
        if (pos >= arrayJson.size() || arrayJson[pos] == L']') break;
        if (arrayJson[pos] != L'"') {
            ++pos;
            continue;
        }
        ++pos;
        std::wstring value;
        while (pos < arrayJson.size() && arrayJson[pos] != L'"') {
            if (arrayJson[pos] == L'\\' && pos + 1 < arrayJson.size()) { ++pos; }
            value += arrayJson[pos];
            ++pos;
        }
        values.push_back(value);
        if (pos < arrayJson.size()) ++pos;
    }
    return values;
}

int CountObjectArrayItems(const std::wstring& arrayJson) {
    if (arrayJson.empty() || arrayJson.front() != L'[') return 0;
    int count = 0;
    size_t pos = 1;
    while (pos < arrayJson.size()) {
        if (arrayJson[pos] == L'{') {
            ++count;
            int depth = 1;
            ++pos;
            while (pos < arrayJson.size() && depth > 0) {
                if (arrayJson[pos] == L'{') ++depth;
                else if (arrayJson[pos] == L'}') --depth;
                ++pos;
            }
        } else {
            ++pos;
        }
    }
    return count;
}

bool ContainsValue(const std::vector<std::wstring>& values, const std::wstring& expected) {
    return std::find(values.begin(), values.end(), expected) != values.end();
}

bool IsTerminalState(TaskSessionState state) {
    return state == TaskSessionState::Completed ||
           state == TaskSessionState::Failed ||
           state == TaskSessionState::Stopped ||
           state == TaskSessionState::Blocked;
}

bool IsNonTerminalActiveState(TaskSessionState state) {
    return state == TaskSessionState::Running ||
           state == TaskSessionState::Waiting ||
           state == TaskSessionState::Verifying ||
           state == TaskSessionState::Recovering ||
           state == TaskSessionState::Confirmed;
}

bool IsAllowedGenericTransition(TaskSessionState from, TaskSessionState to) {
    if (from == TaskSessionState::Pending) {
        return to == TaskSessionState::Running || to == TaskSessionState::Stopped;
    }
    if (from == TaskSessionState::Running) {
        return to == TaskSessionState::Waiting ||
               to == TaskSessionState::Verifying ||
               to == TaskSessionState::Recovering ||
               to == TaskSessionState::Completed ||
               to == TaskSessionState::Failed ||
               to == TaskSessionState::Stopped ||
               to == TaskSessionState::Blocked;
    }
    if (from == TaskSessionState::Waiting) {
        return to == TaskSessionState::Running ||
               to == TaskSessionState::Verifying ||
               to == TaskSessionState::Failed ||
               to == TaskSessionState::Stopped ||
               to == TaskSessionState::Blocked;
    }
    if (from == TaskSessionState::Verifying) {
        return to == TaskSessionState::Confirmed ||
               to == TaskSessionState::Recovering ||
               to == TaskSessionState::Completed ||
               to == TaskSessionState::Failed ||
               to == TaskSessionState::Stopped ||
               to == TaskSessionState::Blocked;
    }
    if (from == TaskSessionState::Recovering) {
        return to == TaskSessionState::Running ||
               to == TaskSessionState::Verifying ||
               to == TaskSessionState::Failed ||
               to == TaskSessionState::Stopped ||
               to == TaskSessionState::Blocked;
    }
    if (from == TaskSessionState::Confirmed) {
        return to == TaskSessionState::Completed ||
               to == TaskSessionState::Failed ||
               to == TaskSessionState::Stopped;
    }
    return false;
}

std::vector<std::wstring> RequiredStateNames() {
    return {
        L"pending",
        L"running",
        L"waiting",
        L"verifying",
        L"recovering",
        L"confirmed",
        L"completed",
        L"failed",
        L"stopped",
        L"blocked"
    };
}

std::vector<std::wstring> AllowedEscalationReasons() {
    return {
        L"semantic_unresolved",
        L"unknown_scene",
        L"unexpected_dialog",
        L"multiple_candidates_low_confidence",
        L"profile_mismatch",
        L"task_replanning_needed",
        L"user_confirmation_required"
    };
}

TaskSessionValidationResult Invalid(const TaskSession& session, const std::wstring& message) {
    TaskSessionValidationResult result;
    result.ok = false;
    result.errorCode = L"TASK_SESSION_SCHEMA_INVALID";
    result.errorMessage = message;
    result.session = session;
    result.dataJson = TaskSessionDataJson(session);
    return result;
}

bool RequireString(const TaskSession& session, const std::wstring& value, const std::wstring& field, TaskSessionValidationResult& out) {
    if (!value.empty()) return true;
    out = Invalid(session, L"TaskSession missing required field: " + field);
    return false;
}

std::wstring StringArrayJsonCountOnly(int count) {
    return std::to_wstring(count);
}

std::wstring NormalizeSeparators(std::wstring value) {
    std::replace(value.begin(), value.end(), L'/', L'\\');
    return value;
}

bool IsAbsolutePath(const std::wstring& path) {
    return path.size() > 2 && path[1] == L':';
}

std::wstring ResolveProjectMaybeRelative(const std::wstring& path) {
    std::wstring normalized = NormalizeSeparators(path);
    if (IsAbsolutePath(normalized)) return normalized;
    return ProjectPath(normalized);
}

bool WriteTextFileUtf8ish(const std::wstring& path, const std::wstring& content, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open output file: " + path;
        return false;
    }
    fwprintf(file, L"%ls", content.c_str());
    fclose(file);
    return true;
}

TaskSessionRunResult RunFailure(
    const std::wstring& code,
    const std::wstring& message,
    const std::wstring& dataJson = L"{}") {
    TaskSessionRunResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = dataJson;
    return result;
}

TaskTransitionResult TransitionInvalid(
    const TaskSession& session,
    const TaskTransitionRequest& request,
    const std::wstring& message) {
    TaskTransitionResult result;
    result.ok = false;
    result.errorCode = L"TASK_TRANSITION_INVALID";
    result.errorMessage = message;
    result.action = request.action;
    result.previousState = TaskSessionStateName(request.fromState);
    result.currentState = result.previousState;
    result.reason = request.reason;
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(session.taskId)
         << L",\"action\":" << JsonString(request.action)
         << L",\"previous_state\":" << JsonString(result.previousState)
         << L",\"current_state\":" << JsonString(result.currentState)
         << L",\"transition\":{\"valid\":false,\"reason\":" << JsonString(message) << L"}}";
    result.dataJson = data.str();
    return result;
}

std::wstring StepEventJson(const std::wstring& taskId, const std::wstring& stepId, int index, const std::wstring& state, const std::wstring& message) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"5.0.4\""
         << L",\"runtime_version\":\"" << kTaskSessionRuntimeVersion << L"\""
         << L",\"protocol_version\":\"" << kTaskSessionProtocolVersion << L"\""
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"task_id\":" << JsonString(taskId)
         << L",\"step_index\":" << index
         << L",\"step_id\":" << JsonString(stepId)
         << L",\"state\":" << JsonString(state)
         << L",\"ok\":true"
         << L",\"message\":" << JsonString(message)
         << L"}";
    return json.str();
}

std::wstring SafeTaskIdFileName(const std::wstring& taskId) {
    std::wstring safe;
    for (wchar_t ch : taskId) {
        if ((ch >= L'a' && ch <= L'z') ||
            (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'0' && ch <= L'9') ||
            ch == L'_' || ch == L'-' || ch == L'.') {
            safe += ch;
        } else {
            safe += L'_';
        }
    }
    return safe.empty() ? L"unknown_task" : safe;
}

std::wstring StableTaskRegistryDir() {
    return ArtifactsPath(L"task_runtime_v5_7\\tasks");
}

std::wstring StableTaskRegistryPath(const std::wstring& taskId) {
    return StableTaskRegistryDir() + L"\\" + SafeTaskIdFileName(taskId) + L".json";
}

std::wstring ReadableStatusJson(const std::wstring& state, bool ok, bool terminal, bool cancellable, const std::wstring& errorCode) {
    std::wstringstream status;
    status << L"{\"state\":" << JsonString(state)
           << L",\"ok\":" << (ok ? L"true" : L"false")
           << L",\"terminal\":" << (terminal ? L"true" : L"false")
           << L",\"cancellable\":" << (cancellable ? L"true" : L"false")
           << L",\"error_code\":" << JsonString(errorCode)
           << L"}";
    return status.str();
}

std::wstring StopCodeForCancelReason(const std::wstring& reason) {
    std::wstring lower = reason;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    if (lower.find(L"confirmation") != std::wstring::npos && lower.find(L"timeout") != std::wstring::npos) {
        return L"CONFIRMATION_TIMEOUT_STOP";
    }
    if (lower.find(L"provider") != std::wstring::npos && lower.find(L"unavailable") != std::wstring::npos) {
        return L"PROVIDER_UNAVAILABLE_STOP";
    }
    if (lower.find(L"safety") != std::wstring::npos) {
        return L"SAFETY_STOP";
    }
    if (lower.find(L"timeout") != std::wstring::npos) {
        return L"TASK_TIMEOUT_CANCELLED";
    }
    return L"TASK_CANCELLED";
}

std::wstring StatusForStopCode(const std::wstring& stopCode) {
    if (stopCode == L"TASK_CANCELLED") return L"cancelled";
    if (stopCode == L"TASK_TIMEOUT_CANCELLED") return L"timeout_cancelled";
    if (stopCode == L"SAFETY_STOP") return L"safety_stopped";
    if (stopCode == L"PROVIDER_UNAVAILABLE_STOP") return L"provider_unavailable_stopped";
    if (stopCode == L"CONFIRMATION_TIMEOUT_STOP") return L"confirmation_timeout_stopped";
    return L"stopped";
}

std::wstring TaskRecordJson(
    const TaskSession& session,
    const std::wstring& state,
    bool ok,
    bool terminal,
    bool cancellable,
    const std::wstring& errorCode,
    const std::wstring& message,
    const std::wstring& eventsPath,
    const std::wstring& resultPath,
    const std::wstring& reportPath,
    const std::wstring& stateDumpPath,
    const std::wstring& failureDumpPath,
    const std::wstring& evidenceIndexPath) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"5.7.1\""
         << L",\"task_id\":" << JsonString(session.taskId)
         << L",\"task_type\":" << JsonString(session.taskType)
         << L",\"current_state\":" << JsonString(state)
         << L",\"status\":" << JsonString(ok ? L"completed" : (terminal ? L"stopped" : L"running"))
         << L",\"ok\":" << (ok ? L"true" : L"false")
         << L",\"terminal\":" << (terminal ? L"true" : L"false")
         << L",\"cancellable\":" << (cancellable ? L"true" : L"false")
         << L",\"error_code\":" << JsonString(errorCode)
         << L",\"message\":" << JsonString(message)
         << L",\"updated_at\":" << JsonString(NowTimestamp())
         << L",\"machine_readable_status\":" << ReadableStatusJson(state, ok, terminal, cancellable, errorCode)
         << L",\"artifacts\":{\"events_jsonl\":" << JsonString(eventsPath)
         << L",\"task_result_json\":" << JsonString(resultPath)
         << L",\"task_report_md\":" << JsonString(reportPath)
         << L",\"current_state_json\":" << JsonString(stateDumpPath)
         << L",\"failure_dump_json\":" << JsonString(failureDumpPath)
         << L",\"evidence_index_md\":" << JsonString(evidenceIndexPath)
         << L"}}";
    return json.str();
}

TaskSessionControlResult ControlFailure(const std::wstring& code, const std::wstring& message, const std::wstring& dataJson = L"{}") {
    TaskSessionControlResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = dataJson;
    return result;
}

TaskSessionControlResult ControlSuccess(const std::wstring& dataJson, const std::vector<std::wstring>& artifacts = {}, const std::wstring& reportPath = L"") {
    TaskSessionControlResult result;
    result.ok = true;
    result.dataJson = dataJson;
    result.artifacts = artifacts;
    result.reportPath = reportPath;
    return result;
}

TaskSessionControlResult LoadStableTaskRecord(const std::wstring& taskId, const std::wstring& file, std::wstring& recordJson, TaskSession* sessionOut = nullptr) {
    std::wstring resolvedTaskId = taskId;
    TaskSession session;
    if (resolvedTaskId.empty() && !file.empty()) {
        TaskSessionValidationResult loaded = ValidateTaskSessionFile(file);
        if (!loaded.ok) {
            return ControlFailure(loaded.errorCode.empty() ? L"TASK_SESSION_SCHEMA_INVALID" : loaded.errorCode, loaded.errorMessage, loaded.dataJson);
        }
        session = loaded.session;
        resolvedTaskId = session.taskId;
    }
    if (resolvedTaskId.empty()) {
        return ControlFailure(L"INVALID_ARGUMENT", L"task_id or file is required.");
    }
    FileReadResult read = ReadTextFile(StableTaskRegistryPath(resolvedTaskId));
    if (!read.ok) {
        return ControlFailure(read.errorCode.empty() ? L"TASK_NOT_FOUND" : read.errorCode, L"Task status record was not found for task_id: " + resolvedTaskId);
    }
    recordJson = read.content;
    if (!recordJson.empty() && recordJson[0] == 0xfeff) {
        recordJson.erase(recordJson.begin());
    }
    if (sessionOut) {
        if (session.taskId.empty() && !file.empty()) {
            TaskSessionValidationResult loaded = ValidateTaskSessionFile(file);
            if (loaded.ok) session = loaded.session;
        }
        if (session.taskId.empty()) {
            session.taskId = JsonGetString(recordJson, L"task_id");
            session.taskType = JsonGetString(recordJson, L"task_type");
        }
        *sessionOut = session;
    }
    return ControlSuccess(recordJson);
}

int CountJsonlEvents(const std::wstring& content) {
    if (content.empty()) return 0;
    int count = 0;
    bool hasAnyOnLine = false;
    for (wchar_t ch : content) {
        if (ch == L'\n') {
            if (hasAnyOnLine) ++count;
            hasAnyOnLine = false;
        } else if (ch != L'\r' && !iswspace(ch)) {
            hasAnyOnLine = true;
        }
    }
    if (hasAnyOnLine) ++count;
    return count;
}

std::wstring ToLowerLocal(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitiveLocal(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return true;
    return ToLowerLocal(haystack).find(ToLowerLocal(needle)) != std::wstring::npos;
}

std::wstring SafeFilePart(std::wstring value) {
    for (wchar_t& ch : value) {
        bool ok = (ch >= L'a' && ch <= L'z') ||
                  (ch >= L'A' && ch <= L'Z') ||
                  (ch >= L'0' && ch <= L'9') ||
                  ch == L'_' || ch == L'-' || ch == L'.';
        if (!ok) ch = L'_';
    }
    return value.empty() ? L"item" : value;
}

std::wstring SequencePrefix(int sequence) {
    std::wstringstream stream;
    stream << std::setw(4) << std::setfill(L'0') << sequence;
    return stream.str();
}

std::wstring JsonStringArrayLocal(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::vector<std::wstring> JsonObjectArrayLocal(const std::wstring& arrayJson) {
    std::vector<std::wstring> result;
    if (arrayJson.empty() || arrayJson.front() != L'[') return result;
    size_t pos = 1;
    while (pos < arrayJson.size()) {
        while (pos < arrayJson.size() && (iswspace(arrayJson[pos]) || arrayJson[pos] == L',')) ++pos;
        if (pos >= arrayJson.size() || arrayJson[pos] == L']') break;
        if (arrayJson[pos] != L'{') {
            ++pos;
            continue;
        }
        size_t start = pos;
        int depth = 1;
        ++pos;
        bool inString = false;
        bool escaped = false;
        while (pos < arrayJson.size() && depth > 0) {
            wchar_t ch = arrayJson[pos];
            if (inString) {
                if (escaped) {
                    escaped = false;
                } else if (ch == L'\\') {
                    escaped = true;
                } else if (ch == L'"') {
                    inString = false;
                }
            } else {
                if (ch == L'"') inString = true;
                else if (ch == L'{') ++depth;
                else if (ch == L'}') --depth;
            }
            ++pos;
        }
        if (depth == 0) result.push_back(arrayJson.substr(start, pos - start));
    }
    return result;
}

bool JsonGetRect(const std::wstring& json, const std::wstring& key, RECT& rect) {
    std::wstring object = JsonGetObject(json, key);
    if (object.empty()) return false;
    rect.left = JsonGetInt(object, L"left", 0);
    rect.top = JsonGetInt(object, L"top", 0);
    rect.right = JsonGetInt(object, L"right", 0);
    rect.bottom = JsonGetInt(object, L"bottom", 0);
    return rect.right > rect.left && rect.bottom > rect.top;
}

bool IsPathUnderDirectoryLocal(const std::wstring& path, const std::wstring& root) {
    wchar_t fullPath[MAX_PATH] = {};
    wchar_t fullRoot[MAX_PATH] = {};
    if (!GetFullPathNameW(path.c_str(), MAX_PATH, fullPath, nullptr)) return false;
    if (!GetFullPathNameW(root.c_str(), MAX_PATH, fullRoot, nullptr)) return false;
    std::wstring p = fullPath;
    std::wstring r = fullRoot;
    std::transform(p.begin(), p.end(), p.begin(), [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
    std::transform(r.begin(), r.end(), r.begin(), [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
    if (!r.empty() && r.back() != L'\\') r += L"\\";
    return p.rfind(r, 0) == 0;
}

void ClearDirectoryContentsUnderArtifacts(const std::wstring& dir) {
    if (dir.empty() || !IsPathUnderDirectoryLocal(dir, ProjectPath(L"artifacts"))) return;
    WIN32_FIND_DATAW data = {};
    HANDLE handle = FindFirstFileW((dir + L"\\*").c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE) return;
    do {
        std::wstring name = data.cFileName;
        if (name == L"." || name == L"..") continue;
        std::wstring child = dir + L"\\" + name;
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            ClearDirectoryContentsUnderArtifacts(child);
            RemoveDirectoryW(child.c_str());
        } else {
            SetFileAttributesW(child.c_str(), FILE_ATTRIBUTE_NORMAL);
            DeleteFileW(child.c_str());
        }
    } while (FindNextFileW(handle, &data));
    FindClose(handle);
}

std::wstring RectJsonLocal(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring CommandLineQuote(const std::wstring& arg) {
    if (arg.empty()) return L"\"\"";
    bool needsQuote = false;
    for (wchar_t ch : arg) {
        if (iswspace(ch) || ch == L'"' || ch == L'&' || ch == L'|' || ch == L'<'
            || ch == L'>' || ch == L'^') {
            needsQuote = true;
            break;
        }
    }
    if (!needsQuote) return arg;
    std::wstring quoted = L"\"";
    for (wchar_t ch : arg) {
        if (ch == L'"') quoted += L"\\\"";
        else quoted += ch;
    }
    quoted += L"\"";
    return quoted;
}

std::string WideToUtf8(const std::wstring& text) {
    if (text.empty()) return std::string();
    int len = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (len <= 0) return std::string();
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), &out[0], len, nullptr, nullptr);
    return out;
}

class LocalhostMailMockServer {
public:
    ~LocalhostMailMockServer() {
        Stop();
    }

    bool Start(int preferredPort, int& boundPort, std::wstring& error) {
        WSADATA data = {};
        int startup = WSAStartup(MAKEWORD(2, 2), &data);
        if (startup != 0) {
            error = L"WSAStartup failed: " + std::to_wstring(startup);
            return false;
        }
        wsaStarted_ = true;
        body_ = WideToUtf8(Html());

        for (int port = preferredPort; port < preferredPort + 30; ++port) {
            SOCKET candidate = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            if (candidate == INVALID_SOCKET) continue;
            BOOL reuse = TRUE;
            setsockopt(candidate, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse), sizeof(reuse));
            sockaddr_in addr = {};
            addr.sin_family = AF_INET;
            addr.sin_port = htons(static_cast<u_short>(port));
            inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
            if (bind(candidate, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0 &&
                listen(candidate, SOMAXCONN) == 0) {
                listenSocket_ = candidate;
                port_ = port;
                stop_.store(false);
                worker_ = std::thread([this]() { ServeLoop(); });
                boundPort = port;
                return true;
            }
            closesocket(candidate);
        }

        error = L"Could not bind localhost server to 127.0.0.1.";
        Stop();
        return false;
    }

    void Stop() {
        bool wasStopped = stop_.exchange(true);
        if (!wasStopped) {
            WakeListener();
        }
        if (worker_.joinable()) {
            worker_.join();
        }
        if (listenSocket_ != INVALID_SOCKET) {
            closesocket(listenSocket_);
            listenSocket_ = INVALID_SOCKET;
        }
        if (wsaStarted_) {
            WSACleanup();
            wsaStarted_ = false;
        }
    }

    static std::wstring Html() {
        return
            L"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            L"<title>DesktopVisual Local Mail Mock</title>"
            L"<style>body{font-family:Arial,sans-serif;margin:48px;max-width:760px}"
            L"h1{margin:0 0 12px 0;font-size:28px}p{margin:0 0 20px 0;color:#333}"
            L"label{display:block;margin-top:16px;font-weight:700}"
            L"input,textarea{display:block;width:680px;padding:9px;margin-top:5px;font-size:16px;box-sizing:border-box}"
            L"textarea{height:136px;resize:none}button{margin-top:20px;padding:10px 20px;font-size:16px;border:1px solid #555;background:#f2f2f2}"
            L"#status{margin-top:18px;padding:10px;border:1px solid #999;min-height:24px}</style></head>"
            L"<body><h1>DesktopVisual Local Mail Mock</h1>"
            L"<p>This page is a local mock. It does not send real email.</p>"
            L"<label for=\"recipient\">Recipient</label><input aria-label=\"Recipient\" id=\"recipient\" name=\"recipient\" autocomplete=\"off\">"
            L"<label for=\"subject\">Subject</label><input aria-label=\"Subject\" id=\"subject\" name=\"subject\" autocomplete=\"off\">"
            L"<label for=\"body\">Body</label><textarea aria-label=\"Body\" id=\"body\" name=\"body\"></textarea>"
            L"<button aria-label=\"Send\" id=\"sendButton\" type=\"button\">Send</button>"
            L"<div id=\"status\" role=\"status\">Not sent</div>"
            L"<script>document.getElementById('sendButton').addEventListener('click',function(){"
            L"document.getElementById('recipient').value='';"
            L"document.getElementById('subject').value='';"
            L"document.getElementById('body').value='';"
            L"document.getElementById('status').textContent='Mock sent successfully';"
            L"document.body.setAttribute('data-sent','true');});</script></body></html>";
    }

private:
    void WakeListener() const {
        if (listenSocket_ == INVALID_SOCKET || port_ <= 0) return;
        SOCKET client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (client == INVALID_SOCKET) return;
        sockaddr_in addr = {};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(static_cast<u_short>(port_));
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
        connect(client, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
        shutdown(client, SD_BOTH);
        closesocket(client);
    }

    void ServeLoop() {
        while (!stop_.load()) {
            fd_set readSet;
            FD_ZERO(&readSet);
            FD_SET(listenSocket_, &readSet);
            timeval timeout = {};
            timeout.tv_sec = 0;
            timeout.tv_usec = 200000;
            int ready = select(0, &readSet, nullptr, nullptr, &timeout);
            if (ready <= 0 || stop_.load()) continue;
            SOCKET client = accept(listenSocket_, nullptr, nullptr);
            if (client == INVALID_SOCKET) continue;
            char buffer[2048] = {};
            recv(client, buffer, sizeof(buffer) - 1, 0);
            std::string header =
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: text/html; charset=utf-8\r\n"
                "Cache-Control: no-store\r\n"
                "Content-Length: " + std::to_string(body_.size()) + "\r\n"
                "Connection: close\r\n\r\n";
            send(client, header.c_str(), static_cast<int>(header.size()), 0);
            send(client, body_.c_str(), static_cast<int>(body_.size()), 0);
            shutdown(client, SD_SEND);
            closesocket(client);
        }
    }

    SOCKET listenSocket_ = INVALID_SOCKET;
    std::thread worker_;
    std::atomic<bool> stop_{false};
    bool wsaStarted_ = false;
    int port_ = 0;
    std::string body_;
};

struct RuntimeCommandResult {
    int sequence = 0;
    std::wstring step;
    std::wstring command;
    std::vector<std::wstring> args;
    int exitCode = 0;
    std::wstring output;
    std::wstring outputPath;
    bool ok = false;
};

struct RuntimeTargetCandidate {
    std::wstring candidateJson;
    std::wstring name;
    std::wstring role;
    std::wstring source;
    RECT rect = {};
    int centerX = 0;
    int centerY = 0;
};

struct TaskRuntimeEvidenceContext {
    TaskSession session;
    std::wstring artifactRoot;
    std::wstring eventsPath;
    std::wstring resultPath;
    std::wstring reportPath;
    std::wstring actionTracePath;
    std::wstring locatorTracePath;
    std::wstring adaptiveLoopTracePath;
    std::wstring humanResultsPath;
    std::wstring rawCommandLogPath;
    std::wstring verificationReportPath;
    std::wstring rawOutputDir;
    std::wstring screenshotsDir;
    std::wstring overlaysDir;
    int sequence = 0;
    int completedSteps = 0;
    int failedSteps = 0;
    int backendActionCount = 0;
    int jsDomActionCount = 0;
    int webdriverCount = 0;
    int cdpCount = 0;
    int uiaInvokeActionCount = 0;
    int uiaValueActionCount = 0;
    bool recipientVerified = false;
    bool subjectVerified = false;
    bool bodyVerified = false;
    bool statusVerified = false;
    bool fieldsClearedVerified = false;
    bool localhostBoundLocalOnly = false;
    int serverPort = 0;
    std::wstring browserTitle;
    std::wstring browserProcess;
    std::wstringstream events;
    std::wstringstream rawCommands;
    std::wstringstream actionTrace;
    std::wstringstream locatorTrace;
    std::wstringstream adaptiveLoopTrace;
    std::wstringstream humanResults;
};

void RecordTaskRuntimeEvent(TaskRuntimeEvidenceContext& ctx, const std::wstring& stepId, bool ok, const std::wstring& message) {
    if (ok) ++ctx.completedSteps;
    else ++ctx.failedSteps;
    ctx.events << L"{\"schema_version\":\"5.10.2.task_event\""
               << L",\"runtime_version\":\"5.10.2\""
               << L",\"timestamp\":" << JsonString(NowTimestamp())
               << L",\"task_id\":" << JsonString(ctx.session.taskId)
               << L",\"step_id\":" << JsonString(stepId)
               << L",\"state\":" << JsonString(ok ? L"completed" : L"failed")
               << L",\"ok\":" << (ok ? L"true" : L"false")
               << L",\"message\":" << JsonString(message)
               << L"}\n";
}

RuntimeCommandResult RunRuntimeCommand(TaskRuntimeEvidenceContext& ctx, const std::wstring& step, const std::vector<std::wstring>& args) {
    RuntimeCommandResult result;
    result.sequence = ++ctx.sequence;
    result.step = step;
    result.args = args;
    result.command = args.empty() ? L"" : args.front();

    std::wstring exe = ProjectPath(L"bin\\winagent.exe");
    std::wstring commandLine = CommandLineQuote(exe);
    for (const auto& arg : args) {
        commandLine += L" ";
        commandLine += CommandLineQuote(arg);
    }
    commandLine += L" 2>&1";

    FILE* pipe = _wpopen(commandLine.c_str(), L"rt");
    if (!pipe) {
        result.exitCode = 127;
        result.output = L"{\"ok\":false,\"error\":{\"code\":\"COMMAND_START_FAILED\",\"message\":\"_wpopen failed\"}}";
    } else {
        wchar_t buffer[4096] = {};
        while (fgetws(buffer, static_cast<int>(sizeof(buffer) / sizeof(buffer[0])), pipe)) {
            result.output += buffer;
        }
        result.exitCode = _pclose(pipe);
    }
    while (!result.output.empty() && (result.output.back() == L'\r' || result.output.back() == L'\n')) {
        result.output.pop_back();
    }
    result.ok = result.exitCode == 0 && JsonGetBool(result.output, L"ok", false);
    result.outputPath = ctx.rawOutputDir + L"\\" + SequencePrefix(result.sequence)
        + L"_" + SafeFilePart(step) + L".stdout.json";
    std::wstring writeError;
    WriteTextFileUtf8ish(result.outputPath, result.output, writeError);

    ctx.rawCommands << L"{\"sequence\":" << result.sequence
                    << L",\"step\":" << JsonString(step)
                    << L",\"command\":" << JsonString(result.command)
                    << L",\"args\":" << JsonStringArrayLocal(args)
                    << L",\"exit_code\":" << result.exitCode
                    << L",\"ok\":" << (result.ok ? L"true" : L"false")
                    << L",\"stdout_path\":" << JsonString(result.outputPath)
                    << L"}\n";

    std::wstring data = JsonGetObject(result.output, L"data");
    std::wstring human = JsonGetObject(data, L"human_action_result");
    if (!human.empty()) {
        ctx.humanResults << L"{\"sequence\":" << result.sequence
                         << L",\"step\":" << JsonString(step)
                         << L",\"command\":" << JsonString(result.command)
                         << L",\"human_action_result\":" << human
                         << L"}\n";
        ctx.actionTrace << L"{\"sequence\":" << result.sequence
                        << L",\"step\":" << JsonString(step)
                        << L",\"command\":" << JsonString(result.command)
                        << L",\"trace_source\":\"derived_from_raw_winagent_command_output\""
                        << L",\"human_action_result\":" << human
                        << L"}\n";
        if (human.find(L"\"backend_action\":true") != std::wstring::npos) ++ctx.backendActionCount;
    }

    if (result.command.rfind(L"adaptive-", 0) == 0 || result.command == L"observe" || result.command == L"read-window-text") {
        ctx.adaptiveLoopTrace << L"{\"sequence\":" << result.sequence
                              << L",\"step\":" << JsonString(step)
                              << L",\"command\":" << JsonString(result.command)
                              << L",\"ok\":" << (result.ok ? L"true" : L"false")
                              << L",\"trace_source\":\"derived_from_raw_winagent_command_output\""
                              << L",\"stdout_path\":" << JsonString(result.outputPath)
                              << L"}\n";
    }

    return result;
}

bool ParseSelectedCandidate(const RuntimeCommandResult& command, RuntimeTargetCandidate& candidate) {
    std::wstring data = JsonGetObject(command.output, L"data");
    std::wstring selected = JsonGetObject(data, L"selected_candidate");
    if (selected.empty()) return false;
    candidate.candidateJson = selected;
    candidate.name = JsonGetString(selected, L"matched_name");
    candidate.role = JsonGetString(selected, L"role");
    candidate.source = JsonGetString(selected, L"source");
    candidate.centerX = JsonGetInt(selected, L"center_x", 0);
    candidate.centerY = JsonGetInt(selected, L"center_y", 0);
    return JsonGetRect(selected, L"rect", candidate.rect);
}

void AppendLocatorTrace(TaskRuntimeEvidenceContext& ctx, const RuntimeCommandResult& command, const RuntimeTargetCandidate& candidate) {
    std::wstring data = JsonGetObject(command.output, L"data");
    ctx.locatorTrace << L"{\"sequence\":" << command.sequence
                     << L",\"step\":" << JsonString(command.step)
                     << L",\"command\":" << JsonString(command.command)
                     << L",\"trace_source\":\"derived_from_raw_winagent_command_output\""
                     << L",\"selected_candidate\":" << candidate.candidateJson
                     << L",\"rejected_candidates\":" << (JsonGetArray(data, L"rejected_candidates").empty() ? L"[]" : JsonGetArray(data, L"rejected_candidates"))
                     << L"}\n";
}

bool LocateAdaptiveTarget(
    TaskRuntimeEvidenceContext& ctx,
    const std::wstring& title,
    const std::wstring& process,
    const std::wstring& target,
    const std::wstring& role,
    const std::wstring& kind,
    const std::wstring& step,
    RuntimeTargetCandidate& candidate) {
    RuntimeCommandResult located = RunRuntimeCommand(ctx, step, {
        L"adaptive-locate",
        L"--target", target,
        L"--target-kind", kind,
        L"--role", role,
        L"--title", title,
        L"--process", process
    });
    if (!located.ok || !ParseSelectedCandidate(located, candidate)) return false;
    if (candidate.source != L"uia") return false;
    AppendLocatorTrace(ctx, located, candidate);
    return true;
}

bool ParseAddressBarCandidate(const RuntimeCommandResult& observe, RuntimeTargetCandidate& candidate) {
    std::wstring data = JsonGetObject(observe.output, L"data");
    std::wstring uia = JsonGetObject(data, L"uia");
    std::wstring elements = JsonGetArray(uia, L"elements");
    int bestScore = -1000000;
    for (const auto& element : JsonObjectArrayLocal(elements)) {
        if (JsonGetString(element, L"control_type") != L"Edit") continue;
        RECT rect = {};
        if (!JsonGetRect(element, L"rect", rect)) continue;
        int width = rect.right - rect.left;
        int height = rect.bottom - rect.top;
        if (width < 240 || height < 16 || height > 80) continue;
        if (rect.left < 0 || rect.top < 0) continue;

        std::wstring name = JsonGetString(element, L"name");
        std::wstring value = JsonGetString(element, L"value");
        bool semanticAddressBar =
            ContainsInsensitiveLocal(name, L"address") ||
            ContainsInsensitiveLocal(name, L"url") ||
            ContainsInsensitiveLocal(value, L"address") ||
            ContainsInsensitiveLocal(value, L"url") ||
            name.find(L"\x5730\x5740") != std::wstring::npos ||
            value.find(L"\x5730\x5740") != std::wstring::npos ||
            ContainsInsensitiveLocal(name, L"\\u5730\\u5740") ||
            ContainsInsensitiveLocal(value, L"\\u5730\\u5740") ||
            ContainsInsensitiveLocal(name, L"u5730u5740") ||
            ContainsInsensitiveLocal(value, L"u5730u5740");
        if (!semanticAddressBar) continue;

        int score = width;
        if (ContainsInsensitiveLocal(name, L"address") ||
            ContainsInsensitiveLocal(name, L"\\u5730\\u5740") ||
            ContainsInsensitiveLocal(name, L"u5730u5740") ||
            name.find(L"\x5730\x5740") != std::wstring::npos) {
            score += 1000;
        }
        if (rect.top < 500) score += 400;
        score -= rect.top / 4;
        if (score > bestScore) {
            bestScore = score;
            candidate.candidateJson = L"{\"candidate_id\":\"observe:address_bar\",\"target_id\":\"address_bar\",\"matched_name\":"
                + JsonString(name)
                + L",\"matched_text\":" + JsonString(name)
                + L",\"role\":\"Edit\",\"source\":\"uia_address_bar\",\"rect\":" + RectJsonLocal(rect)
                + L",\"center_x\":" + std::to_wstring((rect.left + rect.right) / 2)
                + L",\"center_y\":" + std::to_wstring((rect.top + rect.bottom) / 2)
                + L",\"confidence\":0.91}";
            candidate.name = name;
            candidate.role = L"Edit";
            candidate.source = L"uia_address_bar";
            candidate.rect = rect;
            candidate.centerX = (rect.left + rect.right) / 2;
            candidate.centerY = (rect.top + rect.bottom) / 2;
        }
    }
    return bestScore != -1000000;
}

bool LocateAddressBar(TaskRuntimeEvidenceContext& ctx, const std::wstring& title, RuntimeTargetCandidate& candidate) {
    RuntimeCommandResult observed = RunRuntimeCommand(ctx, L"locate_address_bar_observe", {
        L"observe",
        L"--title", title,
        L"--uia", L"true",
        L"--max-elements", L"500"
    });
    if (!observed.ok || !ParseAddressBarCandidate(observed, candidate)) return false;
    ctx.locatorTrace << L"{\"sequence\":" << observed.sequence
                     << L",\"step\":\"locate_address_bar\""
                     << L",\"command\":\"observe\""
                     << L",\"trace_source\":\"derived_from_raw_winagent_command_output\""
                     << L",\"selected_candidate\":" << candidate.candidateJson
                     << L",\"rejected_candidates\":[]}\n";
    return true;
}

bool ClickCandidate(TaskRuntimeEvidenceContext& ctx, const std::wstring& step, const RuntimeTargetCandidate& candidate) {
    int clickX = candidate.centerX;
    int clickY = candidate.centerY;
    int targetHeight = candidate.rect.bottom - candidate.rect.top;
    if (targetHeight > 80) {
        int upperInset = targetHeight / 4;
        if (upperInset < 12) upperInset = 12;
        if (upperInset > 40) upperInset = 40;
        clickY = candidate.rect.top + upperInset;
    }
    std::vector<std::wstring> base = {
        L"--screen-x", std::to_wstring(clickX),
        L"--screen-y", std::to_wstring(clickY),
        L"--permission-mode", L"DEVELOPER_CAPABILITY_DISCOVERY",
        L"--humanmode", L"true",
        L"--target-description", step + L" " + candidate.name,
        L"--coordinate-source", L"locator_derived:" + candidate.source,
        L"--target-rect-left", std::to_wstring(candidate.rect.left),
        L"--target-rect-top", std::to_wstring(candidate.rect.top),
        L"--target-rect-right", std::to_wstring(candidate.rect.right),
        L"--target-rect-bottom", std::to_wstring(candidate.rect.bottom)
    };
    std::vector<std::wstring> moveArgs = {L"desktop-move"};
    moveArgs.insert(moveArgs.end(), base.begin(), base.end());
    RuntimeCommandResult moved = RunRuntimeCommand(ctx, step + L"_move", moveArgs);
    if (!moved.ok) return false;
    std::vector<std::wstring> clickArgs = {L"desktop-click"};
    clickArgs.insert(clickArgs.end(), base.begin(), base.end());
    RuntimeCommandResult clicked = RunRuntimeCommand(ctx, step + L"_click", clickArgs);
    return clicked.ok;
}

bool TypeTextHuman(TaskRuntimeEvidenceContext& ctx, const std::wstring& step, const std::wstring& text, int delayMs = 25) {
    RuntimeCommandResult typed = RunRuntimeCommand(ctx, step, {
        L"desktop-type",
        L"--text", text,
        L"--type-mode", L"demo-human",
        L"--char-delay-ms", std::to_wstring(delayMs),
        L"--permission-mode", L"DEVELOPER_CAPABILITY_DISCOVERY"
    });
    return typed.ok;
}

bool PressHuman(TaskRuntimeEvidenceContext& ctx, const std::wstring& step, const std::wstring& key) {
    RuntimeCommandResult pressed = RunRuntimeCommand(ctx, step, {
        L"desktop-press",
        L"--key", key,
        L"--permission-mode", L"DEVELOPER_CAPABILITY_DISCOVERY"
    });
    return pressed.ok;
}

bool WheelRevealHuman(TaskRuntimeEvidenceContext& ctx, const std::wstring& step, const std::wstring& title) {
    RuntimeCommandResult scrolled = RunRuntimeCommand(ctx, step, {
        L"adaptive-scroll",
        L"--title", title,
        L"--direction", L"down",
        L"--notches", L"3",
        L"--move-mode", L"human",
        L"--verify-content-change", L"true"
    });
    return scrolled.ok;
}

bool HotkeyHuman(TaskRuntimeEvidenceContext& ctx, const std::wstring& step, const std::wstring& keys) {
    RuntimeCommandResult hotkey = RunRuntimeCommand(ctx, step, {
        L"desktop-hotkey",
        L"--keys", keys,
        L"--permission-mode", L"DEVELOPER_CAPABILITY_DISCOVERY"
    });
    return hotkey.ok;
}

bool SaveTaskScreenshot(TaskRuntimeEvidenceContext& ctx, const std::wstring& title, const std::wstring& name) {
    std::wstring out = ctx.screenshotsDir + L"\\" + SafeFilePart(name) + L".bmp";
    RuntimeCommandResult shot = RunRuntimeCommand(ctx, name + L"_screenshot", {
        L"screenshot",
        L"--title", title,
        L"--out", out
    });
    return shot.ok;
}

bool FindBrowserWindow(bool preferMailMock, WindowInfo& out, std::wstring& processName) {
    std::vector<WindowInfo> windows = EnumerateVisibleTopLevelWindows();
    for (const auto& window : windows) {
        std::wstring proc = ProcessNameForPid(window.pid);
        bool browser = ContainsInsensitiveLocal(proc, L"msedge.exe") || ContainsInsensitiveLocal(proc, L"chrome.exe");
        if (!browser || window.title.empty()) continue;
        if (preferMailMock && !ContainsInsensitiveLocal(window.title, L"DesktopVisual Local Mail Mock")) continue;
        out = window;
        processName = proc;
        return true;
    }
    if (preferMailMock) return false;
    for (const auto& window : windows) {
        std::wstring proc = ProcessNameForPid(window.pid);
        bool browser = ContainsInsensitiveLocal(proc, L"msedge.exe") || ContainsInsensitiveLocal(proc, L"chrome.exe");
        if (!browser || window.title.empty()) continue;
        out = window;
        processName = proc;
        return true;
    }
    return false;
}

bool WaitForBrowserWindow(bool preferMailMock, int timeoutMs, WindowInfo& out, std::wstring& processName) {
    ULONGLONG start = GetTickCount64();
    while (ElapsedMs(start) < timeoutMs) {
        if (FindBrowserWindow(preferMailMock, out, processName)) return true;
        Sleep(500);
    }
    return false;
}

bool VerifyObservedFieldValue(TaskRuntimeEvidenceContext& ctx, const std::wstring& title, const std::wstring& field, const std::wstring& value, const std::wstring& step) {
    RuntimeCommandResult observed = RunRuntimeCommand(ctx, step, {
        L"observe",
        L"--title", title,
        L"--uia", L"true",
        L"--max-elements", L"700"
    });
    if (!observed.ok) return false;
    std::wstring needle = L"\"name\":" + JsonString(field) + L",\"value\":" + JsonString(value);
    return observed.output.find(needle) != std::wstring::npos;
}

bool VerifyAfterSend(TaskRuntimeEvidenceContext& ctx, const std::wstring& title) {
    RuntimeCommandResult observed = RunRuntimeCommand(ctx, L"verify_after_send_observe", {
        L"observe",
        L"--title", title,
        L"--uia", L"true",
        L"--max-elements", L"700"
    });
    RuntimeCommandResult text = RunRuntimeCommand(ctx, L"verify_after_send_text", {
        L"read-window-text",
        L"--title", title
    });
    bool status = observed.output.find(L"Mock sent successfully") != std::wstring::npos ||
                  text.output.find(L"Mock sent successfully") != std::wstring::npos;
    bool cleared = observed.output.find(L"\"name\":\"Recipient\",\"value\":\"\"") != std::wstring::npos &&
                   observed.output.find(L"\"name\":\"Subject\",\"value\":\"\"") != std::wstring::npos &&
                   observed.output.find(L"\"name\":\"Body\",\"value\":\"\"") != std::wstring::npos;
    ctx.statusVerified = status;
    ctx.fieldsClearedVerified = cleared;
    return status && cleared;
}

int PreferredPortFromTaskFile(const std::wstring& path, int fallback) {
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) return fallback;
    std::wstring url = JsonGetString(file.content, L"localhost_url");
    std::wstring marker = L"127.0.0.1:";
    size_t pos = url.find(marker);
    if (pos == std::wstring::npos) return fallback;
    pos += marker.size();
    try {
        return std::stoi(url.substr(pos));
    } catch (...) {
        return fallback;
    }
}

bool WriteTaskRuntimeEvidence(
    TaskRuntimeEvidenceContext& ctx,
    bool ok,
    const std::wstring& actualResult,
    const std::wstring& errorCode,
    const std::wstring& message) {
    std::wstring writeError;
    bool wrote = true;
    wrote = WriteTextFileUtf8ish(ctx.eventsPath, ctx.events.str(), writeError) && wrote;
    wrote = WriteTextFileUtf8ish(ctx.rawCommandLogPath, ctx.rawCommands.str(), writeError) && wrote;
    wrote = WriteTextFileUtf8ish(ctx.actionTracePath, ctx.actionTrace.str(), writeError) && wrote;
    wrote = WriteTextFileUtf8ish(ctx.locatorTracePath, ctx.locatorTrace.str(), writeError) && wrote;
    wrote = WriteTextFileUtf8ish(ctx.adaptiveLoopTracePath, ctx.adaptiveLoopTrace.str(), writeError) && wrote;
    wrote = WriteTextFileUtf8ish(ctx.humanResultsPath, ctx.humanResults.str(), writeError) && wrote;

    std::wstringstream result;
    result << L"{\"schema_version\":\"5.10.2.taskruntime\""
           << L",\"runtime_version\":\"5.10.2\""
           << L",\"task_id\":" << JsonString(ctx.session.taskId)
           << L",\"task_type\":" << JsonString(ctx.session.taskType)
           << L",\"ok\":" << (ok ? L"true" : L"false")
           << L",\"current_state\":" << JsonString(ok ? L"completed" : L"failed")
           << L",\"status\":" << JsonString(ok ? L"completed_pending_independent_verifier" : L"failed")
           << L",\"actual_result\":" << JsonString(actualResult)
           << L",\"taskruntime_self_certified_pass\":false"
           << L",\"ready_for_v6_self_claim\":false"
           << L",\"error_code\":" << JsonString(errorCode)
           << L",\"message\":" << JsonString(message)
           << L",\"runtime_flow\":[\"TaskSession\",\"StepContract\",\"TaskRunner\",\"AdaptiveHumanModeLoop\",\"VerificationEngineEquivalent\"]"
           << L",\"localhost\":{\"bind_host\":\"127.0.0.1\",\"bound_all_interfaces\":false,\"port\":" << ctx.serverPort << L"}"
           << L",\"browser\":{\"title\":" << JsonString(ctx.browserTitle)
           << L",\"process\":" << JsonString(ctx.browserProcess) << L"}"
           << L",\"verification\":{\"recipient_text_verified\":" << (ctx.recipientVerified ? L"true" : L"false")
           << L",\"subject_text_verified\":" << (ctx.subjectVerified ? L"true" : L"false")
           << L",\"body_text_verified\":" << (ctx.bodyVerified ? L"true" : L"false")
           << L",\"status_verified\":" << (ctx.statusVerified ? L"true" : L"false")
           << L",\"fields_cleared_verified\":" << (ctx.fieldsClearedVerified ? L"true" : L"false") << L"}"
           << L",\"integrity\":{\"backend_action_count\":" << ctx.backendActionCount
           << L",\"js_dom_action_count\":" << ctx.jsDomActionCount
           << L",\"webdriver_count\":" << ctx.webdriverCount
           << L",\"cdp_count\":" << ctx.cdpCount
           << L",\"uia_invoke_action_count\":" << ctx.uiaInvokeActionCount
           << L",\"uia_value_action_count\":" << ctx.uiaValueActionCount
           << L",\"synthetic_trace\":false"
           << L",\"hardcoded_hwnd\":false"
           << L",\"hardcoded_rect\":false}"
           << L",\"artifacts\":{\"task_events_jsonl\":" << JsonString(ctx.eventsPath)
           << L",\"action_trace_jsonl\":" << JsonString(ctx.actionTracePath)
           << L",\"locator_trace_jsonl\":" << JsonString(ctx.locatorTracePath)
           << L",\"adaptive_loop_trace_jsonl\":" << JsonString(ctx.adaptiveLoopTracePath)
           << L",\"human_action_results_jsonl\":" << JsonString(ctx.humanResultsPath)
           << L",\"raw_command_log_jsonl\":" << JsonString(ctx.rawCommandLogPath)
           << L",\"verification_report_md\":" << JsonString(ctx.verificationReportPath)
           << L",\"screenshots_dir\":" << JsonString(ctx.screenshotsDir)
           << L",\"overlays_dir\":" << JsonString(ctx.overlaysDir)
           << L"}}";
    wrote = WriteTextFileUtf8ish(ctx.resultPath, result.str(), writeError) && wrote;

    std::wstringstream verification;
    verification << L"# TaskRuntime HumanMode Browser Verification\n\n"
                 << L"- Runtime result: `" << actualResult << L"`\n"
                 << L"- TaskRuntime self-certified PASS: `false`\n"
                 << L"- Independent verifier required: `v5_10_2_taskruntime_evidence_verifier.ps1`\n"
                 << L"- Recipient verified: `" << (ctx.recipientVerified ? L"true" : L"false") << L"`\n"
                 << L"- Subject verified: `" << (ctx.subjectVerified ? L"true" : L"false") << L"`\n"
                 << L"- Body verified: `" << (ctx.bodyVerified ? L"true" : L"false") << L"`\n"
                 << L"- Status verified: `" << (ctx.statusVerified ? L"true" : L"false") << L"`\n"
                 << L"- Fields cleared verified: `" << (ctx.fieldsClearedVerified ? L"true" : L"false") << L"`\n"
                 << L"- Localhost bind: `127.0.0.1:" << ctx.serverPort << L"`\n"
                 << L"- Backend action count: `" << ctx.backendActionCount << L"`\n"
                 << L"- JS/DOM/WebDriver/CDP action count: `0`\n";
    wrote = WriteTextFileUtf8ish(ctx.verificationReportPath, verification.str(), writeError) && wrote;

    std::wstringstream report;
    report << L"# v5.10.2 Real TaskRuntime HumanMode Browser Form Report\n\n"
           << L"## Summary\n\n"
           << L"- Task: `" << ctx.session.taskId << L"`\n"
           << L"- Result: `" << actualResult << L"`\n"
           << L"- Final state: `" << (ok ? L"completed" : L"failed") << L"`\n"
           << L"- Completed required steps: " << ctx.completedSteps << L"\n"
           << L"- Failed required steps: " << ctx.failedSteps << L"\n"
           << L"- PASS authority: independent verifier only\n\n"
           << L"## Runtime Flow\n\n"
           << L"`TaskSession -> StepContract -> TaskRunner -> Adaptive HumanMode Loop -> VerificationEngine equivalent`\n\n"
           << L"## Artifacts\n\n"
           << L"- task_result.json: `" << ctx.resultPath << L"`\n"
           << L"- task_events.jsonl: `" << ctx.eventsPath << L"`\n"
           << L"- action_trace.jsonl: `" << ctx.actionTracePath << L"`\n"
           << L"- locator_trace.jsonl: `" << ctx.locatorTracePath << L"`\n"
           << L"- adaptive_loop_trace.jsonl: `" << ctx.adaptiveLoopTracePath << L"`\n"
           << L"- human_action_results.jsonl: `" << ctx.humanResultsPath << L"`\n"
           << L"- raw_command_log.jsonl: `" << ctx.rawCommandLogPath << L"`\n"
           << L"- verification_report.md: `" << ctx.verificationReportPath << L"`\n";
    wrote = WriteTextFileUtf8ish(ctx.reportPath, report.str(), writeError) && wrote;

    std::wstring overlayIndex = ctx.overlaysDir + L"\\target_rects.jsonl";
    wrote = WriteTextFileUtf8ish(overlayIndex, ctx.locatorTrace.str(), writeError) && wrote;
    return wrote;
}

}  // namespace

TaskSessionState ParseTaskSessionState(const std::wstring& value) {
    if (value == L"pending") return TaskSessionState::Pending;
    if (value == L"running") return TaskSessionState::Running;
    if (value == L"waiting") return TaskSessionState::Waiting;
    if (value == L"verifying") return TaskSessionState::Verifying;
    if (value == L"recovering") return TaskSessionState::Recovering;
    if (value == L"confirmed") return TaskSessionState::Confirmed;
    if (value == L"completed") return TaskSessionState::Completed;
    if (value == L"failed") return TaskSessionState::Failed;
    if (value == L"stopped") return TaskSessionState::Stopped;
    if (value == L"blocked") return TaskSessionState::Blocked;
    return TaskSessionState::Unknown;
}

std::wstring TaskSessionStateName(TaskSessionState state) {
    switch (state) {
        case TaskSessionState::Pending: return L"pending";
        case TaskSessionState::Running: return L"running";
        case TaskSessionState::Waiting: return L"waiting";
        case TaskSessionState::Verifying: return L"verifying";
        case TaskSessionState::Recovering: return L"recovering";
        case TaskSessionState::Confirmed: return L"confirmed";
        case TaskSessionState::Completed: return L"completed";
        case TaskSessionState::Failed: return L"failed";
        case TaskSessionState::Stopped: return L"stopped";
        case TaskSessionState::Blocked: return L"blocked";
        default: return L"unknown";
    }
}

std::wstring TaskSessionDataJson(const TaskSession& session) {
    std::wstringstream json;
    json << L"{\"schema_version\":" << JsonString(session.schemaVersion)
         << L",\"runtime_version\":" << JsonString(session.runtimeVersion.empty() ? kTaskSessionRuntimeVersion : session.runtimeVersion)
         << L",\"protocol_version\":" << JsonString(session.protocolVersion.empty() ? kTaskSessionProtocolVersion : session.protocolVersion)
         << L",\"task_id\":" << JsonString(session.taskId)
         << L",\"task_type\":" << JsonString(session.taskType)
         << L",\"profile\":" << JsonString(session.profile)
         << L",\"permission_profile\":" << JsonString(session.permissionProfile)
         << L",\"capability_profile_count\":" << StringArrayJsonCountOnly(session.capabilityProfileCount)
         << L",\"current_state\":" << JsonString(session.currentStateText)
         << L",\"started_at\":" << JsonString(session.startedAt)
         << L",\"updated_at\":" << JsonString(session.updatedAt)
         << L",\"artifacts\":{"
         << L"\"root\":" << JsonString(session.artifacts.root)
         << L",\"events_jsonl\":" << JsonString(session.artifacts.eventsJsonl)
         << L",\"result_json\":" << JsonString(session.artifacts.resultJson)
         << L",\"report_md\":" << JsonString(session.artifacts.reportMd)
         << L"}"
         << L",\"context\":{"
         << L"\"runtime_mode\":" << JsonString(session.context.runtimeMode)
         << L",\"task_goal\":" << JsonString(session.context.taskGoal)
         << L",\"target_title\":" << JsonString(session.context.targetTitle)
         << L",\"target_process\":" << JsonString(session.context.targetProcess)
         << L",\"allow_unrestricted_desktop\":" << (session.context.allowUnrestrictedDesktop ? L"true" : L"false")
         << L"}"
         << L",\"progress\":{"
         << L"\"total_steps\":" << session.progress.totalSteps
         << L",\"completed_steps\":" << session.progress.completedSteps
         << L",\"failed_steps\":" << session.progress.failedSteps
         << L",\"current_step_id\":" << JsonString(session.progress.currentStepId)
         << L"}"
         << L",\"state_count\":" << session.stateCount
         << L",\"task_states\":[\"pending\",\"running\",\"waiting\",\"verifying\",\"recovering\",\"confirmed\",\"completed\",\"failed\",\"stopped\",\"blocked\"]"
         << L",\"transition_schemas\":" << session.transitionSchemaCount
         << L",\"step_contracts\":" << session.stepContractCount
         << L",\"event_count\":" << session.eventCount
         << L",\"task_result\":{"
         << L"\"task_id\":" << JsonString(session.result.taskId)
         << L",\"state\":" << JsonString(session.result.state)
         << L",\"status\":" << JsonString(session.result.status)
         << L",\"ok\":" << (session.result.ok ? L"true" : L"false")
         << L",\"error_code\":" << JsonString(session.result.errorCode)
         << L",\"message\":" << JsonString(session.result.message)
         << L"}"
         << L",\"escalation_provider\":" << JsonString(session.escalationProvider)
         << L"}";
    return json.str();
}

TaskSessionValidationResult ValidateTaskSessionFile(const std::wstring& path) {
    TaskSessionValidationResult out;
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        out.ok = false;
        out.errorCode = file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode;
        out.errorMessage = L"Could not read TaskSession file: " + file.error;
        out.dataJson = L"{\"file\":" + JsonString(path) + L"}";
        return out;
    }

    const std::wstring& json = file.content;
    TaskSession session;
    session.schemaVersion = JsonGetString(json, L"schema_version");
    session.runtimeVersion = JsonGetString(json, L"runtime_version");
    if (session.runtimeVersion.empty()) session.runtimeVersion = kTaskSessionRuntimeVersion;
    session.protocolVersion = JsonGetString(json, L"protocol_version");
    if (session.protocolVersion.empty()) session.protocolVersion = kTaskSessionProtocolVersion;
    session.taskId = JsonGetString(json, L"task_id");
    session.taskType = JsonGetString(json, L"task_type");
    session.profile = JsonGetString(json, L"profile");
    session.permissionProfile = JsonGetString(json, L"permission_profile");
    std::wstring capabilityArray = JsonGetArray(json, L"capability_profile");
    session.capabilityProfileCount = static_cast<int>(JsonStringArrayValues(capabilityArray).size());
    session.currentStateText = JsonGetString(json, L"current_state");
    session.currentState = ParseTaskSessionState(session.currentStateText);
    session.startedAt = JsonGetString(json, L"started_at");
    session.updatedAt = JsonGetString(json, L"updated_at");

    std::wstring artifacts = JsonGetObject(json, L"artifacts");
    session.artifacts.root = JsonGetString(artifacts, L"root");
    session.artifacts.eventsJsonl = JsonGetString(artifacts, L"events_jsonl");
    session.artifacts.resultJson = JsonGetString(artifacts, L"result_json");
    session.artifacts.reportMd = JsonGetString(artifacts, L"report_md");

    std::wstring context = JsonGetObject(json, L"context");
    session.context.runtimeMode = JsonGetString(context, L"runtime_mode");
    session.context.taskGoal = JsonGetString(context, L"task_goal");
    session.context.targetTitle = JsonGetString(context, L"target_title");
    session.context.targetProcess = JsonGetString(context, L"target_process");
    session.context.allowUnrestrictedDesktop = JsonGetBool(context, L"allow_unrestricted_desktop", false);

    std::wstring progress = JsonGetObject(json, L"progress");
    session.progress.totalSteps = JsonGetInt(progress, L"total_steps", 0);
    session.progress.completedSteps = JsonGetInt(progress, L"completed_steps", 0);
    session.progress.failedSteps = JsonGetInt(progress, L"failed_steps", 0);
    session.progress.currentStepId = JsonGetString(progress, L"current_step_id");

    std::vector<std::wstring> states = JsonStringArrayValues(JsonGetArray(json, L"states"));
    session.stateCount = static_cast<int>(states.size());
    session.transitionSchemaCount = CountObjectArrayItems(JsonGetArray(json, L"transitions"));
    session.stepContractCount = CountObjectArrayItems(JsonGetArray(json, L"steps"));
    session.eventCount = CountObjectArrayItems(JsonGetArray(json, L"events"));

    std::wstring resultJson = JsonGetObject(json, L"result");
    session.result.taskId = JsonGetString(resultJson, L"task_id");
    session.result.state = JsonGetString(resultJson, L"state");
    session.result.status = JsonGetString(resultJson, L"status");
    session.result.ok = JsonGetBool(resultJson, L"ok", false);
    session.result.errorCode = JsonGetString(resultJson, L"error_code");
    session.result.message = JsonGetString(resultJson, L"message");

    std::wstring escalation = JsonGetObject(json, L"escalation");
    session.escalationProvider = JsonGetString(escalation, L"provider");
    if (session.escalationProvider.empty()) session.escalationProvider = L"none";

    if (session.schemaVersion != L"5.0.1") return Invalid(session, L"TaskSession schema_version must be 5.0.1.");
    if (!RequireString(session, session.runtimeVersion, L"runtime_version", out)) return out;
    if (!RequireString(session, session.protocolVersion, L"protocol_version", out)) return out;
    if (!RequireString(session, session.taskId, L"task_id", out)) return out;
    if (!RequireString(session, session.taskType, L"task_type", out)) return out;
    if (!RequireString(session, session.profile, L"profile", out)) return out;
    if (!RequireString(session, session.permissionProfile, L"permission_profile", out)) return out;
    if (!RequireString(session, session.currentStateText, L"current_state", out)) return out;
    if (!RequireString(session, session.startedAt, L"started_at", out)) return out;
    if (!RequireString(session, session.updatedAt, L"updated_at", out)) return out;
    if (!RequireString(session, session.artifacts.root, L"artifacts.root", out)) return out;
    if (!RequireString(session, session.artifacts.eventsJsonl, L"artifacts.events_jsonl", out)) return out;
    if (!RequireString(session, session.artifacts.resultJson, L"artifacts.result_json", out)) return out;
    if (!RequireString(session, session.artifacts.reportMd, L"artifacts.report_md", out)) return out;
    if (!RequireString(session, session.context.runtimeMode, L"context.runtime_mode", out)) return out;
    if (!RequireString(session, session.context.taskGoal, L"context.task_goal", out)) return out;

    if (session.permissionProfile != L"DEFAULT" &&
        session.permissionProfile != L"PUBLIC_DEFAULT" &&
        session.permissionProfile != L"DEVELOPER_CAPABILITY_DISCOVERY" &&
        session.permissionProfile != L"DEVELOPER_FULL_RUNTIME" &&
        session.permissionProfile != L"developer_capability_discovery" &&
        session.permissionProfile != L"developer_full_runtime" &&
        session.permissionProfile != L"CI_MOCK" &&
        session.permissionProfile != L"FULL_ACCESS") {
        return Invalid(session, L"permission_profile must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.");
    }
    if (session.context.runtimeMode != L"STANDARD") {
        return Invalid(session, L"context.runtime_mode must be STANDARD in v5.0.1.");
    }
    if (session.context.allowUnrestrictedDesktop) {
        return Invalid(session, L"allow_unrestricted_desktop is denied for v5.0.1 TaskSession schema.");
    }
    if (session.currentState == TaskSessionState::Unknown) {
        return Invalid(session, L"current_state is outside the v5.0.1 TaskState enum: " + session.currentStateText);
    }
    if (ParseTaskSessionState(session.result.state) == TaskSessionState::Unknown) {
        return Invalid(session, L"result.state is outside the v5.0.1 TaskState enum: " + session.result.state);
    }
    if (session.result.taskId != session.taskId) {
        return Invalid(session, L"result.task_id must match task_id.");
    }
    for (const auto& required : RequiredStateNames()) {
        if (!ContainsValue(states, required)) {
            return Invalid(session, L"states must include v5.0.1 TaskState enum value: " + required);
        }
    }

    std::vector<std::wstring> escalationReasons = JsonStringArrayValues(JsonGetArray(escalation, L"allowed_reasons"));
    std::vector<std::wstring> allowed = AllowedEscalationReasons();
    for (const auto& reason : escalationReasons) {
        if (!ContainsValue(allowed, reason)) {
            return Invalid(session, L"Unsupported escalation reason in v5.0.1 TaskSession schema: " + reason);
        }
    }

    out.ok = true;
    out.session = session;
    out.dataJson = TaskSessionDataJson(session);
    return out;
}

TaskTransitionResult ApplyTaskTransition(const TaskSession& session, const TaskTransitionRequest& request) {
    TaskTransitionResult result;
    result.action = request.action;
    result.previousState = TaskSessionStateName(request.fromState);
    result.currentState = result.previousState;
    result.reason = request.reason.empty() ? request.action : request.reason;

    if (request.fromState == TaskSessionState::Unknown) {
        return TransitionInvalid(session, request, L"from_state is outside the v5.0.2 TaskState enum.");
    }
    if (IsTerminalState(request.fromState)) {
        return TransitionInvalid(session, request, L"Cannot transition from a terminal state: " + TaskSessionStateName(request.fromState));
    }

    TaskSessionState target = TaskSessionState::Unknown;
    if (request.action == L"start_task") {
        if (request.fromState != TaskSessionState::Pending) {
            return TransitionInvalid(session, request, L"start_task requires pending state.");
        }
        target = TaskSessionState::Running;
    } else if (request.action == L"enter_state") {
        if (!IsNonTerminalActiveState(request.fromState) || request.toState == TaskSessionState::Pending || IsTerminalState(request.toState) || request.toState == TaskSessionState::Unknown) {
            return TransitionInvalid(session, request, L"enter_state requires a non-terminal active source and target state.");
        }
        target = request.toState;
    } else if (request.action == L"transition_to") {
        if (request.toState == TaskSessionState::Unknown || !IsAllowedGenericTransition(request.fromState, request.toState)) {
            return TransitionInvalid(session, request, L"transition_to target is not allowed from " + TaskSessionStateName(request.fromState) + L".");
        }
        target = request.toState;
    } else if (request.action == L"fail_task") {
        if (request.fromState == TaskSessionState::Pending) {
            return TransitionInvalid(session, request, L"fail_task requires a started task state.");
        }
        target = TaskSessionState::Failed;
    } else if (request.action == L"stop_task") {
        target = TaskSessionState::Stopped;
    } else if (request.action == L"complete_task") {
        if (request.fromState != TaskSessionState::Confirmed && request.fromState != TaskSessionState::Verifying && request.fromState != TaskSessionState::Running) {
            return TransitionInvalid(session, request, L"complete_task requires running, verifying, or confirmed state.");
        }
        target = TaskSessionState::Completed;
    } else if (request.action == L"timeout_task") {
        if (request.timeoutMs <= 0 || request.elapsedMs < request.timeoutMs) {
            return TransitionInvalid(session, request, L"timeout_task requires elapsed_ms greater than or equal to timeout_ms.");
        }
        if (request.fromState == TaskSessionState::Pending) {
            return TransitionInvalid(session, request, L"timeout_task requires a started task state.");
        }
        target = TaskSessionState::Blocked;
        result.timeout = true;
        result.reason = L"timeout";
    } else {
        return TransitionInvalid(session, request, L"Unsupported state machine action: " + request.action);
    }

    result.ok = true;
    result.currentState = TaskSessionStateName(target);
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(session.taskId)
         << L",\"action\":" << JsonString(request.action)
         << L",\"previous_state\":" << JsonString(result.previousState)
         << L",\"current_state\":" << JsonString(result.currentState)
         << L",\"transition\":{\"valid\":true"
         << L",\"from\":" << JsonString(result.previousState)
         << L",\"to\":" << JsonString(result.currentState)
         << L",\"reason\":" << JsonString(result.reason)
         << L"}"
         << L",\"timeout\":{\"detected\":" << (result.timeout ? L"true" : L"false")
         << L",\"timeout_ms\":" << request.timeoutMs
         << L",\"elapsed_ms\":" << request.elapsedMs
         << L"}"
         << L",\"task_result\":{\"task_id\":" << JsonString(session.taskId)
         << L",\"state\":" << JsonString(result.currentState)
         << L",\"status\":" << JsonString(target == TaskSessionState::Completed ? L"completed" : L"in_progress")
         << L",\"ok\":" << (target == TaskSessionState::Completed ? L"true" : L"false")
         << L",\"error_code\":" << JsonString(target == TaskSessionState::Failed ? L"TASK_FAILED" : (target == TaskSessionState::Stopped ? L"TASK_STOPPED" : (target == TaskSessionState::Blocked ? L"TASK_TIMEOUT_BLOCKED" : L"")))
         << L",\"message\":" << JsonString(result.reason)
         << L"}}";
    result.dataJson = data.str();
    return result;
}

TaskSessionRunResult RunMinimalTaskSessionFile(const std::wstring& path) {
    TaskSessionValidationResult loaded = ValidateTaskSessionFile(path);
    if (!loaded.ok) {
        return RunFailure(loaded.errorCode.empty() ? L"TASK_SESSION_SCHEMA_INVALID" : loaded.errorCode, loaded.errorMessage, loaded.dataJson);
    }

    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        return RunFailure(file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode, L"Could not read TaskSession file: " + file.error);
    }
    const std::wstring& json = file.content;
    TaskSession session = loaded.session;
    if (session.taskType != L"local_form_fill_submit_mock") {
        return RunFailure(L"UNSUPPORTED_TASK_TYPE", L"v5.0.3 minimal runner only supports local_form_fill_submit_mock.", TaskSessionDataJson(session));
    }
    if (session.context.allowUnrestrictedDesktop || session.context.runtimeMode != L"STANDARD") {
        return RunFailure(L"SAFETY_POLICY_DENIED", L"v5.0.3 minimal runner requires STANDARD mode and no unrestricted desktop.", TaskSessionDataJson(session));
    }

    std::wstring context = JsonGetObject(json, L"context");
    std::wstring localHtmlPath = JsonGetString(context, L"local_html_path");
    std::wstring formFieldId = JsonGetString(context, L"form_field_id");
    std::wstring formValue = JsonGetString(context, L"form_value");
    std::wstring submitControlId = JsonGetString(context, L"submit_control_id");
    std::wstring successText = JsonGetString(context, L"success_text");
    if (localHtmlPath.empty() || formFieldId.empty() || formValue.empty() || submitControlId.empty() || successText.empty()) {
        return RunFailure(L"INVALID_ARGUMENT", L"local_form_fill_submit_mock requires local_html_path, form_field_id, form_value, submit_control_id, and success_text.", TaskSessionDataJson(session));
    }

    std::wstring htmlPath = ResolveProjectMaybeRelative(localHtmlPath);
    FileReadResult html = ReadTextFile(htmlPath);
    if (!html.ok) {
        return RunFailure(html.errorCode.empty() ? L"FILE_READ_FAILED" : html.errorCode, L"Could not read local mock HTML: " + html.error, L"{\"html_path\":" + JsonString(htmlPath) + L"}");
    }

    if (html.content.find(L"data-dv-fixture=\"local_form_fill_submit_mock\"") == std::wstring::npos ||
        html.content.find(L"id=\"" + formFieldId + L"\"") == std::wstring::npos ||
        html.content.find(L"id=\"" + submitControlId + L"\"") == std::wstring::npos ||
        html.content.find(successText) == std::wstring::npos) {
        return RunFailure(L"EXPECT_FAILED", L"Local mock HTML did not contain required form or success markers.", L"{\"html_path\":" + JsonString(htmlPath) + L"}");
    }

    std::wstring artifactRoot = ResolveProjectMaybeRelative(session.artifacts.root);
    if (!EnsureDirectoryPath(artifactRoot)) {
        return RunFailure(L"FILE_WRITE_FAILED", L"Could not create task artifact directory.", L"{\"artifact_root\":" + JsonString(artifactRoot) + L"}");
    }
    std::wstring eventsPath = ResolveProjectMaybeRelative(session.artifacts.eventsJsonl);
    std::wstring progressPath = ResolveProjectMaybeRelative(session.artifacts.resultJson);
    std::wstring reportPath = ResolveProjectMaybeRelative(session.artifacts.reportMd);
    std::wstring stateDumpPath = artifactRoot + L"\\current_state.json";
    std::wstring failureDumpPath = artifactRoot + L"\\failure_dump.json";

    std::vector<std::wstring> stepIds = {
        L"open_local_page",
        L"wait_form_ready",
        L"fill_one_field",
        L"click_submit_and_verify"
    };
    std::vector<std::wstring> stateForStep = {
        L"running",
        L"waiting",
        L"running",
        L"verifying"
    };
    std::vector<std::wstring> messages = {
        L"Local mock page file read.",
        L"Mock form field is present.",
        L"Mock field value recorded without desktop input.",
        L"Mock submit success text verified."
    };

    std::wstringstream events;
    for (size_t i = 0; i < stepIds.size(); ++i) {
        events << StepEventJson(session.taskId, stepIds[i], static_cast<int>(i), stateForStep[i], messages[i]) << L"\n";
    }
    events << StepEventJson(session.taskId, L"complete_task", 4, L"completed", L"Minimal local mock TaskSession completed.") << L"\n";

    std::wstringstream progress;
    progress << L"{\"schema_version\":\"5.0.3\""
             << L",\"runtime_version\":\"" << kTaskSessionRuntimeVersion << L"\""
             << L",\"protocol_version\":\"" << kTaskSessionProtocolVersion << L"\""
             << L",\"task_id\":" << JsonString(session.taskId)
             << L",\"task_type\":" << JsonString(session.taskType)
             << L",\"ok\":true"
             << L",\"current_state\":\"completed\""
             << L",\"total_steps\":4"
             << L",\"completed_steps\":4"
             << L",\"failed_steps\":0"
             << L",\"current_step_id\":\"complete_task\""
             << L",\"llm_or_vlm_call_count\":0"
             << L",\"artifacts\":{\"events_jsonl\":" << JsonString(eventsPath)
             << L",\"result_json\":" << JsonString(progressPath)
             << L",\"report_md\":" << JsonString(reportPath)
             << L",\"current_state_json\":" << JsonString(stateDumpPath)
             << L",\"failure_dump_json\":" << JsonString(failureDumpPath)
             << L"}}";

    std::wstringstream stateDump;
    stateDump << L"{\"schema_version\":\"5.0.4\""
              << L",\"runtime_version\":\"" << kTaskSessionRuntimeVersion << L"\""
              << L",\"protocol_version\":\"" << kTaskSessionProtocolVersion << L"\""
              << L",\"task_id\":" << JsonString(session.taskId)
              << L",\"task_type\":" << JsonString(session.taskType)
              << L",\"current_state\":\"completed\""
              << L",\"previous_state\":\"verifying\""
              << L",\"completed_steps\":4"
              << L",\"failed_steps\":0"
              << L",\"updated_at\":" << JsonString(NowTimestamp())
              << L",\"step_timeline\":["
              << L"{\"step_id\":\"open_local_page\",\"state\":\"running\",\"ok\":true},"
              << L"{\"step_id\":\"wait_form_ready\",\"state\":\"waiting\",\"ok\":true},"
              << L"{\"step_id\":\"fill_one_field\",\"state\":\"running\",\"ok\":true},"
              << L"{\"step_id\":\"click_submit_and_verify\",\"state\":\"verifying\",\"ok\":true},"
              << L"{\"step_id\":\"complete_task\",\"state\":\"completed\",\"ok\":true}"
              << L"]}";

    std::wstringstream failureDump;
    failureDump << L"{\"schema_version\":\"5.0.4\""
                << L",\"runtime_version\":\"" << kTaskSessionRuntimeVersion << L"\""
                << L",\"protocol_version\":\"" << kTaskSessionProtocolVersion << L"\""
                << L",\"task_id\":" << JsonString(session.taskId)
                << L",\"task_type\":" << JsonString(session.taskType)
                << L",\"has_failure\":false"
                << L",\"failure\":null"
                << L",\"final_state\":\"completed\""
                << L"}";

    std::wstringstream report;
    report << L"# v5.0.3 Minimal TaskSession Report\n\n"
           << L"## Summary\n\n"
           << L"- Task: `" << session.taskId << L"`\n"
           << L"- Type: `" << session.taskType << L"`\n"
           << L"- Result: SUCCESS\n"
           << L"- Final state: `completed`\n"
           << L"- Completed steps: 4 / 4\n"
           << L"- Runtime mode: `STANDARD`\n"
           << L"- LLM/VLM calls: 0\n\n"
           << L"## Step Timeline\n\n";
    for (size_t i = 0; i < stepIds.size(); ++i) {
        report << L"- `" << stepIds[i] << L"`: PASS - " << messages[i] << L"\n";
    }
    report << L"\n## Safety\n\n"
           << L"- Local mock HTML only: `" << htmlPath << L"`\n"
           << L"- No browser launch, network access, focus, click, type, OCR, UIA, or VLM call was performed.\n";

    std::wstring writeError;
    if (!WriteTextFileUtf8ish(eventsPath, events.str(), writeError) ||
        !WriteTextFileUtf8ish(progressPath, progress.str(), writeError) ||
        !WriteTextFileUtf8ish(reportPath, report.str(), writeError) ||
        !WriteTextFileUtf8ish(stateDumpPath, stateDump.str(), writeError) ||
        !WriteTextFileUtf8ish(failureDumpPath, failureDump.str(), writeError)) {
        return RunFailure(L"FILE_WRITE_FAILED", writeError, L"{\"artifact_root\":" + JsonString(artifactRoot) + L"}");
    }

    TaskSessionRunResult result;
    result.ok = true;
    result.progressPath = progressPath;
    result.eventsPath = eventsPath;
    result.reportPath = reportPath;
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(session.taskId)
         << L",\"task_type\":" << JsonString(session.taskType)
         << L",\"ok\":true"
         << L",\"current_state\":\"completed\""
         << L",\"total_steps\":4"
         << L",\"completed_steps\":4"
         << L",\"failed_steps\":0"
         << L",\"llm_or_vlm_call_count\":0"
         << L",\"artifacts\":{\"progress\":" << JsonString(progressPath)
         << L",\"events\":" << JsonString(eventsPath)
         << L",\"report\":" << JsonString(reportPath)
         << L",\"current_state\":" << JsonString(stateDumpPath)
         << L",\"failure_dump\":" << JsonString(failureDumpPath)
         << L"}}";
    result.dataJson = data.str();
    return result;
}

TaskSessionRunResult RunHumanModeBrowserFormTaskSessionFile(const std::wstring& path, const TaskSession& session) {
    TaskRuntimeEvidenceContext ctx;
    ctx.session = session;
    ctx.artifactRoot = ResolveProjectMaybeRelative(session.artifacts.root);
    ctx.eventsPath = ResolveProjectMaybeRelative(session.artifacts.eventsJsonl);
    ctx.resultPath = ResolveProjectMaybeRelative(session.artifacts.resultJson);
    ctx.reportPath = ResolveProjectMaybeRelative(session.artifacts.reportMd);
    ctx.actionTracePath = ctx.artifactRoot + L"\\action_trace.jsonl";
    ctx.locatorTracePath = ctx.artifactRoot + L"\\locator_trace.jsonl";
    ctx.adaptiveLoopTracePath = ctx.artifactRoot + L"\\adaptive_loop_trace.jsonl";
    ctx.humanResultsPath = ctx.artifactRoot + L"\\human_action_results.jsonl";
    ctx.rawCommandLogPath = ctx.artifactRoot + L"\\raw_command_log.jsonl";
    ctx.verificationReportPath = ctx.artifactRoot + L"\\verification_report.md";
    ctx.rawOutputDir = ctx.artifactRoot + L"\\raw_command_outputs";
    ctx.screenshotsDir = ctx.artifactRoot + L"\\screenshots";
    ctx.overlaysDir = ctx.artifactRoot + L"\\overlays";
    EnsureDirectoryPath(ctx.artifactRoot);
    ClearDirectoryContentsUnderArtifacts(ctx.rawOutputDir);
    ClearDirectoryContentsUnderArtifacts(ctx.screenshotsDir);
    ClearDirectoryContentsUnderArtifacts(ctx.overlaysDir);
    EnsureDirectoryPath(ctx.rawOutputDir);
    EnsureDirectoryPath(ctx.screenshotsDir);
    EnsureDirectoryPath(ctx.overlaysDir);

    auto fail = [&](const std::wstring& code, const std::wstring& message) -> TaskSessionRunResult {
        WriteTaskRuntimeEvidence(ctx, false, code, code, message);
        std::wstringstream data;
        data << L"{\"task_id\":" << JsonString(session.taskId)
             << L",\"task_type\":" << JsonString(session.taskType)
             << L",\"ok\":false"
             << L",\"current_state\":\"failed\""
             << L",\"actual_result\":" << JsonString(code)
             << L",\"taskruntime_self_certified_pass\":false"
             << L",\"artifacts\":{\"task_result_json\":" << JsonString(ctx.resultPath)
             << L",\"task_events_jsonl\":" << JsonString(ctx.eventsPath)
             << L",\"task_report_md\":" << JsonString(ctx.reportPath)
             << L"}}";
        return RunFailure(code, message, data.str());
    };

    LocalhostMailMockServer server;
    int preferredPort = PreferredPortFromTaskFile(path, 51210);
    int port = 0;
    std::wstring serverError;
    if (!server.Start(preferredPort, port, serverError)) {
        RecordTaskRuntimeEvent(ctx, L"start_localhost_http_server", false, serverError);
        return fail(L"FAIL_TASKRUNTIME_LOCALHOST_SERVER", serverError);
    }
    ctx.serverPort = port;
    ctx.localhostBoundLocalOnly = true;
    RecordTaskRuntimeEvent(ctx, L"start_localhost_http_server", true, L"Started localhost HTTP server bound to 127.0.0.1 only.");

    std::wstring url = L"http://127.0.0.1:" + std::to_wstring(port) + L"/mail_mock.html";
    WindowInfo browser;
    std::wstring browserProcess;
    if (!WaitForBrowserWindow(false, 2000, browser, browserProcess)) {
        HotkeyHuman(ctx, L"open_browser_run_dialog_hotkey", L"WIN+R");
        Sleep(500);
        TypeTextHuman(ctx, L"open_browser_run_dialog_type_msedge", L"msedge.exe", 25);
        PressHuman(ctx, L"open_browser_run_dialog_enter", L"ENTER");
        if (!WaitForBrowserWindow(false, 12000, browser, browserProcess)) {
            HotkeyHuman(ctx, L"open_browser_run_dialog_hotkey_chrome", L"WIN+R");
            Sleep(500);
            TypeTextHuman(ctx, L"open_browser_run_dialog_type_chrome", L"chrome.exe", 25);
            PressHuman(ctx, L"open_browser_run_dialog_enter_chrome", L"ENTER");
            if (!WaitForBrowserWindow(false, 12000, browser, browserProcess)) {
                server.Stop();
                RecordTaskRuntimeEvent(ctx, L"open_browser_humanmode_address_bar_navigation", false, L"Could not open Chrome or Edge through real UI.");
                return fail(L"FAIL_TASKRUNTIME_BROWSER_OPEN", L"Could not open Chrome or Edge through real UI.");
            }
        }
    }
    ctx.browserTitle = browser.title;
    ctx.browserProcess = browserProcess;

    RuntimeTargetCandidate addressBar;
    if (!LocateAddressBar(ctx, browser.title, addressBar)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"open_browser_humanmode_address_bar_navigation", false, L"Address bar could not be located from current UIA observe output.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Address bar could not be located from current UIA observe output.");
    }
    if (!ClickCandidate(ctx, L"click_address_bar", addressBar) ||
        !HotkeyHuman(ctx, L"select_address_bar_text", L"CTRL+A") ||
        !TypeTextHuman(ctx, L"type_localhost_url", url, 50) ||
        !PressHuman(ctx, L"press_enter_open_localhost_url", L"ENTER")) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"open_browser_humanmode_address_bar_navigation", false, L"HumanMode address bar URL entry failed.");
        return fail(L"FAIL_TASKRUNTIME_BROWSER_NAVIGATION", L"HumanMode address bar URL entry failed.");
    }
    Sleep(3500);

    WindowInfo loadedBrowser;
    std::wstring loadedProcess;
    if (!WaitForBrowserWindow(true, 8000, loadedBrowser, loadedProcess)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"open_browser_humanmode_address_bar_navigation", false, L"Localhost mail mock page was not observed in a browser title.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Localhost mail mock page was not observed in a browser title.");
    }
    ctx.browserTitle = loadedBrowser.title;
    ctx.browserProcess = loadedProcess;
    RecordTaskRuntimeEvent(ctx, L"open_browser_humanmode_address_bar_navigation", true, L"Opened localhost page through HumanMode address bar navigation.");
    SaveTaskScreenshot(ctx, ctx.browserTitle, L"before_fill");

    RuntimeTargetCandidate recipient;
    if (!LocateAdaptiveTarget(ctx, ctx.browserTitle, ctx.browserProcess, L"Recipient", L"Edit", L"browser_field", L"locate_recipient", recipient)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"locate_recipient", false, L"Recipient field locator failed.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Recipient field locator failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"locate_recipient", true, L"Located Recipient field from adaptive UIA locator.");
    if (!ClickCandidate(ctx, L"click_recipient", recipient)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"click_recipient", false, L"Recipient click failed.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Recipient click failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"click_recipient", true, L"Clicked Recipient with HumanMode mouse action.");
    if (!TypeTextHuman(ctx, L"type_recipient", L"xiaoming")) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"type_recipient", false, L"Recipient typing failed.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Recipient typing failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"type_recipient", true, L"Typed Recipient text through HumanMode keyboard.");
    ctx.recipientVerified = VerifyObservedFieldValue(ctx, ctx.browserTitle, L"Recipient", L"xiaoming", L"verify_recipient_text");
    if (!ctx.recipientVerified) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"verify_recipient_text", false, L"Recipient value was not verified through read-only UIA observe evidence.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Recipient value was not verified through read-only UIA observe evidence.");
    }
    RecordTaskRuntimeEvent(ctx, L"verify_recipient_text", true, L"Verified Recipient text through read-only UIA value evidence.");

    RuntimeTargetCandidate subject;
    if (!LocateAdaptiveTarget(ctx, ctx.browserTitle, ctx.browserProcess, L"Subject", L"Edit", L"browser_field", L"locate_subject", subject)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"locate_subject", false, L"Subject field locator failed.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Subject field locator failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"locate_subject", true, L"Located Subject field from adaptive UIA locator.");
    if (!ClickCandidate(ctx, L"click_subject", subject)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"click_subject", false, L"Subject click failed.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Subject click failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"click_subject", true, L"Clicked Subject with HumanMode mouse action.");
    if (!TypeTextHuman(ctx, L"type_subject", L"desktopvisual test")) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"type_subject", false, L"Subject typing failed.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Subject typing failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"type_subject", true, L"Typed Subject text through HumanMode keyboard.");
    ctx.subjectVerified = VerifyObservedFieldValue(ctx, ctx.browserTitle, L"Subject", L"desktopvisual test", L"verify_subject_text");
    if (!ctx.subjectVerified) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"verify_subject_text", false, L"Subject value was not verified through read-only UIA observe evidence.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Subject value was not verified through read-only UIA observe evidence.");
    }
    RecordTaskRuntimeEvent(ctx, L"verify_subject_text", true, L"Verified Subject text through read-only UIA value evidence.");

    RuntimeTargetCandidate body;
    if (!LocateAdaptiveTarget(ctx, ctx.browserTitle, ctx.browserProcess, L"Body", L"Edit", L"browser_field", L"locate_body", body)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"locate_body", false, L"Body field locator failed.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Body field locator failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"locate_body", true, L"Located Body field from adaptive UIA locator.");
    if (!ClickCandidate(ctx, L"click_body", body)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"click_body", false, L"Body click failed.");
        return fail(L"FAIL_TASKRUNTIME_FIELD_LOCATOR", L"Body click failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"click_body", true, L"Clicked Body with HumanMode mouse action.");
    if (!TypeTextHuman(ctx, L"type_body", L"this is a testing message")) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"type_body", false, L"Body typing failed.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Body typing failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"type_body", true, L"Typed Body text through HumanMode keyboard.");
    ctx.bodyVerified = VerifyObservedFieldValue(ctx, ctx.browserTitle, L"Body", L"this is a testing message", L"verify_body_text");
    if (!ctx.bodyVerified) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"verify_body_text", false, L"Body value was not verified through read-only UIA observe evidence.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Body value was not verified through read-only UIA observe evidence.");
    }
    RecordTaskRuntimeEvent(ctx, L"verify_body_text", true, L"Verified Body text through read-only UIA value evidence.");
    SaveTaskScreenshot(ctx, ctx.browserTitle, L"after_fill");

    RuntimeTargetCandidate send;
    if (!LocateAdaptiveTarget(ctx, ctx.browserTitle, ctx.browserProcess, L"Send", L"Button", L"browser_button", L"locate_send", send)) {
        if (!PressHuman(ctx, L"reveal_send_with_tab", L"TAB")) {
            server.Stop();
            RecordTaskRuntimeEvent(ctx, L"locate_send", false, L"Send button locator failed and HumanMode TAB reveal failed.");
            return fail(L"FAIL_TASKRUNTIME_SEND_BUTTON", L"Send button locator failed and HumanMode TAB reveal failed.");
        }
        Sleep(700);
        SaveTaskScreenshot(ctx, ctx.browserTitle, L"after_reveal_send_tab");
        if (!LocateAdaptiveTarget(ctx, ctx.browserTitle, ctx.browserProcess, L"Send", L"Button", L"browser_button", L"locate_send", send)) {
            if (!WheelRevealHuman(ctx, L"reveal_send_with_wheel", ctx.browserTitle)) {
                server.Stop();
                RecordTaskRuntimeEvent(ctx, L"locate_send", false, L"Send button locator failed and real mouse wheel reveal failed.");
                return fail(L"FAIL_TASKRUNTIME_SEND_BUTTON", L"Send button locator failed and real mouse wheel reveal failed.");
            }
            Sleep(700);
            SaveTaskScreenshot(ctx, ctx.browserTitle, L"after_reveal_send_wheel");
            if (!LocateAdaptiveTarget(ctx, ctx.browserTitle, ctx.browserProcess, L"Send", L"Button", L"browser_button", L"locate_send", send)) {
                server.Stop();
                RecordTaskRuntimeEvent(ctx, L"locate_send", false, L"Send button locator failed after real HumanMode reveal actions.");
                return fail(L"FAIL_TASKRUNTIME_SEND_BUTTON", L"Send button locator failed after real HumanMode reveal actions.");
            }
        }
    }
    RecordTaskRuntimeEvent(ctx, L"locate_send", true, L"Located Send button from adaptive UIA locator.");
    if (!ClickCandidate(ctx, L"click_send", send)) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"click_send", false, L"Send click failed.");
        return fail(L"FAIL_TASKRUNTIME_SEND_BUTTON", L"Send click failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"click_send", true, L"Clicked Send with HumanMode mouse action.");
    Sleep(1000);
    SaveTaskScreenshot(ctx, ctx.browserTitle, L"after_send");
    bool verifiedAfterSend = VerifyAfterSend(ctx, ctx.browserTitle);
    if (!verifiedAfterSend) {
        server.Stop();
        RecordTaskRuntimeEvent(ctx, L"verify_mock_sent_successfully", ctx.statusVerified, L"Status verification failed.");
        RecordTaskRuntimeEvent(ctx, L"verify_fields_cleared", ctx.fieldsClearedVerified, L"Field-clear verification failed.");
        return fail(L"FAIL_TASKRUNTIME_VERIFICATION", L"Status or field-clear verification failed.");
    }
    RecordTaskRuntimeEvent(ctx, L"verify_mock_sent_successfully", true, L"Verified Mock sent successfully.");
    RecordTaskRuntimeEvent(ctx, L"verify_fields_cleared", true, L"Verified Recipient, Subject, and Body fields cleared.");

    server.Stop();
    RecordTaskRuntimeEvent(ctx, L"stop_localhost_http_server", true, L"Stopped localhost HTTP server.");

    const std::wstring actualResult = L"REAL_UI_EXECUTION_COMPLETED_PENDING_INDEPENDENT_VERIFIER";
    if (!WriteTaskRuntimeEvidence(ctx, true, actualResult, L"", L"TaskRuntime executed real HumanMode browser form flow; PASS requires independent verifier.")) {
        return RunFailure(L"FILE_WRITE_FAILED", L"Could not write TaskRuntime evidence artifacts.");
    }

    TaskSessionRunResult result;
    result.ok = true;
    result.progressPath = ctx.resultPath;
    result.eventsPath = ctx.eventsPath;
    result.reportPath = ctx.reportPath;
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(session.taskId)
         << L",\"task_type\":" << JsonString(session.taskType)
         << L",\"ok\":true"
         << L",\"current_state\":\"completed\""
         << L",\"actual_result\":" << JsonString(actualResult)
         << L",\"taskruntime_self_certified_pass\":false"
         << L",\"machine_readable_status\":" << ReadableStatusJson(L"completed", true, true, false, L"")
         << L",\"artifacts\":{\"task_result_json\":" << JsonString(ctx.resultPath)
         << L",\"task_events_jsonl\":" << JsonString(ctx.eventsPath)
         << L",\"task_report_md\":" << JsonString(ctx.reportPath)
         << L",\"action_trace_jsonl\":" << JsonString(ctx.actionTracePath)
         << L",\"locator_trace_jsonl\":" << JsonString(ctx.locatorTracePath)
         << L",\"adaptive_loop_trace_jsonl\":" << JsonString(ctx.adaptiveLoopTracePath)
         << L",\"human_action_results_jsonl\":" << JsonString(ctx.humanResultsPath)
         << L",\"raw_command_log_jsonl\":" << JsonString(ctx.rawCommandLogPath)
         << L"}}";
    result.dataJson = data.str();
    return result;
}

TaskSessionRunResult RunStableTaskSessionFile(const std::wstring& path) {
    TaskSessionValidationResult loaded = ValidateTaskSessionFile(path);
    if (!loaded.ok) {
        return RunFailure(loaded.errorCode.empty() ? L"TASK_SESSION_SCHEMA_INVALID" : loaded.errorCode, loaded.errorMessage, loaded.dataJson);
    }

    TaskSessionRunResult run = loaded.session.taskType == L"localhost_form_fill_submit_humanmode"
        ? RunHumanModeBrowserFormTaskSessionFile(path, loaded.session)
        : RunMinimalTaskSessionFile(path);
    if (!run.ok) {
        return run;
    }

    TaskSession session = loaded.session;
    std::wstring artifactRoot = ResolveProjectMaybeRelative(session.artifacts.root);
    std::wstring eventsPath = ResolveProjectMaybeRelative(session.artifacts.eventsJsonl);
    std::wstring resultPath = ResolveProjectMaybeRelative(session.artifacts.resultJson);
    std::wstring reportPath = ResolveProjectMaybeRelative(session.artifacts.reportMd);
    std::wstring stateDumpPath = artifactRoot + L"\\current_state.json";
    std::wstring failureDumpPath = artifactRoot + L"\\failure_dump.json";
    std::wstring evidenceIndexPath = artifactRoot + L"\\evidence_index.md";
    std::wstring cancelAuditPath = artifactRoot + L"\\cancel_audit.json";
    std::wstring registryPath = StableTaskRegistryPath(session.taskId);

    EnsureDirectoryPath(artifactRoot);
    EnsureDirectoryPath(StableTaskRegistryDir());

    std::wstringstream evidence;
    evidence << L"# v5.7 Task Evidence Index\n\n"
             << L"- Task ID: `" << session.taskId << L"`\n"
             << L"- Status: `completed`\n"
             << L"- task_result.json: `" << resultPath << L"`\n"
             << L"- task_events.jsonl: `" << eventsPath << L"`\n"
             << L"- task_report.md: `" << reportPath << L"`\n"
             << L"- current_state.json: `" << stateDumpPath << L"`\n"
             << L"- failure_dump.json: `" << failureDumpPath << L"`\n";

    std::wstring record = TaskRecordJson(
        session,
        L"completed",
        true,
        true,
        false,
        L"",
        L"TaskSession completed through stable v5.7 task API.",
        eventsPath,
        resultPath,
        reportPath,
        stateDumpPath,
        failureDumpPath,
        evidenceIndexPath);

    std::wstring writeError;
    if (!WriteTextFileUtf8ish(evidenceIndexPath, evidence.str(), writeError) ||
        !WriteTextFileUtf8ish(registryPath, record, writeError)) {
        return RunFailure(L"FILE_WRITE_FAILED", writeError, run.dataJson);
    }

    run.progressPath = resultPath;
    run.eventsPath = eventsPath;
    run.reportPath = reportPath;
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(session.taskId)
         << L",\"task_type\":" << JsonString(session.taskType)
         << L",\"ok\":true"
         << L",\"current_state\":\"completed\""
         << L",\"machine_readable_status\":" << ReadableStatusJson(L"completed", true, true, false, L"")
         << L",\"artifacts\":{\"task_result_json\":" << JsonString(resultPath)
         << L",\"task_events_jsonl\":" << JsonString(eventsPath)
         << L",\"task_report_md\":" << JsonString(reportPath)
         << L",\"current_state_json\":" << JsonString(stateDumpPath)
         << L",\"failure_dump_json\":" << JsonString(failureDumpPath)
         << L",\"evidence_index_md\":" << JsonString(evidenceIndexPath)
         << L",\"status_record_json\":" << JsonString(registryPath)
         << L"}}";
    run.dataJson = data.str();
    return run;
}

TaskSessionRunResult RunCompiledStepContractTaskSessionFile(
    const std::wstring& stepContractPath,
    const std::wstring& executionMode,
    const std::wstring& outputPath,
    const std::wstring& evidenceDir) {
    CompiledPlanExecutionOptions options;
    options.executionMode = executionMode.empty() ? L"dry_run" : executionMode;
    if (options.executionMode == L"execute-local-safe") {
        options.executionMode = L"execute_local_safe";
    }
    options.resultJson = outputPath;
    options.evidenceDir = evidenceDir;
    options.sessionReuseEnabled = true;
    options.allowRecovery = true;

    CompiledPlanExecutionResult executed = ExecuteStepContractFile(stepContractPath, options);
    TaskSessionRunResult result;
    result.ok = executed.ok;
    result.errorCode = executed.errorCode;
    result.errorMessage = executed.errorMessage;
    result.dataJson = executed.executionResultJson;
    result.progressPath = outputPath;
    result.eventsPath = evidenceDir.empty() ? L"" : evidenceDir + L"\\step_results.jsonl";
    result.reportPath = evidenceDir.empty() ? L"" : evidenceDir + L"\\execution_report.md";
    return result;
}

TaskSessionControlResult GetStableTaskSessionStatus(const std::wstring& taskId, const std::wstring& file) {
    std::wstring record;
    TaskSessionControlResult loaded = LoadStableTaskRecord(taskId, file, record);
    if (!loaded.ok) return loaded;
    return ControlSuccess(record);
}

TaskSessionControlResult ReadStableTaskSessionEvents(const std::wstring& taskId, const std::wstring& file) {
    std::wstring record;
    TaskSessionControlResult loaded = LoadStableTaskRecord(taskId, file, record);
    if (!loaded.ok) return loaded;
    std::wstring artifacts = JsonGetObject(record, L"artifacts");
    std::wstring eventsPath = JsonGetString(artifacts, L"events_jsonl");
    if (eventsPath.empty()) return ControlFailure(L"TASK_EVENTS_NOT_FOUND", L"Task record does not contain events_jsonl.", record);
    FileReadResult events = ReadTextFile(eventsPath);
    if (!events.ok) {
        return ControlFailure(events.errorCode.empty() ? L"FILE_READ_FAILED" : events.errorCode, L"Could not read task events: " + events.error, record);
    }
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(JsonGetString(record, L"task_id"))
         << L",\"events_path\":" << JsonString(eventsPath)
         << L",\"event_count\":" << CountJsonlEvents(events.content)
         << L",\"content\":" << JsonString(events.content)
         << L"}";
    return ControlSuccess(data.str(), {eventsPath});
}

TaskSessionControlResult ReadStableTaskSessionReport(const std::wstring& taskId, const std::wstring& file) {
    std::wstring record;
    TaskSessionControlResult loaded = LoadStableTaskRecord(taskId, file, record);
    if (!loaded.ok) return loaded;
    std::wstring artifacts = JsonGetObject(record, L"artifacts");
    std::wstring reportPath = JsonGetString(artifacts, L"task_report_md");
    if (reportPath.empty()) return ControlFailure(L"TASK_REPORT_NOT_FOUND", L"Task record does not contain task_report_md.", record);
    FileReadResult report = ReadTextFile(reportPath);
    if (!report.ok) {
        return ControlFailure(report.errorCode.empty() ? L"FILE_READ_FAILED" : report.errorCode, L"Could not read task report: " + report.error, record);
    }
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(JsonGetString(record, L"task_id"))
         << L",\"report_path\":" << JsonString(reportPath)
         << L",\"content_length\":" << report.content.size()
         << L",\"content\":" << JsonString(report.content)
         << L"}";
    return ControlSuccess(data.str(), {reportPath}, reportPath);
}

TaskSessionControlResult ConfirmStableTaskSessionAction(const std::wstring& taskId, const std::wstring& file, const std::wstring& response) {
    std::wstring record;
    TaskSessionControlResult loaded = LoadStableTaskRecord(taskId, file, record);
    if (!loaded.ok) return loaded;
    std::wstring artifacts = JsonGetObject(record, L"artifacts");
    std::wstring reportPath = JsonGetString(artifacts, L"task_report_md");
    std::wstring confirmationPath;
    std::wstring evidencePath = JsonGetString(artifacts, L"evidence_index_md");
    if (!evidencePath.empty()) {
        size_t slash = evidencePath.find_last_of(L"\\/");
        confirmationPath = (slash == std::wstring::npos ? L"" : evidencePath.substr(0, slash + 1)) + L"confirmation.json";
    } else {
        confirmationPath = ArtifactsPath(L"task_runtime_v5_7\\confirmation_" + SafeTaskIdFileName(JsonGetString(record, L"task_id")) + L".json");
    }
    std::wstring normalizedResponse = response.empty() ? L"confirm" : response;
    std::wstringstream confirmation;
    confirmation << L"{\"schema_version\":\"5.7.1\""
                 << L",\"task_id\":" << JsonString(JsonGetString(record, L"task_id"))
                 << L",\"response\":" << JsonString(normalizedResponse)
                 << L",\"confirmed_at\":" << JsonString(NowTimestamp())
                 << L",\"safety_override\":false"
                 << L"}";
    std::wstring writeError;
    if (!WriteTextFileUtf8ish(confirmationPath, confirmation.str(), writeError)) {
        return ControlFailure(L"FILE_WRITE_FAILED", writeError, record);
    }
    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(JsonGetString(record, L"task_id"))
         << L",\"response\":" << JsonString(normalizedResponse)
         << L",\"confirmation_path\":" << JsonString(confirmationPath)
         << L",\"safety_override\":false"
         << L"}";
    return ControlSuccess(data.str(), {confirmationPath}, reportPath);
}

TaskSessionControlResult CancelStableTaskSession(const std::wstring& taskId, const std::wstring& file, const std::wstring& reason) {
    std::wstring record;
    TaskSession session;
    TaskSessionControlResult loaded = LoadStableTaskRecord(taskId, file, record, &session);
    if (!loaded.ok && file.empty()) return loaded;

    if (loaded.ok) {
        std::wstring state = JsonGetString(record, L"current_state");
        bool terminal = state == L"completed" || state == L"failed" || state == L"stopped" || state == L"blocked";
        if (terminal) {
            std::wstringstream data;
            data << L"{\"task_id\":" << JsonString(JsonGetString(record, L"task_id"))
                 << L",\"cancelled\":false"
                 << L",\"current_state\":" << JsonString(state)
                 << L",\"reason\":" << JsonString(reason)
                 << L",\"message\":\"Task is already terminal; cancel is a stable no-op.\""
                 << L"}";
            return ControlSuccess(data.str());
        }
    } else {
        TaskSessionValidationResult validated = ValidateTaskSessionFile(file);
        if (!validated.ok) {
            return ControlFailure(validated.errorCode.empty() ? L"TASK_SESSION_SCHEMA_INVALID" : validated.errorCode, validated.errorMessage, validated.dataJson);
        }
        session = validated.session;
    }

    if (session.taskId.empty()) {
        session.taskId = JsonGetString(record, L"task_id");
        session.taskType = JsonGetString(record, L"task_type");
    }

    std::wstring artifactRoot = session.artifacts.root.empty()
        ? ArtifactsPath(L"task_runtime_v5_7\\cancelled\\" + SafeTaskIdFileName(session.taskId))
        : ResolveProjectMaybeRelative(session.artifacts.root);
    std::wstring eventsPath = session.artifacts.eventsJsonl.empty() ? artifactRoot + L"\\task_events.jsonl" : ResolveProjectMaybeRelative(session.artifacts.eventsJsonl);
    std::wstring resultPath = session.artifacts.resultJson.empty() ? artifactRoot + L"\\task_result.json" : ResolveProjectMaybeRelative(session.artifacts.resultJson);
    std::wstring reportPath = session.artifacts.reportMd.empty() ? artifactRoot + L"\\task_report.md" : ResolveProjectMaybeRelative(session.artifacts.reportMd);
    std::wstring stateDumpPath = artifactRoot + L"\\current_state.json";
    std::wstring failureDumpPath = artifactRoot + L"\\failure_dump.json";
    std::wstring evidenceIndexPath = artifactRoot + L"\\evidence_index.md";
    std::wstring cancelAuditPath = artifactRoot + L"\\cancel_audit.json";
    std::wstring registryPath = StableTaskRegistryPath(session.taskId);
    EnsureDirectoryPath(artifactRoot);
    EnsureDirectoryPath(StableTaskRegistryDir());

    std::wstring cancelReason = reason.empty() ? L"user cancel" : reason;
    std::wstring stopCode = StopCodeForCancelReason(cancelReason);
    std::wstring stopStatus = StatusForStopCode(stopCode);
    std::wstring events = StepEventJson(session.taskId, L"cancel_task", 0, L"stopped", cancelReason) + L"\n";
    std::wstring resultJson = L"{\"schema_version\":\"5.7.3\",\"task_id\":" + JsonString(session.taskId)
        + L",\"ok\":false,\"current_state\":\"stopped\",\"status\":" + JsonString(stopStatus) + L",\"error_code\":" + JsonString(stopCode) + L",\"message\":"
        + JsonString(cancelReason) + L"}";
    std::wstring stateJson = L"{\"schema_version\":\"5.7.3\",\"task_id\":" + JsonString(session.taskId)
        + L",\"current_state\":\"stopped\",\"updated_at\":" + JsonString(NowTimestamp()) + L"}";
    std::wstring failureJson = L"{\"schema_version\":\"5.7.3\",\"task_id\":" + JsonString(session.taskId)
        + L",\"has_failure\":true,\"failure\":{\"error_code\":" + JsonString(stopCode) + L",\"message\":" + JsonString(cancelReason)
        + L"},\"final_state\":\"stopped\"}";
    std::wstring cancelAuditJson = L"{\"schema_version\":\"5.7.6\",\"task_id\":" + JsonString(session.taskId)
        + L",\"action\":\"task_cancel\""
        + L",\"current_state\":\"stopped\""
        + L",\"error_code\":" + JsonString(stopCode)
        + L",\"reason\":" + JsonString(cancelReason)
        + L",\"safety_override\":false"
        + L",\"written_at\":" + JsonString(NowTimestamp())
        + L"}";
    std::wstring report = L"# v5.7 Cancelled Task Report\n\n- Task: `" + session.taskId
        + L"`\n- Result: STOPPED\n- Error: `" + stopCode + L"`\n- Reason: " + cancelReason + L"\n";
    std::wstring evidence = L"# v5.7 Task Evidence Index\n\n- Task ID: `" + session.taskId
        + L"`\n- Status: `stopped`\n- task_result.json: `" + resultPath
        + L"`\n- task_events.jsonl: `" + eventsPath
        + L"`\n- task_report.md: `" + reportPath
        + L"`\n- cancel_audit.json: `" + cancelAuditPath + L"`\n";
    std::wstring stoppedRecord = TaskRecordJson(
        session, L"stopped", false, true, false, stopCode, cancelReason,
        eventsPath, resultPath, reportPath, stateDumpPath, failureDumpPath, evidenceIndexPath);

    std::wstring writeError;
    if (!WriteTextFileUtf8ish(eventsPath, events, writeError) ||
        !WriteTextFileUtf8ish(resultPath, resultJson, writeError) ||
        !WriteTextFileUtf8ish(stateDumpPath, stateJson, writeError) ||
        !WriteTextFileUtf8ish(failureDumpPath, failureJson, writeError) ||
        !WriteTextFileUtf8ish(cancelAuditPath, cancelAuditJson, writeError) ||
        !WriteTextFileUtf8ish(reportPath, report, writeError) ||
        !WriteTextFileUtf8ish(evidenceIndexPath, evidence, writeError) ||
        !WriteTextFileUtf8ish(registryPath, stoppedRecord, writeError)) {
        return ControlFailure(L"FILE_WRITE_FAILED", writeError, stoppedRecord);
    }

    std::wstringstream data;
    data << L"{\"task_id\":" << JsonString(session.taskId)
         << L",\"cancelled\":true"
         << L",\"current_state\":\"stopped\""
         << L",\"error_code\":" << JsonString(stopCode)
         << L",\"status\":" << JsonString(stopStatus)
         << L",\"reason\":" << JsonString(cancelReason)
         << L",\"artifacts\":{\"task_result_json\":" << JsonString(resultPath)
         << L",\"task_events_jsonl\":" << JsonString(eventsPath)
         << L",\"task_report_md\":" << JsonString(reportPath)
         << L",\"failure_dump_json\":" << JsonString(failureDumpPath)
         << L",\"cancel_audit_json\":" << JsonString(cancelAuditPath)
         << L",\"evidence_index_md\":" << JsonString(evidenceIndexPath)
         << L"}}";
    return ControlSuccess(data.str(), {resultPath, eventsPath, reportPath, failureDumpPath, cancelAuditPath, evidenceIndexPath}, reportPath);
}
