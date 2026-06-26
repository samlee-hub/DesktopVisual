#include "AgentPlanner.h"

#include "CaseRunner.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <iomanip>
#include <initializer_list>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

const wchar_t* kPlannerSchemaVersion = L"6.1.2.task_intent_planner";

struct TaskIntent {
    std::wstring taskId;
    std::wstring rawUserGoal;
    std::wstring normalizedGoal;
    std::wstring intentType;
    std::wstring mode;
    std::wstring targetApp;
    std::wstring targetPath;
    std::wstring targetObject;
    std::vector<std::wstring> userConstraints;
    std::wstring riskLevel;
    bool requiresConfirmation = false;
    std::vector<std::wstring> assumptions;
    std::wstring unsupportedReason;
};

struct DraftStep {
    std::wstring stepId;
    std::wstring description;
    std::wstring expectedRuntimeCapability;
    std::wstring target;
    std::wstring preconditionHint;
    std::wstring verificationHint;
    std::wstring risk;
};

struct AgentPlanDraft {
    std::wstring planId;
    std::wstring taskId;
    std::wstring goal;
    std::wstring mode;
    std::wstring intentType;
    std::vector<DraftStep> draftSteps;
    std::vector<std::wstring> requiredRuntimeCapabilities;
    std::vector<std::wstring> assumptions;
    std::wstring riskLevel;
    std::wstring allowedScope;
    bool developerFullAccess = false;
    bool requiresConfirmation = false;
    std::wstring expectedContextSummaryJson;
    std::wstring verificationSummary;
    std::wstring recoverySummary;
    bool compileRequired = true;
    std::wstring executor = L"runtime";
    std::wstring providerRole;
    bool isExecutable = false;
};

struct PlannerValidationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::wstring FromCodePoints(std::initializer_list<int> codePoints) {
    std::wstring value;
    for (int codePoint : codePoints) {
        value.push_back(static_cast<wchar_t>(codePoint));
    }
    return value;
}

std::wstring Trim(const std::wstring& value) {
    size_t begin = 0;
    while (begin < value.size() && (std::iswspace(value[begin]) || value[begin] == 0xfeff)) ++begin;
    size_t end = value.size();
    while (end > begin && (std::iswspace(value[end - 1]) || value[end - 1] == 0xfeff)) --end;
    return value.substr(begin, end - begin);
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool ContainsAny(const std::wstring& value, const std::vector<std::wstring>& needles) {
    for (const auto& needle : needles) {
        if (ContainsInsensitive(value, needle)) return true;
    }
    return false;
}

bool IsValidMode(const std::wstring& mode) {
    return mode == L"runtime" || mode == L"vlm_assisted";
}

bool IsValidRisk(const std::wstring& risk) {
    return risk == L"low" || risk == L"medium" || risk == L"high" || risk == L"blocked";
}

bool IsValidIntentType(const std::wstring& intentType) {
    return intentType == L"explorer_open_path" ||
           intentType == L"explorer_open_file" ||
           intentType == L"explorer_delete_file" ||
           intentType == L"browser_open_page" ||
           intentType == L"browser_fill_form" ||
           intentType == L"local_mock_mail_fill" ||
           intentType == L"unknown";
}

bool IsValidProviderRole(const std::wstring& providerRole) {
    return providerRole == L"none" || providerRole == L"assistive_only";
}

bool IsMatchingClose(wchar_t open, wchar_t close) {
    return (open == L'{' && close == L'}') || (open == L'[' && close == L']');
}

bool IsLikelyValidJsonObject(const std::wstring& json) {
    std::wstring trimmed = Trim(json);
    if (trimmed.empty() || trimmed.front() != L'{') return false;

    std::vector<wchar_t> stack;
    bool inString = false;
    bool escaped = false;
    for (size_t i = 0; i < trimmed.size(); ++i) {
        wchar_t ch = trimmed[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (inString) {
            if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                inString = false;
            }
            continue;
        }
        if (ch == L'"') {
            inString = true;
            continue;
        }
        if (ch == L'{' || ch == L'[') {
            stack.push_back(ch);
            continue;
        }
        if (ch == L'}' || ch == L']') {
            if (stack.empty() || !IsMatchingClose(stack.back(), ch)) return false;
            stack.pop_back();
            if (stack.empty()) {
                for (size_t rest = i + 1; rest < trimmed.size(); ++rest) {
                    if (!std::iswspace(trimmed[rest])) return false;
                }
                return true;
            }
        }
    }
    return false;
}

size_t JsonFindTopLevelValue(const std::wstring& json, const std::wstring& key) {
    int depth = 0;
    bool inString = false;
    for (size_t i = 0; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (ch == L'\\' && inString) {
            ++i;
            continue;
        }
        if (ch == L'"') {
            if (!inString && depth == 1) {
                size_t keyStart = i + 1;
                size_t keyEnd = keyStart;
                while (keyEnd < json.size()) {
                    if (json[keyEnd] == L'\\') {
                        keyEnd += 2;
                        continue;
                    }
                    if (json[keyEnd] == L'"') break;
                    ++keyEnd;
                }
                if (keyEnd < json.size() && json.substr(keyStart, keyEnd - keyStart) == key) {
                    size_t pos = keyEnd + 1;
                    while (pos < json.size() && std::iswspace(json[pos])) ++pos;
                    if (pos < json.size() && json[pos] == L':') {
                        ++pos;
                        while (pos < json.size() && std::iswspace(json[pos])) ++pos;
                        return pos;
                    }
                }
            }
            inString = !inString;
            continue;
        }
        if (inString) continue;
        if (ch == L'{' || ch == L'[') ++depth;
        else if (ch == L'}' || ch == L']') --depth;
    }
    return std::wstring::npos;
}

std::wstring JsonReadStringAt(const std::wstring& json, size_t pos) {
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'"') return L"";
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) ++pos;
        value += json[pos];
        ++pos;
    }
    return value;
}

std::wstring JsonGetTopLevelString(const std::wstring& json, const std::wstring& key) {
    return JsonReadStringAt(json, JsonFindTopLevelValue(json, key));
}

bool JsonHasTopLevelKey(const std::wstring& json, const std::wstring& key) {
    return JsonFindTopLevelValue(json, key) != std::wstring::npos;
}

bool JsonGetTopLevelBool(const std::wstring& json, const std::wstring& key, bool& value) {
    size_t pos = JsonFindTopLevelValue(json, key);
    if (pos == std::wstring::npos) return false;
    if (json.substr(pos, 4) == L"true") {
        value = true;
        return true;
    }
    if (json.substr(pos, 5) == L"false") {
        value = false;
        return true;
    }
    return false;
}

std::wstring JsonGetTopLevelArray(const std::wstring& json, const std::wstring& key) {
    size_t pos = JsonFindTopLevelValue(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'[') return L"";
    int depth = 1;
    size_t start = pos++;
    bool inString = false;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'\\' && inString) {
            pos += 2;
            continue;
        }
        if (json[pos] == L'"') {
            inString = !inString;
            ++pos;
            continue;
        }
        if (!inString) {
            if (json[pos] == L'[') ++depth;
            else if (json[pos] == L']') --depth;
        }
        ++pos;
    }
    return depth == 0 ? json.substr(start, pos - start) : L"";
}

std::vector<std::wstring> SplitArrayItems(const std::wstring& arrayJson) {
    std::vector<std::wstring> items;
    if (arrayJson.size() < 2 || arrayJson.front() != L'[') return items;
    int depth = 0;
    bool inString = false;
    size_t start = 1;
    for (size_t i = 1; i + 1 < arrayJson.size(); ++i) {
        wchar_t ch = arrayJson[i];
        if (ch == L'\\' && inString) {
            ++i;
            continue;
        }
        if (ch == L'"') inString = !inString;
        if (inString) continue;
        if (ch == L'{' || ch == L'[') ++depth;
        else if (ch == L'}' || ch == L']') --depth;
        else if (ch == L',' && depth == 0) {
            std::wstring item = Trim(arrayJson.substr(start, i - start));
            if (!item.empty()) items.push_back(item);
            start = i + 1;
        }
    }
    std::wstring item = Trim(arrayJson.substr(start, arrayJson.size() - start - 1));
    if (!item.empty()) items.push_back(item);
    return items;
}

std::wstring JsonStringArray(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring HashHex(const std::wstring& value) {
    unsigned int hash = 2166136261u;
    for (wchar_t ch : value) {
        hash ^= static_cast<unsigned int>(ch);
        hash *= 16777619u;
    }
    std::wstringstream stream;
    stream << std::hex << std::setw(8) << std::setfill(L'0') << hash;
    return stream.str();
}

std::wstring StableId(const std::wstring& prefix, const std::wstring& value) {
    return prefix + L"-" + HashHex(value);
}

bool IsPathChar(wchar_t ch) {
    return !std::iswspace(ch) && ch != L'"' && ch != L'\'' && ch != L',' && ch != L';';
}

std::wstring ExtractWindowsPath(const std::wstring& goal) {
    for (size_t i = 0; i + 2 < goal.size(); ++i) {
        bool drive = ((goal[i] >= L'A' && goal[i] <= L'Z') || (goal[i] >= L'a' && goal[i] <= L'z')) &&
                     goal[i + 1] == L':' &&
                     (goal[i + 2] == L'\\' || goal[i + 2] == L'/');
        if (!drive) continue;
        size_t end = i + 3;
        while (end < goal.size() && IsPathChar(goal[end])) ++end;
        return goal.substr(i, end - i);
    }
    return L"";
}

bool LooksLikeFilePath(const std::wstring& path) {
    if (path.empty()) return false;
    size_t sep = path.find_last_of(L"\\/");
    std::wstring leaf = sep == std::wstring::npos ? path : path.substr(sep + 1);
    size_t dot = leaf.find_last_of(L'.');
    return dot != std::wstring::npos && dot + 1 < leaf.size();
}

bool HasOpenVerb(const std::wstring& goal) {
    return ContainsAny(goal, {
        L"open",
        FromCodePoints({0x6253, 0x5f00})
    });
}

bool HasDeleteVerb(const std::wstring& goal) {
    return ContainsAny(goal, {
        L"delete",
        L"remove",
        FromCodePoints({0x5220, 0x9664})
    });
}

bool HasActiveProtectionBypass(const std::wstring& goal) {
    return ContainsAny(goal, {
        L"bypass captcha",
        L"captcha bypass",
        L"recaptcha",
        L"bot challenge",
        L"human verification",
        L"active protection",
        L"automation detected",
        L"anti-cheat",
        L"lockdown browser",
        L"bypass",
        FromCodePoints({0x7ed5, 0x8fc7}),
        FromCodePoints({0x9a8c, 0x8bc1, 0x7801}),
        FromCodePoints({0x53cd, 0x4f5c, 0x5f0a})
    });
}

bool HasLocalFormGoal(const std::wstring& goal) {
    return ContainsInsensitive(goal, L"local form") ||
           ContainsInsensitive(goal, L"fill form") ||
           (ContainsInsensitive(goal, FromCodePoints({0x672c, 0x5730})) &&
            ContainsInsensitive(goal, FromCodePoints({0x8868, 0x5355}))) ||
           (ContainsInsensitive(goal, FromCodePoints({0x7f51, 0x9875})) &&
            ContainsInsensitive(goal, FromCodePoints({0x586b, 0x5199})));
}

bool HasBrowserTitleGoal(const std::wstring& goal) {
    return ContainsInsensitive(goal, L"http://") ||
           ContainsInsensitive(goal, L"https://") ||
           ContainsInsensitive(goal, L"read title") ||
           ContainsInsensitive(goal, L"page title") ||
           (ContainsInsensitive(goal, FromCodePoints({0x7f51, 0x9875})) &&
            ContainsInsensitive(goal, FromCodePoints({0x6807, 0x9898})));
}

TaskIntent ParseTaskIntentFromGoal(const std::wstring& mode, const std::wstring& rawGoal) {
    TaskIntent intent;
    intent.mode = mode;
    intent.rawUserGoal = rawGoal;
    intent.normalizedGoal = Trim(rawGoal);
    intent.taskId = StableId(L"intent", mode + L":" + intent.normalizedGoal);
    intent.userConstraints.push_back(L"planner_boundary_no_execution");
    intent.assumptions.push_back(L"planner_only_no_execution");
    intent.assumptions.push_back(L"runtime_executor_required");
    intent.targetPath = ExtractWindowsPath(intent.normalizedGoal);
    intent.targetObject = L"";
    intent.targetApp = L"";

    if (HasActiveProtectionBypass(intent.normalizedGoal)) {
        intent.intentType = L"unknown";
        intent.riskLevel = L"blocked";
        intent.requiresConfirmation = false;
        intent.unsupportedReason = L"active_protection_bypass";
        return intent;
    }

    if (HasDeleteVerb(intent.normalizedGoal) && !intent.targetPath.empty()) {
        intent.intentType = L"explorer_delete_file";
        intent.targetApp = L"explorer";
        intent.riskLevel = L"medium";
        intent.requiresConfirmation = true;
        intent.unsupportedReason = L"";
        intent.targetObject = LooksLikeFilePath(intent.targetPath) ? L"file" : L"path";
        return intent;
    }

    if (HasOpenVerb(intent.normalizedGoal) && !intent.targetPath.empty()) {
        intent.intentType = LooksLikeFilePath(intent.targetPath) ? L"explorer_open_file" : L"explorer_open_path";
        intent.targetApp = L"explorer";
        intent.riskLevel = L"low";
        intent.requiresConfirmation = false;
        intent.unsupportedReason = L"";
        intent.targetObject = LooksLikeFilePath(intent.targetPath) ? L"file" : L"path";
        return intent;
    }

    if (HasLocalFormGoal(intent.normalizedGoal)) {
        intent.intentType = L"browser_fill_form";
        intent.targetApp = L"browser";
        intent.targetObject = L"form";
        intent.riskLevel = L"low";
        intent.requiresConfirmation = false;
        intent.unsupportedReason = L"";
        return intent;
    }

    if (HasBrowserTitleGoal(intent.normalizedGoal)) {
        intent.intentType = L"browser_open_page";
        intent.targetApp = L"browser";
        intent.targetObject = L"page_title";
        intent.riskLevel = L"low";
        intent.requiresConfirmation = false;
        intent.unsupportedReason = L"";
        if (ContainsInsensitive(intent.normalizedGoal, L"http://") || ContainsInsensitive(intent.normalizedGoal, L"https://")) {
            intent.targetPath = intent.normalizedGoal;
        }
        return intent;
    }

    intent.intentType = L"unknown";
    intent.riskLevel = L"medium";
    intent.requiresConfirmation = false;
    intent.unsupportedReason = L"ambiguous_task";
    return intent;
}

std::wstring TaskIntentJson(const TaskIntent& intent) {
    std::wstringstream json;
    json << L"{\"task_id\":" << JsonString(intent.taskId)
         << L",\"raw_user_goal\":" << JsonString(intent.rawUserGoal)
         << L",\"normalized_goal\":" << JsonString(intent.normalizedGoal)
         << L",\"intent_type\":" << JsonString(intent.intentType)
         << L",\"mode\":" << JsonString(intent.mode)
         << L",\"target_app\":" << JsonString(intent.targetApp)
         << L",\"target_path\":" << JsonString(intent.targetPath)
         << L",\"target_object\":" << JsonString(intent.targetObject)
         << L",\"user_constraints\":" << JsonStringArray(intent.userConstraints)
         << L",\"risk_level\":" << JsonString(intent.riskLevel)
         << L",\"requires_confirmation\":" << BoolJson(intent.requiresConfirmation)
         << L",\"assumptions\":" << JsonStringArray(intent.assumptions)
         << L",\"unsupported_reason\":" << JsonString(intent.unsupportedReason)
         << L"}";
    return json.str();
}

DraftStep MakeDraftStep(
    const std::wstring& id,
    const std::wstring& description,
    const std::wstring& capability,
    const std::wstring& target,
    const std::wstring& precondition,
    const std::wstring& verification,
    const std::wstring& risk) {
    DraftStep step;
    step.stepId = id;
    step.description = description;
    step.expectedRuntimeCapability = capability;
    step.target = target;
    step.preconditionHint = precondition;
    step.verificationHint = verification;
    step.risk = risk;
    return step;
}

std::wstring ExpectedContextSummaryJson(const TaskIntent& intent) {
    std::vector<std::wstring> markers;
    std::wstring process = L".*";
    std::wstring title = L".*";
    if (intent.targetApp == L"explorer") {
        process = L"explorer.exe";
        title = intent.targetPath.empty() ? L"Explorer" : intent.targetPath;
        markers.push_back(intent.targetPath.empty() ? L"Explorer" : intent.targetPath);
    } else if (intent.targetApp == L"browser") {
        process = L"(msedge.exe|chrome.exe)";
        title = L"(DesktopVisual|browser|Edge|Chrome)";
        markers.push_back(intent.targetObject.empty() ? L"page" : intent.targetObject);
    }
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << JsonString(process)
         << L",\"expected_title_pattern\":" << JsonString(title)
         << L",\"required_markers\":" << JsonStringArray(markers)
         << L",\"wrong_page_patterns\":[\"login\",\"captcha\",\"human verification\"]"
         << L",\"active_protection_patterns\":[\"captcha\",\"human verification\",\"automation detected\"]"
         << L",\"credential_required_patterns\":[\"password\",\"login required\",\"credential required\"]"
         << L",\"foreground_required\":true"
         << L",\"window_binding_required\":true}";
    return json.str();
}

AgentPlanDraft BuildPlanDraft(const TaskIntent& intent) {
    AgentPlanDraft draft;
    draft.planId = StableId(L"draft", intent.taskId + L":" + intent.intentType);
    draft.taskId = intent.taskId;
    draft.goal = intent.normalizedGoal;
    draft.mode = intent.mode;
    draft.intentType = intent.intentType;
    draft.assumptions = intent.assumptions;
    draft.assumptions.push_back(L"agent_plan_draft_is_not_stepcontract");
    draft.riskLevel = intent.riskLevel;
    draft.allowedScope = L"declared_runtime_scope";
    draft.developerFullAccess = false;
    draft.requiresConfirmation = intent.requiresConfirmation;
    draft.expectedContextSummaryJson = ExpectedContextSummaryJson(intent);
    draft.verificationSummary = L"per-step verification_hint required before StepContract compilation";
    draft.recoverySummary = L"reobserve_only_stop_on_active_protection_or_credentials";
    draft.compileRequired = true;
    draft.executor = L"runtime";
    draft.providerRole = intent.mode == L"vlm_assisted" ? L"assistive_only" : L"none";
    draft.isExecutable = false;

    if (intent.intentType == L"explorer_open_path") {
        draft.requiredRuntimeCapabilities.push_back(L"explorer.open_path");
        draft.draftSteps.push_back(MakeDraftStep(
            L"draft-step-001",
            L"Draft a Runtime capability for opening the target path.",
            L"explorer.open_path",
            intent.targetPath,
            L"Target path is available to Runtime.",
            L"Runtime can later verify Explorer reports the target path.",
            L"low"));
    } else if (intent.intentType == L"explorer_open_file") {
        draft.requiredRuntimeCapabilities.push_back(L"explorer.open_file");
        draft.draftSteps.push_back(MakeDraftStep(
            L"draft-step-001",
            L"Draft a Runtime capability for opening the target file.",
            L"explorer.open_file",
            intent.targetPath,
            L"Target file is available to Runtime.",
            L"Runtime can later verify the file owner application is visible.",
            L"low"));
    } else if (intent.intentType == L"explorer_delete_file") {
        draft.requiredRuntimeCapabilities.push_back(L"confirmation.request");
        draft.requiredRuntimeCapabilities.push_back(L"explorer.delete_file");
        draft.draftSteps.push_back(MakeDraftStep(
            L"draft-step-001",
            L"Draft a confirmation requirement before any destructive Runtime operation.",
            L"confirmation.request",
            intent.targetPath,
            L"User confirmation is available before compilation.",
            L"Compilation must preserve the confirmation gate.",
            L"medium"));
        draft.draftSteps.push_back(MakeDraftStep(
            L"draft-step-002",
            L"Draft a Runtime file deletion capability gated by confirmation.",
            L"explorer.delete_file",
            intent.targetPath,
            L"Confirmation is granted and target path is still the intended file.",
            L"Runtime can later verify the file is absent or deletion was refused.",
            L"medium"));
    } else if (intent.intentType == L"browser_fill_form") {
        draft.requiredRuntimeCapabilities.push_back(L"browser.open_local_page");
        draft.requiredRuntimeCapabilities.push_back(L"browser.form_fill");
        draft.draftSteps.push_back(MakeDraftStep(
            L"draft-step-001",
            L"Draft Runtime browser and form-field capabilities for a local page.",
            L"browser.form_fill",
            intent.targetObject.empty() ? L"local_form" : intent.targetObject,
            L"Local page and form schema are known before compilation.",
            L"Runtime can later verify field values after execution.",
            L"low"));
    } else if (intent.intentType == L"browser_open_page") {
        draft.requiredRuntimeCapabilities.push_back(L"browser.open_page");
        draft.requiredRuntimeCapabilities.push_back(L"browser.read_title");
        draft.draftSteps.push_back(MakeDraftStep(
            L"draft-step-001",
            L"Draft a Runtime browser navigation capability for reading a page title.",
            L"browser.open_page",
            intent.targetPath.empty() ? L"browser_page" : intent.targetPath,
            L"Page target is resolved before compilation.",
            L"Runtime can later verify the page title through observation.",
            L"low"));
    }

    return draft;
}

std::wstring DraftStepJson(const DraftStep& step) {
    std::wstringstream json;
    json << L"{\"step_id\":" << JsonString(step.stepId)
         << L",\"draft_step_id\":" << JsonString(step.stepId)
         << L",\"description\":" << JsonString(step.description)
         << L",\"natural_language_summary\":" << JsonString(step.description)
         << L",\"expected_runtime_capability\":" << JsonString(step.expectedRuntimeCapability)
         << L",\"proposed_action\":" << JsonString(step.expectedRuntimeCapability)
         << L",\"target\":" << JsonString(step.target)
         << L",\"target_description\":" << JsonString(step.target)
         << L",\"input_text\":\"\""
         << L",\"expected_result\":" << JsonString(step.verificationHint)
         << L",\"precondition_hint\":" << JsonString(step.preconditionHint)
         << L",\"verification_hint\":" << JsonString(step.verificationHint)
         << L",\"risk\":" << JsonString(step.risk)
         << L",\"risk_hint\":" << JsonString(step.risk)
         << L",\"confirmation_hint\":\"\""
         << L",\"recovery_hint\":\"reobserve_only_stop_on_active_protection_or_credentials\""
         << L"}";
    return json.str();
}

std::wstring DraftStepsJson(const std::vector<DraftStep>& steps) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < steps.size(); ++i) {
        if (i) json << L",";
        json << DraftStepJson(steps[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring AgentPlanDraftJson(const AgentPlanDraft& draft) {
    std::wstringstream json;
    json << L"{\"plan_id\":" << JsonString(draft.planId)
         << L",\"task_id\":" << JsonString(draft.taskId)
         << L",\"intent\":" << JsonString(draft.intentType)
         << L",\"goal\":" << JsonString(draft.goal)
         << L",\"mode\":" << JsonString(draft.mode)
         << L",\"intent_type\":" << JsonString(draft.intentType)
         << L",\"steps\":" << DraftStepsJson(draft.draftSteps)
         << L",\"draft_steps\":" << DraftStepsJson(draft.draftSteps)
         << L",\"required_runtime_capabilities\":" << JsonStringArray(draft.requiredRuntimeCapabilities)
         << L",\"assumptions\":" << JsonStringArray(draft.assumptions)
         << L",\"risk_summary\":" << JsonString(draft.riskLevel)
         << L",\"risk_level\":" << JsonString(draft.riskLevel)
         << L",\"allowed_scope\":" << JsonString(draft.allowedScope)
         << L",\"developer_full_access\":" << BoolJson(draft.developerFullAccess)
         << L",\"requires_confirmation\":" << BoolJson(draft.requiresConfirmation)
         << L",\"expected_context_summary\":" << (draft.expectedContextSummaryJson.empty() ? L"{}" : draft.expectedContextSummaryJson)
         << L",\"verification_summary\":" << JsonString(draft.verificationSummary)
         << L",\"recovery_summary\":" << JsonString(draft.recoverySummary)
         << L",\"compile_required\":" << BoolJson(draft.compileRequired)
         << L",\"executor\":" << JsonString(draft.executor)
         << L",\"provider_role\":" << JsonString(draft.providerRole)
         << L",\"is_executable\":" << BoolJson(draft.isExecutable)
         << L"}";
    return json.str();
}

std::wstring IntentDataJson(const TaskIntent& intent) {
    std::wstringstream data;
    data << L"{\"schema_version\":" << JsonString(kPlannerSchemaVersion)
         << L",\"intent\":" << TaskIntentJson(intent)
         << L",\"planner_boundary\":{\"executor\":\"runtime\",\"executes_task\":false,\"calls_vlm_provider\":false}}";
    return data.str();
}

std::wstring DraftDataJson(const AgentPlanDraft& draft) {
    std::wstringstream data;
    data << L"{\"schema_version\":" << JsonString(kPlannerSchemaVersion)
         << L",\"plan_draft\":" << AgentPlanDraftJson(draft)
         << L",\"planner_boundary\":{\"is_stepcontract\":false,\"executes_task\":false,\"calls_vlm_provider\":false}}";
    return data.str();
}

int EmitPlannerFailure(
    const std::wstring& command,
    ULONGLONG startTick,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson,
    int exitCode) {
    std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson) << L"\n";
    return exitCode;
}

int EmitPlannerSuccess(
    const std::wstring& command,
    ULONGLONG startTick,
    const std::wstring& dataJson) {
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), dataJson) << L"\n";
    return 0;
}

PlannerValidationResult InvalidValidation(
    const std::wstring& code,
    const std::wstring& message,
    const std::wstring& dataJson) {
    PlannerValidationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = dataJson;
    return result;
}

PlannerValidationResult ValidValidation(const std::wstring& dataJson) {
    PlannerValidationResult result;
    result.ok = true;
    result.dataJson = dataJson;
    return result;
}

bool RequireStringField(
    const std::wstring& json,
    const std::wstring& field,
    bool allowEmpty,
    std::wstring& value,
    std::wstring& missingField) {
    if (!JsonHasTopLevelKey(json, field)) {
        missingField = field;
        return false;
    }
    value = JsonGetTopLevelString(json, field);
    if (!allowEmpty && value.empty()) {
        missingField = field;
        return false;
    }
    return true;
}

bool HasRequiredArray(const std::wstring& json, const std::wstring& field, bool requireNonEmpty, std::wstring& missingField) {
    if (!JsonHasTopLevelKey(json, field)) {
        missingField = field;
        return false;
    }
    std::wstring arrayJson = JsonGetTopLevelArray(json, field);
    if (arrayJson.empty()) {
        missingField = field;
        return false;
    }
    if (requireNonEmpty && SplitArrayItems(arrayJson).empty()) {
        missingField = field;
        return false;
    }
    return true;
}

PlannerValidationResult ValidateTaskIntentJson(const std::wstring& json, const std::wstring& file) {
    if (!IsLikelyValidJsonObject(json)) {
        return InvalidValidation(L"MALFORMED_JSON", L"TaskIntent file is malformed JSON.", L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L"}");
    }

    std::wstring field;
    std::wstring value;
    if (!RequireStringField(json, L"task_id", false, value, field) ||
        !RequireStringField(json, L"raw_user_goal", false, value, field) ||
        !RequireStringField(json, L"normalized_goal", false, value, field) ||
        !RequireStringField(json, L"intent_type", false, value, field) ||
        !RequireStringField(json, L"mode", false, value, field) ||
        !RequireStringField(json, L"target_app", true, value, field) ||
        !RequireStringField(json, L"target_path", true, value, field) ||
        !RequireStringField(json, L"target_object", true, value, field) ||
        !RequireStringField(json, L"risk_level", false, value, field) ||
        !RequireStringField(json, L"unsupported_reason", true, value, field) ||
        !HasRequiredArray(json, L"user_constraints", false, field) ||
        !HasRequiredArray(json, L"assumptions", false, field)) {
        return InvalidValidation(
            L"TASK_INTENT_INVALID",
            L"TaskIntent missing required field: " + field + L".",
            L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L",\"missing_field\":" + JsonString(field) + L"}");
    }

    bool requiresConfirmation = false;
    if (!JsonGetTopLevelBool(json, L"requires_confirmation", requiresConfirmation)) {
        return InvalidValidation(
            L"TASK_INTENT_INVALID",
            L"TaskIntent missing required field: requires_confirmation.",
            L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L",\"missing_field\":\"requires_confirmation\"}");
    }

    std::wstring mode = JsonGetTopLevelString(json, L"mode");
    if (!IsValidMode(mode)) {
        return InvalidValidation(L"AGENT_MODE_INVALID", L"TaskIntent mode must be runtime or vlm_assisted.", L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L",\"mode\":" + JsonString(mode) + L"}");
    }

    std::wstring intentType = JsonGetTopLevelString(json, L"intent_type");
    if (!IsValidIntentType(intentType)) {
        return InvalidValidation(L"TASK_INTENT_INVALID", L"TaskIntent intent_type is unsupported.", L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L",\"intent_type\":" + JsonString(intentType) + L"}");
    }

    std::wstring risk = JsonGetTopLevelString(json, L"risk_level");
    if (!IsValidRisk(risk)) {
        return InvalidValidation(L"TASK_INTENT_INVALID", L"TaskIntent risk_level is unsupported.", L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L",\"risk_level\":" + JsonString(risk) + L"}");
    }

    return ValidValidation(L"{\"check\":\"intent\",\"file\":" + JsonString(file) + L",\"valid\":true,\"mode\":" + JsonString(mode) + L",\"intent_type\":" + JsonString(intentType) + L"}");
}

bool IsDirectExecutableDraftText(const std::wstring& value) {
    return ContainsAny(value, {
        L"\"action_type\"",
        L"\"action\"",
        L" click",
        L"click ",
        L"\"click\"",
        L" type",
        L"type ",
        L"\"type\"",
        L" drag",
        L"drag ",
        L"\"drag\""
    });
}

PlannerValidationResult ValidatePlanDraftJson(const std::wstring& json, const std::wstring& file) {
    if (!IsLikelyValidJsonObject(json)) {
        return InvalidValidation(L"MALFORMED_JSON", L"AgentPlanDraft file is malformed JSON.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }

    std::wstring field;
    std::wstring value;
    if (!RequireStringField(json, L"plan_id", false, value, field) ||
        !RequireStringField(json, L"task_id", false, value, field) ||
        !RequireStringField(json, L"mode", false, value, field) ||
        !RequireStringField(json, L"intent_type", false, value, field) ||
        !RequireStringField(json, L"risk_level", false, value, field) ||
        !RequireStringField(json, L"executor", false, value, field) ||
        !RequireStringField(json, L"provider_role", false, value, field) ||
        !HasRequiredArray(json, L"draft_steps", true, field) ||
        !HasRequiredArray(json, L"required_runtime_capabilities", true, field) ||
        !HasRequiredArray(json, L"assumptions", false, field)) {
        return InvalidValidation(
            L"AGENT_PLAN_DRAFT_INVALID",
            L"AgentPlanDraft missing required field: " + field + L".",
            L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L",\"missing_field\":" + JsonString(field) + L"}");
    }

    bool requiresConfirmation = false;
    bool compileRequired = false;
    bool isExecutable = true;
    if (!JsonGetTopLevelBool(json, L"requires_confirmation", requiresConfirmation)) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft missing required field: requires_confirmation.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }
    if (!JsonGetTopLevelBool(json, L"compile_required", compileRequired)) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft missing required field: compile_required.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }
    if (!JsonGetTopLevelBool(json, L"is_executable", isExecutable)) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft missing required field: is_executable.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }

    std::wstring mode = JsonGetTopLevelString(json, L"mode");
    if (!IsValidMode(mode)) {
        return InvalidValidation(L"AGENT_MODE_INVALID", L"AgentPlanDraft mode must be runtime or vlm_assisted.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L",\"mode\":" + JsonString(mode) + L"}");
    }
    std::wstring executor = JsonGetTopLevelString(json, L"executor");
    if (executor != L"runtime") {
        return InvalidValidation(L"AGENT_EXECUTOR_INVALID", L"AgentPlanDraft executor must be runtime.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L",\"executor\":" + JsonString(executor) + L"}");
    }
    std::wstring providerRole = JsonGetTopLevelString(json, L"provider_role");
    if (!IsValidProviderRole(providerRole) || (mode == L"vlm_assisted" && providerRole != L"assistive_only") || (mode == L"runtime" && providerRole != L"none")) {
        return InvalidValidation(L"AGENT_PROVIDER_ROLE_INVALID", L"AgentPlanDraft provider_role must be none for runtime or assistive_only for vlm_assisted.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L",\"provider_role\":" + JsonString(providerRole) + L"}");
    }
    if (!compileRequired) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft compile_required must be true.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }
    if (isExecutable) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_EXECUTABLE", L"AgentPlanDraft must not be directly executable.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }
    if (!IsValidIntentType(JsonGetTopLevelString(json, L"intent_type"))) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft intent_type is unsupported.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }
    if (!IsValidRisk(JsonGetTopLevelString(json, L"risk_level"))) {
        return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft risk_level is unsupported.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
    }

    std::wstring draftSteps = JsonGetTopLevelArray(json, L"draft_steps");
    std::vector<std::wstring> stepItems = SplitArrayItems(draftSteps);
    for (const auto& step : stepItems) {
        if (!IsLikelyValidJsonObject(step)) {
            return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft step must be a JSON object.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
        }
        if (IsDirectExecutableDraftText(step)) {
            return InvalidValidation(L"AGENT_PLAN_DRAFT_EXECUTABLE", L"AgentPlanDraft must not contain direct click/type/drag action text.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
        }
        std::wstring stepField;
        std::wstring stepValue;
        if (!RequireStringField(step, L"step_id", false, stepValue, stepField) ||
            !RequireStringField(step, L"description", false, stepValue, stepField) ||
            !RequireStringField(step, L"expected_runtime_capability", false, stepValue, stepField) ||
            !RequireStringField(step, L"target", false, stepValue, stepField) ||
            !RequireStringField(step, L"precondition_hint", false, stepValue, stepField) ||
            !RequireStringField(step, L"verification_hint", false, stepValue, stepField) ||
            !RequireStringField(step, L"risk", false, stepValue, stepField)) {
            return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft step missing required field: " + stepField + L".", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L",\"missing_field\":" + JsonString(stepField) + L"}");
        }
        if (!IsValidRisk(JsonGetTopLevelString(step, L"risk"))) {
            return InvalidValidation(L"AGENT_PLAN_DRAFT_INVALID", L"AgentPlanDraft step risk is unsupported.", L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L"}");
        }
    }

    return ValidValidation(L"{\"check\":\"plan-draft\",\"file\":" + JsonString(file) + L",\"valid\":true,\"mode\":" + JsonString(mode) + L",\"executor\":\"runtime\",\"is_executable\":false}");
}

PlannerValidationResult ValidateFile(const std::wstring& check, const std::wstring& file) {
    FileReadResult read = ReadTextFile(file);
    if (!read.ok) {
        return InvalidValidation(
            read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode,
            L"Could not read planner validation file: " + read.error,
            L"{\"check\":" + JsonString(check) + L",\"file\":" + JsonString(file) + L"}");
    }
    if (check == L"intent" || check == L"task-intent") {
        return ValidateTaskIntentJson(read.content, file);
    }
    if (check == L"plan-draft" || check == L"draft") {
        return ValidatePlanDraftJson(read.content, file);
    }
    return InvalidValidation(L"INVALID_ARGUMENT", L"Unsupported planner validation check.", L"{\"check\":" + JsonString(check) + L"}");
}

TaskIntent ParseTaskIntentFromJsonObject(const std::wstring& json) {
    TaskIntent intent;
    intent.taskId = JsonGetTopLevelString(json, L"task_id");
    intent.rawUserGoal = JsonGetTopLevelString(json, L"raw_user_goal");
    intent.normalizedGoal = JsonGetTopLevelString(json, L"normalized_goal");
    intent.intentType = JsonGetTopLevelString(json, L"intent_type");
    intent.mode = JsonGetTopLevelString(json, L"mode");
    intent.targetApp = JsonGetTopLevelString(json, L"target_app");
    intent.targetPath = JsonGetTopLevelString(json, L"target_path");
    intent.targetObject = JsonGetTopLevelString(json, L"target_object");
    intent.riskLevel = JsonGetTopLevelString(json, L"risk_level");
    JsonGetTopLevelBool(json, L"requires_confirmation", intent.requiresConfirmation);
    intent.unsupportedReason = JsonGetTopLevelString(json, L"unsupported_reason");
    intent.userConstraints.push_back(L"planner_boundary_no_execution");
    intent.assumptions.push_back(L"planner_only_no_execution");
    return intent;
}

PlannerValidationResult LoadIntentForDraft(int argc, wchar_t** argv, TaskIntent& intent) {
    std::wstring intentFile;
    if (ArgValue(argc, argv, L"--intent-file", intentFile) && !intentFile.empty()) {
        FileReadResult read = ReadTextFile(intentFile);
        if (!read.ok) {
            return InvalidValidation(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read TaskIntent file: " + read.error, L"{\"intent_file\":" + JsonString(intentFile) + L"}");
        }
        PlannerValidationResult validation = ValidateTaskIntentJson(read.content, intentFile);
        if (!validation.ok) return validation;
        intent = ParseTaskIntentFromJsonObject(read.content);
        return ValidValidation(IntentDataJson(intent));
    }

    std::wstring mode;
    if (!ArgValue(argc, argv, L"--mode", mode) || !IsValidMode(mode)) {
        return InvalidValidation(L"AGENT_MODE_INVALID", L"Agent mode must be runtime or vlm_assisted.", L"{\"valid_modes\":[\"runtime\",\"vlm_assisted\"]}");
    }
    std::wstring goal;
    ArgValue(argc, argv, L"--goal", goal);
    if (Trim(goal).empty()) {
        return InvalidValidation(L"FAIL_EMPTY_TASK", L"Task goal must not be empty.", L"{\"mode\":" + JsonString(mode) + L"}");
    }
    intent = ParseTaskIntentFromGoal(mode, goal);
    return ValidValidation(IntentDataJson(intent));
}

}  // namespace

int CommandAgentIntentParse(int argc, wchar_t** argv) {
    const std::wstring command = L"agent-intent-parse";
    ULONGLONG startTick = GetTickCount64();

    std::wstring mode;
    if (!ArgValue(argc, argv, L"--mode", mode) || !IsValidMode(mode)) {
        return EmitPlannerFailure(
            command,
            startTick,
            L"AGENT_MODE_INVALID",
            L"Agent mode must be runtime or vlm_assisted.",
            L"{\"valid_modes\":[\"runtime\",\"vlm_assisted\"],\"mode\":" + JsonString(mode) + L"}",
            1);
    }

    std::wstring goal;
    ArgValue(argc, argv, L"--goal", goal);
    if (Trim(goal).empty()) {
        return EmitPlannerFailure(
            command,
            startTick,
            L"FAIL_EMPTY_TASK",
            L"Task goal must not be empty.",
            L"{\"mode\":" + JsonString(mode) + L"}",
            1);
    }

    TaskIntent intent = ParseTaskIntentFromGoal(mode, goal);
    return EmitPlannerSuccess(command, startTick, IntentDataJson(intent));
}

int CommandAgentPlanDraft(int argc, wchar_t** argv) {
    const std::wstring command = L"agent-plan-draft";
    ULONGLONG startTick = GetTickCount64();

    TaskIntent intent;
    PlannerValidationResult loaded = LoadIntentForDraft(argc, argv, intent);
    if (!loaded.ok) {
        return EmitPlannerFailure(command, startTick, loaded.errorCode, loaded.errorMessage, loaded.dataJson, 1);
    }

    if (intent.riskLevel == L"blocked") {
        return EmitPlannerFailure(
            command,
            startTick,
            L"AGENT_PLAN_DRAFT_BLOCKED",
            L"Blocked TaskIntent cannot produce an AgentPlanDraft.",
            IntentDataJson(intent),
            1);
    }
    if (intent.intentType == L"unknown") {
        return EmitPlannerFailure(
            command,
            startTick,
            L"FAIL_AMBIGUOUS_TASK",
            L"Ambiguous TaskIntent cannot produce an AgentPlanDraft.",
            IntentDataJson(intent),
            1);
    }

    AgentPlanDraft draft = BuildPlanDraft(intent);
    return EmitPlannerSuccess(command, startTick, DraftDataJson(draft));
}

int CommandAgentPlannerValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"agent-planner-validate";
    ULONGLONG startTick = GetTickCount64();

    std::wstring check;
    if (!ArgValue(argc, argv, L"--check", check) || check.empty()) {
        return EmitPlannerFailure(
            command,
            startTick,
            L"INVALID_ARGUMENT",
            L"agent-planner-validate requires --check.",
            L"{\"supported_checks\":[\"intent\",\"plan-draft\"]}",
            2);
    }

    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitPlannerFailure(
            command,
            startTick,
            L"INVALID_ARGUMENT",
            L"agent-planner-validate requires --file.",
            L"{\"check\":" + JsonString(check) + L"}",
            2);
    }

    PlannerValidationResult result = ValidateFile(check, file);
    if (!result.ok) {
        int exitCode = result.errorCode == L"INVALID_ARGUMENT" ? 2 : 1;
        return EmitPlannerFailure(command, startTick, result.errorCode, result.errorMessage, result.dataJson, exitCode);
    }
    return EmitPlannerSuccess(command, startTick, result.dataJson);
}
