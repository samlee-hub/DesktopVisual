#pragma once

#include <string>

struct ExplorerWorkflowSpec {
    std::wstring workflowId;
    std::wstring taskId;
    std::wstring workflowType;
    std::wstring sourcePath;
    std::wstring targetPath;
    std::wstring destinationPath;
    std::wstring expectedFolder;
    std::wstring expectedFilename;
    std::wstring expectedExtension;
    bool confirmationRequired = false;
    std::wstring confirmationToken;
    std::wstring allowedRoot = L"D:\\testrepo";
    std::wstring riskLevel;
    std::wstring expectedContextJson;
    std::wstring verificationHintJson;
    std::wstring recoveryPolicyJson;
    std::wstring stopPolicyJson;
    std::wstring sessionPolicyJson;
    std::wstring evidencePolicyJson;
    std::wstring contextMenuAction;
};

struct ExplorerWorkflowSchemaResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    ExplorerWorkflowSpec spec;
    std::wstring diagnosticsJson;
};

std::wstring ExplorerWorkflowDefaultAllowedRoot();
std::wstring ExplorerWorkflowNormalizePath(const std::wstring& path);
bool ExplorerWorkflowPathWithinRoot(const std::wstring& path, const std::wstring& allowedRoot);
std::wstring ExplorerWorkflowRiskForType(const std::wstring& workflowType, const std::wstring& requestedRisk);
bool ExplorerWorkflowTypeSupported(const std::wstring& workflowType);
bool ExplorerWorkflowTypeIsDestructive(const std::wstring& workflowType);
bool ExplorerWorkflowTypeIsReversibleDraft(const std::wstring& workflowType);
std::wstring ExplorerWorkflowJsonStringArray1(const std::wstring& value);

ExplorerWorkflowSchemaResult ParseExplorerWorkflowSpecJson(const std::wstring& json);
ExplorerWorkflowSchemaResult ParseExplorerWorkflowSpecFile(const std::wstring& inputPath);

