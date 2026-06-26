#include "OcrController.h"
#include "ProjectRoot.h"
#include "Screenshot.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cwctype>
#include <cstdio>
#include <sstream>
#include <string>
#include <vector>

// ===================================================================
// WinRT OCR availability check (compile-time)
// ===================================================================
#if defined(__has_include) && __has_include(<winrt/base.h>) && __has_include(<winrt/Windows.Media.Ocr.h>)
#define DESKTOPVISUAL_HAS_WINRT_OCR 1
#else
#define DESKTOPVISUAL_HAS_WINRT_OCR 0
#endif

#if DESKTOPVISUAL_HAS_WINRT_OCR
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#pragma comment(lib, "windowsapp")
#endif

namespace {

std::wstring ToLower(const std::wstring& value) {
    std::wstring result = value;
    std::transform(result.begin(), result.end(), result.begin(), ::towlower);
    return result;
}

std::wstring OcrArtifactBmpPath(const wchar_t* prefix) {
    EnsureDirectoryPath(ArtifactsPath());
    SYSTEMTIME now = {};
    GetLocalTime(&now);
    wchar_t path[MAX_PATH] = {};
    swprintf_s(
        path,
        L"%ls_%04u%02u%02u_%02u%02u%02u_%03u.bmp",
        prefix,
        now.wYear,
        now.wMonth,
        now.wDay,
        now.wHour,
        now.wMinute,
        now.wSecond,
        now.wMilliseconds);
    return ArtifactsPath(path);
}

#if DESKTOPVISUAL_HAS_WINRT_OCR

class WinRtApartment {
public:
    WinRtApartment() { winrt::init_apartment(winrt::apartment_type::single_threaded); }
};

OcrResult OcrResultUnavailable() {
    OcrResult result;
    result.errorCode = L"OCR_UNAVAILABLE";
    result.errorMessage = L"Windows OCR is not available on this system.";
    return result;
}

OcrTextResult OcrTextUnavailable(const std::wstring& text) {
    OcrTextResult result;
    result.errorCode = L"OCR_UNAVAILABLE";
    result.errorMessage = L"Windows OCR is not available on this system.";
    result.matchedText = text;
    result.coordinateSpace = L"screen";
    return result;
}

OcrTextResult OcrTextNotFound(const std::wstring& text, const std::wstring& screenshotPath) {
    OcrTextResult result;
    result.errorCode = L"LOCATOR_NOT_FOUND";
    result.errorMessage = L"OCR did not find text '" + text + L"'.";
    result.matchedText = text;
    result.coordinateSpace = L"window_bitmap";
    result.screenshotPath = screenshotPath;
    return result;
}

bool SaveBitmapToFileLocal(HBITMAP bitmap, const std::wstring& outputPath) {
    BITMAP bmp = {};
    if (GetObjectW(bitmap, sizeof(bmp), &bmp) == 0) {
        return false;
    }

    BITMAPINFOHEADER bi = {};
    bi.biSize = sizeof(BITMAPINFOHEADER);
    bi.biWidth = bmp.bmWidth;
    bi.biHeight = -bmp.bmHeight;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;

    const int stride = bmp.bmWidth * 4;
    std::vector<unsigned char> pixels(static_cast<size_t>(stride * bmp.bmHeight));

    HDC hdc = GetDC(nullptr);
    if (!hdc) {
        return false;
    }
    const int copied = GetDIBits(
        hdc,
        bitmap,
        0,
        static_cast<UINT>(bmp.bmHeight),
        pixels.data(),
        reinterpret_cast<BITMAPINFO*>(&bi),
        DIB_RGB_COLORS);
    ReleaseDC(nullptr, hdc);
    if (copied == 0) {
        return false;
    }

    BITMAPFILEHEADER fh = {};
    fh.bfType = 0x4D42;
    fh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
    fh.bfSize = fh.bfOffBits + static_cast<DWORD>(pixels.size());

    FILE* f = nullptr;
    if (_wfopen_s(&f, outputPath.c_str(), L"wb") != 0 || !f) {
        return false;
    }
    fwrite(&fh, sizeof(fh), 1, f);
    fwrite(&bi, sizeof(bi), 1, f);
    fwrite(pixels.data(), pixels.size(), 1, f);
    fclose(f);
    return true;
}

int ChooseOcrScale(const std::wstring& bmpPath) {
    HBITMAP source = static_cast<HBITMAP>(LoadImageW(
        nullptr,
        bmpPath.c_str(),
        IMAGE_BITMAP,
        0,
        0,
        LR_LOADFROMFILE | LR_CREATEDIBSECTION));
    if (!source) {
        return 1;
    }

    BITMAP bmp = {};
    GetObjectW(source, sizeof(bmp), &bmp);
    DeleteObject(source);

    const int maxDim = (std::max)(bmp.bmWidth, bmp.bmHeight);
    if (maxDim <= 900) return 3;
    if (maxDim <= 1300) return 2;
    return 1;
}

std::wstring ScaledOcrBmpPath(const std::wstring& bmpPath) {
    size_t dot = bmpPath.find_last_of(L'.');
    if (dot == std::wstring::npos) {
        return bmpPath + L"_scaled.bmp";
    }
    return bmpPath.substr(0, dot) + L"_scaled" + bmpPath.substr(dot);
}

std::wstring CreateScaledOcrBitmap(const std::wstring& bmpPath, int scale) {
    if (scale <= 1) {
        return bmpPath;
    }

    HBITMAP source = static_cast<HBITMAP>(LoadImageW(
        nullptr,
        bmpPath.c_str(),
        IMAGE_BITMAP,
        0,
        0,
        LR_LOADFROMFILE | LR_CREATEDIBSECTION));
    if (!source) {
        return bmpPath;
    }

    BITMAP bmp = {};
    GetObjectW(source, sizeof(bmp), &bmp);
    const int scaledWidth = bmp.bmWidth * scale;
    const int scaledHeight = bmp.bmHeight * scale;

    HDC screenDc = GetDC(nullptr);
    HDC sourceDc = CreateCompatibleDC(screenDc);
    HDC scaledDc = CreateCompatibleDC(screenDc);
    HBITMAP scaled = CreateCompatibleBitmap(screenDc, scaledWidth, scaledHeight);

    HGDIOBJ oldSource = SelectObject(sourceDc, source);
    HGDIOBJ oldScaled = SelectObject(scaledDc, scaled);
    SetStretchBltMode(scaledDc, HALFTONE);
    SetBrushOrgEx(scaledDc, 0, 0, nullptr);
    StretchBlt(scaledDc, 0, 0, scaledWidth, scaledHeight, sourceDc, 0, 0, bmp.bmWidth, bmp.bmHeight, SRCCOPY);

    SelectObject(sourceDc, oldSource);
    SelectObject(scaledDc, oldScaled);

    std::wstring scaledPath = ScaledOcrBmpPath(bmpPath);
    bool saved = SaveBitmapToFileLocal(scaled, scaledPath);

    DeleteObject(scaled);
    DeleteDC(scaledDc);
    DeleteDC(sourceDc);
    ReleaseDC(nullptr, screenDc);
    DeleteObject(source);

    return saved ? scaledPath : bmpPath;
}

RECT OcrRectToOriginal(double left, double top, double right, double bottom, int scale) {
    if (scale <= 1) {
        return {
            static_cast<LONG>(left),
            static_cast<LONG>(top),
            static_cast<LONG>(right),
            static_cast<LONG>(bottom)};
    }
    return {
        static_cast<LONG>(std::floor(left / scale)),
        static_cast<LONG>(std::floor(top / scale)),
        static_cast<LONG>(std::ceil(right / scale)),
        static_cast<LONG>(std::ceil(bottom / scale))};
}

int ChooseOcrScaleForDimensions(int width, int height) {
    const int maxDim = (std::max)(width, height);
    if (maxDim <= 900) return 3;
    if (maxDim <= 1300) return 2;
    return 1;
}

std::vector<unsigned char> ScaleBgraPixels(
    const std::vector<unsigned char>& pixels,
    int width,
    int height,
    int stride,
    int scale,
    int& scaledWidth,
    int& scaledHeight,
    int& scaledStride) {
    scaledWidth = width;
    scaledHeight = height;
    scaledStride = stride;
    if (scale <= 1) {
        return pixels;
    }
    scaledWidth = width * scale;
    scaledHeight = height * scale;
    scaledStride = scaledWidth * 4;
    std::vector<unsigned char> scaled(static_cast<size_t>(scaledStride) * static_cast<size_t>(scaledHeight), 0);
    for (int y = 0; y < scaledHeight; ++y) {
        const int srcY = y / scale;
        for (int x = 0; x < scaledWidth; ++x) {
            const int srcX = x / scale;
            const size_t srcOffset = static_cast<size_t>(srcY) * static_cast<size_t>(stride) + static_cast<size_t>(srcX) * 4;
            const size_t dstOffset = static_cast<size_t>(y) * static_cast<size_t>(scaledStride) + static_cast<size_t>(x) * 4;
            scaled[dstOffset + 0] = pixels[srcOffset + 0];
            scaled[dstOffset + 1] = pixels[srcOffset + 1];
            scaled[dstOffset + 2] = pixels[srcOffset + 2];
            scaled[dstOffset + 3] = pixels[srcOffset + 3];
        }
    }
    return scaled;
}

void AppendWinRtOcrLines(const winrt::Windows::Media::Ocr::OcrResult& ocrResult, int scale, OcrResult& result) {
    for (const auto& ocrLine : ocrResult.Lines()) {
        OcrLine line;
        line.text = ocrLine.Text().c_str();

        RECT lineRect = {};
        if (ocrLine.Words().Size() > 0) {
            auto wr0 = ocrLine.Words().GetAt(0).BoundingRect();
            double minX = wr0.X, minY = wr0.Y, maxX = wr0.X + wr0.Width, maxY = wr0.Y + wr0.Height;
            for (uint32_t i = 1; i < ocrLine.Words().Size(); ++i) {
                auto wr = ocrLine.Words().GetAt(i).BoundingRect();
                if (wr.X < minX) minX = wr.X;
                if (wr.Y < minY) minY = wr.Y;
                if (wr.X + wr.Width > maxX) maxX = wr.X + wr.Width;
                if (wr.Y + wr.Height > maxY) maxY = wr.Y + wr.Height;
            }
            lineRect = OcrRectToOriginal(minX, minY, maxX, maxY, scale);
        }
        line.boundingBox = lineRect;

        for (const auto& ocrWord : ocrLine.Words()) {
            OcrWord word;
            word.text = ocrWord.Text().c_str();
            auto wr = ocrWord.BoundingRect();
            word.boundingBox = OcrRectToOriginal(wr.X, wr.Y, wr.X + wr.Width, wr.Y + wr.Height, scale);
            word.confidence = -1.0;
            line.words.push_back(word);
            result.allWords.push_back(word);
        }
        result.lines.push_back(line);
    }

    if (!result.lines.empty()) {
        std::wstringstream full;
        for (size_t i = 0; i < result.lines.size(); ++i) {
            if (i != 0) full << L"\n";
            full << result.lines[i].text;
        }
        result.fullText = full.str();
    }
    result.language = L"system-default";
    result.ok = true;
}

OcrResult RecognizeBitmapFile(
    const std::wstring& bmpPath,
    const std::wstring& screenshotPath) {
    OcrResult result;
    result.coordinateSpace = L"window_bitmap";
    result.screenshotPath = screenshotPath;

    try {
        auto engine = winrt::Windows::Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
        if (!engine) {
            result.errorCode = L"OCR_LANGUAGE_UNAVAILABLE";
            result.errorMessage = L"No OCR language is available for the current user profile.";
            return result;
        }

        const int scale = ChooseOcrScale(bmpPath);
        std::wstring ocrBmpPath = CreateScaledOcrBitmap(bmpPath, scale);

        auto file = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(ocrBmpPath).get();
        auto stream = file.OpenAsync(winrt::Windows::Storage::FileAccessMode::Read).get();
        auto decoder = winrt::Windows::Graphics::Imaging::BitmapDecoder::CreateAsync(stream).get();
        auto bitmap = decoder.GetSoftwareBitmapAsync().get();

        auto winrtOcr = engine.RecognizeAsync(bitmap).get();
        if (!winrtOcr) {
            result.errorCode = L"OCR_FAILED";
            result.errorMessage = L"RecognizeAsync returned null.";
            return result;
        }

        AppendWinRtOcrLines(winrtOcr, scale, result);
    } catch (winrt::hresult_error const& e) {
        result.errorCode = L"OCR_FAILED";
        result.errorMessage = L"WinRT OCR failed: 0x" + std::to_wstring(static_cast<unsigned long>(e.code()));
    } catch (...) {
        result.errorCode = L"OCR_FAILED";
        result.errorMessage = L"WinRT OCR failed with unknown exception.";
    }

    return result;
}

OcrResult RecognizeBgraPixelsInternal(
    const std::vector<unsigned char>& pixels,
    int width,
    int height,
    int stride,
    const std::wstring& coordinateSpace,
    const std::wstring& sourcePath) {
    OcrResult result;
    result.coordinateSpace = coordinateSpace;
    result.screenshotPath = sourcePath;
    if (width <= 0 || height <= 0 || stride < width * 4 ||
        pixels.size() < static_cast<size_t>(stride) * static_cast<size_t>(height)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"Invalid BGRA OCR frame dimensions.";
        return result;
    }

    try {
        auto engine = winrt::Windows::Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
        if (!engine) {
            result.errorCode = L"OCR_LANGUAGE_UNAVAILABLE";
            result.errorMessage = L"No OCR language is available for the current user profile.";
            return result;
        }

        const int scale = ChooseOcrScaleForDimensions(width, height);
        int ocrWidth = width;
        int ocrHeight = height;
        int ocrStride = stride;
        std::vector<unsigned char> ocrPixels = ScaleBgraPixels(pixels, width, height, stride, scale, ocrWidth, ocrHeight, ocrStride);
        auto buffer = winrt::Windows::Security::Cryptography::CryptographicBuffer::CreateFromByteArray(
            winrt::array_view<const uint8_t>(ocrPixels.data(), ocrPixels.data() + ocrPixels.size()));
        auto bitmap = winrt::Windows::Graphics::Imaging::SoftwareBitmap::CreateCopyFromBuffer(
            buffer,
            winrt::Windows::Graphics::Imaging::BitmapPixelFormat::Bgra8,
            ocrWidth,
            ocrHeight,
            winrt::Windows::Graphics::Imaging::BitmapAlphaMode::Ignore);

        auto winrtOcr = engine.RecognizeAsync(bitmap).get();
        if (!winrtOcr) {
            result.errorCode = L"OCR_FAILED";
            result.errorMessage = L"RecognizeAsync returned null.";
            return result;
        }
        AppendWinRtOcrLines(winrtOcr, scale, result);
    } catch (winrt::hresult_error const& e) {
        result.errorCode = L"OCR_FAILED";
        result.errorMessage = L"WinRT OCR failed: 0x" + std::to_wstring(static_cast<unsigned long>(e.code()));
    } catch (...) {
        result.errorCode = L"OCR_FAILED";
        result.errorMessage = L"WinRT OCR failed with unknown exception.";
    }
    return result;
}

#endif  // DESKTOPVISUAL_HAS_WINRT_OCR

}  // namespace

// ===================================================================
// Public API
// ===================================================================

OcrCapability GetOcrCapability() {
    OcrCapability cap;
#if DESKTOPVISUAL_HAS_WINRT_OCR
    try {
        WinRtApartment apt;
        auto engine = winrt::Windows::Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
        if (engine) {
            cap.available = true;
            cap.engine = L"Windows.Media.Ocr.OcrEngine (WinRT)";
            auto langs = engine.AvailableRecognizerLanguages();
            uint32_t langCount = langs.Size();
            if (langCount > 0) {
                cap.languages = L"" + std::to_wstring(langCount) + L" language(s)";
            }
            return cap;
        }
    } catch (...) {}
#endif
    cap.available = false;
    cap.engine = L"none";
    cap.languages = L"";
    return cap;
}

OcrResult RecognizeBgraFrame(
    const std::vector<unsigned char>& pixels,
    int width,
    int height,
    int stride,
    const std::wstring& coordinateSpace,
    const std::wstring& sourcePath) {
#if DESKTOPVISUAL_HAS_WINRT_OCR
    WinRtApartment apt;
    return RecognizeBgraPixelsInternal(pixels, width, height, stride, coordinateSpace, sourcePath);
#else
    (void)pixels; (void)width; (void)height; (void)stride; (void)coordinateSpace; (void)sourcePath;
    return OcrResultUnavailable();
#endif
}

OcrResult RecognizeImageFileForBenchmark(const std::wstring& imagePath, const std::wstring& coordinateSpace) {
#if DESKTOPVISUAL_HAS_WINRT_OCR
    WinRtApartment apt;
    OcrResult result = RecognizeBitmapFile(imagePath, imagePath);
    result.coordinateSpace = coordinateSpace;
    return result;
#else
    (void)imagePath; (void)coordinateSpace;
    return OcrResultUnavailable();
#endif
}

OcrResult ReadWindowText(HWND hwnd, const std::wstring& /*language*/) {
#if DESKTOPVISUAL_HAS_WINRT_OCR
    // Screenshot to temp BMP
    RECT rect = {};
    if (!GetWindowRect(hwnd, &rect)) {
        OcrResult result;
        result.errorCode = L"SCREENSHOT_FAILED";
        result.errorMessage = L"GetWindowRect failed.";
        return result;
    }
    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    if (width <= 0 || height <= 0) {
        OcrResult result;
        result.errorCode = L"SCREENSHOT_FAILED";
        result.errorMessage = L"Window rectangle is empty.";
        return result;
    }

    std::wstring bmpPath = OcrArtifactBmpPath(L"ocr_window");

    ScreenshotResult shot = CaptureWindowToBmp(hwnd, bmpPath);
    if (!shot.ok) {
        OcrResult result;
        result.errorCode = L"SCREENSHOT_FAILED";
        result.errorMessage = shot.error;
        return result;
    }

    return RecognizeBitmapFile(bmpPath, bmpPath);
#else
    (void)hwnd;
    return OcrResultUnavailable();
#endif
}

OcrResult ReadRegionText(HWND hwnd, int clientX, int clientY, int width, int height) {
#if DESKTOPVISUAL_HAS_WINRT_OCR
    if (clientX < 0 || clientY < 0 || width <= 0 || height <= 0) {
        OcrResult result;
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"Region coordinates must be non-negative with positive dimensions.";
        return result;
    }

    RECT clientRect = {};
    GetClientRect(hwnd, &clientRect);
    if (clientX >= clientRect.right || clientY >= clientRect.bottom) {
        OcrResult result;
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"Region is outside target window client area.";
        return result;
    }

    POINT topLeft = {clientX, clientY};
    ClientToScreen(hwnd, &topLeft);
    int capW = (std::min)(width, static_cast<int>(clientRect.right) - clientX);
    int capH = (std::min)(height, static_cast<int>(clientRect.bottom) - clientY);

    HDC screenDc = GetDC(nullptr);
    HDC cropDc = CreateCompatibleDC(screenDc);
    HBITMAP cropBitmap = CreateCompatibleBitmap(screenDc, capW, capH);
    HGDIOBJ oldCrop = SelectObject(cropDc, cropBitmap);
    BitBlt(cropDc, 0, 0, capW, capH, screenDc, topLeft.x, topLeft.y, SRCCOPY | CAPTUREBLT);
    SelectObject(cropDc, oldCrop);
    DeleteDC(cropDc);
    ReleaseDC(nullptr, screenDc);

    // Save crop to temp BMP
    std::wstring bmpPath = OcrArtifactBmpPath(L"ocr_region");

    // Save cropBitmap to file
    BITMAP bmpInfo = {};
    GetObjectW(cropBitmap, sizeof(bmpInfo), &bmpInfo);
    BITMAPINFOHEADER bi = {};
    bi.biSize = sizeof(BITMAPINFOHEADER);
    bi.biWidth = bmpInfo.bmWidth;
    bi.biHeight = -bmpInfo.bmHeight;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;
    int stride = bmpInfo.bmWidth * 4;
    std::vector<unsigned char> pixels(static_cast<size_t>(stride * bmpInfo.bmHeight));
    HDC hdcTmp = GetDC(nullptr);
    GetDIBits(hdcTmp, cropBitmap, 0, static_cast<UINT>(bmpInfo.bmHeight), pixels.data(),
              reinterpret_cast<BITMAPINFO*>(&bi), DIB_RGB_COLORS);
    ReleaseDC(nullptr, hdcTmp);
    DeleteObject(cropBitmap);

    BITMAPFILEHEADER fh = {};
    fh.bfType = 0x4D42;
    fh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
    fh.bfSize = fh.bfOffBits + static_cast<DWORD>(pixels.size());
    FILE* f = nullptr;
    if (_wfopen_s(&f, bmpPath.c_str(), L"wb") == 0 && f) {
        fwrite(&fh, sizeof(fh), 1, f);
        fwrite(&bi, sizeof(bi), 1, f);
        fwrite(pixels.data(), pixels.size(), 1, f);
        fclose(f);
    } else {
        OcrResult result;
        result.errorCode = L"SCREENSHOT_FAILED";
        result.errorMessage = L"Could not write OCR region bitmap.";
        return result;
    }

    return RecognizeBitmapFile(bmpPath, bmpPath);
#else
    (void)hwnd; (void)clientX; (void)clientY; (void)width; (void)height;
    return OcrResultUnavailable();
#endif
}

OcrResult ReadScreenRegionText(int screenX, int screenY, int width, int height) {
#if DESKTOPVISUAL_HAS_WINRT_OCR
    if (width <= 0 || height <= 0) {
        OcrResult result;
        result.errorCode = L"INVALID_ARGUMENT";
        result.errorMessage = L"Screen region dimensions must be positive.";
        return result;
    }

    HDC screenDc = GetDC(nullptr);
    HDC cropDc = CreateCompatibleDC(screenDc);
    HBITMAP cropBitmap = CreateCompatibleBitmap(screenDc, width, height);
    HGDIOBJ oldCrop = SelectObject(cropDc, cropBitmap);
    BOOL copied = BitBlt(cropDc, 0, 0, width, height, screenDc, screenX, screenY, SRCCOPY | CAPTUREBLT);
    SelectObject(cropDc, oldCrop);
    DeleteDC(cropDc);
    ReleaseDC(nullptr, screenDc);

    if (!copied) {
        DeleteObject(cropBitmap);
        OcrResult result;
        result.errorCode = L"SCREENSHOT_FAILED";
        result.errorMessage = L"Could not capture screen OCR region.";
        return result;
    }

    std::wstring bmpPath = OcrArtifactBmpPath(L"ocr_screen_region");
    if (!SaveBitmapToFileLocal(cropBitmap, bmpPath)) {
        DeleteObject(cropBitmap);
        OcrResult result;
        result.errorCode = L"SCREENSHOT_FAILED";
        result.errorMessage = L"Could not write screen OCR region bitmap.";
        return result;
    }
    DeleteObject(cropBitmap);

    OcrResult result = RecognizeBitmapFile(bmpPath, bmpPath);
    result.coordinateSpace = L"screen";
    return result;
#else
    (void)screenX; (void)screenY; (void)width; (void)height;
    return OcrResultUnavailable();
#endif
}

OcrTextResult FindTextInWindow(HWND hwnd, const std::wstring& text,
    const std::wstring& matchMode, bool caseSensitive, int index) {
#if DESKTOPVISUAL_HAS_WINRT_OCR
    try {
        OcrResult ocr = ReadWindowText(hwnd, L"");
        if (!ocr.ok) {
            OcrTextResult result;
            result.errorCode = ocr.errorCode;
            result.errorMessage = ocr.errorMessage;
            result.matchedText = text;
            result.screenshotPath = ocr.screenshotPath;
            result.coordinateSpace = ocr.coordinateSpace;
            return result;
        }

        std::wstring needle = caseSensitive ? text : ToLower(text);
        std::vector<OcrWord> matches;

        for (const auto& word : ocr.allWords) {
            std::wstring candidate = caseSensitive ? word.text : ToLower(word.text);
            bool matched = (matchMode == L"exact") ? (candidate == needle) : (candidate.find(needle) != std::wstring::npos);
            if (matched) {
                matches.push_back(word);
            }
        }

        OcrTextResult result;
        result.coordinateSpace = ocr.coordinateSpace;
        result.screenshotPath = ocr.screenshotPath;

        if (matches.empty()) {
            return OcrTextNotFound(text, ocr.screenshotPath);
        }

        if (index >= 0) {
            if (index >= static_cast<int>(matches.size())) {
                result.errorCode = L"LOCATOR_NOT_FOUND";
                result.errorMessage = L"OCR text index " + std::to_wstring(index) + L" is outside matched elements.";
                result.matchedText = text;
                result.matchCount = static_cast<int>(matches.size());
                return result;
            }
            const auto& w = matches[static_cast<size_t>(index)];
            result.ok = true;
            result.matchedText = w.text;
            result.boundingBox = w.boundingBox;
            result.confidence = w.confidence;
            result.matchCount = 1;
            return result;
        }

        if (matches.size() > 1) {
            result.errorCode = L"LOCATOR_NOT_UNIQUE";
            result.errorMessage = L"OCR text matched multiple locations (" + std::to_wstring(matches.size()) + L").";
            result.matchedText = text;
            result.matchCount = static_cast<int>(matches.size());
            return result;
        }

        const auto& w = matches[0];
        result.ok = true;
        result.matchedText = w.text;
        result.boundingBox = w.boundingBox;
        result.confidence = w.confidence;
        result.matchCount = 1;
        return result;
    } catch (...) {
        return OcrTextUnavailable(text);
    }
#else
    (void)hwnd; (void)text; (void)matchMode; (void)caseSensitive; (void)index;
    return OcrTextUnavailable(text);
#endif
}

OcrTextResult WaitForText(HWND hwnd, const std::wstring& text, int timeoutMs, int intervalMs) {
    if (intervalMs <= 0) intervalMs = 300;
    ULONGLONG startTick = GetTickCount64();

    while (true) {
        OcrTextResult result = FindTextInWindow(hwnd, text, L"contains", false, -1);
        if (result.ok) return result;
        if (result.errorCode == L"OCR_UNAVAILABLE" || result.errorCode == L"OCR_FAILED") {
            return result;
        }
        if (ElapsedMs(startTick) >= static_cast<long long>(timeoutMs)) {
            result.errorCode = L"LOCATOR_NOT_FOUND";
            result.errorMessage = L"OCR text '" + text + L"' did not appear within " + std::to_wstring(timeoutMs) + L"ms.";
            return result;
        }
        Sleep(static_cast<DWORD>(intervalMs));
    }
}

OcrTextResult AssertTextContains(HWND hwnd, const std::wstring& text) {
    OcrTextResult result = FindTextInWindow(hwnd, text, L"contains", false, -1);
    if (!result.ok && result.errorCode != L"LOCATOR_NOT_FOUND" && result.errorCode != L"LOCATOR_NOT_UNIQUE") {
        return result;
    }
    if (!result.ok) {
        result.errorCode = L"ASSERTION_FAILED";
        result.errorMessage = L"Assertion failed: window does not contain text '" + text + L"'.";
    }
    return result;
}
