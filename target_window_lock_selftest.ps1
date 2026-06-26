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
    if ($Allowed -notcontains $exit) { throw "winagent $($WinArgs -join ' ') exited $exit with output: $output" }
    return $output | ConvertFrom-Json
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$missing = Invoke-Agent -WinArgs @('target-lock-acquire', '--target-process', 'definitely_missing_visible_ui_process.exe') -Allowed @(1)
Assert ($missing.ok -eq $false) 'missing process target lock should fail.'
Assert ($missing.error.code -eq 'FAIL_TARGET_WINDOW_LOST' -or $missing.error.code -eq 'WINDOW_NOT_FOUND') 'missing target should report target lost/window not found.'

$noLock = Invoke-Agent -WinArgs @('desktop-click', '--screen-x', '1', '--screen-y', '1', '--require-target-lock', 'true', '--allow-global-desktop', 'false', '--humanmode', 'false') -Allowed @(1)
Assert ($noLock.ok -eq $false) 'desktop-click without target lock should fail.'
Assert ($noLock.error.code -eq 'FAIL_TARGET_LOCK_REQUIRED') 'desktop-click without target lock must return FAIL_TARGET_LOCK_REQUIRED.'

$desktop = Invoke-Agent -WinArgs @('target-lock-acquire', '--allow-global-desktop', 'true')
Assert ($desktop.ok -eq $true) 'global desktop target lock should pass.'
Assert ($desktop.data.allow_global_desktop -eq $true) 'global desktop lock should declare allow_global_desktop=true.'
Assert ($desktop.data.target_window_locked -eq $false) 'global desktop lock should not pretend to lock an app window.'

$report = Join-Path $OutDir 'target_window_lock_report.md'
@(
    '# Target Window Lock Selftest',
    '',
    '- result: PASS',
    '- target lock required failure: PASS',
    '- allow global desktop: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS target_window_lock_selftest"
exit 0
