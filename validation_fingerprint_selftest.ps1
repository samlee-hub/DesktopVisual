param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.8.0_preflight_validation_consistency_hardening'
$OutDir = Join-Path $ArtifactRoot 'selftest\fingerprint'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before validation_fingerprint_selftest.ps1."
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

function Get-CommandData([string]$JsonText) {
    $parsed = $JsonText | ConvertFrom-Json
    if ($parsed.ok -ne $true) {
        throw "Expected winagent command ok=true. Response: $JsonText"
    }
    return $parsed.data
}

$Evidence = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$Fingerprint = Join-Path $OutDir 'move_file_fingerprint.json'
$MismatchResult = Join-Path $OutDir 'move_file_mismatch_result.json'
$TamperedFingerprint = Join-Path $OutDir 'move_file_fingerprint_tampered.json'

$fingerprintRun = Invoke-WinAgent @(
    'validation-fingerprint',
    '--feature', 'v6_7_explorer_move_file',
    '--evidence', $Evidence,
    '--output', $Fingerprint
)

if (-not (Test-Path -LiteralPath $Fingerprint)) {
    throw 'validation-fingerprint did not write the fingerprint JSON.'
}

$data = Get-CommandData $fingerprintRun.Stdout
$requiredFields = @(
    'fingerprint_id',
    'feature_id',
    'feature_version',
    'evidence_source_path',
    'input_spec_hash',
    'step_contract_hash',
    'execution_summary_hash',
    'verification_summary_hash',
    'final_status_hash',
    'artifact_manifest_hash',
    'created_at',
    'fingerprint_version'
)
foreach ($field in $requiredFields) {
    if ([string]::IsNullOrWhiteSpace([string]$data.$field)) {
        throw "Fingerprint field missing or empty: $field"
    }
}
if ($data.feature_id -ne 'v6_7_explorer_move_file') { throw 'Fingerprint feature_id mismatch.' }
if ($data.ui_workflow_executed -ne $false) { throw 'Fingerprint command must not execute UI workflow.' }
if ($data.fingerprint_is_execution_result -ne $false) { throw 'Fingerprint must not be represented as execution result.' }

$fp = Get-Content -Raw -LiteralPath $Fingerprint | ConvertFrom-Json
$fp.artifact_manifest_hash = 'tampered_manifest_hash'
$fp | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $TamperedFingerprint -Encoding UTF8

$mismatch = Invoke-WinAgent @(
    'validation-consistency-check',
    '--feature', 'v6_7_explorer_move_file',
    '--evidence', $Evidence,
    '--fingerprint', $TamperedFingerprint,
    '--blocked-evidence', (Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows'),
    '--output', $MismatchResult
) @(1)

$mismatchJson = Get-Content -Raw -LiteralPath $MismatchResult | ConvertFrom-Json
if ($mismatchJson.consistency_ok -ne $false) { throw 'Tampered fingerprint was not rejected.' }
if (@($mismatchJson.hash_mismatches).Count -lt 1) { throw 'Fingerprint mismatch did not report hash_mismatches.' }
if ($mismatch.Stdout -notmatch 'BLOCKED_PREFLIGHT_FINGERPRINT_MISMATCH') {
    throw 'Fingerprint mismatch did not surface BLOCKED_PREFLIGHT_FINGERPRINT_MISMATCH.'
}

$report = Join-Path $OutDir 'validation_fingerprint_selftest_report.md'
@(
    '# Validation Fingerprint Selftest'
    ''
    '- Status: PASS'
    '- validation-fingerprint writes required schema fields: PASS'
    '- fingerprint command UI workflow executed: false'
    '- fingerprint is not execution result: PASS'
    '- tampered fingerprint mismatch detected: PASS'
    "- fingerprint: $Fingerprint"
    "- mismatch_result: $MismatchResult"
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Validation fingerprint selftest PASS. Report: $report"
