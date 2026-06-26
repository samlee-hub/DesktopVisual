param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev_post_v6_runtime_ux_optimization'
$Report = Join-Path $ArtifactDir 'command_alias_report.md'
$Shot = Join-Path $ArtifactDir 'alias_active_screenshot.bmp'
$ObserveOut = Join-Path $ArtifactDir 'alias_active_observe.json'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON from $($WinArgs -join ' '): $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 200
    if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $help = (& $WinAgent help 2>&1 | Out-String)
    foreach ($needle in @('mouse_position -> mouse-position', 'focus-window -> activate-window', 'desktop-right-click', 'desktop-double-click')) {
        if ($help -notmatch [regex]::Escape($needle)) { Fail "help missing alias text: $needle" }
    }

    $focus = Invoke-WinAgentJson -WinArgs @('focus-window', '--title', 'Agent Test Window')
    if ($focus.json.ok -ne $true) { Fail "focus-window setup failed: $($focus.text)" }

    $mouse = Invoke-WinAgentJson -WinArgs @('mouse_position')
    if ($mouse.json.command -ne 'mouse_position') { Fail 'alias command field should preserve mouse_position.' }
    if ($mouse.json.data.canonical_command -ne 'mouse-position') { Fail 'mouse_position missing canonical_command.' }

    $read = Invoke-WinAgentJson -WinArgs @('read_window_text', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    if ($read.json.command -ne 'read_window_text') { Fail 'read_window_text command field should be preserved.' }
    if ($read.json.data.canonical_command -ne 'read-window-text' -and $read.json.data.suggested_command -ne 'read-window-text') {
        Fail "read_window_text missing canonical/suggested command: $($read.text)"
    }

    $shotResult = Invoke-WinAgentJson -WinArgs @('screenshot', '--out', $Shot)
    $fileDeadline = (Get-Date).AddSeconds(2)
    while (-not (Test-Path -LiteralPath $Shot) -and (Get-Date) -lt $fileDeadline) {
        Start-Sleep -Milliseconds 100
    }
    $shotOk = [bool]$shotResult.json.ok
    $shotExists = Test-Path -LiteralPath $Shot
    if ((-not $shotOk) -or (-not $shotExists)) { Fail "screenshot --out default failed: $($shotResult.text)" }
    if ($shotResult.json.data.defaulted_to_active_window -ne $true) { Fail 'screenshot --out must default to active window when title is omitted.' }

    $observeResult = Invoke-WinAgentJson -WinArgs @('observe', '--out', $ObserveOut, '--screenshot', 'false', '--uia', 'false')
    $fileDeadline = (Get-Date).AddSeconds(2)
    while (-not (Test-Path -LiteralPath $ObserveOut) -and (Get-Date) -lt $fileDeadline) {
        Start-Sleep -Milliseconds 100
    }
    $observeOk = [bool]$observeResult.json.ok
    $observeExists = Test-Path -LiteralPath $ObserveOut
    if ((-not $observeOk) -or (-not $observeExists)) { Fail "observe --out default failed: $($observeResult.text)" }
    if ($observeResult.json.data.defaulted_to_active_window -ne $true) { Fail 'observe --out must default to active window when title is omitted.' }

    $uia = Invoke-WinAgentJson -WinArgs @('uia-tree', '--process', 'TestWindow.exe')
    if ($uia.json.ok -ne $true) { Fail "uia-tree --process failed: $($uia.text)" }
    if ($uia.json.data.resolved_from_process -ne $true) { Fail 'uia-tree --process must record process resolution.' }

    $unknown = Invoke-WinAgentJson -WinArgs @('mouse_pos') -AllowedExitCodes @(2)
    if ($unknown.json.error.code -ne 'INVALID_ARGUMENT') { Fail "unknown command expected INVALID_ARGUMENT, got $($unknown.json.error.code)" }
    if ($null -eq $unknown.json.data.closest_matches -or ($unknown.json.data.closest_matches -join ',') -notmatch 'mouse-position') {
        Fail "unknown command did not return closest match mouse-position: $($unknown.text)"
    }

    @(
        '# Command Alias Compatibility Selftest',
        '',
        '- Result: PASS',
        '- mouse_position_alias: PASS',
        '- read_window_text_alias: PASS',
        '- screenshot_out_active_default: PASS',
        '- observe_out_active_default: PASS',
        '- uia_tree_process_resolution: PASS',
        '- unknown_command_suggestions: PASS',
        '- help_aliases_visible: PASS'
    ) | Set-Content -LiteralPath $Report -Encoding UTF8

    Write-Host 'COMMAND_ALIAS_COMPAT_SELFTEST_PASS'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
