#include "OrchestrationLatencyController.h"

#include <algorithm>

OrchestrationLatencySummary SummarizeOrchestrationLatency(const std::vector<OrchestrationOperationTiming>& operations) {
    OrchestrationLatencySummary summary;
    if (operations.empty()) return summary;
    long long firstStart = operations.front().startMs;
    long long lastEnd = operations.front().endMs;
    long long previousEnd = operations.front().endMs;
    for (size_t i = 0; i < operations.size(); ++i) {
        const auto& operation = operations[i];
        summary.fixedSleepTotalMs += operation.fixedSleepMs;
        lastEnd = std::max(lastEnd, operation.endMs);
        if (i > 0) {
            long long gap = std::max(0LL, operation.startMs - previousEnd);
            summary.longestOperationGapMs = std::max(summary.longestOperationGapMs, gap);
            if (gap > 5000) {
                summary.operationGapGt5sCount++;
                summary.silentGapGt5sCount++;
            }
        }
        previousEnd = operation.endMs;
    }
    summary.totalDurationMs = std::max(0LL, lastEnd - firstStart);
    return summary;
}
