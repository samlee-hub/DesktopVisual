#include "Perception.h"

#include "ImageMatcher.h"
#include "OcrController.h"
#include "ProjectRoot.h"
#include "SafetyManifest.h"
#include "SafetyPolicy.h"
#include "Screenshot.h"
#include "Trace.h"
#include "UiaController.h"
#include "WindowSession.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <fstream>
#include <sstream>
#include <unordered_map>

namespace {

struct UiaElementState {
    RECT rect = {};
    bool enabled = false;
};

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsAnySensitiveTerm(const std::wstring& value) {
    std::wstring lower = ToLowerInvariant(value);
    const wchar_t* terms[] = {
        L"password",
        L"credential",
        L"payment",
        L"captcha",
        L"login",
        L"anti-cheat",
        L"anti cheat",
        L"game"
    };
    for (const wchar_t* term : terms) {
        if (lower.find(term) != std::wstring::npos) {
            return true;
        }
    }
    return false;
}

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring StatusJson(const ProviderStatus& status) {
    std::wstringstream json;
    json << L"{\"name\":" << JsonString(status.name)
         << L",\"status\":" << JsonString(status.status)
         << L",\"source_version\":" << JsonString(status.sourceVersion)
         << L",\"configured\":" << (status.configured ? L"true" : L"false")
         << L",\"latency_ms\":" << status.latencyMs
         << L",\"error_code\":" << JsonString(status.errorCode)
         << L",\"message\":" << JsonString(status.message)
         << L",\"attributes\":" << (status.attributesJson.empty() ? L"{}" : status.attributesJson)
         << L"}";
    return json.str();
}

std::wstring CandidateJson(const VisualElementCandidate& candidate) {
    std::wstringstream json;
    json << L"{\"id\":" << JsonString(candidate.id)
         << L",\"source\":" << JsonString(candidate.source)
         << L",\"source_version\":" << JsonString(candidate.sourceVersion)
         << L",\"label\":" << JsonString(candidate.label)
         << L",\"role\":" << JsonString(candidate.role)
         << L",\"text\":" << JsonString(candidate.text)
         << L",\"rect\":" << RectJson(candidate.rect)
         << L",\"coordinate_space\":" << JsonString(candidate.coordinateSpace)
         << L",\"confidence\":" << candidate.confidence
         << L",\"attributes\":" << (candidate.attributesJson.empty() ? L"{}" : candidate.attributesJson)
         << L",\"artifact_path\":" << JsonString(candidate.artifactPath)
         << L",\"provider_latency_ms\":" << candidate.providerLatencyMs
         << L",\"semantic_status\":" << JsonString(candidate.semanticStatus)
         << L",\"fusion_status\":" << JsonString(candidate.fusionStatus)
         << L",\"risk_status\":" << JsonString(candidate.riskStatus)
         << L"}";
    return json.str();
}

std::wstring CandidateArrayJson(const std::vector<VisualElementCandidate>& candidates) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < candidates.size(); ++i) {
        if (i != 0) json << L",";
        json << CandidateJson(candidates[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring ProviderArrayJson(const std::vector<ProviderStatus>& providers) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < providers.size(); ++i) {
        if (i != 0) json << L",";
        json << StatusJson(providers[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring PerceptionSourcesJson(const std::vector<ProviderStatus>& providers) {
    std::wstringstream json;
    json << L"[";
    bool first = true;
    for (const auto& provider : providers) {
        if (provider.status != L"available" && provider.status != L"degraded") {
            continue;
        }
        if (!first) json << L",";
        first = false;
        json << JsonString(provider.name);
    }
    json << L"]";
    return json.str();
}

std::wstring ElementGraphJson(const std::vector<VisualElementCandidate>& candidates) {
    std::wstringstream json;
    json << L"{\"version\":\"4.1.0\",\"node_count\":" << candidates.size() << L",\"nodes\":[";
    for (size_t i = 0; i < candidates.size(); ++i) {
        if (i != 0) json << L",";
        const auto& candidate = candidates[i];
        json << L"{\"node_id\":" << JsonString(L"node:" + candidate.id)
             << L",\"candidate_id\":" << JsonString(candidate.id)
             << L",\"source\":" << JsonString(candidate.source)
             << L",\"label\":" << JsonString(candidate.label)
             << L",\"role\":" << JsonString(candidate.role)
             << L",\"text\":" << JsonString(candidate.text)
             << L",\"rect\":" << RectJson(candidate.rect)
             << L",\"confidence\":" << candidate.confidence
             << L",\"semantic_status\":" << JsonString(candidate.semanticStatus)
             << L",\"risk_status\":" << JsonString(candidate.riskStatus)
             << L"}";
    }
    json << L"]}";
    return json.str();
}

std::wstring WarningArrayJson(const std::vector<std::wstring>& warnings) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < warnings.size(); ++i) {
        if (i != 0) json << L",";
        json << JsonString(warnings[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring NarrowPath(const std::wstring& value) {
    std::string out;
    out.reserve(value.size());
    for (wchar_t ch : value) {
        out.push_back(ch <= 0x7f ? static_cast<char>(ch) : '?');
    }
    return std::wstring(out.begin(), out.end());
}

std::string NarrowUtf8ish(const std::wstring& value) {
    std::string out;
    out.reserve(value.size());
    for (wchar_t ch : value) {
        out.push_back(ch <= 0x7f ? static_cast<char>(ch) : '?');
    }
    return out;
}

bool EnsureParentDirectory(const std::wstring& path) {
    size_t pos = path.find_last_of(L"\\/");
    if (pos == std::wstring::npos) {
        return true;
    }
    std::wstring parent = path.substr(0, pos);
    if (parent.empty()) {
        return true;
    }
    std::wstring current;
    for (size_t i = 0; i < parent.size(); ++i) {
        wchar_t ch = parent[i];
        current.push_back(ch);
        if ((ch == L'\\' || ch == L'/') && current.size() > 3) {
            CreateDirectoryW(current.c_str(), nullptr);
        }
    }
    return CreateDirectoryW(parent.c_str(), nullptr) || GetLastError() == ERROR_ALREADY_EXISTS;
}

uint64_t HashFileFnv1a(const std::wstring& path, bool& ok) {
    ok = false;
    std::ifstream file(NarrowUtf8ish(path), std::ios::binary);
    if (!file) {
        return 0;
    }
    uint64_t hash = 1469598103934665603ull;
    char buffer[4096] = {};
    while (file.read(buffer, sizeof(buffer)) || file.gcount() > 0) {
        std::streamsize count = file.gcount();
        for (std::streamsize i = 0; i < count; ++i) {
            hash ^= static_cast<unsigned char>(buffer[i]);
            hash *= 1099511628211ull;
        }
    }
    ok = true;
    return hash;
}

uint64_t HashStringFnv1a(const std::wstring& value) {
    uint64_t hash = 1469598103934665603ull;
    for (wchar_t ch : value) {
        hash ^= static_cast<unsigned int>(ch & 0xffff);
        hash *= 1099511628211ull;
    }
    return hash;
}

std::wstring HashHex(uint64_t hash) {
    std::wstringstream out;
    out << std::hex << hash;
    return out.str();
}

std::wstring ClientRegionJson(const RECT& rect) {
    return RectJson(rect);
}

RECT DefaultClientRoi(HWND hwnd) {
    RECT client = {};
    GetClientRect(hwnd, &client);
    return client;
}

std::wstring UiaSignature(HWND hwnd, int& count, bool& ok) {
    ok = false;
    count = 0;
    UiaQueryResult uia = ReadUiaTree(hwnd);
    if (!uia.ok) {
        return L"";
    }
    ok = true;
    count = static_cast<int>(uia.elements.size());
    std::wstringstream signature;
    for (const auto& element : uia.elements) {
        signature << element.name << L"|" << element.controlType << L"|" << element.automationId << L";";
    }
    return signature.str();
}

std::wstring EventJson(
    int index,
    const std::wstring& type,
    const std::wstring& reason,
    const std::wstring& title,
    const RECT& region,
    const std::wstring& artifactsJson,
    const std::wstring& cacheJson,
    const std::wstring& guardJson,
    long long latencyMs) {
    std::wstringstream json;
    json << L"{\"index\":" << index
         << L",\"timestamp\":" << JsonString(NowTimestamp())
         << L",\"type\":" << JsonString(type)
         << L",\"reason\":" << JsonString(reason)
         << L",\"target_title\":" << JsonString(title)
         << L",\"region\":" << ClientRegionJson(region)
         << L",\"latency_ms\":" << latencyMs
         << L",\"artifacts\":" << (artifactsJson.empty() ? L"{}" : artifactsJson)
         << L",\"cache\":" << (cacheJson.empty() ? L"{}" : cacheJson)
         << L",\"loop_guard\":" << (guardJson.empty() ? L"{}" : guardJson)
         << L"}";
    return json.str();
}

bool AppendJsonLine(const std::wstring& path, const std::wstring& json) {
    std::ofstream file(NarrowUtf8ish(path), std::ios::app | std::ios::binary);
    if (!file) {
        return false;
    }
    file << NarrowUtf8ish(json) << "\n";
    return true;
}

bool WriteTextFile(const std::wstring& path, const std::wstring& text) {
    std::ofstream file(NarrowUtf8ish(path), std::ios::binary);
    if (!file) {
        return false;
    }
    file << NarrowUtf8ish(text);
    return true;
}

bool Debounced(
    std::unordered_map<std::wstring, ULONGLONG>& lastEmitted,
    const std::wstring& key,
    ULONGLONG now,
    int debounceMs) {
    auto found = lastEmitted.find(key);
    if (found != lastEmitted.end() && now - found->second < static_cast<ULONGLONG>(debounceMs)) {
        return true;
    }
    lastEmitted[key] = now;
    return false;
}

bool LooksLikeLoading(const std::wstring& text) {
    std::wstring lower = ToLowerInvariant(text);
    return lower.find(L"loading") != std::wstring::npos || lower.find(L"please wait") != std::wstring::npos;
}

bool LooksLikeError(const std::wstring& text) {
    std::wstring lower = ToLowerInvariant(text);
    return lower.find(L"error") != std::wstring::npos || lower.find(L"failed") != std::wstring::npos || lower.find(L"exception") != std::wstring::npos;
}

bool LooksLikeSuccess(const std::wstring& text) {
    std::wstring lower = ToLowerInvariant(text);
    return lower.find(L"success") != std::wstring::npos || lower.find(L"passed") != std::wstring::npos || lower.find(L"done") != std::wstring::npos;
}

bool LooksLikeDialogSignature(const std::wstring& signature) {
    std::wstring lower = ToLowerInvariant(signature);
    return lower.find(L"dialog") != std::wstring::npos ||
        lower.find(L"modal") != std::wstring::npos ||
        lower.find(L"#32770") != std::wstring::npos;
}

std::wstring SceneStatusFromSignals(
    const std::wstring& riskContext,
    const std::vector<VisualElementCandidate>& candidates,
    const std::vector<std::wstring>& warnings,
    bool focusVerified) {
    std::wstring lower = ToLowerInvariant(riskContext);
    for (const auto& candidate : candidates) {
        lower += L" " + ToLowerInvariant(candidate.label + L" " + candidate.role + L" " + candidate.text + L" " + candidate.riskStatus);
    }
    for (const auto& warning : warnings) {
        lower += L" " + ToLowerInvariant(warning);
    }
    if (lower.find(L"blocked_sensitive") != std::wstring::npos ||
        lower.find(L"captcha") != std::wstring::npos ||
        lower.find(L"anti-cheat") != std::wstring::npos ||
        lower.find(L"credential") != std::wstring::npos ||
        lower.find(L"password") != std::wstring::npos ||
        lower.find(L"payment") != std::wstring::npos) {
        return L"blocked";
    }
    if (lower.find(L"loading") != std::wstring::npos || lower.find(L"please wait") != std::wstring::npos) {
        return L"loading";
    }
    if (lower.find(L"dialog") != std::wstring::npos || lower.find(L"modal") != std::wstring::npos) {
        return L"dialog_open";
    }
    if (lower.find(L"error") != std::wstring::npos || lower.find(L"failed") != std::wstring::npos || lower.find(L"exception") != std::wstring::npos) {
        return L"error";
    }
    if (lower.find(L"success") != std::wstring::npos || lower.find(L"passed") != std::wstring::npos || lower.find(L"done") != std::wstring::npos) {
        return L"success";
    }
    if (!focusVerified && candidates.empty()) {
        return L"unknown";
    }
    return L"normal";
}

std::wstring DynamicRecoveryJson(const std::wstring& state) {
    if (state == L"loading") return L"{\"strategy_name\":\"loading_wait_observe_loop\",\"steps\":[\"wait\",\"observe-loop\",\"loading_finished_or_timeout\"],\"route\":\"REQUIRE_HUMAN_CONFIRMATION\"}";
    if (state == L"dialog_open") return L"{\"strategy_name\":\"classify_dialog_safe_route\",\"steps\":[\"classify_dialog\",\"do_not_click_underlay\",\"safe_dialog_route\"],\"route\":\"REQUIRE_HUMAN_CONFIRMATION\"}";
    if (state == L"error") return L"{\"strategy_name\":\"error_stop_or_escalate_by_risk\",\"steps\":[\"record_error\",\"stop_or_escalate\"],\"route\":\"STOP\"}";
    if (state == L"success") return L"{\"strategy_name\":\"success_target_ready\",\"steps\":[\"target_ready\"],\"route\":\"AUTO_EXECUTE\"}";
    if (state == L"blocked") return L"{\"strategy_name\":\"blocked_stop_immediately\",\"steps\":[\"stop\"],\"route\":\"STOP\"}";
    if (state == L"unknown") return L"{\"strategy_name\":\"unknown_require_confirmation\",\"steps\":[\"stop_auto_execute\",\"require_human_confirmation\"],\"route\":\"REQUIRE_HUMAN_CONFIRMATION\"}";
    return L"{\"strategy_name\":\"normal_target_ready\",\"steps\":[\"target_ready\"],\"route\":\"AUTO_EXECUTE\"}";
}

std::wstring RouterDecisionForScene(const std::wstring& state) {
    if (state == L"blocked" || state == L"error") return L"STOP";
    if (state == L"loading" || state == L"dialog_open" || state == L"unknown") return L"REQUIRE_HUMAN_CONFIRMATION";
    return L"AUTO_EXECUTE";
}

std::wstring RoutersJsonForScene(const std::wstring& state) {
    std::wstring decision = RouterDecisionForScene(state);
    std::wstring riskRoute = state == L"blocked" ? L"STOP" : L"AUTO_EXECUTE";
    return L"{\"perception_router\":{\"route\":" + JsonString(decision) + L",\"state\":" + JsonString(state) + L"}"
        + L",\"semantic_resolver\":{\"route\":\"AUTO_EXECUTE\",\"semantic_status\":\"resolved_or_not_required\"}"
        + L",\"risk_router\":{\"route\":" + JsonString(riskRoute) + L"}"
        + L",\"action_executor_gate\":{\"route\":" + JsonString(decision) + L"}}";
}

std::wstring InitialChangeEventsJson(const std::wstring& state, size_t candidateCount) {
    std::wstringstream json;
    json << L"[{\"type\":\"initial_observe2\",\"source\":\"screen_frame\",\"candidate_count\":" << candidateCount << L"}";
    if (state == L"loading") json << L",{\"type\":\"loading_started\",\"source\":\"scene_state\"}";
    if (state == L"dialog_open") json << L",{\"type\":\"dialog_opened\",\"source\":\"scene_state\"}";
    if (state == L"error") json << L",{\"type\":\"error_appeared\",\"source\":\"scene_state\"}";
    if (state == L"success") json << L",{\"type\":\"success_appeared\",\"source\":\"scene_state\"}";
    if (state == L"normal" || state == L"success") json << L",{\"type\":\"target_ready\",\"source\":\"scene_state\"}";
    json << L"]";
    return json.str();
}

std::wstring UiaElementKey(const UiaElementInfo& element) {
    std::wstring key = element.automationId;
    if (key.empty()) key = element.name + L"|" + element.controlType + L"|" + element.className;
    return key;
}

std::unordered_map<std::wstring, UiaElementState> UiaStateMap(HWND hwnd, int& count, bool& ok, std::wstring& signature) {
    ok = false;
    count = 0;
    signature.clear();
    std::unordered_map<std::wstring, UiaElementState> states;
    UiaQueryResult uia = ReadUiaTree(hwnd);
    if (!uia.ok) {
        return states;
    }
    ok = true;
    count = static_cast<int>(uia.elements.size());
    std::wstringstream sig;
    for (const auto& element : uia.elements) {
        std::wstring key = UiaElementKey(element);
        if (key.empty()) key = L"element:" + std::to_wstring(states.size());
        UiaElementState state;
        state.rect = element.rect;
        state.enabled = element.enabled;
        states[key] = state;
        sig << key << L"|"
            << element.rect.left << L"," << element.rect.top << L"," << element.rect.right << L"," << element.rect.bottom << L"|"
            << (element.enabled ? L"enabled" : L"disabled") << L";";
    }
    signature = sig.str();
    return states;
}

std::wstring WindowJson(const WindowInfo& window) {
    std::wstringstream json;
    json << L"{\"title\":" << JsonString(window.title)
         << L",\"hwnd\":" << JsonString(FormatHwnd(window.hwnd))
         << L",\"pid\":" << window.pid
         << L",\"process_name\":" << JsonString(ProcessNameForPid(window.pid))
         << L",\"rect\":" << RectJson(window.rect)
         << L"}";
    return json.str();
}

std::wstring Observe2ScreenshotPath() {
    SYSTEMTIME time = {};
    GetLocalTime(&time);
    wchar_t buffer[128] = {};
    swprintf_s(
        buffer,
        L"observe2_%04u%02u%02u_%02u%02u%02u_%03u.bmp",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds);
    return ArtifactsPath(buffer);
}

ProviderStatus MakeExternalProviderStatus(const std::wstring& name, const wchar_t* envName, const std::wstring& message) {
    ProviderStatus status;
    status.name = name;
    status.sourceVersion = L"placeholder-v4.1.0";
    wchar_t value[8] = {};
    DWORD read = GetEnvironmentVariableW(envName, value, 8);
    status.configured = read > 0;
    status.status = status.configured ? L"degraded" : L"unavailable";
    status.message = status.configured ? L"Provider endpoint is configured but runtime integration is not implemented in v4.1.0." : message;
    status.attributesJson = L"{\"placeholder\":true,\"executes_actions\":false,\"downloads_weights\":false}";
    return status;
}

ProviderResult BuildUiaProvider(HWND hwnd, bool includeUia, int maxElements, const std::wstring& riskContext) {
    ProviderResult result;
    result.status.name = L"uia";
    result.status.sourceVersion = L"microsoft-uia-v1";
    result.status.configured = true;
    ULONGLONG start = GetTickCount64();
    if (!includeUia) {
        result.status.status = L"degraded";
        result.status.message = L"UIA provider was disabled for this observe2 call.";
        result.status.latencyMs = ElapsedMs(start);
        return result;
    }

    UiaQueryResult uia = ReadUiaTree(hwnd);
    result.status.latencyMs = ElapsedMs(start);
    if (!uia.ok) {
        result.status.status = L"unavailable";
        result.status.errorCode = uia.errorCode;
        result.status.message = uia.errorMessage;
        return result;
    }

    int limit = maxElements < 0 ? 0 : maxElements;
    result.status.status = L"available";
    result.status.message = L"UI Automation tree read.";
    result.status.attributesJson = L"{\"executes_actions\":false}";
    int count = static_cast<int>(uia.elements.size());
    int toWrite = count < limit ? count : limit;
    for (int i = 0; i < toWrite; ++i) {
        const auto& element = uia.elements[static_cast<size_t>(i)];
        VisualElementCandidate candidate;
        candidate.id = L"uia:" + std::to_wstring(i);
        candidate.source = L"uia";
        candidate.sourceVersion = result.status.sourceVersion;
        candidate.label = element.name;
        candidate.role = element.controlType;
        candidate.text = element.name;
        candidate.rect = element.rect;
        candidate.coordinateSpace = L"screen";
        candidate.confidence = element.name.empty() && element.controlType.empty() ? 0.45 : 0.92;
        candidate.attributesJson = L"{\"automation_id\":" + JsonString(element.automationId)
            + L",\"class_name\":" + JsonString(element.className)
            + L",\"enabled\":" + std::wstring(element.enabled ? L"true" : L"false")
            + L",\"offscreen\":" + std::wstring(element.offscreen ? L"true" : L"false")
            + L"}";
        candidate.providerLatencyMs = result.status.latencyMs;
        candidate.semanticStatus = element.name.empty() && element.controlType.empty() ? L"unresolved" : L"resolved";
        candidate.fusionStatus = L"single_source";
        candidate.riskStatus = ContainsAnySensitiveTerm(riskContext + L" " + element.name + L" " + element.controlType) ? L"blocked_sensitive" : L"normal";
        result.candidates.push_back(candidate);
    }
    return result;
}

ProviderResult BuildImageTemplateProvider(
    const std::wstring& screenshotPath,
    const std::wstring& templatePath,
    int tolerance,
    const std::wstring& riskContext) {
    ProviderResult result;
    result.status.name = L"image_template";
    result.status.sourceVersion = L"bmp-template-v1";
    result.status.configured = !templatePath.empty();
    result.status.attributesJson = L"{\"executes_actions\":false,\"template_format\":\"bmp\"}";
    ULONGLONG start = GetTickCount64();
    if (templatePath.empty()) {
        result.status.status = L"unavailable";
        result.status.message = L"No --image-template was provided.";
        result.status.latencyMs = ElapsedMs(start);
        return result;
    }
    if (screenshotPath.empty()) {
        result.status.status = L"unavailable";
        result.status.errorCode = L"SCREENSHOT_REQUIRED";
        result.status.message = L"Image template provider requires a captured screenshot.";
        result.status.latencyMs = ElapsedMs(start);
        return result;
    }

    ImageMatchResult match = FindTemplateInBmp(screenshotPath, templatePath, tolerance);
    result.status.latencyMs = ElapsedMs(start);
    if (!match.ok) {
        result.status.status = L"degraded";
        result.status.errorCode = match.errorCode;
        result.status.message = match.errorMessage;
        return result;
    }

    result.status.status = L"available";
    result.status.message = L"Image template matched one visual region.";
    VisualElementCandidate candidate;
    candidate.id = L"image_template:0";
    candidate.source = L"image_template";
    candidate.sourceVersion = result.status.sourceVersion;
    candidate.label = L"image_template_match";
    candidate.role = L"visual_region";
    candidate.text = L"";
    candidate.rect.left = match.x;
    candidate.rect.top = match.y;
    candidate.rect.right = match.x + match.width;
    candidate.rect.bottom = match.y + match.height;
    candidate.coordinateSpace = L"window_bitmap";
    candidate.confidence = match.score;
    candidate.attributesJson = L"{\"match_count\":" + std::to_wstring(match.matchCount)
        + L",\"template\":" + JsonString(templatePath)
        + L",\"tolerance\":" + std::to_wstring(tolerance)
        + L"}";
    candidate.artifactPath = templatePath;
    candidate.providerLatencyMs = result.status.latencyMs;
    candidate.semanticStatus = L"unresolved";
    candidate.fusionStatus = L"visual_only";
    candidate.riskStatus = ContainsAnySensitiveTerm(riskContext) ? L"blocked_sensitive" : L"normal";
    result.candidates.push_back(candidate);
    return result;
}

ProviderStatus BuildOcrProviderStatus() {
    ProviderStatus status;
    status.name = L"ocr";
    status.sourceVersion = L"windows-winrt-ocr";
    status.configured = true;
    ULONGLONG start = GetTickCount64();
    OcrCapability capability = GetOcrCapability();
    status.latencyMs = ElapsedMs(start);
    status.status = capability.available ? L"available" : L"unavailable";
    status.message = capability.available ? L"OCR runtime is available." : L"OCR runtime is unavailable.";
    status.attributesJson = L"{\"engine\":" + JsonString(capability.engine)
        + L",\"languages\":" + JsonString(capability.languages)
        + L",\"executes_actions\":false}";
    return status;
}

}  // namespace

std::wstring ProviderRegistryJson(bool includeUia, const std::wstring& imageTemplatePath) {
    std::vector<ProviderStatus> providers;
    ProviderStatus uia;
    uia.name = L"uia";
    uia.status = includeUia ? L"available" : L"degraded";
    uia.sourceVersion = L"microsoft-uia-v1";
    uia.configured = true;
    uia.message = includeUia ? L"UIA provider can be used." : L"UIA provider disabled by caller.";
    uia.attributesJson = L"{\"executes_actions\":false}";
    providers.push_back(uia);
    providers.push_back(BuildOcrProviderStatus());

    ProviderStatus screenDelta;
    screenDelta.name = L"screen_delta";
    screenDelta.status = L"degraded";
    screenDelta.sourceVersion = L"screen-delta-cache-v0";
    screenDelta.configured = true;
    screenDelta.message = L"No previous observe2 frame is available in v4.1.0 command scope.";
    screenDelta.attributesJson = L"{\"cache_required\":true,\"executes_actions\":false}";
    providers.push_back(screenDelta);

    ProviderStatus image;
    image.name = L"image_template";
    image.status = imageTemplatePath.empty() ? L"unavailable" : L"available";
    image.sourceVersion = L"bmp-template-v1";
    image.configured = !imageTemplatePath.empty();
    image.message = imageTemplatePath.empty() ? L"No --image-template configured." : L"Image template provider is configured.";
    image.attributesJson = L"{\"executes_actions\":false,\"template_format\":\"bmp\"}";
    providers.push_back(image);

    providers.push_back(MakeExternalProviderStatus(L"local_visual_provider", L"DESKTOPVISUAL_LOCAL_VISUAL_PROVIDER", L"OmniParser, YOLO, and UGround local providers are placeholders in v4.1.0."));
    providers.push_back(MakeExternalProviderStatus(L"cloud_vlm", L"DESKTOPVISUAL_CLOUD_VLM_PROVIDER", L"Cloud VLM provider is not configured and is not called by v4.1.0."));
    providers.push_back(MakeExternalProviderStatus(L"agent_provider", L"DESKTOPVISUAL_AGENT_PROVIDER", L"Agent provider endpoint is not configured and is not called by v4.1.0."));
    return ProviderArrayJson(providers);
}

bool IsUnresolvedVisualSelector(const std::wstring& selector) {
    return selector.rfind(L"visual:", 0) == 0;
}

Observe2Result Observe2(const Observe2Options& options) {
    Observe2Result result;
    if (options.title.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"observe2 requires --title.";
        return result;
    }
    if (options.maxElements < 0 || options.maxElements > 1000) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"--max-elements must be between 0 and 1000.";
        return result;
    }
    if (options.imageTolerance < 0 || options.imageTolerance > 255) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"--tolerance must be between 0 and 255.";
        return result;
    }

    WindowSessionResult session = ResolveWindowSession(options.title, options.process);
    if (!session.ok) {
        result.errorCode = session.errorCode;
        result.errorMessage = session.errorMessage;
        result.dataJson = session.dataJson;
        return result;
    }
    result.target = session.session.window;

    std::vector<std::wstring> warnings;
    std::wstring screenshotPath;
    std::wstring screenshotMethod = L"none";
    bool needsScreenshot = options.includeScreenshot || !options.imageTemplatePath.empty();
    if (needsScreenshot) {
        screenshotPath = Observe2ScreenshotPath();
        ScreenshotResult shot = CaptureWindowToBmp(result.target.hwnd, screenshotPath);
        if (shot.ok) {
            screenshotMethod = shot.method;
        } else {
            warnings.push_back(L"Screenshot failed: " + shot.error);
            screenshotPath.clear();
        }
    }

    std::vector<ProviderStatus> providers;
    std::vector<VisualElementCandidate> candidates;
    std::wstring riskContext = result.target.title + L" " + ProcessNameForPid(result.target.pid);

    ProviderResult uia = BuildUiaProvider(result.target.hwnd, options.includeUia, options.maxElements, riskContext);
    providers.push_back(uia.status);
    candidates.insert(candidates.end(), uia.candidates.begin(), uia.candidates.end());
    warnings.insert(warnings.end(), uia.warnings.begin(), uia.warnings.end());

    providers.push_back(BuildOcrProviderStatus());

    ProviderStatus screenDelta;
    screenDelta.name = L"screen_delta";
    screenDelta.status = L"degraded";
    screenDelta.sourceVersion = L"screen-delta-cache-v0";
    screenDelta.configured = true;
    screenDelta.message = L"Initial observe2 frame only; no previous frame delta is available.";
    screenDelta.attributesJson = L"{\"cache_required\":true,\"executes_actions\":false}";
    providers.push_back(screenDelta);

    ProviderResult image = BuildImageTemplateProvider(screenshotPath, options.imageTemplatePath, options.imageTolerance, riskContext);
    providers.push_back(image.status);
    candidates.insert(candidates.end(), image.candidates.begin(), image.candidates.end());
    warnings.insert(warnings.end(), image.warnings.begin(), image.warnings.end());

    providers.push_back(MakeExternalProviderStatus(L"local_visual_provider", L"DESKTOPVISUAL_LOCAL_VISUAL_PROVIDER", L"OmniParser, YOLO, and UGround local providers are placeholders in v4.1.0."));
    providers.push_back(MakeExternalProviderStatus(L"cloud_vlm", L"DESKTOPVISUAL_CLOUD_VLM_PROVIDER", L"Cloud VLM provider is not configured and is not called by v4.1.0."));
    providers.push_back(MakeExternalProviderStatus(L"agent_provider", L"DESKTOPVISUAL_AGENT_PROVIDER", L"Agent provider endpoint is not configured and is not called by v4.1.0."));

    SYSTEMTIME time = {};
    GetLocalTime(&time);
    wchar_t frameId[96] = {};
    swprintf_s(frameId, L"frame-%04u%02u%02u-%02u%02u%02u-%03u", time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond, time.wMilliseconds);

    HWND foreground = GetForegroundWindow();
    bool focusVerified = foreground == result.target.hwnd;
    std::wstring sceneStatus = SceneStatusFromSignals(riskContext, candidates, warnings, focusVerified);
    std::wstring actionDecision = RouterDecisionForScene(sceneStatus);
    std::wstringstream data;
    data << L"{\"schema_version\":\"4.4.0\""
         << L",\"screen_frame\":{"
         << L"\"frame_id\":" << JsonString(frameId)
         << L",\"target_window\":" << WindowJson(result.target)
         << L",\"window_session\":" << WindowSessionJson(session.session)
         << L",\"screenshot\":{\"path\":" << JsonString(screenshotPath)
         << L",\"method\":" << JsonString(screenshotMethod)
         << L",\"captured\":" << (screenshotPath.empty() ? L"false" : L"true") << L"}"
         << L"}"
         << L",\"providers\":" << ProviderArrayJson(providers)
         << L",\"perception_sources\":" << PerceptionSourcesJson(providers)
         << L",\"element_graph\":" << ElementGraphJson(candidates)
         << L",\"locator_candidates\":" << CandidateArrayJson(candidates)
         << L",\"scene_state\":{"
         << L"\"status\":" << JsonString(sceneStatus)
         << L",\"focus_verified\":" << (focusVerified ? L"true" : L"false")
         << L",\"candidate_count\":" << candidates.size()
         << L",\"provider_count\":" << providers.size()
         << L",\"warnings\":" << WarningArrayJson(warnings)
         << L"}"
         << L",\"change_events\":" << InitialChangeEventsJson(sceneStatus, candidates.size())
         << L",\"dynamic_recovery\":" << DynamicRecoveryJson(sceneStatus)
         << L",\"routers\":" << RoutersJsonForScene(sceneStatus)
         << L",\"action_decision\":" << JsonString(actionDecision)
         << L"}";

    result.ok = true;
    result.dataJson = data.str();
    return result;
}

ObserveLoopResult ObserveLoop(const ObserveLoopOptions& options) {
    ObserveLoopResult result;
    if (options.title.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"observe-loop requires --title.";
        return result;
    }
    if (options.intervalMs < 50 || options.maxDurationMs < 1 || options.maxEvents < 1 ||
        options.maxNoChangeRounds < 1 || options.debounceMs < 0) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"Invalid loop guard or timing argument.";
        return result;
    }

    std::wstring eventsPath = options.eventsPath.empty() ? ArtifactsPath(L"dev4.2.0\\events.jsonl") : options.eventsPath;
    std::wstring reportPath = options.reportPath.empty() ? ArtifactsPath(L"dev4.2.0\\observe_loop_report.md") : options.reportPath;
    std::wstring normalizedEvents;
    std::wstring writeError;
    if (!IsWritePathAllowed(eventsPath, normalizedEvents, writeError)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.errorMessage = writeError.empty() ? L"Events artifact path is not writable by policy." : writeError;
        return result;
    }
    std::wstring normalizedReport;
    if (!IsWritePathAllowed(reportPath, normalizedReport, writeError)) {
        result.errorCode = L"SAFETY_POLICY_DENIED";
        result.errorMessage = writeError.empty() ? L"Report artifact path is not writable by policy." : writeError;
        return result;
    }
    EnsureParentDirectory(normalizedEvents);
    EnsureParentDirectory(normalizedReport);
    DeleteFileW(normalizedEvents.c_str());

    WindowSessionResult session = ResolveWindowSession(options.title, options.process);
    if (!session.ok) {
        result.errorCode = session.errorCode;
        result.errorMessage = session.errorMessage;
        result.dataJson = session.dataJson;
        return result;
    }
    result.target = session.session.window;

    SafetyManifest manifest = LoadSafetyManifest();
    std::wstring processName = ProcessNameForPid(result.target.pid);
    std::wstring matchedRule;
    std::wstring matchedCategory;
    RECT roi = options.hasRoi ? options.roi : DefaultClientRoi(result.target.hwnd);
    std::unordered_map<std::wstring, ULONGLONG> debounce;
    std::vector<std::wstring> emittedTypes;
    ULONGLONG loopStart = GetTickCount64();
    ULONGLONG lastTick = loopStart;
    HWND lastForeground = nullptr;
    RECT lastWindowRect = result.target.rect;
    uint64_t lastCaptureHash = 0;
    bool hasLastCaptureHash = false;
    uint64_t lastTextHash = 0;
    bool hasLastTextHash = false;
    uint64_t lastUiaHash = 0;
    int lastUiaCount = -1;
    std::unordered_map<std::wstring, UiaElementState> lastUiaStates;
    bool previousLoading = false;
    bool previousDialog = false;
    int cacheHits = 0;
    int cacheMisses = 0;
    int ocrRuns = 0;
    int uiaRuns = 0;
    int screenshotRuns = 0;
    int changedRegionScreenshots = 0;
    bool stoppedBySafety = false;
    std::wstring stopReason = L"max_duration_ms";

    auto guardJson = [&](const std::wstring& reason) {
        std::wstringstream json;
        json << L"{\"reason\":" << JsonString(reason)
             << L",\"max_duration_ms\":" << options.maxDurationMs
             << L",\"max_events\":" << options.maxEvents
             << L",\"max_no_change_rounds\":" << options.maxNoChangeRounds
             << L",\"no_change_rounds\":" << result.noChangeRounds
             << L",\"loop_count\":" << result.loopCount
             << L"}";
        return json.str();
    };

    auto emit = [&](const std::wstring& type, const std::wstring& reason, const std::wstring& artifactsJson, const std::wstring& cacheJson, const std::wstring& guard, bool force) {
        ULONGLONG now = GetTickCount64();
        std::wstring key = type + L"|" + std::to_wstring(roi.left) + L"," + std::to_wstring(roi.top) + L"," + std::to_wstring(roi.right) + L"," + std::to_wstring(roi.bottom);
        if (!force && Debounced(debounce, key, now, options.debounceMs)) {
            return true;
        }
        long long latency = static_cast<long long>(now - lastTick);
        std::wstring line = EventJson(result.eventCount, type, reason, result.target.title, roi, artifactsJson, cacheJson, guard, latency);
        if (!AppendJsonLine(normalizedEvents, line)) {
            result.errorCode = L"FILE_WRITE_FAILED";
            result.errorMessage = L"Could not write observe-loop event.";
            return false;
        }
        emittedTypes.push_back(type);
        ++result.eventCount;
        return true;
    };

    std::wstring initialCache = L"{\"cache_hit\":false,\"capture_hash\":\"\",\"screen_delta\":\"initial\",\"ocr_ran\":false,\"uia_ran\":false}";
    if (!emit(L"target_ready", L"Initial target window resolved.", L"{\"events_path\":" + JsonString(normalizedEvents) + L"}", initialCache, guardJson(L"running"), true)) {
        return result;
    }

    while (ElapsedMs(loopStart) < options.maxDurationMs && result.eventCount < options.maxEvents) {
        if (!options.stopFilePath.empty() && GetFileAttributesW(options.stopFilePath.c_str()) != INVALID_FILE_ATTRIBUTES) {
            stopReason = L"stop_file";
            break;
        }
        if (IsDeniedBySafetyManifest(manifest, result.target.title, processName, matchedRule, matchedCategory)) {
            stoppedBySafety = true;
            std::wstring cache = L"{\"cache_hit\":true,\"safety_blocked\":true,\"matched_rule\":" + JsonString(matchedRule)
                + L",\"matched_category\":" + JsonString(matchedCategory) + L"}";
            emit(L"safety_blocked", L"Target matched denied safety manifest rule.", L"{}", cache, guardJson(L"safety_blocked"), true);
            stopReason = L"safety_blocked";
            break;
        }

        lastTick = GetTickCount64();
        ++result.loopCount;
        std::wstring screenshotPath = ArtifactsPath(L"dev4.2.0\\loop_capture_" + std::to_wstring(result.loopCount) + L".bmp");
        EnsureParentDirectory(screenshotPath);
        ScreenshotResult shot = CaptureWindowToBmp(result.target.hwnd, screenshotPath);
        ++screenshotRuns;
        if (!shot.ok) {
            std::wstring cache = L"{\"cache_hit\":false,\"screen_delta\":\"capture_failed\",\"ocr_ran\":false,\"uia_ran\":false}";
            if (!emit(L"error_appeared", L"Screenshot capture failed.", L"{\"screenshot_path\":" + JsonString(screenshotPath) + L"}", cache, guardJson(L"capture_failed"), false)) {
                return result;
            }
            stopReason = L"capture_failed";
            break;
        }
        bool hashOk = false;
        uint64_t captureHash = HashFileFnv1a(screenshotPath, hashOk);
        bool changed = !hasLastCaptureHash || !hashOk || captureHash != lastCaptureHash;
        if (changed) {
            ++cacheMisses;
            result.noChangeRounds = 0;
        } else {
            ++cacheHits;
            ++result.noChangeRounds;
        }

        HWND foreground = GetForegroundWindow();
        bool foregroundChanged = lastForeground != nullptr && foreground != lastForeground;
        lastForeground = foreground;

        WindowSessionResult currentSession = ResolveWindowSession(options.title, options.process);
        bool windowChanged = currentSession.ok && (
            currentSession.session.window.rect.left != lastWindowRect.left ||
            currentSession.session.window.rect.top != lastWindowRect.top ||
            currentSession.session.window.rect.right != lastWindowRect.right ||
            currentSession.session.window.rect.bottom != lastWindowRect.bottom ||
            currentSession.session.window.title != result.target.title);
        if (currentSession.ok) {
            result.target = currentSession.session.window;
            lastWindowRect = result.target.rect;
        }

        bool uiaRan = false;
        bool ocrRan = false;
        std::wstring text;
        if (changed) {
            std::wstring changedPath = ArtifactsPath(L"dev4.2.0\\changed_region_" + std::to_wstring(changedRegionScreenshots) + L".bmp");
            CopyFileW(screenshotPath.c_str(), changedPath.c_str(), FALSE);
            ++changedRegionScreenshots;

            int uiaCount = 0;
            bool uiaOk = false;
            std::wstring signature;
            std::unordered_map<std::wstring, UiaElementState> currentUiaStates = UiaStateMap(result.target.hwnd, uiaCount, uiaOk, signature);
            uiaRan = uiaOk;
            if (uiaOk) {
                ++uiaRuns;
                uint64_t uiaHash = HashStringFnv1a(signature);
                if (lastUiaCount >= 0 && uiaCount > lastUiaCount) {
                    emit(L"element_appeared", L"UIA element signature gained entries.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                } else if (lastUiaCount >= 0 && uiaCount < lastUiaCount) {
                    emit(L"element_disappeared", L"UIA element signature lost entries.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                }
                for (const auto& item : currentUiaStates) {
                    auto previous = lastUiaStates.find(item.first);
                    if (previous == lastUiaStates.end()) {
                        continue;
                    }
                    const RECT& a = previous->second.rect;
                    const RECT& b = item.second.rect;
                    if (a.left != b.left || a.top != b.top || a.right != b.right || a.bottom != b.bottom) {
                        emit(L"element_moved", L"UIA element rectangle changed.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                    }
                    if (!previous->second.enabled && item.second.enabled) {
                        emit(L"element_enabled", L"UIA element became enabled.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                    }
                    if (previous->second.enabled && !item.second.enabled) {
                        emit(L"element_disabled", L"UIA element became disabled.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                    }
                }
                bool dialog = LooksLikeDialogSignature(signature);
                if (dialog && !previousDialog) {
                    emit(L"dialog_opened", L"Dialog-like UIA signature appeared.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                } else if (!dialog && previousDialog) {
                    emit(L"dialog_closed", L"Dialog-like UIA signature disappeared.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":false,\"uia_ran\":true}", guardJson(L"running"), false);
                }
                previousDialog = dialog;
                lastUiaHash = uiaHash;
                lastUiaCount = uiaCount;
                lastUiaStates = currentUiaStates;
            }

            OcrResult ocr = ReadRegionText(result.target.hwnd, roi.left, roi.top, roi.right - roi.left, roi.bottom - roi.top);
            ocrRan = ocr.ok;
            if (ocr.ok) {
                ++ocrRuns;
                text = ocr.fullText;
                uint64_t textHash = HashStringFnv1a(text);
                if (hasLastTextHash && textHash != lastTextHash) {
                    emit(L"text_changed", L"ROI OCR text changed after screen delta.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":true,\"uia_ran\":" + std::wstring(uiaRan ? L"true" : L"false") + L"}", guardJson(L"running"), false);
                }
                bool loading = LooksLikeLoading(text);
                if (loading && !previousLoading) {
                    emit(L"loading_started", L"Loading text appeared.", L"{}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":true,\"uia_ran\":false}", guardJson(L"running"), false);
                }
                if (!loading && previousLoading) {
                    emit(L"loading_finished", L"Loading text disappeared.", L"{}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":true,\"uia_ran\":false}", guardJson(L"running"), false);
                }
                if (LooksLikeError(text)) {
                    emit(L"error_appeared", L"Error-like text appeared.", L"{}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":true,\"uia_ran\":false}", guardJson(L"running"), false);
                }
                if (LooksLikeSuccess(text)) {
                    emit(L"success_appeared", L"Success-like text appeared.", L"{}", L"{\"cache_hit\":false,\"screen_delta\":\"changed\",\"ocr_ran\":true,\"uia_ran\":false}", guardJson(L"running"), false);
                }
                previousLoading = loading;
                lastTextHash = textHash;
                hasLastTextHash = true;
            }

            std::wstring cache = L"{\"cache_hit\":false,\"capture_hash\":" + JsonString(HashHex(captureHash))
                + L",\"screen_delta\":\"changed\",\"ocr_ran\":" + std::wstring(ocrRan ? L"true" : L"false")
                + L",\"uia_ran\":" + std::wstring(uiaRan ? L"true" : L"false")
                + L",\"changed_regions_only\":" + std::wstring(options.changedRegionsOnly ? L"true" : L"false") + L"}";
            emit(L"region_changed", L"Capture hash changed.", L"{\"changed_region_screenshot\":" + JsonString(changedPath) + L"}", cache, guardJson(L"running"), false);
        } else {
            std::wstring cache = L"{\"cache_hit\":true,\"capture_hash\":" + JsonString(HashHex(captureHash))
                + L",\"screen_delta\":\"unchanged\",\"ocr_ran\":false,\"uia_ran\":false}";
            if (foregroundChanged) {
                emit(L"foreground_changed", L"Foreground window handle changed.", L"{}", cache, guardJson(L"running"), false);
            }
            if (windowChanged) {
                emit(L"window_changed", L"Target window metadata changed.", L"{}", cache, guardJson(L"running"), false);
            }
        }

        lastCaptureHash = captureHash;
        hasLastCaptureHash = true;

        if (result.eventCount >= options.maxEvents) {
            stopReason = L"max_events";
            break;
        }
        if (result.noChangeRounds >= options.maxNoChangeRounds) {
            stopReason = L"max_no_change_rounds";
            break;
        }
        Sleep(static_cast<DWORD>(options.intervalMs));
    }
    result.durationMs = ElapsedMs(loopStart);
    if (result.durationMs >= options.maxDurationMs && stopReason == L"max_duration_ms") {
        // keep default
    } else if (result.eventCount >= options.maxEvents) {
        stopReason = L"max_events";
    } else if (result.noChangeRounds >= options.maxNoChangeRounds) {
        stopReason = L"max_no_change_rounds";
    }

    std::wstringstream report;
    report << L"# Observe Loop Report\n\n"
           << L"- Result: PASS\n"
           << L"- Target: " << result.target.title << L"\n"
           << L"- Events: " << normalizedEvents << L"\n"
           << L"- Event count: " << result.eventCount << L"\n"
           << L"- Loop count: " << result.loopCount << L"\n"
           << L"- Stop reason: " << stopReason << L"\n"
           << L"- Duration ms: " << result.durationMs << L"\n"
           << L"- Cache hits: " << cacheHits << L"\n"
           << L"- Cache misses: " << cacheMisses << L"\n"
           << L"- Screenshot runs: " << screenshotRuns << L"\n"
           << L"- ROI OCR runs: " << ocrRuns << L"\n"
           << L"- UIA refresh runs: " << uiaRuns << L"\n"
           << L"- Changed region screenshots: " << changedRegionScreenshots << L"\n"
           << L"- Safety stopped: " << (stoppedBySafety ? L"true" : L"false") << L"\n\n"
           << L"## Event Types\n\n";
    for (const auto& type : emittedTypes) {
        report << L"- " << type << L"\n";
    }
    if (!WriteTextFile(normalizedReport, report.str())) {
        result.errorCode = L"FILE_WRITE_FAILED";
        result.errorMessage = L"Could not write observe-loop report.";
        return result;
    }

    std::wstringstream data;
    data << L"{\"events_path\":" << JsonString(normalizedEvents)
         << L",\"report_path\":" << JsonString(normalizedReport)
         << L",\"event_count\":" << result.eventCount
         << L",\"loop_count\":" << result.loopCount
         << L",\"duration_ms\":" << result.durationMs
         << L",\"stop_reason\":" << JsonString(stopReason)
         << L",\"cache_hits\":" << cacheHits
         << L",\"cache_misses\":" << cacheMisses
         << L",\"roi_ocr_runs\":" << ocrRuns
         << L",\"uia_refresh_runs\":" << uiaRuns
         << L",\"screenshot_runs\":" << screenshotRuns
         << L",\"changed_region_screenshots\":" << changedRegionScreenshots
         << L",\"supported_event_types\":["
         << L"\"window_changed\",\"foreground_changed\",\"region_changed\",\"text_changed\",\"element_appeared\",\"element_disappeared\",\"dialog_opened\",\"dialog_closed\",\"loading_started\",\"loading_finished\",\"error_appeared\",\"success_appeared\",\"element_moved\",\"element_enabled\",\"element_disabled\",\"target_ready\",\"safety_blocked\""
         << L"]}";
    result.ok = true;
    result.dataJson = data.str();
    return result;
}
