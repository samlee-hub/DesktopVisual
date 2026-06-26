#include "IncrementalCodeInputVerifier.h"

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

void AddFinding(IncrementalCodeInputVerifierResult& result, const std::wstring& finding) {
    result.ok = false;
    result.findings.push_back(finding);
    if (result.errorCode.empty()) {
        result.errorCode = L"STRUCTURED_CODE_INPUT_PLAN_INVALID";
        result.errorMessage = finding;
    }
}

int CountChar(const std::wstring& value, wchar_t target) {
    int count = 0;
    for (wchar_t ch : value) {
        if (ch == target) ++count;
    }
    return count;
}

bool HasBalancedSimpleDelimiters(const std::vector<StructuredCodeLine>& lines) {
    int paren = 0;
    int bracket = 0;
    int brace = 0;
    for (const auto& line : lines) {
        for (wchar_t ch : line.contentWithoutIndent) {
            if (ch == L'(') ++paren;
            if (ch == L')') --paren;
            if (ch == L'[') ++bracket;
            if (ch == L']') --bracket;
            if (ch == L'{') ++brace;
            if (ch == L'}') --brace;
            if (paren < 0 || bracket < 0 || brace < 0) return false;
        }
    }
    return paren == 0 && bracket == 0 && brace == 0;
}

bool PythonDefHasSelfWhenMethod(const StructuredCodeLine& line) {
    std::wstring trimmed = Trim(line.contentWithoutIndent);
    if (!StartsWith(trimmed, L"def ")) return true;
    if (line.targetIndentSpaces <= 0) return true;
    size_t open = trimmed.find(L'(');
    size_t close = trimmed.find(L')', open == std::wstring::npos ? 0 : open + 1);
    if (open == std::wstring::npos || close == std::wstring::npos || close <= open + 1) return false;
    std::wstring args = Trim(trimmed.substr(open + 1, close - open - 1));
    return StartsWith(args, L"self") || StartsWith(args, L"cls");
}

}  // namespace

IncrementalCodeInputVerifierResult VerifyIncrementalCodeInputPlan(const CodeWritePlanResult& plan) {
    IncrementalCodeInputVerifierResult result;
    result.scopeStructureVerified = plan.languageScope.ok;
    result.noRetryContamination = true;
    result.tokenStructureVerified = true;
    result.balancedDelimiterVerified = HasBalancedSimpleDelimiters(plan.lines);

    if (!plan.ok) {
        for (const auto& finding : plan.findings) {
            AddFinding(result, finding);
        }
    }
    if (!result.balancedDelimiterVerified) {
        AddFinding(result, L"Code delimiters are not balanced before visible typing.");
    }

    for (const auto& line : plan.lines) {
        std::wstring trimmed = Trim(line.contentWithoutIndent);
        if (Contains(trimmed, L")class ") || Contains(trimmed, L"selfself") || Contains(trimmed, L"setfsetf")) {
            result.noRetryContamination = false;
            AddFinding(result, L"Retry contamination marker found in planned code.");
        }
        if (plan.language == L"python" && StartsWith(trimmed, L"def ")) {
            if (trimmed.empty() || trimmed.back() != L':') {
                result.tokenStructureVerified = false;
                AddFinding(result, L"Python def line must end with ':' before visible typing.");
            }
            if (!PythonDefHasSelfWhenMethod(line)) {
                result.pythonMethodSelfVerified = false;
                AddFinding(result, L"Python class methods must include self or cls in the planned method signature.");
            }
        }
    }

    result.scopeStructureVerified = result.scopeStructureVerified && result.ok;
    result.tokenStructureVerified = result.tokenStructureVerified && result.ok;
    return result;
}

std::wstring IncrementalCodeInputVerifierResultJson(const IncrementalCodeInputVerifierResult& result) {
    std::wstring json = L"{";
    json += L"\"ok\":" + simplejson::Bool(result.ok);
    json += L",\"incremental_code_input_verifier\":" + simplejson::Bool(result.incrementalCodeInputVerifier);
    json += L",\"token_structure_verified\":" + simplejson::Bool(result.tokenStructureVerified);
    json += L",\"scope_structure_verified\":" + simplejson::Bool(result.scopeStructureVerified);
    json += L",\"no_retry_contamination\":" + simplejson::Bool(result.noRetryContamination);
    json += L",\"python_method_self_verified\":" + simplejson::Bool(result.pythonMethodSelfVerified);
    json += L",\"balanced_delimiter_verified\":" + simplejson::Bool(result.balancedDelimiterVerified);
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
