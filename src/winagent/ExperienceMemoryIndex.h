#pragma once

#include "ExperienceMemoryRecord.h"

#include <string>
#include <vector>

struct ExperienceMemoryIndexResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring indexJson;
};

ExperienceMemoryIndexResult BuildExperienceMemoryIndex(
    const std::vector<ExperienceMemoryRecord>& records);
ExperienceMemoryIndexResult WriteExperienceMemoryIndex(
    const std::wstring& storeRoot,
    const std::vector<ExperienceMemoryRecord>& records);
