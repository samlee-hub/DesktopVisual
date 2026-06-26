#pragma once

#include <string>
#include <vector>

struct TaskCheckpointRecord {
    std::wstring taskId;
    std::wstring caseId;
    int stepIndex = 0;
    std::wstring stepName;
    std::wstring verifiedContext;
    std::vector<std::wstring> verifiedMarkers;
    std::wstring verifiedWindowTitle;
    std::wstring verifiedProcess;
    std::wstring inputStateHash;
    std::wstring pageStateHash;
    bool safeToResume = false;
    int resumeFromStep = 0;
    int replayFromStep = 0;
    std::wstring checkpointCreatedAt;
};

struct ResumeDecision {
    bool resumeAllowed = false;
    int resumeFromStep = 0;
    bool replayRequired = false;
    std::wstring reason;
    std::wstring stateLossRisk = L"unknown";
    bool contextChanged = false;
    bool userDataMayBeLost = false;
};

struct ResumeDecisionInput {
    TaskCheckpointRecord checkpoint;
    std::wstring currentContext;
    std::wstring currentWindowTitle;
    std::wstring currentProcess;
    std::wstring currentInputStateHash;
    std::wstring currentPageStateHash;
    std::wstring stateLossRisk = L"unknown";
    bool recoveryJustExecuted = false;
    bool reobservePerformed = false;
    bool expectedContextReverified = false;
};

ResumeDecision EvaluateResumeDecision(const ResumeDecisionInput& input);
std::wstring TaskCheckpointJson(const TaskCheckpointRecord& checkpoint);
std::wstring ResumeDecisionJson(const ResumeDecision& decision);
