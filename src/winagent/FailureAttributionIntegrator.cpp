#include "FailureAttributionIntegrator.h"

#include "EvidenceFingerprint.h"
#include "ExperienceMemoryRecord.h"
#include "ExperienceMemoryStore.h"
#include "MemorySafetyBoundary.h"
#include "Trace.h"

#include <windows.h>

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

FailureAttributionIntegrationResult Fail(const std::wstring& code, const std::wstring& message, const std::wstring& data = L"{}") {
    FailureAttributionIntegrationResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.recordJson = data;
    return result;
}

}  // namespace

FailureAttributionIntegrationResult IntegrateExperienceMemoryRecord(
    const FailureAttributionIntegrationOptions& options) {
    if (options.inputJsonPath.empty()) {
        return Fail(L"INVALID_ARGUMENT", L"Experience memory integration requires an input JSON path.");
    }

    ExperienceMemoryRecordResult built = LoadExperienceMemoryRecordInput(options.inputJsonPath);
    if (!built.ok) {
        return Fail(built.errorCode, built.errorMessage);
    }

    MemorySafetyCheckResult safety = CheckMemorySafetyJson(built.recordJson);
    if (!safety.ok) {
        return Fail(safety.blockedReason.empty() ? L"MEMORY_SAFETY_BLOCKED" : safety.blockedReason, L"Memory safety boundary rejected the record.", safety.jsonReport);
    }

    ExperienceMemoryStoreResult appended = AppendExperienceMemoryRecord(options.storeRoot, built.record);
    if (!appended.ok) {
        return Fail(appended.errorCode, appended.errorMessage, appended.dataJson.empty() ? built.recordJson : appended.dataJson);
    }

    std::wstring error;
    if (!options.outputJsonPath.empty()) {
        WriteValidationTextFile(options.outputJsonPath, built.recordJson, error);
    }

    FailureAttributionIntegrationResult result;
    result.ok = true;
    result.recordJson = built.recordJson;
    return result;
}

int CommandExperienceMemoryRecord(int argc, wchar_t** argv) {
    const std::wstring command = L"experience-memory-record";
    ULONGLONG startTick = GetTickCount64();
    FailureAttributionIntegrationOptions options;
    ArgValue(argc, argv, L"--input", options.inputJsonPath);
    ArgValue(argc, argv, L"--store-root", options.storeRoot);
    ArgValue(argc, argv, L"--output", options.outputJsonPath);
    if (options.inputJsonPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"experience-memory-record requires --input.", L"{}") << L"\n";
        return 2;
    }
    FailureAttributionIntegrationResult result = IntegrateExperienceMemoryRecord(options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EXPERIENCE_MEMORY_RECORD_FAILED" : result.errorCode, result.errorMessage, result.recordJson.empty() ? L"{}" : result.recordJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.recordJson) << L"\n";
    return 0;
}
