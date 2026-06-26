param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc_fresh'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$SingleRoot = Join-Path $RawRoot 'single_cases'
$NegativeRoot = Join-Path $RawRoot 'negative_cases'
$IntegratedRoot = Join-Path $RawRoot 'integrated_sequence'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$RegistryPath = Join-Path $ArtifactRoot 'case_status_registry.json'

$Cases = @(
    [ordered]@{
        case_id = 'case_1_qqmail_send'
        case_name = 'QQ Mail real send test'
        block_code = 'BLOCKED_QQMAIL_FULL_ACCESS_CASE_FAILED'
        report = 'qqmail_case_report.md'
        min_mouse_clicks = 7
        required_true = @('qqmail_opened','compose_clicked_by_mouse','compose_context_verified','recipient_field_clicked_by_mouse','subject_field_clicked_by_mouse','body_field_clicked_by_mouse','send_clicked_by_mouse','recipient_verified','subject_verified','body_verified','send_success_verified','post_send_not_sent_folder_navigation','post_action_causal_verified')
    },
    [ordered]@{
        case_id = 'case_2_pycharm_run'
        case_name = 'PyCharm code input run output verification'
        block_code = 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED'
        report = 'pycharm_case_report.md'
        min_mouse_clicks = 2
        required_true = @('pycharm_opened','editor_clicked_by_mouse','editor_focus_verified','existing_code_checked','existing_code_cleared_if_present','code_text_verified','code_input_indentation_verified','run_icon_visual_target_limitation','run_via_keyboard_shortcut','run_shortcut_sent','vlm_or_visual_template_future_work','run_triggered','execution_started','execution_completed','execution_success','exit_code_present','current_run_verified','expected_output_verified','run_start_marker_verified','run_end_marker_verified','output_observed','output_count_between_2_and_10','output_sequence_verified','output_is_current_run','post_action_causal_verified')
    },
    [ordered]@{
        case_id = 'case_3_wechat_file_transfer'
        case_name = 'WeChat File Transfer Assistant message send'
        block_code = 'BLOCKED_WECHAT_FULL_ACCESS_CASE_FAILED'
        report = 'wechat_case_report.md'
        min_mouse_clicks = 4
        required_true = @('wechat_opened','file_transfer_assistant_located','wechat_target_is_chat_list_item','wechat_target_not_message_history','chat_clicked_by_mouse','chat_title_verified','message_input_clicked_by_mouse','message_text_verified_before_send','send_target_verified_before_click','send_clicked_by_mouse','message_sent_verified','scroll_if_needed_evidence_present','post_action_causal_verified')
    },
    [ordered]@{
        case_id = 'case_4_tiktok_search'
        case_name = 'TikTok two-query search test'
        block_code = 'BLOCKED_TIKTOK_FULL_ACCESS_CASE_FAILED'
        report = 'tiktok_case_report.md'
        min_mouse_clicks = 4
        required_true = @('tiktok_opened','search_box_clicked_by_mouse','first_query_text_verified','first_search_result_verified','second_query_text_verified','second_search_result_verified','mouse_click_evidence_present','keyword_not_corrected','search_history_item_not_clicked','post_action_causal_verified')
    }
)

function U([int[]]$Codes) {
    $chars = foreach ($code in $Codes) { [char]$code }
    return -join $chars
}

$QqText = [ordered]@{
    Send = (U @(21457,36865))
    Sent = (U @(24050,21457,36865))
    SentMail = (U @(24050,21457,36865,37038,20214))
    SentFolder = (U @(24050,21457,36865,25991,20214,22841))
    Outbox = (U @(21457,20214,31665))
    Drafts = (U @(33609,31295,31665))
}

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Save-Json($Value, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { Ensure-Dir $dir }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Initialize-Registry {
    if (Test-Path -LiteralPath $RegistryPath) { return }
    $rows = foreach ($case in $Cases) {
        [ordered]@{
            case_id = $case.case_id
            case_name = $case.case_name
            status = 'pending'
            last_pass_evidence_path = ''
            last_failure_evidence_path = ''
            frozen_after_pass = $false
            rerun_required = $false
            attempt_count = 0
            last_run_timestamp = ''
        }
    }
    Save-Json @($rows) $RegistryPath
}

function Read-RegistryMap {
    Initialize-Registry
    $rawRows = Read-Json $RegistryPath
    $rows = @()
    foreach ($item in @($rawRows)) {
        if ($item -is [System.Array]) { $rows += @($item) } else { $rows += $item }
    }
    $map = @{}
    foreach ($row in $rows) { $map[[string]$row.case_id] = $row }
    return $map
}

function Save-RegistryMap($Map) {
    $rows = foreach ($case in $Cases) { $Map[$case.case_id] }
    Save-Json @($rows) $RegistryPath
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

function Get-PropertyValue($Object, [string]$Name) {
    if (-not $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Test-True($Object, [string]$Name) {
    return ((Get-PropertyValue $Object $Name) -eq $true)
}

function Add-CaseFailure([System.Collections.Generic.List[object]]$Findings, $CaseMeta, [string]$Message, [string]$Path = '') {
    Add-Finding $Findings ([string]$CaseMeta.block_code) ([string]$CaseMeta.case_id) $Message $Path
}

function Test-QqMailNegativeText([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $trimmed = $Value.Trim()
    foreach ($item in @($QqText.Sent,$QqText.SentMail,$QqText.SentFolder,$QqText.Outbox,$QqText.Drafts,'Sent','Sent Mail')) {
        if ($trimmed -eq $item) { return $true }
    }
    if ($trimmed -ne $QqText.Send -and $trimmed.Contains($QqText.Send)) { return $true }
    return $false
}

function Add-QqMailWrongSendTarget([System.Collections.Generic.List[object]]$Findings, [string]$Message, [string]$Path) {
    Add-Finding $Findings 'BLOCKED_QQMAIL_WRONG_SEND_TARGET' 'case_1_qqmail_send' $Message $Path
}

function Add-TargetSemanticsFinding([System.Collections.Generic.List[object]]$Findings, [string]$CaseId, [string]$Message, [string]$Path) {
    Add-Finding $Findings 'BLOCKED_RUNNER_ONLY_TARGET_SEMANTICS' $CaseId $Message $Path
}

function Add-ExecutionOutcomeFinding([System.Collections.Generic.List[object]]$Findings, [string]$Code, [string]$Message, [string]$Path) {
    Add-Finding $Findings $Code 'case_2_pycharm_run' $Message $Path
}

function Get-CaseEvidencePath($Registry, [string]$CaseId) {
    $row = $Registry[$CaseId]
    if ($row -and -not [string]::IsNullOrWhiteSpace([string]$row.last_pass_evidence_path)) { return [string]$row.last_pass_evidence_path }
    if ($row -and -not [string]::IsNullOrWhiteSpace([string]$row.last_failure_evidence_path)) { return [string]$row.last_failure_evidence_path }
    $defaultPath = Join-Path (Join-Path $SingleRoot $CaseId) 'evidence.json'
    if (Test-Path -LiteralPath $defaultPath) { return $defaultPath }
    return ''
}

function Read-HumanAction($Action) {
    $path = [string]$Action.human_action_result_path
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return Read-Json $path
}

function Validate-MouseActions {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $CaseMeta,
        $Evidence,
        [string]$EvidencePath
    )
    $caseId = [string]$CaseMeta.case_id
    $actions = @($Evidence.mouse_actions)
    if ($actions.Count -lt [int]$CaseMeta.min_mouse_clicks) {
        Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId "Mouse action count $($actions.Count) is below required minimum $($CaseMeta.min_mouse_clicks)." $EvidencePath
    }
    foreach ($action in $actions) {
        $guard = $action.target_semantics_guard
        if (-not $guard) {
            Add-TargetSemanticsFinding $Findings $caseId 'Mouse action lacks bottom-layer target_semantics_guard evidence.' $EvidencePath
        } else {
            if ($guard.enabled -ne $true -or $guard.ok -ne $true) {
                Add-TargetSemanticsFinding $Findings $caseId "TargetSemanticsGuard was not enabled and ok for action $($action.step)." $EvidencePath
            }
            if ($guard.pre_click_semantic_verified -ne $true -or $guard.pre_click_role_verified -ne $true) {
                Add-Finding $Findings 'BLOCKED_MISSING_CLICKED_TARGET_EVIDENCE' $caseId "TargetSemanticsGuard did not verify semantic/role before click for action $($action.step)." $EvidencePath
            }
            if ([string]::IsNullOrWhiteSpace([string]$guard.clicked_target_text) -or [string]::IsNullOrWhiteSpace([string]$guard.clicked_target_region) -or [string]::IsNullOrWhiteSpace([string]$guard.clicked_target_role)) {
                Add-Finding $Findings 'BLOCKED_MISSING_CLICKED_TARGET_EVIDENCE' $caseId "TargetSemanticsGuard clicked target text/role/region is missing for action $($action.step)." $EvidencePath
            }
            if ($guard.clicked_target_is_expected_target -ne $true -or $guard.clicked_target_is_forbidden_similar_target -eq $true) {
                Add-Finding $Findings 'BLOCKED_MOUSE_MISCLICK' $caseId "TargetSemanticsGuard marked clicked target as unexpected or forbidden for action $($action.step)." $EvidencePath
            }
        }
        if ([string]$action.coordinate_source_type -ne 'locator_derived_coordinate') {
            Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'A PASS-counted mouse action is not locator_derived_coordinate.' $EvidencePath
        }
        if ($action.click_sent -ne $true) {
            Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'A PASS-counted mouse action lacks click_sent=true.' $EvidencePath
        }
        if ($action.target_visible -ne $true -or -not $action.target_rect -or -not $action.target_center) {
            Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'A PASS-counted mouse action lacks visible target geometry.' $EvidencePath
        }
        $human = Read-HumanAction $action
        if (-not $human) {
            Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'Human action result JSON is missing or invalid.' ([string]$action.human_action_result_path)
        } else {
            if ($human.backend_action -eq $true -or $human.direct_launch -eq $true) {
                Add-Finding $Findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' $caseId 'Human action result indicates backend_action or direct_launch.' ([string]$action.human_action_result_path)
            }
            if ($human.actual_click_sent -ne $true -and $human.actual_double_click_sent -ne $true) {
                Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'Human action result lacks actual mouse click.' ([string]$action.human_action_result_path)
            }
            if ($human.verification -and $human.verification.cursor_inside_target_rect_before_click -eq $false) {
                Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'Cursor was not inside target rect before click.' ([string]$action.human_action_result_path)
            }
        }
    }
}

function Validate-CommonPassCase {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $CaseMeta,
        $Evidence,
        [string]$EvidencePath
    )
    $caseId = [string]$CaseMeta.case_id
    if ($Evidence.runner_self_certified_pass -ne $false) {
        Add-Finding $Findings 'BLOCKED_RUNNER_SELF_PASS' $caseId 'Runner attempted to self-certify PASS.' $EvidencePath
    }
    $freshRootMarker = 'dev6.1.6_dynamic_app_web_full_access_rc_fresh'
    $oldRootMarker = 'dev6.1.6_dynamic_app_web_full_access_rc'
    if ($EvidencePath -notmatch [regex]::Escape($freshRootMarker) -or ($EvidencePath -match [regex]::Escape($oldRootMarker) -and $EvidencePath -notmatch [regex]::Escape($freshRootMarker))) {
        Add-Finding $Findings 'BLOCKED_STALE_EVIDENCE_USED' $caseId 'Evidence path is not from the fresh evidence directory.' $EvidencePath
    }
    if ($Evidence.fresh_run -ne $true -or $Evidence.stale_evidence_used -eq $true) {
        Add-Finding $Findings 'BLOCKED_STALE_EVIDENCE_USED' $caseId 'Evidence does not declare fresh_run=true and stale_evidence_used=false.' $EvidencePath
    }
    if ($Evidence.raw_status -ne 'RAW_COMPLETED_UNVERIFIED') {
        Add-CaseFailure $Findings $CaseMeta "Raw case did not complete: $($Evidence.raw_status)." $EvidencePath
        return
    }
    if ($Evidence.interaction_mode -ne 'mouse_first' -or $Evidence.mouse_first_required -ne $true -or $Evidence.mouse_first_passed -ne $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'mouse_first fields are not all valid.' $EvidencePath
    }
    if ([int]$Evidence.mouse_move_count -lt [int]$CaseMeta.min_mouse_clicks -or [int]$Evidence.mouse_click_count -lt [int]$CaseMeta.min_mouse_clicks) {
        Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'mouse_move_count or mouse_click_count is below the case minimum.' $EvidencePath
    }
    if ($Evidence.keyboard_only_path_used -eq $true) {
        Add-Finding $Findings 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' $caseId 'keyboard_only_path_used=true.' $EvidencePath
    }
    if ([int]$Evidence.wrong_field_input_count -ne 0) {
        Add-Finding $Findings 'BLOCKED_WRONG_FIELD_INPUT' $caseId 'wrong_field_input_count is not zero.' $EvidencePath
    }
    if ($Evidence.continued_action_after_wrong_context -eq $true) {
        Add-Finding $Findings 'BLOCKED_WRONG_FIELD_INPUT' $caseId 'continued_action_after_wrong_context=true.' $EvidencePath
    }
    if ($Evidence.coordinate_source_type -eq 'fixed_coordinate') {
        Add-Finding $Findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' $caseId 'Top-level coordinate_source_type is fixed_coordinate.' $EvidencePath
    }
    if (-not $Evidence.target_semantics_guard) {
        Add-TargetSemanticsFinding $Findings $caseId 'Top-level target_semantics_guard evidence is missing.' $EvidencePath
    }
    foreach ($field in @('clicked_target_text','clicked_target_normalized_text','clicked_target_role','clicked_target_rect','clicked_target_region','clicked_target_semantic_type')) {
        $value = Get-PropertyValue $Evidence $field
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            Add-Finding $Findings 'BLOCKED_MISSING_CLICKED_TARGET_EVIDENCE' $caseId "Top-level clicked target evidence field is missing: $field." $EvidencePath
        }
    }
    if ($Evidence.clicked_target_is_expected_target -ne $true -or $Evidence.clicked_target_is_forbidden_similar_target -eq $true) {
        Add-Finding $Findings 'BLOCKED_MOUSE_MISCLICK' $caseId 'Top-level clicked target was not expected or was forbidden similar target.' $EvidencePath
    }
    if ($Evidence.pre_click_semantic_verified -ne $true -or $Evidence.pre_click_role_verified -ne $true) {
        Add-Finding $Findings 'BLOCKED_MISSING_CLICKED_TARGET_EVIDENCE' $caseId 'Top-level pre-click semantic/role verification is missing.' $EvidencePath
    }
    if ($Evidence.post_action_causal_verified -ne $true) {
        Add-Finding $Findings 'BLOCKED_MISSING_POST_ACTION_CAUSAL_VERIFICATION' $caseId 'post_action_causal_verified is not true.' $EvidencePath
    }
    foreach ($field in @($CaseMeta.required_true)) {
        if (-not (Test-True $Evidence $field)) {
            Add-CaseFailure $Findings $CaseMeta "Required field is not true: $field." $EvidencePath
        }
    }
    Validate-MouseActions -Findings $Findings -CaseMeta $CaseMeta -Evidence $Evidence -EvidencePath $EvidencePath
}

function Validate-QqMailSendTarget {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $Evidence,
        [string]$EvidencePath
    )
    foreach ($field in @(
        'send_target_text',
        'send_target_role',
        'send_target_rect',
        'send_target_center',
        'send_target_region',
        'send_target_exact_match',
        'send_target_negative_match',
        'send_target_is_compose_action_area',
        'send_target_is_sidebar_or_folder',
        'send_target_unique',
        'send_target_verified_before_click',
        'clicked_target_text',
        'clicked_target_role',
        'clicked_target_rect',
        'clicked_target_is_sidebar_or_folder',
        'clicked_target_is_compose_send_button'
    )) {
        if ($Evidence.PSObject.Properties.Name -notcontains $field) {
            Add-QqMailWrongSendTarget $Findings "Missing QQ Mail send-target evidence field: $field." $EvidencePath
        }
    }
    if ([string]$Evidence.send_target_text -ne $QqText.Send) {
        Add-QqMailWrongSendTarget $Findings 'send_target_text is not exact send text.' $EvidencePath
    }
    if ([string]$Evidence.clicked_target_text -ne $QqText.Send) {
        Add-QqMailWrongSendTarget $Findings 'clicked_target_text is not exact send text.' $EvidencePath
    }
    if (Test-QqMailNegativeText ([string]$Evidence.clicked_target_text)) {
        Add-QqMailWrongSendTarget $Findings 'clicked_target_text is a sent-folder or other negative target.' $EvidencePath
    }
    if (Test-QqMailNegativeText ([string]$Evidence.send_target_text)) {
        Add-QqMailWrongSendTarget $Findings 'send_target_text is a sent-folder or other negative target.' $EvidencePath
    }
    if ($Evidence.send_target_exact_match -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'send_target_exact_match is not true.' $EvidencePath
    }
    if ($Evidence.send_target_negative_match -ne $false) {
        Add-QqMailWrongSendTarget $Findings 'send_target_negative_match is not false.' $EvidencePath
    }
    if ($Evidence.send_target_is_compose_action_area -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'send_target_is_compose_action_area is not true.' $EvidencePath
    }
    if ($Evidence.send_target_is_sidebar_or_folder -ne $false) {
        Add-QqMailWrongSendTarget $Findings 'send_target_is_sidebar_or_folder is not false.' $EvidencePath
    }
    if ($Evidence.clicked_target_is_sidebar_or_folder -ne $false) {
        Add-QqMailWrongSendTarget $Findings 'clicked_target_is_sidebar_or_folder is not false.' $EvidencePath
    }
    if ($Evidence.send_target_unique -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'send_target_unique is not true.' $EvidencePath
    }
    if ($Evidence.send_target_verified_before_click -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'send_target_verified_before_click is not true.' $EvidencePath
    }
    if ($Evidence.clicked_target_is_compose_send_button -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'clicked_target_is_compose_send_button is not true.' $EvidencePath
    }
    if ($Evidence.send_clicked_by_mouse -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'send_clicked_by_mouse is not true.' $EvidencePath
    }
    if ($Evidence.post_send_sent_folder_only -eq $true) {
        Add-QqMailWrongSendTarget $Findings 'post_send_sent_folder_only is true.' $EvidencePath
    }
    if ([string]::IsNullOrWhiteSpace([string]$Evidence.post_send_success_signal)) {
        Add-QqMailWrongSendTarget $Findings 'post_send_success_signal is missing.' $EvidencePath
    }
    if ($Evidence.send_success_verified -ne $true) {
        Add-QqMailWrongSendTarget $Findings 'send_success_verified is not true.' $EvidencePath
    }
}

function Validate-PyCharmRunShortcutException {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $Evidence,
        [string]$EvidencePath
    )
    foreach ($field in @(
        'run_icon_visual_target_limitation',
        'run_via_keyboard_shortcut',
        'run_keyboard_shortcut',
        'run_shortcut_sent',
        'vlm_or_visual_template_future_work',
        'output_current_run_verification_source'
    )) {
        if ($Evidence.PSObject.Properties.Name -notcontains $field) {
            Add-Finding $Findings 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED' 'case_2_pycharm_run' "Missing PyCharm keyboard-run exception evidence field: $field." $EvidencePath
        }
    }
    if ($Evidence.run_clicked_by_mouse -ne $false) {
        Add-Finding $Findings 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED' 'case_2_pycharm_run' 'PyCharm special case must not mark run_clicked_by_mouse=true.' $EvidencePath
    }
    if ([string]$Evidence.run_keyboard_shortcut -ne 'SHIFT+F10') {
        Add-Finding $Findings 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED' 'case_2_pycharm_run' 'PyCharm run_keyboard_shortcut is not SHIFT+F10.' $EvidencePath
    }
    if ([string]$Evidence.run_trigger_method -ne 'SHIFT+F10') {
        Add-Finding $Findings 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED' 'case_2_pycharm_run' 'PyCharm run_trigger_method is not SHIFT+F10.' $EvidencePath
    }
    if (-not (@($Evidence.keyboard_shortcut_used) -contains 'SHIFT+F10')) {
        Add-Finding $Findings 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED' 'case_2_pycharm_run' 'keyboard_shortcut_used does not include SHIFT+F10.' $EvidencePath
    }
    foreach ($action in @($Evidence.mouse_actions)) {
        if ([string]$action.step -eq 'click_pycharm_run') {
            Add-Finding $Findings 'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED' 'case_2_pycharm_run' 'PyCharm special case evidence still contains click_pycharm_run.' $EvidencePath
        }
    }
}

function Validate-PyCharmExecutionOutcome {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $Evidence,
        [string]$EvidencePath
    )
    foreach ($field in @(
        'execution_outcome',
        'execution_outcome_path',
        'execution_outcome_classifier_command',
        'execution_outcome_classifier_bottom_layer',
        'run_triggered',
        'execution_started',
        'execution_completed',
        'execution_success',
        'exit_code_present',
        'exit_code',
        'current_run_verified',
        'old_output_reuse_detected',
        'expected_output_verified'
    )) {
        if ($Evidence.PSObject.Properties.Name -notcontains $field) {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_EXECUTION_OUTCOME_MISSING' "Missing execution outcome evidence field: $field." $EvidencePath
        }
    }
    if (-not $Evidence.execution_outcome) {
        Add-ExecutionOutcomeFinding $Findings 'BLOCKED_EXECUTION_OUTCOME_MISSING' 'Case 2 evidence lacks execution_outcome from the bottom-layer classifier.' $EvidencePath
        return
    }
    if ([string]::IsNullOrWhiteSpace([string]$Evidence.execution_outcome_path) -or -not (Test-Path -LiteralPath ([string]$Evidence.execution_outcome_path))) {
        Add-ExecutionOutcomeFinding $Findings 'BLOCKED_EXECUTION_OUTCOME_MISSING' 'Execution outcome result JSON path is missing or not found.' $EvidencePath
    }
    if ($Evidence.execution_outcome_classifier_bottom_layer -ne $true -or [string]$Evidence.execution_outcome_classifier_command -ne 'winagent.exe classify-execution-output') {
        Add-ExecutionOutcomeFinding $Findings 'BLOCKED_RUNNER_ONLY_EXECUTION_CLASSIFIER' 'Execution outcome was not produced by the reusable winagent classifier command.' $EvidencePath
    }
    $outcome = $Evidence.execution_outcome
    foreach ($field in @(
        'run_triggered',
        'execution_started',
        'execution_completed',
        'execution_success',
        'exit_code_present',
        'exit_code',
        'runtime_command_observed',
        'runtime_command_text',
        'compiler_or_interpreter_observed',
        'error_detected',
        'error_category',
        'error_language_hint',
        'error_summary',
        'output_lines_observed',
        'expected_output_verified',
        'current_run_verified',
        'old_output_reuse_detected',
        'raw_output_excerpt',
        'classifier_profile',
        'classifier_confidence'
    )) {
        if ($outcome.PSObject.Properties.Name -notcontains $field) {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_EXECUTION_OUTCOME_MISSING' "Classifier output missing field: $field." $EvidencePath
        }
    }
    if ($outcome.run_triggered -ne $true) {
        Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Execution classifier did not verify run_triggered=true.' $EvidencePath
    }
    if ($outcome.run_triggered -eq $true -and $outcome.execution_success -ne $true) {
        if ([string]$outcome.error_category -eq 'SYNTAX_OR_INDENTATION_ERROR') {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_CODE_INPUT_INDENTATION_ERROR' 'Execution was triggered and completed, but Python failed with SYNTAX_OR_INDENTATION_ERROR.' $EvidencePath
        } else {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' "Execution was triggered but did not succeed. error_category=$($outcome.error_category)" $EvidencePath
        }
    }
    if ($outcome.execution_success -eq $true) {
        if ($outcome.exit_code_present -ne $true -or [int]$outcome.exit_code -ne 0) {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Successful execution lacks exit_code=0.' $EvidencePath
        }
        if ($outcome.expected_output_verified -ne $true) {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Successful execution lacks expected output verification.' $EvidencePath
        }
        if ($outcome.current_run_verified -ne $true -or $outcome.old_output_reuse_detected -eq $true) {
            Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Execution output was not verified as current run output.' $EvidencePath
        }
    }
    if ([string]$outcome.classifier_profile -ne 'python') {
        Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Execution classifier profile is not python.' $EvidencePath
    }
    if ($Evidence.run_triggered -ne $outcome.run_triggered -or $Evidence.execution_success -ne $outcome.execution_success) {
        Add-ExecutionOutcomeFinding $Findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Top-level Case 2 execution fields do not mirror classifier output.' $EvidencePath
    }
}

function Validate-CaseEvidence {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $CaseMeta,
        [string]$EvidencePath
    )
    if ([string]::IsNullOrWhiteSpace($EvidencePath) -or -not (Test-Path -LiteralPath $EvidencePath)) {
        Add-CaseFailure $Findings $CaseMeta 'Evidence JSON is missing.' $EvidencePath
        return [ordered]@{ status = 'NOT_RUN'; evidence_path = $EvidencePath; stop_code = 'EVIDENCE_MISSING'; failure_attribution = 'EVIDENCE_MISSING' }
    }
    $ev = Read-Json $EvidencePath
    if (-not $ev) {
        Add-CaseFailure $Findings $CaseMeta 'Evidence JSON is invalid.' $EvidencePath
        return [ordered]@{ status = 'FAIL'; evidence_path = $EvidencePath; stop_code = 'EVIDENCE_INVALID'; failure_attribution = 'EVIDENCE_INVALID' }
    }
    if ([string]$CaseMeta.case_id -eq 'case_1_qqmail_send' -and [string]$ev.raw_status -eq 'USER_CONFIRMED_CASE1_PASS_NO_RERUN') {
        if ($ev.fresh_run -eq $true -and $ev.stale_evidence_used -eq $false -and $ev.case1_single_rerun_skipped_by_user_instruction -eq $true) {
            return [ordered]@{ status = 'PASS'; evidence_path = $EvidencePath; stop_code = ''; failure_attribution = 'USER_CONFIRMED_CASE1_PASS_NO_RERUN'; evidence = $ev }
        }
        Add-Finding $Findings 'BLOCKED_STALE_EVIDENCE_USED' 'case_1_qqmail_send' 'Case 1 user-confirmed marker is not fresh or does not disclose no-rerun basis.' $EvidencePath
        return [ordered]@{ status = 'FAIL'; evidence_path = $EvidencePath; stop_code = 'BLOCKED_STALE_EVIDENCE_USED'; failure_attribution = 'CASE1_MARKER_INVALID'; evidence = $ev }
    }
    if ($ev.raw_status -in @('CREDENTIAL_REQUIRED_STOP','ACTIVE_PROTECTION_STOP')) {
        Add-CaseFailure $Findings $CaseMeta "Case stopped by policy: $($ev.raw_status)." $EvidencePath
        return [ordered]@{ status = 'BLOCKED'; evidence_path = $EvidencePath; stop_code = [string]$ev.raw_status; failure_attribution = [string]$ev.failure_attribution; evidence = $ev }
    }
    $beforeCount = $Findings.Count
    Validate-CommonPassCase -Findings $Findings -CaseMeta $CaseMeta -Evidence $ev -EvidencePath $EvidencePath
    if ([string]$CaseMeta.case_id -eq 'case_1_qqmail_send') {
        Validate-QqMailSendTarget -Findings $Findings -Evidence $ev -EvidencePath $EvidencePath
    }
    if ([string]$CaseMeta.case_id -eq 'case_2_pycharm_run') {
        Validate-PyCharmRunShortcutException -Findings $Findings -Evidence $ev -EvidencePath $EvidencePath
        Validate-PyCharmExecutionOutcome -Findings $Findings -Evidence $ev -EvidencePath $EvidencePath
    }
    if ([string]$CaseMeta.case_id -eq 'case_4_tiktok_search') {
        if ([string]$ev.query_text_exact -ne 'Donauld Trump') {
            Add-Finding $Findings 'BLOCKED_TIKTOK_FULL_ACCESS_CASE_FAILED' 'case_4_tiktok_search' 'query_text_exact is not Donauld Trump.' $EvidencePath
        }
    }
    if ($Findings.Count -eq $beforeCount) {
        return [ordered]@{ status = 'PASS'; evidence_path = $EvidencePath; stop_code = ''; failure_attribution = 'NONE'; evidence = $ev }
    }
    return [ordered]@{ status = 'FAIL'; evidence_path = $EvidencePath; stop_code = [string]$ev.final_stop_code; failure_attribution = [string]$ev.failure_attribution; evidence = $ev }
}

function Write-CaseReport {
    param(
        $CaseMeta,
        $CaseResult,
        [string]$Path
    )
    $ev = $CaseResult.evidence
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $($CaseMeta.case_name)") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("- Case ID: $($CaseMeta.case_id)") | Out-Null
    $lines.Add("- Status: $($CaseResult.status)") | Out-Null
    $lines.Add("- Evidence: $($CaseResult.evidence_path)") | Out-Null
    $lines.Add("- Stop code: $($CaseResult.stop_code)") | Out-Null
    $lines.Add("- Failure attribution: $($CaseResult.failure_attribution)") | Out-Null
    if ($ev) {
        $lines.Add("- mouse_move_count: $($ev.mouse_move_count)") | Out-Null
        $lines.Add("- mouse_click_count: $($ev.mouse_click_count)") | Out-Null
        $lines.Add("- keyboard_shortcut_used: $((@($ev.keyboard_shortcut_used) -join ', '))") | Out-Null
        $lines.Add("- fallback_used: $($ev.fallback_used)") | Out-Null
        $lines.Add("- fallback_reason: $($ev.fallback_reason)") | Out-Null
        $lines.Add("- coordinate_source_type: $($ev.coordinate_source_type)") | Out-Null
        $lines.Add("- wrong_field_input_count: $($ev.wrong_field_input_count)") | Out-Null
        $lines.Add("- continued_action_after_wrong_context: $($ev.continued_action_after_wrong_context)") | Out-Null
        $lines.Add('') | Out-Null
        $lines.Add('## Required Fields') | Out-Null
        foreach ($field in @($CaseMeta.required_true)) {
            $lines.Add("- ${field}: $(Get-PropertyValue $ev $field)") | Out-Null
        }
        if ([string]$CaseMeta.case_id -eq 'case_1_qqmail_send') {
            $lines.Add('') | Out-Null
            $lines.Add('## QQ Mail Send Target Evidence') | Out-Null
            foreach ($field in @(
                'send_target_text',
                'send_target_role',
                'send_target_region',
                'send_target_exact_match',
                'send_target_negative_match',
                'send_target_is_compose_action_area',
                'send_target_is_sidebar_or_folder',
                'send_target_unique',
                'send_target_verified_before_click',
                'clicked_target_text',
                'clicked_target_role',
                'clicked_target_is_sidebar_or_folder',
                'clicked_target_is_compose_send_button',
                'post_send_verification_source',
                'post_send_success_signal',
                'post_send_sent_folder_only'
            )) {
                $lines.Add("- ${field}: $(Get-PropertyValue $ev $field)") | Out-Null
            }
        }
        if ([string]$CaseMeta.case_id -eq 'case_2_pycharm_run') {
            $lines.Add('') | Out-Null
            $lines.Add('## PyCharm Execution Outcome') | Out-Null
            foreach ($field in @(
                'run_triggered',
                'execution_started',
                'execution_completed',
                'execution_success',
                'exit_code',
                'current_run_verified',
                'old_output_reuse_detected',
                'expected_output_verified',
                'error_category',
                'error_summary',
                'execution_outcome_path',
                'execution_outcome_classifier_command',
                'run_trigger_method',
                'run_id'
            )) {
                $lines.Add("- ${field}: $(Get-PropertyValue $ev $field)") | Out-Null
            }
        }
    }
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Validate-QqMailNegativeCase {
    param(
        [System.Collections.Generic.List[object]]$Findings
    )
    $caseId = 'qqmail_sent_folder_false_positive_negative'
    $path = Join-Path (Join-Path $NegativeRoot $caseId) 'evidence.json'
    $status = 'FAIL'
    $message = ''
    $ev = Read-Json $path
    if (-not $ev) {
        $message = 'Negative case evidence is missing.'
        Add-Finding $Findings 'BLOCKED_QQMAIL_WRONG_SEND_TARGET' $caseId $message $path
    } elseif (
        $ev.raw_status -eq 'STOP_TARGET_SEMANTIC_MISMATCH' -and
        $ev.send_clicked_by_mouse -eq $false -and
        $ev.send_target_negative_match -eq $true -and
        $ev.send_target_is_sidebar_or_folder -eq $true -and
        $ev.clicked_target_is_compose_send_button -eq $false
    ) {
        $status = 'PASS'
        $message = 'Sent-folder candidate was rejected before click.'
    } else {
        $message = 'Negative case did not prove sent-folder rejection.'
        Add-Finding $Findings 'BLOCKED_QQMAIL_WRONG_SEND_TARGET' $caseId $message $path
    }
    $reportPath = Join-Path $ArtifactRoot 'qqmail_sent_folder_false_positive_negative_report.md'
    @(
        '# QQ Mail Sent Folder False Positive Negative',
        '',
        "- Status: $status",
        "- Evidence: $path",
        "- Message: $message",
        "- Expected stop code: STOP_TARGET_SEMANTIC_MISMATCH",
        "- Observed stop code: $(if ($ev) { $ev.raw_status } else { 'MISSING' })",
        "- send_clicked_by_mouse: $(if ($ev) { $ev.send_clicked_by_mouse } else { 'MISSING' })",
        "- send_target_text: $(if ($ev) { $ev.send_target_text } else { 'MISSING' })",
        "- send_target_is_sidebar_or_folder: $(if ($ev) { $ev.send_target_is_sidebar_or_folder } else { 'MISSING' })",
        "- clicked_target_is_compose_send_button: $(if ($ev) { $ev.clicked_target_is_compose_send_button } else { 'MISSING' })"
    ) | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return [ordered]@{
        case_id = $caseId
        status = $status
        evidence_path = $path
        report_path = $reportPath
        message = $message
    }
}

function Validate-IntegratedSequence {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        $SingleCaseResults
    )
    $summaryPath = Join-Path $IntegratedRoot 'latest_integrated_sequence_summary.json'
    $summary = Read-Json $summaryPath
    $allSinglesPass = $true
    foreach ($case in $Cases) {
        if ($SingleCaseResults[[string]$case.case_id].status -ne 'PASS') { $allSinglesPass = $false }
    }
    if (-not $allSinglesPass) {
        return [ordered]@{
            status = 'NOT_RUN'
            summary_path = $summaryPath
            reason = 'Integrated sequence is not evaluated until all four single cases PASS and freeze.'
            cases = @()
        }
    }
    if (-not $summary -or $summary.runner_status -ne 'RAW_COMPLETED_UNVERIFIED') {
        Add-Finding $Findings 'BLOCKED_INTEGRATED_SEQUENCE_FAILED' 'integrated_sequence' 'Integrated sequence raw summary is missing or was not run.' $summaryPath
        return [ordered]@{ status = 'FAIL'; summary_path = $summaryPath; reason = 'MISSING_OR_NOT_RUN'; cases = @() }
    }
    $integratedResults = New-Object System.Collections.Generic.List[object]
    foreach ($caseMeta in $Cases) {
        $entries = @($summary.cases | Where-Object { $_.case_id -eq $caseMeta.case_id } | Select-Object -First 1)
        $entry = if ($entries.Count -gt 0) { $entries[0] } else { $null }
        if (-not $entry) {
            Add-Finding $Findings 'BLOCKED_INTEGRATED_SEQUENCE_FAILED' ([string]$caseMeta.case_id) 'Case is missing from integrated sequence summary.' $summaryPath
            continue
        }
        $result = Validate-CaseEvidence -Findings $Findings -CaseMeta $caseMeta -EvidencePath ([string]$entry.evidence_path)
        $integratedResults.Add($result) | Out-Null
    }
    $ok = $true
    foreach ($result in @($integratedResults.ToArray())) {
        if ($result.status -ne 'PASS') { $ok = $false }
    }
    return [ordered]@{
        status = if ($ok) { 'PASS' } else { 'FAIL' }
        summary_path = $summaryPath
        sequence_root = [string]$summary.sequence_root
        cases = @($integratedResults.ToArray())
    }
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $RawRoot
Ensure-Dir $VerifiedRoot
Ensure-Dir $NegativeRoot
Initialize-Registry

$findings = New-Object System.Collections.Generic.List[object]
$registry = Read-RegistryMap
$caseResults = @{}
$negativeResult = Validate-QqMailNegativeCase -Findings $findings

foreach ($caseMeta in $Cases) {
    $caseId = [string]$caseMeta.case_id
    $path = Get-CaseEvidencePath $registry $caseId
    $result = Validate-CaseEvidence -Findings $findings -CaseMeta $caseMeta -EvidencePath $path
    $caseResults[$caseId] = $result

    $row = $registry[$caseId]
    if ($result.status -eq 'PASS') {
        $row.status = 'pass'
        $row.last_pass_evidence_path = [string]$result.evidence_path
        $row.frozen_after_pass = $true
        $row.rerun_required = $false
    } elseif ($result.status -eq 'NOT_RUN') {
        if ($row.status -eq 'pending' -or [string]::IsNullOrWhiteSpace([string]$row.status)) {
            $row.status = 'pending'
        }
    } else {
        $row.status = 'blocked'
        $row.last_failure_evidence_path = [string]$result.evidence_path
        $row.frozen_after_pass = $false
        $row.rerun_required = $true
    }
    $row.last_run_timestamp = (Get-Date).ToString('o')
    Write-CaseReport -CaseMeta $caseMeta -CaseResult $result -Path (Join-Path $ArtifactRoot ([string]$caseMeta.report))
}
Save-RegistryMap $registry

$integrated = Validate-IntegratedSequence -Findings $findings -SingleCaseResults $caseResults

$caseResultRows = foreach ($caseMeta in $Cases) {
    $caseId = [string]$caseMeta.case_id
    [ordered]@{
        case_id = $caseId
        case_name = [string]$caseMeta.case_name
        status = [string]$caseResults[$caseId].status
        evidence_path = [string]$caseResults[$caseId].evidence_path
        stop_code = [string]$caseResults[$caseId].stop_code
        failure_attribution = [string]$caseResults[$caseId].failure_attribution
    }
}

$passCount = @($caseResultRows | Where-Object { $_.status -eq 'PASS' }).Count
$status = if ($findings.Count -eq 0 -and $passCount -eq 4 -and $integrated.status -eq 'PASS') { 'PASS' } else { 'BLOCKED' }

$result = [ordered]@{
    schema_version = 'v6.1.6.dynamic_app_web_full_access.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    single_case_pass_count = $passCount
    required_single_case_count = 4
    integrated_sequence_status = [string]$integrated.status
    case_results = @($caseResultRows)
    negative_cases = @($negativeResult)
    integrated_sequence = $integrated
    findings = @($findings.ToArray())
    registry_path = $RegistryPath
}
$verifierJson = Join-Path $VerifiedRoot 'v6_1_6_verifier_result.json'
Save-Json $result $verifierJson

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1}: {2} `{3}`' -f $_.code, $_.case_id, $_.message, $_.path
}
if ($findingRows.Count -eq 0) { $findingRows = @('- No blocking findings.') }

@(
    '# v6.1.6 Dynamic App/Web Full Access Verifier',
    '',
    "- Result: $status",
    "- Single case PASS count: $passCount / 4",
    "- QQ Mail sent-folder negative: $($negativeResult.status)",
    "- Integrated sequence: $($integrated.status)",
    "- Result JSON: $verifierJson",
    '',
    '## Findings'
) + $findingRows | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'verifier_report.md') -Encoding UTF8

$mouseLines = New-Object System.Collections.Generic.List[string]
$mouseLines.Add('# v6.1.6 Mouse Evidence Report') | Out-Null
$mouseLines.Add('') | Out-Null
foreach ($caseMeta in $Cases) {
    $caseId = [string]$caseMeta.case_id
    $ev = $caseResults[$caseId].evidence
    if (-not $ev) {
        $mouseLines.Add("- ${caseId}: no evidence") | Out-Null
        continue
    }
    $fixed = @($ev.mouse_actions | Where-Object { $_.coordinate_source_type -eq 'fixed_coordinate' }).Count
    $fallback = @($ev.mouse_actions | Where-Object { $_.coordinate_source_type -eq 'fallback_coordinate' }).Count
    $mouseLines.Add("- ${caseId}: status=$($caseResults[$caseId].status), moves=$($ev.mouse_move_count), clicks=$($ev.mouse_click_count), fixed=$fixed, fallback_coords=$fallback, fallback_used=$($ev.fallback_used)") | Out-Null
}
$mouseLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mouse_evidence_report.md') -Encoding UTF8

$failureLines = New-Object System.Collections.Generic.List[string]
$failureLines.Add('# v6.1.6 Failure Attribution Report') | Out-Null
$failureLines.Add('') | Out-Null
foreach ($caseMeta in $Cases) {
    $caseId = [string]$caseMeta.case_id
    $failureLines.Add("- ${caseId}: status=$($caseResults[$caseId].status), stop_code=$($caseResults[$caseId].stop_code), attribution=$($caseResults[$caseId].failure_attribution)") | Out-Null
}
$failureLines.Add("- integrated_sequence: status=$($integrated.status)") | Out-Null
$failureLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'failure_attribution_report.md') -Encoding UTF8

@(
    '# v6.1.6 Integrated Sequence Report',
    '',
    "- Status: $($integrated.status)",
    "- Summary: $($integrated.summary_path)",
    "- Reason: $($integrated.reason)",
    "- Sequence root: $($integrated.sequence_root)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'integrated_sequence_report.md') -Encoding UTF8

$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add('# v6.1.6 Evidence Index') | Out-Null
$indexLines.Add('') | Out-Null
$indexLines.Add("- Agent context digest: $(Join-Path $ArtifactRoot 'agent_context_digest.md')") | Out-Null
$indexLines.Add("- Case status registry: $RegistryPath") | Out-Null
$indexLines.Add("- Verifier result: $verifierJson") | Out-Null
$indexLines.Add("- Verifier report: $(Join-Path $ArtifactRoot 'verifier_report.md')") | Out-Null
$indexLines.Add("- Mouse evidence report: $(Join-Path $ArtifactRoot 'mouse_evidence_report.md')") | Out-Null
$indexLines.Add("- Failure attribution report: $(Join-Path $ArtifactRoot 'failure_attribution_report.md')") | Out-Null
$indexLines.Add("- Integrated sequence report: $(Join-Path $ArtifactRoot 'integrated_sequence_report.md')") | Out-Null
foreach ($caseMeta in $Cases) {
    $caseId = [string]$caseMeta.case_id
    $indexLines.Add("- ${caseId} report: $(Join-Path $ArtifactRoot ([string]$caseMeta.report))") | Out-Null
    $indexLines.Add("- ${caseId} evidence: $($caseResults[$caseId].evidence_path)") | Out-Null
}
$indexLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

if ($status -eq 'PASS') {
    Write-Host 'VERIFIER_PASS'
    exit 0
}
Write-Host 'VERIFIER_BLOCKED'
exit 1

