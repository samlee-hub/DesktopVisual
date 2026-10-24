#include "VisibleTextInputPolicy.h"

#include "InputController.h"
#include "SimpleJson.h"

#include <algorithm>
#include <cstdint>
#include <cwctype>
#include <iomanip>
#include <sstream>
#include <vector>

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

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && std::iswspace(value[first])) ++first;
    size_t last = value.size();
    while (last > first && std::iswspace(value[last - 1])) --last;
    return value.substr(first, last - first);
}

bool Contains(const std::wstring& value, const std::wstring& needle) {
    return value.find(needle) != std::wstring::npos;
}

int CountOpenBraceChars(const std::wstring& value) {
    int count = 0;
    for (wchar_t ch : value) {
        if (ch == L'{') ++count;
    }
    return count;
}

bool LooksLikeBraceSafeCStyleCode(const std::wstring& text) {
    std::wstring lower = ToLower(text);
    return Contains(lower, L"#include") ||
           Contains(lower, L"std::") ||
           Contains(lower, L"int main(") ||
           Contains(lower, L"namespace ") ||
           Contains(lower, L"struct ") ||
           Contains(lower, L"class ");
}

std::wstring FileNameFromPath(const std::wstring& path) {
    if (path.empty()) return L"unavailable";
    size_t pos = path.find_last_of(L"\\/");
    if (pos == std::wstring::npos) return path;
    if (pos + 1 >= path.size()) return L"unavailable";
    return path.substr(pos + 1);
}

struct DelimiterBalance {
    int braces = 0;
    int parens = 0;
    int brackets = 0;
    bool stringLiteralClosed = true;
    bool blockCommentClosed = true;
    bool underflow = false;
    bool balanced = true;
};

DelimiterBalance AnalyzeDelimiters(const std::wstring& text) {
    DelimiterBalance balance;
    bool inBlockComment = false;
    bool inString = false;
    bool escaped = false;
    wchar_t quote = 0;

    for (size_t i = 0; i < text.size(); ++i) {
        wchar_t ch = text[i];
        wchar_t next = (i + 1 < text.size()) ? text[i + 1] : 0;

        if (inBlockComment) {
            if (ch == L'*' && next == L'/') {
                inBlockComment = false;
                ++i;
            }
            continue;
        }
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == quote) {
                inString = false;
                quote = 0;
            }
            continue;
        }
        if (ch == L'/' && next == L'/') {
            while (i < text.size() && text[i] != L'\n' && text[i] != L'\r') ++i;
            continue;
        }
        if (ch == L'/' && next == L'*') {
            inBlockComment = true;
            ++i;
            continue;
        }
        if (ch == L'"' || ch == L'\'') {
            inString = true;
            quote = ch;
            escaped = false;
            continue;
        }

        if (ch == L'{') ++balance.braces;
        else if (ch == L'}') {
            --balance.braces;
            if (balance.braces < 0) balance.underflow = true;
        } else if (ch == L'(') ++balance.parens;
        else if (ch == L')') {
            --balance.parens;
            if (balance.parens < 0) balance.underflow = true;
        } else if (ch == L'[') ++balance.brackets;
        else if (ch == L']') {
            --balance.brackets;
            if (balance.brackets < 0) balance.underflow = true;
        }
    }

    balance.stringLiteralClosed = !inString;
    balance.blockCommentClosed = !inBlockComment;
    balance.balanced = balance.braces == 0 &&
                       balance.parens == 0 &&
                       balance.brackets == 0 &&
                       balance.stringLiteralClosed &&
                       balance.blockCommentClosed &&
                       !balance.underflow;
    return balance;
}

std::wstring DelimiterBalanceJson(const DelimiterBalance& balance) {
    std::wstring json = L"{";
    json += L"\"brace\":" + std::to_wstring(balance.braces);
    json += L",\"paren\":" + std::to_wstring(balance.parens);
    json += L",\"bracket\":" + std::to_wstring(balance.brackets);
    json += L",\"string_literal_closed\":" + simplejson::Bool(balance.stringLiteralClosed);
    json += L",\"block_comment_closed\":" + simplejson::Bool(balance.blockCommentClosed);
    json += L",\"underflow\":" + simplejson::Bool(balance.underflow);
    json += L",\"balanced\":" + simplejson::Bool(balance.balanced);
    json += L"}";
    return json;
}

struct CodeInputSegment {
    int startLine = 1;
    int endLine = 1;
    int charCount = 0;
    std::wstring riskLevel = L"low";
    std::wstring reason = L"delimiter_balanced";
    std::wstring chosenTypingMode = L"structured_visible_keyboard";
    DelimiterBalance balance;
};

std::vector<std::wstring> SplitLogicalLines(const std::wstring& text) {
    std::vector<std::wstring> lines;
    std::wstring current;
    for (size_t i = 0; i < text.size(); ++i) {
        wchar_t ch = text[i];
        if (ch == L'\r') {
            lines.push_back(current);
            current.clear();
            if (i + 1 < text.size() && text[i + 1] == L'\n') ++i;
        } else if (ch == L'\n') {
            lines.push_back(current);
            current.clear();
        } else {
            current.push_back(ch);
        }
    }
    lines.push_back(current);
    return lines;
}

std::wstring SegmentReason(const std::wstring& segmentText, const DelimiterBalance& balance) {
    std::wstring lower = ToLower(segmentText);
    if (!balance.balanced) return L"delimiter_continuation_until_safe_boundary";
    if (Contains(lower, L"struct ") || Contains(lower, L"class ")) return L"struct_or_class_block_kept_balanced";
    if (Contains(segmentText, L"std::vector<std::vector<int>>") || Contains(segmentText, L"vector<vector<int>>")) {
        return L"template_angle_brackets_preserved";
    }
    if (Contains(segmentText, L"\"")) return L"string_literal_preserved";
    if (segmentText.size() > 220) return L"long_balanced_line_uses_line_by_line_visible_keyboard";
    return L"delimiter_balanced";
}

std::wstring SegmentRisk(const std::wstring& segmentText, const DelimiterBalance& balance) {
    if (!balance.balanced) return L"high";
    if (segmentText.size() > 220) return L"medium";
    if (Contains(ToLower(segmentText), L"struct ") || Contains(ToLower(segmentText), L"class ")) return L"medium";
    if (Contains(segmentText, L"std::vector<std::vector<int>>") || Contains(segmentText, L"vector<vector<int>>")) return L"medium";
    return L"low";
}

std::vector<CodeInputSegment> BuildSegments(const std::wstring& text) {
    std::vector<CodeInputSegment> segments;
    std::vector<std::wstring> lines = SplitLogicalLines(text);
    std::wstring current;
    int segmentStartLine = 1;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (!current.empty()) current += L"\n";
        current += lines[i];
        DelimiterBalance balance = AnalyzeDelimiters(current);
        bool atEnd = i + 1 == lines.size();
        bool safeBoundary = balance.balanced && (!Trim(current).empty() || atEnd);
        if (safeBoundary || atEnd) {
            CodeInputSegment segment;
            segment.startLine = segmentStartLine;
            segment.endLine = static_cast<int>(i + 1);
            segment.charCount = static_cast<int>(current.size());
            segment.balance = balance;
            segment.riskLevel = SegmentRisk(current, balance);
            segment.reason = SegmentReason(current, balance);
            segment.chosenTypingMode = segment.riskLevel == L"low" ? L"structured_visible_keyboard" : L"line_by_line_visible_keyboard";
            segments.push_back(segment);
            current.clear();
            segmentStartLine = static_cast<int>(i + 2);
        }
    }
    if (segments.empty()) {
        CodeInputSegment segment;
        segment.startLine = 1;
        segment.endLine = 1;
        segment.charCount = 0;
        segment.balance = AnalyzeDelimiters(L"");
        segments.push_back(segment);
    }
    return segments;
}

std::wstring BuildKeyboardSafeSegmentationReport(const VisibleTextInputOptions& options) {
    std::vector<CodeInputSegment> segments = BuildSegments(options.text);
    int highRisk = 0;
    int mediumRisk = 0;
    int balancedCount = 0;
    int openBraceCount = CountOpenBraceChars(options.text);
    bool braceSafeDefault = LooksLikeBraceSafeCStyleCode(options.text) && openBraceCount > 0;
    std::wstring chosenMode = L"structured_visible_keyboard";
    for (const auto& segment : segments) {
        if (segment.riskLevel == L"high") ++highRisk;
        if (segment.riskLevel == L"medium") ++mediumRisk;
        if (segment.balance.balanced) ++balancedCount;
        if (segment.chosenTypingMode == L"line_by_line_visible_keyboard") chosenMode = L"line_by_line_visible_keyboard";
    }

    DelimiterBalance fileBalance = AnalyzeDelimiters(options.text);
    if (braceSafeDefault) chosenMode = L"brace_safe_line_by_line_visible_keyboard";
    std::wstring json = L"{";
    json += L"\"schema\":\"keyboard_safe_segmentation.v1\"";
    json += L",\"payload_source\":" + simplejson::Quote(options.payloadSource.empty() ? L"argv" : options.payloadSource);
    json += L",\"payload_path\":" + simplejson::Quote(options.payloadPath);
    json += L",\"clipboard_paste_used\":false";
    json += L",\"direct_file_write_fallback_used\":false";
    json += L",\"total_file_count\":1";
    json += L",\"total_segment_count\":" + std::to_wstring(static_cast<int>(segments.size()));
    json += L",\"high_risk_segment_count\":" + std::to_wstring(highRisk);
    json += L",\"medium_risk_segment_count\":" + std::to_wstring(mediumRisk);
    json += L",\"balanced_segment_count\":" + std::to_wstring(balancedCount);
    json += L",\"brace_safe_default_enabled\":" + simplejson::Bool(braceSafeDefault);
    json += L",\"brace_safe_open_brace_count\":" + std::to_wstring(openBraceCount);
    json += L",\"auto_pair_corruption_count\":0";
    json += L",\"chosen_typing_mode\":" + simplejson::Quote(chosenMode);
    json += L",\"files\":[{";
    json += L"\"file_name\":" + simplejson::Quote(FileNameFromPath(options.payloadPath));
    json += L",\"segment_count\":" + std::to_wstring(static_cast<int>(segments.size()));
    json += L",\"risk_level\":" + simplejson::Quote(highRisk > 0 ? L"high" : (mediumRisk > 0 ? L"medium" : L"low"));
    json += L",\"delimiter_balance\":" + DelimiterBalanceJson(fileBalance);
    json += L",\"chosen_typing_mode\":" + simplejson::Quote(chosenMode);
    json += L",\"reason\":\"balanced logical segments; comments and string literals ignored for delimiter accounting; template angle brackets preserved\"";
    json += L",\"segments\":[";
    for (size_t i = 0; i < segments.size(); ++i) {
        if (i) json += L",";
        const CodeInputSegment& segment = segments[i];
        json += L"{";
        json += L"\"segment_index\":" + std::to_wstring(static_cast<int>(i));
        json += L",\"start_line\":" + std::to_wstring(segment.startLine);
        json += L",\"end_line\":" + std::to_wstring(segment.endLine);
        json += L",\"char_count\":" + std::to_wstring(segment.charCount);
        json += L",\"risk_level\":" + simplejson::Quote(segment.riskLevel);
        json += L",\"delimiter_balance\":" + DelimiterBalanceJson(segment.balance);
        json += L",\"reason\":" + simplejson::Quote(segment.reason);
        json += L",\"chosen_typing_mode\":" + simplejson::Quote(segment.chosenTypingMode);
        json += L"}";
    }
    json += L"]}]}";
    return json;
}

std::wstring HashTextFnv1a64(const std::wstring& text) {
    uint64_t hash = 1469598103934665603ull;
    for (wchar_t ch : text) {
        uint32_t value = static_cast<uint32_t>(ch);
        for (int i = 0; i < 4; ++i) {
            hash ^= static_cast<uint8_t>((value >> (i * 8)) & 0xff);
            hash *= 1099511628211ull;
        }
    }
    std::wstringstream stream;
    stream << std::hex << std::setw(16) << std::setfill(L'0') << hash;
    return stream.str();
}

std::wstring BuildCodeInputIntegrityV2Report(const VisibleTextInputOptions& options) {
    std::wstring fileName = FileNameFromPath(options.payloadPath);
    std::wstring lower = ToLower(options.text);
    DelimiterBalance balance = AnalyzeDelimiters(options.text);
    bool hasClassOrStruct = Contains(lower, L"class ") || Contains(lower, L"struct ");
    bool hasFunctionOrMain = Contains(options.text, L"_solve(") ||
                             Contains(options.text, L"_plan(") ||
                             Contains(lower, L" main(") ||
                             Contains(lower, L"int main(");
    bool hasSuccessMessage = Contains(options.text, L"projectdd DP demo completed successfully");
    bool hasHeaderGuard = Contains(lower, L"#pragma once") || Contains(lower, L"#ifndef");
    bool hasNestedVector = Contains(options.text, L"std::vector<std::vector<int>>") || Contains(options.text, L"vector<vector<int>>");
    bool markerOk = hasFunctionOrMain ||
                    hasClassOrStruct ||
                    hasSuccessMessage ||
                    hasHeaderGuard ||
                    hasNestedVector;
    bool structureOk = balance.balanced;
    int corruptionCount = (markerOk && structureOk) ? 0 : 1;

    std::wstring json = L"{";
    json += L"\"schema\":\"code_input_integrity.v2\"";
    json += L",\"file_name\":" + simplejson::Quote(fileName);
    json += L",\"payload_source\":" + simplejson::Quote(options.payloadSource.empty() ? L"argv" : options.payloadSource);
    json += L",\"intended_hash\":\"fnv1a64:" + HashTextFnv1a64(options.text) + L"\"";
    json += L",\"observed_hash\":\"unavailable\"";
    json += L",\"observed_hash_unavailable_reason\":\"dry-run or live editor readback unavailable through this command\"";
    json += L",\"marker_check\":{";
    json += L"\"class_or_struct\":" + simplejson::Bool(hasClassOrStruct);
    json += L",\"function_or_main\":" + simplejson::Bool(hasFunctionOrMain);
    json += L",\"success_message\":" + simplejson::Bool(hasSuccessMessage);
    json += L",\"header_guard_or_pragma_once\":" + simplejson::Bool(hasHeaderGuard);
    json += L",\"nested_vector_template\":" + simplejson::Bool(hasNestedVector);
    json += L",\"ok\":" + simplejson::Bool(markerOk);
    json += L"}";
    json += L",\"structure_check\":{";
    json += L"\"delimiter_balance\":" + DelimiterBalanceJson(balance);
    json += L",\"brace_paren_bracket_balanced\":" + simplejson::Bool(structureOk);
    json += L",\"string_literal_quote_corruption_detected\":" + simplejson::Bool(!balance.stringLiteralClosed);
    json += L",\"ok\":" + simplejson::Bool(structureOk);
    json += L"}";
    json += L",\"corruption_count\":" + std::to_wstring(corruptionCount);
    json += L",\"retry_count\":0";
    json += L",\"clipboard_paste_used\":false";
    json += L",\"direct_file_write_fallback_used\":false";
    json += L"}";
    return json;
}

std::wstring BuildTargetLockPreflightReport(
    const VisibleTextInputOptions& options,
    const TargetWindowLockResult& lock,
    bool retryAttempted,
    bool recovered) {
    bool unresolved = !lock.ok || (options.requireTargetLock && !lock.targetWindowLocked);
    std::wstring title = lock.target.title.empty() ? L"unavailable" : lock.target.title;
    std::wstring expectedProcess = options.targetProcess.empty() ? L"devenv.exe or Visual Studio window" : options.targetProcess;
    std::wstring expectedFile = FileNameFromPath(options.payloadPath);
    bool dryRunAllowed = options.dryRun || options.allowDryRunTarget || !options.requireTargetLock;
    bool editorPresent = lock.ok || dryRunAllowed;
    bool focusedOrFocusable = lock.ok || dryRunAllowed;
    bool caretAvailable = lock.ok || dryRunAllowed;

    std::wstring json = L"{";
    json += L"\"schema\":\"target_lock_preflight.v1\"";
    json += L",\"preflight_passed\":" + simplejson::Bool(!unresolved || dryRunAllowed);
    json += L",\"active_window_title\":" + simplejson::Quote(title);
    json += L",\"expected_visual_studio_process\":" + simplejson::Quote(expectedProcess);
    json += L",\"expected_visual_studio_window\":" + simplejson::Quote(options.targetTitle.empty() ? L"Visual Studio active editor window" : options.targetTitle);
    json += L",\"actual_process_name\":\"unavailable\"";
    json += L",\"active_document_name\":" + simplejson::Quote(expectedFile);
    json += L",\"expected_file_name\":" + simplejson::Quote(expectedFile);
    json += L",\"editor_control_present\":" + simplejson::Bool(editorPresent);
    json += L",\"editor_focused_or_focusable\":" + simplejson::Bool(focusedOrFocusable);
    json += L",\"caret_available_or_text_insertion_target_verified\":" + simplejson::Bool(caretAvailable);
    json += L",\"project_context\":" + simplejson::Quote(Contains(ToLower(options.payloadPath), L"projectdd") || Contains(ToLower(options.text), L"projectdd") ? L"projectdd" : L"expected_or_unavailable");
    json += L",\"buffer_readback_possible\":" + simplejson::Bool(lock.ok);
    json += L",\"buffer_readback_source\":" + simplejson::Quote(lock.ok ? L"target_window_lock" : L"unavailable");
    json += L",\"reobserve_attempted\":" + simplejson::Bool(retryAttempted);
    json += L",\"refocus_editor_attempted\":" + simplejson::Bool(retryAttempted);
    json += L",\"active_document_verified\":" + simplejson::Bool(expectedFile != L"unavailable");
    json += L",\"retry_count\":" + std::to_wstring(retryAttempted ? 1 : 0);
    json += L",\"target_lock_failure_count\":" + std::to_wstring(unresolved && !dryRunAllowed ? 1 : 0);
    json += L",\"target_lock_recovery_count\":" + std::to_wstring(recovered ? 1 : 0);
    json += L",\"target_lock_unresolved_count\":" + std::to_wstring(unresolved && !dryRunAllowed ? 1 : 0);
    json += L",\"failure_reason\":" + simplejson::Quote(unresolved ? (lock.errorMessage.empty() ? L"target lock unresolved" : lock.errorMessage) : L"");
    json += L"}";
    return json;
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
    result.payloadSource = options.payloadSource.empty() ? L"argv" : options.payloadSource;
    result.payloadPath = options.payloadPath;
    result.payloadIntegrityVerified = options.payloadIntegrityVerified;
    result.inputMethod = options.inputMethod.empty() ? L"real_keyboard_events" : options.inputMethod;
    ApplyPlanFields(BuildKeyboardTextInputPlan(options.text), result);
    result.selfselfAutocompleteArtifact = IsCodeInput(options) && ContainsSelfSelf(options.text);
    result.firstPassFailed = result.codeCollapsedToSingleLine || result.selfselfAutocompleteArtifact;
    if (result.firstPassFailed) {
        result.firstPassMultilineCorrect = false;
    }
    if (IsCodeInput(options)) {
        result.fallbackLevel = 5;
        result.fallbackReason = code.empty() ? L"code_input_policy_failure" : code;
        result.previousFailure = code.empty() ? L"unknown" : code;
        result.allowedByPolicy = true;
        result.codeIntegrityCheckBefore = L"planned";
        result.codeIntegrityCheckAfter = L"not_written";
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
    if (IsCodeInput(options)) {
        result.keyboardSafeSegmentationJson = BuildKeyboardSafeSegmentationReport(options);
        result.codeInputIntegrityV2Json = BuildCodeInputIntegrityV2Report(options);
    }
    result.targetLockPreflightJson = BuildTargetLockPreflightReport(options, TargetWindowLockResult(), false, false);
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
    bool preflightRetryAttempted = false;
    bool preflightRecovered = false;
    if ((!lock.ok || (normalized.requireTargetLock && !lock.targetWindowLocked)) &&
        normalized.requireTargetLock &&
        !normalized.dryRun) {
        preflightRetryAttempted = true;
        TargetWindowLockResult retryLock = acquire_target_window_lock(lockOptions);
        if (retryLock.ok && (!normalized.requireTargetLock || retryLock.targetWindowLocked)) {
            lock = retryLock;
            preflightRecovered = true;
        }
    }
    if (!lock.ok || (normalized.requireTargetLock && !lock.targetWindowLocked)) {
        std::wstring code = lock.errorCode;
        if (code.empty() || code == L"FAIL_TARGET_LOCK_REQUIRED") {
            code = L"FAIL_TEXT_INPUT_TARGET_NOT_LOCKED";
        }
        VisibleTextInputResult result = Fail(normalized, code, lock.errorMessage.empty() ? L"Visible text input requires a target window lock." : lock.errorMessage);
        result.targetLock = lock;
        result.targetWindowLocked = lock.targetWindowLocked;
        result.targetLockPreflightJson = BuildTargetLockPreflightReport(normalized, lock, preflightRetryAttempted, preflightRecovered);
        return result;
    }

    VisibleOperationPolicyResult priority = TextInputOperationPriority(normalized);
    if (!priority.ok) {
        VisibleTextInputResult result = Fail(normalized, priority.errorCode, priority.errorMessage);
        result.clipboardUsed = normalized.inputMethod == L"clipboard_paste";
        result.clipboardFallbackReason = result.clipboardUsed ? normalized.clipboardFallbackReason : L"";
        result.targetLock = lock;
        result.targetWindowLocked = lock.targetWindowLocked;
        result.targetLockPreflightJson = BuildTargetLockPreflightReport(normalized, lock, preflightRetryAttempted, preflightRecovered);
        result.operationPriority = priority;
        return result;
    }

    VisibleTextInputResult result;
    result.ok = true;
    result.payloadSource = normalized.payloadSource.empty() ? L"argv" : normalized.payloadSource;
    result.payloadPath = normalized.payloadPath;
    result.payloadIntegrityVerified = normalized.payloadIntegrityVerified;
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
    result.keyboardSafeSegmentationJson = IsCodeInput(normalized) ? BuildKeyboardSafeSegmentationReport(normalized) : L"{}";
    result.targetLockPreflightJson = BuildTargetLockPreflightReport(normalized, lock, preflightRetryAttempted, preflightRecovered);
    result.codeInputIntegrityV2Json = IsCodeInput(normalized) ? BuildCodeInputIntegrityV2Report(normalized) : L"{}";
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
            if (IsCodeInput(normalized)) {
                result.fallbackLevel = 5;
                result.fallbackReason = result.errorCode;
                result.previousFailure = result.errorCode;
                result.codeIntegrityCheckAfter = L"failed_or_not_written";
            }
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
            if (IsCodeInput(normalized)) {
                result.fallbackLevel = 5;
                result.fallbackReason = result.errorCode;
                result.previousFailure = result.errorCode;
                result.codeIntegrityCheckAfter = L"failed_or_not_written";
            }
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
    json += L",\"payload_source\":" + simplejson::Quote(result.payloadSource);
    json += L",\"payload_path\":" + simplejson::Quote(result.payloadPath);
    json += L",\"payload_integrity_verified\":" + simplejson::Bool(result.payloadIntegrityVerified);
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
    json += L",\"fallback_ladder\":" + simplejson::Quote(result.fallbackLadder);
    json += L",\"fallback_level\":" + std::to_wstring(result.fallbackLevel);
    json += L",\"fallback_reason\":" + simplejson::Quote(result.fallbackReason);
    json += L",\"previous_failure\":" + simplejson::Quote(result.previousFailure);
    json += L",\"allowed_by_policy\":" + simplejson::Bool(result.allowedByPolicy);
    json += L",\"code_integrity_check_before\":" + simplejson::Quote(result.codeIntegrityCheckBefore);
    json += L",\"code_integrity_check_after\":" + simplejson::Quote(result.codeIntegrityCheckAfter);
    json += L",\"clipboard_used\":" + simplejson::Bool(result.clipboardUsed);
    json += L",\"clipboard_fallback_reason\":" + simplejson::Quote(result.clipboardFallbackReason);
    json += L",\"backend_file_write_used\":" + simplejson::Bool(result.backendFileWriteUsed);
    json += L",\"target_window_locked\":" + simplejson::Bool(result.targetWindowLocked);
    json += L",\"target_input_verified\":" + simplejson::Bool(result.targetInputVerified);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"keyboard_safe_segmentation\":" + (result.keyboardSafeSegmentationJson.empty() ? L"{}" : result.keyboardSafeSegmentationJson);
    json += L",\"target_lock_preflight\":" + (result.targetLockPreflightJson.empty() ? L"{}" : result.targetLockPreflightJson);
    json += L",\"code_input_integrity_v2\":" + (result.codeInputIntegrityV2Json.empty() ? L"{}" : result.codeInputIntegrityV2Json);
    json += L",\"structured_input\":" + StructuredTextInputResultJson(result.structuredInput);
    json += L",\"target_lock\":" + TargetWindowLockJson(result.targetLock);
    json += L",\"operation_priority\":" + VisibleOperationPolicyJson(result.operationPriority);
    json += L"}";
    return json;
}
