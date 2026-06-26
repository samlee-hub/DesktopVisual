#pragma once

#include "RuntimeCandidateValidator.h"

#include <windows.h>

#include <string>

struct LocatorCandidate {
    bool created = false;
    std::wstring candidateSource = L"vlm_assisted_runtime_validated";
    std::wstring sourceRequestId;
    std::wstring sourceResultId;
    std::wstring sourceCandidateId;
    RECT targetRect = {};
    int targetCenterX = 0;
    int targetCenterY = 0;
    std::wstring role;
    std::wstring label;
    double confidence = 0.0;
    bool runtimeValidationOk = false;
    std::wstring runtimeValidationMethod;
    bool requiresFinalGuardCheck = true;
    bool requiresMouseFirstEvidence = true;
    bool requiresPostActionVerification = true;
    std::wstring coordinateSourceType = L"vlm_assisted_runtime_validated";
    std::wstring selector;
};

LocatorCandidate ConvertRuntimeValidatedCandidateToLocatorCandidate(
    const RuntimeCandidateValidationResult& candidate,
    const std::wstring& requestId,
    const std::wstring& resultId);

std::wstring LocatorCandidateJson(const LocatorCandidate& candidate);

