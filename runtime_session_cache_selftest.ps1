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
$RawRoot = Join-Path $ArtifactRoot 'raw\runtime_session_cache_selftest'
$ReportPath = Join-Path $ArtifactRoot 'runtime_session_cache_selftest_report.md'
$ResultPath = Join-Path $ArtifactRoot 'runtime_session_cache_selftest_result.json'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Fail([string]$Message) { throw $Message }

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
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON: $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $WinArgs }
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
    $sessionId = [string]$start.json.session_id

    $focusClick = Invoke-WinAgentJson -WinArgs @('runtime-session-command', '--session-id', $sessionId, '--action', 'click', '--x', '90', '--y', '90', '--move-mode', 'instant')
    if ($focusClick.json.ok -ne $true) { Fail 'Initial focus click failed.' }

    $observe1 = Invoke-WinAgentJson -WinArgs @('runtime-session-observe', '--session-id', $sessionId, '--screenshot', 'false', '--uia', 'true')
    if ($observe1.json.data.observe_cache_miss -ne $true) { Fail 'First observe did not record cache miss.' }

    $observe2 = Invoke-WinAgentJson -WinArgs @('runtime-session-observe', '--session-id', $sessionId, '--screenshot', 'false', '--uia', 'true')
    if ($observe2.json.data.observe_cache_hit -ne $true) { Fail 'Second observe did not hit observe cache.' }

    $locate1 = Invoke-WinAgentJson -WinArgs @('runtime-session-locate', '--session-id', $sessionId, '--target', 'uia:name=Click Me,type=Button')
    if ($locate1.json.data.locator_cache_miss -ne $true) { Fail 'First locate did not record locator cache miss.' }

    $locate2 = Invoke-WinAgentJson -WinArgs @('runtime-session-locate', '--session-id', $sessionId, '--target', 'uia:name=Click Me,type=Button')
    if ($locate2.json.data.locator_cache_hit -ne $true) { Fail 'Second locate did not hit locator cache.' }

    $clickCached = Invoke-WinAgentJson -WinArgs @('runtime-session-command', '--session-id', $sessionId, '--action', 'click', '--target', 'uia:name=Click Me,type=Button', '--move-mode', 'instant')
    if ($clickCached.json.ok -ne $true) { Fail 'Cached locator click failed.' }
    if ($clickCached.json.data.step_result.locator_cache_hit -ne $true) { Fail 'Click did not use locator cache before invalidation.' }

    $observeAfterAction = Invoke-WinAgentJson -WinArgs @('runtime-session-observe', '--session-id', $sessionId, '--screenshot', 'false', '--uia', 'true')
    if ($observeAfterAction.json.data.observe_cache_miss -ne $true) { Fail 'Observe after action did not miss after invalidation.' }

    $stale = Invoke-WinAgentJson -WinArgs @('runtime-session-locate', '--session-id', $sessionId, '--target', 'uia:name=Click Me,type=Button') -AllowedExitCodes @(1)
    if ($stale.json.error.code -ne 'STOP_TARGET_STALE') { Fail "Expected STOP_TARGET_STALE, got $($stale.json.error.code)." }
    if ($stale.json.data.step_result.data.old_rect_not_clicked -ne $true) { Fail 'Stale locator rejection did not prove old_rect_not_clicked=true.' }

    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId)

    $summary = [ordered]@{
        schema_version = 'v6.2.0.runtime_session_cache_selftest'
        status = 'PASS'
        session_id = $sessionId
        observe_cache = [ordered]@{
            first_observe_miss = $true
            second_observe_hit = $true
            invalidated_after_action = $true
        }
        locator_cache = [ordered]@{
            first_locate_miss = $true
            second_locate_hit = $true
            cache_hit_attempted = $true
            stale_target_detected = $true
            old_rect_not_clicked = $true
            stop_code = 'STOP_TARGET_STALE'
        }
    }
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

    @(
        '# Runtime Session Cache Selftest Report',
        '',
        '- Status: PASS',
        "- session_id: $sessionId",
        '- observe_cache_first_miss: true',
        '- observe_cache_second_hit: true',
        '- observe_cache_invalidated_after_action: true',
        '- locator_cache_first_miss: true',
        '- locator_cache_second_hit: true',
        '- cache_hit_attempted: true',
        '- stale_target_detected: true',
        '- old_rect_not_clicked: true',
        '- stop_code: STOP_TARGET_STALE'
    ) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

    Write-Output 'RUNTIME_SESSION_CACHE_SELFTEST_PASS'
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
