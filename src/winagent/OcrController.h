#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct OcrWord {
    std::wstring text;
    RECT boundingBox = {};
    double confidence = -1.0;
};

struct OcrLine {
    std::wstring text;
    RECT boundingBox = {};
    std::vector<OcrWord> words;
};

struct OcrResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring fullText;
    std::wstring language;
    std::vector<OcrLine> lines;
    std::vector<OcrWord> allWords;
    std::wstring screenshotPath;
    std::wstring coordinateSpace;
};

struct OcrTextResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring matchedText;
    RECT boundingBox = {};
    double confidence = -1.0;
    std::wstring coordinateSpace;
    std::wstring screenshotPath;
    int matchCount = 0;
    std::vector<OcrTextResult> allMatches;
};

struct OcrCapability {
    bool available = false;
    std::wstring engine;
    std::wstring languages;
};

OcrCapability GetOcrCapability();
OcrResult RecognizeBgraFrame(
    const std::vector<unsigned char>& pixels,
    int width,
    int height,
    int stride,
    const std::wstring& coordinateSpace,
    const std::wstring& sourcePath);
OcrResult RecognizeImageFileForBenchmark(const std::wstring& imagePath, const std::wstring& coordinateSpace);
OcrResult ReadWindowText(HWND hwnd, const std::wstring& language);
OcrResult ReadRegionText(HWND hwnd, int clientX, int clientY, int width, int height);
OcrResult ReadScreenRegionText(int screenX, int screenY, int width, int height);
OcrTextResult FindTextInWindow(HWND hwnd, const std::wstring& text,
    const std::wstring& matchMode = L"contains", bool caseSensitive = false, int index = -1);
OcrTextResult WaitForText(HWND hwnd, const std::wstring& text, int timeoutMs, int intervalMs = 300);
OcrTextResult AssertTextContains(HWND hwnd, const std::wstring& text);
