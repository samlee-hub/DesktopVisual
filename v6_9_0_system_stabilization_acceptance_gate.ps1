param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'

$Resolver = Join-Path $Root 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_system_stabilization'
$GateResult = Join-Path $ArtifactRoot 'system_stabilization_acceptance_gate_result.json'
$GateReport = Join-Path $ArtifactRoot 'system_stabilization_acceptance_gate_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

function Invoke-GateCommand($Name, $Command) {
    $log = Join-Path $ArtifactRoot ("gate_" + ($Name -replace '[^a-zA-Z0-9_.-]', '_') + ".log")
    Push-Location $Root
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $Command *> $log
    $exit = $LASTEXITCODE
    Pop-Location
    [pscustomobject]@{ name = $Name; command = $Command; exit_code = $exit; ok = ($exit -eq 0); log = $log }
}

$checks = @()
$checks += Invoke-GateCommand 'build' '.\build.ps1'
$checks += Invoke-GateCommand 'selftest' '.\selftest.ps1'
$checks += Invoke-GateCommand 'runtime_evidence_consolidator_selftest' '.\runtime_evidence_consolidator_selftest.ps1'
$checks += Invoke-GateCommand 'session_lifecycle_manager_selftest' '.\session_lifecycle_manager_selftest.ps1'
$checks += Invoke-GateCommand 'workflow_system_boundary_selftest' '.\workflow_system_boundary_selftest.ps1'
$checks += Invoke-GateCommand 'system_stabilization_runner' '.\v6_9_0_system_stabilization_runner.ps1'
$checks += Invoke-GateCommand 'system_stabilization_verifier' '.\v6_9_0_system_stabilization_verifier.ps1'

$SystemCheckPath = Join-Path $ArtifactRoot 'system_stabilization_check_result.json'
$systemStatus = 'MISSING'
if (Test-Path -LiteralPath $SystemCheckPath) {
    try { $systemStatus = (Get-Content -Raw -LiteralPath $SystemCheckPath | ConvertFrom-Json).status } catch { $systemStatus = 'INVALID_JSON' }
}
$checks += [pscustomobject]@{ name = 'system_stabilization_check_result'; command = 'static_read'; exit_code = if ($systemStatus -eq 'PASS') { 0 } else { 1 }; ok = ($systemStatus -eq 'PASS'); log = $SystemCheckPath }

$ok = @($checks | Where-Object { -not $_.ok }).Count -eq 0
$gate = [pscustomobject]@{
    schema_version = '6.9.0.system_stabilization.acceptance_gate'
    gate_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    checks = $checks
    no_ui_workflow_rerun = $true
    no_v6_10_feature_implementation = $true
    trusted_version_advanced = $false
    raw_completed_unverified_as_pass = $false
    rc_check_status = 'NOT_RUN'
}
$gate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $GateResult -Encoding UTF8

$lines = @('# v6.9.0 System Stabilization Acceptance Gate','')
$lines += "- gate_ok: $ok"
$lines += "- result: $($gate.result)"
$lines += "- no_ui_workflow_rerun: true"
$lines += "- no_v6_10_feature_implementation: true"
$lines += "- trusted_version_advanced: false"
$lines += "- rc_check_status: NOT_RUN"
foreach ($check in $checks) {
    $lines += "- $($check.name): ok=$($check.ok) exit=$($check.exit_code) log=$($check.log)"
}
$lines | Set-Content -LiteralPath $GateReport -Encoding UTF8

if ($ok) {
    'v6_9_0_system_stabilization_acceptance_gate PASS'
    exit 0
}
'v6_9_0_system_stabilization_acceptance_gate BLOCKED'
exit 1
