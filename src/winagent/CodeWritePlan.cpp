#include "CodeWritePlan.h"

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

bool Contains(const std::wstring& value, const std::wstring& needle) {
    return value.find(needle) != std::wstring::npos;
}

bool IdentifierChar(wchar_t ch) {
    return std::iswalnum(ch) || ch == L'_';
}

std::wstring ExtractIdentifierAt(const std::wstring& value, size_t start) {
    while (start < value.size() && !IdentifierChar(value[start])) ++start;
    size_t end = start;
    while (end < value.size() && IdentifierChar(value[end])) ++end;
    if (end <= start) return L"";
    return value.substr(start, end - start);
}

std::wstring ExtractIdentifierAfterToken(const std::wstring& trimmed, const std::wstring& token) {
    std::wstring lower = ToLower(trimmed);
    size_t pos = lower.find(token);
    if (pos == std::wstring::npos) return L"";
    return ExtractIdentifierAt(trimmed, pos + token.size());
}

std::wstring PythonFunctionName(const std::wstring& trimmed) {
    if (!StartsWith(trimmed, L"def ")) return L"";
    size_t open = trimmed.find(L'(');
    if (open == std::wstring::npos || open <= 4) return L"";
    return Trim(trimmed.substr(4, open - 4));
}

std::wstring FunctionNameBeforeParen(const std::wstring& trimmed) {
    size_t open = trimmed.find(L'(');
    if (open == std::wstring::npos || open == 0) return L"";
    size_t end = open;
    while (end > 0 && std::iswspace(trimmed[end - 1])) --end;
    size_t start = end;
    while (start > 0 && IdentifierChar(trimmed[start - 1])) --start;
    if (end <= start) return L"";
    return trimmed.substr(start, end - start);
}

std::wstring PythonFirstArgument(const std::wstring& trimmed) {
    size_t open = trimmed.find(L'(');
    size_t close = trimmed.find(L')', open == std::wstring::npos ? 0 : open + 1);
    if (open == std::wstring::npos || close == std::wstring::npos || close <= open + 1) return L"";
    std::wstring args = Trim(trimmed.substr(open + 1, close - open - 1));
    size_t comma = args.find(L',');
    if (comma != std::wstring::npos) args = args.substr(0, comma);
    return Trim(args);
}

bool HasPythonReceiver(const std::wstring& trimmed) {
    std::wstring first = PythonFirstArgument(trimmed);
    return first == L"self" || first == L"cls";
}

bool LooksLikeIncludeOrImport(const std::wstring& trimmed) {
    std::wstring lower = ToLower(trimmed);
    return StartsWith(lower, L"#include") || StartsWith(lower, L"import ") ||
           StartsWith(lower, L"from ") || StartsWith(lower, L"package ");
}

bool LooksLikeClassDeclaration(const std::wstring& trimmed) {
    std::wstring lower = ToLower(trimmed);
    return StartsWith(lower, L"class ") || StartsWith(lower, L"public class ") ||
           StartsWith(lower, L"struct ") || StartsWith(lower, L"interface ");
}

bool LooksLikeFunctionDeclaration(const std::wstring& trimmed, const std::wstring& language) {
    std::wstring lower = ToLower(trimmed);
    if (language == L"python") return StartsWith(lower, L"def ");
    if (language == L"kotlin") return StartsWith(lower, L"fun ") && Contains(lower, L"(");
    if (StartsWith(lower, L"if ") || StartsWith(lower, L"for ") || StartsWith(lower, L"while ") ||
        StartsWith(lower, L"switch ") || StartsWith(lower, L"catch ") || StartsWith(lower, L"return ")) {
        return false;
    }
    if (LooksLikeClassDeclaration(trimmed)) return false;
    return Contains(trimmed, L"(") && Contains(trimmed, L")") && Contains(trimmed, L"{");
}

bool LooksLikeMainFunction(const std::wstring& trimmed, const std::wstring& language) {
    std::wstring lower = ToLower(trimmed);
    if (language == L"kotlin") return StartsWith(lower, L"fun main(") || StartsWith(lower, L"fun main ");
    return Contains(lower, L" main(") || StartsWith(lower, L"main(") || Contains(lower, L" main (");
}

std::wstring ClassNameFromLine(const std::wstring& trimmed) {
    std::wstring lower = ToLower(trimmed);
    if (StartsWith(lower, L"public class ")) return ExtractIdentifierAfterToken(trimmed, L"class ");
    if (StartsWith(lower, L"class ")) return ExtractIdentifierAfterToken(trimmed, L"class ");
    if (StartsWith(lower, L"struct ")) return ExtractIdentifierAfterToken(trimmed, L"struct ");
    if (StartsWith(lower, L"interface ")) return ExtractIdentifierAfterToken(trimmed, L"interface ");
    return L"";
}

void AddFinding(CodeWritePlanResult& result, const std::wstring& finding) {
    result.ok = false;
    result.findings.push_back(finding);
}

void BuildPythonPlan(CodeWritePlanResult& result) {
    std::vector<size_t> classStack;
    for (const auto& line : result.lines) {
        std::wstring trimmed = Trim(line.contentWithoutIndent);
        if (trimmed.empty()) continue;

        while (!classStack.empty() && line.targetIndentSpaces <= result.classes[classStack.back()].targetIndentSpaces) {
            classStack.pop_back();
        }

        if (LooksLikeIncludeOrImport(trimmed)) {
            result.importIncludeSection.push_back({trimmed, line.lineIndex, line.targetIndentSpaces});
            continue;
        }

        if (StartsWith(trimmed, L"class ")) {
            CodeClassPlan cls;
            cls.name = ClassNameFromLine(trimmed);
            cls.lineIndex = line.lineIndex;
            cls.targetIndentSpaces = line.targetIndentSpaces;
            result.classes.push_back(cls);
            classStack.push_back(result.classes.size() - 1);
            if (line.targetIndentSpaces != 0) {
                AddFinding(result, L"Python class declarations must be at file scope in the code write plan.");
            }
            continue;
        }

        if (StartsWith(trimmed, L"def ")) {
            bool insideClass = !classStack.empty() && line.targetIndentSpaces > result.classes[classStack.back()].targetIndentSpaces;
            if (insideClass) {
                CodeMethodPlan method;
                method.name = PythonFunctionName(trimmed);
                method.signature = trimmed;
                method.className = result.classes[classStack.back()].name;
                method.lineIndex = line.lineIndex;
                method.targetIndentSpaces = line.targetIndentSpaces;
                method.constructor = method.name == L"__init__";
                method.receiverToken = PythonFirstArgument(trimmed);
                method.hasReceiver = HasPythonReceiver(trimmed);
                result.classes[classStack.back()].methods.push_back(method);
            } else {
                CodeFunctionPlan fn;
                fn.name = PythonFunctionName(trimmed);
                fn.signature = trimmed;
                fn.lineIndex = line.lineIndex;
                fn.targetIndentSpaces = line.targetIndentSpaces;
                fn.receiverToken = PythonFirstArgument(trimmed);
                fn.hasReceiver = HasPythonReceiver(trimmed);
                result.topLevelFunctions.push_back(fn);
            }
            continue;
        }

        if (line.targetIndentSpaces == 0) {
            result.topLevelStatements.push_back({trimmed, L"global", line.lineIndex, line.targetIndentSpaces});
        }
    }
}

void BuildCStylePlan(CodeWritePlanResult& result) {
    for (const auto& line : result.lines) {
        std::wstring trimmed = Trim(line.contentWithoutIndent);
        if (trimmed.empty()) continue;

        if (LooksLikeIncludeOrImport(trimmed)) {
            result.importIncludeSection.push_back({trimmed, line.lineIndex, line.targetIndentSpaces});
            continue;
        }

        if (LooksLikeClassDeclaration(trimmed)) {
            CodeClassPlan cls;
            cls.name = ClassNameFromLine(trimmed);
            cls.lineIndex = line.lineIndex;
            cls.targetIndentSpaces = line.targetIndentSpaces;
            result.classes.push_back(cls);
            continue;
        }

        if (LooksLikeFunctionDeclaration(trimmed, result.language)) {
            CodeFunctionPlan fn;
            fn.name = result.language == L"kotlin" ? ExtractIdentifierAfterToken(trimmed, L"fun ") : FunctionNameBeforeParen(trimmed);
            fn.signature = trimmed;
            fn.lineIndex = line.lineIndex;
            fn.targetIndentSpaces = line.targetIndentSpaces;
            fn.mainFunction = LooksLikeMainFunction(trimmed, result.language);
            if (fn.mainFunction) {
                result.mainFunctions.push_back(fn);
            } else {
                result.topLevelFunctions.push_back(fn);
            }
            continue;
        }

        if (line.targetIndentSpaces == 0) {
            result.topLevelStatements.push_back({trimmed, L"global", line.lineIndex, line.targetIndentSpaces});
        }
    }
}

std::wstring CodeMethodPlanJson(const CodeMethodPlan& method) {
    std::wstring json = L"{";
    json += L"\"name\":" + simplejson::Quote(method.name);
    json += L",\"signature\":" + simplejson::Quote(method.signature);
    json += L",\"class_name\":" + simplejson::Quote(method.className);
    json += L",\"receiver_token\":" + simplejson::Quote(method.receiverToken);
    json += L",\"line_index\":" + std::to_wstring(method.lineIndex);
    json += L",\"target_indent_spaces\":" + std::to_wstring(method.targetIndentSpaces);
    json += L",\"constructor\":" + simplejson::Bool(method.constructor);
    json += L",\"has_receiver\":" + simplejson::Bool(method.hasReceiver);
    json += L",\"expected_scope_class\":" + simplejson::Bool(method.expectedScopeClass);
    json += L"}";
    return json;
}

std::wstring CodeFunctionPlanJson(const CodeFunctionPlan& fn) {
    std::wstring json = L"{";
    json += L"\"name\":" + simplejson::Quote(fn.name);
    json += L",\"signature\":" + simplejson::Quote(fn.signature);
    json += L",\"receiver_token\":" + simplejson::Quote(fn.receiverToken);
    json += L",\"line_index\":" + std::to_wstring(fn.lineIndex);
    json += L",\"target_indent_spaces\":" + std::to_wstring(fn.targetIndentSpaces);
    json += L",\"main_function\":" + simplejson::Bool(fn.mainFunction);
    json += L",\"has_receiver\":" + simplejson::Bool(fn.hasReceiver);
    json += L"}";
    return json;
}

std::wstring CodeClassPlanJson(const CodeClassPlan& cls) {
    std::wstring json = L"{";
    json += L"\"name\":" + simplejson::Quote(cls.name);
    json += L",\"line_index\":" + std::to_wstring(cls.lineIndex);
    json += L",\"target_indent_spaces\":" + std::to_wstring(cls.targetIndentSpaces);
    json += L",\"methods\":[";
    for (size_t i = 0; i < cls.methods.size(); ++i) {
        if (i) json += L",";
        json += CodeMethodPlanJson(cls.methods[i]);
    }
    json += L"]}";
    return json;
}

std::wstring CodeStatementPlanJson(const CodeStatementPlan& statement) {
    std::wstring json = L"{";
    json += L"\"text\":" + simplejson::Quote(statement.text);
    json += L",\"expected_scope\":" + simplejson::Quote(statement.expectedScope);
    json += L",\"line_index\":" + std::to_wstring(statement.lineIndex);
    json += L",\"target_indent_spaces\":" + std::to_wstring(statement.targetIndentSpaces);
    json += L"}";
    return json;
}

std::wstring CodeIncludeImportPlanJson(const CodeIncludeImportPlan& entry) {
    std::wstring json = L"{";
    json += L"\"text\":" + simplejson::Quote(entry.text);
    json += L",\"line_index\":" + std::to_wstring(entry.lineIndex);
    json += L",\"target_indent_spaces\":" + std::to_wstring(entry.targetIndentSpaces);
    json += L"}";
    return json;
}

}  // namespace

CodeWritePlanResult BuildCodeWritePlan(const std::wstring& text, const IndentationOptions& options) {
    IndentationOptions normalized = NormalizeIndentationOptions(options);
    CodeWritePlanResult result;
    result.sourceText = text;
    result.lines = parse_code_lines(text, normalized);
    result.languageScope = AnalyzeLanguageScope(result.lines, normalized);
    result.editorAutoIndent = BuildEditorAutoIndentPlan(result.lines, result.languageScope, normalized);
    result.language = result.languageScope.language;
    result.ok = result.languageScope.ok && result.editorAutoIndent.ok;

    if (result.language == L"python") {
        BuildPythonPlan(result);
    } else {
        BuildCStylePlan(result);
    }

    if (!result.languageScope.ok) {
        for (const auto& finding : result.languageScope.findings) {
            result.findings.push_back(finding);
        }
    }
    return result;
}

std::wstring CodeWritePlanResultJson(const CodeWritePlanResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"code_write_plan\":" + simplejson::Bool(result.codeWritePlan);
    json += L",\"single_file_plan\":" + simplejson::Bool(result.singleFilePlan);
    json += L",\"multi_file_plan_required\":" + simplejson::Bool(result.multiFilePlanRequired);
    json += L",\"language\":" + simplejson::Quote(result.language);
    json += L",\"target_file_path\":" + simplejson::Quote(result.targetFilePath);
    json += L",\"classes\":[";
    for (size_t i = 0; i < result.classes.size(); ++i) {
        if (i) json += L",";
        json += CodeClassPlanJson(result.classes[i]);
    }
    json += L"],\"top_level_functions\":[";
    for (size_t i = 0; i < result.topLevelFunctions.size(); ++i) {
        if (i) json += L",";
        json += CodeFunctionPlanJson(result.topLevelFunctions[i]);
    }
    json += L"],\"main_functions\":[";
    for (size_t i = 0; i < result.mainFunctions.size(); ++i) {
        if (i) json += L",";
        json += CodeFunctionPlanJson(result.mainFunctions[i]);
    }
    json += L"],\"import_include_section\":[";
    for (size_t i = 0; i < result.importIncludeSection.size(); ++i) {
        if (i) json += L",";
        json += CodeIncludeImportPlanJson(result.importIncludeSection[i]);
    }
    json += L"],\"top_level_statements\":[";
    for (size_t i = 0; i < result.topLevelStatements.size(); ++i) {
        if (i) json += L",";
        json += CodeStatementPlanJson(result.topLevelStatements[i]);
    }
    json += L"],\"language_scope\":" + LanguageScopeModelResultJson(result.languageScope);
    json += L",\"editor_auto_indent\":" + EditorAutoIndentModelResultJson(result.editorAutoIndent);
    json += L",\"findings\":[";
    for (size_t i = 0; i < result.findings.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.findings[i]);
    }
    json += L"]}";
    return json;
}
