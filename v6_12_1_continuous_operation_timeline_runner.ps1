param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_timeline'
$CommandOutDir = Join-Path $OutDir 'command_output'
$ScreenshotDir = Join-Path $OutDir 'screenshots'
$TimelineJsonl = Join-Path $OutDir 'operation_timeline.jsonl'
$TimelineCsv = Join-Path $OutDir 'operation_timeline.csv'
$TaskId = 'v6.12.1-continuous-operation-timeline'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $CommandOutDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null
if (Test-Path -LiteralPath $TimelineJsonl) {
    Clear-Content -LiteralPath $TimelineJsonl
} else {
    New-Item -ItemType File -Force -Path $TimelineJsonl | Out-Null
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

function Quote-CommandArg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value -match '[\s"`]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

function Get-ArgValue([string[]]$Args, [string]$Name) {
    for ($i = 0; $i -lt $Args.Count - 1; $i++) {
        if ($Args[$i] -eq $Name) { return $Args[$i + 1] }
    }
    return ''
}

function Has-JsonProperty($Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-JsonNumber($Object, [string]$Name, [int64]$Default = 0) {
    if (Has-JsonProperty $Object $Name) {
        try { return [int64][Math]::Round([double]$Object.$Name) } catch { return $Default }
    }
    return $Default
}

function Get-JsonBool($Object, [string]$Name) {
    if (Has-JsonProperty $Object $Name) {
        return [bool]$Object.$Name
    }
    return $false
}

function Infer-OperationType([string[]]$Args) {
    $cmd = $Args[0]
    switch ($cmd) {
        'visible-show-desktop' { return 'foreground_preempt' }
        'foreground-preempt' { return 'foreground_preempt' }
        'global-screenshot' { return 'global_screenshot' }
        'screenshot' { return 'global_screenshot' }
        'target-lock-acquire' { return 'target_lock' }
        'target-lock-release' { return 'target_lock' }
        'coordinate-map' { return 'coordinate_mapping' }
        'desktop-move' { return 'mouse_move' }
        'desktop-click' { return 'mouse_click' }
        'desktop-double-click' { return 'mouse_click' }
        'taskbar-icon-click' { return 'mouse_click' }
        'desktop-icon-double-click' { return 'mouse_click' }
        'desktop-hotkey' { return 'keyboard_hotkey' }
        'desktop-press' { return 'keyboard_hotkey' }
        'desktop-type' { return 'text_input' }
        'type' { return 'text_input' }
        'visible-text-input' { return 'visible_text_input' }
        'uia-tree' { return 'uia_tree' }
        'uia-find' { return 'uia_tree' }
        'uia-click' { return 'uia_tree' }
        'uia-type' { return 'uia_tree' }
        'find-text' { return 'ocr' }
        'click-text' { return 'ocr' }
        'vlm-observation-build-request' { return 'vlm_request' }
        'vlm-observation-run-mock' { return 'vlm_request' }
        'vlm-observation-validate' { return 'vlm_validation' }
        'visible-ui-verify' { return 'verification' }
        default { return 'process_spawn' }
    }
}

function New-TimelineEntry {
    param(
        [string]$OperationType,
        [string]$CommandLine,
        [datetime]$StartUtc,
        [datetime]$EndUtc,
        [int64]$WallClockMs,
        [int64]$RuntimeDurationMs,
        [string]$Stage,
        [int]$AttemptIndex,
        [string]$AttemptMode,
        [string]$TargetTitle,
        [string]$TargetProcess,
        [string]$Result,
        [string]$ErrorCode,
        [string]$EvidenceRef,
        [string]$StdoutFile,
        [string]$StderrFile,
        [int]$ExitCode,
        [bool]$IsWinAgentInvocation,
        [int64]$FixedSleepMs = 0,
        [string]$WaitCondition = '',
        [int64]$WaitConditionMs = 0,
        [int64]$ManualViewImageMs = 0,
        [int64]$CodexThinkingGapMs = 0,
        [bool]$UsedGlobalScreenshot = $false,
        [bool]$UsedTargetLock = $false,
        [bool]$UsedCoordinateMapper = $false,
        [bool]$UsedForegroundPreempt = $false,
        [bool]$UsedRealKeyboardInput = $false,
        [bool]$UsedClipboard = $false,
        [bool]$UsedBackend = $false,
        [bool]$UsedShortcut = $false,
        [string]$ForegroundBefore = '',
        [string]$ForegroundAfter = ''
    )
    $script:OperationIndex++
    $overhead = [Math]::Max(0, $WallClockMs - $RuntimeDurationMs)
    $processStartup = if ($IsWinAgentInvocation) { [Math]::Min($overhead, 250) } else { 0 }
    $powershellWrapper = if ($IsWinAgentInvocation) { [Math]::Max(0, $overhead - $processStartup) } else { 0 }
    [pscustomobject]@{
        operation_id = ('op-{0:D3}' -f $script:OperationIndex)
        parent_task_id = $TaskId
        operation_type = $OperationType
        command = $CommandLine
        start_time_utc = $StartUtc.ToString('o')
        end_time_utc = $EndUtc.ToString('o')
        wall_clock_ms = $WallClockMs
        runtime_duration_ms = $RuntimeDurationMs
        orchestration_overhead_ms = $overhead
        stage = $Stage
        attempt_index = $AttemptIndex
        attempt_mode = $AttemptMode
        target_title = $TargetTitle
        target_process = $TargetProcess
        foreground_before = $ForegroundBefore
        foreground_after = $ForegroundAfter
        used_global_screenshot = $UsedGlobalScreenshot
        used_target_lock = $UsedTargetLock
        used_coordinate_mapper = $UsedCoordinateMapper
        used_foreground_preempt = $UsedForegroundPreempt
        used_real_keyboard_input = $UsedRealKeyboardInput
        used_clipboard = $UsedClipboard
        used_backend = $UsedBackend
        used_shortcut = $UsedShortcut
        fixed_sleep_ms = $FixedSleepMs
        sleep_ms = $FixedSleepMs
        wait_condition = $WaitCondition
        wait_condition_ms = $WaitConditionMs
        manual_view_image_ms = $ManualViewImageMs
        codex_thinking_gap_ms = $CodexThinkingGapMs
        process_startup_overhead_ms = $processStartup
        powershell_wrapper_ms = $powershellWrapper
        result = $Result
        error_code = $ErrorCode
        evidence_ref = $EvidenceRef
        stdout_file = $StdoutFile
        stderr_file = $StderrFile
        exit_code = $ExitCode
        is_winagent_invocation = $IsWinAgentInvocation
        external_orchestration_delay = ($RuntimeDurationMs -lt 500 -and $WallClockMs -gt 5000)
        fixed_sleep_candidate = ($FixedSleepMs -gt 1000)
    }
}

function Add-TimelineEntry($Entry) {
    $script:Timeline += $Entry
    ($Entry | ConvertTo-Json -Compress -Depth 12) | Add-Content -Encoding UTF8 -LiteralPath $TimelineJsonl
}

function Invoke-TimelineCommand {
    param(
        [string[]]$WinArgs,
        [string]$OperationType = '',
        [string]$Stage = 'visible_workflow',
        [int]$AttemptIndex = 1,
        [string]$AttemptMode = 'visible',
        [int[]]$AllowedExitCodes = @(0),
        [string]$EvidenceRef = ''
    )
    if ([string]::IsNullOrWhiteSpace($OperationType)) {
        $OperationType = Infer-OperationType $WinArgs
    }
    $ordinal = $script:OperationIndex + 1
    $prefix = ('{0:D3}_{1}' -f $ordinal, ($WinArgs[0] -replace '[^A-Za-z0-9_.-]', '_'))
    $stdoutFile = Join-Path $CommandOutDir "$prefix.stdout.json"
    $stderrFile = Join-Path $CommandOutDir "$prefix.stderr.txt"
    $commandLine = (Quote-CommandArg $WinAgent) + ' ' + (($WinArgs | ForEach-Object { Quote-CommandArg $_ }) -join ' ')
    $start = [DateTime]::UtcNow
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $WinAgent @WinArgs 1> $stdoutFile 2> $stderrFile
    $exit = $LASTEXITCODE
    $sw.Stop()
    $end = [DateTime]::UtcNow
    $wall = [int64]$sw.ElapsedMilliseconds
    $stdout = if (Test-Path -LiteralPath $stdoutFile) { (Get-Content -Raw -LiteralPath $stdoutFile).Trim() } else { '' }
    $json = $null
    $runtime = 0
    $errorCode = ''
    $ok = $false
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        try {
            $json = $stdout | ConvertFrom-Json
            $runtime = Get-JsonNumber $json 'duration_ms' 0
            $ok = Get-JsonBool $json 'ok'
            if (Has-JsonProperty $json 'error') {
                $errorCode = [string]$json.error.code
            } elseif (Has-JsonProperty $json 'error_code') {
                $errorCode = [string]$json.error_code
            }
        } catch {
            $errorCode = 'JSON_PARSE_FAILED'
            if ($stdout -match '"duration_ms"\s*:\s*(\d+)') {
                $runtime = [int64]$Matches[1]
            }
            if ($stdout -match '"ok"\s*:\s*true') {
                $ok = $true
            }
            if ($stdout -match '"code"\s*:\s*"([^"]+)"') {
                $errorCode = $Matches[1]
            }
        }
    } else {
        $errorCode = 'STDOUT_EMPTY'
    }
    $data = if ($null -ne $json -and (Has-JsonProperty $json 'data')) { $json.data } else { $null }
    $cmd = $WinArgs[0]
    $targetTitle = Get-ArgValue $WinArgs '--target-title'
    if ([string]::IsNullOrWhiteSpace($targetTitle)) { $targetTitle = Get-ArgValue $WinArgs '--title' }
    if ([string]::IsNullOrWhiteSpace($targetTitle)) { $targetTitle = Get-ArgValue $WinArgs '--target' }
    $targetProcess = Get-ArgValue $WinArgs '--target-process'
    if ([string]::IsNullOrWhiteSpace($targetProcess)) { $targetProcess = Get-ArgValue $WinArgs '--process' }
    $usedGlobalScreenshot = $cmd -in @('global-screenshot', 'screenshot') -or (Has-JsonProperty $data 'capture_scope' -and [string]$data.capture_scope -eq 'global_desktop')
    $usedTargetLock = $cmd -like 'target-lock-*' -or ($WinArgs -contains '--require-target-lock') -or (Has-JsonProperty $data 'target_lock') -or (Has-JsonProperty $data 'target_window_locked')
    $usedCoordinateMapper = $cmd -eq 'coordinate-map' -or (Has-JsonProperty $data 'coordinate_mapping') -or (Has-JsonProperty $data 'mapper_used')
    $usedForegroundPreempt = $cmd -eq 'foreground-preempt' -or $cmd -eq 'visible-show-desktop' -or (Has-JsonProperty $data 'foreground_preempt') -or (Has-JsonProperty $data 'foreground_preparation')
    $usedRealKeyboard = $cmd -in @('visible-text-input', 'desktop-type', 'desktop-hotkey', 'desktop-press', 'type', 'hotkey', 'press')
    $usedClipboard = $cmd -like 'clipboard-*' -or (Get-JsonBool $data 'clipboard_used')
    $usedBackend = $cmd -in @('launch-app', 'focus', 'focus-window', 'activate-window', 'bring-window-front') -or (Get-JsonBool $data 'backend_launch_used') -or (Get-JsonBool $data 'backend_file_write_used') -or (Get-JsonBool $data 'backend_fallback_used')
    $usedShortcut = $cmd -in @('desktop-hotkey', 'hotkey') -or (Has-JsonProperty $data 'shortcut_result') -or (Get-JsonBool $data 'win_d_used')
    $result = if ($ok -and ($AllowedExitCodes -contains $exit)) { 'ok' } elseif ($AllowedExitCodes -contains $exit) { 'failed_recorded' } else { 'unexpected_exit' }
    $entry = New-TimelineEntry `
        -OperationType $OperationType `
        -CommandLine $commandLine `
        -StartUtc $start `
        -EndUtc $end `
        -WallClockMs $wall `
        -RuntimeDurationMs $runtime `
        -Stage $Stage `
        -AttemptIndex $AttemptIndex `
        -AttemptMode $AttemptMode `
        -TargetTitle $targetTitle `
        -TargetProcess $targetProcess `
        -Result $result `
        -ErrorCode $errorCode `
        -EvidenceRef $EvidenceRef `
        -StdoutFile $stdoutFile `
        -StderrFile $stderrFile `
        -ExitCode $exit `
        -IsWinAgentInvocation $true `
        -UsedGlobalScreenshot $usedGlobalScreenshot `
        -UsedTargetLock $usedTargetLock `
        -UsedCoordinateMapper $usedCoordinateMapper `
        -UsedForegroundPreempt $usedForegroundPreempt `
        -UsedRealKeyboardInput $usedRealKeyboard `
        -UsedClipboard $usedClipboard `
        -UsedBackend $usedBackend `
        -UsedShortcut $usedShortcut
    Add-TimelineEntry $entry
    [pscustomobject]@{ Entry = $entry; Json = $json; ExitCode = $exit; Stdout = $stdout; StdoutFile = $stdoutFile; StderrFile = $stderrFile }
}

function Add-WaitTimelineEntry {
    param(
        [string]$Name,
        [datetime]$StartUtc,
        [datetime]$EndUtc,
        [int64]$WallClockMs,
        [string]$Result,
        [string]$EvidenceRef = ''
    )
    $entry = New-TimelineEntry `
        -OperationType 'wait_condition' `
        -CommandLine "runner-wait-condition $Name" `
        -StartUtc $StartUtc `
        -EndUtc $EndUtc `
        -WallClockMs $WallClockMs `
        -RuntimeDurationMs 0 `
        -Stage 'wait_condition' `
        -AttemptIndex 1 `
        -AttemptMode 'wait_condition' `
        -TargetTitle '' `
        -TargetProcess '' `
        -Result $Result `
        -ErrorCode '' `
        -EvidenceRef $EvidenceRef `
        -StdoutFile '' `
        -StderrFile '' `
        -ExitCode 0 `
        -IsWinAgentInvocation $false `
        -WaitCondition $Name `
        -WaitConditionMs $WallClockMs
    Add-TimelineEntry $entry
    return $entry
}

function Wait-ForRunDialog {
    param([int]$TimeoutMs = 3000)
    $waitStart = [DateTime]::UtcNow
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $found = $null
    $lastProbe = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $lastProbe = Invoke-TimelineCommand -WinArgs @('active-window') -OperationType 'process_spawn' -Stage 'wait_probe' -AllowedExitCodes @(0, 1)
        if ($lastProbe.Json) {
            $title = [string]$lastProbe.Json.data.title
            $localizedRunTitle = ([char]0x8FD0).ToString() + ([char]0x884C).ToString()
            if ($title -eq 'Run' -or $title -eq $localizedRunTitle) {
                $found = [pscustomobject]@{ Title = $title; Hwnd = [string]$lastProbe.Json.data.hwnd }
                break
            }
        }
        Start-Sleep -Milliseconds 200
    }
    $sw.Stop()
    $waitEnd = [DateTime]::UtcNow
    Add-WaitTimelineEntry -Name 'run_dialog_visible' -StartUtc $waitStart -EndUtc $waitEnd -WallClockMs ([int64]$sw.ElapsedMilliseconds) -Result ($(if ($found) { 'ok' } else { 'timeout_recorded' })) -EvidenceRef ($(if ($lastProbe) { $lastProbe.StdoutFile } else { '' })) | Out-Null
    return $found
}

function Add-Category($Totals, [string]$Name, [int64]$Ms) {
    if (-not $Totals.Contains($Name)) { $Totals[$Name] = 0 }
    $Totals[$Name] = [int64]$Totals[$Name] + $Ms
}

function Get-CategoryTotals($Entries) {
    $totals = [ordered]@{
        foreground_preempt_ms = 0
        global_screenshot_ms = 0
        target_lock_ms = 0
        coordinate_mapping_ms = 0
        mouse_move_ms = 0
        mouse_click_ms = 0
        keyboard_hotkey_ms = 0
        text_input_ms = 0
        visible_text_input_ms = 0
        wait_condition_ms = 0
        fixed_sleep_ms = 0
        uia_tree_ms = 0
        ocr_ms = 0
        vlm_request_ms = 0
        vlm_validation_ms = 0
        verification_ms = 0
        process_spawn_ms = 0
        powershell_wrapper_ms = 0
        codex_orchestration_gap_ms = 0
    }
    foreach ($entry in $Entries) {
        Add-Category $totals 'process_spawn_ms' $entry.process_startup_overhead_ms
        Add-Category $totals 'powershell_wrapper_ms' $entry.powershell_wrapper_ms
        Add-Category $totals 'fixed_sleep_ms' $entry.fixed_sleep_ms
        Add-Category $totals 'wait_condition_ms' $entry.wait_condition_ms
        Add-Category $totals 'codex_orchestration_gap_ms' $entry.codex_thinking_gap_ms
        switch ($entry.operation_type) {
            'foreground_preempt' { Add-Category $totals 'foreground_preempt_ms' $entry.wall_clock_ms }
            'global_screenshot' { Add-Category $totals 'global_screenshot_ms' $entry.wall_clock_ms }
            'target_lock' { Add-Category $totals 'target_lock_ms' $entry.wall_clock_ms }
            'coordinate_mapping' { Add-Category $totals 'coordinate_mapping_ms' $entry.wall_clock_ms }
            'mouse_move' { Add-Category $totals 'mouse_move_ms' $entry.wall_clock_ms }
            'mouse_click' { Add-Category $totals 'mouse_click_ms' $entry.wall_clock_ms }
            'keyboard_hotkey' { Add-Category $totals 'keyboard_hotkey_ms' $entry.wall_clock_ms }
            'text_input' { Add-Category $totals 'text_input_ms' $entry.wall_clock_ms }
            'visible_text_input' { Add-Category $totals 'visible_text_input_ms' $entry.wall_clock_ms }
            'uia_tree' { Add-Category $totals 'uia_tree_ms' $entry.wall_clock_ms }
            'ocr' { Add-Category $totals 'ocr_ms' $entry.wall_clock_ms }
            'vlm_request' { Add-Category $totals 'vlm_request_ms' $entry.wall_clock_ms }
            'vlm_validation' { Add-Category $totals 'vlm_validation_ms' $entry.wall_clock_ms }
            'verification' { Add-Category $totals 'verification_ms' $entry.wall_clock_ms }
        }
    }
    return $totals
}

function Average-WallClock($Entries, [string[]]$Types) {
    $items = @($Entries | Where-Object { $Types -contains $_.operation_type })
    if ($items.Count -eq 0) { return 0 }
    return [Math]::Round((($items | Measure-Object -Property wall_clock_ms -Average).Average), 2)
}

function Top-Table($Rows, [string[]]$Columns, [int]$MaxRows = 20) {
    $out = @()
    $out += '| ' + ($Columns -join ' | ') + ' |'
    $out += '| ' + (($Columns | ForEach-Object { '---' }) -join ' | ') + ' |'
    foreach ($row in @($Rows | Select-Object -First $MaxRows)) {
        $values = foreach ($column in $Columns) {
            $value = [string]$row.$column
            $value.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        }
        $out += '| ' + ($values -join ' | ') + ' |'
    }
    return $out
}

$script:Timeline = @()
$script:OperationIndex = 0
$taskStart = [DateTime]::UtcNow
$workflowMode = 'LIGHTWEIGHT_VISIBLE_UI_FALLBACK'
$workflowReason = ''
$pycharmAttempted = $false
$pycharmSuitable = $false

$SafetyConfig = Join-Path $OutDir 'timeline_safety.conf'
@(
    'allowed_titles=Run;运行;Program Manager;Desktop',
    'allowed_processes=explorer.exe;ApplicationFrameHost.exe',
    'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts',
    'allowed_write_roots=${PROJECT_ROOT}\artifacts',
    'max_steps=200',
    'max_duration_ms=120000',
    'emergency_stop_key=F12',
    'allow_absolute_screen_click=true'
) | Set-Content -Encoding UTF8 -LiteralPath $SafetyConfig

$oldSafetyConfig = $env:DESKTOPVISUAL_SAFETY_CONFIG
$env:DESKTOPVISUAL_SAFETY_CONFIG = $SafetyConfig

try {
    $pycharmProbe = Invoke-TimelineCommand -WinArgs @('target-lock-acquire', '--target-process', 'pycharm64.exe') -OperationType 'target_lock' -Stage 'preflight_pycharm_probe' -AllowedExitCodes @(0, 1)
    if ($pycharmProbe.Json -and $pycharmProbe.Json.ok -eq $true) {
        $probeTitle = [string]$pycharmProbe.Json.data.title
        if ($probeTitle -match 'pycharm_sanity|main.py') {
            $pycharmSuitable = $true
            $safePyCharm = @([pscustomobject]@{ title = $probeTitle })
        } else {
            $workflowReason = 'PyCharm window exists, but title did not prove D:\testrepo\pycharm_sanity/main.py; avoided typing into an unknown project.'
        }
    } else {
        $workflowReason = 'No visible PyCharm window was present; avoided backend launch and used lightweight visible UI fallback.'
    }

    if ($pycharmSuitable) {
        $workflowMode = 'PYCHARM_VISIBLE_EXISTING_TARGET'
        $pycharmAttempted = $true
        $title = [string]$safePyCharm[0].title
        Invoke-TimelineCommand -WinArgs @('visible-window-switch', '--target', $title) -OperationType 'foreground_preempt' -Stage 'pycharm_switch' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('target-lock-acquire', '--target-title', $title) -OperationType 'target_lock' -Stage 'pycharm_lock' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('global-screenshot', '--out', (Join-Path $ScreenshotDir 'pycharm_before.png'), '--format', 'png', '--include-metadata', 'true') -OperationType 'global_screenshot' -Stage 'pycharm_screenshot' -AllowedExitCodes @(0, 1) -EvidenceRef (Join-Path $ScreenshotDir 'pycharm_before.png') | Out-Null
        Invoke-TimelineCommand -WinArgs @('uia-tree', '--title', $title) -OperationType 'uia_tree' -Stage 'pycharm_uia' -AllowedExitCodes @(0, 1) | Out-Null
        $code = "print('DesktopVisual timeline profiling')"
        Invoke-TimelineCommand -WinArgs @('visible-text-input', '--text', $code, '--input-kind', 'code', '--input-method', 'code_editor_keyboard', '--target-title', $title, '--require-target-lock', 'true', '--char-delay-ms', '5') -OperationType 'visible_text_input' -Stage 'pycharm_text_input' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('desktop-hotkey', '--keys', 'CTRL+S', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--target-title', $title, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui') -OperationType 'keyboard_hotkey' -Stage 'pycharm_save' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('global-screenshot', '--out', (Join-Path $ScreenshotDir 'pycharm_after.png'), '--format', 'png', '--include-metadata', 'true') -OperationType 'global_screenshot' -Stage 'pycharm_final_screenshot' -AllowedExitCodes @(0, 1) -EvidenceRef (Join-Path $ScreenshotDir 'pycharm_after.png') | Out-Null
        Invoke-TimelineCommand -WinArgs @('visible-ui-verify', '--global-final-frame', 'true', '--target-lock', 'true', '--expected-output-visible', 'true', '--raw-completed', 'false', '--window-only', 'false') -OperationType 'verification' -Stage 'pycharm_policy_verify' -AllowedExitCodes @(0, 1) | Out-Null
    } else {
        Invoke-TimelineCommand -WinArgs @('visible-show-desktop') -OperationType 'foreground_preempt' -Stage 'fallback_show_desktop' -AllowedExitCodes @(0, 1) | Out-Null
        $beforeShot = Join-Path $ScreenshotDir 'fallback_desktop_before.png'
        $shot = Invoke-TimelineCommand -WinArgs @('global-screenshot', '--out', $beforeShot, '--format', 'png', '--include-metadata', 'true') -OperationType 'global_screenshot' -Stage 'fallback_global_screenshot' -AllowedExitCodes @(0, 1) -EvidenceRef $beforeShot
        $screenX = 120
        $screenY = 120
        if ($shot.Json -and $shot.Json.ok -eq $true) {
            $rect = $shot.Json.data.virtual_screen_rect
            $width = [int]$shot.Json.data.physical_width
            $height = [int]$shot.Json.data.physical_height
            $pixelX = [Math]::Max(20, [Math]::Floor($width * 0.35))
            $pixelY = [Math]::Max(20, [Math]::Floor($height * 0.35))
            $map = Invoke-TimelineCommand -WinArgs @(
                'coordinate-map',
                '--direction', 'pixel-to-screen',
                '--capture-scope', 'global_desktop',
                '--capture-left', "$($rect.left)",
                '--capture-top', "$($rect.top)",
                '--capture-width', "$width",
                '--capture-height', "$height",
                '--pixel-x', "$pixelX",
                '--pixel-y', "$pixelY"
            ) -OperationType 'coordinate_mapping' -Stage 'fallback_coordinate_mapping' -AllowedExitCodes @(0, 1)
            if ($map.Json -and $map.Json.ok -eq $true) {
                $screenX = [int]$map.Json.data.screen_x
                $screenY = [int]$map.Json.data.screen_y
            }
        }
        Invoke-TimelineCommand -WinArgs @('target-lock-acquire', '--allow-global-desktop', 'true') -OperationType 'target_lock' -Stage 'fallback_global_lock' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('desktop-move', '--screen-x', "$screenX", '--screen-y', "$screenY", '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--target-description', 'timeline fallback desktop point', '--coordinate-source', 'timeline_coordinate_mapper', '--allow-global-desktop', 'true', '--humanmode', 'true', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz', '--motion-frame-rate', '165', '--move-duration-ms', '160') -OperationType 'mouse_move' -Stage 'fallback_mouse_move' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('desktop-click', '--screen-x', "$screenX", '--screen-y', "$screenY", '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--target-description', 'timeline fallback desktop click', '--coordinate-source', 'timeline_coordinate_mapper', '--allow-global-desktop', 'true', '--humanmode', 'true', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz', '--motion-frame-rate', '165', '--move-duration-ms', '120') -OperationType 'mouse_click' -Stage 'fallback_mouse_click' -AllowedExitCodes @(0, 1) | Out-Null
        Invoke-TimelineCommand -WinArgs @('desktop-hotkey', '--keys', 'WIN+R', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--latency-profile', 'fast-visible-ui') -OperationType 'keyboard_hotkey' -Stage 'fallback_open_run_dialog' -AllowedExitCodes @(0, 1) | Out-Null
        $runDialog = Wait-ForRunDialog -TimeoutMs 3000
        if ($runDialog -and -not [string]::IsNullOrWhiteSpace($runDialog.Hwnd)) {
            Invoke-TimelineCommand -WinArgs @('visible-text-input', '--text', 'DesktopVisual timeline profiling', '--input-kind', 'command', '--input-method', 'real_keyboard_events', '--target-hwnd', $runDialog.Hwnd, '--require-target-lock', 'true', '--char-delay-ms', '5') -OperationType 'visible_text_input' -Stage 'fallback_visible_text_input' -AllowedExitCodes @(0, 1) | Out-Null
        }
        $afterShot = Join-Path $ScreenshotDir 'fallback_run_dialog_after.png'
        Invoke-TimelineCommand -WinArgs @('global-screenshot', '--out', $afterShot, '--format', 'png', '--include-metadata', 'true') -OperationType 'global_screenshot' -Stage 'fallback_final_screenshot' -AllowedExitCodes @(0, 1) -EvidenceRef $afterShot | Out-Null
        Invoke-TimelineCommand -WinArgs @('visible-ui-verify', '--global-final-frame', 'true', '--target-lock', 'true', '--expected-output-visible', 'true', '--raw-completed', 'false', '--window-only', 'false') -OperationType 'verification' -Stage 'fallback_policy_verify' -AllowedExitCodes @(0, 1) | Out-Null
        if ($runDialog -and -not [string]::IsNullOrWhiteSpace($runDialog.Hwnd)) {
            Invoke-TimelineCommand -WinArgs @('desktop-press', '--key', 'ESC', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--target-hwnd', $runDialog.Hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui') -OperationType 'keyboard_hotkey' -Stage 'fallback_close_run_dialog' -AllowedExitCodes @(0, 1) | Out-Null
        }
    }
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldSafetyConfig
}

$taskEnd = [DateTime]::UtcNow
$totalTaskWall = [int64]($taskEnd - $taskStart).TotalMilliseconds
$entries = @($script:Timeline)
$entries | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $TimelineCsv

$categories = Get-CategoryTotals $entries
$totalRuntime = [int64](($entries | Measure-Object -Property runtime_duration_ms -Sum).Sum)
$totalOverhead = [int64](($entries | Measure-Object -Property orchestration_overhead_ms -Sum).Sum)
$totalFixedSleep = [int64](($entries | Measure-Object -Property fixed_sleep_ms -Sum).Sum)
$totalWaitCondition = [int64](($entries | Measure-Object -Property wait_condition_ms -Sum).Sum)
$slowOps = @($entries | Where-Object { $_.wall_clock_ms -gt 5000 } | Sort-Object wall_clock_ms -Descending)
$slowWaits = @($entries | Where-Object { $_.wait_condition_ms -gt 5000 } | Sort-Object wait_condition_ms -Descending)
$overheadSuspects = @($entries | Where-Object { $_.runtime_duration_ms -lt 500 -and $_.wall_clock_ms -gt 5000 } | Sort-Object orchestration_overhead_ms -Descending)
$fixedSleepCandidates = @($entries | Where-Object { $_.fixed_sleep_ms -gt 1000 } | Sort-Object fixed_sleep_ms -Descending)
$topSlow = @($entries | Sort-Object wall_clock_ms -Descending)
$topOverhead = @($entries | Sort-Object orchestration_overhead_ms -Descending)
$winagentInvocationCount = @($entries | Where-Object { $_.is_winagent_invocation }).Count
$screenshotCount = @($entries | Where-Object { $_.used_global_screenshot }).Count
$globalScreenshotCount = @($entries | Where-Object { $_.used_global_screenshot }).Count
$uiaCallCount = @($entries | Where-Object { $_.operation_type -eq 'uia_tree' }).Count
$vlmCallCount = @($entries | Where-Object { $_.operation_type -like 'vlm_*' }).Count
$powershellWrapperCount = $winagentInvocationCount
$avgClick = Average-WallClock $entries @('mouse_click')
$avgScreenshot = Average-WallClock $entries @('global_screenshot')
$avgTextInput = Average-WallClock $entries @('text_input', 'visible_text_input')
$avgVerification = Average-WallClock $entries @('verification')
$topCategory = ($categories.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
$topOperation = ($topSlow | Select-Object -First 1)
$anyIntervalOver5s = $slowOps.Count -gt 0
$branch = ((& git -C $Root branch --show-current) | Out-String).Trim()

$recommendations = @(
    'Use persistent runtime/session batching to reduce per-command process spawn and PowerShell wrapper overhead.',
    'Prefer condition-based waits with explicit evidence over fixed sleeps; no optimization was applied in this run.',
    'Review global screenshot frequency and UIA tree calls if those categories dominate wall-clock time.',
    'Keep visible-first, target lock, foreground preempt, and verification gates intact while optimizing orchestration.'
)

@(
    '# v6.12.1 Continuous Operation Timeline Context',
    '',
    "- branch: $branch",
    '- baseline_commit: c31a21c v6.12.1 fix multiline text input and 165Hz motion pacing',
    "- profiling_only: true",
    "- optimization_applied: false",
    "- workflow_mode: $workflowMode",
    "- workflow_reason: $workflowReason",
    "- pycharm_attempted: $pycharmAttempted",
    "- pycharm_suitable: $pycharmSuitable",
    '- release_path_modified: false',
    '- public_package_generated: false',
    '- github_upload: false'
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'agent_context_digest.md')

@(
    '# Timeline Summary',
    '',
    "- total_task_wall_clock_ms: $totalTaskWall",
    "- total_runtime_internal_ms: $totalRuntime",
    "- total_orchestration_overhead_ms: $totalOverhead",
    "- total_fixed_sleep_ms: $totalFixedSleep",
    "- total_wait_condition_ms: $totalWaitCondition",
    "- winagent_invocation_count: $winagentInvocationCount",
    "- screenshot_count: $screenshotCount",
    "- global_screenshot_count: $globalScreenshotCount",
    "- uia_call_count: $uiaCallCount",
    "- vlm_call_count: $vlmCallCount",
    "- powershell_wrapper_count: $powershellWrapperCount",
    '',
    '## Category Totals',
    '',
    '| category | wall_clock_or_overhead_ms |',
    '| --- | --- |'
) + @($categories.GetEnumerator() | ForEach-Object { "| $($_.Key) | $($_.Value) |" }) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'timeline_summary.md')

@(
    '# Bottleneck Summary',
    '',
    "- Total task wall-clock time: $totalTaskWall ms",
    "- Total Runtime internal time: $totalRuntime ms",
    "- Total orchestration overhead: $totalOverhead ms",
    "- Total fixed sleep time: $totalFixedSleep ms",
    "- Total wait condition time: $totalWaitCondition ms",
    "- Average click wall-clock: $avgClick ms",
    "- Average screenshot wall-clock: $avgScreenshot ms",
    "- Average text input wall-clock: $avgTextInput ms",
    "- Average verification wall-clock: $avgVerification ms",
    "- Number of winagent process invocations: $winagentInvocationCount",
    "- Number of screenshots: $screenshotCount",
    "- Number of global screenshots: $globalScreenshotCount",
    "- Number of UIA calls: $uiaCallCount",
    "- Number of VLM calls: $vlmCallCount",
    "- Number of PowerShell wrappers: $powershellWrapperCount",
    '',
    '## Top 20 Slowest Operations',
    ''
) + (Top-Table $topSlow @('operation_id', 'operation_type', 'stage', 'wall_clock_ms', 'runtime_duration_ms', 'orchestration_overhead_ms', 'result', 'error_code') 20) + @(
    '',
    '## Top 20 Largest Overhead Operations',
    ''
) + (Top-Table $topOverhead @('operation_id', 'operation_type', 'stage', 'wall_clock_ms', 'runtime_duration_ms', 'orchestration_overhead_ms', 'result', 'error_code') 20) + @(
    '',
    '## Suggested Optimization Targets',
    ''
) + ($recommendations | ForEach-Object { "- $_" }) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'bottleneck_summary.md')

@(
    '# Slow Operations Over 5s',
    '',
    "- count: $($slowOps.Count)",
    ''
) + (Top-Table $slowOps @('operation_id', 'operation_type', 'stage', 'wall_clock_ms', 'runtime_duration_ms', 'orchestration_overhead_ms', 'result', 'error_code') 50) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'slow_operations_over_5s.md')

@(
    '# Orchestration Overhead Report',
    '',
    "- total_orchestration_overhead_ms: $totalOverhead",
    "- suspect_rule: runtime_duration_ms < 500 and wall_clock_ms > 5000",
    "- orchestration_overhead_suspects_count: $($overheadSuspects.Count)",
    '',
    'Note: process_startup_overhead_ms and powershell_wrapper_ms are deterministic wrapper estimates from measured overhead; total orchestration overhead is measured exactly as wall-clock minus Runtime duration.',
    ''
) + (Top-Table $overheadSuspects @('operation_id', 'operation_type', 'stage', 'wall_clock_ms', 'runtime_duration_ms', 'orchestration_overhead_ms', 'process_startup_overhead_ms', 'powershell_wrapper_ms') 50) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'orchestration_overhead_report.md')

@(
    '# Fixed Sleep Report',
    '',
    "- total_fixed_sleep_ms: $totalFixedSleep",
    "- fixed_sleep_candidates_count: $($fixedSleepCandidates.Count)",
    "- rule: fixed_sleep_ms > 1000",
    ''
) + (Top-Table $fixedSleepCandidates @('operation_id', 'operation_type', 'stage', 'fixed_sleep_ms', 'wall_clock_ms', 'result') 50) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'fixed_sleep_report.md')

@(
    '# Runtime vs Wall-clock Report',
    '',
    '| metric | value_ms |',
    '| --- | --- |',
    "| total_task_wall_clock_ms | $totalTaskWall |",
    "| total_runtime_internal_ms | $totalRuntime |",
    "| total_orchestration_overhead_ms | $totalOverhead |",
    '',
    '## Operations',
    ''
) + (Top-Table $entries @('operation_id', 'operation_type', 'stage', 'wall_clock_ms', 'runtime_duration_ms', 'orchestration_overhead_ms', 'result', 'error_code') 200) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'runtime_vs_wallclock_report.md')

@(
    '# Optimization Candidates',
    '',
    '- optimization_applied: false',
    '',
    'Suggested next targets, not implemented in this run:',
    ''
) + ($recommendations | ForEach-Object { "- $_" }) + @(
    '',
    "Top bottleneck category: $($topCategory.Key) = $($topCategory.Value) ms",
    "Top bottleneck operation: $($topOperation.operation_id) $($topOperation.operation_type) $($topOperation.wall_clock_ms) ms"
) |
    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'optimization_candidates.md')

@(
    '# Final Status Report',
    '',
    'profiling_only = true',
    'optimization_applied = false',
    'release_path_modified = false',
    'public_package_generated = false',
    'github_upload = false',
    '',
    "workflow_mode = $workflowMode",
    "workflow_reason = $workflowReason",
    "pycharm_attempted = $pycharmAttempted",
    "pycharm_suitable = $pycharmSuitable",
    '',
    "total_task_wall_clock_ms = $totalTaskWall",
    "total_runtime_internal_ms = $totalRuntime",
    "total_orchestration_overhead_ms = $totalOverhead",
    "total_fixed_sleep_ms = $totalFixedSleep",
    "total_wait_condition_ms = $totalWaitCondition",
    '',
    "slow_operations_over_5s_count = $($slowOps.Count)",
    "fixed_sleep_candidates_count = $($fixedSleepCandidates.Count)",
    "winagent_invocation_count = $winagentInvocationCount",
    "global_screenshot_count = $globalScreenshotCount",
    "uia_call_count = $uiaCallCount",
    "vlm_call_count = $vlmCallCount",
    '',
    "top_bottleneck_category = $($topCategory.Key)",
    "top_bottleneck_operation = $($topOperation.operation_id) $($topOperation.operation_type) $($topOperation.wall_clock_ms)ms",
    "any_operation_interval_over_5s = $anyIntervalOver5s",
    "recommendation_summary = $($recommendations -join ' / ')",
    '',
    'decision = PROFILE_COMPLETE'
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'final_status_report.md')

@(
    '# Evidence Index',
    '',
    '- agent_context_digest.md',
    '- operation_timeline.jsonl',
    '- operation_timeline.csv',
    '- timeline_summary.md',
    '- bottleneck_summary.md',
    '- slow_operations_over_5s.md',
    '- orchestration_overhead_report.md',
    '- fixed_sleep_report.md',
    '- runtime_vs_wallclock_report.md',
    '- optimization_candidates.md',
    '- final_status_report.md',
    '- command_output/',
    '- screenshots/',
    '- timeline_safety.conf'
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir 'evidence_index.md')

Write-Host "PROFILE_COMPLETE operation_timeline=$TimelineJsonl total_wall_clock_ms=$totalTaskWall winagent_invocations=$winagentInvocationCount slow_ops_over_5s=$($slowOps.Count)"
exit 0
