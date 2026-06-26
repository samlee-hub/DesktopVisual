#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct GlobalFrameForegroundMetadata {
    HWND hwnd = nullptr;
    DWORD pid = 0;
    std::wstring title;
    std::wstring processName;
    RECT rect = {};
};

struct GlobalDpiAwareFrameResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring outPath;
    std::wstring format;
    RECT virtualScreenRect = {};
    int physicalWidth = 0;
    int physicalHeight = 0;
    std::wstring dpiAwareness;
    GlobalFrameForegroundMetadata foreground;
    POINT cursorPosition = {};
    long long durationMs = 0;
    std::wstring metadataPath;
    bool canBeFinalEvidence = true;
    bool frameCacheHit = false;
    long long frameCacheValidMs = 0;
    bool frameInvalidatedByAction = false;
    bool frameInvalidatedByWindowChange = false;
    bool frameReusedForPlanning = false;
    bool newGlobalFrameForFinalVerification = false;
};

struct GlobalFrameCache {
    bool hasFrame = false;
    bool invalidatedByAction = false;
    GlobalDpiAwareFrameResult frame;
    ULONGLONG capturedTick = 0;
    HWND foregroundHwnd = nullptr;
    RECT foregroundRect = {};
};

bool set_process_dpi_awareness_per_monitor_v2(std::wstring& dpiAwareness, std::wstring& error);
GlobalDpiAwareFrameResult capture_virtual_desktop(const std::wstring& outPath, const std::wstring& format);
GlobalDpiAwareFrameResult capture_full_desktop_dpi_aware(const std::wstring& outPath, const std::wstring& format, bool includeMetadata);
GlobalDpiAwareFrameResult capture_full_desktop_dpi_aware_cached(
    GlobalFrameCache& cache,
    const std::wstring& outPath,
    const std::wstring& format,
    bool includeMetadata,
    bool forceNewFrame,
    bool finalVerification);
void invalidate_global_frame_cache_by_action(GlobalFrameCache& cache);
POINT capture_cursor_position();
GlobalFrameForegroundMetadata capture_foreground_window_metadata();
bool write_png(HBITMAP bitmap, const std::wstring& outPath, std::wstring& error);
bool write_bmp(HBITMAP bitmap, const std::wstring& outPath, std::wstring& error);
bool write_frame_metadata_json(const GlobalDpiAwareFrameResult& result, const std::wstring& metadataPath, std::wstring& error);
bool verify_frame_covers_virtual_screen(const GlobalDpiAwareFrameResult& result);
std::wstring GlobalDpiAwareFrameDataJson(const GlobalDpiAwareFrameResult& result);
