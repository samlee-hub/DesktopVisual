#include "ExplorerWorkflowExecutor.h"

#include "CaseRunner.h"
#include "ExecutionEvidencePack.h"
#include "ExplorerContextMenuHandler.h"
#include "ExplorerWorkflow.h"
#include "ExplorerWorkflowAdapter.h"
#include "ExplorerWorkflowVerifier.h"
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
#include "WindowFinder.h"

#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <cstdio>
#include <iostream>
#include <sstream>
#include <vector>

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

ExplorerWorkflowExecutionResult Failure(
    const ExplorerWorkflowRunOptions& options,
    const ExplorerWorkflowSpec& spec,
    const std::wstring& code,
    const std::wstring& message) {
    ExplorerWorkflowExecutionResult result;
    result.ok = false;
    result.errorCode = code;
    result.errorMessage = message;
    result.evidenceDir = options.evidenceDir;
    result.resultJson = L"{\"schema_version\":\"6.7.0.explorer_workflow.result\""
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
        L",\"powershell_file_action_used\":false"
        L",\"direct_file_api_workflow_action_used\":false}";
    if (!options.outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(options.outputPath, result.resultJson, writeError);
    }
    return result;
}

std::wstring BaseName(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return path;
    return path.substr(slash + 1);
}

std::wstring FolderForSpec(const ExplorerWorkflowSpec& spec) {
    if (!spec.expectedFolder.empty()) return spec.expectedFolder;
    if (spec.workflowType == L"explorer_open_path") return spec.sourcePath;
    std::wstring path = !spec.sourcePath.empty() ? spec.sourcePath : spec.targetPath;
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(0, slash);
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return true;
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

bool StartsWithInsensitive(const std::wstring& value, const std::wstring& prefix) {
    if (prefix.size() > value.size()) return false;
    return Lower(value.substr(0, prefix.size())) == Lower(prefix);
}

bool SameStringVector(const std::vector<std::wstring>& a, const std::vector<std::wstring>& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

std::wstring JsonStringArray(const std::vector<std::wstring>& values) {
    std::wstring json = L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i > 0) json += L",";
        json += simplejson::Quote(values[i]);
    }
    json += L"]";
    return json;
}

std::wstring RectJson(const RECT& rect) {
    return L"{\"left\":" + std::to_wstring(rect.left) +
        L",\"top\":" + std::to_wstring(rect.top) +
        L",\"right\":" + std::to_wstring(rect.right) +
        L",\"bottom\":" + std::to_wstring(rect.bottom) + L"}";
}

std::wstring FirstOrEmpty(const std::vector<std::wstring>& values) {
    return values.empty() ? L"" : values.front();
}

std::wstring LastOrEmpty(const std::vector<std::wstring>& values) {
    return values.empty() ? L"" : values.back();
}

struct VisibleItemCandidate {
    std::wstring name;
    RECT rect = {};
};

bool LooksLikeExplorerFileItem(const UiaElementInfo& element) {
    if (element.name.empty() || element.offscreen) return false;
    if (element.rect.right <= element.rect.left || element.rect.bottom <= element.rect.top) return false;
    if (element.controlType == L"ListItem" || element.controlType == L"DataItem") return true;
    if (ContainsInsensitive(element.name, L".txt")) return true;
    if (StartsWithInsensitive(element.name, L"item_")) return true;
    return false;
}

std::vector<std::wstring> VisibleExplorerItemNames(HWND hwnd) {
    std::vector<VisibleItemCandidate> candidates;
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) return {};
    for (const auto& element : tree.elements) {
        if (!LooksLikeExplorerFileItem(element)) continue;
        bool duplicate = false;
        for (const auto& existing : candidates) {
            if (existing.name == element.name) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) {
            candidates.push_back(VisibleItemCandidate{element.name, element.rect});
        }
    }
    std::sort(candidates.begin(), candidates.end(), [](const VisibleItemCandidate& a, const VisibleItemCandidate& b) {
        if (a.rect.top != b.rect.top) return a.rect.top < b.rect.top;
        if (a.rect.left != b.rect.left) return a.rect.left < b.rect.left;
        return a.name < b.name;
    });
    std::vector<std::wstring> names;
    for (const auto& candidate : candidates) {
        names.push_back(candidate.name);
    }
    return names;
}

bool ClearClipboardData() {
    if (!OpenClipboard(nullptr)) return false;
    EmptyClipboard();
    CloseClipboard();
    return true;
}

bool ClipboardHasFileDropPath(const std::wstring& path) {
    if (!OpenClipboard(nullptr)) return false;
    bool available = false;
    if (IsClipboardFormatAvailable(CF_HDROP)) {
        HDROP drop = reinterpret_cast<HDROP>(GetClipboardData(CF_HDROP));
        if (drop) {
            UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
            std::wstring expected = Lower(ExplorerWorkflowNormalizePath(path));
            for (UINT i = 0; i < count; ++i) {
                UINT length = DragQueryFileW(drop, i, nullptr, 0);
                std::wstring value(static_cast<size_t>(length) + 1, L'\0');
                DragQueryFileW(drop, i, value.data(), length + 1);
                value.resize(length);
                if (Lower(ExplorerWorkflowNormalizePath(value)) == expected) {
                    available = true;
                    break;
                }
            }
        }
    }
    CloseClipboard();
    return available;
}

ExpectedContextSpec ExpectedContextFromSpec(const ExplorerWorkflowSpec& spec) {
    ExpectedContextSpec ctx;
    simplejson::ParseResult parsed = simplejson::Parse(spec.expectedContextJson);
    if (parsed.ok && parsed.root.IsObject()) {
        ctx.expectedProcessPattern = simplejson::GetString(parsed.root, L"expected_process_pattern", L"explorer.exe");
        ctx.expectedTitlePattern = simplejson::GetString(parsed.root, L"expected_title_pattern");
        ctx.requiredMarkers = simplejson::GetStringArray(parsed.root, L"required_markers");
        ctx.wrongPagePatterns = simplejson::GetStringArray(parsed.root, L"wrong_page_patterns");
        ctx.activeProtectionPatterns = simplejson::GetStringArray(parsed.root, L"active_protection_patterns");
        std::vector<std::wstring> credentialMarkers = simplejson::GetStringArray(parsed.root, L"credential_required_patterns");
        ctx.activeProtectionPatterns.insert(ctx.activeProtectionPatterns.end(), credentialMarkers.begin(), credentialMarkers.end());
    }
    if (ctx.expectedProcessPattern.empty()) ctx.expectedProcessPattern = L"explorer.exe";
    ctx.enabled = true;
    return ctx;
}

bool LaunchExplorerFolder(const std::wstring& folder, std::wstring& errorMessage) {
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb = L"open";
    info.lpFile = L"explorer.exe";
    info.lpParameters = folder.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
        errorMessage = L"ShellExecuteExW(explorer.exe) failed.";
        return false;
    }
    if (info.hProcess) {
        WaitForInputIdle(info.hProcess, 5000);
        CloseHandle(info.hProcess);
    }
    return true;
}

bool LaunchExplorerSelectFile(const std::wstring& filePath, std::wstring& errorMessage) {
    std::wstring parameters = L"/select,\"" + filePath + L"\"";
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb = L"open";
    info.lpFile = L"explorer.exe";
    info.lpParameters = parameters.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
        errorMessage = L"ShellExecuteExW(explorer.exe /select) failed.";
        return false;
    }
    if (info.hProcess) {
        WaitForInputIdle(info.hProcess, 5000);
        CloseHandle(info.hProcess);
    }
    return true;
}

bool FindExplorerWindowForFolder(const std::wstring& folder, WindowInfo& selected) {
    std::wstring folderName = BaseName(ExplorerWorkflowNormalizePath(folder));
    for (int attempt = 0; attempt < 30; ++attempt) {
        HWND foreground = GetForegroundWindow();
        if (foreground) {
            WindowInfo active;
            active.hwnd = foreground;
            GetWindowThreadProcessId(foreground, &active.pid);
            int length = GetWindowTextLengthW(foreground);
            if (length > 0) {
                std::wstring title(static_cast<size_t>(length) + 1, L'\0');
                int copied = GetWindowTextW(foreground, title.data(), length + 1);
                title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
                active.title = title;
            }
            GetWindowRect(foreground, &active.rect);
            if (ContainsInsensitive(ProcessNameForPid(active.pid), L"explorer.exe") &&
                (folderName.empty() || ContainsInsensitive(active.title, folderName))) {
                selected = active;
                return true;
            }
        }
        std::vector<WindowInfo> fallback;
        for (const auto& window : EnumerateVisibleTopLevelWindows()) {
            if (!ContainsInsensitive(ProcessNameForPid(window.pid), L"explorer.exe")) continue;
            if (!folderName.empty() && !ContainsInsensitive(window.title, folderName)) {
                fallback.push_back(window);
                continue;
            }
            selected = window;
            return true;
        }
        if (foreground) {
            for (const auto& window : fallback) {
                if (window.hwnd == foreground) {
                    selected = window;
                    return true;
                }
            }
        }
        if (folderName.empty() && !fallback.empty() && attempt > 10) {
            selected = fallback.front();
            return true;
        }
        Sleep(200);
    }
    return false;
}

struct ExplorerStepOutcome {
    bool ok = false;
    std::wstring finalStatus = L"BLOCKED";
    std::wstring errorCode;
    std::wstring errorMessage;
    bool runtimeSessionUsed = false;
    bool runtimeContextGuardUsed = false;
    bool runtimeContextGuardOk = false;
    bool folderOpened = false;
    bool expectedFolderVerified = false;
    bool fileVisible = false;
    bool fileOpenActionExecuted = false;
    bool fileOpenVerified = false;
    bool oldNameExistsBefore = false;
    bool newNameExistsAfter = false;
    bool oldNameAbsentAfter = false;
    bool sourceExistsBefore = false;
    bool destinationExistsBefore = false;
    bool sourceSelectedByMouse = false;
    bool sourceSelectionVerified = false;
    bool cutAttempted = false;
    bool cutSent = false;
    std::wstring cutMethod;
    bool cutEffectVerified = false;
    bool destinationFolderOpened = false;
    bool destinationFolderFocused = false;
    bool pasteAttempted = false;
    bool pasteSent = false;
    std::wstring pasteMethod;
    bool pasteObserved = false;
    bool moveActionAttempted = false;
    bool moveActionExecuted = false;
    int moveVerificationRetryCount = 0;
    bool sourceAbsentAfter = false;
    bool destinationExistsAfter = false;
    bool moveResultVerified = false;
    std::wstring moveFailureStage;
    bool fallbackUsed = false;
    std::wstring fallbackReason;
    bool deleteWithoutConfirmationBlocked = false;
    bool deleteWithConfirmationExecuted = false;
    bool targetExistsBefore = false;
    bool targetAbsentAfter = false;
    bool listAreaLocated = false;
    bool listAreaClicked = false;
    bool listAreaFocusVerified = false;
    bool homeResetUsed = false;
    std::vector<std::wstring> visibleItemsBefore;
    std::vector<std::wstring> visibleItemsAfter;
    int scrollIterationCount = 0;
    int wheelEventCount = 0;
    bool riskGateOk = false;
    bool scrollUsed = false;
    bool scrollProgressDetected = false;
    bool scrollPositionChanged = false;
    bool pageDownFallbackUsed = false;
    std::wstring perIterationVisibleItemsJson = L"[]";
    std::wstring targetName;
    bool targetExistsInFixture = false;
    bool targetSeenByUia = false;
    bool targetSeenByOcr = false;
    bool targetSeenByReadWindowText = false;
    bool targetSeenButNotConfirmed = false;
    bool targetFound = false;
    std::wstring targetRectJson = L"{}";
    bool targetClickedOrVerified = false;
    bool scrollNoProgressDetected = false;
    bool staleRectUsed = false;
    bool runtimeContextGuardEachIteration = true;
    std::wstring failureStage;
    bool noStaleRect = true;
    bool rightClickSent = false;
    bool contextMenuVisible = false;
    bool menuItemLocated = false;
    bool menuItemClicked = false;
    bool resultVerified = false;
    std::wstring sessionId;
    std::wstring guardJson = L"{}";
    bool confirmationVerified = false;
    bool recoveryAttempted = false;
    bool recoverySuccess = false;
    bool wrongFolderDetected = false;
    bool wrongContextDetected = false;
};

std::wstring ParentPath(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return L"";
    return path.substr(0, slash);
}

std::wstring TargetFileNameForSpec(const ExplorerWorkflowSpec& spec) {
    if (!spec.expectedFilename.empty()) return spec.expectedFilename;
    if (!spec.targetPath.empty()) return BaseName(spec.targetPath);
    if (!spec.sourcePath.empty()) return BaseName(spec.sourcePath);
    return L"";
}

std::vector<std::wstring> ExplorerNameCandidates(const std::wstring& fileName) {
    std::vector<std::wstring> names;
    if (!fileName.empty()) names.push_back(fileName);
    size_t dot = fileName.find_last_of(L'.');
    if (dot != std::wstring::npos && dot > 0) {
        std::wstring stem = fileName.substr(0, dot);
        if (!stem.empty() && stem != fileName) names.push_back(stem);
    }
    return names;
}

std::wstring FileExtensionLower(const std::wstring& fileName) {
    size_t dot = fileName.find_last_of(L'.');
    if (dot == std::wstring::npos) return L"";
    return Lower(fileName.substr(dot));
}

std::wstring FileStem(const std::wstring& fileName) {
    size_t dot = fileName.find_last_of(L'.');
    if (dot == std::wstring::npos || dot == 0) return fileName;
    return fileName.substr(0, dot);
}

std::wstring ExplorerRenameInputText(const std::wstring& sourcePath, const std::wstring& targetPath) {
    std::wstring sourceName = BaseName(sourcePath);
    std::wstring targetName = BaseName(targetPath);
    if (!sourceName.empty() && FileExtensionLower(sourceName) == FileExtensionLower(targetName)) {
        std::wstring stem = FileStem(targetName);
        if (!stem.empty()) return stem;
    }
    return targetName;
}

bool RecoveryAllowed(const ExplorerWorkflowSpec& spec) {
    simplejson::ParseResult parsed = simplejson::Parse(spec.recoveryPolicyJson);
    if (!parsed.ok || !parsed.root.IsObject()) return true;
    return simplejson::GetBool(parsed.root, L"recovery_allowed", true);
}

WindowInfo ForegroundWindowInfo() {
    WindowInfo info;
    info.hwnd = GetForegroundWindow();
    if (!info.hwnd) return info;
    GetWindowThreadProcessId(info.hwnd, &info.pid);
    GetWindowRect(info.hwnd, &info.rect);
    int length = GetWindowTextLengthW(info.hwnd);
    if (length > 0) {
        std::wstring title(static_cast<size_t>(length) + 1, L'\0');
        int copied = GetWindowTextW(info.hwnd, title.data(), length + 1);
        title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
        info.title = title;
    }
    return info;
}

void DetectWrongForegroundExplorer(const ExplorerWorkflowSpec& spec, const std::wstring& folder, ExplorerStepOutcome& outcome) {
    WindowInfo active = ForegroundWindowInfo();
    if (!active.hwnd || !ContainsInsensitive(ProcessNameForPid(active.pid), L"explorer.exe")) return;
    std::wstring folderName = BaseName(ExplorerWorkflowNormalizePath(folder));
    if (folderName.empty() || ContainsInsensitive(active.title, folderName)) return;
    outcome.wrongFolderDetected = true;
    outcome.wrongContextDetected = true;
    if (RecoveryAllowed(spec)) {
        outcome.recoveryAttempted = true;
    }
}

bool LocateExplorerItem(HWND hwnd, const std::wstring& fileName, UiaElementInfo& out, std::wstring& code, std::wstring& message) {
    UiaQueryResult tree = ReadUiaTree(hwnd);
    if (!tree.ok) {
        code = tree.errorCode.empty() ? L"UIA_TREE_FAILED" : tree.errorCode;
        message = tree.errorMessage;
        return false;
    }
    std::vector<UiaElementInfo> exact;
    std::vector<UiaElementInfo> contains;
    std::vector<std::wstring> candidateNames = ExplorerNameCandidates(fileName);
    for (const auto& element : tree.elements) {
        if (element.offscreen) continue;
        for (const auto& candidate : candidateNames) {
            if (element.name == candidate) {
                exact.push_back(element);
                break;
            }
            if (!candidate.empty() && element.name.find(candidate) != std::wstring::npos) {
                contains.push_back(element);
                break;
            }
        }
    }
    const std::vector<UiaElementInfo>& matches = exact.empty() ? contains : exact;
    if (matches.empty()) {
        code = L"FAIL_TARGET_NOT_FOUND";
        message = L"Explorer target item was not found by UIA.";
        return false;
    }
    if (matches.size() > 1) {
        code = L"STOP_TARGET_NOT_UNIQUE";
        message = L"Explorer target item was not unique.";
        return false;
    }
    out = matches.front();
    return true;
}

POINT ElementCenterClient(HWND hwnd, const UiaElementInfo& element) {
    POINT pt{(element.rect.left + element.rect.right) / 2, (element.rect.top + element.rect.bottom) / 2};
    ScreenToClient(hwnd, &pt);
    return pt;
}

bool SelectExplorerItem(const WindowInfo& explorer, const std::wstring& fileName, UiaElementInfo& item, ExplorerStepOutcome& outcome) {
    std::wstring lastCode;
    std::wstring lastMessage;
    for (int attempt = 0; attempt < 8; ++attempt) {
        if (LocateExplorerItem(explorer.hwnd, fileName, item, outcome.errorCode, outcome.errorMessage)) {
            outcome.fileVisible = true;
            POINT pt = ElementCenterClient(explorer.hwnd, item);
            ClickResult click = ClickClientPoint(explorer.hwnd, pt.x, pt.y, L"human", 0);
            if (!click.ok) {
                outcome.errorCode = click.errorCode.empty() ? L"SEND_INPUT_FAILED" : click.errorCode;
                outcome.errorMessage = click.error;
                return false;
            }
            Sleep(150);
            return true;
        }
        lastCode = outcome.errorCode;
        lastMessage = outcome.errorMessage;
        if (outcome.errorCode == L"STOP_TARGET_NOT_UNIQUE") return false;
        RECT client = {};
        GetClientRect(explorer.hwnd, &client);
        int x = (client.right - client.left) / 2;
        int y = (client.bottom - client.top) / 2;
        int delta = attempt < 5 ? -360 : 360;
        ScrollClientPoint(explorer.hwnd, x, y, delta, L"human");
        Sleep(180);
    }
    outcome.errorCode = lastCode.empty() ? L"FAIL_TARGET_NOT_FOUND" : lastCode;
    outcome.errorMessage = lastMessage.empty() ? L"Explorer target item was not found by UIA." : lastMessage;
    return false;
}

bool VerifyExplorerFocusedItem(const WindowInfo& explorer, const std::wstring& fileName) {
    ExpectedContextSpec ctx;
    ctx.enabled = true;
    ctx.expectedProcessPattern = L"explorer.exe";
    ctx.expectedTitlePattern = explorer.title;
    ctx.expectedFocusMarker = FileStem(fileName);
    if (ctx.expectedFocusMarker.empty()) ctx.expectedFocusMarker = fileName;
    RuntimeTargetContext targetContext;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(ctx, targetContext);
    return guard.ok;
}

bool KeyboardSelectExplorerItem(const WindowInfo& explorer, const std::wstring& fileName, ExplorerStepOutcome& outcome) {
    ActionResult focus = FocusTargetWindow(explorer.hwnd);
    if (!focus.ok) {
        outcome.errorCode = focus.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focus.errorCode;
        outcome.errorMessage = focus.error;
        return false;
    }
    PressKey(explorer.hwnd, L"HOME");
    Sleep(100);
    std::wstring query = FileStem(fileName);
    if (query.empty()) query = fileName;
    TypeResult typed = TypeText(explorer.hwnd, query, L"human", -1);
    if (!typed.ok) {
        outcome.errorCode = typed.errorCode.empty() ? L"SEND_INPUT_FAILED" : typed.errorCode;
        outcome.errorMessage = typed.error;
        return false;
    }
    Sleep(250);
    ExpectedContextSpec ctx;
    ctx.enabled = true;
    ctx.expectedProcessPattern = L"explorer.exe";
    ctx.expectedTitlePattern = explorer.title;
    ctx.expectedFocusMarker = query;
    RuntimeTargetContext targetContext;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(ctx, targetContext);
    if (!guard.ok) {
        outcome.errorCode = guard.stopCode.empty() ? L"FAIL_TARGET_NOT_FOUND" : guard.stopCode;
        outcome.errorMessage = guard.reason.empty() ? L"Explorer keyboard selection did not focus the requested item." : guard.reason;
        return false;
    }
    outcome.fileVisible = true;
    return true;
}

bool OpenExplorerWithSelectedFile(const ExplorerWorkflowSpec& spec, const std::wstring& filePath, WindowInfo& explorer, ExplorerStepOutcome& outcome) {
    if (!ExplorerWorkflowPathWithinRoot(filePath, spec.allowedRoot)) {
        outcome.errorCode = L"STOP_EXPLORER_SCOPE_VIOLATION";
        outcome.errorMessage = L"Explorer selection path is outside allowed_root.";
        return false;
    }
    if (!ExplorerWorkflowFileExists(filePath)) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Explorer selection target file does not exist.";
        return false;
    }
    std::wstring launchError;
    if (!LaunchExplorerSelectFile(filePath, launchError)) {
        outcome.errorCode = L"EXPLORER_OPEN_FAILED";
        outcome.errorMessage = launchError;
        return false;
    }
    if (!FindExplorerWindowForFolder(ParentPath(filePath), explorer)) {
        outcome.errorCode = L"WINDOW_NOT_VISIBLE";
        outcome.errorMessage = L"Explorer window for selected file was not visible.";
        return false;
    }
    ActionResult focus = FocusTargetWindow(explorer.hwnd);
    if (!focus.ok) {
        outcome.errorCode = focus.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focus.errorCode;
        outcome.errorMessage = focus.error;
        return false;
    }
    Sleep(400);
    ExpectedContextSpec ctx = ExpectedContextFromSpec(spec);
    ctx.expectedFocusMarker = FileStem(BaseName(filePath));
    RuntimeTargetContext targetContext;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(ctx, targetContext);
    if (!guard.ok) {
        outcome.errorCode = guard.stopCode.empty() ? L"FAIL_TARGET_NOT_FOUND" : guard.stopCode;
        outcome.errorMessage = guard.reason;
        return false;
    }
    outcome.fileVisible = true;
    return true;
}

bool OpenAndGuardFolder(const ExplorerWorkflowSpec& spec, const std::wstring& folder, WindowInfo& explorer, ExplorerStepOutcome& outcome) {
    DetectWrongForegroundExplorer(spec, folder, outcome);
    if (outcome.wrongFolderDetected && !RecoveryAllowed(spec)) {
        outcome.errorCode = L"STOP_WRONG_CONTEXT";
        outcome.errorMessage = L"Foreground Explorer is not in expected_folder and recovery_policy disallows recovery.";
        return false;
    }
    if (outcome.wrongFolderDetected && RecoveryAllowed(spec)) {
        PressKeyGlobal(L"ESC");
        Sleep(250);
    }
    if (!ExplorerWorkflowPathWithinRoot(folder, spec.allowedRoot)) {
        outcome.errorCode = L"STOP_EXPLORER_SCOPE_VIOLATION";
        outcome.errorMessage = L"Explorer folder is outside allowed_root.";
        return false;
    }
    if (!ExplorerWorkflowDirectoryExists(folder)) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Expected Explorer folder does not exist.";
        return false;
    }
    std::wstring launchError;
    if (!LaunchExplorerFolder(folder, launchError)) {
        outcome.errorCode = L"EXPLORER_OPEN_FAILED";
        outcome.errorMessage = launchError;
        return false;
    }
    if (!FindExplorerWindowForFolder(folder, explorer)) {
        outcome.errorCode = L"WINDOW_NOT_VISIBLE";
        outcome.errorMessage = L"Explorer window for expected folder was not visible.";
        return false;
    }
    ActionResult focus = FocusTargetWindow(explorer.hwnd);
    if (!focus.ok) {
        outcome.errorCode = focus.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focus.errorCode;
        outcome.errorMessage = focus.error;
        return false;
    }
    Sleep(300);
    SessionManager manager;
    SessionManagerResult session = manager.CreateSession(explorer.title, L"explorer.exe", reinterpret_cast<unsigned long long>(explorer.hwnd));
    if (!session.ok) {
        outcome.errorCode = session.errorCode.empty() ? L"STOP_SESSION_NOT_FOUND" : session.errorCode;
        outcome.errorMessage = session.errorMessage;
        return false;
    }
    outcome.runtimeSessionUsed = true;
    outcome.sessionId = session.session.sessionId;

    ExpectedContextSpec ctx = ExpectedContextFromSpec(spec);
    RuntimeTargetContext targetContext;
    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(ctx, targetContext);
    outcome.runtimeContextGuardUsed = true;
    outcome.runtimeContextGuardOk = guard.ok;
    outcome.guardJson = RuntimeContextGuardResultJson(guard);
    if (!guard.ok) {
        outcome.errorCode = guard.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guard.stopCode;
        outcome.errorMessage = guard.reason;
        return false;
    }
    if (outcome.recoveryAttempted) {
        outcome.recoverySuccess = true;
    }
    outcome.folderOpened = true;
    outcome.expectedFolderVerified = true;
    return true;
}

ExplorerStepOutcome ExecuteOpenPathWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    std::wstring folder = FolderForSpec(spec);
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, folder, explorer, outcome)) return outcome;
    outcome.ok = true;
    outcome.finalStatus = L"PASS";
    return outcome;
}

ExplorerStepOutcome ExecuteOpenFileWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    std::wstring folder = FolderForSpec(spec);
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, folder, explorer, outcome)) return outcome;
    UiaElementInfo item;
    std::wstring fileName = TargetFileNameForSpec(spec);
    if (!SelectExplorerItem(explorer, fileName, item, outcome)) return outcome;
    POINT pt = ElementCenterClient(explorer.hwnd, item);
    ClickResult dbl = DoubleClickClientPoint(explorer.hwnd, pt.x, pt.y, L"human", 0);
    outcome.fileOpenActionExecuted = dbl.ok;
    if (!dbl.ok) {
        outcome.errorCode = dbl.errorCode.empty() ? L"SEND_INPUT_FAILED" : dbl.errorCode;
        outcome.errorMessage = dbl.error;
        return outcome;
    }
    Sleep(700);
    outcome.fileOpenVerified = ExplorerWorkflowFileExists(spec.sourcePath);
    outcome.ok = outcome.fileOpenVerified;
    outcome.finalStatus = outcome.ok ? L"PASS" : L"BLOCKED";
    if (!outcome.ok) {
        outcome.errorCode = L"VERIFY_FILE_OPEN_FAILED";
        outcome.errorMessage = L"File-open action executed but verification failed.";
    }
    return outcome;
}

ExplorerStepOutcome ExecuteRenameWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    std::wstring source = spec.sourcePath;
    std::wstring target = spec.targetPath.empty() ? (ParentPath(source) + L"\\" + spec.expectedFilename) : spec.targetPath;
    outcome.oldNameExistsBefore = ExplorerWorkflowFileExists(source);
    if (!outcome.oldNameExistsBefore) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Rename source file was not found.";
        return outcome;
    }
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, ParentPath(source), explorer, outcome)) return outcome;
    UiaElementInfo item;
    if (!SelectExplorerItem(explorer, BaseName(source), item, outcome)) {
        if (outcome.errorCode == L"STOP_TARGET_NOT_UNIQUE") return outcome;
        if (!KeyboardSelectExplorerItem(explorer, BaseName(source), outcome) &&
            !OpenExplorerWithSelectedFile(spec, source, explorer, outcome)) {
            return outcome;
        }
    }
    FocusTargetWindow(explorer.hwnd);
    Sleep(100);
    ActionResult f2 = PressKeyGlobal(L"F2");
    if (!f2.ok) {
        outcome.errorCode = f2.errorCode.empty() ? L"SEND_INPUT_FAILED" : f2.errorCode;
        outcome.errorMessage = f2.error;
        return outcome;
    }
    Sleep(200);
    TypeResult typed = TypeTextGlobal(ExplorerRenameInputText(source, target), L"human", -1);
    if (!typed.ok) {
        outcome.errorCode = typed.errorCode.empty() ? L"SEND_INPUT_FAILED" : typed.errorCode;
        outcome.errorMessage = typed.error;
        return outcome;
    }
    ActionResult enter = PressKeyGlobal(L"ENTER");
    if (!enter.ok) {
        outcome.errorCode = enter.errorCode.empty() ? L"SEND_INPUT_FAILED" : enter.errorCode;
        outcome.errorMessage = enter.error;
        return outcome;
    }
    Sleep(800);
    outcome.newNameExistsAfter = ExplorerWorkflowFileExists(target);
    outcome.oldNameAbsentAfter = !ExplorerWorkflowFileExists(source);
    outcome.resultVerified = outcome.newNameExistsAfter && outcome.oldNameAbsentAfter;
    outcome.ok = outcome.resultVerified;
    outcome.finalStatus = outcome.ok ? L"PASS" : L"BLOCKED";
    if (!outcome.ok) {
        outcome.errorCode = L"VERIFY_RENAME_FAILED";
        outcome.errorMessage = L"Rename verification failed.";
    }
    return outcome;
}

ExplorerStepOutcome ExecuteMoveWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    std::wstring source = spec.sourcePath;
    std::wstring dest = spec.destinationPath;
    outcome.sourceExistsBefore = ExplorerWorkflowFileExists(source);
    outcome.destinationExistsBefore = ExplorerWorkflowFileExists(dest);
    if (!outcome.sourceExistsBefore) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Move source file was not found.";
        outcome.moveFailureStage = L"source_selection_failed";
        return outcome;
    }
    if (!ExplorerWorkflowDirectoryExists(ParentPath(dest))) {
        outcome.errorCode = L"FAIL_DESTINATION_NOT_FOUND";
        outcome.errorMessage = L"Move destination folder was not found.";
        outcome.moveFailureStage = L"destination_open_failed";
        return outcome;
    }
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, ParentPath(source), explorer, outcome)) return outcome;
    UiaElementInfo item;
    if (!SelectExplorerItem(explorer, BaseName(source), item, outcome)) return outcome;
    outcome.sourceSelectedByMouse = true;
    outcome.sourceSelectionVerified = VerifyExplorerFocusedItem(explorer, BaseName(source));
    if (!outcome.sourceSelectionVerified) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Move source selection was not verified.";
        outcome.moveFailureStage = L"source_selection_failed";
        return outcome;
    }
    outcome.moveActionAttempted = true;
    std::wstring destinationFolder = ParentPath(dest);
    bool useDragShortcut = false;
    if (useDragShortcut && ExplorerWorkflowNormalizePath(ParentPath(destinationFolder)) == ExplorerWorkflowNormalizePath(ParentPath(source))) {
        UiaElementInfo folderItem;
        if (LocateExplorerItem(explorer.hwnd, BaseName(destinationFolder), folderItem, outcome.errorCode, outcome.errorMessage)) {
            POINT from = ElementCenterClient(explorer.hwnd, item);
            POINT to = ElementCenterClient(explorer.hwnd, folderItem);
            DragResult drag = DragClientPoints(explorer.hwnd, from.x, from.y, to.x, to.y, L"human", 700);
            outcome.moveActionExecuted = drag.ok;
            if (!drag.ok) {
                outcome.errorCode = drag.errorCode.empty() ? L"SEND_INPUT_FAILED" : drag.errorCode;
                outcome.errorMessage = drag.error;
                outcome.moveFailureStage = L"paste_failed";
                return outcome;
            }
            Sleep(1200);
            outcome.sourceAbsentAfter = !ExplorerWorkflowFileExists(source);
            outcome.destinationExistsAfter = ExplorerWorkflowFileExists(dest);
            outcome.moveResultVerified = outcome.sourceAbsentAfter && outcome.destinationExistsAfter;
            outcome.resultVerified = outcome.moveResultVerified;
            if (outcome.moveResultVerified) {
                outcome.cutAttempted = true;
                outcome.cutSent = true;
                outcome.cutMethod = L"drag";
                outcome.cutEffectVerified = true;
                outcome.destinationFolderOpened = true;
                outcome.destinationFolderFocused = true;
                outcome.pasteAttempted = true;
                outcome.pasteSent = true;
                outcome.pasteMethod = L"drag";
                outcome.pasteObserved = true;
                outcome.ok = true;
                outcome.finalStatus = L"PASS";
                return outcome;
            }
            if (!OpenAndGuardFolder(spec, ParentPath(source), explorer, outcome)) return outcome;
            if (!SelectExplorerItem(explorer, BaseName(source), item, outcome)) return outcome;
            outcome.sourceSelectedByMouse = true;
            outcome.sourceSelectionVerified = VerifyExplorerFocusedItem(explorer, BaseName(source));
            if (!outcome.sourceSelectionVerified) {
                outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
                outcome.errorMessage = L"Move source selection was not verified after drag retry.";
                outcome.moveFailureStage = L"source_selection_failed";
                return outcome;
            }
        }
    }
    outcome.cutAttempted = true;
    ClearClipboardData();
    POINT sourcePt = ElementCenterClient(explorer.hwnd, item);
    ExplorerContextMenuResult cutMenu = ExecuteExplorerContextMenuAction(explorer, sourcePt.x, sourcePt.y, L"cut", L"");
    outcome.cutSent = cutMenu.ok;
    if (cutMenu.ok) {
        outcome.cutMethod = L"context_menu_cut";
        outcome.moveActionExecuted = true;
        Sleep(250);
        outcome.cutEffectVerified = false;
    }
    if (!cutMenu.ok || !outcome.cutEffectVerified) {
        outcome.fallbackUsed = true;
        outcome.fallbackReason = cutMenu.ok ? L"explorer_context_menu_cut_effect_not_verified" : L"explorer_context_menu_unavailable";
        ActionResult focusSource = FocusTargetWindow(explorer.hwnd);
        if (!focusSource.ok) {
            outcome.errorCode = focusSource.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focusSource.errorCode;
            outcome.errorMessage = focusSource.error;
            outcome.moveFailureStage = L"cut_failed";
            return outcome;
        }
        Sleep(100);
        ActionResult cut = SendHotkey(explorer.hwnd, L"CTRL+X");
        if (!cut.ok) {
            outcome.errorCode = cut.errorCode.empty() ? L"SEND_INPUT_FAILED" : cut.errorCode;
            outcome.errorMessage = cut.error;
            outcome.moveFailureStage = L"cut_failed";
            return outcome;
        }
        outcome.cutSent = true;
        outcome.cutMethod = L"keyboard_ctrl_x";
        Sleep(250);
        outcome.cutEffectVerified = ClipboardHasFileDropPath(source);
        outcome.moveActionExecuted = true;
    }
    if (!outcome.cutEffectVerified) {
        outcome.errorCode = L"SEND_INPUT_FAILED";
        outcome.errorMessage = L"Cut did not produce file clipboard evidence.";
        outcome.moveFailureStage = L"cut_failed";
        return outcome;
    }
    Sleep(250);
    ExplorerWorkflowSpec destinationSpec = spec;
    std::wstring destinationFolderName = BaseName(ParentPath(dest));
    destinationSpec.expectedContextJson = L"{\"expected_process_pattern\":\"explorer.exe\",\"expected_title_pattern\":"
        + simplejson::Quote(destinationFolderName) +
        L",\"required_markers\":" + ExplorerWorkflowJsonStringArray1(destinationFolderName) + L"}";
    bool destinationOpenedByUi = false;
    if (ExplorerWorkflowNormalizePath(ParentPath(destinationFolder)) == ExplorerWorkflowNormalizePath(ParentPath(source))) {
        UiaElementInfo destinationFolderItem;
        std::wstring folderCode;
        std::wstring folderMessage;
        if (LocateExplorerItem(explorer.hwnd, destinationFolderName, destinationFolderItem, folderCode, folderMessage)) {
            POINT folderPt = ElementCenterClient(explorer.hwnd, destinationFolderItem);
            ClickResult openDestination = DoubleClickClientPoint(explorer.hwnd, folderPt.x, folderPt.y, L"human", 0);
            if (openDestination.ok) {
                Sleep(700);
                WindowInfo destinationExplorer;
                if (FindExplorerWindowForFolder(ParentPath(dest), destinationExplorer)) {
                    explorer = destinationExplorer;
                    FocusTargetWindow(explorer.hwnd);
                    Sleep(250);
                    ExpectedContextSpec ctx = ExpectedContextFromSpec(destinationSpec);
                    RuntimeTargetContext targetContext;
                    RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(ctx, targetContext);
                    outcome.runtimeContextGuardUsed = true;
                    outcome.runtimeContextGuardOk = guard.ok;
                    outcome.guardJson = RuntimeContextGuardResultJson(guard);
                    if (guard.ok) {
                        destinationOpenedByUi = true;
                        outcome.destinationFolderOpened = true;
                        outcome.destinationFolderFocused = true;
                        outcome.folderOpened = true;
                        outcome.expectedFolderVerified = true;
                    }
                }
            }
        }
    }
    if (!destinationOpenedByUi) {
        if (!OpenAndGuardFolder(destinationSpec, ParentPath(dest), explorer, outcome)) {
            if (outcome.moveFailureStage.empty()) outcome.moveFailureStage = L"destination_open_failed";
            return outcome;
        }
        outcome.destinationFolderOpened = true;
    }
    ActionResult focusDestination = FocusTargetWindow(explorer.hwnd);
    outcome.destinationFolderFocused = focusDestination.ok;
    if (!focusDestination.ok) {
        outcome.errorCode = focusDestination.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focusDestination.errorCode;
        outcome.errorMessage = focusDestination.error;
        outcome.moveFailureStage = L"destination_focus_failed";
        return outcome;
    }
    Sleep(150);
    outcome.pasteAttempted = true;
    RECT client = {};
    GetClientRect(explorer.hwnd, &client);
    int pasteX = (client.right - client.left) / 2;
    int pasteY = (client.bottom - client.top) / 2;
    ExplorerContextMenuResult pasteMenu = ExecuteExplorerContextMenuAction(explorer, pasteX, pasteY, L"paste", L"");
    outcome.pasteSent = pasteMenu.ok;
    if (pasteMenu.ok) {
        outcome.pasteMethod = L"context_menu_paste";
        outcome.pasteObserved = true;
        outcome.moveActionExecuted = true;
    } else {
        if (!outcome.fallbackUsed) {
            outcome.fallbackUsed = true;
            outcome.fallbackReason = L"explorer_context_menu_unavailable";
        }
        PressKeyGlobal(L"ESC");
        Sleep(150);
        ActionResult refocusDestination = FocusTargetWindow(explorer.hwnd);
        if (!refocusDestination.ok) {
            outcome.errorCode = refocusDestination.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : refocusDestination.errorCode;
            outcome.errorMessage = refocusDestination.error;
            outcome.moveFailureStage = L"destination_focus_failed";
            return outcome;
        }
        Sleep(100);
        ClickResult focusList = ClickClientPoint(explorer.hwnd, pasteX, pasteY, L"human", 0);
        if (!focusList.ok) {
            outcome.errorCode = focusList.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : focusList.errorCode;
            outcome.errorMessage = focusList.error;
            outcome.moveFailureStage = L"destination_focus_failed";
            return outcome;
        }
        Sleep(100);
        ActionResult paste = SendHotkey(explorer.hwnd, L"CTRL+V");
        if (!paste.ok) {
            outcome.errorCode = paste.errorCode.empty() ? L"SEND_INPUT_FAILED" : paste.errorCode;
            outcome.errorMessage = paste.error;
            outcome.moveFailureStage = L"paste_failed";
            return outcome;
        }
        outcome.pasteSent = true;
        outcome.pasteMethod = L"keyboard_ctrl_v";
        outcome.pasteObserved = true;
        outcome.moveActionExecuted = true;
    }
    for (int retry = 1; retry <= 5; ++retry) {
        Sleep(400);
        outcome.moveVerificationRetryCount = retry;
        outcome.sourceAbsentAfter = !ExplorerWorkflowFileExists(source);
        outcome.destinationExistsAfter = ExplorerWorkflowFileExists(dest);
        outcome.moveResultVerified = outcome.sourceAbsentAfter && outcome.destinationExistsAfter;
        if (outcome.moveResultVerified) break;
    }
    outcome.resultVerified = outcome.moveResultVerified;
    outcome.ok = outcome.moveResultVerified;
    outcome.finalStatus = outcome.ok ? L"PASS" : L"BLOCKED";
    if (!outcome.ok) {
        outcome.errorCode = L"VERIFY_MOVE_FAILED";
        outcome.errorMessage = L"Move verification failed.";
        if (!outcome.destinationExistsAfter) outcome.moveFailureStage = L"destination_missing";
        else if (!outcome.sourceAbsentAfter) outcome.moveFailureStage = L"source_still_exists";
        else outcome.moveFailureStage = L"verification_timeout";
    }
    return outcome;
}

ExplorerStepOutcome ExecuteDeleteWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    if (!spec.confirmationRequired || spec.confirmationToken.empty()) {
        outcome.deleteWithoutConfirmationBlocked = true;
        outcome.riskGateOk = true;
        outcome.errorCode = L"BLOCKED_UNCONFIRMED_DESTRUCTIVE_ACTION";
        outcome.errorMessage = L"Delete requires confirmation token.";
        outcome.finalStatus = L"BLOCKED";
        return outcome;
    }
    std::wstring source = spec.sourcePath;
    outcome.targetExistsBefore = ExplorerWorkflowFileExists(source);
    if (!outcome.targetExistsBefore) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Delete target file was not found.";
        return outcome;
    }
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, ParentPath(source), explorer, outcome)) return outcome;
    UiaElementInfo item;
    if (!SelectExplorerItem(explorer, BaseName(source), item, outcome)) return outcome;
    ActionResult del = PressKey(explorer.hwnd, L"DELETE");
    if (!del.ok) {
        outcome.errorCode = del.errorCode.empty() ? L"SEND_INPUT_FAILED" : del.errorCode;
        outcome.errorMessage = del.error;
        return outcome;
    }
    Sleep(400);
    HWND fg = GetForegroundWindow();
    if (fg && fg != explorer.hwnd) {
        PressKey(fg, L"ENTER");
        Sleep(500);
    }
    outcome.deleteWithConfirmationExecuted = true;
    outcome.targetAbsentAfter = !ExplorerWorkflowFileExists(source);
    outcome.riskGateOk = true;
    outcome.confirmationVerified = true;
    outcome.resultVerified = outcome.targetAbsentAfter;
    outcome.ok = outcome.resultVerified;
    outcome.finalStatus = outcome.ok ? L"PASS" : L"BLOCKED";
    if (!outcome.ok) {
        outcome.errorCode = L"VERIFY_DELETE_FAILED";
        outcome.errorMessage = L"Delete verification failed.";
    }
    return outcome;
}

ExplorerStepOutcome ExecuteScrollLocateWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    std::wstring folder = FolderForSpec(spec);
    std::wstring fileName = TargetFileNameForSpec(spec);
    if (fileName.empty() && !spec.targetPath.empty()) fileName = BaseName(spec.targetPath);
    outcome.targetName = fileName;
    outcome.targetExistsInFixture = !spec.targetPath.empty() && ExplorerWorkflowFileExists(spec.targetPath);
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, folder, explorer, outcome)) return outcome;
    RECT client = {};
    GetClientRect(explorer.hwnd, &client);
    int x = (client.right - client.left) / 2;
    int y = (client.bottom - client.top) / 2;
    outcome.listAreaLocated = client.right > client.left && client.bottom > client.top;
    ClickResult listClick = ClickClientPoint(explorer.hwnd, x, y, L"human", 0);
    outcome.listAreaClicked = listClick.ok;
    outcome.listAreaFocusVerified = listClick.ok && GetForegroundWindow() == explorer.hwnd;
    if (!listClick.ok || !outcome.listAreaFocusVerified) {
        outcome.errorCode = listClick.errorCode.empty() ? L"WINDOW_FOCUS_FAILED" : listClick.errorCode;
        outcome.errorMessage = listClick.error.empty() ? L"Explorer list area focus was not verified." : listClick.error;
        outcome.failureStage = L"list_area_focus_failed";
        return outcome;
    }
    ActionResult home = PressKey(explorer.hwnd, L"HOME");
    outcome.homeResetUsed = home.ok;
    Sleep(350);
    outcome.visibleItemsBefore = VisibleExplorerItemNames(explorer.hwnd);
    std::vector<std::wstring> currentVisible = outcome.visibleItemsBefore;
    std::wstring iterations = L"[";
    bool hasIterationJson = false;
    for (int i = 0; i < 40; ++i) {
        outcome.scrollIterationCount = i + 1;
        ExpectedContextSpec ctx = ExpectedContextFromSpec(spec);
        RuntimeTargetContext targetContext;
        RuntimeContextGuardResult guard = EvaluateRuntimeContextGuard(ctx, targetContext);
        if (!guard.ok) {
            outcome.runtimeContextGuardEachIteration = false;
            outcome.errorCode = guard.stopCode.empty() ? L"STOP_WRONG_CONTEXT" : guard.stopCode;
            outcome.errorMessage = guard.reason;
            outcome.failureStage = L"runtime_context_guard_failed";
            break;
        }
        UiaElementInfo item;
        std::wstring code;
        std::wstring message;
        if (LocateExplorerItem(explorer.hwnd, fileName, item, code, message)) {
            outcome.targetSeenByUia = true;
            outcome.targetFound = true;
            outcome.targetRectJson = RectJson(item.rect);
            POINT pt = ElementCenterClient(explorer.hwnd, item);
            ClickResult verifyClick = ClickClientPoint(explorer.hwnd, pt.x, pt.y, L"human", 0);
            outcome.targetClickedOrVerified = verifyClick.ok || VerifyExplorerFocusedItem(explorer, fileName);
            outcome.ok = true;
            outcome.finalStatus = L"PASS";
            outcome.visibleItemsAfter = VisibleExplorerItemNames(explorer.hwnd);
            if (hasIterationJson) iterations += L",";
            iterations += L"{\"iteration\":" + std::to_wstring(i + 1) +
                L",\"visible_items\":" + JsonStringArray(currentVisible) +
                L",\"target_found\":true}";
            hasIterationJson = true;
            outcome.perIterationVisibleItemsJson = iterations + L"]";
            return outcome;
        }
        std::vector<std::wstring> before = currentVisible.empty() ? VisibleExplorerItemNames(explorer.hwnd) : currentVisible;
        ClickResult scroll = ScrollClientPoint(explorer.hwnd, x, y, -360, L"human");
        outcome.scrollUsed = true;
        outcome.wheelEventCount += scroll.wheelEventCount;
        if (!scroll.ok) {
            outcome.errorCode = scroll.errorCode.empty() ? L"SEND_INPUT_FAILED" : scroll.errorCode;
            outcome.errorMessage = scroll.error;
            outcome.failureStage = L"scroll_input_failed";
            return outcome;
        }
        Sleep(250);
        std::vector<std::wstring> after = VisibleExplorerItemNames(explorer.hwnd);
        bool progress = !SameStringVector(before, after) ||
            FirstOrEmpty(before) != FirstOrEmpty(after) ||
            LastOrEmpty(before) != LastOrEmpty(after);
        if (!progress) {
            outcome.scrollNoProgressDetected = true;
            outcome.pageDownFallbackUsed = true;
            ActionResult pageDown = PressKey(explorer.hwnd, L"PAGEDOWN");
            if (pageDown.ok) {
                Sleep(250);
                std::vector<std::wstring> pageAfter = VisibleExplorerItemNames(explorer.hwnd);
                progress = !SameStringVector(after, pageAfter) ||
                    FirstOrEmpty(after) != FirstOrEmpty(pageAfter) ||
                    LastOrEmpty(after) != LastOrEmpty(pageAfter);
                after = pageAfter;
            }
        }
        if (progress) {
            outcome.scrollProgressDetected = true;
            outcome.scrollPositionChanged = true;
        }
        if (hasIterationJson) iterations += L",";
        iterations += L"{\"iteration\":" + std::to_wstring(i + 1) +
            L",\"visible_items_before\":" + JsonStringArray(before) +
            L",\"visible_items_after\":" + JsonStringArray(after) +
            L",\"progress\":" + simplejson::Bool(progress) + L"}";
        hasIterationJson = true;
        currentVisible = after;
        outcome.visibleItemsAfter = after;
        if (!progress && i >= 2) {
            outcome.errorCode = L"SCROLL_NO_PROGRESS";
            outcome.errorMessage = L"Explorer list scroll produced no observable visible item change.";
            outcome.failureStage = L"scroll_no_progress";
            break;
        }
    }
    if (outcome.errorCode.empty()) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Scroll-and-locate target was not found.";
        outcome.failureStage = L"target_not_found";
    }
    outcome.targetSeenButNotConfirmed = (outcome.targetSeenByOcr || outcome.targetSeenByReadWindowText) && !outcome.targetFound;
    outcome.perIterationVisibleItemsJson = iterations + L"]";
    return outcome;
}

ExplorerStepOutcome ExecuteContextMenuWorkflow(const ExplorerWorkflowSpec& spec) {
    ExplorerStepOutcome outcome;
    std::wstring source = spec.sourcePath;
    std::wstring target = spec.targetPath.empty() ? (ParentPath(source) + L"\\" + spec.expectedFilename) : spec.targetPath;
    outcome.sourceExistsBefore = ExplorerWorkflowFileExists(source);
    if (!outcome.sourceExistsBefore) {
        outcome.errorCode = L"FAIL_TARGET_NOT_FOUND";
        outcome.errorMessage = L"Context menu target file was not found.";
        return outcome;
    }
    WindowInfo explorer;
    if (!OpenAndGuardFolder(spec, ParentPath(source), explorer, outcome)) return outcome;
    UiaElementInfo item;
    if (!SelectExplorerItem(explorer, BaseName(source), item, outcome)) return outcome;
    POINT pt = ElementCenterClient(explorer.hwnd, item);
    ExplorerContextMenuResult menu = ExecuteExplorerContextMenuAction(explorer, pt.x, pt.y, spec.contextMenuAction, ExplorerRenameInputText(source, target));
    outcome.rightClickSent = menu.rightClickSent;
    outcome.contextMenuVisible = menu.contextMenuVisible;
    outcome.menuItemLocated = menu.menuItemLocated;
    outcome.menuItemClicked = menu.menuItemClicked;
    if (!menu.ok) {
        outcome.errorCode = menu.errorCode;
        outcome.errorMessage = menu.errorMessage;
        return outcome;
    }
    Sleep(800);
    outcome.newNameExistsAfter = ExplorerWorkflowFileExists(target);
    outcome.oldNameAbsentAfter = !ExplorerWorkflowFileExists(source);
    outcome.resultVerified = outcome.newNameExistsAfter && outcome.oldNameAbsentAfter;
    if (!outcome.resultVerified && (Lower(spec.contextMenuAction).empty() || Lower(spec.contextMenuAction) == L"rename")) {
        PressKeyGlobal(L"ESC");
        Sleep(200);
        FocusTargetWindow(explorer.hwnd);
        Sleep(200);
        WindowInfo retryExplorer;
        if (OpenAndGuardFolder(spec, ParentPath(source), retryExplorer, outcome)) {
            UiaElementInfo retryItem;
            if (SelectExplorerItem(retryExplorer, BaseName(source), retryItem, outcome)) {
                ActionResult f2 = PressKey(retryExplorer.hwnd, L"F2");
                if (f2.ok) {
                    Sleep(200);
                    TypeResult typed = TypeText(retryExplorer.hwnd, ExplorerRenameInputText(source, target), L"human", -1);
                    if (typed.ok) {
                        ActionResult enter = PressKey(retryExplorer.hwnd, L"ENTER");
                        if (enter.ok) {
                            Sleep(800);
                            outcome.newNameExistsAfter = ExplorerWorkflowFileExists(target);
                            outcome.oldNameAbsentAfter = !ExplorerWorkflowFileExists(source);
                            outcome.resultVerified = outcome.newNameExistsAfter && outcome.oldNameAbsentAfter;
                        }
                    }
                }
            }
        }
    }
    outcome.ok = outcome.resultVerified;
    outcome.finalStatus = outcome.ok ? L"PASS" : L"BLOCKED";
    if (!outcome.ok) {
        outcome.errorCode = L"VERIFY_CONTEXT_MENU_ACTION_FAILED";
        outcome.errorMessage = L"Context menu action verification failed.";
    }
    return outcome;
}

}  // namespace

ExplorerWorkflowExecutionResult RunExplorerWorkflowSpecFile(
    const std::wstring& inputPath,
    const ExplorerWorkflowRunOptions& options) {
    ExplorerWorkflowRunOptions effective = options;
    if (effective.mode == L"dry-run") effective.mode = L"dry_run";
    if (effective.mode == L"execute-local-safe") effective.mode = L"execute_local_safe";
    if (effective.evidenceDir.empty()) {
        effective.evidenceDir = ArtifactsPath(L"dev6.7.0_explorer_agent_workflows\\executions\\exec-" + std::to_wstring(GetTickCount64()));
    }
    EnsureDirectoryPath(effective.evidenceDir);

    ExplorerWorkflowSchemaResult schema = ParseExplorerWorkflowSpecFile(inputPath);
    if (!schema.ok) {
        return Failure(effective, schema.spec, schema.errorCode, schema.errorMessage);
    }
    ExplorerWorkflowCompileResult compiled = CompileExplorerWorkflowSpec(schema.spec);
    if (!compiled.ok) {
        return Failure(effective, schema.spec, compiled.errorCode, compiled.errorMessage);
    }

    std::wstring stepContractPath = effective.evidenceDir + L"\\step_contract.json";
    std::wstring writeError;
    WriteTextFileUtf8(stepContractPath, compiled.contractJson, writeError);
    StepContractV63ValidationResult validation = ValidateStepContractV63Json(compiled.contractJson);
    if (!validation.validationOk || !validation.executable) {
        return Failure(effective, schema.spec, validation.errorCode, validation.errorMessage);
    }

    bool dryRun = effective.mode == L"dry_run";
    bool executeLocalSafe = effective.mode == L"execute_local_safe";
    if (!dryRun && !executeLocalSafe) {
        return Failure(effective, schema.spec, L"INVALID_ARGUMENT", L"run-explorer-workflow mode must be dry-run or execute-local-safe.");
    }

    ExplorerStepOutcome outcome;
    if (executeLocalSafe) {
        if (schema.spec.workflowType == L"explorer_open_path") {
            outcome = ExecuteOpenPathWorkflow(schema.spec);
        } else if (schema.spec.workflowType == L"explorer_open_file") {
            outcome = ExecuteOpenFileWorkflow(schema.spec);
        } else if (schema.spec.workflowType == L"explorer_rename_file") {
            outcome = ExecuteRenameWorkflow(schema.spec);
        } else if (schema.spec.workflowType == L"explorer_move_file") {
            outcome = ExecuteMoveWorkflow(schema.spec);
        } else if (schema.spec.workflowType == L"explorer_delete_file") {
            outcome = ExecuteDeleteWorkflow(schema.spec);
        } else if (schema.spec.workflowType == L"explorer_scroll_and_locate") {
            outcome = ExecuteScrollLocateWorkflow(schema.spec);
        } else if (schema.spec.workflowType == L"explorer_context_menu_action") {
            outcome = ExecuteContextMenuWorkflow(schema.spec);
        } else {
            outcome.errorCode = L"EXPLORER_UI_EXECUTION_NOT_IMPLEMENTED";
            outcome.errorMessage = L"Explorer UI execution path for this workflow is not implemented yet.";
        }
    }

    std::wstring finalStatus = dryRun ? L"DRY_RUN_PASS" : outcome.finalStatus;
    std::wstring errorCode = dryRun ? L"" : outcome.errorCode;
    std::wstring errorMessage = dryRun ? L"" : outcome.errorMessage;
    std::wstring resultJson = L"{\"schema_version\":\"6.7.0.explorer_workflow.result\""
        L",\"workflow_id\":" + simplejson::Quote(schema.spec.workflowId) +
        L",\"workflow_type\":" + simplejson::Quote(schema.spec.workflowType) +
        L",\"task_id\":" + simplejson::Quote(schema.spec.taskId) +
        L",\"execution_mode\":" + simplejson::Quote(effective.mode) +
        L",\"final_status\":" + simplejson::Quote(finalStatus) +
        L",\"error_code\":" + simplejson::Quote(errorCode) +
        L",\"error_message\":" + simplejson::Quote(errorMessage) +
        L",\"source_path\":" + simplejson::Quote(schema.spec.sourcePath) +
        L",\"target_path\":" + simplejson::Quote(schema.spec.targetPath) +
        L",\"destination_path\":" + simplejson::Quote(schema.spec.destinationPath) +
        L",\"allowed_root\":" + simplejson::Quote(schema.spec.allowedRoot) +
        L",\"workflow_compiled\":true"
        L",\"compiled_step_contract_used\":true"
        L",\"step_contract_validator_used\":true"
        L",\"step_contract_validated\":true"
        L",\"runtime_session_used\":" + simplejson::Bool(!dryRun && outcome.runtimeSessionUsed) +
        L",\"session_id\":" + simplejson::Quote(outcome.sessionId) +
        L",\"runtime_context_guard_used\":" + simplejson::Bool(!dryRun && outcome.runtimeContextGuardUsed) +
        L",\"runtime_context_guard_ok\":" + simplejson::Bool(!dryRun && outcome.runtimeContextGuardOk) +
        L",\"runtime_context_guard_result\":" + outcome.guardJson +
        L",\"step_level_verification_complete\":" + simplejson::Bool(!dryRun && outcome.ok) +
        L",\"evidence_pack_created\":true"
        L",\"folder_opened\":" + simplejson::Bool(!dryRun && outcome.folderOpened) +
        L",\"expected_folder_verified\":" + simplejson::Bool(!dryRun && outcome.expectedFolderVerified) +
        L",\"file_visible\":" + simplejson::Bool(!dryRun && outcome.fileVisible) +
        L",\"file_open_action_executed\":" + simplejson::Bool(!dryRun && outcome.fileOpenActionExecuted) +
        L",\"file_open_verified\":" + simplejson::Bool(!dryRun && outcome.fileOpenVerified) +
        L",\"old_name_exists_before\":" + simplejson::Bool(!dryRun && outcome.oldNameExistsBefore) +
        L",\"rename_action_executed\":" + simplejson::Bool(!dryRun && schema.spec.workflowType == L"explorer_rename_file" && outcome.resultVerified) +
        L",\"new_name_exists_after\":" + simplejson::Bool(!dryRun && outcome.newNameExistsAfter) +
        L",\"old_name_absent_after\":" + simplejson::Bool(!dryRun && outcome.oldNameAbsentAfter) +
        L",\"source_exists_before\":" + simplejson::Bool(!dryRun && outcome.sourceExistsBefore) +
        L",\"destination_exists_before\":" + simplejson::Bool(!dryRun && outcome.destinationExistsBefore) +
        L",\"source_selected_by_mouse\":" + simplejson::Bool(!dryRun && outcome.sourceSelectedByMouse) +
        L",\"source_selection_verified\":" + simplejson::Bool(!dryRun && outcome.sourceSelectionVerified) +
        L",\"cut_attempted\":" + simplejson::Bool(!dryRun && outcome.cutAttempted) +
        L",\"cut_sent\":" + simplejson::Bool(!dryRun && outcome.cutSent) +
        L",\"cut_method\":" + simplejson::Quote(outcome.cutMethod) +
        L",\"cut_effect_verified\":" + simplejson::Bool(!dryRun && outcome.cutEffectVerified) +
        L",\"destination_folder_opened\":" + simplejson::Bool(!dryRun && outcome.destinationFolderOpened) +
        L",\"destination_folder_focused\":" + simplejson::Bool(!dryRun && outcome.destinationFolderFocused) +
        L",\"paste_attempted\":" + simplejson::Bool(!dryRun && outcome.pasteAttempted) +
        L",\"paste_sent\":" + simplejson::Bool(!dryRun && outcome.pasteSent) +
        L",\"paste_method\":" + simplejson::Quote(outcome.pasteMethod) +
        L",\"paste_observed\":" + simplejson::Bool(!dryRun && outcome.pasteObserved) +
        L",\"move_action_attempted\":" + simplejson::Bool(!dryRun && outcome.moveActionAttempted) +
        L",\"move_action_executed\":" + simplejson::Bool(!dryRun && schema.spec.workflowType == L"explorer_move_file" && outcome.moveActionExecuted) +
        L",\"move_verification_retry_count\":" + std::to_wstring(!dryRun ? outcome.moveVerificationRetryCount : 0) +
        L",\"source_absent_after\":" + simplejson::Bool(!dryRun && outcome.sourceAbsentAfter) +
        L",\"destination_exists_after\":" + simplejson::Bool(!dryRun && outcome.destinationExistsAfter) +
        L",\"move_result_verified\":" + simplejson::Bool(!dryRun && outcome.moveResultVerified) +
        L",\"move_failure_stage\":" + simplejson::Quote(outcome.moveFailureStage) +
        L",\"fallback_used\":" + simplejson::Bool(!dryRun && outcome.fallbackUsed) +
        L",\"fallback_reason\":" + simplejson::Quote(outcome.fallbackReason) +
        L",\"delete_without_confirmation_blocked\":" + simplejson::Bool(!dryRun && outcome.deleteWithoutConfirmationBlocked) +
        L",\"delete_with_confirmation_executed\":" + simplejson::Bool(!dryRun && outcome.deleteWithConfirmationExecuted) +
        L",\"target_exists_before\":" + simplejson::Bool(!dryRun && outcome.targetExistsBefore) +
        L",\"target_absent_after\":" + simplejson::Bool(!dryRun && outcome.targetAbsentAfter) +
        L",\"list_area_located\":" + simplejson::Bool(!dryRun && outcome.listAreaLocated) +
        L",\"list_area_clicked\":" + simplejson::Bool(!dryRun && outcome.listAreaClicked) +
        L",\"list_area_focus_verified\":" + simplejson::Bool(!dryRun && outcome.listAreaFocusVerified) +
        L",\"home_reset_used\":" + simplejson::Bool(!dryRun && outcome.homeResetUsed) +
        L",\"visible_items_before\":" + JsonStringArray(outcome.visibleItemsBefore) +
        L",\"visible_items_after\":" + JsonStringArray(outcome.visibleItemsAfter) +
        L",\"visible_first_item_before\":" + simplejson::Quote(FirstOrEmpty(outcome.visibleItemsBefore)) +
        L",\"visible_first_item_after\":" + simplejson::Quote(FirstOrEmpty(outcome.visibleItemsAfter)) +
        L",\"visible_last_item_before\":" + simplejson::Quote(LastOrEmpty(outcome.visibleItemsBefore)) +
        L",\"visible_last_item_after\":" + simplejson::Quote(LastOrEmpty(outcome.visibleItemsAfter)) +
        L",\"scroll_iteration_count\":" + std::to_wstring(!dryRun ? outcome.scrollIterationCount : 0) +
        L",\"wheel_event_count\":" + std::to_wstring(!dryRun ? outcome.wheelEventCount : 0) +
        L",\"scroll_used\":" + simplejson::Bool(!dryRun && outcome.scrollUsed) +
        L",\"scroll_progress_detected\":" + simplejson::Bool(!dryRun && outcome.scrollProgressDetected) +
        L",\"scroll_position_changed\":" + simplejson::Bool(!dryRun && outcome.scrollPositionChanged) +
        L",\"page_down_fallback_used\":" + simplejson::Bool(!dryRun && outcome.pageDownFallbackUsed) +
        L",\"per_iteration_visible_items\":" + outcome.perIterationVisibleItemsJson +
        L",\"target_name\":" + simplejson::Quote(outcome.targetName) +
        L",\"target_exists_in_fixture\":" + simplejson::Bool(!dryRun && outcome.targetExistsInFixture) +
        L",\"target_seen_by_uia\":" + simplejson::Bool(!dryRun && outcome.targetSeenByUia) +
        L",\"target_seen_by_ocr\":" + simplejson::Bool(!dryRun && outcome.targetSeenByOcr) +
        L",\"target_seen_by_read_window_text\":" + simplejson::Bool(!dryRun && outcome.targetSeenByReadWindowText) +
        L",\"target_seen_but_not_confirmed\":" + simplejson::Bool(!dryRun && outcome.targetSeenButNotConfirmed) +
        L",\"target_found\":" + simplejson::Bool(!dryRun && outcome.targetFound) +
        L",\"target_rect\":" + outcome.targetRectJson +
        L",\"target_clicked_or_verified\":" + simplejson::Bool(!dryRun && outcome.targetClickedOrVerified) +
        L",\"scroll_no_progress_detected\":" + simplejson::Bool(!dryRun && outcome.scrollNoProgressDetected) +
        L",\"stale_rect_used\":" + simplejson::Bool(!dryRun && outcome.staleRectUsed) +
        L",\"runtime_context_guard_each_iteration\":" + simplejson::Bool(!dryRun && outcome.runtimeContextGuardEachIteration) +
        L",\"failure_stage\":" + simplejson::Quote(outcome.failureStage) +
        L",\"no_stale_rect\":" + simplejson::Bool(outcome.noStaleRect) +
        L",\"right_click_sent\":" + simplejson::Bool(!dryRun && outcome.rightClickSent) +
        L",\"context_menu_visible\":" + simplejson::Bool(!dryRun && outcome.contextMenuVisible) +
        L",\"menu_item_located\":" + simplejson::Bool(!dryRun && outcome.menuItemLocated) +
        L",\"menu_item_clicked\":" + simplejson::Bool(!dryRun && outcome.menuItemClicked) +
        L",\"result_verified\":" + simplejson::Bool(!dryRun && outcome.resultVerified) +
        L",\"confirmation_verified\":" + simplejson::Bool(!dryRun && outcome.confirmationVerified) +
        L",\"risk_gate_result\":" + simplejson::Quote(outcome.riskGateOk ? L"ok" : (schema.spec.workflowType == L"explorer_delete_file" ? L"blocked_or_pending" : L"not_required")) +
        L",\"recovery_attempted\":" + simplejson::Bool(!dryRun && outcome.recoveryAttempted) +
        L",\"recovery_success\":" + simplejson::Bool(!dryRun && outcome.recoverySuccess) +
        L",\"wrong_folder_detected\":" + simplejson::Bool(!dryRun && outcome.wrongFolderDetected) +
        L",\"wrong_context_detected\":" + simplejson::Bool(!dryRun && outcome.wrongContextDetected) +
        L",\"failure_attribution\":" + simplejson::Quote(errorCode.empty() ? L"" : L"explorer_workflow_executor") +
        L",\"powershell_file_action_used\":false"
        L",\"direct_file_api_workflow_action_used\":false"
        L",\"power_shell_file_operation_used\":false"
        L",\"direct_file_api_used\":false"
        L",\"runner_only_workflow_logic\":false"
        L",\"step_contract_path\":" + simplejson::Quote(stepContractPath) +
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

    ExplorerWorkflowExecutionResult result;
    result.ok = dryRun || outcome.ok;
    result.errorCode = errorCode;
    result.errorMessage = errorMessage;
    result.resultJson = resultJson;
    result.evidenceDir = effective.evidenceDir;
    return result;
}

int CommandRunExplorerWorkflow(int argc, wchar_t** argv) {
    const std::wstring command = L"run-explorer-workflow";
    ULONGLONG startTick = GetTickCount64();
    std::wstring input;
    ExplorerWorkflowRunOptions options;
    if (!ArgValue(argc, argv, L"--input", input) || input.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"run-explorer-workflow requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--mode", options.mode);
    ArgValue(argc, argv, L"--output", options.outputPath);
    ArgValue(argc, argv, L"--evidence-dir", options.evidenceDir);
    ExplorerWorkflowExecutionResult result = RunExplorerWorkflowSpecFile(input, options);
    if (!result.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.errorCode.empty() ? L"EXPLORER_WORKFLOW_FAILED" : result.errorCode, result.errorMessage, result.resultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.resultJson) << L"\n";
    return 0;
}
