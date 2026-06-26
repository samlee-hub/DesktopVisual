#include "WorkflowTemplateCandidateExtractor.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "Trace.h"
#include "WorkflowTemplateSafetyBoundary.h"

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

bool ContainsNoCase(const std::wstring& value, const std::wstring& needle) {
    return !needle.empty() && Lower(value).find(Lower(needle)) != std::wstring::npos;
}

WorkflowTemplateCandidateExtractionResult Fail(const std::wstring& code, const std::wstring& message) {
    WorkflowTemplateCandidateExtractionResult result;
    result.errorCode = code;
    result.errorMessage = message;
    result.reportJson = L"{\"schema_version\":\"6.11.0.workflow_template_candidate_extraction\",\"status\":\"FAIL\",\"error_code\":" +
        simplejson::Quote(code) + L",\"error_message\":" + simplejson::Quote(message) +
        L",\"candidate_generated\":false,\"runtime_executed\":false}";
    return result;
}

bool AllowedSourcePath(const std::wstring& path) {
    std::wstring slash = path;
    std::replace(slash.begin(), slash.end(), L'\\', L'/');
    std::wstring lower = Lower(slash);
    return lower.find(L"artifacts/dev6.7.0_explorer_agent_workflows_rerun") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.7.0_explorer_agent_workflows") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.8.0_browser_and_web_form_agent_workflows") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.9.0_communication_workflow") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.10.0_experience_memory_failure_attribution") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.9.0_system_stabilization") != std::wstring::npos;
}

std::wstring InferWorkflowType(const std::wstring& sourcePath, const std::wstring& provided) {
    if (!provided.empty()) return provided;
    if (ContainsNoCase(sourcePath, L"dev6.7.0_explorer")) return L"explorer";
    if (ContainsNoCase(sourcePath, L"dev6.8.0_browser")) return L"browser_form";
    if (ContainsNoCase(sourcePath, L"dev6.9.0_communication")) return L"communication";
    if (ContainsNoCase(sourcePath, L"experience_memory")) return L"compiled_plan_execution";
    if (ContainsNoCase(sourcePath, L"system_stabilization")) return L"compiled_plan_execution";
    return L"explorer";
}

std::wstring SkeletonForType(const std::wstring& workflowType) {
    if (Lower(workflowType) == L"browser_form") {
        return L"{\"runtime_action\":\"browser_fill_form\",\"target\":\"{{field_marker}}\",\"risk_level\":\"LOW_RISK\",\"requested_action_backend\":\"runtime_session_step_contract\"}";
    }
    if (Lower(workflowType) == L"communication") {
        return L"{\"runtime_action\":\"communication_create_draft\",\"target\":\"{{redacted_recipient_ref}}\",\"risk_level\":\"REVERSIBLE_DRAFT\",\"send_allowed\":false,\"external_api_allowed\":false}";
    }
    if (Lower(workflowType) == L"vlm_observation") {
        return L"{\"runtime_action\":\"observe\",\"target\":\"{{observation_scope}}\",\"risk_level\":\"READ_ONLY\"}";
    }
    if (Lower(workflowType) == L"vlm_candidate") {
        return L"{\"runtime_action\":\"locate\",\"target\":\"{{candidate_description}}\",\"risk_level\":\"READ_ONLY\"}";
    }
    if (Lower(workflowType) == L"compiled_plan_execution") {
        return L"{\"runtime_action\":\"verify_marker\",\"target\":\"{{compiled_plan_marker}}\",\"risk_level\":\"READ_ONLY\"}";
    }
    return L"{\"runtime_action\":\"explorer_open_path\",\"target\":\"{{target_path}}\",\"risk_level\":\"LOW_RISK\"}";
}

std::vector<std::wstring> RequiredInputsForType(const std::wstring& workflowType) {
    if (Lower(workflowType) == L"browser_form") return {L"field_marker", L"allowed_url_prefix"};
    if (Lower(workflowType) == L"communication") return {L"redacted_recipient_ref", L"body_redacted_ref"};
    if (Lower(workflowType) == L"vlm_observation") return {L"observation_scope"};
    if (Lower(workflowType) == L"vlm_candidate") return {L"candidate_description"};
    if (Lower(workflowType) == L"compiled_plan_execution") return {L"compiled_plan_marker"};
    return {L"target_path"};
}

std::wstring ParameterSchemaForType(const std::wstring& workflowType) {
    if (Lower(workflowType) == L"browser_form") return L"{\"field_marker\":\"string\",\"allowed_url_prefix\":\"string\"}";
    if (Lower(workflowType) == L"communication") return L"{\"redacted_recipient_ref\":\"string\",\"body_redacted_ref\":\"string\"}";
    if (Lower(workflowType) == L"vlm_observation") return L"{\"observation_scope\":\"string\"}";
    if (Lower(workflowType) == L"vlm_candidate") return L"{\"candidate_description\":\"string\"}";
    if (Lower(workflowType) == L"compiled_plan_execution") return L"{\"compiled_plan_marker\":\"string\"}";
    return L"{\"target_path\":\"string\",\"allowed_root\":\"string\"}";
}

WorkflowTemplateRecord BuildCandidate(const std::wstring& sourcePath, const std::wstring& workflowType, const std::wstring& templateName) {
    WorkflowTemplateRecord record;
    record.templateName = templateName.empty() ? L"Evidence-derived " + workflowType + L" workflow structure" : templateName;
    record.templateVersion = L"1.0.0";
    record.workflowType = workflowType;
    record.templateStatus = L"candidate";
    record.sourceEvidenceRefs = { sourcePath };
    record.requiredInputs = RequiredInputsForType(workflowType);
    record.optionalInputs = Lower(workflowType) == L"explorer" ? std::vector<std::wstring>{L"allowed_root"} : std::vector<std::wstring>{};
    record.parameterSchemaJson = ParameterSchemaForType(workflowType);
    record.stepContractSkeletonJson = SkeletonForType(workflowType);
    record.expectedContextSchemaJson = L"{\"expected_process_pattern\":\"string\",\"expected_title_pattern\":\"string\",\"required_markers\":\"array\"}";
    record.verificationHintSchemaJson = L"{\"verify_type\":\"mock_safe_verification\",\"post_action_reobserve_required\":true}";
    record.riskLevel = Lower(workflowType) == L"communication" ? L"REVERSIBLE_DRAFT" : L"LOW_RISK";
    record.confirmationPolicyJson = L"{\"confirmation_required\":false}";
    record.stopPolicyJson = L"{\"stop_on_active_protection\":true,\"stop_on_credential_required\":true,\"stop_on_unverified_result\":true,\"stop_on_runtime_guard_failure\":true}";
    record.recoveryPolicyJson = L"{\"recovery_scope\":\"none\"}";
    record.safetyConstraintsJson = L"{\"no_direct_execution\":true,\"direct_execution_allowed\":false,\"step_contract_validator_required\":true,\"runtime_session_required\":true,\"verifier_required\":true,\"memory_execution_influence\":false}";
    record.createdFromVersion = L"6.11.0";
    record.trustedVersion = L"6.10.0";
    record.validationStatus = L"not_validated";
    record.redactionApplied = Lower(workflowType) == L"communication";
    return FinalizeWorkflowTemplateRecord(record);
}

}  // namespace

WorkflowTemplateCandidateExtractionResult ExtractWorkflowTemplateCandidate(
    const WorkflowTemplateCandidateExtractionOptions& options) {
    std::wstring source = WorkflowTemplateResolveRef(options.sourcePath);
    if (source.empty()) return Fail(L"FAIL_TEMPLATE_SOURCE_MISSING", L"Template extraction source is required.");
    if (!AllowedSourcePath(source)) {
        return Fail(L"FAIL_UNTRUSTED_TEMPLATE_SOURCE", L"Template extraction source is outside the allowed v6.7-v6.10 evidence set.");
    }
    if (!WorkflowTemplateSourceTrusted(source)) {
        return Fail(L"FAIL_UNTRUSTED_TEMPLATE_SOURCE", L"Template extraction source is not accepted/pass evidence.");
    }
    std::wstring workflowType = InferWorkflowType(source, options.workflowType);
    if (!IsSupportedWorkflowTemplateWorkflowType(workflowType)) {
        return Fail(L"FAIL_TEMPLATE_WORKFLOW_TYPE_INVALID", L"workflow_type is unsupported.");
    }
    WorkflowTemplateRecord record = BuildCandidate(source, workflowType, options.templateName);
    WorkflowTemplateCandidateExtractionResult result;
    result.ok = true;
    result.record = record;
    result.candidateJson = WorkflowTemplateRecordToJson(record);
    result.reportJson = L"{\"schema_version\":\"6.11.0.workflow_template_candidate_extraction\""
        L",\"status\":\"PASS\""
        L",\"candidate_generated\":true"
        L",\"template_status\":\"candidate\""
        L",\"workflow_type\":" + simplejson::Quote(workflowType) +
        L",\"source_evidence_ref\":" + simplejson::Quote(source) +
        L",\"validated\":false"
        L",\"runtime_executed\":false"
        L",\"memory_execution_influence\":false}";
    return result;
}

int CommandWorkflowTemplateExtract(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-template-extract";
    ULONGLONG startTick = GetTickCount64();
    WorkflowTemplateCandidateExtractionOptions options;
    if (!ArgValue(argc, argv, L"--source", options.sourcePath) || options.sourcePath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-template-extract requires --source.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--workflow-type", options.workflowType);
    ArgValue(argc, argv, L"--template-name", options.templateName);
    ArgValue(argc, argv, L"--output", options.outputPath);
    WorkflowTemplateCandidateExtractionResult result = ExtractWorkflowTemplateCandidate(options);
    if (!options.outputPath.empty()) {
        std::wstring error;
        WriteValidationTextFile(options.outputPath, result.ok ? result.candidateJson : result.reportJson, error);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode, result.errorMessage, result.reportJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.reportJson) << L"\n";
    return 0;
}
