#include "PreInputCodeStructureVerifier.h"

#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>
#include <map>
#include <set>

namespace {

bool StartsWith(const std::wstring& value, const std::wstring& prefix) {
    return value.rfind(prefix, 0) == 0;
}

bool Contains(const std::wstring& value, const std::wstring& needle) {
    return value.find(needle) != std::wstring::npos;
}

std::wstring Trim(const std::wstring& value) {
    size_t first = 0;
    while (first < value.size() && std::iswspace(value[first])) ++first;
    size_t last = value.size();
    while (last > first && std::iswspace(value[last - 1])) --last;
    return value.substr(first, last - first);
}

bool IdentifierChar(wchar_t ch) {
    return std::iswalnum(ch) || ch == L'_';
}

std::wstring ExtractCallObject(const std::wstring& statement) {
    size_t dot = statement.find(L'.');
    if (dot == std::wstring::npos || dot == 0) return L"";
    size_t start = dot;
    while (start > 0 && IdentifierChar(statement[start - 1])) --start;
    if (dot <= start) return L"";
    return statement.substr(start, dot - start);
}

std::wstring ExtractCallMethod(const std::wstring& statement) {
    size_t dot = statement.find(L'.');
    if (dot == std::wstring::npos) return L"";
    size_t open = statement.find(L'(', dot + 1);
    if (open == std::wstring::npos || open <= dot + 1) return L"";
    return Trim(statement.substr(dot + 1, open - dot - 1));
}

bool ExtractPythonConstructorAssignment(const std::wstring& statement, std::wstring& variable, std::wstring& className) {
    size_t equals = statement.find(L'=');
    if (equals == std::wstring::npos || equals == 0) return false;
    variable = Trim(statement.substr(0, equals));
    std::wstring rhs = Trim(statement.substr(equals + 1));
    size_t open = rhs.find(L'(');
    if (open == std::wstring::npos || open == 0) return false;
    className = Trim(rhs.substr(0, open));
    if (variable.empty() || className.empty()) return false;
    return std::all_of(variable.begin(), variable.end(), IdentifierChar) &&
           std::all_of(className.begin(), className.end(), IdentifierChar);
}

bool IsKnownPythonInstanceMethod(const std::wstring& name) {
    return name == L"__init__" || name == L"introduce" || name == L"show_title";
}

bool IsSuspiciousReceiverToken(const std::wstring& token) {
    std::wstring lower = token;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return lower == L"selfself" ||
           lower == L"self self" ||
           lower == L"self_self" ||
           lower == L"thisself" ||
           lower == L"selfthis" ||
           lower == L"clscls" ||
           (lower.size() > 4 && StartsWith(lower, L"self") && lower != L"self") ||
           (lower.size() > 3 && StartsWith(lower, L"cls") && lower != L"cls");
}

void AddFinding(PreInputCodeStructureVerifierResult& result, const std::wstring& finding) {
    result.ok = false;
    result.preInputCodeStructureVerified = false;
    result.findings.push_back(finding);
    if (result.errorCode.empty()) {
        result.errorCode = L"BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID";
        result.errorMessage = finding;
    }
}

void VerifyPythonPlan(const CodeWritePlanResult& plan, PreInputCodeStructureVerifierResult& result) {
    std::map<std::wstring, std::set<std::wstring>> classMethods;
    for (const auto& cls : plan.classes) {
        if (cls.targetIndentSpaces != 0) {
            result.classMethodScopeVerified = false;
            AddFinding(result, L"Python class declarations must be planned at file scope before visible typing.");
        }
        for (const auto& method : cls.methods) {
            classMethods[cls.name].insert(method.name);
            if (IsSuspiciousReceiverToken(method.receiverToken)) {
                result.receiverBindingVerified = false;
                result.duplicateReceiverTokenDetected = true;
                result.selfselfPresent = result.selfselfPresent || method.receiverToken == L"selfself";
                AddFinding(result, L"Python method receiver token must be exact; duplicated receiver tokens are forbidden before visible typing.");
            }
            if (!method.hasReceiver) {
                result.classMethodScopeVerified = false;
                result.receiverBindingVerified = false;
                AddFinding(result, L"Python class methods must include self or cls before visible typing.");
            }
        }
    }

    for (const auto& fn : plan.topLevelFunctions) {
        if (fn.hasReceiver || IsKnownPythonInstanceMethod(fn.name)) {
            result.classMethodScopeVerified = false;
            result.receiverBindingVerified = false;
            AddFinding(result, L"Python instance methods must be declared inside their owning class before visible typing.");
        }
        if (IsSuspiciousReceiverToken(fn.receiverToken)) {
            result.receiverBindingVerified = false;
            result.duplicateReceiverTokenDetected = true;
            result.selfselfPresent = result.selfselfPresent || fn.receiverToken == L"selfself";
            AddFinding(result, L"Python top-level receiver token is duplicated or malformed before visible typing.");
        }
    }

    std::map<std::wstring, std::wstring> variableTypes;
    for (const auto& statement : plan.topLevelStatements) {
        if (statement.targetIndentSpaces != 0) {
            result.topLevelStatementScopeVerified = false;
            AddFinding(result, L"Python top-level statements must be planned at file scope before visible typing.");
        }
        std::wstring variable;
        std::wstring className;
        if (ExtractPythonConstructorAssignment(statement.text, variable, className)) {
            variableTypes[variable] = className;
        }
    }

    for (const auto& statement : plan.topLevelStatements) {
        if (!Contains(statement.text, L".") || !Contains(statement.text, L"(")) continue;
        std::wstring object = ExtractCallObject(statement.text);
        std::wstring method = ExtractCallMethod(statement.text);
        if (object.empty() || method.empty()) continue;
        auto varIt = variableTypes.find(object);
        if (varIt == variableTypes.end()) continue;
        auto classIt = classMethods.find(varIt->second);
        if (classIt == classMethods.end() || classIt->second.find(method) == classIt->second.end()) {
            result.instanceMethodCallVerified = false;
            AddFinding(result, L"Python instance method calls must target methods declared on the constructed class before visible typing.");
        }
    }
}

}  // namespace

PreInputCodeStructureVerifierResult VerifyPreInputCodeStructure(const CodeWritePlanResult& plan, bool verifyStructure) {
    PreInputCodeStructureVerifierResult result;
    result.ok = true;
    result.codeWritePlanVerified = plan.ok && plan.codeWritePlan;
    result.languageScopeModelVerified = plan.languageScope.ok && plan.languageScope.languageScopeModel;

    if (!verifyStructure) {
        result.preInputCodeStructureVerified = true;
        return result;
    }

    if (!result.codeWritePlanVerified) {
        for (const auto& finding : plan.findings) {
            AddFinding(result, finding);
        }
        if (plan.findings.empty()) {
            AddFinding(result, L"Code write plan failed before visible typing.");
        }
    }

    if (!result.languageScopeModelVerified) {
        for (const auto& finding : plan.languageScope.findings) {
            AddFinding(result, finding);
        }
        if (plan.languageScope.findings.empty()) {
            AddFinding(result, L"Language scope model failed before visible typing.");
        }
    }

    TextInputVerificationOptions verify;
    verify.inputKind = L"code_editor_text";
    verify.expectedText = plan.sourceText;
    verify.verifyStructure = true;
    verify.clipboardUsed = false;
    verify.backendFileWriteUsed = false;
    verify.inputMethod = L"real_keyboard_events";
    result.textVerification = VerifyTextInputStructure(verify);
    result.receiverBindingVerified = result.textVerification.receiverBindingVerified;
    result.duplicateReceiverTokenDetected = result.textVerification.duplicateReceiverTokenDetected;
    result.selfselfPresent = result.textVerification.selfselfPresent;
    if (!result.textVerification.ok) {
        for (const auto& finding : result.textVerification.findings) {
            AddFinding(result, finding);
        }
        if (result.textVerification.findings.empty()) {
            AddFinding(result, result.textVerification.errorMessage.empty()
                                   ? L"Text input structure verification failed before visible typing."
                                   : result.textVerification.errorMessage);
        }
    }

    if (plan.language == L"python") {
        VerifyPythonPlan(plan, result);
    }

    if (result.ok) {
        result.preInputCodeStructureVerified = true;
        result.errorCode.clear();
        result.errorMessage.clear();
    } else if (result.errorCode.empty()) {
        result.errorCode = L"BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID";
        result.errorMessage = L"Pre-input code structure validation failed.";
    }
    return result;
}

std::wstring PreInputCodeStructureVerifierResultJson(const PreInputCodeStructureVerifierResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"pre_input_code_structure_verifier\":" + simplejson::Bool(result.preInputCodeStructureVerifier);
    json += L",\"pre_input_code_structure_verified\":" + simplejson::Bool(result.preInputCodeStructureVerified);
    json += L",\"code_write_plan_verified\":" + simplejson::Bool(result.codeWritePlanVerified);
    json += L",\"language_scope_model_verified\":" + simplejson::Bool(result.languageScopeModelVerified);
    json += L",\"class_method_scope_verified\":" + simplejson::Bool(result.classMethodScopeVerified);
    json += L",\"instance_method_call_verified\":" + simplejson::Bool(result.instanceMethodCallVerified);
    json += L",\"top_level_statement_scope_verified\":" + simplejson::Bool(result.topLevelStatementScopeVerified);
    json += L",\"receiver_binding_verified\":" + simplejson::Bool(result.receiverBindingVerified);
    json += L",\"duplicate_receiver_token_detected\":" + simplejson::Bool(result.duplicateReceiverTokenDetected);
    json += L",\"selfself_present\":" + simplejson::Bool(result.selfselfPresent);
    json += L",\"error_code\":" + simplejson::Quote(result.errorCode);
    json += L",\"error_message\":" + simplejson::Quote(result.errorMessage);
    json += L",\"text_verification\":" + TextInputVerificationResultJson(result.textVerification);
    json += L",\"findings\":[";
    for (size_t i = 0; i < result.findings.size(); ++i) {
        if (i) json += L",";
        json += simplejson::Quote(result.findings[i]);
    }
    json += L"]}";
    return json;
}
