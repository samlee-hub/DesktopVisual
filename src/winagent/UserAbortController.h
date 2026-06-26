#pragma once

#include <string>

struct UserAbortStatus {
    bool abortRequested = false;
    bool userForceExit = false;
    std::wstring forceExitKey;
    std::wstring forceExitScope;
    bool processExit = false;
    std::wstring stopCode;
    std::wstring message;
};

const wchar_t* UserAbortStopCode();
std::wstring UserAbortMessage();
UserAbortStatus PollUserAbort();
bool IsUserAbortRequested();
bool IsUserAbortStopCode(const std::wstring& code);
void ResetUserAbortForCurrentTask();
void ReleaseUserAbortInputState();
std::wstring UserAbortEvidenceFields();
std::wstring UserAbortEvidenceJson(const std::wstring& extraFields = L"");
std::wstring MergeUserAbortEvidenceJson(const std::wstring& dataJson);
