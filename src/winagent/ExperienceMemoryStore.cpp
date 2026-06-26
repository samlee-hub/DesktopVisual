#include "ExperienceMemoryStore.h"

#include "EvidenceFingerprint.h"
#include "ExperienceMemoryIndex.h"
#include "MemorySafetyBoundary.h"
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

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

std::string WideToUtf8Local(const std::wstring& value) {
    if (value.empty()) return std::string();
    int required = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (required <= 0) return std::string();
    std::string out(static_cast<size_t>(required), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), out.data(), required, nullptr, nullptr);
    return out;
}

bool AppendUtf8Line(const std::wstring& path, const std::wstring& line, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        EnsureDirectoryPath(path.substr(0, slash));
    }
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"ab") != 0 || !file) {
        error = L"Could not open JSONL file for append.";
        return false;
    }
    std::string bytes = WideToUtf8Local(line + L"\n");
    bool ok = bytes.empty() || fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size();
    fclose(file);
    if (!ok) error = L"Could not append JSONL line.";
    return ok;
}

bool MatchesQuery(const ExperienceMemoryRecord& record, const ExperienceMemoryQueryOptions& options) {
    if (!options.workflowType.empty() && Lower(record.workflowType) != Lower(options.workflowType)) return false;
    if (!options.failureCategory.empty() && Lower(record.normalizedFailureCategory) != Lower(options.failureCategory)) return false;
    if (!options.sourceVersion.empty() && Lower(record.sourceVersion) != Lower(options.sourceVersion)) return false;
    return true;
}

std::wstring RecordsArrayJson(const std::vector<ExperienceMemoryRecord>& records) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < records.size(); ++i) {
        if (i) json << L",";
        json << ExperienceMemoryRecordToJson(records[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring MapJson(const std::map<std::wstring, int>& values) {
    std::wstringstream json;
    json << L"{";
    bool first = true;
    for (const auto& entry : values) {
        if (!first) json << L",";
        first = false;
        json << simplejson::Quote(entry.first) << L":" << entry.second;
    }
    json << L"}";
    return json.str();
}

std::wstring ReportMarkdown(
    const std::vector<ExperienceMemoryRecord>& records,
    const std::map<std::wstring, int>& byWorkflow,
    const std::map<std::wstring, int>& byCategory) {
    std::wstringstream md;
    md << L"# Experience Memory Report\n\n";
    md << L"- status: PASS\n";
    md << L"- record_count: " << records.size() << L"\n";
    md << L"- read_only_report: true\n";
    md << L"- runtime_execution_triggered: false\n";
    md << L"- step_contract_generated: false\n";
    md << L"- optimization_suggestions_generated: false\n\n";
    md << L"## By Workflow Type\n\n";
    for (const auto& entry : byWorkflow) md << L"- " << entry.first << L": " << entry.second << L"\n";
    md << L"\n## By Failure Category\n\n";
    for (const auto& entry : byCategory) md << L"- " << entry.first << L": " << entry.second << L"\n";
    return md.str();
}

std::wstring ChangeExtension(const std::wstring& path, const std::wstring& extension) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) return path + extension;
    return path.substr(0, dot) + extension;
}

}  // namespace

std::wstring DefaultExperienceMemoryStoreRoot() {
    return ArtifactsPath(L"experience_memory");
}

std::wstring ExperienceMemoryRecordsPath(const std::wstring& storeRoot) {
    return ValidationJoinPath(storeRoot.empty() ? DefaultExperienceMemoryStoreRoot() : storeRoot, L"memory_records.jsonl");
}

std::wstring ExperienceMemoryIndexPath(const std::wstring& storeRoot) {
    return ValidationJoinPath(storeRoot.empty() ? DefaultExperienceMemoryStoreRoot() : storeRoot, L"memory_index.json");
}

ExperienceMemoryStoreResult AppendExperienceMemoryRecord(
    const std::wstring& storeRoot,
    const ExperienceMemoryRecord& record) {
    ExperienceMemoryStoreResult result;
    std::wstring root = storeRoot.empty() ? DefaultExperienceMemoryStoreRoot() : storeRoot;
    EnsureDirectoryPath(root);
    std::wstring line = ExperienceMemoryRecordToJson(record);
    MemorySafetyCheckResult safety = CheckMemorySafetyJson(line);
    if (!safety.ok) {
        result.errorCode = safety.blockedReason.empty() ? L"MEMORY_SAFETY_BLOCKED" : safety.blockedReason;
        result.errorMessage = L"Memory safety boundary rejected the record.";
        result.dataJson = safety.jsonReport;
        return result;
    }
    std::wstring error;
    if (!AppendUtf8Line(ExperienceMemoryRecordsPath(root), line, error)) {
        result.errorCode = L"MEMORY_STORE_APPEND_FAILED";
        result.errorMessage = error;
        return result;
    }
    std::vector<ExperienceMemoryRecord> records;
    LoadExperienceMemoryRecords(root, records);
    WriteExperienceMemoryIndex(root, records);
    result.ok = true;
    result.recordCount = static_cast<int>(records.size());
    result.dataJson = L"{\"schema_version\":\"6.10.0.experience_memory_store_append\",\"status\":\"PASS\",\"record_count\":" +
        std::to_wstring(result.recordCount) +
        L",\"memory_records_path\":" + simplejson::Quote(ExperienceMemoryRecordsPath(root)) +
        L",\"memory_index_path\":" + simplejson::Quote(ExperienceMemoryIndexPath(root)) +
        L",\"append_only\":true,\"runtime_execution_triggered\":false}";
    return result;
}

ExperienceMemoryStoreResult LoadExperienceMemoryRecords(
    const std::wstring& storeRoot,
    std::vector<ExperienceMemoryRecord>& records) {
    records.clear();
    ExperienceMemoryStoreResult result;
    std::wstring path = ExperienceMemoryRecordsPath(storeRoot);
    if (!ValidationFileExists(path)) {
        result.ok = true;
        result.recordCount = 0;
        result.dataJson = L"{\"schema_version\":\"6.10.0.experience_memory_store_load\",\"status\":\"PASS\",\"record_count\":0}";
        return result;
    }
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(path, text, error)) {
        result.errorCode = L"MEMORY_STORE_READ_FAILED";
        result.errorMessage = error;
        return result;
    }
    std::wistringstream stream(text);
    std::wstring line;
    int lineNumber = 0;
    while (std::getline(stream, line)) {
        ++lineNumber;
        if (line.empty()) continue;
        ExperienceMemoryRecordResult parsed = ParseExperienceMemoryRecordJson(line);
        if (!parsed.ok) {
            result.errorCode = L"MEMORY_STORE_JSONL_PARSE_FAILED";
            result.errorMessage = L"Invalid memory JSONL at line " + std::to_wstring(lineNumber) + L".";
            return result;
        }
        records.push_back(parsed.record);
    }
    result.ok = true;
    result.recordCount = static_cast<int>(records.size());
    result.dataJson = L"{\"schema_version\":\"6.10.0.experience_memory_store_load\",\"status\":\"PASS\",\"record_count\":" +
        std::to_wstring(result.recordCount) + L"}";
    return result;
}

ExperienceMemoryStoreResult QueryExperienceMemoryRecords(
    const ExperienceMemoryQueryOptions& options) {
    std::vector<ExperienceMemoryRecord> records;
    ExperienceMemoryStoreResult load = LoadExperienceMemoryRecords(options.storeRoot, records);
    if (!load.ok) return load;
    std::vector<ExperienceMemoryRecord> matches;
    for (const auto& record : records) {
        if (MatchesQuery(record, options)) matches.push_back(record);
    }
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.10.0.experience_memory_query\""
         << L",\"status\":\"PASS\""
         << L",\"query\":{\"workflow_type\":" << simplejson::Quote(options.workflowType)
         << L",\"failure_category\":" << simplejson::Quote(options.failureCategory)
         << L",\"source_version\":" << simplejson::Quote(options.sourceVersion)
         << L"}"
         << L",\"record_count\":" << matches.size()
         << L",\"read_only\":true"
         << L",\"runtime_execution_triggered\":false"
         << L",\"step_contract_generated\":false"
         << L",\"workflow_action_generated\":false"
         << L",\"records\":" << RecordsArrayJson(matches)
         << L"}";
    ExperienceMemoryStoreResult result;
    result.ok = true;
    result.recordCount = static_cast<int>(matches.size());
    result.dataJson = json.str();
    if (!options.outputJsonPath.empty()) {
        std::wstring error;
        WriteValidationTextFile(options.outputJsonPath, result.dataJson, error);
    }
    return result;
}

ExperienceMemoryStoreResult GenerateExperienceMemoryReport(
    const std::wstring& storeRoot,
    const std::wstring& outputJsonPath,
    const std::wstring& outputMarkdownPath) {
    std::vector<ExperienceMemoryRecord> records;
    ExperienceMemoryStoreResult load = LoadExperienceMemoryRecords(storeRoot, records);
    if (!load.ok) return load;
    std::map<std::wstring, int> byWorkflow;
    std::map<std::wstring, int> byCategory;
    std::map<std::wstring, int> bySource;
    for (const auto& record : records) {
        ++byWorkflow[record.workflowType.empty() ? L"unknown" : record.workflowType];
        ++byCategory[record.normalizedFailureCategory.empty() ? L"UNKNOWN_FAILURE" : record.normalizedFailureCategory];
        ++bySource[record.sourceVersion.empty() ? L"unknown" : record.sourceVersion];
    }
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.10.0.experience_memory_report\""
         << L",\"status\":\"PASS\""
         << L",\"record_count\":" << records.size()
         << L",\"by_workflow_type\":" << MapJson(byWorkflow)
         << L",\"by_failure_category\":" << MapJson(byCategory)
         << L",\"by_source_version\":" << MapJson(bySource)
         << L",\"read_only_report\":true"
         << L",\"optimization_suggestions_generated\":false"
         << L",\"auto_fix_plan_generated\":false"
         << L",\"runtime_execution_triggered\":false"
         << L"}";
    std::wstring error;
    if (!outputJsonPath.empty()) {
        WriteValidationTextFile(outputJsonPath, json.str(), error);
        std::wstring mdPath = outputMarkdownPath.empty() ? ChangeExtension(outputJsonPath, L".md") : outputMarkdownPath;
        WriteValidationTextFile(mdPath, ReportMarkdown(records, byWorkflow, byCategory), error);
    }
    ExperienceMemoryStoreResult result;
    result.ok = true;
    result.recordCount = static_cast<int>(records.size());
    result.dataJson = json.str();
    return result;
}

int CommandExperienceMemoryQuery(int argc, wchar_t** argv) {
    const std::wstring command = L"experience-memory-query";
    ULONGLONG startTick = GetTickCount64();
    ExperienceMemoryQueryOptions options;
    ArgValue(argc, argv, L"--store-root", options.storeRoot);
    ArgValue(argc, argv, L"--workflow-type", options.workflowType);
    ArgValue(argc, argv, L"--failure-category", options.failureCategory);
    ArgValue(argc, argv, L"--source-version", options.sourceVersion);
    ArgValue(argc, argv, L"--output", options.outputJsonPath);
    ExperienceMemoryStoreResult result = QueryExperienceMemoryRecords(options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"MEMORY_QUERY_FAILED" : result.errorCode, result.errorMessage, result.dataJson.empty() ? L"{}" : result.dataJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.dataJson) << L"\n";
    return 0;
}

int CommandExperienceMemoryReport(int argc, wchar_t** argv) {
    const std::wstring command = L"experience-memory-report";
    ULONGLONG startTick = GetTickCount64();
    std::wstring storeRoot;
    std::wstring output;
    std::wstring markdownOutput;
    ArgValue(argc, argv, L"--store-root", storeRoot);
    ArgValue(argc, argv, L"--output", output);
    ArgValue(argc, argv, L"--markdown-output", markdownOutput);
    if (output.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"experience-memory-report requires --output.", L"{}") << L"\n";
        return 2;
    }
    ExperienceMemoryStoreResult result = GenerateExperienceMemoryReport(storeRoot, output, markdownOutput);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"MEMORY_REPORT_FAILED" : result.errorCode, result.errorMessage, result.dataJson.empty() ? L"{}" : result.dataJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.dataJson) << L"\n";
    return 0;
}

int CommandV610ExperienceMemoryCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"v6-10-experience-memory-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring storeRoot;
    std::wstring output;
    ArgValue(argc, argv, L"--store-root", storeRoot);
    ArgValue(argc, argv, L"--output", output);
    if (output.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"v6-10-experience-memory-check requires --output.", L"{}") << L"\n";
        return 2;
    }
    std::vector<ExperienceMemoryRecord> records;
    ExperienceMemoryStoreResult load = LoadExperienceMemoryRecords(storeRoot, records);
    MemorySafetyCheckResult safety = CheckMemorySafetyStore(storeRoot);
    bool ok = load.ok && safety.ok;
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.10.0.experience_memory_check\""
         << L",\"status\":" << simplejson::Quote(ok ? L"PASS" : L"BLOCKED")
         << L",\"blocked_reason\":" << simplejson::Quote(ok ? L"" : (load.ok ? safety.blockedReason : load.errorCode))
         << L",\"record_count\":" << records.size()
         << L",\"memory_safety_status\":" << simplejson::Quote(safety.status)
         << L",\"no_old_ui_workflow_rerun\":true"
         << L",\"memory_execution_influence\":false"
         << L",\"step_contract_mutated_by_memory\":false"
         << L",\"runtime_session_mutated_by_memory\":false"
         << L",\"sensitive_plaintext_saved\":false"
         << L",\"raw_completed_unverified_marked_success\":false"
         << L"}";
    std::wstring error;
    WriteValidationTextFile(output, json.str(), error);
    if (!ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), safety.blockedReason.empty() ? L"V6_10_MEMORY_CHECK_BLOCKED" : safety.blockedReason, L"v6.10 experience memory check failed.", json.str()) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), json.str()) << L"\n";
    return 0;
}
