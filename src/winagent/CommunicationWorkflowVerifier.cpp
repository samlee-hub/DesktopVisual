#include "CommunicationWorkflowVerifier.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <cstdio>
#include <iostream>
#include <sstream>
#include <vector>

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

CommunicationWorkflowVerificationResult VerificationFailure(const std::wstring& code, const std::wstring& message) {
    CommunicationWorkflowVerificationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.verificationJson = L"{\"schema_version\":\"6.9.0.communication_workflow.verification\""
        L",\"verification_ok\":false"
        L",\"error_code\":" + simplejson::Quote(code) +
        L",\"error_message\":" + simplejson::Quote(message) + L"}";
    return result;
}

bool AnyBool(const simplejson::Value& root, const std::vector<std::wstring>& keys) {
    for (const auto& key : keys) {
        if (simplejson::GetBool(root, key, false)) return true;
    }
    return false;
}

std::wstring FirstFailureCode(const simplejson::Value& root) {
    if (!simplejson::GetBool(root, L"workflow_executed", false)) return L"VERIFY_COMMUNICATION_WORKFLOW_NOT_EXECUTED";
    if (!simplejson::GetBool(root, L"communication_workflow_executor_used", false)) return L"BLOCKED_COMMUNICATION_EXECUTOR_MISSING";
    if (!simplejson::GetBool(root, L"task_intent_used", false)) return L"BLOCKED_TASK_INTENT_MISSING";
    if (!simplejson::GetBool(root, L"agent_plan_draft_used", false)) return L"BLOCKED_AGENT_PLAN_DRAFT_MISSING";
    if (!simplejson::GetBool(root, L"compiled_step_contract_used", false)) return L"VERIFY_STEP_CONTRACT_MISSING";
    if (!simplejson::GetBool(root, L"step_contract_validator_used", false)) return L"BLOCKED_STEP_CONTRACT_VALIDATOR_BYPASSED";
    if (!simplejson::GetBool(root, L"compiled_plan_executor_used", false)) return L"BLOCKED_COMPILED_PLAN_EXECUTOR_MISSING";
    if (!simplejson::GetBool(root, L"runtime_session_used", false)) return L"BLOCKED_RUNTIME_SESSION_NOT_USED";
    if (!simplejson::GetBool(root, L"context_bound", false) || !simplejson::GetBool(root, L"context_binding_verified", false)) return L"BLOCKED_COMMUNICATION_CONTEXT_NOT_BOUND";
    if (simplejson::GetBool(root, L"runner_only_workflow_logic", false)) return L"BLOCKED_RUNNER_ONLY_COMMUNICATION_WORKFLOW";
    if (simplejson::GetBool(root, L"fake_send_used", false)) return L"BLOCKED_FAKE_SEND";
    if (simplejson::GetBool(root, L"send_attempted", false)) return L"BLOCKED_COMMUNICATION_SEND_ATTEMPTED";
    if (AnyBool(root, {L"external_api_used", L"provider_sdk_used", L"mail_api_used", L"messaging_api_used"})) return L"BLOCKED_EXTERNAL_COMMUNICATION_API_USED";
    if (AnyBool(root, {L"dom_automation_used", L"javascript_automation_used", L"webdriver_used", L"cdp_used", L"playwright_used", L"selenium_used"})) return L"BLOCKED_BROWSER_AUTOMATION_FOR_COMMUNICATION";
    if (!simplejson::GetBool(root, L"step_level_verification_complete", false)) return L"BLOCKED_COMMUNICATION_VERIFICATION_MISSING";
    if (!simplejson::GetBool(root, L"evidence_pack_created", false)) return L"BLOCKED_EVIDENCE_PACK_MISSING";
    return L"";
}

}  // namespace

CommunicationWorkflowVerificationResult VerifyCommunicationWorkflowResultJson(const std::wstring& resultJson) {
    simplejson::ParseResult parsed = simplejson::Parse(resultJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return VerificationFailure(L"VERIFY_SCHEMA_INVALID", L"Communication workflow result JSON is malformed.");
    }
    const simplejson::Value& root = parsed.root;
    std::wstring finalStatus = simplejson::GetString(root, L"final_status");
    std::wstring type = simplejson::GetString(root, L"type");
    std::wstring code = FirstFailureCode(root);
    bool verificationOk = code.empty() && finalStatus == L"PASS";
    if (!verificationOk && code.empty()) code = L"VERIFY_FINAL_STATUS_NOT_PASS";

    CommunicationWorkflowVerificationResult result;
    result.ok = verificationOk;
    result.errorCode = verificationOk ? L"" : code;
    result.errorMessage = verificationOk ? L"" : L"Communication workflow result did not satisfy verifier requirements.";
    result.verificationJson = L"{\"schema_version\":\"6.9.0.communication_workflow.verification\""
        L",\"verification_ok\":" + simplejson::Bool(verificationOk) +
        L",\"final_status\":" + simplejson::Quote(finalStatus) +
        L",\"type\":" + simplejson::Quote(type) +
        L",\"workflow_executed\":" + simplejson::Bool(simplejson::GetBool(root, L"workflow_executed", false)) +
        L",\"task_intent_used\":" + simplejson::Bool(simplejson::GetBool(root, L"task_intent_used", false)) +
        L",\"agent_plan_draft_used\":" + simplejson::Bool(simplejson::GetBool(root, L"agent_plan_draft_used", false)) +
        L",\"compiled_step_contract_used\":" + simplejson::Bool(simplejson::GetBool(root, L"compiled_step_contract_used", false)) +
        L",\"step_contract_validator_used\":" + simplejson::Bool(simplejson::GetBool(root, L"step_contract_validator_used", false)) +
        L",\"compiled_plan_executor_used\":" + simplejson::Bool(simplejson::GetBool(root, L"compiled_plan_executor_used", false)) +
        L",\"runtime_session_used\":" + simplejson::Bool(simplejson::GetBool(root, L"runtime_session_used", false)) +
        L",\"context_bound\":" + simplejson::Bool(simplejson::GetBool(root, L"context_bound", false)) +
        L",\"context_binding_verified\":" + simplejson::Bool(simplejson::GetBool(root, L"context_binding_verified", false)) +
        L",\"step_level_verification_complete\":" + simplejson::Bool(simplejson::GetBool(root, L"step_level_verification_complete", false)) +
        L",\"evidence_pack_created\":" + simplejson::Bool(simplejson::GetBool(root, L"evidence_pack_created", false)) +
        L",\"runner_only_workflow_logic\":" + simplejson::Bool(simplejson::GetBool(root, L"runner_only_workflow_logic", false)) +
        L",\"send_attempted\":" + simplejson::Bool(simplejson::GetBool(root, L"send_attempted", false)) +
        L",\"fake_send_used\":" + simplejson::Bool(simplejson::GetBool(root, L"fake_send_used", false)) +
        L",\"external_api_used\":" + simplejson::Bool(simplejson::GetBool(root, L"external_api_used", false)) +
        L",\"error_code\":" + simplejson::Quote(result.errorCode) +
        L"}";
    return result;
}

CommunicationWorkflowVerificationResult VerifyCommunicationWorkflowResultFile(
    const std::wstring& resultPath,
    const std::wstring& outputPath) {
    FileReadResult read = ReadTextFile(resultPath);
    if (!read.ok) {
        return VerificationFailure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read Communication workflow result: " + read.error);
    }
    CommunicationWorkflowVerificationResult result = VerifyCommunicationWorkflowResultJson(read.content);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.verificationJson, writeError);
    }
    return result;
}

int CommandVerifyCommunicationWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"verify-communication-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring resultPath;
    std::wstring outputPath;
    if (!ArgValue(argc, argv, L"--result", resultPath) || resultPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"verify-communication-workflow requires --result.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", outputPath);
    CommunicationWorkflowVerificationResult result = VerifyCommunicationWorkflowResultFile(resultPath, outputPath);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMMUNICATION_WORKFLOW_VERIFICATION_FAILED" : result.errorCode, result.errorMessage, result.verificationJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.verificationJson) << L"\n";
    return 0;
}
