#include "FileWorkflow.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <sstream>
#include <vector>

namespace {

std::wstring Trim(std::wstring value) {
    while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
    while (!value.empty() && iswspace(value.back())) value.pop_back();
    return value;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    std::wstring lowerValue = Lower(value);
    std::wstring lowerPrefix = Lower(prefix);
    return lowerValue.size() >= lowerPrefix.size() && lowerValue.substr(0, lowerPrefix.size()) == lowerPrefix;
}

bool ContainsTraversal(const std::wstring& value) {
    std::wstring normalized = value;
    std::replace(normalized.begin(), normalized.end(), L'/', L'\\');
    return normalized == L".." ||
           StartsWith(normalized, L"..\\") ||
           normalized.find(L"\\..\\") != std::wstring::npos ||
           (normalized.size() >= 3 && normalized.substr(normalized.size() - 3) == L"\\..");
}

std::wstring NormalizeSeparators(std::wstring value) {
    std::replace(value.begin(), value.end(), L'/', L'\\');
    return value;
}

bool IsAbsolutePath(const std::wstring& path) {
    return path.size() > 2 && path[1] == L':';
}

std::wstring ResolveMaybeProjectRelative(const std::wstring& path) {
    std::wstring normalized = NormalizeSeparators(path);
    if (IsAbsolutePath(normalized)) return normalized;
    return ProjectPath(normalized);
}

std::wstring FullPath(const std::wstring& path) {
    DWORD needed = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (needed == 0) return path;
    std::wstring out(needed, L'\0');
    DWORD written = GetFullPathNameW(path.c_str(), needed, &out[0], nullptr);
    if (written == 0 || written >= needed) return path;
    out.resize(written);
    return NormalizeSeparators(out);
}

std::vector<std::wstring> SplitList(const std::wstring& value, wchar_t delimiter) {
    std::vector<std::wstring> out;
    size_t start = 0;
    while (start <= value.size()) {
        size_t pos = value.find(delimiter, start);
        std::wstring item = Trim(value.substr(start, pos == std::wstring::npos ? std::wstring::npos : pos - start));
        if (!item.empty()) out.push_back(item);
        if (pos == std::wstring::npos) break;
        start = pos + 1;
    }
    return out;
}

std::wstring ExtensionOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) return L"";
    return Lower(path.substr(dot));
}

std::wstring FileNameOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

FileWorkflowResult Failure(const std::wstring& code, const std::wstring& message, const std::wstring& data = L"{}") {
    FileWorkflowResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.dataJson = data;
    return result;
}

size_t FindValueStart(const std::wstring& json, const std::wstring& key) {
    size_t pos = json.find(L"\"" + key + L"\"");
    if (pos == std::wstring::npos) return std::wstring::npos;
    pos = json.find(L":", pos);
    if (pos == std::wstring::npos) return std::wstring::npos;
    ++pos;
    while (pos < json.size() && iswspace(json[pos])) ++pos;
    return pos;
}

std::wstring JsonStringValue(const std::wstring& json, const std::wstring& key) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'"') return L"";
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) {
            ++pos;
            if (json[pos] == L'n') value += L'\n';
            else if (json[pos] == L'r') value += L'\r';
            else if (json[pos] == L't') value += L'\t';
            else value += json[pos];
        } else {
            value += json[pos];
        }
        ++pos;
    }
    return Trim(value);
}

bool JsonBoolValue(const std::wstring& json, const std::wstring& key, bool def = false) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos) return def;
    if (json.substr(pos, 4) == L"true") return true;
    if (json.substr(pos, 5) == L"false") return false;
    std::wstring quoted = Lower(JsonStringValue(json, key));
    if (quoted == L"true" || quoted == L"1") return true;
    if (quoted == L"false" || quoted == L"0") return false;
    return def;
}

int JsonIntValue(const std::wstring& json, const std::wstring& key, int def = 0) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos) return def;
    try { return std::stoi(json.substr(pos)); } catch (...) { return def; }
}

bool JsonArrayContainsString(const std::wstring& json, const std::wstring& key, const std::wstring& expected) {
    size_t pos = FindValueStart(json, key);
    if (pos == std::wstring::npos || pos >= json.size() || json[pos] != L'[') return false;
    size_t end = json.find(L"]", pos);
    if (end == std::wstring::npos) return false;
    return json.substr(pos, end - pos + 1).find(L"\"" + expected + L"\"") != std::wstring::npos;
}

FileWorkflowResult ReadJsonFile(const std::wstring& path, std::wstring& json) {
    FileReadResult read = ReadTextFile(path);
    if (!read.ok) {
        return Failure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read file workflow JSON: " + read.error, L"{\"file\":" + JsonString(path) + L"}");
    }
    json = read.content;
    FileWorkflowResult ok;
    ok.ok = true;
    return ok;
}

FileWorkflowResult ResolveFromTaskJson(const std::wstring& json) {
    std::wstring filePath = JsonStringValue(json, L"file_path");
    std::wstring roots = JsonStringValue(json, L"allowed_roots");
    std::wstring extensions = JsonStringValue(json, L"extensions");
    long long maxBytes = JsonIntValue(json, L"max_bytes", 0);
    return ResolveFilePathForWorkflow(filePath, roots, extensions, maxBytes);
}

std::wstring RootListJson(const std::vector<std::wstring>& roots) {
    std::wstringstream ss;
    ss << L"[";
    for (size_t i = 0; i < roots.size(); ++i) {
        if (i != 0) ss << L",";
        ss << JsonString(roots[i]);
    }
    ss << L"]";
    return ss.str();
}

}  // namespace

FileWorkflowResult ResolveFilePathForWorkflow(
    const std::wstring& path,
    const std::wstring& allowedRoots,
    const std::wstring& extensions,
    long long maxBytes) {
    if (path.empty()) return Failure(L"INVALID_ARGUMENT", L"file-path-resolve requires --path.", L"{}");
    if (ContainsTraversal(path)) {
        return Failure(L"FILE_PATH_TRAVERSAL_DENIED", L"Path traversal segments are not allowed.", L"{\"path\":" + JsonString(path) + L"}");
    }

    std::wstring resolved = FullPath(ResolveMaybeProjectRelative(path));
    std::vector<std::wstring> roots;
    for (const auto& root : SplitList(allowedRoots, L';')) {
        roots.push_back(FullPath(ResolveMaybeProjectRelative(root)));
    }
    if (roots.empty()) {
        return Failure(
            L"FILE_ALLOWED_ROOTS_REQUIRED",
            L"File path resolution requires explicit allowed roots.",
            L"{\"metadata_only\":true,\"content_leaked\":false}");
    }

    bool underAllowedRoot = false;
    for (const auto& root : roots) {
        std::wstring prefix = root;
        if (!prefix.empty() && prefix.back() != L'\\') prefix += L"\\";
        if (Lower(resolved) == Lower(root) || StartsWith(resolved, prefix)) {
            underAllowedRoot = true;
            break;
        }
    }
    if (!underAllowedRoot) {
        return Failure(L"FILE_PATH_OUTSIDE_ALLOWED_ROOT", L"File path is outside allowed roots.", L"{\"path\":" + JsonString(resolved) + L",\"allowed_roots\":" + RootListJson(roots) + L"}");
    }

    DWORD attrs = GetFileAttributesW(resolved.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        return Failure(L"FILE_PICKER_FILE_NOT_FOUND", L"File does not exist or is a directory.", L"{\"path\":" + JsonString(resolved) + L"}");
    }

    std::wstring ext = ExtensionOf(resolved);
    std::vector<std::wstring> allowedExts = SplitList(extensions, L',');
    if (!allowedExts.empty()) {
        bool okExt = false;
        for (auto item : allowedExts) {
            item = Lower(Trim(item));
            if (!item.empty() && item[0] != L'.') item = L"." + item;
            if (item == ext) okExt = true;
        }
        if (!okExt) {
            return Failure(L"FILE_EXTENSION_DENIED", L"File extension is not allowed.", L"{\"extension\":" + JsonString(ext) + L"}");
        }
    }

    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (!GetFileAttributesExW(resolved.c_str(), GetFileExInfoStandard, &data)) {
        return Failure(L"FILE_METADATA_FAILED", L"Could not read file metadata.", L"{\"path\":" + JsonString(resolved) + L"}");
    }
    ULARGE_INTEGER size = {};
    size.HighPart = data.nFileSizeHigh;
    size.LowPart = data.nFileSizeLow;
    if (maxBytes > 0 && static_cast<long long>(size.QuadPart) > maxBytes) {
        return Failure(L"FILE_TOO_LARGE", L"File exceeds max_bytes policy.", L"{\"size_bytes\":" + std::to_wstring(size.QuadPart) + L",\"max_bytes\":" + std::to_wstring(maxBytes) + L"}");
    }

    std::wstring risk = (size.QuadPart <= 1024 * 1024 && (ext == L".txt" || ext == L".md" || ext == L".json")) ? L"low" : L"medium";
    std::wstringstream out;
    out << L"{\"schema_version\":\"5.5.1\""
        << L",\"resolved_path\":" << JsonString(resolved)
        << L",\"file_name\":" << JsonString(FileNameOf(resolved))
        << L",\"extension\":" << JsonString(ext)
        << L",\"exists\":true"
        << L",\"size_bytes\":" << size.QuadPart
        << L",\"under_allowed_root\":true"
        << L",\"file_action_risk\":" << JsonString(risk)
        << L",\"metadata_only\":true"
        << L",\"content_leaked\":false}";

    FileWorkflowResult result;
    result.ok = true;
    result.dataJson = out.str();
    return result;
}

FileWorkflowResult RunFilePickerFlowFile(const std::wstring& path) {
    std::wstring json;
    FileWorkflowResult read = ReadJsonFile(path, json);
    if (!read.ok) return read;

    bool pickerDetected = JsonBoolValue(json, L"picker_detected", false);
    bool pathInput = JsonBoolValue(json, L"path_input", false);
    bool openConfirmed = JsonBoolValue(json, L"open_confirmed", false);
    bool pickerClosed = JsonBoolValue(json, L"picker_closed", false);
    bool targetChanged = JsonBoolValue(json, L"target_app_changed", false);
    bool cancelled = JsonBoolValue(json, L"cancelled", false);
    bool timeout = JsonBoolValue(json, L"timeout", false);
    if (timeout) return Failure(L"FILE_PICKER_TIMEOUT", L"File picker flow timed out.", L"{\"flow\":" + JsonString(path) + L"}");
    if (cancelled) return Failure(L"FILE_PICKER_CANCELLED", L"File picker flow was cancelled.", L"{\"flow\":" + JsonString(path) + L"}");
    if (!pickerDetected) return Failure(L"FILE_PICKER_NOT_FOUND", L"File picker window was not detected.", L"{\"flow\":" + JsonString(path) + L"}");
    if (!pathInput || !openConfirmed) return Failure(L"FILE_PICKER_INPUT_FAILED", L"File picker path input or open confirmation failed.", L"{\"flow\":" + JsonString(path) + L"}");
    if (!pickerClosed && !targetChanged) return Failure(L"FILE_PICKER_CLOSE_VERIFY_FAILED", L"File picker did not close and target app did not change.", L"{\"flow\":" + JsonString(path) + L"}");

    std::wstringstream out;
    out << L"{\"schema_version\":\"5.5.2\""
        << L",\"flow_id\":" << JsonString(JsonStringValue(json, L"flow_id"))
        << L",\"parent_window\":" << JsonString(JsonStringValue(json, L"parent_window"))
        << L",\"picker_window\":" << JsonString(JsonStringValue(json, L"picker_window"))
        << L",\"file_path\":" << JsonString(JsonStringValue(json, L"file_path"))
        << L",\"picker_detected\":true"
        << L",\"path_input\":true"
        << L",\"open_confirmed\":true"
        << L",\"picker_closed\":" << (pickerClosed ? L"true" : L"false")
        << L",\"target_app_changed\":" << (targetChanged ? L"true" : L"false")
        << L",\"no_real_upload\":true}";
    FileWorkflowResult result;
    result.ok = true;
    result.dataJson = out.str();
    return result;
}

FileWorkflowResult VerifyAttachmentStateFile(
    const std::wstring& path,
    const std::wstring& expectedFile,
    int timeoutMs,
    int elapsedMs) {
    std::wstring json;
    FileWorkflowResult read = ReadJsonFile(path, json);
    if (!read.ok) return read;

    if (timeoutMs > 0 && elapsedMs >= timeoutMs && !JsonBoolValue(json, L"upload_completed", false) && !JsonBoolValue(json, L"upload_failed", false)) {
        return Failure(L"UPLOAD_VERIFICATION_TIMEOUT", L"Attachment upload verification timed out.", L"{\"state\":" + JsonString(path) + L"}");
    }
    std::wstring fileName = JsonStringValue(json, L"file_name");
    if (!expectedFile.empty() && Lower(fileName) != Lower(expectedFile)) {
        return Failure(L"UPLOAD_FILE_NAME_MISMATCH", L"Visible attachment file name did not match expected file.", L"{\"expected\":" + JsonString(expectedFile) + L",\"actual\":" + JsonString(fileName) + L"}");
    }
    if (JsonBoolValue(json, L"file_too_large", false)) return Failure(L"UPLOAD_FILE_TOO_LARGE", L"Attachment state reported file too large.", L"{\"file_name\":" + JsonString(fileName) + L"}");
    if (JsonBoolValue(json, L"upload_failed", false)) return Failure(L"UPLOAD_FAILED", L"Attachment state reported upload failed.", L"{\"file_name\":" + JsonString(fileName) + L",\"retry_shown\":" + (JsonBoolValue(json, L"retry_shown", false) ? L"true" : L"false") + L"}");
    if (!JsonBoolValue(json, L"file_name_visible", false) || !JsonBoolValue(json, L"upload_started", false) || !JsonBoolValue(json, L"spinner_detected", false) || !JsonBoolValue(json, L"spinner_gone", false) || !JsonBoolValue(json, L"upload_completed", false)) {
        return Failure(L"UPLOAD_NOT_COMPLETE", L"Attachment state did not reach completed state.", L"{\"file_name\":" + JsonString(fileName) + L"}");
    }

    std::wstringstream out;
    out << L"{\"schema_version\":\"5.5.3\""
        << L",\"file_name\":" << JsonString(fileName)
        << L",\"file_name_visible\":true"
        << L",\"upload_started\":true"
        << L",\"spinner_detected\":true"
        << L",\"progress_detected\":" << (JsonBoolValue(json, L"progress_detected", false) ? L"true" : L"false")
        << L",\"spinner_gone\":true"
        << L",\"upload_completed\":true"
        << L",\"upload_failed\":false"
        << L",\"retry_shown\":false"
        << L",\"no_real_send\":true}";
    FileWorkflowResult result;
    result.ok = true;
    result.dataJson = out.str();
    return result;
}

FileWorkflowResult CheckCrossWindowContextFile(const std::wstring& path) {
    std::wstring json;
    FileWorkflowResult read = ReadJsonFile(path, json);
    if (!read.ok) return read;

    if (JsonBoolValue(json, L"wrong_foreground", false) || !JsonBoolValue(json, L"foreground_verified", false)) {
        return Failure(L"CROSS_WINDOW_WRONG_FOREGROUND", L"Foreground did not return to the parent task window.", L"{\"context\":" + JsonString(path) + L"}");
    }
    if (!JsonBoolValue(json, L"returned_to_parent", false) || !JsonBoolValue(json, L"focus_restored", false)) {
        return Failure(L"CROSS_WINDOW_RETURN_FAILED", L"Cross-window context did not return to parent.", L"{\"context\":" + JsonString(path) + L"}");
    }
    bool windowChanged = JsonArrayContainsString(json, L"events", L"window_changed");
    std::wstringstream out;
    out << L"{\"schema_version\":\"5.5.4\""
        << L",\"context_id\":" << JsonString(JsonStringValue(json, L"context_id"))
        << L",\"parent_task_window\":" << JsonString(JsonStringValue(json, L"parent_task_window"))
        << L",\"child_dialog_window\":" << JsonString(JsonStringValue(json, L"child_dialog_window"))
        << L",\"returned_to_parent\":true"
        << L",\"foreground_verified\":true"
        << L",\"window_changed_event\":" << (windowChanged ? L"true" : L"false")
        << L",\"focus_restored\":true}";
    FileWorkflowResult result;
    result.ok = true;
    result.dataJson = out.str();
    return result;
}

FileWorkflowResult RunLocalMailAttachFlowFile(const std::wstring& path) {
    std::wstring json;
    FileWorkflowResult read = ReadJsonFile(path, json);
    if (!read.ok) return read;
    if (!JsonBoolValue(json, L"no_real_send", false)) {
        return Failure(L"REAL_SEND_BLOCKED", L"Local mail attach flow requires no_real_send=true.", L"{\"task\":" + JsonString(path) + L"}");
    }

    FileWorkflowResult resolved = ResolveFromTaskJson(json);
    if (!resolved.ok) return resolved;
    FileWorkflowResult picker = RunFilePickerFlowFile(ResolveMaybeProjectRelative(JsonStringValue(json, L"file_picker_flow")));
    if (!picker.ok) return picker;
    FileWorkflowResult upload = VerifyAttachmentStateFile(ResolveMaybeProjectRelative(JsonStringValue(json, L"upload_state")), FileNameOf(JsonStringValue(json, L"file_path")), 3000, 800);
    if (!upload.ok) return upload;
    FileWorkflowResult cross = CheckCrossWindowContextFile(ResolveMaybeProjectRelative(JsonStringValue(json, L"cross_window_context")));
    if (!cross.ok) return cross;

    std::wstringstream out;
    out << L"{\"schema_version\":\"5.5.6\""
        << L",\"task_id\":" << JsonString(JsonStringValue(json, L"task_id"))
        << L",\"template_id\":" << JsonString(JsonStringValue(json, L"template_id"))
        << L",\"file\":" << resolved.dataJson
        << L",\"file_picker\":" << picker.dataJson
        << L",\"upload\":" << upload.dataJson
        << L",\"cross_window\":" << cross.dataJson
        << L",\"upload_completed\":true"
        << L",\"no_real_send\":true"
        << L",\"real_email_sent\":false}";
    FileWorkflowResult result;
    result.ok = true;
    result.dataJson = out.str();
    return result;
}
