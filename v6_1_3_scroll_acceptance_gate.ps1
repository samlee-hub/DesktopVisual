param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$VerifiedCasesRoot = Join-Path $VerifiedRoot 'cases'
$ReportPath = Join-Path $ArtifactRoot 'scroll_acceptance_gate_report.md'
$ResultPath = Join-Path $VerifiedRoot 'scroll_acceptance_gate_result.json'

New-Item -ItemType Directory -Force -Path $ArtifactRoot, $RawRoot, $VerifiedRoot | Out-Null

$Findings = New-Object System.Collections.Generic.List[object]

function RelPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($rootFull.Length).TrimStart('\')
    }
    return $Path
}

function Test-ExistingPath([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return $true }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        if ($full.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
            return [System.IO.File]::Exists($full) -or [System.IO.Directory]::Exists($full)
        }
        $longPath = '\\?\' + $full
        return [System.IO.File]::Exists($longPath) -or [System.IO.Directory]::Exists($longPath)
    } catch {
        return $false
    }
}

function Add-Finding([string]$Code, [string]$Message, [string]$Path = '', [bool]$Blocking = $true) {
    $Findings.Add([pscustomobject]@{
        code = $Code
        message = $Message
        path = $Path
        blocking = $Blocking
    }) | Out-Null
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

function Analyze-RawLog([string]$Path, [string]$Name, [string]$RequiredPattern) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding 'MISSING_RAW_LOG' "Missing raw log for $Name." (RelPath $Path) $true
        return $false
    }
    $text = Get-Content -LiteralPath $Path -Raw
    if ($text -match 'SKIP_ENVIRONMENT|NOT_RUN|SKIP\s*$') {
        Add-Finding 'REQUIRED_TEST_SKIPPED' "$Name contains skip/not-run marker." (RelPath $Path) $true
        return $false
    }
    if ($RequiredPattern -and $text -notmatch $RequiredPattern) {
        Add-Finding 'RAW_LOG_PATTERN_MISSING' "$Name did not contain required PASS pattern: $RequiredPattern" (RelPath $Path) $true
        return $false
    }
    return $true
}

function Get-StateField([string]$Text, [string]$Field) {
    $m = [regex]::Match($Text, "(?m)^$([regex]::Escape($Field)):\s*(.+?)\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Test-StrictCommon($Result, [string]$CaseId) {
    $requiredTrue = @('sendinput_used','mouseeventf_wheel_used','wheel_attempted_first','raw_command_evidence_verified')
    foreach ($field in $requiredTrue) {
        if ($Result.$field -ne $true) { Add-Finding 'STRICT_FIELD_FAILED' "$CaseId requires $field=true." $CaseId $true }
    }
    if ([int]$Result.wheel_scroll_count -le 0) { Add-Finding 'STRICT_FIELD_FAILED' "$CaseId requires wheel_scroll_count > 0." $CaseId $true }
    if ([int]$Result.wheel_event_count -le 0) { Add-Finding 'STRICT_FIELD_FAILED' "$CaseId requires wheel_event_count > 0." $CaseId $true }
    foreach ($field in @('synthetic_evidence_detected','placeholder_screenshot_detected','hardcoded_rect_detected','hardcoded_hwnd_detected','precomputed_coordinate_sequence_used')) {
        if ($Result.$field -ne $false) { Add-Finding 'EVIDENCE_INTEGRITY_FAILED' "$CaseId requires $field=false." $CaseId $true }
    }
    foreach ($field in @('scrollbar_click_count','scrollbar_drag_count','right_rail_click_count','keyboard_scroll_count','js_dom_scroll_count','webdriver_count','cdp_count','playwright_count','selenium_count','uia_scrollpattern_count','backend_action_count','wrong_page_navigation_count','stale_coordinate_reuse_count','vlm_call_count','active_protection_bypass_attempt_count')) {
        if ([int]$Result.$field -ne 0) { Add-Finding 'FORBIDDEN_ACTION_DETECTED' "$CaseId requires $field=0." $CaseId $true }
    }
}

$expected = @{
    'v6_1_3_mouse_wheel_primitive_real_input' = 'STRICT_MOUSE_WHEEL_PRIMITIVE_PASS'
    'v6_1_3_browser_long_page_scroll_and_locate' = 'STRICT_SCROLL_AND_LOCATE_PASS'
    'v6_1_3_mock_friend_list_scroll_and_locate' = 'STRICT_APP_LIST_WHEEL_SCROLL_AND_LOCATE_PASS'
    'v6_1_3_explorer_list_wheel_scroll_and_locate' = 'STRICT_EXPLORER_WHEEL_SCROLL_AND_LOCATE_PASS'
    'v6_1_3_wheel_no_progress_detection' = 'STRICT_WHEEL_NO_PROGRESS_DETECTED_PASS'
    'v6_1_3_v6_1_2_baseline_regression_replay' = 'STRICT_V6_1_2_BASELINE_REPLAY_PASS'
}

$caseRows = New-Object System.Collections.Generic.List[object]
$caseResults = @{}
foreach ($caseId in $expected.Keys) {
    $caseDir = Join-Path $VerifiedCasesRoot $caseId
    $result = Read-JsonFile (Join-Path $caseDir 'task_result.json') "$caseId task_result.json" $true
    if ($result) {
        $caseResults[$caseId] = $result
        if ($result.actual_result -ne $expected[$caseId]) {
            Add-Finding 'CASE_RESULT_FAILED' "$caseId expected $($expected[$caseId]), got $($result.actual_result)." (RelPath (Join-Path $caseDir 'task_result.json')) $true
        }
        if ($result.verification_passed -ne $true) {
            Add-Finding 'CASE_VERIFICATION_FAILED' "$caseId verification_passed was not true." (RelPath (Join-Path $caseDir 'task_result.json')) $true
        }
        Test-StrictCommon $result $caseId
        if ($caseId -like '*scroll_and_locate' -or $caseId -like '*friend*' -or $caseId -like '*explorer*') {
            if ($result.target_initially_visible -ne $false) { Add-Finding 'TARGET_VISIBILITY_FAILED' "$caseId target_initially_visible must be false." $caseId $true }
            if ($result.target_found -ne $true) { Add-Finding 'TARGET_VISIBILITY_FAILED' "$caseId target_found must be true." $caseId $true }
            if ([int]$result.found_after_scroll_count -le 0) { Add-Finding 'TARGET_VISIBILITY_FAILED' "$caseId found_after_scroll_count must be > 0." $caseId $true }
            if ([int]$result.wheel_content_changed_count -le 0) { Add-Finding 'CONTENT_CHANGE_FAILED' "$caseId wheel_content_changed_count must be > 0." $caseId $true }
            if ([int]$result.target_rect_missing_count -ne 0) { Add-Finding 'TARGET_RECT_MISSING' "$caseId target rect missing." $caseId $true }
        }
        $caseRows.Add([pscustomobject]@{ case_id = $caseId; expected = $expected[$caseId]; actual = $result.actual_result; verification_passed = $result.verification_passed }) | Out-Null
    }
    foreach ($jsonl in @('task_events.jsonl','action_trace.jsonl','locator_trace.jsonl','scroll_trace.jsonl','adaptive_loop_trace.jsonl','human_action_results.jsonl','raw_command_log.jsonl')) {
        Test-JsonlFile (Join-Path $caseDir $jsonl) "$caseId $jsonl" $true | Out-Null
    }
}

foreach ($required in @(
    'agent_context_digest.md',
    'file_discovery_report.md',
    'runner_raw_evidence_report.md',
    'verifier_report.md',
    'real_ui_wheel_evidence_integrity_report.md',
    'mouse_wheel_primitive_report.md',
    'browser_long_page_scroll_report.md',
    'mock_friend_list_scroll_report.md',
    'explorer_list_scroll_report.md',
    'wheel_no_progress_report.md',
    'v6_1_2_baseline_replay_report.md',
    'adaptive_retry_report.md',
    'regression_report.md',
    'test_summary.md',
    'dev_summary.md',
    'known_limits.md',
    'modified_files.txt',
    'git_status_initial.txt',
    'git_status_final.txt',
    'evidence_index.md'
)) {
    $path = Join-Path $ArtifactRoot $required
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Finding 'MISSING_REQUIRED_REPORT' "Missing required report $required." (RelPath $path) $true
    }
}

$rawChecks = @(
    @{ Path = 'build.log'; Name = 'build'; Pattern = 'Built .*winagent\.exe|Build succeeded|SCRIPT_STATUS:\s*PASS' },
    @{ Path = 'version.log'; Name = 'version'; Pattern = '"version"\s*:\s*"6\.1\.3"|^6\.1\.3$' },
    @{ Path = 'scroll_help.log'; Name = 'scroll help'; Pattern = '"command"\s*:\s*"scroll"' },
    @{ Path = 'adaptive_scroll_help.log'; Name = 'adaptive-scroll help'; Pattern = '"command"\s*:\s*"adaptive-scroll"' },
    @{ Path = 'scroll_and_locate_help.log'; Name = 'scroll-and-locate help'; Pattern = '"command"\s*:\s*"scroll-and-locate"' },
    @{ Path = 'adaptive_scroll_targeted.log'; Name = 'adaptive-scroll targeted test'; Pattern = '"command"\s*:\s*"adaptive-scroll"' },
    @{ Path = 'scroll_and_locate_targeted.log'; Name = 'scroll-and-locate targeted test'; Pattern = '"command"\s*:\s*"scroll-and-locate"' },
    @{ Path = 'v6_1_0_task_intent_planner_selftest.log'; Name = 'v6.1 Planner selftest'; Pattern = 'PASS' },
    @{ Path = 'v6_1_1_evidence_acceptance_gate.log'; Name = 'v6.1.1 acceptance gate regression'; Pattern = 'ACCEPTANCE_GATE_RESULT:\s*PASS|PASS' },
    @{ Path = 'v6_1_2_pre_v6_2_acceptance_gate.log'; Name = 'v6.1.2 baseline acceptance gate regression'; Pattern = 'ACCEPTANCE_GATE_RESULT:\s*PASS|PASS' },
    @{ Path = 'v6_0_0_agent_boundary_selftest.log'; Name = 'v6.0 boundary regression'; Pattern = 'PASS' },
    @{ Path = 'v5_9_permission_reset_selftest.log'; Name = 'permission selftest'; Pattern = 'PASS' },
    @{ Path = 'v5_9_0_e_humanmode_motion_pacing_test_run1.log'; Name = 'HumanMode pacing run1'; Pattern = 'PASS' },
    @{ Path = 'v5_9_0_e_humanmode_motion_pacing_test_run2.log'; Name = 'HumanMode pacing run2'; Pattern = 'PASS' },
    @{ Path = 'v5_10_0_adaptive_humanmode_loop_test.log'; Name = 'adaptive loop regression'; Pattern = 'PASS' },
    @{ Path = 'v6_1_3_wheel_scroll_runner.log'; Name = 'Wheel Scroll Runner'; Pattern = 'raw runner complete' },
    @{ Path = 'v6_1_3_wheel_scroll_verifier.log'; Name = 'Wheel Scroll Verifier'; Pattern = 'verifier PASS' },
    @{ Path = 'json_jsonl_parse.log'; Name = 'JSON/JSONL parse'; Pattern = 'SCRIPT_STATUS:\s*PASS|PASS' },
    @{ Path = 'markdown_fence_validation.log'; Name = 'Markdown fence validation'; Pattern = 'SCRIPT_STATUS:\s*PASS|PASS' },
    @{ Path = 'encoding_mojibake_scan.log'; Name = 'encoding mojibake scan'; Pattern = 'SCRIPT_STATUS:\s*PASS|PASS' },
    @{ Path = 'command_protocol_consistency.log'; Name = 'COMMAND_PROTOCOL consistency'; Pattern = 'SCRIPT_STATUS:\s*PASS|PASS' }
)
foreach ($check in $rawChecks) {
    Analyze-RawLog (Join-Path $RawRoot $check.Path) $check.Name $check.Pattern | Out-Null
}

$protocol = Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw
foreach ($needle in @('adaptive-scroll','scroll-and-locate','v6_1_3_wheel_scroll_runner.ps1','v6_1_3_wheel_scroll_verifier.ps1','v6_1_3_scroll_acceptance_gate.ps1')) {
    if ($protocol -notmatch [regex]::Escape($needle)) {
        Add-Finding 'COMMAND_PROTOCOL_MISSING' "COMMAND_PROTOCOL.md does not mention $needle." 'COMMAND_PROTOCOL.md' $true
    }
}
foreach ($script in @('v6_1_3_wheel_scroll_runner.ps1','v6_1_3_wheel_scroll_verifier.ps1','v6_1_3_scroll_acceptance_gate.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $script))) {
        Add-Finding 'COMMAND_PROTOCOL_NONEXISTENT_COMMAND' "Documented script does not exist: $script." $script $true
    }
}

$evidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
if (Test-Path -LiteralPath $evidenceIndex) {
    foreach ($line in Get-Content -LiteralPath $evidenceIndex) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $path = Join-Path $ArtifactRoot $line
        if (-not (Test-ExistingPath $path)) {
            Add-Finding 'EVIDENCE_POINTER_MISSING' "Evidence index pointer does not exist: $line." (RelPath $path) $true
        }
        if ($line -match 'invalidated') {
            Add-Finding 'INVALIDATED_EVIDENCE_REFERENCED' "Evidence index references invalidated evidence: $line." $line $true
        }
    }
}

$agentsText = Get-Content -LiteralPath (Join-Path $Root 'AGENTS.md') -Raw
$currentTrusted = Get-StateField $agentsText 'current_trusted_version'
$lastCompleted = Get-StateField $agentsText 'last_completed_version'
$lastStatus = Get-StateField $agentsText 'last_completed_status'
$readyNext = Get-StateField $agentsText 'ready_for_next_version'
$nextPlanned = Get-StateField $agentsText 'next_planned_version'
$currentStage = Get-StateField $agentsText 'current_stage'
$acceptedV613State = (
    $currentTrusted -eq '6.1.3' -and
    $lastStatus -eq 'accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.2.0'
)
$v614RegressionState = (
    $currentTrusted -eq '6.1.3' -and
    (
        ($lastCompleted -eq '6.1.3' -and $lastStatus -eq 'accepted' -and $readyNext -eq 'true' -and $nextPlanned -eq '6.1.4') -or
        ($lastCompleted -eq '6.1.4' -and $lastStatus -eq 'blocked' -and $readyNext -eq 'false' -and $nextPlanned -eq '6.1.4-rerun' -and $currentStage -match 'v6\.1\.4_')
    )
)
$acceptedV614RuntimeState = (
    $currentTrusted -eq '6.1.4' -and
    $lastCompleted -eq '6.1.4' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.1.5' -and
    $currentStage -match 'v6\.1\.4_runtime_guard_browser_stabilization_pass'
)
$acceptedLaterV61State = (
    $currentTrusted -match '^6\.1\.(5|5a|6)$' -and
    $lastCompleted -match '^6\.1\.(5|5a|6)$' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    (
        ($currentTrusted -eq '6.1.6' -and $nextPlanned -eq '6.2.0') -or
        ($currentTrusted -ne '6.1.6' -and $nextPlanned -eq '6.1.6')
    )
)
$acceptedV620State = (
    $currentTrusted -eq '6.2.0' -and
    $lastCompleted -eq '6.2.0' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.3.0'
)
$acceptedV630State = (
    $currentTrusted -eq '6.3.0' -and
    $lastCompleted -eq '6.3.0' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.4.0'
)
$acceptedV640State = (
    $currentTrusted -eq '6.4.0' -and
    $lastCompleted -eq '6.4.0' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.5.0'
)
$acceptedV650State = (
    $currentTrusted -eq '6.5.0' -and
    $lastCompleted -eq '6.5.0' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.6.0'
)
$acceptedV660State = (
    $currentTrusted -eq '6.6.0' -and
    $lastCompleted -eq '6.6.0' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.7.0'
)
$blockedV670RerunState = (
    $currentTrusted -eq '6.6.0' -and
    $lastCompleted -eq '6.6.0' -and
    $lastStatus -eq 'blocked' -and
    $readyNext -eq 'false' -and
    $nextPlanned -eq '6.7.0-rerun'
)
$acceptedV670State = (
    $currentTrusted -eq '6.7.0' -and
    $lastCompleted -eq '6.7.0' -and
    $lastStatus -match 'pass|accepted' -and
    $readyNext -eq 'true' -and
    $nextPlanned -eq '6.8.0'
)
$hasBlocking = @($Findings | Where-Object { $_.blocking }).Count -gt 0
if (-not $hasBlocking) {
    if (-not ($acceptedV613State -or $v614RegressionState -or $acceptedV614RuntimeState -or $acceptedLaterV61State -or $acceptedV620State -or $acceptedV630State -or $acceptedV640State -or $acceptedV650State -or $acceptedV660State -or $blockedV670RerunState -or $acceptedV670State)) {
        Add-Finding 'VERSION_STATE_MISMATCH' 'AGENTS.md is not in an accepted v6.1.3/v6.1.4 state or later v6.1 trusted state while gate evidence is otherwise passing.' 'AGENTS.md' $true
    }
} else {
    $blockedV613State = (
        $currentTrusted -eq '6.1.2' -and
        $lastStatus -eq 'blocked' -and
        $readyNext -eq 'false' -and
        $nextPlanned -eq '6.1.4'
    )
    if (-not ($blockedV613State -or $v614RegressionState)) {
        Add-Finding 'VERSION_STATE_MISMATCH' 'AGENTS.md is not in blocked v6.1.3 state or v6.1.4 regression/blocked state while gate has blocking findings.' 'AGENTS.md' $true
    }
}

$finalBlocking = @($Findings | Where-Object { $_.blocking }).Count
$status = if ($finalBlocking -eq 0) { 'PASS' } else { 'FAIL' }

$scrollGateFailureType = ''
if ($status -ne 'PASS') {
    $codes = @($Findings | ForEach-Object { [string]$_.code })
    $nonBaselineFailures = @($caseRows | Where-Object {
        $_.case_id -ne 'v6_1_3_v6_1_2_baseline_regression_replay' -and $_.verification_passed -ne $true
    })
    $baseline = if ($caseResults.ContainsKey('v6_1_3_v6_1_2_baseline_regression_replay')) { $caseResults['v6_1_3_v6_1_2_baseline_regression_replay'] } else { $null }
    $baselineActuals = @()
    if ($baseline -and $baseline.baseline_replay_results) {
        $baselineActuals = @($baseline.baseline_replay_results | ForEach-Object { [string]$_.actual })
    }
    if ($codes -contains 'EVIDENCE_POINTER_MISSING' -or $codes -contains 'MISSING_REQUIRED_REPORT' -or $codes -contains 'MISSING_EVIDENCE') {
        $scrollGateFailureType = 'EVIDENCE_PATH_MISMATCH'
    } elseif ($codes -contains 'COMMAND_PROTOCOL_MISSING' -or $codes -contains 'COMMAND_PROTOCOL_NONEXISTENT_COMMAND') {
        $scrollGateFailureType = 'COMMAND_PROTOCOL_MISMATCH'
    } elseif ($baselineActuals -contains 'STOP_WRONG_CONTEXT') {
        $scrollGateFailureType = 'BASELINE_REPLAY_WRONG_CONTEXT'
    } elseif (($baselineActuals | Where-Object { $_ -eq 'FAIL_BROWSER_AUTOMATION_DETECTED' }).Count -gt 0 -and $nonBaselineFailures.Count -eq 0) {
        $scrollGateFailureType = 'WRONG_PAGE_CONTINUED_ACTION'
    } elseif ($baseline -and $baseline.actual_result -ne 'STRICT_V6_1_2_BASELINE_REPLAY_PASS' -and $nonBaselineFailures.Count -eq 0) {
        $scrollGateFailureType = 'ACTION_PRECONDITION_MISSING'
    } elseif ($nonBaselineFailures.Count -gt 0) {
        $scrollGateFailureType = 'TRUE_SCROLL_REGRESSION'
    } else {
        $scrollGateFailureType = 'INCONCLUSIVE'
    }
}

$result = [pscustomobject]@{
    schema_version = 'v6.1.3.scroll_acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    blocking_finding_count = $finalBlocking
    scroll_gate_failure_type = $scrollGateFailureType
    findings = @($Findings.ToArray())
    cases = @($caseRows.ToArray())
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

@(
    '# v6.1.3 Scroll Acceptance Gate Report',
    '',
    "- Result: $status",
    "- Blocking findings: $finalBlocking",
    "- scroll_gate_failure_type: $scrollGateFailureType",
    '',
    '## Cases'
) + (@($caseRows | ForEach-Object { "- $($_.case_id): expected=$($_.expected); actual=$($_.actual); verification_passed=$($_.verification_passed)" })) + @(
    '',
    '## Findings'
) + ($(if ($Findings.Count -eq 0) { @('- none') } else { @($Findings | ForEach-Object { "- [$($_.code)] $($_.message) $($_.path)" }) })) |
    Set-Content -LiteralPath $ReportPath -Encoding UTF8

Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

if ($status -eq 'PASS') {
    Write-Host 'SCROLL_ACCEPTANCE_GATE_RESULT: PASS'
    exit 0
}

Write-Host 'SCROLL_ACCEPTANCE_GATE_RESULT: FAIL'
exit 1
