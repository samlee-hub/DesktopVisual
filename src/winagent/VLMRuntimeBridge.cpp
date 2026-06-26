#include "VLMRuntimeBridge.h"

#include "SimpleJson.h"

namespace {

VLMRuntimeBridgeResult ValidateChain(const VLMRuntimeBridgeOptions& options) {
    VLMRuntimeBridgeResult result;
    result.visualManualInspection = options.visualManualInspection;
    result.runtimeValidated = options.runtimeCandidateValidator;
    result.coordinateMappingValid = options.coordinateMapper;
    result.targetLockPresent = options.targetWindowLock;

    if (options.visualManualInspection && !options.runtimeCandidateValidator) {
        result.ok = true;
        result.vlmAssisted = false;
        return result;
    }
    if (!options.runtimeCandidateValidator) {
        result.errorCode = L"FAIL_VLM_CANDIDATE_NOT_RUNTIME_VALIDATED";
        result.errorMessage = L"VLM-assisted actions require RuntimeCandidateValidator.";
        return result;
    }
    if (!options.coordinateMapper) {
        result.errorCode = L"FAIL_VLM_COORDINATE_MAPPING_INVALID";
        result.errorMessage = L"VLM candidate coordinates were not validated by ScreenshotCoordinateMapper.";
        return result;
    }
    if (!options.targetWindowLock) {
        result.errorCode = L"FAIL_VLM_TARGET_LOCK_MISSING";
        result.errorMessage = L"VLM candidate action requires TargetWindowLock.";
        return result;
    }

    const bool complete =
        options.globalScreenshot &&
        options.observationRequest &&
        options.observationResult &&
        options.candidateTarget &&
        options.runtimeCandidateValidator &&
        options.coordinateMapper &&
        options.targetWindowLock &&
        options.action &&
        options.verification;
    result.ok = complete;
    result.vlmAssisted = complete;
    if (!complete) {
        result.errorCode = L"FAIL_VLM_CANDIDATE_NOT_RUNTIME_VALIDATED";
        result.errorMessage = L"VLM-assisted evidence chain is incomplete.";
    }
    return result;
}

}  // namespace

VLMRuntimeBridgeResult create_vlm_observation_request_from_global_frame(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult receive_vlm_candidate(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult validate_vlm_candidate_with_runtime(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult convert_candidate_to_locator_candidate(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult apply_coordinate_mapper(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult require_target_window_lock(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult verify_candidate_after_action(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

VLMRuntimeBridgeResult record_vlm_assisted_evidence(const VLMRuntimeBridgeOptions& options) {
    return ValidateChain(options);
}

std::wstring VLMRuntimeBridgeJson(const VLMRuntimeBridgeResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"vlm_assisted\":" + simplejson::Bool(result.vlmAssisted);
    json += L",\"visual_manual_inspection\":" + simplejson::Bool(result.visualManualInspection);
    json += L",\"runtime_validated\":" + simplejson::Bool(result.runtimeValidated);
    json += L",\"runtime_candidate_validated\":" + simplejson::Bool(result.runtimeValidated);
    json += L",\"coordinate_mapping_valid\":" + simplejson::Bool(result.coordinateMappingValid);
    json += L",\"target_lock_present\":" + simplejson::Bool(result.targetLockPresent);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L"}";
    return json;
}
