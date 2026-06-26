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
$Assets = Join-Path $Root 'assets'
$Template = Join-Path $Assets 'click_button.bmp'
$SourceShot = Join-Path $Artifacts 'selector_image_source.bmp'
$Report = Join-Path $Artifacts 'selector_selftest_report.md'
$CaseFile = Join-Path $Artifacts 'selector_selftest.case'
$CaseReport = Join-Path $Artifacts 'selector_case_report.md'
$TaskFile = Join-Path $Artifacts 'selector_v31_selftest.task.json'
$TaskReport = Join-Path $Artifacts 'selector_v31_task_report.md'
$StateFile = Join-Path $TestWindowRoot 'runtime\state.txt'

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

function Get-StateValue([string]$Name) {
    if (!(Test-Path -LiteralPath $StateFile)) { return '' }
    $line = Get-Content -LiteralPath $StateFile | Where-Object { $_ -like "$Name=*" } | Select-Object -First 1
    if (!$line) { return '' }
    return $line.Substring($Name.Length + 1)
}

function New-ButtonTemplate {
    param([string]$Source, [string]$Destination)
    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::FromFile($Source)
    try {
        $rect = New-Object System.Drawing.Rectangle(68, 101, 120, 36)
        $clone = $bitmap.Clone($rect, $bitmap.PixelFormat)
        try { $clone.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Bmp) }
        finally { $clone.Dispose() }
    }
    finally { $bitmap.Dispose() }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
New-Item -ItemType Directory -Force -Path $Assets | Out-Null
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

    $coord = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'coord:x=80,y=90')
    if ($coord.json.data.locate_method -ne 'coord' -or [int]$coord.json.data.client_point.x -ne 80 -or [int]$coord.json.data.client_point.y -ne 90) { Fail "coord locate invalid: $($coord.text)" }

    $name = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:name=Click Me')
    if ($name.json.data.locate_method -ne 'uia' -or $name.json.data.element.name -ne 'Click Me') { Fail "uia name locate invalid: $($name.text)" }

    $contains = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:name_contains=Click,type=Button')
    if ($contains.json.data.element.control_type -ne 'Button') { Fail "uia contains/type locate invalid: $($contains.text)" }

    $edit = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:type=Edit,index=0')
    if ($edit.json.data.element.control_type -ne 'Edit') { Fail "uia type/index locate invalid: $($edit.text)" }

    $automationId = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:automation_id=1001')
    if ($automationId.json.data.method -ne 'uia' -or $automationId.json.data.element.automation_id -ne '1001') { Fail "uia automation_id locate invalid: $($automationId.text)" }

    $className = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:class_name=Button,name=Click Me,type=Button')
    if ($className.json.data.element.class_name -ne 'Button' -or $className.json.data.element.name -ne 'Click Me') { Fail "uia class_name locate invalid: $($className.text)" }

    $relative = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'relative:relation=below,anchor=uia:name=Click Me,target_role=Edit,nth=0')
    if ($relative.json.data.method -ne 'relative' -or $relative.json.data.source -ne 'uia' -or $relative.json.data.element.control_type -ne 'Edit') { Fail "relative locate invalid: $($relative.text)" }

    $nearText = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'near_text:text=Click Me,target_role=Edit,position=below,nth=0')
    if ($nearText.json.data.method -ne 'near_text' -or $nearText.json.data.matched_text -ne 'Click Me' -or $nearText.json.data.element.control_type -ne 'Edit') { Fail "near_text locate invalid: $($nearText.text)" }

    $chain = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'chain:uia:automation_id=missing||uia:name=Click Me')
    if ($chain.json.data.method -ne 'chain' -or $chain.json.data.final_method -ne 'uia' -or $chain.json.data.fallback_attempts.Count -ne 2) { Fail "fallback chain locate invalid: $($chain.text)" }

    $notUniqueNoNth = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'relative:relation=inside_window,target_role=Button') -AllowedExitCodes @(1)
    if ($notUniqueNoNth.json.error.code -ne 'LOCATOR_NOT_UNIQUE') { Fail "Expected relative LOCATOR_NOT_UNIQUE, got $($notUniqueNoNth.json.error.code)" }

    $relativeNth = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'relative:relation=inside_window,target_role=Button,nth=1')
    if ($relativeNth.json.data.method -ne 'relative' -or [int]$relativeNth.json.data.match_count -lt 2) { Fail "relative nth locate invalid: $($relativeNth.text)" }

    $click = Invoke-WinAgentJson -WinArgs @('act', '--title', 'Agent Test Window', '--selector', 'uia:name=Click Me', '--action', 'click')
    if ($click.json.data.action -ne 'click') { Fail "act click invalid: $($click.text)" }

    $type = Invoke-WinAgentJson -WinArgs @('act', '--title', 'Agent Test Window', '--selector', 'uia:type=Edit,index=0', '--action', 'type', '--text', 'hello')
    if ($type.json.data.action -ne 'type') { Fail "act type invalid: $($type.text)" }
    Start-Sleep -Milliseconds 300
    if ((Get-StateValue 'last_text') -ne 'hello') { Fail "act type did not update state.txt" }

    $missing = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:name=Definitely Missing Selector') -AllowedExitCodes @(1)
    if ($missing.json.error.code -ne 'LOCATOR_NOT_FOUND') { Fail "Expected LOCATOR_NOT_FOUND, got $($missing.json.error.code)" }

    $duplicate = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:name=Twin') -AllowedExitCodes @(1)
    if ($duplicate.json.error.code -ne 'LOCATOR_NOT_UNIQUE') { Fail "Expected LOCATOR_NOT_UNIQUE, got $($duplicate.json.error.code)" }

    $automationMissing = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:automation_id=missing') -AllowedExitCodes @(1)
    if ($automationMissing.json.error.code -ne 'LOCATOR_NOT_FOUND' -or $automationMissing.json.data.failure_reason -notlike '*AutomationId*') { Fail "Expected AutomationId LOCATOR_NOT_FOUND, got $($automationMissing.text)" }

    Invoke-WinAgentJson -WinArgs @('screenshot', '--title', 'Agent Test Window', '--out', $SourceShot) | Out-Null
    New-ButtonTemplate -Source $SourceShot -Destination $Template
    $image = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', "image:path=$Template,tolerance=10")
    if ($image.json.data.locate_method -ne 'image' -or [int]$image.json.data.match_count -ne 1) { Fail "image locate invalid: $($image.text)" }

    $version = Invoke-WinAgentJson -WinArgs @('version')
    $ocrAvailable = [bool]$version.json.data.ocr_available
    $text = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'text:contains=Agent') -AllowedExitCodes @(0, 1)
    $textSelectorStatus = ''
    if ($text.exit -eq 0) {
        if ($text.json.data.locate_method -ne 'text' -or [int]$text.json.data.match_count -ne 1) { Fail "text selector locate invalid: $($text.text)" }
        if ($text.json.data.matched_text -ne 'Agent' -or $text.json.data.source -ne 'ocr') { Fail "text selector audit fields invalid: $($text.text)" }
        $textSelectorStatus = 'PASS'
    } elseif ($ocrAvailable) {
        if ($text.json.error.code -ne 'LOCATOR_NOT_FOUND') { Fail "Expected LOCATOR_NOT_FOUND with OCR available, got $($text.json.error.code)" }
        $textSelectorStatus = 'LOCATOR_NOT_FOUND'
    } else {
        if ($text.json.error.code -ne 'OCR_UNAVAILABLE' -and $text.json.error.code -ne 'OCR_LANGUAGE_UNAVAILABLE') { Fail "Expected OCR unavailable error, got $($text.json.error.code)" }
        $textSelectorStatus = $text.json.error.code
    }

    @(
        'target_title=Agent Test Window',
        'locate uia:name=Click Me',
        'act uia:name=Click Me click',
        'act uia:type=Edit,index=0 type casehello',
        'wait 300',
        "assert_file_contains $StateFile casehello"
    ) | Set-Content -Encoding UTF8 -LiteralPath $CaseFile
    $case = Invoke-WinAgentJson -WinArgs @('run-case', '--file', $CaseFile, '--report', $CaseReport)
    if ($case.json.ok -ne $true) { Fail "selector case failed: $($case.text)" }

    @'
{
  "version": 1,
  "name": "selector v3.1 task",
  "target": {
    "title": "Agent Test Window",
    "process": "TestWindow.exe"
  },
  "budget": {
    "max_steps": 3,
    "max_duration_ms": 30000,
    "max_recoveries": 0
  },
  "steps": [
    {
      "name": "locate via chain",
      "type": "locate",
      "selector": "chain:uia:automation_id=missing||uia:automation_id=1001"
    }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $TaskFile
    $task = Invoke-WinAgentJson -WinArgs @('run-task', '--file', $TaskFile, '--report', $TaskReport)
    if ($task.json.ok -ne $true -or !(Test-Path -LiteralPath $TaskReport)) { Fail "selector task failed: $($task.text)" }
    $taskReportText = Get-Content -LiteralPath $TaskReport -Raw
    if ($taskReportText -notlike '*fallback_attempts*' -or $taskReportText -notlike '*automation_id=missing*') { Fail "selector task report missing fallback diagnostics" }

    @(
        '# DesktopVisual Selector Selftest',
        '',
        '- Result: PASS',
        '- locate coord: PASS',
        '- locate uia:name: PASS',
        '- locate uia:name_contains,type: PASS',
        '- locate uia:type,index: PASS',
        '- locate uia:automation_id: PASS',
        '- locate uia:class_name with name/type: PASS',
        '- locate relative below anchor: PASS',
        '- locate near_text below text: PASS',
        '- locate fallback chain: PASS',
        '- relative nth required on ambiguity: PASS',
        '- relative nth explicit selection: PASS',
        '- act uia click: PASS',
        '- act uia type: PASS',
        '- missing uia: LOCATOR_NOT_FOUND',
        '- duplicate uia: LOCATOR_NOT_UNIQUE',
        '- missing automation_id: LOCATOR_NOT_FOUND',
        '- image selector: PASS',
        "- text selector: $textSelectorStatus",
        '- case locate/act: PASS',
        '- run-task selector chain report: PASS'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Selector selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
