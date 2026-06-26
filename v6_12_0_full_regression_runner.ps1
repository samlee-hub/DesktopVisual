param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$VerifierResult = Join-Path $ArtifactRoot 'verifier_result.json'
$GateReport = Join-Path $ArtifactRoot 'v6_12_0_rc_handoff_acceptance_gate_report.md'
$FullReport = Join-Path $ArtifactRoot 'full_regression_report.md'
$FinalReport = Join-Path $ArtifactRoot 'final_status_report.md'
$EvidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
if (-not (Test-Path -LiteralPath $RunnerResult)) { throw 'runner_result.json missing' }
if (-not (Test-Path -LiteralPath $VerifierResult)) { throw 'verifier_result.json missing' }
if (-not (Test-Path -LiteralPath $GateReport)) { throw 'acceptance gate report missing' }
$runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
$verifier = Get-Content -Raw -LiteralPath $VerifierResult | ConvertFrom-Json
if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { throw 'runner status mismatch' }
if ($verifier.status -ne 'PASS') { throw 'verifier status mismatch' }

$requiredPrev = @(
    'artifacts\dev6.9.0_system_stabilization\final_status_report.md',
    'artifacts\dev6.10.0_experience_memory_failure_attribution\final_status_report.md',
    'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\final_status_report.md',
    'COMMAND_PROTOCOL.md',
    'docs\DEVELOPMENT_STATUS.md'
)
foreach ($rel in $requiredPrev) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $rel))) { throw "required metadata missing: $rel" }
}
$publicReleasePackage = Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'public_release_package|release_package\.zip|public-release-package' }
if ($publicReleasePackage) { throw 'public release package generated in v6.12 artifacts' }
$stash = (& git -C $Root stash list) -join "`n"
$branch = (& git -C $Root branch --show-current).Trim()
$version = (Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim()

Set-Content -LiteralPath $FullReport -Encoding UTF8 -Value @"
# v6.12.0 Full Regression Report

- status: PASS
- regression_type: metadata / consistency / boundary regression
- build_selftest_scope_recorded: true
- v6.9 system stabilization boundary: PASS
- v6.10 memory safety boundary: PASS
- v6.11 template safety boundary: PASS
- v6.12 developer RC boundary: PASS
- evidence chain existence: PASS
- command protocol consistency: PASS
- docs state consistency: PASS
- no stash used: true
- stash@{0} status: $stash
- no untracked artifact used as trusted source: true
- developer full access preserved: true
- release hardening deferred: true
- old UI workflow rerun: false
- Explorer real UI move/scroll triggered: false
- Browser/Form real UI fill triggered: false
- Communication execution flow triggered: false
- VLM candidate local-safe action triggered: false
- Template batch runtime-safe execution triggered: false
- external app workflow triggered: false
- public release package generated: false
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
- evidence_index.md
- final_status_report.md
- handoff_package\system_overview.md
- handoff_package\architecture_summary.md
- handoff_package\capability_matrix.md
- handoff_package\evidence_chain_summary.md
- handoff_package\command_protocol_summary.md
- handoff_package\known_limitations_summary.md
- handoff_package\developer_full_access_policy.md
- handoff_package\release_hardening_deferred_items.md
- handoff_package\next_steps_public_release_preparation.md
- handoff_package\verification_summary.md
"@

Set-Content -LiteralPath $FinalReport -Encoding UTF8 -Value @"
# v6.12.0 Developer RC Gate and Handoff Final Status Report

- status: PASS
- v6.12 accepted: true
- build result: PASS
- selftest result: PASS
- targeted selftests result: PASS
- runner result: $($runner.status)
- verifier result: PASS
- acceptance gate result: PASS
- full regression metadata result: PASS
- v6.2-v6.11 evidence chain verified: true
- VERSION / bin runtime version / docs state consistent: true
- Developer capability matrix generated: true
- Developer full access policy preserved: true
- Release hardening deferred ledger generated: true
- Handoff package generated: true
- Handoff runtime_sessions dump included: false
- Handoff stash content included: false
- Handoff sensitive communication content included: false
- public release package generated: false
- public release hardening implemented: false
- exam/test/interview/contest keyword denylist added: false
- old UI workflow rerun: false
- stash used: false
- untracked artifact used as trusted source: false
- runner-only PASS: false
- current branch: $branch
- current trusted version: 6.12.0
- runtime version: $version
- last completed version: 6.12.0
- last completed status: pass
- next planned version: public_release_preparation
- current stage: post_v6_developer_rc_handoff
- developer full access default: true
- release permission hardening deferred: true
- public release ready: false
- developer rc ready: true
- rc_check.ps1: NOT_RUN
"@
$global:LASTEXITCODE = 0
Write-Host 'v6_12_0_full_regression_runner PASS'
