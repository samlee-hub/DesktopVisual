#pragma once

#include "ExplorerWorkflow.h"

#include <string>

struct ExplorerWorkflowCompileResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring workflowId;
    std::wstring workflowType;
    std::wstring contractJson;
    std::wstring diagnosticsJson;
};

ExplorerWorkflowCompileResult CompileExplorerWorkflowSpec(const ExplorerWorkflowSpec& spec);
ExplorerWorkflowCompileResult CompileExplorerWorkflowSpecJson(const std::wstring& json);
ExplorerWorkflowCompileResult CompileExplorerWorkflowSpecFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath);

int CommandCompileExplorerWorkflow(int argc, wchar_t** argv);

