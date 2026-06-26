#include "ExplorerWorkflowAdapter.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "StepContractValidator.h"
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

ExplorerWorkflowCompileResult CompileFailure(const std::wstring& code, const std::wstring& message, const std::wstring& diagnostics = L"{}") {
    ExplorerWorkflowCompileResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.contractJson = L"{\"schema_version\":\"6.3.0.step_contract\",\"compiler_version\":\"6.7.0.explorer_workflow\",\"compile_ok\":false,\"contracts\":[]}";
    result.diagnosticsJson = diagnostics == L"{}"
        ? L"{\"schema_version\":\"6.7.0.explorer_workflow.compile_diagnostics\",\"compile_ok\":false,\"error_code\":" + simplejson::Quote(code) + L",\"error_message\":" + simplejson::Quote(message) + L"}"
        : diagnostics;
    return result;
}

std::wstring TargetForSpec(const ExplorerWorkflowSpec& spec) {
    if (!spec.targetPath.empty()) return spec.targetPath;
    if (!spec.sourcePath.empty()) return spec.sourcePath;
    if (!spec.expectedFolder.empty()) return spec.expectedFolder;
    return spec.expectedFilename;
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring CompleteExpectedContextJson(const ExplorerWorkflowSpec& spec) {
    simplejson::ParseResult parsed = simplejson::Parse(spec.expectedContextJson);
    const simplejson::Value* root = parsed.ok && parsed.root.IsObject() ? &parsed.root : nullptr;
    std::wstring process = root ? simplejson::GetString(*root, L"expected_process_pattern", L"explorer.exe") : L"explorer.exe";
    std::wstring title = root ? simplejson::GetString(*root, L"expected_title_pattern", L".*") : L".*";
    std::vector<std::wstring> markers = root ? simplejson::GetStringArray(*root, L"required_markers") : std::vector<std::wstring>{};
    if (markers.empty() && !spec.expectedFilename.empty()) markers.push_back(spec.expectedFilename);
    std::vector<std::wstring> wrong = root ? simplejson::GetStringArray(*root, L"wrong_page_patterns") : std::vector<std::wstring>{};
    std::vector<std::wstring> protection = root ? simplejson::GetStringArray(*root, L"active_protection_patterns") : std::vector<std::wstring>{};
    std::vector<std::wstring> credentials = root ? simplejson::GetStringArray(*root, L"credential_required_patterns") : std::vector<std::wstring>{};
    bool foreground = root ? simplejson::GetBool(*root, L"foreground_required", true) : true;
    bool binding = root ? simplejson::GetBool(*root, L"window_binding_required", true) : true;
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << simplejson::Quote(process.empty() ? L"explorer.exe" : process)
         << L",\"expected_title_pattern\":" << simplejson::Quote(title.empty() ? L".*" : title)
         << L",\"required_markers\":" << StringArrayJson(markers)
         << L",\"wrong_page_patterns\":" << StringArrayJson(wrong)
         << L",\"active_protection_patterns\":" << StringArrayJson(protection)
         << L",\"credential_required_patterns\":" << StringArrayJson(credentials)
         << L",\"foreground_required\":" << simplejson::Bool(foreground)
         << L",\"window_binding_required\":" << simplejson::Bool(binding)
         << L"}";
    return json.str();
}

std::wstring CompleteVerificationHintJson(const ExplorerWorkflowSpec& spec) {
    simplejson::ParseResult parsed = simplejson::Parse(spec.verificationHintJson);
    const simplejson::Value* root = parsed.ok && parsed.root.IsObject() ? &parsed.root : nullptr;
    std::wstring verifyType = root ? simplejson::GetString(*root, L"verify_type") : L"";
    if (verifyType.empty()) {
        if (spec.workflowType == L"explorer_open_path") verifyType = L"folder_opened";
        else if (spec.workflowType == L"explorer_open_file") verifyType = L"file_opened";
        else if (spec.workflowType == L"explorer_rename_file") verifyType = L"file_renamed";
        else if (spec.workflowType == L"explorer_move_file") verifyType = L"file_moved";
        else if (spec.workflowType == L"explorer_delete_file") verifyType = L"file_deleted";
        else if (spec.workflowType == L"explorer_context_menu_action") verifyType = L"context_menu_action_result";
        else verifyType = L"scroll_target_found";
    }
    std::wstring marker = root ? simplejson::GetString(*root, L"expected_marker", spec.expectedFilename) : spec.expectedFilename;
    std::wstring text = root ? simplejson::GetString(*root, L"expected_text", marker) : marker;
    std::wstringstream json;
    json << L"{\"verify_type\":" << simplejson::Quote(verifyType)
         << L",\"expected_marker\":" << simplejson::Quote(marker)
         << L",\"expected_text\":" << simplejson::Quote(text)
         << L",\"expected_window_title\":\"\""
         << L",\"expected_url_pattern\":\"\""
         << L",\"expected_output_pattern\":\"\""
         << L",\"expected_field_value\":" << simplejson::Quote(spec.expectedFilename)
         << L",\"post_action_reobserve_required\":" << simplejson::Bool(root ? simplejson::GetBool(*root, L"post_action_reobserve_required", true) : true)
         << L"}";
    return json.str();
}

std::wstring CompleteStopPolicyJson(const std::wstring& stopPolicyJson) {
    simplejson::ParseResult parsed = simplejson::Parse(stopPolicyJson);
    const simplejson::Value* root = parsed.ok && parsed.root.IsObject() ? &parsed.root : nullptr;
    auto flag = [root](const std::wstring& key) -> bool {
        return root ? simplejson::GetBool(*root, key, true) : true;
    };
    return L"{\"stop_on_wrong_context\":" + simplejson::Bool(flag(L"stop_on_wrong_context")) +
        L",\"stop_on_wrong_field\":" + simplejson::Bool(flag(L"stop_on_wrong_field")) +
        L",\"stop_on_target_stale\":" + simplejson::Bool(flag(L"stop_on_target_stale")) +
        L",\"stop_on_target_not_unique\":" + simplejson::Bool(flag(L"stop_on_target_not_unique")) +
        L",\"stop_on_active_protection\":" + simplejson::Bool(flag(L"stop_on_active_protection")) +
        L",\"stop_on_credential_required\":" + simplejson::Bool(flag(L"stop_on_credential_required")) +
        L",\"stop_on_unverified_result\":" + simplejson::Bool(flag(L"stop_on_unverified_result")) +
        L",\"stop_on_runtime_guard_failure\":" + simplejson::Bool(flag(L"stop_on_runtime_guard_failure")) +
        L"}";
}

std::wstring StepTypeForWorkflow(const std::wstring& workflowType) {
    if (workflowType == L"explorer_open_path" || workflowType == L"explorer_open_file") return L"open";
    if (workflowType == L"explorer_rename_file") return L"rename";
    if (workflowType == L"explorer_move_file") return L"move";
    if (workflowType == L"explorer_delete_file") return L"delete";
    if (workflowType == L"explorer_context_menu_action") return L"context_menu";
    if (workflowType == L"explorer_scroll_and_locate") return L"scroll";
    return L"explorer";
}

std::wstring ConfirmationPolicyJson(const ExplorerWorkflowSpec& spec) {
    std::wstringstream json;
    json << L"{\"confirmation_required\":" << simplejson::Bool(spec.confirmationRequired)
         << L",\"confirmation_reason\":" << simplejson::Quote(spec.workflowType == L"explorer_delete_file" ? L"Explorer destructive delete requires test confirmation token." : L"")
         << L",\"developer_full_access_allowed\":false"
         << L",\"public_release_confirmation_required\":" << simplejson::Bool(spec.workflowType == L"explorer_delete_file")
         << L",\"manual_handoff_required\":false}";
    return json.str();
}

std::wstring ActionPreconditionJson(const ExplorerWorkflowSpec& spec) {
    bool needsTarget = spec.workflowType != L"explorer_open_path";
    bool mouseFirst = spec.workflowType != L"explorer_open_path";
    bool scrollAllowed = spec.workflowType == L"explorer_scroll_and_locate";
    std::wstringstream json;
    json << L"{\"target_required\":" << simplejson::Bool(needsTarget)
         << L",\"target_unique_required\":true"
         << L",\"target_inside_viewport_required\":true"
         << L",\"target_current_observe_required\":true"
         << L",\"focus_required\":true"
         << L",\"mouse_first_required\":" << simplejson::Bool(mouseFirst)
         << L",\"text_input_allowed\":" << simplejson::Bool(spec.workflowType == L"explorer_rename_file" || spec.workflowType == L"explorer_context_menu_action")
         << L",\"scroll_allowed\":" << simplejson::Bool(scrollAllowed)
         << L",\"stale_target_reject_required\":true}";
    return json.str();
}

}  // namespace

ExplorerWorkflowCompileResult CompileExplorerWorkflowSpec(const ExplorerWorkflowSpec& spec) {
    if (!ExplorerWorkflowTypeSupported(spec.workflowType)) {
        return CompileFailure(L"COMPILE_SCHEMA_INVALID", L"Unsupported Explorer workflow_type.");
    }

    std::wstring target = TargetForSpec(spec);
    std::wstring contractId = L"explorer-contract-" + spec.workflowId;
    std::wstringstream step;
    step << L"{\"contract_id\":" << simplejson::Quote(contractId)
         << L",\"task_id\":" << simplejson::Quote(spec.taskId)
         << L",\"plan_id\":" << simplejson::Quote(L"explorer-plan-" + spec.workflowId)
         << L",\"step_id\":" << simplejson::Quote(spec.workflowId + L"-step-0")
         << L",\"step_index\":0"
         << L",\"step_type\":" << simplejson::Quote(StepTypeForWorkflow(spec.workflowType))
         << L",\"runtime_action\":" << simplejson::Quote(spec.workflowType)
         << L",\"target\":" << simplejson::Quote(target)
         << L",\"input_text\":" << simplejson::Quote(spec.expectedFilename)
         << L",\"executable\":true"
         << L",\"expected_context\":" << CompleteExpectedContextJson(spec)
         << L",\"action_precondition\":" << ActionPreconditionJson(spec)
         << L",\"verification_hint\":" << CompleteVerificationHintJson(spec)
         << L",\"risk_level\":" << simplejson::Quote(spec.riskLevel)
         << L",\"confirmation_policy\":" << ConfirmationPolicyJson(spec)
         << L",\"recovery_policy\":" << spec.recoveryPolicyJson
         << L",\"stop_policy\":" << CompleteStopPolicyJson(spec.stopPolicyJson)
         << L",\"session_policy\":" << spec.sessionPolicyJson
         << L",\"evidence_policy\":" << spec.evidencePolicyJson
         << L",\"workflow_id\":" << simplejson::Quote(spec.workflowId)
         << L",\"workflow_type\":" << simplejson::Quote(spec.workflowType)
         << L",\"source_path\":" << simplejson::Quote(spec.sourcePath)
         << L",\"target_path\":" << simplejson::Quote(spec.targetPath)
         << L",\"destination_path\":" << simplejson::Quote(spec.destinationPath)
         << L",\"expected_folder\":" << simplejson::Quote(spec.expectedFolder)
         << L",\"expected_filename\":" << simplejson::Quote(spec.expectedFilename)
         << L",\"expected_extension\":" << simplejson::Quote(spec.expectedExtension)
         << L",\"allowed_root\":" << simplejson::Quote(spec.allowedRoot)
         << L",\"confirmation_token_present\":" << simplejson::Bool(!spec.confirmationToken.empty())
         << L",\"context_menu_action\":" << simplejson::Quote(spec.contextMenuAction)
         << L",\"created_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"compiler_version\":\"6.7.0.explorer_workflow\"}";

    std::wstring contractJson = L"{\"schema_version\":\"6.3.0.step_contract\",\"compiler_version\":\"6.7.0.explorer_workflow\",\"compile_ok\":true,\"runtime_executed\":false,\"task_id\":"
        + simplejson::Quote(spec.taskId) + L",\"plan_id\":" + simplejson::Quote(L"explorer-plan-" + spec.workflowId)
        + L",\"workflow_id\":" + simplejson::Quote(spec.workflowId) + L",\"workflow_type\":" + simplejson::Quote(spec.workflowType)
        + L",\"contracts\":[" + step.str() + L"]}";

    StepContractV63ValidationResult validation = ValidateStepContractV63Json(contractJson);
    if (!validation.validationOk || !validation.executable) {
        return CompileFailure(validation.errorCode.empty() ? L"STEP_CONTRACT_VALIDATION_FAILED" : validation.errorCode,
            validation.errorMessage.empty() ? L"Explorer StepContract validation failed." : validation.errorMessage,
            validation.resultJson);
    }

    ExplorerWorkflowCompileResult result;
    result.ok = true;
    result.workflowId = spec.workflowId;
    result.workflowType = spec.workflowType;
    result.contractJson = contractJson;
    result.diagnosticsJson = L"{\"schema_version\":\"6.7.0.explorer_workflow.compile_diagnostics\",\"compile_ok\":true,\"workflow_id\":"
        + simplejson::Quote(spec.workflowId) + L",\"workflow_type\":" + simplejson::Quote(spec.workflowType)
        + L",\"step_contract_validator_used\":true,\"emitted_step_count\":1,\"runtime_executed\":false}";
    return result;
}

ExplorerWorkflowCompileResult CompileExplorerWorkflowSpecJson(const std::wstring& json) {
    ExplorerWorkflowSchemaResult schema = ParseExplorerWorkflowSpecJson(json);
    if (!schema.ok) {
        return CompileFailure(schema.errorCode, schema.errorMessage, schema.diagnosticsJson);
    }
    return CompileExplorerWorkflowSpec(schema.spec);
}

ExplorerWorkflowCompileResult CompileExplorerWorkflowSpecFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath) {
    ExplorerWorkflowSchemaResult schema = ParseExplorerWorkflowSpecFile(inputPath);
    if (!schema.ok) {
        return CompileFailure(schema.errorCode, schema.errorMessage, schema.diagnosticsJson);
    }
    ExplorerWorkflowCompileResult result = CompileExplorerWorkflowSpec(schema.spec);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.contractJson, writeError);
    }
    return result;
}

int CommandCompileExplorerWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"compile-explorer-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"compile-explorer-workflow requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    ExplorerWorkflowCompileResult result = CompileExplorerWorkflowSpecFile(input, output);
    std::wstring data = L"{\"compile_ok\":" + simplejson::Bool(result.ok)
        + L",\"input\":" + simplejson::Quote(input)
        + L",\"output\":" + simplejson::Quote(output)
        + L",\"workflow_id\":" + simplejson::Quote(result.workflowId)
        + L",\"workflow_type\":" + simplejson::Quote(result.workflowType)
        + L",\"runtime_executed\":false}";
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMPILE_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.diagnosticsJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}
