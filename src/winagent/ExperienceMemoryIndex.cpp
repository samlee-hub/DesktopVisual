#include "ExperienceMemoryIndex.h"

#include "EvidenceFingerprint.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <map>
#include <sstream>

namespace {

std::wstring MapJson(const std::map<std::wstring, int>& values) {
    std::wstringstream json;
    json << L"{";
    bool first = true;
    for (const auto& entry : values) {
        if (!first) json << L",";
        first = false;
        json << simplejson::Quote(entry.first) << L":" << entry.second;
    }
    json << L"}";
    return json.str();
}

}  // namespace

ExperienceMemoryIndexResult BuildExperienceMemoryIndex(
    const std::vector<ExperienceMemoryRecord>& records) {
    std::map<std::wstring, int> byWorkflow;
    std::map<std::wstring, int> byFailureCategory;
    std::map<std::wstring, int> bySourceVersion;
    for (const auto& record : records) {
        ++byWorkflow[record.workflowType.empty() ? L"unknown" : record.workflowType];
        ++byFailureCategory[record.normalizedFailureCategory.empty() ? L"UNKNOWN_FAILURE" : record.normalizedFailureCategory];
        ++bySourceVersion[record.sourceVersion.empty() ? L"unknown" : record.sourceVersion];
    }

    std::wstringstream json;
    json << L"{\"schema_version\":\"6.10.0.experience_memory_index\""
         << L",\"generated_at\":" << simplejson::Quote(NowTimestamp())
         << L",\"record_count\":" << records.size()
         << L",\"by_workflow_type\":" << MapJson(byWorkflow)
         << L",\"by_failure_category\":" << MapJson(byFailureCategory)
         << L",\"by_source_version\":" << MapJson(bySourceVersion)
         << L",\"read_only_query_index\":true"
         << L",\"runtime_execution_triggered\":false"
         << L",\"step_contract_generated\":false"
         << L"}";

    ExperienceMemoryIndexResult result;
    result.ok = true;
    result.indexJson = json.str();
    return result;
}

ExperienceMemoryIndexResult WriteExperienceMemoryIndex(
    const std::wstring& storeRoot,
    const std::vector<ExperienceMemoryRecord>& records) {
    ExperienceMemoryIndexResult result = BuildExperienceMemoryIndex(records);
    if (!result.ok) return result;
    std::wstring error;
    std::wstring indexPath = ValidationJoinPath(storeRoot, L"memory_index.json");
    if (!WriteValidationTextFile(indexPath, result.indexJson, error)) {
        result.ok = false;
        result.errorCode = L"MEMORY_INDEX_WRITE_FAILED";
        result.errorMessage = error.empty() ? L"Could not write memory index." : error;
    }
    return result;
}
