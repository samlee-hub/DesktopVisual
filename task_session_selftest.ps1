param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_session_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates the v5.0.1 TaskSession schema command and fixtures.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.0.1'
$Report = Join-Path $ArtifactDir 'task_session_selftest_report.md'
$SchemaFixture = Join-Path $Root 'tasks\session_schema\task_session.schema.json'
$ValidFixture = Join-Path $Root 'tasks\session_schema\valid_standard_session.task-session.json'
$InvalidFixture = Join-Path $Root 'tasks\session_schema\invalid_escalation_reason.task-session.json'
$InvalidStateFixture = Join-Path $Root 'tasks\session_schema\invalid_state.task-session.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

$schema = Get-Content -LiteralPath $SchemaFixture -Raw | ConvertFrom-Json
if ($schema.title -ne 'DesktopVisual v5.0.1 TaskSession') {
    throw "Unexpected TaskSession schema title: $($schema.title)"
}
$validFixtureJson = Get-Content -LiteralPath $ValidFixture -Raw | ConvertFrom-Json
if ($validFixtureJson.states.Count -ne 10) {
    throw "Expected exactly 10 v5.0.1 TaskState enum values in valid fixture."
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

$valid = Invoke-JsonCommand @('task-session-validate', '--file', $ValidFixture)
if ($valid.ExitCode -ne 0 -or -not $valid.Json.ok) {
    throw "Expected valid TaskSession fixture to pass. exit=$($valid.ExitCode) output=$($valid.Text)"
}
if ($valid.Json.data.schema_version -ne '5.0.1') {
    throw "Expected schema_version 5.0.1, got $($valid.Json.data.schema_version)"
}
if ($valid.Json.data.task_id -ne 'dev5_0_1_valid_standard') {
    throw "Expected task_id dev5_0_1_valid_standard, got $($valid.Json.data.task_id)"
}
if ($valid.Json.data.current_state -ne 'pending') {
    throw "Expected pending current_state, got $($valid.Json.data.current_state)"
}
if ($valid.Json.data.permission_profile -ne 'DEFAULT') {
    throw "Expected DEFAULT permission profile, got $($valid.Json.data.permission_profile)"
}
if ($valid.Json.data.context.runtime_mode -ne 'STANDARD') {
    throw "Expected STANDARD runtime mode, got $($valid.Json.data.context.runtime_mode)"
}
if ($valid.Json.data.state_count -ne 10) {
    throw "Expected 10 state enum values, got $($valid.Json.data.state_count)"
}
if ($valid.Json.data.step_contracts -ne 1) {
    throw "Expected one step contract, got $($valid.Json.data.step_contracts)"
}
if ($valid.Json.data.transition_schemas -ne 2) {
    throw "Expected two transition schemas, got $($valid.Json.data.transition_schemas)"
}
if ($valid.Json.data.task_result.task_id -ne 'dev5_0_1_valid_standard') {
    throw "Expected serialized task_result JSON for the valid task session."
}
if ($valid.Json.data.escalation_provider -ne 'none') {
    throw "Expected no escalation provider on valid fixture."
}

$invalid = Invoke-JsonCommand @('task-session-validate', '--file', $InvalidFixture)
if ($invalid.ExitCode -eq 0 -or $invalid.Json.ok) {
    throw "Expected invalid escalation fixture to fail. output=$($invalid.Text)"
}
if ($invalid.Json.error.code -ne 'TASK_SESSION_SCHEMA_INVALID') {
    throw "Expected TASK_SESSION_SCHEMA_INVALID, got $($invalid.Json.error.code)"
}
if ($invalid.Json.error.message -notmatch 'bypass_safety_policy') {
    throw "Expected error message to mention bypass_safety_policy. output=$($invalid.Text)"
}

$invalidState = Invoke-JsonCommand @('task-session-validate', '--file', $InvalidStateFixture)
if ($invalidState.ExitCode -eq 0 -or $invalidState.Json.ok) {
    throw "Expected invalid state fixture to fail. output=$($invalidState.Text)"
}
if ($invalidState.Json.error.code -ne 'TASK_SESSION_SCHEMA_INVALID') {
    throw "Expected TASK_SESSION_SCHEMA_INVALID for invalid state, got $($invalidState.Json.error.code)"
}
if ($invalidState.Json.error.message -notmatch 'created') {
    throw "Expected invalid state error to mention created. output=$($invalidState.Text)"
}

$lines = @(
    '# v5.0.1 TaskSession Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Schema fixture: `{0}`' -f $SchemaFixture),
    ('- Valid fixture: `{0}`' -f $ValidFixture),
    ('- Invalid fixture: `{0}`' -f $InvalidFixture),
    ('- Invalid state fixture: `{0}`' -f $InvalidStateFixture),
    ('- Command: `{0} task-session-validate --file <fixture>`' -f $WinAgent),
    '',
    '## Valid Fixture Data',
    '',
    '```json',
    $valid.Text,
    '```',
    '',
    '## Invalid Fixture Data',
    '',
    '```json',
    $invalid.Text,
    '```',
    '',
    '## Invalid State Fixture Data',
    '',
    '```json',
    $invalidState.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host "PASS: v5.0.1 TaskSession selftest"
Write-Host "Report: $Report"
