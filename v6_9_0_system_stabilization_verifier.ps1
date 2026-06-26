param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $Root 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_system_stabilization'
$VerifierResult = Join-Path $ArtifactRoot 'system_stabilization_verifier_result.json'
$VerifierReport = Join-Path $ArtifactRoot 'system_stabilization_verifier_report.md'
$RunnerResult = Join-Path $ArtifactRoot 'system_stabilization_runner_result.json'
$EvidenceReport = Join-Path $ArtifactRoot 'evidence_consolidation_report.json'
$SessionReport = Join-Path $ArtifactRoot 'runtime_session_lifecycle_report.json'
$WorkflowReport = Join-Path $ArtifactRoot 'workflow_system_boundary_report.json'
$SystemCheck = Join-Path $ArtifactRoot 'system_stabilization_check_result.json'
$V69Final = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow\final_status_report.md'
$V69Index = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow\evidence_index.md'
$V69Gate = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow\v6_9_0_acceptance_gate_report.md'

function Check($Name, [bool]$Ok, $Detail = '') {
    [pscustomobject]@{ name = $Name; ok = $Ok; detail = [string]$Detail }
}

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$checks = @()
$checks += Check 'runner_result_exists' (Test-Path -LiteralPath $RunnerResult) $RunnerResult
$checks += Check 'evidence_report_exists' (Test-Path -LiteralPath $EvidenceReport) $EvidenceReport
$checks += Check 'session_report_exists' (Test-Path -LiteralPath $SessionReport) $SessionReport
$checks += Check 'workflow_report_exists' (Test-Path -LiteralPath $WorkflowReport) $WorkflowReport
$checks += Check 'system_check_exists' (Test-Path -LiteralPath $SystemCheck) $SystemCheck
$checks += Check 'v6_9_final_exists' (Test-Path -LiteralPath $V69Final) $V69Final
$checks += Check 'v6_9_index_exists' (Test-Path -LiteralPath $V69Index) $V69Index
$checks += Check 'v6_9_gate_exists' (Test-Path -LiteralPath $V69Gate) $V69Gate

if (Test-Path -LiteralPath $RunnerResult) {
    $runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
    $checks += Check 'runner_pass' ($runner.status -eq 'PASS') $runner.status
    $checks += Check 'no_ui_workflow_rerun' ($runner.old_ui_workflow_rerun -eq $false -and $runner.ui_workflow_executed -eq $false) ''
    $checks += Check 'no_v6_10_feature' ($runner.v6_10_feature_implemented -eq $false) ''
}

if (Test-Path -LiteralPath $EvidenceReport) {
    $evidence = Get-Content -Raw -LiteralPath $EvidenceReport | ConvertFrom-Json
    $coreDelete = @($evidence.inventory | Where-Object { $_.artifact_type -in @('final_report','acceptance_gate_report','evidence_index') -and $_.safe_to_delete -eq $true })
    $checks += Check 'core_evidence_not_deletable' ($coreDelete.Count -eq 0) "count=$($coreDelete.Count)"
    $checks += Check 'runtime_sessions_classified' ([int]$evidence.runtime_session_count -ge 0) "count=$($evidence.runtime_session_count)"
    $checks += Check 'unreferenced_sessions_reported' ($null -ne $evidence.unreferenced_runtime_sessions) ''
    $rawAsPass = ($evidence.report_json -match 'RAW_COMPLETED_UNVERIFIED.+PASS')
    $checks += Check 'no_raw_completed_unverified_as_pass' (-not $rawAsPass) ''
}

if (Test-Path -LiteralPath $SessionReport) {
    $session = Get-Content -Raw -LiteralPath $SessionReport | ConvertFrom-Json
    $checks += Check 'session_report_pass' ($session.status -eq 'PASS') $session.status
    $checks += Check 'session_archive_plan_exists' ($null -ne $session.archive_plan) ''
}

if (Test-Path -LiteralPath $WorkflowReport) {
    $workflow = Get-Content -Raw -LiteralPath $WorkflowReport | ConvertFrom-Json
    $checks += Check 'workflow_report_pass' ($workflow.status -eq 'PASS') $workflow.status
    $checks += Check 'no_runner_only_workflow_detected' ($workflow.runner_only_workflow_detected -eq $false) ''
    $checks += Check 'no_bypass_detected' ($workflow.bypass_detected -eq $false) ''
}

if (Test-Path -LiteralPath $SystemCheck) {
    $system = Get-Content -Raw -LiteralPath $SystemCheck | ConvertFrom-Json
    $checks += Check 'system_check_pass' ($system.status -eq 'PASS') $system.status
}

$ok = @($checks | Where-Object { -not $_.ok }).Count -eq 0
$result = [pscustomobject]@{
    schema_version = '6.9.0.system_stabilization.verifier'
    status = if ($ok) { 'PASS' } else { 'BLOCKED' }
    checks = $checks
    ui_workflow_executed = $false
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $VerifierResult -Encoding UTF8

$lines = @('# v6.9.0 System Stabilization Verifier','')
$lines += "- status: $($result.status)"
foreach ($check in $checks) {
    $lines += "- $($check.name): ok=$($check.ok) detail=$($check.detail)"
}
$lines | Set-Content -LiteralPath $VerifierReport -Encoding UTF8

if ($ok) {
    'v6_9_0_system_stabilization_verifier PASS'
    exit 0
}
'v6_9_0_system_stabilization_verifier BLOCKED'
exit 1
