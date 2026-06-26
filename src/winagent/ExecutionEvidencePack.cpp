#include "ExecutionEvidencePack.h"

#include "ProjectRoot.h"
#include "Trace.h"

#include <cstdio>
#include <sstream>

namespace {

bool WriteTextFileUtf8(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) EnsureDirectoryPath(path.substr(0, slash));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file: " + path;
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

std::wstring SafeDirPart(std::wstring value) {
    for (wchar_t& ch : value) {
        bool ok = (ch >= L'a' && ch <= L'z') || (ch >= L'A' && ch <= L'Z') ||
                  (ch >= L'0' && ch <= L'9') || ch == L'_' || ch == L'-' || ch == L'.';
        if (!ok) ch = L'_';
    }
    return value.empty() ? L"execution" : value;
}

}  // namespace

ExecutionEvidencePackResult WriteExecutionEvidencePack(const ExecutionEvidencePackInput& input) {
    ExecutionEvidencePackResult result;
    std::wstring dir = input.evidenceDir;
    if (dir.empty()) {
        dir = ArtifactsPath(L"dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\executions\\" + SafeDirPart(input.executionId));
    }
    EnsureDirectoryPath(dir);

    result.executionResultPath = dir + L"\\execution_result.json";
    result.stepResultsPath = dir + L"\\step_results.jsonl";
    result.evidenceIndexPath = dir + L"\\evidence_index.md";
    result.executionReportPath = dir + L"\\execution_report.md";

    std::wstring stepJsonl;
    for (const auto& record : input.stepRecords) {
        stepJsonl += record.stepJson;
        stepJsonl += L"\n";
    }

    std::wstringstream index;
    index << L"# v6.4.0 Execution Evidence Index\n\n"
          << L"- execution_id: `" << input.executionId << L"`\n"
          << L"- task_id: `" << input.taskId << L"`\n"
          << L"- final_status: `" << input.finalStatus << L"`\n"
          << L"- execution_result.json: `" << result.executionResultPath << L"`\n"
          << L"- step_results.jsonl: `" << result.stepResultsPath << L"`\n"
          << L"- execution_report.md: `" << result.executionReportPath << L"`\n";

    std::wstringstream report;
    report << L"# v6.4.0 Execution Report\n\n"
           << L"- Execution ID: `" << input.executionId << L"`\n"
           << L"- Task ID: `" << input.taskId << L"`\n"
           << L"- Final status: `" << input.finalStatus << L"`\n"
           << L"- Step records: `" << input.stepRecords.size() << L"`\n";

    std::wstring error;
    if (!WriteTextFileUtf8(result.executionResultPath, input.executionResultJson, error) ||
        !WriteTextFileUtf8(result.stepResultsPath, stepJsonl, error) ||
        !WriteTextFileUtf8(result.evidenceIndexPath, index.str(), error) ||
        !WriteTextFileUtf8(result.executionReportPath, report.str(), error)) {
        result.errorCode = L"FILE_WRITE_FAILED";
        result.errorMessage = error;
        return result;
    }

    result.ok = true;
    result.dataJson = L"{\"evidence_pack_created\":true"
        L",\"execution_result_json\":" + JsonString(result.executionResultPath) +
        L",\"step_results_jsonl\":" + JsonString(result.stepResultsPath) +
        L",\"evidence_index_md\":" + JsonString(result.evidenceIndexPath) +
        L",\"execution_report_md\":" + JsonString(result.executionReportPath) + L"}";
    return result;
}
