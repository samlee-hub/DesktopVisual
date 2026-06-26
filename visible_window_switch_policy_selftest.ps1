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

$backendFocusTooEarly = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'window_switch',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_focus',
    '--backend-fallback-used', 'true'
) -Allowed @(1)
Assert ($backendFocusTooEarly.ok -eq $false) 'backend focus before Alt+Tab and visible click must fail.'
Assert ($backendFocusTooEarly.error.code -eq 'BLOCKED_BACKEND_FOCUS_USED_BEFORE_ALT_TAB_AND_VISIBLE_CLICK') 'backend focus priority code mismatch.'

$altTabDefault = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'window_switch',
    '--final-mode-used', 'alt_tab_keyboard_switch',
    '--attempt-1-mode', 'alt_tab_keyboard_switch',
    '--attempt-2-mode', 'visible_taskbar_or_window_click',
    '--attempt-3-mode', 'backend_focus_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--attempt-1-result', 'succeeded'
)
Assert ($altTabDefault.ok -eq $true) 'Alt+Tab primary window switch policy should pass.'
Assert ($altTabDefault.data.attempt_1_mode -eq 'alt_tab_keyboard_switch') 'window switch attempt 1 must be Alt+Tab.'
Assert ($altTabDefault.data.final_mode_used -eq 'alt_tab_keyboard_switch') 'window switch final mode should be Alt+Tab.'
Assert ($altTabDefault.data.window_switch_primary_alt_tab_skipped -eq $false) 'Alt+Tab primary should not be marked skipped.'

$visibleFallback = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'window_switch',
    '--final-mode-used', 'visible_taskbar_or_window_click',
    '--attempt-1-mode', 'alt_tab_keyboard_switch',
    '--attempt-2-mode', 'visible_taskbar_or_window_click',
    '--attempt-3-mode', 'backend_focus_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--attempt-1-result', 'failed',
    '--attempt-1-failure-reason', 'target_not_found_in_alt_tab_overlay',
    '--keyboard-shortcut-attempted', 'true',
    '--attempt-2-result', 'succeeded'
)
Assert ($visibleFallback.ok -eq $true) 'visible taskbar/window click should be allowed after Alt+Tab failure.'
Assert ($visibleFallback.data.attempt_1_result -eq 'failed') 'fallback policy should retain Alt+Tab failure.'
Assert ($visibleFallback.data.attempt_2_mode -eq 'visible_taskbar_or_window_click') 'window switch attempt 2 mode mismatch.'
Assert ($visibleFallback.data.window_switch_primary_alt_tab_skipped -eq $false) 'fallback after Alt+Tab failure should not mark primary skipped.'

$visibleClickSkippedAltTab = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'window_switch',
    '--final-mode-used', 'visible_taskbar_or_window_click',
    '--attempt-1-mode', 'visible_taskbar_or_window_click',
    '--visible-mouse-keyboard-attempted', 'true',
    '--attempt-1-result', 'succeeded'
)
Assert ($visibleClickSkippedAltTab.ok -eq $true) 'visible click path can be represented but must mark Alt+Tab skipped.'
Assert ($visibleClickSkippedAltTab.data.window_switch_primary_alt_tab_skipped -eq $true) 'direct visible click must record window_switch_primary_alt_tab_skipped.'

$dryRun = Invoke-Agent -WinArgs @('visible-window-switch', '--target-title', 'dry-run-target', '--dry-run', 'true')
Assert ($dryRun.ok -eq $true) 'visible-window-switch dry-run should pass.'
Assert ($dryRun.data.operation_type -eq 'window_switch') 'visible-window-switch operation_type mismatch.'
Assert ($dryRun.data.attempt_1_mode -eq 'alt_tab_keyboard_switch') 'visible-window-switch must default to Alt+Tab.'
Assert ($dryRun.data.alt_tab_attempted -eq $true) 'visible-window-switch must record Alt+Tab attempt.'
Assert ($dryRun.data.backend_focus_used -eq $false) 'visible-window-switch dry-run must not use backend focus.'
Assert ($dryRun.data.priority_violation -eq $false) 'visible-window-switch dry-run should not violate priority.'

$report = Join-Path $OutDir 'visible_window_switch_report.md'
@(
    '# Visible Window Switch Policy Selftest',
    '',
    '- result: PASS',
    '- backend focus blocked before Alt+Tab and visible click: PASS',
    '- Alt+Tab default policy: PASS',
    '- taskbar/window click fallback after Alt+Tab failure: PASS',
    '- direct visible click marks window_switch_primary_alt_tab_skipped: PASS',
    '- visible-window-switch dry-run command fields: PASS',
    '- pycharm_test_run: false',
    '- wechat_test_prepared: false'
) | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host 'PASS visible_window_switch_policy_selftest'
exit 0
