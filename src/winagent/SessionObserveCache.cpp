#include "SessionObserveCache.h"

#include "SafetyPolicy.h"
#include "Trace.h"
#include "WindowFinder.h"

#include <windows.h>

#include <sstream>

namespace {

bool BoundsEqual(const RuntimeBounds& left, const RuntimeBounds& right) {
    return left.left == right.left &&
           left.top == right.top &&
           left.right == right.right &&
           left.bottom == right.bottom;
}

std::wstring HashVisibleText(const ObserveResult& observe) {
    std::wstring seed = observe.target.title + L"|" + ProcessNameForPid(observe.target.pid) + L"|" + std::to_wstring(observe.uiaElementCount);
    unsigned long long hash = 1469598103934665603ULL;
    for (wchar_t ch : seed) {
        hash ^= static_cast<unsigned long long>(ch);
        hash *= 1099511628211ULL;
    }
    std::wstringstream stream;
    stream << std::hex << hash;
    return stream.str();
}

WindowInfo CurrentWindowForSession(const RuntimeSession& session) {
    WindowInfo info;
    HWND hwnd = reinterpret_cast<HWND>(session.targetHwndValue);
    if (!hwnd || !IsWindow(hwnd)) {
        return info;
    }
    info.hwnd = hwnd;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    int length = GetWindowTextLengthW(hwnd);
    if (length > 0) {
        std::wstring title(static_cast<size_t>(length) + 1, L'\0');
        int copied = GetWindowTextW(hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
        info.title = title;
    }
    return info;
}

}  // namespace

SessionObserveCacheLookupResult SessionObserveCacheLookup(
    RuntimeSession& session,
    long long maxAgeMs,
    bool forceReobserve) {
    SessionObserveCacheLookupResult result;
    if (forceReobserve) {
        result.miss = true;
        result.reason = L"force_reobserve";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }
    if (!session.observeCache.hasValue) {
        result.miss = true;
        result.reason = L"empty";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }
    if (session.observeCache.actionSinceObserve || session.cacheSummary.actionSinceObserve) {
        result.rejected = true;
        result.miss = true;
        result.reason = L"action_since_observe";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }
    long long now = RuntimeSessionNowEpochMs();
    long long age = now - session.observeCache.timestampEpochMs;
    if (maxAgeMs > 0 && age > maxAgeMs) {
        result.rejected = true;
        result.miss = true;
        result.reason = L"cache_age_exceeded";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }
    WindowInfo current = CurrentWindowForSession(session);
    if (!current.hwnd || FormatHwnd(current.hwnd) != session.observeCache.hwnd) {
        result.rejected = true;
        result.miss = true;
        result.reason = L"window_closed_or_hwnd_changed";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }
    if (current.title != session.observeCache.windowTitle ||
        ProcessNameForPid(current.pid) != session.observeCache.windowProcess ||
        !BoundsEqual(RuntimeBoundsFromRect(current.rect), session.observeCache.windowBounds)) {
        result.rejected = true;
        result.miss = true;
        result.reason = L"window_changed";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }
    if (GetForegroundWindow() != current.hwnd) {
        result.rejected = true;
        result.miss = true;
        result.reason = L"foreground_changed";
        session.cacheSummary.observeCacheMissCount++;
        return result;
    }

    session.observeCache.cacheAgeMs = age;
    session.observeCache.isFresh = true;
    result.hit = true;
    result.entry = session.observeCache;
    result.entry.cacheAgeMs = age;
    result.entry.isFresh = true;
    result.reason = L"fresh";
    session.cacheSummary.observeCacheHitCount++;
    return result;
}

void SessionObserveCacheStore(RuntimeSession& session, const ObserveResult& observe) {
    SessionObserveCacheEntry entry;
    entry.hasValue = true;
    entry.observeId = L"obs-" + std::to_wstring(RuntimeSessionNowEpochMs()) + L"-" + std::to_wstring(session.sessionCommandCount);
    entry.sessionId = session.sessionId;
    entry.hwnd = FormatHwnd(observe.target.hwnd);
    entry.timestampEpochMs = RuntimeSessionNowEpochMs();
    entry.windowTitle = observe.target.title;
    entry.windowProcess = ProcessNameForPid(observe.target.pid);
    entry.windowBounds = RuntimeBoundsFromRect(observe.target.rect);
    entry.screenshotPath = observe.screenshotPath;
    entry.screenshotRef = observe.screenshotPath;
    entry.uiaTextSummary = L"uia_element_count=" + std::to_wstring(observe.uiaElementCount);
    entry.ocrTextSummary = L"";
    entry.visibleTextHash = HashVisibleText(observe);
    entry.elementCount = observe.uiaElementCount;
    entry.cacheAgeMs = 0;
    entry.actionSinceObserve = false;
    entry.isFresh = true;
    session.observeCache = entry;
    session.lastObserveId = entry.observeId;
    session.cacheSummary.actionSinceObserve = false;
}

void SessionObserveCacheInvalidateAfterAction(RuntimeSession& session) {
    if (session.observeCache.hasValue) {
        session.observeCache.actionSinceObserve = true;
        session.observeCache.isFresh = false;
    }
    session.cacheSummary.actionSinceObserve = true;
}

void SessionObserveCacheInvalidate(RuntimeSession& session, const std::wstring& reason) {
    if (session.observeCache.hasValue) {
        session.observeCache.actionSinceObserve = true;
        session.observeCache.isFresh = false;
        session.observeCache.uiaTextSummary += L"; invalidated=" + reason;
    }
    session.cacheSummary.actionSinceObserve = true;
}
