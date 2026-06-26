#include "ValidationConsistencyChecker.h"

#include "EvidenceFingerprint.h"
#include "ProjectRoot.h"
#include "SimpleJson.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct ConsistencyResult {
    bool consistencyOk = false;
    std::vector<std::wstring> checkedFeatures;
    std::vector<std::wstring> missingEvidence;
    std::vector<std::wstring> statusConflicts;
    std::vector<std::wstring> hashMismatches;
    std::vector<std::wstring> staleEvidence;
    std::vector<std::wstring> unclassifiedArtifacts;
    std::wstring blockedReason;
    bool uiWorkflowExecuted = false;
};

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::wstring SlashPath(std::wstring value) {
    std::replace(value.begin(), value.end(), L'\\', L'/');
    return value;
}

std::wstring ReadOrEmpty(const std::wstring& path) {
    std::wstring text;
    std::wstring error;
    ReadValidationTextFile(path, text, error);
    return text;
}

std::wstring JoinEvidence(const std::wstring& evidencePath, const std::wstring& relativePath) {
    std::wstring rel = relativePath;
    std::replace(rel.begin(), rel.end(), L'/', L'\\');
    if (rel.size() >= 2 && rel[1] == L':') return ValidationNormalizePath(rel);
    std::wstring lower = ValidationToLower(SlashPath(rel));
    if (lower.rfind(L"artifacts/", 0) == 0 || lower.rfind(L"docs/", 0) == 0 || lower.rfind(L"src/", 0) == 0) {
        return ProjectPath(rel);
    }
    return ValidationJoinPath(evidencePath, rel);
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& value) {
    if (std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

std::wstring Trim(std::wstring value) {
    while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
    while (!value.empty() && iswspace(value.back())) value.pop_back();
    return value;
}

std::wstring ExtractMetadataValue(const std::wstring& text, const std::wstring& key) {
    std::wistringstream stream(text);
    std::wstring line;
    std::wstring needle = ValidationToLower(key + L":");
    while (std::getline(stream, line)) {
        std::wstring trimmed = Trim(line);
        std::wstring lower = ValidationToLower(trimmed);
        if (lower.rfind(needle, 0) == 0) {
            return Trim(trimmed.substr(needle.size()));
        }
    }
    return L"";
}

std::vector<int> ParseVersionParts(std::wstring value) {
    value = Trim(value);
    if (!value.empty() && (value[0] == L'v' || value[0] == L'V')) value.erase(value.begin());
    std::vector<int> parts;
    std::wstring current;
    for (wchar_t ch : value) {
        if (iswdigit(ch)) {
            current.push_back(ch);
        } else if (ch == L'.') {
            parts.push_back(current.empty() ? 0 : std::stoi(current));
            current.clear();
        } else {
            break;
        }
    }
    if (!current.empty() || !parts.empty()) {
        parts.push_back(current.empty() ? 0 : std::stoi(current));
    }
    while (parts.size() < 3) parts.push_back(0);
    return parts;
}

bool VersionAtLeast(const std::wstring& actual, const std::wstring& minimum) {
    std::vector<int> left = ParseVersionParts(actual);
    std::vector<int> right = ParseVersionParts(minimum);
    if (left.empty() || right.empty()) return false;
    size_t count = left.size() > right.size() ? left.size() : right.size();
    left.resize(count, 0);
    right.resize(count, 0);
    for (size_t i = 0; i < count; ++i) {
        if (left[i] > right[i]) return true;
        if (left[i] < right[i]) return false;
    }
    return true;
}

void RequireFile(const std::wstring& evidencePath, const std::wstring& relativePath, ConsistencyResult& result) {
    std::wstring path = JoinEvidence(evidencePath, relativePath);
    if (!ValidationFileExists(path)) {
        AddUnique(result.missingEvidence, relativePath);
    }
}

std::wstring FindFirstExisting(const std::wstring& evidencePath, const std::vector<std::wstring>& candidates) {
    for (const std::wstring& candidate : candidates) {
        std::wstring path = JoinEvidence(evidencePath, candidate);
        if (ValidationFileExists(path)) {
            return path;
        }
    }
    return L"";
}

std::vector<std::wstring> ExtractEvidenceIndexReferences(const std::wstring& indexText) {
    std::vector<std::wstring> refs;
    std::wistringstream stream(indexText);
    std::wstring line;
    while (std::getline(stream, line)) {
        std::wstring trimmed = line;
        while (!trimmed.empty() && iswspace(trimmed.front())) trimmed.erase(trimmed.begin());
        if (trimmed.empty() || trimmed[0] != L'-') continue;

        size_t firstTick = trimmed.find(L'`');
        if (firstTick != std::wstring::npos) {
            size_t secondTick = trimmed.find(L'`', firstTick + 1);
            if (secondTick != std::wstring::npos && secondTick > firstTick + 1) {
                refs.push_back(trimmed.substr(firstTick + 1, secondTick - firstTick - 1));
                continue;
            }
        }

        trimmed.erase(trimmed.begin());
        while (!trimmed.empty() && iswspace(trimmed.front())) trimmed.erase(trimmed.begin());
        if (trimmed.empty()) continue;
        if (trimmed.find(L": ") != std::wstring::npos) continue;
        if (trimmed.find(L' ') != std::wstring::npos && trimmed.find(L'/') == std::wstring::npos && trimmed.find(L'\\') == std::wstring::npos && trimmed.find(L'.') == std::wstring::npos) continue;
        refs.push_back(trimmed);
    }
    return refs;
}

void CheckEvidenceIndex(const std::wstring& evidencePath, ConsistencyResult& result) {
    std::wstring indexPath = JoinEvidence(evidencePath, L"evidence_index.md");
    if (!ValidationFileExists(indexPath)) return;
    std::wstring indexText = ReadOrEmpty(indexPath);
    for (const std::wstring& reference : ExtractEvidenceIndexReferences(indexText)) {
        std::wstring path = JoinEvidence(evidencePath, reference);
        if (!ValidationFileExists(path) && !ValidationDirectoryExists(path)) {
            AddUnique(result.missingEvidence, L"evidence_index_reference:" + reference);
        }
    }
}

bool JsonBool(const simplejson::Value& value, const std::wstring& key, bool def = false) {
    return simplejson::GetBool(value, key, def);
}

std::wstring JsonString(const simplejson::Value& value, const std::wstring& key) {
    return simplejson::GetString(value, key, L"");
}

bool CheckCaseResultFields(const simplejson::Value& root, const std::vector<std::wstring>& fields) {
    for (const std::wstring& field : fields) {
        if (!JsonBool(root, field, false)) {
            return false;
        }
    }
    return true;
}

void CheckMoveAndScrollEvidence(const std::wstring& evidencePath, ConsistencyResult& result) {
    std::wstring finalText = ReadOrEmpty(JoinEvidence(evidencePath, L"final_status_report.md"));
    if (!finalText.empty()) {
        if (!ValidationContainsNoCase(finalText, L"case_04_move_file") ||
            !ValidationContainsNoCase(finalText, L"VERIFY_MOVE_FAILED")) {
            AddUnique(result.statusConflicts, L"move_file_original_blocker_missing");
        }
        if (!ValidationContainsNoCase(finalText, L"case_06_scroll_and_locate") ||
            !ValidationContainsNoCase(finalText, L"FAIL_TARGET_NOT_FOUND")) {
            AddUnique(result.statusConflicts, L"scroll_and_locate_original_blocker_missing");
        }
    }

    std::wstring moveResultPath = JoinEvidence(evidencePath, L"acceptance/runner/case_04_move_file/result.json");
    if (ValidationFileExists(moveResultPath)) {
        std::wstring text = ReadOrEmpty(moveResultPath);
        simplejson::ParseResult parsed = simplejson::Parse(text);
        if (!parsed.ok || !parsed.root.IsObject()) {
            AddUnique(result.statusConflicts, L"move_file_result_json_invalid");
        } else {
            bool ok = CheckCaseResultFields(parsed.root, {
                L"source_selected_by_mouse",
                L"source_selection_verified",
                L"cut_sent",
                L"paste_sent",
                L"move_action_executed",
                L"move_result_verified",
                L"runtime_session_used",
                L"runtime_context_guard_used",
                L"step_contract_validated"
            }) &&
            JsonString(parsed.root, L"final_status") == L"PASS" &&
            !JsonBool(parsed.root, L"power_shell_file_operation_used", false) &&
            !JsonBool(parsed.root, L"direct_file_api_used", false);
            if (!ok) AddUnique(result.statusConflicts, L"move_file_rerun_evidence_incomplete");
        }
    } else if (!ValidationContainsNoCase(finalText, L"move_file_rerun: PASS") &&
               !ValidationContainsNoCase(finalText, L"case_04_move_file`: PASS") &&
               !ValidationContainsNoCase(finalText, L"case_04_move_file: PASS")) {
        AddUnique(result.missingEvidence, L"acceptance/runner/case_04_move_file/result.json");
    }

    std::wstring scrollResultPath = JoinEvidence(evidencePath, L"acceptance/runner/case_06_scroll_and_locate/result.json");
    if (ValidationFileExists(scrollResultPath)) {
        std::wstring text = ReadOrEmpty(scrollResultPath);
        simplejson::ParseResult parsed = simplejson::Parse(text);
        if (!parsed.ok || !parsed.root.IsObject()) {
            AddUnique(result.statusConflicts, L"scroll_and_locate_result_json_invalid");
        } else {
            bool ok = CheckCaseResultFields(parsed.root, {
                L"list_area_located",
                L"list_area_focus_verified",
                L"scroll_progress_detected",
                L"scroll_position_changed",
                L"target_found",
                L"target_clicked_or_verified",
                L"runtime_context_guard_each_iteration"
            }) &&
            JsonString(parsed.root, L"final_status") == L"PASS" &&
            !JsonBool(parsed.root, L"stale_rect_used", false) &&
            !JsonBool(parsed.root, L"power_shell_file_operation_used", false) &&
            !JsonBool(parsed.root, L"direct_file_api_used", false);
            if (!ok) AddUnique(result.statusConflicts, L"scroll_and_locate_rerun_evidence_incomplete");
        }
    } else if (!ValidationContainsNoCase(finalText, L"scroll_and_locate_rerun: PASS") &&
               !ValidationContainsNoCase(finalText, L"case_06_scroll_and_locate`: PASS") &&
               !ValidationContainsNoCase(finalText, L"case_06_scroll_and_locate: PASS")) {
        AddUnique(result.missingEvidence, L"acceptance/runner/case_06_scroll_and_locate/result.json");
    }
}

void CheckFullRegression(const std::wstring& evidencePath, ConsistencyResult& result) {
    std::wstring fullPath = JoinEvidence(evidencePath, L"full_regression_rerun_result.json");
    if (!ValidationFileExists(fullPath)) return;
    std::wstring text = ReadOrEmpty(fullPath);
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        AddUnique(result.statusConflicts, L"full_regression_result_json_invalid");
        return;
    }
    bool ok = simplejson::GetString(parsed.root, L"final_status", L"") == L"PASS" &&
        JsonBool(parsed.root, L"started_from_beginning", false) &&
        JsonBool(parsed.root, L"full_regression_completed", false) &&
        simplejson::GetInt(parsed.root, L"commands_completed", simplejson::GetInt(parsed.root, L"completed_count", 0)) == 47 &&
        simplejson::GetInt(parsed.root, L"commands_failed", simplejson::GetInt(parsed.root, L"failed_count", 1)) == 0;
    if (!ok) {
        AddUnique(result.statusConflicts, L"full_regression_result_not_pass");
    }
}

void CheckStatusConsistency(const std::wstring& featureId, const std::wstring& evidencePath, ConsistencyResult& result) {
    std::wstring finalText = ReadOrEmpty(JoinEvidence(evidencePath, L"final_status_report.md"));
    std::wstring gatePath = FindFirstExisting(evidencePath, {
        L"v6_7_0_rerun_acceptance_gate_report.md",
        L"acceptance_gate_report.md",
        L"gate_report.md"
    });
    std::wstring gateText = gatePath.empty() ? L"" : ReadOrEmpty(gatePath);

    std::wstring agentsText = ReadOrEmpty(ProjectPath(L"AGENTS.md"));
    std::wstring featureVersion = EvidenceFeatureVersion(featureId);
    std::wstring trustedVersion = ExtractMetadataValue(agentsText, L"current_trusted_version");
    if (featureVersion.empty() || !VersionAtLeast(trustedVersion, featureVersion)) {
        AddUnique(result.statusConflicts, L"agents_trusted_version_below_feature_version");
    }
    if (!featureVersion.empty() && !finalText.empty() &&
        !ValidationContainsNoCase(finalText, L"current_trusted_version: " + featureVersion) &&
        !ValidationContainsNoCase(finalText, L"VERSION: " + featureVersion)) {
        AddUnique(result.statusConflicts, L"final_status_trusted_version_missing");
    }
    if (!finalText.empty() && !ValidationContainsNoCase(finalText, L"Final status: PASS") &&
        !ValidationContainsNoCase(finalText, L"final_status: PASS")) {
        AddUnique(result.statusConflicts, L"final_status_not_pass");
    }
    if (!gateText.empty() && !ValidationContainsNoCase(gateText, L"Status: PASS")) {
        AddUnique(result.statusConflicts, L"gate_status_not_pass");
    }
    if (!finalText.empty() && !gateText.empty() &&
        (ValidationContainsNoCase(finalText, L"Final status: PASS") || ValidationContainsNoCase(finalText, L"final_status: PASS")) &&
        ValidationContainsNoCase(gateText, L"Status: BLOCKED")) {
        AddUnique(result.statusConflicts, L"final_status_gate_conflict");
    }
}

void CheckRcCheck(const std::wstring& evidencePath, ConsistencyResult& result) {
    std::wstring rcPath = JoinEvidence(evidencePath, L"rc_check_result.json");
    if (ValidationFileExists(rcPath)) {
        simplejson::ParseResult parsed = simplejson::Parse(ReadOrEmpty(rcPath));
        if (parsed.ok && parsed.root.IsObject()) {
            std::wstring status = simplejson::GetString(parsed.root, L"status", L"");
            if (ValidationToLower(status) == L"pass") {
                AddUnique(result.statusConflicts, L"rc_check_wrapped_as_pass");
            }
        }
    }
    std::wstring finalText = ReadOrEmpty(JoinEvidence(evidencePath, L"final_status_report.md"));
    if (ValidationContainsNoCase(finalText, L"rc_check true status: PASS") ||
        ValidationContainsNoCase(finalText, L"rc_check_status: PASS")) {
        AddUnique(result.statusConflicts, L"rc_check_wrapped_as_pass");
    }
}

void CheckBlockedEvidence(const std::wstring& blockedEvidence, ConsistencyResult& result) {
    if (blockedEvidence.empty()) {
        AddUnique(result.missingEvidence, L"old_blocked_evidence_path");
        return;
    }
    std::wstring finalPath = JoinEvidence(blockedEvidence, L"final_status_report.md");
    std::wstring gatePath = JoinEvidence(blockedEvidence, L"v6_7_0_acceptance_gate_report.md");
    std::wstring fullPath = JoinEvidence(blockedEvidence, L"full_regression/full_regression_report.md");
    std::wstring indexPath = JoinEvidence(blockedEvidence, L"evidence_index.md");
    if (!ValidationFileExists(finalPath)) AddUnique(result.missingEvidence, L"old_blocked:final_status_report.md");
    if (!ValidationFileExists(gatePath)) AddUnique(result.missingEvidence, L"old_blocked:v6_7_0_acceptance_gate_report.md");
    if (!ValidationFileExists(fullPath)) AddUnique(result.missingEvidence, L"old_blocked:full_regression/full_regression_report.md");
    if (!ValidationFileExists(indexPath)) AddUnique(result.missingEvidence, L"old_blocked:evidence_index.md");

    std::wstring finalText = ReadOrEmpty(finalPath);
    std::wstring gateText = ReadOrEmpty(gatePath);
    if (!ValidationContainsNoCase(finalText, L"BLOCKED")) {
        AddUnique(result.statusConflicts, L"old_blocked_evidence_not_blocked");
    }
    if (!ValidationContainsNoCase(finalText, L"VERIFY_MOVE_FAILED") ||
        !ValidationContainsNoCase(finalText, L"FAIL_TARGET_NOT_FOUND")) {
        AddUnique(result.statusConflicts, L"old_blocked_reasons_missing");
    }
    if (!gateText.empty() && ValidationContainsNoCase(gateText, L"Status: PASS")) {
        AddUnique(result.statusConflicts, L"old_blocked_gate_overwritten_as_pass");
    }
}

void CheckRawCompletedUnverified(const std::wstring& evidencePath, ConsistencyResult& result) {
    std::wstring finalText = ReadOrEmpty(JoinEvidence(evidencePath, L"final_status_report.md"));
    std::wstring gateText = ReadOrEmpty(FindFirstExisting(evidencePath, {
        L"v6_7_0_rerun_acceptance_gate_report.md",
        L"acceptance_gate_report.md",
        L"gate_report.md"
    }));
    std::wstring combined = finalText + L"\n" + gateText;
    if (ValidationContainsNoCase(combined, L"RAW_COMPLETED_UNVERIFIED as PASS: true") ||
        ValidationContainsNoCase(combined, L"RAW_COMPLETED_UNVERIFIED: PASS") ||
        ValidationContainsNoCase(combined, L"final_status: RAW_COMPLETED_UNVERIFIED")) {
        AddUnique(result.statusConflicts, L"raw_completed_unverified_as_pass");
    }
}

void CheckRuntimeSessionsClassification(ConsistencyResult& result) {
    std::wstring manifest = ProjectPath(L"artifacts\\dev6.7.0_final_closure\\runtime_sessions_manifest.csv");
    if (!ValidationFileExists(manifest)) {
        AddUnique(result.unclassifiedArtifacts, L"runtime_sessions_manifest_missing");
    }
}

void CheckFingerprint(
    const std::wstring& featureId,
    const std::wstring& evidencePath,
    const std::wstring& fingerprintPath,
    ConsistencyResult& result) {
    if (!ValidationFileExists(fingerprintPath)) {
        AddUnique(result.missingEvidence, L"fingerprint_baseline");
        return;
    }
    simplejson::ParseResult baselineParsed = simplejson::Parse(ReadOrEmpty(fingerprintPath));
    if (!baselineParsed.ok || !baselineParsed.root.IsObject()) {
        AddUnique(result.statusConflicts, L"fingerprint_baseline_invalid");
        return;
    }
    EvidenceFingerprintResult current = CreateEvidenceFingerprint(featureId, evidencePath);
    if (!current.ok) {
        AddUnique(result.missingEvidence, L"fingerprint_evidence_source");
        return;
    }
    const simplejson::Value& baseline = baselineParsed.root;
    const std::vector<std::wstring> keys = {
        L"feature_id",
        L"feature_version",
        L"input_spec_hash",
        L"step_contract_hash",
        L"execution_summary_hash",
        L"verification_summary_hash",
        L"final_status_hash",
        L"artifact_manifest_hash"
    };
    simplejson::ParseResult currentParsed = simplejson::Parse(current.fingerprintJson);
    if (!currentParsed.ok || !currentParsed.root.IsObject()) {
        AddUnique(result.statusConflicts, L"fingerprint_current_invalid");
        return;
    }
    for (const std::wstring& key : keys) {
        if (simplejson::GetString(baseline, key, L"") != simplejson::GetString(currentParsed.root, key, L"")) {
            AddUnique(result.hashMismatches, key);
        }
    }
    if (simplejson::GetBool(baseline, L"ui_workflow_executed", false)) {
        AddUnique(result.statusConflicts, L"fingerprint_claimed_ui_execution");
    }
    if (simplejson::GetBool(baseline, L"fingerprint_is_execution_result", false)) {
        AddUnique(result.statusConflicts, L"fingerprint_claimed_execution_result");
    }
}

std::wstring ResultToJson(const ConsistencyResult& result) {
    std::wstringstream json;
    json << L"{"
         << L"\"consistency_ok\":" << simplejson::Bool(result.consistencyOk)
         << L",\"checked_features\":" << ValidationJsonArray(result.checkedFeatures)
         << L",\"missing_evidence\":" << ValidationJsonArray(result.missingEvidence)
         << L",\"status_conflicts\":" << ValidationJsonArray(result.statusConflicts)
         << L",\"hash_mismatches\":" << ValidationJsonArray(result.hashMismatches)
         << L",\"stale_evidence\":" << ValidationJsonArray(result.staleEvidence)
         << L",\"unclassified_artifacts\":" << ValidationJsonArray(result.unclassifiedArtifacts)
         << L",\"blocked_reason\":" << simplejson::Quote(result.blockedReason)
         << L",\"ui_workflow_executed\":" << simplejson::Bool(result.uiWorkflowExecuted)
         << L"}";
    return json.str();
}

std::wstring SelectBlockedReason(const ConsistencyResult& result) {
    if (!result.missingEvidence.empty()) return L"BLOCKED_PREFLIGHT_EVIDENCE_MISSING";
    if (!result.hashMismatches.empty()) return L"BLOCKED_PREFLIGHT_FINGERPRINT_MISMATCH";
    if (std::find(result.statusConflicts.begin(), result.statusConflicts.end(), L"old_blocked_evidence_not_blocked") != result.statusConflicts.end() ||
        std::find(result.statusConflicts.begin(), result.statusConflicts.end(), L"old_blocked_gate_overwritten_as_pass") != result.statusConflicts.end()) {
        return L"BLOCKED_PREFLIGHT_BLOCKED_HISTORY_LOST";
    }
    if (!result.statusConflicts.empty()) return L"BLOCKED_PREFLIGHT_STATUS_CONFLICT";
    if (!result.unclassifiedArtifacts.empty()) return L"BLOCKED_PREFLIGHT_EVIDENCE_MISSING";
    if (!result.staleEvidence.empty()) return L"BLOCKED_PREFLIGHT_STATUS_CONFLICT";
    return L"";
}

}  // namespace

int CommandValidationConsistencyCheck(int argc, wchar_t** argv) {
    const std::wstring command = L"validation-consistency-check";
    ULONGLONG startTick = GetTickCount64();
    std::wstring featureId;
    std::wstring evidencePath;
    std::wstring fingerprintPath;
    std::wstring outputPath;
    std::wstring blockedEvidence;
    if (!ArgValue(argc, argv, L"--feature", featureId) ||
        !ArgValue(argc, argv, L"--evidence", evidencePath) ||
        !ArgValue(argc, argv, L"--fingerprint", fingerprintPath) ||
        !ArgValue(argc, argv, L"--output", outputPath) ||
        featureId.empty() || evidencePath.empty() || fingerprintPath.empty() || outputPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"validation-consistency-check requires --feature, --evidence, --fingerprint, and --output.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--blocked-evidence", blockedEvidence);

    ConsistencyResult result;
    result.checkedFeatures.push_back(featureId);
    result.uiWorkflowExecuted = false;

    if (!ValidationFileExists(evidencePath) && !ValidationDirectoryExists(evidencePath)) {
        AddUnique(result.missingEvidence, L"evidence_source_path");
    }
    RequireFile(evidencePath, L"final_status_report.md", result);
    RequireFile(evidencePath, L"evidence_index.md", result);
    RequireFile(evidencePath, L"v6_7_0_rerun_acceptance_gate_report.md", result);
    RequireFile(evidencePath, L"full_regression_rerun_result.json", result);

    CheckEvidenceIndex(evidencePath, result);
    CheckStatusConsistency(featureId, evidencePath, result);
    CheckFullRegression(evidencePath, result);
    CheckMoveAndScrollEvidence(evidencePath, result);
    CheckRcCheck(evidencePath, result);
    CheckBlockedEvidence(blockedEvidence, result);
    CheckRawCompletedUnverified(evidencePath, result);
    CheckRuntimeSessionsClassification(result);
    CheckFingerprint(featureId, evidencePath, fingerprintPath, result);

    result.blockedReason = SelectBlockedReason(result);
    result.consistencyOk = result.blockedReason.empty();
    std::wstring resultJson = ResultToJson(result);
    std::wstring error;
    WriteValidationTextFile(outputPath, resultJson, error);

    if (!result.consistencyOk) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.blockedReason, L"Validation consistency check failed.", resultJson) << L"\n";
        return 1;
    }

    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), resultJson) << L"\n";
    return 0;
}
