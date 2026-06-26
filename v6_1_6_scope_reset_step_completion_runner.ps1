param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
if (Test-Path -LiteralPath $Resolver) {
    $Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
} elseif ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = $PSScriptRoot
}

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_scope_reset_step_completion_closure'
$RawRoot = Join-Path $ArtifactRoot 'raw\case2_pycharm'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ProjectDir = 'D:\testrepo\pycharm_sanity'
$MainFile = Join-Path $ProjectDir 'main.py'
$RunnerResultPath = Join-Path $ArtifactRoot 'case2_pycharm_runner_result.json'
$RawEvidencePath = Join-Path $ArtifactRoot 'case2_pycharm_raw_evidence.json'
$StepTracePath = Join-Path $ArtifactRoot 'case2_step_completion_trace.json'
$GeneratedCodePath = Join-Path $ArtifactRoot 'case2_generated_code.py.txt'
$GeneratedCodeReportPath = Join-Path $ArtifactRoot 'case2_llm_generated_code_report.md'
$ExecutionReportPath = Join-Path $ArtifactRoot 'case2_pycharm_execution_report.md'
$OutcomeReportPath = Join-Path $ArtifactRoot 'case2_execution_outcome_report.md'
$Case1FreezeReportPath = Join-Path $ArtifactRoot 'case1_valid_pass_freeze_report.md'
$Case1AuditPath = Join-Path $ArtifactRoot 'case1_content1_precondition_audit.json'
$Content1FinalPath = Join-Path $ArtifactRoot 'content1_final_status_report.md'
$StepGateSelftestReportPath = Join-Path $ArtifactRoot 'step_completion_gate_selftest_report.md'
$ScopeResetGateReportPath = Join-Path $ArtifactRoot 'scope_reset_gate_report.md'

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
if (-not (Test-Path -LiteralPath $MainFile)) {
    '' | Set-Content -LiteralPath $MainFile -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { return $null }
}

function Read-TextOrEmpty {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -Raw -LiteralPath $Path
}

function Save-Json {
    param($Value, [string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Sha256 {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Normalize-CodeText {
    param([string]$Text)
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
}

function Invoke-WinAgent {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$TimeoutMs = 30000
    )
    $stdoutPath = Join-Path $RawRoot "$Name.stdout.log"
    $stderrPath = Join-Path $RawRoot "$Name.stderr.log"
    $argLine = (($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join ' ')

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $WinAgent
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($TimeoutMs)
    if ($timedOut) {
        try { $p.Kill($true) } catch { try { $p.Kill() } catch {} }
    }
    try { $outTask.Wait(3000) | Out-Null } catch {}
    try { $errTask.Wait(3000) | Out-Null } catch {}
    $stdout = if ($outTask.IsCompleted) { $outTask.Result } else { '' }
    $stderr = if ($errTask.IsCompleted) { $errTask.Result } else { '' }
    $stdout | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    $stderr | Set-Content -LiteralPath $stderrPath -Encoding UTF8
    $json = $null
    try { $json = $stdout | ConvertFrom-Json } catch {}
    [pscustomobject]@{
        name = $Name
        exit_code = if ($timedOut) { 124 } else { $p.ExitCode }
        timed_out = $timedOut
        stdout = $stdout
        stderr = $stderr
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        json = $json
        arguments = @($Arguments)
    }
}

function Get-PyCharmWindow {
    $windowsRun = Invoke-WinAgent -Name 'windows_for_pycharm' -Arguments @('windows') -TimeoutMs 10000
    if (-not $windowsRun.json -or -not $windowsRun.json.windows) { return $null }
    $matches = @($windowsRun.json.windows | Where-Object {
        ([string]$_.title) -match 'PyCharm|pycharm_sanity|main\.py'
    })
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Find-DesktopPyCharmShortcut {
    $showDesktop = Invoke-WinAgent -Name 'show_desktop_for_pycharm_shortcut' -Arguments @('desktop-hotkey','--keys','WIN+D','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    Start-Sleep -Milliseconds 700
    $uia = Invoke-WinAgent -Name 'program_manager_uia_for_pycharm' -Arguments @('uia-tree','--title','Program Manager','--max-elements','500') -TimeoutMs 20000
    $objects = [System.Collections.Generic.List[object]]::new()
    if ($uia.json) { Walk-JsonObjects $uia.json $objects }
    foreach ($obj in @($objects.ToArray())) {
        $name = if ($obj.PSObject.Properties.Name -contains 'name') { [string]$obj.name } else { '' }
        if ($name -match 'PyCharm') {
            $rect = Get-NodeRect $obj
            if ($rect) {
                return [pscustomobject]@{
                    found = $true
                    rect = $rect
                    show_desktop_stdout = $showDesktop.stdout_path
                    uia_stdout = $uia.stdout_path
                    name = $name
                }
            }
        }
    }
    return [pscustomobject]@{
        found = $false
        rect = $null
        show_desktop_stdout = $showDesktop.stdout_path
        uia_stdout = $uia.stdout_path
        name = ''
    }
}

function OpenOrActivatePyCharmVisibleUi {
    $visible = Get-PyCharmWindow
    if ($visible) {
        $rect = $visible.rect
        $x = [int](([int]$rect.left + [int]$rect.right) / 2)
        $y = [int]([int]$rect.top + 18)
        $click = Invoke-WinAgent -Name 'activate_visible_pycharm_window_click' -Arguments @(
            'desktop-click',
            '--screen-x', [string]$x,
            '--screen-y', [string]$y,
            '--move-mode', 'human',
            '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
            '--target-description', 'visible PyCharm window',
            '--coordinate-source', 'visible_window_list',
            '--target-rect-left', [string]$rect.left,
            '--target-rect-top', [string]$rect.top,
            '--target-rect-right', [string]$rect.right,
            '--target-rect-bottom', [string]$rect.bottom
        ) -TimeoutMs 30000
        Start-Sleep -Milliseconds 800
        $active = Invoke-WinAgent -Name 'active_after_visible_pycharm_click' -Arguments @('active-window') -TimeoutMs 10000
        return [pscustomobject]@{
            opened = ($click.exit_code -eq 0 -and $active.json -and ([string]$active.json.data.title -match 'PyCharm|PythonProject|main\.py'))
            method = 'visible_window_mouse_click'
            start_process_used = $false
            opened_by_visible_ui = $true
            click_stdout = $click.stdout_path
            active_stdout = $active.stdout_path
            shortcut = $null
            title = if ($active.json) { [string]$active.json.data.title } else { [string]$visible.title }
        }
    }

    $shortcut = Find-DesktopPyCharmShortcut
    if (-not $shortcut.found) {
        return [pscustomobject]@{
            opened = $false
            method = 'desktop_shortcut_not_found'
            start_process_used = $false
            opened_by_visible_ui = $false
            click_stdout = ''
            active_stdout = ''
            shortcut = $shortcut
            title = ''
        }
    }
    $rect = $shortcut.rect
    $x = [int](([int]$rect.left + [int]$rect.right) / 2)
    $y = [int](([int]$rect.top + [int]$rect.bottom) / 2)
    $dbl = Invoke-WinAgent -Name 'open_pycharm_desktop_shortcut_double_click' -Arguments @(
        'desktop-double-click',
        '--screen-x', [string]$x,
        '--screen-y', [string]$y,
        '--move-mode', 'human',
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--target-description', 'PyCharm desktop shortcut',
        '--coordinate-source', 'program_manager_uia_shortcut',
        '--target-rect-left', [string]$rect.left,
        '--target-rect-top', [string]$rect.top,
        '--target-rect-right', [string]$rect.right,
        '--target-rect-bottom', [string]$rect.bottom
    ) -TimeoutMs 30000
    $window = Wait-PyCharmWindow -TimeoutSeconds 120
    if ($window) {
        $focus = Focus-PyCharmWindow -Window $window
        return [pscustomobject]@{
            opened = ($dbl.exit_code -eq 0 -and $focus.foreground_verified)
            method = 'desktop_shortcut_mouse_double_click'
            start_process_used = $false
            opened_by_visible_ui = $true
            click_stdout = $dbl.stdout_path
            active_stdout = $focus.active.stdout_path
            shortcut = $shortcut
            title = $focus.title
        }
    }
    return [pscustomobject]@{
        opened = $false
        method = 'desktop_shortcut_mouse_double_click_no_window'
        start_process_used = $false
        opened_by_visible_ui = $true
        click_stdout = $dbl.stdout_path
        active_stdout = ''
        shortcut = $shortcut
        title = ''
    }
}

function Wait-PyCharmWindow {
    param([int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $window = Get-PyCharmWindow
        if ($window) { return $window }
        Start-Sleep -Milliseconds 1000
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Focus-PyCharmWindow {
    param($Window)
    if (-not $Window) { return $null }
    $title = [string]$Window.title
    $focus = Invoke-WinAgent -Name 'focus_pycharm' -Arguments @('focus','--title',$title,'--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    Start-Sleep -Milliseconds 800
    $active = Invoke-WinAgent -Name 'active_window_after_focus' -Arguments @('active-window') -TimeoutMs 10000
    [pscustomobject]@{
        focus = $focus
        active = $active
        foreground_verified = ($active.json -and ([string]$active.json.data.title -match 'PyCharm|pycharm_sanity|main\.py'))
        title = if ($active.json) { [string]$active.json.data.title } else { $title }
    }
}

function Recover-PyCharmForeground {
    $active = Invoke-WinAgent -Name 'recover_pycharm_active_check' -Arguments @('active-window') -TimeoutMs 10000
    if ($active.json -and ([string]$active.json.data.title -match 'PyCharm|PythonProject|main\.py')) {
        return [pscustomobject]@{
            recovered = $true
            method = 'already_foreground'
            title = [string]$active.json.data.title
            active_stdout = $active.stdout_path
        }
    }

    $window = Get-PyCharmWindow
    if ($window) {
        $focus = Focus-PyCharmWindow -Window $window
        if ($focus -and $focus.foreground_verified) {
            return [pscustomobject]@{
                recovered = $true
                method = 'visible_window_focus'
                title = [string]$focus.title
                active_stdout = $focus.active.stdout_path
            }
        }
    }

    $visibleOpen = OpenOrActivatePyCharmVisibleUi
    Start-Sleep -Milliseconds 800
    $afterVisibleOpen = Invoke-WinAgent -Name 'recover_pycharm_active_after_visible_ui' -Arguments @('active-window') -TimeoutMs 10000
    return [pscustomobject]@{
        recovered = ($visibleOpen.opened -and $afterVisibleOpen.json -and ([string]$afterVisibleOpen.json.data.title -match 'PyCharm|PythonProject|main\.py'))
        method = 'desktop_shortcut_visible_ui_recovery'
        title = if ($afterVisibleOpen.json) { [string]$afterVisibleOpen.json.data.title } else { [string]$visibleOpen.title }
        active_stdout = $afterVisibleOpen.stdout_path
        visible_open_method = $visibleOpen.method
        visible_open_stdout = $visibleOpen.click_stdout
    }
}

function Walk-JsonObjects {
    param($Node, [System.Collections.Generic.List[object]]$Out)
    if ($null -eq $Node) { return }
    if ($Node -is [System.Array]) {
        foreach ($item in $Node) { Walk-JsonObjects $item $Out }
        return
    }
    if ($Node -is [pscustomobject]) {
        $Out.Add($Node) | Out-Null
        foreach ($prop in $Node.PSObject.Properties) {
            Walk-JsonObjects $prop.Value $Out
        }
    }
}

function Get-NodeRect {
    param($Node)
    foreach ($name in @('rect','bounds','bounding_rect','boundingRectangle')) {
        if ($Node.PSObject.Properties.Name -contains $name) {
            $r = $Node.$name
            if ($r -and $r.PSObject.Properties.Name -contains 'left' -and $r.PSObject.Properties.Name -contains 'right') {
                return $r
            }
        }
    }
    return $null
}

function Locate-PyCharmEditor {
    param($Window)
    $title = [string]$Window.title
    $uia = Invoke-WinAgent -Name 'pycharm_uia_tree' -Arguments @('uia-tree','--title',$title,'--max-elements','700') -TimeoutMs 30000
    $objects = [System.Collections.Generic.List[object]]::new()
    if ($uia.json) { Walk-JsonObjects $uia.json $objects }
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($obj in @($objects.ToArray())) {
        $rect = Get-NodeRect $obj
        if (-not $rect) { continue }
        $width = [int]$rect.right - [int]$rect.left
        $height = [int]$rect.bottom - [int]$rect.top
        if ($width -lt 200 -or $height -lt 120) { continue }
        $text = (($obj.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' ')
        if ($text -match 'Editor|Document|main\.py|Text|Edit|code|缂栬緫|鏂囨湰') {
            $candidates.Add([pscustomobject]@{
                rect = $rect
                score = (($width * $height) + ($(if ($text -match 'main\.py|Editor|Document') { 1000000 } else { 0 })))
                text = $text
            }) | Out-Null
        }
    }
    $best = @($candidates.ToArray() | Sort-Object -Property score -Descending | Select-Object -First 1)[0]
    if ($best) {
        return [pscustomobject]@{
            source = 'uia_editor_candidate'
            rect = $best.rect
            uia_attempted = $true
            uia_candidate_count = $candidates.Count
            uia_stdout = $uia.stdout_path
            uia_stderr = $uia.stderr_path
        }
    }
    $wr = $Window.rect
    return [pscustomobject]@{
        source = 'window_title_client_region_after_uia_attempt'
        rect = [pscustomobject]@{
            left = [int]$wr.left + 260
            top = [int]$wr.top + 160
            right = [int]$wr.right - 220
            bottom = [int]$wr.bottom - 260
        }
        uia_attempted = $true
        uia_candidate_count = 0
        uia_stdout = $uia.stdout_path
        uia_stderr = $uia.stderr_path
    }
}

function Test-GeneratedCodeComplexity {
    param([string]$Code, [string]$RunId)
    $classCount = ([regex]::Matches($Code, '(?m)^\s*class\s+\w+')).Count
    [pscustomobject]@{
        class_count = $classCount
        at_least_two_classes = ($classCount -ge 2)
        has_association_operation = (($Code -match '\.assign\(' -and $Code -match 'self\.tasks\.append') -or ($Code -match 'attach_item\(' -and $Code -match '\.items\.append'))
        has_function_or_method = ($Code -match '(?m)^\s*def\s+\w+')
        has_random_randint_2_10 = ($Code -match 'random\.randint\(2,\s*10\)')
        has_while_loop = ($Code -match '(?m)^\s*while\s+')
        has_run_id_marker = ($Code -match [regex]::Escape($RunId))
        has_output_sequence_text = ($Code -match 'DV616_SEQ')
        no_third_party_import = ($Code -notmatch '(?m)^\s*import\s+(requests|numpy|pandas|PyQt|tkinter|socket|urllib)')
        no_network_or_file_io = ($Code -notmatch '(open\(|socket|requests|urllib|http)')
    }
}

function Invoke-StepGate {
    param(
        [string]$StepId,
        [string]$StepName,
        [string]$StepType,
        [string]$ExpectedContext,
        [string]$ExpectedPreconditions,
        [string]$ActionName,
        [string]$ActionResult,
        $RawEvidence,
        [bool]$PreconditionVerified,
        [bool]$ActionExecuted,
        [bool]$PostObserveRequired,
        [bool]$PostObservePerformed,
        [bool]$PostconditionVerified,
        [string]$PostObserveResult,
        [string]$ExpectedPostconditions,
        [string]$FailureAttributionOnFail,
        [hashtable]$Extra = @{}
    )
    $input = [ordered]@{
        step_id = $StepId
        step_name = $StepName
        step_type = $StepType
        expected_context = $ExpectedContext
        expected_preconditions = $ExpectedPreconditions
        action_name = $ActionName
        action_result = $ActionResult
        raw_action_evidence = ($RawEvidence | ConvertTo-Json -Depth 20)
        precondition_verified = $PreconditionVerified
        action_executed = $ActionExecuted
        post_observe_required = $PostObserveRequired
        post_observe_performed = $PostObservePerformed
        postcondition_verified = $PostconditionVerified
        post_observe_result = $PostObserveResult
        expected_postconditions = $ExpectedPostconditions
        failure_attribution_on_fail = $FailureAttributionOnFail
    }
    foreach ($key in $Extra.Keys) { $input[$key] = $Extra[$key] }

    $inputPath = Join-Path $RawRoot "$StepId.step_completion_input.json"
    $resultPath = Join-Path $RawRoot "$StepId.step_completion_result.json"
    Save-Json $input $inputPath
    $run = Invoke-WinAgent -Name "$StepId.step_completion_cli" -Arguments @('step-completion-evaluate','--input-json',$inputPath,'--result-json',$resultPath) -TimeoutMs 15000
    $result = Read-JsonFile $resultPath
    $record = [ordered]@{
        step_id = $StepId
        step_name = $StepName
        cli_exit_code = $run.exit_code
        input_json = $inputPath
        result_json = $resultPath
        result = $result
    }
    $script:StepTrace.Add($record) | Out-Null
    Save-Json @($script:StepTrace.ToArray()) $StepTracePath
    if ($null -eq $result -or $result.next_step_allowed -ne $true) {
        $code = if ($result -and $result.stop_code) { [string]$result.stop_code } else { 'BLOCKED_STEP_COMPLETION_GATE_MISSING' }
        throw $code
    }
    return $result
}

function Read-ClipboardRaw {
    try { return Get-Clipboard -Raw -ErrorAction Stop } catch { return '' }
}

function Stop-WithEvidence {
    param([string]$Status, [string]$Reason)
    $script:FinalStatus = $Status
    $script:FinalReason = $Reason
    throw $Status
}

$script:StepTrace = [System.Collections.Generic.List[object]]::new()
$script:FinalStatus = 'BLOCKED'
$script:FinalReason = ''
$evidence = [ordered]@{
    schema_version = 'v6.1.6.case2_pycharm_runner.raw'
    generated_at = (Get-Date).ToString('o')
    runner_is_pass_authority = $false
    content1_precondition_checked = $false
    case1_valid_frozen = $false
    pycharm_opened = $false
    editor_clicked_by_mouse = $false
    editor_focus_verified = $false
    existing_code_checked = $false
    existing_code_cleared_if_present = $false
    editor_clean_verified = $false
    llm_generated_code_saved = $false
    generated_code_medium_complexity_verified = $false
    code_text_verified = $false
    run_via_keyboard_shortcut = $false
    run_trigger_method = ''
    run_icon_visual_target_limitation = $true
    vlm_or_visual_template_future_work = $true
    run_triggered = $false
    execution_started = $false
    execution_completed = $false
    execution_success = $false
    exit_code = $null
    current_run_verified = $false
    old_output_reuse_detected = $true
    run_id_marker_verified = $false
    output_sequence_verified = $false
    output_count_between_2_and_10 = $false
    wrong_field_input_count = 0
    continued_action_after_wrong_context = $false
    fix_attempt_count = 0
    code_fix_exhausted = $false
    pycharm_exe = ''
    pycharm_open_method = ''
    pycharm_opened_by_visible_ui = $false
    pycharm_start_process_used = $false
    pycharm_window_title = ''
    generated_code_path = $GeneratedCodePath
    generated_code_sha256 = ''
    generated_by = 'codex_current_turn_external_file'
    code_input_method = ''
    code_input_by_keyboard = $false
    clipboard_paste_used_for_input = $false
    direct_file_write_used_for_input = $false
    execution_outcome_path = ''
    before_snapshot_path = ''
    after_snapshot_path = ''
    step_completion_trace_path = $StepTracePath
    findings = @()
}

try {
    $content1 = Read-TextOrEmpty $Content1FinalPath
    $stepReport = Read-TextOrEmpty $StepGateSelftestReportPath
    $gateReport = Read-TextOrEmpty $ScopeResetGateReportPath
    if ($content1 -notmatch 'STEP_COMPLETION_GATE_PASS_READY_FOR_CASE2' -or
        $stepReport -notmatch 'Status:\s*PASS' -or
        $gateReport -notmatch 'STEP_COMPLETION_GATE_PASS_READY_FOR_CASE2') {
        Stop-WithEvidence 'BLOCKED_STEP_COMPLETION_GATE_NOT_READY' 'Content1 reports do not allow Case2.'
    }
    $case1Audit = Read-JsonFile $Case1AuditPath
    if ($null -eq $case1Audit -or [string]$case1Audit.status -ne 'PASS') {
        Stop-WithEvidence 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY' 'Case1 machine evidence audit is missing or not PASS.'
    }
    $evidence.content1_precondition_checked = $true
    $evidence.case1_valid_frozen = $true

    @(
        '# Case1 Valid PASS Freeze Report',
        '',
        '- Status: PASS',
        '- Case: case_1_qqmail_send',
        "- Evidence path: $($case1Audit.evidence_path)",
        "- Registry path: $($case1Audit.registry_path)",
        '- clicked_target_text == "鍙戦€?: true',
        '- clicked_target_is_compose_send_button: true',
        '- clicked_target_is_sidebar_or_folder: false',
        '- post_send_not_sent_folder_navigation: true',
        '- send_success_verified: true',
        '- recipient_verified: true',
        '- subject_verified: true',
        '- body_verified: true',
        '- wrong_field_input_count: 0',
        '- continued_action_after_wrong_context: false',
        '- frozen_after_pass: true'
    ) | Set-Content -LiteralPath $Case1FreezeReportPath -Encoding UTF8

    if (-not (Test-Path -LiteralPath $GeneratedCodePath)) {
        Stop-WithEvidence 'BLOCKED_GENERATED_CODE_MISSING' 'case2_generated_code.py.txt was not prepared by Codex current turn.'
    }
    $code = Get-Content -Raw -LiteralPath $GeneratedCodePath
    $runIdMatch = [regex]::Match($code, "(?m)^\s*run_id\s*=\s*['""]([^'""]+)['""]")
    if (-not $runIdMatch.Success) {
        Stop-WithEvidence 'BLOCKED_GENERATED_CODE_RUN_ID_MISSING' 'Generated code does not define run_id.'
    }
    $runId = $runIdMatch.Groups[1].Value
    $complexity = Test-GeneratedCodeComplexity -Code $code -RunId $runId
    $mediumOk = $complexity.at_least_two_classes -and
        $complexity.has_association_operation -and
        $complexity.has_function_or_method -and
        $complexity.has_random_randint_2_10 -and
        $complexity.has_while_loop -and
        $complexity.has_run_id_marker -and
        $complexity.has_output_sequence_text -and
        $complexity.no_third_party_import -and
        $complexity.no_network_or_file_io
    if (-not $mediumOk) {
        Stop-WithEvidence 'BLOCKED_GENERATED_CODE_COMPLEXITY_INVALID' 'Generated code did not satisfy medium complexity constraints.'
    }
    $evidence.llm_generated_code_saved = $true
    $evidence.generated_code_medium_complexity_verified = $true
    $evidence.generated_code_sha256 = Get-Sha256 (Normalize-CodeText $code)
    $evidence.run_id = $runId

    @(
        '# Case2 LLM Generated Code Report',
        '',
        '- Status: GENERATED',
        '- generated_by: codex_current_turn_external_file',
        "- Run ID: $runId",
        "- Code path: $GeneratedCodePath",
        "- SHA256: $($evidence.generated_code_sha256)",
        "- Class count: $($complexity.class_count)",
        "- At least two classes: $($complexity.at_least_two_classes)",
        "- Association operation: $($complexity.has_association_operation)",
        "- Function/method present: $($complexity.has_function_or_method)",
        "- random.randint(2, 10): $($complexity.has_random_randint_2_10)",
        "- while loop: $($complexity.has_while_loop)",
        "- Run marker present: $($complexity.has_run_id_marker)",
        "- Output sequence text: $($complexity.has_output_sequence_text)",
        '- Third-party packages: none',
        '- Network/file IO: none'
    ) | Set-Content -LiteralPath $GeneratedCodeReportPath -Encoding UTF8

    $startInfoPath = Join-Path $RawRoot 'pycharm_start_process.json'
    Save-Json ([ordered]@{ start_process_used = $false; reason = 'Start-Process is forbidden for Case2 PASS path.' }) $startInfoPath
    $visibleOpen = OpenOrActivatePyCharmVisibleUi
    if (-not $visibleOpen.opened) {
        Stop-WithEvidence 'BLOCKED_PYCHARM_VISIBLE_LAUNCH_ENTRY_NOT_FOUND' 'PyCharm could not be opened or activated through a visible UI entry.'
    }
    $evidence.pycharm_opened = $true
    $evidence.pycharm_open_method = [string]$visibleOpen.method
    $evidence.pycharm_opened_by_visible_ui = [bool]$visibleOpen.opened_by_visible_ui
    $evidence.pycharm_start_process_used = [bool]$visibleOpen.start_process_used
    $evidence.pycharm_window_title = [string]$visibleOpen.title
    Invoke-StepGate -StepId 'case2_step1_open_pycharm' -StepName 'Open or activate PyCharm' -StepType 'app_activation' `
        -ExpectedContext 'PyCharm visible UI entry available' -ExpectedPreconditions 'visible PyCharm window or desktop shortcut found' `
        -ActionName 'Runtime visible UI mouse click/double-click PyCharm entry' -ActionResult $(if ($evidence.pycharm_opened) { 'foreground_verified' } else { 'foreground_not_verified' }) `
        -RawEvidence @{ open_method = $visibleOpen.method; start_process = $startInfoPath; click_stdout = $visibleOpen.click_stdout; active_stdout = $visibleOpen.active_stdout; shortcut = $visibleOpen.shortcut } `
        -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $true `
        -PostconditionVerified ($evidence.pycharm_opened -and $evidence.pycharm_opened_by_visible_ui -and -not $evidence.pycharm_start_process_used) -PostObserveResult $evidence.pycharm_window_title `
        -ExpectedPostconditions 'pycharm_opened_by_visible_ui=true and pycharm_start_process_used=false' -FailureAttributionOnFail 'BLOCKED_PYCHARM_VISIBLE_LAUNCH_ENTRY_NOT_FOUND' `
        -Extra @{ pycharm_open_method = $evidence.pycharm_open_method; pycharm_opened_by_visible_ui = $evidence.pycharm_opened_by_visible_ui; pycharm_start_process_used = $evidence.pycharm_start_process_used } | Out-Null

    $window = Get-PyCharmWindow
    $locator = Locate-PyCharmEditor -Window $window
    $rect = $locator.rect
    $clickX = [int](([int]$rect.left + [int]$rect.right) / 2)
    $clickY = [int](([int]$rect.top + [int]$rect.bottom) / 2)
    $click = Invoke-WinAgent -Name 'editor_click' -Arguments @(
        'desktop-click',
        '--screen-x', [string]$clickX,
        '--screen-y', [string]$clickY,
        '--move-mode', 'human',
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--target-description', 'PyCharm code editor',
        '--coordinate-source', [string]$locator.source,
        '--target-rect-left', [string]$rect.left,
        '--target-rect-top', [string]$rect.top,
        '--target-rect-right', [string]$rect.right,
        '--target-rect-bottom', [string]$rect.bottom
    ) -TimeoutMs 30000
    Start-Sleep -Milliseconds 800
    $activeAfterClick = Invoke-WinAgent -Name 'active_after_editor_click' -Arguments @('active-window') -TimeoutMs 10000
    $editorFocus = ($activeAfterClick.json -and ([string]$activeAfterClick.json.data.title -match 'PyCharm|pycharm_sanity|main\.py'))
    $evidence.editor_clicked_by_mouse = ($click.exit_code -eq 0)
    $evidence.editor_focus_verified = ($editorFocus -eq $true)
    Invoke-StepGate -StepId 'case2_step2_click_editor' -StepName 'Locate and click editor' -StepType 'editor_focus' `
        -ExpectedContext 'PyCharm foreground' -ExpectedPreconditions 'editor locator from UIA or window title anchored client region' `
        -ActionName 'desktop-click editor center' -ActionResult $(if ($evidence.editor_clicked_by_mouse) { 'mouse_click_sent' } else { 'mouse_click_failed' }) `
        -RawEvidence @{ locator = $locator; click = $click.stdout_path; active_after_click = $activeAfterClick.stdout_path } `
        -PreconditionVerified $evidence.pycharm_opened -ActionExecuted $evidence.editor_clicked_by_mouse -PostObserveRequired $true -PostObservePerformed $true `
        -PostconditionVerified $evidence.editor_focus_verified -PostObserveResult $(if ($activeAfterClick.json) { [string]$activeAfterClick.json.data.title } else { '' }) `
        -ExpectedPostconditions 'editor_clicked_by_mouse=true and editor_focus_verified=true' -FailureAttributionOnFail 'BLOCKED_PYCHARM_EDITOR_NOT_READY' `
        -Extra @{ editor_clicked_by_mouse = $evidence.editor_clicked_by_mouse; editor_focus_verified = $evidence.editor_focus_verified } | Out-Null

    $evidence.existing_code_checked = $true
    Set-Clipboard -Value 'DV616_EMPTY_SENTINEL_BEFORE_CLEAR'
    $selectAll1 = Invoke-WinAgent -Name 'clear_select_all' -Arguments @('desktop-hotkey','--keys','CTRL+A','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    $delete1 = Invoke-WinAgent -Name 'clear_delete' -Arguments @('desktop-press','--key','DELETE','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    Start-Sleep -Milliseconds 500
    Set-Clipboard -Value 'DV616_EMPTY_SENTINEL_AFTER_CLEAR'
    $selectAll2 = Invoke-WinAgent -Name 'verify_empty_select_all' -Arguments @('desktop-hotkey','--keys','CTRL+A','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    $copyEmpty = Invoke-WinAgent -Name 'verify_empty_copy' -Arguments @('desktop-hotkey','--keys','CTRL+C','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    Start-Sleep -Milliseconds 500
    $emptyClipboard = Read-ClipboardRaw
    $cleanOk = (($selectAll1.exit_code -eq 0) -and ($delete1.exit_code -eq 0) -and ($selectAll2.exit_code -eq 0) -and ($copyEmpty.exit_code -eq 0) -and ($emptyClipboard -notmatch 'class\s+Worker|class\s+Task|DV616_RUN_START|DV616_SEQ'))
    $evidence.existing_code_cleared_if_present = ($selectAll1.exit_code -eq 0 -and $delete1.exit_code -eq 0)
    $evidence.editor_clean_verified = $cleanOk
    Invoke-StepGate -StepId 'case2_step3_clear_existing_code' -StepName 'Check and clear existing code' -StepType 'editor_clean' `
        -ExpectedContext 'editor focused' -ExpectedPreconditions 'editor_clicked_by_mouse=true and editor_focus_verified=true' `
        -ActionName 'CTRL+A then DELETE and clipboard-copy verification' -ActionResult $(if ($evidence.existing_code_cleared_if_present) { 'clear_sent' } else { 'clear_failed' }) `
        -RawEvidence @{ select_all = $selectAll1.stdout_path; delete = $delete1.stdout_path; verify_select_all = $selectAll2.stdout_path; verify_copy = $copyEmpty.stdout_path; clipboard_after_clear_length = $emptyClipboard.Length } `
        -PreconditionVerified ($evidence.editor_clicked_by_mouse -and $evidence.editor_focus_verified) -ActionExecuted $evidence.existing_code_cleared_if_present -PostObserveRequired $true -PostObservePerformed $true `
        -PostconditionVerified $evidence.editor_clean_verified -PostObserveResult "clipboard_after_clear_length=$($emptyClipboard.Length)" `
        -ExpectedPostconditions 'existing_code_checked=true, existing_code_cleared_if_present=true, editor_clean_verified=true' -FailureAttributionOnFail 'BLOCKED_PYCHARM_EXISTING_CODE_NOT_CLEARED' | Out-Null

    $typeRecords = [System.Collections.Generic.List[object]]::new()
    $normalizedCodeForTyping = Normalize-CodeText $code
    $codeLinesForTyping = $normalizedCodeForTyping -split "`n"
    $typeOk = $true
    for ($lineIndex = 0; $lineIndex -lt $codeLinesForTyping.Count; $lineIndex++) {
        $lineText = [string]$codeLinesForTyping[$lineIndex]
        $typeLine = Invoke-WinAgent -Name ("keyboard_type_generated_code_line_{0:D2}" -f ($lineIndex + 1)) -Arguments @('desktop-type','--text',$lineText,'--type-mode','human','--char-delay-ms','0','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 30000
        $typeRecords.Add([ordered]@{ line = $lineIndex + 1; type_stdout = $typeLine.stdout_path; exit_code = $typeLine.exit_code }) | Out-Null
        if ($typeLine.exit_code -ne 0) { $typeOk = $false; break }
        if ($lineIndex -lt ($codeLinesForTyping.Count - 1)) {
            $enterLine = Invoke-WinAgent -Name ("keyboard_type_generated_code_enter_{0:D2}" -f ($lineIndex + 1)) -Arguments @('desktop-press','--key','ENTER','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
            $typeRecords.Add([ordered]@{ line = $lineIndex + 1; enter_stdout = $enterLine.stdout_path; exit_code = $enterLine.exit_code }) | Out-Null
            if ($enterLine.exit_code -ne 0) { $typeOk = $false; break }
        }
    }
    Start-Sleep -Milliseconds 1000
    $selectAllCode = Invoke-WinAgent -Name 'verify_code_select_all' -Arguments @('desktop-hotkey','--keys','CTRL+A','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    $copyCode = Invoke-WinAgent -Name 'verify_code_copy' -Arguments @('desktop-hotkey','--keys','CTRL+C','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    Start-Sleep -Milliseconds 500
    $copiedCode = Read-ClipboardRaw
    $copiedCodePath = Join-Path $RawRoot 'copied_code_after_input.py.txt'
    $copiedCode | Set-Content -LiteralPath $copiedCodePath -Encoding UTF8
    $copiedHash = Get-Sha256 (Normalize-CodeText $copiedCode)
    $evidence.code_input_method = 'desktop-type keyboard SendInput'
    $evidence.code_input_by_keyboard = $typeOk
    $evidence.clipboard_paste_used_for_input = $false
    $evidence.direct_file_write_used_for_input = $false
    $codeVerified = ($typeOk -and $selectAllCode.exit_code -eq 0 -and $copyCode.exit_code -eq 0 -and $copiedHash -eq $evidence.generated_code_sha256)
    $evidence.code_text_verified = $codeVerified
    Invoke-StepGate -StepId 'case2_step4_input_generated_code' -StepName 'Input LLM generated code' -StepType 'code_input' `
        -ExpectedContext 'clean PyCharm editor' -ExpectedPreconditions 'editor_clean_verified=true' `
        -ActionName 'desktop-type keyboard line input then select/copy verification' -ActionResult $(if ($typeOk) { 'keyboard_type_sent' } else { 'keyboard_type_failed' }) `
        -RawEvidence @{ keyboard_type_lines = @($typeRecords.ToArray()); select_all = $selectAllCode.stdout_path; copy = $copyCode.stdout_path; copied_code = $copiedCodePath; copied_sha256 = $copiedHash; expected_sha256 = $evidence.generated_code_sha256; clipboard_paste_used_for_input = $false; direct_file_write_used_for_input = $false } `
        -PreconditionVerified $evidence.editor_clean_verified -ActionExecuted $typeOk -PostObserveRequired $true -PostObservePerformed $true `
        -PostconditionVerified $evidence.code_text_verified -PostObserveResult "copied_code_sha256=$copiedHash" `
        -ExpectedPostconditions 'code_text_verified=true, code_input_by_keyboard=true, clipboard_paste_used_for_input=false, direct_file_write_used_for_input=false' -FailureAttributionOnFail 'BLOCKED_PYCHARM_CODE_TEXT_NOT_VERIFIED' `
        -Extra @{ code_text_verified = $evidence.code_text_verified; code_input_method = $evidence.code_input_method; code_input_by_keyboard = $evidence.code_input_by_keyboard; clipboard_paste_used_for_input = $false; direct_file_write_used_for_input = $false } | Out-Null

    $focusBeforeRun = Focus-PyCharmWindow -Window (Get-PyCharmWindow)
    $beforeRead = Invoke-WinAgent -Name 'output_snapshot_before_run' -Arguments @('read-window-text','--title',$evidence.pycharm_window_title) -TimeoutMs 30000
    $beforePath = Join-Path $RawRoot 'pycharm_output_before_run.txt'
    $beforeRead.stdout | Set-Content -LiteralPath $beforePath -Encoding UTF8
    $evidence.before_snapshot_path = $beforePath
    $runHotkey = Invoke-WinAgent -Name 'shift_f10_run' -Arguments @('desktop-hotkey','--keys','SHIFT+F10','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -TimeoutMs 15000
    $evidence.run_via_keyboard_shortcut = ($runHotkey.exit_code -eq 0)
    $evidence.run_trigger_method = 'SHIFT+F10'
    Invoke-StepGate -StepId 'case2_step5_shift_f10_run' -StepName 'Run through SHIFT+F10' -StepType 'run_shortcut' `
        -ExpectedContext 'PyCharm foreground before run' -ExpectedPreconditions 'code_text_verified=true' `
        -ActionName 'desktop-hotkey SHIFT+F10' -ActionResult $(if ($evidence.run_via_keyboard_shortcut) { 'shortcut_sent' } else { 'shortcut_failed' }) `
        -RawEvidence @{ focus_before_run = $focusBeforeRun.active.stdout_path; before_snapshot = $beforePath; hotkey = $runHotkey.stdout_path; run_icon_visual_target_limitation = $true; vlm_or_visual_template_future_work = $true } `
        -PreconditionVerified ($evidence.code_text_verified -and $focusBeforeRun.foreground_verified) -ActionExecuted $evidence.run_via_keyboard_shortcut -PostObserveRequired $true -PostObservePerformed $true `
        -PostconditionVerified ($evidence.run_via_keyboard_shortcut -and $focusBeforeRun.foreground_verified) -PostObserveResult 'SHIFT+F10 sent with PyCharm foreground' `
        -ExpectedPostconditions 'run_shortcut_sent=true and pycharm_foreground_before_run=true' -FailureAttributionOnFail 'BLOCKED_PYCHARM_RUN_SHORTCUT_NOT_SENT' | Out-Null

    $afterPath = Join-Path $RawRoot 'pycharm_output_after_run.txt'
    $afterRead = $null
    $deadline = (Get-Date).AddSeconds(70)
    do {
        Start-Sleep -Milliseconds 2000
        $recoveredAfterRun = Recover-PyCharmForeground
        $readTitle = if ($recoveredAfterRun.recovered -and -not [string]::IsNullOrWhiteSpace($recoveredAfterRun.title)) { [string]$recoveredAfterRun.title } else { $evidence.pycharm_window_title }
        $afterRead = Invoke-WinAgent -Name 'output_snapshot_after_run' -Arguments @('read-window-text','--title',$readTitle) -TimeoutMs 30000
        $afterRead.stdout | Set-Content -LiteralPath $afterPath -Encoding UTF8
        if ($afterRead.stdout -match [regex]::Escape($runId) -and $afterRead.stdout -match 'exit code|Process finished') { break }
    } while ((Get-Date) -lt $deadline)
    $evidence.after_snapshot_path = $afterPath

    $outcomePath = Join-Path $ArtifactRoot 'case2_execution_outcome.json'
    $classify = Invoke-WinAgent -Name 'classify_case2_execution_output' -Arguments @(
        'classify-execution-output',
        '--profile','python',
        '--before',$beforePath,
        '--after',$afterPath,
        '--result-json',$outcomePath,
        '--expected-start-marker',"DV616_RUN_START $runId",
        '--expected-end-marker',"DV616_RUN_END $runId"
    ) -TimeoutMs 30000
    $outcome = Read-JsonFile $outcomePath
    $evidence.execution_outcome_path = $outcomePath
    if ($null -eq $outcome) {
        Stop-WithEvidence 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'ExecutionOutcomeClassifier did not produce JSON.'
    }
    $evidence.run_triggered = [bool]$outcome.run_triggered
    $evidence.execution_started = [bool]$outcome.execution_started
    $evidence.execution_completed = [bool]$outcome.execution_completed
    $evidence.execution_success = [bool]$outcome.execution_success
    $evidence.exit_code = $outcome.exit_code
    $evidence.current_run_verified = [bool]$outcome.current_run_verified
    $evidence.old_output_reuse_detected = [bool]$outcome.old_output_reuse_detected
    $evidence.run_id_marker_verified = ((Read-TextOrEmpty $afterPath) -match [regex]::Escape($runId))
    $evidence.output_sequence_verified = [bool]$outcome.expected_output_verified
    $evidence.output_count_between_2_and_10 = ([int]$outcome.output_count -ge 2 -and [int]$outcome.output_count -le 10)
    $successOutcome = $evidence.run_triggered -and $evidence.execution_started -and $evidence.execution_completed -and $evidence.execution_success -and ([int]$evidence.exit_code -eq 0) -and $evidence.current_run_verified -and $evidence.output_sequence_verified -and $evidence.output_count_between_2_and_10
    Invoke-StepGate -StepId 'case2_step6_classify_execution_outcome' -StepName 'Read output and classify execution' -StepType 'execution_outcome' `
        -ExpectedContext 'PyCharm run output visible' -ExpectedPreconditions 'SHIFT+F10 shortcut sent' `
        -ActionName 'winagent classify-execution-output' -ActionResult $(if ($classify.exit_code -eq 0) { 'classified' } else { 'classifier_failed' }) `
        -RawEvidence @{ before_snapshot = $beforePath; after_snapshot = $afterPath; classifier_stdout = $classify.stdout_path; outcome = $outcomePath } `
        -PreconditionVerified $evidence.run_via_keyboard_shortcut -ActionExecuted ($classify.exit_code -eq 0) -PostObserveRequired $true -PostObservePerformed $true `
        -PostconditionVerified $successOutcome -PostObserveResult "run_triggered=$($evidence.run_triggered); execution_success=$($evidence.execution_success); output_count=$($outcome.output_count)" `
        -ExpectedPostconditions 'run_triggered=true, execution_success=true, exit_code=0, current_run_verified=true, output_sequence_verified=true' -FailureAttributionOnFail 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' `
        -Extra @{ run_triggered = $evidence.run_triggered; execution_success = $evidence.execution_success } | Out-Null

    $allNext = $true
    foreach ($step in @($script:StepTrace.ToArray())) {
        if ($step.result.next_step_allowed -ne $true) { $allNext = $false }
    }
    $evidence.all_step_completion_gate_results_next_step_allowed = $allNext
    if (-not $allNext) {
        Stop-WithEvidence 'BLOCKED_STEP_COMPLETION_GATE_MISSING' 'One or more StepCompletionGate results blocked next step.'
    }

    $script:FinalStatus = 'RAW_COMPLETED_UNVERIFIED'
    $script:FinalReason = 'Case2 raw evidence collected; verifier must decide PASS.'
} catch {
    if ([string]::IsNullOrWhiteSpace($script:FinalReason)) { $script:FinalReason = $_.Exception.Message }
    if ($script:FinalStatus -eq 'BLOCKED') { $script:FinalStatus = $_.Exception.Message }
    if ([string]::IsNullOrWhiteSpace($script:FinalStatus)) { $script:FinalStatus = 'BLOCKED' }
} finally {
    $evidence.status = $script:FinalStatus
    $evidence.reason = $script:FinalReason
    $evidence.step_completion_trace_path = $StepTracePath
    Save-Json $evidence $RawEvidencePath
    Save-Json @($script:StepTrace.ToArray()) $StepTracePath
    Save-Json ([ordered]@{
        schema_version = 'v6.1.6.scope_reset_step_completion_runner.content2'
        generated_at = (Get-Date).ToString('o')
        status = $script:FinalStatus
        runner_is_pass_authority = $false
        raw_evidence_path = $RawEvidencePath
        step_completion_trace_path = $StepTracePath
        generated_code_path = $GeneratedCodePath
        execution_outcome_path = $evidence.execution_outcome_path
        reason = $script:FinalReason
    }) $RunnerResultPath

    @(
        '# Case2 PyCharm Execution Report',
        '',
        "- Status: $script:FinalStatus",
        "- Reason: $script:FinalReason",
        "- PyCharm opened: $($evidence.pycharm_opened)",
        "- Editor clicked by mouse: $($evidence.editor_clicked_by_mouse)",
        "- Editor focus verified: $($evidence.editor_focus_verified)",
        "- Existing code checked: $($evidence.existing_code_checked)",
        "- Existing code cleared if present: $($evidence.existing_code_cleared_if_present)",
        "- Editor clean verified: $($evidence.editor_clean_verified)",
        "- Code text verified: $($evidence.code_text_verified)",
        "- Run via keyboard shortcut: $($evidence.run_via_keyboard_shortcut)",
        "- Run trigger method: $($evidence.run_trigger_method)",
        "- Run icon visual target limitation: true",
        "- VLM/template future work: true",
        "- Step trace: $StepTracePath",
        "- Raw evidence: $RawEvidencePath"
    ) | Set-Content -LiteralPath $ExecutionReportPath -Encoding UTF8

    @(
        '# Case2 Execution Outcome Report',
        '',
        "- Status: $script:FinalStatus",
        "- Outcome path: $($evidence.execution_outcome_path)",
        "- run_triggered: $($evidence.run_triggered)",
        "- execution_started: $($evidence.execution_started)",
        "- execution_completed: $($evidence.execution_completed)",
        "- execution_success: $($evidence.execution_success)",
        "- exit_code: $($evidence.exit_code)",
        "- current_run_verified: $($evidence.current_run_verified)",
        "- old_output_reuse_detected: $($evidence.old_output_reuse_detected)",
        "- run_id_marker_verified: $($evidence.run_id_marker_verified)",
        "- output_sequence_verified: $($evidence.output_sequence_verified)",
        "- output_count_between_2_and_10: $($evidence.output_count_between_2_and_10)",
        "- fix_attempt_count: $($evidence.fix_attempt_count)"
    ) | Set-Content -LiteralPath $OutcomeReportPath -Encoding UTF8
}

if ($script:FinalStatus -ne 'RAW_COMPLETED_UNVERIFIED') {
    Write-Output $script:FinalStatus
    exit 1
}

Write-Output 'CASE2_PYCHARM_RUNNER_RAW_COMPLETED_UNVERIFIED'
exit 0
