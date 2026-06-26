#pragma once

#include "ExperienceMemoryRecord.h"

#include <string>
#include <vector>

struct ExperienceMemoryStoreOptions {
    std::wstring storeRoot;
};

struct ExperienceMemoryQueryOptions {
    std::wstring storeRoot;
    std::wstring workflowType;
    std::wstring failureCategory;
    std::wstring sourceVersion;
    std::wstring outputJsonPath;
};

struct ExperienceMemoryStoreResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    int recordCount = 0;
};

std::wstring DefaultExperienceMemoryStoreRoot();
std::wstring ExperienceMemoryRecordsPath(const std::wstring& storeRoot);
std::wstring ExperienceMemoryIndexPath(const std::wstring& storeRoot);

ExperienceMemoryStoreResult AppendExperienceMemoryRecord(
    const std::wstring& storeRoot,
    const ExperienceMemoryRecord& record);
ExperienceMemoryStoreResult LoadExperienceMemoryRecords(
    const std::wstring& storeRoot,
    std::vector<ExperienceMemoryRecord>& records);
ExperienceMemoryStoreResult QueryExperienceMemoryRecords(
    const ExperienceMemoryQueryOptions& options);
ExperienceMemoryStoreResult GenerateExperienceMemoryReport(
    const std::wstring& storeRoot,
    const std::wstring& outputJsonPath,
    const std::wstring& outputMarkdownPath);

int CommandExperienceMemoryQuery(int argc, wchar_t** argv);
int CommandExperienceMemoryReport(int argc, wchar_t** argv);
int CommandV610ExperienceMemoryCheck(int argc, wchar_t** argv);
