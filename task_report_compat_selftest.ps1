param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_report_compat_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.7 task report compatibility artifacts.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.7.4'
$Report = Join-Path $ArtifactDir 'task_report_compat_selftest_report.md'
$TaskFile = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail($Message) { throw "FAIL: $Message" }

function Invoke-Json([string[]]$CommandArgs) {
    $output = & $WinAgent @CommandArgs 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "Command failed ($($CommandArgs -join ' ')): $output" }
    try { return ($output | Out-String) | ConvertFrom-Json } catch { Fail "Invalid JSON from $($CommandArgs -join ' '): $output" }
}

$run = Invoke-Json -CommandArgs @('run-task','--file',$TaskFile)
if (-not $run.ok -or -not $run.data.machine_readable_status -or $run.data.machine_readable_status.state -ne 'completed') {
    Fail 'run-task did not return machine_readable_status'
}

$artifacts = $run.data.artifacts
$required = @{
    task_result_json = $artifacts.task_result_json
    task_events_jsonl = $artifacts.task_events_jsonl
    task_report_md = $artifacts.task_report_md
    evidence_index_md = $artifacts.evidence_index_md
}
foreach ($name in $required.Keys) {
    if (-not $required[$name] -or -not (Test-Path -LiteralPath $required[$name])) { Fail "Missing artifact $name" }
}

$resultJson = Get-Content -LiteralPath $required.task_result_json -Raw | ConvertFrom-Json
if ($resultJson.current_state -ne 'completed' -or $resultJson.ok -ne $true) { Fail 'task_result.json schema/status mismatch' }

$eventLines = Get-Content -LiteralPath $required.task_events_jsonl
if (@($eventLines).Count -lt 1) { Fail 'task_events.jsonl is empty' }
foreach ($line in $eventLines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $event = $line | ConvertFrom-Json
    foreach ($field in @('timestamp','task_id','step_id','state','ok','message')) {
        if (-not ($event.PSObject.Properties.Name -contains $field)) { Fail "task_events.jsonl event missing $field" }
    }
}

$reportText = Get-Content -LiteralPath $required.task_report_md -Raw
if ($reportText -notmatch 'Step Timeline' -or $reportText -notmatch 'Safety') { Fail 'task_report.md missing readable sections' }

$evidenceText = Get-Content -LiteralPath $required.evidence_index_md -Raw
foreach ($marker in @('task_result.json','task_events.jsonl','task_report.md')) {
    if ($evidenceText -notmatch [regex]::Escape($marker)) { Fail "evidence_index.md missing $marker" }
}

$status = Invoke-Json -CommandArgs @('task-status','--task-id',$run.data.task_id)
if (-not $status.ok -or $status.data.machine_readable_status.state -ne 'completed') { Fail 'task-status machine-readable compatibility failed' }

$lines = @(
    '# v5.7.4 Task Report Compatibility Selftest',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- task_result.json: $($required.task_result_json)",
    "- task_events.jsonl: $($required.task_events_jsonl)",
    "- task_report.md: $($required.task_report_md)",
    "- evidence_index.md: $($required.evidence_index_md)",
    '- machine-readable status: PASS'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.7 task report compatibility selftest'
Write-Host "Report: $Report"
