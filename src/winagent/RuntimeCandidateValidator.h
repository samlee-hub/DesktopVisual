#pragma once

#include "VLMObservationContract.h"

#include <windows.h>

#include <string>
#include <vector>

struct RuntimeCandidateValidationOptions {
    std::wstring targetLabel;
    std::wstring expectedContext;
    std::wstring actionPrecondition;
    std::wstring riskPolicy;
};

struct RuntimeCandidateEvidencePack {
    bool screenshotPathPresent = false;
    bool uiaCorroborated = false;
    bool ocrCorroborated = false;
    bool contextCorroborated = false;
    bool elementSummaryCorroborated = false;
    std::wstring screenshotPath;
    std::wstring matchedOcrText;
    std::wstring matchedUiaText;
    std::wstring expectedContext;
};

struct RuntimeCandidateValidationResult {
    bool candidateValidationOk = false;
    std::wstring candidateId;
    std::wstring candidateLabel;
    std::wstring candidateRole;
    RECT validatedRect = {};
    int validatedCenterX = 0;
    int validatedCenterY = 0;
    double confidence = 0.0;
    std::wstring validationMethod;
    std::wstring matchedOcrText;
    std::wstring matchedUiaText;
    bool insideViewport = false;
    bool uniqueEnough = false;
    bool contextOk = false;
    bool riskOk = false;
    bool freshnessOk = false;
    bool requiresReobserve = false;
    std::wstring rejectionReason;
    bool safeToConvertToLocatorCandidate = false;
    bool observationOnly = false;
    bool requiresRuntimeValidation = false;
    bool directCoordinateForbidden = false;
    RuntimeCandidateEvidencePack evidence;
};

struct RuntimeCandidateValidationBatch {
    bool validationOk = false;
    int candidateCount = 0;
    int validatedCandidateCount = 0;
    int rejectedCandidateCount = 0;
    bool selectedCandidateUnique = false;
    RuntimeCandidateValidationResult selectedCandidate;
    std::vector<RuntimeCandidateValidationResult> candidates;
    std::vector<std::wstring> rejectionReasons;
    std::wstring stopCode;
    std::wstring resultJson;
};

RuntimeCandidateValidationBatch ValidateRuntimeCandidatesFromJson(
    const std::wstring& requestJson,
    const std::wstring& vlmResultJson,
    const RuntimeCandidateValidationOptions& options);

std::wstring RuntimeCandidateValidationResultJson(const RuntimeCandidateValidationResult& result);
std::wstring RuntimeCandidateValidationBatchJson(const RuntimeCandidateValidationBatch& batch);

