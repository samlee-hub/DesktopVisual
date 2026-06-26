#include "SessionLocatorCache.h"

#include "Trace.h"
#include "WindowFinder.h"

#include <windows.h>

namespace {

bool RectInsideWindow(const RuntimeBounds& rect, HWND hwnd) {
    RECT client = {};
    if (!GetClientRect(hwnd, &client)) return false;
    POINT topLeft{rect.left, rect.top};
    POINT bottomRight{rect.right, rect.bottom};
    if (!ScreenToClient(hwnd, &topLeft) || !ScreenToClient(hwnd, &bottomRight)) {
        return false;
    }
    return topLeft.x >= client.left &&
           topLeft.y >= client.top &&
           bottomRight.x <= client.right &&
           bottomRight.y <= client.bottom &&
           bottomRight.x >= topLeft.x &&
           bottomRight.y >= topLeft.y;
}

SessionLocatorCacheEntry* FindEntry(RuntimeSession& session, const std::wstring& locatorKey) {
    for (auto& entry : session.locatorCache) {
        if (entry.hasValue && entry.locatorKey == locatorKey) {
            return &entry;
        }
    }
    return nullptr;
}

}  // namespace

bool SessionLocatorCacheRejectStale(const RuntimeSession& session, const SessionLocatorCacheEntry& entry, std::wstring& reason) {
    HWND hwnd = reinterpret_cast<HWND>(session.targetHwndValue);
    if (!hwnd || !IsWindow(hwnd)) {
        reason = L"window_closed";
        return true;
    }
    if (entry.validUntilActionId != session.lastActionId) {
        reason = L"action_advanced_since_locator";
        return true;
    }
    if (!entry.insideViewport || !RectInsideWindow(entry.targetRect, hwnd)) {
        reason = L"target_outside_viewport";
        return true;
    }
    return false;
}

SessionLocatorCacheLookupResult SessionLocatorCacheLookup(
    RuntimeSession& session,
    const std::wstring& locatorKey,
    bool forceRelocate) {
    SessionLocatorCacheLookupResult result;
    result.forceRelocate = forceRelocate;
    if (forceRelocate) {
        result.miss = true;
        result.reason = L"force_relocate";
        session.cacheSummary.locatorCacheMissCount++;
        return result;
    }
    SessionLocatorCacheEntry* entry = FindEntry(session, locatorKey);
    if (!entry) {
        result.miss = true;
        result.reason = L"empty";
        session.cacheSummary.locatorCacheMissCount++;
        return result;
    }
    std::wstring staleReason;
    if (SessionLocatorCacheRejectStale(session, *entry, staleReason)) {
        result.rejectedStale = true;
        result.miss = true;
        result.reason = staleReason;
        session.cacheSummary.locatorCacheMissCount++;
        return result;
    }
    entry->lastUsedAtEpochMs = RuntimeSessionNowEpochMs();
    entry->cacheAgeMs = entry->lastUsedAtEpochMs - entry->createdAtEpochMs;
    entry->staleCheckPassed = true;
    result.hit = true;
    result.reason = L"fresh";
    result.entry = *entry;
    session.cacheSummary.locatorCacheHitCount++;
    return result;
}

void SessionLocatorCacheStore(RuntimeSession& session, const std::wstring& locatorKey, const SelectorResult& located) {
    SessionLocatorCacheEntry entry;
    entry.hasValue = true;
    entry.locatorKey = locatorKey;
    entry.targetName = located.elementName;
    entry.targetRole = located.elementControlType;
    entry.targetText = located.matchedText;
    entry.targetRect = RuntimeBoundsFromRect(located.rect);
    entry.targetCenterX = located.clientX;
    entry.targetCenterY = located.clientY;
    entry.locatorSource = located.source.empty() ? located.locateMethod : located.source;
    entry.locatorConfidence = located.confidence;
    entry.observeId = session.lastObserveId;
    entry.createdAtEpochMs = RuntimeSessionNowEpochMs();
    entry.lastUsedAtEpochMs = entry.createdAtEpochMs;
    entry.cacheAgeMs = 0;
    entry.validUntilActionId = session.lastActionId;
    entry.insideViewport = true;
    entry.staleCheckPassed = true;

    SessionLocatorCacheEntry* existing = FindEntry(session, locatorKey);
    if (existing) {
        *existing = entry;
    } else {
        session.locatorCache.push_back(entry);
    }
}

void SessionLocatorCacheInvalidate(RuntimeSession& session, const std::wstring& reason) {
    for (auto& entry : session.locatorCache) {
        entry.staleCheckPassed = false;
        entry.validUntilActionId = L"invalidated:" + reason;
    }
}

void SessionLocatorCacheInvalidateAfterAction(RuntimeSession& session) {
    SessionLocatorCacheInvalidate(session, L"action");
}
