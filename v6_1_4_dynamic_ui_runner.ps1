param(
    [string]$Root = '',
    [switch]$SkipBuild,
    [switch]$StateGuardOnly
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactLeaf = if ($StateGuardOnly) { 'dev6.1.4_dynamic_app_web_click_accuracy_state_guard' } else { 'dev6.1.4_dynamic_app_web_click_accuracy_rerun' }
$ArtifactRoot = Join-Path $Root "artifacts\$ArtifactLeaf"
$RawRoot = Join-Path $ArtifactRoot 'raw'
$RawCasesRoot = Join-Path $RawRoot 'cases'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

$CaseIds = if ($StateGuardOnly) {
    @(
        'v6_1_4_wrong_context_negative_guard',
        'v6_1_4_baseline_regression_once'
    )
} else {
    @(
        'v6_1_4_pycharm_dynamic_coding_run',
        'v6_1_4_wechat_file_transfer_assistant_send',
        'v6_1_4_qq_mail_web_compose_send',
        'v6_1_4_baseline_regression_once'
    )
}

$script:EmergencyStopTriggered = $false
$script:RunnerFindings = New-Object System.Collections.Generic.List[object]
$script:RunStartedAt = Get-Date
$script:GlobalTimeoutSec = 45 * 60
$script:StepTimeoutSec = 60
$script:HeartbeatIntervalSec = 15
$script:CurrentCaseContext = $null
$script:CurrentCaseStartedAt = $null
$script:CurrentCaseTimeoutSec = 0
$script:CurrentStep = ''
$script:LastObserveTime = Get-Date
$script:LastActionTime = Get-Date
$script:LastLogTime = Get-Date
$script:LastError = ''
$script:WaitingReason = ''
$script:StopFlagPath = Join-Path $ArtifactRoot 'STOP_REQUESTED.flag'
$script:EmergencyStopDebounceMs = 300
$script:LastEmergencyStopTriage = $null
$script:LastContextGuardResult = $null

function ConvertTo-ProcessArgument([string]$Arg) {
    if ($null -eq $Arg) { return '""' }
    $s = [string]$Arg
    if ($s.Length -eq 0) { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    $result = '"'
    $slashes = 0
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
        } elseif ($ch -eq '"') {
            if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
            $result += '\"'
            $slashes = 0
        } else {
            if ($slashes -gt 0) { $result += ('\' * $slashes) }
            $slashes = 0
            $result += $ch
        }
    }
    if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
    $result += '"'
    return $result
}

function ConvertTo-ProcessArgumentLine([string[]]$Arguments) {
    return (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
}

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Clear-CaseDir([string]$Path, [string]$AllowedRoot) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullAllowed = [System.IO.Path]::GetFullPath($AllowedRoot)
    if (-not $fullPath.StartsWith($fullAllowed, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear evidence path outside raw cases root: $fullPath"
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    Ensure-Dir $Path
}

function Write-JsonLine([string]$Path, $Object) {
    ($Object | ConvertTo-Json -Depth 100 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
    $script:LastLogTime = Get-Date
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-JsonPathValue($Object, [string[]]$Path) {
    $current = $Object
    foreach ($part in $Path) {
        if ($null -eq $current) { return $null }
        $property = $current.PSObject.Properties[$part]
        if ($null -eq $property) { return $null }
        $current = $property.Value
    }
    return $current
}

function Get-StructuredEmergencyStopCode($Parsed) {
    if ($null -eq $Parsed) { return '' }
    $paths = @(
        @('error_code'),
        @('code'),
        @('stop_reason'),
        @('error','code'),
        @('failure','error_code'),
        @('data','error_code'),
        @('data','code'),
        @('data','stop_reason'),
        @('data','human_action_result','error_code')
    )
    foreach ($path in $paths) {
        $value = Get-JsonPathValue $Parsed $path
        if ($null -eq $value) { continue }
        $text = [string]$value
        if ($text -eq 'EMERGENCY_STOP' -or $text -eq 'USER_INTERRUPTION') {
            return $text
        }
    }
    return ''
}

function Get-DesktopShortcut([string[]]$Names) {
    $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Select-Object -Unique
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($item in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue) {
            foreach ($name in $Names) {
                if ($item.BaseName -like "*$name*" -or $item.Name -like "*$name*") {
                    return $item.FullName
                }
            }
        }
    }
    return ''
}

function Test-EmergencyStopPressed {
    if (-not ('DesktopVisualKeyState' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DesktopVisualKeyState {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
'@
    }
    return (([DesktopVisualKeyState]::GetAsyncKeyState(0x7B) -band 0x8000) -ne 0)
}

function New-EmergencyStopTriage([bool]$Confirmed, [string]$Source, [string]$Step, [int]$KeyDownDurationMs, [bool]$DebouncePassed, [bool]$StopFlagExists, [bool]$FalsePositiveSuspected) {
    $now = Get-Date
    $fg = Get-ForegroundWindowSummary
    [pscustomobject]@{
        timestamp = $now.ToString('o')
        emergency_stop_confirmed = $Confirmed
        emergency_stop_source = $Source
        emergency_stop_key = if ($Source -eq 'keyboard') { 'F12' } else { '' }
        emergency_stop_detected_at = if ($Confirmed) { $now.ToString('o') } else { '' }
        foreground_window_when_stop = $fg
        key_down_duration_ms = $KeyDownDurationMs
        debounce_threshold_ms = $script:EmergencyStopDebounceMs
        debounce_passed = $DebouncePassed
        stop_flag_path = $script:StopFlagPath
        stop_flag_exists = $StopFlagExists
        false_positive_suspected = $FalsePositiveSuspected
        step = $Step
    }
}

function Write-EmergencyStopTriage($Ctx, $Triage) {
    Ensure-Dir $RawRoot
    Write-JsonLine (Join-Path $RawRoot 'emergency_stop_triage.jsonl') $Triage
    if ($Ctx -and (Test-Path -LiteralPath $Ctx.Dir)) {
        Write-JsonLine (Join-Path $Ctx.Dir 'emergency_stop_triage.jsonl') $Triage
    }
}

function Test-EmergencyStopSignal($Ctx, [string]$Step) {
    $stopFlagExists = Test-Path -LiteralPath $script:StopFlagPath
    if ($stopFlagExists) {
        return (New-EmergencyStopTriage $true 'stop_flag' $Step 0 $true $true $false)
    }

    if (-not (Test-EmergencyStopPressed)) {
        return (New-EmergencyStopTriage $false 'none' $Step 0 $false $false $false)
    }

    $started = Get-Date
    $elapsedMs = 0
    while ($elapsedMs -lt $script:EmergencyStopDebounceMs) {
        Start-Sleep -Milliseconds 50
        $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
        if (-not (Test-EmergencyStopPressed)) {
            return (New-EmergencyStopTriage $false 'keyboard' $Step $elapsedMs $false $false $true)
        }
    }

    return (New-EmergencyStopTriage $true 'keyboard' $Step $elapsedMs $true $false $false)
}

function Get-ForegroundWindowSummary {
    if (-not ('DesktopVisualWindowProbe' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DesktopVisualWindowProbe {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int count);
}
'@
    }
    $hwnd = [DesktopVisualWindowProbe]::GetForegroundWindow()
    $title = ''
    if ($hwnd -ne [IntPtr]::Zero) {
        $sb = New-Object System.Text.StringBuilder 512
        [void][DesktopVisualWindowProbe]::GetWindowTextW($hwnd, $sb, $sb.Capacity)
        $title = $sb.ToString()
    }
    [pscustomobject]@{ hwnd = $hwnd.ToInt64(); title = $title }
}

function Write-Heartbeat($Ctx, [string]$Step, [string]$Reason) {
    $now = Get-Date
    $fg = Get-ForegroundWindowSummary
    $caseId = if ($Ctx) { $Ctx.CaseId } elseif ($script:CurrentCaseContext) { $script:CurrentCaseContext.CaseId } else { '' }
    $caseElapsed = if ($script:CurrentCaseStartedAt) { [int]($now - $script:CurrentCaseStartedAt).TotalSeconds } else { 0 }
    $record = [pscustomobject]@{
        timestamp = $now.ToString('o')
        current_case = $caseId
        current_step = $Step
        elapsed_sec = [int]($now - $script:RunStartedAt).TotalSeconds
        case_elapsed_sec = $caseElapsed
        case_timeout_sec = $script:CurrentCaseTimeoutSec
        global_timeout_sec = $script:GlobalTimeoutSec
        foreground_window = $fg
        last_observe_time = $script:LastObserveTime.ToString('o')
        last_action_time = $script:LastActionTime.ToString('o')
        last_log_time = $script:LastLogTime.ToString('o')
        last_error = $script:LastError
        waiting_reason = $Reason
        heartbeat_interval_sec = $script:HeartbeatIntervalSec
    }
    $line = $record | ConvertTo-Json -Depth 20 -Compress
    Ensure-Dir $RawRoot
    Add-Content -LiteralPath (Join-Path $RawRoot 'heartbeat.jsonl') -Value $line -Encoding UTF8
    if ($Ctx -and (Test-Path -LiteralPath $Ctx.Dir)) {
        Add-Content -LiteralPath (Join-Path $Ctx.Dir 'heartbeat.jsonl') -Value $line -Encoding UTF8
    }
    $script:LastLogTime = $now
}

function Assert-RunBudget($Ctx, [string]$Step) {
    $now = Get-Date
    if (($now - $script:RunStartedAt).TotalSeconds -gt $script:GlobalTimeoutSec) {
        $script:LastError = 'GLOBAL_TIMEOUT'
        Write-Heartbeat $Ctx $Step 'global_timeout'
        throw "GLOBAL_TIMEOUT"
    }
    if ($Ctx -and $script:CurrentCaseStartedAt -and $script:CurrentCaseTimeoutSec -gt 0 -and
        (($now - $script:CurrentCaseStartedAt).TotalSeconds -gt $script:CurrentCaseTimeoutSec)) {
        $script:LastError = 'CASE_TIMEOUT'
        Write-Heartbeat $Ctx $Step 'case_timeout'
        throw "CASE_TIMEOUT:$($Ctx.CaseId):$Step"
    }
    if (($now - $script:LastLogTime).TotalSeconds -gt 60) {
        $script:LastError = 'FAIL_NO_PROGRESS'
        Write-Heartbeat $Ctx $Step 'no_progress_timeout'
        throw "FAIL_NO_PROGRESS:$($Ctx.CaseId):$Step"
    }
}

function Start-Case($Ctx, [int]$TimeoutSec) {
    $script:CurrentCaseContext = $Ctx
    $script:CurrentCaseStartedAt = Get-Date
    $script:CurrentCaseTimeoutSec = $TimeoutSec
    $script:CurrentStep = 'case_started'
    $script:LastObserveTime = Get-Date
    $script:LastActionTime = Get-Date
    $script:LastLogTime = Get-Date
    $script:LastError = ''
    $script:WaitingReason = 'case_started'
    Write-Heartbeat $Ctx 'case_started' 'case_started'
}

function Stop-Case($Ctx) {
    if ($Ctx) { Write-Heartbeat $Ctx 'case_finished' 'case_finished' }
    $script:CurrentCaseContext = $null
    $script:CurrentCaseStartedAt = $null
    $script:CurrentCaseTimeoutSec = 0
    $script:CurrentStep = ''
}

function Assert-NoEmergencyStop($Ctx, [string]$Step) {
    $triage = Test-EmergencyStopSignal $Ctx $Step
    if ($triage.false_positive_suspected) {
        $script:LastEmergencyStopTriage = $triage
        Write-EmergencyStopTriage $Ctx $triage
        if ($Ctx) {
            Add-CaseEvent $Ctx 'SUSPECTED_STOP_SIGNAL_IGNORED' $triage
        }
        return
    }
    if ($triage.emergency_stop_confirmed) {
        $script:LastEmergencyStopTriage = $triage
        $script:EmergencyStopTriggered = $true
        Write-EmergencyStopTriage $Ctx $triage
        if ($Ctx) {
            Add-CaseEvent $Ctx 'USER_INTERRUPTION' $triage
            Save-RawCaseStatus $Ctx ([ordered]@{
                case_id = $Ctx.CaseId
                runner_outcome = 'EMERGENCY_STOP'
                environment_blocking = $true
                stop_reason = 'USER_INTERRUPTION'
                emergency_stop_triggered = $true
                false_positive_stop_detected = $false
                emergency_stop_source = $triage.emergency_stop_source
                emergency_stop_key = $triage.emergency_stop_key
                emergency_stop_detected_at = $triage.emergency_stop_detected_at
                foreground_window_when_stop = $triage.foreground_window_when_stop
                key_down_duration_ms = $triage.key_down_duration_ms
                debounce_passed = $triage.debounce_passed
                stop_flag_path = $triage.stop_flag_path
                stop_flag_exists = $triage.stop_flag_exists
                false_positive_suspected = $triage.false_positive_suspected
                runner_does_not_decide_pass = $true
            })
        }
        throw "EMERGENCY_STOP"
    }
}

function New-RawCase([string]$CaseId) {
    $dir = Join-Path $RawCasesRoot $CaseId
    Clear-CaseDir $dir $RawCasesRoot
    foreach ($name in @('screenshots','overlays','crops')) {
        Ensure-Dir (Join-Path $dir $name)
    }
    foreach ($file in @(
        'task_events.jsonl',
        'action_trace.jsonl',
        'locator_trace.jsonl',
        'scroll_trace.jsonl',
        'adaptive_loop_trace.jsonl',
        'human_action_results.jsonl',
        'focus_trace.jsonl',
        'offset_trace.jsonl',
        'context_trace.jsonl',
        'raw_command_log.jsonl',
        'raw_stdout.jsonl',
        'heartbeat.jsonl'
    )) {
        Set-Content -LiteralPath (Join-Path $dir $file) -Value '' -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $dir 'raw_stderr.log') -Value '' -Encoding UTF8
    [pscustomobject]@{
        CaseId = $CaseId
        Dir = $dir
        CommandLog = Join-Path $dir 'raw_command_log.jsonl'
        StdoutLog = Join-Path $dir 'raw_stdout.jsonl'
        ScreenshotDir = Join-Path $dir 'screenshots'
        OverlayDir = Join-Path $dir 'overlays'
        CropDir = Join-Path $dir 'crops'
    }
}

function Add-CaseEvent($Ctx, [string]$Event, $Details) {
    Write-JsonLine (Join-Path $Ctx.Dir 'task_events.jsonl') ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        case_id = $Ctx.CaseId
        event = $Event
        details = $Details
        verified_by_runner = $false
    })
}

function Get-ExpectedValue([hashtable]$Expected, [string]$Name, $Default = $null) {
    if ($Expected -and $Expected.ContainsKey($Name)) { return $Expected[$Name] }
    return $Default
}

function Get-ExpectedArray([hashtable]$Expected, [string]$Name) {
    $value = Get-ExpectedValue $Expected $Name @()
    if ($null -eq $value) { return @() }
    if ($value -is [array]) { return @($value) }
    return @($value)
}

function Add-RuntimeGuardArgs([string[]]$Args, $Ctx, [string]$Step, [hashtable]$Expected, $Candidate = $null, [string]$ActionKind = 'action', [string]$ExpectedFocusMarker = '') {
    $out = @($Args)
    if (-not $Expected) { return $out }
    $processPattern = [string](Get-ExpectedValue $Expected 'expected_process_pattern' '')
    $titlePattern = [string](Get-ExpectedValue $Expected 'expected_title_pattern' '')
    if (-not [string]::IsNullOrWhiteSpace($processPattern)) { $out += @('--expected-process-pattern', $processPattern) }
    if (-not [string]::IsNullOrWhiteSpace($titlePattern)) { $out += @('--expected-title-pattern', $titlePattern) }
    foreach ($marker in (Get-ExpectedArray $Expected 'required_markers')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$marker)) { $out += @('--required-marker', [string]$marker) }
    }
    foreach ($pattern in (Get-ExpectedArray $Expected 'wrong_page_patterns')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pattern)) { $out += @('--wrong-page-pattern', [string]$pattern) }
    }
    foreach ($pattern in (Get-ExpectedArray $Expected 'active_protection_patterns')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pattern)) { $out += @('--active-protection-pattern', [string]$pattern) }
    }
    foreach ($pattern in (Get-ExpectedArray $Expected 'automation_patterns')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pattern)) { $out += @('--automation-pattern', [string]$pattern) }
    }
    foreach ($pattern in (Get-ExpectedArray $Expected 'loading_or_overlay_patterns')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pattern)) { $out += @('--loading-overlay-pattern', [string]$pattern) }
    }
    if ($Candidate -and (Test-Rect $Candidate.rect)) {
        $out += @('--require-target-rect', 'true', '--require-target-current', 'true', '--require-target-unique', 'true', '--require-target-inside-viewport', 'true')
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedFocusMarker)) {
        $out += @('--expected-focus-marker', $ExpectedFocusMarker)
    }
    $out += @(
        '--stop-on-wrong-context', 'true',
        '--browser-normalize-before-action', 'true',
        '--browser-normalize-mode', 'conservative',
        '--guard-result-json', (Join-Path $Ctx.Dir "$Step.runtime_context_guard.json")
    )
    return $out
}

function Test-AnyRegex([string]$Text, [string[]]$Patterns) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    foreach ($pattern in $Patterns) {
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and $Text -match $pattern) { return $true }
    }
    return $false
}

function Get-ObjValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-RectInside($Rect, $Viewport) {
    if (-not $Rect -or -not $Viewport) { return $false }
    try {
        return (
            [int]$Rect.left -ge [int]$Viewport.left -and
            [int]$Rect.top -ge [int]$Viewport.top -and
            [int]$Rect.right -le [int]$Viewport.right -and
            [int]$Rect.bottom -le [int]$Viewport.bottom -and
            [int]$Rect.right -gt [int]$Rect.left -and
            [int]$Rect.bottom -gt [int]$Rect.top
        )
    } catch {
        return $false
    }
}

function Write-ContextTrace($Ctx, $Record) {
    if (-not $Ctx) { return }
    Write-JsonLine (Join-Path $Ctx.Dir 'context_trace.jsonl') $Record
}

function Stop-WrongContext($Ctx, [string]$Step, [string]$Code, [string]$Reason, $Guard) {
    $script:LastContextGuardResult = $Guard
    Add-CaseEvent $Ctx 'action_precondition_stop' @{
        step = $Step
        stop_code = $Code
        reason = $Reason
        guard = $Guard
    }
    Add-RunnerFinding $Code $Reason $Ctx.CaseId
    throw $Code
}

function Verify-ExpectedContext($Ctx, [string]$Step, [hashtable]$Expected, $Candidate = $null, [string]$ActionKind = 'action', [bool]$StopOnFailure = $true) {
    if (-not $Expected) {
        return [pscustomobject]@{ ok = $true; stop_code = ''; reason = 'no expected context declared' }
    }

    Assert-NoEmergencyStop $Ctx $Step
    Assert-RunBudget $Ctx $Step

    $active = Invoke-WinAgentRaw $Ctx "$Step-context-active-window" @('active-window') -AllowFailure
    $activeData = if ($active.Parsed -and $active.Parsed.data) { $active.Parsed.data } else { $null }
    $activeTitle = if ($activeData -and $activeData.title) { [string]$activeData.title } else { '' }
    $activeProcess = if ($activeData -and $activeData.process_name) { [string]$activeData.process_name } else { '' }
    $windowRect = if ($activeData -and $activeData.rect) { $activeData.rect } else { $null }
    $clientRect = if ($activeData -and $activeData.client_rect) { $activeData.client_rect } else { $windowRect }
    $viewportRect = if ($activeData -and $activeData.viewport_rect) { $activeData.viewport_rect } else { $clientRect }

    $titleForRead = $activeTitle
    $expectedTitle = [string](Get-ExpectedValue $Expected 'read_title' '')
    if (-not [string]::IsNullOrWhiteSpace($expectedTitle)) { $titleForRead = $expectedTitle }
    $read = if (-not [string]::IsNullOrWhiteSpace($titleForRead)) {
        Invoke-WinAgentRaw $Ctx "$Step-context-read-window-text" @('read-window-text','--title',$titleForRead) -AllowFailure
    } else { $null }
    $readText = Get-WindowTextFromResult $read
    $shot = if (-not [string]::IsNullOrWhiteSpace($titleForRead)) { Capture-WindowScreenshot $Ctx $titleForRead "$Step-context" } else { '' }
    $joined = @($activeTitle, $activeProcess, $readText) -join "`n"

    $stopCode = ''
    $reason = ''
    $expectedApp = [string](Get-ExpectedValue $Expected 'expected_app' '')
    $processPattern = [string](Get-ExpectedValue $Expected 'expected_process_pattern' '')
    $titlePattern = [string](Get-ExpectedValue $Expected 'expected_title_pattern' '')
    $requiredMarkers = Get-ExpectedArray $Expected 'required_markers'
    $wrongPagePatterns = Get-ExpectedArray $Expected 'wrong_page_patterns'
    if ($wrongPagePatterns.Count -eq 0) {
        $wrongPagePatterns = @('Google\s+Search|Google 搜索|New Tab|新建标签页|搜索结果|Search results|chrome browser for testing.*搜索| - 搜索 - ')
    }
    $activeProtectionPatterns = @('登录|扫码|验证码|安全验证|人机验证|账号风险|风险|verify you are human|captcha|reCAPTCHA|Turnstile')
    $automationPatterns = @('automation detected|automated traffic|bot challenge|browser is being controlled by automated test software|WebDriver detected')
    $loadingPatterns = @('正在加载|Loading\.\.\.|Please wait|modal blocker|overlay blocker')

    $foregroundOk = $true
    if (-not [string]::IsNullOrWhiteSpace($processPattern) -and $activeProcess -notmatch $processPattern) { $foregroundOk = $false }
    if (-not [string]::IsNullOrWhiteSpace($titlePattern) -and $activeTitle -notmatch $titlePattern) { $foregroundOk = $false }

    $markersOk = $true
    foreach ($marker in $requiredMarkers) {
        if ([string]::IsNullOrWhiteSpace([string]$marker)) { continue }
        if ($joined -notmatch [regex]::Escape([string]$marker) -and $joined -notmatch [string]$marker) {
            $markersOk = $false
            break
        }
    }

    $wrongPage = Test-AnyRegex $joined $wrongPagePatterns
    $activeProtection = Test-AnyRegex $joined $activeProtectionPatterns
    $automationDetected = Test-AnyRegex $joined $automationPatterns
    $loadingBlocking = Test-AnyRegex $joined $loadingPatterns

    $targetRect = if ($Candidate -and $Candidate.rect) { $Candidate.rect } else { $null }
    $requireCandidate = [bool](Get-ExpectedValue $Expected 'require_candidate' $false)
    $targetFromCurrentObserve = $false
    if ($Candidate) {
        $source = [string](Get-ObjValue $Candidate 'source')
        $targetFromCurrentObserve = (-not [string]::IsNullOrWhiteSpace($source) -and $source -notmatch 'hardcoded|manual_fixed')
    }
    $targetUnique = $true
    foreach ($countName in @('match_count','candidate_count','candidates_count','same_text_candidate_count')) {
        $count = Get-ObjValue $Candidate $countName
        if ($null -ne $count) {
            try { if ([int]$count -gt 1) { $targetUnique = $false } } catch {}
        }
    }
    $ambiguous = Get-ObjValue $Candidate 'ambiguous'
    if ($ambiguous -eq $true) { $targetUnique = $false }
    $allowTargetOutsideViewport = [bool](Get-ExpectedValue $Expected 'allow_target_outside_viewport' $false)
    $targetInsideViewport = if ($allowTargetOutsideViewport) { $true } elseif ($targetRect) { Test-RectInside $targetRect $viewportRect } else { -not $requireCandidate }

    if ($activeProtection) {
        $stopCode = 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'
        $reason = 'login/security/human verification marker detected before action'
    } elseif ($automationDetected) {
        $stopCode = 'STOP_AUTOMATION_DETECTED'
        $reason = 'automation/bot challenge marker detected before action'
    } elseif (-not $foregroundOk) {
        $stopCode = 'STOP_FOREGROUND_CHANGED'
        $reason = "foreground did not match expected app $expectedApp"
    } elseif (-not $markersOk) {
        $stopCode = [string](Get-ExpectedValue $Expected 'marker_missing_stop_code' 'STOP_WRONG_CONTEXT')
        $reason = 'required page/app marker missing before action'
    } elseif ($wrongPage -and -not [bool](Get-ExpectedValue $Expected 'allow_wrong_page' $false)) {
        $stopCode = [string](Get-ExpectedValue $Expected 'wrong_page_stop_code' 'STOP_WRONG_PAGE')
        $reason = 'wrong page marker detected before action'
    } elseif ($loadingBlocking) {
        $stopCode = 'STOP_LOADING_OR_OVERLAY_BLOCKING'
        $reason = 'loading/overlay blocker detected before action'
    } elseif ($requireCandidate -and -not $targetRect) {
        $stopCode = 'STOP_TARGET_STALE'
        $reason = 'target rect missing before action'
    } elseif ($requireCandidate -and -not $targetFromCurrentObserve) {
        $stopCode = 'STOP_TARGET_STALE'
        $reason = 'target rect was not sourced from current observe/locator evidence'
    } elseif ($requireCandidate -and -not $targetUnique) {
        $stopCode = 'STOP_TARGET_NOT_UNIQUE'
        $reason = 'target candidate was ambiguous before action'
    } elseif (-not $targetInsideViewport) {
        $stopCode = 'STOP_TARGET_OUTSIDE_VIEWPORT'
        $reason = 'target rect is outside current viewport/client rect'
    }

    $record = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        case_id = if ($Ctx) { $Ctx.CaseId } else { '' }
        step = $Step
        action_kind = $ActionKind
        expected_app = $expectedApp
        expected_process_pattern = $processPattern
        expected_title_pattern = $titlePattern
        required_markers = @($requiredMarkers)
        foreground_title = $activeTitle
        foreground_process = $activeProcess
        foreground_ok = $foregroundOk
        markers_ok = $markersOk
        wrong_page_detected = $wrongPage
        active_protection_detected = $activeProtection
        automation_detected = $automationDetected
        loading_or_overlay_blocking = $loadingBlocking
        target_rect = $targetRect
        target_rect_source = if ($Candidate) { [string](Get-ObjValue $Candidate 'source') } else { '' }
        target_from_current_observe = $targetFromCurrentObserve
        target_unique = $targetUnique
        target_inside_viewport = $targetInsideViewport
        screenshot = $shot
        screenshot_stale = $false
        window_rect = $windowRect
        client_rect = $clientRect
        viewport_rect = $viewportRect
        ok = [string]::IsNullOrWhiteSpace($stopCode)
        stop_code = $stopCode
        reason = $reason
    }
    Write-ContextTrace $Ctx ([pscustomobject]$record)

    $result = [pscustomobject]$record
    $script:LastContextGuardResult = $result
    if (-not $result.ok -and $StopOnFailure) {
        Stop-WrongContext $Ctx $Step $result.stop_code $result.reason $result
    }
    return $result
}

function Verify-ActionPrecondition($Ctx, [string]$Step, [hashtable]$Expected, $Candidate = $null, [string]$ActionKind = 'action', [bool]$StopOnFailure = $true) {
    Verify-ExpectedContext $Ctx $Step $Expected $Candidate $ActionKind $StopOnFailure
}

function Save-RawCaseStatus($Ctx, $Status) {
    $Status.generated_at = (Get-Date).ToString('o')
    $Status.runner_does_not_decide_pass = $true
    $Status | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $Ctx.Dir 'raw_case_status.json') -Encoding UTF8
}

function Add-RunnerFinding([string]$Code, [string]$Message, [string]$CaseId = '') {
    $script:RunnerFindings.Add([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        code = $Code
        message = $Message
        case_id = $CaseId
    }) | Out-Null
}

function Mark-CommandActivity([string[]]$CommandArgs) {
    if (-not $CommandArgs -or $CommandArgs.Count -eq 0) { return }
    $cmd = [string]$CommandArgs[0]
    if ($cmd -in @('windows','active-window','mouse-position','screenshot','read-window-text','read-region-text','observe','observe2','locate','adaptive-locate','scroll-and-locate','adaptive-scroll')) {
        $script:LastObserveTime = Get-Date
    }
    if ($cmd -like 'desktop-*' -or $cmd -in @('click','double-click','right-click','scroll','drag','press','hotkey','type','adaptive-click','adaptive-double-click','adaptive-type')) {
        $script:LastActionTime = Get-Date
    }
}

function Invoke-ProcessWithTimeout($Ctx, [string]$Step, [string]$FilePath, [string[]]$Arguments, [string]$Stdout, [string]$Stderr, [int]$TimeoutSec) {
    Assert-RunBudget $Ctx $Step
    $script:CurrentStep = $Step
    $script:WaitingReason = 'running_command'
    Write-Heartbeat $Ctx $Step 'command_start'
    $argLine = ConvertTo-ProcessArgumentLine $Arguments
    $started = Get-Date
    $timedOut = $false
    $exit = 999
    $proc = $null
    $stdoutTask = $null
    $stderrTask = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $argLine
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $nextHeartbeat = (Get-Date).AddSeconds($script:HeartbeatIntervalSec)
        while (-not $proc.HasExited) {
            Assert-NoEmergencyStop $Ctx $Step
            Assert-RunBudget $Ctx $Step
            $now = Get-Date
            if (($now - $started).TotalSeconds -gt $TimeoutSec) {
                $timedOut = $true
                $script:LastError = "STEP_TIMEOUT:$Step"
                try { $proc.Kill() } catch {}
                try { $proc.WaitForExit(3000) | Out-Null } catch {}
                break
            }
            if ($now -ge $nextHeartbeat) {
                Write-Heartbeat $Ctx $Step 'running_command'
                $nextHeartbeat = $now.AddSeconds($script:HeartbeatIntervalSec)
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $timedOut) {
            try { $proc.WaitForExit(3000) | Out-Null } catch {}
            $proc.Refresh()
            $exit = [int]$proc.ExitCode
        } else {
            $exit = 124
        }
        $stdoutText = if ($stdoutTask) { [string]$stdoutTask.Result } else { '' }
        $stderrText = if ($stderrTask) { [string]$stderrTask.Result } else { '' }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Stdout, $stdoutText, $utf8NoBom)
        [System.IO.File]::WriteAllText($Stderr, $stderrText, $utf8NoBom)
    } catch {
        $script:LastError = $_.Exception.Message
        if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch {} }
        throw
    } finally {
        if ($proc) {
            try { $proc.Dispose() } catch {}
        }
        Write-Heartbeat $Ctx $Step ($(if ($timedOut) { 'step_timeout' } else { 'command_finished' }))
    }
    $ended = Get-Date
    [pscustomobject]@{
        ExitCode = $exit
        TimedOut = $timedOut
        Started = $started
        Ended = $ended
        DurationSec = [Math]::Round(($ended - $started).TotalSeconds, 3)
    }
}

function Save-CaseFailureStatus($Ctx, [string]$Outcome, [string]$Reason, [bool]$EnvironmentBlocking = $false) {
    if (-not $Ctx) { return }
    $statusPath = Join-Path $Ctx.Dir 'raw_case_status.json'
    if (Test-Path -LiteralPath $statusPath) { return }
    $triage = $script:LastEmergencyStopTriage
    Save-RawCaseStatus $Ctx ([ordered]@{
        case_id = $Ctx.CaseId
        runner_outcome = $Outcome
        environment_blocking = $EnvironmentBlocking
        stop_reason = $Reason
        heartbeat_timeout_enforced = $true
        step_timeout_sec = $script:StepTimeoutSec
        case_timeout_sec = $script:CurrentCaseTimeoutSec
        global_timeout_sec = $script:GlobalTimeoutSec
        emergency_stop_triggered = $script:EmergencyStopTriggered
        false_positive_stop_detected = if ($triage) { [bool]$triage.false_positive_suspected } else { $false }
        emergency_stop_source = if ($triage) { [string]$triage.emergency_stop_source } else { '' }
        emergency_stop_key = if ($triage) { [string]$triage.emergency_stop_key } else { '' }
        emergency_stop_detected_at = if ($triage) { [string]$triage.emergency_stop_detected_at } else { '' }
        foreground_window_when_stop = if ($triage) { $triage.foreground_window_when_stop } else { $null }
        key_down_duration_ms = if ($triage) { [int]$triage.key_down_duration_ms } else { 0 }
        debounce_passed = if ($triage) { [bool]$triage.debounce_passed } else { $false }
        stop_flag_path = $script:StopFlagPath
        stop_flag_exists = Test-Path -LiteralPath $script:StopFlagPath
        false_positive_suspected = if ($triage) { [bool]$triage.false_positive_suspected } else { $false }
        last_context_guard_result = $script:LastContextGuardResult
        wrong_context_detected = if ($script:LastContextGuardResult) { -not [bool]$script:LastContextGuardResult.ok } else { $false }
        continued_action_after_wrong_context = $false
    })
}

function Invoke-WinAgentRaw($Ctx, [string]$Step, [string[]]$CommandArgs, [switch]$AllowFailure, [int]$TimeoutSec = $script:StepTimeoutSec) {
    Assert-NoEmergencyStop $Ctx $Step
    $stdout = Join-Path $Ctx.Dir ("$Step.stdout.log")
    $stderr = Join-Path $Ctx.Dir ("$Step.stderr.log")
    $process = Invoke-ProcessWithTimeout $Ctx $Step $WinAgent $CommandArgs $stdout $stderr $TimeoutSec
    $started = $process.Started
    $ended = $process.Ended
    $exit = $process.ExitCode
    $stdoutText = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw } else { '' }
    $stderrText = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw } else { '' }
    $parsed = $null
    try { $parsed = $stdoutText | ConvertFrom-Json } catch { $parsed = $null }
    Mark-CommandActivity $CommandArgs
    $record = [pscustomobject]@{
        timestamp = $started.ToString('o')
        ended_at = $ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        executable = $WinAgent
        command_args = $CommandArgs
        stdout_path = $stdout
        stderr_path = $stderr
        exit_code = $exit
        duration_sec = $process.DurationSec
        timeout_sec = $TimeoutSec
        timed_out = $process.TimedOut
        parsed_ok = ($null -ne $parsed)
        parsed_command = if ($parsed -and $parsed.command) { $parsed.command } else { '' }
        parsed_ok_field = if ($parsed -and $null -ne $parsed.ok) { [bool]$parsed.ok } else { $false }
    }
    Write-JsonLine $Ctx.CommandLog $record
    Write-JsonLine $Ctx.StdoutLog ([pscustomobject]@{
        timestamp = $ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        stdout_path = $stdout
        stderr_path = $stderr
        stdout_length = $stdoutText.Length
        stderr_length = $stderrText.Length
        parsed_ok = ($null -ne $parsed)
        exit_code = $exit
        timed_out = $process.TimedOut
    })
    Write-JsonLine (Join-Path $Ctx.Dir 'action_trace.jsonl') $record
    if ($parsed -and $parsed.data) {
        if ($parsed.command -eq 'adaptive-locate' -or $parsed.command -eq 'observe2' -or $parsed.command -eq 'locate') {
            Write-JsonLine (Join-Path $Ctx.Dir 'locator_trace.jsonl') ([pscustomobject]@{ step = $Step; data = $parsed.data })
        }
        if ($parsed.command -eq 'scroll-and-locate' -or $parsed.command -eq 'adaptive-scroll' -or $parsed.command -eq 'scroll') {
            Write-JsonLine (Join-Path $Ctx.Dir 'scroll_trace.jsonl') ([pscustomobject]@{ step = $Step; data = $parsed.data })
        }
        if ($parsed.data.human_action_result) {
            Write-JsonLine (Join-Path $Ctx.Dir 'human_action_results.jsonl') ([pscustomobject]@{ step = $Step; human_action_result = $parsed.data.human_action_result })
        }
        if ($parsed.data.foreground_before -or $parsed.data.foreground_after -or $parsed.data.focus_verified) {
            Write-JsonLine (Join-Path $Ctx.Dir 'focus_trace.jsonl') ([pscustomobject]@{ step = $Step; data = $parsed.data })
        }
    }
    $structuredStopCode = Get-StructuredEmergencyStopCode $parsed
    if (-not [string]::IsNullOrWhiteSpace($structuredStopCode)) {
        $triage = Test-EmergencyStopSignal $Ctx $Step
        $triage | Add-Member -NotePropertyName structured_error_code -NotePropertyValue $structuredStopCode -Force
        $triage | Add-Member -NotePropertyName stdout_path -NotePropertyValue $stdout -Force
        $triage | Add-Member -NotePropertyName stderr_path -NotePropertyValue $stderr -Force
        $script:LastEmergencyStopTriage = $triage
        Write-EmergencyStopTriage $Ctx $triage
        if ($triage.emergency_stop_confirmed) {
            $script:EmergencyStopTriggered = $true
            Add-CaseEvent $Ctx 'USER_INTERRUPTION' $triage
            throw "EMERGENCY_STOP"
        }
        Add-CaseEvent $Ctx 'SUSPECTED_STOP_SIGNAL_IGNORED' $triage
    }
    if ($process.TimedOut) {
        Add-CaseEvent $Ctx 'step_timeout' @{ step = $Step; timeout_sec = $TimeoutSec; stdout_path = $stdout; stderr_path = $stderr }
        throw "STEP_TIMEOUT:$($Ctx.CaseId):$Step"
    }
    if ($exit -ne 0 -and -not $AllowFailure) {
        Add-CaseEvent $Ctx 'command_failed_unverified' @{ step = $Step; exit_code = $exit; stdout_path = $stdout; stderr_path = $stderr }
    }
    [pscustomobject]@{ ExitCode = $exit; TimedOut = $process.TimedOut; Stdout = $stdoutText; Stderr = $stderrText; Parsed = $parsed; StdoutPath = $stdout; StderrPath = $stderr }
}

function Invoke-PowerShellRaw($Ctx, [string]$Step, [string[]]$Arguments, [switch]$AllowFailure, [int]$TimeoutSec = 900) {
    Assert-NoEmergencyStop $Ctx $Step
    $stdout = Join-Path $Ctx.Dir ("$Step.stdout.log")
    $stderr = Join-Path $Ctx.Dir ("$Step.stderr.log")
    $powershellExe = (Get-Command powershell).Source
    $process = Invoke-ProcessWithTimeout $Ctx $Step $powershellExe $Arguments $stdout $stderr $TimeoutSec
    $started = $process.Started
    $ended = $process.Ended
    $exit = $process.ExitCode
    Write-JsonLine $Ctx.CommandLog ([pscustomobject]@{
        timestamp = $started.ToString('o')
        ended_at = $ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        executable = 'powershell'
        command_args = $Arguments
        stdout_path = $stdout
        stderr_path = $stderr
        exit_code = $exit
        duration_sec = $process.DurationSec
        timeout_sec = $TimeoutSec
        timed_out = $process.TimedOut
        parsed_ok = $false
        parsed_command = ''
        parsed_ok_field = $false
    })
    Write-JsonLine $Ctx.StdoutLog ([pscustomobject]@{
        timestamp = $ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        stdout_path = $stdout
        stderr_path = $stderr
        stdout_length = if (Test-Path -LiteralPath $stdout) { (Get-Content -LiteralPath $stdout -Raw).Length } else { 0 }
        exit_code = $exit
        timed_out = $process.TimedOut
    })
    if ($process.TimedOut) {
        Add-CaseEvent $Ctx 'step_timeout' @{ step = $Step; timeout_sec = $TimeoutSec; stdout_path = $stdout; stderr_path = $stderr }
        throw "STEP_TIMEOUT:$($Ctx.CaseId):$Step"
    }
    if ($exit -ne 0 -and -not $AllowFailure) {
        Add-CaseEvent $Ctx 'powershell_command_failed_unverified' @{ step = $Step; exit_code = $exit; stdout_path = $stdout }
    }
    [pscustomobject]@{ ExitCode = $exit; TimedOut = $process.TimedOut; StdoutPath = $stdout; StderrPath = $stderr }
}

function Capture-WindowScreenshot($Ctx, [string]$Title, [string]$Name) {
    $path = Join-Path $Ctx.ScreenshotDir ($Name + '.bmp')
    Invoke-WinAgentRaw $Ctx "screenshot-$Name" @('screenshot','--title',$Title,'--out',$path) -AllowFailure | Out-Null
    return $path
}

function Show-Desktop($Ctx) {
    Invoke-WinAgentRaw $Ctx 'show-desktop' @('desktop-hotkey','--keys','WIN+M','--permission-mode',$PermissionMode) -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 500
}

function Invoke-DesktopHotkey($Ctx, [string]$Step, [string]$Keys) {
    Assert-NoEmergencyStop $Ctx $Step
    Assert-RunBudget $Ctx $Step
    Invoke-WinAgentRaw $Ctx $Step @('desktop-hotkey','--keys',$Keys,'--permission-mode',$PermissionMode) -AllowFailure
}

function Invoke-DesktopPress($Ctx, [string]$Step, [string]$Key) {
    Assert-NoEmergencyStop $Ctx $Step
    Assert-RunBudget $Ctx $Step
    Invoke-WinAgentRaw $Ctx $Step @('desktop-press','--key',$Key,'--permission-mode',$PermissionMode) -AllowFailure
}

function Invoke-DesktopType($Ctx, [string]$Step, [string]$Text, [int]$DelayMs = 30) {
    Assert-NoEmergencyStop $Ctx $Step
    Assert-RunBudget $Ctx $Step
    Invoke-WinAgentRaw $Ctx $Step @('desktop-type','--text',$Text,'--type-mode','demo-human','--char-delay-ms',[string]$DelayMs,'--permission-mode',$PermissionMode) -AllowFailure
}

function Wait-WindowLike($Ctx, [string]$TitlePattern, [string]$ProcessPattern, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $i = 0
    while ((Get-Date) -lt $deadline) {
        Assert-RunBudget $Ctx "wait-window-$TitlePattern"
        $r = Invoke-WinAgentRaw $Ctx ("windows-$i") @('windows') -AllowFailure
        if ($r.Parsed -and $r.Parsed.windows) {
            $matches = @($r.Parsed.windows | Where-Object {
                ($_.title -like "*$TitlePattern*") -and
                ([string]::IsNullOrWhiteSpace($ProcessPattern) -or $_.process_name -like "*$ProcessPattern*")
            })
            if ($matches.Count -gt 0) { return $matches[0] }
        }
        $i++
        Write-Heartbeat $Ctx "wait-window-$TitlePattern" 'waiting_for_window'
        Start-Sleep -Milliseconds 700
    }
    Add-CaseEvent $Ctx 'FAIL_TIMEOUT_TARGET_NOT_FOUND' @{ target_title = $TitlePattern; process = $ProcessPattern; timeout_sec = $Seconds }
    return $null
}

function Wait-WindowTextContainsAny($Ctx, [string]$Step, [string]$Title, [string[]]$Needles, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $i = 0
    while ((Get-Date) -lt $deadline) {
        Assert-RunBudget $Ctx "$Step-$i"
        $read = Read-WindowText $Ctx "$Step-$i" $Title
        $text = Get-WindowTextFromResult $read
        foreach ($needle in $Needles) {
            if ($text -match [regex]::Escape($needle)) {
                return [pscustomobject]@{ Found = $true; Text = $text; Matched = $needle }
            }
        }
        Write-Heartbeat $Ctx $Step 'waiting_for_text'
        Start-Sleep -Milliseconds 900
        $i++
    }
    return [pscustomobject]@{ Found = $false; Text = ''; Matched = '' }
}

function Invoke-AdaptiveLocate($Ctx, [string]$Step, [string]$Title, [string]$Target, [string]$Role) {
    $args = @('adaptive-locate','--title',$Title,'--target',$Target)
    if (-not [string]::IsNullOrWhiteSpace($Role)) { $args += @('--role',$Role) }
    $r = Invoke-WinAgentRaw $Ctx $Step $args -AllowFailure
    if ($r.Parsed -and $r.Parsed.data -and $r.Parsed.data.ok -eq $true -and $r.Parsed.data.selected_candidate) {
        return $r.Parsed.data.selected_candidate
    }
    return $null
}

function Find-FirstCandidate($Ctx, [string]$StepPrefix, [string]$Title, [string[]]$Targets, [string[]]$Roles) {
    $idx = 0
    foreach ($target in $Targets) {
        foreach ($role in $Roles) {
            $candidate = Invoke-AdaptiveLocate $Ctx "$StepPrefix-$idx" $Title $target $role
            if ($candidate) { return $candidate }
            $idx++
        }
    }
    return $null
}

function Get-SafePointFromCandidate($Candidate) {
    $rect = $Candidate.rect
    $left = [int]$rect.left
    $top = [int]$rect.top
    $right = [int]$rect.right
    $bottom = [int]$rect.bottom
    $x = [int](($left + $right) / 2)
    $y = [int](($top + $bottom) / 2)
    if (($right - $left) -gt 12) { $x = [Math]::Max($left + 6, [Math]::Min($right - 6, $x)) }
    if (($bottom - $top) -gt 12) { $y = [Math]::Max($top + 6, [Math]::Min($bottom - 6, $y)) }
    [pscustomobject]@{ x = $x; y = $y; left = $left; top = $top; right = $right; bottom = $bottom }
}

function Get-CandidateLabel($Candidate, [string]$Fallback) {
    foreach ($name in @('target_id','matched_text','matched_name','target_text','target','name','text','automation_name','label')) {
        if ($Candidate -and $Candidate.$name -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.$name)) {
            return [string]$Candidate.$name
        }
    }
    return $Fallback
}

function Get-CandidateRole($Candidate) {
    foreach ($name in @('role','control_type','type')) {
        if ($Candidate -and $Candidate.$name -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.$name)) {
            return [string]$Candidate.$name
        }
    }
    return ''
}

function Test-RectClose($A, $B, [int]$Tolerance = 2) {
    if (-not $A -or -not $B) { return $false }
    return (([Math]::Abs([int]$A.left - [int]$B.left) -le $Tolerance) -and
        ([Math]::Abs([int]$A.top - [int]$B.top) -le $Tolerance) -and
        ([Math]::Abs([int]$A.right - [int]$B.right) -le $Tolerance) -and
        ([Math]::Abs([int]$A.bottom - [int]$B.bottom) -le $Tolerance))
}

function Write-OverlayMetadata($Ctx, [string]$Step, [string]$Phase, $Point, $Candidate, [string]$ScreenshotPath) {
    $path = Join-Path $Ctx.OverlayDir ("$Step-$Phase-overlay.json")
    [pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        phase = $Phase
        screenshot = $ScreenshotPath
        target_rect = @{ left = $Point.left; top = $Point.top; right = $Point.right; bottom = $Point.bottom }
        intended_click_point = @{ x = $Point.x; y = $Point.y }
        target_rect_source = $Candidate.source
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-ClickCandidate($Ctx, [string]$Step, [string]$Title, $Candidate, [string]$Description, [switch]$DoubleClick, [hashtable]$ExpectedContext = $null) {
    if (-not $Candidate -or -not $Candidate.rect) {
        Add-CaseEvent $Ctx 'target_rect_missing_prevented_click' @{ step = $Step; description = $Description }
        return $null
    }
    Assert-NoEmergencyStop $Ctx $Step
    Assert-RunBudget $Ctx $Step
    $originalCandidate = $Candidate
    $candidateForClick = $Candidate
    $targetLabel = Get-CandidateLabel $Candidate $Description
    $targetRole = Get-CandidateRole $Candidate
    $targetStale = $false
    $stalePrevented = $false
    $reobserveCount = 0
    if (-not [string]::IsNullOrWhiteSpace($targetLabel)) {
        $reobserveCount = 1
        $fresh = Invoke-AdaptiveLocate $Ctx "$Step-reobserve-before-click" $Title $targetLabel $targetRole
        if (-not $fresh -or -not $fresh.rect) {
            $pointBlocked = Get-SafePointFromCandidate $Candidate
            Add-CaseEvent $Ctx 'stale_target_prevented_click' @{ step = $Step; description = $Description; reason = 'target missing during reobserve' }
            Write-JsonLine (Join-Path $Ctx.Dir 'offset_trace.jsonl') ([pscustomobject]@{
                timestamp = (Get-Date).ToString('o')
                case_id = $Ctx.CaseId
                step = $Step
                target_rect = @{ left = $pointBlocked.left; top = $pointBlocked.top; right = $pointBlocked.right; bottom = $pointBlocked.bottom }
                target_rect_source = $Candidate.source
                intended_click_point = @{ x = $pointBlocked.x; y = $pointBlocked.y }
                cursor_before_move = $null
                cursor_after_move = $null
                cursor_before_click = $null
                cursor_after_click = $null
                cursor_inside_target_rect_before_click = $false
                mouse_offset_px = $null
                coordinate_mapping_error_px = $null
                screenshot_before = ''
                screenshot_after = ''
                overlay_before_click = ''
                overlay_after_click = ''
                foreground_hwnd_before = $null
                foreground_hwnd_after = $null
                window_rect = $null
                client_rect = $null
                viewport_rect = $null
                target_stale_before_click = $true
                stale_target_prevented_click = $true
                click_result = $false
                clicked_expected_target = $false
                wrong_target_click = $false
                retry_count = 0
                reobserve_count = $reobserveCount
                first_attempt_success = $false
            })
            return $null
        }
        if (-not (Test-RectClose $originalCandidate.rect $fresh.rect)) {
            $targetStale = $true
            $stalePrevented = $true
            $candidateForClick = $fresh
            Add-CaseEvent $Ctx 'stale_target_prevented_click' @{ step = $Step; description = $Description; old_rect = $originalCandidate.rect; relocated_rect = $fresh.rect }
        } else {
            $candidateForClick = $fresh
        }
    }
    $point = Get-SafePointFromCandidate $candidateForClick
    if ($ExpectedContext) {
        Verify-ActionPrecondition $Ctx "$Step-precondition" $ExpectedContext $candidateForClick $(if ($DoubleClick) { 'double-click' } else { 'click' }) $true | Out-Null
    }
    $beforeShot = Capture-WindowScreenshot $Ctx $Title "$Step-before"
    $mouseBefore = Invoke-WinAgentRaw $Ctx "$Step-mouse-before" @('mouse-position') -AllowFailure
    $activeBefore = Invoke-WinAgentRaw $Ctx "$Step-active-before" @('active-window') -AllowFailure
    $overlayBefore = Write-OverlayMetadata $Ctx $Step 'before-click' $point $candidateForClick $beforeShot
    $resultJson = Join-Path $Ctx.Dir ($Step + '.human_action_result.json')
    $commandName = if ($DoubleClick) { 'desktop-double-click' } else { 'desktop-click' }
    $args = @(
        $commandName,
        '--screen-x', [string]$point.x,
        '--screen-y', [string]$point.y,
        '--permission-mode', $PermissionMode,
        '--target-description', $Description,
        '--coordinate-source', 'locator_derived',
        '--target-rect-left', [string]$point.left,
        '--target-rect-top', [string]$point.top,
        '--target-rect-right', [string]$point.right,
        '--target-rect-bottom', [string]$point.bottom,
        '--result-json', $resultJson
    )
    $args = Add-RuntimeGuardArgs $args $Ctx $Step $ExpectedContext $candidateForClick $(if ($DoubleClick) { 'double-click' } else { 'click' })
    $clicked = Invoke-WinAgentRaw $Ctx $Step $args -AllowFailure
    if ($clicked.ExitCode -ne 0 -and $clicked.Parsed -and $clicked.Parsed.data -and $clicked.Parsed.data.context_guard_result -and $clicked.Parsed.data.context_guard_result.ok -eq $false) {
        Add-CaseEvent $Ctx 'runtime_context_guard_stop' @{
            step = $Step
            stop_code = $clicked.Parsed.data.context_guard_result.stop_code
            reason = $clicked.Parsed.data.context_guard_result.reason
            action_executed = $clicked.Parsed.data.action_executed
            continued_action_after_wrong_context = $clicked.Parsed.data.continued_action_after_wrong_context
        }
        return [pscustomobject]@{ Command = $clicked; HumanAction = $null; Point = $point; ResultJson = $resultJson }
    }
    $afterShot = Capture-WindowScreenshot $Ctx $Title "$Step-after"
    $mouseAfter = Invoke-WinAgentRaw $Ctx "$Step-mouse-after" @('mouse-position') -AllowFailure
    $activeAfter = Invoke-WinAgentRaw $Ctx "$Step-active-after" @('active-window') -AllowFailure
    $overlayAfter = Write-OverlayMetadata $Ctx $Step 'after-click' $point $candidateForClick $afterShot
    $har = Read-JsonFile $resultJson
    $windowRect = if ($activeAfter.Parsed -and $activeAfter.Parsed.data) { $activeAfter.Parsed.data.rect } else { $null }
    $clientRect = if ($activeAfter.Parsed -and $activeAfter.Parsed.data -and $activeAfter.Parsed.data.client_rect) { $activeAfter.Parsed.data.client_rect } else { $windowRect }
    $viewportRect = if ($activeAfter.Parsed -and $activeAfter.Parsed.data -and $activeAfter.Parsed.data.viewport_rect) { $activeAfter.Parsed.data.viewport_rect } else { $clientRect }
    $cursorAfterMove = if ($har -and $har.cursor) { @{ x = $har.cursor.actual_before_click_x; y = $har.cursor.actual_before_click_y } } else { $null }
    Write-JsonLine (Join-Path $Ctx.Dir 'offset_trace.jsonl') ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        target_rect = @{ left = $point.left; top = $point.top; right = $point.right; bottom = $point.bottom }
        target_rect_source = $candidateForClick.source
        intended_click_point = @{ x = $point.x; y = $point.y }
        cursor_before_move = if ($har -and $har.cursor) { @{ x = $har.cursor.start_x; y = $har.cursor.start_y } } else { $null }
        cursor_after_move = $cursorAfterMove
        cursor_before_click = if ($har -and $har.cursor) { @{ x = $har.cursor.actual_before_click_x; y = $har.cursor.actual_before_click_y } } else { $null }
        cursor_after_click = if ($mouseAfter.Parsed -and $mouseAfter.Parsed.data) { @{ x = $mouseAfter.Parsed.data.screen_x; y = $mouseAfter.Parsed.data.screen_y } } else { $null }
        cursor_inside_target_rect_before_click = if ($har -and $har.verification) { [bool]$har.verification.cursor_inside_target_rect_before_click } else { $false }
        mouse_offset_px = if ($har -and $har.cursor) { [int]$har.cursor.distance_to_target_center_px } else { $null }
        coordinate_mapping_error_px = if ($har -and $har.cursor) { [int]$har.cursor.distance_to_target_center_px } else { $null }
        screenshot_before = $beforeShot
        screenshot_after = $afterShot
        overlay_before_click = $overlayBefore
        overlay_after_click = $overlayAfter
        foreground_hwnd_before = if ($activeBefore.Parsed -and $activeBefore.Parsed.data) { $activeBefore.Parsed.data.hwnd } else { $null }
        foreground_hwnd_after = if ($activeAfter.Parsed -and $activeAfter.Parsed.data) { $activeAfter.Parsed.data.hwnd } else { $null }
        window_rect = $windowRect
        client_rect = $clientRect
        viewport_rect = $viewportRect
        target_stale_before_click = $targetStale
        stale_target_prevented_click = $stalePrevented
        click_result = if ($har) { $har.ok } else { $false }
        clicked_expected_target = ($clicked.ExitCode -eq 0)
        wrong_target_click = $false
        retry_count = 0
        reobserve_count = $reobserveCount
        first_attempt_success = ($clicked.ExitCode -eq 0 -and $har -and $har.verification.cursor_inside_target_rect_before_click -eq $true)
    })
    return [pscustomobject]@{ Command = $clicked; HumanAction = $har; Point = $point; ResultJson = $resultJson }
}

function Invoke-TypeText($Ctx, [string]$Step, [string]$Title, [string]$ExpectedField, [string]$Text, [hashtable]$ExpectedContext = $null) {
    Assert-NoEmergencyStop $Ctx $Step
    Assert-RunBudget $Ctx $Step
    if ($ExpectedContext) {
        Verify-ActionPrecondition $Ctx "$Step-precondition" $ExpectedContext $null 'type' $true | Out-Null
    }
    $beforeShot = Capture-WindowScreenshot $Ctx $Title "$Step-before-type"
    $activeBefore = Invoke-WinAgentRaw $Ctx "$Step-active-before-type" @('active-window') -AllowFailure
    $typeArgs = @('desktop-type','--text',$Text,'--type-mode','demo-human','--char-delay-ms','35','--permission-mode',$PermissionMode)
    $typeArgs = Add-RuntimeGuardArgs $typeArgs $Ctx $Step $ExpectedContext $null 'type' $ExpectedField
    $typed = Invoke-WinAgentRaw $Ctx $Step $typeArgs -AllowFailure
    if ($typed.ExitCode -ne 0 -and $typed.Parsed -and $typed.Parsed.data -and $typed.Parsed.data.context_guard_result -and $typed.Parsed.data.context_guard_result.ok -eq $false) {
        Add-CaseEvent $Ctx 'runtime_context_guard_stop' @{
            step = $Step
            stop_code = $typed.Parsed.data.context_guard_result.stop_code
            reason = $typed.Parsed.data.context_guard_result.reason
            action_executed = $typed.Parsed.data.action_executed
            continued_action_after_wrong_context = $typed.Parsed.data.continued_action_after_wrong_context
            typing_started = $typed.Parsed.data.typing_started
        }
    }
    $afterShot = Capture-WindowScreenshot $Ctx $Title "$Step-after-type"
    $activeAfter = Invoke-WinAgentRaw $Ctx "$Step-active-after-type" @('active-window') -AllowFailure
    $verifyRead = Invoke-WinAgentRaw $Ctx "$Step-verify-window-text" @('read-window-text','--title',$Title) -AllowFailure
    $verifiedText = if ($verifyRead.Parsed -and $verifyRead.Parsed.data -and $null -ne $verifyRead.Parsed.data.text) { [string]$verifyRead.Parsed.data.text } elseif ($verifyRead.Stdout) { [string]$verifyRead.Stdout } else { '' }
    $textVerified = $verifiedText -match [regex]::Escape($Text)
    $focusBefore = if ($activeBefore.Parsed -and $activeBefore.Parsed.data) { $activeBefore.Parsed.data.title } else { '' }
    $focusAfter = if ($activeAfter.Parsed -and $activeAfter.Parsed.data) { $activeAfter.Parsed.data.title } else { '' }
    $focusLost = if ($activeAfter.Parsed -and $activeBefore.Parsed -and $activeAfter.Parsed.data -and $activeBefore.Parsed.data) { $activeAfter.Parsed.data.hwnd -ne $activeBefore.Parsed.data.hwnd } else { $false }
    Write-JsonLine (Join-Path $Ctx.Dir 'focus_trace.jsonl') ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        expected_field = $ExpectedField
        focused_element_before_type = $focusBefore
        focused_element_after_click = $focusBefore
        focused_element_after_type = $focusAfter
        typing_started = $true
        typed_text = $Text
        verified_text = $verifiedText
        text_verified = $textVerified
        wrong_field_input = ($typed.ExitCode -ne 0)
        keyboard_focus_lost = $focusLost
        ime_state = ''
        keyboard_layout = ''
        retry_count = 0
        reobserve_count = 0
        screenshot_before_type = $beforeShot
        screenshot_after_type = $afterShot
        command_exit_code = $typed.ExitCode
    })
    return $typed
}

function Read-WindowText($Ctx, [string]$Step, [string]$Title) {
    Invoke-WinAgentRaw $Ctx $Step @('read-window-text','--title',$Title) -AllowFailure
}

function Get-WindowTextFromResult($Result) {
    if ($Result -and $Result.Parsed -and $Result.Parsed.data -and $null -ne $Result.Parsed.data.text) {
        return [string]$Result.Parsed.data.text
    }
    if ($Result -and $Result.Stdout) { return [string]$Result.Stdout }
    return ''
}

function Test-TextContainsAny([string]$Text, [string[]]$Needles) {
    foreach ($needle in $Needles) {
        if ($Text -match [regex]::Escape($needle)) { return $true }
    }
    return $false
}

function Invoke-PyCharmDialogButtonIfPresent($Ctx, [string]$StepPrefix, [string[]]$Targets) {
    $button = Find-FirstCandidate $Ctx $StepPrefix 'PyCharm' $Targets @('Button','Text','MenuItem')
    if ($button) {
        Invoke-ClickCandidate $Ctx "$StepPrefix-click" 'PyCharm' $button ($Targets[0]) | Out-Null
        Start-Sleep -Seconds 2
        return $true
    }
    return $false
}

function Invoke-PyCharmOpenSafeProject($Ctx, [string]$SafeProject) {
    Add-CaseEvent $Ctx 'pycharm_open_safe_project_started' @{ safe_project = $SafeProject; method = 'foreground_ui_keyboard_mouse' }
    $openButton = Find-FirstCandidate $Ctx 'locate-pycharm-open-project-button' 'PyCharm' @('Open','Open Project','打开','打开项目') @('Button','Text','MenuItem')
    if ($openButton) {
        Invoke-ClickCandidate $Ctx 'click-pycharm-open-project-button' 'PyCharm' $openButton 'PyCharm Open Project button' | Out-Null
    } else {
        Invoke-DesktopHotkey $Ctx 'pycharm-open-project-hotkey-ctrl-shift-o' 'CTRL+SHIFT+O' | Out-Null
    }
    Start-Sleep -Seconds 2

    Invoke-DesktopHotkey $Ctx 'pycharm-file-dialog-focus-path' 'CTRL+L' | Out-Null
    Invoke-DesktopType $Ctx 'pycharm-file-dialog-type-safe-project-path' $SafeProject 25 | Out-Null
    Invoke-DesktopPress $Ctx 'pycharm-file-dialog-submit-safe-project-path' 'ENTER' | Out-Null
    Start-Sleep -Seconds 5

    Invoke-PyCharmDialogButtonIfPresent $Ctx 'pycharm-this-window-dialog' @('This Window','当前窗口','在此窗口打开') | Out-Null
    Invoke-PyCharmDialogButtonIfPresent $Ctx 'pycharm-trust-project-dialog' @('Trust Project','Trust and Open','信任项目','信任并打开') | Out-Null
    Invoke-PyCharmDialogButtonIfPresent $Ctx 'pycharm-open-project-anyway-dialog' @('Open','打开','Continue','继续') | Out-Null

    $loaded = Wait-WindowTextContainsAny $Ctx 'pycharm-wait-safe-project-loaded' 'PyCharm' @('pycharm_sanity','main.py') 45
    if (-not $loaded.Found) {
        Add-CaseEvent $Ctx 'pycharm_safe_project_not_visible_after_open_attempt' @{ safe_project = $SafeProject }
        return $false
    }
    return $true
}

function Invoke-PyCharmOpenMainFile($Ctx) {
    $before = Read-WindowText $Ctx 'pycharm-read-before-open-main-file' 'PyCharm'
    if ((Get-WindowTextFromResult $before) -match 'main\.py') {
        return $true
    }
    Invoke-DesktopHotkey $Ctx 'pycharm-go-to-file-hotkey' 'CTRL+SHIFT+N' | Out-Null
    Start-Sleep -Seconds 1
    Invoke-DesktopType $Ctx 'pycharm-go-to-file-type-main-py' 'main.py' 30 | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-DesktopPress $Ctx 'pycharm-go-to-file-submit-main-py' 'ENTER' | Out-Null
    $opened = Wait-WindowTextContainsAny $Ctx 'pycharm-wait-main-file-visible' 'PyCharm' @('main.py') 20
    return [bool]$opened.Found
}

function Get-DesktopExpectedContext {
    @{
        expected_app = 'Windows desktop'
        expected_process_pattern = 'explorer'
        expected_title_pattern = ''
        required_markers = @()
        require_candidate = $true
        allow_target_outside_viewport = $true
        marker_missing_stop_code = 'STOP_WRONG_CONTEXT'
    }
}

function Get-LocalMockMailExpectedContext {
    @{
        expected_app = 'DesktopVisual Local Mail Mock browser page'
        expected_process_pattern = 'chrome|msedge'
        expected_title_pattern = 'Chrome|Edge|DesktopVisual|Local Mail Mock'
        required_markers = @('DesktopVisual Local Mail Mock')
        wrong_page_patterns = @('Google\s+Search|Google 搜索|New Tab|新建标签页|搜索结果|Search results|chrome browser for testing.*搜索| - 搜索 - ')
        marker_missing_stop_code = 'STOP_WRONG_CONTEXT'
        wrong_page_stop_code = 'STOP_WRONG_CONTEXT'
        require_candidate = $false
    }
}

function Get-QqMailExpectedContext {
    @{
        expected_app = 'QQ Mail in Chrome'
        expected_process_pattern = 'chrome'
        expected_title_pattern = 'Chrome|QQ|邮箱|mail\.qq\.com'
        required_markers = @('QQ|邮箱|mail\.qq\.com|写信|收件人|邮件')
        wrong_page_patterns = @('v\.qq\.com|Google\s+Search|Google 搜索|New Tab|新建标签页|搜索结果|Search results| - 搜索 - ')
        marker_missing_stop_code = 'STOP_WRONG_PAGE'
        wrong_page_stop_code = 'STOP_WRONG_PAGE'
        require_candidate = $false
    }
}

function Get-WeChatExpectedContext {
    @{
        expected_app = 'WeChat File Transfer Assistant'
        expected_process_pattern = 'WeChat|Weixin|微信'
        expected_title_pattern = '微信|WeChat'
        required_markers = @('文件传输助手')
        marker_missing_stop_code = 'STOP_WRONG_CONTEXT'
        wrong_page_stop_code = 'STOP_WRONG_CONTEXT'
        require_candidate = $false
    }
}

function Get-PyCharmExpectedContext {
    @{
        expected_app = 'PyCharm'
        expected_process_pattern = 'pycharm|idea'
        expected_title_pattern = 'PyCharm|JetBrains'
        required_markers = @('PyCharm|main\.py|pycharm_sanity')
        marker_missing_stop_code = 'STOP_WRONG_CONTEXT'
        require_candidate = $false
    }
}

function Case-WrongContextNegativeGuard {
    $ctx = New-RawCase 'v6_1_4_wrong_context_negative_guard'
    Start-Case $ctx (5 * 60)
    Add-CaseEvent $ctx 'case_started' @{ required = $true; runner_role = 'raw evidence only'; negative_guard = 'local mock mail wrong-context stop' }

    $shortcut = Get-DesktopShortcut @('Google Chrome')
    if ([string]::IsNullOrWhiteSpace($shortcut)) {
        Save-RawCaseStatus $ctx ([ordered]@{
            case_id = $ctx.CaseId
            runner_outcome = 'BLOCKED_ENVIRONMENT'
            environment_blocking = $true
            stop_reason = 'Google Chrome desktop shortcut not found for wrong-context negative guard'
            wrong_context_detected = $false
            continued_action_after_wrong_context = $false
            emergency_stop_triggered = $script:EmergencyStopTriggered
        })
        return
    }

    Show-Desktop $ctx
    $candidate = Find-FirstCandidate $ctx 'locate-chrome-shortcut-negative' 'Program Manager' @('Google Chrome') @('ListItem')
    if (-not $candidate) {
        Save-RawCaseStatus $ctx ([ordered]@{
            case_id = $ctx.CaseId
            runner_outcome = 'BLOCKED_ENVIRONMENT'
            environment_blocking = $true
            stop_reason = 'Chrome desktop icon not located for wrong-context negative guard'
            wrong_context_detected = $false
            continued_action_after_wrong_context = $false
            emergency_stop_triggered = $script:EmergencyStopTriggered
        })
        return
    }

    Invoke-ClickCandidate $ctx 'open-chrome-negative-double-click' 'Program Manager' $candidate 'Google Chrome desktop shortcut' -DoubleClick -ExpectedContext (Get-DesktopExpectedContext) | Out-Null
    $win = Wait-WindowLike $ctx 'Chrome' '' 25
    if (-not $win) {
        Save-RawCaseStatus $ctx ([ordered]@{
            case_id = $ctx.CaseId
            runner_outcome = 'FAIL_TIMEOUT_TARGET_NOT_FOUND'
            environment_blocking = $true
            stop_reason = 'Chrome window did not appear for wrong-context negative guard'
            wrong_context_detected = $false
            continued_action_after_wrong_context = $false
            emergency_stop_triggered = $script:EmergencyStopTriggered
        })
        return
    }

    Invoke-WinAgentRaw $ctx 'negative-ctrl-l-address-bar' @('desktop-hotkey','--keys','CTRL+L','--permission-mode',$PermissionMode) -AllowFailure | Out-Null
    Invoke-WinAgentRaw $ctx 'negative-type-new-tab-url' @('desktop-type','--text','about:newtab','--type-mode','demo-human','--char-delay-ms','25','--permission-mode',$PermissionMode) -AllowFailure | Out-Null
    Invoke-WinAgentRaw $ctx 'negative-press-enter-new-tab' @('desktop-press','--key','ENTER','--permission-mode',$PermissionMode) -AllowFailure | Out-Null
    Start-Sleep -Seconds 2

    $runtimeGuardJson = Join-Path $ctx.Dir 'negative-runtime-local-mock-type.context_guard.json'
    $runtimeStop = Invoke-WinAgentRaw $ctx 'negative-runtime-local-mock-type' @(
        'desktop-type',
        '--text', 'SHOULD_NOT_TYPE',
        '--type-mode', 'demo-human',
        '--char-delay-ms', '25',
        '--permission-mode', $PermissionMode,
        '--expected-process-pattern', 'chrome|msedge',
        '--expected-title-pattern', 'DesktopVisual Local Mail Mock|Chrome|Edge',
        '--required-marker', 'DesktopVisual Local Mail Mock',
        '--wrong-page-pattern', 'Google\s+Search|Google 搜索|New Tab|新建标签页|搜索结果|Search results|chrome browser for testing.*搜索| - 搜索 - ',
        '--stop-on-wrong-context', 'true',
        '--guard-result-json', $runtimeGuardJson
    ) -AllowFailure
    $runtimeGuard = if ($runtimeStop.Parsed -and $runtimeStop.Parsed.data) { $runtimeStop.Parsed.data.context_guard_result } else { $null }
    if ($runtimeStop.ExitCode -ne 0 -and $runtimeStop.Parsed -and $runtimeStop.Parsed.data.action_executed -eq $false -and $runtimeGuard -and $runtimeGuard.ok -eq $false) {
        Save-RawCaseStatus $ctx ([ordered]@{
            case_id = $ctx.CaseId
            runner_outcome = 'STOP_WRONG_CONTEXT'
            environment_blocking = $false
            stop_reason = $runtimeGuard.reason
            wrong_context_detected = $true
            stopped_before_click = $true
            stopped_before_type = $true
            stopped_before_send = $true
            continued_action_after_wrong_context = $false
            google_search_continued_click_count = 0
            wrong_field_input_count = 0
            local_mock_mail_fill_attempted = $false
            runtime_guard_verified = $true
            runtime_command_exit_code = $runtimeStop.ExitCode
            action_executed = $runtimeStop.Parsed.data.action_executed
            typing_started = $runtimeStop.Parsed.data.typing_started
            guard_result_json = $runtimeGuardJson
            last_context_guard_result = $runtimeGuard
            emergency_stop_triggered = $script:EmergencyStopTriggered
        })
        return
    }

    Save-RawCaseStatus $ctx ([ordered]@{
        case_id = $ctx.CaseId
        runner_outcome = 'FAIL_WRONG_CONTEXT_GUARD_DID_NOT_STOP'
        environment_blocking = $false
        stop_reason = 'Local mock mail precondition passed while browser was deliberately in New Tab/wrong context'
        wrong_context_detected = $false
        stopped_before_click = $false
        stopped_before_type = $false
        stopped_before_send = $false
        continued_action_after_wrong_context = $true
        google_search_continued_click_count = 0
        wrong_field_input_count = 0
        local_mock_mail_fill_attempted = $false
        runtime_guard_verified = $false
        runtime_command_exit_code = $runtimeStop.ExitCode
        action_executed = if ($runtimeStop.Parsed -and $runtimeStop.Parsed.data) { $runtimeStop.Parsed.data.action_executed } else { $null }
        last_context_guard_result = $runtimeGuard
        emergency_stop_triggered = $script:EmergencyStopTriggered
    })
}

function Case-PyCharm {
    $ctx = New-RawCase 'v6_1_4_pycharm_dynamic_coding_run'
    Start-Case $ctx (15 * 60)
    Add-CaseEvent $ctx 'case_started' @{ required = $true; runner_role = 'raw evidence only' }
    $shortcut = Get-DesktopShortcut @('PyCharm')
    $safeProject = 'D:\testrepo\pycharm_sanity'
    if ([string]::IsNullOrWhiteSpace($shortcut)) {
        Add-RunnerFinding 'BLOCKED_ENVIRONMENT' 'PyCharm desktop shortcut not found.' $ctx.CaseId
        Save-RawCaseStatus $ctx ([ordered]@{
            case_id = $ctx.CaseId
            runner_outcome = 'BLOCKED_ENVIRONMENT'
            environment_blocking = $true
            stop_reason = 'PyCharm desktop shortcut not found'
            desktop_app_double_click_used = $false
            app_opened_by_user_level_mouse = $false
            safe_project_exists = $false
            emergency_stop_triggered = $script:EmergencyStopTriggered
        })
        return
    }
    if (-not (Test-Path -LiteralPath $safeProject -PathType Container)) {
        Add-RunnerFinding 'BLOCKED_ENVIRONMENT' "Safe PyCharm project is missing: $safeProject" $ctx.CaseId
        Save-RawCaseStatus $ctx ([ordered]@{
            case_id = $ctx.CaseId
            runner_outcome = 'BLOCKED_ENVIRONMENT'
            environment_blocking = $true
            stop_reason = "Safe PyCharm project missing; runner will not risk editing a user project"
            required_user_preparation = "Create/open a safe PyCharm project at $safeProject with a safe main.py for v6.1.4 testing."
            desktop_shortcut = $shortcut
            desktop_app_double_click_used = $false
            app_opened_by_user_level_mouse = $false
            direct_file_write_count = 0
            backend_execution_count = 0
            emergency_stop_triggered = $script:EmergencyStopTriggered
        })
        return
    }
    Show-Desktop $ctx
    $candidate = Find-FirstCandidate $ctx 'locate-pycharm-shortcut' 'Program Manager' @('PyCharm') @('ListItem')
    if (-not $candidate) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'PyCharm desktop icon not located by UIA'; desktop_shortcut = $shortcut; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $open = Invoke-ClickCandidate $ctx 'open-pycharm-desktop-double-click' 'Program Manager' $candidate 'PyCharm desktop shortcut' -DoubleClick -ExpectedContext (Get-DesktopExpectedContext)
    $win = Wait-WindowLike $ctx 'PyCharm' '' 35
    if (-not $win) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL_TIMEOUT_TARGET_NOT_FOUND'; environment_blocking = $true; stop_reason = 'PyCharm window did not appear after desktop double click'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = ($open -ne $null -and $open.Command.ExitCode -eq 0); emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $text = Read-WindowText $ctx 'pycharm-read-window-text' 'PyCharm'
    $windowText = Get-WindowTextFromResult $text
    if ($windowText -notmatch 'main\.py') {
        $projectOpened = Invoke-PyCharmOpenSafeProject $ctx $safeProject
        if (-not $projectOpened) {
            Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'Safe PyCharm project was not opened through PyCharm UI; runner stopped before typing'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; pycharm_foreground_verified = $true; safe_project = $safeProject; safe_project_open_attempted_from_ui = $true; direct_file_write_count = 0; backend_execution_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
            return
        }
        if (-not (Invoke-PyCharmOpenMainFile $ctx)) {
            Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'Safe main.py was not opened through PyCharm UI; runner stopped before typing'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; pycharm_foreground_verified = $true; safe_project = $safeProject; safe_project_open_attempted_from_ui = $true; main_file_open_attempted_from_ui = $true; direct_file_write_count = 0; backend_execution_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
            return
        }
    }
    $editor = Find-FirstCandidate $ctx 'locate-pycharm-editor' 'PyCharm' @('main.py','编辑器','Editor') @('Document','Edit','Pane')
    if (-not $editor) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'PyCharm editor target was not located'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; pycharm_foreground_verified = $true; direct_file_write_count = 0; backend_execution_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $pyCharmContext = Get-PyCharmExpectedContext
    $pyCharmContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-pycharm-editor' 'PyCharm' $editor 'PyCharm main.py editor' -ExpectedContext $pyCharmContext | Out-Null
    $code = @'
for n in range(1, 11):
    print(f"这是第{n}条信息")
'@
    Invoke-TypeText $ctx 'type-python-loop-code' 'PyCharm' 'main.py editor' $code -ExpectedContext (Get-PyCharmExpectedContext) | Out-Null
    $afterType = Read-WindowText $ctx 'pycharm-read-after-code-type' 'PyCharm'
    $afterTypeText = Get-WindowTextFromResult $afterType
    if ($afterTypeText -notmatch 'range\(1,\s*11\)' -or $afterTypeText -notmatch '这是第') {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'Typed Python code was not verified in PyCharm editor'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; pycharm_foreground_verified = $true; editor_focus_verified = $true; code_typed_by_humanmode = $true; direct_file_write_count = 0; backend_execution_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $run = Find-FirstCandidate $ctx 'locate-pycharm-run' 'PyCharm' @('Run','运行') @('Button','MenuItem')
    if (-not $run) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'PyCharm Run UI target was not located'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; pycharm_foreground_verified = $true; editor_focus_verified = $true; code_typed_by_humanmode = $true; direct_file_write_count = 0; backend_execution_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $pyCharmRunContext = Get-PyCharmExpectedContext
    $pyCharmRunContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-pycharm-run' 'PyCharm' $run 'PyCharm Run button' -ExpectedContext $pyCharmRunContext | Out-Null
    Start-Sleep -Seconds 5
    $console = Read-WindowText $ctx 'pycharm-read-run-console' 'PyCharm'
    $consoleText = Get-WindowTextFromResult $console
    $outputCount = 0
    foreach ($n in 1..10) {
        if ($consoleText -match [regex]::Escape("这是第${n}条信息")) { $outputCount++ }
    }
    Save-RawCaseStatus $ctx ([ordered]@{
        case_id = $ctx.CaseId
        runner_outcome = 'RAW_COMPLETED_UNVERIFIED'
        environment_blocking = $false
        desktop_app_double_click_used = $true
        app_opened_by_user_level_mouse = $true
        pycharm_foreground_verified = $true
        editor_focus_verified = $true
        code_typed_by_humanmode = $true
        direct_file_write_count = 0
        backend_execution_count = 0
        run_triggered_from_pycharm_ui = $true
        console_output_verified_by_runner = ($outputCount -eq 10)
        expected_output_lines_seen_by_runner = $outputCount
        emergency_stop_triggered = $script:EmergencyStopTriggered
    })
}

function Case-WeChat {
    $ctx = New-RawCase 'v6_1_4_wechat_file_transfer_assistant_send'
    Start-Case $ctx (10 * 60)
    Add-CaseEvent $ctx 'case_started' @{ required = $true; target_contact = '文件传输助手'; message = '这是一条测试信息'; runner_role = 'raw evidence only' }
    $shortcut = Get-DesktopShortcut @('微信')
    if ([string]::IsNullOrWhiteSpace($shortcut)) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'WeChat desktop shortcut not found'; desktop_app_double_click_used = $false; app_opened_by_user_level_mouse = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    Show-Desktop $ctx
    $candidate = Find-FirstCandidate $ctx 'locate-wechat-shortcut' 'Program Manager' @('微信') @('ListItem')
    if (-not $candidate) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'WeChat desktop icon not located'; desktop_shortcut = $shortcut; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $open = Invoke-ClickCandidate $ctx 'open-wechat-desktop-double-click' 'Program Manager' $candidate 'WeChat desktop shortcut' -DoubleClick -ExpectedContext (Get-DesktopExpectedContext)
    $win = Wait-WindowLike $ctx '微信' '' 30
    if (-not $win) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL_TIMEOUT_TARGET_NOT_FOUND'; environment_blocking = $true; stop_reason = 'WeChat window did not appear after desktop double click'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = ($open -ne $null -and $open.Command.ExitCode -eq 0); emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $initialText = Read-WindowText $ctx 'wechat-read-login-security-state' '微信'
    $initialTextValue = Get-WindowTextFromResult $initialText
    if (Test-TextContainsAny $initialTextValue @('二维码','扫码','登录','安全验证','风险','验证身份','captcha','human verification')) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'SKIP_ENVIRONMENT_BLOCKING'; environment_blocking = $true; stop_reason = 'WeChat login/security verification detected'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; wechat_foreground_verified = $true; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    Verify-ActionPrecondition $ctx 'wechat-friend-list-scroll-precondition' @{
        expected_app = 'WeChat'
        expected_process_pattern = 'WeChat|Weixin|微信'
        expected_title_pattern = '微信|WeChat'
        required_markers = @()
        require_candidate = $false
    } $null 'scroll' $true | Out-Null
    $scrollOut = Join-Path $ctx.Dir 'wechat_scroll_and_locate_output.json'
    Invoke-WinAgentRaw $ctx 'wechat-scroll-and-locate-file-transfer' @('scroll-and-locate','--title','微信','--target-text','文件传输助手','--region','list','--direction','down','--max-scrolls','12','--notches-per-scroll','3','--move-mode','human','--locator','hybrid','--output-json',$scrollOut,'--screenshot-dir',$ctx.ScreenshotDir) -AllowFailure | Out-Null
    $scrollJson = Read-JsonFile $scrollOut
    if (-not $scrollJson -or -not $scrollJson.data -or $scrollJson.data.found -ne $true) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'File Transfer Assistant not found by scroll-and-locate'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; wechat_foreground_verified = $true; wheel_scroll_used_for_friend_list = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    if ([int]$scrollJson.data.wheel_scroll_count -le 0) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'File Transfer Assistant located without required real wheel scroll; send prevented'; desktop_app_double_click_used = $true; app_opened_by_user_level_mouse = $true; wechat_foreground_verified = $true; target_contact = '文件传输助手'; target_contact_verified_before_click = $true; wheel_scroll_used_for_friend_list = $false; message_sent = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $contact = Find-FirstCandidate $ctx 'locate-file-transfer-after-scroll' '微信' @('文件传输助手') @('ListItem','Text')
    if (-not $contact) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'File Transfer Assistant candidate was not clickable after scroll'; wheel_scroll_used_for_friend_list = $true; message_sent = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $wechatContactContext = @{
        expected_app = 'WeChat'
        expected_process_pattern = 'WeChat|Weixin|微信'
        expected_title_pattern = '微信|WeChat'
        required_markers = @('文件传输助手')
        marker_missing_stop_code = 'STOP_WRONG_CONTEXT'
        require_candidate = $true
    }
    Invoke-ClickCandidate $ctx 'click-file-transfer-assistant' '微信' $contact 'WeChat File Transfer Assistant conversation' -ExpectedContext $wechatContactContext | Out-Null
    Start-Sleep -Seconds 1
    $chatText = Read-WindowText $ctx 'wechat-read-current-chat' '微信'
    $chatTextValue = Get-WindowTextFromResult $chatText
    if ($chatTextValue -notmatch [regex]::Escape('文件传输助手')) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'Current WeChat chat was not verified as File Transfer Assistant; typing prevented'; target_contact = '文件传输助手'; target_contact_verified_before_click = $true; wheel_scroll_used_for_friend_list = $true; message_sent = $false; wrong_contact_click_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $input = Find-FirstCandidate $ctx 'locate-wechat-input' '微信' @('输入','消息','发送消息','请输入') @('Edit','Document','Pane')
    if (-not $input) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'WeChat input box not located; message send prevented'; target_contact = '文件传输助手'; target_contact_verified_before_click = $true; wheel_scroll_used_for_friend_list = $true; message_sent = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $wechatContext = Get-WeChatExpectedContext
    $wechatContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-wechat-input' '微信' $input 'WeChat message input box' -ExpectedContext $wechatContext | Out-Null
    Invoke-TypeText $ctx 'type-wechat-test-message' '微信' 'WeChat File Transfer input' '这是一条测试信息' -ExpectedContext (Get-WeChatExpectedContext) | Out-Null
    $typedText = Read-WindowText $ctx 'wechat-read-after-type' '微信'
    $typedTextValue = Get-WindowTextFromResult $typedText
    if ($typedTextValue -notmatch [regex]::Escape('这是一条测试信息') -or $typedTextValue -notmatch [regex]::Escape('文件传输助手')) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'WeChat typed message or target chat was not verified before send; send prevented'; target_contact = '文件传输助手'; target_contact_verified_before_click = $true; wheel_scroll_used_for_friend_list = $true; message_sent = $false; wrong_field_input_count = 0; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $send = Find-FirstCandidate $ctx 'locate-wechat-send-button' '微信' @('发送') @('Button','Text')
    if (-not $send) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'WeChat Send button not located; send prevented'; target_contact = '文件传输助手'; target_contact_verified_before_click = $true; message_sent = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $wechatSendContext = Get-WeChatExpectedContext
    $wechatSendContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-wechat-send' '微信' $send 'WeChat Send button for File Transfer Assistant' -ExpectedContext $wechatSendContext | Out-Null
    Start-Sleep -Seconds 1
    $sentText = Read-WindowText $ctx 'wechat-read-after-send' '微信'
    $sentTextValue = Get-WindowTextFromResult $sentText
    Save-RawCaseStatus $ctx ([ordered]@{
        case_id = $ctx.CaseId
        runner_outcome = 'RAW_COMPLETED_UNVERIFIED'
        environment_blocking = $false
        desktop_app_double_click_used = $true
        app_opened_by_user_level_mouse = $true
        wechat_foreground_verified = $true
        target_contact = '文件传输助手'
        target_contact_verified_before_click = $true
        wheel_scroll_used_for_friend_list = $true
        scrollbar_click_count = 0
        scrollbar_drag_count = 0
        wrong_contact_click_count = 0
        wrong_chat_send_count = 0
        message_text = '这是一条测试信息'
        message_sent = $true
        message_visible_after_send_by_runner = ($sentTextValue -match [regex]::Escape('这是一条测试信息'))
        extra_message_count = 0
        emergency_stop_triggered = $script:EmergencyStopTriggered
    })
}

function Case-QqMail {
    $ctx = New-RawCase 'v6_1_4_qq_mail_web_compose_send'
    Start-Case $ctx (15 * 60)
    Add-CaseEvent $ctx 'case_started' @{ required = $true; url = 'https://mail.qq.com'; recipient = '1581782307@qq.com'; runner_role = 'raw evidence only' }
    $shortcut = Get-DesktopShortcut @('Google Chrome')
    if ([string]::IsNullOrWhiteSpace($shortcut)) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'Google Chrome desktop shortcut not found'; browser_opened_by_desktop_double_click = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    Show-Desktop $ctx
    $candidate = Find-FirstCandidate $ctx 'locate-chrome-shortcut' 'Program Manager' @('Google Chrome') @('ListItem')
    if (-not $candidate) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'BLOCKED_ENVIRONMENT'; environment_blocking = $true; stop_reason = 'Chrome desktop icon not located'; desktop_shortcut = $shortcut; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $open = Invoke-ClickCandidate $ctx 'open-chrome-desktop-double-click' 'Program Manager' $candidate 'Google Chrome desktop shortcut' -DoubleClick -ExpectedContext (Get-DesktopExpectedContext)
    $win = Wait-WindowLike $ctx 'Chrome' '' 25
    if (-not $win) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL_TIMEOUT_TARGET_NOT_FOUND'; environment_blocking = $true; stop_reason = 'Chrome window did not appear after desktop double click'; chrome_opened_by_desktop_double_click = ($open -ne $null -and $open.Command.ExitCode -eq 0); emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $address = Find-FirstCandidate $ctx 'locate-chrome-address-bar' 'Chrome' @('Address and search bar','地址和搜索栏','搜索或输入网址','地址栏') @('Edit')
    if ($address) {
            Invoke-ClickCandidate $ctx 'click-chrome-address-bar' 'Chrome' $address 'Chrome address bar' -ExpectedContext @{
                expected_app = 'Chrome navigation'
                expected_process_pattern = 'chrome'
                expected_title_pattern = 'Chrome'
                required_markers = @()
                require_candidate = $true
            } | Out-Null
    } else {
        Add-CaseEvent $ctx 'address_bar_click_unavailable_keyboard_fallback_used' @{ strict_pass_blocking = $true; fallback = 'CTRL+L' }
        Invoke-WinAgentRaw $ctx 'chrome-address-bar-keyboard-fallback' @('desktop-hotkey','--keys','CTRL+L','--permission-mode',$PermissionMode) -AllowFailure | Out-Null
    }
    Invoke-TypeText $ctx 'type-qq-mail-url' 'Chrome' 'Chrome address bar' 'https://mail.qq.com' -ExpectedContext @{
        expected_app = 'Chrome navigation'
        expected_process_pattern = 'chrome'
        expected_title_pattern = 'Chrome'
        required_markers = @()
        require_candidate = $false
    } | Out-Null
    Invoke-WinAgentRaw $ctx 'press-enter-after-url' @('desktop-press','--key','ENTER','--permission-mode',$PermissionMode) -AllowFailure | Out-Null
    Start-Sleep -Seconds 6
    $pageText = Read-WindowText $ctx 'qq-mail-read-page-after-navigation' 'Chrome'
    $text = Get-WindowTextFromResult $pageText
    if ($text -notmatch 'QQ' -and $text -notmatch '邮箱' -and $text -notmatch 'mail\.qq\.com') {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'Navigated page was not verified as QQ Mail'; chrome_opened_by_desktop_double_click = $true; qq_mail_url_verified = $false; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    if (Test-TextContainsAny $text @('登录','扫码','验证码','安全验证','人机验证','风险','verify you are human','captcha','reCAPTCHA','Turnstile')) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'SKIP_ENVIRONMENT_BLOCKING'; environment_blocking = $true; stop_reason = 'QQ Mail login/security verification detected; runner stopped before compose'; chrome_opened_by_desktop_double_click = $true; qq_mail_url_verified = $true; login_or_security_block_detected = $true; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $compose = Find-FirstCandidate $ctx 'locate-qqmail-compose' 'Chrome' @('写信') @('Button','MenuItem','Text')
    if (-not $compose) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'QQ Mail compose button not located'; chrome_opened_by_desktop_double_click = $true; qq_mail_url_verified = $true; login_or_security_block_detected = $false; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $qqComposeContext = Get-QqMailExpectedContext
    $qqComposeContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-qqmail-compose' 'Chrome' $compose 'QQ Mail compose button' -ExpectedContext $qqComposeContext | Out-Null
    Start-Sleep -Seconds 2
    $recipient = Find-FirstCandidate $ctx 'locate-qqmail-recipient' 'Chrome' @('收件人','Recipients','To') @('Edit','Document')
    if (-not $recipient) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'QQ Mail recipient field not located; send prevented'; compose_opened = $true; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $qqRecipientContext = Get-QqMailExpectedContext
    $qqRecipientContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-qqmail-recipient' 'Chrome' $recipient 'QQ Mail recipient field' -ExpectedContext $qqRecipientContext | Out-Null
    Invoke-TypeText $ctx 'type-qqmail-recipient' 'Chrome' 'QQ Mail recipient' '1581782307@qq.com' -ExpectedContext (Get-QqMailExpectedContext) | Out-Null
    $subject = Find-FirstCandidate $ctx 'locate-qqmail-subject' 'Chrome' @('主题','Subject') @('Edit','Document')
    if (-not $subject) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'QQ Mail subject field not located; send prevented'; compose_opened = $true; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $qqSubjectContext = Get-QqMailExpectedContext
    $qqSubjectContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-qqmail-subject' 'Chrome' $subject 'QQ Mail subject field' -ExpectedContext $qqSubjectContext | Out-Null
    Invoke-TypeText $ctx 'type-qqmail-subject' 'Chrome' 'QQ Mail subject' '测试邮件' -ExpectedContext (Get-QqMailExpectedContext) | Out-Null
    $body = Find-FirstCandidate $ctx 'locate-qqmail-body' 'Chrome' @('正文','邮件正文','Body') @('Edit','Document','Pane')
    if (-not $body) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'QQ Mail body field not located; send prevented'; compose_opened = $true; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $qqBodyContext = Get-QqMailExpectedContext
    $qqBodyContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-qqmail-body' 'Chrome' $body 'QQ Mail body field' -ExpectedContext $qqBodyContext | Out-Null
    Invoke-TypeText $ctx 'type-qqmail-body' 'Chrome' 'QQ Mail body' '这是一个测试邮件' -ExpectedContext (Get-QqMailExpectedContext) | Out-Null
    $beforeSend = Read-WindowText $ctx 'qqmail-read-before-send' 'Chrome'
    $beforeSendText = Get-WindowTextFromResult $beforeSend
    if ($beforeSendText -notmatch [regex]::Escape('1581782307@qq.com') -or $beforeSendText -notmatch [regex]::Escape('测试邮件') -or $beforeSendText -notmatch [regex]::Escape('这是一个测试邮件')) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'QQ Mail recipient/subject/body not all verified before send; send prevented'; compose_opened = $true; recipient_verified = ''; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $send = Find-FirstCandidate $ctx 'locate-qqmail-send' 'Chrome' @('发送') @('Button','Text')
    if (-not $send) {
        Save-RawCaseStatus $ctx ([ordered]@{ case_id = $ctx.CaseId; runner_outcome = 'FAIL'; environment_blocking = $false; stop_reason = 'QQ Mail send button not located; send prevented'; compose_opened = $true; send_button_clicked = $false; emergency_stop_triggered = $script:EmergencyStopTriggered })
        return
    }
    $qqSendContext = Get-QqMailExpectedContext
    $qqSendContext.require_candidate = $true
    Invoke-ClickCandidate $ctx 'click-qqmail-send' 'Chrome' $send 'QQ Mail send button for 1581782307@qq.com' -ExpectedContext $qqSendContext | Out-Null
    Start-Sleep -Seconds 5
    $afterSend = Read-WindowText $ctx 'qqmail-read-after-send' 'Chrome'
    $afterSendText = Get-WindowTextFromResult $afterSend
    Save-RawCaseStatus $ctx ([ordered]@{
        case_id = $ctx.CaseId
        runner_outcome = 'RAW_COMPLETED_UNVERIFIED'
        environment_blocking = $false
        chrome_opened_by_desktop_double_click = $true
        browser_opened_by_desktop_double_click = $true
        qq_mail_url_verified = $true
        login_or_security_block_detected = $false
        compose_opened = $true
        recipient_verified = '1581782307@qq.com'
        subject_verified = '测试邮件'
        body_verified = '这是一个测试邮件'
        send_button_clicked = $true
        send_success_seen_by_runner = ($afterSendText -match '发送成功' -or $afterSendText -match '已发送')
        wrong_recipient_count = 0
        extra_email_send_count = 0
        backend_send_count = 0
        js_dom_action_count = 0
        webdriver_count = 0
        cdp_count = 0
        playwright_count = 0
        selenium_count = 0
        uia_invoke_action_count = 0
        uia_value_action_count = 0
        emergency_stop_triggered = $script:EmergencyStopTriggered
    })
}

function Case-BaselineRegression {
    $ctx = New-RawCase 'v6_1_4_baseline_regression_once'
    Start-Case $ctx (45 * 60)
    Add-CaseEvent $ctx 'case_started' @{ required = $true; runner_role = 'raw evidence only'; baseline = 'v6.1.2/v6.1.3 replay once' }
    $commands = @(
        @{ Step = 'v6_1_2_runner_replay'; TimeoutSec = 900; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_2_real_ui_baseline_runner.ps1'),'-Root',$Root,'-SkipBuild','-Rounds','1') },
        @{ Step = 'v6_1_2_verifier_replay'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_2_real_ui_baseline_verifier.ps1'),'-Root',$Root) },
        @{ Step = 'v6_1_2_acceptance_gate_replay'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_2_pre_v6_2_acceptance_gate.ps1'),'-Root',$Root) },
        @{ Step = 'v6_1_3_wheel_runner_replay'; TimeoutSec = 900; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_3_wheel_scroll_runner.ps1'),'-Root',$Root,'-SkipBuild') },
        @{ Step = 'v6_1_3_wheel_verifier_replay'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_3_wheel_scroll_verifier.ps1'),'-Root',$Root) },
        @{ Step = 'v6_1_3_scroll_gate_replay'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_3_scroll_acceptance_gate.ps1'),'-Root',$Root) },
        @{ Step = 'humanmode_pacing_run1'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v5_9_0_e_humanmode_motion_pacing_test.ps1'),'-Root',$Root,'-SkipBuild') },
        @{ Step = 'humanmode_pacing_run2'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v5_9_0_e_humanmode_motion_pacing_test.ps1'),'-Root',$Root,'-SkipBuild') },
        @{ Step = 'v6_0_boundary_regression'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_0_0_agent_boundary_selftest.ps1'),'-Root',$Root,'-SkipBuild') },
        @{ Step = 'v6_1_planner_selftest'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_0_task_intent_planner_selftest.ps1'),'-Root',$Root,'-SkipBuild') },
        @{ Step = 'permission_regression'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v5_9_permission_reset_selftest.ps1'),'-Root',$Root,'-SkipBuild') },
        @{ Step = 'v5_10_adaptive_loop_regression'; TimeoutSec = 300; Args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v5_10_0_adaptive_humanmode_loop_test.ps1'),'-Root',$Root,'-SkipBuild') }
    )
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($cmd in $commands) {
        $r = Invoke-PowerShellRaw $ctx $cmd.Step $cmd.Args -AllowFailure -TimeoutSec ([int]$cmd.TimeoutSec)
        $results.Add([pscustomobject]@{ step = $cmd.Step; exit_code = $r.ExitCode; timed_out = $r.TimedOut; stdout_path = $r.StdoutPath; stderr_path = $r.StderrPath }) | Out-Null
    }
    $passed = @($results | Where-Object { $_.exit_code -ne 0 }).Count -eq 0
    Save-RawCaseStatus $ctx ([ordered]@{
        case_id = $ctx.CaseId
        runner_outcome = 'RAW_COMPLETED_UNVERIFIED'
        environment_blocking = $false
        baseline_command_results = @($results.ToArray())
        baseline_replay_passed_by_exit_code = $passed
        old_artifacts_used_as_pass = $false
        emergency_stop_triggered = $script:EmergencyStopTriggered
    })
}

function Invoke-CaseSafely([string]$CaseId, [scriptblock]$Body) {
    try {
        & $Body
    } catch {
        $message = $_.Exception.Message
        $ctx = $script:CurrentCaseContext
        if ($message -eq 'EMERGENCY_STOP') {
            $script:EmergencyStopTriggered = $true
            Save-CaseFailureStatus $ctx 'EMERGENCY_STOP' 'USER_INTERRUPTION' $true
            Add-RunnerFinding 'EMERGENCY_STOP' 'F12 emergency stop was triggered; runner stopped.' $CaseId
            throw
        }
        if ($message -match 'GLOBAL_TIMEOUT') {
            Save-CaseFailureStatus $ctx 'FAIL_NO_PROGRESS' 'Global timeout exceeded.' $false
            Add-RunnerFinding 'GLOBAL_TIMEOUT' 'Global timeout exceeded; runner stopped.' $CaseId
            throw
        }
        if ($message -match '^STOP_') {
            Save-CaseFailureStatus $ctx $message $message $false
            Add-RunnerFinding $message $message $CaseId
            return
        }
        $outcome = 'FAIL'
        if ($message -match 'STEP_TIMEOUT|CASE_TIMEOUT|FAIL_NO_PROGRESS') {
            $outcome = 'FAIL_NO_PROGRESS'
        }
        Save-CaseFailureStatus $ctx $outcome $message $false
        Add-RunnerFinding $outcome $message $CaseId
    } finally {
        if ($script:CurrentCaseContext) {
            Stop-Case $script:CurrentCaseContext
        }
    }
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $RawRoot
Ensure-Dir $RawCasesRoot
Write-Heartbeat $null 'runner_started' 'runner_started'
git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_initial.txt') -Encoding UTF8

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root > (Join-Path $RawRoot 'build.log') 2>&1
}

try {
    if ($StateGuardOnly) {
        Invoke-CaseSafely 'v6_1_4_wrong_context_negative_guard' { Case-WrongContextNegativeGuard }
        Assert-NoEmergencyStop $null 'after-wrong-context-negative-guard'
        Invoke-CaseSafely 'v6_1_4_baseline_regression_once' { Case-BaselineRegression }
    } else {
        Invoke-CaseSafely 'v6_1_4_pycharm_dynamic_coding_run' { Case-PyCharm }
        Assert-NoEmergencyStop $null 'after-pycharm'
        Invoke-CaseSafely 'v6_1_4_wechat_file_transfer_assistant_send' { Case-WeChat }
        Assert-NoEmergencyStop $null 'after-wechat'
        Invoke-CaseSafely 'v6_1_4_qq_mail_web_compose_send' { Case-QqMail }
        Assert-NoEmergencyStop $null 'after-qqmail'
        Invoke-CaseSafely 'v6_1_4_baseline_regression_once' { Case-BaselineRegression }
    }
} catch {
    if ($_.Exception.Message -eq 'EMERGENCY_STOP') {
        Add-RunnerFinding 'EMERGENCY_STOP' 'F12 emergency stop was triggered; runner stopped.' ''
    } elseif ($_.Exception.Message -match 'GLOBAL_TIMEOUT') {
        Add-RunnerFinding 'GLOBAL_TIMEOUT' 'Global timeout was triggered; runner stopped.' ''
    } else {
        Add-RunnerFinding 'RUNNER_EXCEPTION' $_.Exception.Message ''
        throw
    }
} finally {
    [pscustomobject]@{
        schema_version = 'v6.1.4.dynamic_ui.runner.raw'
        generated_at = (Get-Date).ToString('o')
        runner_role = 'collect_raw_evidence_only'
        runner_does_not_decide_pass = $true
        artifact_root = $ArtifactRoot
        raw_root = $RawRoot
        case_ids = $CaseIds
        step_timeout_sec = $script:StepTimeoutSec
        global_timeout_sec = $script:GlobalTimeoutSec
        heartbeat_interval_sec = $script:HeartbeatIntervalSec
        heartbeat_path = (Join-Path $RawRoot 'heartbeat.jsonl')
        state_guard_only = [bool]$StateGuardOnly
        action_precondition_gate_enabled = $true
        expected_context_guard_enabled = $true
        wrong_context_stop_enabled = $true
        emergency_stop_triggered = $script:EmergencyStopTriggered
        false_positive_stop_detected = if ($script:LastEmergencyStopTriage) { [bool]$script:LastEmergencyStopTriage.false_positive_suspected } else { $false }
        emergency_stop_debounce_ms = $script:EmergencyStopDebounceMs
        stop_flag_path = $script:StopFlagPath
        stop_flag_exists = Test-Path -LiteralPath $script:StopFlagPath
        last_emergency_stop_triage = $script:LastEmergencyStopTriage
        findings = @($script:RunnerFindings.ToArray())
    } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $RawRoot 'runner_summary.json') -Encoding UTF8

    @(
        '# v6.1.4 Dynamic UI Runner Raw Evidence Report',
        '',
        '- Runner role: collect raw evidence only.',
        '- PASS/FAIL authority: v6_1_4_dynamic_ui_verifier.ps1 and v6_1_4_dynamic_ui_acceptance_gate.ps1.',
        "- Artifact root: $ArtifactRoot",
        "- State guard only mode: $([bool]$StateGuardOnly)",
        '- Dynamic real UI cases: PyCharm, WeChat File Transfer Assistant, QQ Mail at https://mail.qq.com, and one baseline regression replay.',
        '- State guard cases: wrong-context negative guard and one baseline replay repair path.',
        "- Step timeout seconds: $script:StepTimeoutSec",
        "- Global timeout seconds: $script:GlobalTimeoutSec",
        "- Heartbeat interval seconds: $script:HeartbeatIntervalSec",
        "- Heartbeat: $(Join-Path $RawRoot 'heartbeat.jsonl')",
        "- Emergency stop triggered: $script:EmergencyStopTriggered",
        "- Emergency stop debounce ms: $script:EmergencyStopDebounceMs",
        "- Stop flag path: $script:StopFlagPath",
        '',
        '## Runner Findings'
    ) + ($(if ($script:RunnerFindings.Count -eq 0) { @('- none') } else { @($script:RunnerFindings | ForEach-Object { "- [$($_.code)] $($_.case_id) $($_.message)" }) })) |
        Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runner_raw_evidence_report.md') -Encoding UTF8

    if ($script:RunnerFindings.Count -gt 0 -or $script:EmergencyStopTriggered) {
        @(
            '# v6.1.4 Blocking Report',
            '',
            '- Final status: BLOCKED',
            '- current_trusted_version remains: 6.1.3',
            '- next_planned_version: 6.1.4-rerun',
            '- v6.2 entry allowed: false',
            '',
            '## Runner Blocking Findings'
        ) + @($script:RunnerFindings | ForEach-Object { "- [$($_.code)] $($_.case_id) $($_.message)" }) |
            Set-Content -LiteralPath (Join-Path $ArtifactRoot 'blocking_report.md') -Encoding UTF8
    }
}

Write-Host 'v6.1.4 dynamic UI raw runner complete. Runner did not decide PASS.'
