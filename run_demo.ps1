param(
    [string]$Root = '',
    [switch]$Help,
    [switch]$Visible,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\run_demo.ps1 [-Root <path>] [-Visible] [-SkipBuild]'
    Write-Host 'Builds and runs the TestWindow demo case.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$BeforeBmp = if ($Visible) { Join-Path $Root 'artifacts\visible_before.bmp' } else { Join-Path $Root 'artifacts\before.bmp' }
$SourceCaseFile = if ($Visible) { Join-Path $Root 'cases\visible_action.case' } else { Join-Path $Root 'cases\basic_click.case' }
$CaseFile = if ($Visible) { Join-Path $Root 'artifacts\visible_action_current.case' } else { Join-Path $Root 'artifacts\basic_click_current.case' }
$Report = if ($Visible) { Join-Path $Root 'artifacts\visible_action_report.md' } else { Join-Path $Root 'artifacts\basic_click_report.md' }

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) {
        Stop-Process -Id $_.Id -Force
    }
}

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root -TestRepoRoot $TestRepoRoot
}

if (!(Test-Path $TestWindowExe)) {
    throw "Missing $TestWindowExe after build."
}

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'artifacts') | Out-Null
([IO.File]::ReadAllText($SourceCaseFile, [Text.Encoding]::UTF8)).
    Replace('D:\testrepo', $TestRepoRoot) |
    Set-Content -LiteralPath $CaseFile -Encoding UTF8

Start-Process -FilePath $TestWindowExe | Out-Null
Write-Host 'Started TestWindow.exe.'

$deadline = (Get-Date).AddSeconds(10)
do {
    Start-Sleep -Milliseconds 250
    & $WinAgent find --title 'Agent Test Window' | Out-Null
    $foundExit = $LASTEXITCODE
} while ($foundExit -ne 0 -and (Get-Date) -lt $deadline)

if ($foundExit -ne 0) {
    throw 'Agent Test Window did not appear or was not uniquely matched within 10 seconds.'
}

Write-Host '== windows =='
& $WinAgent windows

Write-Host '== find =='
& $WinAgent find --title 'Agent Test Window'

Write-Host '== screenshot before =='
& $WinAgent screenshot --title 'Agent Test Window' --out $BeforeBmp
if ($LASTEXITCODE -ne 0) {
    throw "screenshot failed with exit code $LASTEXITCODE"
}

Write-Host '== run-case =='
& $WinAgent run-case --file $CaseFile --report $Report
if ($LASTEXITCODE -ne 0) {
    throw "run-case failed with exit code $LASTEXITCODE. Report: $Report"
}

Write-Host "Report: $Report"
Write-Host 'TestWindow.exe is still running for inspection.'
