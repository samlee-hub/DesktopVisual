#include "WorkflowTemplateRegistry.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <iostream>
#include <map>
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
    if (slash != std::wstring::npos) EnsureDirectoryPath(path.substr(0, slash));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"ab") != 0 || !file) {
        error = L"Could not open audit JSONL file.";
        return false;
    }
    std::string bytes = WideToUtf8Local(line + L"\n");
    bool ok = bytes.empty() || fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size();
    fclose(file);
    if (!ok) error = L"Could not append audit JSONL line.";
    return ok;
}

std::wstring TemplatesArrayJson(const std::vector<WorkflowTemplateRecord>& records) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < records.size(); ++i) {
        if (i) json << L",";
        json << WorkflowTemplateRecordToJson(records[i]);
    }
    json << L"]";
    return json.str();
}

WorkflowTemplateRegistryResult Fail(const std::wstring& code, const std::wstring& message) {
    WorkflowTemplateRegistryResult result;
    result.errorCode = code;
    result.errorMessage = message;
    return result;
}

std::wstring RegistryJson(const std::vector<WorkflowTemplateRecord>& records) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.workflow_template_registry\""
         << L",\"updated_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"storage\":\"local_json\""
         << L",\"external_database_used\":false"
         << L",\"templates\":" << TemplatesArrayJson(records)
         << L"}";
    return json.str();
}

void Upsert(std::vector<WorkflowTemplateRecord>& records, const WorkflowTemplateRecord& record) {
    for (auto& existing : records) {
        if (existing.templateId == record.templateId &&
            existing.templateVersion == record.templateVersion) {
            existing = record;
            return;
        }
    }
    records.push_back(record);
}

std::wstring AuditRecordJson(const WorkflowTemplateRecord& record, const std::wstring& action) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.workflow_template_registry_audit\""
         << L",\"timestamp\":" << simplejson::Quote(NowTimestamp())
         << L",\"action\":" << simplejson::Quote(action)
         << L",\"template_id\":" << simplejson::Quote(record.templateId)
         << L",\"template_version\":" << simplejson::Quote(record.templateVersion)
         << L",\"template_status\":" << simplejson::Quote(record.templateStatus)
         << L",\"template_hash\":" << simplejson::Quote(record.templateHash)
         << L"}";
    return json.str();
}

WorkflowTemplateRegistryResult Persist(const std::wstring& registryRoot, const std::vector<WorkflowTemplateRecord>& records, const WorkflowTemplateRecord& record, const std::wstring& action) {
    std::wstring root = registryRoot.empty() ? DefaultWorkflowTemplateRegistryRoot() : registryRoot;
    EnsureDirectoryPath(root);
    std::wstring error;
    std::wstring registryJson = RegistryJson(records);
    if (!WriteValidationTextFile(WorkflowTemplateRegistryPath(root), registryJson, error)) {
        return Fail(L"WORKFLOW_TEMPLATE_REGISTRY_WRITE_FAILED", error);
    }
    if (!AppendUtf8Line(WorkflowTemplateAuditPath(root), AuditRecordJson(record, action), error)) {
        return Fail(L"WORKFLOW_TEMPLATE_REGISTRY_AUDIT_FAILED", error);
    }
    WorkflowTemplateRegistryResult result;
    result.ok = true;
    result.templates = records;
    result.dataJson = L"{\"schema_version\":\"6.11.0.workflow_template_registry_update\""
        L",\"status\":\"PASS\""
        L",\"action\":" + simplejson::Quote(action) +
        L",\"template_id\":" + simplejson::Quote(record.templateId) +
        L",\"template_status\":" + simplejson::Quote(record.templateStatus) +
        L",\"template_hash\":" + simplejson::Quote(record.templateHash) +
        L",\"registry_path\":" + simplejson::Quote(WorkflowTemplateRegistryPath(root)) +
        L",\"audit_path\":" + simplejson::Quote(WorkflowTemplateAuditPath(root)) +
        L",\"external_database_used\":false}";
    return result;
}

std::wstring ReportMarkdown(
    const std::map<std::wstring, int>& byStatus,
    const std::map<std::wstring, int>& byType,
    int total) {
    std::wstringstream md;
    md << L"# Workflow Template Registry Report\n\n";
    md << L"- status: PASS\n";
    md << L"- total_templates: " << total << L"\n";
    md << L"- candidate: " << byStatus.at(L"candidate") << L"\n";
    md << L"- validated: " << byStatus.at(L"validated") << L"\n";
    md << L"- rejected: " << byStatus.at(L"rejected") << L"\n";
    md << L"- deprecated: " << byStatus.at(L"deprecated") << L"\n";
    md << L"- external_database_used: false\n\n";
    md << L"## By Workflow Type\n\n";
    for (const auto& entry : byType) md << L"- " << entry.first << L": " << entry.second << L"\n";
    return md.str();
}

}  // namespace

std::wstring WorkflowTemplateRegistryPath(const std::wstring& registryRoot) {
    return ValidationJoinPath(registryRoot.empty() ? DefaultWorkflowTemplateRegistryRoot() : registryRoot, L"template_registry.json");
}

std::wstring WorkflowTemplateAuditPath(const std::wstring& registryRoot) {
    return ValidationJoinPath(registryRoot.empty() ? DefaultWorkflowTemplateRegistryRoot() : registryRoot, L"template_registry_audit.jsonl");
}

WorkflowTemplateRegistryResult LoadWorkflowTemplateRegistry(const std::wstring& registryRoot) {
    std::wstring path = WorkflowTemplateRegistryPath(registryRoot);
    WorkflowTemplateRegistryResult result;
    if (!ValidationFileExists(path)) {
        result.ok = true;
        result.dataJson = RegistryJson({});
        return result;
    }
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(path, text, error)) {
        return Fail(L"WORKFLOW_TEMPLATE_REGISTRY_READ_FAILED", error);
    }
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return Fail(L"WORKFLOW_TEMPLATE_REGISTRY_PARSE_FAILED", parsed.ok ? L"Registry JSON must be an object." : parsed.error);
    }
    const simplejson::Value* templates = simplejson::Find(parsed.root, L"templates");
    if (templates && templates->IsArray()) {
        for (const auto& item : templates->arrayValue) {
            WorkflowTemplateRecordResult one = BuildWorkflowTemplateRecordFromJson(item);
            if (!one.ok) return Fail(one.errorCode, one.errorMessage);
            result.templates.push_back(one.record);
        }
    }
    result.ok = true;
    result.dataJson = RegistryJson(result.templates);
    return result;
}

WorkflowTemplateRegistryResult ExportWorkflowTemplateRegistry(const std::wstring& registryRoot, const std::wstring& outputPath) {
    WorkflowTemplateRegistryResult result = LoadWorkflowTemplateRegistry(registryRoot);
    if (!result.ok) return result;
    std::wstring error;
    if (!outputPath.empty()) WriteValidationTextFile(outputPath, result.dataJson, error);
    return result;
}

WorkflowTemplateRegistryResult RegisterWorkflowTemplateCandidate(const std::wstring& registryRoot, const WorkflowTemplateRecord& record) {
    return UpdateWorkflowTemplateRecord(registryRoot, record, L"register_candidate_template");
}

WorkflowTemplateRegistryResult UpdateWorkflowTemplateRecord(const std::wstring& registryRoot, const WorkflowTemplateRecord& record, const std::wstring& action) {
    WorkflowTemplateRegistryResult loaded = LoadWorkflowTemplateRegistry(registryRoot);
    if (!loaded.ok) return loaded;
    std::vector<WorkflowTemplateRecord> records = loaded.templates;
    Upsert(records, record);
    return Persist(registryRoot, records, record, action);
}

WorkflowTemplateRegistryResult QueryWorkflowTemplatesByType(const std::wstring& registryRoot, const std::wstring& workflowType) {
    WorkflowTemplateRegistryResult loaded = LoadWorkflowTemplateRegistry(registryRoot);
    if (!loaded.ok) return loaded;
    WorkflowTemplateRegistryResult result;
    result.ok = true;
    for (const auto& record : loaded.templates) {
        if (Lower(record.workflowType) == Lower(workflowType)) result.templates.push_back(record);
    }
    result.dataJson = L"{\"schema_version\":\"6.11.0.workflow_template_query\",\"status\":\"PASS\",\"query_type\":\"workflow_type\",\"record_count\":" +
        std::to_wstring(result.templates.size()) + L",\"templates\":" + TemplatesArrayJson(result.templates) + L"}";
    return result;
}

WorkflowTemplateRegistryResult QueryWorkflowTemplatesByStatus(const std::wstring& registryRoot, const std::wstring& status) {
    WorkflowTemplateRegistryResult loaded = LoadWorkflowTemplateRegistry(registryRoot);
    if (!loaded.ok) return loaded;
    WorkflowTemplateRegistryResult result;
    result.ok = true;
    for (const auto& record : loaded.templates) {
        if (Lower(record.templateStatus) == Lower(status)) result.templates.push_back(record);
    }
    result.dataJson = L"{\"schema_version\":\"6.11.0.workflow_template_query\",\"status\":\"PASS\",\"query_type\":\"template_status\",\"record_count\":" +
        std::to_wstring(result.templates.size()) + L",\"templates\":" + TemplatesArrayJson(result.templates) + L"}";
    return result;
}

WorkflowTemplateRegistryResult GenerateWorkflowTemplateRegistryReport(
    const std::wstring& registryRoot,
    const std::wstring& outputJsonPath,
    const std::wstring& outputMarkdownPath) {
    WorkflowTemplateRegistryResult loaded = LoadWorkflowTemplateRegistry(registryRoot);
    if (!loaded.ok) return loaded;
    std::map<std::wstring, int> byStatus = {
        {L"candidate", 0},
        {L"validated", 0},
        {L"rejected", 0},
        {L"deprecated", 0}
    };
    std::map<std::wstring, int> byType;
    for (const auto& record : loaded.templates) {
        ++byStatus[Lower(record.templateStatus)];
        ++byType[record.workflowType.empty() ? L"unknown" : record.workflowType];
    }
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.workflow_template_registry_report\""
         << L",\"status\":\"PASS\""
         << L",\"template_count\":" << loaded.templates.size()
         << L",\"candidate_count\":" << byStatus[L"candidate"]
         << L",\"validated_count\":" << byStatus[L"validated"]
         << L",\"rejected_count\":" << byStatus[L"rejected"]
         << L",\"deprecated_count\":" << byStatus[L"deprecated"]
         << L",\"external_database_used\":false"
         << L",\"templates\":" << TemplatesArrayJson(loaded.templates)
         << L"}";
    std::wstring error;
    if (!outputJsonPath.empty()) WriteValidationTextFile(outputJsonPath, json.str(), error);
    if (!outputMarkdownPath.empty()) WriteValidationTextFile(outputMarkdownPath, ReportMarkdown(byStatus, byType, static_cast<int>(loaded.templates.size())), error);
    WorkflowTemplateRegistryResult result;
    result.ok = true;
    result.templates = loaded.templates;
    result.dataJson = json.str();
    return result;
}

int CommandWorkflowTemplateRegister(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-template-register";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    std::wstring registryRoot;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-template-register requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    ArgValue(argc, argv, L"--registry-root", registryRoot);
    WorkflowTemplateRecordResult record = LoadWorkflowTemplateRecordInput(input);
    if (!record.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), record.errorCode, record.errorMessage, L"{}") << L"\n";
        return 1;
    }
    WorkflowTemplateRegistryResult result = RegisterWorkflowTemplateCandidate(registryRoot, record.record);
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, record.recordJson, error);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode, result.errorMessage, result.dataJson.empty() ? L"{}" : result.dataJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.dataJson) << L"\n";
    return 0;
}

int CommandWorkflowTemplateReport(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-template-report";
    ULONGLONG startTick = GetTickCount64();
    std::wstring registryRoot;
    std::wstring output;
    std::wstring markdownOutput;
    ArgValue(argc, argv, L"--registry-root", registryRoot);
    ArgValue(argc, argv, L"--output", output);
    ArgValue(argc, argv, L"--markdown-output", markdownOutput);
    WorkflowTemplateRegistryResult result = GenerateWorkflowTemplateRegistryReport(registryRoot, output, markdownOutput);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode, result.errorMessage, result.dataJson.empty() ? L"{}" : result.dataJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.dataJson) << L"\n";
    return 0;
}

