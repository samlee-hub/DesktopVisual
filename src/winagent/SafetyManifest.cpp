#include "SafetyManifest.h"

#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <sstream>

namespace {

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

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && (iswspace(value[first]) || value[first] == 0xFEFF)) ++first;
    size_t last = value.size();
    while (last > first && iswspace(value[last - 1])) --last;
    return value.substr(first, last - first);
}

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

std::wstring ReplaceAll(std::wstring value, const std::wstring& needle, const std::wstring& replacement) {
    size_t pos = 0;
    while ((pos = value.find(needle, pos)) != std::wstring::npos) {
        value.replace(pos, needle.size(), replacement);
        pos += replacement.size();
    }
    return value;
}

std::wstring ExpandManifestVariables(const std::wstring& value) {
    std::wstring expanded = ReplaceAll(value, L"${PROJECT_ROOT}", ProjectRootPath());
    expanded = ReplaceAll(expanded, L"%PROJECT_ROOT%", ProjectRootPath());
    return expanded;
}

size_t FindKeyValueStart(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return std::wstring::npos;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    return pos;
}

std::wstring JsonObject(const std::wstring& json, const std::wstring& key) {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'{') return L"";
    int depth = 1;
    size_t start = pos++;
    bool inString = false;
    while (pos < json.size() && depth > 0) {
        wchar_t ch = json[pos];
        if (ch == L'"' && (pos == 0 || json[pos - 1] != L'\\')) inString = !inString;
        if (!inString) {
            if (ch == L'{') ++depth;
            else if (ch == L'}') --depth;
        }
        ++pos;
    }
    return json.substr(start, pos - start);
}

std::wstring JsonArrayRaw(const std::wstring& json, const std::wstring& key) {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'[') return L"";
    int depth = 1;
    size_t start = pos++;
    bool inString = false;
    while (pos < json.size() && depth > 0) {
        wchar_t ch = json[pos];
        if (ch == L'"' && (pos == 0 || json[pos - 1] != L'\\')) inString = !inString;
        if (!inString) {
            if (ch == L'[') ++depth;
            else if (ch == L']') --depth;
        }
        ++pos;
    }
    return json.substr(start, pos - start);
}

std::wstring JsonStringValue(const std::wstring& json, const std::wstring& key, const std::wstring& fallback = L"") {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'"') return fallback;
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) {
            ++pos;
            if (json[pos] == L'n') value += L'\n';
            else if (json[pos] == L'r') value += L'\r';
            else if (json[pos] == L't') value += L'\t';
            else value += json[pos];
        } else {
            value += json[pos];
        }
        ++pos;
    }
    return ExpandManifestVariables(value);
}

int JsonIntValue(const std::wstring& json, const std::wstring& key, int fallback) {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos) return fallback;
    try {
        return std::stoi(json.substr(pos));
    } catch (...) {
        return fallback;
    }
}

bool JsonBoolValue(const std::wstring& json, const std::wstring& key, bool fallback) {
    size_t pos = FindKeyValueStart(json, key);
    if (pos == std::wstring::npos) return fallback;
    if (json.substr(pos, 4) == L"true") return true;
    if (json.substr(pos, 5) == L"false") return false;
    return fallback;
}

std::vector<std::wstring> JsonStringArray(const std::wstring& json, const std::wstring& key) {
    std::vector<std::wstring> values;
    std::wstring raw = JsonArrayRaw(json, key);
    if (raw.empty()) return values;
    size_t pos = 0;
    while (pos < raw.size()) {
        while (pos < raw.size() && raw[pos] != L'"') ++pos;
        if (pos >= raw.size()) break;
        ++pos;
        std::wstring value;
        while (pos < raw.size() && raw[pos] != L'"') {
            if (raw[pos] == L'\\' && pos + 1 < raw.size()) {
                ++pos;
                if (raw[pos] == L'n') value += L'\n';
                else if (raw[pos] == L'r') value += L'\r';
                else if (raw[pos] == L't') value += L'\t';
                else value += raw[pos];
            } else {
                value += raw[pos];
            }
            ++pos;
        }
        ++pos;
        value = Trim(ExpandManifestVariables(value));
        if (!value.empty()) values.push_back(value);
    }
    return values;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
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

bool ListContainsInsensitive(const std::vector<std::wstring>& values, const std::wstring& needle) {
    std::wstring lowered = ToLower(needle);
    for (const auto& value : values) {
        if (ToLower(value) == lowered) return true;
    }
    return false;
}

bool MatchesTitleList(const std::wstring& title, const std::vector<std::wstring>& values) {
    std::wstring lowered = ToLower(title);
    for (const auto& value : values) {
        std::wstring allowed = ToLower(value);
        if (lowered == allowed || lowered.find(allowed) != std::wstring::npos) return true;
    }
    return false;
}

std::wstring ArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

bool WriteUtf8WideFile(const std::wstring& path, const std::wstring& content, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open output file.";
        return false;
    }
    fwprintf(file, L"%ls", content.c_str());
    fclose(file);
    return true;
}

std::wstring PolicyDecisionJson(const PolicyCheckDecision& decision) {
    std::wstringstream json;
    json << L"{\"allow\":" << (decision.allow ? L"true" : L"false")
         << L",\"permission_mode\":" << JsonString(decision.permissionMode)
         << L",\"reason\":" << JsonString(decision.reason)
         << L",\"matched_rule\":" << JsonString(decision.matchedRule)
         << L",\"matched_category\":" << JsonString(decision.matchedCategory)
         << L",\"title\":" << JsonString(decision.title)
         << L",\"process\":" << JsonString(decision.process)
         << L",\"action\":" << JsonString(decision.action)
         << L",\"path\":" << JsonString(decision.path)
         << L",\"full_access_session_id\":" << JsonString(decision.fullAccessSessionId)
         << L",\"full_access_session_active\":" << (decision.fullAccessSessionActive ? L"true" : L"false")
         << L",\"full_access_session_expired\":" << (decision.fullAccessSessionExpired ? L"true" : L"false")
         << L",\"full_access_scope\":" << JsonString(decision.fullAccessScope)
         << L"}";
    return json.str();
}

bool IsActiveProtectionText(const std::wstring& title, const std::wstring& process, std::wstring& category) {
    std::wstring text = title + L" " + process;
    if (ContainsInsensitive(text, L"bypass captcha") ||
        ContainsInsensitive(text, L"avoid bot detection") ||
        ContainsInsensitive(text, L"disable anti cheat") ||
        ContainsInsensitive(text, L"disable anti-cheat") ||
        ContainsInsensitive(text, L"hook beservice") ||
        ContainsInsensitive(text, L"hide automation from secure exam browser") ||
        ContainsInsensitive(text, L"patch vgc.exe")) {
        category = L"active_protection_bypass_request";
        return true;
    }
    if (ContainsInsensitive(text, L"captcha") ||
        ContainsInsensitive(text, L"recaptcha") ||
        ContainsInsensitive(text, L"hcaptcha") ||
        ContainsInsensitive(text, L"turnstile") ||
        ContainsInsensitive(text, L"verify you are human") ||
        ContainsInsensitive(text, L"human verification") ||
        ContainsInsensitive(text, L"bot challenge") ||
        ContainsInsensitive(text, L"bot check") ||
        ContainsInsensitive(text, L"bot verification") ||
        ContainsInsensitive(text, L"robot check")) {
        category = L"captcha_or_human_verification";
        return true;
    }
    if (ContainsInsensitive(text, L"automation detected") ||
        ContainsInsensitive(text, L"script detected") ||
        ContainsInsensitive(text, L"bot detected") ||
        ContainsInsensitive(text, L"automated access challenge") ||
        ContainsInsensitive(text, L"ai detection challenge") ||
        ContainsInsensitive(text, L"browser automation challenge") ||
        ContainsInsensitive(text, L"bot challenge") ||
        ContainsInsensitive(text, L"anti-bot challenge")) {
        category = L"automation_detection";
        return true;
    }
    if (IsAntiCheatProcess(process) ||
        ContainsInsensitive(text, L"ace.exe") ||
        ContainsInsensitive(text, L"ACE anti cheat") ||
        ContainsInsensitive(text, L"ACE anti-cheat") ||
        ContainsInsensitive(text, L"AntiCheatExpert") ||
        ContainsInsensitive(text, L"\x5C0F" L"\x84DD" L"\x718A") ||
        ContainsInsensitive(text, L"EasyAntiCheat") ||
        ContainsInsensitive(text, L"EasyAntiCheat_EOS") ||
        ContainsInsensitive(text, L"eac.exe") ||
        ContainsInsensitive(text, L"BEService.exe") ||
        ContainsInsensitive(text, L"BattlEye") ||
        ContainsInsensitive(text, L"BattleEye") ||
        ContainsInsensitive(text, L"Riot Vanguard") ||
        ContainsInsensitive(text, L"Vanguard") ||
        ContainsInsensitive(text, L"vgc.exe") ||
        ContainsInsensitive(text, L"vgtray.exe") ||
        ContainsInsensitive(text, L"Ricochet") ||
        ContainsInsensitive(text, L"game anti-cheat active") ||
        ContainsInsensitive(text, L"anti-cheat service") ||
        ContainsInsensitive(text, L"anti cheat service") ||
        ContainsInsensitive(text, L"anti-cheat service active")) {
        category = L"anti_cheat_process";
        return true;
    }
    if (IsLockdownOrProctoringProcess(process) ||
        ContainsInsensitive(text, L"proctoring client active") ||
        ContainsInsensitive(text, L"active proctoring client") ||
        ContainsInsensitive(text, L"active proctoring") ||
        ContainsInsensitive(text, L"proctoring active") ||
        ContainsInsensitive(text, L"lockdown browser.exe") ||
        ContainsInsensitive(text, L"lockdown browser") ||
        ContainsInsensitive(text, L"lockdown browser active") ||
        ContainsInsensitive(text, L"secure exam browser.exe") ||
        ContainsInsensitive(text, L"secure exam browser") ||
        ContainsInsensitive(text, L"secure exam browser active") ||
        ContainsInsensitive(text, L"safe exam browser") ||
        ContainsInsensitive(text, L"exam secure browser") ||
        ContainsInsensitive(text, L"screen monitoring protection") ||
        ContainsInsensitive(text, L"screen monitoring protection active")) {
        category = L"lockdown_or_proctoring";
        return true;
    }
    return false;
}

std::wstring PermissionProfileJson(const PermissionModeProfile& profile) {
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

std::wstring ReportPolicyJson(const SafetyManifest& manifest) {
    std::wstringstream json;
    json << L"{\"report_level\":" << JsonString(manifest.reportLevel)
         << L",\"evidence_level\":" << JsonString(manifest.evidenceLevel)
         << L",\"progress_output\":" << JsonString(manifest.progressOutput)
         << L",\"step_chat_detail\":" << JsonString(manifest.stepChatDetail)
         << L",\"artifact_evidence\":" << JsonString(manifest.artifactEvidence)
         << L",\"failure_detail\":" << JsonString(manifest.failureDetail)
         << L"}";
    return json.str();
}

bool OrdinaryVisibleCapabilitiesAligned(const PermissionModeProfile& publicProfile, const PermissionModeProfile& developerProfile) {
    return publicProfile.allowThirdPartyApps == developerProfile.allowThirdPartyApps &&
           publicProfile.allowExternalWeb == developerProfile.allowExternalWeb &&
           publicProfile.allowCommunication == developerProfile.allowCommunication &&
           publicProfile.allowContentDecision == developerProfile.allowContentDecision &&
           publicProfile.allowCrossWindow == developerProfile.allowCrossWindow &&
           publicProfile.allowGlobalDesktop == developerProfile.allowGlobalDesktop &&
           publicProfile.allowBrowser == developerProfile.allowBrowser &&
           publicProfile.allowExplorer == developerProfile.allowExplorer &&
           publicProfile.allowLocalFileOpen == developerProfile.allowLocalFileOpen &&
           publicProfile.allowLocalhost == developerProfile.allowLocalhost &&
           publicProfile.requiresFullAccessSession == developerProfile.requiresFullAccessSession;
}

std::wstring PublicDeveloperProfileDifferenceJson(const SafetyManifest& manifest) {
    bool aligned = OrdinaryVisibleCapabilitiesAligned(manifest.publicDefaultPermission, manifest.developerPermission);
    bool stopTriggersPreserved =
        ListContainsInsensitive(manifest.deniedSensitiveCategories, L"active_protection") &&
        ListContainsInsensitive(manifest.deniedSensitiveCategories, L"anti_cheat") &&
        ListContainsInsensitive(manifest.deniedSensitiveCategories, L"captcha") &&
        ListContainsInsensitive(manifest.deniedSensitiveCategories, L"protected_desktop") &&
        ListContainsInsensitive(manifest.deniedSensitiveCategories, L"proctoring");

    std::wstringstream json;
    json << L"{\"ordinary_visible_capabilities_aligned\":" << (aligned ? L"true" : L"false")
         << L",\"stop_triggers_preserved\":" << (stopTriggersPreserved ? L"true" : L"false")
         << L",\"public_requires_full_access_session\":" << (manifest.publicDefaultPermission.requiresFullAccessSession ? L"true" : L"false")
         << L",\"developer_requires_full_access_session\":" << (manifest.developerPermission.requiresFullAccessSession ? L"true" : L"false")
         << L",\"public_policy_boundary\":\"ordinary visible desktop/app/web/IDE/Explorer/localhost operations are allowed; real active protection/security interception stops\""
         << L"}";
    return json.str();
}

void LoadPermissionProfile(const std::wstring& json, PermissionModeProfile& profile) {
    if (json.empty()) return;
    profile.allowThirdPartyApps = JsonBoolValue(json, L"third_party_apps", profile.allowThirdPartyApps);
    profile.allowExternalWeb = JsonBoolValue(json, L"external_web", profile.allowExternalWeb);
    profile.allowCommunication = JsonBoolValue(json, L"communication", profile.allowCommunication);
    profile.allowContentDecision = JsonBoolValue(json, L"content_decision", profile.allowContentDecision);
    profile.allowCrossWindow = JsonBoolValue(json, L"cross_window", profile.allowCrossWindow);
    profile.allowGlobalDesktop = JsonBoolValue(json, L"global_desktop", profile.allowGlobalDesktop);
    profile.allowBrowser = JsonBoolValue(json, L"browser", profile.allowBrowser);
    profile.allowExplorer = JsonBoolValue(json, L"explorer", profile.allowExplorer);
    profile.allowLocalFileOpen = JsonBoolValue(json, L"local_file_open", profile.allowLocalFileOpen);
    profile.allowLocalhost = JsonBoolValue(json, L"localhost", profile.allowLocalhost);
    profile.requiresFullAccessSession = JsonBoolValue(json, L"requires_full_access_session", profile.requiresFullAccessSession);
}

PermissionModeProfile OpenDeveloperProfile() {
    PermissionModeProfile profile;
    profile.allowThirdPartyApps = true;
    profile.allowExternalWeb = true;
    profile.allowCommunication = true;
    profile.allowContentDecision = true;
    profile.allowCrossWindow = true;
    profile.allowGlobalDesktop = true;
    profile.allowBrowser = true;
    profile.allowExplorer = true;
    profile.allowLocalFileOpen = true;
    profile.allowLocalhost = true;
    profile.requiresFullAccessSession = false;
    return profile;
}

}  // namespace

SafetyManifest LoadSafetyManifest() {
    SafetyManifest manifest;
    manifest.manifestPath = ConfigPath(L"safety_manifest.json");
    manifest.deniedWindowTitlePatterns = {};
    manifest.deniedProcesses = {L"Consent.exe", L"CredentialUIBroker.exe"};
    manifest.deniedSensitiveCategories = {L"admin_elevation", L"protected_desktop", L"active_protection", L"anti_cheat", L"captcha"};
    manifest.defaultPermission = PermissionModeProfile{};
    manifest.publicDefaultPermission = PermissionModeProfile{};
    manifest.developerPermission = OpenDeveloperProfile();
    manifest.ciMockPermission = PermissionModeProfile{};
    manifest.fullAccessPermission.allowThirdPartyApps = true;
    manifest.fullAccessPermission.allowExternalWeb = true;
    manifest.fullAccessPermission.allowCommunication = true;
    manifest.fullAccessPermission.allowContentDecision = true;
    manifest.fullAccessPermission.allowCrossWindow = true;
    manifest.fullAccessPermission.allowGlobalDesktop = true;
    manifest.fullAccessPermission.allowBrowser = true;
    manifest.fullAccessPermission.allowExplorer = true;
    manifest.fullAccessPermission.allowLocalFileOpen = true;
    manifest.fullAccessPermission.allowLocalhost = true;
    manifest.fullAccessPermission.requiresFullAccessSession = true;

    std::wstring json = ReadTextFileRaw(manifest.manifestPath);
    if (json.empty()) {
        manifest.warnings.push_back(L"safety_manifest.json was not found; using safety.conf only.");
        return manifest;
    }

    manifest.loaded = true;
    manifest.version = JsonIntValue(json, L"version", 1);
    manifest.project = JsonStringValue(json, L"project", L"DesktopVisual");
    manifest.mode = JsonStringValue(json, L"mode", L"local_authorized_windows_runtime");
    manifest.defaultPermissionMode = JsonStringValue(json, L"default_permission_mode", manifest.defaultPermissionMode);

    std::wstring allowed = JsonObject(json, L"allowed");
    manifest.allowedWindowTitles = JsonStringArray(allowed, L"window_titles");
    manifest.allowedProcesses = JsonStringArray(allowed, L"processes");
    manifest.allowedReadRoots = JsonStringArray(allowed, L"read_roots");
    manifest.allowedWriteRoots = JsonStringArray(allowed, L"write_roots");
    manifest.allowedActions = JsonStringArray(allowed, L"actions");

    std::wstring denied = JsonObject(json, L"denied");
    std::vector<std::wstring> deniedTitles = JsonStringArray(denied, L"window_title_patterns");
    std::vector<std::wstring> deniedProcesses = JsonStringArray(denied, L"processes");
    std::vector<std::wstring> deniedCategories = JsonStringArray(denied, L"sensitive_categories");
    if (!deniedTitles.empty()) manifest.deniedWindowTitlePatterns = deniedTitles;
    if (!deniedProcesses.empty()) manifest.deniedProcesses = deniedProcesses;
    if (!deniedCategories.empty()) manifest.deniedSensitiveCategories = deniedCategories;

    std::wstring limits = JsonObject(json, L"runtime_limits");
    manifest.maxSteps = JsonIntValue(limits, L"max_steps", manifest.maxSteps);
    manifest.maxDurationMs = JsonIntValue(limits, L"max_duration_ms", manifest.maxDurationMs);
    manifest.maxRecoveries = JsonIntValue(limits, L"max_recoveries", manifest.maxRecoveries);
    manifest.emergencyStopKey = JsonStringValue(limits, L"emergency_stop_key", manifest.emergencyStopKey);

    std::wstring consent = JsonObject(json, L"consent");
    manifest.requiresExplicitTarget = JsonBoolValue(consent, L"requires_explicit_target", true);
    manifest.requiresVisibleForegroundWindow = JsonBoolValue(consent, L"requires_visible_foreground_window", true);
    manifest.allowBackgroundControl = JsonBoolValue(consent, L"allow_background_control", false);
    manifest.allowUnrestrictedDesktop = JsonBoolValue(consent, L"allow_unrestricted_desktop", false);

    std::wstring audit = JsonObject(json, L"audit");
    manifest.writeAuditLog = JsonBoolValue(audit, L"write_audit_log", true);
    manifest.writeMarkdownReport = JsonBoolValue(audit, L"write_markdown_report", true);
    manifest.redactClipboardTextInLogs = JsonBoolValue(audit, L"redact_clipboard_text_in_logs", true);

    std::wstring reportPolicy = JsonObject(json, L"report_policy");
    manifest.reportLevel = JsonStringValue(reportPolicy, L"report_level", manifest.reportLevel);
    manifest.evidenceLevel = JsonStringValue(reportPolicy, L"evidence_level", manifest.evidenceLevel);
    manifest.progressOutput = JsonStringValue(reportPolicy, L"progress_output", manifest.progressOutput);
    manifest.stepChatDetail = JsonStringValue(reportPolicy, L"step_chat_detail", manifest.stepChatDetail);
    manifest.artifactEvidence = JsonStringValue(reportPolicy, L"artifact_evidence", manifest.artifactEvidence);
    manifest.failureDetail = JsonStringValue(reportPolicy, L"failure_detail", manifest.failureDetail);

    std::wstring permissionModes = JsonObject(json, L"permission_modes");
    LoadPermissionProfile(JsonObject(permissionModes, L"DEFAULT"), manifest.defaultPermission);
    LoadPermissionProfile(JsonObject(permissionModes, L"PUBLIC_DEFAULT"), manifest.publicDefaultPermission);
    LoadPermissionProfile(JsonObject(permissionModes, L"DEVELOPER_CAPABILITY_DISCOVERY"), manifest.developerPermission);
    LoadPermissionProfile(JsonObject(permissionModes, L"DEVELOPER_FULL_RUNTIME"), manifest.developerPermission);
    LoadPermissionProfile(JsonObject(permissionModes, L"CI_MOCK"), manifest.ciMockPermission);
    LoadPermissionProfile(JsonObject(permissionModes, L"FULL_ACCESS"), manifest.fullAccessPermission);
    manifest.fullAccessPermission.requiresFullAccessSession = true;

    if (manifest.project != L"DesktopVisual") {
        manifest.warnings.push_back(L"Manifest project field does not match DesktopVisual.");
    }
    if (manifest.allowUnrestrictedDesktop) {
        manifest.warnings.push_back(L"Manifest requests unrestricted desktop control; this is denied by runtime policy.");
    }
    return manifest;
}

bool IsDeniedBySafetyManifest(
    const SafetyManifest& manifest,
    const std::wstring& title,
    const std::wstring& process,
    std::wstring& matchedRule,
    std::wstring& matchedCategory) {
    if (IsActiveProtectionText(title, process, matchedCategory)) {
        matchedRule = L"active_protection.signals";
        return true;
    }
    for (const auto& pattern : manifest.deniedWindowTitlePatterns) {
        if (ContainsInsensitive(title, pattern)) {
            matchedRule = L"denied.window_title_patterns";
            matchedCategory = ContainsInsensitive(pattern, L"\u9A8C\u8BC1\u7801") ? L"captcha" : pattern;
            return true;
        }
    }
    for (const auto& deniedProcess : manifest.deniedProcesses) {
        if (ContainsInsensitive(process, deniedProcess)) {
            matchedRule = L"denied.processes";
            matchedCategory = ContainsInsensitive(deniedProcess, L"consent") ? L"admin_elevation" : L"credential";
            return true;
        }
    }
    return false;
}

PolicyCheckDecision EvaluatePolicyCheck(
    const SafetyPolicy& policy,
    const SafetyManifest& manifest,
    const std::wstring& title,
    const std::wstring& process,
    const std::wstring& action,
    const std::wstring& path,
    bool relaxConfiguredBoundary,
    const std::wstring& permissionMode,
    const std::wstring& fullAccessSessionId,
    bool fullAccessSessionActive,
    bool fullAccessSessionExpired,
    const std::wstring& fullAccessScope) {
    PolicyCheckDecision decision;
    decision.title = title;
    decision.process = process;
    decision.action = action;
    decision.path = path;
    decision.permissionMode = permissionMode;
    decision.fullAccessSessionId = fullAccessSessionId;
    decision.fullAccessSessionActive = fullAccessSessionActive;
    decision.fullAccessSessionExpired = fullAccessSessionExpired;
    decision.fullAccessScope = fullAccessScope;
    decision.errorCode = L"SAFETY_POLICY_DENIED";

    if (manifest.requiresExplicitTarget && title.empty()) {
        decision.reason = L"Safety manifest requires an explicit target title.";
        decision.matchedRule = L"consent.requires_explicit_target";
        return decision;
    }
    std::wstring matchedRule, matchedCategory;
    if (IsDeniedBySafetyManifest(manifest, title, process, matchedRule, matchedCategory)) {
        if (matchedRule == L"active_protection.signals") {
            decision.errorCode = L"STOP_ACTIVE_PROTECTION";
        }
        decision.reason = matchedRule == L"active_protection.signals"
            ? L"active_protection_detected"
            : L"Target matches a denied safety manifest category.";
        decision.matchedRule = matchedRule;
        decision.matchedCategory = matchedCategory;
        return decision;
    }
    if (!relaxConfiguredBoundary && !policy.allowedTitles.empty() && !MatchesTitleList(title, policy.allowedTitles)) {
        decision.reason = L"Title is not allowed by safety.conf.";
        decision.matchedRule = L"safety.conf.allowed_titles";
        return decision;
    }
    if (!relaxConfiguredBoundary && !policy.allowedProcesses.empty() && !ListContainsInsensitive(policy.allowedProcesses, process)) {
        decision.reason = L"Process is not allowed by safety.conf.";
        decision.matchedRule = L"safety.conf.allowed_processes";
        return decision;
    }
    if (!relaxConfiguredBoundary && manifest.loaded && !manifest.allowedWindowTitles.empty() && !MatchesTitleList(title, manifest.allowedWindowTitles)) {
        decision.reason = L"Title is not allowed by safety manifest.";
        decision.matchedRule = L"manifest.allowed.window_titles";
        return decision;
    }
    if (!relaxConfiguredBoundary && manifest.loaded && !manifest.allowedProcesses.empty() && !ListContainsInsensitive(manifest.allowedProcesses, process)) {
        decision.reason = L"Process is not allowed by safety manifest.";
        decision.matchedRule = L"manifest.allowed.processes";
        return decision;
    }
    if (!relaxConfiguredBoundary && manifest.loaded && !manifest.allowedActions.empty() && !ListContainsInsensitive(manifest.allowedActions, action)) {
        decision.reason = L"Action is not allowed by safety manifest.";
        decision.matchedRule = L"manifest.allowed.actions";
        return decision;
    }

    decision.allow = true;
    decision.errorCode.clear();
    decision.reason = L"Allowed by safety.conf and safety manifest.";
    decision.matchedRule = L"allow";
    return decision;
}

std::wstring SafetyManifestSummaryJson(const SafetyManifest& manifest) {
    std::wstringstream json;
    json << L"{\"manifest_path\":" << JsonString(manifest.manifestPath)
         << L",\"loaded\":" << (manifest.loaded ? L"true" : L"false")
         << L",\"version\":" << manifest.version
         << L",\"project\":" << JsonString(manifest.project)
         << L",\"mode\":" << JsonString(manifest.mode)
         << L",\"default_permission_mode\":" << JsonString(manifest.defaultPermissionMode)
         << L",\"permission_modes\":{\"DEFAULT\":" << PermissionProfileJson(manifest.defaultPermission)
         << L",\"PUBLIC_DEFAULT\":" << PermissionProfileJson(manifest.publicDefaultPermission)
         << L",\"DEVELOPER_CAPABILITY_DISCOVERY\":" << PermissionProfileJson(manifest.developerPermission)
         << L",\"CI_MOCK\":" << PermissionProfileJson(manifest.ciMockPermission)
         << L",\"FULL_ACCESS\":" << PermissionProfileJson(manifest.fullAccessPermission) << L"}"
         << L",\"allowed_titles\":" << ArrayJson(manifest.allowedWindowTitles)
         << L",\"allowed_processes\":" << ArrayJson(manifest.allowedProcesses)
         << L",\"allowed_actions\":" << ArrayJson(manifest.allowedActions)
         << L",\"denied_categories\":" << ArrayJson(manifest.deniedSensitiveCategories)
         << L",\"runtime_limits\":{\"max_steps\":" << manifest.maxSteps
         << L",\"max_duration_ms\":" << manifest.maxDurationMs
         << L",\"max_recoveries\":" << manifest.maxRecoveries
         << L",\"emergency_stop_key\":" << JsonString(manifest.emergencyStopKey) << L"}"
         << L",\"consent\":{\"requires_explicit_target\":" << (manifest.requiresExplicitTarget ? L"true" : L"false")
         << L",\"requires_visible_foreground_window\":" << (manifest.requiresVisibleForegroundWindow ? L"true" : L"false")
         << L",\"allow_background_control\":" << (manifest.allowBackgroundControl ? L"true" : L"false")
         << L",\"allow_unrestricted_desktop\":" << (manifest.allowUnrestrictedDesktop ? L"true" : L"false") << L"}"
         << L",\"audit\":{\"write_audit_log\":" << (manifest.writeAuditLog ? L"true" : L"false")
         << L",\"write_markdown_report\":" << (manifest.writeMarkdownReport ? L"true" : L"false")
         << L",\"redact_clipboard_text_in_logs\":" << (manifest.redactClipboardTextInLogs ? L"true" : L"false") << L"}"
         << L",\"report_policy\":" << ReportPolicyJson(manifest)
         << L",\"warnings\":" << ArrayJson(manifest.warnings)
         << L"}";
    return json.str();
}

std::wstring SafetyReportDataJson(const SafetyPolicy& policy, const SafetyManifest& manifest) {
    std::wstringstream json;
    json << L"{\"manifest_loaded\":" << (manifest.loaded ? L"true" : L"false")
         << L",\"manifest_path\":" << JsonString(manifest.manifestPath)
         << L",\"safety_conf_loaded\":" << (policy.loaded ? L"true" : L"false")
         << L",\"safety_conf_path\":" << JsonString(policy.configPath)
         << L",\"allowed_titles\":" << ArrayJson(policy.allowedTitles)
         << L",\"allowed_processes\":" << ArrayJson(policy.allowedProcesses)
         << L",\"allowed_read_roots\":" << ArrayJson(policy.allowedReadRoots)
         << L",\"allowed_write_roots\":" << ArrayJson(policy.allowedWriteRoots)
         << L",\"manifest_allowed_titles\":" << ArrayJson(manifest.allowedWindowTitles)
         << L",\"manifest_allowed_processes\":" << ArrayJson(manifest.allowedProcesses)
         << L",\"manifest_allowed_actions\":" << ArrayJson(manifest.allowedActions)
         << L",\"default_permission_mode\":" << JsonString(manifest.defaultPermissionMode)
         << L",\"permission_modes\":{\"DEFAULT\":" << PermissionProfileJson(manifest.defaultPermission)
         << L",\"PUBLIC_DEFAULT\":" << PermissionProfileJson(manifest.publicDefaultPermission)
         << L",\"DEVELOPER_CAPABILITY_DISCOVERY\":" << PermissionProfileJson(manifest.developerPermission)
         << L",\"CI_MOCK\":" << PermissionProfileJson(manifest.ciMockPermission)
         << L",\"FULL_ACCESS\":" << PermissionProfileJson(manifest.fullAccessPermission) << L"}"
         << L",\"public_developer_profile_difference\":" << PublicDeveloperProfileDifferenceJson(manifest)
         << L",\"denied_categories\":" << ArrayJson(manifest.deniedSensitiveCategories)
         << L",\"runtime_limits\":{\"max_steps\":" << (manifest.loaded ? manifest.maxSteps : policy.maxSteps)
         << L",\"max_duration_ms\":" << (manifest.loaded ? manifest.maxDurationMs : policy.maxDurationMs)
         << L",\"max_recoveries\":" << manifest.maxRecoveries
         << L",\"emergency_stop_key\":" << JsonString(manifest.loaded ? manifest.emergencyStopKey : policy.emergencyStopKey) << L"}"
         << L",\"audit_enabled\":" << (manifest.writeAuditLog ? L"true" : L"false")
         << L",\"audit\":{\"write_audit_log\":" << (manifest.writeAuditLog ? L"true" : L"false")
         << L",\"write_markdown_report\":" << (manifest.writeMarkdownReport ? L"true" : L"false")
         << L",\"redact_clipboard_text_in_logs\":" << (manifest.redactClipboardTextInLogs ? L"true" : L"false") << L"}"
         << L",\"report_policy\":" << ReportPolicyJson(manifest)
         << L",\"warnings\":" << ArrayJson(manifest.warnings)
         << L"}";
    return json.str();
}

bool WriteSafetyReportFiles(const SafetyPolicy& policy, const SafetyManifest& manifest, std::wstring& jsonPath, std::wstring& markdownPath, std::wstring& error) {
    std::wstring safetyDir = ArtifactsPath(L"safety");
    EnsureDirectoryPath(safetyDir);
    jsonPath = ArtifactsPath(L"safety\\safety_report.json");
    markdownPath = ArtifactsPath(L"safety\\safety_report.md");
    std::wstring dataJson = SafetyReportDataJson(policy, manifest);
    std::wstring jsonText = L"{\"ok\":true,\"data\":" + dataJson + L"}\n";
    if (!WriteUtf8WideFile(jsonPath, jsonText, error)) return false;

    std::wstringstream md;
    md << L"# DesktopVisual Safety Report\n\n"
       << L"- Manifest loaded: " << (manifest.loaded ? L"true" : L"false") << L"\n"
       << L"- Manifest path: `" << manifest.manifestPath << L"`\n"
       << L"- Safety conf loaded: " << (policy.loaded ? L"true" : L"false") << L"\n"
       << L"- Safety conf path: `" << policy.configPath << L"`\n"
       << L"- Mode: `" << manifest.mode << L"`\n"
       << L"- Emergency stop: `" << (manifest.loaded ? manifest.emergencyStopKey : policy.emergencyStopKey) << L"`\n"
       << L"- Audit enabled: " << (manifest.writeAuditLog ? L"true" : L"false") << L"\n\n"
       << L"## Report Policy\n\n"
       << L"- report_level: `" << manifest.reportLevel << L"`\n"
       << L"- evidence_level: `" << manifest.evidenceLevel << L"`\n"
       << L"- progress_output: `" << manifest.progressOutput << L"`\n"
       << L"- step_chat_detail: `" << manifest.stepChatDetail << L"`\n"
       << L"- artifact_evidence: `" << manifest.artifactEvidence << L"`\n"
       << L"- failure_detail: `" << manifest.failureDetail << L"`\n\n"
       << L"## Allowed Boundary\n\n"
       << L"- Titles: `" << ArrayJson(policy.allowedTitles) << L"`\n"
       << L"- Processes: `" << ArrayJson(policy.allowedProcesses) << L"`\n"
       << L"- Read roots: `" << ArrayJson(policy.allowedReadRoots) << L"`\n"
       << L"- Write roots: `" << ArrayJson(policy.allowedWriteRoots) << L"`\n"
       << L"- Manifest actions: `" << ArrayJson(manifest.allowedActions) << L"`\n\n"
       << L"## Public/Developer Profile Difference\n\n"
       << L"- Ordinary visible capabilities aligned: "
       << (OrdinaryVisibleCapabilitiesAligned(manifest.publicDefaultPermission, manifest.developerPermission) ? L"true" : L"false") << L"\n"
       << L"- Public requires full access session: " << (manifest.publicDefaultPermission.requiresFullAccessSession ? L"true" : L"false") << L"\n"
       << L"- Developer requires full access session: " << (manifest.developerPermission.requiresFullAccessSession ? L"true" : L"false") << L"\n"
       << L"- Boundary: public allows ordinary visible app/web/IDE/Explorer/localhost workflows and stops on real active protection or security interception.\n\n"
       << L"## Denied Categories\n\n";
    for (const auto& category : manifest.deniedSensitiveCategories) {
        md << L"- `" << category << L"`\n";
    }
    md << L"\n## Warnings\n\n";
    if (manifest.warnings.empty()) {
        md << L"- none\n";
    } else {
        for (const auto& warning : manifest.warnings) md << L"- " << warning << L"\n";
    }
    return WriteUtf8WideFile(markdownPath, md.str(), error);
}
