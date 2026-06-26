param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.8.0_preflight_validation_consistency_hardening'
$RunnerResultPath = Join-Path $ArtifactRoot 'preflight_runner_result.json'
$VerifierResultPath = Join-Path $ArtifactRoot 'preflight_verifier_result.json'
$VerifierReport = Join-Path $ArtifactRoot 'preflight_verifier_report.md'

if (-not (Test-Path -LiteralPath $RunnerResultPath)) {
    throw "preflight runner result not found: $RunnerResultPath"
}

$runner = Get-Content -Raw -LiteralPath $RunnerResultPath | ConvertFrom-Json
$blockers = @()

if ($runner.status -ne 'PASS') { $blockers += 'BLOCKED_PREFLIGHT_RUNNER_NOT_PASS' }
if ($runner.ui_workflow_executed -ne $false) { $blockers += 'BLOCKED_PREFLIGHT_SCOPE_VIOLATION' }
if ($runner.entered_v6_8_feature_development -ne $false) { $blockers += 'BLOCKED_PREFLIGHT_STARTED_V6_8_FEATURE' }

foreach ($fp in @($runner.fingerprints)) {
    if ($fp.fingerprint_ok -ne $true) { $blockers += "BLOCKED_PREFLIGHT_FINGERPRINT_FAILED:$($fp.feature_id)" }
    if ($fp.ui_workflow_executed -ne $false) { $blockers += "BLOCKED_PREFLIGHT_SCOPE_VIOLATION:$($fp.feature_id)" }
}

foreach ($item in @($runner.consistency)) {
    if ($item.consistency_ok -ne $true) { $blockers += "BLOCKED_PREFLIGHT_STATUS_CONFLICT:$($item.feature_id)" }
    if ([int]$item.missing_evidence -ne 0) { $blockers += "BLOCKED_PREFLIGHT_EVIDENCE_MISSING:$($item.feature_id)" }
    if ([int]$item.hash_mismatches -ne 0) { $blockers += "BLOCKED_PREFLIGHT_FINGERPRINT_MISMATCH:$($item.feature_id)" }
    if ($item.ui_workflow_executed -ne $false) { $blockers += "BLOCKED_PREFLIGHT_SCOPE_VIOLATION:$($item.feature_id)" }
}

foreach ($item in @($runner.skip_policy)) {
    if ($item.skip_allowed -ne $true) { $blockers += "BLOCKED_PREFLIGHT_UNSAFE_SKIP_POLICY:$($item.feature_id)" }
    if ($item.replay_required -ne $false) { $blockers += "BLOCKED_PREFLIGHT_UNSAFE_SKIP_POLICY:$($item.feature_id)" }
    if ($item.evidence_fingerprint_ok -ne $true) { $blockers += "BLOCKED_PREFLIGHT_FINGERPRINT_MISMATCH:$($item.feature_id)" }
    if ($item.consistency_check_ok -ne $true) { $blockers += "BLOCKED_PREFLIGHT_STATUS_CONFLICT:$($item.feature_id)" }
}

$probe = Get-Content -Raw -LiteralPath $runner.source_change_probe_result | ConvertFrom-Json
if ($probe.replay_required -ne $true -or $probe.skip_allowed -ne $false -or $probe.source_change_detected -ne $true) {
    $blockers += 'BLOCKED_PREFLIGHT_UNSAFE_SKIP_POLICY:source_change_probe'
}

$commandLog = if (Test-Path -LiteralPath $runner.command_log) { Get-Content -Raw -LiteralPath $runner.command_log } else { '' }
$forbiddenCommands = @(
    'run-explorer-workflow',
    'v6_7_0_explorer_workflow_runner',
    'explorer_move_file_selftest',
    'explorer_scroll_and_locate_selftest',
    'vlm-assisted-locate-and-click-local-safe'
)
foreach ($command in $forbiddenCommands) {
    if ($commandLog -match [regex]::Escape($command)) {
        $blockers += "BLOCKED_PREFLIGHT_SCOPE_VIOLATION:$command"
    }
}

$requiredFiles = @(
    'agent_context_digest.md',
    'evidence_fingerprint_report.md',
    'validation_consistency_report.md',
    'regression_skip_policy_report.md',
    'evidence_index.md',
    'final_status_report.md',
    'evidence_hash_lock.json'
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $ArtifactRoot $file))) {
        $blockers += "BLOCKED_PREFLIGHT_EVIDENCE_MISSING:$file"
    }
}

$blockers = @($blockers | Select-Object -Unique)
$status = if ($blockers.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$result = [pscustomobject]@{
    status = $status
    blockers = $blockers
    ui_workflow_executed = $false
    entered_v6_8_feature_development = $false
    source_change_probe_replay_required = $probe.replay_required
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $VerifierResultPath -Encoding UTF8

@(
    '# v6.8.0 Preflight Validation Verifier Report'
    ''
    "- Status: $status"
    '- UI workflow executed: false'
    '- v6.8 Browser/Form feature implementation started: false'
    "- source_change_probe_replay_required: $($probe.replay_required)"
    ''
    '## Blockers'
    ($(if ($blockers.Count -eq 0) { '- none' } else { $blockers | ForEach-Object { "- $_" } }))
) | Set-Content -LiteralPath $VerifierReport -Encoding UTF8

if ($status -ne 'PASS') {
    Write-Host "v6.8.0 preflight verifier BLOCKED. Report: $VerifierReport"
    exit 1
}

Write-Host "v6.8.0 preflight verifier PASS. Report: $VerifierReport"
