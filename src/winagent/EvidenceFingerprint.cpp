#include "EvidenceFingerprint.h"

#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

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
    UINT codePage = CP_UTF8;
    if (required <= 0) {
        codePage = CP_ACP;
        required = MultiByteToWideChar(codePage, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    }
    if (required <= 0) return L"";
    std::wstring result(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(codePage, 0, value.data(), static_cast<int>(value.size()), result.data(), required);
    return result;
}

uint64_t FnvaInit() {
    return 1469598103934665603ull;
}

void FnvaUpdate(uint64_t& hash, const unsigned char* data, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        hash ^= static_cast<uint64_t>(data[i]);
        hash *= 1099511628211ull;
    }
}

std::wstring HashHex(uint64_t hash) {
    std::wstringstream stream;
    stream << L"fnv1a64:" << std::hex << std::setw(16) << std::setfill(L'0') << hash;
    return stream.str();
}

std::wstring HashBinaryFile(const std::wstring& path) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        return ValidationHashText(L"missing:" + path);
    }
    uint64_t hash = FnvaInit();
    unsigned char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) {
            FnvaUpdate(hash, buffer, read);
        }
        if (read < sizeof(buffer)) {
            break;
        }
    }
    fclose(file);
    return HashHex(hash);
}

uint64_t FileLength(const std::wstring& path) {
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
        return 0;
    }
    ULARGE_INTEGER size = {};
    size.HighPart = data.nFileSizeHigh;
    size.LowPart = data.nFileSizeLow;
    return size.QuadPart;
}

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && (iswspace(value[first]) || value[first] == 0xfeff)) ++first;
    size_t last = value.size();
    while (last > first && iswspace(value[last - 1])) --last;
    return value.substr(first, last - first);
}

std::wstring SlashPath(std::wstring value) {
    std::replace(value.begin(), value.end(), L'\\', L'/');
    return value;
}

std::wstring DirectoryOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return L"";
    if (slash == 2 && path.size() >= 3 && path[1] == L':') return path.substr(0, 3);
    return path.substr(0, slash);
}

std::wstring BasenameOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return path;
    return path.substr(slash + 1);
}

void EnumerateFiles(const std::wstring& root, std::vector<std::wstring>& files) {
    std::wstring query = ValidationJoinPath(root, L"*");
    WIN32_FIND_DATAW data = {};
    HANDLE handle = FindFirstFileW(query.c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE) {
        return;
    }
    do {
        std::wstring name = data.cFileName;
        if (name == L"." || name == L"..") {
            continue;
        }
        std::wstring path = ValidationJoinPath(root, name);
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            EnumerateFiles(path, files);
        } else {
            files.push_back(ValidationNormalizePath(path));
        }
    } while (FindNextFileW(handle, &data));
    FindClose(handle);
}

std::wstring RelativeToRoot(const std::wstring& root, const std::wstring& path) {
    std::wstring normalizedRoot = SlashPath(ValidationNormalizePath(root));
    std::wstring normalizedPath = SlashPath(ValidationNormalizePath(path));
    std::wstring lowerRoot = ValidationToLower(normalizedRoot);
    std::wstring lowerPath = ValidationToLower(normalizedPath);
    if (lowerPath.size() > lowerRoot.size() &&
        lowerPath.compare(0, lowerRoot.size(), lowerRoot) == 0 &&
        (normalizedPath[normalizedRoot.size()] == L'/' || normalizedPath[normalizedRoot.size()] == L'\\')) {
        return normalizedPath.substr(normalizedRoot.size() + 1);
    }
    return BasenameOf(normalizedPath);
}

std::wstring BuildManifest(const std::wstring& evidencePath) {
    std::wstringstream manifest;
    std::wstring normalized = ValidationNormalizePath(evidencePath);
    if (ValidationDirectoryExists(normalized)) {
        std::vector<std::wstring> files;
        EnumerateFiles(normalized, files);
        std::sort(files.begin(), files.end(), [](const std::wstring& a, const std::wstring& b) {
            return ValidationToLower(a) < ValidationToLower(b);
        });
        for (const std::wstring& file : files) {
            manifest << SlashPath(RelativeToRoot(normalized, file)) << L"|"
                     << FileLength(file) << L"|"
                     << HashBinaryFile(file) << L"\n";
        }
    } else if (ValidationFileExists(normalized)) {
        manifest << BasenameOf(normalized) << L"|"
                 << FileLength(normalized) << L"|"
                 << HashBinaryFile(normalized) << L"\n";
    }
    return manifest.str();
}

std::wstring ResolveEvidenceFile(const std::wstring& evidencePath, const std::wstring& relativePath) {
    if (relativePath.size() >= 2 && relativePath[1] == L':') {
        return ValidationNormalizePath(relativePath);
    }
    std::wstring normalizedRel = relativePath;
    std::replace(normalizedRel.begin(), normalizedRel.end(), L'/', L'\\');
    std::wstring lower = ValidationToLower(SlashPath(normalizedRel));
    if (lower.rfind(L"artifacts/", 0) == 0 || lower.rfind(L"src/", 0) == 0 || lower.rfind(L"docs/", 0) == 0) {
        return ProjectPath(normalizedRel);
    }
    if (ValidationDirectoryExists(evidencePath)) {
        return ValidationJoinPath(evidencePath, normalizedRel);
    }
    return ValidationNormalizePath(normalizedRel);
}

std::wstring HashEvidenceSet(
    const std::wstring& evidencePath,
    const std::vector<std::wstring>& candidates,
    const std::wstring& fallbackSeed) {
    std::wstringstream combined;
    for (const std::wstring& candidate : candidates) {
        std::wstring path = ResolveEvidenceFile(evidencePath, candidate);
        if (!ValidationFileExists(path)) {
            continue;
        }
        std::wstring text;
        std::wstring error;
        ReadValidationTextFile(path, text, error);
        combined << L"FILE:" << SlashPath(candidate) << L"\n";
        combined << L"HASH:" << HashBinaryFile(path) << L"\n";
        combined << L"TEXT:" << text << L"\n";
    }
    std::wstring value = combined.str();
    if (value.empty()) {
        value = L"fallback:" + fallbackSeed + L":" + BuildManifest(evidencePath);
    }
    return ValidationHashText(value);
}

std::vector<std::wstring> FeatureCandidates(const std::wstring& featureId, const std::wstring& section) {
    if (featureId == L"v6_7_explorer_move_file") {
        if (section == L"input") return { L"acceptance/runner/case_04_move_file/workflow.json" };
        if (section == L"contract") return { L"acceptance/runner/case_04_move_file/evidence/step_contract.json" };
        if (section == L"execution") return { L"acceptance/runner/case_04_move_file/result.json", L"acceptance/runner/case_04_move_file/evidence/execution_result.json" };
        if (section == L"verification") return { L"move_file_repair_report.md", L"explorer_verification_report.md", L"v6_7_0_rerun_acceptance_gate_report.md" };
        if (section == L"final") return { L"final_status_report.md" };
    }
    if (featureId == L"v6_7_explorer_scroll_and_locate") {
        if (section == L"input") return { L"acceptance/runner/case_06_scroll_and_locate/workflow.json" };
        if (section == L"contract") return { L"acceptance/runner/case_06_scroll_and_locate/evidence/step_contract.json" };
        if (section == L"execution") return { L"acceptance/runner/case_06_scroll_and_locate/result.json", L"acceptance/runner/case_06_scroll_and_locate/evidence/execution_result.json" };
        if (section == L"verification") return { L"scroll_and_locate_repair_report.md", L"explorer_verification_report.md", L"v6_7_0_rerun_acceptance_gate_report.md" };
        if (section == L"final") return { L"final_status_report.md" };
    }
    if (featureId == L"v6_7_explorer_full_regression") {
        if (section == L"input") return { L"agent_context_digest.md", L"evidence_index.md" };
        if (section == L"contract") return { L"targeted_rerun_report.md", L"positive_explorer_cases_report.md" };
        if (section == L"execution") return { L"full_regression_rerun_result.json", L"full_regression_rerun_report.md" };
        if (section == L"verification") return { L"v6_7_0_rerun_acceptance_gate_report.md", L"explorer_verification_report.md" };
        if (section == L"final") return { L"final_status_report.md" };
    }
    if (section == L"input") return { L"agent_context_digest.md", L"evidence_index.md" };
    if (section == L"contract") return { L"acceptance_gate_report.md", L"gate_report.md" };
    if (section == L"execution") return { L"result.json", L"full_regression_result.json" };
    if (section == L"verification") return { L"verification_report.md", L"acceptance_gate_report.md" };
    if (section == L"final") return { L"final_status_report.md" };
    return {};
}

}  // namespace

bool ValidationFileExists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool ValidationDirectoryExists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool ReadValidationTextFile(const std::wstring& path, std::wstring& text, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        error = L"Could not open file.";
        return false;
    }
    std::string bytes;
    char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) {
            bytes.append(buffer, read);
        }
        if (read < sizeof(buffer)) {
            break;
        }
    }
    fclose(file);
    text = Utf8ToWide(bytes);
    if (!text.empty() && text[0] == 0xfeff) {
        text.erase(text.begin());
    }
    return true;
}

bool WriteValidationTextFile(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        EnsureDirectoryPath(path.substr(0, slash));
    }
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

std::wstring ValidationNormalizePath(const std::wstring& path) {
    DWORD required = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (required == 0) return path;
    std::wstring buffer(required, L'\0');
    DWORD written = GetFullPathNameW(path.c_str(), required, buffer.data(), nullptr);
    if (written == 0 || written >= required) return path;
    buffer.resize(written);
    return buffer;
}

std::wstring ValidationJoinPath(const std::wstring& root, const std::wstring& child) {
    if (child.empty()) return ValidationNormalizePath(root);
    if (child.size() >= 2 && child[1] == L':') return ValidationNormalizePath(child);
    if (!child.empty() && (child[0] == L'\\' || child[0] == L'/')) return ValidationNormalizePath(child);
    std::wstring separator = (root.empty() || root.back() == L'\\' || root.back() == L'/') ? L"" : L"\\";
    return ValidationNormalizePath(root + separator + child);
}

std::wstring ValidationToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool ValidationContainsNoCase(const std::wstring& text, const std::wstring& needle) {
    return ValidationToLower(text).find(ValidationToLower(needle)) != std::wstring::npos;
}

std::wstring ValidationHashText(const std::wstring& text) {
    std::string bytes = WideToUtf8(text);
    uint64_t hash = FnvaInit();
    if (!bytes.empty()) {
        FnvaUpdate(hash, reinterpret_cast<const unsigned char*>(bytes.data()), bytes.size());
    }
    return HashHex(hash);
}

std::wstring ValidationJsonArray(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

bool IsSupportedEvidenceFeature(const std::wstring& featureId) {
    static const std::vector<std::wstring> features = {
        L"v6_7_explorer_move_file",
        L"v6_7_explorer_scroll_and_locate",
        L"v6_7_explorer_full_regression",
        L"v6_6_vlm_candidate_gate",
        L"v6_5_vlm_observation_gate",
        L"v6_4_runtime_execution_gate",
        L"v6_3_plan_compiler_gate",
        L"v6_2_session_gate"
    };
    return std::find(features.begin(), features.end(), featureId) != features.end();
}

std::wstring EvidenceFeatureVersion(const std::wstring& featureId) {
    if (featureId.rfind(L"v6_7_", 0) == 0) return L"6.7.0";
    if (featureId.rfind(L"v6_6_", 0) == 0) return L"6.6.0";
    if (featureId.rfind(L"v6_5_", 0) == 0) return L"6.5.0";
    if (featureId.rfind(L"v6_4_", 0) == 0) return L"6.4.0";
    if (featureId.rfind(L"v6_3_", 0) == 0) return L"6.3.0";
    if (featureId.rfind(L"v6_2_", 0) == 0) return L"6.2.0";
    return L"unknown";
}

EvidenceFingerprintResult CreateEvidenceFingerprint(
    const std::wstring& featureId,
    const std::wstring& evidencePath) {
    EvidenceFingerprintResult result;
    if (!IsSupportedEvidenceFeature(featureId)) {
        result.errorCode = L"UNSUPPORTED_FEATURE";
        result.errorMessage = L"validation-fingerprint feature is not supported.";
        return result;
    }

    std::wstring normalizedEvidence = ValidationNormalizePath(evidencePath);
    if (!ValidationFileExists(normalizedEvidence) && !ValidationDirectoryExists(normalizedEvidence)) {
        result.errorCode = L"EVIDENCE_NOT_FOUND";
        result.errorMessage = L"Evidence source path was not found.";
        return result;
    }

    std::wstring manifest = BuildManifest(normalizedEvidence);
    EvidenceFingerprint fingerprint;
    fingerprint.featureId = featureId;
    fingerprint.featureVersion = EvidenceFeatureVersion(featureId);
    fingerprint.evidenceSourcePath = normalizedEvidence;
    fingerprint.artifactManifestHash = ValidationHashText(manifest);
    fingerprint.inputSpecHash = HashEvidenceSet(normalizedEvidence, FeatureCandidates(featureId, L"input"), L"input:" + featureId);
    fingerprint.stepContractHash = HashEvidenceSet(normalizedEvidence, FeatureCandidates(featureId, L"contract"), L"contract:" + featureId);
    fingerprint.executionSummaryHash = HashEvidenceSet(normalizedEvidence, FeatureCandidates(featureId, L"execution"), L"execution:" + featureId);
    fingerprint.verificationSummaryHash = HashEvidenceSet(normalizedEvidence, FeatureCandidates(featureId, L"verification"), L"verification:" + featureId);
    fingerprint.finalStatusHash = HashEvidenceSet(normalizedEvidence, FeatureCandidates(featureId, L"final"), L"final:" + featureId);
    fingerprint.createdAt = NowTimestamp();
    fingerprint.fingerprintVersion = L"6.8.0-preflight.validation_fingerprint.v1";
    fingerprint.fingerprintStatus = L"PASS";
    fingerprint.fingerprintOk = true;
    fingerprint.uiWorkflowExecuted = false;
    fingerprint.fingerprintIsExecutionResult = false;
    fingerprint.fingerprintId = featureId + L":" + fingerprint.featureVersion + L":" + fingerprint.artifactManifestHash;

    result.ok = true;
    result.fingerprint = fingerprint;
    result.fingerprintJson = EvidenceFingerprintToJson(fingerprint);
    return result;
}

std::wstring EvidenceFingerprintToJson(const EvidenceFingerprint& fingerprint) {
    std::wstringstream json;
    json << L"{"
         << L"\"fingerprint_id\":" << simplejson::Quote(fingerprint.fingerprintId)
         << L",\"feature_id\":" << simplejson::Quote(fingerprint.featureId)
         << L",\"feature_version\":" << simplejson::Quote(fingerprint.featureVersion)
         << L",\"evidence_source_path\":" << simplejson::Quote(fingerprint.evidenceSourcePath)
         << L",\"input_spec_hash\":" << simplejson::Quote(fingerprint.inputSpecHash)
         << L",\"step_contract_hash\":" << simplejson::Quote(fingerprint.stepContractHash)
         << L",\"execution_summary_hash\":" << simplejson::Quote(fingerprint.executionSummaryHash)
         << L",\"verification_summary_hash\":" << simplejson::Quote(fingerprint.verificationSummaryHash)
         << L",\"final_status_hash\":" << simplejson::Quote(fingerprint.finalStatusHash)
         << L",\"artifact_manifest_hash\":" << simplejson::Quote(fingerprint.artifactManifestHash)
         << L",\"created_at\":" << simplejson::Quote(fingerprint.createdAt)
         << L",\"fingerprint_version\":" << simplejson::Quote(fingerprint.fingerprintVersion)
         << L",\"fingerprint_status\":" << simplejson::Quote(fingerprint.fingerprintStatus)
         << L",\"fingerprint_ok\":" << simplejson::Bool(fingerprint.fingerprintOk)
         << L",\"ui_workflow_executed\":" << simplejson::Bool(fingerprint.uiWorkflowExecuted)
         << L",\"fingerprint_is_execution_result\":" << simplejson::Bool(fingerprint.fingerprintIsExecutionResult)
         << L"}";
    return json.str();
}

int CommandValidationFingerprint(int argc, wchar_t** argv) {
    const std::wstring command = L"validation-fingerprint";
    ULONGLONG startTick = GetTickCount64();
    std::wstring featureId;
    std::wstring evidencePath;
    std::wstring outputPath;
    if (!ArgValue(argc, argv, L"--feature", featureId) ||
        !ArgValue(argc, argv, L"--evidence", evidencePath) ||
        !ArgValue(argc, argv, L"--output", outputPath) ||
        featureId.empty() || evidencePath.empty() || outputPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"validation-fingerprint requires --feature, --evidence, and --output.", L"{}") << L"\n";
        return 2;
    }

    EvidenceFingerprintResult result = CreateEvidenceFingerprint(featureId, evidencePath);
    if (!result.ok) {
        std::wstring data = L"{\"feature_id\":" + simplejson::Quote(featureId)
            + L",\"evidence_source_path\":" + simplejson::Quote(evidencePath)
            + L",\"ui_workflow_executed\":false}";
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FINGERPRINT_FAILED" : result.errorCode, result.errorMessage, data) << L"\n";
        return 1;
    }

    std::wstring error;
    if (!WriteValidationTextFile(outputPath, result.fingerprintJson, error)) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"OUTPUT_WRITE_FAILED", error, result.fingerprintJson) << L"\n";
        return 1;
    }

    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.fingerprintJson) << L"\n";
    return 0;
}
