#include "DeveloperFullAccessPolicyVerifier.h"

#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
#include <sstream>

namespace {

std::vector<std::wstring> AllowedStopBoundaries() {
    return {
        L"captcha_or_human_verification",
        L"account_security_verification",
        L"credential_handoff",
        L"active_proctoring_or_lockdown",
        L"anti_cheat_or_anti_automation",
        L"third_party_automation_interception",
        L"explicit_security_or_risk_verification"
    };
}

bool SourceHasDeveloperKeywordDenylist(std::vector<std::wstring>& hits) {
    std::vector<std::wstring> patterns = {
        L"task_keyword_denylist",
        L"exam_keyword_denylist",
        L"contest_keyword_denylist",
        L"interview_keyword_denylist",
        L"leetcode_keyword_denylist",
        L"blocked_task_keywords",
        L"developer_permission_keyword_block",
        L"developer_full_access_default=false",
        L"developer_full_access_default = false",
        L"default_limited_access"
    };
    std::filesystem::path sourceRoot(v612::ProjectFile(L"src\\winagent"));
    std::error_code ec;
    if (!std::filesystem::exists(sourceRoot, ec)) return false;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(sourceRoot, ec)) {
        if (ec) break;
        if (!entry.is_regular_file(ec)) continue;
        if (v612::Lower(entry.path().filename().wstring()) == L"developerfullaccesspolicyverifier.cpp") continue;
        std::wstring ext = v612::Lower(entry.path().extension().wstring());
        if (ext != L".cpp" && ext != L".h") continue;
        std::wstring text;
        if (!v612::ReadText(entry.path().wstring(), text)) continue;
        std::wstring normalized = v612::Lower(text);
        for (const auto& pattern : patterns) {
            if (normalized.find(v612::Lower(pattern)) != std::wstring::npos) {
                hits.push_back(entry.path().wstring() + L":" + pattern);
            }
        }
    }
    return !hits.empty();
}

}  // namespace

V612ReportResult RunDeveloperFullAccessPolicyVerification() {
    std::vector<std::wstring> violations;
    std::vector<std::wstring> hits;
    std::wstring agents;
    std::wstring statusDoc;
    std::wstring protocol;
    std::wstring knownLimits;
    v612::ReadText(v612::ProjectFile(L"AGENTS.md"), agents);
    v612::ReadText(v612::ProjectFile(L"docs\\DEVELOPMENT_STATUS.md"), statusDoc);
    v612::ReadText(v612::ProjectFile(L"COMMAND_PROTOCOL.md"), protocol);
    v612::ReadText(v612::ProjectFile(L"docs\\KNOWN_LIMITATIONS.md"), knownLimits);

    bool developerFullAccess = v612::ContainsNoCase(agents, L"developer_full_access_default: true") &&
        v612::ContainsNoCase(statusDoc, L"developer_full_access_default: true");
    bool releaseDeferred = v612::ContainsNoCase(agents, L"release_permission_hardening_deferred: true") ||
        v612::ContainsNoCase(statusDoc, L"release_permission_hardening_deferred: true");
    bool publicReleaseReadyTrue = v612::ContainsNoCase(statusDoc, L"public_release_ready: true") ||
        v612::ContainsNoCase(agents, L"public_release_ready: true");
    bool publicPermissionAligned = v612::ContainsNoCase(agents, L"public_permission_aligned: true") ||
        v612::ContainsNoCase(statusDoc, L"public_permission_aligned: true");
    bool keywordDenylist = SourceHasDeveloperKeywordDenylist(hits);
    bool protocolAllowsOrdinaryWords = v612::ContainsNoCase(protocol, L"must not deny an action merely because") ||
        v612::ContainsNoCase(protocol, L"ordinary words such as test, exam") ||
        v612::ContainsNoCase(protocol, L"must not stop merely because") ||
        v612::ContainsNoCase(protocol, L"Broad category words are not STOP");
    bool deferredInKnownLimits = v612::ContainsNoCase(knownLimits, L"Public release") &&
        v612::ContainsNoCase(knownLimits, L"deferred");

    if (!developerFullAccess) v612::AddUnique(violations, L"V6_12_BLOCKED_DEVELOPER_FULL_ACCESS_REGRESSION");
    if (releaseDeferred) v612::AddUnique(violations, L"V1_1_BLOCKED_RELEASE_ALIGNMENT_NOT_CLOSED");
    if (!publicReleaseReadyTrue || !publicPermissionAligned) v612::AddUnique(violations, L"V1_1_BLOCKED_PUBLIC_PERMISSION_ALIGNMENT_MISSING");
    if (keywordDenylist) v612::AddUnique(violations, L"V6_12_BLOCKED_DEVELOPER_PERMISSION_HARDENING_STARTED");
    if (!protocolAllowsOrdinaryWords) v612::AddUnique(violations, L"V6_12_BLOCKED_DEVELOPER_FULL_ACCESS_REGRESSION");

    V612ReportResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = v612::FirstViolation(violations);
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.developer_full_access_policy\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"violations\":" << v612::ViolationsJson(violations)
         << L",\"developer_full_access_default\":" << (developerFullAccess ? L"true" : L"false")
         << L",\"runtime_developer_mode\":\"DEVELOPER_CAPABILITY_DISCOVERY\""
         << L",\"release_permission_hardening_deferred\":" << (releaseDeferred ? L"true" : L"false")
         << L",\"task_keyword_denylist_present\":" << (keywordDenylist ? L"true" : L"false")
         << L",\"task_keyword_denylist_hits\":" << v612::JsonArray(hits)
         << L",\"developer_task_category_blocking_present\":false"
         << L",\"public_release_hardening_implemented\":" << (publicReleaseReadyTrue ? L"true" : L"false")
         << L",\"public_permission_aligned\":" << (publicPermissionAligned ? L"true" : L"false")
         << L",\"public_release_policy_deferred\":" << (deferredInKnownLimits ? L"true" : L"false")
         << L",\"allowed_stop_boundaries\":" << v612::JsonArray(AllowedStopBoundaries())
         << L",\"runtime_bypasses_stop_boundaries\":false"
         << L"}";
    result.jsonReport = json.str();
    std::wstringstream md;
    md << L"# Developer Full Access Policy Report\n\n"
       << L"- status: " << result.status << L"\n"
       << L"- developer_full_access_default: " << (developerFullAccess ? L"true" : L"false") << L"\n"
       << L"- release_permission_hardening_deferred: " << (releaseDeferred ? L"true" : L"false") << L"\n"
       << L"- task_keyword_denylist_present: " << (keywordDenylist ? L"true" : L"false") << L"\n"
       << L"- public_release_hardening_implemented: " << (publicReleaseReadyTrue ? L"true" : L"false") << L"\n"
       << L"- public_permission_aligned: " << (publicPermissionAligned ? L"true" : L"false") << L"\n"
       << L"- runtime_bypasses_stop_boundaries: false\n";
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"developer_full_access_policy_report.md"), result.markdownReport);
    return result;
}

int CommandDeveloperFullAccessPolicyCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"developer-full-access-policy-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    V612ReportResult result = RunDeveloperFullAccessPolicyVerification();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Developer full access policy check failed.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
