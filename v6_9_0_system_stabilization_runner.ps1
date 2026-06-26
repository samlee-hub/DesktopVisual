param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $Root 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_system_stabilization'
$RunnerResult = Join-Path $ArtifactRoot 'system_stabilization_runner_result.json'
$RunnerReport = Join-Path $ArtifactRoot 'system_stabilization_runner_report.md'
$EvidenceReport = Join-Path $ArtifactRoot 'evidence_consolidation_report.json'
$SessionReport = Join-Path $ArtifactRoot 'runtime_session_lifecycle_report.json'
$WorkflowReport = Join-Path $ArtifactRoot 'workflow_system_boundary_report.json'
$SystemCheck = Join-Path $ArtifactRoot 'system_stabilization_check_result.json'

function Invoke-Checked($Name, [string[]]$WinArgs) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    [pscustomobject]@{
        name = $Name
        args = ($WinArgs -join ' ')
        exit_code = $exit
        ok = ($exit -eq 0)
        output = ($output | Out-String).Trim()
    }
}

if (!(Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run build.ps1 first." }
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$checks = @()
$checks += Invoke-Checked 'evidence_consolidate' @('evidence-consolidate','--root',(Join-Path $Root 'artifacts'),'--output',$EvidenceReport)
$checks += Invoke-Checked 'session_lifecycle_audit' @('session-lifecycle-audit','--root',(Join-Path $Root 'artifacts\runtime_sessions'),'--output',$SessionReport)
$checks += Invoke-Checked 'workflow_boundary_check' @('workflow-boundary-check','--output',$WorkflowReport)
$checks += Invoke-Checked 'system_stabilization_check' @('system-stabilization-check','--output',$SystemCheck)

$ok = @($checks | Where-Object { -not $_.ok }).Count -eq 0
$result = [pscustomobject]@{
    schema_version = '6.9.0.system_stabilization.runner'
    status = if ($ok) { 'PASS' } else { 'BLOCKED' }
    checks = $checks
    evidence_consolidation_report = $EvidenceReport
    runtime_session_lifecycle_report = $SessionReport
    workflow_system_boundary_report = $WorkflowReport
    system_stabilization_check_result = $SystemCheck
    ui_workflow_executed = $false
    old_ui_workflow_rerun = $false
    v6_10_feature_implemented = $false
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RunnerResult -Encoding UTF8

$lines = @('# v6.9.0 System Stabilization Runner','')
$lines += "- status: $($result.status)"
$lines += "- ui_workflow_executed: false"
$lines += "- old_ui_workflow_rerun: false"
$lines += "- v6_10_feature_implemented: false"
foreach ($check in $checks) {
    $lines += "- $($check.name): ok=$($check.ok) exit=$($check.exit_code)"
}
$lines | Set-Content -LiteralPath $RunnerReport -Encoding UTF8

if ($ok) {
    'v6_9_0_system_stabilization_runner PASS'
    exit 0
}
'v6_9_0_system_stabilization_runner BLOCKED'
exit 1
