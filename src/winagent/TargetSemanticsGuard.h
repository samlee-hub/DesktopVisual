#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct TargetSemanticsSpec {
    bool enabled = false;
    std::wstring expectedTextExact;
    std::vector<std::wstring> expectedTextPatterns;
    std::vector<std::wstring> negativeTextPatterns;
    std::vector<std::wstring> expectedRolePatterns;
    std::wstring expectedRegion;
    std::wstring forbiddenRegion;
    bool requireUniqueCandidate = false;
    bool requireNonzeroRect = false;
    bool requireInsideViewport = false;
    bool requireActionableControl = false;
    std::wstring candidateSemanticType;
    std::wstring postActionCausalRequirement;
    bool stopOnFailure = true;
    std::wstring guardTraceJsonl;
    std::wstring guardResultJson;
};

struct TargetSemanticsContext {
    std::wstring clickedTargetText;
    std::wstring clickedTargetRole;
    std::wstring clickedTargetRegion;
    std::wstring clickedTargetSemanticType;
    bool clickedTargetIsExpectedTarget = true;
    bool clickedTargetIsExpectedTargetProvided = false;
    bool clickedTargetIsForbiddenSimilarTarget = false;
    bool clickedTargetIsForbiddenSimilarTargetProvided = false;
    bool targetUnique = true;
    bool targetUniqueProvided = false;
    bool hasTargetRect = false;
    RECT targetRect = {};
    bool targetInsideViewport = true;
    bool targetInsideViewportProvided = false;
    bool targetActionable = false;
    bool targetActionableProvided = false;
    bool postActionCausalVerified = false;
    bool postActionCausalVerifiedProvided = false;
};

struct TargetSemanticsGuardResult {
    bool enabled = false;
    bool ok = true;
    std::wstring stopCode;
    std::wstring reason;
    std::wstring expectedTextExact;
    std::vector<std::wstring> expectedTextPatterns;
    std::vector<std::wstring> negativeTextPatterns;
    std::vector<std::wstring> expectedRolePatterns;
    std::wstring expectedRegion;
    std::wstring forbiddenRegion;
    std::wstring candidateSemanticType;
    std::wstring clickedTargetText;
    std::wstring clickedTargetNormalizedText;
    std::wstring clickedTargetRole;
    std::wstring clickedTargetRegion;
    std::wstring clickedTargetSemanticType;
    bool clickedTargetIsExpectedTarget = true;
    bool clickedTargetIsForbiddenSimilarTarget = false;
    bool preClickSemanticVerified = false;
    bool preClickRegionVerified = false;
    bool preClickRoleVerified = false;
    bool targetUnique = true;
    bool hasTargetRect = false;
    RECT targetRect = {};
    bool targetRectNonzero = false;
    bool targetInsideViewport = true;
    bool targetActionable = false;
    std::wstring matchedNegativePattern;
    std::wstring matchedExpectedTextPattern;
    std::wstring matchedRolePattern;
    std::wstring postActionCausalRequirement;
    bool postActionCausalVerified = false;
    bool postActionCausalVerifiedProvided = false;
};

TargetSemanticsSpec ParseTargetSemanticsSpecFromArgs(int argc, wchar_t** argv, std::wstring& error);
TargetSemanticsContext ParseTargetSemanticsContextFromArgs(int argc, wchar_t** argv);
bool TargetSemanticsGuardArgsPresent(const TargetSemanticsSpec& spec);

TargetSemanticsGuardResult EvaluateTargetSemanticsGuard(
    const TargetSemanticsSpec& spec,
    const TargetSemanticsContext& context);

std::wstring TargetSemanticsGuardResultJson(const TargetSemanticsGuardResult& result);
std::wstring TargetSemanticsGuardEnvelopeJson(
    bool enabled,
    const TargetSemanticsGuardResult& result,
    bool actionExecuted,
    const std::wstring& extraFieldsJson = L"");

bool WriteTargetSemanticsGuardTextFile(const std::wstring& path, const std::wstring& value);
void PersistTargetSemanticsGuardResult(
    const TargetSemanticsSpec& spec,
    const TargetSemanticsGuardResult& result,
    const std::wstring& command,
    bool actionExecuted);
