#include "MotionRecorder.h"

#include "MotionProfile.h"
#include "SafetyPolicy.h"
#include "Trace.h"
#include "UserAbortController.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct RecordedPoint {
    int x = 0;
    int y = 0;
    int clientX = 0;
    int clientY = 0;
    int timestampMs = 0;
    std::wstring buttonState;
};

std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) return "";
    int required = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (required <= 0) return "";
    std::string result(static_cast<size_t>(required - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), required, nullptr, nullptr);
    return result;
}

bool WriteUtf8File(const std::wstring& path, const std::wstring& content) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || !file) return false;
    std::string bytes = WideToUtf8(content);
    bool ok = bytes.empty() || fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size();
    fclose(file);
    return ok;
}

std::wstring ButtonState() {
    if (GetAsyncKeyState(VK_LBUTTON) & 0x8000) return L"left";
    if (GetAsyncKeyState(VK_RBUTTON) & 0x8000) return L"right";
    if (GetAsyncKeyState(VK_MBUTTON) & 0x8000) return L"middle";
    return L"none";
}

std::wstring SampleIdFor(const std::wstring& scenario) {
    SYSTEMTIME t = {};
    GetLocalTime(&t);
    wchar_t buffer[160] = {};
    swprintf_s(buffer, L"%ls_%04u%02u%02u_%02u%02u%02u_%03u",
        scenario.c_str(), t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    return buffer;
}

std::wstring BoundingBoxJson(const std::vector<RecordedPoint>& points) {
    if (points.empty()) return L"{\"left\":0,\"top\":0,\"right\":0,\"bottom\":0}";
    int left = points.front().x;
    int right = points.front().x;
    int top = points.front().y;
    int bottom = points.front().y;
    for (const auto& point : points) {
        left = (std::min)(left, point.x);
        right = (std::max)(right, point.x);
        top = (std::min)(top, point.y);
        bottom = (std::max)(bottom, point.y);
    }
    return L"{\"left\":" + std::to_wstring(left)
        + L",\"top\":" + std::to_wstring(top)
        + L",\"right\":" + std::to_wstring(right)
        + L",\"bottom\":" + std::to_wstring(bottom)
        + L"}";
}

int DistancePx(const std::vector<RecordedPoint>& points) {
    if (points.size() < 2) return 0;
    int dx = points.back().x - points.front().x;
    int dy = points.back().y - points.front().y;
    return static_cast<int>(std::round(std::sqrt(static_cast<double>(dx * dx + dy * dy))));
}

}  // namespace

MotionRecordResult RecordMouseMotion(
    const WindowInfo& target,
    const std::wstring& scenario,
    int durationMs,
    const std::wstring& outPath) {
    EnsureMotionProfileDirectories();
    MotionRecordResult result;
    if (scenario.empty() || durationMs <= 0 || durationMs > 60000 || outPath.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"motion-record requires scenario, positive duration-ms, and out path.";
        result.dataJson = L"{}";
        return result;
    }

    std::wstring normalizedOut;
    std::wstring safetyError;
    if (!IsWritePathAllowed(outPath, normalizedOut, safetyError)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.errorMessage = safetyError;
        result.dataJson = L"{\"out_path\":" + JsonString(outPath) + L"}";
        return result;
    }

    std::vector<RecordedPoint> points;
    ULONGLONG start = GetTickCount64();
    while (ElapsedMs(start) <= durationMs) {
        if (IsEmergencyStopPressed()) {
            result.errorCode = UserAbortStopCode();
            result.errorMessage = UserAbortMessage();
            result.dataJson = UserAbortEvidenceJson(L"\"scenario\":" + JsonString(scenario)
                + L",\"point_count\":" + std::to_wstring(points.size())
                + L",\"out_path\":" + JsonString(normalizedOut));
            return result;
        }
        POINT screen = {};
        if (GetCursorPos(&screen)) {
            POINT client = screen;
            ScreenToClient(target.hwnd, &client);
            RecordedPoint point;
            point.x = screen.x;
            point.y = screen.y;
            point.clientX = client.x;
            point.clientY = client.y;
            point.timestampMs = static_cast<int>(ElapsedMs(start));
            point.buttonState = ButtonState();
            points.push_back(point);
        }
        Sleep(10);
    }

    std::wstring sampleId = SampleIdFor(scenario);
    std::wstringstream json;
    json << L"{\n"
         << L"  \"version\": 1,\n"
         << L"  \"scenario\": " << JsonString(scenario) << L",\n"
         << L"  \"sample_id\": " << JsonString(sampleId) << L",\n"
         << L"  \"coordinate_space\": \"screen_and_client\",\n"
         << L"  \"captured_at\": " << JsonString(NowTimestamp()) << L",\n"
         << L"  \"title\": " << JsonString(target.title) << L",\n"
         << L"  \"points\": [\n";
    for (size_t i = 0; i < points.size(); ++i) {
        if (i != 0) json << L",\n";
        json << L"    {\"x\":" << points[i].x
             << L",\"y\":" << points[i].y
             << L",\"screen_x\":" << points[i].x
             << L",\"screen_y\":" << points[i].y
             << L",\"client_x\":" << points[i].clientX
             << L",\"client_y\":" << points[i].clientY
             << L",\"timestamp_ms\":" << points[i].timestampMs
             << L",\"button_state\":" << JsonString(points[i].buttonState)
             << L"}";
    }
    json << L"\n  ]\n}\n";

    if (!WriteUtf8File(normalizedOut, json.str())) {
        result.errorCode = L"UNKNOWN_ERROR";
        result.errorMessage = L"Could not write raw motion trajectory.";
        result.dataJson = L"{\"out_path\":" + JsonString(normalizedOut) + L"}";
        return result;
    }

    result.ok = true;
    result.dataJson = L"{\"scenario\":" + JsonString(scenario)
        + L",\"sample_id\":" + JsonString(sampleId)
        + L",\"point_count\":" + std::to_wstring(points.size())
        + L",\"duration_ms\":" + std::to_wstring(durationMs)
        + L",\"distance_px\":" + std::to_wstring(DistancePx(points))
        + L",\"bounding_box\":" + BoundingBoxJson(points)
        + L",\"out_path\":" + JsonString(normalizedOut)
        + L"}";
    return result;
}
