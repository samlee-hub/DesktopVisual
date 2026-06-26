#pragma once

#include "CodeWritePlan.h"

#include <string>
#include <vector>

struct IncrementalCodeInputVerifierResult {
    bool ok = true;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool incrementalCodeInputVerifier = true;
    bool tokenStructureVerified = false;
    bool scopeStructureVerified = false;
    bool noRetryContamination = false;
    bool pythonMethodSelfVerified = true;
    bool balancedDelimiterVerified = true;
    std::vector<std::wstring> findings;
};

IncrementalCodeInputVerifierResult VerifyIncrementalCodeInputPlan(const CodeWritePlanResult& plan);
std::wstring IncrementalCodeInputVerifierResultJson(const IncrementalCodeInputVerifierResult& result);
