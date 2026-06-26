#include "RepairEditPolicy.h"

#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>

namespace {

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    return value.rfind(prefix, 0) == 0;
}

bool IsSuspiciousReceiverToken(const std::wstring& token) {
    std::wstring lower = ToLower(token);
    return lower == L"selfself" ||
           lower == L"self self" ||
           lower == L"self_self" ||
           lower == L"thisself" ||
           lower == L"selfthis" ||
           lower == L"clscls" ||
           (lower.size() > 4 && StartsWith(lower, L"self") && lower != L"self") ||
           (lower.size() > 3 && StartsWith(lower, L"cls") && lower != L"cls");
}

void AddFinding(RepairEditPolicyResult& result, const std::wstring& finding, const std::wstring& code) {
    result.ok = false;
    result.findings.push_back(finding);
    if (result.errorCode.empty()) {
        result.errorCode = code;
        result.errorMessage = finding;
    }
}

void MergeRepair(RepairEditPolicyResult& aggregate, const RepairEditPolicyResult& repair) {
    aggregate.repairAttempted = aggregate.repairAttempted || repair.repairAttempted;
    aggregate.duplicatedReceiverTokenDetected = aggregate.duplicatedReceiverTokenDetected || repair.duplicatedReceiverTokenDetected;
    aggregate.receiverTokenStillInvalidAfterRepair = aggregate.receiverTokenStillInvalidAfterRepair || repair.receiverTokenStillInvalidAfterRepair;
    if (!repair.beforeToken.empty()) aggregate.beforeToken = repair.beforeToken;
    if (!repair.afterToken.empty()) aggregate.afterToken = repair.afterToken;
    for (const auto& diff : repair.tokenDiff) aggregate.tokenDiff.push_back(diff);
    for (const auto& finding : repair.findings) aggregate.findings.push_back(finding);
    if (!repair.ok && aggregate.errorCode.empty()) {
        aggregate.ok = false;
        aggregate.errorCode = repair.errorCode;
        aggregate.errorMessage = repair.errorMessage;
    }
}

}  // namespace

RepairEditPolicyResult PlanReceiverTokenRepair(const std::wstring& beforeToken, const std::wstring& expectedToken) {
    RepairEditPolicyResult result;
    result.beforeToken = beforeToken;
    result.afterToken = expectedToken;
    result.repairReplaceNotAppend = true;

    if (beforeToken.empty() || beforeToken == expectedToken || beforeToken == L"cls") {
        return result;
    }

    if (IsSuspiciousReceiverToken(beforeToken)) {
        result.repairAttempted = true;
        result.duplicatedReceiverTokenDetected = true;
        result.tokenDiff.push_back(L"before: " + beforeToken);
        result.tokenDiff.push_back(L"after: " + expectedToken);
        if (result.afterToken != expectedToken) {
            result.receiverTokenStillInvalidAfterRepair = true;
            AddFinding(result, L"Receiver token repair must replace the full token with the expected receiver.", L"BLOCKED_RECEIVER_TOKEN_STILL_INVALID_AFTER_REPAIR");
        }
        return result;
    }

    result.repairAttempted = true;
    result.tokenDiff.push_back(L"before: " + beforeToken);
    result.tokenDiff.push_back(L"after: " + expectedToken);
    return result;
}

RepairEditPolicyResult EvaluateRepairEditPolicyForPlan(const CodeWritePlanResult& plan) {
    RepairEditPolicyResult result;
    result.ok = true;
    result.repairReplaceNotAppend = true;
    if (plan.language != L"python") return result;

    for (const auto& cls : plan.classes) {
        for (const auto& method : cls.methods) {
            MergeRepair(result, PlanReceiverTokenRepair(method.receiverToken.empty() ? L"self" : method.receiverToken, L"self"));
        }
    }
    for (const auto& fn : plan.topLevelFunctions) {
        if (!fn.receiverToken.empty()) {
            MergeRepair(result, PlanReceiverTokenRepair(fn.receiverToken, L"self"));
        }
    }
    return result;
}

std::wstring RepairEditPolicyResultJson(const RepairEditPolicyResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"repair_edit_policy\":" + simplejson::Bool(result.repairEditPolicy);
    json += L",\"repair_replace_not_append\":" + simplejson::Bool(result.repairReplaceNotAppend);
    json += L",\"repair_attempted\":" + simplejson::Bool(result.repairAttempted);
    json += L",\"duplicated_receiver_token_detected\":" + simplejson::Bool(result.duplicatedReceiverTokenDetected);
    json += L",\"receiver_token_still_invalid_after_repair\":" + simplejson::Bool(result.receiverTokenStillInvalidAfterRepair);
    json += L",\"before_token\":" + simplejson::Quote(result.beforeToken);
    json += L",\"after_token\":" + simplejson::Quote(result.afterToken);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"token_diff\":[";
    for (size_t i = 0; i < result.tokenDiff.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.tokenDiff[i]);
    }
    json += L"],\"findings\":[";
    for (size_t i = 0; i < result.findings.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.findings[i]);
    }
    json += L"]}";
    return json;
}
