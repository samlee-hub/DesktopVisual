#include "WorkflowTemplateSafetyBoundary.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <algorithm>
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

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool ContainsNoCase(const std::wstring& value, const std::wstring& needle) {
    return !needle.empty() && Lower(value).find(Lower(needle)) != std::wstring::npos;
}

bool StartsWithNoCase(const std::wstring& value, const std::wstring& prefix) {
    return Lower(value).rfind(Lower(prefix), 0) == 0;
}

std::wstring CmdQuote(const std::wstring& value) {
    std::wstring quoted = L"\"";
    for (wchar_t ch : value) {
        if (ch != L'"') quoted.push_back(ch);
    }
    quoted.push_back(L'"');
    return quoted;
}

std::wstring RunCommandCapture(const std::wstring& command) {
    FILE* pipe = _wpopen(command.c_str(), L"rt");
    if (!pipe) return L"";
    std::wstring output;
    wchar_t buffer[512];
    while (fgetws(buffer, static_cast<int>(std::size(buffer)), pipe)) {
        output += buffer;
    }
    _pclose(pipe);
    return output;
}

bool ToGitRelativePath(const std::wstring& absolutePath, std::wstring& relativePath) {
    std::wstring root = ValidationNormalizePath(ProjectRootPath());
    std::wstring path = ValidationNormalizePath(absolutePath);
    std::wstring lowerRoot = Lower(root);
    std::wstring lowerPath = Lower(path);
    if (lowerPath == lowerRoot) {
        relativePath = L".";
        return true;
    }
    if (lowerPath.rfind(lowerRoot + L"\\", 0) != 0) {
        return false;
    }
    relativePath = path.substr(root.size() + 1);
    std::replace(relativePath.begin(), relativePath.end(), L'\\', L'/');
    return !relativePath.empty();
}

bool GitPathTracked(const std::wstring& resolvedPath) {
    std::wstring rel;
    if (!ToGitRelativePath(resolvedPath, rel)) return false;
    std::wstring command = L"git -C " + CmdQuote(ProjectRootPath()) +
        L" ls-files --error-unmatch -- " + CmdQuote(rel) + L" 2>NUL";
    return !RunCommandCapture(command).empty();
}

bool GitDirectoryHasNoUntracked(const std::wstring& resolvedPath) {
    std::wstring rel;
    if (!ToGitRelativePath(resolvedPath, rel)) return false;
    std::wstring trackedCommand = L"git -C " + CmdQuote(ProjectRootPath()) +
        L" ls-files -- " + CmdQuote(rel) + L" 2>NUL";
    if (RunCommandCapture(trackedCommand).empty()) return false;
    std::wstring untrackedCommand = L"git -C " + CmdQuote(ProjectRootPath()) +
        L" ls-files --others --exclude-standard -- " + CmdQuote(rel) + L" 2>NUL";
    return RunCommandCapture(untrackedCommand).empty();
}

std::wstring BaseNameLower(const std::wstring& path) {
    size_t pos = path.find_last_of(L"\\/");
    std::wstring name = (pos == std::wstring::npos) ? path : path.substr(pos + 1);
    return Lower(name);
}

std::wstring ParentPath(const std::wstring& path) {
    size_t pos = path.find_last_of(L"\\/");
    if (pos == std::wstring::npos) return L"";
    return path.substr(0, pos);
}

bool HasBlockedFinalStatus(const std::wstring& text) {
    std::wstring lower = Lower(text);
    return lower.find(L"status: blocked") != std::wstring::npos ||
           lower.find(L"final status: blocked") != std::wstring::npos ||
           lower.find(L"final_status: blocked") != std::wstring::npos ||
           lower.find(L"no v6.7.0 acceptance is claimed") != std::wstring::npos ||
           lower.find(L"acceptance is blocked") != std::wstring::npos;
}

bool HasAcceptedFinalStatus(const std::wstring& text) {
    if (HasBlockedFinalStatus(text)) return false;
    std::wstring lower = Lower(text);
    return lower.find(L"final status: pass") != std::wstring::npos ||
           lower.find(L"final_status: pass") != std::wstring::npos ||
           lower.find(L"status: pass") != std::wstring::npos ||
           (lower.find(L"final state:") != std::wstring::npos && lower.find(L"accepted") != std::wstring::npos) ||
           lower.find(L"verification_ok: true") != std::wstring::npos ||
           lower.find(L"ok=true") != std::wstring::npos ||
           lower.find(L"acceptance gate: pass") != std::wstring::npos;
}

void AddViolation(std::vector<std::wstring>& violations, const std::wstring& code) {
    if (std::find(violations.begin(), violations.end(), code) == violations.end()) {
        violations.push_back(code);
    }
}

bool JsonContainsForbiddenBackend(const std::wstring& json) {
    return ContainsNoCase(json, L"webdriver") ||
           ContainsNoCase(json, L"cdp") ||
           ContainsNoCase(json, L"selenium") ||
           ContainsNoCase(json, L"playwright") ||
           ContainsNoCase(json, L"javascript") ||
           ContainsNoCase(json, L"\"js\"") ||
           ContainsNoCase(json, L"dom_selector") ||
           ContainsNoCase(json, L"document.queryselector") ||
           ContainsNoCase(json, L"execute_script");
}

bool JsonContainsUnsafeCoordinate(const std::wstring& json) {
    return ContainsNoCase(json, L"direct_coordinate") ||
           ContainsNoCase(json, L"screen_x") ||
           ContainsNoCase(json, L"screen_y") ||
           ContainsNoCase(json, L"target_center_x") ||
           ContainsNoCase(json, L"target_center_y") ||
           ContainsNoCase(json, L"coord:") ||
           (ContainsNoCase(json, L"\"x\"") && ContainsNoCase(json, L"\"y\"") && ContainsNoCase(json, L"click"));
}

bool JsonBoolFalseOrMissing(const std::wstring& json, const std::wstring& key) {
    simplejson::ParseResult parsed = simplejson::Parse(json);
    if (!parsed.ok || !parsed.root.IsObject()) return true;
    if (!simplejson::Has(parsed.root, key)) return true;
    return !simplejson::GetBool(parsed.root, key, false);
}

bool HasSensitiveCommunicationPlaintext(const WorkflowTemplateRecord& record) {
    if (Lower(record.workflowType) != L"communication") return false;
    std::wstring combined = record.parameterSchemaJson + L" " +
        record.stepContractSkeletonJson + L" " +
        record.expectedContextSchemaJson + L" " +
        record.verificationHintSchemaJson;
    if (ContainsNoCase(combined, L"plaintext_body") ||
        ContainsNoCase(combined, L"full_body") ||
        ContainsNoCase(combined, L"message_body")) {
        return true;
    }
    if (ContainsNoCase(combined, L"recipient@example") ||
        ContainsNoCase(combined, L"@gmail.") ||
        ContainsNoCase(combined, L"@qq.") ||
        ContainsNoCase(combined, L"Sensitive draft body")) {
        return true;
    }
    return !record.redactionApplied;
}

std::wstring ViolationsJson(const std::vector<std::wstring>& violations) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < violations.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(violations[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring BlockedReason(const std::vector<std::wstring>& violations) {
    static const std::vector<std::wstring> priority = {
        L"FAIL_UNTRUSTED_TEMPLATE_SOURCE",
        L"FAIL_TEMPLATE_SOURCE_MISSING",
        L"FAIL_TEMPLATE_UNSAFE_COORDINATE",
        L"FAIL_TEMPLATE_BACKEND_BYPASS",
        L"FAIL_TEMPLATE_SENSITIVE_CONTENT",
        L"FAIL_TEMPLATE_VALIDATOR_BYPASS",
        L"FAIL_TEMPLATE_RUNTIME_BYPASS",
        L"FAIL_TEMPLATE_VERIFIER_BYPASS",
        L"BLOCK_MEMORY_TEMPLATE_EXECUTION_INFLUENCE"
    };
    for (const auto& code : priority) {
        if (std::find(violations.begin(), violations.end(), code) != violations.end()) return code;
    }
    return violations.empty() ? L"" : violations.front();
}

WorkflowTemplateSafetyResult BuildResult(const WorkflowTemplateRecord& record, const std::vector<std::wstring>& violations) {
    WorkflowTemplateSafetyResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = BlockedReason(violations);
    result.violations = violations;
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.workflow_template_safety_boundary\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"template_id\":" << simplejson::Quote(record.templateId)
         << L",\"template_status\":" << simplejson::Quote(record.templateStatus)
         << L",\"workflow_type\":" << simplejson::Quote(record.workflowType)
         << L",\"violations\":" << ViolationsJson(violations)
         << L",\"direct_execution_allowed\":false"
         << L",\"step_contract_validator_required\":true"
         << L",\"runtime_session_required\":true"
         << L",\"step_verifier_required\":true"
         << L",\"memory_execution_influence\":false"
         << L",\"parallel_real_ui_allowed\":false"
         << L"}";
    result.jsonReport = json.str();
    return result;
}

bool IsAllowedExtractorSourcePath(const std::wstring& sourceRef) {
    std::wstring slash = sourceRef;
    std::replace(slash.begin(), slash.end(), L'\\', L'/');
    std::wstring lower = Lower(slash);
    return lower.find(L"artifacts/dev6.7.0_explorer_agent_workflows_rerun") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.7.0_explorer_agent_workflows") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.8.0_browser_and_web_form_agent_workflows") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.9.0_communication_workflow") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.10.0_experience_memory_failure_attribution") != std::wstring::npos ||
           lower.find(L"artifacts/dev6.9.0_system_stabilization") != std::wstring::npos;
}

}  // namespace

bool WorkflowTemplateSourceTrusted(const std::wstring& sourceRef) {
    std::wstring resolved = WorkflowTemplateResolveRef(sourceRef);
    if (resolved.empty()) return false;
    if (ContainsNoCase(resolved, L"stash") ||
        ContainsNoCase(resolved, L"dirty") ||
        ContainsNoCase(resolved, L"untracked")) {
        return false;
    }
    if (!ValidationFileExists(resolved) && !ValidationDirectoryExists(resolved)) {
        return false;
    }

    if (ValidationDirectoryExists(resolved)) {
        if (!GitDirectoryHasNoUntracked(resolved)) return false;
        std::wstring indexPath = ValidationJoinPath(resolved, L"evidence_index.md");
        std::wstring finalPath = ValidationJoinPath(resolved, L"final_status_report.md");
        if (!ValidationFileExists(indexPath) || !ValidationFileExists(finalPath)) return false;
        if (!GitPathTracked(indexPath) || !GitPathTracked(finalPath)) return false;
        std::wstring finalText;
        std::wstring error;
        if (!ReadValidationTextFile(finalPath, finalText, error)) return false;
        return HasAcceptedFinalStatus(finalText);
    }

    if (!GitPathTracked(resolved)) return false;
    std::wstring name = BaseNameLower(resolved);
    if (name == L"evidence_index.md") {
        std::wstring finalPath = ValidationJoinPath(ParentPath(resolved), L"final_status_report.md");
        if (!ValidationFileExists(finalPath) || !GitPathTracked(finalPath)) return false;
        std::wstring finalText;
        std::wstring error;
        if (!ReadValidationTextFile(finalPath, finalText, error)) return false;
        return HasAcceptedFinalStatus(finalText);
    }

    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(resolved, text, error)) return false;
    if (ContainsNoCase(text, L"RAW_COMPLETED_UNVERIFIED") &&
        !ContainsNoCase(text, L"verifier") &&
        !ContainsNoCase(text, L"acceptance gate")) {
        return false;
    }
    return HasAcceptedFinalStatus(text) ||
           (!HasBlockedFinalStatus(text) && ContainsNoCase(text, L"accepted"));
}

WorkflowTemplateSafetyResult CheckWorkflowTemplateSafety(const WorkflowTemplateRecord& record) {
    std::vector<std::wstring> violations;
    if (record.sourceEvidenceRefs.empty()) {
        AddViolation(violations, L"FAIL_TEMPLATE_SOURCE_MISSING");
    }
    for (const auto& source : record.sourceEvidenceRefs) {
        if (!WorkflowTemplateSourceTrusted(source)) {
            AddViolation(violations, ValidationFileExists(source) || ValidationDirectoryExists(source)
                ? L"FAIL_UNTRUSTED_TEMPLATE_SOURCE"
                : L"FAIL_TEMPLATE_SOURCE_MISSING");
        }
    }
    std::wstring skeleton = record.stepContractSkeletonJson;
    if (JsonContainsUnsafeCoordinate(skeleton)) {
        AddViolation(violations, L"FAIL_TEMPLATE_UNSAFE_COORDINATE");
    }
    if (JsonContainsForbiddenBackend(skeleton)) {
        AddViolation(violations, L"FAIL_TEMPLATE_BACKEND_BYPASS");
    }
    std::wstring combined = record.parameterSchemaJson + L" " + record.expectedContextSchemaJson + L" " + record.verificationHintSchemaJson;
    if (JsonContainsForbiddenBackend(combined)) {
        AddViolation(violations, L"FAIL_TEMPLATE_BACKEND_BYPASS");
    }
    if (HasSensitiveCommunicationPlaintext(record)) {
        AddViolation(violations, L"FAIL_TEMPLATE_SENSITIVE_CONTENT");
    }
    if (JsonBoolFalseOrMissing(record.safetyConstraintsJson, L"step_contract_validator_required")) {
        AddViolation(violations, L"FAIL_TEMPLATE_VALIDATOR_BYPASS");
    }
    if (JsonBoolFalseOrMissing(record.safetyConstraintsJson, L"runtime_session_required")) {
        AddViolation(violations, L"FAIL_TEMPLATE_RUNTIME_BYPASS");
    }
    if (JsonBoolFalseOrMissing(record.safetyConstraintsJson, L"verifier_required")) {
        AddViolation(violations, L"FAIL_TEMPLATE_VERIFIER_BYPASS");
    }
    if (!JsonBoolFalseOrMissing(record.safetyConstraintsJson, L"direct_execution_allowed")) {
        AddViolation(violations, L"FAIL_TEMPLATE_DIRECT_EXECUTION_ALLOWED");
    }
    if (!JsonBoolFalseOrMissing(record.safetyConstraintsJson, L"memory_execution_influence")) {
        AddViolation(violations, L"BLOCK_MEMORY_TEMPLATE_EXECUTION_INFLUENCE");
    }
    return BuildResult(record, violations);
}

WorkflowTemplateSafetyResult CheckWorkflowTemplateSafetyJson(const std::wstring& json) {
    WorkflowTemplateRecordResult parsed = ParseWorkflowTemplateRecordJson(json);
    if (!parsed.ok) {
        WorkflowTemplateRecord empty;
        std::vector<std::wstring> violations = { parsed.errorCode.empty() ? L"FAIL_TEMPLATE_SCHEMA_INVALID" : parsed.errorCode };
        return BuildResult(empty, violations);
    }
    return CheckWorkflowTemplateSafety(parsed.record);
}

WorkflowTemplateSafetyResult CheckWorkflowTemplateSafetyFile(const std::wstring& inputPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(inputPath, text, error)) {
        WorkflowTemplateRecord empty;
        std::vector<std::wstring> violations = { L"FILE_NOT_FOUND" };
        return BuildResult(empty, violations);
    }
    return CheckWorkflowTemplateSafetyJson(text);
}

int CommandWorkflowTemplateSafetyCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-template-safety-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"workflow-template-safety-check requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    WorkflowTemplateSafetyResult result = CheckWorkflowTemplateSafetyFile(input);
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, result.jsonReport, error);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason.empty() ? L"WORKFLOW_TEMPLATE_SAFETY_BLOCKED" : result.blockedReason, L"Workflow template safety boundary blocked the template.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
