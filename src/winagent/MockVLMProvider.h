#pragma once

#include "VLMProvider.h"

class MockVLMProvider final : public IVLMProvider {
public:
    std::wstring provider_name() const override;
    std::wstring provider_role() const override;
    bool supports_request(const std::wstring& requestJson) const override;
    VLMProviderRunResult run_observation(const std::wstring& requestJson, const std::wstring& scenario) const override;
    VLMProviderCapabilities get_provider_capabilities() const override;
    bool validate_provider_config(std::wstring& error) const override;
};

int CommandVLMObservationRunMock(int argc, wchar_t** argv);

