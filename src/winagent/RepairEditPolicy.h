#pragma once

#include "CodeWritePlan.h"

#include <string>
#include <vector>

struct RepairEditPolicyResult {
    bool ok = true;
    bool repairEditPolicy = true;
    bool repairReplaceNotAppend = true;
    bool repairAttempted = false;
    bool duplicatedReceiverTokenDetected = false;
    bool receiverTokenStillInvalidAfterRepair = false;
    std::wstring beforeToken;
    std::wstring afterToken;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::vector<std::wstring> tokenDiff;
    std::vector<std::wstring> findings;
};

RepairEditPolicyResult EvaluateRepairEditPolicyForPlan(const CodeWritePlanResult& plan);
RepairEditPolicyResult PlanReceiverTokenRepair(const std::wstring& beforeToken, const std::wstring& expectedToken = L"self");
std::wstring RepairEditPolicyResultJson(const RepairEditPolicyResult& result);
