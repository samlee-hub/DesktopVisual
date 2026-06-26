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

$browserNavTooEarly = Invoke-Agent -WinArgs @(
    'browser-nav',
    '--url', 'about:blank',
    '--target-title', 'dry-run-target',
    '--process', 'missing.exe'
) -Allowed @(1)
Assert ($browserNavTooEarly.ok -eq $false) 'backend browser-nav before visible navigation must fail.'
Assert ($browserNavTooEarly.error.code -eq 'BLOCKED_BACKEND_BROWSER_NAV_USED_BEFORE_VISIBLE_NAV') 'browser-nav priority failure code mismatch.'
Assert ($browserNavTooEarly.data.operation_priority.priority_violation -eq $true) 'browser-nav violation evidence missing.'

$policyBackendTooEarly = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'browser_navigation',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_browser_nav',
    '--backend-fallback-used', 'true'
) -Allowed @(1)
Assert ($policyBackendTooEarly.ok -eq $false) 'policy check should block backend browser navigation first.'
Assert ($policyBackendTooEarly.error.code -eq 'BLOCKED_BACKEND_BROWSER_NAV_USED_BEFORE_VISIBLE_NAV') 'policy browser-nav block code mismatch.'

$policyBackendAfterFailures = Invoke-Agent -WinArgs @(
    'visible-operation-policy-check',
    '--operation-type', 'browser_navigation',
    '--final-mode-used', 'backend_fallback',
    '--backend-fallback-kind', 'backend_browser_nav',
    '--backend-fallback-used', 'true',
    '--backend-fallback-reason', 'visible address-bar click and Ctrl+L navigation both failed',
    '--visible-mouse-keyboard-attempted', 'true',
    '--attempt-1-result', 'failed',
    '--attempt-1-failure-reason', 'visible_address_bar_click_failed',
    '--visible-attempt-count', '2',
    '--pre-action-checkpoint-present', 'true',
    '--bounded-recovery-attempted', 'true',
    '--post-recovery-observed', 'true',
    '--same-surface-after-recovery', 'true',
    '--keyboard-shortcut-attempted', 'true',
    '--attempt-2-result', 'failed',
    '--attempt-2-failure-reason', 'ctrl_l_navigation_failed',
    '--attempt-3-result', 'succeeded'
)
Assert ($policyBackendAfterFailures.ok -eq $true) 'backend browser navigation should be allowed only after first two failures.'
Assert ($policyBackendAfterFailures.data.backend_fallback_used -eq $true) 'backend fallback evidence missing after failures.'
Assert ($policyBackendAfterFailures.data.priority_violation -eq $false) 'backend after failure evidence should not violate priority.'

$visiblePageDryRun = Invoke-Agent -WinArgs @('visible-page-navigation', '--target', 'url', '--dry-run', 'true')
Assert ($visiblePageDryRun.ok -eq $true) 'visible-page-navigation dry-run should pass.'
Assert ($visiblePageDryRun.data.backend_fallback_used -eq $false) 'visible-page-navigation dry-run must not use backend fallback.'
Assert ($visiblePageDryRun.data.operation_priority.operation_type -eq 'page_navigation') 'visible-page-navigation operation type mismatch.'

$report = Join-Path $OutDir 'visible_navigation_priority_report.md'
@(
    '# Visible Navigation Priority Selftest',
    '',
    '- result: PASS',
    '- browser-nav blocked before visible navigation evidence: PASS',
    '- backend browser navigation allowed only after visible and Ctrl+L failure evidence: PASS',
    '- visible-page-navigation dry-run remains visible-first: PASS',
    '- pycharm_test_run: false',
    '- wechat_test_prepared: false'
) | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host 'PASS visible_navigation_priority_selftest'
exit 0
