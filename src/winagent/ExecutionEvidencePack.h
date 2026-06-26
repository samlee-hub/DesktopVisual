#pragma once

#include <string>
#include <vector>

struct EvidenceStepRecord {
    std::wstring stepJson;
};

struct ExecutionEvidencePackInput {
    std::wstring evidenceDir;
    std::wstring executionResultJson;
    std::vector<EvidenceStepRecord> stepRecords;
    std::wstring executionId;
    std::wstring taskId;
    std::wstring finalStatus;
};

struct ExecutionEvidencePackResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring executionResultPath;
    std::wstring stepResultsPath;
    std::wstring evidenceIndexPath;
    std::wstring executionReportPath;
    std::wstring dataJson;
};

ExecutionEvidencePackResult WriteExecutionEvidencePack(const ExecutionEvidencePackInput& input);
