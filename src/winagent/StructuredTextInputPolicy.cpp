#include "StructuredTextInputPolicy.h"

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

bool ContainsNewline(const std::wstring& text) {
    return text.find(L'\n') != std::wstring::npos || text.find(L'\r') != std::wstring::npos;
}

std::wstring TypeModeForProfile(const StructuredTextInputOptions& options) {
    return options.typingProfile == L"fast-real-keyboard" ? L"fast-human" : L"fast-human";
}

StructuredTextInputResult Fail(const StructuredTextInputOptions& options, const std::wstring& code, const std::wstring& message, const std::wstring& resolvedKind, const std::wstring& strategy) {
    StructuredTextInputResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.requestedInputKind = options.inputKind;
    result.resolvedInputKind = resolvedKind;
    result.strategy = strategy;
    result.inputMethod = options.inputMethod.empty() ? L"real_keyboard_events" : options.inputMethod;
    result.structured = true;
    result.indentMode = NormalizeIndentMode(options.indentMode);
    result.indentWidth = options.indentWidth <= 0 ? 4 : options.indentWidth;
    result.verifyStructure = options.verifyStructure;
    return result;
}

bool IsSingleLineKind(const std::wstring& kind) {
    return kind == L"single_line_input" || kind == L"form_value" || kind == L"filename_text" || kind == L"command_palette_text";
}

bool IsMultilinePlainKind(const std::wstring& kind) {
    return kind == L"multi_line_plain_text" || kind == L"message_text" || kind == L"email_body";
}

}  // namespace

std::wstring NormalizeInputKind(const std::wstring& inputKind) {
    std::wstring kind = ToLower(inputKind);
    if (kind.empty()) return L"";
    if (kind == L"single" || kind == L"single_line" || kind == L"search" || kind == L"search_box" || kind == L"input") return L"single_line_input";
    if (kind == L"multi" || kind == L"multiline" || kind == L"plain" || kind == L"textarea" || kind == L"multi_line") return L"multi_line_plain_text";
    if (kind == L"message" || kind == L"chat" || kind == L"message_text") return L"message_text";
    if (kind == L"email" || kind == L"mail" || kind == L"email_body") return L"email_body";
    if (kind == L"form" || kind == L"form_value") return L"form_value";
    if (kind == L"code" || kind == L"editor" || kind == L"ide" || kind == L"code_editor" || kind == L"code_editor_text") return L"code_editor_text";
    if (kind == L"filename" || kind == L"file_name" || kind == L"filename_text") return L"filename_text";
    if (kind == L"command" || kind == L"palette" || kind == L"command_palette" || kind == L"command_palette_text") return L"command_palette_text";
    return kind;
}

bool LooksLikeStructuredCode(const std::wstring& text) {
    if (!ContainsNewline(text)) return false;
    std::wstring lower = ToLower(text);
    return lower.find(L"class ") != std::wstring::npos ||
           lower.find(L"def ") != std::wstring::npos ||
           lower.find(L"public class ") != std::wstring::npos ||
           lower.find(L"fun ") != std::wstring::npos ||
           lower.find(L"#include") != std::wstring::npos ||
           lower.find(L"int main(") != std::wstring::npos ||
           lower.find(L"function ") != std::wstring::npos ||
           lower.find(L"{\n") != std::wstring::npos ||
           lower.find(L"[\n") != std::wstring::npos ||
           lower.find(L"</") != std::wstring::npos ||
           lower.find(L"```") != std::wstring::npos;
}

std::wstring InferStructuredInputKind(const std::wstring& text, const std::wstring& requestedKind) {
    std::wstring normalized = NormalizeInputKind(requestedKind);
    if (!normalized.empty()) return normalized;
    if (!ContainsNewline(text)) return L"single_line_input";
    if (LooksLikeStructuredCode(text)) return L"code_editor_text";
    return L"multi_line_plain_text";
}

StructuredTextInputResult ApplyStructuredTextInputPolicy(HWND hwnd, const StructuredTextInputOptions& options) {
    std::wstring resolvedKind = InferStructuredInputKind(options.text, options.inputKind);
    std::wstring method = options.inputMethod.empty() ? L"real_keyboard_events" : options.inputMethod;
    bool fastBatch = options.typingProfile == L"fast-real-keyboard" || options.batchKeyEvents;

    if (IsSingleLineKind(resolvedKind)) {
        if (ContainsNewline(options.text)) {
            return Fail(options, L"FAIL_SINGLE_LINE_INPUT_CONTAINS_NEWLINE", L"single_line_input cannot insert newlines; choose multi_line_plain_text or code_editor_text.", resolvedKind, L"single_line_keyboard_policy");
        }
        StructuredTextInputResult result;
        result.ok = true;
        result.requestedInputKind = options.inputKind;
        result.resolvedInputKind = resolvedKind;
        result.strategy = L"single_line_keyboard_policy";
        result.inputMethod = method;
        result.structured = true;
        result.indentMode = NormalizeIndentMode(options.indentMode);
        result.indentWidth = options.indentWidth <= 0 ? 4 : options.indentWidth;
        result.verifyStructure = options.verifyStructure;
        result.lineInputVerified = true;
        if (!options.dryRun) {
            ActionResult selectAll = SendHotkey(hwnd, L"CTRL+A");
            if (!selectAll.ok) return Fail(options, selectAll.errorCode.empty() ? L"FAIL_SINGLE_LINE_SELECT" : selectAll.errorCode, selectAll.error.empty() ? L"Could not select existing single-line input." : selectAll.error, resolvedKind, result.strategy);
            ActionResult clear = PressKey(hwnd, L"BACKSPACE");
            if (!clear.ok) return Fail(options, clear.errorCode.empty() ? L"FAIL_SINGLE_LINE_CLEAR" : clear.errorCode, clear.error.empty() ? L"Could not clear existing single-line input." : clear.error, resolvedKind, result.strategy);
            result.typeResult = TypeText(hwnd, options.text, TypeModeForProfile(options), options.charDelayMs);
            if (!result.typeResult.ok) return Fail(options, result.typeResult.errorCode.empty() ? L"FAIL_SINGLE_LINE_TYPE" : result.typeResult.errorCode, result.typeResult.error.empty() ? L"Could not type single-line input." : result.typeResult.error, resolvedKind, result.strategy);
            if (options.submitEnter) {
                ActionResult enter = PressKey(hwnd, L"ENTER");
                if (!enter.ok) return Fail(options, enter.errorCode.empty() ? L"FAIL_SINGLE_LINE_ENTER" : enter.errorCode, enter.error.empty() ? L"Could not submit single-line input." : enter.error, resolvedKind, result.strategy);
            }
        } else {
            result.typeResult.ok = true;
            result.typeResult.textLength = static_cast<int>(options.text.size());
            result.typeResult.keyboardSendBatchCount = 1;
        }
        return result;
    }

    if (resolvedKind == L"code_editor_text") {
        CodeEditorTypingOptions code;
        code.text = options.text;
        code.indentMode = options.indentMode;
        code.indentWidth = options.indentWidth;
        code.verifyStructure = options.verifyStructure;
        code.dryRun = options.dryRun;
        code.charDelayMs = options.charDelayMs;
        code.lineDelayMs = options.lineDelayMs;
        code.batchKeyEvents = fastBatch;
        code.typingProfile = options.typingProfile.empty() ? L"fast-real-keyboard" : options.typingProfile;
        code.runSucceededForVerifier = options.verifierRunSucceeded;
        CodeEditorTypingResult codeResult = ApplyCodeEditorTypingPolicy(hwnd, code);
        StructuredTextInputResult result;
        result.ok = codeResult.ok;
        result.errorCode = codeResult.errorCode;
        result.errorMessage = codeResult.errorMessage;
        result.requestedInputKind = options.inputKind;
        result.resolvedInputKind = resolvedKind;
        result.strategy = codeResult.strategy;
        result.inputMethod = method;
        result.structured = true;
        result.indentMode = codeResult.indentMode;
        result.indentWidth = codeResult.indentWidth;
        result.verifyStructure = options.verifyStructure;
        result.codeStructureVerified = codeResult.codeStructureVerified;
        result.codeWritePlanUsed = codeResult.codeWritePlanUsed;
        result.languageScopeModelUsed = codeResult.languageScopeModelUsed;
        result.preInputCodeStructureVerifierUsed = codeResult.preInputCodeStructureVerifierUsed;
        result.preInputCodeStructureVerified = codeResult.preInputCodeStructureVerified;
        result.editorAutoIndentModelUsed = codeResult.editorAutoIndentModelUsed;
        result.cursorBufferStateVerified = codeResult.cursorBufferStateVerified;
        result.oldBufferClearedOrSafeReplaceVerified = codeResult.oldBufferClearedOrSafeReplaceVerified;
        result.noRetryContamination = codeResult.noRetryContamination;
        result.incrementalCodeInputVerifierUsed = codeResult.incrementalCodeInputVerifierUsed;
        result.realKeyboardCodeInputPolicy = codeResult.realKeyboardCodeInputPolicy;
        result.receiverBindingVerified = codeResult.receiverBindingVerified;
        result.duplicateReceiverTokenDetected = codeResult.duplicateReceiverTokenDetected;
        result.repairReplaceNotAppend = codeResult.repairReplaceNotAppend;
        result.selfselfPresent = codeResult.selfselfPresent;
        result.autoIndentDetected = codeResult.autoIndentDetected;
        result.autoIndentCorrectionApplied = codeResult.autoIndentCorrectionApplied;
        result.targetIndentSpacesMax = codeResult.targetIndentSpacesMax;
        result.actualIndentCorrectionKeys = codeResult.actualIndentCorrectionKeys;
        result.lineInputVerified = codeResult.postInputVerified;
        result.codeEditorResult = codeResult;
        result.typeResult = codeResult.typeResult;
        result.typeResult.ok = codeResult.ok;
        result.typeResult.keyboardSendBatchCount = codeResult.keyboardSendBatchCount;
        return result;
    }

    if (IsMultilinePlainKind(resolvedKind)) {
        StructuredTextInputResult result;
        result.ok = true;
        result.requestedInputKind = options.inputKind;
        result.resolvedInputKind = resolvedKind;
        result.strategy = resolvedKind == L"message_text" ? L"message_text_keyboard_policy" : L"multi_line_plain_text_keyboard_policy";
        result.inputMethod = method;
        result.structured = true;
        result.indentMode = NormalizeIndentMode(options.indentMode);
        result.indentWidth = options.indentWidth <= 0 ? 4 : options.indentWidth;
        result.verifyStructure = options.verifyStructure;
        result.lineInputVerified = true;
        if (!options.dryRun) {
            result.typeResult = fastBatch
                ? TypeTextStructured(hwnd, options.text, TypeModeForProfile(options), options.charDelayMs, options.lineDelayMs, true)
                : TypeText(hwnd, options.text, TypeModeForProfile(options), options.charDelayMs);
            if (!result.typeResult.ok) return Fail(options, result.typeResult.errorCode.empty() ? L"FAIL_MULTILINE_TYPE" : result.typeResult.errorCode, result.typeResult.error.empty() ? L"Could not type multiline text." : result.typeResult.error, resolvedKind, result.strategy);
        } else {
            result.typeResult.ok = true;
            result.typeResult.textLength = static_cast<int>(options.text.size());
            result.typeResult.batchKeyEvents = fastBatch;
            result.typeResult.keyboardSendBatchCount = fastBatch ? 1 : 0;
        }
        return result;
    }

    return Fail(options, L"INVALID_INPUT_KIND", L"Unsupported --input-kind for structured visible text input.", resolvedKind, L"structured_text_input_policy");
}

std::wstring StructuredTextInputResultJson(const StructuredTextInputResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"requested_input_kind\":" + simplejson::Quote(result.requestedInputKind);
    json += L",\"resolved_input_kind\":" + simplejson::Quote(result.resolvedInputKind);
    json += L",\"strategy\":" + simplejson::Quote(result.strategy);
    json += L",\"input_method\":" + simplejson::Quote(result.inputMethod);
    json += L",\"structured\":" + simplejson::Bool(result.structured);
    json += L",\"indent_mode\":" + simplejson::Quote(result.indentMode);
    json += L",\"indent_width\":" + std::to_wstring(result.indentWidth);
    json += L",\"verify_structure\":" + simplejson::Bool(result.verifyStructure);
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
    json += L",\"auto_indent_detected\":" + simplejson::Bool(result.autoIndentDetected);
    json += L",\"auto_indent_correction_applied\":" + simplejson::Bool(result.autoIndentCorrectionApplied);
    json += L",\"target_indent_spaces_max\":" + std::to_wstring(result.targetIndentSpacesMax);
    json += L",\"actual_indent_correction_keys\":" + std::to_wstring(result.actualIndentCorrectionKeys);
    json += L",\"line_input_verified\":" + simplejson::Bool(result.lineInputVerified);
    json += L",\"clipboard_used\":" + simplejson::Bool(result.clipboardUsed);
    json += L",\"backend_file_write_used\":" + simplejson::Bool(result.backendFileWriteUsed);
    if (result.resolvedInputKind == L"code_editor_text") {
        json += L",\"code_editor\":" + CodeEditorTypingResultJson(result.codeEditorResult);
    }
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L"}";
    return json;
}
