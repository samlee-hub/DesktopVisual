#pragma once

#include <string>

struct FailureAttributionNormalizationInput {
    std::wstring workflowType;
    std::wstring executionResult;
    std::wstring failureType;
    std::wstring failureCode;
    std::wstring failureReason;
};

struct FailureAttributionNormalizationResult {
    bool ok = true;
    std::wstring normalizedCategory;
    std::wstring reason;
    bool rawCompletedUnverified = false;
    bool unknownMappedToSuccess = false;
    bool successWithoutFailure = false;
    std::wstring dataJson;
};

bool IsKnownNormalizedFailureCategory(const std::wstring& category);
FailureAttributionNormalizationResult NormalizeFailureAttribution(
    const FailureAttributionNormalizationInput& input);

int CommandFailureAttributionNormalize(int argc, wchar_t** argv);
