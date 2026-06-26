#pragma once

#include <string>
#include <vector>

struct TextInputVerificationOptions {
    std::wstring inputKind;
    std::wstring expectedText;
    std::wstring observedText;
    bool visibleTextAvailable = false;
    bool verifyStructure = false;
    bool clipboardUsed = false;
    bool backendFileWriteUsed = false;
    bool runSucceeded = false;
    std::wstring inputMethod = L"real_keyboard_events";
};

struct TextInputVerificationResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool codeStructureVerified = false;
    bool topLevelClassVerified = false;
    bool topLevelExecutionVerified = false;
    bool functionBodyIndentVerified = false;
    bool classCourseNotNestedInStudent = false;
    bool languageScopeVerified = false;
    bool functionNotNestedInMain = false;
    bool mainNotNestedInFunction = false;
    bool includeImportTopLevelVerified = false;
    bool classScopeVerified = false;
    bool receiverBindingVerified = false;
    bool duplicateReceiverTokenDetected = false;
    bool invalidPythonMethodReceiver = false;
    bool selfselfPresent = false;
    std::wstring language;
    bool runSuccessIgnoredForStructure = false;
    bool clipboardRejected = false;
    bool backendWriteRejected = false;
    std::vector<std::wstring> findings;
};

TextInputVerificationResult verify_code_structure(const TextInputVerificationOptions& options);
TextInputVerificationResult VerifyTextInputStructure(const TextInputVerificationOptions& options);
std::wstring TextInputVerificationResultJson(const TextInputVerificationResult& result);
