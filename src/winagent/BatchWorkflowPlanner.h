#pragma once

#include "BatchWorkflowPlan.h"

#include <string>

BatchWorkflowPlanResult PlanBatchWorkflowFromFile(const std::wstring& inputPath);
int CommandBatchWorkflowPlan(int argc, wchar_t** argv);

