#pragma once

#include "WindowFinder.h"

#include <windows.h>

#include <string>

struct TraceTarget {
    bool hasTarget = false;
    std::wstring title;
    std::wstring hwnd;
    DWORD pid = 0;
};

TraceTarget NoTraceTarget();
TraceTarget MakeTraceTarget(const WindowInfo& window);

std::wstring NowTimestamp();
long long ElapsedMs(ULONGLONG startTick);
std::wstring JsonEscape(const std::wstring& value);
std::wstring JsonString(const std::wstring& value);
std::wstring ErrorMessageForCode(const std::wstring& code);

std::wstring TargetJson(const TraceTarget& target);
std::wstring CommandSuccessJson(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& dataJson);
std::wstring CommandFailureJson(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson);

bool AppendAuditLine(
    const std::wstring& command,
    const std::wstring& targetTitle,
    const std::wstring& result,
    const std::wstring& errorCode,
    long long durationMs,
    const std::wstring& data);

std::wstring AuditEscape(const std::wstring& value);
