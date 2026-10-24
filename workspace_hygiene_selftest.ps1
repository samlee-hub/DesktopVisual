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

Assert-Exists "docs\FIELD_TEST_READINESS.md"
Assert-Exists "docs\WORKSPACE_HYGIENE.md"
Assert-Exists "artifacts\EVIDENCE_INDEX.md"
Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md"
Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\cleanup_deleted_files.txt"
Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\ambiguous_files.md"
Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\unexpected_dirty_state.md"
Assert-Exists "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\field_test_plan.md"

Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "Current version:\s*1\.1\.12" "Current contract states v1.1.12" "Current contract missing v1.1.12"
Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "Launch Contract Unification|VS Startup Convergence" "Current contract states v1.1.12 stage" "Current contract missing v1.1.12 stage"
Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "do not enter v1\.2\.0|not entered by v1\.1\.12" "Current contract points away from v1.2.0" "Current contract missing no-v1.2.0 boundary"
Assert-Contains "CURRENT_EXECUTION_CONTRACT.md" "does not reduce permissions|PermissionManager semantics unchanged" "Current contract preserves permission boundary" "Current contract missing permission boundary"

Assert-Contains "docs\FIELD_TEST_READINESS.md" "STOP conditions" "Field test readiness documents STOP conditions" "Field test readiness missing STOP conditions"
Assert-Contains "docs\FIELD_TEST_READINESS.md" "environment failure.*runtime failure|runtime failure.*environment failure" "Field test readiness distinguishes environment and runtime failure" "Field test readiness missing environment/runtime failure distinction"
Assert-Contains "docs\WORKSPACE_HYGIENE.md" "ambiguous" "Workspace hygiene doc covers ambiguous files" "Workspace hygiene doc missing ambiguous file rule"
Assert-Contains "docs\WORKSPACE_HYGIENE.md" "desktop_release" "Workspace hygiene doc forbids desktop_release cleanup/sync" "Workspace hygiene doc missing desktop_release boundary"

foreach ($versionId in @(
    "dev1.1.1_current_execution_contract_unification",
    "dev1.1.2_documentation_entry_slimming",
    "dev1.1.3_release_channel_semantic_cleanup",
    "dev1.1.4_latency_observability_baseline",
    "dev1.1.5_vlm_lazy_cache_fast_degradation",
    "dev1.1.6_core_wait_state_hardening",
    "dev1.1.7_workflow_wait_state_hardening",
    "dev1.1.8_workspace_hygiene_field_test_readiness"
)) {
    Assert-Contains "artifacts\EVIDENCE_INDEX.md" $versionId "Evidence index includes $versionId" "Evidence index missing $versionId"
}

$classificationPath = "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md"
foreach ($section in @(
    "A\. Expected source changes",
    "B\. Required evidence artifacts",
    "C\. Temporary generated files",
    "D\. Ambiguous files",
    "E\. Unexpected dirty state"
)) {
    Assert-Contains $classificationPath $section "Workspace classification includes $section" "Workspace classification missing $section"
}

Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\cleanup_deleted_files.txt" "(?im)^none$|deleted" "Cleanup deletion ledger is explicit" "Cleanup deletion ledger is not explicit"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\ambiguous_files.md" "(?im)^none$|ambiguous" "Ambiguous file ledger is explicit" "Ambiguous file ledger is not explicit"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\unexpected_dirty_state.md" "(?im)^none$" "Unexpected dirty state ledger is none" "Unexpected dirty state ledger is not none"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\field_test_plan.md" "Explorer real file workflow" "Field test plan covers Explorer" "Field test plan missing Explorer"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\field_test_plan.md" "Browser local HTML workflow" "Field test plan covers local browser" "Field test plan missing local browser"
Assert-Contains "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\field_test_plan.md" "Active protection simulated STOP page" "Field test plan covers STOP simulation" "Field test plan missing STOP simulation"

$manifest = Read-Text "config\safety_manifest.json" | ConvertFrom-Json
if ($manifest.default_permission_mode -eq "DEVELOPER_CAPABILITY_DISCOVERY") {
    Add-Pass "default_permission_mode remains DEVELOPER_CAPABILITY_DISCOVERY"
} else {
    Add-Failure "default_permission_mode is '$($manifest.default_permission_mode)', expected DEVELOPER_CAPABILITY_DISCOVERY"
}

Assert-GitCleanForPaths -Paths @("src/winagent/PermissionManager.cpp", "config/safety_manifest.json", "config/safety.conf") -PassMessage "PermissionManager and protected safety config are unmodified" -FailPrefix "Protected boundary modified"

foreach ($path in @(
    "src\winagent\CoreWaitState.h",
    "src\winagent\CoreWaitState.cpp",
    "src\winagent\ExplorerWorkflowExecutor.cpp",
    "src\winagent\BrowserWorkflowExecutor.cpp",
    "src\winagent\TaskRunner.cpp",
    "src\winagent\ForegroundPreparation.cpp",
    "src\winagent\ForegroundPreparation.h",
    "src\winagent\SafeContextRecovery.cpp",
    "src\winagent\SafeContextRecovery.h",
    "src\winagent\CursorAndBufferStateGuard.cpp",
    "src\winagent\CursorAndBufferStateGuard.h",
    "src\winagent\CodeEditorTypingPolicy.cpp",
    "src\winagent\CodeEditorTypingPolicy.h",
    "src\winagent\OperationTimelineProfiler.cpp",
    "src\winagent\OperationTimelineProfiler.h",
    "src\winagent\RealVlmRuntimeBridge.cpp",
    "tools\codex_vlm_provider.ps1"
)) {
    Assert-NotContains $path "1\.1\.8|Workspace Hygiene|FIELD_TEST_READINESS|WORKSPACE_HYGIENE" "$path has no v1.1.8 behavior marker" "$path contains a v1.1.8 behavior marker"
}

Assert-Contains "src\winagent\WinAgent.cpp" 'kRuntimeVersion\s*=\s*L"1\.1\.12"' "Runtime metadata version is 1.1.12" "Runtime metadata version is not 1.1.12"

$developerReleasePaths = @(& git status --short -- "desktop_release" "desktopvisual-public-dist" "public-dist" "public_dist" 2>$null)
if ($developerReleasePaths.Count -eq 0) {
    Add-Pass "No release/public-dist paths changed inside developer tree"
} else {
    foreach ($path in $developerReleasePaths) {
        Add-Failure "Unexpected release/public-dist path changed inside developer tree: $path"
    }
}

foreach ($path in @("desktop_release", "desktopvisual-public-dist", "public-dist", "public_dist", "restricted_public_release")) {
    if (Test-Path -LiteralPath (Join-Path $Root $path)) {
        Add-Failure "Unexpected release/public tree exists inside developer tree: $path"
    } else {
        Add-Pass "$path is absent inside developer tree"
    }
}

$rootName = Split-Path -Leaf $Root
$siblingReleaseRoot = Join-Path (Split-Path -Parent $Root) "desktop_release"
if ($rootName -ieq "desktop_release") {
    if (Test-ApprovedDesktopReleaseSync -ReleaseRoot $Root -ExpectedVersion $version) {
        Add-Pass "Current desktop_release VERSION is $version with approved local-use/demo/testing sync evidence"
    } else {
        Add-Failure "Current desktop_release VERSION is $version but approved sync evidence is incomplete"
    }
} elseif (Test-Path -LiteralPath $siblingReleaseRoot) {
    $siblingVersionPath = Join-Path $siblingReleaseRoot "VERSION"
    if (Test-Path -LiteralPath $siblingVersionPath) {
        $siblingVersion = (Get-Content -Raw -LiteralPath $siblingVersionPath).Trim()
        if ($siblingVersion -eq $version -and (Test-ApprovedDesktopReleaseSync -ReleaseRoot $siblingReleaseRoot -ExpectedVersion $version)) {
            Add-Pass "Sibling desktop_release VERSION is $version with approved local-use/demo/testing sync evidence"
        } else {
            Add-Pass "Sibling desktop_release VERSION is '$siblingVersion', not current v$version sync"
        }
    } else {
        Add-Pass "Sibling desktop_release VERSION file is missing; no v$version sync detected"
    }
} else {
    Add-Pass "Sibling desktop_release path is missing; no v$version sync detected"
}

if ($Failures.Count -eq 0) {
    Write-Host "Workspace hygiene selftest PASS"
    exit 0
}

Write-Host "Workspace hygiene selftest FAIL: $($Failures.Count) failure(s)"
exit 1




