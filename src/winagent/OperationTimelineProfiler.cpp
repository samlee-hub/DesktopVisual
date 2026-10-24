#include "OperationTimelineProfiler.h"

#include "CoreWaitState.h"
#include "SimpleJson.h"

#include <windows.h>

#include <sstream>

namespace {

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring NullOrQuoted(const std::wstring& value) {
    return value.empty() ? L"null" : simplejson::Quote(value);
}

std::wstring NullOrNumber(bool available, long long value) {
    return available ? std::to_wstring(value) : L"null";
}

std::wstring NullOrBool(bool available, bool value) {
    return available ? BoolJson(value) : L"null";
}

std::wstring NullOrStringArray(bool available, const std::vector<std::wstring>& values) {
    return available ? StringArrayJson(values) : L"null";
}

std::wstring TimestampUtc() {
    SYSTEMTIME time;
    GetSystemTime(&time);
    wchar_t buffer[40] = {};
    swprintf_s(
        buffer,
        L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds);
    return buffer;
}

std::wstring ForegroundTitle(HWND hwnd) {
    if (!hwnd) return L"";
    int length = GetWindowTextLengthW(hwnd);
    if (length <= 0) return L"";
    std::wstring title(static_cast<size_t>(length) + 1, L'\0');
    int copied = GetWindowTextW(hwnd, title.data(), length + 1);
    title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    return title;
}

struct LatencyScenarioRecord {
    std::wstring scenario;
    std::wstring command;
    std::wstring taskReceivedTs;
    std::wstring runtimeStartTs;
    std::wstring permissionCheckStartTs;
    std::wstring permissionCheckEndTs;
    std::wstring policyCheckStartTs;
    std::wstring policyCheckEndTs;
    std::wstring foregroundPrepareStartTs;
    std::wstring foregroundPrepareEndTs;
    std::wstring firstObserveStartTs;
    std::wstring firstObserveEndTs;
    std::wstring firstActionStartTs;
    std::wstring firstActionEndTs;
    std::wstring taskEndTs;
    bool hasTotalTaskLatencyMs = true;
    long long totalTaskLatencyMs = 0;
    bool hasFirstActionLatencyMs = false;
    long long firstActionLatencyMs = 0;
    bool hasPermissionCheckMs = false;
    long long permissionCheckMs = 0;
    bool hasPolicyCheckMs = false;
    long long policyCheckMs = 0;
    bool hasForegroundPrepareMs = false;
    long long foregroundPrepareMs = 0;
    bool hasFirstObserveMs = false;
    long long firstObserveMs = 0;
    bool hasFirstActionMs = false;
    long long firstActionMs = 0;
    bool hasScreenshotMs = false;
    long long screenshotMs = 0;
    bool hasUiaMs = false;
    long long uiaMs = 0;
    bool hasOcrMs = false;
    long long ocrMs = 0;
    bool hasFrameRegistryWriteMs = false;
    long long frameRegistryWriteMs = 0;
    bool hasEvidenceWriteMs = false;
    long long evidenceWriteMs = 0;
    bool hasObserveTotalMs = false;
    long long observeTotalMs = 0;
    bool vlmProbeAttempted = false;
    bool hasVlmProbeMs = false;
    long long vlmProbeMs = 0;
    bool hasVlmCacheHit = true;
    bool vlmCacheHit = false;
    std::wstring vlmCacheState = L"not_checked";
    bool hasVlmProviderStartupMs = false;
    long long vlmProviderStartupMs = 0;
    bool hasVlmExecMs = false;
    long long vlmExecMs = 0;
    bool hasVlmTotalMs = false;
    long long vlmTotalMs = 0;
    bool vlmUnavailable = false;
    bool vlmTimeout = false;
    bool vlmRequired = false;
    bool vlmAssistAllowed = false;
    bool vlmUsedForAction = false;
    bool vlmDegradedToRuntimeOnly = false;
    std::wstring vlmProbeReason;
    std::wstring vlmSkipReason = L"not_required";
    bool recoveryAttempted = false;
    bool hasRecoveryWaitMs = false;
    long long recoveryWaitMs = 0;
    bool hasFixedSleepWaitMs = false;
    long long fixedSleepWaitMs = 0;
    bool hasStateWaitTotalMs = false;
    long long stateWaitTotalMs = 0;
    bool hasStateWaitSavedMs = false;
    long long stateWaitSavedMs = 0;
    std::wstring waitReason;
    std::wstring waitSite;
    bool hasWaitBudgetMs = false;
    long long waitBudgetMs = 0;
    bool hasWaitActualMs = false;
    long long waitActualMs = 0;
    std::wstring waitExitReason;
    bool hasWaitReplacedFromSleepMs = false;
    long long waitReplacedFromSleepMs = 0;
    bool hasWaitStateReady = false;
    bool waitStateReady = false;
    bool hasWaitTimeoutCount = false;
    int waitTimeoutCount = 0;
    bool hasWaitNotReplacedCount = false;
    int waitNotReplacedCount = 0;
    std::vector<std::wstring> waitNotReplacedReasons;
    bool hasWorkflowWaitFields = false;
    long long workflowWaitTotalMs = 0;
    long long workflowWaitSavedMs = 0;
    int workflowWaitTimeoutCount = 0;
    int workflowWaitNotReplacedCount = 0;
    std::vector<std::wstring> workflowWaitSites;
    std::vector<std::wstring> workflowWaitReplacedFromSleepMs;
    std::vector<std::wstring> workflowWaitExitReasons;
    long long explorerWaitTotalMs = 0;
    long long explorerWaitSavedMs = 0;
    long long browserWaitTotalMs = 0;
    long long browserWaitSavedMs = 0;
    long long codeWorkflowWaitTotalMs = 0;
    long long codeWorkflowWaitSavedMs = 0;
    bool hasCodexThinkingGapMs = false;
    long long codexThinkingGapMs = 0;
    bool hasExternalAgentPlanningMs = false;
    long long externalAgentPlanningMs = 0;
    bool hasSkillContextLoadMs = false;
    long long skillContextLoadMs = 0;
    bool hasWinagentProcessStartMs = false;
    long long winagentProcessStartMs = 0;
    bool hasPowershellStartupMs = false;
    long long powershellStartupMs = 0;
    bool hasRunnerStartupMs = false;
    long long runnerStartupMs = 0;
    std::wstring firstActionReason = L"no_action_task";
    std::vector<std::wstring> unavailableFields;
    std::wstring notes;
    std::wstring observedForegroundTitle;
};

std::vector<std::wstring> DefaultUnavailableFields() {
    return {
        L"permission_check_start_ts",
        L"permission_check_end_ts",
        L"policy_check_start_ts",
        L"policy_check_end_ts",
        L"foreground_prepare_start_ts",
        L"foreground_prepare_end_ts",
        L"first_action_start_ts",
        L"first_action_end_ts",
        L"first_action_latency_ms",
        L"permission_check_ms",
        L"policy_check_ms",
        L"foreground_prepare_ms",
        L"first_action_ms",
        L"screenshot_ms",
        L"uia_ms",
        L"ocr_ms",
        L"frame_registry_write_ms",
        L"evidence_write_ms",
        L"vlm_probe_ms",
        L"vlm_provider_startup_ms",
        L"vlm_exec_ms",
        L"vlm_total_ms",
        L"recovery_wait_ms",
        L"fixed_sleep_wait_ms",
        L"state_wait_total_ms",
        L"state_wait_saved_ms",
        L"wait_reason",
        L"wait_site",
        L"wait_budget_ms",
        L"wait_actual_ms",
        L"wait_exit_reason",
        L"wait_replaced_from_sleep_ms",
        L"wait_state_ready",
        L"wait_timeout_count",
        L"wait_not_replaced_count",
        L"wait_not_replaced_reasons",
        L"workflow_wait_total_ms",
        L"workflow_wait_saved_ms",
        L"workflow_wait_timeout_count",
        L"workflow_wait_not_replaced_count",
        L"workflow_wait_sites",
        L"workflow_wait_replaced_from_sleep_ms",
        L"workflow_wait_exit_reasons",
        L"explorer_wait_total_ms",
        L"explorer_wait_saved_ms",
        L"browser_wait_total_ms",
        L"browser_wait_saved_ms",
        L"code_workflow_wait_total_ms",
        L"code_workflow_wait_saved_ms",
        L"codex_thinking_gap_ms",
        L"external_agent_planning_ms",
        L"skill_context_load_ms",
        L"winagent_process_start_ms",
        L"powershell_startup_ms",
        L"runner_startup_ms"
    };
}

void AddUnavailable(std::vector<std::wstring>& fields, const std::wstring& field) {
    for (const auto& existing : fields) {
        if (existing == field) return;
    }
    fields.push_back(field);
}

void RemoveUnavailable(std::vector<std::wstring>& fields, const std::wstring& field) {
    std::vector<std::wstring> filtered;
    for (const auto& existing : fields) {
        if (existing != field) filtered.push_back(existing);
    }
    fields.swap(filtered);
}

void AppendLatencyCommonFields(std::wstringstream& json, const LatencyScenarioRecord& record) {
    json << L"\"task_received_ts\":" << NullOrQuoted(record.taskReceivedTs)
         << L",\"runtime_start_ts\":" << NullOrQuoted(record.runtimeStartTs)
         << L",\"permission_check_start_ts\":" << NullOrQuoted(record.permissionCheckStartTs)
         << L",\"permission_check_end_ts\":" << NullOrQuoted(record.permissionCheckEndTs)
         << L",\"policy_check_start_ts\":" << NullOrQuoted(record.policyCheckStartTs)
         << L",\"policy_check_end_ts\":" << NullOrQuoted(record.policyCheckEndTs)
         << L",\"foreground_prepare_start_ts\":" << NullOrQuoted(record.foregroundPrepareStartTs)
         << L",\"foreground_prepare_end_ts\":" << NullOrQuoted(record.foregroundPrepareEndTs)
         << L",\"first_observe_start_ts\":" << NullOrQuoted(record.firstObserveStartTs)
         << L",\"first_observe_end_ts\":" << NullOrQuoted(record.firstObserveEndTs)
         << L",\"first_action_start_ts\":" << NullOrQuoted(record.firstActionStartTs)
         << L",\"first_action_end_ts\":" << NullOrQuoted(record.firstActionEndTs)
         << L",\"task_end_ts\":" << NullOrQuoted(record.taskEndTs)
         << L",\"total_task_latency_ms\":" << NullOrNumber(record.hasTotalTaskLatencyMs, record.totalTaskLatencyMs)
         << L",\"first_action_latency_ms\":" << NullOrNumber(record.hasFirstActionLatencyMs, record.firstActionLatencyMs)
         << L",\"permission_check_ms\":" << NullOrNumber(record.hasPermissionCheckMs, record.permissionCheckMs)
         << L",\"policy_check_ms\":" << NullOrNumber(record.hasPolicyCheckMs, record.policyCheckMs)
         << L",\"foreground_prepare_ms\":" << NullOrNumber(record.hasForegroundPrepareMs, record.foregroundPrepareMs)
         << L",\"first_observe_ms\":" << NullOrNumber(record.hasFirstObserveMs, record.firstObserveMs)
         << L",\"first_action_ms\":" << NullOrNumber(record.hasFirstActionMs, record.firstActionMs)
         << L",\"screenshot_ms\":" << NullOrNumber(record.hasScreenshotMs, record.screenshotMs)
         << L",\"uia_ms\":" << NullOrNumber(record.hasUiaMs, record.uiaMs)
         << L",\"ocr_ms\":" << NullOrNumber(record.hasOcrMs, record.ocrMs)
         << L",\"frame_registry_write_ms\":" << NullOrNumber(record.hasFrameRegistryWriteMs, record.frameRegistryWriteMs)
         << L",\"evidence_write_ms\":" << NullOrNumber(record.hasEvidenceWriteMs, record.evidenceWriteMs)
         << L",\"observe_total_ms\":" << NullOrNumber(record.hasObserveTotalMs, record.observeTotalMs)
         << L",\"vlm_probe_attempted\":" << BoolJson(record.vlmProbeAttempted)
         << L",\"vlm_probe_ms\":" << NullOrNumber(record.hasVlmProbeMs, record.vlmProbeMs)
         << L",\"vlm_cache_hit\":" << NullOrBool(record.hasVlmCacheHit, record.vlmCacheHit)
         << L",\"vlm_cache_state\":" << NullOrQuoted(record.vlmCacheState)
         << L",\"vlm_provider_startup_ms\":" << NullOrNumber(record.hasVlmProviderStartupMs, record.vlmProviderStartupMs)
         << L",\"vlm_exec_ms\":" << NullOrNumber(record.hasVlmExecMs, record.vlmExecMs)
         << L",\"vlm_total_ms\":" << NullOrNumber(record.hasVlmTotalMs, record.vlmTotalMs)
         << L",\"vlm_unavailable\":" << BoolJson(record.vlmUnavailable)
         << L",\"vlm_timeout\":" << BoolJson(record.vlmTimeout)
         << L",\"vlm_required\":" << BoolJson(record.vlmRequired)
         << L",\"vlm_assist_allowed\":" << BoolJson(record.vlmAssistAllowed)
         << L",\"vlm_used_for_action\":" << BoolJson(record.vlmUsedForAction)
         << L",\"vlm_degraded_to_runtime_only\":" << BoolJson(record.vlmDegradedToRuntimeOnly)
         << L",\"vlm_probe_reason\":" << NullOrQuoted(record.vlmProbeReason)
         << L",\"vlm_skip_reason\":" << NullOrQuoted(record.vlmSkipReason)
         << L",\"recovery_attempted\":" << BoolJson(record.recoveryAttempted)
         << L",\"recovery_wait_ms\":" << NullOrNumber(record.hasRecoveryWaitMs, record.recoveryWaitMs)
         << L",\"fixed_sleep_wait_ms\":" << NullOrNumber(record.hasFixedSleepWaitMs, record.fixedSleepWaitMs)
         << L",\"state_wait_total_ms\":" << NullOrNumber(record.hasStateWaitTotalMs, record.stateWaitTotalMs)
         << L",\"state_wait_saved_ms\":" << NullOrNumber(record.hasStateWaitSavedMs, record.stateWaitSavedMs)
         << L",\"wait_reason\":" << NullOrQuoted(record.waitReason)
         << L",\"wait_site\":" << NullOrQuoted(record.waitSite)
         << L",\"wait_budget_ms\":" << NullOrNumber(record.hasWaitBudgetMs, record.waitBudgetMs)
         << L",\"wait_actual_ms\":" << NullOrNumber(record.hasWaitActualMs, record.waitActualMs)
         << L",\"wait_exit_reason\":" << NullOrQuoted(record.waitExitReason)
         << L",\"wait_replaced_from_sleep_ms\":" << NullOrNumber(record.hasWaitReplacedFromSleepMs, record.waitReplacedFromSleepMs)
         << L",\"wait_state_ready\":" << NullOrBool(record.hasWaitStateReady, record.waitStateReady)
         << L",\"wait_timeout_count\":" << NullOrNumber(record.hasWaitTimeoutCount, record.waitTimeoutCount)
         << L",\"wait_not_replaced_count\":" << NullOrNumber(record.hasWaitNotReplacedCount, record.waitNotReplacedCount)
         << L",\"wait_not_replaced_reasons\":" << NullOrStringArray(record.hasWaitNotReplacedCount, record.waitNotReplacedReasons)
         << L",\"workflow_wait_total_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.workflowWaitTotalMs)
         << L",\"workflow_wait_saved_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.workflowWaitSavedMs)
         << L",\"workflow_wait_timeout_count\":" << NullOrNumber(record.hasWorkflowWaitFields, record.workflowWaitTimeoutCount)
         << L",\"workflow_wait_not_replaced_count\":" << NullOrNumber(record.hasWorkflowWaitFields, record.workflowWaitNotReplacedCount)
         << L",\"workflow_wait_sites\":" << NullOrStringArray(record.hasWorkflowWaitFields, record.workflowWaitSites)
         << L",\"workflow_wait_replaced_from_sleep_ms\":" << NullOrStringArray(record.hasWorkflowWaitFields, record.workflowWaitReplacedFromSleepMs)
         << L",\"workflow_wait_exit_reasons\":" << NullOrStringArray(record.hasWorkflowWaitFields, record.workflowWaitExitReasons)
         << L",\"explorer_wait_total_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.explorerWaitTotalMs)
         << L",\"explorer_wait_saved_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.explorerWaitSavedMs)
         << L",\"browser_wait_total_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.browserWaitTotalMs)
         << L",\"browser_wait_saved_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.browserWaitSavedMs)
         << L",\"code_workflow_wait_total_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.codeWorkflowWaitTotalMs)
         << L",\"code_workflow_wait_saved_ms\":" << NullOrNumber(record.hasWorkflowWaitFields, record.codeWorkflowWaitSavedMs)
         << L",\"codex_thinking_gap_ms\":" << NullOrNumber(record.hasCodexThinkingGapMs, record.codexThinkingGapMs)
         << L",\"external_agent_planning_ms\":" << NullOrNumber(record.hasExternalAgentPlanningMs, record.externalAgentPlanningMs)
         << L",\"skill_context_load_ms\":" << NullOrNumber(record.hasSkillContextLoadMs, record.skillContextLoadMs)
         << L",\"winagent_process_start_ms\":" << NullOrNumber(record.hasWinagentProcessStartMs, record.winagentProcessStartMs)
         << L",\"powershell_startup_ms\":" << NullOrNumber(record.hasPowershellStartupMs, record.powershellStartupMs)
         << L",\"runner_startup_ms\":" << NullOrNumber(record.hasRunnerStartupMs, record.runnerStartupMs)
         << L",\"first_action_reason\":" << simplejson::Quote(record.firstActionReason)
         << L",\"unavailable_fields\":" << StringArrayJson(record.unavailableFields)
         << L",\"notes\":" << simplejson::Quote(record.notes);
}

std::wstring LatencyScenarioJson(const LatencyScenarioRecord& record) {
    std::wstringstream json;
    json << L"{\"scenario\":" << simplejson::Quote(record.scenario)
         << L",\"command\":" << simplejson::Quote(record.command)
         << L",";
    AppendLatencyCommonFields(json, record);
    if (!record.observedForegroundTitle.empty()) {
        json << L",\"observed_foreground_title\":" << simplejson::Quote(record.observedForegroundTitle);
    }
    json << L"}";
    return json.str();
}

LatencyScenarioRecord StartScenario(const std::wstring& scenario, const std::wstring& command) {
    LatencyScenarioRecord record;
    record.scenario = scenario;
    record.command = command;
    record.taskReceivedTs = TimestampUtc();
    record.runtimeStartTs = record.taskReceivedTs;
    record.unavailableFields = DefaultUnavailableFields();
    return record;
}

void FinishScenario(LatencyScenarioRecord& record, ULONGLONG startTick) {
    record.taskEndTs = TimestampUtc();
    record.totalTaskLatencyMs = static_cast<long long>(GetTickCount64() - startTick);
}

LatencyScenarioRecord MetadataNoActionScenario(const std::wstring& command) {
    ULONGLONG start = GetTickCount64();
    LatencyScenarioRecord record = StartScenario(L"metadata_no_action", command);
    AddUnavailable(record.unavailableFields, L"first_observe_start_ts");
    AddUnavailable(record.unavailableFields, L"first_observe_end_ts");
    AddUnavailable(record.unavailableFields, L"first_observe_ms");
    AddUnavailable(record.unavailableFields, L"observe_total_ms");
    record.firstActionReason = L"no_action_task";
    record.vlmSkipReason = L"not_required";
    record.notes = L"Metadata-only latency report path; no externally visible action is executed.";
    FinishScenario(record, start);
    return record;
}

LatencyScenarioRecord RuntimeForegroundSnapshotScenario(const std::wstring& command) {
    ULONGLONG start = GetTickCount64();
    LatencyScenarioRecord record = StartScenario(L"runtime_foreground_snapshot", command);
    record.firstObserveStartTs = TimestampUtc();
    ULONGLONG observeStart = GetTickCount64();
    HWND foreground = GetForegroundWindow();
    record.observedForegroundTitle = ForegroundTitle(foreground);
    ULONGLONG observeEnd = GetTickCount64();
    record.firstObserveEndTs = TimestampUtc();
    record.firstObserveMs = static_cast<long long>(observeEnd - observeStart);
    record.observeTotalMs = record.firstObserveMs;
    record.hasFirstObserveMs = true;
    record.hasObserveTotalMs = true;
    RemoveUnavailable(record.unavailableFields, L"first_observe_start_ts");
    RemoveUnavailable(record.unavailableFields, L"first_observe_end_ts");
    RemoveUnavailable(record.unavailableFields, L"first_observe_ms");
    RemoveUnavailable(record.unavailableFields, L"observe_total_ms");
    record.firstActionReason = L"no_action_task";
    record.vlmSkipReason = L"runtime_only_path";
    record.notes = L"Read-only foreground window snapshot for observe timing; no focus, input, VLM, or workflow action is executed.";
    FinishScenario(record, start);
    return record;
}

LatencyScenarioRecord VlmNotRequiredScenario(const std::wstring& command) {
    ULONGLONG start = GetTickCount64();
    LatencyScenarioRecord record = StartScenario(L"vlm_not_required", command);
    AddUnavailable(record.unavailableFields, L"first_observe_start_ts");
    AddUnavailable(record.unavailableFields, L"first_observe_end_ts");
    AddUnavailable(record.unavailableFields, L"first_observe_ms");
    AddUnavailable(record.unavailableFields, L"observe_total_ms");
    record.vlmProbeAttempted = false;
    record.vlmRequired = false;
    record.vlmAssistAllowed = false;
    record.vlmUsedForAction = false;
    record.vlmUnavailable = false;
    record.vlmTimeout = false;
    record.vlmCacheHit = false;
    record.vlmCacheState = L"not_checked";
    record.vlmDegradedToRuntimeOnly = false;
    record.vlmSkipReason = L"not_required";
    record.firstActionReason = L"no_action_task";
    record.notes = L"Baseline path records VLM fields while confirming VLM is not required and no provider probe is attempted.";
    FinishScenario(record, start);
    return record;
}

void ApplyCoreWaitFields(
    LatencyScenarioRecord& record,
    const CoreWaitStateResult& wait,
    const CoreWaitStateSummary& summary) {
    record.hasFixedSleepWaitMs = true;
    record.fixedSleepWaitMs = summary.fixedSleepWaitMs;
    record.hasStateWaitTotalMs = true;
    record.stateWaitTotalMs = summary.stateWaitTotalMs;
    record.hasStateWaitSavedMs = true;
    record.stateWaitSavedMs = summary.stateWaitSavedMs;
    record.waitReason = wait.waitReason;
    record.waitSite = wait.waitSite;
    record.hasWaitBudgetMs = true;
    record.waitBudgetMs = wait.waitBudgetMs;
    record.hasWaitActualMs = true;
    record.waitActualMs = wait.waitActualMs;
    record.waitExitReason = wait.waitExitReason;
    record.hasWaitReplacedFromSleepMs = true;
    record.waitReplacedFromSleepMs = wait.waitReplacedFromSleepMs;
    record.hasWaitStateReady = true;
    record.waitStateReady = wait.stateReady;
    record.hasWaitTimeoutCount = true;
    record.waitTimeoutCount = summary.waitTimeoutCount;
    record.hasWaitNotReplacedCount = true;
    record.waitNotReplacedCount = summary.waitNotReplacedCount;
    record.waitNotReplacedReasons = summary.waitNotReplacedReasons;

    const std::vector<std::wstring> available = {
        L"fixed_sleep_wait_ms",
        L"state_wait_total_ms",
        L"state_wait_saved_ms",
        L"wait_reason",
        L"wait_site",
        L"wait_budget_ms",
        L"wait_actual_ms",
        L"wait_exit_reason",
        L"wait_replaced_from_sleep_ms",
        L"wait_state_ready",
        L"wait_timeout_count",
        L"wait_not_replaced_count",
        L"wait_not_replaced_reasons"
    };
    for (const auto& field : available) {
        RemoveUnavailable(record.unavailableFields, field);
    }
}

void ApplyWorkflowWaitFields(
    LatencyScenarioRecord& record,
    const WorkflowWaitStateSummary& summary) {
    record.hasWorkflowWaitFields = true;
    record.workflowWaitTotalMs = summary.workflowWaitTotalMs;
    record.workflowWaitSavedMs = summary.workflowWaitSavedMs;
    record.workflowWaitTimeoutCount = summary.workflowWaitTimeoutCount;
    record.workflowWaitNotReplacedCount = summary.workflowWaitNotReplacedCount;
    record.workflowWaitSites = summary.workflowWaitSites;
    record.workflowWaitReplacedFromSleepMs = summary.workflowWaitReplacedFromSleepMs;
    record.workflowWaitExitReasons = summary.workflowWaitExitReasons;
    record.explorerWaitTotalMs = summary.explorerWaitTotalMs;
    record.explorerWaitSavedMs = summary.explorerWaitSavedMs;
    record.browserWaitTotalMs = summary.browserWaitTotalMs;
    record.browserWaitSavedMs = summary.browserWaitSavedMs;
    record.codeWorkflowWaitTotalMs = summary.codeWorkflowWaitTotalMs;
    record.codeWorkflowWaitSavedMs = summary.codeWorkflowWaitSavedMs;

    const std::vector<std::wstring> available = {
        L"workflow_wait_total_ms",
        L"workflow_wait_saved_ms",
        L"workflow_wait_timeout_count",
        L"workflow_wait_not_replaced_count",
        L"workflow_wait_sites",
        L"workflow_wait_replaced_from_sleep_ms",
        L"workflow_wait_exit_reasons",
        L"explorer_wait_total_ms",
        L"explorer_wait_saved_ms",
        L"browser_wait_total_ms",
        L"browser_wait_saved_ms",
        L"code_workflow_wait_total_ms",
        L"code_workflow_wait_saved_ms"
    };
    for (const auto& field : available) {
        RemoveUnavailable(record.unavailableFields, field);
    }
}

LatencyScenarioRecord CoreStateWaitProbeScenario(const std::wstring& command) {
    ULONGLONG start = GetTickCount64();
    LatencyScenarioRecord record = StartScenario(L"core_state_wait_probe", command);
    CoreWaitStateOptions options;
    options.waitSite = L"OperationTimelineProfiler.core_state_wait_probe";
    options.waitReason = L"latency_schema_state_wait_field_probe";
    options.waitBudgetMs = 500;
    options.waitPollIntervalMs = 40;
    options.waitReplacedFromSleepMs = 500;
    options.record = false;
    CoreWaitStateResult wait = WaitForCoreState(options, []() {
        return true;
    });
    CoreWaitStateSummary summary = BuildCoreWaitStateSummary({wait});
    ApplyCoreWaitFields(record, wait, summary);
    record.firstActionReason = L"no_action_task";
    record.vlmSkipReason = L"not_required";
    record.notes = L"Runtime/report state-wait probe; no externally visible action is executed and state-ready exits early.";
    FinishScenario(record, start);
    return record;
}

LatencyScenarioRecord WorkflowStateWaitProbeScenario(const std::wstring& command) {
    ULONGLONG start = GetTickCount64();
    LatencyScenarioRecord record = StartScenario(L"workflow_state_wait_probe", command);

    CoreWaitStateOptions explorerOptions;
    explorerOptions.waitSite = L"OperationTimelineProfiler.workflow_state_wait_probe.explorer";
    explorerOptions.waitReason = L"workflow_latency_schema_explorer_wait_probe";
    explorerOptions.waitBudgetMs = 700;
    explorerOptions.waitPollIntervalMs = 40;
    explorerOptions.waitReplacedFromSleepMs = 700;
    explorerOptions.waitStatePredicate = L"WaitUntilExplorerFrameStable";
    explorerOptions.record = false;
    CoreWaitStateResult explorerWait = WaitForWorkflowState(
        L"ExplorerWorkflowExecutor",
        L"explorer",
        explorerOptions,
        []() { return true; });

    CoreWaitStateOptions browserOptions;
    browserOptions.waitSite = L"OperationTimelineProfiler.workflow_state_wait_probe.browser";
    browserOptions.waitReason = L"workflow_latency_schema_browser_wait_probe";
    browserOptions.waitBudgetMs = 600;
    browserOptions.waitPollIntervalMs = 40;
    browserOptions.waitReplacedFromSleepMs = 600;
    browserOptions.waitStatePredicate = L"WaitUntilBrowserFrameStable";
    browserOptions.record = false;
    CoreWaitStateResult browserWait = WaitForWorkflowState(
        L"BrowserWorkflowExecutor",
        L"browser",
        browserOptions,
        []() { return true; });

    WorkflowWaitStateSummary summary = BuildWorkflowWaitStateSummary({explorerWait, browserWait});
    ApplyWorkflowWaitFields(record, summary);
    record.firstActionReason = L"no_action_task";
    record.vlmSkipReason = L"not_required";
    record.notes = L"Runtime/report workflow state-wait probe; no externally visible action is executed and state-ready exits early.";
    FinishScenario(record, start);
    return record;
}

std::wstring ScenarioArrayJson(const std::vector<LatencyScenarioRecord>& records) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < records.size(); ++i) {
        if (i) json << L",";
        json << LatencyScenarioJson(records[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring CategoryTotalsJson(const std::map<std::wstring, long long>& totals) {
    std::wstringstream json;
    json << L"{";
    bool first = true;
    for (const auto& item : totals) {
        if (!first) json << L",";
        first = false;
        json << simplejson::Quote(item.first) << L":" << item.second;
    }
    json << L"}";
    return json.str();
}

}  // namespace

std::vector<std::wstring> OperationTimelineRequiredFields() {
    return {
        L"operation_id",
        L"parent_task_id",
        L"operation_type",
        L"command",
        L"start_time_utc",
        L"end_time_utc",
        L"wall_clock_ms",
        L"runtime_duration_ms",
        L"orchestration_overhead_ms",
        L"stage",
        L"attempt_index",
        L"attempt_mode",
        L"target_title",
        L"target_process",
        L"foreground_before",
        L"foreground_after",
        L"used_global_screenshot",
        L"used_target_lock",
        L"used_coordinate_mapper",
        L"used_foreground_preempt",
        L"used_real_keyboard_input",
        L"used_clipboard",
        L"used_backend",
        L"used_shortcut",
        L"fixed_sleep_ms",
        L"sleep_ms",
        L"wait_condition",
        L"wait_condition_ms",
        L"manual_view_image_ms",
        L"codex_thinking_gap_ms",
        L"process_startup_overhead_ms",
        L"result",
        L"error_code",
        L"evidence_ref",
        L"external_orchestration_delay",
        L"fixed_sleep_candidate"
    };
}

void FinalizeOperationTimelineEntry(OperationTimelineEntry& entry) {
    entry.orchestrationOverheadMs = entry.wallClockMs - entry.runtimeDurationMs;
    if (entry.orchestrationOverheadMs < 0) {
        entry.orchestrationOverheadMs = 0;
    }
}

bool IsOperationTimelineExternalOrchestrationDelay(const OperationTimelineEntry& entry) {
    return entry.runtimeDurationMs < 500 && entry.wallClockMs > 5000;
}

bool IsOperationTimelineFixedSleepCandidate(const OperationTimelineEntry& entry) {
    return entry.fixedSleepMs > 1000;
}

std::wstring OperationTimelineEntryJson(const OperationTimelineEntry& entry) {
    std::wstringstream json;
    json << L"{"
         << L"\"operation_id\":" << simplejson::Quote(entry.operationId)
         << L",\"parent_task_id\":" << simplejson::Quote(entry.parentTaskId)
         << L",\"operation_type\":" << simplejson::Quote(entry.operationType)
         << L",\"command\":" << simplejson::Quote(entry.command)
         << L",\"start_time_utc\":" << simplejson::Quote(entry.startTimeUtc)
         << L",\"end_time_utc\":" << simplejson::Quote(entry.endTimeUtc)
         << L",\"wall_clock_ms\":" << entry.wallClockMs
         << L",\"runtime_duration_ms\":" << entry.runtimeDurationMs
         << L",\"orchestration_overhead_ms\":" << entry.orchestrationOverheadMs
         << L",\"stage\":" << simplejson::Quote(entry.stage)
         << L",\"attempt_index\":" << entry.attemptIndex
         << L",\"attempt_mode\":" << simplejson::Quote(entry.attemptMode)
         << L",\"target_title\":" << simplejson::Quote(entry.targetTitle)
         << L",\"target_process\":" << simplejson::Quote(entry.targetProcess)
         << L",\"foreground_before\":" << simplejson::Quote(entry.foregroundBefore)
         << L",\"foreground_after\":" << simplejson::Quote(entry.foregroundAfter)
         << L",\"used_global_screenshot\":" << BoolJson(entry.usedGlobalScreenshot)
         << L",\"used_target_lock\":" << BoolJson(entry.usedTargetLock)
         << L",\"used_coordinate_mapper\":" << BoolJson(entry.usedCoordinateMapper)
         << L",\"used_foreground_preempt\":" << BoolJson(entry.usedForegroundPreempt)
         << L",\"used_real_keyboard_input\":" << BoolJson(entry.usedRealKeyboardInput)
         << L",\"used_clipboard\":" << BoolJson(entry.usedClipboard)
         << L",\"used_backend\":" << BoolJson(entry.usedBackend)
         << L",\"used_shortcut\":" << BoolJson(entry.usedShortcut)
         << L",\"fixed_sleep_ms\":" << entry.fixedSleepMs
         << L",\"sleep_ms\":" << entry.fixedSleepMs
         << L",\"wait_condition\":" << simplejson::Quote(entry.waitCondition)
         << L",\"wait_condition_ms\":" << entry.waitConditionMs
         << L",\"manual_view_image_ms\":" << entry.manualViewImageMs
         << L",\"codex_thinking_gap_ms\":" << entry.codexThinkingGapMs
         << L",\"process_startup_overhead_ms\":" << entry.processStartupOverheadMs
         << L",\"result\":" << simplejson::Quote(entry.result)
         << L",\"error_code\":" << simplejson::Quote(entry.errorCode)
         << L",\"evidence_ref\":" << simplejson::Quote(entry.evidenceRef)
         << L",\"external_orchestration_delay\":" << BoolJson(IsOperationTimelineExternalOrchestrationDelay(entry))
         << L",\"fixed_sleep_candidate\":" << BoolJson(IsOperationTimelineFixedSleepCandidate(entry))
         << L"}";
    return json.str();
}

std::wstring OperationTimelineProfilerSelftestDataJson() {
    OperationTimelineEntry sample;
    sample.operationId = L"op-selftest-001";
    sample.parentTaskId = L"timeline-selftest";
    sample.operationType = L"global_screenshot";
    sample.command = L"winagent.exe global-screenshot --out sample.png";
    sample.startTimeUtc = L"2026-06-19T00:00:00.0000000Z";
    sample.endTimeUtc = L"2026-06-19T00:00:05.2000000Z";
    sample.wallClockMs = 5200;
    sample.runtimeDurationMs = 400;
    sample.stage = L"selftest";
    sample.attemptIndex = 1;
    sample.attemptMode = L"visible";
    sample.targetTitle = L"Desktop";
    sample.targetProcess = L"explorer.exe";
    sample.usedGlobalScreenshot = true;
    sample.usedTargetLock = true;
    sample.usedCoordinateMapper = true;
    sample.usedForegroundPreempt = true;
    sample.fixedSleepMs = 1200;
    sample.waitCondition = L"window_visible";
    sample.waitConditionMs = 700;
    sample.processStartupOverheadMs = 300;
    sample.result = L"ok";
    sample.evidenceRef = L"sample.stdout.json";
    FinalizeOperationTimelineEntry(sample);

    std::map<std::wstring, long long> totals;
    totals[L"foreground_preempt_ms"] = 400;
    totals[L"global_screenshot_ms"] = 1500;
    totals[L"target_lock_ms"] = 200;
    totals[L"coordinate_mapping_ms"] = 100;
    totals[L"fixed_sleep_ms"] = sample.fixedSleepMs;
    totals[L"wait_condition_ms"] = sample.waitConditionMs;
    totals[L"process_spawn_ms"] = sample.processStartupOverheadMs;

    std::wstringstream data;
    data << L"{"
         << L"\"schema_version\":\"operation_timeline.v1\""
         << L",\"required_fields\":" << StringArrayJson(OperationTimelineRequiredFields())
         << L",\"sample\":" << OperationTimelineEntryJson(sample)
         << L",\"category_totals\":" << CategoryTotalsJson(totals)
         << L"}";
    return data.str();
}

std::wstring LatencyObservabilityRequiredFieldsJson() {
    return StringArrayJson({
        L"version",
        L"generated_at",
        L"command",
        L"schema",
        L"scenarios",
        L"task_received_ts",
        L"runtime_start_ts",
        L"permission_check_start_ts",
        L"permission_check_end_ts",
        L"policy_check_start_ts",
        L"policy_check_end_ts",
        L"foreground_prepare_start_ts",
        L"foreground_prepare_end_ts",
        L"first_observe_start_ts",
        L"first_observe_end_ts",
        L"first_action_start_ts",
        L"first_action_end_ts",
        L"task_end_ts",
        L"total_task_latency_ms",
        L"first_action_latency_ms",
        L"permission_check_ms",
        L"policy_check_ms",
        L"foreground_prepare_ms",
        L"first_observe_ms",
        L"first_action_ms",
        L"screenshot_ms",
        L"uia_ms",
        L"ocr_ms",
        L"frame_registry_write_ms",
        L"evidence_write_ms",
        L"observe_total_ms",
        L"vlm_probe_attempted",
        L"vlm_probe_ms",
        L"vlm_cache_hit",
        L"vlm_cache_state",
        L"vlm_provider_startup_ms",
        L"vlm_exec_ms",
        L"vlm_total_ms",
        L"vlm_unavailable",
        L"vlm_timeout",
        L"vlm_required",
        L"vlm_assist_allowed",
        L"vlm_used_for_action",
        L"vlm_degraded_to_runtime_only",
        L"vlm_probe_reason",
        L"vlm_skip_reason",
        L"recovery_attempted",
        L"recovery_wait_ms",
        L"fixed_sleep_wait_ms",
        L"state_wait_total_ms",
        L"state_wait_saved_ms",
        L"wait_reason",
        L"wait_site",
        L"wait_budget_ms",
        L"wait_actual_ms",
        L"wait_exit_reason",
        L"wait_replaced_from_sleep_ms",
        L"wait_state_ready",
        L"wait_timeout_count",
        L"wait_not_replaced_count",
        L"wait_not_replaced_reasons",
        L"workflow_wait_total_ms",
        L"workflow_wait_saved_ms",
        L"workflow_wait_timeout_count",
        L"workflow_wait_not_replaced_count",
        L"workflow_wait_sites",
        L"workflow_wait_replaced_from_sleep_ms",
        L"workflow_wait_exit_reasons",
        L"explorer_wait_total_ms",
        L"explorer_wait_saved_ms",
        L"browser_wait_total_ms",
        L"browser_wait_saved_ms",
        L"code_workflow_wait_total_ms",
        L"code_workflow_wait_saved_ms",
        L"codex_thinking_gap_ms",
        L"external_agent_planning_ms",
        L"skill_context_load_ms",
        L"winagent_process_start_ms",
        L"powershell_startup_ms",
        L"runner_startup_ms",
        L"first_action_reason",
        L"unavailable_fields",
        L"notes"
    });
}

std::wstring BuildLatencyBaselineSummaryJson(const std::wstring& version, const std::wstring& command) {
    ULONGLONG aggregateStart = GetTickCount64();
    std::wstring aggregateReceivedTs = TimestampUtc();

    std::vector<LatencyScenarioRecord> scenarios;
    scenarios.push_back(MetadataNoActionScenario(command));
    scenarios.push_back(RuntimeForegroundSnapshotScenario(command));
    scenarios.push_back(VlmNotRequiredScenario(command));
    scenarios.push_back(CoreStateWaitProbeScenario(command));
    scenarios.push_back(WorkflowStateWaitProbeScenario(command));

    LatencyScenarioRecord aggregate = StartScenario(L"aggregate", command);
    aggregate.taskReceivedTs = aggregateReceivedTs;
    aggregate.runtimeStartTs = aggregateReceivedTs;
    aggregate.taskEndTs = TimestampUtc();
    aggregate.totalTaskLatencyMs = static_cast<long long>(GetTickCount64() - aggregateStart);
    aggregate.firstObserveStartTs = scenarios[1].firstObserveStartTs;
    aggregate.firstObserveEndTs = scenarios[1].firstObserveEndTs;
    aggregate.firstObserveMs = scenarios[1].firstObserveMs;
    aggregate.observeTotalMs = scenarios[1].observeTotalMs;
    aggregate.hasFirstObserveMs = scenarios[1].hasFirstObserveMs;
    aggregate.hasObserveTotalMs = scenarios[1].hasObserveTotalMs;
    aggregate.vlmProbeAttempted = false;
    aggregate.vlmRequired = false;
    aggregate.vlmAssistAllowed = false;
    aggregate.vlmUsedForAction = false;
    aggregate.vlmUnavailable = false;
    aggregate.vlmTimeout = false;
    aggregate.vlmCacheHit = false;
    aggregate.vlmCacheState = L"not_checked";
    aggregate.vlmDegradedToRuntimeOnly = false;
    aggregate.vlmSkipReason = L"runtime_only_path";
    aggregate.firstActionReason = L"no_action_task";
    CoreWaitStateResult aggregateWait;
    aggregateWait.waitSite = scenarios[3].waitSite;
    aggregateWait.waitReason = scenarios[3].waitReason;
    aggregateWait.waitBudgetMs = static_cast<int>(scenarios[3].waitBudgetMs);
    aggregateWait.waitActualMs = scenarios[3].waitActualMs;
    aggregateWait.waitExitReason = scenarios[3].waitExitReason;
    aggregateWait.waitReplacedFromSleepMs = static_cast<int>(scenarios[3].waitReplacedFromSleepMs);
    aggregateWait.stateReady = scenarios[3].waitStateReady;
    aggregateWait.stateWaitSavedMs = scenarios[3].stateWaitSavedMs;
    CoreWaitStateSummary aggregateWaitSummary;
    aggregateWaitSummary.fixedSleepWaitMs = scenarios[3].fixedSleepWaitMs;
    aggregateWaitSummary.stateWaitTotalMs = scenarios[3].stateWaitTotalMs;
    aggregateWaitSummary.stateWaitSavedMs = scenarios[3].stateWaitSavedMs;
    aggregateWaitSummary.waitTimeoutCount = scenarios[3].waitTimeoutCount;
    aggregateWaitSummary.waitNotReplacedCount = scenarios[3].waitNotReplacedCount;
    aggregateWaitSummary.waitNotReplacedReasons = scenarios[3].waitNotReplacedReasons;
    ApplyCoreWaitFields(aggregate, aggregateWait, aggregateWaitSummary);
    WorkflowWaitStateSummary aggregateWorkflowWaitSummary;
    aggregateWorkflowWaitSummary.workflowWaitTotalMs = scenarios[4].workflowWaitTotalMs;
    aggregateWorkflowWaitSummary.workflowWaitSavedMs = scenarios[4].workflowWaitSavedMs;
    aggregateWorkflowWaitSummary.workflowWaitTimeoutCount = scenarios[4].workflowWaitTimeoutCount;
    aggregateWorkflowWaitSummary.workflowWaitNotReplacedCount = scenarios[4].workflowWaitNotReplacedCount;
    aggregateWorkflowWaitSummary.workflowWaitSites = scenarios[4].workflowWaitSites;
    aggregateWorkflowWaitSummary.workflowWaitReplacedFromSleepMs = scenarios[4].workflowWaitReplacedFromSleepMs;
    aggregateWorkflowWaitSummary.workflowWaitExitReasons = scenarios[4].workflowWaitExitReasons;
    aggregateWorkflowWaitSummary.explorerWaitTotalMs = scenarios[4].explorerWaitTotalMs;
    aggregateWorkflowWaitSummary.explorerWaitSavedMs = scenarios[4].explorerWaitSavedMs;
    aggregateWorkflowWaitSummary.browserWaitTotalMs = scenarios[4].browserWaitTotalMs;
    aggregateWorkflowWaitSummary.browserWaitSavedMs = scenarios[4].browserWaitSavedMs;
    aggregateWorkflowWaitSummary.codeWorkflowWaitTotalMs = scenarios[4].codeWorkflowWaitTotalMs;
    aggregateWorkflowWaitSummary.codeWorkflowWaitSavedMs = scenarios[4].codeWorkflowWaitSavedMs;
    ApplyWorkflowWaitFields(aggregate, aggregateWorkflowWaitSummary);
    aggregate.notes = L"Runtime/report latency baseline records no-action, read-only observe, VLM no-probe, v1.1.6 core state-wait fields, and v1.1.7 workflow state-wait fields.";
    RemoveUnavailable(aggregate.unavailableFields, L"first_observe_start_ts");
    RemoveUnavailable(aggregate.unavailableFields, L"first_observe_end_ts");
    RemoveUnavailable(aggregate.unavailableFields, L"first_observe_ms");
    RemoveUnavailable(aggregate.unavailableFields, L"observe_total_ms");

    std::wstringstream json;
    json << L"{\"version\":" << simplejson::Quote(version)
         << L",\"generated_at\":" << simplejson::Quote(TimestampUtc())
         << L",\"command\":" << simplejson::Quote(command)
         << L",\"schema\":\"latency_observability.v1\""
         << L",\"required_fields\":" << LatencyObservabilityRequiredFieldsJson()
         << L",";
    AppendLatencyCommonFields(json, aggregate);
    json << L",\"scenarios\":" << ScenarioArrayJson(scenarios)
         << L"}";
    return json.str();
}
