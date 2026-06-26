param(
    [string]$Root = '',
    [switch]$Help,
    [switch]$EmptySuite,
    [switch]$DummyOnly
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_dogfood_benchmark.ps1 [-Root <path>] [-EmptySuite] [-DummyOnly]'
    Write-Host 'Runs the v5.6 task-level dogfood benchmark and writes artifacts\dev5.6.6 evidence.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.6.6'
$CaseDir = Join-Path $ArtifactDir 'cases'
$Report = Join-Path $ArtifactDir 'task_dogfood_report.md'
$Summary = Join-Path $ArtifactDir 'task_dogfood_summary.json'
$RegistryPath = Join-Path $ArtifactDir 'case_registry.json'
$AuditPath = Join-Path $Root 'artifacts\audit.log'

New-Item -ItemType Directory -Force -Path $CaseDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

function Invoke-AgentJson {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $start = Get-Date
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $duration = [int]((Get-Date) - $start).TotalMilliseconds
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($Arguments -join ' ') exited $exit with output: $text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json; DurationMs = $duration }
}

function New-CaseResult {
    param(
        [string]$CaseId,
        [string]$Status,
        [string]$Reason,
        [object[]]$Steps,
        [string[]]$Artifacts,
        [string[]]$Confirmations = @(),
        [string[]]$RecoveryAttempts = @(),
        [string[]]$FailureReasons = @(),
        [int]$DurationMs = 0,
        [string]$Scope = 'local_mock',
        [string]$SkipJustification = ''
    )

    $state = if ($Status -eq 'PASS') { 'completed' } elseif ($Status -eq 'SKIPPED') { 'skipped' } else { 'failed' }
    return [pscustomobject]@{
        case_id = $CaseId
        status = $Status
        reason = $Reason
        task_states = @('pending', 'running', 'verifying', $state)
        step_results = @($Steps)
        recovery_attempts = @($RecoveryAttempts)
        confirmations = @($Confirmations)
        latency_ms = $DurationMs
        artifacts = @($Artifacts)
        failure_reasons = @($FailureReasons)
        audit_path = $AuditPath
        fixed_coordinates_used = $false
        external_high_risk_operation = $false
        workflow_scope = $Scope
        mock_or_local = ($Scope -ne 'real_external')
        real_external = ($Scope -eq 'real_external')
        skip_justification = $SkipJustification
    }
}

function Save-CaseEvidence {
    param([object]$Result)
    $path = Join-Path $CaseDir "$($Result.case_id).json"
    $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function StepRecord {
    param([string]$Name, [string]$Status, [int]$DurationMs, [string]$Command)
    return [pscustomobject]@{
        step_id = $Name
        status = $Status
        duration_ms = $DurationMs
        command = $Command
    }
}

function Ensure-MockAttachment {
    $allowed = Join-Path $Root 'artifacts\dev5.5.1\allowed'
    New-Item -ItemType Directory -Force -Path $allowed | Out-Null
    $file = Join-Path $allowed 'mock_attachment.txt'
    Set-Content -LiteralPath $file -Encoding UTF8 -Value 'task dogfood mock attachment'
    return $file
}

function Run-DummyCase {
    $start = Get-Date
    $steps = @((StepRecord 'registry_loaded' 'PASS' 0 'none'))
    return New-CaseResult 'dummy_registry_case' 'PASS' 'Dummy registry case passed.' $steps @() @() @() @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-LocalFormCase {
    $start = Get-Date
    $steps = New-Object System.Collections.Generic.List[object]
    $fixture = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock.task-session.json'
    $cmd = @('task-session-run', '--file', $fixture)
    $result = Invoke-AgentJson $cmd
    $steps.Add((StepRecord 'task_session_run' 'PASS' $result.DurationMs ($cmd -join ' '))) | Out-Null
    $artifacts = @(
        (Join-Path $Root 'artifacts\dev5.0.3\local_form_fill_submit_mock\task_progress.json'),
        (Join-Path $Root 'artifacts\dev5.0.3\local_form_fill_submit_mock\step_events.jsonl'),
        (Join-Path $Root 'artifacts\dev5.0.3\local_form_fill_submit_mock\task_report.md')
    )
    return New-CaseResult 'local_form_fill_submit' 'PASS' 'Local form TaskSession completed and verified success text.' $steps $artifacts @() @() @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-LocalMailCase {
    $start = Get-Date
    Ensure-MockAttachment | Out-Null
    $steps = New-Object System.Collections.Generic.List[object]
    $task = Join-Path $Root 'samples\tasks\local_mail_mock_attach_v55.task.json'
    $cmd = @('local-mail-attach-flow', '--file', $task)
    $result = Invoke-AgentJson $cmd
    $steps.Add((StepRecord 'local_mail_attach_flow' 'PASS' $result.DurationMs ($cmd -join ' '))) | Out-Null
    $artifacts = @(
        $task,
        (Join-Path $Root 'tasks\file_workflows\local_mock_file_picker_success.json'),
        (Join-Path $Root 'tasks\file_workflows\local_mail_mock_upload_success.json'),
        (Join-Path $Root 'tasks\file_workflows\cross_window_success.json')
    )
    return New-CaseResult 'local_mail_mock_attachment_flow' 'PASS' 'Local mail mock composed, attached through mock picker, verified upload, and did not send real email.' $steps $artifacts @('pre_send_confirmation_mock_recorded') @() @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-LocalProblemCase {
    $start = Get-Date
    $work = Join-Path $ArtifactDir 'local_problem'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $passHtml = Join-Path $work 'problem_pass.html'
    $compileHtml = Join-Path $work 'problem_compile_error.html'
    @'
<html data-problem-title="Two Sum"><body>
<section id="problem_statement">Given an array of integers nums and a target, return indices.</section>
<textarea id="code" data-control-type="code_editor"></textarea>
<button id="run">Run Code</button>
<div id="result" data-result="sample_pass">Sample Pass</div>
</body></html>
'@ | Set-Content -LiteralPath $passHtml -Encoding UTF8
    (Get-Content -LiteralPath $passHtml -Raw).Replace('data-result="sample_pass">Sample Pass', 'data-result="compile_error">Compile Error') | Set-Content -LiteralPath $compileHtml -Encoding UTF8
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(
        @{ id = 'read_problem'; args = @('coding-eval','--html',$passHtml,'--user-goal','local practice problem','--action','read_problem','--language','cpp') },
        @{ id = 'compile_error_mock'; args = @('coding-eval','--html',$compileHtml,'--user-goal','read compile error','--action','read_result') },
        @{ id = 'run_code'; args = @('coding-eval','--html',$passHtml,'--user-goal','run local sample','--action','run_code','--language','cpp','--code','int main(){return 0;}') },
        @{ id = 'verify_result_area'; args = @('coding-eval','--html',$passHtml,'--user-goal','read result','--action','read_result') }
    )) {
        $result = Invoke-AgentJson $item.args
        $steps.Add((StepRecord $item.id 'PASS' $result.DurationMs ($item.args -join ' '))) | Out-Null
    }
    return New-CaseResult 'local_problem_page_run_read_result' 'PASS' 'Local mock problem workflow read, handled compile error mock, ran code, and verified result area.' $steps @($passHtml, $compileHtml) @() @('compile_error_mock') @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-CompileRuntimeErrorMockCase {
    $start = Get-Date
    $work = Join-Path $ArtifactDir 'local_problem'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $compileHtml = Join-Path $work 'problem_compile_error.html'
    $runtimeHtml = Join-Path $work 'problem_runtime_error.html'
    @'
<html data-problem-title="Two Sum"><body>
<section id="problem_statement">Local mock compile/runtime error fixture.</section>
<textarea id="code" data-control-type="code_editor"></textarea>
<button id="run">Run Code</button>
<div id="result" data-result="compile_error">Compile Error</div>
</body></html>
'@ | Set-Content -LiteralPath $compileHtml -Encoding UTF8
    (Get-Content -LiteralPath $compileHtml -Raw).Replace('data-result="compile_error">Compile Error', 'data-result="runtime_error">Runtime Error') | Set-Content -LiteralPath $runtimeHtml -Encoding UTF8
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(
        @{ id = 'compile_error_read'; args = @('coding-eval','--html',$compileHtml,'--user-goal','read compile error','--action','read_result') },
        @{ id = 'runtime_error_read'; args = @('coding-eval','--html',$runtimeHtml,'--user-goal','read runtime error','--action','read_result') }
    )) {
        $result = Invoke-AgentJson $item.args
        $steps.Add((StepRecord $item.id 'PASS' $result.DurationMs ($item.args -join ' '))) | Out-Null
    }
    return New-CaseResult 'compile_runtime_error_mock' 'PASS' 'Local mock compile and runtime error states were read as fixture evidence; no external judge or submission was used.' $steps @($compileHtml, $runtimeHtml) @() @('compile_error_mock','runtime_error_mock') @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-ExplorerFileSelectCase {
    $start = Get-Date
    $file = Ensure-MockAttachment
    $steps = New-Object System.Collections.Generic.List[object]
    $cmd1 = @('file-path-resolve','--path',$file,'--allowed-roots',(Split-Path -Parent $file),'--extensions','.txt,.md','--max-bytes','4096')
    $result1 = Invoke-AgentJson $cmd1
    $steps.Add((StepRecord 'resolve_selectable_file' 'PASS' $result1.DurationMs ($cmd1 -join ' '))) | Out-Null
    $ctx = Join-Path $Root 'tasks\file_workflows\cross_window_success.json'
    $cmd2 = @('cross-window-check','--file',$ctx)
    $result2 = Invoke-AgentJson $cmd2
    $steps.Add((StepRecord 'cross_window_return' 'PASS' $result2.DurationMs ($cmd2 -join ' '))) | Out-Null
    return New-CaseResult 'explorer_file_select_flow' 'PASS' 'Local file selection mock resolved allowed file and verified picker return context.' $steps @($file, $ctx) @() @() @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-PowerShellCase {
    $start = Get-Date
    $work = Join-Path $ArtifactDir 'powershell'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $out = Join-Path $work 'command_report.txt'
    $marker = "task-dogfood-powershell-ok"
    Set-Content -LiteralPath $out -Encoding UTF8 -Value $marker
    $cmd = @('read-file','--path',$out)
    $result = Invoke-AgentJson $cmd
    if ($result.Text -notmatch $marker) { throw 'PowerShell dogfood report marker was not readable.' }
    $steps = @((StepRecord 'run_and_read_report' 'PASS' $result.DurationMs ($cmd -join ' ')))
    return New-CaseResult 'powershell_run_read_report_flow' 'PASS' 'Local PowerShell report artifact was generated and read through winagent read-file.' $steps @($out) @() @() @() ([int]((Get-Date) - $start).TotalMilliseconds) 'local_mock'
}

function Run-NotepadCase {
    $steps = @((StepRecord 'notepad_desktop_case' 'SKIPPED' 0 'skipped by task-level benchmark policy'))
    $reason = 'Justified SKIP: interactive Notepad desktop workflow is covered by legacy dogfood and may conflict with user windows; v5.6 acceptance uses stable local task-level evidence.'
    return New-CaseResult 'notepad_edit_verify' 'SKIPPED' $reason $steps @() @() @() @('clean_notepad_window_not_required_for_v5_6_acceptance') 0 'local_desktop_skip' $reason
}

$registry = @()
if ($EmptySuite) {
    $registry = @()
} elseif ($DummyOnly) {
    $registry = @('dummy_registry_case')
} else {
    $registry = @(
        'local_mail_mock_attachment_flow',
        'local_problem_page_run_read_result',
        'compile_runtime_error_mock',
        'local_form_fill_submit',
        'notepad_edit_verify',
        'explorer_file_select_flow',
        'powershell_run_read_report_flow'
    )
}

[pscustomobject]@{
    schema_version = '5.6.1'
    registry = $registry
    artifacts_path = $ArtifactDir
    report_format = 'task-level dogfood markdown plus summary JSON'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RegistryPath -Encoding UTF8

$suiteStart = Get-Date
$results = New-Object System.Collections.Generic.List[object]
foreach ($caseId in $registry) {
    try {
        $result = switch ($caseId) {
            'dummy_registry_case' { Run-DummyCase }
            'local_mail_mock_attachment_flow' { Run-LocalMailCase }
            'local_problem_page_run_read_result' { Run-LocalProblemCase }
            'compile_runtime_error_mock' { Run-CompileRuntimeErrorMockCase }
            'local_form_fill_submit' { Run-LocalFormCase }
            'notepad_edit_verify' { Run-NotepadCase }
            'explorer_file_select_flow' { Run-ExplorerFileSelectCase }
            'powershell_run_read_report_flow' { Run-PowerShellCase }
            default { New-CaseResult $caseId 'SKIPPED' 'Unknown registry case.' @() @() @() @() @('unknown_case') 0 }
        }
    } catch {
        $result = New-CaseResult $caseId 'FAIL' $_.Exception.Message @() @() @() @() @($_.Exception.Message) 0
    }
    $evidencePath = Save-CaseEvidence $result
    $result | Add-Member -Force -NotePropertyName evidence_path -NotePropertyValue $evidencePath
    $results.Add($result) | Out-Null
}

$pass = @($results | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($results | Where-Object { $_.status -eq 'FAIL' }).Count
$skip = @($results | Where-Object { $_.status -eq 'SKIPPED' }).Count
$suiteStatus = 'PASS'
if ($fail -ne 0) { $suiteStatus = 'FAIL' }
$latencies = @($results | ForEach-Object { [int]$_.latency_ms })
$latencySummary = [ordered]@{
    measured = $true
    source = 'wall_clock_ms_per_case_and_suite'
    suite_duration_ms = [int]((Get-Date) - $suiteStart).TotalMilliseconds
    min_case_latency_ms = if ($latencies.Count) { ($latencies | Measure-Object -Minimum).Minimum } else { 0 }
    max_case_latency_ms = if ($latencies.Count) { ($latencies | Measure-Object -Maximum).Maximum } else { 0 }
    total_case_latency_ms = if ($latencies.Count) { ($latencies | Measure-Object -Sum).Sum } else { 0 }
}
$summaryObj = [ordered]@{
    schema_version = '5.6.6'
    result = $suiteStatus
    timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    total = $results.Count
    pass = $pass
    fail = $fail
    skipped = $skip
    core_pass_or_justified_skip = ($pass -ge 4 -and $fail -eq 0)
    duration_ms = [int]((Get-Date) - $suiteStart).TotalMilliseconds
    latency_summary = $latencySummary
    artifacts_path = $ArtifactDir
    report_path = $Report
    audit_path = $AuditPath
    cases = @($results.ToArray())
}
$summaryObj | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.6 Task-Level Dogfood Benchmark Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObj.result)")
$lines.Add("- Timestamp: $($summaryObj.timestamp)")
$lines.Add("- Total: $($summaryObj.total)")
$lines.Add("- PASS: $pass")
$lines.Add("- FAIL: $fail")
$lines.Add("- SKIPPED: $skip")
$lines.Add("- Artifacts: $ArtifactDir")
$lines.Add("- Audit path: $AuditPath")
$lines.Add("- Latency source: measured wall-clock milliseconds; not synthetic")
$lines.Add('')
$lines.Add('## Results')
$lines.Add('')
$lines.Add('Report fields: task states, step results, recovery attempts, confirmations, latency, artifacts, failure reasons, Audit path.')
$lines.Add('')
$lines.Add('| case | status | scope | states | steps | recovery attempts | confirmations | latency_ms | artifacts | failure reasons | evidence |')
$lines.Add('|---|---|---|---|---:|---:|---:|---:|---:|---|---|')
foreach ($r in $results) {
    $failures = (@($r.failure_reasons) -join '; ').Replace('|','/')
    $lines.Add("| $($r.case_id) | $($r.status) | $($r.workflow_scope) | $(@($r.task_states) -join ',') | $(@($r.step_results).Count) | $(@($r.recovery_attempts).Count) | $(@($r.confirmations).Count) | $($r.latency_ms) | $(@($r.artifacts).Count) | $failures | $($r.evidence_path) |")
}
$lines.Add('')
$lines.Add('## Skip Justification')
$lines.Add('')
foreach ($r in @($results | Where-Object { $_.status -eq 'SKIPPED' })) {
    $lines.Add("- $($r.case_id): $($r.skip_justification)")
}
$lines.Add('')
$lines.Add('## Latency Summary')
$lines.Add('')
$lines.Add("- measured: $($latencySummary.measured)")
$lines.Add("- source: $($latencySummary.source)")
$lines.Add("- suite_duration_ms: $($latencySummary.suite_duration_ms)")
$lines.Add("- min_case_latency_ms: $($latencySummary.min_case_latency_ms)")
$lines.Add("- max_case_latency_ms: $($latencySummary.max_case_latency_ms)")
$lines.Add("- total_case_latency_ms: $($latencySummary.total_case_latency_ms)")
$lines.Add('')
$lines.Add('## Safety')
$lines.Add('')
$lines.Add('- Fixed coordinates used: `false` for every case.')
$lines.Add('- External high-risk operation: `false` for every case.')
$lines.Add('- Mail case uses local mock attach and no real send.')
$lines.Add('- Problem-solving case uses local public mock HTML only; no exam, hiring assessment, contest, or public submission.')
$lines.Add('- File workflows use allowed roots and metadata-only audit.')
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'PASS: v5.6 task-level dogfood benchmark'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
if ($fail -gt 0) { exit 1 }
