#include "MemorySafetyBoundary.h"

#include "EvidenceFingerprint.h"
#include "ExperienceMemoryStore.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <sstream>
#include <string>

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

bool StartsWithNoCase(const std::wstring& value, const std::wstring& prefix) {
    return Lower(value).rfind(Lower(prefix), 0) == 0;
}

bool ContainsNoCase(const std::wstring& value, const std::wstring& needle) {
    return !needle.empty() && Lower(value).find(Lower(needle)) != std::wstring::npos;
}

std::wstring ResolveRef(const std::wstring& value) {
    if (value.empty()) return L"";
    std::wstring normalized = value;
    std::replace(normalized.begin(), normalized.end(), L'/', L'\\');
    if (normalized.size() >= 2 && normalized[1] == L':') return ValidationNormalizePath(normalized);
    if (StartsWithNoCase(normalized, L"artifacts\\") ||
        StartsWithNoCase(normalized, L"src\\") ||
        StartsWithNoCase(normalized, L"docs\\")) {
        return ProjectPath(normalized);
    }
    return ValidationNormalizePath(normalized);
}

bool BoolTrue(const simplejson::Value& object, const std::wstring& key) {
    return simplejson::GetBool(object, key, false);
}

bool HasNonEmptyString(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && value->IsString() && !value->stringValue.empty();
}

bool HasAnyValue(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && !value->IsNull();
}

void AddViolation(std::vector<std::wstring>& violations, const std::wstring& code) {
    if (std::find(violations.begin(), violations.end(), code) == violations.end()) {
        violations.push_back(code);
    }
}

std::wstring ViolationsJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring BlockedReason(const std::vector<std::wstring>& violations) {
    static const std::vector<std::wstring> priority = {
        L"BLOCK_MEMORY_EXECUTION_INFLUENCE",
        L"BLOCK_MEMORY_QUERY_SIDE_EFFECT",
        L"FAIL_SENSITIVE_CONTENT_NOT_REDACTED",
        L"FAIL_RAW_COMPLETED_AS_SUCCESS",
        L"FAIL_MEMORY_EVIDENCE_REF_MISSING",
        L"FAIL_MEMORY_EVIDENCE_REF_INVALID",
        L"FAIL_UNKNOWN_FAILURE_MAPPING",
        L"FAIL_UNTRUSTED_MEMORY_SOURCE",
        L"FAIL_RUNNER_ONLY_MEMORY_LOGIC"
    };
    for (const auto& code : priority) {
        if (std::find(violations.begin(), violations.end(), code) != violations.end()) return code;
    }
    return violations.empty() ? L"" : violations.front();
}

void CheckOneRecord(const simplejson::Value& root, std::vector<std::wstring>& violations) {
    if (!root.IsObject()) {
        AddViolation(violations, L"FAIL_MEMORY_SCHEMA_INVALID");
        return;
    }

    std::wstring evidenceRef = simplejson::GetString(root, L"evidence_ref", L"");
    if (evidenceRef.empty()) {
        AddViolation(violations, L"FAIL_MEMORY_EVIDENCE_REF_MISSING");
    } else if (!ValidationFileExists(ResolveRef(evidenceRef))) {
        AddViolation(violations, L"FAIL_MEMORY_EVIDENCE_REF_INVALID");
    }
    if (simplejson::GetString(root, L"source_version", L"").empty()) {
        AddViolation(violations, L"FAIL_MEMORY_SOURCE_VERSION_MISSING");
    }
    if (simplejson::GetString(root, L"trusted_version", L"").empty()) {
        AddViolation(violations, L"FAIL_MEMORY_TRUSTED_VERSION_MISSING");
    }

    std::wstring executionResult = Lower(simplejson::GetString(root, L"execution_result", L""));
    std::wstring failureType = Lower(simplejson::GetString(root, L"failure_type", L""));
    std::wstring failureCode = Lower(simplejson::GetString(root, L"failure_code", L""));
    std::wstring category = simplejson::GetString(root, L"normalized_failure_category", L"");
    if (executionResult == L"success" &&
        (failureType == L"evidence_missing" ||
         failureType == L"unknown" ||
         failureCode == L"raw_completed_unverified" ||
         category == L"EVIDENCE_MISSING")) {
        AddViolation(violations, L"FAIL_RAW_COMPLETED_AS_SUCCESS");
    }
    if (executionResult != L"success" && category == L"SUCCESS_NO_FAILURE") {
        AddViolation(violations, L"FAIL_UNKNOWN_FAILURE_MAPPING");
    }
    if (!failureCode.empty() && failureCode != L"none" && category == L"SUCCESS_NO_FAILURE") {
        AddViolation(violations, L"FAIL_UNKNOWN_FAILURE_MAPPING");
    }

    if (BoolTrue(root, L"memory_execution_influence") ||
        BoolTrue(root, L"runtime_execution_triggered") ||
        BoolTrue(root, L"step_contract_mutated") ||
        BoolTrue(root, L"step_contract_generated") ||
        BoolTrue(root, L"mutate_step_contract") ||
        BoolTrue(root, L"trigger_runtime_execution") ||
        BoolTrue(root, L"auto_retry_requested") ||
        BoolTrue(root, L"workflow_optimization_applied") ||
        HasAnyValue(root, L"selected_locator")) {
        AddViolation(violations, L"BLOCK_MEMORY_EXECUTION_INFLUENCE");
    }
    if (BoolTrue(root, L"workflow_action_generated") ||
        BoolTrue(root, L"query_side_effect") ||
        HasAnyValue(root, L"generated_step_contract") ||
        HasAnyValue(root, L"workflow_action")) {
        AddViolation(violations, L"BLOCK_MEMORY_QUERY_SIDE_EFFECT");
    }

    std::wstring workflowType = Lower(simplejson::GetString(root, L"workflow_type", L""));
    if (workflowType == L"communication") {
        if (!simplejson::GetBool(root, L"redaction_applied", false)) {
            AddViolation(violations, L"FAIL_SENSITIVE_CONTENT_NOT_REDACTED");
        }
        static const std::vector<std::wstring> sensitiveKeys = {
            L"body",
            L"message_body",
            L"plaintext_body",
            L"full_body",
            L"chat_content",
            L"password",
            L"token",
            L"verification_code"
        };
        for (const auto& key : sensitiveKeys) {
            if (HasNonEmptyString(root, key)) {
                AddViolation(violations, L"FAIL_SENSITIVE_CONTENT_NOT_REDACTED");
            }
        }
        std::wstring recipient = simplejson::GetString(root, L"recipient", L"");
        if (!recipient.empty() &&
            !StartsWithNoCase(recipient, L"redacted:") &&
            !StartsWithNoCase(recipient, L"hash:")) {
            AddViolation(violations, L"FAIL_SENSITIVE_CONTENT_NOT_REDACTED");
        }
    }

    if (!simplejson::GetBool(root, L"trusted_source", true) ||
        !simplejson::GetBool(root, L"evidence_trusted", true) ||
        ContainsNoCase(evidenceRef, L"dirty") ||
        ContainsNoCase(evidenceRef, L"untracked")) {
        AddViolation(violations, L"FAIL_UNTRUSTED_MEMORY_SOURCE");
    }
    if (BoolTrue(root, L"runner_only_memory_logic")) {
        AddViolation(violations, L"FAIL_RUNNER_ONLY_MEMORY_LOGIC");
    }
}

MemorySafetyCheckResult BuildResult(const std::vector<std::wstring>& violations, int checkedCount) {
    MemorySafetyCheckResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = BlockedReason(violations);
    result.violations = violations;
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.10.0.memory_safety_boundary\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"checked_record_count\":" << checkedCount
         << L",\"violations\":" << ViolationsJson(violations)
         << L",\"memory_execution_influence_detected\":" << simplejson::Bool(std::find(violations.begin(), violations.end(), L"BLOCK_MEMORY_EXECUTION_INFLUENCE") != violations.end())
         << L",\"sensitive_plaintext_detected\":" << simplejson::Bool(std::find(violations.begin(), violations.end(), L"FAIL_SENSITIVE_CONTENT_NOT_REDACTED") != violations.end())
         << L",\"raw_completed_unverified_marked_success\":" << simplejson::Bool(std::find(violations.begin(), violations.end(), L"FAIL_RAW_COMPLETED_AS_SUCCESS") != violations.end())
         << L",\"runtime_execution_triggered\":false"
         << L",\"step_contract_mutated_by_memory\":false"
         << L"}";
    result.jsonReport = json.str();
    return result;
}

}  // namespace

MemorySafetyCheckResult CheckMemorySafetyJson(const std::wstring& json) {
    std::vector<std::wstring> violations;
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok) {
        AddViolation(violations, L"FAIL_MEMORY_SCHEMA_INVALID");
        return BuildResult(violations, 0);
    }
    if (parsed.root.IsArray()) {
        int count = 0;
        for (const auto& item : parsed.root.arrayValue) {
            CheckOneRecord(item, violations);
            ++count;
        }
        return BuildResult(violations, count);
    }
    CheckOneRecord(parsed.root, violations);
    return BuildResult(violations, 1);
}

MemorySafetyCheckResult CheckMemorySafetyFile(const std::wstring& inputJsonPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(inputJsonPath, text, error)) {
        std::vector<std::wstring> violations = {L"FAIL_MEMORY_EVIDENCE_REF_INVALID"};
        return BuildResult(violations, 0);
    }
    return CheckMemorySafetyJson(text);
}

MemorySafetyCheckResult CheckMemorySafetyStore(const std::wstring& storeRoot) {
    std::wstring recordsPath = ExperienceMemoryRecordsPath(storeRoot.empty() ? DefaultExperienceMemoryStoreRoot() : storeRoot);
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(recordsPath, text, error)) {
        return BuildResult({}, 0);
    }
    std::wistringstream lines(text);
    std::wstring line;
    std::vector<std::wstring> violations;
    int count = 0;
    while (std::getline(lines, line)) {
        if (line.empty()) continue;
        MemorySafetyCheckResult one = CheckMemorySafetyJson(line);
        for (const auto& violation : one.violations) AddViolation(violations, violation);
        ++count;
    }
    return BuildResult(violations, count);
}

int CommandMemorySafetyCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"memory-safety-check";
    ULONGLONG startTick = GetTickCount64();
    MemorySafetyCheckOptions options;
    ArgValue(argc, argv, L"--input", options.inputJsonPath);
    ArgValue(argc, argv, L"--store-root", options.storeRoot);
    ArgValue(argc, argv, L"--output", options.outputJsonPath);
    if (options.inputJsonPath.empty() && options.storeRoot.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"memory-safety-check requires --input or --store-root.", L"{}") << L"\n";
        return 2;
    }
    MemorySafetyCheckResult result = options.inputJsonPath.empty()
        ? CheckMemorySafetyStore(options.storeRoot)
        : CheckMemorySafetyFile(options.inputJsonPath);
    if (!options.outputJsonPath.empty()) {
        std::wstring error;
        WriteValidationTextFile(options.outputJsonPath, result.jsonReport, error);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason.empty() ? L"MEMORY_SAFETY_BLOCKED" : result.blockedReason, L"Memory safety boundary blocked the record or store.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
