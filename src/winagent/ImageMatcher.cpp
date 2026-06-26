#include "ImageMatcher.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

constexpr int kMaxTemplateWidth = 512;
constexpr int kMaxTemplateHeight = 512;
constexpr int kMaxSourcePixels = 3000 * 3000;

struct RgbPixel {
    unsigned char r = 0;
    unsigned char g = 0;
    unsigned char b = 0;
};

struct BmpImage {
    int width = 0;
    int height = 0;
    std::vector<RgbPixel> pixels;
};

ImageMatchResult Error(const std::wstring& code, const std::wstring& message) {
    ImageMatchResult result;
    result.errorCode = code;
    result.errorMessage = message;
    return result;
}

bool ReadExact(FILE* file, void* buffer, size_t size) {
    return fread(buffer, 1, size, file) == size;
}

ImageMatchResult LoadBmp(const std::wstring& path, BmpImage& image) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        return Error(L"IMAGE_FILE_NOT_FOUND", L"BMP file was not found.");
    }

    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        return Error(L"IMAGE_FILE_NOT_FOUND", L"Could not open BMP file.");
    }

    BITMAPFILEHEADER fileHeader = {};
    BITMAPINFOHEADER infoHeader = {};
    if (!ReadExact(file, &fileHeader, sizeof(fileHeader)) ||
        !ReadExact(file, &infoHeader, sizeof(infoHeader))) {
        fclose(file);
        return Error(L"IMAGE_UNSUPPORTED_FORMAT", L"Could not read BMP headers.");
    }

    if (fileHeader.bfType != 0x4D42 ||
        infoHeader.biSize < sizeof(BITMAPINFOHEADER) ||
        infoHeader.biPlanes != 1 ||
        infoHeader.biCompression != BI_RGB ||
        (infoHeader.biBitCount != 24 && infoHeader.biBitCount != 32)) {
        fclose(file);
        return Error(L"IMAGE_UNSUPPORTED_FORMAT", L"Only uncompressed 24-bit and 32-bit BMP files are supported.");
    }

    int width = infoHeader.biWidth;
    int heightRaw = infoHeader.biHeight;
    int height = std::abs(heightRaw);
    if (width <= 0 || height <= 0 || width * height > kMaxSourcePixels) {
        fclose(file);
        return Error(L"IMAGE_MATCH_FAILED", L"BMP dimensions are invalid or too large.");
    }

    int bytesPerPixel = infoHeader.biBitCount / 8;
    int stride = ((width * bytesPerPixel + 3) / 4) * 4;
    std::vector<unsigned char> row(static_cast<size_t>(stride));
    image.width = width;
    image.height = height;
    image.pixels.assign(static_cast<size_t>(width * height), RgbPixel{});

    if (fseek(file, fileHeader.bfOffBits, SEEK_SET) != 0) {
        fclose(file);
        return Error(L"IMAGE_UNSUPPORTED_FORMAT", L"Could not seek to BMP pixel data.");
    }

    bool topDown = heightRaw < 0;
    for (int rowIndex = 0; rowIndex < height; ++rowIndex) {
        if (!ReadExact(file, row.data(), row.size())) {
            fclose(file);
            return Error(L"IMAGE_UNSUPPORTED_FORMAT", L"Could not read BMP pixel row.");
        }
        int y = topDown ? rowIndex : (height - 1 - rowIndex);
        for (int x = 0; x < width; ++x) {
            size_t offset = static_cast<size_t>(x * bytesPerPixel);
            RgbPixel pixel;
            pixel.b = row[offset + 0];
            pixel.g = row[offset + 1];
            pixel.r = row[offset + 2];
            image.pixels[static_cast<size_t>(y * width + x)] = pixel;
        }
    }

    fclose(file);
    ImageMatchResult result;
    result.ok = true;
    return result;
}

bool PixelWithinTolerance(const RgbPixel& a, const RgbPixel& b, int tolerance) {
    return std::abs(static_cast<int>(a.r) - static_cast<int>(b.r)) <= tolerance &&
           std::abs(static_cast<int>(a.g) - static_cast<int>(b.g)) <= tolerance &&
           std::abs(static_cast<int>(a.b) - static_cast<int>(b.b)) <= tolerance;
}

double MatchScore(const BmpImage& source, const BmpImage& templ, int originX, int originY) {
    long long totalDiff = 0;
    const long long maxDiff = static_cast<long long>(templ.width) * templ.height * 3 * 255;
    for (int y = 0; y < templ.height; ++y) {
        for (int x = 0; x < templ.width; ++x) {
            const RgbPixel& a = source.pixels[static_cast<size_t>((originY + y) * source.width + (originX + x))];
            const RgbPixel& b = templ.pixels[static_cast<size_t>(y * templ.width + x)];
            totalDiff += std::abs(static_cast<int>(a.r) - static_cast<int>(b.r));
            totalDiff += std::abs(static_cast<int>(a.g) - static_cast<int>(b.g));
            totalDiff += std::abs(static_cast<int>(a.b) - static_cast<int>(b.b));
        }
    }
    return maxDiff == 0 ? 1.0 : 1.0 - (static_cast<double>(totalDiff) / static_cast<double>(maxDiff));
}

bool TemplateMatchesAt(const BmpImage& source, const BmpImage& templ, int originX, int originY, int tolerance) {
    for (int y = 0; y < templ.height; ++y) {
        for (int x = 0; x < templ.width; ++x) {
            const RgbPixel& a = source.pixels[static_cast<size_t>((originY + y) * source.width + (originX + x))];
            const RgbPixel& b = templ.pixels[static_cast<size_t>(y * templ.width + x)];
            if (!PixelWithinTolerance(a, b, tolerance)) {
                return false;
            }
        }
    }
    return true;
}

}  // namespace

ImageMatchResult FindTemplateInBmp(
    const std::wstring& sourceBmpPath,
    const std::wstring& templateBmpPath,
    int tolerance) {
    if (tolerance < 0 || tolerance > 255) {
        return Error(L"INVALID_ARGUMENT", L"Tolerance must be between 0 and 255.");
    }

    BmpImage source;
    ImageMatchResult loadedSource = LoadBmp(sourceBmpPath, source);
    if (!loadedSource.ok) {
        return loadedSource;
    }

    BmpImage templ;
    ImageMatchResult loadedTemplate = LoadBmp(templateBmpPath, templ);
    if (!loadedTemplate.ok) {
        return loadedTemplate;
    }

    if (templ.width > kMaxTemplateWidth || templ.height > kMaxTemplateHeight) {
        return Error(L"IMAGE_MATCH_FAILED", L"Template dimensions exceed the maximum allowed size.");
    }
    if (templ.width > source.width || templ.height > source.height) {
        return Error(L"IMAGE_MATCH_NOT_FOUND", L"Template is larger than source image.");
    }

    ImageMatchResult result;
    result.width = templ.width;
    result.height = templ.height;

    for (int y = 0; y <= source.height - templ.height; ++y) {
        for (int x = 0; x <= source.width - templ.width; ++x) {
            if (TemplateMatchesAt(source, templ, x, y, tolerance)) {
                ++result.matchCount;
                if (result.matchCount == 1) {
                    result.x = x;
                    result.y = y;
                    result.score = MatchScore(source, templ, x, y);
                }
            }
        }
    }

    if (result.matchCount == 0) {
        result.errorCode = L"IMAGE_MATCH_NOT_FOUND";
        result.errorMessage = L"No image template match was found.";
        return result;
    }
    if (result.matchCount > 1) {
        result.errorCode = L"IMAGE_MATCH_NOT_UNIQUE";
        result.errorMessage = L"Image template matched multiple locations.";
        return result;
    }

    result.ok = true;
    result.matchFound = true;
    return result;
}
