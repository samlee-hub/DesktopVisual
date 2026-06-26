#pragma once

#include <windows.h>

#include <string>

struct BrowserSurfaceNormalizeOptions {
    std::wstring title;
    std::wstring mode = L"conservative";
    std::wstring guardResultJson;
};

struct BrowserSurfaceNormalizeResult {
    bool ok = true;
    std::wstring stopCode;
    std::wstring reason;
    HWND hwnd = nullptr;
    std::wstring title;
    std::wstring process;
    bool escSent = false;
    bool overlayClosed = false;
    bool blockerStillPresent = false;
    bool activeProtectionDetected = false;
    bool automationDetected = false;
    bool loadingOrOverlayBlocking = false;
};

BrowserSurfaceNormalizeOptions ParseBrowserSurfaceNormalizeOptionsFromArgs(int argc, wchar_t** argv);
bool BrowserNormalizeBeforeActionRequested(int argc, wchar_t** argv);
std::wstring BrowserNormalizeModeFromArgs(int argc, wchar_t** argv);
BrowserSurfaceNormalizeResult NormalizeBrowserSurface(const BrowserSurfaceNormalizeOptions& options);
std::wstring BrowserSurfaceNormalizeResultJson(const BrowserSurfaceNormalizeResult& result);
