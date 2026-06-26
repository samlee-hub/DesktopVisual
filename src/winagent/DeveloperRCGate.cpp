#include "DeveloperRCGate.h"

#include "CapabilityMatrixBuilder.h"
#include "DeveloperFullAccessPolicyVerifier.h"
#include "EvidenceChainVerifier.h"
#include "EvidenceFingerprint.h"
#include "HandoffPackageBuilder.h"
#include "ProjectRoot.h"
#include "ReleaseHardeningDeferredLedger.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "VersionIntegrityChecker.h"
#include "WorkflowBoundaryAuditor.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <iostream>
#include <iterator>
#include <sstream>

namespace v612 {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool ArgPresent(int argc, wchar_t** argv, const std::wstring& name) {
    for (int i = 2; i < argc; ++i) {
        if (argv[i] == name) return true;
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

std::wstring ArtifactRoot() {
    return ArtifactsPath(L"dev6.12.0_rc_gate_and_handoff");
}

std::wstring HandoffRoot() {
    return ValidationJoinPath(ArtifactRoot(), L"handoff_package");
}

std::wstring ReportPath(const std::wstring& fileName) {
    return ValidationJoinPath(ArtifactRoot(), fileName);
}

std::wstring ProjectFile(const std::wstring& relativePath) {
    return ProjectPath(relativePath);
}

bool ReadText(const std::wstring& path, std::wstring& text) {
    std::wstring error;
    return ReadValidationTextFile(path, text, error);
}

bool WriteText(const std::wstring& path, const std::wstring& text) {
    std::wstring error;
    return WriteValidationTextFile(path, text, error);
}

bool FileExists(const std::wstring& path) {
    return ValidationFileExists(path);
}

bool DirectoryExists(const std::wstring& path) {
    return ValidationDirectoryExists(path);
}

std::wstring JsonArray(const std::vector<std::wstring>& values) {
    return ValidationJsonArray(values);
}

std::wstring QuoteForCommand(const std::wstring& value) {
    std::wstring quoted = L"\"";
    for (wchar_t ch : value) {
        if (ch != L'"') quoted.push_back(ch);
    }
    quoted.push_back(L'"');
    return quoted;
}

std::wstring GitCapture(const std::wstring& args) {
    std::wstring command = L"git -C " + QuoteForCommand(ProjectRootPath()) + L" " + args + L" 2>NUL";
    FILE* pipe = _wpopen(command.c_str(), L"rt");
    if (!pipe) return L"";
    std::wstring output;
    wchar_t buffer[512] = {};
    while (fgetws(buffer, static_cast<int>(std::size(buffer)), pipe)) {
        output += buffer;
    }
    _pclose(pipe);
    while (!output.empty() && (output.back() == L'\r' || output.back() == L'\n' || output.back() == L' ' || output.back() == L'\t')) {
        output.pop_back();
    }
    return output;
}

std::wstring CurrentGitBranch() {
    return GitCapture(L"branch --show-current");
}

std::vector<EvidenceChainItem> DefaultEvidenceChain() {
    return {
        {L"v6.2", L"Runtime Session / Latency", L"artifacts\\dev6.2.0_persistent_runtime_session_latency_gate", L"v6.2.0"},
        {L"v6.3", L"PlanCompiler", L"artifacts\\dev6.3.0_plan_draft_to_step_contract_compiler", L"v6.3.0"},
        {L"v6.4", L"Runtime Task Execution", L"artifacts\\dev6.4.0_runtime_task_execution_from_compiled_agent_plan", L"v6.4.0"},
        {L"v6.5", L"VLM Observation", L"artifacts\\dev6.5.0_vlm_assisted_observation_contract", L"v6.5.0"},
        {L"v6.6", L"VLM Candidate", L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling", L"v6.6.0"},
        {L"v6.7", L"Explorer Workflow", L"artifacts\\dev6.7.0_explorer_agent_workflows_rerun", L"v6.7.0"},
        {L"v6.8", L"Browser/Form Workflow", L"artifacts\\dev6.8.0_browser_and_web_form_agent_workflows", L"v6.8.0"},
        {L"v6.9_comm", L"Communication Workflow", L"artifacts\\dev6.9.0_communication_workflow", L"v6.9.0"},
        {L"v6.9_stabilization", L"System Stabilization", L"artifacts\\dev6.9.0_system_stabilization", L"v6.9.0"},
        {L"v6.10", L"Experience Memory", L"artifacts\\dev6.10.0_experience_memory_failure_attribution", L"v6.10.0"},
        {L"v6.11", L"Workflow Template / Batch", L"artifacts\\dev6.11.0_workflow_template_learning_batch_acceleration", L"v6.11.0"}
    };
}

bool AcceptedFinalStatusText(const std::wstring& text) {
    std::wstring lower = Lower(text);
    return lower.find(L"final status: pass") != std::wstring::npos ||
           lower.find(L"final_status: pass") != std::wstring::npos ||
           lower.find(L"status: pass") != std::wstring::npos ||
           lower.find(L"final state: `v6_8_0_browser_form_accepted_ready_for_v6_9`") != std::wstring::npos ||
           lower.find(L"verification_ok: true") != std::wstring::npos ||
           lower.find(L"acceptance gate: pass") != std::wstring::npos ||
           lower.find(L"accepted: true") != std::wstring::npos ||
           lower.find(L"accepted version:") != std::wstring::npos;
}

bool RawCompletedUnverifiedTreatedAsPass(const std::wstring& text) {
    std::wstring lower = Lower(text);
    size_t raw = lower.find(L"raw_completed_unverified");
    if (raw == std::wstring::npos) return false;
    size_t pass = lower.find(L"pass");
    size_t verifier = lower.find(L"verifier");
    size_t acceptance = lower.find(L"acceptance gate");
    return pass != std::wstring::npos && verifier == std::wstring::npos && acceptance == std::wstring::npos;
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& value) {
    if (!value.empty() && std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

std::wstring ViolationsJson(const std::vector<std::wstring>& values) {
    return JsonArray(values);
}

std::wstring FirstViolation(const std::vector<std::wstring>& values) {
    return values.empty() ? L"" : values.front();
}

}  // namespace v612

V612ReportResult RunDeveloperRCGate() {
    V612ReportResult version = RunVersionIntegrityCheck();
    V612ReportResult chain = RunEvidenceChainVerification();
    V612ReportResult boundary = RunWorkflowBoundaryAudit();
    V612ReportResult fullAccess = RunDeveloperFullAccessPolicyVerification();
    V612ReportResult ledger = BuildReleaseHardeningDeferredLedger();
    V612ReportResult matrix = BuildCapabilityMatrix();
    V612ReportResult handoff = BuildHandoffPackage();

    std::vector<std::wstring> violations;
    if (!version.ok) v612::AddUnique(violations, version.blockedReason.empty() ? L"V6_12_BLOCKED_VERSION_INTEGRITY" : version.blockedReason);
    if (!chain.ok) v612::AddUnique(violations, chain.blockedReason.empty() ? L"V6_12_BLOCKED_EVIDENCE_CHAIN_INCOMPLETE" : chain.blockedReason);
    if (!boundary.ok) v612::AddUnique(violations, boundary.blockedReason.empty() ? L"V6_12_BLOCKED_WORKFLOW_BOUNDARY" : boundary.blockedReason);
    if (!fullAccess.ok) v612::AddUnique(violations, fullAccess.blockedReason.empty() ? L"V6_12_BLOCKED_DEVELOPER_FULL_ACCESS_REGRESSION" : fullAccess.blockedReason);
    if (!ledger.ok) v612::AddUnique(violations, ledger.blockedReason.empty() ? L"V6_12_BLOCKED_RELEASE_SCOPE_VIOLATION" : ledger.blockedReason);
    if (!matrix.ok) v612::AddUnique(violations, matrix.blockedReason.empty() ? L"FAIL_CAPABILITY_MATRIX" : matrix.blockedReason);
    if (!handoff.ok) v612::AddUnique(violations, handoff.blockedReason.empty() ? L"FAIL_HANDOFF_PACKAGE" : handoff.blockedReason);

    V612ReportResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS_WITH_RELEASE_DEFERRED_ITEMS" : L"BLOCKED";
    result.blockedReason = v612::FirstViolation(violations);

    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.developer_rc_gate\""
         << L",\"status\":" << simplejson::Quote(result.ok ? L"PASS" : L"BLOCKED")
         << L",\"developer_rc_status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"violations\":" << v612::ViolationsJson(violations)
         << L",\"version_integrity\":" << simplejson::Quote(version.status)
         << L",\"evidence_chain\":" << simplejson::Quote(chain.status)
         << L",\"workflow_boundary\":" << simplejson::Quote(boundary.status)
         << L",\"developer_full_access_policy\":" << simplejson::Quote(fullAccess.status)
         << L",\"release_hardening_deferred_ledger\":" << simplejson::Quote(ledger.status)
         << L",\"capability_matrix\":" << simplejson::Quote(matrix.status)
         << L",\"handoff_package\":" << simplejson::Quote(handoff.status)
         << L",\"developer_full_access_default\":true"
         << L",\"release_permission_hardening_deferred\":true"
         << L",\"public_release_ready\":false"
         << L",\"old_ui_workflow_rerun\":false"
         << L",\"public_release_hardening_implemented\":false"
         << L"}";
    result.jsonReport = json.str();

    std::wstringstream md;
    md << L"# v6.12.0 Developer RC Gate Report\n\n"
       << L"- status: " << (result.ok ? L"PASS" : L"BLOCKED") << L"\n"
       << L"- developer_rc_status: " << result.status << L"\n"
       << L"- blocked_reason: " << result.blockedReason << L"\n"
       << L"- version_integrity: " << version.status << L"\n"
       << L"- evidence_chain: " << chain.status << L"\n"
       << L"- workflow_boundary: " << boundary.status << L"\n"
       << L"- developer_full_access_policy: " << fullAccess.status << L"\n"
       << L"- release_hardening_deferred_ledger: " << ledger.status << L"\n"
       << L"- capability_matrix: " << matrix.status << L"\n"
       << L"- handoff_package: " << handoff.status << L"\n"
       << L"- developer_full_access_default: true\n"
       << L"- release_permission_hardening_deferred: true\n"
       << L"- public_release_ready: false\n"
       << L"- old_ui_workflow_rerun: false\n"
       << L"- public_release_hardening_implemented: false\n";
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"developer_rc_gate_report.md"), result.markdownReport);
    return result;
}

namespace {

int EmitV612ReportCommand(const std::wstring& command, ULONGLONG startTick, const V612ReportResult& result, const std::wstring& output) {
    if (!output.empty()) {
        v612::WriteText(output, result.jsonReport);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(),
            result.blockedReason.empty() ? L"V6_12_BLOCKED" : result.blockedReason,
            L"v6.12 developer RC check blocked.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}

}  // namespace

int CommandDeveloperRCGate(int argc, wchar_t** argv) {
    const std::wstring command = L"developer-rc-gate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    return EmitV612ReportCommand(command, startTick, RunDeveloperRCGate(), output);
}

int CommandV612RCHandoffCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"v6-12-rc-handoff-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    return EmitV612ReportCommand(command, startTick, RunDeveloperRCGate(), output);
}
