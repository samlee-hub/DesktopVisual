#include "PermissionManager.h"

#include "ProjectRoot.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <sstream>

namespace {

const int kDefaultTtlSeconds = 900;
const int kMaxTtlSeconds = 86400;

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

std::wstring NormalizeToken(std::wstring value) {
    value = ToLower(value);
    for (wchar_t& ch : value) {
        if (ch == L'-' || ch == L'.' || ch == L' ') ch = L'_';
    }
    return value;
}

long long UnixTimeMs() {
    FILETIME fileTime;
    GetSystemTimeAsFileTime(&fileTime);
    ULARGE_INTEGER value;
    value.LowPart = fileTime.dwLowDateTime;
    value.HighPart = fileTime.dwHighDateTime;
    return static_cast<long long>((value.QuadPart - 116444736000000000ULL) / 10000ULL);
}

std::wstring PermissionDir() {
    return ArtifactsPath(L"permission");
}

std::wstring SessionPath() {
    return PermissionDir() + L"\\full_access_session.json";
}

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) return L"";
    int required = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (required <= 0) return L"";
    std::wstring result(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), required);
    return result;
}

std::wstring ReadTextFileRaw(const std::wstring& path) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) return L"";
    std::string bytes;
    char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) bytes.append(buffer, read);
        if (read < sizeof(buffer)) break;
    }
    fclose(file);
    return Utf8ToWide(bytes);
}

size_t FindKeyValueStart(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return std::wstring::npos;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    return pos;
}

std::wstring JsonStringValue(const std::wstring& json, const std::wstring& key, const std::wstring& fallback = L"") {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'"') return fallback;
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) {
            ++pos;
        }
        value += json[pos];
        ++pos;
    }
    return value;
}

long long JsonLongLongValue(const std::wstring& json, const std::wstring& key, long long fallback) {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos) return fallback;
    try {
        return std::stoll(json.substr(pos));
    } catch (...) {
        return fallback;
    }
}

int JsonIntValue(const std::wstring& json, const std::wstring& key, int fallback) {
    long long value = JsonLongLongValue(json, key, fallback);
    if (value < 0 || value > 2147483647LL) return fallback;
    return static_cast<int>(value);
}

bool WriteUtf8WideFile(const std::wstring& path, const std::wstring& content, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open permission session file.";
        return false;
    }
    fwprintf(file, L"%ls", content.c_str());
    fclose(file);
    return true;
}

std::wstring GenerateFullAccessSessionId() {
    ULONGLONG tick = GetTickCount64();
    DWORD pid = GetCurrentProcessId();
    long long now = UnixTimeMs();
    wchar_t buffer[96] = {};
    swprintf_s(buffer, L"fa-%08x-%08llx-%lld", pid, tick, now);
    return buffer;
}

bool IsAllowedScope(const std::wstring& scope) {
    return scope == L"session-only" || scope == L"task-only";
}

bool IsFullAccessCapability(const std::wstring& action) {
    std::wstring normalized = NormalizeToken(action);
    return normalized == L"third_party_apps" ||
           normalized == L"third_party_app_launch" ||
           normalized == L"app_launch" ||
           normalized == L"explorer_navigate" ||
           normalized == L"file_open_local" ||
           normalized == L"browser_open" ||
           normalized == L"browser_address_bar_input" ||
           normalized == L"browser_navigate" ||
           normalized == L"local_html_interact" ||
           normalized == L"localhost_interact" ||
           normalized == L"external_web_navigate" ||
           normalized == L"external_web" ||
           normalized == L"communication" ||
           normalized == L"content_decision" ||
           normalized == L"cross_window" ||
           normalized == L"global_desktop";
}

bool IsDefaultBlockedCapability(const SafetyManifest& manifest, const std::wstring& action, std::wstring& capability) {
    std::wstring normalized = NormalizeToken(action);
    if (normalized == L"third_party_apps" && !manifest.defaultPermission.allowThirdPartyApps) { capability = normalized; return true; }
    if (normalized == L"external_web" && !manifest.defaultPermission.allowExternalWeb) { capability = normalized; return true; }
    if (normalized == L"communication" && !manifest.defaultPermission.allowCommunication) { capability = normalized; return true; }
    if (normalized == L"content_decision" && !manifest.defaultPermission.allowContentDecision) { capability = normalized; return true; }
    if (normalized == L"cross_window" && !manifest.defaultPermission.allowCrossWindow) { capability = normalized; return true; }
    if (normalized == L"global_desktop" && !manifest.defaultPermission.allowGlobalDesktop) { capability = normalized; return true; }
    return false;
}

bool ProfileAllowsCapability(const PermissionModeProfile& profile, const std::wstring& action) {
    std::wstring normalized = NormalizeToken(action);
    if (normalized == L"third_party_apps" || normalized == L"third_party_app_launch") return profile.allowThirdPartyApps;
    if (normalized == L"external_web" || normalized == L"external_web_navigate") return profile.allowExternalWeb;
    if (normalized == L"communication") return profile.allowCommunication;
    if (normalized == L"content_decision") return profile.allowContentDecision;
    if (normalized == L"cross_window") return profile.allowCrossWindow;
    if (normalized == L"global_desktop" || normalized == L"app_launch") return profile.allowGlobalDesktop || profile.allowThirdPartyApps;
    if (normalized == L"browser" || normalized == L"browser_open" || normalized == L"browser_address_bar_input" || normalized == L"browser_navigate") return profile.allowBrowser || profile.allowExternalWeb;
    if (normalized == L"explorer" || normalized == L"explorer_navigate") return profile.allowExplorer || profile.allowGlobalDesktop;
    if (normalized == L"file_open_local" || normalized == L"local_html_interact") return profile.allowLocalFileOpen || profile.allowGlobalDesktop;
    if (normalized == L"localhost" || normalized == L"localhost_interact") return profile.allowLocalhost || profile.allowExternalWeb;
    return true;
}

bool ImmutableStopForAction(const std::wstring& action, std::wstring& errorCode, std::wstring& matchedCategory) {
    std::wstring normalized = NormalizeToken(action);
    if (normalized == L"credential_input" || normalized == L"password" || normalized == L"credential") {
        errorCode = L"CREDENTIAL_INPUT_DETECTED";
        matchedCategory = L"credential";
        return true;
    }
    if (normalized == L"captcha" || normalized == L"recaptcha" || normalized == L"hcaptcha" || normalized == L"turnstile") {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        matchedCategory = L"captcha";
        return true;
    }
    if (normalized == L"anti_automation" || normalized == L"ai_detection" || normalized == L"script_detection") {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        matchedCategory = L"anti_automation";
        return true;
    }
    if (normalized == L"anti_cheat") {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        matchedCategory = L"anti_cheat";
        return true;
    }
    if (normalized == L"loop_guard") {
        errorCode = L"LOOP_GUARD_STOP";
        matchedCategory = L"loop_guard";
        return true;
    }
    if (normalized == L"user_takeover") {
        errorCode = L"USER_TAKEOVER_REQUIRED";
        matchedCategory = L"user_takeover";
        return true;
    }
    return false;
}

bool ContainsInsensitiveLocal(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLower(haystack).find(ToLower(needle)) != std::wstring::npos;
}

std::wstring BasenameForSignal(std::wstring value) {
    if (!value.empty() && value.front() == L'"' && value.back() == L'"') {
        value = value.substr(1, value.size() - 2);
    }
    size_t slash = value.find_last_of(L"\\/");
    if (slash != std::wstring::npos) value = value.substr(slash + 1);
    return ToLower(value);
}

bool IsAntiCheatProcess(const std::wstring& process) {
    std::wstring base = BasenameForSignal(process);
    return base == L"beservice.exe" ||
           base == L"easyanticheat.exe" ||
           base == L"easyanticheat_eos.exe" ||
           base == L"eac.exe" ||
           base == L"ace.exe" ||
           base == L"vgc.exe" ||
           base == L"vgtray.exe";
}

bool IsLockdownOrProctoringProcess(const std::wstring& process) {
    std::wstring base = BasenameForSignal(process);
    return base == L"lockdown browser.exe" ||
           base == L"secure exam browser.exe" ||
           base == L"safe exam browser.exe";
}

bool IsActiveProtectionSignal(
    const std::wstring& title,
    const std::wstring& process,
    const std::wstring& action,
    std::wstring& matchedCategory,
    std::wstring& matchedRule) {
    std::wstring text = title + L" " + process + L" " + action;
    if (ContainsInsensitiveLocal(text, L"bypass captcha") ||
        ContainsInsensitiveLocal(text, L"avoid bot detection") ||
        ContainsInsensitiveLocal(text, L"disable anti cheat") ||
        ContainsInsensitiveLocal(text, L"disable anti-cheat") ||
        ContainsInsensitiveLocal(text, L"hook beservice") ||
        ContainsInsensitiveLocal(text, L"hide automation from secure exam browser") ||
        ContainsInsensitiveLocal(text, L"patch vgc.exe")) {
        matchedCategory = L"active_protection_bypass_request";
        matchedRule = L"active_protection.bypass_request";
        return true;
    }
    if (ContainsInsensitiveLocal(text, L"captcha") ||
        ContainsInsensitiveLocal(text, L"recaptcha") ||
        ContainsInsensitiveLocal(text, L"hcaptcha") ||
        ContainsInsensitiveLocal(text, L"turnstile") ||
        ContainsInsensitiveLocal(text, L"verify you are human") ||
        ContainsInsensitiveLocal(text, L"human verification") ||
        ContainsInsensitiveLocal(text, L"bot challenge") ||
        ContainsInsensitiveLocal(text, L"bot check") ||
        ContainsInsensitiveLocal(text, L"bot verification") ||
        ContainsInsensitiveLocal(text, L"robot check") ||
        ContainsInsensitiveLocal(text, L"security check requiring human verification")) {
        matchedCategory = L"captcha_or_human_verification";
        matchedRule = L"active_protection.human_verification";
        return true;
    }
    if (ContainsInsensitiveLocal(text, L"automation detected") ||
        ContainsInsensitiveLocal(text, L"script detected") ||
        ContainsInsensitiveLocal(text, L"bot detected") ||
        ContainsInsensitiveLocal(text, L"suspicious automation") ||
        ContainsInsensitiveLocal(text, L"automated access challenge") ||
        ContainsInsensitiveLocal(text, L"ai detection challenge") ||
        ContainsInsensitiveLocal(text, L"ai-detection") ||
        ContainsInsensitiveLocal(text, L"browser automation challenge") ||
        ContainsInsensitiveLocal(text, L"bot challenge") ||
        ContainsInsensitiveLocal(text, L"anti-bot challenge")) {
        matchedCategory = L"automation_detection";
        matchedRule = L"active_protection.automation_detection";
        return true;
    }
    if (IsAntiCheatProcess(process) ||
        ContainsInsensitiveLocal(text, L"ace.exe") ||
        ContainsInsensitiveLocal(text, L"ACE anti cheat") ||
        ContainsInsensitiveLocal(text, L"ACE anti-cheat") ||
        ContainsInsensitiveLocal(text, L"AntiCheatExpert") ||
        ContainsInsensitiveLocal(text, L"\x5C0F" L"\x84DD" L"\x718A") ||
        ContainsInsensitiveLocal(text, L"EasyAntiCheat") ||
        ContainsInsensitiveLocal(text, L"EasyAntiCheat_EOS") ||
        ContainsInsensitiveLocal(text, L"eac.exe") ||
        ContainsInsensitiveLocal(text, L"BEService.exe") ||
        ContainsInsensitiveLocal(text, L"BattlEye") ||
        ContainsInsensitiveLocal(text, L"BattleEye") ||
        ContainsInsensitiveLocal(text, L"Riot Vanguard") ||
        ContainsInsensitiveLocal(text, L"Vanguard") ||
        ContainsInsensitiveLocal(text, L"vgc.exe") ||
        ContainsInsensitiveLocal(text, L"vgtray.exe") ||
        ContainsInsensitiveLocal(text, L"Ricochet") ||
        ContainsInsensitiveLocal(text, L"game anti-cheat active") ||
        ContainsInsensitiveLocal(text, L"protected game client") ||
        ContainsInsensitiveLocal(text, L"anti-cheat service") ||
        ContainsInsensitiveLocal(text, L"anti cheat service") ||
        ContainsInsensitiveLocal(text, L"anti-cheat service active")) {
        matchedCategory = L"anti_cheat_process";
        matchedRule = L"active_protection.anti_cheat";
        return true;
    }
    if (IsLockdownOrProctoringProcess(process) ||
        ContainsInsensitiveLocal(text, L"proctoring client active") ||
        ContainsInsensitiveLocal(text, L"active proctoring client") ||
        ContainsInsensitiveLocal(text, L"active proctoring") ||
        ContainsInsensitiveLocal(text, L"proctoring active") ||
        ContainsInsensitiveLocal(text, L"lockdown browser.exe") ||
        ContainsInsensitiveLocal(text, L"lockdown browser") ||
        ContainsInsensitiveLocal(text, L"lockdown browser active") ||
        ContainsInsensitiveLocal(text, L"secure exam browser.exe") ||
        ContainsInsensitiveLocal(text, L"secure exam browser") ||
        ContainsInsensitiveLocal(text, L"secure exam browser active") ||
        ContainsInsensitiveLocal(text, L"safe exam browser") ||
        ContainsInsensitiveLocal(text, L"exam secure browser") ||
        ContainsInsensitiveLocal(text, L"screen monitoring protection") ||
        ContainsInsensitiveLocal(text, L"screen monitoring protection active")) {
        matchedCategory = L"lockdown_or_proctoring";
        matchedRule = L"active_protection.proctoring";
        return true;
    }
    return false;
}

std::wstring CapabilityJson(const PermissionModeProfile& profile) {
    std::wstringstream json;
    json << L"{\"third_party_apps\":" << (profile.allowThirdPartyApps ? L"true" : L"false")
         << L",\"external_web\":" << (profile.allowExternalWeb ? L"true" : L"false")
         << L",\"communication\":" << (profile.allowCommunication ? L"true" : L"false")
         << L",\"content_decision\":" << (profile.allowContentDecision ? L"true" : L"false")
         << L",\"cross_window\":" << (profile.allowCrossWindow ? L"true" : L"false")
         << L",\"global_desktop\":" << (profile.allowGlobalDesktop ? L"true" : L"false")
         << L",\"browser\":" << (profile.allowBrowser ? L"true" : L"false")
         << L",\"explorer\":" << (profile.allowExplorer ? L"true" : L"false")
         << L",\"local_file_open\":" << (profile.allowLocalFileOpen ? L"true" : L"false")
         << L",\"localhost\":" << (profile.allowLocalhost ? L"true" : L"false")
         << L",\"requires_full_access_session\":" << (profile.requiresFullAccessSession ? L"true" : L"false")
         << L"}";
    return json.str();
}

}  // namespace

std::wstring PermissionModeName(PermissionMode mode) {
    if (mode == PermissionMode::FULL_ACCESS) return L"FULL_ACCESS";
    if (mode == PermissionMode::DEVELOPER_CAPABILITY_DISCOVERY) return L"DEVELOPER_CAPABILITY_DISCOVERY";
    if (mode == PermissionMode::PUBLIC_DEFAULT) return L"PUBLIC_DEFAULT";
    if (mode == PermissionMode::CI_MOCK) return L"CI_MOCK";
    return L"DEFAULT";
}

bool ParsePermissionMode(const std::wstring& value, PermissionMode& mode) {
    std::wstring normalized = NormalizeToken(value);
    if (normalized.empty() || normalized == L"default") {
        mode = PermissionMode::DEFAULT;
        return true;
    }
    if (normalized == L"public_default") {
        mode = PermissionMode::PUBLIC_DEFAULT;
        return true;
    }
    if (normalized == L"developer_capability_discovery" || normalized == L"developer_full_runtime") {
        mode = PermissionMode::DEVELOPER_CAPABILITY_DISCOVERY;
        return true;
    }
    if (normalized == L"ci_mock") {
        mode = PermissionMode::CI_MOCK;
        return true;
    }
    if (normalized == L"full_access") {
        mode = PermissionMode::FULL_ACCESS;
        return true;
    }
    return false;
}

std::wstring PermissionDecisionKindName(PermissionDecisionKind decision) {
    switch (decision) {
    case PermissionDecisionKind::ALLOW: return L"ALLOW";
    case PermissionDecisionKind::ALLOW_AUDITED: return L"ALLOW_AUDITED";
    case PermissionDecisionKind::STOP_ACTIVE_PROTECTION: return L"STOP_ACTIVE_PROTECTION";
    case PermissionDecisionKind::DENY_CONFIG_ERROR: return L"DENY_CONFIG_ERROR";
    case PermissionDecisionKind::REQUIRE_USER_CONFIRMATION: return L"REQUIRE_USER_CONFIRMATION";
    case PermissionDecisionKind::LEGACY_FULL_ACCESS_REQUIRED: return L"LEGACY_FULL_ACCESS_REQUIRED";
    case PermissionDecisionKind::DENY_UNSUPPORTED:
    default: return L"DENY_UNSUPPORTED";
    }
}

std::wstring DefaultPermissionModeName() {
    wchar_t envMode[128] = {};
    DWORD len = GetEnvironmentVariableW(L"DESKTOPVISUAL_PERMISSION_MODE", envMode, 128);
    if (len > 0 && len < 128) {
        PermissionMode parsed = PermissionMode::DEFAULT;
        if (ParsePermissionMode(envMode, parsed)) return PermissionModeName(parsed);
    }
    SafetyManifest manifest = LoadSafetyManifest();
    PermissionMode parsed = PermissionMode::DEFAULT;
    if (ParsePermissionMode(manifest.defaultPermissionMode, parsed)) return PermissionModeName(parsed);
    return L"DEVELOPER_CAPABILITY_DISCOVERY";
}

FullAccessSessionStatus GetFullAccessSessionStatus() {
    FullAccessSessionStatus status;
    status.path = SessionPath();
    std::wstring json = ReadTextFileRaw(status.path);
    if (json.empty()) {
        return status;
    }
    status.exists = true;
    status.sessionId = JsonStringValue(json, L"session_id");
    status.scope = JsonStringValue(json, L"scope", L"session-only");
    status.ttlSeconds = JsonIntValue(json, L"ttl_seconds", 0);
    status.createdAtUnixMs = JsonLongLongValue(json, L"created_at_unix_ms", 0);
    status.expiresAtUnixMs = JsonLongLongValue(json, L"expires_at_unix_ms", 0);
    long long now = UnixTimeMs();
    status.expired = status.expiresAtUnixMs <= now;
    status.active = !status.sessionId.empty() && !status.expired;
    if (status.expiresAtUnixMs > now) {
        status.remainingTtlSeconds = (status.expiresAtUnixMs - now + 999) / 1000;
    }
    return status;
}

bool UnlockFullAccessSession(int ttlSeconds, const std::wstring& scope, FullAccessSessionStatus& status, std::wstring& error) {
    if (!IsAllowedScope(scope)) {
        error = L"--scope must be task-only or session-only.";
        return false;
    }
    if (ttlSeconds <= 0) ttlSeconds = kDefaultTtlSeconds;
    if (ttlSeconds > kMaxTtlSeconds) {
        error = L"--ttl exceeds maximum allowed value.";
        return false;
    }

    EnsureDirectoryPath(PermissionDir());
    long long now = UnixTimeMs();
    status.exists = true;
    status.active = true;
    status.expired = false;
    status.sessionId = GenerateFullAccessSessionId();
    status.scope = scope;
    status.ttlSeconds = ttlSeconds;
    status.createdAtUnixMs = now;
    status.expiresAtUnixMs = now + (static_cast<long long>(ttlSeconds) * 1000LL);
    status.remainingTtlSeconds = ttlSeconds;
    status.path = SessionPath();

    std::wstringstream json;
    json << L"{\n"
         << L"  \"session_id\": " << JsonString(status.sessionId) << L",\n"
         << L"  \"permission_mode\": \"FULL_ACCESS\",\n"
         << L"  \"scope\": " << JsonString(status.scope) << L",\n"
         << L"  \"ttl_seconds\": " << status.ttlSeconds << L",\n"
         << L"  \"created_at_unix_ms\": " << status.createdAtUnixMs << L",\n"
         << L"  \"expires_at_unix_ms\": " << status.expiresAtUnixMs << L"\n"
         << L"}\n";
    return WriteUtf8WideFile(status.path, json.str(), error);
}

bool LockFullAccessSession(std::wstring& error) {
    std::wstring path = SessionPath();
    if (DeleteFileW(path.c_str())) {
        return true;
    }
    DWORD code = GetLastError();
    if (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND) {
        return true;
    }
    error = L"Could not remove full access session file.";
    return false;
}

PermissionDecision EvaluatePermissionRequest(
    const SafetyManifest& manifest,
    const std::wstring& title,
    const std::wstring& process,
    const std::wstring& action,
    PermissionMode mode,
    const std::wstring& fullAccessSessionId) {
    PermissionDecision decision;
    decision.mode = mode;
    decision.action = action;
    decision.title = title;
    decision.process = process;
    decision.fullAccessSessionId = fullAccessSessionId;

    std::wstring stopCode;
    std::wstring stopCategory;
    if (ImmutableStopForAction(action, stopCode, stopCategory)) {
        decision.errorCode = stopCode;
        decision.decision = stopCode == L"STOP_ACTIVE_PROTECTION"
            ? PermissionDecisionKind::STOP_ACTIVE_PROTECTION
            : PermissionDecisionKind::DENY_UNSUPPORTED;
        decision.reason = stopCode == L"STOP_ACTIVE_PROTECTION"
            ? L"Active protection signal detected; automation must stop."
            : L"Action matches an immutable safety stop condition.";
        decision.matchedRule = L"immutable_safety_rules";
        decision.matchedCategory = stopCategory;
        return decision;
    }

    std::wstring activeCategory;
    std::wstring activeRule;
    if (IsActiveProtectionSignal(title, process, action, activeCategory, activeRule)) {
        decision.errorCode = L"STOP_ACTIVE_PROTECTION";
        decision.decision = PermissionDecisionKind::STOP_ACTIVE_PROTECTION;
        decision.reason = L"active_protection_detected";
        decision.matchedRule = activeRule;
        decision.matchedCategory = activeCategory;
        return decision;
    }

    if (mode == PermissionMode::DEVELOPER_CAPABILITY_DISCOVERY) {
        if (!ProfileAllowsCapability(manifest.developerPermission, action)) {
            decision.errorCode = L"SAFETY_POLICY_DENIED";
            decision.decision = PermissionDecisionKind::DENY_CONFIG_ERROR;
            decision.reason = L"Developer capability discovery profile does not allow this capability.";
            decision.matchedRule = L"permission_modes.DEVELOPER_CAPABILITY_DISCOVERY";
            decision.matchedCategory = action;
            return decision;
        }
        decision.allow = true;
        decision.decision = PermissionDecisionKind::ALLOW_AUDITED;
        decision.reason = L"Allowed by DEVELOPER_CAPABILITY_DISCOVERY permission mode with audit.";
        decision.matchedRule = L"permission_modes.DEVELOPER_CAPABILITY_DISCOVERY";
        decision.relaxConfiguredBoundary = true;
        return decision;
    }

    if (mode == PermissionMode::CI_MOCK) {
        decision.allow = true;
        decision.decision = PermissionDecisionKind::ALLOW_AUDITED;
        decision.reason = L"Allowed by CI_MOCK permission mode for schema/mock tests.";
        decision.matchedRule = L"permission_modes.CI_MOCK";
        return decision;
    }

    if (mode == PermissionMode::DEFAULT) {
        std::wstring capability;
        if (IsDefaultBlockedCapability(manifest, action, capability)) {
            decision.errorCode = L"SAFETY_POLICY_DENIED";
            decision.decision = PermissionDecisionKind::DENY_UNSUPPORTED;
            decision.reason = L"DEFAULT permission mode does not allow this capability.";
            decision.matchedRule = L"permission_modes.DEFAULT." + capability;
            decision.matchedCategory = capability;
            return decision;
        }
        decision.allow = true;
        decision.decision = PermissionDecisionKind::ALLOW;
        decision.reason = L"Allowed by DEFAULT permission mode.";
        decision.matchedRule = L"permission_modes.DEFAULT";
        return decision;
    }

    if (mode == PermissionMode::PUBLIC_DEFAULT) {
        if (!ProfileAllowsCapability(manifest.publicDefaultPermission, action)) {
            decision.errorCode = L"SAFETY_POLICY_DENIED";
            decision.decision = PermissionDecisionKind::DENY_UNSUPPORTED;
            decision.reason = L"PUBLIC_DEFAULT permission mode does not allow this capability.";
            decision.matchedRule = L"permission_modes.PUBLIC_DEFAULT";
            decision.matchedCategory = action;
            return decision;
        }
        decision.allow = true;
        decision.decision = PermissionDecisionKind::ALLOW_AUDITED;
        decision.reason = L"Allowed by PUBLIC_DEFAULT permission mode.";
        decision.matchedRule = L"permission_modes.PUBLIC_DEFAULT";
        return decision;
    }

    if (!ProfileAllowsCapability(manifest.fullAccessPermission, action)) {
        decision.errorCode = L"SAFETY_POLICY_DENIED";
        decision.decision = PermissionDecisionKind::DENY_CONFIG_ERROR;
        decision.reason = L"FULL_ACCESS manifest profile does not allow this capability.";
        decision.matchedRule = L"permission_modes.FULL_ACCESS";
        decision.matchedCategory = action;
        return decision;
    }

    FullAccessSessionStatus session = GetFullAccessSessionStatus();
    decision.fullAccessSessionActive = session.active;
    decision.fullAccessSessionExpired = session.expired;
    decision.fullAccessScope = session.scope;
    decision.fullAccessExpiresAtUnixMs = session.expiresAtUnixMs;
    if (!session.active || fullAccessSessionId.empty() || session.sessionId != fullAccessSessionId) {
        decision.errorCode = L"FULL_ACCESS_SESSION_REQUIRED";
        decision.decision = PermissionDecisionKind::LEGACY_FULL_ACCESS_REQUIRED;
        decision.reason = session.expired
            ? L"FULL_ACCESS session is expired."
            : L"FULL_ACCESS requires a valid unlocked session id.";
        decision.matchedRule = L"full_access_session";
        return decision;
    }

    decision.allow = true;
    decision.decision = PermissionDecisionKind::ALLOW_AUDITED;
    decision.reason = L"Allowed by FULL_ACCESS permission mode and active session.";
    decision.matchedRule = L"permission_modes.FULL_ACCESS";
    decision.relaxConfiguredBoundary = true;
    return decision;
}

std::wstring FullAccessSessionStatusJson(const FullAccessSessionStatus& status) {
    std::wstringstream json;
    json << L"{\"exists\":" << (status.exists ? L"true" : L"false")
         << L",\"active\":" << (status.active ? L"true" : L"false")
         << L",\"expired\":" << (status.expired ? L"true" : L"false")
         << L",\"session_id\":" << JsonString(status.sessionId)
         << L",\"scope\":" << JsonString(status.scope)
         << L",\"ttl_seconds\":" << status.ttlSeconds
         << L",\"remaining_ttl_seconds\":" << status.remainingTtlSeconds
         << L",\"created_at_unix_ms\":" << status.createdAtUnixMs
         << L",\"expires_at_unix_ms\":" << status.expiresAtUnixMs
         << L",\"path\":" << JsonString(status.path)
         << L"}";
    return json.str();
}

std::wstring PermissionDecisionJson(const PermissionDecision& decision) {
    std::wstringstream json;
    json << L"{\"allow\":" << (decision.allow ? L"true" : L"false")
         << L",\"permission_mode\":" << JsonString(PermissionModeName(decision.mode))
         << L",\"decision\":" << JsonString(PermissionDecisionKindName(decision.decision))
         << L",\"reason\":" << JsonString(decision.reason)
         << L",\"matched_rule\":" << JsonString(decision.matchedRule)
         << L",\"matched_category\":" << JsonString(decision.matchedCategory)
         << L",\"action\":" << JsonString(decision.action)
         << L",\"title\":" << JsonString(decision.title)
         << L",\"process\":" << JsonString(decision.process)
         << L",\"full_access_session_id\":" << JsonString(decision.fullAccessSessionId)
         << L",\"full_access_session_active\":" << (decision.fullAccessSessionActive ? L"true" : L"false")
         << L",\"full_access_session_expired\":" << (decision.fullAccessSessionExpired ? L"true" : L"false")
         << L",\"full_access_scope\":" << JsonString(decision.fullAccessScope)
         << L",\"full_access_expires_at_unix_ms\":" << decision.fullAccessExpiresAtUnixMs
         << L",\"relax_configured_boundary\":" << (decision.relaxConfiguredBoundary ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring PermissionStatusDataJson() {
    SafetyManifest manifest = LoadSafetyManifest();
    FullAccessSessionStatus session = GetFullAccessSessionStatus();
    std::wstring activeProfile = session.active ? L"FULL_ACCESS" : DefaultPermissionModeName();
    std::wstringstream json;
    json << L"{\"permission_mode\":" << JsonString(activeProfile)
         << L",\"active_profile\":" << JsonString(activeProfile)
         << L",\"default_profile\":" << CapabilityJson(manifest.defaultPermission)
         << L",\"public_default_profile\":" << CapabilityJson(manifest.publicDefaultPermission)
         << L",\"developer_profile\":" << CapabilityJson(manifest.developerPermission)
         << L",\"ci_mock_profile\":" << CapabilityJson(manifest.ciMockPermission)
         << L",\"full_access_profile\":" << CapabilityJson(manifest.fullAccessPermission)
         << L",\"full_access\":" << FullAccessSessionStatusJson(session)
         << L"}";
    return json.str();
}
