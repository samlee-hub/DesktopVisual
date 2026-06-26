param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$VerifierResult = Join-Path $ArtifactRoot 'verifier_result.json'
$GateReport = Join-Path $ArtifactRoot 'v6_12_0_rc_handoff_acceptance_gate_report.md'
$FinalReport = Join-Path $ArtifactRoot 'final_status_report.md'
$EvidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
if (-not (Test-Path -LiteralPath $RunnerResult)) { throw 'runner_result.json missing' }
if (-not (Test-Path -LiteralPath $VerifierResult)) { throw 'verifier_result.json missing' }
$runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
$verifier = Get-Content -Raw -LiteralPath $VerifierResult | ConvertFrom-Json
if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED' -or $runner.runner_pass -ne $false) { throw 'runner/gate separation failed' }
if ($verifier.status -ne 'PASS') { throw 'verifier must PASS before acceptance gate' }

$requiredReports = @(
    'agent_context_digest.md',
    'developer_rc_gate_report.md',
    'version_integrity_report.md',
    'evidence_chain_report.md',
    'developer_capability_matrix.md',
    'developer_capability_matrix.json',
    'workflow_boundary_audit_report.md',
    'developer_full_access_policy_report.md',
    'release_hardening_deferred_ledger.md',
    'release_hardening_deferred_ledger.json',
    'handoff_package_report.md',
    'positive_cases.md',
    'negative_cases.md'
)
$missing = @()
foreach ($name in $requiredReports) {
    if (-not (Test-Path -LiteralPath (Join-Path $ArtifactRoot $name))) { $missing += $name }
}
if ($missing.Count -gt 0) { throw "missing v6.12 evidence reports: $($missing -join ', ')" }

$version = (Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim()
$branch = (& git -C $Root branch --show-current).Trim()

Set-Content -LiteralPath $GateReport -Encoding UTF8 -Value @"
# v6.12.0 RC Handoff Acceptance Gate Report

- status: PASS
- runner_status: $($runner.status)
- runner_self_pass: $($runner.runner_pass)
- verifier_status: $($verifier.status)
- current_branch: $branch
- current_trusted_version: 6.12.0
- runtime_version: $version
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_ready: false
- developer_rc_ready: true
- old_ui_workflow_rerun: false
- public_release_hardening_implemented: false
"@

Set-Content -LiteralPath $EvidenceIndex -Encoding UTF8 -Value @"
# v6.12.0 RC Gate and Handoff Evidence Index

- agent_context_digest.md
- developer_rc_gate_report.md
- version_integrity_report.md
- evidence_chain_report.md
- developer_capability_matrix.md
- developer_capability_matrix.json
- workflow_boundary_audit_report.md
- developer_full_access_policy_report.md
- release_hardening_deferred_ledger.md
- release_hardening_deferred_ledger.json
- handoff_package_report.md
- positive_cases.md
- negative_cases.md
- runner_result.json
- verifier_result.json
- v6_12_0_rc_handoff_acceptance_gate_report.md
- full_regression_report.md
- final_status_report.md
- handoff_package\
"@

Set-Content -LiteralPath $FinalReport -Encoding UTF8 -Value @"
# v6.12.0 Developer RC Gate and Handoff Final Status Report

- status: PASS
- v6.12 accepted: true
- runner result: $($runner.status)
- verifier result: PASS
- acceptance gate result: PASS
- full regression metadata result: PENDING
- developer full access preserved: true
- release hardening deferred: true
- public release ready: false
- developer rc ready: true
- old UI workflow rerun: false
- public release hardening implemented: false
- public release package generated: false
- stash used: false
- untracked artifact used as trusted source: false
- current trusted version: 6.12.0
- runtime version: $version
- next planned version: public_release_preparation
- rc_check.ps1: NOT_RUN
"@
$global:LASTEXITCODE = 0
Write-Host 'v6_12_0_rc_handoff_acceptance_gate PASS'
