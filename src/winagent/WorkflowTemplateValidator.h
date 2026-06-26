#pragma once

#include "WorkflowTemplateRecord.h"

#include <string>
#include <vector>

struct WorkflowTemplateValidationResult {
    bool ok = false;
    std::wstring validationStatus;
    std::wstring reasonCode;
    std::wstring reasonMessage;
    WorkflowTemplateRecord record;
    std::vector<std::wstring> violations;
    std::wstring reportJson;
};

WorkflowTemplateValidationResult ValidateWorkflowTemplateRecord(const WorkflowTemplateRecord& record);
WorkflowTemplateValidationResult ValidateWorkflowTemplateJson(const std::wstring& json);
WorkflowTemplateValidationResult ValidateWorkflowTemplateFile(const std::wstring& inputPath);
WorkflowTemplateRecord PromoteWorkflowTemplateToValidated(WorkflowTemplateRecord record, const std::wstring& validationReportRef);
WorkflowTemplateRecord RejectWorkflowTemplate(WorkflowTemplateRecord record, const std::wstring& reasonCode, const std::wstring& validationReportRef);
WorkflowTemplateRecord DeprecateWorkflowTemplate(WorkflowTemplateRecord record, const std::wstring& validationReportRef);

int CommandWorkflowTemplateValidate(int argc, wchar_t** argv);

