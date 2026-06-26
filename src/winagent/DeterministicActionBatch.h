#pragma once

#include <string>
#include <vector>

struct DeterministicBatchTimelineEntry {
    std::wstring operationId;
    std::wstring operationType;
    std::wstring action;
    long long startMs = 0;
    long long durationMs = 0;
    long long fixedSleepMs = 0;
    std::wstring foregroundPreemptMode;
    std::wstring targetLockMode;
    bool targetLockCacheHit = false;
    bool frameCacheHit = false;
    bool frameInvalidatedByAction = false;
    std::wstring priorityChain;
};

struct DeterministicActionBatchOptions {
    std::wstring planJson;
    std::wstring outPath;
    bool dryRun = false;
};

struct DeterministicActionBatchResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    int actionCount = 0;
    int waitConditionCount = 0;
    bool foregroundPreempt = false;
    bool targetLock = false;
    bool globalScreenshot = false;
    bool textInput = false;
    bool verification = false;
    bool outerProcessRoundtripsReduced = true;
    bool dryRun = false;
    bool operationPriorityPolicyEnforced = true;
    bool operationPriorityViolation = false;
    std::wstring operationPriorityFailureCode;
    std::wstring operationPriorityFailureJson;
    bool actionBatchEnabled = false;
    std::wstring profile;
    std::vector<DeterministicBatchTimelineEntry> operationTimeline;
    int foregroundPreemptFullCount = 0;
    int foregroundPreemptCachedValidationCount = 0;
    int targetLockAcquireCount = 0;
    int targetLockCacheHitCount = 0;
    int targetLockReacquireCount = 0;
    int globalFrameNewCount = 0;
    int globalFrameCacheHitCount = 0;
    long long fixedSleepTotalMs = 0;
    int operationGapGt5sCount = 0;
    int silentGapGt5sCount = 0;
    long long longestOperationGapMs = 0;
    bool structuredTextInputFastPathEnabled = false;
    long long optimizedTotalTaskTimeMs = 0;
    double averageClickLatencyMs = 0.0;
    double desktopClickCommonPathMs = 0.0;
    double cachedValidationPathMs = 0.0;
    double globalScreenshotAverageMs = 0.0;
    int mouseMotionRequestedHz = 165;
    double mouseMotionMeasuredAvgHz = 165.0;

    bool vlmAssistEnabled = false;
    std::wstring vlmCapabilityStatus = L"VLM_UNKNOWN";
    std::wstring vlmSessionId;
    bool vlmAssistAttempted = false;
    std::wstring vlmAssistTriggerReason;
    std::wstring vlmAssistStage = L"none";
    std::wstring vlmProvider;
    std::wstring vlmRawResponsePath;
    bool vlmCandidateAccepted = false;
    std::wstring vlmCandidateRejectedReason;
    bool vlmActionExecuted = false;
    bool vlmAfterBackendAttempted = false;
    std::wstring fallbackStageBeforeVlm;
    std::wstring fallbackStageAfterVlm;
};

DeterministicActionBatchResult ExecuteDeterministicActionBatch(const DeterministicActionBatchOptions& options);
std::wstring DeterministicActionBatchJson(const DeterministicActionBatchResult& result);
