#include "ExplorerWorkflowVerifier.h"

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

ExplorerWorkflowVerificationResult VerificationFailure(const std::wstring& code, const std::wstring& message) {
    ExplorerWorkflowVerificationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.verificationJson = L"{\"schema_version\":\"6.7.0.explorer_workflow.verification\",\"verification_ok\":false,\"error_code\":"
        + simplejson::Quote(code) + L",\"error_message\":" + simplejson::Quote(message) + L"}";
    return result;
}

}  // namespace

bool ExplorerWorkflowFileExists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool ExplorerWorkflowDirectoryExists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

ExplorerWorkflowVerificationResult VerifyExplorerWorkflowResultJson(const std::wstring& resultJson) {
    simplejson::ParseResult parsed = simplejson::Parse(resultJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return VerificationFailure(L"VERIFY_SCHEMA_INVALID", L"Explorer workflow result JSON is malformed.");
    }
    const simplejson::Value& root = parsed.root;
    bool workflowCompiled = simplejson::GetBool(root, L"workflow_compiled", false);
    bool stepContractUsed = simplejson::GetBool(root, L"compiled_step_contract_used", false);
    bool validatorUsed = simplejson::GetBool(root, L"step_contract_validator_used", false) ||
                         simplejson::GetBool(root, L"step_contract_validated", false);
    bool runtimeSessionUsed = simplejson::GetBool(root, L"runtime_session_used", false);
    bool guardUsed = simplejson::GetBool(root, L"runtime_context_guard_used", false);
    bool powershellFake = simplejson::GetBool(root, L"powershell_file_action_used", false) ||
                          simplejson::GetBool(root, L"power_shell_file_operation_used", false);
    bool directFileApi = simplejson::GetBool(root, L"direct_file_api_workflow_action_used", false) ||
                         simplejson::GetBool(root, L"direct_file_api_used", false);
    bool runnerOnly = simplejson::GetBool(root, L"runner_only_workflow_logic", false);
    std::wstring finalStatus = simplejson::GetString(root, L"final_status");
    std::wstring mode = simplejson::GetString(root, L"execution_mode");
    std::wstring workflowType = simplejson::GetString(root, L"workflow_type");
    bool dryRun = mode == L"dry_run" || mode == L"dry-run";
    bool specificOk = true;
    if (!dryRun && workflowType == L"explorer_open_path") {
        specificOk = simplejson::GetBool(root, L"folder_opened", false) &&
                     simplejson::GetBool(root, L"expected_folder_verified", false);
    } else if (!dryRun && workflowType == L"explorer_open_file") {
        specificOk = simplejson::GetBool(root, L"file_visible", false) &&
                     simplejson::GetBool(root, L"file_open_action_executed", false) &&
                     simplejson::GetBool(root, L"file_open_verified", false) &&
                     (!simplejson::GetBool(root, L"wrong_context_detected", false) ||
                      simplejson::GetBool(root, L"recovery_success", false));
    } else if (!dryRun && workflowType == L"explorer_rename_file") {
        specificOk = simplejson::GetBool(root, L"old_name_exists_before", false) &&
                     simplejson::GetBool(root, L"new_name_exists_after", false) &&
                     simplejson::GetBool(root, L"old_name_absent_after", false) &&
                     simplejson::GetBool(root, L"result_verified", false);
    } else if (!dryRun && workflowType == L"explorer_move_file") {
        specificOk = simplejson::GetBool(root, L"source_exists_before", false) &&
                     simplejson::GetBool(root, L"source_selected_by_mouse", false) &&
                     simplejson::GetBool(root, L"source_selection_verified", false) &&
                     simplejson::GetBool(root, L"cut_attempted", false) &&
                     simplejson::GetBool(root, L"cut_sent", false) &&
                     simplejson::GetBool(root, L"destination_folder_opened", false) &&
                     simplejson::GetBool(root, L"destination_folder_focused", false) &&
                     simplejson::GetBool(root, L"paste_attempted", false) &&
                     simplejson::GetBool(root, L"paste_sent", false) &&
                     simplejson::GetBool(root, L"move_action_attempted", false) &&
                     simplejson::GetBool(root, L"move_action_executed", false) &&
                     simplejson::GetBool(root, L"source_absent_after", false) &&
                     simplejson::GetBool(root, L"destination_exists_after", false) &&
                     simplejson::GetBool(root, L"move_result_verified", false) &&
                     simplejson::GetBool(root, L"result_verified", false);
    } else if (!dryRun && workflowType == L"explorer_delete_file") {
        specificOk = simplejson::GetBool(root, L"confirmation_verified", false) &&
                     simplejson::GetBool(root, L"delete_with_confirmation_executed", false) &&
                     simplejson::GetBool(root, L"target_exists_before", false) &&
                     simplejson::GetBool(root, L"target_absent_after", false) &&
                     simplejson::GetString(root, L"risk_gate_result") == L"ok";
    } else if (!dryRun && workflowType == L"explorer_scroll_and_locate") {
        specificOk = simplejson::GetBool(root, L"list_area_located", false) &&
                     simplejson::GetBool(root, L"list_area_clicked", false) &&
                     simplejson::GetBool(root, L"list_area_focus_verified", false) &&
                     simplejson::GetBool(root, L"target_exists_in_fixture", false) &&
                     simplejson::GetBool(root, L"scroll_used", false) &&
                     simplejson::GetInt(root, L"scroll_iteration_count", 0) >= 1 &&
                     simplejson::GetBool(root, L"scroll_progress_detected", false) &&
                     simplejson::GetBool(root, L"scroll_position_changed", false) &&
                     simplejson::GetBool(root, L"target_found", false) &&
                     simplejson::GetBool(root, L"target_clicked_or_verified", false) &&
                     !simplejson::GetBool(root, L"stale_rect_used", false) &&
                     simplejson::GetBool(root, L"runtime_context_guard_each_iteration", false) &&
                     simplejson::GetBool(root, L"no_stale_rect", false);
    } else if (!dryRun && workflowType == L"explorer_context_menu_action") {
        specificOk = simplejson::GetBool(root, L"right_click_sent", false) &&
                     simplejson::GetBool(root, L"context_menu_visible", false) &&
                     simplejson::GetBool(root, L"menu_item_located", false) &&
                     simplejson::GetBool(root, L"menu_item_clicked", false) &&
                     simplejson::GetBool(root, L"result_verified", false);
    }
    bool verificationOk = workflowCompiled && stepContractUsed && validatorUsed && !powershellFake && !directFileApi && !runnerOnly &&
        ((dryRun && finalStatus == L"DRY_RUN_PASS") || (!dryRun && runtimeSessionUsed && guardUsed && finalStatus == L"PASS" && specificOk));

    std::wstring code;
    if (!workflowCompiled) code = L"VERIFY_WORKFLOW_NOT_COMPILED";
    else if (!stepContractUsed) code = L"VERIFY_STEP_CONTRACT_MISSING";
    else if (!validatorUsed) code = L"VERIFY_STEP_CONTRACT_VALIDATOR_NOT_USED";
    else if (powershellFake) code = L"BLOCKED_FAKE_FILESYSTEM_EXECUTION";
    else if (directFileApi) code = L"BLOCKED_DIRECT_FILE_API_WORKFLOW";
    else if (runnerOnly) code = L"BLOCKED_RUNNER_ONLY_EXPLORER_WORKFLOW";
    else if (!dryRun && !runtimeSessionUsed) code = L"BLOCKED_RUNTIME_SESSION_NOT_USED";
    else if (!dryRun && !guardUsed) code = L"BLOCKED_RUNTIME_GUARD_BYPASSED";
    else if (!dryRun && !specificOk && workflowType == L"explorer_move_file") code = L"BLOCKED_EXPLORER_MOVE_EVIDENCE_INCOMPLETE";
    else if (!dryRun && !specificOk && workflowType == L"explorer_scroll_and_locate" &&
             simplejson::GetBool(root, L"scroll_used", false) &&
             !simplejson::GetBool(root, L"scroll_position_changed", false)) code = L"BLOCKED_SCROLL_PROGRESS_NOT_PROVEN";
    else if (!dryRun && !specificOk && workflowType == L"explorer_scroll_and_locate") code = L"BLOCKED_EXPLORER_SCROLL_LOCATE_FAILED";
    else if (!dryRun && !specificOk) code = L"VERIFY_EXPLORER_SPECIFIC_EVIDENCE_MISSING";
    else if (!verificationOk) code = L"VERIFY_FINAL_STATUS_NOT_PASS";

    ExplorerWorkflowVerificationResult result;
    result.ok = verificationOk;
    result.errorCode = verificationOk ? L"" : code;
    result.errorMessage = verificationOk ? L"" : L"Explorer workflow result did not satisfy verifier requirements.";
    result.verificationJson = L"{\"schema_version\":\"6.7.0.explorer_workflow.verification\""
        L",\"verification_ok\":" + simplejson::Bool(verificationOk) +
        L",\"final_status\":" + simplejson::Quote(finalStatus) +
        L",\"execution_mode\":" + simplejson::Quote(mode) +
        L",\"workflow_type\":" + simplejson::Quote(workflowType) +
        L",\"workflow_compiled\":" + simplejson::Bool(workflowCompiled) +
        L",\"compiled_step_contract_used\":" + simplejson::Bool(stepContractUsed) +
        L",\"step_contract_validator_used\":" + simplejson::Bool(validatorUsed) +
        L",\"step_contract_validated\":" + simplejson::Bool(validatorUsed) +
        L",\"runtime_session_used\":" + simplejson::Bool(runtimeSessionUsed) +
        L",\"runtime_context_guard_used\":" + simplejson::Bool(guardUsed) +
        L",\"powershell_file_action_used\":" + simplejson::Bool(powershellFake) +
        L",\"direct_file_api_workflow_action_used\":" + simplejson::Bool(directFileApi) +
        L",\"runner_only_workflow_logic\":" + simplejson::Bool(runnerOnly) +
        L",\"explorer_specific_evidence_ok\":" + simplejson::Bool(specificOk) +
        L",\"error_code\":" + simplejson::Quote(result.errorCode) + L"}";
    return result;
}

ExplorerWorkflowVerificationResult VerifyExplorerWorkflowResultFile(
    const std::wstring& resultPath,
    const std::wstring& outputPath) {
    FileReadResult read = ReadTextFile(resultPath);
    if (!read.ok) {
        return VerificationFailure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read Explorer workflow result: " + read.error);
    }
    ExplorerWorkflowVerificationResult result = VerifyExplorerWorkflowResultJson(read.content);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.verificationJson, writeError);
    }
    return result;
}

int CommandVerifyExplorerWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"verify-explorer-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring resultPath;
    std::wstring outputPath;
    if (!ArgValue(argc, argv, L"--result", resultPath) || resultPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"verify-explorer-workflow requires --result.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", outputPath);
    ExplorerWorkflowVerificationResult result = VerifyExplorerWorkflowResultFile(resultPath, outputPath);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EXPLORER_WORKFLOW_VERIFICATION_FAILED" : result.errorCode, result.errorMessage, result.verificationJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.verificationJson) << L"\n";
    return 0;
}
