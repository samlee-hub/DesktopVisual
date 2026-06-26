#pragma once

#include "RuntimeSession.h"
#include "Selector.h"

#include <string>

struct SessionLocatorCacheLookupResult {
    bool hit = false;
    bool miss = false;
    bool rejectedStale = false;
    bool forceRelocate = false;
    std::wstring reason;
    SessionLocatorCacheEntry entry;
};

SessionLocatorCacheLookupResult SessionLocatorCacheLookup(
    RuntimeSession& session,
    const std::wstring& locatorKey,
    bool forceRelocate);
void SessionLocatorCacheStore(RuntimeSession& session, const std::wstring& locatorKey, const SelectorResult& located);
void SessionLocatorCacheInvalidate(RuntimeSession& session, const std::wstring& reason);
void SessionLocatorCacheInvalidateAfterAction(RuntimeSession& session);
bool SessionLocatorCacheRejectStale(const RuntimeSession& session, const SessionLocatorCacheEntry& entry, std::wstring& reason);
