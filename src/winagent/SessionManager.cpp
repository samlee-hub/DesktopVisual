#include "SessionManager.h"

#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Trace.h"
#include "WindowFinder.h"
#include "WindowSession.h"

#include <windows.h>

#include <cstdio>
#include <sstream>

namespace {

bool ReadTextFileUtf8(const std::wstring& path, std::wstring& text, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"r, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open session file.";
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
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write session file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

WindowInfo WindowInfoFromHwndValue(unsigned long long hwndValue) {
    HWND hwnd = reinterpret_cast<HWND>(hwndValue);
    WindowInfo info;
    info.hwnd = hwnd;
    if (!hwnd || !IsWindow(hwnd)) {
        return info;
    }
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

bool IsProcessAlive(DWORD pid) {
    if (pid == 0) return false;
    HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, pid);
    if (!process) return false;
    DWORD wait = WaitForSingleObject(process, 0);
    CloseHandle(process);
    return wait == WAIT_TIMEOUT;
}

std::wstring SessionsDataJson(const std::vector<RuntimeSession>& sessions) {
    return L"{\"sessions\":" + RuntimeSessionListJson(sessions) + L",\"session_count\":" + std::to_wstring(sessions.size()) + L"}";
}

}  // namespace

SessionManager::SessionManager(long long sessionTimeoutMs)
    : sessionTimeoutMs_(sessionTimeoutMs > 0 ? sessionTimeoutMs : 30 * 60 * 1000) {
}

std::wstring SessionManager::SessionDirectory() const {
    return ArtifactsPath(L"runtime_sessions");
}

std::wstring SessionManager::SessionPath(const std::wstring& sessionId) const {
    return SessionDirectory() + L"\\" + sessionId + L".json";
}

bool SessionManager::ReadSessionFile(const std::wstring& path, RuntimeSession& session, std::wstring& error) const {
    std::wstring text;
    if (!ReadTextFileUtf8(path, text, error)) {
        return false;
    }
    if (!RuntimeSessionDeserialize(text, session)) {
        error = L"Session file could not be parsed.";
        return false;
    }
    return true;
}

bool SessionManager::WriteSessionFile(const RuntimeSession& session, std::wstring& error) const {
    EnsureDirectoryPath(SessionDirectory());
    return WriteTextFileUtf8(SessionPath(session.sessionId), RuntimeSessionSerialize(session), error);
}

SessionManagerResult SessionManager::CreateSession(
    const std::wstring& title,
    const std::wstring& process,
    unsigned long long hwndValue) {
    SessionManagerResult result;
    RuntimeSession session;
    session.sessionId = RuntimeSessionGenerateId();
    session.sessionCreatedAt = NowTimestamp();
    session.sessionLastActiveAt = session.sessionCreatedAt;
    session.sessionCreatedAtEpochMs = RuntimeSessionNowEpochMs();
    session.sessionLastActiveAtEpochMs = session.sessionCreatedAtEpochMs;
    session.sessionAlive = true;
    session.sessionClosed = false;
    session.requestedTitle = title;
    session.requestedProcess = process;
    session.latencySummary.sessionReuseEnabled = true;

    WindowInfo bound;
    if (hwndValue != 0) {
        bound = WindowInfoFromHwndValue(hwndValue);
        if (!bound.hwnd || !IsWindow(bound.hwnd)) {
            result.errorCode = L"STOP_SESSION_WINDOW_CLOSED";
            result.errorMessage = L"Requested hwnd is not a live window.";
            result.dataJson = L"{\"requested_hwnd_value\":" + std::to_wstring(hwndValue) + L"}";
            return result;
        }
    } else if (!title.empty()) {
        WindowSessionResult window = ResolveWindowSession(title, process);
        if (!window.ok) {
            result.errorCode = window.errorCode.empty() ? L"WINDOW_NOT_FOUND" : window.errorCode;
            result.errorMessage = window.errorMessage;
            result.dataJson = window.dataJson;
            return result;
        }
        bound = window.session.window;
        session.requestedTitle = window.session.requestedTitle;
        session.requestedProcess = window.session.requestedProcess;
    } else {
        HWND foreground = GetForegroundWindow();
        if (foreground) {
            bound = WindowInfoFromHwndValue(reinterpret_cast<unsigned long long>(foreground));
            session.requestedTitle = bound.title;
            session.requestedProcess = ProcessNameForPid(bound.pid);
        }
    }

    if (bound.hwnd && IsWindow(bound.hwnd)) {
        session.targetHwndValue = reinterpret_cast<unsigned long long>(bound.hwnd);
        session.targetHwnd = FormatHwnd(bound.hwnd);
        session.targetProcess = bound.pid;
        session.targetProcessName = ProcessNameForPid(bound.pid);
        session.targetTitle = bound.title;
        session.targetBounds = RuntimeBoundsFromRect(bound.rect);
    }

    std::wstring error;
    if (!WriteSessionFile(session, error)) {
        result.errorCode = L"FILE_WRITE_FAILED";
        result.errorMessage = error;
        result.dataJson = RuntimeSessionJson(session);
        return result;
    }

    result.ok = true;
    result.session = session;
    result.dataJson = L"{\"session_created\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
    return result;
}

SessionManagerResult SessionManager::GetSession(const std::wstring& sessionId) {
    SessionManagerResult result;
    if (sessionId.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"--session-id is required.";
        result.dataJson = L"{}";
        return result;
    }

    std::wstring path = SessionPath(sessionId);
    DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        result.errorCode = L"STOP_SESSION_NOT_FOUND";
        result.errorMessage = L"Runtime session was not found.";
        result.dataJson = L"{\"session_id\":" + JsonString(sessionId) + L"}";
        return result;
    }

    RuntimeSession session;
    std::wstring error;
    if (!ReadSessionFile(path, session, error)) {
        result.errorCode = L"STOP_SESSION_NOT_FOUND";
        result.errorMessage = error;
        result.dataJson = L"{\"session_id\":" + JsonString(sessionId) + L"}";
        return result;
    }

    if (session.sessionClosed) {
        result.errorCode = L"STOP_SESSION_CLOSED";
        result.errorMessage = L"Runtime session is closed.";
        result.session = session;
        result.dataJson = L"{\"closed_session_rejected\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
        return result;
    }

    long long now = RuntimeSessionNowEpochMs();
    if (session.sessionLastActiveAtEpochMs > 0 && now - session.sessionLastActiveAtEpochMs > sessionTimeoutMs_) {
        session.sessionAlive = false;
        session.lastErrorCode = L"STOP_SESSION_EXPIRED";
        WriteSessionFile(session, error);
        result.errorCode = L"STOP_SESSION_EXPIRED";
        result.errorMessage = L"Runtime session expired.";
        result.session = session;
        result.dataJson = L"{\"session_expired\":true,\"session_timeout_ms\":" + std::to_wstring(sessionTimeoutMs_) + L",\"session\":" + RuntimeSessionJson(session) + L"}";
        return result;
    }

    if (session.targetProcess != 0 && !IsProcessAlive(session.targetProcess)) {
        session.sessionAlive = false;
        session.lastErrorCode = L"STOP_SESSION_TARGET_STALE";
        WriteSessionFile(session, error);
        result.errorCode = L"STOP_SESSION_TARGET_STALE";
        result.errorMessage = L"Session target process is no longer alive.";
        result.session = session;
        result.dataJson = L"{\"session_target_stale\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
        return result;
    }

    result.ok = true;
    result.session = session;
    result.dataJson = L"{\"session_status_ok\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
    return result;
}

SessionManagerResult SessionManager::SaveSession(RuntimeSession& session) {
    SessionManagerResult result;
    if (session.sessionId.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"Cannot save a session without session_id.";
        result.dataJson = L"{}";
        return result;
    }
    session.sessionLastActiveAt = NowTimestamp();
    session.sessionLastActiveAtEpochMs = RuntimeSessionNowEpochMs();
    std::wstring error;
    if (!WriteSessionFile(session, error)) {
        result.errorCode = L"FILE_WRITE_FAILED";
        result.errorMessage = error;
        result.dataJson = RuntimeSessionJson(session);
        return result;
    }
    result.ok = true;
    result.session = session;
    result.dataJson = L"{\"session_saved\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
    return result;
}

SessionManagerResult SessionManager::CloseSession(const std::wstring& sessionId) {
    SessionManagerResult loaded = GetSession(sessionId);
    if (!loaded.ok && loaded.errorCode != L"STOP_SESSION_CLOSED") {
        return loaded;
    }
    RuntimeSession session = loaded.session;
    session.sessionClosed = true;
    session.sessionAlive = false;
    session.sessionLastActiveAt = NowTimestamp();
    session.sessionLastActiveAtEpochMs = RuntimeSessionNowEpochMs();
    std::wstring error;
    if (!WriteSessionFile(session, error)) {
        SessionManagerResult result;
        result.errorCode = L"FILE_WRITE_FAILED";
        result.errorMessage = error;
        result.session = session;
        result.dataJson = RuntimeSessionJson(session);
        return result;
    }
    SessionManagerResult result;
    result.ok = true;
    result.session = session;
    result.dataJson = L"{\"session_closed\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
    return result;
}

SessionManagerResult SessionManager::ListSessions() {
    EnsureDirectoryPath(SessionDirectory());
    SessionManagerResult result;
    std::wstring pattern = SessionDirectory() + L"\\*.json";
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        result.ok = true;
        result.dataJson = SessionsDataJson({});
        return result;
    }

    std::vector<RuntimeSession> sessions;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }
        RuntimeSession session;
        std::wstring error;
        std::wstring path = SessionDirectory() + L"\\" + data.cFileName;
        if (ReadSessionFile(path, session, error)) {
            sessions.push_back(session);
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);

    result.ok = true;
    result.sessions = sessions;
    result.dataJson = SessionsDataJson(sessions);
    return result;
}

SessionManagerResult SessionManager::CleanupExpiredSessions() {
    SessionManagerResult listed = ListSessions();
    if (!listed.ok) return listed;
    long long now = RuntimeSessionNowEpochMs();
    int expired = 0;
    for (auto& session : listed.sessions) {
        if (!session.sessionClosed && session.sessionLastActiveAtEpochMs > 0 && now - session.sessionLastActiveAtEpochMs > sessionTimeoutMs_) {
            session.sessionAlive = false;
            session.lastErrorCode = L"STOP_SESSION_EXPIRED";
            std::wstring error;
            WriteSessionFile(session, error);
            ++expired;
        }
    }
    SessionManagerResult result;
    result.ok = true;
    result.dataJson = L"{\"expired_sessions\":" + std::to_wstring(expired) + L"}";
    return result;
}

SessionManagerResult SessionManager::RejectClosedSession(const RuntimeSession& session) {
    SessionManagerResult result;
    if (!session.sessionClosed) {
        result.ok = true;
        result.session = session;
        result.dataJson = L"{\"closed_session_rejected\":false}";
        return result;
    }
    result.errorCode = L"STOP_SESSION_CLOSED";
    result.errorMessage = L"Runtime session is closed.";
    result.session = session;
    result.dataJson = L"{\"closed_session_rejected\":true,\"session\":" + RuntimeSessionJson(session) + L"}";
    return result;
}

std::wstring RuntimeSessionListJson(const std::vector<RuntimeSession>& sessions) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < sessions.size(); ++i) {
        if (i) json << L",";
        json << RuntimeSessionJson(sessions[i]);
    }
    json << L"]";
    return json.str();
}
