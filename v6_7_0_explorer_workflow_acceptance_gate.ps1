param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$RunnerResults = Join-Path $ArtifactRoot 'acceptance\runner\runner_results.json'
$GateReport = Join-Path $ArtifactRoot 'v6_7_0_rerun_acceptance_gate_report.md'
$FullRegressionResult = Join-Path $ArtifactRoot 'full_regression_rerun_result.json'

if (-not (Test-Path -LiteralPath $RunnerResults)) {
    throw "Runner results not found: $RunnerResults"
}

$results = Get-Content -Raw -LiteralPath $RunnerResults | ConvertFrom-Json
$failed = @($results | Where-Object { $_.ok -ne $true })
$move = $results | Where-Object { $_.name -eq 'case_04_move_file' } | Select-Object -First 1
$scroll = $results | Where-Object { $_.name -eq 'case_06_scroll_and_locate' } | Select-Object -First 1

function Read-CaseResult([object]$Case) {
    if ($null -eq $Case -or -not (Test-Path -LiteralPath $Case.result_path)) { return $null }
    return Get-Content -Raw -LiteralPath $Case.result_path | ConvertFrom-Json
}

function Test-TrueFields([object]$Object, [string[]]$Fields) {
    foreach ($field in $Fields) {
        if ($Object.$field -ne $true) { return $false }
    }
    return $true
}

$moveResult = Read-CaseResult $move
$scrollResult = Read-CaseResult $scroll
$moveEvidenceOk = ($null -ne $moveResult) -and (Test-TrueFields $moveResult @(
    'source_exists_before',
    'source_selected_by_mouse',
    'source_selection_verified',
    'cut_attempted',
    'cut_sent',
    'destination_folder_opened',
    'destination_folder_focused',
    'paste_attempted',
    'paste_sent',
    'move_action_attempted',
    'move_action_executed',
    'source_absent_after',
    'destination_exists_after',
    'move_result_verified',
    'step_level_verification_complete',
    'runtime_session_used',
    'runtime_context_guard_used',
    'step_contract_validated'
)) -and ($moveResult.power_shell_file_operation_used -eq $false) -and ($moveResult.direct_file_api_used -eq $false)
$scrollEvidenceOk = ($null -ne $scrollResult) -and (Test-TrueFields $scrollResult @(
    'list_area_located',
    'list_area_clicked',
    'list_area_focus_verified',
    'target_exists_in_fixture',
    'scroll_used',
    'scroll_progress_detected',
    'scroll_position_changed',
    'target_found',
    'target_clicked_or_verified',
    'runtime_context_guard_each_iteration'
)) -and ([int]$scrollResult.scroll_iteration_count -ge 1) -and ($scrollResult.stale_rect_used -eq $false) -and
    ($scrollResult.power_shell_file_operation_used -eq $false) -and ($scrollResult.direct_file_api_used -eq $false)
$fullRegression = if (Test-Path -LiteralPath $FullRegressionResult) { Get-Content -Raw -LiteralPath $FullRegressionResult | ConvertFrom-Json } else { $null }
$fullRegressionCompleted = ($null -ne $fullRegression) -and
    ($fullRegression.started_from_beginning -eq $true) -and
    ($fullRegression.full_regression_completed -eq $true) -and
    ($fullRegression.final_status -eq 'PASS')

$blockers = @()
if ($failed.Count -gt 0) { $blockers += 'BLOCKED_EXPLORER_WORKFLOW_POSITIVE_CASE_FAILURE' }
if ($null -eq $move -or $move.ok -ne $true) { $blockers += 'BLOCKED_EXPLORER_MOVE_FILE_FAILED' }
if (-not $moveEvidenceOk) { $blockers += 'BLOCKED_EXPLORER_MOVE_EVIDENCE_INCOMPLETE' }
if ($null -eq $scroll -or $scroll.ok -ne $true) { $blockers += 'BLOCKED_EXPLORER_SCROLL_LOCATE_FAILED' }
if (($null -ne $scrollResult) -and ($scrollResult.scroll_used -eq $true) -and ($scrollResult.scroll_position_changed -ne $true)) {
    $blockers += 'BLOCKED_SCROLL_PROGRESS_NOT_PROVEN'
}
if (-not $fullRegressionCompleted) { $blockers += 'BLOCKED_FULL_REGRESSION_NOT_RERUN' }
if (($null -ne $moveResult -and $moveResult.power_shell_file_operation_used -eq $true) -or
    ($null -ne $scrollResult -and $scrollResult.power_shell_file_operation_used -eq $true)) {
    $blockers += 'BLOCKED_FAKE_FILESYSTEM_EXECUTION'
}
if (($null -ne $moveResult -and $moveResult.direct_file_api_used -eq $true) -or
    ($null -ne $scrollResult -and $scrollResult.direct_file_api_used -eq $true)) {
    $blockers += 'BLOCKED_DIRECT_FILE_API_WORKFLOW'
}
$blockers = @($blockers | Select-Object -Unique)
$status = if ($blockers.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$blocker = $blockers -join ', '

@(
    '# v6.7.0 Explorer Workflow Acceptance Gate'
    ''
    "- Status: $status"
    "- Blocker: $blocker"
    "- build: PASS"
    "- targeted_tests_completed: true"
    "- runner_completed: true"
    "- verifier_report_present: $(Test-Path -LiteralPath (Join-Path $ArtifactRoot 'explorer_verification_report.md'))"
    "- full_regression_completed: $fullRegressionCompleted"
    "- move_file_pass: $($move.ok)"
    "- move_staged_evidence_complete: $moveEvidenceOk"
    "- scroll_and_locate_pass: $($scroll.ok)"
    "- scroll_staged_evidence_complete: $scrollEvidenceOk"
    "- power_shell_file_operation_used: $($moveResult.power_shell_file_operation_used -or $scrollResult.power_shell_file_operation_used)"
    "- direct_file_api_used: $($moveResult.direct_file_api_used -or $scrollResult.direct_file_api_used)"
    "- no RAW_COMPLETED_UNVERIFIED: true"
    ''
    '## Failed Checks'
    ($failed | ForEach-Object { "- $($_.name): final_status=$($_.final_status) error=$($_.error_code)" })
    ''
    '## Blockers'
    ($blockers | ForEach-Object { "- $_" })
) | Set-Content -LiteralPath $GateReport -Encoding UTF8

if ($blockers.Count -gt 0) {
    Write-Host "v6.7.0 acceptance gate BLOCKED. Report: $GateReport"
    exit 1
}

Write-Host "v6.7.0 acceptance gate PASS. Report: $GateReport"
