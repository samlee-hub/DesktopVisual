#pragma once

#include <string>

struct CommunicationWorkflowSpec {
    std::wstring workflowId;
    std::wstring taskId;
    std::wstring type;
    std::wstring recipient;
    std::wstring subject;
    std::wstring body;
    std::wstring contextSource;
    std::wstring expectedContextJson;
    std::wstring verificationHintJson;
    std::wstring riskLevel;
    std::wstring confirmationPolicyJson;
    std::wstring stopPolicyJson;
    std::wstring recoveryPolicyJson;
    std::wstring sessionPolicyJson;
    std::wstring evidencePolicyJson;
    std::wstring requestedActionBackend;
    std::wstring fixtureRoot;
};

struct CommunicationWorkflowSchemaResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    CommunicationWorkflowSpec spec;
    std::wstring diagnosticsJson;
};

bool CommunicationWorkflowTypeSupported(const std::wstring& type);
std::wstring CommunicationWorkflowRuntimeActionForType(const std::wstring& type);
std::wstring CommunicationWorkflowStepTypeForType(const std::wstring& type);
std::wstring CommunicationWorkflowNormalizeRisk(const std::wstring& requestedRisk);

CommunicationWorkflowSchemaResult ParseCommunicationWorkflowSpecJson(const std::wstring& json);
CommunicationWorkflowSchemaResult ParseCommunicationWorkflowSpecFile(const std::wstring& inputPath);
