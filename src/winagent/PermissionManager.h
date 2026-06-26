#pragma once

#include "SafetyManifest.h"

#include <string>

enum class PermissionMode {
    DEFAULT,
    PUBLIC_DEFAULT,
    DEVELOPER_CAPABILITY_DISCOVERY,
    CI_MOCK,
    FULL_ACCESS
};

enum class PermissionDecisionKind {
    ALLOW,
    ALLOW_AUDITED,
    STOP_ACTIVE_PROTECTION,
    DENY_UNSUPPORTED,
    DENY_CONFIG_ERROR,
    REQUIRE_USER_CONFIRMATION,
    LEGACY_FULL_ACCESS_REQUIRED
};

struct PermissionDecision {
    bool allow = false;
    PermissionMode mode = PermissionMode::DEFAULT;
    PermissionDecisionKind decision = PermissionDecisionKind::DENY_UNSUPPORTED;
    std::wstring errorCode;
    std::wstring reason;
    std::wstring matchedRule;
    std::wstring matchedCategory;
    std::wstring action;
    std::wstring title;
    std::wstring process;
    std::wstring fullAccessSessionId;
    bool fullAccessSessionActive = false;
    bool fullAccessSessionExpired = false;
    std::wstring fullAccessScope;
    long long fullAccessExpiresAtUnixMs = 0;
    bool relaxConfiguredBoundary = false;
};

struct FullAccessSessionStatus {
    bool exists = false;
    bool active = false;
    bool expired = false;
    std::wstring sessionId;
    std::wstring scope = L"session-only";
    int ttlSeconds = 0;
    long long createdAtUnixMs = 0;
    long long expiresAtUnixMs = 0;
    long long remainingTtlSeconds = 0;
    std::wstring path;
};

std::wstring PermissionModeName(PermissionMode mode);
bool ParsePermissionMode(const std::wstring& value, PermissionMode& mode);
std::wstring PermissionDecisionKindName(PermissionDecisionKind decision);
std::wstring DefaultPermissionModeName();

FullAccessSessionStatus GetFullAccessSessionStatus();
bool UnlockFullAccessSession(int ttlSeconds, const std::wstring& scope, FullAccessSessionStatus& status, std::wstring& error);
bool LockFullAccessSession(std::wstring& error);

PermissionDecision EvaluatePermissionRequest(
    const SafetyManifest& manifest,
    const std::wstring& title,
    const std::wstring& process,
    const std::wstring& action,
    PermissionMode mode,
    const std::wstring& fullAccessSessionId);

std::wstring FullAccessSessionStatusJson(const FullAccessSessionStatus& status);
std::wstring PermissionDecisionJson(const PermissionDecision& decision);
std::wstring PermissionStatusDataJson();
