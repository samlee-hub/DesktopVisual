#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct FrameWindowMetadata {
    HWND hwnd = nullptr;
    DWORD pid = 0;
    std::wstring title;
    std::wstring processName;
    RECT rect = {};
};

struct FullScreenFrame {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring frameId;
    std::wstring screenshotId;
    std::wstring capturedAt;
    int screenWidth = 0;
    int screenHeight = 0;
    int stride = 0;
    double coordinateScale = 1.0;
    std::wstring pixelFormat = L"BGRA32";
    size_t byteSize = 0;
    std::wstring source = L"full_screen";
    std::wstring evidencePngPath;
    std::wstring evidenceWriteStatus = L"pending";
    std::wstring contentHash;
    std::wstring originatingCommand;
    FrameWindowMetadata foreground;
    RECT virtualScreenRect = {};
    std::wstring dpiAwareness;
    std::wstring metadataPath;
    std::wstring rawFrameCachePath;
    long long durationMs = 0;
    bool frameInMemory = true;
    bool fullScreenCapture = true;
    bool asyncEvidenceWrite = true;
    bool backendCaptureUsed = false;
    std::vector<unsigned char> pixels;
};

struct FrameFlushResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    int pendingBefore = 0;
    int flushedCount = 0;
    int failedCount = 0;
    std::vector<std::wstring> frameIds;
    std::vector<std::wstring> evidencePaths;
};

std::wstring FrameRegistryRoot();
std::wstring FrameRegistryMetadataRoot();
std::wstring FrameRegistryRawRoot();
std::wstring FrameEvidenceRoot();
std::wstring FrameVlmTransportRoot();
std::wstring FrameContentHash(const std::vector<unsigned char>& pixels);

FullScreenFrame CaptureFullScreenFrameToRegistry(const std::wstring& originatingCommand, bool asyncEvidenceWrite);
bool LoadFullScreenFrameFromRegistry(
    const std::wstring& frameId,
    FullScreenFrame& frame,
    std::wstring& errorCode,
    std::wstring& errorMessage);
FrameFlushResult FlushFrameEvidence(const std::wstring& frameId, bool allPending, bool simulateFailure);
bool WriteFullScreenFrameMetadata(const FullScreenFrame& frame, std::wstring& error);
bool WriteFramePngFromBgra(
    const std::vector<unsigned char>& pixels,
    int width,
    int height,
    int stride,
    const std::wstring& outPath,
    std::wstring& error);
FullScreenFrame CropFullScreenFrame(const FullScreenFrame& frame, const RECT& screenRect);
std::vector<std::wstring> ListRegisteredFrameIds();
std::wstring FullScreenFrameDataJson(const FullScreenFrame& frame);
std::wstring FrameFlushDataJson(const FrameFlushResult& result);
