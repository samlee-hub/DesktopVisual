param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts\dev4.4.0'
$Fixtures = Join-Path $Artifacts 'fixtures'
$Report = Join-Path $Artifacts 'dynamic_ui_recovery_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts,$Fixtures | Out-Null
Remove-Item -LiteralPath $Report -ErrorAction SilentlyContinue

$loading = Join-Path $Fixtures 'loading.html'
$ready = Join-Path $Fixtures 'ready.html'
$dialog = Join-Path $Fixtures 'dialog.html'
$errorHtml = Join-Path $Fixtures 'error.html'
$success = Join-Path $Fixtures 'success.html'
$blocked = Join-Path $Fixtures 'blocked.html'
$movedBefore = Join-Path $Fixtures 'moved_before.html'
$movedAfter = Join-Path $Fixtures 'moved_after.html'
$disabledBefore = Join-Path $Fixtures 'disabled_before.html'
$disabledAfter = Join-Path $Fixtures 'disabled_after.html'

'<!doctype html><html><body data-state="loading"><div class="spinner">Loading...</div><button id="submit" disabled>Submit</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $loading
'<!doctype html><html><body data-state="normal"><button id="submit" data-ready="true">Submit</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $ready
'<!doctype html><html><body data-state="dialog_open"><div role="dialog" data-modal="true">Confirm</div><button id="underlay">Delete</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $dialog
'<!doctype html><html><body><div class="error">Error: failed to save</div><button id="retry">Retry</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $errorHtml
'<!doctype html><html><body><div class="success">Success: saved</div><button id="done">Done</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $success
'<!doctype html><html><body data-state="blocked"><div data-risk="blocked">captcha challenge</div></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $blocked
'<!doctype html><html><body><button id="submit" data-x="10" data-y="20" data-enabled="true">Submit</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $movedBefore
'<!doctype html><html><body><button id="submit" data-x="80" data-y="20" data-enabled="true">Submit</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $movedAfter
'<!doctype html><html><body><button id="submit" data-enabled="false" disabled>Submit</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $disabledBefore
'<!doctype html><html><body><button id="submit" data-enabled="true">Submit</button></body></html>' | Set-Content -Encoding UTF8 -LiteralPath $disabledAfter

$loadingEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $loading, '--previous-html', $ready, '--candidate-id', 'submit', '--semantic-status', 'resolved', '--risk-status', 'normal')
if ($loadingEval.json.data.scene_state.status -ne 'loading') { Fail "Expected loading scene state: $($loadingEval.text)" }
if ($loadingEval.json.data.action_decision -ne 'REQUIRE_HUMAN_CONFIRMATION' -and $loadingEval.json.data.action_decision -ne 'STOP') {
    Fail "Loading state must not auto execute: $($loadingEval.text)"
}

$readyEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $ready, '--previous-html', $loading, '--candidate-id', 'submit', '--semantic-status', 'resolved', '--risk-status', 'normal')
$readyEvents = @($readyEval.json.data.change_events | ForEach-Object { $_.type })
if ($readyEval.json.data.scene_state.status -ne 'normal') { Fail "Expected normal scene state: $($readyEval.text)" }
if ($readyEvents -notcontains 'loading_finished') { Fail "Expected loading_finished event: $($readyEval.text)" }
if ($readyEvents -notcontains 'target_ready') { Fail "Expected target_ready event: $($readyEval.text)" }
if ($readyEval.json.data.action_decision -ne 'AUTO_EXECUTE') { Fail "Ready resolved low-risk candidate should auto execute: $($readyEval.text)" }

$dialogEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $dialog, '--candidate-id', 'underlay', '--semantic-status', 'resolved', '--risk-status', 'normal')
if ($dialogEval.json.data.scene_state.status -ne 'dialog_open') { Fail "Expected dialog_open scene state: $($dialogEval.text)" }
if ($dialogEval.json.data.action_decision -eq 'AUTO_EXECUTE') { Fail "Dialog state must not click underlay: $($dialogEval.text)" }

$errorEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $errorHtml, '--candidate-id', 'retry', '--semantic-status', 'resolved', '--risk-status', 'normal')
if ($errorEval.json.data.scene_state.status -ne 'error') { Fail "Expected error scene state: $($errorEval.text)" }
if (@($errorEval.json.data.change_events | ForEach-Object { $_.type }) -notcontains 'error_appeared') { Fail "Expected error_appeared event." }

$successEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $success, '--candidate-id', 'done', '--semantic-status', 'resolved', '--risk-status', 'normal')
if ($successEval.json.data.scene_state.status -ne 'success') { Fail "Expected success scene state: $($successEval.text)" }
if (@($successEval.json.data.change_events | ForEach-Object { $_.type }) -notcontains 'success_appeared') { Fail "Expected success_appeared event." }

$blockedEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $blocked, '--candidate-id', 'captcha', '--semantic-status', 'resolved', '--risk-status', 'blocked_sensitive')
if ($blockedEval.json.data.scene_state.status -ne 'blocked') { Fail "Expected blocked scene state: $($blockedEval.text)" }
if ($blockedEval.json.data.action_decision -ne 'STOP') { Fail "Blocked state must STOP: $($blockedEval.text)" }
if ($blockedEval.json.data.routers.risk_router.route -ne 'STOP') { Fail "Blocked must not route to VLM: $($blockedEval.text)" }

$movedEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $movedAfter, '--previous-html', $movedBefore, '--candidate-id', 'submit', '--semantic-status', 'resolved', '--risk-status', 'normal')
if (@($movedEval.json.data.change_events | ForEach-Object { $_.type }) -notcontains 'element_moved') { Fail "Expected element_moved event: $($movedEval.text)" }

$enabledEval = Invoke-WinAgentJson -WinArgs @('dynamic-ui-recovery', '--html', $disabledAfter, '--previous-html', $disabledBefore, '--candidate-id', 'submit', '--semantic-status', 'resolved', '--risk-status', 'normal')
if (@($enabledEval.json.data.change_events | ForEach-Object { $_.type }) -notcontains 'element_enabled') { Fail "Expected element_enabled event: $($enabledEval.text)" }

$visualBlocked = Invoke-WinAgentJson -WinArgs @('act', '--title', 'Agent Test Window', '--selector', 'visual:id=image_template:0', '--action', 'click') -AllowedExitCodes @(1)
if ($visualBlocked.json.error.code -ne 'WINDOW_NOT_FOUND' -and $visualBlocked.json.error.code -ne 'ACTION_BLOCKED_SEMANTIC_UNRESOLVED') {
    Fail "Unexpected visual block error before TestWindow startup: $($visualBlocked.text)"
}

$tw = $null
try {
    $tw = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }
    $visualBlocked = Invoke-WinAgentJson -WinArgs @('act', '--title', 'Agent Test Window', '--selector', 'visual:id=image_template:0', '--action', 'click') -AllowedExitCodes @(1)
    if ($visualBlocked.json.error.code -ne 'ACTION_BLOCKED_SEMANTIC_UNRESOLVED') {
        Fail "visual-only unresolved action was not blocked: $($visualBlocked.text)"
    }
} finally {
    if ($tw -and !$tw.HasExited) {
        $tw.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$tw.HasExited) { Stop-Process -Id $tw.Id -Force }
    }
}

@(
    '# DesktopVisual Dynamic UI Recovery Selftest',
    '',
    '- Result: PASS',
    '- Loading wait/stop route: PASS',
    '- Loading finished and target_ready: PASS',
    '- Dialog underlay click block: PASS',
    '- Error/success recognition: PASS',
    '- Element moved/enabled events: PASS',
    '- Blocked STOP route: PASS',
    '- Visual-only unresolved ActionExecutor gate: ACTION_BLOCKED_SEMANTIC_UNRESOLVED'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'dynamic UI recovery selftest passed.'
Write-Host "Report: $Report"
