param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\workflow_template_safety_boundary'
$Evidence = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
$ReportPath = Join-Path $OutDir 'workflow_template_safety_boundary_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$DirtyEvidence = Join-Path $OutDir 'dirty_untracked_source.md'
Set-Content -LiteralPath $DirtyEvidence -Encoding UTF8 -Value '# dirty untracked PASS'

function New-Template([string]$Name, [hashtable]$Overrides) {
    $path = Join-Path $OutDir "$Name.json"
    $base = [ordered]@{
        template_name=$Name; template_version='1.0.0'; workflow_type='explorer'; template_status='candidate'
        source_evidence_refs=@($Evidence); source_memory_refs=@()
        required_inputs=@('target_path'); optional_inputs=@()
        parameter_schema=[ordered]@{ target_path='string' }
        step_contract_skeleton=[ordered]@{ runtime_action='explorer_open_path'; target='{{target_path}}'; risk_level='LOW_RISK' }
        expected_context_schema=[ordered]@{ expected_process_pattern='explorer' }
        verification_hint_schema=[ordered]@{ verify_type='path_exists'; post_action_reobserve_required=$true }
        risk_level='LOW_RISK'
        confirmation_policy=[ordered]@{ confirmation_required=$false }
        stop_policy=[ordered]@{ stop_on_active_protection=$true; stop_on_credential_required=$true; stop_on_unverified_result=$true; stop_on_runtime_guard_failure=$true }
        recovery_policy=[ordered]@{ recovery_scope='none' }
        safety_constraints=[ordered]@{ no_direct_execution=$true; direct_execution_allowed=$false; step_contract_validator_required=$true; runtime_session_required=$true; verifier_required=$true; memory_execution_influence=$false }
        created_from_version='6.11.0'; trusted_version='6.10.0'
    }
    foreach ($key in $Overrides.Keys) { $base[$key] = $Overrides[$key] }
    $base | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-Case([string]$Name, [hashtable]$Overrides, [string]$Expected, [bool]$ShouldPass) {
    $input = New-Template $Name $Overrides
    $output = Join-Path $OutDir "$Name.result.json"
    & $WinAgent workflow-template-safety-check --input $input --output $output *> $null
    $exit = $LASTEXITCODE
    $json = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
    if ($ShouldPass) {
        if ($exit -ne 0 -or $json.status -ne 'PASS') { throw "$Name should pass" }
    } else {
        if ($exit -eq 0) { throw "$Name should fail" }
        if ($json.violations -notcontains $Expected) { throw "$Name expected $Expected, got $($json.violations -join ',')" }
    }
}

Invoke-Case 'safe_template' @{} '' $true
Invoke-Case 'missing_source' @{ source_evidence_refs=@() } 'FAIL_TEMPLATE_SOURCE_MISSING' $false
Invoke-Case 'dirty_source' @{ source_evidence_refs=@($DirtyEvidence) } 'FAIL_UNTRUSTED_TEMPLATE_SOURCE' $false
Invoke-Case 'unsafe_coordinate' @{ step_contract_skeleton=[ordered]@{ runtime_action='direct_coordinate_click'; screen_x=1; screen_y=2; target='x=1,y=2' } } 'FAIL_TEMPLATE_UNSAFE_COORDINATE' $false
Invoke-Case 'backend_bypass' @{ step_contract_skeleton=[ordered]@{ runtime_action='browser_fill_form'; requested_action_backend='DOM JS WebDriver CDP'; target='dom_selector:#x' } } 'FAIL_TEMPLATE_BACKEND_BYPASS' $false
Invoke-Case 'communication_plaintext' @{ workflow_type='communication'; redaction_applied=$false; step_contract_skeleton=[ordered]@{ runtime_action='communication_create_draft'; target='recipient@example.test'; message_body='plain text' } } 'FAIL_TEMPLATE_SENSITIVE_CONTENT' $false
Invoke-Case 'validator_bypass' @{ safety_constraints=[ordered]@{ no_direct_execution=$true; direct_execution_allowed=$false; step_contract_validator_required=$false; runtime_session_required=$true; verifier_required=$true; memory_execution_influence=$false } } 'FAIL_TEMPLATE_VALIDATOR_BYPASS' $false
Invoke-Case 'runtime_bypass' @{ safety_constraints=[ordered]@{ no_direct_execution=$true; direct_execution_allowed=$false; step_contract_validator_required=$true; runtime_session_required=$false; verifier_required=$true; memory_execution_influence=$false } } 'FAIL_TEMPLATE_RUNTIME_BYPASS' $false

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Template Safety Boundary Selftest

- status: PASS
- safe_template: PASS
- missing_source: FAIL_TEMPLATE_SOURCE_MISSING
- dirty_source: FAIL_UNTRUSTED_TEMPLATE_SOURCE
- unsafe_coordinate: FAIL_TEMPLATE_UNSAFE_COORDINATE
- backend_bypass: FAIL_TEMPLATE_BACKEND_BYPASS
- communication_plaintext: FAIL_TEMPLATE_SENSITIVE_CONTENT
- validator_bypass: FAIL_TEMPLATE_VALIDATOR_BYPASS
- runtime_bypass: FAIL_TEMPLATE_RUNTIME_BYPASS
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_template_safety_boundary_selftest PASS'
