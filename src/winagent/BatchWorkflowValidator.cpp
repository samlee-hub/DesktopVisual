#include "BatchWorkflowValidator.h"

#include "EvidenceFingerprint.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "WorkflowTemplateRecord.h"

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

void AddViolation(std::vector<std::wstring>& violations, const std::wstring& code) {
    if (std::find(violations.begin(), violations.end(), code) == violations.end()) violations.push_back(code);
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

std::wstring BlockedReason(const std::vector<std::wstring>& violations) {
    static const std::vector<std::wstring> priority = {
        L"BLOCK_BATCH_PARALLEL_UI",
        L"BLOCK_BATCH_SESSION_UNSAFE",
        L"BLOCK_BATCH_UNSAFE_FAILURE_POLICY",
        L"BLOCK_TEMPLATE_NOT_VALIDATED"
    };
    for (const auto& code : priority) {
        if (std::find(violations.begin(), violations.end(), code) != violations.end()) return code;
    }
    return violations.empty() ? L"" : violations.front();
}

bool TemplateValidated(const std::wstring& path) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(path, text, error)) return false;
    WorkflowTemplateRecordResult parsed = ParseWorkflowTemplateRecordJson(text);
    return parsed.ok && parsed.record.templateStatus == L"validated" && parsed.record.validationStatus == L"pass";
}

}  // namespace

BatchWorkflowValidationResult ValidateBatchWorkflowPlan(const BatchWorkflowPlan& plan) {
    std::vector<std::wstring> violations;
    if (!IsSupportedBatchWorkflowMode(plan.batchMode)) AddViolation(violations, L"FAIL_BATCH_MODE_INVALID");
    std::wstring combined = plan.sharedContextPolicyJson + L" " + plan.sessionIsolationPolicyJson + L" " +
        plan.failurePolicyJson + L" " + plan.verificationPolicyJson + L" " + plan.evidencePolicyJson;
    if (ContainsNoCase(plan.batchMode, L"parallel_real_ui") || ContainsNoCase(combined, L"parallel_real_ui") || ContainsNoCase(combined, L"\"parallel\":true")) {
        AddViolation(violations, L"BLOCK_BATCH_PARALLEL_UI");
    }
    if (ContainsNoCase(combined, L"concurrent_runtime_session") && !ContainsNoCase(combined, L"\"concurrent_runtime_session\":false")) {
        AddViolation(violations, L"BLOCK_BATCH_SESSION_UNSAFE");
    }
    if (ContainsNoCase(combined, L"continue_on_verification_failure") && !ContainsNoCase(combined, L"\"continue_on_verification_failure\":false")) {
        AddViolation(violations, L"BLOCK_BATCH_UNSAFE_FAILURE_POLICY");
    }
    if (!ContainsNoCase(plan.failurePolicyJson, L"stop_batch")) AddViolation(violations, L"BLOCK_BATCH_UNSAFE_FAILURE_POLICY");
    if (!ContainsNoCase(plan.verificationPolicyJson, L"step_verifier_required") || !ContainsNoCase(plan.verificationPolicyJson, L"true")) {
        AddViolation(violations, L"FAIL_BATCH_VERIFICATION_POLICY_INVALID");
    }
    if (!ContainsNoCase(plan.evidencePolicyJson, L"evidence_required_per_instance") || !ContainsNoCase(plan.evidencePolicyJson, L"true")) {
        AddViolation(violations, L"FAIL_BATCH_EVIDENCE_POLICY_INVALID");
    }
    for (const auto& instance : plan.templateInstances) {
        if (instance.templatePath.empty() || !TemplateValidated(instance.templatePath)) {
            AddViolation(violations, L"BLOCK_TEMPLATE_NOT_VALIDATED");
        }
    }
    BatchWorkflowValidationResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = BlockedReason(violations);
    result.violations = violations;
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.batch_workflow_validation\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"batch_id\":" << simplejson::Quote(plan.batchId)
         << L",\"batch_mode\":" << simplejson::Quote(plan.batchMode)
         << L",\"violations\":" << ViolationsJson(violations)
         << L",\"parallel_real_ui\":false"
         << L",\"concurrent_runtime_session\":false"
         << L",\"step_verifier_required\":true"
         << L",\"runtime_executed\":false"
         << L"}";
    result.reportJson = json.str();
    return result;
}

BatchWorkflowValidationResult ValidateBatchWorkflowPlanFile(const std::wstring& inputPath) {
    BatchWorkflowPlanResult plan = LoadBatchWorkflowPlanFile(inputPath);
    if (!plan.ok) {
        BatchWorkflowValidationResult result;
        result.status = L"BLOCKED";
        result.blockedReason = plan.errorCode;
        result.violations.push_back(plan.errorCode);
        result.reportJson = L"{\"schema_version\":\"6.11.0.batch_workflow_validation\",\"status\":\"BLOCKED\",\"blocked_reason\":" + simplejson::Quote(plan.errorCode) + L"}";
        return result;
    }
    return ValidateBatchWorkflowPlan(plan.plan);
}

int CommandBatchWorkflowValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"batch-workflow-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"batch-workflow-validate requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    BatchWorkflowValidationResult result = ValidateBatchWorkflowPlanFile(input);
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, result.reportJson, error);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Batch workflow validation failed.", result.reportJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.reportJson) << L"\n";
    return 0;
}

