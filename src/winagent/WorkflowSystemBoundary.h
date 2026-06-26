#pragma once

#include <string>

struct WorkflowBoundaryCheckOptions {
    std::wstring outputJsonPath;
    std::wstring outputMarkdownPath;
    bool injectRunnerOnlyMock = false;
};

struct WorkflowBoundaryCheckResult {
    bool ok = false;
    std::wstring status;
    std::wstring blockedReason;
    std::wstring jsonReport;
    std::wstring markdownReport;
};

WorkflowBoundaryCheckResult CheckWorkflowSystemBoundary(
    const WorkflowBoundaryCheckOptions& options);

int CommandWorkflowBoundaryCheck(int argc, wchar_t** argv);
int CommandSystemStabilizationCheck(int argc, wchar_t** argv);
