#include "TaskCheckpoint.h"

#include "Trace.h"

#include <sstream>

namespace {

std::wstring JsonArray(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

bool DifferentWhenProvided(const std::wstring& current, const std::wstring& verified) {
    return !current.empty() && !verified.empty() && current != verified;
}

}  // namespace

ResumeDecision EvaluateResumeDecision(const ResumeDecisionInput& input) {
    ResumeDecision decision;
    decision.resumeFromStep = input.checkpoint.resumeFromStep;
    decision.stateLossRisk = input.stateLossRisk.empty() ? L"unknown" : input.stateLossRisk;

    bool contextChanged =
        DifferentWhenProvided(input.currentContext, input.checkpoint.verifiedContext) ||
        DifferentWhenProvided(input.currentWindowTitle, input.checkpoint.verifiedWindowTitle) ||
        DifferentWhenProvided(input.currentProcess, input.checkpoint.verifiedProcess);
    decision.contextChanged = contextChanged;

    bool inputChanged = DifferentWhenProvided(input.currentInputStateHash, input.checkpoint.inputStateHash);
    bool pageChanged = DifferentWhenProvided(input.currentPageStateHash, input.checkpoint.pageStateHash);
    decision.userDataMayBeLost = inputChanged || (pageChanged && decision.stateLossRisk != L"low");

    if (input.recoveryJustExecuted && !input.reobservePerformed) {
        decision.resumeAllowed = false;
        decision.replayRequired = true;
        decision.resumeFromStep = input.checkpoint.replayFromStep;
        decision.reason = L"Recovery executed but reobserve has not been performed.";
        return decision;
    }
    if (input.recoveryJustExecuted && !input.expectedContextReverified) {
        decision.resumeAllowed = false;
        decision.replayRequired = true;
        decision.resumeFromStep = input.checkpoint.replayFromStep;
        decision.reason = L"Recovery executed but expected context was not reverified.";
        return decision;
    }
    if (!input.checkpoint.safeToResume) {
        decision.resumeAllowed = false;
        decision.replayRequired = true;
        decision.resumeFromStep = input.checkpoint.replayFromStep;
        decision.reason = L"Checkpoint is not marked safe_to_resume.";
        return decision;
    }
    if (decision.userDataMayBeLost) {
        decision.resumeAllowed = false;
        decision.replayRequired = true;
        decision.resumeFromStep = input.checkpoint.replayFromStep;
        decision.reason = L"Input or page state changed; replay from safe checkpoint is required.";
        return decision;
    }
    if (contextChanged) {
        decision.resumeAllowed = false;
        decision.replayRequired = true;
        decision.resumeFromStep = input.checkpoint.replayFromStep;
        decision.reason = L"Verified context changed; blind mid-step resume is not allowed.";
        return decision;
    }

    decision.resumeAllowed = true;
    decision.replayRequired = false;
    decision.resumeFromStep = input.checkpoint.resumeFromStep;
    decision.reason = L"Checkpoint context and state hashes are stable.";
    return decision;
}

std::wstring TaskCheckpointJson(const TaskCheckpointRecord& checkpoint) {
    std::wstringstream json;
    json << L"{\"task_id\":" << JsonString(checkpoint.taskId)
         << L",\"case_id\":" << JsonString(checkpoint.caseId)
         << L",\"step_index\":" << checkpoint.stepIndex
         << L",\"step_name\":" << JsonString(checkpoint.stepName)
         << L",\"verified_context\":" << JsonString(checkpoint.verifiedContext)
         << L",\"verified_markers\":" << JsonArray(checkpoint.verifiedMarkers)
         << L",\"verified_window_title\":" << JsonString(checkpoint.verifiedWindowTitle)
         << L",\"verified_process\":" << JsonString(checkpoint.verifiedProcess)
         << L",\"input_state_hash\":" << JsonString(checkpoint.inputStateHash)
         << L",\"page_state_hash\":" << JsonString(checkpoint.pageStateHash)
         << L",\"safe_to_resume\":" << (checkpoint.safeToResume ? L"true" : L"false")
         << L",\"resume_from_step\":" << checkpoint.resumeFromStep
         << L",\"replay_from_step\":" << checkpoint.replayFromStep
         << L",\"checkpoint_created_at\":" << JsonString(checkpoint.checkpointCreatedAt)
         << L"}";
    return json.str();
}

std::wstring ResumeDecisionJson(const ResumeDecision& decision) {
    std::wstringstream json;
    json << L"{\"resume_allowed\":" << (decision.resumeAllowed ? L"true" : L"false")
         << L",\"resume_from_step\":" << decision.resumeFromStep
         << L",\"replay_required\":" << (decision.replayRequired ? L"true" : L"false")
         << L",\"reason\":" << JsonString(decision.reason)
         << L",\"state_loss_risk\":" << JsonString(decision.stateLossRisk)
         << L",\"context_changed\":" << (decision.contextChanged ? L"true" : L"false")
         << L",\"user_data_may_be_lost\":" << (decision.userDataMayBeLost ? L"true" : L"false")
         << L"}";
    return json.str();
}
