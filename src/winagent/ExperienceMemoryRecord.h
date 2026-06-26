#pragma once

#include "SimpleJson.h"

#include <string>

struct ExperienceMemoryRecord {
    std::wstring recordId;
    std::wstring taskId;
    std::wstring workflowType;
    std::wstring workflowId;
    std::wstring runtimeSessionId;
    std::wstring stepContractRef;
    std::wstring executionResult;
    std::wstring failureType;
    std::wstring failureReason;
    std::wstring failureCode;
    std::wstring normalizedFailureCategory;
    std::wstring evidenceRef;
    std::wstring evidenceHash;
    std::wstring createdAt;
    std::wstring sourceVersion;
    std::wstring trustedVersion;
    std::wstring memorySchemaVersion;
    bool redactionApplied = false;
    bool memoryExecutionInfluence = false;
    bool runtimeExecutionTriggered = false;
    bool stepContractMutated = false;
    bool querySideEffect = false;
    bool workflowActionGenerated = false;
    bool trustedSource = true;
    bool evidenceTrusted = true;
    bool runnerOnlyMemoryLogic = false;
    std::wstring redactedRecipient;
    std::wstring subjectHash;
    std::wstring recordHash;
};

struct ExperienceMemoryRecordResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    ExperienceMemoryRecord record;
    std::wstring recordJson;
};

bool IsSupportedExperienceWorkflowType(const std::wstring& workflowType);
bool IsSupportedExperienceExecutionResult(const std::wstring& executionResult);
bool IsSupportedExperienceFailureType(const std::wstring& failureType);
std::wstring ResolveExperienceMemoryPath(const std::wstring& path);
std::wstring ExperienceMemoryEvidenceHash(const std::wstring& path);
ExperienceMemoryRecordResult BuildExperienceMemoryRecordFromJson(
    const simplejson::Value& input);
ExperienceMemoryRecordResult LoadExperienceMemoryRecordInput(
    const std::wstring& inputJsonPath);
ExperienceMemoryRecordResult ParseExperienceMemoryRecordJson(
    const std::wstring& recordJson);
std::wstring ExperienceMemoryRecordToJson(const ExperienceMemoryRecord& record);
