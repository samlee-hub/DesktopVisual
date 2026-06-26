param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev_post_v6_runtime_ux_optimization'
$Report = Join-Path $ArtifactDir 'foreground_preparation_report.md'
$Shot = Join-Path $ArtifactDir 'foreground_preparation_target.bmp'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON from $($WinArgs -join ' '): $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 200
    if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $prep = Invoke-WinAgentJson -WinArgs @('prepare-foreground', '--title', 'Agent Test Window', '--timeout-ms', '2500')
    if ($prep.json.ok -ne $true) { Fail "prepare-foreground failed: $($prep.text)" }
    if ($prep.json.data.target_foreground_after -ne $true) { Fail 'prepare-foreground did not make target foreground.' }
    if ($prep.json.data.target_visible_after -ne $true) { Fail 'prepare-foreground did not verify target visibility.' }
    if ($prep.json.data.backend_fallback_used -ne $false) { Fail 'foreground preparation must not use backend fallback for visible TestWindow.' }
    if ($null -eq $prep.json.data.agent_host_detected) { Fail 'foreground preparation missing agent_host_detected field.' }

    $shotResult = Invoke-WinAgentJson -WinArgs @('screenshot', '--title', 'Agent Test Window', '--out', $Shot)
    $fileDeadline = (Get-Date).AddSeconds(2)
    while (-not (Test-Path -LiteralPath $Shot) -and (Get-Date) -lt $fileDeadline) {
        Start-Sleep -Milliseconds 100
    }
    $shotOk = [bool]$shotResult.json.ok
    $shotExists = Test-Path -LiteralPath $Shot
    if ((-not $shotOk) -or (-not $shotExists)) { Fail "screenshot after foreground preparation failed: $($shotResult.text)" }
    if ($shotResult.json.data.foreground_preparation.target_foreground_after -ne $true) { Fail 'screenshot did not run foreground preparation.' }
    if ($shotResult.json.target.title -notmatch 'Agent Test Window') { Fail "screenshot target was not TestWindow: $($shotResult.text)" }

    @(
        '# Foreground Preparation Selftest',
        '',
        '- Result: PASS',
        '- cli_terminal_foreground_detection_field_present: true',
        '- prepare_foreground_for_visible_ui_task: PASS',
        '- target_window_becomes_foreground: true',
        '- screenshot_target_is_not_cli: true',
        '- backend_fallback_used: false'
    ) | Set-Content -LiteralPath $Report -Encoding UTF8

    Write-Host 'FOREGROUND_PREPARATION_SELFTEST_PASS'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
