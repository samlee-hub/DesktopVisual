param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
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

$clipboardTooEarly = Invoke-Agent -WinArgs @(
    'visible-text-input',
    '--text', 'hello',
    '--input-kind', 'form',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true',
    '--input-method', 'clipboard_paste',
    '--allow-clipboard', 'true',
    '--clipboard-fallback-reason', 'convenience'
) -Allowed @(1)
Assert ($clipboardTooEarly.ok -eq $false) 'clipboard fallback before visible/shortcut failures must fail.'
Assert ($clipboardTooEarly.error.code -eq 'FAIL_CLIPBOARD_PRIORITY_VIOLATION') 'clipboard priority failure code mismatch.'

$clipboardSetPrimitive = Invoke-Agent -WinArgs @(
    'clipboard-set',
    '--text', 'hello'
)
Assert ($clipboardSetPrimitive.ok -eq $true) 'direct clipboard-set primitive should pass.'
Assert ($clipboardSetPrimitive.data.operation_priority.operation_type -eq 'clipboard_primitive') 'direct clipboard-set must not be classified as text_input fallback.'

$clipboardAfterFailures = Invoke-Agent -WinArgs @(
    'visible-text-input',
    '--text', 'hello',
    '--input-kind', 'form',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true',
    '--input-method', 'clipboard_paste',
    '--allow-clipboard', 'true',
    '--clipboard-fallback-reason', 'real keyboard and shortcut input both failed',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'real_keyboard_input_failed',
    '--visible-attempt-count', '2',
    '--pre-action-checkpoint-present', 'true',
    '--bounded-recovery-attempted', 'true',
    '--post-recovery-observed', 'true',
    '--same-surface-after-recovery', 'true',
    '--keyboard-shortcut-attempted', 'true',
    '--keyboard-shortcut-result', 'failed',
    '--keyboard-shortcut-failure-reason', 'shortcut_input_failed'
)
Assert ($clipboardAfterFailures.ok -eq $true) 'clipboard fallback with first two failures should pass policy.'
Assert ($clipboardAfterFailures.data.operation_priority.visible_mouse_keyboard_attempted -eq $true) 'visible attempt evidence missing.'
Assert ($clipboardAfterFailures.data.operation_priority.keyboard_shortcut_attempted -eq $true) 'shortcut attempt evidence missing.'
Assert ($clipboardAfterFailures.data.operation_priority.backend_fallback_used -eq $true) 'clipboard fallback must be treated as third-stage fallback.'
Assert ($clipboardAfterFailures.data.operation_priority.final_mode_used -eq 'backend_fallback') 'clipboard final mode should be backend_fallback.'

$backendTooEarly = Invoke-Agent -WinArgs @(
    'visible-ui-verify',
    '--global-final-frame', 'true',
    '--target-lock', 'true',
    '--expected-output-visible', 'true',
    '--raw-completed', 'false',
    '--window-only', 'false',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'convenience'
) -Allowed @(1)
Assert ($backendTooEarly.ok -eq $false) 'backend fallback before visible/shortcut failures must fail.'
Assert ($backendTooEarly.error.code -eq 'FAIL_BACKEND_PRIORITY_VIOLATION') 'backend priority failure code mismatch.'
Assert ($backendTooEarly.data.final_result -eq 'RESULT_INVALID_DUE_TO_VISIBLE_FIRST_VIOLATION') 'path violation must invalidate final result.'

$backendAfterFailures = Invoke-Agent -WinArgs @(
    'visible-ui-verify',
    '--global-final-frame', 'true',
    '--target-lock', 'true',
    '--expected-output-visible', 'true',
    '--raw-completed', 'false',
    '--window-only', 'false',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'visible and shortcut attempts failed',
    '--visible-mouse-keyboard-attempted', 'true',
    '--visible-attempt-result', 'failed',
    '--visible-failure-reason', 'visible_ui_unusable',
    '--visible-attempt-count', '2',
    '--pre-action-checkpoint-present', 'true',
    '--bounded-recovery-attempted', 'true',
    '--post-recovery-observed', 'true',
    '--same-surface-after-recovery', 'true',
    '--keyboard-shortcut-attempted', 'true',
    '--keyboard-shortcut-result', 'failed',
    '--keyboard-shortcut-failure-reason', 'shortcut_unusable'
)
Assert ($backendAfterFailures.ok -eq $true) 'backend fallback after first two failures should pass policy.'
Assert ($backendAfterFailures.data.operation_priority.final_mode_used -eq 'backend_fallback') 'backend final mode missing.'

$launchTooEarly = Invoke-Agent -WinArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', 'Z:\desktopvisual_missing_app.exe',
    '--target-title', 'dry-run-target',
    '--process', 'missing.exe'
) -Allowed @(1)
Assert ($launchTooEarly.ok -eq $false) 'backend launch before visible/shortcut failures must fail.'
Assert ($launchTooEarly.error.code -eq 'BLOCKED_BACKEND_LAUNCH_USED_BEFORE_VISIBLE_LAUNCH') 'backend launch priority failure code mismatch.'
Assert ($launchTooEarly.data.operation_priority.priority_violation -eq $true) 'launch priority violation evidence missing.'

$focusTooEarly = Invoke-Agent -WinArgs @(
    'focus-window',
    '--title', 'dry-run-target'
) -Allowed @(1)
Assert ($focusTooEarly.ok -eq $false) 'backend focus before visible/shortcut failures must fail.'
Assert ($focusTooEarly.error.code -eq 'BLOCKED_BACKEND_FOCUS_USED_BEFORE_ALT_TAB_AND_VISIBLE_CLICK') 'backend focus priority failure code mismatch.'

$browserNavTooEarly = Invoke-Agent -WinArgs @(
    'browser-nav',
    '--url', 'about:blank',
    '--target-title', 'dry-run-target',
    '--process', 'missing.exe'
) -Allowed @(1)
Assert ($browserNavTooEarly.ok -eq $false) 'backend browser navigation before visible/shortcut failures must fail.'
Assert ($browserNavTooEarly.error.code -eq 'BLOCKED_BACKEND_BROWSER_NAV_USED_BEFORE_VISIBLE_NAV') 'backend browser navigation priority failure code mismatch.'

$maxAttempts = Invoke-Agent -WinArgs @(
    'visible-ui-verify',
    '--global-final-frame', 'true',
    '--target-lock', 'true',
    '--expected-output-visible', 'true',
    '--raw-completed', 'false',
    '--window-only', 'false',
    '--max-attempts-exceeded', 'true'
) -Allowed @(1)
Assert ($maxAttempts.ok -eq $false) 'max attempts exceeded must fail.'
Assert ($maxAttempts.error.code -eq 'V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION') 'max attempts failure code mismatch.'

foreach ($visibleCommand in @(
    'taskbar-icon-locate',
    'taskbar-icon-click',
    'desktop-icon-locate',
    'desktop-icon-double-click',
    'start-menu-visible-launch',
    'visible-page-navigation'
)) {
    $visible = Invoke-Agent -WinArgs @($visibleCommand, '--target', 'dry-run-target', '--dry-run', 'true')
    Assert ($visible.ok -eq $true) "$visibleCommand dry-run policy should pass."
    Assert ($visible.data.runtime_visible_first_primitive -eq $true) "$visibleCommand must be a Runtime visible-first primitive."
    Assert ($visible.data.backend_fallback_used -eq $false) "$visibleCommand must not use backend fallback by default."
    Assert ($visible.data.operation_priority.visible_mouse_keyboard_attempted -eq $true) "$visibleCommand must record visible attempt evidence."
    Assert ($visible.data.operation_priority.final_mode_used -eq 'visible_mouse_keyboard') "$visibleCommand final mode should be visible_mouse_keyboard."
}

$visibleShowDesktop = Invoke-Agent -WinArgs @('visible-show-desktop', '--dry-run', 'true')
Assert ($visibleShowDesktop.ok -eq $true) 'visible-show-desktop dry-run policy should pass.'
Assert ($visibleShowDesktop.data.operation_type -eq 'show_desktop') 'visible-show-desktop operation_type mismatch.'
Assert ($visibleShowDesktop.data.attempt_1_mode -eq 'visible_mouse_click_show_desktop') 'visible-show-desktop must use bottom-right visible click as attempt 1.'
Assert ($visibleShowDesktop.data.win_d_used -eq $false) 'visible-show-desktop must not use Win+D by default.'
Assert ($visibleShowDesktop.data.backend_show_desktop_used -eq $false) 'visible-show-desktop must not use backend by default.'

$visibleWindowSwitch = Invoke-Agent -WinArgs @('visible-window-switch', '--target-title', 'dry-run-target', '--dry-run', 'true')
Assert ($visibleWindowSwitch.ok -eq $true) 'visible-window-switch dry-run policy should pass.'
Assert ($visibleWindowSwitch.data.operation_type -eq 'window_switch') 'visible-window-switch operation_type mismatch.'
Assert ($visibleWindowSwitch.data.attempt_1_mode -eq 'alt_tab_keyboard_switch') 'visible-window-switch must use Alt+Tab as attempt 1.'
Assert ($visibleWindowSwitch.data.alt_tab_attempted -eq $true) 'visible-window-switch must record Alt+Tab attempted.'
Assert ($visibleWindowSwitch.data.backend_focus_used -eq $false) 'visible-window-switch must not use backend focus by default.'

$missingTaskbarLocate = Invoke-Agent -WinArgs @(
    'taskbar-icon-locate',
    '--target', 'DesktopVisualMissingVisibleFirstPolicyTarget'
) -Allowed @(1)
Assert ($missingTaskbarLocate.ok -eq $false) 'taskbar-icon-locate missing target should fail safely.'
Assert ($missingTaskbarLocate.error.code -ne 'VISIBLE_PRIMITIVE_REQUIRES_EXPLICIT_VISIBLE_INPUT_EXECUTION') 'visible primitive must have a real non-dry-run execution path.'
Assert ($missingTaskbarLocate.data.operation_priority.visible_mouse_keyboard_attempted -eq $true) 'non-dry-run locate must record visible attempt evidence.'
Assert ($missingTaskbarLocate.data.operation_priority.attempt_1_result -eq 'failed') 'missing locate should record first attempt failure.'

$report = Join-Path $OutDir 'visible_operation_priority_policy_report.md'
@(
    '# Visible Operation Priority Policy Selftest',
    '',
    '- result: PASS',
    '- clipboard before visible/shortcut failure rejected: PASS',
    '- direct clipboard primitive remains separate from visible-text-input fallback: PASS',
    '- clipboard after visible/shortcut failure accepted: PASS',
    '- backend before visible/shortcut failure rejected: PASS',
    '- backend after visible/shortcut failure accepted: PASS',
    '- backend launch primary path rejected: PASS',
    '- backend focus primary path rejected: PASS',
    '- backend browser navigation primary path rejected: PASS',
    '- max attempts exceeded rejected: PASS'
    '- Runtime visible launch/switch/navigation primitive commands: PASS',
    '- visible-show-desktop default bottom-right click command: PASS',
    '- visible-window-switch default Alt+Tab command: PASS',
    '- Runtime visible primitive non-dry-run execution path: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host 'PASS visible_operation_priority_policy_selftest'
exit 0
