param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\run_uia_demo.ps1'
    Write-Host 'Builds and runs the TestWindow UI Automation demo case.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$CaseFile = Join-Path $Root 'cases\uia_action.case'
$ReportFile = Join-Path $Root 'artifacts\uia_action_report.md'

function Fail($Message) {
    Write-Host "FAIL: $Message"
    exit 1
}

& (Join-Path $Root 'build.ps1')
if ($LASTEXITCODE -ne 0) {
    Fail "build.ps1 failed with exit $LASTEXITCODE"
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent"
}
if (!(Test-Path -LiteralPath $TestWindowExe)) {
    Fail "Missing $TestWindowExe"
}
if (!(Test-Path -LiteralPath $CaseFile)) {
    Fail "Missing $CaseFile"
}

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) {
        Stop-Process -Id $_.Id -Force
    }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = & $WinAgent find --title 'Agent Test Window'
        $findExit = $LASTEXITCODE
    } while ($findExit -ne 0 -and (Get-Date) -lt $deadline)

    if ($findExit -ne 0) {
        Fail 'Agent Test Window did not appear.'
    }

    Write-Host "Running UIA action case: $CaseFile"
    $output = & $WinAgent run-case --file $CaseFile --report $ReportFile
    $exit = $LASTEXITCODE
    Write-Output $output
    if ($exit -ne 0) {
        Fail "uia_action.case failed with exit $exit"
    }

    if (!(Test-Path -LiteralPath $ReportFile)) {
        Fail "Missing report: $ReportFile"
    }

    Write-Host "Report: $ReportFile"
    Write-Host 'PASS: UIA action demo passed.'
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
    }
}
