#pragma once

#include "LocatorCandidate.h"
#include "RuntimeCandidateValidator.h"

#include <string>
#include <vector>

struct VLMCandidateBridgeOptions {
    bool locateFailed = true;
    std::wstring locateFailedReason = L"LOCATOR_NOT_FOUND";
    std::wstring observeJson;
    std::wstring screenshotPath;
    std::wstring targetLabel;
    std::wstring expectedContext;
    std::wstring provider = L"mock";
    std::wstring scenario = L"valid";
    std::wstring evidenceDir;
};

struct VLMCandidateBridgeResult {
    bool bridgeInvoked = false;
    bool runtimeLocatorFailed = false;
    std::wstring locateFailedReason;
    std::wstring requestId;
    std::wstring resultId;
    std::wstring providerName;
    bool vlmResultValidated = false;
    int candidateCount = 0;
    int validatedCandidateCount = 0;
    int rejectedCandidateCount = 0;
    std::wstring selectedCandidateId;
    bool candidateValidationRequired = true;
    bool runtimeExecutionAllowed = false;
    std::wstring runtimeExecutionReason;
    std::vector<std::wstring> rejectionReasons;
    std::vector<std::wstring> evidencePaths;
    RuntimeCandidateValidationBatch runtimeValidation;
    LocatorCandidate locatorCandidate;
    std::wstring requestJson;
    std::wstring resultJson;
    std::wstring vlmValidationJson;
    std::wstring resultJsonText;
};

VLMCandidateBridgeResult RunVLMCandidateBridge(const VLMCandidateBridgeOptions& options);
std::wstring VLMCandidateBridgeResultJson(const VLMCandidateBridgeResult& result);
std::wstring VLMAssistedLocatePayloadJson(
    const VLMCandidateBridgeResult& bridge,
    bool runtimeExecuted,
    bool mouseClickSent,
    bool runtimeContextGuardUsed,
    bool postActionVerified,
    const std::wstring& actionEvidenceJson = L"null");

