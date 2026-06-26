#include "WorkflowTemplateValidator.h"

#include "EvidenceFingerprint.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "WorkflowTemplateRegistry.h"
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

void AddViolation(std::vector<std::wstring>& violations, const std::wstring& code) {
    if (std::find(violations.begin(), violations.end(), code) == violations.end()) {
        violations.push_back(code);
    }
}

bool JsonObjectHasKeys(const std::wstring& json, const std::vector<std::wstring>& keys) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) return false;
    for (const auto& key : keys) {
        if (!simplejson::Has(parsed.root, key)) return false;
    }
    return true;
}

bool JsonObjectNonEmpty(const std::wstring& json) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    return parsed.ok && parsed.root.IsObject() && !parsed.root.objectValue.empty();
}

std::wstring ViolationsJson(const std::vector<std::wstring>& violations) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < violations.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(violations[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring FirstReason(const std::vector<std::wstring>& violations) {
    if (violations.empty()) return L"";
    return violations.front();
}

std::wstring ReportJson(const WorkflowTemplateRecord& record, const std::vector<std::wstring>& violations) {
    bool ok = violations.empty();
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.workflow_template_validation\""
         << L",\"validation_status\":" << simplejson::Quote(ok ? L"pass" : L"fail")
         << L",\"template_status\":" << simplejson::Quote(ok ? L"validated" : L"rejected")
         << L",\"template_id\":" << simplejson::Quote(record.templateId)
         << L",\"template_hash\":" << simplejson::Quote(record.templateHash)
         << L",\"violations\":" << ViolationsJson(violations)
         << L",\"source_evidence_refs_preserved\":" << simplejson::Bool(!record.sourceEvidenceRefs.empty())
         << L",\"step_contract_validator_required\":true"
         << L",\"runtime_session_required\":true"
         << L",\"verifier_required\":true"
         << L",\"direct_execution_allowed\":false"
         << L"}";
    return json.str();
}

}  // namespace

WorkflowTemplateRecord PromoteWorkflowTemplateToValidated(WorkflowTemplateRecord record, const std::wstring& validationReportRef) {
    record.templateStatus = L"validated";
    record.validationStatus = L"pass";
    record.validationReportRef = WorkflowTemplateResolveRef(validationReportRef);
    return FinalizeWorkflowTemplateRecord(record);
}

WorkflowTemplateRecord RejectWorkflowTemplate(WorkflowTemplateRecord record, const std::wstring& reasonCode, const std::wstring& validationReportRef) {
    record.templateStatus = L"rejected";
    record.validationStatus = reasonCode.empty() ? L"fail" : reasonCode;
    record.validationReportRef = WorkflowTemplateResolveRef(validationReportRef);
    return FinalizeWorkflowTemplateRecord(record);
}

WorkflowTemplateRecord DeprecateWorkflowTemplate(WorkflowTemplateRecord record, const std::wstring& validationReportRef) {
    record.templateStatus = L"deprecated";
    record.validationStatus = L"deprecated";
    record.validationReportRef = WorkflowTemplateResolveRef(validationReportRef);
    return FinalizeWorkflowTemplateRecord(record);
}

WorkflowTemplateValidationResult ValidateWorkflowTemplateRecord(const WorkflowTemplateRecord& record) {
    std::vector<std::wstring> violations;
    if (record.sourceEvidenceRefs.empty()) AddViolation(violations, L"FAIL_TEMPLATE_SOURCE_MISSING");
    for (const auto& source : record.sourceEvidenceRefs) {
        if (!WorkflowTemplateSourceTrusted(source)) AddViolation(violations, L"FAIL_UNTRUSTED_TEMPLATE_SOURCE");
    }
    if (!IsSupportedWorkflowTemplateStatus(record.templateStatus)) AddViolation(violations, L"FAIL_TEMPLATE_STATUS_INVALID");
    if (Lower(record.templateStatus) != L"candidate" && Lower(record.templateStatus) != L"validated") {
        AddViolation(violations, L"BLOCK_TEMPLATE_NOT_VALIDATED");
    }
    if (record.requiredInputs.empty()) AddViolation(violations, L"FAIL_TEMPLATE_REQUIRED_INPUTS_MISSING");
    if (!JsonObjectNonEmpty(record.parameterSchemaJson)) AddViolation(violations, L"FAIL_TEMPLATE_PARAMETER_SCHEMA_INCOMPLETE");
    if (!JsonObjectNonEmpty(record.expectedContextSchemaJson)) AddViolation(violations, L"FAIL_TEMPLATE_EXPECTED_CONTEXT_SCHEMA_MISSING");
    if (!JsonObjectNonEmpty(record.verificationHintSchemaJson)) AddViolation(violations, L"FAIL_TEMPLATE_VERIFICATION_HINT_SCHEMA_MISSING");
    if (!JsonObjectNonEmpty(record.safetyConstraintsJson)) AddViolation(violations, L"FAIL_TEMPLATE_SAFETY_CONSTRAINTS_MISSING");
    if (!JsonObjectHasKeys(record.safetyConstraintsJson, {
        L"no_direct_execution",
        L"step_contract_validator_required",
        L"runtime_session_required",
        L"verifier_required"
    })) {
        AddViolation(violations, L"FAIL_TEMPLATE_SAFETY_CONSTRAINTS_MISSING");
    }

    WorkflowTemplateSafetyResult safety = CheckWorkflowTemplateSafety(record);
    for (const auto& violation : safety.violations) AddViolation(violations, violation);

    WorkflowTemplateValidationResult result;
    result.ok = violations.empty();
    result.validationStatus = result.ok ? L"pass" : L"fail";
    result.reasonCode = FirstReason(violations);
    result.reasonMessage = result.ok ? L"" : L"Workflow template validation failed.";
    result.violations = violations;
    result.record = result.ok ? PromoteWorkflowTemplateToValidated(record, record.validationReportRef) : RejectWorkflowTemplate(record, result.reasonCode, record.validationReportRef);
    result.reportJson = ReportJson(record, violations);
    return result;
}

WorkflowTemplateValidationResult ValidateWorkflowTemplateJson(const std::wstring& json) {
    WorkflowTemplateRecordResult parsed = ParseWorkflowTemplateRecordJson(json);
    if (!parsed.ok) {
        WorkflowTemplateValidationResult result;
        result.reasonCode = parsed.errorCode;
        result.reasonMessage = parsed.errorMessage;
        result.violations.push_back(parsed.errorCode);
        result.reportJson = L"{\"schema_version\":\"6.11.0.workflow_template_validation\",\"validation_status\":\"fail\",\"violations\":" +
            WorkflowTemplateStringArrayJson(result.violations) + L"}";
        return result;
    }
    return ValidateWorkflowTemplateRecord(parsed.record);
}

WorkflowTemplateValidationResult ValidateWorkflowTemplateFile(const std::wstring& inputPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(inputPath, text, error)) {
        WorkflowTemplateValidationResult result;
        result.reasonCode = L"FILE_NOT_FOUND";
        result.reasonMessage = error;
        result.violations.push_back(L"FILE_NOT_FOUND");
        result.reportJson = L"{\"schema_version\":\"6.11.0.workflow_template_validation\",\"validation_status\":\"fail\",\"violations\":[\"FILE_NOT_FOUND\"]}";
        return result;
    }
    return ValidateWorkflowTemplateJson(text);
}

int CommandWorkflowTemplateValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-template-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    std::wstring report;
    std::wstring registryRoot;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-template-validate requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    ArgValue(argc, argv, L"--report", report);
    ArgValue(argc, argv, L"--registry-root", registryRoot);
    WorkflowTemplateValidationResult result = ValidateWorkflowTemplateFile(input);
    if (!report.empty()) {
        std::wstring error;
        WriteValidationTextFile(report, result.reportJson, error);
        result.record.validationReportRef = WorkflowTemplateResolveRef(report);
        result.record = result.ok ? PromoteWorkflowTemplateToValidated(result.record, report) : RejectWorkflowTemplate(result.record, result.reasonCode, report);
    }
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, WorkflowTemplateRecordToJson(result.record), error);
    }
    UpdateWorkflowTemplateRecord(registryRoot, result.record, result.ok ? L"promote_template_to_validated" : L"reject_template");
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.reasonCode.empty() ? L"WORKFLOW_TEMPLATE_VALIDATION_FAILED" : result.reasonCode, result.reasonMessage, result.reportJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.reportJson) << L"\n";
    return 0;
}

