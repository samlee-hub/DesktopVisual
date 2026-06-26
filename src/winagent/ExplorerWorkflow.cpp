#include "ExplorerWorkflow.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "RuntimeSession.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

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
    return L"{\"schema_version\":\"6.7.0.explorer_workflow.schema_diagnostics\""
        L",\"validation_ok\":false"
        L",\"error_code\":" + simplejson::Quote(code) +
        L",\"error_message\":" + simplejson::Quote(message) + L"}";
}

ExplorerWorkflowSchemaResult Fail(const std::wstring& code, const std::wstring& message, ExplorerWorkflowSpec spec = ExplorerWorkflowSpec{}) {
    ExplorerWorkflowSchemaResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.spec = spec;
    result.diagnosticsJson = FailureDiagnostics(code, message);
    return result;
}

std::wstring FieldOr(const simplejson::Value& root, const std::vector<std::wstring>& fields) {
    for (const auto& field : fields) {
        std::wstring value = simplejson::GetString(root, field);
        if (!value.empty()) return value;
    }
    return L"";
}

bool NeedsPathScope(const std::wstring& workflowType) {
    return workflowType == L"explorer_open_path" ||
           workflowType == L"explorer_open_file" ||
           workflowType == L"explorer_rename_file" ||
           workflowType == L"explorer_move_file" ||
           workflowType == L"explorer_delete_file" ||
           workflowType == L"explorer_context_menu_action" ||
           workflowType == L"explorer_scroll_and_locate";
}

bool PathMaybeScoped(const std::wstring& path) {
    if (path.empty()) return true;
    if (path.find(L":") == std::wstring::npos && path.find(L"\\") == std::wstring::npos && path.find(L"/") == std::wstring::npos) {
        return true;
    }
    return false;
}

std::wstring EnsureObjectDefault(const std::wstring& json, const std::wstring& defaultJson) {
    return json.empty() ? defaultJson : json;
}

}  // namespace

std::wstring ExplorerWorkflowDefaultAllowedRoot() {
    return L"D:\\testrepo";
}

std::wstring ExplorerWorkflowNormalizePath(const std::wstring& path) {
    if (path.empty()) return L"";
    DWORD needed = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (needed == 0) return path;
    std::wstring buffer(needed + 1, L'\0');
    DWORD written = GetFullPathNameW(path.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
    if (written == 0) return path;
    buffer.resize(written);
    while (buffer.size() > 3 && (buffer.back() == L'\\' || buffer.back() == L'/')) buffer.pop_back();
    return buffer;
}

bool ExplorerWorkflowPathWithinRoot(const std::wstring& path, const std::wstring& allowedRoot) {
    if (path.empty()) return true;
    if (PathMaybeScoped(path)) return true;
    std::wstring fullPath = Lower(ExplorerWorkflowNormalizePath(path));
    std::wstring root = Lower(ExplorerWorkflowNormalizePath(allowedRoot.empty() ? ExplorerWorkflowDefaultAllowedRoot() : allowedRoot));
    if (fullPath == root) return true;
    if (root.empty() || fullPath.size() <= root.size()) return false;
    wchar_t next = fullPath[root.size()];
    return fullPath.rfind(root, 0) == 0 && (next == L'\\' || next == L'/');
}

std::wstring ExplorerWorkflowRiskForType(const std::wstring& workflowType, const std::wstring& requestedRisk) {
    std::wstring risk = Lower(requestedRisk);
    if (risk == L"read_only" || risk == L"read-only" || risk == L"readonly") return L"READ_ONLY";
    if (risk == L"low_risk" || risk == L"low-risk" || risk == L"low") return L"LOW_RISK";
    if (risk == L"reversible_draft" || risk == L"reversible-draft" || risk == L"draft") return L"REVERSIBLE_DRAFT";
    if (risk == L"destructive" || risk == L"delete") return L"DESTRUCTIVE";
    if (risk == L"real_commit" || risk == L"real-commit") return L"REAL_COMMIT";

    if (workflowType == L"explorer_delete_file") return L"DESTRUCTIVE";
    if (workflowType == L"explorer_rename_file" || workflowType == L"explorer_move_file" || workflowType == L"explorer_context_menu_action") return L"REVERSIBLE_DRAFT";
    if (workflowType == L"explorer_scroll_and_locate") return L"LOW_RISK";
    return L"READ_ONLY";
}

bool ExplorerWorkflowTypeSupported(const std::wstring& workflowType) {
    return workflowType == L"explorer_open_path" ||
           workflowType == L"explorer_open_file" ||
           workflowType == L"explorer_rename_file" ||
           workflowType == L"explorer_move_file" ||
           workflowType == L"explorer_delete_file" ||
           workflowType == L"explorer_context_menu_action" ||
           workflowType == L"explorer_scroll_and_locate";
}

bool ExplorerWorkflowTypeIsDestructive(const std::wstring& workflowType) {
    return workflowType == L"explorer_delete_file";
}

bool ExplorerWorkflowTypeIsReversibleDraft(const std::wstring& workflowType) {
    return workflowType == L"explorer_rename_file" ||
           workflowType == L"explorer_move_file" ||
           workflowType == L"explorer_context_menu_action";
}

std::wstring ExplorerWorkflowJsonStringArray1(const std::wstring& value) {
    if (value.empty()) return L"[]";
    return L"[" + simplejson::Quote(value) + L"]";
}

ExplorerWorkflowSchemaResult ParseExplorerWorkflowSpecJson(const std::wstring& json) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return Fail(L"COMPILE_SCHEMA_INVALID", L"ExplorerWorkflow JSON is malformed or not an object.");
    }

    const simplejson::Value& root = parsed.root;
    ExplorerWorkflowSpec spec;
    spec.workflowId = simplejson::GetString(root, L"workflow_id");
    spec.taskId = simplejson::GetString(root, L"task_id");
    spec.workflowType = simplejson::GetString(root, L"workflow_type");
    spec.sourcePath = FieldOr(root, {L"source_path", L"path"});
    spec.targetPath = simplejson::GetString(root, L"target_path");
    spec.destinationPath = simplejson::GetString(root, L"destination_path");
    spec.expectedFolder = simplejson::GetString(root, L"expected_folder");
    spec.expectedFilename = simplejson::GetString(root, L"expected_filename");
    spec.expectedExtension = simplejson::GetString(root, L"expected_extension");
    spec.confirmationRequired = simplejson::GetBool(root, L"confirmation_required", false);
    spec.confirmationToken = simplejson::GetString(root, L"confirmation_token");
    const simplejson::Value* allowedRootValue = simplejson::Find(root, L"allowed_root");
    if (!allowedRootValue || !allowedRootValue->IsString() || EmptyOrWhitespace(allowedRootValue->stringValue)) {
        return Fail(L"COMPILE_ALLOWED_ROOT_MISSING", L"Explorer workflow requires explicit allowed_root.", spec);
    }
    spec.allowedRoot = simplejson::GetString(root, L"allowed_root", ExplorerWorkflowDefaultAllowedRoot());
    spec.riskLevel = ExplorerWorkflowRiskForType(spec.workflowType, simplejson::GetString(root, L"risk_level"));
    spec.expectedContextJson = ObjectJsonOrEmpty(root, L"expected_context");
    spec.verificationHintJson = ObjectJsonOrEmpty(root, L"verification_hint");
    spec.recoveryPolicyJson = ObjectJsonOrEmpty(root, L"recovery_policy");
    spec.stopPolicyJson = ObjectJsonOrEmpty(root, L"stop_policy");
    spec.sessionPolicyJson = ObjectJsonOrEmpty(root, L"session_policy");
    spec.evidencePolicyJson = ObjectJsonOrEmpty(root, L"evidence_policy");
    spec.contextMenuAction = simplejson::GetString(root, L"context_menu_action", L"rename");

    if (spec.workflowId.empty()) spec.workflowId = L"explorer-workflow-" + std::to_wstring(RuntimeSessionNowEpochMs());
    if (spec.taskId.empty()) spec.taskId = L"explorer-task-" + spec.workflowId;
    if (spec.allowedRoot.empty()) spec.allowedRoot = ExplorerWorkflowDefaultAllowedRoot();

    if (!ExplorerWorkflowTypeSupported(spec.workflowType)) {
        return Fail(L"COMPILE_SCHEMA_INVALID", L"Unsupported Explorer workflow_type.", spec);
    }
    if (EmptyOrWhitespace(spec.expectedContextJson)) {
        return Fail(L"COMPILE_MISSING_EXPECTED_CONTEXT", L"Explorer workflow requires expected_context.", spec);
    }
    if (EmptyOrWhitespace(spec.verificationHintJson)) {
        return Fail(L"COMPILE_MISSING_VERIFICATION_HINT", L"Explorer workflow requires verification_hint.", spec);
    }
    if (EmptyOrWhitespace(spec.stopPolicyJson)) {
        return Fail(L"COMPILE_STOP_POLICY_MISSING", L"Explorer workflow requires stop_policy.", spec);
    }
    if (NeedsPathScope(spec.workflowType)) {
        if (!ExplorerWorkflowPathWithinRoot(spec.sourcePath, spec.allowedRoot) ||
            !ExplorerWorkflowPathWithinRoot(spec.targetPath, spec.allowedRoot) ||
            !ExplorerWorkflowPathWithinRoot(spec.destinationPath, spec.allowedRoot) ||
            !ExplorerWorkflowPathWithinRoot(spec.expectedFolder, spec.allowedRoot)) {
            return Fail(L"STOP_EXPLORER_SCOPE_VIOLATION", L"Explorer workflow path is outside allowed_root.", spec);
        }
    }
    if (spec.workflowType == L"explorer_delete_file") {
        if (spec.riskLevel != L"DESTRUCTIVE") {
            return Fail(L"COMPILE_RISK_POLICY_MISSING", L"explorer_delete_file must use risk_level=DESTRUCTIVE.", spec);
        }
        if (!spec.confirmationRequired) {
            return Fail(L"COMPILE_CONFIRMATION_REQUIRED", L"explorer_delete_file requires confirmation_required=true.", spec);
        }
    }
    if (ExplorerWorkflowTypeIsReversibleDraft(spec.workflowType) && spec.riskLevel != L"REVERSIBLE_DRAFT") {
        return Fail(L"COMPILE_RISK_POLICY_MISSING", L"rename/move/context-menu Explorer workflows must use risk_level=REVERSIBLE_DRAFT.", spec);
    }

    spec.recoveryPolicyJson = EnsureObjectDefault(spec.recoveryPolicyJson,
        L"{\"recovery_allowed\":true,\"recovery_scope\":\"explorer_allowed_root\",\"recovery_target\":\"expected_folder\",\"max_recovery_attempts\":1,\"resume_from_checkpoint_allowed\":true,\"replay_from_checkpoint_allowed\":true,\"stop_if_recovery_fails\":true}");
    spec.sessionPolicyJson = EnsureObjectDefault(spec.sessionPolicyJson,
        L"{\"session_required\":true,\"session_reuse_allowed\":true,\"force_reobserve_before_action\":true,\"cache_policy\":\"force_reobserve\",\"locator_cache_allowed\":false}");
    spec.evidencePolicyJson = EnsureObjectDefault(spec.evidencePolicyJson,
        L"{\"raw_evidence_required\":true,\"verifier_required\":true,\"gate_required\":true,\"mouse_evidence_required\":true,\"latency_required\":true}");

    ExplorerWorkflowSchemaResult result;
    result.ok = true;
    result.spec = spec;
    result.diagnosticsJson = L"{\"schema_version\":\"6.7.0.explorer_workflow.schema_diagnostics\",\"validation_ok\":true,\"workflow_id\":"
        + simplejson::Quote(spec.workflowId) + L",\"workflow_type\":" + simplejson::Quote(spec.workflowType)
        + L",\"allowed_root\":" + simplejson::Quote(spec.allowedRoot) + L"}";
    return result;
}

ExplorerWorkflowSchemaResult ParseExplorerWorkflowSpecFile(const std::wstring& inputPath) {
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        return Fail(read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, L"Could not read Explorer workflow file: " + read.error);
    }
    return ParseExplorerWorkflowSpecJson(read.content);
}
