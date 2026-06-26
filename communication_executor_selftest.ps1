param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$ArtifactDir = Join-Path $ArtifactRoot 'selftest\executor'
$FixtureRoot = 'D:\testrepo\testwindow\communication_v6_9'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
New-Item -ItemType Directory -Force -Path $FixtureRoot | Out-Null
'DV_COMMUNICATION_CONTEXT_MARKER fixture context' | Set-Content -LiteralPath (Join-Path $FixtureRoot 'context.txt') -Encoding UTF8

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function New-Spec($Id, $Type, $ContextSource) {
    return @{
        workflow_id = $Id
        task_id = "$Id-task"
        type = $Type
        recipient = "$Id@example.invalid"
        subject = "Communication $Type $Id"
        body = "DV_COMMUNICATION_CONTEXT_MARKER body for $Id"
        context_source = $ContextSource
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
            expected_text = "Communication $Type $Id"
            expected_output_pattern = 'DV_COMMUNICATION_CONTEXT_MARKER'
            post_action_reobserve_required = $true
        }
        risk_level = 'REVERSIBLE_DRAFT'
        confirmation_policy = @{ confirmation_required = $false; confirmation_reason = ''; developer_full_access_allowed = $false; public_release_confirmation_required = $false; manual_handoff_required = $false }
        stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
        recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'communication_context_rebind'; recovery_target = 'same_context'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $false; stop_if_recovery_fails = $true }
        session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
        evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $false; latency_required = $true }
        fixture_root = $FixtureRoot
    }
}

function Run-Case($Name, $Spec) {
    $caseDir = Join-Path $ArtifactDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $input = Join-Path $caseDir 'workflow.json'
    $result = Join-Path $caseDir 'execution_result.json'
    $verify = Join-Path $caseDir 'verification.json'
    $evidence = Join-Path $caseDir 'evidence'
    $stdout = Join-Path $caseDir 'stdout.json'
    $Spec | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $input -Encoding UTF8
    & $WinAgent run-communication-workflow --input $input --mode execute-local-safe --output $result --evidence-dir $evidence *> $stdout
    if ($LASTEXITCODE -ne 0) {
        $text = Get-Content -Raw -LiteralPath $stdout
        throw "$Name run-communication-workflow failed. Output: $text"
    }
    $json = Get-Content -Raw -LiteralPath $result | ConvertFrom-Json
    foreach ($field in @('task_intent_used','agent_plan_draft_used','compiled_step_contract_used','step_contract_validator_used','compiled_plan_executor_used','runtime_session_used','workflow_executed','context_bound','step_level_verification_complete','evidence_pack_created')) {
        if ($json.$field -ne $true) { throw "$Name missing required execution flag $field" }
    }
    if ($json.final_status -ne 'PASS') { throw "$Name final_status=$($json.final_status)" }
    if ($json.external_api_used -or $json.fake_send_used -or $json.send_attempted) { throw "$Name used external API or send path" }
    if (-not (Test-Path -LiteralPath (Join-Path $evidence 'evidence_index.md'))) { throw "$Name evidence index missing" }
    & $WinAgent verify-communication-workflow --result $result --output $verify | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Name verify-communication-workflow failed" }
    return [pscustomobject]@{ name = $Name; result = $result; verify = $verify; evidence = $evidence }
}

$cases = @()
$cases += Run-Case 'case_01_draft_email_created' (New-Spec 'case-01-draft-email' 'draft' (Join-Path $FixtureRoot 'context.txt'))
$cases += Run-Case 'case_02_message_from_explorer_context' (New-Spec 'case-02-message-explorer' 'message' 'Explorer')
$cases += Run-Case 'case_03_browser_context_draft_no_send' (New-Spec 'case-03-browser-draft' 'draft' 'Browser')

$summary = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.executor_selftest'
    result = 'PASS'
    fixture_root = $FixtureRoot
    cases = $cases
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'communication_executor_selftest_result.json') -Encoding UTF8

$lines = @('# v6.9.0 Communication Executor Report','')
$lines += '- result: PASS'
foreach ($case in $cases) {
    $lines += "- $($case.name): result=$($case.result)"
}
$lines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'executor_report.md') -Encoding UTF8

'communication_executor_selftest PASS'
