#pragma once

#include "RuntimeSession.h"

#include <string>
#include <vector>

struct RuntimeStepLatency {
    std::wstring stepId;
    std::wstring action;
    long long runtimeProcessStartMs = 0;
    long long sessionStartMs = 0;
    long long sessionAttachMs = 0;
    long long observeMs = 0;
    long long cacheLookupMs = 0;
    long long locateMs = 0;
    long long mouseMoveMs = 0;
    long long clickMs = 0;
    long long typeMs = 0;
    long long scrollMs = 0;
    long long verifyMs = 0;
    long long reobserveMs = 0;
    long long totalStepMs = 0;
    long long totalSequenceMs = 0;
    int processRestartCount = 0;
    bool sessionReuseEnabled = true;
    bool observeCacheHit = false;
    bool observeCacheMiss = false;
    bool locatorCacheHit = false;
    bool locatorCacheMiss = false;
};

class LatencySequenceTracker {
public:
    void Start();
    RuntimeStepLatency NewStep(const std::wstring& stepId, const std::wstring& action) const;
    void FinishStep(RuntimeStepLatency& latency, unsigned long long stepStartTick);
    void AddStep(const RuntimeStepLatency& latency);
    SessionLatencySummary Summary(int processRestartCount, bool sessionReuseEnabled) const;
    std::wstring StepsJson() const;
    std::wstring SummaryJson(int processRestartCount, bool sessionReuseEnabled) const;

private:
    unsigned long long sequenceStartTick_ = 0;
    std::vector<RuntimeStepLatency> steps_;
};

std::wstring RuntimeStepLatencyJson(const RuntimeStepLatency& latency);
