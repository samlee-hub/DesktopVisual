#pragma once

#include <string>

struct StepContractV63ValidationResult {
    bool validationOk = false;
    bool executable = false;
    bool runtimeSessionCompatible = false;
    bool safeForDeveloperFullAccess = false;
    bool safeForPublicRelease = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring resultJson;
};

StepContractV63ValidationResult ValidateStepContractV63Json(const std::wstring& json);
StepContractV63ValidationResult ValidateStepContractV63File(
    const std::wstring& inputPath,
    const std::wstring& resultPath);

int CommandStepContractValidateV63(int argc, wchar_t** argv);
