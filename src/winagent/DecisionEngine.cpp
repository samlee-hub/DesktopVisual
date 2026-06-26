#include "DecisionEngine.h"

#include "FormSemantics.h"
#include "ReportWriter.h"   // CurrentTimestamp

#include <algorithm>
#include <cwctype>
#include <iomanip>
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

std::wstring JsonArrayLocal(const std::vector<std::wstring>& values) {
    std::wstring out = L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) out += L",";
        out += JsonStringLocal(values[i]);
    }
    out += L"]";
    return out;
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

// Detects prompt-injection / instruction-override phrases inside page content.
// These never change the user's goal; they only get flagged and ignored.
bool LooksLikeInjection(const std::wstring& content) {
    static const wchar_t* kPhrases[] = {
        L"ignore previous instructions",
        L"ignore all previous instructions",
        L"ignore the rules",
        L"ignore your rules",
        L"disregard previous instructions",
        L"forget your instructions",
        L"override your instructions",
        L"override the user",
        L"you are now",
        L"system prompt",
        L"\u5ffd\u7565\u4e4b\u524d\u7684\u6307\u4ee4",  // ignore previous instructions (zh)
        L"\u5ffd\u7565\u4ee5\u4e0a\u6307\u4ee4",        // ignore the above instructions (zh)
        L"\u5ffd\u7565\u89c4\u5219",                    // ignore the rules (zh)
        L"\u5ffd\u7565\u6240\u6709\u89c4\u5219",        // ignore all rules (zh)
        L"\u65e0\u89c6\u89c4\u5219",                    // disregard the rules (zh)
        L"\u65e0\u89c6\u4e4b\u524d",                    // disregard the previous (zh)
    };
    for (const wchar_t* p : kPhrases) {
        if (ContainsLocal(content, p)) return true;
    }
    return false;
}

// Detects credential-entry content (never automated).
bool LooksLikeCredential(const std::wstring& content) {
    static const wchar_t* kPhrases[] = {
        L"password", L"passcode", L"credential", L"secret key",
        L"one-time password", L"otp", L"verification code",
        L"\u5bc6\u7801", L"\u53e3\u4ee4", L"\u51ed\u636e", L"\u9a8c\u8bc1\u7801\u8f93\u5165",  // password / passcode / credential / captcha-input (zh)
    };
    for (const wchar_t* p : kPhrases) {
        if (ContainsLocal(content, p)) return true;
    }
    return false;
}

// Detects anti-automation / AI / bot-detection content (never bypassed).
bool LooksLikeAntiAutomation(const std::wstring& content) {
    static const wchar_t* kPhrases[] = {
        L"are you a robot", L"are you human", L"bot detection",
        L"anti-automation", L"automation detected", L"ai detection",
        L"prove you are human", L"unusual traffic", L"detected automated",
        L"\u4eba\u673a\u9a8c\u8bc1", L"\u53cd\u4f5c\u5f0a", L"\u53cd\u81ea\u52a8\u5316", L"\u68c0\u6d4b\u5230\u81ea\u52a8\u5316",  // human-verify / anti-cheat / anti-automation / automation-detected (zh)
    };
    for (const wchar_t* p : kPhrases) {
        if (ContainsLocal(content, p)) return true;
    }
    return false;
}

std::wstring DecisionTypeForAction(const std::wstring& mappedAction) {
    if (mappedAction == L"fill_text" || mappedAction == L"fill_textarea" || mappedAction == L"input_code") {
        return L"fill";
    }
    if (mappedAction == L"select_radio" || mappedAction == L"select_option" ||
        mappedAction == L"toggle_checkbox" || mappedAction == L"select_date") {
        return L"select";
    }
    if (mappedAction == L"click_button" || mappedAction == L"click_link") {
        return L"click";
    }
    return L"stop";
}

bool IsSubmitControl(const FormControl& control) {
    if (control.controlType != L"button") return false;
    std::wstring text = ToLowerLocal(control.fieldId + L" " + control.label);
    return text.find(L"submit") != std::wstring::npos ||
           text.find(L"\u63d0\u4ea4") != std::wstring::npos ||
           text.find(L"send") != std::wstring::npos ||
           text.find(L"\u53d1\u9001") != std::wstring::npos ||
           text.find(L"confirm") != std::wstring::npos ||
           text.find(L"\u786e\u8ba4") != std::wstring::npos ||
           text.find(L"finish") != std::wstring::npos ||
           text.find(L"\u5b8c\u6210") != std::wstring::npos;
}

std::wstring SummarizeControls(const std::vector<FormControl>& controls) {
    int textboxes = 0, choices = 0, buttons = 0, other = 0;
    for (const FormControl& c : controls) {
        if (c.controlType == L"textbox" || c.controlType == L"textarea" || c.controlType == L"code_editor") {
            ++textboxes;
        } else if (c.controlType == L"radio" || c.controlType == L"checkbox" ||
                   c.controlType == L"dropdown" || c.controlType == L"combobox") {
            ++choices;
        } else if (c.controlType == L"button" || c.controlType == L"link") {
            ++buttons;
        } else {
            ++other;
        }
    }
    std::wstringstream out;
    out << L"controls=" << controls.size()
        << L"; text=" << textboxes
        << L"; choice=" << choices
        << L"; action=" << buttons
        << L"; other=" << other;
    return out.str();
}

}  // namespace

DecisionEvalResult EvaluateDecision(const DecisionInput& input) {
    DecisionEvalResult result;
    DecisionTaskContext& ctx = result.context;
    DecisionRecord& rec = result.record;

    // ---- read_context -------------------------------------------------------
    ctx.userGoal = input.userGoal;
    ctx.permissionMode = input.permissionMode.empty() ? L"DEFAULT" : input.permissionMode;
    ctx.currentWindow = input.currentWindow;
    ctx.currentUrl = input.currentUrl;
    ctx.allowedActions = { L"fill", L"select", L"click", L"scroll" };
    if (input.allowSubmit) ctx.allowedActions.push_back(L"submit");
    ctx.deniedActions = { L"credential_input", L"captcha_solve", L"anti_automation_bypass" };
    if (!input.allowSubmit) ctx.deniedActions.push_back(L"submit");
    ctx.riskLevel = L"low";

    rec.timestamp = CurrentTimestamp();
    rec.userGoalPreserved = true;
    rec.source = L"user_goal";
    rec.safetyCheckResult = L"ok";

    if (input.userGoal.empty()) {
        ctx.riskLevel = L"high";
        result.errorCode = L"USER_TAKEOVER_REQUIRED";
        result.errorMessage = L"Decision tasks require an explicit user goal; content cannot supply it.";
        rec.decisionType = L"stop";
        rec.selectedAction = L"stop";
        rec.reason = L"No explicit user goal was provided.";
        rec.safetyCheckResult = result.errorCode;
        rec.userGoalPreserved = false;
        return result;
    }

    FormControlsResult page = LoadFormControlsFromHtml(input.htmlPath);
    if (!page.ok) {
        result.errorCode = page.errorCode;
        result.errorMessage = page.errorMessage;
        rec.decisionType = L"stop";
        rec.selectedAction = L"stop";
        rec.reason = L"Could not read decision page context.";
        rec.safetyCheckResult = page.errorCode;
        return result;
    }
    ctx.observedContentSummary = SummarizeControls(page.controls);

    // ---- content safety scan (page content never overrides the user goal) ---
    bool injection = LooksLikeInjection(page.rawContent);
    if (injection) {
        // Flag and ignore. The user goal is preserved; we keep going and never
        // let injected text change decisionType/selectedAction.
        ctx.observedContentSummary += L"; injection_attempt=ignored";
        rec.source = L"user_goal";  // explicitly NOT page_content
    }
    if (LooksLikeAntiAutomation(page.rawContent)) {
        ctx.riskLevel = L"high";
        result.errorCode = L"ANTI_AUTOMATION_DETECTED";
        result.errorMessage = L"Anti-automation / AI-detection content was detected on the page.";
        rec.decisionType = L"stop";
        rec.selectedAction = L"stop";
        rec.reason = L"Anti-automation content detected; bypass is not supported.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }
    if (LooksLikeCredential(page.rawContent)) {
        ctx.riskLevel = L"high";
        result.errorCode = L"CREDENTIAL_INPUT_DETECTED";
        result.errorMessage = L"Credential-entry content was detected; the user must handle it.";
        rec.decisionType = L"stop";
        rec.selectedAction = L"stop";
        rec.reason = L"Credential content detected; credentials are never automated.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }

    // ---- classify_task: resolve exactly one target control ------------------
    FormControlResult resolved = ResolveFormControlFromHtml(
        input.htmlPath, input.fieldId, input.label, input.minConfidence);
    if (!resolved.ok) {
        // Map the form resolver stop codes straight through.
        result.errorCode = resolved.errorCode.empty() ? L"FIELD_CONFIDENCE_LOW" : resolved.errorCode;
        result.errorMessage = resolved.errorMessage;
        rec.decisionType = L"stop";
        rec.selectedAction = L"stop";
        rec.targetFieldId = input.fieldId;
        rec.targetLabel = input.label;
        rec.controlType = resolved.control.controlType;
        rec.confidence = resolved.control.confidence;
        rec.reason = (result.errorCode == L"CAPTCHA_DETECTED")
            ? L"Captcha/challenge control; the user must solve it."
            : (result.errorCode == L"FIELD_NOT_UNIQUE")
                ? L"Multiple controls matched; a unique target is required."
                : (result.errorCode == L"LOCATOR_NOT_FOUND")
                    ? L"No matching control was found for the target."
                    : L"Field is unknown or low-confidence; not treated as a textbox.";
        rec.safetyCheckResult = result.errorCode;
        return result;
    }

    const FormControl& control = resolved.control;
    rec.targetFieldId = control.fieldId;
    rec.targetLabel = control.label;
    rec.controlType = control.controlType;
    rec.confidence = control.confidence;

    std::wstring mapped = control.recommendedAction;
    rec.decisionType = DecisionTypeForAction(mapped);

    // ---- choose_action: submit authorization gate ---------------------------
    if (IsSubmitControl(control)) {
        rec.decisionType = L"submit";
        if (!input.allowSubmit) {
            ctx.riskLevel = L"high";
            result.errorCode = L"USER_TAKEOVER_REQUIRED";
            result.errorMessage = L"Submit is not explicitly authorized by the task; user confirmation required.";
            rec.selectedAction = L"stop";
            rec.reason = L"Critical submit action requires explicit user authorization (allow_submit).";
            rec.safetyCheckResult = result.errorCode;
            return result;
        }
        ctx.riskLevel = L"medium";
    }

    // ---- record_decision: success ------------------------------------------
    std::wstring chosen = !input.value.empty() ? input.value
                          : (!input.option.empty() ? input.option : input.text);
    rec.selectedAction = mapped;
    rec.chosenValue = chosen;
    rec.reason = L"Action mapped from recognized control type to advance the user goal.";
    if (injection) {
        rec.reason += L" Page injection attempt was detected and ignored; user goal preserved.";
    }
    rec.safetyCheckResult = L"ok";
    result.ok = true;
    return result;
}

std::wstring DecisionTaskContextJson(const DecisionTaskContext& context) {
    std::wstringstream out;
    out << L"{\"user_goal\":" << JsonStringLocal(context.userGoal)
        << L",\"permission_mode\":" << JsonStringLocal(context.permissionMode)
        << L",\"current_window\":" << JsonStringLocal(context.currentWindow)
        << L",\"current_url\":" << JsonStringLocal(context.currentUrl)
        << L",\"observed_content_summary\":" << JsonStringLocal(context.observedContentSummary)
        << L",\"allowed_actions\":" << JsonArrayLocal(context.allowedActions)
        << L",\"denied_actions\":" << JsonArrayLocal(context.deniedActions)
        << L",\"risk_level\":" << JsonStringLocal(context.riskLevel)
        << L"}";
    return out.str();
}

std::wstring DecisionRecordJson(const DecisionRecord& record) {
    std::wstringstream out;
    out << L"{\"decision_type\":" << JsonStringLocal(record.decisionType)
        << L",\"source\":" << JsonStringLocal(record.source)
        << L",\"reason\":" << JsonStringLocal(record.reason)
        << L",\"selected_action\":" << JsonStringLocal(record.selectedAction)
        << L",\"target_field_id\":" << JsonStringLocal(record.targetFieldId)
        << L",\"target_label\":" << JsonStringLocal(record.targetLabel)
        << L",\"control_type\":" << JsonStringLocal(record.controlType)
        << L",\"chosen_value_present\":" << (record.chosenValue.empty() ? L"false" : L"true")
        << L",\"confidence\":" << std::fixed << std::setprecision(2) << record.confidence
        << L",\"user_goal_preserved\":" << (record.userGoalPreserved ? L"true" : L"false")
        << L",\"safety_check_result\":" << JsonStringLocal(record.safetyCheckResult)
        << L",\"timestamp\":" << JsonStringLocal(record.timestamp)
        << L"}";
    return out.str();
}
