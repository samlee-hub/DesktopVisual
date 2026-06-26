#pragma once

#include <string>
#include <vector>

struct RuntimeEvidenceConsolidationOptions {
    std::wstring rootPath;
    std::wstring outputJsonPath;
    std::wstring outputMarkdownPath;
};

struct RuntimeEvidenceConsolidationResult {
    bool ok = false;
    std::wstring status;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring jsonReport;
    std::wstring markdownReport;
    int artifactCount = 0;
    int runtimeSessionCount = 0;
    std::vector<std::wstring> unreferencedRuntimeSessions;
    std::vector<std::wstring> coreEvidenceMarkedDeletable;
};

RuntimeEvidenceConsolidationResult ConsolidateRuntimeEvidence(
    const RuntimeEvidenceConsolidationOptions& options);

int CommandEvidenceConsolidate(int argc, wchar_t** argv);
