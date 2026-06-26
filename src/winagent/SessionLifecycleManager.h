#pragma once

#include <string>
#include <vector>

struct SessionLifecycleAuditOptions {
    std::wstring runtimeSessionsRoot;
    std::wstring outputJsonPath;
    std::wstring outputMarkdownPath;
};

struct SessionLifecycleAuditResult {
    bool ok = false;
    std::wstring status;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring jsonReport;
    std::wstring markdownReport;
    int sessionCount = 0;
    int unreferencedCount = 0;
};

SessionLifecycleAuditResult AuditRuntimeSessionLifecycle(
    const SessionLifecycleAuditOptions& options);

int CommandSessionLifecycleAudit(int argc, wchar_t** argv);
