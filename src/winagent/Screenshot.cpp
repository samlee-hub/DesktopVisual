#include "Screenshot.h"

#include <cstdio>
#include <vector>

namespace {

constexpr UINT kPrintWindowRenderFullContent = 0x00000002;

bool SaveBitmapToFile(HBITMAP bitmap, const std::wstring& outputPath, std::wstring& error) {
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

    if (!ok) {
        error = L"Failed while writing BMP data.";
    }
    return ok;
}

}  // namespace

ScreenshotResult CaptureWindowToBmp(HWND hwnd, const std::wstring& outputPath) {
    ScreenshotResult result;

    RECT rect = {};
    if (!GetWindowRect(hwnd, &rect)) {
        result.error = L"GetWindowRect failed.";
        return result;
    }

    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    if (width <= 0 || height <= 0) {
        result.error = L"Window rectangle is empty.";
        return result;
    }

    HDC screenDc = GetDC(nullptr);
    if (!screenDc) {
        result.error = L"GetDC failed.";
        return result;
    }

    HDC memoryDc = CreateCompatibleDC(screenDc);
    HBITMAP bitmap = CreateCompatibleBitmap(screenDc, width, height);
    if (!memoryDc || !bitmap) {
        if (bitmap) {
            DeleteObject(bitmap);
        }
        if (memoryDc) {
            DeleteDC(memoryDc);
        }
        ReleaseDC(nullptr, screenDc);
        result.error = L"Could not create compatible bitmap resources.";
        return result;
    }

    HGDIOBJ oldBitmap = SelectObject(memoryDc, bitmap);
    BOOL printed = PrintWindow(hwnd, memoryDc, kPrintWindowRenderFullContent);
    std::wstring method = L"PrintWindow";

    if (!printed) {
        BOOL copied = BitBlt(memoryDc, 0, 0, width, height, screenDc, rect.left, rect.top, SRCCOPY | CAPTUREBLT);
        method = L"BitBlt";
        if (!copied) {
            SelectObject(memoryDc, oldBitmap);
            DeleteObject(bitmap);
            DeleteDC(memoryDc);
            ReleaseDC(nullptr, screenDc);
            result.error = L"PrintWindow and BitBlt both failed.";
            return result;
        }
    }

    std::wstring saveError;
    result.ok = SaveBitmapToFile(bitmap, outputPath, saveError);
    result.method = method;
    result.error = saveError;

    SelectObject(memoryDc, oldBitmap);
    DeleteObject(bitmap);
    DeleteDC(memoryDc);
    ReleaseDC(nullptr, screenDc);

    return result;
}
