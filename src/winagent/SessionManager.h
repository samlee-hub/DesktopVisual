#pragma once

#include "RuntimeSession.h"

#include <string>
#include <vector>

struct SessionManagerResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    RuntimeSession session;
    std::vector<RuntimeSession> sessions;
    std::wstring dataJson;
};

class SessionManager {
public:
    explicit SessionManager(long long sessionTimeoutMs = 30 * 60 * 1000);

    SessionManagerResult CreateSession(
        const std::wstring& title,
        const std::wstring& process,
        unsigned long long hwndValue = 0);
    SessionManagerResult GetSession(const std::wstring& sessionId);
    SessionManagerResult SaveSession(RuntimeSession& session);
    SessionManagerResult CloseSession(const std::wstring& sessionId);
    SessionManagerResult ListSessions();
    SessionManagerResult CleanupExpiredSessions();
    SessionManagerResult RejectClosedSession(const RuntimeSession& session);

    long long SessionTimeoutMs() const { return sessionTimeoutMs_; }
    std::wstring SessionDirectory() const;

private:
    long long sessionTimeoutMs_;

    std::wstring SessionPath(const std::wstring& sessionId) const;
    bool ReadSessionFile(const std::wstring& path, RuntimeSession& session, std::wstring& error) const;
    bool WriteSessionFile(const RuntimeSession& session, std::wstring& error) const;
};

std::wstring RuntimeSessionListJson(const std::vector<RuntimeSession>& sessions);
