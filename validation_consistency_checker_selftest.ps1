param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.8.0_preflight_validation_consistency_hardening'
$OutDir = Join-Path $ArtifactRoot 'selftest\consistency'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before validation_consistency_checker_selftest.ps1."
}

function Invoke-WinAgent([string[]]$CommandArgs, [int[]]$AllowedExitCodes = @(0)) {
    $name = [guid]::NewGuid().ToString('N')
    $stdout = Join-Path $OutDir "$name.stdout.json"
    $stderr = Join-Path $OutDir "$name.stderr.txt"
    & $WinAgent @CommandArgs 1> $stdout 2> $stderr
    $exitCode = $LASTEXITCODE
    $text = if (Test-Path -LiteralPath $stdout) { Get-Content -Raw -LiteralPath $stdout } else { '' }
    if ($AllowedExitCodes -notcontains $exitCode) {
        $err = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -LiteralPath $stderr } else { '' }
        throw "winagent $($CommandArgs -join ' ') exit $exitCode. stdout=$text stderr=$err"
    }
    return @{ ExitCode = $exitCode; Stdout = $text; StdoutPath = $stdout; StderrPath = $stderr }
}

function Write-FixtureEvidence([string]$Path, [string]$FinalStatus = 'PASS', [string]$GateStatus = 'PASS', [string]$RcStatus = 'FAIL') {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    @(
        '# Fixture Final Status'
        ''
        "- final_status: $FinalStatus"
        '- current_trusted_version: 6.7.0'
        '- full_regression_result: PASS'
        "- rc_check_status: $RcStatus"
        '- original_blocker: case_04_move_file VERIFY_MOVE_FAILED'
        '- original_blocker: case_06_scroll_and_locate FAIL_TARGET_NOT_FOUND'
        '- move_file_rerun: PASS selected=true cut=true paste=true executed=true verified=true power_shell_file_operation_used=false direct_file_api_used=false'
        '- scroll_and_locate_rerun: PASS list area focus Home reset per-iteration visible items real scroll progress target_found=true target_clicked_or_verified=true stale_rect=false'
        '- full_regression: PASS 47/47 completed 0 failed'
        '- RuntimeSession used=true'
        '- StepContractValidator used=true'
        '- RuntimeContextGuard used=true'
        '- RAW_COMPLETED_UNVERIFIED as PASS: false'
    ) | Set-Content -LiteralPath (Join-Path $Path 'final_status_report.md') -Encoding UTF8
    @(
        '# Fixture Gate'
        ''
        "- Status: $GateStatus"
        '- full_regression_completed: true'
        '- move_file_pass: True'
        '- scroll_and_locate_pass: True'
        '- power_shell_file_operation_used: False'
        '- direct_file_api_used: False'
        '- no RAW_COMPLETED_UNVERIFIED: true'
    ) | Set-Content -LiteralPath (Join-Path $Path 'v6_7_0_rerun_acceptance_gate_report.md') -Encoding UTF8
    @{
        final_status = 'PASS'
        full_regression_completed = $true
        started_from_beginning = $true
        completed_count = 47
        failed_count = 0
        total_count = 47
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Path 'full_regression_rerun_result.json') -Encoding UTF8
    @(
        '# Fixture Evidence Index'
        ''
        '- final_status_report.md'
        '- v6_7_0_rerun_acceptance_gate_report.md'
        '- full_regression_rerun_result.json'
    ) | Set-Content -LiteralPath (Join-Path $Path 'evidence_index.md') -Encoding UTF8
    @{ status = $RcStatus } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Path 'rc_check_result.json') -Encoding UTF8
}

$Evidence = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$BlockedEvidence = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows'
$Fingerprint = Join-Path $OutDir 'full_regression_fingerprint.json'
$ValidResult = Join-Path $OutDir 'valid_consistency_result.json'
$MissingResult = Join-Path $OutDir 'missing_consistency_result.json'
$ConflictResult = Join-Path $OutDir 'conflict_consistency_result.json'
$RcPassResult = Join-Path $OutDir 'rc_pass_consistency_result.json'
$BlockedLostResult = Join-Path $OutDir 'blocked_lost_consistency_result.json'

Invoke-WinAgent @(
    'validation-fingerprint',
    '--feature', 'v6_7_explorer_full_regression',
    '--evidence', $Evidence,
    '--output', $Fingerprint
) | Out-Null

Invoke-WinAgent @(
    'validation-consistency-check',
    '--feature', 'v6_7_explorer_full_regression',
    '--evidence', $Evidence,
    '--fingerprint', $Fingerprint,
    '--blocked-evidence', $BlockedEvidence,
    '--output', $ValidResult
) | Out-Null

$valid = Get-Content -Raw -LiteralPath $ValidResult | ConvertFrom-Json
if ($valid.consistency_ok -ne $true) { throw "Expected valid v6.7 evidence consistency PASS: $($valid.blocked_reason)" }
if ($valid.ui_workflow_executed -ne $false) { throw 'Consistency checker must not execute UI workflow.' }

Invoke-WinAgent @(
    'validation-consistency-check',
    '--feature', 'v6_7_explorer_full_regression',
    '--evidence', (Join-Path $OutDir 'missing_evidence'),
    '--fingerprint', $Fingerprint,
    '--blocked-evidence', $BlockedEvidence,
    '--output', $MissingResult
) @(1) | Out-Null
$missing = Get-Content -Raw -LiteralPath $MissingResult | ConvertFrom-Json
if (@($missing.missing_evidence).Count -lt 1) { throw 'Missing evidence was not reported.' }

$ConflictEvidence = Join-Path $OutDir 'fixture_status_conflict'
Write-FixtureEvidence $ConflictEvidence 'PASS' 'BLOCKED' 'FAIL'
$ConflictFingerprint = Join-Path $OutDir 'conflict_fingerprint.json'
Invoke-WinAgent @('validation-fingerprint', '--feature', 'v6_7_explorer_full_regression', '--evidence', $ConflictEvidence, '--output', $ConflictFingerprint) | Out-Null
Invoke-WinAgent @('validation-consistency-check', '--feature', 'v6_7_explorer_full_regression', '--evidence', $ConflictEvidence, '--fingerprint', $ConflictFingerprint, '--blocked-evidence', $BlockedEvidence, '--output', $ConflictResult) @(1) | Out-Null
$conflict = Get-Content -Raw -LiteralPath $ConflictResult | ConvertFrom-Json
if (@($conflict.status_conflicts).Count -lt 1) { throw 'Final status/gate conflict was not reported.' }

$RcPassEvidence = Join-Path $OutDir 'fixture_rc_pass'
Write-FixtureEvidence $RcPassEvidence 'PASS' 'PASS' 'PASS'
$RcPassFingerprint = Join-Path $OutDir 'rc_pass_fingerprint.json'
Invoke-WinAgent @('validation-fingerprint', '--feature', 'v6_7_explorer_full_regression', '--evidence', $RcPassEvidence, '--output', $RcPassFingerprint) | Out-Null
Invoke-WinAgent @('validation-consistency-check', '--feature', 'v6_7_explorer_full_regression', '--evidence', $RcPassEvidence, '--fingerprint', $RcPassFingerprint, '--blocked-evidence', $BlockedEvidence, '--output', $RcPassResult) @(1) | Out-Null
$rcPass = Get-Content -Raw -LiteralPath $RcPassResult | ConvertFrom-Json
if (@($rcPass.status_conflicts) -notcontains 'rc_check_wrapped_as_pass') { throw 'rc_check PASS substitute was not rejected.' }

$BadBlocked = Join-Path $OutDir 'fixture_blocked_history_lost'
Write-FixtureEvidence $BadBlocked 'PASS' 'PASS' 'FAIL'
Invoke-WinAgent @('validation-consistency-check', '--feature', 'v6_7_explorer_full_regression', '--evidence', $Evidence, '--fingerprint', $Fingerprint, '--blocked-evidence', $BadBlocked, '--output', $BlockedLostResult) @(1) | Out-Null
$blockedLost = Get-Content -Raw -LiteralPath $BlockedLostResult | ConvertFrom-Json
if (@($blockedLost.status_conflicts) -notcontains 'old_blocked_evidence_not_blocked') { throw 'Old BLOCKED evidence loss was not reported.' }

$report = Join-Path $OutDir 'validation_consistency_checker_selftest_report.md'
@(
    '# Validation Consistency Checker Selftest'
    ''
    '- Status: PASS'
    '- valid v6.7 evidence consistency: PASS'
    '- missing evidence detected: PASS'
    '- final_status/gate conflict detected: PASS'
    '- rc_check PASS substitute detected: PASS'
    '- old BLOCKED evidence overwrite detected: PASS'
    '- UI workflow executed: false'
    "- valid_result: $ValidResult"
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Validation consistency checker selftest PASS. Report: $report"
