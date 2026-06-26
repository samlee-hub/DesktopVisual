param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\workflow_boundary'
$JsonReport = Join-Path $OutDir 'workflow_boundary_audit_report.json'
$ReportPath = Join-Path $OutDir 'workflow_boundary_auditor_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent workflow-boundary-audit --output $JsonReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "workflow-boundary-audit failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
foreach ($field in @('runner_only_workflow_logic','backend_bypass','step_contract_validator_bypass','runtime_session_bypass','evidence_pack_bypass','memory_execution_influence','template_execution_influence','batch_parallel_real_ui','developer_full_access_regression','public_release_hardening_started')) {
    if ($report.$field -ne $false) { throw "$field must be false" }
}

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Boundary Auditor Selftest

- status: PASS
- runner_only_workflow_logic: false
- backend_bypass: false
- validator_runtime_evidence_bypass: false
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_boundary_auditor_selftest PASS'
