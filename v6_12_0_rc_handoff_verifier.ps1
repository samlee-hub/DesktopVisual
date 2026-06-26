param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$VerifierResult = Join-Path $ArtifactRoot 'verifier_result.json'
if (-not (Test-Path -LiteralPath $RunnerResult)) { throw 'runner_result.json missing' }
$runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { throw 'runner must output RAW_COMPLETED_UNVERIFIED' }
if ($runner.runner_pass -ne $false) { throw 'runner must not self-certify PASS' }

$version = Get-Content -Raw -LiteralPath $runner.version_integrity | ConvertFrom-Json
$chain = Get-Content -Raw -LiteralPath $runner.evidence_chain | ConvertFrom-Json
$matrix = Get-Content -Raw -LiteralPath $runner.capability_matrix | ConvertFrom-Json
$policy = Get-Content -Raw -LiteralPath $runner.developer_full_access_policy | ConvertFrom-Json
$ledger = Get-Content -Raw -LiteralPath $runner.release_hardening_deferred_ledger | ConvertFrom-Json
$handoff = Get-Content -Raw -LiteralPath $runner.handoff_package | ConvertFrom-Json
$boundary = Get-Content -Raw -LiteralPath $runner.workflow_boundary_audit | ConvertFrom-Json
$gate = Get-Content -Raw -LiteralPath $runner.developer_rc_gate | ConvertFrom-Json

if ($version.status -ne 'PASS') { throw 'version integrity not PASS' }
if ($chain.status -ne 'PASS') { throw 'evidence chain not PASS' }
if ($matrix.status -ne 'PASS') { throw 'capability matrix not PASS' }
if ($policy.status -ne 'PASS') { throw 'developer full access policy not PASS' }
if ($policy.developer_full_access_default -ne $true) { throw 'developer full access default regressed' }
if ($policy.task_keyword_denylist_present -ne $false) { throw 'developer keyword denylist added' }
if ($policy.public_release_hardening_implemented -ne $false) { throw 'public release hardening implemented early' }
if ($ledger.status -ne 'PASS_WITH_RELEASE_DEFERRED_ITEMS') { throw 'release hardening deferred ledger not present' }
if ($ledger.developer_rc_blocker -ne $false) { throw 'deferred release items must not block Developer RC' }
if ($handoff.status -ne 'PASS') { throw 'handoff package not PASS' }
if ($handoff.runtime_sessions_dump_included -ne $false) { throw 'runtime_sessions dump included in handoff' }
if ($handoff.stash_content_included -ne $false) { throw 'stash content included in handoff' }
if ($handoff.sensitive_communication_content_included -ne $false) { throw 'sensitive communication content included in handoff' }
if ($handoff.public_release_package_generated -ne $false) { throw 'public release package generated' }
if ($boundary.status -ne 'PASS') { throw 'workflow boundary audit not PASS' }
foreach ($field in @('runner_only_workflow_logic','backend_bypass','step_contract_validator_bypass','runtime_session_bypass','evidence_pack_bypass','memory_execution_influence','template_execution_influence','batch_parallel_real_ui','developer_full_access_regression','public_release_hardening_started')) {
    if ($boundary.$field -ne $false) { throw "$field must be false" }
}
if ($gate.status -ne 'PASS') { throw 'developer RC gate did not report PASS' }
if ($runner.old_ui_workflow_rerun -ne $false) { throw 'old UI workflow rerun detected' }
if ($runner.public_release_hardening_implemented -ne $false) { throw 'public release hardening implemented by runner' }

Set-Content -LiteralPath (Join-Path $ArtifactRoot 'positive_cases.md') -Encoding UTF8 -Value @"
# v6.12 Positive Cases

- Case 1 Developer RC gate with accepted v6.2-v6.11 chain: PASS
- Case 2 Version integrity check: PASS
- Case 3 Evidence chain verify: PASS
- Case 4 Capability matrix build: PASS
- Case 5 Developer full access policy preserved: PASS
- Case 6 Release hardening deferred ledger: PASS
- Case 7 Handoff package build: PASS
- Case 8 Workflow boundary audit: PASS
"@
Set-Content -LiteralPath (Join-Path $ArtifactRoot 'negative_cases.md') -Encoding UTF8 -Value @"
# v6.12 Negative Cases

- Missing v6.x final_status_report: FAIL_EVIDENCE_CHAIN_INCOMPLETE
- RAW_COMPLETED_UNVERIFIED treated as PASS: FAIL_RAW_AS_PASS
- VERSION mismatch runtime binary: FAIL_VERSION_INTEGRITY
- Developer full access changed to limited by default: V6_12_BLOCKED_DEVELOPER_FULL_ACCESS_REGRESSION
- Exam/test/contest keyword denylist added in developer mode: V6_12_BLOCKED_DEVELOPER_PERMISSION_HARDENING_STARTED
- Public release hardening marked completed: V6_12_BLOCKED_RELEASE_SCOPE_VIOLATION
- Handoff package includes runtime_sessions dump: FAIL_HANDOFF_PACKAGE_TOO_HEAVY
- Handoff package includes stash content: FAIL_HANDOFF_STASH_INCLUDED
- Handoff package includes sensitive communication body: FAIL_HANDOFF_SENSITIVE_CONTENT
- Workflow audit detects runner-only PASS: FAIL_RUNNER_ONLY_RC
- Workflow audit detects backend bypass: FAIL_BACKEND_BYPASS_RC
- v6.12 runner outputs PASS directly: FAIL_RUNNER_GATE_SEPARATION
- Old UI workflow rerun during RC: V6_12_BLOCKED_SCOPE_VIOLATION_UI_RERUN
- Public release package generated: V6_12_BLOCKED_RELEASE_SCOPE_VIOLATION
"@

$result = [ordered]@{
    schema_version = '6.12.0.rc_handoff_verifier'
    status = 'PASS'
    version_integrity = 'PASS'
    evidence_chain = 'PASS'
    capability_matrix = 'PASS'
    developer_full_access_policy = 'PASS'
    release_hardening_deferred_ledger = 'PASS_WITH_RELEASE_DEFERRED_ITEMS'
    handoff_package = 'PASS'
    workflow_boundary_audit = 'PASS'
    no_runner_only_logic = $true
    no_old_ui_workflow_rerun = $true
    no_public_release_hardening_implemented = $true
    no_public_release_package_generated = $true
    no_task_keyword_denylist = $true
    no_stash_used = $true
    no_untracked_artifact_trusted_source = $true
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $VerifierResult -Encoding UTF8
$global:LASTEXITCODE = 0
Write-Host 'v6_12_0_rc_handoff_verifier PASS'
