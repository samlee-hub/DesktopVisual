#include "TargetWindowLock.h"

#include "ForegroundPreparation.h"
#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>
#include <sstream>
#include <tlhelp32.h>

namespace {

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

std::wstring ProcessNameForPidLocal(DWORD pid) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return L"";
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    std::wstring name;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == pid) {
                name = entry.szExeFile;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return name;
}

bool ParseHwnd(const std::wstring& raw, HWND& hwnd) {
    if (raw.empty()) return false;
    try {
        size_t consumed = 0;
        unsigned long long value = std::stoull(raw, &consumed, 0);
        if (consumed != raw.size()) return false;
        hwnd = reinterpret_cast<HWND>(value);
        return true;
    } catch (...) {
        return false;
    }
}

bool WindowInfoFromHwndLocal(HWND hwnd, WindowInfo& info) {
    if (!hwnd || !IsWindow(hwnd) || !IsWindowVisible(hwnd)) return false;
    int length = GetWindowTextLengthW(hwnd);
    if (length <= 0) return false;
    std::wstring title(static_cast<size_t>(length) + 1, L'\0');
    int copied = GetWindowTextW(hwnd, title.data(), length + 1);
    title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    if (title.empty()) return false;
    info.hwnd = hwnd;
    info.title = title;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    return info.rect.right > info.rect.left && info.rect.bottom > info.rect.top;
}

bool ProcessMatches(const WindowInfo& window, const std::wstring& process) {
    if (process.empty()) return true;
    return ToLower(ProcessNameForPidLocal(window.pid)) == ToLower(process);
}

std::vector<WindowInfo> FindMatches(const TargetWindowLockOptions& options) {
    std::vector<WindowInfo> matches;
    if (!options.targetHwnd.empty()) {
        HWND hwnd = nullptr;
        WindowInfo info;
        if (ParseHwnd(options.targetHwnd, hwnd) && WindowInfoFromHwndLocal(hwnd, info) && ProcessMatches(info, options.targetProcess)) {
            matches.push_back(info);
        }
        return matches;
    }
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        if (!options.targetTitle.empty() && ToLower(window.title).find(ToLower(options.targetTitle)) == std::wstring::npos) {
            continue;
        }
        if (!ProcessMatches(window, options.targetProcess)) {
            continue;
        }
        if (options.targetTitle.empty() && options.targetProcess.empty()) {
            continue;
        }
        matches.push_back(window);
    }
    return matches;
}

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right << L",\"bottom\":" << rect.bottom << L"}";
    return json.str();
}

std::wstring HwndJson(HWND hwnd) {
    return hwnd ? simplejson::Quote(FormatHwnd(hwnd)) : L"null";
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

long long Elapsed(ULONGLONG start) {
    return static_cast<long long>(GetTickCount64() - start);
}

bool RectClose(const RECT& a, const RECT& b, int tolerance = 8) {
    return std::abs(a.left - b.left) <= tolerance &&
           std::abs(a.top - b.top) <= tolerance &&
           std::abs(a.right - b.right) <= tolerance &&
           std::abs(a.bottom - b.bottom) <= tolerance;
}

bool SelectorCompatibleWithCache(const TargetWindowLockCache& cache, const TargetWindowLockOptions& options) {
    if (!cache.hasLock) return false;
    if (options.allowGlobalDesktop && cache.options.allowGlobalDesktop) return true;
    if (!cache.targetWindowLocked || !cache.target.hwnd) return false;
    if (!options.targetHwnd.empty()) {
        HWND requested = nullptr;
        return ParseHwnd(options.targetHwnd, requested) && requested == cache.target.hwnd;
    }
    if (!options.targetProcess.empty() && ToLower(ProcessNameForPidLocal(cache.target.pid)) != ToLower(options.targetProcess)) {
        return false;
    }
    if (!options.targetTitle.empty() && cache.options.targetTitle.empty() && cache.options.targetHwnd.empty() && cache.options.targetProcess.empty()) {
        return false;
    }
    return true;
}

bool CurrentRectForCache(const TargetWindowLockCache& cache, RECT& current) {
    current = {};
    if (!cache.targetWindowLocked) {
        current = cache.lockedRect;
        return true;
    }
    if (reinterpret_cast<UINT_PTR>(cache.target.hwnd) == 1) {
        current = cache.lockedRect;
        return true;
    }
    if (!cache.target.hwnd || !IsWindow(cache.target.hwnd)) return false;
    return GetWindowRect(cache.target.hwnd, &current) != FALSE;
}

}  // namespace

bool HasTargetWindowSelector(const TargetWindowLockOptions& options) {
    return !options.targetTitle.empty() || !options.targetHwnd.empty() || !options.targetProcess.empty();
}

TargetWindowLockResult acquire_target_window_lock(const TargetWindowLockOptions& options) {
    ULONGLONG start = GetTickCount64();
    TargetWindowLockResult result;
    result.allowGlobalDesktop = options.allowGlobalDesktop;
    result.foregroundBefore = GetForegroundWindow();
    result.targetLockMode = L"acquire";

    if (!HasTargetWindowSelector(options)) {
        if (options.allowGlobalDesktop) {
            result.ok = true;
            result.targetWindowLocked = false;
            result.rectStable = true;
            result.foregroundAfter = GetForegroundWindow();
            result.durationMs = Elapsed(start);
            return result;
        }
        result.errorCode = L"FAIL_TARGET_LOCK_REQUIRED";
        result.errorMessage = L"App-visible UI action requires --target-title, --target-hwnd, or --target-process unless --allow-global-desktop true is set.";
        result.durationMs = Elapsed(start);
        return result;
    }

    if (options.allowDryRunTarget) {
        result.ok = true;
        result.targetWindowLocked = true;
        result.target.title = options.targetTitle.empty() ? L"dry-run-target" : options.targetTitle;
        result.target.hwnd = reinterpret_cast<HWND>(1);
        result.lockedRect = RECT{0, 0, 640, 480};
        result.rectStable = true;
        result.foregroundValidated = true;
        result.foregroundAfter = result.foregroundBefore;
        result.durationMs = Elapsed(start);
        return result;
    }

    std::vector<WindowInfo> matches = FindMatches(options);
    if (matches.empty()) {
        result.errorCode = L"FAIL_TARGET_WINDOW_LOST";
        result.errorMessage = L"Target window was not found for target lock.";
        result.durationMs = Elapsed(start);
        return result;
    }
    if (matches.size() > 1) {
        result.errorCode = L"WINDOW_NOT_UNIQUE";
        result.errorMessage = L"Target lock matched multiple visible windows.";
        result.durationMs = Elapsed(start);
        return result;
    }
    result.target = matches.front();
    result.lockedRect = result.target.rect;
    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(result.target, 1200);
    result.foregroundAfter = prep.foregroundAfter;
    result.foregroundValidated = prep.ok && prep.foregroundAfter == result.target.hwnd;
    result.targetWindowLocked = result.foregroundValidated;
    result.rectStable = validate_target_rect_stable(result);
    result.foregroundDrifted = detect_foreground_drift(result);
    result.ok = result.targetWindowLocked && result.rectStable && !result.foregroundDrifted;
    if (!result.ok) {
        result.errorCode = result.foregroundDrifted ? L"FAIL_FOREGROUND_DRIFTED" : L"FAIL_TARGET_LOCK_REACQUIRE_FAILED";
        result.errorMessage = result.foregroundDrifted ? L"Foreground drifted during target lock acquisition." : L"Target window lock could not be acquired.";
    }
    result.durationMs = Elapsed(start);
    return result;
}

TargetWindowLockResult reacquire_target_window_lock(const TargetWindowLockOptions& options) {
    TargetWindowLockResult result = acquire_target_window_lock(options);
    result.targetLockMode = L"reacquire";
    return result;
}

TargetWindowLockResult acquire_target_window_lock_cached(TargetWindowLockCache& cache, const TargetWindowLockOptions& options) {
    ULONGLONG start = GetTickCount64();
    if (SelectorCompatibleWithCache(cache, options)) {
        RECT current = {};
        bool rectOk = CurrentRectForCache(cache, current);
        bool foregroundOk = !cache.targetWindowLocked || GetForegroundWindow() == cache.target.hwnd || reinterpret_cast<UINT_PTR>(cache.target.hwnd) == 1;
        if (rectOk && RectClose(current, cache.lockedRect) && foregroundOk) {
            TargetWindowLockResult result;
            result.ok = true;
            result.allowGlobalDesktop = options.allowGlobalDesktop;
            result.target = cache.target;
            result.lockedRect = cache.lockedRect;
            result.targetWindowLocked = cache.targetWindowLocked;
            result.foregroundBefore = GetForegroundWindow();
            result.foregroundAfter = result.foregroundBefore;
            result.foregroundValidated = foregroundOk;
            result.rectStable = true;
            result.foregroundDrifted = false;
            result.targetLockMode = L"cached_validate";
            result.targetLockCacheHit = true;
            result.durationMs = Elapsed(start);
            return result;
        }
    }

    TargetWindowLockResult result = cache.hasLock ? reacquire_target_window_lock(options) : acquire_target_window_lock(options);
    if (result.ok) {
        cache.hasLock = true;
        cache.options = options;
        cache.target = result.target;
        cache.lockedRect = result.lockedRect;
        cache.targetWindowLocked = result.targetWindowLocked;
    }
    result.targetLockCacheHit = false;
    if (result.targetLockMode.empty()) {
        result.targetLockMode = cache.hasLock ? L"reacquire" : L"acquire";
    }
    return result;
}

bool validate_target_foreground(const TargetWindowLockResult& lock) {
    return lock.targetWindowLocked && GetForegroundWindow() == lock.target.hwnd;
}

bool validate_target_rect_stable(const TargetWindowLockResult& lock) {
    if (!lock.targetWindowLocked || !lock.target.hwnd || reinterpret_cast<UINT_PTR>(lock.target.hwnd) == 1) return lock.targetWindowLocked;
    RECT current = {};
    if (!GetWindowRect(lock.target.hwnd, &current)) return false;
    const int tolerance = 8;
    return std::abs(current.left - lock.lockedRect.left) <= tolerance &&
           std::abs(current.top - lock.lockedRect.top) <= tolerance &&
           std::abs(current.right - lock.lockedRect.right) <= tolerance &&
           std::abs(current.bottom - lock.lockedRect.bottom) <= tolerance;
}

bool validate_action_point_inside_target(const TargetWindowLockResult& lock, int screenX, int screenY) {
    if (!lock.targetWindowLocked) return false;
    return screenX >= lock.lockedRect.left && screenX <= lock.lockedRect.right &&
           screenY >= lock.lockedRect.top && screenY <= lock.lockedRect.bottom;
}

bool verify_foreground_after_action(const TargetWindowLockResult& lock) {
    return validate_target_foreground(lock);
}

bool detect_foreground_drift(const TargetWindowLockResult& lock) {
    if (!lock.targetWindowLocked || !lock.target.hwnd || reinterpret_cast<UINT_PTR>(lock.target.hwnd) == 1) return false;
    HWND foreground = GetForegroundWindow();
    return foreground && foreground != lock.target.hwnd;
}

TargetWindowLockResult release_target_window_lock(const TargetWindowLockResult& lock) {
    TargetWindowLockResult released = lock;
    released.ok = true;
    released.targetWindowLocked = false;
    return released;
}

std::wstring TargetWindowLockJson(const TargetWindowLockResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << BoolJson(result.ok)
         << L",\"target_window_locked\":" << BoolJson(result.targetWindowLocked)
         << L",\"allow_global_desktop\":" << BoolJson(result.allowGlobalDesktop)
         << L",\"hwnd\":" << HwndJson(result.target.hwnd)
         << L",\"pid\":" << result.target.pid
         << L",\"title\":" << simplejson::Quote(result.target.title)
         << L",\"process_name\":" << simplejson::Quote(ProcessNameForPidLocal(result.target.pid))
         << L",\"target_rect\":" << RectJson(result.lockedRect)
         << L",\"foreground_before\":" << HwndJson(result.foregroundBefore)
         << L",\"foreground_after\":" << HwndJson(result.foregroundAfter)
         << L",\"foreground_validated\":" << BoolJson(result.foregroundValidated)
         << L",\"rect_stable\":" << BoolJson(result.rectStable)
         << L",\"foreground_drifted\":" << BoolJson(result.foregroundDrifted)
         << L",\"target_lock_mode\":" << simplejson::Quote(result.targetLockMode)
         << L",\"target_lock_cache_hit\":" << BoolJson(result.targetLockCacheHit)
         << L",\"duration_ms\":" << result.durationMs;
    if (!result.errorCode.empty()) {
        json << L",\"error\":{\"code\":" << simplejson::Quote(result.errorCode)
             << L",\"message\":" << simplejson::Quote(result.errorMessage) << L"}";
    }
    json << L"}";
    return json.str();
}
