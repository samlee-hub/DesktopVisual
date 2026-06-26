#include "Selector.h"

#include "ImageMatcher.h"
#include "OcrController.h"
#include "ProjectRoot.h"
#include "Screenshot.h"
#include "Trace.h"
#include "UiaController.h"

#include <windows.h>

#include <algorithm>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct SelectorSpec {
    std::wstring type;
    std::vector<std::pair<std::wstring, std::wstring>> kv;
};

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && iswspace(value[first])) {
        ++first;
    }
    size_t last = value.size();
    while (last > first && iswspace(value[last - 1])) {
        --last;
    }
    return value.substr(first, last - first);
}

std::wstring ValueFor(const SelectorSpec& spec, const std::wstring& key) {
    for (const auto& item : spec.kv) {
        if (item.first == key) {
            return item.second;
        }
    }
    return L"";
}

bool HasKey(const SelectorSpec& spec, const std::wstring& key) {
    for (const auto& item : spec.kv) {
        if (item.first == key) {
            return true;
        }
    }
    return false;
}

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    return value.rfind(prefix, 0) == 0;
}

std::vector<std::wstring> SplitLiteral(const std::wstring& value, const std::wstring& delimiter) {
    std::vector<std::wstring> parts;
    size_t start = 0;
    while (start <= value.size()) {
        size_t found = value.find(delimiter, start);
        parts.push_back(value.substr(start, found == std::wstring::npos ? std::wstring::npos : found - start));
        if (found == std::wstring::npos) {
            break;
        }
        start = found + delimiter.size();
    }
    return parts;
}

bool ParseInt(const std::wstring& value, int& parsed) {
    try {
        size_t consumed = 0;
        parsed = std::stoi(value, &consumed, 10);
        return consumed == value.size();
    } catch (...) {
        return false;
    }
}

bool ParseNth(const SelectorSpec& spec, int& nth, std::wstring& error) {
    nth = -1;
    if (HasKey(spec, L"nth")) {
        if (!ParseInt(ValueFor(spec, L"nth"), nth) || nth < 0) {
            error = L"nth must be a non-negative integer.";
            return false;
        }
        return true;
    }
    if (HasKey(spec, L"index")) {
        if (!ParseInt(ValueFor(spec, L"index"), nth) || nth < 0) {
            error = L"index must be a non-negative integer.";
            return false;
        }
    }
    return true;
}

bool ParseSelector(const std::wstring& selector, SelectorSpec& spec, std::wstring& error) {
    size_t colon = selector.find(L':');
    if (colon == std::wstring::npos || colon == 0) {
        error = L"Selector must be type:key=value.";
        return false;
    }
    spec.type = Trim(selector.substr(0, colon));
    std::wstring rest = selector.substr(colon + 1);
    if (rest.empty()) {
        error = L"Selector body is empty.";
        return false;
    }

    size_t start = 0;
    while (start <= rest.size()) {
        size_t comma = rest.find(L',', start);
        std::wstring part = Trim(rest.substr(start, comma == std::wstring::npos ? std::wstring::npos : comma - start));
        if (!part.empty()) {
            size_t equals = part.find(L'=');
            if (equals == std::wstring::npos || equals == 0) {
                error = L"Selector fields must be key=value.";
                return false;
            }
            spec.kv.push_back({Trim(part.substr(0, equals)), Trim(part.substr(equals + 1))});
        }
        if (comma == std::wstring::npos) {
            break;
        }
        start = comma + 1;
    }
    return true;
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

std::wstring ElementJson(const SelectorResult& result) {
    if (!result.hasElement) {
        return L"null";
    }
    std::wstringstream json;
    json << L"{\"name\":" << JsonString(result.elementName)
         << L",\"control_type\":" << JsonString(result.elementControlType)
         << L",\"automation_id\":" << JsonString(result.elementAutomationId)
         << L",\"class_name\":" << JsonString(result.elementClassName)
         << L",\"rect\":" << RectJson(result.rect)
         << L",\"enabled\":" << (result.elementEnabled ? L"true" : L"false")
         << L",\"offscreen\":" << (result.elementOffscreen ? L"true" : L"false")
         << L"}";
    return json.str();
}

bool ClientToScreenPoint(HWND hwnd, int clientX, int clientY, int& screenX, int& screenY) {
    POINT point = {clientX, clientY};
    if (!ClientToScreen(hwnd, &point)) {
        return false;
    }
    screenX = point.x;
    screenY = point.y;
    return true;
}

bool ScreenToClientPoint(HWND hwnd, int screenX, int screenY, int& clientX, int& clientY) {
    POINT point = {screenX, screenY};
    if (!ScreenToClient(hwnd, &point)) {
        return false;
    }
    clientX = point.x;
    clientY = point.y;
    return true;
}

bool WindowBitmapPointToClient(HWND hwnd, int bitmapX, int bitmapY, int& clientX, int& clientY) {
    RECT windowRect = {};
    if (!GetWindowRect(hwnd, &windowRect)) {
        return false;
    }
    return ScreenToClientPoint(hwnd, windowRect.left + bitmapX, windowRect.top + bitmapY, clientX, clientY);
}

SelectorResult Error(const std::wstring& selector, const std::wstring& method, const std::wstring& code, const std::wstring& message, int matchCount = 0) {
    SelectorResult result;
    result.selector = selector;
    result.locateMethod = method;
    result.errorCode = code;
    result.errorMessage = message;
    result.matchCount = matchCount;
    result.failureReason = message;
    result.source = method;
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

SelectorResult SuccessPoint(const std::wstring& selector, const std::wstring& method, int matchCount, HWND hwnd, int clientX, int clientY, RECT rect) {
    SelectorResult result;
    result.ok = true;
    result.selector = selector;
    result.locateMethod = method;
    result.finalMethod = method;
    result.matchCount = matchCount;
    result.confidence = 1.0;
    result.source = method;
    result.clientX = clientX;
    result.clientY = clientY;
    result.rect = rect;
    if (!ClientToScreenPoint(hwnd, clientX, clientY, result.screenX, result.screenY)) {
        result.ok = false;
        result.errorCode = L"UNKNOWN_ERROR";
        result.errorMessage = L"ClientToScreen failed.";
    }
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

void AttachElement(SelectorResult& result, const UiaElementInfo& element) {
    result.hasElement = true;
    result.elementName = element.name;
    result.elementControlType = element.controlType;
    result.elementAutomationId = element.automationId;
    result.elementClassName = element.className;
    result.elementEnabled = element.enabled;
    result.elementOffscreen = element.offscreen;
    result.uiaValueCandidate = element.controlType == L"Edit";
    result.uiaInvokeCandidate = element.controlType == L"Button";
}

bool UiaMatches(const UiaElementInfo& element, const SelectorSpec& spec) {
    if (HasKey(spec, L"name") && element.name != ValueFor(spec, L"name")) {
        return false;
    }
    if (HasKey(spec, L"name_contains") && element.name.find(ValueFor(spec, L"name_contains")) == std::wstring::npos) {
        return false;
    }
    if (HasKey(spec, L"type") && element.controlType != ValueFor(spec, L"type")) {
        return false;
    }
    if (HasKey(spec, L"role") && element.controlType != ValueFor(spec, L"role")) {
        return false;
    }
    if (HasKey(spec, L"automation_id") && element.automationId != ValueFor(spec, L"automation_id")) {
        return false;
    }
    if (HasKey(spec, L"class_name") && element.className != ValueFor(spec, L"class_name")) {
        return false;
    }
    return true;
}

bool UiaTargetMatches(const UiaElementInfo& element, const SelectorSpec& spec) {
    if (HasKey(spec, L"target_name") && element.name != ValueFor(spec, L"target_name")) {
        return false;
    }
    if (HasKey(spec, L"target_name_contains") && element.name.find(ValueFor(spec, L"target_name_contains")) == std::wstring::npos) {
        return false;
    }
    if (HasKey(spec, L"target_type") && element.controlType != ValueFor(spec, L"target_type")) {
        return false;
    }
    if (HasKey(spec, L"target_role") && element.controlType != ValueFor(spec, L"target_role")) {
        return false;
    }
    if (HasKey(spec, L"target_automation_id") && element.automationId != ValueFor(spec, L"target_automation_id")) {
        return false;
    }
    if (HasKey(spec, L"target_class_name") && element.className != ValueFor(spec, L"target_class_name")) {
        return false;
    }
    return true;
}

bool HasAnyUiaTargetFilter(const SelectorSpec& spec) {
    return HasKey(spec, L"target_name") || HasKey(spec, L"target_name_contains") ||
           HasKey(spec, L"target_type") || HasKey(spec, L"target_role") ||
           HasKey(spec, L"target_automation_id") || HasKey(spec, L"target_class_name");
}

bool UsableElementRect(const UiaElementInfo& element) {
    return element.rect.right > element.rect.left && element.rect.bottom > element.rect.top;
}

long long RectDistanceScore(const RECT& anchor, const RECT& candidate) {
    long long ax = static_cast<long long>(anchor.left) + ((anchor.right - anchor.left) / 2);
    long long ay = static_cast<long long>(anchor.top) + ((anchor.bottom - anchor.top) / 2);
    long long bx = static_cast<long long>(candidate.left) + ((candidate.right - candidate.left) / 2);
    long long by = static_cast<long long>(candidate.top) + ((candidate.bottom - candidate.top) / 2);
    long long dx = ax - bx;
    long long dy = ay - by;
    return (dx * dx) + (dy * dy);
}

bool RelationMatches(const RECT& anchor, const RECT& candidate, const std::wstring& relation) {
    if (relation == L"right_of") return candidate.left >= anchor.right;
    if (relation == L"left_of") return candidate.right <= anchor.left;
    if (relation == L"below") return candidate.top >= anchor.bottom;
    if (relation == L"above") return candidate.bottom <= anchor.top;
    return false;
}

SelectorResult SuccessUiaElement(
    HWND hwnd,
    const std::wstring& selector,
    const std::wstring& method,
    int matchCount,
    const UiaElementInfo& element,
    double confidence) {
    int screenX = element.rect.left + ((element.rect.right - element.rect.left) / 2);
    int screenY = element.rect.top + ((element.rect.bottom - element.rect.top) / 2);
    int clientX = 0;
    int clientY = 0;
    if (!ScreenToClientPoint(hwnd, screenX, screenY, clientX, clientY)) {
        return Error(selector, method, L"UNKNOWN_ERROR", L"ScreenToClient failed for UIA element.", matchCount);
    }
    SelectorResult result = SuccessPoint(selector, method, matchCount, hwnd, clientX, clientY, element.rect);
    result.confidence = confidence;
    result.source = L"uia";
    AttachElement(result, element);
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

SelectorResult LocateCoord(HWND hwnd, const std::wstring& selector, const SelectorSpec& spec) {
    int x = 0;
    int y = 0;
    if (!ParseInt(ValueFor(spec, L"x"), x) || !ParseInt(ValueFor(spec, L"y"), y) || x < 0 || y < 0) {
        return Error(selector, L"coord", L"INVALID_SELECTOR", L"coord selector requires non-negative x and y.");
    }
    RECT client = {};
    if (!GetClientRect(hwnd, &client)) {
        return Error(selector, L"coord", L"UNKNOWN_ERROR", L"GetClientRect failed.");
    }
    if (x >= client.right || y >= client.bottom) {
        return Error(selector, L"coord", L"LOCATOR_NOT_FOUND", L"coord selector point is outside the target client area.");
    }
    RECT rect = {x, y, x, y};
    return SuccessPoint(selector, L"coord", 1, hwnd, x, y, rect);
}

SelectorResult LocateUia(HWND hwnd, const std::wstring& selector, const SelectorSpec& spec) {
    if (!HasKey(spec, L"name") && !HasKey(spec, L"name_contains") && !HasKey(spec, L"type") &&
        !HasKey(spec, L"role") && !HasKey(spec, L"automation_id") && !HasKey(spec, L"class_name")) {
        return Error(selector, L"uia", L"INVALID_SELECTOR", L"uia selector requires name, name_contains, type, role, automation_id, or class_name.");
    }
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) {
        return Error(selector, L"uia", tree.errorCode.empty() ? L"UNKNOWN_ERROR" : tree.errorCode, tree.errorMessage);
    }

    std::vector<UiaElementInfo> matches;
    for (const auto& element : tree.elements) {
        if (UiaMatches(element, spec)) {
            matches.push_back(element);
        }
    }
    if (matches.empty()) {
        if (HasKey(spec, L"automation_id")) {
            return Error(selector, L"uia", L"LOCATOR_NOT_FOUND", L"No UIA element matched AutomationId.", 0);
        }
        if (HasKey(spec, L"class_name")) {
            return Error(selector, L"uia", L"LOCATOR_NOT_FOUND", L"No UIA element matched ClassName.", 0);
        }
        return Error(selector, L"uia", L"LOCATOR_NOT_FOUND", L"No UIA element matched selector.", 0);
    }

    int selectedIndex = -1;
    std::wstring nthError;
    if (!ParseNth(spec, selectedIndex, nthError)) {
        return Error(selector, L"uia", L"INVALID_SELECTOR", L"uia " + nthError, static_cast<int>(matches.size()));
    }
    if (selectedIndex >= 0) {
        if (selectedIndex >= static_cast<int>(matches.size())) {
            return Error(selector, L"uia", L"LOCATOR_NOT_FOUND", L"uia nth is outside matched elements.", static_cast<int>(matches.size()));
        }
    } else if (matches.size() > 1) {
        return Error(selector, L"uia", L"LOCATOR_NOT_UNIQUE", L"UIA selector matched multiple elements.", static_cast<int>(matches.size()));
    } else {
        selectedIndex = 0;
    }

    const UiaElementInfo& element = matches[static_cast<size_t>(selectedIndex)];
    double confidence = HasKey(spec, L"automation_id") ? 0.99 : 0.95;
    return SuccessUiaElement(hwnd, selector, L"uia", static_cast<int>(matches.size()), element, confidence);
}

SelectorResult LocateImage(HWND hwnd, const std::wstring& selector, const SelectorSpec& spec) {
    std::wstring path = ValueFor(spec, L"path");
    if (path.empty()) {
        return Error(selector, L"image", L"INVALID_SELECTOR", L"image selector requires path.");
    }
    int tolerance = 0;
    if (HasKey(spec, L"tolerance") && (!ParseInt(ValueFor(spec, L"tolerance"), tolerance) || tolerance < 0 || tolerance > 255)) {
        return Error(selector, L"image", L"INVALID_SELECTOR", L"image tolerance must be between 0 and 255.");
    }

    std::wstring screenshotPath = ArtifactsPath(L"selector_image_source.bmp");
    ScreenshotResult shot = CaptureWindowToBmp(hwnd, screenshotPath);
    if (!shot.ok) {
        return Error(selector, L"image", L"SCREENSHOT_FAILED", shot.error);
    }
    ImageMatchResult match = FindTemplateInBmp(screenshotPath, path, tolerance);
    if (!match.ok) {
        if (match.errorCode == L"IMAGE_MATCH_NOT_FOUND") {
            return Error(selector, L"image", L"LOCATOR_NOT_FOUND", match.errorMessage, match.matchCount);
        }
        if (match.errorCode == L"IMAGE_MATCH_NOT_UNIQUE") {
            return Error(selector, L"image", L"LOCATOR_NOT_UNIQUE", match.errorMessage, match.matchCount);
        }
        return Error(selector, L"image", match.errorCode.empty() ? L"UNKNOWN_ERROR" : match.errorCode, match.errorMessage, match.matchCount);
    }
    int clientX = 0;
    int clientY = 0;
    if (!WindowBitmapPointToClient(hwnd, match.x + (match.width / 2), match.y + (match.height / 2), clientX, clientY)) {
        return Error(selector, L"image", L"UNKNOWN_ERROR", L"Could not convert image match to client coordinates.", match.matchCount);
    }
    RECT rect = {clientX - (match.width / 2), clientY - (match.height / 2), clientX + (match.width / 2), clientY + (match.height / 2)};
    return SuccessPoint(selector, L"image", match.matchCount, hwnd, clientX, clientY, rect);
}

SelectorResult LocateText(HWND hwnd, const std::wstring& selector, const SelectorSpec& spec) {
    std::wstring text = ValueFor(spec, L"contains");
    std::wstring exactText = ValueFor(spec, L"exact");
    std::wstring searchText;
    std::wstring matchMode = L"contains";
    if (!exactText.empty()) {
        searchText = exactText;
        matchMode = L"exact";
    } else if (!text.empty()) {
        searchText = text;
    } else {
        return Error(selector, L"text", L"INVALID_SELECTOR", L"text selector requires contains or exact.");
    }

    int index = -1;
    if (HasKey(spec, L"index")) {
        if (!ParseInt(ValueFor(spec, L"index"), index) || index < 0) {
            return Error(selector, L"text", L"INVALID_SELECTOR", L"text index must be a non-negative integer.");
        }
    }

    OcrTextResult ocr = FindTextInWindow(hwnd, searchText, matchMode, false, index);
    if (!ocr.ok) {
        return Error(selector, L"text", ocr.errorCode.empty() ? L"OCR_FAILED" : ocr.errorCode, ocr.errorMessage, ocr.matchCount);
    }
    int bitmapX = ocr.boundingBox.left + ((ocr.boundingBox.right - ocr.boundingBox.left) / 2);
    int bitmapY = ocr.boundingBox.top + ((ocr.boundingBox.bottom - ocr.boundingBox.top) / 2);
    int clientX = 0;
    int clientY = 0;
    if (!WindowBitmapPointToClient(hwnd, bitmapX, bitmapY, clientX, clientY)) {
        return Error(selector, L"text", L"OCR_FAILED", L"Could not convert OCR text center to client coordinates.", 1);
    }
    SelectorResult result = SuccessPoint(selector, L"text", ocr.matchCount, hwnd, clientX, clientY, ocr.boundingBox);
    result.confidence = matchMode == L"exact" ? 0.90 : 0.80;
    result.matchedText = searchText;
    result.source = L"ocr";
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

SelectorResult LocateRelative(HWND hwnd, const std::wstring& selector, const SelectorSpec& spec) {
    std::wstring relation = ValueFor(spec, L"relation");
    if (relation.empty()) {
        relation = ValueFor(spec, L"position");
    }
    if (relation != L"right_of" && relation != L"left_of" && relation != L"below" &&
        relation != L"above" && relation != L"inside_window") {
        return Error(selector, L"relative", L"INVALID_SELECTOR", L"relative selector requires relation right_of, left_of, below, above, or inside_window.");
    }
    if (!HasAnyUiaTargetFilter(spec)) {
        return Error(selector, L"relative", L"INVALID_SELECTOR", L"relative selector requires a target_* filter.");
    }

    SelectorResult anchorResult;
    bool hasAnchor = relation != L"inside_window";
    if (hasAnchor) {
        std::wstring anchorSelector = ValueFor(spec, L"anchor");
        if (anchorSelector.empty()) {
            return Error(selector, L"relative", L"INVALID_SELECTOR", L"relative selector requires anchor unless relation=inside_window.");
        }
        anchorResult = LocateSelector(hwnd, anchorSelector);
        if (!anchorResult.ok) {
            SelectorResult result = Error(selector, L"relative", anchorResult.errorCode.empty() ? L"LOCATOR_NOT_FOUND" : anchorResult.errorCode, L"relative anchor failed: " + anchorResult.errorMessage, anchorResult.matchCount);
            result.extraJsonFields = L",\"anchor\":" + anchorResult.dataJson;
            result.dataJson = SelectorResultDataJson(result);
            return result;
        }
    }

    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) {
        return Error(selector, L"relative", tree.errorCode.empty() ? L"UNKNOWN_ERROR" : tree.errorCode, tree.errorMessage);
    }

    std::vector<UiaElementInfo> matches;
    for (const auto& element : tree.elements) {
        if (!UsableElementRect(element) || !UiaTargetMatches(element, spec)) {
            continue;
        }
        if (hasAnchor && !RelationMatches(anchorResult.rect, element.rect, relation)) {
            continue;
        }
        matches.push_back(element);
    }
    if (hasAnchor) {
        std::sort(matches.begin(), matches.end(), [&anchorResult](const UiaElementInfo& a, const UiaElementInfo& b) {
            return RectDistanceScore(anchorResult.rect, a.rect) < RectDistanceScore(anchorResult.rect, b.rect);
        });
    }
    if (matches.empty()) {
        return Error(selector, L"relative", L"LOCATOR_NOT_FOUND", L"No UIA element matched the relative selector.", 0);
    }

    int nth = -1;
    std::wstring nthError;
    if (!ParseNth(spec, nth, nthError)) {
        return Error(selector, L"relative", L"INVALID_SELECTOR", L"relative " + nthError, static_cast<int>(matches.size()));
    }
    if (nth >= 0) {
        if (nth >= static_cast<int>(matches.size())) {
            return Error(selector, L"relative", L"LOCATOR_NOT_FOUND", L"relative nth is outside matched elements.", static_cast<int>(matches.size()));
        }
    } else if (matches.size() > 1) {
        return Error(selector, L"relative", L"LOCATOR_NOT_UNIQUE", L"Relative selector matched multiple elements; provide nth.", static_cast<int>(matches.size()));
    } else {
        nth = 0;
    }

    SelectorResult result = SuccessUiaElement(hwnd, selector, L"relative", static_cast<int>(matches.size()), matches[static_cast<size_t>(nth)], 0.82);
    result.extraJsonFields = L",\"relation\":" + JsonString(relation);
    if (hasAnchor) {
        result.extraJsonFields += L",\"anchor\":" + anchorResult.dataJson;
    }
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

SelectorResult LocateNearText(HWND hwnd, const std::wstring& selector, const SelectorSpec& spec) {
    std::wstring text = ValueFor(spec, L"text");
    if (text.empty()) {
        text = ValueFor(spec, L"contains");
    }
    if (text.empty()) {
        return Error(selector, L"near_text", L"INVALID_SELECTOR", L"near_text selector requires text.");
    }
    std::wstring position = ValueFor(spec, L"position");
    if (position.empty()) {
        position = ValueFor(spec, L"relation");
    }
    if (position.empty()) {
        position = L"right_of";
    }
    if (position != L"right_of" && position != L"left_of" && position != L"below" && position != L"above") {
        return Error(selector, L"near_text", L"INVALID_SELECTOR", L"near_text position must be right_of, left_of, below, or above.");
    }
    if (!HasAnyUiaTargetFilter(spec)) {
        return Error(selector, L"near_text", L"INVALID_SELECTOR", L"near_text selector requires a target_* filter.");
    }

    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) {
        return Error(selector, L"near_text", tree.errorCode.empty() ? L"UNKNOWN_ERROR" : tree.errorCode, tree.errorMessage);
    }

    std::wstring matchMode = ValueFor(spec, L"match");
    if (matchMode.empty()) {
        matchMode = L"exact";
    }
    std::vector<UiaElementInfo> anchors;
    for (const auto& element : tree.elements) {
        bool matched = matchMode == L"contains" ? element.name.find(text) != std::wstring::npos : element.name == text;
        if (matched && UsableElementRect(element)) {
            anchors.push_back(element);
        }
    }
    if (anchors.empty()) {
        return Error(selector, L"near_text", L"LOCATOR_NOT_FOUND", L"No UIA text anchor matched near_text.", 0);
    }

    int anchorNth = -1;
    if (HasKey(spec, L"anchor_nth")) {
        if (!ParseInt(ValueFor(spec, L"anchor_nth"), anchorNth) || anchorNth < 0) {
            return Error(selector, L"near_text", L"INVALID_SELECTOR", L"anchor_nth must be a non-negative integer.", static_cast<int>(anchors.size()));
        }
        if (anchorNth >= static_cast<int>(anchors.size())) {
            return Error(selector, L"near_text", L"LOCATOR_NOT_FOUND", L"anchor_nth is outside matched text anchors.", static_cast<int>(anchors.size()));
        }
    } else if (anchors.size() > 1) {
        return Error(selector, L"near_text", L"LOCATOR_NOT_UNIQUE", L"near_text matched multiple text anchors; provide anchor_nth.", static_cast<int>(anchors.size()));
    } else {
        anchorNth = 0;
    }

    const UiaElementInfo& anchor = anchors[static_cast<size_t>(anchorNth)];
    std::vector<UiaElementInfo> matches;
    for (const auto& element : tree.elements) {
        if (!UsableElementRect(element) || !UiaTargetMatches(element, spec)) {
            continue;
        }
        if (!RelationMatches(anchor.rect, element.rect, position)) {
            continue;
        }
        matches.push_back(element);
    }
    std::sort(matches.begin(), matches.end(), [&anchor](const UiaElementInfo& a, const UiaElementInfo& b) {
        return RectDistanceScore(anchor.rect, a.rect) < RectDistanceScore(anchor.rect, b.rect);
    });
    if (matches.empty()) {
        return Error(selector, L"near_text", L"LOCATOR_NOT_FOUND", L"No target UIA element was found near matched text.", 0);
    }

    int nth = -1;
    std::wstring nthError;
    if (!ParseNth(spec, nth, nthError)) {
        return Error(selector, L"near_text", L"INVALID_SELECTOR", L"near_text " + nthError, static_cast<int>(matches.size()));
    }
    if (nth >= 0) {
        if (nth >= static_cast<int>(matches.size())) {
            return Error(selector, L"near_text", L"LOCATOR_NOT_FOUND", L"near_text nth is outside matched targets.", static_cast<int>(matches.size()));
        }
    } else if (matches.size() > 1) {
        return Error(selector, L"near_text", L"LOCATOR_NOT_UNIQUE", L"near_text matched multiple targets; provide nth.", static_cast<int>(matches.size()));
    } else {
        nth = 0;
    }

    SelectorResult result = SuccessUiaElement(hwnd, selector, L"near_text", static_cast<int>(matches.size()), matches[static_cast<size_t>(nth)], matchMode == L"exact" ? 0.86 : 0.78);
    result.matchedText = anchor.name;
    result.extraJsonFields = L",\"position\":" + JsonString(position)
        + L",\"text_source\":\"uia\""
        + L",\"anchor_rect\":" + RectJson(anchor.rect);
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

SelectorResult LocateChain(HWND hwnd, const std::wstring& selector) {
    std::wstring body = selector.substr(6);
    std::vector<std::wstring> parts = SplitLiteral(body, L"||");
    std::wstringstream attempts;
    attempts << L"[";
    bool first = true;
    SelectorResult lastFailure;
    int attemptIndex = 0;
    for (const auto& raw : parts) {
        std::wstring childSelector = Trim(raw);
        if (childSelector.empty()) {
            continue;
        }
        SelectorResult child = LocateSelector(hwnd, childSelector);
        if (!first) attempts << L",";
        first = false;
        attempts << L"{\"order\":" << attemptIndex
                 << L",\"selector\":" << JsonString(childSelector)
                 << L",\"ok\":" << (child.ok ? L"true" : L"false")
                 << L",\"method\":" << JsonString(child.locateMethod)
                 << L",\"error_code\":" << JsonString(child.errorCode)
                 << L",\"failure_reason\":" << JsonString(child.failureReason)
                 << L"}";
        ++attemptIndex;
        if (child.ok) {
            attempts << L"]";
            SelectorResult result = child;
            result.selector = selector;
            result.locateMethod = L"chain";
            result.finalMethod = child.locateMethod;
            result.confidence = child.confidence * 0.95;
            result.extraJsonFields = L",\"fallback_attempts\":" + attempts.str();
            result.dataJson = SelectorResultDataJson(result);
            return result;
        }
        lastFailure = child;
    }
    attempts << L"]";
    if (attemptIndex == 0) {
        return Error(selector, L"chain", L"INVALID_SELECTOR", L"chain selector requires at least one child selector.");
    }
    SelectorResult result = Error(selector, L"chain", lastFailure.errorCode.empty() ? L"LOCATOR_NOT_FOUND" : lastFailure.errorCode, L"All fallback selectors failed: " + lastFailure.errorMessage, lastFailure.matchCount);
    result.extraJsonFields = L",\"fallback_attempts\":" + attempts.str();
    result.dataJson = SelectorResultDataJson(result);
    return result;
}

}  // namespace

std::wstring SelectorResultDataJson(const SelectorResult& result) {
    std::wstringstream data;
    data << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"selector\":" << JsonString(result.selector)
         << L",\"method\":" << JsonString(result.locateMethod)
         << L",\"locate_method\":" << JsonString(result.locateMethod)
         << L",\"final_method\":" << JsonString(result.finalMethod.empty() ? result.locateMethod : result.finalMethod)
         << L",\"match_count\":" << result.matchCount
         << L",\"confidence\":" << result.confidence
         << L",\"client_point\":{\"x\":" << result.clientX << L",\"y\":" << result.clientY << L"}"
         << L",\"screen_point\":{\"x\":" << result.screenX << L",\"y\":" << result.screenY << L"}"
         << L",\"rect\":" << RectJson(result.rect)
         << L",\"element\":" << ElementJson(result)
         << L",\"matched_text\":" << JsonString(result.matchedText)
         << L",\"matched_name\":" << JsonString(result.elementName)
         << L",\"source\":" << JsonString(result.source)
         << L",\"failure_reason\":" << JsonString(result.failureReason)
         << L",\"artifacts\":{\"report_path\":" << JsonString(result.reportPath) << L"}"
         << result.extraJsonFields
         << L"}";
    return data.str();
}

SelectorResult LocateSelector(HWND hwnd, const std::wstring& selector) {
    if (StartsWith(selector, L"chain:")) {
        return LocateChain(hwnd, selector);
    }
    SelectorSpec spec;
    std::wstring parseError;
    if (!ParseSelector(selector, spec, parseError)) {
        return Error(selector, L"", L"INVALID_SELECTOR", parseError);
    }
    if (spec.type == L"coord") {
        return LocateCoord(hwnd, selector, spec);
    }
    if (spec.type == L"uia") {
        return LocateUia(hwnd, selector, spec);
    }
    if (spec.type == L"image") {
        return LocateImage(hwnd, selector, spec);
    }
    if (spec.type == L"text") {
        return LocateText(hwnd, selector, spec);
    }
    if (spec.type == L"relative") {
        return LocateRelative(hwnd, selector, spec);
    }
    if (spec.type == L"near_text") {
        return LocateNearText(hwnd, selector, spec);
    }
    return Error(selector, spec.type, L"INVALID_SELECTOR", L"Unknown selector type.");
}
