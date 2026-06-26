#include "TextInputVerifier.h"

#include "IndentationController.h"
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

bool EndsWith(const std::wstring& value, wchar_t suffix) {
    return !value.empty() && value.back() == suffix;
}

bool Contains(const std::wstring& value, const std::wstring& needle) {
    return value.find(needle) != std::wstring::npos;
}

bool IsCodeKind(const std::wstring& kind) {
    std::wstring lower = ToLower(kind);
    return lower.find(L"code") != std::wstring::npos || lower.find(L"editor") != std::wstring::npos || lower.find(L"ide") != std::wstring::npos;
}

bool LooksLikePython(const std::wstring& text) {
    if (Contains(text, L"```")) return false;
    if (Contains(text, L"self.") || Contains(text, L"def ") || Contains(text, L"class Student:") || Contains(text, L"class Course:")) return true;
    std::wstring current;
    for (size_t i = 0; i <= text.size(); ++i) {
        if (i == text.size() || text[i] == L'\n' || text[i] == L'\r') {
            std::wstring trimmed = Trim(current);
            if ((StartsWith(trimmed, L"class ") || StartsWith(trimmed, L"def ")) && EndsWith(trimmed, L':')) {
                return true;
            }
            current.clear();
            if (i < text.size() && text[i] == L'\r' && i + 1 < text.size() && text[i + 1] == L'\n') ++i;
        } else {
            current.push_back(text[i]);
        }
    }
    return false;
}

void AddFinding(TextInputVerificationResult& result, const std::wstring& finding) {
    result.findings.push_back(finding);
    if (result.errorCode.empty()) {
        result.errorCode = L"CODE_STRUCTURE_MISMATCH";
        result.errorMessage = finding;
    }
}

bool IsKnownTopLevelExecution(const std::wstring& trimmed) {
    return StartsWith(trimmed, L"student = Student(") ||
           StartsWith(trimmed, L"course = Course(") ||
           StartsWith(trimmed, L"course.show_title(") ||
           StartsWith(trimmed, L"course.show(") ||
           StartsWith(trimmed, L"student.introduce(");
}

std::wstring PythonFunctionName(const std::wstring& trimmed) {
    if (!StartsWith(trimmed, L"def ")) return L"";
    size_t nameStart = 4;
    while (nameStart < trimmed.size() && std::iswspace(trimmed[nameStart])) ++nameStart;
    size_t open = trimmed.find(L'(', nameStart);
    if (open == std::wstring::npos || open <= nameStart) return L"";
    return trimmed.substr(nameStart, open - nameStart);
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

bool IsKnownClassMethodName(const std::wstring& name) {
    return name == L"__init__" || name == L"introduce" || name == L"show_title";
}

bool IsSuspiciousReceiverToken(const std::wstring& token) {
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

bool FunctionBodyUsesReceiver(const std::vector<StructuredCodeLine>& lines, size_t functionLineIndex, int functionIndent, const std::wstring& receiver) {
    std::wstring needle = receiver + L".";
    for (size_t j = functionLineIndex + 1; j < lines.size(); ++j) {
        std::wstring next = Trim(lines[j].contentWithoutIndent);
        if (next.empty()) continue;
        if (lines[j].targetIndentSpaces <= functionIndent) break;
        if (Contains(next, needle)) return true;
    }
    return false;
}

bool VerifyPython(const std::wstring& text, bool runSucceeded, TextInputVerificationResult& result) {
    IndentationOptions indent;
    std::vector<StructuredCodeLine> lines = parse_code_lines(text, indent);
    bool sawStudent = false;
    bool sawCourse = false;
    bool sawKnownExecution = false;
    bool checkedBlockBody = false;
    bool blockBodyOk = true;
    bool pythonMethodScopeOk = true;
    bool receiverBindingOk = true;
    std::vector<int> classIndentStack;

    for (size_t i = 0; i < lines.size(); ++i) {
        const StructuredCodeLine& line = lines[i];
        std::wstring trimmed = Trim(line.contentWithoutIndent);
        if (trimmed.empty()) continue;
        while (!classIndentStack.empty() && line.targetIndentSpaces <= classIndentStack.back()) {
            classIndentStack.pop_back();
        }

        if (StartsWith(trimmed, L"class Student")) {
            sawStudent = true;
            if (line.targetIndentSpaces != 0) {
                AddFinding(result, L"class Student must be top-level.");
            }
        }
        if (StartsWith(trimmed, L"class Course")) {
            sawCourse = true;
            if (line.targetIndentSpaces != 0) {
                result.classCourseNotNestedInStudent = false;
                AddFinding(result, L"class Course must not be nested under Student or another block.");
            }
        }
        if (StartsWith(trimmed, L"class ")) {
            classIndentStack.push_back(line.targetIndentSpaces);
        }
        if (StartsWith(trimmed, L"def ")) {
            std::wstring functionName = PythonFunctionName(trimmed);
            std::wstring firstArg = PythonFirstArgument(trimmed);
            bool insideClass = !classIndentStack.empty() && line.targetIndentSpaces > classIndentStack.back();
            bool hasMethodReceiver = firstArg == L"self" || firstArg == L"cls";
            bool duplicateReceiver = IsSuspiciousReceiverToken(firstArg);
            if (duplicateReceiver || Contains(trimmed, L"selfself")) {
                result.duplicateReceiverTokenDetected = true;
                result.selfselfPresent = result.selfselfPresent || Contains(trimmed, L"selfself") || firstArg == L"selfself";
                receiverBindingOk = false;
                pythonMethodScopeOk = false;
                AddFinding(result, L"Python method receiver token must be an exact token; duplicated receiver tokens are forbidden.");
                if (result.errorCode == L"CODE_STRUCTURE_MISMATCH") {
                    result.errorCode = L"BLOCKED_DUPLICATED_RECEIVER_TOKEN";
                }
            }
            if (insideClass && !hasMethodReceiver) {
                result.invalidPythonMethodReceiver = true;
                receiverBindingOk = false;
                pythonMethodScopeOk = false;
                AddFinding(result, L"Python class methods must include self or cls as the first argument.");
                if (!result.duplicateReceiverTokenDetected && result.errorCode == L"CODE_STRUCTURE_MISMATCH") {
                    result.errorCode = L"BLOCKED_INVALID_PYTHON_METHOD_RECEIVER";
                }
            }
            if (!insideClass && (hasMethodReceiver || IsKnownClassMethodName(functionName))) {
                result.invalidPythonMethodReceiver = true;
                receiverBindingOk = false;
                pythonMethodScopeOk = false;
                AddFinding(result, L"Python class methods must not be emitted at file scope.");
            }
            bool bodyUsesSelf = FunctionBodyUsesReceiver(lines, i, line.targetIndentSpaces, L"self");
            if (bodyUsesSelf && firstArg != L"self") {
                result.invalidPythonMethodReceiver = true;
                receiverBindingOk = false;
                pythonMethodScopeOk = false;
                AddFinding(result, L"Python method body uses self.*, so the first parameter must be the exact token self.");
                if (!result.duplicateReceiverTokenDetected && result.errorCode == L"CODE_STRUCTURE_MISMATCH") {
                    result.errorCode = L"BLOCKED_INVALID_PYTHON_METHOD_RECEIVER";
                }
            }
            if (trimmed.back() != L':') {
                pythonMethodScopeOk = false;
                AddFinding(result, L"Python function headers must end with ':'.");
            }
        }
        if (IsKnownTopLevelExecution(trimmed)) {
            sawKnownExecution = true;
            if (line.targetIndentSpaces != 0) {
                AddFinding(result, L"Top-level execution statements must not be indented into a class or function block.");
            }
        }

        if (EndsWith(trimmed, L':')) {
            checkedBlockBody = true;
            bool foundBody = false;
            for (size_t j = i + 1; j < lines.size(); ++j) {
                std::wstring next = Trim(lines[j].contentWithoutIndent);
                if (next.empty()) continue;
                foundBody = true;
                if (lines[j].targetIndentSpaces <= line.targetIndentSpaces) {
                    blockBodyOk = false;
                    AddFinding(result, L"Python block body must be indented relative to its header.");
                }
                break;
            }
            if (!foundBody) {
                blockBodyOk = false;
                AddFinding(result, L"Python block header is missing a visible body.");
            }
        }
    }

    result.topLevelClassVerified = (!sawStudent || result.errorMessage.find(L"class Student") == std::wstring::npos) &&
                                   (!sawCourse || result.errorMessage.find(L"class Course") == std::wstring::npos);
    result.topLevelExecutionVerified = !sawKnownExecution || result.errorMessage.find(L"Top-level execution") == std::wstring::npos;
    result.functionBodyIndentVerified = (!checkedBlockBody || blockBodyOk) && pythonMethodScopeOk;
    result.classCourseNotNestedInStudent = !sawCourse || result.errorMessage.find(L"class Course") == std::wstring::npos;
    result.receiverBindingVerified = receiverBindingOk;
    result.runSuccessIgnoredForStructure = runSucceeded && !result.findings.empty();
    return result.findings.empty();
}

}  // namespace

TextInputVerificationResult verify_code_structure(const TextInputVerificationOptions& options) {
    TextInputVerificationResult result;
    result.ok = false;

    if (options.clipboardUsed) {
        result.clipboardRejected = true;
        result.errorCode = L"BLOCKED_CLIPBOARD_USED_FOR_CODE_INPUT";
        result.errorMessage = L"Clipboard input cannot satisfy real keyboard structured text verification.";
        return result;
    }
    if (options.backendFileWriteUsed) {
        result.backendWriteRejected = true;
        result.errorCode = L"BLOCKED_BACKEND_FILE_WRITE_USED_FOR_CODE_INPUT";
        result.errorMessage = L"Backend file writes cannot satisfy visible text input verification.";
        return result;
    }

    std::wstring text = options.visibleTextAvailable && !options.observedText.empty() ? options.observedText : options.expectedText;
    if (!IsCodeKind(options.inputKind) || !options.verifyStructure) {
        result.ok = true;
        return result;
    }

    IndentationOptions indent;
    std::vector<StructuredCodeLine> structuredLines = parse_code_lines(text, indent);
    LanguageScopeModelResult languageScope = AnalyzeLanguageScope(structuredLines, indent);
    result.language = languageScope.language;
    result.languageScopeVerified = languageScope.ok;
    result.functionNotNestedInMain = languageScope.functionNotNestedInMain;
    result.mainNotNestedInFunction = languageScope.mainNotNestedInFunction;
    result.includeImportTopLevelVerified = languageScope.includeImportTopLevelVerified;
    result.classScopeVerified = languageScope.classScopeVerified;
    result.receiverBindingVerified = true;
    result.duplicateReceiverTokenDetected = Contains(text, L"selfself") || Contains(text, L"self_self") || Contains(text, L"thisself");
    result.selfselfPresent = Contains(text, L"selfself");
    if (result.duplicateReceiverTokenDetected) {
        AddFinding(result, L"Duplicated or malformed receiver token is forbidden in structured code input.");
        result.errorCode = L"BLOCKED_DUPLICATED_RECEIVER_TOKEN";
        result.receiverBindingVerified = false;
        return result;
    }

    if (!languageScope.ok) {
        for (const auto& finding : languageScope.findings) {
            AddFinding(result, finding);
        }
        if (options.runSucceeded) {
            result.errorCode = L"BLOCKED_CODE_STRUCTURE_INVALID_DESPITE_RUN_SUCCESS";
            result.runSuccessIgnoredForStructure = true;
        }
        return result;
    }

    if (LooksLikePython(text)) {
        result.ok = VerifyPython(text, options.runSucceeded, result);
        result.codeStructureVerified = result.ok;
        if (!result.ok && options.runSucceeded) {
            result.errorCode = L"BLOCKED_CODE_STRUCTURE_INVALID_DESPITE_RUN_SUCCESS";
        }
        return result;
    }

    result.ok = true;
    result.codeStructureVerified = true;
    result.topLevelClassVerified = true;
    result.topLevelExecutionVerified = true;
    result.functionBodyIndentVerified = true;
    result.classCourseNotNestedInStudent = true;
    result.languageScopeVerified = true;
    result.receiverBindingVerified = true;
    return result;
}

TextInputVerificationResult VerifyTextInputStructure(const TextInputVerificationOptions& options) {
    return verify_code_structure(options);
}

std::wstring TextInputVerificationResultJson(const TextInputVerificationResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"code_structure_verified\":" + simplejson::Bool(result.codeStructureVerified);
    json += L",\"top_level_class_verified\":" + simplejson::Bool(result.topLevelClassVerified);
    json += L",\"top_level_execution_verified\":" + simplejson::Bool(result.topLevelExecutionVerified);
    json += L",\"function_body_indent_verified\":" + simplejson::Bool(result.functionBodyIndentVerified);
    json += L",\"class_course_not_nested_in_student\":" + simplejson::Bool(result.classCourseNotNestedInStudent);
    json += L",\"language\":" + simplejson::Quote(result.language);
    json += L",\"language_scope_verified\":" + simplejson::Bool(result.languageScopeVerified);
    json += L",\"function_not_nested_in_main\":" + simplejson::Bool(result.functionNotNestedInMain);
    json += L",\"main_not_nested_in_function\":" + simplejson::Bool(result.mainNotNestedInFunction);
    json += L",\"include_import_top_level_verified\":" + simplejson::Bool(result.includeImportTopLevelVerified);
    json += L",\"class_scope_verified\":" + simplejson::Bool(result.classScopeVerified);
    json += L",\"receiver_binding_verified\":" + simplejson::Bool(result.receiverBindingVerified);
    json += L",\"duplicate_receiver_token_detected\":" + simplejson::Bool(result.duplicateReceiverTokenDetected);
    json += L",\"invalid_python_method_receiver\":" + simplejson::Bool(result.invalidPythonMethodReceiver);
    json += L",\"selfself_present\":" + simplejson::Bool(result.selfselfPresent);
    json += L",\"run_success_ignored_for_structure\":" + simplejson::Bool(result.runSuccessIgnoredForStructure);
    json += L",\"clipboard_rejected\":" + simplejson::Bool(result.clipboardRejected);
    json += L",\"backend_write_rejected\":" + simplejson::Bool(result.backendWriteRejected);
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
