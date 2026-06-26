#include "LanguageScopeModel.h"

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

bool EndsWith(const std::wstring& value, wchar_t suffix) {
    return !value.empty() && value.back() == suffix;
}

void AddFinding(LanguageScopeModelResult& result, const std::wstring& finding) {
    result.ok = false;
    result.findings.push_back(finding);
}

int CountChar(const std::wstring& value, wchar_t target) {
    int count = 0;
    for (wchar_t ch : value) {
        if (ch == target) ++count;
    }
    return count;
}

bool IsControlStatement(const std::wstring& lower) {
    return StartsWith(lower, L"if ") || StartsWith(lower, L"if(") ||
           StartsWith(lower, L"for ") || StartsWith(lower, L"for(") ||
           StartsWith(lower, L"while ") || StartsWith(lower, L"while(") ||
           StartsWith(lower, L"switch ") || StartsWith(lower, L"switch(") ||
           StartsWith(lower, L"catch ") || StartsWith(lower, L"catch(") ||
           StartsWith(lower, L"else") || StartsWith(lower, L"try") ||
           StartsWith(lower, L"do ");
}

bool LooksLikeFunctionDeclaration(const std::wstring& trimmed, const std::wstring& language) {
    std::wstring lower = ToLower(trimmed);
    if (trimmed.empty() || IsControlStatement(lower)) return false;
    if (language == L"python") return StartsWith(lower, L"def ");
    if (StartsWith(lower, L"class ") || StartsWith(lower, L"struct ") || StartsWith(lower, L"namespace ")) return false;
    if (StartsWith(lower, L"return ") || StartsWith(lower, L"print") || StartsWith(lower, L"system.out")) return false;
    if (language == L"kotlin") {
        return StartsWith(lower, L"fun ") && Contains(lower, L"(");
    }
    if (!Contains(trimmed, L"(") || !Contains(trimmed, L")") || !Contains(trimmed, L"{")) return false;
    size_t paren = trimmed.find(L'(');
    size_t assign = trimmed.find(L'=');
    if (assign != std::wstring::npos && assign < paren) return false;
    return true;
}

bool LooksLikeClassDeclaration(const std::wstring& trimmed) {
    std::wstring lower = ToLower(trimmed);
    return StartsWith(lower, L"class ") || StartsWith(lower, L"public class ") ||
           StartsWith(lower, L"struct ") || StartsWith(lower, L"interface ");
}

bool LooksLikeIncludeOrImport(const std::wstring& trimmed) {
    std::wstring lower = ToLower(trimmed);
    return StartsWith(lower, L"#include") || StartsWith(lower, L"import ") ||
           StartsWith(lower, L"from ") || StartsWith(lower, L"package ");
}

bool LooksLikeMainFunction(const std::wstring& trimmed, const std::wstring& language) {
    std::wstring lower = ToLower(trimmed);
    if (language == L"kotlin") return StartsWith(lower, L"fun main(") || StartsWith(lower, L"fun main ");
    return Contains(lower, L" main(") || StartsWith(lower, L"main(") || Contains(lower, L" main (");
}

bool StartsWithClosingBrace(const std::wstring& trimmed) {
    return StartsWith(trimmed, L"}") || StartsWith(trimmed, L"]") || StartsWith(trimmed, L")");
}

std::wstring PythonFunctionName(const std::wstring& trimmed) {
    if (!StartsWith(trimmed, L"def ")) return L"";
    size_t open = trimmed.find(L'(');
    if (open == std::wstring::npos || open <= 4) return L"";
    return Trim(trimmed.substr(4, open - 4));
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

bool IsKnownPythonClassMethodName(const std::wstring& name) {
    return name == L"__init__" || name == L"introduce" || name == L"show_title";
}

bool IsSuspiciousPythonReceiverToken(const std::wstring& token) {
    std::wstring lower = ToLower(token);
    return lower == L"selfself" ||
           lower == L"self self" ||
           lower == L"self_self" ||
           lower == L"thisself" ||
           lower == L"selfthis" ||
           lower == L"clscls" ||
           (lower.size() > 4 && StartsWith(lower, L"self") && lower != L"self") ||
           (lower.size() > 3 && StartsWith(lower, L"cls") && lower != L"cls");
}

bool IsKnownPythonTopLevelExecution(const std::wstring& trimmed) {
    return StartsWith(trimmed, L"student = Student(") ||
           StartsWith(trimmed, L"course = Course(") ||
           StartsWith(trimmed, L"course.show_title(") ||
           StartsWith(trimmed, L"student.introduce(");
}

}  // namespace

std::wstring DetectCodeLanguage(const std::vector<StructuredCodeLine>& lines) {
    std::wstring joined;
    for (const auto& line : lines) {
        joined += line.contentWithoutIndent + L"\n";
    }
    std::wstring lower = ToLower(joined);
    if (Contains(lower, L"```")) return L"markdown";
    if (Contains(lower, L"#include") || Contains(lower, L"std::") || Contains(lower, L"int main(")) return L"cpp";
    if (Contains(lower, L"public class ") || Contains(lower, L"system.out") || Contains(lower, L"public static void main")) return L"java";
    if (Contains(lower, L"fun main(") || Contains(lower, L"fun ") || Contains(lower, L"println(")) return L"kotlin";
    if (Contains(lower, L"</") || Contains(lower, L"<?xml")) return L"xml";
    if (Contains(lower, L"{\n") || Contains(lower, L"[\n")) return L"json";
    if (Contains(lower, L"class ") || Contains(lower, L"def ") || Contains(lower, L"self.")) return L"python";
    return L"unknown";
}

LanguageScopeModelResult AnalyzeLanguageScope(const std::vector<StructuredCodeLine>& lines, const IndentationOptions&) {
    LanguageScopeModelResult result;
    result.language = DetectCodeLanguage(lines);

    int braceDepth = 0;
    int mainBodyDepth = -1;
    std::vector<int> pythonClassIndentStack;
    for (const auto& codeLine : lines) {
        LanguageScopeLine line;
        line.lineIndex = codeLine.lineIndex;
        line.contentWithoutIndent = codeLine.contentWithoutIndent;
        line.targetIndentSpaces = codeLine.targetIndentSpaces;
        line.isBlankLine = codeLine.isBlankLine;
        std::wstring trimmed = Trim(codeLine.contentWithoutIndent);
        std::wstring lower = ToLower(trimmed);

        int depthBefore = braceDepth;
        if (StartsWithClosingBrace(trimmed) && depthBefore > 0) --depthBefore;
        line.scopeDepthBefore = depthBefore;
        line.insideMainBefore = mainBodyDepth >= 0 && braceDepth >= mainBodyDepth;
        line.isIncludeOrImport = LooksLikeIncludeOrImport(trimmed);
        line.isClassDeclaration = LooksLikeClassDeclaration(trimmed);
        line.isFunctionDeclaration = LooksLikeFunctionDeclaration(trimmed, result.language);
        line.isMainFunction = LooksLikeMainFunction(trimmed, result.language);
        line.closesScope = StartsWithClosingBrace(trimmed);
        line.opensScope = Contains(trimmed, L"{") || EndsWith(trimmed, L':');

        if (result.language == L"python" && !line.isBlankLine) {
            while (!pythonClassIndentStack.empty() && line.targetIndentSpaces <= pythonClassIndentStack.back()) {
                pythonClassIndentStack.pop_back();
            }

            if (line.isIncludeOrImport && line.targetIndentSpaces != 0) {
                line.invalidIncludeOrImportInScope = true;
                result.includeImportTopLevelVerified = false;
                AddFinding(result, L"Python import/from statements must stay at file scope.");
            }

            if (line.isClassDeclaration) {
                if (line.targetIndentSpaces != 0) {
                    line.invalidMethodOutsideClass = true;
                    result.classScopeVerified = false;
                    AddFinding(result, L"Python class declarations must stay at file scope.");
                }
                pythonClassIndentStack.push_back(line.targetIndentSpaces);
            }

            if (line.isFunctionDeclaration) {
                bool insideClass = !pythonClassIndentStack.empty() && line.targetIndentSpaces > pythonClassIndentStack.back();
                std::wstring functionName = PythonFunctionName(trimmed);
                std::wstring firstArg = PythonFirstArgument(trimmed);
                bool hasReceiver = firstArg == L"self" || firstArg == L"cls";
                if (IsSuspiciousPythonReceiverToken(firstArg) || Contains(trimmed, L"selfself")) {
                    line.invalidMethodOutsideClass = true;
                    result.classScopeVerified = false;
                    AddFinding(result, L"Python method receiver token must be exact; duplicated receiver tokens are forbidden.");
                }
                if (insideClass && !hasReceiver) {
                    line.invalidMethodOutsideClass = true;
                    result.classScopeVerified = false;
                    AddFinding(result, L"Python class methods must include self or cls.");
                }
                if (!insideClass && (hasReceiver || IsKnownPythonClassMethodName(functionName))) {
                    line.invalidMethodOutsideClass = true;
                    result.classScopeVerified = false;
                    AddFinding(result, L"Python instance methods must not be declared at file scope.");
                }
            }

            if (IsKnownPythonTopLevelExecution(trimmed) && line.targetIndentSpaces != 0) {
                result.classScopeVerified = false;
                AddFinding(result, L"Python top-level execution statements must stay at file scope.");
            }
        }

        if (line.isIncludeOrImport) {
            bool topLevelRequired = result.language == L"cpp" || result.language == L"java" || result.language == L"kotlin";
            if (topLevelRequired && depthBefore != 0) {
                line.invalidIncludeOrImportInScope = true;
                result.includeImportTopLevelVerified = false;
                AddFinding(result, L"include/import/package statements must stay at file scope.");
            }
        }

        if (line.isMainFunction) {
            bool mainNested = false;
            if (result.language == L"cpp" || result.language == L"kotlin") {
                mainNested = depthBefore != 0;
            } else if (result.language == L"java") {
                mainNested = depthBefore != 1;
            }
            if (mainNested) {
                line.invalidMainInsideFunction = true;
                result.mainNotNestedInFunction = false;
                AddFinding(result, L"main must not be nested inside another function or invalid scope.");
            }
        }

        if (line.isFunctionDeclaration && !line.isMainFunction) {
            if (line.insideMainBefore || (result.language == L"java" && depthBefore >= 2)) {
                line.invalidFunctionInsideMain = true;
                result.functionNotNestedInMain = false;
                AddFinding(result, L"function or method declarations must not be nested inside main.");
            }
            if (result.language == L"java" && depthBefore == 0) {
                line.invalidMethodOutsideClass = true;
                result.classScopeVerified = false;
                AddFinding(result, L"Java methods must be declared inside a class scope.");
            }
        }

        braceDepth += CountChar(trimmed, L'{');
        braceDepth -= CountChar(trimmed, L'}');
        if (braceDepth < 0) braceDepth = 0;
        line.scopeDepthAfter = braceDepth;
        if (line.isMainFunction && Contains(trimmed, L"{")) {
            mainBodyDepth = line.scopeDepthBefore + 1;
        }
        if (mainBodyDepth >= 0 && braceDepth < mainBodyDepth) {
            mainBodyDepth = -1;
        }

        result.lines.push_back(line);
    }

    return result;
}

std::wstring LanguageScopeLineJson(const LanguageScopeLine& line) {
    std::wstring json = L"{";
    json += L"\"line_index\":" + std::to_wstring(line.lineIndex);
    json += L",\"content_without_indent\":" + simplejson::Quote(line.contentWithoutIndent);
    json += L",\"target_indent_spaces\":" + std::to_wstring(line.targetIndentSpaces);
    json += L",\"scope_depth_before\":" + std::to_wstring(line.scopeDepthBefore);
    json += L",\"scope_depth_after\":" + std::to_wstring(line.scopeDepthAfter);
    json += L",\"is_blank_line\":" + simplejson::Bool(line.isBlankLine);
    json += L",\"opens_scope\":" + simplejson::Bool(line.opensScope);
    json += L",\"closes_scope\":" + simplejson::Bool(line.closesScope);
    json += L",\"is_main_function\":" + simplejson::Bool(line.isMainFunction);
    json += L",\"is_function_declaration\":" + simplejson::Bool(line.isFunctionDeclaration);
    json += L",\"is_class_declaration\":" + simplejson::Bool(line.isClassDeclaration);
    json += L",\"is_include_or_import\":" + simplejson::Bool(line.isIncludeOrImport);
    json += L",\"inside_main_before\":" + simplejson::Bool(line.insideMainBefore);
    json += L",\"invalid_function_inside_main\":" + simplejson::Bool(line.invalidFunctionInsideMain);
    json += L",\"invalid_main_inside_function\":" + simplejson::Bool(line.invalidMainInsideFunction);
    json += L",\"invalid_include_or_import_in_scope\":" + simplejson::Bool(line.invalidIncludeOrImportInScope);
    json += L",\"invalid_method_outside_class\":" + simplejson::Bool(line.invalidMethodOutsideClass);
    json += L"}";
    return json;
}

std::wstring LanguageScopeModelResultJson(const LanguageScopeModelResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"language\":" + simplejson::Quote(result.language);
    json += L",\"language_scope_model\":" + simplejson::Bool(result.languageScopeModel);
    json += L",\"function_not_nested_in_main\":" + simplejson::Bool(result.functionNotNestedInMain);
    json += L",\"main_not_nested_in_function\":" + simplejson::Bool(result.mainNotNestedInFunction);
    json += L",\"include_import_top_level_verified\":" + simplejson::Bool(result.includeImportTopLevelVerified);
    json += L",\"class_scope_verified\":" + simplejson::Bool(result.classScopeVerified);
    json += L",\"findings\":[";
    for (size_t i = 0; i < result.findings.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.findings[i]);
    }
    json += L"],\"lines\":[";
    size_t limit = result.lines.size() > 80 ? 80 : result.lines.size();
    for (size_t i = 0; i < limit; ++i) {
        if (i) json += L",";
        json += LanguageScopeLineJson(result.lines[i]);
    }
    json += L"]}";
    return json;
}
