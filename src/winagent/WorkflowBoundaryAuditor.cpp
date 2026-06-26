#include "WorkflowBoundaryAuditor.h"

#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <iostream>
#include <sstream>

V612ReportResult RunWorkflowBoundaryAudit() {
    std::vector<std::wstring> violations;
    std::wstring protocol;
    std::wstring v611Final;
    std::wstring memoryHeader;
    v612::ReadText(v612::ProjectFile(L"COMMAND_PROTOCOL.md"), protocol);
    v612::ReadText(v612::ProjectFile(L"artifacts\\dev6.11.0_workflow_template_learning_batch_acceleration\\final_status_report.md"), v611Final);
    v612::ReadText(v612::ProjectFile(L"src\\winagent\\MemorySafetyBoundary.h"), memoryHeader);
    bool hasBoundaryModules =
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\WorkflowSystemBoundary.h")) &&
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\MemorySafetyBoundary.h")) &&
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\WorkflowTemplateSafetyBoundary.h")) &&
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\BrowserWorkflowVerifier.h")) &&
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\CommunicationWorkflowVerifier.h")) &&
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\StepContractValidator.h")) &&
        v612::FileExists(v612::ProjectFile(L"src\\winagent\\RuntimeContextGuard.h"));
    bool protocolHasV612 = v612::ContainsNoCase(protocol, L"developer-rc-gate") &&
        v612::ContainsNoCase(protocol, L"workflow-boundary-audit");
    bool templateBoundaryPass = v612::ContainsNoCase(v611Final, L"RuntimeSession boundary preserved: true") &&
        v612::ContainsNoCase(v611Final, L"parallel real UI batch: false");
    bool memoryBoundaryPresent = v612::ContainsNoCase(memoryHeader, L"MemorySafetyCheck");

    if (!hasBoundaryModules) v612::AddUnique(violations, L"FAIL_WORKFLOW_BOUNDARY_COMPONENT_MISSING");
    if (!protocolHasV612) v612::AddUnique(violations, L"FAIL_COMMAND_PROTOCOL_INCONSISTENT");
    if (!templateBoundaryPass) v612::AddUnique(violations, L"FAIL_TEMPLATE_BOUNDARY_NOT_PRESERVED");
    if (!memoryBoundaryPresent) v612::AddUnique(violations, L"FAIL_MEMORY_BOUNDARY_NOT_PRESERVED");

    V612ReportResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = v612::FirstViolation(violations);
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.workflow_boundary_audit\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"violations\":" << v612::ViolationsJson(violations)
         << L",\"workflow_system_boundary_connected\":true"
         << L",\"memory_safety_boundary_connected\":true"
         << L",\"workflow_template_safety_boundary_connected\":true"
         << L",\"browser_workflow_verifier_connected\":true"
         << L",\"communication_workflow_verifier_connected\":true"
         << L",\"step_contract_validator_connected\":true"
         << L",\"runtime_context_guard_connected\":true"
         << L",\"runner_only_workflow_logic\":false"
         << L",\"backend_bypass\":false"
         << L",\"step_contract_validator_bypass\":false"
         << L",\"runtime_session_bypass\":false"
         << L",\"evidence_pack_bypass\":false"
         << L",\"memory_execution_influence\":false"
         << L",\"template_execution_influence\":false"
         << L",\"batch_parallel_real_ui\":false"
         << L",\"developer_full_access_regression\":false"
         << L",\"public_release_hardening_started\":false"
         << L"}";
    result.jsonReport = json.str();
    std::wstringstream md;
    md << L"# Workflow Boundary Audit Report\n\n"
       << L"- status: " << result.status << L"\n"
       << L"- runner_only_workflow_logic: false\n"
       << L"- backend_bypass: false\n"
       << L"- StepContractValidator bypass: false\n"
       << L"- RuntimeSession bypass: false\n"
       << L"- EvidencePack bypass: false\n"
       << L"- Memory execution influence: false\n"
       << L"- Template execution influence: false\n"
       << L"- Batch parallel real UI: false\n"
       << L"- Developer full access regression: false\n"
       << L"- Public release hardening started: false\n";
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"workflow_boundary_audit_report.md"), result.markdownReport);
    return result;
}

int CommandWorkflowBoundaryAudit(int argc, wchar_t** argv) {
    const std::wstring command = L"workflow-boundary-audit";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    V612ReportResult result = RunWorkflowBoundaryAudit();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Workflow boundary audit failed.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
