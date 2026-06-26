#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct UiaElementInfo {
    std::wstring name;
    std::wstring value;
    std::wstring controlType;
    std::wstring automationId;
    std::wstring className;
    RECT rect = {};
    bool enabled = false;
    bool offscreen = false;
};

struct UiaQueryResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::vector<UiaElementInfo> elements;
};

struct UiaPatternActionResult {
    bool ok = false;
    bool found = false;
    bool patternAvailable = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    UiaElementInfo element;
};

UiaQueryResult ReadUiaTree(HWND hwnd);
UiaQueryResult FindUiaElementsByName(HWND hwnd, const std::wstring& name);
UiaPatternActionResult InvokeUiaElementByName(HWND hwnd, const std::wstring& name);
UiaPatternActionResult SetUiaElementValueByName(HWND hwnd, const std::wstring& name, const std::wstring& text);
