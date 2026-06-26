#include "VLMProvider.h"

#include "Trace.h"
#include "VLMObservationContract.h"

#include <sstream>

std::wstring VLMProviderCapabilitiesJson(const VLMProviderCapabilities& capabilities) {
    std::wstringstream json;
    json << L"{\"provider_name\":" << JsonString(capabilities.providerName)
         << L",\"provider_role\":" << JsonString(capabilities.providerRole)
         << L",\"supports_observation\":" << (capabilities.supportsObservation ? L"true" : L"false")
         << L",\"supports_actions\":" << (capabilities.supportsActions ? L"true" : L"false")
         << L",\"requires_api_key\":" << (capabilities.requiresApiKey ? L"true" : L"false")
         << L",\"external_disabled\":" << (capabilities.externalDisabled ? L"true" : L"false")
         << L",\"supported_purposes\":" << VLMStringArrayJson(capabilities.supportedPurposes)
         << L",\"supported_scenarios\":" << VLMStringArrayJson(capabilities.supportedScenarios)
         << L"}";
    return json.str();
}

VLMProviderRunResult ExternalVLMProviderDisabledResult() {
    VLMProviderRunResult result;
    result.ok = false;
    result.errorCode = L"PROVIDER_EXTERNAL_DISABLED";
    result.errorMessage = L"External VLM provider hook is disabled by default and no API key is required.";
    result.providerName = L"external_vlm_placeholder";
    result.providerRole = L"assistive_only";
    result.resultJson = L"{\"provider_name\":\"external_vlm_placeholder\",\"provider_role\":\"assistive_only\",\"disabled\":true,\"error_code\":\"PROVIDER_EXTERNAL_DISABLED\",\"requires_api_key\":false}";
    return result;
}

