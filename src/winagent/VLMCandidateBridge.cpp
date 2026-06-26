#include "VLMCandidateBridge.h"

#include "MockVLMProvider.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "VLMObservationContract.h"
#include "VLMObservationValidator.h"
#include "VLMProvider.h"

#include <algorithm>
#include <sstream>

namespace {

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& value) {
    if (value.empty()) return;
    if (std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

std::wstring JoinPath(const std::wstring& dir, const std::wstring& leaf) {
    if (dir.empty()) return L"";
    wchar_t last = dir.back();
    if (last == L'\\' || last == L'/') return dir + leaf;
    return dir + L"\\" + leaf;
}

std::wstring GetStringField(const std::wstring& json, const std::wstring& field) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) return L"";
    return simplejson::GetString(parsed.root, field, L"");
}

void WriteEvidence(
    const std::wstring& path,
    const std::wstring& content,
    std::vector<std::wstring>& evidencePaths) {
    if (path.empty()) return;
    std::wstring error;
    if (VLMWriteTextFile(path, content, error)) {
        evidencePaths.push_back(path);
    }
}

std::wstring EvidenceArrayJson(const std::vector<std::wstring>& values) {
    return VLMStringArrayJson(values);
}

}  // namespace

VLMCandidateBridgeResult RunVLMCandidateBridge(const VLMCandidateBridgeOptions& options) {
    VLMCandidateBridgeResult bridge;
    bridge.runtimeLocatorFailed = options.locateFailed;
    bridge.locateFailedReason = options.locateFailedReason.empty() ? L"LOCATOR_NOT_FOUND" : options.locateFailedReason;
    bridge.candidateValidationRequired = true;
    bridge.runtimeExecutionAllowed = false;

    if (!options.locateFailed) {
        bridge.bridgeInvoked = false;
        bridge.runtimeExecutionReason = L"VLM bridge requires a prior Runtime locate failure.";
        AddUnique(bridge.rejectionReasons, L"BRIDGE_REQUIRES_LOCATE_FAILED");
        bridge.resultJsonText = VLMCandidateBridgeResultJson(bridge);
        return bridge;
    }
    bridge.bridgeInvoked = true;

    VLMObservationRequestBuildOptions requestOptions;
    requestOptions.screenshotPath = options.screenshotPath;
    requestOptions.taskHint = options.targetLabel;
    requestOptions.expectedContext = options.expectedContext;
    requestOptions.observationPurpose = L"target_candidates_observation_only";
    VLMContractResult request = BuildVLMObservationRequestFromJsonText(options.observeJson, requestOptions);
    if (!request.ok) {
        bridge.runtimeExecutionReason = request.errorMessage;
        AddUnique(bridge.rejectionReasons, request.errorCode.empty() ? L"VLM_REQUEST_BUILD_FAILED" : request.errorCode);
        bridge.resultJsonText = VLMCandidateBridgeResultJson(bridge);
        return bridge;
    }
    bridge.requestJson = request.json;
    bridge.requestId = VLMGetRequestIdFromJson(request.json);

    VLMProviderRunResult providerResult;
    if (options.provider == L"external") {
        providerResult = ExternalVLMProviderDisabledResult();
    } else {
        MockVLMProvider provider;
        providerResult = provider.run_observation(request.json, options.scenario.empty() ? L"valid" : options.scenario);
    }
    bridge.providerName = providerResult.providerName;
    bridge.resultJson = providerResult.resultJson;
    bridge.resultId = GetStringField(providerResult.resultJson, L"result_id");
    if (!providerResult.ok) {
        bridge.runtimeExecutionReason = providerResult.errorMessage;
        AddUnique(bridge.rejectionReasons, providerResult.errorCode.empty() ? L"VLM_PROVIDER_FAILED" : providerResult.errorCode);
        bridge.resultJsonText = VLMCandidateBridgeResultJson(bridge);
        return bridge;
    }

    VLMObservationValidationResult validation = ValidateVLMObservationResultJson(request.json, providerResult.resultJson);
    bridge.vlmValidationJson = validation.resultJson;
    bridge.vlmResultValidated = validation.validationOk && validation.safeForRuntimeCandidatePipeline;
    if (!bridge.vlmResultValidated) {
        bridge.runtimeExecutionReason = L"VLM result failed assistive-only observation validation.";
        for (const auto& error : validation.validationErrors) AddUnique(bridge.rejectionReasons, error);
        if (!validation.blockedReason.empty()) AddUnique(bridge.rejectionReasons, validation.blockedReason);
        bridge.resultJsonText = VLMCandidateBridgeResultJson(bridge);
        return bridge;
    }

    RuntimeCandidateValidationOptions candidateOptions;
    candidateOptions.targetLabel = options.targetLabel;
    candidateOptions.expectedContext = options.expectedContext;
    bridge.runtimeValidation = ValidateRuntimeCandidatesFromJson(request.json, providerResult.resultJson, candidateOptions);
    bridge.candidateCount = bridge.runtimeValidation.candidateCount;
    bridge.validatedCandidateCount = bridge.runtimeValidation.validatedCandidateCount;
    bridge.rejectedCandidateCount = bridge.runtimeValidation.rejectedCandidateCount;
    bridge.selectedCandidateId = bridge.runtimeValidation.selectedCandidate.candidateId;
    for (const auto& reason : bridge.runtimeValidation.rejectionReasons) AddUnique(bridge.rejectionReasons, reason);

    if (bridge.runtimeValidation.validationOk) {
        bridge.locatorCandidate = ConvertRuntimeValidatedCandidateToLocatorCandidate(
            bridge.runtimeValidation.selectedCandidate,
            bridge.requestId,
            bridge.resultId);
        bridge.runtimeExecutionAllowed = bridge.locatorCandidate.created;
        bridge.runtimeExecutionReason = bridge.runtimeExecutionAllowed
            ? L"Runtime validated candidate may enter final Runtime guard and mouse action path."
            : L"Runtime candidate conversion failed.";
    } else {
        bridge.runtimeExecutionAllowed = false;
        bridge.runtimeExecutionReason = bridge.runtimeValidation.stopCode.empty()
            ? L"Runtime candidate validation rejected all candidates."
            : bridge.runtimeValidation.stopCode;
    }

    if (!options.evidenceDir.empty()) {
        WriteEvidence(JoinPath(options.evidenceDir, L"vlm_candidate_request.json"), bridge.requestJson, bridge.evidencePaths);
        WriteEvidence(JoinPath(options.evidenceDir, L"vlm_candidate_result.json"), bridge.resultJson, bridge.evidencePaths);
        WriteEvidence(JoinPath(options.evidenceDir, L"vlm_candidate_vlm_validation.json"), bridge.vlmValidationJson, bridge.evidencePaths);
        WriteEvidence(JoinPath(options.evidenceDir, L"runtime_candidate_validation.json"), bridge.runtimeValidation.resultJson, bridge.evidencePaths);
        WriteEvidence(JoinPath(options.evidenceDir, L"locator_candidate.json"), LocatorCandidateJson(bridge.locatorCandidate), bridge.evidencePaths);
    }

    bridge.resultJsonText = VLMCandidateBridgeResultJson(bridge);
    if (!options.evidenceDir.empty()) {
        WriteEvidence(JoinPath(options.evidenceDir, L"vlm_candidate_bridge_result.json"), bridge.resultJsonText, bridge.evidencePaths);
        bridge.resultJsonText = VLMCandidateBridgeResultJson(bridge);
    }
    return bridge;
}

std::wstring VLMCandidateBridgeResultJson(const VLMCandidateBridgeResult& result) {
    std::wstringstream json;
    json << L"{\"bridge_invoked\":" << BoolJson(result.bridgeInvoked)
         << L",\"runtime_locator_failed\":" << BoolJson(result.runtimeLocatorFailed)
         << L",\"locate_failed_reason\":" << JsonString(result.locateFailedReason)
         << L",\"request_id\":" << JsonString(result.requestId)
         << L",\"result_id\":" << JsonString(result.resultId)
         << L",\"provider_name\":" << JsonString(result.providerName)
         << L",\"vlm_result_validated\":" << BoolJson(result.vlmResultValidated)
         << L",\"candidate_count\":" << result.candidateCount
         << L",\"validated_candidate_count\":" << result.validatedCandidateCount
         << L",\"rejected_candidate_count\":" << result.rejectedCandidateCount
         << L",\"selected_candidate_id\":" << JsonString(result.selectedCandidateId)
         << L",\"candidate_validation_required\":" << BoolJson(result.candidateValidationRequired)
         << L",\"runtime_execution_allowed\":" << BoolJson(result.runtimeExecutionAllowed)
         << L",\"runtime_execution_reason\":" << JsonString(result.runtimeExecutionReason)
         << L",\"rejection_reasons\":" << VLMStringArrayJson(result.rejectionReasons)
         << L",\"evidence_paths\":" << EvidenceArrayJson(result.evidencePaths)
         << L",\"runtime_candidate_validation\":";
    if (!result.runtimeValidation.resultJson.empty()) {
        json << result.runtimeValidation.resultJson;
    } else {
        json << L"null";
    }
    json << L",\"locator_candidate\":" << LocatorCandidateJson(result.locatorCandidate)
         << L"}";
    return json.str();
}

std::wstring VLMAssistedLocatePayloadJson(
    const VLMCandidateBridgeResult& bridge,
    bool runtimeExecuted,
    bool mouseClickSent,
    bool runtimeContextGuardUsed,
    bool postActionVerified,
    const std::wstring& actionEvidenceJson) {
    const bool locatorCreated = bridge.locatorCandidate.created;
    std::wstringstream json;
    json << L"{\"legacy_mock_vlm\":true"
         << L",\"real_vlm\":false"
         << L",\"not_for_agent_workflow\":true"
         << L",\"runtime_locator_failed\":" << BoolJson(bridge.runtimeLocatorFailed)
         << L",\"vlm_bridge_invoked\":" << BoolJson(bridge.bridgeInvoked)
         << L",\"vlm_result_validated\":" << BoolJson(bridge.vlmResultValidated)
         << L",\"runtime_candidate_validated\":" << BoolJson(bridge.runtimeValidation.validationOk)
         << L",\"locator_candidate_created\":" << BoolJson(locatorCreated)
         << L",\"runtime_executed\":" << BoolJson(runtimeExecuted)
         << L",\"vlm_candidate_used\":" << BoolJson(locatorCreated)
         << L",\"runtime_context_guard_used\":" << BoolJson(runtimeContextGuardUsed)
         << L",\"mouse_click_sent\":" << BoolJson(mouseClickSent)
         << L",\"post_action_verified\":" << BoolJson(postActionVerified)
         << L",\"coordinate_source_type\":" << JsonString(bridge.locatorCandidate.coordinateSourceType)
         << L",\"bridge_result\":" << VLMCandidateBridgeResultJson(bridge)
         << L",\"runtime_candidate_validation\":";
    if (!bridge.runtimeValidation.resultJson.empty()) json << bridge.runtimeValidation.resultJson;
    else json << L"null";
    json << L",\"locator_candidate\":" << LocatorCandidateJson(bridge.locatorCandidate)
         << L",\"action_evidence\":" << (actionEvidenceJson.empty() ? L"null" : actionEvidenceJson)
         << L"}";
    return json.str();
}

