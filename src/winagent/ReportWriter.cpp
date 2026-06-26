#include "ReportWriter.h"

#include <windows.h>

#include <cstdio>

namespace {

std::wstring EscapeMarkdownCell(std::wstring value) {
    for (wchar_t& ch : value) {
        if (ch == L'|' || ch == L'\r' || ch == L'\n') {
            ch = L' ';
        }
    }
    return value;
}

void WriteLine(FILE* file, const std::wstring& line) {
    fwprintf(file, L"%ls\n", line.c_str());
}

}  // namespace

std::wstring CurrentTimestamp() {
    SYSTEMTIME time;
    GetLocalTime(&time);
    wchar_t buffer[32] = {};
    swprintf_s(
        buffer,
        L"%04u-%02u-%02u %02u:%02u:%02u",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond);
    return buffer;
}

bool WriteMarkdownReport(const std::wstring& reportPath, const CaseReport& report, std::wstring& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, reportPath.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not open report file.";
        return false;
    }

    WriteLine(file, L"# WinDesktopAgent Case Report");
    WriteLine(file, L"");
    WriteLine(file, L"- Case name: `" + report.caseName + L"`");
    WriteLine(file, L"- Case file: `" + report.caseFile + L"`");
    WriteLine(file, L"- Case version: " + std::to_wstring(report.caseVersion));
    WriteLine(file, L"- Target title: `" + report.targetTitle + L"`");
    WriteLine(file, L"- Result: " + std::wstring(report.ok ? L"SUCCESS" : L"FAILED"));
    WriteLine(file, L"- Start time: " + report.startTime);
    WriteLine(file, L"- End time: " + report.endTime);
    WriteLine(file, L"- Total duration ms: " + std::to_wstring(report.totalDurationMs));
    WriteLine(file, L"- Step count: " + std::to_wstring(report.stepCount));
    WriteLine(file, L"- Passed step count: " + std::to_wstring(report.passedStepCount));
    WriteLine(file, L"- Failed step index: " + std::to_wstring(report.failedStepIndex));
    WriteLine(file, L"- Failure error_code: `" + report.failureErrorCode + L"`");
    WriteLine(file, L"- Failure message: " + report.failureMessage);
    WriteLine(file, L"");

    WriteLine(file, L"## Artifacts");
    WriteLine(file, L"");
    for (const auto& path : report.screenshotPaths) {
        WriteLine(file, L"- `" + path + L"`");
    }
    WriteLine(file, L"");

    WriteLine(file, L"## Steps");
    WriteLine(file, L"");
    WriteLine(file, L"| index | action | params | start_time | end_time | duration_ms | result | error_code | message | json_output |");
    WriteLine(file, L"|---|---|---|---|---|---|---|---|---|---|");
    for (const auto& step : report.steps) {
        fwprintf(
            file,
            L"| %d | %ls | %ls | %ls | %ls | %lld | %ls | %ls | %ls | %ls |\n",
            step.index,
            EscapeMarkdownCell(step.action).c_str(),
            EscapeMarkdownCell(step.parameters).c_str(),
            EscapeMarkdownCell(step.startedAt).c_str(),
            EscapeMarkdownCell(step.endedAt).c_str(),
            step.durationMs,
            step.ok ? L"ok" : L"failed",
            EscapeMarkdownCell(step.errorCode).c_str(),
            EscapeMarkdownCell(step.message).c_str(),
            EscapeMarkdownCell(step.jsonOutputSummary).c_str());
    }
    WriteLine(file, L"");

    if (!report.readContents.empty()) {
        WriteLine(file, L"## Read State");
        WriteLine(file, L"");
        for (const auto& content : report.readContents) {
            WriteLine(file, L"```text");
            WriteLine(file, content);
            WriteLine(file, L"```");
            WriteLine(file, L"");
        }
    }

    if (!report.focusAndSafety.empty()) {
        WriteLine(file, L"## Focus And Safety");
        WriteLine(file, L"");
        for (const auto& item : report.focusAndSafety) {
            WriteLine(file, L"```json");
            WriteLine(file, item);
            WriteLine(file, L"```");
            WriteLine(file, L"");
        }
    }

    if (!report.observations.empty()) {
        WriteLine(file, L"## Observations");
        WriteLine(file, L"");
        WriteLine(file, L"- observe count: " + std::to_wstring(report.observations.size()));
        WriteLine(file, L"");
        WriteLine(file, L"| index | screenshot | uia_element_count | focus_verified | output_json |");
        WriteLine(file, L"|---|---|---|---|---|");
        for (const auto& observation : report.observations) {
            fwprintf(
                file,
                L"| %d | %ls | %d | %ls | %ls |\n",
                observation.index,
                EscapeMarkdownCell(observation.screenshotPath).c_str(),
                observation.uiaElementCount,
                observation.focusVerified ? L"true" : L"false",
                EscapeMarkdownCell(observation.outputPath).c_str());
        }
        WriteLine(file, L"");
    }

    if (!report.observationBefore.empty()) {
        WriteLine(file, L"## Observation Before");
        WriteLine(file, L"");
        WriteLine(file, L"```json");
        WriteLine(file, report.observationBefore);
        WriteLine(file, L"```");
        WriteLine(file, L"");
    }

    if (!report.observationAfter.empty()) {
        WriteLine(file, L"## Observation After");
        WriteLine(file, L"");
        WriteLine(file, L"```json");
        WriteLine(file, report.observationAfter);
        WriteLine(file, L"```");
        WriteLine(file, L"");
    }

    if (!report.variables.empty()) {
        WriteLine(file, L"## Variables");
        WriteLine(file, L"");
        WriteLine(file, L"| name | value |");
        WriteLine(file, L"|---|---|");
        for (const auto& var : report.variables) {
            fwprintf(
                file,
                L"| %ls | %ls |\n",
                EscapeMarkdownCell(var.first).c_str(),
                EscapeMarkdownCell(var.second).c_str());
        }
        WriteLine(file, L"");
    }

    if (!report.waitResults.empty()) {
        WriteLine(file, L"## Wait Results");
        WriteLine(file, L"");
        WriteLine(file, L"| step | condition | selector/path | text | timeout_ms | elapsed_ms | result |");
        WriteLine(file, L"|---|---|---|---|---|---|---|");
        for (const auto& wr : report.waitResults) {
            fwprintf(
                file,
                L"| %d | %ls | %ls | %ls | %d | %lld | %ls |\n",
                wr.stepIndex,
                EscapeMarkdownCell(wr.conditionType).c_str(),
                EscapeMarkdownCell(wr.selector.empty() ? wr.path : wr.selector).c_str(),
                EscapeMarkdownCell(wr.text).c_str(),
                wr.timeoutMs,
                wr.elapsedMs,
                wr.ok ? L"ok" : L"timeout");
        }
        WriteLine(file, L"");
    }

    if (!report.expectResults.empty()) {
        WriteLine(file, L"## Expect Results");
        WriteLine(file, L"");
        WriteLine(file, L"| step | type | selector/path | text | result | detail |");
        WriteLine(file, L"|---|---|---|---|---|---|");
        for (const auto& er : report.expectResults) {
            fwprintf(
                file,
                L"| %d | %ls | %ls | %ls | %ls | %ls |\n",
                er.stepIndex,
                EscapeMarkdownCell(er.type).c_str(),
                EscapeMarkdownCell(er.selector.empty() ? er.path : er.selector).c_str(),
                EscapeMarkdownCell(er.text).c_str(),
                er.ok ? L"ok" : L"failed",
                EscapeMarkdownCell(er.detail).c_str());
        }
        WriteLine(file, L"");
    }

    fclose(file);
    return true;
}
