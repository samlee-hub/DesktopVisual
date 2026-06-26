#pragma once

#include "InputController.h"

#include <string>

enum class LatencyProfile {
    Conservative,
    Normal,
    FastVisibleUi
};

bool ParseLatencyProfileName(const std::wstring& raw, LatencyProfile& profile);
bool ParseLatencyProfileArg(int argc, wchar_t** argv, LatencyProfile& profile, std::wstring& error);
std::wstring LatencyProfileName(LatencyProfile profile);
void ApplyLatencyProfile(HumanMouseMotionOptions& options, LatencyProfile profile);
int LatencyProfileDefaultLaunchWaitMs(LatencyProfile profile);
int LatencyProfileDefaultRetryCount(LatencyProfile profile);
