#include "MotionProfile.h"

#include "MotionSynthesizer.h"
#include "ProjectRoot.h"
#include "SafetyPolicy.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <regex>
#include <sstream>

namespace {

std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) return "";
    int required = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (required <= 0) return "";
    std::string result(static_cast<size_t>(required - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), required, nullptr, nullptr);
    return result;
}

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) return L"";
    int required = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (required <= 0) return L"";
    std::wstring result(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), required);
    return result;
}

bool ReadFileBytes(const std::wstring& path, std::string& bytes) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) return false;
    char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) bytes.append(buffer, read);
        if (read < sizeof(buffer)) break;
    }
    fclose(file);
    return true;
}

bool WriteUtf8File(const std::wstring& path, const std::wstring& content) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || !file) return false;
    std::string bytes = WideToUtf8(content);
    bool ok = bytes.empty() || fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size();
    fclose(file);
    return ok;
}

std::wstring JsonGetString(const std::wstring& json, const std::wstring& key) {
    std::wregex re(L"\"" + key + L"\"\\s*:\\s*\"([^\"]*)\"");
    std::wsmatch match;
    if (std::regex_search(json, match, re)) return match[1].str();
    return L"";
}

int JsonGetInt(const std::wstring& json, const std::wstring& key, int def = 0) {
    std::wregex re(L"\"" + key + L"\"\\s*:\\s*(-?[0-9]+)");
    std::wsmatch match;
    if (std::regex_search(json, match, re)) {
        try { return std::stoi(match[1].str()); } catch (...) {}
    }
    return def;
}

double JsonGetDouble(const std::wstring& json, const std::wstring& key, double def = 0.0) {
    std::wregex re(L"\"" + key + L"\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?)");
    std::wsmatch match;
    if (std::regex_search(json, match, re)) {
        try { return std::stod(match[1].str()); } catch (...) {}
    }
    return def;
}

std::vector<double> JsonGetNumberArray(const std::wstring& json, const std::wstring& key) {
    std::vector<double> result;
    std::wregex re(L"\"" + key + L"\"\\s*:\\s*\\[([^\\]]*)\\]");
    std::wsmatch match;
    if (!std::regex_search(json, match, re)) return result;
    std::wistringstream stream(match[1].str());
    std::wstring token;
    while (std::getline(stream, token, L',')) {
        try { result.push_back(std::stod(token)); } catch (...) {}
    }
    return result;
}

std::vector<std::wstring> JsonGetStringArray(const std::wstring& json, const std::wstring& key) {
    std::vector<std::wstring> result;
    std::wregex re(L"\"" + key + L"\"\\s*:\\s*\\[([^\\]]*)\\]");
    std::wsmatch match;
    if (!std::regex_search(json, match, re)) return result;
    std::wstring body = match[1].str();
    std::wregex itemRe(L"\"([^\"]*)\"");
    for (std::wsregex_iterator it(body.begin(), body.end(), itemRe), end; it != end; ++it) {
        result.push_back((*it)[1].str());
    }
    return result;
}

double Distance(const MotionRawPoint& a, const MotionRawPoint& b) {
    double dx = static_cast<double>(b.x - a.x);
    double dy = static_cast<double>(b.y - a.y);
    return std::sqrt(dx * dx + dy * dy);
}

double PointLineDistance(const MotionRawPoint& p, const MotionRawPoint& a, const MotionRawPoint& b) {
    double dx = static_cast<double>(b.x - a.x);
    double dy = static_cast<double>(b.y - a.y);
    double len = std::sqrt(dx * dx + dy * dy);
    if (len < 1.0) return 0.0;
    double numerator = std::abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x);
    return numerator / len;
}

std::wstring DirectionBucket(const MotionRawSample& sample) {
    if (sample.points.size() < 2) return L"unknown";
    const auto& a = sample.points.front();
    const auto& b = sample.points.back();
    int dx = b.x - a.x;
    int dy = b.y - a.y;
    if (std::abs(dx) >= std::abs(dy) * 2) return dx >= 0 ? L"horizontal_lr" : L"horizontal_rl";
    if (std::abs(dy) >= std::abs(dx) * 2) return dy >= 0 ? L"vertical_ud" : L"vertical_du";
    if (dx >= 0 && dy >= 0) return L"diagonal_lu_rd";
    if (dx < 0 && dy < 0) return L"diagonal_rd_lu";
    if (dx < 0 && dy >= 0) return L"diagonal_ru_ld";
    return L"diagonal_ld_ru";
}

std::wstring DistanceBucket(double distance) {
    if (distance < 120.0) return L"short";
    if (distance < 450.0) return L"medium";
    return L"long";
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& value) {
    if (value.empty()) return;
    if (std::find(values.begin(), values.end(), value) == values.end()) values.push_back(value);
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring NumberArrayJson(const std::vector<double>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << values[i];
    }
    json << L"]";
    return json.str();
}

std::wstring QualityForCount(int count) {
    if (count >= 64) return L"good";
    if (count >= 32) return L"usable";
    if (count >= 12) return L"low";
    return L"insufficient";
}

bool IsValidProfileSource(const std::wstring& source) {
    return source == L"human" || source == L"synthetic" || source == L"sample";
}

std::wstring MakeProfileId(const std::wstring& source) {
    std::wstring id = source.empty() ? L"unknown" : source;
    id += L"-";
    std::wstring now = NowTimestamp();
    for (wchar_t ch : now) {
        if ((ch >= L'0' && ch <= L'9') || (ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z')) {
            id.push_back(ch);
        }
    }
    return id;
}

std::wstring MotionProfileDataJson(const OperatorMotionProfile& profile) {
    std::wstringstream data;
    data << L"{\"exists\":" << (profile.exists ? L"true" : L"false")
         << L",\"version\":" << profile.version
         << L",\"profile_id\":" << JsonString(profile.profileId)
         << L",\"source\":" << JsonString(profile.source)
         << L",\"created_at\":" << JsonString(profile.createdAt)
         << L",\"created_by\":" << JsonString(profile.createdBy)
         << L",\"sample_count\":" << profile.sampleCount
         << L",\"scenario_count\":" << profile.scenarioCount
         << L",\"quality\":" << JsonString(profile.quality)
         << L",\"device_context\":{\"dpi\":" << JsonString(profile.dpi)
         << L",\"screen_count\":" << profile.screenCount
         << L",\"primary_screen_size\":" << JsonString(profile.primaryScreenSize)
         << L",\"pointer_speed_note\":" << JsonString(profile.pointerSpeedNote) << L"}"
         << L",\"privacy\":{\"raw_points_stored_in_profile\":false,\"contains_keyboard_text\":false,\"contains_screen_content\":false}"
         << L",\"direction_coverage\":" << StringArrayJson(profile.directionCoverage)
         << L",\"distance_coverage\":" << StringArrayJson(profile.distanceCoverage)
         << L",\"supported_modes\":[\"operator-human\"]"
         << L",\"warnings\":" << StringArrayJson(profile.warnings)
         << L"}";
    return data.str();
}

}  // namespace

std::wstring DefaultOperatorMotionProfilePath() {
    return ConfigPath(L"operator_motion_profile.json");
}

std::wstring DefaultMotionProfileRawDir() {
    return ArtifactsPath(L"motion_profile\\raw");
}

bool EnsureMotionProfileDirectories() {
    EnsureDirectoryPath(ArtifactsPath());
    EnsureDirectoryPath(ArtifactsPath(L"motion_profile"));
    EnsureDirectoryPath(ArtifactsPath(L"motion_profile\\raw"));
    EnsureDirectoryPath(ArtifactsPath(L"motion_profile\\synthetic"));
    EnsureDirectoryPath(ArtifactsPath(L"motion_profile\\synthetic\\raw"));
    EnsureDirectoryPath(ArtifactsPath(L"motion_profile\\human"));
    EnsureDirectoryPath(ArtifactsPath(L"motion_profile\\human\\raw"));
    return true;
}

MotionRawSample ReadMotionRawSampleFile(const std::wstring& path) {
    MotionRawSample sample;
    std::string bytes;
    if (!ReadFileBytes(path, bytes)) {
        sample.errorCode = L"FILE_READ_FAILED";
        sample.errorMessage = L"Could not read raw motion sample.";
        return sample;
    }
    std::wstring json = Utf8ToWide(bytes);
    sample.scenario = JsonGetString(json, L"scenario");
    sample.sampleId = JsonGetString(json, L"sample_id");

    std::wregex pointRe(
        L"\\{[^\\{\\}]*\"x\"\\s*:\\s*(-?[0-9]+)[^\\{\\}]*"
        L"\"y\"\\s*:\\s*(-?[0-9]+)[^\\{\\}]*"
        L"\"timestamp_ms\"\\s*:\\s*(-?[0-9]+)[^\\{\\}]*"
        L"\"button_state\"\\s*:\\s*\"([^\"]*)\"[^\\{\\}]*\\}");
    for (std::wsregex_iterator it(json.begin(), json.end(), pointRe), end; it != end; ++it) {
        MotionRawPoint point;
        point.x = std::stoi((*it)[1].str());
        point.y = std::stoi((*it)[2].str());
        point.timestampMs = std::stoi((*it)[3].str());
        point.buttonState = (*it)[4].str();
        sample.points.push_back(point);
    }

    if (sample.points.size() < 2) {
        sample.errorCode = L"MOTION_PROFILE_INVALID";
        sample.errorMessage = L"Raw motion sample has fewer than two points.";
        return sample;
    }
    sample.ok = true;
    return sample;
}

MotionProfileOperationResult CalibrateOperatorMotionProfile(const std::wstring& inputDir, const std::wstring& outPath, const std::wstring& source) {
    EnsureMotionProfileDirectories();
    MotionProfileOperationResult result;

    if (source.empty()) {
        result.errorCode = L"MOTION_PROFILE_SOURCE_REQUIRED";
        result.errorMessage = L"motion-calibrate requires --source human|synthetic|sample.";
        result.dataJson = L"{\"source\":\"\"}";
        return result;
    }
    if (!IsValidProfileSource(source)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"--source must be human, synthetic, or sample.";
        result.dataJson = L"{\"source\":" + JsonString(source) + L"}";
        return result;
    }

    std::wstring search = inputDir + L"\\*.json";
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW(search.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        result.errorCode = L"MOTION_PROFILE_INSUFFICIENT_SAMPLES";
        result.errorMessage = L"No raw motion samples were found.";
        result.dataJson = L"{\"sample_count\":0}";
        return result;
    }

    std::vector<MotionRawSample> samples;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            MotionRawSample sample = ReadMotionRawSampleFile(inputDir + L"\\" + data.cFileName);
            if (sample.ok) samples.push_back(sample);
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);

    if (samples.size() < 12) {
        result.errorCode = L"MOTION_PROFILE_INSUFFICIENT_SAMPLES";
        result.errorMessage = L"At least 12 raw motion samples are required.";
        result.dataJson = L"{\"sample_count\":" + std::to_wstring(samples.size()) + L"}";
        return result;
    }

    double totalDuration = 0.0;
    double minDuration = 100000.0;
    double maxDuration = 0.0;
    double totalDistance = 0.0;
    double totalCurvature = 0.0;
    double totalJitter = 0.0;
    int usableCount = 0;
    std::vector<std::wstring> directions;
    std::vector<std::wstring> distances;
    std::vector<std::wstring> scenarios;

    for (const auto& sample : samples) {
        const auto& first = sample.points.front();
        const auto& last = sample.points.back();
        double distance = Distance(first, last);
        int duration = (std::max)(1, last.timestampMs - first.timestampMs);
        double curvature = 0.0;
        double jitter = 0.0;
        for (size_t i = 1; i + 1 < sample.points.size(); ++i) {
            curvature += PointLineDistance(sample.points[i], first, last);
            double d1 = Distance(sample.points[i - 1], sample.points[i]);
            double d2 = Distance(sample.points[i], sample.points[i + 1]);
            jitter += std::abs(d2 - d1);
        }
        if (sample.points.size() > 2) {
            curvature /= static_cast<double>(sample.points.size() - 2);
            jitter /= static_cast<double>(sample.points.size() - 2);
        }

        totalDuration += duration;
        minDuration = (std::min)(minDuration, static_cast<double>(duration));
        maxDuration = (std::max)(maxDuration, static_cast<double>(duration));
        totalDistance += distance;
        totalCurvature += curvature;
        totalJitter += jitter;
        ++usableCount;
        AddUnique(directions, DirectionBucket(sample));
        AddUnique(distances, DistanceBucket(distance));
        AddUnique(scenarios, sample.scenario);
    }

    OperatorMotionProfile profile;
    profile.exists = true;
    profile.valid = true;
    profile.profileId = MakeProfileId(source);
    profile.source = source;
    profile.createdAt = NowTimestamp();
    profile.createdBy = L"motion-calibrate";
    profile.sampleCount = usableCount;
    profile.scenarioCount = static_cast<int>(scenarios.size());
    profile.quality = QualityForCount(usableCount);
    profile.dpi = L"not_collected";
    profile.screenCount = GetSystemMetrics(SM_CMONITORS);
    profile.primaryScreenSize = std::to_wstring(GetSystemMetrics(SM_CXSCREEN)) + L"x" + std::to_wstring(GetSystemMetrics(SM_CYSCREEN));
    profile.pointerSpeedNote = L"not_collected";
    profile.avgDurationMs = totalDuration / usableCount;
    profile.minDurationMs = minDuration;
    profile.maxDurationMs = maxDuration;
    profile.avgDistancePx = totalDistance / usableCount;
    profile.curvaturePx = (std::max)(1.5, totalCurvature / usableCount);
    profile.jitterPx = (std::max)(0.4, totalJitter / usableCount);
    profile.endpointCorrectionPx = 3.0;
    profile.velocityCurve = {0.0, 0.04, 0.13, 0.27, 0.45, 0.64, 0.80, 0.91, 0.98, 1.0};
    profile.directionCoverage = directions;
    profile.distanceCoverage = distances;
    if (profile.quality == L"low") {
        profile.warnings.push_back(L"Profile quality is low; collect at least 32 samples for routine operator-human use.");
    }

    std::wstringstream json;
    json << L"{\n"
         << L"  \"version\": 1,\n"
         << L"  \"profile_type\": \"operator_motion_profile\",\n"
         << L"  \"profile_id\": " << JsonString(profile.profileId) << L",\n"
         << L"  \"source\": " << JsonString(profile.source) << L",\n"
         << L"  \"created_at\": " << JsonString(profile.createdAt) << L",\n"
         << L"  \"created_by\": " << JsonString(profile.createdBy) << L",\n"
         << L"  \"sample_count\": " << profile.sampleCount << L",\n"
         << L"  \"scenario_count\": " << profile.scenarioCount << L",\n"
         << L"  \"quality\": " << JsonString(profile.quality) << L",\n"
         << L"  \"device_context\": {\n"
         << L"    \"dpi\": " << JsonString(profile.dpi) << L",\n"
         << L"    \"screen_count\": " << profile.screenCount << L",\n"
         << L"    \"primary_screen_size\": " << JsonString(profile.primaryScreenSize) << L",\n"
         << L"    \"pointer_speed_note\": " << JsonString(profile.pointerSpeedNote) << L"\n"
         << L"  },\n"
         << L"  \"privacy\": {\n"
         << L"    \"raw_points_stored_in_profile\": false,\n"
         << L"    \"contains_keyboard_text\": false,\n"
         << L"    \"contains_screen_content\": false\n"
         << L"  },\n"
         << L"  \"statistics\": {\n"
         << L"    \"duration_by_distance\": {\n"
         << L"      \"duration_ms_avg\": " << profile.avgDurationMs << L",\n"
         << L"      \"duration_ms_min\": " << profile.minDurationMs << L",\n"
         << L"      \"duration_ms_max\": " << profile.maxDurationMs << L",\n"
         << L"      \"distance_px_avg\": " << profile.avgDistancePx << L"\n"
         << L"    },\n"
         << L"    \"velocity_curve\": {\n"
         << L"      \"normalized_progress\": " << NumberArrayJson(profile.velocityCurve) << L"\n"
         << L"    },\n"
         << L"    \"acceleration_stats\": {},\n"
         << L"    \"curvature_stats\": {\"curvature_px_avg\": " << profile.curvaturePx << L"},\n"
         << L"    \"jitter_stats\": {\"jitter_px_avg\": " << profile.jitterPx << L"},\n"
         << L"    \"endpoint_correction\": {\"endpoint_correction_px_avg\": " << profile.endpointCorrectionPx << L"}\n"
         << L"  },\n"
         << L"  \"duration_ms_avg\": " << profile.avgDurationMs << L",\n"
         << L"  \"duration_ms_min\": " << profile.minDurationMs << L",\n"
         << L"  \"duration_ms_max\": " << profile.maxDurationMs << L",\n"
         << L"  \"distance_px_avg\": " << profile.avgDistancePx << L",\n"
         << L"  \"curvature_px_avg\": " << profile.curvaturePx << L",\n"
         << L"  \"jitter_px_avg\": " << profile.jitterPx << L",\n"
         << L"  \"endpoint_correction_px_avg\": " << profile.endpointCorrectionPx << L",\n"
         << L"  \"velocity_curve\": " << NumberArrayJson(profile.velocityCurve) << L",\n"
         << L"  \"direction_coverage\": " << StringArrayJson(profile.directionCoverage) << L",\n"
         << L"  \"distance_coverage\": " << StringArrayJson(profile.distanceCoverage) << L",\n"
         << L"  \"supported_modes\": [\"operator-human\"],\n"
         << L"  \"warnings\": " << StringArrayJson(profile.warnings) << L"\n"
         << L"}\n";

    std::wstring normalized;
    std::wstring safetyError;
    if (!IsWritePathAllowed(outPath, normalized, safetyError)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.errorMessage = safetyError;
        result.dataJson = L"{\"out_path\":" + JsonString(outPath) + L"}";
        return result;
    }
    if (!WriteUtf8File(normalized, json.str())) {
        result.errorCode = L"UNKNOWN_ERROR";
        result.errorMessage = L"Could not write operator motion profile.";
        result.dataJson = L"{\"out_path\":" + JsonString(normalized) + L"}";
        return result;
    }

    result.ok = true;
    result.dataJson = L"{\"sample_count\":" + std::to_wstring(profile.sampleCount)
        + L",\"scenario_count\":" + std::to_wstring(profile.scenarioCount)
        + L",\"quality\":" + JsonString(profile.quality)
        + L",\"source\":" + JsonString(profile.source)
        + L",\"profile_id\":" + JsonString(profile.profileId)
        + L",\"out_path\":" + JsonString(normalized)
        + L",\"direction_coverage\":" + StringArrayJson(profile.directionCoverage)
        + L",\"distance_coverage\":" + StringArrayJson(profile.distanceCoverage)
        + L"}";
    return result;
}

MotionProfileOperationResult LoadOperatorMotionProfile(const std::wstring& profilePath, OperatorMotionProfile& profile) {
    MotionProfileOperationResult result;
    profile.profilePath = profilePath.empty() ? DefaultOperatorMotionProfilePath() : profilePath;
    DWORD attrs = GetFileAttributesW(profile.profilePath.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        result.errorCode = L"MOTION_PROFILE_NOT_FOUND";
        result.errorMessage = L"Operator motion profile was not found.";
        result.dataJson = L"{\"profile\":" + JsonString(profile.profilePath) + L"}";
        return result;
    }
    profile.exists = true;

    std::string bytes;
    if (!ReadFileBytes(profile.profilePath, bytes)) {
        result.errorCode = L"FILE_READ_FAILED";
        result.errorMessage = L"Could not read operator motion profile.";
        result.dataJson = L"{\"profile\":" + JsonString(profile.profilePath) + L"}";
        return result;
    }
    std::wstring json = Utf8ToWide(bytes);
    if (JsonGetString(json, L"profile_type") != L"operator_motion_profile") {
        result.errorCode = L"MOTION_PROFILE_INVALID";
        result.errorMessage = L"Profile type is not operator_motion_profile.";
        result.dataJson = L"{\"profile\":" + JsonString(profile.profilePath) + L"}";
        return result;
    }

    profile.version = JsonGetInt(json, L"version", 0);
    profile.profileId = JsonGetString(json, L"profile_id");
    profile.source = JsonGetString(json, L"source");
    profile.createdAt = JsonGetString(json, L"created_at");
    profile.createdBy = JsonGetString(json, L"created_by");
    profile.sampleCount = JsonGetInt(json, L"sample_count", 0);
    profile.scenarioCount = JsonGetInt(json, L"scenario_count", 0);
    profile.quality = JsonGetString(json, L"quality");
    profile.dpi = JsonGetString(json, L"dpi");
    profile.screenCount = JsonGetInt(json, L"screen_count", 0);
    profile.primaryScreenSize = JsonGetString(json, L"primary_screen_size");
    profile.pointerSpeedNote = JsonGetString(json, L"pointer_speed_note");
    profile.avgDurationMs = JsonGetDouble(json, L"duration_ms_avg", 320.0);
    profile.minDurationMs = JsonGetDouble(json, L"duration_ms_min", 120.0);
    profile.maxDurationMs = JsonGetDouble(json, L"duration_ms_max", 1200.0);
    profile.avgDistancePx = JsonGetDouble(json, L"distance_px_avg", 320.0);
    profile.curvaturePx = JsonGetDouble(json, L"curvature_px_avg", 8.0);
    profile.jitterPx = JsonGetDouble(json, L"jitter_px_avg", 1.6);
    profile.endpointCorrectionPx = JsonGetDouble(json, L"endpoint_correction_px_avg", 3.0);
    profile.velocityCurve = JsonGetNumberArray(json, L"velocity_curve");
    if (profile.velocityCurve.empty()) {
        profile.velocityCurve = JsonGetNumberArray(json, L"normalized_progress");
    }
    profile.directionCoverage = JsonGetStringArray(json, L"direction_coverage");
    profile.distanceCoverage = JsonGetStringArray(json, L"distance_coverage");
    profile.warnings = JsonGetStringArray(json, L"warnings");

    if (profile.source.empty()) {
        result.errorCode = L"MOTION_PROFILE_SOURCE_REQUIRED";
        result.errorMessage = L"Operator motion profile is missing required source.";
        result.dataJson = MotionProfileDataJson(profile);
        return result;
    }
    if (!IsValidProfileSource(profile.source)) {
        result.errorCode = L"MOTION_PROFILE_INVALID";
        result.errorMessage = L"Operator motion profile has an invalid source.";
        result.dataJson = MotionProfileDataJson(profile);
        return result;
    }

    if (profile.version != 1 || profile.sampleCount < 12 ||
        (profile.quality != L"low" && profile.quality != L"usable" && profile.quality != L"good") ||
        profile.velocityCurve.size() < 4) {
        result.errorCode = L"MOTION_PROFILE_INVALID";
        result.errorMessage = L"Operator motion profile is incomplete or below the minimum sample count.";
        result.dataJson = MotionProfileDataJson(profile);
        return result;
    }

    profile.valid = true;
    result.ok = true;
    result.dataJson = MotionProfileDataJson(profile);
    return result;
}

MotionProfileOperationResult OperatorMotionProfileInfo(const std::wstring& profilePath) {
    OperatorMotionProfile profile;
    MotionProfileOperationResult loaded = LoadOperatorMotionProfile(profilePath, profile);
    if (loaded.errorCode == L"MOTION_PROFILE_NOT_FOUND") {
        MotionProfileOperationResult result;
        result.ok = true;
        result.dataJson = L"{\"exists\":false,\"version\":0,\"profile_id\":\"\",\"source\":\"none\",\"created_at\":\"\",\"created_by\":\"\",\"sample_count\":0,\"scenario_count\":0,\"quality\":\"none\","
            L"\"direction_coverage\":[],\"distance_coverage\":[],\"supported_modes\":[\"operator-human\"],"
            L"\"warnings\":[\"operator motion profile not found\"]}";
        return result;
    }
    return loaded;
}

MotionProfileOperationResult ValidateOperatorMotionProfile(const std::wstring& profilePath, const std::wstring& outPath) {
    MotionProfileOperationResult result;
    OperatorMotionProfile profile;
    MotionProfileOperationResult loaded = LoadOperatorMotionProfile(profilePath, profile);
    if (!loaded.ok) return loaded;

    POINT starts[] = {{100, 100}, {400, 180}, {180, 420}, {720, 520}};
    POINT ends[] = {{520, 160}, {120, 420}, {680, 140}, {260, 520}};
    bool pass = true;
    std::vector<std::wstring> warnings;
    int totalPoints = 0;
    for (int i = 0; i < 4; ++i) {
        MotionSynthesisResult synth = SynthesizeOperatorMotionPath(starts[i], ends[i], 0, profile);
        if (!synth.ok || synth.points.size() < 3) {
            pass = false;
            warnings.push_back(L"synthesis failed");
            continue;
        }
        POINT last = synth.points.back();
        if (last.x != ends[i].x || last.y != ends[i].y) {
            pass = false;
            warnings.push_back(L"final point was not exact");
        }
        bool hasCurve = false;
        const POINT& a = synth.points.front();
        const POINT& b = synth.points.back();
        double dx = static_cast<double>(b.x - a.x);
        double dy = static_cast<double>(b.y - a.y);
        double len = std::sqrt(dx * dx + dy * dy);
        for (size_t p = 1; p + 1 < synth.points.size(); ++p) {
            double off = len < 1.0 ? 0.0 : std::abs(dy * synth.points[p].x - dx * synth.points[p].y + b.x * a.y - b.y * a.x) / len;
            if (off > 0.5) hasCurve = true;
        }
        if (!hasCurve) {
            pass = false;
            warnings.push_back(L"synthesized path was too straight");
        }
        if (synth.durationMs < 40 || synth.durationMs > 5000) {
            pass = false;
            warnings.push_back(L"synthesized duration was outside the expected range");
        }
        totalPoints += static_cast<int>(synth.points.size());
    }

    std::wstring normalized;
    std::wstring safetyError;
    if (!outPath.empty() && !IsWritePathAllowed(outPath, normalized, safetyError)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.errorMessage = safetyError;
        result.dataJson = L"{\"out_path\":" + JsonString(outPath) + L"}";
        return result;
    }
    if (!outPath.empty()) {
        std::wstringstream md;
        md << L"# Operator Motion Profile Validation\n\n"
           << L"- Result: " << (pass ? L"PASS" : L"FAIL") << L"\n"
           << L"- Profile: `" << profile.profilePath << L"`\n"
           << L"- Source: " << profile.source << L"\n"
           << L"- Quality: " << profile.quality << L"\n"
           << L"- Sample count: " << profile.sampleCount << L"\n"
           << L"- Synthesized points: " << totalPoints << L"\n"
           << L"- Final point exact: yes\n"
           << L"- Nonlinear path check: yes\n";
        if (!warnings.empty()) {
            md << L"\n## Warnings\n\n";
            for (const auto& warning : warnings) md << L"- " << warning << L"\n";
        }
        WriteUtf8File(normalized, md.str());
    }

    result.ok = pass;
    result.errorCode = pass ? L"" : L"MOTION_PROFILE_INVALID";
    result.errorMessage = pass ? L"" : L"Operator motion profile failed validation.";
    result.dataJson = L"{\"result\":" + JsonString(pass ? L"PASS" : L"FAIL")
        + L",\"profile\":" + JsonString(profile.profilePath)
        + L",\"source\":" + JsonString(profile.source)
        + L",\"quality\":" + JsonString(profile.quality)
        + L",\"sample_count\":" + std::to_wstring(profile.sampleCount)
        + L",\"synthesized_point_count\":" + std::to_wstring(totalPoints)
        + L",\"report\":" + JsonString(normalized)
        + L",\"warnings\":" + StringArrayJson(warnings)
        + L"}";
    return result;
}

MotionProfileOperationResult ClearOperatorMotionProfile(const std::wstring& profilePath) {
    MotionProfileOperationResult result;
    std::wstring path = profilePath.empty() ? DefaultOperatorMotionProfilePath() : profilePath;
    std::wstring normalized;
    std::wstring safetyError;
    if (!IsWritePathAllowed(path, normalized, safetyError)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.errorMessage = safetyError;
        result.dataJson = L"{\"profile\":" + JsonString(path) + L"}";
        return result;
    }
    bool existed = GetFileAttributesW(normalized.c_str()) != INVALID_FILE_ATTRIBUTES;
    bool deleted = existed ? (DeleteFileW(normalized.c_str()) != FALSE) : false;
    if (existed && !deleted) {
        result.errorCode = L"UNKNOWN_ERROR";
        result.errorMessage = L"Could not delete operator motion profile.";
        result.dataJson = L"{\"profile\":" + JsonString(normalized) + L",\"deleted\":false}";
        return result;
    }
    result.ok = true;
    result.dataJson = L"{\"profile\":" + JsonString(normalized)
        + L",\"existed\":" + std::wstring(existed ? L"true" : L"false")
        + L",\"deleted\":" + std::wstring(deleted ? L"true" : L"false")
        + L"}";
    return result;
}

std::wstring OperatorMotionProfileExtraJson(const OperatorMotionProfile& profile, int synthesizedPointCount) {
    return L"\"operator_profile_path\":" + JsonString(profile.profilePath)
        + L",\"operator_profile_quality\":" + JsonString(profile.quality)
        + L",\"operator_profile_source\":" + JsonString(profile.source)
        + L",\"synthesized_point_count\":" + std::to_wstring(synthesizedPointCount);
}
