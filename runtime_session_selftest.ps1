param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.2.0_persistent_runtime_session_latency_gate'
$RawRoot = Join-Path $ArtifactRoot 'raw\runtime_session_selftest'
$ReportPath = Join-Path $ArtifactRoot 'runtime_session_selftest_report.md'
$ResultPath = Join-Path $ArtifactRoot 'runtime_session_selftest_result.json'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Fail([string]$Message) {
    throw $Message
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try {
        $json = $text | ConvertFrom-Json
    } catch {
        Fail "winagent $($WinArgs -join ' ') did not return JSON: $text"
    }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $WinArgs }
}

function Assert-SessionEnvelope($Result, [string]$Command) {
    if ($Result.json.command -ne $Command) { Fail "$Command missing command field." }
    if ($null -eq $Result.json.ok) { Fail "$Command missing ok." }
    if (-not $Result.json.timestamp) { Fail "$Command missing timestamp." }
    if ($null -eq $Result.json.duration_ms) { Fail "$Command missing duration_ms." }
    if ($null -eq $Result.json.data) { Fail "$Command missing data." }
    if ($Result.json.PSObject.Properties.Name -notcontains 'session_id') { Fail "$Command missing top-level session_id." }
    if ($Result.json.PSObject.Properties.Name -notcontains 'session_alive') { Fail "$Command missing top-level session_alive." }
    if ($Result.json.PSObject.Properties.Name -notcontains 'session_status') { Fail "$Command missing top-level session_status." }
    if ($Result.json.PSObject.Properties.Name -notcontains 'error') { Fail "$Command missing top-level error." }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 200
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'Agent Test Window', '--process', 'TestWindow.exe')
    Assert-SessionEnvelope $start 'runtime-session-start'
    if ($start.json.ok -ne $true -or $start.json.data.session_created -ne $true) { Fail 'runtime-session-start did not create a live session.' }
    $sessionId = [string]$start.json.session_id
    if ([string]::IsNullOrWhiteSpace($sessionId)) { Fail 'session_id is empty.' }

    $status = Invoke-WinAgentJson -WinArgs @('runtime-session-status', '--session-id', $sessionId)
    Assert-SessionEnvelope $status 'runtime-session-status'
    if ($status.json.data.session_status_ok -ne $true) { Fail 'runtime-session-status was not ok.' }

    $observe = Invoke-WinAgentJson -WinArgs @('runtime-session-observe', '--session-id', $sessionId, '--screenshot', 'false', '--uia', 'true')
    Assert-SessionEnvelope $observe 'runtime-session-observe'
    if ($observe.json.data.session_observe_ok -ne $true) { Fail 'runtime-session-observe was not ok.' }

    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId)
    Assert-SessionEnvelope $close 'runtime-session-close'
    if ($close.json.data.session_closed -ne $true) { Fail 'runtime-session-close did not close the session.' }

    $closed = Invoke-WinAgentJson -WinArgs @('runtime-session-command', '--session-id', $sessionId, '--action', 'observe') -AllowedExitCodes @(1)
    Assert-SessionEnvelope $closed 'runtime-session-command'
    if ($closed.json.error.code -ne 'STOP_SESSION_CLOSED') { Fail "closed session expected STOP_SESSION_CLOSED, got $($closed.json.error.code)." }

    $summary = [ordered]@{
        schema_version = 'v6.2.0.runtime_session_selftest'
        status = 'PASS'
        session_lifecycle = [ordered]@{
            session_created = $true
            session_status_ok = $true
            session_observe_ok = $true
            session_closed = $true
            closed_session_rejected = $true
        }
        session_id = $sessionId
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

    @(
        '# Runtime Session Selftest Report',
        '',
        '- Status: PASS',
        "- session_id: $sessionId",
        '- session_created: true',
        '- session_status_ok: true',
        '- session_observe_ok: true',
        '- session_closed: true',
        '- closed_session_rejected: true'
    ) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

    Write-Output 'RUNTIME_SESSION_SELFTEST_PASS'
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
