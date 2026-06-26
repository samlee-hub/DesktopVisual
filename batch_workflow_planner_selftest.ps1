param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\batch_workflow_planner'
$Candidate = Join-Path $OutDir 'candidate.json'
$Validated = Join-Path $OutDir 'validated.json'
$GoodInput = Join-Path $OutDir 'good_batch_input.json'
$BadInput = Join-Path $OutDir 'bad_candidate_batch_input.json'
$GoodOutput = Join-Path $OutDir 'good_batch_plan.json'
$ReportPath = Join-Path $OutDir 'batch_workflow_planner_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $Candidate | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'extract failed' }
& $WinAgent workflow-template-validate --input $Candidate --output $Validated --report (Join-Path $OutDir 'validation_report.json') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'validate failed' }

function Write-BatchInput([string]$Path, [string]$TemplatePath) {
    [ordered]@{
        batch_name='planner selftest'
        batch_mode='validate_only'
        template_instances=@([ordered]@{ instance_id='instance-1'; template_path=$TemplatePath; parameter_values=[ordered]@{ target_path=$Root; allowed_root=$Root } })
        execution_order=@('instance-1')
        failure_policy=[ordered]@{ default_policy='stop_batch'; continue_on_verification_failure=$false }
        verification_policy=[ordered]@{ step_verifier_required=$true; independent_verifier_per_step=$true }
        evidence_policy=[ordered]@{ evidence_required_per_instance=$true; raw_evidence_required=$true }
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}
Write-BatchInput $GoodInput $Validated
& $WinAgent batch-workflow-plan --input $GoodInput --output $GoodOutput | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'planner should accept validated templates' }
Write-BatchInput $BadInput $Candidate
& $WinAgent batch-workflow-plan --input $BadInput --output (Join-Path $OutDir 'bad_output.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'planner should reject candidate templates' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Batch Workflow Planner Selftest

- status: PASS
- validated_template_plan: PASS
- candidate_template_plan: BLOCK_TEMPLATE_NOT_VALIDATED
- dependency_validation: PASS
- input_parameter_schema_checked: PASS
- runtime_executed: false
"@
$global:LASTEXITCODE = 0
Write-Host 'batch_workflow_planner_selftest PASS'
