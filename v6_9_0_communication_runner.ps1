param(
    [string]$Root = $PSScriptRoot,
    [string]$FixtureRoot = 'D:\testrepo\testwindow\communication_v6_9'
)

$ErrorActionPreference = 'Continue'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$RunDir = Join-Path $ArtifactRoot 'runner'
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
New-Item -ItemType Directory -Force -Path $FixtureRoot | Out-Null

'DV_COMMUNICATION_CONTEXT_MARKER email fixture context' | Set-Content -LiteralPath (Join-Path $FixtureRoot 'email_context.txt') -Encoding UTF8
'DV_COMMUNICATION_CONTEXT_MARKER explorer selected text' | Set-Content -LiteralPath (Join-Path $FixtureRoot 'explorer_context.txt') -Encoding UTF8
'DV_COMMUNICATION_CONTEXT_MARKER browser page summary' | Set-Content -LiteralPath (Join-Path $FixtureRoot 'browser_context.txt') -Encoding UTF8

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function New-Spec($Id, $Type, $ContextSource, $SubjectSuffix) {
    return @{
        workflow_id = $Id
        task_id = "$Id-task"
        type = $Type
        recipient = "$Id@example.invalid"
        subject = "v6.9 $SubjectSuffix"
        body = "DV_COMMUNICATION_CONTEXT_MARKER body for $SubjectSuffix"
        context_source = $ContextSource
        expected_context = @{
            expected_process_pattern = 'winagent.exe'
            expected_title_pattern = 'communication_v6_9'
            required_markers = @('DV_COMMUNICATION_CONTEXT_MARKER')
            wrong_page_patterns = @('wrong-recipient')
            active_protection_patterns = @('captcha','human verification')
            credential_required_patterns = @('password','verification code')
            foreground_required = $false
            window_binding_required = $false
        }
        verification_hint = @{
            verify_type = 'verify_communication_created'
            expected_marker = 'DV_COMMUNICATION_CONTEXT_MARKER'
            expected_text = "v6.9 $SubjectSuffix"
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

function Invoke-PositiveCase($Name, $Spec) {
    $caseDir = Join-Path $RunDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $input = Join-Path $caseDir 'workflow.json'
    $result = Join-Path $caseDir 'execution_result.json'
    $verify = Join-Path $caseDir 'verification.json'
    $stdout = Join-Path $caseDir 'stdout.json'
    $Spec | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $input -Encoding UTF8
    & $WinAgent run-communication-workflow --input $input --mode execute-local-safe --output $result --evidence-dir (Join-Path $caseDir 'evidence') *> $stdout
    $runExit = $LASTEXITCODE
    & $WinAgent verify-communication-workflow --result $result --output $verify *> (Join-Path $caseDir 'verify.stdout.json')
    $verifyExit = $LASTEXITCODE
    return [pscustomobject]@{ name = $Name; kind = 'positive'; exit_code = $runExit; verify_exit = $verifyExit; workflow = $input; result = $result; verify = $verify; evidence = Join-Path $caseDir 'evidence' }
}

function Base-NegativeResult($Name) {
    return @{
        schema_version = '6.9.0.communication_workflow.result'
        workflow_id = $Name
        task_id = "$Name-task"
        type = 'draft'
        execution_mode = 'execute_local_safe'
        final_status = 'PASS'
        workflow_executed = $true
        communication_workflow_executor_used = $true
        task_intent_used = $true
        agent_plan_draft_used = $true
        compiled_step_contract_used = $true
        step_contract_validator_used = $true
        compiled_plan_executor_used = $true
        runtime_session_used = $true
        context_bound = $true
        context_binding_verified = $true
        step_level_verification_complete = $true
        evidence_pack_created = $true
        runner_only_workflow_logic = $false
        external_api_used = $false
        send_attempted = $false
        fake_send_used = $false
        provider_sdk_used = $false
    }
}

function Invoke-NegativeVerifierCase($Name, $Mutate, $ExpectedCode) {
    $caseDir = Join-Path $RunDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $object = Base-NegativeResult $Name
    & $Mutate $object
    $result = Join-Path $caseDir 'execution_result.json'
    $verify = Join-Path $caseDir 'verification.json'
    $stdout = Join-Path $caseDir 'stdout.json'
    $object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $result -Encoding UTF8
    & $WinAgent verify-communication-workflow --result $result --output $verify *> $stdout
    return [pscustomobject]@{ name = $Name; kind = 'negative'; verify_exit = $LASTEXITCODE; expected_code = $ExpectedCode; result = $result; verify = $verify; stdout = $stdout }
}

$positive = @()
$positive += Invoke-PositiveCase 'case_01_draft_email_created_verified_evidence' (New-Spec 'case-01-draft-email' 'draft' (Join-Path $FixtureRoot 'email_context.txt') 'draft email created')
$positive += Invoke-PositiveCase 'case_02_message_created_from_explorer_context' (New-Spec 'case-02-message-explorer' 'message' 'Explorer' 'message from Explorer context')
$positive += Invoke-PositiveCase 'case_03_browser_context_draft_generation_no_send' (New-Spec 'case-03-browser-draft' 'draft' 'Browser' 'browser context draft no send')

$negative = @()
$negative += Invoke-NegativeVerifierCase 'negative_fake_send_fail' { param($o) $o.fake_send_used = $true } 'BLOCKED_FAKE_SEND'
$negative += Invoke-NegativeVerifierCase 'negative_missing_validator_fail' { param($o) $o.step_contract_validator_used = $false } 'BLOCKED_STEP_CONTRACT_VALIDATOR_BYPASSED'
$negative += Invoke-NegativeVerifierCase 'negative_external_api_usage_fail' { param($o) $o.external_api_used = $true } 'BLOCKED_EXTERNAL_COMMUNICATION_API_USED'
$negative += Invoke-NegativeVerifierCase 'negative_runner_only_execution_fail' { param($o) $o.runner_only_workflow_logic = $true } 'BLOCKED_RUNNER_ONLY_COMMUNICATION_WORKFLOW'
$negative += Invoke-NegativeVerifierCase 'negative_no_evidence_fail' { param($o) $o.evidence_pack_created = $false } 'BLOCKED_EVIDENCE_PACK_MISSING'

$runnerResult = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.runner'
    result = 'RAW_COMPLETED_UNVERIFIED'
    fixture_root = $FixtureRoot
    positive_cases = $positive
    negative_cases = $negative
}
$runnerResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'communication_runner_result.json') -Encoding UTF8

$positiveLines = @('# v6.9.0 Communication Positive Cases','')
foreach ($case in $positive) {
    $positiveLines += "- $($case.name): run_exit=$($case.exit_code) verify_exit=$($case.verify_exit) result=$($case.result)"
}
$positiveLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'positive_cases.md') -Encoding UTF8

$negativeLines = @('# v6.9.0 Communication Negative Cases','')
foreach ($case in $negative) {
    $negativeLines += "- $($case.name): verify_exit=$($case.verify_exit) expected=$($case.expected_code)"
}
$negativeLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'negative_cases.md') -Encoding UTF8

'v6_9_0_communication_runner RAW_COMPLETED_UNVERIFIED'
