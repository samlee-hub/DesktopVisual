#include "TaskRunner.h"

#include "CaseRunner.h"      // ReadTextFile, WriteUtf8TextFile
#include "CodingWorkflow.h"
#include "DecisionEngine.h"
#include "FormSemantics.h"
#include "InputController.h"
#include "MotionProfile.h"
#include "ObserveController.h"
#include "OcrController.h"
#include "PermissionManager.h"
#include "ProjectRoot.h"
#include "RecoveryStrategy.h"
#include "ReportWriter.h"     // CurrentTimestamp
#include "SafetyManifest.h"
#include "SafetyPolicy.h"
#include "Screenshot.h"
#include "Selector.h"
#include "Trace.h"
#include "UiaController.h"
#include "WindowFinder.h"
#include "WindowSession.h"

#include <windows.h>
#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <iomanip>
#include <sstream>

namespace {

// ===================================================================
// Simple JSON parser (same pattern as service mode)
// ===================================================================
std::wstring JsonGetString(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'"') return L"";
    ++pos;
    std::wstring value;
    while (pos < json.size() && json[pos] != L'"') {
        if (json[pos] == L'\\' && pos + 1 < json.size()) { ++pos; }
        value += json[pos]; ++pos;
    }
    return value;
}

int JsonGetInt(const std::wstring& json, const std::wstring& key, int def = 0) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    try { return std::stoi(json.substr(pos)); } catch (...) { return def; }
}

double JsonGetDouble(const std::wstring& json, const std::wstring& key, double def = 0.0) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return def;
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos < json.size() && json[pos] == L'"') ++pos;  // tolerate quoted numbers
    try { return std::stod(json.substr(pos)); } catch (...) { return def; }
}

bool JsonGetBool(const std::wstring& json, const std::wstring& key, bool def = false) {
    std::wstring val = JsonGetString(json, key);
    if (val.empty()) {
        std::wstring search = L"\"" + key + L"\":";
        size_t pos = json.find(search);
        if (pos != std::wstring::npos) {
            pos += search.size();
            while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
            if (json.substr(pos, 4) == L"true") return true;
            if (json.substr(pos, 5) == L"false") return false;
        }
        return def;
    }
    return val == L"true" || val == L"1";
}

bool IsMotionProfileFailure(const std::wstring& code) {
    return code == L"MOTION_PROFILE_NOT_FOUND" || code == L"MOTION_PROFILE_INVALID" ||
           code == L"MOTION_PROFILE_NOT_HUMAN" || code == L"MOTION_PROFILE_TEST_ONLY" ||
           code == L"MOTION_PROFILE_SOURCE_REQUIRED";
}

bool IsAllowedMoveFallback(const std::wstring& fallback) {
    return fallback.empty() || fallback == L"fast-human";
}

bool IsOperatorRequestedMove(const std::wstring& moveMode) {
    return moveMode.empty() || moveMode == L"human" || moveMode == L"operator-human";
}

bool IsSafeTemplateName(const std::wstring& name) {
    if (name.empty()) return false;
    for (wchar_t ch : name) {
        bool ok = (ch >= L'a' && ch <= L'z') || (ch >= L'0' && ch <= L'9') || ch == L'_';
        if (!ok) return false;
    }
    return true;
}

std::wstring JsonGetNamedString(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\"";
    size_t pos = 0;
    while ((pos = json.find(search, pos)) != std::wstring::npos) {
        size_t cursor = pos + search.size();
        while (cursor < json.size() && iswspace(json[cursor])) ++cursor;
        if (cursor >= json.size() || json[cursor] != L':') {
            pos += search.size();
            continue;
        }
        ++cursor;
        while (cursor < json.size() && iswspace(json[cursor])) ++cursor;
        if (cursor >= json.size() || json[cursor] != L'"') {
            return L"";
        }
        ++cursor;
        std::wstring value;
        while (cursor < json.size() && json[cursor] != L'"') {
            if (json[cursor] == L'\\' && cursor + 1 < json.size()) { ++cursor; }
            value += json[cursor];
            ++cursor;
        }
        return value;
    }
    return L"";
}

std::wstring JsonGetObject(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'{') return L"";
    int depth = 1; size_t start = pos; ++pos;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'{') ++depth;
        else if (json[pos] == L'}') --depth;
        ++pos;
    }
    return json.substr(start, pos - start);
}

std::wstring JsonGetArray(const std::wstring& json, const std::wstring& key) {
    std::wstring search = L"\"" + key + L"\":";
    size_t pos = json.find(search);
    if (pos == std::wstring::npos) return L"";
    pos += search.size();
    while (pos < json.size() && (iswspace(json[pos]) || json[pos] == L':')) ++pos;
    if (pos >= json.size() || json[pos] != L'[') return L"";
    int depth = 1; size_t start = pos; ++pos;
    while (pos < json.size() && depth > 0) {
        if (json[pos] == L'[') ++depth;
        else if (json[pos] == L']') --depth;
        ++pos;
    }
    return json.substr(start, pos - start);
}

std::vector<std::wstring> JsonGetObjectArray(const std::wstring& json) {
    std::vector<std::wstring> result;
    if (json.empty() || json[0] != L'[') return result;
    size_t pos = 1;
    while (pos < json.size()) {
        while (pos < json.size() && iswspace(json[pos])) ++pos;
        if (json[pos] == L']') break;
        if (json[pos] == L'{') {
            int depth = 1; size_t start = pos; ++pos;
            while (pos < json.size() && depth > 0) {
                if (json[pos] == L'{') ++depth;
                else if (json[pos] == L'}') --depth;
                ++pos;
            }
            result.push_back(json.substr(start, pos - start));
        } else { ++pos; }
        while (pos < json.size() && json[pos] == L',') ++pos;
    }
    return result;
}

TaskStep ParseTaskStepObject(const std::wstring& stepObj) {
    TaskStep step;
    step.name = JsonGetString(stepObj, L"name");
    step.type = JsonGetString(stepObj, L"type");
    step.templateName = JsonGetNamedString(stepObj, L"template");
    step.templateParametersJson = JsonGetObject(stepObj, L"parameters");
    step.selector = JsonGetString(stepObj, L"selector");
    step.action = JsonGetString(stepObj, L"action");
    step.htmlPath = JsonGetString(stepObj, L"html_path");
    step.fieldId = JsonGetString(stepObj, L"field_id");
    step.label = JsonGetString(stepObj, L"label");
    step.controlType = JsonGetString(stepObj, L"control_type");
    step.value = JsonGetString(stepObj, L"value");
    step.option = JsonGetString(stepObj, L"option");
    step.text = JsonGetString(stepObj, L"text");
    step.operation = JsonGetString(stepObj, L"operation");
    step.channel = JsonGetString(stepObj, L"channel");
    step.communicationTarget = JsonGetString(stepObj, L"target");
    step.subject = JsonGetString(stepObj, L"subject");
    step.content = JsonGetString(stepObj, L"content");
    step.contentSummary = JsonGetString(stepObj, L"content_summary");
    step.userRequestedSend = JsonGetBool(stepObj, L"user_requested_send", false);
    step.userGoal = JsonGetString(stepObj, L"user_goal");
    step.currentUrl = JsonGetString(stepObj, L"current_url");
    step.pageId = JsonGetString(stepObj, L"page_id");
    step.observedSummary = JsonGetString(stepObj, L"observed_summary");
    step.windowTitle = JsonGetString(stepObj, L"window_title");
    step.allowSubmit = JsonGetBool(stepObj, L"allow_submit", false);
    step.minConfidence = JsonGetDouble(stepObj, L"min_confidence", 0.50);
    step.language = JsonGetString(stepObj, L"language");
    step.codeText = JsonGetString(stepObj, L"code");
    step.codePath = JsonGetString(stepObj, L"code_path");
    step.revisionCount = JsonGetInt(stepObj, L"revision_count", 0);
    step.liveExecute = JsonGetBool(stepObj, L"live_execute", false);
    step.editorSelector = JsonGetString(stepObj, L"editor_selector");
    step.runSelector = JsonGetString(stepObj, L"run_selector");
    step.submitSelector = JsonGetString(stepObj, L"submit_selector");
    step.resultSelector = JsonGetString(stepObj, L"result_selector");
    step.keys = JsonGetString(stepObj, L"keys");
    step.moveMode = JsonGetString(stepObj, L"move_mode");
    if (step.moveMode.empty()) step.moveMode = L"human";
    step.moveFallback = JsonGetString(stepObj, L"fallback");
    step.profilePath = JsonGetString(stepObj, L"profile");
    step.allowSyntheticProfile = JsonGetBool(stepObj, L"allow_synthetic_profile", false);
    step.waitMs = JsonGetInt(stepObj, L"wait_ms", 0);
    step.timeoutMs = JsonGetInt(stepObj, L"timeout_ms", 5000);
    step.path = JsonGetString(stepObj, L"path");
    step.allowRetry = JsonGetBool(stepObj, L"allow_retry_action", false);

    std::wstring expectObj = JsonGetObject(stepObj, L"expect");
    if (!expectObj.empty()) {
        step.hasExpect = true;
        step.expectSelectorExists = JsonGetString(expectObj, L"selector_exists");
        step.expectTextContains = JsonGetString(expectObj, L"text_contains");
        step.expectFileContainsPath = JsonGetString(expectObj, L"file_contains_path");
        step.expectFileContainsText = JsonGetString(expectObj, L"file_contains_text");
        step.expectWindowTitleContains = JsonGetString(expectObj, L"window_title_contains");
    }
    return step;
}

bool JsonParameterValue(const std::wstring& parametersJson, const std::wstring& key, std::wstring& value) {
    std::wstring quoted = JsonGetString(parametersJson, key);
    if (!quoted.empty()) {
        value = quoted;
        return true;
    }

    std::wstring search = L"\"" + key + L"\"";
    size_t pos = parametersJson.find(search);
    if (pos == std::wstring::npos) return false;
    pos += search.size();
    while (pos < parametersJson.size() && (iswspace(parametersJson[pos]) || parametersJson[pos] == L':')) ++pos;
    if (pos >= parametersJson.size()) return false;
    if (parametersJson[pos] == L'"') {
        value = L"";
        return true;
    }
    size_t start = pos;
    while (pos < parametersJson.size() && parametersJson[pos] != L',' && parametersJson[pos] != L'}') ++pos;
    value = parametersJson.substr(start, pos - start);
    while (!value.empty() && iswspace(value.back())) value.pop_back();
    return true;
}

bool SubstituteTemplateParameters(
    const std::wstring& source,
    const std::wstring& parametersJson,
    std::wstring& expanded,
    std::wstring& error) {
    expanded.clear();
    size_t pos = 0;
    while (pos < source.size()) {
        size_t start = source.find(L"${", pos);
        if (start == std::wstring::npos) {
            expanded += source.substr(pos);
            return true;
        }
        expanded += source.substr(pos, start - pos);
        size_t end = source.find(L"}", start + 2);
        if (end == std::wstring::npos) {
            error = L"Unclosed template parameter placeholder.";
            return false;
        }
        std::wstring key = source.substr(start + 2, end - (start + 2));
        std::wstring value;
        if (!JsonParameterValue(parametersJson, key, value)) {
            error = L"Missing template parameter: " + key;
            return false;
        }
        expanded += JsonEscape(value);
        pos = end + 1;
    }
    return true;
}

bool ValidateTemplateManifest(const std::wstring& content, const std::wstring& expectedName, std::wstring& error) {
    if (JsonGetString(content, L"name") != expectedName) {
        error = L"Template name does not match file name: " + expectedName;
        return false;
    }
    if (JsonGetArray(content, L"required_permissions").empty()) {
        error = L"Template missing required_permissions: " + expectedName;
        return false;
    }
    if (JsonGetObject(content, L"allowed_window").empty()) {
        error = L"Template missing allowed_window: " + expectedName;
        return false;
    }
    if (JsonGetString(content, L"expected_result").empty()) {
        error = L"Template missing expected_result: " + expectedName;
        return false;
    }
    if (JsonGetString(content, L"failure_behavior").empty()) {
        error = L"Template missing failure_behavior: " + expectedName;
        return false;
    }
    if (JsonGetArray(content, L"steps").empty()) {
        error = L"Template missing steps: " + expectedName;
        return false;
    }
    if (JsonGetBool(content, L"allow_unrestricted_desktop", false)) {
        error = L"Template cannot allow unrestricted desktop: " + expectedName;
        return false;
    }
    return true;
}

bool ExpandTaskTemplates(TaskDefinition& task, std::wstring& error) {
    std::vector<TaskStep> expandedTaskSteps;
    std::vector<TaskTemplateUsage> usages;
    int nextUsageId = 0;

    for (const auto& step : task.steps) {
        if (step.type != L"template") {
            expandedTaskSteps.push_back(step);
            continue;
        }

        if (!IsSafeTemplateName(step.templateName)) {
            error = L"Invalid task template name: " + step.templateName;
            return false;
        }

        std::wstring templatePath = ProjectPath(L"tasks\\templates\\" + step.templateName + L".task-template.json");
        FileReadResult templateRead = ReadTextFile(templatePath);
        if (!templateRead.ok) {
            error = L"Could not read task template " + step.templateName + L": " + templateRead.error;
            return false;
        }
        if (!ValidateTemplateManifest(templateRead.content, step.templateName, error)) {
            return false;
        }

        std::wstring stepsArray = JsonGetArray(templateRead.content, L"steps");
        auto templateStepObjects = JsonGetObjectArray(stepsArray);
        if (templateStepObjects.empty()) {
            error = L"Task template has no expandable steps: " + step.templateName;
            return false;
        }

        TaskTemplateUsage usage;
        usage.id = nextUsageId++;
        usage.name = step.templateName;
        usage.stepName = step.name;
        usage.parametersJson = step.templateParametersJson.empty() ? L"{}" : step.templateParametersJson;
        usage.expandedStepCount = static_cast<int>(templateStepObjects.size());

        std::wstringstream expandedStepsJson;
        expandedStepsJson << L"[";
        for (size_t i = 0; i < templateStepObjects.size(); ++i) {
            std::wstring expandedStepJson;
            if (!SubstituteTemplateParameters(templateStepObjects[i], usage.parametersJson, expandedStepJson, error)) {
                error = L"Template " + step.templateName + L" expansion failed: " + error;
                return false;
            }
            if (i != 0) expandedStepsJson << L",";
            expandedStepsJson << expandedStepJson;

            TaskStep expandedStep = ParseTaskStepObject(expandedStepJson);
            expandedStep.templateUsageId = usage.id;
            expandedStep.templateName = usage.name;
            if (expandedStep.name.empty()) {
                expandedStep.name = step.name + L"::" + expandedStep.type;
            } else {
                expandedStep.name = step.name + L"::" + expandedStep.name;
            }
            expandedTaskSteps.push_back(expandedStep);
        }
        expandedStepsJson << L"]";
        usage.expandedStepsJson = expandedStepsJson.str();
        usages.push_back(usage);
    }

    task.steps = expandedTaskSteps;
    task.templateUsages = usages;
    return true;
}

// ===================================================================
// Failure Classifier
// ===================================================================
FailureClassification ClassifyFailure(const std::wstring& errorCode, const std::wstring& errorMessage) {
    FailureClassification fc;
    fc.rawErrorCode = errorCode;
    fc.rawErrorMessage = errorMessage;

    if (errorCode == L"WINDOW_NOT_FOUND") {
        fc.category = FailureCategory::WINDOW_NOT_FOUND;
        fc.canRecover = true;
        fc.safeRecoveryAction = L"find_process_window_activate";
        fc.recommendedUserAction = L"Check that the target application is running with the expected window title. Use 'winagent windows' to list visible windows.";
    } else if (errorCode == L"WINDOW_NOT_UNIQUE") {
        fc.category = FailureCategory::WINDOW_NOT_UNIQUE;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Provide a more specific window title substring. Use 'winagent windows' to list candidates.";
    } else if (errorCode == L"WINDOW_TITLE_CHANGED") {
        fc.category = FailureCategory::WINDOW_TITLE_CHANGED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"The target window title changed during the task. Re-observe the application and update the target title before retrying.";
    } else if (errorCode == L"WINDOW_FOCUS_FAILED") {
        fc.category = FailureCategory::WINDOW_FOCUS_FAILED;
        fc.canRecover = true;
        fc.safeRecoveryAction = L"retry_focus_once";
        fc.recommendedUserAction = L"Ensure the target window is not minimized and can receive focus. Close any full-screen applications that may steal focus.";
    } else if (errorCode == L"SAFETY_POLICY_DENIED") {
        fc.category = FailureCategory::SAFETY_POLICY_DENIED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Add the window title and process to the project config\\safety.conf allowed_titles and allowed_processes, then restart the task.";
    } else if (errorCode == L"USER_TAKEOVER_REQUIRED") {
        fc.category = FailureCategory::USER_TAKEOVER_REQUIRED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation and let the user take over the desktop session.";
    } else if (errorCode == L"CREDENTIAL_INPUT_DETECTED") {
        fc.category = FailureCategory::CREDENTIAL_INPUT_DETECTED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. The user must handle credential entry manually.";
    } else if (errorCode == L"CAPTCHA_DETECTED") {
        fc.category = FailureCategory::CAPTCHA_DETECTED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. The user must handle captcha or verification manually.";
    } else if (errorCode == L"ANTI_AUTOMATION_DETECTED") {
        fc.category = FailureCategory::ANTI_AUTOMATION_DETECTED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation because anti-automation or AI-detection controls were detected.";
    } else if (errorCode == L"ANTI_CHEAT_DETECTED") {
        fc.category = FailureCategory::ANTI_CHEAT_DETECTED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation because anti-cheat protected software is unsupported.";
    } else if (errorCode == L"LOOP_GUARD_STOP") {
        fc.category = FailureCategory::LOOP_GUARD_STOP;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation because the loop guard detected unsafe repetition or no progress.";
    } else if (errorCode == L"REPEATED_ACTION_LIMIT") {
        fc.category = FailureCategory::LOOP_GUARD_STOP;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. Review the recent repeated actions and resume from the latest checkpoint only after correcting the task plan.";
    } else if (errorCode == L"URL_REDIRECT_LOOP") {
        fc.category = FailureCategory::LOOP_GUARD_STOP;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. Review the URL redirect chain and restart from a stable page URL.";
    } else if (errorCode == L"NO_PROGRESS_DETECTED") {
        fc.category = FailureCategory::LOOP_GUARD_STOP;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. Re-observe the page or app, update selectors, and resume from the latest checkpoint.";
    } else if (errorCode == L"WINDOW_SPAWN_LOOP") {
        fc.category = FailureCategory::LOOP_GUARD_STOP;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. Close unexpected duplicate windows, choose the intended target, and resume from the latest checkpoint.";
    } else if (errorCode == L"SCROLL_NO_PROGRESS") {
        fc.category = FailureCategory::LOOP_GUARD_STOP;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Stop automation. Scrolling did not reveal new content; inspect the current page before retrying.";
    } else if (errorCode == L"LOCATOR_NOT_FOUND") {
        fc.category = FailureCategory::LOCATOR_NOT_FOUND;
        fc.canRecover = true;
        fc.safeRecoveryAction = L"reobserve_ocr_fallback";
        fc.recommendedUserAction = L"Check that the UI element exists and is visible. Try a broader selector (e.g., name_contains instead of name). Use 'observe' to inspect current window state.";
    } else if (errorCode == L"LOCATOR_NOT_UNIQUE") {
        fc.category = FailureCategory::LOCATOR_NOT_UNIQUE;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Add an 'index' field to the selector to disambiguate, or use a more specific selector (e.g., add 'type' filter).";
    } else if (errorCode == L"FIELD_NOT_UNIQUE") {
        fc.category = FailureCategory::LOCATOR_NOT_UNIQUE;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Provide a more specific field_id, label, selector, or option so exactly one form control is selected.";
    } else if (errorCode == L"FIELD_CONFIDENCE_LOW") {
        fc.category = FailureCategory::LOCATOR_NOT_FOUND;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Inspect the form controls and provide an explicit control_type or selector; unknown low-confidence fields are not treated as textboxes.";
    } else if (errorCode == L"OCR_TEXT_NOT_FOUND" || errorCode == L"TEXT_NOT_FOUND") {
        fc.category = FailureCategory::TEXT_NOT_FOUND;
        fc.canRecover = true;
        fc.safeRecoveryAction = L"wait_reobserve_stop";
        fc.recommendedUserAction = L"Wait briefly, re-observe the window, and stop if the requested text is still missing.";
    } else if (errorCode == L"OCR_UNAVAILABLE") {
        fc.category = FailureCategory::OCR_UNAVAILABLE;
        fc.canRecover = true;
        fc.safeRecoveryAction = L"fallback_to_uia_if_available";
        fc.recommendedUserAction = L"OCR is not available on this system. Use UIA selectors instead, or install Windows language pack with OCR support.";
    } else if (errorCode == L"OCR_FAILED") {
        fc.category = FailureCategory::OCR_FAILED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"OCR engine failed. Check that the target window is visible and not obscured. Try UIA selectors as an alternative.";
    } else if (errorCode == L"ASSERTION_FAILED" || errorCode == L"EXPECT_FAILED") {
        fc.category = FailureCategory::EXPECT_FAILED;
        fc.canRecover = true;
        fc.safeRecoveryAction = L"reobserve_and_reexpect_once";
        fc.recommendedUserAction = L"The expected state was not reached. Check the observe output and verify the action had the intended effect. Adjust selector or action parameters.";
    } else if (errorCode == L"CURSOR_MOVE_FAILED" || errorCode == L"SEND_INPUT_FAILED" || errorCode == L"SCREENSHOT_FAILED") {
        fc.category = FailureCategory::ACTION_FAILED;
        fc.canRecover = false;
        fc.recommendedUserAction = L"System-level input or capture failure. Check that no other application is blocking input APIs.";
    } else if (errorCode == L"CASE_DURATION_LIMIT_EXCEEDED" || errorCode == L"TIMEOUT") {
        fc.category = FailureCategory::TIMEOUT;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Task exceeded time budget. Increase max_duration_ms or split task into smaller steps.";
    } else if (!errorCode.empty()) {
        fc.category = FailureCategory::UNKNOWN_ERROR;
        fc.canRecover = false;
        fc.recommendedUserAction = L"Unexpected error. Review the full report and logs.";
    } else {
        fc.category = FailureCategory::NONE;
    }
    return fc;
}

// ===================================================================
// Task JSON Parser
// ===================================================================
bool ParseTaskJson(const std::wstring& content, TaskDefinition& task, std::wstring& error) {
    std::wstring json = content;

    task.version = JsonGetInt(json, L"version", 1);
    task.name = JsonGetString(json, L"name");
    task.permissionMode = JsonGetString(json, L"permission_mode");
    if (task.permissionMode.empty()) task.permissionMode = DefaultPermissionModeName();
    task.fullAccessSessionId = JsonGetString(json, L"full_access_session_id");

    std::wstring targetObj = JsonGetObject(json, L"target");
    task.target.title = JsonGetString(targetObj, L"title");
    task.target.process = JsonGetString(targetObj, L"process");

    std::wstring budgetObj = JsonGetObject(json, L"budget");
    task.budget.maxSteps = JsonGetInt(budgetObj, L"max_steps", 50);
    task.budget.maxDurationMs = JsonGetInt(budgetObj, L"max_duration_ms", 120000);
    task.budget.maxRecoveries = JsonGetInt(budgetObj, L"max_recoveries", 2);
    std::wstring checkpointObj = JsonGetObject(json, L"checkpoint");
    if (!checkpointObj.empty()) {
        task.checkpoint.enabled = JsonGetBool(checkpointObj, L"enabled", true);
        task.checkpoint.intervalMs = JsonGetInt(checkpointObj, L"interval_ms", 300000);
        task.checkpoint.cleanupOnEnd = JsonGetBool(checkpointObj, L"cleanup_on_end", true);
    }
    std::wstring loopGuardObj = JsonGetObject(json, L"loop_guard");
    if (!loopGuardObj.empty()) {
        task.loopGuard.repeatedActionLimit = JsonGetInt(loopGuardObj, L"repeated_action_limit", task.loopGuard.repeatedActionLimit);
        task.loopGuard.urlRedirectLimit = JsonGetInt(loopGuardObj, L"url_redirect_limit", task.loopGuard.urlRedirectLimit);
        task.loopGuard.noProgressLimit = JsonGetInt(loopGuardObj, L"no_progress_limit", task.loopGuard.noProgressLimit);
        task.loopGuard.windowSpawnLimit = JsonGetInt(loopGuardObj, L"window_spawn_limit", task.loopGuard.windowSpawnLimit);
        task.loopGuard.scrollNoProgressLimit = JsonGetInt(loopGuardObj, L"scroll_no_progress_limit", task.loopGuard.scrollNoProgressLimit);
    }
    task.allowUnrestrictedDesktop = JsonGetBool(json, L"allow_unrestricted_desktop", false);

    std::wstring stepsArr = JsonGetArray(json, L"steps");
    auto stepObjs = JsonGetObjectArray(stepsArr);
    for (const auto& stepObj : stepObjs) {
        task.steps.push_back(ParseTaskStepObject(stepObj));
    }

    if (task.name.empty()) { error = L"Task name is required."; return false; }
    if (task.target.title.empty()) { error = L"Task target title is required."; return false; }
    if (task.steps.empty()) { error = L"Task must have at least one step."; return false; }
    if (!ExpandTaskTemplates(task, error)) { return false; }
    if (task.steps.empty()) { error = L"Task must have at least one expanded step."; return false; }

    return true;
}

// ===================================================================
// Task Step Executor
// ===================================================================
struct StepExecContext {
    HWND hwnd = nullptr;
    WindowInfo window;
    WindowSessionInfo session;
    std::wstring targetTitle;
    std::wstring targetProcess;
    PermissionMode permissionMode = PermissionMode::DEFAULT;
    std::wstring fullAccessSessionId;
    TaskResult& result;
    TaskBudget& budget;
    int recoveryCount = 0;
};

struct LoopGuardState {
    std::wstring lastActionKey;
    int repeatedActionCount = 0;
    std::wstring lastUrl;
    int repeatedUrlCount = 0;
    std::wstring lastObservedSummary;
    int noProgressCount = 0;
    std::wstring lastWindowOpenKey;
    int windowOpenCount = 0;
    std::wstring lastScrollSummary;
    int scrollNoProgressCount = 0;
    ULONGLONG lastCheckpointTick = 0;
    std::vector<std::wstring> recentActions;
};

std::wstring JsonStringArray(const std::vector<std::wstring>& values) {
    std::wstringstream ss;
    ss << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) ss << L",";
        ss << JsonString(values[i]);
    }
    ss << L"]";
    return ss.str();
}

void RecordRecoveryDecision(
    TaskResult& result,
    TaskStepResult* stepResult,
    int stepIndex,
    const std::wstring& stepName,
    const RecoveryStrategy& strategy,
    int attempt,
    const std::wstring& recordResult,
    const std::wstring& details) {
    RecoveryAttemptRecord record;
    record.stepIndex = stepIndex;
    record.stepName = stepName;
    record.errorCode = strategy.errorCode;
    record.strategyName = strategy.strategyName;
    record.attempt = attempt;
    record.result = recordResult;
    record.details = details;
    record.strategySteps = strategy.steps;
    result.recoveryAttempts.push_back(record);
    if (stepResult) {
        stepResult->recoveryAttempts.push_back(record);
    }
}

std::wstring SelectorValueAfterPrefix(const std::wstring& selector, const std::wstring& prefix) {
    size_t pos = selector.find(prefix);
    if (pos == std::wstring::npos) return L"";
    pos += prefix.size();
    size_t end = selector.find_first_of(L";|", pos);
    if (end == std::wstring::npos) end = selector.size();
    return selector.substr(pos, end - pos);
}

std::wstring TextProbeFromSelector(const TaskStep& step) {
    if (!step.text.empty()) return step.text;
    std::wstring probe = SelectorValueAfterPrefix(step.selector, L"uia:name_contains=");
    if (!probe.empty()) return probe;
    probe = SelectorValueAfterPrefix(step.selector, L"uia:name=");
    if (!probe.empty()) return probe;
    probe = SelectorValueAfterPrefix(step.selector, L"text:contains=");
    if (!probe.empty()) return probe;
    probe = SelectorValueAfterPrefix(step.selector, L"text:exact=");
    return probe;
}

std::wstring LowerCopy(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), towlower);
    return value;
}

std::wstring StableContentHash(const std::wstring& value) {
    unsigned long long hash = 1469598103934665603ull;
    for (wchar_t ch : value) {
        hash ^= static_cast<unsigned long long>(ch);
        hash *= 1099511628211ull;
    }
    std::wstringstream ss;
    ss << std::hex << std::setw(16) << std::setfill(L'0') << hash;
    return ss.str();
}

bool CommunicationSensitiveStop(const TaskStep& step, std::wstring& errorCode, std::wstring& message) {
    std::wstring haystack = LowerCopy(step.channel + L" " + step.communicationTarget + L" " + step.subject + L" " + step.observedSummary);
    if (haystack.find(L"captcha") != std::wstring::npos || haystack.find(L"verification code") != std::wstring::npos) {
        errorCode = L"CAPTCHA_DETECTED";
        message = L"Communication flow encountered captcha or verification challenge.";
        return true;
    }
    if (haystack.find(L"login") != std::wstring::npos || haystack.find(L"account verification") != std::wstring::npos) {
        errorCode = L"USER_TAKEOVER_REQUIRED";
        message = L"Communication flow requires login or account verification.";
        return true;
    }
    if (haystack.find(L"password") != std::wstring::npos || haystack.find(L"credential") != std::wstring::npos) {
        errorCode = L"CREDENTIAL_INPUT_DETECTED";
        message = L"Communication flow encountered credential input.";
        return true;
    }
    if (haystack.find(L"bot detection") != std::wstring::npos || haystack.find(L"automation restricted") != std::wstring::npos) {
        errorCode = L"ANTI_AUTOMATION_DETECTED";
        message = L"Communication flow encountered anti-automation controls.";
        return true;
    }
    return false;
}

std::wstring CommunicationActionJson(const CommunicationAction& action) {
    std::wstringstream json;
    json << L"{\"channel\":" << JsonString(action.channel)
         << L",\"target\":" << JsonString(action.target)
         << L",\"subject\":" << JsonString(action.subject)
         << L",\"content_summary\":" << JsonString(action.contentSummary)
         << L",\"content_hash\":" << JsonString(action.contentHash)
         << L",\"user_requested_send\":" << (action.userRequestedSend ? L"true" : L"false")
         << L",\"send_action_performed\":" << (action.sendActionPerformed ? L"true" : L"false")
         << L",\"permission_mode\":" << JsonString(action.permissionMode)
         << L",\"risk_level\":" << JsonString(action.riskLevel)
         << L"}";
    return json.str();
}

std::wstring StepActionKey(const TaskStep& step) {
    std::wstring action = step.action.empty() ? step.type : step.action;
    return step.type + L"|" + action + L"|" + step.selector + L"|" + step.keys + L"|" + step.value;
}

bool IsSubmitSendOrWindowSwitch(const TaskStep& step) {
    std::wstring action = step.action;
    std::transform(action.begin(), action.end(), action.begin(), towlower);
    return action.find(L"submit") != std::wstring::npos ||
           action.find(L"send") != std::wstring::npos ||
           action.find(L"switch_window") != std::wstring::npos ||
           step.type == L"communication_step" ||
           (step.type == L"coding" && action == L"submit_if_explicitly_allowed");
}

void AddRecentAction(LoopGuardState& guard, const std::wstring& action) {
    if (action.empty()) return;
    guard.recentActions.push_back(action);
    if (guard.recentActions.size() > 8) {
        guard.recentActions.erase(guard.recentActions.begin());
    }
}

bool WriteCheckpointTempFile(SessionCheckpoint& cp) {
    std::wstring dir = ArtifactsPath(L"session_checkpoints");
    CreateDirectoryW(dir.c_str(), nullptr);
    cp.tempPath = dir + L"\\" + cp.checkpointId + L".checkpoint.tmp.json";
    FILE* f = nullptr;
    if (_wfopen_s(&f, cp.tempPath.c_str(), L"w, ccs=UTF-8") != 0 || !f) return false;
    fwprintf(f, L"{\"checkpoint_id\":%ls", JsonString(cp.checkpointId).c_str());
    fwprintf(f, L",\"timestamp\":%ls", JsonString(cp.timestamp).c_str());
    fwprintf(f, L",\"permission_mode\":%ls", JsonString(cp.permissionMode).c_str());
    fwprintf(f, L",\"task_id\":%ls", JsonString(cp.taskId).c_str());
    fwprintf(f, L",\"step_index\":%d", cp.stepIndex);
    fwprintf(f, L",\"window_title\":%ls", JsonString(cp.windowTitle).c_str());
    fwprintf(f, L",\"process_name\":%ls", JsonString(cp.processName).c_str());
    fwprintf(f, L",\"url\":%ls", JsonString(cp.url).c_str());
    fwprintf(f, L",\"screenshot_path\":%ls", JsonString(cp.screenshotPath).c_str());
    fwprintf(f, L",\"observed_summary\":%ls", JsonString(cp.observedSummary).c_str());
    fwprintf(f, L",\"recent_actions\":%ls", JsonStringArray(cp.recentActions).c_str());
    fwprintf(f, L",\"form_state_summary\":%ls", JsonString(cp.formStateSummary).c_str());
    fwprintf(f, L",\"suggested_recovery_actions\":%ls}", JsonStringArray(cp.suggestedRecoveryActions).c_str());
    fclose(f);
    return true;
}

void CreateSessionCheckpoint(
    StepExecContext& ctx,
    const TaskDefinition& task,
    const TaskStep* step,
    int stepIndex,
    LoopGuardState& guard,
    const std::wstring& reason) {
    if (!task.checkpoint.enabled) return;

    SessionCheckpoint cp;
    cp.checkpointId = L"cp_" + std::to_wstring(GetTickCount64()) + L"_" + std::to_wstring(ctx.result.checkpoints.size() + 1);
    cp.timestamp = CurrentTimestamp();
    cp.permissionMode = PermissionModeName(ctx.permissionMode);
    cp.taskId = task.name;
    cp.stepIndex = stepIndex;
    cp.windowTitle = step && !step->windowTitle.empty() ? step->windowTitle : ctx.session.window.title;
    if (cp.windowTitle.empty()) cp.windowTitle = ctx.targetTitle;
    cp.processName = ctx.targetProcess;
    cp.url = step ? step->currentUrl : L"";
    cp.screenshotPath = L"";
    cp.observedSummary = reason;
    if (step && !step->observedSummary.empty()) {
        cp.observedSummary += L"; " + step->observedSummary;
    }
    cp.recentActions = guard.recentActions;
    cp.formStateSummary = L"not captured";
    cp.suggestedRecoveryActions = {
        L"Re-observe the target window before resuming.",
        L"Resume from the step after this checkpoint only if the user goal is still valid.",
        L"Do not assume submitted, sent, or remote state can be rolled back."
    };
    WriteCheckpointTempFile(cp);
    ctx.result.lastCheckpointId = cp.checkpointId;
    ctx.result.checkpoints.push_back(cp);
    guard.lastCheckpointTick = GetTickCount64();
}

void CleanupTemporaryCheckpoints(TaskResult& result, bool cleanupOnEnd) {
    bool allCleaned = true;
    for (auto& cp : result.checkpoints) {
        if (!cp.tempPath.empty() && cleanupOnEnd) {
            if (DeleteFileW(cp.tempPath.c_str()) || GetLastError() == ERROR_FILE_NOT_FOUND) {
                cp.temporaryCleaned = true;
            } else {
                allCleaned = false;
            }
        } else if (cp.tempPath.empty() || !cleanupOnEnd) {
            cp.temporaryCleaned = !cleanupOnEnd;
        }
    }
    result.temporaryCheckpointsCleaned = allCleaned;
}

bool CheckLoopGuard(
    const TaskDefinition& task,
    const TaskStep& step,
    LoopGuardState& guard,
    TaskStepResult& sr,
    int executedSteps,
    ULONGLONG taskStart) {
    if (executedSteps >= task.budget.maxSteps) {
        sr.failure = ClassifyFailure(L"LOOP_GUARD_STOP", L"Task exceeded max_steps loop guard.");
        return false;
    }
    if (ElapsedMs(taskStart) > task.budget.maxDurationMs) {
        sr.failure = ClassifyFailure(L"LOOP_GUARD_STOP", L"Task exceeded max_duration_ms loop guard.");
        return false;
    }

    if (!step.currentUrl.empty()) {
        if (step.currentUrl == guard.lastUrl) ++guard.repeatedUrlCount;
        else { guard.lastUrl = step.currentUrl; guard.repeatedUrlCount = 1; }
        if (task.loopGuard.urlRedirectLimit > 0 && guard.repeatedUrlCount > task.loopGuard.urlRedirectLimit) {
            sr.failure = ClassifyFailure(L"URL_REDIRECT_LOOP", L"URL repeated beyond loop guard threshold: " + step.currentUrl);
            return false;
        }
    }

    std::wstring actionKey = StepActionKey(step);
    if (step.type != L"observe" && step.type != L"checkpoint") {
        if (actionKey == guard.lastActionKey) ++guard.repeatedActionCount;
        else { guard.lastActionKey = actionKey; guard.repeatedActionCount = 1; }
        if (task.loopGuard.repeatedActionLimit > 0 && guard.repeatedActionCount > task.loopGuard.repeatedActionLimit) {
            sr.failure = ClassifyFailure(L"REPEATED_ACTION_LIMIT", L"The same action repeated beyond loop guard threshold.");
            return false;
        }
    }

    std::wstring windowKey = step.windowTitle.empty() ? step.observedSummary : step.windowTitle;
    if (step.action == L"open_window" || step.observedSummary.find(L"window_open") != std::wstring::npos) {
        if (windowKey == guard.lastWindowOpenKey) ++guard.windowOpenCount;
        else { guard.lastWindowOpenKey = windowKey; guard.windowOpenCount = 1; }
        if (task.loopGuard.windowSpawnLimit > 0 && guard.windowOpenCount > task.loopGuard.windowSpawnLimit) {
            sr.failure = ClassifyFailure(L"WINDOW_SPAWN_LOOP", L"Window open/spawn repeated beyond loop guard threshold.");
            return false;
        }
    }

    if (step.action == L"scroll" && !step.observedSummary.empty()) {
        if (step.observedSummary == guard.lastScrollSummary) ++guard.scrollNoProgressCount;
        else { guard.lastScrollSummary = step.observedSummary; guard.scrollNoProgressCount = 1; }
        if (task.loopGuard.scrollNoProgressLimit > 0 && guard.scrollNoProgressCount > task.loopGuard.scrollNoProgressLimit) {
            sr.failure = ClassifyFailure(L"SCROLL_NO_PROGRESS", L"Repeated scroll did not reveal new content.");
            return false;
        }
    }

    if (!step.observedSummary.empty()) {
        if (step.observedSummary == guard.lastObservedSummary) ++guard.noProgressCount;
        else { guard.lastObservedSummary = step.observedSummary; guard.noProgressCount = 1; }
        if (task.loopGuard.noProgressLimit > 0 && guard.noProgressCount > task.loopGuard.noProgressLimit) {
            sr.failure = ClassifyFailure(L"NO_PROGRESS_DETECTED", L"Observed summary did not change beyond loop guard threshold.");
            return false;
        }
    }

    return true;
}

bool EnsureWindowSession(StepExecContext& ctx, TaskStepResult& r) {
    WindowSessionResult session = ctx.session.window.hwnd
        ? ReconfirmWindowSession(ctx.session)
        : ResolveWindowSession(ctx.targetTitle, ctx.targetProcess);
    if (!session.ok) {
        r.failure = ClassifyFailure(session.errorCode.empty() ? L"UNKNOWN_ERROR" : session.errorCode, session.errorMessage);
        if (r.windowSessionBefore.empty()) {
            r.windowSessionBefore = session.dataJson;
        }
        return false;
    }
    ctx.session = session.session;
    ctx.window = session.session.window;
    ctx.hwnd = session.session.window.hwnd;
    if (r.windowSessionBefore.empty()) {
        r.windowSessionBefore = WindowSessionJson(ctx.session);
    }
    return true;
}

bool CaptureObservation(StepExecContext& ctx, std::wstring& jsonSlot, std::wstring& screenshotSlot, FailureClassification& failure, std::wstring* windowSessionSlot = nullptr) {
    ObserveResult obs = ObserveWindow(ctx.targetTitle, true, true, 80, ctx.targetProcess);
    jsonSlot = obs.ok ? obs.dataJson : L"";
    if (!obs.ok) {
        failure = ClassifyFailure(obs.errorCode.empty() ? L"UNKNOWN_ERROR" : obs.errorCode, obs.errorMessage);
        return false;
    }
    ctx.window = obs.target;
    ctx.hwnd = obs.target.hwnd;
    WindowSessionResult session = ResolveWindowSession(ctx.targetTitle, ctx.targetProcess);
    if (session.ok) {
        ctx.session = session.session;
        if (windowSessionSlot) {
            *windowSessionSlot = WindowSessionJson(ctx.session);
        }
    }
    if (!obs.screenshotPath.empty()) ctx.result.screenshots.push_back(obs.screenshotPath);
    screenshotSlot = obs.screenshotPath;
    return true;
}

bool ExecuteObserveStep(StepExecContext& ctx, TaskStepResult& r) {
    return CaptureObservation(ctx, r.observeBefore, r.screenshotPath, r.failure, &r.windowSessionBefore);
}

bool EnsureTargetObserved(StepExecContext& ctx, TaskStepResult& r) {
    if (!EnsureWindowSession(ctx, r)) return false;
    return true;
}

bool EnforceTaskSafety(StepExecContext& ctx, TaskStepResult& r, const std::wstring& action) {
    if (!EnsureTargetObserved(ctx, r)) return false;

    SafetyPolicy policy = LoadSafetyPolicy();
    SafetyManifest manifest = LoadSafetyManifest();
    std::wstring actualProcess = ctx.targetProcess.empty() ? ProcessNameForPid(ctx.window.pid) : ctx.targetProcess;
    std::wstring actualTitle = ctx.window.title.empty() ? ctx.targetTitle : ctx.window.title;
    PermissionDecision permission = EvaluatePermissionRequest(manifest, actualTitle, actualProcess, action, ctx.permissionMode, ctx.fullAccessSessionId);
    if (!permission.allow) {
        r.failure = ClassifyFailure(permission.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permission.errorCode,
                                    permission.reason.empty() ? L"Permission manager denied this task action." : permission.reason);
        return false;
    }

    PolicyCheckDecision policyDecision = EvaluatePolicyCheck(
        policy,
        manifest,
        actualTitle,
        actualProcess,
        action,
        L"",
        permission.relaxConfiguredBoundary,
        PermissionModeName(ctx.permissionMode),
        ctx.fullAccessSessionId,
        permission.fullAccessSessionActive,
        permission.fullAccessSessionExpired,
        permission.fullAccessScope);
    if (!policyDecision.allow) {
        r.failure = ClassifyFailure(policyDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : policyDecision.errorCode,
                                    policyDecision.reason.empty() ? L"Safety policy denied this task action." : policyDecision.reason);
        return false;
    }
    return true;
}

bool ExecuteLocateStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!EnsureTargetObserved(ctx, r)) return false;
    if (step.selector.rfind(L"text:", 0) == 0 && !EnforceTaskSafety(ctx, r, L"locate")) return false;

    SelectorResult sr = LocateSelector(ctx.hwnd, step.selector);
    r.locateResult = sr.dataJson;
    if (!sr.ok) {
        r.failure = ClassifyFailure(sr.errorCode.empty() ? L"UNKNOWN_ERROR" : sr.errorCode, sr.errorMessage);
        return false;
    }
    return true;
}

bool ExecuteActStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!CaptureObservation(ctx, r.observeBefore, r.screenshotPath, r.failure, &r.windowSessionBefore)) return false;
    if (!EnforceTaskSafety(ctx, r, step.action.empty() ? L"act" : step.action)) return false;
    if (!IsAllowedMoveFallback(step.moveFallback)) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"Unsupported move fallback. Only fast-human is allowed.");
        r.actionResult = L"{\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }

    ActionResult foreground = FocusTargetWindow(ctx.hwnd);
    if (!foreground.ok) {
        r.failure = ClassifyFailure(foreground.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : foreground.errorCode, foreground.error);
        r.actionResult = L"{\"ok\":false,\"error_code\":\"" + JsonEscape(r.failure.rawErrorCode) + L"\"}";
        return false;
    }
    WindowSessionResult focusedSession = ResolveWindowSession(ctx.targetTitle, ctx.targetProcess);
    if (focusedSession.ok) {
        ctx.session = focusedSession.session;
        ctx.window = focusedSession.session.window;
        ctx.hwnd = focusedSession.session.window.hwnd;
        r.windowSessionBefore = WindowSessionJson(ctx.session);
    }

    // Reuse existing act logic via LocateSelector + input
    SelectorResult sr = LocateSelector(ctx.hwnd, step.selector);
    r.locateResult = sr.dataJson;
    if (!sr.ok) {
        r.failure = ClassifyFailure(sr.errorCode.empty() ? L"UNKNOWN_ERROR" : sr.errorCode, sr.errorMessage);
        return false;
    }

    bool actionOk = false;
    std::wstring actionErrorCode, actionError;
    std::wstring actionMethod;

    if (step.action == L"focus") {
        ActionResult focused = FocusTargetWindow(ctx.hwnd);
        actionOk = focused.ok; actionErrorCode = focused.errorCode; actionError = focused.error;
        actionMethod = L"focus_window";
    } else if (step.action == L"click" && !IsOperatorRequestedMove(step.moveMode) && sr.locateMethod == L"uia" && sr.uiaInvokeCandidate && !sr.elementName.empty()) {
        UiaPatternActionResult invoked = InvokeUiaElementByName(ctx.hwnd, sr.elementName);
        if (invoked.ok && invoked.patternAvailable) { actionOk = true; actionMethod = L"invoke_pattern"; }
    }
    if (!actionOk && step.action == L"type" && sr.locateMethod == L"uia" && sr.uiaValueCandidate && !sr.elementName.empty()) {
        UiaPatternActionResult typed = SetUiaElementValueByName(ctx.hwnd, sr.elementName, step.text);
        if (typed.ok && typed.patternAvailable) { actionOk = true; actionMethod = L"value_pattern"; }
    }
    if (!actionOk && step.action == L"click") {
        ClickResult click = ClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, step.moveMode, 0, step.profilePath, step.allowSyntheticProfile);
        if (!click.ok && IsOperatorRequestedMove(step.moveMode) && step.moveFallback == L"fast-human" && IsMotionProfileFailure(click.errorCode)) {
            click = ClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, L"fast-human", 0);
        }
        actionOk = click.ok; actionErrorCode = click.errorCode; actionError = click.error;
        actionMethod = L"mouse_click";
    } else if (!actionOk && step.action == L"double-click") {
        ClickResult click = DoubleClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, step.moveMode, 0, step.profilePath, step.allowSyntheticProfile);
        if (!click.ok && IsOperatorRequestedMove(step.moveMode) && step.moveFallback == L"fast-human" && IsMotionProfileFailure(click.errorCode)) {
            click = DoubleClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, L"fast-human", 0);
        }
        actionOk = click.ok; actionErrorCode = click.errorCode; actionError = click.error;
        actionMethod = L"mouse_double_click";
    } else if (!actionOk && step.action == L"right-click") {
        ClickResult click = RightClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, step.moveMode, 0, step.profilePath, step.allowSyntheticProfile);
        if (!click.ok && IsOperatorRequestedMove(step.moveMode) && step.moveFallback == L"fast-human" && IsMotionProfileFailure(click.errorCode)) {
            click = RightClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, L"fast-human", 0);
        }
        actionOk = click.ok; actionErrorCode = click.errorCode; actionError = click.error;
        actionMethod = L"mouse_right_click";
    } else if (!actionOk && step.action == L"type") {
        ClickResult click = ClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, step.moveMode, 0, step.profilePath, step.allowSyntheticProfile);
        if (!click.ok && IsOperatorRequestedMove(step.moveMode) && step.moveFallback == L"fast-human" && IsMotionProfileFailure(click.errorCode)) {
            click = ClickClientPoint(ctx.hwnd, sr.clientX, sr.clientY, L"fast-human", 0);
        }
        if (!click.ok) { actionErrorCode = click.errorCode; actionError = click.error; }
        else {
            ActionResult selAll = SendHotkey(ctx.hwnd, L"CTRL+A");
            if (!selAll.ok) { actionErrorCode = selAll.errorCode; actionError = selAll.error; }
            else {
                TypeResult typed = TypeText(ctx.hwnd, step.text, L"human", -1);
                actionOk = typed.ok; actionErrorCode = typed.errorCode; actionError = typed.error;
            }
        }
        actionMethod = L"mouse_center_type";
    }

    std::wstringstream actJson;
    actJson << L"{\"action\":" << JsonString(step.action)
            << L",\"action_method\":" << JsonString(actionMethod)
            << L",\"window_session\":" << (r.windowSessionBefore.empty() ? L"null" : r.windowSessionBefore)
            << L",\"focus_verified\":" << (foreground.focusVerified ? L"true" : L"false")
            << L",\"move_mode\":" << JsonString(step.moveMode)
            << L",\"fallback\":" << JsonString(step.moveFallback)
            << L",\"profile\":" << JsonString(step.profilePath)
            << L",\"allow_synthetic_profile\":" << (step.allowSyntheticProfile ? L"true" : L"false")
            << L",\"ok\":" << (actionOk ? L"true" : L"false") << L"}";
    r.actionResult = actJson.str();

    if (!actionOk) {
        r.failure = ClassifyFailure(actionErrorCode.empty() ? L"ACTION_FAILED" : actionErrorCode, actionError);
        return false;
    }

    FailureClassification afterFailure;
    std::wstring afterShot;
    CaptureObservation(ctx, r.observeAfter, afterShot, afterFailure, &r.windowSessionAfter);

    return true;
}

struct CodingLiveExecution {
    bool requested = false;
    bool performed = false;
    std::wstring actionKind;
    std::wstring selector;
    std::wstring resultText;
    std::wstring resultState;
    std::wstring locateJson;
    std::wstring actionJson;
};

std::wstring NormalizeCodingResultStateFromText(const std::wstring& raw) {
    std::wstring text = LowerCopy(raw);
    if (text.empty()) return L"UNKNOWN_RESULT";
    if (text.find(L"compile error") != std::wstring::npos || text.find(L"compilation error") != std::wstring::npos || text.find(L"compile_error") != std::wstring::npos) return L"COMPILE_ERROR";
    if (text.find(L"runtime error") != std::wstring::npos || text.find(L"runtime_error") != std::wstring::npos) return L"RUNTIME_ERROR";
    if (text.find(L"wrong answer") != std::wstring::npos || text.find(L"wrong_answer") != std::wstring::npos) return L"WRONG_ANSWER";
    if (text.find(L"time limit") != std::wstring::npos || text.find(L"time_limit") != std::wstring::npos || text.find(L"timeout") != std::wstring::npos) return L"TIME_LIMIT";
    if (text.find(L"accepted") != std::wstring::npos) return L"ACCEPTED";
    if (text.find(L"sample pass") != std::wstring::npos || text.find(L"sample_pass") != std::wstring::npos || text.find(L"samples passed") != std::wstring::npos || text.find(L"sample passed") != std::wstring::npos) return L"SAMPLE_PASS";
    return L"UNKNOWN_RESULT";
}

std::wstring RedactExactText(const std::wstring& value, const std::wstring& secret) {
    if (value.empty() || secret.empty()) return value;
    std::wstring redacted = value;
    size_t pos = 0;
    while ((pos = redacted.find(secret, pos)) != std::wstring::npos) {
        redacted.replace(pos, secret.size(), L"[code_redacted]");
        pos += 15;
    }
    return redacted;
}


bool ExecuteFormActionStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!EnsureWindowSession(ctx, r)) return false;
    if (!EnforceTaskSafety(ctx, r, L"form_action")) return false;

    FormControl control;
    FormControlResult resolved;
    if (!step.htmlPath.empty()) {
        resolved = ResolveFormControlFromHtml(step.htmlPath, step.fieldId, step.label, 0.50);
        r.locateResult = L"{\"form_control\":" + FormControlJson(resolved.control)
            + L",\"candidates\":" + FormControlCandidatesJson(resolved.candidates)
            + L",\"match_count\":" + std::to_wstring(resolved.matchCount)
            + L"}";
        if (!resolved.ok) {
            r.failure = ClassifyFailure(resolved.errorCode.empty() ? L"UNKNOWN_ERROR" : resolved.errorCode, resolved.errorMessage);
            r.actionResult = L"{\"ok\":false,\"error_code\":\"" + JsonEscape(r.failure.rawErrorCode) + L"\",\"field_id\":" + JsonString(step.fieldId) + L"}";
            return false;
        }
        control = resolved.control;
    } else {
        control.fieldId = step.fieldId;
        control.label = step.label;
        control.controlType = step.controlType.empty() ? L"unknown" : step.controlType;
        control.source = L"task_explicit";
        control.confidence = step.controlType.empty() ? 0.40 : 0.90;
        control.recommendedAction = RecommendedFormAction(control.controlType);
        r.locateResult = L"{\"form_control\":" + FormControlJson(control) + L",\"match_count\":1}";
        if (control.controlType == L"unknown" || control.recommendedAction == L"stop") {
            std::wstring code = (control.controlType == L"captcha" || control.controlType == L"challenge" || control.controlType == L"captcha/challenge")
                ? L"CAPTCHA_DETECTED"
                : L"FIELD_CONFIDENCE_LOW";
            r.failure = ClassifyFailure(code, L"Form control requires user confirmation or stop.");
            r.actionResult = L"{\"ok\":false,\"error_code\":\"" + JsonEscape(r.failure.rawErrorCode) + L"\",\"field_id\":" + JsonString(step.fieldId) + L"}";
            return false;
        }
    }

    std::wstring mapped = control.recommendedAction;
    std::wstring effectiveValue = !step.value.empty() ? step.value : (!step.option.empty() ? step.option : step.text);
    std::wstringstream actionJson;
    actionJson << L"{\"action\":\"form_action\""
               << L",\"field_id\":" << JsonString(control.fieldId)
               << L",\"label\":" << JsonString(control.label)
               << L",\"control_type\":" << JsonString(control.controlType)
               << L",\"recommended_action\":" << JsonString(mapped)
               << L",\"value_present\":" << (!effectiveValue.empty() ? L"true" : L"false")
               << L",\"source\":" << JsonString(control.source)
               << L",\"confidence\":" << control.confidence
               << L",\"ok\":true}";
    r.actionResult = actionJson.str();
    return true;
}

bool ExecuteDecisionStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!EnsureWindowSession(ctx, r)) return false;
    // Gate the whole decision step on the content_decision capability.
    // DEFAULT mode denies this with SAFETY_POLICY_DENIED; FULL_ACCESS requires a
    // valid unlocked session id. This reuses the existing PermissionManager and
    // SafetyPolicy paths without loosening any boundary.
    if (!EnforceTaskSafety(ctx, r, L"content_decision")) return false;

    if (step.htmlPath.empty()) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"decision task step requires html_path for page context.");
        r.actionResult = L"{\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }
    if (step.fieldId.empty() && step.label.empty()) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"decision task step requires field_id or label.");
        r.actionResult = L"{\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }
    if (step.userGoal.empty()) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"decision task step requires an explicit user_goal.");
        r.actionResult = L"{\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }

    DecisionInput input;
    input.userGoal = step.userGoal;
    input.permissionMode = PermissionModeName(ctx.permissionMode);
    input.currentWindow = ctx.window.title.empty() ? ctx.targetTitle : ctx.window.title;
    input.currentUrl = step.currentUrl;
    input.htmlPath = step.htmlPath;
    input.fieldId = step.fieldId;
    input.label = step.label;
    input.controlTypeHint = step.controlType;
    input.value = step.value;
    input.option = step.option;
    input.text = step.text;
    input.allowSubmit = step.allowSubmit;
    input.minConfidence = step.minConfidence;

    DecisionEvalResult eval = EvaluateDecision(input);
    r.decisionContext = DecisionTaskContextJson(eval.context);
    r.decisionRecord = DecisionRecordJson(eval.record);
    r.locateResult = L"{\"decision_context\":" + r.decisionContext
        + L",\"decision_record\":" + r.decisionRecord + L"}";

    if (!eval.ok) {
        r.failure = ClassifyFailure(eval.errorCode.empty() ? L"FIELD_CONFIDENCE_LOW" : eval.errorCode, eval.errorMessage);
        r.actionResult = L"{\"action\":\"decision\",\"ok\":false,\"error_code\":\""
            + JsonEscape(r.failure.rawErrorCode) + L"\",\"field_id\":" + JsonString(step.fieldId) + L"}";
        return false;
    }

    std::wstringstream actionJson;
    actionJson << L"{\"action\":\"decision\""
               << L",\"decision_type\":" << JsonString(eval.record.decisionType)
               << L",\"selected_action\":" << JsonString(eval.record.selectedAction)
               << L",\"control_type\":" << JsonString(eval.record.controlType)
               << L",\"source\":" << JsonString(eval.record.source)
               << L",\"user_goal_preserved\":" << (eval.record.userGoalPreserved ? L"true" : L"false")
               << L",\"confidence\":" << std::fixed << std::setprecision(2) << eval.record.confidence
               << L",\"safety_check_result\":" << JsonString(eval.record.safetyCheckResult)
               << L",\"ok\":true}";
    r.actionResult = actionJson.str();
    return true;
}


bool ExecuteCommunicationStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!EnforceTaskSafety(ctx, r, L"communication")) return false;

    std::wstring errorCode;
    std::wstring errorMessage;
    if (CommunicationSensitiveStop(step, errorCode, errorMessage)) {
        r.failure = ClassifyFailure(errorCode, errorMessage);
        r.actionResult = L"{\"action\":\"communication_step\",\"ok\":false,\"error_code\":" + JsonString(errorCode) + L"}";
        return false;
    }

    std::wstring operation = step.operation.empty() ? L"send_message" : step.operation;
    bool wantsSend = operation == L"send_message" || operation == L"verify_sent_or_stopped";
    if (wantsSend && !step.userRequestedSend) {
        r.failure = ClassifyFailure(L"USER_TAKEOVER_REQUIRED", L"Communication send requires user_requested_send=true from the user task.");
        r.actionResult = L"{\"action\":\"communication_step\",\"ok\":false,\"error_code\":\"USER_TAKEOVER_REQUIRED\"}";
        return false;
    }
    if (wantsSend && step.communicationTarget.empty()) {
        r.failure = ClassifyFailure(L"USER_TAKEOVER_REQUIRED", L"Communication send requires an explicit target from the user task.");
        r.actionResult = L"{\"action\":\"communication_step\",\"ok\":false,\"error_code\":\"USER_TAKEOVER_REQUIRED\"}";
        return false;
    }
    if (wantsSend && (step.communicationTarget.find(L",") != std::wstring::npos || step.communicationTarget.find(L";") != std::wstring::npos)) {
        r.failure = ClassifyFailure(L"USER_TAKEOVER_REQUIRED", L"Communication group or multi-target send requires an explicit reviewed target list; this step accepts one target.");
        r.actionResult = L"{\"action\":\"communication_step\",\"ok\":false,\"error_code\":\"USER_TAKEOVER_REQUIRED\"}";
        return false;
    }

    CommunicationAction action;
    action.channel = step.channel.empty() ? L"local-communication-sim" : step.channel;
    action.target = step.communicationTarget;
    action.subject = step.subject;
    action.contentSummary = step.contentSummary.empty()
        ? (L"content_length=" + std::to_wstring(step.content.size()))
        : step.contentSummary;
    action.contentHash = StableContentHash(step.content);
    action.userRequestedSend = step.userRequestedSend;
    action.sendActionPerformed = wantsSend;
    action.permissionMode = PermissionModeName(ctx.permissionMode);
    action.riskLevel = wantsSend ? L"medium" : L"low";

    r.communicationAction = CommunicationActionJson(action);
    r.actionResult = L"{\"action\":\"communication_step\",\"operation\":" + JsonString(operation)
        + L",\"ok\":true,\"communication_action\":" + r.communicationAction + L"}";

    AppendAuditLine(
        L"communication_step",
        ctx.targetTitle,
        L"ok",
        L"",
        0,
        L"{\"channel\":" + JsonString(action.channel)
            + L",\"target\":" + JsonString(action.target)
            + L",\"subject\":" + JsonString(action.subject)
            + L",\"content_summary\":" + JsonString(action.contentSummary)
            + L",\"content_hash\":" + JsonString(action.contentHash)
            + L",\"send_action_performed\":" + (action.sendActionPerformed ? L"true" : L"false")
            + L",\"permission_mode\":" + JsonString(action.permissionMode) + L"}");
    return true;
}

bool ExecuteCodingStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!EnsureWindowSession(ctx, r)) return false;
    if (!EnforceTaskSafety(ctx, r, L"content_decision")) return false;

    if (step.htmlPath.empty()) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"coding task step requires html_path for local page context.");
        r.actionResult = L"{\"action\":\"coding\",\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }
    if (step.userGoal.empty()) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"coding task step requires an explicit user_goal.");
        r.actionResult = L"{\"action\":\"coding\",\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }

    CodingWorkflowInput input;
    input.htmlPath = step.htmlPath;
    input.userGoal = step.userGoal;
    input.action = step.action.empty() ? L"read_problem" : step.action;
    input.language = step.language;
    input.codeText = step.codeText;
    input.codePath = step.codePath;
    input.allowSubmit = step.allowSubmit;
    input.revisionCount = step.revisionCount;
    input.permissionMode = PermissionModeName(ctx.permissionMode);
    input.currentWindow = ctx.window.title.empty() ? ctx.targetTitle : ctx.window.title;
    input.currentUrl = step.currentUrl;

    if (input.codeText.empty() && !input.codePath.empty()) {
        FileReadResult codeFile = ReadTextFile(input.codePath);
        if (!codeFile.ok) {
            r.failure = ClassifyFailure(codeFile.errorCode.empty() ? L"FILE_READ_FAILED" : codeFile.errorCode, codeFile.error);
            r.actionResult = L"{\"action\":\"coding\",\"ok\":false,\"error_code\":\"FILE_READ_FAILED\"}";
            return false;
        }
        input.codeText = codeFile.content;
    }

    CodingWorkflowEvalResult eval = EvaluateCodingWorkflow(input);
    r.codingContext = CodingWorkflowContextJson(eval.context);
    r.codingRecord = CodingWorkflowRecordJson(eval.record);
    r.locateResult = L"{\"coding_workflow_context\":" + r.codingContext
        + L",\"coding_workflow_record\":" + r.codingRecord + L"}";

    if (!eval.ok) {
        r.failure = ClassifyFailure(eval.errorCode.empty() ? L"UNKNOWN_ERROR" : eval.errorCode, eval.errorMessage);
        r.actionResult = L"{\"action\":\"coding\",\"ok\":false,\"error_code\":"
            + JsonString(r.failure.rawErrorCode) + L"}";
        return false;
    }

    bool liveOk = true;
    std::wstring liveErrorCode;
    if (step.liveExecute) {
        if ((input.action == L"input_code" || input.action == L"revise_code") && step.editorSelector.empty()) {
            liveOk = false;
            liveErrorCode = L"LOCATOR_NOT_FOUND";
        } else if (input.action == L"run_code" && step.runSelector.empty()) {
            liveOk = false;
            liveErrorCode = L"LOCATOR_NOT_FOUND";
        } else if (input.action == L"submit_if_explicitly_allowed" && step.submitSelector.empty()) {
            liveOk = false;
            liveErrorCode = L"LOCATOR_NOT_FOUND";
        }
        if (!liveOk) {
            r.failure = ClassifyFailure(liveErrorCode, L"live_execute requires explicit editor/run/result/submit selectors for the requested coding action.");
            r.actionResult = L"{\"action\":\"coding\",\"ok\":false,\"live_execute\":true,\"error_code\":"
                + JsonString(liveErrorCode) + L"}";
            return false;
        }
    }

    r.actionResult = L"{\"action\":\"coding\",\"workflow_action\":" + JsonString(input.action)
        + L",\"result_state\":" + JsonString(eval.context.resultState)
        + L",\"revision_count\":" + std::to_wstring(eval.record.revisionCount)
        + L",\"submit_clicked\":" + (eval.record.submitClicked ? L"true" : L"false")
        + L",\"live_execute\":" + (step.liveExecute ? L"true" : L"false")
        + L",\"code_redacted\":true,\"ok\":true}";
    return true;
}

bool ExecuteHotkeyStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!CaptureObservation(ctx, r.observeBefore, r.screenshotPath, r.failure, &r.windowSessionBefore)) return false;
    if (!EnforceTaskSafety(ctx, r, L"hotkey")) return false;
    if (step.keys.empty()) {
        r.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"hotkey task step requires keys.");
        r.actionResult = L"{\"ok\":false,\"error_code\":\"INVALID_ARGUMENT\"}";
        return false;
    }

    ActionResult hotkey = SendHotkey(ctx.hwnd, step.keys);
    std::wstringstream actionJson;
    actionJson << L"{\"action\":\"hotkey\""
               << L",\"keys\":" << JsonString(step.keys)
               << L",\"focus_verified\":" << (hotkey.focusVerified ? L"true" : L"false")
               << L",\"ok\":" << (hotkey.ok ? L"true" : L"false") << L"}";
    r.actionResult = actionJson.str();

    if (!hotkey.ok) {
        r.failure = ClassifyFailure(hotkey.errorCode.empty() ? L"ACTION_FAILED" : hotkey.errorCode, hotkey.error);
        return false;
    }
    return true;
}

bool VerifyExpects(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    if (!step.hasExpect) return true;
    if (!EnsureWindowSession(ctx, r)) return false;
    std::wstringstream expectJson;
    expectJson << L"{";
    bool allOk = true;
    bool first = true;

    if (!step.expectSelectorExists.empty()) {
        SelectorResult sr = LocateSelector(ctx.hwnd, step.expectSelectorExists);
        if (!first) expectJson << L","; first = false;
        expectJson << L"\"selector_exists\":{\"ok\":" << (sr.ok ? L"true" : L"false")
                   << L",\"selector\":\"" << JsonEscape(step.expectSelectorExists) << L"\"}";
        if (!sr.ok) allOk = false;
    }
    if (!step.expectTextContains.empty()) {
        OcrTextResult ocr = FindTextInWindow(ctx.hwnd, step.expectTextContains);
        if (!first) expectJson << L","; first = false;
        expectJson << L"\"text_contains\":{\"ok\":" << (ocr.ok ? L"true" : L"false")
                   << L",\"text\":\"" << JsonEscape(step.expectTextContains) << L"\"}";
        if (!ocr.ok) allOk = false;
    }
    if (!step.expectFileContainsPath.empty() && !step.expectFileContainsText.empty()) {
        FileReadResult fr = ReadTextFile(step.expectFileContainsPath);
        bool found = fr.ok && fr.content.find(step.expectFileContainsText) != std::wstring::npos;
        if (!first) expectJson << L","; first = false;
        expectJson << L"\"file_contains\":{\"ok\":" << (found ? L"true" : L"false") << L"}";
        if (!found) allOk = false;
    }
    if (!step.expectWindowTitleContains.empty()) {
        WindowInfo active;
        HWND fg = GetForegroundWindow();
        bool titleOk = false;
        if (fg) {
            int len = GetWindowTextLengthW(fg);
            if (len > 0) {
                std::wstring title(static_cast<size_t>(len) + 1, L'\0');
                GetWindowTextW(fg, &title[0], len + 1);
                title.resize(len);
                std::transform(title.begin(), title.end(), title.begin(), ::towlower);
                std::wstring needle = step.expectWindowTitleContains;
                std::transform(needle.begin(), needle.end(), needle.begin(), ::towlower);
                titleOk = title.find(needle) != std::wstring::npos;
            }
        }
        if (!first) expectJson << L","; first = false;
        expectJson << L"\"window_title_contains\":{\"ok\":" << (titleOk ? L"true" : L"false") << L"}";
        if (!titleOk) allOk = false;
    }
    expectJson << L"}";
    r.expectResult = expectJson.str();

    if (!allOk) {
        r.failure = ClassifyFailure(L"EXPECT_FAILED", L"One or more expect conditions failed.");
        return false;
    }
    return true;
}

bool ExecuteWaitStep(StepExecContext& ctx, TaskStepResult& r, const TaskStep& step) {
    int intervalMs = step.waitMs > 0 ? step.waitMs : 500;
    int timeoutMs = step.timeoutMs > 0 ? step.timeoutMs : intervalMs;

    if (!step.hasExpect) {
        Sleep(static_cast<DWORD>(intervalMs));
        return true;
    }

    ULONGLONG waitStart = GetTickCount64();
    while (true) {
        long long elapsed = ElapsedMs(waitStart);
        int remainingMs = timeoutMs - static_cast<int>(elapsed);
        if (remainingMs <= 0) {
            remainingMs = 0;
        }
        int sleepMs = (std::min)(intervalMs, remainingMs > 0 ? remainingMs : intervalMs);
        Sleep(static_cast<DWORD>(sleepMs));

        r.failure = FailureClassification{};
        if (VerifyExpects(ctx, r, step)) {
            return true;
        }

        if (r.failure.rawErrorCode != L"EXPECT_FAILED") {
            return false;
        }
        if (ElapsedMs(waitStart) >= timeoutMs) {
            return false;
        }
    }
}

bool AttemptRecovery(
    StepExecContext& ctx,
    TaskStepResult& r,
    const TaskStep& step,
    int stepIndex,
    const RecoveryStrategy& strategy) {
    FailureClassification originalFailure = r.failure;
    if (!strategy.canAttempt || !originalFailure.canRecover) {
        RecordRecoveryDecision(ctx.result, &r, stepIndex, step.name, strategy, 0, L"not_attempted", strategy.stopReason);
        return false;
    }
    if (ctx.recoveryCount >= ctx.budget.maxRecoveries) {
        RecordRecoveryDecision(ctx.result, &r, stepIndex, step.name, strategy, 0, L"not_attempted", L"max_recoveries reached");
        return false;
    }

    ctx.recoveryCount++;
    int attempt = ctx.recoveryCount;
    r.failure.recoveryAttempted = attempt;
    std::wstring details;
    bool recovered = false;

    if (strategy.strategyName == L"window_not_found_find_process_activate_stop") {
        WindowSessionResult session = ResolveWindowSession(ctx.targetTitle, ctx.targetProcess);
        if (session.ok) {
            ctx.session = session.session;
            ctx.window = session.session.window;
            ctx.hwnd = session.session.window.hwnd;
            ActionResult focused = FocusTargetWindow(ctx.hwnd);
            if (focused.ok) {
                recovered = ExecuteObserveStep(ctx, r);
                details = recovered ? L"resolved and activated target window" : L"window activated but observe failed";
            } else {
                details = L"target window resolved but activation failed: " + focused.errorCode;
            }
        } else {
            details = L"target window/process still not found: " + session.errorCode;
        }
    } else if (strategy.strategyName == L"locator_not_found_reobserve_ocr_stop") {
        Sleep(500);
        bool observed = ExecuteObserveStep(ctx, r);
        if (observed) {
            recovered = ExecuteLocateStep(ctx, r, step);
            details = recovered ? L"re-observe and original selector succeeded" : L"re-observe done; original selector still missing";
        } else {
            details = L"re-observe failed before selector retry";
        }
        if (!recovered) {
            std::wstring probe = TextProbeFromSelector(step);
            if (!probe.empty()) {
                TaskStep textStep = step;
                textStep.selector = L"text:contains=" + probe;
                r.failure = FailureClassification{};
                bool textRecovered = ExecuteLocateStep(ctx, r, textStep);
                if (textRecovered) {
                    recovered = true;
                    details += L"; OCR fallback succeeded with text probe";
                } else {
                    details += L"; OCR fallback failed with text probe";
                }
            } else {
                details += L"; OCR fallback skipped because no text probe could be derived";
            }
        }
    } else if (strategy.strategyName == L"text_not_found_wait_reobserve_stop") {
        Sleep(500);
        bool observed = ExecuteObserveStep(ctx, r);
        if (observed) {
            recovered = step.hasExpect ? VerifyExpects(ctx, r, step) : true;
            details = recovered ? L"wait and re-observe succeeded" : L"text still missing after wait and re-observe";
        } else {
            details = L"re-observe failed after wait";
        }
    } else if (originalFailure.safeRecoveryAction == L"retry_focus_once") {
        FocusTargetWindow(ctx.hwnd);
        Sleep(500);
        recovered = ExecuteObserveStep(ctx, r);
        details = recovered ? L"legacy focus retry succeeded" : L"legacy focus retry failed";
    } else if (originalFailure.safeRecoveryAction == L"fallback_to_uia_if_available") {
        std::wstring probe = TextProbeFromSelector(step);
        if (!probe.empty()) {
            TaskStep uiaStep = step;
            uiaStep.selector = L"uia:name_contains=" + probe;
            recovered = ExecuteLocateStep(ctx, r, uiaStep);
            details = recovered ? L"legacy UIA fallback succeeded" : L"legacy UIA fallback failed";
        } else {
            details = L"legacy UIA fallback skipped because no text probe could be derived";
        }
    } else if (originalFailure.safeRecoveryAction == L"reobserve_and_reexpect_once") {
        Sleep(500);
        if (ExecuteObserveStep(ctx, r)) {
            recovered = VerifyExpects(ctx, r, step);
            details = recovered ? L"legacy re-expect succeeded" : L"legacy re-expect failed";
        } else {
            details = L"legacy re-observe failed before re-expect";
        }
    } else {
        details = L"no executable recovery step for strategy";
    }

    if (!recovered) {
        r.failure = originalFailure;
        r.failure.recoveryAttempted = attempt;
    }
    RecordRecoveryDecision(ctx.result, &r, stepIndex, step.name, strategy, attempt, recovered ? L"recovered" : L"failed", details);
    return recovered;
}

// ===================================================================
// MVP Report Writer
// ===================================================================
void WriteMvpReport(const std::wstring& reportPath, const TaskResult& result) {
    FILE* f = nullptr;
    if (_wfopen_s(&f, reportPath.c_str(), L"w, ccs=UTF-8") != 0 || !f) return;

    fwprintf(f, L"# DesktopVisual MVP Task Report\n\n");
    fwprintf(f, L"## Summary\n\n");
    fwprintf(f, L"- Task: `%ls`\n", result.taskName.c_str());
    fwprintf(f, L"- Result: %ls\n", result.ok ? L"SUCCESS" : L"FAILED");
    fwprintf(f, L"- Duration: %lld ms\n", result.totalDurationMs);
    fwprintf(f, L"- Target: `%ls`\n", result.targetTitle.c_str());
    fwprintf(f, L"- Steps: %d total, %d passed\n", result.totalSteps, result.passedSteps);
    fwprintf(f, L"- Recoveries: %d\n", result.recoveriesUsed);
    fwprintf(f, L"- Max recoveries effective: %d\n", result.maxRecoveriesEffective);
    if (!result.ok) {
        fwprintf(f, L"- Final error: `%ls` - %ls\n", result.finalErrorCode.c_str(), result.finalErrorMessage.c_str());
    }
    fwprintf(f, L"\n## Environment\n\n");
    fwprintf(f, L"- Version: `%ls`\n", result.version.c_str());
    fwprintf(f, L"- Platform: %ls\n", result.platform.c_str());
    fwprintf(f, L"- OCR available: %ls\n", result.ocrAvailable ? L"true" : L"false");
    fwprintf(f, L"- OCR engine: `%ls`\n", result.ocrEngine.c_str());
    fwprintf(f, L"- Service mode: %ls\n", result.serviceMode ? L"yes" : L"no");
    fwprintf(f, L"- Permission mode: `%ls`\n", result.permissionMode.c_str());
    fwprintf(f, L"- Full access session id: `%ls`\n", result.fullAccessSessionId.c_str());
    fwprintf(f, L"- Safety config: `%ls`\n", result.safetyConfigPath.c_str());
    fwprintf(f, L"- Safety manifest loaded: %ls\n", result.safetyManifestLoaded ? L"true" : L"false");
    fwprintf(f, L"- Safety manifest: `%ls`\n", result.safetyManifestPath.c_str());

    fwprintf(f, L"\n## Safety Manifest\n\n");
    if (!result.safetyManifestSummaryJson.empty()) {
        fwprintf(f, L"```json\n%ls\n```\n", result.safetyManifestSummaryJson.c_str());
    } else {
        fwprintf(f, L"Safety manifest summary unavailable.\n");
    }
    if (!result.initialPolicyCheckJson.empty()) {
        fwprintf(f, L"\n### Initial Policy Check\n\n```json\n%ls\n```\n", result.initialPolicyCheckJson.c_str());
    }
    if (!result.permissionDecisionJson.empty()) {
        fwprintf(f, L"\n### Permission Decision\n\n```json\n%ls\n```\n", result.permissionDecisionJson.c_str());
    }
    if (!result.initialWindowSessionJson.empty()) {
        fwprintf(f, L"\n### Initial Window Session\n\n```json\n%ls\n```\n", result.initialWindowSessionJson.c_str());
    }

    fwprintf(f, L"\n## Recovery Strategy Engine\n\n");
    fwprintf(f, L"- max_recoveries_effective: %d\n", result.maxRecoveriesEffective);
    fwprintf(f, L"- recovery_records: %zu\n", result.recoveryAttempts.size());
    if (result.recoveryAttempts.empty()) {
        fwprintf(f, L"- No recovery records.\n");
    }
    for (const auto& rec : result.recoveryAttempts) {
        fwprintf(f, L"\n### Recovery Record\n\n");
        fwprintf(f, L"- step_index: %d\n", rec.stepIndex);
        fwprintf(f, L"- step_name: `%ls`\n", rec.stepName.c_str());
        fwprintf(f, L"- error: `%ls`\n", rec.errorCode.c_str());
        fwprintf(f, L"- strategy: %ls\n", rec.strategyName.c_str());
        fwprintf(f, L"- attempt: %d\n", rec.attempt);
        fwprintf(f, L"- result: %ls\n", rec.result.c_str());
        fwprintf(f, L"- details: %ls\n", rec.details.c_str());
        fwprintf(f, L"- strategy_steps: %ls\n", JsonStringArray(rec.strategySteps).c_str());
    }

    fwprintf(f, L"\n## Session Checkpoints\n\n");
    fwprintf(f, L"- Last checkpoint: `%ls`\n", result.lastCheckpointId.c_str());
    fwprintf(f, L"- Temporary checkpoint cleanup: %ls\n", result.temporaryCheckpointsCleaned ? L"true" : L"false");
    if (result.checkpoints.empty()) {
        fwprintf(f, L"- No checkpoints recorded.\n");
    }
    for (const auto& cp : result.checkpoints) {
        fwprintf(f, L"\n### checkpoint_id `%ls`\n\n", cp.checkpointId.c_str());
        fwprintf(f, L"- timestamp: `%ls`\n", cp.timestamp.c_str());
        fwprintf(f, L"- permission_mode: `%ls`\n", cp.permissionMode.c_str());
        fwprintf(f, L"- task_id: `%ls`\n", cp.taskId.c_str());
        fwprintf(f, L"- step_index: %d\n", cp.stepIndex);
        fwprintf(f, L"- window_title: `%ls`\n", cp.windowTitle.c_str());
        fwprintf(f, L"- process_name: `%ls`\n", cp.processName.c_str());
        fwprintf(f, L"- url: `%ls`\n", cp.url.c_str());
        fwprintf(f, L"- screenshot_path: `%ls`\n", cp.screenshotPath.c_str());
        fwprintf(f, L"- observed_summary: %ls\n", cp.observedSummary.c_str());
        fwprintf(f, L"- recent_actions: %ls\n", JsonStringArray(cp.recentActions).c_str());
        fwprintf(f, L"- form_state_summary: %ls\n", cp.formStateSummary.c_str());
        fwprintf(f, L"- suggested_recovery_actions: %ls\n", JsonStringArray(cp.suggestedRecoveryActions).c_str());
        fwprintf(f, L"- temporary_cleaned: %ls\n", cp.temporaryCleaned ? L"true" : L"false");
    }

    if (!result.templateUsages.empty()) {
        fwprintf(f, L"\n## Templates\n\n");
        for (const auto& usage : result.templateUsages) {
            fwprintf(f, L"### Template: `%ls`\n\n", usage.name.c_str());
            fwprintf(f, L"- Source step: `%ls`\n", usage.stepName.c_str());
            fwprintf(f, L"- Result: %ls\n", usage.ok ? L"PASS" : L"FAIL");
            fwprintf(f, L"- Expanded step count: %d\n", usage.expandedStepCount);
            fwprintf(f, L"- Parameters:\n\n```json\n%ls\n```\n", usage.parametersJson.c_str());
            fwprintf(f, L"- Expanded steps:\n\n```json\n%ls\n```\n\n", usage.expandedStepsJson.c_str());
        }
    }

    fwprintf(f, L"\n## Step Timeline\n\n");
    for (const auto& r : result.stepResults) {
        fwprintf(f, L"### %ls (%ls) - %ls\n\n", r.stepName.c_str(), r.stepType.c_str(), r.ok ? L"PASS" : L"FAIL");
        fwprintf(f, L"- Duration: %lld ms\n", r.durationMs);
        if (!r.templateName.empty()) fwprintf(f, L"- template_expanded_from: `%ls`\n", r.templateName.c_str());
        if (!r.observeBefore.empty()) fwprintf(f, L"- Observe before: present\n");
        if (!r.observeAfter.empty()) fwprintf(f, L"- Observe after: present\n");
        if (!r.windowSessionBefore.empty()) fwprintf(f, L"- Window session before: %ls\n", r.windowSessionBefore.c_str());
        if (!r.windowSessionAfter.empty()) fwprintf(f, L"- Window session after: %ls\n", r.windowSessionAfter.c_str());
        if (!r.locateResult.empty()) fwprintf(f, L"- Locate: %ls\n", r.locateResult.c_str());
        if (!r.decisionContext.empty()) fwprintf(f, L"- Decision context: %ls\n", r.decisionContext.c_str());
        if (!r.decisionRecord.empty()) fwprintf(f, L"- Decision record: %ls\n", r.decisionRecord.c_str());
        if (!r.communicationAction.empty()) fwprintf(f, L"- CommunicationAction: %ls\n", r.communicationAction.c_str());
        if (!r.codingContext.empty()) fwprintf(f, L"- CodingWorkflowContext: %ls\n", r.codingContext.c_str());
        if (!r.codingRecord.empty()) fwprintf(f, L"- CodingWorkflowRecord: %ls\n", r.codingRecord.c_str());
        if (!r.actionResult.empty()) fwprintf(f, L"- Action: %ls\n", r.actionResult.c_str());
        if (!r.expectResult.empty()) fwprintf(f, L"- Expect: %ls\n", r.expectResult.c_str());
        if (!r.screenshotPath.empty()) fwprintf(f, L"- Screenshot: `%ls`\n", r.screenshotPath.c_str());
        if (r.failure.category != FailureCategory::NONE) {
            fwprintf(f, L"- Failure category: %d\n", static_cast<int>(r.failure.category));
            fwprintf(f, L"- Error: `%ls` - %ls\n", r.failure.rawErrorCode.c_str(), r.failure.rawErrorMessage.c_str());
            fwprintf(f, L"- Can recover: %ls\n", r.failure.canRecover ? L"true" : L"false");
            if (r.failure.recoveryAttempted > 0) fwprintf(f, L"- Recovery attempted: %d\n", r.failure.recoveryAttempted);
            fwprintf(f, L"- Recommended: %ls\n", r.failure.recommendedUserAction.c_str());
        }
        for (const auto& rec : r.recoveryAttempts) {
            fwprintf(f, L"- RecoveryStrategy: error=%ls; strategy=%ls; attempt=%d; result=%ls; details=%ls; steps=%ls\n",
                rec.errorCode.c_str(),
                rec.strategyName.c_str(),
                rec.attempt,
                rec.result.c_str(),
                rec.details.c_str(),
                JsonStringArray(rec.strategySteps).c_str());
        }
        if (r.recovered) fwprintf(f, L"- RECOVERED\n");
        fwprintf(f, L"\n");
    }

    fwprintf(f, L"## Artifacts\n\n");
    for (const auto& s : result.screenshots) { fwprintf(f, L"- `%ls`\n", s.c_str()); }
    for (const auto& rp : result.reportPaths) { fwprintf(f, L"- `%ls`\n", rp.c_str()); }

    fwprintf(f, L"\n## Final Recommendation\n\n");
    fwprintf(f, L"%ls\n", result.finalRecommendation.c_str());

    fclose(f);
}

}  // namespace

// ===================================================================
// Public API
// ===================================================================
TaskResult RunTask(
    const std::wstring& taskJsonPath,
    const std::wstring& reportPath,
    bool serviceMode,
    const std::wstring& requestedPermissionMode,
    const std::wstring& requestedFullAccessSessionId) {
    ULONGLONG taskStart = GetTickCount64();
    TaskResult result;
    result.serviceMode = serviceMode;
    result.version = L"5.10.2";
    result.platform = L"Windows";

    OcrCapability ocr = GetOcrCapability();
    result.ocrAvailable = ocr.available;
    result.ocrEngine = ocr.engine;
    result.safetyConfigPath = ConfigPath(L"safety.conf");
    SafetyPolicy safetyPolicy = LoadSafetyPolicy();
    SafetyManifest safetyManifest = LoadSafetyManifest();
    result.safetyManifestLoaded = safetyManifest.loaded;
    result.safetyManifestPath = safetyManifest.manifestPath;
    result.safetyManifestSummaryJson = SafetyManifestSummaryJson(safetyManifest);

    // Read task file
    FileReadResult fileRead = ReadTextFile(taskJsonPath);
    if (!fileRead.ok) {
        result.finalErrorCode = L"FILE_READ_FAILED";
        result.finalErrorMessage = L"Could not read task file: " + fileRead.error;
        result.finalRecommendation = L"Verify the task.json file exists and is readable. Path: " + taskJsonPath;
        WriteMvpReport(reportPath, result);
        return result;
    }

    // Parse task
    TaskDefinition task;
    std::wstring parseError;
    if (!ParseTaskJson(fileRead.content, task, parseError)) {
        result.finalErrorCode = L"INVALID_ARGUMENT";
        result.finalErrorMessage = parseError;
        result.finalRecommendation = L"Fix the task.json syntax errors and retry.";
        WriteMvpReport(reportPath, result);
        return result;
    }

    result.taskName = task.name;
    result.targetTitle = task.target.title;
    result.templateUsages = task.templateUsages;
    if (!requestedPermissionMode.empty()) task.permissionMode = requestedPermissionMode;
    if (!requestedFullAccessSessionId.empty()) task.fullAccessSessionId = requestedFullAccessSessionId;
    PermissionMode parsedMode = PermissionMode::DEFAULT;
    if (!ParsePermissionMode(task.permissionMode, parsedMode)) {
        result.finalErrorCode = L"INVALID_ARGUMENT";
        result.finalErrorMessage = L"permission_mode must be DEFAULT, PUBLIC_DEFAULT, DEVELOPER_CAPABILITY_DISCOVERY, CI_MOCK, or FULL_ACCESS.";
        result.finalRecommendation = L"Use the developer profile for local runtime exploration, PUBLIC_DEFAULT for release-style checks, or legacy FULL_ACCESS with a session id.";
        WriteMvpReport(reportPath, result);
        result.reportPaths.push_back(reportPath);
        return result;
    }
    result.permissionMode = PermissionModeName(parsedMode);
    result.fullAccessSessionId = task.fullAccessSessionId;
    task.budget.maxSteps = (std::min)(task.budget.maxSteps, safetyManifest.loaded ? safetyManifest.maxSteps : safetyPolicy.maxSteps);
    task.budget.maxDurationMs = (std::min)(task.budget.maxDurationMs, safetyManifest.loaded ? safetyManifest.maxDurationMs : safetyPolicy.maxDurationMs);
    task.budget.maxRecoveries = (std::min)(task.budget.maxRecoveries, safetyManifest.loaded ? safetyManifest.maxRecoveries : task.budget.maxRecoveries);
    result.maxRecoveriesEffective = task.budget.maxRecoveries;

    if (task.allowUnrestrictedDesktop || (safetyManifest.loaded && safetyManifest.allowUnrestrictedDesktop)) {
        result.finalErrorCode = L"SAFETY_POLICY_DENIED";
        result.finalErrorMessage = L"Unrestricted desktop control is denied by DesktopVisual safety manifest.";
        result.finalRecommendation = L"Remove allow_unrestricted_desktop and provide an explicit authorized target window.";
        result.initialPolicyCheckJson = L"{\"allow\":false,\"reason\":\"allow_unrestricted_desktop is denied\",\"matched_rule\":\"consent.allow_unrestricted_desktop\"}";
        RecoveryStrategy strategy = StrategyForError(result.finalErrorCode);
        RecordRecoveryDecision(result, nullptr, -1, L"initial_policy_check", strategy, 0, L"not_attempted", strategy.stopReason);
        WriteMvpReport(reportPath, result);
        result.reportPaths.push_back(reportPath);
        return result;
    }

    PermissionDecision permissionDecision = EvaluatePermissionRequest(safetyManifest, task.target.title, task.target.process, L"run-task", parsedMode, task.fullAccessSessionId);
    result.permissionDecisionJson = PermissionDecisionJson(permissionDecision);
    if (!permissionDecision.allow) {
        result.finalErrorCode = permissionDecision.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : permissionDecision.errorCode;
        result.finalErrorMessage = permissionDecision.reason;
        result.finalRecommendation = L"Check permission_mode and full_access_session_id before retrying.";
        RecoveryStrategy strategy = StrategyForError(result.finalErrorCode);
        RecordRecoveryDecision(result, nullptr, -1, L"permission_request", strategy, 0, L"not_attempted", strategy.stopReason);
        WriteMvpReport(reportPath, result);
        result.reportPaths.push_back(reportPath);
        return result;
    }

    PolicyCheckDecision initialPolicy = EvaluatePolicyCheck(
        safetyPolicy,
        safetyManifest,
        task.target.title,
        task.target.process,
        L"run-task",
        L"",
        permissionDecision.relaxConfiguredBoundary,
        PermissionModeName(parsedMode),
        task.fullAccessSessionId,
        permissionDecision.fullAccessSessionActive,
        permissionDecision.fullAccessSessionExpired,
        permissionDecision.fullAccessScope);
    result.initialPolicyCheckJson = L"{\"allow\":" + std::wstring(initialPolicy.allow ? L"true" : L"false")
        + L",\"permission_mode\":" + JsonString(initialPolicy.permissionMode)
        + L",\"reason\":" + JsonString(initialPolicy.reason)
        + L",\"matched_rule\":" + JsonString(initialPolicy.matchedRule)
        + L",\"matched_category\":" + JsonString(initialPolicy.matchedCategory)
        + L",\"full_access_session_active\":" + std::wstring(initialPolicy.fullAccessSessionActive ? L"true" : L"false")
        + L"}";
    if (!initialPolicy.allow) {
        result.finalErrorCode = initialPolicy.errorCode.empty() ? L"SAFETY_POLICY_DENIED" : initialPolicy.errorCode;
        result.finalErrorMessage = initialPolicy.reason;
        result.finalRecommendation = L"Review config\\safety.conf and config\\safety_manifest.json before retrying.";
        RecoveryStrategy strategy = StrategyForError(result.finalErrorCode);
        RecordRecoveryDecision(result, nullptr, -1, L"initial_policy_check", strategy, 0, L"not_attempted", strategy.stopReason);
        WriteMvpReport(reportPath, result);
        result.reportPaths.push_back(reportPath);
        return result;
    }

    WindowSessionResult initialSession = ResolveWindowSession(task.target.title, task.target.process);
    if (!initialSession.ok) {
        std::wstring errorCode = initialSession.errorCode.empty() ? L"UNKNOWN_ERROR" : initialSession.errorCode;
        RecoveryStrategy strategy = StrategyForError(errorCode);
        bool recoveredInitialWindow = false;
        std::wstring details;
        if (strategy.canAttempt && task.budget.maxRecoveries > 0) {
            Sleep(500);
            WindowSessionResult retriedSession = ResolveWindowSession(task.target.title, task.target.process);
            if (retriedSession.ok) {
                ActionResult focused = FocusTargetWindow(retriedSession.session.window.hwnd);
                if (focused.ok) {
                    initialSession = retriedSession;
                    recoveredInitialWindow = true;
                    result.recoveriesUsed++;
                    details = L"initial window resolved and activated after retry";
                } else {
                    details = L"initial window resolved but activation failed: " + focused.errorCode;
                }
            } else {
                details = L"initial window/process still not found: " + retriedSession.errorCode;
            }
            RecordRecoveryDecision(result, nullptr, -1, L"initial_window_session", strategy, 1, recoveredInitialWindow ? L"recovered" : L"failed", details);
        } else {
            RecordRecoveryDecision(result, nullptr, -1, L"initial_window_session", strategy, 0, L"not_attempted", strategy.stopReason);
        }
        if (!recoveredInitialWindow) {
            result.finalErrorCode = errorCode;
            result.finalErrorMessage = initialSession.errorMessage;
            result.finalRecommendation = ClassifyFailure(result.finalErrorCode, result.finalErrorMessage).recommendedUserAction;
            result.initialWindowSessionJson = initialSession.dataJson;
            WriteMvpReport(reportPath, result);
            result.reportPaths.push_back(reportPath);
            return result;
        }
    }
    result.initialWindowSessionJson = WindowSessionJson(initialSession.session);

    StepExecContext ctx = {
        initialSession.session.window.hwnd,
        initialSession.session.window,
        initialSession.session,
        task.target.title,
        task.target.process,
        parsedMode,
        task.fullAccessSessionId,
        result,
        task.budget,
        result.recoveriesUsed};
    LoopGuardState loopGuard;
    CreateSessionCheckpoint(ctx, task, nullptr, -1, loopGuard, L"session_start");

    for (size_t i = 0; i < task.steps.size(); ++i) {
        const auto& step = task.steps[i];
        ULONGLONG stepStart = GetTickCount64();
        TaskStepResult sr;
        sr.stepName = step.name;
        sr.stepType = step.type;
        sr.templateUsageId = step.templateUsageId;
        sr.templateName = step.templateName;

        if (IsSubmitSendOrWindowSwitch(step)) {
            CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"before_submit_send_or_window_switch");
        }

        if ((task.checkpoint.intervalMs <= 1 && i > 0) ||
            (task.checkpoint.intervalMs > 0 && loopGuard.lastCheckpointTick != 0 &&
             ElapsedMs(loopGuard.lastCheckpointTick) >= task.checkpoint.intervalMs)) {
            CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"interval_checkpoint");
        }

        if (!CheckLoopGuard(task, step, loopGuard, sr, result.totalSteps, taskStart)) {
            sr.ok = false;
            result.stepResults.push_back(sr);
            result.totalSteps++;
            result.finalErrorCode = sr.failure.rawErrorCode;
            result.finalErrorMessage = sr.failure.rawErrorMessage;
            result.finalRecommendation = sr.failure.recommendedUserAction;
            CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"loop_guard_stop");
            break;
        }

        bool ok = true;
        if (step.type == L"observe") {
            ok = ExecuteObserveStep(ctx, sr);
        } else if (step.type == L"checkpoint") {
            CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"manual_checkpoint");
            ok = true;
            sr.actionResult = L"{\"action\":\"checkpoint\",\"ok\":true,\"checkpoint_id\":" + JsonString(result.lastCheckpointId) + L"}";
        } else if (step.type == L"locate") {
            ok = ExecuteLocateStep(ctx, sr, step);
        } else if (step.type == L"act") {
            ok = ExecuteActStep(ctx, sr, step);
            if (ok && step.hasExpect) {
                ok = VerifyExpects(ctx, sr, step);
            }
        } else if (step.type == L"form_action") {
            ok = ExecuteFormActionStep(ctx, sr, step);
            if (ok && step.hasExpect) {
                ok = VerifyExpects(ctx, sr, step);
            }
        } else if (step.type == L"decision") {
            ok = ExecuteDecisionStep(ctx, sr, step);
            if (ok && step.hasExpect) {
                ok = VerifyExpects(ctx, sr, step);
            }
        } else if (step.type == L"communication_step") {
            ok = ExecuteCommunicationStep(ctx, sr, step);
            if (ok && step.hasExpect) {
                ok = VerifyExpects(ctx, sr, step);
            }
        } else if (step.type == L"coding") {
            ok = ExecuteCodingStep(ctx, sr, step);
            if (ok && step.hasExpect) {
                ok = VerifyExpects(ctx, sr, step);
            }
        } else if (step.type == L"hotkey") {
            ok = ExecuteHotkeyStep(ctx, sr, step);
            if (ok && step.hasExpect) {
                ok = VerifyExpects(ctx, sr, step);
            }
        } else if (step.type == L"wait") {
            ok = ExecuteWaitStep(ctx, sr, step);
        } else if (step.type == L"screenshot") {
            if (!EnsureWindowSession(ctx, sr)) {
                ok = false;
                sr.durationMs = ElapsedMs(stepStart);
                sr.ok = ok;
                result.stepResults.push_back(sr);
                result.totalSteps++;
                result.finalErrorCode = sr.failure.rawErrorCode;
                result.finalErrorMessage = sr.failure.rawErrorMessage;
                result.finalRecommendation = sr.failure.recommendedUserAction;
                break;
            }
            std::wstring outPath = step.path.empty() ? ArtifactsPath(L"task_screenshot_" + std::to_wstring(i) + L".bmp") : step.path;
            ScreenshotResult shot = CaptureWindowToBmp(ctx.hwnd, outPath);
            if (shot.ok) { sr.screenshotPath = outPath; result.screenshots.push_back(outPath); }
            else { ok = false; sr.failure = ClassifyFailure(L"SCREENSHOT_FAILED", shot.error); }
        } else {
            CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"before_unknown_state");
            ok = false;
            sr.failure = ClassifyFailure(L"INVALID_ARGUMENT", L"Unsupported task step type: " + step.type);
        }

        // Recovery logic
        if (!ok) {
            RecoveryStrategy strategy = StrategyForError(sr.failure.rawErrorCode);
            bool recovered = AttemptRecovery(ctx, sr, step, static_cast<int>(i), strategy);
            if (recovered) {
                sr.recovered = true;
                result.recoveriesUsed++;
                ok = true;
                sr.failure = FailureClassification{};  // reset failure on recovery
            }
        }

        sr.durationMs = ElapsedMs(stepStart);
        sr.ok = ok;
        result.stepResults.push_back(sr);
        result.totalSteps++;

        if (ok) {
            result.passedSteps++;
            AddRecentAction(loopGuard, StepActionKey(step));
            if (!step.pageId.empty()) {
                CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"page_completed");
            }
        } else {
            result.finalErrorCode = sr.failure.rawErrorCode;
            result.finalErrorMessage = sr.failure.rawErrorMessage;
            result.finalRecommendation = sr.failure.recommendedUserAction;
            CreateSessionCheckpoint(ctx, task, &step, static_cast<int>(i), loopGuard, L"failure_stop");
            break;
        }
    }

    result.totalDurationMs = ElapsedMs(taskStart);
    result.ok = result.finalErrorCode.empty();

    for (auto& usage : result.templateUsages) {
        bool sawStep = false;
        bool allOk = true;
        for (const auto& stepResult : result.stepResults) {
            if (stepResult.templateUsageId == usage.id) {
                sawStep = true;
                if (!stepResult.ok) {
                    allOk = false;
                }
            }
        }
        usage.ok = sawStep && allOk;
    }

    if (result.ok) {
        result.finalRecommendation = L"All task steps completed successfully. The MVP workflow executed as expected.";
    }

    CleanupTemporaryCheckpoints(result, task.checkpoint.cleanupOnEnd);
    WriteMvpReport(reportPath, result);
    result.reportPaths.push_back(reportPath);
    return result;
}
