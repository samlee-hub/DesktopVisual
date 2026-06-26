param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$TemplatesDir = Join-Path $Root 'tasks\templates'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'template_selftest_report.md'
$TaskFile = Join-Path $Artifacts 'template_selftest.task.json'
$TaskReport = Join-Path $Artifacts 'template_task_report.md'
$WaitTaskFile = Join-Path $Artifacts 'template_wait_selftest.task.json'
$WaitTaskReport = Join-Path $Artifacts 'template_wait_task_report.md'
$DelayedFile = Join-Path $Artifacts 'template_wait_delayed.txt'
$StateFile = 'D:\testrepo\testwindow\runtime\state.txt'

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

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$expectedTemplates = @(
    'open_app',
    'focus_window',
    'fill_form',
    'click_button',
    'wait_until_text',
    'wait_until_window',
    'copy_text',
    'save_file',
    'open_local_html',
    'run_local_test_page'
)

if (!(Test-Path -LiteralPath $TemplatesDir)) { Fail "Missing templates directory: $TemplatesDir" }
foreach ($name in $expectedTemplates) {
    $path = Join-Path $TemplatesDir "$name.task-template.json"
    if (!(Test-Path -LiteralPath $path)) { Fail "Missing template: $path" }
    try { $template = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Fail "Template is not valid JSON: $path" }
    foreach ($field in @('name','required_permissions','allowed_window','expected_result','failure_behavior','steps')) {
        if ($null -eq $template.$field) { Fail "Template $name missing $field" }
    }
    if ($template.name -ne $name) { Fail "Template $name has mismatched name $($template.name)" }
    if ($template.allow_unrestricted_desktop -eq $true) { Fail "Template $name allows unrestricted desktop." }
}

Stop-TestWindow
$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    Wait-AgentTestWindow

@'
{
  "version": 1,
  "name": "template selftest",
  "target": {
    "title": "Agent Test Window",
    "process": "TestWindow.exe"
  },
  "budget": {
    "max_steps": 10,
    "max_duration_ms": 30000,
    "max_recoveries": 0
  },
  "steps": [
    {
      "name": "click via template",
      "type": "template",
      "template": "click_button",
      "parameters": {
        "selector": "uia:name=Click Me,type=Button",
        "expect_selector": "uia:name=Click Me"
      }
    },
    {
      "name": "fill via template",
      "type": "template",
      "template": "fill_form",
      "parameters": {
        "field_selector": "uia:type=Edit,index=0",
        "text": "templatehello",
        "expect_file_contains_path": "D:\\testrepo\\testwindow\\runtime\\state.txt",
        "expect_file_contains_text": "templatehello"
      }
    },
    {
      "name": "wait window via template",
      "type": "template",
      "template": "wait_until_window",
      "parameters": {
        "wait_ms": 100,
        "timeout_ms": 1000,
        "title_contains": "Agent Test Window"
      }
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $TaskFile

    $task = Invoke-WinAgentJson -WinArgs @('run-task', '--file', $TaskFile, '--report', $TaskReport)
    if ($task.json.ok -ne $true -or !(Test-Path -LiteralPath $TaskReport)) { Fail "template task failed: $($task.text)" }

    $reportText = Get-Content -LiteralPath $TaskReport -Raw
    foreach ($marker in @('## Templates','Template:','click_button','fill_form','wait_until_window','Parameters','Expanded steps','template_expanded_from')) {
        if ($reportText -notlike "*$marker*") { Fail "Template task report missing marker: $marker" }
    }
    if (!(Test-Path -LiteralPath $StateFile)) { Fail "Missing TestWindow state file: $StateFile" }
    $stateText = Get-Content -LiteralPath $StateFile -Raw
    if ($stateText -notlike '*last_text=templatehello*') { Fail 'fill_form template did not update TestWindow text state.' }

    Remove-Item -LiteralPath $DelayedFile -Force -ErrorAction SilentlyContinue
    $job = Start-Job -ArgumentList $DelayedFile -ScriptBlock {
        param([string]$Path)
        Start-Sleep -Milliseconds 800
        Set-Content -Encoding UTF8 -LiteralPath $Path -Value 'delayed_ready=true'
    }
    try {
@"
{
  "version": 1,
  "name": "template wait polling selftest",
  "target": {
    "title": "Agent Test Window",
    "process": "TestWindow.exe"
  },
  "budget": {
    "max_steps": 5,
    "max_duration_ms": 30000,
    "max_recoveries": 0
  },
  "steps": [
    {
      "name": "wait for delayed file",
      "type": "wait",
      "wait_ms": 100,
      "timeout_ms": 3000,
      "expect": {
        "file_contains_path": "$($DelayedFile -replace '\\', '\\')",
        "file_contains_text": "delayed_ready=true"
      }
    }
  ]
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $WaitTaskFile

        $waitTask = Invoke-WinAgentJson -WinArgs @('run-task', '--file', $WaitTaskFile, '--report', $WaitTaskReport)
        if ($waitTask.json.ok -ne $true -or !(Test-Path -LiteralPath $WaitTaskReport)) { Fail "wait polling task failed: $($waitTask.text)" }
    }
    finally {
        Wait-Job $job -Timeout 5 | Out-Null
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    @(
        '# DesktopVisual Template Selftest',
        '',
        '- Result: PASS',
        '- template JSON declarations: PASS',
        '- click_button expansion: PASS',
        '- fill_form expansion: PASS',
        '- wait_until_window expansion: PASS',
        '- wait timeout polling: PASS',
        '- task report template diagnostics: PASS'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Template selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
