#include "VLMObservationValidator.h"

#include "SimpleJson.h"
#include "Trace.h"
#include "VLMObservationContract.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <iostream>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool Contains(const std::wstring& haystack, const std::wstring& needle) {
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

void AddUnique(std::vector<std::wstring>& values, const std::wstring& code) {
    if (std::find(values.begin(), values.end(), code) == values.end()) {
        values.push_back(code);
    }
}

bool HasBoolField(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && value->IsBool();
}

bool HasStringField(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && value->IsString();
}

bool HasArrayField(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && value->IsArray();
}

bool HasNumberField(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* value = simplejson::Find(object, key);
    return value && value->IsNumber();
}

std::wstring ArrayJson(const std::vector<std::wstring>& values) {
    return VLMStringArrayJson(values);
}

std::wstring ValidationResultJson(const VLMObservationValidationResult& result) {
    std::wstringstream json;
    json << L"{\"validation_ok\":" << (result.validationOk ? L"true" : L"false")
         << L",\"executable\":" << (result.executable ? L"true" : L"false")
         << L",\"assistive_only\":" << (result.assistiveOnly ? L"true" : L"false")
         << L",\"request_id_match\":" << (result.requestIdMatch ? L"true" : L"false")
         << L",\"result_schema_valid\":" << (result.resultSchemaValid ? L"true" : L"false")
         << L",\"possible_targets_observation_only\":" << (result.possibleTargetsObservationOnly ? L"true" : L"false")
         << L",\"requires_runtime_validation\":" << (result.requiresRuntimeValidation ? L"true" : L"false")
         << L",\"validation_errors\":" << ArrayJson(result.validationErrors)
         << L",\"validation_warnings\":" << ArrayJson(result.validationWarnings)
         << L",\"blocked_reason\":" << JsonString(result.blockedReason)
         << L",\"safe_for_runtime_candidate_pipeline\":" << (result.safeForRuntimeCandidatePipeline ? L"true" : L"false")
         << L",\"safe_for_direct_execution\":false"
         << L",\"validator_version\":\"6.5.0.vlm_observation_validator\""
         << L"}";
    return json.str();
}

std::wstring FlattenTextArray(const simplejson::Value& object, const std::wstring& key) {
    const simplejson::Value* array = simplejson::Find(object, key);
    if (!array || !array->IsArray()) return L"";
    std::wstringstream text;
    for (const auto& item : array->arrayValue) {
        if (item.IsString()) text << L" " << item.stringValue;
    }
    return text.str();
}

bool RequestActiveProtection(const simplejson::Value& request) {
    return simplejson::GetBool(request, L"active_protection_detected", false);
}

bool RequestCredentialRequired(const simplejson::Value& request) {
    return simplejson::GetBool(request, L"credential_required_detected", false);
}

bool RequestBlockedContext(const simplejson::Value& request) {
    return simplejson::GetBool(request, L"blocked_context", false) ||
        RequestActiveProtection(request) ||
        RequestCredentialRequired(request);
}

bool IsPromptInjectionText(const std::wstring& text) {
    return Contains(text, L"ignore previous instructions") ||
        Contains(text, L"ignore all previous") ||
        Contains(text, L"system instruction") ||
        Contains(text, L"developer instruction") ||
        Contains(text, L"you are now");
}

bool IsCaptchaBypassText(const std::wstring& text) {
    return Contains(text, L"captcha") && (Contains(text, L"bypass") || Contains(text, L"solve"));
}

bool IsCredentialInstructionText(const std::wstring& text) {
    bool credential = Contains(text, L"password") ||
        Contains(text, L"credential") ||
        Contains(text, L"one-time code") ||
        Contains(text, L"verification code");
    return credential && (Contains(text, L"enter") || Contains(text, L"input") || Contains(text, L"type"));
}

bool IsActiveProtectionBypassText(const std::wstring& text) {
    bool protection = Contains(text, L"active protection") ||
        Contains(text, L"human verification") ||
        Contains(text, L"script detection") ||
        Contains(text, L"automation detection") ||
        Contains(text, L"anti-cheat") ||
        Contains(text, L"anti cheat");
    return protection && (Contains(text, L"bypass") || Contains(text, L"evade") || Contains(text, L"avoid") || Contains(text, L"disable"));
}

void ValidateSchemaFields(const simplejson::Value& result, VLMObservationValidationResult& validation) {
    const std::vector<std::wstring> stringFields = {
        L"result_id",
        L"request_id",
        L"provider_name",
        L"provider_role",
        L"schema_version",
        L"scene_summary",
        L"raw_provider_output_ref",
        L"created_at"
    };
    for (const auto& field : stringFields) {
        if (!HasStringField(result, field)) AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
    }
    const std::vector<std::wstring> arrayFields = {
        L"visible_text",
        L"layout_regions",
        L"semantic_elements",
        L"possible_targets",
        L"safety_notes"
    };
    for (const auto& field : arrayFields) {
        if (!HasArrayField(result, field)) AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
    }
    const std::vector<std::wstring> boolFields = {
        L"contains_action",
        L"contains_coordinates",
        L"contains_executable_instruction",
        L"contains_bypass_instruction",
        L"contains_credential_instruction"
    };
    for (const auto& field : boolFields) {
        if (!HasBoolField(result, field)) AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
    }
    if (!HasNumberField(result, L"uncertainty")) AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
}

void ValidatePossibleTargets(const simplejson::Value& result, VLMObservationValidationResult& validation) {
    const simplejson::Value* targets = simplejson::Find(result, L"possible_targets");
    if (!targets || !targets->IsArray()) return;
    for (const auto& item : targets->arrayValue) {
        if (!item.IsObject()) {
            validation.possibleTargetsObservationOnly = false;
            validation.requiresRuntimeValidation = false;
            AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
            continue;
        }
        const simplejson::Value* observationOnly = simplejson::Find(item, L"observation_only");
        if (!observationOnly || !observationOnly->IsBool() || !observationOnly->boolValue) {
            validation.possibleTargetsObservationOnly = false;
            AddUnique(validation.validationErrors, L"VLM_DIRECT_ACTION_REJECTED");
        }
        const simplejson::Value* requiresValidation = simplejson::Find(item, L"requires_runtime_validation");
        if (!requiresValidation || !requiresValidation->IsBool() || !requiresValidation->boolValue) {
            validation.requiresRuntimeValidation = false;
            AddUnique(validation.validationErrors, L"VLM_CANDIDATE_REQUIRES_RUNTIME_VALIDATION");
        }
        if (!HasStringField(item, L"candidate_id") ||
            !HasStringField(item, L"label") ||
            !HasStringField(item, L"role_guess") ||
            !simplejson::Find(item, L"approx_region") ||
            !HasNumberField(item, L"confidence")) {
            AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
        }
    }
}

}  // namespace

VLMObservationValidationResult ValidateVLMObservationResultJson(
    const std::wstring& requestJson,
    const std::wstring& resultJson) {
    VLMObservationValidationResult validation;
    validation.executable = false;
    validation.safeForDirectExecution = false;

    simplejson::ParseResult parsedRequest = simplejson::Parse(requestJson);
    if (!parsedRequest.ok || !parsedRequest.root.IsObject()) {
        AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
        validation.resultJson = ValidationResultJson(validation);
        return validation;
    }

    simplejson::ParseResult parsedResult = simplejson::Parse(resultJson);
    if (!parsedResult.ok || !parsedResult.root.IsObject()) {
        AddUnique(validation.validationErrors, L"VLM_MALFORMED_JSON");
        validation.blockedReason = L"MALFORMED_PROVIDER_OUTPUT";
        validation.resultJson = ValidationResultJson(validation);
        return validation;
    }

    const simplejson::Value& request = parsedRequest.root;
    const simplejson::Value& result = parsedResult.root;
    ValidateSchemaFields(result, validation);

    std::wstring requestId = simplejson::GetString(request, L"request_id", L"");
    std::wstring resultRequestId = simplejson::GetString(result, L"request_id", L"");
    validation.requestIdMatch = !requestId.empty() && requestId == resultRequestId;
    if (!validation.requestIdMatch) AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");

    std::wstring providerRole = simplejson::GetString(result, L"provider_role", L"");
    validation.assistiveOnly = providerRole == L"assistive_only";
    if (!validation.assistiveOnly) AddUnique(validation.validationErrors, L"VLM_PROVIDER_ROLE_INVALID");

    ValidatePossibleTargets(result, validation);

    bool containsAction = simplejson::GetBool(result, L"contains_action", false);
    bool containsExecutable = simplejson::GetBool(result, L"contains_executable_instruction", false);
    bool containsBypass = simplejson::GetBool(result, L"contains_bypass_instruction", false);
    bool containsCredential = simplejson::GetBool(result, L"contains_credential_instruction", false);
    bool coordinateOnly = simplejson::GetBool(result, L"coordinate_only_action", false);
    bool runtimeCommand = simplejson::GetBool(result, L"runtime_command_present", false) || simplejson::Has(result, L"runtime_command");

    if (containsAction || containsExecutable || simplejson::Has(result, L"direct_click") || simplejson::Has(result, L"direct_type") || simplejson::Has(result, L"direct_scroll") || simplejson::GetBool(result, L"executable", false)) {
        AddUnique(validation.validationErrors, L"VLM_DIRECT_ACTION_REJECTED");
    }
    if (coordinateOnly || simplejson::Has(result, L"click_point") || simplejson::Has(result, L"coordinate_action_detail")) {
        AddUnique(validation.validationErrors, L"VLM_COORDINATE_ACTION_REJECTED");
    }
    if (runtimeCommand) {
        AddUnique(validation.validationErrors, L"VLM_RUNTIME_COMMAND_REJECTED");
    }

    std::wstring textSurface =
        simplejson::GetString(result, L"scene_summary", L"") + L" " +
        simplejson::GetString(result, L"rejection_reason", L"") + L" " +
        FlattenTextArray(result, L"visible_text") + L" " +
        FlattenTextArray(result, L"safety_notes");

    if (IsPromptInjectionText(textSurface)) {
        AddUnique(validation.validationWarnings, L"VLM_PROMPT_INJECTION_CLASSIFIED");
    }
    if (containsCredential || IsCredentialInstructionText(textSurface)) {
        AddUnique(validation.validationErrors, L"VLM_CREDENTIAL_INSTRUCTION_REJECTED");
    }
    if (IsActiveProtectionBypassText(textSurface)) {
        AddUnique(validation.validationErrors, L"VLM_ACTIVE_PROTECTION_BYPASS_REJECTED");
    }
    if (containsBypass || IsCaptchaBypassText(textSurface)) {
        AddUnique(validation.validationErrors, L"VLM_BYPASS_INSTRUCTION_REJECTED");
    }

    if (RequestActiveProtection(request)) {
        validation.blockedReason = L"ACTIVE_PROTECTION_CONTEXT";
    } else if (RequestCredentialRequired(request)) {
        validation.blockedReason = L"CREDENTIAL_REQUIRED_CONTEXT";
    } else if (RequestBlockedContext(request)) {
        validation.blockedReason = L"BLOCKED_CONTEXT";
    }

    validation.resultSchemaValid = validation.validationErrors.empty() ||
        (validation.validationErrors.size() == 1 && validation.validationErrors[0] == L"VLM_PROMPT_INJECTION_CLASSIFIED");
    validation.validationOk = validation.validationErrors.empty();
    validation.safeForRuntimeCandidatePipeline =
        validation.validationOk &&
        validation.assistiveOnly &&
        validation.possibleTargetsObservationOnly &&
        validation.requiresRuntimeValidation &&
        !RequestBlockedContext(request);
    validation.safeForDirectExecution = false;
    validation.executable = false;
    validation.resultJson = ValidationResultJson(validation);
    return validation;
}

VLMObservationValidationResult ValidateVLMObservationResultFile(
    const std::wstring& requestPath,
    const std::wstring& resultPath,
    const std::wstring& outputPath) {
    VLMObservationValidationResult validation;
    std::wstring requestJson;
    std::wstring resultJson;
    std::wstring ioError;
    if (!VLMReadTextFile(requestPath, requestJson, ioError)) {
        AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
        validation.blockedReason = L"REQUEST_READ_FAILED";
        validation.resultJson = ValidationResultJson(validation);
    } else if (!VLMReadTextFile(resultPath, resultJson, ioError)) {
        AddUnique(validation.validationErrors, L"VLM_SCHEMA_INVALID");
        validation.blockedReason = L"RESULT_READ_FAILED";
        validation.resultJson = ValidationResultJson(validation);
    } else {
        validation = ValidateVLMObservationResultJson(requestJson, resultJson);
    }
    if (!outputPath.empty()) {
        std::wstring writeError;
        VLMWriteTextFile(outputPath, validation.resultJson, writeError);
    }
    return validation;
}

int CommandVLMObservationValidate(int argc, wchar_t** argv) {
    ULONGLONG startTick = GetTickCount64();
    const std::wstring command = L"vlm-observation-validate";
    std::wstring requestPath;
    std::wstring resultPath;
    std::wstring outputPath;
    ArgValue(argc, argv, L"--request", requestPath);
    ArgValue(argc, argv, L"--result", resultPath);
    ArgValue(argc, argv, L"--output", outputPath);
    if (requestPath.empty() || resultPath.empty() || outputPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"vlm-observation-validate requires --request, --result, and --output.", L"{}") << L"\n";
        return 2;
    }
    VLMObservationValidationResult validation = ValidateVLMObservationResultFile(requestPath, resultPath, outputPath);
    if (!validation.validationOk) {
        std::wstring firstError = validation.validationErrors.empty() ? L"VLM_SCHEMA_INVALID" : validation.validationErrors[0];
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), firstError, L"VLM observation result validation failed.", validation.resultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), validation.resultJson) << L"\n";
    return 0;
}
