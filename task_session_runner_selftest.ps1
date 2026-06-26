param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_session_runner_selftest.ps1 [-Root <path>]'
    Write-Host 'Runs the v5.0.3 local mock minimal TaskSession runner smoke test.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Fixture = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock.task-session.json'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.0.3\local_form_fill_submit_mock'
$Report = Join-Path $Root 'artifacts\dev5.0.3\task_session_runner_selftest_report.md'
$Progress = Join-Path $ArtifactRoot 'task_progress.json'
$Events = Join-Path $ArtifactRoot 'step_events.jsonl'
$TaskReport = Join-Path $ArtifactRoot 'task_report.md'

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
    throw "Expected task-session-run to pass. exit=$exit output=$text"
}
if ($json.data.current_state -ne 'completed') {
    throw "Expected completed state, got $($json.data.current_state)"
}
if ($json.data.completed_steps -ne 4) {
    throw "Expected 4 completed steps, got $($json.data.completed_steps)"
}
if ($json.data.llm_or_vlm_call_count -ne 0) {
    throw "Expected llm_or_vlm_call_count=0, got $($json.data.llm_or_vlm_call_count)"
}
foreach ($path in @($Progress, $Events, $TaskReport)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Expected artifact missing: $path"
    }
}
$progressJson = Get-Content -LiteralPath $Progress -Raw | ConvertFrom-Json
if (-not $progressJson.ok -or $progressJson.current_state -ne 'completed') {
    throw "Expected completed progress artifact."
}
$eventLines = @(Get-Content -LiteralPath $Events | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($eventLines.Count -lt 4) {
    throw "Expected at least four step events, got $($eventLines.Count)"
}
foreach ($line in $eventLines) {
    $parsed = $line | ConvertFrom-Json
    if (-not $parsed.step_id) {
        throw "Event line missing step_id: $line"
    }
}
$reportText = Get-Content -LiteralPath $TaskReport -Raw
if ($reportText -notmatch 'local_form_fill_submit_mock' -or $reportText -notmatch 'SUCCESS') {
    throw "Task report did not include expected task and success summary."
}

$lines = @(
    '# v5.0.3 TaskSession Runner Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Fixture: `{0}`' -f $Fixture),
    ('- Progress: `{0}`' -f $Progress),
    ('- Events: `{0}`' -f $Events),
    ('- Task report: `{0}`' -f $TaskReport),
    '',
    '## Command Output',
    '',
    '```json',
    $text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.0.3 TaskSession minimal runner selftest'
Write-Host "Report: $Report"
