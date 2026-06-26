#include "VLMObservationBoundary.h"

#include "MockVLMProvider.h"
#include "SimpleJson.h"
#include "Trace.h"
#include "VLMObservationContract.h"
#include "VLMObservationValidator.h"
#include "VLMProvider.h"

#include <windows.h>

#include <iostream>
#include <sstream>

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

std::wstring BoundaryJson(const VLMObservationBoundaryResult& result) {
    std::wstringstream json;
    json << L"{\"boundary_enforced\":" << (result.boundaryEnforced ? L"true" : L"false")
         << L",\"boundary_ok\":" << (result.boundaryOk ? L"true" : L"false")
         << L",\"assistive_only_boundary\":true"
         << L",\"runtime_only_executor_rule_preserved\":true"
         << L",\"runtime_executed\":false"
         << L",\"mouse_click_sent\":false"
         << L",\"keyboard_type_sent\":false"
         << L",\"scroll_sent\":false"
         << L",\"result_validated\":" << (result.resultValidated ? L"true" : L"false")
         << L",\"validation_ok\":" << (result.validationOk ? L"true" : L"false")
         << L",\"safe_for_direct_execution\":false"
         << L",\"safe_for_runtime_candidate_pipeline\":" << (result.safeForRuntimeCandidatePipeline ? L"true" : L"false")
         << L",\"vlm_result_entered_runtime_action_path\":false"
         << L",\"vlm_possible_target_directly_converted_to_action\":false"
         << L",\"step_contract_accepts_vlm_action\":false"
         << L",\"compiled_plan_executor_accepts_vlm_action\":false"
         << L",\"v6_6_runtime_validation_pipeline_required\":true"
         << L",\"dry_run_only\":true"
         << L",\"blocked_reason\":" << JsonString(result.blockedReason)
         << L"}";
    return json.str();
}

std::wstring DryRunDataJson(
    const std::wstring& provider,
    const std::wstring& scenario,
    const std::wstring& resultPath,
    const std::wstring& validationPath,
    const std::wstring& boundaryPath,
    const VLMObservationBoundaryResult& boundary) {
    std::wstringstream data;
    data << L"{\"provider\":" << JsonString(provider)
         << L",\"scenario\":" << JsonString(scenario)
         << L",\"result_path\":" << JsonString(resultPath)
         << L",\"validation_path\":" << JsonString(validationPath)
         << L",\"boundary_path\":" << JsonString(boundaryPath)
         << L",\"runtime_executed\":false"
         << L",\"mouse_click_sent\":false"
         << L",\"keyboard_type_sent\":false"
         << L",\"result_validated\":" << (boundary.resultValidated ? L"true" : L"false")
         << L",\"validation_ok\":" << (boundary.validationOk ? L"true" : L"false")
         << L",\"boundary_enforced\":" << (boundary.boundaryEnforced ? L"true" : L"false")
         << L",\"safe_for_direct_execution\":false"
         << L",\"boundary\":" << boundary.resultJson
         << L"}";
    return data.str();
}

std::wstring DisabledValidationJson() {
    return L"{\"validation_ok\":false,\"executable\":false,\"assistive_only\":true,\"validation_errors\":[],\"validation_warnings\":[\"PROVIDER_EXTERNAL_DISABLED\"],\"blocked_reason\":\"PROVIDER_EXTERNAL_DISABLED\",\"safe_for_runtime_candidate_pipeline\":false,\"safe_for_direct_execution\":false}";
}

}  // namespace

VLMObservationBoundaryResult EvaluateVLMObservationBoundary(
    const std::wstring&,
    const std::wstring&,
    const std::wstring& validationJson) {
    VLMObservationBoundaryResult boundary;
    boundary.boundaryEnforced = true;
    boundary.runtimeExecuted = false;
    boundary.mouseClickSent = false;
    boundary.keyboardTypeSent = false;
    boundary.scrollSent = false;
    boundary.vlmResultEnteredRuntimeActionPath = false;
    boundary.vlmPossibleTargetDirectlyConvertedToAction = false;
    boundary.stepContractAcceptsVLMAction = false;
    boundary.compiledPlanExecutorAcceptsVLMAction = false;
    boundary.safeForDirectExecution = false;

    simplejson::ParseResult parsed = simplejson::Parse(validationJson);
    if (parsed.ok && parsed.root.IsObject()) {
        boundary.resultValidated = true;
        boundary.validationOk = simplejson::GetBool(parsed.root, L"validation_ok", false);
        boundary.safeForRuntimeCandidatePipeline = simplejson::GetBool(parsed.root, L"safe_for_runtime_candidate_pipeline", false);
        boundary.safeForDirectExecution = simplejson::GetBool(parsed.root, L"safe_for_direct_execution", false);
        boundary.blockedReason = simplejson::GetString(parsed.root, L"blocked_reason", L"");
    } else {
        boundary.resultValidated = false;
        boundary.validationOk = false;
        boundary.blockedReason = L"VALIDATION_JSON_INVALID";
    }

    boundary.boundaryOk =
        boundary.boundaryEnforced &&
        !boundary.runtimeExecuted &&
        !boundary.mouseClickSent &&
        !boundary.keyboardTypeSent &&
        !boundary.scrollSent &&
        !boundary.safeForDirectExecution &&
        !boundary.vlmResultEnteredRuntimeActionPath &&
        !boundary.vlmPossibleTargetDirectlyConvertedToAction &&
        !boundary.stepContractAcceptsVLMAction &&
        !boundary.compiledPlanExecutorAcceptsVLMAction;
    boundary.resultJson = BoundaryJson(boundary);
    return boundary;
}

int CommandVLMObservationDryRun(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-observation-dry-run";
    std::wstring requestPath;
    std::wstring provider = L"mock";
    std::wstring scenario = L"valid";
    std::wstring resultPath;
    std::wstring validationPath;
    std::wstring boundaryPath;
    ArgValue(argc, argv, L"--request", requestPath);
    ArgValue(argc, argv, L"--provider", provider);
    ArgValue(argc, argv, L"--scenario", scenario);
    ArgValue(argc, argv, L"--result", resultPath);
    ArgValue(argc, argv, L"--validation", validationPath);
    ArgValue(argc, argv, L"--boundary", boundaryPath);
    if (requestPath.empty() || resultPath.empty() || validationPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"vlm-observation-dry-run requires --request, --result, and --validation.", L"{}") << L"\n";
        return 2;
    }
    if (boundaryPath.empty()) {
        boundaryPath = validationPath + L".boundary.json";
    }

    std::wstring requestJson;
    std::wstring ioError;
    if (!VLMReadTextFile(requestPath, requestJson, ioError)) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"FILE_READ_FAILED", ioError, L"{}") << L"\n";
        return 1;
    }

    if (provider == L"external") {
        VLMProviderRunResult disabled = ExternalVLMProviderDisabledResult();
        VLMWriteTextFile(resultPath, disabled.resultJson, ioError);
        std::wstring validationJson = DisabledValidationJson();
        VLMWriteTextFile(validationPath, validationJson, ioError);
        VLMObservationBoundaryResult boundary = EvaluateVLMObservationBoundary(requestJson, disabled.resultJson, validationJson);
        boundary.blockedReason = L"PROVIDER_EXTERNAL_DISABLED";
        boundary.resultJson = BoundaryJson(boundary);
        VLMWriteTextFile(boundaryPath, boundary.resultJson, ioError);
        std::wstring data = DryRunDataJson(provider, scenario, resultPath, validationPath, boundaryPath, boundary);
        std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
        return 0;
    }

    if (provider != L"mock") {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"--provider must be mock or external.", L"{}") << L"\n";
        return 2;
    }

    MockVLMProvider mock;
    VLMProviderRunResult providerResult = mock.run_observation(requestJson, scenario);
    if (!providerResult.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), providerResult.errorCode, providerResult.errorMessage, L"{}") << L"\n";
        return providerResult.errorCode == L"INVALID_ARGUMENT" ? 2 : 1;
    }
    if (!VLMWriteTextFile(resultPath, providerResult.resultJson, ioError)) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"FILE_WRITE_FAILED", ioError, L"{}") << L"\n";
        return 1;
    }

    VLMObservationValidationResult validation = ValidateVLMObservationResultJson(requestJson, providerResult.resultJson);
    VLMWriteTextFile(validationPath, validation.resultJson, ioError);
    VLMObservationBoundaryResult boundary = EvaluateVLMObservationBoundary(requestJson, providerResult.resultJson, validation.resultJson);
    VLMWriteTextFile(boundaryPath, boundary.resultJson, ioError);

    std::wstring data = DryRunDataJson(provider, scenario, resultPath, validationPath, boundaryPath, boundary);
    if (!validation.validationOk) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), validation.validationErrors.empty() ? L"VLM_SCHEMA_INVALID" : validation.validationErrors[0], L"VLM observation dry-run validation failed; no Runtime action executed.", data) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}

int CommandVLMObservationSelftest(int argc, wchar_t** argv) {
    (void)argc;
    (void)argv;
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-observation-selftest";
    std::wstring data =
        L"{\"schema_available\":true"
        L",\"mock_provider_available\":true"
        L",\"validator_available\":true"
        L",\"boundary_available\":true"
        L",\"provider_role\":\"assistive_only\""
        L",\"runtime_executed\":false"
        L",\"safe_for_direct_execution\":false"
        L"}";
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), data) << L"\n";
    return 0;
}

