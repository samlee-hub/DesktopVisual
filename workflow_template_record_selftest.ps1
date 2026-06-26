param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\workflow_template_record'
$EvidencePath = Join-Path $OutDir 'accepted_explorer_evidence.md'
$InputPath = Join-Path $OutDir 'candidate_template_input.json'
$OutputPath = Join-Path $OutDir 'candidate_template.json'
$SecondOutputPath = Join-Path $OutDir 'candidate_template_second.json'
$ReportPath = Join-Path $OutDir 'workflow_template_record_selftest_report.md'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Content -LiteralPath $EvidencePath -Encoding UTF8 -Value @'
# Accepted Explorer Evidence Fixture

- final_status: PASS
- evidence_status: accepted
- evidence_index: present
- final_status_report: present
- ui_workflow_executed: false
- fixture_only: true
'@

$templateInput = [ordered]@{
    template_name = 'Explorer accepted evidence structure'
    template_version = '1.0.0'
    workflow_type = 'explorer'
    template_status = 'candidate'
    source_evidence_refs = @($EvidencePath)
    source_memory_refs = @()
    required_inputs = @('target_path')
    optional_inputs = @('allowed_root')
    parameter_schema = [ordered]@{
        target_path = 'string'
        allowed_root = 'string'
    }
    step_contract_skeleton = [ordered]@{
        runtime_action = 'explorer_open_path'
        target = '{{target_path}}'
        risk_level = 'LOW_RISK'
    }
    expected_context_schema = [ordered]@{
        expected_process_pattern = 'explorer'
        expected_title_pattern = '{{target_path}}'
        required_markers = @()
    }
    verification_hint_schema = [ordered]@{
        verify_type = 'path_exists'
        post_action_reobserve_required = $true
    }
    risk_level = 'LOW_RISK'
    confirmation_policy = [ordered]@{ confirmation_required = $false }
    stop_policy = [ordered]@{
        stop_on_active_protection = $true
        stop_on_credential_required = $true
        stop_on_unverified_result = $true
        stop_on_runtime_guard_failure = $true
    }
    recovery_policy = [ordered]@{ recovery_scope = 'none' }
    safety_constraints = [ordered]@{
        no_direct_execution = $true
        step_contract_validator_required = $true
        runtime_session_required = $true
        verifier_required = $true
    }
    created_from_version = '6.11.0'
    trusted_version = '6.10.0'
}
$templateInput | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $InputPath -Encoding UTF8

& $WinAgent workflow-template-register --input $InputPath --output $OutputPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'workflow-template-register failed for candidate template' }
& $WinAgent workflow-template-register --input $InputPath --output $SecondOutputPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'workflow-template-register failed for deterministic hash check' }

$template = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
$template2 = Get-Content -Raw -LiteralPath $SecondOutputPath | ConvertFrom-Json
if ($template.template_status -ne 'candidate') { throw "template_status mismatch: $($template.template_status)" }
if ($template.workflow_type -ne 'explorer') { throw "workflow_type mismatch: $($template.workflow_type)" }
if ([string]::IsNullOrWhiteSpace($template.template_id)) { throw 'template_id missing' }
if ([string]::IsNullOrWhiteSpace($template.template_hash)) { throw 'template_hash missing' }
if ($template.template_hash -ne $template2.template_hash) { throw 'template_hash must be deterministic' }
if ($template.executable -ne $false) { throw 'candidate template must not be executable' }
if ($template.source_evidence_refs.Count -lt 1) { throw 'source_evidence_refs missing' }
if (-not (Test-Path -LiteralPath $template.source_evidence_refs[0])) { throw 'source evidence ref does not exist' }

$directRunOut = Join-Path $OutDir 'candidate_direct_execute.json'
& $WinAgent workflow-template-instantiate --template $OutputPath --parameters $InputPath --output $directRunOut *> $null
if ($LASTEXITCODE -eq 0) { throw 'candidate template direct instantiation must be blocked' }
$blockedText = Get-Content -Raw -LiteralPath $directRunOut
if ($blockedText -notmatch 'BLOCK_TEMPLATE_NOT_VALIDATED') { throw 'candidate direct execution must return BLOCK_TEMPLATE_NOT_VALIDATED' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Template Record Selftest

- status: PASS
- template_status: $($template.template_status)
- workflow_type: $($template.workflow_type)
- source_evidence_refs_present: true
- template_hash_deterministic: true
- candidate_executable: false
- candidate_direct_execution: BLOCK_TEMPLATE_NOT_VALIDATED
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_template_record_selftest PASS'
