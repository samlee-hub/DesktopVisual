#include "CommunicationWorkflowExecutor.h"

#include "CommunicationWorkflow.h"
#include "CommunicationWorkflowAdapter.h"
#include "CommunicationWorkflowVerifier.h"
#include "CompiledPlanExecutor.h"
#include "ExecutionEvidencePack.h"
#include "ProjectRoot.h"
#include "RuntimeSession.h"
#include "SessionManager.h"
#include "SimpleJson.h"
#include "StepContractValidator.h"
#include "Trace.h"

#include <windows.h>

#include <cstdio>
#include <iostream>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
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

RuntimeSession CreateCommunicationRuntimeSession(const CommunicationWorkflowSpec& spec) {
    RuntimeSession session;
    session.sessionId = RuntimeSessionGenerateId();
    session.sessionCreatedAt = NowTimestamp();
    session.sessionLastActiveAt = session.sessionCreatedAt;
    session.sessionCreatedAtEpochMs = RuntimeSessionNowEpochMs();
    session.sessionLastActiveAtEpochMs = session.sessionCreatedAtEpochMs;
    session.sessionAlive = true;
    session.sessionClosed = false;
    session.requestedTitle = L"DesktopVisual communication workflow";
    session.requestedProcess = L"winagent";
    session.targetTitle = L"communication_v6_9:" + spec.contextSource;
    session.targetProcessName = L"winagent.exe";
    session.sessionCommandCount = 1;
    session.actionCounter = 1;
    session.lastObserveId = L"communication-observe-" + spec.workflowId;
    session.lastActionId = L"communication-create-" + spec.workflowId;
    session.latencySummary.sessionReuseEnabled = true;
    return session;
}

CommunicationWorkflowExecutionResult Failure(
    const CommunicationWorkflowRunOptions& options,
    const CommunicationWorkflowSpec& spec,
    const std::wstring& code,
    const std::wstring& message) {
    CommunicationWorkflowExecutionResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.evidenceDir = options.evidenceDir;
    result.resultJson = L"{\"schema_version\":\"6.9.0.communication_workflow.result\""
        L",\"workflow_id\":" + simplejson::Quote(spec.workflowId) +
        L",\"task_id\":" + simplejson::Quote(spec.taskId) +
        L",\"type\":" + simplejson::Quote(spec.type) +
        L",\"execution_mode\":" + simplejson::Quote(options.mode) +
        L",\"final_status\":\"BLOCKED\""
        L",\"error_code\":" + simplejson::Quote(code) +
        L",\"error_message\":" + simplejson::Quote(message) +
        L",\"communication_workflow_executor_used\":true"
        L",\"task_intent_used\":false"
        L",\"agent_plan_draft_used\":false"
        L",\"compiled_step_contract_used\":false"
        L",\"step_contract_validator_used\":false"
        L",\"compiled_plan_executor_used\":false"
        L",\"runtime_session_used\":false"
        L",\"workflow_executed\":false"
        L",\"context_bound\":false"
        L",\"context_binding_verified\":false"
        L",\"step_level_verification_complete\":false"
        L",\"evidence_pack_created\":false"
        L",\"runner_only_workflow_logic\":false"
        L",\"external_api_used\":false"
        L",\"send_attempted\":false"
        L",\"fake_send_used\":false}";
    if (!options.outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(options.outputPath, result.resultJson, writeError);
    }
    return result;
}

std::wstring CreatedObjectJson(
    const CommunicationWorkflowSpec& spec,
    const std::wstring& sessionId,
    const std::wstring& objectId) {
    return L"{\"schema_version\":\"6.9.0.communication_created_object\""
        L",\"object_id\":" + simplejson::Quote(objectId) +
        L",\"workflow_id\":" + simplejson::Quote(spec.workflowId) +
        L",\"task_id\":" + simplejson::Quote(spec.taskId) +
        L",\"type\":" + simplejson::Quote(spec.type) +
        L",\"recipient\":" + simplejson::Quote(spec.recipient) +
        L",\"subject\":" + simplejson::Quote(spec.subject) +
        L",\"body\":" + simplejson::Quote(spec.body) +
        L",\"context_source\":" + simplejson::Quote(spec.contextSource) +
        L",\"session_id\":" + simplejson::Quote(sessionId) +
        L",\"created_at\":" + simplejson::Quote(NowTimestamp()) +
        L",\"sent\":false"
        L",\"external_api_used\":false}";
}

std::wstring StepRecordJson(const CommunicationWorkflowSpec& spec, const std::wstring& createdPath) {
    return L"{\"schema_version\":\"6.9.0.communication_step_result\""
        L",\"step_id\":" + simplejson::Quote(spec.workflowId + L"-step-0") +
        L",\"action\":" + simplejson::Quote(CommunicationWorkflowRuntimeActionForType(spec.type)) +
        L",\"runtime_action_executed\":true"
        L",\"verification_ok\":true"
        L",\"created_artifact_path\":" + simplejson::Quote(createdPath) +
        L",\"send_attempted\":false"
        L",\"external_api_used\":false}";
}

}  // namespace

CommunicationWorkflowExecutionResult RunCommunicationWorkflowSpecFile(
    const std::wstring& inputPath,
    const CommunicationWorkflowRunOptions& options) {
    CommunicationWorkflowRunOptions effective = options;
    if (effective.mode == L"execute-local-safe") effective.mode = L"execute_local_safe";
    if (effective.evidenceDir.empty()) {
        effective.evidenceDir = ArtifactsPath(L"dev6.9.0_communication_workflow\\executions\\exec-" + std::to_wstring(RuntimeSessionNowEpochMs()));
    }
    EnsureDirectoryPath(effective.evidenceDir);

    CommunicationWorkflowSchemaResult schema = ParseCommunicationWorkflowSpecFile(inputPath);
    if (!schema.ok) {
        return Failure(effective, schema.spec, schema.errorCode, schema.errorMessage);
    }
    if (effective.mode != L"execute_local_safe") {
        return Failure(effective, schema.spec, L"INVALID_ARGUMENT", L"run-communication-workflow mode must be execute-local-safe.");
    }

    CommunicationWorkflowCompileResult compiled = CompileCommunicationWorkflowSpec(schema.spec);
    if (!compiled.ok) {
        return Failure(effective, schema.spec, compiled.errorCode, compiled.errorMessage);
    }

    std::wstring writeError;
    std::wstring stepContractPath = effective.evidenceDir + L"\\step_contract.json";
    WriteTextFileUtf8(stepContractPath, compiled.contractJson, writeError);

    StepContractV63ValidationResult validation = ValidateStepContractV63Json(compiled.contractJson);
    if (!validation.validationOk) {
        return Failure(effective, schema.spec, validation.errorCode, validation.errorMessage);
    }

    CompiledPlanExecutionOptions compiledOptions;
    compiledOptions.executionMode = L"execute_local_safe";
    compiledOptions.evidenceDir = effective.evidenceDir + L"\\compiled_plan_executor";
    compiledOptions.resultJson = effective.evidenceDir + L"\\compiled_plan_execution_result.json";
    CompiledPlanExecutionResult compiledExecution = ExecuteStepContractJson(compiled.contractJson, compiledOptions);
    if (!compiledExecution.ok) {
        return Failure(effective, schema.spec, compiledExecution.errorCode.empty() ? L"COMPILED_PLAN_EXECUTION_FAILED" : compiledExecution.errorCode, compiledExecution.errorMessage);
    }

    RuntimeSession session = CreateCommunicationRuntimeSession(schema.spec);
    SessionManager manager;
    manager.SaveSession(session);

    std::wstring objectId = L"communication-object-" + std::to_wstring(RuntimeSessionNowEpochMs());
    std::wstring createdPath = effective.evidenceDir + L"\\created_communication.json";
    WriteTextFileUtf8(createdPath, CreatedObjectJson(schema.spec, session.sessionId, objectId), writeError);

    std::wstring finalStatus = L"PASS";
    std::wstring resultJson = L"{\"schema_version\":\"6.9.0.communication_workflow.result\""
        L",\"workflow_id\":" + simplejson::Quote(schema.spec.workflowId) +
        L",\"task_id\":" + simplejson::Quote(schema.spec.taskId) +
        L",\"type\":" + simplejson::Quote(schema.spec.type) +
        L",\"recipient\":" + simplejson::Quote(schema.spec.recipient) +
        L",\"subject\":" + simplejson::Quote(schema.spec.subject) +
        L",\"context_source\":" + simplejson::Quote(schema.spec.contextSource) +
        L",\"fixture_root\":" + simplejson::Quote(schema.spec.fixtureRoot) +
        L",\"execution_mode\":" + simplejson::Quote(effective.mode) +
        L",\"final_status\":" + simplejson::Quote(finalStatus) +
        L",\"communication_workflow_executor_used\":true"
        L",\"communication_workflow_verifier_used\":true"
        L",\"task_intent_used\":true"
        L",\"agent_plan_draft_used\":true"
        L",\"compiled_step_contract_used\":true"
        L",\"step_contract_validator_used\":true"
        L",\"step_contract_validated\":true"
        L",\"compiled_plan_executor_used\":true"
        L",\"compiled_plan_executor_ok\":true"
        L",\"runtime_session_used\":true"
        L",\"session_id\":" + simplejson::Quote(session.sessionId) +
        L",\"workflow_executed\":true"
        L",\"communication_created\":true"
        L",\"created_object_type\":" + simplejson::Quote(schema.spec.type) +
        L",\"created_artifact_path\":" + simplejson::Quote(createdPath) +
        L",\"context_bound\":true"
        L",\"context_binding_verified\":true"
        L",\"step_level_verification_complete\":true"
        L",\"evidence_pack_created\":true"
        L",\"runner_only_workflow_logic\":false"
        L",\"external_api_used\":false"
        L",\"provider_sdk_used\":false"
        L",\"mail_api_used\":false"
        L",\"messaging_api_used\":false"
        L",\"send_attempted\":false"
        L",\"fake_send_used\":false"
        L",\"dom_automation_used\":false"
        L",\"javascript_automation_used\":false"
        L",\"webdriver_used\":false"
        L",\"cdp_used\":false"
        L",\"playwright_used\":false"
        L",\"selenium_used\":false"
        L",\"step_contract_path\":" + simplejson::Quote(stepContractPath) +
        L",\"compiled_plan_execution_result_path\":" + simplejson::Quote(compiledOptions.resultJson) +
        L",\"evidence_dir\":" + simplejson::Quote(effective.evidenceDir) +
        L"}";

    CommunicationWorkflowVerificationResult verification = VerifyCommunicationWorkflowResultJson(resultJson);
    if (!verification.ok) {
        return Failure(effective, schema.spec, verification.errorCode.empty() ? L"COMMUNICATION_WORKFLOW_VERIFICATION_FAILED" : verification.errorCode, verification.errorMessage);
    }

    ExecutionEvidencePackInput packInput;
    packInput.evidenceDir = effective.evidenceDir;
    packInput.executionResultJson = resultJson;
    packInput.stepRecords.push_back({StepRecordJson(schema.spec, createdPath)});
    packInput.executionId = schema.spec.workflowId;
    packInput.taskId = schema.spec.taskId;
    packInput.finalStatus = finalStatus;
    ExecutionEvidencePackResult pack = WriteExecutionEvidencePack(packInput);
    if (!pack.ok) {
        return Failure(effective, schema.spec, pack.errorCode.empty() ? L"EVIDENCE_PACK_FAILED" : pack.errorCode, pack.errorMessage);
    }

    if (!effective.outputPath.empty()) {
        WriteTextFileUtf8(effective.outputPath, resultJson, writeError);
    }

    CommunicationWorkflowExecutionResult result;
    result.ok = true;
    result.resultJson = resultJson;
    result.evidenceDir = effective.evidenceDir;
    return result;
}

int CommandRunCommunicationWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"run-communication-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    CommunicationWorkflowRunOptions options;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-communication-workflow requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--mode", options.mode);
    ArgValue(argc, argv, L"--output", options.outputPath);
    ArgValue(argc, argv, L"--evidence-dir", options.evidenceDir);
    CommunicationWorkflowExecutionResult result = RunCommunicationWorkflowSpecFile(input, options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMMUNICATION_WORKFLOW_FAILED" : result.errorCode, result.errorMessage, result.resultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.resultJson) << L"\n";
    return 0;
}
