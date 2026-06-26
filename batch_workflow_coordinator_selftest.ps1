param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\batch_workflow_coordinator'
$Candidate = Join-Path $OutDir 'candidate.json'
$Validated = Join-Path $OutDir 'validated.json'
$Input = Join-Path $OutDir 'serial_mock_input.json'
$Plan = Join-Path $OutDir 'serial_mock_plan.json'
$Run = Join-Path $OutDir 'serial_mock_run.json'
$ReportPath = Join-Path $OutDir 'batch_workflow_coordinator_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $Candidate | Out-Null
& $WinAgent workflow-template-validate --input $Candidate --output $Validated --report (Join-Path $OutDir 'validation_report.json') | Out-Null

[ordered]@{
    batch_name='serial mock coordinator selftest'
    batch_mode='serial_execute_mock'
    template_instances=@([ordered]@{ instance_id='instance-1'; template_path=$Validated; parameter_values=[ordered]@{ target_path=$Root; allowed_root=$Root }; evidence_ref=(Join-Path $OutDir 'instance-1-evidence.json') })
    execution_order=@('instance-1')
    session_isolation_policy=[ordered]@{ concurrent_runtime_session=$false; session_per_instance=$true }
    failure_policy=[ordered]@{ default_policy='stop_batch'; continue_on_verification_failure=$false }
    verification_policy=[ordered]@{ step_verifier_required=$true; independent_verifier_per_step=$true }
    evidence_policy=[ordered]@{ evidence_required_per_instance=$true; raw_evidence_required=$true }
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Input -Encoding UTF8

& $WinAgent batch-workflow-plan --input $Input --output $Plan | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'batch plan failed' }
& $WinAgent batch-workflow-run --input $Plan --output $Run | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'batch workflow run failed' }
$run = Get-Content -Raw -LiteralPath $Run | ConvertFrom-Json
if ($run.status -ne 'RAW_COMPLETED_UNVERIFIED') { throw 'runner must emit RAW_COMPLETED_UNVERIFIED' }
if ($run.runner_pass -ne $false) { throw 'runner must not self-certify PASS' }
if ($run.parallel_real_ui -ne $false -or $run.concurrent_runtime_session -ne $false) { throw 'unsafe batch runtime policy' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Batch Workflow Coordinator Selftest

- status: PASS
- serial_execute_mock: RAW_COMPLETED_UNVERIFIED
- runner_pass: false
- step_verifier_independent: true
- evidence_required_per_instance: true
- parallel_real_ui: false
- concurrent_runtime_session: false
- runtime_executed: false
"@
$global:LASTEXITCODE = 0
Write-Host 'batch_workflow_coordinator_selftest PASS'
