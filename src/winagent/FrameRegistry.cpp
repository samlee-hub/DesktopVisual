#include "FrameRegistry.h"

#include "GlobalDpiAwareFrame.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "WindowFinder.h"

#include <wincodec.h>

#include <algorithm>
#include <cstdio>
#include <iomanip>
#include <sstream>

namespace {

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring RectJsonLocal(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring HwndJsonLocal(HWND hwnd) {
    return hwnd ? JsonString(FormatHwnd(hwnd)) : L"null";
}

std::wstring SanitizeId(std::wstring value) {
    for (auto& ch : value) {
        bool ok = (ch >= L'a' && ch <= L'z') ||
            (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'0' && ch <= L'9') ||
            ch == L'_' || ch == L'-';
        if (!ok) ch = L'_';
    }
    if (value.empty()) return L"frame";
    return value;
}

std::wstring TimestampForId() {
    SYSTEMTIME t = {};
    GetLocalTime(&t);
    wchar_t buffer[64] = {};
    swprintf_s(
        buffer,
        L"%04u%02u%02u_%02u%02u%02u_%03u",
        t.wYear,
        t.wMonth,
        t.wDay,
        t.wHour,
        t.wMinute,
        t.wSecond,
        t.wMilliseconds);
    return buffer;
}

bool WriteBinaryFile(const std::wstring& path, const std::vector<unsigned char>& bytes, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || !file) {
        error = L"Could not open binary output file.";
        return false;
    }
    bool ok = bytes.empty() || fwrite(bytes.data(), bytes.size(), 1, file) == 1;
    fclose(file);
    if (!ok) error = L"Could not write binary output file.";
    return ok;
}

bool ReadBinaryFile(const std::wstring& path, std::vector<unsigned char>& bytes, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        error = L"Could not open binary input file.";
        return false;
    }
    _fseeki64(file, 0, SEEK_END);
    __int64 size = _ftelli64(file);
    _fseeki64(file, 0, SEEK_SET);
    if (size < 0) {
        fclose(file);
        error = L"Could not determine binary input file size.";
        return false;
    }
    bytes.assign(static_cast<size_t>(size), 0);
    bool ok = size == 0 || fread(bytes.data(), bytes.size(), 1, file) == 1;
    fclose(file);
    if (!ok) error = L"Could not read binary input file.";
    return ok;
}

bool ReadTextFileLocal(const std::wstring& path, std::wstring& text, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"r, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open text input file.";
        return false;
    }
    wchar_t buffer[4096] = {};
    text.clear();
    while (fgetws(buffer, static_cast<int>(std::size(buffer)), file)) {
        text += buffer;
    }
    fclose(file);
    if (!text.empty() && text[0] == 0xFEFF) {
        text.erase(text.begin());
    }
    return true;
}

std::wstring MetadataPathForFrameId(const std::wstring& frameId) {
    return FrameRegistryMetadataRoot() + L"\\" + SanitizeId(frameId) + L".json";
}

std::wstring RawPathForFrameId(const std::wstring& frameId) {
    return FrameRegistryRawRoot() + L"\\" + SanitizeId(frameId) + L".bgra";
}

std::wstring EvidencePathForScreenshotId(const std::wstring& screenshotId) {
    return FrameEvidenceRoot() + L"\\" + SanitizeId(screenshotId) + L".png";
}

FrameWindowMetadata FromGlobalForeground(const GlobalFrameForegroundMetadata& source) {
    FrameWindowMetadata value;
    value.hwnd = source.hwnd;
    value.pid = source.pid;
    value.title = source.title;
    value.processName = source.processName;
    value.rect = source.rect;
    return value;
}

void EnsureFrameDirectories() {
    EnsureDirectoryPath(FrameRegistryRoot());
    EnsureDirectoryPath(FrameRegistryMetadataRoot());
    EnsureDirectoryPath(FrameRegistryRawRoot());
    EnsureDirectoryPath(FrameEvidenceRoot());
    EnsureDirectoryPath(FrameVlmTransportRoot());
}

bool FileExistsLocal(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

RECT ParseRect(const simplejson::Value& object, const std::wstring& key) {
    RECT rect = {};
    const simplejson::Value* value = simplejson::Find(object, key);
    if (!value || !value->IsObject()) return rect;
    rect.left = simplejson::GetInt(*value, L"left", 0);
    rect.top = simplejson::GetInt(*value, L"top", 0);
    rect.right = simplejson::GetInt(*value, L"right", 0);
    rect.bottom = simplejson::GetInt(*value, L"bottom", 0);
    return rect;
}

FrameWindowMetadata ParseForeground(const simplejson::Value& object) {
    FrameWindowMetadata foreground;
    const simplejson::Value* value = simplejson::Find(object, L"foreground_window");
    if (!value || !value->IsObject()) return foreground;
    foreground.pid = static_cast<DWORD>(simplejson::GetInt(*value, L"pid", 0));
    foreground.title = simplejson::GetString(*value, L"title");
    foreground.processName = simplejson::GetString(*value, L"process_name");
    foreground.rect = ParseRect(*value, L"rect");
    std::wstring hwndText = simplejson::GetString(*value, L"hwnd");
    if (!hwndText.empty()) {
        unsigned long long hwndValue = 0;
        try {
            hwndValue = std::stoull(hwndText, nullptr, 0);
            foreground.hwnd = reinterpret_cast<HWND>(static_cast<uintptr_t>(hwndValue));
        } catch (...) {
            foreground.hwnd = nullptr;
        }
    }
    return foreground;
}

template <typename T>
void SafeRelease(T*& value) {
    if (value) {
        value->Release();
        value = nullptr;
    }
}

}  // namespace

std::wstring FrameRegistryRoot() {
    return ArtifactsPath(L"frame_registry");
}

std::wstring FrameRegistryMetadataRoot() {
    return FrameRegistryRoot() + L"\\metadata";
}

std::wstring FrameRegistryRawRoot() {
    return FrameRegistryRoot() + L"\\raw";
}

std::wstring FrameEvidenceRoot() {
    return ArtifactsPath(L"dev1.0.5_capture_ocr_performance_pipeline\\evidence_frames");
}

std::wstring FrameVlmTransportRoot() {
    return ArtifactsPath(L"dev1.0.5_capture_ocr_performance_pipeline\\vlm_transport");
}

std::wstring FrameContentHash(const std::vector<unsigned char>& pixels) {
    unsigned long long hash = 1469598103934665603ull;
    for (unsigned char byte : pixels) {
        hash ^= static_cast<unsigned long long>(byte);
        hash *= 1099511628211ull;
    }
    std::wstringstream stream;
    stream << std::hex << std::setw(16) << std::setfill(L'0') << hash;
    return stream.str();
}

FullScreenFrame CaptureFullScreenFrameToRegistry(const std::wstring& originatingCommand, bool asyncEvidenceWrite) {
    EnsureFrameDirectories();
    ULONGLONG start = GetTickCount64();
    FullScreenFrame frame;
    frame.originatingCommand = originatingCommand;
    frame.asyncEvidenceWrite = asyncEvidenceWrite;
    frame.evidenceWriteStatus = asyncEvidenceWrite ? L"pending" : L"written";
    frame.capturedAt = NowTimestamp();

    std::wstring dpiError;
    if (!set_process_dpi_awareness_per_monitor_v2(frame.dpiAwareness, dpiError)) {
        frame.errorCode = L"FAIL_GLOBAL_SCREENSHOT_DPI_AWARENESS";
        frame.errorMessage = dpiError;
        frame.durationMs = ElapsedMs(start);
        return frame;
    }

    frame.virtualScreenRect = {
        GetSystemMetrics(SM_XVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN),
        GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    frame.screenWidth = frame.virtualScreenRect.right - frame.virtualScreenRect.left;
    frame.screenHeight = frame.virtualScreenRect.bottom - frame.virtualScreenRect.top;
    frame.stride = frame.screenWidth * 4;
    frame.byteSize = static_cast<size_t>(frame.stride) * static_cast<size_t>(frame.screenHeight);
    frame.foreground = FromGlobalForeground(capture_foreground_window_metadata());

    if (frame.screenWidth <= 0 || frame.screenHeight <= 0) {
        frame.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        frame.errorMessage = L"Virtual screen rectangle is empty.";
        frame.durationMs = ElapsedMs(start);
        return frame;
    }

    HDC screenDc = GetDC(nullptr);
    if (!screenDc) {
        frame.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        frame.errorMessage = L"GetDC failed.";
        frame.durationMs = ElapsedMs(start);
        return frame;
    }
    HDC memoryDc = CreateCompatibleDC(screenDc);
    HBITMAP bitmap = CreateCompatibleBitmap(screenDc, frame.screenWidth, frame.screenHeight);
    if (!memoryDc || !bitmap) {
        if (bitmap) DeleteObject(bitmap);
        if (memoryDc) DeleteDC(memoryDc);
        ReleaseDC(nullptr, screenDc);
        frame.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        frame.errorMessage = L"Could not allocate capture bitmap.";
        frame.durationMs = ElapsedMs(start);
        return frame;
    }
    HGDIOBJ old = SelectObject(memoryDc, bitmap);
    BOOL copied = BitBlt(
        memoryDc,
        0,
        0,
        frame.screenWidth,
        frame.screenHeight,
        screenDc,
        frame.virtualScreenRect.left,
        frame.virtualScreenRect.top,
        SRCCOPY | CAPTUREBLT);
    SelectObject(memoryDc, old);
    ReleaseDC(nullptr, screenDc);

    if (!copied) {
        DeleteObject(bitmap);
        DeleteDC(memoryDc);
        frame.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        frame.errorMessage = L"BitBlt failed for virtual desktop.";
        frame.durationMs = ElapsedMs(start);
        return frame;
    }

    BITMAPINFOHEADER header = {};
    header.biSize = sizeof(BITMAPINFOHEADER);
    header.biWidth = frame.screenWidth;
    header.biHeight = -frame.screenHeight;
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;
    frame.pixels.assign(frame.byteSize, 0);
    HDC dibDc = GetDC(nullptr);
    int gotBits = GetDIBits(dibDc, bitmap, 0, static_cast<UINT>(frame.screenHeight), frame.pixels.data(), reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS);
    ReleaseDC(nullptr, dibDc);
    DeleteObject(bitmap);
    DeleteDC(memoryDc);

    if (gotBits == 0) {
        frame.errorCode = L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE";
        frame.errorMessage = L"GetDIBits failed for full-screen frame.";
        frame.durationMs = ElapsedMs(start);
        return frame;
    }

    frame.contentHash = FrameContentHash(frame.pixels);
    std::wstring idStamp = TimestampForId() + L"_" + frame.contentHash.substr(0, 8);
    frame.frameId = L"frame_" + idStamp;
    frame.screenshotId = L"screenshot_" + idStamp;
    frame.rawFrameCachePath = RawPathForFrameId(frame.frameId);
    frame.metadataPath = MetadataPathForFrameId(frame.frameId);
    frame.evidencePngPath = EvidencePathForScreenshotId(frame.screenshotId);

    std::wstring ioError;
    if (!WriteBinaryFile(frame.rawFrameCachePath, frame.pixels, ioError)) {
        frame.errorCode = L"FRAME_CACHE_WRITE_FAILED";
        frame.errorMessage = ioError;
        frame.durationMs = ElapsedMs(start);
        return frame;
    }

    if (!asyncEvidenceWrite) {
        std::wstring pngError;
        if (!WriteFramePngFromBgra(frame.pixels, frame.screenWidth, frame.screenHeight, frame.stride, frame.evidencePngPath, pngError)) {
            frame.evidenceWriteStatus = L"failed";
            frame.errorCode = L"EVIDENCE_FLUSH_FAILED";
            frame.errorMessage = pngError;
            frame.durationMs = ElapsedMs(start);
            WriteFullScreenFrameMetadata(frame, ioError);
            return frame;
        }
    }

    if (!WriteFullScreenFrameMetadata(frame, ioError)) {
        frame.errorCode = L"FRAME_METADATA_WRITE_FAILED";
        frame.errorMessage = ioError;
        frame.durationMs = ElapsedMs(start);
        return frame;
    }
    frame.ok = true;
    frame.durationMs = ElapsedMs(start);
    return frame;
}

bool LoadFullScreenFrameFromRegistry(
    const std::wstring& frameId,
    FullScreenFrame& frame,
    std::wstring& errorCode,
    std::wstring& errorMessage) {
    EnsureFrameDirectories();
    if (frameId.empty()) {
        errorCode = L"INVALID_ARGUMENT";
        errorMessage = L"frame_id is required.";
        return false;
    }
    std::wstring metadataPath = MetadataPathForFrameId(frameId);
    std::wstring text;
    std::wstring ioError;
    if (!ReadTextFileLocal(metadataPath, text, ioError)) {
        errorCode = L"FRAME_EXPIRED";
        errorMessage = L"Frame metadata was not found.";
        return false;
    }
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        errorCode = L"FRAME_METADATA_INVALID";
        errorMessage = parsed.error.empty() ? L"Frame metadata JSON is invalid." : parsed.error;
        return false;
    }
    frame.frameId = simplejson::GetString(parsed.root, L"frame_id");
    frame.screenshotId = simplejson::GetString(parsed.root, L"screenshot_id");
    frame.capturedAt = simplejson::GetString(parsed.root, L"captured_at");
    frame.screenWidth = simplejson::GetInt(parsed.root, L"screen_width", 0);
    frame.screenHeight = simplejson::GetInt(parsed.root, L"screen_height", 0);
    frame.stride = simplejson::GetInt(parsed.root, L"stride", frame.screenWidth * 4);
    frame.pixelFormat = simplejson::GetString(parsed.root, L"pixel_format", L"BGRA32");
    frame.byteSize = static_cast<size_t>(simplejson::GetInt(parsed.root, L"byte_size", 0));
    frame.source = simplejson::GetString(parsed.root, L"source", L"full_screen");
    frame.evidencePngPath = simplejson::GetString(parsed.root, L"evidence_png_path");
    frame.evidenceWriteStatus = simplejson::GetString(parsed.root, L"evidence_write_status", L"pending");
    frame.contentHash = simplejson::GetString(parsed.root, L"content_hash");
    frame.originatingCommand = simplejson::GetString(parsed.root, L"originating_command");
    frame.metadataPath = metadataPath;
    frame.rawFrameCachePath = simplejson::GetString(parsed.root, L"raw_frame_cache_path", RawPathForFrameId(frameId));
    frame.dpiAwareness = simplejson::GetString(parsed.root, L"dpi_scale");
    frame.virtualScreenRect = ParseRect(parsed.root, L"virtual_screen_rect");
    frame.foreground = ParseForeground(parsed.root);
    frame.frameInMemory = true;
    frame.fullScreenCapture = true;
    frame.asyncEvidenceWrite = simplejson::GetBool(parsed.root, L"async_evidence_write", true);
    frame.backendCaptureUsed = simplejson::GetBool(parsed.root, L"backend_capture_used", false);

    if (frame.frameId.empty()) frame.frameId = frameId;
    if (!FileExistsLocal(frame.rawFrameCachePath)) {
        errorCode = L"FRAME_EXPIRED";
        errorMessage = L"Frame raw byte cache is no longer available.";
        return false;
    }
    if (!ReadBinaryFile(frame.rawFrameCachePath, frame.pixels, ioError)) {
        errorCode = L"FRAME_EXPIRED";
        errorMessage = ioError;
        return false;
    }
    frame.byteSize = frame.pixels.size();
    frame.ok = true;
    return true;
}

FrameFlushResult FlushFrameEvidence(const std::wstring& frameId, bool allPending, bool simulateFailure) {
    FrameFlushResult result;
    if (simulateFailure) {
        result.errorCode = L"EVIDENCE_FLUSH_FAILED";
        result.errorMessage = L"Simulated evidence writer failure.";
        result.failedCount = 1;
        if (!frameId.empty()) result.frameIds.push_back(frameId);
        return result;
    }
    std::vector<std::wstring> ids = allPending ? ListRegisteredFrameIds() : std::vector<std::wstring>{frameId};
    for (const auto& id : ids) {
        if (id.empty()) continue;
        FullScreenFrame frame;
        std::wstring code;
        std::wstring message;
        if (!LoadFullScreenFrameFromRegistry(id, frame, code, message)) {
            ++result.failedCount;
            result.frameIds.push_back(id);
            continue;
        }
        if (frame.evidenceWriteStatus == L"pending") {
            ++result.pendingBefore;
        }
        std::wstring pngError;
        bool wrote = WriteFramePngFromBgra(frame.pixels, frame.screenWidth, frame.screenHeight, frame.stride, frame.evidencePngPath, pngError);
        result.frameIds.push_back(frame.frameId);
        result.evidencePaths.push_back(frame.evidencePngPath);
        if (wrote) {
            frame.evidenceWriteStatus = L"written";
            ++result.flushedCount;
            std::wstring metaError;
            WriteFullScreenFrameMetadata(frame, metaError);
        } else {
            frame.evidenceWriteStatus = L"failed";
            ++result.failedCount;
            std::wstring metaError;
            WriteFullScreenFrameMetadata(frame, metaError);
        }
    }
    result.ok = result.failedCount == 0;
    if (!result.ok) {
        result.errorCode = L"EVIDENCE_FLUSH_FAILED";
        result.errorMessage = L"One or more frame evidence PNG writes failed.";
    }
    return result;
}

bool WriteFullScreenFrameMetadata(const FullScreenFrame& frame, std::wstring& error) {
    EnsureFrameDirectories();
    FILE* file = nullptr;
    if (_wfopen_s(&file, frame.metadataPath.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open frame metadata file.";
        return false;
    }
    std::wstring json = FullScreenFrameDataJson(frame);
    bool ok = fputws(json.c_str(), file) >= 0;
    fclose(file);
    if (!ok) error = L"Could not write frame metadata file.";
    return ok;
}

bool WriteFramePngFromBgra(
    const std::vector<unsigned char>& pixels,
    int width,
    int height,
    int stride,
    const std::wstring& outPath,
    std::wstring& error) {
    if (width <= 0 || height <= 0 || stride < width * 4 || pixels.size() < static_cast<size_t>(stride) * static_cast<size_t>(height)) {
        error = L"Invalid BGRA frame dimensions.";
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
    if (SUCCEEDED(hr)) hr = frame->SetSize(static_cast<UINT>(width), static_cast<UINT>(height));
    WICPixelFormatGUID pixelFormat = GUID_WICPixelFormat32bppBGRA;
    if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&pixelFormat);
    if (SUCCEEDED(hr) && pixelFormat != GUID_WICPixelFormat32bppBGRA) hr = E_FAIL;
    if (SUCCEEDED(hr)) {
        hr = frame->WritePixels(
            static_cast<UINT>(height),
            static_cast<UINT>(stride),
            static_cast<UINT>(pixels.size()),
            const_cast<BYTE*>(pixels.data()));
    }
    if (SUCCEEDED(hr)) hr = frame->Commit();
    if (SUCCEEDED(hr)) hr = encoder->Commit();

    SafeRelease(propertyBag);
    SafeRelease(frame);
    SafeRelease(encoder);
    SafeRelease(stream);
    SafeRelease(factory);
    if (shouldUninit) CoUninitialize();

    if (FAILED(hr)) {
        error = L"WIC PNG encoder failed.";
        return false;
    }
    return true;
}

FullScreenFrame CropFullScreenFrame(const FullScreenFrame& frame, const RECT& screenRect) {
    FullScreenFrame crop = frame;
    crop.pixels.clear();
    RECT bounded = screenRect;
    bounded.left = (std::max)(bounded.left, frame.virtualScreenRect.left);
    bounded.top = (std::max)(bounded.top, frame.virtualScreenRect.top);
    bounded.right = (std::min)(bounded.right, frame.virtualScreenRect.right);
    bounded.bottom = (std::min)(bounded.bottom, frame.virtualScreenRect.bottom);
    int width = bounded.right - bounded.left;
    int height = bounded.bottom - bounded.top;
    if (width <= 0 || height <= 0) {
        crop.ok = false;
        crop.errorCode = L"INVALID_CROP_RECT";
        crop.errorMessage = L"Crop rectangle does not intersect the full-screen frame.";
        return crop;
    }
    crop.screenWidth = width;
    crop.screenHeight = height;
    crop.stride = width * 4;
    crop.virtualScreenRect = bounded;
    crop.byteSize = static_cast<size_t>(crop.stride) * static_cast<size_t>(height);
    crop.pixels.assign(crop.byteSize, 0);

    int sourceX = bounded.left - frame.virtualScreenRect.left;
    int sourceY = bounded.top - frame.virtualScreenRect.top;
    for (int row = 0; row < height; ++row) {
        size_t sourceOffset = static_cast<size_t>(sourceY + row) * static_cast<size_t>(frame.stride) + static_cast<size_t>(sourceX) * 4;
        size_t destOffset = static_cast<size_t>(row) * static_cast<size_t>(crop.stride);
        memcpy(crop.pixels.data() + destOffset, frame.pixels.data() + sourceOffset, static_cast<size_t>(width) * 4);
    }
    crop.contentHash = FrameContentHash(crop.pixels);
    crop.ok = true;
    return crop;
}

std::vector<std::wstring> ListRegisteredFrameIds() {
    EnsureFrameDirectories();
    std::vector<std::wstring> ids;
    std::wstring pattern = FrameRegistryMetadataRoot() + L"\\*.json";
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return ids;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            std::wstring name = data.cFileName;
            if (name.size() > 5 && name.substr(name.size() - 5) == L".json") {
                ids.push_back(name.substr(0, name.size() - 5));
            }
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);
    return ids;
}

std::wstring FullScreenFrameDataJson(const FullScreenFrame& frame) {
    std::wstringstream json;
    json << L"{\"ok\":" << BoolJson(frame.ok)
         << L",\"frame_id\":" << JsonString(frame.frameId)
         << L",\"screenshot_id\":" << JsonString(frame.screenshotId)
         << L",\"captured_at\":" << JsonString(frame.capturedAt)
         << L",\"screen_width\":" << frame.screenWidth
         << L",\"screen_height\":" << frame.screenHeight
         << L",\"stride\":" << frame.stride
         << L",\"dpi_scale\":" << JsonString(frame.dpiAwareness)
         << L",\"coordinate_scale\":" << frame.coordinateScale
         << L",\"pixel_format\":" << JsonString(frame.pixelFormat)
         << L",\"byte_size\":" << static_cast<unsigned long long>(frame.byteSize)
         << L",\"source\":" << JsonString(frame.source)
         << L",\"evidence_png_path\":" << JsonString(frame.evidencePngPath)
         << L",\"evidence_write_status\":" << JsonString(frame.evidenceWriteStatus)
         << L",\"hash\":" << JsonString(frame.contentHash)
         << L",\"content_hash\":" << JsonString(frame.contentHash)
         << L",\"originating_command\":" << JsonString(frame.originatingCommand)
         << L",\"foreground_window_hwnd\":" << HwndJsonLocal(frame.foreground.hwnd)
         << L",\"foreground_window_rect\":" << RectJsonLocal(frame.foreground.rect)
         << L",\"foreground_window\":{\"hwnd\":" << HwndJsonLocal(frame.foreground.hwnd)
         << L",\"pid\":" << frame.foreground.pid
         << L",\"title\":" << JsonString(frame.foreground.title)
         << L",\"process_name\":" << JsonString(frame.foreground.processName)
         << L",\"rect\":" << RectJsonLocal(frame.foreground.rect) << L"}"
         << L",\"virtual_screen_rect\":" << RectJsonLocal(frame.virtualScreenRect)
         << L",\"metadata_path\":" << JsonString(frame.metadataPath)
         << L",\"raw_frame_cache_path\":" << JsonString(frame.rawFrameCachePath)
         << L",\"duration_ms\":" << frame.durationMs
         << L",\"frame_in_memory\":" << BoolJson(frame.frameInMemory)
         << L",\"full_screen_capture\":" << BoolJson(frame.fullScreenCapture)
         << L",\"async_evidence_write\":" << BoolJson(frame.asyncEvidenceWrite)
         << L",\"backend_capture_used\":" << BoolJson(frame.backendCaptureUsed)
         << L",\"ocr_png_dependency_removed\":true";
    if (!frame.errorCode.empty()) {
        json << L",\"error\":{\"code\":" << JsonString(frame.errorCode)
             << L",\"message\":" << JsonString(frame.errorMessage) << L"}";
    }
    json << L"}";
    return json.str();
}

std::wstring FrameFlushDataJson(const FrameFlushResult& result) {
    std::wstringstream frameIds;
    frameIds << L"[";
    for (size_t i = 0; i < result.frameIds.size(); ++i) {
        if (i) frameIds << L",";
        frameIds << JsonString(result.frameIds[i]);
    }
    frameIds << L"]";
    std::wstringstream paths;
    paths << L"[";
    for (size_t i = 0; i < result.evidencePaths.size(); ++i) {
        if (i) paths << L",";
        paths << JsonString(result.evidencePaths[i]);
    }
    paths << L"]";
    std::wstringstream json;
    json << L"{\"pending_before\":" << result.pendingBefore
         << L",\"flushed_count\":" << result.flushedCount
         << L",\"failed_count\":" << result.failedCount
         << L",\"evidence_write_status\":" << JsonString(result.failedCount == 0 ? L"written" : L"failed")
         << L",\"frame_ids\":" << frameIds.str()
         << L",\"evidence_paths\":" << paths.str()
         << L",\"flush_barrier\":true";
    if (!result.errorCode.empty()) {
        json << L",\"error_code\":" << JsonString(result.errorCode)
             << L",\"error_message\":" << JsonString(result.errorMessage);
    }
    json << L"}";
    return json.str();
}
