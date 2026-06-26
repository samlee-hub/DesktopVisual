#pragma once

#include <string>
#include <vector>

struct SafetyPolicy;

struct PermissionModeProfile {
    bool allowThirdPartyApps = false;
    bool allowExternalWeb = false;
    bool allowCommunication = false;
    bool allowContentDecision = false;
    bool allowCrossWindow = false;
    bool allowGlobalDesktop = false;
    bool allowBrowser = false;
    bool allowExplorer = false;
    bool allowLocalFileOpen = false;
    bool allowLocalhost = false;
    bool requiresFullAccessSession = false;
};

struct SafetyManifest {
    bool loaded = false;
    std::wstring manifestPath;
    int version = 1;
    std::wstring project = L"DesktopVisual";
    std::wstring mode = L"local_authorized_windows_runtime";
    std::wstring defaultPermissionMode = L"DEVELOPER_CAPABILITY_DISCOVERY";
    std::vector<std::wstring> allowedWindowTitles;
    std::vector<std::wstring> allowedProcesses;
    std::vector<std::wstring> allowedReadRoots;
    std::vector<std::wstring> allowedWriteRoots;
    std::vector<std::wstring> allowedActions;
    std::vector<std::wstring> deniedWindowTitlePatterns;
    std::vector<std::wstring> deniedProcesses;
    std::vector<std::wstring> deniedSensitiveCategories;
    int maxSteps = 100;
    int maxDurationMs = 120000;
    int maxRecoveries = 2;
    std::wstring emergencyStopKey = L"F12";
    bool requiresExplicitTarget = true;
    bool requiresVisibleForegroundWindow = true;
    bool allowBackgroundControl = false;
    bool allowUnrestrictedDesktop = false;
    bool writeAuditLog = true;
    bool writeMarkdownReport = true;
    bool redactClipboardTextInLogs = true;
    std::wstring reportLevel = L"compact";
    std::wstring evidenceLevel = L"full";
    std::wstring progressOutput = L"compact";
    std::wstring stepChatDetail = L"compact";
    std::wstring artifactEvidence = L"full";
    std::wstring failureDetail = L"expanded_with_error_evidence_next_repair";
    PermissionModeProfile defaultPermission;
    PermissionModeProfile publicDefaultPermission;
    PermissionModeProfile developerPermission;
    PermissionModeProfile ciMockPermission;
    PermissionModeProfile fullAccessPermission;
    std::vector<std::wstring> warnings;
};

struct PolicyCheckDecision {
    bool allow = false;
    std::wstring errorCode;
    std::wstring reason;
    std::wstring matchedRule;
    std::wstring matchedCategory;
    std::wstring title;
    std::wstring process;
    std::wstring action;
    std::wstring path;
    std::wstring permissionMode = L"DEFAULT";
    std::wstring fullAccessSessionId;
    bool fullAccessSessionActive = false;
    bool fullAccessSessionExpired = false;
    std::wstring fullAccessScope;
};

SafetyManifest LoadSafetyManifest();
PolicyCheckDecision EvaluatePolicyCheck(
    const SafetyPolicy& policy,
    const SafetyManifest& manifest,
    const std::wstring& title,
    const std::wstring& process,
    const std::wstring& action,
    const std::wstring& path,
    bool relaxConfiguredBoundary = false,
    const std::wstring& permissionMode = L"DEFAULT",
    const std::wstring& fullAccessSessionId = L"",
    bool fullAccessSessionActive = false,
    bool fullAccessSessionExpired = false,
    const std::wstring& fullAccessScope = L"");
bool IsDeniedBySafetyManifest(
    const SafetyManifest& manifest,
    const std::wstring& title,
    const std::wstring& process,
    std::wstring& matchedRule,
    std::wstring& matchedCategory);
std::wstring SafetyManifestSummaryJson(const SafetyManifest& manifest);
std::wstring SafetyReportDataJson(const SafetyPolicy& policy, const SafetyManifest& manifest);
bool WriteSafetyReportFiles(const SafetyPolicy& policy, const SafetyManifest& manifest, std::wstring& jsonPath, std::wstring& markdownPath, std::wstring& error);
