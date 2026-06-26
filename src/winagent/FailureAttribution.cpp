#include "FailureAttribution.h"

#include "Trace.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool Contains(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

bool AnyContains(const std::wstring& text, const std::initializer_list<const wchar_t*>& needles) {
    for (const wchar_t* needle : needles) {
        if (Contains(text, needle)) return true;
    }
    return false;
}

std::wstring JoinedSignals(const FailureAttributionInput& input) {
    return input.errorCode + L"\n" + input.stopCode + L"\n" + input.failureReason + L"\n" + input.contextText;
}

FailureAttributionResult Make(FailureAttributionKind kind, const std::wstring& reason) {
    FailureAttributionResult result;
    result.attribution = kind;
    result.attributionName = FailureAttributionKindName(kind);
    result.reason = reason;
    return result;
}

}  // namespace

std::wstring FailureAttributionKindName(FailureAttributionKind kind) {
    switch (kind) {
        case FailureAttributionKind::APP_NOT_INSTALLED: return L"APP_NOT_INSTALLED";
        case FailureAttributionKind::APP_LAUNCH_FAILED: return L"APP_LAUNCH_FAILED";
        case FailureAttributionKind::FOREGROUND_ACQUIRE_FAILED: return L"FOREGROUND_ACQUIRE_FAILED";
        case FailureAttributionKind::EXPECTED_CONTEXT_FAILED: return L"EXPECTED_CONTEXT_FAILED";
        case FailureAttributionKind::UIA_READ_FAILED: return L"UIA_READ_FAILED";
        case FailureAttributionKind::OCR_READ_FAILED: return L"OCR_READ_FAILED";
        case FailureAttributionKind::TARGET_NOT_VISIBLE: return L"TARGET_NOT_VISIBLE";
        case FailureAttributionKind::TARGET_SEEN_BUT_NOT_CONFIRMED: return L"TARGET_SEEN_BUT_NOT_CONFIRMED";
        case FailureAttributionKind::TARGET_NOT_UNIQUE: return L"TARGET_NOT_UNIQUE";
        case FailureAttributionKind::SCROLL_REGION_NOT_FOUND: return L"SCROLL_REGION_NOT_FOUND";
        case FailureAttributionKind::SCROLL_NO_PROGRESS: return L"SCROLL_NO_PROGRESS";
        case FailureAttributionKind::WRONG_FIELD_FOCUS: return L"WRONG_FIELD_FOCUS";
        case FailureAttributionKind::BROWSER_SURFACE_BLOCKING: return L"BROWSER_SURFACE_BLOCKING";
        case FailureAttributionKind::ACTIVE_PROTECTION_STOP: return L"ACTIVE_PROTECTION_STOP";
        case FailureAttributionKind::CREDENTIAL_REQUIRED_STOP: return L"CREDENTIAL_REQUIRED_STOP";
        case FailureAttributionKind::SCRIPT_DETECTION_CHALLENGE_STOP: return L"SCRIPT_DETECTION_CHALLENGE_STOP";
        case FailureAttributionKind::ANTI_CHEAT_STOP: return L"ANTI_CHEAT_STOP";
        case FailureAttributionKind::RECOVERY_NOT_ALLOWED: return L"RECOVERY_NOT_ALLOWED";
        case FailureAttributionKind::RECOVERY_FAILED: return L"RECOVERY_FAILED";
        case FailureAttributionKind::ACTION_BLOCKED_BY_POLICY: return L"ACTION_BLOCKED_BY_POLICY";
        case FailureAttributionKind::ENVIRONMENT_UNSTABLE: return L"ENVIRONMENT_UNSTABLE";
        case FailureAttributionKind::RUNTIME_GUARD_STOP: return L"RUNTIME_GUARD_STOP";
        case FailureAttributionKind::UNKNOWN_FAILURE: return L"UNKNOWN_FAILURE";
    }
    return L"UNKNOWN_FAILURE";
}

FailureAttributionResult ClassifyFailureAttribution(const FailureAttributionInput& input) {
    std::wstring text = JoinedSignals(input);

    bool credential = AnyContains(text, {
        L"STOP_CREDENTIAL_REQUIRED",
        L"CREDENTIAL_REQUIRED",
        L"username",
        L"password",
        L"verification code",
        L"sms code",
        L"email code",
        L"account security verification"
    });
    bool antiCheat = AnyContains(text, {
        L"ANTI_CHEAT",
        L"EasyAntiCheat",
        L"BattlEye",
        L"Vanguard",
        L"vgc.exe",
        L"BEService.exe",
        L"secure exam browser",
        L"lockdown browser"
    });
    bool scriptChallenge = AnyContains(text, {
        L"SCRIPT_DETECTION_CHALLENGE_STOP",
        L"script detection challenge",
        L"automation detected",
        L"bot challenge",
        L"automated queries",
        L"suspicious traffic"
    });
    bool activeProtection = scriptChallenge || antiCheat || AnyContains(text, {
        L"STOP_ACTIVE_PROTECTION",
        L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK",
        L"captcha",
        L"recaptcha",
        L"hcaptcha",
        L"turnstile",
        L"human verification",
        L"verify you are human"
    });

    FailureAttributionResult result;
    if (antiCheat) result = Make(FailureAttributionKind::ANTI_CHEAT_STOP, L"Anti-cheat or lockdown protection signal was detected.");
    else if (scriptChallenge) result = Make(FailureAttributionKind::SCRIPT_DETECTION_CHALLENGE_STOP, L"Automation/script/bot challenge signal was detected.");
    else if (credential) result = Make(FailureAttributionKind::CREDENTIAL_REQUIRED_STOP, L"Credential or verification-code handoff was detected.");
    else if (activeProtection) result = Make(FailureAttributionKind::ACTIVE_PROTECTION_STOP, L"Active protection signal was detected.");
    else if (AnyContains(text, {L"APP_NOT_INSTALLED", L"not installed"})) result = Make(FailureAttributionKind::APP_NOT_INSTALLED, L"Target application appears not installed.");
    else if (AnyContains(text, {L"APP_LAUNCH_FAILED", L"launch failed"})) result = Make(FailureAttributionKind::APP_LAUNCH_FAILED, L"Target application launch failed.");
    else if (AnyContains(text, {L"WINDOW_FOCUS_FAILED", L"FOREGROUND_ACQUIRE_FAILED", L"STOP_FOREGROUND_CHANGED"})) result = Make(FailureAttributionKind::FOREGROUND_ACQUIRE_FAILED, L"Foreground target could not be acquired or changed unexpectedly.");
    else if (AnyContains(text, {L"STOP_WRONG_CONTEXT", L"EXPECTED_CONTEXT_FAILED", L"STOP_WRONG_PAGE", L"STOP_BROWSER_NAVIGATION_WRONG_PAGE"})) result = Make(FailureAttributionKind::EXPECTED_CONTEXT_FAILED, L"Expected context or page marker was not verified.");
    else if (AnyContains(text, {L"UIA_READ_FAILED", L"UIA_TREE_FAILED", L"UIA_INIT_FAILED"})) result = Make(FailureAttributionKind::UIA_READ_FAILED, L"UI Automation read failed.");
    else if (AnyContains(text, {L"OCR_READ_FAILED", L"OCR_FAILED", L"OCR_UNAVAILABLE", L"OCR_TEXT_NOT_FOUND"})) result = Make(FailureAttributionKind::OCR_READ_FAILED, L"OCR read failed or text was unavailable.");
    else if (AnyContains(text, {L"TARGET_NOT_VISIBLE", L"WINDOW_NOT_VISIBLE", L"STOP_TARGET_OUTSIDE_VIEWPORT"})) result = Make(FailureAttributionKind::TARGET_NOT_VISIBLE, L"Target was not visible or inside the viewport.");
    else if (AnyContains(text, {L"TARGET_SEEN_BUT_NOT_CONFIRMED", L"not confirmed"})) result = Make(FailureAttributionKind::TARGET_SEEN_BUT_NOT_CONFIRMED, L"Target candidate was seen but not confirmed.");
    else if (AnyContains(text, {L"TARGET_NOT_UNIQUE", L"LOCATOR_NOT_UNIQUE", L"STOP_TARGET_NOT_UNIQUE", L"UIA_ELEMENT_NOT_UNIQUE"})) result = Make(FailureAttributionKind::TARGET_NOT_UNIQUE, L"Target candidate was not unique.");
    else if (AnyContains(text, {L"SCROLL_REGION_NOT_FOUND"})) result = Make(FailureAttributionKind::SCROLL_REGION_NOT_FOUND, L"Scrollable region was not found.");
    else if (AnyContains(text, {L"SCROLL_NO_PROGRESS", L"WHEEL_NO_CONTENT_CHANGE", L"NO_PROGRESS_DETECTED"})) result = Make(FailureAttributionKind::SCROLL_NO_PROGRESS, L"Scroll produced no observable progress.");
    else if (AnyContains(text, {L"STOP_WRONG_FIELD_FOCUS", L"WRONG_FIELD_FOCUS", L"FIELD_NOT_FOCUSED"})) result = Make(FailureAttributionKind::WRONG_FIELD_FOCUS, L"Focused field did not match the intended target.");
    else if (AnyContains(text, {L"STOP_BROWSER_SURFACE_BLOCKING", L"BROWSER_SURFACE_BLOCKING", L"STOP_LOADING_OR_OVERLAY_BLOCKING"})) result = Make(FailureAttributionKind::BROWSER_SURFACE_BLOCKING, L"Browser surface or overlay blocked safe action.");
    else if (AnyContains(text, {L"RECOVERY_NOT_ALLOWED"})) result = Make(FailureAttributionKind::RECOVERY_NOT_ALLOWED, L"Safe recovery policy denied recovery.");
    else if (AnyContains(text, {L"RECOVERY_FAILED"})) result = Make(FailureAttributionKind::RECOVERY_FAILED, L"Recovery was attempted but did not restore the expected context.");
    else if (AnyContains(text, {L"SAFETY_POLICY_DENIED", L"ACTION_BLOCKED_BY_POLICY", L"CONSENT_DENIED"})) result = Make(FailureAttributionKind::ACTION_BLOCKED_BY_POLICY, L"Action was blocked by project policy.");
    else if (AnyContains(text, {L"ENVIRONMENT_UNSTABLE", L"timeout", L"TIMEOUT"})) result = Make(FailureAttributionKind::ENVIRONMENT_UNSTABLE, L"Environment was unstable, timed out, or changed unexpectedly.");
    else if (AnyContains(text, {L"RUNTIME_GUARD_STOP", L"STOP_TARGET_STALE"})) result = Make(FailureAttributionKind::RUNTIME_GUARD_STOP, L"Runtime guard stopped unsafe continuation.");
    else result = Make(FailureAttributionKind::UNKNOWN_FAILURE, L"No specific failure attribution rule matched.");

    result.activeProtectionDetected = activeProtection;
    result.credentialRequiredDetected = credential;
    result.scriptDetectionChallengeDetected = scriptChallenge;
    result.antiCheatDetected = antiCheat;
    return result;
}

std::wstring FailureAttributionResultJson(const FailureAttributionResult& result) {
    std::wstringstream json;
    json << L"{\"failure_attribution\":" << JsonString(result.attributionName)
         << L",\"reason\":" << JsonString(result.reason)
         << L",\"active_protection_detected\":" << (result.activeProtectionDetected ? L"true" : L"false")
         << L",\"credential_required_detected\":" << (result.credentialRequiredDetected ? L"true" : L"false")
         << L",\"script_detection_challenge_detected\":" << (result.scriptDetectionChallengeDetected ? L"true" : L"false")
         << L",\"anti_cheat_detected\":" << (result.antiCheatDetected ? L"true" : L"false")
         << L"}";
    return json.str();
}
