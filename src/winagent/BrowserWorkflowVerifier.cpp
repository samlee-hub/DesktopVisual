#include "BrowserWorkflowVerifier.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
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

BrowserWorkflowVerificationResult VerificationFailure(const std::wstring& code, const std::wstring& message) {
    BrowserWorkflowVerificationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.verificationJson = L"{\"schema_version\":\"6.8.0.browser_workflow.verification\",\"verification_ok\":false,\"error_code\":"
        + simplejson::Quote(code) + L",\"error_message\":" + simplejson::Quote(message) + L"}";
    return result;
}

bool AnyBool(const simplejson::Value& root, const std::vector<std::wstring>& keys) {
    for (const auto& key : keys) {
        if (simplejson::GetBool(root, key, false)) return true;
    }
    return false;
}

std::wstring FirstFailureCode(const simplejson::Value& root, const std::wstring& workflowType, bool dryRun) {
    if (!simplejson::GetBool(root, L"workflow_compiled", false)) return L"VERIFY_WORKFLOW_NOT_COMPILED";
    if (!simplejson::GetBool(root, L"compiled_step_contract_used", false)) return L"VERIFY_STEP_CONTRACT_MISSING";
    if (!simplejson::GetBool(root, L"step_contract_validator_used", false)) return L"BLOCKED_STEP_CONTRACT_VALIDATOR_BYPASSED";
    if (AnyBool(root, {L"dom_automation_used", L"javascript_automation_used", L"webdriver_used", L"cdp_used", L"playwright_used", L"selenium_used"})) return L"BLOCKED_BROWSER_BACKEND_AUTOMATION_USED";
    if (AnyBool(root, {L"powershell_fake_form_success_used", L"javascript_fake_form_success_used", L"fake_form_execution"})) return L"BLOCKED_FAKE_FORM_EXECUTION";
    if (simplejson::GetBool(root, L"runner_only_workflow_logic", false)) return L"BLOCKED_RUNNER_ONLY_BROWSER_WORKFLOW";
    if (!dryRun && !simplejson::GetBool(root, L"runtime_session_used", false)) return L"BLOCKED_RUNTIME_SESSION_NOT_USED";
    if (!dryRun && !simplejson::GetBool(root, L"runtime_context_guard_used", false)) return L"BLOCKED_RUNTIME_GUARD_BYPASSED";
    if (!dryRun && !simplejson::GetBool(root, L"browser_surface_normalizer_used", false)) return L"BLOCKED_BROWSER_SURFACE_NORMALIZER_BYPASSED";
    if (!dryRun && !simplejson::GetBool(root, L"step_level_verification_complete", false)) return L"BLOCKED_STEP_VERIFICATION_INCOMPLETE";
    if (!simplejson::GetBool(root, L"evidence_pack_created", false)) return L"BLOCKED_EVIDENCE_PACK_MISSING";
    if (workflowType == L"browser_open_page" && !dryRun) {
        if (!simplejson::GetBool(root, L"browser_opened", false)) return L"VERIFY_BROWSER_NOT_OPENED";
        if (!simplejson::GetBool(root, L"page_loaded", false)) return L"VERIFY_PAGE_NOT_LOADED";
        if (!simplejson::GetBool(root, L"required_markers_verified", false)) return L"VERIFY_MARKER_NOT_VERIFIED";
    }
    if ((workflowType == L"browser_fill_form" || workflowType == L"browser_submit_form") && !dryRun) {
        if (simplejson::GetInt(root, L"wrong_field_input_count", 0) != 0) return L"BLOCKED_WRONG_FIELD_INPUT";
        int total = simplejson::GetInt(root, L"form_fields_total", 0);
        if (total > 0 && simplejson::GetInt(root, L"form_fields_verified", 0) != total) return L"VERIFY_FORM_FIELD_EVIDENCE_INCOMPLETE";
        if (workflowType == L"browser_submit_form" && !simplejson::GetBool(root, L"submit_result_verified", false)) return L"BLOCKED_UNVERIFIED_FORM_SUBMIT";
    }
    if (workflowType == L"browser_wrong_page_recovery" && !dryRun) {
        if (!simplejson::GetBool(root, L"wrong_page_detected", false)) return L"VERIFY_WRONG_PAGE_NOT_DETECTED";
        if (!simplejson::GetBool(root, L"recovery_attempted", false)) return L"VERIFY_RECOVERY_NOT_ATTEMPTED";
        if (!simplejson::GetBool(root, L"recovery_success", false)) return L"STOP_BROWSER_RECOVERY_FAILED";
    }
    if (workflowType == L"browser_active_protection_stop" && !simplejson::GetBool(root, L"active_protection_detected", false)) return L"BLOCKED_BROWSER_PROTECTION_STOP_FAILED";
    if (workflowType == L"browser_credential_required_stop" && !simplejson::GetBool(root, L"credential_required_detected", false)) return L"BLOCKED_BROWSER_PROTECTION_STOP_FAILED";
    return L"";
}

}  // namespace

BrowserWorkflowVerificationResult VerifyBrowserWorkflowResultJson(const std::wstring& resultJson) {
    simplejson::ParseResult parsed = simplejson::Parse(resultJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return VerificationFailure(L"VERIFY_SCHEMA_INVALID", L"Browser workflow result JSON is malformed.");
    }
    const simplejson::Value& root = parsed.root;
    std::wstring mode = simplejson::GetString(root, L"execution_mode");
    std::wstring workflowType = simplejson::GetString(root, L"workflow_type");
    std::wstring finalStatus = simplejson::GetString(root, L"final_status");
    std::wstring stopCode = simplejson::GetString(root, L"stop_code");
    bool dryRun = mode == L"dry_run" || mode == L"dry-run";
    bool blockedStop = workflowType == L"browser_active_protection_stop" || workflowType == L"browser_credential_required_stop";
    std::wstring code = FirstFailureCode(root, workflowType, dryRun);
    bool verificationOk = code.empty() &&
        ((dryRun && finalStatus == L"DRY_RUN_PASS") ||
         (!dryRun && finalStatus == L"PASS") ||
         (blockedStop && finalStatus == L"STOPPED" && !stopCode.empty()));

    if (!verificationOk && code.empty()) code = L"VERIFY_FINAL_STATUS_NOT_PASS";

    BrowserWorkflowVerificationResult result;
    result.ok = verificationOk;
    result.errorCode = verificationOk ? L"" : code;
    result.errorMessage = verificationOk ? L"" : L"Browser workflow result did not satisfy verifier requirements.";
    result.verificationJson = L"{\"schema_version\":\"6.8.0.browser_workflow.verification\""
        L",\"verification_ok\":" + simplejson::Bool(verificationOk) +
        L",\"final_status\":" + simplejson::Quote(finalStatus) +
        L",\"execution_mode\":" + simplejson::Quote(mode) +
        L",\"workflow_type\":" + simplejson::Quote(workflowType) +
        L",\"workflow_compiled\":" + simplejson::Bool(simplejson::GetBool(root, L"workflow_compiled", false)) +
        L",\"compiled_step_contract_used\":" + simplejson::Bool(simplejson::GetBool(root, L"compiled_step_contract_used", false)) +
        L",\"step_contract_validator_used\":" + simplejson::Bool(simplejson::GetBool(root, L"step_contract_validator_used", false)) +
        L",\"runtime_session_used\":" + simplejson::Bool(simplejson::GetBool(root, L"runtime_session_used", false)) +
        L",\"runtime_context_guard_used\":" + simplejson::Bool(simplejson::GetBool(root, L"runtime_context_guard_used", false)) +
        L",\"browser_surface_normalizer_used\":" + simplejson::Bool(simplejson::GetBool(root, L"browser_surface_normalizer_used", false)) +
        L",\"step_level_verification_complete\":" + simplejson::Bool(simplejson::GetBool(root, L"step_level_verification_complete", false)) +
        L",\"evidence_pack_created\":" + simplejson::Bool(simplejson::GetBool(root, L"evidence_pack_created", false)) +
        L",\"runner_only_workflow_logic\":" + simplejson::Bool(simplejson::GetBool(root, L"runner_only_workflow_logic", false)) +
        L",\"dom_js_webdriver_cdp_used\":" + simplejson::Bool(AnyBool(root, {L"dom_automation_used", L"javascript_automation_used", L"webdriver_used", L"cdp_used", L"playwright_used", L"selenium_used"})) +
        L",\"fake_form_execution\":" + simplejson::Bool(AnyBool(root, {L"powershell_fake_form_success_used", L"javascript_fake_form_success_used", L"fake_form_execution"})) +
        L",\"error_code\":" + simplejson::Quote(result.errorCode) +
        L"}";
    return result;
}

BrowserWorkflowVerificationResult VerifyBrowserWorkflowResultFile(
    const std::wstring& resultPath,
    const std::wstring& outputPath) {
    FileReadResult read = ReadTextFile(resultPath);
    if (!read.ok) {
        return VerificationFailure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read Browser workflow result: " + read.error);
    }
    BrowserWorkflowVerificationResult result = VerifyBrowserWorkflowResultJson(read.content);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.verificationJson, writeError);
    }
    return result;
}

int CommandVerifyBrowserWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"verify-browser-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring resultPath;
    std::wstring outputPath;
    if (!ArgValue(argc, argv, L"--result", resultPath) || resultPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"verify-browser-workflow requires --result.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", outputPath);
    BrowserWorkflowVerificationResult result = VerifyBrowserWorkflowResultFile(resultPath, outputPath);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"BROWSER_WORKFLOW_VERIFICATION_FAILED" : result.errorCode, result.errorMessage, result.verificationJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.verificationJson) << L"\n";
    return 0;
}
