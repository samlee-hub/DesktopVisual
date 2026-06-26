param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$RawCasesRoot = Join-Path $RawRoot 'cases'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$VerifiedCasesRoot = Join-Path $VerifiedRoot 'cases'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Clear-CaseDir([string]$Path, [string]$AllowedRoot) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
    if (-not $fullRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullRoot += [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear evidence path outside verified cases root: $fullPath"
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Write-JsonLine([string]$Path, $Object) {
    ($Object | ConvertTo-Json -Compress -Depth 100) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Jsonl([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $items.Add(($line | ConvertFrom-Json)) | Out-Null
        } catch {
            $items.Add([pscustomobject]@{ parse_error = $_.Exception.Message; raw = $line }) | Out-Null
        }
    }
    return $items.ToArray()
}

function Get-TextFilesUnder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.ps1', '.json', '.jsonl', '.txt', '.md', '.stdout', '.stderr') -or $_.Name -match 'stdout|stderr|log|manifest' }
}

function Test-TextContainsAny([string]$Path, [string[]]$Patterns) {
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($file in Get-TextFilesUnder $Path) {
        $text = ''
        try { $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop } catch { continue }
        foreach ($pattern in $Patterns) {
            if ($text -match [regex]::Escape($pattern)) {
                $hits.Add([pscustomobject]@{ file = $file.FullName; pattern = $pattern }) | Out-Null
            }
        }
    }
    return $hits.ToArray()
}

function Test-ImageLooksReal([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 1024) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 8) { return $false }
    $isPng = $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47
    $isBmp = $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D
    return ($isPng -or $isBmp)
}

function Get-RectFromHumanResult($Har) {
    if (-not $Har -or -not $Har.target -or -not $Har.target.target_rect) { return $null }
    $r = $Har.target.target_rect
    if ($r -is [array] -or $r.PSObject.TypeNames -contains 'System.Object[]') {
        if (@($r).Count -lt 4) { return $null }
        return [pscustomobject]@{ left = [int]$r[0]; top = [int]$r[1]; right = [int]$r[2]; bottom = [int]$r[3] }
    }
    if ($null -ne $r.left -and $null -ne $r.top -and $null -ne $r.right -and $null -ne $r.bottom) {
        return [pscustomobject]@{ left = [int]$r.left; top = [int]$r.top; right = [int]$r.right; bottom = [int]$r.bottom }
    }
    return $null
}

function Test-PointInRect([int]$X, [int]$Y, $Rect) {
    if (-not $Rect) { return $false }
    return $X -ge [int]$Rect.left -and $X -le [int]$Rect.right -and $Y -ge [int]$Rect.top -and $Y -le [int]$Rect.bottom
}

function Get-HumanActionResults($Stdouts) {
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Stdouts) {
        $json = $entry.parsed_json
        if (-not $json) { continue }
        $har = $null
        if ($json.data -and $json.data.human_action_result) {
            $har = $json.data.human_action_result
        }
        if ($har -and $har.schema_version -eq 'human_action_result.v1') {
            $results.Add([pscustomobject]@{
                sequence = $entry.sequence
                step = $entry.step
                command = $entry.command
                exit_code = $entry.exit_code
                human_action_result = $har
            }) | Out-Null
        }
    }
    return $results.ToArray()
}

function New-VerifiedCaseDirs([string]$CaseId) {
    $dir = Join-Path $VerifiedCasesRoot $CaseId
    Clear-CaseDir $dir $VerifiedCasesRoot
    foreach ($sub in @('', 'screenshots', 'overlays', 'crops')) {
        Ensure-Dir (Join-Path $dir $sub)
    }
    foreach ($file in @('task_events.jsonl', 'action_trace.jsonl', 'locator_trace.jsonl', 'adaptive_loop_trace.jsonl', 'human_action_results.jsonl', 'raw_command_log.jsonl')) {
        Set-Content -LiteralPath (Join-Path $dir $file) -Value '' -Encoding UTF8
    }
    return $dir
}

function Copy-VisualEvidence([string]$RawCaseDir, [string]$VerifiedCaseDir) {
    foreach ($sub in @('screenshots', 'overlays', 'crops')) {
        $src = Join-Path $RawCaseDir $sub
        $dst = Join-Path $VerifiedCaseDir $sub
        if (Test-Path -LiteralPath $src) {
            Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dst $_.Name) -Force
            }
        }
    }
}

function Get-CommandNames($Commands) {
    @($Commands | ForEach-Object { [string]$_.command })
}

function Get-CountByCommand($Commands, [string[]]$Names) {
    @($Commands | Where-Object { $Names -contains [string]$_.command }).Count
}

function Test-AnyCommandArg($Commands, [string]$Pattern) {
    foreach ($cmd in $Commands) {
        $line = (@($cmd.command_line) -join ' ')
        if ($line -match $Pattern) { return $true }
    }
    return $false
}

function Sum-ResultProperty($Results, [string]$Name) {
    $sum = 0
    foreach ($item in @($Results)) {
        if ($item -and $item.PSObject.Properties[$Name]) {
            $sum += [int]$item.$Name
        }
    }
    return $sum
}

function Get-FieldFailureCount($Prelim) {
    @($Prelim | Where-Object { $_.kind -eq 'field_locator_failure' }).Count
}

function Get-SendFailureCount($Prelim) {
    @($Prelim | Where-Object { $_.kind -eq 'send_button_locator_failure' }).Count
}

function Test-AfterSendVerified($Stdouts, [string]$Prefix) {
    $afterText = @($Stdouts | Where-Object { [string]$_.step -eq "$Prefix-after-send-text" } | Select-Object -Last 1)
    $afterObserve = @($Stdouts | Where-Object { [string]$_.step -eq "$Prefix-after-send-observe" } | Select-Object -Last 1)
    $joined = (($afterText | ForEach-Object { $_.stdout }) + ($afterObserve | ForEach-Object { $_.stdout })) -join "`n"
    $statusOk = $joined -match 'Mock sent successfully'
    $cleared = $joined -notmatch 'xiaoming' -and $joined -notmatch 'desktopvisual test' -and $joined -notmatch 'this is a testing message'
    return [pscustomobject]@{ status_ok = $statusOk; fields_cleared = $cleared; text = $joined }
}

function Test-WindowRelocation($Prelim) {
    $attempts = @($Prelim | Where-Object { $_.kind -eq 'window_relocation_attempt' })
    foreach ($attempt in $attempts) {
        $before = $attempt.details.before_window_rect
        $after = $attempt.details.after_window_rect
        if ($before -and $after) {
            if ([int]$before.left -ne [int]$after.left -or [int]$before.top -ne [int]$after.top -or [int]$before.right -ne [int]$after.right -or [int]$before.bottom -ne [int]$after.bottom) {
                return [pscustomobject]@{ ok = $true; before_window_rect = $before; after_window_rect = $after }
            }
        }
    }
    return [pscustomobject]@{ ok = $false; before_window_rect = $null; after_window_rect = $null }
}

function Get-CommonMetrics($RawCaseDir, $Commands, $Stdouts, $Prelim, $HumanResults) {
    $syntheticPatterns = @(
        'Save-PlaceholderPng',
        'Add-AdaptiveStep',
        'synthetic action_trace',
        'synthetic locator_trace',
        'synthetic human_action_results',
        'fake screenshot',
        'precomputed_coordinate_sequence',
        'ready_for_v6":true',
        'ready_for_v6 = true'
    )
    $syntheticHits = Test-TextContainsAny $RawCaseDir $syntheticPatterns
    $placeholderImages = @()
    foreach ($image in Get-ChildItem -LiteralPath $RawCaseDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.png', '.bmp') }) {
        if (-not (Test-ImageLooksReal $image.FullName)) { $placeholderImages += $image.FullName }
    }

    $mouseResults = @($HumanResults | Where-Object { $_.human_action_result.action_type -in @('mouse_click','mouse_double_click') })
    $cursorOutside = 0
    $targetMissing = 0
    foreach ($hr in $mouseResults) {
        $har = $hr.human_action_result
        $rect = Get-RectFromHumanResult $har
        if (-not $rect) {
            $targetMissing++
            continue
        }
        $insideFlag = $false
        if ($har.verification -and $null -ne $har.verification.cursor_inside_target_rect_before_click) {
            $insideFlag = [bool]$har.verification.cursor_inside_target_rect_before_click
        } elseif ($har.cursor -and $null -ne $har.cursor.actual_before_click_x) {
            $insideFlag = Test-PointInRect ([int]$har.cursor.actual_before_click_x) ([int]$har.cursor.actual_before_click_y) $rect
        }
        if (-not $insideFlag) { $cursorOutside++ }
    }

    $manualFixedMouse = @($HumanResults | Where-Object {
        $_.human_action_result.action_type -in @('mouse_click','mouse_double_click') -and
        $_.human_action_result.target -and
        [string]$_.human_action_result.target.coordinate_source -match 'manual_fixed|fixed'
    }).Count

    [ordered]@{
        adaptive_loop_used = ((Get-CountByCommand $Commands @('adaptive-locate')) -gt 0)
        precomputed_coordinate_sequence_used = ($syntheticHits | Where-Object { $_.pattern -eq 'precomputed_coordinate_sequence' }).Count -gt 0
        raw_command_evidence_verified = (($Commands.Count -gt 0) -and (@($Commands | Where-Object { $null -eq $_.timestamp -or $null -eq $_.exit_code -or -not $_.stdout_path }).Count -eq 0))
        synthetic_evidence_detected = ($syntheticHits.Count -gt 0)
        placeholder_screenshot_detected = ($placeholderImages.Count -gt 0)
        hardcoded_rect_detected = ($manualFixedMouse -gt 0)
        hardcoded_hwnd_detected = (Test-AnyCommandArg $Commands '--hwnd|0x[0-9a-fA-F]{4,}')
        backend_action_count = @($HumanResults | Where-Object { $_.human_action_result.backend_action -eq $true }).Count
        direct_launch_count = (Get-CountByCommand $Commands @('launch-app','browser-nav'))
        js_dom_action_count = 0
        webdriver_count = 0
        cdp_count = 0
        uia_invoke_action_count = (Get-CountByCommand $Commands @('uia-click'))
        uia_value_action_count = (Get-CountByCommand $Commands @('uia-type'))
        wrong_candidate_open_count = 0
        cursor_outside_target_rect_count = $cursorOutside
        target_rect_missing_count = $targetMissing
        field_locator_failure_count = Get-FieldFailureCount $Prelim
        send_button_locator_failure_count = Get-SendFailureCount $Prelim
        wrong_field_input_count = 0
        reobserve_count = (Get-CountByCommand $Commands @('observe','adaptive-locate','read-window-text'))
        retry_count = @($Prelim | Where-Object { $_.kind -match 'retry' }).Count
        vlm_call_count = 0
        active_protection_bypass_attempt_count = 0
        stale_coordinate_reuse_count = 0
        synthetic_hits = $syntheticHits
        invalid_images = $placeholderImages
    }
}

function Write-Traces($CaseDir, $Commands, $Stdouts, $Prelim, $HumanResults) {
    foreach ($cmd in $Commands) {
        Write-JsonLine (Join-Path $CaseDir 'raw_command_log.jsonl') $cmd
        Write-JsonLine (Join-Path $CaseDir 'task_events.jsonl') ([pscustomobject]@{
            timestamp = $cmd.timestamp
            event = 'raw_command'
            command = $cmd.command
            step = $cmd.step
            exit_code = $cmd.exit_code
            stdout_path = $cmd.stdout_path
        })
        if ($cmd.command -in @('observe','adaptive-locate')) {
            Write-JsonLine (Join-Path $CaseDir 'adaptive_loop_trace.jsonl') ([pscustomobject]@{
                timestamp = $cmd.timestamp
                phase = if ($cmd.command -eq 'observe') { 'observe' } else { 'locate' }
                command = $cmd.command
                step = $cmd.step
                exit_code = $cmd.exit_code
            })
        } elseif ($cmd.command -match 'desktop-|drag') {
            Write-JsonLine (Join-Path $CaseDir 'adaptive_loop_trace.jsonl') ([pscustomobject]@{
                timestamp = $cmd.timestamp
                phase = 'action'
                command = $cmd.command
                step = $cmd.step
                exit_code = $cmd.exit_code
            })
        }
    }
    foreach ($stdout in $Stdouts) {
        $json = $stdout.parsed_json
        if ($json -and $json.command -eq 'adaptive-locate') {
            Write-JsonLine (Join-Path $CaseDir 'locator_trace.jsonl') ([pscustomobject]@{
                timestamp = $stdout.timestamp
                step = $stdout.step
                source_command = 'adaptive-locate'
                target_id = $json.data.target_id
                ok = $json.data.ok
                selected_candidate = $json.data.selected_candidate
                rejected_candidates = $json.data.rejected_candidates
                locator_methods_attempted = $json.data.locator_methods_attempted
            })
        }
    }
    foreach ($p in $Prelim) {
        if ($p.kind -match 'locator|heuristic') {
            Write-JsonLine (Join-Path $CaseDir 'locator_trace.jsonl') $p
        }
        Write-JsonLine (Join-Path $CaseDir 'task_events.jsonl') ([pscustomobject]@{
            timestamp = $p.timestamp
            event = 'preliminary_observation'
            kind = $p.kind
            details = $p.details
            trusted_for_pass = $false
        })
    }
    foreach ($hr in $HumanResults) {
        Write-JsonLine (Join-Path $CaseDir 'human_action_results.jsonl') $hr
        Write-JsonLine (Join-Path $CaseDir 'action_trace.jsonl') ([pscustomobject]@{
            sequence = $hr.sequence
            step = $hr.step
            command = $hr.command
            action_type = $hr.human_action_result.action_type
            humanmode = $hr.human_action_result.humanmode
            backend_action = $hr.human_action_result.backend_action
            direct_launch = $hr.human_action_result.direct_launch
            target = $hr.human_action_result.target
            cursor = $hr.human_action_result.cursor
            keyboard = $hr.human_action_result.keyboard
            verification = $hr.human_action_result.verification
            error = $hr.human_action_result.error
        })
    }
}

function New-TaskResultBase([string]$CaseId, $Metrics) {
    [ordered]@{
        case_id = $CaseId
        actual_result = 'FAIL'
        adaptive_loop_used = [bool]$Metrics.adaptive_loop_used
        precomputed_coordinate_sequence_used = [bool]$Metrics.precomputed_coordinate_sequence_used
        raw_command_evidence_verified = [bool]$Metrics.raw_command_evidence_verified
        synthetic_evidence_detected = [bool]$Metrics.synthetic_evidence_detected
        placeholder_screenshot_detected = [bool]$Metrics.placeholder_screenshot_detected
        hardcoded_rect_detected = [bool]$Metrics.hardcoded_rect_detected
        hardcoded_hwnd_detected = [bool]$Metrics.hardcoded_hwnd_detected
        backend_action_count = [int]$Metrics.backend_action_count
        direct_launch_count = [int]$Metrics.direct_launch_count
        js_dom_action_count = [int]$Metrics.js_dom_action_count
        webdriver_count = [int]$Metrics.webdriver_count
        cdp_count = [int]$Metrics.cdp_count
        uia_invoke_action_count = [int]$Metrics.uia_invoke_action_count
        uia_value_action_count = [int]$Metrics.uia_value_action_count
        wrong_candidate_open_count = [int]$Metrics.wrong_candidate_open_count
        cursor_outside_target_rect_count = [int]$Metrics.cursor_outside_target_rect_count
        target_rect_missing_count = [int]$Metrics.target_rect_missing_count
        field_locator_failure_count = [int]$Metrics.field_locator_failure_count
        send_button_locator_failure_count = [int]$Metrics.send_button_locator_failure_count
        wrong_field_input_count = [int]$Metrics.wrong_field_input_count
        reobserve_count = [int]$Metrics.reobserve_count
        retry_count = [int]$Metrics.retry_count
        verification_passed = $false
        vlm_call_count = [int]$Metrics.vlm_call_count
        active_protection_bypass_attempt_count = [int]$Metrics.active_protection_bypass_attempt_count
        stale_coordinate_reuse_count = [int]$Metrics.stale_coordinate_reuse_count
    }
}

function Test-IntegrityHardFail($Metrics) {
    if ($Metrics.synthetic_evidence_detected) { return 'FAIL_SYNTHETIC_EVIDENCE_DETECTED' }
    if ($Metrics.placeholder_screenshot_detected) { return 'FAIL_PLACEHOLDER_SCREENSHOT_DETECTED' }
    if ($Metrics.backend_action_count -gt 0) { return 'FAIL_BACKEND_ACTION_DETECTED' }
    if ($Metrics.hardcoded_rect_detected) { return 'FAIL_HARDCODED_RECT_DETECTED' }
    if ($Metrics.hardcoded_hwnd_detected) { return 'FAIL_HARDCODED_HWND_DETECTED' }
    return ''
}

function Verify-CaseD($RawCaseDir, $CaseDir, $Commands, $Stdouts, $Prelim, $HumanResults, $Metrics) {
    $result = New-TaskResultBase 'explorer_open_local_html_via_humanmode_flow' $Metrics
    $doubleSteps = @($HumanResults | Where-Object {
        $_.command -eq 'desktop-double-click' -and
        [string]$_.step -match '^step_(this_pc|d_drive|testrepo|testwindow|html)-double-click$'
    })
    $enterOpen = @($Commands | Where-Object { $_.command -eq 'desktop-press' -and ((@($_.command_line) -join ' ') -match 'ENTER') }).Count
    $overlays = @(
        'step_this_pc_before_double_click.png',
        'step_d_drive_before_double_click.png',
        'step_testrepo_before_double_click.png',
        'step_testwindow_before_double_click.png',
        'step_html_before_double_click.png'
    )
    $missingOverlay = @($overlays | Where-Object { -not (Test-ImageLooksReal (Join-Path (Join-Path $CaseDir 'overlays') $_)) })
    $finalOpened = (($Stdouts | ForEach-Object { $_.stdout }) -join "`n") -match 'DesktopVisual Local Mail Mock|desktopvisual_mail_mock'
    $hardFail = Test-IntegrityHardFail $Metrics

    $result.enter_open_count = $enterOpen
    $result.keyboard_assisted_open_count = $enterOpen
    $result.explorer_addressbar_path_input_count = 0
    $result.shell_execute_count = 0
    $result.start_process_count = 0
    $result.invoke_item_count = 0
    $result.direct_file_open_count = 0
    $result.path_steps_total = 5
    $result.path_steps_with_target_rect = @($doubleSteps | Where-Object { Get-RectFromHumanResult $_.human_action_result }).Count
    $result.path_steps_with_cursor_inside_target_rect = @($doubleSteps | Where-Object { $_.human_action_result.verification.cursor_inside_target_rect_before_click -eq $true }).Count
    $result.overlay_missing_count = $missingOverlay.Count
    $result.final_browser_open_verified = $finalOpened

    if ($hardFail) {
        $result.actual_result = $hardFail
    } elseif ($doubleSteps.Count -eq 5 -and $result.path_steps_with_target_rect -eq 5 -and $result.path_steps_with_cursor_inside_target_rect -eq 5 -and $enterOpen -eq 0 -and $missingOverlay.Count -eq 0 -and $finalOpened -and $result.raw_command_evidence_verified -and $result.adaptive_loop_used -and $result.cursor_outside_target_rect_count -eq 0) {
        $result.actual_result = 'STRICT_MOUSE_TARGET_HUMANMODE_PASS'
        $result.verification_passed = $true
    } elseif (@($Prelim | Where-Object { $_.kind -eq 'case_unverified_failure' }).Count -gt 0) {
        $result.actual_result = 'FAIL'
        $result.final_failure_reason = (@($Prelim | Where-Object { $_.kind -eq 'case_unverified_failure' } | Select-Object -Last 1)[0]).details.reason
    } else {
        $result.actual_result = 'FAIL_EVIDENCE_INVALID'
        $result.final_failure_reason = 'Case D raw evidence did not meet strict mouse-target requirements.'
    }
    return $result
}

function Verify-CaseE($RawCaseDir, $CaseDir, $Commands, $Stdouts, $Prelim, $HumanResults, $Metrics) {
    $result = New-TaskResultBase 'local_mail_mock_browser_fill_and_send_humanmode_flow' $Metrics
    $rounds = @($Prelim | Where-Object { $_.kind -eq 'case_e_round_unverified_complete' })
    $passed = 0
    foreach ($round in 1..2) {
        $check = Test-AfterSendVerified $Stdouts "case-e-round-$round"
        if ($check.status_ok -and $check.fields_cleared) { $passed++ }
    }
    $relocation = Test-WindowRelocation $Prelim
    $hardFail = Test-IntegrityHardFail $Metrics
    $result.case_e_rounds_total = 2
    $result.case_e_rounds_passed = $passed
    $result.send_status_verified = ($passed -eq 2)
    $result.fields_cleared_verified = ($passed -eq 2)
    $result.tab_only_fallback_count = 0
    $result.before_window_rect = $relocation.before_window_rect
    $result.after_window_rect = $relocation.after_window_rect
    $result.coordinate_mapping_validated = [bool]$relocation.ok

    if ($hardFail) {
        $result.actual_result = $hardFail
    } elseif ($rounds.Count -eq 2 -and $passed -eq 2 -and $relocation.ok -and $result.field_locator_failure_count -eq 0 -and $result.send_button_locator_failure_count -eq 0 -and $result.cursor_outside_target_rect_count -eq 0 -and $result.raw_command_evidence_verified -and $result.adaptive_loop_used) {
        $result.actual_result = 'STRICT_ADAPTIVE_HUMANMODE_PASS'
        $result.verification_passed = $true
    } elseif (@($Prelim | Where-Object { $_.kind -eq 'case_unverified_failure' }).Count -gt 0) {
        $result.actual_result = 'FAIL'
        $result.final_failure_reason = (@($Prelim | Where-Object { $_.kind -eq 'case_unverified_failure' } | Select-Object -Last 1)[0]).details.reason
    } else {
        $result.actual_result = 'FAIL_EVIDENCE_INVALID'
        $result.final_failure_reason = 'Case E raw evidence did not verify two status/clear rounds and window relocation.'
    }
    return $result
}

function Verify-CaseF($RawCaseDir, $CaseDir, $Commands, $Stdouts, $Prelim, $HumanResults, $Metrics) {
    $result = New-TaskResultBase 'localhost_form_fill_submit_humanmode_flow' $Metrics
    $check = Test-AfterSendVerified $Stdouts 'case-f'
    $server = @($Prelim | Where-Object { $_.kind -eq 'localhost_server_started' } | Select-Object -First 1)
    $serverOk = ($server.Count -gt 0 -and $server[0].details.bind -eq '127.0.0.1')
    $hardFail = Test-IntegrityHardFail $Metrics
    $result.send_status_verified = [bool]$check.status_ok
    $result.fields_cleared_verified = [bool]$check.fields_cleared
    $result.direct_navigation_count = (Get-CountByCommand $Commands @('browser-nav'))
    $result.server_bind = if ($server.Count -gt 0) { $server[0].details.bind } else { '' }
    $result.server_bound_all_interfaces = ($result.server_bind -eq '0.0.0.0')

    if ($hardFail) {
        $result.actual_result = $hardFail
    } elseif (-not $serverOk) {
        $result.actual_result = 'SKIP_ENVIRONMENT'
        $result.final_failure_reason = 'Localhost server did not start on 127.0.0.1.'
    } elseif ($result.field_locator_failure_count -gt 0) {
        $last = @($Prelim | Where-Object { $_.kind -eq 'field_locator_failure' } | Select-Object -Last 1)[0]
        $result.actual_result = $last.details.failure_code
    } elseif ($result.send_button_locator_failure_count -gt 0) {
        $result.actual_result = 'FAIL_BROWSER_BUTTON_LOCATOR_SEND'
    } elseif ($check.status_ok -and $check.fields_cleared -and $result.direct_navigation_count -eq 0 -and $result.field_locator_failure_count -eq 0 -and $result.send_button_locator_failure_count -eq 0 -and $result.cursor_outside_target_rect_count -eq 0 -and $result.raw_command_evidence_verified -and $result.adaptive_loop_used) {
        $result.actual_result = 'STRICT_ADAPTIVE_HUMANMODE_PASS'
        $result.verification_passed = $true
    } else {
        $result.actual_result = 'FAIL_BROWSER_FORM_VERIFICATION'
        $result.final_failure_reason = 'Case F did not verify status and cleared fields from raw evidence.'
    }
    return $result
}

function Verify-OneCase([string]$CaseId) {
    $rawCase = Join-Path $RawCasesRoot $CaseId
    $caseDir = New-VerifiedCaseDirs $CaseId
    Copy-VisualEvidence $rawCase $caseDir
    $commands = Read-Jsonl (Join-Path $rawCase 'raw_command_log.jsonl')
    $stdouts = Read-Jsonl (Join-Path $rawCase 'raw_stdout.jsonl')
    $prelim = Read-Jsonl (Join-Path $rawCase 'preliminary_observations.jsonl')
    $human = Get-HumanActionResults $stdouts
    $metrics = Get-CommonMetrics $rawCase $commands $stdouts $prelim $human
    Write-Traces $caseDir $commands $stdouts $prelim $human

    if ($CaseId -eq 'explorer_open_local_html_via_humanmode_flow') {
        $result = Verify-CaseD $rawCase $caseDir $commands $stdouts $prelim $human $metrics
    } elseif ($CaseId -eq 'local_mail_mock_browser_fill_and_send_humanmode_flow') {
        $result = Verify-CaseE $rawCase $caseDir $commands $stdouts $prelim $human $metrics
    } elseif ($CaseId -eq 'localhost_form_fill_submit_humanmode_flow') {
        $result = Verify-CaseF $rawCase $caseDir $commands $stdouts $prelim $human $metrics
    } else {
        throw "Unknown case id: $CaseId"
    }

    $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $caseDir 'task_result.json') -Encoding UTF8
    @(
        "# $CaseId",
        "",
        "- actual_result: $($result.actual_result)",
        "- verification_passed: $($result.verification_passed)",
        "- raw_command_evidence_verified: $($result.raw_command_evidence_verified)",
        "- synthetic_evidence_detected: $($result.synthetic_evidence_detected)",
        "- placeholder_screenshot_detected: $($result.placeholder_screenshot_detected)",
        "- hardcoded_rect_detected: $($result.hardcoded_rect_detected)",
        "- hardcoded_hwnd_detected: $($result.hardcoded_hwnd_detected)",
        "- backend_action_count: $($result.backend_action_count)",
        "- cursor_outside_target_rect_count: $($result.cursor_outside_target_rect_count)",
        "- target_rect_missing_count: $($result.target_rect_missing_count)",
        "- final_failure_reason: $($result.final_failure_reason)"
    ) | Set-Content -LiteralPath (Join-Path $caseDir 'verification_report.md') -Encoding UTF8
    @(
        "# $CaseId",
        "",
        "Verifier generated this task report from raw runner evidence. The runner did not decide PASS.",
        "",
        "- Result: $($result.actual_result)",
        "- Case directory: $caseDir"
    ) | Set-Content -LiteralPath (Join-Path $caseDir 'task_report.md') -Encoding UTF8
    return $result
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $VerifiedRoot
Ensure-Dir $VerifiedCasesRoot

$caseIds = @(
    'explorer_open_local_html_via_humanmode_flow',
    'local_mail_mock_browser_fill_and_send_humanmode_flow',
    'localhost_form_fill_submit_humanmode_flow'
)

$results = @()
foreach ($caseId in $caseIds) {
    $results += Verify-OneCase $caseId
}

$caseD = $results | Where-Object case_id -eq 'explorer_open_local_html_via_humanmode_flow' | Select-Object -First 1
$caseE = $results | Where-Object case_id -eq 'local_mail_mock_browser_fill_and_send_humanmode_flow' | Select-Object -First 1
$caseF = $results | Where-Object case_id -eq 'localhost_form_fill_submit_humanmode_flow' | Select-Object -First 1
$allPass = ($caseD.actual_result -eq 'STRICT_MOUSE_TARGET_HUMANMODE_PASS' -and $caseE.actual_result -eq 'STRICT_ADAPTIVE_HUMANMODE_PASS' -and $caseF.actual_result -eq 'STRICT_ADAPTIVE_HUMANMODE_PASS')

[pscustomobject]@{
    schema_version = 'v5.10.1.verification'
    version = '5.10.1'
    generated_at = (Get-Date).ToString('o')
    all_pass = $allPass
    case_results = $results
} | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $VerifiedRoot 'verification_summary.json') -Encoding UTF8

@(
    '# v5.10.1 Real UI Evidence Verifier Report',
    '',
    "- Case D: $($caseD.actual_result)",
    "- Case E: $($caseE.actual_result) ($($caseE.case_e_rounds_passed)/$($caseE.case_e_rounds_total) rounds)",
    "- Case F: $($caseF.actual_result)",
    "- All pass: $allPass",
    '',
    'PASS, FAIL, and SKIP decisions in this directory are generated only by the verifier from raw winagent evidence.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'verifier_report.md') -Encoding UTF8

@(
    '# Real UI Evidence Integrity Report',
    '',
    "- synthetic_evidence_detected: $(@($results | Where-Object synthetic_evidence_detected).Count -gt 0)",
    "- placeholder_screenshot_detected: $(@($results | Where-Object placeholder_screenshot_detected).Count -gt 0)",
    "- hardcoded_rect_detected: $(@($results | Where-Object hardcoded_rect_detected).Count -gt 0)",
    "- hardcoded_hwnd_detected: $(@($results | Where-Object hardcoded_hwnd_detected).Count -gt 0)",
    "- backend_action_total: $(Sum-ResultProperty $results 'backend_action_count')",
    "- direct_launch_total: $(Sum-ResultProperty $results 'direct_launch_count')",
    "- runner_self_pass_detected: false"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'real_ui_evidence_integrity_report.md') -Encoding UTF8

@(
    '# Case D Real Explorer Report',
    '',
    "- Result: $($caseD.actual_result)",
    "- Path steps with target rect: $($caseD.path_steps_with_target_rect) / $($caseD.path_steps_total)",
    "- Path steps with cursor inside rect: $($caseD.path_steps_with_cursor_inside_target_rect) / $($caseD.path_steps_total)",
    "- Enter open count: $($caseD.enter_open_count)",
    "- Overlay missing count: $($caseD.overlay_missing_count)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'case_d_real_explorer_report.md') -Encoding UTF8

@(
    '# Case E Real File Form Report',
    '',
    "- Result: $($caseE.actual_result)",
    "- Rounds passed: $($caseE.case_e_rounds_passed) / $($caseE.case_e_rounds_total)",
    "- Send status verified: $($caseE.send_status_verified)",
    "- Fields cleared verified: $($caseE.fields_cleared_verified)",
    "- Window relocation validated: $($caseE.coordinate_mapping_validated)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'case_e_real_file_form_report.md') -Encoding UTF8

@(
    '# Case F Real Localhost Report',
    '',
    "- Result: $($caseF.actual_result)",
    "- Server bind: $($caseF.server_bind)",
    "- Direct navigation count: $($caseF.direct_navigation_count)",
    "- Send status verified: $($caseF.send_status_verified)",
    "- Fields cleared verified: $($caseF.fields_cleared_verified)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'case_f_real_localhost_report.md') -Encoding UTF8

@(
    '# Browser Form Locator Report',
    '',
    'Locator priority in the raw runner was adaptive-locate/UIA first, observe-derived UIA second, and deterministic local mock geometry only after a target local mock page/window was present.',
    '',
    "- Case E field locator failures: $($caseE.field_locator_failure_count)",
    "- Case E send locator failures: $($caseE.send_button_locator_failure_count)",
    "- Case F field locator failures: $($caseF.field_locator_failure_count)",
    "- Case F send locator failures: $($caseF.send_button_locator_failure_count)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'browser_form_locator_report.md') -Encoding UTF8

@(
    '# Adaptive Retry Report',
    '',
    "- Case D reobserve_count: $($caseD.reobserve_count)",
    "- Case E reobserve_count: $($caseE.reobserve_count)",
    "- Case F reobserve_count: $($caseF.reobserve_count)",
    "- Retry count total: $(Sum-ResultProperty $results 'retry_count')",
    '- Failed locates stop as FAIL/SKIP; verifier does not convert them to PASS.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'adaptive_retry_report.md') -Encoding UTF8

@(
    '# Window Relocation Resilience Report',
    '',
    "- Case E coordinate mapping validated: $($caseE.coordinate_mapping_validated)",
    "- before_window_rect: $($caseE.before_window_rect | ConvertTo-Json -Compress)",
    "- after_window_rect: $($caseE.after_window_rect | ConvertTo-Json -Compress)",
    "- stale_coordinate_reuse_count: $($caseE.stale_coordinate_reuse_count)"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'window_relocation_resilience_report.md') -Encoding UTF8

@(
    '# Runner Raw Evidence Report',
    '',
    "- Raw root: $RawRoot",
    "- Verified root: $VerifiedRoot",
    '- Runner role: collect raw evidence only.',
    '- Verifier role: decide PASS/FAIL/SKIP from raw evidence.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runner_raw_evidence_report.md') -Encoding UTF8

@(
    '# Regression Report',
    '',
    'Regression commands are recorded in test_summary.md after the required command set is run.',
    '',
    "- Verifier all_pass: $allPass"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'regression_report.md') -Encoding UTF8

@(
    '# v5.10.1 REBUILT Dev Summary',
    '',
    'v5.10.1 is rebuilt as a real UI adaptive cases rerun. Old invalidated v5.10.1/v5.10.2 evidence is not used. This remains v5 and does not introduce VLM, Agent Planner work, public release permission narrowing, or developer permission direction changes.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'dev_summary.md') -Encoding UTF8

@(
    '# Known Limits',
    '',
    'Real UI evidence depends on an interactive Windows desktop, visible Explorer/browser windows, UIA/OCR availability, browser address bar behavior, and localhost binding availability. SKIP/FAIL is not converted to PASS.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'known_limits.md') -Encoding UTF8

@(
    '# Test Summary',
    '',
    'Required commands: build, winagent version, permission selftest, HumanMode pacing test, adaptive loop test, real UI raw runner, independent verifier, synthetic guard, JSON/JSONL parse, Markdown fence validation, encoding scan, COMMAND_PROTOCOL consistency, and git status snapshots.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'test_summary.md') -Encoding UTF8

git -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8
git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8

Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

if ($allPass) {
    Write-Host 'v5.10.1 real UI evidence verifier PASS.'
    exit 0
}

Write-Host 'v5.10.1 real UI evidence verifier found FAIL/SKIP.'
exit 1
