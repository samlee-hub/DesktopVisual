#pragma once

#include "WorkflowTemplateRecord.h"

#include <string>
#include <vector>

struct WorkflowTemplateSafetyResult {
    bool ok = false;
    std::wstring status;
    std::wstring blockedReason;
    std::vector<std::wstring> violations;
    std::wstring jsonReport;
};

bool WorkflowTemplateSourceTrusted(const std::wstring& sourceRef);
WorkflowTemplateSafetyResult CheckWorkflowTemplateSafety(const WorkflowTemplateRecord& record);
WorkflowTemplateSafetyResult CheckWorkflowTemplateSafetyJson(const std::wstring& json);
WorkflowTemplateSafetyResult CheckWorkflowTemplateSafetyFile(const std::wstring& inputPath);

int CommandWorkflowTemplateSafetyCheck(int argc, wchar_t** argv);

