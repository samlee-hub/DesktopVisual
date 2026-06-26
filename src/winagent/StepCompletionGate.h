#pragma once

#include <string>

struct StepCompletionInput {
    std::wstring stepId;
    std::wstring stepName;
    std::wstring stepType;
    std::wstring expectedContext;
    std::wstring expectedPreconditions;
    std::wstring actionName;
    std::wstring actionResult;
    std::wstring rawActionEvidence;
    bool preconditionVerified = true;
    bool actionExecuted = true;
    bool postObserveRequired = false;
    bool postObservePerformed = true;
    bool postconditionVerified = true;
    std::wstring postObserveResult;
    std::wstring expectedPostconditions;
    std::wstring failureAttributionOnFail;

    bool editorClickedByMouseProvided = false;
    bool editorClickedByMouse = true;
    bool editorFocusVerifiedProvided = false;
    bool editorFocusVerified = true;
    bool codeTextVerifiedProvided = false;
    bool codeTextVerified = true;
    bool runTriggeredProvided = false;
    bool runTriggered = false;
    bool executionSuccessProvided = false;
    bool executionSuccess = true;
};

struct StepCompletionResult {
    std::wstring stepId;
    bool preconditionVerified = false;
    bool actionExecuted = false;
    bool postObservePerformed = false;
    bool postconditionVerified = false;
    bool stepVerified = false;
    bool nextStepAllowed = false;
    std::wstring stopCode;
    std::wstring failureAttribution;
    std::wstring reason;
    std::wstring evidencePath;

    bool runTriggeredProvided = false;
    bool runTriggered = false;
    bool executionSuccessProvided = false;
    bool executionSuccess = false;
};

StepCompletionInput ParseStepCompletionInputJson(const std::wstring& jsonText);
StepCompletionResult EvaluateStepCompletionGate(const StepCompletionInput& input);
std::wstring StepCompletionResultJson(const StepCompletionResult& result);
