param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\workflow_template_registry'
$RegistryRoot = Join-Path $OutDir 'registry'
$Evidence = Join-Path $OutDir 'accepted_evidence.md'
$Input = Join-Path $OutDir 'candidate.json'
$Output = Join-Path $OutDir 'registered_template.json'
$ReportJson = Join-Path $OutDir 'registry_report.json'
$ReportMd = Join-Path $OutDir 'registry_report.md'
$ReportPath = Join-Path $OutDir 'workflow_template_registry_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (Test-Path -LiteralPath $RegistryRoot) { Remove-Item -LiteralPath $RegistryRoot -Recurse -Force }
Set-Content -LiteralPath $Evidence -Encoding UTF8 -Value '# accepted evidence PASS'

$candidate = [ordered]@{
    template_name='Registry candidate'
    template_version='1.0.0'
    workflow_type='explorer'
    template_status='candidate'
    source_evidence_refs=@($Evidence)
    source_memory_refs=@()
    required_inputs=@('target_path')
    optional_inputs=@('allowed_root')
    parameter_schema=[ordered]@{ target_path='string'; allowed_root='string' }
    step_contract_skeleton=[ordered]@{ runtime_action='explorer_open_path'; target='{{target_path}}'; risk_level='LOW_RISK' }
    expected_context_schema=[ordered]@{ expected_process_pattern='explorer' }
    verification_hint_schema=[ordered]@{ verify_type='path_exists'; post_action_reobserve_required=$true }
    risk_level='LOW_RISK'
    confirmation_policy=[ordered]@{ confirmation_required=$false }
    stop_policy=[ordered]@{ stop_on_active_protection=$true; stop_on_credential_required=$true; stop_on_unverified_result=$true; stop_on_runtime_guard_failure=$true }
    recovery_policy=[ordered]@{ recovery_scope='none' }
    safety_constraints=[ordered]@{ no_direct_execution=$true; direct_execution_allowed=$false; step_contract_validator_required=$true; runtime_session_required=$true; verifier_required=$true; memory_execution_influence=$false }
    created_from_version='6.11.0'
    trusted_version='6.10.0'
}
$candidate | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Input -Encoding UTF8
& $WinAgent workflow-template-register --input $Input --registry-root $RegistryRoot --output $Output | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'workflow-template-register failed' }
& $WinAgent workflow-template-report --registry-root $RegistryRoot --output $ReportJson --markdown-output $ReportMd | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'workflow-template-report failed' }

$report = Get-Content -Raw -LiteralPath $ReportJson | ConvertFrom-Json
if ($report.candidate_count -ne 1) { throw "candidate_count mismatch: $($report.candidate_count)" }
if ($report.validated_count -ne 0) { throw 'validated_count should be 0 before validation' }
if (-not (Test-Path -LiteralPath (Join-Path $RegistryRoot 'template_registry_audit.jsonl'))) { throw 'registry audit missing' }
$registryText = Get-Content -Raw -LiteralPath (Join-Path $RegistryRoot 'template_registry.json')
if ($registryText -match 'password|verification_code|plaintext_body') { throw 'registry contains forbidden sensitive field' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Template Registry Selftest

- status: PASS
- candidate_count: $($report.candidate_count)
- validated_count: $($report.validated_count)
- rejected_count: $($report.rejected_count)
- deprecated_count: $($report.deprecated_count)
- audit_record_appended: true
- external_database_used: false
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_template_registry_selftest PASS'
