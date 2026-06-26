#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct WindowInfo {
    HWND hwnd = nullptr;
    DWORD pid = 0;
    std::wstring title;
    RECT rect = {};
};

std::vector<WindowInfo> EnumerateVisibleTopLevelWindows();
std::vector<WindowInfo> FindWindowsByTitleSubstring(const std::wstring& titleSubstring);
std::wstring FormatHwnd(HWND hwnd);
