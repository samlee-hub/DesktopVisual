param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.1_runtime_visible_first_launch_and_fallback_discipline'
$Report = Join-Path $OutDir 'visible_fallback_discipline_selftest_report.md'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { Fail $Message }
}

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        return $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output"
    }
}

function Expect-Failure($Result, [string]$Message) {
    Assert ($Result.ok -eq $false) $Message
}

function Expect-Success($Result, [string]$Message) {
    Assert ($Result.ok -eq $true) $Message
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build first." }

$results = [ordered]@{}

$results.shortcutAfterOneVisibleFailure = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'text_input',
    '--final-mode-used', 'keyboard_shortcut_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'click_failed',
    '--visible-attempt-count', '1',
    '--pre-action-checkpoint-present', 'true',
    '--bounded-recovery-attempted', 'false',
    '--post-recovery-observed', 'false'
) -Allowed @(1)
Expect-Failure $results.shortcutAfterOneVisibleFailure 'shortcut fallback after one visible failure must fail.'

$results.shortcutAfterTwoVisibleFailures = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'text_input',
    '--final-mode-used', 'keyboard_shortcut_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'click_failed_after_reobserve',
    '--visible-attempt-count', '2',
    '--pre-action-checkpoint-present', 'true',
    '--bounded-recovery-attempted', 'true',
    '--post-recovery-observed', 'true',
    '--same-surface-after-recovery', 'true'
)
Expect-Success $results.shortcutAfterTwoVisibleFailures 'shortcut fallback after two bounded visible failures should pass policy.'

$results.backendAfterOneVisibleFailure = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'app_launch',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_launch',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'visible and shortcut failed',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'target_not_found',
    '--visible-attempt-count', '1',
    '--keyboard-shortcut-attempted', 'true',
    '--keyboard-shortcut-result', 'failed',
    '--keyboard-shortcut-failure-reason', 'shortcut_failed',
    '--pre-action-checkpoint-present', 'true'
) -Allowed @(1)
Expect-Failure $results.backendAfterOneVisibleFailure 'backend fallback after one visible failure plus shortcut failure must fail.'

$results.backendAfterTwoVisibleFailures = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'app_launch',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_launch',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'visible and shortcut failed with bounded retry evidence',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'target_not_found_after_reobserve',
    '--visible-attempt-count', '2',
    '--keyboard-shortcut-attempted', 'true',
    '--keyboard-shortcut-result', 'failed',
    '--keyboard-shortcut-failure-reason', 'shortcut_failed',
    '--pre-action-checkpoint-present', 'true',
    '--bounded-recovery-attempted', 'true',
    '--post-recovery-observed', 'true',
    '--same-surface-after-recovery', 'true'
)
Expect-Success $results.backendAfterTwoVisibleFailures 'backend fallback after two bounded visible failures plus shortcut failure should pass policy.'

$results.surfaceImpossibleNoEvidence = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'text_input',
    '--final-mode-used', 'keyboard_shortcut_fallback',
    '--surface-impossible', 'true'
) -Allowed @(1)
Expect-Failure $results.surfaceImpossibleNoEvidence 'surfaceImpossible=true without reason/evidence must fail.'

$results.surfaceImpossibleStrictEvidence = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'text_input',
    '--final-mode-used', 'keyboard_shortcut_fallback',
    '--surface-impossible', 'true',
    '--surface-impossible-reason', 'operation_is_keyboard_only',
    '--surface-impossible-evidence-present', 'true'
)
Expect-Success $results.surfaceImpossibleStrictEvidence 'strict surface-impossible evidence should allow shortcut fallback.'

foreach ($badReason in @('target_not_found', 'uia_not_found', 'ocr_not_found', 'click_failed')) {
    $key = "badSurfaceImpossible_$badReason"
    $results[$key] = Invoke-Agent -WinArgs @(
        'visible-operation-policy-check',
        '--operation-type', 'text_input',
        '--final-mode-used', 'keyboard_shortcut_fallback',
        '--surface-impossible', 'true',
        '--surface-impossible-reason', $badReason,
        '--surface-impossible-evidence-present', 'true'
    ) -Allowed @(1)
    Expect-Failure $results[$key] "$badReason alone must not count as surface impossible."
}

$results.visibleUiVerifyPathViolation = Invoke-Agent -WinArgs @(
    'visible-ui-verify',
    '--global-final-frame', 'true',
    '--allow-global-desktop', 'true',
    '--expected-output-visible', 'true',
    '--raw-completed', 'false',
    '--window-only', 'false',
    '--operation-type', 'app_launch',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'backend result after insufficient visible evidence',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'target_not_found',
    '--visible-attempt-count', '1',
    '--keyboard-shortcut-attempted', 'true',
    '--keyboard-shortcut-result', 'failed',
    '--keyboard-shortcut-failure-reason', 'shortcut_failed',
    '--pre-action-checkpoint-present', 'true'
) -Allowed @(1)
Expect-Failure $results.visibleUiVerifyPathViolation 'visible-ui-verify must reject final success when path violates fallback discipline.'

$batchPlan = Join-Path $OutDir 'fallback_discipline_batch_violation.json'
$batchResult = Join-Path $OutDir 'fallback_discipline_batch_violation_result.json'
@'
{
  "steps": [
    {
      "type": "backend-show-desktop",
      "operation_id": "batch-one-visible-failure",
      "visible_mouse_keyboard_attempted": true,
      "attempt_1_result": "failed",
      "attempt_1_failure_reason": "click_failed",
      "visible_attempt_count": 1,
      "keyboard_shortcut_attempted": true,
      "attempt_2_result": "failed",
      "attempt_2_failure_reason": "shortcut_failed",
      "backend_fallback_reason": "shortcut failed after one visible failure",
      "pre_action_checkpoint_present": true
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $batchPlan
$results.visibleActionBatchPathViolation = Invoke-Agent -WinArgs @('visible-action-batch', '--plan', $batchPlan, '--out', $batchResult) -Allowed @(1)
Expect-Failure $results.visibleActionBatchPathViolation 'visible-action-batch must reject backend fallback after only one visible failure.'

$stepContract = Join-Path $OutDir 'fallback_discipline_step_contract_violation.json'
$stepContractResult = Join-Path $OutDir 'fallback_discipline_step_contract_violation_result.json'
@'
{
  "schema_version": "6.3.0.step_contract",
  "contracts": [
    {
      "contract_id": "contract-fallback-discipline",
      "task_id": "task-fallback-discipline",
      "plan_id": "plan-fallback-discipline",
      "step_id": "step-backend-focus-one-visible-failure",
      "step_index": 0,
      "step_type": "action",
      "runtime_action": "click",
      "target": "dry-run-target",
      "created_at": "2026-06-23T00:00:00Z",
      "compiler_version": "selftest",
      "risk_level": "LOW_RISK",
      "operation_type": "window_switch",
      "final_mode_used": "backend_fallback",
      "backend_fallback_used": true,
      "backend_fallback_kind": "backend_focus",
      "backend_fallback_reason": "shortcut failed after one visible failure",
      "visible_mouse_keyboard_attempted": true,
      "attempt_1_result": "failed",
      "attempt_1_failure_reason": "target_not_found",
      "visible_attempt_count": 1,
      "keyboard_shortcut_attempted": true,
      "attempt_2_result": "failed",
      "attempt_2_failure_reason": "shortcut_failed",
      "pre_action_checkpoint_present": true
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $stepContract
$results.stepContractPathViolation = Invoke-Agent -WinArgs @('step-contract-validate', '--input', $stepContract, '--result', $stepContractResult) -Allowed @(1)
Expect-Failure $results.stepContractPathViolation 'StepContractValidator must reject backend fallback after only one visible failure.'

$results.startMenuPolicyOneFailure = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'app_launch',
    '--attempt-1-mode', 'visible_start_button_click',
    '--final-mode-used', 'keyboard_shortcut_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'start_button_not_found',
    '--visible-attempt-count', '1',
    '--pre-action-checkpoint-present', 'true'
) -Allowed @(1)
Expect-Failure $results.startMenuPolicyOneFailure 'start-menu-visible-launch policy must not allow Win key fallback after one visible failure.'

$results.startMenuPrimitiveEvidence = Invoke-Agent -WinArgs @(
    'start-menu-visible-launch',
    '--app', 'DesktopVisualDisciplineDryRun',
    '--dry-run', 'true'
)
Expect-Success $results.startMenuPrimitiveEvidence 'start-menu-visible-launch dry-run should still pass.'
Assert ($results.startMenuPrimitiveEvidence.data.operation_priority.min_visible_attempts_before_shortcut -eq 2) 'start-menu-visible-launch must expose min visible attempts before shortcut.'

$results.visibleAppLaunchPolicyOneDesktopFailure = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'app_launch',
    '--final-mode-used', 'keyboard_shortcut_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'desktop_icon_locate_failed',
    '--visible-attempt-count', '1',
    '--pre-action-checkpoint-present', 'true'
) -Allowed @(1)
Expect-Failure $results.visibleAppLaunchPolicyOneDesktopFailure 'visible-app-launch must not enter Start Menu fallback after one desktop locate/click failure.'

$lines = @(
    '# visible fallback discipline selftest',
    '',
    '- result: PASS',
    '- shortcut after one visible failure rejected: PASS',
    '- shortcut after two bounded visible failures accepted: PASS',
    '- backend after one visible failure plus shortcut failure rejected: PASS',
    '- backend after two bounded visible failures plus shortcut failure accepted: PASS',
    '- surface impossible reason/evidence required: PASS',
    '- target_not_found/uia_not_found/ocr_not_found/click_failed not surface impossible: PASS',
    '- visible-ui-verify path-violating success rejected: PASS',
    '- visible-action-batch integration: PASS',
    '- StepContractValidator integration: PASS',
    '- start-menu-visible-launch discipline evidence: PASS',
    '- visible-app-launch desktop fallback policy discipline: PASS',
    '',
    '## Results',
    '',
    '```json',
    ($results | ConvertTo-Json -Depth 20),
    '```'
)
$lines | Set-Content -Encoding UTF8 -LiteralPath $Report
Write-Host 'PASS visible_fallback_discipline_selftest'
Write-Host "Report: $Report"
exit 0
