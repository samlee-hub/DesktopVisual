param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.2.0_persistent_runtime_session_latency_gate'
$RunnerResultPath = Join-Path $ArtifactRoot 'v6_2_0_runner_raw_result.json'
$SelftestPath = Join-Path $ArtifactRoot 'runtime_session_selftest_result.json'
$CacheSelftestPath = Join-Path $ArtifactRoot 'runtime_session_cache_selftest_result.json'
$LatencyPath = Join-Path $ArtifactRoot 'latency_report.json'
$VerifierJsonPath = Join-Path $ArtifactRoot 'v6_2_0_verifier_report.json'
$VerifierMdPath = Join-Path $ArtifactRoot 'v6_2_0_verifier_report.md'

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Add-Finding {
    param([System.Collections.Generic.List[object]]$Findings, [string]$Code, [string]$Message, [string]$Path = '')
    $Findings.Add([pscustomobject]@{ code = $Code; message = $Message; path = $Path; blocking = $true }) | Out-Null
}

function Bool($Value) { return ($Value -eq $true) }

function All-Steps-Ok($DispatchData) {
    if (-not $DispatchData -or -not $DispatchData.step_results) { return $false }
    foreach ($step in @($DispatchData.step_results)) {
        if ($step.ok -ne $true) { return $false }
    }
    return $true
}

function Step-By-Id($DispatchData, [string]$StepId) {
    @($DispatchData.step_results) | Where-Object { $_.step_id -eq $StepId } | Select-Object -First 1
}

function Has-Session-Runtime-Files {
    $required = @(
        'src\winagent\RuntimeSession.cpp',
        'src\winagent\SessionManager.cpp',
        'src\winagent\SessionObserveCache.cpp',
        'src\winagent\SessionLocatorCache.cpp',
        'src\winagent\SessionCommandDispatcher.cpp',
        'src\winagent\LatencyTracker.cpp'
    )
    foreach ($rel in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $rel))) { return $false }
    }
    return $true
}

$findings = [System.Collections.Generic.List[object]]::new()
$runner = Read-JsonFile $RunnerResultPath
$selftest = Read-JsonFile $SelftestPath
$cache = Read-JsonFile $CacheSelftestPath
$latency = Read-JsonFile $LatencyPath

if (-not $runner) {
    Add-Finding $findings 'BLOCKED_RUNNER_EVIDENCE_MISSING' 'Runner raw result is missing.' $RunnerResultPath
} elseif ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding $findings 'BLOCKED_RAW_EVIDENCE_NOT_RAW' 'Runner must produce RAW_COMPLETED_UNVERIFIED, not PASS.' $RunnerResultPath
}

if (-not (Has-Session-Runtime-Files)) {
    Add-Finding $findings 'BLOCKED_SESSION_NOT_IN_RUNTIME' 'Required session Runtime source files are missing.' ''
}

$cases = if ($runner) { $runner.cases } else { $null }

$case1Pass = $false
if ($cases -and $cases.case_1_session_lifecycle) {
    $c = $cases.case_1_session_lifecycle
    $case1Pass =
        (Bool $c.start.ok) -and
        (Bool $c.start.data.session_created) -and
        (Bool $c.status.data.session_status_ok) -and
        (Bool $c.observe.data.session_observe_ok) -and
        (Bool $c.close.data.session_closed) -and
        ($c.closed_reject.error.code -eq 'STOP_SESSION_CLOSED')
}
if (-not $case1Pass) { Add-Finding $findings 'BLOCKED_SESSION_LIFECYCLE_FAILED' 'Session lifecycle raw evidence did not satisfy required lifecycle checks.' $RunnerResultPath }

$case2Pass = $false
if ($cases -and $cases.case_2_one_shot_compatibility) {
    $commands = @($cases.case_2_one_shot_compatibility.commands)
    $allOk = $commands.Count -ge 4
    $noSessionArg = $true
    foreach ($cmd in $commands) {
        if ($cmd.json.ok -ne $true) { $allOk = $false }
        if ((@($cmd.args) -join ' ') -match '--session-id') { $noSessionArg = $false }
    }
    $stateRead = $commands | Where-Object { $_.json.command -eq 'read-file' } | Select-Object -First 1
    $case2Pass = $allOk -and $noSessionArg -and ($stateRead.json.data.content -match 'last_text=abc')
}
if (-not $case2Pass) { Add-Finding $findings 'BLOCKED_ONESHOT_COMPAT_REGRESSION' 'One-shot legacy command evidence failed or used a session id.' $RunnerResultPath }

$case3Pass = $false
if ($cases -and $cases.case_3_10_step_session_workflow) {
    $d = $cases.case_3_10_step_session_workflow.dispatch.command.data
    $case3Pass =
        (Bool $d.all_steps_verified) -and
        ([int]$d.session_command_count -ge 10) -and
        ([int]$d.process_restart_count -le 1) -and
        ($d.continued_action_after_wrong_context -eq $false)
    $typed = @($d.step_results | Where-Object { $_.action -eq 'type' })
    foreach ($step in $typed) {
        if ($step.data.typed_text_verified -ne $true) { $case3Pass = $false }
    }
}
if (-not $case3Pass) { Add-Finding $findings 'BLOCKED_10_STEP_SESSION_WORKFLOW_FAILED' '10-step session workflow did not verify all required step properties.' $RunnerResultPath }

$case4Pass = $false
if ($cases -and $cases.case_4_browser_form_session_workflow) {
    $d = $cases.case_4_browser_form_session_workflow.dispatch.command.data
    $typedOk = $true
    foreach ($step in @($d.step_results | Where-Object { $_.action -eq 'type' })) {
        if ($step.data.typed_text_verified -ne $true -or $step.data.context_guard_each_step -ne $true) { $typedOk = $false }
    }
    $send = Step-By-Id $d 'b08_click_send'
    $case4Pass =
        (Bool $d.all_steps_verified) -and
        (Bool $d.session_reuse_enabled) -and
        $typedOk -and
        ($send.data.verify.verified -eq $true)
}
if (-not $case4Pass) { Add-Finding $findings 'BLOCKED_BROWSER_FORM_SESSION_WORKFLOW_FAILED' 'Browser form session workflow did not prove typed/result verification through Runtime session.' $RunnerResultPath }

$case5Pass = $false
if ($cases -and $cases.case_5_scroll_and_locate_session_workflow) {
    $d = $cases.case_5_scroll_and_locate_session_workflow.dispatch.command.data
    $scroll = Step-By-Id $d 'c02_scroll'
    $locate = Step-By-Id $d 'c04_locate_target'
    $case5Pass =
        (Bool $d.all_steps_verified) -and
        ($scroll.data.scroll_progress_detected -eq $true) -and
        ($locate.data.target_found -eq $true) -and
        ($locate.data.stale_rect_not_used -eq $true)
}
if (-not $case5Pass) { Add-Finding $findings 'BLOCKED_SCROLL_AND_LOCATE_SESSION_WORKFLOW_FAILED' 'Scroll-and-locate session workflow did not prove progress, target_found, and stale_rect_not_used.' $RunnerResultPath }

$case6Pass = $false
if ($cases -and $cases.case_6_wrong_context_inside_session) {
    $d = $cases.case_6_wrong_context_inside_session.dispatch.command.data
    $first = @($d.step_results) | Select-Object -First 1
    $case6Pass =
        ($first.ok -eq $false) -and
        (@('STOP_WRONG_CONTEXT', 'STOP_SESSION_FOREGROUND_CHANGED') -contains [string]$first.error_code) -and
        ($first.action_executed -eq $false) -and
        ($d.stopped_on_failure -eq $true) -and
        ([int]$d.executed_step_count -eq 1) -and
        ($d.continued_action_after_wrong_context -eq $false)
}
if (-not $case6Pass) { Add-Finding $findings 'BLOCKED_SESSION_CONTEXT_GUARD_REGRESSION' 'Wrong context session action was not stopped safely.' $RunnerResultPath }

$case7Pass = $false
if ($cache) {
    $case7Pass =
        ($cache.status -eq 'PASS') -and
        ($cache.locator_cache.cache_hit_attempted -eq $true) -and
        ($cache.locator_cache.stale_target_detected -eq $true) -and
        ($cache.locator_cache.old_rect_not_clicked -eq $true) -and
        (@('STOP_TARGET_STALE', 'force_reobserve') -contains [string]$cache.locator_cache.stop_code)
}
if (-not $case7Pass) { Add-Finding $findings 'BLOCKED_SESSION_CACHE_STALE_TARGET' 'Cache invalidation/stale target evidence failed.' $CacheSelftestPath }

$case8Pass = $false
if ($latency) {
    $case8Pass =
        ($latency.status -eq 'PASS') -and
        ($latency.one_shot_latency_reported -eq $true) -and
        ($latency.persistent_latency_reported -eq $true) -and
        ($latency.process_restart_count_reduced -eq $true) -and
        ($latency.average_step_latency_reported -eq $true) -and
        ($latency.p95_step_latency_reported -eq $true) -and
        ([int]$latency.persistent_session.process_restart_count -lt [int]$latency.one_shot_baseline.process_restart_count)
}
if (-not $case8Pass) { Add-Finding $findings 'BLOCKED_LATENCY_GATE_NOT_MET' 'Latency report did not satisfy v6.2.0 latency comparison requirements.' $LatencyPath }

if (-not $selftest -or $selftest.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_RUNTIME_SESSION_SELFTEST_FAILED' 'runtime_session_selftest result is missing or not PASS.' $SelftestPath
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$result = [ordered]@{
    schema_version = 'v6.2.0.persistent_runtime.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    session_lifecycle_pass = $case1Pass
    one_shot_compatibility_pass = $case2Pass
    ten_step_session_workflow_pass = $case3Pass
    browser_form_session_workflow_pass = $case4Pass
    scroll_and_locate_session_workflow_pass = $case5Pass
    wrong_context_inside_session_pass = $case6Pass
    cache_invalidation_pass = $case7Pass
    latency_comparison_pass = $case8Pass
    no_raw_completed_unverified_as_pass = ($runner -and $runner.status -eq 'RAW_COMPLETED_UNVERIFIED' -and $status -eq 'PASS')
    no_runner_only_implementation = (Has-Session-Runtime-Files)
    findings = @($findings.ToArray())
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $VerifierJsonPath -Encoding UTF8

$findingLines = @($findings.ToArray()) | ForEach-Object { "- $($_.code): $($_.message) $($_.path)" }
if ($findingLines.Count -eq 0) { $findingLines = @('- No blocking findings.') }
@(
    '# v6.2.0 Persistent Runtime Verifier Report',
    '',
    "- Status: $status",
    "- Session lifecycle: $case1Pass",
    "- One-shot compatibility: $case2Pass",
    "- 10-step session workflow: $case3Pass",
    "- Browser form session workflow: $case4Pass",
    "- Scroll-and-locate session workflow: $case5Pass",
    "- Wrong context inside session: $case6Pass",
    "- Cache invalidation: $case7Pass",
    "- Latency comparison: $case8Pass",
    "- No runner-only implementation: $(Has-Session-Runtime-Files)",
    '',
    '## Findings'
) + $findingLines | Set-Content -LiteralPath $VerifierMdPath -Encoding UTF8

if ($status -ne 'PASS') {
    throw (($findings | ForEach-Object { $_.code }) -join '; ')
}

Write-Output 'V6_2_0_VERIFIER_PASS'
