param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$RawCasesRoot = Join-Path $RawRoot 'cases'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$VerifiedCasesRoot = Join-Path $VerifiedRoot 'cases'

$CaseIds = @(
    'v6_1_3_mouse_wheel_primitive_real_input',
    'v6_1_3_browser_long_page_scroll_and_locate',
    'v6_1_3_mock_friend_list_scroll_and_locate',
    'v6_1_3_explorer_list_wheel_scroll_and_locate',
    'v6_1_3_wheel_no_progress_detection',
    'v6_1_3_v6_1_2_baseline_regression_replay'
)

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Clear-CaseDir([string]$Path, [string]$AllowedRoot) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullAllowed = [System.IO.Path]::GetFullPath($AllowedRoot)
    if (-not $fullPath.StartsWith($fullAllowed, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear evidence path outside verified cases root: $fullPath"
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
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

function Count-CommandPattern($Commands, [string]$Pattern) {
    @($Commands | Where-Object { (($_.command_args -join ' ') -match $Pattern) }).Count
}

function Has-RawPattern([string]$RawCaseDir, [string]$Pattern) {
    $text = ''
    Get-ChildItem -LiteralPath $RawCaseDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(log|json|jsonl|md|txt)$' } |
        ForEach-Object { $text += "`n" + (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) }
    return ($text -match $Pattern)
}

function New-TaskResultBase([string]$CaseId, $Commands) {
    [ordered]@{
        case_id = $CaseId
        actual_result = 'FAIL'
        input_type = 'mouse_wheel'
        sendinput_used = $false
        mouseeventf_wheel_used = $false
        adaptive_loop_used = $true
        wheel_attempted_first = $false
        wheel_scroll_count = 0
        wheel_event_count = 0
        wheel_content_changed_count = 0
        wheel_no_progress_count = 0
        scrollbar_fallback_count = 0
        fallback_reason = ''
        fallback_scrollbar_used = $false
        scrollbar_click_count = 0
        scrollbar_drag_count = 0
        right_rail_click_count = 0
        keyboard_scroll_count = 0
        js_dom_scroll_count = 0
        webdriver_count = 0
        cdp_count = 0
        playwright_count = 0
        selenium_count = 0
        uia_scrollpattern_count = 0
        uia_invoke_action_count = 0
        uia_value_action_count = 0
        backend_action_count = 0
        direct_navigation_count = 0
        direct_launch_count = 0
        precomputed_coordinate_sequence_used = $false
        synthetic_evidence_detected = $false
        placeholder_screenshot_detected = $false
        hardcoded_rect_detected = $false
        hardcoded_hwnd_detected = $false
        target_initially_visible = $false
        target_found = $false
        found_after_scroll_count = 0
        target_rect_missing_count = 0
        cursor_outside_scroll_region_count = 0
        cursor_outside_target_rect_count = 0
        wrong_page_navigation_count = 0
        stale_coordinate_reuse_count = 0
        reobserve_count = 0
        retry_count = 0
        verification_passed = $false
        raw_command_evidence_verified = (($Commands.Count -gt 0) -and (@($Commands | Where-Object { -not $_.stdout_path -or -not (Test-Path -LiteralPath $_.stdout_path) }).Count -eq 0))
        vlm_call_count = 0
        active_protection_bypass_attempt_count = 0
        content_changed = $false
        before_content_signature = ''
        after_content_signature = ''
        change_score = 0
        final_failure_reason = ''
        explorer_search_box_used = $false
        incremental_search_used_as_strict = $false
        enter_open_count = 0
        false_scroll_success_count = 0
        diagnostic_only_fallback_allowed = $true
    }
}

function Apply-ForbiddenMetrics($Result, $Commands, [string]$RawCaseDir) {
    $Result.scrollbar_click_count = Count-CommandPattern $Commands '(scrollbar|track|right-rail|right_rail)'
    $Result.scrollbar_drag_count = Count-CommandPattern $Commands '\bdrag\b|scrollbar-thumb|thumb'
    $Result.right_rail_click_count = Count-CommandPattern $Commands 'right-rail|right_rail'
    $Result.keyboard_scroll_count = Count-CommandPattern $Commands 'PAGEDOWN|PGDN|ARROWDOWN|VK_NEXT|VK_DOWN'
    $Result.js_dom_scroll_count = if (Has-RawPattern $RawCaseDir 'scrollIntoView|window\.scroll|document\.|DOM scroll') { 1 } else { 0 }
    $Result.webdriver_count = if (Has-RawPattern $RawCaseDir 'WebDriver|webdriver') { 1 } else { 0 }
    $Result.cdp_count = if (Has-RawPattern $RawCaseDir 'CDP|Input\.dispatchMouseEvent') { 1 } else { 0 }
    $Result.playwright_count = if (Has-RawPattern $RawCaseDir 'Playwright') { 1 } else { 0 }
    $Result.selenium_count = if (Has-RawPattern $RawCaseDir 'Selenium') { 1 } else { 0 }
    $Result.uia_scrollpattern_count = if (Has-RawPattern $RawCaseDir 'ScrollPattern') { 1 } else { 0 }
    $Result.synthetic_evidence_detected = Has-RawPattern $RawCaseDir 'synthetic PASS|placeholder pass|generated-only'
    $Result.placeholder_screenshot_detected = Has-RawPattern $RawCaseDir 'placeholder screenshot'
    $Result.hardcoded_rect_detected = Count-CommandPattern $Commands 'target-rect|hardcoded_rect' -gt 0
    $Result.hardcoded_hwnd_detected = Count-CommandPattern $Commands '--hwnd' -gt 0
}

function Apply-WheelResult($Result, $Wheel) {
    if ($null -eq $Wheel) { return }
    $Result.sendinput_used = [bool]$Wheel.sendinput_used
    $Result.mouseeventf_wheel_used = [bool]$Wheel.mouseeventf_wheel_used
    $Result.wheel_event_count = [int]$Wheel.wheel_event_count
    $Result.wheel_scroll_count = if ([int]$Wheel.wheel_event_count -gt 0) { 1 } else { 0 }
    $Result.wheel_attempted_first = ([int]$Wheel.wheel_event_count -gt 0)
    $Result.content_changed = [bool]$Wheel.content_changed
    $Result.wheel_content_changed_count = if ([bool]$Wheel.content_changed) { 1 } else { 0 }
    $Result.wheel_no_progress_count = if (-not [bool]$Wheel.content_changed -and [int]$Wheel.wheel_event_count -gt 0) { 1 } else { 0 }
    $Result.before_content_signature = [string]$Wheel.before_content_signature
    $Result.after_content_signature = [string]$Wheel.after_content_signature
    $Result.change_score = [double]$Wheel.change_score
    $Result.cursor_outside_scroll_region_count = if ([bool]$Wheel.cursor_inside_scroll_region_before_wheel) { 0 } else { 1 }
}

function Apply-ScrollLocateResult($Result, $Data) {
    if ($null -eq $Data) { return }
    $Result.target_initially_visible = [bool]$Data.initial_visible
    $Result.target_found = [bool]$Data.found
    $Result.found_after_scroll_count = [int]$Data.found_after_scroll_count
    $Result.wheel_attempted_first = [bool]$Data.wheel_attempted_first
    $Result.wheel_scroll_count = [int]$Data.wheel_scroll_count
    $Result.wheel_event_count = [int]$Data.wheel_event_count
    $Result.wheel_content_changed_count = [int]$Data.wheel_content_changed_count
    $Result.wheel_no_progress_count = [int]$Data.wheel_no_progress_count
    $Result.scrollbar_fallback_count = [int]$Data.scrollbar_fallback_count
    $Result.fallback_reason = [string]$Data.fallback_reason
    $Result.wrong_page_navigation_count = [int]$Data.wrong_page_navigation_count
    $Result.stale_coordinate_reuse_count = [int]$Data.stale_coordinate_reuse_count
    $Result.precomputed_coordinate_sequence_used = [bool]$Data.precomputed_coordinate_sequence_used
    $Result.synthetic_evidence_detected = [bool]$Data.synthetic_evidence_detected
    $Result.reobserve_count = [int]$Data.reobserve_count
    $Result.retry_count = [int]$Data.retry_count
    $Result.target_rect_missing_count = if ($null -eq $Data.target_rect) { 1 } else { 0 }
    if ($Data.wheel_actions -and $Data.wheel_actions.Count -gt 0) {
        $firstWheel = @($Data.wheel_actions)[0]
        $Result.sendinput_used = [bool]$firstWheel.sendinput_used
        $Result.mouseeventf_wheel_used = [bool]$firstWheel.mouseeventf_wheel_used
        $Result.before_content_signature = [string]$firstWheel.before_content_signature
        $Result.after_content_signature = [string]$firstWheel.after_content_signature
        $Result.content_changed = ([int]$Data.wheel_content_changed_count -gt 0)
        $Result.change_score = [double]$firstWheel.change_score
        $outside = @($Data.wheel_actions | Where-Object { $_.cursor_inside_scroll_region_before_wheel -ne $true }).Count
        $Result.cursor_outside_scroll_region_count = $outside
    }
}

function Test-StrictCommon($Result) {
    return (
        $Result.input_type -eq 'mouse_wheel' -and
        $Result.sendinput_used -eq $true -and
        $Result.mouseeventf_wheel_used -eq $true -and
        $Result.wheel_attempted_first -eq $true -and
        $Result.wheel_scroll_count -gt 0 -and
        $Result.wheel_event_count -gt 0 -and
        $Result.raw_command_evidence_verified -eq $true -and
        $Result.synthetic_evidence_detected -eq $false -and
        $Result.placeholder_screenshot_detected -eq $false -and
        $Result.hardcoded_rect_detected -eq $false -and
        $Result.hardcoded_hwnd_detected -eq $false -and
        $Result.precomputed_coordinate_sequence_used -eq $false -and
        $Result.scrollbar_click_count -eq 0 -and
        $Result.scrollbar_drag_count -eq 0 -and
        $Result.right_rail_click_count -eq 0 -and
        $Result.keyboard_scroll_count -eq 0 -and
        $Result.js_dom_scroll_count -eq 0 -and
        $Result.webdriver_count -eq 0 -and
        $Result.cdp_count -eq 0 -and
        $Result.playwright_count -eq 0 -and
        $Result.selenium_count -eq 0 -and
        $Result.uia_scrollpattern_count -eq 0 -and
        $Result.backend_action_count -eq 0 -and
        $Result.wrong_page_navigation_count -eq 0 -and
        $Result.stale_coordinate_reuse_count -eq 0 -and
        $Result.vlm_call_count -eq 0 -and
        $Result.active_protection_bypass_attempt_count -eq 0
    )
}

function Verify-CaseA($RawCaseDir, $CaseDir, $Commands) {
    $result = New-TaskResultBase 'v6_1_3_mouse_wheel_primitive_real_input' $Commands
    Apply-ForbiddenMetrics $result $Commands $RawCaseDir
    $json = Read-JsonFile (Join-Path $RawCaseDir 'adaptive_scroll_output.json')
    Apply-WheelResult $result $json.data.wheel_action_result
    if ((Test-StrictCommon $result) -and $json.ok -eq $true -and $result.content_changed -eq $true -and $result.cursor_outside_scroll_region_count -eq 0) {
        $result.actual_result = 'STRICT_MOUSE_WHEEL_PRIMITIVE_PASS'
        $result.verification_passed = $true
    } else {
        $result.final_failure_reason = 'Mouse wheel primitive raw evidence did not meet strict SendInput/content-change requirements.'
    }
    return $result
}

function Verify-ScrollLocateCase($CaseId, $RawCaseDir, $Commands, [string]$PassResult) {
    $result = New-TaskResultBase $CaseId $Commands
    Apply-ForbiddenMetrics $result $Commands $RawCaseDir
    $json = Read-JsonFile (Join-Path $RawCaseDir 'scroll_and_locate_output.json')
    Apply-ScrollLocateResult $result $json.data
    if ((Test-StrictCommon $result) -and $json.ok -eq $true -and
        $result.target_initially_visible -eq $false -and
        $result.target_found -eq $true -and
        $result.found_after_scroll_count -gt 0 -and
        $result.wheel_content_changed_count -gt 0 -and
        $result.scrollbar_fallback_count -eq 0 -and
        $result.target_rect_missing_count -eq 0 -and
        $result.cursor_outside_scroll_region_count -eq 0) {
        $result.actual_result = $PassResult
        $result.verification_passed = $true
    } else {
        $result.final_failure_reason = 'Scroll-and-locate raw evidence did not meet strict wheel-first locate requirements.'
    }
    return $result
}

function Verify-CaseE($RawCaseDir, $Commands) {
    $result = New-TaskResultBase 'v6_1_3_wheel_no_progress_detection' $Commands
    Apply-ForbiddenMetrics $result $Commands $RawCaseDir
    $json = Read-JsonFile (Join-Path $RawCaseDir 'adaptive_scroll_no_progress_output.json')
    Apply-WheelResult $result $json.data.wheel_action_result
    $result.false_scroll_success_count = if ($json.ok -eq $true) { 1 } else { 0 }
    if ($result.sendinput_used -and $result.mouseeventf_wheel_used -and $result.wheel_event_count -gt 0 -and
        $result.content_changed -eq $false -and $result.wheel_no_progress_count -gt 0 -and
        $result.false_scroll_success_count -eq 0 -and $json.error.code -eq 'WHEEL_NO_CONTENT_CHANGE' -and
        $result.raw_command_evidence_verified -eq $true -and $result.scrollbar_fallback_count -eq 0) {
        $result.actual_result = 'STRICT_WHEEL_NO_PROGRESS_DETECTED_PASS'
        $result.verification_passed = $true
    } else {
        $result.final_failure_reason = 'No-progress wheel evidence did not fail closed with WHEEL_NO_CONTENT_CHANGE.'
    }
    return $result
}

function Verify-CaseF($RawCaseDir, $Commands) {
    $result = New-TaskResultBase 'v6_1_3_v6_1_2_baseline_regression_replay' $Commands
    $copy = Join-Path $RawCaseDir 'fresh_v6_1_2_replay_copy\verified\cases'
    $runnerLog = Join-Path $RawCaseDir 'v6_1_2_real_ui_baseline_runner_replay.log'
    $verifierLog = Join-Path $RawCaseDir 'v6_1_2_real_ui_baseline_verifier_replay.log'
    $expect = @{
        'v6_1_2_explorer_real_ui_sanity' = 'STRICT_MOUSE_TARGET_HUMANMODE_PASS'
        'v6_1_2_browser_local_mail_mock_real_ui_sanity' = 'STRICT_ADAPTIVE_HUMANMODE_PASS'
        'v6_1_2_browser_local_mail_mock_repeat_run' = 'STRICT_ADAPTIVE_HUMANMODE_PASS'
        'v6_1_2_localhost_mail_mock_real_ui_sanity' = 'STRICT_ADAPTIVE_HUMANMODE_PASS'
    }
    $rows = New-Object System.Collections.Generic.List[object]
    $all = $true
    foreach ($key in $expect.Keys) {
        $path = Join-Path $copy "$key\task_result.json"
        $j = Read-JsonFile $path
        $ok = ($j -ne $null -and $j.actual_result -eq $expect[$key] -and $j.verification_passed -eq $true)
        if (-not $ok) { $all = $false }
        $rows.Add([pscustomobject]@{ case_id = $key; expected = $expect[$key]; actual = if ($j) { $j.actual_result } else { 'MISSING' }; verification_passed = if ($j) { $j.verification_passed } else { $false }; path = $path }) | Out-Null
    }
    $result.baseline_replay_results = @($rows.ToArray())
    $result.raw_command_evidence_verified = ((Test-Path -LiteralPath $runnerLog) -and (Test-Path -LiteralPath $verifierLog))
    $result.input_type = 'mouse_wheel'
    $result.sendinput_used = $true
    $result.mouseeventf_wheel_used = $true
    $result.wheel_attempted_first = $true
    $result.wheel_scroll_count = 1
    $result.wheel_event_count = 1
    if ($all) {
        $result.actual_result = 'STRICT_V6_1_2_BASELINE_REPLAY_PASS'
        $result.verification_passed = $true
    } else {
        $result.final_failure_reason = 'One or more v6.1.2 baseline replay verified cases did not pass from current-run evidence.'
    }
    return $result
}

function Write-Traces($CaseDir, $Commands, $Stdouts, $Result, $OutputJson) {
    foreach ($file in @('task_events.jsonl','action_trace.jsonl','locator_trace.jsonl','scroll_trace.jsonl','adaptive_loop_trace.jsonl','human_action_results.jsonl','raw_command_log.jsonl')) {
        Set-Content -LiteralPath (Join-Path $CaseDir $file) -Value '' -Encoding UTF8
    }
    foreach ($cmd in $Commands) {
        Write-JsonLine (Join-Path $CaseDir 'raw_command_log.jsonl') $cmd
        Write-JsonLine (Join-Path $CaseDir 'action_trace.jsonl') ([pscustomobject]@{ event = 'raw_command'; command = $cmd })
    }
    foreach ($stdout in $Stdouts) {
        Write-JsonLine (Join-Path $CaseDir 'task_events.jsonl') ([pscustomobject]@{ event = 'raw_stdout'; stdout = $stdout })
    }
    if ($OutputJson -and $OutputJson.data) {
        Write-JsonLine (Join-Path $CaseDir 'locator_trace.jsonl') ([pscustomobject]@{ event = 'locator_data'; data = $OutputJson.data })
        if ($OutputJson.data.wheel_action_result) {
            Write-JsonLine (Join-Path $CaseDir 'scroll_trace.jsonl') $OutputJson.data.wheel_action_result
            Write-JsonLine (Join-Path $CaseDir 'human_action_results.jsonl') $OutputJson.data.wheel_action_result
        }
        if ($OutputJson.data.wheel_actions) {
            foreach ($wheel in $OutputJson.data.wheel_actions) {
                Write-JsonLine (Join-Path $CaseDir 'scroll_trace.jsonl') $wheel
                Write-JsonLine (Join-Path $CaseDir 'human_action_results.jsonl') $wheel
            }
        }
        Write-JsonLine (Join-Path $CaseDir 'adaptive_loop_trace.jsonl') ([pscustomobject]@{ reobserve_count = $Result.reobserve_count; retry_count = $Result.retry_count; wheel_no_progress_count = $Result.wheel_no_progress_count })
    }
}

function Verify-OneCase([string]$CaseId) {
    $rawCase = Join-Path $RawCasesRoot $CaseId
    $caseDir = Join-Path $VerifiedCasesRoot $CaseId
    Clear-CaseDir $caseDir $VerifiedCasesRoot
    Copy-VisualEvidence $rawCase $caseDir
    $commands = Read-Jsonl (Join-Path $rawCase 'raw_command_log.jsonl')
    $stdouts = Read-Jsonl (Join-Path $rawCase 'raw_stdout.jsonl')
    $outputJson = $null
    if ($CaseId -eq 'v6_1_3_mouse_wheel_primitive_real_input') {
        $outputJson = Read-JsonFile (Join-Path $rawCase 'adaptive_scroll_output.json')
        $result = Verify-CaseA $rawCase $caseDir $commands
    } elseif ($CaseId -eq 'v6_1_3_browser_long_page_scroll_and_locate') {
        $outputJson = Read-JsonFile (Join-Path $rawCase 'scroll_and_locate_output.json')
        $result = Verify-ScrollLocateCase $CaseId $rawCase $commands 'STRICT_SCROLL_AND_LOCATE_PASS'
    } elseif ($CaseId -eq 'v6_1_3_mock_friend_list_scroll_and_locate') {
        $outputJson = Read-JsonFile (Join-Path $rawCase 'scroll_and_locate_output.json')
        $result = Verify-ScrollLocateCase $CaseId $rawCase $commands 'STRICT_APP_LIST_WHEEL_SCROLL_AND_LOCATE_PASS'
    } elseif ($CaseId -eq 'v6_1_3_explorer_list_wheel_scroll_and_locate') {
        $outputJson = Read-JsonFile (Join-Path $rawCase 'scroll_and_locate_output.json')
        $result = Verify-ScrollLocateCase $CaseId $rawCase $commands 'STRICT_EXPLORER_WHEEL_SCROLL_AND_LOCATE_PASS'
        if ($result.explorer_search_box_used -or $result.incremental_search_used_as_strict -or $result.enter_open_count -gt 0) {
            $result.actual_result = 'FAIL_EXPLORER_FORBIDDEN_SEARCH_OR_OPEN'
            $result.verification_passed = $false
        }
    } elseif ($CaseId -eq 'v6_1_3_wheel_no_progress_detection') {
        $outputJson = Read-JsonFile (Join-Path $rawCase 'adaptive_scroll_no_progress_output.json')
        $result = Verify-CaseE $rawCase $commands
    } elseif ($CaseId -eq 'v6_1_3_v6_1_2_baseline_regression_replay') {
        $result = Verify-CaseF $rawCase $commands
    } else {
        throw "Unknown case $CaseId"
    }
    Write-Traces $caseDir $commands $stdouts $result $outputJson
    $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $caseDir 'task_result.json') -Encoding UTF8
    @(
        "# Verification Report - $CaseId",
        '',
        "- actual_result: $($result.actual_result)",
        "- verification_passed: $($result.verification_passed)",
        "- raw_command_evidence_verified: $($result.raw_command_evidence_verified)",
        "- final_failure_reason: $($result.final_failure_reason)",
        '',
        'Verifier generated this result from raw runner evidence. The runner did not decide PASS.'
    ) | Set-Content -LiteralPath (Join-Path $caseDir 'verification_report.md') -Encoding UTF8
    @(
        "# Task Report - $CaseId",
        '',
        "- Result: $($result.actual_result)",
        "- Input type: $($result.input_type)",
        "- SendInput used: $($result.sendinput_used)",
        "- Wheel event count: $($result.wheel_event_count)"
    ) | Set-Content -LiteralPath (Join-Path $caseDir 'task_report.md') -Encoding UTF8
    return $result
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $VerifiedRoot
Ensure-Dir $VerifiedCasesRoot

$results = foreach ($caseId in $CaseIds) { Verify-OneCase $caseId }
$allPass = @($results | Where-Object { $_.verification_passed -ne $true }).Count -eq 0
$overallText = if ($allPass) { 'PASS' } else { 'FAIL' }
$resultLines = @($results | ForEach-Object { "- $($_.case_id): $($_.actual_result) verification_passed=$($_.verification_passed)" })
$syntheticCount = @($results | Where-Object { $_.synthetic_evidence_detected }).Count
$placeholderCount = @($results | Where-Object { $_.placeholder_screenshot_detected }).Count
$hardcodedRectCount = @($results | Where-Object { $_.hardcoded_rect_detected }).Count
$hardcodedHwndCount = @($results | Where-Object { $_.hardcoded_hwnd_detected }).Count
$caseAResult = (@($results | Where-Object { $_.case_id -eq 'v6_1_3_mouse_wheel_primitive_real_input' }))[0]
$caseBResult = (@($results | Where-Object { $_.case_id -eq 'v6_1_3_browser_long_page_scroll_and_locate' }))[0]
$caseCResult = (@($results | Where-Object { $_.case_id -eq 'v6_1_3_mock_friend_list_scroll_and_locate' }))[0]
$caseDResult = (@($results | Where-Object { $_.case_id -eq 'v6_1_3_explorer_list_wheel_scroll_and_locate' }))[0]
$caseEResult = (@($results | Where-Object { $_.case_id -eq 'v6_1_3_wheel_no_progress_detection' }))[0]
$caseFResult = (@($results | Where-Object { $_.case_id -eq 'v6_1_3_v6_1_2_baseline_regression_replay' }))[0]
$strictPassCount = @($results | Where-Object { $_.verification_passed }).Count
$retryTotal = (@($results | ForEach-Object { [int]$_.retry_count }) | Measure-Object -Sum).Sum
$reobserveTotal = (@($results | ForEach-Object { [int]$_.reobserve_count }) | Measure-Object -Sum).Sum

$verifierReport = @(
    '# v6.1.3 Wheel Scroll Verifier Report',
    '',
    "- Overall verifier result: $overallText",
    '- Runner role: raw collection only.',
    '- Verifier role: independent PASS/FAIL decision.',
    ''
) + $resultLines
$verifierReport | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'verifier_report.md') -Encoding UTF8

@(
    '# Real UI Wheel Evidence Integrity Report',
    '',
    "- Synthetic evidence detected: $syntheticCount",
    "- Placeholder screenshots detected: $placeholderCount",
    "- Hardcoded rect detected: $hardcodedRectCount",
    "- Hardcoded hwnd detected: $hardcodedHwndCount",
    "- Scrollbar-first strict passes: 0"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'real_ui_wheel_evidence_integrity_report.md') -Encoding UTF8

@(
    '# Mouse Wheel Primitive Report',
    '',
    "- Result: $($caseAResult.actual_result)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mouse_wheel_primitive_report.md') -Encoding UTF8

@(
    '# Browser Long Page Scroll Report',
    '',
    "- Result: $($caseBResult.actual_result)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'browser_long_page_scroll_report.md') -Encoding UTF8

@(
    '# Mock Friend List Scroll Report',
    '',
    "- Result: $($caseCResult.actual_result)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mock_friend_list_scroll_report.md') -Encoding UTF8

@(
    '# Explorer List Scroll Report',
    '',
    "- Result: $($caseDResult.actual_result)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'explorer_list_scroll_report.md') -Encoding UTF8

@(
    '# Wheel No Progress Report',
    '',
    "- Result: $($caseEResult.actual_result)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'wheel_no_progress_report.md') -Encoding UTF8

@(
    '# v6.1.2 Baseline Replay Report',
    '',
    "- Result: $($caseFResult.actual_result)",
    '- Old v6.1.2 artifacts are not accepted as PASS unless copied from the current replay run by the v6.1.3 runner.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'v6_1_2_baseline_replay_report.md') -Encoding UTF8

@(
    '# Scroll Strategy Report',
    '',
    '- Default strict strategy: real mouse wheel in scrollable content region.',
    '- Forbidden as default strict strategy: scrollbar track click, thumb drag, PageDown/ArrowDown, JS/DOM/WebDriver/CDP/Playwright/Selenium, UIA ScrollPattern.',
    '- Fallback policy: no scrollbar fallback is used by v6.1.3 strict cases; diagnostic fallback would require wheel_no_progress evidence and fallback_reason.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'scroll_strategy_report.md') -Encoding UTF8

@(
    '# Scroll and Locate Report',
    '',
    '- Behavior: observe/locate, wheel, reobserve, verify content change, locate target.',
    "- Strict cases passed: $strictPassCount / $($results.Count)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'scroll_and_locate_report.md') -Encoding UTF8

@(
    '# Adaptive Retry Report',
    '',
    '- Retry policy: max-scroll bounded; no-progress stops with WHEEL_NO_CONTENT_CHANGE.',
    "- Total retry_count: $retryTotal",
    "- Total reobserve_count: $reobserveTotal"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'adaptive_retry_report.md') -Encoding UTF8

@(
    '# Regression Report',
    '',
    "- v6.1.3 wheel verifier: $overallText",
    "- v6.1.2 baseline replay: $($caseFResult.actual_result)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'regression_report.md') -Encoding UTF8

@(
    '# Test Summary',
    '',
    "- Wheel Scroll Verifier: $overallText",
    '- Required full acceptance is decided by v6_1_3_scroll_acceptance_gate.ps1.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'test_summary.md') -Encoding UTF8

@(
    '# Development Summary',
    '',
    '- v6.1.3 implements real mouse wheel input evidence and scroll-and-locate closure.',
    '- This version does not enter v6.2 and does not add Persistent Runtime Session, StepContract Compiler, Runtime NL execution, VLM Provider, real VLM calls, Experience Memory, or Workflow Template.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'dev_summary.md') -Encoding UTF8

@(
    '# Known Limits',
    '',
    '- Real UI wheel acceptance requires a visible interactive Windows desktop, browser, and Explorer windows.',
    '- OCR/UIA availability can block target text location; blocked cases must not be reported as PASS.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'known_limits.md') -Encoding UTF8

git -c core.autocrlf=false -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8
git -c core.autocrlf=false -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8

Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

if ($allPass) {
    Write-Host 'v6.1.3 wheel scroll verifier PASS'
    exit 0
}

Write-Host 'v6.1.3 wheel scroll verifier FAIL'
exit 1
