#pragma once

#include <string>

struct CommunicationWorkflowRunOptions {
    std::wstring mode = L"execute_local_safe";
    std::wstring outputPath;
    std::wstring evidenceDir;
};

struct CommunicationWorkflowExecutionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring resultJson;
    std::wstring evidenceDir;
};

CommunicationWorkflowExecutionResult RunCommunicationWorkflowSpecFile(
    const std::wstring& inputPath,
    const CommunicationWorkflowRunOptions& options);

int CommandRunCommunicationWorkflow(int argc, wchar_t** argv);
