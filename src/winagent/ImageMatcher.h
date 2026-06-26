#pragma once

#include <windows.h>

#include <string>

struct ImageMatchResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool matchFound = false;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    double score = 0.0;
    int matchCount = 0;
};

ImageMatchResult FindTemplateInBmp(
    const std::wstring& sourceBmpPath,
    const std::wstring& templateBmpPath,
    int tolerance);
