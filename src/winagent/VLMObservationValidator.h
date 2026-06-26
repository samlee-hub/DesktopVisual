#pragma once

#include <string>
#include <vector>

struct VLMObservationValidationResult {
    bool validationOk = false;
    bool executable = false;
    bool assistiveOnly = false;
    bool requestIdMatch = false;
    bool resultSchemaValid = false;
    bool possibleTargetsObservationOnly = true;
    bool requiresRuntimeValidation = true;
    bool safeForRuntimeCandidatePipeline = false;
    bool safeForDirectExecution = false;
    std::vector<std::wstring> validationErrors;
    std::vector<std::wstring> validationWarnings;
    std::wstring blockedReason;
    std::wstring resultJson;
};

VLMObservationValidationResult ValidateVLMObservationResultJson(
    const std::wstring& requestJson,
    const std::wstring& resultJson);

VLMObservationValidationResult ValidateVLMObservationResultFile(
    const std::wstring& requestPath,
    const std::wstring& resultPath,
    const std::wstring& outputPath);

int CommandVLMObservationValidate(int argc, wchar_t** argv);

