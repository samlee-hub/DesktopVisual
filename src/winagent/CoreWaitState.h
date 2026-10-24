#pragma once

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

struct CoreWaitStateOptions {
    std::wstring waitSite;
    std::wstring waitReason;
    int waitBudgetMs = 0;
    int waitPollIntervalMs = 40;
    int waitReplacedFromSleepMs = 0;
    bool record = true;
    std::wstring workflowName;
    std::wstring workflowCategory;
    std::wstring waitStatePredicate;
    bool workflowWait = false;
};

struct CoreWaitStateResult {
    std::wstring waitSite;
    std::wstring waitReason;
    std::wstring workflowName;
    std::wstring workflowCategory;
    std::wstring waitStatePredicate;
    int waitBudgetMs = 0;
    int waitPollIntervalMs = 40;
    long long waitActualMs = 0;
    std::wstring waitExitReason;
    bool stateReady = false;
    bool timeout = false;
    bool skipped = false;
    bool failed = false;
    int waitReplacedFromSleepMs = 0;
    long long stateWaitSavedMs = 0;
    std::wstring waitNotReplacedReason;
    bool workflowWait = false;
};

struct CoreWaitStateSummary {
    long long fixedSleepWaitMs = 0;
    long long stateWaitTotalMs = 0;
    long long stateWaitSavedMs = 0;
    int waitTimeoutCount = 0;
    int waitNotReplacedCount = 0;
    std::vector<std::wstring> waitNotReplacedReasons;
};

struct WorkflowWaitStateSummary {
    long long workflowWaitTotalMs = 0;
    long long workflowWaitSavedMs = 0;
    int workflowWaitTimeoutCount = 0;
    int workflowWaitNotReplacedCount = 0;
    std::vector<std::wstring> workflowWaitSites;
    std::vector<std::wstring> workflowWaitReplacedFromSleepMs;
    std::vector<std::wstring> workflowWaitExitReasons;
    std::vector<std::wstring> workflowWaitNotReplacedReasons;
    long long explorerWaitTotalMs = 0;
    long long explorerWaitSavedMs = 0;
    long long browserWaitTotalMs = 0;
    long long browserWaitSavedMs = 0;
    long long codeWorkflowWaitTotalMs = 0;
    long long codeWorkflowWaitSavedMs = 0;
};

CoreWaitStateResult WaitForCoreState(
    const CoreWaitStateOptions& options,
    const std::function<bool()>& stateReady);

CoreWaitStateResult WaitForWorkflowState(
    const std::wstring& workflowName,
    const std::wstring& workflowCategory,
    const CoreWaitStateOptions& options,
    const std::function<bool()>& stateReady);

CoreWaitStateResult RecordCoreWaitNotReplaced(
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int fixedSleepMs,
    const std::wstring& waitNotReplacedReason);

CoreWaitStateResult RecordWorkflowWaitNotReplaced(
    const std::wstring& workflowName,
    const std::wstring& workflowCategory,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int fixedSleepMs,
    const std::wstring& waitNotReplacedReason);

CoreWaitStateResult WaitUntilTargetWindowForeground(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilFocusStable(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilWindowResponsive(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilForegroundSettled(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilWindowStillValid(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilNoModalTransition(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilFrameOrFocusStable(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilContextStable(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs = 0);

CoreWaitStateResult WaitUntilCaretOrBufferStable(
    const CoreWaitStateOptions& options,
    const std::function<bool()>& stateReady);

CoreWaitStateSummary BuildCoreWaitStateSummary(const std::vector<CoreWaitStateResult>& waits);
WorkflowWaitStateSummary BuildWorkflowWaitStateSummary(const std::vector<CoreWaitStateResult>& waits);

std::wstring CoreWaitStateResultJson(const CoreWaitStateResult& result);
std::wstring CoreWaitStateArrayJson(const std::vector<CoreWaitStateResult>& waits);
std::wstring CoreWaitStateSummaryJson(const CoreWaitStateSummary& summary);
std::wstring WorkflowWaitStateSummaryJson(const WorkflowWaitStateSummary& summary);

std::vector<CoreWaitStateResult> SnapshotCoreWaitStateRecords();
void ClearCoreWaitStateRecords();
