param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.1.12_launch_contract_vs_startup_convergence"
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

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
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure $FailMessage
        return
    }
    $text = Get-Content -Raw -LiteralPath $full
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
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure $FailMessage
        return
    }
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -notmatch $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
    }
}

function Assert-Property {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )
    if ($null -ne $Object.PSObject.Properties[$Name]) {
        Add-Pass "$Context has $Name"
    } else {
        Add-Failure "$Context is missing $Name"
    }
}

function Assert-GitCleanForPaths {
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

Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\preflight_git_status.txt"
Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md" "Expected source changes" "v1.1.8 classification records expected baseline dirty state" "v1.1.8 classification missing expected baseline dirty state"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md" "RealVlmRuntimeBridge\.cpp" "v1.1.8 classification records pre-existing VLM bridge dirty state" "v1.1.8 classification does not record pre-existing VLM bridge dirty state"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md" "codex_vlm_provider\.ps1" "v1.1.8 classification records pre-existing VLM provider dirty state" "v1.1.8 classification does not record pre-existing VLM provider dirty state"

Assert-Exists "docs\WORKFLOW_WAIT_STATE_HARDENING.md"
Assert-Contains "docs\WORKFLOW_WAIT_STATE_HARDENING.md" "Explorer workflow waits" "Workflow wait doc covers Explorer waits" "Workflow wait doc missing Explorer waits"
Assert-Contains "docs\WORKFLOW_WAIT_STATE_HARDENING.md" "Browser workflow waits" "Workflow wait doc covers Browser waits" "Workflow wait doc missing Browser waits"
Assert-Contains "docs\WORKFLOW_WAIT_STATE_HARDENING.md" "Code/IDE workflow waits" "Workflow wait doc covers Code/IDE waits" "Workflow wait doc missing Code/IDE waits"
Assert-Contains "docs\WORKFLOW_WAIT_STATE_HARDENING.md" "not_state_replaced|not_replaced" "Workflow wait doc defines not_state_replaced" "Workflow wait doc missing not_state_replaced rule"
Assert-Contains "docs\WORKFLOW_WAIT_STATE_HARDENING.md" "v1\.2\.0" "Workflow wait doc states v1.2.0 benchmark handoff" "Workflow wait doc missing v1.2.0 handoff"

Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "current version:\s*1\.1\.12|Current version:\s*1\.1\.12" "Current contract states v1.1.12" "Current contract missing v1.1.12"
Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "Launch Contract Unification|VS Startup Convergence" "Current contract states v1.1.12 launch stage" "Current contract missing v1.1.12 launch stage"
Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "do not enter v1\.2\.0|not entered by v1\.1\.12" "Current contract states no v1.2.0 entry" "Current contract missing no v1.2.0 entry"

Assert-Contains "src\winagent\CoreWaitState.h" "WorkflowWaitStateSummary" "Workflow wait summary is declared" "Workflow wait summary declaration is missing"
Assert-Contains "src\winagent\CoreWaitState.h" "WaitForWorkflowState" "WaitForWorkflowState is declared" "WaitForWorkflowState declaration is missing"
Assert-Contains "src\winagent\CoreWaitState.h" "RecordWorkflowWaitNotReplaced" "Workflow not_replaced recorder is declared" "Workflow not_replaced recorder is missing"
Assert-Contains "src\winagent\CoreWaitState.h" "workflowName|workflow_name" "Workflow name is part of wait state model" "Workflow name is missing from wait state model"
Assert-Contains "src\winagent\CoreWaitState.h" "waitStatePredicate|wait_state_predicate" "Wait state predicate is part of wait state model" "Wait state predicate is missing from wait state model"

Assert-Contains "src\winagent\CoreWaitState.cpp" "workflow_wait_total_ms" "Workflow wait JSON outputs workflow_wait_total_ms" "Workflow wait JSON missing workflow_wait_total_ms"
Assert-Contains "src\winagent\CoreWaitState.cpp" "workflow_wait_saved_ms" "Workflow wait JSON outputs workflow_wait_saved_ms" "Workflow wait JSON missing workflow_wait_saved_ms"
Assert-Contains "src\winagent\CoreWaitState.cpp" "workflow_wait_timeout_count" "Workflow wait JSON outputs workflow_wait_timeout_count" "Workflow wait JSON missing workflow_wait_timeout_count"
Assert-Contains "src\winagent\CoreWaitState.cpp" "workflow_wait_not_replaced_count" "Workflow wait JSON outputs workflow_wait_not_replaced_count" "Workflow wait JSON missing workflow_wait_not_replaced_count"
Assert-Contains "src\winagent\CoreWaitState.cpp" "explorer_wait_total_ms" "Workflow wait JSON outputs explorer_wait_total_ms" "Workflow wait JSON missing explorer_wait_total_ms"
Assert-Contains "src\winagent\CoreWaitState.cpp" "browser_wait_total_ms" "Workflow wait JSON outputs browser_wait_total_ms" "Workflow wait JSON missing browser_wait_total_ms"
Assert-Contains "src\winagent\CoreWaitState.cpp" "code_workflow_wait_total_ms" "Workflow wait JSON outputs code_workflow_wait_total_ms" "Workflow wait JSON missing code_workflow_wait_total_ms"

Assert-Contains "src\winagent\ExplorerWorkflowExecutor.cpp" "workflowWaits|WorkflowWaitStateSummary" "Explorer outcome carries workflow wait evidence" "Explorer outcome missing workflow wait evidence"
Assert-Contains "src\winagent\ExplorerWorkflowExecutor.cpp" "WaitForWorkflowState" "Explorer workflow uses state waits" "Explorer workflow does not use state waits"
Assert-Contains "src\winagent\ExplorerWorkflowExecutor.cpp" "RecordWorkflowWaitNotReplaced|not_state_replaced" "Explorer workflow records not_replaced waits" "Explorer workflow does not record not_replaced waits"
Assert-Contains "src\winagent\ExplorerWorkflowExecutor.cpp" "workflow_wait_summary" "Explorer JSON emits workflow wait summary" "Explorer JSON missing workflow wait summary"
Assert-NotContains "src\winagent\ExplorerWorkflowExecutor.cpp" "Sleep\(800\)(?![\s\S]{0,200}not_state_replaced)" "Explorer 800ms sleeps are replaced or marked" "Explorer contains unmarked Sleep(800)"
Assert-NotContains "src\winagent\ExplorerWorkflowExecutor.cpp" "Sleep\(1200\)(?![\s\S]{0,200}not_state_replaced)" "Explorer 1200ms sleeps are replaced or marked" "Explorer contains unmarked Sleep(1200)"

Assert-Contains "src\winagent\BrowserWorkflowExecutor.cpp" "workflowWaits|WorkflowWaitStateSummary" "Browser outcome carries workflow wait evidence" "Browser outcome missing workflow wait evidence"
Assert-Contains "src\winagent\BrowserWorkflowExecutor.cpp" "WaitForWorkflowState" "Browser workflow uses state waits" "Browser workflow does not use state waits"
Assert-Contains "src\winagent\BrowserWorkflowExecutor.cpp" "RecordWorkflowWaitNotReplaced|not_state_replaced" "Browser workflow records not_replaced waits" "Browser workflow does not record not_replaced waits"
Assert-Contains "src\winagent\BrowserWorkflowExecutor.cpp" "workflow_wait_summary" "Browser JSON emits workflow wait summary" "Browser JSON missing workflow wait summary"
Assert-NotContains "src\winagent\BrowserWorkflowExecutor.cpp" "Sleep\(600\)(?![\s\S]{0,200}not_state_replaced)" "Browser 600ms sleeps are replaced or marked" "Browser contains unmarked Sleep(600)"

Assert-Exists "artifacts\dev1.1.7_workflow_wait_state_hardening\not_replaced_workflow_waits.md"
Assert-Contains "artifacts\dev1.1.7_workflow_wait_state_hardening\not_replaced_workflow_waits.md" "Code/IDE|IDE" "Code/IDE workflow waits have an explicit retained/blocked reason" "Code/IDE not_replaced or blocked reason is missing"

$latencyFields = @(
    "workflow_wait_total_ms",
    "workflow_wait_saved_ms",
    "workflow_wait_timeout_count",
    "workflow_wait_not_replaced_count",
    "workflow_wait_sites",
    "workflow_wait_replaced_from_sleep_ms",
    "workflow_wait_exit_reasons",
    "explorer_wait_total_ms",
    "explorer_wait_saved_ms",
    "browser_wait_total_ms",
    "browser_wait_saved_ms",
    "code_workflow_wait_total_ms",
    "code_workflow_wait_saved_ms"
)
foreach ($field in $latencyFields) {
    Assert-Contains "src\winagent\OperationTimelineProfiler.cpp" $field "Latency profiler emits $field" "Latency profiler missing $field"
}
Assert-Contains "src\winagent\OperationTimelineProfiler.cpp" "workflow_state_wait_probe" "Latency profiler includes workflow wait probe scenario" "Latency profiler missing workflow wait probe scenario"
Assert-Contains "docs\LATENCY_OBSERVABILITY.md" "workflow_wait_total_ms" "Latency doc describes workflow_wait_total_ms" "Latency doc missing workflow_wait_total_ms"

$baselinePath = Join-Path $ArtifactDir "latency_baseline_v1_1_11.json"
if (Test-Path -LiteralPath $baselinePath) {
    $summary = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json
    foreach ($field in $latencyFields) {
        Assert-Property -Object $summary -Name $field -Context "v1.1.12 latency baseline"
    }
    if ($summary.version -eq "1.1.12") {
        Add-Pass "v1.1.12 latency baseline reports version 1.1.12"
    } else {
        Add-Failure "v1.1.12 latency baseline reports version '$($summary.version)'"
    }
} else {
    Add-Failure "latency_baseline_v1_1_11.json is missing"
}

Assert-Exists "artifacts\dev1.1.7_workflow_wait_state_hardening\workflow_wait_replacement_summary.md"
Assert-Exists "artifacts\dev1.1.7_workflow_wait_state_hardening\v1_1_6_vs_v1_1_7_workflow_wait_latency_comparison.md"

Assert-GitCleanForPaths -Paths @("src/winagent/PermissionManager.cpp", "config/safety_manifest.json", "config/safety.conf") -PassMessage "PermissionManager and protected safety config are unmodified" -FailPrefix "Protected boundary modified"

Assert-Contains "docs\VLM_LAZY_LOADING.md" "Default capability probe timeout:\s*12000 ms" "VLM capability probe timeout remains documented as 12000ms" "VLM capability probe timeout documentation changed"
Assert-Contains "docs\VLM_LAZY_LOADING.md" "Default actual VLM locate/inference timeout:\s*60000 ms" "VLM inference timeout remains documented as 60000ms" "VLM inference timeout documentation changed"

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

if ((Test-Path -LiteralPath (Join-Path $Root "core_wait_state_selftest.ps1")) -and $version -eq "1.1.12") {
    $coreOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "core_wait_state_selftest.ps1") 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Pass "Core wait-state selftest still PASS"
    } else {
        Add-Failure "Core wait-state selftest failed: $($coreOutput -join [Environment]::NewLine)"
    }
}

if ((Test-Path -LiteralPath (Join-Path $Root "vlm_lazy_cache_selftest.ps1")) -and $version -eq "1.1.12") {
    $vlmOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "vlm_lazy_cache_selftest.ps1") 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Pass "VLM lazy/cache selftest still PASS"
    } else {
        Add-Failure "VLM lazy/cache selftest failed: $($vlmOutput -join [Environment]::NewLine)"
    }
}

if ($Failures.Count -eq 0) {
    Write-Host "Workflow wait-state selftest PASS"
    exit 0
}

Write-Host "Workflow wait-state selftest FAIL: $($Failures.Count) failure(s)"
exit 1




