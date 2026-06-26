#pragma once

#include "CodeWritePlan.h"
#include "CursorAndBufferStateGuard.h"
#include "IncrementalCodeInputVerifier.h"

#include <string>
#include <vector>

struct RealKeyboardCodeInputPolicyResult {
    bool ok = true;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool realKeyboardCodeInputPolicy = true;
    std::wstring inputMethod = L"real_keyboard_events";
    bool codeWritePlanUsed = false;
    bool languageScopeModelUsed = false;
    bool editorAutoIndentModelUsed = false;
    bool cursorBufferStateVerified = false;
    bool oldBufferClearedOrSafeReplaceVerified = false;
    bool incrementalCodeInputVerifierUsed = false;
    bool clipboardUsed = false;
    bool backendFileWriteUsed = false;
    std::vector<std::wstring> findings;
};

RealKeyboardCodeInputPolicyResult EvaluateRealKeyboardCodeInputPolicy(
    const CodeWritePlanResult& writePlan,
    const CursorAndBufferStateGuardResult& bufferGuard,
    const IncrementalCodeInputVerifierResult& incrementalVerifier,
    bool clipboardUsed,
    bool backendFileWriteUsed);
std::wstring RealKeyboardCodeInputPolicyResultJson(const RealKeyboardCodeInputPolicyResult& result);
