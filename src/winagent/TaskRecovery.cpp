#include "TaskRecovery.h"

#include "CaseRunner.h"
#include "Trace.h"

#include <cwctype>
#include <sstream>
#include <vector>

namespace {

std::wstring JsonGetString(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'"') return L"";
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) ++pos;
        value += json[pos];
        ++pos;
    }
    return value;
}

int JsonGetInt(const std::wstring& json, const std::wstring& key, int def = 0) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    try { return std::stoi(json.substr(pos)); } catch (...) { return def; }
}

bool JsonGetBool(const std::wstring& json, const std::wstring& key, bool def = false) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (json.substr(pos, 4) == L"true") return true;
    if (json.substr(pos, 5) == L"false") return false;
    return def;
}

std::wstring JsonGetObject(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'{') return L"";
    int depth = 1;
    size_t start = pos++;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'{') ++depth;
        else if (json[pos] == L'}') --depth;
        ++pos;
    }
    return depth == 0 ? json.substr(start, pos - start) : L"";
}

std::wstring JsonGetArray(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'[') return L"";
    int depth = 1;
    size_t start = pos++;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'[') ++depth;
        else if (json[pos] == L']') --depth;
        ++pos;
    }
    return depth == 0 ? json.substr(start, pos - start) : L"";
}

std::wstring RawOrEmptyArray(const std::wstring& arrayJson) {
    return arrayJson.empty() ? L"[]" : arrayJson;
}

int CountObjects(const std::wstring& arrayJson) {
    int count = 0;
    bool inString = false;
    for (size_t i = 0; i < arrayJson.size(); ++i) {
        wchar_t ch = arrayJson[i];
        if (ch == L'\\' && inString) {
            ++i;
            continue;
        }
        if (ch == L'"') {
            inString = !inString;
        } else if (!inString && ch == L'{') {
            ++count;
        }
    }
    return count;
}

std::vector<std::wstring> JsonGetStringValues(const std::wstring& json, const std::wstring& key) {
    std::vector<std::wstring> values;
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = 0;
    while ((pos = json.find(search, pos)) != std::wstring::npos) {
        pos += search.size();
        while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
        if (pos >= json.size() || json[pos] != L'"') continue;
        ++pos;
        std::wstring value;
        while (pos < json.size() && json[pos] != L'"') {
            if (json[pos] == L'\\' && pos + 1 < json.size()) ++pos;
            value += json[pos];
            ++pos;
        }
        values.push_back(value);
    }
    return values;
}

bool IsSupportedRecoveryStrategy(const std::wstring& strategy) {
    return strategy == L"re_observe" ||
           strategy == L"re_locate" ||
           strategy == L"wait_and_retry" ||
           strategy == L"invalidate_cache" ||
           strategy == L"use_profile_fallback" ||
           strategy == L"use_visual_provider" ||
           strategy == L"ask_user" ||
           strategy == L"escalate_to_agent" ||
           strategy == L"stop";
}

RecoveryPolicyValidationResult Invalid(const RecoveryPolicy& policy, const std::wstring& message) {
    RecoveryPolicyValidationResult result;
    result.ok = false;
    result.errorCode = L"RECOVERY_POLICY_SCHEMA_INVALID";
    result.errorMessage = message;
    result.policy = policy;
    result.dataJson = RecoveryPolicyDataJson(policy);
    return result;
}

bool RequireString(const RecoveryPolicy& policy, const std::wstring& value, const std::wstring& field, RecoveryPolicyValidationResult& out) {
    if (!value.empty()) return true;
    out = Invalid(policy, L"RecoveryPolicy missing required field: " + field);
    return false;
}

std::wstring SupportedStrategiesJson() {
    return L"[\"re_observe\",\"re_locate\",\"wait_and_retry\",\"invalidate_cache\",\"use_profile_fallback\",\"use_visual_provider\",\"ask_user\",\"escalate_to_agent\",\"stop\"]";
}

std::wstring RouteObjectForFailure(const std::wstring& routes, const std::wstring& failureReason) {
    std::wstring needle = L"\"failure_reason\"";
    size_t pos = 0;
    while ((pos = routes.find(needle, pos)) != std::wstring::npos) {
        size_t objectStart = routes.rfind(L'{', pos);
        size_t objectEnd = routes.find(L'}', pos);
        if (objectStart == std::wstring::npos || objectEnd == std::wstring::npos || objectEnd <= objectStart) {
            ++pos;
            continue;
        }
        std::wstring object = routes.substr(objectStart, objectEnd - objectStart + 1);
        if (JsonGetString(object, L"failure_reason") == failureReason) {
            return object;
        }
        pos = objectEnd + 1;
    }
    return L"";
}

std::wstring NextActionForStrategy(const std::wstring& strategy) {
    if (strategy == L"wait_and_retry") return L"wait";
    if (strategy == L"re_observe") return L"re_observe";
    if (strategy == L"re_locate") return L"re_locate";
    if (strategy == L"invalidate_cache") return L"invalidate_cache";
    if (strategy == L"use_profile_fallback") return L"use_profile_fallback";
    if (strategy == L"use_visual_provider") return L"use_visual_provider";
    if (strategy == L"ask_user") return L"ask_user";
    if (strategy == L"escalate_to_agent") return L"escalate_to_agent";
    return L"stop";
}

bool IsLowRiskAutoRecovery(const std::wstring& strategy) {
    return strategy == L"wait_and_retry" ||
           strategy == L"re_observe" ||
           strategy == L"re_locate" ||
           strategy == L"invalidate_cache";
}

std::wstring NormalizeToken(std::wstring value) {
    for (wchar_t& ch : value) {
        if (ch == L'-' || ch == L' ') ch = L'_';
        else ch = static_cast<wchar_t>(towlower(ch));
    }
    return value;
}

bool IsSafeStopReason(const std::wstring& reason) {
    std::wstring normalized = NormalizeToken(reason);
    return normalized == L"captcha" ||
           normalized == L"anti_cheat" ||
           normalized == L"proctoring" ||
           normalized == L"payment" ||
           normalized == L"credential" ||
           normalized == L"security_challenge" ||
           normalized == L"credential_security_challenge" ||
           normalized == L"game_automation" ||
           normalized == L"real_exam_public_profile" ||
           normalized == L"hiring_assessment_public_profile" ||
           normalized == L"real_exam_hiring_assessment_submission" ||
           normalized == L"safety_denied" ||
           normalized == L"safety_policy_denied";
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

}  // namespace

std::wstring RecoveryPolicyDataJson(const RecoveryPolicy& policy) {
    std::wstringstream json;
    json << L"{\"schema_version\":" << JsonString(policy.schemaVersion)
         << L",\"policy_id\":" << JsonString(policy.policyId)
         << L",\"task_type\":" << JsonString(policy.taskType)
         << L",\"permission_profile\":" << JsonString(policy.permissionProfile)
         << L",\"retry_budget\":{\"max_attempts\":" << policy.retryMaxAttempts
         << L",\"max_total_recovery_ms\":" << policy.retryMaxTotalRecoveryMs
         << L",\"max_wait_ms\":" << policy.retryMaxWaitMs
         << L",\"backoff_ms\":" << policy.retryBackoffMs
         << L"}"
         << L",\"route_count\":" << policy.routeCount
         << L",\"audit\":{\"record_attempts\":" << (policy.recordAttempts ? L"true" : L"false")
         << L",\"artifact_dir\":" << JsonString(policy.artifactDir)
         << L"}"
         << L",\"supported_strategies\":" << SupportedStrategiesJson()
         << L"}";
    return json.str();
}

RecoveryPolicyValidationResult ValidateRecoveryPolicyFile(const std::wstring& path) {
    RecoveryPolicyValidationResult out;
    FileReadResult file = ReadTextFile(path);
    if (!file.ok) {
        out.ok = false;
        out.errorCode = file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode;
        out.errorMessage = L"Could not read RecoveryPolicy file: " + file.error;
        out.dataJson = L"{\"file\":" + JsonString(path) + L"}";
        return out;
    }

    const std::wstring& json = file.content;
    RecoveryPolicy policy;
    policy.schemaVersion = JsonGetString(json, L"schema_version");
    policy.policyId = JsonGetString(json, L"policy_id");
    policy.taskType = JsonGetString(json, L"task_type");
    policy.permissionProfile = JsonGetString(json, L"permission_profile");

    std::wstring retry = JsonGetObject(json, L"retry_budget");
    policy.retryMaxAttempts = JsonGetInt(retry, L"max_attempts", 0);
    policy.retryMaxTotalRecoveryMs = JsonGetInt(retry, L"max_total_recovery_ms", 0);
    policy.retryMaxWaitMs = JsonGetInt(retry, L"max_wait_ms", 0);
    if (policy.retryMaxTotalRecoveryMs <= 0) policy.retryMaxTotalRecoveryMs = policy.retryMaxWaitMs;
    policy.retryBackoffMs = JsonGetInt(retry, L"backoff_ms", 0);

    std::wstring routes = JsonGetArray(json, L"routes");
    policy.routeCount = CountObjects(routes);

    std::wstring audit = JsonGetObject(json, L"audit");
    policy.recordAttempts = JsonGetBool(audit, L"record_attempts", false);
    policy.artifactDir = JsonGetString(audit, L"artifact_dir");

    if (policy.schemaVersion != L"5.2.1") return Invalid(policy, L"RecoveryPolicy schema_version must be 5.2.1.");
    if (!RequireString(policy, policy.policyId, L"policy_id", out)) return out;
    if (!RequireString(policy, policy.taskType, L"task_type", out)) return out;
    if (policy.permissionProfile != L"DEFAULT" &&
        policy.permissionProfile != L"PUBLIC_DEFAULT" &&
        policy.permissionProfile != L"DEVELOPER_CAPABILITY_DISCOVERY" &&
        policy.permissionProfile != L"DEVELOPER_FULL_RUNTIME" &&
        policy.permissionProfile != L"developer_capability_discovery" &&
        policy.permissionProfile != L"developer_full_runtime" &&
        policy.permissionProfile != L"CI_MOCK" &&
        policy.permissionProfile != L"FULL_ACCESS") {
        return Invalid(policy, L"permission_profile must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.");
    }
    if (retry.empty()) return Invalid(policy, L"RecoveryPolicy missing required field: retry_budget.");
    if (policy.retryMaxAttempts < 0 || policy.retryMaxTotalRecoveryMs < 0 || policy.retryMaxWaitMs < 0 || policy.retryBackoffMs < 0) {
        return Invalid(policy, L"retry_budget values must be non-negative.");
    }
    if (policy.retryMaxAttempts == 0 && policy.retryMaxTotalRecoveryMs == 0) {
        return Invalid(policy, L"retry_budget must bound attempts or total recovery time.");
    }
    if (routes.empty() || policy.routeCount <= 0) return Invalid(policy, L"RecoveryPolicy routes must not be empty.");

    std::vector<std::wstring> strategies = JsonGetStringValues(routes, L"strategy");
    if (static_cast<int>(strategies.size()) != policy.routeCount) {
        return Invalid(policy, L"Each recovery route requires a strategy.");
    }
    for (const std::wstring& strategy : strategies) {
        if (!IsSupportedRecoveryStrategy(strategy)) {
            return Invalid(policy, L"Unsupported recovery strategy: " + strategy);
        }
    }
    std::vector<std::wstring> reasons = JsonGetStringValues(routes, L"failure_reason");
    if (static_cast<int>(reasons.size()) != policy.routeCount) {
        return Invalid(policy, L"Each recovery route requires a failure_reason.");
    }
    if (audit.empty()) return Invalid(policy, L"RecoveryPolicy missing required field: audit.");
    if (!policy.recordAttempts) return Invalid(policy, L"audit.record_attempts must be true.");
    if (!RequireString(policy, policy.artifactDir, L"audit.artifact_dir", out)) return out;

    out.ok = true;
    out.policy = policy;
    out.dataJson = RecoveryPolicyDataJson(policy);
    return out;
}

RecoveryAttemptEvaluationResult EvaluateRecoveryAttempt(
    const std::wstring& policyPath,
    const std::wstring& failureReason,
    const std::wstring& contextPath,
    int attempt) {
    RecoveryAttemptEvaluationResult out;
    RecoveryPolicyValidationResult policyResult = ValidateRecoveryPolicyFile(policyPath);
    if (!policyResult.ok) {
        out.ok = false;
        out.errorCode = policyResult.errorCode;
        out.errorMessage = policyResult.errorMessage;
        out.dataJson = policyResult.dataJson;
        return out;
    }
    if (failureReason.empty()) {
        out.ok = false;
        out.errorCode = L"INVALID_ARGUMENT";
        out.errorMessage = L"recovery-evaluate requires failure_reason.";
        out.dataJson = L"{}";
        return out;
    }
    if (attempt <= 0) attempt = 1;

    FileReadResult policyFile = ReadTextFile(policyPath);
    FileReadResult contextFile = ReadTextFile(contextPath);
    if (!contextFile.ok) {
        out.ok = false;
        out.errorCode = contextFile.errorCode.empty() ? L"FILE_READ_FAILED" : contextFile.errorCode;
        out.errorMessage = L"Could not read recovery context file: " + contextFile.error;
        out.dataJson = L"{\"context\":" + JsonString(contextPath) + L"}";
        return out;
    }

    std::wstring sceneState = JsonGetString(contextFile.content, L"scene_state");
    std::wstring blockType = JsonGetString(contextFile.content, L"block_type");
    std::wstring riskLevel = JsonGetString(contextFile.content, L"risk_level");
    if (IsSafeStopReason(failureReason) || IsSafeStopReason(blockType) || sceneState == L"blocked" || riskLevel == L"high") {
        out.ok = false;
        out.errorCode = L"RECOVERY_REQUIRES_ESCALATION_OR_STOP";
        out.errorMessage = L"Recovery is denied for SafeStop or blocked context.";
        out.dataJson = L"{\"failure_reason\":" + JsonString(failureReason)
            + L",\"strategy\":\"stop\",\"next_action\":\"stop\""
            + L",\"safe_to_retry\":false,\"recovery_allowed\":false"
            + L",\"scene_state\":" + JsonString(sceneState)
            + L",\"block_type\":" + JsonString(blockType)
            + L",\"risk_level\":" + JsonString(riskLevel)
            + L"}";
        return out;
    }

    std::wstring routes = JsonGetArray(policyFile.content, L"routes");
    std::wstring route = RouteObjectForFailure(routes, failureReason);
    if (route.empty()) {
        out.ok = false;
        out.errorCode = L"RECOVERY_ROUTE_NOT_FOUND";
        out.errorMessage = L"No recovery route for failure reason: " + failureReason;
        out.dataJson = L"{\"failure_reason\":" + JsonString(failureReason) + L"}";
        return out;
    }

    std::wstring strategy = JsonGetString(route, L"strategy");
    int routeMaxAttempts = JsonGetInt(route, L"max_attempts", 0);
    if (!IsLowRiskAutoRecovery(strategy)) {
        out.ok = false;
        out.errorCode = L"RECOVERY_REQUIRES_ESCALATION_OR_STOP";
        out.errorMessage = L"Recovery strategy is not low-risk automatic recovery: " + strategy;
        out.dataJson = L"{\"failure_reason\":" + JsonString(failureReason)
            + L",\"strategy\":" + JsonString(strategy)
            + L",\"next_action\":" + JsonString(NextActionForStrategy(strategy))
            + L"}";
        return out;
    }
    if (routeMaxAttempts > 0 && attempt > routeMaxAttempts) {
        out.ok = false;
        out.errorCode = L"RETRY_BUDGET_EXHAUSTED";
        out.errorMessage = L"Recovery retry budget exhausted for failure reason: " + failureReason;
        out.dataJson = L"{\"failure_reason\":" + JsonString(failureReason)
            + L",\"strategy\":" + JsonString(strategy)
            + L",\"attempt\":" + std::to_wstring(attempt)
            + L",\"max_attempts\":" + std::to_wstring(routeMaxAttempts)
            + L"}";
        return out;
    }

    const RecoveryPolicy& policy = policyResult.policy;
    int waitMs = strategy == L"wait_and_retry" ? policy.retryBackoffMs * attempt : 0;
    if (policy.retryMaxWaitMs > 0 && waitMs > policy.retryMaxWaitMs) waitMs = policy.retryMaxWaitMs;
    std::wstring cacheState = JsonGetString(contextFile.content, L"cache_state");
    bool targetReady = JsonGetBool(contextFile.content, L"target_ready", false);
    bool cacheInvalidated = strategy == L"invalidate_cache";

    std::wstringstream data;
    data << L"{\"schema_version\":\"5.2.2\""
         << L",\"policy_id\":" << JsonString(policy.policyId)
         << L",\"failure_reason\":" << JsonString(failureReason)
         << L",\"strategy\":" << JsonString(strategy)
         << L",\"next_action\":" << JsonString(NextActionForStrategy(strategy))
         << L",\"attempt\":" << attempt
         << L",\"max_attempts\":" << routeMaxAttempts
         << L",\"max_total_recovery_ms\":" << policy.retryMaxTotalRecoveryMs
         << L",\"safe_to_retry\":true"
         << L",\"wait_ms\":" << waitMs
         << L",\"requires_reobserve\":" << (strategy == L"re_observe" || strategy == L"invalidate_cache" ? L"true" : L"false")
         << L",\"requires_relocate\":" << (strategy == L"re_locate" || strategy == L"invalidate_cache" ? L"true" : L"false")
         << L",\"cache_invalidated\":" << (cacheInvalidated ? L"true" : L"false")
         << L",\"context\":{\"scene_state\":" << JsonString(sceneState)
         << L",\"target_ready\":" << (targetReady ? L"true" : L"false")
         << L",\"cache_state\":" << JsonString(cacheState)
         << L"}"
         << L",\"audit_record\":{\"recovery_attempt_id\":"
         << JsonString(policy.policyId + L":" + failureReason + L":" + std::to_wstring(attempt))
         << L",\"recorded\":true"
         << L",\"artifact_dir\":" << JsonString(policy.artifactDir)
         << L"}"
         << L"}";
    out.ok = true;
    out.dataJson = data.str();
    return out;
}

EscalationRequestResult CreateEscalationRequest(
    const std::wstring& reason,
    const std::wstring& currentTask,
    const std::wstring& currentStep,
    const std::wstring& contextPath) {
    EscalationRequestResult out;
    if (reason.empty() || currentTask.empty() || currentStep.empty() || contextPath.empty()) {
        out.ok = false;
        out.errorCode = L"INVALID_ARGUMENT";
        out.errorMessage = L"EscalationRequest requires reason, current_task, current_step, and context.";
        out.dataJson = L"{}";
        return out;
    }

    FileReadResult contextFile = ReadTextFile(contextPath);
    if (!contextFile.ok) {
        out.ok = false;
        out.errorCode = contextFile.errorCode.empty() ? L"FILE_READ_FAILED" : contextFile.errorCode;
        out.errorMessage = L"Could not read escalation context file: " + contextFile.error;
        out.dataJson = L"{\"context\":" + JsonString(contextPath) + L"}";
        return out;
    }

    const std::wstring& json = contextFile.content;
    std::wstring sceneState = JsonGetString(json, L"scene_state");
    std::wstring riskLevel = JsonGetString(json, L"risk_level");
    std::wstring screenshotArtifact = JsonGetString(json, L"screenshot_artifact");
    std::wstring elementGraphArtifact = JsonGetString(json, L"element_graph_artifact");
    std::wstring blockType = JsonGetString(json, L"block_type");
    bool agentProviderAvailable = JsonGetBool(json, L"agent_provider_available", false);
    std::wstring candidates = JsonGetArray(json, L"candidates");
    int candidateCount = CountObjects(candidates);

    if (sceneState.empty()) sceneState = L"unknown";
    if (riskLevel.empty()) riskLevel = L"medium";

    std::vector<std::wstring> allowedRoutes;
    std::wstring recommendedAction;
    std::wstring fallback = L"ask_user_or_stop";
    if (IsSafeStopReason(reason) || IsSafeStopReason(blockType) || sceneState == L"blocked" || riskLevel == L"high") {
        allowedRoutes = {L"stop"};
        recommendedAction = L"stop";
        fallback = L"stop";
    } else if (reason == L"semantic_unresolved" && agentProviderAvailable) {
        allowedRoutes = {L"escalate_to_agent", L"ask_user", L"stop"};
        recommendedAction = L"escalate_to_agent";
        fallback = L"ask_user_or_stop";
    } else if (reason == L"unknown_scene") {
        allowedRoutes = {L"ask_user", L"stop"};
        recommendedAction = L"ask_user";
    } else if (reason == L"multiple_candidates_low_confidence" && agentProviderAvailable) {
        allowedRoutes = {L"escalate_to_agent", L"ask_user", L"stop"};
        recommendedAction = L"escalate_to_agent";
    } else {
        allowedRoutes = {L"ask_user", L"stop"};
        recommendedAction = L"ask_user";
    }

    std::wstringstream data;
    data << L"{\"schema_version\":\"5.2.3\""
         << L",\"reason\":" << JsonString(reason)
         << L",\"current_task\":" << JsonString(currentTask)
         << L",\"current_step\":" << JsonString(currentStep)
         << L",\"scene_state\":" << JsonString(sceneState)
         << L",\"candidate_count\":" << candidateCount
         << L",\"candidates\":" << RawOrEmptyArray(candidates)
         << L",\"screenshot_artifact\":" << JsonString(screenshotArtifact)
         << L",\"element_graph_artifact\":" << JsonString(elementGraphArtifact)
         << L",\"risk_level\":" << JsonString(riskLevel)
         << L",\"agent_provider_available\":" << (agentProviderAvailable ? L"true" : L"false")
         << L",\"allowed_routes\":" << StringArrayJson(allowedRoutes)
         << L",\"recommended_action\":" << JsonString(recommendedAction)
         << L",\"fallback_if_provider_unavailable\":" << JsonString(fallback)
         << L",\"llm_or_vlm_call_count\":0"
         << L"}";

    out.ok = true;
    out.dataJson = data.str();
    return out;
}

SafeStopCheckResult CheckSafeStop(const std::wstring& reason, const std::wstring& contextPath) {
    SafeStopCheckResult out;
    if (reason.empty()) {
        out.ok = false;
        out.errorCode = L"INVALID_ARGUMENT";
        out.errorMessage = L"safe-stop-check requires reason.";
        out.dataJson = L"{}";
        return out;
    }

    std::wstring sceneState;
    std::wstring blockType;
    std::wstring riskLevel;
    if (!contextPath.empty()) {
        FileReadResult contextFile = ReadTextFile(contextPath);
        if (!contextFile.ok) {
            out.ok = false;
            out.errorCode = contextFile.errorCode.empty() ? L"FILE_READ_FAILED" : contextFile.errorCode;
            out.errorMessage = L"Could not read safe stop context file: " + contextFile.error;
            out.dataJson = L"{\"context\":" + JsonString(contextPath) + L"}";
            return out;
        }
        sceneState = JsonGetString(contextFile.content, L"scene_state");
        blockType = JsonGetString(contextFile.content, L"block_type");
        riskLevel = JsonGetString(contextFile.content, L"risk_level");
    }

    bool safeStop = IsSafeStopReason(reason) || IsSafeStopReason(blockType) || sceneState == L"blocked" || riskLevel == L"high";
    std::wstring matched = IsSafeStopReason(reason) ? NormalizeToken(reason) : NormalizeToken(blockType);
    if (matched.empty() && sceneState == L"blocked") matched = L"blocked_scene";
    if (matched.empty() && riskLevel == L"high") matched = L"high_risk";

    std::wstringstream data;
    data << L"{\"schema_version\":\"5.2.4\""
         << L",\"reason\":" << JsonString(reason)
         << L",\"matched_stop\":" << JsonString(matched)
         << L",\"scene_state\":" << JsonString(sceneState)
         << L",\"block_type\":" << JsonString(blockType)
         << L",\"risk_level\":" << JsonString(riskLevel)
         << L",\"safe_stop\":" << (safeStop ? L"true" : L"false")
         << L",\"recovery_allowed\":" << (safeStop ? L"false" : L"true")
         << L",\"escalation_allowed\":" << (safeStop ? L"false" : L"true")
         << L",\"recommended_action\":" << JsonString(safeStop ? L"stop" : L"continue_policy_evaluation")
         << L",\"llm_or_vlm_call_count\":0"
         << L"}";
    out.ok = true;
    out.dataJson = data.str();
    return out;
}
