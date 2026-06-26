#pragma once

#include <string>

struct TaskTemplateV2OperationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
};

TaskTemplateV2OperationResult ValidateTaskTemplateV2File(const std::wstring& path);
TaskTemplateV2OperationResult ResolveTaskTemplateV2(
    const std::wstring& templatePath,
    const std::wstring& profileName,
    const std::wstring& paramsPath,
    const std::wstring& taskPath);
