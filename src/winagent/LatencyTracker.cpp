#include "LatencyTracker.h"

#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <sstream>

namespace {

long long TickElapsed(unsigned long long start) {
    return static_cast<long long>(GetTickCount64() - start);
}

long long Percentile(std::vector<long long> values, double percentile) {
    if (values.empty()) return 0;
    std::sort(values.begin(), values.end());
    if (values.size() == 1) return values.front();
    double rank = percentile * static_cast<double>(values.size() - 1);
    size_t index = static_cast<size_t>(rank + 0.5);
    if (index >= values.size()) index = values.size() - 1;
    return values[index];
}

}  // namespace

void LatencySequenceTracker::Start() {
    sequenceStartTick_ = GetTickCount64();
    steps_.clear();
}

RuntimeStepLatency LatencySequenceTracker::NewStep(const std::wstring& stepId, const std::wstring& action) const {
    RuntimeStepLatency latency;
    latency.stepId = stepId;
    latency.action = action;
    latency.sessionReuseEnabled = true;
    return latency;
}

void LatencySequenceTracker::FinishStep(RuntimeStepLatency& latency, unsigned long long stepStartTick) {
    latency.totalStepMs = TickElapsed(stepStartTick);
    latency.totalSequenceMs = sequenceStartTick_ == 0 ? latency.totalStepMs : TickElapsed(sequenceStartTick_);
}

void LatencySequenceTracker::AddStep(const RuntimeStepLatency& latency) {
    steps_.push_back(latency);
}

SessionLatencySummary LatencySequenceTracker::Summary(int processRestartCount, bool sessionReuseEnabled) const {
    SessionLatencySummary summary;
    summary.processRestartCount = processRestartCount;
    summary.sessionReuseEnabled = sessionReuseEnabled;
    if (steps_.empty()) {
        return summary;
    }

    std::vector<long long> totals;
    long long total = 0;
    long long slowest = -1;
    for (const auto& step : steps_) {
        totals.push_back(step.totalStepMs);
        total += step.totalStepMs;
        if (step.totalStepMs > slowest) {
            slowest = step.totalStepMs;
            summary.slowestStep = step.stepId.empty() ? step.action : step.stepId;
            summary.slowestStepReason = step.action;
        }
        if (step.observeCacheHit || step.locatorCacheHit) summary.cacheHitCount++;
        if (step.observeCacheMiss || step.locatorCacheMiss) summary.cacheMissCount++;
    }
    summary.totalSequenceMs = steps_.back().totalSequenceMs;
    if (summary.totalSequenceMs <= 0) summary.totalSequenceMs = total;
    summary.averageStepMs = total / static_cast<long long>(steps_.size());
    summary.p50StepMs = Percentile(totals, 0.50);
    summary.p95StepMs = Percentile(totals, 0.95);
    return summary;
}

std::wstring LatencySequenceTracker::StepsJson() const {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < steps_.size(); ++i) {
        if (i) json << L",";
        json << RuntimeStepLatencyJson(steps_[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring LatencySequenceTracker::SummaryJson(int processRestartCount, bool sessionReuseEnabled) const {
    return SessionLatencySummaryJson(Summary(processRestartCount, sessionReuseEnabled));
}

std::wstring RuntimeStepLatencyJson(const RuntimeStepLatency& latency) {
    std::wstringstream json;
    json << L"{\"step_id\":" << JsonString(latency.stepId)
         << L",\"action\":" << JsonString(latency.action)
         << L",\"runtime_process_start_ms\":" << latency.runtimeProcessStartMs
         << L",\"session_start_ms\":" << latency.sessionStartMs
         << L",\"session_attach_ms\":" << latency.sessionAttachMs
         << L",\"observe_ms\":" << latency.observeMs
         << L",\"cache_lookup_ms\":" << latency.cacheLookupMs
         << L",\"locate_ms\":" << latency.locateMs
         << L",\"mouse_move_ms\":" << latency.mouseMoveMs
         << L",\"click_ms\":" << latency.clickMs
         << L",\"type_ms\":" << latency.typeMs
         << L",\"scroll_ms\":" << latency.scrollMs
         << L",\"verify_ms\":" << latency.verifyMs
         << L",\"reobserve_ms\":" << latency.reobserveMs
         << L",\"total_step_ms\":" << latency.totalStepMs
         << L",\"total_sequence_ms\":" << latency.totalSequenceMs
         << L",\"process_restart_count\":" << latency.processRestartCount
         << L",\"session_reuse_enabled\":" << (latency.sessionReuseEnabled ? L"true" : L"false")
         << L",\"observe_cache_hit\":" << (latency.observeCacheHit ? L"true" : L"false")
         << L",\"observe_cache_miss\":" << (latency.observeCacheMiss ? L"true" : L"false")
         << L",\"locator_cache_hit\":" << (latency.locatorCacheHit ? L"true" : L"false")
         << L",\"locator_cache_miss\":" << (latency.locatorCacheMiss ? L"true" : L"false")
         << L"}";
    return json.str();
}
