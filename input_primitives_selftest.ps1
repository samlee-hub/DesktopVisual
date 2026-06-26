param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'input_primitives_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try { $json = $output | ConvertFrom-Json } catch { Fail "Invalid JSON: $output" }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $focus = Invoke-WinAgentJson -WinArgs @('focus', '--title', 'Agent Test Window')
    if ($focus.json.data.focus_verified -ne $true) { Fail "focus did not verify: $($focus.text)" }

    $active = Invoke-WinAgentJson -WinArgs @('active-window')
    if (!$active.json.data.hwnd -or !$active.json.data.title) { Fail "active-window missing data: $($active.text)" }

    $pos = Invoke-WinAgentJson -WinArgs @('mouse-position')
    if ([int]$pos.json.data.screen_x -lt 0 -or [int]$pos.json.data.screen_y -lt 0) { Fail "mouse-position invalid: $($pos.text)" }

    foreach ($cmd in @(
        @('double-click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'instant'),
        @('right-click', '--title', 'Agent Test Window', '--x', '90', '--y', '150', '--move-mode', 'instant'),
        @('scroll', '--title', 'Agent Test Window', '--x', '90', '--y', '150', '--delta', '-120', '--move-mode', 'instant'),
        @('drag', '--title', 'Agent Test Window', '--from-x', '120', '--from-y', '160', '--to-x', '180', '--to-y', '160', '--move-mode', 'instant', '--duration-ms', '50'),
        @('hotkey', '--title', 'Agent Test Window', '--keys', 'CTRL+A'),
        @('hotkey', '--title', 'Agent Test Window', '--keys', 'CTRL+C'),
        @('hotkey', '--title', 'Agent Test Window', '--keys', 'CTRL+V')
    )) {
        $result = Invoke-WinAgentJson -WinArgs $cmd
        if ($result.json.ok -ne $true) { Fail "Expected command to pass: $($cmd -join ' ') output=$($result.text)" }
    }

    $clipSet = Invoke-WinAgentJson -WinArgs @('clipboard-set', '--text', 'primitive_clip')
    if ([int]$clipSet.json.data.text_length -ne 14) { Fail "clipboard-set text_length mismatch: $($clipSet.text)" }

    Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '90', '--y', '150') | Out-Null
    $paste = Invoke-WinAgentJson -WinArgs @('clipboard-paste', '--title', 'Agent Test Window', '--text', 'primitive_paste')
    if ($paste.json.data.pasted -ne $true -or [int]$paste.json.data.text_length -ne 15) { Fail "clipboard-paste invalid: $($paste.text)" }

    $missing = Invoke-WinAgentJson -WinArgs @('double-click', '--title', 'Definitely Missing Agent Test Window', '--x', '80', '--y', '90') -AllowedExitCodes @(1)
    if ($missing.json.error.code -ne 'WINDOW_NOT_FOUND') { Fail "Expected WINDOW_NOT_FOUND, got $($missing.json.error.code)" }

    $denyConfig = Join-Path $Artifacts 'input_primitives_deny.conf'
    @(
        'allowed_titles=Some Other Window',
        'allowed_processes=TestWindow.exe',
        "allowed_read_roots=`${PROJECT_ROOT};`${PROJECT_ROOT}\artifacts;$TestWindowRoot",
        "allowed_write_roots=`${PROJECT_ROOT}\artifacts;$TestWindowRoot",
        'max_steps=100',
        'max_duration_ms=120000',
        'emergency_stop_key=F12',
        'allow_absolute_screen_click=false'
    ) | Set-Content -Encoding UTF8 -LiteralPath $denyConfig
    $oldConfig = $env:DESKTOPVISUAL_SAFETY_CONFIG
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $denyConfig
    try {
        $denied = Invoke-WinAgentJson -WinArgs @('right-click', '--title', 'Agent Test Window', '--x', '80', '--y', '90') -AllowedExitCodes @(1)
    } finally {
        $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldConfig
    }
    if ($denied.json.error.code -ne 'SAFETY_POLICY_DENIED') { Fail "Expected SAFETY_POLICY_DENIED, got $($denied.json.error.code)" }

    @(
        '# DesktopVisual Input Primitives Selftest',
        '',
        '- Result: PASS',
        '- focus: PASS',
        '- active-window: PASS',
        '- mouse-position: PASS',
        '- double-click/right-click/scroll/drag: PASS',
        '- hotkey: PASS',
        '- clipboard-set/clipboard-paste: PASS',
        '- missing window: WINDOW_NOT_FOUND',
        '- deny policy: SAFETY_POLICY_DENIED'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Input primitives selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
