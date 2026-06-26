#pragma once

#include "SimpleJson.h"

#include <string>

struct StepExecutionVerificationInput {
    std::wstring stepId;
    int stepIndex = 0;
    std::wstring runtimeAction;
    std::wstring target;
    std::wstring inputText;
    const simplejson::Value* verificationHint = nullptr;
    std::wstring contextText;
    std::wstring fieldValue;
    std::wstring windowTitle;
    std::wstring url;
    std::wstring outputText;
    bool wrongContextDetected = false;
    bool wrongFieldDetected = false;
};

struct StepExecutionVerificationResult {
    bool verificationOk = false;
    std::wstring verificationType;
    std::wstring evidence;
    std::wstring stopCode;
    std::wstring failureAttribution;
    std::wstring resultJson;
};

StepExecutionVerificationResult VerifyStepExecution(const StepExecutionVerificationInput& input);

int CommandStepExecutionVerify(int argc, wchar_t** argv);
