#pragma once

#include "SimpleJson.h"

#include <string>

struct StepContractRuntimeAdapterResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring sessionStepsJson;
    int stepCount = 0;
};

std::wstring RuntimeSessionActionForStepContractAction(const std::wstring& runtimeAction);
StepContractRuntimeAdapterResult AdaptStepContractToRuntimeSessionSteps(const simplejson::Value& stepContractRoot);
StepContractRuntimeAdapterResult AdaptStepContractJsonToRuntimeSessionSteps(const std::wstring& stepContractJson);
