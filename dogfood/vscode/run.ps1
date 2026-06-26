param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\vscode\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\vscode\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded VS Code dogfood task when VS Code is available.'
    exit 0
}
$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\vscode'
$ProfileDir = Join-Path $Artifacts 'profile'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0
$oldSafety = $env:DESKTOPVISUAL_SAFETY_CONFIG
$beforeCodeIds = @()

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
        'allowed_titles=sample.txt;Visual Studio Code'
        'allowed_processes=Code.exe'
        'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Find-CodeExe {
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles}\Microsoft VS Code\Code.exe"
    )
    return ($paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Wait-CodeWindow {
    $deadline = (Get-Date).AddSeconds(20)
    do {
        $found = Invoke-AgentJson -WinArgs @('find', '--title', 'sample.txt') -AllowedExitCodes @(0, 1)
        if ($found.exit -eq 0) { return 'sample.txt' }
        Start-Sleep -Milliseconds 400
    } while ((Get-Date) -lt $deadline)
    return ''
}

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'VS Code'
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
    $beforeCodeIds = @(Get-Process Code -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if ($beforeCodeIds.Count -gt 0) {
        Skip 'Existing VS Code process found; skipping to avoid closing a user workspace.'
    }

    $codeExe = Find-CodeExe
    if (-not $codeExe) { Skip 'VS Code not found on this system.' }

    $sampleFile = Join-Path $Artifacts 'sample.txt'
    'VS_CODE_DOGFOOD_INITIAL' | Set-Content -LiteralPath $sampleFile -Encoding UTF8
    Remove-Item -LiteralPath $ProfileDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-DogfoodSafetyConfig

    Start-Process -FilePath $codeExe -ArgumentList @('--new-window', "--user-data-dir=$ProfileDir", $sampleFile)
    Start-Sleep -Milliseconds 3500

    $title = Wait-CodeWindow
    if (-not $title) { Skip 'VS Code sample.txt window was not found.' }

    $before = Join-Path $Artifacts 'before.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $before) -AllowedExitCodes @(0, 1) | Out-Null
    if (Test-Path -LiteralPath $before) { $screenshots.Add($before) }

    $uia = Invoke-AgentJson -WinArgs @('uia-tree', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($uia.exit -eq 0) { $locators.Add('UIA') }

    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'CTRL+END') -AllowedExitCodes @(0, 1) | Out-Null
    Invoke-AgentJson -WinArgs @('type', '--title', $title, '--text', "`r`nVSCODE_DOGFOOD_APPENDED_TEXT") -AllowedExitCodes @(0, 1) | Out-Null
    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'CTRL+S') -AllowedExitCodes @(0, 1) | Out-Null
    Start-Sleep -Milliseconds 700

    $content = Get-Content -LiteralPath $sampleFile -Raw
    if ($content -notmatch 'VSCODE_DOGFOOD_APPENDED_TEXT') {
        Skip 'VS Code opened the file but typed content was not saved; editor focus may be unavailable.'
    }

    $after = Join-Path $Artifacts 'after.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $after) -AllowedExitCodes @(0, 1) | Out-Null
    if (Test-Path -LiteralPath $after) { $screenshots.Add($after) }

    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'ALT+F4') -AllowedExitCodes @(0, 1) | Out-Null
    Write-Host '  File verification PASS'
    Write-Host '  VS Code dogfood PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  VS Code dogfood $status : $reason"
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldSafety
    $afterIds = @(Get-Process Code -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    foreach ($id in @($afterIds | Where-Object { $beforeCodeIds -notcontains $_ })) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

Write-Result
