param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_artifact_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.0.4 formal TaskSession artifacts.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Fixture = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.0.4\local_form_fill_submit_mock_audit'
$Report = Join-Path $Root 'artifacts\dev5.0.4\task_artifact_selftest_report.md'
$Events = Join-Path $ArtifactRoot 'task_events.jsonl'
$Result = Join-Path $ArtifactRoot 'task_result.json'
$TaskReport = Join-Path $ArtifactRoot 'task_report.md'
$StateDump = Join-Path $ArtifactRoot 'current_state.json'
$FailureDump = Join-Path $ArtifactRoot 'failure_dump.json'

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Report) | Out-Null
if (Test-Path -LiteralPath $ArtifactRoot) {
    Remove-Item -LiteralPath $ArtifactRoot -Recurse -Force
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

$output = & $WinAgent task-session-run --file $Fixture 2>&1
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
$json = $text | ConvertFrom-Json
if ($exit -ne 0 -or -not $json.ok) {
    throw "Expected task-session-run artifact fixture to pass. exit=$exit output=$text"
}

foreach ($path in @($Events, $Result, $TaskReport, $StateDump, $FailureDump)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Expected artifact missing: $path"
    }
}

$resultJson = Get-Content -LiteralPath $Result -Raw | ConvertFrom-Json
if (-not $resultJson.ok -or $resultJson.current_state -ne 'completed') {
    throw "Expected task_result.json to record completed success."
}
$stateJson = Get-Content -LiteralPath $StateDump -Raw | ConvertFrom-Json
if ($stateJson.current_state -ne 'completed' -or $stateJson.completed_steps -ne 4) {
    throw "Expected current_state.json to record completed progress."
}
$failureJson = Get-Content -LiteralPath $FailureDump -Raw | ConvertFrom-Json
if ($failureJson.has_failure) {
    throw "Expected failure_dump.json to record no failure."
}
$eventLines = @(Get-Content -LiteralPath $Events | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($eventLines.Count -lt 5) {
    throw "Expected at least five task events, got $($eventLines.Count)"
}
foreach ($line in $eventLines) {
    $event = $line | ConvertFrom-Json
    if (-not $event.task_id -or -not $event.step_id -or -not $event.state) {
        throw "Task event missing required fields: $line"
    }
}
$reportText = Get-Content -LiteralPath $TaskReport -Raw
if ($reportText -notmatch 'Step Timeline' -or $reportText -notmatch 'Final state: `completed`') {
    throw "Task report is missing readable step timeline or final state."
}

$lines = @(
    '# v5.0.4 Task Artifact Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Fixture: `{0}`' -f $Fixture),
    ('- Events: `{0}`' -f $Events),
    ('- Result: `{0}`' -f $Result),
    ('- Report: `{0}`' -f $TaskReport),
    ('- Current state: `{0}`' -f $StateDump),
    ('- Failure dump: `{0}`' -f $FailureDump),
    '',
    '## Command Output',
    '',
    '```json',
    $text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.0.4 TaskSession artifact selftest'
Write-Host "Report: $Report"
