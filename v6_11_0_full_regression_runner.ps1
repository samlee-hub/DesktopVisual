param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration'
$ReportPath = Join-Path $ArtifactRoot 'full_regression_report.md'
$ResultPath = Join-Path $ArtifactRoot 'full_regression_result.json'
$BoundaryOut = Join-Path $ArtifactRoot 'full_regression_workflow_boundary.json'
$TemplateBatchOut = Join-Path $ArtifactRoot 'full_regression_template_batch_check.json'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$requiredPreviousEvidence = @(
    'artifacts\dev6.7.0_explorer_agent_workflows_rerun\evidence_index.md',
    'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md',
    'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\evidence_index.md',
    'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\final_status_report.md',
    'artifacts\dev6.9.0_communication_workflow\evidence_index.md',
    'artifacts\dev6.9.0_communication_workflow\final_status_report.md',
    'artifacts\dev6.9.0_system_stabilization\evidence_index.md',
    'artifacts\dev6.9.0_system_stabilization\final_status_report.md',
    'artifacts\dev6.10.0_experience_memory_failure_attribution\evidence_index.md',
    'artifacts\dev6.10.0_experience_memory_failure_attribution\final_status_report.md'
)
$missing = @()
foreach ($rel in $requiredPreviousEvidence) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $rel))) { $missing += $rel }
}

$boundaryOutput = & $WinAgent workflow-boundary-check --output $BoundaryOut 2>&1
$boundaryExit = $LASTEXITCODE
$boundaryStatus = if ($boundaryExit -eq 0) { 'PASS' } else { 'FAIL' }

$runnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$batchPlan = ''
if (Test-Path -LiteralPath $runnerResult) {
    $runner = Get-Content -Raw -LiteralPath $runnerResult | ConvertFrom-Json
    $batchPlan = $runner.serial_mock_plan
}
$templateBatchOutput = & $WinAgent v6-11-template-batch-check --registry-root (Join-Path $ArtifactRoot 'runner\registry') --batch-plan $batchPlan --output $TemplateBatchOut 2>&1
$templateBatchExit = $LASTEXITCODE
$templateBatchStatus = if ($templateBatchExit -eq 0) { 'PASS' } else { 'FAIL' }

$stash = git stash list
$status = if ($missing.Count -eq 0 -and $boundaryStatus -eq 'PASS' -and $templateBatchStatus -eq 'PASS') { 'PASS' } else { 'BLOCKED' }
$blocked = ''
if ($missing.Count -gt 0) { $blocked = 'MISSING_PREVIOUS_EVIDENCE' }
elseif ($boundaryStatus -ne 'PASS') { $blocked = 'WORKFLOW_BOUNDARY_METADATA_FAILED' }
elseif ($templateBatchStatus -ne 'PASS') { $blocked = 'V6_11_TEMPLATE_BATCH_CHECK_FAILED' }

$result = [ordered]@{
    schema_version='6.11.0.full_regression_metadata'
    status=$status
    blocked_reason=$blocked
    previous_evidence_missing=$missing
    workflow_boundary_metadata_status=$boundaryStatus
    template_batch_check_status=$templateBatchStatus
    stash_recorded=($stash -join "`n")
    stash_used=$false
    untracked_artifact_used_as_trusted_source=$false
    old_ui_workflow_rerun=$false
    explorer_real_ui_rerun=$false
    browser_form_real_ui_rerun=$false
    communication_execution_rerun=$false
    vlm_candidate_action_rerun=$false
    pycharm_qq_youtube_rerun=$false
    metadata_only=$true
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# v6.11.0 Full Regression Metadata Report

- status: $status
- blocked_reason: $blocked
- previous_evidence_missing: $($missing -join ', ')
- workflow_boundary_metadata_status: $boundaryStatus
- template_batch_check_status: $templateBatchStatus
- stash_used: false
- untracked_artifact_used_as_trusted_source: false
- old_ui_workflow_rerun: false
- explorer_real_ui_rerun: false
- browser_form_real_ui_rerun: false
- communication_execution_rerun: false
- vlm_candidate_action_rerun: false
- pycharm_qq_youtube_rerun: false
- metadata_only: true

## Boundary Command Output

    $(($boundaryOutput | Out-String).TrimEnd() -replace "`r?`n", "`n    ")

## Template Batch Check Output

    $(($templateBatchOutput | Out-String).TrimEnd() -replace "`r?`n", "`n    ")
"@

if ($status -ne 'PASS') { throw "v6.11 full regression metadata BLOCKED: $blocked" }
$global:LASTEXITCODE = 0
Write-Host 'v6_11_0_full_regression_runner PASS'
