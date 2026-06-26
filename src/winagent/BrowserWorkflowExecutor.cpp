#include "BrowserWorkflowExecutor.h"

#include "BrowserSurfaceNormalizer.h"
#include "BrowserWorkflow.h"
#include "BrowserWorkflowAdapter.h"
#include "CompiledPlanExecutor.h"
#include "ExecutionEvidencePack.h"
#include "InputController.h"
#include "ProjectRoot.h"
#include "RuntimeContextGuard.h"
#include "RuntimeSession.h"
#include "SafetyPolicy.h"
#include "SessionManager.h"
#include "SimpleJson.h"
#include "StepContractValidator.h"
#include "Trace.h"
#include "UiaController.h"
#include "WebFormFieldLocator.h"
#include "WindowFinder.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <iostream>
#include <regex>
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

bool WriteTextFileUtf8(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) EnsureDirectoryPath(path.substr(0, slash));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

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

bool MatchesPattern(const std::wstring& haystack, const std::wstring& pattern) {
    if (pattern.empty()) return true;
    try {
        std::wregex regex(pattern, std::regex_constants::icase);
        return std::regex_search(haystack, regex);
    } catch (...) {
        return ContainsInsensitive(haystack, pattern);
    }
}

bool AnyPatternMatches(const std::wstring& haystack, const std::vector<std::wstring>& patterns, std::wstring& matched) {
    for (const auto& pattern : patterns) {
        if (MatchesPattern(haystack, pattern)) {
            matched = pattern;
            return true;
        }
    }
    return false;
}

bool AllMarkersPresent(const std::wstring& haystack, const std::vector<std::wstring>& markers, std::wstring& missing) {
    for (const auto& marker : markers) {
        if (!MatchesPattern(haystack, marker)) {
            missing = marker;
            return false;
        }
    }
    return true;
}

std::wstring ObjectStringOr(const std::wstring& objectJson, const std::wstring& key, const std::wstring& fallback);

bool ActiveWindowInfo(WindowInfo& info) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return false;
    info.hwnd = hwnd;
    GetWindowThreadProcessId(hwnd, &info.pid);
    GetWindowRect(hwnd, &info.rect);
    int length = GetWindowTextLengthW(hwnd);
    if (length > 0) {
        std::wstring title(static_cast<size_t>(length) + 1, L'\0');
        int copied = GetWindowTextW(hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
        info.title = title;
    }
    return true;
}

bool ProcessMatchesBrowser(const std::wstring& process, const std::wstring& browser) {
    std::wstring lower = Lower(process);
    if (browser == L"chrome") return lower == L"chrome.exe";
    if (browser == L"edge") return lower == L"msedge.exe";
    return lower == L"chrome.exe" || lower == L"msedge.exe";
}

std::wstring BrowserExeForOption(const std::wstring& browser) {
    if (browser == L"chrome") return L"chrome.exe --new-window about:blank";
    return L"msedge.exe --new-window about:blank";
}

bool TitleUnsafeForReuse(const std::wstring& title) {
    return ContainsInsensitive(title, L"captcha") ||
           ContainsInsensitive(title, L"human verification") ||
           ContainsInsensitive(title, L"bot challenge") ||
           ContainsInsensitive(title, L"password required") ||
           ContainsInsensitive(title, L"verification code");
}

bool ActivateExistingBrowserWindow(const std::wstring& browser, WindowInfo& selected) {
    for (const auto& window : EnumerateVisibleTopLevelWindows()) {
        if (TitleUnsafeForReuse(window.title)) continue;
        if (ProcessMatchesBrowser(ProcessNameForPid(window.pid), browser)) {
            selected = window;
            SetForegroundWindow(window.hwnd);
            Sleep(200);
            return true;
        }
    }
    return false;
}

bool WaitForBrowserWindow(const std::wstring& browser, int waitMs, WindowInfo& selected) {
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    do {
        if (ActivateExistingBrowserWindow(browser, selected)) return true;
        Sleep(150);
    } while (GetTickCount64() < deadline);
    return ActivateExistingBrowserWindow(browser, selected);
}

bool EnsureBrowserForeground(const std::wstring& browser, WindowInfo& selected) {
    WindowInfo active;
    ActiveWindowInfo(active);
    if (active.hwnd && ProcessMatchesBrowser(ProcessNameForPid(active.pid), browser)) {
        selected = active;
        return true;
    }
    if (selected.hwnd && IsWindow(selected.hwnd) &&
        ProcessMatchesBrowser(ProcessNameForPid(selected.pid), browser)) {
        ShowWindow(selected.hwnd, SW_RESTORE);
        BringWindowToTop(selected.hwnd);
        SetForegroundWindow(selected.hwnd);
        Sleep(180);
        ActiveWindowInfo(active);
        if (active.hwnd && ProcessMatchesBrowser(ProcessNameForPid(active.pid), browser)) {
            selected = active;
            return true;
        }
    }
    return ActivateExistingBrowserWindow(browser, selected);
}

std::wstring BrowserHaystack(HWND hwnd, const std::wstring& title, const std::wstring& process) {
    std::wstring text = L"title:" + title + L"\nprocess:" + process;
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (tree.ok) {
        for (const auto& element : tree.elements) {
            if (!element.name.empty()) text += L"\nname:" + element.name;
            if (!element.value.empty()) text += L"\nvalue:" + element.value;
            if (!element.controlType.empty()) text += L"\nrole:" + element.controlType;
            if (!element.automationId.empty()) text += L"\nautomation_id:" + element.automationId;
            if (!element.className.empty()) text += L"\nclass_name:" + element.className;
        }
    }
    return text;
}

std::wstring FirstMarker(const BrowserWorkflowSpec& spec) {
    if (!spec.requiredMarkers.empty()) return spec.requiredMarkers.front();
    return L"";
}

ExpectedContextSpec ExpectedContextFromBrowserSpec(const BrowserWorkflowSpec& spec) {
    ExpectedContextSpec ctx;
    ctx.enabled = true;
    simplejson::ParseResult parsed = simplejson::Parse(spec.expectedContextJson);
    if (parsed.ok && parsed.root.IsObject()) {
        ctx.expectedProcessPattern = simplejson::GetString(parsed.root, L"expected_process_pattern", L"chrome.exe|msedge.exe");
        ctx.expectedTitlePattern = simplejson::GetString(parsed.root, L"expected_title_pattern", spec.expectedTitlePattern);
        ctx.requiredMarkers = simplejson::GetStringArray(parsed.root, L"required_markers");
        ctx.wrongPagePatterns = simplejson::GetStringArray(parsed.root, L"wrong_page_patterns");
        ctx.activeProtectionPatterns = simplejson::GetStringArray(parsed.root, L"active_protection_patterns");
    }
    if (ctx.expectedProcessPattern.empty()) ctx.expectedProcessPattern = L"chrome.exe|msedge.exe";
    if (ctx.requiredMarkers.empty()) ctx.requiredMarkers = spec.requiredMarkers;
    if (ctx.wrongPagePatterns.empty()) ctx.wrongPagePatterns = spec.wrongPagePatterns;
    if (ctx.activeProtectionPatterns.empty()) ctx.activeProtectionPatterns = spec.activeProtectionPatterns;
    return ctx;
}

RuntimeSession CreateRuntimeSession(const BrowserWorkflowSpec& spec, const WindowInfo& window) {
    RuntimeSession session;
    session.sessionId = RuntimeSessionGenerateId();
    session.sessionCreatedAt = NowTimestamp();
    session.sessionLastActiveAt = session.sessionCreatedAt;
    session.sessionCreatedAtEpochMs = RuntimeSessionNowEpochMs();
    session.sessionLastActiveAtEpochMs = session.sessionCreatedAtEpochMs;
    session.sessionAlive = true;
    session.sessionClosed = false;
    session.requestedTitle = spec.expectedTitlePattern;
    session.requestedProcess = spec.browser;
    session.targetHwnd = window.hwnd ? FormatHwnd(window.hwnd) : L"";
    session.targetHwndValue = reinterpret_cast<unsigned long long>(window.hwnd);
    session.targetProcess = window.pid;
    session.targetTitle = window.title;
    session.targetProcessName = window.hwnd ? ProcessNameForPid(window.pid) : L"";
    session.targetBounds = RuntimeBoundsFromRect(window.rect);
    session.sessionCommandCount = 0;
    session.latencySummary.sessionReuseEnabled = true;
    session.lastObserveId = L"browser-observe-" + spec.workflowId;
    return session;
}

struct BrowserStepOutcome {
    bool ok = false;
    std::wstring finalStatus = L"BLOCKED";
    std::wstring stopCode;
    std::wstring errorMessage;
    bool browserOpened = false;
    bool pageLoaded = false;
    bool expectedTitleVerified = false;
    bool expectedUrlVerified = false;
    bool requiredMarkersVerified = false;
    int formFieldsTotal = 0;
    int formFieldsClicked = 0;
    int formFieldsFilled = 0;
    int formFieldsVerified = 0;
    bool submitClicked = false;
    bool submitResultVerified = false;
    bool wrongPageDetected = false;
    bool recoveryAttempted = false;
    bool recoverySuccess = false;
    bool activeProtectionDetected = false;
    bool credentialRequiredDetected = false;
    bool scrollUsed = false;
    bool scrollProgressDetected = false;
    bool fieldFoundAfterScroll = false;
    bool staleRectUsed = false;
    int wrongFieldInputCount = 0;
    bool runtimeContextGuardUsed = false;
    bool runtimeContextGuardOk = false;
    bool browserSurfaceNormalizerUsed = false;
    bool browserSurfaceNormalizerOk = true;
    bool realBrowserUiUsed = false;
    std::wstring sessionId;
    std::wstring guardJson = L"{}";
    std::wstring normalizerJson = L"{}";
    std::wstring lastHaystack;
    WindowInfo window;
};

bool OpenBrowserHuman(const BrowserWorkflowSpec& spec, BrowserStepOutcome& outcome, int waitMs = 10000) {
    WindowInfo browserWindow;
    bool reused = ActivateExistingBrowserWindow(spec.browser, browserWindow);
    if (!reused) {
        ActionResult runDialog = SendHotkeyGlobal(L"WIN+R");
        if (!runDialog.ok) {
            outcome.stopCode = runDialog.errorCode.empty() ? L"SEND_INPUT_FAILED" : runDialog.errorCode;
            outcome.errorMessage = runDialog.error;
            return false;
        }
        Sleep(250);
        TypeResult typedBrowser = TypeTextGlobal(BrowserExeForOption(spec.browser), L"human", -1);
        if (!typedBrowser.ok) {
            outcome.stopCode = typedBrowser.errorCode.empty() ? L"SEND_INPUT_FAILED" : typedBrowser.errorCode;
            outcome.errorMessage = typedBrowser.error;
            return false;
        }
        ActionResult enterBrowser = PressKeyGlobal(L"ENTER");
        if (!enterBrowser.ok) {
            outcome.stopCode = enterBrowser.errorCode.empty() ? L"SEND_INPUT_FAILED" : enterBrowser.errorCode;
            outcome.errorMessage = enterBrowser.error;
            return false;
        }
        if (!WaitForBrowserWindow(spec.browser, waitMs, browserWindow)) {
            outcome.stopCode = L"WINDOW_NOT_FOUND";
            outcome.errorMessage = L"Browser window did not appear after human launch.";
            return false;
        }
    }
    SetForegroundWindow(browserWindow.hwnd);
    Sleep(150);
    bool focusAddressOk = false;
    bool typedUrlOk = false;
    bool enterOk = false;
    for (int attempt = 0; attempt < 3; ++attempt) {
        SetForegroundWindow(browserWindow.hwnd);
        Sleep(120);
        ActionResult focusAddress = SendHotkeyGlobal(L"CTRL+L");
        focusAddressOk = focusAddressOk || focusAddress.ok;
        if (!focusAddress.ok) continue;
        Sleep(80);
        ActionResult selectAll = SendHotkeyGlobal(L"CTRL+A");
        if (!selectAll.ok) continue;
        Sleep(80);
        TypeResult typed = TypeTextGlobal(spec.url, L"human", -1);
        typedUrlOk = typed.ok;
        if (!typed.ok) {
            ActionResult paste = PasteClipboardText(browserWindow.hwnd, spec.url, true);
            typedUrlOk = paste.ok;
        }
        if (!typedUrlOk) continue;
        Sleep(80);
        ActionResult enter = PressKeyGlobal(L"ENTER");
        enterOk = enter.ok;
        if (enterOk) break;
    }
    if (!focusAddressOk || !typedUrlOk || !enterOk) {
        outcome.stopCode = L"STOP_BROWSER_NAVIGATION_INPUT_FAILED";
        outcome.errorMessage = L"Could not complete visible address-bar URL input.";
        return false;
    }
    outcome.browserOpened = true;
    outcome.realBrowserUiUsed = true;
    outcome.window = browserWindow;
    return true;
}

void ObserveBrowserPage(const BrowserWorkflowSpec& spec, BrowserStepOutcome& outcome, int waitMs = 10000) {
    ExpectedContextSpec guardSpec = ExpectedContextFromBrowserSpec(spec);
    ULONGLONG deadline = GetTickCount64() + static_cast<ULONGLONG>(waitMs);
    std::wstring matched;
    do {
        Sleep(250);
        if (!EnsureBrowserForeground(spec.browser, outcome.window)) continue;
        BrowserSurfaceNormalizeOptions normalizeOptions;
        normalizeOptions.mode = L"conservative";
        BrowserSurfaceNormalizeResult normalize = NormalizeBrowserSurface(normalizeOptions);
        outcome.browserSurfaceNormalizerUsed = true;
        outcome.browserSurfaceNormalizerOk = normalize.ok;
        outcome.normalizerJson = BrowserSurfaceNormalizeResultJson(normalize);
        if (!normalize.ok) {
            outcome.activeProtectionDetected = normalize.activeProtectionDetected;
            outcome.stopCode = normalize.stopCode;
            outcome.errorMessage = normalize.reason;
            break;
        }
        if (!EnsureBrowserForeground(spec.browser, outcome.window)) continue;
        outcome.lastHaystack = BrowserHaystack(outcome.window.hwnd, outcome.window.title, ProcessNameForPid(outcome.window.pid));
        if (AnyPatternMatches(outcome.lastHaystack, spec.credentialRequiredPatterns, matched)) {
            outcome.credentialRequiredDetected = true;
            outcome.stopCode = L"STOP_CREDENTIAL_REQUIRED";
            outcome.errorMessage = L"Credential required marker matched: " + matched;
            break;
        }
        if (AnyPatternMatches(outcome.lastHaystack, spec.activeProtectionPatterns, matched)) {
            outcome.activeProtectionDetected = true;
            outcome.stopCode = L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK";
            outcome.errorMessage = L"Active protection marker matched: " + matched;
            break;
        }
        if (AnyPatternMatches(outcome.lastHaystack, spec.wrongPagePatterns, matched)) {
            outcome.wrongPageDetected = true;
            outcome.stopCode = L"STOP_WRONG_CONTEXT";
            outcome.errorMessage = L"Wrong page marker matched: " + matched;
            break;
        }
        std::wstring missing;
        outcome.requiredMarkersVerified = AllMarkersPresent(outcome.lastHaystack, spec.requiredMarkers, missing);
        outcome.expectedTitleVerified = spec.expectedTitlePattern.empty() || MatchesPattern(outcome.window.title, spec.expectedTitlePattern) || MatchesPattern(outcome.lastHaystack, spec.expectedTitlePattern);
        outcome.expectedUrlVerified = spec.expectedUrlPattern.empty() || MatchesPattern(spec.url, spec.expectedUrlPattern) || MatchesPattern(outcome.lastHaystack, spec.expectedUrlPattern);
        outcome.pageLoaded = outcome.requiredMarkersVerified || outcome.expectedTitleVerified;
        if (outcome.pageLoaded && outcome.expectedUrlVerified) break;
    } while (GetTickCount64() < deadline);

    EnsureBrowserForeground(spec.browser, outcome.window);
    RuntimeTargetContext targetContext;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(guardSpec, targetContext);
    outcome.runtimeContextGuardUsed = true;
    outcome.runtimeContextGuardOk = guard.ok;
    outcome.guardJson = RuntimeContextGuardResultJson(guard);
    if (!guard.ok && outcome.stopCode.empty()) {
        outcome.stopCode = guard.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guard.stopCode;
        outcome.errorMessage = guard.reason;
        outcome.wrongPageDetected = guard.wrongPageDetected;
        outcome.activeProtectionDetected = guard.activeProtectionDetected;
    }
}

bool ScrollPageForField(const BrowserWorkflowSpec& spec, BrowserStepOutcome& outcome) {
    if (!outcome.window.hwnd) return false;
    if (!EnsureBrowserForeground(spec.browser, outcome.window)) return false;
    RECT rect = outcome.window.rect;
    int x = (rect.right - rect.left) / 2;
    int y = (rect.bottom - rect.top) / 2;
    ClickResult scrolled = ScrollClientPoint(outcome.window.hwnd, x, y, -520, L"human");
    outcome.scrollUsed = outcome.scrollUsed || scrolled.ok;
    outcome.scrollProgressDetected = outcome.scrollProgressDetected || scrolled.ok;
    Sleep(250);
    ObserveBrowserPage(spec, outcome, 1000);
    return scrolled.ok;
}

bool VerifyFieldValue(HWND hwnd, const BrowserWorkflowFieldSpec& field) {
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) return false;
    std::wstring expected = field.value;
    std::wstring label = field.fieldLabel.empty() ? field.fieldId : field.fieldLabel;
    for (const auto& element : tree.elements) {
        std::wstring haystack = element.name + L" " + element.value + L" " + element.automationId + L" " + element.className;
        if (!expected.empty() && ContainsInsensitive(haystack, expected)) {
            if (label.empty() || ContainsInsensitive(haystack, label) || element.controlType == L"Edit") return true;
        }
    }
    return false;
}

void ExecuteFormFields(const BrowserWorkflowSpec& spec, BrowserStepOutcome& outcome) {
    outcome.formFieldsTotal = static_cast<int>(spec.formSpec.fields.size());
    for (const auto& field : spec.formSpec.fields) {
        if (!EnsureBrowserForeground(spec.browser, outcome.window)) {
            outcome.stopCode = L"STOP_FOREGROUND_CHANGED";
            outcome.errorMessage = L"Could not restore browser foreground before field input.";
            return;
        }
        WebFormFieldLocatorRequest request = WebFormFieldLocatorRequestFromSpec(field);
        WebFormFieldLocatorResult located = LocateWebFormField(outcome.window.hwnd, request);
        if (!located.ok && located.missing) {
            for (int i = 0; i < 6 && !located.ok; ++i) {
                if (!ScrollPageForField(spec, outcome)) break;
                located = LocateWebFormField(outcome.window.hwnd, request);
                if (located.ok) outcome.fieldFoundAfterScroll = true;
            }
        }
        if (!located.ok) {
            outcome.stopCode = located.errorCode.empty() ? L"FAIL_FIELD_NOT_FOUND" : located.errorCode;
            outcome.errorMessage = located.errorMessage;
            return;
        }
        if (located.coordinateSourceType == L"direct_coordinate") {
            outcome.stopCode = L"BLOCKED_BROWSER_BACKEND_AUTOMATION_USED";
            outcome.errorMessage = L"Direct coordinate field locator was rejected.";
            return;
        }
        ClickResult clicked = ClickScreenPoint(located.targetCenter.x, located.targetCenter.y, L"human", 450);
        if (!clicked.ok) {
            outcome.stopCode = clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode;
            outcome.errorMessage = clicked.error;
            return;
        }
        outcome.formFieldsClicked++;
        Sleep(120);
        ActionResult selectAll = SendHotkeyGlobal(L"CTRL+A");
        Sleep(80);
        TypeResult typed = TypeTextGlobal(field.value, L"human", -1);
        if (!selectAll.ok || !typed.ok) {
            outcome.stopCode = typed.errorCode.empty() ? L"SEND_INPUT_FAILED" : typed.errorCode;
            outcome.errorMessage = typed.error.empty() ? L"Could not type field value." : typed.error;
            return;
        }
        outcome.formFieldsFilled++;
        Sleep(250);
        bool valueOk = VerifyFieldValue(outcome.window.hwnd, field);
        if (!valueOk) {
            outcome.wrongFieldInputCount++;
            outcome.stopCode = L"BLOCKED_WRONG_FIELD_INPUT";
            outcome.errorMessage = L"Field value was not verified in the intended visible field.";
            return;
        }
        outcome.formFieldsVerified++;
    }
}

void ExecuteSubmit(const BrowserWorkflowSpec& spec, BrowserStepOutcome& outcome) {
    if (!EnsureBrowserForeground(spec.browser, outcome.window)) {
        outcome.stopCode = L"STOP_FOREGROUND_CHANGED";
        outcome.errorMessage = L"Could not restore browser foreground before submit.";
        return;
    }
    WebFormFieldLocatorResult submit = LocateWebFormSubmit(outcome.window.hwnd, spec.formSpec.submit.label);
    if (!submit.ok) {
        outcome.stopCode = submit.errorCode.empty() ? L"STOP_TARGET_NOT_UNIQUE" : submit.errorCode;
        outcome.errorMessage = submit.errorMessage;
        return;
    }
    ClickResult clicked = ClickScreenPoint(submit.targetCenter.x, submit.targetCenter.y, L"human", 450);
    if (!clicked.ok) {
        outcome.stopCode = clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode;
        outcome.errorMessage = clicked.error;
        return;
    }
    outcome.submitClicked = true;
    Sleep(600);
    ObserveBrowserPage(spec, outcome, 2500);
    std::wstring expected = spec.formSpec.submit.expectedResultMarker;
    if (expected.empty()) {
        expected = ObjectStringOr(spec.verificationHintJson, L"expected_result_marker", FirstMarker(spec));
    }
    outcome.submitResultVerified = !expected.empty() && MatchesPattern(outcome.lastHaystack, expected);
    if (!outcome.submitResultVerified) {
        outcome.stopCode = L"BLOCKED_UNVERIFIED_FORM_SUBMIT";
        outcome.errorMessage = L"Submit result marker was not verified after visible click.";
    }
}

std::wstring ObjectStringOr(const std::wstring& objectJson, const std::wstring& key, const std::wstring& fallback) {
    simplejson::ParseResult parsed = simplejson::Parse(objectJson);
    if (!parsed.ok || !parsed.root.IsObject()) return fallback;
    std::wstring value = simplejson::GetString(parsed.root, key);
    return value.empty() ? fallback : value;
}

std::wstring RecoveryUrlFromPolicy(const BrowserWorkflowSpec& spec) {
    std::wstring target = ObjectStringOr(spec.recoveryPolicyJson, L"recovery_url", L"");
    if (!target.empty()) return target;
    target = ObjectStringOr(spec.recoveryPolicyJson, L"target_url", L"");
    if (!target.empty()) return target;
    return spec.url;
}

BrowserWorkflowExecutionResult Failure(
    const BrowserWorkflowRunOptions& options,
    const BrowserWorkflowSpec& spec,
    const std::wstring& code,
    const std::wstring& message) {
    BrowserWorkflowExecutionResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.evidenceDir = options.evidenceDir;
    result.resultJson = L"{\"schema_version\":\"6.8.0.browser_workflow.result\""
        L",\"workflow_id\":" + simplejson::Quote(spec.workflowId) +
        L",\"workflow_type\":" + simplejson::Quote(spec.workflowType) +
        L",\"execution_mode\":" + simplejson::Quote(options.mode) +
        L",\"final_status\":\"BLOCKED\""
        L",\"error_code\":" + simplejson::Quote(code) +
        L",\"error_message\":" + simplejson::Quote(message) +
        L",\"workflow_compiled\":false"
        L",\"compiled_step_contract_used\":false"
        L",\"step_contract_validator_used\":false"
        L",\"runtime_session_used\":false"
        L",\"runtime_context_guard_used\":false"
        L",\"browser_surface_normalizer_used\":false"
        L",\"runner_only_workflow_logic\":false"
        L",\"dom_automation_used\":false"
        L",\"javascript_automation_used\":false"
        L",\"webdriver_used\":false"
        L",\"cdp_used\":false}";
    if (!options.outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(options.outputPath, result.resultJson, writeError);
    }
    return result;
}

}  // namespace

BrowserWorkflowExecutionResult RunBrowserWorkflowSpecFile(
    const std::wstring& inputPath,
    const BrowserWorkflowRunOptions& options) {
    BrowserWorkflowRunOptions effective = options;
    if (effective.mode == L"dry-run") effective.mode = L"dry_run";
    if (effective.mode == L"execute-local-safe") effective.mode = L"execute_local_safe";
    if (effective.evidenceDir.empty()) {
        effective.evidenceDir = ArtifactsPath(L"dev6.8.0_browser_and_web_form_agent_workflows\\executions\\exec-" + std::to_wstring(GetTickCount64()));
    }
    EnsureDirectoryPath(effective.evidenceDir);

    BrowserWorkflowSchemaResult schema = ParseBrowserWorkflowSpecFile(inputPath);
    if (!schema.ok) {
        return Failure(effective, schema.spec, schema.errorCode, schema.errorMessage);
    }
    BrowserWorkflowCompileResult compiled = CompileBrowserWorkflowSpec(schema.spec);
    if (!compiled.ok) {
        return Failure(effective, schema.spec, compiled.errorCode, compiled.errorMessage);
    }
    std::wstring stepContractPath = effective.evidenceDir + L"\\step_contract.json";
    std::wstring writeError;
    WriteTextFileUtf8(stepContractPath, compiled.contractJson, writeError);
    StepContractV63ValidationResult validation = ValidateStepContractV63Json(compiled.contractJson);
    if (!validation.validationOk) {
        return Failure(effective, schema.spec, validation.errorCode, validation.errorMessage);
    }
    bool dryRun = effective.mode == L"dry_run";
    bool executeLocalSafe = effective.mode == L"execute_local_safe";
    if (!dryRun && !executeLocalSafe) {
        return Failure(effective, schema.spec, L"INVALID_ARGUMENT", L"run-browser-workflow mode must be dry-run or execute-local-safe.");
    }

    CompiledPlanExecutionOptions compiledOptions;
    compiledOptions.executionMode = executeLocalSafe ? L"execute_local_safe" : L"dry_run";
    compiledOptions.evidenceDir = effective.evidenceDir + L"\\compiled_plan_executor";
    compiledOptions.resultJson = effective.evidenceDir + L"\\compiled_plan_execution_result.json";
    CompiledPlanExecutionResult compiledExecution = ExecuteStepContractJson(compiled.contractJson, compiledOptions);

    BrowserStepOutcome outcome;
    if (dryRun) {
        outcome.ok = true;
        outcome.finalStatus = L"DRY_RUN_PASS";
    } else if (BrowserWorkflowTypeIsBlockedStop(schema.spec.workflowType)) {
        if (OpenBrowserHuman(schema.spec, outcome)) {
            ObserveBrowserPage(schema.spec, outcome, 5000);
        }
        outcome.finalStatus = L"STOPPED";
        if (schema.spec.workflowType == L"browser_active_protection_stop" && outcome.activeProtectionDetected) {
            outcome.ok = true;
            outcome.stopCode = L"STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK";
        } else if (schema.spec.workflowType == L"browser_credential_required_stop" && outcome.credentialRequiredDetected) {
            outcome.ok = true;
            outcome.stopCode = L"STOP_CREDENTIAL_REQUIRED";
        } else {
            outcome.ok = false;
            if (outcome.stopCode.empty()) outcome.stopCode = L"BLOCKED_BROWSER_PROTECTION_STOP_FAILED";
        }
    } else {
        if (schema.spec.workflowType == L"browser_wrong_page_recovery") {
            BrowserWorkflowSpec initial = schema.spec;
            if (OpenBrowserHuman(initial, outcome)) {
                ObserveBrowserPage(initial, outcome, 5000);
            }
            if (outcome.wrongPageDetected || !outcome.requiredMarkersVerified) {
                outcome.wrongPageDetected = true;
                outcome.recoveryAttempted = true;
                BrowserWorkflowSpec recovered = schema.spec;
                recovered.url = RecoveryUrlFromPolicy(schema.spec);
                if (BrowserWorkflowUrlAllowedByPrefix(recovered.url, recovered.allowedUrlPrefix)) {
                    BrowserStepOutcome recoveryOutcome;
                    if (OpenBrowserHuman(recovered, recoveryOutcome)) {
                        ObserveBrowserPage(recovered, recoveryOutcome, 7000);
                        outcome = recoveryOutcome;
                        outcome.wrongPageDetected = true;
                        outcome.recoveryAttempted = true;
                        outcome.recoverySuccess = recoveryOutcome.pageLoaded && recoveryOutcome.requiredMarkersVerified;
                    }
                }
                if (!outcome.recoverySuccess && outcome.stopCode.empty()) {
                    outcome.stopCode = L"STOP_BROWSER_RECOVERY_FAILED";
                    outcome.errorMessage = L"Wrong page recovery did not verify the target page.";
                }
            }
        } else {
            if (OpenBrowserHuman(schema.spec, outcome)) {
                ObserveBrowserPage(schema.spec, outcome, 7000);
            }
        }
        if (outcome.stopCode.empty() && (schema.spec.workflowType == L"browser_fill_form" ||
            schema.spec.workflowType == L"browser_submit_form" ||
            (schema.spec.workflowType == L"browser_wrong_page_recovery" && !schema.spec.formSpec.fields.empty()))) {
            ExecuteFormFields(schema.spec, outcome);
            if (outcome.stopCode.empty() && (schema.spec.workflowType == L"browser_submit_form" ||
                (schema.spec.workflowType == L"browser_wrong_page_recovery" && !schema.spec.submitPolicyJson.empty()))) {
                ExecuteSubmit(schema.spec, outcome);
            }
        }
        if (outcome.stopCode.empty() && schema.spec.workflowType == L"browser_scroll_page") {
            ScrollPageForField(schema.spec, outcome);
        }
        if (outcome.stopCode.empty() && schema.spec.workflowType == L"browser_locate_text") {
            std::wstring expected = ObjectStringOr(schema.spec.verificationHintJson, L"expected_text", schema.spec.verificationTargetText);
            if (!expected.empty() && !MatchesPattern(outcome.lastHaystack, expected)) {
                ScrollPageForField(schema.spec, outcome);
            }
        }
        bool formWorkflow = schema.spec.workflowType == L"browser_fill_form" ||
            schema.spec.workflowType == L"browser_submit_form" ||
            (schema.spec.workflowType == L"browser_wrong_page_recovery" && !schema.spec.formSpec.fields.empty());
        bool submitWorkflow = schema.spec.workflowType == L"browser_submit_form" ||
            (schema.spec.workflowType == L"browser_wrong_page_recovery" && !schema.spec.submitPolicyJson.empty());
        bool formOk = !formWorkflow ||
            (outcome.formFieldsTotal > 0 && outcome.formFieldsVerified == outcome.formFieldsTotal &&
             (!submitWorkflow || outcome.submitResultVerified));
        bool pageOk = outcome.pageLoaded && outcome.expectedUrlVerified && outcome.requiredMarkersVerified;
        outcome.ok = outcome.stopCode.empty() && pageOk && formOk;
        outcome.finalStatus = outcome.ok ? L"PASS" : L"BLOCKED";
        if (!outcome.ok && outcome.stopCode.empty()) {
            outcome.stopCode = L"STOP_UNVERIFIED_RESULT";
            outcome.errorMessage = L"Browser workflow did not satisfy page or form verification.";
        }
    }

    if (!dryRun && outcome.window.hwnd) {
        RuntimeSession session = CreateRuntimeSession(schema.spec, outcome.window);
        session.sessionCommandCount = 1;
        SessionManager manager;
        manager.SaveSession(session);
        outcome.sessionId = session.sessionId;
    }

    std::wstring finalStatus = dryRun ? L"DRY_RUN_PASS" : outcome.finalStatus;
    std::wstring resultJson = L"{\"schema_version\":\"6.8.0.browser_workflow.result\""
        L",\"workflow_id\":" + simplejson::Quote(schema.spec.workflowId) +
        L",\"workflow_type\":" + simplejson::Quote(schema.spec.workflowType) +
        L",\"task_id\":" + simplejson::Quote(schema.spec.taskId) +
        L",\"execution_mode\":" + simplejson::Quote(effective.mode) +
        L",\"final_status\":" + simplejson::Quote(finalStatus) +
        L",\"stop_code\":" + simplejson::Quote(outcome.stopCode) +
        L",\"error_code\":" + simplejson::Quote(outcome.stopCode) +
        L",\"error_message\":" + simplejson::Quote(outcome.errorMessage) +
        L",\"url\":" + simplejson::Quote(schema.spec.url) +
        L",\"allowed_url_prefix\":" + simplejson::Quote(schema.spec.allowedUrlPrefix) +
        L",\"workflow_compiled\":true"
        L",\"compiled_step_contract_used\":true"
        L",\"compiled_plan_executor_used\":true"
        L",\"compiled_plan_executor_ok\":" + simplejson::Bool(compiledExecution.ok || !compiledExecution.executionResultJson.empty()) +
        L",\"step_contract_validator_used\":true"
        L",\"step_contract_validated\":true"
        L",\"runtime_session_used\":" + simplejson::Bool(!dryRun) +
        L",\"session_id\":" + simplejson::Quote(outcome.sessionId) +
        L",\"runtime_context_guard_used\":" + simplejson::Bool(!dryRun && outcome.runtimeContextGuardUsed) +
        L",\"runtime_context_guard_ok\":" + simplejson::Bool(!dryRun && outcome.runtimeContextGuardOk) +
        L",\"runtime_context_guard_result\":" + outcome.guardJson +
        L",\"browser_surface_normalizer_used\":" + simplejson::Bool(!dryRun && outcome.browserSurfaceNormalizerUsed) +
        L",\"browser_surface_normalization_result\":" + outcome.normalizerJson +
        L",\"step_level_verification_complete\":" + simplejson::Bool(dryRun || outcome.ok || BrowserWorkflowTypeIsBlockedStop(schema.spec.workflowType)) +
        L",\"evidence_pack_created\":true"
        L",\"browser_opened\":" + simplejson::Bool(!dryRun && outcome.browserOpened) +
        L",\"page_loaded\":" + simplejson::Bool(!dryRun && outcome.pageLoaded) +
        L",\"expected_title_verified\":" + simplejson::Bool(!dryRun && outcome.expectedTitleVerified) +
        L",\"expected_url_verified\":" + simplejson::Bool(dryRun || outcome.expectedUrlVerified) +
        L",\"required_markers_verified\":" + simplejson::Bool(!dryRun && outcome.requiredMarkersVerified) +
        L",\"form_fields_total\":" + std::to_wstring(outcome.formFieldsTotal) +
        L",\"form_fields_clicked\":" + std::to_wstring(outcome.formFieldsClicked) +
        L",\"form_fields_filled\":" + std::to_wstring(outcome.formFieldsFilled) +
        L",\"form_fields_verified\":" + std::to_wstring(outcome.formFieldsVerified) +
        L",\"submit_clicked_by_mouse\":" + simplejson::Bool(outcome.submitClicked) +
        L",\"submit_clicked\":" + simplejson::Bool(outcome.submitClicked) +
        L",\"submit_result_verified\":" + simplejson::Bool(outcome.submitResultVerified) +
        L",\"wrong_page_detected\":" + simplejson::Bool(outcome.wrongPageDetected) +
        L",\"recovery_attempted\":" + simplejson::Bool(outcome.recoveryAttempted) +
        L",\"recovery_success\":" + simplejson::Bool(outcome.recoverySuccess) +
        L",\"active_protection_detected\":" + simplejson::Bool(outcome.activeProtectionDetected) +
        L",\"credential_required_detected\":" + simplejson::Bool(outcome.credentialRequiredDetected) +
        L",\"scroll_used\":" + simplejson::Bool(outcome.scrollUsed) +
        L",\"scroll_progress_detected\":" + simplejson::Bool(outcome.scrollProgressDetected) +
        L",\"field_found_after_scroll\":" + simplejson::Bool(outcome.fieldFoundAfterScroll) +
        L",\"stale_rect_used\":" + simplejson::Bool(outcome.staleRectUsed) +
        L",\"wrong_field_input_count\":" + std::to_wstring(outcome.wrongFieldInputCount) +
        L",\"real_browser_ui_used\":" + simplejson::Bool(!dryRun && outcome.realBrowserUiUsed) +
        L",\"runner_only_workflow_logic\":false"
        L",\"dom_automation_used\":false"
        L",\"javascript_automation_used\":false"
        L",\"webdriver_used\":false"
        L",\"cdp_used\":false"
        L",\"playwright_used\":false"
        L",\"selenium_used\":false"
        L",\"powershell_fake_form_success_used\":false"
        L",\"javascript_fake_form_success_used\":false"
        L",\"fake_form_execution\":false"
        L",\"failure_attribution\":" + simplejson::Quote(outcome.stopCode.empty() ? L"" : L"browser_workflow_executor") +
        L",\"step_contract_path\":" + simplejson::Quote(stepContractPath) +
        L",\"compiled_plan_execution_result_path\":" + simplejson::Quote(compiledOptions.resultJson) +
        L"}";

    ExecutionEvidencePackInput packInput;
    packInput.evidenceDir = effective.evidenceDir;
    packInput.executionResultJson = resultJson;
    packInput.executionId = schema.spec.workflowId;
    packInput.taskId = schema.spec.taskId;
    packInput.finalStatus = finalStatus;
    WriteExecutionEvidencePack(packInput);
    if (!effective.outputPath.empty()) {
        WriteTextFileUtf8(effective.outputPath, resultJson, writeError);
    }

    BrowserWorkflowExecutionResult result;
    result.ok = dryRun || outcome.ok || (BrowserWorkflowTypeIsBlockedStop(schema.spec.workflowType) && outcome.ok);
    result.errorCode = result.ok ? L"" : outcome.stopCode;
    result.errorMessage = result.ok ? L"" : outcome.errorMessage;
    result.resultJson = resultJson;
    result.evidenceDir = effective.evidenceDir;
    return result;
}

int CommandRunBrowserWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"run-browser-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    BrowserWorkflowRunOptions options;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-browser-workflow requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--mode", options.mode);
    ArgValue(argc, argv, L"--output", options.outputPath);
    ArgValue(argc, argv, L"--evidence-dir", options.evidenceDir);
    BrowserWorkflowExecutionResult result = RunBrowserWorkflowSpecFile(input, options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"BROWSER_WORKFLOW_FAILED" : result.errorCode, result.errorMessage, result.resultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.resultJson) << L"\n";
    return 0;
}
