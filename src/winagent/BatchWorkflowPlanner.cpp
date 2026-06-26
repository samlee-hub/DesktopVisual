#include "BatchWorkflowPlanner.h"

#include "EvidenceFingerprint.h"
#include "Trace.h"
#include "WorkflowTemplateRecord.h"

#include <iostream>

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

BatchWorkflowPlanResult Fail(const std::wstring& code, const std::wstring& message) {
    BatchWorkflowPlanResult result;
    result.errorCode = code;
    result.errorMessage = message;
    return result;
}

}  // namespace

BatchWorkflowPlanResult PlanBatchWorkflowFromFile(const std::wstring& inputPath) {
    BatchWorkflowPlanResult plan = LoadBatchWorkflowPlanFile(inputPath);
    if (!plan.ok) return plan;
    for (auto& instance : plan.plan.templateInstances) {
        if (instance.templatePath.empty()) return Fail(L"FAIL_BATCH_TEMPLATE_PATH_MISSING", L"template_path is required for each batch instance.");
        std::wstring text;
        std::wstring error;
        if (!ReadValidationTextFile(instance.templatePath, text, error)) {
            return Fail(L"FAIL_BATCH_TEMPLATE_NOT_FOUND", L"Batch template path could not be read.");
        }
        WorkflowTemplateRecordResult record = ParseWorkflowTemplateRecordJson(text);
        if (!record.ok) return Fail(record.errorCode, record.errorMessage);
        if (record.record.templateStatus != L"validated" || record.record.validationStatus != L"pass") {
            return Fail(L"BLOCK_TEMPLATE_NOT_VALIDATED", L"Batch planner accepts only validated templates.");
        }
        instance.templateId = record.record.templateId;
        instance.templateVersion = record.record.templateVersion;
    }
    plan.plan = FinalizeBatchWorkflowPlan(plan.plan);
    plan.planJson = BatchWorkflowPlanToJson(plan.plan);
    return plan;
}

int CommandBatchWorkflowPlan(int argc, wchar_t** argv) {
    const std::wstring command = L"batch-workflow-plan";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    std::wstring output;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"batch-workflow-plan requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", output);
    BatchWorkflowPlanResult result = PlanBatchWorkflowFromFile(input);
    if (!output.empty()) {
        std::wstring error;
        WriteValidationTextFile(output, result.ok ? result.planJson : L"{\"status\":\"FAIL\",\"error_code\":" + simplejson::Quote(result.errorCode) + L"}", error);
    }
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode, result.errorMessage, L"{}") << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), L"{\"status\":\"PASS\",\"batch_id\":" + simplejson::Quote(result.plan.batchId) + L",\"batch_hash\":" + simplejson::Quote(result.plan.batchHash) + L",\"runtime_executed\":false}") << L"\n";
    return 0;
}

