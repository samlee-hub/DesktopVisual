#include "FailureAttributionNormalizer.h"

#include "EvidenceFingerprint.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool Contains(const std::wstring& text, const std::wstring& needle) {
    return !needle.empty() && Lower(text).find(Lower(needle)) != std::wstring::npos;
}

bool AnyContains(const std::wstring& text, const std::vector<std::wstring>& needles) {
    for (const auto& needle : needles) {
        if (Contains(text, needle)) return true;
    }
    return false;
}

std::wstring JoinedSignals(const FailureAttributionNormalizationInput& input) {
    return input.workflowType + L"\n" +
        input.executionResult + L"\n" +
        input.failureType + L"\n" +
        input.failureCode + L"\n" +
        input.failureReason;
}

bool IsSuccessResult(const std::wstring& executionResult) {
    std::wstring lower = Lower(executionResult);
    return lower == L"success" || lower == L"passed" || lower == L"pass";
}

bool IsNoFailureSignal(const FailureAttributionNormalizationInput& input) {
    std::wstring code = Lower(input.failureCode);
    std::wstring type = Lower(input.failureType);
    return (code.empty() || code == L"none" || code == L"success" || code == L"ok") &&
        (type.empty() || type == L"none") &&
        IsSuccessResult(input.executionResult);
}

FailureAttributionNormalizationResult MakeResult(
    const std::wstring& category,
    const std::wstring& reason,
    const FailureAttributionNormalizationInput& input) {
    FailureAttributionNormalizationResult result;
    result.normalizedCategory = category;
    result.reason = reason;
    result.rawCompletedUnverified = AnyContains(JoinedSignals(input), {L"RAW_COMPLETED_UNVERIFIED", L"raw_completed_unverified"});
    result.successWithoutFailure = category == L"SUCCESS_NO_FAILURE";
    result.unknownMappedToSuccess = result.successWithoutFailure &&
        !IsNoFailureSignal(input);
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.10.0.failure_attribution_normalization\""
         << L",\"workflow_type\":" << simplejson::Quote(input.workflowType)
         << L",\"execution_result\":" << simplejson::Quote(input.executionResult)
         << L",\"failure_type\":" << simplejson::Quote(input.failureType)
         << L",\"failure_code\":" << simplejson::Quote(input.failureCode)
         << L",\"normalized_failure_category\":" << simplejson::Quote(result.normalizedCategory)
         << L",\"reason\":" << simplejson::Quote(result.reason)
         << L",\"raw_completed_unverified\":" << simplejson::Bool(result.rawCompletedUnverified)
         << L",\"unknown_mapped_to_success\":" << simplejson::Bool(result.unknownMappedToSuccess)
         << L",\"safe_for_success\":" << simplejson::Bool(result.successWithoutFailure && !result.rawCompletedUnverified && !result.unknownMappedToSuccess)
         << L",\"generates_execution_plan\":false"
         << L",\"runtime_execution_triggered\":false"
         << L"}";
    result.dataJson = json.str();
    return result;
}

}  // namespace

bool IsKnownNormalizedFailureCategory(const std::wstring& category) {
    static const std::vector<std::wstring> categories = {
        L"LOCATOR_FAILURE",
        L"CONTEXT_MISMATCH",
        L"RUNTIME_GUARD_STOP",
        L"CREDENTIAL_REQUIRED",
        L"ACTIVE_PROTECTION",
        L"STEP_VALIDATION_FAILED",
        L"EXECUTION_VERIFICATION_FAILED",
        L"EVIDENCE_MISSING",
        L"ENVIRONMENT_BLOCKED",
        L"UNKNOWN_FAILURE",
        L"SUCCESS_NO_FAILURE"
    };
    for (const auto& known : categories) {
        if (Lower(known) == Lower(category)) return true;
    }
    return false;
}

FailureAttributionNormalizationResult NormalizeFailureAttribution(
    const FailureAttributionNormalizationInput& input) {
    std::wstring text = JoinedSignals(input);
    std::wstring lowerType = Lower(input.failureType);
    std::wstring lowerResult = Lower(input.executionResult);

    if (IsNoFailureSignal(input)) {
        return MakeResult(L"SUCCESS_NO_FAILURE", L"Execution succeeded and no failure signal was present.", input);
    }
    if (lowerResult == L"raw_completed_unverified" || AnyContains(text, {L"RAW_COMPLETED_UNVERIFIED"})) {
        return MakeResult(L"EVIDENCE_MISSING", L"Raw completion without independent verification is evidence missing, not success.", input);
    }
    if (lowerType == L"locator_failure" || AnyContains(text, {
        L"FAIL_FIELD_NOT_FOUND",
        L"FIELD_NOT_FOUND",
        L"LOCATOR_NOT_FOUND",
        L"LOCATOR_NOT_UNIQUE",
        L"STOP_TARGET_NOT_UNIQUE",
        L"TARGET_NOT_UNIQUE",
        L"TARGET_NOT_VISIBLE",
        L"UIA_ELEMENT_NOT_FOUND",
        L"UIA_ELEMENT_NOT_UNIQUE",
        L"OCR_TEXT_NOT_FOUND",
        L"STOP_TARGET_OUTSIDE_VIEWPORT"
    })) {
        return MakeResult(L"LOCATOR_FAILURE", L"Target, field, or locator could not be resolved safely.", input);
    }
    if (lowerType == L"context_mismatch" || AnyContains(text, {
        L"STOP_WRONG_CONTEXT",
        L"EXPECTED_CONTEXT_FAILED",
        L"STOP_WRONG_PAGE",
        L"CONTEXT_MISMATCH",
        L"STOP_BROWSER_NAVIGATION_WRONG_PAGE"
    })) {
        return MakeResult(L"CONTEXT_MISMATCH", L"Observed context did not match the expected workflow context.", input);
    }
    if (lowerType == L"runtime_guard_stop" || AnyContains(text, {
        L"RUNTIME_GUARD_STOP",
        L"STOP_TARGET_STALE",
        L"STOP_FOREGROUND_CHANGED",
        L"WINDOW_FOCUS_FAILED"
    })) {
        return MakeResult(L"RUNTIME_GUARD_STOP", L"Runtime guard stopped unsafe continuation.", input);
    }
    if (lowerType == L"credential_required" || AnyContains(text, {
        L"STOP_CREDENTIAL_REQUIRED",
        L"CREDENTIAL_REQUIRED",
        L"PASSWORD_REQUIRED",
        L"VERIFICATION_CODE_REQUIRED"
    })) {
        return MakeResult(L"CREDENTIAL_REQUIRED", L"Credential or verification-code handoff was required.", input);
    }
    if (lowerType == L"active_protection" || AnyContains(text, {
        L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK",
        L"STOP_ACTIVE_PROTECTION",
        L"ACTIVE_PROTECTION",
        L"CAPTCHA",
        L"RECAPTCHA",
        L"HCAPTCHA",
        L"TURNSTILE",
        L"HUMAN VERIFICATION",
        L"BOT CHALLENGE",
        L"AUTOMATION DETECTED",
        L"ANTI_CHEAT"
    })) {
        return MakeResult(L"ACTIVE_PROTECTION", L"Active protection or automation-detection signal was present.", input);
    }
    if (lowerType == L"step_validation_failed" || AnyContains(text, {
        L"STEP_VALIDATION_FAILED",
        L"STEP_CONTRACT_SCHEMA_INVALID",
        L"COMPILE_SCHEMA_INVALID",
        L"VALIDATION_FAILED"
    })) {
        return MakeResult(L"STEP_VALIDATION_FAILED", L"Step contract or workflow schema validation failed.", input);
    }
    if (lowerType == L"execution_verification_failed" || AnyContains(text, {
        L"VERIFY_MOVE_FAILED",
        L"EXECUTION_VERIFICATION_FAILED",
        L"VERIFICATION_FAILED",
        L"STEP_VERIFY_FAILED",
        L"VERIFY_FAILED",
        L"RESULT_NOT_VERIFIED"
    })) {
        return MakeResult(L"EXECUTION_VERIFICATION_FAILED", L"Execution completed or attempted but required verification failed.", input);
    }
    if (lowerType == L"evidence_missing" || AnyContains(text, {
        L"EVIDENCE_MISSING",
        L"FAIL_EVIDENCE_MISSING",
        L"MISSING_EVIDENCE",
        L"MISSING_FINAL_STATUS",
        L"MISSING_EVIDENCE_INDEX"
    })) {
        return MakeResult(L"EVIDENCE_MISSING", L"Required evidence was missing or incomplete.", input);
    }
    if (lowerType == L"environment_blocked" || AnyContains(text, {
        L"ENVIRONMENT_BLOCKED",
        L"environment/surface-blocked",
        L"surface-blocked",
        L"SURFACE_BLOCKED",
        L"BROWSER_SURFACE_BLOCKING",
        L"SKIP_ENVIRONMENT",
        L"TIMEOUT",
        L"WINDOW_NOT_FOUND",
        L"APP_NOT_INSTALLED",
        L"APP_LAUNCH_FAILED"
    })) {
        return MakeResult(L"ENVIRONMENT_BLOCKED", L"Environment, app, surface, or timing condition blocked the workflow.", input);
    }

    return MakeResult(L"UNKNOWN_FAILURE", L"No safe specific normalization rule matched; unknown is not success.", input);
}

int CommandFailureAttributionNormalize(int argc, wchar_t** argv) {
    const std::wstring command = L"failure-attribution-normalize";
    ULONGLONG startTick = GetTickCount64();
    FailureAttributionNormalizationInput input;
    std::wstring output;
    ArgValue(argc, argv, L"--workflow-type", input.workflowType);
    ArgValue(argc, argv, L"--execution-result", input.executionResult);
    ArgValue(argc, argv, L"--failure-type", input.failureType);
    ArgValue(argc, argv, L"--failure-code", input.failureCode);
    ArgValue(argc, argv, L"--failure-reason", input.failureReason);
    ArgValue(argc, argv, L"--output", output);
    if (input.failureCode.empty() && input.failureType.empty() && input.executionResult.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"failure-attribution-normalize requires a failure code, failure type, or execution result.", L"{}") << L"\n";
        return 2;
    }
    FailureAttributionNormalizationResult result = NormalizeFailureAttribution(input);
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, result.dataJson, error);
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.dataJson) << L"\n";
    return 0;
}
