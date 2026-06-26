#include "LatencyProfile.h"

#include <algorithm>
#include <cwctype>

namespace {

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ArgValueLocal(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

}  // namespace

bool ParseLatencyProfileName(const std::wstring& raw, LatencyProfile& profile) {
    std::wstring value = ToLower(raw.empty() ? L"normal" : raw);
    if (value == L"conservative") {
        profile = LatencyProfile::Conservative;
        return true;
    }
    if (value == L"normal") {
        profile = LatencyProfile::Normal;
        return true;
    }
    if (value == L"fast-visible-ui") {
        profile = LatencyProfile::FastVisibleUi;
        return true;
    }
    return false;
}

bool ParseLatencyProfileArg(int argc, wchar_t** argv, LatencyProfile& profile, std::wstring& error) {
    profile = LatencyProfile::Normal;
    std::wstring raw;
    if (!ArgValueLocal(argc, argv, L"--latency-profile", raw)) {
        return true;
    }
    if (!ParseLatencyProfileName(raw, profile)) {
        error = L"--latency-profile must be conservative, normal, or fast-visible-ui.";
        return false;
    }
    return true;
}

std::wstring LatencyProfileName(LatencyProfile profile) {
    switch (profile) {
        case LatencyProfile::Conservative:
            return L"conservative";
        case LatencyProfile::FastVisibleUi:
            return L"fast-visible-ui";
        case LatencyProfile::Normal:
        default:
            return L"normal";
    }
}

void ApplyLatencyProfile(HumanMouseMotionOptions& options, LatencyProfile profile) {
    if (profile == LatencyProfile::Conservative) {
        options.moveDurationMs = options.moveDurationMs > 0 ? options.moveDurationMs : 650;
        options.minSteps = options.minSteps > 0 ? options.minSteps : 20;
        options.maxStepIntervalMs = options.maxStepIntervalMs > 0 ? options.maxStepIntervalMs : 35;
        options.dwellBeforeClickMs = options.dwellBeforeClickMs > 0 ? options.dwellBeforeClickMs : 220;
        options.postClickSettleMs = options.postClickSettleMs > 0 ? options.postClickSettleMs : 220;
        options.doubleClickIntervalMs = options.doubleClickIntervalMs > 0 ? options.doubleClickIntervalMs : 160;
        return;
    }

    if (profile == LatencyProfile::FastVisibleUi) {
        options.fastVisibleUi = true;
        options.motionFrameRateHz = options.motionFrameRateHz > 0 ? options.motionFrameRateHz : 165;
        options.moveDurationMs = options.moveDurationMs > 0 ? options.moveDurationMs : 60;
        options.minSteps = 0;
        options.maxStepIntervalMs = 0;
        options.dwellBeforeClickMs = options.dwellBeforeClickMs > 0 ? options.dwellBeforeClickMs : 25;
        options.postClickSettleMs = options.postClickSettleMs > 0 ? options.postClickSettleMs : 35;
        options.doubleClickIntervalMs = options.doubleClickIntervalMs > 0 ? options.doubleClickIntervalMs : 60;
        options.targetEpsilonPx = options.targetEpsilonPx > 0 ? options.targetEpsilonPx : 4;
        return;
    }
}

int LatencyProfileDefaultLaunchWaitMs(LatencyProfile profile) {
    if (profile == LatencyProfile::FastVisibleUi) return 1800;
    if (profile == LatencyProfile::Conservative) return 7000;
    return 5000;
}

int LatencyProfileDefaultRetryCount(LatencyProfile profile) {
    if (profile == LatencyProfile::FastVisibleUi) return 1;
    if (profile == LatencyProfile::Conservative) return 3;
    return 2;
}
