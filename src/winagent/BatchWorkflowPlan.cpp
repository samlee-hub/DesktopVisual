#include "BatchWorkflowPlan.h"

#include "EvidenceFingerprint.h"
#include "Trace.h"
#include "WorkflowTemplateRecord.h"

#include <algorithm>
#include <sstream>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

BatchWorkflowPlanResult Fail(const std::wstring& code, const std::wstring& message) {
    BatchWorkflowPlanResult result;
    result.errorCode = code;
    result.errorMessage = message;
    return result;
}

std::wstring JsonField(const simplejson::Value& object, const std::wstring& key, const std::wstring& fallback) {
    const simplejson::Value* value = simplejson::Find(object, key);
    if (!value) return fallback;
    return WorkflowTemplateValueToJson(*value);
}

std::vector<std::wstring> StringArrayOrDefault(const simplejson::Value& object, const std::wstring& key, const std::vector<std::wstring>& fallback) {
    std::vector<std::wstring> values = simplejson::GetStringArray(object, key);
    return values.empty() ? fallback : values;
}

std::wstring InstancesJson(const std::vector<BatchTemplateInstance>& instances) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < instances.size(); ++i) {
        if (i) json << L",";
        json << L"{\"instance_id\":" << simplejson::Quote(instances[i].instanceId)
             << L",\"template_id\":" << simplejson::Quote(instances[i].templateId)
             << L",\"template_version\":" << simplejson::Quote(instances[i].templateVersion)
             << L",\"template_path\":" << simplejson::Quote(instances[i].templatePath)
             << L",\"parameter_values\":" << (instances[i].parameterValuesJson.empty() ? L"{}" : instances[i].parameterValuesJson)
             << L",\"evidence_ref\":" << simplejson::Quote(instances[i].evidenceRef)
             << L"}";
    }
    json << L"]";
    return json.str();
}

}  // namespace

bool IsSupportedBatchWorkflowMode(const std::wstring& mode) {
    return Lower(mode) == L"compile_only" ||
           Lower(mode) == L"validate_only" ||
           Lower(mode) == L"serial_execute_mock" ||
           Lower(mode) == L"serial_execute_runtime_safe";
}

bool IsExecutableBatchWorkflowMode(const std::wstring& mode) {
    return Lower(mode) == L"serial_execute_mock" || Lower(mode) == L"serial_execute_runtime_safe";
}

std::wstring BatchWorkflowPlanHash(const BatchWorkflowPlan& plan) {
    std::wstringstream seed;
    seed << L"batch_name=" << plan.batchName << L"\n";
    seed << L"batch_mode=" << plan.batchMode << L"\n";
    for (const auto& instance : plan.templateInstances) {
        seed << instance.instanceId << L"|" << instance.templateId << L"|" << instance.templateVersion << L"|" << instance.templatePath << L"|" << instance.parameterValuesJson << L"\n";
    }
    for (const auto& step : plan.executionOrder) seed << L"order=" << step << L"\n";
    seed << plan.dependencyGraphJson << L"\n" << plan.sharedContextPolicyJson << L"\n" << plan.sessionIsolationPolicyJson << L"\n";
    seed << plan.failurePolicyJson << L"\n" << plan.verificationPolicyJson << L"\n" << plan.evidencePolicyJson << L"\n";
    seed << plan.createdFromVersion << L"\n" << plan.trustedVersion << L"\n";
    return ValidationHashText(seed.str());
}

BatchWorkflowPlan FinalizeBatchWorkflowPlan(BatchWorkflowPlan plan) {
    if (plan.batchName.empty()) plan.batchName = L"v6.11 batch workflow plan";
    if (plan.batchMode.empty()) plan.batchMode = L"compile_only";
    if (plan.createdFromVersion.empty()) plan.createdFromVersion = L"6.11.0";
    if (plan.trustedVersion.empty()) plan.trustedVersion = L"6.10.0";
    if (plan.dependencyGraphJson.empty()) plan.dependencyGraphJson = L"[]";
    if (plan.sharedContextPolicyJson.empty()) plan.sharedContextPolicyJson = L"{\"shared_context_allowed\":false}";
    if (plan.sessionIsolationPolicyJson.empty()) plan.sessionIsolationPolicyJson = L"{\"concurrent_runtime_session\":false,\"session_per_instance\":true}";
    if (plan.failurePolicyJson.empty()) plan.failurePolicyJson = L"{\"default_policy\":\"stop_batch\",\"continue_on_verification_failure\":false}";
    if (plan.verificationPolicyJson.empty()) plan.verificationPolicyJson = L"{\"step_verifier_required\":true,\"independent_verifier_per_step\":true}";
    if (plan.evidencePolicyJson.empty()) plan.evidencePolicyJson = L"{\"evidence_required_per_instance\":true,\"raw_evidence_required\":true}";
    if (plan.executionOrder.empty()) {
        for (const auto& instance : plan.templateInstances) plan.executionOrder.push_back(instance.instanceId);
    }
    plan.batchHash = BatchWorkflowPlanHash(plan);
    if (plan.batchId.empty()) plan.batchId = L"batch-" + plan.batchHash;
    return plan;
}

BatchWorkflowPlanResult BuildBatchWorkflowPlanFromJson(const simplejson::Value& input) {
    if (!input.IsObject()) return Fail(L"FAIL_BATCH_SCHEMA_INVALID", L"BatchWorkflowPlan input must be an object.");
    BatchWorkflowPlan plan;
    plan.batchId = simplejson::GetString(input, L"batch_id");
    plan.batchName = simplejson::GetString(input, L"batch_name", L"v6.11 batch workflow plan");
    plan.batchMode = simplejson::GetString(input, L"batch_mode", L"compile_only");
    const simplejson::Value* instances = simplejson::Find(input, L"template_instances");
    if (instances && instances->IsArray()) {
        int index = 0;
        for (const auto& item : instances->arrayValue) {
            if (!item.IsObject()) continue;
            BatchTemplateInstance instance;
            instance.instanceId = simplejson::GetString(item, L"instance_id", L"instance-" + std::to_wstring(index));
            instance.templateId = simplejson::GetString(item, L"template_id");
            instance.templateVersion = simplejson::GetString(item, L"template_version", L"1.0.0");
            instance.templatePath = WorkflowTemplateResolveRef(simplejson::GetString(item, L"template_path"));
            instance.parameterValuesJson = JsonField(item, L"parameter_values", L"{}");
            instance.evidenceRef = WorkflowTemplateResolveRef(simplejson::GetString(item, L"evidence_ref"));
            plan.templateInstances.push_back(instance);
            ++index;
        }
    }
    plan.executionOrder = StringArrayOrDefault(input, L"execution_order", {});
    plan.dependencyGraphJson = JsonField(input, L"dependency_graph", L"[]");
    plan.sharedContextPolicyJson = JsonField(input, L"shared_context_policy", L"{\"shared_context_allowed\":false}");
    plan.sessionIsolationPolicyJson = JsonField(input, L"session_isolation_policy", L"{\"concurrent_runtime_session\":false,\"session_per_instance\":true}");
    plan.failurePolicyJson = JsonField(input, L"failure_policy", L"{\"default_policy\":\"stop_batch\",\"continue_on_verification_failure\":false}");
    plan.verificationPolicyJson = JsonField(input, L"verification_policy", L"{\"step_verifier_required\":true,\"independent_verifier_per_step\":true}");
    plan.evidencePolicyJson = JsonField(input, L"evidence_policy", L"{\"evidence_required_per_instance\":true,\"raw_evidence_required\":true}");
    plan.createdFromVersion = simplejson::GetString(input, L"created_from_version", L"6.11.0");
    plan.trustedVersion = simplejson::GetString(input, L"trusted_version", L"6.10.0");
    if (!IsSupportedBatchWorkflowMode(plan.batchMode)) return Fail(L"FAIL_BATCH_MODE_INVALID", L"Unsupported batch_mode.");
    plan = FinalizeBatchWorkflowPlan(plan);
    BatchWorkflowPlanResult result;
    result.ok = true;
    result.plan = plan;
    result.planJson = BatchWorkflowPlanToJson(plan);
    return result;
}

BatchWorkflowPlanResult ParseBatchWorkflowPlanJson(const std::wstring& json) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok) return Fail(L"FAIL_BATCH_SCHEMA_INVALID", parsed.error);
    return BuildBatchWorkflowPlanFromJson(parsed.root);
}

BatchWorkflowPlanResult LoadBatchWorkflowPlanFile(const std::wstring& inputPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(inputPath, text, error)) return Fail(L"FILE_NOT_FOUND", error);
    return ParseBatchWorkflowPlanJson(text);
}

std::wstring BatchWorkflowPlanToJson(const BatchWorkflowPlan& plan) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.batch_workflow_plan\""
         << L",\"batch_id\":" << simplejson::Quote(plan.batchId)
         << L",\"batch_name\":" << simplejson::Quote(plan.batchName)
         << L",\"batch_mode\":" << simplejson::Quote(plan.batchMode)
         << L",\"template_instances\":" << InstancesJson(plan.templateInstances)
         << L",\"execution_order\":" << WorkflowTemplateStringArrayJson(plan.executionOrder)
         << L",\"dependency_graph\":" << plan.dependencyGraphJson
         << L",\"shared_context_policy\":" << plan.sharedContextPolicyJson
         << L",\"session_isolation_policy\":" << plan.sessionIsolationPolicyJson
         << L",\"failure_policy\":" << plan.failurePolicyJson
         << L",\"verification_policy\":" << plan.verificationPolicyJson
         << L",\"evidence_policy\":" << plan.evidencePolicyJson
         << L",\"created_from_version\":" << simplejson::Quote(plan.createdFromVersion)
         << L",\"trusted_version\":" << simplejson::Quote(plan.trustedVersion)
         << L",\"batch_hash\":" << simplejson::Quote(plan.batchHash)
         << L",\"parallel_real_ui\":false"
         << L",\"runtime_executed\":false"
         << L"}";
    return json.str();
}

