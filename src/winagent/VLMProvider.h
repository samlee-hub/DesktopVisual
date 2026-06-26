#pragma once

#include <string>
#include <vector>

struct VLMProviderCapabilities {
    std::wstring providerName;
    std::wstring providerRole = L"assistive_only";
    bool supportsObservation = true;
    bool supportsActions = false;
    bool requiresApiKey = false;
    bool externalDisabled = false;
    std::vector<std::wstring> supportedPurposes;
    std::vector<std::wstring> supportedScenarios;
};

struct VLMProviderRunResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring providerName;
    std::wstring providerRole = L"assistive_only";
    std::wstring resultJson;
    std::wstring rawProviderOutputRef;
};

class IVLMProvider {
public:
    virtual ~IVLMProvider() = default;
    virtual std::wstring provider_name() const = 0;
    virtual std::wstring provider_role() const = 0;
    virtual bool supports_request(const std::wstring& requestJson) const = 0;
    virtual VLMProviderRunResult run_observation(const std::wstring& requestJson, const std::wstring& scenario) const = 0;
    virtual VLMProviderCapabilities get_provider_capabilities() const = 0;
    virtual bool validate_provider_config(std::wstring& error) const = 0;
};

std::wstring VLMProviderCapabilitiesJson(const VLMProviderCapabilities& capabilities);
VLMProviderRunResult ExternalVLMProviderDisabledResult();

