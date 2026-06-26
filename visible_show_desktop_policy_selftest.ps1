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

$shortcutWithoutVisible = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'show_desktop',
    '--final-mode-used', 'win_d_keyboard_shortcut_fallback',
    '--keyboard-shortcut-attempted', 'true',
    '--keyboard-shortcut-result', 'succeeded'
) -Allowed @(1)
Assert ($shortcutWithoutVisible.ok -eq $false) 'Win+D before bottom-right visible click must fail.'
Assert ($shortcutWithoutVisible.error.code -eq 'FAIL_SHOW_DESKTOP_VISIBLE_CLICK_NOT_ATTEMPTED') 'show desktop missing visible click code mismatch.'

$backendWithoutEvidence = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'show_desktop',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_show_desktop',
    '--backend-fallback-used', 'true'
) -Allowed @(1)
Assert ($backendWithoutEvidence.ok -eq $false) 'backend show desktop before visible and shortcut failures must fail.'
Assert ($backendWithoutEvidence.error.code -eq 'BLOCKED_BACKEND_SHOW_DESKTOP_USED_BEFORE_VISIBLE_AND_SHORTCUT') 'backend show desktop violation code mismatch.'

$visibleClickDefault = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'show_desktop',
    '--final-mode-used', 'visible_mouse_click_show_desktop',
    '--attempt-1-mode', 'visible_mouse_click_show_desktop',
    '--attempt-2-mode', 'win_d_keyboard_shortcut_fallback',
    '--attempt-3-mode', 'backend_show_desktop_fallback',
    '--visible-mouse-keyboard-attempted', 'true',
    '--attempt-1-result', 'succeeded'
)
Assert ($visibleClickDefault.ok -eq $true) 'bottom-right visible click show desktop policy should pass.'
Assert ($visibleClickDefault.data.operation_type -eq 'show_desktop') 'operation_type should be show_desktop.'
Assert ($visibleClickDefault.data.attempt_1_mode -eq 'visible_mouse_click_show_desktop') 'show desktop attempt 1 mode mismatch.'
Assert ($visibleClickDefault.data.final_mode_used -eq 'visible_mouse_click_show_desktop') 'show desktop final mode mismatch.'
Assert ($visibleClickDefault.data.priority_violation -eq $false) 'visible click default should not be a priority violation.'

$dryRun = Invoke-Agent -WinArgs @('visible-show-desktop', '--dry-run', 'true')
Assert ($dryRun.ok -eq $true) 'visible-show-desktop dry-run should pass.'
Assert ($dryRun.data.operation_type -eq 'show_desktop') 'visible-show-desktop operation_type mismatch.'
Assert ($dryRun.data.attempt_1_mode -eq 'visible_mouse_click_show_desktop') 'visible-show-desktop must default to bottom-right click.'
Assert ($dryRun.data.bottom_right_show_desktop_clicked -eq $true) 'dry-run should record bottom_right_show_desktop_clicked=true.'
Assert ($dryRun.data.win_d_used -eq $false) 'dry-run should not use Win+D.'
Assert ($dryRun.data.backend_show_desktop_used -eq $false) 'dry-run should not use backend show desktop.'
Assert ($dryRun.data.priority_violation -eq $false) 'dry-run should not violate priority.'

$report = Join-Path $OutDir 'visible_show_desktop_report.md'
@(
    '# Visible Show Desktop Policy Selftest',
    '',
    '- result: PASS',
    '- bottom-right show desktop visible click required before Win+D: PASS',
    '- backend show desktop blocked before visible and shortcut failure evidence: PASS',
    '- visible-show-desktop default dry-run command fields: PASS',
    '- pycharm_test_run: false',
    '- wechat_test_prepared: false'
) | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host 'PASS visible_show_desktop_policy_selftest'
exit 0
