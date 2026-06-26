#pragma once

#include "BrowserWorkflow.h"

#include <string>

struct BrowserWorkflowCompileResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring workflowId;
    std::wstring workflowType;
    std::wstring contractJson;
    std::wstring diagnosticsJson;
};

BrowserWorkflowCompileResult CompileBrowserWorkflowSpec(const BrowserWorkflowSpec& spec);
BrowserWorkflowCompileResult CompileBrowserWorkflowSpecJson(const std::wstring& json);
BrowserWorkflowCompileResult CompileBrowserWorkflowSpecFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath);

int CommandCompileBrowserWorkflow(int argc, wchar_t** argv);
