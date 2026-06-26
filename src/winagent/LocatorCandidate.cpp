#include "LocatorCandidate.h"

#include "Trace.h"

#include <iomanip>
#include <sstream>

namespace {

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring NumberJson(double value) {
    std::wstringstream stream;
    stream << std::setprecision(12) << value;
    return stream.str();
}

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

}  // namespace

LocatorCandidate ConvertRuntimeValidatedCandidateToLocatorCandidate(
    const RuntimeCandidateValidationResult& candidate,
    const std::wstring& requestId,
    const std::wstring& resultId) {
    LocatorCandidate locator;
    if (!candidate.candidateValidationOk || !candidate.safeToConvertToLocatorCandidate) {
        locator.created = false;
        return locator;
    }
    locator.created = true;
    locator.sourceRequestId = requestId;
    locator.sourceResultId = resultId;
    locator.sourceCandidateId = candidate.candidateId;
    locator.targetRect = candidate.validatedRect;
    locator.targetCenterX = candidate.validatedCenterX;
    locator.targetCenterY = candidate.validatedCenterY;
    locator.role = candidate.candidateRole;
    locator.label = candidate.candidateLabel;
    locator.confidence = candidate.confidence;
    locator.runtimeValidationOk = true;
    locator.runtimeValidationMethod = candidate.validationMethod;
    locator.selector = L"coord:x=" + std::to_wstring(locator.targetCenterX) + L",y=" + std::to_wstring(locator.targetCenterY);
    return locator;
}

std::wstring LocatorCandidateJson(const LocatorCandidate& candidate) {
    if (!candidate.created) {
        return L"{\"created\":false,\"candidate_source\":\"vlm_assisted_runtime_validated\"}";
    }
    std::wstringstream json;
    json << L"{\"created\":true"
         << L",\"candidate_source\":" << JsonString(candidate.candidateSource)
         << L",\"source_request_id\":" << JsonString(candidate.sourceRequestId)
         << L",\"source_result_id\":" << JsonString(candidate.sourceResultId)
         << L",\"source_candidate_id\":" << JsonString(candidate.sourceCandidateId)
         << L",\"target_rect\":" << RectJson(candidate.targetRect)
         << L",\"target_center\":{\"x\":" << candidate.targetCenterX << L",\"y\":" << candidate.targetCenterY << L"}"
         << L",\"role\":" << JsonString(candidate.role)
         << L",\"label\":" << JsonString(candidate.label)
         << L",\"confidence\":" << NumberJson(candidate.confidence)
         << L",\"runtime_validation_ok\":" << BoolJson(candidate.runtimeValidationOk)
         << L",\"runtime_validation_method\":" << JsonString(candidate.runtimeValidationMethod)
         << L",\"requires_final_guard_check\":" << BoolJson(candidate.requiresFinalGuardCheck)
         << L",\"requires_mouse_first_evidence\":" << BoolJson(candidate.requiresMouseFirstEvidence)
         << L",\"requires_post_action_verification\":" << BoolJson(candidate.requiresPostActionVerification)
         << L",\"coordinate_source_type\":" << JsonString(candidate.coordinateSourceType)
         << L",\"selector\":" << JsonString(candidate.selector)
         << L"}";
    return json.str();
}

