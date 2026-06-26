#include "VersionIntegrityChecker.h"

#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <cstdio>
#include <iostream>
#include <iterator>
#include <sstream>

namespace {

std::wstring RunCommandCapture(const std::wstring& command) {
    FILE* pipe = _wpopen(command.c_str(), L"rt");
    if (!pipe) return L"";
    std::wstring output;
    wchar_t buffer[512] = {};
    while (fgetws(buffer, static_cast<int>(std::size(buffer)), pipe)) output += buffer;
    _pclose(pipe);
    return output;
}

std::wstring Quote(const std::wstring& value) {
    std::wstring out = L"\"";
    for (wchar_t ch : value) if (ch != L'"') out.push_back(ch);
    out.push_back(L'"');
    return out;
}

std::wstring ExtractJsonVersion(const std::wstring& text) {
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (parsed.ok && parsed.root.IsObject()) {
        const simplejson::Value* data = simplejson::Find(parsed.root, L"data");
        if (data && data->IsObject()) {
            std::wstring version = simplejson::GetString(*data, L"version");
            if (!version.empty()) return version;
        }
        std::wstring version = simplejson::GetString(parsed.root, L"version");
        if (!version.empty()) return version;
    }
    return L"";
}

std::wstring Trim(std::wstring value) {
    while (!value.empty() && (value.back() == L'\r' || value.back() == L'\n' || value.back() == L' ' || value.back() == L'\t')) value.pop_back();
    size_t first = 0;
    while (first < value.size() && (value[first] == L'\r' || value[first] == L'\n' || value[first] == L' ' || value[first] == L'\t' || value[first] == 0xFEFF)) ++first;
    return value.substr(first);
}

}  // namespace

V612ReportResult RunVersionIntegrityCheck() {
    std::vector<std::wstring> violations;
    std::wstring versionText;
    v612::ReadText(v612::ProjectFile(L"VERSION"), versionText);
    std::wstring version = Trim(versionText);
    std::wstring winagent = v612::ProjectFile(L"bin\\winagent.exe");
    std::wstring runtimeOutput = RunCommandCapture(Quote(winagent) + L" version 2>NUL");
    std::wstring runtimeVersion = ExtractJsonVersion(runtimeOutput);
    std::wstring agents;
    std::wstring statusDoc;
    std::wstring changelog;
    std::wstring roadmap;
    v612::ReadText(v612::ProjectFile(L"AGENTS.md"), agents);
    v612::ReadText(v612::ProjectFile(L"docs\\DEVELOPMENT_STATUS.md"), statusDoc);
    v612::ReadText(v612::ProjectFile(L"CHANGELOG.md"), changelog);
    v612::ReadText(v612::ProjectFile(L"docs\\ROADMAP.md"), roadmap);
    std::wstring branch = v612::CurrentGitBranch();
    bool tagExists = !v612::GitCapture(L"tag --list v6.11.0").empty();
    bool digestPresent = v612::FileExists(v612::ReportPath(L"agent_context_digest.md"));

    if (version != L"6.12.0") v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (runtimeVersion != L"6.12.0") v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (!v612::ContainsNoCase(agents, L"current_trusted_version: 6.12.0")) v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (!v612::ContainsNoCase(statusDoc, L"current_trusted_version: 6.12.0")) v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (!v612::ContainsNoCase(statusDoc, L"runtime_version: 6.12.0")) v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (!v612::ContainsNoCase(changelog, L"v6.12.0")) v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (!v612::ContainsNoCase(roadmap, L"post_v6_developer_rc_handoff")) v612::AddUnique(violations, L"FAIL_VERSION_INTEGRITY");
    if (!tagExists) v612::AddUnique(violations, L"FAIL_VERSION_TAG_MISSING");
    if (branch != L"dev/v6.12.0-rc-gate-and-handoff") v612::AddUnique(violations, L"FAIL_VERSION_BRANCH_MISMATCH");
    if (!digestPresent) v612::AddUnique(violations, L"FAIL_VERSION_START_AUDIT_MISSING");

    V612ReportResult result;
    result.ok = violations.empty();
    result.status = result.ok ? L"PASS" : L"BLOCKED";
    result.blockedReason = v612::FirstViolation(violations);
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.12.0.version_integrity\""
         << L",\"status\":" << simplejson::Quote(result.status)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"violations\":" << v612::ViolationsJson(violations)
         << L",\"version_file\":" << simplejson::Quote(version)
         << L",\"runtime_binary_version\":" << simplejson::Quote(runtimeVersion)
         << L",\"branch\":" << simplejson::Quote(branch)
         << L",\"tag_v6_11_0_exists\":" << (tagExists ? L"true" : L"false")
         << L",\"start_dirty_audit_recorded\":" << (digestPresent ? L"true" : L"false")
         << L",\"current_trusted_version\":\"6.12.0\""
         << L",\"runtime_version\":\"6.12.0\""
         << L"}";
    result.jsonReport = json.str();
    std::wstringstream md;
    md << L"# Version Integrity Report\n\n"
       << L"- status: " << result.status << L"\n"
       << L"- VERSION: " << version << L"\n"
       << L"- bin\\winagent.exe version: " << runtimeVersion << L"\n"
       << L"- branch: " << branch << L"\n"
       << L"- tag_v6_11_0_exists: " << (tagExists ? L"true" : L"false") << L"\n"
       << L"- start_dirty_audit_recorded: " << (digestPresent ? L"true" : L"false") << L"\n";
    result.markdownReport = md.str();
    v612::WriteText(v612::ReportPath(L"version_integrity_report.md"), result.markdownReport);
    return result;
}

int CommandVersionIntegrityCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"version-integrity-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring output;
    v612::ArgValue(argc, argv, L"--output", output);
    V612ReportResult result = RunVersionIntegrityCheck();
    if (!output.empty()) v612::WriteText(output, result.jsonReport);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Version integrity check failed.", result.jsonReport) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.jsonReport) << L"\n";
    return 0;
}
