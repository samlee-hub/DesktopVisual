#include "BrowserWorkflow.h"

#include "CaseRunner.h"
#include "RuntimeSession.h"
#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool EmptyOrWhitespace(const std::wstring& value) {
    for (wchar_t ch : value) {
        if (std::iswspace(ch) == 0) return false;
    }
    return true;
}

bool StartsWithInsensitive(const std::wstring& value, const std::wstring& prefix) {
    if (prefix.size() > value.size()) return false;
    return Lower(value.substr(0, prefix.size())) == Lower(prefix);
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

std::wstring JsonValueToString(const simplejson::Value& value) {
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
            json << JsonValueToString(value.arrayValue[i]);
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
        json << simplejson::Quote(entry.first) << L":" << JsonValueToString(entry.second);
    }
    json << L"}";
    return json.str();
}

std::wstring ObjectJsonOrEmpty(const simplejson::Value& root, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(root, key);
    if (!value || !value->IsObject()) return L"";
    return JsonValueToString(*value);
}

std::wstring FailureDiagnostics(const std::wstring& code, const std::wstring& message) {
    return L"{\"schema_version\":\"6.8.0.browser_workflow.schema_diagnostics\""
        L",\"validation_ok\":false"
        L",\"error_code\":" + simplejson::Quote(code) +
        L",\"error_message\":" + simplejson::Quote(message) + L"}";
}

BrowserWorkflowSchemaResult Fail(const std::wstring& code, const std::wstring& message, BrowserWorkflowSpec spec = BrowserWorkflowSpec{}) {
    BrowserWorkflowSchemaResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.spec = spec;
    result.diagnosticsJson = FailureDiagnostics(code, message);
    return result;
}

std::vector<BrowserWorkflowFieldSpec> ParseFields(const simplejson::Value& form) {
    std::vector<BrowserWorkflowFieldSpec> fields;
    const simplejson::Value* rawFields = simplejson::Find(form, L"fields");
    if (!rawFields || !rawFields->IsArray()) return fields;
    for (const auto& item : rawFields->arrayValue) {
        if (!item.IsObject()) continue;
        BrowserWorkflowFieldSpec field;
        field.fieldId = simplejson::GetString(item, L"field_id");
        field.fieldLabel = simplejson::GetString(item, L"field_label");
        if (field.fieldLabel.empty()) field.fieldLabel = simplejson::GetString(item, L"label");
        field.placeholder = simplejson::GetString(item, L"placeholder");
        field.name = simplejson::GetString(item, L"name");
        field.title = simplejson::GetString(item, L"title");
        field.expectedRole = simplejson::GetString(item, L"expected_role", L"Edit");
        field.value = simplejson::GetString(item, L"value");
        field.required = simplejson::GetBool(item, L"required", false);
        fields.push_back(field);
    }
    return fields;
}

BrowserWorkflowSubmitSpec ParseSubmit(const simplejson::Value& form) {
    BrowserWorkflowSubmitSpec submit;
    const simplejson::Value* rawSubmit = simplejson::Find(form, L"submit");
    if (!rawSubmit || !rawSubmit->IsObject()) return submit;
    submit.label = simplejson::GetString(*rawSubmit, L"label", L"Submit");
    submit.expectedResultMarker = simplejson::GetString(*rawSubmit, L"expected_result_marker");
    submit.allowSubmit = simplejson::GetBool(*rawSubmit, L"allow_submit", false);
    submit.postSubmitVerificationRequired = simplejson::GetBool(*rawSubmit, L"post_submit_verification_required", true);
    return submit;
}

BrowserWorkflowFormSpec ParseFormSpec(const simplejson::Value& root) {
    BrowserWorkflowFormSpec formSpec;
    const simplejson::Value* form = simplejson::Find(root, L"form_spec");
    if (!form || !form->IsObject()) return formSpec;
    formSpec.rawJson = JsonValueToString(*form);
    formSpec.fields = ParseFields(*form);
    formSpec.submit = ParseSubmit(*form);
    return formSpec;
}

std::vector<std::wstring> ContextStringArray(const std::wstring& expectedContextJson, const std::wstring& key) {
    simplejson::ParseResult parsed = simplejson::Parse(expectedContextJson);
    if (!parsed.ok || !parsed.root.IsObject()) return {};
    return simplejson::GetStringArray(parsed.root, key);
}

bool IsBackendAutomationText(const std::wstring& value) {
    return ContainsInsensitive(value, L"dom") ||
           ContainsInsensitive(value, L"javascript") ||
           ContainsInsensitive(value, L"js") ||
           ContainsInsensitive(value, L"webdriver") ||
           ContainsInsensitive(value, L"cdp") ||
           ContainsInsensitive(value, L"playwright") ||
           ContainsInsensitive(value, L"selenium");
}

bool UrlIsLocalSafe(const std::wstring& url) {
    return StartsWithInsensitive(url, L"file://") ||
           StartsWithInsensitive(url, L"http://localhost") ||
           StartsWithInsensitive(url, L"https://localhost") ||
           StartsWithInsensitive(url, L"http://127.0.0.1") ||
           StartsWithInsensitive(url, L"https://127.0.0.1") ||
           StartsWithInsensitive(url, L"D:\\testrepo") ||
           StartsWithInsensitive(url, L"D:/testrepo");
}

bool AllowedPrefixShapeOk(const std::wstring& prefix, const std::wstring& risk) {
    if (prefix.empty()) return false;
    if (StartsWithInsensitive(prefix, L"file://") ||
        StartsWithInsensitive(prefix, L"http://localhost") ||
        StartsWithInsensitive(prefix, L"https://localhost") ||
        StartsWithInsensitive(prefix, L"http://127.0.0.1") ||
        StartsWithInsensitive(prefix, L"https://127.0.0.1") ||
        StartsWithInsensitive(prefix, L"D:\\testrepo") ||
        StartsWithInsensitive(prefix, L"D:/testrepo")) {
        return true;
    }
    return risk == L"READ_ONLY" && (StartsWithInsensitive(prefix, L"http://") || StartsWithInsensitive(prefix, L"https://"));
}

}  // namespace

bool BrowserWorkflowTypeSupported(const std::wstring& workflowType) {
    return workflowType == L"browser_open_page" ||
           workflowType == L"browser_read_page" ||
           workflowType == L"browser_scroll_page" ||
           workflowType == L"browser_locate_text" ||
           workflowType == L"browser_fill_form" ||
           workflowType == L"browser_submit_form" ||
           workflowType == L"browser_wrong_page_recovery" ||
           workflowType == L"browser_active_protection_stop" ||
           workflowType == L"browser_credential_required_stop";
}

bool BrowserWorkflowTypeIsSubmit(const std::wstring& workflowType) {
    return workflowType == L"browser_submit_form";
}

bool BrowserWorkflowTypeIsBlockedStop(const std::wstring& workflowType) {
    return workflowType == L"browser_active_protection_stop" || workflowType == L"browser_credential_required_stop";
}

bool BrowserWorkflowTypeIsReadOnly(const std::wstring& workflowType) {
    return workflowType == L"browser_open_page" ||
           workflowType == L"browser_read_page" ||
           workflowType == L"browser_scroll_page" ||
           workflowType == L"browser_locate_text" ||
           workflowType == L"browser_wrong_page_recovery";
}

std::wstring BrowserWorkflowRiskForType(const std::wstring& workflowType, const std::wstring& requestedRisk, const std::wstring& url) {
    std::wstring risk = Lower(requestedRisk);
    if (risk == L"read_only" || risk == L"read-only" || risk == L"readonly") return L"READ_ONLY";
    if (risk == L"low_risk" || risk == L"low-risk" || risk == L"low") return L"LOW_RISK";
    if (risk == L"reversible_draft" || risk == L"reversible-draft" || risk == L"draft") return L"REVERSIBLE_DRAFT";
    if (risk == L"real_commit" || risk == L"real-commit") return L"REAL_COMMIT";
    if (risk == L"active_protection_blocked") return L"ACTIVE_PROTECTION_BLOCKED";
    if (risk == L"credential_required_blocked") return L"CREDENTIAL_REQUIRED_BLOCKED";
    if (workflowType == L"browser_active_protection_stop") return L"ACTIVE_PROTECTION_BLOCKED";
    if (workflowType == L"browser_credential_required_stop") return L"CREDENTIAL_REQUIRED_BLOCKED";
    if (BrowserWorkflowTypeIsReadOnly(workflowType)) return L"READ_ONLY";
    return UrlIsLocalSafe(url) ? L"LOW_RISK" : L"REAL_COMMIT";
}

bool BrowserWorkflowUrlAllowedByPrefix(const std::wstring& url, const std::wstring& allowedUrlPrefix) {
    if (url.empty() || allowedUrlPrefix.empty()) return false;
    return StartsWithInsensitive(url, allowedUrlPrefix);
}

std::wstring BrowserWorkflowDefaultAllowedOrigin(const std::wstring& url) {
    if (StartsWithInsensitive(url, L"file://")) return L"file://";
    if (StartsWithInsensitive(url, L"http://localhost")) return L"http://localhost";
    if (StartsWithInsensitive(url, L"https://localhost")) return L"https://localhost";
    if (StartsWithInsensitive(url, L"http://127.0.0.1")) return L"http://127.0.0.1";
    if (StartsWithInsensitive(url, L"https://127.0.0.1")) return L"https://127.0.0.1";
    size_t scheme = url.find(L"://");
    if (scheme == std::wstring::npos) return L"";
    size_t hostEnd = url.find(L"/", scheme + 3);
    return hostEnd == std::wstring::npos ? url : url.substr(0, hostEnd);
}

BrowserWorkflowSchemaResult ParseBrowserWorkflowSpecJson(const std::wstring& json) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return Fail(L"COMPILE_SCHEMA_INVALID", L"BrowserWorkflow JSON is malformed or not an object.");
    }

    const simplejson::Value& root = parsed.root;
    BrowserWorkflowSpec spec;
    spec.workflowId = simplejson::GetString(root, L"workflow_id");
    spec.taskId = simplejson::GetString(root, L"task_id");
    spec.workflowType = simplejson::GetString(root, L"workflow_type");
    spec.url = simplejson::GetString(root, L"url");
    spec.browser = simplejson::GetString(root, L"browser", L"auto");
    spec.expectedTitlePattern = simplejson::GetString(root, L"expected_title_pattern");
    spec.expectedUrlPattern = simplejson::GetString(root, L"expected_url_pattern");
    spec.requiredMarkers = simplejson::GetStringArray(root, L"required_markers");
    spec.wrongPagePatterns = simplejson::GetStringArray(root, L"wrong_page_patterns");
    spec.activeProtectionPatterns = simplejson::GetStringArray(root, L"active_protection_patterns");
    spec.credentialRequiredPatterns = simplejson::GetStringArray(root, L"credential_required_patterns");
    spec.allowedOrigin = simplejson::GetString(root, L"allowed_origin");
    spec.allowedUrlPrefix = simplejson::GetString(root, L"allowed_url_prefix");
    spec.formSpec = ParseFormSpec(root);
    spec.submitPolicyJson = ObjectJsonOrEmpty(root, L"submit_policy");
    spec.expectedContextJson = ObjectJsonOrEmpty(root, L"expected_context");
    spec.verificationHintJson = ObjectJsonOrEmpty(root, L"verification_hint");
    spec.recoveryPolicyJson = ObjectJsonOrEmpty(root, L"recovery_policy");
    spec.stopPolicyJson = ObjectJsonOrEmpty(root, L"stop_policy");
    spec.sessionPolicyJson = ObjectJsonOrEmpty(root, L"session_policy");
    spec.evidencePolicyJson = ObjectJsonOrEmpty(root, L"evidence_policy");
    spec.requestedActionBackend = simplejson::GetString(root, L"requested_action_backend");
    if (spec.requestedActionBackend.empty()) spec.requestedActionBackend = simplejson::GetString(root, L"action_backend");
    spec.verificationTargetText = simplejson::GetString(root, L"verification_target_text");
    spec.riskLevel = BrowserWorkflowRiskForType(spec.workflowType, simplejson::GetString(root, L"risk_level"), spec.url);
    if (spec.requiredMarkers.empty()) spec.requiredMarkers = ContextStringArray(spec.expectedContextJson, L"required_markers");
    if (spec.wrongPagePatterns.empty()) spec.wrongPagePatterns = ContextStringArray(spec.expectedContextJson, L"wrong_page_patterns");
    if (spec.activeProtectionPatterns.empty()) spec.activeProtectionPatterns = ContextStringArray(spec.expectedContextJson, L"active_protection_patterns");
    if (spec.credentialRequiredPatterns.empty()) spec.credentialRequiredPatterns = ContextStringArray(spec.expectedContextJson, L"credential_required_patterns");

    if (spec.workflowId.empty()) spec.workflowId = L"browser-workflow-" + std::to_wstring(RuntimeSessionNowEpochMs());
    if (spec.taskId.empty()) spec.taskId = L"browser-task-" + spec.workflowId;
    if (spec.allowedOrigin.empty()) spec.allowedOrigin = BrowserWorkflowDefaultAllowedOrigin(spec.url);

    if (!BrowserWorkflowTypeSupported(spec.workflowType)) {
        return Fail(L"COMPILE_SCHEMA_INVALID", L"Unsupported Browser workflow_type.", spec);
    }
    if (spec.url.empty()) {
        return Fail(L"COMPILE_URL_MISSING", L"Browser workflow requires url.", spec);
    }
    if (EmptyOrWhitespace(spec.expectedContextJson)) {
        return Fail(L"COMPILE_MISSING_EXPECTED_CONTEXT", L"Browser workflow requires expected_context.", spec);
    }
    if (EmptyOrWhitespace(spec.verificationHintJson)) {
        return Fail(L"COMPILE_MISSING_VERIFICATION_HINT", L"Browser workflow requires verification_hint.", spec);
    }
    if (spec.allowedUrlPrefix.empty()) {
        return Fail(L"COMPILE_ALLOWED_URL_PREFIX_MISSING", L"Browser workflow requires explicit allowed_url_prefix.", spec);
    }
    if (!AllowedPrefixShapeOk(spec.allowedUrlPrefix, spec.riskLevel)) {
        return Fail(L"COMPILE_ALLOWED_URL_PREFIX_UNSAFE", L"allowed_url_prefix must be local-safe or read-only external.", spec);
    }
    if (!BrowserWorkflowUrlAllowedByPrefix(spec.url, spec.allowedUrlPrefix)) {
        return Fail(L"STOP_BROWSER_SCOPE_VIOLATION", L"Browser workflow url is outside allowed_url_prefix.", spec);
    }
    if (IsBackendAutomationText(spec.requestedActionBackend)) {
        return Fail(L"COMPILE_BROWSER_BACKEND_AUTOMATION_REJECTED", L"Browser workflow must not request DOM/JS/WebDriver/CDP/Playwright/Selenium backend automation.", spec);
    }
    if (BrowserWorkflowTypeIsSubmit(spec.workflowType) && EmptyOrWhitespace(spec.submitPolicyJson)) {
        return Fail(L"COMPILE_SUBMIT_POLICY_MISSING", L"Submit Browser workflow requires submit_policy.", spec);
    }
    if ((spec.workflowType == L"browser_fill_form" || spec.workflowType == L"browser_submit_form") && spec.formSpec.fields.empty() && spec.workflowType == L"browser_fill_form") {
        return Fail(L"COMPILE_FORM_SPEC_MISSING", L"browser_fill_form requires form_spec.fields.", spec);
    }
    if (!BrowserWorkflowTypeIsReadOnly(spec.workflowType) && !BrowserWorkflowTypeIsBlockedStop(spec.workflowType) && !UrlIsLocalSafe(spec.url) && spec.riskLevel != L"REAL_COMMIT") {
        return Fail(L"COMPILE_EXTERNAL_FORM_RISK_INVALID", L"External non-readonly form workflow must use REAL_COMMIT risk and is not a main gate action.", spec);
    }

    spec.recoveryPolicyJson = spec.recoveryPolicyJson.empty()
        ? L"{\"recovery_allowed\":true,\"recovery_scope\":\"browser_allowed_url_prefix\",\"recovery_target\":\"expected_url\",\"max_recovery_attempts\":1,\"resume_from_checkpoint_allowed\":true,\"replay_from_checkpoint_allowed\":true,\"stop_if_recovery_fails\":true}"
        : spec.recoveryPolicyJson;
    spec.stopPolicyJson = spec.stopPolicyJson.empty()
        ? L"{\"stop_on_wrong_context\":true,\"stop_on_wrong_field\":true,\"stop_on_target_stale\":true,\"stop_on_target_not_unique\":true,\"stop_on_active_protection\":true,\"stop_on_credential_required\":true,\"stop_on_unverified_result\":true,\"stop_on_runtime_guard_failure\":true}"
        : spec.stopPolicyJson;
    spec.sessionPolicyJson = spec.sessionPolicyJson.empty()
        ? L"{\"session_required\":true,\"session_reuse_allowed\":true,\"force_reobserve_before_action\":true,\"cache_policy\":\"force_reobserve\",\"locator_cache_allowed\":false}"
        : spec.sessionPolicyJson;
    spec.evidencePolicyJson = spec.evidencePolicyJson.empty()
        ? L"{\"raw_evidence_required\":true,\"verifier_required\":true,\"gate_required\":true,\"mouse_evidence_required\":true,\"latency_required\":true}"
        : spec.evidencePolicyJson;

    BrowserWorkflowSchemaResult result;
    result.ok = true;
    result.spec = spec;
    result.diagnosticsJson = L"{\"schema_version\":\"6.8.0.browser_workflow.schema_diagnostics\",\"validation_ok\":true,\"workflow_id\":"
        + simplejson::Quote(spec.workflowId) + L",\"workflow_type\":" + simplejson::Quote(spec.workflowType)
        + L",\"allowed_url_prefix\":" + simplejson::Quote(spec.allowedUrlPrefix) + L"}";
    return result;
}

BrowserWorkflowSchemaResult ParseBrowserWorkflowSpecFile(const std::wstring& inputPath) {
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        return Fail(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read Browser workflow file: " + read.error);
    }
    return ParseBrowserWorkflowSpecJson(read.content);
}
