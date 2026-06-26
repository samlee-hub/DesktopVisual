param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate'
$RawDir = Join-Path $ArtifactRoot 'raw'
$VerifiedDir = Join-Path $ArtifactRoot 'verified'
$VerifiedCasesRoot = Join-Path $VerifiedDir 'cases'
$ResultPath = Join-Path $VerifiedDir 'pre_v6_2_acceptance_gate_result.json'
$ReportPath = Join-Path $ArtifactRoot 'pre_v6_2_acceptance_gate_report.md'
$EvidenceIndexPath = Join-Path $ArtifactRoot 'evidence_index.md'

New-Item -ItemType Directory -Force -Path $ArtifactRoot, $RawDir, $VerifiedDir | Out-Null

function RelPath([string]$Path) {
    if ($Path -and $Path.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($Root.Length).TrimStart('\')
    }
    return $Path
}

function Add-Finding([System.Collections.Generic.List[object]]$Findings, [string]$Code, [string]$Message, [string]$Path = '', [bool]$Blocking = $true) {
    $Findings.Add([pscustomobject]@{
        code = $Code
        message = $Message
        path = $Path
        blocking = $Blocking
    }) | Out-Null
}

function Read-JsonFile([string]$Path, [string]$Label, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding $Findings 'MISSING_EVIDENCE' "Missing $Label." (RelPath $Path) $Required
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        Add-Finding $Findings 'INVALID_JSON' "Invalid JSON in $Label`: $($_.Exception.Message)" (RelPath $Path) $Required
        return $null
    }
}

function Test-JsonlFile([string]$Path, [string]$Label, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding $Findings 'MISSING_EVIDENCE' "Missing $Label." (RelPath $Path) $Required
        return [pscustomobject]@{ label=$Label; path=(RelPath $Path); status='MISSING'; line_count=0 }
    }
    $lineNo = 0
    $errors = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $null = $line | ConvertFrom-Json }
        catch {
            $errors++
            Add-Finding $Findings 'INVALID_JSONL' "Invalid JSONL in $Label at line $lineNo`: $($_.Exception.Message)" (RelPath $Path) $Required
        }
    }
    return [pscustomobject]@{ label=$Label; path=(RelPath $Path); status=if($errors -eq 0){'PASS'}else{'FAIL'}; line_count=$lineNo; error_count=$errors }
}

function Analyze-RawLog([string]$Path, [string]$Name, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true, [string]$RequiredPattern = '') {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding $Findings 'MISSING_EVIDENCE' "Missing raw log for $Name." (RelPath $Path) $Required
        return [pscustomobject]@{ name=$Name; path=(RelPath $Path); exists=$false; exit_code=$null; status='MISSING'; has_required_header=$false; has_required_pattern=$false }
    }
    $text = Get-Content -LiteralPath $Path -Raw
    $exit = $null
    if ($text -match '(?m)^EXIT_CODE:\s*(-?\d+)') { $exit = [int]$Matches[1] }
    $hasHeader = ($text -match '(?m)^COMMAND:\s+') -and ($text -match '(?m)^TIMESTAMP_START:\s+') -and ($text -match '(?m)^TIMESTAMP_END:\s+') -and ($text -match '(?m)^EXIT_CODE:\s+')
    $hasPattern = [string]::IsNullOrWhiteSpace($RequiredPattern) -or ($text -match $RequiredPattern)
    $hasSkip = $text -match '\bSKIP\b|\bSKIPPED\b|SKIP_ENVIRONMENT|NOT_RUN'
    $hasFail = $text -match '(?m)^SCRIPT_STATUS:\s*FAIL\b|FAIL_CURSOR_NOT_AT_TARGET|FAIL_EVIDENCE|FAIL_REGRESSION|failed'
    if ($Required -and -not $hasHeader) {
        Add-Finding $Findings 'RAW_LOG_INCOMPLETE' "Raw log lacks command/timestamp/exit-code header for $Name." (RelPath $Path) $true
    }
    if ($Required -and $exit -ne 0) {
        Add-Finding $Findings 'REGRESSION_FAILED' "Required raw log $Name has non-zero exit code $exit." (RelPath $Path) $true
    }
    if ($Required -and $hasSkip) {
        Add-Finding $Findings 'REGRESSION_SKIPPED' "Required raw log $Name contains SKIP/NOT_RUN marker." (RelPath $Path) $true
    }
    if ($Required -and -not $hasPattern) {
        Add-Finding $Findings 'RAW_LOG_PATTERN_MISSING' "Raw log $Name lacks required success pattern." (RelPath $Path) $true
    }
    return [pscustomobject]@{
        name = $Name
        path = (RelPath $Path)
        exists = $true
        exit_code = $exit
        status = if($exit -eq 0 -and $hasHeader -and $hasPattern -and -not $hasSkip -and -not ($Name -match 'HumanMode pacing' -and $hasFail)){'PASS'}elseif($hasSkip){'SKIP_OR_NOT_RUN'}else{'FAIL'}
        has_required_header = $hasHeader
        has_required_pattern = $hasPattern
        has_skip = $hasSkip
        has_fail = $hasFail
    }
}

function Get-StateField([string]$Text, [string]$Field) {
    if ($Text -match ('(?m)^' + [regex]::Escape($Field) + ':\s*(.+)$')) { return $Matches[1].Trim() }
    return ''
}

function Test-TaskResultRequiredFields($Result, [string]$CaseId, [System.Collections.Generic.List[object]]$Findings) {
    $required = @(
        'actual_result','adaptive_loop_used','precomputed_coordinate_sequence_used','raw_command_evidence_verified',
        'synthetic_evidence_detected','placeholder_screenshot_detected','hardcoded_rect_detected','hardcoded_hwnd_detected',
        'backend_action_count','direct_launch_count','shell_execute_count','start_process_count','invoke_item_count',
        'direct_file_open_count','direct_navigation_count','js_dom_action_count','webdriver_count','cdp_count','playwright_count',
        'selenium_count','uia_invoke_action_count','uia_value_action_count','wrong_candidate_open_count',
        'cursor_outside_target_rect_count','target_rect_missing_count','field_locator_failure_count',
        'send_button_locator_failure_count','wrong_field_input_count','reobserve_count','retry_count',
        'verification_passed','vlm_call_count','active_protection_bypass_attempt_count','stale_coordinate_reuse_count',
        'coordinate_mapping_validated','send_status_verified','fields_cleared_verified'
    )
    foreach ($field in $required) {
        if (-not $Result.PSObject.Properties[$field]) {
            Add-Finding $Findings 'TASK_RESULT_FIELD_MISSING' "Missing task_result field $field for $CaseId." $CaseId $true
        }
    }
}

function Test-PassHardRequirements($Result, [string]$CaseId, [System.Collections.Generic.List[object]]$Findings) {
    $zeroFields = @(
        'backend_action_count','direct_launch_count','shell_execute_count','start_process_count','invoke_item_count',
        'direct_file_open_count','js_dom_action_count','webdriver_count','cdp_count','playwright_count','selenium_count',
        'uia_invoke_action_count','uia_value_action_count','cursor_outside_target_rect_count','wrong_candidate_open_count',
        'stale_coordinate_reuse_count','vlm_call_count','active_protection_bypass_attempt_count'
    )
    if ($Result.adaptive_loop_used -ne $true) { Add-Finding $Findings 'REAL_UI_CASE_FAILED' "$CaseId did not use adaptive loop." $CaseId $true }
    if ($Result.precomputed_coordinate_sequence_used -ne $false) { Add-Finding $Findings 'REAL_UI_CASE_FAILED' "$CaseId used precomputed coordinate sequence." $CaseId $true }
    if ($Result.raw_command_evidence_verified -ne $true) { Add-Finding $Findings 'REAL_UI_CASE_FAILED' "$CaseId raw command evidence was not verified." $CaseId $true }
    foreach ($flag in @('synthetic_evidence_detected','placeholder_screenshot_detected','hardcoded_rect_detected','hardcoded_hwnd_detected')) {
        if ($Result.$flag -ne $false) { Add-Finding $Findings 'REAL_UI_CASE_FAILED' "$CaseId has $flag." $CaseId $true }
    }
    foreach ($field in $zeroFields) {
        if ([int]$Result.$field -ne 0) { Add-Finding $Findings 'REAL_UI_CASE_FAILED' "$CaseId has non-zero $field=$($Result.$field)." $CaseId $true }
    }
}

function Add-ExpectedPointer([System.Collections.Generic.List[object]]$Pointers, [string]$Pointer, [bool]$Required = $true) {
    $resolved = if ([System.IO.Path]::IsPathRooted($Pointer)) { $Pointer } else { Join-Path $ArtifactRoot $Pointer }
    $Pointers.Add([pscustomobject]@{
        pointer = $Pointer
        resolved = (RelPath $resolved)
        exists = (Test-Path -LiteralPath $resolved)
        required = $Required
    }) | Out-Null
}

$findings = New-Object System.Collections.Generic.List[object]

$rawLogs = New-Object System.Collections.Generic.List[object]
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'build.log') 'build' $findings $true 'SCRIPT_STATUS:\s*PASS|Build succeeded|BUILD SUCCESS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'version.log') 'version' $findings $true '"version"\s*:\s*"6\.1\.2"|^6\.1\.2$')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v6_1_0_task_intent_planner_selftest.log') 'v6.1 Planner selftest' $findings $true 'PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v6_1_1_evidence_acceptance_gate.log') 'v6.1.1 acceptance gate regression' $findings $true 'ACCEPTANCE_GATE_RESULT:\s*PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v6_0_0_agent_boundary_selftest.log') 'v6.0 boundary regression' $findings $true 'PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v5_9_permission_reset_selftest.log') 'permission selftest' $findings $true 'PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v5_9_0_e_humanmode_motion_pacing_test_run1.log') 'HumanMode pacing run1' $findings $true 'PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v5_9_0_e_humanmode_motion_pacing_test_run2.log') 'HumanMode pacing run2' $findings $true 'PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v5_10_0_adaptive_humanmode_loop_test.log') 'adaptive loop regression' $findings $true 'PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v6_1_2_real_ui_baseline_runner.log') 'Real UI runner' $findings $true 'raw runner complete')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'v6_1_2_real_ui_baseline_verifier.log') 'Real UI verifier' $findings $true 'verifier PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'json_jsonl_parse.log') 'JSON JSONL parse' $findings $true 'SCRIPT_STATUS:\s*PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'markdown_fence_validation.log') 'Markdown fence validation' $findings $true 'SCRIPT_STATUS:\s*PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'encoding_mojibake_scan.log') 'encoding mojibake scan' $findings $true 'SCRIPT_STATUS:\s*PASS')) | Out-Null
$rawLogs.Add((Analyze-RawLog (Join-Path $RawDir 'command_protocol_consistency.log') 'COMMAND_PROTOCOL consistency' $findings $true 'SCRIPT_STATUS:\s*PASS')) | Out-Null

$caseExpectations = @(
    @{ id='v6_1_2_explorer_real_ui_sanity'; expected='STRICT_MOUSE_TARGET_HUMANMODE_PASS'; required=$true },
    @{ id='v6_1_2_browser_local_mail_mock_real_ui_sanity'; expected='STRICT_ADAPTIVE_HUMANMODE_PASS'; required=$true },
    @{ id='v6_1_2_browser_local_mail_mock_repeat_run'; expected='STRICT_ADAPTIVE_HUMANMODE_PASS'; required=$true },
    @{ id='v6_1_2_localhost_mail_mock_real_ui_sanity'; expected='STRICT_ADAPTIVE_HUMANMODE_PASS'; required=$false }
)

$caseResults = New-Object System.Collections.Generic.List[object]
foreach ($case in $caseExpectations) {
    $path = Join-Path $VerifiedCasesRoot "$($case.id)\task_result.json"
    $result = Read-JsonFile $path "$($case.id) task_result.json" $findings ([bool]$case.required)
    if (-not $result) { continue }
    Test-TaskResultRequiredFields $result $case.id $findings
    $caseResults.Add($result) | Out-Null
    if ([bool]$case.required) {
        if ($result.actual_result -ne $case.expected) {
            Add-Finding $findings 'REAL_UI_CASE_FAILED' "$($case.id) expected $($case.expected), got $($result.actual_result)." (RelPath $path) $true
        } else {
            Test-PassHardRequirements $result $case.id $findings
        }
    } else {
        if ($result.actual_result -eq $case.expected) {
            Test-PassHardRequirements $result $case.id $findings
        } elseif ($result.actual_result -ne 'SKIP_ENVIRONMENT') {
            Add-Finding $findings 'OPTIONAL_REAL_UI_CASE_FAILED' "$($case.id) failed after execution: $($result.actual_result)." (RelPath $path) $true
        }
    }
}

foreach ($case in $caseExpectations) {
    $caseDir = Join-Path $VerifiedCasesRoot $case.id
    foreach ($jsonl in @('task_events.jsonl','action_trace.jsonl','locator_trace.jsonl','adaptive_loop_trace.jsonl','human_action_results.jsonl','raw_command_log.jsonl')) {
        $null = Test-JsonlFile (Join-Path $caseDir $jsonl) "$($case.id) $jsonl" $findings ([bool]$case.required)
    }
}

$verificationSummary = Read-JsonFile (Join-Path $VerifiedDir 'verification_summary.json') 'verification_summary.json' $findings $true
if ($verificationSummary -and $verificationSummary.all_pass -ne $true) {
    Add-Finding $findings 'REAL_UI_VERIFIER_FAILED' 'Verifier summary all_pass is not true.' (RelPath (Join-Path $VerifiedDir 'verification_summary.json')) $true
}

$agentsPath = Join-Path $Root 'AGENTS.md'
$agents = if (Test-Path -LiteralPath $agentsPath) { Get-Content -LiteralPath $agentsPath -Raw } else { '' }
$agentsState = [ordered]@{
    version_file = if (Test-Path -LiteralPath (Join-Path $Root 'VERSION')) { (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim() } else { '' }
    current_trusted_version = Get-StateField $agents 'current_trusted_version'
    last_completed_version = Get-StateField $agents 'last_completed_version'
    last_completed_status = Get-StateField $agents 'last_completed_status'
    ready_for_next_version = Get-StateField $agents 'ready_for_next_version'
    next_planned_version = Get-StateField $agents 'next_planned_version'
    current_stage = Get-StateField $agents 'current_stage'
    blocking_report = Get-StateField $agents 'blocking_report'
}
$regressionMode = $agentsState.version_file -ne '6.1.2'

$blockingBeforeState = @($findings | Where-Object { $_.blocking }).Count -gt 0
if (-not $regressionMode) {
    if (-not $blockingBeforeState) {
        if ($agentsState.version_file -ne '6.1.2') { Add-Finding $findings 'STATE_INCONSISTENT' 'VERSION must be 6.1.2.' 'VERSION' $true }
        if ($agentsState.current_trusted_version -ne '6.1.2') { Add-Finding $findings 'STATE_INCONSISTENT' 'Accepted v6.1.2 requires current_trusted_version 6.1.2.' 'AGENTS.md' $true }
        if ($agentsState.last_completed_version -ne '6.1.2') { Add-Finding $findings 'STATE_INCONSISTENT' 'Accepted v6.1.2 requires last_completed_version 6.1.2.' 'AGENTS.md' $true }
        if ($agentsState.last_completed_status -ne 'accepted') { Add-Finding $findings 'STATE_INCONSISTENT' 'Accepted v6.1.2 requires last_completed_status accepted.' 'AGENTS.md' $true }
        if ($agentsState.ready_for_next_version -ne 'true') { Add-Finding $findings 'STATE_INCONSISTENT' 'Accepted v6.1.2 requires ready_for_next_version true.' 'AGENTS.md' $true }
        if ($agentsState.next_planned_version -ne '6.2.0') { Add-Finding $findings 'STATE_INCONSISTENT' 'Accepted v6.1.2 requires next_planned_version 6.2.0.' 'AGENTS.md' $true }
        if ($agentsState.current_stage -ne 'v6.1.2_real_ui_baseline_sanity_pre_v6_2_gate_accepted') { Add-Finding $findings 'STATE_INCONSISTENT' 'Accepted v6.1.2 current_stage mismatch.' 'AGENTS.md' $true }
    } else {
        if ($agentsState.current_trusted_version -ne '6.1.1') { Add-Finding $findings 'STATE_INCONSISTENT' 'Blocked v6.1.2 must keep current_trusted_version 6.1.1.' 'AGENTS.md' $true }
        if ($agentsState.ready_for_next_version -ne 'false') { Add-Finding $findings 'STATE_INCONSISTENT' 'Blocked v6.1.2 must set ready_for_next_version false.' 'AGENTS.md' $true }
        if ($agentsState.next_planned_version -ne '6.1.3') { Add-Finding $findings 'STATE_INCONSISTENT' 'Blocked v6.1.2 must set next_planned_version 6.1.3.' 'AGENTS.md' $true }
        if ($agentsState.current_stage -ne 'v6.1.2_real_ui_baseline_sanity_pre_v6_2_gate_blocked') { Add-Finding $findings 'STATE_INCONSISTENT' 'Blocked v6.1.2 current_stage mismatch.' 'AGENTS.md' $true }
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\blocking_report.md'))) {
            Add-Finding $findings 'MISSING_BLOCKING_REPORT' 'Blocked v6.1.2 requires blocking_report.md.' 'AGENTS.md' $true
        }
    }
}

$pointers = New-Object System.Collections.Generic.List[object]
if (-not (Test-Path -LiteralPath $ResultPath)) {
    '{"status":"IN_PROGRESS"}' | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}
if (-not (Test-Path -LiteralPath $ReportPath)) {
    '# v6.1.2 Pre-v6.2 Acceptance Gate Report' | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
foreach ($ptr in @(
    'agent_context_digest.md',
    'file_discovery_report.md',
    'dev_summary.md',
    'test_summary.md',
    'modified_files.txt',
    'real_ui_evidence_integrity_report.md',
    'explorer_real_ui_sanity_report.md',
    'browser_mail_mock_real_ui_sanity_report.md',
    'browser_mail_mock_repeatability_report.md',
    'browser_form_locator_report.md',
    'adaptive_retry_report.md',
    'window_relocation_resilience_report.md',
    'runner_raw_evidence_report.md',
    'verifier_report.md',
    'pre_v6_2_acceptance_gate_report.md',
    'regression_report.md',
    'known_limits.md',
    'git_status_initial.txt',
    'git_status_final.txt',
    'verified\verification_summary.json',
    'verified\pre_v6_2_acceptance_gate_result.json'
)) {
    Add-ExpectedPointer $pointers $ptr $true
}
foreach ($ptr in @(
    'localhost_mail_mock_real_ui_sanity_report.md'
)) {
    Add-ExpectedPointer $pointers $ptr $false
}
foreach ($case in $caseExpectations) {
    foreach ($ptr in @('task_result.json','task_events.jsonl','action_trace.jsonl','locator_trace.jsonl','adaptive_loop_trace.jsonl','human_action_results.jsonl','raw_command_log.jsonl','verification_report.md','task_report.md')) {
        Add-ExpectedPointer $pointers ("verified\cases\$($case.id)\$ptr") ([bool]$case.required)
    }
}
foreach ($ptr in @($pointers | Where-Object { $_.required -and -not $_.exists })) {
    Add-Finding $findings 'MISSING_EVIDENCE_POINTER' "Required evidence pointer is missing: $($ptr.pointer)" $ptr.resolved $true
}

$blockingFindings = @($findings | Where-Object { $_.blocking })
$status = 'PASS'
if (@($blockingFindings | Where-Object { $_.code -match 'REAL_UI|VERIFIER' }).Count -gt 0) { $status = 'FAIL_REAL_UI' }
elseif (@($blockingFindings | Where-Object { $_.code -match 'REGRESSION|RAW_LOG' }).Count -gt 0) { $status = 'FAIL_REGRESSION' }
elseif (@($blockingFindings | Where-Object { $_.code -match 'STATE' }).Count -gt 0) { $status = 'FAIL_STATE_INCONSISTENT' }
elseif (@($blockingFindings | Where-Object { $_.code -match 'JSON|JSONL|MISSING' }).Count -gt 0) { $status = 'FAIL_EVIDENCE_MISSING' }
elseif ($blockingFindings.Count -gt 0) { $status = 'FAIL_INCONCLUSIVE' }
if ($status -eq 'PASS' -and $regressionMode) { $status = 'PASS_REGRESSION' }

$accepted = ($status -eq 'PASS' -or $status -eq 'PASS_REGRESSION')
$result = [ordered]@{
    schema_version = 'v6.1.2.pre_v6_2_acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    regression_mode = [bool]$regressionMode
    accepted = [bool]$accepted
    current_trusted_version_allowed = if ($accepted) { '6.1.2' } else { '6.1.1' }
    ready_for_next_version_allowed = [bool]$accepted
    next_planned_version_required = if ($accepted) { '6.2.0' } else { '6.1.3' }
    raw_log_results = [object[]]$rawLogs.ToArray()
    case_results = [object[]]$caseResults.ToArray()
    evidence_pointers = [object[]]$pointers.ToArray()
    agents_state = $agentsState
    findings = [object[]]$findings.ToArray()
}
$result | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# v6.1.2 Pre-v6.2 Acceptance Gate Report') | Out-Null
$report.Add('') | Out-Null
$report.Add(('- Status: `{0}`' -f $status)) | Out-Null
$report.Add(('- Accepted: `{0}`' -f $accepted)) | Out-Null
$report.Add(('- current_trusted_version_allowed: `{0}`' -f $result.current_trusted_version_allowed)) | Out-Null
$report.Add(('- ready_for_next_version_allowed: `{0}`' -f $result.ready_for_next_version_allowed)) | Out-Null
$report.Add(('- next_planned_version_required: `{0}`' -f $result.next_planned_version_required)) | Out-Null
$report.Add('') | Out-Null
$report.Add('## Raw Logs') | Out-Null
foreach ($row in $rawLogs) {
    $report.Add(('- {0}: {1}, exit={2}, path=`{3}`' -f $row.name, $row.status, $row.exit_code, $row.path)) | Out-Null
}
$report.Add('') | Out-Null
$report.Add('## Case Results') | Out-Null
foreach ($row in $caseResults) {
    $report.Add(('- {0}: `{1}` verification_passed=`{2}`' -f $row.case_id, $row.actual_result, $row.verification_passed)) | Out-Null
}
$report.Add('') | Out-Null
$report.Add('## Findings') | Out-Null
if ($findings.Count -eq 0) {
    $report.Add('- None') | Out-Null
} else {
    foreach ($finding in $findings) {
        $report.Add(('- [{0}] blocking={1}: {2} `{3}`' -f $finding.code, $finding.blocking, $finding.message, $finding.path)) | Out-Null
    }
}
$report | Set-Content -LiteralPath $ReportPath -Encoding UTF8

$index = New-Object System.Collections.Generic.List[string]
$index.Add('# v6.1.2 Evidence Index') | Out-Null
$index.Add('') | Out-Null
$index.Add(('Generated: {0}' -f (Get-Date).ToString('o'))) | Out-Null
$index.Add(('- Gate status: `{0}`' -f $status)) | Out-Null
$index.Add('') | Out-Null
$index.Add('## PASS Evidence') | Out-Null
if ($accepted) {
    foreach ($ptr in @($pointers | Where-Object { $_.required -or $_.exists })) {
        $index.Add(('- `{0}`' -f $ptr.pointer)) | Out-Null
    }
} else {
    $index.Add('- none; v6.1.2 is blocked.') | Out-Null
}
$index.Add('') | Out-Null
$index.Add('## Required Evidence Pointers') | Out-Null
foreach ($ptr in $pointers) {
    $index.Add(('- `{0}` exists=`{1}` required=`{2}`' -f $ptr.pointer, $ptr.exists, $ptr.required)) | Out-Null
}
$index.Add('') | Out-Null
$index.Add('## Invalidated Evidence References') | Out-Null
$index.Add('- `artifacts\invalidation_index.md` checked as invalidation metadata only, not PASS evidence.') | Out-Null
$index.Add('- `artifacts\invalidated\` checked as invalidated evidence root only, not PASS evidence.') | Out-Null
$index | Set-Content -LiteralPath $EvidenceIndexPath -Encoding UTF8

Write-Host "PRE_V6_2_ACCEPTANCE_GATE_RESULT: $status"
Write-Host "Result: $ResultPath"
Write-Host "Report: $ReportPath"
if ($accepted) { exit 0 } else { exit 1 }
