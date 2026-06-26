#pragma once

#include <map>
#include <string>
#include <vector>

struct OperationTimelineEntry {
    std::wstring operationId;
    std::wstring parentTaskId;
    std::wstring operationType;
    std::wstring command;
    std::wstring startTimeUtc;
    std::wstring endTimeUtc;
    long long wallClockMs = 0;
    long long runtimeDurationMs = 0;
    long long orchestrationOverheadMs = 0;
    std::wstring stage;
    int attemptIndex = 0;
    std::wstring attemptMode;
    std::wstring targetTitle;
    std::wstring targetProcess;
    std::wstring foregroundBefore;
    std::wstring foregroundAfter;
    bool usedGlobalScreenshot = false;
    bool usedTargetLock = false;
    bool usedCoordinateMapper = false;
    bool usedForegroundPreempt = false;
    bool usedRealKeyboardInput = false;
    bool usedClipboard = false;
    bool usedBackend = false;
    bool usedShortcut = false;
    long long fixedSleepMs = 0;
    std::wstring waitCondition;
    long long waitConditionMs = 0;
    long long manualViewImageMs = 0;
    long long codexThinkingGapMs = 0;
    long long processStartupOverheadMs = 0;
    std::wstring result;
    std::wstring errorCode;
    std::wstring evidenceRef;
};

std::vector<std::wstring> OperationTimelineRequiredFields();
void FinalizeOperationTimelineEntry(OperationTimelineEntry& entry);
bool IsOperationTimelineExternalOrchestrationDelay(const OperationTimelineEntry& entry);
bool IsOperationTimelineFixedSleepCandidate(const OperationTimelineEntry& entry);
std::wstring OperationTimelineEntryJson(const OperationTimelineEntry& entry);
std::wstring OperationTimelineProfilerSelftestDataJson();
