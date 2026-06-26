#include "RealKeyboardCodeInputPolicy.h"

#include "SimpleJson.h"

namespace {

void AddFinding(RealKeyboardCodeInputPolicyResult& result, const std::wstring& finding, const std::wstring& code = L"REAL_KEYBOARD_CODE_INPUT_POLICY_FAILED") {
    result.ok = false;
    result.findings.push_back(finding);
    if (result.errorCode.empty()) {
        result.errorCode = code;
        result.errorMessage = finding;
    }
}

}  // namespace

RealKeyboardCodeInputPolicyResult EvaluateRealKeyboardCodeInputPolicy(
    const CodeWritePlanResult& writePlan,
    const CursorAndBufferStateGuardResult& bufferGuard,
    const IncrementalCodeInputVerifierResult& incrementalVerifier,
    bool clipboardUsed,
    bool backendFileWriteUsed) {
    RealKeyboardCodeInputPolicyResult result;
    result.codeWritePlanUsed = writePlan.codeWritePlan;
    result.languageScopeModelUsed = writePlan.languageScope.languageScopeModel;
    result.editorAutoIndentModelUsed = writePlan.editorAutoIndent.editorAutoIndentModel;
    result.cursorBufferStateVerified = bufferGuard.cursorBufferStateVerified;
    result.oldBufferClearedOrSafeReplaceVerified = bufferGuard.oldBufferClearedOrSafeReplaceVerified;
    result.incrementalCodeInputVerifierUsed = incrementalVerifier.incrementalCodeInputVerifier;
    result.clipboardUsed = clipboardUsed;
    result.backendFileWriteUsed = backendFileWriteUsed;

    if (clipboardUsed) {
        AddFinding(result, L"Clipboard cannot be used for structured real-keyboard code input.", L"BLOCKED_CLIPBOARD_USED_FOR_CODE_INPUT");
    }
    if (backendFileWriteUsed) {
        AddFinding(result, L"Backend file write cannot be used for structured visible code input.", L"BLOCKED_BACKEND_FILE_WRITE_USED_FOR_CODE_INPUT");
    }
    if (!writePlan.ok || !writePlan.codeWritePlan) {
        AddFinding(result, L"CodeWritePlan did not approve the code structure.");
    }
    if (!writePlan.languageScope.ok || !writePlan.languageScope.languageScopeModel) {
        AddFinding(result, L"LanguageScopeModel did not approve the code scope structure.");
    }
    if (!writePlan.editorAutoIndent.ok || !writePlan.editorAutoIndent.editorAutoIndentModel) {
        AddFinding(result, L"EditorAutoIndentModel did not produce a safe typing plan.");
    }
    if (!bufferGuard.ok || !bufferGuard.cursorBufferStateVerified || !bufferGuard.oldBufferClearedOrSafeReplaceVerified) {
        AddFinding(result, L"CursorAndBufferStateGuard did not verify a clean rewrite state.");
    }
    if (!incrementalVerifier.ok) {
        for (const auto& finding : incrementalVerifier.findings) {
            AddFinding(result, finding);
        }
    }
    return result;
}

std::wstring RealKeyboardCodeInputPolicyResultJson(const RealKeyboardCodeInputPolicyResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"real_keyboard_code_input_policy\":" + simplejson::Bool(result.realKeyboardCodeInputPolicy);
    json += L",\"input_method\":" + simplejson::Quote(result.inputMethod);
    json += L",\"code_write_plan_used\":" + simplejson::Bool(result.codeWritePlanUsed);
    json += L",\"language_scope_model_used\":" + simplejson::Bool(result.languageScopeModelUsed);
    json += L",\"editor_auto_indent_model_used\":" + simplejson::Bool(result.editorAutoIndentModelUsed);
    json += L",\"cursor_buffer_state_verified\":" + simplejson::Bool(result.cursorBufferStateVerified);
    json += L",\"old_buffer_cleared_or_safe_replace_verified\":" + simplejson::Bool(result.oldBufferClearedOrSafeReplaceVerified);
    json += L",\"incremental_code_input_verifier_used\":" + simplejson::Bool(result.incrementalCodeInputVerifierUsed);
    json += L",\"clipboard_used\":" + simplejson::Bool(result.clipboardUsed);
    json += L",\"backend_file_write_used\":" + simplejson::Bool(result.backendFileWriteUsed);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"findings\":[";
    for (size_t i = 0; i < result.findings.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.findings[i]);
    }
    json += L"]}";
    return json;
}
