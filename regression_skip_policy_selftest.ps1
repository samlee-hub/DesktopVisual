param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.8.0_preflight_validation_consistency_hardening'
$OutDir = Join-Path $ArtifactRoot 'selftest\skip_policy'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before regression_skip_policy_selftest.ps1."
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

$Evidence = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$Fingerprint = Join-Path $OutDir 'move_file_fingerprint.json'
$Unchanged = Join-Path $OutDir 'unchanged_files.txt'
$ExplorerChanged = Join-Path $OutDir 'explorer_changed_files.txt'
$MismatchFingerprint = Join-Path $OutDir 'move_file_fingerprint_mismatch.json'
$UnchangedResult = Join-Path $OutDir 'unchanged_skip_result.json'
$ChangedResult = Join-Path $OutDir 'changed_skip_result.json'
$MismatchResult = Join-Path $OutDir 'mismatch_skip_result.json'

Invoke-WinAgent @('validation-fingerprint', '--feature', 'v6_7_explorer_move_file', '--evidence', $Evidence, '--output', $Fingerprint) | Out-Null

'' | Set-Content -LiteralPath $Unchanged -Encoding UTF8
'src\winagent\ExplorerWorkflowExecutor.cpp' | Set-Content -LiteralPath $ExplorerChanged -Encoding UTF8

Invoke-WinAgent @('regression-skip-evaluate', '--feature', 'v6_7_explorer_move_file', '--changed-files', $Unchanged, '--fingerprint', $Fingerprint, '--output', $UnchangedResult) | Out-Null
$unchangedResult = Get-Content -Raw -LiteralPath $UnchangedResult | ConvertFrom-Json
if ($unchangedResult.skip_allowed -ne $true) { throw 'Accepted unchanged feature did not allow skip.' }
if ($unchangedResult.replay_required -ne $false) { throw 'Accepted unchanged feature incorrectly required replay.' }

Invoke-WinAgent @('regression-skip-evaluate', '--feature', 'v6_7_explorer_move_file', '--changed-files', $ExplorerChanged, '--fingerprint', $Fingerprint, '--output', $ChangedResult) | Out-Null
$changedResult = Get-Content -Raw -LiteralPath $ChangedResult | ConvertFrom-Json
if ($changedResult.skip_allowed -ne $false) { throw 'Explorer source change incorrectly allowed skip.' }
if ($changedResult.replay_required -ne $true) { throw 'Explorer source change did not require replay.' }
if ($changedResult.source_change_detected -ne $true) { throw 'Explorer source change was not detected.' }

$fp = Get-Content -Raw -LiteralPath $Fingerprint | ConvertFrom-Json
$fp.fingerprint_status = 'MISMATCH'
$fp | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $MismatchFingerprint -Encoding UTF8
Invoke-WinAgent @('regression-skip-evaluate', '--feature', 'v6_7_explorer_move_file', '--changed-files', $Unchanged, '--fingerprint', $MismatchFingerprint, '--output', $MismatchResult) | Out-Null
$mismatchResult = Get-Content -Raw -LiteralPath $MismatchResult | ConvertFrom-Json
if ($mismatchResult.skip_allowed -ne $false) { throw 'Fingerprint mismatch incorrectly allowed skip.' }
if ($mismatchResult.replay_required -ne $true) { throw 'Fingerprint mismatch did not require replay.' }
if ($mismatchResult.evidence_fingerprint_ok -ne $false) { throw 'Fingerprint mismatch did not set evidence_fingerprint_ok=false.' }

$report = Join-Path $OutDir 'regression_skip_policy_selftest_report.md'
@(
    '# Regression Skip Policy Selftest'
    ''
    '- Status: PASS'
    '- accepted unchanged feature skip_allowed=true: PASS'
    '- source change replay_required=true: PASS'
    '- fingerprint mismatch replay_required=true: PASS'
    "- unchanged_result: $UnchangedResult"
    "- changed_result: $ChangedResult"
    "- mismatch_result: $MismatchResult"
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Regression skip policy selftest PASS. Report: $report"
