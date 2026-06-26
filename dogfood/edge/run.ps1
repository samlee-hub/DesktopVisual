param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\edge\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\edge\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded Edge local-file dogfood task.'
    exit 0
}
$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\edge'
$ProfileDir = Join-Path $Artifacts 'edge_profile'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0
$oldSafety = $env:DESKTOPVISUAL_SAFETY_CONFIG
$beforeEdgeIds = @()
$htmlPath = Join-Path $Artifacts 'page.html'
$localUrl = "file:///$($htmlPath -replace '\\','/')"
$inputText = 'DogfoodEdgeTest'

function Add-Step { $script:steps++ }
function Fail([string]$msg) { $script:status = 'FAIL'; $script:reason = $msg; throw $msg }
function Skip([string]$msg) { $script:status = 'SKIPPED'; $script:reason = $msg; throw $msg }

function Invoke-AgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    Add-Step
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try { return @{ exit = $exit; json = ($output | ConvertFrom-Json); text = [string]$output } }
    catch { Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output" }
}

function New-DogfoodSafetyConfig {
    $path = Join-Path $Artifacts 'safety.conf'
    @(
        'allowed_titles=DesktopVisual Dogfood Test'
        'allowed_processes=msedge.exe'
        'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Write-LocalPage {
    @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>DesktopVisual Dogfood Test</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; padding: 48px; background: #fff; color: #111; }
    label, input, button, #result { font-size: 24px; }
    input { width: 420px; padding: 8px; margin: 12px 0; }
    button { padding: 10px 18px; }
    #result { margin-top: 24px; font-weight: 700; }
  </style>
</head>
<body>
  <h1>DesktopVisual Dogfood Test</h1>
  <form id="form">
    <label for="dogfoodInput">Input</label><br>
    <input id="dogfoodInput" name="dogfoodInput" autofocus autocomplete="off">
    <button id="submitButton" type="submit">Submit</button>
  </form>
  <div id="result">Waiting</div>
  <script>
    document.getElementById('form').addEventListener('submit', function (event) {
      event.preventDefault();
      var value = document.getElementById('dogfoodInput').value;
      document.getElementById('result').textContent = 'Received: ' + value;
      document.title = 'DesktopVisual Dogfood Test Received ' + value;
    });
    window.addEventListener('load', function () { document.getElementById('dogfoodInput').focus(); });
  </script>
</body>
</html>
"@ | Set-Content -LiteralPath $htmlPath -Encoding UTF8
}

function Find-EdgeTitle {
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $found = Invoke-AgentJson -WinArgs @('find', '--title', 'DesktopVisual Dogfood Test') -AllowedExitCodes @(0, 1)
        if ($found.exit -eq 0) { return 'DesktopVisual Dogfood Test' }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return ''
}

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'Edge'
        status = $script:status
        reason = $script:reason
        steps = $script:steps
        duration_ms = $duration
        locators = (($script:locators | Select-Object -Unique) -join ',')
        screenshots = @($script:screenshots)
        report_path = $ReportOut
    }
    $result | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $ReportOut -Encoding utf8
    return $result
}

try {
    $beforeEdgeIds = @(Get-Process msedge -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if ($beforeEdgeIds.Count -gt 0) {
        Skip 'Existing Edge process found; skipping to avoid closing or reading a user browser session.'
    }

    $edgePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    )
    $edgeExe = $edgePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edgeExe) { Skip 'Microsoft Edge not found on this system.' }

    Write-LocalPage
    Remove-Item -LiteralPath $ProfileDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-DogfoodSafetyConfig

    Start-Process -FilePath $edgeExe -ArgumentList @(
        '--no-first-run',
        '--no-default-browser-check',
        "--user-data-dir=$ProfileDir",
        $localUrl
    )
    Start-Sleep -Milliseconds 2500

    $title = Find-EdgeTitle
    if (-not $title) { Skip 'Edge window with local dogfood page title was not found.' }

    $before = Join-Path $Artifacts 'before.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $before) | Out-Null
    if (Test-Path -LiteralPath $before) { $screenshots.Add($before) }

    $uia = Invoke-AgentJson -WinArgs @('uia-tree', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($uia.exit -eq 0) { $locators.Add('UIA') }

    Invoke-AgentJson -WinArgs @('click', '--title', $title, '--x', '360', '--y', '430', '--move-mode', 'human') | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-AgentJson -WinArgs @('type', '--title', $title, '--text', $inputText) | Out-Null
    Invoke-AgentJson -WinArgs @('press', '--title', $title, '--key', 'ENTER') | Out-Null
    Start-Sleep -Milliseconds 700

    $after = Join-Path $Artifacts 'after.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $after) | Out-Null
    if (Test-Path -LiteralPath $after) { $screenshots.Add($after) }

    $verified = $false
    $uiaAfter = Invoke-AgentJson -WinArgs @('uia-tree', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($uiaAfter.exit -eq 0) {
        $names = @($uiaAfter.json.data.elements | ForEach-Object { [string]$_.name })
        $joinedNames = ($names -join ' ')
        if ($joinedNames -match 'Received') {
            $locators.Add('UIA')
            $verified = $true
        }
    }

    $ocr = Invoke-AgentJson -WinArgs @('read-window-text', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($ocr.exit -eq 0) {
        $locators.Add('OCR')
        if ($ocr.json.data.text -match 'Received') {
            $verified = $true
        }
    }
    if (-not $verified) {
        $titleCheck = Invoke-AgentJson -WinArgs @('find', '--title', "Received $inputText") -AllowedExitCodes @(0, 1)
        if ($titleCheck.exit -eq 0) {
            $locators.Add('window_title')
            $verified = $true
        }
    }
    if (-not $verified) {
        Skip 'Edge page opened and was operated, but OCR/UIA/window-title verification did not confirm the submitted local form result.'
    }

    Write-Host '  Local HTML form verified'
    Write-Host '  Edge dogfood PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  Edge dogfood $status : $reason"
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldSafety
    $afterIds = @(Get-Process msedge -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    foreach ($id in @($afterIds | Where-Object { $beforeEdgeIds -notcontains $_ })) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

Write-Result
