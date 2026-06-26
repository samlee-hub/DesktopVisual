#include "EvidenceChainVerifier.h"

#include "EvidenceFingerprint.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <iostream>
#include <sstream>

V612ReportResult RunEvidenceChainVerification() {
    std::vector<std::wstring> violations;
    auto items = v612::DefaultEvidenceChain();
    std::wstringstream itemJson;
    std::wstringstream md;
    md << L"# Evidence Chain Report\n\n"
       << L"| Item | Evidence | final_status_report | evidence_index | tag | accepted |\n"
       << L"| --- | --- | --- | --- | --- | --- |\n";
    itemJson << L"[";
    for (size_t i = 0; i < items.size(); ++i) {
        const auto& item = items[i];
        std::wstring dir = v612::ProjectFile(item.evidenceDir);
        std::wstring finalPath = ValidationJoinPath(dir, L"final_status_report.md");
        std::wstring indexPath = ValidationJoinPath(dir, L"evidence_index.md");
        bool dirExists = v612::DirectoryExists(dir);
        bool finalExists = v612::FileExists(finalPath);
        bool indexExists = v612::FileExists(indexPath);
        bool tagExists = !v612::GitCapture(std::wstring(L"tag --list ") + item.tag).empty();
        std::wstring finalText;
        bool accepted = finalExists && v612::ReadText(finalPath, finalText) && v612::AcceptedFinalStatusText(finalText);
        bool rawAsPass = finalExists && v612::RawCompletedUnverifiedTreatedAsPass(finalText);
        if (!dirExists || !finalExists || !indexExists) v612::AddUnique(violations, L"FAIL_EVIDENCE_CHAIN_INCOMPLETE");
        if (!accepted) v612::AddUnique(violations, L"FAIL_EVIDENCE_NOT_ACCEPTED");
        if (rawAsPass) v612::AddUnique(violations, L"FAIL_RAW_AS_PASS");
        if (!tagExists) v612::AddUnique(violations, L"FAIL_EVIDENCE_TAG_MISSING");
        if (i) itemJson << L",";
        itemJson << L"{\"id\":" << simplejson::Quote(item.id)
                 << L",\"title\":" << simplejson::Quote(item.title)
                 << L",\"evidence_dir\":" << simplejson::Quote(item.evidenceDir)
                 << L",\"final_status_report_present\":" << (finalExists ? L"true" : L"false")
                 << L",\"evidence_index_present\":" << (indexExists ? L"true" : L"false")
                 << L",\"accepted_or_pass\":" << (accepted ? L"true" : L"false")
                 << L",\"raw_completed_unverified_as_pass\":" << (rawAsPass ? L"true" : L"false")
                 << L",\"tag\":" << simplejson::Quote(item.tag)
                 << L",\"tag_exists\":" << (tagExists ? L"true" : L"false")
                 << L"}";
        md << L"| " << item.title << L" | `" << item.evidenceDir << L"` | "
           << (finalExists ? L"present" : L"missing") << L" | "
           << (indexExists ? L"present" : L"missing") << L" | "
           << (tagExists ? item.tag : L"missing") << L" | "
           << (accepted ? L"true" : L"false") << L" |\n";
    }
    itemJson << L"]";

    V612ReportResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = v612::FirstViolation(violations);
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.evidence_chain\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"violations\":" << v612::ViolationsJson(violations)
         << L",\"no_ui_workflow_rerun\":true"
         << L",\"stash_used\":false"
         << L",\"untracked_artifact_used_as_trusted_source\":false"
         << L",\"items\":" << itemJson.str()
         << L"}";
    result.jsonReport = json.str();
    md << L"\n- status: " << result.status << L"\n"
       << L"- no_ui_workflow_rerun: true\n"
       << L"- stash_used: false\n"
       << L"- untracked_artifact_used_as_trusted_source: false\n";
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"evidence_chain_report.md"), result.markdownReport);
    return result;
}

int CommandEvidenceChainVerify(int argc, wchar_t** argv) {
    const std::wstring command = L"evidence-chain-verify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    V612ReportResult result = RunEvidenceChainVerification();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Evidence chain verification failed.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
