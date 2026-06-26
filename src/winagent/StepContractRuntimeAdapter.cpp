#include "StepContractRuntimeAdapter.h"

#include "Trace.h"

#include <cwctype>
#include <sstream>

namespace {

std::wstring Lower(std::wstring value) {
    for (wchar_t& ch : value) ch = static_cast<wchar_t>(std::towlower(ch));
    return value;
}

std::wstring RequiredMarkerFromExpectedContext(const simplejson::Value& expectedContext) {
    const simplejson::Value* markers = simplejson::Find(expectedContext, L"required_markers");
    if (markers && markers->IsArray() && !markers->arrayValue.empty() && markers->arrayValue.front().IsString()) {
        return markers->arrayValue.front().stringValue;
    }
    return L"";
}

std::wstring ExpectedContextForSession(const simplejson::Value& expectedContext) {
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << simplejson::Quote(simplejson::GetString(expectedContext, L"expected_process_pattern"))
         << L",\"expected_title_pattern\":" << simplejson::Quote(simplejson::GetString(expectedContext, L"expected_title_pattern"))
         << L",\"required_marker\":" << simplejson::Quote(RequiredMarkerFromExpectedContext(expectedContext))
         << L"}";
    return json.str();
}

std::wstring StepError(const std::wstring& code, const std::wstring& message) {
    return L"{\"error_code\":" + JsonString(code) + L",\"error_message\":" + JsonString(message) + L"}";
}

}  // namespace

std::wstring RuntimeSessionActionForStepContractAction(const std::wstring& runtimeAction) {
    std::wstring action = Lower(runtimeAction);
    if (action == L"explorer_open_path" || action == L"explorer_open_file" || action == L"browser_open_page" || action == L"browser_read_page" || action == L"browser_surface_normalize" || action == L"wait_for_context") return L"observe";
    if (action == L"browser_wrong_page_recovery") return L"observe";
    if (action == L"explorer_rename_file" || action == L"explorer_move_file" || action == L"explorer_delete_file" || action == L"explorer_context_menu_action") return L"click_and_verify_context";
    if (action == L"browser_fill_form") return L"type_and_verify_text";
    if (action == L"browser_submit_form") return L"click_and_verify_context";
    if (action == L"communication_create_draft" || action == L"communication_create_message" || action == L"communication_create_email") return L"type_and_verify_text";
    if (action == L"explorer_scroll_and_locate") return L"scroll_and_locate";
    if (action == L"browser_scroll_page" || action == L"browser_locate_text") return L"scroll_and_locate";
    if (action == L"click_target" || action == L"click" || action == L"click_submit" || action == L"run_button_click" || action == L"local_mock_mail_fill" || action == L"code_editor_run_mock") return L"click_and_verify_focus";
    if (action == L"type_text" || action == L"type") return L"type_and_verify_text";
    if (action == L"verify_marker" || action == L"verify" || action == L"observe" || action == L"locate") return L"observe";
    if (action == L"scroll_and_locate" || action == L"scroll") return L"scroll_and_locate";
    if (action == L"non_executable_stop" || action == L"stop") return L"stop";
    return L"unsupported";
}

StepContractRuntimeAdapterResult AdaptStepContractToRuntimeSessionSteps(const simplejson::Value& root) {
    StepContractRuntimeAdapterResult result;
    const simplejson::Value* contracts = simplejson::Find(root, L"contracts");
    if (!contracts || !contracts->IsArray()) {
        result.errorCode = L"COMPILE_SCHEMA_INVALID";
        result.errorMessage = L"StepContract contracts array is missing.";
        result.sessionStepsJson = StepError(result.errorCode, result.errorMessage);
        return result;
    }

    std::wstringstream json;
    json << L"{\"schema_version\":\"6.4.0.runtime_session_steps\""
         << L",\"adapter_used\":true"
         << L",\"runtime_session_compatible\":true"
         << L",\"session_steps\":[";
    for (size_t i = 0; i < contracts->arrayValue.size(); ++i) {
        const simplejson::Value& step = contracts->arrayValue[i];
        if (!step.IsObject()) {
            result.errorCode = L"COMPILE_SCHEMA_INVALID";
            result.errorMessage = L"StepContract entry is not an object.";
            result.sessionStepsJson = StepError(result.errorCode, result.errorMessage);
            return result;
        }
        std::wstring runtimeAction = simplejson::GetString(step, L"runtime_action");
        std::wstring sessionAction = RuntimeSessionActionForStepContractAction(runtimeAction);
        if (sessionAction == L"unsupported") {
            result.errorCode = L"COMPILE_UNSUPPORTED_ACTION";
            result.errorMessage = L"Unsupported runtime_action for RuntimeSession adapter.";
            result.sessionStepsJson = StepError(result.errorCode, result.errorMessage);
            return result;
        }
        const simplejson::Value* expected = simplejson::Find(step, L"expected_context");
        const simplejson::Value* sessionPolicy = simplejson::Find(step, L"session_policy");
        if (i) json << L",";
        json << L"{\"step_id\":" << simplejson::Quote(simplejson::GetString(step, L"step_id"))
             << L",\"action\":" << simplejson::Quote(sessionAction)
             << L",\"target\":" << simplejson::Quote(simplejson::GetString(step, L"target"))
             << L",\"text\":" << simplejson::Quote(simplejson::GetString(step, L"input_text"))
             << L",\"expected_context\":" << (expected && expected->IsObject() ? ExpectedContextForSession(*expected) : L"{}")
             << L",\"action_precondition\":\"step_contract_action_precondition\""
             << L",\"verification_hint\":\"step_contract_verification_hint\""
             << L",\"cache_policy\":" << simplejson::Quote(sessionPolicy && sessionPolicy->IsObject() ? simplejson::GetString(*sessionPolicy, L"cache_policy", L"force_reobserve") : L"force_reobserve")
             << L",\"force_reobserve\":" << simplejson::Bool(sessionPolicy && sessionPolicy->IsObject() ? simplejson::GetBool(*sessionPolicy, L"force_reobserve_before_action", true) : true)
             << L",\"stop_on_failure\":true}";
    }
    json << L"]}";
    result.ok = true;
    result.stepCount = static_cast<int>(contracts->arrayValue.size());
    result.sessionStepsJson = json.str();
    return result;
}

StepContractRuntimeAdapterResult AdaptStepContractJsonToRuntimeSessionSteps(const std::wstring& stepContractJson) {
    simplejson::ParseResult parsed = simplejson::Parse(stepContractJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        StepContractRuntimeAdapterResult result;
        result.errorCode = L"COMPILE_SCHEMA_INVALID";
        result.errorMessage = L"StepContract JSON is malformed.";
        result.sessionStepsJson = StepError(result.errorCode, result.errorMessage);
        return result;
    }
    return AdaptStepContractToRuntimeSessionSteps(parsed.root);
}
