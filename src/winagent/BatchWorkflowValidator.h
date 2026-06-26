#pragma once

#include "BatchWorkflowPlan.h"

#include <string>
#include <vector>

struct BatchWorkflowValidationResult {
    bool ok = false;
    std::wstring status;
    std::wstring blockedReason;
    std::vector<std::wstring> violations;
    std::wstring reportJson;
};

BatchWorkflowValidationResult ValidateBatchWorkflowPlan(const BatchWorkflowPlan& plan);
BatchWorkflowValidationResult ValidateBatchWorkflowPlanFile(const std::wstring& inputPath);
int CommandBatchWorkflowValidate(int argc, wchar_t** argv);

