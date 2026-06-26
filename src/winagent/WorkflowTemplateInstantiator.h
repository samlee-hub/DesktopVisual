#pragma once

#include "WorkflowTemplateRecord.h"

#include <string>

struct WorkflowTemplateInstantiationInput {
    std::wstring templatePath;
    std::wstring parametersPath;
    std::wstring expectedContextPath;
    std::wstring verificationHintPath;
    std::wstring sessionPolicyPath;
    std::wstring evidencePolicyPath;
    std::wstring outputPath;
    std::wstring evidenceOutputPath;
};

struct WorkflowTemplateInstantiationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring stepContractJson;
    std::wstring evidenceJson;
    bool stepContractValidatorUsed = false;
    bool stepContractValid = false;
};

WorkflowTemplateInstantiationResult InstantiateWorkflowTemplate(
    const WorkflowTemplateRecord& record,
    const simplejson::Value& parameterValues,
    const std::wstring& outputPath,
    const std::wstring& evidenceOutputPath);
WorkflowTemplateInstantiationResult InstantiateWorkflowTemplateFromFiles(const WorkflowTemplateInstantiationInput& input);

int CommandWorkflowTemplateInstantiate(int argc, wchar_t** argv);

