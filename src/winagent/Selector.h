#pragma once

#include "WindowFinder.h"

#include <string>

struct SelectorResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring selector;
    std::wstring locateMethod;
    std::wstring finalMethod;
    int matchCount = 0;
    double confidence = 0.0;
    int clientX = 0;
    int clientY = 0;
    int screenX = 0;
    int screenY = 0;
    RECT rect = {};
    bool hasElement = false;
    std::wstring elementName;
    std::wstring elementControlType;
    std::wstring elementAutomationId;
    std::wstring elementClassName;
    bool elementEnabled = false;
    bool elementOffscreen = false;
    bool uiaValueCandidate = false;
    bool uiaInvokeCandidate = false;
    std::wstring matchedText;
    std::wstring source;
    std::wstring failureReason;
    std::wstring reportPath;
    std::wstring extraJsonFields;
    std::wstring dataJson;
};

SelectorResult LocateSelector(HWND hwnd, const std::wstring& selector);
std::wstring SelectorResultDataJson(const SelectorResult& result);
