#pragma once

#include "WorkflowTemplateRecord.h"

#include <string>

struct WorkflowTemplateCandidateExtractionOptions {
    std::wstring sourcePath;
    std::wstring workflowType;
    std::wstring templateName;
    std::wstring outputPath;
};

struct WorkflowTemplateCandidateExtractionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    WorkflowTemplateRecord record;
    std::wstring candidateJson;
    std::wstring reportJson;
};

WorkflowTemplateCandidateExtractionResult ExtractWorkflowTemplateCandidate(
    const WorkflowTemplateCandidateExtractionOptions& options);

int CommandWorkflowTemplateExtract(int argc, wchar_t** argv);

