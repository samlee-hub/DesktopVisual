#include "VLMObservationContract.h"

#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <iomanip>
#include <iostream>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool IsAbsolutePath(const std::wstring& path) {
    return path.size() >= 2 && path[1] == L':';
}

std::wstring NormalizeMaybeProjectPath(const std::wstring& path) {
    if (path.empty() || IsAbsolutePath(path)) return path;
    return ProjectPath(path);
}

bool IsAllowedPurpose(const std::wstring& purpose) {
    for (const auto& value : VLMObservationPurposes()) {
        if (value == purpose) return true;
    }
    return false;
}

std::wstring JoinJsonFields(const std::vector<std::wstring>& fields) {
    std::wstringstream json;
    json << L"{";
    for (size_t i = 0; i < fields.size(); ++i) {
        if (i) json << L",";
        json << fields[i];
    }
    json << L"}";
    return json.str();
}

std::wstring JsonNumber(double value) {
    if (std::fabs(value - std::round(value)) < 0.000001) {
        return std::to_wstring(static_cast<long long>(std::llround(value)));
    }
    std::wstringstream stream;
    stream << std::setprecision(12) << value;
    return stream.str();
}

std::wstring JsonValueToString(const simplejson::Value& value) {
    using simplejson::Type;
    switch (value.type) {
        case Type::Null:
            return L"null";
        case Type::Bool:
            return value.boolValue ? L"true" : L"false";
        case Type::Number:
            return JsonNumber(value.numberValue);
        case Type::String:
            return JsonString(value.stringValue);
        case Type::Array: {
            std::wstringstream json;
            json << L"[";
            for (size_t i = 0; i < value.arrayValue.size(); ++i) {
                if (i) json << L",";
                json << JsonValueToString(value.arrayValue[i]);
            }
            json << L"]";
            return json.str();
        }
        case Type::Object: {
            std::wstringstream json;
            json << L"{";
            size_t index = 0;
            for (const auto& entry : value.objectValue) {
                if (index++) json << L",";
                json << JsonString(entry.first) << L":" << JsonValueToString(entry.second);
            }
            json << L"}";
            return json.str();
        }
    }
    return L"null";
}

const simplejson::Value* ObjectValue(const simplejson::Value* value) {
    return value && value->IsObject() ? value : nullptr;
}

const simplejson::Value* RootDataObject(const simplejson::Value& root) {
    if (!root.IsObject()) return nullptr;
    const simplejson::Value* data = simplejson::Find(root, L"data");
    if (data && data->IsObject()) return data;
    return &root;
}

std::wstring GetNestedString(const simplejson::Value* object, const std::wstring& key, const std::wstring& def = L"") {
    if (!object || !object->IsObject()) return def;
    return simplejson::GetString(*object, key, def);
}

bool GetNestedBool(const simplejson::Value* object, const std::wstring& key, bool def = false) {
    if (!object || !object->IsObject()) return def;
    return simplejson::GetBool(*object, key, def);
}

bool ReadRect(const simplejson::Value* value, VLMRect& rect) {
    if (!value || !value->IsObject()) return false;
    const bool hasLTRB =
        simplejson::Has(*value, L"left") &&
        simplejson::Has(*value, L"top") &&
        simplejson::Has(*value, L"right") &&
        simplejson::Has(*value, L"bottom");
    if (hasLTRB) {
        rect.present = true;
        rect.left = simplejson::GetInt(*value, L"left", 0);
        rect.top = simplejson::GetInt(*value, L"top", 0);
        rect.right = simplejson::GetInt(*value, L"right", 0);
        rect.bottom = simplejson::GetInt(*value, L"bottom", 0);
        return true;
    }
    const bool hasXYWH =
        simplejson::Has(*value, L"x") &&
        simplejson::Has(*value, L"y") &&
        simplejson::Has(*value, L"width") &&
        simplejson::Has(*value, L"height");
    if (hasXYWH) {
        rect.present = true;
        rect.left = simplejson::GetInt(*value, L"x", 0);
        rect.top = simplejson::GetInt(*value, L"y", 0);
        rect.right = rect.left + simplejson::GetInt(*value, L"width", 0);
        rect.bottom = rect.top + simplejson::GetInt(*value, L"height", 0);
        return true;
    }
    return false;
}

bool RectBoundsValid(const VLMRect& rect) {
    return rect.present && rect.right > rect.left && rect.bottom > rect.top;
}

std::wstring SummarizeUiaElements(const simplejson::Value* uia) {
    if (!uia || !uia->IsObject()) return L"";
    const simplejson::Value* elements = simplejson::Find(*uia, L"elements");
    if (!elements || !elements->IsArray()) return L"";
    std::vector<std::wstring> fragments;
    for (const auto& item : elements->arrayValue) {
        if (!item.IsObject()) continue;
        std::wstring name = simplejson::GetString(item, L"name", L"");
        std::wstring control = simplejson::GetString(item, L"control_type", L"");
        std::wstring text = simplejson::GetString(item, L"value", L"");
        std::wstring fragment = name;
        if (!control.empty()) fragment += fragment.empty() ? control : L" (" + control + L")";
        if (!text.empty()) fragment += fragment.empty() ? text : L": " + text;
        if (!fragment.empty()) fragments.push_back(fragment);
        if (fragments.size() >= 12) break;
    }
    std::wstringstream summary;
    for (size_t i = 0; i < fragments.size(); ++i) {
        if (i) summary << L"; ";
        summary << fragments[i];
    }
    return summary.str();
}

std::wstring DefaultElementSummaryJson(const simplejson::Value* data) {
    const simplejson::Value* explicitSummary = simplejson::Find(*data, L"element_summary");
    if (explicitSummary && explicitSummary->IsArray()) {
        return JsonValueToString(*explicitSummary);
    }
    const simplejson::Value* uia = simplejson::Find(*data, L"uia");
    const simplejson::Value* elements = uia && uia->IsObject() ? simplejson::Find(*uia, L"elements") : nullptr;
    if (elements && elements->IsArray()) {
        return JsonValueToString(*elements);
    }
    return L"[]";
}

std::wstring NewId(const std::wstring& prefix) {
    std::wstringstream id;
    id << prefix << L"-" << GetTickCount64();
    return id.str();
}

std::wstring RequestDataForEnvelope(const std::wstring& outputPath, const std::wstring& requestJson) {
    std::wstringstream data;
    data << L"{\"request_path\":" << JsonString(outputPath)
         << L",\"request\":" << requestJson
         << L"}";
    return data.str();
}

}  // namespace

std::vector<std::wstring> VLMAllowedOutputs() {
    return {
        L"scene_summary",
        L"visible_text",
        L"layout_regions",
        L"semantic_elements",
        L"possible_targets",
        L"uncertainty",
        L"rejection_reason",
        L"safety_notes"
    };
}

std::vector<std::wstring> VLMForbiddenOutputs() {
    return {
        L"direct_click",
        L"direct_type",
        L"direct_scroll",
        L"executable_action",
        L"coordinate_only_action",
        L"bypass_instruction",
        L"credential_handling",
        L"captcha_solving",
        L"anti_cheat_evasion",
        L"runtime_command"
    };
}

std::vector<std::wstring> VLMObservationPurposes() {
    return {
        L"scene_summary",
        L"semantic_elements",
        L"target_candidates_observation_only",
        L"layout_understanding",
        L"text_extraction_assist",
        L"unknown_ui_description"
    };
}

bool VLMReadTextFile(const std::wstring& path, std::wstring& text, std::wstring& error) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = L"file not found or unreadable";
        return false;
    }
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || size.QuadPart > 64LL * 1024LL * 1024LL) {
        CloseHandle(file);
        error = L"file size invalid or too large";
        return false;
    }
    std::string bytes(static_cast<size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    BOOL ok = bytes.empty() ? TRUE : ReadFile(file, &bytes[0], static_cast<DWORD>(bytes.size()), &read, nullptr);
    CloseHandle(file);
    if (!ok || read != bytes.size()) {
        error = L"file read failed";
        return false;
    }
    if (bytes.size() >= 3 &&
        static_cast<unsigned char>(bytes[0]) == 0xEF &&
        static_cast<unsigned char>(bytes[1]) == 0xBB &&
        static_cast<unsigned char>(bytes[2]) == 0xBF) {
        bytes.erase(0, 3);
    }
    if (bytes.empty()) {
        text.clear();
        return true;
    }
    int wideLen = MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    if (wideLen <= 0) {
        error = L"UTF-8 decode failed";
        return false;
    }
    text.assign(static_cast<size_t>(wideLen), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), &text[0], wideLen);
    return true;
}

bool VLMWriteTextFile(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        EnsureDirectoryPath(path.substr(0, slash));
    }
    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (utf8Len < 0) {
        error = L"UTF-8 encode failed";
        return false;
    }
    std::string bytes(static_cast<size_t>(utf8Len), '\0');
    if (utf8Len > 0) {
        WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), &bytes[0], utf8Len, nullptr, nullptr);
    }
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = L"file create failed";
        return false;
    }
    DWORD written = 0;
    BOOL ok = bytes.empty() ? TRUE : WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
    CloseHandle(file);
    if (!ok || written != bytes.size()) {
        error = L"file write failed";
        return false;
    }
    return true;
}

std::wstring VLMRectJson(const VLMRect& rect) {
    if (!rect.present) {
        return L"null";
    }
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring VLMStringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring VLMObservationResultToJson(const VLMObservationResult& result) {
    std::wstringstream layout;
    layout << L"[";
    for (size_t i = 0; i < result.layoutRegions.size(); ++i) {
        const auto& item = result.layoutRegions[i];
        if (i) layout << L",";
        layout << L"{\"region_id\":" << JsonString(item.regionId)
               << L",\"region_label\":" << JsonString(item.regionLabel)
               << L",\"approx_bounds\":" << VLMRectJson(item.approxBounds)
               << L",\"description\":" << JsonString(item.description)
               << L",\"confidence\":" << JsonNumber(item.confidence)
               << L"}";
    }
    layout << L"]";

    std::wstringstream elements;
    elements << L"[";
    for (size_t i = 0; i < result.semanticElements.size(); ++i) {
        const auto& item = result.semanticElements[i];
        if (i) elements << L",";
        elements << L"{\"element_id\":" << JsonString(item.elementId)
                 << L",\"label\":" << JsonString(item.label)
                 << L",\"role_guess\":" << JsonString(item.roleGuess)
                 << L",\"text\":" << JsonString(item.text)
                 << L",\"approx_region\":" << VLMRectJson(item.approxRegion)
                 << L",\"confidence\":" << JsonNumber(item.confidence)
                 << L",\"reasoning_summary\":" << JsonString(item.reasoningSummary)
                 << L"}";
    }
    elements << L"]";

    std::wstringstream targets;
    targets << L"[";
    for (size_t i = 0; i < result.possibleTargets.size(); ++i) {
        const auto& item = result.possibleTargets[i];
        if (i) targets << L",";
        targets << L"{\"candidate_id\":" << JsonString(item.candidateId)
                << L",\"label\":" << JsonString(item.label)
                << L",\"role_guess\":" << JsonString(item.roleGuess)
                << L",\"approx_region\":" << VLMRectJson(item.approxRegion)
                << L",\"confidence\":" << JsonNumber(item.confidence)
                << L",\"observation_only\":" << (item.observationOnly ? L"true" : L"false")
                << L",\"requires_runtime_validation\":" << (item.requiresRuntimeValidation ? L"true" : L"false")
                << L"}";
    }
    targets << L"]";

    std::vector<std::wstring> fields = {
        L"\"result_id\":" + JsonString(result.resultId),
        L"\"request_id\":" + JsonString(result.requestId),
        L"\"provider_name\":" + JsonString(result.providerName),
        L"\"provider_role\":" + JsonString(result.providerRole),
        L"\"schema_version\":" + JsonString(result.schemaVersion),
        L"\"result_schema_valid\":" + std::wstring(result.resultSchemaValid ? L"true" : L"false"),
        L"\"scene_summary\":" + JsonString(result.sceneSummary),
        L"\"visible_text\":" + VLMStringArrayJson(result.visibleText),
        L"\"layout_regions\":" + layout.str(),
        L"\"semantic_elements\":" + elements.str(),
        L"\"possible_targets\":" + targets.str(),
        L"\"uncertainty\":" + JsonNumber(result.uncertainty),
        L"\"rejection_reason\":" + JsonString(result.rejectionReason),
        L"\"safety_notes\":" + VLMStringArrayJson(result.safetyNotes),
        L"\"contains_action\":" + std::wstring(result.containsAction ? L"true" : L"false"),
        L"\"contains_coordinates\":" + std::wstring(result.containsCoordinates ? L"true" : L"false"),
        L"\"contains_executable_instruction\":" + std::wstring(result.containsExecutableInstruction ? L"true" : L"false"),
        L"\"contains_bypass_instruction\":" + std::wstring(result.containsBypassInstruction ? L"true" : L"false"),
        L"\"contains_credential_instruction\":" + std::wstring(result.containsCredentialInstruction ? L"true" : L"false"),
        L"\"coordinate_only_action\":" + std::wstring(result.coordinateOnlyAction ? L"true" : L"false"),
        L"\"runtime_command_present\":" + std::wstring(result.runtimeCommandPresent ? L"true" : L"false"),
        L"\"raw_provider_output_ref\":" + JsonString(result.rawProviderOutputRef),
        L"\"created_at\":" + JsonString(result.createdAt.empty() ? NowTimestamp() : result.createdAt)
    };
    if (!result.extraJsonFields.empty()) {
        fields.push_back(result.extraJsonFields);
    }
    return JoinJsonFields(fields);
}

std::wstring VLMGetRequestIdFromJson(const std::wstring& requestJson) {
    simplejson::ParseResult parsed = simplejson::Parse(requestJson);
    if (!parsed.ok || !parsed.root.IsObject()) return L"";
    return simplejson::GetString(parsed.root, L"request_id", L"");
}

bool VLMRequestHasBlockedContext(const std::wstring& requestJson) {
    simplejson::ParseResult parsed = simplejson::Parse(requestJson);
    if (!parsed.ok || !parsed.root.IsObject()) return false;
    return simplejson::GetBool(parsed.root, L"blocked_context", false) ||
        simplejson::GetBool(parsed.root, L"active_protection_detected", false) ||
        simplejson::GetBool(parsed.root, L"credential_required_detected", false);
}

VLMContractResult BuildVLMObservationRequestFromJsonText(
    const std::wstring& observeJson,
    const VLMObservationRequestBuildOptions& options) {
    VLMContractResult result;
    if (!IsAllowedPurpose(options.observationPurpose)) {
        result.errorCode = L"VLM_SCHEMA_INVALID";
        result.errorMessage = L"Unsupported observation_purpose.";
        return result;
    }

    simplejson::ParseResult parsed = simplejson::Parse(observeJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        result.errorCode = L"VLM_MALFORMED_JSON";
        result.errorMessage = parsed.error.empty() ? L"observe JSON is malformed." : parsed.error;
        return result;
    }

    const simplejson::Value* data = RootDataObject(parsed.root);
    if (!data) {
        result.errorCode = L"VLM_SCHEMA_INVALID";
        result.errorMessage = L"observe JSON root must be an object.";
        return result;
    }
    const simplejson::Value* targetWindow = ObjectValue(simplejson::Find(*data, L"target_window"));
    const simplejson::Value* screenshot = ObjectValue(simplejson::Find(*data, L"screenshot"));
    const simplejson::Value* uia = ObjectValue(simplejson::Find(*data, L"uia"));

    VLMRect windowBounds;
    if (targetWindow) {
        ReadRect(simplejson::Find(*targetWindow, L"rect"), windowBounds);
    }
    VLMRect screenBounds;
    if (!ReadRect(simplejson::Find(*data, L"screen_bounds"), screenBounds)) {
        screenBounds.present = true;
        screenBounds.left = 0;
        screenBounds.top = 0;
        screenBounds.right = 0;
        screenBounds.bottom = 0;
    }
    VLMRect screenshotRegion;
    ReadRect(simplejson::Find(*data, L"screenshot_region"), screenshotRegion);

    std::wstring screenshotPath = options.screenshotPath.empty()
        ? GetNestedString(screenshot, L"path", L"")
        : options.screenshotPath;
    screenshotPath = NormalizeMaybeProjectPath(screenshotPath);
    std::wstring uiaSummary = GetNestedString(data, L"uia_text_summary", L"");
    if (uiaSummary.empty()) uiaSummary = SummarizeUiaElements(uia);
    std::wstring ocrSummary = GetNestedString(data, L"ocr_text_summary", L"");
    const simplejson::Value* ocr = ObjectValue(simplejson::Find(*data, L"ocr"));
    if (ocrSummary.empty()) ocrSummary = GetNestedString(ocr, L"text", L"");
    bool activeProtection = GetNestedBool(data, L"active_protection_detected", false);
    bool credentialRequired = GetNestedBool(data, L"credential_required_detected", false);
    bool staleObserve = GetNestedBool(data, L"stale_observe", false) ||
        GetNestedBool(data, L"observe_stale", false) ||
        GetNestedBool(data, L"target_from_current_observe", true) == false;
    bool blockedContext = activeProtection || credentialRequired;

    std::wstring requestId = NewId(L"vlm-req");
    std::wstring observationId = simplejson::GetString(*data, L"observation_id", L"");
    if (observationId.empty()) observationId = NewId(L"obs");
    std::wstring sessionId = simplejson::GetString(*data, L"session_id", L"");
    if (sessionId.empty()) {
        const simplejson::Value* windowSession = ObjectValue(simplejson::Find(*data, L"window_session"));
        sessionId = GetNestedString(windowSession, L"session_id", L"");
    }

    std::vector<std::wstring> fields = {
        L"\"request_created\":true",
        L"\"request_id\":" + JsonString(requestId),
        L"\"observation_id\":" + JsonString(observationId),
        L"\"session_id\":" + JsonString(sessionId),
        L"\"window_hwnd\":" + JsonString(GetNestedString(targetWindow, L"hwnd", L"")),
        L"\"window_title\":" + JsonString(GetNestedString(targetWindow, L"title", L"")),
        L"\"process_name\":" + JsonString(GetNestedString(targetWindow, L"process_name", L"")),
        L"\"screen_bounds\":" + VLMRectJson(screenBounds),
        L"\"window_bounds\":" + VLMRectJson(windowBounds),
        L"\"screenshot_path\":" + JsonString(screenshotPath),
        L"\"screenshot_path_present\":" + std::wstring(screenshotPath.empty() ? L"false" : L"true"),
        L"\"screenshot_region\":" + VLMRectJson(screenshotRegion),
        L"\"roi_present\":" + std::wstring(screenshotRegion.present ? L"true" : L"false"),
        L"\"roi_bounds_valid\":" + std::wstring(screenshotRegion.present ? (RectBoundsValid(screenshotRegion) ? L"true" : L"false") : L"false"),
        L"\"uia_text_summary\":" + JsonString(uiaSummary),
        L"\"uia_summary_present\":" + std::wstring(uiaSummary.empty() ? L"false" : L"true"),
        L"\"ocr_text_summary\":" + JsonString(ocrSummary),
        L"\"ocr_summary_present\":" + std::wstring(ocrSummary.empty() ? L"false" : L"true"),
        L"\"visible_text_hash\":" + JsonString(GetNestedString(data, L"visible_text_hash", L"")),
        L"\"element_summary\":" + DefaultElementSummaryJson(data),
        L"\"task_hint\":" + JsonString(options.taskHint),
        L"\"expected_context\":" + JsonString(options.expectedContext),
        L"\"expected_context_present\":" + std::wstring(options.expectedContext.empty() ? L"false" : L"true"),
        L"\"observation_purpose\":" + JsonString(options.observationPurpose),
        L"\"provider_role\":\"assistive_only\"",
        L"\"allowed_outputs\":" + VLMStringArrayJson(VLMAllowedOutputs()),
        L"\"forbidden_outputs\":" + VLMStringArrayJson(VLMForbiddenOutputs()),
        L"\"forbidden_outputs_present\":true",
        L"\"active_protection_detected\":" + std::wstring(activeProtection ? L"true" : L"false"),
        L"\"credential_required_detected\":" + std::wstring(credentialRequired ? L"true" : L"false"),
        L"\"stale_observe\":" + std::wstring(staleObserve ? L"true" : L"false"),
        L"\"blocked_context\":" + std::wstring(blockedContext ? L"true" : L"false"),
        L"\"created_at\":" + JsonString(NowTimestamp()),
        L"\"contract_version\":\"6.5.0.vlm_observation_request\""
    };

    result.ok = true;
    result.json = JoinJsonFields(fields);
    return result;
}

VLMContractResult BuildVLMObservationRequestFile(const VLMObservationRequestBuildOptions& options) {
    VLMContractResult result;
    std::wstring observeJson;
    std::wstring ioError;
    if (options.observeJsonPath.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"vlm-observation-build-request requires --observe-json.";
        return result;
    }
    if (!VLMReadTextFile(options.observeJsonPath, observeJson, ioError)) {
        result.errorCode = L"FILE_READ_FAILED";
        result.errorMessage = ioError;
        return result;
    }
    result = BuildVLMObservationRequestFromJsonText(observeJson, options);
    if (!result.ok) return result;
    if (!options.outputPath.empty() && !VLMWriteTextFile(options.outputPath, result.json, ioError)) {
        result.ok = false;
        result.errorCode = L"FILE_WRITE_FAILED";
        result.errorMessage = ioError;
        return result;
    }
    return result;
}

int CommandVLMObservationBuildRequest(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-observation-build-request";
    VLMObservationRequestBuildOptions options;
    ArgValue(argc, argv, L"--observe-json", options.observeJsonPath);
    ArgValue(argc, argv, L"--screenshot", options.screenshotPath);
    ArgValue(argc, argv, L"--task-hint", options.taskHint);
    ArgValue(argc, argv, L"--expected-context", options.expectedContext);
    ArgValue(argc, argv, L"--observation-purpose", options.observationPurpose);
    ArgValue(argc, argv, L"--output", options.outputPath);
    if (options.observationPurpose.empty()) options.observationPurpose = L"scene_summary";
    if (options.observeJsonPath.empty() || options.outputPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"vlm-observation-build-request requires --observe-json and --output.", L"{}") << L"\n";
        return 2;
    }
    VLMContractResult result = BuildVLMObservationRequestFile(options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"VLM_SCHEMA_INVALID" : result.errorCode, result.errorMessage, L"{}") << L"\n";
        return result.errorCode == L"INVALID_ARGUMENT" ? 2 : 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), RequestDataForEnvelope(options.outputPath, result.json)) << L"\n";
    return 0;
}
