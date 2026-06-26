#include "StepContract.h"

#include "CaseRunner.h"
#include "Trace.h"

#include <cwctype>
#include <sstream>
#include <vector>

namespace {

std::wstring JsonGetString(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'"') return L"";
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) ++pos;
        value += json[pos];
        ++pos;
    }
    return value;
}

int JsonGetInt(const std::wstring& json, const std::wstring& key, int def = 0) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    try { return std::stoi(json.substr(pos)); } catch (...) { return def; }
}

bool JsonGetBool(const std::wstring& json, const std::wstring& key, bool def = false) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (json.substr(pos, 4) == L"true") return true;
    if (json.substr(pos, 5) == L"false") return false;
    return def;
}

std::wstring JsonGetObject(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = 0;
    while ((pos = json.find(search, pos)) != std::wstring::npos) {
        pos += search.size();
        while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
        if (pos >= json.size()) return L"";
        if (json[pos] != L'{') {
            ++pos;
            continue;
        }
        int depth = 1;
        size_t start = pos++;
        while (pos < json.size() && depth > 0) {
            if (json[pos] == L'{') ++depth;
            else if (json[pos] == L'}') --depth;
            ++pos;
        }
        return depth == 0 ? json.substr(start, pos - start) : L"";
    }
    return L"";
}

std::wstring JsonGetArray(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'[') return L"";
    int depth = 1;
    size_t start = pos++;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'[') ++depth;
        else if (json[pos] == L']') --depth;
        ++pos;
    }
    return depth == 0 ? json.substr(start, pos - start) : L"";
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
                    while (pos < json.size() && iswspace(json[pos])) ++pos;
                    if (pos < json.size() && json[pos] == L':') {
                        ++pos;
                        while (pos < json.size() && iswspace(json[pos])) ++pos;
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

std::wstring JsonGetTopLevelString(const std::wstring& json, const std::wstring& key) {
    size_t pos = JsonFindTopLevelValue(json, key);
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

int CountArrayItems(const std::wstring& arrayJson) {
    if (arrayJson.empty() || arrayJson.front() != L'[') return 0;
    int count = 0;
    int nested = 0;
    bool inString = false;
    bool sawValue = false;
    for (size_t i = 1; i + 1 < arrayJson.size(); ++i) {
        wchar_t ch = arrayJson[i];
        if (ch == L'\\' && inString) {
            ++i;
            continue;
        }
        if (ch == L'"') inString = !inString;
        if (inString) {
            sawValue = true;
            continue;
        }
        if (ch == L'{' || ch == L'[') {
            ++nested;
            sawValue = true;
        } else if (ch == L'}' || ch == L']') {
            --nested;
        } else if (ch == L',' && nested == 0) {
            ++count;
            sawValue = false;
        } else if (!iswspace(ch)) {
            sawValue = true;
        }
    }
    return sawValue ? count + 1 : count;
}

std::wstring Trim(const std::wstring& value) {
    size_t begin = 0;
    while (begin < value.size() && iswspace(value[begin])) ++begin;
    size_t end = value.size();
    while (end > begin && iswspace(value[end - 1])) --end;
    return value.substr(begin, end - begin);
}

std::wstring JsonUnquote(const std::wstring& value) {
    std::wstring trimmed = Trim(value);
    if (trimmed.size() < 2 || trimmed.front() != L'"' || trimmed.back() != L'"') return trimmed;
    std::wstring out;
    for (size_t i = 1; i + 1 < trimmed.size(); ++i) {
        if (trimmed[i] == L'\\' && i + 1 < trimmed.size() - 1) ++i;
        out += trimmed[i];
    }
    return out;
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

std::vector<std::wstring> JsonStringArrayValues(const std::wstring& arrayJson, const std::wstring& objectKey = L"") {
    std::vector<std::wstring> values;
    for (const std::wstring& item : SplitArrayItems(arrayJson)) {
        std::wstring trimmed = Trim(item);
        if (trimmed.empty()) continue;
        if (trimmed.front() == L'"') {
            values.push_back(JsonUnquote(trimmed));
        } else if (!objectKey.empty() && trimmed.front() == L'{') {
            std::wstring value = JsonGetString(trimmed, objectKey);
            if (!value.empty()) values.push_back(value);
        }
    }
    return values;
}

bool HasStringValue(const std::vector<std::wstring>& values, const std::wstring& expected) {
    for (const std::wstring& value : values) {
        if (value == expected) return true;
    }
    return false;
}

std::wstring FirstPreconditionValue(const std::wstring& preconditionsArray, const std::wstring& type, const std::wstring& key) {
    for (const std::wstring& item : SplitArrayItems(preconditionsArray)) {
        if (JsonGetString(item, L"type") == type) {
            return JsonGetString(item, key);
        }
    }
    return L"";
}

bool HasPreconditionType(const std::wstring& preconditionsArray, const std::wstring& type) {
    for (const std::wstring& item : SplitArrayItems(preconditionsArray)) {
        if (JsonGetString(item, L"type") == type) return true;
    }
    return false;
}

std::wstring JsonStringArray(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i > 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring ElementExpectationsJson(const std::vector<StepElementExpectation>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i > 0) json << L",";
        json << L"{\"element_id\":" << JsonString(values[i].elementId)
             << L",\"condition\":" << JsonString(values[i].condition.empty() ? L"appeared" : values[i].condition)
             << L"}";
    }
    json << L"]";
    return json.str();
}

std::wstring LocatorElementId(const std::wstring& locator) {
    size_t colon = locator.find(L":");
    if (colon == std::wstring::npos || colon + 1 >= locator.size()) return locator;
    return locator.substr(colon + 1);
}

StepContractValidationResult Invalid(const StepContract& contract, const std::wstring& message) {
    StepContractValidationResult result;
    result.ok = false;
    result.errorCode = L"STEP_CONTRACT_SCHEMA_INVALID";
    result.errorMessage = message;
    result.contract = contract;
    result.dataJson = StepContractDataJson(contract);
    return result;
}

bool RequireString(const StepContract& contract, const std::wstring& value, const std::wstring& field, StepContractValidationResult& out) {
    if (!value.empty()) return true;
    out = Invalid(contract, L"StepContract missing required field: " + field);
    return false;
}

}  // namespace

std::wstring StepContractDataJson(const StepContract& contract) {
    std::wstringstream json;
    json << L"{\"schema_version\":" << JsonString(contract.schemaVersion)
         << L",\"step_id\":" << JsonString(contract.stepId)
         << L",\"name\":" << JsonString(contract.name)
         << L",\"precondition_count\":" << contract.preconditionCount
         << L",\"preconditions\":{\"expected_scene_state\":" << JsonString(contract.preconditionExpectedSceneState)
         << L",\"element_id\":" << JsonString(contract.preconditionElementId)
         << L",\"requires_target_ready\":" << (contract.requiresTargetReady ? L"true" : L"false")
         << L",\"requires_window_focused\":" << (contract.requiresWindowFocused ? L"true" : L"false")
         << L",\"required_profile\":" << JsonString(contract.requiredProfile)
         << L",\"required_safety_action\":" << JsonString(contract.requiredSafetyAction)
         << L",\"required_capability\":" << JsonString(contract.requiredCapability)
         << L"}"
         << L",\"action\":{\"type\":" << JsonString(contract.actionType)
         << L",\"locator\":" << JsonString(contract.actionLocator)
         << L"}"
         << L",\"verification\":{\"type\":" << JsonString(contract.verificationType)
         << L",\"expected_text\":" << JsonString(contract.verificationExpectedText)
         << L",\"expected_scene_state\":" << JsonString(contract.verificationExpectedSceneState)
         << L"}"
         << L",\"timeout_ms\":" << contract.timeoutMs
         << L",\"retry_policy\":{\"max_attempts\":" << contract.retryMaxAttempts
         << L",\"backoff_ms\":" << contract.retryBackoffMs
         << L"}"
         << L",\"on_failure\":{\"strategy\":" << JsonString(contract.onFailureStrategy)
         << L",\"failure_reason\":" << JsonString(contract.onFailureReason)
         << L"}"
         << L",\"safety_requirements\":{\"permission_profile\":" << JsonString(contract.safety.permissionProfile)
         << L",\"allow_unrestricted_desktop\":" << (contract.safety.allowUnrestrictedDesktop ? L"true" : L"false")
         << L",\"requires_human_confirmation\":" << (contract.safety.requiresHumanConfirmation ? L"true" : L"false")
         << L"}"
         << L",\"expected_scene_state\":" << JsonString(contract.expectedSceneState)
         << L",\"expected_change_event_count\":" << contract.expectedChangeEventCount
         << L",\"expected_element_count\":" << contract.expectedElementCount
         << L",\"expected_change_events\":" << JsonStringArray(contract.expectedChangeEvents)
         << L",\"expected_elements\":" << ElementExpectationsJson(contract.expectedElements)
         << L"}";
    return json.str();
}

StepContractValidationResult ValidateStepContractFile(const std::wstring& path) {
    StepContractValidationResult out;
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        out.ok = false;
        out.errorCode = file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode;
        out.errorMessage = L"Could not read StepContract file: " + file.error;
        out.dataJson = L"{\"file\":" + JsonString(path) + L"}";
        return out;
    }

    const std::wstring& json = file.content;
    StepContract contract;
    contract.schemaVersion = JsonGetString(json, L"schema_version");
    contract.stepId = JsonGetString(json, L"step_id");
    contract.name = JsonGetString(json, L"name");
    std::wstring preconditions = JsonGetArray(json, L"preconditions");
    contract.preconditionCount = CountArrayItems(preconditions);
    contract.preconditionExpectedSceneState = FirstPreconditionValue(preconditions, L"scene_state", L"expected");
    contract.preconditionElementId = FirstPreconditionValue(preconditions, L"element_exists", L"element_id");
    contract.requiresTargetReady = HasPreconditionType(preconditions, L"target_ready");
    contract.requiresWindowFocused = HasPreconditionType(preconditions, L"window_focused");
    contract.requiredProfile = FirstPreconditionValue(preconditions, L"profile_active", L"profile");
    contract.requiredSafetyAction = FirstPreconditionValue(preconditions, L"safety_allowed", L"action");
    contract.requiredCapability = FirstPreconditionValue(preconditions, L"capability_available", L"capability");

    std::wstring action = JsonGetObject(json, L"action");
    contract.actionType = JsonGetString(action, L"type");
    contract.actionLocator = JsonGetString(action, L"locator");
    if (contract.preconditionElementId.empty() && !contract.actionLocator.empty()) {
        contract.preconditionElementId = LocatorElementId(contract.actionLocator);
    }
    if (contract.requiredSafetyAction.empty()) {
        contract.requiredSafetyAction = contract.actionType;
    }

    std::wstring verification = JsonGetObject(json, L"verification");
    contract.verificationType = JsonGetString(verification, L"type");
    contract.verificationExpectedText = JsonGetString(verification, L"expected_text");
    contract.verificationExpectedSceneState = JsonGetString(verification, L"expected_scene_state");

    contract.timeoutMs = JsonGetInt(json, L"timeout_ms", 0);
    std::wstring retry = JsonGetObject(json, L"retry_policy");
    contract.retryMaxAttempts = JsonGetInt(retry, L"max_attempts", 0);
    contract.retryBackoffMs = JsonGetInt(retry, L"backoff_ms", 0);

    std::wstring onFailure = JsonGetObject(json, L"on_failure");
    contract.onFailureStrategy = JsonGetString(onFailure, L"strategy");
    contract.onFailureReason = JsonGetString(onFailure, L"failure_reason");

    std::wstring safety = JsonGetObject(json, L"safety_requirements");
    contract.safety.permissionProfile = JsonGetString(safety, L"permission_profile");
    contract.safety.allowUnrestrictedDesktop = JsonGetBool(safety, L"allow_unrestricted_desktop", false);
    contract.safety.requiresHumanConfirmation = JsonGetBool(safety, L"requires_human_confirmation", false);

    contract.expectedSceneState = JsonGetTopLevelString(json, L"expected_scene_state");
    std::wstring expectedChangeEvents = JsonGetTopLevelArray(json, L"expected_change_events");
    contract.expectedChangeEvents = JsonStringArrayValues(expectedChangeEvents, L"type");
    if (contract.expectedChangeEvents.empty()) {
        contract.expectedChangeEvents = JsonStringArrayValues(JsonGetArray(verification, L"expected_change_events"), L"type");
    }
    contract.expectedChangeEventCount = static_cast<int>(contract.expectedChangeEvents.size());
    std::wstring expectedElements = JsonGetTopLevelArray(json, L"expected_elements");
    std::vector<std::wstring> expectedElementIds = JsonStringArrayValues(expectedElements, L"element_id");
    std::wstring verificationElements = JsonGetArray(verification, L"expected_elements");
    for (const std::wstring& id : expectedElementIds) {
        StepElementExpectation expectation;
        expectation.elementId = id;
        for (const std::wstring& item : SplitArrayItems(expectedElements)) {
            if (JsonGetString(item, L"element_id") == id) {
                expectation.condition = JsonGetString(item, L"condition");
                if (expectation.condition.empty()) expectation.condition = L"appeared";
                break;
            }
        }
        for (const std::wstring& item : SplitArrayItems(verificationElements)) {
            if (JsonGetString(item, L"element_id") == id) {
                expectation.condition = JsonGetString(item, L"condition");
                if (expectation.condition.empty()) expectation.condition = L"appeared";
                break;
            }
        }
        contract.expectedElements.push_back(expectation);
    }
    if (contract.expectedElements.empty()) {
        for (const std::wstring& item : SplitArrayItems(verificationElements)) {
            StepElementExpectation expectation;
            expectation.elementId = JsonGetString(item, L"element_id");
            expectation.condition = JsonGetString(item, L"condition");
            if (expectation.condition.empty()) expectation.condition = L"appeared";
            if (!expectation.elementId.empty()) contract.expectedElements.push_back(expectation);
        }
    }
    contract.expectedElementCount = static_cast<int>(contract.expectedElements.size());

    if (contract.schemaVersion != L"5.1.1") return Invalid(contract, L"StepContract schema_version must be 5.1.1.");
    if (!RequireString(contract, contract.stepId, L"step_id", out)) return out;
    if (!RequireString(contract, contract.name, L"name", out)) return out;
    if (contract.preconditionCount <= 0) return Invalid(contract, L"StepContract requires preconditions.");
    if (!RequireString(contract, contract.actionType, L"action.type", out)) return out;
    if (verification.empty()) return Invalid(contract, L"StepContract missing required field: verification.");
    if (!RequireString(contract, contract.verificationType, L"verification.type", out)) return out;
    if (contract.timeoutMs <= 0) return Invalid(contract, L"timeout_ms must be positive.");
    if (retry.empty()) return Invalid(contract, L"StepContract missing required field: retry_policy.");
    if (onFailure.empty()) return Invalid(contract, L"StepContract missing required field: on_failure.");
    if (!RequireString(contract, contract.onFailureStrategy, L"on_failure.strategy", out)) return out;
    if (safety.empty()) return Invalid(contract, L"StepContract missing required field: safety_requirements.");
    if (contract.safety.permissionProfile != L"DEFAULT" &&
        contract.safety.permissionProfile != L"PUBLIC_DEFAULT" &&
        contract.safety.permissionProfile != L"DEVELOPER_CAPABILITY_DISCOVERY" &&
        contract.safety.permissionProfile != L"DEVELOPER_FULL_RUNTIME" &&
        contract.safety.permissionProfile != L"developer_capability_discovery" &&
        contract.safety.permissionProfile != L"developer_full_runtime" &&
        contract.safety.permissionProfile != L"CI_MOCK" &&
        contract.safety.permissionProfile != L"FULL_ACCESS") {
        return Invalid(contract, L"safety_requirements.permission_profile must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.");
    }
    if (contract.safety.allowUnrestrictedDesktop) {
        return Invalid(contract, L"safety_requirements.allow_unrestricted_desktop is denied.");
    }
    if (!RequireString(contract, contract.expectedSceneState, L"expected_scene_state", out)) return out;
    if (contract.expectedChangeEventCount <= 0) return Invalid(contract, L"expected_change_events must not be empty.");
    if (contract.expectedElementCount <= 0) return Invalid(contract, L"expected_elements must not be empty.");

    out.ok = true;
    out.contract = contract;
    out.dataJson = StepContractDataJson(contract);
    return out;
}

namespace {

PreconditionCheckResult PreconditionFailure(const std::wstring& message, int passed, int failed) {
    PreconditionCheckResult result;
    result.ok = false;
    result.errorCode = L"PRECONDITION_FAILED";
    result.errorMessage = message;
    result.passedCount = passed;
    result.failedCount = failed;
    std::wstringstream data;
    data << L"{\"ok\":false,\"passed_count\":" << passed
         << L",\"failed_count\":" << failed
         << L",\"failure_reason\":\"PRECONDITION_FAILED\""
         << L",\"message\":" << JsonString(message)
         << L"}";
    result.dataJson = data.str();
    return result;
}

bool JsonContainsString(const std::wstring& json, const std::wstring& key, const std::wstring& value) {
    return json.find(L"\"" + key + L"\"") != std::wstring::npos &&
           json.find(L"\"" + value + L"\"") != std::wstring::npos;
}

bool JsonContainsElementId(const std::wstring& json, const std::wstring& elementId) {
    return json.find(L"\"element_id\": \"" + elementId + L"\"") != std::wstring::npos ||
           json.find(L"\"element_id\":\"" + elementId + L"\"") != std::wstring::npos;
}

}  // namespace

PreconditionCheckResult CheckStepPreconditions(const std::wstring& contractPath, const std::wstring& perceptionPath) {
    StepContractValidationResult contractResult = ValidateStepContractFile(contractPath);
    if (!contractResult.ok) {
        PreconditionCheckResult result;
        result.ok = false;
        result.errorCode = contractResult.errorCode;
        result.errorMessage = contractResult.errorMessage;
        result.dataJson = contractResult.dataJson;
        return result;
    }

    FileReadResult perceptionFile = ReadTextFile(perceptionPath);
    if (!perceptionFile.ok) {
        PreconditionCheckResult result;
        result.ok = false;
        result.errorCode = perceptionFile.errorCode.empty() ? L"FILE_READ_FAILED" : perceptionFile.errorCode;
        result.errorMessage = L"Could not read perception file: " + perceptionFile.error;
        result.dataJson = L"{\"perception\":" + JsonString(perceptionPath) + L"}";
        return result;
    }

    const StepContract& contract = contractResult.contract;
    const std::wstring& perception = perceptionFile.content;
    int passed = 0;

    std::wstring sceneObj = JsonGetObject(perception, L"scene_state");
    std::wstring actualScene = JsonGetString(sceneObj, L"status");
    if (!contract.preconditionExpectedSceneState.empty() && actualScene != contract.preconditionExpectedSceneState) {
        return PreconditionFailure(L"scene_state expected " + contract.preconditionExpectedSceneState + L" but was " + actualScene, passed, 1);
    }
    ++passed;

    if (!contract.preconditionElementId.empty() && !JsonContainsElementId(perception, contract.preconditionElementId)) {
        return PreconditionFailure(L"required element missing: " + contract.preconditionElementId, passed, 1);
    }
    ++passed;

    if (contract.requiresTargetReady && !JsonGetBool(perception, L"target_ready", false)) {
        return PreconditionFailure(L"target_ready expected true.", passed, 1);
    }
    ++passed;

    std::wstring windowObj = JsonGetObject(perception, L"window");
    if (contract.requiresWindowFocused && !JsonGetBool(windowObj, L"focused", false)) {
        return PreconditionFailure(L"window focused expected true.", passed, 1);
    }
    ++passed;

    std::wstring profileObj = JsonGetObject(perception, L"profile");
    std::wstring activeProfile = JsonGetString(profileObj, L"active");
    if (!contract.requiredProfile.empty() && activeProfile != contract.requiredProfile) {
        return PreconditionFailure(L"profile active expected " + contract.requiredProfile + L".", passed, 1);
    }
    ++passed;

    if (!contract.requiredSafetyAction.empty() && !JsonContainsString(perception, L"allowed_actions", contract.requiredSafetyAction)) {
        return PreconditionFailure(L"safety allowed action missing: " + contract.requiredSafetyAction, passed, 1);
    }
    ++passed;

    if (!contract.requiredCapability.empty() && !JsonContainsString(perception, L"capabilities", contract.requiredCapability)) {
        return PreconditionFailure(L"capability unavailable: " + contract.requiredCapability, passed, 1);
    }
    ++passed;

    PreconditionCheckResult result;
    result.ok = true;
    result.passedCount = passed;
    result.failedCount = 0;
    std::wstringstream data;
    data << L"{\"ok\":true"
         << L",\"step_id\":" << JsonString(contract.stepId)
         << L",\"passed_count\":" << passed
         << L",\"failed_count\":0"
         << L",\"checks\":[\"scene_state\",\"element_exists\",\"target_ready\",\"window_focused\",\"profile_active\",\"safety_allowed\",\"capability_available\"]"
         << L"}";
    result.dataJson = data.str();
    return result;
}

namespace {

StepVerificationResult VerificationFailure(const std::wstring& code, const std::wstring& message, const std::wstring& dataJson) {
    StepVerificationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = dataJson;
    return result;
}

bool ContainsQuotedValue(const std::wstring& json, const std::wstring& value) {
    return json.find(L"\"" + value + L"\"") != std::wstring::npos;
}

}  // namespace

StepVerificationResult VerifyStepAfterAction(
    const std::wstring& contractPath,
    const std::wstring& beforePath,
    const std::wstring& afterPath,
    int timeoutMs,
    int elapsedMs) {
    StepContractValidationResult contractResult = ValidateStepContractFile(contractPath);
    if (!contractResult.ok) {
        return VerificationFailure(contractResult.errorCode, contractResult.errorMessage, contractResult.dataJson);
    }
    if (timeoutMs <= 0) timeoutMs = contractResult.contract.timeoutMs;
    if (timeoutMs > 0 && elapsedMs >= timeoutMs) {
        std::wstring data = L"{\"ok\":false,\"failure_reason\":\"VERIFICATION_TIMEOUT\",\"timeout_ms\":" + std::to_wstring(timeoutMs)
            + L",\"elapsed_ms\":" + std::to_wstring(elapsedMs) + L"}";
        return VerificationFailure(L"VERIFICATION_TIMEOUT", L"Step verification timed out.", data);
    }

    FileReadResult beforeFile = ReadTextFile(beforePath);
    if (!beforeFile.ok) {
        return VerificationFailure(beforeFile.errorCode.empty() ? L"FILE_READ_FAILED" : beforeFile.errorCode, L"Could not read before perception file: " + beforeFile.error, L"{}");
    }
    FileReadResult afterFile = ReadTextFile(afterPath);
    if (!afterFile.ok) {
        return VerificationFailure(afterFile.errorCode.empty() ? L"FILE_READ_FAILED" : afterFile.errorCode, L"Could not read after perception file: " + afterFile.error, L"{}");
    }

    const StepContract& contract = contractResult.contract;
    const std::wstring& before = beforeFile.content;
    const std::wstring& after = afterFile.content;

    std::wstring afterScene = JsonGetString(JsonGetObject(after, L"scene_state"), L"status");
    bool sceneOk = afterScene == contract.expectedSceneState;
    if (!sceneOk) {
        std::wstring data = L"{\"ok\":false,\"failure_reason\":\"UNEXPECTED_SCENE\",\"expected_scene_state\":"
            + JsonString(contract.expectedSceneState) + L",\"actual_scene_state\":" + JsonString(afterScene) + L"}";
        return VerificationFailure(L"VERIFICATION_FAILED", L"expected SceneState was not observed: " + contract.expectedSceneState, data);
    }

    for (const std::wstring& eventName : contract.expectedChangeEvents) {
        bool eventOk = false;
        if (eventName == L"region_changed") {
            eventOk = JsonGetBool(after, L"region_changed", false) || ContainsQuotedValue(after, eventName);
        } else {
            eventOk = ContainsQuotedValue(after, eventName);
        }
        if (!eventOk) {
            std::wstring data = L"{\"ok\":false,\"failure_reason\":\"MISSING_CHANGE_EVENT\",\"change_event_ok\":false,\"missing\":"
                + JsonString(eventName) + L"}";
            return VerificationFailure(L"VERIFICATION_FAILED", L"expected ChangeEvent missing: " + eventName, data);
        }
    }

    for (const StepElementExpectation& expectation : contract.expectedElements) {
        bool beforeHas = JsonContainsElementId(before, expectation.elementId);
        bool afterHas = JsonContainsElementId(after, expectation.elementId);
        std::wstring condition = expectation.condition.empty() ? L"appeared" : expectation.condition;
        bool elementOk = false;
        if (condition == L"appeared") {
            elementOk = !beforeHas && afterHas;
        } else if (condition == L"disappeared") {
            elementOk = beforeHas && !afterHas;
        } else if (condition == L"exists") {
            elementOk = afterHas;
        } else if (condition == L"absent") {
            elementOk = !afterHas;
        }
        if (!elementOk) {
            std::wstring data = L"{\"ok\":false,\"failure_reason\":\"ELEMENT_CONDITION_FAILED\",\"element_id\":"
                + JsonString(expectation.elementId) + L",\"condition\":" + JsonString(condition) + L"}";
            return VerificationFailure(L"VERIFICATION_FAILED", L"expected ElementGraph condition failed: " + expectation.elementId + L" " + condition, data);
        }
    }

    bool textAppearedOk = true;
    bool textDisappearedOk = true;
    if (!contract.verificationExpectedText.empty() && contract.verificationType == L"text_appeared") {
        textAppearedOk = before.find(contract.verificationExpectedText) == std::wstring::npos &&
                         after.find(contract.verificationExpectedText) != std::wstring::npos;
        if (!textAppearedOk) {
            return VerificationFailure(L"VERIFICATION_FAILED", L"expected text appeared condition failed.", L"{\"ok\":false,\"failure_reason\":\"TEXT_APPEARED_FAILED\",\"text_appeared_ok\":false}");
        }
    }
    if (!contract.verificationExpectedText.empty() && contract.verificationType == L"text_disappeared") {
        textDisappearedOk = before.find(contract.verificationExpectedText) != std::wstring::npos &&
                            after.find(contract.verificationExpectedText) == std::wstring::npos;
        if (!textDisappearedOk) {
            return VerificationFailure(L"VERIFICATION_FAILED", L"expected text disappeared condition failed.", L"{\"ok\":false,\"failure_reason\":\"TEXT_DISAPPEARED_FAILED\",\"text_disappeared_ok\":false}");
        }
    }

    bool regionChangedRequired = HasStringValue(contract.expectedChangeEvents, L"region_changed");
    bool regionChanged = !regionChangedRequired || JsonGetBool(after, L"region_changed", false) || ContainsQuotedValue(after, L"region_changed");
    if (!regionChanged) {
        return VerificationFailure(L"VERIFICATION_FAILED", L"expected region changed condition failed.", L"{\"ok\":false,\"failure_reason\":\"REGION_CHANGED_FAILED\",\"region_changed_ok\":false}");
    }

    StepVerificationResult result;
    result.ok = true;
    std::wstringstream data;
    data << L"{\"ok\":true"
         << L",\"step_id\":" << JsonString(contract.stepId)
         << L",\"scene_state_ok\":true"
         << L",\"change_event_ok\":true"
         << L",\"element_appeared_ok\":true"
         << L",\"text_appeared_ok\":" << (textAppearedOk ? L"true" : L"false")
         << L",\"text_disappeared_ok\":" << (textDisappearedOk ? L"true" : L"false")
         << L",\"region_changed_ok\":" << (regionChanged ? L"true" : L"false")
         << L",\"timeout_ms\":" << timeoutMs
         << L",\"elapsed_ms\":" << elapsedMs
         << L"}";
    result.dataJson = data.str();
    return result;
}

FailureReasonRecord ClassifyStepFailureReason(const std::wstring& stepId, const std::wstring& errorCode) {
    FailureReasonRecord record;
    record.stepId = stepId;
    record.rawErrorCode = errorCode;
    record.failureReason = errorCode;

    if (errorCode == L"PRECONDITION_FAILED") {
        record.category = L"precondition";
        record.recommendedAction = L"Stop before action and refresh perception state.";
    } else if (errorCode == L"LOCATOR_NOT_FOUND") {
        record.category = L"locator";
        record.recommendedAction = L"Re-observe and update the step locator.";
    } else if (errorCode == L"TARGET_NOT_READY") {
        record.category = L"readiness";
        record.recommendedAction = L"Wait or re-observe until target_ready is true.";
    } else if (errorCode == L"ACTION_FAILED") {
        record.category = L"action";
        record.recommendedAction = L"Stop and inspect the action result before retrying.";
    } else if (errorCode == L"ACTION_NO_EFFECT") {
        record.category = L"verification";
        record.recommendedAction = L"Treat as failed verification and avoid reporting success.";
    } else if (errorCode == L"VERIFICATION_TIMEOUT") {
        record.category = L"verification";
        record.recommendedAction = L"Stop after timeout and record latest observed state.";
    } else if (errorCode == L"UNEXPECTED_SCENE") {
        record.category = L"scene";
        record.recommendedAction = L"Escalate or require confirmation for unexpected scene.";
    } else if (errorCode == L"SAFETY_DENIED") {
        record.category = L"safety";
        record.recommendedAction = L"Stop. Do not bypass safety policy.";
    } else if (errorCode == L"SEMANTIC_UNRESOLVED") {
        record.category = L"semantic";
        record.recommendedAction = L"Escalate only through allowed semantic_unresolved path.";
    } else {
        record.failureReason = L"ACTION_FAILED";
        record.category = L"unknown";
        record.recommendedAction = L"Stop and classify the error before continuing.";
    }

    std::wstringstream data;
    data << L"{\"step_id\":" << JsonString(record.stepId)
         << L",\"raw_error_code\":" << JsonString(record.rawErrorCode)
         << L",\"failure_reason\":" << JsonString(record.failureReason)
         << L",\"category\":" << JsonString(record.category)
         << L",\"recommended_action\":" << JsonString(record.recommendedAction)
         << L"}";
    record.dataJson = data.str();
    return record;
}
