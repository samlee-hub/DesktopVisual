param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_2_revalidation_selftest.ps1 [-Root <path>]'
    Write-Host 'Runs Phase 4 v5.2 Recovery/Escalation/SafeStop revalidation checks.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$PhaseDir = Join-Path $Root 'artifacts\dev5.8.7_revalidation\phase_04_v5.2'
$Report = Join-Path $PhaseDir 'v5_2_revalidation_selftest_report.md'

New-Item -ItemType Directory -Force -Path $PhaseDir | Out-Null

$Policy = Join-Path $Root 'tasks\recovery_policy\valid_standard_recovery_policy.json'
$InvalidPolicy = Join-Path $Root 'tasks\recovery_policy\invalid_unknown_strategy.json'
$DelayedButton = Join-Path $Root 'tasks\recovery_policy\delayed_button_not_ready.json'
$DelayedText = Join-Path $Root 'tasks\recovery_policy\delayed_text_missing.json'
$StaleCandidate = Join-Path $Root 'tasks\recovery_policy\stale_candidate_context.json'
$Semantic = Join-Path $Root 'tasks\recovery_policy\escalation_semantic_unresolved.json'
$Unknown = Join-Path $Root 'tasks\recovery_policy\escalation_unknown_scene.json'
$NoProvider = Join-Path $Root 'tasks\recovery_policy\escalation_no_provider.json'
$Blocked = Join-Path $Root 'tasks\recovery_policy\blocked_scene_captcha.json'

foreach ($jsonPath in @($Policy, $InvalidPolicy, $DelayedButton, $DelayedText, $StaleCandidate, $Semantic, $Unknown, $NoProvider, $Blocked)) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}

function Invoke-JsonCommand {
    param(
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit for $($Arguments -join ' '). output=$text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$outputs = New-Object System.Collections.Generic.List[string]

$policyResult = Invoke-JsonCommand @('recovery-policy-validate', '--file', $Policy)
if (-not $policyResult.Json.ok) { throw "RecoveryPolicy validation returned ok=false. output=$($policyResult.Text)" }
foreach ($strategy in @('re_observe','re_locate','wait_and_retry','invalidate_cache','use_profile_fallback','use_visual_provider','ask_user','escalate_to_agent','stop')) {
    if ($policyResult.Json.data.supported_strategies -notcontains $strategy) {
        throw "RecoveryPolicy missing strategy $strategy"
    }
}
if ($null -eq $policyResult.Json.data.retry_budget.max_attempts) { throw 'RetryBudget missing max_attempts.' }
if ($null -eq $policyResult.Json.data.retry_budget.max_total_recovery_ms) { throw 'RetryBudget missing max_total_recovery_ms.' }
$outputs.Add($policyResult.Text) | Out-Null

$invalidResult = Invoke-JsonCommand @('recovery-policy-validate', '--file', $InvalidPolicy) @(1)
if ($invalidResult.Json.ok -or $invalidResult.Json.error.code -ne 'RECOVERY_POLICY_SCHEMA_INVALID') {
    throw "Invalid policy was not rejected correctly. output=$($invalidResult.Text)"
}
$outputs.Add($invalidResult.Text) | Out-Null

function Assert-Recovery {
    param(
        [string]$Reason,
        [string]$Context,
        [string]$Strategy,
        [string]$NextAction
    )
    $result = Invoke-JsonCommand @('recovery-evaluate', '--policy', $Policy, '--failure-reason', $Reason, '--context', $Context, '--attempt', '1')
    if (-not $result.Json.ok) { throw "Recovery failed for $Reason. output=$($result.Text)" }
    if ($result.Json.data.strategy -ne $Strategy) { throw "Expected $Strategy for $Reason, got $($result.Json.data.strategy)" }
    if ($result.Json.data.next_action -ne $NextAction) { throw "Expected $NextAction for $Reason, got $($result.Json.data.next_action)" }
    if (-not $result.Json.data.audit_record.recovery_attempt_id) { throw "Missing recovery audit record for $Reason" }
    $outputs.Add($result.Text) | Out-Null
}

Assert-Recovery 'TARGET_NOT_READY' $DelayedButton 'wait_and_retry' 'wait'
Assert-Recovery 'TEXT_NOT_FOUND' $DelayedText 're_observe' 're_observe'
Assert-Recovery 'LOCATOR_NOT_FOUND' $DelayedText 're_locate' 're_locate'
Assert-Recovery 'STALE_CANDIDATE' $StaleCandidate 'invalidate_cache' 'invalidate_cache'

$exhausted = Invoke-JsonCommand @('recovery-evaluate', '--policy', $Policy, '--failure-reason', 'TARGET_NOT_READY', '--context', $DelayedButton, '--attempt', '3') @(1)
if ($exhausted.Json.error.code -ne 'RETRY_BUDGET_EXHAUSTED') { throw "Expected RETRY_BUDGET_EXHAUSTED. output=$($exhausted.Text)" }
$outputs.Add($exhausted.Text) | Out-Null

function Assert-Escalation {
    param(
        [string]$Reason,
        [string]$Context,
        [string]$RecommendedAction
    )
    $result = Invoke-JsonCommand @('escalation-request-create', '--reason', $Reason, '--task', 'local_form_fill_submit_mock', '--step', 'click_submit_and_verify', '--context', $Context)
    if (-not $result.Json.ok) { throw "Escalation failed for $Reason. output=$($result.Text)" }
    foreach ($field in @('reason','current_task','current_step','scene_state','candidates','screenshot_artifact','element_graph_artifact','risk_level','allowed_routes','recommended_action','fallback_if_provider_unavailable')) {
        if ($null -eq $result.Json.data.$field) { throw "EscalationRequest missing $field for $Reason" }
    }
    if ($result.Json.data.recommended_action -ne $RecommendedAction) { throw "Expected $RecommendedAction for $Reason, got $($result.Json.data.recommended_action)" }
    $outputs.Add($result.Text) | Out-Null
    return $result
}

$semanticEscalation = Assert-Escalation 'semantic_unresolved' $Semantic 'escalate_to_agent'
if ($semanticEscalation.Json.data.candidates.Count -lt 1) { throw 'semantic_unresolved escalation must include candidates array.' }

Assert-Escalation 'unknown_scene' $Unknown 'ask_user' | Out-Null
$noProviderEscalation = Assert-Escalation 'semantic_unresolved' $NoProvider 'ask_user'
if ($noProviderEscalation.Json.data.allowed_routes -contains 'escalate_to_agent') { throw 'No-provider fallback must not allow escalate_to_agent.' }

$blockedRecovery = Invoke-JsonCommand @('recovery-evaluate', '--policy', $Policy, '--failure-reason', 'SAFETY_DENIED', '--context', $Blocked, '--attempt', '1') @(1)
if ($blockedRecovery.Json.data.next_action -ne 'stop') { throw 'SAFETY_DENIED recovery must recommend stop.' }
$outputs.Add($blockedRecovery.Text) | Out-Null

$blockedEscalation = Assert-Escalation 'safety_denied' $Blocked 'stop'
if ($blockedEscalation.Json.data.allowed_routes -contains 'escalate_to_agent') { throw 'Blocked scene must not allow escalate_to_agent.' }
if ($blockedEscalation.Json.data.allowed_routes -contains 'ask_user') { throw 'Blocked scene must not allow ask_user as bypass.' }

$safeStop = Invoke-JsonCommand @('safe-stop-check', '--reason', 'captcha', '--context', $Blocked)
if (-not $safeStop.Json.data.safe_stop -or $safeStop.Json.data.recovery_allowed -or $safeStop.Json.data.escalation_allowed -or $safeStop.Json.data.recommended_action -ne 'stop') {
    throw "Blocked scene did not directly STOP. output=$($safeStop.Text)"
}
$outputs.Add($safeStop.Text) | Out-Null

$lines = @(
    '# Phase 4 v5.2 Revalidation Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- Scope: RecoveryPolicy, RecoveryAttempt, EscalationRequest, RetryBudget, SafeStop.',
    '- VLM/Agent provider calls: 0',
    '',
    '## Command Outputs',
    '',
    '```json'
)
$lines += $outputs
$lines += '```'
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: Phase 4 v5.2 revalidation selftest'
Write-Host "Report: $Report"
