#pragma once

#include <string>

struct ExplorerWorkflowRunOptions {
    std::wstring mode = L"dry_run";
    std::wstring outputPath;
    std::wstring evidenceDir;
};

struct ExplorerWorkflowExecutionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring resultJson;
    std::wstring evidenceDir;
};

ExplorerWorkflowExecutionResult RunExplorerWorkflowSpecFile(
    const std::wstring& inputPath,
    const ExplorerWorkflowRunOptions& options);

int CommandRunExplorerWorkflow(int argc, wchar_t** argv);

