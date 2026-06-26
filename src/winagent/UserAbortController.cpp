#include "UserAbortController.h"

#include "Trace.h"

#include <windows.h>

#include <atomic>
#include <cwctype>
#include <sstream>
#include <string>

namespace {

std::atomic<bool> g_abortLatched{false};
std::atomic<int> g_pollCount{0};

std::wstring EnvValue(const wchar_t* name) {
    DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
    if (required == 0) return L"";
    std::wstring value(required, L'\0');
    DWORD copied = GetEnvironmentVariableW(name, value.data(), required);
    if (copied == 0) return L"";
    value.resize(copied);
    return value;
}

std::wstring Lower(std::wstring value) {
    for (wchar_t& ch : value) {
        ch = static_cast<wchar_t>(std::towlower(ch));
    }
    return value;
}

bool EnvFlag(const wchar_t* name) {
    std::wstring value = Lower(EnvValue(name));
    return value == L"1" || value == L"true" || value == L"yes" || value == L"on";
}

int EnvInt(const wchar_t* name) {
    std::wstring value = EnvValue(name);
    if (value.empty()) return 0;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(value, &consumed, 10);
        return consumed == value.size() ? parsed : 0;
    } catch (...) {
        return 0;
    }
}

bool IsPhysicalF12Pressed() {
    return (GetAsyncKeyState(VK_F12) & 0x8000) != 0;
}

void SendKeyUp(WORD vk) {
    INPUT input = {};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = vk;
    input.ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(1, &input, sizeof(INPUT));
}

void SendMouseUp(DWORD flag) {
    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = flag;
    SendInput(1, &input, sizeof(INPUT));
}

std::wstring TrimObjectBraces(std::wstring json) {
    size_t start = json.find_first_not_of(L" \r\n\t");
    size_t end = json.find_last_not_of(L" \r\n\t");
    if (start == std::wstring::npos || end == std::wstring::npos || end < start) return L"";
    json = json.substr(start, end - start + 1);
    if (json.size() >= 2 && json.front() == L'{' && json.back() == L'}') {
        return json.substr(1, json.size() - 2);
    }
    return json;
}

}  // namespace

const wchar_t* UserAbortStopCode() {
    return L"STOP_USER_FORCE_EXIT_F12";
}

std::wstring UserAbortMessage() {
    static const wchar_t kMessage[] = {
        0x7528, 0x6237, 0x5DF2, 0x6309, 0x0020, 0x0046, 0x0031, 0x0032,
        0x0020, 0x5F3A, 0x5236, 0x7ED3, 0x675F, 0x5F53, 0x524D,
        0x4EFB, 0x52A1, 0xFF0C, 0x0041, 0x0067, 0x0065, 0x006E, 0x0074,
        0x0020, 0x5DF2, 0x505C, 0x6B62, 0x672C, 0x6B21, 0x884C,
        0x4E3A, 0x3002, 0
    };
    return std::wstring(kMessage);
}

UserAbortStatus PollUserAbort() {
    int pollCount = ++g_pollCount;
    int abortAfterChecks = EnvInt(L"DESKTOPVISUAL_FORCE_F12_ABORT_AFTER_CHECKS");
    bool simulatedAbort = EnvFlag(L"DESKTOPVISUAL_FORCE_F12_ABORT") ||
        (abortAfterChecks > 0 && pollCount >= abortAfterChecks);

    if (simulatedAbort || IsPhysicalF12Pressed()) {
        g_abortLatched.store(true);
    }

    UserAbortStatus status;
    status.abortRequested = g_abortLatched.load();
    if (status.abortRequested) {
        status.userForceExit = true;
        status.forceExitKey = L"F12";
        status.forceExitScope = L"current_task_only";
        status.processExit = false;
        status.stopCode = UserAbortStopCode();
        status.message = UserAbortMessage();
    }
    return status;
}

bool IsUserAbortRequested() {
    return PollUserAbort().abortRequested;
}

bool IsUserAbortStopCode(const std::wstring& code) {
    return code == UserAbortStopCode();
}

void ResetUserAbortForCurrentTask() {
    g_abortLatched.store(false);
    g_pollCount.store(0);
}

void ReleaseUserAbortInputState() {
    SendMouseUp(MOUSEEVENTF_LEFTUP);
    SendMouseUp(MOUSEEVENTF_RIGHTUP);
    SendMouseUp(MOUSEEVENTF_MIDDLEUP);
    SendKeyUp(VK_CONTROL);
    SendKeyUp(VK_LCONTROL);
    SendKeyUp(VK_RCONTROL);
    SendKeyUp(VK_SHIFT);
    SendKeyUp(VK_LSHIFT);
    SendKeyUp(VK_RSHIFT);
    SendKeyUp(VK_MENU);
    SendKeyUp(VK_LMENU);
    SendKeyUp(VK_RMENU);
    SendKeyUp(VK_LWIN);
    SendKeyUp(VK_RWIN);
}

std::wstring UserAbortEvidenceFields() {
    std::wstringstream json;
    json << L"\"user_force_exit\":true"
         << L",\"force_exit_key\":\"F12\""
         << L",\"force_exit_scope\":\"current_task_only\""
         << L",\"process_exit\":false";
    return json.str();
}

std::wstring UserAbortEvidenceJson(const std::wstring& extraFields) {
    std::wstring extra = TrimObjectBraces(extraFields);
    std::wstring fields = UserAbortEvidenceFields();
    if (!extra.empty()) {
        fields += L"," + extra;
    }
    return L"{" + fields + L"}";
}

std::wstring MergeUserAbortEvidenceJson(const std::wstring& dataJson) {
    return UserAbortEvidenceJson(dataJson);
}
