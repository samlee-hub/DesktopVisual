#include "CommunicationWorkflow.h"

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
    return L"{\"schema_version\":\"6.9.0.communication_workflow.schema_diagnostics\""
        L",\"validation_ok\":false"
        L",\"error_code\":" + simplejson::Quote(code) +
        L",\"error_message\":" + simplejson::Quote(message) + L"}";
}

CommunicationWorkflowSchemaResult Fail(
    const std::wstring& code,
    const std::wstring& message,
    CommunicationWorkflowSpec spec = CommunicationWorkflowSpec{}) {
    CommunicationWorkflowSchemaResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.spec = spec;
    result.diagnosticsJson = FailureDiagnostics(code, message);
    return result;
}

bool ExternalCommunicationBackendText(const std::wstring& value) {
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
           ContainsInsensitive(value, L"dom") ||
           ContainsInsensitive(value, L"javascript") ||
           ContainsInsensitive(value, L"webdriver") ||
           ContainsInsensitive(value, L"cdp") ||
           ContainsInsensitive(value, L"playwright") ||
           ContainsInsensitive(value, L"selenium");
}

bool SendRequested(const simplejson::Value& root) {
    return simplejson::GetBool(root, L"send", false) ||
           simplejson::GetBool(root, L"allow_send", false) ||
           simplejson::GetBool(root, L"send_attempted", false) ||
           simplejson::GetBool(root, L"mark_sent", false);
}

}  // namespace

bool CommunicationWorkflowTypeSupported(const std::wstring& type) {
    return type == L"email" || type == L"message" || type == L"draft";
}

std::wstring CommunicationWorkflowRuntimeActionForType(const std::wstring& type) {
    if (type == L"email") return L"communication_create_email";
    if (type == L"message") return L"communication_create_message";
    if (type == L"draft") return L"communication_create_draft";
    return L"";
}

std::wstring CommunicationWorkflowStepTypeForType(const std::wstring& type) {
    if (type == L"email") return L"communication_email_create";
    if (type == L"message") return L"communication_message_create";
    if (type == L"draft") return L"communication_draft_create";
    return L"communication_create";
}

std::wstring CommunicationWorkflowNormalizeRisk(const std::wstring& requestedRisk) {
    std::wstring risk = Lower(requestedRisk);
    if (risk == L"read_only" || risk == L"read-only" || risk == L"readonly") return L"READ_ONLY";
    if (risk == L"low_risk" || risk == L"low-risk" || risk == L"low") return L"LOW_RISK";
    if (risk == L"reversible_draft" || risk == L"reversible-draft" || risk == L"draft" || risk == L"medium") return L"REVERSIBLE_DRAFT";
    if (risk == L"real_commit" || risk == L"real-commit" || risk == L"commit" || risk == L"high") return L"REAL_COMMIT";
    if (risk == L"destructive" || risk == L"delete") return L"DESTRUCTIVE";
    return L"";
}

CommunicationWorkflowSchemaResult ParseCommunicationWorkflowSpecJson(const std::wstring& json) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return Fail(L"COMMUNICATION_SCHEMA_INVALID", L"CommunicationWorkflow JSON is malformed or not an object.");
    }

    const simplejson::Value& root = parsed.root;
    CommunicationWorkflowSpec spec;
    spec.workflowId = simplejson::GetString(root, L"workflow_id");
    spec.taskId = simplejson::GetString(root, L"task_id");
    spec.type = Lower(simplejson::GetString(root, L"type"));
    spec.recipient = simplejson::GetString(root, L"recipient");
    spec.subject = simplejson::GetString(root, L"subject");
    spec.body = simplejson::GetString(root, L"body");
    spec.contextSource = simplejson::GetString(root, L"context_source");
    spec.expectedContextJson = ObjectJsonOrEmpty(root, L"expected_context");
    spec.verificationHintJson = ObjectJsonOrEmpty(root, L"verification_hint");
    spec.riskLevel = CommunicationWorkflowNormalizeRisk(simplejson::GetString(root, L"risk_level"));
    spec.confirmationPolicyJson = ObjectJsonOrEmpty(root, L"confirmation_policy");
    spec.stopPolicyJson = ObjectJsonOrEmpty(root, L"stop_policy");
    spec.recoveryPolicyJson = ObjectJsonOrEmpty(root, L"recovery_policy");
    spec.sessionPolicyJson = ObjectJsonOrEmpty(root, L"session_policy");
    spec.evidencePolicyJson = ObjectJsonOrEmpty(root, L"evidence_policy");
    spec.requestedActionBackend = simplejson::GetString(root, L"requested_action_backend");
    if (spec.requestedActionBackend.empty()) spec.requestedActionBackend = simplejson::GetString(root, L"action_backend");
    spec.fixtureRoot = simplejson::GetString(root, L"fixture_root");

    if (!CommunicationWorkflowTypeSupported(spec.type)) {
        return Fail(L"COMMUNICATION_TYPE_UNSUPPORTED", L"CommunicationWorkflow type must be email, message, or draft.", spec);
    }
    if (EmptyOrWhitespace(spec.workflowId)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_WORKFLOW_ID", L"CommunicationWorkflow requires workflow_id.", spec);
    if (EmptyOrWhitespace(spec.taskId)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_TASK_ID", L"CommunicationWorkflow requires task_id.", spec);
    if (EmptyOrWhitespace(spec.recipient)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_RECIPIENT", L"CommunicationWorkflow requires recipient.", spec);
    if (EmptyOrWhitespace(spec.subject)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_SUBJECT", L"CommunicationWorkflow requires subject.", spec);
    if (EmptyOrWhitespace(spec.body)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_BODY", L"CommunicationWorkflow requires body.", spec);
    if (EmptyOrWhitespace(spec.contextSource)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_CONTEXT_SOURCE", L"CommunicationWorkflow requires context_source.", spec);
    if (EmptyOrWhitespace(spec.expectedContextJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_EXPECTED_CONTEXT", L"CommunicationWorkflow requires expected_context.", spec);
    if (EmptyOrWhitespace(spec.verificationHintJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_VERIFICATION_HINT", L"CommunicationWorkflow requires verification_hint.", spec);
    if (EmptyOrWhitespace(spec.riskLevel)) return Fail(L"COMMUNICATION_RISK_LEVEL_INVALID", L"CommunicationWorkflow requires supported risk_level.", spec);
    if (spec.riskLevel == L"REAL_COMMIT" || spec.riskLevel == L"DESTRUCTIVE") {
        return Fail(L"COMMUNICATION_REAL_SEND_RISK_REJECTED", L"CommunicationWorkflow create-only workflows must not request REAL_COMMIT or DESTRUCTIVE risk.", spec);
    }
    if (EmptyOrWhitespace(spec.confirmationPolicyJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_CONFIRMATION_POLICY", L"CommunicationWorkflow requires confirmation_policy.", spec);
    if (EmptyOrWhitespace(spec.stopPolicyJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_STOP_POLICY", L"CommunicationWorkflow requires stop_policy.", spec);
    if (EmptyOrWhitespace(spec.recoveryPolicyJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_RECOVERY_POLICY", L"CommunicationWorkflow requires recovery_policy.", spec);
    if (EmptyOrWhitespace(spec.sessionPolicyJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_SESSION_POLICY", L"CommunicationWorkflow requires session_policy.", spec);
    if (EmptyOrWhitespace(spec.evidencePolicyJson)) return Fail(L"COMMUNICATION_SCHEMA_MISSING_EVIDENCE_POLICY", L"CommunicationWorkflow requires evidence_policy.", spec);
    if (ExternalCommunicationBackendText(spec.requestedActionBackend) || SendRequested(root)) {
        return Fail(L"COMMUNICATION_EXTERNAL_API_REJECTED", L"CommunicationWorkflow must not request send, external communication APIs, provider SDKs, or browser automation.", spec);
    }

    CommunicationWorkflowSchemaResult result;
    result.ok = true;
    result.spec = spec;
    result.diagnosticsJson = L"{\"schema_version\":\"6.9.0.communication_workflow.schema_diagnostics\""
        L",\"validation_ok\":true"
        L",\"workflow_id\":" + simplejson::Quote(spec.workflowId) +
        L",\"type\":" + simplejson::Quote(spec.type) +
        L",\"external_api_allowed\":false"
        L",\"send_allowed\":false}";
    return result;
}

CommunicationWorkflowSchemaResult ParseCommunicationWorkflowSpecFile(const std::wstring& inputPath) {
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        return Fail(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read Communication workflow file: " + read.error);
    }
    return ParseCommunicationWorkflowSpecJson(read.content);
}
