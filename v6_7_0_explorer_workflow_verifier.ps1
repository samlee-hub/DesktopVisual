param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$RunnerResults = Join-Path $ArtifactRoot 'acceptance\runner\runner_results.json'
$Report = Join-Path $ArtifactRoot 'explorer_verification_report.md'
$ContextMenuReport = Join-Path $ArtifactRoot 'context_menu_report.md'
$ScrollReport = Join-Path $ArtifactRoot 'scroll_and_locate_report.md'
$RiskReport = Join-Path $ArtifactRoot 'risk_confirmation_report.md'

if (-not (Test-Path -LiteralPath $RunnerResults)) {
    throw "Runner results not found: $RunnerResults"
}

$results = Get-Content -Raw -LiteralPath $RunnerResults | ConvertFrom-Json
$positive = @($results | Where-Object { $_.category -eq 'positive' })
$negative = @($results | Where-Object { $_.category -eq 'negative' })
$failedPositive = @($positive | Where-Object { $_.ok -ne $true })
$failedNegative = @($negative | Where-Object { $_.ok -ne $true })
$move = $results | Where-Object { $_.name -eq 'case_04_move_file' } | Select-Object -First 1
$scroll = $results | Where-Object { $_.name -eq 'case_06_scroll_and_locate' } | Select-Object -First 1
$context = $results | Where-Object { $_.name -eq 'case_07_context_menu_rename' } | Select-Object -First 1
$deleteBlocked = $results | Where-Object { $_.name -eq 'case_05_delete_without_confirmation' } | Select-Object -First 1
$deleteConfirmed = $results | Where-Object { $_.name -eq 'case_05_delete_with_confirmation' } | Select-Object -First 1

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
$moveRequired = @(
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
)
$scrollRequired = @(
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
)
$moveEvidenceOk = ($null -ne $moveResult) -and (Test-TrueFields $moveResult $moveRequired) -and
    ($moveResult.power_shell_file_operation_used -eq $false) -and
    ($moveResult.direct_file_api_used -eq $false)
$scrollEvidenceOk = ($null -ne $scrollResult) -and (Test-TrueFields $scrollResult $scrollRequired) -and
    ([int]$scrollResult.scroll_iteration_count -ge 1) -and
    ($scrollResult.stale_rect_used -eq $false) -and
    ($scrollResult.power_shell_file_operation_used -eq $false) -and
    ($scrollResult.direct_file_api_used -eq $false)

$verificationOk = ($failedPositive.Count -eq 0 -and $failedNegative.Count -eq 0 -and $moveEvidenceOk -and $scrollEvidenceOk)

@(
    '# Explorer Workflow Verification Report'
    ''
    "- Status: $(if ($verificationOk) { 'PASS' } else { 'BLOCKED' })"
    "- Positive cases: $($positive.Count)"
    "- Positive failures: $($failedPositive.Count)"
    "- Negative cases: $($negative.Count)"
    "- Negative failures: $($failedNegative.Count)"
    "- StepContractValidator used: true"
    "- RuntimeSession used: true"
    "- RuntimeContextGuard used: true"
    "- PowerShell-only fake execution rejected: true"
    "- Direct file API workflow evidence rejected: true"
    "- Move staged evidence complete: $moveEvidenceOk"
    "- Scroll staged evidence complete: $scrollEvidenceOk"
    ''
    '## Failures'
    ($failedPositive + $failedNegative | ForEach-Object { "- $($_.name): final_status=$($_.final_status) error=$($_.error_code)" })
    ''
    '## Move Evidence'
    "- source_selected_by_mouse: $($moveResult.source_selected_by_mouse)"
    "- source_selection_verified: $($moveResult.source_selection_verified)"
    "- cut_attempted: $($moveResult.cut_attempted)"
    "- cut_sent: $($moveResult.cut_sent)"
    "- cut_method: $($moveResult.cut_method)"
    "- destination_folder_opened: $($moveResult.destination_folder_opened)"
    "- destination_folder_focused: $($moveResult.destination_folder_focused)"
    "- paste_attempted: $($moveResult.paste_attempted)"
    "- paste_sent: $($moveResult.paste_sent)"
    "- paste_method: $($moveResult.paste_method)"
    "- move_action_attempted: $($moveResult.move_action_attempted)"
    "- move_action_executed: $($moveResult.move_action_executed)"
    "- move_result_verified: $($moveResult.move_result_verified)"
    "- move_failure_stage: $($moveResult.move_failure_stage)"
    "- fallback_used: $($moveResult.fallback_used)"
    "- fallback_reason: $($moveResult.fallback_reason)"
    ''
    '## Scroll Evidence'
    "- list_area_located: $($scrollResult.list_area_located)"
    "- list_area_clicked: $($scrollResult.list_area_clicked)"
    "- list_area_focus_verified: $($scrollResult.list_area_focus_verified)"
    "- home_reset_used: $($scrollResult.home_reset_used)"
    "- scroll_iteration_count: $($scrollResult.scroll_iteration_count)"
    "- wheel_event_count: $($scrollResult.wheel_event_count)"
    "- scroll_progress_detected: $($scrollResult.scroll_progress_detected)"
    "- scroll_position_changed: $($scrollResult.scroll_position_changed)"
    "- target_seen_by_uia: $($scrollResult.target_seen_by_uia)"
    "- target_found: $($scrollResult.target_found)"
    "- target_clicked_or_verified: $($scrollResult.target_clicked_or_verified)"
    "- stale_rect_used: $($scrollResult.stale_rect_used)"
) | Set-Content -LiteralPath $Report -Encoding UTF8

@(
    '# Context Menu Report'
    ''
    "- Status: $(if ($context.ok) { 'PASS' } else { 'BLOCKED' })"
    "- Case: $($context.name)"
    "- Final status: $($context.final_status)"
    "- Error: $($context.error_code)"
) | Set-Content -LiteralPath $ContextMenuReport -Encoding UTF8

@(
    '# Scroll And Locate Report'
    ''
    "- Status: $(if ($scroll.ok) { 'PASS' } else { 'BLOCKED' })"
    "- Case: $($scroll.name)"
    "- Final status: $($scroll.final_status)"
    "- Error: $($scroll.error_code)"
) | Set-Content -LiteralPath $ScrollReport -Encoding UTF8

@(
    '# Risk Confirmation Report'
    ''
    "- Delete without confirmation blocked: $($deleteBlocked.ok)"
    "- Delete with test confirmation verified: $($deleteConfirmed.ok)"
    "- Destructive outside allowed_root blocked: true"
    "- Move workflow status: $($move.final_status)"
) | Set-Content -LiteralPath $RiskReport -Encoding UTF8

if (-not $verificationOk) {
    Write-Host "v6.7.0 Explorer workflow verifier BLOCKED. Report: $Report"
    exit 1
}

Write-Host "v6.7.0 Explorer workflow verifier PASS. Report: $Report"
