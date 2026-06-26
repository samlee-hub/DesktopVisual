#include "EditorAutoIndentModel.h"

#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>

namespace {

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && std::iswspace(value[first])) ++first;
    size_t last = value.size();
    while (last > first && std::iswspace(value[last - 1])) --last;
    return value.substr(first, last - first);
}

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    return value.rfind(prefix, 0) == 0;
}

bool EndsWith(const std::wstring& value, wchar_t suffix) {
    return !value.empty() && value.back() == suffix;
}

int CountChar(const std::wstring& value, wchar_t target) {
    int count = 0;
    for (wchar_t ch : value) {
        if (ch == target) ++count;
    }
    return count;
}

std::wstring Repeat(wchar_t ch, int count) {
    if (count <= 0) return L"";
    return std::wstring(static_cast<size_t>(count), ch);
}

bool StartsWithClosingScope(const std::wstring& trimmed) {
    return StartsWith(trimmed, L"}") || StartsWith(trimmed, L"]") || StartsWith(trimmed, L")");
}

bool PythonBlockStarterLikelyAutoDedents(const std::wstring& trimmed) {
    return StartsWith(trimmed, L"class ") || StartsWith(trimmed, L"def ") || StartsWith(trimmed, L"async def ");
}

int PredictNextIndent(const StructuredCodeLine& line, const std::wstring& language, int currentEffectiveIndent, int indentWidth) {
    std::wstring trimmed = Trim(line.contentWithoutIndent);
    if (line.isBlankLine || trimmed.empty()) return currentEffectiveIndent;

    if (language == L"python") {
        if (EndsWith(trimmed, L':')) return line.targetIndentSpaces + indentWidth;
        return line.targetIndentSpaces;
    }

    if (language == L"xml") {
        if (StartsWith(trimmed, L"</")) return line.targetIndentSpaces;
        if (StartsWith(trimmed, L"<") && !StartsWith(trimmed, L"</") &&
            trimmed.find(L"/>") == std::wstring::npos && trimmed.find(L"</") == std::wstring::npos) {
            return line.targetIndentSpaces + indentWidth;
        }
        return line.targetIndentSpaces;
    }

    int opens = CountChar(trimmed, L'{') + CountChar(trimmed, L'[') + CountChar(trimmed, L'(');
    int closes = CountChar(trimmed, L'}') + CountChar(trimmed, L']') + CountChar(trimmed, L')');
    int net = opens - closes;
    if (net > 0) return line.targetIndentSpaces + (net * indentWidth);
    return line.targetIndentSpaces;
}

}  // namespace

EditorAutoIndentModelResult BuildEditorAutoIndentPlan(
    const std::vector<StructuredCodeLine>& lines,
    const LanguageScopeModelResult& scopeModel,
    const IndentationOptions& options) {
    IndentationOptions normalized = NormalizeIndentationOptions(options);
    EditorAutoIndentModelResult result;
    int predictedIndent = 0;

    for (size_t i = 0; i < lines.size(); ++i) {
        const StructuredCodeLine& line = lines[i];
        IndentationLinePlan plan;
        plan.line = line;
        plan.editorAutoIndentModelUsed = true;
        plan.predictedAutoIndentSpaces = predictedIndent;
        plan.targetIndentSpaces = line.targetIndentSpaces;
        plan.targetIndentLevel = line.targetIndentLevel;
        plan.autoIndentDetected = i > 0 && predictedIndent > 0;
        plan.resetStrategy = L"natural_auto_indent";

        std::wstring trimmed = Trim(line.contentWithoutIndent);
        int effectiveIndentAfterLine = line.isBlankLine ? predictedIndent : line.targetIndentSpaces;
        bool closingScope = StartsWithClosingScope(trimmed);
        bool naturalClosingDedent = !line.isBlankLine &&
            closingScope &&
            predictedIndent >= line.targetIndentSpaces + normalized.indentWidth;
        bool naturalPythonBlockStarterDedent = !line.isBlankLine &&
            scopeModel.language == L"python" &&
            PythonBlockStarterLikelyAutoDedents(trimmed) &&
            predictedIndent > line.targetIndentSpaces;

        if (line.isBlankLine) {
            plan.naturalAutoIndentUsed = true;
            plan.resetStrategy = L"blank_line_preserves_editor_indent_state";
            result.naturalAutoIndentFollowed = true;
        } else if (naturalPythonBlockStarterDedent) {
            plan.indentDeltaSpaces = line.targetIndentSpaces - predictedIndent;
            if (line.targetIndentSpaces > 0) {
                plan.explicitIndentCorrectionApplied = true;
                plan.autoIndentCorrectionApplied = true;
                plan.naturalAutoIndentUsed = true;
                plan.resetStrategy = L"python_block_starter_target_indent_from_semantic_baseline";
                if (normalized.indentMode == L"tab") {
                    plan.tabsTyped = normalized.indentWidth > 0 ? line.targetIndentSpaces / normalized.indentWidth : 0;
                    plan.spacesTyped = normalized.indentWidth > 0 ? line.targetIndentSpaces % normalized.indentWidth : line.targetIndentSpaces;
                    plan.indentText = Repeat(L'\t', plan.tabsTyped) + Repeat(L' ', plan.spacesTyped);
                } else {
                    plan.spacesTyped = line.targetIndentSpaces;
                    plan.indentText = Repeat(L' ', line.targetIndentSpaces);
                }
                ++result.explicitCorrectionLineCount;
            } else {
                plan.expectedEditorAutoDedent = true;
                plan.naturalAutoIndentUsed = true;
                plan.resetStrategy = L"natural_python_block_starter_dedent";
            }
            result.naturalAutoIndentFollowed = true;
        } else if (naturalClosingDedent) {
            plan.expectedEditorAutoDedent = true;
            plan.naturalAutoIndentUsed = true;
            plan.resetStrategy = L"natural_editor_dedent_closing_scope";
            result.naturalAutoIndentFollowed = true;
        } else {
            int delta = line.targetIndentSpaces - predictedIndent;
            plan.indentDeltaSpaces = delta;
            if (delta == 0) {
                plan.naturalAutoIndentUsed = i > 0;
                plan.resetStrategy = i == 0 ? L"first_line_at_baseline" : L"natural_auto_indent";
                if (i > 0) result.naturalAutoIndentFollowed = true;
            } else if (delta > 0) {
                plan.explicitIndentCorrectionApplied = true;
                plan.autoIndentCorrectionApplied = true;
                plan.resetStrategy = L"type_missing_indent_delta";
                if (normalized.indentMode == L"tab") {
                    plan.tabsTyped = normalized.indentWidth > 0 ? delta / normalized.indentWidth : 0;
                    plan.spacesTyped = normalized.indentWidth > 0 ? delta % normalized.indentWidth : delta;
                    plan.indentText = Repeat(L'\t', plan.tabsTyped) + Repeat(L' ', plan.spacesTyped);
                } else {
                    plan.spacesTyped = delta;
                    plan.indentText = Repeat(L' ', delta);
                }
                ++result.explicitCorrectionLineCount;
            } else {
                int outdentSpaces = -delta;
                int outdentKeys = normalized.indentWidth > 0
                    ? (outdentSpaces + normalized.indentWidth - 1) / normalized.indentWidth
                    : outdentSpaces;
                plan.explicitIndentCorrectionApplied = true;
                plan.autoIndentCorrectionApplied = true;
                plan.actualIndentCorrectionKeys = outdentKeys;
                plan.resetStrategy = L"shift_tab_to_scope_boundary";
                result.actualIndentCorrectionKeys += outdentKeys;
                ++result.explicitCorrectionLineCount;
            }
        }

        plan.lineInputVerified = true;
        result.linePlans.push_back(plan);
        predictedIndent = PredictNextIndent(line, scopeModel.language, effectiveIndentAfterLine, normalized.indentWidth);
        if (predictedIndent < 0) predictedIndent = 0;
    }

    int nonBlankCount = 0;
    for (const auto& line : lines) {
        if (!line.isBlankLine) ++nonBlankCount;
    }
    if (nonBlankCount > 0 && result.explicitCorrectionLineCount > nonBlankCount) {
        result.minimalIndentCorrection = false;
    }
    return result;
}

std::wstring EditorAutoIndentModelResultJson(const EditorAutoIndentModelResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"editor_auto_indent_model\":" + simplejson::Bool(result.editorAutoIndentModel);
    json += L",\"natural_auto_indent_followed\":" + simplejson::Bool(result.naturalAutoIndentFollowed);
    json += L",\"minimal_indent_correction\":" + simplejson::Bool(result.minimalIndentCorrection);
    json += L",\"explicit_correction_line_count\":" + std::to_wstring(result.explicitCorrectionLineCount);
    json += L",\"actual_indent_correction_keys\":" + std::to_wstring(result.actualIndentCorrectionKeys);
    json += L"}";
    return json;
}
