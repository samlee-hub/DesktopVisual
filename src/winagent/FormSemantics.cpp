#include "FormSemantics.h"

#include "CaseRunner.h"

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

std::wstring ToLowerLocal(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsLocal(const std::wstring& haystack, const std::wstring& needle) {
    return ToLowerLocal(haystack).find(ToLowerLocal(needle)) != std::wstring::npos;
}

std::wstring TrimLocal(const std::wstring& value) {
    size_t start = 0;
    while (start < value.size() && iswspace(value[start])) ++start;
    size_t end = value.size();
    while (end > start && iswspace(value[end - 1])) --end;
    return value.substr(start, end - start);
}

std::wstring StripTags(std::wstring value) {
    std::wstring out;
    bool inTag = false;
    for (wchar_t ch : value) {
        if (ch == L'<') {
            inTag = true;
            continue;
        }
        if (ch == L'>') {
            inTag = false;
            continue;
        }
        if (!inTag) out += ch;
    }
    return TrimLocal(out);
}

std::wstring AttrValue(const std::wstring& tag, const std::wstring& name) {
    std::wstring lower = ToLowerLocal(tag);
    std::wstring key = ToLowerLocal(name) + L"=";
    size_t pos = lower.find(key);
    if (pos == std::wstring::npos) return L"";
    pos += key.size();
    if (pos >= tag.size()) return L"";
    wchar_t quote = tag[pos];
    if (quote == L'"' || quote == L'\'') {
        ++pos;
        size_t end = tag.find(quote, pos);
        if (end == std::wstring::npos) return L"";
        return tag.substr(pos, end - pos);
    }
    size_t end = pos;
    while (end < tag.size() && !iswspace(tag[end]) && tag[end] != L'>') ++end;
    return tag.substr(pos, end - pos);
}

bool HasAttr(const std::wstring& tag, const std::wstring& name) {
    return !AttrValue(tag, name).empty() || ContainsLocal(tag, L" " + name) || ContainsLocal(tag, L"<" + name);
}

std::wstring LabelFor(const std::wstring& html, const std::wstring& id) {
    if (id.empty()) return L"";
    std::wstring lower = ToLowerLocal(html);
    std::wstring needle1 = L"<label";
    size_t pos = 0;
    while ((pos = lower.find(needle1, pos)) != std::wstring::npos) {
        size_t tagEnd = lower.find(L">", pos);
        if (tagEnd == std::wstring::npos) break;
        std::wstring tag = html.substr(pos, tagEnd - pos + 1);
        if (ToLowerLocal(AttrValue(tag, L"for")) == ToLowerLocal(id)) {
            size_t close = lower.find(L"</label>", tagEnd);
            if (close == std::wstring::npos) return L"";
            return StripTags(html.substr(tagEnd + 1, close - tagEnd - 1));
        }
        pos = tagEnd + 1;
    }
    return L"";
}

std::vector<std::wstring> ParseSelectOptions(const std::wstring& body) {
    std::vector<std::wstring> options;
    std::wstring lower = ToLowerLocal(body);
    size_t pos = 0;
    while ((pos = lower.find(L"<option", pos)) != std::wstring::npos) {
        size_t tagEnd = lower.find(L">", pos);
        if (tagEnd == std::wstring::npos) break;
        size_t close = lower.find(L"</option>", tagEnd);
        std::wstring tag = body.substr(pos, tagEnd - pos + 1);
        std::wstring value = AttrValue(tag, L"value");
        if (close != std::wstring::npos) {
            std::wstring text = StripTags(body.substr(tagEnd + 1, close - tagEnd - 1));
            if (!text.empty()) value = value.empty() ? text : value + L":" + text;
            pos = close + 9;
        } else {
            pos = tagEnd + 1;
        }
        if (!value.empty()) options.push_back(value);
    }
    return options;
}

FormControl MakeControl(const std::wstring& html, const std::wstring& tag, const std::wstring& body, const std::wstring& tagName) {
    FormControl c;
    std::wstring inputType = ToLowerLocal(AttrValue(tag, L"type"));
    c.fieldId = (inputType == L"radio") ? AttrValue(tag, L"name") : AttrValue(tag, L"id");
    if (c.fieldId.empty()) c.fieldId = AttrValue(tag, L"name");
    c.label = AttrValue(tag, L"data-label");
    if (c.label.empty()) c.label = AttrValue(tag, L"aria-label");
    if (c.label.empty()) c.label = LabelFor(html, AttrValue(tag, L"id"));
    c.required = HasAttr(tag, L"required");
    c.source = L"dom_like_visual_hints";
    c.confidence = 0.90;

    std::wstring forced = ToLowerLocal(AttrValue(tag, L"data-control-type"));
    std::wstring className = ToLowerLocal(AttrValue(tag, L"class"));
    std::wstring text = tag + L" " + body + L" " + c.fieldId + L" " + c.label + L" " + forced + L" " + className;

    if (forced == L"captcha" || forced == L"challenge" || ContainsLocal(text, L"captcha") || ContainsLocal(text, L"challenge")) {
        c.controlType = L"captcha/challenge";
        c.confidence = 0.99;
    } else if (forced == L"code_editor" || ContainsLocal(className, L"code")) {
        c.controlType = L"code_editor";
        c.confidence = 0.93;
    } else if (tagName == L"textarea") {
        c.controlType = L"textarea";
        c.confidence = 0.92;
    } else if (tagName == L"select") {
        c.controlType = L"dropdown";
        c.options = ParseSelectOptions(body);
        c.confidence = 0.94;
    } else if (tagName == L"button") {
        c.controlType = L"button";
        if (c.label.empty()) c.label = StripTags(body);
        c.confidence = 0.94;
    } else if (tagName == L"a") {
        c.controlType = L"link";
        if (c.label.empty()) c.label = StripTags(body);
        c.confidence = 0.90;
    } else if (tagName == L"input") {
        if (inputType == L"radio") c.controlType = L"radio";
        else if (inputType == L"checkbox") c.controlType = L"checkbox";
        else if (inputType == L"date") c.controlType = L"date_picker";
        else if (inputType == L"file") c.controlType = L"file_upload";
        else c.controlType = L"textbox";
        c.confidence = 0.94;
        std::wstring value = AttrValue(tag, L"value");
        if (!value.empty()) c.options.push_back(value);
    } else {
        c.controlType = L"unknown";
        c.confidence = 0.40;
    }
    c.recommendedAction = RecommendedFormAction(c.controlType);
    return c;
}

void AppendTagControls(const std::wstring& html, const std::wstring& tagName, bool hasClosingTag, std::vector<FormControl>& controls) {
    std::wstring lower = ToLowerLocal(html);
    std::wstring open = L"<" + tagName;
    std::wstring close = L"</" + tagName + L">";
    size_t pos = 0;
    while ((pos = lower.find(open, pos)) != std::wstring::npos) {
        size_t tagEnd = lower.find(L">", pos);
        if (tagEnd == std::wstring::npos) break;
        std::wstring tag = html.substr(pos, tagEnd - pos + 1);
        std::wstring body;
        size_t next = tagEnd + 1;
        if (hasClosingTag) {
            size_t closePos = lower.find(close, tagEnd);
            if (closePos != std::wstring::npos) {
                body = html.substr(tagEnd + 1, closePos - tagEnd - 1);
                next = closePos + close.size();
            }
        }
        controls.push_back(MakeControl(html, tag, body, tagName));
        pos = next;
    }
}

std::vector<FormControl> ParseHtmlControls(const std::wstring& html) {
    std::vector<FormControl> controls;
    AppendTagControls(html, L"input", false, controls);
    AppendTagControls(html, L"textarea", true, controls);
    AppendTagControls(html, L"select", true, controls);
    AppendTagControls(html, L"button", true, controls);
    AppendTagControls(html, L"a", true, controls);
    AppendTagControls(html, L"div", true, controls);
    return controls;
}

FormControl AggregateRadioGroup(const std::vector<FormControl>& matches) {
    FormControl c = matches.front();
    c.options.clear();
    c.label = L"";
    for (const FormControl& m : matches) {
        for (const std::wstring& option : m.options) {
            if (!option.empty()) c.options.push_back(option);
        }
        if (!m.label.empty()) {
            if (!c.label.empty()) c.label += L"; ";
            c.label += m.label;
        }
    }
    c.fieldId = matches.front().fieldId;
    c.controlType = L"radio";
    c.recommendedAction = RecommendedFormAction(c.controlType);
    c.confidence = 0.94;
    return c;
}

}

std::wstring RecommendedFormAction(const std::wstring& controlType) {
    if (controlType == L"textbox") return L"fill_text";
    if (controlType == L"textarea") return L"fill_textarea";
    if (controlType == L"radio") return L"select_radio";
    if (controlType == L"checkbox") return L"toggle_checkbox";
    if (controlType == L"dropdown" || controlType == L"combobox") return L"select_option";
    if (controlType == L"button") return L"click_button";
    if (controlType == L"link") return L"click_link";
    if (controlType == L"date_picker") return L"select_date";
    if (controlType == L"file_upload") return L"select_file";
    if (controlType == L"code_editor") return L"input_code";
    if (controlType == L"captcha/challenge" || controlType == L"captcha" || controlType == L"challenge") return L"stop";
    return L"stop";
}

std::wstring FormControlJson(const FormControl& control) {
    std::wstringstream out;
    out << L"{\"field_id\":" << JsonStringLocal(control.fieldId)
        << L",\"label\":" << JsonStringLocal(control.label)
        << L",\"control_type\":" << JsonStringLocal(control.controlType)
        << L",\"required\":" << (control.required ? L"true" : L"false")
        << L",\"options\":[";
    for (size_t i = 0; i < control.options.size(); ++i) {
        if (i != 0) out << L",";
        out << JsonStringLocal(control.options[i]);
    }
    out << L"],\"rect\":{\"left\":" << control.rect.left
        << L",\"top\":" << control.rect.top
        << L",\"right\":" << control.rect.right
        << L",\"bottom\":" << control.rect.bottom
        << L"},\"source\":" << JsonStringLocal(control.source)
        << L",\"confidence\":" << std::fixed << std::setprecision(2) << control.confidence
        << L",\"recommended_action\":" << JsonStringLocal(control.recommendedAction)
        << L"}";
    return out.str();
}

std::wstring FormControlCandidatesJson(const std::vector<FormControl>& controls) {
    std::wstringstream out;
    out << L"[";
    for (size_t i = 0; i < controls.size(); ++i) {
        if (i != 0) out << L",";
        out << FormControlJson(controls[i]);
    }
    out << L"]";
    return out.str();
}

FormControlResult ResolveFormControlFromHtml(
    const std::wstring& htmlPath,
    const std::wstring& fieldId,
    const std::wstring& label,
    double minConfidence) {
    FormControlResult result;
    FileReadResult file = ReadTextFile(htmlPath);
    if (!file.ok) {
        result.errorCode = file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode;
        result.errorMessage = file.error.empty() ? L"Could not read HTML form source." : file.error;
        return result;
    }
    std::vector<FormControl> controls = ParseHtmlControls(file.content);
    std::vector<FormControl> matches;
    std::wstring fieldLower = ToLowerLocal(fieldId);
    std::wstring labelLower = ToLowerLocal(label);
    for (const FormControl& c : controls) {
        if (!fieldId.empty()) {
            if (ToLowerLocal(c.fieldId) == fieldLower || ToLowerLocal(c.label) == fieldLower) {
                matches.push_back(c);
            }
        } else if (!label.empty()) {
            if (ToLowerLocal(c.label) == labelLower) {
                matches.push_back(c);
            }
        }
    }

    result.matchedBy = !fieldId.empty() ? L"field_id" : L"label";
    result.matchCount = static_cast<int>(matches.size());
    result.candidates = matches;
    if (matches.empty()) {
        result.errorCode = L"LOCATOR_NOT_FOUND";
        result.errorMessage = L"No matching form control was found.";
        return result;
    }

    bool allRadio = true;
    std::wstring radioKey = matches.front().fieldId;
    for (const FormControl& m : matches) {
        allRadio = allRadio && m.controlType == L"radio";
    }
    if (allRadio && !matches.empty() && !fieldId.empty()) {
        FormControl grouped = AggregateRadioGroup(matches);
        grouped.fieldId = fieldId;
        matches.clear();
        matches.push_back(grouped);
    }

    if (matches.size() > 1) {
        result.matchCount = static_cast<int>(matches.size());
        result.candidates = matches;
        result.errorCode = L"FIELD_NOT_UNIQUE";
        result.errorMessage = L"Form control query matched multiple fields.";
        return result;
    }

    result.control = matches.front();
    result.matchCount = 1;
    result.candidates = matches;
    if (result.control.controlType == L"captcha/challenge" || result.control.recommendedAction == L"stop") {
        result.errorCode = result.control.controlType == L"captcha/challenge" ? L"CAPTCHA_DETECTED" : L"FIELD_CONFIDENCE_LOW";
        result.errorMessage = result.control.controlType == L"captcha/challenge"
            ? L"Captcha or challenge control was detected."
            : L"Form control is unknown or requires user confirmation.";
        return result;
    }
    if (result.control.confidence < minConfidence || result.control.controlType == L"unknown") {
        result.errorCode = L"FIELD_CONFIDENCE_LOW";
        result.errorMessage = L"Form control confidence is too low for automatic action.";
        return result;
    }
    result.ok = true;
    return result;
}

FormControlsResult LoadFormControlsFromHtml(const std::wstring& htmlPath) {
    FormControlsResult result;
    FileReadResult file = ReadTextFile(htmlPath);
    if (!file.ok) {
        result.errorCode = file.errorCode.empty() ? L"FILE_READ_FAILED" : file.errorCode;
        result.errorMessage = file.error.empty() ? L"Could not read HTML form source." : file.error;
        return result;
    }
    result.rawContent = file.content;
    result.controls = ParseHtmlControls(file.content);
    result.ok = true;
    return result;
}
