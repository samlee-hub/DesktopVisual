#include "MotionPacer.h"

#include "SimpleJson.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <numeric>
#include <sstream>
#include <vector>

namespace {

using TimeBeginPeriodFn = MMRESULT(WINAPI*)(UINT);
using TimeEndPeriodFn = MMRESULT(WINAPI*)(UINT);

double QpcMs(const LARGE_INTEGER& counter, const LARGE_INTEGER& frequency) {
    return (static_cast<double>(counter.QuadPart) * 1000.0) / static_cast<double>(frequency.QuadPart);
}

double NowMs(const LARGE_INTEGER& frequency) {
    LARGE_INTEGER now = {};
    QueryPerformanceCounter(&now);
    return QpcMs(now, frequency);
}

bool WaitUntilMs(double deadlineMs, const LARGE_INTEGER& frequency) {
    while (true) {
        double remaining = deadlineMs - NowMs(frequency);
        if (remaining <= 0.0) return true;
        if (remaining > 2.0) {
            Sleep(1);
        } else if (remaining > 0.35) {
            Sleep(0);
        } else {
            SwitchToThread();
        }
    }
}

std::wstring JsonDouble(double value, int precision = 2) {
    if (!std::isfinite(value)) return L"0";
    std::wstringstream stream;
    stream.setf(std::ios::fixed);
    stream.precision(precision);
    stream << value;
    return stream.str();
}

}  // namespace

MotionPacerSelfTestResult RunMotionPacerSelfTest(const MotionPacerSelfTestOptions& options) {
    MotionPacerSelfTestResult result;
    result.requestedHz = options.requestedHz;
    result.totalMoveDurationMs = options.durationMs;
    if (options.motionProfile != L"165hz-visible" && options.motionProfile != L"165hz") {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"motion profile must be 165hz-visible or 165hz.";
        return result;
    }
    if (options.requestedHz <= 0 || options.requestedHz > 500 || options.durationMs <= 0) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"requested Hz and duration must be positive.";
        return result;
    }

    HMODULE winmm = LoadLibraryW(L"winmm.dll");
    auto timeBegin = winmm ? reinterpret_cast<TimeBeginPeriodFn>(GetProcAddress(winmm, "timeBeginPeriod")) : nullptr;
    auto timeEnd = winmm ? reinterpret_cast<TimeEndPeriodFn>(GetProcAddress(winmm, "timeEndPeriod")) : nullptr;
    bool highRes = timeBegin && timeBegin(1) == TIMERR_NOERROR;
    result.highResolutionTimerEnabled = highRes;

    LARGE_INTEGER frequency = {};
    LARGE_INTEGER start = {};
    if (!QueryPerformanceFrequency(&frequency) || !QueryPerformanceCounter(&start) || frequency.QuadPart <= 0) {
        if (highRes && timeEnd) timeEnd(1);
        if (winmm) FreeLibrary(winmm);
        result.errorCode = L"BLOCKED_MOTION_165HZ_NOT_MET";
        result.errorMessage = L"QueryPerformanceCounter is unavailable.";
        return result;
    }

    const double frameMs = 1000.0 / static_cast<double>(options.requestedHz);
    int frames = static_cast<int>(std::ceil(static_cast<double>(options.durationMs) / frameMs)) + 1;
    if (frames < 2) frames = 2;
    std::vector<double> timestamps;
    timestamps.reserve(static_cast<size_t>(frames));
    double baseMs = QpcMs(start, frequency);
    for (int i = 0; i < frames; ++i) {
        if (i > 0) {
            WaitUntilMs(baseMs + (frameMs * static_cast<double>(i)), frequency);
        }
        LARGE_INTEGER frame = {};
        QueryPerformanceCounter(&frame);
        timestamps.push_back(QpcMs(frame, frequency) - baseMs);
    }

    if (highRes && timeEnd) timeEnd(1);
    if (winmm) FreeLibrary(winmm);

    std::vector<double> intervals;
    intervals.reserve(timestamps.size() - 1);
    for (size_t i = 1; i < timestamps.size(); ++i) {
        intervals.push_back(timestamps[i] - timestamps[i - 1]);
    }
    double total = std::accumulate(intervals.begin(), intervals.end(), 0.0);
    double avgInterval = intervals.empty() ? 0.0 : total / static_cast<double>(intervals.size());
    double maxInterval = intervals.empty() ? 0.0 : *std::max_element(intervals.begin(), intervals.end());
    result.measuredMaxIntervalMs = maxInterval;
    result.measuredAvgHz = avgInterval > 0.0 ? 1000.0 / avgInterval : 0.0;
    result.measuredMinHz = maxInterval > 0.0 ? 1000.0 / maxInterval : 0.0;
    result.frameCount = static_cast<int>(timestamps.size());
    result.ok = result.measuredAvgHz >= 150.0 && result.measuredMaxIntervalMs <= 12.0 && result.highResolutionTimerEnabled;
    if (!result.ok) {
        result.errorCode = L"BLOCKED_MOTION_165HZ_NOT_MET";
        result.errorMessage = L"Measured motion pacing did not satisfy 165Hz acceptance thresholds.";
    }
    return result;
}

std::wstring MotionPacerSelfTestJson(const MotionPacerSelfTestResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"requested_hz\":" + std::to_wstring(result.requestedHz);
    json += L",\"measured_avg_hz\":" + JsonDouble(result.measuredAvgHz, 2);
    json += L",\"measured_min_hz\":" + JsonDouble(result.measuredMinHz, 2);
    json += L",\"measured_max_interval_ms\":" + JsonDouble(result.measuredMaxIntervalMs, 3);
    json += L",\"total_move_duration_ms\":" + std::to_wstring(result.totalMoveDurationMs);
    json += L",\"high_resolution_timer_enabled\":" + simplejson::Bool(result.highResolutionTimerEnabled);
    json += L",\"frame_count\":" + std::to_wstring(result.frameCount);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L"}";
    return json;
}
