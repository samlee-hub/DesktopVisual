#include "ExperienceMemoryRecord.h"

#include "EvidenceFingerprint.h"
#include "FailureAttributionNormalizer.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <algorithm>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool StartsWithNoCase(const std::wstring& value, const std::wstring& prefix) {
    std::wstring lowerValue = Lower(value);
    std::wstring lowerPrefix = Lower(prefix);
    return lowerValue.rfind(lowerPrefix, 0) == 0;
}

std::wstring Trim(std::wstring value) {
    while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
    while (!value.empty() && iswspace(value.back())) value.pop_back();
    return value;
}

std::wstring JsonOptionalString(const simplejson::Value& object, const std::wstring& key) {
    return simplejson::GetString(object, key, L"");
}

bool JsonOptionalBool(const simplejson::Value& object, const std::wstring& key, bool def = false) {
    return simplejson::GetBool(object, key, def);
}

bool HasNonEmptyString(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && value->IsString() && !value->stringValue.empty();
}

bool IsSensitiveBodyKeyPresent(const simplejson::Value& input) {
    static const std::vector<std::wstring> bodyKeys = {
        L"body",
        L"message_body",
        L"plaintext_body",
        L"full_body",
        L"chat_content"
    };
    for (const auto& key : bodyKeys) {
        if (HasNonEmptyString(input, key)) return true;
    }
    return false;
}

std::wstring ResolveEvidenceRef(const std::wstring& path) {
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

std::wstring CanonicalRecordSeed(const ExperienceMemoryRecord& record) {
    std::wstringstream seed;
    seed << L"task_id=" << record.taskId << L"\n";
    seed << L"workflow_type=" << record.workflowType << L"\n";
    seed << L"workflow_id=" << record.workflowId << L"\n";
    seed << L"runtime_session_id=" << record.runtimeSessionId << L"\n";
    seed << L"step_contract_ref=" << record.stepContractRef << L"\n";
    seed << L"execution_result=" << record.executionResult << L"\n";
    seed << L"failure_type=" << record.failureType << L"\n";
    seed << L"failure_code=" << record.failureCode << L"\n";
    seed << L"normalized_failure_category=" << record.normalizedFailureCategory << L"\n";
    seed << L"evidence_ref=" << record.evidenceRef << L"\n";
    seed << L"evidence_hash=" << record.evidenceHash << L"\n";
    seed << L"source_version=" << record.sourceVersion << L"\n";
    seed << L"trusted_version=" << record.trustedVersion << L"\n";
    seed << L"memory_schema_version=" << record.memorySchemaVersion << L"\n";
    seed << L"redaction_applied=" << (record.redactionApplied ? L"true" : L"false") << L"\n";
    return seed.str();
}

void FinalizeRecordIds(ExperienceMemoryRecord& record) {
    std::wstring seed = CanonicalRecordSeed(record);
    record.recordHash = ValidationHashText(seed);
    if (record.recordId.empty()) {
        record.recordId = L"memory-" + record.recordHash;
    }
}

ExperienceMemoryRecordResult Fail(const std::wstring& code, const std::wstring& message) {
    ExperienceMemoryRecordResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    return result;
}

std::wstring BoolField(const std::wstring& key, bool value) {
    return L",\"" + key + L"\":" + simplejson::Bool(value);
}

}  // namespace

bool IsSupportedExperienceWorkflowType(const std::wstring& workflowType) {
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

bool IsSupportedExperienceExecutionResult(const std::wstring& executionResult) {
    static const std::vector<std::wstring> values = {
        L"success",
        L"failed",
        L"blocked",
        L"stopped",
        L"raw_completed_unverified"
    };
    for (const auto& value : values) {
        if (Lower(value) == Lower(executionResult)) return true;
    }
    return false;
}

bool IsSupportedExperienceFailureType(const std::wstring& failureType) {
    static const std::vector<std::wstring> values = {
        L"none",
        L"locator_failure",
        L"context_mismatch",
        L"runtime_guard_stop",
        L"credential_required",
        L"active_protection",
        L"step_validation_failed",
        L"execution_verification_failed",
        L"evidence_missing",
        L"environment_blocked",
        L"unknown"
    };
    for (const auto& value : values) {
        if (Lower(value) == Lower(failureType)) return true;
    }
    return false;
}

std::wstring ResolveExperienceMemoryPath(const std::wstring& path) {
    return ResolveEvidenceRef(path);
}

std::wstring ExperienceMemoryEvidenceHash(const std::wstring& path) {
    std::wstring resolved = ResolveEvidenceRef(path);
    if (resolved.empty() || !ValidationFileExists(resolved)) {
        return ValidationHashText(L"missing:" + resolved);
    }
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(resolved, text, error)) {
        return ValidationHashText(L"unreadable:" + resolved);
    }
    return ValidationHashText(text);
}

ExperienceMemoryRecordResult BuildExperienceMemoryRecordFromJson(
    const simplejson::Value& input) {
    if (!input.IsObject()) {
        return Fail(L"FAIL_MEMORY_SCHEMA_INVALID", L"Experience memory input must be a JSON object.");
    }

    ExperienceMemoryRecord record;
    record.recordId = JsonOptionalString(input, L"record_id");
    record.taskId = JsonOptionalString(input, L"task_id");
    record.workflowType = JsonOptionalString(input, L"workflow_type");
    record.workflowId = JsonOptionalString(input, L"workflow_id");
    record.runtimeSessionId = JsonOptionalString(input, L"runtime_session_id");
    record.stepContractRef = JsonOptionalString(input, L"step_contract_ref");
    record.executionResult = JsonOptionalString(input, L"execution_result");
    record.failureType = JsonOptionalString(input, L"failure_type");
    record.failureReason = JsonOptionalString(input, L"failure_reason");
    record.failureCode = JsonOptionalString(input, L"failure_code");
    record.evidenceRef = ResolveEvidenceRef(JsonOptionalString(input, L"evidence_ref"));
    record.createdAt = JsonOptionalString(input, L"created_at");
    record.sourceVersion = JsonOptionalString(input, L"source_version");
    record.trustedVersion = JsonOptionalString(input, L"trusted_version");
    record.memorySchemaVersion = JsonOptionalString(input, L"memory_schema_version");
    record.redactionApplied = JsonOptionalBool(input, L"redaction_applied", false);
    record.memoryExecutionInfluence = JsonOptionalBool(input, L"memory_execution_influence", false);
    record.runtimeExecutionTriggered = JsonOptionalBool(input, L"runtime_execution_triggered", false);
    record.stepContractMutated = JsonOptionalBool(input, L"step_contract_mutated", false);
    record.querySideEffect = JsonOptionalBool(input, L"query_side_effect", false);
    record.workflowActionGenerated = JsonOptionalBool(input, L"workflow_action_generated", false);
    record.trustedSource = JsonOptionalBool(input, L"trusted_source", true);
    record.evidenceTrusted = JsonOptionalBool(input, L"evidence_trusted", true);
    record.runnerOnlyMemoryLogic = JsonOptionalBool(input, L"runner_only_memory_logic", false);
    record.redactedRecipient = JsonOptionalString(input, L"redacted_recipient");
    record.subjectHash = JsonOptionalString(input, L"subject_hash");

    if (record.memorySchemaVersion.empty()) record.memorySchemaVersion = L"experience_memory.v1";
    if (record.createdAt.empty()) record.createdAt = NowTimestamp();
    if (record.failureType.empty()) record.failureType = L"none";
    if (record.executionResult.empty()) record.executionResult = L"failed";

    if (record.taskId.empty()) return Fail(L"FAIL_MEMORY_TASK_ID_MISSING", L"task_id is required.");
    if (!IsSupportedExperienceWorkflowType(record.workflowType)) {
        return Fail(L"FAIL_MEMORY_WORKFLOW_TYPE_INVALID", L"workflow_type is missing or unsupported.");
    }
    if (!IsSupportedExperienceExecutionResult(record.executionResult)) {
        return Fail(L"FAIL_MEMORY_EXECUTION_RESULT_INVALID", L"execution_result is missing or unsupported.");
    }
    if (!IsSupportedExperienceFailureType(record.failureType)) {
        return Fail(L"FAIL_MEMORY_FAILURE_TYPE_INVALID", L"failure_type is missing or unsupported.");
    }
    if (record.evidenceRef.empty()) {
        return Fail(L"FAIL_MEMORY_EVIDENCE_REF_MISSING", L"evidence_ref is required.");
    }
    if (!ValidationFileExists(record.evidenceRef)) {
        return Fail(L"FAIL_MEMORY_EVIDENCE_REF_INVALID", L"evidence_ref does not exist.");
    }
    if (record.sourceVersion.empty()) {
        return Fail(L"FAIL_MEMORY_SOURCE_VERSION_MISSING", L"source_version is required.");
    }
    if (record.trustedVersion.empty()) {
        return Fail(L"FAIL_MEMORY_TRUSTED_VERSION_MISSING", L"trusted_version is required.");
    }
    if (Lower(record.executionResult) == L"success" &&
        (Lower(record.failureType) == L"evidence_missing" ||
         Lower(record.failureType) == L"unknown" ||
         Lower(record.failureCode) == L"raw_completed_unverified")) {
        return Fail(L"FAIL_RAW_COMPLETED_AS_SUCCESS", L"Failure or raw completion signal cannot be recorded as success.");
    }

    FailureAttributionNormalizationInput normalization;
    normalization.workflowType = record.workflowType;
    normalization.executionResult = record.executionResult;
    normalization.failureType = record.failureType;
    normalization.failureCode = record.failureCode;
    normalization.failureReason = record.failureReason;
    FailureAttributionNormalizationResult normalized = NormalizeFailureAttribution(normalization);
    record.normalizedFailureCategory = JsonOptionalString(input, L"normalized_failure_category");
    if (record.normalizedFailureCategory.empty()) {
        record.normalizedFailureCategory = normalized.normalizedCategory;
    }
    if (Lower(record.executionResult) == L"success" &&
        record.normalizedFailureCategory != L"SUCCESS_NO_FAILURE") {
        return Fail(L"FAIL_SUCCESS_WITH_FAILURE_CATEGORY", L"success record cannot carry a failure category.");
    }
    if (Lower(record.executionResult) != L"success" &&
        record.normalizedFailureCategory == L"SUCCESS_NO_FAILURE") {
        return Fail(L"FAIL_UNKNOWN_FAILURE_MAPPING", L"non-success record cannot map to SUCCESS_NO_FAILURE.");
    }

    if (Lower(record.workflowType) == L"communication") {
        record.redactionApplied = true;
        std::wstring recipient = JsonOptionalString(input, L"recipient");
        if (!recipient.empty() && record.redactedRecipient.empty()) {
            record.redactedRecipient = L"hash:" + ValidationHashText(recipient);
        }
        std::wstring subject = JsonOptionalString(input, L"subject");
        if (!subject.empty() && record.subjectHash.empty()) {
            record.subjectHash = L"hash:" + ValidationHashText(subject);
        }
        if (IsSensitiveBodyKeyPresent(input)) {
            record.redactionApplied = true;
        }
    }

    record.evidenceHash = ExperienceMemoryEvidenceHash(record.evidenceRef);
    FinalizeRecordIds(record);
    ExperienceMemoryRecordResult result;
    result.ok = true;
    result.record = record;
    result.recordJson = ExperienceMemoryRecordToJson(record);
    return result;
}

ExperienceMemoryRecordResult LoadExperienceMemoryRecordInput(
    const std::wstring& inputJsonPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(inputJsonPath, text, error)) {
        return Fail(L"FILE_NOT_FOUND", L"Could not read memory input JSON.");
    }
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok) {
        return Fail(L"FAIL_MEMORY_SCHEMA_INVALID", L"Invalid JSON: " + parsed.error);
    }
    return BuildExperienceMemoryRecordFromJson(parsed.root);
}

ExperienceMemoryRecordResult ParseExperienceMemoryRecordJson(
    const std::wstring& recordJson) {
    simplejson::ParseResult parsed = simplejson::Parse(recordJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return Fail(L"FAIL_MEMORY_SCHEMA_INVALID", parsed.ok ? L"Record JSON must be an object." : parsed.error);
    }
    ExperienceMemoryRecord record;
    record.recordId = JsonOptionalString(parsed.root, L"record_id");
    record.taskId = JsonOptionalString(parsed.root, L"task_id");
    record.workflowType = JsonOptionalString(parsed.root, L"workflow_type");
    record.workflowId = JsonOptionalString(parsed.root, L"workflow_id");
    record.runtimeSessionId = JsonOptionalString(parsed.root, L"runtime_session_id");
    record.stepContractRef = JsonOptionalString(parsed.root, L"step_contract_ref");
    record.executionResult = JsonOptionalString(parsed.root, L"execution_result");
    record.failureType = JsonOptionalString(parsed.root, L"failure_type");
    record.failureReason = JsonOptionalString(parsed.root, L"failure_reason");
    record.failureCode = JsonOptionalString(parsed.root, L"failure_code");
    record.normalizedFailureCategory = JsonOptionalString(parsed.root, L"normalized_failure_category");
    record.evidenceRef = JsonOptionalString(parsed.root, L"evidence_ref");
    record.evidenceHash = JsonOptionalString(parsed.root, L"evidence_hash");
    record.createdAt = JsonOptionalString(parsed.root, L"created_at");
    record.sourceVersion = JsonOptionalString(parsed.root, L"source_version");
    record.trustedVersion = JsonOptionalString(parsed.root, L"trusted_version");
    record.memorySchemaVersion = JsonOptionalString(parsed.root, L"memory_schema_version");
    record.redactionApplied = JsonOptionalBool(parsed.root, L"redaction_applied", false);
    record.memoryExecutionInfluence = JsonOptionalBool(parsed.root, L"memory_execution_influence", false);
    record.runtimeExecutionTriggered = JsonOptionalBool(parsed.root, L"runtime_execution_triggered", false);
    record.stepContractMutated = JsonOptionalBool(parsed.root, L"step_contract_mutated", false);
    record.querySideEffect = JsonOptionalBool(parsed.root, L"query_side_effect", false);
    record.workflowActionGenerated = JsonOptionalBool(parsed.root, L"workflow_action_generated", false);
    record.trustedSource = JsonOptionalBool(parsed.root, L"trusted_source", true);
    record.evidenceTrusted = JsonOptionalBool(parsed.root, L"evidence_trusted", true);
    record.runnerOnlyMemoryLogic = JsonOptionalBool(parsed.root, L"runner_only_memory_logic", false);
    record.redactedRecipient = JsonOptionalString(parsed.root, L"redacted_recipient");
    record.subjectHash = JsonOptionalString(parsed.root, L"subject_hash");
    record.recordHash = JsonOptionalString(parsed.root, L"record_hash");
    ExperienceMemoryRecordResult result;
    result.ok = true;
    result.record = record;
    result.recordJson = ExperienceMemoryRecordToJson(record);
    return result;
}

std::wstring ExperienceMemoryRecordToJson(const ExperienceMemoryRecord& record) {
    std::wstringstream json;
    json << L"{"
         << L"\"record_id\":" << simplejson::Quote(record.recordId)
         << L",\"task_id\":" << simplejson::Quote(record.taskId)
         << L",\"workflow_type\":" << simplejson::Quote(record.workflowType)
         << L",\"workflow_id\":" << simplejson::Quote(record.workflowId)
         << L",\"runtime_session_id\":" << simplejson::Quote(record.runtimeSessionId)
         << L",\"step_contract_ref\":" << simplejson::Quote(record.stepContractRef)
         << L",\"execution_result\":" << simplejson::Quote(record.executionResult)
         << L",\"failure_type\":" << simplejson::Quote(record.failureType)
         << L",\"failure_reason\":" << simplejson::Quote(record.failureReason)
         << L",\"failure_code\":" << simplejson::Quote(record.failureCode)
         << L",\"normalized_failure_category\":" << simplejson::Quote(record.normalizedFailureCategory)
         << L",\"evidence_ref\":" << simplejson::Quote(record.evidenceRef)
         << L",\"evidence_hash\":" << simplejson::Quote(record.evidenceHash)
         << L",\"created_at\":" << simplejson::Quote(record.createdAt)
         << L",\"source_version\":" << simplejson::Quote(record.sourceVersion)
         << L",\"trusted_version\":" << simplejson::Quote(record.trustedVersion)
         << L",\"memory_schema_version\":" << simplejson::Quote(record.memorySchemaVersion)
         << BoolField(L"redaction_applied", record.redactionApplied)
         << BoolField(L"memory_execution_influence", record.memoryExecutionInfluence)
         << BoolField(L"runtime_execution_triggered", record.runtimeExecutionTriggered)
         << BoolField(L"step_contract_mutated", record.stepContractMutated)
         << BoolField(L"query_side_effect", record.querySideEffect)
         << BoolField(L"workflow_action_generated", record.workflowActionGenerated)
         << BoolField(L"trusted_source", record.trustedSource)
         << BoolField(L"evidence_trusted", record.evidenceTrusted)
         << BoolField(L"runner_only_memory_logic", record.runnerOnlyMemoryLogic)
         << L",\"record_hash\":" << simplejson::Quote(record.recordHash);
    if (!record.redactedRecipient.empty()) {
        json << L",\"redacted_recipient\":" << simplejson::Quote(record.redactedRecipient);
    }
    if (!record.subjectHash.empty()) {
        json << L",\"subject_hash\":" << simplejson::Quote(record.subjectHash);
    }
    json << L"}";
    return json.str();
}
