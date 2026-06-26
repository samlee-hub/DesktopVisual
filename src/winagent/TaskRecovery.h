#pragma once

#include <string>

struct RecoveryPolicy {
    std::wstring schemaVersion;
    std::wstring policyId;
    std::wstring taskType;
    std::wstring permissionProfile;
    int retryMaxAttempts = 0;
    int retryMaxWaitMs = 0;
    int retryMaxTotalRecoveryMs = 0;
    int retryBackoffMs = 0;
    int routeCount = 0;
    bool recordAttempts = false;
    std::wstring artifactDir;
};

struct RecoveryPolicyValidationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    RecoveryPolicy policy;
};

struct RecoveryAttemptEvaluationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

struct EscalationRequestResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

struct SafeStopCheckResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

RecoveryPolicyValidationResult ValidateRecoveryPolicyFile(const std::wstring& path);
std::wstring RecoveryPolicyDataJson(const RecoveryPolicy& policy);
RecoveryAttemptEvaluationResult EvaluateRecoveryAttempt(
    const std::wstring& policyPath,
    const std::wstring& failureReason,
    const std::wstring& contextPath,
    int attempt);
EscalationRequestResult CreateEscalationRequest(
    const std::wstring& reason,
    const std::wstring& currentTask,
    const std::wstring& currentStep,
    const std::wstring& contextPath);
SafeStopCheckResult CheckSafeStop(const std::wstring& reason, const std::wstring& contextPath);
