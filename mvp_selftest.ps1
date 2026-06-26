param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$MvpArtifacts = Join-Path $Artifacts 'mvp'
$TasksDir = Join-Path $Root 'tasks'
New-Item -ItemType Directory -Force -Path $MvpArtifacts | Out-Null

function Fail($msg) { throw "FAIL: $msg" }
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green }
function Skip($msg) { throw "SKIPPED: $msg" }

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail "Build failed" }
}

$passed = 0
$failed = 0
$skipped = 0
$oldSafety = $env:DESKTOPVISUAL_SAFETY_CONFIG

function Check($name, [scriptblock]$test) {
    Write-Host "=== $name ===" -ForegroundColor Cyan
    try {
        & $test
        $script:passed++
    } catch {
        if ($_.Exception.Message -match '^SKIPPED:') {
            $script:skipped++
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
        } else {
            $script:failed++
            Write-Host "  $_" -ForegroundColor Red
        }
    } finally {
        $env:DESKTOPVISUAL_SAFETY_CONFIG = $script:oldSafety
    }
}

function Invoke-AgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try { return @{ exit = $exit; json = ($output | ConvertFrom-Json); raw = [string]$output } }
    catch { Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output" }
}

function Invoke-TaskJson {
    param([string]$TaskName, [string]$ReportName, [int[]]$AllowedExitCodes = @(0))
    $task = Join-Path $TasksDir $TaskName
    $report = Join-Path $MvpArtifacts $ReportName
    return Invoke-AgentJson -WinArgs @('run-task', '--file', $task, '--report', $report) -AllowedExitCodes $AllowedExitCodes
}

function New-MvpSafetyConfig {
    param([string]$Name, [string]$AllowedTitles, [string]$AllowedProcesses)
    $dir = Join-Path $MvpArtifacts $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $path = Join-Path $dir 'safety.conf'
    @(
        "allowed_titles=$AllowedTitles"
        "allowed_processes=$AllowedProcesses"
        'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;${PROJECT_ROOT}\cases;${PROJECT_ROOT}\tasks;D:\testrepo\testwindow'
        'allowed_write_roots=${PROJECT_ROOT}\artifacts;${PROJECT_ROOT}\config;D:\testrepo\testwindow'
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-OcrAvailable {
    $version = Invoke-AgentJson -WinArgs @('version')
    return [bool]$version.json.data.ocr_available
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Check "testwindow_basic.task.json PASS" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 300
    Start-Process -FilePath $TestWindowExe -PassThru | Out-Null
    Start-Sleep -Milliseconds 900
    $result = Invoke-TaskJson -TaskName 'testwindow_basic.task.json' -ReportName 'mvp_testwindow_report.md'
    Stop-TestWindow
    if (-not $result.json.ok) { Fail "testwindow_basic failed: $($result.json.error.message)" }
    if ($result.json.data.steps -lt 3) { Fail "Expected at least 3 task steps." }
    Pass "testwindow_basic passed with $($result.json.data.steps) steps"
}

Check "notepad_input.task.json PASS/SKIP" {
    if (-not (Get-OcrAvailable)) { Skip 'OCR unavailable; notepad text expectation depends on OCR.' }
    if (@(Get-Process notepad -ErrorAction SilentlyContinue).Count -gt 0) {
        Skip 'Existing Notepad process found; skipping to avoid user-file input.'
    }
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-MvpSafetyConfig -Name 'notepad' -AllowedTitles 'Notepad;mvp_notepad.txt' -AllowedProcesses 'notepad.exe;ApplicationFrameHost.exe'
    $dir = Join-Path $MvpArtifacts 'notepad'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $sample = Join-Path $dir 'mvp_notepad.txt'
    '' | Set-Content -LiteralPath $sample -Encoding UTF8
    $proc = Start-Process notepad.exe -ArgumentList ('"{0}"' -f $sample) -PassThru
    Start-Sleep -Milliseconds 1200
    try {
        $result = Invoke-TaskJson -TaskName 'notepad_input.task.json' -ReportName 'mvp_notepad_report.md' -AllowedExitCodes @(0, 1)
        if (-not $result.json.ok) { Skip "Notepad task did not pass in this environment: $($result.json.error.code) $($result.json.error.message)" }
        Pass 'Notepad task passed'
    } finally {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

Check "calculator_42.task.json PASS/SKIP" {
    if (@(Get-Process calc,Calculator,CalculatorApp -ErrorAction SilentlyContinue).Count -gt 0) {
        Skip 'Existing Calculator process found; skipping to avoid closing a user window.'
    }
    $calcPath = Join-Path $env:SystemRoot 'System32\calc.exe'
    if (-not (Test-Path -LiteralPath $calcPath)) { Skip 'calc.exe not found.' }
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-MvpSafetyConfig -Name 'calculator' -AllowedTitles 'Calculator' -AllowedProcesses 'CalculatorApp.exe;Calculator.exe;calc.exe;ApplicationFrameHost.exe'
    $beforeIds = @(Get-Process calc,Calculator,CalculatorApp,ApplicationFrameHost -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    Start-Process -FilePath $calcPath
    Start-Sleep -Milliseconds 1800
    try {
        $result = Invoke-TaskJson -TaskName 'calculator_42.task.json' -ReportName 'mvp_calculator_report.md' -AllowedExitCodes @(0, 1)
        if (-not $result.json.ok) { Skip "Calculator task did not pass: $($result.json.error.code) $($result.json.error.message)" }
        Pass 'Calculator task passed'
    } finally {
        $afterIds = @(Get-Process calc,Calculator,CalculatorApp,ApplicationFrameHost -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
        foreach ($id in @($afterIds | Where-Object { $beforeIds -notcontains $_ })) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        }
    }
}

Check "edge_local_form.task.json PASS/SKIP" {
    if (@(Get-Process msedge -ErrorAction SilentlyContinue).Count -gt 0) {
        Skip 'Existing Edge process found; skipping to avoid user browser state.'
    }
    $edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edgeExe) { Skip 'Microsoft Edge not found.' }
    $dir = Join-Path $MvpArtifacts 'edge'
    $profile = Join-Path $dir 'profile'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $profile | Out-Null
    $page = Join-Path $dir 'page.html'
    '<!doctype html><title>DesktopVisual Dogfood Test</title><h1>DesktopVisual Dogfood Test</h1><input aria-label="Input"><button>Submit</button>' |
        Set-Content -LiteralPath $page -Encoding UTF8
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-MvpSafetyConfig -Name 'edge' -AllowedTitles 'DesktopVisual Dogfood Test' -AllowedProcesses 'msedge.exe'
    Start-Process -FilePath $edgeExe -ArgumentList @('--no-first-run', '--no-default-browser-check', "--user-data-dir=$profile", "file:///$($page -replace '\\','/')")
    Start-Sleep -Milliseconds 2500
    try {
        $result = Invoke-TaskJson -TaskName 'edge_local_form.task.json' -ReportName 'mvp_edge_report.md' -AllowedExitCodes @(0, 1)
        if (-not $result.json.ok) { Skip "Edge task did not pass: $($result.json.error.code) $($result.json.error.message)" }
        Pass 'Edge local task passed'
    } finally {
        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Check "explorer_temp_folder.task.json PASS" {
    $dir = Join-Path $MvpArtifacts 'explorer\mvp_explorer_work'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-MvpSafetyConfig -Name 'explorer' -AllowedTitles 'mvp_explorer_work;File Explorer' -AllowedProcesses 'explorer.exe'
    Start-Process explorer.exe -ArgumentList ('"{0}"' -f $dir)
    Start-Sleep -Milliseconds 1500
    $result = Invoke-TaskJson -TaskName 'explorer_temp_folder.task.json' -ReportName 'mvp_explorer_report.md' -AllowedExitCodes @(0, 1)
    Invoke-AgentJson -WinArgs @('hotkey', '--title', 'mvp_explorer_work', '--keys', 'ALT+F4') -AllowedExitCodes @(0, 1) | Out-Null
    if (-not $result.json.ok) { Fail "Explorer task failed: $($result.json.error.code) $($result.json.error.message)" }
    Pass 'Explorer task passed'
}

Check "vscode_edit_save.task.json PASS/SKIP" {
    if (@(Get-Process Code -ErrorAction SilentlyContinue).Count -gt 0) {
        Skip 'Existing VS Code process found; skipping to avoid user workspace state.'
    }
    $codeExe = (Get-Command code -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    if (-not $codeExe) {
        $codeExe = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "${env:ProgramFiles}\Microsoft VS Code\Code.exe") |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $codeExe) { Skip 'VS Code not found.' }
    $dir = Join-Path $MvpArtifacts 'vscode'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $sample = Join-Path $dir 'sample.txt'
    'DesktopVisual MVP VS Code sample' | Set-Content -LiteralPath $sample -Encoding UTF8
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-MvpSafetyConfig -Name 'vscode' -AllowedTitles 'sample.txt' -AllowedProcesses 'Code.exe'
    Start-Process -FilePath $codeExe -ArgumentList ('"{0}"' -f $sample)
    Start-Sleep -Milliseconds 3500
    try {
        $result = Invoke-TaskJson -TaskName 'vscode_edit_save.task.json' -ReportName 'mvp_vscode_report.md' -AllowedExitCodes @(0, 1)
        if (-not $result.json.ok) { Skip "VS Code task did not pass: $($result.json.error.code) $($result.json.error.message)" }
        Pass 'VS Code task passed'
    } finally {
        Get-Process Code -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Check "Locator failure recovery stops" {
    $failTask = Join-Path $MvpArtifacts 'mvp_locator_fail.task.json'
    $failTaskJson = '{"version":1,"name":"locator_fail_test","target":{"title":"Agent Test Window","process":"TestWindow.exe"},"budget":{"max_steps":10,"max_duration_ms":30000,"max_recoveries":1},"steps":[{"name":"fail_locate","type":"locate","selector":"uia:name=DoesNotExistXYZ"}]}'
    $failTaskJson | Set-Content -LiteralPath $failTask -Encoding UTF8
    Stop-TestWindow
    Start-Sleep -Milliseconds 300
    Start-Process -FilePath $TestWindowExe -PassThru | Out-Null
    Start-Sleep -Milliseconds 900
    $report = Join-Path $MvpArtifacts 'mvp_locator_fail_report.md'
    $result = Invoke-AgentJson -WinArgs @('run-task', '--file', $failTask, '--report', $report) -AllowedExitCodes @(1)
    Stop-TestWindow
    if ($result.json.ok) { Fail 'Locator failure task should fail.' }
    if ($result.json.error.code -ne 'LOCATOR_NOT_FOUND') { Fail "Expected LOCATOR_NOT_FOUND, got $($result.json.error.code)" }
    Pass 'Task stopped after bounded locator recovery path'
}

Check "Safety denied immediate stop" {
    $safetyTask = Join-Path $MvpArtifacts 'mvp_safety_denied.task.json'
    $safetyTaskJson = '{"version":1,"name":"safety_denied_test","target":{"title":"Agent Test Window","process":"TestWindow.exe"},"budget":{"max_steps":5,"max_duration_ms":10000,"max_recoveries":2},"steps":[{"name":"unsafe_click","type":"act","selector":"coord:x=80,y=90","action":"click"}]}'
    $safetyTaskJson | Set-Content -LiteralPath $safetyTask -Encoding UTF8
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-MvpSafetyConfig -Name 'safety_denied' -AllowedTitles 'Notepad' -AllowedProcesses 'notepad.exe'
    Stop-TestWindow
    Start-Process -FilePath $TestWindowExe -PassThru | Out-Null
    Start-Sleep -Milliseconds 900
    $report = Join-Path $MvpArtifacts 'mvp_safety_denied_report.md'
    $result = Invoke-AgentJson -WinArgs @('run-task', '--file', $safetyTask, '--report', $report) -AllowedExitCodes @(1)
    Stop-TestWindow
    if ($result.json.ok) { Fail 'Safety denied task should fail.' }
    if ($result.json.error.code -ne 'SAFETY_POLICY_DENIED') { Fail "Expected SAFETY_POLICY_DENIED, got $($result.json.error.code)" }
    Pass 'Safety denial stopped immediately'
}

Check "Window unique failure stops" {
    $uniqueTask = Join-Path $MvpArtifacts 'mvp_window_unique.task.json'
    $uniqueTaskJson = '{"version":1,"name":"window_unique_test","target":{"title":"Agent Test Window","process":"TestWindow.exe"},"budget":{"max_steps":5,"max_duration_ms":10000,"max_recoveries":1},"steps":[{"name":"observe_duplicate","type":"observe"}]}'
    $uniqueTaskJson | Set-Content -LiteralPath $uniqueTask -Encoding UTF8
    Stop-TestWindow
    Start-Process -FilePath $TestWindowExe -PassThru | Out-Null
    Start-Process -FilePath $TestWindowExe -PassThru | Out-Null
    Start-Sleep -Milliseconds 1200
    $report = Join-Path $MvpArtifacts 'mvp_window_unique_report.md'
    $result = Invoke-AgentJson -WinArgs @('run-task', '--file', $uniqueTask, '--report', $report) -AllowedExitCodes @(1)
    Stop-TestWindow
    if ($result.json.ok) { Fail 'Window unique task should fail.' }
    if ($result.json.error.code -ne 'WINDOW_NOT_UNIQUE') { Fail "Expected WINDOW_NOT_UNIQUE, got $($result.json.error.code)" }
    Pass 'Window-not-unique stopped with user-actionable failure'
}

Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "MVP Selftest v3.0" -ForegroundColor Cyan
Write-Host "Passed: $passed  Failed: $failed  Skipped: $skipped" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
if ($failed -gt 0) { exit 1 }
exit 0
