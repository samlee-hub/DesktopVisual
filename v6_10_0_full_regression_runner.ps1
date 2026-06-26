param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution'
$ReportPath = Join-Path $ArtifactRoot 'full_regression_report.md'
$ResultPath = Join-Path $ArtifactRoot 'full_regression_result.json'
$BoundaryOut = Join-Path $ArtifactRoot 'full_regression_workflow_boundary.json'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$requiredPreviousEvidence = @(
    'artifacts\dev6.9.0_communication_workflow\evidence_index.md',
    'artifacts\dev6.9.0_communication_workflow\final_status_report.md',
    'artifacts\dev6.9.0_system_stabilization\evidence_index.md',
    'artifacts\dev6.9.0_system_stabilization\final_status_report.md',
    'artifacts\dev6.9.0_system_stabilization\system_stabilization_acceptance_gate_report.md'
)
$missing = @()
foreach ($rel in $requiredPreviousEvidence) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $rel))) { $missing += $rel }
}

$boundaryStatus = 'NOT_RUN'
$boundaryExit = 0
$boundaryOutput = & $WinAgent workflow-boundary-check --output $BoundaryOut 2>&1
$boundaryExit = $LASTEXITCODE
if ($boundaryExit -eq 0) { $boundaryStatus = 'PASS' } else { $boundaryStatus = 'FAIL' }

$status = if ($missing.Count -eq 0 -and $boundaryStatus -eq 'PASS') { 'PASS' } else { 'BLOCKED' }
$blockedReason = ''
if ($missing.Count -gt 0) { $blockedReason = 'MISSING_PREVIOUS_EVIDENCE' }
elseif ($boundaryStatus -ne 'PASS') { $blockedReason = 'WORKFLOW_BOUNDARY_METADATA_FAILED' }

$result = [ordered]@{
    schema_version = '6.10.0.full_regression_metadata'
    status = $status
    blocked_reason = $blockedReason
    previous_evidence_missing = $missing
    workflow_boundary_metadata_status = $boundaryStatus
    workflow_boundary_exit_code = $boundaryExit
    old_ui_workflow_rerun = $false
    explorer_real_ui_rerun = $false
    browser_form_real_ui_rerun = $false
    communication_execution_rerun = $false
    vlm_candidate_action_rerun = $false
    pycharm_qq_youtube_rerun = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$boundaryText = ($boundaryOutput | Out-String).TrimEnd()
$reportText = @(
    '# v6.10.0 Full Regression Metadata Report',
    '',
    "- status: $status",
    "- blocked_reason: $blockedReason",
    "- previous_evidence_missing: $($missing -join ', ')",
    "- workflow_boundary_metadata_status: $boundaryStatus",
    "- workflow_boundary_output: $BoundaryOut",
    '- old_ui_workflow_rerun: false',
    '- explorer_real_ui_rerun: false',
    '- browser_form_real_ui_rerun: false',
    '- communication_execution_rerun: false',
    '- vlm_candidate_action_rerun: false',
    '- pycharm_qq_youtube_rerun: false',
    '- metadata_only: true',
    '',
    '## Boundary Command Output',
    '',
    '    ' + ($boundaryText -replace "`r?`n", "`n    ")
) -join "`n"
Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value $reportText

if ($status -ne 'PASS') {
    throw "v6.10 full regression metadata BLOCKED: $blockedReason"
}
Write-Host 'v6_10_0_full_regression_runner PASS'
