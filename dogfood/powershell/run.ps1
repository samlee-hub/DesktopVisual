param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\powershell\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\powershell\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded local PowerShell read-only/test dogfood task.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\powershell'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0

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

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'PowerShell'
        task_id = 'powershell'
        status = $script:status
        reason = $script:reason
        steps = $script:steps
        duration_ms = $duration
        locators = (($script:locators | Select-Object -Unique) -join ',')
        screenshots = @($script:screenshots)
        report_path = $ReportOut
        safety_boundary = 'Local non-admin read-only/test commands only; generated output under artifacts\dogfood\powershell.'
        expected_result = 'Generated command output is readable through winagent read-file.'
        skipped_condition = 'PowerShell execution or read-file allowlist is unavailable.'
    }
    $result | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $ReportOut -Encoding utf8
    return $result
}

try {
    $outputFile = Join-Path $Artifacts 'readonly_command_output.txt'
    $payload = [PSCustomObject]@{
        marker = "DV_DOGFOOD_POWERSHELL_$([Guid]::NewGuid().ToString('N'))"
        pwd = (Get-Location).Path
        ps_version = $PSVersionTable.PSVersion.ToString()
        root_exists = (Test-Path -LiteralPath $Root)
    }
    $payload | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $outputFile -Encoding UTF8
    Add-Step

    $read = Invoke-AgentJson -WinArgs @('read-file', '--path', $outputFile) -AllowedExitCodes @(0, 1)
    if ($read.exit -ne 0 -or -not $read.json.ok) {
        Skip "read-file could not read generated PowerShell output: $($read.json.error.code)"
    }
    if ($read.json.data.content -notmatch [regex]::Escape($payload.marker)) {
        Fail 'read-file output did not contain the generated marker.'
    }

    $locators.Add('read-file')
    Write-Host '  PowerShell read-only/test command PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  PowerShell dogfood $status : $reason"
}

Write-Result
