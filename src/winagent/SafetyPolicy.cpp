#include "SafetyPolicy.h"

#include "ProjectRoot.h"
#include "SafetyManifest.h"
#include "Trace.h"
#include "UserAbortController.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <sstream>

namespace {

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) {
        return L"";
    }
    int required = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (required <= 0) {
        required = MultiByteToWideChar(CP_ACP, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
        if (required <= 0) {
            return L"";
        }
        std::wstring fallback(static_cast<size_t>(required), L'\0');
        MultiByteToWideChar(CP_ACP, 0, value.data(), static_cast<int>(value.size()), fallback.data(), required);
        return fallback;
    }

    std::wstring result(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), required);
    return result;
}

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && (iswspace(value[first]) || value[first] == 0xFEFF)) {
        ++first;
    }
    size_t last = value.size();
    while (last > first && iswspace(value[last - 1])) {
        --last;
    }
    return value.substr(first, last - first);
}

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

std::vector<std::wstring> SplitList(const std::wstring& value) {
    std::vector<std::wstring> items;
    size_t start = 0;
    while (start <= value.size()) {
        size_t end = value.find(L';', start);
        std::wstring item = Trim(value.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start));
        if (!item.empty()) {
            items.push_back(item);
        }
        if (end == std::wstring::npos) {
            break;
        }
        start = end + 1;
    }
    return items;
}

bool ParseInt(const std::wstring& value, int& parsed) {
    try {
        size_t consumed = 0;
        parsed = std::stoi(value, &consumed, 10);
        return consumed == value.size();
    } catch (...) {
        return false;
    }
}

std::wstring DefaultConfigPath() {
    wchar_t buffer[MAX_PATH] = {};
    DWORD len = GetEnvironmentVariableW(L"DESKTOPVISUAL_SAFETY_CONFIG", buffer, MAX_PATH);
    if (len > 0 && len < MAX_PATH) {
        return buffer;
    }
    return ConfigPath(L"safety.conf");
}

std::wstring ReplaceAll(std::wstring value, const std::wstring& needle, const std::wstring& replacement) {
    size_t pos = 0;
    while ((pos = value.find(needle, pos)) != std::wstring::npos) {
        value.replace(pos, needle.size(), replacement);
        pos += replacement.size();
    }
    return value;
}

std::wstring ExpandConfigVariables(const std::wstring& value) {
    std::wstring expanded = ReplaceAll(value, L"${PROJECT_ROOT}", ProjectRootPath());
    expanded = ReplaceAll(expanded, L"%PROJECT_ROOT%", ProjectRootPath());
    return expanded;
}

std::wstring Basename(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return path;
    }
    return path.substr(slash + 1);
}

std::wstring ProcessNameFromPid(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) {
        return L"";
    }
    wchar_t path[MAX_PATH] = {};
    DWORD size = MAX_PATH;
    std::wstring name;
    if (QueryFullProcessImageNameW(process, 0, path, &size) && size > 0) {
        name = Basename(path);
    }
    CloseHandle(process);
    return name;
}

bool HasParentTraversal(const std::wstring& path) {
    std::wstring normalizedSeparators = path;
    std::replace(normalizedSeparators.begin(), normalizedSeparators.end(), L'/', L'\\');
    if (normalizedSeparators == L"..") {
        return true;
    }
    return normalizedSeparators.rfind(L"..\\", 0) == 0 ||
           normalizedSeparators.find(L"\\..\\") != std::wstring::npos ||
           (normalizedSeparators.size() >= 3 &&
            normalizedSeparators.compare(normalizedSeparators.size() - 3, 3, L"\\..") == 0);
}

bool NormalizeFullPath(const std::wstring& path, std::wstring& normalized, std::wstring& errorMessage) {
    if (path.empty()) {
        errorMessage = L"Path is required.";
        return false;
    }
    if (HasParentTraversal(path)) {
        errorMessage = L"Path traversal is not allowed.";
        return false;
    }
    DWORD required = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (required == 0) {
        errorMessage = L"Could not normalize path.";
        return false;
    }
    std::wstring buffer(required, L'\0');
    DWORD written = GetFullPathNameW(path.c_str(), required, buffer.data(), nullptr);
    if (written == 0 || written >= required) {
        errorMessage = L"Could not normalize path.";
        return false;
    }
    buffer.resize(written);
    while (!buffer.empty() && (buffer.back() == L'\\' || buffer.back() == L'/')) {
        buffer.pop_back();
    }
    normalized = buffer;
    return true;
}

bool IsPathUnderRoot(const std::wstring& path, const std::wstring& root) {
    std::wstring normalizedPath = ToLower(path);
    std::wstring normalizedRoot = ToLower(root);
    std::replace(normalizedPath.begin(), normalizedPath.end(), L'/', L'\\');
    std::replace(normalizedRoot.begin(), normalizedRoot.end(), L'/', L'\\');
    while (!normalizedRoot.empty() && normalizedRoot.back() == L'\\') {
        normalizedRoot.pop_back();
    }
    if (normalizedPath == normalizedRoot) {
        return true;
    }
    return normalizedPath.size() > normalizedRoot.size() &&
           normalizedPath.rfind(normalizedRoot, 0) == 0 &&
           normalizedPath[normalizedRoot.size()] == L'\\';
}

bool IsPathAllowedByRoots(const std::wstring& path, const std::vector<std::wstring>& roots, std::wstring& normalizedPath, std::wstring& errorMessage) {
    if (!NormalizeFullPath(path, normalizedPath, errorMessage)) {
        return false;
    }
    for (const auto& root : roots) {
        std::wstring normalizedRoot;
        std::wstring rootError;
        if (NormalizeFullPath(root, normalizedRoot, rootError) && IsPathUnderRoot(normalizedPath, normalizedRoot)) {
            return true;
        }
    }
    errorMessage = L"Path is outside the configured safety roots.";
    return false;
}

bool MatchesAllowedTitle(const std::wstring& requestedTitle, const std::wstring& actualTitle, const std::vector<std::wstring>& allowedTitles) {
    std::wstring requested = ToLower(requestedTitle);
    std::wstring actual = ToLower(actualTitle);
    for (const auto& item : allowedTitles) {
        std::wstring allowed = ToLower(item);
        if (requested == allowed || actual == allowed) {
            return true;
        }
        if (!allowed.empty() && (requested.find(allowed) != std::wstring::npos || actual.find(allowed) != std::wstring::npos)) {
            return true;
        }
    }
    return false;
}

bool MatchesAllowedProcess(const std::wstring& processName, const std::vector<std::wstring>& allowedProcesses) {
    std::wstring actual = ToLower(processName);
    for (const auto& item : allowedProcesses) {
        if (actual == ToLower(item)) {
            return true;
        }
    }
    return false;
}

int VirtualKeyForSafetyKey(const std::wstring& key) {
    std::wstring upper = ToLower(key);
    if (upper == L"f12") return VK_F12;
    if (upper == L"f11") return VK_F11;
    if (upper == L"esc" || upper == L"escape") return VK_ESCAPE;
    return VK_F12;
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) {
            json << L",";
        }
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

}  // namespace

SafetyPolicy LoadSafetyPolicy() {
    SafetyPolicy policy;
    policy.configPath = DefaultConfigPath();
    policy.allowedReadRoots = {
        ProjectRootPath(),
        ArtifactsPath(),
        ProjectPath(L"cases"),
        ProjectPath(L"tasks")
    };
    policy.allowedWriteRoots = {
        ArtifactsPath(),
        ConfigPath()
    };

    FILE* file = nullptr;
    if (_wfopen_s(&file, policy.configPath.c_str(), L"rb") != 0 || !file) {
        policy.warnings.push_back(L"Safety config was not found; only explicit --title scoped actions are allowed.");
        return policy;
    }

    std::string bytes;
    char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) {
            bytes.append(buffer, read);
        }
        if (read < sizeof(buffer)) {
            break;
        }
    }
    fclose(file);

    std::wistringstream lines(Utf8ToWide(bytes));
    std::wstring line;
    while (std::getline(lines, line)) {
        line = Trim(line);
        if (line.empty() || line[0] == L'#') {
            continue;
        }
        size_t equals = line.find(L'=');
        if (equals == std::wstring::npos) {
            policy.warnings.push_back(L"Ignored malformed safety config line.");
            continue;
        }
        std::wstring key = Trim(line.substr(0, equals));
        std::wstring value = ExpandConfigVariables(Trim(line.substr(equals + 1)));
        if (key == L"allowed_titles") {
            policy.allowedTitles = SplitList(value);
        } else if (key == L"allowed_processes") {
            policy.allowedProcesses = SplitList(value);
        } else if (key == L"allowed_read_roots") {
            policy.allowedReadRoots = SplitList(value);
        } else if (key == L"allowed_write_roots") {
            policy.allowedWriteRoots = SplitList(value);
        } else if (key == L"max_steps") {
            int parsed = 0;
            if (ParseInt(value, parsed) && parsed > 0 && parsed <= 1000) {
                policy.maxSteps = parsed;
            }
        } else if (key == L"max_duration_ms") {
            int parsed = 0;
            if (ParseInt(value, parsed) && parsed > 0 && parsed <= 3600000) {
                policy.maxDurationMs = parsed;
            }
        } else if (key == L"emergency_stop_key") {
            policy.emergencyStopKey = value.empty() ? L"F12" : value;
            policy.emergencyStopVk = VirtualKeyForSafetyKey(policy.emergencyStopKey);
        } else if (key == L"allow_absolute_screen_click") {
            policy.allowAbsoluteScreenClick = (ToLower(value) == L"true" || value == L"1");
        }
    }

    policy.loaded = true;
    if (policy.allowedTitles.empty()) {
        policy.warnings.push_back(L"allowed_titles is empty; action commands still require explicit --title.");
    }
    if (policy.allowedProcesses.empty()) {
        policy.warnings.push_back(L"allowed_processes is empty; process whitelist is not enforced.");
    }
    if (policy.allowedReadRoots.empty()) {
        policy.warnings.push_back(L"allowed_read_roots is empty; file reads are denied.");
    }
    if (policy.allowedWriteRoots.empty()) {
        policy.warnings.push_back(L"allowed_write_roots is empty; file writes should stay inside approved roots.");
    }
    return policy;
}

SafetyCheckResult CheckWindowSafety(const WindowInfo& window, const std::wstring& requestedTitle) {
    SafetyCheckResult result;
    SafetyPolicy policy = LoadSafetyPolicy();
    SafetyManifest manifest = LoadSafetyManifest();
    result.processName = ProcessNameFromPid(window.pid);
    if (!policy.warnings.empty()) {
        result.warning = policy.warnings.front();
    } else if (!manifest.warnings.empty()) {
        result.warning = manifest.warnings.front();
    }

    if (requestedTitle.empty()) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.message = L"Safety policy requires an explicit target window title.";
        return result;
    }

    std::wstring matchedRule;
    std::wstring matchedCategory;
    if (IsDeniedBySafetyManifest(manifest, window.title.empty() ? requestedTitle : window.title, result.processName, matchedRule, matchedCategory)) {
        result.errorCode = matchedRule == L"active_protection.signals" ? L"STOP_ACTIVE_PROTECTION" : L"SAFETY_POLICY_DENIED";
        result.message = L"Target matches denied safety manifest category: " + matchedCategory + L".";
        return result;
    }

    if (!policy.allowedTitles.empty() && !MatchesAllowedTitle(requestedTitle, window.title, policy.allowedTitles)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.message = L"Target window title is not allowed by safety policy.";
        return result;
    }

    if (!policy.allowedProcesses.empty() && !MatchesAllowedProcess(result.processName, policy.allowedProcesses)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.message = L"Target process is not allowed by safety policy.";
        return result;
    }

    if (manifest.loaded && !manifest.allowedWindowTitles.empty() && !MatchesAllowedTitle(requestedTitle, window.title, manifest.allowedWindowTitles)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.message = L"Target window title is not allowed by safety manifest.";
        return result;
    }

    if (manifest.loaded && !manifest.allowedProcesses.empty() && !MatchesAllowedProcess(result.processName, manifest.allowedProcesses)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.message = L"Target process is not allowed by safety manifest.";
        return result;
    }

    result.ok = true;
    return result;
}

std::wstring ProcessNameForPid(DWORD pid) {
    return ProcessNameFromPid(pid);
}

bool IsReadPathAllowed(const std::wstring& path, std::wstring& normalizedPath, std::wstring& errorMessage) {
    SafetyPolicy policy = LoadSafetyPolicy();
    if (!IsPathAllowedByRoots(path, policy.allowedReadRoots, normalizedPath, errorMessage)) {
        return false;
    }
    SafetyManifest manifest = LoadSafetyManifest();
    if (manifest.loaded && !manifest.allowedReadRoots.empty()) {
        std::wstring manifestNormalized;
        if (!IsPathAllowedByRoots(normalizedPath, manifest.allowedReadRoots, manifestNormalized, errorMessage)) {
            errorMessage = L"Path is outside the safety manifest read roots.";
            return false;
        }
    }
    return true;
}

bool IsWritePathAllowed(const std::wstring& path, std::wstring& normalizedPath, std::wstring& errorMessage) {
    SafetyPolicy policy = LoadSafetyPolicy();
    if (!IsPathAllowedByRoots(path, policy.allowedWriteRoots, normalizedPath, errorMessage)) {
        return false;
    }
    SafetyManifest manifest = LoadSafetyManifest();
    if (manifest.loaded && !manifest.allowedWriteRoots.empty()) {
        std::wstring manifestNormalized;
        if (!IsPathAllowedByRoots(normalizedPath, manifest.allowedWriteRoots, manifestNormalized, errorMessage)) {
            errorMessage = L"Path is outside the safety manifest write roots.";
            return false;
        }
    }
    return true;
}

bool IsEmergencyStopPressed() {
    return IsUserAbortRequested();
}

std::wstring SafetyPolicySummaryJson(const SafetyPolicy& policy) {
    std::wstringstream json;
    json << L"{\"config_path\":" << JsonString(policy.configPath)
         << L",\"loaded\":" << (policy.loaded ? L"true" : L"false")
         << L",\"allowed_titles\":" << StringArrayJson(policy.allowedTitles)
         << L",\"allowed_processes\":" << StringArrayJson(policy.allowedProcesses)
         << L",\"allowed_read_roots\":" << StringArrayJson(policy.allowedReadRoots)
         << L",\"allowed_write_roots\":" << StringArrayJson(policy.allowedWriteRoots)
         << L",\"max_steps\":" << policy.maxSteps
         << L",\"max_duration_ms\":" << policy.maxDurationMs
         << L",\"emergency_stop_key\":" << JsonString(policy.emergencyStopKey)
         << L",\"allow_absolute_screen_click\":" << (policy.allowAbsoluteScreenClick ? L"true" : L"false")
         << L"}";
    return json.str();
}
