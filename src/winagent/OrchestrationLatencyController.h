#pragma once

#include <string>
#include <vector>

struct OrchestrationOperationTiming {
    std::wstring operationId;
    std::wstring operationType;
    long long startMs = 0;
    long long endMs = 0;
    long long durationMs = 0;
    long long fixedSleepMs = 0;
};

struct OrchestrationLatencySummary {
    long long totalDurationMs = 0;
    long long fixedSleepTotalMs = 0;
    int operationGapGt5sCount = 0;
    int silentGapGt5sCount = 0;
    long long longestOperationGapMs = 0;
};

OrchestrationLatencySummary SummarizeOrchestrationLatency(const std::vector<OrchestrationOperationTiming>& operations);
