#pragma once

#include <string>
#include <vector>
#include <utility>

struct CaseStepRecord {
    int index = 0;
    std::wstring startedAt;
    std::wstring endedAt;
    long long durationMs = 0;
    std::wstring action;
    std::wstring parameters;
    bool ok = false;
    std::wstring errorCode;
    std::wstring message;
    std::wstring jsonOutputSummary;
    std::wstring content;
};

struct CaseObservationRecord {
    int index = 0;
    std::wstring screenshotPath;
    int uiaElementCount = 0;
    bool focusVerified = false;
    std::wstring outputPath;
};

struct CaseV2ExpectRecord {
    int stepIndex = 0;
    std::wstring type;
    std::wstring selector;
    std::wstring path;
    std::wstring text;
    bool ok = false;
    std::wstring detail;
};

struct CaseV2WaitUntilRecord {
    int stepIndex = 0;
    std::wstring conditionType;
    std::wstring selector;
    std::wstring path;
    std::wstring text;
    int timeoutMs = 0;
    bool ok = false;
    long long elapsedMs = 0;
};

struct CaseReport {
    std::wstring caseFile;
    std::wstring caseName;
    std::wstring targetTitle;
    bool ok = false;
    std::wstring startTime;
    std::wstring endTime;
    long long totalDurationMs = 0;
    int stepCount = 0;
    int passedStepCount = 0;
    int failedStepIndex = 0;
    std::wstring failureErrorCode;
    std::wstring failureMessage;
    std::vector<CaseStepRecord> steps;
    std::vector<std::wstring> screenshotPaths;
    std::vector<std::wstring> readContents;
    std::vector<std::wstring> focusAndSafety;
    std::vector<CaseObservationRecord> observations;
    int caseVersion = 1;
    std::vector<std::pair<std::wstring, std::wstring>> variables;
    std::vector<CaseV2ExpectRecord> expectResults;
    std::vector<CaseV2WaitUntilRecord> waitResults;
    std::wstring observationBefore;
    std::wstring observationAfter;
};

bool WriteMarkdownReport(const std::wstring& reportPath, const CaseReport& report, std::wstring& error);
std::wstring CurrentTimestamp();
