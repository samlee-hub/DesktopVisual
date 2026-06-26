#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct FormControl {
    std::wstring fieldId;
    std::wstring label;
    std::wstring controlType;
    bool required = false;
    std::vector<std::wstring> options;
    RECT rect = {};
    std::wstring source;
    double confidence = 0.0;
    std::wstring recommendedAction;
};

struct FormControlResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring matchedBy;
    int matchCount = 0;
    FormControl control;
    std::vector<FormControl> candidates;
};

// Result of reading every recognizable form control from a local HTML/DOM-like
// fixture. Added in v3.3.6 so the Decision Task Runtime can read page context
// (all candidate controls plus the raw page text) without changing the existing
// single-field ResolveFormControlFromHtml behavior.
struct FormControlsResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring rawContent;
    std::vector<FormControl> controls;
};

std::wstring RecommendedFormAction(const std::wstring& controlType);
std::wstring FormControlJson(const FormControl& control);
std::wstring FormControlCandidatesJson(const std::vector<FormControl>& controls);
FormControlResult ResolveFormControlFromHtml(
    const std::wstring& htmlPath,
    const std::wstring& fieldId,
    const std::wstring& label,
    double minConfidence);

// Loads and parses all controls from a local HTML/DOM-like fixture. This is a
// read-only, compatible addition that reuses the existing parser; it does not
// send input or change permission/safety behavior.
FormControlsResult LoadFormControlsFromHtml(const std::wstring& htmlPath);
