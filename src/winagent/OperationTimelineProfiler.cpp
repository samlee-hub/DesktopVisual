#include "OperationTimelineProfiler.h"

#include "SimpleJson.h"

#include <sstream>

namespace {

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << simplejson::Quote(values[i]);
    }
    json << L"]";
    return json.str();
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring CategoryTotalsJson(const std::map<std::wstring, long long>& totals) {
    std::wstringstream json;
    json << L"{";
    bool first = true;
    for (const auto& item : totals) {
        if (!first) json << L",";
        first = false;
        json << simplejson::Quote(item.first) << L":" << item.second;
    }
    json << L"}";
    return json.str();
}

}  // namespace

std::vector<std::wstring> OperationTimelineRequiredFields() {
    return {
        L"operation_id",
        L"parent_task_id",
        L"operation_type",
        L"command",
        L"start_time_utc",
        L"end_time_utc",
        L"wall_clock_ms",
        L"runtime_duration_ms",
        L"orchestration_overhead_ms",
        L"stage",
        L"attempt_index",
        L"attempt_mode",
        L"target_title",
        L"target_process",
        L"foreground_before",
        L"foreground_after",
        L"used_global_screenshot",
        L"used_target_lock",
        L"used_coordinate_mapper",
        L"used_foreground_preempt",
        L"used_real_keyboard_input",
        L"used_clipboard",
        L"used_backend",
        L"used_shortcut",
        L"fixed_sleep_ms",
        L"sleep_ms",
        L"wait_condition",
        L"wait_condition_ms",
        L"manual_view_image_ms",
        L"codex_thinking_gap_ms",
        L"process_startup_overhead_ms",
        L"result",
        L"error_code",
        L"evidence_ref",
        L"external_orchestration_delay",
        L"fixed_sleep_candidate"
    };
}

void FinalizeOperationTimelineEntry(OperationTimelineEntry& entry) {
    entry.orchestrationOverheadMs = entry.wallClockMs - entry.runtimeDurationMs;
    if (entry.orchestrationOverheadMs < 0) {
        entry.orchestrationOverheadMs = 0;
    }
}

bool IsOperationTimelineExternalOrchestrationDelay(const OperationTimelineEntry& entry) {
    return entry.runtimeDurationMs < 500 && entry.wallClockMs > 5000;
}

bool IsOperationTimelineFixedSleepCandidate(const OperationTimelineEntry& entry) {
    return entry.fixedSleepMs > 1000;
}

std::wstring OperationTimelineEntryJson(const OperationTimelineEntry& entry) {
    std::wstringstream json;
    json << L"{"
         << L"\"operation_id\":" << simplejson::Quote(entry.operationId)
         << L",\"parent_task_id\":" << simplejson::Quote(entry.parentTaskId)
         << L",\"operation_type\":" << simplejson::Quote(entry.operationType)
         << L",\"command\":" << simplejson::Quote(entry.command)
         << L",\"start_time_utc\":" << simplejson::Quote(entry.startTimeUtc)
         << L",\"end_time_utc\":" << simplejson::Quote(entry.endTimeUtc)
         << L",\"wall_clock_ms\":" << entry.wallClockMs
         << L",\"runtime_duration_ms\":" << entry.runtimeDurationMs
         << L",\"orchestration_overhead_ms\":" << entry.orchestrationOverheadMs
         << L",\"stage\":" << simplejson::Quote(entry.stage)
         << L",\"attempt_index\":" << entry.attemptIndex
         << L",\"attempt_mode\":" << simplejson::Quote(entry.attemptMode)
         << L",\"target_title\":" << simplejson::Quote(entry.targetTitle)
         << L",\"target_process\":" << simplejson::Quote(entry.targetProcess)
         << L",\"foreground_before\":" << simplejson::Quote(entry.foregroundBefore)
         << L",\"foreground_after\":" << simplejson::Quote(entry.foregroundAfter)
         << L",\"used_global_screenshot\":" << BoolJson(entry.usedGlobalScreenshot)
         << L",\"used_target_lock\":" << BoolJson(entry.usedTargetLock)
         << L",\"used_coordinate_mapper\":" << BoolJson(entry.usedCoordinateMapper)
         << L",\"used_foreground_preempt\":" << BoolJson(entry.usedForegroundPreempt)
         << L",\"used_real_keyboard_input\":" << BoolJson(entry.usedRealKeyboardInput)
         << L",\"used_clipboard\":" << BoolJson(entry.usedClipboard)
         << L",\"used_backend\":" << BoolJson(entry.usedBackend)
         << L",\"used_shortcut\":" << BoolJson(entry.usedShortcut)
         << L",\"fixed_sleep_ms\":" << entry.fixedSleepMs
         << L",\"sleep_ms\":" << entry.fixedSleepMs
         << L",\"wait_condition\":" << simplejson::Quote(entry.waitCondition)
         << L",\"wait_condition_ms\":" << entry.waitConditionMs
         << L",\"manual_view_image_ms\":" << entry.manualViewImageMs
         << L",\"codex_thinking_gap_ms\":" << entry.codexThinkingGapMs
         << L",\"process_startup_overhead_ms\":" << entry.processStartupOverheadMs
         << L",\"result\":" << simplejson::Quote(entry.result)
         << L",\"error_code\":" << simplejson::Quote(entry.errorCode)
         << L",\"evidence_ref\":" << simplejson::Quote(entry.evidenceRef)
         << L",\"external_orchestration_delay\":" << BoolJson(IsOperationTimelineExternalOrchestrationDelay(entry))
         << L",\"fixed_sleep_candidate\":" << BoolJson(IsOperationTimelineFixedSleepCandidate(entry))
         << L"}";
    return json.str();
}

std::wstring OperationTimelineProfilerSelftestDataJson() {
    OperationTimelineEntry sample;
    sample.operationId = L"op-selftest-001";
    sample.parentTaskId = L"timeline-selftest";
    sample.operationType = L"global_screenshot";
    sample.command = L"winagent.exe global-screenshot --out sample.png";
    sample.startTimeUtc = L"2026-06-19T00:00:00.0000000Z";
    sample.endTimeUtc = L"2026-06-19T00:00:05.2000000Z";
    sample.wallClockMs = 5200;
    sample.runtimeDurationMs = 400;
    sample.stage = L"selftest";
    sample.attemptIndex = 1;
    sample.attemptMode = L"visible";
    sample.targetTitle = L"Desktop";
    sample.targetProcess = L"explorer.exe";
    sample.usedGlobalScreenshot = true;
    sample.usedTargetLock = true;
    sample.usedCoordinateMapper = true;
    sample.usedForegroundPreempt = true;
    sample.fixedSleepMs = 1200;
    sample.waitCondition = L"window_visible";
    sample.waitConditionMs = 700;
    sample.processStartupOverheadMs = 300;
    sample.result = L"ok";
    sample.evidenceRef = L"sample.stdout.json";
    FinalizeOperationTimelineEntry(sample);

    std::map<std::wstring, long long> totals;
    totals[L"foreground_preempt_ms"] = 400;
    totals[L"global_screenshot_ms"] = 1500;
    totals[L"target_lock_ms"] = 200;
    totals[L"coordinate_mapping_ms"] = 100;
    totals[L"fixed_sleep_ms"] = sample.fixedSleepMs;
    totals[L"wait_condition_ms"] = sample.waitConditionMs;
    totals[L"process_spawn_ms"] = sample.processStartupOverheadMs;

    std::wstringstream data;
    data << L"{"
         << L"\"schema_version\":\"operation_timeline.v1\""
         << L",\"required_fields\":" << StringArrayJson(OperationTimelineRequiredFields())
         << L",\"sample\":" << OperationTimelineEntryJson(sample)
         << L",\"category_totals\":" << CategoryTotalsJson(totals)
         << L"}";
    return data.str();
}
