#pragma once

#include "WindowFinder.h"

#include <string>

struct ObserveResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    WindowInfo target;
    std::wstring dataJson;
    std::wstring screenshotPath;
    std::wstring screenshotMethod;
    int uiaElementCount = 0;
    bool focusVerified = false;
};

ObserveResult ObserveWindow(const std::wstring& title, bool includeScreenshot, bool includeUia, int maxElements, const std::wstring& process = L"");
