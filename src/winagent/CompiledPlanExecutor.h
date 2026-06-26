#pragma once

#include <string>

struct CompiledPlanExecutionOptions {
    std::wstring executionMode = L"dry_run";
    bool sessionReuseEnabled = true;
    bool developerFullAccess = false;
    bool allowRecovery = true;
    bool allowRealCommit = false;
    bool requireConfirmation = true;
    bool confirmationProvided = false;
    std::wstring evidenceDir;
    std::wstring resultJson;
};

struct CompiledPlanExecutionResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring executionResultJson;
    std::wstring evidenceDir;
};

CompiledPlanExecutionResult ExecuteStepContractJson(
    const std::wstring& stepContractJson,
    const CompiledPlanExecutionOptions& options);

CompiledPlanExecutionResult ExecuteStepContractFile(
    const std::wstring& inputPath,
    const CompiledPlanExecutionOptions& options);

int CommandExecuteStepContract(int argc, wchar_t** argv);
int CommandExecuteCompiledPlan(int argc, wchar_t** argv);
int CommandRunAgentTask(int argc, wchar_t** argv);
