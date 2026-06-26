#include "BatchWorkflowCoordinator.h"

#include "BatchWorkflowPlan.h"
#include "BatchWorkflowValidator.h"
#include "EvidenceFingerprint.h"
#include "Trace.h"
#include "WorkflowTemplateRegistry.h"

#include <algorithm>
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

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(towlower(ch));
    });
    return value;
}

bool MainGateModeAllowed(const std::wstring& mode) {
    return Lower(mode) == L"compile_only" || Lower(mode) == L"validate_only" || Lower(mode) == L"serial_execute_mock";
}

}  // namespace

int CommandBatchWorkflowRun(int argc, wchar_t** argv) {
    const std::wstring command = L"batch-workflow-run";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"batch-workflow-run requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    BatchWorkflowPlanResult plan = LoadBatchWorkflowPlanFile(input);
    if (!plan.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), plan.errorCode, plan.errorMessage, L"{}") << L"\n";
        return 1;
    }
    if (!MainGateModeAllowed(plan.plan.batchMode)) {
        std::wstring data = L"{\"status\":\"BLOCKED\",\"blocked_reason\":\"BLOCK_BATCH_RUNTIME_SAFE_NOT_MAIN_GATE\",\"batch_mode\":" + simplejson::Quote(plan.plan.batchMode) + L"}";
        if (!output.empty()) {
            std::wstring error;
            WriteValidationTextFile(output, data, error);
        }
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"BLOCK_BATCH_RUNTIME_SAFE_NOT_MAIN_GATE", L"batch-workflow-run main gate allows only compile_only, validate_only, or serial_execute_mock.", data) << L"\n";
        return 1;
    }
    BatchWorkflowValidationResult validation = ValidateBatchWorkflowPlan(plan.plan);
    if (!validation.ok) {
        if (!output.empty()) {
            std::wstring error;
            WriteValidationTextFile(output, validation.reportJson, error);
        }
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), validation.blockedReason, L"Batch workflow validation failed before run.", validation.reportJson) << L"\n";
        return 1;
    }
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.11.0.batch_workflow_runner\""
         << L",\"status\":\"RAW_COMPLETED_UNVERIFIED\""
         << L",\"runner_pass\":false"
         << L",\"batch_id\":" << simplejson::Quote(plan.plan.batchId)
         << L",\"batch_mode\":" << simplejson::Quote(plan.plan.batchMode)
         << L",\"template_instance_count\":" << plan.plan.templateInstances.size()
         << L",\"ui_workflow_executed\":false"
         << L",\"parallel_real_ui\":false"
         << L",\"concurrent_runtime_session\":false"
         << L",\"runtime_executed\":false"
         << L",\"step_verifier_independent\":true"
         << L",\"evidence_required_per_instance\":true"
         << L"}";
    std::wstring resultJson = json.str();
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, resultJson, error);
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), resultJson) << L"\n";
    return 0;
}

int CommandBatchWorkflowReport(int argc, wchar_t** argv) {
    const std::wstring command = L"batch-workflow-report";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"batch-workflow-report requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    BatchWorkflowPlanResult plan = LoadBatchWorkflowPlanFile(input);
    if (!plan.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), plan.errorCode, plan.errorMessage, L"{}") << L"\n";
        return 1;
    }
    std::wstring report = L"{\"schema_version\":\"6.11.0.batch_workflow_report\",\"status\":\"PASS\",\"batch_id\":" +
        simplejson::Quote(plan.plan.batchId) +
        L",\"batch_mode\":" + simplejson::Quote(plan.plan.batchMode) +
        L",\"template_instance_count\":" + std::to_wstring(plan.plan.templateInstances.size()) +
        L",\"parallel_real_ui\":false,\"concurrent_runtime_session\":false,\"runtime_executed\":false}";
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, report, error);
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), report) << L"\n";
    return 0;
}

int CommandV611TemplateBatchCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"v6-11-template-batch-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring registryRoot;
    std::wstring batchPlan;
    std::wstring output;
    ArgValue(argc, argv, L"--registry-root", registryRoot);
    ArgValue(argc, argv, L"--batch-plan", batchPlan);
    ArgValue(argc, argv, L"--output", output);
    WorkflowTemplateRegistryResult report = GenerateWorkflowTemplateRegistryReport(registryRoot, L"", L"");
    bool batchOk = true;
    std::wstring batchReason;
    if (!batchPlan.empty()) {
        BatchWorkflowValidationResult validation = ValidateBatchWorkflowPlanFile(batchPlan);
        batchOk = validation.ok;
        batchReason = validation.blockedReason;
    }
    bool ok = report.ok && batchOk;
    std::wstring json = L"{\"schema_version\":\"6.11.0.template_batch_check\",\"status\":" +
        simplejson::Quote(ok ? L"PASS" : L"BLOCKED") +
        L",\"registry_ok\":" + simplejson::Bool(report.ok) +
        L",\"batch_ok\":" + simplejson::Bool(batchOk) +
        L",\"blocked_reason\":" + simplejson::Quote(ok ? L"" : (report.ok ? batchReason : report.errorCode)) +
        L",\"no_parallel_real_ui\":true,\"no_concurrent_runtime_session\":true,\"no_memory_execution_influence\":true,\"runtime_executed\":false}";
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, json, error);
    }
    if (!ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"V6_11_TEMPLATE_BATCH_CHECK_BLOCKED", L"v6.11 template batch check failed.", json) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), json) << L"\n";
    return 0;
}

