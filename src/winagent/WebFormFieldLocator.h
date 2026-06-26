#pragma once

#include "BrowserWorkflow.h"
#include "UiaController.h"

#include <windows.h>

#include <string>
#include <vector>

struct WebFormFieldLocatorRequest {
    std::wstring fieldId;
    std::wstring fieldLabel;
    std::wstring placeholder;
    std::wstring name;
    std::wstring title;
    std::wstring expectedRole = L"Edit";
    bool allowVlmCandidateFallback = false;
};

struct WebFormFieldLocatorResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring fieldId;
    std::wstring fieldLabel;
    std::wstring fieldRole;
    RECT targetRect = {};
    POINT targetCenter = {};
    std::wstring locatorSource;
    double confidence = 0.0;
    bool ambiguous = false;
    bool missing = false;
    bool requiresRuntimeValidation = true;
    std::wstring coordinateSourceType = L"runtime_locator";
    std::vector<UiaElementInfo> candidates;
};

WebFormFieldLocatorRequest WebFormFieldLocatorRequestFromSpec(const BrowserWorkflowFieldSpec& field);
WebFormFieldLocatorResult LocateWebFormField(HWND hwnd, const WebFormFieldLocatorRequest& request);
WebFormFieldLocatorResult LocateWebFormSubmit(HWND hwnd, const std::wstring& label);
std::wstring WebFormFieldLocatorResultJson(const WebFormFieldLocatorResult& result);
