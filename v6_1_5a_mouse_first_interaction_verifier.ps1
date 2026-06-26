param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5a_visible_mouse_first_interaction'
$RawRoot = Join-Path $ArtifactRoot 'raw\mouse_first'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified\mouse_first'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Code,
        [string]$CaseId,
        [string]$Message,
        [string]$Path = ''
    )
    $Findings.Add([pscustomobject]@{
        code = $Code
        case_id = $CaseId
        message = $Message
        path = $Path
        blocking = $true
    }) | Out-Null
}

function Test-HumanMouseAction {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$CaseId,
        [object]$Action
    )
    if (-not $Action) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Mouse action entry is missing.'
        return
    }
    if (-not (Test-Path -LiteralPath ([string]$Action.human_action_result_path))) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Human action result JSON is missing.' ([string]$Action.human_action_result_path)
        return
    }
    $human = Read-Json ([string]$Action.human_action_result_path)
    if (-not $human) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Human action result JSON is invalid.' ([string]$Action.human_action_result_path)
        return
    }
    if ($human.ok -ne $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Human mouse action did not complete ok=true.' ([string]$Action.human_action_result_path)
    }
    if ($human.backend_action -eq $true -or $human.direct_launch -eq $true) {
        Add-Finding $Findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' $CaseId 'Mouse PASS evidence contains backend_action or direct_launch.' ([string]$Action.human_action_result_path)
    }
    if ($human.actual_click_sent -ne $true -and $human.actual_double_click_sent -ne $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Mouse action lacks actual click or double-click sent.' ([string]$Action.human_action_result_path)
    }
    if ($human.verification.cursor_inside_target_rect_before_click -ne $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $CaseId 'Cursor was not verified inside target rect before click.' ([string]$Action.human_action_result_path)
    }
    if (-not $Action.target_rect -or -not $Action.target_center -or $Action.target_visible -ne $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Action lacks visible target rect/center evidence.'
    }
    if ([string]$Action.coordinate_source_type -notin @('locator_derived_coordinate', 'fixed_coordinate', 'fallback_coordinate')) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Action has invalid coordinate_source_type.'
    }
    if ([string]$Action.coordinate_source_type -eq 'fixed_coordinate' -and [string]::IsNullOrWhiteSpace([string]$Action.fixed_coordinate_reason)) {
        Add-Finding $Findings 'BLOCKED_UNDISCLOSED_FIXED_COORDINATE' $CaseId 'Fixed coordinate was used without reason.'
    }
    if ([string]$Action.coordinate_source_type -eq 'fallback_coordinate') {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $CaseId 'Fallback coordinate cannot count as mouse-first PASS.'
    }
    if ($Action.fallback_used -eq $true) {
        Add-Finding $Findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' $CaseId 'Mouse action reported fallback_used=true.'
    }
}

function Test-CommonMouseFirstCase {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [object]$Case,
        [bool]$AllowChromeFallback = $false
    )
    $caseId = [string]$Case.case_id
    if ($Case.raw_status -ne 'RAW_COMPLETED_UNVERIFIED') {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $caseId 'Case raw_status must remain RAW_COMPLETED_UNVERIFIED.'
    }
    if ($Case.interaction_mode -ne 'mouse_first' -or $Case.mouse_first_required -ne $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $caseId 'Case interaction_mode/mouse_first_required is invalid.'
    }
    if ($Case.mouse_first_passed -ne $true -and -not $AllowChromeFallback) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $caseId 'Runner raw fields do not show mouse_first_passed=true.'
    }
    if ([int]$Case.mouse_move_count -lt 1 -and -not $AllowChromeFallback) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $caseId 'mouse_move_count < 1.'
    }
    if ([int]$Case.mouse_click_count -lt 1 -and -not $AllowChromeFallback) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $caseId 'mouse_click_count < 1.'
    }
    if ($Case.keyboard_only_path_used -eq $true) {
        Add-Finding $Findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' $caseId 'keyboard_only_path_used=true in mouse-first PASS case.'
    }
    if ($Case.fallback_used -eq $true -and -not $AllowChromeFallback) {
        Add-Finding $Findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' $caseId 'fallback_used=true in mouse-first PASS case.'
    }
    if ($Case.focus_verified_after_click -ne $true -and -not $AllowChromeFallback) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $caseId 'focus_verified_after_click is not true.'
    }
    if ($Case.context_verified_after_click -ne $true -and -not $AllowChromeFallback) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $caseId 'context_verified_after_click is not true.'
    }
    if ([int]$Case.wrong_field_input_count -ne 0) {
        Add-Finding $Findings 'BLOCKED_WRONG_FIELD_INPUT' $caseId 'wrong_field_input_count is not zero.'
    }
    if ($Case.continued_action_after_wrong_context -eq $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $caseId 'continued_action_after_wrong_context=true.'
    }
    foreach ($action in @($Case.mouse_actions)) {
        Test-HumanMouseAction -Findings $Findings -CaseId $caseId -Action $action
    }
}

$matrixPath = Join-Path $RawRoot 'mouse_first_raw_matrix.json'
$matrix = Read-Json $matrixPath
$findings = New-Object System.Collections.Generic.List[object]

if (-not $matrix) {
    Add-Finding $findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' 'matrix' 'Mouse-first raw matrix is missing or invalid.' $matrixPath
} elseif ($matrix.runner_self_certified_pass -ne $false -or $matrix.runner_status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding $findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' 'matrix' 'Runner attempted to self-certify or did not use RAW_COMPLETED_UNVERIFIED.' $matrixPath
}

$caseMap = @{}
if ($matrix -and $matrix.cases) {
    foreach ($case in @($matrix.cases)) {
        $caseMap[[string]$case.case_id] = $case
    }
}

$required = @(
    'case_1_mouse_first_chrome_open',
    'case_2_mouse_click_address_bar',
    'case_3_mouse_first_search_box',
    'case_4_mouse_click_search_result_link',
    'case_5_mouse_first_form_fill',
    'case_6_mouse_click_code_editor_run',
    'case_7_mouse_mid_editor_reposition'
)

foreach ($caseId in $required) {
    if (-not $caseMap.ContainsKey($caseId)) {
        Add-Finding $findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $caseId 'Required mouse-first case is missing.'
    }
}

if ($caseMap.ContainsKey('case_1_mouse_first_chrome_open')) {
    $case = $caseMap['case_1_mouse_first_chrome_open']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ($case.chrome_visible_entry_located -ne $true -or $case.chrome_clicked_or_double_clicked_by_mouse -ne $true -or $case.chrome_foreground_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' $case.case_id 'Chrome visible entry, mouse double-click, or foreground verification failed.'
    }
}

if ($caseMap.ContainsKey('case_2_mouse_click_address_bar')) {
    $case = $caseMap['case_2_mouse_click_address_bar']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ($case.address_bar_clicked_by_mouse -ne $true -or $case.typed_url_verified -ne $true -or $case.page_marker_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $case.case_id 'Address bar mouse click, typed URL, or page marker verification failed.'
    }
}

if ($caseMap.ContainsKey('case_3_mouse_first_search_box')) {
    $case = $caseMap['case_3_mouse_first_search_box']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ($case.search_box_clicked_by_mouse -ne $true -or $case.search_button_clicked_by_mouse -ne $true -or $case.typed_text_verified -ne $true -or $case.results_context_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $case.case_id 'Search box/button mouse click or result context verification failed.'
    }
}

if ($caseMap.ContainsKey('case_4_mouse_click_search_result_link')) {
    $case = $caseMap['case_4_mouse_click_search_result_link']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ($case.result_candidate_located -ne $true -or $case.result_clicked_by_mouse -ne $true -or $case.new_context_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $case.case_id 'Search result/link mouse click or new context verification failed.'
    }
}

if ($caseMap.ContainsKey('case_5_mouse_first_form_fill')) {
    $case = $caseMap['case_5_mouse_first_form_fill']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ([int]$case.field_click_count -lt 2 -or $case.focus_verified_after_each_click -ne $true -or $case.submit_clicked_by_mouse -ne $true -or $case.result_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_WRONG_FIELD_INPUT' $case.case_id 'Form field clicks, focus verification, submit click, or result verification failed.'
    }
}

if ($caseMap.ContainsKey('case_6_mouse_click_code_editor_run')) {
    $case = $caseMap['case_6_mouse_click_code_editor_run']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ($case.editor_clicked_by_mouse -ne $true -or $case.editor_focus_verified -ne $true -or $case.code_text_verified -ne $true -or $case.run_button_clicked_by_mouse -ne $true -or $case.result_observed -ne $true) {
        Add-Finding $findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $case.case_id 'Code editor click, code verification, Run click, or result observation failed.'
    }
}

if ($caseMap.ContainsKey('case_7_mouse_mid_editor_reposition')) {
    $case = $caseMap['case_7_mouse_mid_editor_reposition']
    Test-CommonMouseFirstCase -Findings $findings -Case $case
    if ($case.mid_editor_click_sent -ne $true -or $case.focus_verified_after_mid_click -ne $true -or $case.insert_text_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' $case.case_id 'Mid-editor mouse click or inserted text verification failed.'
    }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema_version = 'v6.1.5a.mouse_first.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    case_count = if ($matrix -and $matrix.cases) { @($matrix.cases).Count } else { 0 }
    required_case_count = $required.Count
    findings = @($findings.ToArray())
    raw_matrix = $matrixPath
}
$resultPath = Join-Path $VerifiedRoot 'mouse_first_verifier_result.json'
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1}: {2} `{3}`' -f $_.code, $_.case_id, $_.message, $_.path
}
if ($findingRows.Count -eq 0) { $findingRows = @('- No blocking findings.') }

@(
    '# v6.1.5a Mouse First Interaction Verifier',
    '',
    "- Result: $status",
    "- Raw matrix: $matrixPath",
    "- Verifier result: $resultPath",
    '',
    '## Findings'
) + $findingRows | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mouse_first_interaction_verifier_report.md') -Encoding UTF8

function Write-CaseReport {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$CaseIds
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $Title") | Out-Null
    $lines.Add('') | Out-Null
    foreach ($caseId in $CaseIds) {
        if (-not $caseMap.ContainsKey($caseId)) {
            $lines.Add("- ${caseId}: MISSING") | Out-Null
            continue
        }
        $case = $caseMap[$caseId]
        $localFindings = @($findings.ToArray() | Where-Object { $_.case_id -eq $caseId })
        $caseStatus = if ($localFindings.Count -eq 0) { 'PASS' } else { 'FAIL' }
        $lines.Add("- ${caseId}: $caseStatus") | Out-Null
        $lines.Add("  - mouse_move_count: $($case.mouse_move_count)") | Out-Null
        $lines.Add("  - mouse_click_count: $($case.mouse_click_count)") | Out-Null
        $lines.Add("  - keyboard_only_path_used: $($case.keyboard_only_path_used)") | Out-Null
        $lines.Add("  - fallback_used: $($case.fallback_used)") | Out-Null
        $lines.Add("  - wrong_field_input_count: $($case.wrong_field_input_count)") | Out-Null
    }
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

Write-CaseReport -Path (Join-Path $ArtifactRoot 'chrome_open_mouse_report.md') -Title 'v6.1.5a Chrome Mouse Open Report' -CaseIds @('case_1_mouse_first_chrome_open')
Write-CaseReport -Path (Join-Path $ArtifactRoot 'address_bar_mouse_report.md') -Title 'v6.1.5a Address Bar Mouse Report' -CaseIds @('case_2_mouse_click_address_bar')
Write-CaseReport -Path (Join-Path $ArtifactRoot 'search_mouse_report.md') -Title 'v6.1.5a Search Mouse Report' -CaseIds @('case_3_mouse_first_search_box','case_4_mouse_click_search_result_link')
Write-CaseReport -Path (Join-Path $ArtifactRoot 'form_mouse_report.md') -Title 'v6.1.5a Form Mouse Report' -CaseIds @('case_5_mouse_first_form_fill')
Write-CaseReport -Path (Join-Path $ArtifactRoot 'code_editor_mouse_report.md') -Title 'v6.1.5a Code Editor Mouse Report' -CaseIds @('case_6_mouse_click_code_editor_run','case_7_mouse_mid_editor_reposition')

if ($status -eq 'PASS') { exit 0 }
exit 1
