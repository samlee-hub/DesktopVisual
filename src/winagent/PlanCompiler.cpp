#include "PlanCompiler.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <iostream>
#include <sstream>
#include <vector>

namespace {

const wchar_t* kCompilerVersion = L"6.3.0";
const wchar_t* kStepContractSchema = L"6.3.0.step_contract";

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
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

std::wstring FirstString(const simplejson::Value& object, const std::vector<std::wstring>& keys, const std::wstring& def = L"") {
    for (const std::wstring& key : keys) {
        const simplejson::Value* value = simplejson::Find(object, key);
        if (value && value->IsString()) return value->stringValue;
    }
    return def;
}

bool FirstBool(const simplejson::Value& object, const std::vector<std::wstring>& keys, bool def = false) {
    for (const std::wstring& key : keys) {
        const simplejson::Value* value = simplejson::Find(object, key);
        if (value && value->IsBool()) return value->boolValue;
    }
    return def;
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

std::wstring JsonValueJson(const simplejson::Value& value) {
    if (value.IsNull()) return L"null";
    if (value.IsBool()) return simplejson::Bool(value.boolValue);
    if (value.IsNumber()) {
        std::wstringstream stream;
        stream << static_cast<long long>(value.numberValue);
        return stream.str();
    }
    if (value.IsString()) return simplejson::Quote(value.stringValue);
    if (value.IsArray()) {
        std::wstringstream json;
        json << L"[";
        for (size_t i = 0; i < value.arrayValue.size(); ++i) {
            if (i) json << L",";
            json << JsonValueJson(value.arrayValue[i]);
        }
        json << L"]";
        return json.str();
    }
    std::wstringstream json;
    json << L"{";
    bool first = true;
    for (const auto& entry : value.objectValue) {
        if (!first) json << L",";
        first = false;
        json << simplejson::Quote(entry.first) << L":" << JsonValueJson(entry.second);
    }
    json << L"}";
    return json.str();
}

std::vector<std::wstring> StringArrayFromObject(const simplejson::Value& object, const std::wstring& key) {
    return simplejson::GetStringArray(object, key);
}

std::wstring NormalizeRisk(const std::wstring& raw) {
    std::wstring risk = ToLowerInvariant(raw);
    if (risk == L"read_only" || risk == L"readonly" || risk == L"read-only") return L"READ_ONLY";
    if (risk == L"low" || risk == L"low_risk" || risk == L"low-risk") return L"LOW_RISK";
    if (risk == L"reversible_draft" || risk == L"draft" || risk == L"medium") return L"REVERSIBLE_DRAFT";
    if (risk == L"real_commit" || risk == L"real-commit" || risk == L"commit" || risk == L"high") return L"REAL_COMMIT";
    if (risk == L"destructive" || risk == L"delete") return L"DESTRUCTIVE";
    if (risk == L"active_protection_blocked" || risk == L"active-protection-blocked") return L"ACTIVE_PROTECTION_BLOCKED";
    if (risk == L"credential_required_blocked" || risk == L"credential-required-blocked") return L"CREDENTIAL_REQUIRED_BLOCKED";
    return L"";
}

bool IsBlockedRisk(const std::wstring& risk) {
    return risk == L"ACTIVE_PROTECTION_BLOCKED" || risk == L"CREDENTIAL_REQUIRED_BLOCKED";
}

bool IsHighRisk(const std::wstring& risk) {
    return risk == L"REAL_COMMIT" || risk == L"DESTRUCTIVE";
}

bool IsDirectCoordinateAction(const std::wstring& proposedAction, const std::wstring& target) {
    return ContainsInsensitive(proposedAction, L"direct_coordinate") ||
           ContainsInsensitive(proposedAction, L"coordinate_click") ||
           ContainsInsensitive(target, L"coord:") ||
           (ContainsInsensitive(target, L"x=") && ContainsInsensitive(target, L"y="));
}

bool HasAcceptedCoordinatePolicy(const simplejson::Value& step) {
    std::wstring policy = FirstString(step, {L"coordinate_policy", L"coordinate_source_type"});
    const simplejson::Value* evidence = simplejson::Find(step, L"evidence_policy");
    return (policy == L"locator_derived" || policy == L"locator_derived_coordinate") && evidence && evidence->IsObject();
}

bool UnsafeRecoveryHint(const std::wstring& hint) {
    return ContainsInsensitive(hint, L"bypass captcha") ||
           ContainsInsensitive(hint, L"solve captcha") ||
           ContainsInsensitive(hint, L"bypass human verification") ||
           ContainsInsensitive(hint, L"bypass credential") ||
           ContainsInsensitive(hint, L"bypass password") ||
           ContainsInsensitive(hint, L"skip credential") ||
           ContainsInsensitive(hint, L"override credential");
}

std::wstring RuntimeActionFromProposed(const std::wstring& proposedAction) {
    std::wstring action = ToLowerInvariant(proposedAction);
    if (action == L"explorer_open_path" || action == L"explorer.open_path") return L"explorer_open_path";
    if (action == L"explorer_open_file" || action == L"explorer.open_file") return L"explorer_open_file";
    if (action == L"explorer_rename_file" || action == L"explorer.rename_file") return L"explorer_rename_file";
    if (action == L"explorer_move_file" || action == L"explorer.move_file") return L"explorer_move_file";
    if (action == L"explorer_delete_file" || action == L"explorer.delete_file") return L"explorer_delete_file";
    if (action == L"explorer_context_menu_action" || action == L"explorer.context_menu_action") return L"explorer_context_menu_action";
    if (action == L"explorer_scroll_and_locate" || action == L"explorer.scroll_and_locate") return L"explorer_scroll_and_locate";
    if (action == L"browser_open_page" || action == L"browser.open_page" || action == L"browser.open_local_page") return L"browser_open_page";
    if (action == L"browser_surface_normalize" || action == L"browser.surface_normalize") return L"browser_surface_normalize";
    if (action == L"click" || action == L"click_field" || action == L"click_button" || action == L"button_click") return L"click";
    if (action == L"click_submit" || action == L"submit_click") return L"click_submit";
    if (action == L"run_button_click" || action == L"run_code" || action == L"code_editor_run") return L"run_button_click";
    if (action == L"type" || action == L"type_text" || action == L"fill_field" || action == L"message_draft_fill" || action == L"browser.form_fill") return L"type";
    if (action == L"verify" || action == L"verify_field" || action == L"verify_result" || action == L"browser.read_title") return L"verify";
    if (action == L"scroll" || action == L"scroll_and_locate") return action;
    if (action == L"send_message" || action == L"send_mail" || action == L"developer_real_commit") return L"click";
    if (action == L"active_protection_stop" || action == L"credential_required_stop" || action == L"stop") return L"non_executable_stop";
    return L"";
}

std::wstring StepTypeForAction(const std::wstring& runtimeAction) {
    if (runtimeAction == L"explorer_open_path" || runtimeAction == L"explorer_open_file" || runtimeAction == L"browser_open_page") return L"open";
    if (runtimeAction == L"explorer_rename_file") return L"rename";
    if (runtimeAction == L"explorer_move_file") return L"move";
    if (runtimeAction == L"explorer_delete_file") return L"delete";
    if (runtimeAction == L"explorer_context_menu_action") return L"context_menu";
    if (runtimeAction == L"click" || runtimeAction == L"click_submit" || runtimeAction == L"run_button_click") return L"click";
    if (runtimeAction == L"type") return L"type";
    if (runtimeAction == L"verify") return L"verify";
    if (runtimeAction == L"scroll" || runtimeAction == L"scroll_and_locate") return L"scroll";
    if (runtimeAction == L"non_executable_stop") return L"stop";
    return L"runtime_step";
}

std::wstring ExpectedContextJson(const simplejson::Value& context) {
    std::wstring process = simplejson::GetString(context, L"expected_process_pattern", L".*");
    std::wstring title = simplejson::GetString(context, L"expected_title_pattern", L".*");
    std::vector<std::wstring> markers = StringArrayFromObject(context, L"required_markers");
    std::vector<std::wstring> wrong = StringArrayFromObject(context, L"wrong_page_patterns");
    std::vector<std::wstring> protection = StringArrayFromObject(context, L"active_protection_patterns");
    std::vector<std::wstring> credentials = StringArrayFromObject(context, L"credential_required_patterns");
    bool foreground = simplejson::GetBool(context, L"foreground_required", true);
    bool binding = simplejson::GetBool(context, L"window_binding_required", true);
    std::wstringstream json;
    json << L"{\"expected_process_pattern\":" << simplejson::Quote(process)
         << L",\"expected_title_pattern\":" << simplejson::Quote(title)
         << L",\"required_markers\":" << StringArrayJson(markers)
         << L",\"wrong_page_patterns\":" << StringArrayJson(wrong)
         << L",\"active_protection_patterns\":" << StringArrayJson(protection)
         << L",\"credential_required_patterns\":" << StringArrayJson(credentials)
         << L",\"foreground_required\":" << simplejson::Bool(foreground)
         << L",\"window_binding_required\":" << simplejson::Bool(binding)
         << L"}";
    return json.str();
}

std::wstring ActionPreconditionJson(const std::wstring& runtimeAction, const std::wstring& proposedAction, const std::wstring& intent) {
    bool isType = runtimeAction == L"type";
    bool isScroll = runtimeAction == L"scroll" || runtimeAction == L"scroll_and_locate" || runtimeAction == L"explorer_scroll_and_locate";
    bool mouseFirst = runtimeAction == L"click" || runtimeAction == L"click_submit" || runtimeAction == L"run_button_click" ||
        runtimeAction == L"explorer_rename_file" || runtimeAction == L"explorer_move_file" ||
        runtimeAction == L"explorer_delete_file" || runtimeAction == L"explorer_context_menu_action" ||
        ContainsInsensitive(proposedAction, L"editor") || ContainsInsensitive(intent, L"code_editor");
    std::wstringstream json;
    json << L"{\"target_required\":true"
         << L",\"target_unique_required\":true"
         << L",\"target_inside_viewport_required\":true"
         << L",\"target_current_observe_required\":true"
         << L",\"focus_required\":true"
         << L",\"mouse_first_required\":" << simplejson::Bool(mouseFirst)
         << L",\"text_input_allowed\":" << simplejson::Bool(isType)
         << L",\"scroll_allowed\":" << simplejson::Bool(isScroll)
         << L",\"stale_target_reject_required\":true}";
    return json.str();
}

std::wstring VerificationHintJson(
    const std::wstring& runtimeAction,
    const std::wstring& hint,
    const std::wstring& target,
    const std::wstring& inputText) {
    std::wstring verifyType = L"marker_visible";
    if (runtimeAction == L"explorer_open_path") verifyType = L"path_visible";
    else if (runtimeAction == L"explorer_open_file") verifyType = L"file_opened";
    else if (runtimeAction == L"explorer_rename_file") verifyType = L"file_renamed";
    else if (runtimeAction == L"explorer_move_file") verifyType = L"file_moved";
    else if (runtimeAction == L"explorer_delete_file") verifyType = L"file_deleted";
    else if (runtimeAction == L"explorer_context_menu_action") verifyType = L"context_menu_action_result";
    else if (runtimeAction == L"explorer_scroll_and_locate") verifyType = L"scroll_target_found";
    else if (runtimeAction == L"browser_open_page") verifyType = L"url_or_marker_visible";
    else if (runtimeAction == L"type") verifyType = L"field_value";
    else if (runtimeAction == L"run_button_click") verifyType = L"output_contains";
    else if (runtimeAction == L"verify") verifyType = L"marker_visible";
    std::wstring expectedFieldValue = runtimeAction == L"type" ? inputText : L"";
    std::wstringstream json;
    json << L"{\"verify_type\":" << simplejson::Quote(verifyType)
         << L",\"expected_marker\":" << simplejson::Quote(hint)
         << L",\"expected_text\":" << simplejson::Quote(hint)
         << L",\"expected_window_title\":\"\""
         << L",\"expected_url_pattern\":" << simplejson::Quote(runtimeAction == L"browser_open_page" ? target : L"")
         << L",\"expected_output_pattern\":" << simplejson::Quote(runtimeAction == L"run_button_click" ? hint : L"")
         << L",\"expected_field_value\":" << simplejson::Quote(expectedFieldValue)
         << L",\"post_action_reobserve_required\":true}";
    return json.str();
}

std::wstring ConfirmationPolicyJson(bool developerFullAccess, bool requiresConfirmation, const std::wstring& risk, const std::wstring& hint) {
    bool highRisk = IsHighRisk(risk);
    bool confirmationRequired = requiresConfirmation || highRisk;
    std::wstring reason = hint.empty() ? (highRisk ? L"risk policy requires confirmation" : L"") : hint;
    std::wstringstream json;
    json << L"{\"confirmation_required\":" << simplejson::Bool(confirmationRequired)
         << L",\"confirmation_reason\":" << simplejson::Quote(reason)
         << L",\"developer_full_access_allowed\":" << simplejson::Bool(developerFullAccess)
         << L",\"public_release_confirmation_required\":" << simplejson::Bool(highRisk)
         << L",\"manual_handoff_required\":false}";
    return json.str();
}

std::wstring RecoveryPolicyJson(const std::wstring& risk) {
    bool blocked = IsBlockedRisk(risk);
    std::wstringstream json;
    json << L"{\"recovery_allowed\":" << simplejson::Bool(!blocked)
         << L",\"recovery_scope\":\"reobserve_only\""
         << L",\"recovery_target\":\"same_context\""
         << L",\"max_recovery_attempts\":" << (blocked ? 0 : 1)
         << L",\"resume_from_checkpoint_allowed\":" << simplejson::Bool(!blocked)
         << L",\"replay_from_checkpoint_allowed\":false"
         << L",\"stop_if_recovery_fails\":true}";
    return json.str();
}

std::wstring StopPolicyJson() {
    return L"{\"stop_on_wrong_context\":true,\"stop_on_wrong_field\":true,\"stop_on_target_stale\":true,"
           L"\"stop_on_target_not_unique\":true,\"stop_on_active_protection\":true,"
           L"\"stop_on_credential_required\":true,\"stop_on_unverified_result\":true,"
           L"\"stop_on_runtime_guard_failure\":true}";
}

std::wstring SessionPolicyJson(const std::wstring& runtimeAction) {
    bool force = runtimeAction != L"verify";
    std::wstringstream json;
    json << L"{\"session_required\":true"
         << L",\"session_reuse_allowed\":true"
         << L",\"force_reobserve_before_action\":" << simplejson::Bool(force)
         << L",\"cache_policy\":" << simplejson::Quote(force ? L"force_reobserve" : L"allow_fresh_cache")
         << L",\"locator_cache_allowed\":false}";
    return json.str();
}

std::wstring EvidencePolicyJson(const std::wstring& runtimeAction) {
    bool mouse = runtimeAction == L"click" || runtimeAction == L"click_submit" || runtimeAction == L"run_button_click" ||
        runtimeAction == L"explorer_rename_file" || runtimeAction == L"explorer_move_file" ||
        runtimeAction == L"explorer_delete_file" || runtimeAction == L"explorer_context_menu_action" ||
        runtimeAction == L"explorer_scroll_and_locate";
    std::wstringstream json;
    json << L"{\"raw_evidence_required\":true"
         << L",\"verifier_required\":true"
         << L",\"gate_required\":true"
         << L",\"mouse_evidence_required\":" << simplejson::Bool(mouse)
         << L",\"latency_required\":true}";
    return json.str();
}

std::wstring SessionActionForRuntimeAction(const std::wstring& runtimeAction) {
    if (runtimeAction == L"click" || runtimeAction == L"click_submit" || runtimeAction == L"run_button_click") return L"click";
    if (runtimeAction == L"type") return L"type";
    if (runtimeAction == L"scroll" || runtimeAction == L"scroll_and_locate" || runtimeAction == L"explorer_scroll_and_locate") return L"scroll";
    if (runtimeAction == L"explorer_rename_file" || runtimeAction == L"explorer_move_file" ||
        runtimeAction == L"explorer_delete_file" || runtimeAction == L"explorer_context_menu_action") return L"click";
    if (runtimeAction == L"verify" || runtimeAction == L"non_executable_stop") return L"verify";
    return L"observe";
}

PlanCompileResult CompileFailure(
    const std::wstring& code,
    const std::wstring& message,
    const std::wstring& failedStepId,
    const std::wstring& missingFieldsJson,
    const std::wstring& unsafeReason,
    const std::wstring& repairHint) {
    PlanCompiler compiler;
    PlanCompileResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.contractJson = L"{\"schema_version\":\"6.3.0.step_contract\",\"compile_ok\":false,\"contracts\":[]}";
    result.diagnosticsJson = compiler.emit_compile_diagnostics(false, code, message, failedStepId, missingFieldsJson, unsafeReason, repairHint, 0);
    return result;
}

}  // namespace

PlanCompileResult PlanCompiler::compile_plan(const std::wstring& planDraftJson) {
    simplejson::ParseResult parsed = simplejson::Parse(planDraftJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return CompileFailure(
            L"COMPILE_SCHEMA_INVALID",
            L"AgentPlanDraft JSON is malformed or not an object.",
            L"",
            L"[\"json\"]",
            L"",
            L"Provide a valid AgentPlanDraft JSON object.");
    }

    const simplejson::Value& root = parsed.root;
    const simplejson::Value* stepsValue = simplejson::Find(root, L"steps");
    if (!stepsValue || !stepsValue->IsArray()) stepsValue = simplejson::Find(root, L"draft_steps");
    if (!stepsValue || !stepsValue->IsArray() || stepsValue->arrayValue.empty()) {
        return CompileFailure(
            L"COMPILE_SCHEMA_INVALID",
            L"AgentPlanDraft must contain non-empty steps.",
            L"",
            L"[\"steps\"]",
            L"",
            L"Add reviewed draft steps before compiling.");
    }

    std::wstring planId = FirstString(root, {L"plan_id"}, L"plan-v6-3");
    std::wstring taskId = FirstString(root, {L"task_id"}, L"task-v6-3");
    std::wstring intent = FirstString(root, {L"intent", L"intent_type"}, L"unknown");
    std::wstring planRisk = FirstString(root, {L"risk_summary", L"risk_level"}, L"");
    bool developerFullAccess = FirstBool(root, {L"developer_full_access"}, false);
    bool requiresConfirmation = FirstBool(root, {L"requires_confirmation"}, false);
    bool stopPolicyMissing = FirstBool(root, {L"stop_policy_missing"}, false);

    const simplejson::Value* globalContext = simplejson::Find(root, L"expected_context_summary");
    if (!globalContext || !globalContext->IsObject()) globalContext = simplejson::Find(root, L"expected_context");

    std::vector<std::wstring> stepJsons;
    for (size_t i = 0; i < stepsValue->arrayValue.size(); ++i) {
        const simplejson::Value& step = stepsValue->arrayValue[i];
        if (!step.IsObject()) {
            return CompileFailure(L"COMPILE_SCHEMA_INVALID", L"AgentPlanDraft step must be an object.", L"", L"[\"steps\"]", L"", L"Use JSON objects for every draft step.");
        }

        std::wstring stepId = FirstString(step, {L"draft_step_id", L"step_id"}, L"");
        if (stepId.empty()) {
            return CompileFailure(L"COMPILE_SCHEMA_INVALID", L"AgentPlanDraft step is missing draft_step_id.", L"", L"[\"draft_step_id\"]", L"", L"Add stable draft_step_id to every step.");
        }

        const simplejson::Value* stepContext = simplejson::Find(step, L"expected_context");
        const simplejson::Value* context = (stepContext && stepContext->IsObject()) ? stepContext : globalContext;
        if (!context || !context->IsObject()) {
            return CompileFailure(
                L"COMPILE_MISSING_EXPECTED_CONTEXT",
                L"Step cannot compile without expected_context.",
                stepId,
                L"[\"expected_context\"]",
                L"",
                L"Add expected_context_summary or per-step expected_context.");
        }

        std::wstring verificationHint = FirstString(step, {L"verification_hint"}, L"");
        if (verificationHint.empty()) {
            return CompileFailure(
                L"COMPILE_MISSING_VERIFICATION_HINT",
                L"Step cannot compile without verification_hint.",
                stepId,
                L"[\"verification_hint\"]",
                L"",
                L"Add a concrete post-action verification hint.");
        }

        std::wstring proposedAction = FirstString(step, {L"proposed_action", L"expected_runtime_capability"}, L"");
        std::wstring target = FirstString(step, {L"target_description", L"target"}, L"");
        if (IsDirectCoordinateAction(proposedAction, target) && !HasAcceptedCoordinatePolicy(step)) {
            return CompileFailure(
                L"COMPILE_UNSAFE_DIRECT_COORDINATE",
                L"Direct coordinate action lacks accepted locator/evidence policy.",
                stepId,
                L"[]",
                L"direct coordinate without locator/evidence policy",
                L"Use a locator-derived target and evidence policy, or do not compile as executable.");
        }

        std::wstring runtimeAction = RuntimeActionFromProposed(proposedAction);
        if (runtimeAction.empty()) {
            return CompileFailure(
                L"COMPILE_UNSUPPORTED_ACTION",
                L"Draft step proposed_action is unsupported by v6.3 compiler.",
                stepId,
                L"[\"proposed_action\"]",
                proposedAction,
                L"Use a supported Runtime action such as click, type, verify, browser_open_page, or explorer_open_path.");
        }

        if (FirstBool(step, {L"target_ambiguous"}, false) || ContainsInsensitive(target, L"ambiguous")) {
            return CompileFailure(
                L"COMPILE_TARGET_AMBIGUOUS",
                L"Draft step target is ambiguous.",
                stepId,
                L"[\"target_description\"]",
                L"target ambiguous",
                L"Provide a unique target description or locator.");
        }

        if (stopPolicyMissing || FirstBool(step, {L"stop_policy_missing"}, false)) {
            return CompileFailure(
                L"COMPILE_STOP_POLICY_MISSING",
                L"Draft step explicitly lacks required stop_policy.",
                stepId,
                L"[\"stop_policy\"]",
                L"",
                L"Compiler must emit a complete stop_policy for every step.");
        }

        std::wstring risk = NormalizeRisk(FirstString(step, {L"risk_hint", L"risk"}, planRisk));
        if (risk.empty()) {
            return CompileFailure(
                L"COMPILE_RISK_POLICY_MISSING",
                L"Draft step lacks a supported risk policy.",
                stepId,
                L"[\"risk_hint\"]",
                L"",
                L"Set risk_hint to READ_ONLY, LOW_RISK, REVERSIBLE_DRAFT, REAL_COMMIT, DESTRUCTIVE, ACTIVE_PROTECTION_BLOCKED, or CREDENTIAL_REQUIRED_BLOCKED.");
        }

        std::wstring confirmationHint = FirstString(step, {L"confirmation_hint"}, L"");
        if (IsHighRisk(risk) && !requiresConfirmation && !developerFullAccess && confirmationHint.empty()) {
            return CompileFailure(
                L"COMPILE_CONFIRMATION_REQUIRED",
                L"REAL_COMMIT or DESTRUCTIVE step requires confirmation or developer-mode policy.",
                stepId,
                L"[\"confirmation_policy\"]",
                L"high risk without confirmation policy",
                L"Set requires_confirmation, developer_full_access, or confirmation_hint.");
        }

        std::wstring recoveryHint = FirstString(step, {L"recovery_hint"}, L"");
        if (UnsafeRecoveryHint(recoveryHint)) {
            return CompileFailure(
                L"COMPILE_RECOVERY_POLICY_INVALID",
                L"Recovery policy attempts to bypass active protection or credentials.",
                stepId,
                L"[\"recovery_hint\"]",
                recoveryHint,
                L"Recovery may reobserve or stop; it must not bypass protection or credentials.");
        }

        bool executable = !IsBlockedRisk(risk) && runtimeAction != L"non_executable_stop";
        std::wstring inputText = FirstString(step, {L"input_text"}, L"");
        bool explorerRuntimeAction = runtimeAction.rfind(L"explorer_", 0) == 0;
        std::wstring allowedRoot = FirstString(step, {L"allowed_root"}, FirstString(root, {L"allowed_root"}, L"D:\\testrepo"));
        std::wstringstream stepJson;
        stepJson << L"{\"contract_id\":" << simplejson::Quote(L"contract-" + planId + L"-" + std::to_wstring(i))
                 << L",\"task_id\":" << simplejson::Quote(taskId)
                 << L",\"plan_id\":" << simplejson::Quote(planId)
                 << L",\"step_id\":" << simplejson::Quote(stepId)
                 << L",\"step_index\":" << i
                 << L",\"step_type\":" << simplejson::Quote(StepTypeForAction(runtimeAction))
                 << L",\"runtime_action\":" << simplejson::Quote(executable ? runtimeAction : L"non_executable_stop")
                 << L",\"target\":" << simplejson::Quote(target)
                 << L",\"input_text\":" << simplejson::Quote(inputText)
                 << L",\"executable\":" << simplejson::Bool(executable)
                 << L",\"expected_context\":" << ExpectedContextJson(*context)
                 << L",\"action_precondition\":" << ActionPreconditionJson(runtimeAction, proposedAction, intent)
                 << L",\"verification_hint\":" << VerificationHintJson(runtimeAction, verificationHint, target, inputText)
                 << L",\"risk_level\":" << simplejson::Quote(risk)
                 << L",\"confirmation_policy\":" << ConfirmationPolicyJson(developerFullAccess, requiresConfirmation, risk, confirmationHint)
                 << L",\"recovery_policy\":" << RecoveryPolicyJson(risk)
                 << L",\"stop_policy\":" << StopPolicyJson()
                 << L",\"session_policy\":" << SessionPolicyJson(runtimeAction)
                 << L",\"evidence_policy\":" << EvidencePolicyJson(runtimeAction)
                 << (explorerRuntimeAction ? (L",\"allowed_root\":" + simplejson::Quote(allowedRoot)) : L"")
                 << L",\"created_at\":" << simplejson::Quote(NowTimestamp())
                 << L",\"compiler_version\":" << simplejson::Quote(kCompilerVersion)
                 << L"}";
        stepJsons.push_back(stepJson.str());
    }

    std::wstringstream contract;
    contract << L"{\"schema_version\":" << simplejson::Quote(kStepContractSchema)
             << L",\"compiler_version\":" << simplejson::Quote(kCompilerVersion)
             << L",\"compile_ok\":true"
             << L",\"runtime_executed\":false"
             << L",\"task_id\":" << simplejson::Quote(taskId)
             << L",\"plan_id\":" << simplejson::Quote(planId)
             << L",\"contracts\":[";
    for (size_t i = 0; i < stepJsons.size(); ++i) {
        if (i) contract << L",";
        contract << stepJsons[i];
    }
    contract << L"]}";

    PlanCompileResult result;
    result.ok = true;
    result.stepCount = static_cast<int>(stepJsons.size());
    result.contractJson = contract.str();
    result.diagnosticsJson = emit_compile_diagnostics(true, L"", L"", L"", L"[]", L"", L"", result.stepCount);
    return result;
}

PlanCompileResult PlanCompiler::emit_runtime_session_steps(const std::wstring& stepContractJson) {
    simplejson::ParseResult parsed = simplejson::Parse(stepContractJson);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return CompileFailure(L"COMPILE_SCHEMA_INVALID", L"StepContract JSON is malformed.", L"", L"[\"step_contract\"]", L"", L"Provide valid StepContract JSON.");
    }
    const simplejson::Value* contracts = simplejson::Find(parsed.root, L"contracts");
    if (!contracts || !contracts->IsArray()) {
        return CompileFailure(L"COMPILE_SCHEMA_INVALID", L"StepContract contracts array is missing.", L"", L"[\"contracts\"]", L"", L"Provide compiled StepContract JSON.");
    }
    std::wstringstream steps;
    steps << L"{\"schema_version\":\"6.3.0.session_steps_dry_run\""
          << L",\"runtime_executed\":false"
          << L",\"step_count\":" << contracts->arrayValue.size()
          << L",\"session_steps\":[";
    for (size_t i = 0; i < contracts->arrayValue.size(); ++i) {
        const simplejson::Value& step = contracts->arrayValue[i];
        std::wstring runtimeAction = simplejson::GetString(step, L"runtime_action");
        std::wstring sessionAction = SessionActionForRuntimeAction(runtimeAction);
        const simplejson::Value* expectedContext = simplejson::Find(step, L"expected_context");
        const simplejson::Value* precondition = simplejson::Find(step, L"action_precondition");
        const simplejson::Value* verification = simplejson::Find(step, L"verification_hint");
        const simplejson::Value* sessionPolicy = simplejson::Find(step, L"session_policy");
        if (i) steps << L",";
        steps << L"{\"step_id\":" << simplejson::Quote(simplejson::GetString(step, L"step_id"))
              << L",\"action\":" << simplejson::Quote(sessionAction)
              << L",\"compiled_runtime_action\":" << simplejson::Quote(runtimeAction)
              << L",\"target\":" << simplejson::Quote(simplejson::GetString(step, L"target"))
              << L",\"text\":" << simplejson::Quote(simplejson::GetString(step, L"input_text"))
              << L",\"expected_context\":" << (expectedContext ? JsonValueJson(*expectedContext) : L"{}")
              << L",\"action_precondition\":" << (precondition ? JsonValueJson(*precondition) : L"{}")
              << L",\"verification_hint\":" << (verification ? JsonValueJson(*verification) : L"{}")
              << L",\"cache_policy\":" << simplejson::Quote(sessionPolicy ? simplejson::GetString(*sessionPolicy, L"cache_policy", L"force_reobserve") : L"force_reobserve")
              << L",\"force_reobserve\":" << simplejson::Bool(sessionPolicy ? simplejson::GetBool(*sessionPolicy, L"force_reobserve_before_action", true) : true)
              << L",\"stop_on_failure\":true"
              << L",\"executable\":" << simplejson::Bool(simplejson::GetBool(step, L"executable", true))
              << L"}";
    }
    steps << L"]}";

    PlanCompileResult result;
    result.ok = true;
    result.stepCount = static_cast<int>(contracts->arrayValue.size());
    result.sessionStepsJson = steps.str();
    return result;
}

PlanCompileResult PlanCompiler::compile_step() {
    return PlanCompileResult{};
}

std::wstring PlanCompiler::infer_runtime_action(const std::wstring& proposedAction) {
    return RuntimeActionFromProposed(proposedAction);
}

std::wstring PlanCompiler::compile_expected_context() {
    return L"{}";
}

std::wstring PlanCompiler::compile_action_precondition() {
    return ActionPreconditionJson(L"verify", L"verify", L"");
}

std::wstring PlanCompiler::compile_verification_hint() {
    return VerificationHintJson(L"verify", L"marker visible", L"", L"");
}

std::wstring PlanCompiler::compile_risk_level(const std::wstring& rawRisk) {
    return NormalizeRisk(rawRisk);
}

std::wstring PlanCompiler::compile_confirmation_policy() {
    return ConfirmationPolicyJson(false, false, L"LOW_RISK", L"");
}

std::wstring PlanCompiler::compile_recovery_policy() {
    return RecoveryPolicyJson(L"LOW_RISK");
}

std::wstring PlanCompiler::compile_stop_policy() {
    return StopPolicyJson();
}

std::wstring PlanCompiler::compile_session_policy() {
    return SessionPolicyJson(L"verify");
}

std::wstring PlanCompiler::compile_evidence_policy() {
    return EvidencePolicyJson(L"verify");
}

std::wstring PlanCompiler::emit_compile_diagnostics(
    bool compileOk,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& failedStepId,
    const std::wstring& missingFieldsJson,
    const std::wstring& unsafeReason,
    const std::wstring& repairHint,
    int emittedStepCount) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.3.0.compile_diagnostics\""
         << L",\"compile_ok\":" << simplejson::Bool(compileOk)
         << L",\"compiler_version\":" << simplejson::Quote(kCompilerVersion)
         << L",\"error_code\":" << simplejson::Quote(errorCode)
         << L",\"error_message\":" << simplejson::Quote(errorMessage)
         << L",\"failed_step_id\":" << simplejson::Quote(failedStepId)
         << L",\"missing_fields\":" << (missingFieldsJson.empty() ? L"[]" : missingFieldsJson)
         << L",\"unsafe_reason\":" << simplejson::Quote(unsafeReason)
         << L",\"repair_hint\":" << simplejson::Quote(repairHint)
         << L",\"emitted_step_count\":" << emittedStepCount
         << L",\"runtime_executed\":false}";
    return json.str();
}

PlanCompileResult CompilePlanDraftFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath,
    const std::wstring& diagnosticsPath) {
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        return CompileFailure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read AgentPlanDraft file: " + read.error, L"", L"[\"input\"]", L"", L"Check the input path.");
    }

    PlanCompiler compiler;
    PlanCompileResult result = compiler.compile_plan(read.content);

    std::wstring writeError;
    if (!outputPath.empty()) {
        WriteTextFileUtf8(outputPath, result.contractJson, writeError);
    }
    if (!diagnosticsPath.empty()) {
        WriteTextFileUtf8(diagnosticsPath, result.diagnosticsJson, writeError);
    }
    return result;
}

PlanCompileResult DryRunStepContractFile(
    const std::wstring& inputPath,
    const std::wstring& sessionStepsOutputPath) {
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        return CompileFailure(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read StepContract file: " + read.error, L"", L"[\"input\"]", L"", L"Check the input path.");
    }
    PlanCompiler compiler;
    PlanCompileResult result = compiler.emit_runtime_session_steps(read.content);
    std::wstring writeError;
    if (!sessionStepsOutputPath.empty()) {
        WriteTextFileUtf8(sessionStepsOutputPath, result.sessionStepsJson, writeError);
    }
    return result;
}

int CommandPlanCompile(int argc, wchar_t** argv) {
    const std::wstring command = L"plan-compile";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    std::wstring diagnostics;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"plan-compile requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    ArgValue(argc, argv, L"--diagnostics", diagnostics);
    PlanCompileResult result = CompilePlanDraftFile(input, output, diagnostics);
    std::wstring data = L"{\"compile_ok\":" + simplejson::Bool(result.ok)
        + L",\"input\":" + simplejson::Quote(input)
        + L",\"output\":" + simplejson::Quote(output)
        + L",\"diagnostics\":" + simplejson::Quote(diagnostics)
        + L",\"step_count\":" + std::to_wstring(result.stepCount)
        + L",\"runtime_executed\":false}";
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMPILE_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.diagnosticsJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}

int CommandStepContractDryRun(int argc, wchar_t** argv) {
    const std::wstring command = L"step-contract-dry-run";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-contract-dry-run requires --input.", L"{}") << L"\n";
        return 2;
    }
    if (!ArgValue(argc, argv, L"--session-steps-output", output) || output.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-contract-dry-run requires --session-steps-output.", L"{}") << L"\n";
        return 2;
    }
    PlanCompileResult result = DryRunStepContractFile(input, output);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"COMPILE_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.diagnosticsJson) << L"\n";
        return 1;
    }
    std::wstring data = L"{\"input\":" + simplejson::Quote(input)
        + L",\"session_steps_output\":" + simplejson::Quote(output)
        + L",\"step_count\":" + std::to_wstring(result.stepCount)
        + L",\"runtime_executed\":false}";
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}

int CommandPlanCompileSelftest(int argc, wchar_t** argv) {
    (void)argc;
    (void)argv;
    const std::wstring command = L"plan-compile-selftest";
    ULONGLONG startTick = GetTickCount64();
    const std::wstring sample =
        L"{\"plan_id\":\"selftest-plan\",\"task_id\":\"selftest-task\",\"intent\":\"explorer_open_path\","
        L"\"risk_summary\":\"LOW_RISK\",\"requires_confirmation\":false,\"developer_full_access\":false,"
        L"\"expected_context_summary\":{\"expected_process_pattern\":\"explorer.exe\",\"expected_title_pattern\":\"testwindow\","
        L"\"required_markers\":[\"testwindow\"],\"wrong_page_patterns\":[],\"active_protection_patterns\":[\"captcha\"],"
        L"\"credential_required_patterns\":[\"password\"],\"foreground_required\":true,\"window_binding_required\":true},"
        L"\"steps\":[{\"draft_step_id\":\"selftest-step\",\"proposed_action\":\"explorer_open_path\","
        L"\"target_description\":\"D:\\\\testrepo\\\\testwindow\",\"input_text\":\"\",\"risk_hint\":\"LOW_RISK\","
        L"\"recovery_hint\":\"reobserve only\",\"verification_hint\":\"path visible\"}]}";
    PlanCompiler compiler;
    PlanCompileResult result = compiler.compile_plan(sample);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode, result.errorMessage, result.diagnosticsJson) << L"\n";
        return 1;
    }
    std::wstring data = L"{\"compile_ok\":true,\"step_count\":" + std::to_wstring(result.stepCount) + L",\"runtime_executed\":false}";
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}
