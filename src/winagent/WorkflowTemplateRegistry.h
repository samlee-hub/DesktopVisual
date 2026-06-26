#pragma once

#include "WorkflowTemplateRecord.h"

#include <string>
#include <vector>

struct WorkflowTemplateRegistryResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring dataJson;
    std::vector<WorkflowTemplateRecord> templates;
};

std::wstring WorkflowTemplateRegistryPath(const std::wstring& registryRoot);
std::wstring WorkflowTemplateAuditPath(const std::wstring& registryRoot);
WorkflowTemplateRegistryResult LoadWorkflowTemplateRegistry(const std::wstring& registryRoot);
WorkflowTemplateRegistryResult ExportWorkflowTemplateRegistry(const std::wstring& registryRoot, const std::wstring& outputPath);
WorkflowTemplateRegistryResult RegisterWorkflowTemplateCandidate(const std::wstring& registryRoot, const WorkflowTemplateRecord& record);
WorkflowTemplateRegistryResult UpdateWorkflowTemplateRecord(const std::wstring& registryRoot, const WorkflowTemplateRecord& record, const std::wstring& action);
WorkflowTemplateRegistryResult QueryWorkflowTemplatesByType(const std::wstring& registryRoot, const std::wstring& workflowType);
WorkflowTemplateRegistryResult QueryWorkflowTemplatesByStatus(const std::wstring& registryRoot, const std::wstring& status);
WorkflowTemplateRegistryResult GenerateWorkflowTemplateRegistryReport(
    const std::wstring& registryRoot,
    const std::wstring& outputJsonPath,
    const std::wstring& outputMarkdownPath);

int CommandWorkflowTemplateRegister(int argc, wchar_t** argv);
int CommandWorkflowTemplateReport(int argc, wchar_t** argv);

