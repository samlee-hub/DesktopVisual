#pragma once

#include "StructuredTextInputPolicy.h"
#include "TargetWindowLock.h"
#include "VisibleOperationPolicy.h"

#include <string>

struct VisibleTextInputOptions {
    std::wstring text;
    std::wstring inputKind;
    std::wstring inputMethod = L"real_keyboard_events";
    std::wstring targetTitle;
    std::wstring targetHwnd;
    std::wstring targetProcess;
    bool requireTargetLock = true;
    bool allowGlobalDesktop = false;
    bool dryRun = false;
    bool allowDryRunTarget = false;
    bool allowClipboard = false;
    bool backendFileWriteUsed = false;
    std::wstring clipboardFallbackReason;
    bool visibleMouseKeyboardAttempted = false;
    std::wstring visibleAttemptResult;
    std::wstring visibleFailureReason;
    int visibleAttemptCount = 0;
    int minVisibleAttemptsBeforeShortcut = 2;
    bool preActionCheckpointPresent = false;
    bool boundedRecoveryAttempted = false;
    bool postRecoveryObserved = false;
    bool sameSurfaceAfterRecovery = false;
    bool surfaceImpossible = false;
    std::wstring surfaceImpossibleReason;
    bool surfaceImpossibleEvidencePresent = false;
    bool keyboardShortcutAttempted = false;
    std::wstring keyboardShortcutResult;
    std::wstring keyboardShortcutFailureReason;
    bool explicitBackendRequested = false;
    bool maxAttemptsExceeded = false;
    int charDelayMs = 0;
    int lineDelayMs = 0;
    bool batchKeyEvents = false;
    std::wstring typingProfile;
    bool structured = true;
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    bool verifyStructure = false;
    bool submitEnter = false;
    bool verifierRunSucceeded = false;
};

struct VisibleTextInputResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    std::wstring inputMethod = L"real_keyboard_events";
    int keyboardEventCount = 0;
    int unicodeCharEventCount = 0;
    int enterKeyEventCount = 0;
    int tabKeyEventCount = 0;
    int crlfNewlineCount = 0;
    int lfNewlineCount = 0;
    int crNewlineCount = 0;
    int typedCharCount = 0;
    int typedLineCount = 0;
    int charDelayMs = 0;
    int lineDelayMs = 0;
    bool batchKeyEvents = false;
    int keyboardSendBatchCount = 0;
    std::wstring typingProfile;
    std::wstring inputKind;
    std::wstring resolvedInputKind;
    std::wstring structuredStrategy;
    bool structured = true;
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    bool verifyStructure = false;
    bool autoIndentDetected = false;
    bool autoIndentCorrectionApplied = false;
    int targetIndentSpacesMax = 0;
    int actualIndentCorrectionKeys = 0;
    bool lineInputVerified = false;
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
    bool postInputCodeStructureVerified = false;
    bool realKeyboardEvents = true;
    bool expensiveObserveAfterEachLine = false;
    bool newlineAsUnicode = false;
    bool tabAsUnicode = false;
    bool firstPassMultilineCorrect = true;
    bool codeCollapsedToSingleLine = false;
    bool selfselfAutocompleteArtifact = false;
    bool firstPassFailed = false;
    bool clipboardUsed = false;
    std::wstring clipboardFallbackReason;
    bool backendFileWriteUsed = false;
    bool targetWindowLocked = false;
    bool targetInputVerified = false;
    TargetWindowLockResult targetLock;
    VisibleOperationPolicyResult operationPriority;
    StructuredTextInputResult structuredInput;
};

VisibleTextInputResult type_text_as_keyboard_events(const VisibleTextInputOptions& options);
VisibleTextInputResult type_line_by_line(const VisibleTextInputOptions& options);
VisibleTextInputResult type_multiline_text(const VisibleTextInputOptions& options);
VisibleTextInputResult type_code_with_indentation(const VisibleTextInputOptions& options);
VisibleTextInputResult type_form_value(const VisibleTextInputOptions& options);
VisibleTextInputResult type_message_text(const VisibleTextInputOptions& options);
bool verify_visible_text_inserted(const VisibleTextInputResult& result);
bool reject_unapproved_clipboard_paste(const VisibleTextInputOptions& options, std::wstring& errorCode, std::wstring& errorMessage);
bool detect_backend_file_write_attempt(const VisibleTextInputOptions& options, std::wstring& errorCode, std::wstring& errorMessage);
VisibleTextInputResult ApplyVisibleTextInputPolicy(const VisibleTextInputOptions& options);
std::wstring VisibleTextInputJson(const VisibleTextInputResult& result);
