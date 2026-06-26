param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\notepad\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\notepad\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded Notepad dogfood task against a generated sample file.'
    exit 0
}
$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\notepad'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0
$marker = "DV_DOGFOOD_NOTEPAD_$([Guid]::NewGuid().ToString('N'))"
$sampleFile = Join-Path $Artifacts 'notepad_dogfood.txt'
$oldSafety = $env:DESKTOPVISUAL_SAFETY_CONFIG
$startedIds = @()

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
        'allowed_titles='
        'allowed_processes=notepad.exe;ApplicationFrameHost.exe'
        'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Find-NotepadTitle {
    $deadline = (Get-Date).AddSeconds(10)
    $sampleName = Split-Path -Leaf $sampleFile
    do {
        $windows = Invoke-AgentJson -WinArgs @('windows') -AllowedExitCodes @(0, 1)
        if ($windows.exit -eq 0) {
            $candidate = @($windows.json.windows | Where-Object { $_.title -and $_.title -match [regex]::Escape($sampleName) }) | Select-Object -First 1
            if ($candidate) { return [string]$candidate.title }
        }
        foreach ($candidateTitle in @($sampleName, 'Notepad')) {
            $found = Invoke-AgentJson -WinArgs @('find', '--title', $candidateTitle) -AllowedExitCodes @(0, 1)
            if ($found.exit -eq 0) { return $candidateTitle }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return ''
}

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'Notepad'
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
    $existing = @(Get-Process notepad -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Skip 'Existing Notepad process found; skipping to avoid typing into or closing a user file.'
    }

    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-DogfoodSafetyConfig
    '' | Set-Content -LiteralPath $sampleFile -Encoding UTF8
$proc = Start-Process notepad.exe -ArgumentList ('"{0}"' -f $sampleFile) -PassThru
    $startedIds += $proc.Id
    Start-Sleep -Milliseconds 800

    $title = Find-NotepadTitle
    if (-not $title) { Skip 'Notepad did not open the artifacts temp file.' }
    if ($title -notmatch [regex]::Escape((Split-Path -Leaf $sampleFile))) {
        Skip "Notepad opened a different document ('$title'); skipping to avoid user-file input."
    }

    $before = Join-Path $Artifacts 'before.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $before) | Out-Null
    if (Test-Path -LiteralPath $before) { $screenshots.Add($before) }

    $uia = Invoke-AgentJson -WinArgs @('uia-tree', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($uia.exit -eq 0) { $locators.Add('UIA') }

    $typed = Invoke-AgentJson -WinArgs @('type', '--title', $title, '--text', $marker) -AllowedExitCodes @(0, 1)
    if ($typed.exit -ne 0 -or -not $typed.json.ok) {
        Fail "Type failed: $($typed.json.error.code) $($typed.json.error.message)"
    }

    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'CTRL+S') | Out-Null
    Start-Sleep -Milliseconds 500

    $content = Get-Content -LiteralPath $sampleFile -Raw
    if ($content -notmatch [regex]::Escape($marker)) {
        Fail 'Saved temp file did not contain the typed marker.'
    }

    $after = Join-Path $Artifacts 'after.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $after) | Out-Null
    if (Test-Path -LiteralPath $after) { $screenshots.Add($after) }

    Write-Host '  File verification PASS'
    Write-Host '  Notepad dogfood PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  Notepad dogfood $status : $reason"
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldSafety
    foreach ($id in $startedIds) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

Write-Result
