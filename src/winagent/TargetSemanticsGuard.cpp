#include "TargetSemanticsGuard.h"

#include "Trace.h"

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <regex>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool ArgExists(int argc, wchar_t** argv, const std::wstring& name) {
    for (int i = 2; i < argc; ++i) {
        if (argv[i] == name) return true;
    }
    return false;
}

std::vector<std::wstring> ArgValues(int argc, wchar_t** argv, const std::wstring& name) {
    std::vector<std::wstring> values;
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            values.push_back(argv[i + 1]);
            ++i;
        }
    }
    return values;
}

bool ParseBoolArg(int argc, wchar_t** argv, const std::wstring& name, bool& value, std::wstring& error) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return true;
    if (raw == L"true" || raw == L"1") {
        value = true;
        return true;
    }
    if (raw == L"false" || raw == L"0") {
        value = false;
        return true;
    }
    error = name + L" must be true or false.";
    return false;
}

bool ParseIntArg(int argc, wchar_t** argv, const std::wstring& name, int& value) {
    std::wstring raw;
    if (!ArgValue(argc, argv, name, raw)) return false;
    try {
        size_t consumed = 0;
        int parsed = std::stoi(raw, &consumed, 10);
        if (consumed != raw.size()) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

std::wstring Trim(std::wstring value) {
    auto first = std::find_if_not(value.begin(), value.end(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    });
    auto last = std::find_if_not(value.rbegin(), value.rend(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    }).base();
    if (first >= last) return L"";
    return std::wstring(first, last);
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

std::wstring NormalizeText(const std::wstring& value) {
    std::wstring normalized;
    for (wchar_t ch : value) {
        if (std::iswspace(ch) == 0) normalized += ch;
    }
    return normalized;
}

bool EqualsInsensitive(const std::wstring& left, const std::wstring& right) {
    return ToLowerInvariant(Trim(left)) == ToLowerInvariant(Trim(right));
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool MatchesPattern(const std::wstring& haystack, const std::wstring& pattern) {
    if (pattern.empty()) return true;
    try {
        std::wregex regex(pattern, std::regex_constants::icase);
        return std::regex_search(haystack, regex);
    } catch (...) {
        return ContainsInsensitive(haystack, pattern);
    }
}

bool AnyPatternMatches(const std::wstring& haystack, const std::vector<std::wstring>& patterns, std::wstring& matched) {
    for (const auto& pattern : patterns) {
        if (MatchesPattern(haystack, pattern)) {
            matched = pattern;
            return true;
        }
    }
    return false;
}

bool IsRectNonzero(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

bool RectInsideVirtualScreen(const RECT& rect) {
    RECT virtualScreen = {};
    virtualScreen.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    virtualScreen.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    virtualScreen.right = virtualScreen.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    virtualScreen.bottom = virtualScreen.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
    RECT intersection = {};
    return IntersectRect(&intersection, &rect, &virtualScreen) != 0;
}

bool LooksActionableRole(const std::wstring& role) {
    static const std::vector<std::wstring> kRoles = {
        L"Button", L"Edit", L"Document", L"Pane", L"ListItem", L"MenuItem",
        L"Hyperlink", L"ComboBox", L"CheckBox", L"RadioButton", L"TabItem",
        L"TreeItem", L"DataItem", L"Text"
    };
    for (const auto& item : kRoles) {
        if (EqualsInsensitive(role, item)) return true;
    }
    return false;
}

std::wstring RectJsonOrNull(bool hasRect, const RECT& rect) {
    if (!hasRect) return L"null";
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i > 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

void Fail(TargetSemanticsGuardResult& result, const std::wstring& code, const std::wstring& reason) {
    result.ok = false;
    result.stopCode = code;
    result.reason = reason;
}

}  // namespace

TargetSemanticsSpec ParseTargetSemanticsSpecFromArgs(int argc, wchar_t** argv, std::wstring& error) {
    TargetSemanticsSpec spec;
    ArgValue(argc, argv, L"--expected-text-exact", spec.expectedTextExact);
    spec.expectedTextPatterns = ArgValues(argc, argv, L"--expected-text-pattern");
    spec.negativeTextPatterns = ArgValues(argc, argv, L"--negative-text-pattern");
    spec.expectedRolePatterns = ArgValues(argc, argv, L"--expected-role-pattern");
    ArgValue(argc, argv, L"--expected-region", spec.expectedRegion);
    ArgValue(argc, argv, L"--forbidden-region", spec.forbiddenRegion);
    ArgValue(argc, argv, L"--candidate-semantic-type", spec.candidateSemanticType);
    ArgValue(argc, argv, L"--post-action-causal-requirement", spec.postActionCausalRequirement);
    ArgValue(argc, argv, L"--target-semantics-guard-trace-jsonl", spec.guardTraceJsonl);
    ArgValue(argc, argv, L"--target-semantics-guard-result-json", spec.guardResultJson);

    if (!ParseBoolArg(argc, argv, L"--require-unique-candidate", spec.requireUniqueCandidate, error) ||
        !ParseBoolArg(argc, argv, L"--require-nonzero-rect", spec.requireNonzeroRect, error) ||
        !ParseBoolArg(argc, argv, L"--require-inside-viewport", spec.requireInsideViewport, error) ||
        !ParseBoolArg(argc, argv, L"--require-actionable-control", spec.requireActionableControl, error) ||
        !ParseBoolArg(argc, argv, L"--stop-on-target-semantic-mismatch", spec.stopOnFailure, error)) {
        return spec;
    }

    spec.enabled =
        !spec.expectedTextExact.empty() ||
        !spec.expectedTextPatterns.empty() ||
        !spec.negativeTextPatterns.empty() ||
        !spec.expectedRolePatterns.empty() ||
        !spec.expectedRegion.empty() ||
        !spec.forbiddenRegion.empty() ||
        spec.requireUniqueCandidate ||
        spec.requireNonzeroRect ||
        spec.requireInsideViewport ||
        spec.requireActionableControl ||
        !spec.candidateSemanticType.empty() ||
        !spec.postActionCausalRequirement.empty();
    return spec;
}

TargetSemanticsContext ParseTargetSemanticsContextFromArgs(int argc, wchar_t** argv) {
    TargetSemanticsContext context;
    ArgValue(argc, argv, L"--clicked-target-text", context.clickedTargetText);
    if (context.clickedTargetText.empty()) ArgValue(argc, argv, L"--candidate-text", context.clickedTargetText);
    ArgValue(argc, argv, L"--clicked-target-role", context.clickedTargetRole);
    if (context.clickedTargetRole.empty()) ArgValue(argc, argv, L"--candidate-role", context.clickedTargetRole);
    ArgValue(argc, argv, L"--clicked-target-region", context.clickedTargetRegion);
    if (context.clickedTargetRegion.empty()) ArgValue(argc, argv, L"--candidate-region", context.clickedTargetRegion);
    ArgValue(argc, argv, L"--clicked-target-semantic-type", context.clickedTargetSemanticType);
    if (context.clickedTargetSemanticType.empty()) ArgValue(argc, argv, L"--candidate-semantic-type", context.clickedTargetSemanticType);

    std::wstring error;
    if (ArgExists(argc, argv, L"--clicked-target-is-expected-target")) {
        context.clickedTargetIsExpectedTargetProvided = true;
        ParseBoolArg(argc, argv, L"--clicked-target-is-expected-target", context.clickedTargetIsExpectedTarget, error);
    }
    if (ArgExists(argc, argv, L"--clicked-target-is-forbidden-similar-target")) {
        context.clickedTargetIsForbiddenSimilarTargetProvided = true;
        ParseBoolArg(argc, argv, L"--clicked-target-is-forbidden-similar-target", context.clickedTargetIsForbiddenSimilarTarget, error);
    }
    if (ArgExists(argc, argv, L"--target-unique")) {
        context.targetUniqueProvided = true;
        ParseBoolArg(argc, argv, L"--target-unique", context.targetUnique, error);
    }
    if (ArgExists(argc, argv, L"--target-inside-viewport")) {
        context.targetInsideViewportProvided = true;
        ParseBoolArg(argc, argv, L"--target-inside-viewport", context.targetInsideViewport, error);
    }
    if (ArgExists(argc, argv, L"--target-actionable")) {
        context.targetActionableProvided = true;
        ParseBoolArg(argc, argv, L"--target-actionable", context.targetActionable, error);
    }
    if (ArgExists(argc, argv, L"--post-action-causal-verified")) {
        context.postActionCausalVerifiedProvided = true;
        ParseBoolArg(argc, argv, L"--post-action-causal-verified", context.postActionCausalVerified, error);
    }

    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
    bool hasAll = ParseIntArg(argc, argv, L"--target-rect-left", left) &&
                  ParseIntArg(argc, argv, L"--target-rect-top", top) &&
                  ParseIntArg(argc, argv, L"--target-rect-right", right) &&
                  ParseIntArg(argc, argv, L"--target-rect-bottom", bottom);
    if (hasAll) {
        context.hasTargetRect = true;
        context.targetRect.left = left;
        context.targetRect.top = top;
        context.targetRect.right = right;
        context.targetRect.bottom = bottom;
    }
    return context;
}

bool TargetSemanticsGuardArgsPresent(const TargetSemanticsSpec& spec) {
    return spec.enabled;
}

TargetSemanticsGuardResult EvaluateTargetSemanticsGuard(
    const TargetSemanticsSpec& spec,
    const TargetSemanticsContext& context) {
    TargetSemanticsGuardResult result;
    result.enabled = spec.enabled;
    result.expectedTextExact = spec.expectedTextExact;
    result.expectedTextPatterns = spec.expectedTextPatterns;
    result.negativeTextPatterns = spec.negativeTextPatterns;
    result.expectedRolePatterns = spec.expectedRolePatterns;
    result.expectedRegion = spec.expectedRegion;
    result.forbiddenRegion = spec.forbiddenRegion;
    result.candidateSemanticType = spec.candidateSemanticType;
    result.clickedTargetText = context.clickedTargetText;
    result.clickedTargetNormalizedText = NormalizeText(context.clickedTargetText);
    result.clickedTargetRole = context.clickedTargetRole;
    result.clickedTargetRegion = context.clickedTargetRegion;
    result.clickedTargetSemanticType = context.clickedTargetSemanticType;
    result.clickedTargetIsExpectedTarget = context.clickedTargetIsExpectedTarget;
    result.clickedTargetIsForbiddenSimilarTarget = context.clickedTargetIsForbiddenSimilarTarget;
    result.targetUnique = context.targetUnique;
    result.hasTargetRect = context.hasTargetRect;
    result.targetRect = context.targetRect;
    result.targetRectNonzero = context.hasTargetRect && IsRectNonzero(context.targetRect);
    result.targetInsideViewport = context.targetInsideViewportProvided
        ? context.targetInsideViewport
        : (!context.hasTargetRect || RectInsideVirtualScreen(context.targetRect));
    result.targetActionable = context.targetActionableProvided
        ? context.targetActionable
        : LooksActionableRole(context.clickedTargetRole);
    result.postActionCausalRequirement = spec.postActionCausalRequirement;
    result.postActionCausalVerified = context.postActionCausalVerified;
    result.postActionCausalVerifiedProvided = context.postActionCausalVerifiedProvided;

    if (!spec.enabled) return result;

    if (context.clickedTargetIsForbiddenSimilarTargetProvided && context.clickedTargetIsForbiddenSimilarTarget) {
        Fail(result, L"STOP_FORBIDDEN_SIMILAR_TARGET", L"Clicked target was explicitly marked as a forbidden similar target.");
        return result;
    }

    std::wstring matched;
    if (AnyPatternMatches(context.clickedTargetText, spec.negativeTextPatterns, matched)) {
        result.matchedNegativePattern = matched;
        result.clickedTargetIsForbiddenSimilarTarget = true;
        Fail(result, L"STOP_FORBIDDEN_SIMILAR_TARGET", L"Clicked target text matched a negative target pattern.");
        return result;
    }

    if (!spec.forbiddenRegion.empty() && EqualsInsensitive(context.clickedTargetRegion, spec.forbiddenRegion)) {
        Fail(result, L"STOP_TARGET_REGION_MISMATCH", L"Clicked target is in a forbidden region.");
        return result;
    }

    if (!spec.expectedRegion.empty() && !EqualsInsensitive(context.clickedTargetRegion, spec.expectedRegion)) {
        Fail(result, L"STOP_TARGET_REGION_MISMATCH", L"Clicked target region does not match expected region.");
        return result;
    }
    result.preClickRegionVerified = spec.expectedRegion.empty() || EqualsInsensitive(context.clickedTargetRegion, spec.expectedRegion);

    if (!spec.expectedTextExact.empty() && Trim(context.clickedTargetText) != Trim(spec.expectedTextExact)) {
        Fail(result, L"STOP_TARGET_SEMANTIC_MISMATCH", L"Clicked target text does not exactly match expected text.");
        return result;
    }
    if (!spec.expectedTextPatterns.empty()) {
        std::wstring textMatch;
        if (!AnyPatternMatches(context.clickedTargetText, spec.expectedTextPatterns, textMatch)) {
            Fail(result, L"STOP_TARGET_SEMANTIC_MISMATCH", L"Clicked target text did not match any expected text pattern.");
            return result;
        }
        result.matchedExpectedTextPattern = textMatch;
    }

    if (!spec.expectedRolePatterns.empty()) {
        std::wstring roleMatch;
        if (!AnyPatternMatches(context.clickedTargetRole, spec.expectedRolePatterns, roleMatch)) {
            Fail(result, L"STOP_TARGET_SEMANTIC_MISMATCH", L"Clicked target role did not match any expected role pattern.");
            return result;
        }
        result.matchedRolePattern = roleMatch;
    }
    result.preClickRoleVerified = spec.expectedRolePatterns.empty() || !result.matchedRolePattern.empty();

    if (spec.requireUniqueCandidate && (!context.targetUniqueProvided || !context.targetUnique)) {
        Fail(result, L"STOP_TARGET_SEMANTIC_MISMATCH", L"Target candidate was not proven unique.");
        return result;
    }

    if (spec.requireNonzeroRect && (!context.hasTargetRect || !result.targetRectNonzero)) {
        Fail(result, L"STOP_TARGET_SEMANTIC_MISMATCH", L"Target rect is missing or zero sized.");
        return result;
    }

    if (spec.requireInsideViewport && !result.targetInsideViewport) {
        Fail(result, L"STOP_TARGET_REGION_MISMATCH", L"Target rect is outside the viewport.");
        return result;
    }

    if (spec.requireActionableControl && !result.targetActionable) {
        Fail(result, L"STOP_TARGET_SEMANTIC_MISMATCH", L"Target role was not proven actionable.");
        return result;
    }

    if (context.clickedTargetIsExpectedTargetProvided && !context.clickedTargetIsExpectedTarget) {
        Fail(result, L"STOP_CLICKED_TARGET_NOT_EXPECTED", L"Clicked target was explicitly marked as not expected.");
        return result;
    }

    if (!spec.postActionCausalRequirement.empty() &&
        context.postActionCausalVerifiedProvided &&
        !context.postActionCausalVerified) {
        Fail(result, L"STOP_POST_ACTION_CAUSAL_VERIFICATION_FAILED", L"Post-action causal verification failed.");
        return result;
    }

    result.preClickSemanticVerified = true;
    result.clickedTargetIsExpectedTarget = true;
    return result;
}

std::wstring TargetSemanticsGuardResultJson(const TargetSemanticsGuardResult& result) {
    std::wstringstream json;
    json << L"{\"enabled\":" << (result.enabled ? L"true" : L"false")
         << L",\"ok\":" << (result.ok ? L"true" : L"false")
         << L",\"stop_code\":" << JsonString(result.stopCode)
         << L",\"reason\":" << JsonString(result.reason)
         << L",\"expected_text_exact\":" << JsonString(result.expectedTextExact)
         << L",\"expected_text_patterns\":" << StringArrayJson(result.expectedTextPatterns)
         << L",\"negative_text_patterns\":" << StringArrayJson(result.negativeTextPatterns)
         << L",\"expected_role_patterns\":" << StringArrayJson(result.expectedRolePatterns)
         << L",\"expected_region\":" << JsonString(result.expectedRegion)
         << L",\"forbidden_region\":" << JsonString(result.forbiddenRegion)
         << L",\"candidate_semantic_type\":" << JsonString(result.candidateSemanticType)
         << L",\"clicked_target_text\":" << JsonString(result.clickedTargetText)
         << L",\"clicked_target_normalized_text\":" << JsonString(result.clickedTargetNormalizedText)
         << L",\"clicked_target_role\":" << JsonString(result.clickedTargetRole)
         << L",\"clicked_target_region\":" << JsonString(result.clickedTargetRegion)
         << L",\"clicked_target_semantic_type\":" << JsonString(result.clickedTargetSemanticType)
         << L",\"clicked_target_is_expected_target\":" << (result.clickedTargetIsExpectedTarget ? L"true" : L"false")
         << L",\"clicked_target_is_forbidden_similar_target\":" << (result.clickedTargetIsForbiddenSimilarTarget ? L"true" : L"false")
         << L",\"pre_click_semantic_verified\":" << (result.preClickSemanticVerified ? L"true" : L"false")
         << L",\"pre_click_region_verified\":" << (result.preClickRegionVerified ? L"true" : L"false")
         << L",\"pre_click_role_verified\":" << (result.preClickRoleVerified ? L"true" : L"false")
         << L",\"target_unique\":" << (result.targetUnique ? L"true" : L"false")
         << L",\"target_rect\":" << RectJsonOrNull(result.hasTargetRect, result.targetRect)
         << L",\"target_rect_nonzero\":" << (result.targetRectNonzero ? L"true" : L"false")
         << L",\"target_inside_viewport\":" << (result.targetInsideViewport ? L"true" : L"false")
         << L",\"target_actionable\":" << (result.targetActionable ? L"true" : L"false")
         << L",\"matched_negative_pattern\":" << JsonString(result.matchedNegativePattern)
         << L",\"matched_expected_text_pattern\":" << JsonString(result.matchedExpectedTextPattern)
         << L",\"matched_role_pattern\":" << JsonString(result.matchedRolePattern)
         << L",\"post_action_causal_requirement\":" << JsonString(result.postActionCausalRequirement)
         << L",\"post_action_causal_verified\":" << (result.postActionCausalVerified ? L"true" : L"false")
         << L",\"post_action_causal_verified_provided\":" << (result.postActionCausalVerifiedProvided ? L"true" : L"false")
         << L"}";
    return json.str();
}

std::wstring TargetSemanticsGuardEnvelopeJson(
    bool enabled,
    const TargetSemanticsGuardResult& result,
    bool actionExecuted,
    const std::wstring& extraFieldsJson) {
    std::wstringstream json;
    json << L"{\"target_semantics_guard_enabled\":" << (enabled ? L"true" : L"false")
         << L",\"target_semantics_guard\":" << TargetSemanticsGuardResultJson(result)
         << L",\"action_executed\":" << (actionExecuted ? L"true" : L"false");
    if (!extraFieldsJson.empty()) {
        json << L"," << extraFieldsJson;
    }
    json << L"}";
    return json.str();
}

bool WriteTargetSemanticsGuardTextFile(const std::wstring& path, const std::wstring& value) {
    if (path.empty()) return false;
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) return false;
    fwprintf(file, L"%ls", value.c_str());
    fclose(file);
    return true;
}

void PersistTargetSemanticsGuardResult(
    const TargetSemanticsSpec& spec,
    const TargetSemanticsGuardResult& result,
    const std::wstring& command,
    bool actionExecuted) {
    if (!spec.enabled && spec.guardResultJson.empty() && spec.guardTraceJsonl.empty()) return;
    std::wstring payload = TargetSemanticsGuardEnvelopeJson(spec.enabled, result, actionExecuted, L"\"command\":" + JsonString(command));
    if (!spec.guardResultJson.empty()) {
        WriteTargetSemanticsGuardTextFile(spec.guardResultJson, payload);
    }
    if (!spec.guardTraceJsonl.empty()) {
        FILE* file = nullptr;
        if (_wfopen_s(&file, spec.guardTraceJsonl.c_str(), L"a, ccs=UTF-8") == 0 && file) {
            fwprintf(file, L"%ls\n", payload.c_str());
            fclose(file);
        }
    }
}
