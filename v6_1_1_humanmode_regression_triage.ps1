param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.1_humanmode_regression_triage_and_evidence_gate'
$RawDir = Join-Path $ArtifactRoot 'raw'
$VerifiedDir = Join-Path $ArtifactRoot 'verified'
$ResultPath = Join-Path $VerifiedDir 'humanmode_triage_result.json'
$ReportPath = Join-Path $ArtifactRoot 'humanmode_regression_triage_report.md'
$RerunPlanPath = Join-Path $ArtifactRoot 'required_real_ui_rerun_plan.md'

New-Item -ItemType Directory -Force -Path $ArtifactRoot, $RawDir, $VerifiedDir | Out-Null

function Get-Rel([string]$Path) {
    if ($Path.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($Root.Length).TrimStart('\')
    }
    return $Path
}

function Read-TextOrNull([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw
}

function Test-TextHas([string]$Text, [string]$Pattern) {
    return -not [string]::IsNullOrEmpty($Text) -and $Text -match $Pattern
}

function Get-JsonCandidates([string]$Text) {
    $items = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Text)) { return $items.ToArray() }
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) {
            try { $items.Add(($trimmed | ConvertFrom-Json)) | Out-Null } catch {}
            continue
        }
        $match = [regex]::Match($trimmed, '(\{.*\})')
        if ($match.Success) {
            try { $items.Add(($match.Groups[1].Value | ConvertFrom-Json)) | Out-Null } catch {}
        }
    }
    return $items.ToArray()
}

function Get-PropExists($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-HumanActionSummaries([string]$Text) {
    $summaries = New-Object System.Collections.Generic.List[object]
    foreach ($json in (Get-JsonCandidates $Text)) {
        $har = $null
        if ($json.data -and $json.data.human_action_result) { $har = $json.data.human_action_result }
        elseif ($json.human_action_result) { $har = $json.human_action_result }
        if ($null -eq $har) { continue }
        $summaries.Add([pscustomobject]@{
            ok = [bool]$har.ok
            action_type = [string]$har.action_type
            error_code = if ($har.error) { [string]$har.error.code } else { '' }
            target_x_present = (Get-PropExists $har.target 'x')
            target_y_present = (Get-PropExists $har.target 'y')
            target_rect_present = (Get-PropExists $har.target 'target_rect')
            target_rect_verified = if ($har.verification -and (Get-PropExists $har.verification 'target_rect_verified')) { [bool]$har.verification.target_rect_verified } else { $false }
            final_x_present = (Get-PropExists $har.cursor 'final_x')
            final_y_present = (Get-PropExists $har.cursor 'final_y')
            actual_before_click_x_present = (Get-PropExists $har.cursor 'actual_before_click_x')
            actual_before_click_y_present = (Get-PropExists $har.cursor 'actual_before_click_y')
            target_epsilon_present = (Get-PropExists $har.target 'target_epsilon_px')
            distance_to_target_present = (Get-PropExists $har.cursor 'distance_to_target_before_click_px')
            click_sent = if (Get-PropExists $har 'actual_click_sent') { [bool]$har.actual_click_sent } else { $false }
            double_click_sent = if (Get-PropExists $har 'actual_double_click_sent') { [bool]$har.actual_double_click_sent } else { $false }
            foreground_present = (Get-PropExists $har 'foreground')
            motion_present = (Get-PropExists $har 'motion')
            move_mode_present = (Get-PropExists $har.motion 'move_mode')
        }) | Out-Null
    }
    return $summaries.ToArray()
}

function Analyze-Log([string]$Path, [string]$Label) {
    $exists = Test-Path -LiteralPath $Path
    $text = if ($exists) { Get-Content -LiteralPath $Path -Raw } else { '' }
    $human = Get-HumanActionSummaries $text
    return [pscustomobject]@{
        label = $Label
        path = (Get-Rel $Path)
        exists = [bool]$exists
        has_fail_cursor_not_at_target = (Test-TextHas $text 'FAIL_CURSOR_NOT_AT_TARGET')
        has_pass_marker = (Test-TextHas $text '(?m)\bPASS\b|SCRIPT_STATUS:\s*PASS')
        has_fail_marker = (Test-TextHas $text '(?m)\bFAIL\b|SCRIPT_STATUS:\s*FAIL|failed')
        has_skip_marker = (Test-TextHas $text '(?m)\b(SKIP_ENVIRONMENT|SKIPPED|NOT_RUN)\b')
        human_action_result_count = @($human).Count
        human_action_results = @($human)
    }
}

$pacingScript = Join-Path $Root 'v5_9_0_e_humanmode_motion_pacing_test.ps1'
$inputController = Join-Path $Root 'src\winagent\InputController.cpp'
$winAgent = Join-Path $Root 'src\winagent\WinAgent.cpp'
$oldV610MissingLog = Join-Path $Root 'artifacts\dev6.1.0_task_intent_planner\v5_9_0_e_humanmode_motion_pacing_test.log'
$v600Log = Join-Path $Root 'artifacts\dev6.0.0_agent_boundary\v5_9_0_e_humanmode_motion_pacing_test.log'
$currentRun1 = Join-Path $RawDir 'v5_9_0_e_humanmode_motion_pacing_test_run1.log'
$currentRun2 = Join-Path $RawDir 'v5_9_0_e_humanmode_motion_pacing_test_run2.log'

$scriptText = Read-TextOrNull $pacingScript
$inputText = Read-TextOrNull $inputController
$winAgentText = Read-TextOrNull $winAgent
$modifiedText = Read-TextOrNull (Join-Path $Root 'artifacts\dev6.1.0_task_intent_planner\modified_files.txt')

$logs = @(
    (Analyze-Log $oldV610MissingLog 'v6.1.0 referenced HumanMode pacing failure log'),
    (Analyze-Log $v600Log 'v6.0.0 accepted baseline HumanMode pacing log'),
    (Analyze-Log $currentRun1 'v6.1.1 current HumanMode pacing run1 log'),
    (Analyze-Log $currentRun2 'v6.1.1 current HumanMode pacing run2 log')
)

$missingMeasurements = New-Object System.Collections.Generic.List[string]
$allHuman = @($logs | ForEach-Object { $_.human_action_results } | Where-Object { $_ })
if (@($allHuman).Count -eq 0) {
    foreach ($field in @(
        'target_x',
        'target_y',
        'target_rect',
        'cursor_final_position',
        'cursor_before_click',
        'target_epsilon_px',
        'move_mode',
        'click_or_double_click_action_result',
        'foreground_hwnd',
        'active_window_rect',
        'screen_bounds',
        'dpi_scaling'
    )) { $missingMeasurements.Add($field) | Out-Null }
} else {
    if (-not (@($allHuman | Where-Object { $_.target_x_present -and $_.target_y_present }).Count -gt 0)) { $missingMeasurements.Add('target_x/target_y') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.target_rect_present -and $_.target_rect_verified }).Count -gt 0)) { $missingMeasurements.Add('target_rect_verified') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.final_x_present -and $_.final_y_present }).Count -gt 0)) { $missingMeasurements.Add('cursor_final_position') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.actual_before_click_x_present -and $_.actual_before_click_y_present }).Count -gt 0)) { $missingMeasurements.Add('cursor_before_click') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.target_epsilon_present -or $_.distance_to_target_present }).Count -gt 0)) { $missingMeasurements.Add('allowed_tolerance_or_distance') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.move_mode_present }).Count -gt 0)) { $missingMeasurements.Add('move_mode') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.click_sent -or $_.double_click_sent -or $_.action_type -match 'mouse_move' }).Count -gt 0)) { $missingMeasurements.Add('click_or_double_click_action_result') | Out-Null }
    if (-not (@($allHuman | Where-Object { $_.foreground_present }).Count -gt 0)) { $missingMeasurements.Add('foreground_hwnd') | Out-Null }
    foreach ($field in @('active_window_rect','screen_bounds','dpi_scaling')) { $missingMeasurements.Add($field) | Out-Null }
}

$directFiles = New-Object System.Collections.Generic.List[string]
$indirectFiles = New-Object System.Collections.Generic.List[string]
if ($modifiedText) {
    foreach ($line in ($modifiedText -split "`r?`n")) {
        $clean = $line.Trim().TrimStart('-').Trim()
        if ($clean -match 'AdaptiveHumanMode|InputController') { $directFiles.Add($clean) | Out-Null }
        elseif ($clean -match 'WinAgent\.cpp|TaskRunner|TaskSession|build\.ps1') { $indirectFiles.Add($clean) | Out-Null }
    }
}

$scriptAssertions = [ordered]@{
    script_exists = (Test-Path -LiteralPath $pacingScript)
    asserts_within_target_epsilon = (Test-TextHas $scriptText 'within_target_epsilon_before_click')
    asserts_move_duration = (Test-TextHas $scriptText 'move_duration_ms')
    asserts_actual_steps = (Test-TextHas $scriptText 'actual_steps')
    asserts_dwell_before_click = (Test-TextHas $scriptText 'dwell_before_click_ms')
    asserts_double_click_interval = (Test-TextHas $scriptText 'double_click_interval_ms')
    records_trace_jsonl = (Test-TextHas $scriptText 'action_trace\.jsonl')
    checks_failure_contract = (Test-TextHas $scriptText 'ok=false|error\.code')
}

$sourceChecks = [ordered]@{
    fail_cursor_source_found = (Test-TextHas $inputText 'FAIL_CURSOR_NOT_AT_TARGET')
    fail_cursor_source_file = 'src\winagent\InputController.cpp'
    command_result_json_contains_target_and_cursor = (Test-TextHas $winAgentText 'HumanActionResultJson' -and (Test-TextHas $winAgentText 'actual_before_click_x') -and (Test-TextHas $winAgentText 'target_epsilon_px'))
}

$currentLogs = @($logs | Where-Object { $_.label -like 'v6.1.1 current*' })
$currentExisting = @($currentLogs | Where-Object { $_.exists })
$currentFailures = @($currentExisting | Where-Object { $_.has_fail_cursor_not_at_target -or ($_.has_fail_marker -and -not $_.has_pass_marker) })
$currentPasses = @($currentExisting | Where-Object { $_.has_pass_marker -and -not $_.has_fail_cursor_not_at_target })
$oldMissing = -not (Test-Path -LiteralPath $oldV610MissingLog)
$hasFailCursor = @($logs | Where-Object { $_.has_fail_cursor_not_at_target }).Count -gt 0
$doubleClickFailure = @($allHuman | Where-Object { $_.action_type -eq 'mouse_double_click' -and ($_.error_code -eq 'FAIL_CURSOR_NOT_AT_TARGET' -or $_.ok -eq $false) }).Count -gt 0
$moveFailure = @($allHuman | Where-Object { $_.action_type -eq 'mouse_move' -and ($_.error_code -eq 'FAIL_CURSOR_NOT_AT_TARGET' -or $_.ok -eq $false) }).Count -gt 0
$clickFailure = @($allHuman | Where-Object { $_.action_type -eq 'mouse_click' -and ($_.error_code -eq 'FAIL_CURSOR_NOT_AT_TARGET' -or $_.ok -eq $false) }).Count -gt 0

$requiredRerun = $true
$failureType = 'INCONCLUSIVE'
$blockerStatus = 'INCONCLUSIVE_MISSING_MEASUREMENT'
$confidence = 'low'
$possibleEnvironment = $true
$possibleFixture = $true
$possibleRealRegression = $true

if ($oldMissing -and @($currentExisting).Count -eq 0) {
    $failureType = 'EVIDENCE_MISSING'
    $blockerStatus = 'INCONCLUSIVE_MISSING_MEASUREMENT'
    $requiredRerun = $true
} elseif (@($currentExisting).Count -gt 0 -and @($currentFailures).Count -gt 0) {
    if (@($directFiles).Count -gt 0) {
        $failureType = 'V6_1_INDIRECT_REGRESSION'
        $confidence = 'medium'
    } elseif (@($indirectFiles).Count -gt 0) {
        $failureType = 'V6_1_INDIRECT_REGRESSION'
        $confidence = 'low'
    } else {
        $failureType = 'INCONCLUSIVE'
        $confidence = 'low'
    }
    if (@($missingMeasurements).Count -gt 0) {
        $blockerStatus = 'INCONCLUSIVE_MISSING_MEASUREMENT'
    } else {
        $blockerStatus = 'BLOCKED_HUMANMODE_PACING_FAILED'
        $confidence = 'medium'
    }
    $requiredRerun = $false
} elseif (@($currentExisting).Count -ge 2 -and @($currentPasses).Count -ge 2) {
    $failureType = if ($oldMissing) { 'EVIDENCE_MISSING' } else { 'TEST_FIXTURE_FRAGILE' }
    $blockerStatus = if ($oldMissing) { 'OLD_V6_1_0_EVIDENCE_MISSING_CURRENT_RERUNS_PASS' } else { 'CURRENT_RERUNS_PASS_OLD_FAILURE_NOT_REPRODUCED' }
    $requiredRerun = $false
    $possibleRealRegression = $false
    $confidence = 'medium'
}

$result = [ordered]@{
    schema_version = 'v6.1.1.humanmode_regression_triage'
    generated_at = (Get-Date).ToString('o')
    failure_type = $failureType
    failure_detail = $blockerStatus
    direct_humanmode_files_modified_by_v6_1 = @($directFiles)
    indirect_runtime_files_modified_by_v6_1 = @($indirectFiles)
    missing_measurement_fields = @($missingMeasurements | Select-Object -Unique)
    required_rerun_needed = [bool]$requiredRerun
    possible_environment_interference = [bool]$possibleEnvironment
    possible_fixture_fragility = [bool]$possibleFixture
    possible_real_regression = [bool]$possibleRealRegression
    confidence = $confidence
    blocker_status = $blockerStatus
    fail_cursor_not_at_target_found = [bool]$hasFailCursor
    fail_cursor_source = $sourceChecks
    test_assertions = $scriptAssertions
    action_failure_scope = [ordered]@{
        double_click_specific_failure_observed = [bool]$doubleClickFailure
        click_failure_observed = [bool]$clickFailure
        move_failure_observed = [bool]$moveFailure
    }
    logs = @($logs)
}

$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# v6.1.1 HumanMode Regression Triage Report') | Out-Null
$report.Add('') | Out-Null
$report.Add(('- Failure type: `{0}`' -f $failureType)) | Out-Null
$report.Add(('- Blocker status: `{0}`' -f $blockerStatus)) | Out-Null
$report.Add(('- Confidence: `{0}`' -f $confidence)) | Out-Null
$report.Add(('- Required rerun needed: `{0}`' -f $requiredRerun)) | Out-Null
$report.Add(('- v6.1.0 referenced pacing log exists: `{0}`' -f (-not $oldMissing))) | Out-Null
$report.Add('') | Out-Null
$report.Add('## Source Findings') | Out-Null
$report.Add(('- FAIL_CURSOR_NOT_AT_TARGET source found in `src\winagent\InputController.cpp`: {0}' -f $sourceChecks.fail_cursor_source_found)) | Out-Null
$report.Add(('- v6.1.0 direct HumanMode file modifications found: {0}' -f @($directFiles).Count)) | Out-Null
$report.Add(('- v6.1.0 indirect runtime/shared modifications found: {0}' -f @($indirectFiles).Count)) | Out-Null
$report.Add('') | Out-Null
$report.Add('## Measurement Gaps') | Out-Null
foreach ($field in @($missingMeasurements | Select-Object -Unique)) { $report.Add("- $field") | Out-Null }
if (@($missingMeasurements).Count -eq 0) { $report.Add('- None') | Out-Null }
$report.Add('') | Out-Null
$report.Add('## Log Audit') | Out-Null
foreach ($log in $logs) {
    $report.Add(('- {0}: exists={1}, fail_cursor={2}, pass_marker={3}, path=`{4}`' -f $log.label, $log.exists, $log.has_fail_cursor_not_at_target, $log.has_pass_marker, $log.path)) | Out-Null
}
$report.Add('') | Out-Null
$report.Add('## Result JSON') | Out-Null
$report.Add('') | Out-Null
$report.Add('```json') | Out-Null
$report.Add(($result | ConvertTo-Json -Depth 20)) | Out-Null
$report.Add('```') | Out-Null
$report | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($requiredRerun -or $blockerStatus -eq 'INCONCLUSIVE_MISSING_MEASUREMENT') {
    @(
        '# Required Real UI Rerun Plan',
        '',
        '- Reason: existing evidence is missing or lacks enough measurement fields to conclusively classify FAIL_CURSOR_NOT_AT_TARGET.',
        '- Required command run 1:',
        '',
        '```powershell',
        'D:\desktopvisual\v5_9_0_e_humanmode_motion_pacing_test.ps1 -Root D:\desktopvisual -SkipBuild',
        '```',
        '',
        '- Required command run 2:',
        '',
        '```powershell',
        'D:\desktopvisual\v5_9_0_e_humanmode_motion_pacing_test.ps1 -Root D:\desktopvisual -SkipBuild',
        '```',
        '',
        '- Save raw stdout/stderr and exit code separately under `artifacts\dev6.1.1_humanmode_regression_triage_and_evidence_gate\raw\`.',
        '- After rerun, run `D:\desktopvisual\v6_1_1_humanmode_regression_triage.ps1 -Root D:\desktopvisual` again.'
    ) | Set-Content -LiteralPath $RerunPlanPath -Encoding UTF8
}

Write-Host "TRIAGE_RESULT: $failureType"
Write-Host "TRIAGE_DETAIL: $blockerStatus"
Write-Host "Result: $ResultPath"
Write-Host "Report: $ReportPath"
if (Test-Path -LiteralPath $RerunPlanPath) { Write-Host "Rerun plan: $RerunPlanPath" }
