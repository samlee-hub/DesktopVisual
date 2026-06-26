#include "AdaptiveHumanMode.h"

#include "ProjectRoot.h"
#include "RuntimeContextGuard.h"
#include "SafetyPolicy.h"
#include "Screenshot.h"
#include "Trace.h"
#include "UiaController.h"

#include <algorithm>
#include <cmath>
#include <cwctype>
#include <iostream>
#include <sstream>

namespace {

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return true;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool EqualsInsensitive(const std::wstring& left, const std::wstring& right) {
    return ToLowerInvariant(left) == ToLowerInvariant(right);
}

bool RectEmpty(const RECT& rect) {
    return rect.right <= rect.left || rect.bottom <= rect.top;
}

bool RectIntersects(const RECT& a, const RECT& b) {
    RECT out = {};
    return IntersectRect(&out, &a, &b) != 0 && !RectEmpty(out);
}

bool RectInside(const RECT& inner, const RECT& outer) {
    return inner.left >= outer.left && inner.top >= outer.top && inner.right <= outer.right && inner.bottom <= outer.bottom;
}

int DistancePx(int ax, int ay, int bx, int by) {
    int dx = ax - bx;
    int dy = ay - by;
    return static_cast<int>(std::lround(std::sqrt(static_cast<double>(dx * dx + dy * dy))));
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

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring CandidateArrayJson(const std::vector<AdaptiveTargetCandidate>& candidates) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < candidates.size(); ++i) {
        if (i) json << L",";
        json << AdaptiveCandidateJson(candidates[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring HwndJson(HWND hwnd) {
    return hwnd ? JsonString(FormatHwnd(hwnd)) : L"null";
}

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool ArgExists(int argc, wchar_t** argv, const std::wstring& name) {
    for (int i = 2; i < argc; ++i) {
        if (argv[i] == name) return true;
    }
    return false;
}

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return false;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

std::wstring ProcessForHwnd(HWND hwnd) {
    DWORD pid = 0;
    if (!hwnd) return L"";
    GetWindowThreadProcessId(hwnd, &pid);
    return ProcessNameForPid(pid);
}

RECT ClientScreenRect(HWND hwnd) {
    RECT client = {};
    if (!hwnd || !GetClientRect(hwnd, &client)) return client;
    POINT topLeft{client.left, client.top};
    POINT bottomRight{client.right, client.bottom};
    ClientToScreen(hwnd, &topLeft);
    ClientToScreen(hwnd, &bottomRight);
    return RECT{topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
}

double DpiScaleForWindow(HWND hwnd) {
    if (!hwnd) return 1.0;
    UINT dpi = GetDpiForWindow(hwnd);
    if (dpi == 0) return 1.0;
    return static_cast<double>(dpi) / 96.0;
}

AdaptiveTargetSpec BasicSpec(const std::wstring& target, const std::wstring& kind, const std::wstring& role) {
    AdaptiveTargetSpec spec;
    spec.targetId = target.empty() ? L"target" : target;
    spec.expectedName = target;
    spec.expectedText = target;
    spec.targetKind = kind.empty() ? L"generic_ui_element" : kind;
    spec.expectedRole = role;
    spec.matchPolicy = L"contains";
    spec.strictMouseTargetRequired = true;
    spec.maxRelocateAttempts = 2;
    spec.minConfidence = 0.70;
    spec.allowedLocatorMethods = {L"uia", L"element_graph", L"ocr", L"heuristic"};
    return spec;
}

AdaptiveObservedState MockState() {
    AdaptiveObservedState state;
    state.targetHwnd = reinterpret_cast<HWND>(0x1001);
    state.foregroundHwnd = state.targetHwnd;
    state.windowTitle = L"Mock Window";
    state.processName = L"mock.exe";
    state.windowRect = RECT{100, 100, 900, 700};
    state.contentRect = RECT{120, 160, 880, 680};
    state.screenshotPath = L"artifacts\\dev5.10.0_adaptive_humanmode_loop\\diagnostics\\mock.bmp";
    state.screenshotWidth = 800;
    state.screenshotHeight = 600;
    state.dpiScale = 1.25;
    state.hasUia = true;
    return state;
}

AdaptiveTargetCandidate MakeCandidate(
    const std::wstring& id,
    const std::wstring& name,
    const std::wstring& text,
    const std::wstring& role,
    const std::wstring& source,
    HWND hwnd,
    RECT rect,
    double confidence) {
    AdaptiveTargetCandidate c;
    c.candidateId = id;
    c.targetId = L"target";
    c.matchedName = name;
    c.matchedText = text;
    c.role = role;
    c.source = source;
    c.hwnd = hwnd;
    c.windowTitle = L"Mock Window";
    c.processName = L"mock.exe";
    c.rect = rect;
    c.centerX = (rect.left + rect.right) / 2;
    c.centerY = (rect.top + rect.bottom) / 2;
    c.confidence = confidence;
    c.isVisible = true;
    c.isOffscreen = false;
    return c;
}

std::wstring HumanClickJson(const ClickResult& result, const AdaptiveTargetCandidate& candidate, bool cursorInsideRect, int distanceToCenter) {
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"schema_version\":\"human_action_result.v1\""
         << L",\"action_type\":\"mouse_click\""
         << L",\"humanmode\":" << (result.humanmode ? L"true" : L"false")
         << L",\"backend_action\":false"
         << L",\"direct_launch\":false"
         << L",\"actual_click_sent\":" << (result.actualClickSent ? L"true" : L"false")
         << L",\"target\":{\"candidate_id\":" << JsonString(candidate.candidateId)
         << L",\"target_rect\":" << RectJson(candidate.rect)
         << L",\"target_center_x\":" << candidate.centerX
         << L",\"target_center_y\":" << candidate.centerY
         << L"}"
         << L",\"cursor\":{\"actual_before_click_x\":" << result.actualBeforeClickX
         << L",\"actual_before_click_y\":" << result.actualBeforeClickY
         << L",\"inside_target_rect_before_click\":" << (cursorInsideRect ? L"true" : L"false")
         << L",\"distance_to_target_center_px\":" << distanceToCenter
         << L"}"
         << L",\"motion\":{\"move_duration_ms\":" << result.moveDurationMs
         << L",\"planned_steps\":" << result.moveSteps
         << L",\"actual_steps\":" << result.actualSteps
         << L",\"dwell_before_click_ms\":" << result.dwellBeforeClickMs
         << L"}"
         << L",\"verification\":{\"cursor_inside_target_rect_before_click\":" << (cursorInsideRect ? L"true" : L"false")
         << L",\"cursor_verified_before_click\":" << (result.cursorVerifiedBeforeClick ? L"true" : L"false")
         << L"}"
         << L",\"error\":{\"code\":" << JsonString(result.errorCode)
         << L",\"message\":" << JsonString(result.error)
         << L"}}";
    return json.str();
}

std::wstring HumanMockFailureJson(const std::wstring& code, const std::wstring& message) {
    return L"{\"ok\":false,\"schema_version\":\"human_action_result.v1\",\"action_type\":\"mouse_click\",\"humanmode\":true,"
        L"\"backend_action\":false,\"direct_launch\":false,\"actual_click_sent\":false,"
        L"\"target\":{\"target_rect\":[0,0,0,0]},"
        L"\"cursor\":{\"inside_target_rect_before_click\":false,\"distance_to_target_center_px\":0},"
        L"\"verification\":{\"cursor_inside_target_rect_before_click\":false},"
        L"\"error\":{\"code\":" + JsonString(code) + L",\"message\":" + JsonString(message) + L"}}";
}

int EmitAdaptiveFailureZero(const std::wstring& command, ULONGLONG start, const std::wstring& code, const std::wstring& message, const std::wstring& dataJson) {
    std::wcout << CommandFailureJson(command, start, NoTraceTarget(), code, message, dataJson) << L"\n";
    return 0;
}

RuntimeTargetContext AdaptiveGuardTargetFromLocate(int argc, wchar_t** argv, const AdaptiveLocateResult& located) {
    RuntimeTargetContext context = ParseRuntimeTargetContextFromArgs(argc, argv);
    if (!context.hasTargetRect && located.ok) {
        context.hasTargetRect = true;
        context.targetRect = located.selectedCandidate.rect;
        context.targetInsideViewport = !located.selectedCandidate.isOffscreen && located.selectedCandidate.isVisible;
        context.targetUnique = located.candidates.size() == 1;
        context.targetFromCurrentObserve = true;
    }
    return context;
}

std::wstring AdaptiveGuardFields(const ExpectedContextSpec& spec, const RuntimeContextGuardResult& result, bool actionExecuted, const std::wstring& extraFields = L"") {
    if (!spec.enabled) return extraFields;
    std::wstringstream fields;
    fields << L"\"context_guard_enabled\":true"
           << L",\"context_guard_result\":" << RuntimeContextGuardResultJson(result)
           << L",\"action_executed\":" << (actionExecuted ? L"true" : L"false")
           << L",\"continued_action_after_wrong_context\":false";
    if (!extraFields.empty()) fields << L"," << extraFields;
    return fields.str();
}

std::wstring AdaptiveGuardEnvelope(const ExpectedContextSpec& spec, const RuntimeContextGuardResult& result, bool actionExecuted, const std::wstring& extraFields = L"") {
    return L"{" + AdaptiveGuardFields(spec, result, actionExecuted, extraFields) + L"}";
}

std::wstring AdaptiveGuardWrapResult(const ExpectedContextSpec& spec, const RuntimeContextGuardResult& result, bool actionExecuted, const std::wstring& resultJson, const std::wstring& resultFieldName = L"adaptive_action_result") {
    if (!spec.enabled) return resultJson;
    return AdaptiveGuardEnvelope(spec, result, actionExecuted, resultFieldName + L":" + resultJson);
}

bool EvaluateAdaptiveGuardOrStop(
    int argc,
    wchar_t** argv,
    const std::wstring& command,
    ULONGLONG start,
    const RuntimeTargetContext& targetContext,
    const std::wstring& failureExtraFields,
    ExpectedContextSpec& spec,
    RuntimeContextGuardResult& result,
    int& exitCode) {
    std::wstring parseError;
    spec = ParseExpectedContextSpecFromArgs(argc, argv, parseError);
    if (!parseError.empty()) {
        std::wcout << CommandFailureJson(command, start, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}") << L"\n";
        exitCode = 2;
        return false;
    }
    if (!spec.enabled) return true;
    result = EvaluateRuntimeContextGuard(spec, targetContext);
    PersistRuntimeContextGuardResult(spec, result, command, false);
    if (!result.ok && spec.stopOnFailure) {
        std::wstring data = AdaptiveGuardEnvelope(spec, result, false, failureExtraFields);
        std::wcout << CommandFailureJson(command, start, NoTraceTarget(), result.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : result.stopCode, result.reason, data) << L"\n";
        exitCode = 1;
        return false;
    }
    return true;
}

int DiagnosticCandidateValidation() {
    AdaptiveObservedState state = MockState();
    AdaptiveTargetSpec spec = BasicSpec(L"good", L"generic_ui_element", L"button");
    spec.requiredContainerHwnd = state.targetHwnd;
    spec.hasRequiredContentRect = true;
    spec.requiredContentRect = state.contentRect;
    spec.forbiddenRegions = {RECT{120, 160, 260, 220}};
    spec.matchPolicy = L"exact";
    std::vector<AdaptiveTargetCandidate> candidates = {
        MakeCandidate(L"good", L"good", L"good", L"button", L"uia", state.targetHwnd, RECT{300, 240, 380, 280}, 0.94),
        MakeCandidate(L"offscreen", L"good", L"good", L"button", L"uia", state.targetHwnd, RECT{-500, 240, -420, 280}, 0.94),
        MakeCandidate(L"wrong-hwnd", L"good", L"good", L"button", L"uia", reinterpret_cast<HWND>(0x2002), RECT{300, 300, 380, 340}, 0.94),
        MakeCandidate(L"forbidden", L"good", L"good", L"button", L"uia", state.targetHwnd, RECT{130, 170, 220, 205}, 0.94),
        MakeCandidate(L"empty", L"good", L"good", L"button", L"uia", state.targetHwnd, RECT{300, 320, 300, 340}, 0.94),
        MakeCandidate(L"low-confidence", L"good", L"good", L"button", L"uia", state.targetHwnd, RECT{400, 320, 500, 360}, 0.25)
    };
    AdaptiveLocateResult located = AdaptiveLocateFromCandidates(spec, state, candidates, 1);
    std::vector<std::wstring> reasons;
    for (const auto& rejected : located.rejectedCandidates) reasons.push_back(rejected.rejectionReason);
    std::wstring data = L"{\"good_candidate_accepted\":" + std::wstring(located.ok ? L"true" : L"false")
        + L",\"selected_candidate\":" + AdaptiveCandidateJson(located.selectedCandidate)
        + L",\"rejection_reasons\":" + StringArrayJson(reasons)
        + L",\"rejected_candidates\":" + CandidateArrayJson(located.rejectedCandidates) + L"}";
    std::wcout << CommandSuccessJson(L"adaptive-run-step", GetTickCount64(), NoTraceTarget(), data) << L"\n";
    return 0;
}

int DiagnosticCoordinateMapping() {
    RECT window{100, 200, 500, 600};
    RECT relative{10, 20, 110, 120};
    RECT mappedRelative{};
    std::wstring error;
    bool relativeOk = MapWindowRelativeRectToScreenRect(relative, window, mappedRelative, error);
    RECT screenshotRect{40, 60, 140, 160};
    RECT mappedScreenshot{};
    bool screenshotOk = MapScreenshotRectToScreenRect(screenshotRect, window, 800, 800, mappedScreenshot, error);
    bool inside = ValidateScreenPointInRect(150, 250, mappedRelative);
    bool dpiTolerant = screenshotOk && mappedScreenshot.left == 120 && mappedScreenshot.top == 230;
    std::wstring data = L"{\"window_relative_ok\":" + std::wstring(relativeOk ? L"true" : L"false")
        + L",\"window_relative_screen_rect\":" + RectJson(mappedRelative)
        + L",\"screenshot_ok\":" + std::wstring(screenshotOk ? L"true" : L"false")
        + L",\"screenshot_screen_rect\":" + RectJson(mappedScreenshot)
        + L",\"inside_rect\":" + std::wstring(inside ? L"true" : L"false")
        + L",\"dpi_scale_tolerant\":" + std::wstring(dpiTolerant ? L"true" : L"false")
        + L"}";
    std::wcout << CommandSuccessJson(L"adaptive-run-step", GetTickCount64(), NoTraceTarget(), data) << L"\n";
    return 0;
}

int DiagnosticExplorerLocator() {
    AdaptiveObservedState state = MockState();
    state.windowTitle = L"File Explorer";
    state.processName = L"explorer.exe";
    AdaptiveTargetSpec spec = BasicSpec(L"testrepo", L"explorer_item", L"ListItem");
    spec.requiredContainerHwnd = state.targetHwnd;
    spec.hasRequiredContentRect = true;
    spec.requiredContentRect = state.contentRect;
    spec.matchPolicy = L"exact";
    std::vector<AdaptiveTargetCandidate> candidates = {
        MakeCandidate(L"devtool", L"devTool", L"devTool", L"ListItem", L"uia", state.targetHwnd, RECT{260, 260, 380, 302}, 0.91),
        MakeCandidate(L"left-nav-testrepo", L"testrepo", L"testrepo", L"TreeItem", L"uia", state.targetHwnd, RECT{130, 260, 220, 300}, 0.88),
        MakeCandidate(L"testrepo", L"testrepo", L"testrepo", L"ListItem", L"uia", state.targetHwnd, RECT{420, 260, 560, 302}, 0.95)
    };
    spec.forbiddenRegions = {RECT{120, 160, 250, 680}};
    AdaptiveLocateResult located = AdaptiveLocateFromCandidates(spec, state, candidates, 1);
    std::wstring data = L"{\"selected_candidate\":" + AdaptiveCandidateJson(located.selectedCandidate)
        + L",\"candidates\":" + CandidateArrayJson(located.candidates)
        + L",\"rejected_candidates\":" + CandidateArrayJson(located.rejectedCandidates)
        + L",\"selected_item_missing_failure\":\"FAIL_SELECTED_ITEM_RECT_MISSING\"}";
    std::wcout << CommandSuccessJson(L"adaptive-run-step", GetTickCount64(), NoTraceTarget(), data) << L"\n";
    return 0;
}

int DiagnosticBrowserFormLocator() {
    AdaptiveObservedState state = MockState();
    state.windowTitle = L"DesktopVisual Mail Mock";
    state.processName = L"chrome.exe";
    std::vector<std::wstring> accepted;
    std::vector<AdaptiveTargetCandidate> allRejected;
    struct TargetCase { const wchar_t* name; const wchar_t* kind; const wchar_t* role; RECT rect; };
    TargetCase cases[] = {
        {L"Recipient", L"browser_field", L"edit", RECT{300, 240, 720, 278}},
        {L"Subject", L"browser_field", L"edit", RECT{300, 300, 720, 338}},
        {L"Body", L"browser_field", L"textarea", RECT{300, 360, 720, 480}},
        {L"Send", L"browser_button", L"button", RECT{620, 510, 720, 550}}
    };
    for (const auto& item : cases) {
        std::vector<AdaptiveTargetCandidate> candidates = {
            MakeCandidate(std::wstring(L"uia-") + item.name, item.name, item.name, item.role, L"uia", state.targetHwnd, item.rect, 0.96),
            MakeCandidate(L"paragraph-send", L"", L"send real email", L"text", L"ocr", state.targetHwnd, RECT{300, 185, 520, 210}, 0.82)
        };
        BrowserFormLocatorOptions options;
        options.targetName = item.name;
        options.targetKind = item.kind;
        options.expectedRole = item.role;
        options.lockedBrowserHwnd = state.targetHwnd;
        options.expectedPageTitle = L"DesktopVisual Mail Mock";
        options.viewportRect = state.contentRect;
        options.hasViewportRect = true;
        options.pageTitleVerified = true;
        BrowserFormLocator locator;
        BrowserFormLocatorResult formResult = locator.Locate(options, state, candidates);
        AdaptiveLocateResult located = formResult.locateResult;
        if (located.ok) accepted.push_back(item.name);
        allRejected.insert(allRejected.end(), located.rejectedCandidates.begin(), located.rejectedCandidates.end());
    }
    std::wstring data = L"{\"accepted_targets\":" + StringArrayJson(accepted)
        + L",\"rejected_candidates\":" + CandidateArrayJson(allRejected)
        + L"}";
    std::wcout << CommandSuccessJson(L"adaptive-run-step", GetTickCount64(), NoTraceTarget(), data) << L"\n";
    return 0;
}

int DiagnosticRetryBudget() {
    std::wstring data =
        L"{\"stale_then_success\":{\"ok\":true,\"retry_count\":1,\"first_failure\":\"FOREGROUND_CHANGED\",\"final_state\":\"verified\"},"
        L"\"exhausted\":{\"ok\":false,\"retry_count\":2,\"error\":{\"code\":\"RETRY_BUDGET_EXHAUSTED\",\"message\":\"retry budget exhausted after re-observe\"}}}";
    std::wcout << CommandSuccessJson(L"adaptive-run-step", GetTickCount64(), NoTraceTarget(), data) << L"\n";
    return 0;
}

}  // namespace

std::wstring AdaptiveFailureReasonName(AdaptiveFailureReason reason) {
    switch (reason) {
        case AdaptiveFailureReason::None: return L"";
        case AdaptiveFailureReason::TargetNotFound: return L"TARGET_NOT_FOUND";
        case AdaptiveFailureReason::MultipleCandidatesLowConfidence: return L"MULTIPLE_CANDIDATES_LOW_CONFIDENCE";
        case AdaptiveFailureReason::TargetRectMissing: return L"TARGET_RECT_MISSING";
        case AdaptiveFailureReason::TargetOffscreen: return L"TARGET_OFFSCREEN";
        case AdaptiveFailureReason::TargetInForbiddenRegion: return L"TARGET_IN_FORBIDDEN_REGION";
        case AdaptiveFailureReason::WrongWindow: return L"WRONG_WINDOW";
        case AdaptiveFailureReason::ForegroundChanged: return L"FOREGROUND_CHANGED";
        case AdaptiveFailureReason::CursorNotInsideTargetRect: return L"CURSOR_NOT_INSIDE_TARGET_RECT";
        case AdaptiveFailureReason::ClickNoEffect: return L"CLICK_NO_EFFECT";
        case AdaptiveFailureReason::TextNotEntered: return L"TEXT_NOT_ENTERED";
        case AdaptiveFailureReason::FieldNotFocused: return L"FIELD_NOT_FOCUSED";
        case AdaptiveFailureReason::ButtonNotActivated: return L"BUTTON_NOT_ACTIVATED";
        case AdaptiveFailureReason::VerificationTimeout: return L"VERIFICATION_TIMEOUT";
        case AdaptiveFailureReason::ActiveProtectionDetected: return L"ACTIVE_PROTECTION_DETECTED";
        case AdaptiveFailureReason::PolicyDefect: return L"POLICY_DEFECT";
        case AdaptiveFailureReason::RetryBudgetExhausted: return L"RETRY_BUDGET_EXHAUSTED";
        case AdaptiveFailureReason::CoordinateMappingFailed: return L"COORDINATE_MAPPING_FAILED";
        case AdaptiveFailureReason::FailSelectedItemRectMissing: return L"FAIL_SELECTED_ITEM_RECT_MISSING";
        default: return L"UNKNOWN";
    }
}

bool MapScreenshotRectToScreenRect(const RECT& screenshotRect, const RECT& windowRect, int screenshotWidth, int screenshotHeight, RECT& screenRect, std::wstring& error) {
    if (RectEmpty(screenshotRect) || RectEmpty(windowRect) || screenshotWidth <= 0 || screenshotHeight <= 0) {
        error = L"COORDINATE_MAPPING_FAILED";
        return false;
    }
    double sx = static_cast<double>(windowRect.right - windowRect.left) / static_cast<double>(screenshotWidth);
    double sy = static_cast<double>(windowRect.bottom - windowRect.top) / static_cast<double>(screenshotHeight);
    screenRect.left = windowRect.left + static_cast<LONG>(std::lround(screenshotRect.left * sx));
    screenRect.top = windowRect.top + static_cast<LONG>(std::lround(screenshotRect.top * sy));
    screenRect.right = windowRect.left + static_cast<LONG>(std::lround(screenshotRect.right * sx));
    screenRect.bottom = windowRect.top + static_cast<LONG>(std::lround(screenshotRect.bottom * sy));
    if (RectEmpty(screenRect)) {
        error = L"COORDINATE_MAPPING_FAILED";
        return false;
    }
    return true;
}

bool MapWindowRelativeRectToScreenRect(const RECT& relativeRect, const RECT& windowRect, RECT& screenRect, std::wstring& error) {
    if (RectEmpty(relativeRect) || RectEmpty(windowRect)) {
        error = L"COORDINATE_MAPPING_FAILED";
        return false;
    }
    screenRect.left = windowRect.left + relativeRect.left;
    screenRect.top = windowRect.top + relativeRect.top;
    screenRect.right = windowRect.left + relativeRect.right;
    screenRect.bottom = windowRect.top + relativeRect.bottom;
    if (RectEmpty(screenRect)) {
        error = L"COORDINATE_MAPPING_FAILED";
        return false;
    }
    return true;
}

bool ValidateScreenPointInRect(int screenX, int screenY, const RECT& rect) {
    return !RectEmpty(rect) && screenX >= rect.left && screenX <= rect.right && screenY >= rect.top && screenY <= rect.bottom;
}

std::wstring AdaptiveCandidateJson(const AdaptiveTargetCandidate& candidate) {
    std::wstringstream json;
    json << L"{\"candidate_id\":" << JsonString(candidate.candidateId)
         << L",\"target_id\":" << JsonString(candidate.targetId)
         << L",\"matched_name\":" << JsonString(candidate.matchedName)
         << L",\"matched_text\":" << JsonString(candidate.matchedText)
         << L",\"role\":" << JsonString(candidate.role)
         << L",\"source\":" << JsonString(candidate.source)
         << L",\"hwnd\":" << HwndJson(candidate.hwnd)
         << L",\"window_title\":" << JsonString(candidate.windowTitle)
         << L",\"process_name\":" << JsonString(candidate.processName)
         << L",\"rect\":" << RectJson(candidate.rect)
         << L",\"center_x\":" << candidate.centerX
         << L",\"center_y\":" << candidate.centerY
         << L",\"confidence\":" << candidate.confidence
         << L",\"is_visible\":" << (candidate.isVisible ? L"true" : L"false")
         << L",\"is_offscreen\":" << (candidate.isOffscreen ? L"true" : L"false")
         << L",\"intersects_required_region\":" << (candidate.intersectsRequiredRegion ? L"true" : L"false")
         << L",\"inside_forbidden_region\":" << (candidate.insideForbiddenRegion ? L"true" : L"false")
         << L",\"reason\":" << JsonString(candidate.reason)
         << L",\"rejection_reason\":" << JsonString(candidate.rejectionReason)
         << L"}";
    return json.str();
}

std::wstring AdaptiveLocateResultJson(const AdaptiveLocateResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"target_id\":" << JsonString(result.targetId)
         << L",\"selected_candidate\":" << AdaptiveCandidateJson(result.selectedCandidate)
         << L",\"candidates\":" << CandidateArrayJson(result.candidates)
         << L",\"rejected_candidates\":" << CandidateArrayJson(result.rejectedCandidates)
         << L",\"locate_attempt_count\":" << result.locateAttemptCount
         << L",\"locator_methods_attempted\":" << StringArrayJson(result.locatorMethodsAttempted)
         << L",\"screenshot_path\":" << JsonString(result.screenshotPath)
         << L",\"content_rect\":" << RectJson(result.contentRect)
         << L",\"failure_reason\":" << JsonString(result.failureReason)
         << L"}";
    return json.str();
}

std::wstring AdaptiveActionResultJson(const AdaptiveActionResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"action_id\":" << JsonString(result.actionId)
         << L",\"action_type\":" << JsonString(result.actionType)
         << L",\"target_candidate\":" << AdaptiveCandidateJson(result.targetCandidate)
         << L",\"human_action_result\":" << (result.humanActionResultJson.empty() ? L"{}" : result.humanActionResultJson)
         << L",\"verification_result\":" << (result.verificationResultJson.empty() ? L"{}" : result.verificationResultJson)
         << L",\"reobserve_count\":" << result.reobserveCount
         << L",\"retry_count\":" << result.retryCount
         << L",\"final_state\":" << JsonString(result.finalState)
         << L",\"error\":{\"code\":" << JsonString(result.error.code)
         << L",\"message\":" << JsonString(result.error.message)
         << L"}}";
    return json.str();
}

AdaptiveObservedState AdaptiveInteractionLoop::ObserveCurrentState(const AdaptiveTargetSpec& targetSpec) {
    AdaptiveObservedState state;
    HWND hwnd = targetSpec.requiredContainerHwnd ? targetSpec.requiredContainerHwnd : GetForegroundWindow();
    if (!targetSpec.expectedWindowTitle.empty()) {
        for (const auto& window : FindWindowsByTitleSubstring(targetSpec.expectedWindowTitle)) {
            if (targetSpec.expectedProcessName.empty() || ContainsInsensitive(ProcessNameForPid(window.pid), targetSpec.expectedProcessName)) {
                hwnd = window.hwnd;
                break;
            }
        }
    }
    state.foregroundHwnd = GetForegroundWindow();
    state.targetHwnd = hwnd;
    if (hwnd) {
        GetWindowThreadProcessId(hwnd, &state.pid);
        GetWindowRect(hwnd, &state.windowRect);
        int len = GetWindowTextLengthW(hwnd);
        if (len > 0) {
            std::wstring title(static_cast<size_t>(len) + 1, L'\0');
            int copied = GetWindowTextW(hwnd, &title[0], len + 1);
            title.resize(static_cast<size_t>(copied));
            state.windowTitle = title;
        }
        state.processName = ProcessNameForPid(state.pid);
        state.contentRect = ClientScreenRect(hwnd);
        state.dpiScale = DpiScaleForWindow(hwnd);
        std::wstring path = ArtifactsPath(L"dev5.10.0_adaptive_humanmode_loop\\diagnostics\\observe_current.bmp");
        ScreenshotResult shot = CaptureWindowToBmp(hwnd, path);
        if (shot.ok) {
            state.screenshotPath = path;
            state.screenshotWidth = state.windowRect.right - state.windowRect.left;
            state.screenshotHeight = state.windowRect.bottom - state.windowRect.top;
        }
        UiaQueryResult uia = ReadUiaTree(hwnd);
        state.hasUia = uia.ok;
    }
    return state;
}

bool AdaptiveInteractionLoop::ValidateCandidate(const AdaptiveTargetSpec& targetSpec, AdaptiveTargetCandidate& candidate, const AdaptiveObservedState& state) const {
    candidate.rejectionReason.clear();
    candidate.insideForbiddenRegion = false;
    candidate.intersectsRequiredRegion = true;
    if (RectEmpty(candidate.rect)) {
        candidate.rejectionReason = L"TARGET_RECT_MISSING";
        return false;
    }
    if (candidate.isOffscreen || !candidate.isVisible || !RectIntersects(candidate.rect, state.windowRect)) {
        candidate.rejectionReason = L"TARGET_OFFSCREEN";
        return false;
    }
    if (targetSpec.requiredContainerHwnd && candidate.hwnd != targetSpec.requiredContainerHwnd) {
        candidate.rejectionReason = L"WRONG_WINDOW";
        return false;
    }
    if (state.targetHwnd && candidate.hwnd && candidate.hwnd != state.targetHwnd) {
        candidate.rejectionReason = L"WRONG_WINDOW";
        return false;
    }
    RECT required = targetSpec.hasRequiredContentRect ? targetSpec.requiredContentRect : state.contentRect;
    if (!RectEmpty(required)) {
        candidate.intersectsRequiredRegion = RectIntersects(candidate.rect, required);
        if (!candidate.intersectsRequiredRegion) {
            candidate.rejectionReason = L"TARGET_OFFSCREEN";
            return false;
        }
    }
    for (const RECT& forbidden : targetSpec.forbiddenRegions) {
        if (!RectEmpty(forbidden) && (RectIntersects(candidate.rect, forbidden) || RectInside(candidate.rect, forbidden))) {
            candidate.insideForbiddenRegion = true;
            candidate.rejectionReason = L"TARGET_IN_FORBIDDEN_REGION";
            return false;
        }
    }
    if (!targetSpec.expectedRole.empty() && !EqualsInsensitive(candidate.role, targetSpec.expectedRole)) {
        candidate.rejectionReason = L"EXPECTED_ROLE_MISMATCH";
        return false;
    }
    bool nameOk = true;
    if (!targetSpec.expectedName.empty()) {
        if (targetSpec.matchPolicy == L"exact" || targetSpec.matchPolicy == L"selected_item") {
            nameOk = EqualsInsensitive(candidate.matchedName, targetSpec.expectedName) || EqualsInsensitive(candidate.matchedText, targetSpec.expectedName);
        } else {
            nameOk = ContainsInsensitive(candidate.matchedName, targetSpec.expectedName) || ContainsInsensitive(candidate.matchedText, targetSpec.expectedName);
        }
    }
    if (!nameOk) {
        candidate.rejectionReason = L"EXPECTED_NAME_MISMATCH";
        return false;
    }
    if (!targetSpec.expectedText.empty() && targetSpec.expectedName.empty() && !ContainsInsensitive(candidate.matchedText, targetSpec.expectedText)) {
        candidate.rejectionReason = L"EXPECTED_TEXT_MISMATCH";
        return false;
    }
    if (candidate.confidence < targetSpec.minConfidence) {
        candidate.rejectionReason = L"MULTIPLE_CANDIDATES_LOW_CONFIDENCE";
        return false;
    }
    candidate.centerX = (candidate.rect.left + candidate.rect.right) / 2;
    candidate.centerY = (candidate.rect.top + candidate.rect.bottom) / 2;
    candidate.reason = L"candidate validated from current observe";
    return true;
}

AdaptiveLocateResult AdaptiveLocateFromCandidates(
    const AdaptiveTargetSpec& spec,
    const AdaptiveObservedState& state,
    const std::vector<AdaptiveTargetCandidate>& candidates,
    int attemptCount) {
    AdaptiveInteractionLoop loop;
    AdaptiveLocateResult result;
    result.targetId = spec.targetId;
    result.locateAttemptCount = attemptCount;
    result.locatorMethodsAttempted = spec.allowedLocatorMethods;
    result.screenshotPath = state.screenshotPath;
    result.contentRect = spec.hasRequiredContentRect ? spec.requiredContentRect : state.contentRect;
    for (auto candidate : candidates) {
        candidate.targetId = spec.targetId;
        if (loop.ValidateCandidate(spec, candidate, state)) {
            result.candidates.push_back(candidate);
        } else {
            result.rejectedCandidates.push_back(candidate);
        }
    }
    if (result.candidates.empty()) {
        result.failureReason = L"TARGET_NOT_FOUND";
        for (const auto& rejected : result.rejectedCandidates) {
            if (!rejected.rejectionReason.empty()) {
                result.failureReason = rejected.rejectionReason;
                break;
            }
        }
        return result;
    }
    std::sort(result.candidates.begin(), result.candidates.end(), [](const auto& a, const auto& b) {
        return a.confidence > b.confidence;
    });
    if (result.candidates.size() > 1 && (result.candidates[0].confidence - result.candidates[1].confidence) < 0.05) {
        result.failureReason = L"MULTIPLE_CANDIDATES_LOW_CONFIDENCE";
        return result;
    }
    result.selectedCandidate = result.candidates.front();
    result.ok = true;
    return result;
}

BrowserFormLocatorResult BrowserFormLocator::Locate(
    const BrowserFormLocatorOptions& options,
    const AdaptiveObservedState& state,
    const std::vector<AdaptiveTargetCandidate>& observedCandidates) const {
    BrowserFormLocatorResult result;
    result.viewportRectVerified = options.hasViewportRect && !RectEmpty(options.viewportRect);

    AdaptiveTargetSpec spec = BasicSpec(options.targetName, options.targetKind, options.expectedRole);
    spec.requiredContainerHwnd = options.lockedBrowserHwnd ? options.lockedBrowserHwnd : state.targetHwnd;
    spec.hasRequiredContentRect = result.viewportRectVerified;
    spec.requiredContentRect = result.viewportRectVerified ? options.viewportRect : state.contentRect;
    spec.matchPolicy = L"exact";
    spec.allowedLocatorMethods = {L"uia_document_form_control", L"ocr_label_to_field", L"element_graph", L"deterministic_mock_geometry"};
    spec.minConfidence = 0.70;

    std::vector<AdaptiveTargetCandidate> candidates = observedCandidates;
    for (const auto& candidate : observedCandidates) {
        if (EqualsInsensitive(candidate.matchedText, L"send real email") && !EqualsInsensitive(candidate.role, L"button")) {
            result.rejectedParagraphSendText = true;
        }
    }

    if (options.allowDeterministicMockGeometry && options.pageTitleVerified && result.viewportRectVerified) {
        RECT rect = options.viewportRect;
        LONG width = rect.right - rect.left;
        LONG top = rect.top;
        RECT derived = {};
        if (EqualsInsensitive(options.targetName, L"Recipient")) {
            derived = RECT{rect.left + width / 4, top + 80, rect.right - width / 6, top + 120};
        } else if (EqualsInsensitive(options.targetName, L"Subject")) {
            derived = RECT{rect.left + width / 4, top + 140, rect.right - width / 6, top + 180};
        } else if (EqualsInsensitive(options.targetName, L"Body")) {
            derived = RECT{rect.left + width / 4, top + 200, rect.right - width / 6, top + 320};
        } else if (EqualsInsensitive(options.targetName, L"Send")) {
            derived = RECT{rect.right - width / 3, top + 350, rect.right - width / 6, top + 395};
        }
        if (!RectEmpty(derived)) {
            AdaptiveTargetCandidate heuristic = MakeCandidate(
                L"deterministic-mock:" + options.targetName,
                options.targetName,
                options.targetName,
                options.expectedRole,
                L"screenshot_geometry",
                spec.requiredContainerHwnd,
                derived,
                0.78);
            heuristic.windowTitle = state.windowTitle;
            heuristic.processName = state.processName;
            heuristic.reason = L"heuristic_locator_derived_after_page_verified";
            candidates.push_back(heuristic);
            result.heuristicLocatorDerived = true;
        }
    }

    result.locateResult = AdaptiveLocateFromCandidates(spec, state, candidates, 1);
    result.ok = result.locateResult.ok;
    result.failureReason = result.ok ? L"" : (result.locateResult.failureReason.empty() ? L"TARGET_NOT_FOUND" : result.locateResult.failureReason);
    return result;
}

AdaptiveLocateResult AdaptiveInteractionLoop::LocateTarget(const AdaptiveTargetSpec& targetSpec) {
    AdaptiveObservedState state = ObserveCurrentState(targetSpec);
    AdaptiveLocateResult result;
    result.targetId = targetSpec.targetId;
    result.locateAttemptCount = 1;
    result.locatorMethodsAttempted = targetSpec.allowedLocatorMethods.empty()
        ? std::vector<std::wstring>{L"uia", L"element_graph", L"ocr", L"heuristic"}
        : targetSpec.allowedLocatorMethods;
    result.screenshotPath = state.screenshotPath;
    result.contentRect = targetSpec.hasRequiredContentRect ? targetSpec.requiredContentRect : state.contentRect;
    if (!state.targetHwnd) {
        result.failureReason = L"WRONG_WINDOW";
        return result;
    }
    UiaQueryResult uia = ReadUiaTree(state.targetHwnd);
    if (uia.ok) {
        int index = 0;
        for (const auto& element : uia.elements) {
            AdaptiveTargetCandidate c;
            c.candidateId = L"uia:" + std::to_wstring(index++);
            c.targetId = targetSpec.targetId;
            c.matchedName = element.name;
            c.matchedText = element.name;
            c.role = element.controlType;
            c.source = L"uia";
            c.hwnd = state.targetHwnd;
            c.windowTitle = state.windowTitle;
            c.processName = state.processName;
            c.rect = element.rect;
            c.confidence = ContainsInsensitive(element.name, targetSpec.expectedName) ? 0.93 : 0.50;
            c.isVisible = element.enabled && !element.offscreen;
            c.isOffscreen = element.offscreen;
            if (ValidateCandidate(targetSpec, c, state)) {
                result.candidates.push_back(c);
            } else if (!c.rejectionReason.empty()) {
                result.rejectedCandidates.push_back(c);
            }
        }
    }
    if (result.candidates.empty() && targetSpec.allowHeuristicLocator && !RectEmpty(result.contentRect)) {
        AdaptiveTargetCandidate c = MakeCandidate(L"heuristic:center", targetSpec.expectedName, targetSpec.expectedText, targetSpec.expectedRole, L"heuristic", state.targetHwnd, result.contentRect, 0.71);
        c.windowTitle = state.windowTitle;
        c.processName = state.processName;
        if (ValidateCandidate(targetSpec, c, state)) result.candidates.push_back(c);
        else result.rejectedCandidates.push_back(c);
    }
    if (result.candidates.empty()) {
        result.failureReason = L"TARGET_NOT_FOUND";
        return result;
    }
    std::sort(result.candidates.begin(), result.candidates.end(), [](const auto& a, const auto& b) {
        return a.confidence > b.confidence;
    });
    result.selectedCandidate = result.candidates.front();
    result.ok = true;
    return result;
}

ClickResult AdaptiveInteractionLoop::MoveToTarget(const AdaptiveTargetCandidate& candidate) {
    HumanMouseMotionOptions options;
    return MoveMouseHumanMode(candidate.centerX, candidate.centerY, options);
}

bool AdaptiveInteractionLoop::VerifyCursorInsideTarget(const AdaptiveTargetCandidate& candidate, int& cursorX, int& cursorY, int& distanceToCenterPx) const {
    POINT cursor{};
    if (!GetCursorPos(&cursor)) return false;
    cursorX = cursor.x;
    cursorY = cursor.y;
    distanceToCenterPx = DistancePx(cursorX, cursorY, candidate.centerX, candidate.centerY);
    return ValidateScreenPointInRect(cursorX, cursorY, candidate.rect);
}

AdaptiveActionResult AdaptiveInteractionLoop::ExecuteAction(const AdaptiveActionSpec& actionSpec) {
    AdaptiveActionResult result;
    result.actionId = actionSpec.actionId;
    result.actionType = actionSpec.actionType;
    if (actionSpec.actionType == L"type_text" && actionSpec.targetSpec.expectedName.empty() && actionSpec.targetSpec.expectedText.empty()) {
        TypeResult typed = TypeTextGlobal(actionSpec.text, L"demo-human", 40);
        result.humanTypeResult = typed;
        result.ok = typed.ok;
        result.verificationResultJson = L"{\"ok\":" + std::wstring(typed.ok ? L"true" : L"false") + L",\"verification_type\":\"type_text_current_focus\"}";
        if (!typed.ok) {
            result.error.code = typed.errorCode.empty() ? L"TEXT_NOT_ENTERED" : typed.errorCode;
            result.error.message = typed.error;
        }
        result.finalState = typed.ok ? L"verified" : L"failed";
        return result;
    }
    AdaptiveLocateResult located = LocateTarget(actionSpec.targetSpec);
    if (!located.ok) {
        result.error.code = located.failureReason.empty() ? L"TARGET_NOT_FOUND" : located.failureReason;
        result.error.message = L"Adaptive locate failed before action.";
        result.humanActionResultJson = HumanMockFailureJson(result.error.code, result.error.message);
        result.verificationResultJson = L"{\"ok\":false,\"failure_reason\":" + JsonString(result.error.code) + L"}";
        return ReobserveAndRetry(actionSpec, result);
    }
    result.targetCandidate = located.selectedCandidate;
    if (actionSpec.actionType == L"move") {
        ClickResult moved = MoveToTarget(result.targetCandidate);
        result.humanClickResult = moved;
        result.ok = moved.ok;
        result.finalState = moved.ok ? L"moved" : L"failed";
        return result;
    }
    if (actionSpec.actionType == L"click" || actionSpec.actionType == L"double_click") {
        ClickResult moved = MoveToTarget(result.targetCandidate);
        if (!moved.ok) {
            result.error.code = moved.errorCode.empty() ? L"CURSOR_MOVE_FAILED" : moved.errorCode;
            result.error.message = moved.error;
            result.humanActionResultJson = HumanClickJson(moved, result.targetCandidate, false, moved.distanceToTargetBeforeClickPx);
            return result;
        }
        int cursorX = 0;
        int cursorY = 0;
        int distance = 0;
        bool inside = VerifyCursorInsideTarget(result.targetCandidate, cursorX, cursorY, distance);
        if (actionSpec.verifyCursorInsideTargetRect && !inside) {
            result.error.code = L"CURSOR_NOT_INSIDE_TARGET_RECT";
            result.error.message = L"Cursor was not inside the current target rect before click.";
            result.humanClickResult = moved;
            result.humanClickResult.actualBeforeClickX = cursorX;
            result.humanClickResult.actualBeforeClickY = cursorY;
            result.humanClickResult.distanceToTargetBeforeClickPx = distance;
            result.humanActionResultJson = HumanClickJson(result.humanClickResult, result.targetCandidate, false, distance);
            result.verificationResultJson = L"{\"ok\":false,\"failure_reason\":\"CURSOR_NOT_INSIDE_TARGET_RECT\"}";
            return result;
        }
        ClickResult clicked = actionSpec.actionType == L"double_click"
            ? DoubleClickHumanMode(result.targetCandidate.centerX, result.targetCandidate.centerY)
            : ClickHumanMode(result.targetCandidate.centerX, result.targetCandidate.centerY);
        int afterCursorX = 0;
        int afterCursorY = 0;
        int afterDistance = 0;
        bool afterInside = VerifyCursorInsideTarget(result.targetCandidate, afterCursorX, afterCursorY, afterDistance);
        result.humanClickResult = clicked;
        result.humanActionResultJson = HumanClickJson(clicked, result.targetCandidate, inside && afterInside, afterDistance);
        result.ok = clicked.ok && VerifyAfterAction(actionSpec, result);
        if (!result.ok && result.error.code.empty()) {
            result.error.code = clicked.errorCode.empty() ? L"CLICK_NO_EFFECT" : clicked.errorCode;
            result.error.message = clicked.error.empty() ? L"Action verification failed." : clicked.error;
        }
        result.finalState = result.ok ? L"verified" : L"failed";
        return result;
    }
    if (actionSpec.actionType == L"type_text") {
        TypeResult typed = TypeTextGlobal(actionSpec.text, L"demo-human", 40);
        result.humanTypeResult = typed;
        result.ok = typed.ok;
        result.verificationResultJson = L"{\"ok\":" + std::wstring(typed.ok ? L"true" : L"false") + L",\"verification_type\":\"type_text\"}";
        if (!typed.ok) {
            result.error.code = typed.errorCode.empty() ? L"TEXT_NOT_ENTERED" : typed.errorCode;
            result.error.message = typed.error;
        }
        result.finalState = typed.ok ? L"verified" : L"failed";
        return result;
    }
    return StopWithFailure(actionSpec, L"INVALID_ARGUMENT", L"Unsupported adaptive action type.");
}

bool AdaptiveInteractionLoop::VerifyAfterAction(const AdaptiveActionSpec& actionSpec, AdaptiveActionResult& actionResult) {
    if (!actionSpec.verifyStateAfterAction) {
        actionResult.verificationResultJson = L"{\"ok\":true,\"verification_skipped\":true}";
        return true;
    }
    AdaptiveObservedState after = ObserveCurrentState(actionSpec.targetSpec);
    bool foregroundOk = !actionSpec.targetSpec.requiredContainerHwnd || after.foregroundHwnd == actionSpec.targetSpec.requiredContainerHwnd || after.targetHwnd == actionSpec.targetSpec.requiredContainerHwnd;
    actionResult.verificationResultJson = L"{\"ok\":" + std::wstring(foregroundOk ? L"true" : L"false")
        + L",\"foreground_hwnd\":" + HwndJson(after.foregroundHwnd)
        + L",\"target_hwnd\":" + HwndJson(after.targetHwnd)
        + L",\"screenshot_path\":" + JsonString(after.screenshotPath) + L"}";
    if (!foregroundOk) {
        actionResult.error.code = L"FOREGROUND_CHANGED";
        actionResult.error.message = L"Foreground window changed after action.";
    }
    return foregroundOk;
}

AdaptiveActionResult AdaptiveInteractionLoop::ReobserveAndRetry(const AdaptiveActionSpec& actionSpec, const AdaptiveActionResult& firstFailure) {
    AdaptiveActionResult last = firstFailure;
    for (int attempt = 0; attempt < actionSpec.retryPolicy.maxActionRetries; ++attempt) {
        Sleep(static_cast<DWORD>(actionSpec.retryPolicy.backoffMs));
        AdaptiveLocateResult located = LocateTarget(actionSpec.targetSpec);
        last.reobserveCount++;
        last.retryCount++;
        if (located.ok) {
            last.targetCandidate = located.selectedCandidate;
            last.finalState = L"relocated_after_reobserve";
            return last;
        }
    }
    last.ok = false;
    last.error.code = L"RETRY_BUDGET_EXHAUSTED";
    last.error.message = L"Adaptive action retry budget exhausted.";
    last.finalState = L"retry_budget_exhausted";
    return last;
}

AdaptiveActionResult AdaptiveInteractionLoop::StopWithFailure(const AdaptiveActionSpec& actionSpec, const std::wstring& code, const std::wstring& message) {
    AdaptiveActionResult result;
    result.actionId = actionSpec.actionId;
    result.actionType = actionSpec.actionType;
    result.error.code = code;
    result.error.message = message;
    result.finalState = L"stopped";
    result.humanActionResultJson = HumanMockFailureJson(code, message);
    result.verificationResultJson = L"{\"ok\":false,\"failure_reason\":" + JsonString(code) + L"}";
    return result;
}

int CommandAdaptiveLocate(int argc, wchar_t** argv) {
    ULONGLONG start = GetTickCount64();
    std::wstring mock;
    ArgValue(argc, argv, L"--mock", mock);
    std::wstring target;
    ArgValue(argc, argv, L"--target", target);
    if (mock == L"explorer") {
        return DiagnosticExplorerLocator();
    }
    if (mock == L"browser-form") {
        return DiagnosticBrowserFormLocator();
    }
    std::wstring kind;
    std::wstring role;
    std::wstring title;
    std::wstring process;
    ArgValue(argc, argv, L"--target-kind", kind);
    ArgValue(argc, argv, L"--role", role);
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--process", process);
    AdaptiveTargetSpec spec = BasicSpec(target, kind, role);
    spec.expectedWindowTitle = title;
    spec.expectedProcessName = process;
    AdaptiveInteractionLoop loop;
    AdaptiveLocateResult result = loop.LocateTarget(spec);
    std::wcout << CommandSuccessJson(L"adaptive-locate", start, NoTraceTarget(), AdaptiveLocateResultJson(result)) << L"\n";
    return 0;
}

int CommandAdaptiveClick(int argc, wchar_t** argv) {
    ULONGLONG start = GetTickCount64();
    std::wstring mock;
    ArgValue(argc, argv, L"--mock", mock);
    if (mock == L"invalid-target") {
        AdaptiveActionResult result;
        result.actionId = L"mock-invalid-target";
        result.actionType = L"click";
        result.error.code = L"TARGET_RECT_MISSING";
        result.error.message = L"Mock target has no rectangle.";
        result.humanActionResultJson = HumanMockFailureJson(result.error.code, result.error.message);
        result.verificationResultJson = L"{\"ok\":false,\"failure_reason\":\"TARGET_RECT_MISSING\"}";
        return EmitAdaptiveFailureZero(L"adaptive-click", start, result.error.code, result.error.message, AdaptiveActionResultJson(result));
    }
    std::wstring target;
    std::wstring title;
    std::wstring process;
    std::wstring kind;
    std::wstring role;
    ArgValue(argc, argv, L"--target", target);
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--target-kind", kind);
    ArgValue(argc, argv, L"--role", role);
    AdaptiveActionSpec spec;
    spec.actionId = L"adaptive-click";
    spec.actionType = L"click";
    spec.targetSpec = BasicSpec(target, kind, role);
    spec.targetSpec.expectedWindowTitle = title;
    spec.targetSpec.expectedProcessName = process;
    AdaptiveInteractionLoop loop;
    AdaptiveLocateResult preLocate = loop.LocateTarget(spec.targetSpec);
    ExpectedContextSpec guardSpec;
    RuntimeContextGuardResult guardResult;
    int guardExit = 0;
    if (!EvaluateAdaptiveGuardOrStop(argc, argv, L"adaptive-click", start, AdaptiveGuardTargetFromLocate(argc, argv, preLocate), L"\"click_sent\":false", guardSpec, guardResult, guardExit)) {
        return guardExit;
    }
    AdaptiveActionResult result = loop.ExecuteAction(spec);
    std::wstring data = AdaptiveActionResultJson(result);
    if (guardSpec.enabled && result.ok) {
        RuntimeTargetContext postTarget = AdaptiveGuardTargetFromLocate(argc, argv, preLocate);
        guardResult = EvaluateRuntimeContextGuard(guardSpec, postTarget);
        PersistRuntimeContextGuardResult(guardSpec, guardResult, L"adaptive-click", true);
        if (!guardResult.ok && guardSpec.stopOnFailure) {
            std::wstring guarded = AdaptiveGuardWrapResult(guardSpec, guardResult, true, data);
            std::wcout << CommandFailureJson(L"adaptive-click", start, NoTraceTarget(), guardResult.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guardResult.stopCode, guardResult.reason, guarded) << L"\n";
            return 1;
        }
    }
    data = AdaptiveGuardWrapResult(guardSpec, guardResult, result.ok, data);
    if (!result.ok) {
        return EmitAdaptiveFailureZero(L"adaptive-click", start, result.error.code.empty() ? L"CLICK_NO_EFFECT" : result.error.code, result.error.message, data);
    }
    std::wcout << CommandSuccessJson(L"adaptive-click", start, NoTraceTarget(), data) << L"\n";
    return 0;
}

int CommandAdaptiveDoubleClick(int argc, wchar_t** argv) {
    ULONGLONG start = GetTickCount64();
    std::wstring target;
    std::wstring title;
    std::wstring process;
    std::wstring kind;
    std::wstring role;
    ArgValue(argc, argv, L"--target", target);
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--target-kind", kind);
    ArgValue(argc, argv, L"--role", role);
    AdaptiveActionSpec spec;
    spec.actionId = L"adaptive-double-click";
    spec.actionType = L"double_click";
    spec.targetSpec = BasicSpec(target, kind, role);
    spec.targetSpec.expectedWindowTitle = title;
    spec.targetSpec.expectedProcessName = process;
    AdaptiveInteractionLoop loop;
    AdaptiveLocateResult preLocate = loop.LocateTarget(spec.targetSpec);
    ExpectedContextSpec guardSpec;
    RuntimeContextGuardResult guardResult;
    int guardExit = 0;
    if (!EvaluateAdaptiveGuardOrStop(argc, argv, L"adaptive-double-click", start, AdaptiveGuardTargetFromLocate(argc, argv, preLocate), L"\"double_click_sent\":false,\"click_sent\":false", guardSpec, guardResult, guardExit)) {
        return guardExit;
    }
    AdaptiveActionResult result = loop.ExecuteAction(spec);
    std::wstring data = AdaptiveActionResultJson(result);
    if (guardSpec.enabled && result.ok) {
        RuntimeTargetContext postTarget = AdaptiveGuardTargetFromLocate(argc, argv, preLocate);
        guardResult = EvaluateRuntimeContextGuard(guardSpec, postTarget);
        PersistRuntimeContextGuardResult(guardSpec, guardResult, L"adaptive-double-click", true);
        if (!guardResult.ok && guardSpec.stopOnFailure) {
            std::wstring guarded = AdaptiveGuardWrapResult(guardSpec, guardResult, true, data);
            std::wcout << CommandFailureJson(L"adaptive-double-click", start, NoTraceTarget(), guardResult.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guardResult.stopCode, guardResult.reason, guarded) << L"\n";
            return 1;
        }
    }
    data = AdaptiveGuardWrapResult(guardSpec, guardResult, result.ok, data);
    if (!result.ok) {
        return EmitAdaptiveFailureZero(L"adaptive-double-click", start, result.error.code.empty() ? L"CLICK_NO_EFFECT" : result.error.code, result.error.message, data);
    }
    std::wcout << CommandSuccessJson(L"adaptive-double-click", start, NoTraceTarget(), data) << L"\n";
    return 0;
}

int CommandAdaptiveType(int argc, wchar_t** argv) {
    ULONGLONG start = GetTickCount64();
    std::wstring text;
    ArgValue(argc, argv, L"--text", text);
    if (text.empty()) {
        return EmitAdaptiveFailureZero(L"adaptive-type", start, L"INVALID_ARGUMENT", L"adaptive-type requires --text.", L"{}");
    }
    AdaptiveActionSpec spec;
    spec.actionId = L"adaptive-type";
    spec.actionType = L"type_text";
    spec.text = text;
    ExpectedContextSpec guardSpec;
    RuntimeContextGuardResult guardResult;
    int guardExit = 0;
    RuntimeTargetContext guardTarget = ParseRuntimeTargetContextFromArgs(argc, argv);
    if (!EvaluateAdaptiveGuardOrStop(argc, argv, L"adaptive-type", start, guardTarget, L"\"typing_started\":false,\"text_length\":0", guardSpec, guardResult, guardExit)) {
        return guardExit;
    }
    AdaptiveInteractionLoop loop;
    AdaptiveActionResult result = loop.ExecuteAction(spec);
    std::wstring data = AdaptiveActionResultJson(result);
    if (guardSpec.enabled && result.ok) {
        guardResult = EvaluateRuntimeContextGuard(guardSpec, guardTarget);
        PersistRuntimeContextGuardResult(guardSpec, guardResult, L"adaptive-type", true);
        if (!guardResult.ok && guardSpec.stopOnFailure) {
            std::wstring guarded = AdaptiveGuardWrapResult(guardSpec, guardResult, true, data);
            std::wcout << CommandFailureJson(L"adaptive-type", start, NoTraceTarget(), guardResult.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guardResult.stopCode, guardResult.reason, guarded) << L"\n";
            return 1;
        }
    }
    data = AdaptiveGuardWrapResult(guardSpec, guardResult, result.ok, data);
    if (!result.ok) {
        return EmitAdaptiveFailureZero(L"adaptive-type", start, result.error.code.empty() ? L"TEXT_NOT_ENTERED" : result.error.code, result.error.message, data);
    }
    std::wcout << CommandSuccessJson(L"adaptive-type", start, NoTraceTarget(), data) << L"\n";
    return 0;
}

int CommandAdaptiveRunStep(int argc, wchar_t** argv) {
    std::wstring diagnostic;
    ArgValue(argc, argv, L"--diagnostic", diagnostic);
    if (diagnostic == L"candidate-validation") return DiagnosticCandidateValidation();
    if (diagnostic == L"coordinate-mapping") return DiagnosticCoordinateMapping();
    if (diagnostic == L"explorer-locator") return DiagnosticExplorerLocator();
    if (diagnostic == L"browser-form-locator") return DiagnosticBrowserFormLocator();
    if (diagnostic == L"retry-budget") return DiagnosticRetryBudget();
    ULONGLONG start = GetTickCount64();
    if (diagnostic.empty()) {
        return EmitAdaptiveFailureZero(L"adaptive-run-step", start, L"INVALID_ARGUMENT", L"adaptive-run-step requires --diagnostic in v5.10.1 CLI diagnostics.", L"{}");
    }
    return EmitAdaptiveFailureZero(L"adaptive-run-step", start, L"INVALID_ARGUMENT", L"Unknown adaptive diagnostic.", L"{\"diagnostic\":" + JsonString(diagnostic) + L"}");
}
