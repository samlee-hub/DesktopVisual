param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_0_revalidation_selftest.ps1 [-Root <path>]'
    Write-Host 'Revalidates v5.0 TaskSession, state machine, minimal runner, and artifacts.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.7_revalidation\phase_02_v5.0\focused'
$Report = Join-Path $ArtifactDir 'v5_0_revalidation_selftest_report.md'
$SessionFixture = Join-Path $Root 'tasks\session_schema\valid_standard_session.task-session.json'
$RunnerFixture = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json'
$RunnerArtifactRoot = Join-Path $Root 'artifacts\dev5.0.4\local_form_fill_submit_mock_audit'
$Events = Join-Path $RunnerArtifactRoot 'task_events.jsonl'
$Result = Join-Path $RunnerArtifactRoot 'task_result.json'
$TaskReport = Join-Path $RunnerArtifactRoot 'task_report.md'
$StateDump = Join-Path $RunnerArtifactRoot 'current_state.json'
$FailureDump = Join-Path $RunnerArtifactRoot 'failure_dump.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
if (Test-Path -LiteralPath $RunnerArtifactRoot) {
    Remove-Item -LiteralPath $RunnerArtifactRoot -Recurse -Force
}

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

function Assert-HasValue {
    param($Object, [string]$Name)
    if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
        throw "Expected field '$Name' to be present."
    }
    $value = $Object.$Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        throw "Expected field '$Name' to be non-empty."
    }
}

function Assert-JsonFile {
    param([string]$Path, [string[]]$RequiredFields)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected JSON artifact missing: $Path"
    }
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($field in $RequiredFields) {
        Assert-HasValue $json $field
    }
    return $json
}

$validate = Invoke-JsonCommand @('task-session-validate', '--file', $SessionFixture)
if ($validate.ExitCode -ne 0 -or -not $validate.Json.ok) {
    throw "Expected TaskSession validation to pass. output=$($validate.Text)"
}
$data = $validate.Json.data
foreach ($field in @('schema_version','runtime_version','protocol_version','task_id','task_type','profile','permission_profile','current_state','started_at','updated_at')) {
    Assert-HasValue $data $field
}
foreach ($state in @('pending','running','waiting','verifying','recovering','confirmed','completed','failed','stopped','blocked')) {
    if ($validate.Text -notmatch ('"' + [regex]::Escape($state) + '"')) {
        throw "Expected TaskState '$state' to be represented in validation output."
    }
}
if ($data.current_state -ne 'pending') {
    throw "Expected initial current_state pending, got $($data.current_state)"
}

$start = Invoke-JsonCommand @('task-session-transition', '--file', $SessionFixture, '--action', 'start_task', '--from-state', 'pending')
if ($start.ExitCode -ne 0 -or -not $start.Json.ok -or $start.Json.data.current_state -ne 'running') {
    throw "Expected start_task pending->running to pass. output=$($start.Text)"
}

$invalid = Invoke-JsonCommand @('task-session-transition', '--file', $SessionFixture, '--action', 'complete_task', '--from-state', 'pending')
if ($invalid.ExitCode -eq 0 -or $invalid.Json.ok -or $invalid.Json.error.code -ne 'TASK_TRANSITION_INVALID') {
    throw "Expected invalid complete_task from pending to be rejected. output=$($invalid.Text)"
}

$timeout = Invoke-JsonCommand @('task-session-transition', '--file', $SessionFixture, '--action', 'timeout_task', '--from-state', 'verifying', '--timeout-ms', '1000', '--elapsed-ms', '1500')
if ($timeout.ExitCode -ne 0 -or -not $timeout.Json.ok -or $timeout.Json.data.current_state -ne 'blocked' -or -not $timeout.Json.data.timeout) {
    throw "Expected timeout_task verifying to blocked timeout=true. output=$($timeout.Text)"
}

$terminalInvalid = Invoke-JsonCommand @('task-session-transition', '--file', $SessionFixture, '--action', 'start_task', '--from-state', 'failed')
if ($terminalInvalid.ExitCode -eq 0 -or $terminalInvalid.Json.ok) {
    throw "Expected failure state to reject further execution transitions. output=$($terminalInvalid.Text)"
}

$run = Invoke-JsonCommand @('task-session-run', '--file', $RunnerFixture)
if ($run.ExitCode -ne 0 -or -not $run.Json.ok -or $run.Json.data.current_state -ne 'completed') {
    throw "Expected minimal runner smoke to complete. output=$($run.Text)"
}

$resultJson = Assert-JsonFile $Result @('schema_version','runtime_version','protocol_version','task_id','task_type','current_state')
if (-not $resultJson.ok -or $resultJson.current_state -ne 'completed') {
    throw "Expected task_result.json completed ok=true."
}
$stateJson = Assert-JsonFile $StateDump @('schema_version','runtime_version','protocol_version','task_id','task_type','current_state')
if ($stateJson.current_state -ne 'completed') {
    throw "Expected current_state.json completed."
}
$failureJson = Assert-JsonFile $FailureDump @('schema_version','runtime_version','protocol_version','task_id')
if ($failureJson.has_failure) {
    throw "Expected failure_dump.json has_failure=false."
}

if (-not (Test-Path -LiteralPath $Events)) {
    throw "Expected task_events.jsonl missing: $Events"
}
$eventLines = @(Get-Content -LiteralPath $Events -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($eventLines.Count -lt 5) {
    throw "Expected at least five task events, got $($eventLines.Count)."
}
foreach ($line in $eventLines) {
    $event = $line | ConvertFrom-Json
    foreach ($field in @('schema_version','runtime_version','protocol_version','timestamp','task_id','step_id','state')) {
        Assert-HasValue $event $field
    }
}

if (-not (Test-Path -LiteralPath $TaskReport)) {
    throw "Expected task_report.md missing: $TaskReport"
}
$reportText = Get-Content -LiteralPath $TaskReport -Raw -Encoding UTF8
if ($reportText.Contains([string][char]0xfffd)) {
    throw "task_report.md appears to contain mojibake."
}
if (($reportText -notmatch 'Step Timeline') -or ($reportText -notmatch 'Final state: `completed`')) {
    throw "task_report.md missing readable timeline or final state."
}

$lines = @(
    '# v5.0 Revalidation Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Validation fixture: `{0}`' -f $SessionFixture),
    ('- Runner fixture: `{0}`' -f $RunnerFixture),
    ('- Result JSON: `{0}`' -f $Result),
    ('- Events JSONL: `{0}`' -f $Events),
    ('- Task report: `{0}`' -f $TaskReport),
    '',
    '## Command Evidence',
    '',
    '```json',
    $validate.Text,
    $start.Text,
    $invalid.Text,
    $timeout.Text,
    $terminalInvalid.Text,
    $run.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.0 revalidation selftest'
Write-Host "Report: $Report"
