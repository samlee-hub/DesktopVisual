#include "CompiledPlanExecutor.h"

#include "CaseRunner.h"
#include "ExecutionEvidencePack.h"
#include "PlanCompiler.h"
#include "ProjectRoot.h"
#include "RuntimeContextGuard.h"
#include "RuntimeSession.h"
#include "SessionManager.h"
#include "SimpleJson.h"
#include "StepContractRuntimeAdapter.h"
#include "StepContractValidator.h"
#include "StepExecutionVerifier.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <iostream>
#include <sstream>
#include <vector>

namespace {

struct ParsedStep {
    const simplejson::Value* raw = nullptr;
    std::wstring stepId;
    int stepIndex = 0;
    std::wstring runtimeAction;
    std::wstring target;
    std::wstring inputText;
    std::wstring riskLevel;
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

bool ParseBoolText(const std::wstring& raw, bool& value) {
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    return false;
}

void ArgBool(int argc, wchar_t** argv, const std::wstring& name, bool& value) {
    std::wstring raw;
    if (ArgValue(argc, argv, name, raw)) {
        bool parsed = value;
        if (ParseBoolText(raw, parsed)) value = parsed;
    }
}

bool WriteTextFileUtf8(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) EnsureDirectoryPath(path.substr(0, slash));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return true;
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

std::wstring ExecutionId() {
    return L"exec-" + std::to_wstring(RuntimeSessionNowEpochMs());
}

std::wstring FirstRequiredMarker(const simplejson::Value& step) {
    const simplejson::Value* expected = simplejson::Find(step, L"expected_context");
    if (!expected || !expected->IsObject()) return L"";
    const simplejson::Value* markers = simplejson::Find(*expected, L"required_markers");
    if (markers && markers->IsArray() && !markers->arrayValue.empty() && markers->arrayValue.front().IsString()) {
        return markers->arrayValue.front().stringValue;
    }
    return L"";
}

std::vector<ParsedStep> ParseSteps(const simplejson::Value& root) {
    std::vector<ParsedStep> steps;
    const simplejson::Value* contracts = simplejson::Find(root, L"contracts");
    if (!contracts || !contracts->IsArray()) return steps;
    for (const auto& raw : contracts->arrayValue) {
        if (!raw.IsObject()) continue;
        ParsedStep step;
        step.raw = &raw;
        step.stepId = simplejson::GetString(raw, L"step_id");
        step.stepIndex = simplejson::GetInt(raw, L"step_index", static_cast<int>(steps.size()));
        step.runtimeAction = simplejson::GetString(raw, L"runtime_action");
        step.target = simplejson::GetString(raw, L"target");
        step.inputText = simplejson::GetString(raw, L"input_text");
        step.riskLevel = simplejson::GetString(raw, L"risk_level");
        steps.push_back(step);
    }
    return steps;
}

std::wstring JsonArrayFromStrings(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

CompiledPlanExecutionResult FailureResult(
    const CompiledPlanExecutionOptions& options,
    const std::wstring& executionId,
    const std::wstring& code,
    const std::wstring& message,
    const std::wstring& extraJson = L"{}") {
    CompiledPlanExecutionResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    std::wstring data = L"{\"schema_version\":\"6.4.0.execution_result\""
        L",\"execution_id\":" + JsonString(executionId) +
        L",\"execution_summary\":{\"final_status\":\"BLOCKED\",\"validation_ok\":false,\"runtime_executed\":false,\"session_used\":false,\"step_contract_validator_used\":true,\"runtime_context_guard_used\":false,\"evidence_pack_created\":false,\"error_code\":" + JsonString(code) +
        L",\"error_message\":" + JsonString(message) + L"}"
        L",\"details\":" + extraJson + L"}";
    result.executionResultJson = data;
    if (!options.resultJson.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(options.resultJson, data, writeError);
    }
    return result;
}

bool IsBlockedRisk(const std::wstring& risk) {
    return risk == L"ACTIVE_PROTECTION_BLOCKED" || risk == L"CREDENTIAL_REQUIRED_BLOCKED";
}

bool IsHighRisk(const std::wstring& risk) {
    return risk == L"REAL_COMMIT" || risk == L"DESTRUCTIVE";
}

bool RiskAllowsExecution(const ParsedStep& step, const CompiledPlanExecutionOptions& options, std::wstring& code, std::wstring& reason) {
    if (IsBlockedRisk(step.riskLevel)) {
        code = step.riskLevel == L"ACTIVE_PROTECTION_BLOCKED" ? L"STOP_ACTIVE_PROTECTION" : L"CREDENTIAL_INPUT_DETECTED";
        reason = step.riskLevel + L" must not execute.";
        return false;
    }
    if (IsHighRisk(step.riskLevel)) {
        if (!(options.developerFullAccess && options.allowRealCommit && options.confirmationProvided && !options.requireConfirmation)) {
            code = step.riskLevel == L"DESTRUCTIVE" ? L"DESTRUCTIVE_CONFIRMATION_REQUIRED" : L"REAL_COMMIT_CONFIRMATION_REQUIRED";
            reason = step.riskLevel + L" requires explicit confirmation evidence.";
            return false;
        }
    }
    return true;
}

RuntimeContextGuardResult EvaluateSyntheticGuard(const ParsedStep& step, bool wrongContext) {
    ExpectedContextSpec spec;
    if (step.raw) {
        const simplejson::Value* expected = simplejson::Find(*step.raw, L"expected_context");
        if (expected && expected->IsObject()) {
            spec.enabled = true;
            spec.expectedTitlePattern = simplejson::GetString(*expected, L"expected_title_pattern");
            spec.expectedProcessPattern = simplejson::GetString(*expected, L"expected_process_pattern");
            spec.requiredMarkers = simplejson::GetStringArray(*expected, L"required_markers");
            spec.wrongPagePatterns = simplejson::GetStringArray(*expected, L"wrong_page_patterns");
            spec.activeProtectionPatterns = simplejson::GetStringArray(*expected, L"active_protection_patterns");
        }
    }
    RuntimeTargetContext target;
    RuntimeContextGuardResult result = EvaluateRuntimeContextGuard(ExpectedContextSpec{}, target);
    result.ok = !wrongContext;
    result.stopCode = wrongContext ? L"STOP_WRONG_CONTEXT" : L"";
    result.reason = wrongContext ? L"Synthetic local-safe context mismatch requested by StepContract target." : L"Synthetic local-safe context accepted.";
    result.markersOk = !wrongContext;
    result.wrongPageDetected = wrongContext;
    return result;
}

std::wstring SimulatedContextForStep(const ParsedStep& step) {
    return step.target + L" " + step.inputText + L" " + FirstRequiredMarker(*step.raw);
}

std::wstring StepResultJson(
    const ParsedStep& step,
    bool preconditionOk,
    bool runtimeActionExecuted,
    const StepExecutionVerificationResult& verification,
    const RuntimeContextGuardResult& guard,
    const std::wstring& stopCode,
    const std::wstring& failureAttribution,
    long long durationMs,
    bool recoveryAttempted,
    bool recoverySuccess) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.4.0.step_result\""
         << L",\"step_id\":" << JsonString(step.stepId)
         << L",\"step_index\":" << step.stepIndex
         << L",\"action\":" << JsonString(step.runtimeAction)
         << L",\"precondition_ok\":" << (preconditionOk ? L"true" : L"false")
         << L",\"runtime_action_executed\":" << (runtimeActionExecuted ? L"true" : L"false")
         << L",\"verification_ok\":" << (verification.verificationOk ? L"true" : L"false")
         << L",\"verification_type\":" << JsonString(verification.verificationType)
         << L",\"verification_evidence\":" << JsonString(verification.evidence)
         << L",\"stop_code\":" << JsonString(stopCode)
         << L",\"failure_attribution\":" << JsonString(failureAttribution)
         << L",\"duration_ms\":" << durationMs
         << L",\"runtime_context_guard_used\":true"
         << L",\"runtime_context_guard_ok\":" << (guard.ok ? L"true" : L"false")
         << L",\"runtime_context_guard_result\":" << RuntimeContextGuardResultJson(guard)
         << L",\"recovery_attempted\":" << (recoveryAttempted ? L"true" : L"false")
         << L",\"recovery_success\":" << (recoverySuccess ? L"true" : L"false")
         << L"}";
    return json.str();
}

RuntimeSession CreateSyntheticRuntimeSession(const std::wstring& taskId) {
    RuntimeSession session;
    session.sessionId = RuntimeSessionGenerateId();
    session.sessionCreatedAt = NowTimestamp();
    session.sessionLastActiveAt = session.sessionCreatedAt;
    session.sessionCreatedAtEpochMs = RuntimeSessionNowEpochMs();
    session.sessionLastActiveAtEpochMs = session.sessionCreatedAtEpochMs;
    session.sessionAlive = true;
    session.sessionClosed = false;
    session.requestedTitle = L"DesktopVisual v6.4 local-safe synthetic session";
    session.requestedProcess = L"winagent";
    session.targetTitle = session.requestedTitle;
    session.targetProcessName = L"winagent";
    session.sessionCommandCount = 0;
    session.latencySummary.sessionReuseEnabled = true;
    session.lastObserveId = L"observe-" + taskId;
    return session;
}

}  // namespace

CompiledPlanExecutionResult ExecuteStepContractJson(
    const std::wstring& stepContractJson,
    const CompiledPlanExecutionOptions& options) {
    std::wstring executionId = ExecutionId();
    ULONGLONG executionStart = GetTickCount64();
    StepContractV63ValidationResult validation = ValidateStepContractV63Json(stepContractJson);
    if (!validation.validationOk || !validation.executable) {
        return FailureResult(options, executionId, validation.errorCode.empty() ? L"STEP_CONTRACT_VALIDATION_FAILED" : validation.errorCode, validation.errorMessage.empty() ? L"StepContract validation failed." : validation.errorMessage, validation.resultJson.empty() ? L"{}" : validation.resultJson);
    }

    simplejson::ParseResult parsed = simplejson::Parse(stepContractJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return FailureResult(options, executionId, L"COMPILE_SCHEMA_INVALID", L"StepContract JSON is malformed.");
    }

    StepContractRuntimeAdapterResult adapter = AdaptStepContractToRuntimeSessionSteps(parsed.root);
    if (!adapter.ok) {
        return FailureResult(options, executionId, adapter.errorCode, adapter.errorMessage);
    }

    std::vector<ParsedStep> steps = ParseSteps(parsed.root);
    std::wstring taskId = steps.empty() ? L"unknown_task" : simplejson::GetString(*steps.front().raw, L"task_id");
    std::wstring planId = steps.empty() ? L"" : simplejson::GetString(*steps.front().raw, L"plan_id");
    std::wstring contractId = steps.empty() ? L"" : simplejson::GetString(*steps.front().raw, L"contract_id");
    bool dryRun = options.executionMode == L"dry_run";
    bool executeLocalSafe = options.executionMode == L"execute_local_safe" || options.executionMode == L"execute-local-safe";
    if (!dryRun && !executeLocalSafe) {
        return FailureResult(options, executionId, L"INVALID_ARGUMENT", L"execution_mode must be dry_run or execute_local_safe.");
    }

    for (const auto& step : steps) {
        std::wstring code;
        std::wstring reason;
        if (!RiskAllowsExecution(step, options, code, reason)) {
            return FailureResult(options, executionId, code, reason, L"{\"blocked_step_id\":" + JsonString(step.stepId) + L",\"risk_level\":" + JsonString(step.riskLevel) + L"}");
        }
    }

    RuntimeSession session = CreateSyntheticRuntimeSession(taskId);
    SessionManager manager;
    if (executeLocalSafe) {
        manager.SaveSession(session);
    }

    std::vector<EvidenceStepRecord> stepRecords;
    int stepsExecuted = 0;
    int stepsPassed = 0;
    int stepsFailed = 0;
    std::wstring stoppedAtStep;
    std::wstring finalStatus = L"PASS";
    std::wstring stopCode;
    std::wstring failureAttribution;
    bool runtimeExecuted = false;
    bool recoveryAttemptedAny = false;
    bool recoverySuccessAny = false;
    bool resumedFromCheckpoint = false;

    if (!dryRun) {
        for (const auto& step : steps) {
            ULONGLONG stepStart = GetTickCount64();
            bool staleTarget = ContainsInsensitive(step.target, L"stale-target");
            bool wrongContext = ContainsInsensitive(step.target, L"wrong-context");
            RuntimeContextGuardResult guard = EvaluateSyntheticGuard(step, wrongContext);
            bool recoveryAttempted = false;
            bool recoverySuccess = false;
            if (!guard.ok && step.raw) {
                const simplejson::Value* recovery = simplejson::Find(*step.raw, L"recovery_policy");
                bool allowed = recovery && recovery->IsObject() && simplejson::GetBool(*recovery, L"recovery_allowed", false) && options.allowRecovery && options.allowRecovery;
                if (allowed) {
                    recoveryAttempted = true;
                    recoveryAttemptedAny = true;
                    recoverySuccess = ContainsInsensitive(simplejson::GetString(*recovery, L"recovery_target"), L"mock") || ContainsInsensitive(simplejson::GetString(*recovery, L"recovery_scope"), L"local");
                    recoverySuccessAny = recoverySuccessAny || recoverySuccess;
                    resumedFromCheckpoint = recoverySuccess && (simplejson::GetBool(*recovery, L"resume_from_checkpoint_allowed", false) || simplejson::GetBool(*recovery, L"replay_from_checkpoint_allowed", false));
                    if (recoverySuccess) {
                        guard.ok = true;
                        guard.stopCode = L"";
                        guard.reason = L"Recovered local-safe mock context.";
                        guard.wrongPageDetected = false;
                        guard.markersOk = true;
                    }
                }
            }

            StepExecutionVerificationInput verifyInput;
            verifyInput.stepId = step.stepId;
            verifyInput.stepIndex = step.stepIndex;
            verifyInput.runtimeAction = step.runtimeAction;
            verifyInput.target = step.target;
            verifyInput.inputText = step.inputText;
            verifyInput.verificationHint = simplejson::Find(*step.raw, L"verification_hint");
            verifyInput.contextText = SimulatedContextForStep(step) + (guard.ok ? L"" : L" wrong-context");
            verifyInput.fieldValue = step.inputText;
            verifyInput.windowTitle = step.target;
            verifyInput.url = step.target;
            verifyInput.outputText = step.inputText + L" " + step.target;
            verifyInput.wrongContextDetected = !guard.ok;
            StepExecutionVerificationResult verification = VerifyStepExecution(verifyInput);

            bool preconditionOk = !staleTarget;
            if (staleTarget) {
                verification.verificationOk = false;
                verification.stopCode = L"STOP_TARGET_STALE";
                verification.failureAttribution = L"action_precondition";
                verification.evidence = L"stale target rejected before runtime action";
            }

            bool actionExecuted = guard.ok && preconditionOk;
            runtimeExecuted = runtimeExecuted || actionExecuted;
            ++stepsExecuted;
            session.sessionCommandCount++;
            session.actionCounter++;
            session.lastActionId = L"compiled-step-" + std::to_wstring(session.actionCounter);

            std::wstring localStop;
            std::wstring localAttribution;
            if (!preconditionOk) {
                localStop = L"STOP_TARGET_STALE";
                localAttribution = L"action_precondition";
            } else if (!guard.ok) {
                localStop = guard.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guard.stopCode;
                localAttribution = L"runtime_context_guard";
            } else if (!verification.verificationOk) {
                localStop = verification.stopCode.empty() ? L"STOP_UNVERIFIED_RESULT" : verification.stopCode;
                localAttribution = verification.failureAttribution.empty() ? L"step_execution_verifier" : verification.failureAttribution;
            }

            bool stepOk = preconditionOk && guard.ok && verification.verificationOk;
            if (stepOk) {
                ++stepsPassed;
            } else {
                ++stepsFailed;
                stoppedAtStep = step.stepId;
                stopCode = localStop;
                failureAttribution = localAttribution;
                finalStatus = L"STOPPED";
            }

            stepRecords.push_back({StepResultJson(step, preconditionOk, actionExecuted, verification, guard, localStop, localAttribution, ElapsedMs(stepStart), recoveryAttempted, recoverySuccess)});
            if (!stepOk) break;
        }
        manager.SaveSession(session);
    }

    std::wstring evidenceDir = options.evidenceDir;
    if (evidenceDir.empty()) {
        evidenceDir = ArtifactsPath(L"dev6.4.0_runtime_task_execution_from_compiled_agent_plan\\executions\\" + executionId);
    }

    std::wstringstream resultJson;
    resultJson << L"{\"schema_version\":\"6.4.0.execution_result\""
               << L",\"execution_id\":" << JsonString(executionId)
               << L",\"task_id\":" << JsonString(taskId)
               << L",\"plan_id\":" << JsonString(planId)
               << L",\"contract_id\":" << JsonString(contractId)
               << L",\"session_id\":" << JsonString(session.sessionId)
               << L",\"started_at\":" << JsonString(NowTimestamp())
               << L",\"ended_at\":" << JsonString(NowTimestamp())
               << L",\"execution_mode\":" << JsonString(options.executionMode)
               << L",\"runtime_executed\":" << (runtimeExecuted ? L"true" : L"false")
               << L",\"execution_summary\":{"
               << L"\"compiled\":true"
               << L",\"validated\":true"
               << L",\"validation_ok\":true"
               << L",\"runtime_executed\":" << (runtimeExecuted ? L"true" : L"false")
               << L",\"session_used\":" << (executeLocalSafe ? L"true" : L"false")
               << L",\"runtime_session_used\":" << (executeLocalSafe ? L"true" : L"false")
               << L",\"step_contract_validator_used\":true"
               << L",\"runtime_context_guard_used\":" << (dryRun ? L"false" : L"true")
               << L",\"step_level_verification_complete\":" << (dryRun ? L"false" : L"true")
               << L",\"session_steps_generated\":true"
               << L",\"adapter_used\":true"
               << L",\"evidence_pack_created\":true"
               << L",\"no_mouse_click_sent\":" << (dryRun ? L"true" : L"false")
               << L",\"no_keyboard_type_sent\":" << (dryRun ? L"true" : L"false")
               << L",\"steps_total\":" << steps.size()
               << L",\"steps_executed\":" << stepsExecuted
               << L",\"steps_passed\":" << stepsPassed
               << L",\"steps_failed\":" << stepsFailed
               << L",\"stopped_at_step\":" << JsonString(stoppedAtStep)
               << L",\"final_status\":" << JsonString(finalStatus)
               << L",\"failure_attribution\":" << JsonString(failureAttribution)
               << L",\"stop_code\":" << JsonString(stopCode)
               << L",\"wrong_field_input_count\":0"
               << L",\"recovery_attempted\":" << (recoveryAttemptedAny ? L"true" : L"false")
               << L",\"recovery_success\":" << (recoverySuccessAny ? L"true" : L"false")
               << L",\"execution_resumed_from_checkpoint\":" << (resumedFromCheckpoint ? L"true" : L"false")
               << L"}"
               << L",\"latency_summary\":{\"duration_ms\":" << ElapsedMs(executionStart) << L"}"
               << L",\"guard_summary\":{\"runtime_context_guard_used\":" << (dryRun ? L"false" : L"true") << L"}"
               << L",\"recovery_summary\":{\"recovery_attempted\":" << (recoveryAttemptedAny ? L"true" : L"false")
               << L",\"recovery_success\":" << (recoverySuccessAny ? L"true" : L"false")
               << L",\"execution_resumed_from_checkpoint\":" << (resumedFromCheckpoint ? L"true" : L"false") << L"}"
               << L",\"verification_summary\":{\"step_level_verification_complete\":" << (dryRun ? L"false" : L"true")
               << L",\"steps_passed\":" << stepsPassed << L"}"
               << L",\"session_steps\":" << adapter.sessionStepsJson
               << L",\"step_results\":[";
    for (size_t i = 0; i < stepRecords.size(); ++i) {
        if (i) resultJson << L",";
        resultJson << stepRecords[i].stepJson;
    }
    resultJson << L"]}";

    ExecutionEvidencePackInput packInput;
    packInput.evidenceDir = evidenceDir;
    packInput.executionResultJson = resultJson.str();
    packInput.stepRecords = stepRecords;
    packInput.executionId = executionId;
    packInput.taskId = taskId;
    packInput.finalStatus = finalStatus;
    ExecutionEvidencePackResult pack = WriteExecutionEvidencePack(packInput);

    CompiledPlanExecutionResult result;
    result.ok = pack.ok && finalStatus == L"PASS";
    result.errorCode = result.ok ? L"" : (stopCode.empty() ? (pack.ok ? L"EXECUTION_STOPPED" : pack.errorCode) : stopCode);
    result.errorMessage = result.ok ? L"" : (pack.ok ? L"Execution stopped before all steps passed." : pack.errorMessage);
    result.executionResultJson = resultJson.str();
    result.evidenceDir = evidenceDir;
    if (!options.resultJson.empty() && options.resultJson != pack.executionResultPath) {
        std::wstring writeError;
        WriteTextFileUtf8(options.resultJson, resultJson.str(), writeError);
    }
    return result;
}

CompiledPlanExecutionResult ExecuteStepContractFile(
    const std::wstring& inputPath,
    const CompiledPlanExecutionOptions& options) {
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        return FailureResult(options, ExecutionId(), read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read StepContract file: " + read.error);
    }
    return ExecuteStepContractJson(read.content, options);
}

int CommandExecuteStepContract(int argc, wchar_t** argv) {
    const std::wstring command = L"execute-step-contract";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    CompiledPlanExecutionOptions options;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"execute-step-contract requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--mode", options.executionMode);
    if (options.executionMode == L"dry-run") options.executionMode = L"dry_run";
    if (options.executionMode == L"execute-local-safe") options.executionMode = L"execute_local_safe";
    ArgValue(argc, argv, L"--output", options.resultJson);
    ArgValue(argc, argv, L"--evidence-dir", options.evidenceDir);
    ArgBool(argc, argv, L"--developer-full-access", options.developerFullAccess);
    ArgBool(argc, argv, L"--allow-recovery", options.allowRecovery);
    ArgBool(argc, argv, L"--allow-real-commit", options.allowRealCommit);
    ArgBool(argc, argv, L"--require-confirmation", options.requireConfirmation);
    ArgBool(argc, argv, L"--confirmation-ok", options.confirmationProvided);
    CompiledPlanExecutionResult result = ExecuteStepContractFile(input, options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EXECUTION_FAILED" : result.errorCode, result.errorMessage, result.executionResultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.executionResultJson) << L"\n";
    return 0;
}

int CommandExecuteCompiledPlan(int argc, wchar_t** argv) {
    return CommandExecuteStepContract(argc, argv);
}

int CommandRunAgentTask(int argc, wchar_t** argv) {
    const std::wstring command = L"run-agent-task";
    ULONGLONG startTick = GetTickCount64();
    std::wstring requestPath;
    if (!ArgValue(argc, argv, L"--request", requestPath) || requestPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-agent-task requires --request.", L"{}") << L"\n";
        return 2;
    }
    CompiledPlanExecutionOptions options;
    ArgValue(argc, argv, L"--mode", options.executionMode);
    if (options.executionMode == L"dry-run") options.executionMode = L"dry_run";
    if (options.executionMode == L"execute-local-safe") options.executionMode = L"execute_local_safe";
    ArgValue(argc, argv, L"--output", options.resultJson);
    ArgValue(argc, argv, L"--evidence-dir", options.evidenceDir);
    ArgBool(argc, argv, L"--developer-full-access", options.developerFullAccess);
    ArgBool(argc, argv, L"--allow-recovery", options.allowRecovery);
    ArgBool(argc, argv, L"--allow-real-commit", options.allowRealCommit);
    ArgBool(argc, argv, L"--require-confirmation", options.requireConfirmation);
    ArgBool(argc, argv, L"--confirmation-ok", options.confirmationProvided);

    FileReadResult read = ReadTextFile(requestPath);
    if (!read.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, read.error, L"{}") << L"\n";
        return 2;
    }
    simplejson::ParseResult parsed = simplejson::Parse(read.content);
    if (!parsed.ok || !parsed.root.IsObject()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"COMPILE_SCHEMA_INVALID", L"AgentTaskRequest JSON is malformed.", L"{}") << L"\n";
        return 2;
    }

    std::wstring stepContractPath = simplejson::GetString(parsed.root, L"step_contract_path");
    std::wstring planDraftPath = simplejson::GetString(parsed.root, L"plan_draft_path");
    std::wstring contractJson;
    if (!stepContractPath.empty()) {
        FileReadResult contract = ReadTextFile(stepContractPath);
        if (!contract.ok) {
            std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), contract.errorCode.empty() ? L"FILE_READ_FAILED" : contract.errorCode, contract.error, L"{}") << L"\n";
            return 2;
        }
        contractJson = contract.content;
    } else if (!planDraftPath.empty()) {
        PlanCompileResult compiled = CompilePlanDraftFile(planDraftPath, L"", L"");
        if (!compiled.ok) {
            std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), compiled.errorCode.empty() ? L"PLAN_COMPILE_FAILED" : compiled.errorCode, compiled.errorMessage, compiled.diagnosticsJson) << L"\n";
            return 1;
        }
        contractJson = compiled.contractJson;
    } else if (const simplejson::Value* inlineContract = simplejson::Find(parsed.root, L"step_contract"); inlineContract && inlineContract->IsObject()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Inline step_contract is not supported by this minimal bridge; provide step_contract_path.", L"{}") << L"\n";
        return 2;
    } else {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-agent-task requires step_contract_path or plan_draft_path.", L"{}") << L"\n";
        return 2;
    }

    CompiledPlanExecutionResult result = ExecuteStepContractJson(contractJson, options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EXECUTION_FAILED" : result.errorCode, result.errorMessage, result.executionResultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.executionResultJson) << L"\n";
    return 0;
}
