#include "WebFormFieldLocator.h"

#include "SimpleJson.h"

#include <algorithm>
#include <cwctype>
#include <iomanip>
#include <sstream>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

bool EqualsInsensitive(const std::wstring& left, const std::wstring& right) {
    if (left.empty() || right.empty()) return false;
    return Lower(left) == Lower(right);
}

bool RectValid(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

POINT Center(const RECT& rect) {
    POINT p{};
    p.x = rect.left + (rect.right - rect.left) / 2;
    p.y = rect.top + (rect.bottom - rect.top) / 2;
    return p;
}

std::wstring ElementText(const UiaElementInfo& e) {
    return e.name + L" " + e.value + L" " + e.automationId + L" " + e.className + L" " + e.controlType;
}

bool IsFieldRole(const UiaElementInfo& e) {
    return e.controlType == L"Edit" ||
           e.controlType == L"ComboBox" ||
           e.controlType == L"Document" ||
           e.controlType == L"Custom";
}

bool IsSubmitRole(const UiaElementInfo& e) {
    return e.controlType == L"Button" || e.controlType == L"Hyperlink" || e.controlType == L"Text";
}

double ScoreField(const UiaElementInfo& e, const WebFormFieldLocatorRequest& r, std::wstring& source) {
    std::wstring text = ElementText(e);
    double score = 0.0;
    if (!r.fieldLabel.empty() && (EqualsInsensitive(e.name, r.fieldLabel) || EqualsInsensitive(e.automationId, r.fieldLabel))) {
        score = 0.98;
        source = L"uia_label_exact";
    } else if (!r.placeholder.empty() && ContainsInsensitive(text, r.placeholder)) {
        score = 0.94;
        source = L"placeholder_text";
    } else if (!r.fieldId.empty() && ContainsInsensitive(text, r.fieldId)) {
        score = 0.92;
        source = L"field_id_or_name";
    } else if (!r.name.empty() && ContainsInsensitive(text, r.name)) {
        score = 0.90;
        source = L"name_attribute_like";
    } else if (!r.title.empty() && ContainsInsensitive(text, r.title)) {
        score = 0.88;
        source = L"title_like_visible_summary";
    } else if (!r.fieldLabel.empty() && ContainsInsensitive(text, r.fieldLabel)) {
        score = 0.86;
        source = L"label_text_contains";
    }
    if (score > 0.0 && r.expectedRole == L"textarea" && e.controlType == L"Document") score += 0.02;
    if (score > 0.0 && e.offscreen) score -= 0.30;
    if (score > 0.0 && !RectValid(e.rect)) score -= 0.25;
    return score;
}

double NearbyAssociationScore(const UiaElementInfo& label, const UiaElementInfo& field) {
    if (!RectValid(label.rect) || !RectValid(field.rect)) return 0.0;
    LONG labelMidY = label.rect.top + (label.rect.bottom - label.rect.top) / 2;
    LONG fieldMidY = field.rect.top + (field.rect.bottom - field.rect.top) / 2;
    bool sameRow = std::abs(labelMidY - fieldMidY) <= 48 && field.rect.left >= label.rect.left;
    bool below = field.rect.top >= label.rect.bottom && field.rect.top - label.rect.bottom <= 80;
    if (sameRow) return 0.84;
    if (below) return 0.78;
    return 0.0;
}

WebFormFieldLocatorResult Failure(const WebFormFieldLocatorRequest& request, const std::wstring& code, const std::wstring& message, bool missing, bool ambiguous, const std::vector<UiaElementInfo>& candidates) {
    WebFormFieldLocatorResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.fieldId = request.fieldId;
    result.fieldLabel = request.fieldLabel;
    result.ambiguous = ambiguous;
    result.missing = missing;
    result.candidates = candidates;
    return result;
}

std::wstring RectJson(const RECT& rect) {
    return L"{\"left\":" + std::to_wstring(rect.left) +
        L",\"top\":" + std::to_wstring(rect.top) +
        L",\"right\":" + std::to_wstring(rect.right) +
        L",\"bottom\":" + std::to_wstring(rect.bottom) + L"}";
}

std::wstring CandidatesJson(const std::vector<UiaElementInfo>& candidates) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < candidates.size(); ++i) {
        if (i) json << L",";
        json << L"{\"name\":" << simplejson::Quote(candidates[i].name)
             << L",\"value\":" << simplejson::Quote(candidates[i].value)
             << L",\"role\":" << simplejson::Quote(candidates[i].controlType)
             << L",\"automation_id\":" << simplejson::Quote(candidates[i].automationId)
             << L",\"rect\":" << RectJson(candidates[i].rect)
             << L",\"offscreen\":" << simplejson::Bool(candidates[i].offscreen)
             << L"}";
    }
    json << L"]";
    return json.str();
}

}  // namespace

WebFormFieldLocatorRequest WebFormFieldLocatorRequestFromSpec(const BrowserWorkflowFieldSpec& field) {
    WebFormFieldLocatorRequest request;
    request.fieldId = field.fieldId;
    request.fieldLabel = field.fieldLabel;
    request.placeholder = field.placeholder;
    request.name = field.name;
    request.title = field.title;
    request.expectedRole = field.expectedRole.empty() ? L"Edit" : field.expectedRole;
    return request;
}

WebFormFieldLocatorResult LocateWebFormField(HWND hwnd, const WebFormFieldLocatorRequest& request) {
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) {
        return Failure(request, tree.errorCode.empty() ? L"UIA_TREE_FAILED" : tree.errorCode, tree.errorMessage, true, false, {});
    }

    struct Scored {
        UiaElementInfo element;
        double score = 0.0;
        std::wstring source;
    };
    std::vector<Scored> scored;
    std::vector<UiaElementInfo> labels;
    for (const auto& element : tree.elements) {
        if (element.offscreen || !RectValid(element.rect)) continue;
        if (!request.fieldLabel.empty() && ContainsInsensitive(ElementText(element), request.fieldLabel)) {
            labels.push_back(element);
        }
        if (!IsFieldRole(element)) continue;
        std::wstring source;
        double score = ScoreField(element, request, source);
        if (score > 0.0) {
            scored.push_back({element, score, source});
        }
    }

    if (scored.empty() && !labels.empty()) {
        for (const auto& label : labels) {
            for (const auto& element : tree.elements) {
                if (element.offscreen || !RectValid(element.rect) || !IsFieldRole(element)) continue;
                double score = NearbyAssociationScore(label, element);
                if (score > 0.0) {
                    scored.push_back({element, score, L"nearby_text_to_field"});
                }
            }
        }
    }

    std::sort(scored.begin(), scored.end(), [](const Scored& a, const Scored& b) {
        return a.score > b.score;
    });
    std::vector<UiaElementInfo> candidates;
    for (const auto& item : scored) candidates.push_back(item.element);
    if (scored.empty()) {
        return Failure(request, L"FAIL_FIELD_NOT_FOUND", L"Web form field was not found from UIA/visible text.", true, false, candidates);
    }
    if (scored.size() > 1 && (scored[0].score - scored[1].score) < 0.05) {
        return Failure(request, L"STOP_TARGET_NOT_UNIQUE", L"Web form field locator matched multiple equivalent candidates.", false, true, candidates);
    }

    WebFormFieldLocatorResult result;
    result.ok = true;
    result.fieldId = request.fieldId;
    result.fieldLabel = request.fieldLabel;
    result.fieldRole = scored[0].element.controlType;
    result.targetRect = scored[0].element.rect;
    result.targetCenter = Center(scored[0].element.rect);
    result.locatorSource = scored[0].source;
    result.confidence = scored[0].score;
    result.requiresRuntimeValidation = true;
    result.coordinateSourceType = L"runtime_locator";
    result.candidates = candidates;
    return result;
}

WebFormFieldLocatorResult LocateWebFormSubmit(HWND hwnd, const std::wstring& label) {
    WebFormFieldLocatorRequest request;
    request.fieldLabel = label.empty() ? L"Submit" : label;
    request.expectedRole = L"Button";
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) {
        return Failure(request, tree.errorCode.empty() ? L"UIA_TREE_FAILED" : tree.errorCode, tree.errorMessage, true, false, {});
    }
    std::vector<UiaElementInfo> matches;
    for (const auto& element : tree.elements) {
        if (element.offscreen || !RectValid(element.rect) || !IsSubmitRole(element)) continue;
        if (ContainsInsensitive(ElementText(element), request.fieldLabel)) {
            matches.push_back(element);
        }
    }
    if (matches.empty()) {
        return Failure(request, L"FAIL_FIELD_NOT_FOUND", L"Submit button was not found from UIA/visible text.", true, false, matches);
    }
    if (matches.size() > 1) {
        return Failure(request, L"STOP_TARGET_NOT_UNIQUE", L"Submit button locator matched multiple candidates.", false, true, matches);
    }
    WebFormFieldLocatorResult result;
    result.ok = true;
    result.fieldLabel = request.fieldLabel;
    result.fieldRole = matches[0].controlType;
    result.targetRect = matches[0].rect;
    result.targetCenter = Center(matches[0].rect);
    result.locatorSource = L"visible_submit_text";
    result.confidence = 0.94;
    result.requiresRuntimeValidation = true;
    result.coordinateSourceType = L"runtime_locator";
    result.candidates = matches;
    return result;
}

std::wstring WebFormFieldLocatorResultJson(const WebFormFieldLocatorResult& result) {
    std::wstringstream json;
    json << L"{\"ok\":" << simplejson::Bool(result.ok)
         << L",\"error_code\":" << simplejson::Quote(result.errorCode)
         << L",\"error_message\":" << simplejson::Quote(result.errorMessage)
         << L",\"field_id\":" << simplejson::Quote(result.fieldId)
         << L",\"field_label\":" << simplejson::Quote(result.fieldLabel)
         << L",\"field_role\":" << simplejson::Quote(result.fieldRole)
         << L",\"target_rect\":" << RectJson(result.targetRect)
         << L",\"target_center\":{\"x\":" << result.targetCenter.x << L",\"y\":" << result.targetCenter.y << L"}"
         << L",\"locator_source\":" << simplejson::Quote(result.locatorSource)
         << L",\"confidence\":" << std::fixed << std::setprecision(2) << result.confidence
         << L",\"ambiguous\":" << simplejson::Bool(result.ambiguous)
         << L",\"missing\":" << simplejson::Bool(result.missing)
         << L",\"requires_runtime_validation\":" << simplejson::Bool(result.requiresRuntimeValidation)
         << L",\"coordinate_source_type\":" << simplejson::Quote(result.coordinateSourceType)
         << L",\"candidates\":" << CandidatesJson(result.candidates)
         << L"}";
    return json.str();
}
