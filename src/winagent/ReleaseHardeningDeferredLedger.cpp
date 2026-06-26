#include "ReleaseHardeningDeferredLedger.h"

#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <iostream>
#include <sstream>

namespace {

std::vector<std::wstring> DeferredItems() {
    return {
        L"public release permission modes",
        L"user selectable FULL_ACCESS / limited access",
        L"exam/test/interview/contest public safety policy",
        L"release consent UI",
        L"public repo cleanup",
        L"artifact slimming for release package",
        L"privacy review for public package",
        L"installer / packaging",
        L"public documentation",
        L"release rc_check strict mode"
    };
}

}  // namespace

V612ReportResult BuildReleaseHardeningDeferredLedger() {
    V612ReportResult result;
    result.ok = true;
    result.status = L"PASS_WITH_RELEASE_DEFERRED_ITEMS";
    std::vector<std::wstring> items = DeferredItems();
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.release_hardening_deferred_ledger\""
         << L",\"status\":\"PASS_WITH_RELEASE_DEFERRED_ITEMS\""
         << L",\"developer_rc_blocker\":false"
         << L",\"public_release_ready\":false"
         << L",\"release_permission_hardening_deferred\":true"
         << L",\"items\":[";
    for (size_t i = 0; i < items.size(); ++i) {
        if (i) json << L",";
        json << L"{\"id\":\"release_deferred_" << (i + 1) << L"\",\"item\":" << simplejson::Quote(items[i])
             << L",\"scope\":\"public_release_preparation\",\"v6_12_blocker\":false}";
    }
    json << L"]}";
    result.jsonReport = json.str();

    std::wstringstream md;
    md << L"# Release Hardening Deferred Ledger\n\n"
       << L"- status: PASS_WITH_RELEASE_DEFERRED_ITEMS\n"
       << L"- developer_rc_blocker: false\n"
       << L"- release_permission_hardening_deferred: true\n"
       << L"- public_release_ready: false\n\n";
    for (size_t i = 0; i < items.size(); ++i) {
        md << L"- " << (i + 1) << L". " << items[i] << L" - deferred to public_release_preparation\n";
    }
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"release_hardening_deferred_ledger.json"), result.jsonReport);
    v612::WriteText(v612::ReportPath(L"release_hardening_deferred_ledger.md"), result.markdownReport);
    return result;
}

int CommandReleaseHardeningDeferredLedger(int argc, wchar_t** argv) {
    const std::wstring command = L"release-hardening-deferred-ledger";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    std::wstring markdownOutput;
    v612::ArgValue(argc, argv, L"--output", output);
    v612::ArgValue(argc, argv, L"--markdown-output", markdownOutput);
    V612ReportResult result = BuildReleaseHardeningDeferredLedger();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!markdownOutput.empty()) v612::WriteText(markdownOutput, result.markdownReport);
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
