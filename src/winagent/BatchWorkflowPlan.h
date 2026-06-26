#pragma once

#include "SimpleJson.h"

#include <string>
#include <vector>

struct BatchTemplateInstance {
    std::wstring instanceId;
    std::wstring templateId;
    std::wstring templateVersion;
    std::wstring templatePath;
    std::wstring parameterValuesJson;
    std::wstring evidenceRef;
};

struct BatchWorkflowPlan {
    std::wstring batchId;
    std::wstring batchName;
    std::wstring batchMode;
    std::vector<BatchTemplateInstance> templateInstances;
    std::vector<std::wstring> executionOrder;
    std::wstring dependencyGraphJson;
    std::wstring sharedContextPolicyJson;
    std::wstring sessionIsolationPolicyJson;
    std::wstring failurePolicyJson;
    std::wstring verificationPolicyJson;
    std::wstring evidencePolicyJson;
    std::wstring createdFromVersion;
    std::wstring trustedVersion;
    std::wstring batchHash;
};

struct BatchWorkflowPlanResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    BatchWorkflowPlan plan;
    std::wstring planJson;
};

bool IsSupportedBatchWorkflowMode(const std::wstring& mode);
bool IsExecutableBatchWorkflowMode(const std::wstring& mode);
std::wstring BatchWorkflowPlanHash(const BatchWorkflowPlan& plan);
BatchWorkflowPlan FinalizeBatchWorkflowPlan(BatchWorkflowPlan plan);
BatchWorkflowPlanResult BuildBatchWorkflowPlanFromJson(const simplejson::Value& input);
BatchWorkflowPlanResult ParseBatchWorkflowPlanJson(const std::wstring& json);
BatchWorkflowPlanResult LoadBatchWorkflowPlanFile(const std::wstring& inputPath);
std::wstring BatchWorkflowPlanToJson(const BatchWorkflowPlan& plan);

