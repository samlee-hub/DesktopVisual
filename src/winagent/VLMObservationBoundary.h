#pragma once

#include <string>

struct VLMObservationBoundaryResult {
    bool boundaryEnforced = true;
    bool boundaryOk = true;
    bool runtimeExecuted = false;
    bool mouseClickSent = false;
    bool keyboardTypeSent = false;
    bool scrollSent = false;
    bool resultValidated = false;
    bool validationOk = false;
    bool safeForDirectExecution = false;
    bool safeForRuntimeCandidatePipeline = false;
    bool vlmResultEnteredRuntimeActionPath = false;
    bool vlmPossibleTargetDirectlyConvertedToAction = false;
    bool stepContractAcceptsVLMAction = false;
    bool compiledPlanExecutorAcceptsVLMAction = false;
    std::wstring blockedReason;
    std::wstring resultJson;
};

VLMObservationBoundaryResult EvaluateVLMObservationBoundary(
    const std::wstring& requestJson,
    const std::wstring& resultJson,
    const std::wstring& validationJson);

int CommandVLMObservationDryRun(int argc, wchar_t** argv);
int CommandVLMObservationSelftest(int argc, wchar_t** argv);

