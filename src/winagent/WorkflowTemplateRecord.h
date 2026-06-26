#pragma once

#include "SimpleJson.h"

#include <string>
#include <vector>

struct WorkflowTemplateRecord {
    std::wstring templateId;
    std::wstring templateName;
    std::wstring templateVersion;
    std::wstring workflowType;
    std::wstring templateStatus;
    std::vector<std::wstring> sourceEvidenceRefs;
    std::vector<std::wstring> sourceMemoryRefs;
    std::vector<std::wstring> requiredInputs;
    std::vector<std::wstring> optionalInputs;
    std::wstring parameterSchemaJson;
    std::wstring stepContractSkeletonJson;
    std::wstring expectedContextSchemaJson;
    std::wstring verificationHintSchemaJson;
    std::wstring riskLevel;
    std::wstring confirmationPolicyJson;
    std::wstring stopPolicyJson;
    std::wstring recoveryPolicyJson;
    std::wstring safetyConstraintsJson;
    std::wstring createdFromVersion;
    std::wstring trustedVersion;
    std::wstring templateHash;
    std::wstring validationStatus;
    std::wstring validationReportRef;
    bool redactionApplied = false;
};

struct WorkflowTemplateRecordResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    WorkflowTemplateRecord record;
    std::wstring recordJson;
};

bool IsSupportedWorkflowTemplateStatus(const std::wstring& status);
bool IsSupportedWorkflowTemplateWorkflowType(const std::wstring& workflowType);
bool WorkflowTemplateExecutable(const WorkflowTemplateRecord& record);
std::wstring DefaultWorkflowTemplateRegistryRoot();
std::wstring WorkflowTemplateResolveRef(const std::wstring& path);
std::wstring WorkflowTemplateValueToJson(const simplejson::Value& value);
std::wstring WorkflowTemplateStringArrayJson(const std::vector<std::wstring>& values);
std::wstring WorkflowTemplateHash(const WorkflowTemplateRecord& record);
WorkflowTemplateRecord FinalizeWorkflowTemplateRecord(WorkflowTemplateRecord record);
WorkflowTemplateRecordResult BuildWorkflowTemplateRecordFromJson(const simplejson::Value& input);
WorkflowTemplateRecordResult LoadWorkflowTemplateRecordInput(const std::wstring& inputJsonPath);
WorkflowTemplateRecordResult ParseWorkflowTemplateRecordJson(const std::wstring& recordJson);
std::wstring WorkflowTemplateRecordToJson(const WorkflowTemplateRecord& record);

