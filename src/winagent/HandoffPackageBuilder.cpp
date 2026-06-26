#include "HandoffPackageBuilder.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
#include <sstream>

namespace {

void WritePackageFile(const std::wstring& name, const std::wstring& title, const std::wstring& body) {
    std::wstring path = ValidationJoinPath(v612::HandoffRoot(), name);
    std::wstringstream text;
    text << L"# " << title << L"\n\n" << body << L"\n";
    v612::WriteText(path, text.str());
}

bool PackageContainsForbiddenContent(std::vector<std::wstring>& hits) {
    std::filesystem::path root(v612::HandoffRoot());
    std::error_code ec;
    if (!std::filesystem::exists(root, ec)) return false;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root, ec)) {
        if (ec) break;
        if (!entry.is_regular_file(ec)) continue;
        std::wstring path = entry.path().wstring();
        std::wstring lowerPath = v612::Lower(path);
        if (lowerPath.find(L"runtime_sessions") != std::wstring::npos) hits.push_back(path + L":runtime_sessions");
        if (lowerPath.find(L"stash") != std::wstring::npos) hits.push_back(path + L":stash");
        std::wstring text;
        if (v612::ReadText(path, text)) {
            std::wstring lower = v612::Lower(text);
            if (lower.find(L"plaintext_body") != std::wstring::npos ||
                lower.find(L"full_body") != std::wstring::npos ||
                lower.find(L"sensitive draft body") != std::wstring::npos ||
                lower.find(L"recipient@example") != std::wstring::npos) {
                hits.push_back(path + L":sensitive_content");
            }
        }
    }
    return !hits.empty();
}

}  // namespace

V612ReportResult BuildHandoffPackage() {
    EnsureDirectoryPath(v612::HandoffRoot());
    WritePackageFile(L"system_overview.md", L"System Overview",
        L"DesktopVisual v6.x Developer RC is a local Windows automation runtime with evidence-gated workflow layers from RuntimeSession through Workflow Templates. It is not a public release package.");
    WritePackageFile(L"architecture_summary.md", L"Architecture Summary",
        L"RuntimeSession, RuntimeContextGuard, StepContractValidator, workflow verifiers, MemorySafetyBoundary, WorkflowTemplateSafetyBoundary, and v6.12 RC checks remain separate gate layers.");
    WritePackageFile(L"capability_matrix.md", L"Capability Matrix",
        L"See ../developer_capability_matrix.md. Developer build is full access by default; public release permission policy is deferred.");
    WritePackageFile(L"evidence_chain_summary.md", L"Evidence Chain Summary",
        L"v6.2 through v6.11 final_status_report.md and evidence_index.md are verified by the v6.12 evidence-chain-verify command without rerunning old UI workflows.");
    WritePackageFile(L"command_protocol_summary.md", L"Command Protocol Summary",
        L"v6.12 adds Developer RC metadata commands only: developer-rc-gate, version-integrity-check, evidence-chain-verify, capability-matrix-build, workflow-boundary-audit, developer-full-access-policy-check, release-hardening-deferred-ledger, handoff-package-build, and v6-12-rc-handoff-check.");
    WritePackageFile(L"known_limitations_summary.md", L"Known Limitations Summary",
        L"Developer RC is not public release hardening. It does not add new workflows, does not alter RuntimeSession or StepContract semantics, and does not implement public permission narrowing.");
    WritePackageFile(L"developer_full_access_policy.md", L"Developer Full Access Policy",
        L"developer_full_access_default=true. Ordinary task words such as test, exam, interview, contest, LeetCode, OJ, social, email, and message are not developer-mode denylist terms. Runtime stops only on real active protection, credential, verification, proctoring, anti-cheat, anti-automation, or explicit security/risk mechanisms.");
    WritePackageFile(L"release_hardening_deferred_items.md", L"Release Hardening Deferred Items",
        L"Public release permission modes, consent UI, public repo cleanup, artifact slimming, privacy review, installer, public docs, and strict release rc_check are deferred to public_release_preparation.");
    WritePackageFile(L"next_steps_public_release_preparation.md", L"Next Steps Public Release Preparation",
        L"Prepare a separate public release hardening pass after v6.12 Developer RC, without retroactively changing the developer RC gate result.");
    WritePackageFile(L"verification_summary.md", L"Verification Summary",
        L"Required v6.12 runner/verifier/gate and metadata regression reports are stored under artifacts/dev6.12.0_rc_gate_and_handoff.");

    std::vector<std::wstring> hits;
    bool forbidden = PackageContainsForbiddenContent(hits);
    std::vector<std::wstring> violations;
    if (forbidden) v612::AddUnique(violations, L"FAIL_HANDOFF_SENSITIVE_CONTENT");

    V612ReportResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = v612::FirstViolation(violations);
    std::vector<std::wstring> files = {
        L"system_overview.md",
        L"architecture_summary.md",
        L"capability_matrix.md",
        L"evidence_chain_summary.md",
        L"command_protocol_summary.md",
        L"known_limitations_summary.md",
        L"developer_full_access_policy.md",
        L"release_hardening_deferred_items.md",
        L"next_steps_public_release_preparation.md",
        L"verification_summary.md"
    };
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.handoff_package\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"violations\":" << v612::ViolationsJson(violations)
         << L",\"package_root\":" << simplejson::Quote(v612::HandoffRoot())
         << L",\"files\":" << v612::JsonArray(files)
         << L",\"runtime_sessions_dump_included\":false"
         << L",\"stash_content_included\":false"
         << L",\"sensitive_communication_content_included\":" << (forbidden ? L"true" : L"false")
         << L",\"public_release_package_generated\":false"
         << L",\"forbidden_hits\":" << v612::JsonArray(hits)
         << L"}";
    result.jsonReport = json.str();
    std::wstringstream md;
    md << L"# Handoff Package Report\n\n"
       << L"- status: " << result.status << L"\n"
       << L"- package_root: " << v612::HandoffRoot() << L"\n"
       << L"- runtime_sessions_dump_included: false\n"
       << L"- stash_content_included: false\n"
       << L"- sensitive_communication_content_included: " << (forbidden ? L"true" : L"false") << L"\n"
       << L"- public_release_package_generated: false\n";
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"handoff_package_report.md"), result.markdownReport);
    return result;
}

int CommandHandoffPackageBuild(int argc, wchar_t** argv) {
    const std::wstring command = L"handoff-package-build";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    V612ReportResult result = BuildHandoffPackage();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Handoff package build failed.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
