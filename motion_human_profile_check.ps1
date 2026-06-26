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
$Profile = Join-Path $Root 'config\operator_motion_profile.json'
$Report = Join-Path $Root 'artifacts\motion_profile\human_profile_check_report.md'
$ValidationReport = Join-Path $Root 'artifacts\motion_profile\human\validation_report.md'

function Write-Report([string]$Status, [string[]]$Lines) {
    $dir = Split-Path -Parent $Report
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    @(
        '# DesktopVisual Human Motion Profile Check',
        '',
        "- Result: $Status"
    ) + $Lines | Set-Content -LiteralPath $Report -Encoding UTF8
    Write-Host "$Status`: $($Lines -join ' ') "
    Write-Host "Report: $Report"
}

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    return @{ exit = $exit; text = [string]$output; json = ($output | ConvertFrom-Json) }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
}

if (!(Test-Path -LiteralPath $Profile)) {
    Write-Report 'SKIPPED' @('- reason: config\operator_motion_profile.json does not exist; run motion_calibration_session.ps1 to create a human profile.')
    exit 0
}

$info = Invoke-WinAgentJson -WinArgs @('motion-profile-info', '--profile', $Profile) -AllowedExitCodes @(0, 1)
if ($info.json.ok -ne $true -or $info.json.data.exists -ne $true) {
    Write-Report 'FAIL' @("- reason: motion-profile-info failed or did not find profile", "- output: $($info.text)")
    exit 1
}
if ($info.json.data.source -ne 'human') {
    Write-Report 'FAIL' @("- reason: profile source is not human", "- source: $($info.json.data.source)")
    exit 1
}
if ([int]$info.json.data.sample_count -lt 12) {
    Write-Report 'FAIL' @("- reason: human profile has fewer than 12 samples", "- sample_count: $($info.json.data.sample_count)")
    exit 1
}
if (@('low','usable','good') -notcontains [string]$info.json.data.quality) {
    Write-Report 'FAIL' @("- reason: invalid quality", "- quality: $($info.json.data.quality)")
    exit 1
}

$validation = Invoke-WinAgentJson -WinArgs @('motion-profile-validate', '--profile', $Profile, '--out', $ValidationReport) -AllowedExitCodes @(0, 1)
if ($validation.json.ok -ne $true -and !$validation.json.data.warnings) {
    Write-Report 'FAIL' @("- reason: validation failed without actionable warnings", "- output: $($validation.text)")
    exit 1
}

if (!(Test-Path -LiteralPath $TestWindowExe)) {
    Write-Report 'FAIL' @("- reason: missing TestWindow executable", "- path: $TestWindowExe")
    exit 1
}

Stop-TestWindow
$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) {
        Write-Report 'FAIL' @('- reason: Agent Test Window did not appear.')
        exit 1
    }

    $click = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'operator-human')
    if ($click.json.data.move_profile -ne 'operator-human' -or $click.json.data.operator_profile_source -ne 'human') {
        Write-Report 'FAIL' @("- reason: operator-human did not use human profile", "- output: $($click.text)")
        exit 1
    }
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}

Write-Report 'PASS' @(
    "- profile: $Profile",
    "- source: human",
    "- sample_count: $($info.json.data.sample_count)",
    "- quality: $($info.json.data.quality)",
    "- validation: $($validation.json.data.result)",
    '- operator-human click: PASS'
)
exit 0
