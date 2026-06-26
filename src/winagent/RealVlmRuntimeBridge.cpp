#include "RealVlmRuntimeBridge.h"

#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "VLMObservationContract.h"

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cwctype>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>

namespace {

const wchar_t* kBridgeDesktopVisualVersion = L"1.0.5";
const wchar_t* kCapabilityAvailable = L"VLM_AVAILABLE";
const wchar_t* kCapabilityUnavailable = L"VLM_UNAVAILABLE";
const wchar_t* kCapabilityUnknown = L"VLM_UNKNOWN";
const wchar_t* kCapabilityTimeout = L"VLM_TIMEOUT";
const wchar_t* kCapabilityInvalidResponse = L"VLM_INVALID_RESPONSE";
const wchar_t* kCapabilityCandidateRejected = L"VLM_CANDIDATE_REJECTED";

struct CapabilityProbeArgs {
    std::wstring provider = L"codex-cli";
    std::wstring sessionId;
    std::wstring probeImage;
    int timeoutMs = 60000;
    bool cache = true;
    long long ttlSeconds = 24LL * 60LL * 60LL;
    std::wstring simulation;
};

struct ProviderProbeResult {
    bool wrapperOk = false;
    std::wstring wrapperJson;
    std::wstring provider;
    std::wstring status = kCapabilityUnknown;
    std::wstring codexCliVersion;
    bool imageInputSupported = false;
    std::wstring rawOutputPath;
    std::wstring reason;
    int exitCode = 0;
};

struct CapabilityCacheEntry {
    bool valid = false;
    std::wstring sessionId;
    std::wstring provider;
    std::wstring providerCommand;
    std::wstring codexCliVersion;
    std::wstring capabilityStatus = kCapabilityUnknown;
    std::wstring checkedAt;
    bool imageInputSupported = false;
    std::wstring probeImagePath;
    std::wstring rawProbeOutputPath;
    std::wstring reason;
    std::wstring ttlOrExpiration;
    long long expiresAtUnix = 0;
    std::wstring desktopVisualVersion;
    std::wstring cachePath;
};

struct CapabilityResolution {
    CapabilityCacheEntry entry;
    bool cacheHit = false;
    std::wstring cachePath;
    bool cacheWriteOk = true;
    std::wstring cacheWriteError;
};

struct AssistLocateArgs {
    std::wstring provider = L"codex-cli";
    std::wstring sessionId;
    std::wstring imagePath;
    std::wstring target;
    std::wstring targetWindowTitle;
    int timeoutMs = 60000;
    double minConfidence = 0.65;
    bool cache = true;
    std::wstring simulation;
    std::wstring capabilitySimulation;
    std::wstring screenshotId;
    std::wstring frameId;
};

struct ImageDimensions {
    bool ok = false;
    int width = 0;
    int height = 0;
    std::wstring error;
};

struct VlmCandidate {
    bool schemaValid = false;
    bool ok = false;
    bool targetFound = false;
    std::wstring targetLabel;
    std::wstring targetType;
    double confidence = 0.0;
    int bboxX = 0;
    int bboxY = 0;
    int bboxW = 0;
    int bboxH = 0;
    int pointX = 0;
    int pointY = 0;
    std::wstring coordinateSpace;
    int imageWidth = 0;
    int imageHeight = 0;
    std::wstring reason;
    std::vector<std::wstring> visibleText;
    std::wstring uncertainty;
    std::vector<std::wstring> safetyFlags;
    bool requiresHumanReview = false;
};

struct CandidateValidationResult {
    bool accepted = false;
    std::wstring rejectedReason;
    VlmCandidate candidate;
};

struct ProviderLocateResult {
    bool wrapperOk = false;
    std::wstring wrapperJson;
    std::wstring provider;
    std::wstring status = kCapabilityUnknown;
    std::wstring codexCliVersion;
    bool imageInputSupported = false;
    std::wstring rawOutputPath;
    std::wstring parsedJsonPath;
    std::wstring reason;
    int exitCode = 0;
};

struct CandidateValidateArgs {
    std::wstring candidateJsonPath;
    std::wstring imagePath;
    std::wstring target;
    std::wstring targetWindowTitle;
    double minConfidence = 0.65;
};

struct CandidateEvidenceBinding {
    std::wstring screenshotId;
    std::wstring frameId;
    std::wstring imagePath;
    std::wstring provider;
    std::wstring sessionId;
    std::wstring promptHash;
    std::wstring rawResponsePath;
    std::wstring parsedJsonPath;
    std::wstring requestedTarget;
};

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool ParseBoolArg(int argc, wchar_t** argv, const std::wstring& name, bool& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    std::wstring lower = raw;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    if (lower == L"true" || lower == L"1" || lower == L"yes") {
        value = true;
        return true;
    }
    if (lower == L"false" || lower == L"0" || lower == L"no") {
        value = false;
        return true;
    }
    error = name + L" must be true or false.";
    return false;
}

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) {
            error = name + L" must be an integer.";
            return false;
        }
        value = parsed;
        return true;
    } catch (...) {
        error = name + L" must be an integer.";
        return false;
    }
}

bool ParseInt64Arg(int argc, wchar_t** argv, const std::wstring& name, long long& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    try {
        size_t consumed = 0;
        long long parsed = std::stoll(raw, &consumed, 10);
        if (consumed != raw.size()) {
            error = name + L" must be an integer.";
            return false;
        }
        value = parsed;
        return true;
    } catch (...) {
        error = name + L" must be an integer.";
        return false;
    }
}

bool ParseDoubleArg(int argc, wchar_t** argv, const std::wstring& name, double& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    try {
        size_t consumed = 0;
        double parsed = std::stod(raw, &consumed);
        if (consumed != raw.size()) {
            error = name + L" must be a number.";
            return false;
        }
        value = parsed;
        return true;
    } catch (...) {
        error = name + L" must be a number.";
        return false;
    }
}

bool JsonNumber(const simplejson::Value& object, const std::wstring& key, double& value) {
    const simplejson::Value* found = simplejson::Find(object, key);
    if (!found || !found->IsNumber()) return false;
    value = found->numberValue;
    return true;
}

int JsonIntRounded(const simplejson::Value& object, const std::wstring& key, int def = 0) {
    double value = 0.0;
    if (!JsonNumber(object, key, value)) return def;
    return static_cast<int>(std::lround(value));
}

bool FileExists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool ReadBinaryPrefix(const std::wstring& path, std::vector<unsigned char>& bytes, size_t maxBytes) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    bytes.assign(maxBytes, 0);
    DWORD read = 0;
    BOOL ok = ReadFile(file, bytes.data(), static_cast<DWORD>(maxBytes), &read, nullptr);
    CloseHandle(file);
    if (!ok) return false;
    bytes.resize(read);
    return true;
}

int ReadBigEndian32(const std::vector<unsigned char>& bytes, size_t offset) {
    if (offset + 4 > bytes.size()) return 0;
    return (static_cast<int>(bytes[offset]) << 24) |
           (static_cast<int>(bytes[offset + 1]) << 16) |
           (static_cast<int>(bytes[offset + 2]) << 8) |
           static_cast<int>(bytes[offset + 3]);
}

int ReadLittleEndian32(const std::vector<unsigned char>& bytes, size_t offset) {
    if (offset + 4 > bytes.size()) return 0;
    return static_cast<int>(bytes[offset]) |
           (static_cast<int>(bytes[offset + 1]) << 8) |
           (static_cast<int>(bytes[offset + 2]) << 16) |
           (static_cast<int>(bytes[offset + 3]) << 24);
}

ImageDimensions ReadImageDimensions(const std::wstring& path) {
    ImageDimensions result;
    if (!FileExists(path)) {
        result.error = L"image_path_not_found";
        return result;
    }
    std::vector<unsigned char> bytes;
    if (!ReadBinaryPrefix(path, bytes, 64)) {
        result.error = L"image_read_failed";
        return result;
    }
    const unsigned char pngSig[8] = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
    if (bytes.size() >= 24 && std::equal(std::begin(pngSig), std::end(pngSig), bytes.begin())) {
        result.width = ReadBigEndian32(bytes, 16);
        result.height = ReadBigEndian32(bytes, 20);
        result.ok = result.width > 0 && result.height > 0;
        if (!result.ok) result.error = L"png_dimensions_invalid";
        return result;
    }
    if (bytes.size() >= 26 && bytes[0] == 'B' && bytes[1] == 'M') {
        result.width = ReadLittleEndian32(bytes, 18);
        result.height = std::abs(ReadLittleEndian32(bytes, 22));
        result.ok = result.width > 0 && result.height > 0;
        if (!result.ok) result.error = L"bmp_dimensions_invalid";
        return result;
    }
    result.error = L"image_format_dimensions_unsupported";
    return result;
}

std::wstring QuoteCommandArg(const std::wstring& value) {
    std::wstring quoted = L"\"";
    for (wchar_t ch : value) {
        if (ch == L'"') continue;
        quoted.push_back(ch);
    }
    quoted.push_back(L'"');
    return quoted;
}

std::wstring ExtractFirstJsonObject(const std::wstring& text) {
    bool inString = false;
    bool escaped = false;
    int depth = 0;
    size_t start = std::wstring::npos;
    for (size_t i = 0; i < text.size(); ++i) {
        wchar_t ch = text[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                inString = false;
            }
            continue;
        }
        if (ch == L'"') {
            inString = true;
            continue;
        }
        if (ch == L'{') {
            if (depth == 0) start = i;
            ++depth;
        } else if (ch == L'}') {
            if (depth > 0) {
                --depth;
                if (depth == 0 && start != std::wstring::npos) {
                    return text.substr(start, i - start + 1);
                }
            }
        }
    }
    return L"";
}

std::wstring Trim(std::wstring value) {
    while (!value.empty() && (value.back() == L'\r' || value.back() == L'\n' || value.back() == L' ' || value.back() == L'\t')) {
        value.pop_back();
    }
    size_t first = 0;
    while (first < value.size() && (value[first] == L'\r' || value[first] == L'\n' || value[first] == L' ' || value[first] == L'\t' || value[first] == 0xfeff)) {
        ++first;
    }
    return value.substr(first);
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

std::wstring RunCommandCapture(const std::wstring& command) {
    FILE* pipe = _wpopen(command.c_str(), L"rt");
    if (!pipe) return L"";
    std::wstring output;
    wchar_t buffer[1024] = {};
    while (fgetws(buffer, static_cast<int>(std::size(buffer)), pipe)) {
        output += buffer;
    }
    _pclose(pipe);
    return output;
}

long long UnixNow() {
    return std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

unsigned long long DurationMsSince(ULONGLONG startTick) {
    if (startTick == 0) return 0;
    ULONGLONG now = GetTickCount64();
    if (now < startTick) return 0;
    return static_cast<unsigned long long>(now - startTick);
}

std::wstring TimestampForPath() {
    SYSTEMTIME t;
    GetLocalTime(&t);
    wchar_t buffer[32] = {};
    swprintf_s(buffer, L"%04u%02u%02u_%02u%02u%02u", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
    return buffer;
}

std::wstring HexHash(const std::wstring& text) {
    unsigned long long hash = 1469598103934665603ull;
    for (wchar_t ch : text) {
        hash ^= static_cast<unsigned long long>(ch);
        hash *= 1099511628211ull;
    }
    std::wstringstream stream;
    stream << std::hex << std::setw(16) << std::setfill(L'0') << hash;
    return stream.str();
}

std::wstring SanitizeId(const std::wstring& value) {
    std::wstring out;
    for (wchar_t ch : value) {
        if ((ch >= L'a' && ch <= L'z') ||
            (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'0' && ch <= L'9') ||
            ch == L'-' || ch == L'_') {
            out.push_back(ch);
        } else {
            out.push_back(L'_');
        }
    }
    if (out.empty()) return L"default";
    if (out.size() > 80) out = out.substr(0, 80);
    return out;
}

std::wstring CodexVersionQuick() {
    return Trim(RunCommandCapture(L"codex --version 2>NUL"));
}

std::wstring DefaultSessionId(const std::wstring& provider) {
    wchar_t user[256] = {};
    GetEnvironmentVariableW(L"USERNAME", user, static_cast<DWORD>(std::size(user)));
    std::wstring basis = ProjectRootPath() + L"|" + user + L"|" + provider + L"|" + CodexVersionQuick() + L"|" + kBridgeDesktopVisualVersion;
    return L"default-" + HexHash(basis);
}

std::wstring CacheRoot() {
    return ArtifactsPath(L"vlm_session_cache");
}

std::wstring DevArtifactRoot() {
    return ArtifactsPath(L"dev1.0.3_automatic_real_vlm_runtime_bridge");
}

std::wstring CapabilityCachePath(const std::wstring& provider, const std::wstring& sessionId) {
    return CacheRoot() + L"\\" + SanitizeId(provider) + L"_" + SanitizeId(sessionId) + L".json";
}

std::wstring RawProbeOutputPath(const std::wstring& provider, const std::wstring& sessionId) {
    return DevArtifactRoot() + L"\\provider_raw_output_samples\\probe_" + SanitizeId(provider) + L"_" + SanitizeId(sessionId) + L"_" + TimestampForPath() + L".txt";
}

std::wstring RawLocateOutputPath(const std::wstring& provider, const std::wstring& sessionId) {
    return DevArtifactRoot() + L"\\provider_raw_output_samples\\locate_" + SanitizeId(provider) + L"_" + SanitizeId(sessionId) + L"_" + TimestampForPath() + L".txt";
}

std::wstring ParsedLocateJsonPath(const std::wstring& provider, const std::wstring& sessionId) {
    return DevArtifactRoot() + L"\\parsed_vlm_json_samples\\locate_" + SanitizeId(provider) + L"_" + SanitizeId(sessionId) + L"_" + TimestampForPath() + L".json";
}

std::wstring ProviderCommandDescription() {
    return L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\\codex_vlm_provider.ps1 -Mode probe";
}

std::wstring CacheEntryJson(const CapabilityCacheEntry& entry) {
    std::wstringstream json;
    json << L"{"
         << L"\"schema_version\":\"1.0.3.vlm_capability_session_cache\""
         << L",\"session_id\":" << JsonString(entry.sessionId)
         << L",\"provider\":" << JsonString(entry.provider)
         << L",\"provider_command\":" << JsonString(entry.providerCommand)
         << L",\"codex_cli_version\":" << JsonString(entry.codexCliVersion)
         << L",\"capability_status\":" << JsonString(entry.capabilityStatus)
         << L",\"checked_at\":" << JsonString(entry.checkedAt)
         << L",\"image_input_supported\":" << (entry.imageInputSupported ? L"true" : L"false")
         << L",\"probe_image_path\":" << JsonString(entry.probeImagePath)
         << L",\"raw_probe_output_path\":" << JsonString(entry.rawProbeOutputPath)
         << L",\"reason\":" << JsonString(entry.reason)
         << L",\"ttl_or_expiration\":" << JsonString(entry.ttlOrExpiration)
         << L",\"expires_at_unix\":" << entry.expiresAtUnix
         << L",\"desktopvisual_version\":" << JsonString(entry.desktopVisualVersion)
         << L"}";
    return json.str();
}

bool ReadCacheEntry(const std::wstring& path, CapabilityCacheEntry& entry, std::wstring& error) {
    std::wstring text;
    if (!VLMReadTextFile(path, text, error)) return false;
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        error = parsed.error.empty() ? L"cache JSON invalid" : parsed.error;
        return false;
    }
    entry.sessionId = simplejson::GetString(parsed.root, L"session_id");
    entry.provider = simplejson::GetString(parsed.root, L"provider");
    entry.providerCommand = simplejson::GetString(parsed.root, L"provider_command");
    entry.codexCliVersion = simplejson::GetString(parsed.root, L"codex_cli_version");
    entry.capabilityStatus = simplejson::GetString(parsed.root, L"capability_status", kCapabilityUnknown);
    entry.checkedAt = simplejson::GetString(parsed.root, L"checked_at");
    entry.imageInputSupported = simplejson::GetBool(parsed.root, L"image_input_supported", false);
    entry.probeImagePath = simplejson::GetString(parsed.root, L"probe_image_path");
    entry.rawProbeOutputPath = simplejson::GetString(parsed.root, L"raw_probe_output_path");
    entry.reason = simplejson::GetString(parsed.root, L"reason");
    entry.ttlOrExpiration = simplejson::GetString(parsed.root, L"ttl_or_expiration");
    entry.expiresAtUnix = static_cast<long long>(simplejson::GetInt(parsed.root, L"expires_at_unix", 0));
    entry.desktopVisualVersion = simplejson::GetString(parsed.root, L"desktopvisual_version");
    entry.cachePath = path;
    entry.valid = !entry.sessionId.empty() && !entry.provider.empty() && !entry.capabilityStatus.empty();
    return entry.valid;
}

std::wstring CacheOutputJson(
    const CapabilityProbeArgs& args,
    const CapabilityCacheEntry& entry,
    bool cacheHit,
    const std::wstring& cachePath,
    bool cacheWriteOk,
    const std::wstring& cacheWriteError,
    ULONGLONG startTick) {
    unsigned long long durationMs = DurationMsSince(startTick);
    std::wstringstream json;
    json << L"{"
         << L"\"ok\":true"
         << L",\"command\":\"vlm-capability-probe\""
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << durationMs
         << L",\"error_code\":\"\""
         << L",\"provider\":" << JsonString(args.provider)
         << L",\"session_id\":" << JsonString(entry.sessionId)
         << L",\"capability_status\":" << JsonString(entry.capabilityStatus)
         << L",\"cache_hit\":" << (cacheHit ? L"true" : L"false")
         << L",\"cache_enabled\":" << (args.cache ? L"true" : L"false")
         << L",\"cache_path\":" << JsonString(cachePath)
         << L",\"cache_write_ok\":" << (cacheWriteOk ? L"true" : L"false")
         << L",\"cache_write_error\":" << JsonString(cacheWriteError)
         << L",\"provider_command\":" << JsonString(entry.providerCommand)
         << L",\"codex_cli_version\":" << JsonString(entry.codexCliVersion)
         << L",\"checked_at\":" << JsonString(entry.checkedAt)
         << L",\"image_input_supported\":" << (entry.imageInputSupported ? L"true" : L"false")
         << L",\"probe_image_path\":" << JsonString(entry.probeImagePath)
         << L",\"raw_probe_output_path\":" << JsonString(entry.rawProbeOutputPath)
         << L",\"raw_probe_output_path_exists\":" << (FileExists(entry.rawProbeOutputPath) ? L"true" : L"false")
         << L",\"raw_probe_output_path_field\":" << JsonString(entry.rawProbeOutputPath)
         << L",\"reason\":" << JsonString(entry.reason)
         << L",\"ttl_or_expiration\":" << JsonString(entry.ttlOrExpiration)
         << L",\"expires_at_unix\":" << entry.expiresAtUnix
         << L",\"desktopvisual_version\":" << JsonString(entry.desktopVisualVersion)
         << L",\"data\":{"
         << L"\"provider\":" << JsonString(args.provider)
         << L",\"session_id\":" << JsonString(entry.sessionId)
         << L",\"capability_status\":" << JsonString(entry.capabilityStatus)
         << L",\"cache_hit\":" << (cacheHit ? L"true" : L"false")
         << L",\"cache_enabled\":" << (args.cache ? L"true" : L"false")
         << L",\"image_input_supported\":" << (entry.imageInputSupported ? L"true" : L"false")
         << L",\"codex_cli_version\":" << JsonString(entry.codexCliVersion)
         << L",\"reason\":" << JsonString(entry.reason)
         << L"}"
         << L",\"evidence\":{"
         << L"\"cache_path\":" << JsonString(cachePath)
         << L",\"cache_write_ok\":" << (cacheWriteOk ? L"true" : L"false")
         << L",\"cache_write_error\":" << JsonString(cacheWriteError)
         << L",\"probe_image_path\":" << JsonString(entry.probeImagePath)
         << L",\"raw_probe_output_path\":" << JsonString(entry.rawProbeOutputPath)
         << L",\"raw_probe_output_path_exists\":" << (FileExists(entry.rawProbeOutputPath) ? L"true" : L"false")
         << L",\"provider_command\":" << JsonString(entry.providerCommand)
         << L",\"checked_at\":" << JsonString(entry.checkedAt)
         << L",\"ttl_or_expiration\":" << JsonString(entry.ttlOrExpiration)
         << L"}"
         << L"}";
    return json.str();
}

std::wstring ErrorJson(const std::wstring& command, const std::wstring& code, const std::wstring& message, ULONGLONG startTick = 0) {
    std::wstringstream json;
    json << L"{\"ok\":false"
         << L",\"command\":" << JsonString(command)
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << DurationMsSince(startTick)
         << L",\"error_code\":" << JsonString(code)
         << L",\"error\":{\"code\":" << JsonString(code)
         << L",\"message\":" << JsonString(message)
         << L"}"
         << L",\"data\":{}"
         << L",\"evidence\":{\"message\":" << JsonString(message) << L"}"
         << L"}";
    return json.str();
}

bool ParseCapabilityProbeArgs(int argc, wchar_t** argv, CapabilityProbeArgs& args, std::wstring& error) {
    ArgValue(argc, argv, L"--provider", args.provider);
    ArgValue(argc, argv, L"--session-id", args.sessionId);
    ArgValue(argc, argv, L"--probe-image", args.probeImage);
    ArgValue(argc, argv, L"--simulation", args.simulation);
    if (args.simulation.empty()) {
        ArgValue(argc, argv, L"--simulate-provider", args.simulation);
    }
    if (!ParseIntArg(argc, argv, L"--timeout-ms", args.timeoutMs, error) ||
        !ParseBoolArg(argc, argv, L"--cache", args.cache, error) ||
        !ParseInt64Arg(argc, argv, L"--ttl-seconds", args.ttlSeconds, error)) {
        return false;
    }
    if (args.provider.empty()) {
        error = L"--provider must not be empty.";
        return false;
    }
    if (args.sessionId.empty()) {
        args.sessionId = DefaultSessionId(args.provider);
    }
    if (args.probeImage.empty()) {
        args.probeImage = ArtifactsPath(L"vlm_capability_probe\\vlm_probe_image.png");
    }
    if (args.timeoutMs <= 0) {
        error = L"--timeout-ms must be positive.";
        return false;
    }
    if (args.ttlSeconds <= 0) {
        error = L"--ttl-seconds must be positive.";
        return false;
    }
    return true;
}

bool ParseAssistLocateArgs(int argc, wchar_t** argv, AssistLocateArgs& args, std::wstring& error) {
    ArgValue(argc, argv, L"--provider", args.provider);
    ArgValue(argc, argv, L"--session-id", args.sessionId);
    ArgValue(argc, argv, L"--image", args.imagePath);
    ArgValue(argc, argv, L"--target", args.target);
    ArgValue(argc, argv, L"--target-window-title", args.targetWindowTitle);
    ArgValue(argc, argv, L"--simulation", args.simulation);
    ArgValue(argc, argv, L"--capability-simulation", args.capabilitySimulation);
    ArgValue(argc, argv, L"--screenshot-id", args.screenshotId);
    ArgValue(argc, argv, L"--frame-id", args.frameId);
    if (!ParseIntArg(argc, argv, L"--timeout-ms", args.timeoutMs, error) ||
        !ParseDoubleArg(argc, argv, L"--min-confidence", args.minConfidence, error) ||
        !ParseBoolArg(argc, argv, L"--cache", args.cache, error)) {
        return false;
    }
    if (args.provider.empty()) {
        error = L"--provider must not be empty.";
        return false;
    }
    if (args.sessionId.empty()) {
        args.sessionId = DefaultSessionId(args.provider);
    }
    if (args.imagePath.empty()) {
        error = L"vlm-assist-locate requires --image.";
        return false;
    }
    if (args.target.empty()) {
        error = L"vlm-assist-locate requires --target.";
        return false;
    }
    if (args.timeoutMs <= 0) {
        error = L"--timeout-ms must be positive.";
        return false;
    }
    if (args.minConfidence < 0.0 || args.minConfidence > 1.0) {
        error = L"--min-confidence must be between 0.0 and 1.0.";
        return false;
    }
    if (args.frameId.empty()) {
        args.frameId = L"frame-" + HexHash(args.imagePath + L"|" + args.target);
    }
    if (args.screenshotId.empty()) {
        args.screenshotId = args.frameId;
    }
    return true;
}

bool ParseCandidateValidateArgs(int argc, wchar_t** argv, CandidateValidateArgs& args, std::wstring& error) {
    ArgValue(argc, argv, L"--candidate-json", args.candidateJsonPath);
    ArgValue(argc, argv, L"--image", args.imagePath);
    ArgValue(argc, argv, L"--target", args.target);
    ArgValue(argc, argv, L"--target-window-title", args.targetWindowTitle);
    if (!ParseDoubleArg(argc, argv, L"--min-confidence", args.minConfidence, error)) {
        return false;
    }
    if (args.candidateJsonPath.empty()) {
        error = L"vlm-candidate-validate requires --candidate-json.";
        return false;
    }
    if (args.minConfidence < 0.0 || args.minConfidence > 1.0) {
        error = L"--min-confidence must be between 0.0 and 1.0.";
        return false;
    }
    return true;
}

CandidateEvidenceBinding ReadEvidenceBinding(const simplejson::Value& root) {
    CandidateEvidenceBinding binding;
    binding.screenshotId = simplejson::GetString(root, L"screenshot_id");
    binding.frameId = simplejson::GetString(root, L"frame_id");
    binding.imagePath = simplejson::GetString(root, L"image_path");
    binding.provider = simplejson::GetString(root, L"provider");
    binding.sessionId = simplejson::GetString(root, L"session_id");
    binding.promptHash = simplejson::GetString(root, L"prompt_hash");
    binding.rawResponsePath = simplejson::GetString(root, L"raw_response_path");
    binding.parsedJsonPath = simplejson::GetString(root, L"parsed_json_path");
    binding.requestedTarget = simplejson::GetString(root, L"requested_target");
    if (binding.requestedTarget.empty()) {
        binding.requestedTarget = simplejson::GetString(root, L"target");
    }
    return binding;
}

std::wstring EvidenceBindingFailure(const CandidateEvidenceBinding& binding) {
    if (binding.screenshotId.empty() && binding.frameId.empty()) return L"screenshot_id_or_frame_id_missing";
    if (binding.imagePath.empty()) return L"image_path_missing";
    if (!FileExists(binding.imagePath)) return L"image_path_not_found";
    if (binding.provider.empty()) return L"provider_missing";
    if (binding.sessionId.empty()) return L"session_id_missing";
    if (binding.promptHash.empty()) return L"prompt_hash_missing";
    if (binding.rawResponsePath.empty()) return L"raw_response_path_missing";
    if (!FileExists(binding.rawResponsePath)) return L"raw_response_path_not_found";
    if (binding.parsedJsonPath.empty()) return L"parsed_json_path_missing";
    if (!FileExists(binding.parsedJsonPath)) return L"parsed_json_path_not_found";
    return L"";
}

bool IsAllowedTargetType(const std::wstring& type) {
    static const std::vector<std::wstring> allowed = {
        L"button", L"icon", L"text", L"menu", L"input", L"window", L"region", L"unknown"
    };
    return std::find(allowed.begin(), allowed.end(), ToLowerInvariant(type)) != allowed.end();
}

bool ContainsUnsafeSafetyFlag(const std::vector<std::wstring>& flags, std::wstring& matched) {
    static const std::vector<std::wstring> unsafe = {
        L"active_protection", L"captcha", L"human_verification", L"anti_cheat",
        L"protected_desktop", L"automation_detected", L"bot_challenge", L"security_verification"
    };
    for (const auto& flag : flags) {
        std::wstring lower = ToLowerInvariant(flag);
        for (const auto& needle : unsafe) {
            if (lower.find(needle) != std::wstring::npos) {
                matched = flag;
                return true;
            }
        }
    }
    return false;
}

bool TargetSemanticsMatch(const VlmCandidate& candidate, const std::wstring& target) {
    std::wstring lowerTarget = ToLowerInvariant(target);
    if (lowerTarget.empty()) return false;
    if (ToLowerInvariant(candidate.targetLabel).find(lowerTarget) != std::wstring::npos) return true;
    if (ToLowerInvariant(candidate.reason).find(lowerTarget) != std::wstring::npos) return true;
    for (const auto& text : candidate.visibleText) {
        if (ToLowerInvariant(text).find(lowerTarget) != std::wstring::npos) return true;
    }
    return false;
}

bool ParseCandidateJson(const simplejson::Value& root, VlmCandidate& candidate, std::wstring& error) {
    if (!root.IsObject()) {
        error = L"candidate JSON root is not an object";
        return false;
    }
    candidate.schemaValid = true;
    candidate.ok = simplejson::GetBool(root, L"ok", false);
    candidate.targetFound = simplejson::GetBool(root, L"target_found", false);
    candidate.targetLabel = simplejson::GetString(root, L"target_label");
    candidate.targetType = simplejson::GetString(root, L"target_type", L"unknown");
    JsonNumber(root, L"confidence", candidate.confidence);
    candidate.coordinateSpace = simplejson::GetString(root, L"coordinate_space");
    candidate.imageWidth = simplejson::GetInt(root, L"image_width", 0);
    candidate.imageHeight = simplejson::GetInt(root, L"image_height", 0);
    candidate.reason = simplejson::GetString(root, L"reason");
    candidate.visibleText = simplejson::GetStringArray(root, L"visible_text");
    candidate.uncertainty = simplejson::GetString(root, L"uncertainty");
    candidate.safetyFlags = simplejson::GetStringArray(root, L"safety_flags");
    candidate.requiresHumanReview = simplejson::GetBool(root, L"requires_human_review", false);

    const simplejson::Value* bbox = simplejson::Find(root, L"bbox");
    const simplejson::Value* point = simplejson::Find(root, L"point");
    if (!bbox || !bbox->IsObject()) {
        error = L"bbox missing or invalid";
        return false;
    }
    if (!point || !point->IsObject()) {
        error = L"point missing or invalid";
        return false;
    }
    candidate.bboxX = JsonIntRounded(*bbox, L"x", 0);
    candidate.bboxY = JsonIntRounded(*bbox, L"y", 0);
    candidate.bboxW = JsonIntRounded(*bbox, L"w", 0);
    candidate.bboxH = JsonIntRounded(*bbox, L"h", 0);
    candidate.pointX = JsonIntRounded(*point, L"x", 0);
    candidate.pointY = JsonIntRounded(*point, L"y", 0);
    return true;
}

CandidateValidationResult ValidateCandidate(
    const VlmCandidate& candidate,
    const AssistLocateArgs& args,
    const ImageDimensions& image) {
    CandidateValidationResult result;
    result.candidate = candidate;
    if (!candidate.schemaValid) {
        result.rejectedReason = L"schema_invalid";
        return result;
    }
    if (!candidate.ok || !candidate.targetFound) {
        result.rejectedReason = L"target_not_found";
        return result;
    }
    if (!image.ok) {
        result.rejectedReason = L"image_dimensions_unavailable";
        return result;
    }
    if (candidate.coordinateSpace != L"image_pixels") {
        result.rejectedReason = L"coordinate_space_not_image_pixels";
        return result;
    }
    if (candidate.confidence < args.minConfidence) {
        result.rejectedReason = L"confidence_below_minimum";
        return result;
    }
    if (!IsAllowedTargetType(candidate.targetType)) {
        result.rejectedReason = L"target_type_invalid";
        return result;
    }
    if (!TargetSemanticsMatch(candidate, args.target)) {
        result.rejectedReason = L"target_semantic_mismatch";
        return result;
    }
    if (candidate.bboxW <= 0 || candidate.bboxH <= 0 ||
        candidate.bboxX < 0 || candidate.bboxY < 0 ||
        candidate.bboxX + candidate.bboxW > image.width ||
        candidate.bboxY + candidate.bboxH > image.height) {
        result.rejectedReason = L"bbox_out_of_bounds";
        return result;
    }
    if (candidate.pointX < 0 || candidate.pointY < 0 ||
        candidate.pointX >= image.width || candidate.pointY >= image.height) {
        result.rejectedReason = L"point_out_of_bounds";
        return result;
    }
    if (candidate.imageWidth > 0 && candidate.imageWidth != image.width) {
        result.rejectedReason = L"image_width_mismatch";
        return result;
    }
    if (candidate.imageHeight > 0 && candidate.imageHeight != image.height) {
        result.rejectedReason = L"image_height_mismatch";
        return result;
    }
    std::wstring unsafeFlag;
    if (ContainsUnsafeSafetyFlag(candidate.safetyFlags, unsafeFlag)) {
        result.rejectedReason = L"safety_flag_" + unsafeFlag;
        return result;
    }
    if (candidate.requiresHumanReview) {
        result.rejectedReason = L"requires_human_review";
        return result;
    }
    result.accepted = true;
    result.rejectedReason = L"";
    return result;
}

std::wstring BuildWrapperCommand(const CapabilityProbeArgs& args, const std::wstring& rawOutputPath) {
    std::wstring script = ProjectPath(L"tools\\codex_vlm_provider.ps1");
    std::wstringstream command;
    command << L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File " << QuoteCommandArg(script)
            << L" -Mode probe"
            << L" -Provider " << QuoteCommandArg(args.provider)
            << L" -ImagePath " << QuoteCommandArg(args.probeImage)
            << L" -RawOutputPath " << QuoteCommandArg(rawOutputPath)
            << L" -TimeoutMs " << args.timeoutMs;
    if (!args.simulation.empty()) {
        command << L" -Simulation " << QuoteCommandArg(args.simulation);
    }
    command << L" 2>&1";
    return command.str();
}

std::wstring BuildWrapperLocateCommand(const AssistLocateArgs& args, const std::wstring& rawOutputPath) {
    std::wstring script = ProjectPath(L"tools\\codex_vlm_provider.ps1");
    std::wstringstream command;
    command << L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File " << QuoteCommandArg(script)
            << L" -Mode locate"
            << L" -Provider " << QuoteCommandArg(args.provider)
            << L" -ImagePath " << QuoteCommandArg(args.imagePath)
            << L" -Target " << QuoteCommandArg(args.target)
            << L" -RawOutputPath " << QuoteCommandArg(rawOutputPath)
            << L" -TimeoutMs " << args.timeoutMs;
    if (!args.simulation.empty()) {
        command << L" -Simulation " << QuoteCommandArg(args.simulation);
    }
    command << L" 2>&1";
    return command.str();
}

CapabilityCacheEntry EntryFromProviderResult(
    const CapabilityProbeArgs& args,
    const ProviderProbeResult& provider,
    long long now,
    const std::wstring& cachePath);

ProviderProbeResult RunProviderProbe(const CapabilityProbeArgs& args, const std::wstring& rawOutputPath) {
    ProviderProbeResult result;
    result.provider = args.provider;
    result.rawOutputPath = rawOutputPath;
    if (!FileExists(args.probeImage)) {
        result.status = kCapabilityUnavailable;
        result.reason = L"probe image not found";
        result.imageInputSupported = false;
        return result;
    }
    std::wstring wrapperOutput = Trim(RunCommandCapture(BuildWrapperCommand(args, rawOutputPath)));
    result.wrapperJson = wrapperOutput;
    simplejson::ParseResult parsed = simplejson::Parse(wrapperOutput);
    if (!parsed.ok || !parsed.root.IsObject()) {
        result.status = kCapabilityUnknown;
        result.reason = parsed.error.empty() ? L"provider wrapper returned invalid JSON" : parsed.error;
        result.imageInputSupported = false;
        return result;
    }
    result.wrapperOk = simplejson::GetBool(parsed.root, L"ok", false);
    result.status = simplejson::GetString(parsed.root, L"provider_status", kCapabilityUnknown);
    if (result.status == kCapabilityTimeout) {
        result.status = kCapabilityUnavailable;
        result.reason = L"provider timed out";
    }
    result.codexCliVersion = simplejson::GetString(parsed.root, L"codex_cli_version");
    result.imageInputSupported = simplejson::GetBool(parsed.root, L"image_input_supported", false);
    result.rawOutputPath = simplejson::GetString(parsed.root, L"raw_output_path", rawOutputPath);
    result.reason = simplejson::GetString(parsed.root, L"reason");
    result.exitCode = simplejson::GetInt(parsed.root, L"exit_code", 0);
    if (result.status.empty()) {
        result.status = result.wrapperOk ? kCapabilityAvailable : kCapabilityUnknown;
    }
    if (result.status == kCapabilityAvailable && !result.wrapperOk) {
        result.status = kCapabilityUnknown;
        if (result.reason.empty()) result.reason = L"provider wrapper did not confirm availability";
    }
    if (result.status == kCapabilityAvailable && !result.imageInputSupported) {
        result.status = kCapabilityUnavailable;
        result.reason = L"provider did not report image input support";
    }
    if (result.reason.empty()) {
        result.reason = result.status == kCapabilityAvailable ? L"provider capability probe succeeded" : L"provider capability probe did not succeed";
    }
    return result;
}

CapabilityResolution ResolveCapability(const CapabilityProbeArgs& args) {
    CapabilityResolution resolution;
    resolution.cachePath = CapabilityCachePath(args.provider, args.sessionId);
    long long now = UnixNow();
    if (args.cache && FileExists(resolution.cachePath)) {
        CapabilityCacheEntry cached;
        std::wstring cacheError;
        if (ReadCacheEntry(resolution.cachePath, cached, cacheError) &&
            cached.provider == args.provider &&
            cached.sessionId == args.sessionId &&
            cached.expiresAtUnix > now) {
            resolution.entry = cached;
            resolution.cacheHit = true;
            return resolution;
        }
    }

    std::wstring rawOutputPath = RawProbeOutputPath(args.provider, args.sessionId);
    ProviderProbeResult provider = RunProviderProbe(args, rawOutputPath);
    resolution.entry = EntryFromProviderResult(args, provider, now, resolution.cachePath);
    if (args.cache) {
        resolution.cacheWriteOk = VLMWriteTextFile(resolution.cachePath, CacheEntryJson(resolution.entry), resolution.cacheWriteError);
    }
    return resolution;
}

CapabilityCacheEntry EntryFromProviderResult(
    const CapabilityProbeArgs& args,
    const ProviderProbeResult& provider,
    long long now,
    const std::wstring& cachePath) {
    CapabilityCacheEntry entry;
    entry.valid = true;
    entry.sessionId = args.sessionId;
    entry.provider = args.provider;
    entry.providerCommand = ProviderCommandDescription();
    entry.codexCliVersion = provider.codexCliVersion;
    if (entry.codexCliVersion.empty() && args.provider == L"codex-cli") {
        entry.codexCliVersion = CodexVersionQuick();
    }
    entry.capabilityStatus = provider.status.empty() ? kCapabilityUnknown : provider.status;
    if (entry.capabilityStatus == kCapabilityTimeout) {
        entry.capabilityStatus = kCapabilityUnavailable;
    }
    entry.checkedAt = NowTimestamp();
    entry.imageInputSupported = provider.imageInputSupported;
    entry.probeImagePath = args.probeImage;
    entry.rawProbeOutputPath = provider.rawOutputPath;
    entry.reason = provider.reason;
    entry.expiresAtUnix = now + args.ttlSeconds;
    entry.ttlOrExpiration = L"ttl_seconds=" + std::to_wstring(args.ttlSeconds) + L";expires_at_unix=" + std::to_wstring(entry.expiresAtUnix);
    entry.desktopVisualVersion = kBridgeDesktopVisualVersion;
    entry.cachePath = cachePath;
    return entry;
}

ProviderLocateResult RunProviderLocate(const AssistLocateArgs& args, const std::wstring& rawOutputPath) {
    ProviderLocateResult result;
    result.provider = args.provider;
    result.rawOutputPath = rawOutputPath;
    if (!FileExists(args.imagePath)) {
        result.status = kCapabilityUnavailable;
        result.reason = L"image not found";
        result.imageInputSupported = false;
        return result;
    }
    std::wstring wrapperOutput = Trim(RunCommandCapture(BuildWrapperLocateCommand(args, rawOutputPath)));
    result.wrapperJson = wrapperOutput;
    simplejson::ParseResult parsed = simplejson::Parse(wrapperOutput);
    if (!parsed.ok || !parsed.root.IsObject()) {
        result.status = kCapabilityInvalidResponse;
        result.reason = parsed.error.empty() ? L"provider wrapper returned invalid JSON" : parsed.error;
        return result;
    }
    result.wrapperOk = simplejson::GetBool(parsed.root, L"ok", false);
    result.status = simplejson::GetString(parsed.root, L"provider_status", kCapabilityUnknown);
    result.codexCliVersion = simplejson::GetString(parsed.root, L"codex_cli_version");
    result.imageInputSupported = simplejson::GetBool(parsed.root, L"image_input_supported", false);
    result.rawOutputPath = simplejson::GetString(parsed.root, L"raw_output_path", rawOutputPath);
    result.reason = simplejson::GetString(parsed.root, L"reason");
    result.exitCode = simplejson::GetInt(parsed.root, L"exit_code", 0);
    if (result.status.empty()) {
        result.status = result.wrapperOk ? kCapabilityAvailable : kCapabilityUnknown;
    }
    if (result.reason.empty()) {
        result.reason = result.status == kCapabilityAvailable ? L"provider locate returned output" : L"provider locate did not return available status";
    }
    return result;
}

std::wstring BboxJson(const VlmCandidate& candidate) {
    std::wstringstream json;
    json << L"{\"x\":" << candidate.bboxX
         << L",\"y\":" << candidate.bboxY
         << L",\"w\":" << candidate.bboxW
         << L",\"h\":" << candidate.bboxH
         << L"}";
    return json.str();
}

std::wstring PointJson(const VlmCandidate& candidate) {
    std::wstringstream json;
    json << L"{\"x\":" << candidate.pointX
         << L",\"y\":" << candidate.pointY
         << L"}";
    return json.str();
}

std::wstring AssistLocateOutputJson(
    const AssistLocateArgs& args,
    const CapabilityResolution& capability,
    const ProviderLocateResult& provider,
    const CandidateValidationResult& validation,
    const std::wstring& vlmStatus,
    const std::wstring& parsedJsonPath,
    const std::wstring& candidateRejectedReason,
    bool targetFound,
    int candidateCount,
    const ImageDimensions& image,
    ULONGLONG startTick) {
    const VlmCandidate& candidate = validation.candidate;
    std::wstring effectiveErrorCode;
    if (!validation.accepted) {
        effectiveErrorCode = !candidateRejectedReason.empty()
            ? candidateRejectedReason
            : (!vlmStatus.empty() ? vlmStatus : L"VLM_CANDIDATE_REJECTED");
        if (effectiveErrorCode == L"invalid_json") effectiveErrorCode = kCapabilityInvalidResponse;
        if (effectiveErrorCode == L"timeout") effectiveErrorCode = kCapabilityTimeout;
    }
    std::wstring reason = candidate.reason.empty() ? provider.reason : candidate.reason;
    std::wstringstream json;
    json << L"{"
         << L"\"ok\":" << (validation.accepted ? L"true" : L"false")
         << L",\"command\":\"vlm-assist-locate\""
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << DurationMsSince(startTick)
         << L",\"error_code\":" << JsonString(effectiveErrorCode)
         << L",\"provider\":" << JsonString(args.provider)
         << L",\"session_id\":" << JsonString(args.sessionId)
         << L",\"vlm_status\":" << JsonString(vlmStatus)
         << L",\"capability_status\":" << JsonString(capability.entry.capabilityStatus)
         << L",\"capability_cache_hit\":" << (capability.cacheHit ? L"true" : L"false")
         << L",\"raw_response_path\":" << JsonString(provider.rawOutputPath)
         << L",\"parsed_json_path\":" << JsonString(parsedJsonPath)
         << L",\"image_path\":" << JsonString(args.imagePath)
         << L",\"screenshot_id\":" << JsonString(args.screenshotId)
         << L",\"frame_id\":" << JsonString(args.frameId)
         << L",\"target\":" << JsonString(args.target)
         << L",\"target_window_title\":" << JsonString(args.targetWindowTitle)
         << L",\"target_found\":" << (targetFound ? L"true" : L"false")
         << L",\"candidate_count\":" << candidateCount
         << L",\"candidate_accepted\":" << (validation.accepted ? L"true" : L"false")
         << L",\"candidate_rejected_reason\":" << JsonString(candidateRejectedReason)
         << L",\"confidence\":" << std::fixed << std::setprecision(3) << candidate.confidence
         << L",\"bbox\":" << BboxJson(candidate)
         << L",\"point\":" << PointJson(candidate)
         << L",\"coordinate_space\":" << JsonString(candidate.coordinateSpace)
         << L",\"image_width\":" << (image.ok ? image.width : candidate.imageWidth)
         << L",\"image_height\":" << (image.ok ? image.height : candidate.imageHeight)
         << L",\"runtime_validation_passed\":" << (validation.accepted ? L"true" : L"false")
         << L",\"runtime_action_executed\":false"
         << L",\"vlm_action_executed\":false"
         << L",\"candidate_is_locate_only\":true"
         << L",\"requires_runtime_action\":true"
         << L",\"requires_coordinate_mapping_before_action\":true"
         << L",\"requires_target_window_lock_before_action\":true"
         << L",\"requires_post_action_verification\":true"
         << L",\"reason\":" << JsonString(reason);
    if (!effectiveErrorCode.empty()) {
        json << L",\"error\":{\"code\":" << JsonString(effectiveErrorCode)
             << L",\"message\":" << JsonString(candidateRejectedReason.empty() ? reason : candidateRejectedReason)
             << L"}";
    }
    json << L",\"data\":{"
         << L"\"provider\":" << JsonString(args.provider)
         << L",\"session_id\":" << JsonString(args.sessionId)
         << L",\"vlm_status\":" << JsonString(vlmStatus)
         << L",\"capability_status\":" << JsonString(capability.entry.capabilityStatus)
         << L",\"raw_response_path\":" << JsonString(provider.rawOutputPath)
         << L",\"parsed_json_path\":" << JsonString(parsedJsonPath)
         << L",\"candidate_accepted\":" << (validation.accepted ? L"true" : L"false")
         << L",\"candidate_rejected_reason\":" << JsonString(candidateRejectedReason)
         << L",\"runtime_validation_passed\":" << (validation.accepted ? L"true" : L"false")
         << L",\"runtime_action_executed\":false"
         << L",\"vlm_action_executed\":false"
         << L",\"candidate_is_locate_only\":true"
         << L",\"requires_runtime_action\":true"
         << L",\"requires_coordinate_mapping_before_action\":true"
         << L",\"requires_target_window_lock_before_action\":true"
         << L",\"requires_post_action_verification\":true"
         << L"}"
         << L",\"evidence\":{"
         << L"\"image_path\":" << JsonString(args.imagePath)
         << L",\"screenshot_id\":" << JsonString(args.screenshotId)
         << L",\"frame_id\":" << JsonString(args.frameId)
         << L",\"raw_response_path\":" << JsonString(provider.rawOutputPath)
         << L",\"raw_response_path_exists\":" << (FileExists(provider.rawOutputPath) ? L"true" : L"false")
         << L",\"parsed_json_path\":" << JsonString(parsedJsonPath)
         << L",\"parsed_json_path_exists\":" << (FileExists(parsedJsonPath) ? L"true" : L"false")
         << L",\"candidate_rejected_reason\":" << JsonString(candidateRejectedReason)
         << L",\"vlm_status\":" << JsonString(vlmStatus)
         << L",\"capability_status\":" << JsonString(capability.entry.capabilityStatus)
         << L",\"provider_reason\":" << JsonString(provider.reason)
         << L",\"target_window_title\":" << JsonString(args.targetWindowTitle)
         << L"}"
         << L"}";
    return json.str();
}

std::wstring AssistLocateUnavailableOutputJson(
    const AssistLocateArgs& args,
    const CapabilityResolution& capability,
    const std::wstring& vlmStatus,
    const std::wstring& rejectedReason,
    const ImageDimensions& image,
    ULONGLONG startTick) {
    ProviderLocateResult provider;
    provider.provider = args.provider;
    CandidateValidationResult validation;
    validation.rejectedReason = rejectedReason;
    validation.candidate.coordinateSpace = L"image_pixels";
    validation.candidate.imageWidth = image.width;
    validation.candidate.imageHeight = image.height;
    return AssistLocateOutputJson(args, capability, provider, validation, vlmStatus, L"", rejectedReason, false, 0, image, startTick);
}

std::wstring CandidateValidateOutputJson(
    const CandidateValidateArgs& args,
    const CandidateEvidenceBinding& binding,
    const CandidateValidationResult& validation,
    const ImageDimensions& image,
    const std::wstring& rejectedReason,
    ULONGLONG startTick) {
    const VlmCandidate& candidate = validation.candidate;
    std::wstring effectiveErrorCode = validation.accepted ? L"" : (rejectedReason.empty() ? L"VLM_CANDIDATE_REJECTED" : rejectedReason);
    std::wstring target = args.target.empty() ? binding.requestedTarget : args.target;
    std::wstringstream json;
    json << L"{"
         << L"\"ok\":" << (validation.accepted ? L"true" : L"false")
         << L",\"command\":\"vlm-candidate-validate\""
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"duration_ms\":" << DurationMsSince(startTick)
         << L",\"error_code\":" << JsonString(effectiveErrorCode)
         << L",\"candidate_json\":" << JsonString(args.candidateJsonPath)
         << L",\"image_path\":" << JsonString(binding.imagePath.empty() ? args.imagePath : binding.imagePath)
         << L",\"screenshot_id\":" << JsonString(binding.screenshotId)
         << L",\"frame_id\":" << JsonString(binding.frameId)
         << L",\"provider\":" << JsonString(binding.provider)
         << L",\"session_id\":" << JsonString(binding.sessionId)
         << L",\"prompt_hash\":" << JsonString(binding.promptHash)
         << L",\"raw_response_path\":" << JsonString(binding.rawResponsePath)
         << L",\"parsed_json_path\":" << JsonString(binding.parsedJsonPath)
         << L",\"target\":" << JsonString(target)
         << L",\"target_window_title\":" << JsonString(args.targetWindowTitle)
         << L",\"validation_result\":" << JsonString(validation.accepted ? L"PASS" : L"REJECTED")
         << L",\"candidate_accepted\":" << (validation.accepted ? L"true" : L"false")
         << L",\"candidate_rejected_reason\":" << JsonString(rejectedReason)
         << L",\"runtime_validation_passed\":" << (validation.accepted ? L"true" : L"false")
         << L",\"runtime_action_executed\":false"
         << L",\"vlm_action_executed\":false"
         << L",\"candidate_can_enter_runtime_action_planning\":" << (validation.accepted ? L"true" : L"false")
         << L",\"candidate_action_executed\":false"
         << L",\"confidence\":" << std::fixed << std::setprecision(3) << candidate.confidence
         << L",\"bbox\":" << BboxJson(candidate)
         << L",\"point\":" << PointJson(candidate)
         << L",\"coordinate_space\":" << JsonString(candidate.coordinateSpace)
         << L",\"image_width\":" << (image.ok ? image.width : candidate.imageWidth)
         << L",\"image_height\":" << (image.ok ? image.height : candidate.imageHeight)
         << L",\"coordinate_mapping_status\":" << JsonString(validation.accepted ? L"image_pixels_validated" : L"not_mapped")
         << L",\"mapped_screen_point\":" << PointJson(candidate)
         << L",\"target_window_lock_checked\":true"
         << L",\"target_window_lock_status\":" << JsonString(args.targetWindowTitle.empty() ? L"not_requested" : L"not_broken_by_candidate");
    if (!effectiveErrorCode.empty()) {
        json << L",\"error\":{\"code\":" << JsonString(effectiveErrorCode)
             << L",\"message\":" << JsonString(rejectedReason)
             << L"}";
    }
    json << L",\"data\":{"
         << L"\"validation_result\":" << JsonString(validation.accepted ? L"PASS" : L"REJECTED")
         << L",\"runtime_validation_passed\":" << (validation.accepted ? L"true" : L"false")
         << L",\"candidate_accepted\":" << (validation.accepted ? L"true" : L"false")
         << L",\"candidate_rejected_reason\":" << JsonString(rejectedReason)
         << L",\"candidate_can_enter_runtime_action_planning\":" << (validation.accepted ? L"true" : L"false")
         << L",\"runtime_action_executed\":false"
         << L",\"vlm_action_executed\":false"
         << L",\"candidate_action_executed\":false"
         << L"}"
         << L",\"evidence\":{"
         << L"\"candidate_json\":" << JsonString(args.candidateJsonPath)
         << L",\"image_path\":" << JsonString(binding.imagePath.empty() ? args.imagePath : binding.imagePath)
         << L",\"screenshot_id\":" << JsonString(binding.screenshotId)
         << L",\"frame_id\":" << JsonString(binding.frameId)
         << L",\"provider\":" << JsonString(binding.provider)
         << L",\"session_id\":" << JsonString(binding.sessionId)
         << L",\"raw_response_path\":" << JsonString(binding.rawResponsePath)
         << L",\"raw_response_path_exists\":" << (FileExists(binding.rawResponsePath) ? L"true" : L"false")
         << L",\"parsed_json_path\":" << JsonString(binding.parsedJsonPath)
         << L",\"parsed_json_path_exists\":" << (FileExists(binding.parsedJsonPath) ? L"true" : L"false")
         << L",\"candidate_rejected_reason\":" << JsonString(rejectedReason)
         << L",\"target\":" << JsonString(target)
         << L"}"
         << L"}";
    return json.str();
}

}  // namespace

int CommandVlmCapabilityProbe(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-capability-probe";
    CapabilityProbeArgs args;
    std::wstring error;
    if (!ParseCapabilityProbeArgs(argc, argv, args, error)) {
        std::wcout << ErrorJson(command, L"INVALID_ARGUMENT", error, startTick) << L"\n";
        return 2;
    }

    EnsureDirectoryPath(CacheRoot());
    EnsureDirectoryPath(DevArtifactRoot());
    EnsureDirectoryPath(DevArtifactRoot() + L"\\provider_raw_output_samples");

    std::wstring cachePath = CapabilityCachePath(args.provider, args.sessionId);
    long long now = UnixNow();
    if (args.cache && FileExists(cachePath)) {
        CapabilityCacheEntry cached;
        std::wstring cacheError;
        if (ReadCacheEntry(cachePath, cached, cacheError) &&
            cached.provider == args.provider &&
            cached.sessionId == args.sessionId &&
            cached.expiresAtUnix > now) {
            std::wcout << CacheOutputJson(args, cached, true, cachePath, true, L"", startTick) << L"\n";
            return 0;
        }
    }

    std::wstring rawOutputPath = RawProbeOutputPath(args.provider, args.sessionId);
    ProviderProbeResult provider = RunProviderProbe(args, rawOutputPath);
    CapabilityCacheEntry entry = EntryFromProviderResult(args, provider, now, cachePath);
    std::wstring writeError;
    bool writeOk = true;
    if (args.cache) {
        writeOk = VLMWriteTextFile(cachePath, CacheEntryJson(entry), writeError);
    }
    std::wcout << CacheOutputJson(args, entry, false, cachePath, writeOk, writeError, startTick) << L"\n";
    return 0;
}

int CommandVlmAssistLocate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-assist-locate";
    AssistLocateArgs args;
    std::wstring error;
    if (!ParseAssistLocateArgs(argc, argv, args, error)) {
        std::wcout << ErrorJson(command, L"INVALID_ARGUMENT", error, startTick) << L"\n";
        return 2;
    }

    EnsureDirectoryPath(CacheRoot());
    EnsureDirectoryPath(DevArtifactRoot());
    EnsureDirectoryPath(DevArtifactRoot() + L"\\provider_raw_output_samples");
    EnsureDirectoryPath(DevArtifactRoot() + L"\\parsed_vlm_json_samples");
    EnsureDirectoryPath(DevArtifactRoot() + L"\\rejected_candidate_samples");

    ImageDimensions image = ReadImageDimensions(args.imagePath);
    if (!image.ok) {
        CapabilityResolution emptyCapability;
        emptyCapability.entry.sessionId = args.sessionId;
        emptyCapability.entry.provider = args.provider;
        emptyCapability.entry.capabilityStatus = kCapabilityUnknown;
        std::wcout << AssistLocateUnavailableOutputJson(args, emptyCapability, kCapabilityUnknown, image.error.empty() ? L"image_invalid" : image.error, image, startTick) << L"\n";
        return 0;
    }

    CapabilityProbeArgs capArgs;
    capArgs.provider = args.provider;
    capArgs.sessionId = args.sessionId;
    capArgs.timeoutMs = args.timeoutMs;
    capArgs.cache = args.cache;
    capArgs.probeImage = ArtifactsPath(L"vlm_capability_probe\\vlm_probe_image.png");
    if (!FileExists(capArgs.probeImage)) capArgs.probeImage = args.imagePath;
    capArgs.simulation = args.capabilitySimulation;
    CapabilityResolution capability = ResolveCapability(capArgs);

    if (capability.entry.capabilityStatus != kCapabilityAvailable) {
        std::wstring reason = capability.entry.capabilityStatus.empty() ? L"vlm_capability_not_available" : capability.entry.capabilityStatus;
        std::wcout << AssistLocateUnavailableOutputJson(args, capability, reason, L"capability_gate_not_available", image, startTick) << L"\n";
        return 0;
    }

    ProviderLocateResult provider = RunProviderLocate(args, RawLocateOutputPath(args.provider, args.sessionId));
    if (provider.status != kCapabilityAvailable) {
        std::wstring status = provider.status.empty() ? kCapabilityUnknown : provider.status;
        if (status == kCapabilityTimeout) status = kCapabilityTimeout;
        CandidateValidationResult validation;
        validation.rejectedReason = status;
        validation.candidate.coordinateSpace = L"image_pixels";
        validation.candidate.imageWidth = image.width;
        validation.candidate.imageHeight = image.height;
        std::wcout << AssistLocateOutputJson(args, capability, provider, validation, status, L"", status, false, 0, image, startTick) << L"\n";
        return 0;
    }

    std::wstring rawText;
    std::wstring ioError;
    if (!VLMReadTextFile(provider.rawOutputPath, rawText, ioError)) {
        CandidateValidationResult validation;
        validation.rejectedReason = L"raw_response_missing";
        validation.candidate.coordinateSpace = L"image_pixels";
        validation.candidate.imageWidth = image.width;
        validation.candidate.imageHeight = image.height;
        std::wcout << AssistLocateOutputJson(args, capability, provider, validation, kCapabilityInvalidResponse, L"", L"raw_response_missing", false, 0, image, startTick) << L"\n";
        return 0;
    }

    std::wstring jsonText = ExtractFirstJsonObject(rawText);
    if (jsonText.empty()) {
        CandidateValidationResult validation;
        validation.rejectedReason = L"invalid_json";
        validation.candidate.coordinateSpace = L"image_pixels";
        validation.candidate.imageWidth = image.width;
        validation.candidate.imageHeight = image.height;
        std::wstring rejectedPath = DevArtifactRoot() + L"\\rejected_candidate_samples\\invalid_json_" + SanitizeId(args.sessionId) + L"_" + TimestampForPath() + L".txt";
        VLMWriteTextFile(rejectedPath, rawText, ioError);
        std::wcout << AssistLocateOutputJson(args, capability, provider, validation, kCapabilityInvalidResponse, L"", L"invalid_json", false, 0, image, startTick) << L"\n";
        return 0;
    }

    std::wstring parsedJsonPath = ParsedLocateJsonPath(args.provider, args.sessionId);
    VLMWriteTextFile(parsedJsonPath, jsonText, ioError);
    provider.parsedJsonPath = parsedJsonPath;

    simplejson::ParseResult parsed = simplejson::Parse(jsonText);
    if (!parsed.ok || !parsed.root.IsObject()) {
        CandidateValidationResult validation;
        validation.rejectedReason = L"invalid_json";
        validation.candidate.coordinateSpace = L"image_pixels";
        validation.candidate.imageWidth = image.width;
        validation.candidate.imageHeight = image.height;
        std::wstring rejectedPath = DevArtifactRoot() + L"\\rejected_candidate_samples\\invalid_json_" + SanitizeId(args.sessionId) + L"_" + TimestampForPath() + L".json";
        VLMWriteTextFile(rejectedPath, jsonText, ioError);
        std::wcout << AssistLocateOutputJson(args, capability, provider, validation, kCapabilityInvalidResponse, parsedJsonPath, L"invalid_json", false, 0, image, startTick) << L"\n";
        return 0;
    }

    VlmCandidate candidate;
    std::wstring candidateError;
    bool candidateParsed = ParseCandidateJson(parsed.root, candidate, candidateError);
    CandidateValidationResult validation;
    bool targetFound = false;
    int candidateCount = 0;
    std::wstring rejectedReason;
    if (!candidateParsed) {
        validation.candidate = candidate;
        validation.rejectedReason = candidateError.empty() ? L"schema_invalid" : candidateError;
        rejectedReason = validation.rejectedReason;
    } else {
        targetFound = candidate.targetFound;
        candidateCount = candidate.targetFound ? 1 : 0;
        validation = ValidateCandidate(candidate, args, image);
        rejectedReason = validation.accepted ? L"" : validation.rejectedReason;
    }
    if (!validation.accepted) {
        std::wstring rejectedPath = DevArtifactRoot() + L"\\rejected_candidate_samples\\candidate_rejected_" + SanitizeId(args.sessionId) + L"_" + TimestampForPath() + L".json";
        VLMWriteTextFile(rejectedPath, jsonText, ioError);
    }
    std::wstring status = validation.accepted || targetFound ? kCapabilityAvailable : kCapabilityCandidateRejected;
    if (candidateParsed && !candidate.targetFound) {
        status = kCapabilityAvailable;
        rejectedReason = L"target_not_found";
    }
    std::wcout << AssistLocateOutputJson(args, capability, provider, validation, status, parsedJsonPath, rejectedReason, targetFound, candidateCount, image, startTick) << L"\n";
    return 0;
}

int CommandVlmCandidateValidate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-candidate-validate";
    CandidateValidateArgs args;
    std::wstring error;
    if (!ParseCandidateValidateArgs(argc, argv, args, error)) {
        std::wcout << ErrorJson(command, L"INVALID_ARGUMENT", error, startTick) << L"\n";
        return 2;
    }

    std::wstring text;
    std::wstring ioError;
    if (!VLMReadTextFile(args.candidateJsonPath, text, ioError)) {
        CandidateValidationResult validation;
        CandidateEvidenceBinding binding;
        ImageDimensions image;
        std::wcout << CandidateValidateOutputJson(args, binding, validation, image, L"candidate_json_read_failed", startTick) << L"\n";
        return 0;
    }

    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        CandidateValidationResult validation;
        CandidateEvidenceBinding binding;
        ImageDimensions image;
        std::wcout << CandidateValidateOutputJson(args, binding, validation, image, L"invalid_json", startTick) << L"\n";
        return 0;
    }

    CandidateEvidenceBinding binding = ReadEvidenceBinding(parsed.root);
    if (!args.imagePath.empty() && binding.imagePath.empty()) {
        binding.imagePath = args.imagePath;
    }
    std::wstring bindingFailure = EvidenceBindingFailure(binding);
    ImageDimensions image = ReadImageDimensions(binding.imagePath.empty() ? args.imagePath : binding.imagePath);
    const simplejson::Value* candidateRoot = simplejson::Find(parsed.root, L"candidate");
    const simplejson::Value& parseRoot = candidateRoot && candidateRoot->IsObject() ? *candidateRoot : parsed.root;
    VlmCandidate candidate;
    std::wstring candidateError;
    bool candidateParsed = ParseCandidateJson(parseRoot, candidate, candidateError);

    CandidateValidationResult validation;
    std::wstring rejectedReason;
    if (!bindingFailure.empty()) {
        validation.candidate = candidate;
        rejectedReason = bindingFailure;
    } else if (!candidateParsed) {
        validation.candidate = candidate;
        rejectedReason = candidateError.empty() ? L"schema_invalid" : candidateError;
    } else {
        AssistLocateArgs locateArgs;
        locateArgs.target = args.target.empty() ? binding.requestedTarget : args.target;
        if (locateArgs.target.empty()) locateArgs.target = candidate.targetLabel;
        locateArgs.minConfidence = args.minConfidence;
        locateArgs.imagePath = binding.imagePath;
        locateArgs.targetWindowTitle = args.targetWindowTitle;
        validation = ValidateCandidate(candidate, locateArgs, image);
        rejectedReason = validation.accepted ? L"" : validation.rejectedReason;
    }

    if (!candidateParsed && rejectedReason.empty()) {
        rejectedReason = L"schema_invalid";
    }
    std::wcout << CandidateValidateOutputJson(args, binding, validation, image, rejectedReason, startTick) << L"\n";
    return 0;
}
