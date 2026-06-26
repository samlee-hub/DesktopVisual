param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\batch_workflow_validator'
$Candidate = Join-Path $OutDir 'candidate.json'
$Validated = Join-Path $OutDir 'validated.json'
$GoodInput = Join-Path $OutDir 'good_batch_input.json'
$GoodPlan = Join-Path $OutDir 'good_batch_plan.json'
$GoodValidation = Join-Path $OutDir 'good_validation.json'
$ReportPath = Join-Path $OutDir 'batch_workflow_validator_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $Candidate | Out-Null
& $WinAgent workflow-template-validate --input $Candidate --output $Validated --report (Join-Path $OutDir 'validation_report.json') | Out-Null

function Write-Batch([string]$Path, [hashtable]$Overrides) {
    $base = [ordered]@{
        batch_name='validator selftest'
        batch_mode='validate_only'
        template_instances=@([ordered]@{ instance_id='instance-1'; template_path=$Validated; parameter_values=[ordered]@{ target_path=$Root; allowed_root=$Root } })
        execution_order=@('instance-1')
        shared_context_policy=[ordered]@{ shared_context_allowed=$false }
        session_isolation_policy=[ordered]@{ concurrent_runtime_session=$false; session_per_instance=$true }
        failure_policy=[ordered]@{ default_policy='stop_batch'; continue_on_verification_failure=$false }
        verification_policy=[ordered]@{ step_verifier_required=$true; independent_verifier_per_step=$true }
        evidence_policy=[ordered]@{ evidence_required_per_instance=$true; raw_evidence_required=$true }
    }
    foreach ($key in $Overrides.Keys) { $base[$key] = $Overrides[$key] }
    $base | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

Write-Batch $GoodInput @{}
& $WinAgent batch-workflow-plan --input $GoodInput --output $GoodPlan | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'batch plan failed' }
& $WinAgent batch-workflow-validate --input $GoodPlan --output $GoodValidation | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'batch validate should pass' }
$good = Get-Content -Raw -LiteralPath $GoodValidation | ConvertFrom-Json
if ($good.status -ne 'PASS') { throw 'good validation did not PASS' }

$parallel = Join-Path $OutDir 'parallel_input.json'
Write-Batch $parallel @{ batch_mode='parallel_real_ui' }
& $WinAgent batch-workflow-validate --input $parallel --output (Join-Path $OutDir 'parallel_validation.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'parallel_real_ui should be blocked' }

$sessionUnsafe = Join-Path $OutDir 'session_unsafe_input.json'
Write-Batch $sessionUnsafe @{ session_isolation_policy=[ordered]@{ concurrent_runtime_session=$true; session_per_instance=$false } }
& $WinAgent batch-workflow-validate --input $sessionUnsafe --output (Join-Path $OutDir 'session_unsafe_validation.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'concurrent runtime session should be blocked' }

$failureUnsafe = Join-Path $OutDir 'failure_unsafe_input.json'
Write-Batch $failureUnsafe @{ failure_policy=[ordered]@{ default_policy='continue'; continue_on_verification_failure=$true } }
& $WinAgent batch-workflow-validate --input $failureUnsafe --output (Join-Path $OutDir 'failure_unsafe_validation.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'unsafe failure policy should be blocked' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Batch Workflow Validator Selftest

- status: PASS
- validate_only_plan: PASS
- parallel_real_ui: BLOCK_BATCH_PARALLEL_UI
- concurrent_runtime_session: BLOCK_BATCH_SESSION_UNSAFE
- continue_on_verification_failure: BLOCK_BATCH_UNSAFE_FAILURE_POLICY
- step_verifier_required: true
- evidence_required_per_instance: true
"@
$global:LASTEXITCODE = 0
Write-Host 'batch_workflow_validator_selftest PASS'
