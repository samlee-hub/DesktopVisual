#pragma once

#include <string>

struct PyCharmVisibleWorkflowOptions {
    bool dryRun = false;
    bool performanceAcceptance = false;
    std::wstring projectDir;
    std::wstring targetTitle;
    std::wstring targetProcess;
    int targetTotalMs = 120000;
    int maxTotalMs = 180000;
};

struct PyCharmVisibleWorkflowResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool realWorkflowExecuted = false;
    bool usesGlobalDpiAwareFrame = true;
    bool usesTargetWindowLock = true;
    bool usesCoordinateMapper = true;
    bool usesForegroundPreempt = true;
    bool usesVisibleTextInputPolicy = true;
    bool usesDeterministicActionBatch = true;
    bool usesVisibleUiVerificationPolicy = true;
    bool pycharmOpenedByDesktopIconOrTaskbar = false;
    bool backendLaunchUsed = false;
    bool launchAppPathUsed = false;
    bool desktopOrTaskbarIconClicked = false;
    bool visibleSwitchOrLaunchAttempted = false;
    std::wstring inputMethod = L"code_editor_keyboard";
    bool firstPassMultilineCorrect = false;
    bool codeCollapsedToSingleLine = false;
    bool selfselfAutocompleteArtifact = false;
    bool clipboardUsed = false;
    bool backendFileWriteUsed = false;
    bool finalEvidenceGlobalDpiAware = false;
    bool globalDpiAwareFinalScreenshot = false;
    bool outputVerified = false;
    int targetMotionFrameRateHz = 165;
    double motionActualFrameRateHz = 0.0;
    double averageClickLatencyMs = 0.0;
    bool operationIntervalBudgetPass = false;
    bool anyOperationIntervalOver5s = false;
    bool fixedSleepPrimaryWaitDetected = false;
    bool performanceAcceptance = false;
    long long optimizedTotalTaskTimeMs = 0;
    int operationGapGt5sCount = 0;
    int silentGapGt5sCount = 0;
    long long fixedSleepTotalMs = 0;
    std::wstring performanceGrade;
    bool visibleFirstPreserved = false;
    bool globalFinalScreenshot = false;
    int mouseMotionRequestedHz = 165;
    double mouseMotionMeasuredAvgHz = 0.0;
    std::wstring result = L"BLOCKED";
};

PyCharmVisibleWorkflowResult RunPyCharmVisibleWorkflow(const PyCharmVisibleWorkflowOptions& options);
std::wstring PyCharmVisibleWorkflowJson(const PyCharmVisibleWorkflowResult& result);
