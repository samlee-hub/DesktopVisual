param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\batch_workflow_plan'
$Candidate = Join-Path $OutDir 'candidate.json'
$Validated = Join-Path $OutDir 'validated.json'
$PlanInput = Join-Path $OutDir 'batch_input.json'
$PlanOutput = Join-Path $OutDir 'batch_plan.json'
$ReportPath = Join-Path $OutDir 'batch_workflow_plan_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $Candidate | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'extract failed' }
& $WinAgent workflow-template-validate --input $Candidate --output $Validated --report (Join-Path $OutDir 'validation_report.json') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'validate failed' }

$input = [ordered]@{
    batch_name='compile only plan selftest'
    batch_mode='compile_only'
    template_instances=@(
        [ordered]@{
            instance_id='instance-1'
            template_path=$Validated
            parameter_values=[ordered]@{ target_path=$Root; allowed_root=$Root }
            evidence_ref=(Join-Path $OutDir 'instance-1-evidence.json')
        }
    )
    execution_order=@('instance-1')
    dependency_graph=@()
    shared_context_policy=[ordered]@{ shared_context_allowed=$false }
    session_isolation_policy=[ordered]@{ concurrent_runtime_session=$false; session_per_instance=$true }
    failure_policy=[ordered]@{ default_policy='stop_batch'; continue_on_verification_failure=$false }
    verification_policy=[ordered]@{ step_verifier_required=$true; independent_verifier_per_step=$true }
    evidence_policy=[ordered]@{ evidence_required_per_instance=$true; raw_evidence_required=$true }
    created_from_version='6.11.0'
    trusted_version='6.10.0'
}
$input | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PlanInput -Encoding UTF8
& $WinAgent batch-workflow-plan --input $PlanInput --output $PlanOutput | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'batch-workflow-plan failed' }
$plan = Get-Content -Raw -LiteralPath $PlanOutput | ConvertFrom-Json
if ($plan.batch_mode -ne 'compile_only') { throw 'batch_mode should be compile_only' }
if ([string]::IsNullOrWhiteSpace($plan.batch_hash)) { throw 'batch_hash missing' }
if ($plan.parallel_real_ui -ne $false) { throw 'parallel_real_ui must be false' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Batch Workflow Plan Selftest

- status: PASS
- batch_mode: $($plan.batch_mode)
- batch_hash_present: true
- template_instances: $($plan.template_instances.Count)
- parallel_real_ui: false
- runtime_executed: false
"@
$global:LASTEXITCODE = 0
Write-Host 'batch_workflow_plan_selftest PASS'
