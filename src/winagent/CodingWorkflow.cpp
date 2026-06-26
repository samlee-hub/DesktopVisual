#include "CodingWorkflow.h"

#include "CaseRunner.h"
#include "FormSemantics.h"
#include "ReportWriter.h"

#include <algorithm>
#include <cwctype>
#include <sstream>

namespace {

std::wstring JsonEscapeLocal(const std::wstring& value) {
    std::wstring out;
    for (wchar_t ch : value) {
        switch (ch) {
        case L'\\': out += L"\\\\"; break;
        case L'"': out += L"\\\""; break;
        case L'\n': out += L"\\n"; break;
        case L'\r': out += L"\\r"; break;
        case L'\t': out += L"\\t"; break;
        default: out += ch; break;
        }
    }
    return out;
}

std::wstring JsonStringLocal(const std::wstring& value) {
    return L"\"" + JsonEscapeLocal(value) + L"\"";
}

std::wstring ToLowerLocal(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsLocal(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerLocal(haystack).find(ToLowerLocal(needle)) != std::wstring::npos;
}

std::wstring TrimLocal(const std::wstring& value) {
    size_t start = 0;
    while (start < value.size() && iswspace(value[start])) ++start;
    size_t end = value.size();
    while (end > start && iswspace(value[end - 1])) --end;
    return value.substr(start, end - start);
}

std::wstring CollapseWhitespace(const std::wstring& value) {
    std::wstring out;
    bool previousSpace = false;
    for (wchar_t ch : value) {
        bool space = iswspace(ch) != 0;
        if (space) {
            if (!previousSpace) out += L' ';
        } else {
            out += ch;
        }
        previousSpace = space;
    }
    return TrimLocal(out);
}

std::wstring StripTags(const std::wstring& value) {
    std::wstring out;
    bool inTag = false;
    for (size_t i = 0; i < value.size(); ++i) {
        wchar_t ch = value[i];
        if (ch == L'<') {
            wchar_t next = (i + 1 < value.size()) ? value[i + 1] : L'\0';
            if ((next >= L'a' && next <= L'z') || (next >= L'A' && next <= L'Z') ||
                next == L'/' || next == L'!' || next == L'?') {
                inTag = true;
                out += L' ';
                continue;
            }
        }
        if (ch == L'>') {
            inTag = false;
            out += L' ';
            continue;
        }
        if (!inTag) out += ch;
    }
    return CollapseWhitespace(out);
}

std::wstring LimitSummary(const std::wstring& value, size_t maxChars = 220) {
    std::wstring clean = CollapseWhitespace(value);
    if (clean.size() <= maxChars) return clean;
    return clean.substr(0, maxChars) + L"...";
}

std::wstring ExtractAttrAnywhere(const std::wstring& html, const std::wstring& attrName) {
    std::wstring lower = ToLowerLocal(html);
    std::wstring key = ToLowerLocal(attrName) + L"=";
    size_t pos = lower.find(key);
    if (pos == std::wstring::npos) return L"";
    pos += key.size();
    if (pos >= html.size()) return L"";
    wchar_t quote = html[pos];
    if (quote != L'"' && quote != L'\'') return L"";
    ++pos;
    size_t end = html.find(quote, pos);
    if (end == std::wstring::npos) return L"";
    return html.substr(pos, end - pos);
}

std::wstring ExtractFirstTagText(const std::wstring& html, const std::wstring& tagName) {
    std::wstring lower = ToLowerLocal(html);
    std::wstring open = L"<" + ToLowerLocal(tagName);
    size_t pos = lower.find(open);
    if (pos == std::wstring::npos) return L"";
    size_t tagEnd = lower.find(L">", pos);
    if (tagEnd == std::wstring::npos) return L"";
    std::wstring close = L"</" + ToLowerLocal(tagName) + L">";
    size_t closePos = lower.find(close, tagEnd);
    if (closePos == std::wstring::npos) return L"";
    return StripTags(html.substr(tagEnd + 1, closePos - tagEnd - 1));
}

std::wstring ExtractElementById(const std::wstring& html, const std::wstring& id) {
    std::wstring lower = ToLowerLocal(html);
    std::wstring needle1 = L"id=\"" + ToLowerLocal(id) + L"\"";
    std::wstring needle2 = L"id='" + ToLowerLocal(id) + L"'";
    size_t idPos = lower.find(needle1);
    if (idPos == std::wstring::npos) idPos = lower.find(needle2);
    if (idPos == std::wstring::npos) return L"";
    size_t tagStart = lower.rfind(L"<", idPos);
    size_t tagEnd = lower.find(L">", idPos);
    if (tagStart == std::wstring::npos || tagEnd == std::wstring::npos) return L"";
    size_t nameStart = tagStart + 1;
    while (nameStart < tagEnd && iswspace(lower[nameStart])) ++nameStart;
    size_t nameEnd = nameStart;
    while (nameEnd < tagEnd && !iswspace(lower[nameEnd]) && lower[nameEnd] != L'>') ++nameEnd;
    std::wstring tagName = lower.substr(nameStart, nameEnd - nameStart);
    std::wstring close = L"</" + tagName + L">";
    size_t closePos = lower.find(close, tagEnd);
    if (closePos == std::wstring::npos) return L"";
    return StripTags(html.substr(tagEnd + 1, closePos - tagEnd - 1));
}

std::wstring ResultStateFromText(const std::wstring& text) {
    std::wstring explicitState = ExtractAttrAnywhere(text, L"data-result");
    std::wstring state = ToLowerLocal(explicitState);
    if (state == L"compile_error") return L"COMPILE_ERROR";
    if (state == L"runtime_error") return L"RUNTIME_ERROR";
    if (state == L"wrong_answer") return L"WRONG_ANSWER";
    if (state == L"time_limit") return L"TIME_LIMIT";
    if (state == L"sample_pass") return L"SAMPLE_PASS";
    if (state == L"accepted") return L"ACCEPTED";

    if (ContainsLocal(text, L"compile error") || ContainsLocal(text, L"compilation error")) return L"COMPILE_ERROR";
    if (ContainsLocal(text, L"runtime error")) return L"RUNTIME_ERROR";
    if (ContainsLocal(text, L"wrong answer")) return L"WRONG_ANSWER";
    if (ContainsLocal(text, L"time limit")) return L"TIME_LIMIT";
    if (ContainsLocal(text, L"sample pass") || ContainsLocal(text, L"samples passed")) return L"SAMPLE_PASS";
    if (ContainsLocal(text, L"accepted")) return L"ACCEPTED";
    return L"UNKNOWN_RESULT";
}

bool LooksLikeLoginOrPassword(const std::wstring& text) {
    return ContainsLocal(text, L"login") || ContainsLocal(text, L"sign in") ||
           ContainsLocal(text, L"signin") || ContainsLocal(text, L"password") ||
           ContainsLocal(text, L"credential") || ContainsLocal(text, L"passcode");
}

bool LooksLikeCaptcha(const std::wstring& text) {
    return ContainsLocal(text, L"captcha") || ContainsLocal(text, L"recaptcha") ||
           ContainsLocal(text, L"hcaptcha") || ContainsLocal(text, L"prove you are human");
}

bool LooksLikeAntiAutomation(const std::wstring& text) {
    return ContainsLocal(text, L"bot detection") || ContainsLocal(text, L"anti-automation") ||
           ContainsLocal(text, L"automation detected") || ContainsLocal(text, L"ai detection");
}

std::wstring CodeSummary(const CodingWorkflowInput& input) {
    if (!input.codePath.empty()) return L"code_path=" + input.codePath;
    size_t lines = input.codeText.empty() ? 0 : 1;
    for (wchar_t ch : input.codeText) {
        if (ch == L'\n') ++lines;
    }
    return L"code_length=" + std::to_wstring(input.codeText.size()) + L"; lines=" + std::to_wstring(lines);
}

bool HasCodeEditor(const FormControlsResult& page) {
    for (const FormControl& control : page.controls) {
        if (control.controlType == L"code_editor") return true;
    }
    const std::wstring& raw = page.rawContent;
    return ContainsLocal(raw, L"monaco-editor") || ContainsLocal(raw, L"codemirror") ||
           ContainsLocal(raw, L"data-control-type=\"code_editor\"") ||
           ContainsLocal(raw, L"data-control-type='code_editor'");
}

bool HasRunButton(const FormControlsResult& page) {
    for (const FormControl& control : page.controls) {
        std::wstring text = control.fieldId + L" " + control.label;
        if ((control.controlType == L"button" || control.controlType == L"link") &&
            (ContainsLocal(text, L"run code") || ContainsLocal(text, L"run"))) {
            return true;
        }
    }
    return ContainsLocal(page.rawContent, L"data-action=\"run\"") ||
           ContainsLocal(page.rawContent, L"data-action='run'");
}

}  // namespace

CodingWorkflowEvalResult EvaluateCodingWorkflow(const CodingWorkflowInput& input) {
    CodingWorkflowEvalResult result;
    CodingWorkflowContext& ctx = result.context;
    CodingWorkflowRecord& rec = result.record;

    rec.timestamp = CurrentTimestamp();
    rec.action = input.action.empty() ? L"read_problem" : input.action;
    rec.source = L"user_goal";
    rec.revisionCount = input.revisionCount;
    rec.codeSummary = CodeSummary(input);
    rec.codePath = input.codePath;
    rec.safetyCheckResult = L"ok";
    rec.submitClicked = false;
    rec.submitBasis = input.allowSubmit ? L"allow_submit=true" : L"default_stop_before_submit";

    ctx.language = input.language;
    ctx.submitAllowed = input.allowSubmit;
    ctx.resultState = L"UNKNOWN_RESULT";

    if (input.userGoal.empty()) {
        result.errorCode = L"USER_TAKEOVER_REQUIRED";
        result.errorMessage = L"Coding workflow requires an explicit user goal.";
        rec.reason = L"No explicit user goal was provided.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }

    FormControlsResult page = LoadFormControlsFromHtml(input.htmlPath);
    if (!page.ok) {
        result.errorCode = page.errorCode.empty() ? L"FILE_READ_FAILED" : page.errorCode;
        result.errorMessage = page.errorMessage.empty() ? L"Could not read coding workflow page." : page.errorMessage;
        rec.reason = L"Could not read local coding workflow context.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }

    ctx.problemTitle = ExtractAttrAnywhere(page.rawContent, L"data-problem-title");
    if (ctx.problemTitle.empty()) ctx.problemTitle = ExtractFirstTagText(page.rawContent, L"h1");
    ctx.problemStatementSummary = ExtractAttrAnywhere(page.rawContent, L"data-problem-statement");
    if (ctx.problemStatementSummary.empty()) ctx.problemStatementSummary = ExtractElementById(page.rawContent, L"problem_statement");
    if (ctx.problemStatementSummary.empty()) ctx.problemStatementSummary = ExtractElementById(page.rawContent, L"problem-statement");
    ctx.examplesSummary = ExtractAttrAnywhere(page.rawContent, L"data-examples");
    if (ctx.examplesSummary.empty()) ctx.examplesSummary = ExtractElementById(page.rawContent, L"examples");
    ctx.constraintsSummary = ExtractAttrAnywhere(page.rawContent, L"data-constraints");
    if (ctx.constraintsSummary.empty()) ctx.constraintsSummary = ExtractElementById(page.rawContent, L"constraints");
    ctx.problemStatementSummary = LimitSummary(ctx.problemStatementSummary);
    ctx.examplesSummary = LimitSummary(ctx.examplesSummary);
    ctx.constraintsSummary = LimitSummary(ctx.constraintsSummary);
    ctx.editorDetected = HasCodeEditor(page);
    ctx.runButtonDetected = HasRunButton(page);
    ctx.resultState = ResultStateFromText(page.rawContent);

    if (LooksLikeCaptcha(page.rawContent)) {
        result.errorCode = L"CAPTCHA_DETECTED";
        result.errorMessage = L"Captcha or human-verification content was detected.";
        rec.reason = L"Captcha/challenge detected; bypass is not supported.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }
    if (LooksLikeLoginOrPassword(page.rawContent)) {
        result.errorCode = L"USER_TAKEOVER_REQUIRED";
        result.errorMessage = L"Login/password content was detected; user takeover required.";
        rec.reason = L"Login or password content detected.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }
    if (LooksLikeAntiAutomation(page.rawContent)) {
        result.errorCode = L"ANTI_AUTOMATION_DETECTED";
        result.errorMessage = L"Anti-automation / AI-detection content was detected.";
        rec.reason = L"Anti-automation content detected; bypass is not supported.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }
    if ((rec.action == L"input_code" || rec.action == L"run_code" ||
         rec.action == L"revise_code" || rec.action == L"submit_if_explicitly_allowed") &&
        !ctx.editorDetected) {
        result.errorCode = L"LOCATOR_NOT_FOUND";
        result.errorMessage = L"Code editor could not be reliably identified.";
        rec.reason = L"Code editor detection failed.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }

    if ((rec.action == L"run_code" || rec.action == L"submit_if_explicitly_allowed") && !ctx.runButtonDetected) {
        result.errorCode = L"LOCATOR_NOT_FOUND";
        result.errorMessage = L"Run Code control could not be reliably identified.";
        rec.reason = L"Run Code button detection failed.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }

    if (rec.action == L"submit_if_explicitly_allowed") {
        if (!input.allowSubmit) {
            result.errorCode = L"USER_TAKEOVER_REQUIRED";
            result.errorMessage = L"Submit is not explicitly allowed; stop before submit.";
            rec.reason = L"Submit requires allow_submit=true.";
            rec.safetyCheckResult = result.errorCode;
            return result;
        }
        rec.submitClicked = true;
        rec.submitBasis = L"allow_submit=true";
    }

    if (rec.action == L"stop_before_submit") {
        rec.submitClicked = false;
        rec.submitBasis = L"default_stop_before_submit";
    }

    rec.reason = L"Coding workflow action recorded from explicit user goal over local page context.";
    result.ok = true;
    return result;
}

std::wstring CodingWorkflowContextJson(const CodingWorkflowContext& context) {
    std::wstringstream out;
    out << L"{\"problem_title\":" << JsonStringLocal(context.problemTitle)
        << L",\"problem_statement_summary\":" << JsonStringLocal(context.problemStatementSummary)
        << L",\"examples_summary\":" << JsonStringLocal(context.examplesSummary)
        << L",\"constraints_summary\":" << JsonStringLocal(context.constraintsSummary)
        << L",\"language\":" << JsonStringLocal(context.language)
        << L",\"editor_detected\":" << (context.editorDetected ? L"true" : L"false")
        << L",\"run_button_detected\":" << (context.runButtonDetected ? L"true" : L"false")
        << L",\"submit_allowed\":" << (context.submitAllowed ? L"true" : L"false")
        << L",\"result_state\":" << JsonStringLocal(context.resultState)
        << L"}";
    return out.str();
}

std::wstring CodingWorkflowRecordJson(const CodingWorkflowRecord& record) {
    std::wstringstream out;
    out << L"{\"action\":" << JsonStringLocal(record.action)
        << L",\"source\":" << JsonStringLocal(record.source)
        << L",\"reason\":" << JsonStringLocal(record.reason)
        << L",\"code_summary\":" << JsonStringLocal(record.codeSummary)
        << L",\"code_path\":" << JsonStringLocal(record.codePath)
        << L",\"revision_count\":" << record.revisionCount
        << L",\"submit_clicked\":" << (record.submitClicked ? L"true" : L"false")
        << L",\"submit_basis\":" << JsonStringLocal(record.submitBasis)
        << L",\"safety_check_result\":" << JsonStringLocal(record.safetyCheckResult)
        << L",\"timestamp\":" << JsonStringLocal(record.timestamp)
        << L"}";
    return out.str();
}
