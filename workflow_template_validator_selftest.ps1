param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\workflow_template_validator'
$Candidate = Join-Path $OutDir 'candidate.json'
$Validated = Join-Path $OutDir 'validated.json'
$ValidationReport = Join-Path $OutDir 'validation_report.json'
$MissingSource = Join-Path $OutDir 'missing_source.json'
$UnsafeCoord = Join-Path $OutDir 'unsafe_coordinate.json'
$BackendBypass = Join-Path $OutDir 'backend_bypass.json'
$ReportPath = Join-Path $OutDir 'workflow_template_validator_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $Candidate | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'extract candidate failed' }
& $WinAgent workflow-template-validate --input $Candidate --output $Validated --report $ValidationReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'template validation should pass' }
$validated = Get-Content -Raw -LiteralPath $Validated | ConvertFrom-Json
if ($validated.template_status -ne 'validated') { throw 'template should promote to validated' }
if ($validated.validation_status -ne 'pass') { throw 'validation_status should pass' }
if ([string]::IsNullOrWhiteSpace($validated.validation_report_ref)) { throw 'validation_report_ref missing' }

$bad = Get-Content -Raw -LiteralPath $Candidate | ConvertFrom-Json
$bad.source_evidence_refs = @()
$bad | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MissingSource -Encoding UTF8
& $WinAgent workflow-template-validate --input $MissingSource --output (Join-Path $OutDir 'missing_source_rejected.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'missing source should fail validation' }

$bad = Get-Content -Raw -LiteralPath $Candidate | ConvertFrom-Json
$bad.step_contract_skeleton = [ordered]@{ runtime_action='direct_coordinate_click'; screen_x=10; screen_y=10; target='x=10,y=10' }
$bad | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $UnsafeCoord -Encoding UTF8
& $WinAgent workflow-template-validate --input $UnsafeCoord --output (Join-Path $OutDir 'unsafe_coordinate_rejected.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'unsafe coordinate template should fail validation' }

$bad = Get-Content -Raw -LiteralPath $Candidate | ConvertFrom-Json
$bad.step_contract_skeleton = [ordered]@{ runtime_action='browser_fill_form'; requested_action_backend='WebDriver CDP JavaScript DOM'; target='dom_selector:#x' }
$bad.workflow_type = 'browser_form'
$bad | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $BackendBypass -Encoding UTF8
& $WinAgent workflow-template-validate --input $BackendBypass --output (Join-Path $OutDir 'backend_bypass_rejected.json') *> $null
if ($LASTEXITCODE -eq 0) { throw 'backend bypass template should fail validation' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Template Validator Selftest

- status: PASS
- candidate_promoted_to_validated: PASS
- validation_status: pass
- validation_report_ref_present: true
- missing_source: FAIL_TEMPLATE_SOURCE_MISSING
- unsafe_coordinate: FAIL_TEMPLATE_UNSAFE_COORDINATE
- backend_bypass: FAIL_TEMPLATE_BACKEND_BYPASS
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_template_validator_selftest PASS'
