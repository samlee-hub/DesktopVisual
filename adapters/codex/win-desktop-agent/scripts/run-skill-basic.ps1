param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$SourceCaseFile = Join-Path $Root 'cases\case_v2_expect_success.case'
$CaseFile = Join-Path $Root 'artifacts\skill_basic_current.case'
$ReportFile = Join-Path $Root 'artifacts\skill_basic_report.md'
$ReadLatestReport = Join-Path $Root 'skill_template\win-desktop-agent\scripts\read-latest-report.ps1'
if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$TestWindowExe = Join-Path $TestRepoRoot 'testwindow\bin\TestWindow.exe'

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )

    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        throw "winagent output was not valid JSON: $output"
    }
    return @{ Exit = $exit; Text = [string]$output; Json = $json }
}

function Ensure-AgentTestWindow {
    $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    if ($find.Exit -eq 0 -and $find.Json.ok -eq $true) {
        return $null
    }

    if (!(Test-Path -LiteralPath $TestWindowExe)) {
        throw "Agent Test Window was not found and missing $TestWindowExe. Run $Root\build.ps1 first."
    }

    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
        if ($find.Exit -eq 0 -and $find.Json.ok -eq $true) {
            return $proc
        }
    } while ((Get-Date) -lt $deadline)

    throw 'Agent Test Window did not appear or was not uniquely matched.'
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}
if (!(Test-Path -LiteralPath $SourceCaseFile)) {
    throw "Missing skill basic case: $SourceCaseFile"
}
if (!(Test-Path -LiteralPath $ReadLatestReport)) {
    throw "Missing report reader: $ReadLatestReport"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportFile) | Out-Null
([IO.File]::ReadAllText($SourceCaseFile, [Text.Encoding]::UTF8)).Replace('D:\testrepo', $TestRepoRoot) |
    Set-Content -LiteralPath $CaseFile -Encoding UTF8

$startedProcess = $null
try {
    $startedProcess = Ensure-AgentTestWindow
    Write-Host "Running Skill basic case: $CaseFile"
    & $WinAgent run-case --file $CaseFile --report $ReportFile
    $exit = $LASTEXITCODE
    Write-Host "Report: $ReportFile"
    if ($exit -ne 0) {
        exit $exit
    }

    & $ReadLatestReport -Lines 40
    exit $LASTEXITCODE
}
finally {
    if ($startedProcess -and !$startedProcess.HasExited) {
        $startedProcess.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$startedProcess.HasExited) {
            Stop-Process -Id $startedProcess.Id -Force
        }
    }
}
