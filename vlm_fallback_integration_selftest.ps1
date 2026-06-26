param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\vlm_fallback_integration_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies v1.0.3 VLM assist evidence within visible fallback discipline.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3_automatic_real_vlm_runtime_bridge'
$ReportPath = Join-Path $EvidenceRoot 'vlm_fallback_integration_selftest_report.md'
$CaseRoot = Join-Path $EvidenceRoot 'fallback_integration_cases'
New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null

$checks = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) { throw "${Name}: ${Detail}" }
}

function Invoke-WinAgentJson {
    param(
        [string[]]$Arguments,
        [switch]$AllowFailure
    )
    $output = & $WinAgent @Arguments
    $exitCode = $LASTEXITCODE
    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "winagent exited with ${exitCode}: $($output -join [Environment]::NewLine)"
    }
    $text = ($output | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'winagent produced no JSON output' }
    return $text | ConvertFrom-Json
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent

    $rawPath = Join-Path $CaseRoot 'vlm_raw_response.json'
    Set-Content -LiteralPath $rawPath -Value '{"ok":true}' -Encoding UTF8

    $visibleRecovery = Invoke-WinAgentJson @(
        'visible-operation-policy-check',
        '--operation-type', 'click',
        '--final-mode-used', 'visible_mouse_keyboard',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-result', 'succeeded',
        '--visible-attempt-count', '2',
        '--pre-action-checkpoint-present', 'true',
        '--bounded-recovery-attempted', 'true',
        '--post-recovery-observed', 'true',
        '--same-surface-after-recovery', 'true',
        '--vlm-assist-enabled', 'true',
        '--vlm-capability-status', 'VLM_AVAILABLE',
        '--vlm-session-id', 'fallback-visible',
        '--vlm-assist-attempted', 'true',
        '--vlm-assist-trigger-reason', 'uia_not_found',
        '--vlm-assist-stage', 'visible_attempt_1_recovery',
        '--vlm-provider', 'codex-cli',
        '--vlm-raw-response-path', $rawPath,
        '--vlm-candidate-accepted', 'true',
        '--vlm-action-executed', 'false',
        '--vlm-after-backend-attempted', 'false',
        '--fallback-stage-before-vlm', 'visible_attempt_1',
        '--fallback-stage-after-vlm', 'visible_attempt_2'
    )
    Add-Check 'visible recovery VLM attempted' ([bool]$visibleRecovery.data.vlm_assist_attempted) "stage=$($visibleRecovery.data.vlm_assist_stage)"
    Add-Check 'visible recovery stage correct' ($visibleRecovery.data.vlm_assist_stage -eq 'visible_attempt_1_recovery') $visibleRecovery.data.vlm_assist_stage
    Add-Check 'VLM candidate accepted evidence' ([bool]$visibleRecovery.data.vlm_candidate_accepted) "accepted=$($visibleRecovery.data.vlm_candidate_accepted)"
    Add-Check 'VLM did not execute action' (-not [bool]$visibleRecovery.data.vlm_action_executed) "vlm_action_executed=$($visibleRecovery.data.vlm_action_executed)"

    $unavailable = Invoke-WinAgentJson @(
        'visible-operation-policy-check',
        '--operation-type', 'click',
        '--final-mode-used', 'visible_mouse_keyboard',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-result', 'failed',
        '--visible-failure-reason', 'ocr_not_found',
        '--visible-attempt-count', '2',
        '--pre-action-checkpoint-present', 'true',
        '--bounded-recovery-attempted', 'true',
        '--post-recovery-observed', 'true',
        '--same-surface-after-recovery', 'true',
        '--vlm-assist-enabled', 'true',
        '--vlm-capability-status', 'VLM_UNAVAILABLE',
        '--vlm-session-id', 'fallback-unavailable',
        '--vlm-assist-attempted', 'false',
        '--vlm-candidate-accepted', 'false',
        '--vlm-candidate-rejected-reason', 'VLM_UNAVAILABLE'
    )
    Add-Check 'VLM unavailable remains Runtime-only' (($unavailable.data.vlm_capability_status -eq 'VLM_UNAVAILABLE') -and (-not [bool]$unavailable.data.vlm_candidate_accepted)) "status=$($unavailable.data.vlm_capability_status)"

    $keyboardVerify = Invoke-WinAgentJson @(
        'visible-ui-verify',
        '--global-final-frame', 'true',
        '--expected-output-visible', 'true',
        '--target-lock', 'true',
        '--operation-type', 'click',
        '--final-mode-used', 'keyboard_shortcut_fallback',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-result', 'failed',
        '--visible-failure-reason', 'target_not_found',
        '--visible-attempt-count', '2',
        '--pre-action-checkpoint-present', 'true',
        '--bounded-recovery-attempted', 'true',
        '--post-recovery-observed', 'true',
        '--same-surface-after-recovery', 'true',
        '--keyboard-shortcut-attempted', 'true',
        '--keyboard-shortcut-result', 'succeeded',
        '--vlm-assist-enabled', 'true',
        '--vlm-capability-status', 'VLM_AVAILABLE',
        '--vlm-session-id', 'keyboard-verify',
        '--vlm-assist-attempted', 'true',
        '--vlm-assist-stage', 'keyboard_state_verify',
        '--vlm-action-executed', 'false'
    )
    Add-Check 'keyboard VLM state verify allowed' ($keyboardVerify.data.vlm_assist_stage -eq 'keyboard_state_verify') $keyboardVerify.data.vlm_assist_stage
    Add-Check 'keyboard VLM did not generate action' (-not [bool]$keyboardVerify.data.vlm_action_executed) "vlm_action_executed=$($keyboardVerify.data.vlm_action_executed)"

    $backendFailed = Invoke-WinAgentJson @(
        'visible-operation-policy-check',
        '--operation-type', 'app_launch',
        '--final-mode-used', 'backend_fallback',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-result', 'failed',
        '--visible-failure-reason', 'target_not_found',
        '--visible-attempt-count', '2',
        '--pre-action-checkpoint-present', 'true',
        '--bounded-recovery-attempted', 'true',
        '--post-recovery-observed', 'true',
        '--same-surface-after-recovery', 'true',
        '--keyboard-shortcut-attempted', 'true',
        '--keyboard-shortcut-result', 'failed',
        '--keyboard-shortcut-failure-reason', 'no_visible_shortcut',
        '--backend-fallback-used', 'true',
        '--backend-fallback-kind', 'backend',
        '--backend-fallback-reason', 'visible_and_keyboard_failed',
        '--attempt-3-result', 'failed',
        '--vlm-after-backend-attempted', 'false'
    ) -AllowFailure
    Add-Check 'backend failure does not call VLM after backend' (-not [bool]$backendFailed.data.vlm_after_backend_attempted) "vlm_after_backend_attempted=$($backendFailed.data.vlm_after_backend_attempted)"

    $afterBackend = Invoke-WinAgentJson @(
        'visible-operation-policy-check',
        '--operation-type', 'click',
        '--final-mode-used', 'backend_fallback',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-result', 'failed',
        '--visible-failure-reason', 'target_not_found',
        '--visible-attempt-count', '2',
        '--pre-action-checkpoint-present', 'true',
        '--bounded-recovery-attempted', 'true',
        '--post-recovery-observed', 'true',
        '--same-surface-after-recovery', 'true',
        '--keyboard-shortcut-attempted', 'true',
        '--keyboard-shortcut-result', 'failed',
        '--keyboard-shortcut-failure-reason', 'no_shortcut',
        '--backend-fallback-used', 'true',
        '--backend-fallback-kind', 'backend',
        '--backend-fallback-reason', 'visible_and_keyboard_failed',
        '--vlm-after-backend-attempted', 'true'
    ) -AllowFailure
    Add-Check 'VLM after backend blocked' ($afterBackend.error.code -eq 'FAIL_VLM_AFTER_BACKEND_FORBIDDEN') "error=$($afterBackend.error.code)"

    $vlmDirectAction = Invoke-WinAgentJson @(
        'visible-operation-policy-check',
        '--operation-type', 'click',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-result', 'succeeded',
        '--vlm-action-executed', 'true'
    ) -AllowFailure
    Add-Check 'VLM direct action blocked' ($vlmDirectAction.error.code -eq 'FAIL_VLM_DIRECT_ACTION_FORBIDDEN') "error=$($vlmDirectAction.error.code)"

    $candidatePath = Join-Path $CaseRoot 'active_protection_candidate.json'
    $imagePath = Join-Path $CaseRoot 'active_protection.png'
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 100, 100
    $bitmap.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $parsedPath = Join-Path $CaseRoot 'active_protection_parsed.json'
    Set-Content -LiteralPath $parsedPath -Value '{}' -Encoding UTF8
    $candidate = [ordered]@{
        screenshot_id = 'shot-active'
        frame_id = 'frame-active'
        image_path = $imagePath
        provider = 'codex-cli'
        session_id = 'active-protection'
        prompt_hash = 'hash'
        raw_response_path = $rawPath
        parsed_json_path = $parsedPath
        requested_target = 'RUN_ALPHA_739'
        ok = $true
        target_found = $true
        target_label = 'RUN_ALPHA_739'
        target_type = 'button'
        confidence = 0.9
        bbox = [ordered]@{ x = 10; y = 10; w = 30; h = 20 }
        point = [ordered]@{ x = 20; y = 20 }
        coordinate_space = 'image_pixels'
        image_width = 100
        image_height = 100
        reason = 'target visible'
        visible_text = @('RUN_ALPHA_739')
        uncertainty = ''
        safety_flags = @('active_protection')
        requires_human_review = $false
    }
    $candidate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
    $activeProtection = Invoke-WinAgentJson @(
        'vlm-candidate-validate',
        '--candidate-json', $candidatePath,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--min-confidence', '0.65'
    )
    Add-Check 'active protection candidate rejected' ($activeProtection.candidate_rejected_reason -like 'safety_flag_active_protection*') "rejected=$($activeProtection.candidate_rejected_reason)"

    $planPath = Join-Path $CaseRoot 'visible_action_batch_vlm_plan.json'
    $batchOut = Join-Path $CaseRoot 'visible_action_batch_vlm_result.json'
    @{
        profile = 'vlm-fallback-integration'
        vlm_assist_enabled = $true
        vlm_capability_status = 'VLM_AVAILABLE'
        vlm_session_id = 'batch-vlm'
        vlm_assist_attempted = $true
        vlm_assist_stage = 'visible_attempt_1_recovery'
        vlm_candidate_accepted = $true
        vlm_action_executed = $false
        vlm_after_backend_attempted = $false
        steps = @(@{ type = 'foreground-preempt' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $batch = Invoke-WinAgentJson @('visible-action-batch', '--plan', $planPath, '--out', $batchOut)
    Add-Check 'visible action batch carries VLM evidence' ([bool]$batch.data.vlm_assist_attempted -and (-not [bool]$batch.data.vlm_action_executed)) "stage=$($batch.data.vlm_assist_stage)"

    $launch = Invoke-WinAgentJson @(
        'visible-app-launch',
        '--target', 'DesktopVisualNoSuchApp',
        '--target-title', 'DesktopVisualNoSuchApp',
        '--dry-run', 'true'
    )
    Add-Check 'visible-app-launch desktop-first still active' ([bool]$launch.data.runtime_visible_first_launch) 'runtime_visible_first_launch=true'
    Add-Check 'visible-app-launch did not use VLM normally' (-not [bool]$launch.data.vlm_assist_attempted) "vlm_assist_attempted=$($launch.data.vlm_assist_attempted)"
    Add-Check 'visible-app-launch did not use backend launch' (-not [bool]$launch.data.backend_launch_used) "backend_launch_used=$($launch.data.backend_launch_used)"

    $report = @(
        '# VLM Fallback Integration Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- raw_response_path: $rawPath",
        "- visible_action_batch_result: $batchOut",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_fallback_integration_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Fallback Integration Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_fallback_integration_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
