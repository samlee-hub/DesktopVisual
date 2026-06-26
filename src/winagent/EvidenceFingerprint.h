#pragma once

#include <string>
#include <vector>

struct EvidenceFingerprint {
    std::wstring fingerprintId;
    std::wstring featureId;
    std::wstring featureVersion;
    std::wstring evidenceSourcePath;
    std::wstring inputSpecHash;
    std::wstring stepContractHash;
    std::wstring executionSummaryHash;
    std::wstring verificationSummaryHash;
    std::wstring finalStatusHash;
    std::wstring artifactManifestHash;
    std::wstring createdAt;
    std::wstring fingerprintVersion;
    std::wstring fingerprintStatus;
    bool fingerprintOk = false;
    bool uiWorkflowExecuted = false;
    bool fingerprintIsExecutionResult = false;
};

struct EvidenceFingerprintResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    EvidenceFingerprint fingerprint;
    std::wstring fingerprintJson;
};

bool ValidationFileExists(const std::wstring& path);
bool ValidationDirectoryExists(const std::wstring& path);
bool ReadValidationTextFile(const std::wstring& path, std::wstring& text, std::wstring& error);
bool WriteValidationTextFile(const std::wstring& path, const std::wstring& text, std::wstring& error);
std::wstring ValidationNormalizePath(const std::wstring& path);
std::wstring ValidationJoinPath(const std::wstring& root, const std::wstring& child);
std::wstring ValidationToLower(std::wstring value);
bool ValidationContainsNoCase(const std::wstring& text, const std::wstring& needle);
std::wstring ValidationHashText(const std::wstring& text);
std::wstring ValidationJsonArray(const std::vector<std::wstring>& values);

bool IsSupportedEvidenceFeature(const std::wstring& featureId);
std::wstring EvidenceFeatureVersion(const std::wstring& featureId);
EvidenceFingerprintResult CreateEvidenceFingerprint(
    const std::wstring& featureId,
    const std::wstring& evidencePath);
std::wstring EvidenceFingerprintToJson(const EvidenceFingerprint& fingerprint);

int CommandValidationFingerprint(int argc, wchar_t** argv);
