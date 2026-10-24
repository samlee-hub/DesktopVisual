#include "CoreWaitState.h"

#include "SimpleJson.h"

#include <algorithm>
#include <mutex>
#include <sstream>

namespace {

std::mutex g_coreWaitStateMutex;
std::vector<CoreWaitStateResult> g_coreWaitStateRecords;

int NormalizePollIntervalMs(int value) {
    if (value <= 0) return 40;
    if (value < 30) return 30;
    if (value > 50) return 50;
    return value;
}

void RecordResult(const CoreWaitStateResult& result, bool enabled) {
    if (!enabled) return;
    std::lock_guard<std::mutex> lock(g_coreWaitStateMutex);
    g_coreWaitStateRecords.push_back(result);
}

bool WindowVisible(HWND hwnd) {
    return hwnd && IsWindow(hwnd) && IsWindowVisible(hwnd) && !IsIconic(hwnd);
}

bool WindowResponsive(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    DWORD_PTR unused = 0;
    LRESULT response = SendMessageTimeoutW(
        hwnd,
        WM_NULL,
        0,
        0,
        SMTO_ABORTIFHUNG,
        20,
        &unused);
    return response != 0;
}

bool ForegroundStableFor(HWND hwnd, int& readyCount) {
    if (!hwnd || !IsWindow(hwnd) || GetForegroundWindow() != hwnd) {
        readyCount = 0;
        return false;
    }
    ++readyCount;
    return readyCount >= 2;
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& value) {
    if (value.empty()) return;
    if (std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

void AddCategoryTotals(
    WorkflowWaitStateSummary& summary,
    const std::wstring& category,
    long long waitActualMs,
    long long waitSavedMs) {
    if (category == L"explorer") {
        summary.explorerWaitTotalMs += waitActualMs;
        summary.explorerWaitSavedMs += waitSavedMs;
    } else if (category == L"browser") {
        summary.browserWaitTotalMs += waitActualMs;
        summary.browserWaitSavedMs += waitSavedMs;
    } else if (category == L"code" || category == L"ide" || category == L"code_ide") {
        summary.codeWorkflowWaitTotalMs += waitActualMs;
        summary.codeWorkflowWaitSavedMs += waitSavedMs;
    }
}

}  // namespace

CoreWaitStateResult WaitForCoreState(
    const CoreWaitStateOptions& options,
    const std::function<bool()>& stateReady) {
    CoreWaitStateResult result;
    result.waitSite = options.waitSite;
    result.waitReason = options.waitReason;
    result.workflowName = options.workflowName;
    result.workflowCategory = options.workflowCategory;
    result.waitStatePredicate = options.waitStatePredicate;
    result.waitBudgetMs = (std::max)(0, options.waitBudgetMs);
    result.waitPollIntervalMs = NormalizePollIntervalMs(options.waitPollIntervalMs);
    result.waitReplacedFromSleepMs = options.waitReplacedFromSleepMs;
    result.workflowWait = options.workflowWait;

    ULONGLONG start = GetTickCount64();
    if (!stateReady) {
        result.failed = true;
        result.waitExitReason = L"failed";
        result.waitActualMs = 0;
        RecordResult(result, options.record);
        return result;
    }

    if (result.waitBudgetMs <= 0) {
        result.skipped = true;
        result.waitExitReason = L"skipped";
        result.waitActualMs = 0;
        RecordResult(result, options.record);
        return result;
    }

    try {
        if (stateReady()) {
            result.stateReady = true;
            result.waitExitReason = L"state_ready";
            result.waitActualMs = static_cast<long long>(GetTickCount64() - start);
            result.stateWaitSavedMs = (std::max)(0LL, static_cast<long long>(result.waitReplacedFromSleepMs) - result.waitActualMs);
            RecordResult(result, options.record);
            return result;
        }

        while (static_cast<long long>(GetTickCount64() - start) < result.waitBudgetMs) {
            long long elapsed = static_cast<long long>(GetTickCount64() - start);
            int remainingMs = result.waitBudgetMs - static_cast<int>(elapsed);
            if (remainingMs <= 0) break;
            Sleep(static_cast<DWORD>((std::min)(result.waitPollIntervalMs, remainingMs)));
            if (stateReady()) {
                result.stateReady = true;
                result.waitExitReason = L"state_ready";
                result.waitActualMs = static_cast<long long>(GetTickCount64() - start);
                result.stateWaitSavedMs = (std::max)(0LL, static_cast<long long>(result.waitReplacedFromSleepMs) - result.waitActualMs);
                RecordResult(result, options.record);
                return result;
            }
        }
    } catch (...) {
        result.failed = true;
        result.waitExitReason = L"failed";
        result.waitActualMs = static_cast<long long>(GetTickCount64() - start);
        RecordResult(result, options.record);
        return result;
    }

    result.timeout = true;
    result.waitExitReason = L"timeout";
    result.waitActualMs = static_cast<long long>(GetTickCount64() - start);
    RecordResult(result, options.record);
    return result;
}

CoreWaitStateResult WaitForWorkflowState(
    const std::wstring& workflowName,
    const std::wstring& workflowCategory,
    const CoreWaitStateOptions& options,
    const std::function<bool()>& stateReady) {
    CoreWaitStateOptions workflowOptions = options;
    workflowOptions.workflowName = workflowName;
    workflowOptions.workflowCategory = workflowCategory;
    workflowOptions.workflowWait = true;
    if (workflowOptions.waitStatePredicate.empty()) {
        workflowOptions.waitStatePredicate = workflowOptions.waitReason;
    }
    return WaitForCoreState(workflowOptions, stateReady);
}

CoreWaitStateResult RecordCoreWaitNotReplaced(
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int fixedSleepMs,
    const std::wstring& waitNotReplacedReason) {
    CoreWaitStateResult result;
    result.waitSite = waitSite;
    result.waitReason = waitReason;
    result.waitBudgetMs = (std::max)(0, fixedSleepMs);
    result.waitPollIntervalMs = 0;
    result.waitActualMs = (std::max)(0, fixedSleepMs);
    result.waitExitReason = L"not_state_replaced";
    result.waitReplacedFromSleepMs = 0;
    result.waitNotReplacedReason = waitNotReplacedReason;
    RecordResult(result, true);
    return result;
}

CoreWaitStateResult RecordWorkflowWaitNotReplaced(
    const std::wstring& workflowName,
    const std::wstring& workflowCategory,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int fixedSleepMs,
    const std::wstring& waitNotReplacedReason) {
    CoreWaitStateResult result;
    result.workflowName = workflowName;
    result.workflowCategory = workflowCategory;
    result.waitSite = waitSite;
    result.waitReason = waitReason;
    result.waitBudgetMs = (std::max)(0, fixedSleepMs);
    result.waitPollIntervalMs = 0;
    result.waitActualMs = (std::max)(0, fixedSleepMs);
    result.waitExitReason = L"not_state_replaced";
    result.waitReplacedFromSleepMs = 0;
    result.waitStatePredicate = L"not_state_replaced";
    result.waitNotReplacedReason = waitNotReplacedReason;
    result.workflowWait = true;
    RecordResult(result, true);
    return result;
}

CoreWaitStateResult WaitUntilTargetWindowForeground(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    CoreWaitStateOptions options;
    options.waitSite = waitSite;
    options.waitReason = waitReason;
    options.waitBudgetMs = waitBudgetMs;
    options.waitPollIntervalMs = 30;
    options.waitReplacedFromSleepMs = waitReplacedFromSleepMs;
    return WaitForCoreState(options, [hwnd]() {
        return hwnd && IsWindow(hwnd) && GetForegroundWindow() == hwnd;
    });
}

CoreWaitStateResult WaitUntilFocusStable(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    CoreWaitStateOptions options;
    options.waitSite = waitSite;
    options.waitReason = waitReason;
    options.waitBudgetMs = waitBudgetMs;
    options.waitPollIntervalMs = 40;
    options.waitReplacedFromSleepMs = waitReplacedFromSleepMs;
    int readyCount = 0;
    return WaitForCoreState(options, [hwnd, &readyCount]() {
        return ForegroundStableFor(hwnd, readyCount);
    });
}

CoreWaitStateResult WaitUntilWindowResponsive(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    CoreWaitStateOptions options;
    options.waitSite = waitSite;
    options.waitReason = waitReason;
    options.waitBudgetMs = waitBudgetMs;
    options.waitPollIntervalMs = 40;
    options.waitReplacedFromSleepMs = waitReplacedFromSleepMs;
    return WaitForCoreState(options, [hwnd]() {
        return WindowVisible(hwnd) && WindowResponsive(hwnd);
    });
}

CoreWaitStateResult WaitUntilForegroundSettled(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    CoreWaitStateOptions options;
    options.waitSite = waitSite;
    options.waitReason = waitReason;
    options.waitBudgetMs = waitBudgetMs;
    options.waitPollIntervalMs = 40;
    options.waitReplacedFromSleepMs = waitReplacedFromSleepMs;
    int readyCount = 0;
    return WaitForCoreState(options, [hwnd, &readyCount]() {
        return WindowVisible(hwnd) && WindowResponsive(hwnd) && ForegroundStableFor(hwnd, readyCount);
    });
}

CoreWaitStateResult WaitUntilWindowStillValid(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    CoreWaitStateOptions options;
    options.waitSite = waitSite;
    options.waitReason = waitReason;
    options.waitBudgetMs = waitBudgetMs;
    options.waitPollIntervalMs = 40;
    options.waitReplacedFromSleepMs = waitReplacedFromSleepMs;
    return WaitForCoreState(options, [hwnd]() {
        return WindowVisible(hwnd);
    });
}

CoreWaitStateResult WaitUntilNoModalTransition(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    return WaitUntilWindowResponsive(hwnd, waitBudgetMs, waitSite, waitReason, waitReplacedFromSleepMs);
}

CoreWaitStateResult WaitUntilFrameOrFocusStable(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    return WaitUntilForegroundSettled(hwnd, waitBudgetMs, waitSite, waitReason, waitReplacedFromSleepMs);
}

CoreWaitStateResult WaitUntilContextStable(
    HWND hwnd,
    int waitBudgetMs,
    const std::wstring& waitSite,
    const std::wstring& waitReason,
    int waitReplacedFromSleepMs) {
    return WaitUntilFrameOrFocusStable(hwnd, waitBudgetMs, waitSite, waitReason, waitReplacedFromSleepMs);
}

CoreWaitStateResult WaitUntilCaretOrBufferStable(
    const CoreWaitStateOptions& options,
    const std::function<bool()>& stateReady) {
    return WaitForCoreState(options, stateReady);
}

CoreWaitStateSummary BuildCoreWaitStateSummary(const std::vector<CoreWaitStateResult>& waits) {
    CoreWaitStateSummary summary;
    for (const auto& wait : waits) {
        if (wait.workflowWait) continue;
        bool notReplaced = wait.waitExitReason == L"not_state_replaced";
        if (notReplaced) {
            summary.fixedSleepWaitMs += wait.waitActualMs;
            ++summary.waitNotReplacedCount;
            if (!wait.waitNotReplacedReason.empty() &&
                std::find(summary.waitNotReplacedReasons.begin(), summary.waitNotReplacedReasons.end(), wait.waitNotReplacedReason) == summary.waitNotReplacedReasons.end()) {
                summary.waitNotReplacedReasons.push_back(wait.waitNotReplacedReason);
            }
            continue;
        }

        summary.stateWaitTotalMs += wait.waitActualMs;
        summary.stateWaitSavedMs += wait.stateWaitSavedMs;
        if (wait.timeout) ++summary.waitTimeoutCount;
    }
    return summary;
}

WorkflowWaitStateSummary BuildWorkflowWaitStateSummary(const std::vector<CoreWaitStateResult>& waits) {
    WorkflowWaitStateSummary summary;
    for (const auto& wait : waits) {
        if (!wait.workflowWait) continue;

        bool notReplaced = wait.waitExitReason == L"not_state_replaced";
        AddUnique(summary.workflowWaitSites, wait.waitSite);
        AddUnique(summary.workflowWaitExitReasons, wait.waitExitReason);

        if (notReplaced) {
            ++summary.workflowWaitNotReplacedCount;
            AddUnique(summary.workflowWaitNotReplacedReasons, wait.waitNotReplacedReason);
            continue;
        }

        summary.workflowWaitTotalMs += wait.waitActualMs;
        summary.workflowWaitSavedMs += wait.stateWaitSavedMs;
        AddCategoryTotals(summary, wait.workflowCategory, wait.waitActualMs, wait.stateWaitSavedMs);
        if (wait.waitReplacedFromSleepMs > 0) {
            AddUnique(
                summary.workflowWaitReplacedFromSleepMs,
                wait.waitSite + L":" + std::to_wstring(wait.waitReplacedFromSleepMs));
        }
        if (wait.timeout) ++summary.workflowWaitTimeoutCount;
    }
    return summary;
}

std::wstring CoreWaitStateResultJson(const CoreWaitStateResult& result) {
    std::wstringstream json;
    json << L"{\"wait_site\":" << simplejson::Quote(result.waitSite)
         << L",\"wait_reason\":" << simplejson::Quote(result.waitReason)
         << L",\"workflow_name\":" << simplejson::Quote(result.workflowName)
         << L",\"workflow_category\":" << simplejson::Quote(result.workflowCategory)
         << L",\"wait_state_predicate\":" << simplejson::Quote(result.waitStatePredicate)
         << L",\"wait_budget_ms\":" << result.waitBudgetMs
         << L",\"wait_poll_interval_ms\":" << result.waitPollIntervalMs
         << L",\"wait_actual_ms\":" << result.waitActualMs
         << L",\"wait_exit_reason\":" << simplejson::Quote(result.waitExitReason)
         << L",\"state_ready\":" << BoolJson(result.stateReady)
         << L",\"wait_state_ready\":" << BoolJson(result.stateReady)
         << L",\"timeout\":" << BoolJson(result.timeout)
         << L",\"skipped\":" << BoolJson(result.skipped)
         << L",\"failed\":" << BoolJson(result.failed)
         << L",\"wait_replaced_from_sleep_ms\":" << result.waitReplacedFromSleepMs
         << L",\"state_wait_saved_ms\":" << result.stateWaitSavedMs
         << L",\"wait_not_replaced_reason\":" << simplejson::Quote(result.waitNotReplacedReason)
         << L",\"workflow_wait\":" << BoolJson(result.workflowWait)
         << L"}";
    return json.str();
}

std::wstring CoreWaitStateArrayJson(const std::vector<CoreWaitStateResult>& waits) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < waits.size(); ++i) {
        if (i) json << L",";
        json << CoreWaitStateResultJson(waits[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring CoreWaitStateSummaryJson(const CoreWaitStateSummary& summary) {
    std::wstringstream json;
    json << L"{\"fixed_sleep_wait_ms\":" << summary.fixedSleepWaitMs
         << L",\"state_wait_total_ms\":" << summary.stateWaitTotalMs
         << L",\"state_wait_saved_ms\":" << summary.stateWaitSavedMs
         << L",\"wait_timeout_count\":" << summary.waitTimeoutCount
         << L",\"wait_not_replaced_count\":" << summary.waitNotReplacedCount
         << L",\"wait_not_replaced_reasons\":" << StringArrayJson(summary.waitNotReplacedReasons)
         << L"}";
    return json.str();
}

std::wstring WorkflowWaitStateSummaryJson(const WorkflowWaitStateSummary& summary) {
    std::wstringstream json;
    json << L"{\"workflow_wait_total_ms\":" << summary.workflowWaitTotalMs
         << L",\"workflow_wait_saved_ms\":" << summary.workflowWaitSavedMs
         << L",\"workflow_wait_timeout_count\":" << summary.workflowWaitTimeoutCount
         << L",\"workflow_wait_not_replaced_count\":" << summary.workflowWaitNotReplacedCount
         << L",\"workflow_wait_sites\":" << StringArrayJson(summary.workflowWaitSites)
         << L",\"workflow_wait_replaced_from_sleep_ms\":" << StringArrayJson(summary.workflowWaitReplacedFromSleepMs)
         << L",\"workflow_wait_exit_reasons\":" << StringArrayJson(summary.workflowWaitExitReasons)
         << L",\"workflow_wait_not_replaced_reasons\":" << StringArrayJson(summary.workflowWaitNotReplacedReasons)
         << L",\"explorer_wait_total_ms\":" << summary.explorerWaitTotalMs
         << L",\"explorer_wait_saved_ms\":" << summary.explorerWaitSavedMs
         << L",\"browser_wait_total_ms\":" << summary.browserWaitTotalMs
         << L",\"browser_wait_saved_ms\":" << summary.browserWaitSavedMs
         << L",\"code_workflow_wait_total_ms\":" << summary.codeWorkflowWaitTotalMs
         << L",\"code_workflow_wait_saved_ms\":" << summary.codeWorkflowWaitSavedMs
         << L"}";
    return json.str();
}

std::vector<CoreWaitStateResult> SnapshotCoreWaitStateRecords() {
    std::lock_guard<std::mutex> lock(g_coreWaitStateMutex);
    return g_coreWaitStateRecords;
}

void ClearCoreWaitStateRecords() {
    std::lock_guard<std::mutex> lock(g_coreWaitStateMutex);
    g_coreWaitStateRecords.clear();
}
