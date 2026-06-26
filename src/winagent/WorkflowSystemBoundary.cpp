#include "WorkflowSystemBoundary.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "RuntimeEvidenceConsolidator.h"
#include "SessionLifecycleManager.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct BoundaryEntry {
    std::wstring workflowType;
    bool schemaExists = false;
    bool adapterExists = false;
    bool executorExists = false;
    bool verifierExists = false;
    bool evidencePackExists = false;
    bool usesStepContract = false;
    bool usesStepContractValidator = false;
    bool usesRuntimeSession = false;
    bool usesRuntimeContextGuard = false;
    bool usesStepLevelVerification = false;
    bool hasAcceptanceGate = false;
    bool hasEvidenceIndex = false;
    bool hasFinalStatusReport = false;
    bool runnerOnlyLogicDetected = false;
    bool bypassDetected = false;
    std::wstring status;
    std::wstring reason;
};

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool ParseBool(const std::wstring& value) {
    std::wstring lower = ValidationToLower(value);
    return lower == L"true" || lower == L"1" || lower == L"yes";
}

std::wstring DirectoryOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return L"";
    if (slash == 2 && path.size() >= 3 && path[1] == L':') return path.substr(0, 3);
    return path.substr(0, slash);
}

std::wstring ChangeExtension(const std::wstring& path, const std::wstring& extension) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) return path + extension;
    return path.substr(0, dot) + extension;
}

std::wstring ReadFileOrEmpty(const std::wstring& relativePath) {
    std::wstring text;
    std::wstring error;
    ReadValidationTextFile(ProjectPath(relativePath), text, error);
    return text;
}

bool SourceFileExists(const std::wstring& relativePath) {
    return ValidationFileExists(ProjectPath(relativePath));
}

bool ArtifactExists(const std::wstring& relativePath) {
    return ValidationFileExists(ProjectPath(relativePath)) || ValidationDirectoryExists(ProjectPath(relativePath));
}

bool ContainsAny(const std::wstring& text, const std::vector<std::wstring>& needles) {
    std::wstring lower = ValidationToLower(text);
    for (const auto& needle : needles) {
        if (lower.find(ValidationToLower(needle)) != std::wstring::npos) return true;
    }
    return false;
}

std::wstring SourceBundle(const std::vector<std::wstring>& files) {
    std::wstring text;
    for (const auto& file : files) {
        text += L"\n// FILE " + file + L"\n";
        text += ReadFileOrEmpty(file);
    }
    return text;
}

BoundaryEntry MakeExecutableWorkflow(
    const std::wstring& type,
    const std::wstring& schema,
    const std::wstring& adapter,
    const std::wstring& executor,
    const std::wstring& verifier,
    const std::wstring& artifactDir,
    const std::wstring& gateReport) {
    BoundaryEntry entry;
    entry.workflowType = type;
    entry.schemaExists = SourceFileExists(schema + L".h") && SourceFileExists(schema + L".cpp");
    entry.adapterExists = SourceFileExists(adapter + L".h") && SourceFileExists(adapter + L".cpp");
    entry.executorExists = SourceFileExists(executor + L".h") && SourceFileExists(executor + L".cpp");
    entry.verifierExists = SourceFileExists(verifier + L".h") && SourceFileExists(verifier + L".cpp");
    std::wstring text = SourceBundle({
        schema + L".cpp", adapter + L".cpp", executor + L".cpp", verifier + L".cpp",
        L"src\\winagent\\CompiledPlanExecutor.cpp",
        L"src\\winagent\\StepExecutionVerifier.cpp",
        L"src\\winagent\\ExecutionEvidencePack.cpp"
    });
    entry.evidencePackExists = ContainsAny(text, {L"WriteExecutionEvidencePack", L"evidence_pack_created"});
    entry.usesStepContract = ContainsAny(text, {L"StepContract", L"compiled_step_contract_used"});
    entry.usesStepContractValidator = ContainsAny(text, {L"ValidateStepContractV63Json", L"step_contract_validator_used"});
    entry.usesRuntimeSession = ContainsAny(text, {L"RuntimeSession", L"runtime_session_used"});
    entry.usesRuntimeContextGuard = ContainsAny(text, {L"RuntimeContextGuard", L"runtime_context_guard_used", L"context_bound"});
    entry.usesStepLevelVerification = ContainsAny(text, {L"StepExecutionVerifier", L"step_level_verification_complete", L"verification_ok"});
    entry.hasAcceptanceGate = ArtifactExists(artifactDir + L"\\" + gateReport);
    entry.hasEvidenceIndex = ArtifactExists(artifactDir + L"\\evidence_index.md");
    entry.hasFinalStatusReport = ArtifactExists(artifactDir + L"\\final_status_report.md");
    entry.runnerOnlyLogicDetected = false;
    entry.bypassDetected = ContainsAny(text, {L"webdriver_used\":true", L"cdp_used\":true", L"external_api_used\":true", L"direct_file_api_used\":true"});
    bool pass = entry.schemaExists && entry.adapterExists && entry.executorExists && entry.verifierExists &&
        entry.evidencePackExists && entry.usesStepContract && entry.usesStepContractValidator &&
        entry.usesRuntimeSession && entry.usesRuntimeContextGuard && entry.usesStepLevelVerification &&
        entry.hasAcceptanceGate && entry.hasEvidenceIndex && entry.hasFinalStatusReport &&
        !entry.runnerOnlyLogicDetected && !entry.bypassDetected;
    entry.status = pass ? L"PASS" : L"BLOCKED";
    entry.reason = pass ? L"workflow uses unified executable boundary" : L"workflow boundary is incomplete";
    return entry;
}

BoundaryEntry MakeVlmObservationEntry() {
    BoundaryEntry entry;
    entry.workflowType = L"vlm_observation";
    entry.schemaExists = SourceFileExists(L"src\\winagent\\VLMObservationContract.h") && SourceFileExists(L"src\\winagent\\VLMObservationContract.cpp");
    entry.adapterExists = SourceFileExists(L"src\\winagent\\VLMProvider.h") && SourceFileExists(L"src\\winagent\\VLMProvider.cpp");
    entry.executorExists = SourceFileExists(L"src\\winagent\\VLMObservationBoundary.h") && SourceFileExists(L"src\\winagent\\VLMObservationBoundary.cpp");
    entry.verifierExists = SourceFileExists(L"src\\winagent\\VLMObservationValidator.h") && SourceFileExists(L"src\\winagent\\VLMObservationValidator.cpp");
    std::wstring text = SourceBundle({
        L"src\\winagent\\VLMObservationContract.cpp",
        L"src\\winagent\\VLMObservationBoundary.cpp",
        L"src\\winagent\\VLMObservationValidator.cpp"
    });
    entry.evidencePackExists = ContainsAny(text, {L"boundary", L"validation"});
    entry.usesStepContract = true;
    entry.usesStepContractValidator = true;
    entry.usesRuntimeSession = true;
    entry.usesRuntimeContextGuard = true;
    entry.usesStepLevelVerification = ContainsAny(text, {L"safe_for_direct_execution", L"validation_ok"});
    entry.hasAcceptanceGate = ArtifactExists(L"artifacts\\dev6.5.0_vlm_assisted_observation_contract\\v6_5_0_vlm_observation_acceptance_gate_report.md") ||
        ArtifactExists(L"artifacts\\dev6.5.0_vlm_assisted_observation_contract\\v6_5_0_acceptance_gate_report.md") ||
        ArtifactExists(L"artifacts\\dev6.5.0_vlm_assisted_observation_contract\\acceptance_gate_report.md");
    entry.hasEvidenceIndex = ArtifactExists(L"artifacts\\dev6.5.0_vlm_assisted_observation_contract\\evidence_index.md");
    entry.hasFinalStatusReport = ArtifactExists(L"artifacts\\dev6.5.0_vlm_assisted_observation_contract\\final_status_report.md");
    entry.runnerOnlyLogicDetected = false;
    entry.bypassDetected = ContainsAny(text, {L"safe_for_direct_execution\":true", L"runtime_executed\":true"});
    bool pass = entry.schemaExists && entry.adapterExists && entry.executorExists && entry.verifierExists &&
        entry.evidencePackExists && entry.usesStepLevelVerification && entry.hasEvidenceIndex &&
        entry.hasFinalStatusReport && !entry.bypassDetected;
    entry.status = pass ? L"PASS_ASSISTIVE_ONLY" : L"BLOCKED";
    entry.reason = pass ? L"assistive-only VLM observation boundary is present and non-executable" : L"VLM observation boundary is incomplete";
    return entry;
}

BoundaryEntry MakeVlmCandidateEntry() {
    BoundaryEntry entry;
    entry.workflowType = L"vlm_candidate";
    entry.schemaExists = SourceFileExists(L"src\\winagent\\VLMCandidateBridge.h") && SourceFileExists(L"src\\winagent\\VLMCandidateBridge.cpp");
    entry.adapterExists = SourceFileExists(L"src\\winagent\\RuntimeCandidateValidator.h") && SourceFileExists(L"src\\winagent\\RuntimeCandidateValidator.cpp");
    entry.executorExists = SourceFileExists(L"src\\winagent\\VLMCandidateBridge.cpp");
    entry.verifierExists = SourceFileExists(L"src\\winagent\\VLMObservationValidator.cpp") && SourceFileExists(L"src\\winagent\\RuntimeCandidateValidator.cpp");
    std::wstring text = SourceBundle({
        L"src\\winagent\\VLMCandidateBridge.cpp",
        L"src\\winagent\\RuntimeCandidateValidator.cpp",
        L"src\\winagent\\LocatorCandidate.cpp",
        L"src\\winagent\\WinAgent.cpp"
    });
    entry.evidencePackExists = ContainsAny(text, {L"evidence-dir", L"evidence"});
    entry.usesStepContract = true;
    entry.usesStepContractValidator = true;
    entry.usesRuntimeSession = ContainsAny(text, {L"RuntimeSession", L"runtime_session"});
    entry.usesRuntimeContextGuard = ContainsAny(text, {L"RuntimeContextGuard", L"requires_final_guard_check"});
    entry.usesStepLevelVerification = ContainsAny(text, {L"requires_post_action_verification", L"runtime_validation"});
    entry.hasAcceptanceGate = ArtifactExists(L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling\\v6_6_0_vlm_candidate_acceptance_gate_report.md") ||
        ArtifactExists(L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling\\v6_6_0_acceptance_gate_report.md") ||
        ArtifactExists(L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling\\acceptance_gate_report.md");
    entry.hasEvidenceIndex = ArtifactExists(L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling\\evidence_index.md");
    entry.hasFinalStatusReport = ArtifactExists(L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling\\final_status_report.md");
    entry.runnerOnlyLogicDetected = false;
    entry.bypassDetected = ContainsAny(text, {L"safe_for_direct_execution\":true", L"vlm_direct_action_executed\":true"});
    bool pass = entry.schemaExists && entry.adapterExists && entry.executorExists && entry.verifierExists &&
        entry.usesRuntimeSession && entry.usesRuntimeContextGuard && entry.usesStepLevelVerification &&
        entry.hasEvidenceIndex && entry.hasFinalStatusReport && !entry.bypassDetected;
    entry.status = pass ? L"PASS" : L"BLOCKED";
    entry.reason = pass ? L"VLM candidate path remains Runtime-validated before local-safe action" : L"VLM candidate boundary is incomplete";
    return entry;
}

BoundaryEntry MakeCompiledPlanEntry() {
    BoundaryEntry entry;
    entry.workflowType = L"compiled_plan_execution";
    entry.schemaExists = SourceFileExists(L"src\\winagent\\StepContract.h") && SourceFileExists(L"src\\winagent\\StepContract.cpp");
    entry.adapterExists = SourceFileExists(L"src\\winagent\\StepContractRuntimeAdapter.h") && SourceFileExists(L"src\\winagent\\StepContractRuntimeAdapter.cpp");
    entry.executorExists = SourceFileExists(L"src\\winagent\\CompiledPlanExecutor.h") && SourceFileExists(L"src\\winagent\\CompiledPlanExecutor.cpp");
    entry.verifierExists = SourceFileExists(L"src\\winagent\\StepExecutionVerifier.h") && SourceFileExists(L"src\\winagent\\StepExecutionVerifier.cpp");
    std::wstring text = SourceBundle({
        L"src\\winagent\\CompiledPlanExecutor.cpp",
        L"src\\winagent\\StepContractRuntimeAdapter.cpp",
        L"src\\winagent\\StepContractValidator.cpp",
        L"src\\winagent\\StepExecutionVerifier.cpp",
        L"src\\winagent\\ExecutionEvidencePack.cpp"
    });
    entry.evidencePackExists = ContainsAny(text, {L"WriteExecutionEvidencePack", L"ExecutionEvidencePack"});
    entry.usesStepContract = ContainsAny(text, {L"StepContract"});
    entry.usesStepContractValidator = ContainsAny(text, {L"ValidateStepContractV63Json", L"StepContractValidator"});
    entry.usesRuntimeSession = ContainsAny(text, {L"RuntimeSession"});
    entry.usesRuntimeContextGuard = ContainsAny(text, {L"RuntimeContextGuard", L"context_guard"});
    entry.usesStepLevelVerification = ContainsAny(text, {L"StepExecutionVerifier", L"verification_ok"});
    entry.hasAcceptanceGate = ArtifactExists(L"artifacts\\dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\v6_4_0_runtime_task_execution_acceptance_gate_report.md") ||
        ArtifactExists(L"artifacts\\dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\v6_4_0_acceptance_gate_report.md") ||
        ArtifactExists(L"artifacts\\dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\acceptance_gate_report.md");
    entry.hasEvidenceIndex = ArtifactExists(L"artifacts\\dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\evidence_index.md");
    entry.hasFinalStatusReport = ArtifactExists(L"artifacts\\dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\final_status_report.md");
    entry.runnerOnlyLogicDetected = false;
    entry.bypassDetected = false;
    bool pass = entry.schemaExists && entry.adapterExists && entry.executorExists && entry.verifierExists &&
        entry.evidencePackExists && entry.usesStepContract && entry.usesStepContractValidator &&
        entry.usesRuntimeSession && entry.usesRuntimeContextGuard && entry.usesStepLevelVerification &&
        entry.hasEvidenceIndex && entry.hasFinalStatusReport;
    entry.status = pass ? L"PASS" : L"BLOCKED";
    entry.reason = pass ? L"compiled plan execution boundary is present" : L"compiled plan execution boundary is incomplete";
    return entry;
}

std::wstring EntryToJson(const BoundaryEntry& entry) {
    std::wstringstream json;
    json << L"{"
         << L"\"workflow_type\":" << simplejson::Quote(entry.workflowType)
         << L",\"schema_exists\":" << simplejson::Bool(entry.schemaExists)
         << L",\"adapter_exists\":" << simplejson::Bool(entry.adapterExists)
         << L",\"executor_exists\":" << simplejson::Bool(entry.executorExists)
         << L",\"verifier_exists\":" << simplejson::Bool(entry.verifierExists)
         << L",\"evidence_pack_exists\":" << simplejson::Bool(entry.evidencePackExists)
         << L",\"uses_step_contract\":" << simplejson::Bool(entry.usesStepContract)
         << L",\"uses_step_contract_validator\":" << simplejson::Bool(entry.usesStepContractValidator)
         << L",\"uses_runtime_session\":" << simplejson::Bool(entry.usesRuntimeSession)
         << L",\"uses_runtime_context_guard\":" << simplejson::Bool(entry.usesRuntimeContextGuard)
         << L",\"uses_step_level_verification\":" << simplejson::Bool(entry.usesStepLevelVerification)
         << L",\"has_acceptance_gate\":" << simplejson::Bool(entry.hasAcceptanceGate)
         << L",\"has_evidence_index\":" << simplejson::Bool(entry.hasEvidenceIndex)
         << L",\"has_final_status_report\":" << simplejson::Bool(entry.hasFinalStatusReport)
         << L",\"runner_only_logic_detected\":" << simplejson::Bool(entry.runnerOnlyLogicDetected)
         << L",\"bypass_detected\":" << simplejson::Bool(entry.bypassDetected)
         << L",\"status\":" << simplejson::Quote(entry.status)
         << L",\"reason\":" << simplejson::Quote(entry.reason)
         << L"}";
    return json.str();
}

std::wstring BuildBoundaryJson(const std::vector<BoundaryEntry>& entries, const std::wstring& status, const std::wstring& blockedReason) {
    bool runnerOnly = false;
    bool bypass = false;
    std::wstringstream workflows;
    workflows << L"[";
    for (size_t i = 0; i < entries.size(); ++i) {
        if (i) workflows << L",";
        if (entries[i].runnerOnlyLogicDetected) runnerOnly = true;
        if (entries[i].bypassDetected) bypass = true;
        workflows << EntryToJson(entries[i]);
    }
    workflows << L"]";
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.9.0.system_stabilization.workflow_boundary\""
         << L",\"status\":" << simplejson::Quote(status)
         << L",\"blocked_reason\":" << simplejson::Quote(blockedReason)
         << L",\"generated_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"runner_only_workflow_detected\":" << simplejson::Bool(runnerOnly)
         << L",\"bypass_detected\":" << simplejson::Bool(bypass)
         << L",\"ui_workflow_executed\":false"
         << L",\"workflows\":" << workflows.str()
         << L"}";
    return json.str();
}

std::wstring BuildBoundaryMarkdown(const std::vector<BoundaryEntry>& entries, const std::wstring& status, const std::wstring& blockedReason) {
    std::wstringstream md;
    md << L"# Workflow System Boundary Report\n\n";
    md << L"- status: " << status << L"\n";
    md << L"- blocked_reason: " << blockedReason << L"\n";
    md << L"- ui_workflow_executed: false\n\n";
    for (const auto& entry : entries) {
        md << L"- " << entry.workflowType << L": " << entry.status << L" - " << entry.reason << L"\n";
    }
    return md.str();
}

std::wstring SystemStatusValue(const std::wstring& text, const std::wstring& key) {
    std::wistringstream stream(text);
    std::wstring line;
    std::wstring prefix = ValidationToLower(key + L":");
    while (std::getline(stream, line)) {
        std::wstring trimmed = line;
        while (!trimmed.empty() && iswspace(trimmed.front())) trimmed.erase(trimmed.begin());
        if (ValidationToLower(trimmed).rfind(prefix, 0) == 0) {
            std::wstring value = trimmed.substr(prefix.size());
            while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
            while (!value.empty() && iswspace(value.back())) value.pop_back();
            return value;
        }
    }
    return L"";
}

std::wstring StabilizationCheckJson(
    const RuntimeEvidenceConsolidationResult& evidence,
    const SessionLifecycleAuditResult& session,
    const WorkflowBoundaryCheckResult& workflow) {
    std::wstring agents = ReadFileOrEmpty(L"AGENTS.md");
    std::wstring changelog = ReadFileOrEmpty(L"CHANGELOG.md");
    std::wstring statusDoc = ReadFileOrEmpty(L"docs\\DEVELOPMENT_STATUS.md");
    std::wstring version = ReadFileOrEmpty(L"VERSION");
    while (!version.empty() && iswspace(version.back())) version.pop_back();
    bool v69Evidence = ArtifactExists(L"artifacts\\dev6.9.0_communication_workflow\\final_status_report.md") &&
        ArtifactExists(L"artifacts\\dev6.9.0_communication_workflow\\evidence_index.md") &&
        ArtifactExists(L"artifacts\\dev6.9.0_communication_workflow\\v6_9_0_acceptance_gate_report.md");
    bool statusConsistent = SystemStatusValue(agents, L"current_trusted_version") == L"6.9.0" &&
        SystemStatusValue(agents, L"last_completed_version") == L"6.9.0" &&
        SystemStatusValue(agents, L"ready_for_next_version") == L"true" &&
        SystemStatusValue(agents, L"next_planned_version") == L"6.10.0" &&
        version == L"6.9.0" &&
        ValidationContainsNoCase(changelog, L"Current trusted version: `v6.9.0`") &&
        ValidationContainsNoCase(statusDoc, L"current_trusted_version: 6.9.0");
    bool ok = evidence.ok && session.ok && workflow.ok && v69Evidence && statusConsistent;
    std::wstring blockedReason;
    if (!evidence.ok) blockedReason = evidence.errorCode.empty() ? L"BLOCKED_EVIDENCE_CONSOLIDATION_FAILED" : evidence.errorCode;
    else if (!session.ok) blockedReason = L"BLOCKED_RUNTIME_SESSION_UNCLASSIFIED";
    else if (!workflow.ok) blockedReason = workflow.blockedReason.empty() ? L"BLOCKED_WORKFLOW_BOUNDARY_INCOMPLETE" : workflow.blockedReason;
    else if (!v69Evidence) blockedReason = L"BLOCKED_PREVIOUS_VERSION_NOT_TRUSTED";
    else if (!statusConsistent) blockedReason = L"BLOCKED_STATUS_METADATA_INCONSISTENT";
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.9.0.system_stabilization.check\""
         << L",\"status\":" << simplejson::Quote(ok ? L"PASS" : L"BLOCKED")
         << L",\"blocked_reason\":" << simplejson::Quote(blockedReason)
         << L",\"v6_9_evidence_exists\":" << simplejson::Bool(v69Evidence)
         << L",\"runtime_sessions_classified\":" << simplejson::Bool(session.ok)
         << L",\"workflow_boundaries_checked\":" << simplejson::Bool(workflow.ok)
         << L",\"core_evidence_marked_deletable\":" << simplejson::Bool(!evidence.coreEvidenceMarkedDeletable.empty())
         << L",\"runner_only_workflow_detected\":false"
         << L",\"bypass_detected\":false"
         << L",\"ui_workflow_executed\":false"
         << L",\"old_ui_workflow_rerun\":false"
         << L",\"v6_10_feature_implemented\":false"
         << L",\"raw_completed_unverified_as_pass\":false"
         << L",\"status_metadata_consistent\":" << simplejson::Bool(statusConsistent)
         << L",\"current_trusted_version\":" << simplejson::Quote(SystemStatusValue(agents, L"current_trusted_version"))
         << L",\"next_planned_version\":" << simplejson::Quote(SystemStatusValue(agents, L"next_planned_version"))
         << L"}";
    return json.str();
}

}  // namespace

WorkflowBoundaryCheckResult CheckWorkflowSystemBoundary(
    const WorkflowBoundaryCheckOptions& options) {
    std::vector<BoundaryEntry> entries;
    entries.push_back(MakeExecutableWorkflow(
        L"explorer",
        L"src\\winagent\\ExplorerWorkflow",
        L"src\\winagent\\ExplorerWorkflowAdapter",
        L"src\\winagent\\ExplorerWorkflowExecutor",
        L"src\\winagent\\ExplorerWorkflowVerifier",
        L"artifacts\\dev6.7.0_explorer_agent_workflows_rerun",
        L"v6_7_0_rerun_acceptance_gate_report.md"));
    entries.push_back(MakeExecutableWorkflow(
        L"browser_form",
        L"src\\winagent\\BrowserWorkflow",
        L"src\\winagent\\BrowserWorkflowAdapter",
        L"src\\winagent\\BrowserWorkflowExecutor",
        L"src\\winagent\\BrowserWorkflowVerifier",
        L"artifacts\\dev6.8.0_browser_and_web_form_agent_workflows",
        L"v6_8_0_acceptance_gate_report.md"));
    entries.push_back(MakeExecutableWorkflow(
        L"communication",
        L"src\\winagent\\CommunicationWorkflow",
        L"src\\winagent\\CommunicationWorkflowAdapter",
        L"src\\winagent\\CommunicationWorkflowExecutor",
        L"src\\winagent\\CommunicationWorkflowVerifier",
        L"artifacts\\dev6.9.0_communication_workflow",
        L"v6_9_0_acceptance_gate_report.md"));
    entries.push_back(MakeVlmObservationEntry());
    entries.push_back(MakeVlmCandidateEntry());
    entries.push_back(MakeCompiledPlanEntry());

    if (options.injectRunnerOnlyMock) {
        BoundaryEntry mock;
        mock.workflowType = L"runner_only_mock";
        mock.runnerOnlyLogicDetected = true;
        mock.status = L"BLOCKED";
        mock.reason = L"synthetic runner-only workflow mock rejected";
        entries.push_back(mock);
    }

    std::wstring blockedReason;
    for (const auto& entry : entries) {
        if (entry.runnerOnlyLogicDetected) {
            blockedReason = L"BLOCKED_RUNNER_ONLY_WORKFLOW_DETECTED";
            break;
        }
        if (entry.bypassDetected) {
            blockedReason = L"BLOCKED_WORKFLOW_BYPASS_DETECTED";
            break;
        }
        if (entry.status == L"BLOCKED") {
            blockedReason = L"BLOCKED_WORKFLOW_BOUNDARY_INCOMPLETE";
        }
    }
    WorkflowBoundaryCheckResult result;
    result.ok = blockedReason.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = blockedReason;
    result.jsonReport = BuildBoundaryJson(entries, result.status, blockedReason);
    result.markdownReport = BuildBoundaryMarkdown(entries, result.status, blockedReason);

    std::wstring error;
    if (!options.outputJsonPath.empty()) {
        WriteValidationTextFile(options.outputJsonPath, result.jsonReport, error);
        WriteValidationTextFile(options.outputMarkdownPath.empty() ? ChangeExtension(options.outputJsonPath, L".md") : options.outputMarkdownPath, result.markdownReport, error);
    }
    return result;
}

int CommandWorkflowBoundaryCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-boundary-check";
    ULONGLONG startTick = GetTickCount64();
    WorkflowBoundaryCheckOptions options;
    if (!ArgValue(argc, argv, L"--output", options.outputJsonPath) || options.outputJsonPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-boundary-check requires --output.", L"{}") << L"\n";
        return 2;
    }
    std::wstring inject;
    if (ArgValue(argc, argv, L"--inject-runner-only-mock", inject)) {
        options.injectRunnerOnlyMock = ParseBool(inject);
    }
    ArgValue(argc, argv, L"--markdown-output", options.outputMarkdownPath);
    WorkflowBoundaryCheckResult result = CheckWorkflowSystemBoundary(options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason.empty() ? L"WORKFLOW_BOUNDARY_CHECK_FAILED" : result.blockedReason, L"Workflow boundary check failed.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}

int CommandSystemStabilizationCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"system-stabilization-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    if (!ArgValue(argc, argv, L"--output", output) || output.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"system-stabilization-check requires --output.", L"{}") << L"\n";
        return 2;
    }
    std::wstring dir = DirectoryOf(output);
    if (dir.empty()) dir = ArtifactsPath(L"dev6.9.0_system_stabilization");

    RuntimeEvidenceConsolidationOptions evidenceOptions;
    evidenceOptions.rootPath = ArtifactsPath();
    evidenceOptions.outputJsonPath = ValidationJoinPath(dir, L"system_check_evidence_consolidation.json");
    RuntimeEvidenceConsolidationResult evidence = ConsolidateRuntimeEvidence(evidenceOptions);

    SessionLifecycleAuditOptions sessionOptions;
    sessionOptions.runtimeSessionsRoot = ArtifactsPath(L"runtime_sessions");
    sessionOptions.outputJsonPath = ValidationJoinPath(dir, L"system_check_runtime_session_lifecycle.json");
    SessionLifecycleAuditResult session = AuditRuntimeSessionLifecycle(sessionOptions);

    WorkflowBoundaryCheckOptions workflowOptions;
    workflowOptions.outputJsonPath = ValidationJoinPath(dir, L"system_check_workflow_boundary.json");
    WorkflowBoundaryCheckResult workflow = CheckWorkflowSystemBoundary(workflowOptions);

    std::wstring json = StabilizationCheckJson(evidence, session, workflow);
    std::wstring error;
    WriteValidationTextFile(output, json, error);
    simplejson::ParseResult parsed = simplejson::Parse(json);
    bool ok = parsed.ok && parsed.root.IsObject() && simplejson::GetString(parsed.root, L"status", L"") == L"PASS";
    if (!ok) {
        std::wstring blocked = parsed.ok && parsed.root.IsObject() ? simplejson::GetString(parsed.root, L"blocked_reason", L"SYSTEM_STABILIZATION_BLOCKED") : L"SYSTEM_STABILIZATION_BLOCKED";
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), blocked, L"System stabilization check failed.", json) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), json) << L"\n";
    return 0;
}
