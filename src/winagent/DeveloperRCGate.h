#pragma once

#include <string>
#include <vector>

struct V612ReportResult {
    bool ok = false;
    std::wstring status;
    std::wstring blockedReason;
    std::wstring jsonReport;
    std::wstring markdownReport;
};

namespace v612 {

struct EvidenceChainItem {
    std::wstring id;
    std::wstring title;
    std::wstring evidenceDir;
    std::wstring tag;
};

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value);
bool ArgPresent(int argc, wchar_t** argv, const std::wstring& name);
std::wstring Lower(std::wstring value);
bool ContainsNoCase(const std::wstring& value, const std::wstring& needle);
std::wstring ArtifactRoot();
std::wstring HandoffRoot();
std::wstring ReportPath(const std::wstring& fileName);
std::wstring ProjectFile(const std::wstring& relativePath);
bool ReadText(const std::wstring& path, std::wstring& text);
bool WriteText(const std::wstring& path, const std::wstring& text);
bool FileExists(const std::wstring& path);
bool DirectoryExists(const std::wstring& path);
std::wstring JsonArray(const std::vector<std::wstring>& values);
std::wstring GitCapture(const std::wstring& args);
std::wstring CurrentGitBranch();
std::vector<EvidenceChainItem> DefaultEvidenceChain();
bool AcceptedFinalStatusText(const std::wstring& text);
bool RawCompletedUnverifiedTreatedAsPass(const std::wstring& text);
void AddUnique(std::vector<std::wstring>& values, const std::wstring& value);
std::wstring ViolationsJson(const std::vector<std::wstring>& values);
std::wstring FirstViolation(const std::vector<std::wstring>& values);

}  // namespace v612

V612ReportResult RunDeveloperRCGate();

int CommandDeveloperRCGate(int argc, wchar_t** argv);
int CommandV612RCHandoffCheck(int argc, wchar_t** argv);
