#include "BrowserWorkflowAdapter.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "StepContractValidator.h"
#include "Trace.h"

#include <windows.h>

#include <cstdio>
#include <iostream>
#include <sstream>
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

bool WriteTextFileUtf8(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) EnsureDirectoryPath(path.substr(0, slash));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

BrowserWorkflowCompileResult CompileFailure(const std::wstring& code, const std::wstring& message, const std::wstring& diagnostics = L"{}") {
    BrowserWorkflowCompileResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.contractJson = L"{\"schema_version\":\"6.3.0.step_contract\",\"compiler_version\":\"6.8.0.browser_workflow\",\"compile_ok\":false,\"contracts\":[]}";
    result.diagnosticsJson = diagnostics == L"{}"
        ? L"{\"schema_version\":\"6.8.0.browser_workflow.compile_diagnostics\",\"compile_ok\":false,\"error_code\":" + simplejson::Quote(code) + L",\"error_message\":" + simplejson::Quote(message) + L"}"
        : diagnostics;
    return result;
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::vector<std::wstring> ObjectStringArrayOr(const std::wstring& objectJson, const std::wstring& key, const std::vector<std::wstring>& fallback) {
    simplejson::ParseResult parsed = simplejson::Parse(objectJson);
    if (!parsed.ok || !parsed.root.IsObject()) return fallback;
    std::vector<std::wstring> values = simplejson::GetStringArray(parsed.root, key);
    return values.empty() ? fallback : values;
}

std::wstring ObjectStringOr(const std::wstring& objectJson, const std::wstring& key, const std::wstring& fallback) {
    simplejson::ParseResult parsed = simplejson::Parse(objectJson);
    if (!parsed.ok || !parsed.root.IsObject()) return fallback;
    std::wstring value = simplejson::GetString(parsed.root, key);
    return value.empty() ? fallback : value;
}

bool ObjectBoolOr(const std::wstring& objectJson, const std::wstring& key, bool fallback) {
    simplejson::ParseResult parsed = simplejson::Parse(objectJson);
    if (!parsed.ok || !parsed.root.IsObject()) return fallback;
    return simplejson::GetBool(parsed.root, key, fallback);
}

std::wstring CompleteExpectedContextJson(const BrowserWorkflowSpec& spec) {
    std::wstring process = ObjectStringOr(spec.expectedContextJson, L"expected_process_pattern", L"chrome.exe|msedge.exe");
    std::wstring title = ObjectStringOr(spec.expectedContextJson, L"expected_title_pattern", spec.expectedTitlePattern);
    std::vector<std::wstring> markers = ObjectStringArrayOr(spec.expectedContextJson, L"required_markers", spec.requiredMarkers);
    std::vector<std::wstring> wrong = ObjectStringArrayOr(spec.expectedContextJson, L"wrong_page_patterns", spec.wrongPagePatterns);
    std::vector<std::wstring> protection = ObjectStringArrayOr(spec.expectedContextJson, L"active_protection_patterns", spec.activeProtectionPatterns);
    std::vector<std::wstring> credentials = ObjectStringArrayOr(spec.expectedContextJson, L"credential_required_patterns", spec.credentialRequiredPatterns);
    bool foreground = ObjectBoolOr(spec.expectedContextJson, L"foreground_required", true);
    bool binding = ObjectBoolOr(spec.expectedContextJson, L"window_binding_required", true);
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << simplejson::Quote(process.empty() ? L"chrome.exe|msedge.exe" : process)
         << L",\"expected_title_pattern\":" << simplejson::Quote(title)
         << L",\"required_markers\":" << StringArrayJson(markers)
         << L",\"wrong_page_patterns\":" << StringArrayJson(wrong)
         << L",\"active_protection_patterns\":" << StringArrayJson(protection)
         << L",\"credential_required_patterns\":" << StringArrayJson(credentials)
         << L",\"foreground_required\":" << simplejson::Bool(foreground)
         << L",\"window_binding_required\":" << simplejson::Bool(binding)
         << L"}";
    return json.str();
}

std::wstring VerifyTypeForWorkflow(const BrowserWorkflowSpec& spec, const std::wstring& runtimeAction) {
    if (runtimeAction == L"browser_fill_form") return L"verify_field_value";
    if (runtimeAction == L"browser_submit_form") return L"verify_submit_result";
    std::wstring requested = ObjectStringOr(spec.verificationHintJson, L"verify_type", L"");
    if (!requested.empty()) return requested;
    if (spec.workflowType == L"browser_scroll_page") return L"verify_scroll_progress";
    if (spec.workflowType == L"browser_locate_text") return L"verify_text_present";
    return L"verify_page_loaded";
}

std::wstring CompleteVerificationHintJson(const BrowserWorkflowSpec& spec, const std::wstring& runtimeAction, const BrowserWorkflowFieldSpec* field) {
    std::wstring verifyType = VerifyTypeForWorkflow(spec, runtimeAction);
    std::wstring marker = ObjectStringOr(spec.verificationHintJson, L"expected_marker", spec.requiredMarkers.empty() ? L"" : spec.requiredMarkers.front());
    std::wstring text = ObjectStringOr(spec.verificationHintJson, L"expected_text", field ? field->fieldLabel : spec.verificationTargetText);
    std::wstring expectedFieldValue = field ? field->value : ObjectStringOr(spec.verificationHintJson, L"expected_field_value", L"");
    std::wstring resultMarker = spec.formSpec.submit.expectedResultMarker.empty()
        ? ObjectStringOr(spec.verificationHintJson, L"expected_result_marker", marker)
        : spec.formSpec.submit.expectedResultMarker;
    std::wstringstream json;
    json << L"{\"verify_type\":" << simplejson::Quote(verifyType)
         << L",\"expected_marker\":" << simplejson::Quote(marker)
         << L",\"expected_text\":" << simplejson::Quote(text)
         << L",\"expected_window_title\":" << simplejson::Quote(spec.expectedTitlePattern)
         << L",\"expected_url_pattern\":" << simplejson::Quote(spec.expectedUrlPattern)
         << L",\"expected_output_pattern\":" << simplejson::Quote(resultMarker)
         << L",\"expected_result_marker\":" << simplejson::Quote(resultMarker)
         << L",\"expected_field_value\":" << simplejson::Quote(expectedFieldValue)
         << L",\"post_action_reobserve_required\":true}";
    return json.str();
}

std::wstring CompleteStopPolicyJson(const std::wstring& stopPolicyJson) {
    simplejson::ParseResult parsed = simplejson::Parse(stopPolicyJson);
    const simplejson::Value* root = parsed.ok && parsed.root.IsObject() ? &parsed.root : nullptr;
    auto flag = [root](const std::wstring& key) -> bool {
        return root ? simplejson::GetBool(*root, key, true) : true;
    };
    return L"{\"stop_on_wrong_context\":" + simplejson::Bool(flag(L"stop_on_wrong_context")) +
        L",\"stop_on_wrong_field\":" + simplejson::Bool(flag(L"stop_on_wrong_field")) +
        L",\"stop_on_target_stale\":" + simplejson::Bool(flag(L"stop_on_target_stale")) +
        L",\"stop_on_target_not_unique\":" + simplejson::Bool(flag(L"stop_on_target_not_unique")) +
        L",\"stop_on_active_protection\":" + simplejson::Bool(flag(L"stop_on_active_protection")) +
        L",\"stop_on_credential_required\":" + simplejson::Bool(flag(L"stop_on_credential_required")) +
        L",\"stop_on_unverified_result\":" + simplejson::Bool(flag(L"stop_on_unverified_result")) +
        L",\"stop_on_runtime_guard_failure\":" + simplejson::Bool(flag(L"stop_on_runtime_guard_failure")) +
        L"}";
}

std::wstring ActionPreconditionJson(const BrowserWorkflowSpec& spec, const std::wstring& runtimeAction) {
    bool formAction = runtimeAction == L"browser_fill_form" || runtimeAction == L"browser_submit_form";
    bool scrollAction = runtimeAction == L"browser_scroll_page" || runtimeAction == L"browser_locate_text";
    std::wstringstream json;
    json << L"{\"target_required\":" << simplejson::Bool(formAction || runtimeAction == L"browser_locate_text")
         << L",\"target_unique_required\":true"
         << L",\"target_inside_viewport_required\":" << simplejson::Bool(formAction)
         << L",\"target_current_observe_required\":true"
         << L",\"focus_required\":" << simplejson::Bool(formAction)
         << L",\"mouse_first_required\":" << simplejson::Bool(formAction)
         << L",\"text_input_allowed\":" << simplejson::Bool(runtimeAction == L"browser_fill_form")
         << L",\"scroll_allowed\":" << simplejson::Bool(scrollAction || spec.workflowType == L"browser_fill_form" || spec.workflowType == L"browser_submit_form")
         << L",\"stale_target_reject_required\":true}";
    return json.str();
}

std::wstring ConfirmationPolicyJson(const BrowserWorkflowSpec& spec) {
    bool realCommit = spec.riskLevel == L"REAL_COMMIT";
    std::wstringstream json;
    json << L"{\"confirmation_required\":" << simplejson::Bool(realCommit)
         << L",\"confirmation_reason\":" << simplejson::Quote(realCommit ? L"Browser REAL_COMMIT form submission requires explicit confirmation." : L"")
         << L",\"developer_full_access_allowed\":false"
         << L",\"public_release_confirmation_required\":" << simplejson::Bool(realCommit)
         << L",\"manual_handoff_required\":false}";
    return json.str();
}

std::wstring FieldTarget(const BrowserWorkflowFieldSpec& field) {
    if (!field.fieldLabel.empty()) return L"field_label:" + field.fieldLabel;
    if (!field.placeholder.empty()) return L"placeholder:" + field.placeholder;
    if (!field.fieldId.empty()) return L"field_id:" + field.fieldId;
    if (!field.name.empty()) return L"name:" + field.name;
    if (!field.title.empty()) return L"title:" + field.title;
    return L"field";
}

std::wstring StepJson(
    const BrowserWorkflowSpec& spec,
    const std::wstring& runtimeAction,
    const std::wstring& stepType,
    const std::wstring& target,
    const std::wstring& inputText,
    int index,
    bool executable,
    const BrowserWorkflowFieldSpec* field) {
    std::wstring contractId = L"browser-contract-" + spec.workflowId;
    std::wstring stepId = spec.workflowId + L"-step-" + std::to_wstring(index);
    std::wstringstream step;
    step << L"{\"contract_id\":" << simplejson::Quote(contractId)
         << L",\"task_id\":" << simplejson::Quote(spec.taskId)
         << L",\"plan_id\":" << simplejson::Quote(L"browser-plan-" + spec.workflowId)
         << L",\"step_id\":" << simplejson::Quote(stepId)
         << L",\"step_index\":" << index
         << L",\"step_type\":" << simplejson::Quote(stepType)
         << L",\"runtime_action\":" << simplejson::Quote(runtimeAction)
         << L",\"target\":" << simplejson::Quote(target)
         << L",\"input_text\":" << simplejson::Quote(inputText)
         << L",\"executable\":" << simplejson::Bool(executable)
         << L",\"expected_context\":" << CompleteExpectedContextJson(spec)
         << L",\"action_precondition\":" << ActionPreconditionJson(spec, runtimeAction)
         << L",\"verification_hint\":" << CompleteVerificationHintJson(spec, runtimeAction, field)
         << L",\"risk_level\":" << simplejson::Quote(spec.riskLevel)
         << L",\"confirmation_policy\":" << ConfirmationPolicyJson(spec)
         << L",\"recovery_policy\":" << spec.recoveryPolicyJson
         << L",\"stop_policy\":" << CompleteStopPolicyJson(spec.stopPolicyJson)
         << L",\"session_policy\":" << spec.sessionPolicyJson
         << L",\"evidence_policy\":" << spec.evidencePolicyJson
         << L",\"workflow_id\":" << simplejson::Quote(spec.workflowId)
         << L",\"workflow_type\":" << simplejson::Quote(spec.workflowType)
         << L",\"url\":" << simplejson::Quote(spec.url)
         << L",\"browser\":" << simplejson::Quote(spec.browser)
         << L",\"allowed_origin\":" << simplejson::Quote(spec.allowedOrigin)
         << L",\"allowed_url_prefix\":" << simplejson::Quote(spec.allowedUrlPrefix)
         << L",\"submit_policy\":" << (spec.submitPolicyJson.empty() ? L"{}" : spec.submitPolicyJson)
         << L",\"field_id\":" << simplejson::Quote(field ? field->fieldId : L"")
         << L",\"field_label\":" << simplejson::Quote(field ? field->fieldLabel : L"")
         << L",\"field_placeholder\":" << simplejson::Quote(field ? field->placeholder : L"")
         << L",\"field_name\":" << simplejson::Quote(field ? field->name : L"")
         << L",\"field_expected_role\":" << simplejson::Quote(field ? field->expectedRole : L"")
         << L",\"coordinate_source_type\":\"runtime_locator\""
         << L",\"requested_action_backend\":\"runtime_visible_ui\""
         << L",\"created_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"compiler_version\":\"6.8.0.browser_workflow\"}";
    return step.str();
}

std::wstring RuntimeActionForWorkflow(const BrowserWorkflowSpec& spec) {
    if (spec.workflowType == L"browser_active_protection_stop" || spec.workflowType == L"browser_credential_required_stop") return L"non_executable_stop";
    return spec.workflowType;
}

std::wstring StepTypeForWorkflow(const BrowserWorkflowSpec& spec) {
    if (spec.workflowType == L"browser_open_page") return L"browser_open";
    if (spec.workflowType == L"browser_read_page") return L"browser_read";
    if (spec.workflowType == L"browser_scroll_page") return L"browser_scroll";
    if (spec.workflowType == L"browser_locate_text") return L"browser_locate";
    if (spec.workflowType == L"browser_fill_form") return L"browser_form_field";
    if (spec.workflowType == L"browser_submit_form") return L"browser_form_submit";
    if (spec.workflowType == L"browser_wrong_page_recovery") return L"browser_recovery";
    return L"browser_stop";
}

}  // namespace

BrowserWorkflowCompileResult CompileBrowserWorkflowSpec(const BrowserWorkflowSpec& spec) {
    if (!BrowserWorkflowTypeSupported(spec.workflowType)) {
        return CompileFailure(L"COMPILE_SCHEMA_INVALID", L"Unsupported Browser workflow_type.");
    }

    std::vector<std::wstring> steps;
    int index = 0;
    bool blocked = BrowserWorkflowTypeIsBlockedStop(spec.workflowType);
    if (spec.workflowType == L"browser_fill_form" || spec.workflowType == L"browser_submit_form") {
        for (const auto& field : spec.formSpec.fields) {
            steps.push_back(StepJson(spec, L"browser_fill_form", L"browser_form_field", FieldTarget(field), field.value, index++, true, &field));
        }
        if (spec.workflowType == L"browser_submit_form") {
            std::wstring label = spec.formSpec.submit.label.empty() ? L"Submit" : spec.formSpec.submit.label;
            steps.push_back(StepJson(spec, L"browser_submit_form", L"browser_form_submit", L"submit:" + label, label, index++, true, nullptr));
        }
    } else {
        std::wstring runtimeAction = RuntimeActionForWorkflow(spec);
        steps.push_back(StepJson(spec, runtimeAction, StepTypeForWorkflow(spec), spec.url, spec.verificationTargetText, index++, !blocked, nullptr));
    }

    std::wstringstream contractJson;
    contractJson << L"{\"schema_version\":\"6.3.0.step_contract\""
                 << L",\"compiler_version\":\"6.8.0.browser_workflow\""
                 << L",\"compile_ok\":true"
                 << L",\"runtime_executed\":false"
                 << L",\"task_id\":" << simplejson::Quote(spec.taskId)
                 << L",\"plan_id\":" << simplejson::Quote(L"browser-plan-" + spec.workflowId)
                 << L",\"workflow_id\":" << simplejson::Quote(spec.workflowId)
                 << L",\"workflow_type\":" << simplejson::Quote(spec.workflowType)
                 << L",\"contracts\":[";
    for (size_t i = 0; i < steps.size(); ++i) {
        if (i) contractJson << L",";
        contractJson << steps[i];
    }
    contractJson << L"]}";

    StepContractV63ValidationResult validation = ValidateStepContractV63Json(contractJson.str());
    if (!validation.validationOk) {
        return CompileFailure(validation.errorCode.empty() ? L"STEP_CONTRACT_VALIDATION_FAILED" : validation.errorCode,
            validation.errorMessage.empty() ? L"Browser StepContract validation failed." : validation.errorMessage,
            validation.resultJson);
    }

    BrowserWorkflowCompileResult result;
    result.ok = true;
    result.workflowId = spec.workflowId;
    result.workflowType = spec.workflowType;
    result.contractJson = contractJson.str();
    result.diagnosticsJson = L"{\"schema_version\":\"6.8.0.browser_workflow.compile_diagnostics\",\"compile_ok\":true,\"workflow_id\":"
        + simplejson::Quote(spec.workflowId) + L",\"workflow_type\":" + simplejson::Quote(spec.workflowType)
        + L",\"step_contract_validator_used\":true,\"emitted_step_count\":" + std::to_wstring(steps.size())
        + L",\"runtime_executed\":false,\"blocked_step_contract\":" + simplejson::Bool(blocked) + L"}";
    return result;
}

BrowserWorkflowCompileResult CompileBrowserWorkflowSpecJson(const std::wstring& json) {
    BrowserWorkflowSchemaResult schema = ParseBrowserWorkflowSpecJson(json);
    if (!schema.ok) {
        return CompileFailure(schema.errorCode, schema.errorMessage, schema.diagnosticsJson);
    }
    return CompileBrowserWorkflowSpec(schema.spec);
}

BrowserWorkflowCompileResult CompileBrowserWorkflowSpecFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath) {
    BrowserWorkflowSchemaResult schema = ParseBrowserWorkflowSpecFile(inputPath);
    if (!schema.ok) {
        return CompileFailure(schema.errorCode, schema.errorMessage, schema.diagnosticsJson);
    }
    BrowserWorkflowCompileResult result = CompileBrowserWorkflowSpec(schema.spec);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.contractJson, writeError);
    }
    return result;
}

int CommandCompileBrowserWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"compile-browser-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"compile-browser-workflow requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    BrowserWorkflowCompileResult result = CompileBrowserWorkflowSpecFile(input, output);
    std::wstring data = L"{\"compile_ok\":" + simplejson::Bool(result.ok)
        + L",\"input\":" + simplejson::Quote(input)
        + L",\"output\":" + simplejson::Quote(output)
        + L",\"workflow_id\":" + simplejson::Quote(result.workflowId)
        + L",\"workflow_type\":" + simplejson::Quote(result.workflowType)
        + L",\"runtime_executed\":false}";
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMPILE_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.diagnosticsJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}
