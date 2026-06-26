#pragma once

#include "ExplorerWorkflow.h"

#include <string>

struct ExplorerWorkflowVerificationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring verificationJson;
};

bool ExplorerWorkflowFileExists(const std::wstring& path);
bool ExplorerWorkflowDirectoryExists(const std::wstring& path);

ExplorerWorkflowVerificationResult VerifyExplorerWorkflowResultJson(const std::wstring& resultJson);
ExplorerWorkflowVerificationResult VerifyExplorerWorkflowResultFile(
    const std::wstring& resultPath,
    const std::wstring& outputPath);

int CommandVerifyExplorerWorkflow(int argc, wchar_t** argv);

