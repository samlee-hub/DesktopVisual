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
$RawCasesRoot = Join-Path $RawRoot 'cases'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$VerifiedCasesRoot = Join-Path $VerifiedRoot 'cases'

$CaseExpectations = if ($StateGuardOnly) {
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

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Clear-CaseDir([string]$Path, [string]$AllowedRoot) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullAllowed = [System.IO.Path]::GetFullPath($AllowedRoot)
    if (-not $fullPath.StartsWith($fullAllowed, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear verified case path outside verified cases root: $fullPath"
    }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    Ensure-Dir $Path
}

function Write-JsonLine([string]$Path, $Object) {
    ($Object | ConvertTo-Json -Depth 100 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Read-Jsonl([string]$Path) {
    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $items.Add(($line | ConvertFrom-Json)) | Out-Null } catch { $items.Add([pscustomobject]@{ parse_error = $_.Exception.Message; raw = $line }) | Out-Null }
    }
    @($items.ToArray())
}

function Copy-IfExists([string]$Src, [string]$Dst) {
    if (Test-Path -LiteralPath $Src) { Copy-Item -LiteralPath $Src -Destination $Dst -Force }
}

function Copy-VisualEvidence([string]$RawCaseDir, [string]$CaseDir) {
    foreach ($name in @('screenshots','overlays','crops')) {
        $dst = Join-Path $CaseDir $name
        Ensure-Dir $dst
        $src = Join-Path $RawCaseDir $name
        if (Test-Path -LiteralPath $src) {
            Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dst $_.Name) -Force
            }
        }
    }
}

function Scan-RawText([string]$RawCaseDir, [string]$Pattern) {
    $text = ''
    if (Test-Path -LiteralPath $RawCaseDir) {
        Get-ChildItem -LiteralPath $RawCaseDir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(log|json|jsonl|md|txt)$' } |
            ForEach-Object { $text += "`n" + (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) }
    }
    return ($text -match $Pattern)
}

function Count-RawPattern([string]$RawCaseDir, [string]$Pattern) {
    if (Scan-RawText $RawCaseDir $Pattern) { return 1 }
    return 0
}

function Sum-JsonlInt([object[]]$Rows, [string]$Path, [string]$Name) {
    $sum = 0
    foreach ($row in $Rows) {
        $value = $row
        foreach ($part in $Path.Split('.')) {
            if ($null -eq $value) { break }
            $value = $value.$part
        }
        if ($null -ne $value -and $value.$Name -ne $null) {
            try { $sum += [int]$value.$Name } catch {}
        }
    }
    return $sum
}

function Test-PropertyPresent($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if (-not ($Object.PSObject.Properties.Name -contains $Name)) { return $false }
    return ($null -ne $Object.$Name)
}

function Count-MissingRequiredFields([object[]]$Rows, [string[]]$Fields) {
    $missing = 0
    foreach ($row in $Rows) {
        foreach ($field in $Fields) {
            if (-not (Test-PropertyPresent $row $field)) { $missing++ }
        }
    }
    return $missing
}

function Count-MissingEvidenceFiles([object[]]$Rows, [string[]]$Fields) {
    $missing = 0
    foreach ($row in $Rows) {
        foreach ($field in $Fields) {
            if (-not (Test-PropertyPresent $row $field) -or [string]::IsNullOrWhiteSpace([string]$row.$field) -or -not (Test-Path -LiteralPath ([string]$row.$field))) {
                $missing++
            }
        }
    }
    return $missing
}

function Get-MaxHeartbeatGapSec([object[]]$HeartbeatRows) {
    $times = @($HeartbeatRows | Where-Object { $_.timestamp } | ForEach-Object {
        try { [datetime]$_.timestamp } catch { $null }
    } | Where-Object { $_ -ne $null } | Sort-Object)
    if ($times.Count -lt 2) { return 0 }
    $max = 0
    for ($i = 1; $i -lt $times.Count; $i++) {
        $gap = ($times[$i] - $times[$i - 1]).TotalSeconds
        if ($gap -gt $max) { $max = $gap }
    }
    return [Math]::Round($max, 3)
}

function New-TaskResultBase([string]$CaseId, $Status, [string]$RawCaseDir) {
    $commands = Read-Jsonl (Join-Path $RawCaseDir 'raw_command_log.jsonl')
    $offsetRows = Read-Jsonl (Join-Path $RawCaseDir 'offset_trace.jsonl')
    $focusRows = Read-Jsonl (Join-Path $RawCaseDir 'focus_trace.jsonl')
    $contextRows = Read-Jsonl (Join-Path $RawCaseDir 'context_trace.jsonl')
    $heartbeatRows = Read-Jsonl (Join-Path $RawCaseDir 'heartbeat.jsonl')
    $validCommands = @($commands | Where-Object { $_ -ne $null -and -not $_.parse_error })
    $firstSuccess = @($offsetRows | Where-Object { $_.first_attempt_success -eq $true }).Count
    $firstFailure = @($offsetRows | Where-Object { $_.first_attempt_success -eq $false }).Count
    $actionCount = $firstSuccess + $firstFailure
    $rate = if ($actionCount -gt 0) { [Math]::Round($firstSuccess / [double]$actionCount, 4) } else { 0.0 }
    $outside = @($offsetRows | Where-Object { $_.cursor_inside_target_rect_before_click -ne $true -and $_.click_result -eq $true }).Count
    $mouseOffsets = @($offsetRows | Where-Object { $_.mouse_offset_px -ne $null } | ForEach-Object { [double]$_.mouse_offset_px })
    $offsetMax = if ($mouseOffsets.Count -gt 0) { ($mouseOffsets | Measure-Object -Maximum).Maximum } else { 0 }
    $offsetAvg = if ($mouseOffsets.Count -gt 0) { [Math]::Round(($mouseOffsets | Measure-Object -Average).Average, 2) } else { 0 }
    $offsetRequired = @('target_rect','target_rect_source','intended_click_point','cursor_before_move','cursor_after_move','cursor_before_click','cursor_after_click','cursor_inside_target_rect_before_click','mouse_offset_px','coordinate_mapping_error_px','screenshot_before','screenshot_after','overlay_before_click','overlay_after_click','foreground_hwnd_before','foreground_hwnd_after','window_rect','client_rect','viewport_rect','target_stale_before_click','click_result','retry_count','reobserve_count','first_attempt_success')
    $focusRequired = @('expected_field','focused_element_before_type','focused_element_after_click','typed_text','verified_text','text_verified','wrong_field_input','keyboard_focus_lost','screenshot_before_type','screenshot_after_type')
    $typedRows = @($focusRows | Where-Object { $_.typing_started -eq $true })
    $staleClicked = @($offsetRows | Where-Object { $_.target_stale_before_click -eq $true -and $_.stale_target_prevented_click -ne $true }).Count
    $wrongFieldFromTrace = @($typedRows | Where-Object { $_.wrong_field_input -eq $true }).Count
    $focusLossFromTrace = @($typedRows | Where-Object { $_.keyboard_focus_lost -eq $true }).Count
    $textUnverified = @($typedRows | Where-Object { $_.text_verified -ne $true }).Count
    $wrongContextStops = @($contextRows | Where-Object { $_.ok -eq $false -and [string]$_.stop_code -match '^STOP_' }).Count
    $continuedAfterWrongContext = if ($Status -and $Status.continued_action_after_wrong_context -ne $null) { [bool]$Status.continued_action_after_wrong_context } else { $false }
    $timedOutCommands = @($validCommands | Where-Object { $_.timed_out -eq $true }).Count
    $stepTimeoutMissing = @($validCommands | Where-Object { $_.timeout_sec -eq $null }).Count
    $statusWrongField = if ($Status -and $Status.wrong_field_input_count -ne $null) { [int]$Status.wrong_field_input_count } else { 0 }
    $statusRetry = if ($Status -and $Status.retry_count -ne $null) { [int]$Status.retry_count } else { 0 }
    $statusReobserve = if ($Status -and $Status.reobserve_count -ne $null) { [int]$Status.reobserve_count } else { 0 }
    $traceRetry = (($offsetRows | ForEach-Object { if ($_.retry_count -ne $null) { [int]$_.retry_count } else { 0 } }) | Measure-Object -Sum).Sum
    $traceReobserve = (($offsetRows | ForEach-Object { if ($_.reobserve_count -ne $null) { [int]$_.reobserve_count } else { 0 } }) | Measure-Object -Sum).Sum
    if ($null -eq $traceRetry) { $traceRetry = 0 }
    if ($null -eq $traceReobserve) { $traceReobserve = 0 }
    [ordered]@{
        case_id = $CaseId
        actual_result = if ($Status -and $Status.runner_outcome) { [string]$Status.runner_outcome } else { 'NOT_RUN' }
        verification_passed = $false
        raw_command_evidence_verified = (($validCommands.Count -gt 0) -and (@($validCommands | Where-Object { -not $_.stdout_path -or -not (Test-Path -LiteralPath $_.stdout_path) }).Count -eq 0))
        heartbeat_present = ($heartbeatRows.Count -gt 0)
        heartbeat_max_gap_sec = Get-MaxHeartbeatGapSec $heartbeatRows
        heartbeat_interval_sec = 15
        no_progress_timeout_enforced = ($heartbeatRows.Count -gt 0 -and (@($heartbeatRows | Where-Object { $_.waiting_reason -match 'no_progress|timeout|running_command|case_started|case_finished' }).Count -gt 0))
        step_timeout_sec = 60
        command_timeout_missing_count = $stepTimeoutMissing
        command_timeout_triggered_count = $timedOutCommands
        synthetic_evidence_detected = (Scan-RawText $RawCaseDir 'synthetic PASS|fake dynamic UI evidence|generated-only PASS')
        placeholder_screenshot_detected = (Scan-RawText $RawCaseDir 'placeholder screenshot')
        hardcoded_rect_detected = (Scan-RawText $RawCaseDir 'hardcoded_rect|manual_fixed')
        hardcoded_hwnd_detected = (Scan-RawText $RawCaseDir '--hwnd|hardcoded_hwnd')
        backend_action_count = Count-RawPattern $RawCaseDir 'Start-Process|ShellExecute|backend_action\":true'
        js_dom_action_count = Count-RawPattern $RawCaseDir 'document\.|querySelector|scrollIntoView|DOM click|DOM set value|JS action'
        webdriver_count = Count-RawPattern $RawCaseDir 'WebDriver|webdriver'
        cdp_count = Count-RawPattern $RawCaseDir 'CDP|Input\.dispatch|Chrome DevTools Protocol'
        playwright_count = Count-RawPattern $RawCaseDir 'Playwright'
        selenium_count = Count-RawPattern $RawCaseDir 'Selenium'
        uia_invoke_action_count = Count-RawPattern $RawCaseDir 'invoke_pattern|InvokePattern'
        uia_value_action_count = Count-RawPattern $RawCaseDir 'value_pattern|ValuePattern'
        direct_file_write_count = if ($Status -and $Status.direct_file_write_count -ne $null) { [int]$Status.direct_file_write_count } else { 0 }
        backend_execution_count = if ($Status -and $Status.backend_execution_count -ne $null) { [int]$Status.backend_execution_count } else { 0 }
        desktop_app_double_click_used = if ($Status -and $Status.desktop_app_double_click_used -ne $null) { [bool]$Status.desktop_app_double_click_used } else { $false }
        app_opened_by_user_level_mouse = if ($Status -and $Status.app_opened_by_user_level_mouse -ne $null) { [bool]$Status.app_opened_by_user_level_mouse } else { $false }
        browser_opened_by_desktop_double_click = if ($Status -and $Status.browser_opened_by_desktop_double_click -ne $null) { [bool]$Status.browser_opened_by_desktop_double_click } else { $false }
        target_rect_missing_count = @($offsetRows | Where-Object { -not $_.target_rect }).Count
        required_offset_field_missing_count = Count-MissingRequiredFields $offsetRows $offsetRequired
        visual_evidence_missing_count = Count-MissingEvidenceFiles $offsetRows @('screenshot_before','screenshot_after','overlay_before_click','overlay_after_click')
        required_focus_field_missing_count = Count-MissingRequiredFields $typedRows $focusRequired
        text_unverified_count = $textUnverified
        cursor_outside_target_rect_count = $outside
        wrong_target_click_count = if ($Status -and $Status.wrong_target_click_count -ne $null) { [int]$Status.wrong_target_click_count } else { 0 }
        wrong_field_input_count = ($statusWrongField + $wrongFieldFromTrace)
        keyboard_focus_loss_count = $focusLossFromTrace
        misclick_count = if ($outside -gt 0) { $outside } else { 0 }
        stale_target_rect_count = if ($Status -and $Status.stale_target_rect_count -ne $null) { [int]$Status.stale_target_rect_count } else { 0 }
        stale_target_clicked_count = $staleClicked
        wrong_page_navigation_count = if ($Status -and $Status.wrong_page_navigation_count -ne $null) { [int]$Status.wrong_page_navigation_count } else { 0 }
        context_trace_present = ($contextRows.Count -gt 0)
        action_precondition_count = $contextRows.Count
        wrong_context_stop_count = $wrongContextStops
        wrong_context_detected = if ($Status -and $Status.wrong_context_detected -ne $null) { [bool]$Status.wrong_context_detected } else { ($wrongContextStops -gt 0) }
        stopped_before_click = if ($Status -and $Status.stopped_before_click -ne $null) { [bool]$Status.stopped_before_click } else { $false }
        stopped_before_type = if ($Status -and $Status.stopped_before_type -ne $null) { [bool]$Status.stopped_before_type } else { $false }
        stopped_before_send = if ($Status -and $Status.stopped_before_send -ne $null) { [bool]$Status.stopped_before_send } else { $false }
        continued_action_after_wrong_context = $continuedAfterWrongContext
        google_search_continued_click_count = if ($Status -and $Status.google_search_continued_click_count -ne $null) { [int]$Status.google_search_continued_click_count } else { 0 }
        retry_count = ($statusRetry + $traceRetry)
        reobserve_count = ($statusReobserve + $traceReobserve)
        first_attempt_success_count = $firstSuccess
        first_attempt_failure_count = $firstFailure
        first_attempt_success_rate = $rate
        screenshot_recovery_count = if ($Status -and $Status.screenshot_recovery_count -ne $null) { [int]$Status.screenshot_recovery_count } else { 0 }
        recovery_success_count = if ($Status -and $Status.recovery_success_count -ne $null) { [int]$Status.recovery_success_count } else { 0 }
        mouse_offset_max_px = $offsetMax
        mouse_offset_avg_px = $offsetAvg
        coordinate_mapping_error_max_px = $offsetMax
        coordinate_mapping_error_avg_px = $offsetAvg
        vlm_call_count = Count-RawPattern $RawCaseDir 'VLM API|"vlm_call"|openai_api|OpenAI API|provider":"openai|openai_request|openai_response'
        active_protection_bypass_attempt_count = Count-RawPattern $RawCaseDir 'bypass captcha|avoid bot detection|disable anti cheat|hide automation'
        emergency_stop_triggered = if ($Status -and $Status.emergency_stop_triggered -ne $null) { [bool]$Status.emergency_stop_triggered } else { $false }
        false_positive_stop_detected = if ($Status -and $Status.false_positive_stop_detected -ne $null) { [bool]$Status.false_positive_stop_detected } else { $false }
        final_failure_reason = if ($Status -and $Status.stop_reason) { [string]$Status.stop_reason } else { '' }
    }
}

function Test-StrictCommon($Result) {
    return (
        $Result.raw_command_evidence_verified -eq $true -and
        $Result.heartbeat_present -eq $true -and
        [double]$Result.heartbeat_max_gap_sec -le 20 -and
        $Result.no_progress_timeout_enforced -eq $true -and
        [int]$Result.command_timeout_missing_count -eq 0 -and
        [int]$Result.command_timeout_triggered_count -eq 0 -and
        $Result.synthetic_evidence_detected -eq $false -and
        $Result.placeholder_screenshot_detected -eq $false -and
        $Result.hardcoded_rect_detected -eq $false -and
        $Result.hardcoded_hwnd_detected -eq $false -and
        [int]$Result.backend_action_count -eq 0 -and
        [int]$Result.js_dom_action_count -eq 0 -and
        [int]$Result.webdriver_count -eq 0 -and
        [int]$Result.cdp_count -eq 0 -and
        [int]$Result.playwright_count -eq 0 -and
        [int]$Result.selenium_count -eq 0 -and
        [int]$Result.uia_invoke_action_count -eq 0 -and
        [int]$Result.uia_value_action_count -eq 0 -and
        [int]$Result.required_offset_field_missing_count -eq 0 -and
        [int]$Result.visual_evidence_missing_count -eq 0 -and
        [int]$Result.required_focus_field_missing_count -eq 0 -and
        [int]$Result.text_unverified_count -eq 0 -and
        [int]$Result.cursor_outside_target_rect_count -eq 0 -and
        [int]$Result.wrong_target_click_count -eq 0 -and
        [int]$Result.wrong_field_input_count -eq 0 -and
        [int]$Result.misclick_count -eq 0 -and
        [int]$Result.stale_target_clicked_count -eq 0 -and
        [int]$Result.vlm_call_count -eq 0 -and
        [int]$Result.active_protection_bypass_attempt_count -eq 0 -and
        $Result.emergency_stop_triggered -eq $false -and
        $Result.false_positive_stop_detected -eq $false -and
        [double]$Result.first_attempt_success_rate -ge 0.80
    )
}

function Verify-PyCharm($Status, $Result) {
    $Result.pycharm_foreground_verified = if ($Status -and $Status.pycharm_foreground_verified -ne $null) { [bool]$Status.pycharm_foreground_verified } else { $false }
    $Result.editor_focus_verified = if ($Status -and $Status.editor_focus_verified -ne $null) { [bool]$Status.editor_focus_verified } else { $false }
    $Result.code_typed_by_humanmode = if ($Status -and $Status.code_typed_by_humanmode -ne $null) { [bool]$Status.code_typed_by_humanmode } else { $false }
    $Result.run_triggered_from_pycharm_ui = if ($Status -and $Status.run_triggered_from_pycharm_ui -ne $null) { [bool]$Status.run_triggered_from_pycharm_ui } else { $false }
    $Result.console_output_verified = if ($Status -and $Status.console_output_verified_by_runner -ne $null) { [bool]$Status.console_output_verified_by_runner } else { $false }
    $Result.expected_output_lines_verified = if ($Status -and $Status.expected_output_lines_seen_by_runner -ne $null) { [int]$Status.expected_output_lines_seen_by_runner } else { 0 }
    $Result.wrong_file_input_count = if ($Status -and $Status.wrong_file_input_count -ne $null) { [int]$Status.wrong_file_input_count } else { 0 }
    if ((Test-StrictCommon $Result) -and $Status.runner_outcome -eq 'RAW_COMPLETED_UNVERIFIED' -and
        $Result.desktop_app_double_click_used -and $Result.app_opened_by_user_level_mouse -and
        $Result.pycharm_foreground_verified -and $Result.editor_focus_verified -and $Result.code_typed_by_humanmode -and
        [int]$Result.direct_file_write_count -eq 0 -and [int]$Result.backend_execution_count -eq 0 -and
        $Result.run_triggered_from_pycharm_ui -and $Result.console_output_verified -and
        [int]$Result.expected_output_lines_verified -eq 10 -and [int]$Result.wrong_file_input_count -eq 0) {
        $Result.actual_result = 'STRICT_DYNAMIC_APP_PYCHARM_PASS'
        $Result.verification_passed = $true
    }
}

function Verify-WeChat($Status, $Result) {
    $Result.wechat_foreground_verified = if ($Status -and $Status.wechat_foreground_verified -ne $null) { [bool]$Status.wechat_foreground_verified } else { $false }
    $Result.target_contact = if ($Status -and $Status.target_contact) { [string]$Status.target_contact } else { '' }
    $Result.target_contact_verified_before_click = if ($Status -and $Status.target_contact_verified_before_click -ne $null) { [bool]$Status.target_contact_verified_before_click } else { $false }
    $Result.wheel_scroll_used_for_friend_list = if ($Status -and $Status.wheel_scroll_used_for_friend_list -ne $null) { [bool]$Status.wheel_scroll_used_for_friend_list } else { $false }
    $Result.scrollbar_click_count = if ($Status -and $Status.scrollbar_click_count -ne $null) { [int]$Status.scrollbar_click_count } else { 0 }
    $Result.scrollbar_drag_count = if ($Status -and $Status.scrollbar_drag_count -ne $null) { [int]$Status.scrollbar_drag_count } else { 0 }
    $Result.wrong_contact_click_count = if ($Status -and $Status.wrong_contact_click_count -ne $null) { [int]$Status.wrong_contact_click_count } else { 0 }
    $Result.wrong_chat_send_count = if ($Status -and $Status.wrong_chat_send_count -ne $null) { [int]$Status.wrong_chat_send_count } else { 0 }
    $Result.message_text = if ($Status -and $Status.message_text) { [string]$Status.message_text } else { '' }
    $Result.message_sent = if ($Status -and $Status.message_sent -ne $null) { [bool]$Status.message_sent } else { $false }
    $Result.message_visible_after_send = if ($Status -and $Status.message_visible_after_send_by_runner -ne $null) { [bool]$Status.message_visible_after_send_by_runner } else { $false }
    $Result.extra_message_count = if ($Status -and $Status.extra_message_count -ne $null) { [int]$Status.extra_message_count } else { 0 }
    if ((Test-StrictCommon $Result) -and $Status.runner_outcome -eq 'RAW_COMPLETED_UNVERIFIED' -and
        $Result.desktop_app_double_click_used -and $Result.app_opened_by_user_level_mouse -and
        $Result.wechat_foreground_verified -and $Result.target_contact -eq '文件传输助手' -and
        $Result.target_contact_verified_before_click -and $Result.wheel_scroll_used_for_friend_list -and
        [int]$Result.scrollbar_click_count -eq 0 -and [int]$Result.scrollbar_drag_count -eq 0 -and
        [int]$Result.wrong_contact_click_count -eq 0 -and [int]$Result.wrong_chat_send_count -eq 0 -and
        $Result.message_text -eq '这是一条测试信息' -and $Result.message_sent -and $Result.message_visible_after_send -and
        [int]$Result.extra_message_count -eq 0) {
        $Result.actual_result = 'STRICT_DYNAMIC_APP_WECHAT_FILE_TRANSFER_PASS'
        $Result.verification_passed = $true
    }
}

function Verify-QqMail($Status, $Result) {
    $Result.chrome_opened_by_desktop_double_click = if ($Status -and $Status.chrome_opened_by_desktop_double_click -ne $null) { [bool]$Status.chrome_opened_by_desktop_double_click } else { $false }
    $Result.qq_mail_url_verified = if ($Status -and $Status.qq_mail_url_verified -ne $null) { [bool]$Status.qq_mail_url_verified } else { $false }
    $Result.login_or_security_block_detected = if ($Status -and $Status.login_or_security_block_detected -ne $null) { [bool]$Status.login_or_security_block_detected } else { $false }
    $Result.compose_opened = if ($Status -and $Status.compose_opened -ne $null) { [bool]$Status.compose_opened } else { $false }
    $Result.recipient_verified = if ($Status -and $Status.recipient_verified) { [string]$Status.recipient_verified } else { '' }
    $Result.subject_verified = if ($Status -and $Status.subject_verified) { [string]$Status.subject_verified } else { '' }
    $Result.body_verified = if ($Status -and $Status.body_verified) { [string]$Status.body_verified } else { '' }
    $Result.send_button_clicked = if ($Status -and $Status.send_button_clicked -ne $null) { [bool]$Status.send_button_clicked } else { $false }
    $Result.send_success_verified = if ($Status -and $Status.send_success_seen_by_runner -ne $null) { [bool]$Status.send_success_seen_by_runner } else { $false }
    $Result.wrong_recipient_count = if ($Status -and $Status.wrong_recipient_count -ne $null) { [int]$Status.wrong_recipient_count } else { 0 }
    $Result.extra_email_send_count = if ($Status -and $Status.extra_email_send_count -ne $null) { [int]$Status.extra_email_send_count } else { 0 }
    $Result.backend_send_count = if ($Status -and $Status.backend_send_count -ne $null) { [int]$Status.backend_send_count } else { 0 }
    if ((Test-StrictCommon $Result) -and $Status.runner_outcome -eq 'RAW_COMPLETED_UNVERIFIED' -and
        $Result.chrome_opened_by_desktop_double_click -and $Result.qq_mail_url_verified -and
        $Result.login_or_security_block_detected -eq $false -and $Result.compose_opened -and
        $Result.recipient_verified -eq '1581782307@qq.com' -and $Result.subject_verified -eq '测试邮件' -and
        $Result.body_verified -eq '这是一个测试邮件' -and $Result.send_button_clicked -and $Result.send_success_verified -and
        [int]$Result.wrong_recipient_count -eq 0 -and [int]$Result.extra_email_send_count -eq 0 -and [int]$Result.backend_send_count -eq 0) {
        $Result.actual_result = 'STRICT_DYNAMIC_WEB_QQ_MAIL_SEND_PASS'
        $Result.verification_passed = $true
    }
}

function Verify-Baseline($Status, $Result) {
    $failed = @()
    $seen = @{}
    if ($Status -and $Status.baseline_command_results) {
        foreach ($row in $Status.baseline_command_results) {
            $seen[[string]$row.step] = $true
            if ([int]$row.exit_code -ne 0) { $failed += $row.step }
        }
    } else {
        $failed += 'baseline_command_results_missing'
    }
    foreach ($requiredStep in @('v6_1_2_runner_replay','v6_1_2_verifier_replay','v6_1_2_acceptance_gate_replay','v6_1_3_wheel_runner_replay','v6_1_3_wheel_verifier_replay','v6_1_3_scroll_gate_replay','humanmode_pacing_run1','humanmode_pacing_run2','v6_0_boundary_regression','v6_1_planner_selftest','permission_regression','v5_10_adaptive_loop_regression')) {
        if (-not $seen.ContainsKey($requiredStep)) { $failed += "missing_$requiredStep" }
    }
    $Result.baseline_replay_passed = ($failed.Count -eq 0)
    $Result.fixed_ui_regression_passed = ($failed.Count -eq 0)
    $Result.wheel_regression_passed = ($failed.Count -eq 0)
    $Result.humanmode_pacing_passed = ($failed.Count -eq 0)
    $Result.v6_1_2_baseline_gate_passed = ($seen.ContainsKey('v6_1_2_acceptance_gate_replay') -and $failed -notcontains 'v6_1_2_acceptance_gate_replay')
    $Result.v6_1_3_scroll_gate_passed = ($seen.ContainsKey('v6_1_3_scroll_gate_replay') -and $failed -notcontains 'v6_1_3_scroll_gate_replay')
    $Result.v6_1_planner_passed = ($seen.ContainsKey('v6_1_planner_selftest') -and $failed -notcontains 'v6_1_planner_selftest')
    $Result.v6_0_boundary_passed = ($seen.ContainsKey('v6_0_boundary_regression') -and $failed -notcontains 'v6_0_boundary_regression')
    $Result.permission_passed = ($seen.ContainsKey('permission_regression') -and $failed -notcontains 'permission_regression')
    $Result.adaptive_loop_passed = ($seen.ContainsKey('v5_10_adaptive_loop_regression') -and $failed -notcontains 'v5_10_adaptive_loop_regression')
    $Result.old_artifacts_used_as_pass = if ($Status -and $Status.old_artifacts_used_as_pass -ne $null) { [bool]$Status.old_artifacts_used_as_pass } else { $true }
    $Result.failed_baseline_steps = $failed
    if ($Status.runner_outcome -eq 'RAW_COMPLETED_UNVERIFIED' -and $Result.baseline_replay_passed -and $Result.old_artifacts_used_as_pass -eq $false -and $Result.raw_command_evidence_verified) {
        $Result.actual_result = 'STRICT_V6_1_4_BASELINE_REGRESSION_ONCE_PASS'
        $Result.verification_passed = $true
    }
}

function Verify-WrongContextNegative($Status, $Result) {
    $Result.wrong_context_detected = if ($Status -and $Status.wrong_context_detected -ne $null) { [bool]$Status.wrong_context_detected } else { $Result.wrong_context_detected }
    $Result.stopped_before_click = if ($Status -and $Status.stopped_before_click -ne $null) { [bool]$Status.stopped_before_click } else { $Result.stopped_before_click }
    $Result.stopped_before_type = if ($Status -and $Status.stopped_before_type -ne $null) { [bool]$Status.stopped_before_type } else { $Result.stopped_before_type }
    $Result.stopped_before_send = if ($Status -and $Status.stopped_before_send -ne $null) { [bool]$Status.stopped_before_send } else { $Result.stopped_before_send }
    $Result.continued_action_after_wrong_context = if ($Status -and $Status.continued_action_after_wrong_context -ne $null) { [bool]$Status.continued_action_after_wrong_context } else { $Result.continued_action_after_wrong_context }
    $Result.google_search_continued_click_count = if ($Status -and $Status.google_search_continued_click_count -ne $null) { [int]$Status.google_search_continued_click_count } else { $Result.google_search_continued_click_count }
    if ($Status.runner_outcome -eq 'STOP_WRONG_CONTEXT' -and
        $Result.raw_command_evidence_verified -eq $true -and
        $Result.context_trace_present -eq $true -and
        $Result.wrong_context_detected -eq $true -and
        $Result.stopped_before_click -eq $true -and
        $Result.stopped_before_type -eq $true -and
        $Result.stopped_before_send -eq $true -and
        $Result.continued_action_after_wrong_context -eq $false -and
        [int]$Result.google_search_continued_click_count -eq 0 -and
        [int]$Result.wrong_field_input_count -eq 0 -and
        $Result.emergency_stop_triggered -eq $false -and
        $Result.false_positive_stop_detected -eq $false) {
        $Result.actual_result = 'STRICT_WRONG_CONTEXT_STOP_PASS'
        $Result.verification_passed = $true
    }
}

function Copy-TraceOrCreateEmpty([string]$RawCaseDir, [string]$CaseDir, [string]$Name) {
    $src = Join-Path $RawCaseDir $Name
    $dst = Join-Path $CaseDir $Name
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst -Force }
    else { Set-Content -LiteralPath $dst -Value '' -Encoding UTF8 }
}

function Verify-OneCase([string]$CaseId) {
    $rawCase = Join-Path $RawCasesRoot $CaseId
    $caseDir = Join-Path $VerifiedCasesRoot $CaseId
    Clear-CaseDir $caseDir $VerifiedCasesRoot
    foreach ($name in @('screenshots','overlays','crops')) { Ensure-Dir (Join-Path $caseDir $name) }
    Copy-VisualEvidence $rawCase $caseDir
    foreach ($trace in @('task_events.jsonl','action_trace.jsonl','locator_trace.jsonl','scroll_trace.jsonl','adaptive_loop_trace.jsonl','human_action_results.jsonl','focus_trace.jsonl','offset_trace.jsonl','context_trace.jsonl','raw_command_log.jsonl','heartbeat.jsonl')) {
        Copy-TraceOrCreateEmpty $rawCase $caseDir $trace
    }
    $status = Read-JsonFile (Join-Path $rawCase 'raw_case_status.json')
    $result = New-TaskResultBase $CaseId $status $rawCase
    if (-not $status) {
        $result.actual_result = 'NOT_RUN'
        $result.final_failure_reason = 'raw_case_status.json missing'
    } elseif ($CaseId -eq 'v6_1_4_pycharm_dynamic_coding_run') {
        Verify-PyCharm $status $result
    } elseif ($CaseId -eq 'v6_1_4_wechat_file_transfer_assistant_send') {
        Verify-WeChat $status $result
    } elseif ($CaseId -eq 'v6_1_4_qq_mail_web_compose_send') {
        Verify-QqMail $status $result
    } elseif ($CaseId -eq 'v6_1_4_baseline_regression_once') {
        Verify-Baseline $status $result
    } elseif ($CaseId -eq 'v6_1_4_wrong_context_negative_guard') {
        Verify-WrongContextNegative $status $result
    }
    $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $caseDir 'task_result.json') -Encoding UTF8
    @(
        "# Verification Report - $CaseId",
        '',
        "- actual_result: $($result.actual_result)",
        "- verification_passed: $($result.verification_passed)",
        "- raw_command_evidence_verified: $($result.raw_command_evidence_verified)",
        "- first_attempt_success_rate: $($result.first_attempt_success_rate)",
        "- final_failure_reason: $($result.final_failure_reason)",
        '',
        'Verifier generated this result from raw runner evidence. The runner did not decide PASS.'
    ) | Set-Content -LiteralPath (Join-Path $caseDir 'verification_report.md') -Encoding UTF8
    @(
        "# Task Report - $CaseId",
        '',
        "- Result: $($result.actual_result)",
        "- Required expected result: $($CaseExpectations[$CaseId])",
        "- Verification passed: $($result.verification_passed)"
    ) | Set-Content -LiteralPath (Join-Path $caseDir 'task_report.md') -Encoding UTF8
    return $result
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $VerifiedRoot
Ensure-Dir $VerifiedCasesRoot

$results = foreach ($caseId in $CaseExpectations.Keys) { Verify-OneCase $caseId }
$allPass = @($results | Where-Object { $_.verification_passed -ne $true }).Count -eq 0
$overall = if ($allPass) { 'PASS' } else { 'FAIL' }

function Write-SimpleReport([string]$Name, [string[]]$Lines) {
    $Lines | Set-Content -LiteralPath (Join-Path $ArtifactRoot $Name) -Encoding UTF8
}

if ($StateGuardOnly) {
    $wrong = @($results | Where-Object { $_.case_id -eq 'v6_1_4_wrong_context_negative_guard' })[0]
    $base = @($results | Where-Object { $_.case_id -eq 'v6_1_4_baseline_regression_once' })[0]
    $stateGuardPass = ($wrong -and $wrong.actual_result -eq 'STRICT_WRONG_CONTEXT_STOP_PASS' -and $wrong.verification_passed -eq $true)
    $baselinePass = ($base -and $base.actual_result -eq 'STRICT_V6_1_4_BASELINE_REGRESSION_ONCE_PASS' -and $base.verification_passed -eq $true)
    $overall = if ($stateGuardPass -and $baselinePass) { 'STATE_GUARD_PASS_FULL_DYNAMIC_RERUN_PENDING' } else { 'FAIL' }

    Write-SimpleReport 'state_guard_design_report.md' @(
        '# State Guard Design Report',
        '',
        '- Action Precondition Gate: enabled in v6_1_4_dynamic_ui_runner.ps1.',
        '- Expected Context Guard: foreground process/title, page markers, wrong page markers, active protection, automation/bot challenge, target rect source, uniqueness, and viewport checks.',
        '- STOP outcomes: STOP_WRONG_CONTEXT, STOP_WRONG_PAGE, STOP_FOREGROUND_CHANGED, STOP_TARGET_STALE, STOP_TARGET_NOT_UNIQUE, STOP_TARGET_OUTSIDE_VIEWPORT, STOP_WRONG_FIELD_FOCUS, STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK, STOP_AUTOMATION_DETECTED, STOP_LOADING_OR_OVERLAY_BLOCKING.',
        '- Real WeChat/QQ send cases remain gated until wrong-context negative and baseline replay pass.'
    )
    Write-SimpleReport 'action_precondition_report.md' @(
        '# Action Precondition Report',
        '',
        "- Wrong-context negative result: $($wrong.actual_result)",
        "- action_precondition_count: $($wrong.action_precondition_count)",
        "- context_trace_present: $($wrong.context_trace_present)",
        "- continued_action_after_wrong_context: $($wrong.continued_action_after_wrong_context)"
    )
    Write-SimpleReport 'wrong_context_negative_report.md' @(
        '# Wrong Context Negative Report',
        '',
        "- Result: $($wrong.actual_result)",
        "- wrong_context_detected: $($wrong.wrong_context_detected)",
        "- stopped_before_click: $($wrong.stopped_before_click)",
        "- stopped_before_type: $($wrong.stopped_before_type)",
        "- stopped_before_send: $($wrong.stopped_before_send)",
        "- continued_action_after_wrong_context: $($wrong.continued_action_after_wrong_context)",
        "- google_search_continued_click_count: $($wrong.google_search_continued_click_count)",
        "- wrong_field_input_count: $($wrong.wrong_field_input_count)"
    )
    Write-SimpleReport 'browser_context_guard_report.md' @(
        '# Browser Context Guard Report',
        '',
        '- Local mock mail expected context requires Chrome/Edge foreground plus DesktopVisual Local Mail Mock marker.',
        '- Google Search, New Tab, search results, and Bing are wrong context for local mock mail fill.',
        '- QQ Mail expected context is restricted to Chrome and QQ Mail/mail.qq.com markers. v.qq.com, Google Search, New Tab, login/security pages, automation, and bot challenges STOP before action.'
    )
    Write-SimpleReport 'baseline_replay_state_guard_report.md' @(
        '# Baseline Replay State Guard Report',
        '',
        "- Result: $($base.actual_result)",
        "- Baseline replay passed: $($base.baseline_replay_passed)",
        "- Failed baseline steps: $($base.failed_baseline_steps -join ', ')",
        '- v6.1.2 baseline runner now checks local mock mail context before each field and send action.'
    )
    Write-SimpleReport 'scroll_gate_failure_reclassification_report.md' @(
        '# Scroll Gate Failure Reclassification Report',
        '',
        '- scroll_gate_failure_type: BASELINE_REPLAY_WRONG_CONTEXT',
        '- Rationale: existing v6.1.3 scroll primitive cases pass, while v6.1.2 browser local mail mock replay shows page drift/wrong context risk. This must not be classified as TRUE_SCROLL_REGRESSION unless fresh state-guarded replay proves scroll behavior itself failed.'
    )
    Write-SimpleReport 'verifier_report.md' (@('# v6.1.4 State Guard Verifier Report','',"- Overall verifier result: $overall",'') + @($results | ForEach-Object { "- $($_.case_id): $($_.actual_result) verification_passed=$($_.verification_passed) failure=$($_.final_failure_reason)" }))
    Write-SimpleReport 'test_summary.md' @(
        '# v6.1.4 State Guard Test Summary',
        '',
        "- State guard verifier: $overall",
        "- Wrong-context negative: $($wrong.actual_result)",
        "- Baseline regression: $($base.actual_result)",
        "- dynamic app/web full rerun pending: true"
    )
    Write-SimpleReport 'dev_summary.md' @('# v6.1.4 State Guard Development Summary','','- v6.1.4 remains blocked inside the same version.','- State guard work does not enter v6.2 or create v6.1.5.','- WeChat and QQ Mail send paths were not run before guard readiness.')
    Write-SimpleReport 'known_limits.md' @('# v6.1.4 State Guard Known Limits','','- State guard passing alone is not v6.1.4 acceptance. Full PyCharm, WeChat, QQ Mail, and baseline rerun remain required before ACCEPTED.','- Login/security/active protection pages still STOP.')
    Write-SimpleReport 'regression_report.md' @('# v6.1.4 State Guard Regression Report','',"- Baseline case result: $($base.actual_result)","- v6.1.3 scroll gate failure is reclassified through scroll_gate_failure_reclassification_report.md.")

    git -c core.autocrlf=false -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8
    git -c core.autocrlf=false -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8
    Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File |
        ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
        Sort-Object |
        Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

    if ($stateGuardPass -and $baselinePass) {
        Write-Host 'v6.1.4 state guard verifier PASS; full dynamic rerun still pending'
        exit 0
    }
    Write-Host 'v6.1.4 state guard verifier FAIL'
    exit 1
}

$py = @($results | Where-Object { $_.case_id -eq 'v6_1_4_pycharm_dynamic_coding_run' })[0]
$wx = @($results | Where-Object { $_.case_id -eq 'v6_1_4_wechat_file_transfer_assistant_send' })[0]
$qq = @($results | Where-Object { $_.case_id -eq 'v6_1_4_qq_mail_web_compose_send' })[0]
$base = @($results | Where-Object { $_.case_id -eq 'v6_1_4_baseline_regression_once' })[0]

Write-SimpleReport 'pycharm_dynamic_app_report.md' @('# PyCharm Dynamic App Report','',"- Result: $($py.actual_result)","- Verified output lines: $($py.expected_output_lines_verified)","- Failure: $($py.final_failure_reason)")
Write-SimpleReport 'wechat_dynamic_app_report.md' @('# WeChat Dynamic App Report','',"- Result: $($wx.actual_result)","- Target contact: $($wx.target_contact)","- Message sent: $($wx.message_sent)","- Failure: $($wx.final_failure_reason)")
Write-SimpleReport 'qq_mail_dynamic_web_report.md' @('# QQ Mail Dynamic Web Report','',"- Result: $($qq.actual_result)","- URL verified: $($qq.qq_mail_url_verified)","- Recipient: $($qq.recipient_verified)","- Send success: $($qq.send_success_verified)","- Failure: $($qq.final_failure_reason)")
Write-SimpleReport 'baseline_regression_once_report.md' @('# Baseline Regression Once Report','',"- Result: $($base.actual_result)","- Baseline replay passed: $($base.baseline_replay_passed)","- Failed baseline steps: $($base.failed_baseline_steps -join ', ')")

$actionCount = (($results | ForEach-Object { [int]$_.first_attempt_success_count + [int]$_.first_attempt_failure_count }) | Measure-Object -Sum).Sum
$firstSuccess = (($results | ForEach-Object { [int]$_.first_attempt_success_count }) | Measure-Object -Sum).Sum
$firstRate = if ($actionCount -gt 0) { [Math]::Round($firstSuccess / [double]$actionCount, 4) } else { 0.0 }
$misclick = (($results | ForEach-Object { [int]$_.misclick_count }) | Measure-Object -Sum).Sum
$wrongTarget = (($results | ForEach-Object { [int]$_.wrong_target_click_count }) | Measure-Object -Sum).Sum
$wrongField = (($results | ForEach-Object { [int]$_.wrong_field_input_count }) | Measure-Object -Sum).Sum
$outside = (($results | ForEach-Object { [int]$_.cursor_outside_target_rect_count }) | Measure-Object -Sum).Sum
$stale = (($results | ForEach-Object { [int]$_.stale_target_rect_count }) | Measure-Object -Sum).Sum
$focusLoss = (($results | ForEach-Object { [int]$_.keyboard_focus_loss_count }) | Measure-Object -Sum).Sum
$retry = (($results | ForEach-Object { [int]$_.retry_count }) | Measure-Object -Sum).Sum
$reobserve = (($results | ForEach-Object { [int]$_.reobserve_count }) | Measure-Object -Sum).Sum
$screenshotRecovery = (($results | ForEach-Object { [int]$_.screenshot_recovery_count }) | Measure-Object -Sum).Sum

Write-SimpleReport 'first_attempt_quality_report.md' @('# First Attempt Quality Report','',"- action_count: $actionCount","- first_attempt_success_count: $firstSuccess","- first_attempt_success_rate: $firstRate","- misclick_count: $misclick","- wrong_target_click_count: $wrongTarget","- wrong_field_input_count: $wrongField","- cursor_outside_target_rect_count: $outside","- stale_target_rect_count: $stale","- keyboard_focus_loss_count: $focusLoss","- retry_count: $retry","- reobserve_count: $reobserve","- screenshot_recovery_count: $screenshotRecovery")
Write-SimpleReport 'dynamic_click_accuracy_design_report.md' @('# Dynamic Click Accuracy Design Report','','- Click evidence is derived from locator candidates and desktop HumanMode result JSON.','- Verifier requires cursor_inside_target_rect_before_click=true, zero misclicks, and no hardcoded hwnd/rect evidence for PASS.','- Stale or missing target rect prevents click in the runner.')
Write-SimpleReport 'keyboard_focus_diagnostics_report.md' @('# Keyboard Focus Diagnostics Report','','- Keyboard evidence is captured in focus_trace.jsonl around each desktop-type action.','- Verifier blocks wrong_field_input and keyboard_focus_loss for strict PASS.','- Runner verifies target text before send actions when UI text is readable.')
Write-SimpleReport 'mouse_offset_diagnostics_report.md' @('# Mouse Offset Diagnostics Report','',"- mouse_offset_max_px: $(($results | ForEach-Object { [double]$_.mouse_offset_max_px } | Measure-Object -Maximum).Maximum)","- mouse_offset_avg_px_over_cases: $(($results | ForEach-Object { [double]$_.mouse_offset_avg_px } | Measure-Object -Average).Average)")
Write-SimpleReport 'adaptive_retry_report.md' @('# Adaptive Retry Report','',"- retry_count: $retry","- reobserve_count: $reobserve","- screenshot_recovery_count: $screenshotRecovery","- max_action_retries: 2","- max_relocate_attempts: 2")
Write-SimpleReport 'dynamic_ui_evidence_integrity_report.md' @('# Dynamic UI Evidence Integrity Report','',"- synthetic_detected_cases: $(@($results | Where-Object { $_.synthetic_evidence_detected }).Count)","- placeholder_screenshot_cases: $(@($results | Where-Object { $_.placeholder_screenshot_detected }).Count)","- hardcoded_rect_cases: $(@($results | Where-Object { $_.hardcoded_rect_detected }).Count)","- hardcoded_hwnd_cases: $(@($results | Where-Object { $_.hardcoded_hwnd_detected }).Count)")

Write-SimpleReport 'verifier_report.md' (@('# v6.1.4 Dynamic UI Verifier Report','',"- Overall verifier result: $overall",'') + @($results | ForEach-Object { "- $($_.case_id): $($_.actual_result) verification_passed=$($_.verification_passed) failure=$($_.final_failure_reason)" }))
Write-SimpleReport 'test_summary.md' (@('# v6.1.4 Test Summary','',"- Dynamic UI verifier: $overall","- PyCharm: $($py.actual_result)","- WeChat: $($wx.actual_result)","- QQ Mail: $($qq.actual_result)","- Baseline regression: $($base.actual_result)"))
Write-SimpleReport 'dev_summary.md' @('# v6.1.4 Development Summary','','- v6.1.4 adds dynamic App/Web click accuracy and offset diagnostics around real HumanMode actions.','- This stage stays in v6.1.x and does not enter v6.2.','- Persistent Runtime Session, StepContract Compiler, VLM Provider/calls, Experience Memory, and Workflow Templates were not developed.')
Write-SimpleReport 'known_limits.md' @('# v6.1.4 Known Limits','','- Required real UI tests need visible desktop shortcuts, logged-in WeChat, logged-in QQ Mail, and a safe PyCharm project.','- If login/security/human verification appears, the run is blocked and cannot be accepted.','- F12 emergency stop requires runner-side debounce or an explicit stop flag before USER_INTERRUPTION is recorded.')
Write-SimpleReport 'regression_report.md' @('# v6.1.4 Regression Report','',"- Baseline case result: $($base.actual_result)","- v6.1.2/v6.1.3 regression evidence is fresh only when baseline case passes.")

git -c core.autocrlf=false -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8
git -c core.autocrlf=false -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8
Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

if ($allPass) {
    Write-Host 'v6.1.4 dynamic UI verifier PASS'
    exit 0
}

Write-Host 'v6.1.4 dynamic UI verifier FAIL'
exit 1
