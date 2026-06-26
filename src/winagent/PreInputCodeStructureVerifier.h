#pragma once

#include "CodeWritePlan.h"
#include "TextInputVerifier.h"

#include <string>
#include <vector>

struct PreInputCodeStructureVerifierResult {
    bool ok = true;
    bool preInputCodeStructureVerifier = true;
    bool preInputCodeStructureVerified = false;
    bool codeWritePlanVerified = false;
    bool languageScopeModelVerified = false;
    bool classMethodScopeVerified = true;
    bool instanceMethodCallVerified = true;
    bool topLevelStatementScopeVerified = true;
    bool receiverBindingVerified = true;
    bool duplicateReceiverTokenDetected = false;
    bool selfselfPresent = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    TextInputVerificationResult textVerification;
    std::vector<std::wstring> findings;
};

PreInputCodeStructureVerifierResult VerifyPreInputCodeStructure(const CodeWritePlanResult& plan, bool verifyStructure);
std::wstring PreInputCodeStructureVerifierResultJson(const PreInputCodeStructureVerifierResult& result);
