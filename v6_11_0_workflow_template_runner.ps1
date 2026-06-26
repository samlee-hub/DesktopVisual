param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration'
$RunnerRoot = Join-Path $ArtifactRoot 'runner'
$RegistryRoot = Join-Path $RunnerRoot 'registry'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
New-Item -ItemType Directory -Force -Path $RunnerRoot | Out-Null
if (Test-Path -LiteralPath $RegistryRoot) { Remove-Item -LiteralPath $RegistryRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $RegistryRoot | Out-Null

function Invoke-Checked([scriptblock]$Block, [string]$Name) {
    & $Block | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

$sources = [ordered]@{
    explorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
    browser = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\final_status_report.md'
    communication = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow\final_status_report.md'
}

$explorerCandidate = Join-Path $RunnerRoot 'case1_explorer_candidate.json'
$explorerValidated = Join-Path $RunnerRoot 'case2_explorer_validated.json'
$explorerValidationReport = Join-Path $RunnerRoot 'case2_explorer_validation_report.json'
$params = Join-Path $RunnerRoot 'case3_explorer_params.json'
$stepContract = Join-Path $RunnerRoot 'case3_explorer_step_contract.json'
$instEvidence = Join-Path $RunnerRoot 'case3_explorer_instantiation_evidence.json'
$browserCandidate = Join-Path $RunnerRoot 'case4_browser_candidate.json'
$browserValidated = Join-Path $RunnerRoot 'case4_browser_validated.json'
$communicationCandidate = Join-Path $RunnerRoot 'case5_communication_candidate.json'
$communicationValidated = Join-Path $RunnerRoot 'case5_communication_validated.json'

Invoke-Checked { & $WinAgent workflow-template-extract --source $sources.explorer --workflow-type explorer --output $explorerCandidate } 'case1 extract explorer'
Invoke-Checked { & $WinAgent workflow-template-register --input $explorerCandidate --registry-root $RegistryRoot --output (Join-Path $RunnerRoot 'case1_registered.json') } 'case1 register explorer candidate'
Invoke-Checked { & $WinAgent workflow-template-validate --input $explorerCandidate --registry-root $RegistryRoot --output $explorerValidated --report $explorerValidationReport } 'case2 validate explorer'
@{ parameter_values = [ordered]@{ target_path = $Root; allowed_root = $Root } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $params -Encoding UTF8
Invoke-Checked { & $WinAgent workflow-template-instantiate --template $explorerValidated --parameters $params --output $stepContract --evidence-output $instEvidence } 'case3 instantiate explorer'

Invoke-Checked { & $WinAgent workflow-template-extract --source $sources.browser --workflow-type browser_form --output $browserCandidate } 'case4 extract browser'
Invoke-Checked { & $WinAgent workflow-template-validate --input $browserCandidate --registry-root $RegistryRoot --output $browserValidated --report (Join-Path $RunnerRoot 'case4_browser_validation_report.json') } 'case4 validate browser'

Invoke-Checked { & $WinAgent workflow-template-extract --source $sources.communication --workflow-type communication --output $communicationCandidate } 'case5 extract communication'
Invoke-Checked { & $WinAgent workflow-template-validate --input $communicationCandidate --registry-root $RegistryRoot --output $communicationValidated --report (Join-Path $RunnerRoot 'case5_communication_validation_report.json') } 'case5 validate communication'

$compileInput = Join-Path $RunnerRoot 'case6_batch_compile_input.json'
$compilePlan = Join-Path $RunnerRoot 'case6_batch_compile_plan.json'
[ordered]@{
    batch_name='v6.11 compile only batch'
    batch_mode='compile_only'
    template_instances=@([ordered]@{ instance_id='explorer-1'; template_path=$explorerValidated; parameter_values=[ordered]@{ target_path=$Root; allowed_root=$Root }; evidence_ref=(Join-Path $RunnerRoot 'case6_instance_evidence.json') })
    execution_order=@('explorer-1')
    session_isolation_policy=[ordered]@{ concurrent_runtime_session=$false; session_per_instance=$true }
    failure_policy=[ordered]@{ default_policy='stop_batch'; continue_on_verification_failure=$false }
    verification_policy=[ordered]@{ step_verifier_required=$true; independent_verifier_per_step=$true }
    evidence_policy=[ordered]@{ evidence_required_per_instance=$true; raw_evidence_required=$true }
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $compileInput -Encoding UTF8
Invoke-Checked { & $WinAgent batch-workflow-plan --input $compileInput --output $compilePlan } 'case6 batch compile_only plan'

$validateInput = Join-Path $RunnerRoot 'case7_batch_validate_input.json'
$validatePlan = Join-Path $RunnerRoot 'case7_batch_validate_plan.json'
$validateReport = Join-Path $RunnerRoot 'case7_batch_validate_report.json'
(Get-Content -Raw -LiteralPath $compileInput | ConvertFrom-Json) | ForEach-Object { $_.batch_mode = 'validate_only'; $_ } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $validateInput -Encoding UTF8
Invoke-Checked { & $WinAgent batch-workflow-plan --input $validateInput --output $validatePlan } 'case7 batch validate plan'
Invoke-Checked { & $WinAgent batch-workflow-validate --input $validatePlan --output $validateReport } 'case7 batch validate'

$mockInput = Join-Path $RunnerRoot 'case8_serial_mock_input.json'
$mockPlan = Join-Path $RunnerRoot 'case8_serial_mock_plan.json'
$mockRun = Join-Path $RunnerRoot 'case8_serial_mock_run.json'
(Get-Content -Raw -LiteralPath $compileInput | ConvertFrom-Json) | ForEach-Object { $_.batch_mode = 'serial_execute_mock'; $_ } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $mockInput -Encoding UTF8
Invoke-Checked { & $WinAgent batch-workflow-plan --input $mockInput --output $mockPlan } 'case8 serial mock plan'
Invoke-Checked { & $WinAgent batch-workflow-run --input $mockPlan --output $mockRun } 'case8 serial mock run'

$registryReport = Join-Path $RunnerRoot 'registry_report.json'
Invoke-Checked { & $WinAgent workflow-template-report --registry-root $RegistryRoot --output $registryReport --markdown-output (Join-Path $RunnerRoot 'registry_report.md') } 'registry report'

$result = [ordered]@{
    schema_version = '6.11.0.workflow_template_runner'
    status = 'RAW_COMPLETED_UNVERIFIED'
    runner_pass = $false
    registry_root = $RegistryRoot
    explorer_candidate = $explorerCandidate
    explorer_validated = $explorerValidated
    explorer_step_contract = $stepContract
    explorer_instantiation_evidence = $instEvidence
    browser_candidate = $browserCandidate
    browser_validated = $browserValidated
    communication_candidate = $communicationCandidate
    communication_validated = $communicationValidated
    batch_compile_plan = $compilePlan
    batch_validate_plan = $validatePlan
    batch_validate_report = $validateReport
    serial_mock_plan = $mockPlan
    serial_mock_run = $mockRun
    registry_report = $registryReport
    ui_workflow_executed = $false
    old_ui_workflow_rerun = $false
    parallel_real_ui = $false
    concurrent_runtime_session = $false
    memory_execution_influence = $false
    dirty_artifact_used_as_trusted_source = $false
    v6_12_rc_implemented = $false
    public_release_hardening_started = $false
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $RunnerResult -Encoding UTF8
$global:LASTEXITCODE = 0
Write-Host 'RAW_COMPLETED_UNVERIFIED'
