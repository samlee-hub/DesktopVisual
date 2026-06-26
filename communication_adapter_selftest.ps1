param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$ArtifactDir = Join-Path $ArtifactRoot 'selftest\adapter'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

$spec = @{
    workflow_id = 'adapter-draft'
    task_id = 'adapter-draft-task'
    type = 'draft'
    recipient = 'adapter@example.invalid'
    subject = 'Adapter communication draft'
    body = 'DV_COMMUNICATION_CONTEXT_MARKER adapter body'
    context_source = 'Fixture'
    expected_context = @{
        expected_process_pattern = 'winagent.exe'
        expected_title_pattern = 'communication_v6_9'
        required_markers = @('DV_COMMUNICATION_CONTEXT_MARKER')
        wrong_page_patterns = @('wrong-recipient')
        active_protection_patterns = @('captcha')
        credential_required_patterns = @('password')
        foreground_required = $false
        window_binding_required = $false
    }
    verification_hint = @{
        verify_type = 'verify_communication_created'
        expected_marker = 'DV_COMMUNICATION_CONTEXT_MARKER'
        expected_text = 'Adapter communication draft'
        expected_output_pattern = 'adapter body'
        post_action_reobserve_required = $true
    }
    risk_level = 'REVERSIBLE_DRAFT'
    confirmation_policy = @{ confirmation_required = $false; confirmation_reason = ''; developer_full_access_allowed = $false; public_release_confirmation_required = $false; manual_handoff_required = $false }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
    recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'communication_context_rebind'; recovery_target = 'same_context'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $false; stop_if_recovery_fails = $true }
    session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
    evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $false; latency_required = $true }
}

$input = Join-Path $ArtifactDir 'adapter.workflow.json'
$contractPath = Join-Path $ArtifactDir 'adapter.step_contract.json'
$stdout = Join-Path $ArtifactDir 'adapter.stdout.json'
$spec | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $input -Encoding UTF8

& $WinAgent compile-communication-workflow --input $input --output $contractPath *> $stdout
if ($LASTEXITCODE -ne 0) {
    $text = Get-Content -Raw -LiteralPath $stdout
    throw "compile-communication-workflow failed. Output: $text"
}

$contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
if ($contract.schema_version -ne '6.3.0.step_contract') { throw 'compiled output is not StepContract v6.3' }
if (-not $contract.task_intent_used) { throw 'TaskIntent stage was not recorded' }
if (-not $contract.agent_plan_draft_used) { throw 'AgentPlanDraft stage was not recorded' }
if (-not $contract.step_contract_validator_used) { throw 'StepContractValidator stage was not recorded' }
if ($contract.contracts.Count -ne 1) { throw "expected one StepContract step, got $($contract.contracts.Count)" }
$step = $contract.contracts[0]
if ($step.runtime_action -ne 'communication_create_draft') { throw "unexpected runtime_action: $($step.runtime_action)" }
if ($step.recipient -ne 'adapter@example.invalid') { throw 'recipient was not bound into StepContract' }
if ($step.requested_action_backend -ne 'runtime_session_local_create') { throw 'communication adapter did not force RuntimeSession local create backend' }
if ($step.send_allowed -ne $false -or $step.external_api_allowed -ne $false) { throw 'adapter allowed send or external API' }

$summary = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.adapter_selftest'
    result = 'PASS'
    task_intent_used = $contract.task_intent_used
    agent_plan_draft_used = $contract.agent_plan_draft_used
    runtime_action = $step.runtime_action
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'communication_adapter_selftest_result.json') -Encoding UTF8

$lines = @('# v6.9.0 Communication Adapter Report','')
$lines += '- result: PASS'
$lines += "- runtime_action: $($step.runtime_action)"
$lines += "- task_intent_used: $($contract.task_intent_used)"
$lines += "- agent_plan_draft_used: $($contract.agent_plan_draft_used)"
$lines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'adapter_report.md') -Encoding UTF8

'communication_adapter_selftest PASS'
