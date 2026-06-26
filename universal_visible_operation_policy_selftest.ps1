param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_universal_visible_operation_policy'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) {
        throw "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    return $output | ConvertFrom-Json
}

function Assert($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}

$maxAttempts = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'visible_ui_operation',
    '--max-attempts-exceeded', 'true'
) -Allowed @(1)
Assert ($maxAttempts.ok -eq $false) 'operations beyond three stages must fail.'
Assert ($maxAttempts.error.code -eq 'V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION') 'max attempts failure code mismatch.'

$launchTooEarly = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'app_launch',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_launch',
    '--backend-fallback-used', 'true'
) -Allowed @(1)
Assert ($launchTooEarly.error.code -eq 'BLOCKED_BACKEND_LAUNCH_USED_BEFORE_VISIBLE_LAUNCH') 'backend launch first must be blocked.'

$focusTooEarly = Invoke-Agent -WinArgs @(
    'focus-window',
    '--title', 'dry-run-target'
) -Allowed @(1)
Assert ($focusTooEarly.ok -eq $false) 'focus-window first path must fail in visible UI context.'
Assert ($focusTooEarly.error.code -eq 'BLOCKED_BACKEND_FOCUS_USED_BEFORE_ALT_TAB_AND_VISIBLE_CLICK') 'focus-window block code mismatch.'

$batchPlan = Join-Path $OutDir 'universal_policy_batch_backend_show_desktop.json'
$batchResult = Join-Path $OutDir 'universal_policy_batch_backend_show_desktop_result.json'
@'
{
  "steps": [
    {
      "type": "backend-show-desktop",
      "operation_id": "batch-show-desktop-violation"
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $batchPlan
$batch = Invoke-Agent -WinArgs @('visible-action-batch', '--plan', $batchPlan, '--out', $batchResult) -Allowed @(1)
Assert ($batch.ok -eq $false) 'visible-action-batch must block backend show desktop as primary path.'
Assert ($batch.error.code -eq 'BLOCKED_BACKEND_SHOW_DESKTOP_USED_BEFORE_VISIBLE_AND_SHORTCUT') 'batch backend show desktop block code mismatch.'

$stepContract = Join-Path $OutDir 'universal_policy_step_contract_backend_focus.json'
$stepContractResult = Join-Path $OutDir 'universal_policy_step_contract_backend_focus_result.json'
@'
{
  "schema_version": "6.3.0.step_contract",
  "contracts": [
    {
      "contract_id": "contract-visible-policy",
      "task_id": "task-visible-policy",
      "plan_id": "plan-visible-policy",
      "step_id": "step-backend-focus",
      "step_index": 0,
      "step_type": "action",
      "runtime_action": "click",
      "target": "dry-run-target",
      "created_at": "2026-06-19T00:00:00Z",
      "compiler_version": "selftest",
      "risk_level": "LOW_RISK",
      "operation_type": "window_switch",
      "final_mode_used": "backend_fallback",
      "backend_fallback_used": true,
      "backend_fallback_kind": "backend_focus"
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $stepContract
$contract = Invoke-Agent -WinArgs @('step-contract-validate', '--input', $stepContract, '--result', $stepContractResult) -Allowed @(1)
Assert ($contract.ok -eq $false) 'StepContractValidator must block backend focus without Alt+Tab and visible click evidence.'
Assert ($contract.error.code -eq 'BLOCKED_BACKEND_FOCUS_USED_BEFORE_ALT_TAB_AND_VISIBLE_CLICK') 'StepContractValidator block code mismatch.'

$verification = Invoke-Agent -WinArgs @(
    'visible-ui-verify',
    '--global-final-frame', 'true',
    '--allow-global-desktop', 'true',
    '--expected-output-visible', 'true',
    '--raw-completed', 'false',
    '--window-only', 'false',
    '--operation-type', 'show_desktop',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'backend show desktop convenience'
) -Allowed @(1)
Assert ($verification.ok -eq $false) 'VisibleUIVerificationPolicy must reject successful state with show desktop path violation.'
Assert ($verification.error.code -eq 'BLOCKED_BACKEND_SHOW_DESKTOP_USED_BEFORE_VISIBLE_AND_SHORTCUT') 'VisibleUIVerificationPolicy show desktop block code mismatch.'
Assert ($verification.data.final_result -eq 'RESULT_INVALID_DUE_TO_VISIBLE_FIRST_VIOLATION') 'path violation must invalidate final result.'

$report = Join-Path $OutDir 'universal_visible_operation_policy_report.md'
@(
    '# Universal Visible Operation Policy Selftest',
    '',
    '- result: PASS',
    '- operations over three stages blocked: PASS',
    '- backend app launch primary path blocked: PASS',
    '- backend focus primary path blocked: PASS',
    '- visible-action-batch backend show desktop primary path blocked: PASS',
    '- StepContractValidator backend focus primary path blocked: PASS',
    '- VisibleUIVerificationPolicy rejects path-violating success: PASS',
    '- pycharm_test_run: false',
    '- wechat_test_prepared: false'
) | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host 'PASS universal_visible_operation_policy_selftest'
exit 0
