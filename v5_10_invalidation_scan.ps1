param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

function Fail($Message) { throw $Message }

function Invoke-Rg {
    param([string[]]$RgArgs)
    $output = & rg @RgArgs 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

Push-Location $Root
try {
    $invalidated = @(
        'artifacts\invalidated\dev5.10.1_adaptive_cases_INVALIDATED',
        'artifacts\invalidated\dev5.10.2_final_pre_v6_gate_INVALIDATED'
    )
    foreach ($path in $invalidated) {
        if (-not (Test-Path -LiteralPath $path)) { Fail "Missing invalidated artifact path: $path" }
        if (-not (Test-Path -LiteralPath (Join-Path $path 'INVALIDATED_DO_NOT_USE.md'))) {
            Fail "Missing INVALIDATED_DO_NOT_USE.md in $path"
        }
    }

    foreach ($path in @('artifacts\dev5.10.1_adaptive_cases', 'artifacts\dev5.10.2_final_pre_v6_gate')) {
        if (Test-Path -LiteralPath $path) { Fail "Original invalidated artifact path still exists: $path" }
    }

    $evidenceIndexes = Get-ChildItem -Path artifacts -Filter evidence_index.md -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\artifacts\\invalidated\\' -and $_.FullName -notmatch '\\artifacts\\dev5\.10_invalidation_rollback\\' }
    foreach ($index in $evidenceIndexes) {
        $content = Get-Content -Raw -LiteralPath $index.FullName
        if ($content -match 'dev5\.10\.1_adaptive_cases|dev5\.10\.2_final_pre_v6_gate') {
            Fail "Invalidated artifact is referenced by valid evidence index: $($index.FullName)"
        }
    }

    $ready = Invoke-Rg -RgArgs @(
        '-n',
        'ready_for_v6\s*[:=]\s*true|ready_for_v6=true',
        '-g', '!v5_10_invalidation_scan.ps1',
        '-g', '!*artifacts/invalidated/**',
        '-g', '!*artifacts/dev5.10_invalidation_rollback/**',
        '.'
    )
    if ($ready.ExitCode -eq 0) { Fail "ready_for_v6 true claim remains:`n$($ready.Output -join "`n")" }
    if ($ready.ExitCode -gt 1) { Fail "ready_for_v6 scan failed:`n$($ready.Output -join "`n")" }

    $runner = Get-Content -Raw -LiteralPath 'v5_10_1_adaptive_cases_runner.ps1'
    if ($runner -match 'STRICT_ADAPTIVE_HUMANMODE_PASS|STRICT_MOUSE_TARGET_HUMANMODE_PASS|Save-PlaceholderPng|Add-AdaptiveStep') {
        Fail 'v5_10_1_adaptive_cases_runner.ps1 still contains synthetic PASS generation markers.'
    }
    if ($runner -notmatch 'INVALIDATED' -or $runner -notmatch 'exit 1') {
        Fail 'v5_10_1_adaptive_cases_runner.ps1 does not hard-fail as invalidated.'
    }

    $taskRuntimeFiles = @(
        'src\winagent\TaskSession.cpp',
        'src\winagent\TaskRunner.cpp',
        'src\winagent\WinAgent.cpp'
    )
    $taskRuntimePatterns = @(
        '0x5102',
        'STRICT_ADAPTIVE_HUMANMODE_PASS',
        'task_runtime_humanmode_browser_flow":true',
        'task_runtime_humanmode_browser_flow\":true'
    )
    foreach ($pattern in $taskRuntimePatterns) {
        $matches = Select-String -Path $taskRuntimeFiles -Pattern $pattern -SimpleMatch
        if ($matches) {
            Fail "Hardcoded TaskRuntime browser-flow PASS path remains:`n$($matches -join "`n")"
        }
    }

    $placeholder = Invoke-Rg -RgArgs @(
        '-n',
        'Save-PlaceholderPng|Add-AdaptiveStep',
        '-g', '!v5_10_invalidation_scan.ps1',
        '-g', '!*artifacts/invalidated/**',
        '-g', '!*artifacts/dev5.10_invalidation_rollback/**',
        '.'
    )
    if ($placeholder.ExitCode -eq 0) { Fail "Placeholder/Add-AdaptiveStep path remains outside invalidated archive:`n$($placeholder.Output -join "`n")" }
    if ($placeholder.ExitCode -gt 1) { Fail "Placeholder scan failed:`n$($placeholder.Output -join "`n")" }

    [pscustomobject]@{
        ok = $true
        version = '5.10.0'
        invalidated_artifacts_isolated = $true
        valid_evidence_index_excludes_invalidated = $true
        ready_for_v6_true_absent = $true
        synthetic_runner_can_output_pass = $false
        hardcoded_taskruntime_browser_flow_pass_absent = $true
        placeholder_pass_path_absent = $true
    } | ConvertTo-Json -Depth 5
} finally {
    Pop-Location
}
