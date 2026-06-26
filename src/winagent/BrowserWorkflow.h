#pragma once

#include <string>
#include <vector>

struct BrowserWorkflowFieldSpec {
    std::wstring fieldId;
    std::wstring fieldLabel;
    std::wstring placeholder;
    std::wstring name;
    std::wstring title;
    std::wstring expectedRole;
    std::wstring value;
    bool required = false;
};

struct BrowserWorkflowSubmitSpec {
    std::wstring label;
    std::wstring expectedResultMarker;
    bool allowSubmit = false;
    bool postSubmitVerificationRequired = true;
};

struct BrowserWorkflowFormSpec {
    std::vector<BrowserWorkflowFieldSpec> fields;
    BrowserWorkflowSubmitSpec submit;
    std::wstring rawJson;
};

struct BrowserWorkflowSpec {
    std::wstring workflowId;
    std::wstring taskId;
    std::wstring workflowType;
    std::wstring url;
    std::wstring browser = L"auto";
    std::wstring expectedTitlePattern;
    std::wstring expectedUrlPattern;
    std::vector<std::wstring> requiredMarkers;
    std::vector<std::wstring> wrongPagePatterns;
    std::vector<std::wstring> activeProtectionPatterns;
    std::vector<std::wstring> credentialRequiredPatterns;
    std::wstring allowedOrigin;
    std::wstring allowedUrlPrefix;
    BrowserWorkflowFormSpec formSpec;
    std::wstring submitPolicyJson;
    std::wstring riskLevel;
    std::wstring expectedContextJson;
    std::wstring verificationHintJson;
    std::wstring recoveryPolicyJson;
    std::wstring stopPolicyJson;
    std::wstring sessionPolicyJson;
    std::wstring evidencePolicyJson;
    std::wstring requestedActionBackend;
    std::wstring verificationTargetText;
};

struct BrowserWorkflowSchemaResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    BrowserWorkflowSpec spec;
    std::wstring diagnosticsJson;
};

bool BrowserWorkflowTypeSupported(const std::wstring& workflowType);
bool BrowserWorkflowTypeIsSubmit(const std::wstring& workflowType);
bool BrowserWorkflowTypeIsBlockedStop(const std::wstring& workflowType);
bool BrowserWorkflowTypeIsReadOnly(const std::wstring& workflowType);
std::wstring BrowserWorkflowRiskForType(const std::wstring& workflowType, const std::wstring& requestedRisk, const std::wstring& url);
bool BrowserWorkflowUrlAllowedByPrefix(const std::wstring& url, const std::wstring& allowedUrlPrefix);
std::wstring BrowserWorkflowDefaultAllowedOrigin(const std::wstring& url);

BrowserWorkflowSchemaResult ParseBrowserWorkflowSpecJson(const std::wstring& json);
BrowserWorkflowSchemaResult ParseBrowserWorkflowSpecFile(const std::wstring& inputPath);
