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
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'focus_selftest_report.md'

function Fail($Message) {
    throw $Message
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
        Fail "Output was not valid JSON: $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $click = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90')
    if ($click.json.ok -ne $true) { Fail "Expected TestWindow click to succeed: $($click.text)" }
    if ($click.json.data.focus_verified -ne $true) { Fail "Expected click focus_verified=true: $($click.text)" }

    $missing = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Definitely Missing Agent Test Window', '--x', '80', '--y', '90') -AllowedExitCodes @(1)
    if ($missing.json.error.code -ne 'WINDOW_NOT_FOUND' -and $missing.json.error.code -ne 'WINDOW_FOCUS_FAILED') {
        Fail "Expected WINDOW_NOT_FOUND or WINDOW_FOCUS_FAILED, got $($missing.json.error.code)"
    }

    @(
        '# DesktopVisual Focus Selftest',
        '',
        '- Result: PASS',
        '- Normal TestWindow click: PASS',
        "- Missing window error: $($missing.json.error.code)",
        '- Focus verified field: PASS'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Focus selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
