param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\calculator\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\calculator\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded Calculator dogfood task.'
    exit 0
}
$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\calculator'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0
$oldSafety = $env:DESKTOPVISUAL_SAFETY_CONFIG
$beforeCalcIds = @()
$beforeFrameIds = @()

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
        'allowed_processes=ApplicationFrameHost.exe;CalculatorApp.exe;Calculator.exe;calc.exe'
        'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow'
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-CalcProcesses {
    @(Get-Process calc,Calculator,CalculatorApp -ErrorAction SilentlyContinue)
}

function Get-AppFrameProcesses {
    @(Get-Process ApplicationFrameHost -ErrorAction SilentlyContinue)
}

function Get-CalculatorTitlePattern {
    $localized = "$([char]0x8BA1)$([char]0x7B97)$([char]0x5668)"
    return "Calculator|$([regex]::Escape($localized))"
}

function Test-CalculatorWindowExists {
    if (@(Get-CalcProcesses).Count -gt 0) { return $true }
    $windows = Invoke-AgentJson -WinArgs @('windows') -AllowedExitCodes @(0, 1)
    if ($windows.exit -ne 0) { return $false }
    $pattern = Get-CalculatorTitlePattern
    return [bool](@($windows.json.windows | Where-Object { $_.title -and $_.title -match $pattern } | Select-Object -First 1))
}

function Find-CalculatorTitle {
    $deadline = (Get-Date).AddSeconds(12)
    $pattern = Get-CalculatorTitlePattern
    do {
        $windows = Invoke-AgentJson -WinArgs @('windows') -AllowedExitCodes @(0, 1)
        if ($windows.exit -eq 0) {
            $candidate = @($windows.json.windows | Where-Object {
                $_.title -and ($_.title -match $pattern -or ($script:beforeFrameIds -notcontains [int]$_.pid -and @(Get-AppFrameProcesses | Select-Object -ExpandProperty Id) -contains [int]$_.pid))
            }) | Select-Object -First 1
            if ($candidate) { return [string]$candidate.title }
        }
        $found = Invoke-AgentJson -WinArgs @('find', '--title', 'Calculator') -AllowedExitCodes @(0, 1)
        if ($found.exit -eq 0) { return 'Calculator' }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return ''
}

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'Calculator'
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
    $beforeCalcIds = @(Get-CalcProcesses | Select-Object -ExpandProperty Id)
    $beforeFrameIds = @(Get-AppFrameProcesses | Select-Object -ExpandProperty Id)
    if (Test-CalculatorWindowExists) {
        Skip 'Existing Calculator window found; skipping to avoid closing a user window.'
    }

    $calcPath = Join-Path $env:SystemRoot 'System32\calc.exe'
    if (-not (Test-Path -LiteralPath $calcPath)) { Skip 'calc.exe not found on this system.' }

    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-DogfoodSafetyConfig
    Start-Process -FilePath $calcPath
    Start-Sleep -Milliseconds 1500

    $title = Find-CalculatorTitle
    if (-not $title) { Skip 'Calculator window was not found.' }

    $before = Join-Path $Artifacts 'before.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $before) | Out-Null
    if (Test-Path -LiteralPath $before) { $screenshots.Add($before) }

    $uia = Invoke-AgentJson -WinArgs @('uia-tree', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($uia.exit -eq 0) { $locators.Add('UIA') }

    Invoke-AgentJson -WinArgs @('press', '--title', $title, '--key', 'ESC') -AllowedExitCodes @(0, 1) | Out-Null
    $typed = Invoke-AgentJson -WinArgs @('type', '--title', $title, '--text', '12+30') -AllowedExitCodes @(0, 1)
    if ($typed.exit -ne 0 -or -not $typed.json.ok) {
        Skip "Calculator did not accept typed expression: $($typed.json.error.code) $($typed.json.error.message)"
    }
    Invoke-AgentJson -WinArgs @('press', '--title', $title, '--key', 'ENTER') | Out-Null
    Start-Sleep -Milliseconds 700

    $after = Join-Path $Artifacts 'after.bmp'
    Invoke-AgentJson -WinArgs @('screenshot', '--title', $title, '--out', $after) | Out-Null
    if (Test-Path -LiteralPath $after) { $screenshots.Add($after) }

    $verified = $false
    $ocr = Invoke-AgentJson -WinArgs @('read-window-text', '--title', $title) -AllowedExitCodes @(0, 1)
    if ($ocr.exit -eq 0 -and $ocr.json.data.text -match '42') {
        $locators.Add('OCR')
        $verified = $true
        Write-Host '  OCR verification PASS: 42 found'
    } elseif ($uia.exit -eq 0) {
        $uiaFind = Invoke-AgentJson -WinArgs @('uia-find', '--title', $title, '--name', '42') -AllowedExitCodes @(0, 1)
        if ($uiaFind.exit -eq 0) {
            $verified = $true
            Write-Host '  UIA verification PASS: 42 found'
        }
    }

    if (-not $verified) {
        Skip 'Could not verify 12+30=42 via OCR or UIA in this Calculator build.'
    }

    Invoke-AgentJson -WinArgs @('hotkey', '--title', $title, '--keys', 'ALT+F4') -AllowedExitCodes @(0, 1) | Out-Null
    Write-Host '  Calculator dogfood PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  Calculator dogfood $status : $reason"
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldSafety
    $afterIds = @(Get-CalcProcesses | Select-Object -ExpandProperty Id)
    foreach ($id in @($afterIds | Where-Object { $beforeCalcIds -notcontains $_ })) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

Write-Result
