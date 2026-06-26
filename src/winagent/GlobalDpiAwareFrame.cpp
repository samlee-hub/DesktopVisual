#include "GlobalDpiAwareFrame.h"

#include "SimpleJson.h"
#include "WindowFinder.h"

#include <gdiplus.h>
#include <tlhelp32.h>
#include <wincodec.h>

#include <algorithm>
#include <cstdio>
#include <sstream>
#include <vector>

namespace {

long long Elapsed(ULONGLONG start) {
    return static_cast<long long>(GetTickCount64() - start);
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring HwndJson(HWND hwnd) {
    return hwnd ? simplejson::Quote(FormatHwnd(hwnd)) : L"null";
}

std::wstring ProcessNameForPidLocal(DWORD pid) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return L"";
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    std::wstring name;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == pid) {
                name = entry.szExeFile;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return name;
}

std::wstring WindowTitle(HWND hwnd) {
    int length = GetWindowTextLengthW(hwnd);
    if (length <= 0) return L"";
    std::wstring title(static_cast<size_t>(length) + 1, L'\0');
    int copied = GetWindowTextW(hwnd, title.data(), length + 1);
    title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    return title;
}

RECT VirtualScreenRect() {
    RECT rect{
        GetSystemMetrics(SM_XVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN),
        GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    return rect;
}

bool SaveBitmapBytes(HBITMAP bitmap, const std::wstring& outputPath, std::wstring& error) {
    BITMAP bitmapInfo = {};
    if (!GetObjectW(bitmap, sizeof(bitmapInfo), &bitmapInfo)) {
        error = L"GetObjectW failed for bitmap.";
        return false;
    }

    BITMAPINFOHEADER header = {};
    header.biSize = sizeof(BITMAPINFOHEADER);
    header.biWidth = bitmapInfo.bmWidth;
    header.biHeight = -bitmapInfo.bmHeight;
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;

    const int stride = bitmapInfo.bmWidth * 4;
    const DWORD imageSize = static_cast<DWORD>(stride * bitmapInfo.bmHeight);
    std::vector<unsigned char> pixels(imageSize);

    HDC screenDc = GetDC(nullptr);
    if (!screenDc) {
        error = L"GetDC failed while saving bitmap.";
        return false;
    }
    int gotBits = GetDIBits(screenDc, bitmap, 0, static_cast<UINT>(bitmapInfo.bmHeight), pixels.data(), reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS);
    ReleaseDC(nullptr, screenDc);
    if (gotBits == 0) {
        error = L"GetDIBits failed.";
        return false;
    }

    BITMAPFILEHEADER fileHeader = {};
    fileHeader.bfType = 0x4D42;
    fileHeader.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
    fileHeader.bfSize = fileHeader.bfOffBits + imageSize;

    FILE* file = nullptr;
    if (_wfopen_s(&file, outputPath.c_str(), L"wb") != 0 || !file) {
        error = L"Could not open output BMP file.";
        return false;
    }
    bool ok = fwrite(&fileHeader, sizeof(fileHeader), 1, file) == 1 &&
              fwrite(&header, sizeof(header), 1, file) == 1 &&
              fwrite(pixels.data(), pixels.size(), 1, file) == 1;
    fclose(file);
    if (!ok) error = L"Failed while writing BMP data.";
    return ok;
}

int GetEncoderClsid(const WCHAR* format, CLSID* clsid) {
    UINT count = 0;
    UINT size = 0;
    Gdiplus::GetImageEncodersSize(&count, &size);
    if (size == 0) return -1;
    std::vector<BYTE> buffer(size);
    auto* info = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
    if (Gdiplus::GetImageEncoders(count, size, info) != Gdiplus::Ok) return -1;
    for (UINT i = 0; i < count; ++i) {
        if (wcscmp(info[i].MimeType, format) == 0) {
            *clsid = info[i].Clsid;
            return static_cast<int>(i);
        }
    }
    return -1;
}

std::wstring NormalizeFormat(std::wstring format, const std::wstring& outPath) {
    std::transform(format.begin(), format.end(), format.begin(), [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
    if (format.empty()) {
        std::wstring lower = outPath;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
        if (lower.size() >= 4 && lower.substr(lower.size() - 4) == L".png") return L"png";
        return L"bmp";
    }
    return format;
}

template <typename T>
void SafeRelease(T*& value) {
    if (value) {
        value->Release();
        value = nullptr;
    }
}

}  // namespace

bool set_process_dpi_awareness_per_monitor_v2(std::wstring& dpiAwareness, std::wstring& error) {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    auto setContext = user32 ? reinterpret_cast<BOOL(WINAPI*)(DPI_AWARENESS_CONTEXT)>(GetProcAddress(user32, "SetProcessDpiAwarenessContext")) : nullptr;
    if (setContext) {
        if (setContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {
            dpiAwareness = L"per_monitor_v2";
            return true;
        }
        DWORD code = GetLastError();
        if (code == ERROR_ACCESS_DENIED) {
            dpiAwareness = L"per_monitor_v2_or_existing_dpi_aware";
            return true;
        }
    }
    if (SetProcessDPIAware()) {
        dpiAwareness = L"system_dpi_aware";
        return true;
    }
    error = L"Could not set DPI awareness.";
    dpiAwareness = L"unknown";
    return false;
}

POINT capture_cursor_position() {
    POINT point = {};
    GetCursorPos(&point);
    return point;
}

GlobalFrameForegroundMetadata capture_foreground_window_metadata() {
    GlobalFrameForegroundMetadata metadata;
    metadata.hwnd = GetForegroundWindow();
    if (!metadata.hwnd) return metadata;
    GetWindowThreadProcessId(metadata.hwnd, &metadata.pid);
    GetWindowRect(metadata.hwnd, &metadata.rect);
    metadata.title = WindowTitle(metadata.hwnd);
    metadata.processName = ProcessNameForPidLocal(metadata.pid);
    return metadata;
}

bool write_bmp(HBITMAP bitmap, const std::wstring& outPath, std::wstring& error) {
    return SaveBitmapBytes(bitmap, outPath, error);
}

bool write_png(HBITMAP bitmap, const std::wstring& outPath, std::wstring& error) {
    BITMAP bitmapInfo = {};
    if (!GetObjectW(bitmap, sizeof(bitmapInfo), &bitmapInfo)) {
        error = L"GetObjectW failed for bitmap.";
        return false;
    }

    BITMAPINFOHEADER header = {};
    header.biSize = sizeof(BITMAPINFOHEADER);
    header.biWidth = bitmapInfo.bmWidth;
    header.biHeight = -bitmapInfo.bmHeight;
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;

    const UINT stride = static_cast<UINT>(bitmapInfo.bmWidth * 4);
    const UINT imageSize = stride * static_cast<UINT>(bitmapInfo.bmHeight);
    std::vector<BYTE> pixels(imageSize);

    HDC screenDc = GetDC(nullptr);
    if (!screenDc) {
        error = L"GetDC failed while preparing PNG pixels.";
        return false;
    }
    int gotBits = GetDIBits(screenDc, bitmap, 0, static_cast<UINT>(bitmapInfo.bmHeight), pixels.data(), reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS);
    ReleaseDC(nullptr, screenDc);
    if (gotBits == 0) {
        error = L"GetDIBits failed while preparing PNG pixels.";
        return false;
    }

    HRESULT initHr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    bool shouldUninit = SUCCEEDED(initHr);
    if (FAILED(initHr) && initHr != RPC_E_CHANGED_MODE) {
        error = L"COM initialization failed for PNG encoder.";
        return false;
    }

    IWICImagingFactory* factory = nullptr;
    IWICBitmapEncoder* encoder = nullptr;
    IWICBitmapFrameEncode* frame = nullptr;
    IWICStream* stream = nullptr;
    IPropertyBag2* propertyBag = nullptr;

    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
    if (SUCCEEDED(hr)) hr = factory->CreateStream(&stream);
    if (SUCCEEDED(hr)) hr = stream->InitializeFromFilename(outPath.c_str(), GENERIC_WRITE);
    if (SUCCEEDED(hr)) hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
    if (SUCCEEDED(hr)) hr = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(&frame, &propertyBag);
    if (SUCCEEDED(hr)) hr = frame->Initialize(propertyBag);
    if (SUCCEEDED(hr)) hr = frame->SetSize(static_cast<UINT>(bitmapInfo.bmWidth), static_cast<UINT>(bitmapInfo.bmHeight));
    WICPixelFormatGUID pixelFormat = GUID_WICPixelFormat32bppBGRA;
    if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&pixelFormat);
    if (SUCCEEDED(hr) && pixelFormat != GUID_WICPixelFormat32bppBGRA) {
        hr = E_FAIL;
    }
    if (SUCCEEDED(hr)) hr = frame->WritePixels(static_cast<UINT>(bitmapInfo.bmHeight), stride, imageSize, pixels.data());
    if (SUCCEEDED(hr)) hr = frame->Commit();
    if (SUCCEEDED(hr)) hr = encoder->Commit();

    SafeRelease(propertyBag);
    SafeRelease(frame);
    SafeRelease(encoder);
    SafeRelease(stream);
    SafeRelease(factory);
    if (shouldUninit) {
        CoUninitialize();
    }

    if (FAILED(hr)) {
        error = L"WIC PNG encoder failed.";
        return false;
    }
    return true;
}

GlobalDpiAwareFrameResult capture_virtual_desktop(const std::wstring& outPath, const std::wstring& format) {
    ULONGLONG start = GetTickCount64();
    GlobalDpiAwareFrameResult result;
    result.outPath = outPath;
    result.format = NormalizeFormat(format, outPath);
    result.virtualScreenRect = VirtualScreenRect();
    result.physicalWidth = result.virtualScreenRect.right - result.virtualScreenRect.left;
    result.physicalHeight = result.virtualScreenRect.bottom - result.virtualScreenRect.top;
    result.cursorPosition = capture_cursor_position();
    result.foreground = capture_foreground_window_metadata();
    result.canBeFinalEvidence = true;

    if (result.physicalWidth <= 0 || result.physicalHeight <= 0) {
        result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        result.errorMessage = L"Virtual screen rectangle is empty.";
        result.durationMs = Elapsed(start);
        return result;
    }

    HDC screenDc = GetDC(nullptr);
    if (!screenDc) {
        result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        result.errorMessage = L"GetDC failed.";
        result.durationMs = Elapsed(start);
        return result;
    }
    HDC memoryDc = CreateCompatibleDC(screenDc);
    HBITMAP bitmap = CreateCompatibleBitmap(screenDc, result.physicalWidth, result.physicalHeight);
    if (!memoryDc || !bitmap) {
        if (bitmap) DeleteObject(bitmap);
        if (memoryDc) DeleteDC(memoryDc);
        ReleaseDC(nullptr, screenDc);
        result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        result.errorMessage = L"Could not allocate capture bitmap.";
        result.durationMs = Elapsed(start);
        return result;
    }
    HGDIOBJ old = SelectObject(memoryDc, bitmap);
    BOOL copied = BitBlt(
        memoryDc,
        0,
        0,
        result.physicalWidth,
        result.physicalHeight,
        screenDc,
        result.virtualScreenRect.left,
        result.virtualScreenRect.top,
        SRCCOPY | CAPTUREBLT);
    SelectObject(memoryDc, old);
    std::wstring saveError;
    if (!copied) {
        result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        result.errorMessage = L"BitBlt failed for virtual desktop.";
    } else if (result.format == L"png") {
        result.ok = write_png(bitmap, outPath, saveError);
    } else {
        result.format = L"bmp";
        result.ok = write_bmp(bitmap, outPath, saveError);
    }
    if (!result.ok && result.errorCode.empty()) {
        result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        result.errorMessage = saveError.empty() ? L"Could not write global screenshot." : saveError;
    }
    DeleteObject(bitmap);
    DeleteDC(memoryDc);
    ReleaseDC(nullptr, screenDc);
    result.durationMs = Elapsed(start);
    return result;
}

GlobalDpiAwareFrameResult capture_full_desktop_dpi_aware(const std::wstring& outPath, const std::wstring& format, bool includeMetadata) {
    std::wstring dpi;
    std::wstring error;
    if (!set_process_dpi_awareness_per_monitor_v2(dpi, error)) {
        GlobalDpiAwareFrameResult failed;
        failed.ok = false;
        failed.errorCode = L"FAIL_GLOBAL_SCREENSHOT_DPI_AWARENESS";
        failed.errorMessage = error;
        failed.dpiAwareness = dpi;
        failed.outPath = outPath;
        failed.format = NormalizeFormat(format, outPath);
        return failed;
    }
    GlobalDpiAwareFrameResult result = capture_virtual_desktop(outPath, format);
    result.dpiAwareness = dpi;
    if (result.ok && !verify_frame_covers_virtual_screen(result)) {
        result.ok = false;
        result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        result.errorMessage = L"Captured frame did not cover the virtual screen.";
    }
    if (result.ok && includeMetadata) {
        result.metadataPath = outPath + L".metadata.json";
        std::wstring metaError;
        if (!write_frame_metadata_json(result, result.metadataPath, metaError)) {
            result.ok = false;
            result.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
            result.errorMessage = metaError;
        }
    }
    return result;
}

bool verify_frame_covers_virtual_screen(const GlobalDpiAwareFrameResult& result) {
    RECT expected = VirtualScreenRect();
    return result.physicalWidth == (expected.right - expected.left) &&
           result.physicalHeight == (expected.bottom - expected.top) &&
           result.virtualScreenRect.left == expected.left &&
           result.virtualScreenRect.top == expected.top &&
           result.virtualScreenRect.right == expected.right &&
           result.virtualScreenRect.bottom == expected.bottom;
}

void invalidate_global_frame_cache_by_action(GlobalFrameCache& cache) {
    cache.invalidatedByAction = true;
}

GlobalDpiAwareFrameResult capture_full_desktop_dpi_aware_cached(
    GlobalFrameCache& cache,
    const std::wstring& outPath,
    const std::wstring& format,
    bool includeMetadata,
    bool forceNewFrame,
    bool finalVerification) {
    GlobalFrameForegroundMetadata foreground = capture_foreground_window_metadata();
    bool windowChanged = cache.hasFrame &&
        (foreground.hwnd != cache.foregroundHwnd ||
         foreground.rect.left != cache.foregroundRect.left ||
         foreground.rect.top != cache.foregroundRect.top ||
         foreground.rect.right != cache.foregroundRect.right ||
         foreground.rect.bottom != cache.foregroundRect.bottom);
    if (cache.hasFrame && !forceNewFrame && !finalVerification && !cache.invalidatedByAction && !windowChanged) {
        GlobalDpiAwareFrameResult reused = cache.frame;
        reused.frameCacheHit = true;
        reused.frameCacheValidMs = static_cast<long long>(GetTickCount64() - cache.capturedTick);
        reused.frameInvalidatedByAction = false;
        reused.frameInvalidatedByWindowChange = false;
        reused.frameReusedForPlanning = true;
        reused.newGlobalFrameForFinalVerification = false;
        return reused;
    }

    GlobalDpiAwareFrameResult fresh = capture_full_desktop_dpi_aware(outPath, format, includeMetadata);
    fresh.frameCacheHit = false;
    fresh.frameCacheValidMs = 0;
    fresh.frameInvalidatedByAction = cache.invalidatedByAction;
    fresh.frameInvalidatedByWindowChange = windowChanged;
    fresh.frameReusedForPlanning = false;
    fresh.newGlobalFrameForFinalVerification = finalVerification;
    if (fresh.ok) {
        cache.hasFrame = true;
        cache.invalidatedByAction = false;
        cache.frame = fresh;
        cache.capturedTick = GetTickCount64();
        cache.foregroundHwnd = fresh.foreground.hwnd;
        cache.foregroundRect = fresh.foreground.rect;
    }
    return fresh;
}

bool write_frame_metadata_json(const GlobalDpiAwareFrameResult& result, const std::wstring& metadataPath, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, metadataPath.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open frame metadata file.";
        return false;
    }
    std::wstring json = GlobalDpiAwareFrameDataJson(result);
    bool ok = fputws(json.c_str(), file) >= 0;
    fclose(file);
    if (!ok) error = L"Could not write frame metadata file.";
    return ok;
}

std::wstring GlobalDpiAwareFrameDataJson(const GlobalDpiAwareFrameResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << BoolJson(result.ok)
         << L",\"command\":\"global-screenshot\""
         << L",\"out\":" << simplejson::Quote(result.outPath)
         << L",\"format\":" << simplejson::Quote(result.format)
         << L",\"virtual_screen_rect\":" << RectJson(result.virtualScreenRect)
         << L",\"physical_width\":" << result.physicalWidth
         << L",\"physical_height\":" << result.physicalHeight
         << L",\"dpi_awareness\":" << simplejson::Quote(result.dpiAwareness)
         << L",\"foreground_window\":{\"hwnd\":" << HwndJson(result.foreground.hwnd)
         << L",\"pid\":" << result.foreground.pid
         << L",\"title\":" << simplejson::Quote(result.foreground.title)
         << L",\"process_name\":" << simplejson::Quote(result.foreground.processName)
         << L",\"rect\":" << RectJson(result.foreground.rect) << L"}"
         << L",\"cursor_position\":{\"x\":" << result.cursorPosition.x
         << L",\"y\":" << result.cursorPosition.y << L"}"
         << L",\"duration_ms\":" << result.durationMs
         << L",\"metadata_path\":" << simplejson::Quote(result.metadataPath)
         << L",\"capture_scope\":\"global_desktop\""
         << L",\"can_be_final_evidence\":" << BoolJson(result.canBeFinalEvidence)
         << L",\"frame_cache_hit\":" << BoolJson(result.frameCacheHit)
         << L",\"frame_cache_valid_ms\":" << result.frameCacheValidMs
         << L",\"frame_invalidated_by_action\":" << BoolJson(result.frameInvalidatedByAction)
         << L",\"frame_invalidated_by_window_change\":" << BoolJson(result.frameInvalidatedByWindowChange)
         << L",\"frame_reused_for_planning\":" << BoolJson(result.frameReusedForPlanning)
         << L",\"new_global_frame_for_final_verification\":" << BoolJson(result.newGlobalFrameForFinalVerification);
    if (!result.errorCode.empty()) {
        json << L",\"error\":{\"code\":" << simplejson::Quote(result.errorCode)
             << L",\"message\":" << simplejson::Quote(result.errorMessage) << L"}";
    }
    json << L"}";
    return json.str();
}
