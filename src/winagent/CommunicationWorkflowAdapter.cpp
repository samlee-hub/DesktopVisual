#include "CommunicationWorkflowAdapter.h"

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

CommunicationWorkflowCompileResult CompileFailure(
    const std::wstring& code,
    const std::wstring& message,
    const std::wstring& diagnostics = L"{}") {
    CommunicationWorkflowCompileResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.contractJson = L"{\"schema_version\":\"6.3.0.step_contract\",\"compiler_version\":\"6.9.0.communication_workflow\",\"compile_ok\":false,\"contracts\":[]}";
    result.diagnosticsJson = diagnostics == L"{}"
        ? L"{\"schema_version\":\"6.9.0.communication_workflow.compile_diagnostics\",\"compile_ok\":false,\"error_code\":" + simplejson::Quote(code) + L",\"error_message\":" + simplejson::Quote(message) + L"}"
        : diagnostics;
    return result;
}

std::wstring JsonValueToString(const simplejson::Value& value) {
    if (value.IsNull()) return L"null";
    if (value.IsBool()) return simplejson::Bool(value.boolValue);
    if (value.IsNumber()) {
        std::wstringstream stream;
        stream << static_cast<long long>(value.numberValue);
        return stream.str();
    }
    if (value.IsString()) return simplejson::Quote(value.stringValue);
    if (value.IsArray()) {
        std::wstringstream json;
        json << L"[";
        for (size_t i = 0; i < value.arrayValue.size(); ++i) {
            if (i) json << L",";
            json << JsonValueToString(value.arrayValue[i]);
        }
        json << L"]";
        return json.str();
    }
    std::wstringstream json;
    json << L"{";
    bool first = true;
    for (const auto& entry : value.objectValue) {
        if (!first) json << L",";
        first = false;
        json << simplejson::Quote(entry.first) << L":" << JsonValueToString(entry.second);
    }
    json << L"}";
    return json.str();
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

std::vector<std::wstring> ObjectStringArrayOr(const std::wstring& objectJson, const std::wstring& key, const std::vector<std::wstring>& fallback) {
    simplejson::ParseResult parsed = simplejson::Parse(objectJson);
    if (!parsed.ok || !parsed.root.IsObject()) return fallback;
    std::vector<std::wstring> values = simplejson::GetStringArray(parsed.root, key);
    return values.empty() ? fallback : values;
}

std::wstring CompleteExpectedContextJson(const CommunicationWorkflowSpec& spec) {
    std::vector<std::wstring> markers = ObjectStringArrayOr(spec.expectedContextJson, L"required_markers", {L"DV_COMMUNICATION_CONTEXT_MARKER"});
    std::vector<std::wstring> wrong = ObjectStringArrayOr(spec.expectedContextJson, L"wrong_page_patterns", {});
    std::vector<std::wstring> protection = ObjectStringArrayOr(spec.expectedContextJson, L"active_protection_patterns", {L"captcha", L"human verification"});
    std::vector<std::wstring> credentials = ObjectStringArrayOr(spec.expectedContextJson, L"credential_required_patterns", {L"password", L"token"});
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << simplejson::Quote(ObjectStringOr(spec.expectedContextJson, L"expected_process_pattern", L"winagent.exe"))
         << L",\"expected_title_pattern\":" << simplejson::Quote(ObjectStringOr(spec.expectedContextJson, L"expected_title_pattern", L"communication_v6_9"))
         << L",\"required_markers\":" << StringArrayJson(markers)
         << L",\"wrong_page_patterns\":" << StringArrayJson(wrong)
         << L",\"active_protection_patterns\":" << StringArrayJson(protection)
         << L",\"credential_required_patterns\":" << StringArrayJson(credentials)
         << L",\"foreground_required\":" << simplejson::Bool(ObjectBoolOr(spec.expectedContextJson, L"foreground_required", false))
         << L",\"window_binding_required\":" << simplejson::Bool(ObjectBoolOr(spec.expectedContextJson, L"window_binding_required", false))
         << L"}";
    return json.str();
}

std::wstring CompleteVerificationHintJson(const CommunicationWorkflowSpec& spec) {
    std::wstring expectedMarker = ObjectStringOr(spec.verificationHintJson, L"expected_marker", L"DV_COMMUNICATION_CONTEXT_MARKER");
    std::wstring expectedText = ObjectStringOr(spec.verificationHintJson, L"expected_text", spec.subject);
    std::wstring expectedOutput = ObjectStringOr(spec.verificationHintJson, L"expected_output_pattern", spec.body);
    std::wstringstream json;
    json << L"{\"verify_type\":\"verify_communication_created\""
         << L",\"expected_marker\":" << simplejson::Quote(expectedMarker)
         << L",\"expected_text\":" << simplejson::Quote(expectedText)
         << L",\"expected_window_title\":\"communication_v6_9\""
         << L",\"expected_url_pattern\":\"\""
         << L",\"expected_output_pattern\":" << simplejson::Quote(expectedOutput)
         << L",\"expected_field_value\":\"\""
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

std::wstring CompleteActionPreconditionJson() {
    return L"{\"target_required\":true"
           L",\"target_unique_required\":true"
           L",\"target_inside_viewport_required\":false"
           L",\"target_current_observe_required\":true"
           L",\"focus_required\":false"
           L",\"mouse_first_required\":false"
           L",\"text_input_allowed\":true"
           L",\"scroll_allowed\":false"
           L",\"stale_target_reject_required\":true"
           L",\"external_api_disallowed\":true"
           L",\"send_disallowed\":true}";
}

std::wstring TaskIntentJson(const CommunicationWorkflowSpec& spec) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.9.0.communication_task_intent\""
         << L",\"task_id\":" << simplejson::Quote(spec.taskId)
         << L",\"workflow_id\":" << simplejson::Quote(spec.workflowId)
         << L",\"intent_type\":" << simplejson::Quote(CommunicationWorkflowRuntimeActionForType(spec.type))
         << L",\"mode\":\"runtime\""
         << L",\"target_app\":\"communication\""
         << L",\"target_object\":" << simplejson::Quote(spec.type)
         << L",\"recipient\":" << simplejson::Quote(spec.recipient)
         << L",\"context_source\":" << simplejson::Quote(spec.contextSource)
         << L",\"risk_level\":" << simplejson::Quote(spec.riskLevel)
         << L",\"requires_confirmation\":false"
         << L",\"unsupported_reason\":\"\""
         << L",\"planner_boundary\":{\"executes_task\":false,\"calls_vlm_provider\":false}}";
    return json.str();
}

std::wstring AgentPlanDraftJson(const CommunicationWorkflowSpec& spec) {
    std::wstring runtimeAction = CommunicationWorkflowRuntimeActionForType(spec.type);
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.9.0.communication_agent_plan_draft\""
         << L",\"plan_id\":" << simplejson::Quote(L"communication-plan-" + spec.workflowId)
         << L",\"task_id\":" << simplejson::Quote(spec.taskId)
         << L",\"intent_type\":" << simplejson::Quote(runtimeAction)
         << L",\"executor\":\"runtime\""
         << L",\"provider_role\":\"none\""
         << L",\"compile_required\":true"
         << L",\"is_executable\":false"
         << L",\"risk_level\":" << simplejson::Quote(spec.riskLevel)
         << L",\"steps\":[{\"draft_step_id\":" << simplejson::Quote(spec.workflowId + L"-draft-step-0")
         << L",\"proposed_action\":" << simplejson::Quote(runtimeAction)
         << L",\"target_description\":" << simplejson::Quote(spec.recipient + L" | " + spec.subject)
         << L",\"input_text\":" << simplejson::Quote(spec.body)
         << L",\"verification_hint\":\"verify communication object was locally created and not sent\""
         << L",\"risk_hint\":" << simplejson::Quote(spec.riskLevel)
         << L"}]}";
    return json.str();
}

std::wstring StepJson(const CommunicationWorkflowSpec& spec, int index) {
    std::wstring runtimeAction = CommunicationWorkflowRuntimeActionForType(spec.type);
    std::wstring contractId = L"communication-contract-" + spec.workflowId;
    std::wstring stepId = spec.workflowId + L"-step-" + std::to_wstring(index);
    std::wstringstream step;
    step << L"{\"contract_id\":" << simplejson::Quote(contractId)
         << L",\"task_id\":" << simplejson::Quote(spec.taskId)
         << L",\"plan_id\":" << simplejson::Quote(L"communication-plan-" + spec.workflowId)
         << L",\"step_id\":" << simplejson::Quote(stepId)
         << L",\"step_index\":" << index
         << L",\"step_type\":" << simplejson::Quote(CommunicationWorkflowStepTypeForType(spec.type))
         << L",\"runtime_action\":" << simplejson::Quote(runtimeAction)
         << L",\"target\":" << simplejson::Quote(L"recipient:" + spec.recipient + L";subject:" + spec.subject)
         << L",\"input_text\":" << simplejson::Quote(spec.body)
         << L",\"executable\":true"
         << L",\"expected_context\":" << CompleteExpectedContextJson(spec)
         << L",\"action_precondition\":" << CompleteActionPreconditionJson()
         << L",\"verification_hint\":" << CompleteVerificationHintJson(spec)
         << L",\"risk_level\":" << simplejson::Quote(spec.riskLevel)
         << L",\"confirmation_policy\":" << spec.confirmationPolicyJson
         << L",\"recovery_policy\":" << spec.recoveryPolicyJson
         << L",\"stop_policy\":" << CompleteStopPolicyJson(spec.stopPolicyJson)
         << L",\"session_policy\":" << spec.sessionPolicyJson
         << L",\"evidence_policy\":" << spec.evidencePolicyJson
         << L",\"workflow_id\":" << simplejson::Quote(spec.workflowId)
         << L",\"workflow_type\":\"communication\""
         << L",\"communication_type\":" << simplejson::Quote(spec.type)
         << L",\"recipient\":" << simplejson::Quote(spec.recipient)
         << L",\"subject\":" << simplejson::Quote(spec.subject)
         << L",\"body\":" << simplejson::Quote(spec.body)
         << L",\"context_source\":" << simplejson::Quote(spec.contextSource)
         << L",\"requested_action_backend\":\"runtime_session_local_create\""
         << L",\"send_allowed\":false"
         << L",\"external_api_allowed\":false"
         << L",\"created_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"compiler_version\":\"6.9.0.communication_workflow\"}";
    return step.str();
}

}  // namespace

CommunicationWorkflowCompileResult CompileCommunicationWorkflowSpec(const CommunicationWorkflowSpec& spec) {
    if (!CommunicationWorkflowTypeSupported(spec.type)) {
        return CompileFailure(L"COMMUNICATION_TYPE_UNSUPPORTED", L"Unsupported CommunicationWorkflow type.");
    }

    std::wstring taskIntent = TaskIntentJson(spec);
    std::wstring planDraft = AgentPlanDraftJson(spec);
    std::wstring step = StepJson(spec, 0);

    std::wstringstream contractJson;
    contractJson << L"{\"schema_version\":\"6.3.0.step_contract\""
                 << L",\"compiler_version\":\"6.9.0.communication_workflow\""
                 << L",\"compile_ok\":true"
                 << L",\"runtime_executed\":false"
                 << L",\"task_intent_used\":true"
                 << L",\"agent_plan_draft_used\":true"
                 << L",\"step_contract_validator_used\":true"
                 << L",\"task_id\":" << simplejson::Quote(spec.taskId)
                 << L",\"plan_id\":" << simplejson::Quote(L"communication-plan-" + spec.workflowId)
                 << L",\"workflow_id\":" << simplejson::Quote(spec.workflowId)
                 << L",\"workflow_type\":\"communication\""
                 << L",\"type\":" << simplejson::Quote(spec.type)
                 << L",\"task_intent\":" << taskIntent
                 << L",\"agent_plan_draft\":" << planDraft
                 << L",\"contracts\":[" << step << L"]}";

    StepContractV63ValidationResult validation = ValidateStepContractV63Json(contractJson.str());
    if (!validation.validationOk) {
        return CompileFailure(validation.errorCode.empty() ? L"STEP_CONTRACT_VALIDATION_FAILED" : validation.errorCode,
            validation.errorMessage.empty() ? L"Communication StepContract validation failed." : validation.errorMessage,
            validation.resultJson);
    }

    CommunicationWorkflowCompileResult result;
    result.ok = true;
    result.workflowId = spec.workflowId;
    result.type = spec.type;
    result.taskIntentJson = taskIntent;
    result.agentPlanDraftJson = planDraft;
    result.contractJson = contractJson.str();
    result.diagnosticsJson = L"{\"schema_version\":\"6.9.0.communication_workflow.compile_diagnostics\""
        L",\"compile_ok\":true"
        L",\"workflow_id\":" + simplejson::Quote(spec.workflowId) +
        L",\"type\":" + simplejson::Quote(spec.type) +
        L",\"task_intent_used\":true"
        L",\"agent_plan_draft_used\":true"
        L",\"step_contract_validator_used\":true"
        L",\"emitted_step_count\":1"
        L",\"runtime_executed\":false}";
    return result;
}

CommunicationWorkflowCompileResult CompileCommunicationWorkflowSpecJson(const std::wstring& json) {
    CommunicationWorkflowSchemaResult schema = ParseCommunicationWorkflowSpecJson(json);
    if (!schema.ok) {
        return CompileFailure(schema.errorCode, schema.errorMessage, schema.diagnosticsJson);
    }
    return CompileCommunicationWorkflowSpec(schema.spec);
}

CommunicationWorkflowCompileResult CompileCommunicationWorkflowSpecFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath) {
    CommunicationWorkflowSchemaResult schema = ParseCommunicationWorkflowSpecFile(inputPath);
    if (!schema.ok) {
        return CompileFailure(schema.errorCode, schema.errorMessage, schema.diagnosticsJson);
    }
    CommunicationWorkflowCompileResult result = CompileCommunicationWorkflowSpec(schema.spec);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.contractJson, writeError);
    }
    return result;
}

int CommandCompileCommunicationWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"compile-communication-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"compile-communication-workflow requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    CommunicationWorkflowCompileResult result = CompileCommunicationWorkflowSpecFile(input, output);
    std::wstring data = L"{\"compile_ok\":" + simplejson::Bool(result.ok)
        + L",\"input\":" + simplejson::Quote(input)
        + L",\"output\":" + simplejson::Quote(output)
        + L",\"workflow_id\":" + simplejson::Quote(result.workflowId)
        + L",\"type\":" + simplejson::Quote(result.type)
        + L",\"task_intent_used\":true"
        L",\"agent_plan_draft_used\":true"
        L",\"step_contract_validator_used\":true"
        L",\"runtime_executed\":false}";
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMMUNICATION_COMPILE_FAILED" : result.errorCode, result.errorMessage, result.diagnosticsJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}
