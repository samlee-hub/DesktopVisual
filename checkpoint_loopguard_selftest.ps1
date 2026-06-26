param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$BuildScript = Join-Path $Root 'build.ps1'
$Artifacts = Join-Path $Root 'artifacts\checkpoint_loopguard'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'

function Fail($Message) {
    throw $Message
}

function Invoke-AgentJson {
    param(
        [string[]]$CmdArgs,
        [switch]$AllowFailure
    )
    $output = & $WinAgent @CmdArgs
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function Write-JsonTask {
    param([string]$Name, [string]$Json)
    $path = Join-Path $Artifacts "$Name.task.json"
    Set-Content -LiteralPath $path -Value $Json -Encoding UTF8
    return $path
}

function Run-Task {
    param([string]$Name, [string]$Json, [switch]$AllowFailure)
    $taskPath = Write-JsonTask -Name $Name -Json $Json
    $report = Join-Path $Artifacts "$Name.report.md"
    $result = Invoke-AgentJson -CmdArgs @('run-task', '--file', $taskPath, '--report', $report) -AllowFailure:$AllowFailure
    if (!(Test-Path -LiteralPath $report)) { Fail "Missing report: $report" }
    return @{ result = $result; report = $report; text = Get-Content -LiteralPath $report -Raw }
}

function Assert-ReportContains {
    param([string]$ReportText, [string]$Needle)
    if ($ReportText -notlike "*$Needle*") {
        Fail "Report missing expected text: $Needle"
    }
}

if (-not $SkipBuild) {
    & $BuildScript -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail "build failed" }
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Get-ChildItem -LiteralPath $Artifacts -Filter '*.checkpoint.tmp.json' -ErrorAction SilentlyContinue | Remove-Item -Force

if (!(Test-Path -LiteralPath $TestWindowExe)) {
    Fail "TestWindow.exe not found: $TestWindowExe"
}

Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$proc = $null

try {
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 500

    $normal = Run-Task -Name 'normal_checkpoint' -Json @'
{
  "version": 1,
  "name": "normal_checkpoint",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "checkpoint": { "enabled": true, "interval_ms": 1, "cleanup_on_end": true },
  "loop_guard": { "repeated_action_limit": 10, "no_progress_limit": 10 },
  "budget": { "max_steps": 10, "max_duration_ms": 120000, "max_recoveries": 0 },
  "steps": [
    { "name": "observe_page", "type": "observe", "page_id": "page-1", "observed_summary": "page loaded" },
    { "name": "manual_checkpoint", "type": "checkpoint", "observed_summary": "manual checkpoint requested" },
    { "name": "wait_done", "type": "wait", "wait_ms": 1, "observed_summary": "page complete" }
  ]
}
'@
    if (-not $normal.result.json.ok) { Fail "normal checkpoint task failed: $($normal.result.text)" }
    Assert-ReportContains $normal.text '## Session Checkpoints'
    Assert-ReportContains $normal.text 'checkpoint_id'
    Assert-ReportContains $normal.text 'Temporary checkpoint cleanup: true'
    Assert-ReportContains $normal.text 'suggested_recovery_actions'

    $repeatClick = Run-Task -Name 'repeated_click_stop' -AllowFailure -Json @'
{
  "version": 1,
  "name": "repeated_click_stop",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "checkpoint": { "enabled": true, "cleanup_on_end": true },
  "loop_guard": { "repeated_action_limit": 2 },
  "budget": { "max_steps": 10, "max_duration_ms": 120000, "max_recoveries": 0 },
  "steps": [
    { "name": "click_1", "type": "act", "selector": "uia:name=Click Me,type=Button", "action": "click", "move_mode": "instant", "observed_summary": "click target" },
    { "name": "click_2", "type": "act", "selector": "uia:name=Click Me,type=Button", "action": "click", "move_mode": "instant", "observed_summary": "click target" },
    { "name": "click_3", "type": "act", "selector": "uia:name=Click Me,type=Button", "action": "click", "move_mode": "instant", "observed_summary": "click target" }
  ]
}
'@
    if ($repeatClick.result.json.error.code -ne 'REPEATED_ACTION_LIMIT') { Fail "Expected REPEATED_ACTION_LIMIT, got $($repeatClick.result.json.error.code)" }
    Assert-ReportContains $repeatClick.text 'REPEATED_ACTION_LIMIT'

    $urlLoop = Run-Task -Name 'url_loop_stop' -AllowFailure -Json @'
{
  "version": 1,
  "name": "url_loop_stop",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "checkpoint": { "enabled": true, "cleanup_on_end": true },
  "loop_guard": { "url_redirect_limit": 2 },
  "budget": { "max_steps": 10, "max_duration_ms": 120000, "max_recoveries": 0 },
  "steps": [
    { "name": "url_1", "type": "wait", "wait_ms": 1, "current_url": "https://example.test/a", "observed_summary": "redirect" },
    { "name": "url_2", "type": "wait", "wait_ms": 1, "current_url": "https://example.test/a", "observed_summary": "redirect" },
    { "name": "url_3", "type": "wait", "wait_ms": 1, "current_url": "https://example.test/a", "observed_summary": "redirect" }
  ]
}
'@
    if ($urlLoop.result.json.error.code -ne 'URL_REDIRECT_LOOP') { Fail "Expected URL_REDIRECT_LOOP, got $($urlLoop.result.json.error.code)" }

    $windowLoop = Run-Task -Name 'window_spawn_stop' -AllowFailure -Json @'
{
  "version": 1,
  "name": "window_spawn_stop",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "checkpoint": { "enabled": true, "cleanup_on_end": true },
  "loop_guard": { "window_spawn_limit": 2 },
  "budget": { "max_steps": 10, "max_duration_ms": 120000, "max_recoveries": 0 },
  "steps": [
    { "name": "open_1", "type": "wait", "action": "open_window", "window_title": "Agent Test Window", "observed_summary": "window_open" },
    { "name": "open_2", "type": "wait", "action": "open_window", "window_title": "Agent Test Window", "observed_summary": "window_open" },
    { "name": "open_3", "type": "wait", "action": "open_window", "window_title": "Agent Test Window", "observed_summary": "window_open" }
  ]
}
'@
    if ($windowLoop.result.json.error.code -ne 'WINDOW_SPAWN_LOOP') { Fail "Expected WINDOW_SPAWN_LOOP, got $($windowLoop.result.json.error.code)" }

    $noProgress = Run-Task -Name 'no_progress_stop' -AllowFailure -Json @'
{
  "version": 1,
  "name": "no_progress_stop",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "checkpoint": { "enabled": true, "cleanup_on_end": true },
  "loop_guard": { "no_progress_limit": 2 },
  "budget": { "max_steps": 10, "max_duration_ms": 120000, "max_recoveries": 0 },
  "steps": [
    { "name": "same_1", "type": "wait", "wait_ms": 1, "observed_summary": "same screen" },
    { "name": "same_2", "type": "wait", "wait_ms": 1, "observed_summary": "same screen" },
    { "name": "same_3", "type": "wait", "wait_ms": 1, "observed_summary": "same screen" }
  ]
}
'@
    if ($noProgress.result.json.error.code -ne 'NO_PROGRESS_DETECTED') { Fail "Expected NO_PROGRESS_DETECTED, got $($noProgress.result.json.error.code)" }
    Assert-ReportContains $noProgress.text 'suggested_recovery_actions'

    $tmpCheckpoints = @(Get-ChildItem -LiteralPath $Artifacts -Filter '*.checkpoint.tmp.json' -ErrorAction SilentlyContinue)
    if ($tmpCheckpoints.Count -ne 0) {
        Fail "Temporary checkpoint files were not cleaned: $($tmpCheckpoints.FullName -join ', ')"
    }

    Write-Host "checkpoint_loopguard_selftest passed."
} finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
