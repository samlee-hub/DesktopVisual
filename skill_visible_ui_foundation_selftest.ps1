param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$Protocol = Join-Path $Root 'COMMAND_PROTOCOL.md'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$text = Get-Content -Raw -LiteralPath $Protocol
foreach ($needle in @(
    'global-screenshot',
    'target-lock-acquire',
    'target-lock-release',
    'coordinate-map',
    'foreground-preempt',
    'visible-text-input',
    'visible-action-batch',
    'visible-ui-verify',
    'visible-operation-policy-check',
    'taskbar-icon-locate',
    'taskbar-icon-click',
    'desktop-icon-locate',
    'desktop-icon-double-click',
    'start-menu-visible-launch',
    'visible-window-switch',
    'visible-page-navigation',
    'vlm-runtime-candidate',
    'pycharm-visible-demo',
    'Clipboard operations are fallbacks',
    'clipboard-set',
    'FAIL_CLIPBOARD_PRIORITY_VIOLATION',
    'VLM-assisted requires Runtime candidate validation',
    'attempt 1 visible mouse/keyboard',
    'BLOCKED_BACKEND_LAUNCH_USED_BEFORE_VISIBLE_LAUNCH',
    'BLOCKED_BACKEND_FOCUS_USED_BEFORE_VISIBLE_SWITCH',
    'BLOCKED_BACKEND_BROWSER_NAV_USED_BEFORE_VISIBLE_NAV',
    'V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION',
    'BLOCKED_PYCHARM_BACKEND_LAUNCH_PRIORITY_VIOLATION'
)) {
    Assert ($text -match [regex]::Escape($needle)) "COMMAND_PROTOCOL.md missing $needle"
}

$report = Join-Path $OutDir 'skill_visible_ui_foundation_report.md'
@(
    '# Skill Visible UI Foundation Selftest',
    '',
    '- result: PASS',
    '- developer path only: true',
    '- external skill file modified by this run: false',
    '- protocol visible UI foundation rules: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS skill_visible_ui_foundation_selftest"
exit 0
