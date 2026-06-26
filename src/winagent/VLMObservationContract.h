#pragma once

#include <string>
#include <vector>

struct VLMRect {
    bool present = false;
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
};

struct VLMObservationRequestBuildOptions {
    std::wstring observeJsonPath;
    std::wstring screenshotPath;
    std::wstring taskHint;
    std::wstring expectedContext;
    std::wstring observationPurpose = L"scene_summary";
    std::wstring outputPath;
};

struct VLMContractResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring json;
};

struct VLMLayoutRegion {
    std::wstring regionId;
    std::wstring regionLabel;
    VLMRect approxBounds;
    std::wstring description;
    double confidence = 0.0;
};

struct VLMSemanticElement {
    std::wstring elementId;
    std::wstring label;
    std::wstring roleGuess;
    std::wstring text;
    VLMRect approxRegion;
    double confidence = 0.0;
    std::wstring reasoningSummary;
};

struct VLMPossibleTarget {
    std::wstring candidateId;
    std::wstring label;
    std::wstring roleGuess;
    VLMRect approxRegion;
    double confidence = 0.0;
    bool observationOnly = true;
    bool requiresRuntimeValidation = true;
};

struct VLMObservationResult {
    std::wstring resultId;
    std::wstring requestId;
    std::wstring providerName = L"mock_vlm_provider";
    std::wstring providerRole = L"assistive_only";
    std::wstring schemaVersion = L"6.5.0.vlm_observation_result";
    std::wstring sceneSummary;
    std::vector<std::wstring> visibleText;
    std::vector<VLMLayoutRegion> layoutRegions;
    std::vector<VLMSemanticElement> semanticElements;
    std::vector<VLMPossibleTarget> possibleTargets;
    double uncertainty = 0.0;
    std::wstring rejectionReason;
    std::vector<std::wstring> safetyNotes;
    bool containsAction = false;
    bool containsCoordinates = false;
    bool containsExecutableInstruction = false;
    bool containsBypassInstruction = false;
    bool containsCredentialInstruction = false;
    bool coordinateOnlyAction = false;
    bool runtimeCommandPresent = false;
    bool resultSchemaValid = true;
    std::wstring rawProviderOutputRef;
    std::wstring createdAt;
    std::wstring extraJsonFields;
};

std::vector<std::wstring> VLMAllowedOutputs();
std::vector<std::wstring> VLMForbiddenOutputs();
std::vector<std::wstring> VLMObservationPurposes();

bool VLMReadTextFile(const std::wstring& path, std::wstring& text, std::wstring& error);
bool VLMWriteTextFile(const std::wstring& path, const std::wstring& text, std::wstring& error);

std::wstring VLMRectJson(const VLMRect& rect);
std::wstring VLMStringArrayJson(const std::vector<std::wstring>& values);
std::wstring VLMObservationResultToJson(const VLMObservationResult& result);
std::wstring VLMGetRequestIdFromJson(const std::wstring& requestJson);
bool VLMRequestHasBlockedContext(const std::wstring& requestJson);

VLMContractResult BuildVLMObservationRequestFromJsonText(
    const std::wstring& observeJson,
    const VLMObservationRequestBuildOptions& options);

VLMContractResult BuildVLMObservationRequestFile(const VLMObservationRequestBuildOptions& options);

int CommandVLMObservationBuildRequest(int argc, wchar_t** argv);

