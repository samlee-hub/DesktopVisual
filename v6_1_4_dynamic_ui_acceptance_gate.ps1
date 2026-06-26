param(
    [string]$Root = '',
    [switch]$StateGuardOnly
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactLeaf = if ($StateGuardOnly) { 'dev6.1.4_dynamic_app_web_click_accuracy_state_guard' } else { 'dev6.1.4_dynamic_app_web_click_accuracy_rerun' }
$ArtifactRoot = Join-Path $Root "artifacts\$ArtifactLeaf"
$RawRoot = Join-Path $ArtifactRoot 'raw'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$VerifiedCasesRoot = Join-Path $VerifiedRoot 'cases'
$ReportName = if ($StateGuardOnly) { 'acceptance_gate_report.md' } else { 'dynamic_ui_acceptance_gate_report.md' }
$ReportPath = Join-Path $ArtifactRoot $ReportName
$ResultPath = Join-Path $VerifiedRoot 'dynamic_ui_acceptance_gate_result.json'

New-Item -ItemType Directory -Force -Path $ArtifactRoot, $RawRoot, $VerifiedRoot | Out-Null

$Findings = New-Object System.Collections.Generic.List[object]

function RelPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($rootFull.Length) }
    return $Path
}

function Add-Finding([string]$Code, [string]$Message, [string]$Path = '', [bool]$Blocking = $true) {
    $Findings.Add([pscustomobject]@{ code = $Code; message = $Message; path = $Path; blocking = $Blocking }) | Out-Null
}

function Read-JsonFile([string]$Path, [string]$Label, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding 'MISSING_EVIDENCE' "Missing $Label." (RelPath $Path) $Required
        return $null
    }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch {
        Add-Finding 'JSON_PARSE_FAILED' "$Label is not valid JSON: $($_.Exception.Message)" (RelPath $Path) $Required
        return $null
    }
}

function Test-JsonlFile([string]$Path, [string]$Label, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding 'MISSING_EVIDENCE' "Missing $Label." (RelPath $Path) $Required
        return $false
    }
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $null = $line | ConvertFrom-Json } catch {
            Add-Finding 'JSONL_PARSE_FAILED' "$Label line $lineNo is not valid JSONL." (RelPath $Path) $Required
            return $false
        }
    }
    return $true
}

function Get-StateField([string]$Text, [string]$Field) {
    $m = [regex]::Match($Text, "(?m)^$([regex]::Escape($Field)):\s*(.+?)\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

$expected = if ($StateGuardOnly) {
    [ordered]@{
        'v6_1_4_wrong_context_negative_guard' = 'STRICT_WRONG_CONTEXT_STOP_PASS'
        'v6_1_4_baseline_regression_once' = 'STRICT_V6_1_4_BASELINE_REGRESSION_ONCE_PASS'
    }
} else {
    [ordered]@{
        'v6_1_4_pycharm_dynamic_coding_run' = 'STRICT_DYNAMIC_APP_PYCHARM_PASS'
        'v6_1_4_wechat_file_transfer_assistant_send' = 'STRICT_DYNAMIC_APP_WECHAT_FILE_TRANSFER_PASS'
        'v6_1_4_qq_mail_web_compose_send' = 'STRICT_DYNAMIC_WEB_QQ_MAIL_SEND_PASS'
        'v6_1_4_baseline_regression_once' = 'STRICT_V6_1_4_BASELINE_REGRESSION_ONCE_PASS'
    }
}

$caseRows = New-Object System.Collections.Generic.List[object]
$results = @()
foreach ($caseId in $expected.Keys) {
    $caseDir = Join-Path $VerifiedCasesRoot $caseId
    $result = Read-JsonFile (Join-Path $caseDir 'task_result.json') "$caseId task_result.json" $true
    if ($result) {
        $results += $result
        if ($result.actual_result -ne $expected[$caseId]) {
            Add-Finding 'CASE_RESULT_FAILED' "$caseId expected $($expected[$caseId]), got $($result.actual_result)." (RelPath (Join-Path $caseDir 'task_result.json')) $true
        }
        if ($result.verification_passed -ne $true) {
            Add-Finding 'CASE_VERIFICATION_FAILED' "$caseId verification_passed was not true." (RelPath (Join-Path $caseDir 'task_result.json')) $true
        }
        foreach ($field in @('raw_command_evidence_verified')) {
            if ($result.$field -ne $true) { Add-Finding 'STRICT_FIELD_FAILED' "$caseId requires $field=true." $caseId $true }
        }
        if ($result.heartbeat_present -ne $true) {
            Add-Finding 'HEARTBEAT_MISSING' "$caseId requires heartbeat_present=true." $caseId $true
        }
        if ([double]$result.heartbeat_max_gap_sec -gt 20) {
            Add-Finding 'HEARTBEAT_GAP_TOO_LARGE' "$caseId heartbeat gap is $($result.heartbeat_max_gap_sec), above 20 seconds." $caseId $true
        }
        if ($result.no_progress_timeout_enforced -ne $true) {
            Add-Finding 'NO_PROGRESS_GUARD_MISSING' "$caseId did not record no-progress/heartbeat guard evidence." $caseId $true
        }
        foreach ($field in @('synthetic_evidence_detected','placeholder_screenshot_detected','hardcoded_rect_detected','hardcoded_hwnd_detected','emergency_stop_triggered','false_positive_stop_detected')) {
            if ($result.$field -ne $false) { Add-Finding 'EVIDENCE_INTEGRITY_FAILED' "$caseId requires $field=false." $caseId $true }
        }
        foreach ($field in @('backend_action_count','js_dom_action_count','webdriver_count','cdp_count','playwright_count','selenium_count','uia_invoke_action_count','uia_value_action_count','cursor_outside_target_rect_count','wrong_target_click_count','wrong_field_input_count','misclick_count','stale_target_clicked_count','vlm_call_count','active_protection_bypass_attempt_count','command_timeout_missing_count','command_timeout_triggered_count')) {
            if ([int]$result.$field -ne 0) { Add-Finding 'FORBIDDEN_ACTION_DETECTED' "$caseId requires $field=0." $caseId $true }
        }
        foreach ($field in @('required_offset_field_missing_count','visual_evidence_missing_count','required_focus_field_missing_count','text_unverified_count')) {
            if ([int]$result.$field -ne 0) { Add-Finding 'REQUIRED_EVIDENCE_FIELD_MISSING' "$caseId requires $field=0." $caseId $true }
        }
        $actionCount = [int]$result.first_attempt_success_count + [int]$result.first_attempt_failure_count
        if ($caseId -ne 'v6_1_4_baseline_regression_once' -and $caseId -ne 'v6_1_4_wrong_context_negative_guard' -and $actionCount -le 0) {
            Add-Finding 'MISSING_ACTION_EVIDENCE' "$caseId has no click offset action evidence." $caseId $true
        }
        if ($actionCount -gt 0 -and [double]$result.first_attempt_success_rate -lt 0.80) {
            Add-Finding 'FIRST_ATTEMPT_RATE_TOO_LOW' "$caseId first_attempt_success_rate is $($result.first_attempt_success_rate), below 0.80." $caseId $true
        }
        $caseRows.Add([pscustomobject]@{ case_id = $caseId; expected = $expected[$caseId]; actual = $result.actual_result; verification_passed = $result.verification_passed }) | Out-Null
    }
    foreach ($jsonl in @('task_events.jsonl','action_trace.jsonl','locator_trace.jsonl','scroll_trace.jsonl','adaptive_loop_trace.jsonl','human_action_results.jsonl','focus_trace.jsonl','offset_trace.jsonl','context_trace.jsonl','raw_command_log.jsonl','heartbeat.jsonl')) {
        Test-JsonlFile (Join-Path $caseDir $jsonl) "$caseId $jsonl" $true | Out-Null
    }
    foreach ($dir in @('screenshots','overlays','crops')) {
        if (-not (Test-Path -LiteralPath (Join-Path $caseDir $dir) -PathType Container)) {
            Add-Finding 'MISSING_EVIDENCE_DIR' "$caseId missing $dir directory." (RelPath (Join-Path $caseDir $dir)) $true
        }
    }
}

$requiredReports = if ($StateGuardOnly) {
    @(
        'agent_context_digest.md',
        'file_discovery_report.md',
        'state_guard_design_report.md',
        'action_precondition_report.md',
        'wrong_context_negative_report.md',
        'browser_context_guard_report.md',
        'baseline_replay_state_guard_report.md',
        'scroll_gate_failure_reclassification_report.md',
        'runner_raw_evidence_report.md',
        'verifier_report.md',
        'regression_report.md',
        'evidence_index.md',
        'known_limits.md',
        'git_status_initial.txt',
        'git_status_final.txt',
        'modified_files.txt'
    )
} else {
    @(
        'agent_context_digest.md',
        'file_discovery_report.md',
        'emergency_stop_false_positive_report.md',
        'dynamic_click_accuracy_design_report.md',
        'keyboard_focus_diagnostics_report.md',
        'mouse_offset_diagnostics_report.md',
        'pycharm_dynamic_app_report.md',
        'wechat_dynamic_app_report.md',
        'qq_mail_dynamic_web_report.md',
        'baseline_regression_once_report.md',
        'first_attempt_quality_report.md',
        'adaptive_retry_report.md',
        'dynamic_ui_evidence_integrity_report.md',
        'runner_raw_evidence_report.md',
        'verifier_report.md',
        'regression_report.md',
        'evidence_index.md',
        'known_limits.md',
        'git_status_initial.txt',
        'git_status_final.txt',
        'modified_files.txt'
    )
}
foreach ($required in $requiredReports) {
    $path = Join-Path $ArtifactRoot $required
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Finding 'MISSING_REQUIRED_REPORT' "Missing required report $required." (RelPath $path) $true
    }
}

$runnerSummary = Read-JsonFile (Join-Path $RawRoot 'runner_summary.json') 'runner_summary.json' $true
if ($runnerSummary) {
    if ([int]$runnerSummary.step_timeout_sec -ne 60) {
        Add-Finding 'RUNNER_STEP_TIMEOUT_INVALID' "Runner step_timeout_sec must be 60, got $($runnerSummary.step_timeout_sec)." 'raw\runner_summary.json' $true
    }
    if ([int]$runnerSummary.global_timeout_sec -ne 2700) {
        Add-Finding 'RUNNER_GLOBAL_TIMEOUT_INVALID' "Runner global_timeout_sec must be 2700, got $($runnerSummary.global_timeout_sec)." 'raw\runner_summary.json' $true
    }
    if ([int]$runnerSummary.heartbeat_interval_sec -ne 15) {
        Add-Finding 'RUNNER_HEARTBEAT_INVALID' "Runner heartbeat_interval_sec must be 15, got $($runnerSummary.heartbeat_interval_sec)." 'raw\runner_summary.json' $true
    }
    if ($runnerSummary.emergency_stop_triggered -ne $false) {
        Add-Finding 'EMERGENCY_STOP_TRIGGERED' 'Runner summary recorded emergency_stop_triggered=true.' 'raw\runner_summary.json' $true
    }
    if ($StateGuardOnly -and $runnerSummary.state_guard_only -ne $true) {
        Add-Finding 'STATE_GUARD_MODE_MISSING' 'Runner summary did not record state_guard_only=true.' 'raw\runner_summary.json' $true
    }
}
Test-JsonlFile (Join-Path $RawRoot 'heartbeat.jsonl') 'raw heartbeat.jsonl' $true | Out-Null

if (-not $StateGuardOnly) {
    $triageResult = Read-JsonFile (Join-Path $VerifiedRoot 'emergency_stop_triage_result.json') 'verified emergency_stop_triage_result.json' $true
    if ($triageResult) {
        if ($triageResult.false_positive_root_cause_fixed -ne $true) {
            Add-Finding 'EMERGENCY_STOP_FALSE_POSITIVE_NOT_FIXED' 'Emergency stop false-positive triage did not record false_positive_root_cause_fixed=true.' 'verified\emergency_stop_triage_result.json' $true
        }
        if ($triageResult.legacy_stdout_substring_match_removed -ne $true) {
            Add-Finding 'EMERGENCY_STOP_LEGACY_MATCH_PRESENT' 'Emergency stop triage did not confirm legacy stdout substring matching was removed.' 'verified\emergency_stop_triage_result.json' $true
        }
    }
}

$protocol = Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw
foreach ($needle in @('v6_1_4_dynamic_ui_runner.ps1','v6_1_4_dynamic_ui_verifier.ps1','v6_1_4_dynamic_ui_acceptance_gate.ps1')) {
    if ($protocol -notmatch [regex]::Escape($needle)) {
        Add-Finding 'COMMAND_PROTOCOL_MISSING' "COMMAND_PROTOCOL.md does not mention $needle." 'COMMAND_PROTOCOL.md' $true
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Root $needle))) {
        Add-Finding 'COMMAND_PROTOCOL_NONEXISTENT_COMMAND' "Documented script does not exist: $needle." $needle $true
    }
}
if ($protocol -notmatch [regex]::Escape('https://mail.qq.com')) {
    Add-Finding 'COMMAND_PROTOCOL_QQ_MAIL_ENTRY_MISSING' 'COMMAND_PROTOCOL.md must document https://mail.qq.com as the QQ Mail entry.' 'COMMAND_PROTOCOL.md' $true
}

$evidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
if (Test-Path -LiteralPath $evidenceIndex) {
    foreach ($line in Get-Content -LiteralPath $evidenceIndex) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $path = Join-Path $ArtifactRoot $line
        if (-not (Test-Path -LiteralPath $path)) {
            Add-Finding 'EVIDENCE_POINTER_MISSING' "Evidence index pointer does not exist: $line." (RelPath $path) $true
        }
        if ($line -match 'invalidated') {
            Add-Finding 'INVALIDATED_EVIDENCE_REFERENCED' "Evidence index references invalidated evidence: $line." $line $true
        }
    }
}

$agentsText = Get-Content -LiteralPath (Join-Path $Root 'AGENTS.md') -Raw
$allCasesPass = @($results | Where-Object { $_.verification_passed -ne $true }).Count -eq 0 -and $results.Count -eq $expected.Count
if ($StateGuardOnly) {
    if ((Get-StateField $agentsText 'current_trusted_version') -ne '6.1.3' -or
        (Get-StateField $agentsText 'last_completed_version') -ne '6.1.4' -or
        (Get-StateField $agentsText 'last_completed_status') -ne 'blocked' -or
        (Get-StateField $agentsText 'ready_for_next_version') -ne 'false' -or
        (Get-StateField $agentsText 'next_planned_version') -ne '6.1.4-rerun') {
        Add-Finding 'AGENTS_STATE_INCONSISTENT' 'AGENTS.md must remain blocked v6.1.4 state during state-guard-only validation.' 'AGENTS.md' $true
    }
    if ($allCasesPass) {
        Add-Finding 'DYNAMIC_APP_WEB_FULL_RERUN_PENDING' 'State guard path passed, but PyCharm/WeChat/QQ Mail full dynamic rerun is still pending; v6.1.4 remains BLOCKED.' 'artifacts\dev6.1.4_dynamic_app_web_click_accuracy_state_guard' $true
    }
} elseif ($allCasesPass) {
    if ((Get-StateField $agentsText 'current_trusted_version') -ne '6.1.4' -or
        (Get-StateField $agentsText 'last_completed_status') -ne 'accepted' -or
        (Get-StateField $agentsText 'ready_for_next_version') -ne 'true' -or
        (Get-StateField $agentsText 'next_planned_version') -ne '6.2.0') {
        Add-Finding 'AGENTS_STATE_INCONSISTENT' 'AGENTS.md is not in accepted v6.1.4 state while case evidence is passing.' 'AGENTS.md' $true
    }
} else {
    if ((Get-StateField $agentsText 'current_trusted_version') -ne '6.1.3' -or
        (Get-StateField $agentsText 'last_completed_version') -ne '6.1.4' -or
        (Get-StateField $agentsText 'last_completed_status') -ne 'blocked' -or
        (Get-StateField $agentsText 'ready_for_next_version') -ne 'false' -or
        (Get-StateField $agentsText 'next_planned_version') -ne '6.1.4-rerun') {
        Add-Finding 'AGENTS_STATE_INCONSISTENT' 'AGENTS.md is not in blocked v6.1.4 state while required dynamic UI evidence is not accepted.' 'AGENTS.md' $true
    }
}

$blocking = @($Findings | Where-Object { $_.blocking }).Count
$status = if ($blocking -eq 0 -and $allCasesPass) { 'PASS' } else { 'FAIL' }

$result = [pscustomobject]@{
    schema_version = 'v6.1.4.dynamic_ui_acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    blocking_finding_count = $blocking
    state_guard_only = [bool]$StateGuardOnly
    state_guard_passed = ($StateGuardOnly -and $allCasesPass)
    dynamic_app_web_full_rerun_pending = [bool]$StateGuardOnly
    all_required_dynamic_ui_cases_passed = $allCasesPass
    findings = @($Findings.ToArray())
    cases = @($caseRows.ToArray())
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

@(
    $(if ($StateGuardOnly) { '# v6.1.4 State Guard Acceptance Gate Report' } else { '# v6.1.4 Dynamic UI Acceptance Gate Report' }),
    '',
    "- Result: $status",
    "- Blocking findings: $blocking",
    "- State guard only: $([bool]$StateGuardOnly)",
    "- State guard passed: $($StateGuardOnly -and $allCasesPass)",
    "- All required dynamic UI cases passed: $allCasesPass",
    '',
    '## Cases'
) + (@($caseRows | ForEach-Object { "- $($_.case_id): expected=$($_.expected); actual=$($_.actual); verification_passed=$($_.verification_passed)" })) + @(
    '',
    '## Findings'
) + ($(if ($Findings.Count -eq 0) { @('- none') } else { @($Findings | ForEach-Object { "- [$($_.code)] $($_.message) $($_.path)" }) })) |
    Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($status -ne 'PASS') {
    @(
        '# v6.1.4 Blocking Report',
        '',
        '- Final status: BLOCKED',
        '- current_trusted_version remains: 6.1.3',
        '- next_planned_version: 6.1.4-rerun',
        '- v6.2 entry allowed: false',
        '',
        '## Blocking Findings'
    ) + ($(if ($Findings.Count -eq 0) { @('- none') } else { @($Findings | Where-Object { $_.blocking } | ForEach-Object { "- [$($_.code)] $($_.message) $($_.path)" }) })) |
        Set-Content -LiteralPath (Join-Path $ArtifactRoot 'blocking_report.md') -Encoding UTF8
}

Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

if ($status -eq 'PASS') {
    Write-Host 'DYNAMIC_UI_ACCEPTANCE_GATE_RESULT: PASS'
    exit 0
}

Write-Host 'DYNAMIC_UI_ACCEPTANCE_GATE_RESULT: FAIL'
exit 1
