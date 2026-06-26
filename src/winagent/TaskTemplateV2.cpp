#include "TaskTemplateV2.h"

#include "AppProfile.h"
#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <algorithm>
#include <cwctype>
#include <sstream>
#include <vector>

namespace {

struct TemplateParameterV2 {
    std::wstring name;
    std::wstring type;
    bool required = false;
};

struct TemplateStepV2 {
    std::wstring stepId;
    std::wstring action;
    std::wstring locatorRef;
    std::wstring roiRef;
    std::wstring confirmationNode;
    std::vector<std::wstring> usesParameters;
};

struct ParsedTemplateV2 {
    std::wstring path;
    std::wstring content;
    std::wstring schemaVersion;
    std::wstring runtimeVersion;
    std::wstring protocolVersion;
    std::wstring templateId;
    std::wstring requiredProfile;
    std::wstring parametersRaw;
    std::wstring statesRaw;
    std::wstring stepsRaw;
    std::wstring preconditionsRaw;
    std::wstring verificationRaw;
    std::wstring recoveryRaw;
    std::wstring confirmationNodesRaw;
    std::wstring finalStatePolicyRaw;
    bool allowUnrestrictedDesktop = false;
    std::vector<TemplateParameterV2> parameters;
    std::vector<TemplateStepV2> steps;
};

std::wstring Trim(std::wstring value) {
    while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
    while (!value.empty() && iswspace(value.back())) value.pop_back();
    return value;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    return value.size() >= prefix.size() && Lower(value.substr(0, prefix.size())) == Lower(prefix);
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

std::wstring JsonStringValue(const std::wstring& json, const std::wstring& key) {
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
    return Trim(value);
}

bool JsonBoolValue(const std::wstring& json, const std::wstring& key, bool def = false) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos) return def;
    if (json.substr(pos, 4) == L"true") return true;
    if (json.substr(pos, 5) == L"false") return false;
    std::wstring quoted = Lower(JsonStringValue(json, key));
    if (quoted == L"true" || quoted == L"1") return true;
    if (quoted == L"false" || quoted == L"0") return false;
    return def;
}

std::wstring RawValue(const std::wstring& json, const std::wstring& key) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size()) return L"";
    wchar_t open = json[pos];
    wchar_t close = open == L'[' ? L']' : (open == L'{' ? L'}' : L'\0');
    if (!close) return L"";
    int depth = 0;
    bool inString = false;
    for (size_t i = pos; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (ch == L'"' && (i == 0 || json[i - 1] != L'\\')) inString = !inString;
        if (inString) continue;
        if (ch == open) ++depth;
        if (ch == close) {
            --depth;
            if (depth == 0) return json.substr(pos, i - pos + 1);
        }
    }
    return L"";
}

std::vector<std::wstring> ObjectArray(const std::wstring& arrayRaw) {
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

std::vector<std::wstring> StringArray(const std::wstring& arrayRaw) {
    std::vector<std::wstring> values;
    if (arrayRaw.empty() || arrayRaw.front() != L'[') return values;
    size_t pos = 1;
    while (pos < arrayRaw.size()) {
        while (pos < arrayRaw.size() && (iswspace(arrayRaw[pos]) || arrayRaw[pos] == L',')) ++pos;
        if (pos >= arrayRaw.size() || arrayRaw[pos] == L']') break;
        if (arrayRaw[pos] != L'"') {
            ++pos;
            continue;
        }
        ++pos;
        std::wstring value;
        while (pos < arrayRaw.size() && arrayRaw[pos] != L'"') {
            if (arrayRaw[pos] == L'\\' && pos + 1 < arrayRaw.size()) ++pos;
            value += arrayRaw[pos++];
        }
        values.push_back(value);
        if (pos < arrayRaw.size()) ++pos;
    }
    return values;
}

std::wstring RawOr(const std::wstring& raw, const std::wstring& fallback) {
    return raw.empty() ? fallback : raw;
}

TaskTemplateV2OperationResult Failure(const std::wstring& code, const std::wstring& message, const std::wstring& data = L"{}") {
    TaskTemplateV2OperationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = data;
    return result;
}

bool IsSafeTemplateId(const std::wstring& value) {
    if (value.empty()) return false;
    for (wchar_t ch : value) {
        bool ok = (ch >= L'a' && ch <= L'z') || (ch >= L'0' && ch <= L'9') || ch == L'_';
        if (!ok) return false;
    }
    return true;
}

std::wstring ValidationDataJson(const ParsedTemplateV2& t) {
    std::wstringstream data;
    data << L"{\"schema_version\":" << JsonString(t.schemaVersion)
         << L",\"runtime_version\":" << JsonString(t.runtimeVersion)
         << L",\"protocol_version\":" << JsonString(t.protocolVersion)
         << L",\"template_id\":" << JsonString(t.templateId)
         << L",\"required_profile\":" << JsonString(t.requiredProfile)
         << L",\"parameters\":" << RawOr(t.parametersRaw, L"[]")
         << L",\"parameter_count\":" << t.parameters.size()
         << L",\"state_count\":" << StringArray(t.statesRaw).size()
         << L",\"steps\":" << RawOr(t.stepsRaw, L"[]")
         << L",\"step_count\":" << t.steps.size()
         << L",\"states\":" << RawOr(t.statesRaw, L"[]")
         << L",\"preconditions\":" << RawOr(t.preconditionsRaw, L"[]")
         << L",\"verification\":" << RawOr(t.verificationRaw, L"{}")
         << L",\"recovery\":" << RawOr(t.recoveryRaw, L"{}")
         << L",\"confirmation_nodes\":" << RawOr(t.confirmationNodesRaw, L"[]")
         << L",\"final_state_policy\":" << RawOr(t.finalStatePolicyRaw, L"{}")
         << L",\"allow_unrestricted_desktop\":" << (t.allowUnrestrictedDesktop ? L"true" : L"false")
         << L",\"safety\":{\"profile_can_override_safety\":false,\"no_fixed_coordinates\":true,\"resolver_executes_actions\":false}"
         << L"}";
    return data.str();
}

bool IsSupportedParameterType(const std::wstring& type) {
    return type == L"string" ||
           type == L"path" ||
           type == L"local_url" ||
           type == L"roi";
}

TaskTemplateV2OperationResult ParseTemplateFile(const std::wstring& path, ParsedTemplateV2& t) {
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        return Failure(file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode, L"Could not read Task Template v2 file: " + file.error, L"{\"file\":" + JsonString(path) + L"}");
    }

    t.path = path;
    t.content = file.content;
    t.schemaVersion = JsonStringValue(t.content, L"schema_version");
    t.runtimeVersion = JsonStringValue(t.content, L"runtime_version");
    t.protocolVersion = JsonStringValue(t.content, L"protocol_version");
    t.templateId = JsonStringValue(t.content, L"template_id");
    t.requiredProfile = JsonStringValue(t.content, L"required_profile");
    t.parametersRaw = RawValue(t.content, L"parameters");
    t.statesRaw = RawValue(t.content, L"states");
    t.stepsRaw = RawValue(t.content, L"steps");
    t.preconditionsRaw = RawValue(t.content, L"preconditions");
    t.verificationRaw = RawValue(t.content, L"verification");
    t.recoveryRaw = RawValue(t.content, L"recovery");
    t.confirmationNodesRaw = RawValue(t.content, L"confirmation_nodes");
    t.finalStatePolicyRaw = RawValue(t.content, L"final_state_policy");
    t.allowUnrestrictedDesktop = JsonBoolValue(t.content, L"allow_unrestricted_desktop", false);

    for (const auto& obj : ObjectArray(t.parametersRaw)) {
        TemplateParameterV2 p;
        p.name = JsonStringValue(obj, L"name");
        p.type = JsonStringValue(obj, L"type");
        p.required = JsonBoolValue(obj, L"required", false);
        if (!p.name.empty()) t.parameters.push_back(p);
    }
    for (const auto& obj : ObjectArray(t.stepsRaw)) {
        TemplateStepV2 s;
        s.stepId = JsonStringValue(obj, L"step_id");
        s.action = JsonStringValue(obj, L"action");
        s.locatorRef = JsonStringValue(obj, L"locator_ref");
        s.roiRef = JsonStringValue(obj, L"roi_ref");
        s.confirmationNode = JsonStringValue(obj, L"confirmation_node");
        s.usesParameters = StringArray(RawValue(obj, L"uses_parameters"));
        if (!s.stepId.empty()) t.steps.push_back(s);
    }

    if (t.schemaVersion != L"5.4.1") return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 schema_version must be 5.4.1.", ValidationDataJson(t));
    if (t.runtimeVersion.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: runtime_version.", ValidationDataJson(t));
    if (t.protocolVersion != L"5.4") return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 protocol_version must be 5.4.", ValidationDataJson(t));
    if (!IsSafeTemplateId(t.templateId)) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 template_id is required and must use lowercase letters, digits, or underscore.", ValidationDataJson(t));
    if (t.requiredProfile.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: required_profile.", ValidationDataJson(t));
    if (!ContainsKey(t.content, L"parameters") || t.parametersRaw.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: parameters.", ValidationDataJson(t));
    for (const auto& p : t.parameters) {
        if (!IsSafeTemplateId(p.name)) {
            return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 parameter name is required and must use lowercase letters, digits, or underscore.", ValidationDataJson(t));
        }
        if (!IsSupportedParameterType(p.type)) {
            return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 parameter has unsupported type: " + p.name, L"{\"template_id\":" + JsonString(t.templateId) + L",\"parameter\":" + JsonString(p.name) + L",\"type\":" + JsonString(p.type) + L"}");
        }
    }
    if (StringArray(t.statesRaw).empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 states must include at least one state.", ValidationDataJson(t));
    if (t.steps.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 steps must include at least one step.", ValidationDataJson(t));
    if (!ContainsKey(t.content, L"preconditions") || t.preconditionsRaw.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: preconditions.", ValidationDataJson(t));
    if (t.verificationRaw.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: verification.", ValidationDataJson(t));
    if (t.recoveryRaw.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: recovery.", ValidationDataJson(t));
    if (!ContainsKey(t.content, L"confirmation_nodes") || t.confirmationNodesRaw.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: confirmation_nodes.", ValidationDataJson(t));
    if (t.finalStatePolicyRaw.empty()) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 missing required field: final_state_policy.", ValidationDataJson(t));
    if (t.allowUnrestrictedDesktop) return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 cannot set allow_unrestricted_desktop=true.", ValidationDataJson(t));
    if (JsonBoolValue(t.finalStatePolicyRaw, L"profile_can_override_safety", false)) {
        return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"final_state_policy.profile_can_override_safety must be false.", ValidationDataJson(t));
    }
    if (t.content.find(L"coord:") != std::wstring::npos || t.content.find(L"fixed_coordinate") != std::wstring::npos) {
        return Failure(L"TASK_TEMPLATE_V2_SCHEMA_INVALID", L"TaskTemplateV2 must not use fixed coordinate selectors.", ValidationDataJson(t));
    }

    TaskTemplateV2OperationResult ok;
    ok.ok = true;
    ok.dataJson = ValidationDataJson(t);
    return ok;
}

bool ParameterValue(const std::wstring& paramsJson, const std::wstring& name, std::wstring& value) {
    if (!ContainsKey(paramsJson, name)) return false;
    value = JsonStringValue(paramsJson, name);
    return !value.empty();
}

bool IsSafePathParameter(const std::wstring& value) {
    std::wstring lower = Lower(value);
    if (lower.find(L"://") != std::wstring::npos) return false;
    if (value.find(L"..") != std::wstring::npos) return false;
    if (value.size() > 2 && value[1] == L':') {
        return StartsWith(value, ProjectRootPath()) || StartsWith(value, L"D:\\testrepo\\");
    }
    return true;
}

bool IsLocalUrlParameter(const std::wstring& value) {
    std::wstring lower = Lower(value);
    return StartsWith(lower, L"file://") ||
           StartsWith(lower, L"http://localhost") ||
           StartsWith(lower, L"https://localhost") ||
           StartsWith(lower, L"http://127.0.0.1") ||
           StartsWith(lower, L"https://127.0.0.1");
}

bool HasProfileConfirmationNode(const std::wstring& profileConfirmationRaw, const std::wstring& name) {
    for (const auto& obj : ObjectArray(profileConfirmationRaw)) {
        if (Lower(JsonStringValue(obj, L"name")) == Lower(name)) return true;
    }
    return false;
}

TaskTemplateV2OperationResult LoadProfile(const std::wstring& profileName, AppProfile& profile, std::wstring& profileJson) {
    ProfileLoadReport report = LoadAppProfiles(L"");
    for (const auto& item : report.profiles) {
        if (!item.valid) continue;
        if (Lower(item.profileName) != Lower(profileName)) continue;
        profile = item;
        FileReadResult read = ReadTextFile(item.path);
        if (!read.ok) {
            return Failure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read profile file: " + read.error, L"{\"profile\":" + JsonString(profileName) + L"}");
        }
        profileJson = read.content;
        TaskTemplateV2OperationResult ok;
        ok.ok = true;
        return ok;
    }
    return Failure(L"PROFILE_BINDING_PROFILE_NOT_FOUND", L"App Profile was not found or invalid: " + profileName, L"{\"profile\":" + JsonString(profileName) + L"}");
}

TaskTemplateV2OperationResult ResolveWithInputs(const ParsedTemplateV2& t, const std::wstring& requestedProfile, const std::wstring& paramsJson) {
    std::wstring profileName = requestedProfile.empty() ? t.requiredProfile : requestedProfile;
    if (Lower(profileName) != Lower(t.requiredProfile)) {
        return Failure(L"PROFILE_BINDING_PROFILE_MISMATCH", L"TaskTemplateV2 required_profile does not match requested profile.", L"{\"required_profile\":" + JsonString(t.requiredProfile) + L",\"profile\":" + JsonString(profileName) + L"}");
    }

    AppProfile profile;
    std::wstring profileJson;
    TaskTemplateV2OperationResult profileLoaded = LoadProfile(profileName, profile, profileJson);
    if (!profileLoaded.ok) return profileLoaded;

    std::wstring profileRois = RawValue(profileJson, L"roi_definitions");
    std::wstring profileVisual = RawValue(profileJson, L"visual_strategy");
    std::wstring profileRecovery = RawValue(profileJson, L"recovery_strategy");
    std::wstring profileConfirmations = RawValue(profileJson, L"confirmation_nodes");

    for (const auto& p : t.parameters) {
        std::wstring value;
        if (p.required && !ParameterValue(paramsJson, p.name, value)) {
            return Failure(L"TASK_PARAMETER_MISSING", L"Missing required TaskParameter: " + p.name, L"{\"template_id\":" + JsonString(t.templateId) + L",\"parameter\":" + JsonString(p.name) + L"}");
        }
        if (!value.empty() && p.type == L"path" && !IsSafePathParameter(value)) {
            return Failure(L"TASK_PARAMETER_PATH_INVALID", L"TaskParameter path is outside the allowed local path form: " + p.name, L"{\"parameter\":" + JsonString(p.name) + L",\"value\":" + JsonString(value) + L"}");
        }
        if (!value.empty() && p.type == L"local_url" && !IsLocalUrlParameter(value)) {
            return Failure(L"TASK_PARAMETER_LOCAL_URL_INVALID", L"TaskParameter local_url must be file://, localhost, or 127.0.0.1: " + p.name, L"{\"parameter\":" + JsonString(p.name) + L",\"value\":" + JsonString(value) + L"}");
        }
        if (!value.empty() && p.type == L"roi" && RawValue(profileRois, value).empty()) {
            return Failure(L"TASK_PARAMETER_ROI_INVALID", L"TaskParameter output_region does not exist in profile.roi_definitions: " + value, L"{\"parameter\":" + JsonString(p.name) + L",\"value\":" + JsonString(value) + L"}");
        }
    }

    std::wstringstream stepsJson;
    stepsJson << L"[";
    for (size_t i = 0; i < t.steps.size(); ++i) {
        const auto& step = t.steps[i];
        std::wstring selector;
        if (!step.locatorRef.empty()) {
            AppProfile locatorProfile;
            ProfileLocator locator;
            std::wstring error;
            if (!ResolveProfileLocator(profileName, step.locatorRef, locatorProfile, locator, error)) {
                return Failure(L"PROFILE_BINDING_MISSING_LOCATOR", L"ProfileBoundLocator was not found: " + step.locatorRef, L"{\"profile\":" + JsonString(profileName) + L",\"locator_ref\":" + JsonString(step.locatorRef) + L"}");
            }
            selector = locator.selector;
        }
        bool roiBound = false;
        if (!step.roiRef.empty()) {
            roiBound = !RawValue(profileRois, step.roiRef).empty();
            if (!roiBound) {
                return Failure(L"PROFILE_BINDING_MISSING_ROI", L"Profile ROI definition was not found: " + step.roiRef, L"{\"profile\":" + JsonString(profileName) + L",\"roi_ref\":" + JsonString(step.roiRef) + L"}");
            }
        }
        if (!step.confirmationNode.empty() && !HasProfileConfirmationNode(profileConfirmations, step.confirmationNode)) {
            return Failure(L"PROFILE_BINDING_MISSING_CONFIRMATION_NODE", L"Profile confirmation node was not found: " + step.confirmationNode, L"{\"profile\":" + JsonString(profileName) + L",\"confirmation_node\":" + JsonString(step.confirmationNode) + L"}");
        }

        if (i != 0) stepsJson << L",";
        stepsJson << L"{\"step_id\":" << JsonString(step.stepId)
                  << L",\"action\":" << JsonString(step.action)
                  << L",\"locator_ref\":" << JsonString(step.locatorRef)
                  << L",\"selector\":" << JsonString(selector)
                  << L",\"roi_ref\":" << JsonString(step.roiRef)
                  << L",\"roi_bound\":" << (roiBound ? L"true" : L"false")
                  << L",\"confirmation_node\":" << JsonString(step.confirmationNode)
                  << L",\"uses_parameters\":[";
        for (size_t j = 0; j < step.usesParameters.size(); ++j) {
            if (j != 0) stepsJson << L",";
            stepsJson << JsonString(step.usesParameters[j]);
        }
        stepsJson << L"]}";
    }
    stepsJson << L"]";

    std::wstringstream data;
    data << L"{\"schema_version\":\"5.4.2\""
         << L",\"runtime_version\":" << JsonString(t.runtimeVersion)
         << L",\"protocol_version\":" << JsonString(t.protocolVersion)
         << L",\"template_id\":" << JsonString(t.templateId)
         << L",\"required_profile\":" << JsonString(t.requiredProfile)
         << L",\"profile_name\":" << JsonString(profile.profileName)
         << L",\"parameter_count\":" << t.parameters.size()
         << L",\"step_count\":" << t.steps.size()
         << L",\"bound_profile\":{"
         << L"\"common_locators\":" << (!profile.commonLocators.empty() ? L"true" : L"false")
         << L",\"roi_definitions\":" << (!profileRois.empty() ? L"true" : L"false")
         << L",\"visual_strategy\":" << (!profileVisual.empty() ? L"true" : L"false")
         << L",\"recovery_strategy\":" << (!profileRecovery.empty() ? L"true" : L"false")
         << L",\"confirmation_nodes\":" << (!profileConfirmations.empty() ? L"true" : L"false")
         << L",\"can_override_safety_manifest\":false}"
         << L",\"profile_bound_verification\":" << RawOr(t.verificationRaw, L"{}")
         << L",\"profile_recovery_strategy_bound\":" << (!profileRecovery.empty() ? L"true" : L"false")
         << L",\"resolved_steps\":" << stepsJson.str()
         << L",\"final_state_policy\":" << RawOr(t.finalStatePolicyRaw, L"{}")
         << L",\"safety\":{\"profile_can_override_safety\":false,\"no_fixed_coordinates\":true,\"resolver_executes_actions\":false}"
         << L"}";

    TaskTemplateV2OperationResult ok;
    ok.ok = true;
    ok.dataJson = data.str();
    return ok;
}

}  // namespace

TaskTemplateV2OperationResult ValidateTaskTemplateV2File(const std::wstring& path) {
    ParsedTemplateV2 t;
    return ParseTemplateFile(path, t);
}

TaskTemplateV2OperationResult ResolveTaskTemplateV2(
    const std::wstring& templatePath,
    const std::wstring& profileName,
    const std::wstring& paramsPath,
    const std::wstring& taskPath) {
    std::wstring effectiveTemplate = templatePath;
    std::wstring effectiveProfile = profileName;
    std::wstring paramsJson = L"{}";

    if (!taskPath.empty()) {
        FileReadResult task = ReadTextFile(taskPath);
        if (!task.ok) {
            return Failure(task.errorCode.empty() ? L"FILE_READ_FAILED" : task.errorCode, L"Could not read template task file: " + task.error, L"{\"task\":" + JsonString(taskPath) + L"}");
        }
        std::wstring templateId = JsonStringValue(task.content, L"template_id");
        if (!IsSafeTemplateId(templateId)) {
            return Failure(L"INVALID_ARGUMENT", L"Template task requires a safe template_id.", L"{\"task\":" + JsonString(taskPath) + L"}");
        }
        effectiveTemplate = ProjectPath(L"tasks\\templates_v2\\" + templateId + L".task-template-v2.json");
        effectiveProfile = JsonStringValue(task.content, L"profile");
        paramsJson = RawValue(task.content, L"parameters");
        if (paramsJson.empty()) paramsJson = L"{}";
    } else {
        if (effectiveTemplate.empty()) {
            return Failure(L"INVALID_ARGUMENT", L"task-template-v2-resolve requires --task or --template.", L"{}");
        }
        if (!paramsPath.empty()) {
            FileReadResult params = ReadTextFile(paramsPath);
            if (!params.ok) {
                return Failure(params.errorCode.empty() ? L"FILE_READ_FAILED" : params.errorCode, L"Could not read params file: " + params.error, L"{\"params_file\":" + JsonString(paramsPath) + L"}");
            }
            paramsJson = params.content;
        }
    }

    ParsedTemplateV2 t;
    TaskTemplateV2OperationResult parsed = ParseTemplateFile(effectiveTemplate, t);
    if (!parsed.ok) return parsed;
    return ResolveWithInputs(t, effectiveProfile, paramsJson);
}
