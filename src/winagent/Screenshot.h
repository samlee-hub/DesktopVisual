#pragma once

#include <windows.h>

#include <string>

struct ScreenshotResult {
    bool ok = false;
    std::wstring method;
    std::wstring format;
    std::wstring error;
};

ScreenshotResult CaptureWindowToBmp(HWND hwnd, const std::wstring& outputPath);
ScreenshotResult CaptureWindowToFile(HWND hwnd, const std::wstring& outputPath, const std::wstring& format);
