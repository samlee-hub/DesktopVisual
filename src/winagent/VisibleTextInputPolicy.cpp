#include "VisibleTextInputPolicy.h"

#include "InputController.h"
#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>

namespace {

std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool IsKeyboardInputMethod(const std::wstring& method) {
    return method == L"real_keyboard_events" ||
           method == L"line_by_line_keyboard" ||
           method == L"code_editor_keyboard";
}

std::wstring NormalizeTypingProfile(const std::wstring& profile) {
    if (profile.empty()) return L"standard-real-keyboard";
    return profile;
}

bool IsCodeInput(const VisibleTextInputOptions& options) {
    std::wstring kind = ToLower(options.inputKind);
    return options.inputMethod == L"code_editor_keyboard" ||
           NormalizeInputKind(kind) == L"code_editor_text" ||
           kind.find(L"code") != std::wstring::npos ||
           kind.find(L"editor") != std::wstring::npos ||
           kind.find(L"ide") != std::wstring::npos ||
           LooksLikeStructuredCode(options.text);
}

bool ContainsSelfSelf(const std::wstring& text) {
    return text.find(L"selfself") != std::wstring::npos;
}

void ApplyPlanFields(const KeyboardTextInputPlan& plan, VisibleTextInputResult& result) {
    result.keyboardEventCount = plan.keyboardEventCount;
    result.unicodeCharEventCount = plan.unicodeCharEventCount;
    result.enterKeyEventCount = plan.enterKeyEventCount;
    result.tabKeyEventCount = plan.tabKeyEventCount;
    result.crlfNewlineCount = plan.crlfNewlineCount;
    result.lfNewlineCount = plan.lfNewlineCount;
    result.crNewlineCount = plan.crNewlineCount;
    result.typedCharCount = plan.typedCharCount;
    result.typedLineCount = plan.typedLineCount;
    result.newlineAsUnicode = plan.newlineAsUnicode;
    result.tabAsUnicode = plan.tabAsUnicode;
    result.codeCollapsedToSingleLine = plan.multiline && plan.enterKeyEventCount == 0;
    result.firstPassMultilineCorrect = !result.codeCollapsedToSingleLine &&
                                       !plan.newlineAsUnicode &&
                                       !plan.tabAsUnicode;
}

VisibleTextInputResult Fail(const VisibleTextInputOptions& options, const std::wstring& code, const std::wstring& message) {
    VisibleTextInputResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.inputMethod = options.inputMethod.empty() ? L"real_keyboard_events" : options.inputMethod;
    ApplyPlanFields(BuildKeyboardTextInputPlan(options.text), result);
    result.selfselfAutocompleteArtifact = IsCodeInput(options) && ContainsSelfSelf(options.text);
    result.firstPassFailed = result.codeCollapsedToSingleLine || result.selfselfAutocompleteArtifact;
    if (result.firstPassFailed) {
        result.firstPassMultilineCorrect = false;
    }
    result.backendFileWriteUsed = options.backendFileWriteUsed;
    result.typingProfile = NormalizeTypingProfile(options.typingProfile);
    result.charDelayMs = options.charDelayMs;
    result.lineDelayMs = options.lineDelayMs;
    result.batchKeyEvents = options.batchKeyEvents;
    result.inputKind = options.inputKind;
    result.resolvedInputKind = InferStructuredInputKind(options.text, options.inputKind);
    result.structured = true;
    result.indentMode = NormalizeIndentMode(options.indentMode);
    result.indentWidth = options.indentWidth <= 0 ? 4 : options.indentWidth;
    result.verifyStructure = options.verifyStructure;
    return result;
}

VisibleOperationPolicyResult TextInputOperationPriority(const VisibleTextInputOptions& options) {
    VisibleOperationPolicyOptions priority;
    priority.operationType = L"text_input";
    bool clipboard = options.inputMethod == L"clipboard_paste";
    bool keyboard = IsKeyboardInputMethod(options.inputMethod);
    priority.backendFallbackKind = clipboard ? L"clipboard_paste" : L"";
    priority.backendFallbackUsed = clipboard;
    priority.backendFallbackReason = options.clipboardFallbackReason;
    priority.explicitBackendRequested = options.explicitBackendRequested;
    priority.maxAttemptsExceeded = options.maxAttemptsExceeded;
    priority.visibleMouseKeyboardAttempted = keyboard ? true : options.visibleMouseKeyboardAttempted;
    priority.attempt1Result = keyboard ? L"succeeded" : options.visibleAttemptResult;
    priority.attempt1FailureReason = options.visibleFailureReason;
    priority.visibleAttemptCount = options.visibleAttemptCount;
    priority.minVisibleAttemptsBeforeShortcut = options.minVisibleAttemptsBeforeShortcut;
    priority.preActionCheckpointPresent = options.preActionCheckpointPresent;
    priority.boundedRecoveryAttempted = options.boundedRecoveryAttempted;
    priority.postRecoveryObserved = options.postRecoveryObserved;
    priority.sameSurfaceAfterRecovery = options.sameSurfaceAfterRecovery;
    priority.surfaceImpossible = options.surfaceImpossible;
    priority.surfaceImpossibleReason = options.surfaceImpossibleReason;
    priority.surfaceImpossibleEvidencePresent = options.surfaceImpossibleEvidencePresent;
    priority.keyboardShortcutAttempted = options.keyboardShortcutAttempted;
    priority.attempt2Result = options.keyboardShortcutResult;
    priority.attempt2FailureReason = options.keyboardShortcutFailureReason;
    priority.attempt3Result = clipboard ? L"succeeded" : L"not_attempted";
    priority.finalModeUsed = clipboard ? L"backend_fallback" : L"visible_mouse_keyboard";
    return enforce_visible_operation_priority(priority);
}

}  // namespace

bool reject_unapproved_clipboard_paste(const VisibleTextInputOptions& options, std::wstring& errorCode, std::wstring& errorMessage) {
    if (options.inputMethod == L"clipboard_paste" && !options.allowClipboard) {
        errorCode = L"FAIL_CLIPBOARD_INPUT_NOT_ALLOWED";
        errorMessage = L"Clipboard paste is a visible text input fallback and was not approved.";
        return false;
    }
    return true;
}

bool detect_backend_file_write_attempt(const VisibleTextInputOptions& options, std::wstring& errorCode, std::wstring& errorMessage) {
    if (options.backendFileWriteUsed) {
        errorCode = L"FAIL_BACKEND_TEXT_WRITE_FORBIDDEN";
        errorMessage = L"Backend file writes cannot be reported as visible UI text input.";
        return true;
    }
    return false;
}

VisibleTextInputResult ApplyVisibleTextInputPolicy(const VisibleTextInputOptions& options) {
    VisibleTextInputOptions normalized = options;
    if (normalized.inputMethod.empty()) {
        normalized.inputMethod = L"real_keyboard_events";
    }
    if (!IsKeyboardInputMethod(normalized.inputMethod) && normalized.inputMethod != L"clipboard_paste") {
        return Fail(normalized, L"INVALID_ARGUMENT", L"--input-method must be real_keyboard_events, line_by_line_keyboard, code_editor_keyboard, or clipboard_paste.");
    }

    std::wstring errorCode;
    std::wstring errorMessage;
    if (detect_backend_file_write_attempt(normalized, errorCode, errorMessage)) {
        return Fail(normalized, errorCode, errorMessage);
    }
    if (!reject_unapproved_clipboard_paste(normalized, errorCode, errorMessage)) {
        return Fail(normalized, errorCode, errorMessage);
    }
    TargetWindowLockOptions lockOptions;
    lockOptions.targetTitle = normalized.targetTitle;
    lockOptions.targetHwnd = normalized.targetHwnd;
    lockOptions.targetProcess = normalized.targetProcess;
    lockOptions.requireTargetLock = normalized.requireTargetLock;
    lockOptions.allowGlobalDesktop = normalized.allowGlobalDesktop;
    lockOptions.allowDryRunTarget = normalized.allowDryRunTarget || normalized.dryRun;
    TargetWindowLockResult lock = acquire_target_window_lock(lockOptions);
    if (!lock.ok || (normalized.requireTargetLock && !lock.targetWindowLocked)) {
        std::wstring code = lock.errorCode;
        if (code.empty() || code == L"FAIL_TARGET_LOCK_REQUIRED") {
            code = L"FAIL_TEXT_INPUT_TARGET_NOT_LOCKED";
        }
        VisibleTextInputResult result = Fail(normalized, code, lock.errorMessage.empty() ? L"Visible text input requires a target window lock." : lock.errorMessage);
        result.targetLock = lock;
        result.targetWindowLocked = lock.targetWindowLocked;
        return result;
    }

    VisibleOperationPolicyResult priority = TextInputOperationPriority(normalized);
    if (!priority.ok) {
        VisibleTextInputResult result = Fail(normalized, priority.errorCode, priority.errorMessage);
        result.clipboardUsed = normalized.inputMethod == L"clipboard_paste";
        result.clipboardFallbackReason = result.clipboardUsed ? normalized.clipboardFallbackReason : L"";
        result.targetLock = lock;
        result.targetWindowLocked = lock.targetWindowLocked;
        result.operationPriority = priority;
        return result;
    }

    VisibleTextInputResult result;
    result.ok = true;
    result.inputMethod = normalized.inputMethod;
    result.typingProfile = NormalizeTypingProfile(normalized.typingProfile);
    result.charDelayMs = normalized.charDelayMs;
    result.lineDelayMs = normalized.lineDelayMs;
    result.batchKeyEvents = normalized.batchKeyEvents || result.typingProfile == L"fast-real-keyboard";
    result.inputKind = normalized.inputKind;
    result.resolvedInputKind = InferStructuredInputKind(normalized.text, normalized.inputKind);
    result.structured = true;
    result.indentMode = NormalizeIndentMode(normalized.indentMode);
    result.indentWidth = normalized.indentWidth <= 0 ? 4 : normalized.indentWidth;
    result.verifyStructure = normalized.verifyStructure;
    result.realKeyboardEvents = IsKeyboardInputMethod(normalized.inputMethod);
    result.expensiveObserveAfterEachLine = false;
    ApplyPlanFields(BuildKeyboardTextInputPlan(normalized.text), result);
    result.selfselfAutocompleteArtifact = IsCodeInput(normalized) && ContainsSelfSelf(normalized.text);
    result.firstPassFailed = result.codeCollapsedToSingleLine || result.selfselfAutocompleteArtifact;
    if (result.firstPassFailed) {
        result.firstPassMultilineCorrect = false;
    }
    result.clipboardUsed = normalized.inputMethod == L"clipboard_paste";
    result.clipboardFallbackReason = result.clipboardUsed ? normalized.clipboardFallbackReason : L"";
    result.backendFileWriteUsed = false;
    result.targetWindowLocked = lock.targetWindowLocked;
    result.targetLock = lock;
    result.operationPriority = priority;

    if (!normalized.dryRun && IsKeyboardInputMethod(normalized.inputMethod)) {
        StructuredTextInputOptions structured;
        structured.text = normalized.text;
        structured.inputKind = normalized.inputKind;
        structured.inputMethod = normalized.inputMethod;
        structured.structured = normalized.structured;
        structured.indentMode = normalized.indentMode;
        structured.indentWidth = normalized.indentWidth;
        structured.verifyStructure = normalized.verifyStructure;
        structured.dryRun = false;
        structured.submitEnter = normalized.submitEnter;
        structured.charDelayMs = normalized.charDelayMs;
        structured.lineDelayMs = normalized.lineDelayMs;
        structured.batchKeyEvents = result.batchKeyEvents;
        structured.typingProfile = result.typingProfile;
        structured.verifierRunSucceeded = normalized.verifierRunSucceeded;
        StructuredTextInputResult structuredResult = ApplyStructuredTextInputPolicy(lock.target.hwnd, structured);
        result.structuredInput = structuredResult;
        result.resolvedInputKind = structuredResult.resolvedInputKind;
        result.structuredStrategy = structuredResult.strategy;
        result.indentMode = structuredResult.indentMode;
        result.indentWidth = structuredResult.indentWidth;
        result.verifyStructure = structuredResult.verifyStructure;
        result.autoIndentDetected = structuredResult.autoIndentDetected;
        result.autoIndentCorrectionApplied = structuredResult.autoIndentCorrectionApplied;
        result.targetIndentSpacesMax = structuredResult.targetIndentSpacesMax;
        result.actualIndentCorrectionKeys = structuredResult.actualIndentCorrectionKeys;
        result.lineInputVerified = structuredResult.lineInputVerified;
        result.codeStructureVerified = structuredResult.codeStructureVerified;
        result.codeWritePlanUsed = structuredResult.codeWritePlanUsed;
        result.languageScopeModelUsed = structuredResult.languageScopeModelUsed;
        result.preInputCodeStructureVerifierUsed = structuredResult.preInputCodeStructureVerifierUsed;
        result.preInputCodeStructureVerified = structuredResult.preInputCodeStructureVerified;
        result.editorAutoIndentModelUsed = structuredResult.editorAutoIndentModelUsed;
        result.cursorBufferStateVerified = structuredResult.cursorBufferStateVerified;
        result.oldBufferClearedOrSafeReplaceVerified = structuredResult.oldBufferClearedOrSafeReplaceVerified;
        result.noRetryContamination = structuredResult.noRetryContamination;
        result.incrementalCodeInputVerifierUsed = structuredResult.incrementalCodeInputVerifierUsed;
        result.realKeyboardCodeInputPolicy = structuredResult.realKeyboardCodeInputPolicy;
        result.receiverBindingVerified = structuredResult.receiverBindingVerified;
        result.duplicateReceiverTokenDetected = structuredResult.duplicateReceiverTokenDetected;
        result.repairReplaceNotAppend = structuredResult.repairReplaceNotAppend;
        result.selfselfPresent = structuredResult.selfselfPresent;
        result.postInputCodeStructureVerified = structuredResult.codeStructureVerified;
        result.targetInputVerified = structuredResult.lineInputVerified;
        result.keyboardSendBatchCount = structuredResult.typeResult.keyboardSendBatchCount;
        result.batchKeyEvents = structuredResult.typeResult.batchKeyEvents || result.batchKeyEvents;
        if (!structuredResult.ok) {
            result.ok = false;
            result.errorCode = structuredResult.errorCode.empty() ? L"FAIL_TEXT_INPUT_NOT_VERIFIED" : structuredResult.errorCode;
            result.errorMessage = structuredResult.errorMessage.empty() ? L"Keyboard text input failed." : structuredResult.errorMessage;
            result.targetInputVerified = false;
        }
    } else if (normalized.dryRun && IsKeyboardInputMethod(normalized.inputMethod)) {
        StructuredTextInputOptions structured;
        structured.text = normalized.text;
        structured.inputKind = normalized.inputKind;
        structured.inputMethod = normalized.inputMethod;
        structured.structured = normalized.structured;
        structured.indentMode = normalized.indentMode;
        structured.indentWidth = normalized.indentWidth;
        structured.verifyStructure = normalized.verifyStructure;
        structured.dryRun = true;
        structured.submitEnter = normalized.submitEnter;
        structured.charDelayMs = normalized.charDelayMs;
        structured.lineDelayMs = normalized.lineDelayMs;
        structured.batchKeyEvents = result.batchKeyEvents;
        structured.typingProfile = result.typingProfile;
        structured.verifierRunSucceeded = normalized.verifierRunSucceeded;
        StructuredTextInputResult structuredResult = ApplyStructuredTextInputPolicy(nullptr, structured);
        result.structuredInput = structuredResult;
        result.resolvedInputKind = structuredResult.resolvedInputKind;
        result.structuredStrategy = structuredResult.strategy;
        result.indentMode = structuredResult.indentMode;
        result.indentWidth = structuredResult.indentWidth;
        result.verifyStructure = structuredResult.verifyStructure;
        result.autoIndentDetected = structuredResult.autoIndentDetected;
        result.autoIndentCorrectionApplied = structuredResult.autoIndentCorrectionApplied;
        result.targetIndentSpacesMax = structuredResult.targetIndentSpacesMax;
        result.actualIndentCorrectionKeys = structuredResult.actualIndentCorrectionKeys;
        result.lineInputVerified = structuredResult.lineInputVerified;
        result.codeStructureVerified = structuredResult.codeStructureVerified;
        result.codeWritePlanUsed = structuredResult.codeWritePlanUsed;
        result.languageScopeModelUsed = structuredResult.languageScopeModelUsed;
        result.preInputCodeStructureVerifierUsed = structuredResult.preInputCodeStructureVerifierUsed;
        result.preInputCodeStructureVerified = structuredResult.preInputCodeStructureVerified;
        result.editorAutoIndentModelUsed = structuredResult.editorAutoIndentModelUsed;
        result.cursorBufferStateVerified = structuredResult.cursorBufferStateVerified;
        result.oldBufferClearedOrSafeReplaceVerified = structuredResult.oldBufferClearedOrSafeReplaceVerified;
        result.noRetryContamination = structuredResult.noRetryContamination;
        result.incrementalCodeInputVerifierUsed = structuredResult.incrementalCodeInputVerifierUsed;
        result.realKeyboardCodeInputPolicy = structuredResult.realKeyboardCodeInputPolicy;
        result.receiverBindingVerified = structuredResult.receiverBindingVerified;
        result.duplicateReceiverTokenDetected = structuredResult.duplicateReceiverTokenDetected;
        result.repairReplaceNotAppend = structuredResult.repairReplaceNotAppend;
        result.selfselfPresent = structuredResult.selfselfPresent;
        result.postInputCodeStructureVerified = structuredResult.codeStructureVerified;
        result.targetInputVerified = structuredResult.lineInputVerified;
        result.keyboardSendBatchCount = structuredResult.typeResult.keyboardSendBatchCount;
        result.batchKeyEvents = structuredResult.typeResult.batchKeyEvents || result.batchKeyEvents;
        if (!structuredResult.ok) {
            result.ok = false;
            result.errorCode = structuredResult.errorCode.empty() ? L"FAIL_TEXT_INPUT_NOT_VERIFIED" : structuredResult.errorCode;
            result.errorMessage = structuredResult.errorMessage.empty() ? L"Keyboard text input failed." : structuredResult.errorMessage;
            result.targetInputVerified = false;
        }
    } else {
        result.targetInputVerified = !result.clipboardUsed;
        if (result.batchKeyEvents) {
            result.keyboardSendBatchCount = result.typedLineCount > 0 ? result.typedLineCount : (result.typedCharCount > 0 ? 1 : 0);
        }
    }
    return result;
}

VisibleTextInputResult type_text_as_keyboard_events(const VisibleTextInputOptions& options) {
    VisibleTextInputOptions normalized = options;
    normalized.inputMethod = L"real_keyboard_events";
    return ApplyVisibleTextInputPolicy(normalized);
}

VisibleTextInputResult type_line_by_line(const VisibleTextInputOptions& options) {
    VisibleTextInputOptions normalized = options;
    normalized.inputMethod = L"line_by_line_keyboard";
    return ApplyVisibleTextInputPolicy(normalized);
}

VisibleTextInputResult type_multiline_text(const VisibleTextInputOptions& options) {
    VisibleTextInputOptions normalized = options;
    normalized.inputMethod = L"line_by_line_keyboard";
    return ApplyVisibleTextInputPolicy(normalized);
}

VisibleTextInputResult type_code_with_indentation(const VisibleTextInputOptions& options) {
    VisibleTextInputOptions normalized = options;
    normalized.inputMethod = L"code_editor_keyboard";
    return ApplyVisibleTextInputPolicy(normalized);
}

VisibleTextInputResult type_form_value(const VisibleTextInputOptions& options) {
    return type_text_as_keyboard_events(options);
}

VisibleTextInputResult type_message_text(const VisibleTextInputOptions& options) {
    return type_text_as_keyboard_events(options);
}

bool verify_visible_text_inserted(const VisibleTextInputResult& result) {
    return result.ok && result.targetInputVerified && !result.backendFileWriteUsed;
}

std::wstring VisibleTextInputJson(const VisibleTextInputResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"input_method\":" + simplejson::Quote(result.inputMethod);
    json += L",\"keyboard_event_count\":" + std::to_wstring(result.keyboardEventCount);
    json += L",\"unicode_char_event_count\":" + std::to_wstring(result.unicodeCharEventCount);
    json += L",\"enter_key_event_count\":" + std::to_wstring(result.enterKeyEventCount);
    json += L",\"tab_key_event_count\":" + std::to_wstring(result.tabKeyEventCount);
    json += L",\"crlf_newline_count\":" + std::to_wstring(result.crlfNewlineCount);
    json += L",\"lf_newline_count\":" + std::to_wstring(result.lfNewlineCount);
    json += L",\"cr_newline_count\":" + std::to_wstring(result.crNewlineCount);
    json += L",\"typed_char_count\":" + std::to_wstring(result.typedCharCount);
    json += L",\"typed_line_count\":" + std::to_wstring(result.typedLineCount);
    json += L",\"input_kind\":" + simplejson::Quote(result.inputKind);
    json += L",\"resolved_input_kind\":" + simplejson::Quote(result.resolvedInputKind);
    json += L",\"structured_strategy\":" + simplejson::Quote(result.structuredStrategy);
    json += L",\"structured\":" + simplejson::Bool(result.structured);
    json += L",\"indent_mode\":" + simplejson::Quote(result.indentMode);
    json += L",\"indent_width\":" + std::to_wstring(result.indentWidth);
    json += L",\"verify_structure\":" + simplejson::Bool(result.verifyStructure);
    json += L",\"auto_indent_detected\":" + simplejson::Bool(result.autoIndentDetected);
    json += L",\"auto_indent_correction_applied\":" + simplejson::Bool(result.autoIndentCorrectionApplied);
    json += L",\"target_indent_spaces\":" + std::to_wstring(result.targetIndentSpacesMax);
    json += L",\"actual_indent_correction_keys\":" + std::to_wstring(result.actualIndentCorrectionKeys);
    json += L",\"line_input_verified\":" + simplejson::Bool(result.lineInputVerified);
    json += L",\"code_structure_verified\":" + simplejson::Bool(result.codeStructureVerified);
    json += L",\"code_write_plan_used\":" + simplejson::Bool(result.codeWritePlanUsed);
    json += L",\"language_scope_model_used\":" + simplejson::Bool(result.languageScopeModelUsed);
    json += L",\"preinput_code_structure_verifier_used\":" + simplejson::Bool(result.preInputCodeStructureVerifierUsed);
    json += L",\"preinput_code_structure_verified\":" + simplejson::Bool(result.preInputCodeStructureVerified);
    json += L",\"pre_input_code_structure_verifier_used\":" + simplejson::Bool(result.preInputCodeStructureVerifierUsed);
    json += L",\"pre_input_code_structure_verified\":" + simplejson::Bool(result.preInputCodeStructureVerified);
    json += L",\"editor_auto_indent_model_used\":" + simplejson::Bool(result.editorAutoIndentModelUsed);
    json += L",\"cursor_buffer_state_verified\":" + simplejson::Bool(result.cursorBufferStateVerified);
    json += L",\"old_buffer_cleared_or_safe_replace_verified\":" + simplejson::Bool(result.oldBufferClearedOrSafeReplaceVerified);
    json += L",\"no_retry_contamination\":" + simplejson::Bool(result.noRetryContamination);
    json += L",\"incremental_code_input_verifier_used\":" + simplejson::Bool(result.incrementalCodeInputVerifierUsed);
    json += L",\"real_keyboard_code_input_policy\":" + simplejson::Bool(result.realKeyboardCodeInputPolicy);
    json += L",\"receiver_binding_verified\":" + simplejson::Bool(result.receiverBindingVerified);
    json += L",\"duplicate_receiver_token_detected\":" + simplejson::Bool(result.duplicateReceiverTokenDetected);
    json += L",\"repair_replace_not_append\":" + simplejson::Bool(result.repairReplaceNotAppend);
    json += L",\"selfself_present\":" + simplejson::Bool(result.selfselfPresent);
    json += L",\"postinput_code_structure_verified\":" + simplejson::Bool(result.postInputCodeStructureVerified);
    json += L",\"post_input_code_structure_verified\":" + simplejson::Bool(result.postInputCodeStructureVerified);
    json += L",\"typing_profile\":" + simplejson::Quote(result.typingProfile);
    json += L",\"char_delay_ms\":" + std::to_wstring(result.charDelayMs);
    json += L",\"line_delay_ms\":" + std::to_wstring(result.lineDelayMs);
    json += L",\"batch_key_events\":" + simplejson::Bool(result.batchKeyEvents);
    json += L",\"keyboard_send_batch_count\":" + std::to_wstring(result.keyboardSendBatchCount);
    json += L",\"real_keyboard_events\":" + simplejson::Bool(result.realKeyboardEvents);
    json += L",\"expensive_observe_after_each_line\":" + simplejson::Bool(result.expensiveObserveAfterEachLine);
    json += L",\"newline_as_unicode\":" + simplejson::Bool(result.newlineAsUnicode);
    json += L",\"tab_as_unicode\":" + simplejson::Bool(result.tabAsUnicode);
    json += L",\"first_pass_multiline_correct\":" + simplejson::Bool(result.firstPassMultilineCorrect);
    json += L",\"code_collapsed_to_single_line\":" + simplejson::Bool(result.codeCollapsedToSingleLine);
    json += L",\"selfself_autocomplete_artifact\":" + simplejson::Bool(result.selfselfAutocompleteArtifact);
    json += L",\"first_pass_failed\":" + simplejson::Bool(result.firstPassFailed);
    json += L",\"clipboard_used\":" + simplejson::Bool(result.clipboardUsed);
    json += L",\"clipboard_fallback_reason\":" + simplejson::Quote(result.clipboardFallbackReason);
    json += L",\"backend_file_write_used\":" + simplejson::Bool(result.backendFileWriteUsed);
    json += L",\"target_window_locked\":" + simplejson::Bool(result.targetWindowLocked);
    json += L",\"target_input_verified\":" + simplejson::Bool(result.targetInputVerified);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"structured_input\":" + StructuredTextInputResultJson(result.structuredInput);
    json += L",\"target_lock\":" + TargetWindowLockJson(result.targetLock);
    json += L",\"operation_priority\":" + VisibleOperationPolicyJson(result.operationPriority);
    json += L"}";
    return json;
}
