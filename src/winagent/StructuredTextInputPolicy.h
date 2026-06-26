#pragma once

#include "CodeEditorTypingPolicy.h"
#include "InputController.h"

#include <windows.h>

#include <string>

struct StructuredTextInputOptions {
    std::wstring text;
    std::wstring inputKind;
    std::wstring inputMethod = L"real_keyboard_events";
    bool structured = true;
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    bool verifyStructure = false;
    bool dryRun = false;
    bool submitEnter = false;
    int charDelayMs = 0;
    int lineDelayMs = 0;
    bool batchKeyEvents = false;
    std::wstring typingProfile;
    bool verifierRunSucceeded = false;
};

struct StructuredTextInputResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring requestedInputKind;
    std::wstring resolvedInputKind;
    std::wstring strategy;
    std::wstring inputMethod = L"real_keyboard_events";
    bool structured = true;
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    bool verifyStructure = false;
    bool codeStructureVerified = false;
    bool codeWritePlanUsed = false;
    bool languageScopeModelUsed = false;
    bool preInputCodeStructureVerifierUsed = false;
    bool preInputCodeStructureVerified = false;
    bool editorAutoIndentModelUsed = false;
    bool cursorBufferStateVerified = false;
    bool oldBufferClearedOrSafeReplaceVerified = false;
    bool noRetryContamination = false;
    bool incrementalCodeInputVerifierUsed = false;
    bool realKeyboardCodeInputPolicy = false;
    bool receiverBindingVerified = false;
    bool duplicateReceiverTokenDetected = false;
    bool repairReplaceNotAppend = true;
    bool selfselfPresent = false;
    bool autoIndentDetected = false;
    bool autoIndentCorrectionApplied = false;
    int targetIndentSpacesMax = 0;
    int actualIndentCorrectionKeys = 0;
    bool lineInputVerified = false;
    bool clipboardUsed = false;
    bool backendFileWriteUsed = false;
    TypeResult typeResult;
    CodeEditorTypingResult codeEditorResult;
};

std::wstring NormalizeInputKind(const std::wstring& inputKind);
std::wstring InferStructuredInputKind(const std::wstring& text, const std::wstring& requestedKind);
bool LooksLikeStructuredCode(const std::wstring& text);
StructuredTextInputResult ApplyStructuredTextInputPolicy(HWND hwnd, const StructuredTextInputOptions& options);
std::wstring StructuredTextInputResultJson(const StructuredTextInputResult& result);
