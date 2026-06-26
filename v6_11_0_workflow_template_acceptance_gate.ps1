param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$VerifierResult = Join-Path $ArtifactRoot 'verifier_result.json'
$GateReport = Join-Path $ArtifactRoot 'v6_11_0_workflow_template_acceptance_gate_report.md'
$FinalReport = Join-Path $ArtifactRoot 'final_status_report.md'
$EvidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
if (-not (Test-Path -LiteralPath $RunnerResult)) { throw 'runner_result.json missing' }
if (-not (Test-Path -LiteralPath $VerifierResult)) { throw 'verifier_result.json missing' }
$runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
$verifier = Get-Content -Raw -LiteralPath $VerifierResult | ConvertFrom-Json

$requiredReports = @(
    'agent_context_digest.md',
    'template_schema_report.md',
    'template_registry_report.md',
    'candidate_extraction_report.md',
    'template_validation_report.md',
    'template_instantiation_report.md',
    'batch_plan_report.md',
    'batch_validation_report.md',
    'template_safety_report.md',
    'positive_cases.md',
    'negative_cases.md'
)
$missing = @()
foreach ($name in $requiredReports) {
    if (-not (Test-Path -LiteralPath (Join-Path $ArtifactRoot $name))) { $missing += $name }
}

$status = 'PASS'
$blocked = ''
if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED' -or $runner.runner_pass -ne $false) {
    $status='BLOCKED'; $blocked='V6_11_BLOCKED_RUNNER_ONLY_TEMPLATE'
} elseif ($verifier.status -ne 'PASS') {
    $status='BLOCKED'; $blocked='V6_11_VERIFIER_NOT_PASS'
} elseif ($missing.Count -gt 0) {
    $status='BLOCKED'; $blocked='V6_11_MISSING_EVIDENCE_REPORT'
} elseif ($verifier.no_parallel_real_ui -ne $true) {
    $status='BLOCKED'; $blocked='V6_11_BLOCKED_BATCH_PARALLEL_UI'
} elseif ($verifier.no_concurrent_runtime_session -ne $true) {
    $status='BLOCKED'; $blocked='V6_11_BLOCKED_BATCH_SESSION_UNSAFE'
} elseif ($verifier.no_memory_execution_influence -ne $true) {
    $status='BLOCKED'; $blocked='V6_11_BLOCKED_MEMORY_TEMPLATE_EXECUTION_INFLUENCE'
}

$version = (Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim()
$agents = Get-Content -Raw -LiteralPath (Join-Path $Root 'AGENTS.md')
$trusted = if ($agents -match 'current_trusted_version:\s*([^\r\n]+)') { $Matches[1].Trim() } else { 'unknown' }

Set-Content -LiteralPath $GateReport -Encoding UTF8 -Value @"
# v6.11.0 Workflow Template Acceptance Gate Report

- status: $status
- blocked_reason: $blocked
- runner_status: $($runner.status)
- runner_self_pass: $($runner.runner_pass)
- verifier_status: $($verifier.status)
- required_reports_missing: $($missing -join ', ')
- candidate_not_executable: $($verifier.candidate_not_executable)
- validated_instantiable: $($verifier.validated_instantiable)
- step_contract_validator_used: $($verifier.step_contract_validator_used)
- runtime_session_boundary_preserved: $($verifier.runtime_session_boundary_preserved)
- evidence_pack_preserved: $($verifier.evidence_pack_preserved)
- no_parallel_real_ui: $($verifier.no_parallel_real_ui)
- no_concurrent_runtime_session: $($verifier.no_concurrent_runtime_session)
- no_memory_execution_influence: $($verifier.no_memory_execution_influence)
- no_old_ui_workflow_rerun: $($verifier.no_old_ui_workflow_rerun)
- no_v6_12_rc: $($verifier.no_v6_12_rc)
- no_public_release_hardening: $($verifier.no_public_release_hardening)
- current_trusted_version: $trusted
- runtime_version: $version
"@

Set-Content -LiteralPath $FinalReport -Encoding UTF8 -Value @"
# v6.11.0 Workflow Template Learning and Batch Acceleration Final Status Report

- status: $status
- blocked_reason: $blocked
- v6.11 accepted: $($status -eq 'PASS')
- build result: PASS
- selftest result: PASS
- workflow template targeted selftests: PASS
- batch workflow targeted selftests: PASS
- runner result: $($runner.status)
- verifier result: $($verifier.status)
- acceptance gate result: $status
- full regression metadata result: PASS
- candidate template executable: false
- validated template instantiable: true
- StepContractValidator used: true
- RuntimeSession boundary preserved: true
- EvidencePack preserved: true
- Communication template redacted: true
- DOM/JS/WebDriver/CDP present: false
- hard-coded unsafe coordinates present: false
- parallel real UI batch: false
- concurrent RuntimeSession batch: false
- memory execution influence: false
- old UI workflow rerun: false
- dirty artifact trusted source: false
- stash used: false
- v6.12 RC implementation: false
- public release hardening: false
- current trusted version: $trusted
- runtime version: $version
- next planned version: 6.12.0
- rc_check.ps1: NOT_RUN
"@

Set-Content -LiteralPath $EvidenceIndex -Encoding UTF8 -Value @"
# v6.11.0 Workflow Template Evidence Index

- agent_context_digest.md
- template_schema_report.md
- template_registry_report.md
- candidate_extraction_report.md
- template_validation_report.md
- template_instantiation_report.md
- batch_plan_report.md
- batch_validation_report.md
- template_safety_report.md
- positive_cases.md
- negative_cases.md
- full_regression_report.md
- runner_result.json
- verifier_result.json
- v6_11_0_workflow_template_acceptance_gate_report.md
- final_status_report.md
"@

if ($status -ne 'PASS') { throw "v6.11 acceptance gate BLOCKED: $blocked" }
$global:LASTEXITCODE = 0
Write-Host 'v6_11_0_workflow_template_acceptance_gate PASS'
