#pragma once

#include <string>

struct CommunicationWorkflowVerificationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring verificationJson;
};

CommunicationWorkflowVerificationResult VerifyCommunicationWorkflowResultJson(const std::wstring& resultJson);
CommunicationWorkflowVerificationResult VerifyCommunicationWorkflowResultFile(
    const std::wstring& resultPath,
    const std::wstring& outputPath);

int CommandVerifyCommunicationWorkflow(int argc, wchar_t** argv);
