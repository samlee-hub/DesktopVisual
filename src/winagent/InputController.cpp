#include "InputController.h"

#include "MotionProfile.h"
#include "MotionSynthesizer.h"
#include "SafetyPolicy.h"
#include "UserAbortController.h"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <sstream>
#include <vector>

namespace {

struct MotionPlan {
    std::wstring mode;
    std::wstring profile;
    std::wstring pathType;
    int durationMs = 0;
    int stepCount = 1;
    int distancePx = 0;
    bool emergencyStopChecked = false;
    std::wstring operatorProfilePath;
    std::wstring operatorProfileQuality;
    std::wstring operatorProfileSource;
    int synthesizedPointCount = 0;
};

std::wstring NormalizeMoveMode(const std::wstring& mode) {
    if (mode.empty()) return L"operator-human";
    if (mode == L"human") return L"operator-human";
    return mode;
}

std::wstring NormalizeTypeMode(const std::wstring& mode) {
    if (mode.empty()) return L"demo-human";
    if (mode == L"human") return L"demo-human";
    return mode;
}

bool IsMoveModeValid(const std::wstring& mode) {
    return mode == L"instant" || mode == L"fast-human" || mode == L"demo-human" || mode == L"operator-human";
}

bool IsTypeModeValid(const std::wstring& mode) {
    return mode == L"instant" || mode == L"fast-human" || mode == L"demo-human";
}

int ClampInt(int value, int minValue, int maxValue) {
    return value < minValue ? minValue : (value > maxValue ? maxValue : value);
}

double ClampDouble(double value, double minValue, double maxValue) {
    return value < minValue ? minValue : (value > maxValue ? maxValue : value);
}

int Distance(const POINT& from, const POINT& to) {
    int dx = to.x - from.x;
    int dy = to.y - from.y;
    return static_cast<int>(std::round(std::sqrt(static_cast<double>(dx * dx + dy * dy))));
}

bool IsScreenPointInVirtualDesktop(int x, int y);

int AutoDuration(int distance) {
    if (distance < 80) return ClampInt(50 + distance, 50, 120);
    if (distance < 400) return ClampInt(120 + ((distance - 80) * 230 / 320), 120, 350);
    if (distance < 1200) return ClampInt(300 + ((distance - 400) * 500 / 800), 300, 800);
    return ClampInt(800 + ((distance - 1200) / 8), 800, 1200);
}

std::wstring TimestampMs() {
    SYSTEMTIME time;
    GetLocalTime(&time);
    wchar_t buffer[40] = {};
    swprintf_s(
        buffer,
        L"%04u-%02u-%02u %02u:%02u:%02u.%03u",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds);
    return buffer;
}

void SetUserAbort(ActionResult& result) {
    ReleaseUserAbortInputState();
    result.ok = false;
    result.errorCode = UserAbortStopCode();
    result.error = UserAbortMessage();
}

void SetUserAbort(ClickResult& result) {
    ReleaseUserAbortInputState();
    result.ok = false;
    result.errorCode = UserAbortStopCode();
    result.error = UserAbortMessage();
}

void SetUserAbort(DragResult& result) {
    ReleaseUserAbortInputState();
    result.ok = false;
    result.errorCode = UserAbortStopCode();
    result.error = UserAbortMessage();
}

void SetUserAbort(TypeResult& result) {
    ReleaseUserAbortInputState();
    result.ok = false;
    result.errorCode = UserAbortStopCode();
    result.error = UserAbortMessage();
}

bool SleepInterruptible(DWORD totalMs) {
    DWORD slept = 0;
    while (slept < totalMs) {
        if (IsUserAbortRequested()) {
            ReleaseUserAbortInputState();
            return false;
        }
        DWORD chunk = (totalMs - slept) < 10 ? (totalMs - slept) : 10;
        Sleep(chunk);
        slept += chunk;
    }
    return !IsUserAbortRequested();
}

double QpcMs(const LARGE_INTEGER& counter, const LARGE_INTEGER& frequency) {
    return (static_cast<double>(counter.QuadPart) * 1000.0) / static_cast<double>(frequency.QuadPart);
}

double QpcNowMs(const LARGE_INTEGER& frequency) {
    LARGE_INTEGER now = {};
    QueryPerformanceCounter(&now);
    return QpcMs(now, frequency);
}

bool WaitUntilQpcMs(double deadlineMs, const LARGE_INTEGER& frequency) {
    while (true) {
        if (IsUserAbortRequested()) {
            ReleaseUserAbortInputState();
            return false;
        }
        double remainingMs = deadlineMs - QpcNowMs(frequency);
        if (remainingMs <= 0.0) return true;
        if (remainingMs > 2.0) {
            Sleep(1);
        } else if (remainingMs > 0.35) {
            Sleep(0);
        } else {
            SwitchToThread();
        }
    }
}

double Percentile95(std::vector<double> values) {
    if (values.empty()) return 0.0;
    std::sort(values.begin(), values.end());
    size_t index = static_cast<size_t>(std::ceil(values.size() * 0.95)) - 1;
    if (index >= values.size()) index = values.size() - 1;
    return values[index];
}

void FinalizeMotionFramePacing(ClickResult& result) {
    result.frameTimestampsRecorded = !result.motionFrameTimestampsMs.empty();
    if (result.motionFrameTimestampsMs.size() < 2) {
        result.averageFrameIntervalMs = 0.0;
        result.p95FrameIntervalMs = 0.0;
        result.actualFrameRateHz = 0.0;
        return;
    }
    std::vector<double> intervals;
    intervals.reserve(result.motionFrameTimestampsMs.size() - 1);
    for (size_t i = 1; i < result.motionFrameTimestampsMs.size(); ++i) {
        double interval = result.motionFrameTimestampsMs[i] - result.motionFrameTimestampsMs[i - 1];
        if (interval >= 0.0) intervals.push_back(interval);
    }
    if (intervals.empty()) return;
    double total = std::accumulate(intervals.begin(), intervals.end(), 0.0);
    result.averageFrameIntervalMs = total / static_cast<double>(intervals.size());
    result.p95FrameIntervalMs = Percentile95(intervals);
    if (result.averageFrameIntervalMs > 0.0) {
        result.actualFrameRateHz = 1000.0 / result.averageFrameIntervalMs;
    }
}

bool PointOvershootsLinearTarget(const POINT& from, const POINT& target, const POINT& point, int epsilon) {
    int minX = (from.x < target.x ? from.x : target.x) - epsilon;
    int maxX = (from.x > target.x ? from.x : target.x) + epsilon;
    int minY = (from.y < target.y ? from.y : target.y) - epsilon;
    int maxY = (from.y > target.y ? from.y : target.y) + epsilon;
    return point.x < minX || point.x > maxX || point.y < minY || point.y > maxY;
}

HumanMouseMotionOptions NormalizeHumanOptions(const HumanMouseMotionOptions& requested, int distance) {
    HumanMouseMotionOptions options = requested;
    if (options.motionFrameRateHz < 0) options.motionFrameRateHz = 0;
    if (options.fastVisibleUi) {
        if (options.motionFrameRateHz <= 0) options.motionFrameRateHz = 165;
        double targetFrameMs = 1000.0 / static_cast<double>(options.motionFrameRateHz);
        int targetFrameCeil = static_cast<int>(std::ceil(targetFrameMs));
        if (options.maxStepIntervalMs <= 0 || options.maxStepIntervalMs > targetFrameCeil) options.maxStepIntervalMs = targetFrameCeil;
        if (options.targetEpsilonPx <= 0) options.targetEpsilonPx = 4;
        if (options.dwellBeforeClickMs <= 0) options.dwellBeforeClickMs = 25;
        if (options.postClickSettleMs <= 0) options.postClickSettleMs = 35;
        if (options.doubleClickIntervalMs <= 0) options.doubleClickIntervalMs = 60;

        int minDuration = 45;
        int minSteps = 3;
        if (distance > 400) {
            minDuration = 80;
            minSteps = 5;
        } else if (distance > 80) {
            minDuration = 60;
            minSteps = 4;
        }
        if (options.moveDurationMs <= 0) {
            options.moveDurationMs = minDuration;
        }
        options.moveDurationMs = options.moveDurationMs > minDuration ? options.moveDurationMs : minDuration;
        options.minSteps = options.minSteps > minSteps ? options.minSteps : minSteps;
        int intervalSteps = static_cast<int>(std::ceil(static_cast<double>(options.moveDurationMs) / targetFrameMs));
        options.minSteps = options.minSteps > intervalSteps ? options.minSteps : intervalSteps;
        return options;
    }
    if (options.maxStepIntervalMs <= 0) options.maxStepIntervalMs = 35;
    if (options.targetEpsilonPx <= 0) options.targetEpsilonPx = 3;
    if (options.dwellBeforeClickMs <= 0) options.dwellBeforeClickMs = 180;
    if (options.postClickSettleMs <= 0) options.postClickSettleMs = 180;
    if (options.doubleClickIntervalMs <= 0) options.doubleClickIntervalMs = 140;

    int minDuration = 500;
    int minSteps = 18;
    if (distance < 80) {
        minDuration = 250;
        minSteps = 8;
    } else if (distance <= 400) {
        minDuration = 350;
        minSteps = 12;
    } else {
        minDuration = 550;
        minSteps = 18;
    }
    if (options.moveDurationMs <= 0) {
        if (distance < 80) {
            options.moveDurationMs = 250;
        } else if (distance <= 400) {
            options.moveDurationMs = ClampInt(350 + ((distance - 80) * 200 / 320), 350, 550);
        } else {
            options.moveDurationMs = ClampInt(550 + ((distance - 400) * 300 / 800), 550, 850);
        }
    }
    options.moveDurationMs = options.moveDurationMs > minDuration ? options.moveDurationMs : minDuration;
    options.minSteps = options.minSteps > minSteps ? options.minSteps : minSteps;
    int intervalSteps = (options.moveDurationMs + options.maxStepIntervalMs - 1) / options.maxStepIntervalMs;
    options.minSteps = options.minSteps > intervalSteps ? options.minSteps : intervalSteps;
    if (options.motionFrameRateHz > 0) {
        options.motionFrameRateHz = ClampInt(options.motionFrameRateHz, 30, 500);
        double targetFrameMs = 1000.0 / static_cast<double>(options.motionFrameRateHz);
        int frameSteps = static_cast<int>(std::ceil(static_cast<double>(options.moveDurationMs) / targetFrameMs));
        options.minSteps = options.minSteps > frameSteps ? options.minSteps : frameSteps;
        int targetFrameCeil = static_cast<int>(std::ceil(targetFrameMs));
        if (options.maxStepIntervalMs <= 0 || options.maxStepIntervalMs > targetFrameCeil) {
            options.maxStepIntervalMs = targetFrameCeil;
        }
    }
    return options;
}

std::vector<POINT> BuildHumanPath(const POINT& from, const POINT& to, int steps, bool smoothstep) {
    std::vector<POINT> points;
    points.reserve(static_cast<size_t>(steps > 1 ? steps : 1));
    for (int i = 1; i <= steps; ++i) {
        double t = static_cast<double>(i) / static_cast<double>(steps);
        double ease = smoothstep ? t * t * (3.0 - 2.0 * t) : t;
        POINT point = {
            static_cast<LONG>(std::round(from.x + (to.x - from.x) * ease)),
            static_cast<LONG>(std::round(from.y + (to.y - from.y) * ease))};
        points.push_back(point);
    }
    return points;
}

bool SendMouseEvent(DWORD flag) {
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        return false;
    }
    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = flag;
    return SendInput(1, &input, sizeof(INPUT)) == 1;
}

bool MoveCursorToPoint(const POINT& point, bool requireExact = false) {
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        return false;
    }
    POINT currentBefore = {};
    if (GetCursorPos(&currentBefore) && Distance(currentBefore, point) <= 2) return true;

    if (SetCursorPos(point.x, point.y)) return true;

    int attempts = requireExact ? 30 : 1;
    for (int i = 0; i < attempts; ++i) {
        POINT current = {};
        if (!GetCursorPos(&current)) return false;
        if (Distance(current, point) <= 2) return true;

        INPUT relative = {};
        relative.type = INPUT_MOUSE;
        relative.mi.dx = point.x - current.x;
        relative.mi.dy = point.y - current.y;
        relative.mi.dwFlags = MOUSEEVENTF_MOVE;
        if (SendInput(1, &relative, sizeof(INPUT)) != 1) return false;
        if (!SleepInterruptible(8)) return false;
        if (!requireExact) return true;
    }

    int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (width <= 1 || height <= 1) return false;

    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dx = static_cast<LONG>(((point.x - left) * 65535LL) / (width - 1));
    input.mi.dy = static_cast<LONG>(((point.y - top) * 65535LL) / (height - 1));
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
    if (SendInput(1, &input, sizeof(INPUT)) != 1) return false;
    if (!SleepInterruptible(5)) return false;
    if (!requireExact) return true;

    for (int i = 0; i < 12; ++i) {
        POINT current = {};
        if (!GetCursorPos(&current)) return false;
        if (Distance(current, point) <= 2) return true;

        INPUT relative = {};
        relative.type = INPUT_MOUSE;
        relative.mi.dx = point.x - current.x;
        relative.mi.dy = point.y - current.y;
        relative.mi.dwFlags = MOUSEEVENTF_MOVE;
        if (SendInput(1, &relative, sizeof(INPUT)) != 1) return false;
        if (!SleepInterruptible(8)) return false;
    }

    POINT finalPoint = {};
    return GetCursorPos(&finalPoint) && Distance(finalPoint, point) <= 2;
}

void FillHumanMotionFields(ClickResult& result, const POINT& from, const POINT& target, const HumanMouseMotionOptions& options, int distance) {
    result.humanmode = true;
    result.backendAction = false;
    result.directLaunch = false;
    result.moveMode = L"humanmode-paced";
    result.moveProfile = L"humanmode-paced";
    result.pathType = L"smoothstep";
    result.easing = options.useSmoothstepEasing ? L"smoothstep" : L"linear";
    result.distancePx = distance;
    result.durationMs = options.moveDurationMs;
    result.moveDurationMs = options.moveDurationMs;
    result.stepCount = options.minSteps;
    result.moveSteps = options.minSteps;
    result.targetMotionFrameRateHz = options.motionFrameRateHz;
    result.targetFrameIntervalMs = options.motionFrameRateHz > 0 ? 1000.0 / static_cast<double>(options.motionFrameRateHz) : 0.0;
    result.motionFrameRateBestEffort = options.motionFrameRateHz > 0 && options.motionFrameRateBestEffort;
    result.actualSteps = 0;
    result.targetEpsilonPx = options.targetEpsilonPx;
    result.dwellBeforeClickMs = options.dwellBeforeClickMs;
    result.postClickSettleMs = options.postClickSettleMs;
    result.doubleClickIntervalMs = options.doubleClickIntervalMs;
    result.emergencyStopChecked = true;
    result.cursorBeforeX = from.x;
    result.cursorBeforeY = from.y;
    result.targetScreenX = target.x;
    result.targetScreenY = target.y;
}

bool IsWithinTarget(const POINT& point, const POINT& target, int epsilon, int& distancePx) {
    distancePx = Distance(point, target);
    return distancePx <= epsilon;
}

ClickResult MoveHumanModeCore(int screenX, int screenY, const HumanMouseMotionOptions& requestedOptions, const std::wstring& actionMethod) {
    ClickResult result;
    result.actionMethod = actionMethod;
    result.targetClientX = -1;
    result.targetClientY = -1;
    result.foregroundBefore = GetForegroundWindow();
    result.foregroundAfter = result.foregroundBefore;
    result.focusVerified = false;
    if (IsUserAbortRequested()) {
        result.humanmode = true;
        SetUserAbort(result);
        return result;
    }
    if (!IsScreenPointInVirtualDesktop(screenX, screenY)) {
        result.humanmode = true;
        result.errorCode = L"FAIL_INVALID_TARGET";
        result.error = L"Screen coordinates are outside the virtual desktop.";
        return result;
    }

    POINT from = {};
    if (!GetCursorPos(&from)) {
        result.humanmode = true;
        result.errorCode = L"FAIL_MOVE_TIMEOUT";
        result.error = L"GetCursorPos failed before input.";
        return result;
    }
    POINT target = {screenX, screenY};
    int distance = Distance(from, target);
    HumanMouseMotionOptions options = NormalizeHumanOptions(requestedOptions, distance);
    FillHumanMotionFields(result, from, target, options, distance);
    result.plannedPath = BuildHumanPath(from, target, options.minSteps, options.useSmoothstepEasing);
    result.moveStartTs = TimestampMs();

    LARGE_INTEGER frequency = {};
    LARGE_INTEGER startCounter = {};
    bool qpcOk = QueryPerformanceFrequency(&frequency) != FALSE && QueryPerformanceCounter(&startCounter) != FALSE && frequency.QuadPart > 0;
    double startMs = qpcOk ? QpcMs(startCounter, frequency) : 0.0;
    double frameIntervalMs = options.minSteps > 1 ? static_cast<double>(options.moveDurationMs) / static_cast<double>(options.minSteps) : 0.0;
    int sleepBase = !qpcOk && options.minSteps > 0 ? options.moveDurationMs / options.minSteps : 0;
    int sleepRemainder = !qpcOk && options.minSteps > 0 ? options.moveDurationMs % options.minSteps : 0;
    for (int i = 0; i < options.minSteps; ++i) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        if (qpcOk && i > 0 && frameIntervalMs > 0.0) {
            if (!WaitUntilQpcMs(startMs + (frameIntervalMs * static_cast<double>(i)), frequency)) {
                SetUserAbort(result);
                return result;
            }
        }
        const POINT& point = result.plannedPath[static_cast<size_t>(i)];
        if (!MoveCursorToPoint(point)) {
            result.errorCode = L"FAIL_MOVE_TIMEOUT";
            result.error = L"Could not move system cursor.";
            FinalizeMotionFramePacing(result);
            return result;
        }
        if (qpcOk) {
            LARGE_INTEGER frameCounter = {};
            QueryPerformanceCounter(&frameCounter);
            result.motionFrameTimestampsMs.push_back(QpcMs(frameCounter, frequency) - QpcMs(startCounter, frequency));
        }
        if (PointOvershootsLinearTarget(from, target, point, options.targetEpsilonPx)) {
            result.cursorOvershoot = true;
        }
        result.actualSteps++;
        int sleepMs = !qpcOk ? sleepBase + (i < sleepRemainder ? 1 : 0) : 0;
        if (!qpcOk && sleepMs > 0 && !SleepInterruptible(static_cast<DWORD>(sleepMs))) {
            SetUserAbort(result);
            FinalizeMotionFramePacing(result);
            return result;
        }
    }
    result.moveEndTs = TimestampMs();
    FinalizeMotionFramePacing(result);

    POINT finalPoint = {};
    if (!GetCursorPos(&finalPoint)) {
        result.errorCode = L"FAIL_MOVE_TIMEOUT";
        result.error = L"GetCursorPos failed after move.";
        return result;
    }
    int finalDistance = 0;
    bool within = IsWithinTarget(finalPoint, target, options.targetEpsilonPx, finalDistance);
    if (!within && options.retryFinalPositionIfNeeded) {
        if (!MoveCursorToPoint(target, true)) {
            result.errorCode = L"FAIL_MOVE_TIMEOUT";
            result.error = L"Final cursor retry failed.";
            result.targetMiss = true;
            return result;
        }
        if (!SleepInterruptible(25)) {
            SetUserAbort(result);
            return result;
        }
        GetCursorPos(&finalPoint);
        within = IsWithinTarget(finalPoint, target, options.targetEpsilonPx, finalDistance);
    }
    result.finalX = finalPoint.x;
    result.finalY = finalPoint.y;
    result.cursorAfterX = finalPoint.x;
    result.cursorAfterY = finalPoint.y;
    result.actualBeforeClickX = finalPoint.x;
    result.actualBeforeClickY = finalPoint.y;
    result.distanceToTargetBeforeClickPx = finalDistance;
    result.withinTargetEpsilonBeforeClick = within;
    result.cursorVerifiedBeforeClick = within;
    result.targetMiss = !within;
    if (!within) {
        result.errorCode = L"FAIL_CURSOR_NOT_AT_TARGET";
        result.error = L"Cursor did not reach the target epsilon.";
        return result;
    }
    result.ok = true;
    return result;
}

ClickResult ClickHumanModeCore(
    int screenX,
    int screenY,
    const HumanMouseMotionOptions& options,
    int clickCount,
    const std::wstring& actionMethod,
    DWORD downFlag = MOUSEEVENTF_LEFTDOWN,
    DWORD upFlag = MOUSEEVENTF_LEFTUP) {
    ClickResult result = MoveHumanModeCore(screenX, screenY, options, actionMethod);
    if (!result.ok) return result;
    POINT target = {screenX, screenY};

    result.ok = false;
    result.dwellStartTs = TimestampMs();
    if (!SleepInterruptible(static_cast<DWORD>(result.dwellBeforeClickMs))) {
        SetUserAbort(result);
        return result;
    }
    result.dwellCompletedBeforeClick = true;

    POINT beforeClick = {};
    if (!GetCursorPos(&beforeClick)) {
        result.errorCode = L"FAIL_MOVE_TIMEOUT";
        result.error = L"GetCursorPos failed before click.";
        return result;
    }
    int distanceBefore = 0;
    bool withinBefore = IsWithinTarget(beforeClick, target, result.targetEpsilonPx, distanceBefore);
    if (!withinBefore && options.retryFinalPositionIfNeeded) {
        if (!MoveCursorToPoint(target, true)) {
            result.actualBeforeClickX = beforeClick.x;
            result.actualBeforeClickY = beforeClick.y;
            result.distanceToTargetBeforeClickPx = distanceBefore;
            result.withinTargetEpsilonBeforeClick = false;
            result.cursorVerifiedBeforeClick = false;
            result.clickAfterMoveEnd = !result.moveEndTs.empty();
            result.errorCode = L"FAIL_CURSOR_NOT_AT_TARGET";
            result.error = L"Cursor drifted before click and final correction failed.";
            return result;
        }
        if (!SleepInterruptible(static_cast<DWORD>(result.dwellBeforeClickMs))) {
            SetUserAbort(result);
            return result;
        }
        result.dwellCompletedBeforeClick = true;
        if (!GetCursorPos(&beforeClick)) {
            result.errorCode = L"FAIL_MOVE_TIMEOUT";
            result.error = L"GetCursorPos failed after pre-click correction.";
            return result;
        }
        withinBefore = IsWithinTarget(beforeClick, target, result.targetEpsilonPx, distanceBefore);
    }
    result.actualBeforeClickX = beforeClick.x;
    result.actualBeforeClickY = beforeClick.y;
    result.distanceToTargetBeforeClickPx = distanceBefore;
    result.withinTargetEpsilonBeforeClick = withinBefore;
    result.cursorVerifiedBeforeClick = withinBefore;
    result.clickAfterMoveEnd = !result.moveEndTs.empty();
    if (!withinBefore) {
        result.errorCode = L"FAIL_CURSOR_NOT_AT_TARGET";
        result.error = L"Cursor is not within target epsilon before click.";
        return result;
    }

    result.clickDownTs = TimestampMs();
    if (!SendMouseEvent(downFlag)) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"FAIL_SENDINPUT";
            result.error = L"SendInput failed for mouse down.";
        }
        return result;
    }
    result.clickUpTs = TimestampMs();
    if (!SendMouseEvent(upFlag)) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"FAIL_SENDINPUT";
            result.error = L"SendInput failed for mouse up.";
        }
        return result;
    }
    result.actualClickSent = true;

    if (clickCount == 2) {
        if (!SleepInterruptible(static_cast<DWORD>(result.doubleClickIntervalMs))) {
            SetUserAbort(result);
            return result;
        }
        result.secondClickDownTs = TimestampMs();
        if (!SendMouseEvent(downFlag)) {
            if (IsUserAbortRequested()) {
                SetUserAbort(result);
            } else {
                result.errorCode = L"FAIL_SENDINPUT";
                result.error = L"SendInput failed for second mouse down.";
            }
            return result;
        }
        result.secondClickUpTs = TimestampMs();
        if (!SendMouseEvent(upFlag)) {
            if (IsUserAbortRequested()) {
                SetUserAbort(result);
            } else {
                result.errorCode = L"FAIL_SENDINPUT";
                result.error = L"SendInput failed for second mouse up.";
            }
            return result;
        }
        result.actualDoubleClickSent = true;
    }

    if (!SleepInterruptible(static_cast<DWORD>(result.postClickSettleMs))) {
        SetUserAbort(result);
        return result;
    }
    POINT after = {};
    if (!GetCursorPos(&after)) {
        result.errorCode = L"FAIL_MOVE_TIMEOUT";
        result.error = L"GetCursorPos failed after click.";
        return result;
    }
    result.cursorAfterX = after.x;
    result.cursorAfterY = after.y;
    result.foregroundAfter = GetForegroundWindow();
    result.ok = true;
    return result;
}

MotionPlan BuildMotionPlan(const POINT& from, const POINT& to, const std::wstring& requestedMode, int requestedDurationMs) {
    MotionPlan plan;
    plan.mode = NormalizeMoveMode(requestedMode);
    plan.profile = plan.mode;
    plan.distancePx = Distance(from, to);
    if (plan.mode == L"instant") {
        plan.pathType = L"direct";
        plan.durationMs = 0;
        plan.stepCount = 1;
        return plan;
    }
    if (plan.mode == L"operator-human") {
        plan.pathType = L"operator-statistical";
        plan.durationMs = requestedDurationMs > 0 ? requestedDurationMs : AutoDuration(plan.distancePx);
        plan.stepCount = ClampInt(plan.durationMs / 8, 8, 240);
        plan.emergencyStopChecked = true;
        return plan;
    }

    int duration = requestedDurationMs > 0 ? requestedDurationMs : AutoDuration(plan.distancePx);
    if (plan.mode == L"fast-human") {
        duration = ClampInt(duration, 0, 1500);
        plan.pathType = L"bezier";
    } else {
        duration = ClampInt(duration, 0, 3000);
        plan.pathType = L"bezier-demo";
    }
    plan.durationMs = duration;
    plan.stepCount = ClampInt(duration / 8, 8, plan.mode == L"fast-human" ? 80 : 180);
    plan.emergencyStopChecked = true;
    return plan;
}

void CopyMotionToClick(const MotionPlan& plan, ClickResult& result) {
    result.moveMode = plan.mode;
    result.moveProfile = plan.profile;
    result.pathType = plan.pathType;
    result.distancePx = plan.distancePx;
    result.durationMs = plan.durationMs;
    result.moveDurationMs = plan.durationMs;
    result.stepCount = plan.stepCount;
    result.moveSteps = plan.stepCount;
    result.emergencyStopChecked = plan.emergencyStopChecked;
    result.operatorProfilePath = plan.operatorProfilePath;
    result.operatorProfileQuality = plan.operatorProfileQuality;
    result.operatorProfileSource = plan.operatorProfileSource;
    result.synthesizedPointCount = plan.synthesizedPointCount;
}

void CopyMotionToDrag(const MotionPlan& plan, DragResult& result) {
    result.moveMode = plan.mode;
    result.moveProfile = plan.profile;
    result.pathType = plan.pathType;
    result.distancePx = plan.distancePx;
    result.durationMs = plan.durationMs;
    result.stepCount = plan.stepCount;
    result.emergencyStopChecked = plan.emergencyStopChecked;
    result.operatorProfilePath = plan.operatorProfilePath;
    result.operatorProfileQuality = plan.operatorProfileQuality;
    result.operatorProfileSource = plan.operatorProfileSource;
    result.synthesizedPointCount = plan.synthesizedPointCount;
}

bool ActivateWindow(HWND hwnd, HWND& foregroundBefore, HWND& foregroundAfter) {
    foregroundBefore = GetForegroundWindow();
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        foregroundAfter = foregroundBefore;
        return false;
    }
    if (IsIconic(hwnd)) {
        ShowWindow(hwnd, SW_RESTORE);
    } else {
        ShowWindow(hwnd, SW_SHOW);
    }

    DWORD targetThread = GetWindowThreadProcessId(hwnd, nullptr);
    DWORD currentThread = GetCurrentThreadId();
    HWND currentForeground = GetForegroundWindow();
    DWORD foregroundThread = currentForeground ? GetWindowThreadProcessId(currentForeground, nullptr) : 0;

    bool attachedTarget = targetThread && targetThread != currentThread && AttachThreadInput(currentThread, targetThread, TRUE);
    bool attachedForeground = foregroundThread && foregroundThread != currentThread && foregroundThread != targetThread && AttachThreadInput(currentThread, foregroundThread, TRUE);

    BringWindowToTop(hwnd);
    SetActiveWindow(hwnd);
    SetForegroundWindow(hwnd);

    for (int i = 0; i < 10; ++i) {
        foregroundAfter = GetForegroundWindow();
        if (foregroundAfter == hwnd) break;
        if (!SleepInterruptible(50)) {
            if (attachedForeground) AttachThreadInput(currentThread, foregroundThread, FALSE);
            if (attachedTarget) AttachThreadInput(currentThread, targetThread, FALSE);
            return false;
        }
        BringWindowToTop(hwnd);
        SetForegroundWindow(hwnd);
    }

    if (attachedForeground) AttachThreadInput(currentThread, foregroundThread, FALSE);
    if (attachedTarget) AttachThreadInput(currentThread, targetThread, FALSE);

    foregroundAfter = GetForegroundWindow();
    return foregroundAfter == hwnd;
}

ActionResult SendInputs(const std::vector<INPUT>& inputs) {
    ActionResult result;
    if (inputs.empty()) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"No inputs to send.";
        return result;
    }
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    UINT sent = SendInput(static_cast<UINT>(inputs.size()), const_cast<INPUT*>(inputs.data()), sizeof(INPUT));
    if (sent != inputs.size()) {
        result.errorCode = L"SEND_INPUT_FAILED";
        result.error = L"SendInput did not send all events.";
        return result;
    }
    result.ok = true;
    return result;
}

WORD VirtualKeyForName(std::wstring keyName) {
    std::transform(keyName.begin(), keyName.end(), keyName.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towupper(ch));
    });
    if (keyName.size() == 1) {
        wchar_t ch = keyName[0];
        if ((ch >= L'A' && ch <= L'Z') || (ch >= L'0' && ch <= L'9')) return static_cast<WORD>(ch);
    }
    if (keyName == L"CTRL" || keyName == L"CONTROL") return VK_CONTROL;
    if (keyName == L"SHIFT") return VK_SHIFT;
    if (keyName == L"ALT") return VK_MENU;
    if (keyName == L"WIN" || keyName == L"WINDOWS") return VK_LWIN;
    if (keyName == L"SPACE") return VK_SPACE;
    if (keyName == L"ENTER") return VK_RETURN;
    if (keyName == L"ESC" || keyName == L"ESCAPE") return VK_ESCAPE;
    if (keyName == L"TAB") return VK_TAB;
    if (keyName == L"DELETE" || keyName == L"DEL") return VK_DELETE;
    if (keyName == L"BACKSPACE" || keyName == L"BKSP") return VK_BACK;
    if (keyName == L"LEFT") return VK_LEFT;
    if (keyName == L"RIGHT") return VK_RIGHT;
    if (keyName == L"UP") return VK_UP;
    if (keyName == L"DOWN") return VK_DOWN;
    if (keyName == L"HOME") return VK_HOME;
    if (keyName == L"END") return VK_END;
    if (keyName == L"PAGEUP" || keyName == L"PGUP") return VK_PRIOR;
    if (keyName == L"PAGEDOWN" || keyName == L"PGDN") return VK_NEXT;
    if (keyName.size() >= 2 && keyName[0] == L'F') {
        try {
            int f = std::stoi(keyName.substr(1));
            if (f >= 1 && f <= 12) return static_cast<WORD>(VK_F1 + f - 1);
        } catch (...) {
        }
    }
    return 0;
}

std::vector<std::wstring> SplitCombo(const std::wstring& combo) {
    std::vector<std::wstring> parts;
    size_t start = 0;
    while (start <= combo.size()) {
        size_t plus = combo.find(L'+', start);
        std::wstring part = combo.substr(start, plus == std::wstring::npos ? std::wstring::npos : plus - start);
        if (!part.empty()) parts.push_back(part);
        if (plus == std::wstring::npos) break;
        start = plus + 1;
    }
    return parts;
}

ActionResult SendVirtualKey(WORD vk) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wVk = vk;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_KEYUP;
    return SendInputs({down, up});
}

ActionResult SendUnicodeChar(wchar_t ch) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = ch;
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    return SendInputs({down, up});
}

void AppendVirtualKey(std::vector<INPUT>& inputs, WORD vk) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wVk = vk;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
}

void AppendUnicodeChar(std::vector<INPUT>& inputs, wchar_t ch) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = ch;
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
}

void AppendTextInputUnit(std::vector<INPUT>& inputs, const std::wstring& text, size_t& index) {
    wchar_t ch = text[index];
    if (ch == L'\r') {
        if (index + 1 < text.size() && text[index + 1] == L'\n') {
            ++index;
        }
        AppendVirtualKey(inputs, VK_RETURN);
        return;
    }
    if (ch == L'\n') {
        AppendVirtualKey(inputs, VK_RETURN);
        return;
    }
    if (ch == L'\t') {
        AppendVirtualKey(inputs, VK_TAB);
        return;
    }
    AppendUnicodeChar(inputs, ch);
}

ActionResult SendTextInputUnit(const std::wstring& text, size_t& index) {
    std::vector<INPUT> inputs;
    inputs.reserve(2);
    AppendTextInputUnit(inputs, text, index);
    return SendInputs(inputs);
}

std::vector<std::vector<INPUT>> BuildLineInputBatches(const std::wstring& text) {
    std::vector<std::vector<INPUT>> batches;
    std::vector<INPUT> current;
    current.reserve(128);
    for (size_t i = 0; i < text.size(); ++i) {
        AppendTextInputUnit(current, text, i);
        bool lineBreak = i < text.size() && (text[i] == L'\n' || text[i] == L'\r');
        if (lineBreak || current.size() >= 240) {
            batches.push_back(current);
            current.clear();
            current.reserve(128);
        }
    }
    if (!current.empty()) {
        batches.push_back(current);
    }
    return batches;
}

bool SendInputBatches(const std::vector<std::vector<INPUT>>& batches, int lineDelayMs, TypeResult& result) {
    result.keyboardSendBatchCount = 0;
    result.lineDelayMs = ClampInt(lineDelayMs, 0, 500);
    result.batchKeyEvents = true;
    for (size_t i = 0; i < batches.size(); ++i) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return false;
        }
        ActionResult sent = SendInputs(batches[i]);
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return false;
        }
        result.keyboardSendBatchCount++;
        if (i + 1 < batches.size() && result.lineDelayMs > 0 &&
            !SleepInterruptible(static_cast<DWORD>(result.lineDelayMs))) {
            SetUserAbort(result);
            return false;
        }
    }
    return true;
}

bool ClientPointToScreen(HWND hwnd, int x, int y, POINT& point, std::wstring& error) {
    if (x < 0 || y < 0) {
        error = L"Client coordinates must be non-negative.";
        return false;
    }
    RECT client = {};
    if (!GetClientRect(hwnd, &client)) {
        error = L"GetClientRect failed.";
        return false;
    }
    if (x >= client.right || y >= client.bottom) {
        error = L"Client coordinates are outside target window.";
        return false;
    }
    point = {x, y};
    if (!ClientToScreen(hwnd, &point)) {
        error = L"ClientToScreen failed.";
        return false;
    }
    return true;
}

bool IsScreenPointInVirtualDesktop(int x, int y) {
    int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    return width > 0 && height > 0 &&
           x >= left && y >= top &&
           x < left + width && y < top + height;
}

bool MoveCursorWithPlan(const POINT& from, const POINT& to, const MotionPlan& plan) {
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        return false;
    }
    if (plan.mode == L"instant") {
        return SetCursorPos(to.x, to.y) != FALSE;
    }

    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    int dx = to.x - from.x;
    int dy = to.y - from.y;
    double offset = plan.mode == L"fast-human" ? 14.0 : 36.0;
    POINT c1 = {
        ClampInt(from.x + dx / 3 - static_cast<int>(dy == 0 ? 0 : offset), 0, screenW - 1),
        ClampInt(from.y + dy / 3 + static_cast<int>(dx == 0 ? 0 : offset), 0, screenH - 1)};
    POINT c2 = {
        ClampInt(from.x + (2 * dx) / 3 + static_cast<int>(dy == 0 ? 0 : offset), 0, screenW - 1),
        ClampInt(from.y + (2 * dy) / 3 - static_cast<int>(dx == 0 ? 0 : offset), 0, screenH - 1)};

    int sleepBase = plan.stepCount > 0 ? plan.durationMs / plan.stepCount : 0;
    int sleepRemainder = plan.stepCount > 0 ? plan.durationMs % plan.stepCount : 0;
    for (int i = 1; i <= plan.stepCount; ++i) {
        if (IsUserAbortRequested()) {
            ReleaseUserAbortInputState();
            return false;
        }
        double t = static_cast<double>(i) / static_cast<double>(plan.stepCount);
        double ease = t * t * (3.0 - 2.0 * t);
        double u = 1.0 - ease;
        int x = static_cast<int>(std::round(u * u * u * from.x + 3 * u * u * ease * c1.x + 3 * u * ease * ease * c2.x + ease * ease * ease * to.x));
        int y = static_cast<int>(std::round(u * u * u * from.y + 3 * u * u * ease * c1.y + 3 * u * ease * ease * c2.y + ease * ease * ease * to.y));
        if (!SetCursorPos(ClampInt(x, 0, screenW - 1), ClampInt(y, 0, screenH - 1))) return false;
        int sleepMs = sleepBase + (i <= sleepRemainder ? 1 : 0);
        if (sleepMs > 0 && !SleepInterruptible(static_cast<DWORD>(sleepMs))) return false;
    }
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        return false;
    }
    return SetCursorPos(to.x, to.y) != FALSE;
}

bool MoveCursorWithOperatorPath(const std::vector<POINT>& points, int durationMs) {
    if (points.empty()) return false;
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        return false;
    }
    int sleepBase = points.size() > 1 ? durationMs / static_cast<int>(points.size() - 1) : 0;
    int sleepRemainder = points.size() > 1 ? durationMs % static_cast<int>(points.size() - 1) : 0;
    for (size_t i = 1; i < points.size(); ++i) {
        if (IsUserAbortRequested()) {
            ReleaseUserAbortInputState();
            return false;
        }
        if (!SetCursorPos(points[i].x, points[i].y)) return false;
        if (i + 1 < points.size()) {
            int sleepMs = sleepBase + (static_cast<int>(i - 1) < sleepRemainder ? 1 : 0);
            if (sleepMs > 0 && !SleepInterruptible(static_cast<DWORD>(sleepMs))) return false;
        }
    }
    if (IsUserAbortRequested()) {
        ReleaseUserAbortInputState();
        return false;
    }
    const POINT& last = points.back();
    return SetCursorPos(last.x, last.y) != FALSE;
}

bool LoadProfileForOperatorUse(const std::wstring& profilePath, bool allowSyntheticProfile, OperatorMotionProfile& profile, std::wstring& errorCode, std::wstring& error) {
    std::wstring path = profilePath.empty() ? DefaultOperatorMotionProfilePath() : profilePath;
    MotionProfileOperationResult loaded = LoadOperatorMotionProfile(path, profile);
    if (!loaded.ok) {
        errorCode = loaded.errorCode.empty() ? L"MOTION_PROFILE_INVALID" : loaded.errorCode;
        error = loaded.errorMessage;
        return false;
    }
    if (profile.source != L"human") {
        if (!allowSyntheticProfile) {
            errorCode = (profilePath.empty() || (profile.source != L"synthetic" && profile.source != L"sample")) ? L"MOTION_PROFILE_NOT_HUMAN" : L"MOTION_PROFILE_TEST_ONLY";
            error = L"Operator-human requires a human profile unless --allow-synthetic-profile is explicitly provided for tests.";
            return false;
        }
        if (profile.source != L"synthetic" && profile.source != L"sample") {
            errorCode = L"MOTION_PROFILE_NOT_HUMAN";
            error = L"Operator motion profile source is not human.";
            return false;
        }
    }
    return true;
}

bool BuildOperatorPlan(const POINT& from, const POINT& to, int requestedDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile, MotionPlan& plan, std::vector<POINT>& operatorPath, std::wstring& errorCode, std::wstring& error) {
    OperatorMotionProfile profile;
    if (!LoadProfileForOperatorUse(profilePath, allowSyntheticProfile, profile, errorCode, error)) {
        return false;
    }
    MotionSynthesisResult synth = SynthesizeOperatorMotionPath(from, to, requestedDurationMs, profile);
    if (!synth.ok) {
        errorCode = synth.errorCode.empty() ? L"MOTION_PROFILE_INVALID" : synth.errorCode;
        error = synth.errorMessage;
        return false;
    }
    plan.mode = L"operator-human";
    plan.profile = L"operator-human";
    plan.pathType = L"operator-statistical";
    plan.durationMs = synth.durationMs;
    plan.stepCount = static_cast<int>(synth.points.size());
    plan.distancePx = synth.distancePx;
    plan.emergencyStopChecked = true;
    plan.operatorProfilePath = synth.profilePath;
    plan.operatorProfileQuality = synth.profileQuality;
    plan.operatorProfileSource = synth.profileSource;
    plan.synthesizedPointCount = static_cast<int>(synth.points.size());
    operatorPath = synth.points;
    return true;
}

void FillClickPoint(ClickResult& result, int clientX, int clientY, const POINT& screenPoint) {
    result.targetClientX = clientX;
    result.targetClientY = clientY;
    result.targetScreenX = screenPoint.x;
    result.targetScreenY = screenPoint.y;
}

ClickResult MouseClick(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, DWORD downFlag, DWORD upFlag, int clickCount, const std::wstring& actionMethod, const std::wstring& profilePath, bool allowSyntheticProfile) {
    ClickResult result;
    result.actionMethod = actionMethod;
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    std::wstring normalizedMode = NormalizeMoveMode(moveMode);
    if (!IsMoveModeValid(normalizedMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported move mode.";
        return result;
    }
    POINT screenPoint = {};
    std::wstring pointError;
    if (!ClientPointToScreen(hwnd, x, y, screenPoint, pointError)) {
        result.errorCode = pointError.find(L"outside") != std::wstring::npos || pointError.find(L"non-negative") != std::wstring::npos ? L"INVALID_ARGUMENT" : L"UNKNOWN_ERROR";
        result.error = pointError;
        return result;
    }
    FillClickPoint(result, x, y, screenPoint);
    if (!ActivateWindow(hwnd, result.foregroundBefore, result.foregroundAfter)) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"WINDOW_FOCUS_FAILED";
            result.error = L"Could not focus target window.";
        }
        return result;
    }
    result.focusVerified = true;

    POINT before = {};
    if (!GetCursorPos(&before)) {
        result.errorCode = L"CURSOR_MOVE_FAILED";
        result.error = L"GetCursorPos failed before input.";
        return result;
    }
    result.cursorBeforeX = before.x;
    result.cursorBeforeY = before.y;
    MotionPlan plan;
    std::vector<POINT> operatorPath;
    if (normalizedMode == L"operator-human") {
        if (!BuildOperatorPlan(before, screenPoint, moveDurationMs, profilePath, allowSyntheticProfile, plan, operatorPath, result.errorCode, result.error)) {
            return result;
        }
    } else {
        plan = BuildMotionPlan(before, screenPoint, normalizedMode, moveDurationMs);
    }
    CopyMotionToClick(plan, result);
    bool moved = normalizedMode == L"operator-human"
        ? MoveCursorWithOperatorPath(operatorPath, plan.durationMs)
        : MoveCursorWithPlan(before, screenPoint, plan);
    if (!moved) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"CURSOR_MOVE_FAILED";
            result.error = L"Could not move system cursor.";
        }
        return result;
    }

    for (int i = 0; i < clickCount; ++i) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        INPUT down = {};
        down.type = INPUT_MOUSE;
        down.mi.dwFlags = downFlag;
        INPUT up = {};
        up.type = INPUT_MOUSE;
        up.mi.dwFlags = upFlag;
        ActionResult sent = SendInputs({down, up});
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        if (clickCount > 1 && i + 1 < clickCount && !SleepInterruptible(60)) {
            SetUserAbort(result);
            return result;
        }
    }
    if (clickCount > 0) {
        result.actualClickSent = true;
        result.actualDoubleClickSent = clickCount > 1;
        result.sendInputUsed = true;
    }

    POINT after = {};
    if (!GetCursorPos(&after)) {
        result.errorCode = L"CURSOR_MOVE_FAILED";
        result.error = L"GetCursorPos failed after input.";
        return result;
    }
    result.cursorAfterX = after.x;
    result.cursorAfterY = after.y;
    result.ok = true;
    if (!SleepInterruptible(40)) {
        SetUserAbort(result);
        return result;
    }
    return result;
}

ClickResult ScreenMouseAction(int screenX, int screenY, const std::wstring& moveMode, int moveDurationMs, DWORD downFlag, DWORD upFlag, int clickCount, const std::wstring& actionMethod, const std::wstring& profilePath, bool allowSyntheticProfile) {
    ClickResult result;
    result.actionMethod = actionMethod;
    result.targetClientX = -1;
    result.targetClientY = -1;
    result.targetScreenX = screenX;
    result.targetScreenY = screenY;
    result.foregroundBefore = GetForegroundWindow();
    result.foregroundAfter = result.foregroundBefore;
    result.focusVerified = false;
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    std::wstring normalizedMode = NormalizeMoveMode(moveMode);
    if (!IsMoveModeValid(normalizedMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported move mode.";
        return result;
    }
    if (!IsScreenPointInVirtualDesktop(screenX, screenY)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Screen coordinates are outside the virtual desktop.";
        return result;
    }

    POINT before = {};
    if (!GetCursorPos(&before)) {
        result.errorCode = L"CURSOR_MOVE_FAILED";
        result.error = L"GetCursorPos failed before input.";
        return result;
    }
    result.cursorBeforeX = before.x;
    result.cursorBeforeY = before.y;
    POINT target = {screenX, screenY};
    MotionPlan plan;
    std::vector<POINT> operatorPath;
    if (normalizedMode == L"operator-human") {
        if (!BuildOperatorPlan(before, target, moveDurationMs, profilePath, allowSyntheticProfile, plan, operatorPath, result.errorCode, result.error)) {
            return result;
        }
    } else {
        plan = BuildMotionPlan(before, target, normalizedMode, moveDurationMs);
    }
    CopyMotionToClick(plan, result);
    bool moved = normalizedMode == L"operator-human"
        ? MoveCursorWithOperatorPath(operatorPath, plan.durationMs)
        : MoveCursorWithPlan(before, target, plan);
    if (!moved) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"CURSOR_MOVE_FAILED";
            result.error = L"Could not move system cursor.";
        }
        return result;
    }

    for (int i = 0; i < clickCount; ++i) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        INPUT down = {};
        down.type = INPUT_MOUSE;
        down.mi.dwFlags = downFlag;
        INPUT up = {};
        up.type = INPUT_MOUSE;
        up.mi.dwFlags = upFlag;
        ActionResult sent = clickCount == 0 ? ActionResult{true} : SendInputs({down, up});
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        if (clickCount > 1 && i + 1 < clickCount && !SleepInterruptible(60)) {
            SetUserAbort(result);
            return result;
        }
    }
    if (clickCount > 0) {
        result.actualClickSent = true;
        result.actualDoubleClickSent = clickCount > 1;
        result.sendInputUsed = true;
    }

    POINT after = {};
    if (!GetCursorPos(&after)) {
        result.errorCode = L"CURSOR_MOVE_FAILED";
        result.error = L"GetCursorPos failed after input.";
        return result;
    }
    result.cursorAfterX = after.x;
    result.cursorAfterY = after.y;
    result.foregroundAfter = GetForegroundWindow();
    result.ok = true;
    if (!SleepInterruptible(40)) {
        SetUserAbort(result);
        return result;
    }
    return result;
}

}  // namespace

KeyboardTextInputPlan BuildKeyboardTextInputPlan(const std::wstring& text) {
    KeyboardTextInputPlan plan;
    plan.typedCharCount = static_cast<int>(text.size());
    if (text.empty()) {
        plan.typedLineCount = 0;
        return plan;
    }
    plan.typedLineCount = 1;
    for (size_t i = 0; i < text.size(); ++i) {
        wchar_t ch = text[i];
        if (ch == L'\r') {
            if (i + 1 < text.size() && text[i + 1] == L'\n') {
                ++plan.crlfNewlineCount;
                ++i;
            } else {
                ++plan.crNewlineCount;
            }
            ++plan.enterKeyEventCount;
            ++plan.keyboardEventCount;
            ++plan.typedLineCount;
            plan.multiline = true;
            plan.endsWithLineBreak = (i + 1) >= text.size();
            continue;
        }
        if (ch == L'\n') {
            ++plan.lfNewlineCount;
            ++plan.enterKeyEventCount;
            ++plan.keyboardEventCount;
            ++plan.typedLineCount;
            plan.multiline = true;
            plan.endsWithLineBreak = (i + 1) >= text.size();
            continue;
        }
        if (ch == L'\t') {
            ++plan.tabKeyEventCount;
            ++plan.keyboardEventCount;
            plan.endsWithLineBreak = false;
            continue;
        }
        ++plan.unicodeCharEventCount;
        ++plan.keyboardEventCount;
        plan.endsWithLineBreak = false;
    }
    plan.newlineAsUnicode = false;
    plan.tabAsUnicode = false;
    return plan;
}

ClickResult ClickClientPoint(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return MouseClick(hwnd, x, y, moveMode, moveDurationMs, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, 1, L"left_click", profilePath, allowSyntheticProfile);
}

ClickResult DoubleClickClientPoint(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return MouseClick(hwnd, x, y, moveMode, moveDurationMs, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, 2, L"double_click", profilePath, allowSyntheticProfile);
}

ClickResult RightClickClientPoint(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return MouseClick(hwnd, x, y, moveMode, moveDurationMs, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP, 1, L"right_click", profilePath, allowSyntheticProfile);
}

ClickResult MoveScreenPoint(int screenX, int screenY, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return ScreenMouseAction(screenX, screenY, moveMode, moveDurationMs, 0, 0, 0, L"screen_move", profilePath, allowSyntheticProfile);
}

ClickResult ClickScreenPoint(int screenX, int screenY, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return ScreenMouseAction(screenX, screenY, moveMode, moveDurationMs, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, 1, L"screen_left_click", profilePath, allowSyntheticProfile);
}

ClickResult DoubleClickScreenPoint(int screenX, int screenY, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return ScreenMouseAction(screenX, screenY, moveMode, moveDurationMs, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, 2, L"screen_double_click", profilePath, allowSyntheticProfile);
}

ClickResult RightClickScreenPoint(int screenX, int screenY, const std::wstring& moveMode, int moveDurationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return ScreenMouseAction(screenX, screenY, moveMode, moveDurationMs, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP, 1, L"screen_right_click", profilePath, allowSyntheticProfile);
}

ClickResult MoveMouseHumanMode(int screenX, int screenY, const HumanMouseMotionOptions& options) {
    return MoveHumanModeCore(screenX, screenY, options, L"screen_move_humanmode");
}

ClickResult ClickHumanMode(int screenX, int screenY, const HumanMouseMotionOptions& options) {
    return ClickHumanModeCore(screenX, screenY, options, 1, L"screen_left_click_humanmode");
}

ClickResult DoubleClickHumanMode(int screenX, int screenY, const HumanMouseMotionOptions& options) {
    return ClickHumanModeCore(screenX, screenY, options, 2, L"screen_double_click_humanmode");
}

ClickResult RightClickHumanMode(int screenX, int screenY, const HumanMouseMotionOptions& options) {
    return ClickHumanModeCore(screenX, screenY, options, 1, L"screen_right_click_humanmode", MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP);
}

ClickResult WheelClientPoint(HWND hwnd, int x, int y, int delta, DWORD wheelFlag, const std::wstring& moveMode, const std::wstring& profilePath, bool allowSyntheticProfile) {
    ClickResult result = MouseClick(hwnd, x, y, moveMode, 0, 0, 0, 0, L"scroll", profilePath, allowSyntheticProfile);
    if (!result.ok) return result;
    INPUT wheel = {};
    wheel.type = INPUT_MOUSE;
    wheel.mi.dwFlags = wheelFlag;
    wheel.mi.mouseData = static_cast<DWORD>(delta);
    ActionResult sent = SendInputs({wheel});
    if (!sent.ok) {
        result.ok = false;
        result.errorCode = sent.errorCode;
        result.error = sent.error;
        return result;
    }
    result.wheelDelta = delta;
    result.wheelEventCount = 1;
    result.sendInputUsed = true;
    result.mouseeventfWheelUsed = wheelFlag == MOUSEEVENTF_WHEEL;
    result.mouseeventfHWheelUsed = wheelFlag == MOUSEEVENTF_HWHEEL;
    return result;
}

ClickResult ScrollClientPoint(HWND hwnd, int x, int y, int delta, const std::wstring& moveMode, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return WheelClientPoint(hwnd, x, y, delta, MOUSEEVENTF_WHEEL, moveMode, profilePath, allowSyntheticProfile);
}

ClickResult HorizontalScrollClientPoint(HWND hwnd, int x, int y, int delta, const std::wstring& moveMode, const std::wstring& profilePath, bool allowSyntheticProfile) {
    return WheelClientPoint(hwnd, x, y, delta, MOUSEEVENTF_HWHEEL, moveMode, profilePath, allowSyntheticProfile);
}

DragResult DragClientPoints(HWND hwnd, int fromX, int fromY, int toX, int toY, const std::wstring& moveMode, int durationMs, const std::wstring& profilePath, bool allowSyntheticProfile) {
    DragResult result;
    result.fromClientX = fromX;
    result.fromClientY = fromY;
    result.toClientX = toX;
    result.toClientY = toY;
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    std::wstring normalizedMode = NormalizeMoveMode(moveMode);
    if (!IsMoveModeValid(normalizedMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported move mode.";
        return result;
    }
    POINT from = {};
    POINT to = {};
    std::wstring pointError;
    if (!ClientPointToScreen(hwnd, fromX, fromY, from, pointError) || !ClientPointToScreen(hwnd, toX, toY, to, pointError)) {
        result.errorCode = pointError.find(L"outside") != std::wstring::npos || pointError.find(L"non-negative") != std::wstring::npos ? L"INVALID_ARGUMENT" : L"UNKNOWN_ERROR";
        result.error = pointError;
        return result;
    }
    result.fromScreenX = from.x;
    result.fromScreenY = from.y;
    result.toScreenX = to.x;
    result.toScreenY = to.y;
    if (!ActivateWindow(hwnd, result.foregroundBefore, result.foregroundAfter)) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"WINDOW_FOCUS_FAILED";
            result.error = L"Could not focus target window.";
        }
        return result;
    }
    result.focusVerified = true;
    POINT before = {};
    if (!GetCursorPos(&before)) {
        result.errorCode = L"CURSOR_MOVE_FAILED";
        result.error = L"GetCursorPos failed before drag.";
        return result;
    }
    result.cursorBeforeX = before.x;
    result.cursorBeforeY = before.y;
    MotionPlan toStart;
    std::vector<POINT> operatorToStart;
    if (normalizedMode == L"operator-human") {
        if (!BuildOperatorPlan(before, from, 0, profilePath, allowSyntheticProfile, toStart, operatorToStart, result.errorCode, result.error)) {
            return result;
        }
    } else {
        toStart = BuildMotionPlan(before, from, normalizedMode, 0);
    }
    bool movedToStart = normalizedMode == L"operator-human"
        ? MoveCursorWithOperatorPath(operatorToStart, toStart.durationMs)
        : MoveCursorWithPlan(before, from, toStart);
    if (!movedToStart) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"CURSOR_MOVE_FAILED";
            result.error = L"Could not move cursor to drag start.";
        }
        return result;
    }
    INPUT down = {};
    down.type = INPUT_MOUSE;
    down.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    ActionResult downSent = SendInputs({down});
    if (!downSent.ok) {
        result.errorCode = downSent.errorCode;
        result.error = downSent.error;
        return result;
    }
    result.mouseDownSent = true;
    MotionPlan dragPlan;
    std::vector<POINT> operatorDragPath;
    if (normalizedMode == L"operator-human") {
        if (!BuildOperatorPlan(from, to, durationMs, profilePath, allowSyntheticProfile, dragPlan, operatorDragPath, result.errorCode, result.error)) {
            return result;
        }
    } else {
        dragPlan = BuildMotionPlan(from, to, normalizedMode, durationMs);
    }
    CopyMotionToDrag(dragPlan, result);
    bool moved = normalizedMode == L"operator-human"
        ? MoveCursorWithOperatorPath(operatorDragPath, dragPlan.durationMs)
        : MoveCursorWithPlan(from, to, dragPlan);
    INPUT up = {};
    up.type = INPUT_MOUSE;
    up.mi.dwFlags = MOUSEEVENTF_LEFTUP;
    ActionResult upSent = SendInputs({up});
    result.mouseUpSent = upSent.ok;
    if (!moved) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"CURSOR_MOVE_FAILED";
            result.error = L"Could not complete drag cursor move.";
        }
        return result;
    }
    if (!upSent.ok) {
        result.errorCode = upSent.errorCode;
        result.error = upSent.error;
        return result;
    }
    POINT after = {};
    if (GetCursorPos(&after)) {
        result.cursorAfterX = after.x;
        result.cursorAfterY = after.y;
    }
    result.ok = true;
    if (!SleepInterruptible(40)) {
        SetUserAbort(result);
        return result;
    }
    return result;
}

ActionResult FocusTargetWindow(HWND hwnd) {
    ActionResult result;
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    if (!ActivateWindow(hwnd, result.foregroundBefore, result.foregroundAfter)) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
        } else {
            result.errorCode = L"WINDOW_FOCUS_FAILED";
            result.error = L"Could not focus target window.";
        }
        return result;
    }
    result.focusVerified = true;
    result.ok = true;
    return result;
}

ActionResult PressKey(HWND hwnd, const std::wstring& keyName) {
    ActionResult result = FocusTargetWindow(hwnd);
    if (!result.ok) return result;
    WORD vk = VirtualKeyForName(keyName);
    if (vk == 0) {
        result.ok = false;
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported key.";
        return result;
    }
    ActionResult sent = SendVirtualKey(vk);
    if (!sent.ok) {
        result.ok = false;
        result.errorCode = sent.errorCode;
        result.error = sent.error;
    }
    return result;
}

ActionResult PressKeyGlobal(const std::wstring& keyName) {
    ActionResult result;
    result.foregroundBefore = GetForegroundWindow();
    result.foregroundAfter = result.foregroundBefore;
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    WORD vk = VirtualKeyForName(keyName);
    if (vk == 0) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported key.";
        return result;
    }
    ActionResult sent = SendVirtualKey(vk);
    result.foregroundAfter = GetForegroundWindow();
    if (!sent.ok) {
        result.errorCode = sent.errorCode;
        result.error = sent.error;
        return result;
    }
    result.ok = true;
    if (!SleepInterruptible(120)) {
        SetUserAbort(result);
        return result;
    }
    return result;
}

ActionResult SendHotkey(HWND hwnd, const std::wstring& keys) {
    ActionResult result = FocusTargetWindow(hwnd);
    result.keys = keys;
    if (!result.ok) return result;
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    std::vector<WORD> vks;
    for (const auto& part : SplitCombo(keys)) {
        WORD vk = VirtualKeyForName(part);
        if (vk == 0) {
            result.ok = false;
            result.errorCode = L"INVALID_ARGUMENT";
            result.error = L"Unsupported hotkey component.";
            return result;
        }
        vks.push_back(vk);
    }
    std::vector<WORD> pressed;
    for (WORD vk : vks) {
        if (IsUserAbortRequested()) {
            for (auto it = pressed.rbegin(); it != pressed.rend(); ++it) {
                INPUT up = {};
                up.type = INPUT_KEYBOARD;
                up.ki.wVk = *it;
                up.ki.dwFlags = KEYEVENTF_KEYUP;
                SendInput(1, &up, sizeof(INPUT));
            }
            SetUserAbort(result);
            return result;
        }
        INPUT down = {};
        down.type = INPUT_KEYBOARD;
        down.ki.wVk = vk;
        ActionResult sent = SendInputs({down});
        if (!sent.ok) {
            for (auto it = pressed.rbegin(); it != pressed.rend(); ++it) {
                INPUT up = {};
                up.type = INPUT_KEYBOARD;
                up.ki.wVk = *it;
                up.ki.dwFlags = KEYEVENTF_KEYUP;
                SendInputs({up});
            }
            result.ok = false;
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        pressed.push_back(vk);
    }
    for (auto it = pressed.rbegin(); it != pressed.rend(); ++it) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        INPUT up = {};
        up.type = INPUT_KEYBOARD;
        up.ki.wVk = *it;
        up.ki.dwFlags = KEYEVENTF_KEYUP;
        ActionResult sent = SendInputs({up});
        if (!sent.ok) {
            result.ok = false;
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
    }
    result.ok = true;
    if (!SleepInterruptible(120)) {
        SetUserAbort(result);
        return result;
    }
    return result;
}

ActionResult SendHotkeyGlobal(const std::wstring& keys) {
    ActionResult result;
    result.keys = keys;
    result.foregroundBefore = GetForegroundWindow();
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    std::vector<WORD> vks;
    for (const auto& part : SplitCombo(keys)) {
        WORD vk = VirtualKeyForName(part);
        if (vk == 0) {
            result.errorCode = L"INVALID_ARGUMENT";
            result.error = L"Unsupported hotkey component.";
            return result;
        }
        vks.push_back(vk);
    }
    std::vector<WORD> pressed;
    for (WORD vk : vks) {
        if (IsUserAbortRequested()) {
            for (auto it = pressed.rbegin(); it != pressed.rend(); ++it) {
                INPUT up = {};
                up.type = INPUT_KEYBOARD;
                up.ki.wVk = *it;
                up.ki.dwFlags = KEYEVENTF_KEYUP;
                SendInput(1, &up, sizeof(INPUT));
            }
            SetUserAbort(result);
            return result;
        }
        INPUT down = {};
        down.type = INPUT_KEYBOARD;
        down.ki.wVk = vk;
        ActionResult sent = SendInputs({down});
        if (!sent.ok) {
            for (auto it = pressed.rbegin(); it != pressed.rend(); ++it) {
                INPUT up = {};
                up.type = INPUT_KEYBOARD;
                up.ki.wVk = *it;
                up.ki.dwFlags = KEYEVENTF_KEYUP;
                SendInputs({up});
            }
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        pressed.push_back(vk);
    }
    for (auto it = pressed.rbegin(); it != pressed.rend(); ++it) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        INPUT up = {};
        up.type = INPUT_KEYBOARD;
        up.ki.wVk = *it;
        up.ki.dwFlags = KEYEVENTF_KEYUP;
        ActionResult sent = SendInputs({up});
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
    }
    result.foregroundAfter = GetForegroundWindow();
    result.ok = true;
    if (!SleepInterruptible(120)) {
        SetUserAbort(result);
        return result;
    }
    return result;
}

ActionResult SetClipboardUnicodeText(const std::wstring& text) {
    ActionResult result;
    result.textLength = static_cast<int>(text.size());
    if (!OpenClipboard(nullptr)) {
        result.errorCode = L"UNKNOWN_ERROR";
        result.error = L"OpenClipboard failed.";
        return result;
    }
    EmptyClipboard();
    size_t bytes = (text.size() + 1) * sizeof(wchar_t);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!memory) {
        CloseClipboard();
        result.errorCode = L"UNKNOWN_ERROR";
        result.error = L"GlobalAlloc failed.";
        return result;
    }
    void* locked = GlobalLock(memory);
    if (!locked) {
        GlobalFree(memory);
        CloseClipboard();
        result.errorCode = L"UNKNOWN_ERROR";
        result.error = L"GlobalLock failed.";
        return result;
    }
    memcpy(locked, text.c_str(), bytes);
    GlobalUnlock(memory);
    if (!SetClipboardData(CF_UNICODETEXT, memory)) {
        GlobalFree(memory);
        CloseClipboard();
        result.errorCode = L"UNKNOWN_ERROR";
        result.error = L"SetClipboardData failed.";
        return result;
    }
    CloseClipboard();
    result.ok = true;
    return result;
}

TypeResult TypeTextGlobal(const std::wstring& text, const std::wstring& typeMode, int charDelayMs) {
    TypeResult result;
    result.typeMode = NormalizeTypeMode(typeMode);
    result.textLength = static_cast<int>(text.size());
    result.foregroundBefore = GetForegroundWindow();
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    if (!IsTypeModeValid(result.typeMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported type mode.";
        return result;
    }
    int delay = 0;
    if (result.typeMode == L"fast-human") delay = charDelayMs >= 0 ? charDelayMs : 20;
    if (result.typeMode == L"demo-human") delay = charDelayMs >= 0 ? charDelayMs : 80;
    result.charDelayMs = ClampInt(delay, 0, 500);
    result.keyboardSendBatchCount = 0;

    if (result.typeMode == L"instant") {
        std::vector<INPUT> inputs;
        inputs.reserve(text.size() * 2);
        for (size_t i = 0; i < text.size(); ++i) {
            AppendTextInputUnit(inputs, text, i);
        }
        ActionResult sent = SendInputs(inputs);
        result.foregroundAfter = GetForegroundWindow();
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        result.ok = true;
        result.keyboardSendBatchCount = 1;
        return result;
    }

    for (size_t i = 0; i < text.size(); ++i) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        ActionResult sent = SendTextInputUnit(text, i);
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        if (i + 1 < text.size() && result.charDelayMs > 0 &&
            !SleepInterruptible(static_cast<DWORD>(result.charDelayMs))) {
            SetUserAbort(result);
            return result;
        }
    }
    result.foregroundAfter = GetForegroundWindow();
    result.ok = true;
    return result;
}

TypeResult TypeTextStructuredGlobal(const std::wstring& text, const std::wstring& typeMode, int charDelayMs, int lineDelayMs, bool batchKeyEvents) {
    TypeResult result;
    result.typeMode = NormalizeTypeMode(typeMode);
    result.textLength = static_cast<int>(text.size());
    result.foregroundBefore = GetForegroundWindow();
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    if (!IsTypeModeValid(result.typeMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported type mode.";
        return result;
    }
    int delay = 0;
    if (result.typeMode == L"fast-human") delay = charDelayMs >= 0 ? charDelayMs : 20;
    if (result.typeMode == L"demo-human") delay = charDelayMs >= 0 ? charDelayMs : 80;
    if (result.typeMode == L"instant") delay = 0;
    result.charDelayMs = ClampInt(delay, 0, 500);
    result.lineDelayMs = ClampInt(lineDelayMs, 0, 500);
    result.batchKeyEvents = batchKeyEvents;
    if (!batchKeyEvents) {
        return TypeTextGlobal(text, typeMode, charDelayMs);
    }
    std::vector<std::vector<INPUT>> batches = BuildLineInputBatches(text);
    if (batches.empty()) {
        result.ok = true;
        result.foregroundAfter = GetForegroundWindow();
        return result;
    }
    if (!SendInputBatches(batches, result.lineDelayMs, result)) {
        result.foregroundAfter = GetForegroundWindow();
        return result;
    }
    result.foregroundAfter = GetForegroundWindow();
    result.ok = true;
    return result;
}

ActionResult PasteClipboardText(HWND hwnd, const std::wstring& text, bool setText) {
    ActionResult result;
    if (setText) {
        result = SetClipboardUnicodeText(text);
        if (!result.ok) return result;
    }
    ActionResult hotkey = SendHotkey(hwnd, L"CTRL+V");
    result.foregroundBefore = hotkey.foregroundBefore;
    result.foregroundAfter = hotkey.foregroundAfter;
    result.focusVerified = hotkey.focusVerified;
    result.pasted = hotkey.ok;
    result.keys = L"CTRL+V";
    result.textLength = setText ? static_cast<int>(text.size()) : 0;
    if (!hotkey.ok) {
        result.ok = false;
        result.errorCode = hotkey.errorCode;
        result.error = hotkey.error;
        return result;
    }
    result.ok = true;
    return result;
}

TypeResult TypeText(HWND hwnd, const std::wstring& text, const std::wstring& typeMode, int charDelayMs) {
    TypeResult result;
    result.typeMode = NormalizeTypeMode(typeMode);
    result.textLength = static_cast<int>(text.size());
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    if (!IsTypeModeValid(result.typeMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported type mode.";
        return result;
    }
    ActionResult focused = FocusTargetWindow(hwnd);
    result.foregroundBefore = focused.foregroundBefore;
    result.foregroundAfter = focused.foregroundAfter;
    result.focusVerified = focused.focusVerified;
    if (!focused.ok) {
        result.errorCode = focused.errorCode;
        result.error = focused.error;
        return result;
    }

    int delay = 0;
    if (result.typeMode == L"fast-human") delay = charDelayMs >= 0 ? charDelayMs : 20;
    if (result.typeMode == L"demo-human") delay = charDelayMs >= 0 ? charDelayMs : 80;
    result.charDelayMs = ClampInt(delay, 0, 500);
    result.keyboardSendBatchCount = 0;

    if (result.typeMode == L"instant") {
        std::vector<INPUT> inputs;
        inputs.reserve(text.size() * 2);
        for (size_t i = 0; i < text.size(); ++i) {
            AppendTextInputUnit(inputs, text, i);
        }
        ActionResult sent = SendInputs(inputs);
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        result.ok = true;
        result.keyboardSendBatchCount = 1;
        return result;
    }

    for (size_t i = 0; i < text.size(); ++i) {
        if (IsUserAbortRequested()) {
            SetUserAbort(result);
            return result;
        }
        ActionResult sent = SendTextInputUnit(text, i);
        if (!sent.ok) {
            result.errorCode = sent.errorCode;
            result.error = sent.error;
            return result;
        }
        if (i + 1 < text.size() && result.charDelayMs > 0 &&
            !SleepInterruptible(static_cast<DWORD>(result.charDelayMs))) {
            SetUserAbort(result);
            return result;
        }
    }
    result.ok = true;
    return result;
}

TypeResult TypeTextStructured(HWND hwnd, const std::wstring& text, const std::wstring& typeMode, int charDelayMs, int lineDelayMs, bool batchKeyEvents) {
    TypeResult result;
    result.typeMode = NormalizeTypeMode(typeMode);
    result.textLength = static_cast<int>(text.size());
    if (IsUserAbortRequested()) {
        SetUserAbort(result);
        return result;
    }
    if (!IsTypeModeValid(result.typeMode)) {
        result.errorCode = L"INVALID_ARGUMENT";
        result.error = L"Unsupported type mode.";
        return result;
    }
    ActionResult focused = FocusTargetWindow(hwnd);
    result.foregroundBefore = focused.foregroundBefore;
    result.foregroundAfter = focused.foregroundAfter;
    result.focusVerified = focused.focusVerified;
    if (!focused.ok) {
        result.errorCode = focused.errorCode;
        result.error = focused.error;
        return result;
    }
    int delay = 0;
    if (result.typeMode == L"fast-human") delay = charDelayMs >= 0 ? charDelayMs : 20;
    if (result.typeMode == L"demo-human") delay = charDelayMs >= 0 ? charDelayMs : 80;
    if (result.typeMode == L"instant") delay = 0;
    result.charDelayMs = ClampInt(delay, 0, 500);
    result.lineDelayMs = ClampInt(lineDelayMs, 0, 500);
    result.batchKeyEvents = batchKeyEvents;
    if (!batchKeyEvents) {
        return TypeText(hwnd, text, typeMode, charDelayMs);
    }
    std::vector<std::vector<INPUT>> batches = BuildLineInputBatches(text);
    if (batches.empty()) {
        result.ok = true;
        return result;
    }
    if (!SendInputBatches(batches, result.lineDelayMs, result)) {
        return result;
    }
    result.ok = true;
    return result;
}
