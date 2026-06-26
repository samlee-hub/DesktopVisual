#pragma once

#include <string>

struct CodingWorkflowContext {
    std::wstring problemTitle;
    std::wstring problemStatementSummary;
    std::wstring examplesSummary;
    std::wstring constraintsSummary;
    std::wstring language;
    bool editorDetected = false;
    bool runButtonDetected = false;
    bool submitAllowed = false;
    std::wstring resultState;
};

struct CodingWorkflowRecord {
    std::wstring action;
    std::wstring source;
    std::wstring reason;
    std::wstring codeSummary;
    std::wstring codePath;
    int revisionCount = 0;
    bool submitClicked = false;
    std::wstring submitBasis;
    std::wstring safetyCheckResult;
    std::wstring timestamp;
};

struct CodingWorkflowInput {
    std::wstring htmlPath;
    std::wstring userGoal;
    std::wstring action;
    std::wstring language;
    std::wstring codeText;
    std::wstring codePath;
    bool allowSubmit = false;
    int revisionCount = 0;
    std::wstring permissionMode;
    std::wstring currentWindow;
    std::wstring currentUrl;
};

struct CodingWorkflowEvalResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    CodingWorkflowContext context;
    CodingWorkflowRecord record;
};

CodingWorkflowEvalResult EvaluateCodingWorkflow(const CodingWorkflowInput& input);

std::wstring CodingWorkflowContextJson(const CodingWorkflowContext& context);
std::wstring CodingWorkflowRecordJson(const CodingWorkflowRecord& record);
