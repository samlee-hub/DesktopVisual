#include "RegressionSkipPolicy.h"

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

struct SkipPolicyResult {
    bool skipAllowed = false;
    std::wstring skipReason;
    bool replayRequired = false;
    std::vector<std::wstring> affectedFeatures;
    bool sourceChangeDetected = false;
    bool evidenceFingerprintOk = false;
    bool consistencyCheckOk = true;
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

std::vector<std::wstring> SplitLines(const std::wstring& text) {
    std::vector<std::wstring> lines;
    std::wistringstream stream(text);
    std::wstring line;
    while (std::getline(stream, line)) {
        while (!line.empty() && (line.back() == L'\r' || iswspace(line.back()))) line.pop_back();
        size_t first = 0;
        while (first < line.size() && iswspace(line[first])) ++first;
        line = line.substr(first);
        if (!line.empty()) lines.push_back(line);
    }
    return lines;
}

std::vector<std::wstring> SourcePrefixesForFeature(const std::wstring& featureId) {
    if (featureId == L"v6_7_explorer_move_file" ||
        featureId == L"v6_7_explorer_scroll_and_locate" ||
        featureId == L"v6_7_explorer_full_regression") {
        return {
            L"src/winagent/explorerworkflow",
            L"src/winagent/explorerworkflowadapter",
            L"src/winagent/explorerworkflowexecutor",
            L"src/winagent/explorerworkflowverifier",
            L"src/winagent/explorercontextmenuhandler",
            L"src/winagent/plancompiler",
            L"src/winagent/stepcontractruntimeadapter",
            L"src/winagent/stepcontractvalidator",
            L"src/winagent/runtimecontextguard"
        };
    }
    if (featureId == L"v6_6_vlm_candidate_gate") {
        return {
            L"src/winagent/vlmcandidatebridge",
            L"src/winagent/runtimecandidatevalidator",
            L"src/winagent/locatorcandidate"
        };
    }
    if (featureId == L"v6_5_vlm_observation_gate") {
        return {
            L"src/winagent/vlmobservation",
            L"src/winagent/vlmprovider",
            L"src/winagent/mockvlmprovider"
        };
    }
    if (featureId == L"v6_4_runtime_execution_gate") {
        return {
            L"src/winagent/compiledplanexecutor",
            L"src/winagent/stepcontractruntimeadapter",
            L"src/winagent/stepexecutionverifier",
            L"src/winagent/executionevidencepack",
            L"src/winagent/runtimesession",
            L"src/winagent/runtimecontextguard"
        };
    }
    if (featureId == L"v6_3_plan_compiler_gate") {
        return {
            L"src/winagent/plancompiler",
            L"src/winagent/stepcontract",
            L"src/winagent/stepcontractvalidator"
        };
    }
    if (featureId == L"v6_2_session_gate") {
        return {
            L"src/winagent/runtimesession",
            L"src/winagent/sessionmanager",
            L"src/winagent/session"
        };
    }
    return {};
}

bool ChangedFileAffectsFeature(const std::wstring& featureId, const std::wstring& changedFile) {
    std::wstring file = ValidationToLower(SlashPath(changedFile));
    for (const std::wstring& prefix : SourcePrefixesForFeature(featureId)) {
        if (file.rfind(prefix, 0) == 0) {
            return true;
        }
    }
    return false;
}

bool FingerprintLooksOk(const std::wstring& fingerprintPath) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(fingerprintPath, text, error)) {
        return false;
    }
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return false;
    }
    if (simplejson::Has(parsed.root, L"fingerprint_ok") && !simplejson::GetBool(parsed.root, L"fingerprint_ok", false)) {
        return false;
    }
    std::wstring status = simplejson::GetString(parsed.root, L"fingerprint_status", L"PASS");
    if (!status.empty() && ValidationToLower(status) != L"pass") {
        return false;
    }
    if (simplejson::GetString(parsed.root, L"fingerprint_id", L"").empty()) {
        return false;
    }
    if (simplejson::GetString(parsed.root, L"artifact_manifest_hash", L"").empty()) {
        return false;
    }
    const simplejson::Value* mismatches = simplejson::Find(parsed.root, L"hash_mismatches");
    if (mismatches && mismatches->IsArray() && !mismatches->arrayValue.empty()) {
        return false;
    }
    return true;
}

bool ConsistencyLooksOk(const std::wstring& consistencyPath) {
    if (consistencyPath.empty()) return true;
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(consistencyPath, text, error)) {
        return false;
    }
    simplejson::ParseResult parsed = simplejson::Parse(text);
    if (!parsed.ok || !parsed.root.IsObject()) {
        return false;
    }
    return simplejson::GetBool(parsed.root, L"consistency_ok", false);
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

bool AgentsTrustedVersionOk(const std::wstring& featureId) {
    std::wstring text;
    std::wstring error;
    if (!ReadValidationTextFile(ProjectPath(L"AGENTS.md"), text, error)) {
        return false;
    }
    std::wstring featureVersion = EvidenceFeatureVersion(featureId);
    std::wstring trustedVersion = ExtractMetadataValue(text, L"current_trusted_version");
    return !featureVersion.empty() && VersionAtLeast(trustedVersion, featureVersion);
}

std::wstring ResultToJson(const SkipPolicyResult& result) {
    std::wstringstream json;
    json << L"{"
         << L"\"skip_allowed\":" << simplejson::Bool(result.skipAllowed)
         << L",\"skip_reason\":" << simplejson::Quote(result.skipReason)
         << L",\"replay_required\":" << simplejson::Bool(result.replayRequired)
         << L",\"affected_features\":" << ValidationJsonArray(result.affectedFeatures)
         << L",\"source_change_detected\":" << simplejson::Bool(result.sourceChangeDetected)
         << L",\"evidence_fingerprint_ok\":" << simplejson::Bool(result.evidenceFingerprintOk)
         << L",\"consistency_check_ok\":" << simplejson::Bool(result.consistencyCheckOk)
         << L"}";
    return json.str();
}

}  // namespace

int CommandRegressionSkipEvaluate(int argc, wchar_t** argv) {
    const std::wstring command = L"regression-skip-evaluate";
    ULONGLONG startTick = GetTickCount64();
    std::wstring featureId;
    std::wstring changedFilesPath;
    std::wstring fingerprintPath;
    std::wstring outputPath;
    std::wstring consistencyPath;
    if (!ArgValue(argc, argv, L"--feature", featureId) ||
        !ArgValue(argc, argv, L"--changed-files", changedFilesPath) ||
        !ArgValue(argc, argv, L"--fingerprint", fingerprintPath) ||
        !ArgValue(argc, argv, L"--output", outputPath) ||
        featureId.empty() || changedFilesPath.empty() || fingerprintPath.empty() || outputPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"regression-skip-evaluate requires --feature, --changed-files, --fingerprint, and --output.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--consistency", consistencyPath);

    SkipPolicyResult result;
    result.affectedFeatures.push_back(featureId);
    result.evidenceFingerprintOk = FingerprintLooksOk(fingerprintPath);
    result.consistencyCheckOk = ConsistencyLooksOk(consistencyPath);

    std::wstring changedText;
    std::wstring error;
    ReadValidationTextFile(changedFilesPath, changedText, error);
    for (const std::wstring& changedFile : SplitLines(changedText)) {
        if (ChangedFileAffectsFeature(featureId, changedFile)) {
            result.sourceChangeDetected = true;
            break;
        }
    }

    bool trustedOk = AgentsTrustedVersionOk(featureId);
    result.replayRequired = result.sourceChangeDetected || !result.evidenceFingerprintOk || !result.consistencyCheckOk || !trustedOk;
    result.skipAllowed = !result.replayRequired;
    if (result.skipAllowed) {
        result.skipReason = L"accepted_unchanged_feature_consistency_check_only";
    } else if (result.sourceChangeDetected) {
        result.skipReason = L"source_change_detected_replay_required";
    } else if (!result.evidenceFingerprintOk) {
        result.skipReason = L"evidence_fingerprint_mismatch_replay_required";
    } else if (!result.consistencyCheckOk) {
        result.skipReason = L"consistency_check_failed_replay_required";
    } else {
        result.skipReason = L"trusted_version_rollback_replay_required";
    }

    std::wstring resultJson = ResultToJson(result);
    WriteValidationTextFile(outputPath, resultJson, error);
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), resultJson) << L"\n";
    return 0;
}
