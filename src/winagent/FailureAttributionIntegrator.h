#pragma once

#include <string>

struct FailureAttributionIntegrationOptions {
    std::wstring inputJsonPath;
    std::wstring storeRoot;
    std::wstring outputJsonPath;
};

struct FailureAttributionIntegrationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring recordJson;
};

FailureAttributionIntegrationResult IntegrateExperienceMemoryRecord(
    const FailureAttributionIntegrationOptions& options);

int CommandExperienceMemoryRecord(int argc, wchar_t** argv);
