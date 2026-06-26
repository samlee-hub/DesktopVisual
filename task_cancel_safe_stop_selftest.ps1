param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_cancel_safe_stop_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.7 cancellation and safe-stop task artifacts.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.7.3'
$FixtureDir = Join-Path $ArtifactDir 'fixtures'
$Report = Join-Path $ArtifactDir 'task_cancel_safe_stop_selftest_report.md'
$BaseTask = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json'

New-Item -ItemType Directory -Force -Path $FixtureDir | Out-Null

function Fail($Message) { throw "FAIL: $Message" }

function Invoke-Json([string[]]$CommandArgs, [int]$ExpectedExit = 0) {
    $output = & $WinAgent @CommandArgs 2>&1
    if ($LASTEXITCODE -ne $ExpectedExit) { Fail "Command exit $LASTEXITCODE, expected $ExpectedExit ($($CommandArgs -join ' ')): $output" }
    try { return ($output | Out-String) | ConvertFrom-Json } catch { Fail "Invalid JSON from $($CommandArgs -join ' '): $output" }
}

function New-CancelFixture([string]$TaskId) {
    $task = Get-Content -LiteralPath $BaseTask -Raw | ConvertFrom-Json
    $task.task_id = $TaskId
    $task.current_state = 'waiting'
    $task.result.task_id = $TaskId
    $rootRel = "artifacts/dev5.7.3/$TaskId"
    $task.artifacts.root = $rootRel
    $task.artifacts.events_jsonl = "$rootRel/task_events.jsonl"
    $task.artifacts.result_json = "$rootRel/task_result.json"
    $task.artifacts.report_md = "$rootRel/task_report.md"
    $path = Join-Path $FixtureDir "$TaskId.task-session.json"
    $task | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    $registry = Join-Path $Root "artifacts\task_runtime_v5_7\tasks\$TaskId.json"
    Remove-Item -LiteralPath $registry -ErrorAction SilentlyContinue
    return $path
}

$cases = @(
    @{ id = 'dev5_7_user_cancel'; reason = 'user cancel'; code = 'TASK_CANCELLED' },
    @{ id = 'dev5_7_timeout_cancel'; reason = 'timeout cancel'; code = 'TASK_TIMEOUT_CANCELLED' },
    @{ id = 'dev5_7_safety_stop'; reason = 'safety stop'; code = 'SAFETY_STOP' },
    @{ id = 'dev5_7_provider_unavailable_stop'; reason = 'provider unavailable stop'; code = 'PROVIDER_UNAVAILABLE_STOP' },
    @{ id = 'dev5_7_confirmation_timeout_stop'; reason = 'confirmation timeout stop'; code = 'CONFIRMATION_TIMEOUT_STOP' }
)

$results = @()
foreach ($case in $cases) {
    $fixture = New-CancelFixture $case.id
    $cancel = Invoke-Json -CommandArgs @('task-cancel','--file',$fixture,'--reason',$case.reason)
    if (-not $cancel.ok -or $cancel.data.cancelled -ne $true -or $cancel.data.current_state -ne 'stopped' -or $cancel.data.error_code -ne $case.code) {
        Fail "cancel case $($case.id) did not produce expected stopped result"
    }
    foreach ($field in @('task_result_json','task_events_jsonl','task_report_md','failure_dump_json','cancel_audit_json','evidence_index_md')) {
        $path = $cancel.data.artifacts.$field
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { Fail "$($case.id) missing artifact $field" }
    }
    $cancelAudit = Get-Content -LiteralPath $cancel.data.artifacts.cancel_audit_json -Raw | ConvertFrom-Json
    if ($cancelAudit.error_code -ne $case.code -or $cancelAudit.safety_override -ne $false -or $cancelAudit.action -ne 'task_cancel') {
        Fail "$($case.id) cancel audit artifact did not expose stop code and safety_override=false"
    }
    $eventText = Get-Content -LiteralPath $cancel.data.artifacts.task_events_jsonl -Raw
    if ($eventText -notmatch 'cancel_task') { Fail "$($case.id) task_events.jsonl missing cancel_task audit event" }
    $status = Invoke-Json -CommandArgs @('task-status','--task-id',$case.id)
    if (-not $status.ok -or $status.data.current_state -ne 'stopped' -or $status.data.machine_readable_status.error_code -ne $case.code) {
        Fail "status case $($case.id) did not expose stopped machine-readable status"
    }
    $reportJson = Invoke-Json -CommandArgs @('task-report','--task-id',$case.id)
    if (-not $reportJson.ok -or $reportJson.data.content -notmatch [regex]::Escape($case.code)) {
        Fail "report case $($case.id) missing stop code"
    }
    $results += [pscustomobject]@{ task_id = $case.id; stop_code = $case.code; status = 'PASS' }
}

$summaryPath = Join-Path $ArtifactDir 'task_cancel_safe_stop_summary.json'
@{
    schema_version = '5.7.3'
    result = 'PASS'
    total = $results.Count
    cases = $results
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$lines = @(
    '# v5.7.3 Task Cancel and Safe Stop Selftest',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- user cancel: PASS',
    '- timeout cancel: PASS',
    '- safety stop: PASS',
    '- provider unavailable stop: PASS',
    '- confirmation timeout stop: PASS',
    '- stop while waiting: PASS',
    '- cancel audit artifact: PASS',
    "- Summary: $summaryPath"
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.7 task cancel and safe stop selftest'
Write-Host "Report: $Report"
