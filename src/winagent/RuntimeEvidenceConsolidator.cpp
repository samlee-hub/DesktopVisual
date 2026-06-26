#include "RuntimeEvidenceConsolidator.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct ArtifactRecord {
    std::wstring artifactPath;
    std::wstring artifactType;
    std::wstring versionId;
    std::wstring featureId;
    bool referencedByEvidenceIndex = false;
    bool safeToArchive = false;
    bool safeToDelete = false;
    std::wstring reason;
    unsigned long long sizeBytes = 0;
    std::wstring hash;
};

struct EvidenceIndexReference {
    std::wstring indexPath;
    std::wstring text;
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

std::wstring SlashPath(std::wstring value) {
    std::replace(value.begin(), value.end(), L'\\', L'/');
    return value;
}

std::wstring BasenameOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

std::wstring DirectoryOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return L"";
    if (slash == 2 && path.size() >= 3 && path[1] == L':') return path.substr(0, 3);
    return path.substr(0, slash);
}

std::wstring ChangeExtension(const std::wstring& path, const std::wstring& extension) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) {
        return path + extension;
    }
    return path.substr(0, dot) + extension;
}

unsigned long long FileSizeBytes(const std::wstring& path) {
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
        return 0;
    }
    ULARGE_INTEGER size = {};
    size.HighPart = data.nFileSizeHigh;
    size.LowPart = data.nFileSizeLow;
    return size.QuadPart;
}

std::wstring HashFile(const std::wstring& path) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        return ValidationHashText(L"missing:" + path);
    }
    unsigned long long hash = 1469598103934665603ull;
    unsigned char buffer[4096] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        for (size_t i = 0; i < read; ++i) {
            hash ^= static_cast<unsigned long long>(buffer[i]);
            hash *= 1099511628211ull;
        }
        if (read < sizeof(buffer)) break;
    }
    fclose(file);
    std::wstringstream stream;
    stream << L"fnv1a64:" << std::hex;
    stream.width(16);
    stream.fill(L'0');
    stream << hash;
    return stream.str();
}

void EnumerateFiles(const std::wstring& root, std::vector<std::wstring>& files) {
    std::wstring query = ValidationJoinPath(root, L"*");
    WIN32_FIND_DATAW data = {};
    HANDLE handle = FindFirstFileW(query.c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE) return;
    do {
        std::wstring name = data.cFileName;
        if (name == L"." || name == L"..") continue;
        std::wstring path = ValidationJoinPath(root, name);
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            EnumerateFiles(path, files);
        } else {
            files.push_back(ValidationNormalizePath(path));
        }
    } while (FindNextFileW(handle, &data));
    FindClose(handle);
}

void EnumerateImmediateDirectories(const std::wstring& root, std::vector<std::wstring>& dirs) {
    std::wstring query = ValidationJoinPath(root, L"*");
    WIN32_FIND_DATAW data = {};
    HANDLE handle = FindFirstFileW(query.c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE) return;
    do {
        std::wstring name = data.cFileName;
        if (name == L"." || name == L"..") continue;
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            dirs.push_back(ValidationJoinPath(root, name));
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
        normalizedPath[normalizedRoot.size()] == L'/') {
        return normalizedPath.substr(normalizedRoot.size() + 1);
    }
    return normalizedPath;
}

std::wstring ExtractVersionId(const std::wstring& path) {
    std::wstring lower = ValidationToLower(SlashPath(path));
    size_t pos = lower.find(L"dev");
    while (pos != std::wstring::npos) {
        size_t i = pos + 3;
        std::wstring version;
        while (i < lower.size()) {
            wchar_t ch = lower[i];
            if ((ch >= L'0' && ch <= L'9') || ch == L'.') {
                version.push_back(ch);
            } else if (ch == L'_') {
                version.push_back(L'.');
            } else {
                break;
            }
            ++i;
        }
        while (!version.empty() && version.back() == L'.') version.pop_back();
        if (!version.empty() && version.find(L'.') != std::wstring::npos) return version;
        pos = lower.find(L"dev", pos + 1);
    }
    return L"unknown";
}

std::wstring ExtractFeatureId(const std::wstring& root, const std::wstring& path) {
    std::wstring rel = RelativeToRoot(root, path);
    size_t slash = rel.find(L'/');
    std::wstring first = slash == std::wstring::npos ? rel : rel.substr(0, slash);
    if (first.empty()) return L"unknown";
    return first;
}

std::wstring ClassifyArtifact(const std::wstring& root, const std::wstring& path) {
    std::wstring lowerPath = ValidationToLower(SlashPath(path));
    std::wstring name = ValidationToLower(BasenameOf(path));
    if (name == L"final_status_report.md") return L"final_report";
    if (name == L"evidence_index.md") return L"evidence_index";
    if (name.find(L"acceptance_gate_report") != std::wstring::npos ||
        name.find(L"gate_report") != std::wstring::npos) return L"acceptance_gate_report";
    if (name.find(L"step_result") != std::wstring::npos || name == L"step_results.jsonl") return L"step_result";
    if (name.find(L"execution_result") != std::wstring::npos ||
        name.find(L"compiled_plan_execution_result") != std::wstring::npos) return L"execution_result";
    if (lowerPath.find(L"/runtime_sessions/") != std::wstring::npos ||
        name.rfind(L"rs-", 0) == 0) return L"runtime_session";
    if (name.find(L"full_regression") != std::wstring::npos &&
        name.find(L"result") != std::wstring::npos) return L"full_regression_result";
    if (name.find(L"selftest") != std::wstring::npos &&
        name.find(L"result") != std::wstring::npos) return L"selftest_result";
    if (name.find(L"screenshot") != std::wstring::npos ||
        name.rfind(L".png") != std::wstring::npos ||
        name.rfind(L".bmp") != std::wstring::npos ||
        name.rfind(L".jpg") != std::wstring::npos ||
        name.rfind(L".jpeg") != std::wstring::npos) return L"raw_screenshot";
    if (name.rfind(L".log") != std::wstring::npos ||
        name.find(L"stdout") != std::wstring::npos ||
        name.find(L"stderr") != std::wstring::npos) return L"temporary_log";
    if (lowerPath.find(L"/cache/") != std::wstring::npos ||
        name.find(L"cache") != std::wstring::npos) return L"cache";
    return L"unknown";
}

std::vector<EvidenceIndexReference> LoadEvidenceIndexes(const std::vector<std::wstring>& files) {
    std::vector<EvidenceIndexReference> indexes;
    for (const std::wstring& file : files) {
        if (ValidationToLower(BasenameOf(file)) != L"evidence_index.md") continue;
        std::wstring text;
        std::wstring error;
        ReadValidationTextFile(file, text, error);
        indexes.push_back({file, ValidationToLower(SlashPath(text))});
    }
    return indexes;
}

bool IsReferencedByEvidenceIndex(
    const std::wstring& root,
    const std::wstring& path,
    const std::vector<EvidenceIndexReference>& indexes) {
    std::wstring normalized = ValidationToLower(SlashPath(ValidationNormalizePath(path)));
    std::wstring rel = ValidationToLower(SlashPath(RelativeToRoot(root, path)));
    std::wstring artifactsRel = L"artifacts/" + rel;
    std::wstring name = ValidationToLower(BasenameOf(path));
    for (const auto& index : indexes) {
        if (ValidationToLower(SlashPath(index.indexPath)) == normalized) return true;
        if (index.text.find(normalized) != std::wstring::npos ||
            index.text.find(rel) != std::wstring::npos ||
            index.text.find(artifactsRel) != std::wstring::npos) {
            return true;
        }
        if (!name.empty() && index.text.find(name) != std::wstring::npos &&
            (name.rfind(L"rs-", 0) == 0 || name == L"final_status_report.md" || name.find(L"acceptance_gate") != std::wstring::npos)) {
            return true;
        }
    }
    return false;
}

ArtifactRecord BuildRecord(
    const std::wstring& root,
    const std::wstring& path,
    const std::vector<EvidenceIndexReference>& indexes) {
    ArtifactRecord record;
    record.artifactPath = ValidationNormalizePath(path);
    record.artifactType = ClassifyArtifact(root, path);
    record.versionId = ExtractVersionId(path);
    record.featureId = ExtractFeatureId(root, path);
    record.referencedByEvidenceIndex = IsReferencedByEvidenceIndex(root, path, indexes);
    record.sizeBytes = FileSizeBytes(path);
    record.hash = HashFile(path);

    if (record.artifactType == L"final_report" ||
        record.artifactType == L"acceptance_gate_report" ||
        record.artifactType == L"evidence_index") {
        record.safeToArchive = false;
        record.safeToDelete = false;
        record.reason = L"core evidence is permanently retained";
    } else if (record.artifactType == L"runtime_session") {
        record.safeToArchive = !record.referencedByEvidenceIndex;
        record.safeToDelete = false;
        record.reason = record.referencedByEvidenceIndex ? L"runtime session referenced by evidence index" : L"runtime session unreferenced; archive candidate only";
    } else if (record.artifactType == L"unknown") {
        record.safeToArchive = false;
        record.safeToDelete = false;
        record.reason = L"unknown artifact type is retained";
    } else if (record.artifactType == L"raw_screenshot" ||
               record.artifactType == L"temporary_log" ||
               record.artifactType == L"cache") {
        record.safeToArchive = !record.referencedByEvidenceIndex;
        record.safeToDelete = false;
        record.reason = record.referencedByEvidenceIndex ? L"referenced supporting artifact retained" : L"raw/support artifact archive candidate only";
    } else {
        record.safeToArchive = false;
        record.safeToDelete = false;
        record.reason = L"classified evidence retained";
    }
    return record;
}

std::wstring RecordToJson(const ArtifactRecord& record) {
    std::wstringstream json;
    json << L"{"
         << L"\"artifact_path\":" << simplejson::Quote(record.artifactPath)
         << L",\"artifact_type\":" << simplejson::Quote(record.artifactType)
         << L",\"version_id\":" << simplejson::Quote(record.versionId)
         << L",\"feature_id\":" << simplejson::Quote(record.featureId)
         << L",\"referenced_by_evidence_index\":" << simplejson::Bool(record.referencedByEvidenceIndex)
         << L",\"safe_to_archive\":" << simplejson::Bool(record.safeToArchive)
         << L",\"safe_to_delete\":" << simplejson::Bool(record.safeToDelete)
         << L",\"reason\":" << simplejson::Quote(record.reason)
         << L",\"size_bytes\":" << record.sizeBytes
         << L",\"hash\":" << simplejson::Quote(record.hash)
         << L"}";
    return json.str();
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring DuplicateGroupsJson(const std::map<std::wstring, std::vector<std::wstring>>& byHash) {
    std::wstringstream json;
    json << L"[";
    bool first = true;
    int group = 1;
    for (const auto& entry : byHash) {
        if (entry.second.size() < 2) continue;
        if (!first) json << L",";
        first = false;
        json << L"{\"duplicate_group_id\":\"session-dup-" << group++ << L"\",\"hash\":"
             << simplejson::Quote(entry.first) << L",\"paths\":" << StringArrayJson(entry.second) << L"}";
    }
    json << L"]";
    return json.str();
}

std::wstring BuildJsonReport(
    const std::wstring& root,
    const std::vector<ArtifactRecord>& records,
    const std::vector<std::wstring>& unreferencedSessions,
    const std::vector<std::wstring>& missingIndexes,
    const std::vector<std::wstring>& missingFinalStatus,
    const std::map<std::wstring, std::vector<std::wstring>>& duplicateSessions,
    const std::vector<std::wstring>& coreDeletable,
    int rawArtifactCount) {
    int sessionCount = 0;
    std::wstringstream inventory;
    inventory << L"[";
    for (size_t i = 0; i < records.size(); ++i) {
        if (i) inventory << L",";
        if (records[i].artifactType == L"runtime_session") ++sessionCount;
        inventory << RecordToJson(records[i]);
    }
    inventory << L"]";
    bool ok = coreDeletable.empty();
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.9.0.system_stabilization.evidence_consolidation\""
         << L",\"status\":" << simplejson::Quote(ok ? L"PASS" : L"BLOCKED")
         << L",\"blocked_reason\":" << simplejson::Quote(ok ? L"" : L"BLOCKED_CORE_EVIDENCE_MARKED_DELETABLE")
         << L",\"root\":" << simplejson::Quote(ValidationNormalizePath(root))
         << L",\"generated_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"artifact_count\":" << records.size()
         << L",\"runtime_session_count\":" << sessionCount
         << L",\"unreferenced_runtime_sessions\":" << StringArrayJson(unreferencedSessions)
         << L",\"missing_evidence_index_entries\":" << StringArrayJson(missingIndexes)
         << L",\"missing_final_status\":" << StringArrayJson(missingFinalStatus)
         << L",\"duplicate_session_evidence\":" << DuplicateGroupsJson(duplicateSessions)
         << L",\"raw_artifact_growth\":{\"raw_artifact_count\":" << rawArtifactCount
         << L",\"growth_detected\":" << simplejson::Bool(rawArtifactCount > 100)
         << L",\"policy\":\"archive-candidates-only-no-delete\"}"
         << L",\"core_evidence_marked_deletable\":" << StringArrayJson(coreDeletable)
         << L",\"safe_delete_policy\":\"final_report/evidence_index/acceptance_gate_report/unknown/runtime_session are never deleted by this module\""
         << L",\"ui_workflow_executed\":false"
         << L",\"inventory\":" << inventory.str()
         << L"}";
    return json.str();
}

std::wstring BuildMarkdownReport(
    const std::vector<ArtifactRecord>& records,
    const std::vector<std::wstring>& unreferencedSessions,
    const std::vector<std::wstring>& missingIndexes,
    const std::vector<std::wstring>& missingFinalStatus,
    int rawArtifactCount) {
    std::map<std::wstring, int> counts;
    for (const auto& record : records) ++counts[record.artifactType];
    std::wstringstream md;
    md << L"# Runtime Evidence Consolidation Report\n\n";
    md << L"- status: PASS\n";
    md << L"- artifact_count: " << records.size() << L"\n";
    md << L"- runtime_session_count: " << counts[L"runtime_session"] << L"\n";
    md << L"- unreferenced_runtime_sessions: " << unreferencedSessions.size() << L"\n";
    md << L"- missing_evidence_index_entries: " << missingIndexes.size() << L"\n";
    md << L"- missing_final_status: " << missingFinalStatus.size() << L"\n";
    md << L"- raw_artifact_count: " << rawArtifactCount << L"\n";
    md << L"- ui_workflow_executed: false\n\n";
    md << L"## Classification Counts\n\n";
    for (const auto& entry : counts) {
        md << L"- " << entry.first << L": " << entry.second << L"\n";
    }
    md << L"\n## Archive Policy\n\n";
    md << L"- Core reports, evidence indexes, acceptance gates, runtime sessions, and unknown artifacts are never marked safe_to_delete.\n";
    md << L"- Unreferenced runtime sessions may be marked safe_to_archive only.\n";
    return md.str();
}

std::vector<std::wstring> MissingVersionDirectories(const std::wstring& root, const std::wstring& fileName) {
    std::vector<std::wstring> dirs;
    std::vector<std::wstring> immediate;
    EnumerateImmediateDirectories(root, immediate);
    for (const auto& dir : immediate) {
        std::wstring name = ValidationToLower(BasenameOf(dir));
        if (name.rfind(L"dev", 0) != 0) continue;
        if (!ValidationFileExists(ValidationJoinPath(dir, fileName))) {
            dirs.push_back(dir);
        }
    }
    return dirs;
}

}  // namespace

RuntimeEvidenceConsolidationResult ConsolidateRuntimeEvidence(
    const RuntimeEvidenceConsolidationOptions& options) {
    RuntimeEvidenceConsolidationResult result;
    std::wstring root = options.rootPath.empty() ? ArtifactsPath() : ValidationNormalizePath(options.rootPath);
    if (!ValidationDirectoryExists(root)) {
        result.errorCode = L"ARTIFACT_ROOT_NOT_FOUND";
        result.errorMessage = L"Artifact root was not found.";
        result.status = L"BLOCKED";
        result.jsonReport = L"{\"schema_version\":\"6.9.0.system_stabilization.evidence_consolidation\",\"status\":\"BLOCKED\",\"blocked_reason\":\"ARTIFACT_ROOT_NOT_FOUND\"}";
        return result;
    }

    std::vector<std::wstring> files;
    EnumerateFiles(root, files);
    std::sort(files.begin(), files.end(), [](const std::wstring& a, const std::wstring& b) {
        return ValidationToLower(a) < ValidationToLower(b);
    });
    std::vector<EvidenceIndexReference> indexes = LoadEvidenceIndexes(files);
    std::vector<ArtifactRecord> records;
    std::vector<std::wstring> unreferencedSessions;
    std::vector<std::wstring> coreDeletable;
    std::map<std::wstring, std::vector<std::wstring>> duplicateSessions;
    int rawArtifactCount = 0;

    for (const auto& file : files) {
        ArtifactRecord record = BuildRecord(root, file, indexes);
        if (record.artifactType == L"runtime_session") {
            ++result.runtimeSessionCount;
            duplicateSessions[record.hash].push_back(record.artifactPath);
            if (!record.referencedByEvidenceIndex) {
                unreferencedSessions.push_back(record.artifactPath);
            }
        }
        if (record.artifactType == L"raw_screenshot" ||
            record.artifactType == L"temporary_log" ||
            record.artifactType == L"cache") {
            ++rawArtifactCount;
        }
        if ((record.artifactType == L"final_report" ||
             record.artifactType == L"acceptance_gate_report" ||
             record.artifactType == L"evidence_index") &&
            record.safeToDelete) {
            coreDeletable.push_back(record.artifactPath);
        }
        records.push_back(record);
    }

    std::vector<std::wstring> missingIndexes = MissingVersionDirectories(root, L"evidence_index.md");
    std::vector<std::wstring> missingFinalStatus = MissingVersionDirectories(root, L"final_status_report.md");
    result.artifactCount = static_cast<int>(records.size());
    result.unreferencedRuntimeSessions = unreferencedSessions;
    result.coreEvidenceMarkedDeletable = coreDeletable;
    result.ok = coreDeletable.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.errorCode = result.ok ? L"" : L"BLOCKED_CORE_EVIDENCE_MARKED_DELETABLE";
    result.jsonReport = BuildJsonReport(root, records, unreferencedSessions, missingIndexes, missingFinalStatus, duplicateSessions, coreDeletable, rawArtifactCount);
    result.markdownReport = BuildMarkdownReport(records, unreferencedSessions, missingIndexes, missingFinalStatus, rawArtifactCount);

    std::wstring error;
    if (!options.outputJsonPath.empty()) {
        WriteValidationTextFile(options.outputJsonPath, result.jsonReport, error);
        std::wstring mdPath = options.outputMarkdownPath.empty() ? ChangeExtension(options.outputJsonPath, L".md") : options.outputMarkdownPath;
        WriteValidationTextFile(mdPath, result.markdownReport, error);
    }
    return result;
}

int CommandEvidenceConsolidate(int argc, wchar_t** argv) {
    const std::wstring command = L"evidence-consolidate";
    ULONGLONG startTick = GetTickCount64();
    RuntimeEvidenceConsolidationOptions options;
    if (!ArgValue(argc, argv, L"--root", options.rootPath) ||
        !ArgValue(argc, argv, L"--output", options.outputJsonPath) ||
        options.rootPath.empty() || options.outputJsonPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"evidence-consolidate requires --root and --output.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--markdown-output", options.outputMarkdownPath);
    RuntimeEvidenceConsolidationResult result = ConsolidateRuntimeEvidence(options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EVIDENCE_CONSOLIDATION_FAILED" : result.errorCode, result.errorMessage, result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
