#pragma once

#include <string>
#include <vector>

struct StepContractSafetyRequirements {
    std::wstring permissionProfile = L"DEFAULT";
    bool allowUnrestrictedDesktop = false;
    bool requiresHumanConfirmation = false;
};

struct StepContractExpectedContextV63 {
    std::wstring expectedProcessPattern;
    std::wstring expectedTitlePattern;
    std::vector<std::wstring> requiredMarkers;
    std::vector<std::wstring> wrongPagePatterns;
    std::vector<std::wstring> activeProtectionPatterns;
    std::vector<std::wstring> credentialRequiredPatterns;
    bool foregroundRequired = true;
    bool windowBindingRequired = true;
};

struct StepContractActionPreconditionV63 {
    bool targetRequired = true;
    bool targetUniqueRequired = true;
    bool targetInsideViewportRequired = true;
    bool targetCurrentObserveRequired = true;
    bool focusRequired = true;
    bool mouseFirstRequired = false;
    bool textInputAllowed = false;
    bool scrollAllowed = false;
    bool staleTargetRejectRequired = true;
};

struct StepContractVerificationHintV63 {
    std::wstring verifyType;
    std::wstring expectedMarker;
    std::wstring expectedText;
    std::wstring expectedWindowTitle;
    std::wstring expectedUrlPattern;
    std::wstring expectedOutputPattern;
    std::wstring expectedFieldValue;
    bool postActionReobserveRequired = true;
};

struct StepContractConfirmationPolicyV63 {
    bool confirmationRequired = false;
    std::wstring confirmationReason;
    bool developerFullAccessAllowed = false;
    bool publicReleaseConfirmationRequired = false;
    bool manualHandoffRequired = false;
};

struct StepContractRecoveryPolicyV63 {
    bool recoveryAllowed = true;
    std::wstring recoveryScope = L"reobserve_only";
    std::wstring recoveryTarget = L"same_context";
    int maxRecoveryAttempts = 1;
    bool resumeFromCheckpointAllowed = true;
    bool replayFromCheckpointAllowed = false;
    bool stopIfRecoveryFails = true;
};

struct StepContractStopPolicyV63 {
    bool stopOnWrongContext = true;
    bool stopOnWrongField = true;
    bool stopOnTargetStale = true;
    bool stopOnTargetNotUnique = true;
    bool stopOnActiveProtection = true;
    bool stopOnCredentialRequired = true;
    bool stopOnUnverifiedResult = true;
    bool stopOnRuntimeGuardFailure = true;
};

struct StepContractSessionPolicyV63 {
    bool sessionRequired = true;
    bool sessionReuseAllowed = true;
    bool forceReobserveBeforeAction = true;
    std::wstring cachePolicy = L"force_reobserve";
    bool locatorCacheAllowed = false;
};

struct StepContractEvidencePolicyV63 {
    bool rawEvidenceRequired = true;
    bool verifierRequired = true;
    bool gateRequired = true;
    bool mouseEvidenceRequired = true;
    bool latencyRequired = true;
};

struct StepContractV63 {
    std::wstring contractId;
    std::wstring taskId;
    std::wstring planId;
    std::wstring stepId;
    int stepIndex = 0;
    std::wstring stepType;
    std::wstring runtimeAction;
    std::wstring target;
    std::wstring inputText;
    bool executable = true;
    StepContractExpectedContextV63 expectedContext;
    StepContractActionPreconditionV63 actionPrecondition;
    StepContractVerificationHintV63 verificationHint;
    std::wstring riskLevel = L"LOW_RISK";
    StepContractConfirmationPolicyV63 confirmationPolicy;
    StepContractRecoveryPolicyV63 recoveryPolicy;
    StepContractStopPolicyV63 stopPolicy;
    StepContractSessionPolicyV63 sessionPolicy;
    StepContractEvidencePolicyV63 evidencePolicy;
    std::wstring createdAt;
    std::wstring compilerVersion = L"6.3.0";
};

struct StepElementExpectation {
    std::wstring elementId;
    std::wstring condition = L"appeared";
};

struct StepContract {
    std::wstring schemaVersion;
    std::wstring stepId;
    std::wstring name;
    int preconditionCount = 0;
    std::wstring preconditionExpectedSceneState;
    std::wstring preconditionElementId;
    bool requiresTargetReady = false;
    bool requiresWindowFocused = false;
    std::wstring requiredProfile;
    std::wstring requiredSafetyAction;
    std::wstring requiredCapability;
    std::wstring actionType;
    std::wstring actionLocator;
    std::wstring verificationType;
    std::wstring verificationExpectedText;
    std::wstring verificationExpectedSceneState;
    int timeoutMs = 0;
    int retryMaxAttempts = 0;
    int retryBackoffMs = 0;
    std::wstring onFailureStrategy;
    std::wstring onFailureReason;
    StepContractSafetyRequirements safety;
    std::wstring expectedSceneState;
    int expectedChangeEventCount = 0;
    int expectedElementCount = 0;
    std::vector<std::wstring> expectedChangeEvents;
    std::vector<StepElementExpectation> expectedElements;
};

struct StepContractValidationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    StepContract contract;
};

struct PreconditionCheckResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    int passedCount = 0;
    int failedCount = 0;
};

struct StepVerificationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

struct FailureReasonRecord {
    std::wstring stepId;
    std::wstring rawErrorCode;
    std::wstring failureReason;
    std::wstring category;
    std::wstring recommendedAction;
    std::wstring dataJson;
};

StepContractValidationResult ValidateStepContractFile(const std::wstring& path);
std::wstring StepContractDataJson(const StepContract& contract);
PreconditionCheckResult CheckStepPreconditions(const std::wstring& contractPath, const std::wstring& perceptionPath);
StepVerificationResult VerifyStepAfterAction(
    const std::wstring& contractPath,
    const std::wstring& beforePath,
    const std::wstring& afterPath,
    int timeoutMs,
    int elapsedMs);
FailureReasonRecord ClassifyStepFailureReason(const std::wstring& stepId, const std::wstring& errorCode);
