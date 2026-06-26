#include "TaskConfirmation.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <cwctype>
#include <fstream>
#include <sstream>
#include <vector>
#include <windows.h>

namespace {

std::wstring NormalizeAction(std::wstring value) {
    for (wchar_t& ch : value) {
        if (ch == L'-' || ch == L'_') ch = L' ';
        else ch = static_cast<wchar_t>(towlower(ch));
    }
    while (value.find(L"  ") != std::wstring::npos) {
        value.replace(value.find(L"  "), 2, L" ");
    }
    return value;
}

bool Contains(const std::wstring& value, const std::wstring& needle) {
    return value.find(needle) != std::wstring::npos;
}

bool IsPublicProfile(const std::wstring& profile) {
    return profile == L"PUBLIC_RELEASE" || profile == L"PUBLIC" || profile == L"RELEASE";
}

bool IsBlockedAction(const std::wstring& action, const std::wstring& permissionProfile, std::wstring& reason) {
    if (Contains(action, L"captcha")) {
        reason = L"captcha";
        return true;
    }
    if (Contains(action, L"anti cheat") || Contains(action, L"anticheat")) {
        reason = L"anti_cheat";
        return true;
    }
    if (Contains(action, L"proctor")) {
        reason = L"proctoring";
        return true;
    }
    if (Contains(action, L"credential") || Contains(action, L"password") || Contains(action, L"security challenge")) {
        reason = L"credential_or_security_challenge";
        return true;
    }
    if (IsPublicProfile(permissionProfile) &&
        (Contains(action, L"real exam") || Contains(action, L"hiring") || Contains(action, L"assessment") ||
         Contains(action, L"certification") || Contains(action, L"rated contest"))) {
        reason = L"public_profile_assessment_restriction";
        return true;
    }
    return false;
}

bool IsHighRiskAction(const std::wstring& action) {
    return Contains(action, L"send email") ||
           Contains(action, L"submit external form") ||
           Contains(action, L"delete file") ||
           Contains(action, L"overwrite file") ||
           Contains(action, L"external upload") ||
           Contains(action, L"upload") ||
           Contains(action, L"external download") ||
           Contains(action, L"download") ||
           Contains(action, L"account setting change") ||
           Contains(action, L"account settings") ||
           Contains(action, L"public posting") ||
           Contains(action, L"post publicly") ||
           Contains(action, L"payment-like") ||
           Contains(action, L"payment");
}

bool IsMediumRiskAction(const std::wstring& action) {
    return Contains(action, L"external") ||
           Contains(action, L"browser") ||
           Contains(action, L"url") ||
           Contains(action, L"launch app") ||
           Contains(action, L"clipboard");
}

std::vector<std::wstring> SplitCsv(const std::wstring& value) {
    std::vector<std::wstring> parts;
    std::wstring current;
    for (wchar_t ch : value) {
        if (ch == L',') {
            if (!current.empty()) parts.push_back(current);
            current.clear();
        } else if (!iswspace(ch) || !current.empty()) {
            current += ch;
        }
    }
    while (!current.empty() && iswspace(current.back())) current.pop_back();
    if (!current.empty()) parts.push_back(current);
    return parts;
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

std::wstring SanitizeId(std::wstring value) {
    for (wchar_t& ch : value) {
        if (!(iswalnum(ch) || ch == L'-' || ch == L'_')) ch = L'_';
    }
    if (value.empty()) value = L"confirmation";
    return value;
}

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

bool WriteWideTextFile(const std::wstring& path, const std::wstring& content, std::wstring& error) {
    auto toUtf8 = [](const std::wstring& value) {
        if (value.empty()) return std::string();
        int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (size <= 0) return std::string();
        std::string out(static_cast<size_t>(size - 1), '\0');
        WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, out.data(), size, nullptr, nullptr);
        return out;
    };
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        error = L"Could not open file for writing: " + path;
        return false;
    }
    std::string utf8 = toUtf8(content);
    out.write(utf8.data(), static_cast<std::streamsize>(utf8.size()));
    if (!out.good()) {
        error = L"Could not write file: " + path;
        return false;
    }
    return true;
}

}  // namespace

RiskActionClassification ClassifyRiskAction(const std::wstring& action, const std::wstring& permissionProfile) {
    RiskActionClassification result;
    result.action = action;
    result.permissionProfile = permissionProfile.empty() ? L"DEFAULT" : permissionProfile;
    result.normalizedAction = NormalizeAction(action);

    std::wstring blockedReason;
    if (IsBlockedAction(result.normalizedAction, result.permissionProfile, blockedReason)) {
        result.riskLevel = L"blocked";
        result.blocked = true;
        result.requiresConfirmation = false;
        result.allowedAfterConfirmation = false;
        result.blockedReason = blockedReason;
    } else if (IsHighRiskAction(result.normalizedAction)) {
        result.riskLevel = L"high";
        result.blocked = false;
        result.requiresConfirmation = true;
        result.allowedAfterConfirmation = true;
    } else if (IsMediumRiskAction(result.normalizedAction)) {
        result.riskLevel = L"medium";
        result.blocked = false;
        result.requiresConfirmation = false;
        result.allowedAfterConfirmation = true;
    } else {
        result.riskLevel = L"low";
        result.blocked = false;
        result.requiresConfirmation = false;
        result.allowedAfterConfirmation = true;
    }

    std::wstringstream json;
    json << L"{\"schema_version\":\"5.3.1\""
         << L",\"action\":" << JsonString(result.action)
         << L",\"normalized_action\":" << JsonString(result.normalizedAction)
         << L",\"permission_profile\":" << JsonString(result.permissionProfile)
         << L",\"risk_level\":" << JsonString(result.riskLevel)
         << L",\"requires_confirmation\":" << (result.requiresConfirmation ? L"true" : L"false")
         << L",\"blocked\":" << (result.blocked ? L"true" : L"false")
         << L",\"allowed_after_confirmation\":" << (result.allowedAfterConfirmation ? L"true" : L"false")
         << L",\"blocked_reason\":" << JsonString(result.blockedReason)
         << L"}";
    result.dataJson = json.str();
    return result;
}

ConfirmationRequestCreateResult CreateConfirmationRequest(
    const std::wstring& action,
    const std::wstring& riskLevel,
    const std::wstring& summary,
    const std::wstring& targetWindow,
    const std::wstring& screenshot,
    const std::wstring& involvedFiles,
    const std::wstring& destination,
    int timeoutMs,
    const std::wstring& allowedResponses) {
    ConfirmationRequestCreateResult out;
    if (action.empty() || riskLevel.empty() || summary.empty() || targetWindow.empty() || timeoutMs <= 0) {
        out.ok = false;
        out.errorCode = L"CONFIRMATION_REQUEST_SCHEMA_INVALID";
        out.errorMessage = L"ConfirmationRequest requires action, risk_level, summary, target_window, and positive timeout_ms.";
        out.dataJson = L"{}";
        return out;
    }
    if (riskLevel != L"low" && riskLevel != L"medium" && riskLevel != L"high" && riskLevel != L"blocked") {
        out.ok = false;
        out.errorCode = L"CONFIRMATION_REQUEST_SCHEMA_INVALID";
        out.errorMessage = L"risk_level must be low, medium, high, or blocked.";
        out.dataJson = L"{}";
        return out;
    }

    std::vector<std::wstring> files = SplitCsv(involvedFiles);
    std::vector<std::wstring> responses = SplitCsv(allowedResponses.empty() ? L"confirm,reject" : allowedResponses);
    bool hasConfirm = false;
    bool hasReject = false;
    for (const auto& response : responses) {
        if (response == L"confirm") hasConfirm = true;
        if (response == L"reject") hasReject = true;
    }
    if (!hasConfirm || !hasReject) {
        out.ok = false;
        out.errorCode = L"CONFIRMATION_REQUEST_SCHEMA_INVALID";
        out.errorMessage = L"allowed_responses must include confirm and reject.";
        out.dataJson = L"{}";
        return out;
    }

    ULONGLONG tick = GetTickCount64();
    std::wstring auditId = SanitizeId(L"confirm_" + NormalizeAction(action) + L"_" + std::to_wstring(tick));
    std::wstring root = ProjectRootPath();
    std::wstring relDir = L"artifacts/dev5.3.2/confirmation_requests";
    std::wstring absDir = root + L"\\" + relDir;
    CreateDirectoryW((root + L"\\artifacts").c_str(), nullptr);
    CreateDirectoryW((root + L"\\artifacts\\dev5.3.2").c_str(), nullptr);
    CreateDirectoryW(absDir.c_str(), nullptr);

    std::wstring requestRel = relDir + L"/" + auditId + L".json";
    std::wstring reportRel = relDir + L"/" + auditId + L".md";
    std::wstring requestAbs = root + L"\\" + requestRel;
    std::wstring reportAbs = root + L"\\" + reportRel;

    std::wstringstream request;
    request << L"{\"schema_version\":\"5.3.2\""
            << L",\"action\":" << JsonString(action)
            << L",\"risk_level\":" << JsonString(riskLevel)
            << L",\"summary\":" << JsonString(summary)
            << L",\"target_window\":" << JsonString(targetWindow)
            << L",\"screenshot\":" << JsonString(screenshot)
            << L",\"involved_files\":" << StringArrayJson(files)
            << L",\"destination\":" << JsonString(destination)
            << L",\"timeout_ms\":" << timeoutMs
            << L",\"allowed_responses\":" << StringArrayJson(responses)
            << L",\"audit_id\":" << JsonString(auditId)
            << L",\"status\":\"pending\""
            << L"}";

    std::wstringstream report;
    report << L"# Confirmation Request\n\n"
           << L"- Audit ID: `" << auditId << L"`\n"
           << L"- Action: " << action << L"\n"
           << L"- Risk: " << riskLevel << L"\n"
           << L"- Target window: " << targetWindow << L"\n"
           << L"- Destination/recipient: " << destination << L"\n"
           << L"- Screenshot: `" << screenshot << L"`\n"
           << L"- Timeout ms: " << timeoutMs << L"\n"
           << L"- Status: pending\n\n"
           << L"## Summary\n\n" << summary << L"\n";

    std::wstring error;
    if (!WriteWideTextFile(requestAbs, request.str(), error) || !WriteWideTextFile(reportAbs, report.str(), error)) {
        out.ok = false;
        out.errorCode = L"FILE_WRITE_FAILED";
        out.errorMessage = error;
        out.dataJson = L"{\"audit_id\":" + JsonString(auditId) + L"}";
        return out;
    }

    std::wstringstream data;
    data << request.str().substr(0, request.str().size() - 1)
         << L",\"request_json\":" << JsonString(requestRel)
         << L",\"report_md\":" << JsonString(reportRel)
         << L"}";
    out.ok = true;
    out.dataJson = data.str();
    return out;
}

ConfirmationGateResult CheckConfirmationGate(
    const std::wstring& action,
    const std::wstring& riskLevel,
    const std::wstring& permissionProfile,
    const std::wstring& response,
    int timeoutMs,
    int elapsedMs) {
    ConfirmationGateResult out;
    if (action.empty()) {
        out.ok = false;
        out.errorCode = L"INVALID_ARGUMENT";
        out.errorMessage = L"confirmation-gate-check requires action.";
        out.dataJson = L"{}";
        return out;
    }
    if (timeoutMs <= 0) timeoutMs = 30000;
    if (elapsedMs < 0) elapsedMs = 0;

    RiskActionClassification classified = ClassifyRiskAction(action, permissionProfile);
    std::wstring effectiveRisk = riskLevel.empty() ? classified.riskLevel : riskLevel;
    bool blocked = classified.blocked || effectiveRisk == L"blocked";
    bool requiresConfirmation = blocked ? false : (classified.requiresConfirmation || effectiveRisk == L"high");
    bool timedOut = elapsedMs > timeoutMs;
    std::wstring decision;
    std::wstring reason;
    bool allowed = false;

    if (blocked) {
        decision = L"stopped";
        reason = classified.blockedReason.empty() ? L"blocked_action" : classified.blockedReason;
    } else if (timedOut) {
        decision = L"stopped";
        reason = L"confirmation_timeout";
    } else if (requiresConfirmation && response.empty()) {
        decision = L"blocked";
        reason = L"confirmation_required";
    } else if (requiresConfirmation && response == L"reject") {
        decision = L"stopped";
        reason = L"confirmation_rejected";
    } else if (requiresConfirmation && response == L"confirm") {
        decision = L"allowed";
        reason = L"confirmation_accepted";
        allowed = true;
    } else if (requiresConfirmation) {
        decision = L"blocked";
        reason = L"confirmation_required";
    } else {
        decision = L"allowed";
        reason = L"confirmation_not_required";
        allowed = true;
    }

    std::wstringstream json;
    json << L"{\"schema_version\":\"5.3.3\""
         << L",\"action\":" << JsonString(action)
         << L",\"permission_profile\":" << JsonString(permissionProfile.empty() ? L"DEFAULT" : permissionProfile)
         << L",\"risk_level\":" << JsonString(effectiveRisk)
         << L",\"requires_confirmation\":" << (requiresConfirmation ? L"true" : L"false")
         << L",\"response\":" << JsonString(response)
         << L",\"timeout_ms\":" << timeoutMs
         << L",\"elapsed_ms\":" << elapsedMs
         << L",\"timed_out\":" << (timedOut ? L"true" : L"false")
         << L",\"blocked\":" << (blocked ? L"true" : L"false")
         << L",\"allowed\":" << (allowed ? L"true" : L"false")
         << L",\"decision\":" << JsonString(decision)
         << L",\"reason\":" << JsonString(reason)
         << L"}";
    out.ok = true;
    out.dataJson = json.str();
    return out;
}

ConfirmationFlowRunResult RunLocalConfirmationFlow(const std::wstring& file, const std::wstring& response) {
    ConfirmationFlowRunResult out;
    FileReadResult flowFile = ReadTextFile(file);
    if (!flowFile.ok) {
        out.ok = false;
        out.errorCode = flowFile.errorCode.empty() ? L"FILE_READ_FAILED" : flowFile.errorCode;
        out.errorMessage = L"Could not read confirmation flow file: " + flowFile.error;
        out.dataJson = L"{\"file\":" + JsonString(file) + L"}";
        return out;
    }
    const std::wstring& json = flowFile.content;
    std::wstring flowId = JsonGetString(json, L"flow_id");
    std::wstring action = JsonGetString(json, L"action");
    std::wstring targetWindow = JsonGetString(json, L"target_window");
    std::wstring recipient = JsonGetString(json, L"recipient");
    std::wstring bodySummary = JsonGetString(json, L"body_summary");
    std::wstring attachment = JsonGetString(json, L"attachment");
    std::wstring screenshot = JsonGetString(json, L"screenshot");
    int timeoutMs = JsonGetInt(json, L"timeout_ms", 30000);
    if (flowId != L"local_mail_mock_send_confirm" || action.empty() || targetWindow.empty()) {
        out.ok = false;
        out.errorCode = L"CONFIRMATION_FLOW_INVALID";
        out.errorMessage = L"Unsupported or invalid local confirmation flow.";
        out.dataJson = L"{\"flow_id\":" + JsonString(flowId) + L"}";
        return out;
    }

    RiskActionClassification risk = ClassifyRiskAction(action, L"DEFAULT");
    ConfirmationRequestCreateResult request = CreateConfirmationRequest(
        action,
        risk.riskLevel,
        L"Pre-send review for local mail mock. " + bodySummary,
        targetWindow,
        screenshot,
        attachment,
        recipient,
        timeoutMs,
        L"confirm,reject");
    if (!request.ok) {
        out.ok = false;
        out.errorCode = request.errorCode;
        out.errorMessage = request.errorMessage;
        out.dataJson = request.dataJson;
        return out;
    }

    ConfirmationGateResult gate = CheckConfirmationGate(action, risk.riskLevel, L"DEFAULT", response, timeoutMs, 0);
    if (!gate.ok) {
        out.ok = false;
        out.errorCode = gate.errorCode;
        out.errorMessage = gate.errorMessage;
        out.dataJson = gate.dataJson;
        return out;
    }
    if (response.empty()) {
        out.ok = false;
        out.errorCode = L"CONFIRMATION_REQUIRED";
        out.errorMessage = L"local_mail_mock_send_confirm requires human confirmation before mock send.";
        out.dataJson = gate.dataJson;
        return out;
    }
    if (response != L"confirm") {
        out.ok = false;
        out.errorCode = L"CONFIRMATION_NOT_APPROVED";
        out.errorMessage = L"Confirmation was not approved.";
        out.dataJson = gate.dataJson;
        return out;
    }

    std::wstring root = ProjectRootPath();
    std::wstring relDir = L"artifacts/dev5.3.4/local_mail_mock_send_confirm";
    std::wstring absDir = root + L"\\" + relDir;
    CreateDirectoryW((root + L"\\artifacts").c_str(), nullptr);
    CreateDirectoryW((root + L"\\artifacts\\dev5.3.4").c_str(), nullptr);
    CreateDirectoryW(absDir.c_str(), nullptr);

    std::wstring attachmentRel = L"artifacts/dev5.3.4/mock_attachment.txt";
    std::wstring auditRel = relDir + L"/confirmation_audit.jsonl";
    std::wstring sentRel = relDir + L"/sent_state.json";
    std::wstring error;
    WriteWideTextFile(root + L"\\" + attachmentRel, L"local mock attachment\n", error);

    std::wstringstream audit;
    audit << L"{\"event\":\"compose_mock\",\"flow_id\":\"" << flowId << L"\"}\n"
          << L"{\"event\":\"attach_mock_file\",\"path\":" << JsonString(attachmentRel) << L"}\n"
          << L"{\"event\":\"pre_send_review\",\"target_window\":" << JsonString(targetWindow) << L"}\n"
          << L"{\"event\":\"confirmation_accepted\",\"response\":\"confirm\"}\n"
          << L"{\"event\":\"mock_send\",\"recipient\":" << JsonString(recipient) << L"}\n";
    std::wstringstream sent;
    sent << L"{\"schema_version\":\"5.3.4\",\"flow_id\":" << JsonString(flowId)
         << L",\"sent_state\":\"mock_sent\",\"real_email_sent\":false,\"recipient\":" << JsonString(recipient) << L"}";
    if (!WriteWideTextFile(root + L"\\" + auditRel, audit.str(), error) ||
        !WriteWideTextFile(root + L"\\" + sentRel, sent.str(), error)) {
        out.ok = false;
        out.errorCode = L"FILE_WRITE_FAILED";
        out.errorMessage = error;
        out.dataJson = L"{\"flow_id\":" + JsonString(flowId) + L"}";
        return out;
    }

    std::wstring requestJson = JsonGetString(request.dataJson, L"request_json");
    std::wstring reportMd = JsonGetString(request.dataJson, L"report_md");
    std::wstringstream data;
    data << L"{\"schema_version\":\"5.3.4\""
         << L",\"flow_id\":" << JsonString(flowId)
         << L",\"action\":" << JsonString(action)
         << L",\"risk_level\":" << JsonString(risk.riskLevel)
         << L",\"confirmation_decision\":\"allowed\""
         << L",\"sent_state\":\"mock_sent\""
         << L",\"real_email_sent\":false"
         << L",\"recipient\":" << JsonString(recipient)
         << L",\"confirmation_request\":" << JsonString(requestJson)
         << L",\"confirmation_report\":" << JsonString(reportMd)
         << L",\"confirmation_audit\":" << JsonString(auditRel)
         << L",\"sent_state_artifact\":" << JsonString(sentRel)
         << L"}";
    out.ok = true;
    out.dataJson = data.str();
    return out;
}
