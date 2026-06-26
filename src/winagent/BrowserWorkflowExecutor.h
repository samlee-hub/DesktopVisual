#pragma once

#include <string>

struct BrowserWorkflowRunOptions {
    std::wstring mode = L"dry_run";
    std::wstring outputPath;
    std::wstring evidenceDir;
};

struct BrowserWorkflowExecutionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring resultJson;
    std::wstring evidenceDir;
};

BrowserWorkflowExecutionResult RunBrowserWorkflowSpecFile(
    const std::wstring& inputPath,
    const BrowserWorkflowRunOptions& options);

int CommandRunBrowserWorkflow(int argc, wchar_t** argv);
