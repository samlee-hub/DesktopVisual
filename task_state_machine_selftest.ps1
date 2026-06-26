param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_state_machine_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates the v5.0.2 TaskSession state machine dry-run command.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.0.2'
$Report = Join-Path $ArtifactDir 'task_state_machine_selftest_report.md'
$PendingFixture = Join-Path $Root 'tasks\session_schema\valid_standard_session.task-session.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

function Invoke-JsonCommand {
    param([string[]]$Arguments)

    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{
        ExitCode = $exit
        Text = $text
        Json = $json
    }
}

function Assert-Transition {
    param(
        [string]$Action,
        [string]$From,
        [string]$To,
        [string]$Expected,
        [string[]]$Extra = @()
    )

    $args = @('task-session-transition', '--file', $PendingFixture, '--action', $Action, '--from-state', $From)
    if ($To) {
        $args += @('--to-state', $To)
    }
    if ($Extra.Count -gt 0) {
        $args += $Extra
    }
    $result = Invoke-JsonCommand $args
    if ($result.ExitCode -ne 0 -or -not $result.Json.ok) {
        throw "Expected transition $Action $From->$Expected to pass. output=$($result.Text)"
    }
    if ($result.Json.data.previous_state -ne $From) {
        throw "Expected previous_state $From, got $($result.Json.data.previous_state)"
    }
    if ($result.Json.data.current_state -ne $Expected) {
        throw "Expected current_state $Expected, got $($result.Json.data.current_state)"
    }
    if (-not $result.Json.data.transition.valid) {
        throw "Expected transition.valid=true for $Action."
    }
    return $result.Text
}

$startText = Assert-Transition -Action 'start_task' -From 'pending' -To '' -Expected 'running'
$enterText = Assert-Transition -Action 'enter_state' -From 'running' -To 'waiting' -Expected 'waiting'
$transitionText = Assert-Transition -Action 'transition_to' -From 'running' -To 'verifying' -Expected 'verifying'
$completeText = Assert-Transition -Action 'complete_task' -From 'confirmed' -To '' -Expected 'completed'
$failText = Assert-Transition -Action 'fail_task' -From 'running' -To '' -Expected 'failed'
$stopText = Assert-Transition -Action 'stop_task' -From 'waiting' -To '' -Expected 'stopped'
$timeoutText = Assert-Transition -Action 'timeout_task' -From 'verifying' -To '' -Expected 'blocked' -Extra @('--timeout-ms', '1000', '--elapsed-ms', '1500')

$invalid = Invoke-JsonCommand @('task-session-transition', '--file', $PendingFixture, '--action', 'complete_task', '--from-state', 'pending')
if ($invalid.ExitCode -eq 0 -or $invalid.Json.ok) {
    throw "Expected invalid complete_task from pending to fail. output=$($invalid.Text)"
}
if ($invalid.Json.error.code -ne 'TASK_TRANSITION_INVALID') {
    throw "Expected TASK_TRANSITION_INVALID, got $($invalid.Json.error.code)"
}

$terminalInvalid = Invoke-JsonCommand @('task-session-transition', '--file', $PendingFixture, '--action', 'start_task', '--from-state', 'completed')
if ($terminalInvalid.ExitCode -eq 0 -or $terminalInvalid.Json.ok) {
    throw "Expected terminal state transition to fail. output=$($terminalInvalid.Text)"
}
if ($terminalInvalid.Json.error.message -notmatch 'terminal') {
    throw "Expected terminal state error. output=$($terminalInvalid.Text)"
}

$lines = @(
    '# v5.0.2 Task State Machine Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Fixture: `{0}`' -f $PendingFixture),
    ('- Command: `{0} task-session-transition --file <fixture> --action <action>`' -f $WinAgent),
    '',
    '## Passing Transitions',
    '',
    '```json',
    $startText,
    $enterText,
    $transitionText,
    $completeText,
    $failText,
    $stopText,
    $timeoutText,
    '```',
    '',
    '## Invalid Transition',
    '',
    '```json',
    $invalid.Text,
    $terminalInvalid.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.0.2 TaskSession state machine selftest'
Write-Host "Report: $Report"
