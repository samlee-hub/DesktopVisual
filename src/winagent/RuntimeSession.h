#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct RuntimeBounds {
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
};

struct SessionLatencySummary {
    long long totalSequenceMs = 0;
    long long averageStepMs = 0;
    long long p50StepMs = 0;
    long long p95StepMs = 0;
    int processRestartCount = 0;
    bool sessionReuseEnabled = true;
    int cacheHitCount = 0;
    int cacheMissCount = 0;
    std::wstring slowestStep;
    std::wstring slowestStepReason;
};

struct SessionCacheSummary {
    int observeCacheHitCount = 0;
    int observeCacheMissCount = 0;
    int locatorCacheHitCount = 0;
    int locatorCacheMissCount = 0;
    bool actionSinceObserve = false;
};

struct SessionObserveCacheEntry {
    bool hasValue = false;
    std::wstring observeId;
    std::wstring sessionId;
    std::wstring hwnd;
    long long timestampEpochMs = 0;
    std::wstring windowTitle;
    std::wstring windowProcess;
    RuntimeBounds windowBounds;
    std::wstring screenshotPath;
    std::wstring screenshotRef;
    std::wstring uiaTextSummary;
    std::wstring ocrTextSummary;
    std::wstring visibleTextHash;
    int elementCount = 0;
    long long cacheAgeMs = 0;
    bool actionSinceObserve = false;
    bool isFresh = false;
};

struct SessionLocatorCacheEntry {
    bool hasValue = false;
    std::wstring locatorKey;
    std::wstring targetName;
    std::wstring targetRole;
    std::wstring targetText;
    RuntimeBounds targetRect;
    int targetCenterX = 0;
    int targetCenterY = 0;
    std::wstring locatorSource;
    double locatorConfidence = 0.0;
    std::wstring observeId;
    long long createdAtEpochMs = 0;
    long long lastUsedAtEpochMs = 0;
    long long cacheAgeMs = 0;
    std::wstring validUntilActionId;
    bool insideViewport = true;
    bool staleCheckPassed = false;
};

struct RuntimeSession {
    std::wstring sessionId;
    std::wstring sessionCreatedAt;
    std::wstring sessionLastActiveAt;
    long long sessionCreatedAtEpochMs = 0;
    long long sessionLastActiveAtEpochMs = 0;
    bool sessionAlive = false;
    int sessionCommandCount = 0;
    bool sessionClosed = false;
    std::wstring targetHwnd;
    unsigned long long targetHwndValue = 0;
    DWORD targetProcess = 0;
    std::wstring targetProcessName;
    std::wstring targetTitle;
    RuntimeBounds targetBounds;
    std::wstring requestedTitle;
    std::wstring requestedProcess;
    std::wstring lastObserveId;
    std::wstring lastActionId;
    std::wstring lastErrorCode;
    int actionCounter = 0;
    SessionLatencySummary latencySummary;
    SessionCacheSummary cacheSummary;
    SessionObserveCacheEntry observeCache;
    std::vector<SessionLocatorCacheEntry> locatorCache;
};

long long RuntimeSessionNowEpochMs();
std::wstring RuntimeSessionGenerateId();
std::wstring RuntimeBoundsJson(const RuntimeBounds& bounds);
RuntimeBounds RuntimeBoundsFromRect(const RECT& rect);
RECT RuntimeBoundsToRect(const RuntimeBounds& bounds);
std::wstring RuntimeSessionStatus(const RuntimeSession& session);
std::wstring RuntimeSessionJson(const RuntimeSession& session);
std::wstring SessionObserveCacheJson(const SessionObserveCacheEntry& entry);
std::wstring SessionLocatorCacheJson(const SessionLocatorCacheEntry& entry);
std::wstring SessionCacheSummaryJson(const SessionCacheSummary& summary);
std::wstring SessionLatencySummaryJson(const SessionLatencySummary& summary);
std::wstring RuntimeSessionSerialize(const RuntimeSession& session);
bool RuntimeSessionDeserialize(const std::wstring& json, RuntimeSession& session);
