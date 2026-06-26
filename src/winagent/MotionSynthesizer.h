#pragma once

#include "MotionProfile.h"

#include <windows.h>

#include <string>
#include <vector>

struct MotionSynthesisResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::vector<POINT> points;
    int durationMs = 0;
    int distancePx = 0;
    std::wstring profilePath;
    std::wstring profileQuality;
    std::wstring profileSource;
};

MotionSynthesisResult SynthesizeOperatorMotionPath(
    const POINT& from,
    const POINT& to,
    int requestedDurationMs,
    const OperatorMotionProfile& profile);
