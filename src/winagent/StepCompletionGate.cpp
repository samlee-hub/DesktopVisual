#include "StepCompletionGate.h"

#include "Trace.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring Trim(std::wstring value) {
    auto first = std::find_if_not(value.begin(), value.end(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    });
    auto last = std::find_if_not(value.rbegin(), value.rend(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    }).base();
    if (first >= last) return L"";
    return std::wstring(first, last);
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

bool FindJsonKey(const std::wstring& json, const std::wstring& key, size_t& colon) {
    const std::wstring quoted = L"\"" + key + L"\"";
    size_t pos = json.find(quoted);
    if (pos == std::wstring::npos) return false;
    colon = json.find(L":", pos + quoted.size());
    return colon != std::wstring::npos;
}

bool ExtractObjectSection(const std::wstring& json, const std::wstring& key, std::wstring& section) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t open = json.find(L"{", colon + 1);
    if (open == std::wstring::npos) return false;

    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (size_t i = open; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
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
        if (ch == L'{') {
            ++depth;
        } else if (ch == L'}') {
            --depth;
            if (depth == 0) {
                section = json.substr(open, i - open + 1);
                return true;
            }
        }
    }
    return false;
}

std::wstring UnescapeJsonString(const std::wstring& value) {
    std::wstring result;
    bool escaped = false;
    for (wchar_t ch : value) {
        if (!escaped) {
            if (ch == L'\\') {
                escaped = true;
            } else {
                result += ch;
            }
            continue;
        }
        switch (ch) {
            case L'n':
                result += L'\n';
                break;
            case L'r':
                result += L'\r';
                break;
            case L't':
                result += L'\t';
                break;
            case L'"':
                result += L'"';
                break;
            case L'\\':
                result += L'\\';
                break;
            default:
                result += ch;
                break;
        }
        escaped = false;
    }
    if (escaped) result += L'\\';
    return result;
}

bool FindJsonString(const std::wstring& json, const std::wstring& key, std::wstring& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t quote = json.find(L"\"", colon + 1);
    if (quote == std::wstring::npos) return false;

    std::wstring raw;
    bool escaped = false;
    for (size_t i = quote + 1; i < json.size(); ++i) {
        wchar_t ch = json[i];
        if (!escaped && ch == L'"') {
            value = UnescapeJsonString(raw);
            return true;
        }
        if (!escaped && ch == L'\\') {
            escaped = true;
            raw += ch;
        } else {
            escaped = false;
            raw += ch;
        }
    }
    return false;
}

bool FindJsonBool(const std::wstring& json, const std::wstring& key, bool& value) {
    size_t colon = 0;
    if (!FindJsonKey(json, key, colon)) return false;
    size_t pos = colon + 1;
    while (pos < json.size() && std::iswspace(json[pos]) != 0) ++pos;
    if (json.compare(pos, 4, L"true") == 0) {
        value = true;
        return true;
    }
    if (json.compare(pos, 5, L"false") == 0) {
        value = false;
        return true;
    }
    return false;
}

bool FindObjectBool(const std::wstring& json, const std::wstring& objectKey, const std::wstring& boolKey, bool& value) {
    std::wstring section;
    if (!ExtractObjectSection(json, objectKey, section)) return false;
    return FindJsonBool(section, boolKey, value);
}

std::wstring FindStringOrEmpty(const std::wstring& json, const std::wstring& key) {
    std::wstring value;
    FindJsonString(json, key, value);
    return value;
}

std::wstring FindObjectOrEmpty(const std::wstring& json, const std::wstring& key) {
    std::wstring section;
    ExtractObjectSection(json, key, section);
    return section;
}

bool FindBoolWithFallback(
    const std::wstring& json,
    const std::wstring& key,
    const std::wstring& objectKey,
    const std::wstring& objectBoolKey,
    bool defaultValue) {
    bool value = defaultValue;
    if (FindJsonBool(json, key, value)) return value;
    if (!objectKey.empty() && FindObjectBool(json, objectKey, objectBoolKey, value)) return value;
    return defaultValue;
}

void ApplyPycharmSpecificGates(const StepCompletionInput& input, StepCompletionResult& result, std::wstring& specificReason, std::wstring& specificAttribution) {
    const std::wstring stepType = ToLowerInvariant(input.stepType);
    const std::wstring stepName = ToLowerInvariant(input.stepName);

    if (ContainsInsensitive(stepType, L"pycharm_editor_click") || ContainsInsensitive(stepName, L"editor click")) {
        if (input.editorClickedByMouseProvided && !input.editorClickedByMouse) {
            result.actionExecuted = false;
            result.postconditionVerified = false;
            specificAttribution = L"EDITOR_FOCUS_NOT_VERIFIED";
            specificReason = L"PyCharm editor click/focus gate failed; code type is forbidden until editor mouse click and focus are verified.";
        } else if (input.editorFocusVerifiedProvided && !input.editorFocusVerified) {
            result.postconditionVerified = false;
            specificAttribution = L"EDITOR_FOCUS_NOT_VERIFIED";
            specificReason = L"PyCharm editor focus was not verified; code type is forbidden.";
        }
    }

    if (ContainsInsensitive(stepType, L"pycharm_code_type") || ContainsInsensitive(stepName, L"code type")) {
        if (input.codeTextVerifiedProvided && !input.codeTextVerified) {
            result.postconditionVerified = false;
            specificAttribution = L"CODE_TEXT_NOT_VERIFIED";
            specificReason = L"PyCharm code text was not verified; run shortcut is forbidden.";
        }
    }

    if (ContainsInsensitive(stepType, L"pycharm_run") || ContainsInsensitive(stepName, L"run gate")) {
        if (input.runTriggeredProvided) {
            result.actionExecuted = input.runTriggered;
        }
        if (input.executionSuccessProvided && !input.executionSuccess) {
            result.postconditionVerified = false;
            specificAttribution = L"CODE_EXECUTION_ERROR";
            specificReason = L"PyCharm run was triggered but execution_success=false; this is not a run shortcut failure.";
        }
    }
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

}  // namespace

StepCompletionInput ParseStepCompletionInputJson(const std::wstring& jsonText) {
    StepCompletionInput input;
    input.stepId = FindStringOrEmpty(jsonText, L"step_id");
    input.stepName = FindStringOrEmpty(jsonText, L"step_name");
    input.stepType = FindStringOrEmpty(jsonText, L"step_type");
    input.expectedContext = FindObjectOrEmpty(jsonText, L"expected_context");
    input.expectedPreconditions = FindObjectOrEmpty(jsonText, L"expected_preconditions");
    input.actionName = FindStringOrEmpty(jsonText, L"action_name");
    input.actionResult = FindObjectOrEmpty(jsonText, L"action_result");
    input.rawActionEvidence = FindObjectOrEmpty(jsonText, L"raw_action_evidence");
    input.postObserveResult = FindObjectOrEmpty(jsonText, L"post_observe_result");
    input.expectedPostconditions = FindObjectOrEmpty(jsonText, L"expected_postconditions");
    input.failureAttributionOnFail = FindStringOrEmpty(jsonText, L"failure_attribution_on_fail");

    input.preconditionVerified = FindBoolWithFallback(jsonText, L"precondition_verified", L"expected_preconditions", L"verified", true);
    input.actionExecuted = FindBoolWithFallback(jsonText, L"action_executed", L"action_result", L"action_executed", true);
    if (!FindJsonBool(jsonText, L"action_executed", input.actionExecuted)) {
        bool nested = input.actionExecuted;
        if (FindObjectBool(jsonText, L"action_result", L"executed", nested)) input.actionExecuted = nested;
    }
    input.postObserveRequired = FindBoolWithFallback(jsonText, L"post_observe_required", L"", L"", false);
    input.postObservePerformed = FindBoolWithFallback(jsonText, L"post_observe_performed", L"post_observe_result", L"performed", !input.postObserveRequired);
    input.postconditionVerified = FindBoolWithFallback(jsonText, L"postcondition_verified", L"expected_postconditions", L"verified", true);

    input.editorClickedByMouseProvided = FindJsonBool(jsonText, L"editor_clicked_by_mouse", input.editorClickedByMouse);
    input.editorFocusVerifiedProvided = FindJsonBool(jsonText, L"editor_focus_verified", input.editorFocusVerified);
    input.codeTextVerifiedProvided = FindJsonBool(jsonText, L"code_text_verified", input.codeTextVerified);
    input.runTriggeredProvided = FindJsonBool(jsonText, L"run_triggered", input.runTriggered);
    input.executionSuccessProvided = FindJsonBool(jsonText, L"execution_success", input.executionSuccess);
    return input;
}

StepCompletionResult EvaluateStepCompletionGate(const StepCompletionInput& input) {
    StepCompletionResult result;
    result.stepId = input.stepId;
    result.preconditionVerified = input.preconditionVerified;
    result.actionExecuted = input.actionExecuted;
    result.postObservePerformed = input.postObservePerformed;
    result.postconditionVerified = input.postconditionVerified;
    result.runTriggeredProvided = input.runTriggeredProvided;
    result.runTriggered = input.runTriggered;
    result.executionSuccessProvided = input.executionSuccessProvided;
    result.executionSuccess = input.executionSuccess;

    std::wstring specificReason;
    std::wstring specificAttribution;
    ApplyPycharmSpecificGates(input, result, specificReason, specificAttribution);

    if (!result.preconditionVerified) {
        result.actionExecuted = false;
        result.stepVerified = false;
        result.nextStepAllowed = false;
        result.stopCode = L"STEP_PRECONDITION_FAILED";
        result.failureAttribution = input.failureAttributionOnFail.empty() ? L"PRECONDITION_FAILED" : input.failureAttributionOnFail;
        result.reason = L"Step precondition was not verified; action execution and next step are blocked.";
        return result;
    }

    if (!result.actionExecuted) {
        result.stepVerified = false;
        result.nextStepAllowed = false;
        result.stopCode = L"STEP_ACTION_NOT_EXECUTED";
        result.failureAttribution = !specificAttribution.empty()
            ? specificAttribution
            : (input.failureAttributionOnFail.empty() ? L"ACTION_NOT_EXECUTED" : input.failureAttributionOnFail);
        result.reason = !specificReason.empty() ? specificReason : L"Step action was not executed; next step is blocked.";
        return result;
    }

    if (input.postObserveRequired && !result.postObservePerformed) {
        result.stepVerified = false;
        result.nextStepAllowed = false;
        result.stopCode = L"STEP_POST_OBSERVE_MISSING";
        result.failureAttribution = input.failureAttributionOnFail.empty() ? L"POST_OBSERVE_MISSING" : input.failureAttributionOnFail;
        result.reason = L"Post-action observe was required but not performed; next step is blocked.";
        return result;
    }

    if (!result.postconditionVerified) {
        result.stepVerified = false;
        result.nextStepAllowed = false;
        result.stopCode = L"STEP_POSTCONDITION_FAILED";
        result.failureAttribution = !specificAttribution.empty()
            ? specificAttribution
            : (input.failureAttributionOnFail.empty() ? L"POSTCONDITION_FAILED" : input.failureAttributionOnFail);
        result.reason = !specificReason.empty() ? specificReason : L"Step postcondition was not verified; next step is blocked.";
        return result;
    }

    result.stepVerified = true;
    result.nextStepAllowed = true;
    result.stopCode = L"STEP_OK";
    result.failureAttribution = L"NONE";
    result.reason = L"Step verified; next step allowed.";
    return result;
}

std::wstring StepCompletionResultJson(const StepCompletionResult& result) {
    std::wstringstream json;
    json << L"{"
         << L"\"schema_version\":\"v6.1.6.step_completion_result\","
         << L"\"step_id\":" << JsonString(result.stepId) << L","
         << L"\"precondition_verified\":" << BoolJson(result.preconditionVerified) << L","
         << L"\"action_executed\":" << BoolJson(result.actionExecuted) << L","
         << L"\"post_observe_performed\":" << BoolJson(result.postObservePerformed) << L","
         << L"\"postcondition_verified\":" << BoolJson(result.postconditionVerified) << L","
         << L"\"step_verified\":" << BoolJson(result.stepVerified) << L","
         << L"\"next_step_allowed\":" << BoolJson(result.nextStepAllowed) << L","
         << L"\"stop_code\":" << JsonString(result.stopCode) << L","
         << L"\"failure_attribution\":" << JsonString(result.failureAttribution) << L","
         << L"\"reason\":" << JsonString(result.reason) << L","
         << L"\"evidence_path\":" << JsonString(result.evidencePath);
    if (result.runTriggeredProvided) {
        json << L",\"run_triggered\":" << BoolJson(result.runTriggered);
    }
    if (result.executionSuccessProvided) {
        json << L",\"execution_success\":" << BoolJson(result.executionSuccess);
    }
    json << L"}";
    return json.str();
}
