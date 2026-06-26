#pragma once

#include "CodeWritePlan.h"
#include "CursorAndBufferStateGuard.h"
#include "IndentationController.h"
#include "InputController.h"
#include "IncrementalCodeInputVerifier.h"
#include "PreInputCodeStructureVerifier.h"
#include "RealKeyboardCodeInputPolicy.h"
#include "RepairEditPolicy.h"
#include "TextInputVerifier.h"

#include <windows.h>

#include <string>
#include <vector>

struct CodeEditorTypingOptions {
    std::wstring text;
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    bool verifyStructure = true;
    bool dryRun = false;
    bool clearFirst = true;
    int charDelayMs = 0;
    int lineDelayMs = 0;
    bool batchKeyEvents = true;
    std::wstring typingProfile = L"fast-real-keyboard";
    bool runSucceededForVerifier = false;
};

struct CodeEditorTypingResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring strategy = L"code_editor_typing_policy";
    std::wstring inputMethod = L"real_keyboard_events";
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    int parsedLineCount = 0;
    int nonBlankLineCount = 0;
    int keyboardSendBatchCount = 0;
    int enterKeyEventCount = 0;
    int targetIndentSpacesMax = 0;
    int actualIndentCorrectionKeys = 0;
    bool autoIndentDetected = false;
    bool autoIndentCorrectionApplied = false;
    bool lineAware = true;
    bool indentAware = true;
    bool autoIndentAware = true;
    bool completionSuppressionApplied = false;
    std::wstring contentInsertionOrder = L"forward";
    int completionSuppressionKeyCount = 0;
    bool editorAutoIndentModel = false;
    bool languageScopeModel = false;
    bool codeWritePlan = false;
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
    bool naturalAutoIndentFollowed = false;
    bool minimalIndentCorrection = false;
    bool smartCompletionModel = false;
    bool smartCompletionAdjustmentApplied = false;
    int smartCompletionAdjustedLineCount = 0;
    std::wstring language = L"unknown";
    bool postInputVerified = false;
    bool codeStructureVerified = false;
    bool clipboardUsed = false;
    bool backendFileWriteUsed = false;
    std::vector<StructuredCodeLine> lines;
    std::vector<IndentationLinePlan> linePlans;
    CodeWritePlanResult writePlan;
    RepairEditPolicyResult repairEditPolicy;
    PreInputCodeStructureVerifierResult preInputVerification;
    CursorAndBufferStateGuardResult bufferGuard;
    IncrementalCodeInputVerifierResult incrementalVerifier;
    RealKeyboardCodeInputPolicyResult realKeyboardPolicy;
    TextInputVerificationResult verification;
    TypeResult typeResult;
};

CodeEditorTypingResult ApplyCodeEditorTypingPolicy(HWND hwnd, const CodeEditorTypingOptions& options);
std::vector<StructuredCodeLine> parse_code_lines(const std::wstring& text, const CodeEditorTypingOptions& options);
bool enter_new_line(HWND hwnd, bool dryRun, CodeEditorTypingResult& result);
bool reset_current_line_indent(HWND hwnd, bool dryRun, const IndentationLinePlan& plan, CodeEditorTypingResult& result);
bool apply_target_indent(HWND hwnd, bool dryRun, const IndentationLinePlan& plan, const CodeEditorTypingOptions& options, CodeEditorTypingResult& result);
bool type_line_content(HWND hwnd, bool dryRun, const StructuredCodeLine& line, const CodeEditorTypingOptions& options, CodeEditorTypingResult& result);
bool verify_code_structure(CodeEditorTypingResult& result, const CodeEditorTypingOptions& options);
std::wstring CodeEditorTypingResultJson(const CodeEditorTypingResult& result);
