#pragma once

#include <string>

struct MotionPacerSelfTestOptions {
    int requestedHz = 165;
    int durationMs = 180;
    std::wstring motionProfile = L"165hz-visible";
};

struct MotionPacerSelfTestResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    int requestedHz = 0;
    double measuredAvgHz = 0.0;
    double measuredMinHz = 0.0;
    double measuredMaxIntervalMs = 0.0;
    int totalMoveDurationMs = 0;
    bool highResolutionTimerEnabled = false;
    int frameCount = 0;
};

MotionPacerSelfTestResult RunMotionPacerSelfTest(const MotionPacerSelfTestOptions& options);
std::wstring MotionPacerSelfTestJson(const MotionPacerSelfTestResult& result);
