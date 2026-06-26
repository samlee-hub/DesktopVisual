#pragma once

#include <string>
#include <vector>

struct MemorySafetyCheckOptions {
    std::wstring inputJsonPath;
    std::wstring storeRoot;
    std::wstring outputJsonPath;
};

struct MemorySafetyCheckResult {
    bool ok = false;
    std::wstring status;
    std::wstring blockedReason;
    std::vector<std::wstring> violations;
    std::wstring jsonReport;
};

MemorySafetyCheckResult CheckMemorySafetyJson(const std::wstring& json);
MemorySafetyCheckResult CheckMemorySafetyFile(const std::wstring& inputJsonPath);
MemorySafetyCheckResult CheckMemorySafetyStore(const std::wstring& storeRoot);

int CommandMemorySafetyCheck(int argc, wchar_t** argv);
