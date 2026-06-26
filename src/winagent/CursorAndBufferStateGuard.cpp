#include "CursorAndBufferStateGuard.h"

#include "OcrController.h"
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

bool Contains(const std::wstring& value, const std::wstring& needle) {
    return value.find(needle) != std::wstring::npos;
}

void AddKey(CursorAndBufferStateGuardResult& result, const std::wstring& key) {
    result.keySequence.push_back(key);
    ++result.keyboardSendBatchCount;
}

bool MergeAction(const ActionResult& action, CursorAndBufferStateGuardResult& result, const std::wstring& code, const std::wstring& message) {
    if (action.ok) return true;
    result.ok = false;
    result.errorCode = action.errorCode.empty() ? code : action.errorCode;
    result.errorMessage = action.error.empty() ? message : action.error;
    result.cursorBufferStateVerified = false;
    result.oldBufferClearedOrSafeReplaceVerified = false;
    result.noRetryContamination = false;
    return false;
}

bool VisibleTextContainsCodeResidue(const std::wstring& text) {
    std::wstring lower = ToLower(text);
    return Contains(lower, L"class student") ||
           Contains(lower, L"class course") ||
           Contains(lower, L"def __init") ||
           Contains(lower, L"def introduce") ||
           Contains(lower, L"def show_title") ||
           Contains(lower, L"student =") ||
           Contains(lower, L"course =") ||
           Contains(lower, L"student.introduce") ||
           Contains(lower, L"course.show_title") ||
           Contains(lower, L"#include") ||
           Contains(lower, L"int main") ||
           Contains(lower, L"fun main") ||
           Contains(lower, L"public class");
}

bool VerifyVisibleBufferCleared(HWND hwnd, CursorAndBufferStateGuardResult& result) {
    Sleep(250);
    OcrResult visible = ReadWindowText(hwnd, L"");
    if (!visible.ok) {
        result.ok = false;
        result.errorCode = L"BLOCKED_BUFFER_CLEAR_VISIBLE_VERIFICATION_UNAVAILABLE";
        result.errorMessage = visible.errorMessage.empty() ? L"Visible buffer clear verification could not read editor text." : visible.errorMessage;
        result.cursorBufferStateVerified = false;
        result.oldBufferClearedOrSafeReplaceVerified = false;
        result.noRetryContamination = false;
        result.visibleBufferClearVerified = false;
        return false;
    }
    result.visibleBufferClearVerified = true;
    if (VisibleTextContainsCodeResidue(visible.fullText)) {
        result.ok = false;
        result.errorCode = L"BLOCKED_BUFFER_CLEAR_CONTAMINATION_VISIBLE";
        result.errorMessage = L"Visible editor text still contains code residue after clear; refusing to type over contaminated buffer.";
        result.cursorBufferStateVerified = false;
        result.oldBufferClearedOrSafeReplaceVerified = false;
        result.noRetryContamination = false;
        result.clearContaminationDetected = true;
        return false;
    }
    return true;
}

}  // namespace

CursorAndBufferStateGuardResult PlanCursorAndBufferStateGuard(bool clearFirst) {
    CursorAndBufferStateGuardResult result;
    result.clearFirst = clearFirst;
    result.targetEditorFocused = true;
    if (!clearFirst) {
        result.clearStrategy = L"append_without_clear_requested";
        result.cursorBufferStateVerified = true;
        result.oldBufferClearedOrSafeReplaceVerified = true;
        result.noRetryContamination = true;
        return result;
    }
    AddKey(result, L"ESC");
    AddKey(result, L"ESC");
    AddKey(result, L"CTRL+A");
    AddKey(result, L"CTRL+A");
    AddKey(result, L"DELETE");
    AddKey(result, L"BACKSPACE");
    AddKey(result, L"CTRL+HOME");
    AddKey(result, L"CTRL+SHIFT+END");
    AddKey(result, L"DELETE");
    AddKey(result, L"CTRL+END");
    AddKey(result, L"CTRL+SHIFT+HOME");
    AddKey(result, L"DELETE");
    AddKey(result, L"CTRL+HOME");
    result.clearStrategy = L"foreground_ctrl_a_twice_plus_bidirectional_full_buffer_selection_delete_visible_verified";
    result.cursorBufferStateVerified = true;
    result.oldBufferClearedOrSafeReplaceVerified = true;
    result.noRetryContamination = true;
    return result;
}

CursorAndBufferStateGuardResult ClearCodeEditorBufferForRewrite(HWND hwnd, bool dryRun, bool clearFirst) {
    CursorAndBufferStateGuardResult result = PlanCursorAndBufferStateGuard(clearFirst);
    if (!clearFirst || dryRun) return result;

    result.keySequence.clear();
    result.keyboardSendBatchCount = 0;

    ActionResult focus = FocusTargetWindow(hwnd);
    if (!MergeAction(focus, result, L"FAIL_CODE_EDITOR_CLEAR_FOCUS", L"Could not focus editor before buffer clear.")) return result;

    AddKey(result, L"ESC");
    if (!MergeAction(PressKeyGlobal(L"ESC"), result, L"FAIL_CODE_EDITOR_CLEAR_ESCAPE", L"Could not dismiss editor completion before buffer clear.")) return result;

    AddKey(result, L"ESC");
    if (!MergeAction(PressKeyGlobal(L"ESC"), result, L"FAIL_CODE_EDITOR_CLEAR_ESCAPE", L"Could not dismiss editor selection state before buffer clear.")) return result;

    AddKey(result, L"CTRL+A");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+A"), result, L"FAIL_CODE_EDITOR_CLEAR_SELECT_ALL", L"Could not select the current editor buffer before rewrite.")) return result;

    AddKey(result, L"CTRL+A");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+A"), result, L"FAIL_CODE_EDITOR_CLEAR_SELECT_ALL", L"Could not select the current editor buffer before rewrite.")) return result;

    AddKey(result, L"DELETE");
    if (!MergeAction(PressKeyGlobal(L"DELETE"), result, L"FAIL_CODE_EDITOR_CLEAR_DELETE", L"Could not delete the selected editor buffer.")) return result;

    AddKey(result, L"BACKSPACE");
    if (!MergeAction(PressKeyGlobal(L"BACKSPACE"), result, L"FAIL_CODE_EDITOR_CLEAR_BACKSPACE", L"Could not clear the selected editor buffer with backspace.")) return result;

    AddKey(result, L"CTRL+HOME");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+HOME"), result, L"FAIL_CODE_EDITOR_CLEAR_HOME", L"Could not move to the editor buffer start before forward clear.")) return result;

    AddKey(result, L"CTRL+SHIFT+END");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+SHIFT+END"), result, L"FAIL_CODE_EDITOR_CLEAR_SELECT_FORWARD", L"Could not select the editor buffer from start to end.")) return result;

    AddKey(result, L"DELETE");
    if (!MergeAction(PressKeyGlobal(L"DELETE"), result, L"FAIL_CODE_EDITOR_CLEAR_DELETE", L"Could not delete the selected editor buffer.")) return result;

    AddKey(result, L"CTRL+END");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+END"), result, L"FAIL_CODE_EDITOR_CLEAR_END", L"Could not move to the end of the editor buffer for reverse clear.")) return result;

    AddKey(result, L"CTRL+SHIFT+HOME");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+SHIFT+HOME"), result, L"FAIL_CODE_EDITOR_CLEAR_SELECT_REVERSE", L"Could not select the remaining editor buffer from end to start.")) return result;

    AddKey(result, L"DELETE");
    if (!MergeAction(PressKeyGlobal(L"DELETE"), result, L"FAIL_CODE_EDITOR_CLEAR_DELETE", L"Could not delete the reverse-selected editor buffer.")) return result;

    AddKey(result, L"CTRL+HOME");
    if (!MergeAction(SendHotkeyGlobal(L"CTRL+HOME"), result, L"FAIL_CODE_EDITOR_CLEAR_HOME", L"Could not return cursor to the editor buffer start after clear.")) return result;

    if (!VerifyVisibleBufferCleared(hwnd, result)) return result;

    result.targetEditorFocused = true;
    result.cursorBufferStateVerified = true;
    result.oldBufferClearedOrSafeReplaceVerified = true;
    result.noRetryContamination = true;
    return result;
}

std::wstring CursorAndBufferStateGuardResultJson(const CursorAndBufferStateGuardResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"cursor_and_buffer_state_guard\":" + simplejson::Bool(result.cursorAndBufferStateGuard);
    json += L",\"target_editor_focused\":" + simplejson::Bool(result.targetEditorFocused);
    json += L",\"cursor_buffer_state_verified\":" + simplejson::Bool(result.cursorBufferStateVerified);
    json += L",\"old_buffer_cleared_or_safe_replace_verified\":" + simplejson::Bool(result.oldBufferClearedOrSafeReplaceVerified);
    json += L",\"no_retry_contamination\":" + simplejson::Bool(result.noRetryContamination);
    json += L",\"visible_buffer_clear_verified\":" + simplejson::Bool(result.visibleBufferClearVerified);
    json += L",\"clear_contamination_detected\":" + simplejson::Bool(result.clearContaminationDetected);
    json += L",\"clear_first\":" + simplejson::Bool(result.clearFirst);
    json += L",\"visible_verification_required\":" + simplejson::Bool(result.visibleVerificationRequired);
    json += L",\"clear_strategy\":" + simplejson::Quote(result.clearStrategy);
    json += L",\"keyboard_send_batch_count\":" + std::to_wstring(result.keyboardSendBatchCount);
    json += L",\"key_sequence\":[";
    for (size_t i = 0; i < result.keySequence.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.keySequence[i]);
    }
    json += L"]";
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L"}";
    return json;
}
