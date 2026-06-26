#pragma once

#include <string>

#include "ReportWriter.h"

struct FileReadResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring content;
    std::wstring error;
};

struct CaseRunResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring error;
    std::wstring reportPath;
    int stepCount = 0;
    int passedStepCount = 0;
    int failedStepIndex = 0;
};

FileReadResult ReadTextFile(const std::wstring& path);
CaseRunResult RunCaseFile(const std::wstring& caseFilePath, const std::wstring& reportPath);
