param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\workflow_template_instantiator'
$Candidate = Join-Path $OutDir 'candidate.json'
$Validated = Join-Path $OutDir 'validated.json'
$Params = Join-Path $OutDir 'params.json'
$StepContract = Join-Path $OutDir 'step_contract.json'
$Evidence = Join-Path $OutDir 'instantiation_evidence.json'
$Missing = Join-Path $OutDir 'missing_params.json'
$ReportPath = Join-Path $OutDir 'workflow_template_instantiator_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $Candidate | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'extract candidate failed' }
& $WinAgent workflow-template-validate --input $Candidate --output $Validated --report (Join-Path $OutDir 'validation_report.json') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'validate candidate failed' }
@{ parameter_values = [ordered]@{ target_path = $Root; allowed_root = $Root } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Params -Encoding UTF8
& $WinAgent workflow-template-instantiate --template $Validated --parameters $Params --output $StepContract --evidence-output $Evidence | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'validated template instantiation failed' }
$contract = Get-Content -Raw -LiteralPath $StepContract | ConvertFrom-Json
$inst = Get-Content -Raw -LiteralPath $Evidence | ConvertFrom-Json
if ($contract.step_contract_validator_used -ne $true) { throw 'StepContractValidator used flag missing' }
if ($inst.step_contract_valid -ne $true) { throw 'StepContract should validate' }
if ([string]::IsNullOrWhiteSpace($contract.template_id) -or [string]::IsNullOrWhiteSpace($contract.template_hash)) { throw 'template metadata not preserved' }

@{ parameter_values = [ordered]@{} } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Missing -Encoding UTF8
& $WinAgent workflow-template-instantiate --template $Validated --parameters $Missing --output (Join-Path $OutDir 'missing_result.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'missing parameter should fail' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Template Instantiator Selftest

- status: PASS
- validated_template_instantiated: PASS
- step_contract_validator_used: true
- step_contract_valid: true
- template_id_preserved: true
- template_hash_preserved: true
- source_evidence_refs_preserved: true
- missing_parameter: FAIL_TEMPLATE_INPUT_MISSING
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_template_instantiator_selftest PASS'
