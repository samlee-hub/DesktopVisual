param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts\benchmark\full_access'
$ReportDir = Join-Path $Artifacts 'reports'
$Generated = Join-Path $Artifacts 'generated'
$SummaryPath = Join-Path $Artifacts 'full_access_benchmark_summary.json'
$ReportPath = Join-Path $Artifacts 'full_access_benchmark_report.md'
$PermissionArtifacts = Join-Path $Root 'artifacts\permission'
$SessionPath = Join-Path $PermissionArtifacts 'full_access_session.json'
New-Item -ItemType Directory -Force -Path $Artifacts,$ReportDir,$Generated,$PermissionArtifacts | Out-Null

function Invoke-AgentJson {
    param([string[]]$CmdArgs, [int[]]$AllowedExitCodes = @(0,1,2))
    $started = Get-Date
    $raw = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    $duration = [int]((Get-Date) - $started).TotalMilliseconds
    $text = ($raw | Out-String).Trim()
    $json = $null
    try { if ($text) { $json = $text | ConvertFrom-Json } } catch { $json = $null }
    [pscustomobject]@{ ExitCode = $exit; Json = $json; Raw = $text; DurationMs = $duration }
}

function Get-ErrorCode($Result) {
    if ($Result.Json -and $Result.Json.error -and $Result.Json.error.code) { return [string]$Result.Json.error.code }
    return ''
}

function New-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$OutcomeKind,
        [string]$ErrorCode = '',
        [string]$SkippedReason = '',
        [int]$DurationMs = 0,
        [int]$StepCount = 0,
        [hashtable]$Metrics = @{},
        [string[]]$Artifacts = @(),
        [string]$ReportPath = ''
    )
    [pscustomobject]@{
        name = $Name
        status = $Status
        outcome_kind = $OutcomeKind
        error_code = $ErrorCode
        skipped_reason = $SkippedReason
        duration_ms = $DurationMs
        step_count = $StepCount
        metrics = $Metrics
        artifacts = $Artifacts
        report_path = $ReportPath
    }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function New-FullAccessSession {
    param([string]$SessionId = 'full-access-benchmark-session')
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    @{
        session_id = $SessionId
        permission_mode = 'FULL_ACCESS'
        scope = 'session-only'
        ttl_seconds = 900
        created_at_unix_ms = $now
        expires_at_unix_ms = ($now + 900000)
    } | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    return $SessionId
}

function Clear-FullAccessSession {
    Remove-Item -LiteralPath $SessionPath -ErrorAction SilentlyContinue
}

function Start-TestWindow {
    if (-not (Test-Path -LiteralPath $TestWindowExe)) { throw "Missing TestWindow.exe: $TestWindowExe" }
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 150
        if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-AgentJson -CmdArgs @('find','--title','Agent Test Window')
    } while (($find.ExitCode -ne 0 -or $find.Json.ok -ne $true) -and (Get-Date) -lt $deadline)
    if ($find.ExitCode -ne 0 -or $find.Json.ok -ne $true) { throw 'Agent Test Window did not appear.' }
    return $proc
}

function Stop-TestWindowProcess($Proc) {
    if ($Proc -and -not $Proc.HasExited) {
        $Proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 150
        if (-not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force }
    }
}

$results = New-Object System.Collections.Generic.List[object]
Clear-FullAccessSession

# 1. DEFAULT denial for broad capabilities.
$denied = @()
$denied += Invoke-AgentJson -CmdArgs @('policy-check','--title','Third Party App','--process','ThirdParty.exe','--action','third_party_apps','--permission-mode','DEFAULT')
$denied += Invoke-AgentJson -CmdArgs @('policy-check','--title','External Browser','--process','msedge.exe','--action','external_web','--permission-mode','DEFAULT')
$denied += Invoke-AgentJson -CmdArgs @('policy-check','--title','Chat Window','--process','Chat.exe','--action','communication','--permission-mode','DEFAULT')
$deniedOk = @($denied | Where-Object { $_.Json.ok -eq $false -and $_.Json.error.code -eq 'SAFETY_POLICY_DENIED' }).Count
$results.Add((New-Result -Name 'permission_mode_default_denied' -Status $(if ($deniedOk -eq 3) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'expected_safe_stop' -ErrorCode $(if ($deniedOk -eq 3) { 'SAFETY_POLICY_DENIED' } else { 'UNEXPECTED_PERMISSION_RESULT' }) -DurationMs (($denied | Measure-Object DurationMs -Sum).Sum) -StepCount 3 -Metrics @{ permission_mode_success = ($deniedOk -eq 3); stop_condition_success_rate = [math]::Round(($deniedOk / 3.0) * 100, 2) })) | Out-Null

# 2. Interactive unlock check. Non-interactive benchmark records the required gate.
$unlock = Invoke-AgentJson -CmdArgs @('unlock-full-access','--ttl','30','--scope','session-only')
$unlockSkipped = ($unlock.Json.ok -eq $false -and $unlock.Json.error.code -eq 'FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION')
$results.Add((New-Result -Name 'full_access_unlock' -Status $(if ($unlockSkipped) { 'SKIPPED' } else { 'FAIL' }) -OutcomeKind 'interactive_required' -ErrorCode (Get-ErrorCode $unlock) -SkippedReason $(if ($unlockSkipped) { 'interactive local terminal confirmation required' } else { '' }) -DurationMs $unlock.DurationMs -StepCount 1 -Metrics @{ full_access_unlock_success = $false; user_takeover_trigger_success = $unlockSkipped })) | Out-Null

$sessionId = New-FullAccessSession

# 3. FULL_ACCESS gated app launch against deterministic TestWindow.
Remove-Item -LiteralPath (Join-Path $Root 'artifacts\global_desktop_launch_history.txt') -ErrorAction SilentlyContinue
$launch = Invoke-AgentJson -CmdArgs @('launch-app','--kind','exe','--path',$TestWindowExe,'--target-title','Agent Test Window','--process','TestWindow.exe','--permission-mode','FULL_ACCESS','--full-access-session-id',$sessionId,'--wait-ms','5000')
$launchOk = ($launch.ExitCode -eq 0 -and $launch.Json.ok -eq $true)
$results.Add((New-Result -Name 'global_app_launch' -Status $(if ($launchOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'full_access_app_launch' -ErrorCode (Get-ErrorCode $launch) -DurationMs $launch.DurationMs -StepCount 1 -Metrics @{ permission_mode_success = $launchOk } -Artifacts @())) | Out-Null
Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 100; if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force } }

# 4. External web navigation in no-open simulated mode.
$web = Invoke-AgentJson -CmdArgs @('browser-nav','--url','https://example.test/desktopvisual-full-access','--no-open','true','--permission-mode','FULL_ACCESS','--full-access-session-id',$sessionId)
$webOk = ($web.ExitCode -eq 0 -and $web.Json.ok -eq $true)
$results.Add((New-Result -Name 'external_web_navigation' -Status $(if ($webOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'simulated_external_web' -ErrorCode (Get-ErrorCode $web) -DurationMs $web.DurationMs -StepCount 1 -Metrics @{ permission_mode_success = $webOk })) | Out-Null

# Local fixture pages.
$formHtml = Join-Path $Generated 'mixed_form.html'
Write-Text $formHtml @'
<html><body>
<label for="name">Name</label><input id="name" type="text" />
<input name="choice" type="radio" value="a" data-label="Choice A" />
<input name="choice" type="radio" value="b" data-label="Choice B" />
<input id="agree" type="checkbox" data-label="Agree" />
<select id="plan" data-label="Plan"><option value="basic">Basic</option><option value="pro">Pro</option></select>
<textarea id="notes" data-label="Notes"></textarea>
<button id="submit">Submit</button>
</body></html>
'@

# 5. Form semantics mixed classification.
$formChecks = @(
    @{ field='name'; type='textbox' },
    @{ field='choice'; type='radio' },
    @{ field='agree'; type='checkbox' },
    @{ field='plan'; type='dropdown' },
    @{ field='notes'; type='textarea' }
)
$correct = 0
$formDuration = 0
foreach ($check in $formChecks) {
    $fc = Invoke-AgentJson -CmdArgs @('form-control','--html',$formHtml,'--field-id',$check.field)
    $formDuration += $fc.DurationMs
    if ($fc.Json.ok -eq $true -and $fc.Json.data.control.control_type -eq $check.type) { $correct++ }
}
$accuracy = [math]::Round(($correct / [double]$formChecks.Count) * 100, 2)
$results.Add((New-Result -Name 'form_semantics_mixed' -Status $(if ($correct -eq $formChecks.Count) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'local_form_semantics' -DurationMs $formDuration -StepCount $formChecks.Count -Metrics @{ form_control_classification_accuracy = $accuracy } -Artifacts @($formHtml))) | Out-Null

# 6. Decision task form.
$decision = Invoke-AgentJson -CmdArgs @('decision-eval','--html',$formHtml,'--user-goal','choose pro plan','--field-id','plan','--value','pro','--allow-submit')
$decisionOk = ($decision.ExitCode -eq 0 -and $decision.Json.ok -eq $true)
$results.Add((New-Result -Name 'decision_task_form' -Status $(if ($decisionOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'local_decision' -ErrorCode (Get-ErrorCode $decision) -DurationMs $decision.DurationMs -StepCount 1 -Metrics @{ decision_task_success_rate = $(if ($decisionOk) { 100 } else { 0 }) })) | Out-Null

# 7. Checkpoint and loop guard.
$tw = $null
try {
    $tw = Start-TestWindow
    $loopTask = Join-Path $Generated 'loop_guard.task.json'
    $loopReport = Join-Path $ReportDir 'checkpoint_loop_guard.md'
    @{
        version = 1
        name = 'full_access_loop_guard'
        target = @{ title = 'Agent Test Window'; process = 'TestWindow.exe' }
        loop_guard = @{ repeated_action_limit = 1 }
        steps = @(
            @{ name = 'checkpoint'; type = 'checkpoint'; observed_summary = 'before repeated waits' },
            @{ name = 'wait1'; type = 'wait'; wait_ms = 1 },
            @{ name = 'wait2'; type = 'wait'; wait_ms = 1 }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $loopTask -Encoding UTF8
    $loop = Invoke-AgentJson -CmdArgs @('run-task','--file',$loopTask,'--report',$loopReport)
    $loopOk = ($loop.Json.ok -eq $false -and $loop.Json.error.code -eq 'REPEATED_ACTION_LIMIT')
    $results.Add((New-Result -Name 'checkpoint_loop_guard' -Status $(if ($loopOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'expected_safe_stop' -ErrorCode (Get-ErrorCode $loop) -DurationMs $loop.DurationMs -StepCount $(if ($loop.Json.data.steps) { [int]$loop.Json.data.steps } else { 0 }) -Metrics @{ loop_guard_trigger_success = $loopOk; stop_condition_success_rate = $(if ($loopOk) { 100 } else { 0 }) } -Artifacts @($loopTask,$loopReport) -ReportPath $loopReport)) | Out-Null
} finally {
    Stop-TestWindowProcess $tw
}

# 8. Communication simulated task.
$tw = $null
try {
    $tw = Start-TestWindow
    $commTask = Join-Path $Generated 'communication_simulated.task.json'
    $commReport = Join-Path $ReportDir 'communication_simulated.md'
    @{
        version = 1
        name = 'full_access_communication_simulated'
        permission_mode = 'FULL_ACCESS'
        full_access_session_id = $sessionId
        target = @{ title = 'Agent Test Window'; process = 'TestWindow.exe' }
        steps = @(
            @{ name = 'send simulated'; type = 'communication_step'; operation = 'send_message'; channel = 'local-email-sim'; target = 'alice@example.test'; subject = 'Status'; content = 'Local benchmark message'; content_summary = 'benchmark status'; user_requested_send = $true }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $commTask -Encoding UTF8
    $comm = Invoke-AgentJson -CmdArgs @('run-task','--file',$commTask,'--report',$commReport)
    $commOk = ($comm.Json.ok -eq $true)
    $results.Add((New-Result -Name 'communication_simulated' -Status $(if ($commOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'local_communication_sim' -ErrorCode (Get-ErrorCode $comm) -DurationMs $comm.DurationMs -StepCount $(if ($comm.Json.data.steps) { [int]$comm.Json.data.steps } else { 0 }) -Metrics @{ communication_simulation_success = $commOk } -Artifacts @($commTask,$commReport) -ReportPath $commReport)) | Out-Null
} finally {
    Stop-TestWindowProcess $tw
}

# 9. Coding workflow simulated.
$ojHtml = Join-Path $Generated 'oj_sample_pass.html'
Write-Text $ojHtml @'
<html data-problem-title="Two Sum"><body>
<h1>Two Sum</h1>
<section id="problem_statement">Given nums and target, return two indices.</section>
<section id="examples">Example sample passes.</section>
<section id="constraints">2 <= nums.length <= 10000.</section>
<textarea id="code" data-control-type="code_editor"></textarea>
<button id="run" data-action="run">Run Code</button>
<div id="result" data-result="sample_pass">Sample Pass</div>
</body></html>
'@
$coding = Invoke-AgentJson -CmdArgs @('coding-eval','--html',$ojHtml,'--user-goal','practice two sum','--action','run_code','--language','cpp')
$codingOk = ($coding.Json.ok -eq $true -and $coding.Json.data.coding_workflow_context.result_state -eq 'SAMPLE_PASS')
$results.Add((New-Result -Name 'coding_workflow_simulated' -Status $(if ($codingOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'local_coding_sim' -ErrorCode (Get-ErrorCode $coding) -DurationMs $coding.DurationMs -StepCount 1 -Metrics @{ coding_workflow_success = $codingOk } -Artifacts @($ojHtml))) | Out-Null

# 10. Assessment workflow permission notice.
$assessmentHtml = Join-Path $Generated 'assessment_permission_notice.html'
Write-Text $assessmentHtml '<html><body><h1>Online assessment</h1><textarea data-control-type="code_editor"></textarea><button>Run Code</button></body></html>'
$assessment = Invoke-AgentJson -CmdArgs @('coding-eval','--html',$assessmentHtml,'--user-goal','solve assessment','--action','read_problem')
$assessmentOk = ($assessment.Json.ok -eq $true -and $assessment.Json.data.coding_workflow_context.problem_title -eq 'Online assessment')
$results.Add((New-Result -Name 'assessment_permission_notice' -Status $(if ($assessmentOk) { 'PASS' } else { 'FAIL' }) -OutcomeKind 'public_release_permission_restriction_required' -ErrorCode (Get-ErrorCode $assessment) -DurationMs $assessment.DurationMs -StepCount 1 -Metrics @{ coding_workflow_success = $assessmentOk } -Artifacts @($assessmentHtml))) | Out-Null

Clear-FullAccessSession

$total = $results.Count
$pass = @($results | Where-Object status -eq 'PASS').Count
$fail = @($results | Where-Object status -eq 'FAIL').Count
$skipped = @($results | Where-Object status -eq 'SKIPPED').Count
$safeStops = @($results | Where-Object { $_.outcome_kind -eq 'expected_safe_stop' })
$safeStopPass = @($safeStops | Where-Object status -eq 'PASS').Count
$reportCount = @($results | Where-Object { $_.report_path -or $_.artifacts.Count -gt 0 }).Count

$metrics = [ordered]@{
    full_access_unlock_success = $false
    permission_mode_success = (@($results | Where-Object { $_.metrics.permission_mode_success -eq $true }).Count -ge 2)
    form_control_classification_accuracy = $accuracy
    decision_task_success_rate = $(if ($decisionOk) { 100 } else { 0 })
    loop_guard_trigger_success = @($results | Where-Object { $_.metrics.loop_guard_trigger_success -eq $true }).Count -gt 0
    user_takeover_trigger_success = @($results | Where-Object { $_.metrics.user_takeover_trigger_success -eq $true }).Count -gt 0
    communication_simulation_success = $commOk
    coding_workflow_success = $codingOk
    stop_condition_success_rate = $(if ($safeStops.Count -gt 0) { [math]::Round(($safeStopPass / [double]$safeStops.Count) * 100, 2) } else { 0 })
    report_completeness_score = [math]::Round(($reportCount / [double]$total) * 100, 2)
}

$summary = [pscustomobject]@{
    version = $Version
    timestamp = (Get-Date).ToString('s')
    total = $total
    pass = $pass
    fail = $fail
    skipped = $skipped
    pass_rate_excluding_skipped = $(if (($total - $skipped) -gt 0) { [math]::Round(($pass / [double]($total - $skipped)) * 100, 2) } else { 0 })
    metrics = $metrics
    artifacts = @($ReportPath,$SummaryPath,$ReportDir,$Generated)
    scenarios = $results
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# DesktopVisual Full Access Benchmark Report')
$lines.Add('')
$lines.Add("- Version: $Version")
$lines.Add("- Timestamp: $($summary.timestamp)")
$lines.Add("- PASS: $pass")
$lines.Add("- FAIL: $fail")
$lines.Add("- SKIPPED: $skipped")
$lines.Add("- report_completeness_score: $($metrics.report_completeness_score)%")
$lines.Add('')
$lines.Add('## Capability Matrix')
$lines.Add('')
$lines.Add('| scenario | status | outcome | error_code | skipped_reason | duration_ms |')
$lines.Add('|---|---|---|---|---|---:|')
foreach ($r in $results) {
    $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $r.name,$r.status,$r.outcome_kind,$r.error_code,($r.skipped_reason -replace '\|','/'),$r.duration_ms))
}
$lines.Add('')
$lines.Add('## Metrics')
$lines.Add('')
foreach ($key in $metrics.Keys) {
    $lines.Add("- ${key}: $($metrics[$key])")
}
$lines.Add('')
$lines.Add('## Boundary')
$lines.Add('')
$lines.Add('- No real accounts, real communications, browser profiles, raw motion data, bin/obj, or release artifacts are included.')
$lines.Add('- Interactive FULL_ACCESS unlock is recorded as SKIPPED in non-interactive harness runs; the refusal gate is evidence that unlock cannot be automated.')
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host "Full Access benchmark report: $ReportPath"
Write-Host "Full Access benchmark summary: $SummaryPath"
Write-Host "PASS=$pass FAIL=$fail SKIPPED=$skipped"
if ($fail -gt 0) { exit 1 }
exit 0
