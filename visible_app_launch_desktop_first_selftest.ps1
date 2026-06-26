param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.1_runtime_visible_first_launch_and_fallback_discipline'
$Report = Join-Path $OutDir 'visible_app_launch_desktop_first_selftest_report.md'
if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$TestWindowExe = Join-Path $TestRepoRoot 'testwindow\bin\TestWindow.exe'
$Desktop = [Environment]::GetFolderPath('Desktop')
$StartMenuPrograms = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$DesktopFixtureName = 'DesktopVisual101LaunchFixture'
$StartFixtureName = 'DesktopVisual101StartFixture'
$DesktopShortcut = Join-Path $Desktop "$DesktopFixtureName.lnk"
$StartShortcut = Join-Path $StartMenuPrograms "$StartFixtureName.lnk"

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

function New-Shortcut([string]$ShortcutPath, [string]$TargetPath) {
    $parent = Split-Path -Parent $ShortcutPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
    $shortcut.WindowStyle = 1
    $shortcut.Save()
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
}

function Cleanup-Fixtures {
    Remove-Item -LiteralPath $DesktopShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StartShortcut -Force -ErrorAction SilentlyContinue
    Stop-TestWindow
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build first." }
if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build first." }

$desktopResult = $null
$startResult = $null
try {
    Cleanup-Fixtures

    New-Shortcut -ShortcutPath $DesktopShortcut -TargetPath $TestWindowExe
    Start-Sleep -Milliseconds 5000

    $desktopResult = Invoke-Agent -WinArgs @(
        'visible-app-launch',
        '--target', $DesktopFixtureName,
        '--target-title', 'Agent Test Window',
        '--process', 'TestWindow.exe',
        '--wait-ms', '8000',
        '--dry-run', 'false',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    )
    Assert ($desktopResult.ok -eq $true) 'desktop shortcut visible-app-launch returned ok=false.'
    Assert ($desktopResult.data.runtime_visible_first_launch -eq $true) 'runtime_visible_first_launch must be true.'
    Assert ($desktopResult.data.launch_strategy -eq 'desktop_first') 'launch_strategy must be desktop_first.'
    Assert ($desktopResult.data.desktop_surface_attempted -eq $true) 'desktop_surface_attempted must be true.'
    Assert ($desktopResult.data.desktop_icon_path_used -eq $true) 'desktop_icon_path_used must be true.'
    Assert ($desktopResult.data.desktop_icon_locate_attempt_count -ge 1) 'desktop icon locate attempt count missing.'
    Assert ($desktopResult.data.desktop_icon_double_click_attempt_count -ge 1) 'desktop icon double-click attempt count missing.'
    Assert ($desktopResult.data.start_menu_fallback_attempted -eq $false) 'desktop hit must not attempt Start Menu fallback.'
    Assert ($desktopResult.data.browser_visible_navigation_fallback_attempted -eq $false) 'desktop app hit must not attempt browser visible nav fallback.'
    Assert ($desktopResult.data.backend_launch_used -eq $false) 'desktop hit must not use backend launch.'
    Assert ($desktopResult.data.target_window_verified -eq $true) 'target window must be verified after desktop launch.'
    Assert ($desktopResult.data.target_verification_method) 'target verification method must be present.'
    Stop-TestWindow
    Remove-Item -LiteralPath $DesktopShortcut -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800

    New-Shortcut -ShortcutPath $StartShortcut -TargetPath $TestWindowExe
    Start-Sleep -Milliseconds 5000

    $startResult = Invoke-Agent -WinArgs @(
        'visible-app-launch',
        '--target', $StartFixtureName,
        '--app', $StartFixtureName,
        '--target-title', 'Agent Test Window',
        '--process', 'TestWindow.exe',
        '--wait-ms', '10000',
        '--dry-run', 'false',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    )
    Assert ($startResult.ok -eq $true) 'Start Menu fallback visible-app-launch returned ok=false.'
    Assert ($startResult.data.runtime_visible_first_launch -eq $true) 'fallback runtime_visible_first_launch must be true.'
    Assert ($startResult.data.launch_strategy -eq 'desktop_first') 'fallback launch_strategy must be desktop_first.'
    Assert ($startResult.data.desktop_surface_attempted -eq $true) 'fallback desktop_surface_attempted must be true.'
    Assert ($startResult.data.desktop_icon_path_used -eq $false) 'desktop_icon_path_used must be false when desktop shortcut is absent.'
    Assert ($startResult.data.desktop_icon_locate_attempt_count -ge 2) 'fallback requires two bounded desktop locate attempts.'
    Assert ($startResult.data.bounded_recovery_attempted -eq $true) 'fallback requires bounded recovery between desktop attempts.'
    Assert ($startResult.data.start_menu_fallback_attempted -eq $true) 'Start Menu visible fallback must be attempted after desktop miss.'
    Assert ($startResult.data.backend_launch_used -eq $false) 'Start Menu visible fallback must not use backend launch.'
    Assert ($startResult.data.target_window_verified -eq $true) 'target window must be verified after Start Menu fallback.'

    $lines = @(
        '# visible-app-launch desktop-first selftest',
        '',
        '- result: PASS',
        '- desktop shortcut path: PASS',
        '- desktop-miss Start Menu visible fallback path: PASS',
        '',
        '## Desktop Path Result',
        '',
        '```json',
        ($desktopResult | ConvertTo-Json -Depth 20),
        '```',
        '',
        '## Start Menu Fallback Result',
        '',
        '```json',
        ($startResult | ConvertTo-Json -Depth 20),
        '```'
    )
    $lines | Set-Content -Encoding UTF8 -LiteralPath $Report
    Write-Host 'PASS visible_app_launch_desktop_first_selftest'
    Write-Host "Report: $Report"
    exit 0
} finally {
    Cleanup-Fixtures
}
