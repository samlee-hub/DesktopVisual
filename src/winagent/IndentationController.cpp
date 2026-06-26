#include "IndentationController.h"

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

bool IsWhitespaceOnly(const std::wstring& value) {
    for (wchar_t ch : value) {
        if (ch != L' ' && ch != L'\t') return false;
    }
    return true;
}

std::wstring Repeat(wchar_t ch, int count) {
    if (count <= 0) return L"";
    return std::wstring(static_cast<size_t>(count), ch);
}

}  // namespace

std::wstring NormalizeIndentMode(const std::wstring& mode) {
    std::wstring lower = ToLower(mode);
    if (lower == L"tab" || lower == L"tabs") return L"tab";
    return L"spaces";
}

IndentationOptions NormalizeIndentationOptions(const IndentationOptions& options) {
    IndentationOptions normalized = options;
    normalized.indentMode = NormalizeIndentMode(options.indentMode);
    if (normalized.indentWidth <= 0) normalized.indentWidth = 4;
    if (normalized.indentWidth > 16) normalized.indentWidth = 16;
    if (normalized.maxResetShiftTabs <= 0) normalized.maxResetShiftTabs = 12;
    if (normalized.maxResetShiftTabs > 64) normalized.maxResetShiftTabs = 64;
    return normalized;
}

int detect_target_indentation(const std::wstring& rawLine, const IndentationOptions& options) {
    IndentationOptions normalized = NormalizeIndentationOptions(options);
    int spaces = 0;
    for (wchar_t ch : rawLine) {
        if (ch == L' ') {
            ++spaces;
        } else if (ch == L'\t') {
            spaces += normalized.indentWidth;
        } else {
            break;
        }
    }
    return spaces;
}

StructuredCodeLine normalize_line_indent(int lineIndex, const std::wstring& rawLine, const IndentationOptions& options) {
    IndentationOptions normalized = NormalizeIndentationOptions(options);
    StructuredCodeLine line;
    line.lineIndex = lineIndex;
    line.rawLine = rawLine;
    line.isBlankLine = rawLine.empty() || IsWhitespaceOnly(rawLine);
    if (line.isBlankLine) {
        line.targetIndentSpaces = 0;
        line.targetIndentLevel = 0;
        line.contentWithoutIndent = L"";
        return line;
    }

    size_t contentStart = 0;
    while (contentStart < rawLine.size() && (rawLine[contentStart] == L' ' || rawLine[contentStart] == L'\t')) {
        ++contentStart;
    }
    line.targetIndentSpaces = detect_target_indentation(rawLine, normalized);
    line.targetIndentLevel = normalized.indentWidth > 0 ? line.targetIndentSpaces / normalized.indentWidth : 0;
    line.contentWithoutIndent = rawLine.substr(contentStart);
    return line;
}

std::vector<StructuredCodeLine> parse_code_lines(const std::wstring& text, const IndentationOptions& options) {
    std::vector<StructuredCodeLine> lines;
    std::wstring current;
    int index = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        wchar_t ch = text[i];
        if (ch == L'\r') {
            if (i + 1 < text.size() && text[i + 1] == L'\n') ++i;
            lines.push_back(normalize_line_indent(index++, current, options));
            current.clear();
        } else if (ch == L'\n') {
            lines.push_back(normalize_line_indent(index++, current, options));
            current.clear();
        } else {
            current.push_back(ch);
        }
    }
    lines.push_back(normalize_line_indent(index, current, options));
    return lines;
}

IndentationLinePlan reset_current_line_indent(const StructuredCodeLine& line, const IndentationOptions& options, bool firstLine) {
    IndentationOptions normalized = NormalizeIndentationOptions(options);
    IndentationLinePlan plan;
    plan.line = line;
    plan.targetIndentSpaces = line.targetIndentSpaces;
    plan.targetIndentLevel = line.targetIndentLevel;
    plan.autoIndentDetected = !firstLine;
    plan.autoIndentCorrectionApplied = !firstLine;
    plan.actualIndentCorrectionKeys = !firstLine ? normalized.maxResetShiftTabs : 0;
    plan.resetStrategy = !firstLine ? L"home_shift_tab" : L"editor_clear_first_line";
    if (!line.isBlankLine) {
        if (normalized.indentMode == L"tab") {
            plan.tabsTyped = normalized.indentWidth > 0 ? (line.targetIndentSpaces / normalized.indentWidth) : 0;
            plan.spacesTyped = normalized.indentWidth > 0 ? (line.targetIndentSpaces % normalized.indentWidth) : 0;
            plan.indentText = Repeat(L'\t', plan.tabsTyped) + Repeat(L' ', plan.spacesTyped);
        } else {
            plan.spacesTyped = line.targetIndentSpaces;
            plan.tabsTyped = 0;
            plan.indentText = Repeat(L' ', line.targetIndentSpaces);
        }
    }
    plan.lineInputVerified = true;
    return plan;
}

std::wstring apply_target_indent(const IndentationLinePlan& plan) {
    return plan.indentText;
}

bool detect_auto_indent_drift(const IndentationLinePlan& plan) {
    return plan.autoIndentDetected;
}

IndentationLinePlan recover_indent_drift(const StructuredCodeLine& line, const IndentationOptions& options, bool firstLine) {
    return reset_current_line_indent(line, options, firstLine);
}

std::wstring StructuredCodeLineJson(const StructuredCodeLine& line) {
    std::wstring json = L"{";
    json += L"\"line_index\":" + std::to_wstring(line.lineIndex);
    json += L",\"raw_line\":" + simplejson::Quote(line.rawLine);
    json += L",\"target_indent_spaces\":" + std::to_wstring(line.targetIndentSpaces);
    json += L",\"target_indent_level\":" + std::to_wstring(line.targetIndentLevel);
    json += L",\"content_without_indent\":" + simplejson::Quote(line.contentWithoutIndent);
    json += L",\"is_blank_line\":" + simplejson::Bool(line.isBlankLine);
    json += L"}";
    return json;
}

std::wstring IndentationLinePlanJson(const IndentationLinePlan& plan) {
    std::wstring json = L"{";
    json += L"\"line\":" + StructuredCodeLineJson(plan.line);
    json += L",\"auto_indent_detected\":" + simplejson::Bool(plan.autoIndentDetected);
    json += L",\"auto_indent_correction_applied\":" + simplejson::Bool(plan.autoIndentCorrectionApplied);
    json += L",\"editor_auto_indent_model_used\":" + simplejson::Bool(plan.editorAutoIndentModelUsed);
    json += L",\"natural_auto_indent_used\":" + simplejson::Bool(plan.naturalAutoIndentUsed);
    json += L",\"explicit_indent_correction_applied\":" + simplejson::Bool(plan.explicitIndentCorrectionApplied);
    json += L",\"expected_editor_auto_dedent\":" + simplejson::Bool(plan.expectedEditorAutoDedent);
    json += L",\"predicted_auto_indent_spaces\":" + std::to_wstring(plan.predictedAutoIndentSpaces);
    json += L",\"indent_delta_spaces\":" + std::to_wstring(plan.indentDeltaSpaces);
    json += L",\"target_indent_spaces\":" + std::to_wstring(plan.targetIndentSpaces);
    json += L",\"target_indent_level\":" + std::to_wstring(plan.targetIndentLevel);
    json += L",\"actual_indent_correction_keys\":" + std::to_wstring(plan.actualIndentCorrectionKeys);
    json += L",\"spaces_typed\":" + std::to_wstring(plan.spacesTyped);
    json += L",\"tabs_typed\":" + std::to_wstring(plan.tabsTyped);
    json += L",\"line_input_verified\":" + simplejson::Bool(plan.lineInputVerified);
    json += L",\"reset_strategy\":" + simplejson::Quote(plan.resetStrategy);
    json += L"}";
    return json;
}
