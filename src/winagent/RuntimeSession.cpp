#include "RuntimeSession.h"

#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring Trim(std::wstring value) {
    auto first = std::find_if_not(value.begin(), value.end(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    });
    auto last = std::find_if_not(value.rbegin(), value.rend(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    }).base();
    if (first >= last) return L"";
    return std::wstring(first, last);
}

bool FindJsonKey(const std::wstring& json, const std::wstring& key, size_t& colon) {
    const std::wstring quoted = L"\"" + key + L"\"";
    size_t pos = json.find(quoted);
    if (pos == std::wstring::npos) return false;
    colon = json.find(L":", pos + quoted.size());
    return colon != std::wstring::npos;
}

std::wstring UnescapeJsonString(const std::wstring& value) {
    std::wstring result;
    bool escaped = false;
    for (wchar_t ch : value) {
        if (!escaped) {
            if (ch == L'\\') {
                escaped = true;
            } else {
                result += ch;
            }
            continue;
        }
        switch (ch) {
            case L'n': result += L'\n'; break;
            case L'r': result += L'\r'; break;
            case L't': result += L'\t'; break;
            case L'"': result += L'"'; break;
            case L'\\': result += L'\\'; break;
            default: result += ch; break;
        }
        escaped = false;
    }
    if (escaped) result += L'\\';
    return result;
}

bool FindJsonString(const std::wstring& json, const std::wstring& key, std::wstring& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t quote = json.find(L"\"", colon + 1);
    if (quote == std::wstring::npos) return false;
    std::wstring raw;
    bool escaped = false;
    for (size_t i = quote + 1; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (!escaped && ch == L'"') {
            value = UnescapeJsonString(raw);
            return true;
        }
        if (!escaped && ch == L'\\') {
            escaped = true;
            raw += ch;
        } else {
            escaped = false;
            raw += ch;
        }
    }
    return false;
}

bool FindJsonBool(const std::wstring& json, const std::wstring& key, bool& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t pos = colon + 1;
    while (pos < json.size() && std::iswspace(json[pos]) != 0) ++pos;
    if (json.compare(pos, 4, L"true") == 0) {
        value = true;
        return true;
    }
    if (json.compare(pos, 5, L"false") == 0) {
        value = false;
        return true;
    }
    return false;
}

bool FindJsonNumberToken(const std::wstring& json, const std::wstring& key, std::wstring& token) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t pos = colon + 1;
    while (pos < json.size() && std::iswspace(json[pos]) != 0) ++pos;
    size_t start = pos;
    while (pos < json.size()) {
        wchar_t ch = json[pos];
        if ((ch >= L'0' && ch <= L'9') || ch == L'-' || ch == L'+' || ch == L'.') {
            ++pos;
            continue;
        }
        break;
    }
    if (pos == start) return false;
    token = json.substr(start, pos - start);
    return true;
}

bool FindJsonInt(const std::wstring& json, const std::wstring& key, int& value) {
    std::wstring token;
    if (!FindJsonNumberToken(json, key, token)) return false;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(token, &consumed, 10);
        if (consumed != token.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

bool FindJsonLongLong(const std::wstring& json, const std::wstring& key, long long& value) {
    std::wstring token;
    if (!FindJsonNumberToken(json, key, token)) return false;
    try {
        size_t consumed = 0;
        long long parsed = std::stoll(token, &consumed, 10);
        if (consumed != token.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

bool FindJsonUnsignedLongLong(const std::wstring& json, const std::wstring& key, unsigned long long& value) {
    std::wstring token;
    if (!FindJsonNumberToken(json, key, token)) return false;
    try {
        size_t consumed = 0;
        unsigned long long parsed = std::stoull(token, &consumed, 10);
        if (consumed != token.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

bool FindJsonDouble(const std::wstring& json, const std::wstring& key, double& value) {
    std::wstring token;
    if (!FindJsonNumberToken(json, key, token)) return false;
    try {
        size_t consumed = 0;
        double parsed = std::stod(token, &consumed);
        if (consumed != token.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

bool ExtractJsonSection(
    const std::wstring& json,
    const std::wstring& key,
    wchar_t openChar,
    wchar_t closeChar,
    std::wstring& section) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t open = json.find(openChar, colon + 1);
    if (open == std::wstring::npos) return false;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (size_t i = open; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                inString = false;
            }
            continue;
        }
        if (ch == L'"') {
            inString = true;
            continue;
        }
        if (ch == openChar) {
            ++depth;
        } else if (ch == closeChar) {
            --depth;
            if (depth == 0) {
                section = json.substr(open, i - open + 1);
                return true;
            }
        }
    }
    return false;
}

std::vector<std::wstring> SplitTopLevelObjects(const std::wstring& arrayJson) {
    std::vector<std::wstring> objects;
    bool inString = false;
    bool escaped = false;
    int depth = 0;
    size_t start = std::wstring::npos;
    for (size_t i = 0; i < arrayJson.size(); ++i) {
        wchar_t ch = arrayJson[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                inString = false;
            }
            continue;
        }
        if (ch == L'"') {
            inString = true;
            continue;
        }
        if (ch == L'{') {
            if (depth == 0) start = i;
            ++depth;
        } else if (ch == L'}') {
            --depth;
            if (depth == 0 && start != std::wstring::npos) {
                objects.push_back(arrayJson.substr(start, i - start + 1));
                start = std::wstring::npos;
            }
        }
    }
    return objects;
}

RuntimeBounds ParseBoundsObject(const std::wstring& json) {
    RuntimeBounds bounds;
    FindJsonInt(json, L"left", bounds.left);
    FindJsonInt(json, L"top", bounds.top);
    FindJsonInt(json, L"right", bounds.right);
    FindJsonInt(json, L"bottom", bounds.bottom);
    return bounds;
}

SessionObserveCacheEntry ParseObserveCache(const std::wstring& json) {
    SessionObserveCacheEntry entry;
    FindJsonBool(json, L"has_value", entry.hasValue);
    FindJsonString(json, L"observe_id", entry.observeId);
    FindJsonString(json, L"session_id", entry.sessionId);
    FindJsonString(json, L"hwnd", entry.hwnd);
    FindJsonLongLong(json, L"timestamp_epoch_ms", entry.timestampEpochMs);
    FindJsonString(json, L"window_title", entry.windowTitle);
    FindJsonString(json, L"window_process", entry.windowProcess);
    std::wstring boundsJson;
    if (ExtractJsonSection(json, L"window_bounds", L'{', L'}', boundsJson)) {
        entry.windowBounds = ParseBoundsObject(boundsJson);
    }
    FindJsonString(json, L"screenshot_path", entry.screenshotPath);
    FindJsonString(json, L"screenshot_ref", entry.screenshotRef);
    FindJsonString(json, L"uia_text_summary", entry.uiaTextSummary);
    FindJsonString(json, L"ocr_text_summary", entry.ocrTextSummary);
    FindJsonString(json, L"visible_text_hash", entry.visibleTextHash);
    FindJsonInt(json, L"element_count", entry.elementCount);
    FindJsonLongLong(json, L"cache_age_ms", entry.cacheAgeMs);
    FindJsonBool(json, L"action_since_observe", entry.actionSinceObserve);
    FindJsonBool(json, L"is_fresh", entry.isFresh);
    return entry;
}

SessionLocatorCacheEntry ParseLocatorCache(const std::wstring& json) {
    SessionLocatorCacheEntry entry;
    FindJsonBool(json, L"has_value", entry.hasValue);
    FindJsonString(json, L"locator_key", entry.locatorKey);
    FindJsonString(json, L"target_name", entry.targetName);
    FindJsonString(json, L"target_role", entry.targetRole);
    FindJsonString(json, L"target_text", entry.targetText);
    std::wstring rectJson;
    if (ExtractJsonSection(json, L"target_rect", L'{', L'}', rectJson)) {
        entry.targetRect = ParseBoundsObject(rectJson);
    }
    FindJsonInt(json, L"target_center_x", entry.targetCenterX);
    FindJsonInt(json, L"target_center_y", entry.targetCenterY);
    FindJsonString(json, L"locator_source", entry.locatorSource);
    FindJsonDouble(json, L"locator_confidence", entry.locatorConfidence);
    FindJsonString(json, L"observe_id", entry.observeId);
    FindJsonLongLong(json, L"created_at_epoch_ms", entry.createdAtEpochMs);
    FindJsonLongLong(json, L"last_used_at_epoch_ms", entry.lastUsedAtEpochMs);
    FindJsonLongLong(json, L"cache_age_ms", entry.cacheAgeMs);
    FindJsonString(json, L"valid_until_action_id", entry.validUntilActionId);
    FindJsonBool(json, L"inside_viewport", entry.insideViewport);
    FindJsonBool(json, L"stale_check_passed", entry.staleCheckPassed);
    return entry;
}

}  // namespace

long long RuntimeSessionNowEpochMs() {
    FILETIME ft = {};
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER uli = {};
    uli.LowPart = ft.dwLowDateTime;
    uli.HighPart = ft.dwHighDateTime;
    return static_cast<long long>((uli.QuadPart - 116444736000000000ULL) / 10000ULL);
}

std::wstring RuntimeSessionGenerateId() {
    SYSTEMTIME time = {};
    GetLocalTime(&time);
    wchar_t buffer[128] = {};
    swprintf_s(
        buffer,
        L"rs-%04u%02u%02u%02u%02u%02u%03u-%lu",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds,
        GetCurrentProcessId());
    return buffer;
}

std::wstring RuntimeBoundsJson(const RuntimeBounds& bounds) {
    std::wstringstream json;
    json << L"{\"left\":" << bounds.left
         << L",\"top\":" << bounds.top
         << L",\"right\":" << bounds.right
         << L",\"bottom\":" << bounds.bottom << L"}";
    return json.str();
}

RuntimeBounds RuntimeBoundsFromRect(const RECT& rect) {
    RuntimeBounds bounds;
    bounds.left = rect.left;
    bounds.top = rect.top;
    bounds.right = rect.right;
    bounds.bottom = rect.bottom;
    return bounds;
}

RECT RuntimeBoundsToRect(const RuntimeBounds& bounds) {
    RECT rect{bounds.left, bounds.top, bounds.right, bounds.bottom};
    return rect;
}

std::wstring RuntimeSessionStatus(const RuntimeSession& session) {
    if (session.sessionClosed) return L"closed";
    if (!session.sessionAlive) return L"expired";
    return L"alive";
}

std::wstring SessionLatencySummaryJson(const SessionLatencySummary& summary) {
    std::wstringstream json;
    json << L"{\"total_sequence_ms\":" << summary.totalSequenceMs
         << L",\"average_step_ms\":" << summary.averageStepMs
         << L",\"p50_step_ms\":" << summary.p50StepMs
         << L",\"p95_step_ms\":" << summary.p95StepMs
         << L",\"process_restart_count\":" << summary.processRestartCount
         << L",\"session_reuse_enabled\":" << (summary.sessionReuseEnabled ? L"true" : L"false")
         << L",\"cache_hit_count\":" << summary.cacheHitCount
         << L",\"cache_miss_count\":" << summary.cacheMissCount
         << L",\"slowest_step\":" << JsonString(summary.slowestStep)
         << L",\"slowest_step_reason\":" << JsonString(summary.slowestStepReason)
         << L"}";
    return json.str();
}

std::wstring SessionCacheSummaryJson(const SessionCacheSummary& summary) {
    std::wstringstream json;
    json << L"{\"observe_cache_hit_count\":" << summary.observeCacheHitCount
         << L",\"observe_cache_miss_count\":" << summary.observeCacheMissCount
         << L",\"locator_cache_hit_count\":" << summary.locatorCacheHitCount
         << L",\"locator_cache_miss_count\":" << summary.locatorCacheMissCount
         << L",\"action_since_observe\":" << (summary.actionSinceObserve ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring SessionObserveCacheJson(const SessionObserveCacheEntry& entry) {
    std::wstringstream json;
    json << L"{\"has_value\":" << (entry.hasValue ? L"true" : L"false")
         << L",\"observe_id\":" << JsonString(entry.observeId)
         << L",\"session_id\":" << JsonString(entry.sessionId)
         << L",\"hwnd\":" << JsonString(entry.hwnd)
         << L",\"timestamp_epoch_ms\":" << entry.timestampEpochMs
         << L",\"window_title\":" << JsonString(entry.windowTitle)
         << L",\"window_process\":" << JsonString(entry.windowProcess)
         << L",\"window_bounds\":" << RuntimeBoundsJson(entry.windowBounds)
         << L",\"screenshot_path\":" << JsonString(entry.screenshotPath)
         << L",\"screenshot_ref\":" << JsonString(entry.screenshotRef)
         << L",\"uia_text_summary\":" << JsonString(entry.uiaTextSummary)
         << L",\"ocr_text_summary\":" << JsonString(entry.ocrTextSummary)
         << L",\"visible_text_hash\":" << JsonString(entry.visibleTextHash)
         << L",\"element_count\":" << entry.elementCount
         << L",\"cache_age_ms\":" << entry.cacheAgeMs
         << L",\"action_since_observe\":" << (entry.actionSinceObserve ? L"true" : L"false")
         << L",\"is_fresh\":" << (entry.isFresh ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring SessionLocatorCacheJson(const SessionLocatorCacheEntry& entry) {
    std::wstringstream json;
    json << L"{\"has_value\":" << (entry.hasValue ? L"true" : L"false")
         << L",\"locator_key\":" << JsonString(entry.locatorKey)
         << L",\"target_name\":" << JsonString(entry.targetName)
         << L",\"target_role\":" << JsonString(entry.targetRole)
         << L",\"target_text\":" << JsonString(entry.targetText)
         << L",\"target_rect\":" << RuntimeBoundsJson(entry.targetRect)
         << L",\"target_center_x\":" << entry.targetCenterX
         << L",\"target_center_y\":" << entry.targetCenterY
         << L",\"locator_source\":" << JsonString(entry.locatorSource)
         << L",\"locator_confidence\":" << entry.locatorConfidence
         << L",\"observe_id\":" << JsonString(entry.observeId)
         << L",\"created_at_epoch_ms\":" << entry.createdAtEpochMs
         << L",\"last_used_at_epoch_ms\":" << entry.lastUsedAtEpochMs
         << L",\"cache_age_ms\":" << entry.cacheAgeMs
         << L",\"valid_until_action_id\":" << JsonString(entry.validUntilActionId)
         << L",\"inside_viewport\":" << (entry.insideViewport ? L"true" : L"false")
         << L",\"stale_check_passed\":" << (entry.staleCheckPassed ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring RuntimeSessionJson(const RuntimeSession& session) {
    std::wstringstream locators;
    locators << L"[";
    for (size_t i = 0; i < session.locatorCache.size(); ++i) {
        if (i) locators << L",";
        locators << SessionLocatorCacheJson(session.locatorCache[i]);
    }
    locators << L"]";

    std::wstringstream json;
    json << L"{\"session_id\":" << JsonString(session.sessionId)
         << L",\"session_created_at\":" << JsonString(session.sessionCreatedAt)
         << L",\"session_last_active_at\":" << JsonString(session.sessionLastActiveAt)
         << L",\"session_created_at_epoch_ms\":" << session.sessionCreatedAtEpochMs
         << L",\"session_last_active_at_epoch_ms\":" << session.sessionLastActiveAtEpochMs
         << L",\"session_alive\":" << (session.sessionAlive ? L"true" : L"false")
         << L",\"session_command_count\":" << session.sessionCommandCount
         << L",\"session_closed\":" << (session.sessionClosed ? L"true" : L"false")
         << L",\"session_status\":" << JsonString(RuntimeSessionStatus(session))
         << L",\"target_hwnd\":" << JsonString(session.targetHwnd)
         << L",\"target_hwnd_value\":" << session.targetHwndValue
         << L",\"target_process\":" << session.targetProcess
         << L",\"target_process_name\":" << JsonString(session.targetProcessName)
         << L",\"target_title\":" << JsonString(session.targetTitle)
         << L",\"target_bounds\":" << RuntimeBoundsJson(session.targetBounds)
         << L",\"requested_title\":" << JsonString(session.requestedTitle)
         << L",\"requested_process\":" << JsonString(session.requestedProcess)
         << L",\"last_observe_id\":" << JsonString(session.lastObserveId)
         << L",\"last_action_id\":" << JsonString(session.lastActionId)
         << L",\"last_error_code\":" << JsonString(session.lastErrorCode)
         << L",\"action_counter\":" << session.actionCounter
         << L",\"latency_summary\":" << SessionLatencySummaryJson(session.latencySummary)
         << L",\"cache_summary\":" << SessionCacheSummaryJson(session.cacheSummary)
         << L",\"observe_cache\":" << SessionObserveCacheJson(session.observeCache)
         << L",\"locator_cache\":" << locators.str()
         << L"}";
    return json.str();
}

std::wstring RuntimeSessionSerialize(const RuntimeSession& session) {
    return RuntimeSessionJson(session);
}

bool RuntimeSessionDeserialize(const std::wstring& json, RuntimeSession& session) {
    std::wstring trimmed = Trim(json);
    if (trimmed.empty()) return false;
    FindJsonString(trimmed, L"session_id", session.sessionId);
    FindJsonString(trimmed, L"session_created_at", session.sessionCreatedAt);
    FindJsonString(trimmed, L"session_last_active_at", session.sessionLastActiveAt);
    FindJsonLongLong(trimmed, L"session_created_at_epoch_ms", session.sessionCreatedAtEpochMs);
    FindJsonLongLong(trimmed, L"session_last_active_at_epoch_ms", session.sessionLastActiveAtEpochMs);
    FindJsonBool(trimmed, L"session_alive", session.sessionAlive);
    FindJsonInt(trimmed, L"session_command_count", session.sessionCommandCount);
    FindJsonBool(trimmed, L"session_closed", session.sessionClosed);
    FindJsonString(trimmed, L"target_hwnd", session.targetHwnd);
    FindJsonUnsignedLongLong(trimmed, L"target_hwnd_value", session.targetHwndValue);
    int pid = 0;
    if (FindJsonInt(trimmed, L"target_process", pid)) session.targetProcess = static_cast<DWORD>(pid);
    FindJsonString(trimmed, L"target_process_name", session.targetProcessName);
    FindJsonString(trimmed, L"target_title", session.targetTitle);
    std::wstring boundsJson;
    if (ExtractJsonSection(trimmed, L"target_bounds", L'{', L'}', boundsJson)) {
        session.targetBounds = ParseBoundsObject(boundsJson);
    }
    FindJsonString(trimmed, L"requested_title", session.requestedTitle);
    FindJsonString(trimmed, L"requested_process", session.requestedProcess);
    FindJsonString(trimmed, L"last_observe_id", session.lastObserveId);
    FindJsonString(trimmed, L"last_action_id", session.lastActionId);
    FindJsonString(trimmed, L"last_error_code", session.lastErrorCode);
    FindJsonInt(trimmed, L"action_counter", session.actionCounter);

    std::wstring latencyJson;
    if (ExtractJsonSection(trimmed, L"latency_summary", L'{', L'}', latencyJson)) {
        FindJsonLongLong(latencyJson, L"total_sequence_ms", session.latencySummary.totalSequenceMs);
        FindJsonLongLong(latencyJson, L"average_step_ms", session.latencySummary.averageStepMs);
        FindJsonLongLong(latencyJson, L"p50_step_ms", session.latencySummary.p50StepMs);
        FindJsonLongLong(latencyJson, L"p95_step_ms", session.latencySummary.p95StepMs);
        FindJsonInt(latencyJson, L"process_restart_count", session.latencySummary.processRestartCount);
        FindJsonBool(latencyJson, L"session_reuse_enabled", session.latencySummary.sessionReuseEnabled);
        FindJsonInt(latencyJson, L"cache_hit_count", session.latencySummary.cacheHitCount);
        FindJsonInt(latencyJson, L"cache_miss_count", session.latencySummary.cacheMissCount);
        FindJsonString(latencyJson, L"slowest_step", session.latencySummary.slowestStep);
        FindJsonString(latencyJson, L"slowest_step_reason", session.latencySummary.slowestStepReason);
    }

    std::wstring cacheJson;
    if (ExtractJsonSection(trimmed, L"cache_summary", L'{', L'}', cacheJson)) {
        FindJsonInt(cacheJson, L"observe_cache_hit_count", session.cacheSummary.observeCacheHitCount);
        FindJsonInt(cacheJson, L"observe_cache_miss_count", session.cacheSummary.observeCacheMissCount);
        FindJsonInt(cacheJson, L"locator_cache_hit_count", session.cacheSummary.locatorCacheHitCount);
        FindJsonInt(cacheJson, L"locator_cache_miss_count", session.cacheSummary.locatorCacheMissCount);
        FindJsonBool(cacheJson, L"action_since_observe", session.cacheSummary.actionSinceObserve);
    }

    std::wstring observeJson;
    if (ExtractJsonSection(trimmed, L"observe_cache", L'{', L'}', observeJson)) {
        session.observeCache = ParseObserveCache(observeJson);
    }

    std::wstring locatorArrayJson;
    if (ExtractJsonSection(trimmed, L"locator_cache", L'[', L']', locatorArrayJson)) {
        session.locatorCache.clear();
        for (const auto& objectJson : SplitTopLevelObjects(locatorArrayJson)) {
            SessionLocatorCacheEntry entry = ParseLocatorCache(objectJson);
            if (!entry.locatorKey.empty() || entry.hasValue) {
                session.locatorCache.push_back(entry);
            }
        }
    }
    return !session.sessionId.empty();
}
