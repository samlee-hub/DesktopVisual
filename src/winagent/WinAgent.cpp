#include "WinAgent.h"

#include "AdaptiveHumanMode.h"
#include "AgentBoundary.h"
#include "AgentPlanner.h"
#include "AppProfile.h"
#include "BrowserSurfaceNormalizer.h"
#include "BrowserWorkflowAdapter.h"
#include "BrowserWorkflowExecutor.h"
#include "BrowserWorkflowVerifier.h"
#include "CaseRunner.h"
#include "CodingWorkflow.h"
#include "CommunicationWorkflowAdapter.h"
#include "CommunicationWorkflowExecutor.h"
#include "CommunicationWorkflowVerifier.h"
#include "CompiledPlanExecutor.h"
#include "DecisionEngine.h"
#include "DeterministicActionBatch.h"
#include "ExecutionOutcomeClassifier.h"
#include "EvidenceFingerprint.h"
#include "ExperienceMemoryStore.h"
#include "FailureAttributionIntegrator.h"
#include "ExplorerWorkflowAdapter.h"
#include "ExplorerWorkflowExecutor.h"
#include "ExplorerWorkflowVerifier.h"
#include "FailureAttribution.h"
#include "FailureAttributionNormalizer.h"
#include "FileWorkflow.h"
#include "FormSemantics.h"
#include "FrameRegistry.h"
#include "ForegroundPreempt.h"
#include "ForegroundPreparation.h"
#include "GlobalDpiAwareFrame.h"
#include "ImageMatcher.h"
#include "InputController.h"
#include "LatencyProfile.h"
#include "MotionProfile.h"
#include "MotionPacer.h"
#include "MotionRecorder.h"
#include "MemorySafetyBoundary.h"
#include "MockVLMProvider.h"
#include "ObserveController.h"
#include "OcrController.h"
#include "OperationTimelineProfiler.h"
#include "Perception.h"
#include "PermissionManager.h"
#include "PlanCompiler.h"
#include "ProjectRoot.h"
#include "PyCharmVisibleWorkflow.h"
#include "RegressionSkipPolicy.h"
#include "RealVlmRuntimeBridge.h"
#include "RuntimeEvidenceConsolidator.h"
#include "RuntimeContextGuard.h"
#include "SafeContextRecovery.h"
#include "SafetyManifest.h"
#include "SafetyPolicy.h"
#include "SessionLifecycleManager.h"
#include "Selector.h"
#include "SessionCommandDispatcher.h"
#include "Screenshot.h"
#include "ScreenshotCoordinateMapper.h"
#include "StepContract.h"
#include "StepContractRuntimeAdapter.h"
#include "StepContractValidator.h"
#include "StepExecutionVerifier.h"
#include "StepCompletionGate.h"
#include "TaskConfirmation.h"
#include "TaskCheckpoint.h"
#include "TaskRecovery.h"
#include "TaskSession.h"
#include "TaskTemplateV2.h"
#include "TaskRunner.h"
#include "TargetWindowLock.h"
#include "TargetSemanticsGuard.h"
#include "Trace.h"
#include "UserAbortController.h"
#include "UiaController.h"
#include "VLMCandidateBridge.h"
#include "VLMRuntimeBridge.h"
#include "VLMObservationBoundary.h"
#include "VLMObservationContract.h"
#include "VLMObservationValidator.h"
#include "ValidationConsistencyChecker.h"
#include "WindowFinder.h"
#include "WindowSession.h"
#include "VisibleOperationPolicy.h"
#include "VisibleTextInputPolicy.h"
#include "VisibleUIVerificationPolicy.h"
#include "WorkflowSystemBoundary.h"
#include "WorkflowTemplateCandidateExtractor.h"
#include "WorkflowTemplateRegistry.h"
#include "WorkflowTemplateValidator.h"
#include "WorkflowTemplateInstantiator.h"
#include "WorkflowTemplateSafetyBoundary.h"
#include "BatchWorkflowPlanner.h"
#include "BatchWorkflowValidator.h"
#include "BatchWorkflowCoordinator.h"
#include "DeveloperRCGate.h"
#include "VersionIntegrityChecker.h"
#include "EvidenceChainVerifier.h"
#include "CapabilityMatrixBuilder.h"
#include "WorkflowBoundaryAuditor.h"
#include "DeveloperFullAccessPolicyVerifier.h"
#include "ReleaseHardeningDeferredLedger.h"
#include "HandoffPackageBuilder.h"

#include <shellapi.h>
#include <shldisp.h>

#include <iostream>
#include <iomanip>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cwctype>
#include <regex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#pragma comment(lib, "Shell32.lib")

namespace {

const wchar_t* kRuntimeVersion = L"1.1.0";

struct TargetRectSpec {
    bool provided = false;
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
};

bool IsPointInsideRect(int x, int y, const TargetRectSpec& rect) {
    if (!rect.provided) return false;
    return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
}

int DistanceToPoint(int x, int y, int targetX, int targetY) {
    int dx = x - targetX;
    int dy = y - targetY;
    return static_cast<int>(std::lround(std::sqrt(static_cast<double>(dx * dx + dy * dy))));
}

std::wstring JsonEscape(const std::wstring& value) {
    std::wstring escaped;
    for (wchar_t ch : value) {
        switch (ch) {
            case L'\\':
                escaped += L"\\\\";
                break;
            case L'"':
                escaped += L"\\\"";
                break;
            case L'\n':
                escaped += L"\\n";
                break;
            case L'\r':
                escaped += L"\\r";
                break;
            case L'\t':
                escaped += L"\\t";
                break;
            default:
                if (ch < 0x20 || ch > 0x7e) {
                    std::wstringstream stream;
                    stream << L"\\u" << std::hex << std::setw(4) << std::setfill(L'0') << static_cast<int>(ch);
                    escaped += stream.str();
                } else {
                    escaped += ch;
                }
                break;
        }
    }
    return escaped;
}

void PrintWindowJson(const WindowInfo& window, int indentSpaces = 0) {
    std::wstring indent(static_cast<size_t>(indentSpaces), L' ');
    std::wcout << indent << L"{"
               << L"\"hwnd\":\"" << JsonEscape(FormatHwnd(window.hwnd)) << L"\","
               << L"\"pid\":" << window.pid << L","
               << L"\"title\":\"" << JsonEscape(window.title) << L"\","
               << L"\"rect\":{"
               << L"\"left\":" << window.rect.left << L","
               << L"\"top\":" << window.rect.top << L","
               << L"\"right\":" << window.rect.right << L","
               << L"\"bottom\":" << window.rect.bottom
               << L"}}";
}

void PrintErrorJson(const std::wstring& error) {
    std::wcout << L"{\"ok\":false,\"error\":\"" << JsonEscape(error) << L"\"}\n";
}

void PrintOkJson(const std::wstring& extraFields) {
    std::wcout << L"{\"ok\":true";
    if (!extraFields.empty()) {
        std::wcout << L"," << extraFields;
    }
    std::wcout << L"}\n";
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

std::vector<std::wstring> ArgValues(int argc, wchar_t** argv, const std::wstring& name) {
    std::vector<std::wstring> values;
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            values.push_back(argv[i + 1]);
            ++i;
        }
    }
    return values;
}

bool ArgExists(int argc, wchar_t** argv, const std::wstring& name) {
    for (int i = 2; i < argc; ++i) {
        if (argv[i] == name) return true;
    }
    return false;
}

bool IsConsoleHandle(DWORD handleId) {
    HANDLE handle = GetStdHandle(handleId);
    if (handle == INVALID_HANDLE_VALUE || handle == nullptr) {
        return false;
    }
    DWORD mode = 0;
    return GetConsoleMode(handle, &mode) != 0;
}

bool HasLocalInteractiveConsole() {
    return IsConsoleHandle(STD_INPUT_HANDLE) && IsConsoleHandle(STD_ERROR_HANDLE);
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) {
        return false;
    }
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) {
            return false;
        }
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

bool ParseOptionalIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) {
        return true;
    }
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) {
            error = name + L" must be an integer.";
            return false;
        }
        value = parsed;
        return true;
    } catch (...) {
        error = name + L" must be an integer.";
        return false;
    }
}

bool ParseOptionalBoolArg(int argc, wchar_t** argv, const std::wstring& name, bool& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) {
        return true;
    }
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    error = name + L" must be true or false.";
    return false;
}

VisibleOperationPolicyOptions ParseVisibleOperationPriorityArgs(
    int argc,
    wchar_t** argv,
    const std::wstring& operationType,
    const std::wstring& finalModeUsed,
    bool backendFallbackUsed,
    const std::wstring& backendFallbackKind,
    std::wstring& error) {
    VisibleOperationPolicyOptions options;
    options.operationType = operationType;
    options.finalModeUsed = finalModeUsed;
    options.backendFallbackUsed = backendFallbackUsed;
    options.backendFallbackKind = backendFallbackKind;
    ArgValue(argc, argv, L"--operation-id", options.operationId);
    ArgValue(argc, argv, L"--operation-type", options.operationType);
    ArgValue(argc, argv, L"--final-mode-used", options.finalModeUsed);
    ArgValue(argc, argv, L"--attempt-1-mode", options.attempt1Mode);
    ArgValue(argc, argv, L"--attempt-2-mode", options.attempt2Mode);
    ArgValue(argc, argv, L"--attempt-3-mode", options.attempt3Mode);
    ArgValue(argc, argv, L"--backend-fallback-reason", options.backendFallbackReason);
    ArgValue(argc, argv, L"--visible-attempt-result", options.attempt1Result);
    if (options.attempt1Result.empty()) ArgValue(argc, argv, L"--attempt-1-result", options.attempt1Result);
    ArgValue(argc, argv, L"--visible-failure-reason", options.attempt1FailureReason);
    if (options.attempt1FailureReason.empty()) ArgValue(argc, argv, L"--attempt-1-failure-reason", options.attempt1FailureReason);
    ArgValue(argc, argv, L"--keyboard-shortcut-result", options.attempt2Result);
    if (options.attempt2Result.empty()) ArgValue(argc, argv, L"--attempt-2-result", options.attempt2Result);
    ArgValue(argc, argv, L"--keyboard-shortcut-failure-reason", options.attempt2FailureReason);
    if (options.attempt2FailureReason.empty()) ArgValue(argc, argv, L"--attempt-2-failure-reason", options.attempt2FailureReason);
    ArgValue(argc, argv, L"--attempt-3-result", options.attempt3Result);
    ArgValue(argc, argv, L"--surface-impossible-reason", options.surfaceImpossibleReason);
    ArgValue(argc, argv, L"--vlm-capability-status", options.vlmCapabilityStatus);
    ArgValue(argc, argv, L"--vlm-session-id", options.vlmSessionId);
    ArgValue(argc, argv, L"--vlm-assist-trigger-reason", options.vlmAssistTriggerReason);
    ArgValue(argc, argv, L"--vlm-assist-stage", options.vlmAssistStage);
    ArgValue(argc, argv, L"--vlm-provider", options.vlmProvider);
    ArgValue(argc, argv, L"--vlm-raw-response-path", options.vlmRawResponsePath);
    ArgValue(argc, argv, L"--vlm-candidate-rejected-reason", options.vlmCandidateRejectedReason);
    ArgValue(argc, argv, L"--fallback-stage-before-vlm", options.fallbackStageBeforeVlm);
    ArgValue(argc, argv, L"--fallback-stage-after-vlm", options.fallbackStageAfterVlm);
    if (!ParseOptionalBoolArg(argc, argv, L"--visible-mouse-keyboard-attempted", options.visibleMouseKeyboardAttempted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--keyboard-shortcut-attempted", options.keyboardShortcutAttempted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--backend-fallback-used", options.backendFallbackUsed, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--explicit-backend-request", options.explicitBackendRequested, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--max-attempts-exceeded", options.maxAttemptsExceeded, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-assist-enabled", options.vlmAssistEnabled, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-assist-attempted", options.vlmAssistAttempted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-candidate-accepted", options.vlmCandidateAccepted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-action-executed", options.vlmActionExecuted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-after-backend-attempted", options.vlmAfterBackendAttempted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--pre-action-checkpoint-present", options.preActionCheckpointPresent, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--bounded-recovery-attempted", options.boundedRecoveryAttempted, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--post-recovery-observed", options.postRecoveryObserved, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--same-surface-after-recovery", options.sameSurfaceAfterRecovery, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--surface-impossible", options.surfaceImpossible, error) ||
        !ParseOptionalBoolArg(argc, argv, L"--surface-impossible-evidence-present", options.surfaceImpossibleEvidencePresent, error) ||
        !ParseOptionalIntArg(argc, argv, L"--visible-attempt-count", options.visibleAttemptCount, error) ||
        !ParseOptionalIntArg(argc, argv, L"--min-visible-attempts-before-shortcut", options.minVisibleAttemptsBeforeShortcut, error)) {
        return options;
    }
    return options;
}

std::wstring WindowRectJson(const WindowInfo& window) {
    std::wstringstream json;
    json << L"{\"left\":" << window.rect.left
         << L",\"top\":" << window.rect.top
         << L",\"right\":" << window.rect.right
         << L",\"bottom\":" << window.rect.bottom
         << L"}";
    return json.str();
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
    return hwnd ? JsonString(FormatHwnd(hwnd)) : L"null";
}

std::wstring JsonDouble(double value, int precision = 2) {
    if (!std::isfinite(value)) return L"0";
    std::wstringstream json;
    json << std::fixed << std::setprecision(precision) << value;
    return json.str();
}

std::wstring DoubleArrayJson(const std::vector<double>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << JsonDouble(values[i], 3);
    }
    json << L"]";
    return json.str();
}

std::wstring ActionFocusFields(
    const WindowInfo& window,
    const std::wstring& requestedTitle,
    HWND foregroundBefore,
    HWND foregroundAfter,
    bool focusVerified) {
    std::wstringstream fields;
    fields << L"\"requested_title\":" << JsonString(requestedTitle)
           << L",\"actual_title\":" << JsonString(window.title)
           << L",\"hwnd\":" << JsonString(FormatHwnd(window.hwnd))
           << L",\"pid\":" << window.pid
           << L",\"process_name\":" << JsonString(ProcessNameForPid(window.pid))
           << L",\"foreground_before\":" << HwndJson(foregroundBefore)
           << L",\"foreground_after\":" << HwndJson(foregroundAfter)
           << L",\"focus_verified\":" << (focusVerified ? L"true" : L"false");
    return fields.str();
}

std::wstring ClickMotionFields(const ClickResult& result) {
    std::wstringstream fields;
    fields << L"\"move_mode\":" << JsonString(result.moveMode)
           << L",\"move_duration_ms\":" << result.moveDurationMs
           << L",\"move_steps\":" << result.moveSteps
           << L",\"move_profile\":" << JsonString(result.moveProfile)
           << L",\"path_type\":" << JsonString(result.pathType)
           << L",\"distance_px\":" << result.distancePx
           << L",\"duration_ms\":" << result.durationMs
           << L",\"step_count\":" << result.stepCount
           << L",\"target_motion_frame_rate_hz\":" << result.targetMotionFrameRateHz
           << L",\"target_frame_interval_ms\":" << JsonDouble(result.targetFrameIntervalMs)
           << L",\"best_effort\":" << (result.motionFrameRateBestEffort ? L"true" : L"false")
           << L",\"frame_timestamps_recorded\":" << (result.frameTimestampsRecorded ? L"true" : L"false")
           << L",\"frame_timestamps_ms\":" << DoubleArrayJson(result.motionFrameTimestampsMs)
           << L",\"average_frame_interval_ms\":" << JsonDouble(result.averageFrameIntervalMs)
           << L",\"p95_frame_interval_ms\":" << JsonDouble(result.p95FrameIntervalMs)
           << L",\"actual_frame_rate_hz\":" << JsonDouble(result.actualFrameRateHz)
           << L",\"target_miss\":" << (result.targetMiss ? L"true" : L"false")
           << L",\"cursor_overshoot\":" << (result.cursorOvershoot ? L"true" : L"false")
           << L",\"emergency_stop_checked\":" << (result.emergencyStopChecked ? L"true" : L"false");
    if (!result.operatorProfilePath.empty()) {
        fields << L",\"operator_profile_path\":" << JsonString(result.operatorProfilePath)
               << L",\"operator_profile_quality\":" << JsonString(result.operatorProfileQuality)
               << L",\"operator_profile_source\":" << JsonString(result.operatorProfileSource)
               << L",\"synthesized_point_count\":" << result.synthesizedPointCount;
    }
    if (result.humanmode) {
        fields << L",\"humanmode_paced\":true"
               << L",\"target_epsilon_px\":" << result.targetEpsilonPx
               << L",\"actual_steps\":" << result.actualSteps
               << L",\"dwell_before_click_ms\":" << result.dwellBeforeClickMs
               << L",\"post_click_settle_ms\":" << result.postClickSettleMs
               << L",\"double_click_interval_ms\":" << result.doubleClickIntervalMs
               << L",\"within_target_epsilon_before_click\":" << (result.withinTargetEpsilonBeforeClick ? L"true" : L"false");
    }
    return fields.str();
}

std::wstring PointArrayJson(const std::vector<POINT>& points) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < points.size(); ++i) {
        if (i) json << L",";
        json << L"{\"x\":" << points[i].x << L",\"y\":" << points[i].y << L"}";
    }
    json << L"]";
    return json.str();
}

std::wstring HumanActionTypeForCommand(const std::wstring& command) {
    if (command == L"desktop-move") return L"mouse_move";
    if (command == L"desktop-double-click") return L"mouse_double_click";
    if (command == L"desktop-click") return L"mouse_click";
    if (command == L"desktop-type") return L"key_type";
    if (command == L"desktop-hotkey") return L"hotkey";
    if (command == L"desktop-press") return L"key_press";
    if (command == L"drag") return L"mouse_drag";
    if (command == L"click") return L"mouse_click";
    if (command == L"double-click") return L"mouse_double_click";
    return command;
}

std::wstring KeyboardHumanActionResultJson(
    const std::wstring& command,
    const std::wstring& actionId,
    const std::wstring& key,
    const std::wstring& keys,
    int textLength,
    HWND foregroundBefore,
    HWND foregroundAfter,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    int exitCode) {
    bool ok = exitCode == 0 && errorCode.empty();
    std::wstringstream json;
    json << L"{\"ok\":" << (ok ? L"true" : L"false")
         << L",\"schema_version\":\"human_action_result.v1\""
         << L",\"runtime_version\":" << JsonString(kRuntimeVersion)
         << L",\"action_id\":" << JsonString(actionId)
         << L",\"action_type\":" << JsonString(HumanActionTypeForCommand(command))
         << L",\"humanmode\":true"
         << L",\"backend_action\":false"
         << L",\"direct_launch\":false"
         << L",\"fallback_used\":false"
         << L",\"actual_click_sent\":false"
         << L",\"actual_double_click_sent\":false"
         << L",\"actual_key_sent\":" << (ok ? L"true" : L"false")
         << L",\"exit_code\":" << exitCode
         << L",\"target\":{\"description\":\"desktop global keyboard\",\"coordinate_source\":\"keyboard_focus\"}"
         << L",\"keyboard\":{\"key\":" << JsonString(key)
         << L",\"keys\":" << JsonString(keys)
         << L",\"text_length\":" << textLength
         << L"}"
         << L",\"foreground\":{\"before\":" << HwndJson(foregroundBefore)
         << L",\"after\":" << HwndJson(foregroundAfter)
         << L"}"
         << L",\"verification\":{\"foreground_after_present\":" << (foregroundAfter ? L"true" : L"false")
         << L"}"
         << L",\"error\":{\"code\":" << JsonString(errorCode)
         << L",\"message\":" << JsonString(errorMessage)
         << L"}}";
    return json.str();
}

std::wstring DragHumanActionResultJson(
    const std::wstring& command,
    const DragResult& result,
    const std::wstring& actionId,
    int exitCode) {
    std::wstring errorCode = result.errorCode.empty() ? L"" : result.errorCode;
    std::wstring errorMessage = result.error.empty() ? L"" : result.error;
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"schema_version\":\"human_action_result.v1\""
         << L",\"runtime_version\":" << JsonString(kRuntimeVersion)
         << L",\"action_id\":" << JsonString(actionId)
         << L",\"action_type\":" << JsonString(HumanActionTypeForCommand(command))
         << L",\"humanmode\":true"
         << L",\"backend_action\":false"
         << L",\"direct_launch\":false"
         << L",\"fallback_used\":false"
         << L",\"actual_click_sent\":false"
         << L",\"actual_double_click_sent\":false"
         << L",\"actual_drag_sent\":" << (result.mouseDownSent && result.mouseUpSent ? L"true" : L"false")
         << L",\"exit_code\":" << exitCode
         << L",\"target\":{\"from_screen_x\":" << result.fromScreenX
         << L",\"from_screen_y\":" << result.fromScreenY
         << L",\"to_screen_x\":" << result.toScreenX
         << L",\"to_screen_y\":" << result.toScreenY
         << L",\"coordinate_source\":\"window_titlebar_drag\"}"
         << L",\"cursor\":{\"start_x\":" << result.cursorBeforeX
         << L",\"start_y\":" << result.cursorBeforeY
         << L",\"final_x\":" << result.cursorAfterX
         << L",\"final_y\":" << result.cursorAfterY
         << L"}"
         << L",\"motion\":{\"move_duration_ms\":" << result.durationMs
         << L",\"planned_steps\":" << result.stepCount
         << L",\"easing\":" << JsonString(result.pathType)
         << L"}"
         << L",\"verification\":{\"mouse_down_sent\":" << (result.mouseDownSent ? L"true" : L"false")
         << L",\"mouse_up_sent\":" << (result.mouseUpSent ? L"true" : L"false")
         << L"}"
         << L",\"error\":{\"code\":" << JsonString(errorCode)
         << L",\"message\":" << JsonString(errorMessage)
         << L"}}";
    return json.str();
}

std::wstring HumanActionResultJson(
    const std::wstring& command,
    const ClickResult& result,
    const std::wstring& actionId,
    const std::wstring& targetDescription,
    const std::wstring& coordinateSource,
    const TargetRectSpec& targetRect,
    int exitCode) {
    std::wstring errorCode = result.errorCode.empty() ? L"" : result.errorCode;
    std::wstring errorMessage = result.error.empty() ? L"" : result.error;
    int targetCenterX = targetRect.provided ? (targetRect.left + targetRect.right) / 2 : result.targetScreenX;
    int targetCenterY = targetRect.provided ? (targetRect.top + targetRect.bottom) / 2 : result.targetScreenY;
    bool cursorInsideTargetRect = IsPointInsideRect(result.actualBeforeClickX, result.actualBeforeClickY, targetRect);
    int distanceToTargetCenter = DistanceToPoint(result.actualBeforeClickX, result.actualBeforeClickY, targetCenterX, targetCenterY);
    std::wstringstream json;
    json << L"{\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"schema_version\":\"human_action_result.v1\""
         << L",\"runtime_version\":" << JsonString(kRuntimeVersion)
         << L",\"action_id\":" << JsonString(actionId)
         << L",\"action_type\":" << JsonString(HumanActionTypeForCommand(command))
         << L",\"humanmode\":" << (result.humanmode ? L"true" : L"false")
         << L",\"backend_action\":" << (result.backendAction ? L"true" : L"false")
         << L",\"direct_launch\":" << (result.directLaunch ? L"true" : L"false")
         << L",\"fallback_used\":" << (result.fallbackUsed ? L"true" : L"false")
         << L",\"actual_click_sent\":" << (result.actualClickSent ? L"true" : L"false")
         << L",\"actual_double_click_sent\":" << (result.actualDoubleClickSent ? L"true" : L"false")
         << L",\"exit_code\":" << exitCode
         << L",\"target\":{\"x\":" << result.targetScreenX
         << L",\"y\":" << result.targetScreenY
         << L",\"description\":" << JsonString(targetDescription.empty() ? L"desktop screen coordinate" : targetDescription)
         << L",\"coordinate_source\":" << JsonString(coordinateSource.empty() ? L"manual_fixed" : coordinateSource)
         << L",\"target_rect\":[" << targetRect.left << L"," << targetRect.top << L"," << targetRect.right << L"," << targetRect.bottom << L"]"
         << L",\"target_center_x\":" << targetCenterX
         << L",\"target_center_y\":" << targetCenterY
         << L",\"target_epsilon_px\":" << result.targetEpsilonPx
         << L"}"
         << L",\"cursor\":{\"start_x\":" << result.cursorBeforeX
         << L",\"start_y\":" << result.cursorBeforeY
         << L",\"final_x\":" << result.finalX
         << L",\"final_y\":" << result.finalY
         << L",\"actual_before_click_x\":" << result.actualBeforeClickX
         << L",\"actual_before_click_y\":" << result.actualBeforeClickY
         << L",\"inside_target_rect_before_click\":" << (cursorInsideTargetRect ? L"true" : L"false")
         << L",\"within_target_epsilon_before_click\":" << (result.withinTargetEpsilonBeforeClick ? L"true" : L"false")
         << L",\"distance_to_target_before_click_px\":" << result.distanceToTargetBeforeClickPx
         << L",\"distance_to_target_center_px\":" << distanceToTargetCenter
         << L"}"
          << L",\"motion\":{\"move_duration_ms\":" << result.moveDurationMs
          << L",\"planned_steps\":" << result.moveSteps
          << L",\"actual_steps\":" << result.actualSteps
          << L",\"easing\":" << JsonString(result.easing.empty() ? L"smoothstep" : result.easing)
          << L",\"dwell_before_click_ms\":" << result.dwellBeforeClickMs
          << L",\"post_click_settle_ms\":" << result.postClickSettleMs
          << L",\"double_click_interval_ms\":" << result.doubleClickIntervalMs
          << L",\"target_motion_frame_rate_hz\":" << result.targetMotionFrameRateHz
          << L",\"target_frame_interval_ms\":" << JsonDouble(result.targetFrameIntervalMs)
          << L",\"best_effort\":" << (result.motionFrameRateBestEffort ? L"true" : L"false")
          << L",\"frame_timestamps_recorded\":" << (result.frameTimestampsRecorded ? L"true" : L"false")
          << L",\"frame_timestamps_ms\":" << DoubleArrayJson(result.motionFrameTimestampsMs)
          << L",\"average_frame_interval_ms\":" << JsonDouble(result.averageFrameIntervalMs)
          << L",\"p95_frame_interval_ms\":" << JsonDouble(result.p95FrameIntervalMs)
          << L",\"actual_frame_rate_hz\":" << JsonDouble(result.actualFrameRateHz)
          << L",\"target_miss\":" << (result.targetMiss ? L"true" : L"false")
          << L",\"cursor_overshoot\":" << (result.cursorOvershoot ? L"true" : L"false")
          << L",\"planned_path\":" << PointArrayJson(result.plannedPath)
          << L"}"
         << L",\"timing\":{\"move_start_ts\":" << JsonString(result.moveStartTs)
         << L",\"move_end_ts\":" << JsonString(result.moveEndTs)
         << L",\"dwell_start_ts\":" << JsonString(result.dwellStartTs)
         << L",\"click_down_ts\":" << JsonString(result.clickDownTs)
         << L",\"click_up_ts\":" << JsonString(result.clickUpTs)
         << L",\"second_click_down_ts\":" << JsonString(result.secondClickDownTs)
         << L",\"second_click_up_ts\":" << JsonString(result.secondClickUpTs)
         << L"}"
         << L",\"verification\":{\"target_rect_verified\":" << (targetRect.provided ? L"true" : L"false")
         << L",\"cursor_verified_before_click\":" << (result.cursorVerifiedBeforeClick ? L"true" : L"false")
         << L",\"click_after_move_end\":" << (result.clickAfterMoveEnd ? L"true" : L"false")
         << L",\"dwell_completed_before_click\":" << (result.dwellCompletedBeforeClick ? L"true" : L"false")
         << L",\"cursor_inside_target_rect_before_click\":" << (cursorInsideTargetRect ? L"true" : L"false")
         << L"}"
         << L",\"error\":{\"code\":" << JsonString(errorCode)
         << L",\"message\":" << JsonString(errorMessage)
         << L"}}";
    return json.str();
}

std::wstring DragMotionFields(const DragResult& result) {
    std::wstringstream fields;
    fields << L"\"move_mode\":" << JsonString(result.moveMode)
           << L",\"move_profile\":" << JsonString(result.moveProfile)
           << L",\"path_type\":" << JsonString(result.pathType)
           << L",\"distance_px\":" << result.distancePx
           << L",\"duration_ms\":" << result.durationMs
           << L",\"step_count\":" << result.stepCount
           << L",\"emergency_stop_checked\":" << (result.emergencyStopChecked ? L"true" : L"false");
    if (!result.operatorProfilePath.empty()) {
        fields << L",\"operator_profile_path\":" << JsonString(result.operatorProfilePath)
               << L",\"operator_profile_quality\":" << JsonString(result.operatorProfileQuality)
               << L",\"operator_profile_source\":" << JsonString(result.operatorProfileSource)
               << L",\"synthesized_point_count\":" << result.synthesizedPointCount;
    }
    return fields.str();
}

bool IsMotionProfileFailure(const std::wstring& code) {
    return code == L"MOTION_PROFILE_NOT_FOUND" || code == L"MOTION_PROFILE_INVALID" ||
           code == L"MOTION_PROFILE_NOT_HUMAN" || code == L"MOTION_PROFILE_TEST_ONLY" ||
           code == L"MOTION_PROFILE_SOURCE_REQUIRED";
}

bool ValidateMoveFallback(const std::wstring& fallback, std::wstring& error) {
    if (fallback.empty() || fallback == L"fast-human") {
        return true;
    }
    error = L"Unsupported --fallback. Only fast-human is allowed.";
    return false;
}

bool IsOperatorRequestedMove(const std::wstring& moveMode) {
    return moveMode.empty() || moveMode == L"human" || moveMode == L"operator-human";
}

ClickResult ApplyClickFallback(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, const std::wstring& fallback, const ClickResult& first) {
    if (!first.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(first.errorCode)) {
        return ClickClientPoint(hwnd, x, y, L"fast-human", moveDurationMs);
    }
    return first;
}

ClickResult ApplyDoubleClickFallback(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, const std::wstring& fallback, const ClickResult& first) {
    if (!first.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(first.errorCode)) {
        return DoubleClickClientPoint(hwnd, x, y, L"fast-human", moveDurationMs);
    }
    return first;
}

ClickResult ApplyRightClickFallback(HWND hwnd, int x, int y, const std::wstring& moveMode, int moveDurationMs, const std::wstring& fallback, const ClickResult& first) {
    if (!first.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(first.errorCode)) {
        return RightClickClientPoint(hwnd, x, y, L"fast-human", moveDurationMs);
    }
    return first;
}

ClickResult ApplyScrollFallback(HWND hwnd, int x, int y, int delta, const std::wstring& moveMode, const std::wstring& fallback, const ClickResult& first) {
    if (!first.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(first.errorCode)) {
        return ScrollClientPoint(hwnd, x, y, delta, L"fast-human");
    }
    return first;
}

DragResult ApplyDragFallback(HWND hwnd, int fromX, int fromY, int toX, int toY, int durationMs, const std::wstring& moveMode, const std::wstring& fallback, const DragResult& first) {
    if (!first.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(first.errorCode)) {
        return DragClientPoints(hwnd, fromX, fromY, toX, toY, L"fast-human", durationMs);
    }
    return first;
}

bool ActiveWindowInfo(WindowInfo& info) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) {
        return false;
    }
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        if (window.hwnd == hwnd) {
            info = window;
            return true;
        }
    }
    info.hwnd = hwnd;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    int length = GetWindowTextLengthW(hwnd);
    if (length > 0) {
        std::wstring title(static_cast<size_t>(length) + 1, L'\0');
        int copied = GetWindowTextW(hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
        info.title = title;
    }
    return true;
}

std::wstring UiaElementJson(const UiaElementInfo& element) {
    std::wstringstream json;
    json << L"{\"name\":" << JsonString(element.name)
         << L",\"value\":" << JsonString(element.value)
         << L",\"control_type\":" << JsonString(element.controlType)
         << L",\"rect\":" << RectJson(element.rect)
         << L",\"enabled\":" << (element.enabled ? L"true" : L"false")
         << L",\"offscreen\":" << (element.offscreen ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring UiaElementsJson(const std::vector<UiaElementInfo>& elements) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < elements.size(); ++i) {
        if (i != 0) {
            json << L",";
        }
        json << UiaElementJson(elements[i]);
    }
    json << L"]";
    return json.str();
}

bool ElementCenterClientPoint(HWND hwnd, const UiaElementInfo& element, int& clientX, int& clientY) {
    int screenX = element.rect.left + ((element.rect.right - element.rect.left) / 2);
    int screenY = element.rect.top + ((element.rect.bottom - element.rect.top) / 2);
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
    POINT screenPoint = {windowRect.left + bitmapX, windowRect.top + bitmapY};
    if (!ScreenToClient(hwnd, &screenPoint)) {
        return false;
    }
    clientX = screenPoint.x;
    clientY = screenPoint.y;
    return true;
}

bool ResolveUniqueWindowByTitle(
    const std::wstring& title,
    WindowInfo& selected,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    if (title.empty()) {
        errorCode = L"INVALID_ARGUMENT";
        errorMessage = L"--title is required.";
        dataJson = L"{\"requested_title\":\"\"}";
        return false;
    }

    WindowSessionResult session = ResolveWindowSession(title);
    if (!session.ok) {
        errorCode = session.errorCode;
        errorMessage = session.errorMessage;
        dataJson = session.dataJson;
        return false;
    }

    selected = session.session.window;
    return true;
}

bool EnforceSafetyPolicy(
    const WindowInfo& selected,
    const std::wstring& requestedTitle,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    SafetyCheckResult safety = CheckWindowSafety(selected, requestedTitle);
    if (safety.ok) {
        return true;
    }

    errorCode = safety.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : safety.errorCode;
    errorMessage = safety.message.empty() ? L"Safety policy denied this action." : safety.message;
    dataJson = L"{\"requested_title\":" + JsonString(requestedTitle)
        + L",\"actual_title\":" + JsonString(selected.title)
        + L",\"process_name\":" + JsonString(safety.processName)
        + L"}";
    return false;
}

std::wstring LaunchHistoryPath() {
    return ArtifactsPath(L"global_desktop_launch_history.txt");
}

std::wstring ReadSmallTextFile(const std::wstring& path) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"r, ccs=UTF-8") != 0 || !file) return L"";
    wchar_t buffer[1024] = {};
    std::wstring value;
    while (fgetws(buffer, static_cast<int>(sizeof(buffer) / sizeof(buffer[0])), file)) {
        value += buffer;
    }
    fclose(file);
    return value;
}

void WriteSmallTextFile(const std::wstring& path, const std::wstring& value) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) return;
    fwprintf(file, L"%ls", value.c_str());
    fclose(file);
}

struct FileContentSignature {
    bool ok = false;
    std::wstring value;
    long long byteCount = 0;
    std::wstring error;
};

struct ScrollRegionInfo {
    RECT clientRect = {};
    RECT scrollRegion = {};
    int safeClientX = 0;
    int safeClientY = 0;
};

bool PointInsideRect(const RECT& rect, int x, int y) {
    return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
}

std::wstring PointJson(int x, int y) {
    return L"{\"x\":" + std::to_wstring(x) + L",\"y\":" + std::to_wstring(y) + L"}";
}

std::wstring ScrollRegionJson(const ScrollRegionInfo& region) {
    std::wstringstream json;
    json << L"{\"client_rect\":" << RectJson(region.clientRect)
         << L",\"region\":" << RectJson(region.scrollRegion)
         << L",\"safe_point\":" << PointJson(region.safeClientX, region.safeClientY)
         << L"}";
    return json.str();
}

bool ComputeScrollRegion(HWND hwnd, bool hasClientPoint, int requestedX, int requestedY, ScrollRegionInfo& region, std::wstring& error) {
    if (!GetClientRect(hwnd, &region.clientRect)) {
        error = L"GetClientRect failed.";
        return false;
    }
    int width = region.clientRect.right - region.clientRect.left;
    int height = region.clientRect.bottom - region.clientRect.top;
    if (width <= 0 || height <= 0) {
        error = L"Target client rect is empty.";
        return false;
    }

    int leftMargin = width > 80 ? 24 : 4;
    int rightMargin = width > 120 ? 36 : 4;
    int verticalMargin = height > 80 ? 24 : 4;
    region.scrollRegion.left = region.clientRect.left + leftMargin;
    region.scrollRegion.top = region.clientRect.top + verticalMargin;
    region.scrollRegion.right = region.clientRect.right - rightMargin;
    region.scrollRegion.bottom = region.clientRect.bottom - verticalMargin;
    if (region.scrollRegion.right <= region.scrollRegion.left || region.scrollRegion.bottom <= region.scrollRegion.top) {
        region.scrollRegion = region.clientRect;
    }

    if (hasClientPoint) {
        region.safeClientX = requestedX;
        region.safeClientY = requestedY;
    } else {
        region.safeClientX = region.scrollRegion.left + ((region.scrollRegion.right - region.scrollRegion.left) / 2);
        region.safeClientY = region.scrollRegion.top + ((region.scrollRegion.bottom - region.scrollRegion.top) / 2);
    }
    return true;
}

std::wstring V613CommandScreenshotPath(const std::wstring& prefix, const std::wstring& screenshotDir) {
    std::wstring dir = screenshotDir.empty()
        ? ArtifactsPath(L"dev6.1.3_mouse_wheel_scroll_and_scroll_locate\\raw\\command_screenshots")
        : screenshotDir;
    EnsureDirectoryPath(dir);
    SYSTEMTIME time = {};
    GetLocalTime(&time);
    wchar_t buffer[256] = {};
    swprintf_s(
        buffer,
        L"%ls_%04u%02u%02u_%02u%02u%02u_%03u_%lu_%llu.bmp",
        prefix.c_str(),
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds,
        GetCurrentProcessId(),
        static_cast<unsigned long long>(GetTickCount64()));
    return dir + L"\\" + buffer;
}

FileContentSignature ComputeFileSignature(const std::wstring& path) {
    FileContentSignature result;
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) {
        result.error = L"Could not open file for content signature.";
        return result;
    }
    const std::uint64_t fnvPrime = 1099511628211ULL;
    std::uint64_t hash = 1469598103934665603ULL;
    unsigned char buffer[8192] = {};
    while (true) {
        size_t read = fread(buffer, 1, sizeof(buffer), file);
        if (read > 0) {
            result.byteCount += static_cast<long long>(read);
            for (size_t i = 0; i < read; ++i) {
                hash ^= static_cast<std::uint64_t>(buffer[i]);
                hash *= fnvPrime;
            }
        }
        if (read < sizeof(buffer)) {
            if (ferror(file)) {
                result.error = L"Could not read file for content signature.";
                fclose(file);
                return result;
            }
            break;
        }
    }
    fclose(file);
    std::wstringstream sig;
    sig << L"fnv1a64:" << std::hex << std::setw(16) << std::setfill(L'0') << hash
        << L":bytes:" << std::dec << result.byteCount;
    result.value = sig.str();
    result.ok = true;
    return result;
}

bool ParseHwndValue(const std::wstring& raw, HWND& hwnd) {
    if (raw.empty()) return false;
    int base = 10;
    const wchar_t* start = raw.c_str();
    if (raw.size() > 2 && raw[0] == L'0' && (raw[1] == L'x' || raw[1] == L'X')) {
        base = 16;
    }
    wchar_t* end = nullptr;
    unsigned long long value = wcstoull(start, &end, base);
    if (end == start || (end && *end != L'\0') || value == 0) {
        return false;
    }
    hwnd = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(value));
    return true;
}

bool WindowInfoFromHwnd(HWND hwnd, WindowInfo& info) {
    if (!hwnd || !IsWindow(hwnd) || !IsWindowVisible(hwnd)) {
        return false;
    }
    info.hwnd = hwnd;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    int length = GetWindowTextLengthW(hwnd);
    if (length > 0) {
        std::wstring title(static_cast<size_t>(length) + 1, L'\0');
        int copied = GetWindowTextW(hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
        info.title = title;
    }
    return true;
}

bool ResolveWindowByTitleOrHwnd(
    const std::wstring& title,
    const std::wstring& hwndArg,
    WindowInfo& selected,
    std::wstring& requestedTitleForSafety,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    if (!hwndArg.empty()) {
        HWND hwnd = nullptr;
        if (!ParseHwndValue(hwndArg, hwnd) || !WindowInfoFromHwnd(hwnd, selected)) {
            errorCode = L"WINDOW_NOT_FOUND";
            errorMessage = L"Requested --hwnd did not resolve to a visible top-level window.";
            dataJson = L"{\"requested_hwnd\":" + JsonString(hwndArg) + L"}";
            return false;
        }
        requestedTitleForSafety = title.empty() ? selected.title : title;
        return true;
    }
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return false;
    }
    requestedTitleForSafety = title;
    return true;
}

std::wstring FirstLine(const std::wstring& text) {
    size_t pos = text.find_first_of(L"\r\n");
    return pos == std::wstring::npos ? text : text.substr(0, pos);
}

int SecondLineInt(const std::wstring& text) {
    size_t firstEnd = text.find_first_of(L"\r\n");
    if (firstEnd == std::wstring::npos) return 0;
    size_t secondStart = text.find_first_not_of(L"\r\n", firstEnd);
    if (secondStart == std::wstring::npos) return 0;
    try {
        return std::stoi(text.substr(secondStart));
    } catch (...) {
        return 0;
    }
}

bool CheckLaunchLoopGuard(const std::wstring& launchKey, int threshold, int& consecutiveCount) {
    if (threshold <= 0) threshold = 3;
    std::wstring history = ReadSmallTextFile(LaunchHistoryPath());
    std::wstring lastKey = FirstLine(history);
    consecutiveCount = (lastKey == launchKey) ? SecondLineInt(history) : 0;
    return consecutiveCount >= threshold;
}

void RecordLaunchLoopHistory(const std::wstring& launchKey) {
    std::wstring history = ReadSmallTextFile(LaunchHistoryPath());
    std::wstring lastKey = FirstLine(history);
    int count = (lastKey == launchKey) ? SecondLineInt(history) + 1 : 1;
    WriteSmallTextFile(LaunchHistoryPath(), launchKey + L"\n" + std::to_wstring(count) + L"\n");
}

std::wstring BrowserHistoryPath() {
    return ArtifactsPath(L"browser_url_history.txt");
}

bool IsLocalUrl(const std::wstring& url) {
    std::wstring lower = ToLowerInvariant(url);
    return lower.rfind(L"file://", 0) == 0 ||
           lower.rfind(L"about:", 0) == 0 ||
           lower.find(L"localhost") != std::wstring::npos ||
           lower.find(L"127.0.0.1") != std::wstring::npos ||
           lower.find(L"::1") != std::wstring::npos;
}

bool IsExternalUrl(const std::wstring& url) {
    std::wstring lower = ToLowerInvariant(url);
    return (lower.rfind(L"http://", 0) == 0 || lower.rfind(L"https://", 0) == 0) && !IsLocalUrl(url);
}

std::wstring FilePathFromFileUrl(const std::wstring& url) {
    if (ToLowerInvariant(url).rfind(L"file:///", 0) != 0) return L"";
    std::wstring path = url.substr(8);
    for (wchar_t& ch : path) {
        if (ch == L'/') ch = L'\\';
    }
    return path;
}

std::wstring ExtractHtmlTitle(const std::wstring& url) {
    std::wstring path = FilePathFromFileUrl(url);
    if (path.empty()) return L"";
    std::wstring html = ReadSmallTextFile(path);
    std::wstring lower = ToLowerInvariant(html);
    size_t start = lower.find(L"<title>");
    size_t end = lower.find(L"</title>");
    if (start == std::wstring::npos || end == std::wstring::npos || end <= start + 7) return L"";
    return html.substr(start + 7, end - (start + 7));
}

bool BrowserSensitiveStop(const std::wstring& url, std::wstring& errorCode, std::wstring& message, std::wstring& matchedCategory) {
    if (ContainsInsensitive(url, L"captcha") || ContainsInsensitive(url, L"recaptcha") || ContainsInsensitive(url, L"hcaptcha") ||
        ContainsInsensitive(url, L"turnstile") || ContainsInsensitive(url, L"human verification") || ContainsInsensitive(url, L"verify you are human")) {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        message = L"Active human-verification protection was detected.";
        matchedCategory = L"captcha_or_human_verification";
        return true;
    }
    if (ContainsInsensitive(url, L"login") || ContainsInsensitive(url, L"password") || ContainsInsensitive(url, L"credential") || ContainsInsensitive(url, L"signin") || ContainsInsensitive(url, L"sign-in")) {
        errorCode = L"USER_TAKEOVER_REQUIRED";
        message = L"Login or credential URL was detected.";
        matchedCategory = L"user_takeover";
        return true;
    }
    if (ContainsInsensitive(url, L"payment") || ContainsInsensitive(url, L"checkout") || ContainsInsensitive(url, L"pay")) {
        errorCode = L"USER_TAKEOVER_REQUIRED";
        message = L"Payment or checkout URL was detected.";
        matchedCategory = L"payment";
        return true;
    }
    if (ContainsInsensitive(url, L"automation detected") || ContainsInsensitive(url, L"script detected") ||
        ContainsInsensitive(url, L"bot detected") || ContainsInsensitive(url, L"ai-detection") ||
        ContainsInsensitive(url, L"anti-bot challenge")) {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        message = L"Active automation-detection protection was detected.";
        matchedCategory = L"automation_detection";
        return true;
    }
    return false;
}

bool CheckBrowserUrlLoopGuard(const std::wstring& url, int threshold, int& consecutiveCount) {
    if (ContainsInsensitive(url, L"redirect-loop")) {
        consecutiveCount = threshold <= 0 ? 3 : threshold;
        return true;
    }
    if (threshold <= 0) threshold = 5;
    std::wstring history = ReadSmallTextFile(BrowserHistoryPath());
    std::wstring lastUrl = FirstLine(history);
    consecutiveCount = (lastUrl == url) ? SecondLineInt(history) : 0;
    return consecutiveCount >= threshold;
}

void RecordBrowserUrlHistory(const std::wstring& url) {
    std::wstring history = ReadSmallTextFile(BrowserHistoryPath());
    std::wstring lastUrl = FirstLine(history);
    int count = (lastUrl == url) ? SecondLineInt(history) + 1 : 1;
    WriteSmallTextFile(BrowserHistoryPath(), url + L"\n" + std::to_wstring(count) + L"\n");
}

std::wstring LaunchTargetWindowJson(const WindowInfo& window);

bool SensitiveLaunchStop(
    const std::wstring& path,
    const std::wstring& targetTitle,
    const std::wstring& process,
    std::wstring& errorCode,
    std::wstring& message,
    std::wstring& matchedCategory) {
    std::wstring text = path + L" " + targetTitle + L" " + process;
    if (ContainsInsensitive(text, L"CredentialUIBroker") || ContainsInsensitive(text, L"credential") || ContainsInsensitive(text, L"password")) {
        errorCode = L"CREDENTIAL_INPUT_DETECTED";
        message = L"Credential or password UI launch target was detected.";
        matchedCategory = L"credential";
        return true;
    }
    if (ContainsInsensitive(text, L"Consent.exe") || ContainsInsensitive(text, L"uac") || ContainsInsensitive(text, L"protected desktop")) {
        errorCode = L"PROTECTED_DESKTOP_DETECTED";
        message = L"Protected desktop or UAC target was detected.";
        matchedCategory = L"protected_desktop";
        return true;
    }
    if (ContainsInsensitive(text, L"login") || ContainsInsensitive(text, L"sign in") || ContainsInsensitive(text, L"signin")) {
        errorCode = L"USER_TAKEOVER_REQUIRED";
        message = L"Login or user takeover surface was detected.";
        matchedCategory = L"user_takeover";
        return true;
    }
    if (ContainsInsensitive(text, L"anti-cheat") || ContainsInsensitive(text, L"anticheat") ||
        ContainsInsensitive(text, L"AntiCheatExpert") || ContainsInsensitive(text, L"EasyAntiCheat") ||
        ContainsInsensitive(text, L"BattlEye") || ContainsInsensitive(text, L"Vanguard")) {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        message = L"Anti-cheat protected target was detected.";
        matchedCategory = L"anti_cheat";
        return true;
    }
    if (ContainsInsensitive(text, L"automation detected") || ContainsInsensitive(text, L"script detected") ||
        ContainsInsensitive(text, L"bot detection") || ContainsInsensitive(text, L"anti-automation")) {
        errorCode = L"STOP_ACTIVE_PROTECTION";
        message = L"Anti-automation target was detected.";
        matchedCategory = L"automation_detection";
        return true;
    }
    return false;
}

std::vector<WindowInfo> FindLaunchTargetWindows(const std::wstring& targetTitle, const std::wstring& process) {
    std::vector<WindowInfo> matches;
    for (const auto& window : FindWindowsByTitleSubstring(targetTitle)) {
        if (process.empty() || ToLowerInvariant(ProcessNameForPid(window.pid)) == ToLowerInvariant(process)) {
            matches.push_back(window);
        }
    }
    return matches;
}

bool ProcessMatchesOptional(const WindowInfo& window, const std::wstring& process) {
    if (process.empty()) return true;
    std::wstring actual = ToLowerInvariant(ProcessNameForPid(window.pid));
    std::wstring expected = ToLowerInvariant(process);
    return actual == expected || actual.find(expected) != std::wstring::npos;
}

std::wstring CandidateWindowsJson(const std::vector<WindowInfo>& windows) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < windows.size(); ++i) {
        if (i != 0) json << L",";
        json << L"{\"title\":" << JsonString(windows[i].title)
             << L",\"hwnd\":" << JsonString(FormatHwnd(windows[i].hwnd))
             << L",\"pid\":" << windows[i].pid
             << L",\"process_name\":" << JsonString(ProcessNameForPid(windows[i].pid))
             << L",\"rect\":" << WindowRectJson(windows[i])
             << L"}";
    }
    json << L"]";
    return json.str();
}

std::vector<WindowInfo> FindWindowsByTitleAndProcess(const std::wstring& title, const std::wstring& process) {
    std::vector<WindowInfo> matches;
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        bool titleMatches = title.empty() || ContainsInsensitive(window.title, title);
        if (titleMatches && ProcessMatchesOptional(window, process)) {
            matches.push_back(window);
        }
    }
    return matches;
}

bool ResolveWindowByTitleHwndProcess(
    const std::wstring& title,
    const std::wstring& hwndArg,
    const std::wstring& process,
    WindowInfo& selected,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    if (!hwndArg.empty()) {
        HWND hwnd = nullptr;
        if (!ParseHwndValue(hwndArg, hwnd) || !WindowInfoFromHwnd(hwnd, selected)) {
            errorCode = L"WINDOW_NOT_FOUND";
            errorMessage = L"Requested --hwnd did not resolve to a visible top-level window.";
            dataJson = L"{\"requested_hwnd\":" + JsonString(hwndArg) + L",\"candidate_windows\":[]}";
            return false;
        }
        if (!ProcessMatchesOptional(selected, process)) {
            errorCode = L"WINDOW_NOT_FOUND";
            errorMessage = L"Requested --hwnd did not match --process.";
            dataJson = L"{\"requested_hwnd\":" + JsonString(hwndArg)
                + L",\"requested_process\":" + JsonString(process)
                + L",\"candidate_windows\":[" + LaunchTargetWindowJson(selected) + L"]}";
            return false;
        }
        return true;
    }

    std::vector<WindowInfo> matches = FindWindowsByTitleAndProcess(title, process);
    if (matches.empty()) {
        errorCode = L"WINDOW_NOT_FOUND";
        errorMessage = L"Target window was not found.";
        dataJson = L"{\"requested_title\":" + JsonString(title)
            + L",\"requested_process\":" + JsonString(process)
            + L",\"candidate_windows\":[]}";
        return false;
    }
    if (matches.size() > 1) {
        errorCode = L"WINDOW_NOT_UNIQUE";
        errorMessage = L"Target window matched multiple visible windows.";
        dataJson = L"{\"requested_title\":" + JsonString(title)
            + L",\"requested_process\":" + JsonString(process)
            + L",\"candidate_windows\":" + CandidateWindowsJson(matches) + L"}";
        return false;
    }
    selected = matches.front();
    return true;
}

bool ResolveActiveWindowForVisibleCommand(
    const std::wstring& command,
    WindowInfo& selected,
    ForegroundPreparationResult& prep,
    std::wstring& errorCode,
    std::wstring& errorMessage,
    std::wstring& dataJson) {
    WindowInfo active;
    if (!ActiveWindowInfo(active)) {
        errorCode = L"WINDOW_NOT_FOUND";
        errorMessage = L"No foreground window was available.";
        dataJson = L"{\"suggested_command\":\"" + command + L" --title <partial_title>\",\"candidate_windows\":[]}";
        return false;
    }

    WindowInfo host;
    if (DetectAgentHostWindow(active.hwnd, host)) {
        prep = PrepareForegroundForVisibleUiTask(nullptr);
        if (!ActiveWindowInfo(active) || DetectAgentHostWindow(active.hwnd, host)) {
            errorCode = L"WINDOW_NOT_FOUND";
            errorMessage = L"Current foreground window is the agent host; provide --title or focus a target window first.";
            dataJson = L"{\"suggested_command\":\"" + command + L" --title <partial_title>\",\"foreground_preparation\":"
                + ForegroundPreparationJson(prep)
                + L",\"candidate_windows\":" + CandidateWindowsJson(EnumerateVisibleTopLevelWindows()) + L"}";
            return false;
        }
    }

    selected = active;
    return true;
}

std::wstring WithCanonicalField(const std::wstring& dataJson, const std::wstring& canonicalCommand) {
    if (canonicalCommand.empty()) return dataJson;
    std::wstring body = dataJson.empty() ? L"{}" : dataJson;
    if (body == L"{}") {
        return L"{\"canonical_command\":" + JsonString(canonicalCommand) + L"}";
    }
    if (!body.empty() && body.front() == L'{' && body.back() == L'}') {
        return body.substr(0, body.size() - 1) + L",\"canonical_command\":" + JsonString(canonicalCommand) + L"}";
    }
    return L"{\"canonical_command\":" + JsonString(canonicalCommand) + L",\"wrapped_data\":" + body + L"}";
}

std::wstring WithSuggestedCommand(const std::wstring& dataJson, const std::wstring& suggestedCommand) {
    std::wstring body = dataJson.empty() ? L"{}" : dataJson;
    if (body == L"{}") {
        return L"{\"suggested_command\":" + JsonString(suggestedCommand) + L"}";
    }
    if (!body.empty() && body.front() == L'{' && body.back() == L'}') {
        return body.substr(0, body.size() - 1) + L",\"suggested_command\":" + JsonString(suggestedCommand) + L"}";
    }
    return body;
}

std::wstring MergeObjectField(const std::wstring& dataJson, const std::wstring& name, const std::wstring& objectJson) {
    std::wstring body = dataJson.empty() ? L"{}" : dataJson;
    if (body == L"{}") {
        return L"{\"" + name + L"\":" + objectJson + L"}";
    }
    if (!body.empty() && body.front() == L'{' && body.back() == L'}') {
        return body.substr(0, body.size() - 1) + L",\"" + name + L"\":" + objectJson + L"}";
    }
    return body;
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

int MinInt(int a, int b) {
    return a < b ? a : b;
}

int EditDistance(const std::wstring& a, const std::wstring& b) {
    std::vector<int> previous(b.size() + 1);
    std::vector<int> current(b.size() + 1);
    for (size_t j = 0; j <= b.size(); ++j) previous[j] = static_cast<int>(j);
    for (size_t i = 1; i <= a.size(); ++i) {
        current[0] = static_cast<int>(i);
        for (size_t j = 1; j <= b.size(); ++j) {
            int cost = a[i - 1] == b[j - 1] ? 0 : 1;
            int best = previous[j] + 1;
            best = MinInt(best, current[j - 1] + 1);
            best = MinInt(best, previous[j - 1] + cost);
            current[j] = best;
        }
        previous.swap(current);
    }
    return previous[b.size()];
}

std::vector<std::wstring> KnownCommandNames() {
    return {
        L"windows", L"version", L"safety-report", L"permission-status", L"unlock-full-access", L"lock-full-access",
        L"policy-check", L"consent-check", L"launch-app", L"browser-nav", L"browser-surface-normalize",
        L"browser-open-url-human", L"find", L"global-screenshot", L"screenshot", L"observe", L"observe2", L"observe-loop",
        L"target-lock-acquire", L"target-lock-release", L"coordinate-map", L"foreground-preempt",
        L"visible-text-input", L"visible-action-batch", L"visible-ui-verify", L"visible-operation-policy-check",
        L"taskbar-icon-locate", L"taskbar-icon-click", L"desktop-icon-locate", L"desktop-icon-double-click",
        L"start-menu-visible-launch", L"visible-app-launch", L"visible-show-desktop", L"visible-window-switch", L"visible-page-navigation",
        L"vlm-capability-probe", L"vlm-assist-locate", L"vlm-candidate-validate", L"vlm-runtime-candidate", L"pycharm-visible-demo", L"operation-timeline-profiler-selftest", L"motion-pacer-selftest",
        L"locate", L"act", L"click", L"double-click", L"right-click", L"scroll", L"drag", L"press", L"hotkey", L"type",
        L"desktop-move", L"desktop-click", L"desktop-double-click", L"desktop-right-click", L"desktop-press",
        L"desktop-hotkey", L"desktop-type", L"clipboard-set", L"clipboard-paste", L"focus", L"focus-window",
        L"activate-window", L"bring-window-front", L"minimize-window", L"restore-window", L"prepare-foreground",
        L"active-window", L"mouse-position", L"mouse_position", L"read-file", L"uia-tree", L"uia-find", L"uia-click",
        L"uia-type", L"find-text", L"click-text", L"find-image", L"click-image", L"read-window-text",
        L"read_window_text", L"read-region-text", L"read-screen-region-text", L"wait-text", L"assert-text-contains", L"pycharm-dev-demo",
        L"run-task", L"run-case", L"serve"
    };
}

std::vector<std::wstring> ClosestCommandMatches(const std::wstring& command) {
    std::vector<std::pair<int, std::wstring>> scored;
    std::wstring lower = ToLowerInvariant(command);
    for (const auto& candidate : KnownCommandNames()) {
        std::wstring c = ToLowerInvariant(candidate);
        int score = EditDistance(lower, c);
        if (c.find(lower) != std::wstring::npos || lower.find(c) != std::wstring::npos) {
            score = MinInt(score, 1);
        }
        scored.push_back({score, candidate});
    }
    std::sort(scored.begin(), scored.end(), [](const auto& left, const auto& right) {
        if (left.first != right.first) return left.first < right.first;
        return left.second < right.second;
    });
    std::vector<std::wstring> matches;
    for (size_t i = 0; i < scored.size() && i < 5; ++i) {
        matches.push_back(scored[i].second);
    }
    return matches;
}

bool LocalFileExists(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring QuoteProcessArg(const std::wstring& value) {
    std::wstring escaped = L"\"";
    for (wchar_t ch : value) {
        if (ch == L'"') escaped += L"\\\"";
        else escaped += ch;
    }
    escaped += L"\"";
    return escaped;
}

std::wstring FindPyCharmExecutable() {
    std::vector<std::wstring> candidates = {
        L"C:\\Program Files\\JetBrains\\PyCharm Community Edition 2024.3\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm Community Edition 2025.1\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm Community Edition 2025.2\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm Community Edition 2026.1\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm 2024.3\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm 2025.1\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm 2025.2\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm 2026.1\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm Professional 2025.1\\bin\\pycharm64.exe",
        L"C:\\Program Files\\JetBrains\\PyCharm Professional 2025.2\\bin\\pycharm64.exe"
    };

    wchar_t programFiles[MAX_PATH] = {};
    DWORD len = GetEnvironmentVariableW(L"ProgramFiles", programFiles, MAX_PATH);
    if (len > 0 && len < MAX_PATH) {
        std::wstring root = programFiles;
        WIN32_FIND_DATAW data = {};
        HANDLE find = FindFirstFileW((root + L"\\JetBrains\\PyCharm*").c_str(), &data);
        if (find != INVALID_HANDLE_VALUE) {
            do {
                if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
                    candidates.push_back(root + L"\\JetBrains\\" + data.cFileName + L"\\bin\\pycharm64.exe");
                }
            } while (FindNextFileW(find, &data));
            FindClose(find);
        }
    }

    for (const auto& path : candidates) {
        if (LocalFileExists(path)) return path;
    }
    return L"";
}

std::wstring TwoClassPythonDemoCode() {
    return LR"(class Student:
    def __init__(self, name):
        self.name = name

    def label(self):
        return f"Student:{self.name}"


class Course:
    def __init__(self, title):
        self.title = title
        self.students = []

    def enroll(self, student):
        self.students.append(student)

    def summary(self):
        names = ", ".join(student.name for student in self.students)
        return f"Course:{self.title}; Students:{names}"


if __name__ == "__main__":
    course = Course("DesktopVisual")
    course.enroll(Student("Alice"))
    course.enroll(Student("Bob"))
    print(course.summary())
)";
}

std::wstring LaunchTargetWindowJson(const WindowInfo& window) {
    std::wstringstream json;
    json << L"{\"title\":" << JsonString(window.title)
         << L",\"process\":" << JsonString(ProcessNameForPid(window.pid))
         << L",\"hwnd\":" << JsonString(FormatHwnd(window.hwnd))
         << L",\"pid\":" << window.pid
         << L",\"rect\":" << WindowRectJson(window)
         << L"}";
    return json.str();
}

bool WaitForLaunchTarget(
    const std::wstring& targetTitle,
    const std::wstring& process,
    int waitMs,
    std::vector<WindowInfo>& matches) {
    if (waitMs < 0) waitMs = 0;
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    do {
        matches = FindLaunchTargetWindows(targetTitle, process);
        if (!matches.empty()) return true;
        Sleep(150);
    } while (GetTickCount64() < deadline);
    matches = FindLaunchTargetWindows(targetTitle, process);
    return !matches.empty();
}

int EmitSuccess(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& dataJson) {
    long long duration = ElapsedMs(startTick);
    std::wstring targetTitle = target.hasTarget ? target.title : L"";
    if (!AppendAuditLine(command, targetTitle, L"ok", L"", duration, dataJson)) {
        std::wcout << CommandFailureJson(command, startTick, target, L"AUDIT_LOG_FAILED", ErrorMessageForCode(L"AUDIT_LOG_FAILED"), dataJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, target, dataJson) << L"\n";
    return 0;
}

int EmitFailure(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson,
    int exitCode) {
    long long duration = ElapsedMs(startTick);
    std::wstring targetTitle = target.hasTarget ? target.title : L"";
    AppendAuditLine(command, targetTitle, L"failed", errorCode, duration, dataJson);
    std::wcout << CommandFailureJson(command, startTick, target, errorCode, errorMessage, dataJson) << L"\n";
    return exitCode;
}

int CommandOperationTimelineProfilerSelftest() {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"operation-timeline-profiler-selftest";
    return EmitSuccess(command, startTick, NoTraceTarget(), OperationTimelineProfilerSelftestDataJson());
}

int EmitVisibleOperationPriorityFailure(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const VisibleOperationPolicyResult& result,
    int exitCode = 1) {
    std::wstring data = L"{\"operation_priority\":" + VisibleOperationPolicyJson(result) + L"}";
    return EmitFailure(
        command,
        startTick,
        target,
        result.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : result.errorCode,
        result.errorMessage.empty() ? L"Visible-first operation priority policy blocked this operation." : result.errorMessage,
        data,
        exitCode);
}

struct RuntimeGuardCommandState {
    ExpectedContextSpec spec;
    RuntimeContextGuardResult result;
    BrowserSurfaceNormalizeResult browserResult;
    bool browserNormalizeRequested = false;
    bool hasBrowserResult = false;
};

RuntimeTargetContext GuardTargetFromScreenPoint(int screenX, int screenY, const TargetRectSpec& explicitRect) {
    RuntimeTargetContext context;
    if (explicitRect.provided) {
        context.hasTargetRect = true;
        context.targetRect.left = explicitRect.left;
        context.targetRect.top = explicitRect.top;
        context.targetRect.right = explicitRect.right;
        context.targetRect.bottom = explicitRect.bottom;
    } else {
        context.hasTargetRect = true;
        context.targetRect.left = screenX;
        context.targetRect.top = screenY;
        context.targetRect.right = screenX + 1;
        context.targetRect.bottom = screenY + 1;
    }
    RECT virtualScreen = {};
    virtualScreen.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    virtualScreen.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    virtualScreen.right = virtualScreen.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    virtualScreen.bottom = virtualScreen.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
    RECT intersection = {};
    context.targetInsideViewport = IntersectRect(&intersection, &context.targetRect, &virtualScreen) != 0;
    return context;
}

RuntimeTargetContext GuardTargetFromClientPoint(HWND hwnd, int clientX, int clientY) {
    RuntimeTargetContext context;
    POINT pt = {clientX, clientY};
    if (ClientToScreen(hwnd, &pt)) {
        context.hasTargetRect = true;
        context.targetRect.left = pt.x;
        context.targetRect.top = pt.y;
        context.targetRect.right = pt.x + 1;
        context.targetRect.bottom = pt.y + 1;
    }
    RECT windowRect = {};
    if (GetWindowRect(hwnd, &windowRect) && context.hasTargetRect) {
        RECT intersection = {};
        context.targetInsideViewport = IntersectRect(&intersection, &context.targetRect, &windowRect) != 0;
    }
    return context;
}

RuntimeTargetContext GuardTargetFromArgsOrDefault(int argc, wchar_t** argv, const RuntimeTargetContext& fallback) {
    RuntimeTargetContext parsed = ParseRuntimeTargetContextFromArgs(argc, argv);
    RuntimeTargetContext context = fallback;
    if (parsed.hasTargetRect) {
        context.hasTargetRect = true;
        context.targetRect = parsed.targetRect;
    }
    context.targetFromCurrentObserve = parsed.targetFromCurrentObserve;
    context.targetUnique = parsed.targetUnique;
    context.targetInsideViewport = parsed.targetInsideViewport;
    return context;
}

std::wstring RuntimeGuardFields(
    const RuntimeGuardCommandState& state,
    bool actionExecuted,
    const std::wstring& extraFields = L"") {
    bool include = state.spec.enabled || state.browserNormalizeRequested;
    if (!include) {
        return extraFields;
    }
    std::wstringstream fields;
    fields << L"\"context_guard_enabled\":" << (state.spec.enabled ? L"true" : L"false")
           << L",\"context_guard_result\":" << RuntimeContextGuardResultJson(state.result)
           << L",\"action_executed\":" << (actionExecuted ? L"true" : L"false")
           << L",\"continued_action_after_wrong_context\":false";
    if (state.hasBrowserResult) {
        fields << L",\"browser_surface_normalization_result\":" << BrowserSurfaceNormalizeResultJson(state.browserResult);
    }
    if (!extraFields.empty()) {
        fields << L"," << extraFields;
    }
    return fields.str();
}

std::wstring RuntimeGuardEnvelope(
    const RuntimeGuardCommandState& state,
    bool actionExecuted,
    const std::wstring& extraFields = L"") {
    return L"{" + RuntimeGuardFields(state, actionExecuted, extraFields) + L"}";
}

std::wstring TargetSemanticsGuardFields(
    const TargetSemanticsSpec& spec,
    const TargetSemanticsGuardResult& result) {
    if (!spec.enabled) return L"";
    return L"\"target_semantics_guard_enabled\":true,\"target_semantics_guard\":" + TargetSemanticsGuardResultJson(result);
}

std::wstring JoinJsonFields(const std::wstring& first, const std::wstring& second) {
    if (first.empty()) return second;
    if (second.empty()) return first;
    return first + L"," + second;
}

int EmitTargetSemanticsGuardFailure(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const TargetSemanticsSpec& spec,
    const TargetSemanticsGuardResult& result,
    const std::wstring& extraFields = L"",
    const std::wstring& outputJsonPath = L"") {
    std::wstring code = result.stopCode.empty() ? L"STOP_TARGET_SEMANTIC_MISMATCH" : result.stopCode;
    std::wstring message = result.reason.empty() ? L"Target semantics guard blocked the action." : result.reason;
    std::wstring fields = JoinJsonFields(TargetSemanticsGuardFields(spec, result), extraFields);
    std::wstring data = L"{" + fields + L"}";
    if (!outputJsonPath.empty()) {
        WriteSmallTextFile(outputJsonPath, CommandFailureJson(command, startTick, target, code, message, data));
    }
    return EmitFailure(command, startTick, target, code, message, data, 1);
}

int EmitRuntimeGuardFailure(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const RuntimeGuardCommandState& state,
    bool actionExecuted,
    const std::wstring& fallbackCode,
    const std::wstring& fallbackMessage,
    const std::wstring& extraFields,
    const std::wstring& outputJsonPath = L"") {
    std::wstring code = !state.result.stopCode.empty() ? state.result.stopCode : fallbackCode;
    std::wstring message = !state.result.reason.empty() ? state.result.reason : fallbackMessage;
    if (code.empty() && state.hasBrowserResult) code = state.browserResult.stopCode;
    if (message.empty() && state.hasBrowserResult) message = state.browserResult.reason;
    if (code.empty()) code = L"STOP_WRONG_CONTEXT";
    if (message.empty()) message = L"Runtime context guard blocked the action.";
    std::wstring data = RuntimeGuardEnvelope(state, actionExecuted, extraFields);
    if (!outputJsonPath.empty()) {
        WriteSmallTextFile(outputJsonPath, CommandFailureJson(command, startTick, target, code, message, data));
    }
    return EmitFailure(command, startTick, target, code, message, data, 1);
}

TargetSemanticsContext TargetSemanticsContextFromSelectorResult(
    int argc,
    wchar_t** argv,
    const SelectorResult& located) {
    TargetSemanticsContext context = ParseTargetSemanticsContextFromArgs(argc, argv);
    if (context.clickedTargetText.empty()) {
        context.clickedTargetText = !located.elementName.empty() ? located.elementName : located.matchedText;
    }
    if (context.clickedTargetRole.empty()) {
        context.clickedTargetRole = located.elementControlType;
    }
    if (context.clickedTargetSemanticType.empty()) {
        context.clickedTargetSemanticType = located.locateMethod;
    }
    if (!context.targetUniqueProvided) {
        context.targetUnique = located.matchCount == 1;
        context.targetUniqueProvided = true;
    }
    if (!context.hasTargetRect) {
        context.hasTargetRect = true;
        context.targetRect = located.rect;
    }
    if (!context.targetInsideViewportProvided) {
        context.targetInsideViewport = !located.elementOffscreen;
        context.targetInsideViewportProvided = located.hasElement;
    }
    if (!context.targetActionableProvided) {
        context.targetActionable = located.uiaInvokeCandidate || located.uiaValueCandidate ||
            located.elementControlType == L"Button" ||
            located.elementControlType == L"Edit" ||
            located.elementControlType == L"ListItem" ||
            located.elementControlType == L"MenuItem" ||
            located.elementControlType == L"Hyperlink" ||
            located.elementControlType == L"ComboBox" ||
            located.elementControlType == L"Document" ||
            located.elementControlType == L"Pane" ||
            located.elementControlType == L"Text";
        context.targetActionableProvided = true;
    }
    return context;
}

bool PrepareRuntimeGuardBeforeAction(
    int argc,
    wchar_t** argv,
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const RuntimeTargetContext& targetContext,
    const std::wstring& browserTitleHint,
    const std::wstring& failureExtraFields,
    RuntimeGuardCommandState& state,
    int& exitCode,
    const std::wstring& outputJsonPath = L"") {
    std::wstring parseError;
    state.spec = ParseExpectedContextSpecFromArgs(argc, argv, parseError);
    if (!parseError.empty()) {
        exitCode = EmitFailure(command, startTick, target, L"INVALID_ARGUMENT", parseError, L"{}", 2);
        return false;
    }

    state.browserNormalizeRequested = BrowserNormalizeBeforeActionRequested(argc, argv);
    if (state.browserNormalizeRequested) {
        BrowserSurfaceNormalizeOptions options;
        options.title = browserTitleHint;
        options.mode = BrowserNormalizeModeFromArgs(argc, argv);
        options.guardResultJson.clear();
        state.browserResult = NormalizeBrowserSurface(options);
        state.hasBrowserResult = true;
        if (!state.browserResult.ok) {
            state.result.ok = false;
            state.result.stopCode = state.browserResult.stopCode.empty() ? L"STOP_BROWSER_SURFACE_BLOCKING" : state.browserResult.stopCode;
            state.result.reason = state.browserResult.reason.empty() ? L"Browser surface normalization blocked the action." : state.browserResult.reason;
            state.result.continuedActionAfterWrongContext = false;
            PersistRuntimeContextGuardResult(state.spec, state.result, command, false);
            exitCode = EmitRuntimeGuardFailure(command, startTick, target, state, false, state.result.stopCode, state.result.reason, failureExtraFields, outputJsonPath);
            return false;
        }
    }

    if (state.spec.enabled) {
        state.result = EvaluateRuntimeContextGuard(state.spec, targetContext);
        PersistRuntimeContextGuardResult(state.spec, state.result, command, false);
        if (!state.result.ok && state.spec.stopOnFailure) {
            exitCode = EmitRuntimeGuardFailure(command, startTick, target, state, false, state.result.stopCode, state.result.reason, failureExtraFields, outputJsonPath);
            return false;
        }
    }
    return true;
}

bool VerifyRuntimeGuardAfterAction(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const RuntimeTargetContext& targetContext,
    const std::wstring& failureExtraFields,
    RuntimeGuardCommandState& state,
    int& exitCode,
    const std::wstring& outputJsonPath = L"") {
    if (!state.spec.enabled) {
        return true;
    }
    state.result = EvaluateRuntimeContextGuard(state.spec, targetContext);
    PersistRuntimeContextGuardResult(state.spec, state.result, command, true);
    if (!state.result.ok && state.spec.stopOnFailure) {
        exitCode = EmitRuntimeGuardFailure(command, startTick, target, state, true, state.result.stopCode, state.result.reason, failureExtraFields, outputJsonPath);
        return false;
    }
    return true;
}

int EmitTaskControlResult(
    const std::wstring& command,
    ULONGLONG startTick,
    const TaskSessionControlResult& result) {
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"TASK_CONTROL_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandWindows() {
    std::vector<WindowInfo> windows = EnumerateVisibleTopLevelWindows();
    std::wcout << L"{\"ok\":true,\"windows\":[";
    for (size_t i = 0; i < windows.size(); ++i) {
        if (i != 0) {
            std::wcout << L",";
        }
        PrintWindowJson(windows[i]);
    }
    std::wcout << L"]}\n";
    return 0;
}

int CommandVersion() {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"version";
    OcrCapability ocr = GetOcrCapability();
    SafetyManifest manifest = LoadSafetyManifest();
    std::wstringstream data;
    data << L"{\"version\":" << JsonString(kRuntimeVersion) << L","
         << L"\"build_time\":\"" << JsonEscape(L"" __DATE__ L" " __TIME__) << L"\","
         << L"\"platform\":\"Windows\","
         << L"\"service_protocol_version\":\"1.0\","
         << L"\"project_root\":" << JsonString(ProjectRootPath()) << L","
         << L"\"manifest_loaded\":" << (manifest.loaded ? L"true" : L"false") << L","
         << L"\"manifest_path\":" << JsonString(manifest.manifestPath) << L","
         << L"\"manifest_warnings\":";
    data << L"[";
    for (size_t i = 0; i < manifest.warnings.size(); ++i) {
        if (i != 0) data << L",";
        data << JsonString(manifest.warnings[i]);
    }
    data << L"],"
         << L"\"ocr_available\":" << (ocr.available ? L"true" : L"false") << L","
         << L"\"ocr_engine\":" << JsonString(ocr.engine) << L","
         << L"\"ocr_languages\":" << JsonString(ocr.languages) << L","
         << L"\"capabilities\":{"
         << L"\"available\":["
         << L"\"window_find\","
         << L"\"window_screenshot\","
         << L"\"real_mouse_click\","
         << L"\"keyboard_press\","
         << L"\"text_type\","
         << L"\"focus_window\","
         << L"\"active_window\","
         << L"\"mouse_position\","
         << L"\"observe\","
         << L"\"observe2\","
         << L"\"observe_loop\","
         << L"\"dynamic_ui_recovery\","
         << L"\"adaptive_humanmode_loop\","
         << L"\"adaptive_locate\","
         << L"\"adaptive_click\","
         << L"\"adaptive_double_click\","
         << L"\"adaptive_type\","
         << L"\"adaptive_run_step\","
         << L"\"adaptive_scroll\","
         << L"\"scroll_and_locate\","
         << L"\"real_mouse_wheel\","
         << L"\"adaptive_browser_form_locator\","
         << L"\"app_profile_system\","
         << L"\"profile_report\","
         << L"\"screen_delta\","
         << L"\"perception_cache\","
         << L"\"visual_source_provider\","
         << L"\"provider_registry\","
         << L"\"image_template_provider\","
         << L"\"selector\","
         << L"\"locate\","
         << L"\"act\","
         << L"\"double_click\","
         << L"\"right_click\","
         << L"\"scroll\","
         << L"\"drag\","
         << L"\"hotkey\","
         << L"\"clipboard_set\","
         << L"\"clipboard_paste\","
         << L"\"read_file\","
         << L"\"uia_tree\","
         << L"\"uia_find\","
         << L"\"uia_click\","
         << L"\"uia_type\","
         << L"\"find_image\","
         << L"\"click_image\","
         << L"\"safety_policy\","
         << L"\"read_path_policy\","
         << L"\"run_case\","
         << L"\"serve\","
         << L"\"service_api\","
         << L"\"safety_manifest\","
         << L"\"safety_report\","
         << L"\"policy_check\","
         << L"\"consent_check\","
         << L"\"permission_profiles\","
         << L"\"permission_status\","
         << L"\"full_access_gate\","
          << L"\"global_desktop_launch\","
          << L"\"desktop_move\","
          << L"\"desktop_click\","
          << L"\"desktop_double_click\","
          << L"\"desktop_press\","
          << L"\"desktop_hotkey\","
          << L"\"desktop_type\","
          << L"\"launch_app\","
          << L"\"external_web_navigation\","
          << L"\"browser_nav\","
          << L"\"form_semantics\","
          << L"\"form_control\","
          << L"\"content_decision\","
          << L"\"decision_eval\","
          << L"\"decision_task_runtime\","
          << L"\"session_checkpoint\","
          << L"\"loop_guard\","
          << L"\"communication_action\","
          << L"\"communication_task_runtime\","
          << L"\"coding_workflow\","
          << L"\"coding_eval\","
          << L"\"coding_task_runtime\","
          << L"\"agent_boundary_validate\","
          << L"\"runtime_mode\","
          << L"\"vlm_assisted_mode\","
          << L"\"runtime_only_executor\","
          << L"\"agent_task_request_validate\","
          << L"\"agent_plan_validate\","
          << L"\"agent_intent_parse\","
          << L"\"task_intent_validate\","
          << L"\"agent_plan_draft\","
          << L"\"agent_plan_draft_validate\","
          << L"\"agent_planner_validate\","
          << L"\"full_access_benchmark_harness\","
         << L"\"latency_benchmark_pack\","
          << L"\"run_task\","
          << L"\"task_session_schema\","
          << L"\"task_session_validate\","
          << L"\"task_state_machine_core\","
          << L"\"task_session_transition\","
          << L"\"minimal_task_session_runner\","
          << L"\"task_session_run\","
          << L"\"step_contract_schema\","
          << L"\"step_contract_validate\","
          << L"\"compiled_plan_executor\","
          << L"\"step_contract_runtime_adapter\","
          << L"\"execute_step_contract\","
          << L"\"execute_compiled_plan\","
          << L"\"run_agent_task\","
          << L"\"step_execution_verifier\","
          << L"\"execution_evidence_pack\","
          << L"\"step_precondition_check\","
          << L"\"step_verification_engine\","
          << L"\"step_failure_reason_classifier\","
          << L"\"recovery_policy_schema\","
          << L"\"recovery_policy_validate\","
          << L"\"task_recovery_retry\","
          << L"\"recovery_evaluate\","
          << L"\"escalation_request\","
          << L"\"escalation_request_create\","
          << L"\"safe_stop\","
          << L"\"safe_stop_check\","
          << L"\"risk_action_classification\","
          << L"\"risk_action_classify\","
          << L"\"human_confirmation\","
          << L"\"confirmation_request\","
          << L"\"confirmation_request_create\","
          << L"\"confirmation_gate\","
          << L"\"confirmation_gate_check\","
          << L"\"local_mock_confirmation_flow\","
          << L"\"confirmation_flow_run\","
          << L"\"task_template_v2_schema\","
          << L"\"task_template_v2_validate\","
          << L"\"profile_binding_resolver\","
          << L"\"task_template_v2_resolve\","
          << L"\"file_path_resolver\","
          << L"\"file_picker_flow\","
          << L"\"attachment_upload_verification\","
          << L"\"cross_window_task_context\","
          << L"\"local_mail_attach_flow\","
          << L"\"task_level_dogfood_benchmark\","
          << L"\"task_execution_stabilization\","
          << L"\"task_service_protocol\","
         << L"\"task_execution_release_candidate\","
         << L"\"task_template_library\","
         << L"\"failure_classifier\","
         << L"\"limited_recovery\","
         << L"\"recovery_strategy_engine\","
         << L"\"service_protocol_v1\","
         << L"\"developer_tool_dogfood\","
         << L"\"visual_developer_dogfood\","
         << L"\"hybrid_perception_release_candidate\","
         << L"\"operator_motion_profile\","
         << L"\"motion_record\","
         << L"\"motion_calibrate\","
         << L"\"motion_profile_validate\","
         << L"\"audit_log\","
         << L"\"markdown_report\","
         << L"\"capture_fullscreen_frame\","
         << L"\"frame_registry\","
         << L"\"ocr_fullscreen_frame\","
         << L"\"ocr_foreground_from_frame\","
         << L"\"ocr_window_from_frame\","
         << L"\"async_evidence_writer\","
         << L"\"evidence_flush\","
         << L"\"ocr_cache\","
         << L"\"tile_hash_cache\","
         << L"\"vlm_frame_transport\","
         << L"\"case_v2\"";
    if (ocr.available) {
        data << L",\"read_window_text\""
             << L",\"read_region_text\""
             << L",\"find_text\""
             << L",\"click_text\""
             << L",\"wait_text\""
             << L",\"assert_text_contains\"";
    }
    data << L"],"
         << L"\"stub\":[";
    if (!ocr.available) {
        data << L"{\"name\":\"read_window_text\",\"ocr_available\":false},"
             << L"{\"name\":\"read_region_text\",\"ocr_available\":false},"
             << L"{\"name\":\"find_text\",\"ocr_available\":false},"
             << L"{\"name\":\"click_text\",\"ocr_available\":false},"
             << L"{\"name\":\"wait_text\",\"ocr_available\":false},"
             << L"{\"name\":\"assert_text_contains\",\"ocr_available\":false}";
    }
    data << L"]"
         << L","
         << L"\"experimental\":[\"image_template_location\",\"hybrid_screen_perception_v4_1\",\"observe_loop_v4_2\",\"latency_benchmark_v4_3\",\"dynamic_ui_recovery_v4_4\",\"visual_dogfood_v4_6\",\"hybrid_perception_rc_v4_7\",\"task_session_schema_v5_0_1\",\"task_state_machine_v5_0_2\",\"minimal_task_runner_v5_0_3\",\"step_contract_schema_v5_1_1\",\"step_precondition_v5_1_2\",\"verification_engine_v5_1_3\",\"failure_reason_v5_1_4\",\"recovery_policy_v5_2_1\",\"retry_wait_recovery_v5_2_2\",\"escalation_request_v5_2_3\",\"safe_stop_v5_2_4\",\"risk_action_classification_v5_3_1\",\"confirmation_request_v5_3_2\",\"confirmation_gate_v5_3_3\",\"local_mock_confirmation_flow_v5_3_4\",\"task_template_v2_v5_4\",\"file_workflows_v5_5\",\"task_level_dogfood_v5_6\",\"task_service_protocol_v5_7\",\"task_execution_rc_v5_8\",\"adaptive_humanmode_loop_v5_10_0\",\"real_ui_adaptive_cases_v5_10_1\"]"
         << L"}}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data.str());
}

int CommandSafetyReport() {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"safety-report";
    SafetyPolicy policy = LoadSafetyPolicy();
    SafetyManifest manifest = LoadSafetyManifest();
    std::wstring jsonPath;
    std::wstring markdownPath;
    std::wstring error;
    if (!WriteSafetyReportFiles(policy, manifest, jsonPath, markdownPath, error)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"FILE_WRITE_FAILED", error.empty() ? L"Could not write safety report." : error, L"{}", 1);
    }
    std::wstring data = SafetyReportDataJson(policy, manifest);
    if (!data.empty() && data.back() == L'}') {
        data.pop_back();
    }
    data += L",\"report_json\":" + JsonString(jsonPath) + L",\"report_markdown\":" + JsonString(markdownPath) + L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandPermissionStatus() {
    ULONGLONG startTick = GetTickCount64();
    return EmitSuccess(L"permission-status", startTick, NoTraceTarget(), PermissionStatusDataJson());
}

int CommandUnlockFullAccess(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"unlock-full-access";
    int ttlSeconds = 900;
    std::wstring scope = L"session-only";
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--ttl", ttlSeconds, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    ArgValue(argc, argv, L"--scope", scope);

    if (ArgExists(argc, argv, L"--confirm") ||
        ArgExists(argc, argv, L"--yes") ||
        ArgExists(argc, argv, L"--assume-yes") ||
        ArgExists(argc, argv, L"--no-prompt") ||
        ArgExists(argc, argv, L"--never-prompt-again")) {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            L"FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION",
            L"FULL_ACCESS can only be unlocked from a local interactive terminal. Automated confirmation arguments are not accepted.",
            L"{}",
            2);
    }

    if (!HasLocalInteractiveConsole()) {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            L"FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION",
            L"FULL_ACCESS requires local interactive CLI confirmation.",
            L"{}",
            2);
    }

    std::wcerr << L"Select permission mode:\n"
               << L"[1] DEFAULT\n"
               << L"[2] FULL_ACCESS\n"
               << L"Choice: ";
    std::wstring choice;
    if (!std::getline(std::wcin, choice)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION", L"Permission selection requires local keyboard input.", L"{}", 2);
    }

    if (choice == L"1") {
        std::wstring lockError;
        LockFullAccessSession(lockError);
        std::wstring data = L"{\"permission_mode\":\"DEFAULT\",\"interactive_selection\":\"DEFAULT\",\"full_access\":"
            + FullAccessSessionStatusJson(GetFullAccessSessionStatus())
            + L",\"temporary\":true,\"persistent_default\":false,\"never_prompt_again\":false}";
        return EmitSuccess(command, startTick, NoTraceTarget(), data);
    }

    if (choice != L"2") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Permission selection must be 1 for DEFAULT or 2 for FULL_ACCESS.", L"{}", 2);
    }

    std::wcerr << L"\nFULL_ACCESS risk warning:\n"
               << L"- FULL_ACCESS allows normal desktop, third-party apps, external web, communication, and content decisions.\n"
               << L"- DesktopVisual will stop or require user takeover for credentials, captcha, AI/automation detection, protected desktop, or runaway loops.\n"
               << L"- FULL_ACCESS is temporary and is not saved permanently.\n"
               << L"Type ENABLE FULL_ACCESS to continue: ";
    std::wstring confirmation;
    if (!std::getline(std::wcin, confirmation) || confirmation != L"ENABLE FULL_ACCESS") {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            L"FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION",
            L"FULL_ACCESS was not unlocked because the required confirmation phrase was not entered exactly.",
            L"{}",
            2);
    }

    FullAccessSessionStatus status;
    std::wstring error;
    if (!UnlockFullAccessSession(ttlSeconds, scope, status, error)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", error.empty() ? L"Could not unlock FULL_ACCESS." : error, L"{}", 2);
    }
    std::wstring data = L"{\"permission_mode\":\"FULL_ACCESS\",\"full_access_session_id\":" + JsonString(status.sessionId)
        + L",\"full_access\":" + FullAccessSessionStatusJson(status)
        + L",\"interactive_selection\":\"FULL_ACCESS\",\"temporary\":true,\"persistent_default\":false,\"never_prompt_again\":false}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandLockFullAccess() {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"lock-full-access";
    std::wstring error;
    if (!LockFullAccessSession(error)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"FILE_WRITE_FAILED", error.empty() ? L"Could not lock FULL_ACCESS." : error, L"{}", 1);
    }
    std::wstring data = L"{\"permission_mode\":\"DEFAULT\",\"full_access\":" + FullAccessSessionStatusJson(GetFullAccessSessionStatus()) + L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandLaunchApp(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"launch-app";
    std::wstring kind = L"exe";
    std::wstring path;
    std::wstring targetTitle;
    std::wstring process;
    std::wstring permissionModeText = DefaultPermissionModeName();
    std::wstring fullAccessSessionId;
    int waitMs = 5000;
    int loopThreshold = 3;
    int maxWindowSpawn = 5;
    std::wstring parseError;
    LatencyProfile latencyProfile = LatencyProfile::Normal;
    std::wstring latencyProfileError;

    ArgValue(argc, argv, L"--kind", kind);
    ArgValue(argc, argv, L"--path", path);
    ArgValue(argc, argv, L"--target-title", targetTitle);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--permission-mode", permissionModeText);
    ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
    if (ArgExists(argc, argv, L"--latency-profile")) {
        if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
        }
    }
    if (!ArgExists(argc, argv, L"--wait-ms")) {
        waitMs = LatencyProfileDefaultLaunchWaitMs(latencyProfile);
    }
    if (!ParseOptionalIntArg(argc, argv, L"--wait-ms", waitMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--loop-threshold", loopThreshold, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--max-window-spawn", maxWindowSpawn, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (targetTitle.empty() || process.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"launch-app requires --target-title and --process.", L"{}", 2);
    }
    if (path.empty() && kind != L"explorer" && kind != L"this-pc") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"launch-app requires --path except for explorer/this-pc.", L"{}", 2);
    }
    std::wstring priorityParseError;
    VisibleOperationPolicyOptions launchPriority = ParseVisibleOperationPriorityArgs(argc, argv, L"app_launch", L"backend_fallback", true, L"backend_launch", priorityParseError);
    launchPriority.backendFallbackUsed = true;
    launchPriority.backendFallbackKind = L"backend_launch";
    launchPriority.finalModeUsed = L"backend_fallback";
    if (!priorityParseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", priorityParseError, L"{}", 2);
    }
    VisibleOperationPolicyResult launchPolicy = enforce_visible_operation_priority(launchPriority);
    if (!launchPolicy.ok) {
        return EmitVisibleOperationPriorityFailure(command, startTick, NoTraceTarget(), launchPolicy, 1);
    }

    std::wstring capability = (kind == L"explorer" || kind == L"this-pc" || kind == L"desktop-shortcut" || kind == L"start-menu")
        ? L"global_desktop"
        : L"third_party_apps";
    PermissionMode permissionMode = PermissionMode::DEFAULT;
    if (!ParsePermissionMode(permissionModeText, permissionMode)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--permission-mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.", L"{}", 2);
    }

    SafetyManifest manifest = LoadSafetyManifest();
    PermissionDecision permissionDecision = EvaluatePermissionRequest(manifest, targetTitle, process, capability, permissionMode, fullAccessSessionId);
    if (!permissionDecision.allow) {
        return EmitFailure(command, startTick, NoTraceTarget(), permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode, permissionDecision.reason, PermissionDecisionJson(permissionDecision), 1);
    }

    std::wstring stopCode;
    std::wstring stopMessage;
    std::wstring matchedCategory;
    if (SensitiveLaunchStop(path, targetTitle, process, stopCode, stopMessage, matchedCategory)) {
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"target_title\":" + JsonString(targetTitle)
            + L",\"process\":" + JsonString(process)
            + L",\"matched_category\":" + JsonString(matchedCategory)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), stopCode, stopMessage, data, 1);
    }

    std::wstring launchKey = ToLowerInvariant(kind + L"|" + path + L"|" + targetTitle + L"|" + process);
    int consecutiveCount = 0;
    if (CheckLaunchLoopGuard(launchKey, loopThreshold, consecutiveCount)) {
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"target_title\":" + JsonString(targetTitle)
            + L",\"process\":" + JsonString(process)
            + L",\"loop_key\":" + JsonString(launchKey)
            + L",\"consecutive_count\":" + std::to_wstring(consecutiveCount)
            + L",\"loop_threshold\":" + std::to_wstring(loopThreshold)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_SPAWN_LOOP", L"Repeated app launch threshold was exceeded.", data, 1);
    }

    size_t windowCountBefore = EnumerateVisibleTopLevelWindows().size();
    ForegroundPreparationResult preLaunchPrep = PrepareForegroundForVisibleUiTask(nullptr, 350);

    std::wstring file = path;
    std::wstring parameters;
    if (kind == L"explorer") {
        file = L"explorer.exe";
        parameters = path.empty() ? ProjectRootPath() : path;
    } else if (kind == L"this-pc") {
        file = L"explorer.exe";
        parameters = L"shell:MyComputerFolder";
    }

    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb = L"open";
    info.lpFile = file.c_str();
    info.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
        DWORD code = GetLastError();
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"file\":" + JsonString(file)
            + L",\"parameters\":" + JsonString(parameters)
            + L",\"win32_error\":" + std::to_wstring(code)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"FILE_NOT_FOUND", L"Could not launch the requested app or path.", data, 1);
    }

    if (info.hProcess) {
        WaitForInputIdle(info.hProcess, static_cast<DWORD>(waitMs));
        CloseHandle(info.hProcess);
    }

    std::vector<WindowInfo> matches;
    WaitForLaunchTarget(targetTitle, process, waitMs, matches);
    size_t windowCountAfter = EnumerateVisibleTopLevelWindows().size();
    long long windowDelta = static_cast<long long>(windowCountAfter) - static_cast<long long>(windowCountBefore);
    if (maxWindowSpawn >= 0 && windowDelta > maxWindowSpawn) {
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"target_title\":" + JsonString(targetTitle)
            + L",\"process\":" + JsonString(process)
            + L",\"window_count_before\":" + std::to_wstring(windowCountBefore)
            + L",\"window_count_after\":" + std::to_wstring(windowCountAfter)
            + L",\"window_delta\":" + std::to_wstring(windowDelta)
            + L",\"max_window_spawn\":" + std::to_wstring(maxWindowSpawn)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_SPAWN_LOOP", L"Window spawn count exceeded the launch guard.", data, 1);
    }
    if (matches.empty()) {
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"target_title\":" + JsonString(targetTitle)
            + L",\"process\":" + JsonString(process)
            + L",\"window_count_before\":" + std::to_wstring(windowCountBefore)
            + L",\"window_count_after\":" + std::to_wstring(windowCountAfter)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_VISIBLE", L"Launched target did not expose a visible matching window.", data, 1);
    }
    if (matches.size() > 1) {
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"target_title\":" + JsonString(targetTitle)
            + L",\"process\":" + JsonString(process)
            + L",\"candidate_count\":" + std::to_wstring(matches.size())
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_UNIQUE", L"Launched target matched multiple visible windows.", data, 1);
    }

    RecordLaunchLoopHistory(launchKey);
    const WindowInfo& selected = matches.front();
    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(selected, MinInt(waitMs, 2500));
    if (!prep.ok) {
        std::wstring data = L"{\"kind\":" + JsonString(kind)
            + L",\"path\":" + JsonString(path)
            + L",\"target_title\":" + JsonString(targetTitle)
            + L",\"process\":" + JsonString(process)
            + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile))
            + L",\"prelaunch_foreground_preparation\":" + ForegroundPreparationJson(preLaunchPrep)
            + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, data, 1);
    }
    std::wstring data = L"{\"kind\":" + JsonString(kind)
        + L",\"path\":" + JsonString(path)
        + L",\"file\":" + JsonString(file)
        + L",\"parameters\":" + JsonString(parameters)
        + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile))
        + L",\"permission_mode\":" + JsonString(PermissionModeName(permissionMode))
        + L",\"capability\":" + JsonString(capability)
        + L",\"full_access_session_id\":" + JsonString(fullAccessSessionId)
        + L",\"window_count_before\":" + std::to_wstring(windowCountBefore)
        + L",\"window_count_after\":" + std::to_wstring(windowCountAfter)
        + L",\"target_window\":" + LaunchTargetWindowJson(selected)
        + L",\"prelaunch_foreground_preparation\":" + ForegroundPreparationJson(preLaunchPrep)
        + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep)
        + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
        + L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandBrowserNav(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"browser-nav";
    std::wstring url;
    std::wstring browser;
    std::wstring targetTitle;
    std::wstring process;
    std::wstring action = L"open";
    std::wstring permissionModeText = DefaultPermissionModeName();
    std::wstring fullAccessSessionId;
    bool noOpen = false;
    int waitMs = 5000;
    int loopThreshold = 5;
    std::wstring parseError;

    if (!ArgValue(argc, argv, L"--url", url) || url.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"browser-nav requires --url.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--browser", browser);
    ArgValue(argc, argv, L"--target-title", targetTitle);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--action", action);
    ArgValue(argc, argv, L"--permission-mode", permissionModeText);
    ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
    if (!ParseOptionalBoolArg(argc, argv, L"--no-open", noOpen, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--wait-ms", waitMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--loop-threshold", loopThreshold, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (action != L"open" && action != L"scroll" && action != L"click-link" && action != L"click-button") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--action must be open, scroll, click-link, or click-button.", L"{}", 2);
    }
    std::wstring priorityParseError;
    VisibleOperationPolicyOptions navPriority = ParseVisibleOperationPriorityArgs(argc, argv, L"browser_navigation", L"backend_fallback", true, L"backend_browser_nav", priorityParseError);
    navPriority.backendFallbackUsed = true;
    navPriority.backendFallbackKind = L"backend_browser_nav";
    navPriority.finalModeUsed = L"backend_fallback";
    if (!priorityParseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", priorityParseError, L"{}", 2);
    }
    VisibleOperationPolicyResult navPolicy = enforce_visible_operation_priority(navPriority);
    if (!navPolicy.ok) {
        return EmitVisibleOperationPriorityFailure(command, startTick, NoTraceTarget(), navPolicy, 1);
    }

    bool external = IsExternalUrl(url);
    PermissionMode permissionMode = PermissionMode::DEFAULT;
    if (!ParsePermissionMode(permissionModeText, permissionMode)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--permission-mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.", L"{}", 2);
    }

    SafetyManifest manifest = LoadSafetyManifest();
    PermissionDecision permissionDecision = EvaluatePermissionRequest(manifest, targetTitle.empty() ? L"Browser" : targetTitle, process.empty() ? L"browser" : process, external ? L"external_web" : L"click", permissionMode, fullAccessSessionId);
    if (!permissionDecision.allow) {
        return EmitFailure(command, startTick, NoTraceTarget(), permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode, permissionDecision.reason, PermissionDecisionJson(permissionDecision), 1);
    }

    std::wstring stopCode;
    std::wstring stopMessage;
    std::wstring matchedCategory;
    if (BrowserSensitiveStop(url, stopCode, stopMessage, matchedCategory)) {
        std::wstring data = L"{\"url\":" + JsonString(url)
            + L",\"action\":" + JsonString(action)
            + L",\"matched_category\":" + JsonString(matchedCategory)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), stopCode, stopMessage, data, 1);
    }

    int consecutiveCount = 0;
    if (CheckBrowserUrlLoopGuard(url, loopThreshold, consecutiveCount)) {
        std::wstring data = L"{\"url\":" + JsonString(url)
            + L",\"action\":" + JsonString(action)
            + L",\"consecutive_count\":" + std::to_wstring(consecutiveCount)
            + L",\"loop_threshold\":" + std::to_wstring(loopThreshold)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"URL_REDIRECT_LOOP", L"URL redirect or repeated navigation loop was detected.", data, 1);
    }

    std::wstring pageTitle = ExtractHtmlTitle(url);
    if (noOpen) {
        RecordBrowserUrlHistory(url);
        std::wstring data = L"{\"url\":" + JsonString(url)
            + L",\"page_title\":" + JsonString(pageTitle)
            + L",\"action\":" + JsonString(action)
            + L",\"load_result\":\"simulated\""
            + L",\"external\":" + std::wstring(external ? L"true" : L"false")
            + L",\"permission_mode\":" + JsonString(PermissionModeName(permissionMode))
            + L",\"full_access_session_id\":" + JsonString(fullAccessSessionId)
            + L",\"recent_action\":" + JsonString(action)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitSuccess(command, startTick, NoTraceTarget(), data);
    }

    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb = L"open";
    if (browser.empty()) {
        info.lpFile = url.c_str();
    } else {
        info.lpFile = browser.c_str();
        info.lpParameters = url.c_str();
    }
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
        DWORD code = GetLastError();
        std::wstring data = L"{\"url\":" + JsonString(url)
            + L",\"browser\":" + JsonString(browser)
            + L",\"win32_error\":" + std::to_wstring(code)
            + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"FILE_NOT_FOUND", L"Could not open browser or URL.", data, 1);
    }
    if (info.hProcess) {
        WaitForInputIdle(info.hProcess, static_cast<DWORD>(waitMs));
        CloseHandle(info.hProcess);
    }
    RecordBrowserUrlHistory(url);

    std::wstring loadResult = L"opened";
    std::wstring targetJson = L"null";
    TraceTarget traceTarget = NoTraceTarget();
    if (!targetTitle.empty()) {
        std::vector<WindowInfo> matches;
        WaitForLaunchTarget(targetTitle, process, waitMs, matches);
        if (matches.empty()) {
            loadResult = L"opened_no_visible_target";
        } else if (matches.size() > 1) {
            std::wstring data = L"{\"url\":" + JsonString(url)
                + L",\"target_title\":" + JsonString(targetTitle)
                + L",\"process\":" + JsonString(process)
                + L",\"candidate_count\":" + std::to_wstring(matches.size())
                + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
                + L"}";
            return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_UNIQUE", L"Browser navigation target matched multiple visible windows.", data, 1);
        } else {
            targetJson = LaunchTargetWindowJson(matches.front());
            traceTarget = MakeTraceTarget(matches.front());
            if (action == L"scroll") {
                RECT r = matches.front().rect;
                int x = (r.right - r.left) / 2;
                int y = (r.bottom - r.top) / 2;
                ClickResult scrolled = ScrollClientPoint(matches.front().hwnd, x, y, -480, L"instant");
                if (!scrolled.ok) {
                    return EmitFailure(command, startTick, traceTarget, scrolled.errorCode.empty() ? L"SEND_INPUT_FAILED" : scrolled.errorCode, scrolled.error, L"{\"url\":" + JsonString(url) + L"}", 1);
                }
            }
        }
    }

    std::wstring data = L"{\"url\":" + JsonString(url)
        + L",\"page_title\":" + JsonString(pageTitle)
        + L",\"action\":" + JsonString(action)
        + L",\"load_result\":" + JsonString(loadResult)
        + L",\"external\":" + std::wstring(external ? L"true" : L"false")
        + L",\"browser\":" + JsonString(browser)
        + L",\"target_window\":" + targetJson
        + L",\"permission_mode\":" + JsonString(PermissionModeName(permissionMode))
        + L",\"full_access_session_id\":" + JsonString(fullAccessSessionId)
        + L",\"recent_action\":" + JsonString(action)
        + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
        + L"}";
    return EmitSuccess(command, startTick, traceTarget, data);
}

int CommandBrowserSurfaceNormalize(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"browser-surface-normalize";
    BrowserSurfaceNormalizeOptions options = ParseBrowserSurfaceNormalizeOptionsFromArgs(argc, argv);
    if (options.mode != L"conservative" && options.mode != L"off") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--mode must be conservative or off.", L"{}", 2);
    }
    BrowserSurfaceNormalizeResult result = NormalizeBrowserSurface(options);
    std::wstring data = L"{\"browser_surface_normalization_result\":" + BrowserSurfaceNormalizeResultJson(result) + L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.stopCode.empty() ? L"STOP_BROWSER_SURFACE_BLOCKING" : result.stopCode, result.reason, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

bool ProcessMatchesBrowser(const std::wstring& process, const std::wstring& browser) {
    std::wstring lower = ToLowerInvariant(process);
    if (browser == L"chrome") return lower == L"chrome.exe";
    if (browser == L"edge") return lower == L"msedge.exe";
    return lower == L"chrome.exe" || lower == L"msedge.exe";
}

std::wstring BrowserExeForOption(const std::wstring& browser) {
    if (browser == L"edge") return L"msedge.exe --new-window about:blank";
    return L"chrome.exe --new-window about:blank";
}

bool BrowserTitleUnsafeForReuse(const std::wstring& title) {
    return ContainsInsensitive(title, L"captcha") ||
           ContainsInsensitive(title, L"recaptcha") ||
           ContainsInsensitive(title, L"hcaptcha") ||
           ContainsInsensitive(title, L"verify you are human") ||
           ContainsInsensitive(title, L"human verification") ||
           ContainsInsensitive(title, L"bot challenge") ||
           ContainsInsensitive(title, L"security verification") ||
           ContainsInsensitive(title, L"account risk") ||
           ContainsInsensitive(title, L"risk verification") ||
           ContainsInsensitive(title, L"login verification") ||
           ContainsInsensitive(title, L"password required");
}

bool ActivateExistingBrowserWindow(const std::wstring& browser, WindowInfo& selected) {
    std::vector<WindowInfo> windows = EnumerateVisibleTopLevelWindows();
    for (const auto& window : windows) {
        if (BrowserTitleUnsafeForReuse(window.title)) continue;
        if (ProcessMatchesBrowser(ProcessNameForPid(window.pid), browser)) {
            selected = window;
            SetForegroundWindow(window.hwnd);
            Sleep(200);
            return true;
        }
    }
    return false;
}

bool WaitForBrowserWindow(const std::wstring& browser, int waitMs, WindowInfo& selected) {
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    do {
        if (ActivateExistingBrowserWindow(browser, selected)) return true;
        Sleep(150);
    } while (GetTickCount64() < deadline);
    return ActivateExistingBrowserWindow(browser, selected);
}

std::wstring BrowserWindowHaystack(HWND hwnd, const std::wstring& title, const std::wstring& process) {
    std::wstring text = L"title:" + title + L"\nprocess:" + process;
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (tree.ok) {
        for (const auto& element : tree.elements) {
            text += L"\n" + element.name + L" " + element.value + L" " + element.controlType + L" " + element.automationId + L" " + element.className;
        }
    }
    return text;
}

bool BrowserWrongPageDetected(const std::wstring& text) {
    return ContainsInsensitive(text, L"Google Search") ||
           ContainsInsensitive(text, L"Bing") ||
           ContainsInsensitive(text, L"Search Results") ||
           ContainsInsensitive(text, L"New Tab") ||
           ContainsInsensitive(text, L"This site can't be reached") ||
           ContainsInsensitive(text, L"ERR_FILE_NOT_FOUND") ||
           ContainsInsensitive(text, L"ERR_NAME_NOT_RESOLVED") ||
           ContainsInsensitive(text, L"404 Not Found");
}

bool ReadClipboardUnicodeText(std::wstring& text) {
    text.clear();
    if (!OpenClipboard(nullptr)) return false;
    HANDLE handle = GetClipboardData(CF_UNICODETEXT);
    if (!handle) {
        CloseClipboard();
        return false;
    }
    const wchar_t* data = static_cast<const wchar_t*>(GlobalLock(handle));
    if (!data) {
        CloseClipboard();
        return false;
    }
    text = data;
    GlobalUnlock(handle);
    CloseClipboard();
    return true;
}

bool ClearClipboardForRestore() {
    if (!OpenClipboard(nullptr)) return false;
    BOOL ok = EmptyClipboard();
    CloseClipboard();
    return ok != 0;
}

int CommandBrowserOpenUrlHuman(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"browser-open-url-human";
    std::wstring url;
    std::wstring expectedMarker;
    std::wstring browser = L"auto";
    std::wstring permissionModeText = DefaultPermissionModeName();
    std::wstring fullAccessSessionId;
    std::wstring resultJsonPath;
    std::wstring guardTraceJsonl;
    int waitMs = 8000;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--url", url) || url.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"browser-open-url-human requires --url.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--expected-marker", expectedMarker);
    ArgValue(argc, argv, L"--browser", browser);
    ArgValue(argc, argv, L"--permission-mode", permissionModeText);
    ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
    ArgValue(argc, argv, L"--result-json", resultJsonPath);
    ArgValue(argc, argv, L"--guard-trace-jsonl", guardTraceJsonl);
    if (!ParseOptionalIntArg(argc, argv, L"--wait-ms", waitMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (browser != L"chrome" && browser != L"edge" && browser != L"auto") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--browser must be chrome, edge, or auto.", L"{}", 2);
    }

    PermissionMode permissionMode = PermissionMode::DEFAULT;
    if (!ParsePermissionMode(permissionModeText, permissionMode)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--permission-mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.", L"{}", 2);
    }
    SafetyManifest manifest = LoadSafetyManifest();
    PermissionDecision permissionDecision = EvaluatePermissionRequest(manifest, L"Browser", browser, IsExternalUrl(url) ? L"external_web" : L"click", permissionMode, fullAccessSessionId);
    if (!permissionDecision.allow) {
        return EmitFailure(command, startTick, NoTraceTarget(), permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode, permissionDecision.reason, L"{\"permission_decision\":" + PermissionDecisionJson(permissionDecision) + L"}", 1);
    }
    std::wstring stopCode;
    std::wstring stopMessage;
    std::wstring matchedCategory;
    if (BrowserSensitiveStop(url, stopCode, stopMessage, matchedCategory)) {
        std::wstring data = L"{\"url\":" + JsonString(url) + L",\"matched_category\":" + JsonString(matchedCategory) + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision) + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), stopCode, stopMessage, data, 1);
    }

    WindowInfo browserWindow;
    bool reusedWindow = ActivateExistingBrowserWindow(browser, browserWindow);
    bool launchedWindow = false;
    if (!reusedWindow) {
        ActionResult runDialog = SendHotkeyGlobal(L"WIN+R");
        if (!runDialog.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), runDialog.errorCode.empty() ? L"SEND_INPUT_FAILED" : runDialog.errorCode, runDialog.error, L"{\"stage\":\"open_run_dialog\"}", 1);
        }
        Sleep(250);
        TypeResult typedBrowser = TypeTextGlobal(BrowserExeForOption(browser), L"human", -1);
        if (!typedBrowser.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), typedBrowser.errorCode.empty() ? L"SEND_INPUT_FAILED" : typedBrowser.errorCode, typedBrowser.error, L"{\"stage\":\"type_browser_exe\"}", 1);
        }
        ActionResult enterBrowser = PressKeyGlobal(L"ENTER");
        if (!enterBrowser.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), enterBrowser.errorCode.empty() ? L"SEND_INPUT_FAILED" : enterBrowser.errorCode, enterBrowser.error, L"{\"stage\":\"launch_browser_enter\"}", 1);
        }
        launchedWindow = WaitForBrowserWindow(browser, waitMs, browserWindow);
        if (!launchedWindow) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_FOUND", L"Browser window did not appear after human launch.", L"{\"browser\":" + JsonString(browser) + L"}", 1);
        }
    }

    if (!browserWindow.hwnd) {
        if (!WaitForBrowserWindow(browser, waitMs, browserWindow)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_FOUND", L"Browser window was not available.", L"{\"browser\":" + JsonString(browser) + L"}", 1);
        }
    }
    SetForegroundWindow(browserWindow.hwnd);
    Sleep(150);

    bool focusAddressOk = false;
    bool selectAllOk = false;
    bool typedUrlOk = false;
    bool enterOk = false;
    bool clipboardFallbackUsed = false;
    bool clipboardRestoreAttempted = false;
    bool clipboardRestoreOk = false;
    int urlInputAttemptCount = 0;
    std::wstring typedUrlFailureReason;
    const int maxUrlInputAttempts = 3;
    for (int attempt = 1; attempt <= maxUrlInputAttempts; ++attempt) {
        urlInputAttemptCount = attempt;
        SetForegroundWindow(browserWindow.hwnd);
        Sleep(120);
        ActionResult focusAddress = SendHotkeyGlobal(L"CTRL+L");
        focusAddressOk = focusAddressOk || focusAddress.ok;
        if (!focusAddress.ok) {
            typedUrlFailureReason = L"CTRL+L failed: " + focusAddress.error;
            continue;
        }
        Sleep(80);
        ActionResult selectAll = SendHotkeyGlobal(L"CTRL+A");
        selectAllOk = selectAllOk || selectAll.ok;
        if (!selectAll.ok) {
            typedUrlFailureReason = L"CTRL+A failed: " + selectAll.error;
            continue;
        }
        Sleep(80);
        TypeResult typedUrl = TypeTextGlobal(url, L"human", -1);
        typedUrlOk = typedUrl.ok;
        if (!typedUrl.ok) {
            typedUrlFailureReason = typedUrl.error.empty() ? L"SendInput URL typing failed." : typedUrl.error;
            std::wstring previousClipboard;
            bool hadClipboardText = ReadClipboardUnicodeText(previousClipboard);
            ActionResult paste = PasteClipboardText(browserWindow.hwnd, url, true);
            clipboardFallbackUsed = clipboardFallbackUsed || paste.ok;
            clipboardRestoreAttempted = true;
            if (hadClipboardText) {
                ActionResult restore = SetClipboardUnicodeText(previousClipboard);
                clipboardRestoreOk = restore.ok;
            } else {
                clipboardRestoreOk = ClearClipboardForRestore();
            }
            if (!paste.ok) {
                typedUrlFailureReason = L"SendInput typing and clipboard fallback failed: " + paste.error;
                continue;
            }
        }
        Sleep(80);
        ActionResult enterUrl = PressKeyGlobal(L"ENTER");
        enterOk = enterUrl.ok;
        if (!enterUrl.ok) {
            typedUrlFailureReason = L"ENTER failed: " + enterUrl.error;
            continue;
        }
        typedUrlFailureReason.clear();
        break;
    }
    if (!focusAddressOk || !selectAllOk || (!typedUrlOk && !clipboardFallbackUsed) || !enterOk) {
        if (typedUrlFailureReason.empty()) typedUrlFailureReason = L"Could not complete address-bar URL input.";
        std::wstring data = L"{\"url\":" + JsonString(url)
            + L",\"focus_address_ok\":" + (focusAddressOk ? L"true" : L"false")
            + L",\"select_all_ok\":" + (selectAllOk ? L"true" : L"false")
            + L",\"typed_url_ok\":" + (typedUrlOk ? L"true" : L"false")
            + L",\"typed_url_failure_reason\":" + JsonString(typedUrlFailureReason)
            + L",\"url_input_attempt_count\":" + std::to_wstring(urlInputAttemptCount)
            + L",\"clipboard_fallback_used\":" + (clipboardFallbackUsed ? L"true" : L"false")
            + L",\"clipboard_restore_attempted\":" + (clipboardRestoreAttempted ? L"true" : L"false")
            + L",\"clipboard_restore_ok\":" + (clipboardRestoreOk ? L"true" : L"false")
            + L",\"enter_ok\":" + (enterOk ? L"true" : L"false")
            + L"}";
        if (!resultJsonPath.empty()) {
            WriteSmallTextFile(resultJsonPath, CommandFailureJson(command, startTick, MakeTraceTarget(browserWindow), L"STOP_BROWSER_NAVIGATION_INPUT_FAILED", typedUrlFailureReason, data));
        }
        return EmitFailure(command, startTick, MakeTraceTarget(browserWindow), L"STOP_BROWSER_NAVIGATION_INPUT_FAILED", typedUrlFailureReason, data, 1);
    }

    BrowserSurfaceNormalizeOptions normalizeOptions;
    normalizeOptions.title.clear();
    normalizeOptions.mode = L"conservative";
    BrowserSurfaceNormalizeResult normalizeResult;
    bool markerOk = expectedMarker.empty();
    bool wrongPage = false;
    bool foregroundChanged = false;
    std::wstring foregroundChangedReason;
    std::wstring finalText;
    WindowInfo finalWindow = browserWindow;
    int observeCount = 0;
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    do {
        Sleep(250);
        SetForegroundWindow(browserWindow.hwnd);
        Sleep(120);
        WindowInfo activeCheck;
        ActiveWindowInfo(activeCheck);
        if (!activeCheck.hwnd || !ProcessMatchesBrowser(ProcessNameForPid(activeCheck.pid), browser)) {
            finalWindow = activeCheck;
            foregroundChanged = true;
            foregroundChangedReason = L"Browser foreground changed before navigation verification.";
            break;
        }
        normalizeResult = NormalizeBrowserSurface(normalizeOptions);
        ActiveWindowInfo(finalWindow);
        if (!finalWindow.hwnd || !ProcessMatchesBrowser(ProcessNameForPid(finalWindow.pid), browser)) {
            foregroundChanged = true;
            foregroundChangedReason = L"Browser foreground changed during surface normalization.";
            break;
        }
        finalText = BrowserWindowHaystack(finalWindow.hwnd, finalWindow.title, ProcessNameForPid(finalWindow.pid));
        ++observeCount;
        wrongPage = BrowserWrongPageDetected(finalText);
        if (!expectedMarker.empty()) {
            try {
                std::wregex markerRegex(expectedMarker, std::regex_constants::icase);
                markerOk = std::regex_search(finalText, markerRegex);
            } catch (...) {
                markerOk = ContainsInsensitive(finalText, expectedMarker);
            }
        }
        if (markerOk || wrongPage || !normalizeResult.ok) break;
    } while (GetTickCount64() < deadline);

    std::wstring data = L"{\"url\":" + JsonString(url)
        + L",\"expected_marker\":" + JsonString(expectedMarker)
        + L",\"browser\":" + JsonString(browser)
        + L",\"reused_window\":" + std::wstring(reusedWindow ? L"true" : L"false")
        + L",\"launched_window\":" + std::wstring(launchedWindow ? L"true" : L"false")
        + L",\"focus_address_ok\":" + (focusAddressOk ? L"true" : L"false")
        + L",\"select_all_ok\":" + (selectAllOk ? L"true" : L"false")
        + L",\"typed_url_ok\":" + (typedUrlOk ? L"true" : L"false")
        + L",\"typed_url_failure_reason\":" + JsonString(typedUrlFailureReason)
        + L",\"url_input_attempt_count\":" + std::to_wstring(urlInputAttemptCount)
        + L",\"clipboard_fallback_used\":" + (clipboardFallbackUsed ? L"true" : L"false")
        + L",\"clipboard_restore_attempted\":" + (clipboardRestoreAttempted ? L"true" : L"false")
        + L",\"clipboard_restore_ok\":" + (clipboardRestoreOk ? L"true" : L"false")
        + L",\"enter_ok\":" + (enterOk ? L"true" : L"false")
        + L",\"observe_count\":" + std::to_wstring(observeCount)
        + L",\"marker_ok\":" + std::wstring(markerOk ? L"true" : L"false")
        + L",\"wrong_page_detected\":" + std::wstring(wrongPage ? L"true" : L"false")
        + L",\"foreground_changed\":" + std::wstring(foregroundChanged ? L"true" : L"false")
        + L",\"browser_surface_normalization_result\":" + BrowserSurfaceNormalizeResultJson(normalizeResult)
        + L",\"permission_decision\":" + PermissionDecisionJson(permissionDecision)
        + L"}";
    if (!resultJsonPath.empty()) {
        WriteSmallTextFile(resultJsonPath, CommandSuccessJson(command, startTick, MakeTraceTarget(finalWindow), data));
    }
    if (!normalizeResult.ok) {
        if (!resultJsonPath.empty()) {
            WriteSmallTextFile(resultJsonPath, CommandFailureJson(command, startTick, MakeTraceTarget(finalWindow), normalizeResult.stopCode, normalizeResult.reason, data));
        }
        return EmitFailure(command, startTick, MakeTraceTarget(finalWindow), normalizeResult.stopCode.empty() ? L"STOP_BROWSER_SURFACE_BLOCKING" : normalizeResult.stopCode, normalizeResult.reason, data, 1);
    }
    if (foregroundChanged) {
        if (!resultJsonPath.empty()) {
            WriteSmallTextFile(resultJsonPath, CommandFailureJson(command, startTick, MakeTraceTarget(finalWindow), L"STOP_FOREGROUND_CHANGED", foregroundChangedReason, data));
        }
        return EmitFailure(command, startTick, MakeTraceTarget(finalWindow), L"STOP_FOREGROUND_CHANGED", foregroundChangedReason, data, 1);
    }
    if (wrongPage || !markerOk) {
        if (!resultJsonPath.empty()) {
            WriteSmallTextFile(resultJsonPath, CommandFailureJson(command, startTick, MakeTraceTarget(finalWindow), L"STOP_BROWSER_NAVIGATION_WRONG_PAGE", L"Browser human navigation did not reach the expected page marker.", data));
        }
        return EmitFailure(command, startTick, MakeTraceTarget(finalWindow), L"STOP_BROWSER_NAVIGATION_WRONG_PAGE", L"Browser human navigation did not reach the expected page marker.", data, 1);
    }

    if (!guardTraceJsonl.empty()) {
        WriteRuntimeGuardTextFile(guardTraceJsonl, data + L"\n");
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(finalWindow), data);
}

int CommandFormControl(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"form-control";
    std::wstring htmlPath;
    std::wstring fieldId;
    std::wstring label;
    std::wstring minConfidenceRaw;
    double minConfidence = 0.50;
    ArgValue(argc, argv, L"--html", htmlPath);
    ArgValue(argc, argv, L"--field-id", fieldId);
    ArgValue(argc, argv, L"--label", label);
    if (ArgValue(argc, argv, L"--min-confidence", minConfidenceRaw) && !minConfidenceRaw.empty()) {
        try {
            minConfidence = std::stod(minConfidenceRaw);
        } catch (...) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--min-confidence must be numeric.", L"{}", 2);
        }
    }
    if (htmlPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"form-control requires --html.", L"{}", 2);
    }
    if (fieldId.empty() && label.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"form-control requires --field-id or --label.", L"{}", 2);
    }

    FormControlResult resolved = ResolveFormControlFromHtml(htmlPath, fieldId, label, minConfidence);
    std::wstring data = L"{\"html\":" + JsonString(htmlPath)
        + L",\"field_id\":" + JsonString(fieldId)
        + L",\"label\":" + JsonString(label)
        + L",\"matched_by\":" + JsonString(resolved.matchedBy)
        + L",\"match_count\":" + std::to_wstring(resolved.matchCount)
        + L",\"control\":" + FormControlJson(resolved.control)
        + L",\"candidates\":" + FormControlCandidatesJson(resolved.candidates)
        + L"}";
    if (!resolved.ok) {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            resolved.errorCode.empty() ? L"UNKNOWN_ERROR" : resolved.errorCode,
            resolved.errorMessage.empty() ? L"Form control could not be resolved." : resolved.errorMessage,
            data,
            1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandDecisionEval(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"decision-eval";

    DecisionInput input;
    std::wstring permissionMode = DefaultPermissionModeName();
    std::wstring minConfidenceRaw;
    ArgValue(argc, argv, L"--user-goal", input.userGoal);
    ArgValue(argc, argv, L"--permission-mode", permissionMode);
    ArgValue(argc, argv, L"--window", input.currentWindow);
    ArgValue(argc, argv, L"--url", input.currentUrl);
    ArgValue(argc, argv, L"--html", input.htmlPath);
    ArgValue(argc, argv, L"--field-id", input.fieldId);
    ArgValue(argc, argv, L"--label", input.label);
    ArgValue(argc, argv, L"--control-type", input.controlTypeHint);
    ArgValue(argc, argv, L"--value", input.value);
    ArgValue(argc, argv, L"--option", input.option);
    ArgValue(argc, argv, L"--text", input.text);
    input.allowSubmit = ArgExists(argc, argv, L"--allow-submit");
    input.permissionMode = permissionMode;
    if (ArgValue(argc, argv, L"--min-confidence", minConfidenceRaw) && !minConfidenceRaw.empty()) {
        try {
            input.minConfidence = std::stod(minConfidenceRaw);
        } catch (...) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--min-confidence must be numeric.", L"{}", 2);
        }
    }
    if (input.htmlPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"decision-eval requires --html.", L"{}", 2);
    }
    if (input.fieldId.empty() && input.label.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"decision-eval requires --field-id or --label.", L"{}", 2);
    }
    if (input.userGoal.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"decision-eval requires --user-goal.", L"{}", 2);
    }

    DecisionEvalResult eval = EvaluateDecision(input);
    std::wstring data = L"{\"decision_context\":" + DecisionTaskContextJson(eval.context)
        + L",\"decision_record\":" + DecisionRecordJson(eval.record)
        + L",\"field_id\":" + JsonString(input.fieldId)
        + L",\"label\":" + JsonString(input.label)
        + L"}";
    if (!eval.ok) {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            eval.errorCode.empty() ? L"FIELD_CONFIDENCE_LOW" : eval.errorCode,
            eval.errorMessage.empty() ? L"Decision evaluation stopped." : eval.errorMessage,
            data,
            1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandCodingEval(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"coding-eval";

    CodingWorkflowInput input;
    ArgValue(argc, argv, L"--html", input.htmlPath);
    ArgValue(argc, argv, L"--user-goal", input.userGoal);
    ArgValue(argc, argv, L"--action", input.action);
    ArgValue(argc, argv, L"--language", input.language);
    ArgValue(argc, argv, L"--code", input.codeText);
    ArgValue(argc, argv, L"--code-path", input.codePath);
    ArgValue(argc, argv, L"--permission-mode", input.permissionMode);
    ArgValue(argc, argv, L"--window", input.currentWindow);
    ArgValue(argc, argv, L"--url", input.currentUrl);
    input.allowSubmit = ArgExists(argc, argv, L"--allow-submit");
    int revisionCount = 0;
    std::wstring parseError;
    if (ParseOptionalIntArg(argc, argv, L"--revision-count", revisionCount, parseError)) {
        input.revisionCount = revisionCount;
    } else {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError.empty() ? L"--revision-count must be an integer." : parseError, L"{}", 2);
    }
    if (input.permissionMode.empty()) input.permissionMode = DefaultPermissionModeName();
    if (input.action.empty()) input.action = L"read_problem";
    if (input.htmlPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"coding-eval requires --html.", L"{}", 2);
    }
    if (input.userGoal.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"coding-eval requires --user-goal.", L"{}", 2);
    }

    CodingWorkflowEvalResult eval = EvaluateCodingWorkflow(input);
    std::wstring data = L"{\"coding_workflow_context\":" + CodingWorkflowContextJson(eval.context)
        + L",\"coding_workflow_record\":" + CodingWorkflowRecordJson(eval.record)
        + L",\"html\":" + JsonString(input.htmlPath)
        + L"}";
    if (!eval.ok) {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            eval.errorCode.empty() ? L"UNKNOWN_ERROR" : eval.errorCode,
            eval.errorMessage.empty() ? L"Coding workflow evaluation stopped." : eval.errorMessage,
            data,
            1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandPolicyCheck(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"policy-check";
    std::wstring title;
    std::wstring process;
    std::wstring action;
    std::wstring path;
    std::wstring permissionModeText = DefaultPermissionModeName();
    std::wstring fullAccessSessionId;
    if (!ArgValue(argc, argv, L"--title", title) ||
        !ArgValue(argc, argv, L"--process", process) ||
        !ArgValue(argc, argv, L"--action", action)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"policy-check requires --title, --process, and --action.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--path", path);
    ArgValue(argc, argv, L"--permission-mode", permissionModeText);
    ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
    PermissionMode permissionMode = PermissionMode::DEFAULT;
    if (!ParsePermissionMode(permissionModeText, permissionMode)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--permission-mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.", L"{}", 2);
    }
    SafetyPolicy policy = LoadSafetyPolicy();
    SafetyManifest manifest = LoadSafetyManifest();
    PermissionDecision permissionDecision = EvaluatePermissionRequest(manifest, title, process, action, permissionMode, fullAccessSessionId);
    if (!permissionDecision.allow) {
        return EmitFailure(command, startTick, NoTraceTarget(), permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode, permissionDecision.reason, PermissionDecisionJson(permissionDecision), 1);
    }
    PolicyCheckDecision decision = EvaluatePolicyCheck(
        policy,
        manifest,
        title,
        process,
        action,
        path,
        permissionDecision.relaxConfiguredBoundary,
        PermissionModeName(permissionMode),
        fullAccessSessionId,
        permissionDecision.fullAccessSessionActive,
        permissionDecision.fullAccessSessionExpired,
        permissionDecision.fullAccessScope);
    std::wstringstream data;
    data << L"{\"allow\":" << (decision.allow ? L"true" : L"false")
         << L",\"permission_mode\":" << JsonString(PermissionModeName(permissionMode))
         << L",\"reason\":" << JsonString(decision.reason)
         << L",\"matched_rule\":" << JsonString(decision.matchedRule)
         << L",\"matched_category\":" << JsonString(decision.matchedCategory)
         << L",\"title\":" << JsonString(title)
         << L",\"process\":" << JsonString(process)
         << L",\"action\":" << JsonString(action)
         << L",\"path\":" << JsonString(path)
         << L",\"full_access_session_id\":" << JsonString(fullAccessSessionId)
         << L",\"full_access_session_active\":" << (permissionDecision.fullAccessSessionActive ? L"true" : L"false")
         << L",\"full_access_session_expired\":" << (permissionDecision.fullAccessSessionExpired ? L"true" : L"false")
         << L",\"permission_decision\":" << PermissionDecisionJson(permissionDecision)
         << L",\"manifest_loaded\":" << (manifest.loaded ? L"true" : L"false") << L"}";
    if (!decision.allow) {
        return EmitFailure(command, startTick, NoTraceTarget(), decision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : decision.errorCode, decision.reason, data.str(), 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data.str());
}

int CommandConsentCheck(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"consent-check";
    std::wstring title;
    if (!ArgValue(argc, argv, L"--title", title) || title.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"consent-check requires --title.", L"{}", 2);
    }
    SafetyManifest manifest = LoadSafetyManifest();
    std::wstringstream requirements;
    requirements << L"{\"requires_explicit_target\":" << (manifest.requiresExplicitTarget ? L"true" : L"false")
                 << L",\"requires_visible_foreground_window\":" << (manifest.requiresVisibleForegroundWindow ? L"true" : L"false")
                 << L",\"allow_background_control\":" << (manifest.allowBackgroundControl ? L"true" : L"false")
                 << L",\"allow_unrestricted_desktop\":" << (manifest.allowUnrestrictedDesktop ? L"true" : L"false") << L"}";

    std::vector<WindowInfo> matches = FindWindowsByTitleSubstring(title);
    if (matches.empty()) {
        std::wstring data = L"{\"requested_title\":" + JsonString(title) + L",\"consent_requirements\":" + requirements.str() + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_FOUND", L"Target window was not found.", data, 1);
    }
    if (matches.size() > 1) {
        std::wstring data = L"{\"requested_title\":" + JsonString(title) + L",\"consent_requirements\":" + requirements.str() + L",\"candidate_count\":" + std::to_wstring(matches.size()) + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"WINDOW_NOT_UNIQUE", L"Target window title matched multiple windows.", data, 1);
    }

    WindowInfo selected = matches.front();
    std::wstring processName = ProcessNameForPid(selected.pid);
    std::wstring matchedRule;
    std::wstring matchedCategory;
    if (IsDeniedBySafetyManifest(manifest, selected.title, processName, matchedRule, matchedCategory)) {
        std::wstring data = L"{\"requested_title\":" + JsonString(title)
            + L",\"actual_title\":" + JsonString(selected.title)
            + L",\"process_name\":" + JsonString(processName)
            + L",\"consent_requirements\":" + requirements.str()
            + L",\"matched_rule\":" + JsonString(matchedRule)
            + L",\"matched_category\":" + JsonString(matchedCategory)
            + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"SAFETY_POLICY_DENIED", L"Target matches a denied safety manifest category.", data, 1);
    }

    HWND foreground = GetForegroundWindow();
    bool isForeground = foreground == selected.hwnd;
    bool visible = IsWindowVisible(selected.hwnd) != FALSE;
    std::wstringstream data;
    data << L"{\"requested_title\":" << JsonString(title)
         << L",\"actual_title\":" << JsonString(selected.title)
         << L",\"process_name\":" << JsonString(processName)
         << L",\"visible\":" << (visible ? L"true" : L"false")
         << L",\"is_foreground\":" << (isForeground ? L"true" : L"false")
         << L",\"foreground_control_policy\":\"focus_required_before_input\""
         << L",\"consent_requirements\":" << requirements.str()
         << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data.str());
}

int CommandFind(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"find";
    std::wstring title;
    if (!ArgValue(argc, argv, L"--title", title)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"find requires --title.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    std::wstringstream data;
    data << L"{\"requested_title\":" << JsonString(title)
         << L",\"rect\":" << WindowRectJson(selected) << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data.str());
}

int CommandScreenshot(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"screenshot";
    std::wstring title;
    std::wstring hwndArg;
    std::wstring process;
    std::wstring outputPath;
    std::wstring format;
    bool includeMetadata = false;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--format", format);
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--include-metadata", includeMetadata, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (!ArgValue(argc, argv, L"--out", outputPath)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"screenshot requires --out.", WithSuggestedCommand(L"{}", L"screenshot --title <partial_title> --out <file>"), 2);
    }

    if (title.empty() && hwndArg.empty() && process.empty()) {
        ForegroundPreemptResult preempt = prepare_before_first_observation(nullptr, false);
        if (!preempt.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), preempt.errorCode.empty() ? L"FAIL_FOREGROUND_PREEMPT_NOT_RUN_BEFORE_OBSERVATION" : preempt.errorCode, preempt.errorMessage, L"{\"out\":" + JsonString(outputPath) + L",\"foreground_preempt\":" + ForegroundPreemptJson(preempt) + L"}", 1);
        }
        GlobalDpiAwareFrameResult global = capture_full_desktop_dpi_aware(outputPath, format, includeMetadata);
        std::wstring data = GlobalDpiAwareFrameDataJson(global);
        data = MergeObjectField(data, L"foreground_preempt", ForegroundPreemptJson(preempt));
        data = data.substr(0, data.size() - 1) + L",\"defaulted_to_global_screenshot\":true}";
        if (!global.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), global.errorCode.empty() ? L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE" : global.errorCode, global.errorMessage, data, 1);
        }
        return EmitSuccess(command, startTick, NoTraceTarget(), data);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    ForegroundPreparationResult prep;
    if (!ResolveWindowByTitleHwndProcess(title, hwndArg, process, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    if (!prep.attempted) {
        prep = PrepareForegroundForVisibleUiTask(selected);
    }
    if (!prep.ok) {
        std::wstring failure = L"{\"out\":" + JsonString(outputPath)
            + L",\"capture_scope\":\"window_only\",\"can_be_final_evidence\":false"
            + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, failure, 1);
    }

    ScreenshotResult result = CaptureWindowToBmp(selected.hwnd, outputPath);
    if (!result.ok) {
        std::wstring data = L"{\"out\":" + JsonString(outputPath)
            + L",\"capture_scope\":\"window_only\",\"can_be_final_evidence\":false"
            + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"SCREENSHOT_FAILED", result.error, data, 1);
    }

    std::wstringstream fields;
    fields << L"{\"out\":" << JsonString(outputPath)
           << L",\"method\":" << JsonString(result.method)
           << L",\"capture_scope\":\"window_only\""
           << L",\"can_be_final_evidence\":false"
           << L",\"failure_code_if_used_as_final_evidence\":\"FAIL_WINDOW_SCREENSHOT_USED_AS_FINAL_EVIDENCE\""
           << L",\"foreground_preparation\":" << ForegroundPreparationJson(prep)
           << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), fields.str());
}

TargetWindowLockOptions ParseTargetWindowLockOptionsFromArgs(int argc, wchar_t** argv) {
    TargetWindowLockOptions options;
    ArgValue(argc, argv, L"--target-title", options.targetTitle);
    ArgValue(argc, argv, L"--target-hwnd", options.targetHwnd);
    ArgValue(argc, argv, L"--target-process", options.targetProcess);
    std::wstring error;
    ParseOptionalBoolArg(argc, argv, L"--require-target-lock", options.requireTargetLock, error);
    ParseOptionalBoolArg(argc, argv, L"--allow-global-desktop", options.allowGlobalDesktop, error);
    ParseOptionalBoolArg(argc, argv, L"--allow-dry-run-target", options.allowDryRunTarget, error);
    return options;
}

int CommandGlobalScreenshot(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"global-screenshot";
    std::wstring outputPath;
    std::wstring format;
    bool includeMetadata = false;
    bool cacheSelftest = false;
    ArgValue(argc, argv, L"--format", format);
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--include-metadata", includeMetadata, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--cache-selftest", cacheSelftest, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (!ArgValue(argc, argv, L"--out", outputPath) || outputPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"global-screenshot requires --out.", L"{}", 2);
    }
    if (cacheSelftest) {
        ForegroundPreemptResult preempt = prepare_before_first_observation(nullptr, false);
        if (!preempt.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), preempt.errorCode.empty() ? L"FAIL_FOREGROUND_PREEMPT_NOT_RUN_BEFORE_OBSERVATION" : preempt.errorCode, preempt.errorMessage, L"{\"foreground_preempt\":" + ForegroundPreemptJson(preempt) + L"}", 1);
        }
        GlobalFrameCache cache;
        GlobalDpiAwareFrameResult first = capture_full_desktop_dpi_aware_cached(cache, outputPath, format, includeMetadata, false, false);
        GlobalDpiAwareFrameResult second = capture_full_desktop_dpi_aware_cached(cache, outputPath, format, includeMetadata, false, false);
        invalidate_global_frame_cache_by_action(cache);
        GlobalDpiAwareFrameResult afterAction = capture_full_desktop_dpi_aware_cached(cache, outputPath, format, includeMetadata, false, false);
        GlobalDpiAwareFrameResult finalFrame = capture_full_desktop_dpi_aware_cached(cache, outputPath, format, includeMetadata, true, true);
        std::vector<GlobalDpiAwareFrameResult> frames = {first, second, afterAction, finalFrame};
        int newCount = 0;
        int hitCount = 0;
        long long captureTotal = 0;
        for (const auto& frame : frames) {
            if (frame.frameCacheHit) {
                ++hitCount;
            } else {
                ++newCount;
                captureTotal += frame.durationMs;
            }
        }
        std::wstring framesJson = L"[";
        for (size_t i = 0; i < frames.size(); ++i) {
            if (i) framesJson += L",";
            framesJson += GlobalDpiAwareFrameDataJson(frames[i]);
        }
        framesJson += L"]";
        bool ok = first.ok && second.ok && afterAction.ok && finalFrame.ok && hitCount >= 1 && finalFrame.newGlobalFrameForFinalVerification;
        std::wstring data = L"{\"cache_enabled\":true"
            L",\"new_frame_count\":" + std::to_wstring(newCount) +
            L",\"cache_hit_count\":" + std::to_wstring(hitCount) +
            L",\"average_capture_duration_ms\":" + std::to_wstring(newCount > 0 ? captureTotal / newCount : 0) +
            L",\"frames\":" + framesJson +
            L",\"foreground_preempt\":" + ForegroundPreemptJson(preempt) + L"}";
        if (!ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"FAIL_GLOBAL_FRAME_CACHE_SELFTEST", L"Global frame cache selftest failed.", data, 1);
        }
        return EmitSuccess(command, startTick, NoTraceTarget(), data);
    }
    ForegroundPreemptResult preempt = prepare_before_first_observation(nullptr, false);
    if (!preempt.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), preempt.errorCode.empty() ? L"FAIL_FOREGROUND_PREEMPT_NOT_RUN_BEFORE_OBSERVATION" : preempt.errorCode, preempt.errorMessage, L"{\"out\":" + JsonString(outputPath) + L",\"foreground_preempt\":" + ForegroundPreemptJson(preempt) + L"}", 1);
    }
    GlobalDpiAwareFrameResult result = capture_full_desktop_dpi_aware(outputPath, format, includeMetadata);
    std::wstring data = GlobalDpiAwareFrameDataJson(result);
    data = MergeObjectField(data, L"foreground_preempt", ForegroundPreemptJson(preempt));
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_GLOBAL_SCREENSHOT_INCOMPLETE" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandTargetLockAcquire(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"target-lock-acquire";
    TargetWindowLockOptions options = ParseTargetWindowLockOptionsFromArgs(argc, argv);
    bool cacheSelftest = false;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--cache-selftest", cacheSelftest, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (cacheSelftest) {
        TargetWindowLockCache cache;
        TargetWindowLockResult first = acquire_target_window_lock_cached(cache, options);
        TargetWindowLockResult second = acquire_target_window_lock_cached(cache, options);
        TargetWindowLockResult third = acquire_target_window_lock_cached(cache, options);
        std::vector<TargetWindowLockResult> results = {first, second, third};
        int acquireCount = 0;
        int hitCount = 0;
        int reacquireCount = 0;
        std::wstring resultsJson = L"[";
        for (size_t i = 0; i < results.size(); ++i) {
            if (i) resultsJson += L",";
            resultsJson += TargetWindowLockJson(results[i]);
            if (results[i].targetLockMode == L"acquire") ++acquireCount;
            if (results[i].targetLockMode == L"cached_validate") ++hitCount;
            if (results[i].targetLockMode == L"reacquire") ++reacquireCount;
        }
        resultsJson += L"]";
        bool ok = first.ok && second.ok && third.ok && acquireCount == 1 && hitCount >= 1;
        std::wstring data = L"{\"cache_enabled\":true"
            L",\"acquire_count\":" + std::to_wstring(acquireCount) +
            L",\"cache_hit_count\":" + std::to_wstring(hitCount) +
            L",\"reacquire_count\":" + std::to_wstring(reacquireCount) +
            L",\"results\":" + resultsJson + L"}";
        if (!ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"FAIL_TARGET_LOCK_CACHE_SELFTEST", L"Target lock cache selftest failed.", data, 1);
        }
        return EmitSuccess(command, startTick, NoTraceTarget(), data);
    }
    TargetWindowLockResult result = acquire_target_window_lock(options);
    std::wstring data = TargetWindowLockJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_TARGET_LOCK_REQUIRED" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandTargetLockRelease(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"target-lock-release";
    TargetWindowLockOptions options = ParseTargetWindowLockOptionsFromArgs(argc, argv);
    options.allowGlobalDesktop = true;
    TargetWindowLockResult acquired = acquire_target_window_lock(options);
    TargetWindowLockResult released = release_target_window_lock(acquired);
    return EmitSuccess(command, startTick, NoTraceTarget(), TargetWindowLockJson(released));
}

int CommandCoordinateMap(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"coordinate-map";
    ScreenshotCoordinateMappingInput input;
    int captureLeft = 0;
    int captureTop = 0;
    int captureWidth = 0;
    int captureHeight = 0;
    int targetLeft = 0;
    int targetTop = 0;
    int targetRight = 0;
    int targetBottom = 0;
    ArgValue(argc, argv, L"--direction", input.direction);
    ArgValue(argc, argv, L"--capture-scope", input.captureScope);
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--capture-left", captureLeft, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--capture-top", captureTop, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--capture-width", captureWidth, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--capture-height", captureHeight, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--pixel-x", input.pixelX, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--pixel-y", input.pixelY, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--screen-x", input.screenX, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--screen-y", input.screenY, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    input.captureRect.left = captureLeft;
    input.captureRect.top = captureTop;
    input.captureRect.right = input.captureRect.left + captureWidth;
    input.captureRect.bottom = input.captureRect.top + captureHeight;
    input.capturePhysicalWidth = captureWidth;
    input.capturePhysicalHeight = captureHeight;
    input.hasTargetRect = ArgExists(argc, argv, L"--target-left") || ArgExists(argc, argv, L"--target-top") || ArgExists(argc, argv, L"--target-right") || ArgExists(argc, argv, L"--target-bottom");
    if (input.hasTargetRect &&
        (!ParseOptionalIntArg(argc, argv, L"--target-left", targetLeft, parseError) ||
         !ParseOptionalIntArg(argc, argv, L"--target-top", targetTop, parseError) ||
         !ParseOptionalIntArg(argc, argv, L"--target-right", targetRight, parseError) ||
         !ParseOptionalIntArg(argc, argv, L"--target-bottom", targetBottom, parseError))) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    input.targetRect.left = targetLeft;
    input.targetRect.top = targetTop;
    input.targetRect.right = targetRight;
    input.targetRect.bottom = targetBottom;
    ScreenshotCoordinateMappingResult result = MapScreenshotCoordinate(input);
    std::wstring data = ScreenshotCoordinateMappingJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_UNSAFE_COORDINATE_SOURCE" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandForegroundPreempt(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"foreground-preempt";
    bool dryRun = false;
    bool cacheSelftest = false;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--dry-run", dryRun, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--cache-selftest", cacheSelftest, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (cacheSelftest) {
        ForegroundPreemptCache cache;
        ForegroundPreemptResult first = prepare_before_first_observation_cached(cache, nullptr, dryRun);
        ForegroundPreemptResult second = prepare_before_each_action_cached(cache, nullptr, dryRun);
        ForegroundPreemptResult third = prepare_before_each_action_cached(cache, nullptr, dryRun);
        std::vector<ForegroundPreemptResult> results = {first, second, third};
        int fullCount = 0;
        int cachedCount = 0;
        int skippedCount = 0;
        std::wstring resultsJson = L"[";
        for (size_t i = 0; i < results.size(); ++i) {
            if (i) resultsJson += L",";
            resultsJson += ForegroundPreemptJson(results[i]);
            if (results[i].foregroundPreemptMode == L"full") ++fullCount;
            if (results[i].foregroundPreemptMode == L"cached_validation") ++cachedCount;
            if (results[i].foregroundPreemptMode == L"skipped_safe") ++skippedCount;
        }
        resultsJson += L"]";
        bool ok = first.ok && second.ok && third.ok && fullCount == 1 && cachedCount >= 1;
        std::wstring data = L"{\"cache_enabled\":true"
            L",\"full_preempt_count\":" + std::to_wstring(fullCount) +
            L",\"cached_validation_count\":" + std::to_wstring(cachedCount) +
            L",\"skipped_safe_count\":" + std::to_wstring(skippedCount) +
            L",\"results\":" + resultsJson + L"}";
        if (!ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"FAIL_FOREGROUND_PREEMPT_CACHE_SELFTEST", L"Foreground preempt cache selftest failed.", data, 1);
        }
        return EmitSuccess(command, startTick, NoTraceTarget(), data);
    }
    ForegroundPreemptResult result = prepare_before_first_observation(nullptr, dryRun);
    std::wstring data = ForegroundPreemptJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"BLOCKED_AGENT_HOST_OBSTRUCTING_TARGET" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandVisibleTextInput(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-text-input";
    VisibleTextInputOptions options;
    ArgValue(argc, argv, L"--text", options.text);
    ArgValue(argc, argv, L"--input-kind", options.inputKind);
    ArgValue(argc, argv, L"--input-method", options.inputMethod);
    ArgValue(argc, argv, L"--typing-profile", options.typingProfile);
    ArgValue(argc, argv, L"--indent-mode", options.indentMode);
    ArgValue(argc, argv, L"--target-title", options.targetTitle);
    ArgValue(argc, argv, L"--target-hwnd", options.targetHwnd);
    ArgValue(argc, argv, L"--target-process", options.targetProcess);
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--require-target-lock", options.requireTargetLock, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--allow-global-desktop", options.allowGlobalDesktop, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--dry-run", options.dryRun, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--allow-dry-run-target", options.allowDryRunTarget, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--allow-clipboard", options.allowClipboard, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--backend-file-write-used", options.backendFileWriteUsed, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--visible-mouse-keyboard-attempted", options.visibleMouseKeyboardAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--keyboard-shortcut-attempted", options.keyboardShortcutAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--explicit-backend-request", options.explicitBackendRequested, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--max-attempts-exceeded", options.maxAttemptsExceeded, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--pre-action-checkpoint-present", options.preActionCheckpointPresent, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--bounded-recovery-attempted", options.boundedRecoveryAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--post-recovery-observed", options.postRecoveryObserved, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--same-surface-after-recovery", options.sameSurfaceAfterRecovery, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--surface-impossible", options.surfaceImpossible, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--surface-impossible-evidence-present", options.surfaceImpossibleEvidencePresent, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--visible-attempt-count", options.visibleAttemptCount, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--min-visible-attempts-before-shortcut", options.minVisibleAttemptsBeforeShortcut, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--char-delay-ms", options.charDelayMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--line-delay-ms", options.lineDelayMs, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--batch-key-events", options.batchKeyEvents, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--structured", options.structured, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--indent-width", options.indentWidth, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--verify-structure", options.verifyStructure, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--submit-enter", options.submitEnter, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--verifier-run-succeeded", options.verifierRunSucceeded, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    ArgValue(argc, argv, L"--clipboard-fallback-reason", options.clipboardFallbackReason);
    ArgValue(argc, argv, L"--visible-attempt-result", options.visibleAttemptResult);
    if (options.visibleAttemptResult.empty()) ArgValue(argc, argv, L"--attempt-1-result", options.visibleAttemptResult);
    ArgValue(argc, argv, L"--visible-failure-reason", options.visibleFailureReason);
    if (options.visibleFailureReason.empty()) ArgValue(argc, argv, L"--attempt-1-failure-reason", options.visibleFailureReason);
    ArgValue(argc, argv, L"--keyboard-shortcut-result", options.keyboardShortcutResult);
    if (options.keyboardShortcutResult.empty()) ArgValue(argc, argv, L"--attempt-2-result", options.keyboardShortcutResult);
    ArgValue(argc, argv, L"--keyboard-shortcut-failure-reason", options.keyboardShortcutFailureReason);
    if (options.keyboardShortcutFailureReason.empty()) ArgValue(argc, argv, L"--attempt-2-failure-reason", options.keyboardShortcutFailureReason);
    ArgValue(argc, argv, L"--surface-impossible-reason", options.surfaceImpossibleReason);
    VisibleTextInputResult result = ApplyVisibleTextInputPolicy(options);
    std::wstring data = VisibleTextInputJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_TEXT_INPUT_NOT_VERIFIED" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandVlmRuntimeCandidate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-runtime-candidate";
    VLMRuntimeBridgeOptions options;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--global-frame", options.globalScreenshot, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--observation-request", options.observationRequest, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--observation-result", options.observationResult, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--candidate-target", options.candidateTarget, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--runtime-validator", options.runtimeCandidateValidator, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--coordinate-mapper", options.coordinateMapper, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--target-lock", options.targetWindowLock, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--action", options.action, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--verification", options.verification, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--visual-manual-inspection", options.visualManualInspection, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    VLMRuntimeBridgeResult result = record_vlm_assisted_evidence(options);
    std::wstring data = VLMRuntimeBridgeJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_VLM_CANDIDATE_NOT_RUNTIME_VALIDATED" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandVisibleActionBatch(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-action-batch";
    std::wstring planPath;
    std::wstring outPath;
    if (!ArgValue(argc, argv, L"--plan", planPath) || planPath.empty() || !ArgValue(argc, argv, L"--out", outPath) || outPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"visible-action-batch requires --plan and --out.", L"{}", 2);
    }
    FileReadResult plan = ReadTextFile(planPath);
    if (!plan.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), plan.errorCode.empty() ? L"FILE_READ_FAILED" : plan.errorCode, plan.error, L"{\"plan\":" + JsonString(planPath) + L"}", 1);
    }
    DeterministicActionBatchOptions options;
    options.planJson = plan.content;
    DeterministicActionBatchResult result = ExecuteDeterministicActionBatch(options);
    std::wstring data = DeterministicActionBatchJson(result);
    WriteSmallTextFile(outPath, data);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_BATCH_VERIFICATION_FAILED" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandVisibleUiVerify(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-ui-verify";
    VisibleUIVerificationOptions options;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--global-final-frame", options.finalEvidenceGlobal, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--window-only", options.windowOnlyEvidence, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--expected-output-visible", options.expectedOutputVisible, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--target-lock", options.targetWindowLocked, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--allow-global-desktop", options.allowGlobalDesktop, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--raw-completed", options.rawCompleted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--backend-fallback-used", options.backendFallbackUsed, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--visible-mouse-keyboard-attempted", options.visibleMouseKeyboardAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--keyboard-shortcut-attempted", options.keyboardShortcutAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--explicit-backend-request", options.explicitBackendRequested, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--max-attempts-exceeded", options.maxAttemptsExceeded, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--pre-action-checkpoint-present", options.preActionCheckpointPresent, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--bounded-recovery-attempted", options.boundedRecoveryAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--post-recovery-observed", options.postRecoveryObserved, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--same-surface-after-recovery", options.sameSurfaceAfterRecovery, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--surface-impossible", options.surfaceImpossible, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--surface-impossible-evidence-present", options.surfaceImpossibleEvidencePresent, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-assist-enabled", options.vlmAssistEnabled, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-assist-attempted", options.vlmAssistAttempted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-candidate-accepted", options.vlmCandidateAccepted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-action-executed", options.vlmActionExecuted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--vlm-after-backend-attempted", options.vlmAfterBackendAttempted, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--visible-attempt-count", options.visibleAttemptCount, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--min-visible-attempts-before-shortcut", options.minVisibleAttemptsBeforeShortcut, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    ArgValue(argc, argv, L"--backend-fallback-reason", options.backendFallbackReason);
    ArgValue(argc, argv, L"--operation-type", options.operationType);
    ArgValue(argc, argv, L"--final-mode-used", options.finalModeUsed);
    ArgValue(argc, argv, L"--visible-attempt-result", options.visibleAttemptResult);
    if (options.visibleAttemptResult.empty()) ArgValue(argc, argv, L"--attempt-1-result", options.visibleAttemptResult);
    ArgValue(argc, argv, L"--visible-failure-reason", options.visibleFailureReason);
    if (options.visibleFailureReason.empty()) ArgValue(argc, argv, L"--attempt-1-failure-reason", options.visibleFailureReason);
    ArgValue(argc, argv, L"--keyboard-shortcut-result", options.keyboardShortcutResult);
    if (options.keyboardShortcutResult.empty()) ArgValue(argc, argv, L"--attempt-2-result", options.keyboardShortcutResult);
    ArgValue(argc, argv, L"--keyboard-shortcut-failure-reason", options.keyboardShortcutFailureReason);
    if (options.keyboardShortcutFailureReason.empty()) ArgValue(argc, argv, L"--attempt-2-failure-reason", options.keyboardShortcutFailureReason);
    ArgValue(argc, argv, L"--surface-impossible-reason", options.surfaceImpossibleReason);
    ArgValue(argc, argv, L"--vlm-capability-status", options.vlmCapabilityStatus);
    ArgValue(argc, argv, L"--vlm-session-id", options.vlmSessionId);
    ArgValue(argc, argv, L"--vlm-assist-trigger-reason", options.vlmAssistTriggerReason);
    ArgValue(argc, argv, L"--vlm-assist-stage", options.vlmAssistStage);
    ArgValue(argc, argv, L"--vlm-provider", options.vlmProvider);
    ArgValue(argc, argv, L"--vlm-raw-response-path", options.vlmRawResponsePath);
    ArgValue(argc, argv, L"--vlm-candidate-rejected-reason", options.vlmCandidateRejectedReason);
    ArgValue(argc, argv, L"--fallback-stage-before-vlm", options.fallbackStageBeforeVlm);
    ArgValue(argc, argv, L"--fallback-stage-after-vlm", options.fallbackStageAfterVlm);
    VisibleUIVerificationResult result = classify_final_result(options);
    std::wstring data = VisibleUIVerificationJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FAIL_FINAL_EVIDENCE_NOT_GLOBAL" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandVisibleOperationPolicyCheck(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-operation-policy-check";
    std::wstring operationType = L"visible_ui_operation";
    std::wstring finalMode = L"visible_mouse_keyboard";
    std::wstring backendKind;
    std::wstring parseError;
    bool backendUsed = false;
    ArgValue(argc, argv, L"--operation-type", operationType);
    ArgValue(argc, argv, L"--final-mode-used", finalMode);
    ArgValue(argc, argv, L"--backend-fallback-kind", backendKind);
    if (!ParseOptionalBoolArg(argc, argv, L"--backend-fallback-used", backendUsed, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    VisibleOperationPolicyOptions options = ParseVisibleOperationPriorityArgs(argc, argv, operationType, finalMode, backendUsed, backendKind, parseError);
    if (!parseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    VisibleOperationPolicyResult result = enforce_visible_operation_priority(options);
    std::wstring data = VisibleOperationPolicyJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

std::wstring VisiblePrimitiveOperationType(const std::wstring& command) {
    if (command == L"taskbar-icon-locate" || command == L"taskbar-icon-click" ||
        command == L"desktop-icon-locate" || command == L"desktop-icon-double-click" ||
        command == L"start-menu-visible-launch") {
        return L"app_launch";
    }
    if (command == L"visible-show-desktop") return L"show_desktop";
    if (command == L"visible-window-switch") return L"window_switch";
    if (command == L"visible-page-navigation") return L"page_navigation";
    return L"visible_ui_operation";
}

struct VisiblePrimitiveTarget {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring surface;
    HWND hwnd = nullptr;
    UiaElementInfo element;
};

bool RectHasArea(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

int RectCenterX(const RECT& rect) {
    return rect.left + ((rect.right - rect.left) / 2);
}

int RectCenterY(const RECT& rect) {
    return rect.top + ((rect.bottom - rect.top) / 2);
}

void AddUniqueHwnd(std::vector<HWND>& hwnds, HWND hwnd) {
    if (!hwnd) return;
    for (HWND existing : hwnds) {
        if (existing == hwnd) return;
    }
    hwnds.push_back(hwnd);
}

BOOL CALLBACK EnumDesktopWorkerWindows(HWND hwnd, LPARAM lparam) {
    auto* hwnds = reinterpret_cast<std::vector<HWND>*>(lparam);
    HWND defView = FindWindowExW(hwnd, nullptr, L"SHELLDLL_DefView", nullptr);
    if (defView) {
        AddUniqueHwnd(*hwnds, defView);
        HWND listView = FindWindowExW(defView, nullptr, L"SysListView32", nullptr);
        AddUniqueHwnd(*hwnds, listView);
        AddUniqueHwnd(*hwnds, hwnd);
    }
    return TRUE;
}

std::vector<HWND> DesktopIconSearchWindows() {
    std::vector<HWND> hwnds;
    HWND progman = FindWindowW(L"Progman", nullptr);
    HWND defView = progman ? FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr) : nullptr;
    HWND listView = defView ? FindWindowExW(defView, nullptr, L"SysListView32", nullptr) : nullptr;
    AddUniqueHwnd(hwnds, listView);
    AddUniqueHwnd(hwnds, defView);
    AddUniqueHwnd(hwnds, progman);
    EnumWindows(EnumDesktopWorkerWindows, reinterpret_cast<LPARAM>(&hwnds));
    AddUniqueHwnd(hwnds, GetDesktopWindow());
    return hwnds;
}

VisiblePrimitiveTarget LocateUiaTargetOnCandidates(
    const std::vector<HWND>& hwnds,
    const std::wstring& target,
    const std::wstring& surface) {
    VisiblePrimitiveTarget located;
    located.surface = surface;
    if (target.empty()) {
        located.errorCode = L"INVALID_ARGUMENT";
        located.errorMessage = L"Visible primitive locate requires --target.";
        return located;
    }
    std::wstring lastError;
    std::wstring lastCode = L"UIA_ELEMENT_NOT_FOUND";
    for (HWND hwnd : hwnds) {
        UiaQueryResult query = FindUiaElementsByName(hwnd, target);
        if (!query.ok) {
            lastCode = query.errorCode.empty() ? L"UIA_ELEMENT_NOT_FOUND" : query.errorCode;
            lastError = query.errorMessage;
            continue;
        }
        if (query.elements.empty() || !RectHasArea(query.elements.front().rect)) {
            lastCode = L"UIA_ELEMENT_RECT_INVALID";
            lastError = L"UI Automation target did not expose a usable bounding rectangle.";
            continue;
        }
        located.ok = true;
        located.hwnd = hwnd;
        located.element = query.elements.front();
        return located;
    }
    located.errorCode = lastCode;
    located.errorMessage = lastError.empty() ? L"No visible UI element matched the requested target." : lastError;
    return located;
}

VisiblePrimitiveTarget LocateTaskbarTarget(const std::wstring& target) {
    std::vector<HWND> hwnds;
    AddUniqueHwnd(hwnds, FindWindowW(L"Shell_TrayWnd", nullptr));
    AddUniqueHwnd(hwnds, FindWindowW(L"Shell_SecondaryTrayWnd", nullptr));
    return LocateUiaTargetOnCandidates(hwnds, target, L"taskbar");
}

VisiblePrimitiveTarget LocateTaskbarSearchEntry() {
    VisiblePrimitiveTarget located;
    located.surface = L"taskbar_search";

    std::vector<HWND> hwnds;
    AddUniqueHwnd(hwnds, FindWindowW(L"Shell_TrayWnd", nullptr));
    AddUniqueHwnd(hwnds, FindWindowW(L"Shell_SecondaryTrayWnd", nullptr));

    std::vector<std::wstring> names = {L"Search", L"搜索"};
    long long bestScore = -1;
    std::wstring lastCode = L"UIA_ELEMENT_NOT_FOUND";
    std::wstring lastError = L"No visible taskbar search entry matched.";

    for (HWND hwnd : hwnds) {
        for (const std::wstring& name : names) {
            UiaQueryResult query = FindUiaElementsByName(hwnd, name);
            if (query.elements.empty()) {
                if (!query.errorCode.empty()) {
                    lastCode = query.errorCode;
                    lastError = query.errorMessage;
                }
                continue;
            }

            for (const UiaElementInfo& element : query.elements) {
                if (!RectHasArea(element.rect) || element.offscreen || !element.enabled) {
                    continue;
                }
                long long width = static_cast<long long>(element.rect.right - element.rect.left);
                long long height = static_cast<long long>(element.rect.bottom - element.rect.top);
                long long area = width * height;
                long long score = area;
                std::wstring control = ToLowerInvariant(element.controlType);
                if (control.find(L"edit") != std::wstring::npos) score += 1000000000LL;
                if (control.find(L"button") != std::wstring::npos) score += 100000000LL;
                if (width > height * 2) score += 10000000LL;
                if (score > bestScore) {
                    bestScore = score;
                    located.ok = true;
                    located.hwnd = hwnd;
                    located.element = element;
                }
            }
        }
    }

    if (!located.ok) {
        located.errorCode = lastCode;
        located.errorMessage = lastError;
    }
    return located;
}

std::wstring StripExeSuffix(std::wstring process) {
    std::wstring lower = ToLowerInvariant(process);
    if (lower.size() > 4 && lower.substr(lower.size() - 4) == L".exe") {
        process.resize(process.size() - 4);
    }
    return process;
}

void AddFriendlyTaskbarNames(const std::wstring& process, std::vector<std::wstring>& candidates) {
    std::wstring stripped = ToLowerInvariant(StripExeSuffix(process));
    if (stripped == L"powershell" || stripped == L"pwsh") {
        candidates.push_back(L"Windows PowerShell");
        candidates.push_back(L"PowerShell");
    } else if (stripped == L"chrome") {
        candidates.push_back(L"Google Chrome");
    } else if (stripped == L"msedge") {
        candidates.push_back(L"Microsoft Edge");
    } else if (stripped == L"explorer") {
        candidates.push_back(L"File Explorer");
        candidates.push_back(L"文件资源管理器");
    } else if (stripped == L"cmd") {
        candidates.push_back(L"Command Prompt");
    }
}

VisiblePrimitiveTarget LocateWindowSwitchTaskbarTarget(const std::wstring& targetTitle, const std::wstring& targetProcess, const WindowInfo& targetWindow) {
    std::vector<std::wstring> candidates;
    if (!targetTitle.empty()) candidates.push_back(targetTitle);
    if (!targetWindow.title.empty()) candidates.push_back(targetWindow.title);
    if (!targetProcess.empty()) {
        candidates.push_back(targetProcess);
        std::wstring stripped = StripExeSuffix(targetProcess);
        if (stripped != targetProcess) candidates.push_back(stripped);
        AddFriendlyTaskbarNames(targetProcess, candidates);
    }
    std::wstring processName = targetWindow.pid ? ProcessNameForPid(targetWindow.pid) : L"";
    if (!processName.empty()) {
        candidates.push_back(processName);
        std::wstring stripped = StripExeSuffix(processName);
        if (stripped != processName) candidates.push_back(stripped);
        AddFriendlyTaskbarNames(processName, candidates);
    }

    VisiblePrimitiveTarget last;
    for (const auto& candidate : candidates) {
        if (candidate.empty()) continue;
        last = LocateTaskbarTarget(candidate);
        if (last.ok) return last;
    }
    if (last.errorCode.empty()) {
        last.errorCode = L"VISIBLE_TASKBAR_TARGET_NOT_FOUND";
        last.errorMessage = L"No taskbar target matched the requested window.";
        last.surface = L"taskbar";
    }
    return last;
}

VisiblePrimitiveTarget LocateDesktopTarget(const std::wstring& target) {
    return LocateUiaTargetOnCandidates(DesktopIconSearchWindows(), target, L"desktop");
}

std::wstring VisiblePrimitiveTargetJson(const VisiblePrimitiveTarget& target) {
    return L"{\"ok\":" + std::wstring(target.ok ? L"true" : L"false")
        + L",\"surface\":" + JsonString(target.surface)
        + L",\"hwnd\":" + HwndJson(target.hwnd)
        + L",\"error_code\":" + JsonString(target.errorCode)
        + L",\"error_message\":" + JsonString(target.errorMessage)
        + L",\"element\":" + UiaElementJson(target.element)
        + L"}";
}

VisibleOperationPolicyResult VisiblePrimitivePolicyResult(
    const std::wstring& command,
    bool visibleAttempted,
    const std::wstring& visibleResult,
    const std::wstring& visibleFailureReason,
    bool shortcutAttempted,
    const std::wstring& shortcutResult,
    const std::wstring& shortcutFailureReason,
    const std::wstring& finalMode) {
    VisibleOperationPolicyOptions priority;
    priority.operationType = VisiblePrimitiveOperationType(command);
    priority.finalModeUsed = finalMode;
    priority.visibleMouseKeyboardAttempted = visibleAttempted;
    priority.attempt1Result = visibleResult;
    priority.attempt1FailureReason = visibleFailureReason;
    priority.visibleAttemptCount = visibleAttempted ? 1 : 0;
    priority.preActionCheckpointPresent = visibleAttempted;
    if (shortcutAttempted) {
        priority.visibleAttemptCount = 2;
        priority.boundedRecoveryAttempted = true;
        priority.postRecoveryObserved = true;
        priority.sameSurfaceAfterRecovery = true;
    }
    priority.keyboardShortcutAttempted = shortcutAttempted;
    priority.attempt2Result = shortcutResult;
    priority.attempt2FailureReason = shortcutFailureReason;
    return enforce_visible_operation_priority(priority);
}

int EmitVisiblePrimitiveExecution(
    const std::wstring& command,
    ULONGLONG startTick,
    const std::wstring& target,
    const std::wstring& title,
    const std::wstring& app,
    const std::wstring& url,
    bool dryRun,
    const VisibleOperationPolicyResult& policy,
    const std::wstring& extraFields) {
    std::wstring data = std::wstring(L"{\"runtime_visible_first_primitive\":true")
        + L",\"command\":" + JsonString(command)
        + L",\"target\":" + JsonString(target)
        + L",\"title\":" + JsonString(title)
        + L",\"app\":" + JsonString(app)
        + L",\"url\":" + JsonString(url)
        + L",\"dry_run\":" + std::wstring(dryRun ? L"true" : L"false")
        + L",\"visible_mouse_keyboard_path\":true"
        + L",\"keyboard_shortcut_fallback\":" + std::wstring(policy.finalModeUsed == L"keyboard_shortcut_fallback" ? L"true" : L"false")
        + L",\"backend_fallback_used\":false"
        + L",\"requires_real_visible_input_command_for_execution\":false"
        + L",\"operation_priority\":" + VisibleOperationPolicyJson(policy);
    if (!extraFields.empty()) {
        data += L"," + extraFields;
    }
    data += L"}";
    if (!policy.ok) {
        return EmitVisibleOperationPriorityFailure(command, startTick, NoTraceTarget(), policy, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

std::wstring ActionResultJson(const ActionResult& result) {
    return L"{\"ok\":" + std::wstring(result.ok ? L"true" : L"false")
        + L",\"error_code\":" + JsonString(result.errorCode)
        + L",\"error\":" + JsonString(result.error)
        + L",\"foreground_before\":" + HwndJson(result.foregroundBefore)
        + L",\"foreground_after\":" + HwndJson(result.foregroundAfter)
        + L",\"focus_verified\":" + std::wstring(result.focusVerified ? L"true" : L"false")
        + L",\"text_length\":" + std::to_wstring(result.textLength)
        + L",\"pasted\":" + std::wstring(result.pasted ? L"true" : L"false")
        + L",\"keys\":" + JsonString(result.keys)
        + L"}";
}

std::wstring TypeResultJson(const TypeResult& result) {
    return L"{\"ok\":" + std::wstring(result.ok ? L"true" : L"false")
        + L",\"error_code\":" + JsonString(result.errorCode)
        + L",\"error\":" + JsonString(result.error)
        + L",\"foreground_before\":" + HwndJson(result.foregroundBefore)
        + L",\"foreground_after\":" + HwndJson(result.foregroundAfter)
        + L",\"focus_verified\":" + std::wstring(result.focusVerified ? L"true" : L"false")
        + L",\"type_mode\":" + JsonString(result.typeMode)
        + L",\"text_length\":" + std::to_wstring(result.textLength)
        + L"}";
}

bool IsNavigationKeyword(const std::wstring& value, const std::wstring& keyword) {
    return ToLowerInvariant(value) == ToLowerInvariant(keyword);
}

std::wstring WindowClassName(HWND hwnd) {
    wchar_t buffer[256] = {};
    if (!hwnd || GetClassNameW(hwnd, buffer, 256) <= 0) return L"";
    return buffer;
}

bool IsShellDesktopClass(const std::wstring& className) {
    return className == L"Progman" || className == L"WorkerW" || className == L"SHELLDLL_DefView" || className == L"SysListView32";
}

bool IsDesktopForeground(HWND hwnd) {
    if (!hwnd) return false;
    HWND shell = GetShellWindow();
    if (hwnd == shell) return true;
    std::wstring className = WindowClassName(hwnd);
    if (IsShellDesktopClass(className)) return true;
    int length = GetWindowTextLengthW(hwnd);
    std::wstring title;
    if (length > 0) {
        title.resize(static_cast<size_t>(length) + 1);
        int copied = GetWindowTextW(hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    }
    return title == L"Program Manager";
}

bool IsShellOrTaskbarWindow(HWND hwnd) {
    std::wstring className = WindowClassName(hwnd);
    return IsShellDesktopClass(className) || className == L"Shell_TrayWnd" || className == L"Shell_SecondaryTrayWnd";
}

std::wstring WindowTitleForHwnd(HWND hwnd) {
    int length = GetWindowTextLengthW(hwnd);
    if (length <= 0) return L"";
    std::wstring title(static_cast<size_t>(length) + 1, L'\0');
    int copied = GetWindowTextW(hwnd, title.data(), length + 1);
    title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    return title;
}

bool HasVisibleText(const std::wstring& value) {
    for (wchar_t ch : value) {
        if (!iswspace(ch)) return true;
    }
    return false;
}

BOOL CALLBACK EnumWindowSwitchCandidatesCallback(HWND hwnd, LPARAM lparam) {
    auto* windows = reinterpret_cast<std::vector<WindowInfo>*>(lparam);
    if (!IsWindowVisible(hwnd) || IsShellOrTaskbarWindow(hwnd)) return TRUE;
    LONG_PTR exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if ((exStyle & WS_EX_TOOLWINDOW) != 0 && (exStyle & WS_EX_APPWINDOW) == 0) return TRUE;
    if (GetWindow(hwnd, GW_OWNER) != nullptr && (exStyle & WS_EX_APPWINDOW) == 0) return TRUE;
    std::wstring title = WindowTitleForHwnd(hwnd);
    if (!HasVisibleText(title)) return TRUE;
    WindowInfo info;
    info.hwnd = hwnd;
    info.title = title;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    windows->push_back(info);
    return TRUE;
}

bool WindowMatchesTarget(const WindowInfo& window, const std::wstring& title, const std::wstring& process) {
    bool titleMatches = title.empty() || ContainsInsensitive(window.title, title);
    bool processMatches = process.empty() || ProcessMatchesOptional(window, process);
    return titleMatches && processMatches;
}

std::vector<WindowInfo> EnumerateWindowSwitchCandidates() {
    std::vector<WindowInfo> windows;
    EnumWindows(EnumWindowSwitchCandidatesCallback, reinterpret_cast<LPARAM>(&windows));
    return windows;
}

std::vector<WindowInfo> FindWindowSwitchCandidates(const std::wstring& title, const std::wstring& process) {
    std::vector<WindowInfo> matches;
    for (const auto& window : EnumerateWindowSwitchCandidates()) {
        if (WindowMatchesTarget(window, title, process)) {
            matches.push_back(window);
        }
    }
    return matches;
}

bool IsDesktopStateVisible() {
    HWND foreground = GetForegroundWindow();
    if (IsDesktopForeground(foreground)) return true;
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        if (!window.hwnd || IsShellOrTaskbarWindow(window.hwnd) || IsIconic(window.hwnd)) continue;
        return false;
    }
    return true;
}

RECT LocateBottomRightShowDesktopHotArea(const RECT& virtualRect) {
    RECT taskbar = {};
    HWND taskbarHwnd = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (taskbarHwnd && GetWindowRect(taskbarHwnd, &taskbar) && taskbar.right > taskbar.left && taskbar.bottom > taskbar.top) {
        return RECT{taskbar.right - 12, taskbar.bottom - 12, taskbar.right - 1, taskbar.bottom - 1};
    }
    return RECT{virtualRect.right - 12, virtualRect.bottom - 12, virtualRect.right - 1, virtualRect.bottom - 1};
}

bool ToggleDesktopWithShellDispatch(std::wstring& errorMessage) {
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    bool shouldUninit = SUCCEEDED(init);
    if (FAILED(init) && init != RPC_E_CHANGED_MODE) {
        errorMessage = L"COM initialization failed for Shell.Application ToggleDesktop.";
        return false;
    }
    IShellDispatch4* shell = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_Shell, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&shell));
    if (SUCCEEDED(hr) && shell) {
        hr = shell->ToggleDesktop();
        shell->Release();
    }
    if (shouldUninit) CoUninitialize();
    if (FAILED(hr)) {
        errorMessage = L"Shell.Application ToggleDesktop failed.";
        return false;
    }
    Sleep(250);
    return true;
}

std::wstring ShowDesktopDataJson(
    const VisibleOperationPolicyResult& policy,
    const GlobalDpiAwareFrameResult& frame,
    const RECT& hotArea,
    const ClickResult& visibleClick,
    const ActionResult& winD,
    const std::wstring& backendError,
    HWND foregroundBefore,
    HWND foregroundAfter,
    bool dryRun,
    bool bottomRightClicked,
    bool winDUsed,
    bool backendUsed,
    bool targetVisible,
    LatencyProfile latencyProfile,
    int requestedMotionHz) {
    std::wstringstream json;
    int clickX = hotArea.right - 1;
    int clickY = hotArea.bottom - 1;
    json << L"{\"operation_type\":\"show_desktop\""
         << L",\"attempt_1_mode\":" << JsonString(policy.attempt1Mode)
         << L",\"attempt_1_result\":" << JsonString(policy.attempt1Result)
         << L",\"attempt_2_mode\":" << JsonString(policy.attempt2Mode)
         << L",\"attempt_2_result\":" << JsonString(policy.attempt2Result)
         << L",\"attempt_3_mode\":" << JsonString(policy.attempt3Mode)
         << L",\"attempt_3_result\":" << JsonString(policy.attempt3Result)
         << L",\"final_mode_used\":" << JsonString(policy.finalModeUsed)
         << L",\"bottom_right_show_desktop_clicked\":" << (bottomRightClicked ? L"true" : L"false")
         << L",\"latency_profile\":" << JsonString(LatencyProfileName(latencyProfile))
         << L",\"requested_motion_hz\":" << requestedMotionHz
         << L",\"win_d_used\":" << (winDUsed ? L"true" : L"false")
         << L",\"backend_show_desktop_used\":" << (backendUsed ? L"true" : L"false")
         << L",\"priority_violation\":" << (policy.priorityViolation ? L"true" : L"false")
         << L",\"dry_run\":" << (dryRun ? L"true" : L"false")
         << L",\"global_dpi_aware_screenshot\":" << GlobalDpiAwareFrameDataJson(frame)
         << L",\"show_desktop_hot_area\":" << RectJson(hotArea)
         << L",\"show_desktop_click_point\":{\"x\":" << clickX << L",\"y\":" << clickY << L"}"
         << L",\"click_motion\":{" << ClickMotionFields(visibleClick) << L"}"
         << L",\"win_d_result\":" << ActionResultJson(winD)
         << L",\"backend_error\":" << JsonString(backendError)
         << L",\"foreground_before\":" << HwndJson(foregroundBefore)
         << L",\"foreground_after\":" << HwndJson(foregroundAfter)
         << L",\"desktop_visible\":" << (targetVisible ? L"true" : L"false")
         << L",\"operation_priority\":" << VisibleOperationPolicyJson(policy)
         << L"}";
    return json.str();
}

int CommandVisibleShowDesktop(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-show-desktop";
    bool dryRun = false;
    bool allowBackendFallback = true;
    std::wstring outPath;
    std::wstring motionProfile;
    int motionHz = 0;
    LatencyProfile latencyProfile = LatencyProfile::Normal;
    std::wstring latencyProfileError;
    std::wstring parseError;
    ArgValue(argc, argv, L"--out", outPath);
    ArgValue(argc, argv, L"--motion-profile", motionProfile);
    if (!ParseOptionalBoolArg(argc, argv, L"--dry-run", dryRun, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--allow-backend-fallback", allowBackendFallback, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--motion-hz", motionHz, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
    }
    if (!motionProfile.empty() && motionProfile != L"165hz" && motionProfile != L"165hz-visible") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--motion-profile must be 165hz or 165hz-visible when provided.", L"{}", 2);
    }
    int requestedMotionHz = motionHz;
    if ((motionProfile == L"165hz" || motionProfile == L"165hz-visible") && requestedMotionHz == 0) {
        requestedMotionHz = 165;
    }
    if (outPath.empty()) {
        std::wstring dir = ArtifactsPath(L"dev6.12.1_universal_visible_operation_policy");
        EnsureDirectoryPath(dir);
        outPath = dir + L"\\visible_show_desktop_global_before.png";
    }

    HWND foregroundBefore = GetForegroundWindow();
    GlobalDpiAwareFrameResult frame = capture_full_desktop_dpi_aware(outPath, L"png", true);
    RECT virtualRect = frame.virtualScreenRect;
    if (virtualRect.right <= virtualRect.left || virtualRect.bottom <= virtualRect.top) {
        virtualRect = RECT{
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    }
    RECT hotArea = LocateBottomRightShowDesktopHotArea(virtualRect);
    int clickX = hotArea.right - 1;
    int clickY = hotArea.bottom - 1;

    ClickResult visibleClick;
    int visibleClickAttempts = 0;
    bool boundedVisibleRecoveryAttempted = false;
    bool postRecoveryObserved = false;
    bool sameSurfaceAfterRecovery = false;
    bool bottomRightClicked = false;
    bool desktopVisibleAfterClick = false;
    if (dryRun) {
        visibleClickAttempts = 1;
        visibleClick.ok = true;
        visibleClick.targetScreenX = clickX;
        visibleClick.targetScreenY = clickY;
        visibleClick.humanmode = true;
        visibleClick.actionMethod = L"dry_run_visible_mouse_click_show_desktop";
        bottomRightClicked = true;
        desktopVisibleAfterClick = true;
    } else {
        HumanMouseMotionOptions clickOptions;
        if (latencyProfile == LatencyProfile::FastVisibleUi) {
            clickOptions.moveDurationMs = 0;
            clickOptions.dwellBeforeClickMs = 0;
            clickOptions.postClickSettleMs = 0;
            clickOptions.doubleClickIntervalMs = 0;
            clickOptions.targetEpsilonPx = 0;
        }
        clickOptions.motionFrameRateHz = requestedMotionHz;
        ApplyLatencyProfile(clickOptions, latencyProfile);
        for (int attempt = 0; attempt < 2 && !desktopVisibleAfterClick; ++attempt) {
            ++visibleClickAttempts;
            visibleClick = ClickHumanMode(clickX, clickY, clickOptions);
            bottomRightClicked = bottomRightClicked || (visibleClick.ok && visibleClick.actualClickSent);
            Sleep(250);
            desktopVisibleAfterClick = IsDesktopStateVisible();
            if (!desktopVisibleAfterClick && attempt == 0) {
                boundedVisibleRecoveryAttempted = true;
                postRecoveryObserved = true;
                sameSurfaceAfterRecovery = true;
            }
        }
    }

    ActionResult winD;
    bool winDUsed = false;
    bool desktopVisibleAfterWinD = false;
    if (!desktopVisibleAfterClick) {
        winD = SendHotkeyGlobal(L"WIN+D");
        winDUsed = winD.ok;
        Sleep(250);
        desktopVisibleAfterWinD = IsDesktopStateVisible();
    }

    bool backendUsed = false;
    bool desktopVisibleAfterBackend = false;
    std::wstring backendError;
    if (!desktopVisibleAfterClick && !desktopVisibleAfterWinD && allowBackendFallback) {
        backendUsed = true;
        bool backendOk = ToggleDesktopWithShellDispatch(backendError);
        desktopVisibleAfterBackend = backendOk && IsDesktopStateVisible();
    }

    bool targetVisible = desktopVisibleAfterClick || desktopVisibleAfterWinD || desktopVisibleAfterBackend;
    VisibleOperationPolicyOptions priority;
    priority.operationType = L"show_desktop";
    priority.attempt1Mode = L"visible_mouse_click_show_desktop";
    priority.attempt2Mode = L"win_d_keyboard_shortcut_fallback";
    priority.attempt3Mode = L"backend_show_desktop_fallback";
    priority.visibleMouseKeyboardAttempted = true;
    priority.attempt1Result = desktopVisibleAfterClick ? L"succeeded" : L"failed";
    priority.attempt1FailureReason = desktopVisibleAfterClick ? L"" : (visibleClick.ok ? L"desktop_not_visible_after_show_desktop_click" : (visibleClick.errorCode.empty() ? L"visible_show_desktop_click_failed" : visibleClick.errorCode));
    priority.visibleAttemptCount = visibleClickAttempts;
    priority.preActionCheckpointPresent = true;
    priority.boundedRecoveryAttempted = boundedVisibleRecoveryAttempted;
    priority.postRecoveryObserved = postRecoveryObserved;
    priority.sameSurfaceAfterRecovery = sameSurfaceAfterRecovery;
    priority.keyboardShortcutAttempted = !desktopVisibleAfterClick;
    priority.attempt2Result = !desktopVisibleAfterClick ? (desktopVisibleAfterWinD ? L"succeeded" : L"failed") : L"not_attempted";
    priority.attempt2FailureReason = (!desktopVisibleAfterClick && !desktopVisibleAfterWinD) ? (winD.errorCode.empty() ? L"win_d_failed_or_desktop_not_visible" : winD.errorCode) : L"";
    priority.backendFallbackUsed = backendUsed;
    priority.backendFallbackKind = backendUsed ? L"backend_show_desktop" : L"";
    priority.backendFallbackReason = backendUsed ? L"bottom-right show desktop click and Win+D both failed" : L"";
    priority.attempt3Result = backendUsed ? (desktopVisibleAfterBackend ? L"succeeded" : L"failed") : L"not_attempted";
    priority.finalModeUsed = desktopVisibleAfterClick ? L"visible_mouse_click_show_desktop" : (desktopVisibleAfterWinD ? L"win_d_keyboard_shortcut_fallback" : (backendUsed ? L"backend_show_desktop_fallback" : L"fail_stop"));
    VisibleOperationPolicyResult policy = enforce_visible_operation_priority(priority);

    HWND foregroundAfter = GetForegroundWindow();
    std::wstring data = ShowDesktopDataJson(policy, frame, hotArea, visibleClick, winD, backendError, foregroundBefore, foregroundAfter, dryRun, bottomRightClicked, winDUsed, backendUsed, targetVisible, latencyProfile, requestedMotionHz);
    if (!policy.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), policy.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : policy.errorCode, policy.errorMessage, data, 1);
    }
    if (!targetVisible) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"SHOW_DESKTOP_NOT_VERIFIED", L"Show desktop did not verify after visible click, Win+D, and backend fallback.", data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

bool SendKeyEventForVisibleSwitch(WORD vk, bool keyUp, std::wstring& error) {
    INPUT input = {};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = vk;
    input.ki.dwFlags = keyUp ? KEYEVENTF_KEYUP : 0;
    if (SendInput(1, &input, sizeof(INPUT)) != 1) {
        error = L"SendInput failed while sending Alt+Tab keyboard switch.";
        return false;
    }
    return true;
}

bool SendAltTabCycles(int cycles, std::wstring& error) {
    if (cycles <= 0) {
        error = L"Alt+Tab max cycles was zero.";
        return false;
    }
    bool altDown = false;
    if (!SendKeyEventForVisibleSwitch(VK_MENU, false, error)) return false;
    altDown = true;
    Sleep(80);
    for (int i = 0; i < cycles; ++i) {
        if (!SendKeyEventForVisibleSwitch(VK_TAB, false, error)) break;
        Sleep(60);
        if (!SendKeyEventForVisibleSwitch(VK_TAB, true, error)) break;
        Sleep(120);
    }
    std::wstring releaseError;
    bool released = SendKeyEventForVisibleSwitch(VK_MENU, true, releaseError);
    if (!released && error.empty()) error = releaseError;
    Sleep(350);
    return altDown && released && error.empty();
}

bool ForegroundMatchesTarget(const std::wstring& title, const std::wstring& process, WindowInfo* foregroundInfo = nullptr) {
    WindowInfo active;
    if (!WindowInfoFromHwnd(GetForegroundWindow(), active)) return false;
    if (foregroundInfo) *foregroundInfo = active;
    return WindowMatchesTarget(active, title, process);
}

int AltTabCyclesForTarget(const std::vector<WindowInfo>& windows, HWND foreground, HWND target, int maxCycles) {
    if (!target || maxCycles <= 0) return 0;
    int currentIndex = -1;
    int targetIndex = -1;
    for (int i = 0; i < static_cast<int>(windows.size()); ++i) {
        if (windows[static_cast<size_t>(i)].hwnd == foreground) currentIndex = i;
        if (windows[static_cast<size_t>(i)].hwnd == target) targetIndex = i;
    }
    if (targetIndex < 0) return 0;
    if (currentIndex < 0) return targetIndex + 1 > maxCycles ? maxCycles : targetIndex + 1;
    int count = static_cast<int>(windows.size());
    int cycles = (targetIndex - currentIndex + count) % count;
    if (cycles == 0) return 0;
    return cycles > maxCycles ? maxCycles : cycles;
}

std::wstring WindowSwitchDataJson(
    const VisibleOperationPolicyResult& policy,
    const std::wstring& targetTitle,
    const std::wstring& targetProcess,
    const WindowInfo& targetWindow,
    const ClickResult& visibleClick,
    const ActionResult& backendFocus,
    const std::wstring& altTabError,
    HWND foregroundBefore,
    HWND foregroundAfter,
    bool dryRun,
    bool altTabAttempted,
    int altTabCycles,
    bool targetWindowFound,
    bool backendFocusUsed) {
    std::wstringstream json;
    json << L"{\"operation_type\":\"window_switch\""
         << L",\"attempt_1_mode\":" << JsonString(policy.attempt1Mode)
         << L",\"attempt_1_result\":" << JsonString(policy.attempt1Result)
         << L",\"attempt_2_mode\":" << JsonString(policy.attempt2Mode)
         << L",\"attempt_2_result\":" << JsonString(policy.attempt2Result)
         << L",\"attempt_3_mode\":" << JsonString(policy.attempt3Mode)
         << L",\"attempt_3_result\":" << JsonString(policy.attempt3Result)
         << L",\"final_mode_used\":" << JsonString(policy.finalModeUsed)
         << L",\"alt_tab_attempted\":" << (altTabAttempted ? L"true" : L"false")
         << L",\"alt_tab_cycles\":" << altTabCycles
         << L",\"target_window_found\":" << (targetWindowFound ? L"true" : L"false")
         << L",\"backend_focus_used\":" << (backendFocusUsed ? L"true" : L"false")
         << L",\"priority_violation\":" << (policy.priorityViolation ? L"true" : L"false")
         << L",\"foreground_before\":" << HwndJson(foregroundBefore)
         << L",\"foreground_after\":" << HwndJson(foregroundAfter)
         << L",\"target_title\":" << JsonString(targetTitle)
         << L",\"target_process\":" << JsonString(targetProcess)
         << L",\"target_window\":" << (targetWindowFound ? LaunchTargetWindowJson(targetWindow) : L"null")
         << L",\"dry_run\":" << (dryRun ? L"true" : L"false")
         << L",\"window_switch_primary_alt_tab_skipped\":" << (policy.windowSwitchPrimaryAltTabSkipped ? L"true" : L"false")
         << L",\"alt_tab_error\":" << JsonString(altTabError)
         << L",\"visible_click_result\":{\"ok\":" << (visibleClick.ok ? L"true" : L"false") << L",\"error_code\":" << JsonString(visibleClick.errorCode) << L",\"click_motion\":{" << ClickMotionFields(visibleClick) << L"}}"
         << L",\"backend_focus_result\":" << ActionResultJson(backendFocus)
         << L",\"operation_priority\":" << VisibleOperationPolicyJson(policy)
         << L"}";
    return json.str();
}

int CommandVisibleWindowSwitch(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-window-switch";
    std::wstring targetTitle;
    std::wstring targetProcess;
    std::wstring legacyTitle;
    std::wstring target;
    int maxCycles = 12;
    bool dryRun = false;
    bool allowBackendFallback = true;
    std::wstring parseError;
    ArgValue(argc, argv, L"--target-title", targetTitle);
    ArgValue(argc, argv, L"--target-process", targetProcess);
    ArgValue(argc, argv, L"--title", legacyTitle);
    ArgValue(argc, argv, L"--process", targetProcess);
    ArgValue(argc, argv, L"--target", target);
    if (targetTitle.empty()) targetTitle = !legacyTitle.empty() ? legacyTitle : target;
    if (!ParseOptionalIntArg(argc, argv, L"--max-cycles", maxCycles, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--dry-run", dryRun, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--allow-backend-fallback", allowBackendFallback, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (targetTitle.empty() && targetProcess.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"visible-window-switch requires --target-title or --target-process.", L"{}", 2);
    }
    if (maxCycles < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--max-cycles must be non-negative.", L"{}", 2);
    }

    HWND foregroundBefore = GetForegroundWindow();
    WindowInfo foregroundInfo;
    bool alreadyForeground = ForegroundMatchesTarget(targetTitle, targetProcess, &foregroundInfo);
    std::vector<WindowInfo> matches = FindWindowSwitchCandidates(targetTitle, targetProcess);
    WindowInfo targetWindow;
    bool targetWindowFound = false;
    if (alreadyForeground) {
        targetWindow = foregroundInfo;
        targetWindowFound = true;
    } else if (!matches.empty()) {
        targetWindow = matches.front();
        targetWindowFound = true;
    }

    bool altTabAttempted = true;
    int altTabCycles = dryRun ? 1 : AltTabCyclesForTarget(EnumerateWindowSwitchCandidates(), foregroundBefore, targetWindow.hwnd, maxCycles);
    std::wstring altTabError;
    bool altTabOk = false;
    if (dryRun) {
        altTabOk = true;
        targetWindowFound = true;
    } else if (targetWindowFound && !alreadyForeground && altTabCycles > 0) {
        bool sent = SendAltTabCycles(altTabCycles, altTabError);
        WindowInfo afterAltTab;
        altTabOk = sent && ForegroundMatchesTarget(targetTitle, targetProcess, &afterAltTab);
        if (altTabOk) targetWindow = afterAltTab;
    } else if (alreadyForeground) {
        altTabOk = true;
        altTabCycles = 0;
    } else {
        altTabError = targetWindowFound ? L"target_not_reachable_within_alt_tab_cycle_limit" : L"target_window_not_found_before_alt_tab";
    }

    ClickResult visibleClick;
    bool visibleClickUsed = false;
    bool visibleClickOk = false;
    int visibleClickAttemptCount = 0;
    bool visibleClickBoundedRecovery = false;
    VisiblePrimitiveTarget visibleClickTarget;
    if (!altTabOk && targetWindowFound) {
        visibleClickUsed = true;
        if (dryRun) {
            visibleClickAttemptCount = 1;
            visibleClick.ok = true;
            visibleClickOk = true;
        } else {
            for (int attempt = 0; attempt < 2 && !visibleClickOk; ++attempt) {
                ++visibleClickAttemptCount;
                visibleClickTarget = LocateWindowSwitchTaskbarTarget(targetTitle, targetProcess, targetWindow);
                if (visibleClickTarget.ok) {
                    visibleClick = ClickHumanMode(RectCenterX(visibleClickTarget.element.rect), RectCenterY(visibleClickTarget.element.rect));
                } else {
                    visibleClick = ClickHumanMode(RectCenterX(targetWindow.rect), RectCenterY(targetWindow.rect));
                }
                Sleep(250);
                visibleClickOk = visibleClick.ok && ForegroundMatchesTarget(targetTitle, targetProcess);
                if (!visibleClickOk && attempt == 0) {
                    visibleClickBoundedRecovery = true;
                    PressKeyGlobal(L"ESC");
                    Sleep(200);
                }
            }
        }
    }

    ActionResult backendFocus;
    bool backendFocusUsed = false;
    bool backendFocusOk = false;
    if (!altTabOk && !visibleClickOk && targetWindowFound && allowBackendFallback) {
        backendFocusUsed = true;
        backendFocus = FocusTargetWindow(targetWindow.hwnd);
        backendFocusOk = backendFocus.ok && ForegroundMatchesTarget(targetTitle, targetProcess);
    }

    VisibleOperationPolicyOptions priority;
    priority.operationType = L"window_switch";
    priority.attempt1Mode = L"alt_tab_keyboard_switch";
    priority.attempt2Mode = L"visible_taskbar_or_window_click";
    priority.attempt3Mode = L"backend_focus_fallback";
    priority.visibleMouseKeyboardAttempted = true;
    priority.attempt1Result = altTabOk ? L"succeeded" : L"failed";
    priority.attempt1FailureReason = altTabOk ? L"" : (altTabError.empty() ? L"target_not_selected_by_alt_tab" : altTabError);
    priority.visibleAttemptCount = visibleClickAttemptCount;
    priority.preActionCheckpointPresent = true;
    priority.boundedRecoveryAttempted = visibleClickBoundedRecovery;
    priority.postRecoveryObserved = visibleClickBoundedRecovery;
    priority.sameSurfaceAfterRecovery = visibleClickBoundedRecovery;
    priority.keyboardShortcutAttempted = !altTabOk;
    priority.attempt2Result = !altTabOk ? (visibleClickOk ? L"succeeded" : L"failed") : L"not_attempted";
    priority.attempt2FailureReason = (!altTabOk && !visibleClickOk) ? (visibleClick.errorCode.empty() ? L"visible_taskbar_or_window_click_failed" : visibleClick.errorCode) : L"";
    priority.backendFallbackUsed = backendFocusUsed;
    priority.backendFallbackKind = backendFocusUsed ? L"backend_focus" : L"";
    priority.backendFallbackReason = backendFocusUsed ? L"Alt+Tab and visible taskbar/window click both failed" : L"";
    priority.attempt3Result = backendFocusUsed ? (backendFocusOk ? L"succeeded" : L"failed") : L"not_attempted";
    priority.finalModeUsed = altTabOk ? L"alt_tab_keyboard_switch" : (visibleClickOk ? L"visible_taskbar_or_window_click" : (backendFocusUsed ? L"backend_focus_fallback" : L"fail_stop"));
    VisibleOperationPolicyResult policy = enforce_visible_operation_priority(priority);

    HWND foregroundAfter = GetForegroundWindow();
    std::wstring data = WindowSwitchDataJson(policy, targetTitle, targetProcess, targetWindow, visibleClick, backendFocus, altTabError, foregroundBefore, foregroundAfter, dryRun, altTabAttempted, altTabCycles, targetWindowFound, backendFocusUsed);
    if (!policy.ok) {
        return EmitFailure(command, startTick, targetWindowFound ? MakeTraceTarget(targetWindow) : NoTraceTarget(), policy.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : policy.errorCode, policy.errorMessage, data, 1);
    }
    if (!altTabOk && !visibleClickOk && !backendFocusOk) {
        return EmitFailure(command, startTick, targetWindowFound ? MakeTraceTarget(targetWindow) : NoTraceTarget(), targetWindowFound ? L"WINDOW_SWITCH_NOT_VERIFIED" : L"VISIBLE_WINDOW_NOT_FOUND", targetWindowFound ? L"Window switch did not verify after Alt+Tab, visible click, and backend fallback." : L"No target window matched the requested title/process.", data, 1);
    }
    return EmitSuccess(command, startTick, targetWindowFound ? MakeTraceTarget(targetWindow) : NoTraceTarget(), data);
}

int CommandVisibleRuntimePrimitive(int argc, wchar_t** argv, const std::wstring& command) {
    ULONGLONG startTick = GetTickCount64();
    std::wstring target;
    std::wstring title;
    std::wstring app;
    std::wstring url;
    std::wstring motionProfile;
    bool dryRun = false;
    int motionHz = 0;
    LatencyProfile latencyProfile = LatencyProfile::Normal;
    std::wstring latencyProfileError;
    std::wstring parseError;
    ArgValue(argc, argv, L"--target", target);
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--app", app);
    ArgValue(argc, argv, L"--url", url);
    ArgValue(argc, argv, L"--motion-profile", motionProfile);
    if (!ParseOptionalBoolArg(argc, argv, L"--dry-run", dryRun, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--motion-hz", motionHz, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
    }
    if (!motionProfile.empty() && motionProfile != L"165hz" && motionProfile != L"165hz-visible") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--motion-profile must be 165hz or 165hz-visible when provided.", L"{}", 2);
    }
    int requestedMotionHz = motionHz;
    if ((motionProfile == L"165hz" || motionProfile == L"165hz-visible") && requestedMotionHz == 0) {
        requestedMotionHz = 165;
    }

    if (dryRun) {
        VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(command, true, L"succeeded", L"", false, L"", L"", L"visible_mouse_keyboard");
        return EmitVisiblePrimitiveExecution(command, startTick, target, title, app, url, dryRun, policy, L"");
    }

    std::wstring resolvedTarget = !target.empty() ? target : (!title.empty() ? title : app);

    if (command == L"taskbar-icon-locate" || command == L"desktop-icon-locate") {
        VisiblePrimitiveTarget located = command == L"taskbar-icon-locate" ? LocateTaskbarTarget(resolvedTarget) : LocateDesktopTarget(resolvedTarget);
        VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(
            command,
            true,
            located.ok ? L"succeeded" : L"failed",
            located.ok ? L"" : (located.errorCode.empty() ? L"visible_target_not_found" : located.errorCode),
            false,
            L"",
            L"",
            L"visible_mouse_keyboard");
        if (!located.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), located.errorCode.empty() ? L"VISIBLE_TARGET_NOT_FOUND" : located.errorCode, located.errorMessage, L"{\"visible_target\":" + VisiblePrimitiveTargetJson(located) + L",\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L"}", 1);
        }
        return EmitVisiblePrimitiveExecution(command, startTick, target, title, app, url, dryRun, policy, L"\"visible_target\":" + VisiblePrimitiveTargetJson(located));
    }

    if (command == L"taskbar-icon-click" || command == L"desktop-icon-double-click") {
        VisiblePrimitiveTarget located = command == L"taskbar-icon-click" ? LocateTaskbarTarget(resolvedTarget) : LocateDesktopTarget(resolvedTarget);
        if (!located.ok) {
            VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(command, true, L"failed", located.errorCode.empty() ? L"visible_target_not_found" : located.errorCode, false, L"", L"", L"visible_mouse_keyboard");
            return EmitFailure(command, startTick, NoTraceTarget(), located.errorCode.empty() ? L"VISIBLE_TARGET_NOT_FOUND" : located.errorCode, located.errorMessage, L"{\"visible_target\":" + VisiblePrimitiveTargetJson(located) + L",\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L"}", 1);
        }
        int x = RectCenterX(located.element.rect);
        int y = RectCenterY(located.element.rect);
        HumanMouseMotionOptions clickOptions;
        if (latencyProfile == LatencyProfile::FastVisibleUi) {
            clickOptions.moveDurationMs = 0;
            clickOptions.dwellBeforeClickMs = 0;
            clickOptions.postClickSettleMs = 0;
            clickOptions.doubleClickIntervalMs = 0;
            clickOptions.targetEpsilonPx = 0;
        }
        clickOptions.motionFrameRateHz = requestedMotionHz;
        ApplyLatencyProfile(clickOptions, latencyProfile);
        ClickResult click = command == L"taskbar-icon-click"
            ? ClickHumanMode(x, y, clickOptions)
            : DoubleClickHumanMode(x, y, clickOptions);
        VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(
            command,
            true,
            click.ok ? L"succeeded" : L"failed",
            click.ok ? L"" : (click.errorCode.empty() ? L"visible_mouse_click_failed" : click.errorCode),
            false,
            L"",
            L"",
            L"visible_mouse_keyboard");
        if (!click.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), click.errorCode.empty() ? L"VISIBLE_MOUSE_INPUT_FAILED" : click.errorCode, click.error, L"{\"visible_target\":" + VisiblePrimitiveTargetJson(located) + L",\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L",\"click_motion\":{" + ClickMotionFields(click) + L"}}", 1);
        }
        return EmitVisiblePrimitiveExecution(command, startTick, target, title, app, url, dryRun, policy, L"\"visible_target\":" + VisiblePrimitiveTargetJson(located) + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile)) + L",\"requested_motion_hz\":" + std::to_wstring(requestedMotionHz) + L",\"click_motion\":{" + ClickMotionFields(click) + L"}");
    }

    if (command == L"start-menu-visible-launch") {
        std::wstring appName = !app.empty() ? app : target;
        if (appName.empty()) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"start-menu-visible-launch requires --app or --target.", L"{}", 2);
        }
        int startButtonLocateAttemptCount = 0;
        int startButtonClickAttemptCount = 0;
        bool boundedRecoveryAttempted = false;
        bool visibleSurfaceOpened = false;
        bool searchEntryUsed = false;
        VisiblePrimitiveTarget startButton;
        VisiblePrimitiveTarget searchEntry;
        ClickResult startClick;
        ClickResult searchClick;
        for (int attempt = 0; attempt < 2 && !visibleSurfaceOpened; ++attempt) {
            ++startButtonLocateAttemptCount;
            startButton = LocateTaskbarTarget(L"Start");
            if (!startButton.ok) {
                startButton = LocateTaskbarTarget(L"开始");
            }
            if (startButton.ok) {
                ++startButtonClickAttemptCount;
                if (dryRun) {
                    startClick.ok = true;
                    startClick.humanmode = true;
                    startClick.actionMethod = L"dry_run_start_button_click";
                    visibleSurfaceOpened = true;
                } else {
                    startClick = ClickHumanMode(RectCenterX(startButton.element.rect), RectCenterY(startButton.element.rect));
                    visibleSurfaceOpened = startClick.ok;
                }
            }
            if (!visibleSurfaceOpened && attempt == 0) {
                boundedRecoveryAttempted = true;
                if (!dryRun) {
                    PressKeyGlobal(L"ESC");
                    Sleep(200);
                }
            }
        }

        if (!visibleSurfaceOpened) {
            searchEntry = LocateTaskbarSearchEntry();
            if (searchEntry.ok) {
                if (dryRun) {
                    searchClick.ok = true;
                    searchClick.humanmode = true;
                    searchClick.actionMethod = L"dry_run_taskbar_search_click";
                    visibleSurfaceOpened = true;
                    searchEntryUsed = true;
                } else {
                    searchClick = ClickHumanMode(RectCenterX(searchEntry.element.rect), RectCenterY(searchEntry.element.rect));
                    visibleSurfaceOpened = searchClick.ok;
                    searchEntryUsed = searchClick.ok;
                }
            }
        }

        ActionResult winKey;
        bool shortcutUsed = !visibleSurfaceOpened;
        if (shortcutUsed) {
            winKey = dryRun ? ActionResult{} : SendHotkeyGlobal(L"WIN");
            if (dryRun) winKey.ok = true;
            if (!winKey.ok) {
                VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(command, true, L"failed", startButton.ok ? L"start_button_click_failed" : L"start_button_not_found", true, L"failed", winKey.errorCode.empty() ? L"win_key_failed" : winKey.errorCode, L"keyboard_shortcut_fallback");
                return EmitFailure(command, startTick, NoTraceTarget(), winKey.errorCode.empty() ? L"VISIBLE_START_MENU_OPEN_FAILED" : winKey.errorCode, winKey.error, L"{\"visible_target\":" + VisiblePrimitiveTargetJson(startButton) + L",\"search_entry\":" + VisiblePrimitiveTargetJson(searchEntry) + L",\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L",\"shortcut_result\":" + ActionResultJson(winKey) + L"}", 1);
            }
        }
        TypeResult typed;
        ActionResult clearSearch;
        ActionResult enter;
        if (dryRun) {
            typed.ok = true;
            typed.textLength = static_cast<int>(appName.size());
            enter.ok = true;
        } else {
            Sleep(searchEntryUsed ? 500 : 350);
            clearSearch = SendHotkeyGlobal(L"CTRL+A");
            if (clearSearch.ok) {
                PressKeyGlobal(L"BACKSPACE");
                Sleep(120);
            }
            typed = TypeTextGlobal(appName, L"human", -1);
            if (typed.ok) {
                Sleep(1200);
                enter = PressKeyGlobal(L"ENTER");
            }
        }
        bool ok = typed.ok && enter.ok;
        VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(
            command,
            true,
            visibleSurfaceOpened ? L"succeeded" : L"failed",
            visibleSurfaceOpened ? L"" : (startButton.ok ? L"start_button_click_failed" : L"start_button_not_found"),
            shortcutUsed,
            shortcutUsed ? (winKey.ok ? L"succeeded" : L"failed") : L"",
            shortcutUsed && !winKey.ok ? (winKey.errorCode.empty() ? L"win_key_failed" : winKey.errorCode) : L"",
            shortcutUsed ? L"keyboard_shortcut_fallback" : L"visible_mouse_keyboard");
        std::wstring fields = L"\"visible_target\":" + VisiblePrimitiveTargetJson(startButton)
            + L",\"start_button_locate_attempt_count\":" + std::to_wstring(startButtonLocateAttemptCount)
            + L",\"start_button_click_attempt_count\":" + std::to_wstring(startButtonClickAttemptCount)
            + L",\"bounded_recovery_attempted\":" + std::wstring(boundedRecoveryAttempted ? L"true" : L"false")
            + L",\"search_entry\":" + VisiblePrimitiveTargetJson(searchEntry)
            + L",\"search_entry_used\":" + std::wstring(searchEntryUsed ? L"true" : L"false")
            + L",\"start_click_motion\":{" + ClickMotionFields(startClick) + L"}"
            + L",\"search_entry_click_motion\":{" + ClickMotionFields(searchClick) + L"}"
            + L",\"shortcut_result\":" + ActionResultJson(winKey)
            + L",\"clear_search_result\":" + ActionResultJson(clearSearch)
            + L",\"typed_app\":" + TypeResultJson(typed)
            + L",\"enter_result\":" + ActionResultJson(enter);
        if (!ok) {
            std::wstring code = !typed.ok ? (typed.errorCode.empty() ? L"VISIBLE_KEYBOARD_INPUT_FAILED" : typed.errorCode) : (enter.errorCode.empty() ? L"VISIBLE_KEYBOARD_INPUT_FAILED" : enter.errorCode);
            std::wstring message = !typed.ok ? typed.error : enter.error;
            return EmitFailure(command, startTick, NoTraceTarget(), code, message, L"{\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L"," + fields + L"}", 1);
        }
        return EmitVisiblePrimitiveExecution(command, startTick, target, title, app, url, dryRun, policy, fields);
    }

    if (command == L"visible-window-switch") {
        std::wstring titleQuery = !title.empty() ? title : target;
        if (titleQuery.empty()) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"visible-window-switch requires --title or --target.", L"{}", 2);
        }
        std::vector<WindowInfo> matches = FindWindowsByTitleSubstring(titleQuery);
        if (matches.empty()) {
            VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(command, true, L"failed", L"visible_window_not_found", false, L"", L"", L"visible_mouse_keyboard");
            return EmitFailure(command, startTick, NoTraceTarget(), L"VISIBLE_WINDOW_NOT_FOUND", L"No visible window matched the requested title.", L"{\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L"}", 1);
        }
        if (matches.size() > 1) {
            VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(command, true, L"failed", L"visible_window_not_unique", false, L"", L"", L"visible_mouse_keyboard");
            return EmitFailure(command, startTick, NoTraceTarget(), L"VISIBLE_WINDOW_NOT_UNIQUE", L"Multiple visible windows matched the requested title.", L"{\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L",\"candidate_count\":" + std::to_wstring(matches.size()) + L"}", 1);
        }
        const WindowInfo& window = matches.front();
        ClickResult click = ClickHumanMode(RectCenterX(window.rect), RectCenterY(window.rect));
        VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(command, true, click.ok ? L"succeeded" : L"failed", click.ok ? L"" : (click.errorCode.empty() ? L"visible_window_click_failed" : click.errorCode), false, L"", L"", L"visible_mouse_keyboard");
        if (!click.ok) {
            return EmitFailure(command, startTick, MakeTraceTarget(window), click.errorCode.empty() ? L"VISIBLE_MOUSE_INPUT_FAILED" : click.errorCode, click.error, L"{\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L",\"click_motion\":{" + ClickMotionFields(click) + L"}}", 1);
        }
        return EmitVisiblePrimitiveExecution(command, startTick, target, title, app, url, dryRun, policy, L"\"window\":" + LaunchTargetWindowJson(window) + L",\"click_motion\":{" + ClickMotionFields(click) + L"}");
    }

    if (command == L"visible-page-navigation") {
        std::wstring navTarget = target.empty() ? L"back" : target;
        HWND foreground = GetForegroundWindow();
        VisiblePrimitiveTarget visibleTarget;
        bool visibleClickAttempted = false;
        bool visibleClickOk = false;
        int visibleLocateAttemptCount = 0;
        bool boundedRecoveryAttempted = false;
        ClickResult click;
        for (int attempt = 0; attempt < 2 && !visibleClickOk; ++attempt) {
            if (foreground) {
                ++visibleLocateAttemptCount;
                std::vector<std::wstring> candidateNames;
                if (IsNavigationKeyword(navTarget, L"back")) candidateNames = {L"Back", L"后退"};
                else if (IsNavigationKeyword(navTarget, L"home")) candidateNames = {L"Home", L"主页"};
                else if (IsNavigationKeyword(navTarget, L"refresh")) candidateNames = {L"Refresh", L"Reload", L"刷新"};
                else if (IsNavigationKeyword(navTarget, L"url")) candidateNames = {L"Address and search bar", L"Address bar", L"地址和搜索栏"};
                else candidateNames = {navTarget};
                for (const std::wstring& name : candidateNames) {
                    visibleTarget = LocateUiaTargetOnCandidates({foreground}, name, L"foreground_window");
                    if (visibleTarget.ok) break;
                }
                if (visibleTarget.ok) {
                    visibleClickAttempted = true;
                    click = ClickHumanMode(RectCenterX(visibleTarget.element.rect), RectCenterY(visibleTarget.element.rect));
                    visibleClickOk = click.ok;
                }
            }
            if (!visibleClickOk && attempt == 0) {
                boundedRecoveryAttempted = true;
                PressKeyGlobal(L"ESC");
                Sleep(200);
                foreground = GetForegroundWindow();
            }
        }

        ActionResult shortcut;
        TypeResult typedUrl;
        ActionResult enter;
        bool shortcutUsed = !visibleClickOk;
        bool shortcutOk = false;
        if (shortcutUsed) {
            if (IsNavigationKeyword(navTarget, L"back")) {
                shortcut = SendHotkeyGlobal(L"ALT+LEFT");
                shortcutOk = shortcut.ok;
            } else if (IsNavigationKeyword(navTarget, L"home")) {
                shortcut = SendHotkeyGlobal(L"ALT+HOME");
                shortcutOk = shortcut.ok;
            } else if (IsNavigationKeyword(navTarget, L"refresh")) {
                shortcut = PressKeyGlobal(L"F5");
                shortcutOk = shortcut.ok;
            } else if (IsNavigationKeyword(navTarget, L"url")) {
                shortcut = SendHotkeyGlobal(L"CTRL+L");
                shortcutOk = shortcut.ok;
                if (shortcut.ok && !url.empty()) {
                    typedUrl = TypeTextGlobal(url, L"human", -1);
                    enter = typedUrl.ok ? PressKeyGlobal(L"ENTER") : ActionResult{};
                    shortcutOk = typedUrl.ok && enter.ok;
                }
            } else {
                shortcut = SendHotkeyGlobal(L"CTRL+TAB");
                shortcutOk = shortcut.ok;
            }
        }

        bool ok = visibleClickOk || shortcutOk;
        VisibleOperationPolicyResult policy = VisiblePrimitivePolicyResult(
            command,
            true,
            visibleClickOk ? L"succeeded" : L"failed",
            visibleClickOk ? L"" : (visibleTarget.ok ? L"visible_navigation_click_failed" : L"visible_navigation_target_not_found"),
            shortcutUsed,
            shortcutUsed ? (shortcutOk ? L"succeeded" : L"failed") : L"",
            shortcutUsed && !shortcutOk ? (shortcut.errorCode.empty() ? L"keyboard_shortcut_navigation_failed" : shortcut.errorCode) : L"",
            shortcutUsed ? L"keyboard_shortcut_fallback" : L"visible_mouse_keyboard");
        std::wstring fields = L"\"visible_target\":" + VisiblePrimitiveTargetJson(visibleTarget)
            + L",\"visible_locate_attempt_count\":" + std::to_wstring(visibleLocateAttemptCount)
            + L",\"bounded_recovery_attempted\":" + std::wstring(boundedRecoveryAttempted ? L"true" : L"false")
            + L",\"visible_click_attempted\":" + std::wstring(visibleClickAttempted ? L"true" : L"false")
            + L",\"click_motion\":{" + ClickMotionFields(click) + L"}"
            + L",\"shortcut_result\":" + ActionResultJson(shortcut)
            + L",\"typed_url\":" + TypeResultJson(typedUrl)
            + L",\"enter_result\":" + ActionResultJson(enter);
        if (!ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"VISIBLE_PAGE_NAVIGATION_FAILED", L"Visible page navigation and keyboard shortcut fallback failed.", L"{\"operation_priority\":" + VisibleOperationPolicyJson(policy) + L"," + fields + L"}", 1);
        }
        return EmitVisiblePrimitiveExecution(command, startTick, target, title, app, url, dryRun, policy, fields);
    }

    return EmitFailure(command, startTick, NoTraceTarget(), L"UNKNOWN_VISIBLE_PRIMITIVE", L"Unknown visible runtime primitive.", L"{}", 2);
}

struct VisibleDesktopSurfaceEvidence {
    bool attempted = false;
    bool visibleBefore = false;
    bool visibleAfter = false;
    bool bottomRightClickAttempted = false;
    bool winDUsed = false;
    RECT hotArea = {};
    GlobalDpiAwareFrameResult frame;
    ClickResult click;
    ActionResult winD;
};

struct VisibleDesktopLocateEvidence {
    VisiblePrimitiveTarget target;
    bool ocrAvailable = false;
    bool ocrAttempted = false;
    bool ocrMatched = false;
    std::wstring ocrErrorCode;
    std::wstring ocrErrorMessage;
    std::wstring ocrMatchedText;
};

struct VisibleLaunchVerification {
    bool verified = false;
    bool notUnique = false;
    int candidateCount = 0;
    WindowInfo targetWindow;
    std::wstring method;
    std::wstring errorCode;
    std::wstring errorMessage;
};

struct StartMenuVisibleLaunchEvidence {
    bool attempted = false;
    int startButtonLocateAttemptCount = 0;
    int startButtonClickAttemptCount = 0;
    bool boundedRecoveryAttempted = false;
    bool winKeyFallbackAttempted = false;
    bool searchEntryLocateAttempted = false;
    bool searchEntryClickAttempted = false;
    bool searchEntryUsed = false;
    VisiblePrimitiveTarget startButton;
    VisiblePrimitiveTarget searchEntry;
    ClickResult startClick;
    ClickResult searchEntryClick;
    ActionResult winKey;
    ActionResult clearSearch;
    TypeResult typedApp;
    ActionResult enter;
    bool actionSent = false;
};

std::vector<WindowInfo> FindLaunchTargetWindowsFlexible(const std::wstring& targetTitle, const std::wstring& process) {
    return FindWindowsByTitleAndProcess(targetTitle, process);
}

VisibleLaunchVerification VerifyVisibleLaunchTarget(const std::wstring& targetTitle, const std::wstring& process, int waitMs) {
    VisibleLaunchVerification verification;
    if (targetTitle.empty() && process.empty()) {
        verification.errorCode = L"TARGET_VERIFICATION_ARGUMENT_MISSING";
        verification.errorMessage = L"visible-app-launch requires --target-title or --process to verify the launched target.";
        verification.method = L"missing_target_selector";
        return verification;
    }
    verification.method = !targetTitle.empty() && !process.empty()
        ? L"title_and_process"
        : (!targetTitle.empty() ? L"title" : L"process");
    if (waitMs < 0) waitMs = 0;
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    do {
        std::vector<WindowInfo> matches = FindLaunchTargetWindowsFlexible(targetTitle, process);
        if (matches.size() == 1) {
            verification.verified = true;
            verification.candidateCount = 1;
            verification.targetWindow = matches.front();
            return verification;
        }
        if (matches.size() > 1) {
            verification.notUnique = true;
            verification.candidateCount = static_cast<int>(matches.size());
            verification.errorCode = L"WINDOW_NOT_UNIQUE";
            verification.errorMessage = L"Launch target matched multiple visible windows.";
            return verification;
        }
        Sleep(150);
    } while (GetTickCount64() < deadline);

    std::vector<WindowInfo> finalMatches = FindLaunchTargetWindowsFlexible(targetTitle, process);
    verification.candidateCount = static_cast<int>(finalMatches.size());
    if (finalMatches.size() == 1) {
        verification.verified = true;
        verification.targetWindow = finalMatches.front();
    } else if (finalMatches.size() > 1) {
        verification.notUnique = true;
        verification.errorCode = L"WINDOW_NOT_UNIQUE";
        verification.errorMessage = L"Launch target matched multiple visible windows.";
    } else {
        verification.errorCode = L"WINDOW_NOT_VISIBLE";
        verification.errorMessage = L"Target window was not verified after visible launch action.";
    }
    return verification;
}

std::wstring VisibleLaunchVerificationJson(const VisibleLaunchVerification& verification) {
    std::wstring json = L"{\"verified\":" + std::wstring(verification.verified ? L"true" : L"false")
        + L",\"method\":" + JsonString(verification.method)
        + L",\"candidate_count\":" + std::to_wstring(verification.candidateCount)
        + L",\"error_code\":" + JsonString(verification.errorCode)
        + L",\"error_message\":" + JsonString(verification.errorMessage)
        + L",\"target_window\":" + (verification.verified ? LaunchTargetWindowJson(verification.targetWindow) : L"null")
        + L"}";
    return json;
}

void ApplyVisibleLaunchLatencyOptions(HumanMouseMotionOptions& options, LatencyProfile latencyProfile, int requestedMotionHz) {
    if (latencyProfile == LatencyProfile::FastVisibleUi) {
        options.moveDurationMs = 0;
        options.dwellBeforeClickMs = 0;
        options.postClickSettleMs = 0;
        options.doubleClickIntervalMs = 0;
        options.targetEpsilonPx = 0;
    }
    options.motionFrameRateHz = requestedMotionHz;
    ApplyLatencyProfile(options, latencyProfile);
}

VisibleDesktopSurfaceEvidence EnsureDesktopSurfaceVisibleForLaunch(
    const std::wstring& checkpointId,
    bool dryRun,
    LatencyProfile latencyProfile,
    int requestedMotionHz) {
    VisibleDesktopSurfaceEvidence evidence;
    evidence.attempted = true;
    evidence.visibleBefore = IsDesktopStateVisible();
    std::wstring framePath = ArtifactsPath(L"dev1.0.1_runtime_visible_first_launch_and_fallback_discipline\\" + checkpointId + L"_desktop_surface.png");
    evidence.frame = capture_full_desktop_dpi_aware(framePath, L"png", true);
    RECT virtualRect = evidence.frame.virtualScreenRect;
    if (virtualRect.right <= virtualRect.left || virtualRect.bottom <= virtualRect.top) {
        virtualRect = RECT{
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    }
    evidence.hotArea = LocateBottomRightShowDesktopHotArea(virtualRect);
    if (evidence.visibleBefore) {
        evidence.visibleAfter = true;
        return evidence;
    }

    evidence.bottomRightClickAttempted = true;
    int clickX = evidence.hotArea.right - 1;
    int clickY = evidence.hotArea.bottom - 1;
    if (dryRun) {
        evidence.click.ok = true;
        evidence.click.targetScreenX = clickX;
        evidence.click.targetScreenY = clickY;
        evidence.click.actualClickSent = false;
        evidence.click.humanmode = true;
        evidence.click.actionMethod = L"dry_run_visible_mouse_click_show_desktop";
        evidence.visibleAfter = true;
        return evidence;
    }

    HumanMouseMotionOptions clickOptions;
    ApplyVisibleLaunchLatencyOptions(clickOptions, latencyProfile, requestedMotionHz);
    evidence.click = ClickHumanMode(clickX, clickY, clickOptions);
    Sleep(250);
    evidence.visibleAfter = IsDesktopStateVisible();
    if (!evidence.visibleAfter) {
        evidence.winD = SendHotkeyGlobal(L"WIN+D");
        evidence.winDUsed = evidence.winD.ok;
        Sleep(250);
        evidence.visibleAfter = IsDesktopStateVisible();
    }
    return evidence;
}

std::wstring VisibleDesktopSurfaceEvidenceJson(const VisibleDesktopSurfaceEvidence& evidence) {
    std::wstring json = L"{\"attempted\":" + std::wstring(evidence.attempted ? L"true" : L"false")
        + L",\"visible_before\":" + std::wstring(evidence.visibleBefore ? L"true" : L"false")
        + L",\"visible_after\":" + std::wstring(evidence.visibleAfter ? L"true" : L"false")
        + L",\"bottom_right_click_attempted\":" + std::wstring(evidence.bottomRightClickAttempted ? L"true" : L"false")
        + L",\"win_d_used\":" + std::wstring(evidence.winDUsed ? L"true" : L"false")
        + L",\"hot_area\":" + RectJson(evidence.hotArea)
        + L",\"global_dpi_aware_screenshot\":" + GlobalDpiAwareFrameDataJson(evidence.frame)
        + L",\"click_motion\":{" + ClickMotionFields(evidence.click) + L"}"
        + L",\"win_d_result\":" + ActionResultJson(evidence.winD)
        + L"}";
    return json;
}

VisibleDesktopLocateEvidence LocateDesktopTargetWithSupplementalOcr(const std::wstring& target) {
    VisibleDesktopLocateEvidence evidence;
    evidence.target = LocateDesktopTarget(target);
    OcrCapability cap = GetOcrCapability();
    evidence.ocrAvailable = cap.available;
    if (evidence.target.ok || !cap.available) {
        if (!cap.available) {
            evidence.ocrErrorCode = L"OCR_UNAVAILABLE";
            evidence.ocrErrorMessage = L"Windows OCR is unavailable in this runtime build or environment.";
        }
        return evidence;
    }

    evidence.ocrAttempted = true;
    RECT virtualRect{
        GetSystemMetrics(SM_XVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN),
        GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
    OcrResult ocr = ReadScreenRegionText(
        virtualRect.left,
        virtualRect.top,
        virtualRect.right - virtualRect.left,
        virtualRect.bottom - virtualRect.top);
    if (!ocr.ok) {
        evidence.ocrErrorCode = ocr.errorCode.empty() ? L"OCR_FAILED" : ocr.errorCode;
        evidence.ocrErrorMessage = ocr.errorMessage;
        return evidence;
    }
    for (const auto& word : ocr.allWords) {
        if (ContainsInsensitive(word.text, target)) {
            evidence.ocrMatched = true;
            evidence.ocrMatchedText = word.text;
            evidence.target.ok = true;
            evidence.target.surface = L"desktop_ocr";
            evidence.target.hwnd = GetDesktopWindow();
            evidence.target.element.name = word.text;
            evidence.target.element.controlType = L"OCRText";
            evidence.target.element.enabled = true;
            evidence.target.element.offscreen = false;
            evidence.target.element.rect = RECT{
                virtualRect.left + word.boundingBox.left,
                virtualRect.top + word.boundingBox.top,
                virtualRect.left + word.boundingBox.right,
                virtualRect.top + word.boundingBox.bottom};
            return evidence;
        }
    }
    evidence.ocrErrorCode = L"OCR_TEXT_NOT_FOUND";
    evidence.ocrErrorMessage = L"OCR did not find a visible desktop label matching the target.";
    return evidence;
}

std::wstring VisibleDesktopLocateEvidenceJson(const VisibleDesktopLocateEvidence& evidence) {
    return L"{\"visible_target\":" + VisiblePrimitiveTargetJson(evidence.target)
        + L",\"ocr_available\":" + std::wstring(evidence.ocrAvailable ? L"true" : L"false")
        + L",\"ocr_attempted\":" + std::wstring(evidence.ocrAttempted ? L"true" : L"false")
        + L",\"ocr_matched\":" + std::wstring(evidence.ocrMatched ? L"true" : L"false")
        + L",\"ocr_matched_text\":" + JsonString(evidence.ocrMatchedText)
        + L",\"ocr_error_code\":" + JsonString(evidence.ocrErrorCode)
        + L",\"ocr_error_message\":" + JsonString(evidence.ocrErrorMessage)
        + L"}";
}

std::wstring StartMenuVisibleLaunchEvidenceJson(const StartMenuVisibleLaunchEvidence& evidence) {
    return L"{\"attempted\":" + std::wstring(evidence.attempted ? L"true" : L"false")
        + L",\"start_button_locate_attempt_count\":" + std::to_wstring(evidence.startButtonLocateAttemptCount)
        + L",\"start_button_click_attempt_count\":" + std::to_wstring(evidence.startButtonClickAttemptCount)
        + L",\"bounded_recovery_attempted\":" + std::wstring(evidence.boundedRecoveryAttempted ? L"true" : L"false")
        + L",\"win_key_fallback_attempted\":" + std::wstring(evidence.winKeyFallbackAttempted ? L"true" : L"false")
        + L",\"search_entry_locate_attempted\":" + std::wstring(evidence.searchEntryLocateAttempted ? L"true" : L"false")
        + L",\"search_entry_click_attempted\":" + std::wstring(evidence.searchEntryClickAttempted ? L"true" : L"false")
        + L",\"search_entry_used\":" + std::wstring(evidence.searchEntryUsed ? L"true" : L"false")
        + L",\"visible_target\":" + VisiblePrimitiveTargetJson(evidence.startButton)
        + L",\"search_entry\":" + VisiblePrimitiveTargetJson(evidence.searchEntry)
        + L",\"start_click_motion\":{" + ClickMotionFields(evidence.startClick) + L"}"
        + L",\"search_entry_click_motion\":{" + ClickMotionFields(evidence.searchEntryClick) + L"}"
        + L",\"shortcut_result\":" + ActionResultJson(evidence.winKey)
        + L",\"clear_search_result\":" + ActionResultJson(evidence.clearSearch)
        + L",\"typed_app\":" + TypeResultJson(evidence.typedApp)
        + L",\"enter_result\":" + ActionResultJson(evidence.enter)
        + L",\"action_sent\":" + std::wstring(evidence.actionSent ? L"true" : L"false")
        + L"}";
}

StartMenuVisibleLaunchEvidence ExecuteStartMenuVisibleLaunchForApp(
    const std::wstring& appName,
    bool dryRun,
    LatencyProfile latencyProfile,
    int requestedMotionHz) {
    StartMenuVisibleLaunchEvidence evidence;
    evidence.attempted = true;
    if (appName.empty()) {
        return evidence;
    }

    bool startOpenedByVisibleClick = false;
    for (int attempt = 0; attempt < 2 && !startOpenedByVisibleClick; ++attempt) {
        ++evidence.startButtonLocateAttemptCount;
        VisiblePrimitiveTarget startButton = LocateTaskbarTarget(L"Start");
        if (!startButton.ok) {
            startButton = LocateTaskbarTarget(L"开始");
        }
        evidence.startButton = startButton;
        if (startButton.ok) {
            ++evidence.startButtonClickAttemptCount;
            if (dryRun) {
                evidence.startClick.ok = true;
                evidence.startClick.humanmode = true;
                evidence.startClick.actionMethod = L"dry_run_start_button_click";
                startOpenedByVisibleClick = true;
                break;
            }
            HumanMouseMotionOptions clickOptions;
            ApplyVisibleLaunchLatencyOptions(clickOptions, latencyProfile, requestedMotionHz);
            evidence.startClick = ClickHumanMode(RectCenterX(startButton.element.rect), RectCenterY(startButton.element.rect), clickOptions);
            startOpenedByVisibleClick = evidence.startClick.ok;
        }
        if (!startOpenedByVisibleClick && attempt == 0) {
            evidence.boundedRecoveryAttempted = true;
            PressKeyGlobal(L"ESC");
            Sleep(200);
        }
    }

    if (!startOpenedByVisibleClick) {
        evidence.searchEntryLocateAttempted = true;
        evidence.searchEntry = LocateTaskbarSearchEntry();
        if (evidence.searchEntry.ok) {
            evidence.searchEntryClickAttempted = true;
            if (dryRun) {
                evidence.searchEntryClick.ok = true;
                evidence.searchEntryClick.humanmode = true;
                evidence.searchEntryClick.actionMethod = L"dry_run_taskbar_search_click";
                startOpenedByVisibleClick = true;
                evidence.searchEntryUsed = true;
            } else {
                HumanMouseMotionOptions clickOptions;
                ApplyVisibleLaunchLatencyOptions(clickOptions, latencyProfile, requestedMotionHz);
                evidence.searchEntryClick = ClickHumanMode(RectCenterX(evidence.searchEntry.element.rect), RectCenterY(evidence.searchEntry.element.rect), clickOptions);
                startOpenedByVisibleClick = evidence.searchEntryClick.ok;
                evidence.searchEntryUsed = evidence.searchEntryClick.ok;
            }
        }
        if (!startOpenedByVisibleClick) {
            evidence.winKeyFallbackAttempted = true;
            if (dryRun) {
                evidence.winKey.ok = true;
            } else {
                evidence.winKey = SendHotkeyGlobal(L"WIN");
            }
        }
    } else {
        Sleep(300);
        evidence.searchEntryLocateAttempted = true;
        evidence.searchEntry = LocateTaskbarSearchEntry();
        if (evidence.searchEntry.ok) {
            evidence.searchEntryClickAttempted = true;
            if (dryRun) {
                evidence.searchEntryClick.ok = true;
                evidence.searchEntryClick.humanmode = true;
                evidence.searchEntryClick.actionMethod = L"dry_run_taskbar_search_click";
                evidence.searchEntryUsed = true;
            } else {
                HumanMouseMotionOptions clickOptions;
                ApplyVisibleLaunchLatencyOptions(clickOptions, latencyProfile, requestedMotionHz);
                evidence.searchEntryClick = ClickHumanMode(RectCenterX(evidence.searchEntry.element.rect), RectCenterY(evidence.searchEntry.element.rect), clickOptions);
                evidence.searchEntryUsed = evidence.searchEntryClick.ok;
            }
        }
    }

    if (dryRun) {
        evidence.typedApp.ok = true;
        evidence.typedApp.textLength = static_cast<int>(appName.size());
        evidence.enter.ok = true;
        evidence.actionSent = true;
        return evidence;
    }

    Sleep(evidence.searchEntryUsed ? 500 : 350);
    evidence.clearSearch = SendHotkeyGlobal(L"CTRL+A");
    if (evidence.clearSearch.ok) {
        PressKeyGlobal(L"BACKSPACE");
        Sleep(120);
    }
    evidence.typedApp = TypeTextGlobal(appName, L"human", -1);
    if (evidence.typedApp.ok) {
        Sleep(1200);
        evidence.enter = PressKeyGlobal(L"ENTER");
    }
    evidence.actionSent = evidence.typedApp.ok && evidence.enter.ok;
    return evidence;
}

bool ProcessIsKnownBrowser(const std::wstring& process) {
    std::wstring lower = ToLowerInvariant(process);
    return lower == L"chrome.exe" || lower == L"msedge.exe";
}

WindowInfo FirstVisibleBrowserWindow() {
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        if (ProcessIsKnownBrowser(ProcessNameForPid(window.pid))) {
            return window;
        }
    }
    return WindowInfo{};
}

int CommandVisibleAppLaunch(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"visible-app-launch";
    std::wstring target;
    std::wstring app;
    std::wstring url;
    std::wstring targetTitle;
    std::wstring process;
    std::wstring motionProfile;
    bool dryRun = false;
    int waitMs = 5000;
    int motionHz = 0;
    LatencyProfile latencyProfile = LatencyProfile::Normal;
    std::wstring latencyProfileError;
    std::wstring parseError;

    ArgValue(argc, argv, L"--target", target);
    ArgValue(argc, argv, L"--app", app);
    ArgValue(argc, argv, L"--url", url);
    ArgValue(argc, argv, L"--target-title", targetTitle);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--motion-profile", motionProfile);
    if (!ArgExists(argc, argv, L"--wait-ms")) {
        waitMs = LatencyProfileDefaultLaunchWaitMs(latencyProfile);
    }
    if (!ParseOptionalBoolArg(argc, argv, L"--dry-run", dryRun, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--wait-ms", waitMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--motion-hz", motionHz, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
    }
    if (!motionProfile.empty() && motionProfile != L"165hz" && motionProfile != L"165hz-visible") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--motion-profile must be 165hz or 165hz-visible when provided.", L"{}", 2);
    }
    int requestedMotionHz = motionHz;
    if ((motionProfile == L"165hz" || motionProfile == L"165hz-visible") && requestedMotionHz == 0) {
        requestedMotionHz = 165;
    }
    if (target.empty() && app.empty() && url.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"visible-app-launch requires --target, --app, or --url.", L"{}", 2);
    }

    std::wstring resolvedTarget = !target.empty() ? target : (!app.empty() ? app : url);
    std::wstring appName = !app.empty() ? app : resolvedTarget;
    std::wstring checkpointId = L"visible-app-launch-pre-" + std::to_wstring(startTick);

    VisibleDesktopSurfaceEvidence desktopSurface = EnsureDesktopSurfaceVisibleForLaunch(checkpointId, dryRun, latencyProfile, requestedMotionHz);
    int desktopLocateAttempts = 0;
    int desktopDoubleClickAttempts = 0;
    bool desktopIconPathUsed = false;
    bool boundedRecoveryAttempted = false;
    VisibleDesktopLocateEvidence desktopLocateFirst;
    VisibleDesktopLocateEvidence desktopLocateSecond;
    ClickResult desktopDoubleClickFirst;
    ClickResult desktopDoubleClickSecond;
    VisibleLaunchVerification verification;
    std::wstring finalMode = L"fail_stop";
    std::wstring visibleFailureReason;

    auto attemptDesktopIconLaunch = [&](VisibleDesktopLocateEvidence& locateEvidence, ClickResult& doubleClickResult) -> bool {
        ++desktopLocateAttempts;
        locateEvidence = LocateDesktopTargetWithSupplementalOcr(resolvedTarget);
        if (!locateEvidence.target.ok) {
            visibleFailureReason = locateEvidence.target.errorCode.empty() ? L"desktop_icon_locate_failed" : locateEvidence.target.errorCode;
            return false;
        }
        ++desktopDoubleClickAttempts;
        int x = RectCenterX(locateEvidence.target.element.rect);
        int y = RectCenterY(locateEvidence.target.element.rect);
        if (dryRun) {
            doubleClickResult.ok = true;
            doubleClickResult.targetScreenX = x;
            doubleClickResult.targetScreenY = y;
            doubleClickResult.actualDoubleClickSent = false;
            doubleClickResult.humanmode = true;
            doubleClickResult.actionMethod = L"dry_run_desktop_icon_double_click";
        } else {
            HumanMouseMotionOptions clickOptions;
            ApplyVisibleLaunchLatencyOptions(clickOptions, latencyProfile, requestedMotionHz);
            doubleClickResult = DoubleClickHumanMode(x, y, clickOptions);
        }
        if (!doubleClickResult.ok) {
            visibleFailureReason = doubleClickResult.errorCode.empty() ? L"desktop_icon_double_click_failed" : doubleClickResult.errorCode;
            return false;
        }
        verification = dryRun
            ? VisibleLaunchVerification{true, false, 1, WindowInfo{}, L"dry_run_target_window", L"", L""}
            : VerifyVisibleLaunchTarget(targetTitle, process, waitMs);
        if (verification.verified) {
            desktopIconPathUsed = true;
            finalMode = L"desktop_icon_visible_mouse_double_click";
            return true;
        }
        visibleFailureReason = verification.errorCode.empty() ? L"target_window_not_verified_after_desktop_double_click" : verification.errorCode;
        return false;
    };

    bool launched = false;
    if (desktopSurface.visibleAfter || dryRun) {
        launched = attemptDesktopIconLaunch(desktopLocateFirst, desktopDoubleClickFirst);
        if (!launched) {
            boundedRecoveryAttempted = true;
            if (!dryRun) {
                PressKeyGlobal(L"ESC");
                Sleep(250);
            }
            desktopSurface = EnsureDesktopSurfaceVisibleForLaunch(checkpointId + L"-retry", dryRun, latencyProfile, requestedMotionHz);
            launched = attemptDesktopIconLaunch(desktopLocateSecond, desktopDoubleClickSecond);
        }
    } else {
        visibleFailureReason = L"desktop_surface_not_visible";
    }

    bool startMenuFallbackAttempted = false;
    bool browserVisibleNavigationFallbackAttempted = false;
    bool backendLaunchUsed = false;
    StartMenuVisibleLaunchEvidence startMenuEvidence;
    TypeResult browserTypedUrl;
    ActionResult browserAddressShortcut;
    ActionResult browserEnter;
    WindowInfo browserWindow;

    if (!launched && !url.empty()) {
        browserVisibleNavigationFallbackAttempted = true;
        browserWindow = FirstVisibleBrowserWindow();
        if (!browserWindow.hwnd && !appName.empty()) {
            startMenuEvidence = ExecuteStartMenuVisibleLaunchForApp(appName, dryRun, latencyProfile, requestedMotionHz);
            if (!dryRun) {
                Sleep(1000);
                browserWindow = FirstVisibleBrowserWindow();
            }
        }
        if (dryRun || browserWindow.hwnd) {
            browserAddressShortcut = dryRun ? ActionResult{} : SendHotkeyGlobal(L"CTRL+L");
            if (dryRun) browserAddressShortcut.ok = true;
            browserTypedUrl = dryRun ? TypeResult{} : TypeTextGlobal(url, L"human", -1);
            if (dryRun) {
                browserTypedUrl.ok = true;
                browserTypedUrl.textLength = static_cast<int>(url.size());
            }
            browserEnter = (browserTypedUrl.ok || dryRun) ? (dryRun ? ActionResult{} : PressKeyGlobal(L"ENTER")) : ActionResult{};
            if (dryRun) browserEnter.ok = true;
            if (browserAddressShortcut.ok && browserTypedUrl.ok && browserEnter.ok) {
                verification = dryRun
                    ? VisibleLaunchVerification{true, false, 1, WindowInfo{}, L"dry_run_target_window", L"", L""}
                    : VerifyVisibleLaunchTarget(targetTitle, process.empty() ? ProcessNameForPid(browserWindow.pid) : process, waitMs);
                if (verification.verified) {
                    launched = true;
                    finalMode = L"browser_visible_navigation_fallback";
                }
            }
        }
    }

    if (!launched && url.empty()) {
        startMenuFallbackAttempted = true;
        startMenuEvidence = ExecuteStartMenuVisibleLaunchForApp(appName, dryRun, latencyProfile, requestedMotionHz);
        if (startMenuEvidence.actionSent) {
            verification = dryRun
                ? VisibleLaunchVerification{true, false, 1, WindowInfo{}, L"dry_run_target_window", L"", L""}
                : VerifyVisibleLaunchTarget(targetTitle, process, waitMs);
            if (verification.verified) {
                launched = true;
                finalMode = L"start_menu_visible_launch_fallback";
            }
        }
    }

    VisibleOperationPolicyOptions priority;
    priority.operationType = url.empty() ? L"app_launch" : L"browser_navigation";
    priority.attempt1Mode = L"desktop_icon_visible_mouse_double_click";
    priority.attempt2Mode = url.empty() ? L"start_menu_visible_launch_fallback" : L"browser_visible_navigation_fallback";
    priority.attempt3Mode = L"backend_launch_fallback";
    priority.visibleMouseKeyboardAttempted = true;
    priority.attempt1Result = desktopIconPathUsed ? L"succeeded" : L"failed";
    priority.attempt1FailureReason = desktopIconPathUsed ? L"" : (visibleFailureReason.empty() ? L"desktop_icon_path_failed" : visibleFailureReason);
    priority.visibleAttemptCount = desktopLocateAttempts;
    priority.preActionCheckpointPresent = true;
    priority.boundedRecoveryAttempted = boundedRecoveryAttempted;
    priority.postRecoveryObserved = boundedRecoveryAttempted && (desktopSurface.visibleAfter || dryRun);
    priority.sameSurfaceAfterRecovery = boundedRecoveryAttempted;
    priority.keyboardShortcutAttempted = startMenuFallbackAttempted || browserVisibleNavigationFallbackAttempted;
    priority.attempt2Result = priority.keyboardShortcutAttempted ? (launched ? L"succeeded" : L"failed") : L"not_attempted";
    priority.attempt2FailureReason = (priority.keyboardShortcutAttempted && !launched) ? (verification.errorCode.empty() ? L"visible_launch_fallback_failed" : verification.errorCode) : L"";
    priority.backendFallbackUsed = backendLaunchUsed;
    priority.backendFallbackKind = backendLaunchUsed ? L"backend_launch" : L"";
    priority.backendFallbackReason = backendLaunchUsed ? L"desktop and visible fallback failed" : L"";
    priority.attempt3Result = backendLaunchUsed ? (launched ? L"succeeded" : L"failed") : L"not_attempted";
    priority.finalModeUsed = launched ? finalMode : L"fail_stop";
    VisibleOperationPolicyResult policy = enforce_visible_operation_priority(priority);

    std::wstring data = std::wstring(L"{\"runtime_visible_first_launch\":true")
        + L",\"launch_strategy\":\"desktop_first\""
        + L",\"target\":" + JsonString(target)
        + L",\"app\":" + JsonString(app)
        + L",\"url\":" + JsonString(url)
        + L",\"resolved_target\":" + JsonString(resolvedTarget)
        + L",\"target_title\":" + JsonString(targetTitle)
        + L",\"process\":" + JsonString(process)
        + L",\"dry_run\":" + std::wstring(dryRun ? L"true" : L"false")
        + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile))
        + L",\"requested_motion_hz\":" + std::to_wstring(requestedMotionHz)
        + L",\"desktop_surface_attempted\":" + std::wstring(desktopSurface.attempted ? L"true" : L"false")
        + L",\"desktop_surface\":" + VisibleDesktopSurfaceEvidenceJson(desktopSurface)
        + L",\"desktop_icon_locate_attempt_count\":" + std::to_wstring(desktopLocateAttempts)
        + L",\"desktop_icon_double_click_attempt_count\":" + std::to_wstring(desktopDoubleClickAttempts)
        + L",\"desktop_icon_path_used\":" + std::wstring(desktopIconPathUsed ? L"true" : L"false")
        + L",\"desktop_locate_attempt_1\":" + VisibleDesktopLocateEvidenceJson(desktopLocateFirst)
        + L",\"desktop_locate_attempt_2\":" + VisibleDesktopLocateEvidenceJson(desktopLocateSecond)
        + L",\"desktop_double_click_attempt_1\":{\"ok\":" + std::wstring(desktopDoubleClickFirst.ok ? L"true" : L"false") + L",\"click_motion\":{" + ClickMotionFields(desktopDoubleClickFirst) + L"}}"
        + L",\"desktop_double_click_attempt_2\":{\"ok\":" + std::wstring(desktopDoubleClickSecond.ok ? L"true" : L"false") + L",\"click_motion\":{" + ClickMotionFields(desktopDoubleClickSecond) + L"}}"
        + L",\"start_menu_fallback_attempted\":" + std::wstring(startMenuFallbackAttempted ? L"true" : L"false")
        + L",\"start_menu_fallback\":" + StartMenuVisibleLaunchEvidenceJson(startMenuEvidence)
        + L",\"browser_visible_navigation_fallback_attempted\":" + std::wstring(browserVisibleNavigationFallbackAttempted ? L"true" : L"false")
        + L",\"browser_visible_navigation_fallback\":{\"address_bar_shortcut\":" + ActionResultJson(browserAddressShortcut)
        + L",\"typed_url\":" + TypeResultJson(browserTypedUrl)
        + L",\"enter_result\":" + ActionResultJson(browserEnter)
        + L",\"browser_window\":" + (browserWindow.hwnd ? LaunchTargetWindowJson(browserWindow) : L"null") + L"}"
        + L",\"backend_launch_used\":" + std::wstring(backendLaunchUsed ? L"true" : L"false")
        + L",\"pre_action_checkpoint_id\":" + JsonString(checkpointId)
        + L",\"bounded_recovery_attempted\":" + std::wstring(boundedRecoveryAttempted ? L"true" : L"false")
        + L",\"target_verification_method\":" + JsonString(verification.method)
        + L",\"target_window_verified\":" + std::wstring(verification.verified ? L"true" : L"false")
        + L",\"target_verification\":" + VisibleLaunchVerificationJson(verification)
        + L",\"vlm_assist_enabled\":false"
        + L",\"vlm_capability_status\":\"VLM_UNKNOWN\""
        + L",\"vlm_session_id\":\"\""
        + L",\"vlm_assist_attempted\":false"
        + L",\"vlm_assist_trigger_reason\":\"not_applicable_desktop_target_located\""
        + L",\"vlm_assist_stage\":\"none\""
        + L",\"vlm_provider\":\"\""
        + L",\"vlm_raw_response_path\":\"\""
        + L",\"vlm_candidate_accepted\":false"
        + L",\"vlm_candidate_rejected_reason\":\"\""
        + L",\"vlm_action_executed\":false"
        + L",\"vlm_after_backend_attempted\":false"
        + L",\"fallback_stage_before_vlm\":\"none\""
        + L",\"fallback_stage_after_vlm\":\"none\""
        + L",\"operation_priority\":" + VisibleOperationPolicyJson(policy)
        + L"}";

    if (!policy.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), policy.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : policy.errorCode, policy.errorMessage, data, 1);
    }
    if (!launched || !verification.verified) {
        std::wstring code = verification.errorCode.empty() ? L"TARGET_WINDOW_NOT_VERIFIED" : verification.errorCode;
        std::wstring message = verification.errorMessage.empty() ? L"visible-app-launch did not verify the requested target window." : verification.errorMessage;
        return EmitFailure(command, startTick, verification.verified ? MakeTraceTarget(verification.targetWindow) : NoTraceTarget(), code, message, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(verification.targetWindow), data);
}

int CommandPyCharmVisibleDemo(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"pycharm-visible-demo";
    PyCharmVisibleWorkflowOptions options;
    ArgValue(argc, argv, L"--project", options.projectDir);
    ArgValue(argc, argv, L"--target-title", options.targetTitle);
    ArgValue(argc, argv, L"--target-process", options.targetProcess);
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--dry-run", options.dryRun, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--performance-acceptance", options.performanceAcceptance, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--target-total-ms", options.targetTotalMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--max-total-ms", options.maxTotalMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    PyCharmVisibleWorkflowResult result = RunPyCharmVisibleWorkflow(options);
    std::wstring data = PyCharmVisibleWorkflowJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"BLOCKED_PYCHARM_TARGET_LOCK_FAILED" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandObserve(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"observe";
    std::wstring title;
    std::wstring hwndArg;
    std::wstring process;
    std::wstring outPath;
    bool includeScreenshot = true;
    bool includeUia = true;
    int maxElements = 80;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--process", process);
    ArgValue(argc, argv, L"--out", outPath);
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--screenshot", includeScreenshot, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--uia", includeUia, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--max-elements", maxElements, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (maxElements < 0 || maxElements > 1000) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--max-elements must be between 0 and 1000.", L"{}", 2);
    }

    WindowInfo selected;
    bool defaultedToActiveWindow = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    ForegroundPreparationResult prep;
    if (title.empty() && hwndArg.empty() && process.empty()) {
        if (outPath.empty()) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"observe requires --title, --hwnd, --process, or --out for active-window default.", WithSuggestedCommand(L"{}", L"observe --title <partial_title>"), 2);
        }
        if (!ResolveActiveWindowForVisibleCommand(command, selected, prep, errorCode, errorMessage, dataJson)) {
            return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
        }
        title = selected.title;
        defaultedToActiveWindow = true;
    } else if (!ResolveWindowByTitleHwndProcess(title, hwndArg, process, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    if (!prep.attempted) {
        prep = PrepareForegroundForVisibleUiTask(selected);
    }
    if (!prep.ok) {
        std::wstring failure = L"{\"defaulted_to_active_window\":" + std::wstring(defaultedToActiveWindow ? L"true" : L"false")
            + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, failure, 1);
    }

    ObserveResult result = ObserveWindow(title, includeScreenshot, includeUia, maxElements);
    if (!result.ok) {
        std::wstring failureData = result.dataJson.empty() ? (L"{\"requested_title\":" + JsonString(title) + L"}") : result.dataJson;
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.errorMessage, failureData, result.errorCode == L"INVALID_ARGUMENT" ? 2 : 1);
    }
    std::wstring successData = MergeObjectField(result.dataJson, L"foreground_preparation", ForegroundPreparationJson(prep));
    successData = successData.substr(0, successData.size() - 1)
        + L",\"defaulted_to_active_window\":" + std::wstring(defaultedToActiveWindow ? L"true" : L"false") + L"}";
    if (!outPath.empty()) {
        WriteSmallTextFile(outPath, CommandSuccessJson(command, startTick, MakeTraceTarget(result.target), successData));
        successData = successData.substr(0, successData.size() - 1) + L",\"out\":" + JsonString(outPath) + L"}";
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(result.target), successData);
}

bool ParseRoiArg(const std::wstring& raw, RECT& roi) {
    int x = 0;
    int y = 0;
    int w = 0;
    int h = 0;
    if (swscanf_s(raw.c_str(), L"%d,%d,%d,%d", &x, &y, &w, &h) != 4) {
        return false;
    }
    if (w <= 0 || h <= 0) {
        return false;
    }
    roi.left = x;
    roi.top = y;
    roi.right = x + w;
    roi.bottom = y + h;
    return true;
}

std::wstring HtmlElementForId(const std::wstring& html, const std::wstring& candidateId) {
    if (candidateId.empty()) return L"";
    std::wstring lower = ToLowerInvariant(html);
    std::wstring id1 = L"id=\"" + ToLowerInvariant(candidateId) + L"\"";
    std::wstring id2 = L"id='" + ToLowerInvariant(candidateId) + L"'";
    size_t pos = lower.find(id1);
    if (pos == std::wstring::npos) pos = lower.find(id2);
    if (pos == std::wstring::npos) return L"";
    size_t start = lower.rfind(L"<", pos);
    size_t end = lower.find(L">", pos);
    if (start == std::wstring::npos || end == std::wstring::npos || end < start) return L"";
    return html.substr(start, end - start + 1);
}

std::wstring HtmlAttrValue(const std::wstring& element, const std::wstring& attr) {
    std::wstring lower = ToLowerInvariant(element);
    std::wstring key = ToLowerInvariant(attr) + L"=";
    size_t pos = lower.find(key);
    if (pos == std::wstring::npos) return L"";
    pos += key.size();
    if (pos >= element.size()) return L"";
    wchar_t quote = element[pos];
    if (quote != L'"' && quote != L'\'') return L"";
    size_t end = element.find(quote, pos + 1);
    if (end == std::wstring::npos) return L"";
    return element.substr(pos + 1, end - pos - 1);
}

bool HtmlElementEnabled(const std::wstring& element) {
    std::wstring lower = ToLowerInvariant(element);
    std::wstring enabled = ToLowerInvariant(HtmlAttrValue(element, L"data-enabled"));
    if (enabled == L"true" || enabled == L"1") return true;
    if (enabled == L"false" || enabled == L"0") return false;
    return lower.find(L"disabled") == std::wstring::npos;
}

bool HtmlElementPosition(const std::wstring& element, int& x, int& y) {
    std::wstring rawX = HtmlAttrValue(element, L"data-x");
    std::wstring rawY = HtmlAttrValue(element, L"data-y");
    if (rawX.empty() || rawY.empty()) return false;
    try {
        x = std::stoi(rawX);
        y = std::stoi(rawY);
        return true;
    } catch (...) {
        return false;
    }
}

std::wstring DetectDynamicSceneState(const std::wstring& html, const std::wstring& riskStatus) {
    std::wstring lower = ToLowerInvariant(html + L" " + riskStatus);
    if (lower.find(L"data-state=\"blocked\"") != std::wstring::npos ||
        lower.find(L"data-risk=\"blocked\"") != std::wstring::npos ||
        lower.find(L"blocked_sensitive") != std::wstring::npos ||
        lower.find(L"captcha") != std::wstring::npos ||
        lower.find(L"anti-cheat") != std::wstring::npos ||
        lower.find(L"credential") != std::wstring::npos ||
        lower.find(L"password") != std::wstring::npos ||
        lower.find(L"payment") != std::wstring::npos) {
        return L"blocked";
    }
    if (lower.find(L"data-state=\"loading\"") != std::wstring::npos ||
        lower.find(L"class=\"spinner\"") != std::wstring::npos ||
        lower.find(L"loading") != std::wstring::npos ||
        lower.find(L"please wait") != std::wstring::npos) {
        return L"loading";
    }
    if (lower.find(L"data-state=\"dialog_open\"") != std::wstring::npos ||
        lower.find(L"role=\"dialog\"") != std::wstring::npos ||
        lower.find(L"data-modal=\"true\"") != std::wstring::npos ||
        lower.find(L"modal") != std::wstring::npos) {
        return L"dialog_open";
    }
    if (lower.find(L"error") != std::wstring::npos ||
        lower.find(L"failed") != std::wstring::npos ||
        lower.find(L"exception") != std::wstring::npos) {
        return L"error";
    }
    if (lower.find(L"success") != std::wstring::npos ||
        lower.find(L"saved") != std::wstring::npos ||
        lower.find(L"passed") != std::wstring::npos) {
        return L"success";
    }
    if (lower.find(L"<button") != std::wstring::npos ||
        lower.find(L"<input") != std::wstring::npos ||
        lower.find(L"data-ready=\"true\"") != std::wstring::npos) {
        return L"normal";
    }
    return L"unknown";
}

std::wstring RecoveryStrategyJsonForScene(const std::wstring& state) {
    if (state == L"loading") {
        return L"{\"strategy_name\":\"loading_wait_observe_loop\",\"steps\":[\"wait\",\"observe-loop\",\"loading_finished_or_timeout\"],\"requires_agent\":false,\"requires_human\":false,\"terminal\":false}";
    }
    if (state == L"dialog_open") {
        return L"{\"strategy_name\":\"classify_dialog_safe_route\",\"steps\":[\"classify_dialog\",\"do_not_click_underlay\",\"require_safe_route\"],\"requires_agent\":true,\"requires_human\":true,\"terminal\":false}";
    }
    if (state == L"error") {
        return L"{\"strategy_name\":\"error_stop_or_escalate_by_risk\",\"steps\":[\"record_error\",\"stop_or_escalate\"],\"requires_agent\":true,\"requires_human\":false,\"terminal\":false}";
    }
    if (state == L"success") {
        return L"{\"strategy_name\":\"success_target_ready\",\"steps\":[\"record_success\",\"target_ready\"],\"requires_agent\":false,\"requires_human\":false,\"terminal\":false}";
    }
    if (state == L"blocked") {
        return L"{\"strategy_name\":\"blocked_stop_immediately\",\"steps\":[\"stop\"],\"requires_agent\":false,\"requires_human\":false,\"terminal\":true}";
    }
    if (state == L"unknown") {
        return L"{\"strategy_name\":\"unknown_require_confirmation\",\"steps\":[\"stop_auto_execute\",\"require_human_confirmation\"],\"requires_agent\":true,\"requires_human\":true,\"terminal\":false}";
    }
    return L"{\"strategy_name\":\"normal_target_ready\",\"steps\":[\"target_ready\"],\"requires_agent\":false,\"requires_human\":false,\"terminal\":false}";
}

std::wstring DynamicActionDecision(
    const std::wstring& state,
    const std::wstring& candidateSource,
    const std::wstring& semanticStatus,
    const std::wstring& riskStatus) {
    std::wstring lowerRisk = ToLowerInvariant(riskStatus);
    std::wstring lowerSource = ToLowerInvariant(candidateSource);
    std::wstring lowerSemantic = ToLowerInvariant(semanticStatus);
    if (state == L"blocked" || lowerRisk.find(L"blocked") != std::wstring::npos || lowerRisk.find(L"sensitive") != std::wstring::npos) {
        return L"STOP";
    }
    if ((lowerSource == L"visual" || lowerSource == L"image_template" || lowerSource == L"visual_only") && lowerSemantic != L"resolved") {
        return L"STOP";
    }
    if (lowerSemantic != L"resolved") {
        return L"ESCALATE_TO_VLM";
    }
    if (state == L"dialog_open" || state == L"loading" || state == L"unknown") {
        return L"REQUIRE_HUMAN_CONFIRMATION";
    }
    if (state == L"error") {
        return L"STOP";
    }
    return L"AUTO_EXECUTE";
}

std::wstring DynamicRouterJson(
    const std::wstring& state,
    const std::wstring& candidateSource,
    const std::wstring& semanticStatus,
    const std::wstring& riskStatus,
    const std::wstring& decision) {
    std::wstring perception = (state == L"normal" || state == L"success") ? L"AUTO_EXECUTE" :
        (state == L"blocked" || state == L"error" ? L"STOP" : L"REQUIRE_HUMAN_CONFIRMATION");
    std::wstring semantic = ToLowerInvariant(semanticStatus) == L"resolved" ? L"AUTO_EXECUTE" : L"ESCALATE_TO_VLM";
    std::wstring risk = (decision == L"STOP" && (state == L"blocked" || ToLowerInvariant(riskStatus).find(L"blocked") != std::wstring::npos)) ? L"STOP" : L"AUTO_EXECUTE";
    return L"{\"perception_router\":{\"route\":" + JsonString(perception) + L",\"state\":" + JsonString(state) + L"}"
        + L",\"semantic_resolver\":{\"route\":" + JsonString(semantic) + L",\"semantic_status\":" + JsonString(semanticStatus) + L",\"candidate_source\":" + JsonString(candidateSource) + L"}"
        + L",\"risk_router\":{\"route\":" + JsonString(risk) + L",\"risk_status\":" + JsonString(riskStatus) + L"}"
        + L",\"action_executor_gate\":{\"route\":" + JsonString(decision) + L",\"unresolved_visual_blocked\":"
        + std::wstring((decision == L"STOP" && ToLowerInvariant(semanticStatus) != L"resolved") ? L"true" : L"false") + L"}}";
}

std::wstring DynamicEventsJson(
    const std::wstring& state,
    const std::wstring& previousState,
    const std::wstring& html,
    const std::wstring& previousHtml,
    const std::wstring& candidateId) {
    std::vector<std::wstring> events;
    if (state == L"loading" && previousState != L"loading") events.push_back(L"loading_started");
    if (previousState == L"loading" && state != L"loading") events.push_back(L"loading_finished");
    if (state == L"dialog_open" && previousState != L"dialog_open") events.push_back(L"dialog_opened");
    if (previousState == L"dialog_open" && state != L"dialog_open") events.push_back(L"dialog_closed");
    if (state == L"error") events.push_back(L"error_appeared");
    if (state == L"success") events.push_back(L"success_appeared");
    if (state == L"normal" || state == L"success") events.push_back(L"target_ready");

    std::wstring currentElement = HtmlElementForId(html, candidateId);
    std::wstring previousElement = HtmlElementForId(previousHtml, candidateId);
    if (!currentElement.empty() && !previousElement.empty()) {
        int currentX = 0, currentY = 0, previousX = 0, previousY = 0;
        if (HtmlElementPosition(currentElement, currentX, currentY) && HtmlElementPosition(previousElement, previousX, previousY) &&
            (currentX != previousX || currentY != previousY)) {
            events.push_back(L"element_moved");
        }
        bool currentEnabled = HtmlElementEnabled(currentElement);
        bool previousEnabled = HtmlElementEnabled(previousElement);
        if (currentEnabled && !previousEnabled) events.push_back(L"element_enabled");
        if (!currentEnabled && previousEnabled) events.push_back(L"element_disabled");
    }

    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < events.size(); ++i) {
        if (i != 0) json << L",";
        json << L"{\"type\":" << JsonString(events[i]) << L",\"source\":\"dynamic_ui_recovery\"}";
    }
    json << L"]";
    return json.str();
}

int CommandDynamicUiRecovery(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"dynamic-ui-recovery";
    std::wstring htmlPath;
    std::wstring previousHtmlPath;
    std::wstring candidateId;
    std::wstring candidateSource = L"uia";
    std::wstring semanticStatus = L"resolved";
    std::wstring riskStatus = L"normal";
    if (!ArgValue(argc, argv, L"--html", htmlPath)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"dynamic-ui-recovery requires --html.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--previous-html", previousHtmlPath);
    ArgValue(argc, argv, L"--candidate-id", candidateId);
    ArgValue(argc, argv, L"--candidate-source", candidateSource);
    ArgValue(argc, argv, L"--semantic-status", semanticStatus);
    ArgValue(argc, argv, L"--risk-status", riskStatus);

    std::wstring normalizedPath;
    std::wstring safetyError;
    if (!IsReadPathAllowed(htmlPath, normalizedPath, safetyError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"SAFETY_POLICY_DENIED", safetyError, L"{\"html\":" + JsonString(htmlPath) + L"}", 1);
    }
    FileReadResult currentRead = ReadTextFile(normalizedPath);
    if (!currentRead.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), currentRead.errorCode.empty() ? L"FILE_READ_FAILED" : currentRead.errorCode, currentRead.error, L"{\"html\":" + JsonString(normalizedPath) + L"}", 1);
    }

    std::wstring previousHtml;
    std::wstring normalizedPrevious;
    if (!previousHtmlPath.empty()) {
        if (!IsReadPathAllowed(previousHtmlPath, normalizedPrevious, safetyError)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"SAFETY_POLICY_DENIED", safetyError, L"{\"previous_html\":" + JsonString(previousHtmlPath) + L"}", 1);
        }
        FileReadResult previousRead = ReadTextFile(normalizedPrevious);
        if (!previousRead.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), previousRead.errorCode.empty() ? L"FILE_READ_FAILED" : previousRead.errorCode, previousRead.error, L"{\"previous_html\":" + JsonString(normalizedPrevious) + L"}", 1);
        }
        previousHtml = previousRead.content;
    }

    std::wstring state = DetectDynamicSceneState(currentRead.content, riskStatus);
    std::wstring previousState = previousHtml.empty() ? L"unknown" : DetectDynamicSceneState(previousHtml, L"normal");
    std::wstring decision = DynamicActionDecision(state, candidateSource, semanticStatus, riskStatus);
    std::wstring events = DynamicEventsJson(state, previousState, currentRead.content, previousHtml, candidateId);
    std::wstring routers = DynamicRouterJson(state, candidateSource, semanticStatus, riskStatus, decision);

    std::wstring data = std::wstring(L"{\"schema_version\":\"4.4.0\"")
        + L",\"html\":" + JsonString(normalizedPath)
        + L",\"previous_html\":" + JsonString(normalizedPrevious)
        + L",\"scene_state\":{\"status\":" + JsonString(state) + L",\"previous_status\":" + JsonString(previousState) + L"}"
        + L",\"change_events\":" + events
        + L",\"dynamic_recovery\":" + RecoveryStrategyJsonForScene(state)
        + L",\"routers\":" + routers
        + L",\"action_decision\":" + JsonString(decision)
        + L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandObserveLoop(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"observe-loop";
    ObserveLoopOptions options;
    std::wstring roiRaw;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--title", options.title)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"observe-loop requires --title.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--process", options.process);
    ArgValue(argc, argv, L"--out", options.eventsPath);
    ArgValue(argc, argv, L"--report", options.reportPath);
    ArgValue(argc, argv, L"--stop-file", options.stopFilePath);
    if (ArgValue(argc, argv, L"--roi", roiRaw)) {
        options.hasRoi = ParseRoiArg(roiRaw, options.roi);
        if (!options.hasRoi) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--roi must be x,y,w,h with positive width and height.", L"{}", 2);
        }
    }
    options.changedRegionsOnly = ArgExists(argc, argv, L"--changed-regions-only");
    if (!ParseOptionalIntArg(argc, argv, L"--interval-ms", options.intervalMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--max-duration-ms", options.maxDurationMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--max-events", options.maxEvents, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--max-no-change-rounds", options.maxNoChangeRounds, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--debounce-ms", options.debounceMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    ObserveLoopResult loop = ObserveLoop(options);
    if (!loop.ok) {
        std::wstring failureData = loop.dataJson.empty() ? (L"{\"requested_title\":" + JsonString(options.title) + L"}") : loop.dataJson;
        return EmitFailure(command, startTick, loop.target.hwnd ? MakeTraceTarget(loop.target) : NoTraceTarget(), loop.errorCode.empty() ? L"UNKNOWN_ERROR" : loop.errorCode, loop.errorMessage, failureData, loop.errorCode == L"INVALID_ARGUMENT" ? 2 : 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(loop.target), loop.dataJson);
}

int CommandObserve2(int argc, wchar_t** argv) {
    if (ArgExists(argc, argv, L"--loop")) {
        return CommandObserveLoop(argc, argv);
    }
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"observe2";
    Observe2Options options;
    options.includeScreenshot = ArgExists(argc, argv, L"--screenshot");
    options.includeUia = true;
    if (!ArgValue(argc, argv, L"--title", options.title)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"observe2 requires --title.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--process", options.process);
    ArgValue(argc, argv, L"--image-template", options.imageTemplatePath);
    if (ArgExists(argc, argv, L"--no-uia")) {
        options.includeUia = false;
    }
    if (ArgExists(argc, argv, L"--include-uia")) {
        options.includeUia = true;
    }

    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--max-elements", options.maxElements, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--tolerance", options.imageTolerance, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    Observe2Result result = Observe2(options);
    if (!result.ok) {
        std::wstring failureData = result.dataJson.empty() ? (L"{\"requested_title\":" + JsonString(options.title) + L"}") : result.dataJson;
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.errorMessage, failureData, result.errorCode == L"INVALID_ARGUMENT" ? 2 : 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(result.target), result.dataJson);
}

int CommandLocate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"locate";
    std::wstring title;
    std::wstring selector;
    std::wstring profileName;
    std::wstring profileLocatorName;
    ArgValue(argc, argv, L"--selector", selector);
    ArgValue(argc, argv, L"--profile", profileName);
    ArgValue(argc, argv, L"--profile-locator", profileLocatorName);
    if (!ArgValue(argc, argv, L"--title", title) || (selector.empty() && (profileName.empty() || profileLocatorName.empty()))) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"locate requires --title and --selector, or --title with --profile and --profile-locator.", L"{}", 2);
    }

    std::wstring profileCandidateJson;
    if (selector.empty()) {
        AppProfile profile;
        ProfileLocator locator;
        std::wstring profileError;
        if (!ResolveProfileLocator(profileName, profileLocatorName, profile, locator, profileError)) {
            std::wstring data = L"{\"profile\":" + JsonString(profileName)
                + L",\"profile_locator\":" + JsonString(profileLocatorName) + L"}";
            return EmitFailure(command, startTick, NoTraceTarget(), L"PROFILE_LOCATOR_NOT_FOUND", profileError, data, 2);
        }
        selector = locator.selector;
        profileCandidateJson = ProfileLocatorCandidateJson(profile, locator);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (selector.rfind(L"text:", 0) == 0 && !EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    SelectorResult located = LocateSelector(selected.hwnd, selector);
    if (!located.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), located.errorCode.empty() ? L"UNKNOWN_ERROR" : located.errorCode, located.errorMessage, located.dataJson, located.errorCode == L"INVALID_SELECTOR" ? 2 : 1);
    }
    std::wstring data = located.dataJson;
    if (!profileCandidateJson.empty() && data.size() >= 1 && data.back() == L'}') {
        data = data.substr(0, data.size() - 1) + L",\"profile_candidate\":" + profileCandidateJson + L"}";
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandProfileReport(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"profile-report";
    std::wstring path;
    ArgValue(argc, argv, L"--path", path);
    if (!path.empty()) {
        DWORD attrs = GetFileAttributesW(path.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES) {
            std::wstring data = L"{\"path\":" + JsonString(path) + L"}";
            return EmitFailure(command, startTick, NoTraceTarget(), L"PROFILE_PATH_NOT_FOUND", L"Profile path was not found.", data, 2);
        }
    }
    ProfileLoadReport report = LoadAppProfiles(path);
    return EmitSuccess(command, startTick, NoTraceTarget(), ProfileLoadReportJson(report));
}

int CommandTargetSemanticsGuardCheck(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"target-semantics-guard-check";
    std::wstring parseError;
    TargetSemanticsSpec spec = ParseTargetSemanticsSpecFromArgs(argc, argv, parseError);
    if (!parseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    TargetSemanticsContext context = ParseTargetSemanticsContextFromArgs(argc, argv);
    TargetSemanticsGuardResult result = EvaluateTargetSemanticsGuard(spec, context);
    PersistTargetSemanticsGuardResult(spec, result, command, false);
    std::wstring data = L"{\"target_semantics_guard\":" + TargetSemanticsGuardResultJson(result) + L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.stopCode, result.reason, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandClassifyExecutionOutput(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"classify-execution-output";
    std::wstring profile;
    std::wstring beforePath;
    std::wstring afterPath;
    std::wstring resultJsonPath;
    std::wstring startMarker;
    std::wstring endMarker;
    ArgValue(argc, argv, L"--profile", profile);
    ArgValue(argc, argv, L"--before", beforePath);
    ArgValue(argc, argv, L"--after", afterPath);
    ArgValue(argc, argv, L"--result-json", resultJsonPath);
    ArgValue(argc, argv, L"--expected-start-marker", startMarker);
    ArgValue(argc, argv, L"--expected-end-marker", endMarker);
    if (afterPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"classify-execution-output requires --after.", L"{}", 2);
    }
    ExecutionOutcomeInput input;
    input.profile = profile.empty() ? L"python" : profile;
    input.beforeText = beforePath.empty() ? L"" : ReadSmallTextFile(beforePath);
    input.afterText = ReadSmallTextFile(afterPath);
    if (!startMarker.empty()) input.expectedStartMarker = startMarker;
    if (!endMarker.empty()) input.expectedEndMarker = endMarker;
    ExecutionOutcome outcome = ClassifyExecutionOutcome(input);
    std::wstring outcomeJson = ExecutionOutcomeJson(outcome);
    if (!resultJsonPath.empty()) {
        WriteSmallTextFile(resultJsonPath, outcomeJson);
    }
    std::wstring data = L"{\"execution_outcome\":" + outcomeJson
        + L",\"profile\":" + JsonString(input.profile)
        + L",\"before\":" + JsonString(beforePath)
        + L",\"after\":" + JsonString(afterPath)
        + L",\"result_json\":" + JsonString(resultJsonPath)
        + L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandStepCompletionEvaluate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"step-completion-evaluate";
    std::wstring inputJsonPath;
    std::wstring resultJsonPath;
    ArgValue(argc, argv, L"--input-json", inputJsonPath);
    ArgValue(argc, argv, L"--result-json", resultJsonPath);
    if (inputJsonPath.empty() || resultJsonPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-completion-evaluate requires --input-json and --result-json.", L"{}", 2);
    }
    if (GetFileAttributesW(inputJsonPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        std::wstring data = L"{\"input_json\":" + JsonString(inputJsonPath)
            + L",\"result_json\":" + JsonString(resultJsonPath)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"FILE_NOT_FOUND", L"StepCompletionGate input JSON was not found.", data, 2);
    }

    std::wstring inputJson = ReadSmallTextFile(inputJsonPath);
    if (inputJson.empty()) {
        std::wstring data = L"{\"input_json\":" + JsonString(inputJsonPath)
            + L",\"result_json\":" + JsonString(resultJsonPath)
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"StepCompletionGate input JSON was empty or unreadable.", data, 2);
    }

    StepCompletionInput input = ParseStepCompletionInputJson(inputJson);
    StepCompletionResult result = EvaluateStepCompletionGate(input);
    result.evidencePath = resultJsonPath;
    std::wstring resultJson = StepCompletionResultJson(result);
    WriteSmallTextFile(resultJsonPath, resultJson);

    std::wstring data = L"{\"step_completion_result\":" + resultJson
        + L",\"input_json\":" + JsonString(inputJsonPath)
        + L",\"result_json\":" + JsonString(resultJsonPath)
        + L"}";
    if (!result.stepVerified || !result.nextStepAllowed) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.stopCode, result.reason, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

std::wstring DefaultVLMAssistedObserveJson(
    const std::wstring& windowTitle,
    const std::wstring& processName,
    const RECT& windowRect,
    const std::wstring& screenshotPath,
    const std::wstring& targetLabel,
    bool staleObserve = false,
    bool activeProtection = false,
    bool credentialRequired = false,
    bool includeRoi = false) {
    std::wstring label = targetLabel.empty() ? L"Submit" : targetLabel;
    bool testWindowClickMe = ContainsInsensitive(label, L"Click Me");
    std::wstring runtimeLabel = testWindowClickMe ? label : L"Submit";
    std::wstring uia = runtimeLabel + L" button, Email field, Result area";
    std::wstring ocr = L"DesktopVisual Mock " + runtimeLabel + L" Email Result";
    std::wstringstream json;
    json << L"{\"ok\":true"
         << L",\"command\":\"observe\""
         << L",\"data\":{"
         << L"\"target_window\":{\"hwnd\":\"0x0000000000012345\",\"title\":" << JsonString(windowTitle.empty() ? L"DesktopVisual Mock Window" : windowTitle)
         << L",\"process_name\":" << JsonString(processName.empty() ? L"mock.exe" : processName)
         << L",\"rect\":" << RectJson(windowRect) << L"}"
         << L",\"screen_bounds\":{\"left\":0,\"top\":0,\"right\":1920,\"bottom\":1080}"
         << L",\"screenshot\":{\"path\":" << JsonString(screenshotPath) << L",\"method\":\"mock\"}"
         << L",\"uia_text_summary\":" << JsonString(uia)
         << L",\"ocr_text_summary\":" << JsonString(ocr)
         << L",\"visible_text_hash\":\"hash-v66-default\""
         << L",\"element_summary\":["
         << L"{\"element_id\":\"uia-target\",\"label\":" << JsonString(runtimeLabel)
         << L",\"role\":\"Button\",\"text\":" << JsonString(runtimeLabel)
         << L",\"bounds\":{\"left\":60,\"top\":70,\"right\":180,\"bottom\":106}},"
         << L"{\"element_id\":\"uia-submit\",\"label\":\"Submit\",\"role\":\"Button\",\"text\":\"Submit\",\"bounds\":{\"left\":130,\"top\":240,\"right\":230,\"bottom\":280}}]"
         << L",\"stale_observe\":" << (staleObserve ? L"true" : L"false")
         << L",\"active_protection_detected\":" << (activeProtection ? L"true" : L"false")
         << L",\"credential_required_detected\":" << (credentialRequired ? L"true" : L"false");
    if (includeRoi) {
        json << L",\"screenshot_region\":{\"left\":120,\"top\":150,\"right\":520,\"bottom\":360}";
    }
    json << L"}}";
    return json.str();
}

std::wstring ResolveVLMAssistedEvidenceDir(const std::wstring& explicitDir, const std::wstring& command) {
    if (!explicitDir.empty()) return explicitDir;
    return ProjectPath(L"artifacts\\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling\\raw\\" + command);
}

bool LegacyMockVlmAllowed(int argc, wchar_t** argv) {
    std::wstring allow;
    if (ArgValue(argc, argv, L"--allow-legacy-mock-vlm", allow)) {
        std::wstring lower = ToLowerInvariant(allow);
        if (lower == L"1" || lower == L"true" || lower == L"yes") {
            return true;
        }
    }
    wchar_t env[16] = {};
    DWORD len = GetEnvironmentVariableW(L"DESKTOPVISUAL_ENABLE_LEGACY_MOCK_VLM", env, static_cast<DWORD>(sizeof(env) / sizeof(env[0])));
    if (len == 0) return false;
    std::wstring lower = ToLowerInvariant(env);
    return lower == L"1" || lower == L"true" || lower == L"yes";
}

std::wstring LegacyMockVlmDisabledData(const std::wstring& command) {
    return L"{\"legacy_mock_vlm\":true"
        L",\"real_vlm\":false"
        L",\"not_for_agent_workflow\":true"
        L",\"deprecated_command\":" + JsonString(command) +
        L",\"use_real_vlm_runtime_bridge\":true"
        L",\"recommended_commands\":[\"vlm-capability-probe\",\"vlm-assist-locate\",\"vlm-candidate-validate\"]"
        L",\"replacement_path\":\"RealVlmRuntimeBridge\""
        L"}";
}

int EmitLegacyMockVlmDisabled(const std::wstring& command, ULONGLONG startTick, const std::wstring& hint) {
    std::wstring message = L"Legacy mock VLM command is disabled by default. Use vlm-capability-probe, vlm-assist-locate, and vlm-candidate-validate through RealVlmRuntimeBridge.";
    if (!hint.empty()) {
        message += L" " + hint;
    }
    message += L" Historical tests may pass --allow-legacy-mock-vlm true or set DESKTOPVISUAL_ENABLE_LEGACY_MOCK_VLM=1.";
    return EmitFailure(command, startTick, NoTraceTarget(), L"LEGACY_MOCK_VLM_DEPRECATED", message, LegacyMockVlmDisabledData(command), 1);
}

VLMCandidateBridgeResult RunVLMAssistedBridgeFromArgs(
    const std::wstring& command,
    int argc,
    wchar_t** argv,
    const std::wstring& defaultScenario,
    const std::wstring& defaultTitle,
    const RECT& defaultWindowRect,
    std::wstring& errorCode,
    std::wstring& errorMessage) {
    std::wstring target;
    std::wstring provider = L"mock";
    std::wstring scenario = defaultScenario.empty() ? L"valid" : defaultScenario;
    std::wstring observePath;
    std::wstring screenshotPath;
    std::wstring expectedContext;
    std::wstring evidenceDir;
    bool staleObserve = false;
    bool activeProtection = false;
    bool credentialRequired = false;
    bool includeRoi = false;
    std::wstring rawBool;

    ArgValue(argc, argv, L"--target", target);
    ArgValue(argc, argv, L"--provider", provider);
    ArgValue(argc, argv, L"--scenario", scenario);
    ArgValue(argc, argv, L"--observe-json", observePath);
    ArgValue(argc, argv, L"--screenshot", screenshotPath);
    ArgValue(argc, argv, L"--expected-context", expectedContext);
    ArgValue(argc, argv, L"--evidence-dir", evidenceDir);
    if (ArgValue(argc, argv, L"--stale-observe", rawBool)) staleObserve = (rawBool == L"true" || rawBool == L"1");
    if (ArgValue(argc, argv, L"--active-protection", rawBool)) activeProtection = (rawBool == L"true" || rawBool == L"1");
    if (ArgValue(argc, argv, L"--credential-required", rawBool)) credentialRequired = (rawBool == L"true" || rawBool == L"1");
    if (ArgValue(argc, argv, L"--roi", rawBool)) includeRoi = (rawBool == L"true" || rawBool == L"1");

    VLMCandidateBridgeOptions options;
    options.locateFailed = true;
    options.locateFailedReason = L"LOCATOR_NOT_FOUND";
    options.provider = provider.empty() ? L"mock" : provider;
    options.scenario = scenario.empty() ? L"valid" : scenario;
    options.targetLabel = target;
    options.expectedContext = expectedContext.empty() ? defaultTitle : expectedContext;
    options.screenshotPath = screenshotPath;
    options.evidenceDir = ResolveVLMAssistedEvidenceDir(evidenceDir, command);

    if (options.targetLabel.empty()) {
        errorCode = L"INVALID_ARGUMENT";
        errorMessage = command + L" requires --target.";
        return VLMCandidateBridgeResult{};
    }

    if (!observePath.empty()) {
        options.observeJson = ReadSmallTextFile(observePath);
        if (options.observeJson.empty()) {
            errorCode = L"FILE_READ_FAILED";
            errorMessage = L"Could not read --observe-json.";
            return VLMCandidateBridgeResult{};
        }
    } else {
        if (options.screenshotPath.empty()) {
            options.screenshotPath = options.evidenceDir + L"\\mock_screen.bmp";
            WriteSmallTextFile(options.screenshotPath, L"");
        }
        options.observeJson = DefaultVLMAssistedObserveJson(
            defaultTitle,
            L"mock.exe",
            defaultWindowRect,
            options.screenshotPath,
            options.targetLabel,
            staleObserve,
            activeProtection,
            credentialRequired,
            includeRoi);
    }

    errorCode.clear();
    errorMessage.clear();
    return RunVLMCandidateBridge(options);
}

int EmitVLMAssistedLocateResult(
    const std::wstring& command,
    ULONGLONG startTick,
    const VLMCandidateBridgeResult& bridge,
    const std::wstring& resultPath,
    bool runtimeExecuted,
    bool mouseClickSent,
    bool guardUsed,
    bool postVerified,
    const std::wstring& actionEvidenceJson,
    const TraceTarget& target = NoTraceTarget()) {
    std::wstring payload = VLMAssistedLocatePayloadJson(
        bridge,
        runtimeExecuted,
        mouseClickSent,
        guardUsed,
        postVerified,
        actionEvidenceJson.empty() ? L"null" : actionEvidenceJson);
    if (!resultPath.empty()) {
        WriteSmallTextFile(resultPath, payload);
    }
    if (!bridge.runtimeExecutionAllowed && !runtimeExecuted) {
        std::wstring code = bridge.rejectionReasons.empty() ? L"VLM_ASSISTED_LOCATE_FAILED" : bridge.rejectionReasons.front();
        return EmitFailure(command, startTick, target, code, bridge.runtimeExecutionReason, payload, 1);
    }
    return EmitSuccess(command, startTick, target, payload);
}

int CommandVLMAssistedLocateDryRun(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-assisted-locate-dry-run";
    if (!LegacyMockVlmAllowed(argc, argv)) {
        return EmitLegacyMockVlmDisabled(command, startTick, L"Use the real VLM bridge locate-only path instead of legacy dry-run mock fixtures.");
    }
    std::wstring resultPath;
    ArgValue(argc, argv, L"--result", resultPath);
    if (resultPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"vlm-assisted-locate-dry-run requires --result.", L"{}", 2);
    }
    RECT windowRect = {100, 120, 900, 720};
    std::wstring errorCode;
    std::wstring errorMessage;
    VLMCandidateBridgeResult bridge = RunVLMAssistedBridgeFromArgs(command, argc, argv, L"valid", L"DesktopVisual Mock Window", windowRect, errorCode, errorMessage);
    if (!errorCode.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, L"{}", errorCode == L"INVALID_ARGUMENT" ? 2 : 1);
    }
    return EmitVLMAssistedLocateResult(command, startTick, bridge, resultPath, false, false, false, false, L"null");
}

int CommandVLMAssistedLocate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-assisted-locate";
    if (!LegacyMockVlmAllowed(argc, argv)) {
        return EmitLegacyMockVlmDisabled(command, startTick, L"The replacement locate command is vlm-assist-locate.");
    }
    std::wstring resultPath;
    ArgValue(argc, argv, L"--result", resultPath);
    if (resultPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"vlm-assisted-locate requires --result.", L"{}", 2);
    }
    RECT windowRect = {100, 120, 900, 720};
    std::wstring errorCode;
    std::wstring errorMessage;
    VLMCandidateBridgeResult bridge = RunVLMAssistedBridgeFromArgs(command, argc, argv, L"valid", L"DesktopVisual Mock Window", windowRect, errorCode, errorMessage);
    if (!errorCode.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, L"{}", errorCode == L"INVALID_ARGUMENT" ? 2 : 1);
    }
    return EmitVLMAssistedLocateResult(command, startTick, bridge, resultPath, false, false, false, false, L"null");
}

int CommandVLMAssistedLocateAndClickLocalSafe(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-assisted-locate-and-click-local-safe";
    if (!LegacyMockVlmAllowed(argc, argv)) {
        return EmitLegacyMockVlmDisabled(command, startTick, L"Locate-and-click legacy mock commands are not valid real VLM workflows; use vlm-assist-locate plus Runtime-owned action planning.");
    }
    std::wstring resultPath;
    std::wstring title = L"Agent Test Window";
    std::wstring expectedMarker;
    std::wstring verificationFile = L"D:\\testrepo\\testwindow\\runtime\\state.txt";
    std::wstring moveMode = L"human";
    ArgValue(argc, argv, L"--result", resultPath);
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--expected-marker", expectedMarker);
    ArgValue(argc, argv, L"--verification-file", verificationFile);
    ArgValue(argc, argv, L"--move-mode", moveMode);
    if (resultPath.empty() || expectedMarker.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"vlm-assisted-locate-and-click-local-safe requires --expected-marker and --result.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RECT client = {};
    GetClientRect(selected.hwnd, &client);
    RECT windowRect = selected.rect;
    std::wstring bridgeErrorCode;
    std::wstring bridgeErrorMessage;
    VLMCandidateBridgeResult bridge = RunVLMAssistedBridgeFromArgs(command, argc, argv, L"testwindow_click_me", selected.title, windowRect, bridgeErrorCode, bridgeErrorMessage);
    if (!bridgeErrorCode.empty()) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), bridgeErrorCode, bridgeErrorMessage, L"{}", bridgeErrorCode == L"INVALID_ARGUMENT" ? 2 : 1);
    }
    if (!bridge.runtimeExecutionAllowed || !bridge.locatorCandidate.created) {
        return EmitVLMAssistedLocateResult(command, startTick, bridge, resultPath, false, false, false, false, L"null", MakeTraceTarget(selected));
    }

    ActionResult focused = FocusTargetWindow(selected.hwnd);
    if (!focused.ok) {
        std::wstring actionEvidence = L"{\"focus_ok\":false,\"error_code\":" + JsonString(focused.errorCode) + L",\"error\":" + JsonString(focused.error) + L"}";
        std::wstring payload = VLMAssistedLocatePayloadJson(bridge, false, false, false, false, actionEvidence);
        WriteSmallTextFile(resultPath, payload);
        return EmitFailure(command, startTick, MakeTraceTarget(selected), focused.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focused.errorCode, focused.error, payload, 1);
    }

    RuntimeTargetContext guardTarget;
    guardTarget.hasTargetRect = true;
    guardTarget.targetRect = bridge.locatorCandidate.targetRect;
    guardTarget.targetFromCurrentObserve = true;
    guardTarget.targetUnique = true;
    guardTarget.targetInsideViewport = true;
    ExpectedContextSpec guardSpec;
    guardSpec.enabled = true;
    guardSpec.expectedTitlePattern = selected.title;
    guardSpec.requireTargetRect = true;
    guardSpec.requireTargetFromCurrentObserve = true;
    guardSpec.requireTargetUnique = true;
    guardSpec.requireTargetInsideViewport = true;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(guardSpec, guardTarget);
    PersistRuntimeContextGuardResult(guardSpec, guard, command, false);
    if (!guard.ok) {
        std::wstring actionEvidence = L"{\"runtime_context_guard_used\":true,\"context_guard_result\":" + RuntimeContextGuardResultJson(guard) + L",\"mouse_click_sent\":false}";
        std::wstring payload = VLMAssistedLocatePayloadJson(bridge, false, false, true, false, actionEvidence);
        WriteSmallTextFile(resultPath, payload);
        return EmitFailure(command, startTick, MakeTraceTarget(selected), guard.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guard.stopCode, guard.reason, payload, 1);
    }

    int clientX = bridge.locatorCandidate.targetCenterX;
    int clientY = bridge.locatorCandidate.targetCenterY;
    ClickResult clicked = ClickClientPoint(selected.hwnd, clientX, clientY, moveMode, 0);
    PersistRuntimeContextGuardResult(guardSpec, guard, command, true);
    bool postVerified = false;
    Sleep(250);
    std::wstring stateText = ReadSmallTextFile(verificationFile);
    postVerified = !expectedMarker.empty() && stateText.find(expectedMarker) != std::wstring::npos;

    TargetRectSpec screenTargetRect;
    screenTargetRect.provided = true;
    POINT tl{bridge.locatorCandidate.targetRect.left, bridge.locatorCandidate.targetRect.top};
    POINT br{bridge.locatorCandidate.targetRect.right, bridge.locatorCandidate.targetRect.bottom};
    ClientToScreen(selected.hwnd, &tl);
    ClientToScreen(selected.hwnd, &br);
    screenTargetRect.left = tl.x;
    screenTargetRect.top = tl.y;
    screenTargetRect.right = br.x;
    screenTargetRect.bottom = br.y;
    std::wstring humanAction = HumanActionResultJson(
        command,
        clicked,
        L"vlm-assisted-local-safe-click",
        bridge.locatorCandidate.label,
        L"vlm_assisted_runtime_validated",
        screenTargetRect,
        clicked.ok ? 0 : 1);
    std::wstringstream actionEvidence;
    actionEvidence << L"{\"runtime_context_guard_used\":true"
                   << L",\"context_guard_result\":" << RuntimeContextGuardResultJson(guard)
                   << L",\"mouse_click_sent\":" << (clicked.actualClickSent ? L"true" : L"false")
                   << L",\"human_action_result\":" << humanAction
                   << L",\"post_action_verified\":" << (postVerified ? L"true" : L"false")
                   << L",\"verification_file\":" << JsonString(verificationFile)
                   << L",\"expected_marker\":" << JsonString(expectedMarker)
                   << L"}";

    bool runtimeExecuted = clicked.ok;
    std::wstring payload = VLMAssistedLocatePayloadJson(
        bridge,
        runtimeExecuted,
        clicked.actualClickSent,
        true,
        postVerified,
        actionEvidence.str());
    WriteSmallTextFile(resultPath, payload);
    if (!clicked.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode, clicked.error, payload, 1);
    }
    if (!postVerified) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"POST_ACTION_VERIFICATION_FAILED", L"Expected local-safe marker was not observed after click.", payload, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), payload);
}

std::wstring ActSuccessData(
    const SelectorResult& located,
    const std::wstring& action,
    const std::wstring& actionMethod,
    const std::wstring& extra = L"",
    const std::wstring& windowSessionJson = L"") {
    std::wstring data = located.dataJson.substr(0, located.dataJson.size() - 1)
        + L",\"action\":" + JsonString(action)
        + L",\"action_method\":" + JsonString(actionMethod);
    if (!windowSessionJson.empty()) {
        data += L",\"window_session\":" + windowSessionJson;
    }
    if (!extra.empty()) {
        data += L"," + extra;
    }
    data += L"}";
    return data;
}

int CommandAct(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"act";
    std::wstring title;
    std::wstring selector;
    std::wstring action;
    std::wstring text;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    bool hasText = ArgValue(argc, argv, L"--text", text);
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--selector", selector) || !ArgValue(argc, argv, L"--action", action)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"act requires --title, --selector, and --action.", L"{}", 2);
    }
    if (action != L"click" && action != L"double-click" && action != L"right-click" && action != L"type" && action != L"focus") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Unsupported act action.", L"{\"action\":" + JsonString(action) + L"}", 2);
    }
    if (action == L"type" && !hasText) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"type action requires --text.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring semanticParseError;
    TargetSemanticsSpec semanticSpec = ParseTargetSemanticsSpecFromArgs(argc, argv, semanticParseError);
    if (!semanticParseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", semanticParseError, L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    if (IsUnresolvedVisualSelector(selector)) {
        std::wstring data = L"{\"selector\":" + JsonString(selector)
            + L",\"semantic_status\":\"unresolved\""
            + L",\"source\":\"visual\""
            + L",\"action\":" + JsonString(action)
            + L",\"action_blocked\":true"
            + L",\"reason\":\"Visual-only unresolved LocatorCandidate cannot be executed by ActionExecutor.\""
            + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"ACTION_BLOCKED_SEMANTIC_UNRESOLVED", L"Visual-only unresolved LocatorCandidate cannot be clicked or typed.", data, 1);
    }

    if (selector.rfind(L"text:", 0) == 0 && !EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    SelectorResult located = LocateSelector(selected.hwnd, selector);
    if (!located.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), located.errorCode.empty() ? L"UNKNOWN_ERROR" : located.errorCode, located.errorMessage, located.dataJson, located.errorCode == L"INVALID_SELECTOR" ? 2 : 1);
    }

    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    TargetSemanticsContext semanticContext = TargetSemanticsContextFromSelectorResult(argc, argv, located);
    TargetSemanticsGuardResult semanticResult = EvaluateTargetSemanticsGuard(semanticSpec, semanticContext);
    PersistTargetSemanticsGuardResult(semanticSpec, semanticResult, command, false);
    std::wstring semanticFields = TargetSemanticsGuardFields(semanticSpec, semanticResult);
    if (!semanticResult.ok) {
        return EmitTargetSemanticsGuardFailure(command, startTick, MakeTraceTarget(selected), semanticSpec, semanticResult, L"\"selector_result\":" + located.dataJson);
    }

    ActionResult foreground = FocusTargetWindow(selected.hwnd);
    if (!foreground.ok) {
        std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
        return EmitFailure(command, startTick, MakeTraceTarget(selected), foreground.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : foreground.errorCode, foreground.error, data, 1);
    }
    WindowSessionResult actionSession = ResolveWindowSession(title);
    std::wstring actionSessionJson = actionSession.ok ? WindowSessionJson(actionSession.session) : L"";
    if (actionSession.ok) {
        selected = actionSession.session.window;
    }

    if (action == L"focus") {
        return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"focus_window", JoinJsonFields(semanticFields, L"\"focus_verified\":" + std::wstring(foreground.focusVerified ? L"true" : L"false")), actionSessionJson));
    }

    if (action == L"click" && !IsOperatorRequestedMove(moveMode) && located.locateMethod == L"uia" && located.uiaInvokeCandidate && !located.elementName.empty()) {
        UiaPatternActionResult invoked = InvokeUiaElementByName(selected.hwnd, located.elementName);
        if (invoked.ok && invoked.patternAvailable) {
            Sleep(200);
            return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"invoke_pattern", JoinJsonFields(semanticFields, L"\"focus_verified\":" + std::wstring(foreground.focusVerified ? L"true" : L"false")), actionSessionJson));
        }
    }

    if (action == L"type" && located.locateMethod == L"uia" && located.uiaValueCandidate && !located.elementName.empty()) {
        UiaPatternActionResult typed = SetUiaElementValueByName(selected.hwnd, located.elementName, text);
        if (typed.ok && typed.patternAvailable) {
            Sleep(200);
            return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"value_pattern", JoinJsonFields(semanticFields, L"\"text_length\":" + std::to_wstring(text.size()) + L",\"focus_verified\":" + std::wstring(foreground.focusVerified ? L"true" : L"false")), actionSessionJson));
        }
    }

    if (action == L"click") {
        ClickResult click = ApplyClickFallback(selected.hwnd, located.clientX, located.clientY, moveMode, 0, fallback,
                                               ClickClientPoint(selected.hwnd, located.clientX, located.clientY, moveMode, 0, profilePath, allowSyntheticProfile));
        if (!click.ok) {
            std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
            return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
        }
        return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"mouse_click", JoinJsonFields(semanticFields, L"\"focus_verified\":" + std::wstring(click.focusVerified ? L"true" : L"false") + L"," + ClickMotionFields(click)), actionSessionJson));
    }
    if (action == L"double-click") {
        ClickResult click = ApplyDoubleClickFallback(selected.hwnd, located.clientX, located.clientY, moveMode, 0, fallback,
                                                     DoubleClickClientPoint(selected.hwnd, located.clientX, located.clientY, moveMode, 0, profilePath, allowSyntheticProfile));
        if (!click.ok) {
            std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
            return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
        }
        return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"mouse_double_click", JoinJsonFields(semanticFields, L"\"focus_verified\":" + std::wstring(click.focusVerified ? L"true" : L"false") + L"," + ClickMotionFields(click)), actionSessionJson));
    }
    if (action == L"right-click") {
        ClickResult click = ApplyRightClickFallback(selected.hwnd, located.clientX, located.clientY, moveMode, 0, fallback,
                                                    RightClickClientPoint(selected.hwnd, located.clientX, located.clientY, moveMode, 0, profilePath, allowSyntheticProfile));
        if (!click.ok) {
            std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
            return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
        }
        return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"mouse_right_click", JoinJsonFields(semanticFields, L"\"focus_verified\":" + std::wstring(click.focusVerified ? L"true" : L"false") + L"," + ClickMotionFields(click)), actionSessionJson));
    }

    ClickResult click = ApplyClickFallback(selected.hwnd, located.clientX, located.clientY, moveMode, 0, fallback,
                                           ClickClientPoint(selected.hwnd, located.clientX, located.clientY, moveMode, 0, profilePath, allowSyntheticProfile));
    if (!click.ok) {
        std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
        return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
    }
    ActionResult selectAll = SendHotkey(selected.hwnd, L"CTRL+A");
    if (!selectAll.ok) {
        std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
        return EmitFailure(command, startTick, MakeTraceTarget(selected), selectAll.errorCode.empty() ? L"UNKNOWN_ERROR" : selectAll.errorCode, selectAll.error, data, 1);
    }
    TypeResult typed = TypeText(selected.hwnd, text, L"human", -1);
    if (!typed.ok) {
        std::wstring data = semanticFields.empty() ? located.dataJson : (located.dataJson.substr(0, located.dataJson.size() - 1) + L"," + semanticFields + L"}");
        return EmitFailure(command, startTick, MakeTraceTarget(selected), typed.errorCode.empty() ? L"UNKNOWN_ERROR" : typed.errorCode, typed.error, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), ActSuccessData(located, action, L"mouse_center_type", JoinJsonFields(semanticFields, L"\"text_length\":" + std::to_wstring(text.size()) + L",\"focus_verified\":" + std::wstring(typed.focusVerified ? L"true" : L"false") + L"," + ClickMotionFields(click)), actionSessionJson));
}

int CommandClick(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"click";
    std::wstring title;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int moveDurationMs = 0;
    int x = 0;
    int y = 0;
    if (!ArgValue(argc, argv, L"--title", title) || !ParseIntArg(argc, argv, L"--x", x) || !ParseIntArg(argc, argv, L"--y", y)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"click requires --title, --x, and --y.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--move-duration-ms", moveDurationMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (moveDurationMs < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--move-duration-ms must be non-negative.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, GuardTargetFromClientPoint(selected.hwnd, x, y));
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"click_sent\":false", guardState, guardExit)) {
        return guardExit;
    }

    ClickResult result = ApplyClickFallback(selected.hwnd, x, y, moveMode, moveDurationMs, fallback,
                                            ClickClientPoint(selected.hwnd, x, y, moveMode, moveDurationMs, profilePath, allowSyntheticProfile));
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, RuntimeGuardEnvelope(guardState, true, L"\"click_sent\":false"), 1);
    }
    if (!VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"click_sent\":true", guardState, guardExit)) {
        return guardExit;
    }

    std::wstringstream fields;
    std::wstring guardFields = RuntimeGuardFields(guardState, true);
    fields << L"{";
    if (!guardFields.empty()) fields << guardFields << L",";
    fields << ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified) << L","
           << L"\"target_client_x\":" << result.targetClientX << L","
           << L"\"target_client_y\":" << result.targetClientY << L","
           << L"\"target_screen_x\":" << result.targetScreenX << L","
           << L"\"target_screen_y\":" << result.targetScreenY << L","
           << L"\"cursor_before_x\":" << result.cursorBeforeX << L","
           << L"\"cursor_before_y\":" << result.cursorBeforeY << L","
           << L"\"cursor_after_x\":" << result.cursorAfterX << L","
           << L"\"cursor_after_y\":" << result.cursorAfterY << L","
           << ClickMotionFields(result) << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), fields.str());
}

int CommandMouseClickVariant(int argc, wchar_t** argv, const std::wstring& command) {
    ULONGLONG startTick = GetTickCount64();
    std::wstring title;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int moveDurationMs = 0;
    int x = 0;
    int y = 0;
    if (!ArgValue(argc, argv, L"--title", title) || !ParseIntArg(argc, argv, L"--x", x) || !ParseIntArg(argc, argv, L"--y", y)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", command + L" requires --title, --x, and --y.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--move-duration-ms", moveDurationMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (moveDurationMs < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--move-duration-ms must be non-negative.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, GuardTargetFromClientPoint(selected.hwnd, x, y));
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"click_sent\":false", guardState, guardExit)) {
        return guardExit;
    }

    ClickResult result = command == L"double-click"
        ? ApplyDoubleClickFallback(selected.hwnd, x, y, moveMode, moveDurationMs, fallback,
                                   DoubleClickClientPoint(selected.hwnd, x, y, moveMode, moveDurationMs, profilePath, allowSyntheticProfile))
        : ApplyRightClickFallback(selected.hwnd, x, y, moveMode, moveDurationMs, fallback,
                                  RightClickClientPoint(selected.hwnd, x, y, moveMode, moveDurationMs, profilePath, allowSyntheticProfile));
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, RuntimeGuardEnvelope(guardState, true, L"\"click_sent\":false"), 1);
    }
    if (!VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"click_sent\":true", guardState, guardExit)) {
        return guardExit;
    }

    std::wstringstream fields;
    std::wstring guardFields = RuntimeGuardFields(guardState, true);
    fields << L"{";
    if (!guardFields.empty()) fields << guardFields << L",";
    fields << ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified) << L","
           << L"\"action_method\":" << JsonString(result.actionMethod) << L","
           << L"\"target_client_x\":" << result.targetClientX << L","
           << L"\"target_client_y\":" << result.targetClientY << L","
           << L"\"target_screen_x\":" << result.targetScreenX << L","
           << L"\"target_screen_y\":" << result.targetScreenY << L","
           << L"\"cursor_before_x\":" << result.cursorBeforeX << L","
           << L"\"cursor_before_y\":" << result.cursorBeforeY << L","
           << L"\"cursor_after_x\":" << result.cursorAfterX << L","
           << L"\"cursor_after_y\":" << result.cursorAfterY << L","
           << ClickMotionFields(result) << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), fields.str());
}

int CommandScroll(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"scroll";
    if (ArgExists(argc, argv, L"--help")) {
        return EmitSuccess(command, startTick, NoTraceTarget(), L"{\"usage\":\"winagent.exe scroll --title <substring> --x <client_x> --y <client_y> --delta <int> [--move-mode instant|fast-human|demo-human|human|operator-human]\"}");
    }
    std::wstring title;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int x = 0;
    int y = 0;
    int delta = 0;
    if (!ArgValue(argc, argv, L"--title", title) ||
        !ParseIntArg(argc, argv, L"--x", x) ||
        !ParseIntArg(argc, argv, L"--y", y) ||
        !ParseIntArg(argc, argv, L"--delta", delta)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"scroll requires --title, --x, --y, and --delta.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, GuardTargetFromClientPoint(selected.hwnd, x, y));
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"wheel_event_count\":0", guardState, guardExit)) {
        return guardExit;
    }

    ClickResult result = ApplyScrollFallback(selected.hwnd, x, y, delta, moveMode, fallback,
                                             ScrollClientPoint(selected.hwnd, x, y, delta, moveMode, profilePath, allowSyntheticProfile));
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, RuntimeGuardEnvelope(guardState, true, L"\"wheel_event_count\":0"), 1);
    }
    if (!VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"wheel_event_count\":" + std::to_wstring(result.wheelEventCount), guardState, guardExit)) {
        return guardExit;
    }

    std::wstringstream fields;
    std::wstring guardFields = RuntimeGuardFields(guardState, true);
    fields << L"{";
    if (!guardFields.empty()) fields << guardFields << L",";
    fields << ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified) << L","
           << L"\"action_method\":\"scroll\","
           << L"\"input_type\":\"mouse_wheel\","
           << L"\"sendinput_used\":" << (result.sendInputUsed ? L"true" : L"false") << L","
           << L"\"mouseeventf_wheel_used\":" << (result.mouseeventfWheelUsed ? L"true" : L"false") << L","
           << L"\"wheel_event_count\":" << result.wheelEventCount << L","
           << L"\"target_client_x\":" << result.targetClientX << L","
           << L"\"target_client_y\":" << result.targetClientY << L","
           << L"\"target_screen_x\":" << result.targetScreenX << L","
           << L"\"target_screen_y\":" << result.targetScreenY << L","
           << L"\"wheel_delta\":" << result.wheelDelta << L","
           << ClickMotionFields(result) << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), fields.str());
}

struct WheelActionExecution {
    ClickResult wheel;
    ScrollRegionInfo region;
    bool regionOk = false;
    bool cursorInsideScrollRegionBeforeWheel = false;
    bool contentChanged = false;
    double changeScore = 0.0;
    std::wstring screenshotBefore;
    std::wstring screenshotAfter;
    FileContentSignature beforeSignature;
    FileContentSignature afterSignature;
    WindowInfo foregroundWindow;
    std::wstring error;
};

std::wstring DirectionFromDelta(const std::wstring& requestedDirection, int delta, bool horizontal) {
    if (!requestedDirection.empty()) return requestedDirection;
    if (horizontal) return delta < 0 ? L"left" : L"right";
    return delta < 0 ? L"down" : L"up";
}

bool DirectionIsHorizontal(const std::wstring& direction) {
    return direction == L"left" || direction == L"right";
}

int DeltaForDirection(const std::wstring& direction, int notches, bool hasExplicitDelta, int explicitDelta) {
    if (hasExplicitDelta) return explicitDelta;
    int magnitude = 120 * (notches <= 0 ? 1 : notches);
    if (direction == L"up") return magnitude;
    if (direction == L"left") return -magnitude;
    if (direction == L"right") return magnitude;
    return -magnitude;
}

WheelActionExecution ExecuteWheelAction(
    const WindowInfo& selected,
    bool hasClientPoint,
    int requestedX,
    int requestedY,
    const std::wstring& direction,
    int delta,
    const std::wstring& moveMode,
    const std::wstring& profilePath,
    bool allowSyntheticProfile,
    const std::wstring& screenshotDir) {
    WheelActionExecution execution;
    std::wstring regionError;
    execution.regionOk = ComputeScrollRegion(selected.hwnd, hasClientPoint, requestedX, requestedY, execution.region, regionError);
    if (!execution.regionOk) {
        execution.error = regionError;
        execution.wheel.errorCode = L"INVALID_ARGUMENT";
        execution.wheel.error = regionError;
        return execution;
    }

    execution.screenshotBefore = V613CommandScreenshotPath(L"wheel_before", screenshotDir);
    ScreenshotResult beforeShot = CaptureWindowToBmp(selected.hwnd, execution.screenshotBefore);
    if (beforeShot.ok) {
        execution.beforeSignature = ComputeFileSignature(execution.screenshotBefore);
    } else {
        execution.beforeSignature.error = beforeShot.error;
    }

    if (DirectionIsHorizontal(direction)) {
        execution.wheel = HorizontalScrollClientPoint(
            selected.hwnd,
            execution.region.safeClientX,
            execution.region.safeClientY,
            delta,
            moveMode,
            profilePath,
            allowSyntheticProfile);
    } else {
        execution.wheel = ScrollClientPoint(
            selected.hwnd,
            execution.region.safeClientX,
            execution.region.safeClientY,
            delta,
            moveMode,
            profilePath,
            allowSyntheticProfile);
    }
    if (execution.wheel.ok) {
        POINT beforeWheelClient = {execution.wheel.cursorAfterX, execution.wheel.cursorAfterY};
        if (ScreenToClient(selected.hwnd, &beforeWheelClient)) {
            execution.cursorInsideScrollRegionBeforeWheel = PointInsideRect(execution.region.scrollRegion, beforeWheelClient.x, beforeWheelClient.y);
        }
    }

    Sleep(250);
    execution.screenshotAfter = V613CommandScreenshotPath(L"wheel_after", screenshotDir);
    ScreenshotResult afterShot = CaptureWindowToBmp(selected.hwnd, execution.screenshotAfter);
    if (afterShot.ok) {
        execution.afterSignature = ComputeFileSignature(execution.screenshotAfter);
    } else {
        execution.afterSignature.error = afterShot.error;
    }
    execution.contentChanged = execution.beforeSignature.ok && execution.afterSignature.ok &&
        execution.beforeSignature.value != execution.afterSignature.value;
    execution.changeScore = execution.contentChanged ? 1.0 : 0.0;
    ActiveWindowInfo(execution.foregroundWindow);
    if (!execution.wheel.ok) {
        execution.error = execution.wheel.error;
    }
    return execution;
}

std::wstring WheelActionResultJson(
    const WindowInfo& selected,
    const std::wstring& direction,
    int delta,
    int notches,
    bool verifyContentChange,
    const WheelActionExecution& execution) {
    std::wstringstream json;
    json << L"{\"input_type\":\"mouse_wheel\""
         << L",\"sendinput_used\":" << (execution.wheel.sendInputUsed ? L"true" : L"false")
         << L",\"mouseeventf_wheel_used\":" << (execution.wheel.mouseeventfWheelUsed ? L"true" : L"false")
         << L",\"mouseeventf_hwheel_used\":" << (execution.wheel.mouseeventfHWheelUsed ? L"true" : L"false")
         << L",\"wheel_event_count\":" << execution.wheel.wheelEventCount
         << L",\"delta\":" << delta
         << L",\"notches\":" << notches
         << L",\"direction\":" << JsonString(direction)
         << L",\"wheel_direction\":" << JsonString(direction)
         << L",\"cursor_before\":" << PointJson(execution.wheel.cursorBeforeX, execution.wheel.cursorBeforeY)
         << L",\"cursor_before_wheel\":" << PointJson(execution.wheel.cursorAfterX, execution.wheel.cursorAfterY)
         << L",\"cursor_after\":" << PointJson(execution.wheel.cursorAfterX, execution.wheel.cursorAfterY)
         << L",\"cursor_inside_scroll_region_before_wheel\":" << (execution.cursorInsideScrollRegionBeforeWheel ? L"true" : L"false")
         << L",\"scroll_region\":" << ScrollRegionJson(execution.region)
         << L",\"target_scroll_region\":" << ScrollRegionJson(execution.region)
         << L",\"foreground_hwnd\":" << HwndJson(execution.wheel.foregroundAfter)
         << L",\"foreground_window\":{\"hwnd\":" << JsonString(FormatHwnd(execution.foregroundWindow.hwnd))
         << L",\"title\":" << JsonString(execution.foregroundWindow.title)
         << L",\"pid\":" << execution.foregroundWindow.pid << L"}"
         << L",\"window_rect\":" << WindowRectJson(selected)
         << L",\"client_rect\":" << RectJson(execution.region.clientRect)
         << L",\"screenshot_before\":" << JsonString(execution.screenshotBefore)
         << L",\"screenshot_after\":" << JsonString(execution.screenshotAfter)
         << L",\"verify_content_change\":" << (verifyContentChange ? L"true" : L"false")
         << L",\"content_changed\":" << (execution.contentChanged ? L"true" : L"false")
         << L",\"before_content_signature\":" << JsonString(execution.beforeSignature.value)
         << L",\"after_content_signature\":" << JsonString(execution.afterSignature.value)
         << L",\"change_score\":" << execution.changeScore
         << L",\"visible_items_before\":[]"
         << L",\"visible_items_after\":[]"
         << L",\"error\":" << JsonString(execution.error)
         << L"}";
    return json.str();
}

int EmitSuccessWithOptionalOutput(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& dataJson,
    const std::wstring& outputJsonPath) {
    if (!outputJsonPath.empty()) {
        WriteSmallTextFile(outputJsonPath, CommandSuccessJson(command, startTick, target, dataJson));
    }
    return EmitSuccess(command, startTick, target, dataJson);
}

int EmitFailureWithOptionalOutput(
    const std::wstring& command,
    ULONGLONG startTick,
    const TraceTarget& target,
    const std::wstring& errorCode,
    const std::wstring& errorMessage,
    const std::wstring& dataJson,
    int exitCode,
    const std::wstring& outputJsonPath) {
    if (!outputJsonPath.empty()) {
        WriteSmallTextFile(outputJsonPath, CommandFailureJson(command, startTick, target, errorCode, errorMessage, dataJson));
    }
    return EmitFailure(command, startTick, target, errorCode, errorMessage, dataJson, exitCode);
}

int CommandAdaptiveScroll(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"adaptive-scroll";
    if (ArgExists(argc, argv, L"--help")) {
        return EmitSuccess(command, startTick, NoTraceTarget(), L"{\"usage\":\"winagent.exe adaptive-scroll --title <title>|--hwnd <hwnd> [--x <client_x> --y <client_y>] [--direction up|down|left|right] [--notches <n>|--delta <int>] [--move-mode human] [--verify-content-change true|false] [--output-json <path>]\"}");
    }

    std::wstring title;
    std::wstring hwndArg;
    std::wstring direction = L"down";
    std::wstring moveMode = L"human";
    std::wstring profilePath;
    std::wstring outputJsonPath;
    std::wstring screenshotDir;
    bool allowSyntheticProfile = false;
    bool verifyContentChange = false;
    int x = 0;
    int y = 0;
    int delta = 0;
    int notches = 3;
    bool hasX = ParseIntArg(argc, argv, L"--x", x);
    bool hasY = ParseIntArg(argc, argv, L"--y", y);
    bool hasDelta = ParseIntArg(argc, argv, L"--delta", delta);
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--direction", direction);
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--profile", profilePath);
    ArgValue(argc, argv, L"--output-json", outputJsonPath);
    if (outputJsonPath.empty()) ArgValue(argc, argv, L"--result-json", outputJsonPath);
    ArgValue(argc, argv, L"--screenshot-dir", screenshotDir);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--notches", notches, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--verify-content-change", verifyContentChange, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (title.empty() && hwndArg.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"adaptive-scroll requires --title or --hwnd.", L"{}", 2);
    }
    if (hasX != hasY) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--x and --y must be provided together.", L"{}", 2);
    }
    if (notches <= 0 || notches > 50) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--notches must be between 1 and 50.", L"{}", 2);
    }
    if (direction != L"up" && direction != L"down" && direction != L"left" && direction != L"right") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--direction must be up, down, left, or right.", L"{}", 2);
    }
    delta = DeltaForDirection(direction, notches, hasDelta, delta);
    direction = DirectionFromDelta(direction, delta, DirectionIsHorizontal(direction));

    WindowInfo selected;
    std::wstring requestedTitleForSafety;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveWindowByTitleOrHwnd(title, hwndArg, selected, requestedTitleForSafety, errorCode, errorMessage, dataJson)) {
        return EmitFailureWithOptionalOutput(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1, outputJsonPath);
    }
    if (!EnforceSafetyPolicy(selected, requestedTitleForSafety, errorCode, errorMessage, dataJson)) {
        return EmitFailureWithOptionalOutput(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1, outputJsonPath);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext baseGuardTarget = hasX ? GuardTargetFromClientPoint(selected.hwnd, x, y) : RuntimeTargetContext{};
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, baseGuardTarget);
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"wheel_event_count\":0", guardState, guardExit, outputJsonPath)) {
        return guardExit;
    }

    WheelActionExecution execution = ExecuteWheelAction(
        selected,
        hasX,
        x,
        y,
        direction,
        delta,
        moveMode,
        profilePath,
        allowSyntheticProfile,
        screenshotDir);
    std::wstring wheelJson = WheelActionResultJson(selected, direction, delta, notches, verifyContentChange, execution);
    if (execution.wheel.ok && !VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"wheel_event_count\":" + std::to_wstring(execution.wheel.wheelEventCount), guardState, guardExit, outputJsonPath)) {
        return guardExit;
    }
    std::wstring guardFields = RuntimeGuardFields(guardState, execution.wheel.ok);
    std::wstring data = L"{";
    if (!guardFields.empty()) data += guardFields + L",";
    data += L"\"wheel_action_result\":" + wheelJson + L"}";
    if (!execution.wheel.ok) {
        return EmitFailureWithOptionalOutput(command, startTick, MakeTraceTarget(selected), execution.wheel.errorCode.empty() ? L"SEND_INPUT_FAILED" : execution.wheel.errorCode, execution.wheel.error, data, 1, outputJsonPath);
    }
    if (verifyContentChange && !execution.contentChanged) {
        return EmitFailureWithOptionalOutput(command, startTick, MakeTraceTarget(selected), L"WHEEL_NO_CONTENT_CHANGE", L"Mouse wheel input was sent but verified content did not change.", data, 1, outputJsonPath);
    }
    return EmitSuccessWithOptionalOutput(command, startTick, MakeTraceTarget(selected), data, outputJsonPath);
}

bool LocateTargetTextVisible(HWND hwnd, const std::wstring& targetText, SelectorResult& located, std::wstring& locatorUsed, std::wstring& failureSummary) {
    std::vector<std::wstring> selectors = {
        L"uia:name=" + targetText,
        L"uia:name_contains=" + targetText,
        L"text:exact=" + targetText,
        L"text:contains=" + targetText
    };
    RECT client = {};
    GetClientRect(hwnd, &client);
    std::vector<std::wstring> failures;
    for (const auto& selector : selectors) {
        SelectorResult candidate = LocateSelector(hwnd, selector);
        if (!candidate.ok) {
            failures.push_back(selector + L" -> " + candidate.errorCode);
            continue;
        }
        bool visible = PointInsideRect(client, candidate.clientX, candidate.clientY);
        if (candidate.hasElement && candidate.elementOffscreen) {
            visible = false;
        }
        if (visible) {
            located = candidate;
            locatorUsed = candidate.source.empty() ? candidate.locateMethod : candidate.source;
            failureSummary.clear();
            return true;
        }
        failures.push_back(selector + L" -> offscreen_or_outside_client");
    }
    failureSummary.clear();
    for (size_t i = 0; i < failures.size(); ++i) {
        if (i) failureSummary += L"; ";
        failureSummary += failures[i];
    }
    return false;
}

std::wstring SelectorRectOrNull(const SelectorResult& result, bool found) {
    return found ? RectJson(result.rect) : L"null";
}

int CommandScrollAndLocate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"scroll-and-locate";
    if (ArgExists(argc, argv, L"--help")) {
        return EmitSuccess(command, startTick, NoTraceTarget(), L"{\"usage\":\"winagent.exe scroll-and-locate --title <title>|--hwnd <hwnd> --target-text <text> [--region auto|client|content|list] [--direction down|up] [--max-scrolls <n>] [--notches-per-scroll <n>] [--move-mode human] [--locator uia|ocr|hybrid|auto] [--output-json <path>]\"}");
    }

    std::wstring title;
    std::wstring hwndArg;
    std::wstring targetText;
    std::wstring regionMode = L"auto";
    std::wstring direction = L"down";
    std::wstring moveMode = L"human";
    std::wstring locator = L"auto";
    std::wstring outputJsonPath;
    std::wstring screenshotDir;
    int maxScrolls = 20;
    int notchesPerScroll = 3;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--target-text", targetText);
    ArgValue(argc, argv, L"--region", regionMode);
    ArgValue(argc, argv, L"--direction", direction);
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--locator", locator);
    ArgValue(argc, argv, L"--output-json", outputJsonPath);
    if (outputJsonPath.empty()) ArgValue(argc, argv, L"--result-json", outputJsonPath);
    ArgValue(argc, argv, L"--screenshot-dir", screenshotDir);
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--max-scrolls", maxScrolls, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--notches-per-scroll", notchesPerScroll, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if ((title.empty() && hwndArg.empty()) || targetText.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"scroll-and-locate requires --title or --hwnd and requires --target-text.", L"{}", 2);
    }
    if (direction != L"up" && direction != L"down") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--direction must be down or up.", L"{}", 2);
    }
    if (maxScrolls <= 0 || maxScrolls > 100 || notchesPerScroll <= 0 || notchesPerScroll > 50) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Scroll budgets must be positive and bounded.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring requestedTitleForSafety;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveWindowByTitleOrHwnd(title, hwndArg, selected, requestedTitleForSafety, errorCode, errorMessage, dataJson)) {
        return EmitFailureWithOptionalOutput(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1, outputJsonPath);
    }
    if (!EnforceSafetyPolicy(selected, requestedTitleForSafety, errorCode, errorMessage, dataJson)) {
        return EmitFailureWithOptionalOutput(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1, outputJsonPath);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, RuntimeTargetContext{});
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"wheel_event_count\":0,\"wheel_scroll_count\":0", guardState, guardExit, outputJsonPath)) {
        return guardExit;
    }

    ScrollRegionInfo initialRegion;
    std::wstring regionError;
    if (!ComputeScrollRegion(selected.hwnd, false, 0, 0, initialRegion, regionError)) {
        return EmitFailureWithOptionalOutput(command, startTick, MakeTraceTarget(selected), L"INVALID_ARGUMENT", regionError, L"{}", 2, outputJsonPath);
    }

    ObserveResult initialObserve = ObserveWindow(requestedTitleForSafety.empty() ? selected.title : requestedTitleForSafety, true, true, 200);
    int reobserveCount = initialObserve.ok ? 1 : 0;
    SelectorResult located;
    std::wstring locatorUsed;
    std::wstring locateFailure;
    bool initiallyVisible = LocateTargetTextVisible(selected.hwnd, targetText, located, locatorUsed, locateFailure);
    bool found = initiallyVisible;
    int foundAfterScrollCount = 0;
    bool wheelAttemptedFirst = false;
    int wheelScrollCount = 0;
    int wheelEventCount = 0;
    int wheelContentChangedCount = 0;
    int wheelNoProgressCount = 0;
    int retryCount = 0;
    int wrongPageNavigationCount = 0;
    std::wstring finalFailureReason;
    std::vector<std::wstring> wheelActions;

    int delta = DeltaForDirection(direction, notchesPerScroll, false, 0);
    for (int i = 1; !found && i <= maxScrolls; ++i) {
        if (guardState.spec.enabled) {
            guardState.result = EvaluateRuntimeContextGuard(guardState.spec, guardTarget);
            PersistRuntimeContextGuardResult(guardState.spec, guardState.result, command, false);
            if (!guardState.result.ok && guardState.spec.stopOnFailure) {
                return EmitRuntimeGuardFailure(command, startTick, MakeTraceTarget(selected), guardState, false, guardState.result.stopCode, guardState.result.reason, L"\"wheel_event_count\":" + std::to_wstring(wheelEventCount) + L",\"wheel_scroll_count\":" + std::to_wstring(wheelScrollCount), outputJsonPath);
            }
        }
        WheelActionExecution wheel = ExecuteWheelAction(
            selected,
            false,
            0,
            0,
            direction,
            delta,
            moveMode,
            L"",
            false,
            screenshotDir);
        wheelAttemptedFirst = true;
        wheelActions.push_back(WheelActionResultJson(selected, direction, delta, notchesPerScroll, true, wheel));
        if (wheel.wheel.ok) {
            ++wheelScrollCount;
            wheelEventCount += wheel.wheel.wheelEventCount;
        } else {
            finalFailureReason = wheel.wheel.error.empty() ? L"wheel action failed" : wheel.wheel.error;
            errorCode = wheel.wheel.errorCode.empty() ? L"SEND_INPUT_FAILED" : wheel.wheel.errorCode;
            break;
        }
        if (wheel.wheel.foregroundAfter != selected.hwnd) {
            ++wrongPageNavigationCount;
        }
        ObserveResult observed = ObserveWindow(requestedTitleForSafety.empty() ? selected.title : requestedTitleForSafety, true, true, 200);
        if (observed.ok) {
            ++reobserveCount;
        }
        if (!VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"wheel_event_count\":" + std::to_wstring(wheelEventCount) + L",\"wheel_scroll_count\":" + std::to_wstring(wheelScrollCount), guardState, guardExit, outputJsonPath)) {
            return guardExit;
        }
        if (!wheel.contentChanged) {
            ++wheelNoProgressCount;
            finalFailureReason = L"WHEEL_NO_CONTENT_CHANGE";
            errorCode = L"WHEEL_NO_CONTENT_CHANGE";
            break;
        }
        ++wheelContentChangedCount;
        SelectorResult afterLocate;
        std::wstring afterLocator;
        std::wstring afterFailure;
        if (LocateTargetTextVisible(selected.hwnd, targetText, afterLocate, afterLocator, afterFailure)) {
            located = afterLocate;
            locatorUsed = afterLocator;
            found = true;
            foundAfterScrollCount = i;
            break;
        }
        locateFailure = afterFailure;
        if (i < maxScrolls) {
            ++retryCount;
        }
    }
    if (!found && finalFailureReason.empty()) {
        finalFailureReason = L"FAIL_TARGET_NOT_FOUND_AFTER_SCROLL";
        errorCode = L"FAIL_TARGET_NOT_FOUND_AFTER_SCROLL";
    }

    std::wstringstream wheelArray;
    wheelArray << L"[";
    for (size_t i = 0; i < wheelActions.size(); ++i) {
        if (i) wheelArray << L",";
        wheelArray << wheelActions[i];
    }
    wheelArray << L"]";

    std::wstringstream data;
    std::wstring guardFields = RuntimeGuardFields(guardState, wheelEventCount > 0);
    data << L"{";
    if (!guardFields.empty()) data << guardFields << L",";
    data << L"\"target_text\":" << JsonString(targetText)
         << L",\"locator\":" << JsonString(locatorUsed.empty() ? locator : locatorUsed)
         << L",\"requested_locator\":" << JsonString(locator)
         << L",\"region\":" << JsonString(regionMode)
         << L",\"scrollable_region\":" << ScrollRegionJson(initialRegion)
         << L",\"initial_visible\":" << (initiallyVisible ? L"true" : L"false")
         << L",\"found\":" << (found ? L"true" : L"false")
         << L",\"found_after_scroll_count\":" << foundAfterScrollCount
         << L",\"target_rect\":" << SelectorRectOrNull(located, found)
         << L",\"wheel_attempted_first\":" << (wheelAttemptedFirst ? L"true" : L"false")
         << L",\"wheel_scroll_count\":" << wheelScrollCount
         << L",\"wheel_event_count\":" << wheelEventCount
         << L",\"wheel_content_changed_count\":" << wheelContentChangedCount
         << L",\"wheel_no_progress_count\":" << wheelNoProgressCount
         << L",\"scrollbar_fallback_count\":0"
         << L",\"fallback_reason\":\"\""
         << L",\"fallback_scrollbar_used\":false"
         << L",\"wrong_page_navigation_count\":" << wrongPageNavigationCount
         << L",\"stale_coordinate_reuse_count\":0"
         << L",\"precomputed_coordinate_sequence_used\":false"
         << L",\"synthetic_evidence_detected\":false"
         << L",\"reobserve_count\":" << reobserveCount
         << L",\"retry_count\":" << retryCount
         << L",\"wheel_actions\":" << wheelArray.str()
         << L",\"locate_failure_summary\":" << JsonString(locateFailure)
         << L",\"error\":" << JsonString(found ? L"" : finalFailureReason)
         << L"}";

    if (!found) {
        return EmitFailureWithOptionalOutput(command, startTick, MakeTraceTarget(selected), errorCode.empty() ? L"FAIL_TARGET_NOT_FOUND_AFTER_SCROLL" : errorCode, finalFailureReason, data.str(), 1, outputJsonPath);
    }
    return EmitSuccessWithOptionalOutput(command, startTick, MakeTraceTarget(selected), data.str(), outputJsonPath);
}

int CommandDrag(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"drag";
    std::wstring title;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int fromX = 0;
    int fromY = 0;
    int toX = 0;
    int toY = 0;
    int durationMs = 0;
    if (!ArgValue(argc, argv, L"--title", title) ||
        !ParseIntArg(argc, argv, L"--from-x", fromX) ||
        !ParseIntArg(argc, argv, L"--from-y", fromY) ||
        !ParseIntArg(argc, argv, L"--to-x", toX) ||
        !ParseIntArg(argc, argv, L"--to-y", toY)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"drag requires --title, --from-x, --from-y, --to-x, and --to-y.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--duration-ms", durationMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (durationMs < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--duration-ms must be non-negative.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    DragResult result = ApplyDragFallback(selected.hwnd, fromX, fromY, toX, toY, durationMs, moveMode, fallback,
                                          DragClientPoints(selected.hwnd, fromX, fromY, toX, toY, moveMode, durationMs, profilePath, allowSyntheticProfile));
    if (!result.ok) {
        std::wstring actionId = command + L"-" + std::to_wstring(startTick);
        std::wstring humanResult = DragHumanActionResultJson(command, result, actionId, 1);
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, L"{\"human_action_result\":" + humanResult + L"}", 1);
    }

    std::wstring actionId = command + L"-" + std::to_wstring(startTick);
    std::wstring humanResult = DragHumanActionResultJson(command, result, actionId, 0);
    std::wstringstream fields;
    fields << L"{" << ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified) << L","
           << L"\"from_client_x\":" << result.fromClientX << L","
           << L"\"from_client_y\":" << result.fromClientY << L","
           << L"\"to_client_x\":" << result.toClientX << L","
           << L"\"to_client_y\":" << result.toClientY << L","
           << L"\"from_screen_x\":" << result.fromScreenX << L","
           << L"\"from_screen_y\":" << result.fromScreenY << L","
           << L"\"to_screen_x\":" << result.toScreenX << L","
           << L"\"to_screen_y\":" << result.toScreenY << L","
           << L"\"cursor_before_x\":" << result.cursorBeforeX << L","
           << L"\"cursor_before_y\":" << result.cursorBeforeY << L","
           << L"\"cursor_after_x\":" << result.cursorAfterX << L","
           << L"\"cursor_after_y\":" << result.cursorAfterY << L","
           << L"\"mouse_down_sent\":" << (result.mouseDownSent ? L"true" : L"false") << L","
           << L"\"mouse_up_sent\":" << (result.mouseUpSent ? L"true" : L"false") << L","
           << L"\"human_action_result\":" << humanResult << L","
           << DragMotionFields(result) << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), fields.str());
}

int CommandPress(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"press";
    std::wstring title;
    std::wstring key;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--key", key)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"press requires --title and --key.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, RuntimeTargetContext{});
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"key_sent\":false", guardState, guardExit)) {
        return guardExit;
    }

    ActionResult result = PressKey(selected.hwnd, key);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, RuntimeGuardEnvelope(guardState, true, L"\"key\":" + JsonString(key) + L",\"key_sent\":false"), 1);
    }
    if (!VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"key_sent\":true", guardState, guardExit)) {
        return guardExit;
    }

    std::wstring guardFields = RuntimeGuardFields(guardState, true);
    std::wstring data = L"{";
    if (!guardFields.empty()) data += guardFields + L",";
    data += ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified)
        + L",\"key\":" + JsonString(key) + L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandType(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"type";
    std::wstring title;
    std::wstring text;
    std::wstring typeMode = L"human";
    int charDelayMs = -1;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"type requires --title and --text.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--type-mode", typeMode);
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--char-delay-ms", charDelayMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (ArgValue(argc, argv, L"--char-delay-ms", parseError) && charDelayMs < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--char-delay-ms must be non-negative.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, RuntimeTargetContext{});
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"typing_started\":false,\"text_length\":0", guardState, guardExit)) {
        return guardExit;
    }

    TypeResult result = TypeText(selected.hwnd, text, typeMode, charDelayMs);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, RuntimeGuardEnvelope(guardState, true, L"\"typing_started\":false,\"text_length\":0"), 1);
    }
    if (!VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"typing_started\":true,\"text_length\":" + std::to_wstring(result.textLength), guardState, guardExit)) {
        return guardExit;
    }

    std::wstringstream fields;
    std::wstring guardFields = RuntimeGuardFields(guardState, true);
    fields << L"{";
    if (!guardFields.empty()) fields << guardFields << L",";
    fields << ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified) << L","
           << L"\"type_mode\":\"" << JsonEscape(result.typeMode) << L"\","
           << L"\"char_delay_ms\":" << result.charDelayMs << L","
           << L"\"text_length\":" << result.textLength << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), fields.str());
}

int CommandHotkey(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"hotkey";
    std::wstring title;
    std::wstring keys;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--keys", keys)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"hotkey requires --title and --keys.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, RuntimeTargetContext{});
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"key_sent\":false", guardState, guardExit)) {
        return guardExit;
    }

    ActionResult result = SendHotkey(selected.hwnd, keys);
    if (result.ok && !VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"key_sent\":true", guardState, guardExit)) {
        return guardExit;
    }
    std::wstring guardFields = RuntimeGuardFields(guardState, result.ok);
    std::wstring data = L"{";
    if (!guardFields.empty()) data += guardFields + L",";
    data += ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified)
        + L",\"keys\":" + JsonString(keys) + L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandClipboardSet(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"clipboard-set";
    std::wstring text;
    if (!ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"clipboard-set requires --text.", L"{}", 2);
    }

    VisibleOperationPolicyOptions clipboardPriority;
    clipboardPriority.operationType = L"clipboard_primitive";
    clipboardPriority.attempt1Mode = L"system_clipboard_set";
    clipboardPriority.attempt1Result = L"succeeded";
    clipboardPriority.finalModeUsed = L"system_clipboard_set";
    VisibleOperationPolicyResult clipboardPolicy = enforce_visible_operation_priority(clipboardPriority);
    if (!clipboardPolicy.ok) {
        return EmitVisibleOperationPriorityFailure(command, startTick, NoTraceTarget(), clipboardPolicy, 1);
    }

    ActionResult result = SetClipboardUnicodeText(text);
    std::wstring data = L"{\"text_length\":" + std::to_wstring(result.textLength)
        + L",\"operation_priority\":" + VisibleOperationPolicyJson(clipboardPolicy) + L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandClipboardPaste(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"clipboard-paste";
    std::wstring title;
    std::wstring text;
    bool hasText = ArgValue(argc, argv, L"--text", text);
    if (!ArgValue(argc, argv, L"--title", title)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"clipboard-paste requires --title.", L"{}", 2);
    }

    VisibleOperationPolicyOptions pastePriority;
    pastePriority.operationType = L"clipboard_primitive";
    pastePriority.attempt1Mode = L"system_clipboard_paste";
    pastePriority.attempt1Result = L"succeeded";
    pastePriority.finalModeUsed = L"system_clipboard_paste";
    VisibleOperationPolicyResult pastePolicy = enforce_visible_operation_priority(pastePriority);
    if (!pastePolicy.ok) {
        return EmitVisibleOperationPriorityFailure(command, startTick, NoTraceTarget(), pastePolicy, 1);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    ActionResult result = PasteClipboardText(selected.hwnd, text, hasText);
    std::wstring data = L"{" + ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified)
        + L",\"pasted\":" + (result.pasted ? L"true" : L"false")
        + L",\"text_length\":" + std::to_wstring(result.textLength)
        + L",\"operation_priority\":" + VisibleOperationPolicyJson(pastePolicy)
        + L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandFocus(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"focus";
    std::wstring title;
    bool allowBackendFallback = true;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--title", title)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"focus requires --title.", L"{}", 2);
    }
    if (!ParseOptionalBoolArg(argc, argv, L"--allow-backend-fallback", allowBackendFallback, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, RuntimeTargetContext{});
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, MakeTraceTarget(selected), guardTarget, selected.title, L"\"focus_executed\":false", guardState, guardExit)) {
        return guardExit;
    }

    HWND foregroundBefore = GetForegroundWindow();
    bool alreadyForeground = ForegroundMatchesTarget(title, L"");
    bool altTabOk = alreadyForeground;
    bool altTabAttempted = false;
    int altTabCycles = 0;
    std::wstring altTabError;
    if (!alreadyForeground) {
        altTabAttempted = true;
        altTabCycles = AltTabCyclesForTarget(EnumerateWindowSwitchCandidates(), foregroundBefore, selected.hwnd, 12);
        if (altTabCycles > 0) {
            bool sent = SendAltTabCycles(altTabCycles, altTabError);
            altTabOk = sent && ForegroundMatchesTarget(title, L"");
        } else {
            altTabError = L"target_not_reachable_within_alt_tab_cycle_limit";
        }
    }

    ClickResult visibleClick;
    bool visibleClickOk = false;
    int visibleClickAttemptCount = 0;
    bool visibleClickBoundedRecovery = false;
    if (!altTabOk) {
        for (int attempt = 0; attempt < 2 && !visibleClickOk; ++attempt) {
            ++visibleClickAttemptCount;
            VisiblePrimitiveTarget visibleClickTarget = LocateWindowSwitchTaskbarTarget(title, L"", selected);
            if (visibleClickTarget.ok) {
                visibleClick = ClickHumanMode(RectCenterX(visibleClickTarget.element.rect), RectCenterY(visibleClickTarget.element.rect));
            } else {
                visibleClick = ClickHumanMode(RectCenterX(selected.rect), RectCenterY(selected.rect));
            }
            Sleep(250);
            visibleClickOk = visibleClick.ok && ForegroundMatchesTarget(title, L"");
            if (!visibleClickOk && attempt == 0) {
                visibleClickBoundedRecovery = true;
                PressKeyGlobal(L"ESC");
                Sleep(200);
            }
        }
    }

    ActionResult backendFocus;
    bool backendFocusUsed = false;
    bool backendFocusOk = false;
    if (!altTabOk && !visibleClickOk && allowBackendFallback) {
        backendFocusUsed = true;
        backendFocus = FocusTargetWindow(selected.hwnd);
        backendFocusOk = backendFocus.ok && ForegroundMatchesTarget(title, L"");
    }

    ActionResult result;
    result.foregroundBefore = foregroundBefore;
    result.foregroundAfter = GetForegroundWindow();
    result.focusVerified = ForegroundMatchesTarget(title, L"");
    result.ok = result.focusVerified;
    if (backendFocusUsed) {
        result = backendFocus;
        result.focusVerified = backendFocusOk;
        result.ok = backendFocusOk;
    }
    if (!result.ok && result.errorCode.empty()) {
        result.errorCode = L"WINDOW_SWITCH_NOT_VERIFIED";
        result.error = L"Focus did not verify after visible switch attempts.";
    }

    VisibleOperationPolicyOptions priority;
    priority.operationType = L"window_switch";
    priority.attempt1Mode = L"alt_tab_keyboard_switch";
    priority.attempt2Mode = L"visible_taskbar_or_window_click";
    priority.attempt3Mode = L"backend_focus_fallback";
    priority.visibleMouseKeyboardAttempted = true;
    priority.attempt1Result = altTabOk ? L"succeeded" : L"failed";
    priority.attempt1FailureReason = altTabOk ? L"" : (altTabError.empty() ? L"target_not_selected_by_alt_tab" : altTabError);
    priority.visibleAttemptCount = visibleClickAttemptCount;
    priority.preActionCheckpointPresent = true;
    priority.boundedRecoveryAttempted = visibleClickBoundedRecovery;
    priority.postRecoveryObserved = visibleClickBoundedRecovery;
    priority.sameSurfaceAfterRecovery = visibleClickBoundedRecovery;
    priority.keyboardShortcutAttempted = !altTabOk;
    priority.attempt2Result = !altTabOk ? (visibleClickOk ? L"succeeded" : L"failed") : L"not_attempted";
    priority.attempt2FailureReason = (!altTabOk && !visibleClickOk) ? (visibleClick.errorCode.empty() ? L"visible_taskbar_or_window_click_failed" : visibleClick.errorCode) : L"";
    priority.backendFallbackUsed = backendFocusUsed;
    priority.backendFallbackKind = backendFocusUsed ? L"backend_focus" : L"";
    priority.backendFallbackReason = backendFocusUsed ? L"Alt+Tab and visible taskbar/window click both failed" : L"";
    priority.attempt3Result = backendFocusUsed ? (backendFocusOk ? L"succeeded" : L"failed") : L"not_attempted";
    priority.finalModeUsed = altTabOk ? L"alt_tab_keyboard_switch" : (visibleClickOk ? L"visible_taskbar_or_window_click" : (backendFocusUsed ? L"backend_focus_fallback" : L"fail_stop"));
    VisibleOperationPolicyResult focusPolicy = enforce_visible_operation_priority(priority);

    std::wstring guardFields = RuntimeGuardFields(guardState, result.ok);
    std::wstring data = L"{";
    if (!guardFields.empty()) {
        data += guardFields + L",";
    }
    data += ActionFocusFields(selected, title, result.foregroundBefore, result.foregroundAfter, result.focusVerified)
        + L",\"focus_executed\":" + std::wstring(result.ok ? L"true" : L"false")
        + L",\"focus_path\":" + JsonString(focusPolicy.finalModeUsed)
        + L",\"alt_tab_attempted\":" + std::wstring(altTabAttempted ? L"true" : L"false")
        + L",\"alt_tab_cycles\":" + std::to_wstring(altTabCycles)
        + L",\"visible_click_attempt_count\":" + std::to_wstring(visibleClickAttemptCount)
        + L",\"backend_focus_used\":" + std::wstring(backendFocusUsed ? L"true" : L"false")
        + L",\"operation_priority\":" + VisibleOperationPolicyJson(focusPolicy)
        + L"}";

    if (!focusPolicy.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), focusPolicy.errorCode.empty() ? L"V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION" : focusPolicy.errorCode, focusPolicy.errorMessage, data, 1);
    }
    if (result.ok && !VerifyRuntimeGuardAfterAction(command, startTick, MakeTraceTarget(selected), guardTarget, L"\"focus_executed\":true", guardState, guardExit)) {
        return guardExit;
    }
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandWindowActivation(int argc, wchar_t** argv, const std::wstring& command) {
    ULONGLONG startTick = GetTickCount64();
    std::wstring title;
    std::wstring hwndArg;
    std::wstring process;
    int timeoutMs = 1500;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--process", process);
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, WithSuggestedCommand(L"{}", command + L" --title <partial_title>"), 2);
    }
    if (timeoutMs < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--timeout-ms must be non-negative.", WithSuggestedCommand(L"{}", command + L" --title <partial_title>"), 2);
    }
    if (title.empty() && hwndArg.empty() && process.empty()) {
        std::wstring data = L"{\"candidate_windows\":" + CandidateWindowsJson(EnumerateVisibleTopLevelWindows()) + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", command + L" requires --title, --hwnd, or --process.", WithSuggestedCommand(data, command + L" --title <partial_title>"), 2);
    }

    std::wstring priorityParseError;
    VisibleOperationPolicyOptions switchPriority = ParseVisibleOperationPriorityArgs(argc, argv, L"window_switch", L"backend_fallback", true, L"backend_focus", priorityParseError);
    switchPriority.backendFallbackUsed = true;
    switchPriority.backendFallbackKind = L"backend_focus";
    switchPriority.finalModeUsed = L"backend_fallback";
    if (!priorityParseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", priorityParseError, L"{}", 2);
    }
    VisibleOperationPolicyResult switchPolicy = enforce_visible_operation_priority(switchPriority);
    if (!switchPolicy.ok) {
        return EmitVisibleOperationPriorityFailure(command, startTick, NoTraceTarget(), switchPolicy, 1);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveWindowByTitleHwndProcess(title, hwndArg, process, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, errorCode == L"WINDOW_NOT_UNIQUE" ? 1 : 1);
    }

    std::wstring canonical = command == L"focus-window" ? L"activate-window" : command;
    bool ok = false;
    HWND foregroundBefore = GetForegroundWindow();
    HWND foregroundAfter = foregroundBefore;
    bool windowMinimized = false;
    ForegroundPreparationResult prep;

    if (command == L"minimize-window") {
        ShowWindow(selected.hwnd, SW_MINIMIZE);
        Sleep(80);
        foregroundAfter = GetForegroundWindow();
        windowMinimized = IsIconic(selected.hwnd) != FALSE;
        ok = windowMinimized;
    } else if (command == L"restore-window") {
        ShowWindow(selected.hwnd, SW_RESTORE);
        prep = PrepareForegroundForVisibleUiTask(selected, timeoutMs);
        foregroundBefore = prep.foregroundBefore;
        foregroundAfter = prep.foregroundAfter;
        ok = prep.ok;
    } else {
        prep = PrepareForegroundForVisibleUiTask(selected, timeoutMs);
        foregroundBefore = prep.foregroundBefore;
        foregroundAfter = prep.foregroundAfter;
        ok = prep.ok;
    }

    bool foregroundAfterPresent = foregroundAfter == selected.hwnd;
    std::wstringstream data;
    data << L"{\"canonical_command\":" << JsonString(canonical)
         << L",\"target_window_title\":" << JsonString(selected.title)
         << L",\"hwnd\":" << JsonString(FormatHwnd(selected.hwnd))
         << L",\"pid\":" << selected.pid
         << L",\"process_name\":" << JsonString(ProcessNameForPid(selected.pid))
         << L",\"foreground_before\":" << HwndJson(foregroundBefore)
         << L",\"foreground_after\":" << HwndJson(foregroundAfter)
         << L",\"foreground_after_present\":" << (foregroundAfterPresent ? L"true" : L"false")
         << L",\"window_minimized\":" << (windowMinimized ? L"true" : L"false")
         << L",\"target_visible_after\":" << (VerifyTargetWindowVisible(selected.hwnd) ? L"true" : L"false")
         << L",\"duration_ms\":" << ElapsedMs(startTick);
    if (prep.attempted) {
        data << L",\"foreground_preparation\":" << ForegroundPreparationJson(prep);
    }
    data << L"}";

    if (!ok) {
        std::wstring failureCode = command == L"minimize-window" ? L"WINDOW_FOCUS_FAILED" : (prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode);
        std::wstring failureMessage = command == L"minimize-window" ? L"Target window could not be minimized." : (prep.errorMessage.empty() ? L"Target window could not be activated." : prep.errorMessage);
        return EmitFailure(command, startTick, MakeTraceTarget(selected), failureCode, failureMessage, data.str(), 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data.str());
}

int CommandPrepareForeground(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"prepare-foreground";
    std::wstring title;
    std::wstring hwndArg;
    std::wstring process;
    int timeoutMs = 1500;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--process", process);
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    WindowInfo selected;
    bool hasTarget = false;
    if (!title.empty() || !hwndArg.empty() || !process.empty()) {
        std::wstring errorCode;
        std::wstring errorMessage;
        std::wstring dataJson;
        if (!ResolveWindowByTitleHwndProcess(title, hwndArg, process, selected, errorCode, errorMessage, dataJson)) {
            return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
        }
        hasTarget = true;
    }

    ForegroundPreparationResult prep = hasTarget
        ? PrepareForegroundForVisibleUiTask(selected, timeoutMs)
        : PrepareForegroundForVisibleUiTask(nullptr, timeoutMs);
    std::wstring data = ForegroundPreparationJson(prep);
    if (!prep.ok) {
        return EmitFailure(command, startTick, hasTarget ? MakeTraceTarget(selected) : NoTraceTarget(), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, hasTarget ? MakeTraceTarget(selected) : NoTraceTarget(), data);
}

int CommandPyCharmDevDemo(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"pycharm-dev-demo";
    std::wstring project = L"D:\\testrepo\\pycharm_sanity";
    std::wstring fileName = L"main.py";
    std::wstring codeProfile = L"two-class-demo";
    int timeoutMs = 90000;
    LatencyProfile latencyProfile = LatencyProfile::FastVisibleUi;
    std::wstring latencyProfileError;
    std::wstring parseError;

    ArgValue(argc, argv, L"--project", project);
    ArgValue(argc, argv, L"--file", fileName);
    ArgValue(argc, argv, L"--code-profile", codeProfile);
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (ArgExists(argc, argv, L"--latency-profile")) {
        if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
        }
    }
    if (project.empty() || ToLowerInvariant(project).rfind(L"d:\\testrepo\\pycharm_sanity", 0) != 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"pycharm-dev-demo may only write under D:\\testrepo\\pycharm_sanity.", L"{\"project\":" + JsonString(project) + L"}", 2);
    }
    if (fileName.empty() || fileName.find(L"\\") != std::wstring::npos || fileName.find(L"/") != std::wstring::npos) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--file must be a filename within the safe test project.", L"{\"file\":" + JsonString(fileName) + L"}", 2);
    }
    if (codeProfile != L"two-class-demo") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--code-profile currently supports two-class-demo.", L"{\"code_profile\":" + JsonString(codeProfile) + L"}", 2);
    }

    std::wstring pycharmExe = FindPyCharmExecutable();
    if (pycharmExe.empty()) {
        std::wstring data = L"{\"project\":" + JsonString(project)
            + L",\"pycharm_executable_found\":false"
            + L",\"backend_fallback_used\":false"
            + L",\"skipped\":true"
            + L"}";
        return EmitFailure(command, startTick, NoTraceTarget(), L"PYCHARM_NOT_FOUND", L"PyCharm executable was not found.", data, 1);
    }

    EnsureDirectoryPath(project);
    std::wstring filePath = project + L"\\" + fileName;
    std::wstring outputPath = project + L"\\demo_output.txt";

    std::vector<WindowInfo> pycharmWindows = FindWindowsByTitleAndProcess(L"", L"pycharm64.exe");
    WindowInfo selected;
    bool hasWindow = false;
    if (!pycharmWindows.empty()) {
        selected = pycharmWindows.front();
        hasWindow = true;
    } else {
        ForegroundPreparationResult preLaunchPrep = PrepareForegroundForVisibleUiTask(nullptr, 350);
        (void)preLaunchPrep;
        SHELLEXECUTEINFOW info = {};
        info.cbSize = sizeof(info);
        info.fMask = SEE_MASK_NOCLOSEPROCESS;
        info.lpVerb = L"open";
        info.lpFile = pycharmExe.c_str();
        std::wstring params = QuoteProcessArg(project);
        info.lpParameters = params.c_str();
        info.nShow = SW_SHOWNORMAL;
        if (!ShellExecuteExW(&info)) {
            DWORD code = GetLastError();
            std::wstring data = L"{\"project\":" + JsonString(project)
                + L",\"pycharm_executable\":" + JsonString(pycharmExe)
                + L",\"win32_error\":" + std::to_wstring(code)
                + L"}";
            return EmitFailure(command, startTick, NoTraceTarget(), L"PYCHARM_LAUNCH_FAILED", L"Could not launch PyCharm.", data, 1);
        }
        if (info.hProcess) {
            WaitForInputIdle(info.hProcess, static_cast<DWORD>(MinInt(timeoutMs, 30000)));
            CloseHandle(info.hProcess);
        }
        std::vector<WindowInfo> matches;
        WaitForLaunchTarget(L"PyCharm", L"pycharm64.exe", MinInt(timeoutMs, LatencyProfileDefaultLaunchWaitMs(latencyProfile) + 4000), matches);
        if (matches.empty()) {
            matches = FindWindowsByTitleAndProcess(L"", L"pycharm64.exe");
        }
        if (!matches.empty()) {
            selected = matches.front();
            hasWindow = true;
        }
    }

    ForegroundPreparationResult prep;
    bool visibleSurfaceUsable = false;
    if (hasWindow) {
        prep = PrepareForegroundForVisibleUiTask(selected, MinInt(timeoutMs, 2500));
        if (prep.ok) {
            UiaQueryResult uia = ReadUiaTree(selected.hwnd);
            if (uia.ok) {
                for (const auto& element : uia.elements) {
                    std::wstring text = element.name + L" " + element.controlType;
                    if (ContainsInsensitive(text, L"main.py") || ContainsInsensitive(text, L"editor") || ContainsInsensitive(text, L"project")) {
                        visibleSurfaceUsable = true;
                        break;
                    }
                }
            }
        }
    }

    bool backendFallbackUsed = !hasWindow || !prep.ok || !visibleSurfaceUsable;
    std::wstring fallbackReason = backendFallbackUsed ? L"pycharm_visible_surface_unusable" : L"";
    WriteSmallTextFile(filePath, TwoClassPythonDemoCode());

    std::wstring cmdLine = L"/C cd /d " + QuoteProcessArg(project)
        + L" && (py -3 " + QuoteProcessArg(fileName) + L" > " + QuoteProcessArg(outputPath)
        + L" 2>&1 || python " + QuoteProcessArg(fileName) + L" > " + QuoteProcessArg(outputPath) + L" 2>&1)";
    SHELLEXECUTEINFOW runInfo = {};
    runInfo.cbSize = sizeof(runInfo);
    runInfo.fMask = SEE_MASK_NOCLOSEPROCESS;
    runInfo.lpVerb = L"open";
    runInfo.lpFile = L"cmd.exe";
    runInfo.lpParameters = cmdLine.c_str();
    runInfo.nShow = SW_HIDE;
    DWORD exitCode = 9999;
    bool runnerStarted = ShellExecuteExW(&runInfo) != FALSE;
    if (runnerStarted && runInfo.hProcess) {
        WaitForSingleObject(runInfo.hProcess, static_cast<DWORD>(MinInt(timeoutMs, 30000)));
        GetExitCodeProcess(runInfo.hProcess, &exitCode);
        CloseHandle(runInfo.hProcess);
    }

    FileReadResult outputRead = ReadTextFile(outputPath);
    std::wstring output = outputRead.ok ? outputRead.content : L"";
    bool verified = output.find(L"Course:DesktopVisual") != std::wstring::npos &&
                    output.find(L"Alice") != std::wstring::npos &&
                    output.find(L"Bob") != std::wstring::npos;
    std::wstring data = L"{\"project_path\":" + JsonString(project)
        + L",\"file\":" + JsonString(fileName)
        + L",\"file_path\":" + JsonString(filePath)
        + L",\"code_profile\":" + JsonString(codeProfile)
        + L",\"pycharm_executable\":" + JsonString(pycharmExe)
        + L",\"pycharm_window_found\":" + std::wstring(hasWindow ? L"true" : L"false")
        + L",\"pycharm_window_title\":" + JsonString(hasWindow ? selected.title : L"")
        + L",\"hwnd\":" + JsonString(hasWindow ? FormatHwnd(selected.hwnd) : L"")
        + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile))
        + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep)
        + L",\"visible_surface_usable\":" + std::wstring(visibleSurfaceUsable ? L"true" : L"false")
        + L",\"backend_fallback_used\":" + std::wstring(backendFallbackUsed ? L"true" : L"false")
        + L",\"reason\":" + JsonString(fallbackReason)
        + L",\"runner_started\":" + std::wstring(runnerStarted ? L"true" : L"false")
        + L",\"python_exit_code\":" + std::to_wstring(exitCode)
        + L",\"output_path\":" + JsonString(outputPath)
        + L",\"output_excerpt\":" + JsonString(output.substr(0, 500))
        + L",\"demo_output_verified\":" + std::wstring(verified ? L"true" : L"false")
        + L"}";
    if (!verified) {
        return EmitFailure(command, startTick, hasWindow ? MakeTraceTarget(selected) : NoTraceTarget(), L"PYCHARM_DEMO_OUTPUT_NOT_VERIFIED", L"Two-class demo output was not verified.", data, 1);
    }
    return EmitSuccess(command, startTick, hasWindow ? MakeTraceTarget(selected) : NoTraceTarget(), data);
}

int CommandActiveWindow(const std::wstring& command = L"active-window", const std::wstring& canonicalCommand = L"") {
    ULONGLONG startTick = GetTickCount64();
    WindowInfo active;
    if (!ActiveWindowInfo(active)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"UNKNOWN_ERROR", L"No active window was available.", L"{}", 1);
    }
    std::wstringstream data;
    data << L"{";
    if (!canonicalCommand.empty()) {
        data << L"\"canonical_command\":" << JsonString(canonicalCommand) << L",";
    }
    data << L"\"hwnd\":" << JsonString(FormatHwnd(active.hwnd))
         << L",\"pid\":" << active.pid
         << L",\"title\":" << JsonString(active.title)
         << L",\"process_name\":" << JsonString(ProcessNameForPid(active.pid))
         << L",\"rect\":" << WindowRectJson(active)
         << L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(active), data.str());
}

int CommandMousePosition(const std::wstring& command = L"mouse-position", const std::wstring& canonicalCommand = L"") {
    ULONGLONG startTick = GetTickCount64();
    POINT point = {};
    if (!GetCursorPos(&point)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"UNKNOWN_ERROR", L"GetCursorPos failed.", L"{}", 1);
    }
    std::wstring data = L"{";
    if (!canonicalCommand.empty()) {
        data += L"\"canonical_command\":" + JsonString(canonicalCommand) + L",";
    }
    data += L"\"screen_x\":" + std::to_wstring(point.x)
        + L",\"screen_y\":" + std::to_wstring(point.y) + L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandDesktopMouseVariant(int argc, wchar_t** argv, const std::wstring& command) {
    ULONGLONG startTick = GetTickCount64();
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    std::wstring permissionModeText;
    std::wstring fullAccessSessionId;
    std::wstring resultJsonPath;
    std::wstring targetDescription = L"desktop screen coordinate";
    std::wstring coordinateSource = L"manual_fixed";
    bool allowSyntheticProfile = false;
    bool humanmode = true;
    int moveDurationMs = 0;
    int dwellBeforeClickMs = 180;
    int doubleClickIntervalMs = 140;
    int postClickSettleMs = 180;
    int targetEpsilonPx = 3;
    int motionFrameRateHz = 0;
    int motionHz = 0;
    int screenX = 0;
    int screenY = 0;
    std::wstring motionProfile;
    TargetRectSpec targetRect;
    TargetWindowLockOptions targetLockOptions = ParseTargetWindowLockOptionsFromArgs(argc, argv);
    TargetWindowLockResult targetLock;
    ScreenshotCoordinateMappingResult coordinateMapping;
    LatencyProfile latencyProfile = LatencyProfile::Normal;
    std::wstring latencyProfileError;
    if (!ParseIntArg(argc, argv, L"--screen-x", screenX) || !ParseIntArg(argc, argv, L"--screen-y", screenY)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", command + L" requires --screen-x and --screen-y.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    ArgValue(argc, argv, L"--permission-mode", permissionModeText);
    ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
    ArgValue(argc, argv, L"--result-json", resultJsonPath);
    ArgValue(argc, argv, L"--target-description", targetDescription);
    ArgValue(argc, argv, L"--coordinate-source", coordinateSource);
    ArgValue(argc, argv, L"--motion-profile", motionProfile);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
    }
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--humanmode", humanmode, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--move-duration-ms", moveDurationMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--dwell-before-click-ms", dwellBeforeClickMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--double-click-interval-ms", doubleClickIntervalMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--post-click-settle-ms", postClickSettleMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--target-epsilon-px", targetEpsilonPx, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--motion-frame-rate", motionFrameRateHz, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--motion-hz", motionHz, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--target-rect-left", targetRect.left, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--target-rect-top", targetRect.top, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--target-rect-right", targetRect.right, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--target-rect-bottom", targetRect.bottom, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    targetRect.provided = ArgExists(argc, argv, L"--target-rect-left") ||
                          ArgExists(argc, argv, L"--target-rect-top") ||
                          ArgExists(argc, argv, L"--target-rect-right") ||
                          ArgExists(argc, argv, L"--target-rect-bottom");
    if (moveDurationMs < 0 || dwellBeforeClickMs < 0 || doubleClickIntervalMs < 0 || postClickSettleMs < 0 || targetEpsilonPx < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"HumanMode pacing parameters must be non-negative.", L"{}", 2);
    }
    if (motionHz > 0) {
        motionFrameRateHz = motionHz;
    }
    if (!motionProfile.empty() && motionProfile != L"165hz" && motionProfile != L"165hz-visible") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--motion-profile must be 165hz or 165hz-visible when provided.", L"{}", 2);
    }
    if ((motionProfile == L"165hz" || motionProfile == L"165hz-visible") && motionFrameRateHz == 0) {
        motionFrameRateHz = 165;
    }
    if (motionFrameRateHz < 0 || motionFrameRateHz > 500) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--motion-frame-rate must be between 0 and 500.", L"{}", 2);
    }
    if (targetRect.provided && (targetRect.right <= targetRect.left || targetRect.bottom <= targetRect.top)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Target rect must be non-empty when provided.", L"{}", 2);
    }
    bool targetGateRequested = targetLockOptions.requireTargetLock || HasTargetWindowSelector(targetLockOptions) || targetLockOptions.allowGlobalDesktop;
    if (targetGateRequested) {
        targetLock = acquire_target_window_lock(targetLockOptions);
        if (!targetLock.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), targetLock.errorCode.empty() ? L"FAIL_TARGET_LOCK_REQUIRED" : targetLock.errorCode, targetLock.errorMessage, L"{\"target_lock\":" + TargetWindowLockJson(targetLock) + L"}", 1);
        }
        if (targetLock.targetWindowLocked && !validate_action_point_inside_target(targetLock, screenX, screenY)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"FAIL_CLICK_POINT_OUTSIDE_TARGET", L"Click point is outside the locked target window.", L"{\"screen_x\":" + std::to_wstring(screenX) + L",\"screen_y\":" + std::to_wstring(screenY) + L",\"target_lock\":" + TargetWindowLockJson(targetLock) + L"}", 1);
        }
    }
    ScreenshotCoordinateMappingInput mappingInput;
    mappingInput.direction = L"screen-to-pixel";
    mappingInput.captureScope = L"global_desktop";
    mappingInput.captureRect.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    mappingInput.captureRect.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    mappingInput.captureRect.right = mappingInput.captureRect.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    mappingInput.captureRect.bottom = mappingInput.captureRect.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
    mappingInput.capturePhysicalWidth = mappingInput.captureRect.right - mappingInput.captureRect.left;
    mappingInput.capturePhysicalHeight = mappingInput.captureRect.bottom - mappingInput.captureRect.top;
    mappingInput.screenX = screenX;
    mappingInput.screenY = screenY;
    mappingInput.hasTargetRect = targetLock.targetWindowLocked;
    mappingInput.targetRect = targetLock.lockedRect;
    coordinateMapping = MapScreenshotCoordinate(mappingInput);
    if (!coordinateMapping.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), coordinateMapping.errorCode.empty() ? L"FAIL_UNSAFE_COORDINATE_SOURCE" : coordinateMapping.errorCode, coordinateMapping.errorMessage, L"{\"coordinate_mapping\":" + ScreenshotCoordinateMappingJson(coordinateMapping) + L"}", 1);
    }
    if (latencyProfile == LatencyProfile::FastVisibleUi) {
        if (!ArgExists(argc, argv, L"--move-duration-ms")) moveDurationMs = 0;
        if (!ArgExists(argc, argv, L"--dwell-before-click-ms")) dwellBeforeClickMs = 0;
        if (!ArgExists(argc, argv, L"--double-click-interval-ms")) doubleClickIntervalMs = 0;
        if (!ArgExists(argc, argv, L"--post-click-settle-ms")) postClickSettleMs = 0;
        if (!ArgExists(argc, argv, L"--target-epsilon-px")) targetEpsilonPx = 0;
    }

    std::wstring semanticParseError;
    TargetSemanticsSpec semanticSpec = ParseTargetSemanticsSpecFromArgs(argc, argv, semanticParseError);
    if (!semanticParseError.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", semanticParseError, L"{}", 2);
    }
    TargetSemanticsContext semanticContext = ParseTargetSemanticsContextFromArgs(argc, argv);
    if (!semanticContext.hasTargetRect && targetRect.provided) {
        semanticContext.hasTargetRect = true;
        semanticContext.targetRect.left = targetRect.left;
        semanticContext.targetRect.top = targetRect.top;
        semanticContext.targetRect.right = targetRect.right;
        semanticContext.targetRect.bottom = targetRect.bottom;
    }
    TargetSemanticsGuardResult semanticResult = EvaluateTargetSemanticsGuard(semanticSpec, semanticContext);
    PersistTargetSemanticsGuardResult(semanticSpec, semanticResult, command, false);
    std::wstring semanticFields = TargetSemanticsGuardFields(semanticSpec, semanticResult);
    std::wstring actionFailureFields = command == L"desktop-move"
        ? L"\"mouse_move_sent\":false"
        : (command == L"desktop-double-click" ? L"\"double_click_sent\":false,\"click_sent\":false" : L"\"click_sent\":false");
    if (!semanticResult.ok) {
        if (!resultJsonPath.empty()) {
            WriteSmallTextFile(
                resultJsonPath,
                CommandFailureJson(command, startTick, NoTraceTarget(), semanticResult.stopCode, semanticResult.reason, L"{" + JoinJsonFields(semanticFields, actionFailureFields) + L"}"));
        }
        return EmitTargetSemanticsGuardFailure(command, startTick, NoTraceTarget(), semanticSpec, semanticResult, actionFailureFields);
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, GuardTargetFromScreenPoint(screenX, screenY, targetRect));
    int guardExit = 0;
    std::wstring guardFailureExtra = JoinJsonFields(semanticFields, actionFailureFields);
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, NoTraceTarget(), guardTarget, L"", guardFailureExtra, guardState, guardExit)) {
        return guardExit;
    }

    PermissionMode permissionMode;
    if (!ParsePermissionMode(permissionModeText.empty() ? DefaultPermissionModeName() : permissionModeText, permissionMode)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--permission-mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.", L"{}", 2);
    }
    SafetyPolicy policy = LoadSafetyPolicy();
    if (!policy.allowAbsoluteScreenClick) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"SAFETY_POLICY_DENIED", L"Absolute screen coordinate input is disabled by safety.conf.", SafetyPolicySummaryJson(policy), 1);
    }
    SafetyManifest manifest = LoadSafetyManifest();
    PermissionDecision permissionDecision = EvaluatePermissionRequest(manifest, L"Desktop", L"explorer.exe", L"global_desktop", permissionMode, fullAccessSessionId);
    if (!permissionDecision.allow) {
        return EmitFailure(command, startTick, NoTraceTarget(), permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode, permissionDecision.reason, L"{\"permission_decision\":" + PermissionDecisionJson(permissionDecision) + L"}", 1);
    }

    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(nullptr, latencyProfile == LatencyProfile::FastVisibleUi ? 350 : 1000);

    ClickResult result;
    if (humanmode) {
        HumanMouseMotionOptions options;
        options.moveDurationMs = moveDurationMs > 0 ? moveDurationMs : (latencyProfile == LatencyProfile::FastVisibleUi ? 0 : 500);
        options.dwellBeforeClickMs = dwellBeforeClickMs;
        options.doubleClickIntervalMs = doubleClickIntervalMs;
        options.postClickSettleMs = postClickSettleMs;
        options.targetEpsilonPx = targetEpsilonPx;
        options.motionFrameRateHz = motionFrameRateHz;
        ApplyLatencyProfile(options, latencyProfile);
        if (moveMode == L"instant") {
            result.humanmode = true;
            result.targetScreenX = screenX;
            result.targetScreenY = screenY;
            result.errorCode = L"FAIL_UNSUPPORTED";
            result.error = L"instant move mode is not allowed when --humanmode true.";
        } else if (command == L"desktop-move") {
            result = MoveMouseHumanMode(screenX, screenY, options);
        } else if (command == L"desktop-double-click") {
            result = DoubleClickHumanMode(screenX, screenY, options);
        } else if (command == L"desktop-right-click") {
            result = RightClickHumanMode(screenX, screenY, options);
        } else {
            result = ClickHumanMode(screenX, screenY, options);
        }
    } else {
        if (command == L"desktop-move") {
            result = MoveScreenPoint(screenX, screenY, moveMode, moveDurationMs, profilePath, allowSyntheticProfile);
            if (!result.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(result.errorCode)) {
                result = MoveScreenPoint(screenX, screenY, L"fast-human", moveDurationMs);
                result.fallbackUsed = true;
            }
        } else if (command == L"desktop-double-click") {
            result = DoubleClickScreenPoint(screenX, screenY, moveMode, moveDurationMs, profilePath, allowSyntheticProfile);
            if (!result.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(result.errorCode)) {
                result = DoubleClickScreenPoint(screenX, screenY, L"fast-human", moveDurationMs);
                result.fallbackUsed = true;
            }
        } else if (command == L"desktop-right-click") {
            result = RightClickScreenPoint(screenX, screenY, moveMode, moveDurationMs, profilePath, allowSyntheticProfile);
            if (!result.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(result.errorCode)) {
                result = RightClickScreenPoint(screenX, screenY, L"fast-human", moveDurationMs);
                result.fallbackUsed = true;
            }
        } else {
            result = ClickScreenPoint(screenX, screenY, moveMode, moveDurationMs, profilePath, allowSyntheticProfile);
            if (!result.ok && IsOperatorRequestedMove(moveMode) && fallback == L"fast-human" && IsMotionProfileFailure(result.errorCode)) {
                result = ClickScreenPoint(screenX, screenY, L"fast-human", moveDurationMs);
                result.fallbackUsed = true;
            }
        }
    }
    if (!result.ok) {
        std::wstring actionId = command + L"-" + std::to_wstring(startTick);
        std::wstring humanResult = HumanActionResultJson(command, result, actionId, targetDescription, coordinateSource, targetRect, 1);
        if (!resultJsonPath.empty()) WriteSmallTextFile(resultJsonPath, humanResult);
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, RuntimeGuardEnvelope(guardState, true, JoinJsonFields(semanticFields, L"\"permission_decision\":" + PermissionDecisionJson(permissionDecision) + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile)) + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L",\"target_lock\":" + TargetWindowLockJson(targetLock) + L",\"coordinate_mapping\":" + ScreenshotCoordinateMappingJson(coordinateMapping) + L",\"human_action_result\":" + humanResult + L"," + actionFailureFields)), 1);
    }
    if (targetLock.targetWindowLocked && !verify_foreground_after_action(targetLock)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"FAIL_FOREGROUND_DRIFTED", L"Foreground drifted away from the locked target after action.", L"{\"target_lock\":" + TargetWindowLockJson(targetLock) + L"}", 1);
    }
    if (!VerifyRuntimeGuardAfterAction(command, startTick, NoTraceTarget(), guardTarget, guardFailureExtra, guardState, guardExit)) {
        return guardExit;
    }

    WindowInfo active;
    ActiveWindowInfo(active);
    std::wstring actionId = command + L"-" + std::to_wstring(startTick);
    std::wstring humanResult = HumanActionResultJson(command, result, actionId, targetDescription, coordinateSource, targetRect, 0);
    if (!resultJsonPath.empty()) WriteSmallTextFile(resultJsonPath, humanResult);
    std::wstringstream fields;
    std::wstring guardFields = RuntimeGuardFields(guardState, true, semanticFields);
    fields << L"{";
    if (!guardFields.empty()) fields << guardFields << L",";
    fields << L"\"permission_mode\":" << JsonString(PermissionModeName(permissionMode))
           << L",\"permission_decision\":" << PermissionDecisionJson(permissionDecision)
           << L",\"latency_profile\":" << JsonString(LatencyProfileName(latencyProfile))
           << L",\"foreground_preparation\":" << ForegroundPreparationJson(prep)
           << L",\"target_lock\":" << TargetWindowLockJson(targetLock)
           << L",\"coordinate_mapping\":" << ScreenshotCoordinateMappingJson(coordinateMapping)
           << L",\"action_method\":" << JsonString(result.actionMethod)
           << L",\"target_description\":" << JsonString(targetDescription)
           << L",\"coordinate_space\":\"screen\""
           << L",\"coordinate_source\":" << JsonString(coordinateSource)
           << L",\"target_screen_x\":" << result.targetScreenX
           << L",\"target_screen_y\":" << result.targetScreenY
           << L",\"cursor_before_x\":" << result.cursorBeforeX
           << L",\"cursor_before_y\":" << result.cursorBeforeY
           << L",\"cursor_after_x\":" << result.cursorAfterX
           << L",\"cursor_after_y\":" << result.cursorAfterY
           << L",\"foreground_window_title\":" << JsonString(active.title)
           << L",\"foreground_process\":" << JsonString(ProcessNameForPid(active.pid))
           << L",\"humanmode\":" << (humanmode ? L"true" : L"false")
           << L",\"backend_action\":false"
           << L",\"human_action_result\":" << humanResult
           << L"," << ClickMotionFields(result) << L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), fields.str());
}

bool EvaluateGlobalDesktopPermission(
    const std::wstring& command,
    ULONGLONG startTick,
    const std::wstring& permissionModeText,
    const std::wstring& fullAccessSessionId,
    PermissionMode& permissionMode,
    PermissionDecision& permissionDecision,
    int& exitCode) {
    if (!ParsePermissionMode(permissionModeText.empty() ? DefaultPermissionModeName() : permissionModeText, permissionMode)) {
        exitCode = EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--permission-mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.", L"{}", 2);
        return false;
    }
    SafetyManifest manifest = LoadSafetyManifest();
    permissionDecision = EvaluatePermissionRequest(manifest, L"Desktop", L"explorer.exe", L"global_desktop", permissionMode, fullAccessSessionId);
    if (!permissionDecision.allow) {
        exitCode = EmitFailure(command, startTick, NoTraceTarget(), permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode, permissionDecision.reason, L"{\"permission_decision\":" + PermissionDecisionJson(permissionDecision) + L"}", 1);
        return false;
    }
    return true;
}

int CommandDesktopKeyboardVariant(int argc, wchar_t** argv, const std::wstring& command) {
    ULONGLONG startTick = GetTickCount64();
    std::wstring permissionModeText;
    std::wstring fullAccessSessionId;
    std::wstring key;
    std::wstring keys;
    std::wstring text;
    std::wstring typeMode = L"human";
    int charDelayMs = -1;
    TargetWindowLockOptions targetLockOptions = ParseTargetWindowLockOptionsFromArgs(argc, argv);
    TargetWindowLockResult targetLock;
    LatencyProfile latencyProfile = LatencyProfile::Normal;
    std::wstring latencyProfileError;
    ArgValue(argc, argv, L"--permission-mode", permissionModeText);
    ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
    if (!ParseLatencyProfileArg(argc, argv, latencyProfile, latencyProfileError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", latencyProfileError, L"{}", 2);
    }
    PermissionMode permissionMode;
    PermissionDecision permissionDecision;
    int permissionExit = 0;
    if (!EvaluateGlobalDesktopPermission(command, startTick, permissionModeText, fullAccessSessionId, permissionMode, permissionDecision, permissionExit)) {
        return permissionExit;
    }

    std::wstring guardFailureExtra;
    if (command == L"desktop-press") {
        if (!ArgValue(argc, argv, L"--key", key)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"desktop-press requires --key.", L"{}", 2);
        }
        guardFailureExtra = L"\"key_sent\":false";
    } else if (command == L"desktop-hotkey") {
        if (!ArgValue(argc, argv, L"--keys", keys)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"desktop-hotkey requires --keys.", L"{}", 2);
        }
        guardFailureExtra = L"\"key_sent\":false";
    } else {
        if (!ArgValue(argc, argv, L"--text", text)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"desktop-type requires --text.", L"{}", 2);
        }
        ArgValue(argc, argv, L"--type-mode", typeMode);
        std::wstring parseError;
        if (!ParseOptionalIntArg(argc, argv, L"--char-delay-ms", charDelayMs, parseError)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
        }
        if (latencyProfile == LatencyProfile::FastVisibleUi && !ArgExists(argc, argv, L"--char-delay-ms")) {
            charDelayMs = 5;
        }
        guardFailureExtra = L"\"typing_started\":false,\"text_length\":0";
    }

    bool targetGateRequested = targetLockOptions.requireTargetLock || HasTargetWindowSelector(targetLockOptions) || targetLockOptions.allowGlobalDesktop;
    if (targetGateRequested) {
        targetLock = acquire_target_window_lock(targetLockOptions);
        if (!targetLock.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), targetLock.errorCode.empty() ? L"FAIL_TARGET_LOCK_REQUIRED" : targetLock.errorCode, targetLock.errorMessage, L"{\"target_lock\":" + TargetWindowLockJson(targetLock) + L"}", 1);
        }
    }

    RuntimeGuardCommandState guardState;
    RuntimeTargetContext guardTarget = GuardTargetFromArgsOrDefault(argc, argv, RuntimeTargetContext{});
    int guardExit = 0;
    if (!PrepareRuntimeGuardBeforeAction(argc, argv, command, startTick, NoTraceTarget(), guardTarget, L"", guardFailureExtra, guardState, guardExit)) {
        return guardExit;
    }

    WindowInfo activeBefore;
    ActiveWindowInfo(activeBefore);
    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(nullptr, latencyProfile == LatencyProfile::FastVisibleUi ? 350 : 1000);
    std::wstring resultCode;
    std::wstring resultError;
    HWND foregroundBefore = GetForegroundWindow();
    HWND foregroundAfter = foregroundBefore;
    int textLength = 0;
    if (command == L"desktop-press") {
        if (!ArgValue(argc, argv, L"--key", key)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"desktop-press requires --key.", L"{}", 2);
        }
        ActionResult result = targetLock.targetWindowLocked ? PressKey(targetLock.target.hwnd, key) : PressKeyGlobal(key);
        foregroundBefore = result.foregroundBefore;
        foregroundAfter = result.foregroundAfter;
        if (!result.ok) { resultCode = result.errorCode; resultError = result.error; }
    } else if (command == L"desktop-hotkey") {
        if (!ArgValue(argc, argv, L"--keys", keys)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"desktop-hotkey requires --keys.", L"{}", 2);
        }
        ActionResult result = targetLock.targetWindowLocked ? SendHotkey(targetLock.target.hwnd, keys) : SendHotkeyGlobal(keys);
        foregroundBefore = result.foregroundBefore;
        foregroundAfter = result.foregroundAfter;
        if (!result.ok) { resultCode = result.errorCode; resultError = result.error; }
    } else {
        if (!ArgValue(argc, argv, L"--text", text)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"desktop-type requires --text.", L"{}", 2);
        }
        ArgValue(argc, argv, L"--type-mode", typeMode);
        std::wstring parseError;
        if (!ParseOptionalIntArg(argc, argv, L"--char-delay-ms", charDelayMs, parseError)) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
        }
        if (latencyProfile == LatencyProfile::FastVisibleUi && !ArgExists(argc, argv, L"--char-delay-ms")) {
            charDelayMs = 5;
        }
        TypeResult result = targetLock.targetWindowLocked ? TypeText(targetLock.target.hwnd, text, typeMode, charDelayMs) : TypeTextGlobal(text, typeMode, charDelayMs);
        foregroundBefore = result.foregroundBefore;
        foregroundAfter = result.foregroundAfter;
        textLength = result.textLength;
        if (!result.ok) { resultCode = result.errorCode; resultError = result.error; }
    }
    if (resultCode.empty() && targetLock.targetWindowLocked && !verify_foreground_after_action(targetLock)) {
        resultCode = L"FAIL_FOREGROUND_DRIFTED";
        resultError = L"Foreground drifted away from the locked target after keyboard action.";
    }
    std::wstring guardSuccessExtra = command == L"desktop-type"
        ? L"\"typing_started\":true,\"text_length\":" + std::to_wstring(textLength)
        : L"\"key_sent\":true";
    if (resultCode.empty() && !VerifyRuntimeGuardAfterAction(command, startTick, NoTraceTarget(), guardTarget, guardSuccessExtra, guardState, guardExit)) {
        return guardExit;
    }
    if (!resultCode.empty()) {
        std::wstring actionId = command + L"-" + std::to_wstring(startTick);
        std::wstring humanResult = KeyboardHumanActionResultJson(command, actionId, key, keys, textLength, foregroundBefore, foregroundAfter, resultCode, resultError, 1);
        return EmitFailure(command, startTick, NoTraceTarget(), resultCode, resultError, RuntimeGuardEnvelope(guardState, true, L"\"permission_decision\":" + PermissionDecisionJson(permissionDecision) + L",\"latency_profile\":" + JsonString(LatencyProfileName(latencyProfile)) + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L",\"target_lock\":" + TargetWindowLockJson(targetLock) + L",\"human_action_result\":" + humanResult + L"," + guardFailureExtra), 1);
    }
    WindowInfo activeAfter;
    ActiveWindowInfo(activeAfter);
    std::wstring actionId = command + L"-" + std::to_wstring(startTick);
    std::wstring humanResult = KeyboardHumanActionResultJson(command, actionId, key, keys, textLength, foregroundBefore, foregroundAfter, L"", L"", 0);
    std::wstringstream fields;
    std::wstring guardFields = RuntimeGuardFields(guardState, true);
    fields << L"{";
    if (!guardFields.empty()) fields << guardFields << L",";
    fields << L"\"permission_mode\":" << JsonString(PermissionModeName(permissionMode))
           << L",\"permission_decision\":" << PermissionDecisionJson(permissionDecision)
           << L",\"latency_profile\":" << JsonString(LatencyProfileName(latencyProfile))
           << L",\"foreground_preparation\":" << ForegroundPreparationJson(prep)
           << L",\"target_lock\":" << TargetWindowLockJson(targetLock)
           << L",\"target_description\":\"desktop global keyboard\""
           << L",\"key\":" << JsonString(key)
           << L",\"keys\":" << JsonString(keys)
           << L",\"text_length\":" << textLength
           << L",\"foreground_before\":" << HwndJson(foregroundBefore)
           << L",\"foreground_after\":" << HwndJson(foregroundAfter)
           << L",\"foreground_window_title\":" << JsonString(activeAfter.title)
           << L",\"foreground_process\":" << JsonString(ProcessNameForPid(activeAfter.pid))
           << L",\"humanmode\":true"
           << L",\"backend_action\":false"
           << L",\"human_action_result\":" << humanResult
           << L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), fields.str());
}

int CommandReadFile(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"read-file";
    std::wstring path;
    if (!ArgValue(argc, argv, L"--path", path)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"read-file requires --path.", L"{}", 2);
    }

    std::wstring normalizedPath;
    std::wstring safetyError;
    if (!IsReadPathAllowed(path, normalizedPath, safetyError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"SAFETY_POLICY_DENIED", safetyError, L"{\"path\":" + JsonString(path) + L"}", 1);
    }

    FileReadResult result = ReadTextFile(normalizedPath);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FILE_READ_FAILED" : result.errorCode, result.error, L"{\"path\":" + JsonString(normalizedPath) + L"}", 1);
    }

    std::wstringstream data;
    data << L"{\"path\":" << JsonString(normalizedPath)
         << L",\"content\":" << JsonString(result.content)
         << L",\"content_length\":" << result.content.size()
         << L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data.str());
}

int CommandUiaTree(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"uia-tree";
    std::wstring title;
    std::wstring hwndArg;
    std::wstring process;
    ArgValue(argc, argv, L"--title", title);
    ArgValue(argc, argv, L"--hwnd", hwndArg);
    ArgValue(argc, argv, L"--process", process);
    if (title.empty() && hwndArg.empty() && process.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"uia-tree requires --title, --hwnd, or --process.", WithSuggestedCommand(L"{}", L"uia-tree --title <partial_title>"), 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveWindowByTitleHwndProcess(title, hwndArg, process, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(selected);
    if (!prep.ok) {
        std::wstring failure = L"{\"requested_title\":" + JsonString(title)
            + L",\"requested_hwnd\":" + JsonString(hwndArg)
            + L",\"requested_process\":" + JsonString(process)
            + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, failure, 1);
    }

    UiaQueryResult result = ReadUiaTree(selected.hwnd);
    std::wstring data = L"{\"resolved_from_process\":" + std::wstring(!process.empty() && title.empty() && hwndArg.empty() ? L"true" : L"false")
        + L",\"target_window_title\":" + JsonString(selected.title)
        + L",\"hwnd\":" + JsonString(FormatHwnd(selected.hwnd))
        + L",\"foreground_preparation\":" + ForegroundPreparationJson(prep)
        + L",\"elements\":" + UiaElementsJson(result.elements) + L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode, result.errorMessage, data, 1);
    }

    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandUiaFind(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"uia-find";
    std::wstring title;
    std::wstring name;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--name", name)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"uia-find requires --title and --name.", L"{}", 2);
    }
    if (name.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--name must not be empty.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    UiaQueryResult result = FindUiaElementsByName(selected.hwnd, name);
    if (!result.ok) {
        std::wstring data = L"{\"requested_name\":" + JsonString(name) + L",\"matches\":" + UiaElementsJson(result.elements) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode, result.errorMessage, data, 1);
    }

    std::wstring data = L"{\"requested_name\":" + JsonString(name);
    if (!result.elements.empty()) {
        const UiaElementInfo& element = result.elements.front();
        data += L",\"name\":" + JsonString(element.name)
             + L",\"control_type\":" + JsonString(element.controlType)
             + L",\"rect\":" + RectJson(element.rect)
             + L",\"enabled\":" + std::wstring(element.enabled ? L"true" : L"false")
             + L",\"offscreen\":" + std::wstring(element.offscreen ? L"true" : L"false");
    }
    data += L"}";

    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandUiaClick(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"uia-click";
    std::wstring title;
    std::wstring name;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--name", name)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"uia-click requires --title and --name.", L"{}", 2);
    }
    if (name.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--name must not be empty.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    UiaPatternActionResult action = InvokeUiaElementByName(selected.hwnd, name);
    if (!action.found) {
        std::wstring data = L"{\"locate_method\":\"uia\",\"requested_name\":" + JsonString(name) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), action.errorCode, action.errorMessage, data, 1);
    }

    std::wstring actionMethod = L"invoke_pattern";
    std::wstring resultText = L"success";
    if (action.ok && action.patternAvailable) {
        Sleep(200);
    } else if (action.patternAvailable && !action.ok) {
        std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"invoke_pattern\",\"element_name\":" + JsonString(action.element.name)
            + L",\"control_type\":" + JsonString(action.element.controlType)
            + L",\"rect\":" + RectJson(action.element.rect)
            + L",\"result\":\"failed\"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.errorMessage, data, 1);
    } else {
        int clientX = 0;
        int clientY = 0;
        actionMethod = L"mouse_center";
        if (!ElementCenterClientPoint(selected.hwnd, action.element, clientX, clientY)) {
            std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"mouse_center\",\"element_name\":" + JsonString(action.element.name)
                + L",\"control_type\":" + JsonString(action.element.controlType)
                + L",\"rect\":" + RectJson(action.element.rect)
                + L",\"result\":\"failed\"}";
            return EmitFailure(command, startTick, MakeTraceTarget(selected), L"UNKNOWN_ERROR", L"ScreenToClient failed for UIA element center.", data, 1);
        }
        ClickResult click = ClickClientPoint(selected.hwnd, clientX, clientY, L"human", 0);
        if (!click.ok) {
            std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"mouse_center\",\"element_name\":" + JsonString(action.element.name)
                + L",\"control_type\":" + JsonString(action.element.controlType)
                + L",\"rect\":" + RectJson(action.element.rect)
                + L",\"result\":\"failed\"}";
            return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
        }
        actionMethod = L"mouse_center";
    }

    std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":" + JsonString(actionMethod)
        + L",\"element_name\":" + JsonString(action.element.name)
        + L",\"control_type\":" + JsonString(action.element.controlType)
        + L",\"rect\":" + RectJson(action.element.rect)
        + L",\"result\":" + JsonString(resultText)
        + L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandUiaType(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"uia-type";
    std::wstring title;
    std::wstring name;
    std::wstring text;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--name", name) || !ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"uia-type requires --title, --name, and --text.", L"{}", 2);
    }
    if (name.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--name must not be empty.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    UiaPatternActionResult action = SetUiaElementValueByName(selected.hwnd, name, text);
    if (!action.found) {
        std::wstring data = L"{\"locate_method\":\"uia\",\"requested_name\":" + JsonString(name) + L",\"text_length\":" + std::to_wstring(text.size()) + L"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), action.errorCode, action.errorMessage, data, 1);
    }

    std::wstring actionMethod = L"value_pattern";
    std::wstring typeMode = L"value_pattern";
    if (action.ok && action.patternAvailable) {
        Sleep(200);
    } else if (action.patternAvailable && !action.ok) {
        std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"value_pattern\",\"element_name\":" + JsonString(action.element.name)
            + L",\"control_type\":" + JsonString(action.element.controlType)
            + L",\"rect\":" + RectJson(action.element.rect)
            + L",\"text_length\":" + std::to_wstring(text.size())
            + L",\"type_mode\":\"value_pattern\"}";
        return EmitFailure(command, startTick, MakeTraceTarget(selected), action.errorCode.empty() ? L"UNKNOWN_ERROR" : action.errorCode, action.errorMessage, data, 1);
    } else {
        int clientX = 0;
        int clientY = 0;
        actionMethod = L"mouse_center_type";
        typeMode = L"human";
        if (!ElementCenterClientPoint(selected.hwnd, action.element, clientX, clientY)) {
            std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"mouse_center_type\",\"element_name\":" + JsonString(action.element.name)
                + L",\"control_type\":" + JsonString(action.element.controlType)
                + L",\"rect\":" + RectJson(action.element.rect)
                + L",\"text_length\":" + std::to_wstring(text.size())
                + L",\"type_mode\":\"demo-human\"}";
            return EmitFailure(command, startTick, MakeTraceTarget(selected), L"UNKNOWN_ERROR", L"ScreenToClient failed for UIA element center.", data, 1);
        }
        ClickResult click = ClickClientPoint(selected.hwnd, clientX, clientY, L"human", 0);
        if (!click.ok) {
            std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"mouse_center_type\",\"element_name\":" + JsonString(action.element.name)
                + L",\"control_type\":" + JsonString(action.element.controlType)
                + L",\"rect\":" + RectJson(action.element.rect)
                + L",\"text_length\":" + std::to_wstring(text.size())
                + L",\"type_mode\":\"demo-human\"}";
            return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
        }
        TypeResult typed = TypeText(selected.hwnd, text, L"human", -1);
        if (!typed.ok) {
            std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":\"mouse_center_type\",\"element_name\":" + JsonString(action.element.name)
                + L",\"control_type\":" + JsonString(action.element.controlType)
                + L",\"rect\":" + RectJson(action.element.rect)
                + L",\"text_length\":" + std::to_wstring(text.size())
                + L",\"type_mode\":\"demo-human\"}";
            return EmitFailure(command, startTick, MakeTraceTarget(selected), typed.errorCode.empty() ? L"UNKNOWN_ERROR" : typed.errorCode, typed.error, data, 1);
        }
    }

    std::wstring data = L"{\"locate_method\":\"uia\",\"action_method\":" + JsonString(actionMethod)
        + L",\"element_name\":" + JsonString(action.element.name)
        + L",\"control_type\":" + JsonString(action.element.controlType)
        + L",\"rect\":" + RectJson(action.element.rect)
        + L",\"text_length\":" + std::to_wstring(text.size())
        + L",\"type_mode\":" + JsonString(typeMode)
        + L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

std::wstring OcrDataJson(const std::wstring& requestedText, const OcrTextResult& result) {
    std::wstringstream data;
    data << L"{\"requested_text\":" << JsonString(requestedText)
         << L",\"matched_text\":" << JsonString(result.matchedText)
         << L",\"bounding_box\":" << RectJson(result.boundingBox)
         << L",\"coordinate_space\":" << JsonString(result.coordinateSpace.empty() ? L"screen" : result.coordinateSpace)
         << L",\"match_count\":" << result.matchCount;
    if (result.confidence >= 0.0) {
        data << L",\"confidence\":" << result.confidence;
    } else {
        data << L",\"confidence\":null";
    }
    if (!result.screenshotPath.empty()) {
        data << L",\"screenshot_path\":" << JsonString(result.screenshotPath);
    }
    OcrCapability cap = GetOcrCapability();
    data << L",\"ocr_available\":" << (cap.available ? L"true" : L"false")
         << L"}";
    return data.str();
}

std::wstring OcrResultJson(const OcrResult& result) {
    std::wstringstream json;
    json << L"{\"text\":" << JsonString(result.fullText)
         << L",\"line_count\":" << result.lines.size()
         << L",\"word_count\":" << result.allWords.size()
         << L",\"language\":" << JsonString(result.language)
         << L",\"coordinate_space\":" << JsonString(result.coordinateSpace)
         << L",\"ocr_available\":" << (result.ok ? L"true" : L"false");
    if (!result.screenshotPath.empty()) {
        json << L",\"screenshot_path\":" << JsonString(result.screenshotPath);
    }
    json
         << L",\"lines\":[";
    for (size_t i = 0; i < result.lines.size(); ++i) {
        if (i != 0) json << L",";
        json << L"{\"text\":" << JsonString(result.lines[i].text)
             << L",\"rect\":" << RectJson(result.lines[i].boundingBox) << L"}";
    }
    json << L"],\"words\":[";
    for (size_t i = 0; i < result.allWords.size(); ++i) {
        if (i != 0) json << L",";
        json << L"{\"text\":" << JsonString(result.allWords[i].text)
             << L",\"rect\":" << RectJson(result.allWords[i].boundingBox);
        if (result.allWords[i].confidence >= 0.0) {
            json << L",\"confidence\":" << result.allWords[i].confidence;
        }
        json << L"}";
    }
    json << L"]}";
    return json.str();
}

std::wstring OcrCacheRoot() {
    return ArtifactsPath(L"ocr_cache");
}

std::wstring SanitizeFrameArtifactId(std::wstring value) {
    for (auto& ch : value) {
        const bool ok = (ch >= L'a' && ch <= L'z') ||
            (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'0' && ch <= L'9') ||
            ch == L'_' || ch == L'-';
        if (!ok) ch = L'_';
    }
    if (value.empty()) value = L"empty";
    return value;
}

std::wstring OcrCachePathForKey(const std::wstring& cacheKey) {
    EnsureDirectoryPath(OcrCacheRoot());
    return OcrCacheRoot() + L"\\" + SanitizeFrameArtifactId(cacheKey) + L".json";
}

std::wstring RectKey(const RECT& rect) {
    return std::to_wstring(rect.left) + L"_" + std::to_wstring(rect.top) + L"_" +
        std::to_wstring(rect.right) + L"_" + std::to_wstring(rect.bottom);
}

std::wstring MakeOcrCacheKey(
    const FullScreenFrame& frame,
    const RECT& cropRect,
    const std::wstring& scope,
    const std::wstring& tileHash) {
    return L"ocr_" + SanitizeFrameArtifactId(scope) + L"_" + SanitizeFrameArtifactId(frame.frameId) +
        L"_" + SanitizeFrameArtifactId(frame.contentHash) +
        L"_" + SanitizeFrameArtifactId(RectKey(cropRect)) +
        L"_" + SanitizeFrameArtifactId(tileHash) +
        L"_winrt_system";
}

std::wstring OcrTextBlocksJson(const OcrResult& result) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < result.lines.size(); ++i) {
        if (i) json << L",";
        json << L"{\"text\":" << JsonString(result.lines[i].text)
             << L",\"rect\":" << RectJson(result.lines[i].boundingBox) << L"}";
    }
    json << L"]";
    return json.str();
}

std::wstring SetJsonBoolField(std::wstring json, const std::wstring& key, bool value) {
    std::wstring needle = L"\"" + key + L"\":";
    size_t pos = json.find(needle);
    if (pos == std::wstring::npos) {
        if (!json.empty() && json.back() == L'}') {
            json.pop_back();
            if (json.size() > 1) json += L",";
            json += needle + (value ? L"true" : L"false") + L"}";
        }
        return json;
    }
    pos += needle.size();
    if (json.compare(pos, 4, L"true") == 0) {
        json.replace(pos, 4, value ? L"true" : L"false");
    } else if (json.compare(pos, 5, L"false") == 0) {
        json.replace(pos, 5, value ? L"true" : L"false");
    }
    return json;
}

std::wstring SetJsonNumberField(std::wstring json, const std::wstring& key, long long value) {
    std::wstring needle = L"\"" + key + L"\":";
    size_t pos = json.find(needle);
    if (pos == std::wstring::npos) {
        if (!json.empty() && json.back() == L'}') {
            json.pop_back();
            if (json.size() > 1) json += L",";
            json += needle + std::to_wstring(value) + L"}";
        }
        return json;
    }
    pos += needle.size();
    size_t end = pos;
    while (end < json.size() && (json[end] == L'-' || (json[end] >= L'0' && json[end] <= L'9'))) ++end;
    json.replace(pos, end - pos, std::to_wstring(value));
    return json;
}

std::wstring OcrFrameDataJson(
    const FullScreenFrame& frame,
    const OcrResult& result,
    const std::wstring& ocrSource,
    bool pngReadForOcr,
    bool ocrCacheHit,
    bool tileCacheHit,
    const std::wstring& cacheKey,
    const std::wstring& cacheScope,
    const std::wstring& tileHash,
    long long durationMs,
    const std::wstring& extraFields) {
    OcrCapability cap = GetOcrCapability();
    std::wstringstream json;
    json << L"{\"frame_id\":" << JsonString(frame.frameId)
         << L",\"screenshot_id\":" << JsonString(frame.screenshotId)
         << L",\"ocr_source\":" << JsonString(ocrSource)
         << L",\"png_read_for_ocr\":" << (pngReadForOcr ? L"true" : L"false")
         << L",\"evidence_png_path\":" << JsonString(frame.evidencePngPath)
         << L",\"evidence_write_status\":" << JsonString(frame.evidenceWriteStatus)
         << L",\"text\":" << JsonString(result.fullText)
         << L",\"text_blocks\":" << OcrTextBlocksJson(result)
         << L",\"text_count\":" << result.lines.size()
         << L",\"word_count\":" << result.allWords.size()
         << L",\"duration_ms\":" << durationMs
         << L",\"ocr_cache_hit\":" << (ocrCacheHit ? L"true" : L"false")
         << L",\"tile_cache_hit\":" << (tileCacheHit ? L"true" : L"false")
         << L",\"tile_hash\":" << JsonString(tileHash)
         << L",\"cache_key\":" << JsonString(cacheKey)
         << L",\"cache_scope\":" << JsonString(cacheScope)
         << L",\"cache_validated\":true"
         << L",\"ocr_engine\":" << JsonString(cap.engine.empty() ? L"Windows.Media.Ocr.OcrEngine (WinRT)" : cap.engine)
         << L",\"frame_cache_materialized\":true";
    if (!extraFields.empty()) {
        json << L"," << extraFields;
    }
    json << L"}";
    return json.str();
}

bool TryReadOcrCache(const std::wstring& cacheKey, std::wstring& dataJson) {
    std::wstring path = OcrCachePathForKey(cacheKey);
    DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        return false;
    }
    dataJson = ReadSmallTextFile(path);
    if (dataJson.empty()) return false;
    dataJson = SetJsonBoolField(dataJson, L"ocr_cache_hit", true);
    dataJson = SetJsonBoolField(dataJson, L"cache_validated", true);
    return true;
}

void WriteOcrCache(const std::wstring& cacheKey, const std::wstring& dataJson) {
    EnsureDirectoryPath(OcrCacheRoot());
    WriteSmallTextFile(OcrCachePathForKey(cacheKey), dataJson);
}

int CountOcrCacheEntries() {
    EnsureDirectoryPath(OcrCacheRoot());
    int count = 0;
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW((OcrCacheRoot() + L"\\*.json").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return 0;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) ++count;
    } while (FindNextFileW(find, &data));
    FindClose(find);
    return count;
}

int DeleteOcrCacheEntries() {
    EnsureDirectoryPath(OcrCacheRoot());
    int count = 0;
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW((OcrCacheRoot() + L"\\*.json").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return 0;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            std::wstring path = OcrCacheRoot() + L"\\" + data.cFileName;
            if (DeleteFileW(path.c_str())) ++count;
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);
    return count;
}

bool LoadFrameForCommand(
    int argc,
    wchar_t** argv,
    const std::wstring& command,
    FullScreenFrame& frame,
    bool& capturedNew,
    std::wstring& errorCode,
    std::wstring& errorMessage) {
    capturedNew = false;
    bool captureNew = false;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--capture-new", captureNew, parseError)) {
        errorCode = L"INVALID_ARGUMENT";
        errorMessage = parseError;
        return false;
    }
    std::wstring frameId;
    ArgValue(argc, argv, L"--frame-id", frameId);
    if (captureNew || frameId.empty()) {
        if (!captureNew && frameId.empty()) {
            errorCode = L"INVALID_ARGUMENT";
            errorMessage = command + L" requires --frame-id or --capture-new true.";
            return false;
        }
        frame = CaptureFullScreenFrameToRegistry(command, true);
        capturedNew = true;
        if (!frame.ok) {
            errorCode = frame.errorCode.empty() ? L"FRAME_CAPTURE_FAILED" : frame.errorCode;
            errorMessage = frame.errorMessage;
            return false;
        }
        return true;
    }
    return LoadFullScreenFrameFromRegistry(frameId, frame, errorCode, errorMessage);
}

int CommandCaptureFullscreenFrame(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"capture-fullscreen-frame";
    std::wstring originating = command;
    ArgValue(argc, argv, L"--originating-command", originating);
    bool asyncEvidence = true;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--async-evidence", asyncEvidence, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    FullScreenFrame frame = CaptureFullScreenFrameToRegistry(originating, asyncEvidence);
    std::wstring data = FullScreenFrameDataJson(frame);
    if (!frame.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), frame.errorCode.empty() ? L"FRAME_CAPTURE_FAILED" : frame.errorCode, frame.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandEvidenceFlush(int argc, wchar_t** argv, const std::wstring& command = L"evidence-flush") {
    ULONGLONG startTick = GetTickCount64();
    std::wstring frameId;
    ArgValue(argc, argv, L"--frame-id", frameId);
    bool allPending = false;
    bool simulateFailure = false;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--all-pending", allPending, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--simulate-failure", simulateFailure, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (frameId.empty() && !allPending) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"evidence-flush requires --frame-id or --all-pending true.", L"{}", 2);
    }
    FrameFlushResult result = FlushFrameEvidence(frameId, allPending, simulateFailure);
    std::wstring data = FrameFlushDataJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EVIDENCE_FLUSH_FAILED" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandOcrCacheClear() {
    ULONGLONG startTick = GetTickCount64();
    int deleted = DeleteOcrCacheEntries();
    std::wstring data = L"{\"cache_root\":" + JsonString(OcrCacheRoot()) +
        L",\"deleted_count\":" + std::to_wstring(deleted) +
        L",\"entry_count\":0,\"cache_validated\":true}";
    return EmitSuccess(L"ocr-cache-clear", startTick, NoTraceTarget(), data);
}

int CommandOcrCacheStatus() {
    ULONGLONG startTick = GetTickCount64();
    int count = CountOcrCacheEntries();
    std::wstring data = L"{\"cache_root\":" + JsonString(OcrCacheRoot()) +
        L",\"entry_count\":" + std::to_wstring(count) +
        L",\"cache_validated\":true}";
    return EmitSuccess(L"ocr-cache-status", startTick, NoTraceTarget(), data);
}

int CommandOcrFullscreenFrame(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"ocr-fullscreen-frame";
    bool legacyBenchmark = false;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--allow-legacy-png-read-for-benchmark", legacyBenchmark, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    FullScreenFrame frame;
    bool capturedNew = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    if (!LoadFrameForCommand(argc, argv, command, frame, capturedNew, errorCode, errorMessage)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, L"{}", 1);
    }

    RECT fullRect = frame.virtualScreenRect;
    std::wstring tileHash = frame.contentHash;
    std::wstring cacheKey = MakeOcrCacheKey(frame, fullRect, L"full_screen", tileHash);
    std::wstring cachedData;
    if (!legacyBenchmark && TryReadOcrCache(cacheKey, cachedData)) {
        cachedData = SetJsonNumberField(cachedData, L"duration_ms", ElapsedMs(startTick));
        return EmitSuccess(command, startTick, NoTraceTarget(), cachedData);
    }

    OcrResult result;
    if (legacyBenchmark) {
        FrameFlushResult flush = FlushFrameEvidence(frame.frameId, false, false);
        if (!flush.ok) {
            return EmitFailure(command, startTick, NoTraceTarget(), flush.errorCode.empty() ? L"EVIDENCE_FLUSH_FAILED" : flush.errorCode, flush.errorMessage, FrameFlushDataJson(flush), 1);
        }
        frame.evidenceWriteStatus = L"written";
        result = RecognizeImageFileForBenchmark(frame.evidencePngPath, L"legacy_png_file_benchmark");
    } else {
        result = RecognizeBgraFrame(frame.pixels, frame.screenWidth, frame.screenHeight, frame.stride, L"full_screen_frame", frame.rawFrameCachePath);
    }
    const long long duration = ElapsedMs(startTick);
    std::wstring extra = L"\"full_screen_capture\":true,\"capture_new\":" + std::wstring(capturedNew ? L"true" : L"false") +
        L",\"benchmark_only_legacy_path\":" + std::wstring(legacyBenchmark ? L"true" : L"false");
    std::wstring data = OcrFrameDataJson(
        frame,
        result,
        legacyBenchmark ? L"legacy_png_file_benchmark" : L"memory_frame",
        legacyBenchmark,
        false,
        false,
        cacheKey,
        L"full_screen",
        tileHash,
        duration,
        extra);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"OCR_FAILED" : result.errorCode, result.errorMessage, data, 1);
    }
    if (!legacyBenchmark) {
        WriteOcrCache(cacheKey, data);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandOcrForegroundFromFrame(int argc, wchar_t** argv, const std::wstring& command = L"ocr-foreground-from-frame") {
    ULONGLONG startTick = GetTickCount64();
    FullScreenFrame frame;
    bool capturedNew = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    if (!LoadFrameForCommand(argc, argv, command, frame, capturedNew, errorCode, errorMessage)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, L"{}", 1);
    }
    bool forceCropFailure = false;
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--force-crop-failure", forceCropFailure, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    RECT cropRect = frame.foreground.rect;
    if (cropRect.right <= cropRect.left || cropRect.bottom <= cropRect.top) {
        cropRect = frame.virtualScreenRect;
    }
    FullScreenFrame crop = CropFullScreenFrame(frame, cropRect);
    const std::wstring tileHash = crop.ok ? crop.contentHash : L"invalid_crop";
    std::wstring cacheKey = MakeOcrCacheKey(frame, cropRect, L"foreground_crop", tileHash);
    std::wstring cachedData;
    if (!forceCropFailure && crop.ok && TryReadOcrCache(cacheKey, cachedData)) {
        cachedData = SetJsonBoolField(cachedData, L"tile_cache_hit", true);
        cachedData = SetJsonNumberField(cachedData, L"duration_ms", ElapsedMs(startTick));
        return EmitSuccess(command, startTick, NoTraceTarget(), cachedData);
    }

    OcrResult result;
    bool cropOcrSuccess = false;
    bool fallbackUsed = false;
    std::wstring ocrSource = L"memory_frame_crop";
    if (!forceCropFailure && crop.ok) {
        result = RecognizeBgraFrame(crop.pixels, crop.screenWidth, crop.screenHeight, crop.stride, L"memory_frame_crop", frame.rawFrameCachePath);
        cropOcrSuccess = result.ok && !result.fullText.empty();
    }
    if (!cropOcrSuccess) {
        fallbackUsed = true;
        ocrSource = L"memory_frame_full_screen_fallback";
        result = RecognizeBgraFrame(frame.pixels, frame.screenWidth, frame.screenHeight, frame.stride, L"full_screen_frame", frame.rawFrameCachePath);
    }
    const long long duration = ElapsedMs(startTick);
    std::wstringstream extra;
    extra << L"\"crop_from_fullscreen_frame\":true"
          << L",\"partial_screenshot_used\":false"
          << L",\"target_window_hwnd\":" << (frame.foreground.hwnd ? JsonString(FormatHwnd(frame.foreground.hwnd)) : L"null")
          << L",\"target_window_title\":" << JsonString(frame.foreground.title)
          << L",\"foreground_crop_rect\":" << RectJson(cropRect)
          << L",\"crop_ocr_success\":" << (cropOcrSuccess ? L"true" : L"false")
          << L",\"full_screen_ocr_fallback_used\":" << (fallbackUsed ? L"true" : L"false")
          << L",\"same_frame_for_fallback\":true"
          << L",\"screenshot_recaptured_for_fallback\":false"
          << L",\"capture_new\":" << (capturedNew ? L"true" : L"false");
    std::wstring data = OcrFrameDataJson(
        frame,
        result,
        ocrSource,
        false,
        false,
        false,
        cacheKey,
        L"foreground_crop",
        tileHash,
        duration,
        extra.str());
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"OCR_FAILED" : result.errorCode, result.errorMessage, data, 1);
    }
    if (!fallbackUsed && crop.ok) {
        WriteOcrCache(cacheKey, data);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandVlmFrameTransportCheck(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-frame-transport-check";
    std::wstring provider = L"codex-cli";
    std::wstring target;
    ArgValue(argc, argv, L"--provider", provider);
    ArgValue(argc, argv, L"--target", target);
    FullScreenFrame frame;
    bool capturedNew = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    if (!LoadFrameForCommand(argc, argv, command, frame, capturedNew, errorCode, errorMessage)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, L"{}", 1);
    }
    EnsureDirectoryPath(FrameVlmTransportRoot());
    std::wstring vlmInputPath = FrameVlmTransportRoot() + L"\\" + SanitizeFrameArtifactId(frame.frameId) + L"_" + SanitizeFrameArtifactId(provider) + L".png";
    std::wstring pngError;
    bool wrote = WriteFramePngFromBgra(frame.pixels, frame.screenWidth, frame.screenHeight, frame.stride, vlmInputPath, pngError);
    if (!wrote) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"VLM_TRANSPORT_IMAGE_WRITE_FAILED", pngError, L"{\"frame_id\":" + JsonString(frame.frameId) + L"}", 1);
    }
    const bool codexCli = provider == L"codex-cli";
    std::wstringstream data;
    data << L"{\"frame_id\":" << JsonString(frame.frameId)
         << L",\"screenshot_id\":" << JsonString(frame.screenshotId)
         << L",\"provider\":" << JsonString(provider)
         << L",\"target\":" << JsonString(target)
         << L",\"provider_transport\":" << JsonString(codexCli ? L"file_path" : L"unavailable")
         << L",\"provider_requires_file_input\":" << (codexCli ? L"true" : L"false")
         << L",\"supports_memory_bytes\":" << (codexCli ? L"false" : L"false")
         << L",\"vlm_input_image_path\":" << JsonString(vlmInputPath)
         << L",\"evidence_png_path\":" << JsonString(frame.evidencePngPath)
         << L",\"vlm_input_generated_from_frame\":true"
         << L",\"screenshot_recaptured_for_vlm\":false"
         << L",\"ocr_read_vlm_png\":false"
         << L",\"candidate_is_locate_only\":true"
         << L",\"old_mock_vlm_used\":false"
         << L",\"runtime_only_degradation\":" << (codexCli ? L"false" : L"true")
         << L",\"vlm_candidate_fabricated\":false"
         << L",\"capture_new\":" << (capturedNew ? L"true" : L"false")
         << L"}";
    return EmitSuccess(command, startTick, NoTraceTarget(), data.str());
}

int CommandFindText(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"find-text";
    std::wstring title;
    std::wstring text;
    std::wstring matchMode = L"contains";
    bool caseSensitive = false;
    int index = -1;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"find-text requires --title and --text.", L"{}", 2);
    }
    if (text.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--text must not be empty.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--match", matchMode);
    std::wstring parseError;
    if (!ParseOptionalBoolArg(argc, argv, L"--case-sensitive", caseSensitive, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--index", index, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (matchMode != L"exact" && matchMode != L"contains") {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--match must be exact or contains.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }
    OcrTextResult result = FindTextInWindow(selected.hwnd, text, matchMode, caseSensitive, index);
    std::wstring data = OcrDataJson(text, result);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode, result.errorMessage, data, 1);
    }

    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandClickText(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"click-text";
    std::wstring title;
    std::wstring text;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int moveDurationMs = 0;
    int index = -1;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"click-text requires --title and --text.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--move-duration-ms", moveDurationMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--index", index, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (text.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--text must not be empty.", L"{}", 2);
    }
    if (moveDurationMs < 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--move-duration-ms must be non-negative.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    OcrTextResult result = FindTextInWindow(selected.hwnd, text, L"contains", false, index);
    std::wstring data = OcrDataJson(text, result);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode, result.errorMessage, data, 1);
    }

    int bitmapX = result.boundingBox.left + ((result.boundingBox.right - result.boundingBox.left) / 2);
    int bitmapY = result.boundingBox.top + ((result.boundingBox.bottom - result.boundingBox.top) / 2);
    int clientX = 0;
    int clientY = 0;
    if (!WindowBitmapPointToClient(selected.hwnd, bitmapX, bitmapY, clientX, clientY)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"OCR_FAILED", L"Could not convert OCR text center to client coordinates.", data, 1);
    }
    ClickResult click = ApplyClickFallback(selected.hwnd, clientX, clientY, moveMode, moveDurationMs, fallback,
                                           ClickClientPoint(selected.hwnd, clientX, clientY, moveMode, moveDurationMs, profilePath, allowSyntheticProfile));
    if (!click.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
    }

    std::wstring successData = data.substr(0, data.size() - 1)
        + L",\"action_method\":\"mouse_center\""
        + L"," + ActionFocusFields(selected, title, click.foregroundBefore, click.foregroundAfter, click.focusVerified)
        + L"," + ClickMotionFields(click)
        + L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), successData);
}

int CommandReadWindowText(int argc, wchar_t** argv, const std::wstring& command = L"read-window-text", const std::wstring& canonicalCommand = L"") {
    ULONGLONG startTick = GetTickCount64();
    std::wstring title;
    std::wstring outPath;
    if (!ArgValue(argc, argv, L"--title", title)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"read-window-text requires --title.", WithSuggestedCommand(WithCanonicalField(L"{}", canonicalCommand), L"read-window-text --title <partial_title>"), 2);
    }
    ArgValue(argc, argv, L"--out", outPath);

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }
    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(selected);
    if (!prep.ok) {
        std::wstring failure = WithCanonicalField(L"{\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L"}", canonicalCommand);
        return EmitFailure(command, startTick, MakeTraceTarget(selected), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, failure, 1);
    }
    if (!outPath.empty()) {
        std::wstring normalizedOut;
        std::wstring safetyError;
        if (!IsWritePathAllowed(outPath, normalizedOut, safetyError)) {
            return EmitFailure(command, startTick, MakeTraceTarget(selected), L"SAFETY_POLICY_DENIED", safetyError, L"{\"out\":" + JsonString(outPath) + L"}", 1);
        }
        outPath = normalizedOut;
    }

    OcrResult result = ReadWindowText(selected.hwnd, L"");
    if (!result.ok) {
        std::wstring failure = WithCanonicalField(L"{\"foreground_preparation\":" + ForegroundPreparationJson(prep) + L"}", canonicalCommand);
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"OCR_FAILED" : result.errorCode, result.errorMessage, failure, 1);
    }

    if (!outPath.empty()) {
        FILE* file = nullptr;
        if (_wfopen_s(&file, outPath.c_str(), L"w, ccs=UTF-8") == 0 && file) {
            fwprintf(file, L"%ls", result.fullText.c_str());
            fclose(file);
        } else {
            return EmitFailure(command, startTick, MakeTraceTarget(selected), L"UNKNOWN_ERROR", L"Could not write OCR text output file.", L"{\"out\":" + JsonString(outPath) + L"}", 1);
        }
    }

    std::wstring data = MergeObjectField(WithCanonicalField(OcrResultJson(result), canonicalCommand), L"foreground_preparation", ForegroundPreparationJson(prep));
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandReadRegionText(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"read-region-text";
    std::wstring title;
    int x = 0, y = 0, w = 0, h = 0;
    if (!ArgValue(argc, argv, L"--title", title) ||
        !ParseIntArg(argc, argv, L"--x", x) ||
        !ParseIntArg(argc, argv, L"--y", y) ||
        !ParseIntArg(argc, argv, L"--w", w) ||
        !ParseIntArg(argc, argv, L"--h", h)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"read-region-text requires --title, --x, --y, --w, and --h.", L"{}", 2);
    }
    if (w <= 0 || h <= 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--w and --h must be positive.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    OcrResult result = ReadRegionText(selected.hwnd, x, y, w, h);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"OCR_FAILED" : result.errorCode, result.errorMessage, L"{}", 1);
    }

    return EmitSuccess(command, startTick, MakeTraceTarget(selected), OcrResultJson(result));
}

int CommandReadScreenRegionText(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"read-screen-region-text";
    std::wstring title;
    int x = 0, y = 0, w = 0, h = 0;
    if (!ArgValue(argc, argv, L"--title", title) ||
        !ParseIntArg(argc, argv, L"--x", x) ||
        !ParseIntArg(argc, argv, L"--y", y) ||
        !ParseIntArg(argc, argv, L"--w", w) ||
        !ParseIntArg(argc, argv, L"--h", h)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"read-screen-region-text requires --title, --x, --y, --w, and --h.", L"{}", 2);
    }
    if (w <= 0 || h <= 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--w and --h must be positive.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }
    ForegroundPreparationResult prep = PrepareForegroundForVisibleUiTask(selected);
    if (!prep.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), prep.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : prep.errorCode, prep.errorMessage, L"{}", 1);
    }

    OcrResult result = ReadScreenRegionText(x, y, w, h);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode.empty() ? L"OCR_FAILED" : result.errorCode, result.errorMessage, L"{}", 1);
    }

    std::wstring data = MergeObjectField(OcrResultJson(result), L"foreground_preparation", ForegroundPreparationJson(prep));
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandWaitText(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"wait-text";
    std::wstring title;
    std::wstring text;
    int timeoutMs = 5000;
    int intervalMs = 300;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"wait-text requires --title and --text.", L"{}", 2);
    }
    if (text.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--text must not be empty.", L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--interval-ms", intervalMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    OcrTextResult result = WaitForText(selected.hwnd, text, timeoutMs, intervalMs);
    std::wstring data = OcrDataJson(text, result);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandAssertTextContains(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"assert-text-contains";
    std::wstring title;
    std::wstring text;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--text", text)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"assert-text-contains requires --title and --text.", L"{}", 2);
    }
    if (text.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--text must not be empty.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    OcrTextResult result = AssertTextContains(selected.hwnd, text);
    std::wstring data = OcrDataJson(text, result);
    if (!result.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

std::wstring ImageMatchDataJson(
    const ImageMatchResult& match,
    const std::wstring& templatePath,
    const std::wstring& screenshotPath) {
    std::wstringstream data;
    data << L"{\"match_found\":" << (match.matchFound ? L"true" : L"false")
         << L",\"x\":" << match.x
         << L",\"y\":" << match.y
         << L",\"width\":" << match.width
         << L",\"height\":" << match.height
         << L",\"score\":" << match.score
         << L",\"match_count\":" << match.matchCount
         << L",\"coordinate_space\":\"window_bitmap\""
         << L",\"template\":" << JsonString(templatePath)
         << L",\"screenshot_path\":" << JsonString(screenshotPath)
         << L"}";
    return data.str();
}

int CommandFindImage(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"find-image";
    std::wstring title;
    std::wstring templatePath;
    int tolerance = 0;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--template", templatePath)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"find-image requires --title and --template.", L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--tolerance", tolerance, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (tolerance < 0 || tolerance > 255) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--tolerance must be between 0 and 255.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }

    std::wstring screenshotPath = ArtifactsPath(L"find_image_source.bmp");
    ScreenshotResult shot = CaptureWindowToBmp(selected.hwnd, screenshotPath);
    if (!shot.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"SCREENSHOT_FAILED", shot.error, L"{\"screenshot_path\":" + JsonString(screenshotPath) + L"}", 1);
    }

    ImageMatchResult match = FindTemplateInBmp(screenshotPath, templatePath, tolerance);
    std::wstring data = ImageMatchDataJson(match, templatePath, screenshotPath);
    if (!match.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), match.errorCode, match.errorMessage, data, 1);
    }

    return EmitSuccess(command, startTick, MakeTraceTarget(selected), data);
}

int CommandClickImage(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"click-image";
    std::wstring title;
    std::wstring templatePath;
    std::wstring moveMode = L"human";
    std::wstring fallback;
    std::wstring profilePath;
    bool allowSyntheticProfile = false;
    int moveDurationMs = 0;
    int tolerance = 0;
    if (!ArgValue(argc, argv, L"--title", title) || !ArgValue(argc, argv, L"--template", templatePath)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"click-image requires --title and --template.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--move-mode", moveMode);
    ArgValue(argc, argv, L"--fallback", fallback);
    ArgValue(argc, argv, L"--profile", profilePath);
    allowSyntheticProfile = ArgExists(argc, argv, L"--allow-synthetic-profile");
    std::wstring fallbackError;
    if (!ValidateMoveFallback(fallback, fallbackError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", fallbackError, L"{}", 2);
    }
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--move-duration-ms", moveDurationMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--tolerance", tolerance, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    if (moveDurationMs < 0 || tolerance < 0 || tolerance > 255) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Invalid move duration or tolerance.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    std::wstring screenshotPath = ArtifactsPath(L"click_image_source.bmp");
    ScreenshotResult shot = CaptureWindowToBmp(selected.hwnd, screenshotPath);
    if (!shot.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"SCREENSHOT_FAILED", shot.error, L"{\"screenshot_path\":" + JsonString(screenshotPath) + L"}", 1);
    }

    ImageMatchResult match = FindTemplateInBmp(screenshotPath, templatePath, tolerance);
    std::wstring data = ImageMatchDataJson(match, templatePath, screenshotPath);
    if (!match.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), match.errorCode, match.errorMessage, data, 1);
    }

    int clientX = 0;
    int clientY = 0;
    if (!WindowBitmapPointToClient(selected.hwnd, match.x + (match.width / 2), match.y + (match.height / 2), clientX, clientY)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), L"IMAGE_MATCH_FAILED", L"Could not convert image match to client coordinates.", data, 1);
    }
    ClickResult click = ApplyClickFallback(selected.hwnd, clientX, clientY, moveMode, moveDurationMs, fallback,
                                           ClickClientPoint(selected.hwnd, clientX, clientY, moveMode, moveDurationMs, profilePath, allowSyntheticProfile));
    if (!click.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), click.errorCode.empty() ? L"UNKNOWN_ERROR" : click.errorCode, click.error, data, 1);
    }

    std::wstring successData = data.substr(0, data.size() - 1)
        + L",\"action_method\":\"mouse_center\""
        + L",\"target_client_x\":" + std::to_wstring(clientX)
        + L",\"target_client_y\":" + std::to_wstring(clientY)
        + L"," + ActionFocusFields(selected, title, click.foregroundBefore, click.foregroundAfter, click.focusVerified)
        + L"," + ClickMotionFields(click)
        + L"}";
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), successData);
}

int CommandRunCase(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"run-case";
    std::wstring file;
    std::wstring report;
    if (!ArgValue(argc, argv, L"--file", file) || !ArgValue(argc, argv, L"--report", report)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-case requires --file and --report.", L"{}", 2);
    }

    CaseRunResult result = RunCaseFile(file, report);
    std::wstringstream data;
    data << L"{\"case_file\":" << JsonString(file)
         << L",\"report\":" << JsonString(result.reportPath)
         << L",\"step_count\":" << result.stepCount
         << L",\"passed_step_count\":" << result.passedStepCount
         << L",\"failed_step_index\":" << result.failedStepIndex
         << L"}";
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"UNKNOWN_ERROR" : result.errorCode, result.error, data.str(), 1);
    }

    return EmitSuccess(command, startTick, NoTraceTarget(), data.str());
}

int CommandMotionRecord(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"motion-record";
    std::wstring title;
    std::wstring scenario;
    std::wstring outPath;
    int durationMs = 0;
    if (!ArgValue(argc, argv, L"--title", title) ||
        !ArgValue(argc, argv, L"--scenario", scenario) ||
        !ArgValue(argc, argv, L"--out", outPath) ||
        !ParseIntArg(argc, argv, L"--duration-ms", durationMs)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"motion-record requires --title, --scenario, --duration-ms, and --out.", L"{}", 2);
    }

    WindowInfo selected;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    if (!ResolveUniqueWindowByTitle(title, selected, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, NoTraceTarget(), errorCode, errorMessage, dataJson, 1);
    }
    if (!EnforceSafetyPolicy(selected, title, errorCode, errorMessage, dataJson)) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), errorCode, errorMessage, dataJson, 1);
    }

    MotionRecordResult recorded = RecordMouseMotion(selected, scenario, durationMs, outPath);
    if (!recorded.ok) {
        return EmitFailure(command, startTick, MakeTraceTarget(selected), recorded.errorCode.empty() ? L"UNKNOWN_ERROR" : recorded.errorCode, recorded.errorMessage, recorded.dataJson, 1);
    }
    return EmitSuccess(command, startTick, MakeTraceTarget(selected), recorded.dataJson);
}

int CommandMotionCalibrate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"motion-calibrate";
    std::wstring inputDir;
    std::wstring outPath;
    std::wstring source;
    if (!ArgValue(argc, argv, L"--input", inputDir) || !ArgValue(argc, argv, L"--out", outPath)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"motion-calibrate requires --input and --out.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--source", source);
    MotionProfileOperationResult calibrated = CalibrateOperatorMotionProfile(inputDir, outPath, source);
    if (!calibrated.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), calibrated.errorCode.empty() ? L"UNKNOWN_ERROR" : calibrated.errorCode, calibrated.errorMessage, calibrated.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), calibrated.dataJson);
}

int CommandMotionProfileInfo(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"motion-profile-info";
    std::wstring profilePath = DefaultOperatorMotionProfilePath();
    ArgValue(argc, argv, L"--profile", profilePath);
    MotionProfileOperationResult info = OperatorMotionProfileInfo(profilePath);
    if (!info.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), info.errorCode.empty() ? L"UNKNOWN_ERROR" : info.errorCode, info.errorMessage, info.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), info.dataJson);
}

int CommandMotionProfileValidate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"motion-profile-validate";
    std::wstring profilePath = DefaultOperatorMotionProfilePath();
    std::wstring outPath;
    ArgValue(argc, argv, L"--profile", profilePath);
    if (!ArgValue(argc, argv, L"--out", outPath)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"motion-profile-validate requires --out.", L"{}", 2);
    }
    MotionProfileOperationResult validated = ValidateOperatorMotionProfile(profilePath, outPath);
    if (!validated.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), validated.errorCode.empty() ? L"MOTION_PROFILE_INVALID" : validated.errorCode, validated.errorMessage, validated.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), validated.dataJson);
}

int CommandMotionProfileClear(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"motion-profile-clear";
    std::wstring profilePath = DefaultOperatorMotionProfilePath();
    ArgValue(argc, argv, L"--profile", profilePath);
    MotionProfileOperationResult cleared = ClearOperatorMotionProfile(profilePath);
    if (!cleared.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), cleared.errorCode.empty() ? L"UNKNOWN_ERROR" : cleared.errorCode, cleared.errorMessage, cleared.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), cleared.dataJson);
}

int CommandMotionPacerSelftest(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"motion-pacer-selftest";
    MotionPacerSelfTestOptions options;
    std::wstring parseError;
    ArgValue(argc, argv, L"--motion-profile", options.motionProfile);
    if (!ParseOptionalIntArg(argc, argv, L"--motion-hz", options.requestedHz, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--duration-ms", options.durationMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    MotionPacerSelfTestResult result = RunMotionPacerSelfTest(options);
    std::wstring data = MotionPacerSelfTestJson(result);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"BLOCKED_MOTION_165HZ_NOT_MET" : result.errorCode, result.errorMessage, data, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandTaskSessionValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"task-session-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-session-validate requires --file.", L"{}", 2);
    }

    TaskSessionValidationResult result = ValidateTaskSessionFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"TASK_SESSION_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandTaskSessionTransition(int argc, wchar_t** argv) {
    const std::wstring command = L"task-session-transition";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    std::wstring action;
    std::wstring fromStateText;
    std::wstring toStateText;
    std::wstring reason;
    int timeoutMs = 0;
    int elapsedMs = 0;

    if (!ArgValue(argc, argv, L"--file", file) || file.empty() ||
        !ArgValue(argc, argv, L"--action", action) || action.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-session-transition requires --file and --action.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--from-state", fromStateText);
    ArgValue(argc, argv, L"--to-state", toStateText);
    ArgValue(argc, argv, L"--reason", reason);
    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--elapsed-ms", elapsedMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    TaskSessionValidationResult loaded = ValidateTaskSessionFile(file);
    if (!loaded.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), loaded.errorCode.empty() ? L"TASK_SESSION_SCHEMA_INVALID" : loaded.errorCode, loaded.errorMessage, loaded.dataJson, 1);
    }

    TaskTransitionRequest request;
    request.action = action;
    request.fromState = ParseTaskSessionState(fromStateText.empty() ? loaded.session.currentStateText : fromStateText);
    request.toState = ParseTaskSessionState(toStateText);
    request.reason = reason;
    request.timeoutMs = timeoutMs;
    request.elapsedMs = elapsedMs;

    TaskTransitionResult transition = ApplyTaskTransition(loaded.session, request);
    if (!transition.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), transition.errorCode.empty() ? L"TASK_TRANSITION_INVALID" : transition.errorCode, transition.errorMessage, transition.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), transition.dataJson);
}

int CommandTaskSessionRun(int argc, wchar_t** argv) {
    const std::wstring command = L"task-session-run";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-session-run requires --file.", L"{}", 2);
    }

    TaskSessionRunResult result = RunMinimalTaskSessionFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"TASK_SESSION_RUN_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandTaskStatus(int argc, wchar_t** argv) {
    const std::wstring command = L"task-status";
    ULONGLONG startTick = GetTickCount64();
    std::wstring taskId;
    std::wstring file;
    ArgValue(argc, argv, L"--task-id", taskId);
    ArgValue(argc, argv, L"--file", file);
    if (taskId.empty() && file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-status requires --task-id or --file.", L"{}", 2);
    }
    return EmitTaskControlResult(command, startTick, GetStableTaskSessionStatus(taskId, file));
}

int CommandTaskEvents(int argc, wchar_t** argv) {
    const std::wstring command = L"task-events";
    ULONGLONG startTick = GetTickCount64();
    std::wstring taskId;
    std::wstring file;
    ArgValue(argc, argv, L"--task-id", taskId);
    ArgValue(argc, argv, L"--file", file);
    if (taskId.empty() && file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-events requires --task-id or --file.", L"{}", 2);
    }
    return EmitTaskControlResult(command, startTick, ReadStableTaskSessionEvents(taskId, file));
}

int CommandTaskReport(int argc, wchar_t** argv) {
    const std::wstring command = L"task-report";
    ULONGLONG startTick = GetTickCount64();
    std::wstring taskId;
    std::wstring file;
    ArgValue(argc, argv, L"--task-id", taskId);
    ArgValue(argc, argv, L"--file", file);
    if (taskId.empty() && file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-report requires --task-id or --file.", L"{}", 2);
    }
    return EmitTaskControlResult(command, startTick, ReadStableTaskSessionReport(taskId, file));
}

int CommandTaskConfirm(int argc, wchar_t** argv) {
    const std::wstring command = L"task-confirm";
    ULONGLONG startTick = GetTickCount64();
    std::wstring taskId;
    std::wstring file;
    std::wstring response;
    ArgValue(argc, argv, L"--task-id", taskId);
    ArgValue(argc, argv, L"--file", file);
    ArgValue(argc, argv, L"--response", response);
    if (taskId.empty() && file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-confirm requires --task-id or --file.", L"{}", 2);
    }
    return EmitTaskControlResult(command, startTick, ConfirmStableTaskSessionAction(taskId, file, response));
}

int CommandTaskCancel(int argc, wchar_t** argv) {
    const std::wstring command = L"task-cancel";
    ULONGLONG startTick = GetTickCount64();
    std::wstring taskId;
    std::wstring file;
    std::wstring reason;
    ArgValue(argc, argv, L"--task-id", taskId);
    ArgValue(argc, argv, L"--file", file);
    ArgValue(argc, argv, L"--reason", reason);
    if (taskId.empty() && file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-cancel requires --task-id or --file.", L"{}", 2);
    }
    return EmitTaskControlResult(command, startTick, CancelStableTaskSession(taskId, file, reason));
}

int CommandTaskTemplateV2Validate(int argc, wchar_t** argv) {
    const std::wstring command = L"task-template-v2-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-template-v2-validate requires --file.", L"{}", 2);
    }

    TaskTemplateV2OperationResult result = ValidateTaskTemplateV2File(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"TASK_TEMPLATE_V2_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandTaskTemplateV2Resolve(int argc, wchar_t** argv) {
    const std::wstring command = L"task-template-v2-resolve";
    ULONGLONG startTick = GetTickCount64();
    std::wstring task;
    std::wstring templ;
    std::wstring profile;
    std::wstring paramsFile;
    ArgValue(argc, argv, L"--task", task);
    ArgValue(argc, argv, L"--template", templ);
    ArgValue(argc, argv, L"--profile", profile);
    ArgValue(argc, argv, L"--params-file", paramsFile);
    if (task.empty() && templ.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"task-template-v2-resolve requires --task or --template.", L"{}", 2);
    }

    TaskTemplateV2OperationResult result = ResolveTaskTemplateV2(templ, profile, paramsFile, task);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"TASK_TEMPLATE_V2_RESOLVE_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandFilePathResolve(int argc, wchar_t** argv) {
    const std::wstring command = L"file-path-resolve";
    ULONGLONG startTick = GetTickCount64();
    std::wstring path;
    std::wstring allowedRoots;
    std::wstring extensions;
    int maxBytes = 0;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--path", path) || path.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"file-path-resolve requires --path.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--allowed-roots", allowedRoots);
    ArgValue(argc, argv, L"--extensions", extensions);
    if (!ParseOptionalIntArg(argc, argv, L"--max-bytes", maxBytes, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }

    FileWorkflowResult result = ResolveFilePathForWorkflow(path, allowedRoots, extensions, maxBytes);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FILE_PATH_RESOLVE_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandFilePickerFlow(int argc, wchar_t** argv) {
    const std::wstring command = L"file-picker-flow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"file-picker-flow requires --file.", L"{}", 2);
    }
    FileWorkflowResult result = RunFilePickerFlowFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"FILE_PICKER_FLOW_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandAttachmentVerify(int argc, wchar_t** argv) {
    const std::wstring command = L"attachment-verify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    std::wstring expectedFile;
    int timeoutMs = 0;
    int elapsedMs = 0;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"attachment-verify requires --file.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--expected-file", expectedFile);
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--elapsed-ms", elapsedMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    FileWorkflowResult result = VerifyAttachmentStateFile(file, expectedFile, timeoutMs, elapsedMs);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"UPLOAD_VERIFICATION_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandCrossWindowCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"cross-window-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"cross-window-check requires --file.", L"{}", 2);
    }
    FileWorkflowResult result = CheckCrossWindowContextFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"CROSS_WINDOW_CHECK_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandLocalMailAttachFlow(int argc, wchar_t** argv) {
    const std::wstring command = L"local-mail-attach-flow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"local-mail-attach-flow requires --file.", L"{}", 2);
    }
    FileWorkflowResult result = RunLocalMailAttachFlowFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"LOCAL_MAIL_ATTACH_FLOW_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandStepContractValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"step-contract-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    if (ArgValue(argc, argv, L"--input", input) && !input.empty()) {
        return CommandStepContractValidateV63(argc, argv);
    }
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-contract-validate requires --file.", L"{}", 2);
    }

    StepContractValidationResult result = ValidateStepContractFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"STEP_CONTRACT_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandStepPreconditionCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"step-precondition-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring contractPath;
    std::wstring perceptionPath;
    if (!ArgValue(argc, argv, L"--contract", contractPath) || contractPath.empty() ||
        !ArgValue(argc, argv, L"--perception", perceptionPath) || perceptionPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-precondition-check requires --contract and --perception.", L"{}", 2);
    }
    PreconditionCheckResult result = CheckStepPreconditions(contractPath, perceptionPath);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"PRECONDITION_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandStepVerify(int argc, wchar_t** argv) {
    const std::wstring command = L"step-verify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring contractPath;
    std::wstring beforePath;
    std::wstring afterPath;
    int timeoutMs = 0;
    int elapsedMs = 0;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--contract", contractPath) || contractPath.empty() ||
        !ArgValue(argc, argv, L"--before", beforePath) || beforePath.empty() ||
        !ArgValue(argc, argv, L"--after", afterPath) || afterPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-verify requires --contract, --before, and --after.", L"{}", 2);
    }
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--elapsed-ms", elapsedMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    StepVerificationResult result = VerifyStepAfterAction(contractPath, beforePath, afterPath, timeoutMs, elapsedMs);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"VERIFICATION_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandStepFailureClassify(int argc, wchar_t** argv) {
    const std::wstring command = L"step-failure-classify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring errorCode;
    std::wstring stepId;
    if (!ArgValue(argc, argv, L"--error-code", errorCode) || errorCode.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-failure-classify requires --error-code.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--step-id", stepId);
    FailureReasonRecord record = ClassifyStepFailureReason(stepId, errorCode);
    return EmitSuccess(command, startTick, NoTraceTarget(), record.dataJson);
}

int CommandRecoveryPolicyValidate(int argc, wchar_t** argv) {
    const std::wstring command = L"recovery-policy-validate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"recovery-policy-validate requires --file.", L"{}", 2);
    }

    RecoveryPolicyValidationResult result = ValidateRecoveryPolicyFile(file);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"RECOVERY_POLICY_SCHEMA_INVALID" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandRecoveryEvaluate(int argc, wchar_t** argv) {
    const std::wstring command = L"recovery-evaluate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring policyPath;
    std::wstring failureReason;
    std::wstring contextPath;
    int attempt = 1;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--policy", policyPath) || policyPath.empty() ||
        !ArgValue(argc, argv, L"--failure-reason", failureReason) || failureReason.empty() ||
        !ArgValue(argc, argv, L"--context", contextPath) || contextPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"recovery-evaluate requires --policy, --failure-reason, and --context.", L"{}", 2);
    }
    if (!ParseOptionalIntArg(argc, argv, L"--attempt", attempt, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    RecoveryAttemptEvaluationResult result = EvaluateRecoveryAttempt(policyPath, failureReason, contextPath, attempt);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"RECOVERY_EVALUATE_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandSafeContextRecovery(int argc, wchar_t** argv) {
    const std::wstring command = L"safe-context-recovery";
    ULONGLONG startTick = GetTickCount64();
    std::wstring resultJsonPath;
    std::wstring evidenceJsonlPath;
    ArgValue(argc, argv, L"--result-json", resultJsonPath);
    ArgValue(argc, argv, L"--evidence-jsonl", evidenceJsonlPath);

    RecoveryRequest request;
    std::wstring parseError;
    if (!ParseRecoveryPolicyFromArgs(argc, argv, request, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    RecoveryResult result = EvaluateSafeContextRecovery(request);
    std::wstring data = L"{\"recovery_policy\":" + RecoveryPolicyJson(request.policy)
        + L",\"recovery_result\":" + RecoveryResultJson(result)
        + L"}";
    std::wstring envelope = result.recoverySuccess
        ? CommandSuccessJson(command, startTick, NoTraceTarget(), data)
        : CommandFailureJson(
            command,
            startTick,
            NoTraceTarget(),
            result.recoveryStopCode.empty() ? L"RECOVERY_FAILED" : result.recoveryStopCode,
            result.recoveryReason,
            data);
    if (!resultJsonPath.empty()) {
        WriteSmallTextFile(resultJsonPath, envelope);
    }
    if (!evidenceJsonlPath.empty()) {
        FILE* file = nullptr;
        if (_wfopen_s(&file, evidenceJsonlPath.c_str(), L"a, ccs=UTF-8") == 0 && file) {
            fwprintf(file, L"%ls\n", envelope.c_str());
            fclose(file);
        }
    }
    if (!result.recoverySuccess) {
        return EmitFailure(
            command,
            startTick,
            NoTraceTarget(),
            result.recoveryStopCode.empty() ? L"RECOVERY_FAILED" : result.recoveryStopCode,
            result.recoveryReason,
            data,
            1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandTaskCheckpointEvaluate(int argc, wchar_t** argv) {
    const std::wstring command = L"task-checkpoint-evaluate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring resultJsonPath;
    ArgValue(argc, argv, L"--result-json", resultJsonPath);

    TaskCheckpointRecord checkpoint;
    ArgValue(argc, argv, L"--task-id", checkpoint.taskId);
    ArgValue(argc, argv, L"--case-id", checkpoint.caseId);
    ArgValue(argc, argv, L"--step-name", checkpoint.stepName);
    ArgValue(argc, argv, L"--verified-context", checkpoint.verifiedContext);
    checkpoint.verifiedMarkers = ArgValues(argc, argv, L"--verified-marker");
    ArgValue(argc, argv, L"--verified-window-title", checkpoint.verifiedWindowTitle);
    ArgValue(argc, argv, L"--verified-process", checkpoint.verifiedProcess);
    ArgValue(argc, argv, L"--input-state-hash", checkpoint.inputStateHash);
    ArgValue(argc, argv, L"--page-state-hash", checkpoint.pageStateHash);
    ArgValue(argc, argv, L"--checkpoint-created-at", checkpoint.checkpointCreatedAt);
    if (checkpoint.checkpointCreatedAt.empty()) checkpoint.checkpointCreatedAt = NowTimestamp();

    ResumeDecisionInput input;
    input.checkpoint = checkpoint;
    ArgValue(argc, argv, L"--current-context", input.currentContext);
    ArgValue(argc, argv, L"--current-window-title", input.currentWindowTitle);
    ArgValue(argc, argv, L"--current-process", input.currentProcess);
    ArgValue(argc, argv, L"--current-input-state-hash", input.currentInputStateHash);
    ArgValue(argc, argv, L"--current-page-state-hash", input.currentPageStateHash);
    ArgValue(argc, argv, L"--state-loss-risk", input.stateLossRisk);

    std::wstring parseError;
    if (!ParseOptionalIntArg(argc, argv, L"--step-index", checkpoint.stepIndex, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--resume-from-step", checkpoint.resumeFromStep, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--replay-from-step", checkpoint.replayFromStep, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--safe-to-resume", checkpoint.safeToResume, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--recovery-just-executed", input.recoveryJustExecuted, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--reobserve-performed", input.reobservePerformed, parseError) ||
        !ParseOptionalBoolArg(argc, argv, L"--expected-context-reverified", input.expectedContextReverified, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    input.checkpoint = checkpoint;
    ResumeDecision decision = EvaluateResumeDecision(input);
    std::wstring data = L"{\"task_checkpoint\":" + TaskCheckpointJson(checkpoint)
        + L",\"resume_decision\":" + ResumeDecisionJson(decision)
        + L"}";
    std::wstring envelope = CommandSuccessJson(command, startTick, NoTraceTarget(), data);
    if (!resultJsonPath.empty()) WriteSmallTextFile(resultJsonPath, envelope);
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandFailureAttributionClassify(int argc, wchar_t** argv) {
    const std::wstring command = L"failure-attribution-classify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring resultJsonPath;
    std::wstring contextFile;
    FailureAttributionInput input;
    ArgValue(argc, argv, L"--error-code", input.errorCode);
    ArgValue(argc, argv, L"--stop-code", input.stopCode);
    ArgValue(argc, argv, L"--failure-reason", input.failureReason);
    ArgValue(argc, argv, L"--context-text", input.contextText);
    ArgValue(argc, argv, L"--target-type", input.targetType);
    ArgValue(argc, argv, L"--result-json", resultJsonPath);
    if (ArgValue(argc, argv, L"--context-file", contextFile)) {
        if (GetFileAttributesW(contextFile.c_str()) == INVALID_FILE_ATTRIBUTES) {
            return EmitFailure(command, startTick, NoTraceTarget(), L"FILE_NOT_FOUND", L"--context-file was not found.", L"{\"context_file\":" + JsonString(contextFile) + L"}", 2);
        }
        input.contextText += L"\n" + ReadSmallTextFile(contextFile);
    }
    FailureAttributionResult result = ClassifyFailureAttribution(input);
    std::wstring data = FailureAttributionResultJson(result);
    std::wstring envelope = CommandSuccessJson(command, startTick, NoTraceTarget(), data);
    if (!resultJsonPath.empty()) WriteSmallTextFile(resultJsonPath, envelope);
    return EmitSuccess(command, startTick, NoTraceTarget(), data);
}

int CommandEscalationRequestCreate(int argc, wchar_t** argv) {
    const std::wstring command = L"escalation-request-create";
    ULONGLONG startTick = GetTickCount64();
    std::wstring reason;
    std::wstring task;
    std::wstring step;
    std::wstring contextPath;
    if (!ArgValue(argc, argv, L"--reason", reason) || reason.empty() ||
        !ArgValue(argc, argv, L"--task", task) || task.empty() ||
        !ArgValue(argc, argv, L"--step", step) || step.empty() ||
        !ArgValue(argc, argv, L"--context", contextPath) || contextPath.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"escalation-request-create requires --reason, --task, --step, and --context.", L"{}", 2);
    }
    EscalationRequestResult result = CreateEscalationRequest(reason, task, step, contextPath);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"ESCALATION_REQUEST_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandSafeStopCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"safe-stop-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring reason;
    std::wstring contextPath;
    if (!ArgValue(argc, argv, L"--reason", reason) || reason.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"safe-stop-check requires --reason.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--context", contextPath);
    SafeStopCheckResult result = CheckSafeStop(reason, contextPath);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"SAFE_STOP_CHECK_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandRiskActionClassify(int argc, wchar_t** argv) {
    const std::wstring command = L"risk-action-classify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring action;
    std::wstring permissionProfile;
    if (!ArgValue(argc, argv, L"--action", action) || action.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"risk-action-classify requires --action.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--permission-profile", permissionProfile);
    RiskActionClassification result = ClassifyRiskAction(action, permissionProfile);
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandConfirmationRequestCreate(int argc, wchar_t** argv) {
    const std::wstring command = L"confirmation-request-create";
    ULONGLONG startTick = GetTickCount64();
    std::wstring action;
    std::wstring riskLevel;
    std::wstring summary;
    std::wstring targetWindow;
    std::wstring screenshot;
    std::wstring involvedFiles;
    std::wstring destination;
    std::wstring allowedResponses;
    int timeoutMs = 0;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--action", action) || action.empty() ||
        !ArgValue(argc, argv, L"--risk-level", riskLevel) || riskLevel.empty() ||
        !ArgValue(argc, argv, L"--summary", summary) || summary.empty() ||
        !ArgValue(argc, argv, L"--target-window", targetWindow) || targetWindow.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"confirmation-request-create requires --action, --risk-level, --summary, and --target-window.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--screenshot", screenshot);
    ArgValue(argc, argv, L"--files", involvedFiles);
    ArgValue(argc, argv, L"--destination", destination);
    ArgValue(argc, argv, L"--allowed-responses", allowedResponses);
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError) || timeoutMs <= 0) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError.empty() ? L"confirmation-request-create requires positive --timeout-ms." : parseError, L"{}", 2);
    }
    ConfirmationRequestCreateResult result = CreateConfirmationRequest(action, riskLevel, summary, targetWindow, screenshot, involvedFiles, destination, timeoutMs, allowedResponses);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"CONFIRMATION_REQUEST_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandConfirmationGateCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"confirmation-gate-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring action;
    std::wstring riskLevel;
    std::wstring permissionProfile;
    std::wstring response;
    int timeoutMs = 30000;
    int elapsedMs = 0;
    std::wstring parseError;
    if (!ArgValue(argc, argv, L"--action", action) || action.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"confirmation-gate-check requires --action.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--risk-level", riskLevel);
    ArgValue(argc, argv, L"--permission-profile", permissionProfile);
    ArgValue(argc, argv, L"--response", response);
    if (!ParseOptionalIntArg(argc, argv, L"--timeout-ms", timeoutMs, parseError) ||
        !ParseOptionalIntArg(argc, argv, L"--elapsed-ms", elapsedMs, parseError)) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", parseError, L"{}", 2);
    }
    ConfirmationGateResult result = CheckConfirmationGate(action, riskLevel, permissionProfile, response, timeoutMs, elapsedMs);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"CONFIRMATION_GATE_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

int CommandConfirmationFlowRun(int argc, wchar_t** argv) {
    const std::wstring command = L"confirmation-flow-run";
    ULONGLONG startTick = GetTickCount64();
    std::wstring file;
    std::wstring response;
    if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
        return EmitFailure(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"confirmation-flow-run requires --file.", L"{}", 2);
    }
    ArgValue(argc, argv, L"--response", response);
    ConfirmationFlowRunResult result = RunLocalConfirmationFlow(file, response);
    if (!result.ok) {
        return EmitFailure(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"CONFIRMATION_FLOW_FAILED" : result.errorCode, result.errorMessage, result.dataJson, 1);
    }
    return EmitSuccess(command, startTick, NoTraceTarget(), result.dataJson);
}

void PrintUsage() {
    std::wcout << L"Usage: winagent.exe windows|version|safety-report|permission-status|unlock-full-access|lock-full-access|policy-check|consent-check|launch-app|browser-nav|browser-surface-normalize|browser-open-url-human|compile-browser-workflow|run-browser-workflow|verify-browser-workflow|compile-communication-workflow|run-communication-workflow|verify-communication-workflow|form-control|decision-eval|coding-eval|agent-boundary-validate|agent-intent-parse|agent-plan-draft|agent-planner-validate|plan-compile|step-contract-dry-run|plan-compile-selftest|validation-fingerprint|validation-consistency-check|regression-skip-evaluate|evidence-consolidate|session-lifecycle-audit|workflow-boundary-check|system-stabilization-check|run-agent-task|execute-step-contract|execute-compiled-plan|step-execution-verify|vlm-capability-probe|vlm-assist-locate|vlm-candidate-validate|vlm-frame-transport-check|vlm-observation-build-request|vlm-observation-run-mock|vlm-observation-validate|vlm-observation-dry-run|vlm-observation-selftest|vlm-assisted-locate|vlm-assisted-locate-dry-run|vlm-assisted-locate-and-click-local-safe|find|global-screenshot|capture-fullscreen-frame|evidence-flush|frame-evidence-flush|screenshot|target-lock-acquire|target-lock-release|coordinate-map|foreground-preempt|visible-text-input|visible-action-batch|visible-ui-verify|visible-operation-policy-check|taskbar-icon-locate|taskbar-icon-click|desktop-icon-locate|desktop-icon-double-click|start-menu-visible-launch|visible-app-launch|visible-show-desktop|visible-window-switch|visible-page-navigation|vlm-runtime-candidate|pycharm-visible-demo|operation-timeline-profiler-selftest|motion-pacer-selftest|observe|observe2|observe-loop|dynamic-ui-recovery|adaptive-locate|adaptive-click|adaptive-double-click|adaptive-type|adaptive-run-step|adaptive-scroll|scroll-and-locate|profile-report|target-semantics-guard-check|classify-execution-output|step-completion-evaluate|runtime-session-start|runtime-session-status|runtime-session-close|runtime-session-list|runtime-session-observe|runtime-session-locate|runtime-session-command|runtime-session-dispatch|runtime-session-act-and-verify|runtime-session-type-and-verify|runtime-session-scroll-and-locate|locate|act|click|double-click|right-click|scroll|drag|press|hotkey|type|desktop-move|desktop-click|desktop-double-click|desktop-right-click|desktop-press|desktop-hotkey|desktop-type|clipboard-set|clipboard-paste|focus|focus-window|activate-window|bring-window-front|minimize-window|restore-window|prepare-foreground|active-window|mouse-position|mouse_position|read-file|uia-tree|uia-find|uia-click|uia-type|find-text|click-text|find-image|click-image|read-window-text|read_window_text|read-region-text|read-screen-region-text|ocr-fullscreen-frame|ocr-foreground-from-frame|ocr-window-from-frame|ocr-cache-status|ocr-cache-clear|wait-text|assert-text-contains|pycharm-dev-demo|motion-record|motion-calibrate|motion-profile-info|motion-profile-validate|motion-profile-clear|task-session-validate|task-session-transition|task-session-run|task-status|task-report|task-events|task-cancel|task-confirm|task-template-v2-validate|task-template-v2-resolve|file-path-resolve|file-picker-flow|attachment-verify|cross-window-check|local-mail-attach-flow|step-contract-validate|step-precondition-check|step-verify|step-failure-classify|recovery-policy-validate|recovery-evaluate|safe-context-recovery|task-checkpoint-evaluate|failure-attribution-classify|escalation-request-create|safe-stop-check|risk-action-classify|confirmation-request-create|confirmation-gate-check|confirmation-flow-run|run-case|serve|run-task\n";
    std::wcout << L"Aliases: mouse_position -> mouse-position; read_window_text -> read-window-text; focus-window -> activate-window; right-click -> desktop-right-click alias for visible desktop coordinates; double-click -> desktop-double-click alias guidance; screenshot --out <file> defaults to global-screenshot; screenshot --title <title> is diagnostic window_only and cannot be final PASS evidence; observe --out <file> defaults to active foreground window; uia-tree --process <process> resolves the process main window.\n";
    std::wcout << L"Latency profiles: --latency-profile conservative|normal|fast-visible-ui.\n";
}

}  // namespace

// ===================================================================
// Named Pipe Service Mode
// ===================================================================

namespace {

struct ServiceSession {
    std::wstring sessionId;
    std::wstring startTime;
    std::wstring lastTargetTitle;
    std::wstring lastObserveSummary;
    int requestCount = 0;
    int actionCount = 0;
    int errorCount = 0;
};

ServiceSession g_session;
bool g_shutdownRequested = false;

std::wstring GenerateSessionId() {
    ULONGLONG tick = GetTickCount64();
    DWORD pid = GetCurrentProcessId();
    wchar_t buf[64] = {};
    swprintf_s(buf, L"dv-sess-%08x-%08llx", pid, tick);
    return buf;
}

std::wstring SimpleJsonGetString(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) { ++pos; }
        value += json[pos];
        ++pos;
    }
    return value;
}

std::wstring SimpleJsonGetRaw(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && iswspace(json[pos])) { ++pos; }
    if (pos >= json.size()) return L"";
    if (json[pos] == L'"') {
        ++pos;
        std::wstring value;
        while (pos < json.size() && json[pos] != L'"') {
            if (json[pos] == L'\\' && pos + 1 < json.size()) { ++pos; }
            value += json[pos]; ++pos;
        }
        return value;
    }
    if (json[pos] == L'{' || json[pos] == L'[') {
        int depth = 1; size_t start = pos; ++pos;
        while (pos < json.size() && depth > 0) {
            if (json[pos] == L'{' || json[pos] == L'[') ++depth;
            else if (json[pos] == L'}' || json[pos] == L']') --depth;
            ++pos;
        }
        return json.substr(start, pos - start);
    }
    // bool/number
    size_t end = pos;
    while (end < json.size() && !iswspace(json[end]) && json[end] != L',' && json[end] != L'}') { ++end; }
    return json.substr(pos, end - pos);
}

const wchar_t* kServiceProtocolVersion = L"1.0";

std::wstring TrimServiceJson(std::wstring value) {
    while (!value.empty() && (value.back() == L'\r' || value.back() == L'\n' || iswspace(value.back()))) {
        value.pop_back();
    }
    size_t start = 0;
    while (start < value.size() && iswspace(value[start])) {
        ++start;
    }
    return start == 0 ? value : value.substr(start);
}

std::wstring ServiceArtifactsJson(const std::vector<std::wstring>& artifacts) {
    std::wstringstream ss;
    ss << L"[";
    for (size_t i = 0; i < artifacts.size(); ++i) {
        if (i != 0) ss << L",";
        ss << JsonString(artifacts[i]);
    }
    ss << L"]";
    return ss.str();
}

std::wstring ServiceEnvelope(
    bool ok,
    const std::wstring& errorCode,
    const std::wstring& message,
    const std::wstring& dataJson,
    const std::vector<std::wstring>& artifacts,
    const std::wstring& reportPath,
    long long durationMs) {
    std::wstring normalizedData = dataJson.empty() ? L"{}" : dataJson;
    std::wstring normalizedMessage = message.empty() ? (ok ? L"OK" : L"Request failed.") : message;
    std::wstring normalizedError = ok ? L"" : (errorCode.empty() ? L"UNKNOWN_ERROR" : errorCode);
    if (!ok && IsUserAbortStopCode(normalizedError)) {
        normalizedData = MergeUserAbortEvidenceJson(normalizedData);
        if (message.empty()) {
            normalizedMessage = UserAbortMessage();
        }
    }

    std::wstringstream ss;
    ss << L"{\"ok\":" << (ok ? L"true" : L"false")
       << L",\"error_code\":" << JsonString(normalizedError)
       << L",\"message\":" << JsonString(normalizedMessage)
       << L",\"data\":" << normalizedData
       << L",\"artifacts\":" << ServiceArtifactsJson(artifacts)
       << L",\"report_path\":" << JsonString(reportPath)
       << L",\"duration_ms\":" << durationMs
       << L",\"service_protocol_version\":" << JsonString(kServiceProtocolVersion);
    if (!ok) {
        ss << L",\"error\":{\"code\":" << JsonString(normalizedError)
           << L",\"message\":" << JsonString(normalizedMessage) << L"}";
    }
    ss << L"}";
    return ss.str();
}

std::wstring ServiceEnvelopeFromCli(
    const std::wstring& cliJson,
    long long durationMs,
    const std::vector<std::wstring>& artifacts = {},
    const std::wstring& reportPath = L"") {
    std::wstring trimmed = TrimServiceJson(cliJson);
    bool ok = trimmed.find(L"\"ok\":true") != std::wstring::npos;
    std::wstring errorCode;
    if (!ok) {
        errorCode = SimpleJsonGetString(trimmed, L"code");
        if (errorCode.empty()) errorCode = SimpleJsonGetString(trimmed, L"error_code");
        if (errorCode.empty()) errorCode = L"UNKNOWN_ERROR";
    }
    std::wstring message = SimpleJsonGetString(trimmed, L"message");
    std::wstring dataJson = SimpleJsonGetRaw(trimmed, L"data");
    if (dataJson.empty()) dataJson = L"{}";
    return ServiceEnvelope(ok, errorCode, message, dataJson, artifacts, reportPath, durationMs);
}

void AppendServiceAudit(const std::wstring& endpoint, const std::wstring& title, const std::wstring& permissionMode, bool ok, const std::wstring& errorCode, long long durationMs) {
    FILE* file = nullptr;
    EnsureDirectoryPath(ArtifactsPath());
    std::wstring auditPath = ArtifactsPath(L"service_audit.log");
    if (_wfopen_s(&file, auditPath.c_str(), L"a, ccs=UTF-8") != 0 || !file) return;
    fwprintf(file, L"timestamp=\"%ls\" session_id=\"%ls\" endpoint=\"%ls\" title=\"%ls\" permission_mode=\"%ls\" service_protocol_version=\"%ls\" ok=\"%ls\" error_code=\"%ls\" duration_ms=%lld\n",
        NowTimestamp().c_str(), g_session.sessionId.c_str(), endpoint.c_str(),
        title.c_str(), permissionMode.empty() ? DefaultPermissionModeName().c_str() : permissionMode.c_str(), kServiceProtocolVersion,
        ok ? L"true" : L"false", errorCode.c_str(), durationMs);
    fclose(file);
}

std::wstring ServiceHandleRequest(const std::wstring& requestJson, std::wstring& response) {
    ULONGLONG startTick = GetTickCount64();
    ResetUserAbortForCurrentTask();
    g_session.requestCount++;

    std::wstring endpoint = SimpleJsonGetString(requestJson, L"endpoint");
    std::wstring body = SimpleJsonGetRaw(requestJson, L"body");
    std::wstring token = SimpleJsonGetString(requestJson, L"token");

    // Extract common fields from body
    std::wstring title = SimpleJsonGetString(body, L"title");
    std::wstring selector = SimpleJsonGetString(body, L"selector");
    std::wstring action = SimpleJsonGetString(body, L"action");
    std::wstring text = SimpleJsonGetString(body, L"text");
    std::wstring file = SimpleJsonGetString(body, L"file");
    std::wstring report = SimpleJsonGetString(body, L"report");
    std::wstring path = SimpleJsonGetString(body, L"path");
    std::wstring taskId = SimpleJsonGetString(body, L"task_id");
    std::wstring profile = SimpleJsonGetString(body, L"profile");
    std::wstring profileLocator = SimpleJsonGetString(body, L"profile_locator");
    std::wstring process = SimpleJsonGetString(body, L"process");
    std::wstring responseText = SimpleJsonGetString(body, L"response");
    std::wstring reason = SimpleJsonGetString(body, L"reason");
    std::wstring screenshot = SimpleJsonGetString(body, L"screenshot");
    std::wstring uia = SimpleJsonGetString(body, L"uia");
    std::wstring permissionMode = SimpleJsonGetString(body, L"permission_mode");
    std::wstring fullAccessSessionId = SimpleJsonGetString(body, L"full_access_session_id");
    if (permissionMode.empty()) permissionMode = DefaultPermissionModeName();

    if (!title.empty()) g_session.lastTargetTitle = title;

    if (endpoint == L"/shutdown") {
        g_shutdownRequested = true;
        response = ServiceEnvelope(true, L"", L"shutting down", L"{\"status\":\"shutting_down\"}", {}, L"", ElapsedMs(startTick));
        AppendServiceAudit(endpoint, L"", permissionMode, true, L"", ElapsedMs(startTick));
        return L"";
    }

    // Build fake command-line args to reuse existing command functions
    std::vector<std::wstring> fakeArgs;
    std::vector<wchar_t*> fakeArgv;
    fakeArgs.push_back(L"winagent.exe");

    if (endpoint == L"/health-check" || endpoint == L"/health") {
        std::wstringstream data;
        data << L"{\"status\":\"ok\""
             << L",\"service_protocol_version\":" << JsonString(kServiceProtocolVersion)
             << L",\"session_id\":" << JsonString(g_session.sessionId)
             << L",\"start_time\":" << JsonString(g_session.startTime)
             << L",\"request_count\":" << g_session.requestCount
             << L",\"action_count\":" << g_session.actionCount
             << L",\"error_count\":" << g_session.errorCount
             << L"}";
        response = ServiceEnvelope(true, L"", L"OK", data.str(), {}, L"", ElapsedMs(startTick));
        AppendServiceAudit(endpoint, L"", permissionMode, true, L"", ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/capabilities") {
        std::wstringstream data;
        data << L"{\"service_protocol_version\":" << JsonString(kServiceProtocolVersion)
             << L",\"available\":["
             << L"\"task_service_protocol\","
             << L"\"run_task\","
             << L"\"get_task_status\","
             << L"\"get_task_events\","
             << L"\"confirm_task_action\","
             << L"\"cancel_task\","
             << L"\"read_task_report\","
             << L"\"adaptive_humanmode_loop\","
             << L"\"adaptive_run_step\","
             << L"\"adaptive_double_click\","
             << L"\"adaptive_browser_form_locator\","
             << L"\"real_ui_adaptive_cases_v5_10_1\""
             << L"],\"safety_bypass\":false}";
        response = ServiceEnvelope(true, L"", L"OK", data.str(), {}, L"", ElapsedMs(startTick));
        AppendServiceAudit(endpoint, L"", permissionMode, true, L"", ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/version") {
        fakeArgs.push_back(L"version");
    } else if (endpoint == L"/safety-report") {
        fakeArgs.push_back(L"safety-report");
    } else if (endpoint == L"/profile-report") {
        fakeArgs.push_back(L"profile-report");
        if (!path.empty()) { fakeArgs.push_back(L"--path"); fakeArgs.push_back(path); }
    } else if (endpoint == L"/policy-check") {
        fakeArgs.push_back(L"policy-check");
        fakeArgs.push_back(L"--title"); fakeArgs.push_back(title);
        fakeArgs.push_back(L"--process"); fakeArgs.push_back(process);
        fakeArgs.push_back(L"--action"); fakeArgs.push_back(action);
        if (!path.empty()) { fakeArgs.push_back(L"--path"); fakeArgs.push_back(path); }
        fakeArgs.push_back(L"--permission-mode"); fakeArgs.push_back(permissionMode);
        if (!fullAccessSessionId.empty()) { fakeArgs.push_back(L"--full-access-session-id"); fakeArgs.push_back(fullAccessSessionId); }
    } else if (endpoint == L"/consent-check") {
        fakeArgs.push_back(L"consent-check");
        fakeArgs.push_back(L"--title"); fakeArgs.push_back(title);
    } else if (endpoint == L"/observe") {
        fakeArgs.push_back(L"observe");
        fakeArgs.push_back(L"--title"); fakeArgs.push_back(title);
        if (!screenshot.empty()) { fakeArgs.push_back(L"--screenshot"); fakeArgs.push_back(screenshot); }
        if (!uia.empty()) { fakeArgs.push_back(L"--uia"); fakeArgs.push_back(uia); }
    } else if (endpoint == L"/locate") {
        fakeArgs.push_back(L"locate");
        fakeArgs.push_back(L"--title"); fakeArgs.push_back(title);
        if (!selector.empty()) {
            fakeArgs.push_back(L"--selector"); fakeArgs.push_back(selector);
        }
        if (!profile.empty()) { fakeArgs.push_back(L"--profile"); fakeArgs.push_back(profile); }
        if (!profileLocator.empty()) { fakeArgs.push_back(L"--profile-locator"); fakeArgs.push_back(profileLocator); }
    } else if (endpoint == L"/act") {
        fakeArgs.push_back(L"act");
        fakeArgs.push_back(L"--title"); fakeArgs.push_back(title);
        fakeArgs.push_back(L"--selector"); fakeArgs.push_back(selector);
        fakeArgs.push_back(L"--action"); fakeArgs.push_back(action);
        if (!text.empty()) { fakeArgs.push_back(L"--text"); fakeArgs.push_back(text); }
        g_session.actionCount++;
    } else if (endpoint == L"/run-case") {
        fakeArgs.push_back(L"run-case");
        fakeArgs.push_back(L"--file"); fakeArgs.push_back(file);
        fakeArgs.push_back(L"--report"); fakeArgs.push_back(report);
    } else if (endpoint == L"/run_task") {
        if (file.empty()) {
            response = ServiceEnvelope(false, L"INVALID_ARGUMENT", L"/run_task requires file.", L"{}", {}, L"", ElapsedMs(startTick));
            AppendServiceAudit(endpoint, L"", permissionMode, false, L"INVALID_ARGUMENT", ElapsedMs(startTick));
            return L"";
        }
        TaskSessionRunResult sessionRun = RunStableTaskSessionFile(file);
        response = ServiceEnvelope(
            sessionRun.ok,
            sessionRun.ok ? L"" : (sessionRun.errorCode.empty() ? L"TASK_SESSION_RUN_FAILED" : sessionRun.errorCode),
            sessionRun.ok ? L"OK" : sessionRun.errorMessage,
            sessionRun.dataJson.empty() ? L"{}" : sessionRun.dataJson,
            sessionRun.reportPath.empty() ? std::vector<std::wstring>{} : std::vector<std::wstring>{sessionRun.progressPath, sessionRun.eventsPath, sessionRun.reportPath},
            sessionRun.reportPath,
            ElapsedMs(startTick));
        AppendServiceAudit(endpoint, L"", permissionMode, sessionRun.ok, sessionRun.errorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/get_task_status") {
        TaskSessionControlResult status = GetStableTaskSessionStatus(taskId, file);
        response = ServiceEnvelope(status.ok, status.ok ? L"" : status.errorCode, status.ok ? L"OK" : status.errorMessage, status.dataJson.empty() ? L"{}" : status.dataJson, status.artifacts, status.reportPath, ElapsedMs(startTick));
        AppendServiceAudit(endpoint, taskId, permissionMode, status.ok, status.errorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/get_task_events") {
        TaskSessionControlResult events = ReadStableTaskSessionEvents(taskId, file);
        response = ServiceEnvelope(events.ok, events.ok ? L"" : events.errorCode, events.ok ? L"OK" : events.errorMessage, events.dataJson.empty() ? L"{}" : events.dataJson, events.artifacts, events.reportPath, ElapsedMs(startTick));
        AppendServiceAudit(endpoint, taskId, permissionMode, events.ok, events.errorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/confirm_task_action") {
        TaskSessionControlResult confirmed = ConfirmStableTaskSessionAction(taskId, file, responseText);
        response = ServiceEnvelope(confirmed.ok, confirmed.ok ? L"" : confirmed.errorCode, confirmed.ok ? L"OK" : confirmed.errorMessage, confirmed.dataJson.empty() ? L"{}" : confirmed.dataJson, confirmed.artifacts, confirmed.reportPath, ElapsedMs(startTick));
        AppendServiceAudit(endpoint, taskId, permissionMode, confirmed.ok, confirmed.errorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/cancel_task") {
        TaskSessionControlResult cancelled = CancelStableTaskSession(taskId, file, reason);
        response = ServiceEnvelope(cancelled.ok, cancelled.ok ? L"" : cancelled.errorCode, cancelled.ok ? L"OK" : cancelled.errorMessage, cancelled.dataJson.empty() ? L"{}" : cancelled.dataJson, cancelled.artifacts, cancelled.reportPath, ElapsedMs(startTick));
        AppendServiceAudit(endpoint, taskId, permissionMode, cancelled.ok, cancelled.errorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/read_task_report") {
        TaskSessionControlResult taskReport = ReadStableTaskSessionReport(taskId, file);
        response = ServiceEnvelope(taskReport.ok, taskReport.ok ? L"" : taskReport.errorCode, taskReport.ok ? L"OK" : taskReport.errorMessage, taskReport.dataJson.empty() ? L"{}" : taskReport.dataJson, taskReport.artifacts, taskReport.reportPath, ElapsedMs(startTick));
        AppendServiceAudit(endpoint, taskId, permissionMode, taskReport.ok, taskReport.errorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/run-task") {
        std::wstring taskFile = SimpleJsonGetString(body, L"file");
        std::wstring taskReport = SimpleJsonGetString(body, L"report");
        if (taskFile.empty()) {
            response = ServiceEnvelope(false, L"INVALID_ARGUMENT", L"/run-task requires file.", L"{}", {}, L"", ElapsedMs(startTick));
            AppendServiceAudit(endpoint, L"", permissionMode, false, L"INVALID_ARGUMENT", ElapsedMs(startTick));
            return L"";
        }
        TaskSessionValidationResult taskSession = ValidateTaskSessionFile(taskFile);
        if (taskSession.ok) {
            TaskSessionRunResult sessionRun = RunStableTaskSessionFile(taskFile);
            response = ServiceEnvelope(
                sessionRun.ok,
                sessionRun.ok ? L"" : (sessionRun.errorCode.empty() ? L"TASK_SESSION_RUN_FAILED" : sessionRun.errorCode),
                sessionRun.ok ? L"OK" : sessionRun.errorMessage,
                sessionRun.dataJson.empty() ? L"{}" : sessionRun.dataJson,
                sessionRun.reportPath.empty() ? std::vector<std::wstring>{} : std::vector<std::wstring>{sessionRun.progressPath, sessionRun.eventsPath, sessionRun.reportPath},
                sessionRun.reportPath,
                ElapsedMs(startTick));
            AppendServiceAudit(endpoint, taskSession.session.taskId, permissionMode, sessionRun.ok, sessionRun.errorCode, ElapsedMs(startTick));
            return L"";
        }
        if (taskReport.empty()) {
            response = ServiceEnvelope(false, L"INVALID_ARGUMENT", L"/run-task requires report for legacy TaskRunner task files. TaskSession files can omit report.", taskSession.dataJson.empty() ? L"{}" : taskSession.dataJson, {}, L"", ElapsedMs(startTick));
            AppendServiceAudit(endpoint, L"", permissionMode, false, L"INVALID_ARGUMENT", ElapsedMs(startTick));
            return L"";
        }
        TaskResult tr = RunTask(taskFile, taskReport, true, permissionMode, fullAccessSessionId);
        std::wstring data = L"{\"task\":\"" + JsonEscape(tr.taskName)
            + L"\",\"permission_mode\":\"" + JsonEscape(tr.permissionMode)
            + L"\",\"steps\":" + std::to_wstring(tr.totalSteps)
            + L",\"passed\":" + std::to_wstring(tr.passedSteps)
            + L",\"recoveries\":" + std::to_wstring(tr.recoveriesUsed)
            + L",\"recovery_records\":" + std::to_wstring(tr.recoveryAttempts.size())
            + L",\"report\":\"" + JsonEscape(taskReport) + L"\"}";
        std::vector<std::wstring> artifacts;
        if (!taskReport.empty()) artifacts.push_back(taskReport);
        response = ServiceEnvelope(
            tr.ok,
            tr.ok ? L"" : (tr.finalErrorCode.empty() ? L"UNKNOWN_ERROR" : tr.finalErrorCode),
            tr.ok ? L"OK" : tr.finalErrorMessage,
            data,
            artifacts,
            taskReport,
            ElapsedMs(startTick));
        AppendServiceAudit(endpoint, tr.taskName, permissionMode, tr.ok, tr.finalErrorCode, ElapsedMs(startTick));
        return L"";
    } else if (endpoint == L"/report" || endpoint == L"/read-report") {
        // Read report file with safety path check
        std::wstring normalizedPath;
        std::wstring safetyError;
        if (!IsReadPathAllowed(path, normalizedPath, safetyError)) {
            response = ServiceEnvelope(false, L"SAFETY_POLICY_DENIED", safetyError, L"{}", {}, L"", ElapsedMs(startTick));
            AppendServiceAudit(endpoint, L"", permissionMode, false, L"SAFETY_POLICY_DENIED", ElapsedMs(startTick));
            return L"";
        }
        FileReadResult read = ReadTextFile(normalizedPath);
        if (!read.ok) {
            response = ServiceEnvelope(false, L"FILE_READ_FAILED", read.error, L"{}", {}, normalizedPath, ElapsedMs(startTick));
            AppendServiceAudit(endpoint, L"", permissionMode, false, L"FILE_READ_FAILED", ElapsedMs(startTick));
            return L"";
        }
        response = ServiceEnvelope(true, L"", L"OK", L"{\"path\":" + JsonString(normalizedPath) + L",\"content\":" + JsonString(read.content) + L",\"content_length\":" + std::to_wstring(read.content.size()) + L"}", {normalizedPath}, normalizedPath, ElapsedMs(startTick));
        AppendServiceAudit(endpoint, L"", permissionMode, true, L"", ElapsedMs(startTick));
        return L"";
    } else {
        response = ServiceEnvelope(false, L"INVALID_ARGUMENT", L"Unknown endpoint: " + endpoint, L"{}", {}, L"", ElapsedMs(startTick));
        AppendServiceAudit(endpoint, L"", permissionMode, false, L"INVALID_ARGUMENT", ElapsedMs(startTick));
        return L"";
    }

    // Build argv
    for (auto& s : fakeArgs) { fakeArgv.push_back(&s[0]); }
    int fakeArgc = static_cast<int>(fakeArgv.size());

    // Capture stdout
    std::wstringstream captured;
    auto oldBuf = std::wcout.rdbuf();
    std::wcout.rdbuf(captured.rdbuf());

    int exitCode = RunWinAgent(fakeArgc, fakeArgv.data());

    std::wcout.rdbuf(oldBuf);
    response = ServiceEnvelopeFromCli(captured.str(), ElapsedMs(startTick), report.empty() ? std::vector<std::wstring>{} : std::vector<std::wstring>{report}, report);

    // Parse response to extract ok/error_code
    bool ok = response.find(L"\"ok\":true") != std::wstring::npos;
    std::wstring errorCode;
    if (!ok) {
        errorCode = SimpleJsonGetString(response, L"error_code");
        g_session.errorCount++;
    }

    if (endpoint == L"/observe" && ok) {
        g_session.lastObserveSummary = L"observed";
    }

    AppendServiceAudit(endpoint, title, permissionMode, ok, errorCode, ElapsedMs(startTick));
    (void)exitCode;
    return L"";
}

int CommandServe(int argc, wchar_t** argv) {
    std::wstring host = L"127.0.0.1";
    int port = 17873;
    std::wstring token;
    int maxSessionMs = 3600000;

    for (int i = 2; i + 1 < argc; ++i) {
        if (wcscmp(argv[i], L"--host") == 0) host = argv[++i];
        else if (wcscmp(argv[i], L"--port") == 0) port = std::stoi(argv[++i]);
        else if (wcscmp(argv[i], L"--token") == 0) token = argv[++i];
        else if (wcscmp(argv[i], L"--max-session-ms") == 0) maxSessionMs = std::stoi(argv[++i]);
    }

    g_session.sessionId = GenerateSessionId();
    g_session.startTime = NowTimestamp();
    g_session.requestCount = 0;
    g_session.actionCount = 0;
    g_session.errorCount = 0;
    g_shutdownRequested = false;

    if (token.empty()) {
        std::wcout << L"WARNING: No --token set. Service accepts requests only from localhost (127.0.0.1)." << std::endl;
    } else {
        std::wcout << L"Token auth enabled." << std::endl;
    }

    std::wstring pipeName = L"\\\\.\\pipe\\DesktopVisualService";
    std::wcout << L"Starting DesktopVisual Service v" << kRuntimeVersion << std::endl;
    std::wcout << L"Pipe: " << pipeName << std::endl;
    std::wcout << L"Session: " << g_session.sessionId << std::endl;
    std::wcout << L"Max session: " << maxSessionMs << L"ms" << std::endl;

    ULONGLONG sessionStart = GetTickCount64();

    while (!g_shutdownRequested) {
        if (maxSessionMs > 0 && ElapsedMs(sessionStart) > maxSessionMs) {
            std::wcout << L"Session max duration reached. Shutting down." << std::endl;
            break;
        }

        HANDLE pipe = CreateNamedPipeW(
            pipeName.c_str(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
            1,          // max instances
            65536,      // out buffer
            65536,      // in buffer
            30000,      // timeout ms
            nullptr);

        if (pipe == INVALID_HANDLE_VALUE) {
            std::wcout << L"CreateNamedPipe failed: " << GetLastError() << std::endl;
            Sleep(1000);
            continue;
        }

        BOOL connected = ConnectNamedPipe(pipe, nullptr);
        if (!connected && GetLastError() != ERROR_PIPE_CONNECTED) {
            CloseHandle(pipe);
            Sleep(100);
            continue;
        }

        // Read request (treat as UTF-8 bytes, convert to wstring)
        char rawBuffer[65536] = {};
        DWORD bytesRead = 0;
        BOOL readOk = ReadFile(pipe, rawBuffer, sizeof(rawBuffer) - 1, &bytesRead, nullptr);
        std::wstring requestJson;
        if (readOk && bytesRead > 0) {
            rawBuffer[bytesRead] = '\0';
            // Trim trailing whitespace/newlines
            while (bytesRead > 0 && (rawBuffer[bytesRead-1] == '\r' || rawBuffer[bytesRead-1] == '\n' || rawBuffer[bytesRead-1] == ' ')) {
                rawBuffer[--bytesRead] = '\0';
            }
            // UTF-8 to wide
            int wideLen = MultiByteToWideChar(CP_UTF8, 0, rawBuffer, bytesRead, nullptr, 0);
            if (wideLen > 0) {
                requestJson.resize(wideLen);
                MultiByteToWideChar(CP_UTF8, 0, rawBuffer, bytesRead, &requestJson[0], wideLen);
            }
        }

        // Check token
        bool tokenOk = true;
        if (!token.empty()) {
            std::wstring reqToken = SimpleJsonGetString(requestJson, L"token");
            if (reqToken != token) {
                std::wstring endpoint = SimpleJsonGetString(requestJson, L"endpoint");
                std::wstring body = SimpleJsonGetRaw(requestJson, L"body");
                std::wstring permissionMode = SimpleJsonGetString(body, L"permission_mode");
                if (permissionMode.empty()) permissionMode = DefaultPermissionModeName();
                AppendServiceAudit(endpoint, L"", permissionMode, false, L"UNAUTHORIZED", 0);
                std::wstring wideResp = ServiceEnvelope(false, L"UNAUTHORIZED", L"Invalid or missing token.", L"{}", {}, L"", 0);
                int utf8Len = WideCharToMultiByte(CP_UTF8, 0, wideResp.c_str(), -1, nullptr, 0, nullptr, nullptr);
                std::string resp;
                if (utf8Len > 1) {
                    resp.resize(utf8Len - 1);
                    WideCharToMultiByte(CP_UTF8, 0, wideResp.c_str(), -1, &resp[0], utf8Len, nullptr, nullptr);
                } else {
                    resp = "{\"ok\":false,\"error_code\":\"UNAUTHORIZED\",\"message\":\"Invalid or missing token.\",\"data\":{},\"artifacts\":[],\"report_path\":\"\",\"duration_ms\":0,\"service_protocol_version\":\"1.0\",\"error\":{\"code\":\"UNAUTHORIZED\",\"message\":\"Invalid or missing token.\"}}";
                }
                resp.push_back('\n');
                DWORD written = 0;
                WriteFile(pipe, resp.c_str(), static_cast<DWORD>(resp.size()), &written, nullptr);
                FlushFileBuffers(pipe);
                DisconnectNamedPipe(pipe);
                CloseHandle(pipe);
                continue;
            }
        }

        std::wstring response;
        ServiceHandleRequest(requestJson, response);

        if (!response.empty()) {
            // Convert response to UTF-8 for pipe transmission
            int utf8Len = WideCharToMultiByte(CP_UTF8, 0, response.c_str(), -1, nullptr, 0, nullptr, nullptr);
            if (utf8Len > 1) {
                std::string utf8(utf8Len - 1, '\0');
                WideCharToMultiByte(CP_UTF8, 0, response.c_str(), -1, &utf8[0], utf8Len, nullptr, nullptr);
                utf8.push_back('\n');
                DWORD written = 0;
                WriteFile(pipe, utf8.c_str(), static_cast<DWORD>(utf8.size()), &written, nullptr);
            }
        }

        FlushFileBuffers(pipe);
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
    }

    std::wcout << L"Service stopped. Requests: " << g_session.requestCount
              << L" Actions: " << g_session.actionCount
              << L" Errors: " << g_session.errorCount << std::endl;
    return 0;
}

}  // namespace (service)

int RunWinAgent(int argc, wchar_t** argv) {
    ResetUserAbortForCurrentTask();
    if (argc < 2) {
        ULONGLONG startTick = GetTickCount64();
        std::wcout << CommandFailureJson(L"unknown", startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Missing command.", L"{}") << L"\n";
        return 2;
    }

    std::wstring command = argv[1];
    if (command == L"help" || command == L"--help" || command == L"-h") {
        PrintUsage();
        return 0;
    }
    if (IsRuntimeSessionCommand(command) ||
        (RuntimeSessionArgPresent(argc, argv) && IsRuntimeSessionCompatibleLegacyCommand(command))) {
        return DispatchRuntimeSessionCommandLine(argc, argv);
    }
    if (command == L"mouse_position") {
        return CommandMousePosition(L"mouse_position", L"mouse-position");
    }
    if (command == L"read_window_text") {
        return CommandReadWindowText(argc, argv, L"read_window_text", L"read-window-text");
    }
    if (command == L"windows") {
        return CommandWindows();
    }
    if (command == L"version") {
        return CommandVersion();
    }
    if (command == L"permission-status") {
        return CommandPermissionStatus();
    }
    if (command == L"unlock-full-access") {
        return CommandUnlockFullAccess(argc, argv);
    }
    if (command == L"lock-full-access") {
        return CommandLockFullAccess();
    }
    if (command == L"safety-report") {
        return CommandSafetyReport();
    }
    if (command == L"policy-check") {
        return CommandPolicyCheck(argc, argv);
    }
    if (command == L"consent-check") {
        return CommandConsentCheck(argc, argv);
    }
    if (command == L"launch-app") {
        return CommandLaunchApp(argc, argv);
    }
    if (command == L"pycharm-dev-demo") {
        return CommandPyCharmDevDemo(argc, argv);
    }
    if (command == L"browser-nav") {
        return CommandBrowserNav(argc, argv);
    }
    if (command == L"browser-surface-normalize") {
        return CommandBrowserSurfaceNormalize(argc, argv);
    }
    if (command == L"browser-open-url-human") {
        return CommandBrowserOpenUrlHuman(argc, argv);
    }
    if (command == L"form-control") {
        return CommandFormControl(argc, argv);
    }
    if (command == L"decision-eval") {
        return CommandDecisionEval(argc, argv);
    }
    if (command == L"coding-eval") {
        return CommandCodingEval(argc, argv);
    }
    if (command == L"agent-boundary-validate") {
        return CommandAgentBoundaryValidate(argc, argv);
    }
    if (command == L"agent-intent-parse") {
        return CommandAgentIntentParse(argc, argv);
    }
    if (command == L"agent-plan-draft") {
        return CommandAgentPlanDraft(argc, argv);
    }
    if (command == L"agent-planner-validate") {
        return CommandAgentPlannerValidate(argc, argv);
    }
    if (command == L"plan-compile") {
        return CommandPlanCompile(argc, argv);
    }
    if (command == L"step-contract-dry-run") {
        return CommandStepContractDryRun(argc, argv);
    }
    if (command == L"plan-compile-selftest") {
        return CommandPlanCompileSelftest(argc, argv);
    }
    if (command == L"validation-fingerprint") {
        return CommandValidationFingerprint(argc, argv);
    }
    if (command == L"validation-consistency-check") {
        return CommandValidationConsistencyCheck(argc, argv);
    }
    if (command == L"regression-skip-evaluate") {
        return CommandRegressionSkipEvaluate(argc, argv);
    }
    if (command == L"evidence-consolidate") {
        return CommandEvidenceConsolidate(argc, argv);
    }
    if (command == L"session-lifecycle-audit") {
        return CommandSessionLifecycleAudit(argc, argv);
    }
    if (command == L"workflow-boundary-check") {
        return CommandWorkflowBoundaryCheck(argc, argv);
    }
    if (command == L"system-stabilization-check") {
        return CommandSystemStabilizationCheck(argc, argv);
    }
    if (command == L"compile-browser-workflow") {
        return CommandCompileBrowserWorkflow(argc, argv);
    }
    if (command == L"run-browser-workflow") {
        return CommandRunBrowserWorkflow(argc, argv);
    }
    if (command == L"verify-browser-workflow") {
        return CommandVerifyBrowserWorkflow(argc, argv);
    }
    if (command == L"compile-communication-workflow") {
        return CommandCompileCommunicationWorkflow(argc, argv);
    }
    if (command == L"run-communication-workflow") {
        return CommandRunCommunicationWorkflow(argc, argv);
    }
    if (command == L"verify-communication-workflow") {
        return CommandVerifyCommunicationWorkflow(argc, argv);
    }
    if (command == L"compile-explorer-workflow") {
        return CommandCompileExplorerWorkflow(argc, argv);
    }
    if (command == L"run-explorer-workflow") {
        return CommandRunExplorerWorkflow(argc, argv);
    }
    if (command == L"verify-explorer-workflow") {
        return CommandVerifyExplorerWorkflow(argc, argv);
    }
    if (command == L"run-agent-task") {
        return CommandRunAgentTask(argc, argv);
    }
    if (command == L"execute-step-contract") {
        return CommandExecuteStepContract(argc, argv);
    }
    if (command == L"execute-compiled-plan") {
        return CommandExecuteCompiledPlan(argc, argv);
    }
    if (command == L"step-execution-verify") {
        return CommandStepExecutionVerify(argc, argv);
    }
    if (command == L"vlm-capability-probe") {
        return CommandVlmCapabilityProbe(argc, argv);
    }
    if (command == L"vlm-assist-locate") {
        return CommandVlmAssistLocate(argc, argv);
    }
    if (command == L"vlm-candidate-validate") {
        return CommandVlmCandidateValidate(argc, argv);
    }
    if (command == L"vlm-frame-transport-check") {
        return CommandVlmFrameTransportCheck(argc, argv);
    }
    if (command == L"vlm-observation-build-request") {
        return CommandVLMObservationBuildRequest(argc, argv);
    }
    if (command == L"vlm-observation-run-mock") {
        return CommandVLMObservationRunMock(argc, argv);
    }
    if (command == L"vlm-observation-validate") {
        return CommandVLMObservationValidate(argc, argv);
    }
    if (command == L"vlm-observation-dry-run") {
        return CommandVLMObservationDryRun(argc, argv);
    }
    if (command == L"vlm-observation-selftest") {
        return CommandVLMObservationSelftest(argc, argv);
    }
    if (command == L"vlm-assisted-locate") {
        return CommandVLMAssistedLocate(argc, argv);
    }
    if (command == L"vlm-assisted-locate-dry-run") {
        return CommandVLMAssistedLocateDryRun(argc, argv);
    }
    if (command == L"vlm-assisted-locate-and-click-local-safe") {
        return CommandVLMAssistedLocateAndClickLocalSafe(argc, argv);
    }
    if (command == L"find") {
        return CommandFind(argc, argv);
    }
    if (command == L"global-screenshot") {
        return CommandGlobalScreenshot(argc, argv);
    }
    if (command == L"capture-fullscreen-frame") {
        return CommandCaptureFullscreenFrame(argc, argv);
    }
    if (command == L"evidence-flush" || command == L"frame-evidence-flush") {
        return CommandEvidenceFlush(argc, argv, command);
    }
    if (command == L"screenshot") {
        return CommandScreenshot(argc, argv);
    }
    if (command == L"target-lock-acquire") {
        return CommandTargetLockAcquire(argc, argv);
    }
    if (command == L"target-lock-release") {
        return CommandTargetLockRelease(argc, argv);
    }
    if (command == L"coordinate-map") {
        return CommandCoordinateMap(argc, argv);
    }
    if (command == L"foreground-preempt") {
        return CommandForegroundPreempt(argc, argv);
    }
    if (command == L"visible-text-input") {
        return CommandVisibleTextInput(argc, argv);
    }
    if (command == L"visible-action-batch") {
        return CommandVisibleActionBatch(argc, argv);
    }
    if (command == L"visible-ui-verify") {
        return CommandVisibleUiVerify(argc, argv);
    }
    if (command == L"visible-operation-policy-check") {
        return CommandVisibleOperationPolicyCheck(argc, argv);
    }
    if (command == L"visible-app-launch") {
        return CommandVisibleAppLaunch(argc, argv);
    }
    if (command == L"visible-show-desktop") {
        return CommandVisibleShowDesktop(argc, argv);
    }
    if (command == L"visible-window-switch") {
        return CommandVisibleWindowSwitch(argc, argv);
    }
    if (command == L"taskbar-icon-locate" || command == L"taskbar-icon-click" ||
        command == L"desktop-icon-locate" || command == L"desktop-icon-double-click" ||
        command == L"start-menu-visible-launch" ||
        command == L"visible-page-navigation") {
        return CommandVisibleRuntimePrimitive(argc, argv, command);
    }
    if (command == L"vlm-runtime-candidate") {
        return CommandVlmRuntimeCandidate(argc, argv);
    }
    if (command == L"pycharm-visible-demo") {
        return CommandPyCharmVisibleDemo(argc, argv);
    }
    if (command == L"operation-timeline-profiler-selftest") {
        return CommandOperationTimelineProfilerSelftest();
    }
    if (command == L"motion-pacer-selftest") {
        return CommandMotionPacerSelftest(argc, argv);
    }
    if (command == L"observe") {
        return CommandObserve(argc, argv);
    }
    if (command == L"observe2") {
        return CommandObserve2(argc, argv);
    }
    if (command == L"observe-loop") {
        return CommandObserveLoop(argc, argv);
    }
    if (command == L"dynamic-ui-recovery") {
        return CommandDynamicUiRecovery(argc, argv);
    }
    if (command == L"adaptive-locate") {
        return CommandAdaptiveLocate(argc, argv);
    }
    if (command == L"adaptive-click") {
        return CommandAdaptiveClick(argc, argv);
    }
    if (command == L"adaptive-double-click") {
        return CommandAdaptiveDoubleClick(argc, argv);
    }
    if (command == L"adaptive-type") {
        return CommandAdaptiveType(argc, argv);
    }
    if (command == L"adaptive-run-step") {
        return CommandAdaptiveRunStep(argc, argv);
    }
    if (command == L"adaptive-scroll") {
        return CommandAdaptiveScroll(argc, argv);
    }
    if (command == L"scroll-and-locate") {
        return CommandScrollAndLocate(argc, argv);
    }
    if (command == L"profile-report") {
        return CommandProfileReport(argc, argv);
    }
    if (command == L"target-semantics-guard-check") {
        return CommandTargetSemanticsGuardCheck(argc, argv);
    }
    if (command == L"classify-execution-output") {
        return CommandClassifyExecutionOutput(argc, argv);
    }
    if (command == L"step-completion-evaluate") {
        return CommandStepCompletionEvaluate(argc, argv);
    }
    if (command == L"locate") {
        return CommandLocate(argc, argv);
    }
    if (command == L"act") {
        return CommandAct(argc, argv);
    }
    if (command == L"click") {
        return CommandClick(argc, argv);
    }
    if (command == L"double-click" && ArgExists(argc, argv, L"--screen-x")) {
        return CommandDesktopMouseVariant(argc, argv, L"desktop-double-click");
    }
    if (command == L"double-click") {
        return CommandMouseClickVariant(argc, argv, command);
    }
    if (command == L"right-click" && ArgExists(argc, argv, L"--screen-x")) {
        return CommandDesktopMouseVariant(argc, argv, L"desktop-right-click");
    }
    if (command == L"right-click") {
        return CommandMouseClickVariant(argc, argv, command);
    }
    if (command == L"scroll") {
        return CommandScroll(argc, argv);
    }
    if (command == L"drag") {
        return CommandDrag(argc, argv);
    }
    if (command == L"press") {
        return CommandPress(argc, argv);
    }
    if (command == L"hotkey") {
        return CommandHotkey(argc, argv);
    }
    if (command == L"type") {
        return CommandType(argc, argv);
    }
    if (command == L"desktop-move" || command == L"desktop-click" || command == L"desktop-double-click" || command == L"desktop-right-click") {
        return CommandDesktopMouseVariant(argc, argv, command);
    }
    if (command == L"desktop-press" || command == L"desktop-hotkey" || command == L"desktop-type") {
        return CommandDesktopKeyboardVariant(argc, argv, command);
    }
    if (command == L"clipboard-set") {
        return CommandClipboardSet(argc, argv);
    }
    if (command == L"clipboard-paste") {
        return CommandClipboardPaste(argc, argv);
    }
    if (command == L"focus") {
        return CommandFocus(argc, argv);
    }
    if (command == L"focus-window" || command == L"activate-window" || command == L"bring-window-front" ||
        command == L"minimize-window" || command == L"restore-window") {
        return CommandWindowActivation(argc, argv, command);
    }
    if (command == L"prepare-foreground") {
        return CommandPrepareForeground(argc, argv);
    }
    if (command == L"active-window") {
        return CommandActiveWindow();
    }
    if (command == L"mouse-position") {
        return CommandMousePosition();
    }
    if (command == L"read-file") {
        return CommandReadFile(argc, argv);
    }
    if (command == L"uia-tree") {
        return CommandUiaTree(argc, argv);
    }
    if (command == L"uia-find") {
        return CommandUiaFind(argc, argv);
    }
    if (command == L"uia-click") {
        return CommandUiaClick(argc, argv);
    }
    if (command == L"uia-type") {
        return CommandUiaType(argc, argv);
    }
    if (command == L"find-text") {
        return CommandFindText(argc, argv);
    }
    if (command == L"click-text") {
        return CommandClickText(argc, argv);
    }
    if (command == L"find-image") {
        return CommandFindImage(argc, argv);
    }
    if (command == L"click-image") {
        return CommandClickImage(argc, argv);
    }
    if (command == L"read-window-text") {
        return CommandReadWindowText(argc, argv);
    }
    if (command == L"read-region-text") {
        return CommandReadRegionText(argc, argv);
    }
    if (command == L"read-screen-region-text") {
        return CommandReadScreenRegionText(argc, argv);
    }
    if (command == L"ocr-fullscreen-frame") {
        return CommandOcrFullscreenFrame(argc, argv);
    }
    if (command == L"ocr-foreground-from-frame") {
        return CommandOcrForegroundFromFrame(argc, argv, command);
    }
    if (command == L"ocr-window-from-frame") {
        return CommandOcrForegroundFromFrame(argc, argv, command);
    }
    if (command == L"ocr-cache-status") {
        return CommandOcrCacheStatus();
    }
    if (command == L"ocr-cache-clear") {
        return CommandOcrCacheClear();
    }
    if (command == L"wait-text") {
        return CommandWaitText(argc, argv);
    }
    if (command == L"assert-text-contains") {
        return CommandAssertTextContains(argc, argv);
    }
    if (command == L"motion-record") {
        return CommandMotionRecord(argc, argv);
    }
    if (command == L"motion-calibrate") {
        return CommandMotionCalibrate(argc, argv);
    }
    if (command == L"motion-profile-info") {
        return CommandMotionProfileInfo(argc, argv);
    }
    if (command == L"motion-profile-validate") {
        return CommandMotionProfileValidate(argc, argv);
    }
    if (command == L"motion-profile-clear") {
        return CommandMotionProfileClear(argc, argv);
    }
    if (command == L"motion-pacer-selftest") {
        return CommandMotionPacerSelftest(argc, argv);
    }
    if (command == L"task-session-validate") {
        return CommandTaskSessionValidate(argc, argv);
    }
    if (command == L"task-session-transition") {
        return CommandTaskSessionTransition(argc, argv);
    }
    if (command == L"task-session-run") {
        return CommandTaskSessionRun(argc, argv);
    }
    if (command == L"task-status") {
        return CommandTaskStatus(argc, argv);
    }
    if (command == L"task-report") {
        return CommandTaskReport(argc, argv);
    }
    if (command == L"task-events") {
        return CommandTaskEvents(argc, argv);
    }
    if (command == L"task-cancel") {
        return CommandTaskCancel(argc, argv);
    }
    if (command == L"task-confirm") {
        return CommandTaskConfirm(argc, argv);
    }
    if (command == L"task-template-v2-validate") {
        return CommandTaskTemplateV2Validate(argc, argv);
    }
    if (command == L"task-template-v2-resolve") {
        return CommandTaskTemplateV2Resolve(argc, argv);
    }
    if (command == L"file-path-resolve") {
        return CommandFilePathResolve(argc, argv);
    }
    if (command == L"file-picker-flow") {
        return CommandFilePickerFlow(argc, argv);
    }
    if (command == L"attachment-verify") {
        return CommandAttachmentVerify(argc, argv);
    }
    if (command == L"cross-window-check") {
        return CommandCrossWindowCheck(argc, argv);
    }
    if (command == L"local-mail-attach-flow") {
        return CommandLocalMailAttachFlow(argc, argv);
    }
    if (command == L"step-contract-validate") {
        return CommandStepContractValidate(argc, argv);
    }
    if (command == L"step-precondition-check") {
        return CommandStepPreconditionCheck(argc, argv);
    }
    if (command == L"step-verify") {
        return CommandStepVerify(argc, argv);
    }
    if (command == L"step-failure-classify") {
        return CommandStepFailureClassify(argc, argv);
    }
    if (command == L"recovery-policy-validate") {
        return CommandRecoveryPolicyValidate(argc, argv);
    }
    if (command == L"recovery-evaluate") {
        return CommandRecoveryEvaluate(argc, argv);
    }
    if (command == L"safe-context-recovery") {
        return CommandSafeContextRecovery(argc, argv);
    }
    if (command == L"task-checkpoint-evaluate") {
        return CommandTaskCheckpointEvaluate(argc, argv);
    }
    if (command == L"failure-attribution-classify") {
        return CommandFailureAttributionClassify(argc, argv);
    }
    if (command == L"experience-memory-record") {
        return CommandExperienceMemoryRecord(argc, argv);
    }
    if (command == L"experience-memory-query") {
        return CommandExperienceMemoryQuery(argc, argv);
    }
    if (command == L"experience-memory-report") {
        return CommandExperienceMemoryReport(argc, argv);
    }
    if (command == L"failure-attribution-normalize") {
        return CommandFailureAttributionNormalize(argc, argv);
    }
    if (command == L"memory-safety-check") {
        return CommandMemorySafetyCheck(argc, argv);
    }
    if (command == L"v6-10-experience-memory-check") {
        return CommandV610ExperienceMemoryCheck(argc, argv);
    }
    if (command == L"workflow-template-extract") {
        return CommandWorkflowTemplateExtract(argc, argv);
    }
    if (command == L"workflow-template-validate") {
        return CommandWorkflowTemplateValidate(argc, argv);
    }
    if (command == L"workflow-template-register") {
        return CommandWorkflowTemplateRegister(argc, argv);
    }
    if (command == L"workflow-template-instantiate") {
        return CommandWorkflowTemplateInstantiate(argc, argv);
    }
    if (command == L"workflow-template-report") {
        return CommandWorkflowTemplateReport(argc, argv);
    }
    if (command == L"workflow-template-safety-check") {
        return CommandWorkflowTemplateSafetyCheck(argc, argv);
    }
    if (command == L"batch-workflow-plan") {
        return CommandBatchWorkflowPlan(argc, argv);
    }
    if (command == L"batch-workflow-validate") {
        return CommandBatchWorkflowValidate(argc, argv);
    }
    if (command == L"batch-workflow-run") {
        return CommandBatchWorkflowRun(argc, argv);
    }
    if (command == L"batch-workflow-report") {
        return CommandBatchWorkflowReport(argc, argv);
    }
    if (command == L"v6-11-template-batch-check") {
        return CommandV611TemplateBatchCheck(argc, argv);
    }
    if (command == L"developer-rc-gate") {
        return CommandDeveloperRCGate(argc, argv);
    }
    if (command == L"version-integrity-check") {
        return CommandVersionIntegrityCheck(argc, argv);
    }
    if (command == L"evidence-chain-verify") {
        return CommandEvidenceChainVerify(argc, argv);
    }
    if (command == L"capability-matrix-build") {
        return CommandCapabilityMatrixBuild(argc, argv);
    }
    if (command == L"workflow-boundary-audit") {
        return CommandWorkflowBoundaryAudit(argc, argv);
    }
    if (command == L"developer-full-access-policy-check") {
        return CommandDeveloperFullAccessPolicyCheck(argc, argv);
    }
    if (command == L"release-hardening-deferred-ledger") {
        return CommandReleaseHardeningDeferredLedger(argc, argv);
    }
    if (command == L"handoff-package-build") {
        return CommandHandoffPackageBuild(argc, argv);
    }
    if (command == L"v6-12-rc-handoff-check") {
        return CommandV612RCHandoffCheck(argc, argv);
    }
    if (command == L"escalation-request-create") {
        return CommandEscalationRequestCreate(argc, argv);
    }
    if (command == L"safe-stop-check") {
        return CommandSafeStopCheck(argc, argv);
    }
    if (command == L"risk-action-classify") {
        return CommandRiskActionClassify(argc, argv);
    }
    if (command == L"confirmation-request-create") {
        return CommandConfirmationRequestCreate(argc, argv);
    }
    if (command == L"confirmation-gate-check") {
        return CommandConfirmationGateCheck(argc, argv);
    }
    if (command == L"confirmation-flow-run") {
        return CommandConfirmationFlowRun(argc, argv);
    }
    if (command == L"run-task") {
        ULONGLONG startTick = GetTickCount64();
        std::wstring file, report, permissionMode, fullAccessSessionId;
        if (!ArgValue(argc, argv, L"--file", file) || file.empty()) {
            return EmitFailure(L"run-task", startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-task requires --file.", L"{}", 2);
        }
        TaskSessionValidationResult taskSession = ValidateTaskSessionFile(file);
        if (taskSession.ok) {
            TaskSessionRunResult sessionRun = RunStableTaskSessionFile(file);
            if (!sessionRun.ok) {
                return EmitFailure(L"run-task", startTick, NoTraceTarget(), sessionRun.errorCode.empty() ? L"TASK_SESSION_RUN_FAILED" : sessionRun.errorCode, sessionRun.errorMessage, sessionRun.dataJson, 1);
            }
            return EmitSuccess(L"run-task", startTick, NoTraceTarget(), sessionRun.dataJson);
        }
        if (!ArgValue(argc, argv, L"--report", report) || report.empty()) {
            return EmitFailure(L"run-task", startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-task requires --report for legacy TaskRunner task files. TaskSession files can omit --report.", taskSession.dataJson.empty() ? L"{}" : taskSession.dataJson, 2);
        }
        ArgValue(argc, argv, L"--permission-mode", permissionMode);
        ArgValue(argc, argv, L"--full-access-session-id", fullAccessSessionId);
        TaskResult tr = RunTask(file, report, false, permissionMode, fullAccessSessionId);
        std::wstringstream data2;
        data2 << L"{\"task\":" << JsonString(tr.taskName)
              << L",\"ok\":" << (tr.ok ? L"true" : L"false")
              << L",\"permission_mode\":" << JsonString(tr.permissionMode)
              << L",\"full_access_session_id\":" << JsonString(tr.fullAccessSessionId)
              << L",\"steps\":" << tr.totalSteps
              << L",\"passed\":" << tr.passedSteps
              << L",\"recoveries\":" << tr.recoveriesUsed
              << L",\"recovery_records\":" << tr.recoveryAttempts.size()
              << L",\"duration_ms\":" << tr.totalDurationMs
              << L",\"report\":" << JsonString(report) << L"}";
        if (!tr.ok) {
            return EmitFailure(L"run-task", startTick, NoTraceTarget(), tr.finalErrorCode.empty() ? L"UNKNOWN_ERROR" : tr.finalErrorCode, tr.finalErrorMessage, data2.str(), 1);
        }
        return EmitSuccess(L"run-task", startTick, NoTraceTarget(), data2.str());
    }
    if (command == L"run-case") {
        return CommandRunCase(argc, argv);
    }
    if (command == L"serve") {
        return CommandServe(argc, argv);
    }

    ULONGLONG startTick = GetTickCount64();
    std::wstring data = L"{\"closest_matches\":" + StringArrayJson(ClosestCommandMatches(command)) + L"}";
    std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"Unknown command.", data) << L"\n";
    return 2;
}






