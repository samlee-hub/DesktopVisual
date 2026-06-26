param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'window_session_selftest_report.md'
$TaskFile = Join-Path $Artifacts 'window_session_selftest.task.json'
$TaskReport = Join-Path $Artifacts 'window_session_task_report.md'

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

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
}

function Wait-AgentTestWindow {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }
}

function Assert-WindowSession($Session, [string]$Context) {
    if ($null -eq $Session) { Fail "$Context missing window_session." }
    if ($Session.title -notlike '*Agent Test Window*') { Fail "$Context window_session.title invalid." }
    if ($Session.process_name -ne 'TestWindow.exe') { Fail "$Context window_session.process_name invalid: $($Session.process_name)" }
    if (-not $Session.hwnd) { Fail "$Context window_session.hwnd missing." }
    if ($Session.pid -le 0) { Fail "$Context window_session.pid invalid." }
    if ($null -eq $Session.rect -or $Session.rect.right -le $Session.rect.left -or $Session.rect.bottom -le $Session.rect.top) { Fail "$Context window_session.rect invalid." }
    if ($null -eq $Session.foreground -or $null -eq $Session.foreground.is_foreground) { Fail "$Context window_session.foreground invalid." }
    if ($null -eq $Session.dpi -or $Session.dpi -le 0) { Fail "$Context window_session.dpi invalid." }
    if ($null -eq $Session.monitor -or -not $Session.monitor.device_name) { Fail "$Context window_session.monitor invalid." }
    if ($null -eq $Session.monitor.rect -or $null -eq $Session.monitor.work_rect) { Fail "$Context window_session.monitor bounds missing." }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Stop-TestWindow
$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    Wait-AgentTestWindow

    $observe = Invoke-WinAgentJson -WinArgs @('observe', '--title', 'Agent Test Window', '--screenshot', 'false', '--uia', 'false')
    Assert-WindowSession $observe.json.data.window_session 'observe'

    $focus = Invoke-WinAgentJson -WinArgs @('focus', '--title', 'Agent Test Window')
    if ($focus.json.ok -ne $true) { Fail "focus failed: $($focus.text)" }
    $focusedObserve = Invoke-WinAgentJson -WinArgs @('observe', '--title', 'Agent Test Window', '--screenshot', 'false', '--uia', 'false')
    Assert-WindowSession $focusedObserve.json.data.window_session 'focused observe'
    if ($focusedObserve.json.data.window_session.foreground.is_foreground -ne $true) { Fail 'focused observe did not confirm foreground window.' }

    @'
{
  "version": 1,
  "name": "window session v3.2 task",
  "target": {
    "title": "Agent Test Window",
    "process": "TestWindow.exe"
  },
  "budget": {
    "max_steps": 2,
    "max_duration_ms": 30000,
    "max_recoveries": 0
  },
  "steps": [
    {
      "name": "locate click button",
      "type": "locate",
      "selector": "uia:name=Click Me"
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $TaskFile

    $task = Invoke-WinAgentJson -WinArgs @('run-task', '--file', $TaskFile, '--report', $TaskReport)
    if ($task.json.ok -ne $true -or !(Test-Path -LiteralPath $TaskReport)) { Fail "window session task failed: $($task.text)" }
    $taskReportText = Get-Content -LiteralPath $TaskReport -Raw
    if ($taskReportText -notlike '*Window session before:*' -or $taskReportText -notlike '*process_name*' -or $taskReportText -notlike '*monitor*') {
        Fail 'run-task report missing window session diagnostics.'
    }

    $proc2 = Start-Process -FilePath $TestWindowExe -PassThru
    try {
        Start-Sleep -Milliseconds 800
        $duplicate = Invoke-WinAgentJson -WinArgs @('observe', '--title', 'Agent Test Window', '--screenshot', 'false', '--uia', 'false') -AllowedExitCodes @(1)
        if ($duplicate.json.error.code -ne 'WINDOW_NOT_UNIQUE') { Fail "Expected WINDOW_NOT_UNIQUE, got $($duplicate.json.error.code)." }
        if ($duplicate.json.data.candidates.Count -lt 2) { Fail 'WINDOW_NOT_UNIQUE did not include duplicate candidates.' }
    }
    finally {
        if ($proc2 -and !$proc2.HasExited) {
            $proc2.CloseMainWindow() | Out-Null
            Start-Sleep -Milliseconds 250
            if (!$proc2.HasExited) { Stop-Process -Id $proc2.Id -Force }
        }
    }

    @(
        '# DesktopVisual Window Session Selftest',
        '',
        '- Result: PASS',
        '- observe window_session: PASS',
        '- foreground confirmation: PASS',
        '- run-task session report: PASS',
        '- duplicate windows stop with WINDOW_NOT_UNIQUE: PASS'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Window session selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
