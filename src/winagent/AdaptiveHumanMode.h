#pragma once

#include "InputController.h"
#include "WindowFinder.h"

#include <windows.h>

#include <string>
#include <vector>

struct AdaptiveObservedState {
    HWND foregroundHwnd = nullptr;
    HWND targetHwnd = nullptr;
    DWORD pid = 0;
    std::wstring windowTitle;
    std::wstring processName;
    RECT windowRect = {};
    RECT contentRect = {};
    std::wstring screenshotPath;
    int screenshotWidth = 0;
    int screenshotHeight = 0;
    double dpiScale = 1.0;
    bool hasUia = false;
};

struct AdaptiveTargetSpec {
    std::wstring targetId;
    std::wstring targetKind;
    std::wstring expectedName;
    std::wstring expectedRole;
    std::wstring expectedText;
    std::wstring expectedWindowTitle;
    std::wstring expectedProcessName;
    HWND requiredContainerHwnd = nullptr;
    RECT requiredContentRect = {};
    bool hasRequiredContentRect = false;
    std::vector<std::wstring> allowedLocatorMethods;
    std::vector<RECT> forbiddenRegions;
    std::wstring matchPolicy = L"contains";
    bool strictMouseTargetRequired = true;
    bool allowKeyboardLocatorAssist = false;
    bool allowKeyboardOpen = false;
    bool allowHeuristicLocator = false;
    int maxRelocateAttempts = 2;
    double minConfidence = 0.70;
};

struct AdaptiveTargetCandidate {
    std::wstring candidateId;
    std::wstring targetId;
    std::wstring matchedName;
    std::wstring matchedText;
    std::wstring role;
    std::wstring source;
    HWND hwnd = nullptr;
    std::wstring windowTitle;
    std::wstring processName;
    RECT rect = {};
    int centerX = 0;
    int centerY = 0;
    double confidence = 0.0;
    bool isVisible = true;
    bool isOffscreen = false;
    bool intersectsRequiredRegion = true;
    bool insideForbiddenRegion = false;
    std::wstring reason;
    std::wstring rejectionReason;
};

struct AdaptiveLocateResult {
    bool ok = false;
    std::wstring targetId;
    AdaptiveTargetCandidate selectedCandidate;
    std::vector<AdaptiveTargetCandidate> candidates;
    std::vector<AdaptiveTargetCandidate> rejectedCandidates;
    int locateAttemptCount = 0;
    std::vector<std::wstring> locatorMethodsAttempted;
    std::wstring screenshotPath;
    RECT contentRect = {};
    std::wstring failureReason;
};

struct AdaptiveRetryPolicy {
    int maxActionRetries = 2;
    int backoffMs = 120;
};

struct AdaptiveActionSpec {
    std::wstring actionId;
    std::wstring actionType;
    AdaptiveTargetSpec targetSpec;
    std::wstring text;
    std::wstring key;
    bool humanmodeRequired = true;
    bool verifyCursorInsideTargetRect = true;
    bool verifyFocusAfterClick = true;
    bool verifyStateAfterAction = true;
    AdaptiveRetryPolicy retryPolicy;
    int timeoutMs = 5000;
};

struct AdaptiveError {
    std::wstring code;
    std::wstring message;
};

struct AdaptiveActionResult {
    bool ok = false;
    std::wstring actionId;
    std::wstring actionType;
    AdaptiveTargetCandidate targetCandidate;
    ClickResult humanClickResult;
    TypeResult humanTypeResult;
    std::wstring humanActionResultJson;
    std::wstring verificationResultJson;
    int reobserveCount = 0;
    int retryCount = 0;
    std::wstring finalState;
    AdaptiveError error;
};

struct BrowserFormLocatorOptions {
    std::wstring targetName;
    std::wstring targetKind;
    std::wstring expectedRole;
    HWND lockedBrowserHwnd = nullptr;
    std::wstring expectedPageTitle;
    RECT viewportRect = {};
    bool hasViewportRect = false;
    bool pageTitleVerified = false;
    bool allowDeterministicMockGeometry = true;
};

struct BrowserFormLocatorResult {
    bool ok = false;
    AdaptiveLocateResult locateResult;
    std::wstring failureReason;
    bool viewportRectVerified = false;
    bool heuristicLocatorDerived = false;
    bool rejectedParagraphSendText = false;
};

class BrowserFormLocator {
public:
    BrowserFormLocatorResult Locate(
        const BrowserFormLocatorOptions& options,
        const AdaptiveObservedState& state,
        const std::vector<AdaptiveTargetCandidate>& observedCandidates) const;
};

enum class AdaptiveFailureReason {
    None,
    TargetNotFound,
    MultipleCandidatesLowConfidence,
    TargetRectMissing,
    TargetOffscreen,
    TargetInForbiddenRegion,
    WrongWindow,
    ForegroundChanged,
    CursorNotInsideTargetRect,
    ClickNoEffect,
    TextNotEntered,
    FieldNotFocused,
    ButtonNotActivated,
    VerificationTimeout,
    ActiveProtectionDetected,
    PolicyDefect,
    RetryBudgetExhausted,
    CoordinateMappingFailed,
    FailSelectedItemRectMissing
};

std::wstring AdaptiveFailureReasonName(AdaptiveFailureReason reason);
bool MapScreenshotRectToScreenRect(const RECT& screenshotRect, const RECT& windowRect, int screenshotWidth, int screenshotHeight, RECT& screenRect, std::wstring& error);
bool MapWindowRelativeRectToScreenRect(const RECT& relativeRect, const RECT& windowRect, RECT& screenRect, std::wstring& error);
bool ValidateScreenPointInRect(int screenX, int screenY, const RECT& rect);
std::wstring AdaptiveCandidateJson(const AdaptiveTargetCandidate& candidate);
std::wstring AdaptiveLocateResultJson(const AdaptiveLocateResult& result);
std::wstring AdaptiveActionResultJson(const AdaptiveActionResult& result);

class AdaptiveInteractionLoop {
public:
    AdaptiveObservedState ObserveCurrentState(const AdaptiveTargetSpec& targetSpec);
    AdaptiveLocateResult LocateTarget(const AdaptiveTargetSpec& targetSpec);
    bool ValidateCandidate(const AdaptiveTargetSpec& targetSpec, AdaptiveTargetCandidate& candidate, const AdaptiveObservedState& state) const;
    ClickResult MoveToTarget(const AdaptiveTargetCandidate& candidate);
    bool VerifyCursorInsideTarget(const AdaptiveTargetCandidate& candidate, int& cursorX, int& cursorY, int& distanceToCenterPx) const;
    AdaptiveActionResult ExecuteAction(const AdaptiveActionSpec& actionSpec);
    bool VerifyAfterAction(const AdaptiveActionSpec& actionSpec, AdaptiveActionResult& actionResult);
    AdaptiveActionResult ReobserveAndRetry(const AdaptiveActionSpec& actionSpec, const AdaptiveActionResult& firstFailure);
    AdaptiveActionResult StopWithFailure(const AdaptiveActionSpec& actionSpec, const std::wstring& code, const std::wstring& message);
};

AdaptiveLocateResult AdaptiveLocateFromCandidates(
    const AdaptiveTargetSpec& spec,
    const AdaptiveObservedState& state,
    const std::vector<AdaptiveTargetCandidate>& candidates,
    int attemptCount);

int CommandAdaptiveLocate(int argc, wchar_t** argv);
int CommandAdaptiveClick(int argc, wchar_t** argv);
int CommandAdaptiveDoubleClick(int argc, wchar_t** argv);
int CommandAdaptiveType(int argc, wchar_t** argv);
int CommandAdaptiveRunStep(int argc, wchar_t** argv);
