param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:Failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message"
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Read-Text {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath (Join-Path $Root $Path)
}

function Assert-Exists {
    param([string]$Path)
    if (Test-Path -LiteralPath (Join-Path $Root $Path)) {
        Add-Pass "$Path exists"
    } else {
        Add-Failure "$Path is missing"
    }
}

function Assert-Contains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$PassMessage,
        [string]$FailMessage
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Path))) {
        Add-Failure $FailMessage
        return
    }
    $text = Read-Text $Path
    if ($text -match $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
    }
}

function Assert-NotContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$PassMessage,
        [string]$FailMessage
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Path))) {
        Add-Failure $FailMessage
        return
    }
    $text = Read-Text $Path
    if ($text -notmatch $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
    }
}

function Test-GitCleanForPaths {
    param(
        [string[]]$Paths,
        [string]$PassMessage,
        [string]$FailPrefix
    )
    $gitAvailable = $false
    try {
        & git rev-parse --is-inside-work-tree *> $null
        $gitAvailable = ($LASTEXITCODE -eq 0)
    } catch {
        $gitAvailable = $false
    }
    if (-not $gitAvailable) {
        Add-Failure "git is unavailable; cannot verify $FailPrefix"
        return
    }
    $changed = @(& git diff --name-only -- $Paths)
    $staged = @(& git diff --cached --name-only -- $Paths)
    $untracked = @(& git ls-files --others --exclude-standard -- $Paths)
    $all = @($changed + $staged + $untracked) | Where-Object { $_ }
    if ($all.Count -eq 0) {
        Add-Pass $PassMessage
    } else {
        foreach ($path in $all) {
            Add-Failure "${FailPrefix}: $path"
        }
    }
}

function Test-ApprovedDesktopReleaseSync {
    param(
        [string]$ReleaseRoot,
        [string]$ExpectedVersion
    )
    $evidenceRoot = Join-Path $ReleaseRoot "artifacts\release_sync_v$($ExpectedVersion)_local_use_demo"
    $requiredEvidence = @(
        "sync_summary.md",
        "source_version_before_sync.txt",
        "target_version_before_sync.txt",
        "robocopy_actual_sync.log",
        "target_version_after_sync.txt"
    )
    foreach ($name in $requiredEvidence) {
        if (-not (Test-Path -LiteralPath (Join-Path $evidenceRoot $name))) {
            return $false
        }
    }
    return $true
}

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.1.12") {
    Add-Pass "VERSION is 1.1.12"
} else {
    Add-Failure "VERSION is '$version', expected 1.1.12"
}

Assert-Exists "docs\CORE_WAIT_STATE_HARDENING.md"
Assert-Exists "src\winagent\CoreWaitState.h"
Assert-Exists "src\winagent\CoreWaitState.cpp"

if (Test-Path -LiteralPath (Join-Path $Root "src\winagent\CoreWaitState.h")) {
    Assert-Contains "src\winagent\CoreWaitState.h" "CoreWaitStateResult" "CoreWaitStateResult is declared" "CoreWaitStateResult is missing"
    Assert-Contains "src\winagent\CoreWaitState.h" "WaitForCoreState" "WaitForCoreState is declared" "WaitForCoreState is missing"
    Assert-Contains "src\winagent\CoreWaitState.h" "RecordCoreWaitNotReplaced" "not_replaced wait recorder is declared" "not_replaced wait recorder is missing"
}

if (Test-Path -LiteralPath (Join-Path $Root "src\winagent\CoreWaitState.cpp")) {
    Assert-Contains "src\winagent\CoreWaitState.cpp" "wait_exit_reason" "Core wait JSON outputs wait_exit_reason" "Core wait JSON does not output wait_exit_reason"
    Assert-Contains "src\winagent\CoreWaitState.cpp" "state_ready" "Core wait JSON outputs state_ready" "Core wait JSON does not output state_ready"
    Assert-Contains "src\winagent\CoreWaitState.cpp" "timeout" "Core wait JSON outputs timeout" "Core wait JSON does not output timeout"
    Assert-Contains "src\winagent\CoreWaitState.cpp" "wait_replaced_from_sleep_ms" "Core wait JSON outputs wait_replaced_from_sleep_ms" "Core wait JSON does not output wait_replaced_from_sleep_ms"
}

Assert-Contains "build.ps1" "CoreWaitState\.cpp" "build.ps1 compiles CoreWaitState.cpp" "build.ps1 does not compile CoreWaitState.cpp"

Assert-Contains "src\winagent\TaskRunner.cpp" "CoreWaitState" "TaskRunner uses CoreWaitState" "TaskRunner does not use CoreWaitState"
Assert-NotContains "src\winagent\TaskRunner.cpp" "locator_not_found_reobserve_ocr_stop[\s\S]{0,80}Sleep\(500\)" "TaskRunner locator_not_found recovery fixed Sleep is replaced" "TaskRunner locator_not_found recovery still has Sleep(500)"
Assert-NotContains "src\winagent\TaskRunner.cpp" "text_not_found_wait_reobserve_stop[\s\S]{0,80}Sleep\(500\)" "TaskRunner text_not_found recovery fixed Sleep is replaced" "TaskRunner text_not_found recovery still has Sleep(500)"
Assert-NotContains "src\winagent\TaskRunner.cpp" "retry_focus_once[\s\S]{0,120}Sleep\(500\)" "TaskRunner retry_focus_once fixed Sleep is replaced" "TaskRunner retry_focus_once still has Sleep(500)"
Assert-NotContains "src\winagent\TaskRunner.cpp" "initial_window_session[\s\S]{0,240}Sleep\(500\)" "TaskRunner initial recovery fixed Sleep is replaced" "TaskRunner initial recovery still has Sleep(500)"
Assert-Contains "src\winagent\TaskRunner.cpp" "core_wait" "TaskRunner records core wait evidence" "TaskRunner does not record core wait evidence"

Assert-Contains "src\winagent\ForegroundPreparation.cpp" "WaitUntilTargetWindowForeground|WaitUntilFocusStable|WaitUntilWindowResponsive|WaitUntilForegroundSettled" "ForegroundPreparation uses foreground state wait helpers" "ForegroundPreparation does not use foreground state wait helpers"
Assert-NotContains "src\winagent\ForegroundPreparation.cpp" "\bSleep\s*\(" "ForegroundPreparation fixed Sleep calls are replaced" "ForegroundPreparation still contains fixed Sleep calls"

Assert-Contains "src\winagent\SafeContextRecovery.cpp" "WaitUntilContextStable|WaitUntilWindowStillValid|WaitUntilNoModalTransition|WaitUntilFrameOrFocusStable" "SafeContextRecovery uses safe recovery state wait helpers" "SafeContextRecovery does not use safe recovery state wait helpers"
Assert-NotContains "src\winagent\SafeContextRecovery.cpp" "Sleep\(result\.recoveryAttempted" "SafeContextRecovery 1200ms recovery Sleep is replaced" "SafeContextRecovery still has the 1200ms recovery Sleep"
Assert-Contains "src\winagent\SafeContextRecovery.cpp" "CORE_WAIT_NOT_REPLACED|RecordCoreWaitNotReplaced|not_state_replaced" "SafeContextRecovery retained waits are explicitly marked" "SafeContextRecovery retained waits are not marked"

Assert-Contains "src\winagent\CursorAndBufferStateGuard.cpp" "WaitUntilCaretOrBufferStable|CoreWaitState|WaitForCoreState" "Cursor/buffer guard uses state wait" "Cursor/buffer guard does not use state wait"
Assert-NotContains "src\winagent\CursorAndBufferStateGuard.cpp" "Sleep\(250\)" "Cursor/buffer fixed Sleep(250) is replaced" "Cursor/buffer fixed Sleep(250) remains"

Assert-Contains "src\winagent\CodeEditorTypingPolicy.cpp" "CORE_WAIT_NOT_REPLACED|RecordCoreWaitNotReplaced|not_state_replaced|WaitForCoreState" "Code editor typing waits are stateized or marked" "Code editor typing waits are neither stateized nor marked"
Assert-Contains "src\winagent\CodeEditorTypingPolicy.cpp" "line_delay_input_pacing_not_core_wait" "Code editor line delay is explicitly retained as input pacing" "Code editor line delay retention reason is missing"

$latencyFields = @(
    "fixed_sleep_wait_ms",
    "state_wait_total_ms",
    "state_wait_saved_ms",
    "wait_site",
    "wait_reason",
    "wait_budget_ms",
    "wait_actual_ms",
    "wait_exit_reason",
    "wait_replaced_from_sleep_ms",
    "wait_state_ready",
    "wait_timeout_count",
    "wait_not_replaced_count",
    "wait_not_replaced_reasons"
)
foreach ($field in $latencyFields) {
    Assert-Contains "src\winagent\OperationTimelineProfiler.cpp" $field "Latency profiler exposes $field" "Latency profiler missing $field"
}

Assert-Contains "docs\LATENCY_OBSERVABILITY.md" "state_wait_total_ms" "Latency doc describes state_wait_total_ms" "Latency doc missing state_wait_total_ms"
Assert-Contains "docs\CORE_WAIT_STATE_HARDENING.md" "TaskRunner" "Core wait-state doc includes TaskRunner scope" "Core wait-state doc missing TaskRunner scope"
Assert-Contains "docs\CORE_WAIT_STATE_HARDENING.md" "Explorer" "Core wait-state doc states Explorer non-goal" "Core wait-state doc missing Explorer non-goal"
Assert-Contains "docs\CORE_WAIT_STATE_HARDENING.md" "not_replaced" "Core wait-state doc describes not_replaced waits" "Core wait-state doc missing not_replaced semantics"

Assert-Contains "docs\WORKFLOW_WAIT_STATE_HARDENING.md" "v1\.1\.7" "Workflow wait-state doc exists for v1.1.7 scope" "Workflow wait-state doc missing for v1.1.7"

Assert-Contains "docs\VLM_LAZY_LOADING.md" "Default capability probe timeout:\s*12000 ms" "VLM capability probe timeout remains documented as 12000ms" "VLM capability probe timeout documentation changed"
Assert-Contains "docs\VLM_LAZY_LOADING.md" "Default actual VLM locate/inference timeout:\s*60000 ms" "VLM inference timeout remains documented as 60000ms" "VLM inference timeout documentation changed"
Assert-Contains "src\winagent\RealVlmRuntimeBridge.cpp" "vlm_cache_state" "VLM lazy/cache report fields remain present" "VLM lazy/cache report fields missing"
Assert-Contains "tools\codex_vlm_provider.ps1" "60000" "VLM provider wrapper still contains inference timeout budget" "VLM provider wrapper timeout budget missing"

Test-GitCleanForPaths -Paths @("src/winagent/PermissionManager.cpp", "config/safety_manifest.json", "config/safety.conf") -PassMessage "PermissionManager and protected safety config are unmodified" -FailPrefix "Protected boundary modified"

$developerReleasePaths = @(& git status --short -- "desktop_release" "desktopvisual-public-dist" "public-dist" "public_dist" 2>$null)
if ($developerReleasePaths.Count -eq 0) {
    Add-Pass "No release/public-dist paths changed inside developer tree"
} else {
    foreach ($path in $developerReleasePaths) {
        Add-Failure "Unexpected release/public-dist path changed inside developer tree: $path"
    }
}

$rootName = Split-Path -Leaf $Root
$siblingReleaseRoot = Join-Path (Split-Path -Parent $Root) "desktop_release"
if ($rootName -ieq "desktop_release") {
    if (Test-ApprovedDesktopReleaseSync -ReleaseRoot $Root -ExpectedVersion $version) {
        Add-Pass "Current desktop_release is v$version with approved local-use/demo/testing sync evidence"
    } else {
        Add-Failure "Current desktop_release is v$version but approved sync evidence is incomplete"
    }
} elseif (Test-Path -LiteralPath $siblingReleaseRoot) {
    $siblingVersionPath = Join-Path $siblingReleaseRoot "VERSION"
    if (Test-Path -LiteralPath $siblingVersionPath) {
        $siblingVersion = (Get-Content -Raw -LiteralPath $siblingVersionPath).Trim()
        if ($siblingVersion -eq $version) {
            if (Test-ApprovedDesktopReleaseSync -ReleaseRoot $siblingReleaseRoot -ExpectedVersion $version) {
                Add-Pass "Sibling desktop_release VERSION is $version with approved local-use/demo/testing sync evidence"
            } else {
                Add-Failure "Sibling desktop_release VERSION is $version without approved sync evidence"
            }
        } else {
            Add-Pass "Sibling desktop_release VERSION is not $version"
        }
    } else {
        Add-Pass "Sibling desktop_release has no VERSION file to indicate v$version sync"
    }
} else {
    Add-Pass "Sibling desktop_release path is absent; no v$version sync detected"
}

if ($Failures.Count -eq 0) {
    Write-Host "Core wait-state selftest PASS"
    exit 0
}

Write-Host "Core wait-state selftest FAIL: $($Failures.Count) failure(s)"
exit 1



