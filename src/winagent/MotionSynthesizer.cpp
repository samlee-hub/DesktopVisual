#include "MotionSynthesizer.h"

#include <algorithm>
#include <cmath>

namespace {

int ClampInt(int value, int minValue, int maxValue) {
    return value < minValue ? minValue : (value > maxValue ? maxValue : value);
}

double ClampDouble(double value, double minValue, double maxValue) {
    return value < minValue ? minValue : (value > maxValue ? maxValue : value);
}

int Distance(const POINT& from, const POINT& to) {
    int dx = to.x - from.x;
    int dy = to.y - from.y;
    return static_cast<int>(std::round(std::sqrt(static_cast<double>(dx * dx + dy * dy))));
}

double CurveProgress(const std::vector<double>& curve, double t) {
    if (curve.size() < 2) {
        return t * t * (3.0 - 2.0 * t);
    }
    double scaled = t * static_cast<double>(curve.size() - 1);
    int index = ClampInt(static_cast<int>(std::floor(scaled)), 0, static_cast<int>(curve.size() - 2));
    double local = scaled - static_cast<double>(index);
    double a = curve[static_cast<size_t>(index)];
    double b = curve[static_cast<size_t>(index + 1)];
    return a + ((b - a) * local);
}

double DefaultPeakVelocityPxPerMs() {
    return 1.6 * 1.3 * 1.3;
}

double DefaultAccelerationPxPerMs2() {
    return 0.006 * 1.3 * 1.3 * 1.3 * 1.3;
}

double DefaultDurationForDistance(int distancePx) {
    if (distancePx <= 2) return 0.0;

    double distance = static_cast<double>(distancePx);
    double peakVelocity = DefaultPeakVelocityPxPerMs();
    double acceleration = DefaultAccelerationPxPerMs2();
    double accelDistance = (peakVelocity * peakVelocity) / (2.0 * acceleration);
    double duration = 0.0;

    if (distance <= 2.0 * accelDistance) {
        duration = 2.0 * std::sqrt(distance / acceleration);
    } else {
        double accelTime = peakVelocity / acceleration;
        duration = (2.0 * accelTime) + ((distance - (2.0 * accelDistance)) / peakVelocity);
    }

    return ClampDouble(duration, 12.0, 1200.0);
}

double KinematicProgress(int distancePx, double durationMs, double t) {
    if (distancePx <= 0) return 1.0;
    if (durationMs <= 0.0) return 1.0;

    double distance = static_cast<double>(distancePx);
    double peakVelocity = DefaultPeakVelocityPxPerMs();
    double acceleration = DefaultAccelerationPxPerMs2();
    double accelDistance = (peakVelocity * peakVelocity) / (2.0 * acceleration);
    double time = ClampDouble(t, 0.0, 1.0) * durationMs;
    double traveled = 0.0;

    if (distance <= 2.0 * accelDistance) {
        double halfTime = durationMs / 2.0;
        if (time <= halfTime) {
            traveled = 0.5 * acceleration * time * time;
        } else {
            double remaining = durationMs - time;
            traveled = distance - (0.5 * acceleration * remaining * remaining);
        }
    } else {
        double accelTime = peakVelocity / acceleration;
        double cruiseDistance = distance - (2.0 * accelDistance);
        double cruiseTime = cruiseDistance / peakVelocity;
        if (time <= accelTime) {
            traveled = 0.5 * acceleration * time * time;
        } else if (time <= accelTime + cruiseTime) {
            traveled = accelDistance + ((time - accelTime) * peakVelocity);
        } else {
            double remaining = durationMs - time;
            traveled = distance - (0.5 * acceleration * remaining * remaining);
        }
    }

    return ClampDouble(traveled / distance, 0.0, 1.0);
}

}  // namespace

MotionSynthesisResult SynthesizeOperatorMotionPath(
    const POINT& from,
    const POINT& to,
    int requestedDurationMs,
    const OperatorMotionProfile& profile) {
    MotionSynthesisResult result;
    if (!profile.valid) {
        result.errorCode = L"MOTION_PROFILE_INVALID";
        result.errorMessage = L"Operator motion profile is invalid.";
        return result;
    }

    result.profilePath = profile.profilePath;
    result.profileQuality = profile.quality;
    result.profileSource = profile.source;
    result.distancePx = Distance(from, to);

    if (result.distancePx <= 2) {
        result.durationMs = 0;
        result.points.push_back(to);
        result.ok = true;
        return result;
    }

    bool defaultTiming = requestedDurationMs <= 0;
    double duration = defaultTiming
        ? DefaultDurationForDistance(result.distancePx)
        : ClampDouble(static_cast<double>(requestedDurationMs), 0.0, 2000.0);
    result.durationMs = static_cast<int>(std::round(duration));

    int stepCount = ClampInt(static_cast<int>(std::round(duration / 16.0)), 2, 120);
    result.points.reserve(static_cast<size_t>(stepCount) + 1);

    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    if (screenW <= 0 || screenH <= 0) {
        screenW = 1920;
        screenH = 1080;
    }

    double dx = static_cast<double>(to.x - from.x);
    double dy = static_cast<double>(to.y - from.y);
    double len = (std::max)(1.0, std::sqrt(dx * dx + dy * dy));
    double nx = -dy / len;
    double ny = dx / len;
    double shapeScale = 0.0;
    if (len >= 120.0) {
        double shaped = ClampDouble((len - 120.0) / 280.0, 0.0, 1.0);
        shapeScale = shaped * shaped * (3.0 - 2.0 * shaped);
    }
    double curvature = ClampDouble(profile.curvaturePx, 0.0, 32.0) * shapeScale;
    double jitter = ClampDouble(profile.jitterPx, 0.0, 6.0) * shapeScale;
    double correctionWindow = ClampDouble(profile.endpointCorrectionPx / 20.0, 0.08, 0.22);

    for (int i = 0; i <= stepCount; ++i) {
        double t = static_cast<double>(i) / static_cast<double>(stepCount);
        double p = defaultTiming
            ? KinematicProgress(result.distancePx, duration, t)
            : CurveProgress(profile.velocityCurve, t);
        p = ClampDouble(p, 0.0, 1.0);

        double endpointBlend = t > (1.0 - correctionWindow)
            ? (t - (1.0 - correctionWindow)) / correctionWindow
            : 0.0;
        double curveEnvelope = std::sin(t * 3.14159265358979323846) * (1.0 - endpointBlend);
        double operatorWave = std::sin((t * 2.1 + 0.17) * 3.14159265358979323846) * curvature * curveEnvelope;
        double microJitter = std::sin((t * 37.0) + (len * 0.013)) * jitter * curveEnvelope;
        double offset = operatorWave + microJitter;

        int x = static_cast<int>(std::round(static_cast<double>(from.x) + dx * p + nx * offset));
        int y = static_cast<int>(std::round(static_cast<double>(from.y) + dy * p + ny * offset));
        x = ClampInt(x, 0, screenW - 1);
        y = ClampInt(y, 0, screenH - 1);
        result.points.push_back({x, y});
    }

    if (result.points.empty()) {
        result.errorCode = L"MOTION_PROFILE_INVALID";
        result.errorMessage = L"Operator motion synthesizer produced no points.";
        return result;
    }
    result.points.front() = from;
    result.points.back() = to;
    result.ok = true;
    return result;
}
