#pragma once

#include "WindowFinder.h"

#include <string>

struct MotionRecordResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

MotionRecordResult RecordMouseMotion(
    const WindowInfo& target,
    const std::wstring& scenario,
    int durationMs,
    const std::wstring& outPath);
