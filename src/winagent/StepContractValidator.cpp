#include "StepContractValidator.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "VisibleOperationPolicy.h"

#include <windows.h>

#include <cwctype>
#include <cstdio>
#include <iostream>
#include <set>
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

std::wstring ToLowerInvariant(std::wstring value) {
    for (wchar_t& ch : value) ch = static_cast<wchar_t>(std::towlower(ch));
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool IsSupportedRisk(const std::wstring& risk) {
    return risk == L"READ_ONLY" ||
           risk == L"LOW_RISK" ||
           risk == L"REVERSIBLE_DRAFT" ||
           risk == L"REAL_COMMIT" ||
           risk == L"DESTRUCTIVE" ||
           risk == L"ACTIVE_PROTECTION_BLOCKED" ||
           risk == L"CREDENTIAL_REQUIRED_BLOCKED";
}

bool IsHighRisk(const std::wstring& risk) {
    return risk == L"REAL_COMMIT" || risk == L"DESTRUCTIVE";
}

bool IsBlockedRisk(const std::wstring& risk) {
    return risk == L"ACTIVE_PROTECTION_BLOCKED" || risk == L"CREDENTIAL_REQUIRED_BLOCKED";
}

bool IsSupportedRuntimeAction(const std::wstring& action) {
    return action == L"explorer_open_path" ||
           action == L"explorer_rename_file" ||
           action == L"explorer_move_file" ||
           action == L"explorer_delete_file" ||
           action == L"explorer_context_menu_action" ||
           action == L"explorer_scroll_and_locate" ||
           action == L"browser_open_page" ||
           action == L"browser_read_page" ||
           action == L"browser_scroll_page" ||
           action == L"browser_locate_text" ||
           action == L"browser_fill_form" ||
           action == L"browser_submit_form" ||
           action == L"browser_wrong_page_recovery" ||
           action == L"browser_surface_normalize" ||
           action == L"communication_create_draft" ||
           action == L"communication_create_message" ||
           action == L"communication_create_email" ||
           action == L"explorer_open_file" ||
           action == L"click_target" ||
           action == L"click" ||
           action == L"click_submit" ||
           action == L"run_button_click" ||
           action == L"type_text" ||
           action == L"type" ||
           action == L"verify_marker" ||
           action == L"verify" ||
           action == L"scroll" ||
           action == L"scroll_and_locate" ||
           action == L"local_mock_mail_fill" ||
           action == L"code_editor_run_mock" ||
           action == L"show_desktop" ||
           action == L"window_switch" ||
           action == L"wait_for_context" ||
           action == L"observe" ||
           action == L"locate" ||
           action == L"non_executable_stop" ||
           action == L"stop";
}

bool IsDirectCoordinateAction(const std::wstring& action, const std::wstring& target) {
    return action == L"direct_coordinate_click" ||
           ContainsInsensitive(target, L"coord:") ||
           (ContainsInsensitive(target, L"x=") && ContainsInsensitive(target, L"y="));
}

bool IsExplorerWorkflowAction(const std::wstring& action) {
    return action == L"explorer_open_path" ||
           action == L"explorer_open_file" ||
           action == L"explorer_rename_file" ||
           action == L"explorer_move_file" ||
           action == L"explorer_delete_file" ||
           action == L"explorer_context_menu_action" ||
           action == L"explorer_scroll_and_locate";
}

bool IsBrowserWorkflowAction(const std::wstring& action) {
    return action == L"browser_open_page" ||
           action == L"browser_read_page" ||
           action == L"browser_scroll_page" ||
           action == L"browser_locate_text" ||
           action == L"browser_fill_form" ||
           action == L"browser_submit_form" ||
           action == L"browser_wrong_page_recovery" ||
           action == L"browser_surface_normalize";
}

bool IsCommunicationWorkflowAction(const std::wstring& action) {
    return action == L"communication_create_draft" ||
           action == L"communication_create_message" ||
           action == L"communication_create_email";
}

bool IsBackendAutomationText(const std::wstring& value) {
    if (value.empty()) return false;
    return ContainsInsensitive(value, L"dom") ||
           ContainsInsensitive(value, L"javascript") ||
           ContainsInsensitive(value, L"webdriver") ||
           ContainsInsensitive(value, L"cdp") ||
           ContainsInsensitive(value, L"playwright") ||
           ContainsInsensitive(value, L"selenium");
}

bool IsCommunicationExternalApiText(const std::wstring& value) {
    if (value.empty()) return false;
    return ContainsInsensitive(value, L"provider_sdk") ||
           ContainsInsensitive(value, L"external_provider") ||
           ContainsInsensitive(value, L"external api") ||
           ContainsInsensitive(value, L"mail api") ||
           ContainsInsensitive(value, L"messaging api") ||
           ContainsInsensitive(value, L"chat api") ||
           ContainsInsensitive(value, L"sdk") ||
           ContainsInsensitive(value, L"smtp") ||
           ContainsInsensitive(value, L"imap") ||
           ContainsInsensitive(value, L"webhook") ||
           ContainsInsensitive(value, L"http://") ||
           ContainsInsensitive(value, L"https://") ||
           ContainsInsensitive(value, L"send") ||
           IsBackendAutomationText(value);
}

std::wstring VisibleOperationTypeForRuntimeAction(const std::wstring& runtimeAction) {
    if (runtimeAction == L"browser_open_page" || runtimeAction == L"browser_wrong_page_recovery") return L"browser_navigation";
    if (runtimeAction == L"explorer_open_path" || runtimeAction == L"explorer_open_file") return L"app_launch";
    if (runtimeAction == L"code_editor_run_mock") return L"ide_panel_switch";
    if (runtimeAction == L"local_mock_mail_fill") return L"text_input";
    if (runtimeAction == L"show_desktop") return L"show_desktop";
    if (runtimeAction == L"window_switch") return L"window_switch";
    return L"visible_ui_operation";
}

VisibleOperationPolicyOptions VisiblePriorityFromStep(const simplejson::Value& step, const std::wstring& runtimeAction) {
    VisibleOperationPolicyOptions options;
    options.operationId = simplejson::GetString(step, L"operation_id");
    if (options.operationId.empty()) options.operationId = simplejson::GetString(step, L"step_id");
    options.operationType = simplejson::GetString(step, L"operation_type");
    if (options.operationType.empty()) options.operationType = VisibleOperationTypeForRuntimeAction(runtimeAction);
    options.attempt1Mode = simplejson::GetString(step, L"attempt_1_mode");
    options.attempt2Mode = simplejson::GetString(step, L"attempt_2_mode");
    options.attempt3Mode = simplejson::GetString(step, L"attempt_3_mode");
    options.backendFallbackKind = simplejson::GetString(step, L"backend_fallback_kind");
    if (options.backendFallbackKind.empty()) options.backendFallbackKind = simplejson::GetString(step, L"action_backend");
    options.finalModeUsed = simplejson::GetString(step, L"final_mode_used");
    options.backendFallbackUsed = simplejson::GetBool(step, L"backend_fallback_used", false);
    options.backendFallbackReason = simplejson::GetString(step, L"backend_fallback_reason");
    options.visibleMouseKeyboardAttempted = simplejson::GetBool(step, L"visible_mouse_keyboard_attempted", false);
    options.attempt1Result = simplejson::GetString(step, L"attempt_1_result");
    options.attempt1FailureReason = simplejson::GetString(step, L"attempt_1_failure_reason");
    options.visibleAttemptCount = simplejson::GetInt(step, L"visible_attempt_count", 0);
    options.minVisibleAttemptsBeforeShortcut = simplejson::GetInt(step, L"min_visible_attempts_before_shortcut", 2);
    options.preActionCheckpointPresent = simplejson::GetBool(step, L"pre_action_checkpoint_present", false);
    options.boundedRecoveryAttempted = simplejson::GetBool(step, L"bounded_recovery_attempted", false);
    options.postRecoveryObserved = simplejson::GetBool(step, L"post_recovery_observed", false);
    options.sameSurfaceAfterRecovery = simplejson::GetBool(step, L"same_surface_after_recovery", false);
    options.surfaceImpossible = simplejson::GetBool(step, L"surface_impossible", false);
    options.surfaceImpossibleReason = simplejson::GetString(step, L"surface_impossible_reason");
    options.surfaceImpossibleEvidencePresent = simplejson::GetBool(step, L"surface_impossible_evidence_present", false);
    options.keyboardShortcutAttempted = simplejson::GetBool(step, L"keyboard_shortcut_attempted", false);
    options.attempt2Result = simplejson::GetString(step, L"attempt_2_result");
    options.attempt2FailureReason = simplejson::GetString(step, L"attempt_2_failure_reason");
    options.attempt3Result = simplejson::GetString(step, L"attempt_3_result");
    options.explicitBackendRequested = simplejson::GetBool(step, L"explicit_backend_request", false);
    options.maxAttemptsExceeded = simplejson::GetBool(step, L"max_attempts_exceeded", false);
    return options;
}

bool RecoveryBypassesProtection(const simplejson::Value& recovery) {
    std::wstring scope = simplejson::GetString(recovery, L"recovery_scope");
    std::wstring target = simplejson::GetString(recovery, L"recovery_target");
    std::wstring joined = scope + L" " + target;
    return ContainsInsensitive(joined, L"bypass captcha") ||
           ContainsInsensitive(joined, L"bypass credential") ||
           ContainsInsensitive(joined, L"credential_required") ||
           ContainsInsensitive(joined, L"active_protection");
}

struct Finding {
    std::wstring code;
    std::wstring message;
    std::wstring stepId;
};

void AddFinding(std::vector<Finding>& findings, const std::wstring& code, const std::wstring& message, const std::wstring& stepId = L"") {
    findings.push_back({code, message, stepId});
}

std::wstring FindingsJson(const std::vector<Finding>& findings) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < findings.size(); ++i) {
        if (i) json << L",";
        json << L"{\"code\":" << simplejson::Quote(findings[i].code)
             << L",\"message\":" << simplejson::Quote(findings[i].message)
             << L",\"step_id\":" << simplejson::Quote(findings[i].stepId)
             << L"}";
    }
    json << L"]";
    return json.str();
}

bool RequireObject(const simplejson::Value& step, const std::wstring& key, std::vector<Finding>& findings, const std::wstring& stepId) {
    const simplejson::Value* value = simplejson::Find(step, key);
    if (value && value->IsObject()) return true;
    AddFinding(findings, L"VALIDATION_SCHEMA_INVALID", L"Required object is missing: " + key, stepId);
    return false;
}

bool RequireString(const simplejson::Value& step, const std::wstring& key, std::vector<Finding>& findings, const std::wstring& stepId) {
    const simplejson::Value* value = simplejson::Find(step, key);
    if (value && value->IsString() && !value->stringValue.empty()) return true;
    AddFinding(findings, L"VALIDATION_SCHEMA_INVALID", L"Required string is missing: " + key, stepId);
    return false;
}

bool EvidencePolicyOk(const simplejson::Value& evidence) {
    return simplejson::GetBool(evidence, L"raw_evidence_required", false) &&
           simplejson::GetBool(evidence, L"verifier_required", false) &&
           simplejson::GetBool(evidence, L"gate_required", false);
}

bool SessionPolicyOk(const simplejson::Value& session) {
    return simplejson::GetBool(session, L"session_required", false) &&
           simplejson::GetBool(session, L"session_reuse_allowed", false) &&
           !simplejson::GetString(session, L"cache_policy").empty();
}

StepContractV63ValidationResult BuildResult(
    const std::vector<Finding>& findings,
    const std::vector<Finding>& warnings,
    bool executable,
    bool runtimeSessionCompatible,
    bool safeForPublicRelease) {
    StepContractV63ValidationResult result;
    result.validationOk = findings.empty();
    result.executable = result.validationOk && executable;
    result.runtimeSessionCompatible = result.validationOk && runtimeSessionCompatible;
    result.safeForDeveloperFullAccess = result.validationOk;
    result.safeForPublicRelease = result.validationOk && safeForPublicRelease;
    if (!findings.empty()) {
        result.errorCode = findings.front().code;
        result.errorMessage = findings.front().message;
    }
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.3.0.step_contract.validation\""
         << L",\"validation_ok\":" << simplejson::Bool(result.validationOk)
         << L",\"validation_errors\":" << FindingsJson(findings)
         << L",\"validation_warnings\":" << FindingsJson(warnings)
         << L",\"executable\":" << simplejson::Bool(result.executable)
         << L",\"runtime_session_compatible\":" << simplejson::Bool(result.runtimeSessionCompatible)
         << L",\"safe_for_developer_full_access\":" << simplejson::Bool(result.safeForDeveloperFullAccess)
         << L",\"safe_for_public_release\":" << simplejson::Bool(result.safeForPublicRelease)
         << L"}";
    result.resultJson = json.str();
    return result;
}

}  // namespace

StepContractV63ValidationResult ValidateStepContractV63Json(const std::wstring& json) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) {
        std::vector<Finding> findings;
        AddFinding(findings, L"COMPILE_SCHEMA_INVALID", L"StepContract JSON is malformed or not an object.");
        return BuildResult(findings, {}, false, false, false);
    }

    std::vector<Finding> findings;
    std::vector<Finding> warnings;
    if (simplejson::GetString(parsed.root, L"schema_version") != L"6.3.0.step_contract") {
        AddFinding(findings, L"VALIDATION_SCHEMA_INVALID", L"schema_version must be 6.3.0.step_contract.");
    }
    const simplejson::Value* contracts = simplejson::Find(parsed.root, L"contracts");
    if (!contracts || !contracts->IsArray() || contracts->arrayValue.empty()) {
        AddFinding(findings, L"VALIDATION_SCHEMA_INVALID", L"contracts array is required.");
        return BuildResult(findings, warnings, false, false, false);
    }

    std::set<std::wstring> stepIds;
    bool allExecutable = true;
    bool runtimeSessionCompatible = true;
    bool publicReleaseSafe = true;

    for (size_t i = 0; i < contracts->arrayValue.size(); ++i) {
        const simplejson::Value& step = contracts->arrayValue[i];
        if (!step.IsObject()) {
            AddFinding(findings, L"VALIDATION_SCHEMA_INVALID", L"StepContract entry must be an object.");
            continue;
        }

        std::wstring stepId = simplejson::GetString(step, L"step_id");
        RequireString(step, L"contract_id", findings, stepId);
        RequireString(step, L"task_id", findings, stepId);
        RequireString(step, L"plan_id", findings, stepId);
        RequireString(step, L"step_id", findings, stepId);
        RequireString(step, L"step_type", findings, stepId);
        RequireString(step, L"runtime_action", findings, stepId);
        RequireString(step, L"created_at", findings, stepId);
        RequireString(step, L"compiler_version", findings, stepId);

        if (!stepId.empty()) {
            if (stepIds.count(stepId) != 0) {
                AddFinding(findings, L"VALIDATION_DUPLICATE_STEP_ID", L"duplicate step_id is not allowed.", stepId);
            }
            stepIds.insert(stepId);
        }

        int stepIndex = simplejson::GetInt(step, L"step_index", -1);
        if (stepIndex != static_cast<int>(i)) {
            AddFinding(findings, L"VALIDATION_STEP_INDEX_NOT_CONTINUOUS", L"step_index must be continuous from zero.", stepId);
        }

        std::wstring runtimeAction = simplejson::GetString(step, L"runtime_action");
        std::wstring target = simplejson::GetString(step, L"target");
        bool executable = simplejson::GetBool(step, L"executable", true);
        std::wstring risk = simplejson::GetString(step, L"risk_level");
        if (!simplejson::GetString(step, L"operation_type").empty() ||
            !simplejson::GetString(step, L"final_mode_used").empty() ||
            simplejson::GetBool(step, L"backend_fallback_used", false) ||
            simplejson::GetBool(step, L"max_attempts_exceeded", false)) {
            VisibleOperationPolicyResult priority = enforce_visible_operation_priority(VisiblePriorityFromStep(step, runtimeAction));
            if (!priority.ok) {
                AddFinding(findings, priority.errorCode.empty() ? L"VALIDATION_VISIBLE_FIRST_PRIORITY_VIOLATION" : priority.errorCode, priority.errorMessage.empty() ? L"Visible-first operation priority evidence is invalid." : priority.errorMessage, stepId);
            }
        }

        if (!IsSupportedRuntimeAction(runtimeAction)) {
            AddFinding(findings, L"VALIDATION_UNSUPPORTED_RUNTIME_ACTION", L"runtime_action is not supported.", stepId);
            runtimeSessionCompatible = false;
        }
        if (IsDirectCoordinateAction(runtimeAction, target) && executable) {
            AddFinding(findings, L"VALIDATION_UNSAFE_DIRECT_COORDINATE", L"direct coordinate action must not be executable.", stepId);
        }
        if (!IsSupportedRisk(risk)) {
            AddFinding(findings, L"VALIDATION_RISK_LEVEL_INVALID", L"risk_level is invalid.", stepId);
        }
        if (IsExplorerWorkflowAction(runtimeAction)) {
            std::wstring allowedRoot = simplejson::GetString(step, L"allowed_root");
            if (allowedRoot.empty()) {
                AddFinding(warnings, L"VALIDATION_EXPLORER_ALLOWED_ROOT_MISSING", L"Legacy Explorer StepContract is missing allowed_root; ExplorerWorkflow schema still requires it.", stepId);
            }
            if (runtimeAction == L"explorer_delete_file" && risk != L"DESTRUCTIVE") {
                AddFinding(findings, L"VALIDATION_EXPLORER_DELETE_RISK_INVALID", L"explorer_delete_file must use risk_level=DESTRUCTIVE.", stepId);
            }
            if ((runtimeAction == L"explorer_rename_file" || runtimeAction == L"explorer_move_file" || runtimeAction == L"explorer_context_menu_action") &&
                risk != L"REVERSIBLE_DRAFT") {
                AddFinding(findings, L"VALIDATION_EXPLORER_REVERSIBLE_RISK_INVALID", L"Explorer rename/move/context-menu workflows must use risk_level=REVERSIBLE_DRAFT.", stepId);
            }
        }
        if (IsBrowserWorkflowAction(runtimeAction)) {
            std::wstring allowedPrefix = simplejson::GetString(step, L"allowed_url_prefix");
            if (allowedPrefix.empty()) {
                AddFinding(findings, L"VALIDATION_BROWSER_ALLOWED_URL_PREFIX_MISSING", L"Browser workflow StepContract requires allowed_url_prefix.", stepId);
            }
            std::wstring backend = simplejson::GetString(step, L"requested_action_backend");
            if (backend.empty()) backend = simplejson::GetString(step, L"action_backend");
            if (IsBackendAutomationText(backend) || IsBackendAutomationText(runtimeAction)) {
                AddFinding(findings, L"VALIDATION_BROWSER_BACKEND_AUTOMATION_REJECTED", L"Browser workflow must not use DOM/JS/WebDriver/CDP/Playwright/Selenium.", stepId);
            }
            if (simplejson::GetString(step, L"coordinate_source_type") == L"direct_coordinate") {
                AddFinding(findings, L"VALIDATION_UNSAFE_DIRECT_COORDINATE", L"Browser workflow must not execute direct coordinate action.", stepId);
            }
            if (runtimeAction == L"browser_fill_form" || runtimeAction == L"browser_submit_form") {
                const simplejson::Value* pre = simplejson::Find(step, L"action_precondition");
                if (!pre || !pre->IsObject() ||
                    !simplejson::GetBool(*pre, L"focus_required", false) ||
                    !simplejson::GetBool(*pre, L"mouse_first_required", false) ||
                    !simplejson::GetBool(*pre, L"target_unique_required", false)) {
                    AddFinding(findings, L"VALIDATION_BROWSER_FORM_PRECONDITION_INCOMPLETE", L"Browser form steps require focus, mouse-first, and unique-target preconditions.", stepId);
                }
            }
            if (runtimeAction == L"browser_submit_form") {
                const simplejson::Value* submitPolicy = simplejson::Find(step, L"submit_policy");
                if (!submitPolicy || !submitPolicy->IsObject()) {
                    AddFinding(findings, L"VALIDATION_BROWSER_SUBMIT_POLICY_MISSING", L"browser_submit_form requires submit_policy.", stepId);
                }
            }
        }
        if (IsCommunicationWorkflowAction(runtimeAction)) {
            if (risk == L"REAL_COMMIT" || risk == L"DESTRUCTIVE") {
                AddFinding(findings, L"VALIDATION_COMMUNICATION_RISK_INVALID", L"Communication create workflows must not use REAL_COMMIT or DESTRUCTIVE risk.", stepId);
            }
            std::wstring backend = simplejson::GetString(step, L"requested_action_backend");
            if (backend.empty()) backend = simplejson::GetString(step, L"action_backend");
            if (IsCommunicationExternalApiText(backend)) {
                AddFinding(findings, L"VALIDATION_COMMUNICATION_EXTERNAL_API_REJECTED", L"Communication workflow must not use send, external communication APIs, provider SDKs, or browser automation.", stepId);
            }
            if (!simplejson::Has(step, L"send_allowed") || simplejson::GetBool(step, L"send_allowed", true)) {
                AddFinding(findings, L"VALIDATION_COMMUNICATION_SEND_NOT_ALLOWED", L"Communication workflow StepContract must set send_allowed=false.", stepId);
            }
            if (!simplejson::Has(step, L"external_api_allowed") || simplejson::GetBool(step, L"external_api_allowed", true)) {
                AddFinding(findings, L"VALIDATION_COMMUNICATION_EXTERNAL_API_NOT_ALLOWED", L"Communication workflow StepContract must set external_api_allowed=false.", stepId);
            }
            const simplejson::Value* pre = simplejson::Find(step, L"action_precondition");
            if (!pre || !pre->IsObject() ||
                !simplejson::GetBool(*pre, L"external_api_disallowed", false) ||
                !simplejson::GetBool(*pre, L"send_disallowed", false)) {
                AddFinding(findings, L"VALIDATION_COMMUNICATION_PRECONDITION_INCOMPLETE", L"Communication workflow precondition must disallow external APIs and send.", stepId);
            }
        }
        if (IsBlockedRisk(risk) && (executable || (runtimeAction != L"non_executable_stop" && runtimeAction != L"stop"))) {
            AddFinding(findings, L"VALIDATION_BLOCKED_RISK_EXECUTABLE", risk + L" must not generate executable action.", stepId);
        }
        if (!executable) allExecutable = false;

        bool expectedContextOk = RequireObject(step, L"expected_context", findings, stepId);
        bool actionPreconditionOk = RequireObject(step, L"action_precondition", findings, stepId);
        bool verificationOk = RequireObject(step, L"verification_hint", findings, stepId);
        bool confirmationOk = RequireObject(step, L"confirmation_policy", findings, stepId);
        bool recoveryOk = RequireObject(step, L"recovery_policy", findings, stepId);
        bool stopOk = RequireObject(step, L"stop_policy", findings, stepId);
        bool sessionOk = RequireObject(step, L"session_policy", findings, stepId);
        bool evidenceOk = RequireObject(step, L"evidence_policy", findings, stepId);

        if (expectedContextOk) {
            const simplejson::Value& expectedContext = *simplejson::Find(step, L"expected_context");
            if (!simplejson::Has(expectedContext, L"expected_process_pattern") ||
                !simplejson::Has(expectedContext, L"expected_title_pattern") ||
                !simplejson::Has(expectedContext, L"required_markers") ||
                !simplejson::Has(expectedContext, L"wrong_page_patterns") ||
                !simplejson::Has(expectedContext, L"active_protection_patterns") ||
                !simplejson::Has(expectedContext, L"credential_required_patterns") ||
                !simplejson::Has(expectedContext, L"foreground_required") ||
                !simplejson::Has(expectedContext, L"window_binding_required")) {
                AddFinding(findings, L"VALIDATION_EXPECTED_CONTEXT_INCOMPLETE", L"expected_context is incomplete.", stepId);
            }
        }
        if (actionPreconditionOk) {
            const simplejson::Value& pre = *simplejson::Find(step, L"action_precondition");
            if (!simplejson::GetBool(pre, L"stale_target_reject_required", false)) {
                AddFinding(findings, L"VALIDATION_PRECONDITION_INCOMPLETE", L"stale_target_reject_required must be true.", stepId);
            }
        }
        if (verificationOk) {
            const simplejson::Value& verification = *simplejson::Find(step, L"verification_hint");
            if (simplejson::GetString(verification, L"verify_type").empty()) {
                AddFinding(findings, L"VALIDATION_VERIFICATION_HINT_INCOMPLETE", L"verification_hint.verify_type is required.", stepId);
            }
            if (!simplejson::Has(verification, L"post_action_reobserve_required")) {
                AddFinding(findings, L"VALIDATION_VERIFICATION_HINT_INCOMPLETE", L"post_action_reobserve_required is required.", stepId);
            }
        }
        if (confirmationOk && IsHighRisk(risk)) {
            const simplejson::Value& confirmation = *simplejson::Find(step, L"confirmation_policy");
            bool confirmed = simplejson::GetBool(confirmation, L"confirmation_required", false);
            bool developerMode = simplejson::GetBool(confirmation, L"developer_full_access_allowed", false);
            if (!confirmed && !developerMode) {
                AddFinding(findings, L"VALIDATION_REAL_COMMIT_POLICY_MISSING", L"REAL_COMMIT/DESTRUCTIVE requires confirmation_policy.", stepId);
            }
            if (runtimeAction == L"explorer_delete_file" && !confirmed) {
                AddFinding(findings, L"VALIDATION_EXPLORER_DELETE_CONFIRMATION_MISSING", L"explorer_delete_file requires confirmation_required=true.", stepId);
            }
            publicReleaseSafe = false;
        }
        if (recoveryOk) {
            const simplejson::Value& recovery = *simplejson::Find(step, L"recovery_policy");
            if (RecoveryBypassesProtection(recovery)) {
                AddFinding(findings, L"VALIDATION_RECOVERY_POLICY_INVALID", L"recovery_policy must not bypass active protection or credentials.", stepId);
            }
        }
        if (stopOk) {
            const simplejson::Value& stop = *simplejson::Find(step, L"stop_policy");
            if (!simplejson::GetBool(stop, L"stop_on_active_protection", false) ||
                !simplejson::GetBool(stop, L"stop_on_credential_required", false) ||
                !simplejson::GetBool(stop, L"stop_on_unverified_result", false) ||
                !simplejson::GetBool(stop, L"stop_on_runtime_guard_failure", false)) {
                AddFinding(findings, L"VALIDATION_STOP_POLICY_INCOMPLETE", L"stop_policy must preserve protection, credential, verification, and guard stops.", stepId);
            }
        }
        if (sessionOk) {
            const simplejson::Value& session = *simplejson::Find(step, L"session_policy");
            if (!SessionPolicyOk(session)) {
                AddFinding(findings, L"VALIDATION_SESSION_POLICY_INVALID", L"session_policy is not v6.2 session compatible.", stepId);
                runtimeSessionCompatible = false;
            }
        }
        if (evidenceOk) {
            const simplejson::Value& evidence = *simplejson::Find(step, L"evidence_policy");
            if (!EvidencePolicyOk(evidence)) {
                AddFinding(findings, L"VALIDATION_EVIDENCE_POLICY_INVALID", L"evidence_policy must require raw evidence, verifier, and gate.", stepId);
            }
        }
    }

    return BuildResult(findings, warnings, allExecutable, runtimeSessionCompatible, publicReleaseSafe);
}

StepContractV63ValidationResult ValidateStepContractV63File(
    const std::wstring& inputPath,
    const std::wstring& resultPath) {
    FileReadResult read = ReadTextFile(inputPath);
    StepContractV63ValidationResult result;
    if (!read.ok) {
        std::vector<Finding> findings;
        AddFinding(findings, read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read StepContract file: " + read.error);
        result = BuildResult(findings, {}, false, false, false);
    } else {
        result = ValidateStepContractV63Json(read.content);
    }
    if (!resultPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(resultPath, result.resultJson, writeError);
    }
    return result;
}

int CommandStepContractValidateV63(int argc, wchar_t** argv) {
    const std::wstring command = L"step-contract-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring resultPath;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-contract-validate requires --input for v6.3 validation.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--result", resultPath);
    StepContractV63ValidationResult result = ValidateStepContractV63File(input, resultPath);
    std::wstring data = L"{\"input\":" + simplejson::Quote(input)
        + L",\"result\":" + simplejson::Quote(resultPath)
        + L",\"validation_ok\":" + simplejson::Bool(result.validationOk)
        + L",\"executable\":" + simplejson::Bool(result.executable)
        + L",\"runtime_session_compatible\":" + simplejson::Bool(result.runtimeSessionCompatible)
        + L",\"runtime_executed\":false}";
    if (!result.validationOk) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"STEP_CONTRACT_VALIDATION_FAILED" : result.errorCode, result.errorMessage, result.resultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}
