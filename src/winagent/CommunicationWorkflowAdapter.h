#pragma once

#include "CommunicationWorkflow.h"

#include <string>

struct CommunicationWorkflowCompileResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring workflowId;
    std::wstring type;
    std::wstring taskIntentJson;
    std::wstring agentPlanDraftJson;
    std::wstring contractJson;
    std::wstring diagnosticsJson;
};

CommunicationWorkflowCompileResult CompileCommunicationWorkflowSpec(const CommunicationWorkflowSpec& spec);
CommunicationWorkflowCompileResult CompileCommunicationWorkflowSpecJson(const std::wstring& json);
CommunicationWorkflowCompileResult CompileCommunicationWorkflowSpecFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath);

int CommandCompileCommunicationWorkflow(int argc, wchar_t** argv);
