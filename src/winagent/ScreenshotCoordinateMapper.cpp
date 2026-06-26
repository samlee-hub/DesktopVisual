#include "ScreenshotCoordinateMapper.h"

#include "SimpleJson.h"

#include <cmath>
#include <sstream>

namespace {

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right << L",\"bottom\":" << rect.bottom << L"}";
    return json.str();
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

ScreenshotCoordinateMappingResult BaseResult(const ScreenshotCoordinateMappingInput& input) {
    ScreenshotCoordinateMappingResult result;
    result.captureScope = input.captureScope;
    result.captureRect = input.captureRect;
    result.capturePhysicalWidth = input.capturePhysicalWidth;
    result.capturePhysicalHeight = input.capturePhysicalHeight;
    result.targetRect = input.targetRect;
    result.dpiScale = input.dpiScale;
    result.coordinateSource = input.captureScope == L"global_desktop" ? L"global_frame_pixel" : L"window_frame_pixel";
    return result;
}

}  // namespace

bool validate_dpi_scale_consistency(double dpiScale) {
    return std::isfinite(dpiScale) && dpiScale > 0.0 && dpiScale < 8.0;
}

bool validate_capture_rect_matches_target_rect(const ScreenshotCoordinateMappingInput& input) {
    if (input.captureScope != L"window_only") return true;
    if (!input.hasTargetRect) return false;
    return input.captureRect.left == input.targetRect.left &&
           input.captureRect.top == input.targetRect.top &&
           input.captureRect.right == input.targetRect.right &&
           input.captureRect.bottom == input.targetRect.bottom;
}

bool reject_mixed_coordinate_sources(const ScreenshotCoordinateMappingInput& input, std::wstring& errorCode, std::wstring& errorMessage) {
    if (input.captureScope != L"global_desktop" && input.captureScope != L"window_only") {
        errorCode = L"FAIL_UNSAFE_COORDINATE_SOURCE";
        errorMessage = L"Unknown coordinate capture scope.";
        return true;
    }
    if (!validate_dpi_scale_consistency(input.dpiScale)) {
        errorCode = L"FAIL_DPI_COORDINATE_MISMATCH";
        errorMessage = L"DPI scale is not valid.";
        return true;
    }
    if (!validate_capture_rect_matches_target_rect(input)) {
        errorCode = L"FAIL_CAPTURE_TARGET_RECT_MISMATCH";
        errorMessage = L"Window capture rect does not match target rect.";
        return true;
    }
    return false;
}

ScreenshotCoordinateMappingResult map_global_pixel_to_screen_coord(const ScreenshotCoordinateMappingInput& input) {
    ScreenshotCoordinateMappingResult result = BaseResult(input);
    result.screenX = input.captureRect.left + input.pixelX;
    result.screenY = input.captureRect.top + input.pixelY;
    result.pixelX = input.pixelX;
    result.pixelY = input.pixelY;
    result.ok = true;
    result.mappingValid = true;
    return result;
}

ScreenshotCoordinateMappingResult map_window_pixel_to_screen_coord(const ScreenshotCoordinateMappingInput& input) {
    ScreenshotCoordinateMappingResult result = BaseResult(input);
    result.screenX = input.captureRect.left + input.pixelX;
    result.screenY = input.captureRect.top + input.pixelY;
    result.pixelX = input.pixelX;
    result.pixelY = input.pixelY;
    result.ok = true;
    result.mappingValid = true;
    return result;
}

ScreenshotCoordinateMappingResult map_screen_coord_to_global_pixel(const ScreenshotCoordinateMappingInput& input) {
    ScreenshotCoordinateMappingResult result = BaseResult(input);
    result.pixelX = input.screenX - input.captureRect.left;
    result.pixelY = input.screenY - input.captureRect.top;
    result.screenX = input.screenX;
    result.screenY = input.screenY;
    result.ok = true;
    result.mappingValid = true;
    return result;
}

ScreenshotCoordinateMappingResult map_screen_coord_to_window_pixel(const ScreenshotCoordinateMappingInput& input) {
    return map_screen_coord_to_global_pixel(input);
}

ScreenshotCoordinateMappingResult MapScreenshotCoordinate(const ScreenshotCoordinateMappingInput& input) {
    ScreenshotCoordinateMappingResult result = BaseResult(input);
    std::wstring errorCode;
    std::wstring errorMessage;
    if (reject_mixed_coordinate_sources(input, errorCode, errorMessage)) {
        result.errorCode = errorCode;
        result.errorMessage = errorMessage;
        return result;
    }
    if (input.direction == L"screen-to-pixel") {
        return input.captureScope == L"global_desktop"
            ? map_screen_coord_to_global_pixel(input)
            : map_screen_coord_to_window_pixel(input);
    }
    return input.captureScope == L"global_desktop"
        ? map_global_pixel_to_screen_coord(input)
        : map_window_pixel_to_screen_coord(input);
}

std::wstring ScreenshotCoordinateMappingJson(const ScreenshotCoordinateMappingResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << BoolJson(result.ok)
         << L",\"coordinate_source\":" << simplejson::Quote(result.coordinateSource)
         << L",\"capture_scope\":" << simplejson::Quote(result.captureScope)
         << L",\"capture_rect\":" << RectJson(result.captureRect)
         << L",\"capture_physical_size\":{\"width\":" << result.capturePhysicalWidth
         << L",\"height\":" << result.capturePhysicalHeight << L"}"
         << L",\"screen_x\":" << result.screenX
         << L",\"screen_y\":" << result.screenY
         << L",\"pixel_x\":" << result.pixelX
         << L",\"pixel_y\":" << result.pixelY
         << L",\"target_rect\":" << RectJson(result.targetRect)
         << L",\"dpi_scale\":" << result.dpiScale
         << L",\"mapper_used\":" << BoolJson(result.mapperUsed)
         << L",\"mapping_valid\":" << BoolJson(result.mappingValid);
    if (!result.errorCode.empty()) {
        json << L",\"error\":{\"code\":" << simplejson::Quote(result.errorCode)
             << L",\"message\":" << simplejson::Quote(result.errorMessage) << L"}";
    }
    json << L"}";
    return json.str();
}
