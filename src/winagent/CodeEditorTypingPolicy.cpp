#include "CodeEditorTypingPolicy.h"

#include "SimpleJson.h"

#include <cwctype>

namespace {

void MergeActionFailure(const ActionResult& action, CodeEditorTypingResult& result, const std::wstring& fallbackCode, const std::wstring& fallbackMessage) {
    if (action.ok) return;
    result.ok = false;
    result.errorCode = action.errorCode.empty() ? fallbackCode : action.errorCode;
    result.errorMessage = action.error.empty() ? fallbackMessage : action.error;
}

void MergeTypeFailure(const TypeResult& typed, CodeEditorTypingResult& result, const std::wstring& fallbackCode, const std::wstring& fallbackMessage) {
    if (typed.ok) return;
    result.ok = false;
    result.errorCode = typed.errorCode.empty() ? fallbackCode : typed.errorCode;
    result.errorMessage = typed.error.empty() ? fallbackMessage : typed.error;
}

std::wstring TypeModeForOptions(const CodeEditorTypingOptions& options) {
    return options.typingProfile == L"fast-real-keyboard" ? L"fast-human" : L"fast-human";
}

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    return value.rfind(prefix, 0) == 0;
}

int EffectiveCodeCharDelayMs(const CodeEditorTypingOptions& options) {
    return options.charDelayMs > 0 ? options.charDelayMs : 16;
}

int EffectiveCodeLineDelayMs(const CodeEditorTypingOptions& options) {
    return options.lineDelayMs > 0 ? options.lineDelayMs : 45;
}

bool DismissEditorCompletion(HWND hwnd, bool dryRun, CodeEditorTypingResult& result) {
    result.completionSuppressionApplied = true;
    ++result.completionSuppressionKeyCount;
    ++result.keyboardSendBatchCount;
    if (dryRun) return true;
    ActionResult esc = PressKey(hwnd, L"ESC");
    if (!esc.ok) {
        MergeActionFailure(esc, result, L"FAIL_DISMISS_EDITOR_COMPLETION", L"Could not dismiss editor completion before structured input.");
        return false;
    }
    return true;
}

bool BuildPythonReceiverAwareTypingPlan(
    const StructuredCodeLine& line,
    std::wstring& methodName,
    std::wstring& prefixThroughOpenParen,
    std::wstring& receiver,
    std::wstring& suffixAfterReceiver) {
    if (line.targetIndentSpaces <= 0) return false;
    const std::wstring& content = line.contentWithoutIndent;
    if (!StartsWith(content, L"def ")) return false;
    size_t open = content.find(L'(');
    if (open == std::wstring::npos || open <= 4) return false;
    methodName = content.substr(4, open - 4);
    while (!methodName.empty() && std::iswspace(methodName.front())) methodName.erase(methodName.begin());
    while (!methodName.empty() && std::iswspace(methodName.back())) methodName.pop_back();
    size_t receiverStart = open + 1;
    if (content.compare(receiverStart, 4, L"self") == 0) {
        receiver = L"self";
    } else if (content.compare(receiverStart, 3, L"cls") == 0) {
        receiver = L"cls";
    } else {
        return false;
    }
    prefixThroughOpenParen = content.substr(0, receiverStart);
    suffixAfterReceiver = content.substr(receiverStart + receiver.size());
    return !methodName.empty();
}

bool type_python_method_header_content(
    HWND hwnd,
    bool dryRun,
    const StructuredCodeLine& line,
    const CodeEditorTypingOptions& options,
    CodeEditorTypingResult& result) {
    std::wstring methodName;
    std::wstring prefix;
    std::wstring receiver;
    std::wstring suffix;
    if (!BuildPythonReceiverAwareTypingPlan(line, methodName, prefix, receiver, suffix)) {
        return false;
    }

    result.smartCompletionModel = true;
    if (dryRun) return true;

    if (!DismissEditorCompletion(hwnd, dryRun, result)) return true;
    ++result.keyboardSendBatchCount;
    TypeResult prefixTyped = TypeText(hwnd, prefix, TypeModeForOptions(options), EffectiveCodeCharDelayMs(options));
    result.typeResult = prefixTyped;
    if (!prefixTyped.ok) {
        MergeTypeFailure(prefixTyped, result, L"FAIL_TYPE_LINE_CONTENT", L"Could not type Python method header prefix.");
        return true;
    }

    Sleep(180);
    DismissEditorCompletion(hwnd, dryRun, result);
    bool receiverAlreadyInserted = true;
    std::wstring remainder = receiverAlreadyInserted ? suffix : (receiver + suffix);
    result.smartCompletionAdjustmentApplied = true;
    ++result.smartCompletionAdjustedLineCount;
    if (!remainder.empty()) {
        ++result.keyboardSendBatchCount;
        TypeResult suffixTyped = TypeText(hwnd, remainder, TypeModeForOptions(options), EffectiveCodeCharDelayMs(options));
        result.typeResult = suffixTyped;
        if (!suffixTyped.ok) {
            MergeTypeFailure(suffixTyped, result, L"FAIL_TYPE_LINE_CONTENT", L"Could not type Python method header suffix.");
        }
    }
    return true;
}

}  // namespace

std::vector<StructuredCodeLine> parse_code_lines(const std::wstring& text, const CodeEditorTypingOptions& options) {
    IndentationOptions indent;
    indent.indentMode = options.indentMode;
    indent.indentWidth = options.indentWidth;
    return ::parse_code_lines(text, indent);
}

bool enter_new_line(HWND hwnd, bool dryRun, CodeEditorTypingResult& result) {
    ++result.keyboardSendBatchCount;
    if (dryRun) return true;
    ActionResult end = PressKey(hwnd, L"END");
    if (!end.ok) {
        MergeActionFailure(end, result, L"FAIL_ENTER_NEW_LINE_END", L"Could not move to line end before entering a new editor line.");
        return false;
    }
    ++result.enterKeyEventCount;
    ++result.keyboardSendBatchCount;
    ActionResult enter = PressKey(hwnd, L"ENTER");
    if (!enter.ok) {
        MergeActionFailure(enter, result, L"FAIL_ENTER_NEW_LINE", L"Could not enter a new editor line.");
        return false;
    }
    return true;
}

bool reset_current_line_indent(HWND hwnd, bool dryRun, const IndentationLinePlan& plan, CodeEditorTypingResult& result) {
    if (!plan.explicitIndentCorrectionApplied || plan.indentDeltaSpaces >= 0) return true;
    result.autoIndentDetected = result.autoIndentDetected || plan.autoIndentDetected;
    result.autoIndentCorrectionApplied = true;
    result.actualIndentCorrectionKeys += plan.actualIndentCorrectionKeys;
    result.keyboardSendBatchCount += plan.actualIndentCorrectionKeys;
    if (dryRun) return true;

    if (!DismissEditorCompletion(hwnd, dryRun, result)) return false;
    for (int i = 0; i < plan.actualIndentCorrectionKeys; ++i) {
        ActionResult outdent = SendHotkey(hwnd, L"SHIFT+TAB");
        if (!outdent.ok) {
            MergeActionFailure(outdent, result, L"FAIL_RESET_LINE_SHIFT_TAB", L"Could not clear editor auto-indent drift.");
            return false;
        }
    }
    return true;
}

bool apply_target_indent(HWND hwnd, bool dryRun, const IndentationLinePlan& plan, const CodeEditorTypingOptions& options, CodeEditorTypingResult& result) {
    if (plan.indentText.empty()) return true;
    ++result.keyboardSendBatchCount;
    if (dryRun) return true;
    TypeResult typed = TypeText(hwnd, plan.indentText, TypeModeForOptions(options), EffectiveCodeCharDelayMs(options));
    result.typeResult = typed;
    if (!typed.ok) {
        MergeTypeFailure(typed, result, L"FAIL_APPLY_TARGET_INDENT", L"Could not apply target code indentation.");
        return false;
    }
    return true;
}

bool type_line_content(HWND hwnd, bool dryRun, const StructuredCodeLine& line, const CodeEditorTypingOptions& options, CodeEditorTypingResult& result) {
    if (line.contentWithoutIndent.empty()) return true;
    if (result.language == L"python") {
        bool handled = type_python_method_header_content(hwnd, dryRun, line, options, result);
        if (handled) return result.ok;
    }
    ++result.keyboardSendBatchCount;
    std::wstring typingContent = line.contentWithoutIndent;
    if (dryRun) return true;

    if (!DismissEditorCompletion(hwnd, dryRun, result)) return false;
    TypeResult typed = TypeText(hwnd, typingContent, TypeModeForOptions(options), EffectiveCodeCharDelayMs(options));
    result.typeResult = typed;
    if (!typed.ok) {
        MergeTypeFailure(typed, result, L"FAIL_TYPE_LINE_CONTENT", L"Could not type code line content.");
        return false;
    }
    return true;
}

bool verify_code_structure(CodeEditorTypingResult& result, const CodeEditorTypingOptions& options) {
    TextInputVerificationOptions verify;
    verify.inputKind = L"code_editor_text";
    verify.expectedText = options.text;
    verify.verifyStructure = options.verifyStructure;
    verify.clipboardUsed = result.clipboardUsed;
    verify.backendFileWriteUsed = result.backendFileWriteUsed;
    verify.inputMethod = result.inputMethod;
    verify.runSucceeded = options.runSucceededForVerifier;
    result.verification = VerifyTextInputStructure(verify);
    result.postInputVerified = result.verification.ok;
    result.codeStructureVerified = result.verification.codeStructureVerified || (!options.verifyStructure && result.verification.ok);
    if (!result.verification.ok) {
        result.ok = false;
        result.errorCode = result.verification.errorCode.empty() ? L"CODE_STRUCTURE_MISMATCH" : result.verification.errorCode;
        result.errorMessage = result.verification.errorMessage.empty() ? L"Code structure verification failed." : result.verification.errorMessage;
        return false;
    }
    return true;
}

CodeEditorTypingResult ApplyCodeEditorTypingPolicy(HWND hwnd, const CodeEditorTypingOptions& options) {
    CodeEditorTypingOptions normalized = options;
    if (normalized.indentMode.empty()) normalized.indentMode = L"spaces";
    if (normalized.indentWidth <= 0) normalized.indentWidth = 4;

    CodeEditorTypingResult result;
    result.ok = true;
    result.indentMode = NormalizeIndentMode(normalized.indentMode);
    result.indentWidth = normalized.indentWidth;
    result.contentInsertionOrder = L"forward";

    IndentationOptions indent;
    indent.indentMode = result.indentMode;
    indent.indentWidth = result.indentWidth;
    result.writePlan = BuildCodeWritePlan(normalized.text, indent);
    result.repairEditPolicy = EvaluateRepairEditPolicyForPlan(result.writePlan);
    result.repairReplaceNotAppend = result.repairEditPolicy.repairReplaceNotAppend;
    result.duplicateReceiverTokenDetected = result.repairEditPolicy.duplicatedReceiverTokenDetected;
    result.editorAutoIndentModel = result.writePlan.editorAutoIndent.editorAutoIndentModel;
    result.languageScopeModel = result.writePlan.languageScope.languageScopeModel;
    result.codeWritePlan = result.writePlan.codeWritePlan;
    result.codeWritePlanUsed = result.codeWritePlan;
    result.languageScopeModelUsed = result.languageScopeModel;
    result.preInputVerification = VerifyPreInputCodeStructure(result.writePlan, normalized.verifyStructure);
    result.preInputCodeStructureVerifierUsed = result.preInputVerification.preInputCodeStructureVerifier;
    result.preInputCodeStructureVerified = result.preInputVerification.preInputCodeStructureVerified;
    result.editorAutoIndentModelUsed = result.editorAutoIndentModel;
    result.naturalAutoIndentFollowed = result.writePlan.editorAutoIndent.naturalAutoIndentFollowed;
    result.minimalIndentCorrection = result.writePlan.editorAutoIndent.minimalIndentCorrection;
    result.language = result.writePlan.language;
    result.smartCompletionModel = false;
    result.lines = result.writePlan.lines;
    result.parsedLineCount = static_cast<int>(result.lines.size());
    result.bufferGuard = PlanCursorAndBufferStateGuard(normalized.clearFirst);
    result.incrementalVerifier = VerifyIncrementalCodeInputPlan(result.writePlan);
    result.realKeyboardPolicy = EvaluateRealKeyboardCodeInputPolicy(
        result.writePlan,
        result.bufferGuard,
        result.incrementalVerifier,
        result.clipboardUsed,
        result.backendFileWriteUsed);
    result.cursorBufferStateVerified = result.bufferGuard.cursorBufferStateVerified;
    result.oldBufferClearedOrSafeReplaceVerified = result.bufferGuard.oldBufferClearedOrSafeReplaceVerified;
    result.noRetryContamination = result.bufferGuard.noRetryContamination && result.incrementalVerifier.noRetryContamination;
    result.incrementalCodeInputVerifierUsed = result.incrementalVerifier.incrementalCodeInputVerifier;
    result.realKeyboardCodeInputPolicy = result.realKeyboardPolicy.realKeyboardCodeInputPolicy;

    for (size_t i = 0; i < result.writePlan.editorAutoIndent.linePlans.size(); ++i) {
        IndentationLinePlan plan = result.writePlan.editorAutoIndent.linePlans[i];
        result.linePlans.push_back(plan);
        if (!result.lines[i].isBlankLine) ++result.nonBlankLineCount;
        if (plan.targetIndentSpaces > result.targetIndentSpacesMax) {
            result.targetIndentSpacesMax = plan.targetIndentSpaces;
        }
        result.autoIndentDetected = result.autoIndentDetected || plan.autoIndentDetected;
        result.autoIndentCorrectionApplied = result.autoIndentCorrectionApplied || plan.autoIndentCorrectionApplied;
    }

    if (!result.writePlan.ok) {
        result.ok = false;
        result.errorCode = result.preInputVerification.errorCode.empty() ? L"BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID" : result.preInputVerification.errorCode;
        result.errorMessage = result.preInputVerification.errorMessage.empty()
            ? (result.writePlan.findings.empty() ? L"Code write plan failed language scope validation." : result.writePlan.findings.front())
            : result.preInputVerification.errorMessage;
        result.verification = result.preInputVerification.textVerification;
        result.receiverBindingVerified = result.verification.receiverBindingVerified;
        result.duplicateReceiverTokenDetected = result.duplicateReceiverTokenDetected || result.verification.duplicateReceiverTokenDetected;
        result.selfselfPresent = result.verification.selfselfPresent;
        result.postInputVerified = false;
        result.codeStructureVerified = false;
        return result;
    }

    if (!result.preInputVerification.ok) {
        result.ok = false;
        result.errorCode = result.preInputVerification.errorCode.empty() ? L"BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID" : result.preInputVerification.errorCode;
        result.errorMessage = result.preInputVerification.errorMessage.empty() ? L"Pre-input code structure validation failed." : result.preInputVerification.errorMessage;
        result.verification = result.preInputVerification.textVerification;
        result.receiverBindingVerified = result.verification.receiverBindingVerified;
        result.duplicateReceiverTokenDetected = result.duplicateReceiverTokenDetected || result.verification.duplicateReceiverTokenDetected;
        result.selfselfPresent = result.verification.selfselfPresent;
        result.postInputVerified = false;
        result.codeStructureVerified = false;
        return result;
    }

    if (!result.incrementalVerifier.ok) {
        result.ok = false;
        result.errorCode = result.incrementalVerifier.errorCode.empty() ? L"STRUCTURED_CODE_INPUT_PLAN_INVALID" : result.incrementalVerifier.errorCode;
        result.errorMessage = result.incrementalVerifier.errorMessage.empty() ? L"Incremental code input verification failed before typing." : result.incrementalVerifier.errorMessage;
        return result;
    }

    if (!result.realKeyboardPolicy.ok) {
        result.ok = false;
        result.errorCode = result.realKeyboardPolicy.errorCode.empty() ? L"REAL_KEYBOARD_CODE_INPUT_POLICY_FAILED" : result.realKeyboardPolicy.errorCode;
        result.errorMessage = result.realKeyboardPolicy.errorMessage.empty() ? L"Real keyboard code input policy failed before typing." : result.realKeyboardPolicy.errorMessage;
        return result;
    }

    if (!normalized.dryRun && normalized.clearFirst) {
        result.bufferGuard = ClearCodeEditorBufferForRewrite(hwnd, normalized.dryRun, normalized.clearFirst);
        result.cursorBufferStateVerified = result.bufferGuard.cursorBufferStateVerified;
        result.oldBufferClearedOrSafeReplaceVerified = result.bufferGuard.oldBufferClearedOrSafeReplaceVerified;
        result.noRetryContamination = result.bufferGuard.noRetryContamination && result.incrementalVerifier.noRetryContamination;
        result.keyboardSendBatchCount += result.bufferGuard.keyboardSendBatchCount;
        result.realKeyboardPolicy = EvaluateRealKeyboardCodeInputPolicy(
            result.writePlan,
            result.bufferGuard,
            result.incrementalVerifier,
            result.clipboardUsed,
            result.backendFileWriteUsed);
        if (!result.bufferGuard.ok || !result.realKeyboardPolicy.ok) {
            result.ok = false;
            result.errorCode = !result.bufferGuard.ok ? result.bufferGuard.errorCode : result.realKeyboardPolicy.errorCode;
            result.errorMessage = !result.bufferGuard.ok ? result.bufferGuard.errorMessage : result.realKeyboardPolicy.errorMessage;
            return result;
        }
    } else if (normalized.clearFirst) {
        result.keyboardSendBatchCount += result.bufferGuard.keyboardSendBatchCount;
    }

    for (size_t i = 0; i < result.linePlans.size(); ++i) {
        const IndentationLinePlan& plan = result.linePlans[i];
        if (!reset_current_line_indent(hwnd, normalized.dryRun, plan, result)) return result;
        if (!apply_target_indent(hwnd, normalized.dryRun, plan, normalized, result)) return result;
        if (!type_line_content(hwnd, normalized.dryRun, plan.line, normalized, result)) return result;
        if (!DismissEditorCompletion(hwnd, normalized.dryRun, result)) return result;
        if (i + 1 < result.linePlans.size()) {
            if (!enter_new_line(hwnd, normalized.dryRun, result)) return result;
            if (!normalized.dryRun) {
                Sleep(static_cast<DWORD>(EffectiveCodeLineDelayMs(normalized)));
            }
        }
    }

    verify_code_structure(result, normalized);
    result.receiverBindingVerified = result.verification.receiverBindingVerified;
    result.duplicateReceiverTokenDetected = result.duplicateReceiverTokenDetected || result.verification.duplicateReceiverTokenDetected;
    result.selfselfPresent = result.verification.selfselfPresent;
    return result;
}

std::wstring CodeEditorTypingResultJson(const CodeEditorTypingResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"strategy\":" + simplejson::Quote(result.strategy);
    json += L",\"input_method\":" + simplejson::Quote(result.inputMethod);
    json += L",\"language\":" + simplejson::Quote(result.language);
    json += L",\"indent_mode\":" + simplejson::Quote(result.indentMode);
    json += L",\"indent_width\":" + std::to_wstring(result.indentWidth);
    json += L",\"parsed_line_count\":" + std::to_wstring(result.parsedLineCount);
    json += L",\"non_blank_line_count\":" + std::to_wstring(result.nonBlankLineCount);
    json += L",\"keyboard_send_batch_count\":" + std::to_wstring(result.keyboardSendBatchCount);
    json += L",\"enter_key_event_count\":" + std::to_wstring(result.enterKeyEventCount);
    json += L",\"target_indent_spaces_max\":" + std::to_wstring(result.targetIndentSpacesMax);
    json += L",\"actual_indent_correction_keys\":" + std::to_wstring(result.actualIndentCorrectionKeys);
    json += L",\"auto_indent_detected\":" + simplejson::Bool(result.autoIndentDetected);
    json += L",\"auto_indent_correction_applied\":" + simplejson::Bool(result.autoIndentCorrectionApplied);
    json += L",\"line_aware\":" + simplejson::Bool(result.lineAware);
    json += L",\"indent_aware\":" + simplejson::Bool(result.indentAware);
    json += L",\"auto_indent_aware\":" + simplejson::Bool(result.autoIndentAware);
    json += L",\"editor_auto_indent_model\":" + simplejson::Bool(result.editorAutoIndentModel);
    json += L",\"language_scope_model\":" + simplejson::Bool(result.languageScopeModel);
    json += L",\"code_write_plan\":" + simplejson::Bool(result.codeWritePlan);
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
    json += L",\"natural_auto_indent_followed\":" + simplejson::Bool(result.naturalAutoIndentFollowed);
    json += L",\"minimal_indent_correction\":" + simplejson::Bool(result.minimalIndentCorrection);
    json += L",\"smart_completion_model\":" + simplejson::Bool(result.smartCompletionModel);
    json += L",\"smart_completion_adjustment_applied\":" + simplejson::Bool(result.smartCompletionAdjustmentApplied);
    json += L",\"smart_completion_adjusted_line_count\":" + std::to_wstring(result.smartCompletionAdjustedLineCount);
    json += L",\"completion_suppression_applied\":" + simplejson::Bool(result.completionSuppressionApplied);
    json += L",\"completion_suppression_key_count\":" + std::to_wstring(result.completionSuppressionKeyCount);
    json += L",\"content_insertion_order\":" + simplejson::Quote(result.contentInsertionOrder);
    json += L",\"post_input_verified\":" + simplejson::Bool(result.postInputVerified);
    json += L",\"postinput_code_structure_verified\":" + simplejson::Bool(result.codeStructureVerified);
    json += L",\"post_input_code_structure_verified\":" + simplejson::Bool(result.codeStructureVerified);
    json += L",\"code_structure_verified\":" + simplejson::Bool(result.codeStructureVerified);
    json += L",\"clipboard_used\":" + simplejson::Bool(result.clipboardUsed);
    json += L",\"backend_file_write_used\":" + simplejson::Bool(result.backendFileWriteUsed);
    json += L",\"cursor_buffer_state_guard\":" + CursorAndBufferStateGuardResultJson(result.bufferGuard);
    json += L",\"incremental_code_input_verifier\":" + IncrementalCodeInputVerifierResultJson(result.incrementalVerifier);
    json += L",\"real_keyboard_code_input_policy_result\":" + RealKeyboardCodeInputPolicyResultJson(result.realKeyboardPolicy);
    json += L",\"code_write_plan_details\":" + CodeWritePlanResultJson(result.writePlan);
    json += L",\"repair_edit_policy\":" + RepairEditPolicyResultJson(result.repairEditPolicy);
    json += L",\"pre_input_code_structure_verifier\":" + PreInputCodeStructureVerifierResultJson(result.preInputVerification);
    json += L",\"verification\":" + TextInputVerificationResultJson(result.verification);
    json += L",\"line_plans\":[";
    size_t limit = result.linePlans.size() > 80 ? 80 : result.linePlans.size();
    for (size_t i = 0; i < limit; ++i) {
        if (i) json += L",";
        json += IndentationLinePlanJson(result.linePlans[i]);
    }
    json += L"]";
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L"}";
    return json;
}
