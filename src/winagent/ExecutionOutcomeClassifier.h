#pragma once

#include <string>
#include <vector>

struct ExecutionOutcomeInput {
    std::wstring profile = L"python";
    std::wstring beforeText;
    std::wstring afterText;
    std::wstring expectedStartMarker = L"DV616_RUN_START";
    std::wstring expectedEndMarker = L"DV616_RUN_END";
};

struct ExecutionOutcome {
    bool runTriggered = false;
    bool executionStarted = false;
    bool executionCompleted = false;
    bool executionSuccess = false;
    bool exitCodePresent = false;
    int exitCode = 0;
    bool runtimeCommandObserved = false;
    std::wstring runtimeCommandText;
    bool compilerOrInterpreterObserved = false;
    bool errorDetected = false;
    std::wstring errorCategory;
    std::wstring errorLanguageHint;
    std::wstring errorSummary;
    std::vector<std::wstring> outputLinesObserved;
    bool expectedOutputVerified = false;
    bool currentRunVerified = false;
    bool oldOutputReuseDetected = false;
    std::wstring rawOutputExcerpt;
    std::wstring classifierProfile;
    double classifierConfidence = 0.0;
};

ExecutionOutcome ClassifyExecutionOutcome(const ExecutionOutcomeInput& input);
std::wstring ExecutionOutcomeJson(const ExecutionOutcome& outcome);
