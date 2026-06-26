#pragma once

#include "WindowFinder.h"

#include <windows.h>

#include <string>
#include <vector>

struct TargetWindowLockOptions {
    std::wstring targetTitle;
    std::wstring targetHwnd;
    std::wstring targetProcess;
    bool requireTargetLock = false;
    bool allowGlobalDesktop = false;
    bool allowDryRunTarget = false;
};

struct TargetWindowLockResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool targetWindowLocked = false;
    bool allowGlobalDesktop = false;
    WindowInfo target;
    RECT lockedRect = {};
    HWND foregroundBefore = nullptr;
    HWND foregroundAfter = nullptr;
    bool foregroundValidated = false;
    bool rectStable = false;
    bool foregroundDrifted = false;
    std::wstring targetLockMode;
    bool targetLockCacheHit = false;
    long long durationMs = 0;
};

struct TargetWindowLockCache {
    bool hasLock = false;
    TargetWindowLockOptions options;
    WindowInfo target;
    RECT lockedRect = {};
    bool targetWindowLocked = false;
};

TargetWindowLockResult acquire_target_window_lock(const TargetWindowLockOptions& options);
TargetWindowLockResult reacquire_target_window_lock(const TargetWindowLockOptions& options);
TargetWindowLockResult acquire_target_window_lock_cached(TargetWindowLockCache& cache, const TargetWindowLockOptions& options);
bool validate_target_foreground(const TargetWindowLockResult& lock);
bool validate_target_rect_stable(const TargetWindowLockResult& lock);
bool validate_action_point_inside_target(const TargetWindowLockResult& lock, int screenX, int screenY);
bool verify_foreground_after_action(const TargetWindowLockResult& lock);
bool detect_foreground_drift(const TargetWindowLockResult& lock);
TargetWindowLockResult release_target_window_lock(const TargetWindowLockResult& lock);
std::wstring TargetWindowLockJson(const TargetWindowLockResult& result);
bool HasTargetWindowSelector(const TargetWindowLockOptions& options);
