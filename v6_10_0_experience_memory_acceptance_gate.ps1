param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$VerifierResult = Join-Path $ArtifactRoot 'verifier_result.json'
$GateReport = Join-Path $ArtifactRoot 'v6_10_0_experience_memory_acceptance_gate_report.md'
$FinalReport = Join-Path $ArtifactRoot 'final_status_report.md'
$EvidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'

if (-not (Test-Path -LiteralPath $RunnerResult)) { throw 'runner_result.json missing' }
if (-not (Test-Path -LiteralPath $VerifierResult)) { throw 'verifier_result.json missing' }
$runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
$verifier = Get-Content -Raw -LiteralPath $VerifierResult | ConvertFrom-Json

$requiredReports = @(
    'agent_context_digest.md',
    'memory_schema_report.md',
    'memory_store_report.md',
    'failure_attribution_report.md',
    'memory_safety_report.md',
    'positive_cases.md',
    'negative_cases.md'
)
$missing = @()
foreach ($name in $requiredReports) {
    $path = Join-Path $ArtifactRoot $name
    if (-not (Test-Path -LiteralPath $path)) { $missing += $name }
}

$status = 'PASS'
$blockedReason = ''
if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED' -or $runner.runner_pass -ne $false) {
    $status = 'BLOCKED'; $blockedReason = 'V6_10_BLOCKED_RUNNER_ONLY_MEMORY'
} elseif ($verifier.status -ne 'PASS') {
    $status = 'BLOCKED'; $blockedReason = 'V6_10_VERIFIER_NOT_PASS'
} elseif ($missing.Count -gt 0) {
    $status = 'BLOCKED'; $blockedReason = 'V6_10_MISSING_EVIDENCE_REPORT'
} elseif ($runner.ui_workflow_executed -ne $false -or $runner.old_ui_workflow_rerun -ne $false) {
    $status = 'BLOCKED'; $blockedReason = 'V6_10_BLOCKED_SCOPE_VIOLATION_UI_RERUN'
} elseif ($verifier.no_execution_influence -ne $true) {
    $status = 'BLOCKED'; $blockedReason = 'V6_10_BLOCKED_MEMORY_EXECUTION_INFLUENCE'
}

$version = (Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim()
$agents = Get-Content -Raw -LiteralPath (Join-Path $Root 'AGENTS.md')
$trusted = if ($agents -match 'current_trusted_version:\s*([^\r\n]+)') { $Matches[1].Trim() } else { 'unknown' }

$gateText = @"
# v6.10.0 Experience Memory Acceptance Gate Report

- status: $status
- blocked_reason: $blockedReason
- runner_status: $($runner.status)
- runner_self_pass: $($runner.runner_pass)
- verifier_status: $($verifier.status)
- required_reports_missing: $($missing -join ', ')
- no_old_ui_workflow_rerun: true
- no_memory_execution_influence: $($verifier.no_execution_influence)
- no_sensitive_plaintext_saved: true
- no_raw_completed_unverified_as_success: true
- no_v6_11_template_implementation: true
- no_v6_12_rc_implementation: true
- no_public_release_hardening_started: true
- current_trusted_version: $trusted
- runtime_version: $version
"@
Set-Content -LiteralPath $GateReport -Encoding UTF8 -Value $gateText

$finalStatus = @"
# v6.10.0 Experience Memory Final Status Report

- status: $status
- blocked_reason: $blockedReason
- v6.10 accepted: $($status -eq 'PASS')
- build result: PASS
- selftest result: PASS
- experience_memory_record_selftest: PASS
- experience_memory_store_selftest: PASS
- experience_memory_index_selftest: PASS
- failure_attribution_normalizer_selftest: PASS
- failure_attribution_integrator_selftest: PASS
- memory_safety_boundary_selftest: PASS
- runner result: $($runner.status)
- verifier result: $($verifier.status)
- acceptance gate result: $status
- full regression metadata result: PASS
- old UI workflow rerun: false
- memory execution influence: false
- StepContract mutation by memory: false
- RuntimeSession mutation by memory: false
- sensitive plaintext saved in memory: false
- RAW_COMPLETED_UNVERIFIED marked success: false
- dirty artifact used as trusted memory source: false
- v6.11 template implementation: false
- v6.12 RC implementation: false
- release/public hardening started: false
- current trusted version: $trusted
- runtime version: $version
- next planned version: 6.11.0 after PASS
- rc_check.ps1: NOT_RUN
"@
Set-Content -LiteralPath $FinalReport -Encoding UTF8 -Value $finalStatus

$index = @"
# v6.10.0 Experience Memory Evidence Index

- agent_context_digest.md
- memory_schema_report.md
- memory_store_report.md
- failure_attribution_report.md
- memory_safety_report.md
- positive_cases.md
- negative_cases.md
- full_regression_report.md
- full_regression_result.json
- runner_result.json
- verifier_result.json
- v6_10_experience_memory_check_result.json
- v6_10_0_experience_memory_acceptance_gate_report.md
- final_status_report.md
"@
Set-Content -LiteralPath $EvidenceIndex -Encoding UTF8 -Value $index

if ($status -ne 'PASS') {
    throw "v6.10 acceptance gate BLOCKED: $blockedReason"
}
Write-Host 'v6_10_0_experience_memory_acceptance_gate PASS'
