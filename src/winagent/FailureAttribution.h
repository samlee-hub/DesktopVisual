#pragma once

#include <string>

enum class FailureAttributionKind {
    APP_NOT_INSTALLED,
    APP_LAUNCH_FAILED,
    FOREGROUND_ACQUIRE_FAILED,
    EXPECTED_CONTEXT_FAILED,
    UIA_READ_FAILED,
    OCR_READ_FAILED,
    TARGET_NOT_VISIBLE,
    TARGET_SEEN_BUT_NOT_CONFIRMED,
    TARGET_NOT_UNIQUE,
    SCROLL_REGION_NOT_FOUND,
    SCROLL_NO_PROGRESS,
    WRONG_FIELD_FOCUS,
    BROWSER_SURFACE_BLOCKING,
    ACTIVE_PROTECTION_STOP,
    CREDENTIAL_REQUIRED_STOP,
    SCRIPT_DETECTION_CHALLENGE_STOP,
    ANTI_CHEAT_STOP,
    RECOVERY_NOT_ALLOWED,
    RECOVERY_FAILED,
    ACTION_BLOCKED_BY_POLICY,
    ENVIRONMENT_UNSTABLE,
    RUNTIME_GUARD_STOP,
    UNKNOWN_FAILURE
};

struct FailureAttributionInput {
    std::wstring errorCode;
    std::wstring stopCode;
    std::wstring failureReason;
    std::wstring contextText;
    std::wstring targetType;
};

struct FailureAttributionResult {
    FailureAttributionKind attribution = FailureAttributionKind::UNKNOWN_FAILURE;
    std::wstring attributionName;
    std::wstring reason;
    bool activeProtectionDetected = false;
    bool credentialRequiredDetected = false;
    bool scriptDetectionChallengeDetected = false;
    bool antiCheatDetected = false;
};

std::wstring FailureAttributionKindName(FailureAttributionKind kind);
FailureAttributionResult ClassifyFailureAttribution(const FailureAttributionInput& input);
std::wstring FailureAttributionResultJson(const FailureAttributionResult& result);
