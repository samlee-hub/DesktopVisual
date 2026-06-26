#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct MotionRawPoint {
    int x = 0;
    int y = 0;
    int timestampMs = 0;
    std::wstring buttonState;
};

struct MotionRawSample {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring scenario;
    std::wstring sampleId;
    std::vector<MotionRawPoint> points;
};

struct OperatorMotionProfile {
    bool exists = false;
    bool valid = false;
    int version = 1;
    std::wstring profileId;
    std::wstring source;
    std::wstring createdAt;
    std::wstring createdBy;
    int sampleCount = 0;
    int scenarioCount = 0;
    std::wstring quality;
    std::wstring dpi;
    int screenCount = 0;
    std::wstring primaryScreenSize;
    std::wstring pointerSpeedNote;
    double avgDurationMs = 320.0;
    double minDurationMs = 120.0;
    double maxDurationMs = 1200.0;
    double avgDistancePx = 320.0;
    double curvaturePx = 8.0;
    double jitterPx = 1.6;
    double endpointCorrectionPx = 3.0;
    std::vector<double> velocityCurve;
    std::vector<std::wstring> directionCoverage;
    std::vector<std::wstring> distanceCoverage;
    std::vector<std::wstring> warnings;
    std::wstring profilePath;
};

struct MotionProfileOperationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

std::wstring DefaultOperatorMotionProfilePath();
std::wstring DefaultMotionProfileRawDir();
bool EnsureMotionProfileDirectories();

MotionRawSample ReadMotionRawSampleFile(const std::wstring& path);
MotionProfileOperationResult CalibrateOperatorMotionProfile(const std::wstring& inputDir, const std::wstring& outPath, const std::wstring& source);
MotionProfileOperationResult LoadOperatorMotionProfile(const std::wstring& profilePath, OperatorMotionProfile& profile);
MotionProfileOperationResult OperatorMotionProfileInfo(const std::wstring& profilePath);
MotionProfileOperationResult ValidateOperatorMotionProfile(const std::wstring& profilePath, const std::wstring& outPath);
MotionProfileOperationResult ClearOperatorMotionProfile(const std::wstring& profilePath);

std::wstring OperatorMotionProfileExtraJson(const OperatorMotionProfile& profile, int synthesizedPointCount);
