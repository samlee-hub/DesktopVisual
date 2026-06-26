#include "AgentBoundary.h"

#include "CaseRunner.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

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

std::wstring Trim(const std::wstring& value) {
    size_t begin = 0;
    while (begin < value.size() && (std::iswspace(value[begin]) || value[begin] == 0xfeff)) ++begin;
    size_t end = value.size();
    while (end > begin && (std::iswspace(value[end - 1]) || value[end - 1] == 0xfeff)) --end;
    return value.substr(begin, end - begin);
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

std::wstring ValidModesJson() {
    return L"[\"runtime\",\"vlm_assisted\"]";
}

bool IsValidAgentMode(const std::wstring& mode) {
    return mode == L"runtime" || mode == L"vlm_assisted";
}

bool IsValidAgentExecutor(const std::wstring& executor) {
    return executor == L"runtime";
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool ParseBoolValue(const std::wstring& raw, bool& value) {
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    return false;
}

bool IsDisallowedHumanModeAction(const std::wstring& actionType) {
    const std::wstring action = ToLowerInvariant(actionType);
    return action == L"js" ||
           action == L"javascript" ||
           action == L"dom" ||
           action == L"webdriver" ||
           action == L"selenium" ||
           action == L"playwright" ||
           action == L"cdp" ||
           action == L"uia_invoke" ||
           action == L"uia.invoke" ||
           action == L"invoke_pattern" ||
           action == L"invokepattern" ||
           action == L"uia_value" ||
           action == L"uia.value" ||
           action == L"value_pattern" ||
           action == L"valuepattern" ||
           ContainsInsensitive(action, L"webdriver") ||
           ContainsInsensitive(action, L"cdp") ||
           ContainsInsensitive(action, L"javascript") ||
           ContainsInsensitive(action, L"invoke_pattern") ||
           ContainsInsensitive(action, L"value_pattern");
}

std::wstring ModeDataJson(const std::wstring& mode) {
    std::wstringstream data;
    data << L"{\"schema_version\":\"6.0.0.agent_boundary\""
         << L",\"check\":\"mode\""
         << L",\"mode\":" << JsonString(mode)
         << L",\"valid_modes\":" << ValidModesJson()
         << L",\"runtime_only_executor\":true}";
    return data.str();
}

std::wstring ExecutorDataJson(const std::wstring& executor) {
    std::wstringstream data;
    data << L"{\"schema_version\":\"6.0.0.agent_boundary\""
         << L",\"check\":\"executor\""
         << L",\"executor\":" << JsonString(executor)
         << L",\"valid_executors\":[\"runtime\"]"
         << L",\"rejected_executors\":[\"vlm\",\"agent_direct\"]"
         << L",\"runtime_only_executor\":true}";
    return data.str();
}

std::wstring ActionDataJson(const std::wstring& actionType, bool humanModeAction) {
    std::wstringstream data;
    data << L"{\"schema_version\":\"6.0.0.agent_boundary\""
         << L",\"check\":\"action\""
         << L",\"action_type\":" << JsonString(actionType)
         << L",\"humanmode_action\":" << (humanModeAction ? L"true" : L"false")
         << L",\"runtime_only_executor\":true"
         << L",\"disallowed_humanmode_actions\":[\"js\",\"dom\",\"webdriver\",\"cdp\",\"uia_invoke\",\"uia_value\"]}";
    return data.str();
}

struct BoundaryValidationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

std::wstring CompileRequiredJson(bool present, bool value) {
    if (!present) return L"null";
    return value ? L"true" : L"false";
}

std::wstring RequestDataJson(
    const std::wstring& file,
    const std::wstring& taskId,
    const std::wstring& mode,
    const std::wstring& userGoal,
    const std::wstring& risk,
    const std::wstring& executor,
    bool compilePresent,
    bool compileRequired) {
    std::wstringstream data;
    data << L"{\"schema_version\":\"6.0.0.agent_boundary\""
         << L",\"check\":\"request\""
         << L",\"request_type\":\"AgentTaskRequest\""
         << L",\"file\":" << JsonString(file)
         << L",\"task_id\":" << JsonString(taskId)
         << L",\"mode\":" << JsonString(mode)
         << L",\"user_goal\":" << JsonString(userGoal)
         << L",\"risk\":" << JsonString(risk)
         << L",\"executor\":" << JsonString(executor)
         << L",\"compile_required\":" << CompileRequiredJson(compilePresent, compileRequired)
         << L",\"runtime_only_executor\":true}";
    return data.str();
}

std::wstring PlanDataJson(
    const std::wstring& file,
    const std::wstring& planId,
    const std::wstring& taskId,
    const std::wstring& mode,
    const std::wstring& userGoal,
    const std::wstring& risk,
    const std::wstring& executor,
    bool compilePresent,
    bool compileRequired,
    int stepCount) {
    std::wstringstream data;
    data << L"{\"schema_version\":\"6.0.0.agent_boundary\""
         << L",\"check\":\"plan\""
         << L",\"plan_type\":\"AgentPlan\""
         << L",\"file\":" << JsonString(file)
         << L",\"plan_id\":" << JsonString(planId)
         << L",\"task_id\":" << JsonString(taskId)
         << L",\"mode\":" << JsonString(mode)
         << L",\"user_goal\":" << JsonString(userGoal)
         << L",\"risk\":" << JsonString(risk)
         << L",\"executor\":" << JsonString(executor)
         << L",\"compile_required\":" << CompileRequiredJson(compilePresent, compileRequired)
         << L",\"step_count\":" << stepCount
         << L",\"runtime_only_executor\":true}";
    return data.str();
}

BoundaryValidationResult InvalidResult(
    const std::wstring& code,
    const std::wstring& message,
    const std::wstring& dataJson) {
    BoundaryValidationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = dataJson;
    return result;
}

BoundaryValidationResult ValidResult(const std::wstring& dataJson) {
    BoundaryValidationResult result;
    result.ok = true;
    result.dataJson = dataJson;
    return result;
}

BoundaryValidationResult ValidateAgentTaskRequestFile(const std::wstring& path) {
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        return InvalidResult(
            file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode,
            L"Could not read AgentTaskRequest file: " + file.error,
            L"{\"check\":\"request\",\"file\":" + JsonString(path) + L"}");
    }

    if (!IsLikelyValidJsonObject(file.content)) {
        return InvalidResult(
            L"MALFORMED_JSON",
            L"AgentTaskRequest file is malformed JSON.",
            L"{\"check\":\"request\",\"file\":" + JsonString(path) + L"}");
    }

    const std::wstring& json = file.content;
    std::wstring taskId = JsonGetTopLevelString(json, L"task_id");
    std::wstring mode = JsonGetTopLevelString(json, L"mode");
    std::wstring userGoal = JsonGetTopLevelString(json, L"user_goal");
    std::wstring risk = JsonGetTopLevelString(json, L"risk");
    std::wstring executor = JsonGetTopLevelString(json, L"executor");
    bool compileRequired = false;
    bool compilePresent = JsonGetTopLevelBool(json, L"compile_required", compileRequired);
    std::wstring data = RequestDataJson(path, taskId, mode, userGoal, risk, executor, compilePresent, compileRequired);

    if (taskId.empty()) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest missing required field: task_id.", data);
    if (mode.empty()) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest missing required field: mode.", data);
    if (!IsValidAgentMode(mode)) return InvalidResult(L"AGENT_MODE_INVALID", L"AgentTaskRequest mode must be runtime or vlm_assisted.", data);
    if (userGoal.empty()) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest missing required field: user_goal.", data);
    if (risk.empty()) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest missing required field: risk.", data);
    if (executor.empty()) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest missing required field: executor.", data);
    if (!IsValidAgentExecutor(executor)) return InvalidResult(L"AGENT_EXECUTOR_INVALID", L"AgentTaskRequest executor must be runtime.", data);
    if (!compilePresent) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest missing required field: compile_required.", data);
    if (!compileRequired) return InvalidResult(L"AGENT_REQUEST_INVALID", L"AgentTaskRequest compile_required must be true.", data);

    return ValidResult(data);
}

BoundaryValidationResult ValidateAgentPlanFile(const std::wstring& path) {
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        return InvalidResult(
            file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode,
            L"Could not read AgentPlan file: " + file.error,
            L"{\"check\":\"plan\",\"file\":" + JsonString(path) + L"}");
    }

    if (!IsLikelyValidJsonObject(file.content)) {
        return InvalidResult(
            L"MALFORMED_JSON",
            L"AgentPlan file is malformed JSON.",
            L"{\"check\":\"plan\",\"file\":" + JsonString(path) + L"}");
    }

    const std::wstring& json = file.content;
    std::wstring planId = JsonGetTopLevelString(json, L"plan_id");
    std::wstring taskId = JsonGetTopLevelString(json, L"task_id");
    std::wstring mode = JsonGetTopLevelString(json, L"mode");
    std::wstring userGoal = JsonGetTopLevelString(json, L"user_goal");
    std::wstring risk = JsonGetTopLevelString(json, L"risk");
    std::wstring executor = JsonGetTopLevelString(json, L"executor");
    bool compileRequired = false;
    bool compilePresent = JsonGetTopLevelBool(json, L"compile_required", compileRequired);
    std::wstring steps = JsonGetTopLevelArray(json, L"steps");
    std::vector<std::wstring> stepItems = SplitArrayItems(steps);
    std::wstring data = PlanDataJson(path, planId, taskId, mode, userGoal, risk, executor, compilePresent, compileRequired, static_cast<int>(stepItems.size()));

    if (planId.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: plan_id.", data);
    if (taskId.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: task_id.", data);
    if (mode.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: mode.", data);
    if (!IsValidAgentMode(mode)) return InvalidResult(L"AGENT_MODE_INVALID", L"AgentPlan mode must be runtime or vlm_assisted.", data);
    if (userGoal.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: user_goal.", data);
    if (risk.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: risk.", data);
    if (executor.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: executor.", data);
    if (!IsValidAgentExecutor(executor)) return InvalidResult(L"AGENT_EXECUTOR_INVALID", L"AgentPlan executor must be runtime.", data);
    if (!compilePresent) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: compile_required.", data);
    if (!compileRequired) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan compile_required must be true.", data);
    if (steps.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan missing required field: steps.", data);
    if (stepItems.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlan steps must not be empty.", data);

    for (size_t i = 0; i < stepItems.size(); ++i) {
        const std::wstring& step = stepItems[i];
        if (!IsLikelyValidJsonObject(step)) {
            return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep must be a JSON object.", data);
        }
        std::wstring stepId = JsonGetTopLevelString(step, L"step_id");
        std::wstring description = JsonGetTopLevelString(step, L"description");
        std::wstring stepExecutor = JsonGetTopLevelString(step, L"executor");
        std::wstring actionType = JsonGetTopLevelString(step, L"action_type");
        bool stepCompileRequired = false;
        bool stepCompilePresent = JsonGetTopLevelBool(step, L"compile_required", stepCompileRequired);
        bool humanModeAction = true;
        JsonGetTopLevelBool(step, L"humanmode_action", humanModeAction);

        if (stepId.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep missing required field: step_id.", data);
        if (description.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep missing required field: description.", data);
        if (stepExecutor.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep missing required field: executor.", data);
        if (!IsValidAgentExecutor(stepExecutor)) return InvalidResult(L"AGENT_EXECUTOR_INVALID", L"AgentPlanStep executor must be runtime.", data);
        if (!stepCompilePresent) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep missing required field: compile_required.", data);
        if (!stepCompileRequired) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep compile_required must be true.", data);
        if (actionType.empty()) return InvalidResult(L"AGENT_PLAN_INVALID", L"AgentPlanStep missing required field: action_type.", data);
        if (humanModeAction && IsDisallowedHumanModeAction(actionType)) {
            return InvalidResult(
                L"AGENT_ACTION_BOUNDARY_INVALID",
                L"JS, DOM, WebDriver, CDP, UIA Invoke, and UIA Value are not HumanMode Runtime actions.",
                data);
        }
    }

    return ValidResult(data);
}

int EmitBoundaryFailure(
    const std::wstring& command,
    ULONGLONG startTick,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson,
    int exitCode) {
    std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson) << L"\n";
    return exitCode;
}

int EmitBoundarySuccess(
    const std::wstring& command,
    ULONGLONG startTick,
    const std::wstring& dataJson) {
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), dataJson) << L"\n";
    return 0;
}

int CheckMode(int argc, wchar_t** argv, ULONGLONG startTick) {
    const std::wstring command = L"agent-boundary-validate";
    std::wstring mode;
    ArgValue(argc, argv, L"--mode", mode);
    if (!IsValidAgentMode(mode)) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"AGENT_MODE_INVALID",
            L"Agent mode must be runtime or vlm_assisted.",
            ModeDataJson(mode),
            1);
    }
    return EmitBoundarySuccess(command, startTick, ModeDataJson(mode));
}

int CheckExecutor(int argc, wchar_t** argv, ULONGLONG startTick) {
    const std::wstring command = L"agent-boundary-validate";
    std::wstring executor;
    ArgValue(argc, argv, L"--executor", executor);
    if (!IsValidAgentExecutor(executor)) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"AGENT_EXECUTOR_INVALID",
            L"Agent executor must be runtime. VLM and agent_direct execution are forbidden.",
            ExecutorDataJson(executor),
            1);
    }
    return EmitBoundarySuccess(command, startTick, ExecutorDataJson(executor));
}

int CheckAction(int argc, wchar_t** argv, ULONGLONG startTick) {
    const std::wstring command = L"agent-boundary-validate";
    std::wstring actionType;
    ArgValue(argc, argv, L"--action-type", actionType);

    std::wstring rawHumanMode;
    bool humanModeAction = true;
    if (ArgValue(argc, argv, L"--humanmode-action", rawHumanMode) &&
        !ParseBoolValue(rawHumanMode, humanModeAction)) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"INVALID_ARGUMENT",
            L"--humanmode-action must be true or false.",
            ActionDataJson(actionType, humanModeAction),
            2);
    }

    if (actionType.empty()) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"AGENT_ACTION_BOUNDARY_INVALID",
            L"Agent action_type is required for HumanMode action boundary validation.",
            ActionDataJson(actionType, humanModeAction),
            1);
    }

    if (humanModeAction && IsDisallowedHumanModeAction(actionType)) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"AGENT_ACTION_BOUNDARY_INVALID",
            L"JS, DOM, WebDriver, CDP, UIA Invoke, and UIA Value are not HumanMode Runtime actions.",
            ActionDataJson(actionType, humanModeAction),
            1);
    }

    return EmitBoundarySuccess(command, startTick, ActionDataJson(actionType, humanModeAction));
}

int CheckRequest(int argc, wchar_t** argv, ULONGLONG startTick) {
    const std::wstring command = L"agent-boundary-validate";
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"INVALID_ARGUMENT",
            L"agent-boundary-validate --check request requires --file.",
            L"{\"check\":\"request\"}",
            2);
    }

    BoundaryValidationResult result = ValidateAgentTaskRequestFile(file);
    if (!result.ok) {
        return EmitBoundaryFailure(command, startTick, result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitBoundarySuccess(command, startTick, result.dataJson);
}

int CheckPlan(int argc, wchar_t** argv, ULONGLONG startTick) {
    const std::wstring command = L"agent-boundary-validate";
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"INVALID_ARGUMENT",
            L"agent-boundary-validate --check plan requires --file.",
            L"{\"check\":\"plan\"}",
            2);
    }

    BoundaryValidationResult result = ValidateAgentPlanFile(file);
    if (!result.ok) {
        return EmitBoundaryFailure(command, startTick, result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitBoundarySuccess(command, startTick, result.dataJson);
}

}  // namespace

int CommandAgentBoundaryValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"agent-boundary-validate";
    ULONGLONG startTick = GetTickCount64();

    std::wstring check;
    if (!ArgValue(argc, argv, L"--check", check) || check.empty()) {
        return EmitBoundaryFailure(
            command,
            startTick,
            L"INVALID_ARGUMENT",
            L"agent-boundary-validate requires --check.",
            L"{\"supported_checks\":[\"mode\",\"executor\",\"action\",\"request\",\"plan\"]}",
            2);
    }

    if (check == L"mode") {
        return CheckMode(argc, argv, startTick);
    }
    if (check == L"executor") {
        return CheckExecutor(argc, argv, startTick);
    }
    if (check == L"action") {
        return CheckAction(argc, argv, startTick);
    }
    if (check == L"request") {
        return CheckRequest(argc, argv, startTick);
    }
    if (check == L"plan") {
        return CheckPlan(argc, argv, startTick);
    }

    return EmitBoundaryFailure(
        command,
        startTick,
        L"INVALID_ARGUMENT",
        L"Unsupported agent boundary check.",
        L"{\"check\":" + JsonString(check) + L",\"supported_checks\":[\"mode\",\"executor\",\"action\",\"request\",\"plan\"]}",
        2);
}
