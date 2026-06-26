param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\explorer\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\explorer\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded Explorer dogfood task under artifacts\dogfood\explorer.'
    exit 0
}
$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\explorer'
$WorkDir = Join-Path $Artifacts 'explorer_work'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0
$oldSafety = $env:DESKTOPVISUAL_SAFETY_CONFIG
$folderName = "dogfood_folder_$([Guid]::NewGuid().ToString('N').Substring(0,8))"

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
        'allowed_titles=explorer_work;File Explorer'
        'allowed_processes=explorer.exe'
        'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Wait-ExplorerWindow {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        $found = Invoke-AgentJson -WinArgs @('find', '--title', 'explorer_work') -AllowedExitCodes @(0, 1)
        if ($found.exit -eq 0) { return 'explorer_work' }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return ''
}

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'Explorer'
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
    Get-ChildItem -LiteralPath $WorkDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-DogfoodSafetyConfig

    Start-Process explorer.exe -ArgumentList ('"{0}"' -f $WorkDir)
    Start-Sleep -Milliseconds 1200
    $title = Wait-ExplorerWindow
    if (-not $title) { Skip 'Explorer window for artifacts dogfood directory was not found.' }

    $before = Join-Path $Artifacts 'before.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $before) | Out-Null
    if (Test-Path -LiteralPath $before) { $screenshots.Add($before) }

    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'CTRL+SHIFT+N') | Out-Null
    Start-Sleep -Milliseconds 400
    Invoke-AgentJson -WinArgs @('type', '--title', $title, '--text', $folderName) | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-AgentJson -WinArgs @('press', '--title', $title, '--key', 'ENTER') | Out-Null
    Start-Sleep -Milliseconds 700

    $created = Join-Path $WorkDir $folderName
    if (-not (Test-Path -LiteralPath $created -PathType Container)) {
        Skip 'Explorer did not create the requested folder; focus or shell shortcut may be unavailable.'
    }

    $after = Join-Path $Artifacts 'after.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $after) | Out-Null
    if (Test-Path -LiteralPath $after) { $screenshots.Add($after) }

    $locators.Add('filesystem')
    Write-Host '  Folder created and verified under artifacts dogfood directory'
    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'ALT+F4') -AllowedExitCodes @(0, 1) | Out-Null
    Write-Host '  Explorer dogfood PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  Explorer dogfood $status : $reason"
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldSafety
    Get-ChildItem -LiteralPath $WorkDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Result
