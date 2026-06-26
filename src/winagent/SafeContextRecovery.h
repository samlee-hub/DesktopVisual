#pragma once

#include <string>
#include <vector>

struct SafeRecoveryPolicy {
    bool recoveryEnabled = false;
    std::wstring recoveryScope;
    std::vector<std::wstring> allowedRecoveryTargets;
    std::vector<std::wstring> disallowedRecoveryPatterns;
    int maxRecoveryAttempts = 1;
    std::wstring recoveryAction;
    std::wstring recoveryUrl;
    std::wstring recoveryPath;
    std::wstring recoveryWindowTitlePattern;
    std::wstring recoveryProcessPattern;
    std::vector<std::wstring> recoveryExpectedMarkers;
    std::wstring resumePolicy;
    bool checkpointRequired = false;
    bool reobserveRequired = true;
    bool stopIfActiveProtection = true;
    bool stopIfCredentialRequired = true;
};

struct RecoveryRequest {
    SafeRecoveryPolicy policy;
    int recoveryAttemptCount = 0;
    std::wstring currentContextText;
    bool checkpointAvailable = false;
    bool dryRun = false;
};

struct RecoveryResult {
    bool recoveryAttempted = false;
    bool recoveryAllowed = false;
    bool recoverySuccess = false;
    std::wstring recoveryActionExecuted;
    int recoveryAttemptCount = 0;
    std::wstring recoveryStopCode;
    std::wstring recoveryReason;
    std::wstring recoveredContextTitle;
    std::wstring recoveredContextProcess;
    bool recoveredMarkersOk = false;
    bool resumedFromCheckpoint = false;
    bool resumeAllowed = false;
    std::wstring resumeBlockReason;
    bool activeProtectionDetected = false;
    bool credentialRequiredDetected = false;
};

bool ParseRecoveryPolicyFromArgs(int argc, wchar_t** argv, RecoveryRequest& request, std::wstring& error);
RecoveryResult EvaluateSafeContextRecovery(const RecoveryRequest& request);
std::wstring RecoveryPolicyJson(const SafeRecoveryPolicy& policy);
std::wstring RecoveryResultJson(const RecoveryResult& result);
