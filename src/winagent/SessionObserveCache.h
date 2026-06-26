#pragma once

#include "ObserveController.h"
#include "RuntimeSession.h"

#include <string>

struct SessionObserveCacheLookupResult {
    bool hit = false;
    bool miss = false;
    bool rejected = false;
    std::wstring reason;
    SessionObserveCacheEntry entry;
};

SessionObserveCacheLookupResult SessionObserveCacheLookup(
    RuntimeSession& session,
    long long maxAgeMs,
    bool forceReobserve);
void SessionObserveCacheStore(RuntimeSession& session, const ObserveResult& observe);
void SessionObserveCacheInvalidateAfterAction(RuntimeSession& session);
void SessionObserveCacheInvalidate(RuntimeSession& session, const std::wstring& reason);
