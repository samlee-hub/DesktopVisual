#pragma once

#include <string>

struct PlanCompileResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring contractJson;
    std::wstring diagnosticsJson;
    std::wstring sessionStepsJson;
    int stepCount = 0;
};

class PlanCompiler {
public:
    PlanCompileResult compile_plan(const std::wstring& planDraftJson);
    PlanCompileResult emit_runtime_session_steps(const std::wstring& stepContractJson);
    std::wstring emit_compile_diagnostics(
        bool compileOk,
        const std::wstring& errorCode,
        const std::wstring& errorMessage,
        const std::wstring& failedStepId,
        const std::wstring& missingFieldsJson,
        const std::wstring& unsafeReason,
        const std::wstring& repairHint,
        int emittedStepCount);

private:
    PlanCompileResult compile_step();
    std::wstring infer_runtime_action(const std::wstring& proposedAction);
    std::wstring compile_expected_context();
    std::wstring compile_action_precondition();
    std::wstring compile_verification_hint();
    std::wstring compile_risk_level(const std::wstring& rawRisk);
    std::wstring compile_confirmation_policy();
    std::wstring compile_recovery_policy();
    std::wstring compile_stop_policy();
    std::wstring compile_session_policy();
    std::wstring compile_evidence_policy();
};

PlanCompileResult CompilePlanDraftFile(
    const std::wstring& inputPath,
    const std::wstring& outputPath,
    const std::wstring& diagnosticsPath);

PlanCompileResult DryRunStepContractFile(
    const std::wstring& inputPath,
    const std::wstring& sessionStepsOutputPath);

int CommandPlanCompile(int argc, wchar_t** argv);
int CommandStepContractDryRun(int argc, wchar_t** argv);
int CommandPlanCompileSelftest(int argc, wchar_t** argv);
