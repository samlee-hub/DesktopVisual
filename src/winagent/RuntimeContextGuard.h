#pragma once

#include <windows.h>

#include <string>
#include <vector>

struct ExpectedContextSpec {
    bool enabled = false;
    std::wstring expectedProcessPattern;
    std::wstring expectedTitlePattern;
    std::vector<std::wstring> requiredMarkers;
    std::vector<std::wstring> wrongPagePatterns;
    std::vector<std::wstring> activeProtectionPatterns;
    std::vector<std::wstring> automationPatterns;
    std::vector<std::wstring> loadingOrOverlayPatterns;
    bool requireTargetRect = false;
    bool requireTargetFromCurrentObserve = false;
    bool requireTargetUnique = false;
    bool requireTargetInsideViewport = false;
    std::wstring expectedFocusMarker;
    bool allowSafeOverlayNormalization = false;
    bool stopOnFailure = true;
    std::wstring guardTraceJsonl;
    std::wstring guardResultJson;
};

struct RuntimeTargetContext {
    bool hasTargetRect = false;
    RECT targetRect = {};
    bool targetFromCurrentObserve = true;
    bool targetUnique = true;
    bool targetInsideViewport = true;
};

struct RuntimeContextGuardResult {
    bool ok = true;
    std::wstring stopCode;
    std::wstring reason;
    HWND foregroundHwnd = nullptr;
    std::wstring foregroundTitle;
    std::wstring foregroundProcess;
    bool foregroundOk = true;
    bool markersOk = true;
    bool wrongPageDetected = false;
    bool activeProtectionDetected = false;
    bool automationDetected = false;
    bool loadingOrOverlayBlocking = false;
    bool hasTargetRect = false;
    RECT targetRect = {};
    bool targetFromCurrentObserve = true;
    bool targetUnique = true;
    bool targetInsideViewport = true;
    std::wstring focusedElementName;
    std::wstring focusedElementControlType;
    std::wstring screenshotPath;
    bool continuedActionAfterWrongContext = false;
};

ExpectedContextSpec ParseExpectedContextSpecFromArgs(int argc, wchar_t** argv, std::wstring& error);
RuntimeTargetContext ParseRuntimeTargetContextFromArgs(int argc, wchar_t** argv);

bool RuntimeContextGuardArgsPresent(const ExpectedContextSpec& spec);
RuntimeContextGuardResult EvaluateRuntimeContextGuard(
    const ExpectedContextSpec& spec,
    const RuntimeTargetContext& targetContext);

std::wstring RuntimeContextGuardResultJson(const RuntimeContextGuardResult& result);
std::wstring RuntimeContextGuardEnvelopeJson(
    bool enabled,
    const RuntimeContextGuardResult& result,
    bool actionExecuted,
    const std::wstring& extraFieldsJson = L"");

bool WriteRuntimeGuardTextFile(const std::wstring& path, const std::wstring& value);
void PersistRuntimeContextGuardResult(
    const ExpectedContextSpec& spec,
    const RuntimeContextGuardResult& result,
    const std::wstring& command,
    bool actionExecuted);
