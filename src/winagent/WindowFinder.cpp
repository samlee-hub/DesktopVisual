#include "WindowFinder.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

std::wstring GetWindowTitle(HWND hwnd) {
    int length = GetWindowTextLengthW(hwnd);
    if (length <= 0) {
        return L"";
    }

    std::wstring title(static_cast<size_t>(length) + 1, L'\0');
    int copied = GetWindowTextW(hwnd, title.data(), length + 1);
    title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    for (wchar_t& ch : title) {
        if (ch < 0x20 || ch == 0x7f) {
            ch = L' ';
        }
    }
    return title;
}

bool HasNonWhitespace(const std::wstring& value) {
    for (wchar_t ch : value) {
        if (!iswspace(ch)) {
            return true;
        }
    }
    return false;
}

bool IntersectsVirtualDesktop(const RECT& rect) {
    if (rect.right <= rect.left || rect.bottom <= rect.top) {
        return false;
    }
    RECT virtualDesktop{
        GetSystemMetrics(SM_XVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN),
        GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    return rect.left < virtualDesktop.right &&
           rect.right > virtualDesktop.left &&
           rect.top < virtualDesktop.bottom &&
           rect.bottom > virtualDesktop.top;
}

BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lparam) {
    auto* windows = reinterpret_cast<std::vector<WindowInfo>*>(lparam);
    if (!IsWindowVisible(hwnd)) {
        return TRUE;
    }

    WindowInfo info;
    info.hwnd = hwnd;
    info.title = GetWindowTitle(hwnd);
    if (!HasNonWhitespace(info.title)) {
        return TRUE;
    }
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    if (!IntersectsVirtualDesktop(info.rect)) {
        return TRUE;
    }
    windows->push_back(info);
    return TRUE;
}

}  // namespace

std::vector<WindowInfo> EnumerateVisibleTopLevelWindows() {
    std::vector<WindowInfo> windows;
    EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&windows));
    return windows;
}

std::vector<WindowInfo> FindWindowsByTitleSubstring(const std::wstring& titleSubstring) {
    std::vector<WindowInfo> matches;
    std::wstring needle = ToLower(titleSubstring);

    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        std::wstring haystack = ToLower(window.title);
        if (!needle.empty() && haystack.find(needle) != std::wstring::npos) {
            matches.push_back(window);
        }
    }

    return matches;
}

std::wstring FormatHwnd(HWND hwnd) {
    std::wstringstream stream;
    stream << L"0x" << std::hex << reinterpret_cast<unsigned long long>(hwnd);
    return stream.str();
}
