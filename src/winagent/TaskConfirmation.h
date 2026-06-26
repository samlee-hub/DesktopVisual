#pragma once

#include <string>

struct RiskActionClassification {
    std::wstring action;
    std::wstring normalizedAction;
    std::wstring permissionProfile;
    std::wstring riskLevel;
    bool requiresConfirmation = false;
    bool blocked = false;
    bool allowedAfterConfirmation = false;
    std::wstring blockedReason;
    std::wstring dataJson;
};

struct ConfirmationRequestCreateResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

struct ConfirmationGateResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

struct ConfirmationFlowRunResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

RiskActionClassification ClassifyRiskAction(const std::wstring& action, const std::wstring& permissionProfile);
ConfirmationRequestCreateResult CreateConfirmationRequest(
    const std::wstring& action,
    const std::wstring& riskLevel,
    const std::wstring& summary,
    const std::wstring& targetWindow,
    const std::wstring& screenshot,
    const std::wstring& involvedFiles,
    const std::wstring& destination,
    int timeoutMs,
    const std::wstring& allowedResponses);
ConfirmationGateResult CheckConfirmationGate(
    const std::wstring& action,
    const std::wstring& riskLevel,
    const std::wstring& permissionProfile,
    const std::wstring& response,
    int timeoutMs,
    int elapsedMs);
ConfirmationFlowRunResult RunLocalConfirmationFlow(const std::wstring& file, const std::wstring& response);
