#pragma once

#include <string>
#include <vector>

enum class TaskSessionState {
    Pending,
    Running,
    Waiting,
    Verifying,
    Recovering,
    Confirmed,
    Completed,
    Failed,
    Stopped,
    Blocked,
    Unknown
};

struct TaskSessionContext {
    std::wstring runtimeMode = L"STANDARD";
    std::wstring taskGoal;
    std::wstring targetTitle;
    std::wstring targetProcess;
    bool allowUnrestrictedDesktop = false;
};

struct TaskSessionArtifacts {
    std::wstring root;
    std::wstring eventsJsonl;
    std::wstring resultJson;
    std::wstring reportMd;
};

struct TaskSessionProgress {
    int totalSteps = 0;
    int completedSteps = 0;
    int failedSteps = 0;
    std::wstring currentStepId;
};

struct TaskSessionResultRecord {
    std::wstring taskId;
    std::wstring state;
    std::wstring status;
    bool ok = false;
    std::wstring errorCode;
    std::wstring message;
};

struct TaskSession {
    std::wstring schemaVersion;
    std::wstring runtimeVersion;
    std::wstring protocolVersion;
    std::wstring taskId;
    std::wstring taskType;
    std::wstring profile;
    std::wstring permissionProfile;
    int capabilityProfileCount = 0;
    TaskSessionState currentState = TaskSessionState::Unknown;
    std::wstring currentStateText;
    std::wstring startedAt;
    std::wstring updatedAt;
    TaskSessionArtifacts artifacts;
    TaskSessionContext context;
    TaskSessionProgress progress;
    int stateCount = 0;
    int transitionSchemaCount = 0;
    int stepContractCount = 0;
    int eventCount = 0;
    TaskSessionResultRecord result;
    std::wstring escalationProvider = L"none";
};

struct TaskSessionValidationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    TaskSession session;
};

struct TaskTransitionRequest {
    std::wstring action;
    TaskSessionState fromState = TaskSessionState::Unknown;
    TaskSessionState toState = TaskSessionState::Unknown;
    std::wstring reason;
    int timeoutMs = 0;
    int elapsedMs = 0;
};

struct TaskTransitionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring action;
    std::wstring previousState;
    std::wstring currentState;
    std::wstring reason;
    bool timeout = false;
    std::wstring dataJson;
};

struct TaskSessionRunResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    std::wstring progressPath;
    std::wstring eventsPath;
    std::wstring reportPath;
};

struct TaskSessionControlResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    std::vector<std::wstring> artifacts;
    std::wstring reportPath;
};

TaskSessionState ParseTaskSessionState(const std::wstring& value);
std::wstring TaskSessionStateName(TaskSessionState state);
TaskSessionValidationResult ValidateTaskSessionFile(const std::wstring& path);
std::wstring TaskSessionDataJson(const TaskSession& session);
TaskTransitionResult ApplyTaskTransition(const TaskSession& session, const TaskTransitionRequest& request);
TaskSessionRunResult RunMinimalTaskSessionFile(const std::wstring& path);
TaskSessionRunResult RunStableTaskSessionFile(const std::wstring& path);
TaskSessionRunResult RunCompiledStepContractTaskSessionFile(
    const std::wstring& stepContractPath,
    const std::wstring& executionMode,
    const std::wstring& outputPath,
    const std::wstring& evidenceDir);
TaskSessionControlResult GetStableTaskSessionStatus(const std::wstring& taskId, const std::wstring& file);
TaskSessionControlResult ReadStableTaskSessionEvents(const std::wstring& taskId, const std::wstring& file);
TaskSessionControlResult ReadStableTaskSessionReport(const std::wstring& taskId, const std::wstring& file);
TaskSessionControlResult ConfirmStableTaskSessionAction(const std::wstring& taskId, const std::wstring& file, const std::wstring& response);
TaskSessionControlResult CancelStableTaskSession(const std::wstring& taskId, const std::wstring& file, const std::wstring& reason);
