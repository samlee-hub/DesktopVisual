#include "SafeContextRecovery.h"

#include "InputController.h"
#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Trace.h"
#include "UiaController.h"
#include "WindowFinder.h"

#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <regex>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::vector<std::wstring> ArgValues(int argc, wchar_t** argv, const std::wstring& name) {
    std::vector<std::wstring> values;
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            values.push_back(argv[i + 1]);
            ++i;
        }
    }
    return values;
}

bool ParseBoolArg(int argc, wchar_t** argv, const std::wstring& name, bool& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    error = name + L" must be true or false.";
    return false;
}

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) {
            error = name + L" must be an integer.";
            return false;
        }
        value = parsed;
        return true;
    } catch (...) {
        error = name + L" must be an integer.";
        return false;
    }
}

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

bool RegexOrContains(const std::wstring& haystack, const std::wstring& pattern) {
    if (pattern.empty()) return true;
    try {
        std::wregex re(pattern, std::regex_constants::icase);
        return std::regex_search(haystack, re);
    } catch (...) {
        return Contains(haystack, pattern);
    }
}

std::wstring NormalizeSlashes(std::wstring value) {
    std::replace(value.begin(), value.end(), L'/', L'\\');
    return value;
}

std::wstring TargetString(const SafeRecoveryPolicy& policy) {
    if (!policy.recoveryUrl.empty()) return policy.recoveryUrl;
    if (!policy.recoveryPath.empty()) return policy.recoveryPath;
    return policy.recoveryWindowTitlePattern + L" " + policy.recoveryProcessPattern;
}

bool FileExists(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES;
}

bool DirectoryExists(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY);
}

bool BuiltinAllowedTarget(const std::wstring& target) {
    std::wstring lowerRaw = Lower(target);
    std::wstring lowerPath = Lower(NormalizeSlashes(target));
    if (lowerRaw.rfind(L"file:///d:/testrepo/testwindow/", 0) == 0) return true;
    if (lowerRaw.rfind(L"http://127.0.0.1:", 0) == 0) return true;
    if (lowerRaw.rfind(L"http://localhost:", 0) == 0) return true;
    if (lowerPath.rfind(L"d:\\testrepo\\testwindow", 0) == 0) return true;
    if (lowerPath.find(L"d:\\testrepo\\testwindow\\desktopvisual_long_scroll_test.html") != std::wstring::npos) return true;
    if (lowerPath.find(L"d:\\testrepo\\testwindow\\desktopvisual_mock_friend_list.html") != std::wstring::npos) return true;
    if (lowerPath.rfind(L"d:\\testrepo\\pycharm_sanity", 0) == 0 && DirectoryExists(L"D:\\testrepo\\pycharm_sanity")) return true;
    return false;
}

bool TargetAllowedByPolicy(const SafeRecoveryPolicy& policy, std::wstring& reason) {
    std::wstring target = TargetString(policy);
    if (target.empty()) {
        reason = L"Recovery target is empty.";
        return false;
    }
    std::wstring haystack = target + L"\n" + policy.recoveryScope + L"\n" + policy.recoveryAction;
    for (const auto& pattern : policy.disallowedRecoveryPatterns) {
        if (RegexOrContains(haystack, pattern)) {
            reason = L"Recovery target matched disallowed pattern: " + pattern;
            return false;
        }
    }
    if (policy.allowedRecoveryTargets.empty()) {
        if (BuiltinAllowedTarget(target)) return true;
        reason = L"Recovery target is not in the built-in safe recovery target set.";
        return false;
    }
    for (const auto& allowed : policy.allowedRecoveryTargets) {
        if (RegexOrContains(target, allowed) || RegexOrContains(haystack, allowed)) return true;
    }
    reason = L"Recovery target did not match allowed_recovery_targets.";
    return false;
}

bool HasAny(const std::wstring& text, std::initializer_list<const wchar_t*> needles) {
    for (const wchar_t* needle : needles) {
        if (Contains(text, needle)) return true;
    }
    return false;
}

bool ActiveProtectionDetected(const std::wstring& context) {
    return HasAny(context, {
        L"captcha",
        L"recaptcha",
        L"hcaptcha",
        L"turnstile",
        L"human verification",
        L"verify you are human",
        L"bot challenge",
        L"automation detected",
        L"script detection challenge",
        L"script detected",
        L"anti-cheat",
        L"EasyAntiCheat",
        L"BattlEye",
        L"Vanguard",
        L"vgc.exe",
        L"BEService.exe",
        L"lockdown browser",
        L"secure exam browser",
        L"active proctoring"
    });
}

bool CredentialRequiredDetected(const std::wstring& context) {
    return HasAny(context, {
        L"username",
        L"password",
        L"verification code",
        L"sms code",
        L"email code",
        L"account security verification",
        L"security verification",
        L"risk verification",
        L"account risk verification"
    });
}

bool ReadTextFileLocal(const std::wstring& path, std::wstring& text) {
    text.clear();
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"r, ccs=UTF-8") != 0 || !file) return false;
    wchar_t buffer[1024];
    while (fgetws(buffer, 1024, file)) {
        text += buffer;
    }
    fclose(file);
    return true;
}

bool ActiveWindow(WindowInfo& info) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return false;
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
    return true;
}

std::wstring ActiveWindowText(WindowInfo& active) {
    std::wstring text;
    if (!ActiveWindow(active)) return text;
    std::wstring process = ProcessNameForPid(active.pid);
    text = L"title:" + active.title + L"\nprocess:" + process;
    UiaQueryResult tree = ReadUiaTree(active.hwnd);
    if (tree.ok) {
        for (const auto& element : tree.elements) {
            text += L"\n" + element.name + L" " + element.value + L" " + element.controlType + L" " + element.automationId + L" " + element.className;
        }
    }
    return text;
}

bool VerifyMarkers(const std::wstring& text, const std::vector<std::wstring>& markers) {
    for (const auto& marker : markers) {
        if (!RegexOrContains(text, marker)) return false;
    }
    return true;
}

bool ProcessIsBrowser(const std::wstring& process) {
    std::wstring lower = Lower(process);
    return lower == L"chrome.exe" || lower == L"msedge.exe";
}

bool ActivateBrowserWindow(WindowInfo& selected) {
    std::vector<WindowInfo> windows = EnumerateVisibleTopLevelWindows();
    for (const auto& window : windows) {
        if (ProcessIsBrowser(ProcessNameForPid(window.pid))) {
            selected = window;
            SetForegroundWindow(window.hwnd);
            Sleep(200);
            return true;
        }
    }
    return false;
}

bool WaitForBrowserWindow(int waitMs, WindowInfo& selected) {
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    do {
        if (ActivateBrowserWindow(selected)) return true;
        Sleep(150);
    } while (GetTickCount64() < deadline);
    return ActivateBrowserWindow(selected);
}

bool OpenRunDialogAndType(const std::wstring& commandLine) {
    ActionResult run = SendHotkeyGlobal(L"WIN+R");
    if (!run.ok) return false;
    Sleep(250);
    TypeResult typed = TypeTextGlobal(commandLine, L"human", -1);
    if (!typed.ok) return false;
    Sleep(100);
    ActionResult enter = PressKeyGlobal(L"ENTER");
    return enter.ok;
}

bool ExecuteBrowserOpenUrlHuman(const std::wstring& url) {
    WindowInfo browser;
    if (!ActivateBrowserWindow(browser)) {
        if (!OpenRunDialogAndType(L"msedge.exe --new-window about:blank")) return false;
        if (!WaitForBrowserWindow(8000, browser)) return false;
    }
    SetForegroundWindow(browser.hwnd);
    Sleep(150);
    ActionResult focus = SendHotkeyGlobal(L"CTRL+L");
    if (!focus.ok) return false;
    Sleep(80);
    ActionResult selectAll = SendHotkeyGlobal(L"CTRL+A");
    if (!selectAll.ok) return false;
    Sleep(80);
    TypeResult typed = TypeTextGlobal(url, L"human", -1);
    if (!typed.ok) return false;
    Sleep(80);
    ActionResult enter = PressKeyGlobal(L"ENTER");
    return enter.ok;
}

bool ExecuteExplorerOpenPath(const std::wstring& path) {
    if (path.empty()) return false;
    std::wstring command = L"explorer.exe \"" + path + L"\"";
    return OpenRunDialogAndType(command);
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

void Stop(RecoveryResult& result, const std::wstring& code, const std::wstring& reason) {
    result.recoveryAllowed = false;
    result.recoverySuccess = false;
    result.recoveryStopCode = code;
    result.recoveryReason = reason;
}

}  // namespace

bool ParseRecoveryPolicyFromArgs(int argc, wchar_t** argv, RecoveryRequest& request, std::wstring& error) {
    SafeRecoveryPolicy& policy = request.policy;
    ArgValue(argc, argv, L"--recovery-scope", policy.recoveryScope);
    policy.allowedRecoveryTargets = ArgValues(argc, argv, L"--allowed-recovery-target");
    policy.disallowedRecoveryPatterns = ArgValues(argc, argv, L"--disallowed-recovery-pattern");
    ArgValue(argc, argv, L"--recovery-action", policy.recoveryAction);
    ArgValue(argc, argv, L"--recovery-url", policy.recoveryUrl);
    ArgValue(argc, argv, L"--recovery-path", policy.recoveryPath);
    ArgValue(argc, argv, L"--recovery-window-title-pattern", policy.recoveryWindowTitlePattern);
    ArgValue(argc, argv, L"--recovery-process-pattern", policy.recoveryProcessPattern);
    policy.recoveryExpectedMarkers = ArgValues(argc, argv, L"--recovery-expected-marker");
    ArgValue(argc, argv, L"--resume-policy", policy.resumePolicy);
    ArgValue(argc, argv, L"--context-text", request.currentContextText);
    std::wstring contextFile;
    if (ArgValue(argc, argv, L"--context-file", contextFile)) {
        std::wstring fileText;
        if (!ReadTextFileLocal(contextFile, fileText)) {
            error = L"Could not read --context-file.";
            return false;
        }
        request.currentContextText += L"\n" + fileText;
    }

    if (!ParseBoolArg(argc, argv, L"--recovery-enabled", policy.recoveryEnabled, error) ||
        !ParseBoolArg(argc, argv, L"--checkpoint-required", policy.checkpointRequired, error) ||
        !ParseBoolArg(argc, argv, L"--reobserve-required", policy.reobserveRequired, error) ||
        !ParseBoolArg(argc, argv, L"--stop-if-active-protection", policy.stopIfActiveProtection, error) ||
        !ParseBoolArg(argc, argv, L"--stop-if-credential-required", policy.stopIfCredentialRequired, error) ||
        !ParseBoolArg(argc, argv, L"--checkpoint-available", request.checkpointAvailable, error) ||
        !ParseBoolArg(argc, argv, L"--dry-run", request.dryRun, error) ||
        !ParseIntArg(argc, argv, L"--max-recovery-attempts", policy.maxRecoveryAttempts, error) ||
        !ParseIntArg(argc, argv, L"--recovery-attempt-count", request.recoveryAttemptCount, error)) {
        return false;
    }
    if (policy.maxRecoveryAttempts < 0) policy.maxRecoveryAttempts = 0;
    if (policy.recoveryAction.empty()) policy.recoveryAction = L"none";
    return true;
}

RecoveryResult EvaluateSafeContextRecovery(const RecoveryRequest& request) {
    RecoveryResult result;
    result.recoveryAttemptCount = request.recoveryAttemptCount;
    std::wstring context = request.currentContextText;
    WindowInfo beforeActive;
    if (context.empty()) {
        context = ActiveWindowText(beforeActive);
    }

    result.activeProtectionDetected = ActiveProtectionDetected(context);
    result.credentialRequiredDetected = CredentialRequiredDetected(context);

    if (!request.policy.recoveryEnabled) {
        Stop(result, L"RECOVERY_NOT_ALLOWED", L"Recovery policy disabled recovery.");
        return result;
    }
    if (request.policy.stopIfActiveProtection && result.activeProtectionDetected) {
        Stop(result, L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK", L"Active protection signal detected; recovery and continuation are refused.");
        return result;
    }
    if (request.policy.stopIfCredentialRequired && result.credentialRequiredDetected) {
        Stop(result, L"STOP_CREDENTIAL_REQUIRED", L"Credential or verification-code handoff detected; recovery and continuation are refused.");
        return result;
    }
    if (request.policy.checkpointRequired && !request.checkpointAvailable) {
        result.resumeAllowed = false;
        result.resumeBlockReason = L"Checkpoint is required but not available.";
        Stop(result, L"RECOVERY_NOT_ALLOWED", result.resumeBlockReason);
        return result;
    }
    if (request.recoveryAttemptCount >= request.policy.maxRecoveryAttempts) {
        Stop(result, L"RECOVERY_NOT_ALLOWED", L"Max recovery attempts reached.");
        return result;
    }

    std::wstring allowReason;
    if (!TargetAllowedByPolicy(request.policy, allowReason)) {
        Stop(result, L"RECOVERY_NOT_ALLOWED", allowReason);
        return result;
    }

    result.recoveryAllowed = true;
    bool actionOk = true;
    if (request.policy.recoveryAction != L"none" && request.policy.recoveryAction != L"observe_only") {
        result.recoveryAttempted = true;
        result.recoveryAttemptCount = request.recoveryAttemptCount + 1;
        if (!request.dryRun) {
            if (request.policy.recoveryAction == L"browser_open_url_human" ||
                request.policy.recoveryAction == L"browser-open-url-human") {
                actionOk = ExecuteBrowserOpenUrlHuman(request.policy.recoveryUrl);
                result.recoveryActionExecuted = L"browser-open-url-human";
            } else if (request.policy.recoveryAction == L"explorer_open_path" ||
                       request.policy.recoveryAction == L"explorer-open-path") {
                actionOk = ExecuteExplorerOpenPath(request.policy.recoveryPath);
                result.recoveryActionExecuted = L"explorer-open-path";
            } else {
                actionOk = false;
                result.recoveryActionExecuted = request.policy.recoveryAction;
            }
        } else {
            result.recoveryActionExecuted = request.policy.recoveryAction;
        }
    } else {
        result.recoveryActionExecuted = request.policy.recoveryAction;
    }

    if (!actionOk) {
        result.recoveryAttempted = true;
        Stop(result, L"RECOVERY_FAILED", L"Recovery action failed or is unsupported.");
        return result;
    }

    std::wstring observed = context;
    WindowInfo recovered;
    if (request.policy.reobserveRequired && result.recoveryAttempted && !request.dryRun) {
        Sleep(result.recoveryAttempted && !request.dryRun ? 1200 : 100);
        observed = ActiveWindowText(recovered);
        result.recoveredContextTitle = recovered.title;
        result.recoveredContextProcess = recovered.hwnd ? ProcessNameForPid(recovered.pid) : L"";
    }
    result.recoveredMarkersOk = VerifyMarkers(observed, request.policy.recoveryExpectedMarkers);
    if (!request.policy.recoveryExpectedMarkers.empty() && !result.recoveredMarkersOk) {
        Stop(result, L"RECOVERY_FAILED", L"Recovery completed but expected markers were not verified after reobserve.");
        return result;
    }

    result.recoverySuccess = true;
    result.recoveryStopCode.clear();
    result.recoveryReason = result.recoveryAttempted ? L"Recovery restored expected context markers." : L"Recovery policy allowed current context.";
    if (!request.policy.resumePolicy.empty() && request.policy.resumePolicy != L"none") {
        result.resumeAllowed = request.checkpointAvailable || !request.policy.checkpointRequired;
        result.resumedFromCheckpoint = result.resumeAllowed && request.policy.resumePolicy.find(L"checkpoint") != std::wstring::npos;
        if (!result.resumeAllowed) {
            result.resumeBlockReason = L"Resume policy requires checkpoint evidence.";
        }
    } else {
        result.resumeAllowed = true;
    }
    return result;
}

std::wstring RecoveryPolicyJson(const SafeRecoveryPolicy& policy) {
    std::wstringstream json;
    json << L"{\"recovery_enabled\":" << (policy.recoveryEnabled ? L"true" : L"false")
         << L",\"recovery_scope\":" << JsonString(policy.recoveryScope)
         << L",\"allowed_recovery_targets\":" << StringArrayJson(policy.allowedRecoveryTargets)
         << L",\"disallowed_recovery_patterns\":" << StringArrayJson(policy.disallowedRecoveryPatterns)
         << L",\"max_recovery_attempts\":" << policy.maxRecoveryAttempts
         << L",\"recovery_action\":" << JsonString(policy.recoveryAction)
         << L",\"recovery_url\":" << JsonString(policy.recoveryUrl)
         << L",\"recovery_path\":" << JsonString(policy.recoveryPath)
         << L",\"recovery_window_title_pattern\":" << JsonString(policy.recoveryWindowTitlePattern)
         << L",\"recovery_process_pattern\":" << JsonString(policy.recoveryProcessPattern)
         << L",\"recovery_expected_markers\":" << StringArrayJson(policy.recoveryExpectedMarkers)
         << L",\"resume_policy\":" << JsonString(policy.resumePolicy)
         << L",\"checkpoint_required\":" << (policy.checkpointRequired ? L"true" : L"false")
         << L",\"reobserve_required\":" << (policy.reobserveRequired ? L"true" : L"false")
         << L",\"stop_if_active_protection\":" << (policy.stopIfActiveProtection ? L"true" : L"false")
         << L",\"stop_if_credential_required\":" << (policy.stopIfCredentialRequired ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring RecoveryResultJson(const RecoveryResult& result) {
    std::wstringstream json;
    json << L"{\"recovery_attempted\":" << (result.recoveryAttempted ? L"true" : L"false")
         << L",\"recovery_allowed\":" << (result.recoveryAllowed ? L"true" : L"false")
         << L",\"recovery_success\":" << (result.recoverySuccess ? L"true" : L"false")
         << L",\"recovery_action_executed\":" << JsonString(result.recoveryActionExecuted)
         << L",\"recovery_attempt_count\":" << result.recoveryAttemptCount
         << L",\"recovery_stop_code\":" << JsonString(result.recoveryStopCode)
         << L",\"recovery_reason\":" << JsonString(result.recoveryReason)
         << L",\"recovered_context_title\":" << JsonString(result.recoveredContextTitle)
         << L",\"recovered_context_process\":" << JsonString(result.recoveredContextProcess)
         << L",\"recovered_markers_ok\":" << (result.recoveredMarkersOk ? L"true" : L"false")
         << L",\"resumed_from_checkpoint\":" << (result.resumedFromCheckpoint ? L"true" : L"false")
         << L",\"resume_allowed\":" << (result.resumeAllowed ? L"true" : L"false")
         << L",\"resume_block_reason\":" << JsonString(result.resumeBlockReason)
         << L",\"active_protection_detected\":" << (result.activeProtectionDetected ? L"true" : L"false")
         << L",\"credential_required_detected\":" << (result.credentialRequiredDetected ? L"true" : L"false")
         << L"}";
    return json.str();
}
