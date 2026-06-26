param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$ArtifactDir = Join-Path $Root 'artifacts\f12_force_exit_runtime_integration'
$StepsPath = Join-Path $ArtifactDir 'f12_dispatch_steps.json'
$DispatchResultPath = Join-Path $ArtifactDir 'f12_dispatch_result.json'
$Report = Join-Path $ArtifactDir 'f12_force_exit_runtime_integration_selftest_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) {
    throw $Message
}

function Expected-F12Message {
    $codes = @(
        0x7528, 0x6237, 0x5DF2, 0x6309, 0x20, 0x46, 0x31, 0x32,
        0x20, 0x5F3A, 0x5236, 0x7ED3, 0x675F, 0x5F53, 0x524D,
        0x4EFB, 0x52A1, 0xFF0C, 0x41, 0x67, 0x65, 0x6E, 0x74,
        0x20, 0x5DF2, 0x505C, 0x6B62, 0x672C, 0x6B21, 0x884C,
        0x4E3A, 0x3002
    )
    return -join ($codes | ForEach-Object { [char]$_ })
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

if (-not (Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent. Run build.ps1 first."
}
if (-not (Test-Path -LiteralPath $TestWindowExe)) {
    Fail "Missing $TestWindowExe. Run build.ps1 first."
}

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 250
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

    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'Agent Test Window', '--process', 'TestWindow.exe')
    if ($start.json.ok -ne $true -or -not $start.json.session_id) {
        Fail "runtime-session-start failed: $($start.text)"
    }
    $sessionId = [string]$start.json.session_id

    @{
        steps = @(
            @{
                step_id = 'f12-stop-before-click'
                action = 'click'
                x = 70
                y = 70
                move_mode = 'instant'
                stop_on_failure = $true
            },
            @{
                step_id = 'must-not-run-after-f12'
                action = 'click'
                x = 90
                y = 90
                move_mode = 'instant'
                stop_on_failure = $true
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StepsPath -Encoding UTF8

    $oldForce = $env:DESKTOPVISUAL_FORCE_F12_ABORT
    $env:DESKTOPVISUAL_FORCE_F12_ABORT = '1'
    try {
        $dispatch = Invoke-WinAgentJson -WinArgs @(
            'runtime-session-dispatch',
            '--session-id', $sessionId,
            '--steps-json', $StepsPath,
            '--result-json', $DispatchResultPath
        ) -AllowedExitCodes @(1)
    } finally {
        $env:DESKTOPVISUAL_FORCE_F12_ABORT = $oldForce
    }

    if ($dispatch.json.ok -ne $false) { Fail "dispatch stop must be ok=false: $($dispatch.text)" }
    if ($dispatch.json.error.code -ne 'STOP_USER_FORCE_EXIT_F12') {
        Fail "Expected STOP_USER_FORCE_EXIT_F12, got $($dispatch.json.error.code). output=$($dispatch.text)"
    }
    if ($dispatch.json.error.message -ne (Expected-F12Message)) {
        Fail "F12 user message mismatch: $($dispatch.json.error.message)"
    }
    if ($dispatch.json.session_alive -ne $true) { Fail 'Runtime session should remain alive after F12 stop.' }
    if ($dispatch.json.data.executed_step_count -ne 1) {
        Fail "Expected exactly one executed step, got $($dispatch.json.data.executed_step_count)."
    }
    if ($dispatch.json.data.stop_code -ne 'STOP_USER_FORCE_EXIT_F12') {
        Fail "Expected dispatch stop_code STOP_USER_FORCE_EXIT_F12, got $($dispatch.json.data.stop_code)."
    }
    if ($dispatch.json.data.step_results.Count -ne 1) {
        Fail "Expected one step_result because following steps must not execute after F12."
    }
    $first = $dispatch.json.data.step_results[0]
    if ($first.error_code -ne 'STOP_USER_FORCE_EXIT_F12') { Fail "First step did not carry F12 stop code." }
    if ($first.action_executed -ne $false) { Fail 'First step must not report action_executed after F12.' }
    if ($first.data.user_force_exit -ne $true) { Fail 'Step evidence missing user_force_exit=true.' }
    if ($first.data.process_exit -ne $false) { Fail 'Step evidence must record process_exit=false.' }

    $status = Invoke-WinAgentJson -WinArgs @('runtime-session-status', '--session-id', $sessionId)
    if ($status.json.ok -ne $true -or $status.json.session_alive -ne $true) {
        Fail "runtime-session-status did not respond after F12 stop: $($status.text)"
    }

    $version = Invoke-WinAgentJson -WinArgs @('version')
    if ($version.json.ok -ne $true) { Fail "version did not respond after F12 stop: $($version.text)" }

    @(
        '# F12 Runtime Integration Selftest',
        '',
        '- Result: PASS',
        "- session_id: $sessionId",
        '- dispatch_stop_code: STOP_USER_FORCE_EXIT_F12',
        '- user_force_exit: true',
        '- force_exit_key: F12',
        '- force_exit_scope: current_task_only',
        '- process_exit: false',
        '- following_step_executed: false',
        '- session_alive_after_stop: true',
        '- version_after_stop: PASS',
        "- dispatch_result: $DispatchResultPath"
    ) | Set-Content -LiteralPath $Report -Encoding UTF8

    Write-Host 'F12_FORCE_EXIT_RUNTIME_INTEGRATION_SELFTEST_PASS'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
