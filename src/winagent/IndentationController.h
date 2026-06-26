#pragma once

#include <string>
#include <vector>

struct IndentationOptions {
    std::wstring indentMode = L"spaces";
    int indentWidth = 4;
    int maxResetShiftTabs = 12;
};

struct StructuredCodeLine {
    int lineIndex = 0;
    std::wstring rawLine;
    int targetIndentSpaces = 0;
    int targetIndentLevel = 0;
    std::wstring contentWithoutIndent;
    bool isBlankLine = false;
};

struct IndentationLinePlan {
    StructuredCodeLine line;
    bool autoIndentDetected = false;
    bool autoIndentCorrectionApplied = false;
    bool editorAutoIndentModelUsed = false;
    bool naturalAutoIndentUsed = false;
    bool explicitIndentCorrectionApplied = false;
    bool expectedEditorAutoDedent = false;
    int predictedAutoIndentSpaces = 0;
    int indentDeltaSpaces = 0;
    int targetIndentSpaces = 0;
    int targetIndentLevel = 0;
    int actualIndentCorrectionKeys = 0;
    int spacesTyped = 0;
    int tabsTyped = 0;
    bool lineInputVerified = false;
    std::wstring resetStrategy;
    std::wstring indentText;
};

std::wstring NormalizeIndentMode(const std::wstring& mode);
IndentationOptions NormalizeIndentationOptions(const IndentationOptions& options);
int detect_target_indentation(const std::wstring& rawLine, const IndentationOptions& options);
StructuredCodeLine normalize_line_indent(int lineIndex, const std::wstring& rawLine, const IndentationOptions& options);
std::vector<StructuredCodeLine> parse_code_lines(const std::wstring& text, const IndentationOptions& options);
IndentationLinePlan reset_current_line_indent(const StructuredCodeLine& line, const IndentationOptions& options, bool firstLine);
std::wstring apply_target_indent(const IndentationLinePlan& plan);
bool detect_auto_indent_drift(const IndentationLinePlan& plan);
IndentationLinePlan recover_indent_drift(const StructuredCodeLine& line, const IndentationOptions& options, bool firstLine);
std::wstring StructuredCodeLineJson(const StructuredCodeLine& line);
std::wstring IndentationLinePlanJson(const IndentationLinePlan& plan);
