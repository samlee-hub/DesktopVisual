#pragma once

#include <string>

struct BrowserWorkflowVerificationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring verificationJson;
};

BrowserWorkflowVerificationResult VerifyBrowserWorkflowResultJson(const std::wstring& resultJson);
BrowserWorkflowVerificationResult VerifyBrowserWorkflowResultFile(
    const std::wstring& resultPath,
    const std::wstring& outputPath);

int CommandVerifyBrowserWorkflow(int argc, wchar_t** argv);
