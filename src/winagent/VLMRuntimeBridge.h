#pragma once

#include <string>

struct VLMRuntimeBridgeOptions {
    bool globalScreenshot = false;
    bool observationRequest = false;
    bool observationResult = false;
    bool candidateTarget = false;
    bool runtimeCandidateValidator = false;
    bool coordinateMapper = false;
    bool targetWindowLock = false;
    bool action = false;
    bool verification = false;
    bool visualManualInspection = false;
};

struct VLMRuntimeBridgeResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool vlmAssisted = false;
    bool visualManualInspection = false;
    bool runtimeValidated = false;
    bool coordinateMappingValid = false;
    bool targetLockPresent = false;
};

VLMRuntimeBridgeResult create_vlm_observation_request_from_global_frame(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult receive_vlm_candidate(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult validate_vlm_candidate_with_runtime(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult convert_candidate_to_locator_candidate(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult apply_coordinate_mapper(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult require_target_window_lock(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult verify_candidate_after_action(const VLMRuntimeBridgeOptions& options);
VLMRuntimeBridgeResult record_vlm_assisted_evidence(const VLMRuntimeBridgeOptions& options);
std::wstring VLMRuntimeBridgeJson(const VLMRuntimeBridgeResult& result);
