#include "WorkflowTemplateRecord.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool StartsWithNoCase(const std::wstring& value, const std::wstring& prefix) {
    return Lower(value).rfind(Lower(prefix), 0) == 0;
}

std::wstring JsonField(const simplejson::Value& object, const std::wstring& key, const std::wstring& fallback) {
    const simplejson::Value* value = simplejson::Find(object, key);
    if (!value || value->IsNull()) return fallback;
    return WorkflowTemplateValueToJson(*value);
}

std::wstring JsonFieldRequiredObject(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    if (!value) return L"null";
    return WorkflowTemplateValueToJson(*value);
}

std::vector<std::wstring> ResolvedStringArray(const simplejson::Value& object, const std::wstring& key, bool resolveRefs) {
    std::vector<std::wstring> values = simplejson::GetStringArray(object, key);
    if (resolveRefs) {
        for (std::wstring& value : values) value = WorkflowTemplateResolveRef(value);
    }
    return values;
}

WorkflowTemplateRecordResult Fail(const std::wstring& code, const std::wstring& message) {
    WorkflowTemplateRecordResult result;
    result.errorCode = code;
    result.errorMessage = message;
    return result;
}

std::wstring JoinCanonical(const std::vector<std::wstring>& values) {
    std::wstringstream out;
    for (const auto& value : values) {
        out << value << L"\n";
    }
    return out.str();
}

}  // namespace

bool IsSupportedWorkflowTemplateStatus(const std::wstring& status) {
    static const std::vector<std::wstring> values = {
        L"candidate",
        L"validated",
        L"rejected",
        L"deprecated"
    };
    for (const auto& value : values) {
        if (Lower(value) == Lower(status)) return true;
    }
    return false;
}

bool IsSupportedWorkflowTemplateWorkflowType(const std::wstring& workflowType) {
    static const std::vector<std::wstring> values = {
        L"explorer",
        L"browser_form",
        L"communication",
        L"vlm_observation",
        L"vlm_candidate",
        L"compiled_plan_execution"
    };
    for (const auto& value : values) {
        if (Lower(value) == Lower(workflowType)) return true;
    }
    return false;
}

bool WorkflowTemplateExecutable(const WorkflowTemplateRecord& record) {
    return Lower(record.templateStatus) == L"validated";
}

std::wstring DefaultWorkflowTemplateRegistryRoot() {
    return ArtifactsPath(L"workflow_templates");
}

std::wstring WorkflowTemplateResolveRef(const std::wstring& path) {
    if (path.empty()) return L"";
    std::wstring normalized = path;
    std::replace(normalized.begin(), normalized.end(), L'/', L'\\');
    if (normalized.size() >= 2 && normalized[1] == L':') {
        return ValidationNormalizePath(normalized);
    }
    if (StartsWithNoCase(normalized, L"artifacts\\") ||
        StartsWithNoCase(normalized, L"src\\") ||
        StartsWithNoCase(normalized, L"docs\\")) {
        return ProjectPath(normalized);
    }
    return ValidationNormalizePath(normalized);
}

std::wstring WorkflowTemplateValueToJson(const simplejson::Value& value) {
    if (value.IsNull()) return L"null";
    if (value.IsBool()) return simplejson::Bool(value.boolValue);
    if (value.IsNumber()) {
        double number = value.numberValue;
        long long asInteger = static_cast<long long>(number);
        std::wstringstream out;
        if (static_cast<double>(asInteger) == number) out << asInteger;
        else out << number;
        return out.str();
    }
    if (value.IsString()) return simplejson::Quote(value.stringValue);
    if (value.IsArray()) {
        std::wstringstream out;
        out << L"[";
        for (size_t i = 0; i < value.arrayValue.size(); ++i) {
            if (i) out << L",";
            out << WorkflowTemplateValueToJson(value.arrayValue[i]);
        }
        out << L"]";
        return out.str();
    }
    std::wstringstream out;
    out << L"{";
    bool first = true;
    for (const auto& entry : value.objectValue) {
        if (!first) out << L",";
        first = false;
        out << simplejson::Quote(entry.first) << L":" << WorkflowTemplateValueToJson(entry.second);
    }
    out << L"}";
    return out.str();
}

std::wstring WorkflowTemplateStringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring WorkflowTemplateHash(const WorkflowTemplateRecord& record) {
    std::wstringstream seed;
    seed << L"template_name=" << record.templateName << L"\n";
    seed << L"template_version=" << record.templateVersion << L"\n";
    seed << L"workflow_type=" << record.workflowType << L"\n";
    seed << L"source_evidence_refs=\n" << JoinCanonical(record.sourceEvidenceRefs);
    seed << L"source_memory_refs=\n" << JoinCanonical(record.sourceMemoryRefs);
    seed << L"required_inputs=\n" << JoinCanonical(record.requiredInputs);
    seed << L"optional_inputs=\n" << JoinCanonical(record.optionalInputs);
    seed << L"parameter_schema=" << record.parameterSchemaJson << L"\n";
    seed << L"step_contract_skeleton=" << record.stepContractSkeletonJson << L"\n";
    seed << L"expected_context_schema=" << record.expectedContextSchemaJson << L"\n";
    seed << L"verification_hint_schema=" << record.verificationHintSchemaJson << L"\n";
    seed << L"risk_level=" << record.riskLevel << L"\n";
    seed << L"confirmation_policy=" << record.confirmationPolicyJson << L"\n";
    seed << L"stop_policy=" << record.stopPolicyJson << L"\n";
    seed << L"recovery_policy=" << record.recoveryPolicyJson << L"\n";
    seed << L"safety_constraints=" << record.safetyConstraintsJson << L"\n";
    seed << L"created_from_version=" << record.createdFromVersion << L"\n";
    seed << L"trusted_version=" << record.trustedVersion << L"\n";
    seed << L"redaction_applied=" << (record.redactionApplied ? L"true" : L"false") << L"\n";
    return ValidationHashText(seed.str());
}

WorkflowTemplateRecord FinalizeWorkflowTemplateRecord(WorkflowTemplateRecord record) {
    if (record.templateStatus.empty()) record.templateStatus = L"candidate";
    if (record.templateVersion.empty()) record.templateVersion = L"1.0.0";
    if (record.createdFromVersion.empty()) record.createdFromVersion = L"6.11.0";
    if (record.trustedVersion.empty()) record.trustedVersion = L"6.10.0";
    if (record.validationStatus.empty()) {
        record.validationStatus = Lower(record.templateStatus) == L"validated" ? L"pass" : L"not_validated";
    }
    if (record.parameterSchemaJson.empty()) record.parameterSchemaJson = L"{}";
    if (record.stepContractSkeletonJson.empty()) record.stepContractSkeletonJson = L"{}";
    if (record.expectedContextSchemaJson.empty()) record.expectedContextSchemaJson = L"{}";
    if (record.verificationHintSchemaJson.empty()) record.verificationHintSchemaJson = L"{}";
    if (record.confirmationPolicyJson.empty()) record.confirmationPolicyJson = L"{}";
    if (record.stopPolicyJson.empty()) record.stopPolicyJson = L"{}";
    if (record.recoveryPolicyJson.empty()) record.recoveryPolicyJson = L"{}";
    if (record.safetyConstraintsJson.empty()) record.safetyConstraintsJson = L"{}";
    record.templateHash = WorkflowTemplateHash(record);
    if (record.templateId.empty()) {
        record.templateId = L"template-" + record.templateHash;
    }
    return record;
}

WorkflowTemplateRecordResult BuildWorkflowTemplateRecordFromJson(const simplejson::Value& input) {
    if (!input.IsObject()) {
        return Fail(L"FAIL_TEMPLATE_SCHEMA_INVALID", L"WorkflowTemplateRecord input must be a JSON object.");
    }
    WorkflowTemplateRecord record;
    record.templateId = simplejson::GetString(input, L"template_id");
    record.templateName = simplejson::GetString(input, L"template_name");
    record.templateVersion = simplejson::GetString(input, L"template_version", L"1.0.0");
    record.workflowType = simplejson::GetString(input, L"workflow_type");
    record.templateStatus = simplejson::GetString(input, L"template_status", L"candidate");
    record.sourceEvidenceRefs = ResolvedStringArray(input, L"source_evidence_refs", true);
    record.sourceMemoryRefs = ResolvedStringArray(input, L"source_memory_refs", true);
    record.requiredInputs = ResolvedStringArray(input, L"required_inputs", false);
    record.optionalInputs = ResolvedStringArray(input, L"optional_inputs", false);
    record.parameterSchemaJson = JsonFieldRequiredObject(input, L"parameter_schema");
    record.stepContractSkeletonJson = JsonFieldRequiredObject(input, L"step_contract_skeleton");
    record.expectedContextSchemaJson = JsonFieldRequiredObject(input, L"expected_context_schema");
    record.verificationHintSchemaJson = JsonFieldRequiredObject(input, L"verification_hint_schema");
    record.riskLevel = simplejson::GetString(input, L"risk_level", L"LOW_RISK");
    record.confirmationPolicyJson = JsonField(input, L"confirmation_policy", L"{}");
    record.stopPolicyJson = JsonField(input, L"stop_policy", L"{}");
    record.recoveryPolicyJson = JsonField(input, L"recovery_policy", L"{}");
    record.safetyConstraintsJson = JsonField(input, L"safety_constraints", L"{}");
    record.createdFromVersion = simplejson::GetString(input, L"created_from_version", L"6.11.0");
    record.trustedVersion = simplejson::GetString(input, L"trusted_version", L"6.10.0");
    record.validationStatus = simplejson::GetString(input, L"validation_status");
    record.validationReportRef = WorkflowTemplateResolveRef(simplejson::GetString(input, L"validation_report_ref"));
    record.redactionApplied = simplejson::GetBool(input, L"redaction_applied", false);

    if (record.templateName.empty()) return Fail(L"FAIL_TEMPLATE_NAME_MISSING", L"template_name is required.");
    if (!IsSupportedWorkflowTemplateWorkflowType(record.workflowType)) {
        return Fail(L"FAIL_TEMPLATE_WORKFLOW_TYPE_INVALID", L"workflow_type is missing or unsupported.");
    }
    if (!IsSupportedWorkflowTemplateStatus(record.templateStatus)) {
        return Fail(L"FAIL_TEMPLATE_STATUS_INVALID", L"template_status is missing or unsupported.");
    }
    record = FinalizeWorkflowTemplateRecord(record);
    WorkflowTemplateRecordResult result;
    result.ok = true;
    result.record = record;
    result.recordJson = WorkflowTemplateRecordToJson(record);
    return result;
}

WorkflowTemplateRecordResult LoadWorkflowTemplateRecordInput(const std::wstring& inputJsonPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(inputJsonPath, text, error)) {
        return Fail(L"FILE_NOT_FOUND", L"Could not read workflow template input JSON.");
    }
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok) {
        return Fail(L"FAIL_TEMPLATE_SCHEMA_INVALID", L"Invalid JSON: " + parsed.error);
    }
    return BuildWorkflowTemplateRecordFromJson(parsed.root);
}

WorkflowTemplateRecordResult ParseWorkflowTemplateRecordJson(const std::wstring& recordJson) {
    simplejson::ParseResult parsed = simplejson::Parse(recordJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return Fail(L"FAIL_TEMPLATE_SCHEMA_INVALID", parsed.ok ? L"Template JSON must be an object." : parsed.error);
    }
    return BuildWorkflowTemplateRecordFromJson(parsed.root);
}

std::wstring WorkflowTemplateRecordToJson(const WorkflowTemplateRecord& record) {
    std::wstringstream json;
    json << L"{"
         << L"\"schema_version\":\"6.11.0.workflow_template_record\""
         << L",\"template_id\":" << simplejson::Quote(record.templateId)
         << L",\"template_name\":" << simplejson::Quote(record.templateName)
         << L",\"template_version\":" << simplejson::Quote(record.templateVersion)
         << L",\"workflow_type\":" << simplejson::Quote(record.workflowType)
         << L",\"template_status\":" << simplejson::Quote(record.templateStatus)
         << L",\"source_evidence_refs\":" << WorkflowTemplateStringArrayJson(record.sourceEvidenceRefs)
         << L",\"source_memory_refs\":" << WorkflowTemplateStringArrayJson(record.sourceMemoryRefs)
         << L",\"required_inputs\":" << WorkflowTemplateStringArrayJson(record.requiredInputs)
         << L",\"optional_inputs\":" << WorkflowTemplateStringArrayJson(record.optionalInputs)
         << L",\"parameter_schema\":" << record.parameterSchemaJson
         << L",\"step_contract_skeleton\":" << record.stepContractSkeletonJson
         << L",\"expected_context_schema\":" << record.expectedContextSchemaJson
         << L",\"verification_hint_schema\":" << record.verificationHintSchemaJson
         << L",\"risk_level\":" << simplejson::Quote(record.riskLevel)
         << L",\"confirmation_policy\":" << record.confirmationPolicyJson
         << L",\"stop_policy\":" << record.stopPolicyJson
         << L",\"recovery_policy\":" << record.recoveryPolicyJson
         << L",\"safety_constraints\":" << record.safetyConstraintsJson
         << L",\"created_from_version\":" << simplejson::Quote(record.createdFromVersion)
         << L",\"trusted_version\":" << simplejson::Quote(record.trustedVersion)
         << L",\"template_hash\":" << simplejson::Quote(record.templateHash)
         << L",\"validation_status\":" << simplejson::Quote(record.validationStatus)
         << L",\"validation_report_ref\":" << simplejson::Quote(record.validationReportRef)
         << L",\"redaction_applied\":" << simplejson::Bool(record.redactionApplied)
         << L",\"executable\":" << simplejson::Bool(WorkflowTemplateExecutable(record))
         << L"}";
    return json.str();
}

