param(
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
$ExplainReport = Join-Path $Root 'skill_template\win-desktop-agent\scripts\explain-report.ps1'
if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$TestWindowExe = Join-Path $TestRepoRoot 'testwindow\bin\TestWindow.exe'

function Fail($Message) {
    Write-Output "FAIL: $Message"
    exit 1
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )

    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "winagent output was not valid JSON: $output"
    }
    return @{ Exit = $exit; Text = [string]$output; Json = $json }
}

function Ensure-AgentTestWindow {
    $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    if ($find.Exit -eq 0 -and $find.Json.ok -eq $true) {
        return $null
    }

    if (!(Test-Path -LiteralPath $TestWindowExe)) {
        Fail "Agent Test Window was not found and missing $TestWindowExe. Run $Root\build.ps1 first."
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

    Fail 'Agent Test Window did not appear or was not uniquely matched.'
}

function Invoke-ExpectedFailureCase {
    param(
        [string]$CaseFile,
        [string]$ReportFile,
        [string]$ExpectedErrorCode
    )

    $result = Invoke-WinAgentJson -WinArgs @('run-case', '--file', $CaseFile, '--report', $ReportFile) -AllowedExitCodes @(1)
    if ($result.Json.ok -ne $false) {
        Fail "Expected case to fail: $CaseFile"
    }
    if ($result.Json.error.code -ne $ExpectedErrorCode) {
        Fail "Expected $ExpectedErrorCode for $CaseFile, got $($result.Json.error.code)."
    }
    if (!(Test-Path -LiteralPath $ReportFile)) {
        Fail "Missing report: $ReportFile"
    }

    Write-Output "Expected failure: $ExpectedErrorCode"
    & $ExplainReport -ReportFile $ReportFile
    if ($LASTEXITCODE -ne 0) {
        Fail "explain-report.ps1 failed for $ReportFile"
    }
}

function New-CurrentTestRepoCase {
    param(
        [string]$SourceCase,
        [string]$OutputName
    )

    $casePath = Join-Path $Artifacts $OutputName
    ([IO.File]::ReadAllText($SourceCase, [Text.Encoding]::UTF8)).
        Replace('D:\testrepo', $TestRepoRoot) |
        Set-Content -LiteralPath $casePath -Encoding UTF8
    return $casePath
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent. Run $Root\build.ps1 first."
}
if (!(Test-Path -LiteralPath $ExplainReport)) {
    Fail "Missing explain-report.ps1"
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
$failureAssertCase = New-CurrentTestRepoCase `
    -SourceCase (Join-Path $Root 'cases\failure_assert.case') `
    -OutputName 'skill_failure_assert_current.case'

$startedProcess = $null
try {
    $startedProcess = Ensure-AgentTestWindow

    Invoke-ExpectedFailureCase `
        -CaseFile (Join-Path $Root 'cases\failure_window_not_found.case') `
        -ReportFile (Join-Path $Artifacts 'skill_failure_window_not_found_report.md') `
        -ExpectedErrorCode 'WINDOW_NOT_FOUND'

    Invoke-ExpectedFailureCase `
        -CaseFile $failureAssertCase `
        -ReportFile (Join-Path $Artifacts 'skill_failure_assert_report.md') `
        -ExpectedErrorCode 'ASSERTION_FAILED'

    Invoke-ExpectedFailureCase `
        -CaseFile (Join-Path $Root 'cases\failure_invalid_click.case') `
        -ReportFile (Join-Path $Artifacts 'skill_failure_invalid_click_report.md') `
        -ExpectedErrorCode 'INVALID_ARGUMENT'

    Write-Output 'PASS: failure demo observed all expected failures and stopped safely.'
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
