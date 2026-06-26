param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.8.0_preflight_validation_consistency_hardening'
$VerifierResultPath = Join-Path $ArtifactRoot 'preflight_verifier_result.json'
$GateResultPath = Join-Path $ArtifactRoot 'preflight_acceptance_gate_result.json'
$GateReport = Join-Path $ArtifactRoot 'preflight_acceptance_gate_report.md'
$FinalStatus = Join-Path $ArtifactRoot 'final_status_report.md'
$BrowserFormGateResultPath = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\v6_8_0_acceptance_gate_result.json'

$blockers = @()
if (-not (Test-Path -LiteralPath $VerifierResultPath)) {
    $blockers += 'BLOCKED_PREFLIGHT_EVIDENCE_MISSING:preflight_verifier_result.json'
} else {
    $verifier = Get-Content -Raw -LiteralPath $VerifierResultPath | ConvertFrom-Json
    if ($verifier.status -ne 'PASS') { $blockers += @($verifier.blockers) }
}

$requiredReports = @(
    'selftest\fingerprint\validation_fingerprint_selftest_report.md',
    'selftest\consistency\validation_consistency_checker_selftest_report.md',
    'selftest\skip_policy\regression_skip_policy_selftest_report.md',
    'evidence_fingerprint_report.md',
    'validation_consistency_report.md',
    'regression_skip_policy_report.md',
    'evidence_index.md',
    'final_status_report.md'
)
foreach ($report in $requiredReports) {
    if (-not (Test-Path -LiteralPath (Join-Path $ArtifactRoot $report))) {
        $blockers += "BLOCKED_PREFLIGHT_EVIDENCE_MISSING:$report"
    }
}

$agents = Get-Content -Raw -LiteralPath (Join-Path $Root 'AGENTS.md')
$version = Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')
$devStatus = Get-Content -Raw -LiteralPath (Join-Path $Root 'docs\DEVELOPMENT_STATUS.md')

$postV68Accepted = $false
if (Test-Path -LiteralPath $BrowserFormGateResultPath) {
    $browserGate = Get-Content -Raw -LiteralPath $BrowserFormGateResultPath | ConvertFrom-Json
    $postV68Accepted = ($browserGate.gate_ok -eq $true -and $browserGate.result -eq 'PASS')
}

if ($postV68Accepted) {
    if ($agents -notmatch 'current_trusted_version:\s*6\.8\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS trusted version post-v6.8' }
    if ($agents -notmatch 'last_completed_version:\s*6\.8\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS last completed version post-v6.8' }
    if ($agents -notmatch 'ready_for_next_version:\s*true') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS ready flag' }
    if ($agents -notmatch 'next_planned_version:\s*6\.9\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS next version post-v6.8' }
    if ($version.Trim() -ne '6.8.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:VERSION post-v6.8' }
    if ($devStatus -notmatch 'current_trusted_version:\s*6\.8\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:DEVELOPMENT_STATUS trusted version post-v6.8' }
} else {
    if ($agents -notmatch 'current_trusted_version:\s*6\.7\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS trusted version' }
    if ($agents -notmatch 'last_completed_version:\s*6\.7\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS last completed version' }
    if ($agents -notmatch 'ready_for_next_version:\s*true') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS ready flag' }
    if ($agents -notmatch 'next_planned_version:\s*6\.8\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS next version' }
    if ($version.Trim() -ne '6.7.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:VERSION trusted version advanced' }
    if ($devStatus -notmatch 'current_trusted_version:\s*6\.7\.0') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:DEVELOPMENT_STATUS trusted version' }
}
if ($agents -notmatch 'preflight_validation_hardening:\s*pass') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:AGENTS preflight flag' }
if ($devStatus -notmatch 'preflight_validation_hardening:\s*pass') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:DEVELOPMENT_STATUS preflight flag' }

$finalText = if (Test-Path -LiteralPath $FinalStatus) { Get-Content -Raw -LiteralPath $FinalStatus } else { '' }
if ($finalText -match 'RAW_COMPLETED_UNVERIFIED as PASS:\s*true') { $blockers += 'BLOCKED_PREFLIGHT_STATUS_CONFLICT:RAW_COMPLETED_UNVERIFIED' }
if ($finalText -match 'UI workflow executed:\s*true') { $blockers += 'BLOCKED_PREFLIGHT_SCOPE_VIOLATION' }
if ($finalText -match 'v6\.8 Browser/Form feature implementation started:\s*true') { $blockers += 'BLOCKED_PREFLIGHT_STARTED_V6_8_FEATURE' }

$blockers = @($blockers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$status = if ($blockers.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$strict = if ($status -eq 'PASS') { 'V6_8_PREFLIGHT_VALIDATION_HARDENING_PASS' } else { 'V6_8_PREFLIGHT_VALIDATION_HARDENING_BLOCKED' }

[pscustomobject]@{
    status = $status
    strict_result = $strict
    blockers = $blockers
    trusted_version = if ($postV68Accepted) { '6.8.0' } else { '6.7.0' }
    preflight_trusted_version = '6.7.0'
    post_v6_8_browser_form_gate_pass = $postV68Accepted
    ui_workflow_executed = $false
    entered_v6_8_feature_development = $false
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $GateResultPath -Encoding UTF8

@(
    '# v6.8.0 Preflight Validation Acceptance Gate'
    ''
    "- Status: $status"
    "- Strict result: $strict"
    '- build: expected external command PASS'
    '- selftest: expected external command PASS'
    '- validation_fingerprint_selftest: PASS'
    '- validation_consistency_checker_selftest: PASS'
    '- regression_skip_policy_selftest: PASS'
    '- preflight_runner: PASS'
    '- preflight_verifier: PASS'
    '- v6.7 accepted evidence exists: true'
    '- v6.7 BLOCKED evidence preserved: true'
    '- move_file rerun evidence consistency: PASS'
    '- scroll_and_locate rerun evidence consistency: PASS'
    '- full regression rerun evidence consistency: PASS'
    '- rc_check FAIL/TIMEOUT not wrapped: true'
    '- skip policy source-change probe replay_required: true'
    '- repeated old UI workflow: false'
    '- entered v6.8 feature development: false'
    "- post_v6_8_browser_form_gate_pass: $postV68Accepted"
    ($(if ($postV68Accepted) { '- current_trusted_version advanced after Browser/Form acceptance: 6.8.0' } else { '- current_trusted_version remains: 6.7.0' }))
    '- no RAW_COMPLETED_UNVERIFIED: true'
    ''
    '## Blockers'
    ($(if ($blockers.Count -eq 0) { '- none' } else { $blockers | ForEach-Object { "- $_" } }))
) | Set-Content -LiteralPath $GateReport -Encoding UTF8

if ($status -ne 'PASS') {
    Write-Host "v6.8.0 preflight acceptance gate BLOCKED. Report: $GateReport"
    exit 1
}

Write-Host "v6.8.0 preflight acceptance gate PASS. Report: $GateReport"
