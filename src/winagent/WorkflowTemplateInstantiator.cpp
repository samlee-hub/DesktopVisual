#include "WorkflowTemplateInstantiator.h"

#include "EvidenceFingerprint.h"
#include "SimpleJson.h"
#include "StepContractValidator.h"
#include "Trace.h"

#include <algorithm>
#include <iostream>
#include <sstream>

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

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

WorkflowTemplateInstantiationResult Fail(const std::wstring& code, const std::wstring& message, const std::wstring& outputPath) {
    WorkflowTemplateInstantiationResult result;
    result.errorCode = code;
    result.errorMessage = message;
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.workflow_template_instantiation\""
         << L",\"status\":\"BLOCKED\""
         << L",\"error_code\":" << simplejson::Quote(code)
         << L",\"error_message\":" << simplejson::Quote(message)
         << L",\"step_contract_validator_used\":false"
         << L",\"runtime_executed\":false"
         << L",\"step_level_verification_skipped\":false"
         << L"}";
    result.evidenceJson = json.str();
    if (!outputPath.empty()) {
        std::wstring error;
        WriteValidationTextFile(outputPath, result.evidenceJson, error);
    }
    return result;
}

std::wstring ReplaceAll(std::wstring value, const std::wstring& needle, const std::wstring& replacement) {
    size_t pos = 0;
    while ((pos = value.find(needle, pos)) != std::wstring::npos) {
        value.replace(pos, needle.size(), replacement);
        pos += replacement.size();
    }
    return value;
}

std::wstring SubstituteParams(std::wstring value, const simplejson::Value& params) {
    if (!params.IsObject()) return value;
    for (const auto& entry : params.objectValue) {
        if (entry.second.IsString()) {
            value = ReplaceAll(value, L"{{" + entry.first + L"}}", entry.second.stringValue);
        }
    }
    return value;
}

const simplejson::Value* ParameterObject(const simplejson::Value& root) {
    if (!root.IsObject()) return nullptr;
    const simplejson::Value* nested = simplejson::Find(root, L"parameter_values");
    if (nested && nested->IsObject()) return nested;
    return &root;
}

bool ParameterValueString(const simplejson::Value& params, const std::wstring& key, std::wstring& value) {
    const simplejson::Value* found = simplejson::Find(params, key);
    if (!found || !found->IsString()) return false;
    value = found->stringValue;
    return true;
}

bool ParameterTypeOk(const simplejson::Value& schema, const simplejson::Value& params, const std::wstring& key, std::wstring& expectedType) {
    const simplejson::Value* expected = simplejson::Find(schema, key);
    expectedType = expected && expected->IsString() ? expected->stringValue : L"string";
    const simplejson::Value* actual = simplejson::Find(params, key);
    if (!actual) return false;
    if (Lower(expectedType) == L"string") return actual->IsString();
    if (Lower(expectedType) == L"boolean" || Lower(expectedType) == L"bool") return actual->IsBool();
    if (Lower(expectedType) == L"number" || Lower(expectedType) == L"integer" || Lower(expectedType) == L"int") return actual->IsNumber();
    return actual->IsString();
}

std::wstring SkeletonString(const WorkflowTemplateRecord& record, const std::wstring& key, const std::wstring& fallback) {
    simplejson::ParseResult parsed = simplejson::Parse(record.stepContractSkeletonJson);
    if (!parsed.ok || !parsed.root.IsObject()) return fallback;
    return simplejson::GetString(parsed.root, key, fallback);
}

std::wstring DefaultStopPolicyJson() {
    return L"{\"stop_on_active_protection\":true,\"stop_on_credential_required\":true,\"stop_on_unverified_result\":true,\"stop_on_runtime_guard_failure\":true}";
}

std::wstring DefaultSessionPolicyJson() {
    return L"{\"session_required\":true,\"session_reuse_allowed\":true,\"cache_policy\":\"isolated_step\"}";
}

std::wstring DefaultEvidencePolicyJson() {
    return L"{\"raw_evidence_required\":true,\"verifier_required\":true,\"gate_required\":true}";
}

std::wstring BuildExpectedContextJson(const WorkflowTemplateRecord& record, const simplejson::Value& params) {
    std::wstring title = SubstituteParams(SkeletonString(record, L"target", L"{{target_path}}"), params);
    std::wstring process = Lower(record.workflowType) == L"browser_form" ? L"browser" :
        (Lower(record.workflowType) == L"communication" ? L"local_mail_mock" : L"explorer");
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << simplejson::Quote(process)
         << L",\"expected_title_pattern\":" << simplejson::Quote(title.empty() ? L"*" : title)
         << L",\"required_markers\":[]"
         << L",\"wrong_page_patterns\":[]"
         << L",\"active_protection_patterns\":[]"
         << L",\"credential_required_patterns\":[]"
         << L",\"foreground_required\":true"
         << L",\"window_binding_required\":true"
         << L"}";
    return json.str();
}

std::wstring BuildActionPreconditionJson(const WorkflowTemplateRecord& record) {
    if (Lower(record.workflowType) == L"browser_form") {
        return L"{\"stale_target_reject_required\":true,\"focus_required\":true,\"mouse_first_required\":true,\"target_unique_required\":true}";
    }
    if (Lower(record.workflowType) == L"communication") {
        return L"{\"stale_target_reject_required\":true,\"external_api_disallowed\":true,\"send_disallowed\":true}";
    }
    return L"{\"stale_target_reject_required\":true}";
}

std::wstring BuildVerificationHintJson(const WorkflowTemplateRecord& record) {
    simplejson::ParseResult parsed = simplejson::Parse(record.verificationHintSchemaJson);
    std::wstring verifyType = L"mock_safe_verification";
    bool reobserve = true;
    if (parsed.ok && parsed.root.IsObject()) {
        verifyType = simplejson::GetString(parsed.root, L"verify_type", verifyType);
        reobserve = simplejson::GetBool(parsed.root, L"post_action_reobserve_required", true);
    }
    std::wstringstream json;
    json << L"{\"verify_type\":" << simplejson::Quote(verifyType)
         << L",\"post_action_reobserve_required\":" << simplejson::Bool(reobserve)
         << L"}";
    return json.str();
}

std::wstring BuildStepContractJson(const WorkflowTemplateRecord& record, const simplejson::Value& params, const std::wstring& evidenceRef) {
    std::wstring runtimeAction = SkeletonString(record, L"runtime_action", L"explorer_open_path");
    std::wstring target = SubstituteParams(SkeletonString(record, L"target", L"{{target_path}}"), params);
    if (target.empty()) target = L"template-target";
    std::wstring risk = SkeletonString(record, L"risk_level", record.riskLevel.empty() ? L"LOW_RISK" : record.riskLevel);
    std::wstring allowedRoot;
    ParameterValueString(params, L"allowed_root", allowedRoot);
    if (allowedRoot.empty()) allowedRoot = L"D:\\desktopvisual";
    std::wstring allowedUrlPrefix = L"http://localhost/";
    ParameterValueString(params, L"allowed_url_prefix", allowedUrlPrefix);

    std::wstringstream step;
    step << L"{\"contract_id\":" << simplejson::Quote(record.templateId + L"-contract")
         << L",\"task_id\":" << simplejson::Quote(record.templateId + L"-task")
         << L",\"plan_id\":" << simplejson::Quote(record.templateId + L"-plan")
         << L",\"step_id\":\"step-0\""
         << L",\"step_index\":0"
         << L",\"step_type\":\"workflow_template_instance\""
         << L",\"runtime_action\":" << simplejson::Quote(runtimeAction)
         << L",\"target\":" << simplejson::Quote(target)
         << L",\"created_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"compiler_version\":\"6.11.0\""
         << L",\"risk_level\":" << simplejson::Quote(risk)
         << L",\"executable\":true"
         << L",\"allowed_root\":" << simplejson::Quote(allowedRoot)
         << L",\"allowed_url_prefix\":" << simplejson::Quote(allowedUrlPrefix)
         << L",\"requested_action_backend\":\"runtime_session_step_contract\""
         << L",\"coordinate_source_type\":\"semantic_locator\""
         << L",\"send_allowed\":false"
         << L",\"external_api_allowed\":false"
         << L",\"action_precondition\":" << BuildActionPreconditionJson(record)
         << L",\"expected_context\":" << BuildExpectedContextJson(record, params)
         << L",\"verification_hint\":" << BuildVerificationHintJson(record)
         << L",\"confirmation_policy\":" << (record.confirmationPolicyJson.empty() ? L"{\"confirmation_required\":false}" : record.confirmationPolicyJson)
         << L",\"recovery_policy\":" << (record.recoveryPolicyJson.empty() ? L"{\"recovery_scope\":\"none\"}" : record.recoveryPolicyJson)
         << L",\"stop_policy\":" << (record.stopPolicyJson.empty() ? DefaultStopPolicyJson() : record.stopPolicyJson)
         << L",\"session_policy\":" << DefaultSessionPolicyJson()
         << L",\"evidence_policy\":" << DefaultEvidencePolicyJson()
         << L",\"template_id\":" << simplejson::Quote(record.templateId)
         << L",\"template_hash\":" << simplejson::Quote(record.templateHash)
         << L",\"source_evidence_refs\":" << WorkflowTemplateStringArrayJson(record.sourceEvidenceRefs)
         << L"}";

    std::wstringstream json;
    json << L"{\"schema_version\":\"6.3.0.step_contract\""
         << L",\"runtime_version\":\"6.11.0\""
         << L",\"template_id\":" << simplejson::Quote(record.templateId)
         << L",\"template_hash\":" << simplejson::Quote(record.templateHash)
         << L",\"source_evidence_refs\":" << WorkflowTemplateStringArrayJson(record.sourceEvidenceRefs)
         << L",\"instantiation_evidence_ref\":" << simplejson::Quote(evidenceRef)
         << L",\"step_contract_validator_used\":true"
         << L",\"runtime_context_guard_bypassed\":false"
         << L",\"step_level_verification_skipped\":false"
         << L",\"contracts\":[" << step.str() << L"]"
         << L"}";
    return json.str();
}

}  // namespace

WorkflowTemplateInstantiationResult InstantiateWorkflowTemplate(
    const WorkflowTemplateRecord& record,
    const simplejson::Value& parameterValues,
    const std::wstring& outputPath,
    const std::wstring& evidenceOutputPath) {
    if (Lower(record.templateStatus) != L"validated" || Lower(record.validationStatus) != L"pass") {
        return Fail(L"BLOCK_TEMPLATE_NOT_VALIDATED", L"Only validated templates can be instantiated.", outputPath);
    }
    const simplejson::Value* params = ParameterObject(parameterValues);
    if (!params || !params->IsObject()) {
        return Fail(L"FAIL_TEMPLATE_INPUT_INVALID", L"parameter_values must be a JSON object.", outputPath);
    }
    simplejson::ParseResult schema = simplejson::Parse(record.parameterSchemaJson);
    if (!schema.ok || !schema.root.IsObject()) {
        return Fail(L"FAIL_TEMPLATE_INPUT_INVALID", L"parameter_schema is invalid.", outputPath);
    }
    for (const auto& key : record.requiredInputs) {
        const simplejson::Value* found = simplejson::Find(*params, key);
        if (!found) return Fail(L"FAIL_TEMPLATE_INPUT_MISSING", L"Missing required template input: " + key, outputPath);
        std::wstring expectedType;
        if (!ParameterTypeOk(schema.root, *params, key, expectedType)) {
            return Fail(L"FAIL_TEMPLATE_INPUT_INVALID", L"Invalid template input type for: " + key, outputPath);
        }
    }

    std::wstring evidenceRef = evidenceOutputPath.empty() ? outputPath : evidenceOutputPath;
    WorkflowTemplateInstantiationResult result;
    result.stepContractJson = BuildStepContractJson(record, *params, evidenceRef);
    result.stepContractValidatorUsed = true;
    StepContractV63ValidationResult validation = ValidateStepContractV63Json(result.stepContractJson);
    result.stepContractValid = validation.validationOk;
    std::wstringstream evidence;
    evidence << L"{\"schema_version\":\"6.11.0.workflow_template_instantiation\""
             << L",\"status\":" << simplejson::Quote(validation.validationOk ? L"PASS" : L"FAIL")
             << L",\"template_id\":" << simplejson::Quote(record.templateId)
             << L",\"template_hash\":" << simplejson::Quote(record.templateHash)
             << L",\"source_evidence_refs\":" << WorkflowTemplateStringArrayJson(record.sourceEvidenceRefs)
             << L",\"step_contract_validator_used\":true"
             << L",\"step_contract_valid\":" << simplejson::Bool(validation.validationOk)
             << L",\"runtime_context_guard_bypassed\":false"
             << L",\"step_level_verification_skipped\":false"
             << L",\"runtime_executed\":false"
             << L",\"validation_result\":" << validation.resultJson
             << L"}";
    result.evidenceJson = evidence.str();
    if (!outputPath.empty()) {
        std::wstring error;
        WriteValidationTextFile(outputPath, result.stepContractJson, error);
    }
    if (!evidenceOutputPath.empty()) {
        std::wstring error;
        WriteValidationTextFile(evidenceOutputPath, result.evidenceJson, error);
    }
    if (!validation.validationOk) {
        result.errorCode = validation.errorCode.empty() ? L"STEP_CONTRACT_VALIDATION_FAILED" : validation.errorCode;
        result.errorMessage = validation.errorMessage;
        return result;
    }
    result.ok = true;
    return result;
}

WorkflowTemplateInstantiationResult InstantiateWorkflowTemplateFromFiles(const WorkflowTemplateInstantiationInput& input) {
    std::wstring templateText;
    std::wstring error;
    if (!ReadValidationTextFile(input.templatePath, templateText, error)) {
        return Fail(L"FILE_NOT_FOUND", L"Could not read template file.", input.outputPath);
    }
    WorkflowTemplateRecordResult record = ParseWorkflowTemplateRecordJson(templateText);
    if (!record.ok) return Fail(record.errorCode, record.errorMessage, input.outputPath);

    std::wstring paramsText;
    if (!ReadValidationTextFile(input.parametersPath, paramsText, error)) {
        return Fail(L"FAIL_TEMPLATE_INPUT_MISSING", L"Could not read parameters file.", input.outputPath);
    }
    simplejson::ParseResult params = simplejson::Parse(paramsText);
    if (!params.ok) return Fail(L"FAIL_TEMPLATE_INPUT_INVALID", L"Invalid parameters JSON.", input.outputPath);
    return InstantiateWorkflowTemplate(record.record, params.root, input.outputPath, input.evidenceOutputPath);
}

int CommandWorkflowTemplateInstantiate(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-template-instantiate";
    ULONGLONG startTick = GetTickCount64();
    WorkflowTemplateInstantiationInput input;
    if (!ArgValue(argc, argv, L"--template", input.templatePath) || input.templatePath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-template-instantiate requires --template.", L"{}") << L"\n";
        return 2;
    }
    if (!ArgValue(argc, argv, L"--parameters", input.parametersPath) || input.parametersPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-template-instantiate requires --parameters.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", input.outputPath);
    ArgValue(argc, argv, L"--evidence-output", input.evidenceOutputPath);
    WorkflowTemplateInstantiationResult result = InstantiateWorkflowTemplateFromFiles(input);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"WORKFLOW_TEMPLATE_INSTANTIATION_FAILED" : result.errorCode, result.errorMessage, result.evidenceJson.empty() ? L"{}" : result.evidenceJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.evidenceJson) << L"\n";
    return 0;
}

