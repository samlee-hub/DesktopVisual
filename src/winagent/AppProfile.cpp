#include "AppProfile.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring ToLowerLocal(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

std::wstring TrimLocal(std::wstring value) {
    while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
    while (!value.empty() && iswspace(value.back())) value.pop_back();
    return value;
}

bool ContainsKey(const std::wstring& json, const std::wstring& key) {
    return json.find(L"\"" + key + L"\"") != std::wstring::npos;
}

size_t FindValueStart(const std::wstring& json, const std::wstring& key) {
    size_t pos = json.find(L"\"" + key + L"\"");
    if (pos == std::wstring::npos) return std::wstring::npos;
    pos = json.find(L":", pos);
    if (pos == std::wstring::npos) return std::wstring::npos;
    ++pos;
    while (pos < json.size() && iswspace(json[pos])) ++pos;
    return pos;
}

std::wstring JsonStringValueLocal(const std::wstring& json, const std::wstring& key) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'"') return L"";
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
    return TrimLocal(value);
}

std::wstring RawValueLocal(const std::wstring& json, const std::wstring& key) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos) return L"";
    wchar_t open = json[pos];
    wchar_t close = open == L'[' ? L']' : (open == L'{' ? L'}' : L'\0');
    if (!close) return L"";
    int depth = 0;
    bool inString = false;
    for (size_t i = pos; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (ch == L'"' && (i == pos || json[i - 1] != L'\\')) inString = !inString;
        if (inString) continue;
        if (ch == open) ++depth;
        if (ch == close) {
            --depth;
            if (depth == 0) return json.substr(pos, i - pos + 1);
        }
    }
    return L"";
}

std::vector<std::wstring> ObjectArrayLocal(const std::wstring& arrayRaw) {
    std::vector<std::wstring> objects;
    bool inString = false;
    int depth = 0;
    size_t start = std::wstring::npos;
    for (size_t i = 0; i < arrayRaw.size(); ++i) {
        wchar_t ch = arrayRaw[i];
        if (ch == L'"' && (i == 0 || arrayRaw[i - 1] != L'\\')) inString = !inString;
        if (inString) continue;
        if (ch == L'{') {
            if (depth == 0) start = i;
            ++depth;
        } else if (ch == L'}') {
            --depth;
            if (depth == 0 && start != std::wstring::npos) {
                objects.push_back(arrayRaw.substr(start, i - start + 1));
                start = std::wstring::npos;
            }
        }
    }
    return objects;
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring StringVectorJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::vector<std::wstring> EnumerateProfileFiles(const std::wstring& root) {
    std::vector<std::wstring> files;
    DWORD attrs = GetFileAttributesW(root.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) return files;
    if ((attrs & FILE_ATTRIBUTE_DIRECTORY) == 0) {
        files.push_back(root);
        return files;
    }
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW((root + L"\\*.profile.json").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return files;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            files.push_back(root + L"\\" + data.cFileName);
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);
    std::sort(files.begin(), files.end());
    return files;
}

void ValidateProfile(AppProfile& profile, const std::wstring& json) {
    const wchar_t* required[] = {
        L"profile_name",
        L"app_kind",
        L"process_match",
        L"title_match",
        L"allowed_window_scope",
        L"common_locators",
        L"roi_definitions",
        L"visual_strategy",
        L"ocr_strategy",
        L"recovery_strategy",
        L"safety_overrides",
        L"task_templates",
        L"confirmation_nodes",
        L"version",
        L"notes"
    };
    for (const wchar_t* key : required) {
        if (!ContainsKey(json, key)) {
            profile.errors.push_back(L"Missing required field: " + std::wstring(key));
        }
    }
    if (profile.profileName.empty()) profile.errors.push_back(L"profile_name cannot be empty.");
    if (profile.allowedWindowScope.empty()) profile.errors.push_back(L"allowed_window_scope cannot be empty.");
    if (profile.commonLocators.empty()) profile.warnings.push_back(L"No common_locators were defined.");
    std::wstring safety = ToLowerLocal(RawValueLocal(json, L"safety_overrides"));
    if (safety.find(L"allow") != std::wstring::npos && safety.find(L"true") != std::wstring::npos) {
        profile.warnings.push_back(L"safety_overrides are adapter metadata only and cannot loosen Safety Manifest.");
    }
    profile.valid = profile.errors.empty();
}

}  // namespace

std::wstring ProfilesRootPath() {
    return ProjectPath(L"profiles");
}

AppProfile LoadAppProfileFile(const std::wstring& path) {
    AppProfile profile;
    profile.path = path;
    FileReadResult read = ReadTextFile(path);
    if (!read.ok) {
        profile.errors.push_back(read.error.empty() ? L"Profile file could not be read." : read.error);
        return profile;
    }
    std::wstring json = read.content;
    profile.profileName = JsonStringValueLocal(json, L"profile_name");
    profile.appKind = JsonStringValueLocal(json, L"app_kind");
    profile.processMatch = JsonStringValueLocal(json, L"process_match");
    profile.titleMatch = JsonStringValueLocal(json, L"title_match");
    profile.windowClassMatch = JsonStringValueLocal(json, L"window_class_match");
    profile.allowedWindowScope = JsonStringValueLocal(json, L"allowed_window_scope");
    profile.version = JsonStringValueLocal(json, L"version");
    profile.notes = JsonStringValueLocal(json, L"notes");
    profile.hasRoiDefinitions = !RawValueLocal(json, L"roi_definitions").empty();
    profile.hasVisualStrategy = !RawValueLocal(json, L"visual_strategy").empty();
    profile.hasOcrStrategy = !RawValueLocal(json, L"ocr_strategy").empty();
    profile.hasRecoveryStrategy = !RawValueLocal(json, L"recovery_strategy").empty();
    profile.hasSafetyOverrides = !RawValueLocal(json, L"safety_overrides").empty();
    profile.hasTaskTemplates = !RawValueLocal(json, L"task_templates").empty();
    profile.hasConfirmationNodes = !RawValueLocal(json, L"confirmation_nodes").empty();

    for (const auto& obj : ObjectArrayLocal(RawValueLocal(json, L"common_locators"))) {
        ProfileLocator locator;
        locator.name = JsonStringValueLocal(obj, L"name");
        locator.selector = JsonStringValueLocal(obj, L"selector");
        locator.semanticStatus = JsonStringValueLocal(obj, L"semantic_status");
        locator.riskStatus = JsonStringValueLocal(obj, L"risk_status");
        if (locator.semanticStatus.empty()) locator.semanticStatus = L"resolved";
        if (locator.riskStatus.empty()) locator.riskStatus = L"normal";
        if (!locator.name.empty() && !locator.selector.empty()) {
            profile.commonLocators.push_back(locator);
        }
    }

    ValidateProfile(profile, json);
    return profile;
}

ProfileLoadReport LoadAppProfiles(const std::wstring& path) {
    ProfileLoadReport report;
    std::wstring root = path.empty() ? ProfilesRootPath() : path;
    for (const auto& file : EnumerateProfileFiles(root)) {
        AppProfile profile = LoadAppProfileFile(file);
        if (profile.valid) ++report.loadedCount;
        else ++report.invalidCount;
        report.profiles.push_back(profile);
    }
    return report;
}

bool ResolveProfileLocator(
    const std::wstring& profileName,
    const std::wstring& locatorName,
    AppProfile& profile,
    ProfileLocator& locator,
    std::wstring& error) {
    if (profileName.empty()) {
        error = L"profile name is required.";
        return false;
    }
    ProfileLoadReport report = LoadAppProfiles(L"");
    for (const auto& item : report.profiles) {
        if (!item.valid) continue;
        if (ToLowerLocal(item.profileName) != ToLowerLocal(profileName)) continue;
        profile = item;
        for (const auto& candidate : item.commonLocators) {
            if (ToLowerLocal(candidate.name) == ToLowerLocal(locatorName)) {
                locator = candidate;
                return true;
            }
        }
        error = L"profile locator was not found.";
        return false;
    }
    error = L"profile was not found or was invalid.";
    return false;
}

std::wstring ProfileLocatorCandidateJson(const AppProfile& profile, const ProfileLocator& locator) {
    std::wstringstream json;
    json << L"{\"source\":\"app_profile\""
         << L",\"profile_name\":" << JsonString(profile.profileName)
         << L",\"locator_name\":" << JsonString(locator.name)
         << L",\"selector\":" << JsonString(locator.selector)
         << L",\"semantic_status\":" << JsonString(locator.semanticStatus)
         << L",\"risk_status\":" << JsonString(locator.riskStatus)
         << L",\"action_gate\":\"requires_runtime_safety_policy\"}";
    return json.str();
}

std::wstring ProfileLoadReportJson(const ProfileLoadReport& report) {
    std::wstringstream json;
    json << L"{\"profiles_root\":" << JsonString(ProfilesRootPath())
         << L",\"loaded_count\":" << report.loadedCount
         << L",\"invalid_count\":" << report.invalidCount
         << L",\"profiles\":[";
    for (size_t i = 0; i < report.profiles.size(); ++i) {
        if (i != 0) json << L",";
        const auto& profile = report.profiles[i];
        json << L"{\"path\":" << JsonString(profile.path)
             << L",\"profile_name\":" << JsonString(profile.profileName)
             << L",\"app_kind\":" << JsonString(profile.appKind)
             << L",\"process_match\":" << JsonString(profile.processMatch)
             << L",\"title_match\":" << JsonString(profile.titleMatch)
             << L",\"window_class_match\":" << JsonString(profile.windowClassMatch)
             << L",\"allowed_window_scope\":" << JsonString(profile.allowedWindowScope)
             << L",\"version\":" << JsonString(profile.version)
             << L",\"valid\":" << BoolJson(profile.valid)
             << L",\"errors\":" << StringVectorJson(profile.errors)
             << L",\"warnings\":" << StringVectorJson(profile.warnings)
             << L",\"common_locator_count\":" << profile.commonLocators.size()
             << L",\"effective_capabilities\":{"
             << L"\"common_locators\":" << BoolJson(!profile.commonLocators.empty())
             << L",\"roi_definitions\":" << BoolJson(profile.hasRoiDefinitions)
             << L",\"visual_strategy\":" << BoolJson(profile.hasVisualStrategy)
             << L",\"ocr_strategy\":" << BoolJson(profile.hasOcrStrategy)
             << L",\"recovery_strategy\":" << BoolJson(profile.hasRecoveryStrategy)
             << L",\"task_templates\":" << BoolJson(profile.hasTaskTemplates)
             << L",\"confirmation_nodes\":" << BoolJson(profile.hasConfirmationNodes)
             << L",\"can_override_safety_manifest\":false}"
             << L"}";
    }
    json << L"]}";
    return json.str();
}
