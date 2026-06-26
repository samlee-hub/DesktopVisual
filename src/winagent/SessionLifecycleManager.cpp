#include "SessionLifecycleManager.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct SessionRecord {
    std::wstring sessionId;
    std::wstring sessionFilePath;
    std::wstring createdAt;
    std::wstring linkedVersion;
    std::wstring linkedFeature;
    bool referencedByEvidence = false;
    std::wstring duplicateGroupId;
    bool stale = false;
    bool archiveRecommended = false;
    bool deleteRecommended = false;
    std::wstring reason;
    std::wstring hash;
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
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) return path + extension;
    return path.substr(0, dot) + extension;
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

std::wstring DetectArtifactsRoot(const std::wstring& runtimeSessionsRoot) {
    std::wstring name = ValidationToLower(BasenameOf(runtimeSessionsRoot));
    if (name == L"runtime_sessions") {
        return DirectoryOf(runtimeSessionsRoot);
    }
    return ArtifactsPath();
}

std::wstring ExtractVersionId(const std::wstring& path) {
    std::wstring lower = ValidationToLower(SlashPath(path));
    size_t pos = lower.find(L"dev");
    if (pos == std::wstring::npos) return L"unknown";
    size_t i = pos + 3;
    std::wstring version;
    while (i < lower.size()) {
        wchar_t ch = lower[i];
        if ((ch >= L'0' && ch <= L'9') || ch == L'.') version.push_back(ch);
        else if (ch == L'_') version.push_back(L'.');
        else break;
        ++i;
    }
    while (!version.empty() && version.back() == L'.') version.pop_back();
    return version.empty() ? L"unknown" : version;
}

std::wstring ExtractFeatureId(const std::wstring& artifactsRoot, const std::wstring& indexPath) {
    std::wstring normalizedRoot = ValidationToLower(SlashPath(ValidationNormalizePath(artifactsRoot)));
    std::wstring normalizedPath = SlashPath(ValidationNormalizePath(indexPath));
    std::wstring lowerPath = ValidationToLower(normalizedPath);
    if (lowerPath.size() > normalizedRoot.size() &&
        lowerPath.compare(0, normalizedRoot.size(), normalizedRoot) == 0 &&
        normalizedPath[normalizedRoot.size()] == L'/') {
        std::wstring rel = normalizedPath.substr(normalizedRoot.size() + 1);
        size_t slash = rel.find(L'/');
        return slash == std::wstring::npos ? rel : rel.substr(0, slash);
    }
    return L"unknown";
}

std::wstring SessionIdFromPath(const std::wstring& path) {
    std::wstring name = BasenameOf(path);
    size_t dot = name.find_last_of(L'.');
    if (dot != std::wstring::npos) name = name.substr(0, dot);
    return name;
}

bool FileOlderThanDays(const std::wstring& path, int days) {
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return false;
    ULARGE_INTEGER write = {};
    write.HighPart = data.ftLastWriteTime.dwHighDateTime;
    write.LowPart = data.ftLastWriteTime.dwLowDateTime;
    FILETIME nowFt = {};
    GetSystemTimeAsFileTime(&nowFt);
    ULARGE_INTEGER now = {};
    now.HighPart = nowFt.dwHighDateTime;
    now.LowPart = nowFt.dwLowDateTime;
    unsigned long long interval = static_cast<unsigned long long>(days) * 24ull * 60ull * 60ull * 10000000ull;
    return now.QuadPart > write.QuadPart && (now.QuadPart - write.QuadPart) > interval;
}

std::wstring GetJsonStringFromFile(const std::wstring& path, const std::wstring& key) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(path, text, error)) return L"";
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) return L"";
    return simplejson::GetString(parsed.root, key, L"");
}

struct ReferenceInfo {
    bool referenced = false;
    std::wstring version;
    std::wstring feature;
};

ReferenceInfo FindReference(
    const std::wstring& artifactsRoot,
    const std::wstring& sessionPath,
    const std::vector<std::wstring>& evidenceIndexes) {
    std::wstring name = ValidationToLower(BasenameOf(sessionPath));
    std::wstring normalized = ValidationToLower(SlashPath(ValidationNormalizePath(sessionPath)));
    ReferenceInfo info;
    for (const auto& index : evidenceIndexes) {
        std::wstring text;
        std::wstring error;
        ReadValidationTextFile(index, text, error);
        std::wstring lower = ValidationToLower(SlashPath(text));
        if (lower.find(name) != std::wstring::npos || lower.find(normalized) != std::wstring::npos) {
            info.referenced = true;
            info.version = ExtractVersionId(index);
            info.feature = ExtractFeatureId(artifactsRoot, index);
            return info;
        }
    }
    return info;
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

std::wstring SessionToJson(const SessionRecord& session) {
    std::wstringstream json;
    json << L"{"
         << L"\"session_id\":" << simplejson::Quote(session.sessionId)
         << L",\"session_file_path\":" << simplejson::Quote(session.sessionFilePath)
         << L",\"created_at\":" << simplejson::Quote(session.createdAt)
         << L",\"linked_version\":" << simplejson::Quote(session.linkedVersion)
         << L",\"linked_feature\":" << simplejson::Quote(session.linkedFeature)
         << L",\"referenced_by_evidence\":" << simplejson::Bool(session.referencedByEvidence)
         << L",\"duplicate_group_id\":" << simplejson::Quote(session.duplicateGroupId)
         << L",\"stale\":" << simplejson::Bool(session.stale)
         << L",\"archive_recommended\":" << simplejson::Bool(session.archiveRecommended)
         << L",\"delete_recommended\":" << simplejson::Bool(session.deleteRecommended)
         << L",\"reason\":" << simplejson::Quote(session.reason)
         << L"}";
    return json.str();
}

std::wstring ArchivePlanJson(const std::vector<SessionRecord>& sessions) {
    std::wstringstream json;
    json << L"[";
    bool first = true;
    for (const auto& session : sessions) {
        if (!session.archiveRecommended) continue;
        if (!first) json << L",";
        first = false;
        json << L"{\"session_id\":" << simplejson::Quote(session.sessionId)
             << L",\"source\":" << simplejson::Quote(session.sessionFilePath)
             << L",\"destination_root\":" << simplejson::Quote(ArtifactsPath(L"archive\\runtime_sessions"))
             << L",\"safe_to_archive\":true"
             << L",\"delete_recommended\":false"
             << L",\"reason\":" << simplejson::Quote(session.reason) << L"}";
    }
    json << L"]";
    return json.str();
}

std::wstring BuildJsonReport(const std::wstring& root, const std::vector<SessionRecord>& sessions) {
    int referenced = 0;
    int stale = 0;
    int unreferenced = 0;
    std::wstringstream items;
    items << L"[";
    for (size_t i = 0; i < sessions.size(); ++i) {
        if (i) items << L",";
        if (sessions[i].referencedByEvidence) ++referenced;
        else ++unreferenced;
        if (sessions[i].stale) ++stale;
        items << SessionToJson(sessions[i]);
    }
    items << L"]";
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.9.0.system_stabilization.session_lifecycle\""
         << L",\"status\":\"PASS\""
         << L",\"runtime_sessions_root\":" << simplejson::Quote(ValidationNormalizePath(root))
         << L",\"generated_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"session_count\":" << sessions.size()
         << L",\"referenced_session_count\":" << referenced
         << L",\"unreferenced_session_count\":" << unreferenced
         << L",\"stale_session_count\":" << stale
         << L",\"delete_recommended_count\":0"
         << L",\"archive_plan\":" << ArchivePlanJson(sessions)
         << L",\"ui_workflow_executed\":false"
         << L",\"sessions\":" << items.str()
         << L"}";
    return json.str();
}

std::wstring BuildMarkdownReport(const std::vector<SessionRecord>& sessions) {
    int referenced = 0;
    int archive = 0;
    int stale = 0;
    for (const auto& session : sessions) {
        if (session.referencedByEvidence) ++referenced;
        if (session.archiveRecommended) ++archive;
        if (session.stale) ++stale;
    }
    std::wstringstream md;
    md << L"# Runtime Session Lifecycle Report\n\n";
    md << L"- status: PASS\n";
    md << L"- session_count: " << sessions.size() << L"\n";
    md << L"- referenced_session_count: " << referenced << L"\n";
    md << L"- stale_session_count: " << stale << L"\n";
    md << L"- archive_recommended_count: " << archive << L"\n";
    md << L"- delete_recommended_count: 0\n";
    md << L"- ui_workflow_executed: false\n\n";
    md << L"Referenced sessions are retained. Unreferenced stale sessions can be archived only by an explicit archive operation.\n";
    return md.str();
}

}  // namespace

SessionLifecycleAuditResult AuditRuntimeSessionLifecycle(
    const SessionLifecycleAuditOptions& options) {
    SessionLifecycleAuditResult result;
    std::wstring root = options.runtimeSessionsRoot.empty() ? ArtifactsPath(L"runtime_sessions") : ValidationNormalizePath(options.runtimeSessionsRoot);
    if (!ValidationDirectoryExists(root)) {
        result.ok = true;
        result.status = L"PASS";
        result.jsonReport = L"{\"schema_version\":\"6.9.0.system_stabilization.session_lifecycle\",\"status\":\"PASS\",\"session_count\":0,\"sessions\":[],\"archive_plan\":[],\"ui_workflow_executed\":false}";
        result.markdownReport = L"# Runtime Session Lifecycle Report\n\n- status: PASS\n- session_count: 0\n";
        std::wstring error;
        if (!options.outputJsonPath.empty()) {
            WriteValidationTextFile(options.outputJsonPath, result.jsonReport, error);
            WriteValidationTextFile(options.outputMarkdownPath.empty() ? ChangeExtension(options.outputJsonPath, L".md") : options.outputMarkdownPath, result.markdownReport, error);
        }
        return result;
    }

    std::wstring artifactsRoot = DetectArtifactsRoot(root);
    std::vector<std::wstring> artifactFiles;
    EnumerateFiles(artifactsRoot, artifactFiles);
    std::vector<std::wstring> evidenceIndexes;
    for (const auto& file : artifactFiles) {
        if (ValidationToLower(BasenameOf(file)) == L"evidence_index.md") evidenceIndexes.push_back(file);
    }

    std::vector<std::wstring> sessionFiles;
    EnumerateFiles(root, sessionFiles);
    std::sort(sessionFiles.begin(), sessionFiles.end(), [](const std::wstring& a, const std::wstring& b) {
        return ValidationToLower(a) < ValidationToLower(b);
    });

    std::vector<SessionRecord> sessions;
    std::map<std::wstring, std::vector<size_t>> byHash;
    for (const auto& file : sessionFiles) {
        if (ValidationToLower(BasenameOf(file)).rfind(L"rs-", 0) != 0 &&
            ValidationToLower(BasenameOf(file)).find(L"session") == std::wstring::npos) {
            continue;
        }
        SessionRecord record;
        record.sessionFilePath = ValidationNormalizePath(file);
        record.hash = HashFile(file);
        record.sessionId = GetJsonStringFromFile(file, L"session_id");
        if (record.sessionId.empty()) record.sessionId = SessionIdFromPath(file);
        record.createdAt = GetJsonStringFromFile(file, L"session_created_at");
        if (record.createdAt.empty()) record.createdAt = GetJsonStringFromFile(file, L"created_at");
        ReferenceInfo ref = FindReference(artifactsRoot, file, evidenceIndexes);
        record.referencedByEvidence = ref.referenced;
        record.linkedVersion = ref.version.empty() ? L"unknown" : ref.version;
        record.linkedFeature = ref.feature.empty() ? L"unknown" : ref.feature;
        record.stale = !record.referencedByEvidence && FileOlderThanDays(file, 30);
        record.archiveRecommended = !record.referencedByEvidence && record.stale;
        record.deleteRecommended = false;
        record.reason = record.referencedByEvidence
            ? L"referenced by evidence index; retain"
            : (record.archiveRecommended ? L"unreferenced stale session; archive candidate only" : L"unreferenced but not stale or source unclear; retain");
        byHash[record.hash].push_back(sessions.size());
        sessions.push_back(record);
    }

    int duplicateGroup = 1;
    for (const auto& entry : byHash) {
        if (entry.second.size() < 2) continue;
        std::wstring groupId = L"session-dup-" + std::to_wstring(duplicateGroup++);
        for (size_t index : entry.second) {
            sessions[index].duplicateGroupId = groupId;
            if (!sessions[index].referencedByEvidence && sessions[index].stale) {
                sessions[index].archiveRecommended = true;
                sessions[index].reason = L"duplicate and stale unreferenced session; archive candidate only";
            }
        }
    }

    result.ok = true;
    result.status = L"PASS";
    result.sessionCount = static_cast<int>(sessions.size());
    for (const auto& session : sessions) {
        if (!session.referencedByEvidence) ++result.unreferencedCount;
    }
    result.jsonReport = BuildJsonReport(root, sessions);
    result.markdownReport = BuildMarkdownReport(sessions);
    std::wstring error;
    if (!options.outputJsonPath.empty()) {
        WriteValidationTextFile(options.outputJsonPath, result.jsonReport, error);
        WriteValidationTextFile(options.outputMarkdownPath.empty() ? ChangeExtension(options.outputJsonPath, L".md") : options.outputMarkdownPath, result.markdownReport, error);
    }
    return result;
}

int CommandSessionLifecycleAudit(int argc, wchar_t** argv) {
    const std::wstring command = L"session-lifecycle-audit";
    ULONGLONG startTick = GetTickCount64();
    SessionLifecycleAuditOptions options;
    if (!ArgValue(argc, argv, L"--root", options.runtimeSessionsRoot) ||
        !ArgValue(argc, argv, L"--output", options.outputJsonPath) ||
        options.runtimeSessionsRoot.empty() || options.outputJsonPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"session-lifecycle-audit requires --root and --output.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--markdown-output", options.outputMarkdownPath);
    SessionLifecycleAuditResult result = AuditRuntimeSessionLifecycle(options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"SESSION_LIFECYCLE_AUDIT_FAILED" : result.errorCode, result.errorMessage, result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
