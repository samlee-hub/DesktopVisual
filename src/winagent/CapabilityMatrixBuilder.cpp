#include "CapabilityMatrixBuilder.h"

#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <iostream>
#include <sstream>

namespace {

struct CapabilityRow {
    std::wstring name;
    std::wstring status;
    std::wstring evidenceRef;
    std::wstring limitation;
};

std::vector<CapabilityRow> Rows() {
    return {
        {L"Runtime Session", L"accepted", L"artifacts/dev6.2.0_persistent_runtime_session_latency_gate/final_status_report.md", L"same-machine runtime state; not a planner"},
        {L"StepContract compiler", L"accepted", L"artifacts/dev6.3.0_plan_draft_to_step_contract_compiler/final_status_report.md", L"compile/dry-run only for v6.3"},
        {L"Runtime task execution", L"accepted", L"artifacts/dev6.4.0_runtime_task_execution_from_compiled_agent_plan/final_status_report.md", L"bounded local-safe execution"},
        {L"VLM observation", L"accepted", L"artifacts/dev6.5.0_vlm_assisted_observation_contract/final_status_report.md", L"observation-only; no direct execution"},
        {L"VLM candidate handling", L"accepted", L"artifacts/dev6.6.0_vlm_assisted_unknown_ui_candidate_handling/final_status_report.md", L"candidates require Runtime validation"},
        {L"Explorer workflow", L"accepted", L"artifacts/dev6.7.0_explorer_agent_workflows_rerun/final_status_report.md", L"local allowed-root Explorer workflows"},
        {L"Browser/Form workflow", L"accepted", L"artifacts/dev6.8.0_browser_and_web_form_agent_workflows/final_status_report.md", L"no credential/CAPTCHA/public form commit"},
        {L"Communication workflow", L"accepted", L"artifacts/dev6.9.0_communication_workflow/final_status_report.md", L"draft/mock-safe; redacted evidence"},
        {L"Evidence stabilization", L"accepted", L"artifacts/dev6.9.0_system_stabilization/final_status_report.md", L"metadata and boundary checks only"},
        {L"Experience memory", L"accepted", L"artifacts/dev6.10.0_experience_memory_failure_attribution/final_status_report.md", L"read-only memory influence; no planner"},
        {L"Failure attribution", L"accepted", L"artifacts/dev6.10.0_experience_memory_failure_attribution/final_status_report.md", L"classification only"},
        {L"Workflow template", L"accepted", L"artifacts/dev6.11.0_workflow_template_learning_batch_acceleration/final_status_report.md", L"validated structure only"},
        {L"Batch workflow", L"accepted", L"artifacts/dev6.11.0_workflow_template_learning_batch_acceleration/final_status_report.md", L"compile/validate/serial mock; no parallel real UI"},
        {L"Developer full access policy", L"preserved", L"artifacts/dev6.12.0_rc_gate_and_handoff/developer_full_access_policy_report.md", L"developer build full access by default"},
        {L"Known stop boundaries", L"preserved", L"COMMAND_PROTOCOL.md", L"stops on real active protections and credentials"},
        {L"Deferred public release hardening", L"deferred", L"artifacts/dev6.12.0_rc_gate_and_handoff/release_hardening_deferred_ledger.md", L"not a v6.12 Developer RC blocker"}
    };
}

}  // namespace

V612ReportResult BuildCapabilityMatrix() {
    V612ReportResult result;
    result.ok = true;
    result.status = L"PASS";
    std::vector<CapabilityRow> rows = Rows();
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.developer_capability_matrix\""
         << L",\"status\":\"PASS\""
         << L",\"developer_build_full_access_default\":true"
         << L",\"public_release_permission_policy\":\"deferred\""
         << L",\"capabilities\":[";
    for (size_t i = 0; i < rows.size(); ++i) {
        if (i) json << L",";
        json << L"{\"name\":" << simplejson::Quote(rows[i].name)
             << L",\"status\":" << simplejson::Quote(rows[i].status)
             << L",\"evidence_ref\":" << simplejson::Quote(rows[i].evidenceRef)
             << L",\"known_limitation\":" << simplejson::Quote(rows[i].limitation)
             << L"}";
    }
    json << L"]}";
    result.jsonReport = json.str();

    std::wstringstream md;
    md << L"# Developer Capability Matrix\n\n"
       << L"- status: PASS\n"
       << L"- Developer build: full access by default\n"
       << L"- Public release permission policy: deferred\n\n"
       << L"| Capability | Status | Evidence | Known limitation |\n"
       << L"| --- | --- | --- | --- |\n";
    for (const auto& row : rows) {
        md << L"| " << row.name << L" | " << row.status << L" | `" << row.evidenceRef << L"` | " << row.limitation << L" |\n";
    }
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"developer_capability_matrix.json"), result.jsonReport);
    v612::WriteText(v612::ReportPath(L"developer_capability_matrix.md"), result.markdownReport);
    return result;
}

int CommandCapabilityMatrixBuild(int argc, wchar_t** argv) {
    const std::wstring command = L"capability-matrix-build";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    std::wstring markdownOutput;
    v612::ArgValue(argc, argv, L"--output", output);
    v612::ArgValue(argc, argv, L"--markdown-output", markdownOutput);
    V612ReportResult result = BuildCapabilityMatrix();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!markdownOutput.empty()) v612::WriteText(markdownOutput, result.markdownReport);
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
