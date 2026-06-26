#pragma once

#include <string>

struct FileWorkflowResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

FileWorkflowResult ResolveFilePathForWorkflow(
    const std::wstring& path,
    const std::wstring& allowedRoots,
    const std::wstring& extensions,
    long long maxBytes);
FileWorkflowResult RunFilePickerFlowFile(const std::wstring& path);
FileWorkflowResult VerifyAttachmentStateFile(
    const std::wstring& path,
    const std::wstring& expectedFile,
    int timeoutMs,
    int elapsedMs);
FileWorkflowResult CheckCrossWindowContextFile(const std::wstring& path);
FileWorkflowResult RunLocalMailAttachFlowFile(const std::wstring& path);
