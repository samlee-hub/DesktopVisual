#pragma once

#include <windows.h>

#include <string>

struct ScreenshotCoordinateMappingInput {
    std::wstring direction;
    std::wstring captureScope;
    RECT captureRect = {};
    int capturePhysicalWidth = 0;
    int capturePhysicalHeight = 0;
    RECT targetRect = {};
    bool hasTargetRect = false;
    int pixelX = 0;
    int pixelY = 0;
    int screenX = 0;
    int screenY = 0;
    double dpiScale = 1.0;
};

struct ScreenshotCoordinateMappingResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    int screenX = 0;
    int screenY = 0;
    int pixelX = 0;
    int pixelY = 0;
    std::wstring coordinateSource;
    std::wstring captureScope;
    RECT captureRect = {};
    int capturePhysicalWidth = 0;
    int capturePhysicalHeight = 0;
    RECT targetRect = {};
    double dpiScale = 1.0;
    bool mapperUsed = true;
    bool mappingValid = false;
};

ScreenshotCoordinateMappingResult map_global_pixel_to_screen_coord(const ScreenshotCoordinateMappingInput& input);
ScreenshotCoordinateMappingResult map_window_pixel_to_screen_coord(const ScreenshotCoordinateMappingInput& input);
ScreenshotCoordinateMappingResult map_screen_coord_to_global_pixel(const ScreenshotCoordinateMappingInput& input);
ScreenshotCoordinateMappingResult map_screen_coord_to_window_pixel(const ScreenshotCoordinateMappingInput& input);
bool validate_dpi_scale_consistency(double dpiScale);
bool validate_capture_rect_matches_target_rect(const ScreenshotCoordinateMappingInput& input);
bool reject_mixed_coordinate_sources(const ScreenshotCoordinateMappingInput& input, std::wstring& errorCode, std::wstring& errorMessage);
ScreenshotCoordinateMappingResult MapScreenshotCoordinate(const ScreenshotCoordinateMappingInput& input);
std::wstring ScreenshotCoordinateMappingJson(const ScreenshotCoordinateMappingResult& result);
