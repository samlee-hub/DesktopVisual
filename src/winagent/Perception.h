#pragma once

#include "WindowFinder.h"

#include <string>
#include <vector>

struct ProviderStatus {
    std::wstring name;
    std::wstring status;
    std::wstring sourceVersion;
    bool configured = false;
    long long latencyMs = 0;
    std::wstring errorCode;
    std::wstring message;
    std::wstring attributesJson;
};

struct VisualElementCandidate {
    std::wstring id;
    std::wstring source;
    std::wstring sourceVersion;
    std::wstring label;
    std::wstring role;
    std::wstring text;
    RECT rect = {};
    std::wstring coordinateSpace;
    double confidence = 0.0;
    std::wstring attributesJson;
    std::wstring artifactPath;
    long long providerLatencyMs = 0;
    std::wstring semanticStatus;
    std::wstring fusionStatus;
    std::wstring riskStatus;
};

struct ProviderResult {
    ProviderStatus status;
    std::vector<VisualElementCandidate> candidates;
    std::vector<std::wstring> warnings;
};

struct Observe2Options {
    std::wstring title;
    std::wstring process;
    bool includeScreenshot = false;
    bool includeUia = true;
    int maxElements = 50;
    std::wstring imageTemplatePath;
    int imageTolerance = 0;
};

struct Observe2Result {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    WindowInfo target;
    std::wstring dataJson;
};

struct ObserveLoopOptions {
    std::wstring title;
    std::wstring process;
    int intervalMs = 250;
    int maxDurationMs = 5000;
    int maxEvents = 20;
    int maxNoChangeRounds = 10;
    int debounceMs = 300;
    bool hasRoi = false;
    RECT roi = {};
    bool changedRegionsOnly = false;
    std::wstring eventsPath;
    std::wstring reportPath;
    std::wstring stopFilePath;
};

struct ObserveLoopResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    WindowInfo target;
    std::wstring dataJson;
    int eventCount = 0;
    int loopCount = 0;
    int noChangeRounds = 0;
    long long durationMs = 0;
};

Observe2Result Observe2(const Observe2Options& options);
ObserveLoopResult ObserveLoop(const ObserveLoopOptions& options);
std::wstring ProviderRegistryJson(bool includeUia, const std::wstring& imageTemplatePath);
bool IsUnresolvedVisualSelector(const std::wstring& selector);
