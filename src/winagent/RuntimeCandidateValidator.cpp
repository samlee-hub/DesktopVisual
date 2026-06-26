#include "RuntimeCandidateValidator.h"

#include "SimpleJson.h"
#include "Trace.h"

#include <algorithm>
#include <cwctype>
#include <iomanip>
#include <set>
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

bool TextMatches(const std::wstring& haystack, const std::wstring& label) {
    if (label.empty()) return false;
    return ContainsInsensitive(haystack, label);
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& value) {
    if (value.empty()) return;
    if (std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

std::wstring BoolJson(bool value) {
    return value ? L"true" : L"false";
}

std::wstring NumberJson(double value) {
    std::wstringstream stream;
    stream << std::setprecision(12) << value;
    return stream.str();
}

std::wstring RectJson(const RECT& rect) {
    std::wstringstream json;
    json << L"{\"left\":" << rect.left
         << L",\"top\":" << rect.top
         << L",\"right\":" << rect.right
         << L",\"bottom\":" << rect.bottom
         << L"}";
    return json.str();
}

bool ReadRect(const simplejson::Value* value, RECT& rect) {
    if (!value || !value->IsObject()) return false;
    if (simplejson::Has(*value, L"left") &&
        simplejson::Has(*value, L"top") &&
        simplejson::Has(*value, L"right") &&
        simplejson::Has(*value, L"bottom")) {
        rect.left = simplejson::GetInt(*value, L"left", 0);
        rect.top = simplejson::GetInt(*value, L"top", 0);
        rect.right = simplejson::GetInt(*value, L"right", 0);
        rect.bottom = simplejson::GetInt(*value, L"bottom", 0);
        return true;
    }
    if (simplejson::Has(*value, L"x") &&
        simplejson::Has(*value, L"y") &&
        simplejson::Has(*value, L"width") &&
        simplejson::Has(*value, L"height")) {
        rect.left = simplejson::GetInt(*value, L"x", 0);
        rect.top = simplejson::GetInt(*value, L"y", 0);
        rect.right = rect.left + simplejson::GetInt(*value, L"width", 0);
        rect.bottom = rect.top + simplejson::GetInt(*value, L"height", 0);
        return true;
    }
    return false;
}

bool RectValid(const RECT& rect) {
    return rect.right > rect.left && rect.bottom > rect.top;
}

int RectWidth(const RECT& rect) {
    return rect.right - rect.left;
}

int RectHeight(const RECT& rect) {
    return rect.bottom - rect.top;
}

bool RectInside(const RECT& inner, const RECT& outer) {
    return RectValid(inner) && RectValid(outer) &&
        inner.left >= outer.left &&
        inner.top >= outer.top &&
        inner.right <= outer.right &&
        inner.bottom <= outer.bottom;
}

bool RectIntersects(const RECT& a, const RECT& b) {
    return RectValid(a) && RectValid(b) &&
        a.left < b.right && a.right > b.left &&
        a.top < b.bottom && a.bottom > b.top;
}

RECT OffsetRectCopy(const RECT& rect, int dx, int dy) {
    RECT mapped = rect;
    mapped.left += dx;
    mapped.right += dx;
    mapped.top += dy;
    mapped.bottom += dy;
    return mapped;
}

void FlattenJsonText(const simplejson::Value& value, std::wstring& out) {
    if (value.IsString()) {
        out += L" ";
        out += value.stringValue;
        return;
    }
    if (value.IsArray()) {
        for (const auto& item : value.arrayValue) FlattenJsonText(item, out);
        return;
    }
    if (value.IsObject()) {
        for (const auto& entry : value.objectValue) {
            out += L" ";
            out += entry.first;
            FlattenJsonText(entry.second, out);
        }
    }
}

std::wstring FlattenOptional(const simplejson::Value& root, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(root, key);
    if (!value) return L"";
    std::wstring text;
    FlattenJsonText(*value, text);
    return text;
}

bool IsBlockedRiskText(const std::wstring& text) {
    return ContainsInsensitive(text, L"captcha") ||
        ContainsInsensitive(text, L"recaptcha") ||
        ContainsInsensitive(text, L"hcaptcha") ||
        ContainsInsensitive(text, L"turnstile") ||
        ContainsInsensitive(text, L"human verification") ||
        ContainsInsensitive(text, L"bot challenge") ||
        ContainsInsensitive(text, L"automation detected") ||
        ContainsInsensitive(text, L"script detection") ||
        ContainsInsensitive(text, L"anti-cheat") ||
        ContainsInsensitive(text, L"anti cheat");
}

bool IsCredentialRiskText(const std::wstring& text) {
    return ContainsInsensitive(text, L"password") ||
        ContainsInsensitive(text, L"credential") ||
        ContainsInsensitive(text, L"one-time code") ||
        ContainsInsensitive(text, L"verification code") ||
        ContainsInsensitive(text, L"security code");
}

bool RoleSupported(const std::wstring& role) {
    if (role.empty()) return false;
    const std::wstring normalized = Lower(role);
    return normalized == L"button" ||
        normalized == L"edit" ||
        normalized == L"text" ||
        normalized == L"hyperlink" ||
        normalized == L"link" ||
        normalized == L"menuitem" ||
        normalized == L"listitem" ||
        normalized == L"checkbox" ||
        normalized == L"combobox" ||
        normalized == L"document" ||
        normalized == L"pane";
}

std::wstring MethodJson(
    bool uia,
    bool ocr,
    bool context,
    bool elementSummary,
    bool roi) {
    std::vector<std::wstring> methods = {L"approx_region_window_mapping"};
    if (roi) methods.push_back(L"roi_check");
    if (uia) methods.push_back(L"uia_text");
    if (ocr) methods.push_back(L"ocr_text");
    if (elementSummary) methods.push_back(L"element_summary");
    if (context) methods.push_back(L"expected_context");
    std::wstringstream value;
    for (size_t i = 0; i < methods.size(); ++i) {
        if (i) value << L"+";
        value << methods[i];
    }
    return value.str();
}

struct RequestContext {
    bool ok = false;
    bool activeProtection = false;
    bool credentialRequired = false;
    bool staleObserve = false;
    bool hasWindowBounds = false;
    bool hasScreenBounds = false;
    bool hasRoi = false;
    RECT windowBounds = {};
    RECT screenBounds = {};
    RECT roi = {};
    RECT clientViewport = {};
    std::wstring screenshotPath;
    std::wstring uiaSummary;
    std::wstring ocrSummary;
    std::wstring elementSummary;
    std::wstring expectedContext;
};

RequestContext BuildRequestContext(const simplejson::Value& request, const RuntimeCandidateValidationOptions& options) {
    RequestContext context;
    context.ok = true;
    context.activeProtection = simplejson::GetBool(request, L"active_protection_detected", false) ||
        simplejson::GetBool(request, L"blocked_context", false);
    context.credentialRequired = simplejson::GetBool(request, L"credential_required_detected", false);
    context.staleObserve = simplejson::GetBool(request, L"stale_observe", false) ||
        simplejson::GetBool(request, L"observe_stale", false) ||
        simplejson::GetBool(request, L"target_from_current_observe", true) == false;
    context.hasWindowBounds = ReadRect(simplejson::Find(request, L"window_bounds"), context.windowBounds) && RectValid(context.windowBounds);
    context.hasScreenBounds = ReadRect(simplejson::Find(request, L"screen_bounds"), context.screenBounds) && RectValid(context.screenBounds);
    context.hasRoi = ReadRect(simplejson::Find(request, L"screenshot_region"), context.roi) && RectValid(context.roi);
    if (context.hasWindowBounds) {
        context.clientViewport = RECT{0, 0, RectWidth(context.windowBounds), RectHeight(context.windowBounds)};
    } else if (context.hasScreenBounds) {
        context.clientViewport = context.screenBounds;
    } else {
        context.clientViewport = RECT{0, 0, 1920, 1080};
    }
    context.screenshotPath = simplejson::GetString(request, L"screenshot_path", L"");
    context.uiaSummary = simplejson::GetString(request, L"uia_text_summary", L"");
    context.ocrSummary = simplejson::GetString(request, L"ocr_text_summary", L"");
    context.elementSummary = FlattenOptional(request, L"element_summary");
    context.expectedContext = options.expectedContext.empty()
        ? simplejson::GetString(request, L"expected_context", L"")
        : options.expectedContext;
    return context;
}

struct ParsedTarget {
    bool schemaOk = false;
    bool directCoordinate = false;
    std::wstring candidateId;
    std::wstring label;
    std::wstring role;
    RECT approxRegion = {};
    double confidence = 0.0;
    bool observationOnly = false;
    bool requiresRuntimeValidation = false;
};

ParsedTarget ParseTarget(const simplejson::Value& item) {
    ParsedTarget target;
    if (!item.IsObject()) return target;
    target.candidateId = simplejson::GetString(item, L"candidate_id", L"");
    target.label = simplejson::GetString(item, L"label", L"");
    target.role = simplejson::GetString(item, L"role_guess", L"");
    const simplejson::Value* confidence = simplejson::Find(item, L"confidence");
    target.confidence = confidence && confidence->IsNumber() ? confidence->numberValue : 0.0;
    target.observationOnly = simplejson::GetBool(item, L"observation_only", false);
    target.requiresRuntimeValidation = simplejson::GetBool(item, L"requires_runtime_validation", false);
    target.directCoordinate = simplejson::Has(item, L"click_point") ||
        simplejson::Has(item, L"direct_click") ||
        simplejson::Has(item, L"coordinate_action_detail") ||
        (simplejson::Has(item, L"x") && simplejson::Has(item, L"y"));
    bool hasRect = ReadRect(simplejson::Find(item, L"approx_region"), target.approxRegion) && RectValid(target.approxRegion);
    target.schemaOk =
        !target.candidateId.empty() &&
        !target.label.empty() &&
        !target.role.empty() &&
        confidence &&
        confidence->IsNumber() &&
        hasRect;
    return target;
}

bool MapCandidateToClientRect(const RequestContext& context, const RECT& candidateRect, RECT& clientRect) {
    if (!RectValid(candidateRect)) return false;
    if (RectInside(candidateRect, context.clientViewport)) {
        clientRect = candidateRect;
        return true;
    }
    if (context.hasWindowBounds && RectInside(candidateRect, context.windowBounds)) {
        clientRect = OffsetRectCopy(candidateRect, -context.windowBounds.left, -context.windowBounds.top);
        return RectInside(clientRect, context.clientViewport);
    }
    return false;
}

RuntimeCandidateValidationResult ValidateOne(
    const ParsedTarget& target,
    const RequestContext& request,
    const RuntimeCandidateValidationOptions& options) {
    RuntimeCandidateValidationResult result;
    result.candidateId = target.candidateId;
    result.candidateLabel = target.label;
    result.candidateRole = target.role;
    result.confidence = target.confidence;
    result.observationOnly = target.observationOnly;
    result.requiresRuntimeValidation = target.requiresRuntimeValidation;
    result.evidence.screenshotPath = request.screenshotPath;
    result.evidence.screenshotPathPresent = !request.screenshotPath.empty();
    result.evidence.expectedContext = request.expectedContext;
    result.freshnessOk = !request.staleObserve;
    result.riskOk = true;
    result.uniqueEnough = true;

    if (!target.schemaOk) {
        result.rejectionReason = L"CANDIDATE_SCHEMA_INVALID";
        return result;
    }
    if (!target.observationOnly || !target.requiresRuntimeValidation) {
        result.rejectionReason = L"CANDIDATE_SCHEMA_INVALID";
        return result;
    }
    if (target.directCoordinate) {
        result.directCoordinateForbidden = true;
        result.rejectionReason = L"CANDIDATE_DIRECT_COORDINATE_FORBIDDEN";
        return result;
    }
    if (!RoleSupported(target.role)) {
        result.rejectionReason = L"CANDIDATE_UNSUPPORTED_ROLE";
        return result;
    }
    if (target.confidence < 0.50) {
        result.rejectionReason = L"CANDIDATE_LOW_CONFIDENCE";
        return result;
    }
    if (!result.freshnessOk) {
        result.requiresReobserve = true;
        result.rejectionReason = L"CANDIDATE_STALE_OBSERVE";
        return result;
    }
    if (request.activeProtection) {
        result.riskOk = false;
        result.rejectionReason = L"CANDIDATE_ACTIVE_PROTECTION_REGION";
        return result;
    }
    if (request.credentialRequired) {
        result.riskOk = false;
        result.rejectionReason = L"CANDIDATE_CREDENTIAL_REGION";
        return result;
    }

    const std::wstring riskText = target.label + L" " + target.role + L" " + request.uiaSummary + L" " + request.ocrSummary + L" " + request.expectedContext;
    if (IsCredentialRiskText(riskText)) {
        result.riskOk = false;
        result.rejectionReason = L"CANDIDATE_CREDENTIAL_REGION";
        return result;
    }
    if (IsBlockedRiskText(riskText)) {
        result.riskOk = false;
        result.rejectionReason = L"CANDIDATE_ACTIVE_PROTECTION_REGION";
        return result;
    }

    RECT clientRect = {};
    if (!MapCandidateToClientRect(request, target.approxRegion, clientRect)) {
        if (target.approxRegion.right <= 0 || target.approxRegion.bottom <= 0 ||
            target.approxRegion.left >= request.clientViewport.right ||
            target.approxRegion.top >= request.clientViewport.bottom) {
            result.rejectionReason = L"CANDIDATE_OFFSCREEN";
        } else {
            result.rejectionReason = L"CANDIDATE_OUTSIDE_VIEWPORT";
        }
        return result;
    }
    if (!RectInside(clientRect, request.clientViewport)) {
        result.rejectionReason = L"CANDIDATE_OUTSIDE_VIEWPORT";
        return result;
    }
    if (request.hasRoi && !RectInside(clientRect, request.roi) && !RectIntersects(clientRect, request.roi)) {
        result.rejectionReason = L"CANDIDATE_OUTSIDE_VIEWPORT";
        return result;
    }

    result.validatedRect = clientRect;
    result.validatedCenterX = clientRect.left + (RectWidth(clientRect) / 2);
    result.validatedCenterY = clientRect.top + (RectHeight(clientRect) / 2);
    result.insideViewport = true;

    if (!options.targetLabel.empty() &&
        !ContainsInsensitive(target.label, options.targetLabel) &&
        !ContainsInsensitive(options.targetLabel, target.label)) {
        result.contextOk = false;
        result.rejectionReason = L"CANDIDATE_CONTEXT_MISMATCH";
        return result;
    }

    result.evidence.uiaCorroborated = TextMatches(request.uiaSummary, target.label) ||
        (!options.targetLabel.empty() && TextMatches(request.uiaSummary, options.targetLabel));
    result.evidence.ocrCorroborated = TextMatches(request.ocrSummary, target.label) ||
        (!options.targetLabel.empty() && TextMatches(request.ocrSummary, options.targetLabel));
    result.evidence.elementSummaryCorroborated = TextMatches(request.elementSummary, target.label) ||
        (!options.targetLabel.empty() && TextMatches(request.elementSummary, options.targetLabel));
    result.evidence.contextCorroborated = !request.expectedContext.empty() &&
        (TextMatches(request.expectedContext, target.label) ||
         (!options.targetLabel.empty() && TextMatches(request.expectedContext, options.targetLabel)));
    result.matchedUiaText = result.evidence.uiaCorroborated ? request.uiaSummary : L"";
    result.matchedOcrText = result.evidence.ocrCorroborated ? request.ocrSummary : L"";
    result.contextOk = options.expectedContext.empty() ||
        ContainsInsensitive(request.expectedContext, options.expectedContext) ||
        ContainsInsensitive(options.expectedContext, request.expectedContext) ||
        result.evidence.contextCorroborated ||
        result.evidence.uiaCorroborated ||
        result.evidence.ocrCorroborated ||
        result.evidence.elementSummaryCorroborated;

    const bool corroborated =
        result.evidence.uiaCorroborated ||
        result.evidence.ocrCorroborated ||
        result.evidence.elementSummaryCorroborated ||
        result.evidence.contextCorroborated;
    if (!corroborated) {
        result.rejectionReason = L"CANDIDATE_NO_RUNTIME_CORROBORATION";
        return result;
    }
    if (!result.contextOk) {
        result.rejectionReason = L"CANDIDATE_CONTEXT_MISMATCH";
        return result;
    }

    result.validationMethod = MethodJson(
        result.evidence.uiaCorroborated,
        result.evidence.ocrCorroborated,
        result.evidence.contextCorroborated,
        result.evidence.elementSummaryCorroborated,
        request.hasRoi);
    result.candidateValidationOk = true;
    result.safeToConvertToLocatorCandidate = true;
    return result;
}

}  // namespace

RuntimeCandidateValidationBatch ValidateRuntimeCandidatesFromJson(
    const std::wstring& requestJson,
    const std::wstring& vlmResultJson,
    const RuntimeCandidateValidationOptions& options) {
    RuntimeCandidateValidationBatch batch;
    simplejson::ParseResult parsedRequest = simplejson::Parse(requestJson);
    simplejson::ParseResult parsedResult = simplejson::Parse(vlmResultJson);
    if (!parsedRequest.ok || !parsedRequest.root.IsObject() || !parsedResult.ok || !parsedResult.root.IsObject()) {
        batch.stopCode = L"CANDIDATE_SCHEMA_INVALID";
        AddUnique(batch.rejectionReasons, L"CANDIDATE_SCHEMA_INVALID");
        batch.resultJson = RuntimeCandidateValidationBatchJson(batch);
        return batch;
    }

    RequestContext request = BuildRequestContext(parsedRequest.root, options);
    const simplejson::Value* targets = simplejson::Find(parsedResult.root, L"possible_targets");
    if (!targets || !targets->IsArray()) {
        batch.stopCode = L"CANDIDATE_SCHEMA_INVALID";
        AddUnique(batch.rejectionReasons, L"CANDIDATE_SCHEMA_INVALID");
        batch.resultJson = RuntimeCandidateValidationBatchJson(batch);
        return batch;
    }

    for (const auto& item : targets->arrayValue) {
        ParsedTarget parsed = ParseTarget(item);
        RuntimeCandidateValidationResult result = ValidateOne(parsed, request, options);
        ++batch.candidateCount;
        if (result.candidateValidationOk) {
            ++batch.validatedCandidateCount;
        } else {
            ++batch.rejectedCandidateCount;
            AddUnique(batch.rejectionReasons, result.rejectionReason);
        }
        batch.candidates.push_back(result);
    }

    if (batch.validatedCandidateCount == 1) {
        for (const auto& item : batch.candidates) {
            if (item.candidateValidationOk) {
                batch.selectedCandidate = item;
                break;
            }
        }
        batch.validationOk = true;
        batch.selectedCandidateUnique = true;
    } else if (batch.validatedCandidateCount > 1) {
        batch.validationOk = false;
        batch.selectedCandidateUnique = false;
        batch.stopCode = L"STOP_TARGET_NOT_UNIQUE";
        AddUnique(batch.rejectionReasons, L"CANDIDATE_NOT_UNIQUE");
        for (auto& item : batch.candidates) {
            if (item.candidateValidationOk) {
                item.candidateValidationOk = false;
                item.safeToConvertToLocatorCandidate = false;
                item.uniqueEnough = false;
                item.rejectionReason = L"CANDIDATE_NOT_UNIQUE";
            }
        }
        batch.rejectedCandidateCount = batch.candidateCount;
        batch.validatedCandidateCount = 0;
    } else {
        batch.validationOk = false;
        batch.selectedCandidateUnique = false;
        if (batch.stopCode.empty()) {
            batch.stopCode = batch.rejectionReasons.empty() ? L"CANDIDATE_NO_RUNTIME_CORROBORATION" : batch.rejectionReasons.front();
        }
    }

    batch.resultJson = RuntimeCandidateValidationBatchJson(batch);
    return batch;
}

std::wstring RuntimeCandidateValidationResultJson(const RuntimeCandidateValidationResult& result) {
    std::wstringstream json;
    json << L"{\"candidate_validation_ok\":" << BoolJson(result.candidateValidationOk)
         << L",\"candidate_id\":" << JsonString(result.candidateId)
         << L",\"candidate_label\":" << JsonString(result.candidateLabel)
         << L",\"candidate_role\":" << JsonString(result.candidateRole)
         << L",\"validated_rect\":" << RectJson(result.validatedRect)
         << L",\"validated_center\":{\"x\":" << result.validatedCenterX << L",\"y\":" << result.validatedCenterY << L"}"
         << L",\"confidence\":" << NumberJson(result.confidence)
         << L",\"validation_method\":" << JsonString(result.validationMethod)
         << L",\"matched_ocr_text\":" << JsonString(result.matchedOcrText)
         << L",\"matched_uia_text\":" << JsonString(result.matchedUiaText)
         << L",\"inside_viewport\":" << BoolJson(result.insideViewport)
         << L",\"unique_enough\":" << BoolJson(result.uniqueEnough)
         << L",\"context_ok\":" << BoolJson(result.contextOk)
         << L",\"risk_ok\":" << BoolJson(result.riskOk)
         << L",\"freshness_ok\":" << BoolJson(result.freshnessOk)
         << L",\"requires_reobserve\":" << BoolJson(result.requiresReobserve)
         << L",\"rejection_reason\":" << JsonString(result.rejectionReason)
         << L",\"safe_to_convert_to_locator_candidate\":" << BoolJson(result.safeToConvertToLocatorCandidate)
         << L",\"observation_only\":" << BoolJson(result.observationOnly)
         << L",\"requires_runtime_validation\":" << BoolJson(result.requiresRuntimeValidation)
         << L",\"direct_coordinate_forbidden\":" << BoolJson(result.directCoordinateForbidden)
         << L",\"evidence_pack\":{"
         << L"\"screenshot_path_present\":" << BoolJson(result.evidence.screenshotPathPresent)
         << L",\"screenshot_path\":" << JsonString(result.evidence.screenshotPath)
         << L",\"uia_corroborated\":" << BoolJson(result.evidence.uiaCorroborated)
         << L",\"ocr_corroborated\":" << BoolJson(result.evidence.ocrCorroborated)
         << L",\"context_corroborated\":" << BoolJson(result.evidence.contextCorroborated)
         << L",\"element_summary_corroborated\":" << BoolJson(result.evidence.elementSummaryCorroborated)
         << L",\"expected_context\":" << JsonString(result.evidence.expectedContext)
         << L"}}";
    return json.str();
}

std::wstring RuntimeCandidateValidationBatchJson(const RuntimeCandidateValidationBatch& batch) {
    std::wstringstream candidates;
    candidates << L"[";
    for (size_t i = 0; i < batch.candidates.size(); ++i) {
        if (i) candidates << L",";
        candidates << RuntimeCandidateValidationResultJson(batch.candidates[i]);
    }
    candidates << L"]";

    std::wstringstream json;
    json << L"{\"candidate_validation_ok\":" << BoolJson(batch.validationOk)
         << L",\"candidate_count\":" << batch.candidateCount
         << L",\"validated_candidate_count\":" << batch.validatedCandidateCount
         << L",\"rejected_candidate_count\":" << batch.rejectedCandidateCount
         << L",\"selected_candidate_unique\":" << BoolJson(batch.selectedCandidateUnique)
         << L",\"selected_candidate_id\":" << JsonString(batch.selectedCandidate.candidateId)
         << L",\"stop_code\":" << JsonString(batch.stopCode)
         << L",\"rejection_reasons\":" << VLMStringArrayJson(batch.rejectionReasons)
         << L",\"selected_candidate\":";
    if (batch.validationOk) {
        json << RuntimeCandidateValidationResultJson(batch.selectedCandidate);
    } else {
        json << L"null";
    }
    json << L",\"candidates\":" << candidates.str()
         << L",\"validator_version\":\"6.6.0.runtime_candidate_validator\""
         << L"}";
    return json.str();
}

