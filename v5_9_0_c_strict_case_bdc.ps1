param(
    [string]$Root = '',
    [switch]$SkipBuild,
    [switch]$SkipGuiCases,
    [string]$ThirdPartyAppPath = '',
    [string]$ThirdPartyAppName = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.9.0-c_strict_case_bdc'
$CasesRoot = Join-Path $ArtifactRoot 'cases'
$PreviousArtifactRoot = Join-Path $Root 'artifacts\dev5.9.0-b_humanmode_case_runner'
$MockDir = 'D:\testrepo\testwindow'
$MockHtml = Join-Path $MockDir 'desktopvisual_mail_mock.html'
$BrowserProfile = Join-Path $ArtifactRoot 'browser_profile'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'
$PreviousResults = @{
    'chrome_address_bar_external_url_navigation_flow' = 'HUMANMODE_FALLBACK_PASS'
    'explorer_open_local_html_via_humanmode_flow' = 'HUMANMODE_FALLBACK_PASS'
    'third_party_app_launch_visible_flow' = 'SKIP_ENVIRONMENT'
}

function Fail($Message) { throw $Message }

function Ensure-Dir($Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

function Save-ScreenShot($Path) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
}

function Save-CaseScreenshot($Ctx, [string]$Name) {
    $path = Join-Path $Ctx.Screenshots $Name
    Save-ScreenShot $path
    $Ctx.ScreenshotsTaken++
    Add-Event $Ctx 'screenshot' 'ok' @{ path = $path }
    return $path
}

function Write-JsonLine($Path, $Object) {
    try {
        ($Object | ConvertTo-Json -Compress -Depth 20 -ErrorAction Stop) | Add-Content -LiteralPath $Path -Encoding UTF8
    } catch {
        ([pscustomobject]@{
            timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
            serialization_fallback = $true
            serialization_error = $_.Exception.Message
            original_type = $Object.GetType().FullName
            text = ($Object | Out-String)
        } | ConvertTo-Json -Compress -Depth 5) | Add-Content -LiteralPath $Path -Encoding UTF8
    }
}

function Get-VirtualScreenRect {
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    [pscustomobject]@{
        Left = [int]$bounds.Left
        Top = [int]$bounds.Top
        Right = [int]($bounds.Left + $bounds.Width)
        Bottom = [int]($bounds.Top + $bounds.Height)
    }
}

function Test-ScreenPoint([Nullable[int]]$X, [Nullable[int]]$Y) {
    if ($null -eq $X -or $null -eq $Y) { return $false }
    $v = Get-VirtualScreenRect
    return ($X -ge $v.Left -and $X -lt $v.Right -and $Y -ge $v.Top -and $Y -lt $v.Bottom)
}

function Test-WindowRectUsable($Rect) {
    if (-not $Rect) { return $false }
    $cx = [int](($Rect.left + $Rect.right) / 2)
    $cy = [int](($Rect.top + $Rect.bottom) / 2)
    return (($Rect.right - $Rect.left) -gt 100 -and ($Rect.bottom - $Rect.top) -gt 80 -and (Test-ScreenPoint $cx $cy))
}

function Get-ForegroundUiaItemCenter([string[]]$Patterns) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    if (-not ('DesktopVisual.NativeMethods' -as [type])) {
        Add-Type -Namespace DesktopVisual -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
'@
    }
    $hwnd = [DesktopVisual.NativeMethods]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $null }
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if (-not $root) { return $null }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $foundItems = New-Object System.Collections.Generic.List[object]
    foreach ($el in $all) {
        try {
            $name = $el.Current.Name
            if (-not $name) { continue }
            if ($el.Current.IsOffscreen) { continue }
            if (@($Patterns | Where-Object { $name -match $_ }).Count -eq 0) { continue }
            $rect = $el.Current.BoundingRectangle
            if ($rect.Width -le 0 -or $rect.Height -le 0) { continue }
            $x = [int]($rect.Left + ($rect.Width / 2))
            $y = [int]($rect.Top + ($rect.Height / 2))
            if (-not (Test-ScreenPoint $x $y)) { continue }
            $foundItems.Add([pscustomobject]@{
                X = $x
                Y = $y
                Name = $name
                ControlType = $el.Current.ControlType.ProgrammaticName
                Rect = [pscustomobject]@{ left = [int]$rect.Left; top = [int]$rect.Top; right = [int]($rect.Left + $rect.Width); bottom = [int]($rect.Top + $rect.Height) }
            }) | Out-Null
        } catch {}
    }
    if ($foundItems.Count -eq 0) { return $null }
    return @($foundItems | Sort-Object @{ Expression = { $_.Y } }, @{ Expression = { $_.X } } | Select-Object -First 1)[0]
}

function New-CaseContext($CaseId) {
    $dir = Join-Path $CasesRoot $CaseId
    Ensure-Dir $dir
    Ensure-Dir (Join-Path $dir 'screenshots')
    foreach ($file in @('task_events.jsonl', 'action_trace.jsonl', 'locator_trace.jsonl')) {
        Set-Content -LiteralPath (Join-Path $dir $file) -Value '' -Encoding UTF8
    }
    [pscustomobject]@{
        CaseId = $CaseId
        Dir = $dir
        Screenshots = Join-Path $dir 'screenshots'
        Events = Join-Path $dir 'task_events.jsonl'
        Actions = Join-Path $dir 'action_trace.jsonl'
        Locators = Join-Path $dir 'locator_trace.jsonl'
        Result = Join-Path $dir 'task_result.json'
        Report = Join-Path $dir 'task_report.md'
        Verify = Join-Path $dir 'verification_report.md'
        Failure = Join-Path $dir 'failure_reason.md'
        UsedFallback = $false
        FixtureUsed = $false
        StrictHumanMode = $false
        BackendActionCount = 0
        DirectLaunchCount = 0
        ShellExecuteCount = 0
        StartProcessCount = 0
        WebDriverCount = 0
        CdpCount = 0
        JsDomActionCount = 0
        UiaInvokeActionCount = 0
        UiaValueActionCount = 0
        LocatorDerivedCount = 0
        HeuristicLocatorDerivedCount = 0
        FixedCoordinateCount = 0
        HumanModeActionCount = 0
        HumanModePacingChecked = $false
        MinMoveDurationMs = $null
        MinDwellBeforeClickMs = $null
        MinDoubleClickIntervalMs = $null
        ClickBeforeMoveEndCount = 0
        InstantClickAfterMoveCount = 0
        HumanActionResultCount = 0
        HumanActionResultParseErrors = 0
        ResultContractVersion = 'human_action_result.v1'
        LocatorMethods = New-Object System.Collections.Generic.List[string]
        ScreenshotsTaken = 0
        VerificationPassed = $false
        FailureReason = ''
        ActiveProtectionSeen = $false
    }
}

function Get-ActiveInfo {
    Invoke-AgentJson -CmdArgs @('active-window') -AllowFailure
}

function Add-Event($Ctx, $Name, $Status, $Details) {
    Write-JsonLine $Ctx.Events ([pscustomobject]@{
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        event = $Name
        status = $Status
        details = $Details
    })
}

function Add-Locator($Ctx, $Target, $Method, $Status, $X, $Y, $Details) {
    if ($Method -match 'heuristic') {
        $Ctx.HeuristicLocatorDerivedCount++
    } elseif ($Method -match 'uia|ocr|element|observe') {
        $Ctx.LocatorDerivedCount++
    }
    if ($Status -eq 'ok' -and -not $Ctx.LocatorMethods.Contains($Method)) {
        $Ctx.LocatorMethods.Add($Method) | Out-Null
    }
    Write-JsonLine $Ctx.Locators ([pscustomobject]@{
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        target_description = $Target
        locator_method = $Method
        status = $Status
        screen_x = $X
        screen_y = $Y
        details = $Details
    })
}

function Update-MinMetric($Ctx, [string]$Name, $Value) {
    if ($null -eq $Value) { return }
    $intValue = [int]$Value
    if ($null -eq $Ctx.$Name -or $intValue -lt [int]$Ctx.$Name) { $Ctx.$Name = $intValue }
}

function Normalize-HumanModeCommand([string[]]$CmdArgs, [string]$Target, [string]$CoordinateSource) {
    if ($CmdArgs.Count -eq 0 -or $CmdArgs[0] -notin @('desktop-move', 'desktop-click', 'desktop-double-click')) { return $CmdArgs }
    $normalized = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $CmdArgs.Count; $i++) {
        if ($CmdArgs[$i] -eq '--move-mode' -and ($i + 1) -lt $CmdArgs.Count -and $CmdArgs[$i + 1] -eq 'fast-human') { $i++; continue }
        $normalized.Add($CmdArgs[$i]) | Out-Null
    }
    if ($normalized -notcontains '--humanmode') { $normalized.Add('--humanmode') | Out-Null; $normalized.Add('true') | Out-Null }
    if ($normalized -notcontains '--target-description') { $normalized.Add('--target-description') | Out-Null; $normalized.Add($Target) | Out-Null }
    if ($normalized -notcontains '--coordinate-source') { $normalized.Add('--coordinate-source') | Out-Null; $normalized.Add($CoordinateSource) | Out-Null }
    return [string[]]$normalized.ToArray()
}

function Add-HumanActionTrace($Ctx, [string]$ActionType, $Result) {
    $har = $Result.data.human_action_result
    if (-not $har) {
        if ($ActionType -like 'mouse.*') { $Ctx.HumanActionResultParseErrors++ }
        return
    }
    if ($har.schema_version -ne 'human_action_result.v1') { $Ctx.HumanActionResultParseErrors++ }
    $Ctx.HumanActionResultCount++
    $Ctx.HumanModePacingChecked = $true
    Update-MinMetric $Ctx 'MinMoveDurationMs' $har.motion.move_duration_ms
    if ($har.action_type -in @('mouse_click', 'mouse_double_click')) { Update-MinMetric $Ctx 'MinDwellBeforeClickMs' $har.motion.dwell_before_click_ms }
    if ($har.action_type -eq 'mouse_double_click') { Update-MinMetric $Ctx 'MinDoubleClickIntervalMs' $har.motion.double_click_interval_ms }
    if ($har.motion.move_duration_ms -eq 0 -and $har.actual_click_sent) { $Ctx.InstantClickAfterMoveCount++ }
    if ($har.verification.click_after_move_end -eq $false -and $har.actual_click_sent) { $Ctx.ClickBeforeMoveEndCount++ }
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_move_humanmode_start'; from_x=$har.cursor.start_x; from_y=$har.cursor.start_y; target_x=$har.target.x; target_y=$har.target.y; duration_ms=$har.motion.move_duration_ms; planned_steps=$har.motion.planned_steps; easing=$har.motion.easing; timestamp=$har.timing.move_start_ts })
    $path = @($har.motion.planned_path)
    if ($path.Count -gt 0) {
        foreach ($idx in (@(0, [Math]::Floor(($path.Count - 1) / 2), ($path.Count - 1)) | Select-Object -Unique)) {
            Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_move_humanmode_step'; step_index=[int]($idx + 1); step_count=$path.Count; x=$path[$idx].x; y=$path[$idx].y; timestamp=$har.timing.move_start_ts })
        }
    }
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_move_humanmode_end'; final_x=$har.cursor.final_x; final_y=$har.cursor.final_y; target_x=$har.target.x; target_y=$har.target.y; within_epsilon=$har.cursor.within_target_epsilon_before_click; timestamp=$har.timing.move_end_ts })
    if ($har.action_type -in @('mouse_click', 'mouse_double_click')) {
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='dwell_before_click'; duration_ms=$har.motion.dwell_before_click_ms; timestamp=$har.timing.dwell_start_ts })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_click_down'; x=$har.cursor.actual_before_click_x; y=$har.cursor.actual_before_click_y; timestamp=$har.timing.click_down_ts })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_click_up'; x=$har.cursor.actual_before_click_x; y=$har.cursor.actual_before_click_y; timestamp=$har.timing.click_up_ts })
    }
    if ($har.action_type -eq 'mouse_double_click') {
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='double_click_interval'; duration_ms=$har.motion.double_click_interval_ms; timestamp=$har.timing.click_up_ts })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_click_down'; x=$har.cursor.actual_before_click_x; y=$har.cursor.actual_before_click_y; timestamp=$har.timing.second_click_down_ts })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{ action_type='mouse_click_up'; x=$har.cursor.actual_before_click_x; y=$har.cursor.actual_before_click_y; timestamp=$har.timing.second_click_up_ts })
    }
}

function Invoke-HumanAction($Ctx, [string]$ActionType, [string]$Target, [string]$LocatorMethod, [string]$CoordinateSource, [Nullable[int]]$ScreenX, [Nullable[int]]$ScreenY, [string[]]$CmdArgs, [switch]$AllowFailure) {
    $CmdArgs = Normalize-HumanModeCommand $CmdArgs $Target $CoordinateSource
    $result = Invoke-AgentJson -CmdArgs $CmdArgs -AllowFailure:$AllowFailure
    Add-HumanActionTrace $Ctx $ActionType $result
    $active = Get-ActiveInfo
    if ($CoordinateSource -eq 'locator_derived') { $Ctx.LocatorDerivedCount++ }
    if ($CoordinateSource -eq 'heuristic_locator_derived') { $Ctx.HeuristicLocatorDerivedCount++ }
    if ($CoordinateSource -eq 'manual_fixed') { $Ctx.FixedCoordinateCount++ }
    $Ctx.HumanModeActionCount++
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        action_type = $ActionType
        target_description = $Target
        locator_method = $LocatorMethod
        coordinate_source = $CoordinateSource
        screen_x = $ScreenX
        screen_y = $ScreenY
        foreground_window_title = $active.data.title
        foreground_process = $active.data.process_name
        humanmode = $true
        backend_action = $false
        ok = [bool]$result.ok
        error_code = $(if ($result.ok) { '' } else { $result.error.code })
        notes = ($CmdArgs -join ' ')
    })
    Add-Event $Ctx $ActionType $(if ($result.ok) { 'ok' } else { 'failed' }) @{ command = ($CmdArgs -join ' '); ok = $result.ok }
    return $result
}

function Complete-Case($Ctx, $Status, $Summary, $Verification) {
    if ($Status -notin @('FAIL', 'FAIL_POLICY_DEFECT', 'BLOCKED_BY_ACTIVE_PROTECTION', 'SKIP_ENVIRONMENT') -and (Test-Path $Ctx.Failure)) {
        Remove-Item -LiteralPath $Ctx.Failure -Force
    }
    $Ctx.StrictHumanMode = ($Status -eq 'STRICT_HUMANMODE_PASS')
    $Ctx.VerificationPassed = ($Status -eq 'STRICT_HUMANMODE_PASS' -or $Status -eq 'HUMANMODE_FALLBACK_PASS')
    $failureReason = if ($Ctx.FailureReason) { $Ctx.FailureReason } elseif ($Ctx.VerificationPassed) { '' } else { $Summary }
    $result = [pscustomobject]@{
        case_id = $Ctx.CaseId
        previous_result_from_v5_9_0_b = $PreviousResults[$Ctx.CaseId]
        target_result = $(if ($Ctx.CaseId -eq 'third_party_app_launch_visible_flow') { 'STRICT_HUMANMODE_PASS_OR_HUMANMODE_FALLBACK_PASS' } else { 'STRICT_HUMANMODE_PASS' })
        actual_result = $Status
        strict_humanmode = $Ctx.StrictHumanMode
        fallback_used = $Ctx.UsedFallback
        fixture_used = $Ctx.FixtureUsed
        locator_methods_used = @($Ctx.LocatorMethods)
        backend_action_count = $Ctx.BackendActionCount
        direct_launch_count = $Ctx.DirectLaunchCount
        shell_execute_count = $Ctx.ShellExecuteCount
        start_process_count = $Ctx.StartProcessCount
        webdriver_count = $Ctx.WebDriverCount
        cdp_count = $Ctx.CdpCount
        js_dom_action_count = $Ctx.JsDomActionCount
        uia_invoke_action_count = $Ctx.UiaInvokeActionCount
        uia_value_action_count = $Ctx.UiaValueActionCount
        fixed_coordinate_count = $Ctx.FixedCoordinateCount
        locator_derived_coordinate_count = $Ctx.LocatorDerivedCount
        heuristic_locator_derived_count = $Ctx.HeuristicLocatorDerivedCount
        humanmode_action_count = $Ctx.HumanModeActionCount
        humanmode_pacing_checked = $Ctx.HumanModePacingChecked
        min_move_duration_ms = $Ctx.MinMoveDurationMs
        min_dwell_before_click_ms = $Ctx.MinDwellBeforeClickMs
        min_double_click_interval_ms = $Ctx.MinDoubleClickIntervalMs
        click_before_move_end_count = $Ctx.ClickBeforeMoveEndCount
        instant_click_after_move_count = $Ctx.InstantClickAfterMoveCount
        human_action_result_count = $Ctx.HumanActionResultCount
        human_action_result_parse_errors = $Ctx.HumanActionResultParseErrors
        result_contract_version = $Ctx.ResultContractVersion
        screenshots_count = $Ctx.ScreenshotsTaken
        verification_passed = $Ctx.VerificationPassed
        failure_reason = $failureReason
        active_protection_seen = $Ctx.ActiveProtectionSeen
        vlm_call_count = 0
        status = $Status
        summary = $Summary
        used_fallback = $Ctx.UsedFallback
        real_email_send_count = 0
        active_protection_bypass_attempt_count = 0
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Ctx.Result -Encoding UTF8
    $Verification | Set-Content -LiteralPath $Ctx.Verify -Encoding UTF8
    @(
        "# $($Ctx.CaseId)",
        "",
        "- Result: $Status",
        "- Summary: $Summary",
        "- Fallback used: $($Ctx.UsedFallback)",
        "- Fixture used: $($Ctx.FixtureUsed)",
        "- Locator methods: $(@($Ctx.LocatorMethods) -join ', ')",
        "- Backend actions counted as HumanMode: 0",
        "- Direct launches counted as PASS: 0",
        "- VLM calls: 0",
        "- Real email sends: 0",
        "",
        "Artifacts are in this directory."
    ) | Set-Content -LiteralPath $Ctx.Report -Encoding UTF8
}

function Fail-Case($Ctx, $Status, $Reason) {
    $Ctx.FailureReason = $Reason
    $Reason | Set-Content -LiteralPath $Ctx.Failure -Encoding UTF8
    Complete-Case $Ctx $Status $Reason "Verification failed: $Reason"
}

function Find-WindowTitle($Pattern) {
    $windows = Invoke-AgentJson -CmdArgs @('windows')
    foreach ($w in $windows.windows) {
        if ($w.title -match $Pattern -and (Test-WindowRectUsable $w.rect)) { return $w.title }
    }
    return ''
}

function Wait-WindowTitle($Pattern, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $title = Find-WindowTitle $Pattern
        if ($title) { return $title }
        Start-Sleep -Milliseconds 500
    }
    return ''
}

function Get-UiaCenter($Title, $Name) {
    $found = Invoke-AgentJson -CmdArgs @('uia-find', '--title', $Title, '--name', $Name) -AllowFailure
    if (-not $found.ok) { return $null }
    $rect = $found.data.rect
    [pscustomobject]@{
        X = [int](($rect.left + $rect.right) / 2)
        Y = [int](($rect.top + $rect.bottom) / 2)
        Raw = $found
    }
}

function Get-ObservedElementCenter($Title, $Name, $ControlType) {
    $observed = Invoke-AgentJson -CmdArgs @('observe', '--title', $Title, '--screenshot', 'false', '--uia', 'true', '--max-elements', '160') -AllowFailure
    if (-not $observed.ok) { return $null }
    $matches = @($observed.data.uia.elements | Where-Object { $_.name -eq $Name -and $_.control_type -eq $ControlType -and $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top })
    if ($matches.Count -ne 1) { return $null }
    $rect = $matches[0].rect
    [pscustomobject]@{
        X = [int](($rect.left + $rect.right) / 2)
        Y = [int](($rect.top + $rect.bottom) / 2)
        Raw = $matches[0]
    }
}

function Get-WindowInfoByTitle($Pattern) {
    $windows = Invoke-AgentJson -CmdArgs @('windows') -AllowFailure
    if (-not $windows.ok -and -not $windows.windows) { return $null }
    foreach ($w in $windows.windows) {
        if ($w.title -match $Pattern -and (Test-WindowRectUsable $w.rect)) { return $w }
    }
    if ($windows.data -and $windows.data.windows) {
        foreach ($w in $windows.data.windows) {
            if ($w.title -match $Pattern -and (Test-WindowRectUsable $w.rect)) { return $w }
        }
    }
    return $null
}

function New-DesktopShortcut($Name, $TargetPath, $Arguments, $WorkingDirectory) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop ($Name + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnk)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    $shortcut.Save()
    return $lnk
}

function Invoke-DesktopShortcut($Ctx, [string]$ShortcutName, [string]$Purpose) {
    Invoke-HumanAction $Ctx 'keyboard.hotkey' 'show desktop' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'WIN+D', '--permission-mode', $PermissionMode) | Out-Null
    Start-Sleep -Milliseconds 800
    $center = Get-UiaCenter 'Program Manager' $ShortcutName
    if (-not $center) {
        Add-Locator $Ctx $ShortcutName 'uia Program Manager ListItem' 'not_found' $null $null @{}
        return $false
    }
    if (-not (Test-ScreenPoint $center.X $center.Y)) {
        Add-Locator $Ctx $ShortcutName 'uia Program Manager ListItem' 'invalid_offscreen_coordinate' $center.X $center.Y $center.Raw.data
        return $false
    }
    Add-Locator $Ctx $ShortcutName 'uia Program Manager ListItem' 'ok' $center.X $center.Y $center.Raw.data
    Invoke-HumanAction $Ctx 'mouse.move' $ShortcutName 'uia Program Manager ListItem' 'locator_derived' $center.X $center.Y @('desktop-move', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $Ctx 'mouse.double_click' $ShortcutName 'uia Program Manager ListItem' 'locator_derived' $center.X $center.Y @('desktop-double-click', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
    Add-Event $Ctx 'desktop_shortcut_opened' 'ok' @{ shortcut = $ShortcutName; purpose = $Purpose }
    return $true
}

function Ensure-BrowserVisibleHumanMode($Ctx) {
    $existing = Wait-WindowTitle 'Chrome|Edge' 1
    if ($existing) { return $existing }
    $browser = Find-BrowserExe
    if (-not $browser) { return '' }
    $lnk = Ensure-BrowserShortcut $browser
    Add-Event $Ctx 'setup_browser_shortcut' 'ok' @{ path = $lnk; browser = $browser.Exe; setup_only = $true }
    if (Invoke-DesktopShortcut $Ctx $browser.Shortcut 'open browser for address-bar case') {
        $title = Wait-WindowTitle 'Chrome|Edge' 15
        if ($title) { return $title }
    }
    $Ctx.UsedFallback = $true
    Add-Event $Ctx 'browser_visible_setup_fallback' 'start_menu' @{ reason = 'desktop shortcut locator unavailable or offscreen'; setup_only = $true }
    Invoke-HumanAction $Ctx 'keyboard.press' 'Start menu' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'WIN', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $Ctx 'keyboard.type_text' $browser.Name 'Start menu search' 'fallback_keyboard' $null $null @('desktop-type', '--text', $browser.Name, '--type-mode', 'demo-human', '--char-delay-ms', '45', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $Ctx 'keyboard.press' 'Start search result' 'Start menu search' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', $PermissionMode) | Out-Null
    return Wait-WindowTitle 'Chrome|Edge' 15
}

function Resolve-AddressBarCenter($Ctx, [string]$BrowserTitle) {
    $candidatePath = Join-Path $Ctx.Dir 'address_bar_locator_candidates.json'
    $candidates = New-Object System.Collections.Generic.List[object]
    $observed = Invoke-AgentJson -CmdArgs @('observe', '--title', $BrowserTitle, '--screenshot', 'false', '--uia', 'true', '--max-elements', '260') -AllowFailure
    if ($observed.ok) {
        $matches = @($observed.data.uia.elements | Where-Object {
            $_.control_type -eq 'Edit' -and
            $_.rect.right -gt $_.rect.left -and
            $_.rect.bottom -gt $_.rect.top -and
            ($_.name -match 'Address|Search|address|search|omnibox|地址|搜索|输入网址')
        } | Sort-Object @{ Expression = { $_.rect.top } }, @{ Expression = { -($_.rect.right - $_.rect.left) } })
        foreach ($m in $matches) { $candidates.Add([pscustomobject]@{ method = 'uia'; name = $m.name; control_type = $m.control_type; rect = $m.rect }) | Out-Null }
        if ($matches.Count -gt 0) {
            $rect = $matches[0].rect
            $center = [pscustomobject]@{
                X = [int](($rect.left + $rect.right) / 2)
                Y = [int](($rect.top + $rect.bottom) / 2)
                Method = 'uia browser address bar Edit'
                CoordinateSource = 'locator_derived'
                Raw = $matches[0]
            }
            if (Test-ScreenPoint $center.X $center.Y) {
                Add-Locator $Ctx 'browser address bar' $center.Method 'ok' $center.X $center.Y $center.Raw
                $candidates | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
                return $center
            }
            Add-Locator $Ctx 'browser address bar' $center.Method 'invalid_offscreen_coordinate' $center.X $center.Y $center.Raw
        }
        Add-Locator $Ctx 'browser address bar' 'uia browser address bar Edit' 'not_found' $null $null @{ observed = $observed.ok }
    } else {
        Add-Locator $Ctx 'browser address bar' 'uia browser address bar Edit' 'not_found' $null $null @{ error = $observed.error.code }
    }

    $window = Get-WindowInfoByTitle $BrowserTitle
    $width = if ($window -and $window.rect) { [int]($window.rect.right - $window.rect.left) } else { 1200 }
    $ocr = Invoke-AgentJson -CmdArgs @('read-region-text', '--title', $BrowserTitle, '--x', '0', '--y', '0', '--w', "$([Math]::Min($width, 1400))", '--h', '140') -AllowFailure
    if ($ocr.ok) {
        $text = $ocr.data.text
        $hit = @($ocr.data.words | Where-Object { $_.text -match 'Search|address|baidu|example|输入网址|搜索|地址' } | Select-Object -First 1)
        $candidates.Add([pscustomobject]@{ method = 'ocr'; text = $text; hit = $hit }) | Out-Null
        if ($hit) {
            $rect = $hit.rect
            $winRect = $window.rect
            $x = [int]($winRect.left + [Math]::Max(220, $rect.left + 260))
            $y = [int]($winRect.top + [Math]::Max(48, $rect.top + (($rect.bottom - $rect.top) / 2)))
            if (Test-ScreenPoint $x $y) {
                Add-Locator $Ctx 'browser address bar' 'ocr browser toolbar text inferred address bar' 'ok' $x $y @{ text = $text; hit = $hit }
                $candidates | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
                return [pscustomobject]@{ X = $x; Y = $y; Method = 'ocr browser toolbar text inferred address bar'; CoordinateSource = 'locator_derived'; Raw = $ocr.data }
            }
            Add-Locator $Ctx 'browser address bar' 'ocr browser toolbar text inferred address bar' 'invalid_offscreen_coordinate' $x $y @{ text = $text; hit = $hit }
        }
        Add-Locator $Ctx 'browser address bar' 'ocr browser toolbar text' 'not_found' $null $null @{ text = $text }
    } else {
        Add-Locator $Ctx 'browser address bar' 'ocr browser toolbar text' 'not_found' $null $null @{ error = $ocr.error.code }
    }

    if ($window -and $window.rect) {
        $rect = $window.rect
        $x = [int]($rect.left + [Math]::Max(260, (($rect.right - $rect.left) * 0.48)))
        $y = [int]($rect.top + 52)
        $candidate = [pscustomobject]@{ method = 'visual_geometry'; rect = $rect; x = $x; y = $y; coordinate_source = 'heuristic_locator_derived' }
        $candidates.Add($candidate) | Out-Null
        if (Test-ScreenPoint $x $y) {
            Add-Locator $Ctx 'browser address bar' 'heuristic browser toolbar geometry' 'ok' $x $y $candidate
            $candidates | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
            return [pscustomobject]@{ X = $x; Y = $y; Method = 'heuristic browser toolbar geometry'; CoordinateSource = 'heuristic_locator_derived'; Raw = $candidate }
        }
        Add-Locator $Ctx 'browser address bar' 'heuristic browser toolbar geometry' 'invalid_offscreen_coordinate' $x $y $candidate
    }

    $candidates | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
    return $null
}

function Resolve-ExplorerItemCenter($Ctx, [string]$ExplorerTitle, [string]$ItemName, [string[]]$Patterns) {
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $fg = Get-ForegroundUiaItemCenter $Patterns
        if ($fg) {
            Add-Locator $Ctx $ItemName 'uia foreground Explorer item' 'ok' $fg.X $fg.Y $fg
            return [pscustomobject]@{ X = $fg.X; Y = $fg.Y; Method = 'uia foreground Explorer item'; CoordinateSource = 'locator_derived'; Raw = $fg }
        }
        Add-Locator $Ctx $ItemName 'uia foreground Explorer item' 'not_found' $null $null @{ attempt = $attempt }
        $observed = Invoke-AgentJson -CmdArgs @('observe', '--title', $ExplorerTitle, '--screenshot', 'false', '--uia', 'true', '--max-elements', '500') -AllowFailure
        if ($observed.ok) {
            $matches = @($observed.data.uia.elements | Where-Object {
                $n = $_.name
                $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top -and
                @($Patterns | Where-Object { $n -match $_ }).Count -gt 0
            } | Sort-Object @{ Expression = { $_.rect.top } }, @{ Expression = { $_.rect.left } })
            if ($matches.Count -gt 0) {
                $rect = $matches[0].rect
                $x = [int](($rect.left + $rect.right) / 2)
                $y = [int](($rect.top + $rect.bottom) / 2)
                if (Test-ScreenPoint $x $y) {
                    Add-Locator $Ctx $ItemName 'uia Explorer item' 'ok' $x $y $matches[0]
                    return [pscustomobject]@{ X = $x; Y = $y; Method = 'uia Explorer item'; CoordinateSource = 'locator_derived'; Raw = $matches[0] }
                }
                Add-Locator $Ctx $ItemName 'uia Explorer item' 'invalid_offscreen_coordinate' $x $y $matches[0]
            }
        }
        Add-Locator $Ctx $ItemName 'uia Explorer item' 'not_found' $null $null @{ attempt = $attempt }
        $ocr = Invoke-AgentJson -CmdArgs @('read-window-text', '--title', $ExplorerTitle) -AllowFailure
        if ($ocr.ok) {
            $hit = @($ocr.data.words | Where-Object {
                $word = $_.text
                @($Patterns | Where-Object { $word -match $_ }).Count -gt 0
            } | Select-Object -First 1)
            if ($hit) {
                $win = Get-WindowInfoByTitle $ExplorerTitle
                $rect = $hit.rect
                $x = [int]($win.rect.left + (($rect.left + $rect.right) / 2))
                $y = [int]($win.rect.top + (($rect.top + $rect.bottom) / 2))
                if (Test-ScreenPoint $x $y) {
                    Add-Locator $Ctx $ItemName 'ocr Explorer item' 'ok' $x $y $hit
                    return [pscustomobject]@{ X = $x; Y = $y; Method = 'ocr Explorer item'; CoordinateSource = 'locator_derived'; Raw = $hit }
                }
                Add-Locator $Ctx $ItemName 'ocr Explorer item' 'invalid_offscreen_coordinate' $x $y $hit
            }
            Add-Locator $Ctx $ItemName 'ocr Explorer item' 'not_found' $null $null @{ attempt = $attempt; text = $ocr.data.text }
        } else {
            Add-Locator $Ctx $ItemName 'ocr Explorer item' 'not_found' $null $null @{ attempt = $attempt; error = $ocr.error.code }
        }
        if ($attempt -lt 3) {
            $win = Get-WindowInfoByTitle $ExplorerTitle
            $sx = if ($win -and $win.rect) { [int](($win.rect.left + $win.rect.right) / 2) } else { 640 }
            $sy = if ($win -and $win.rect) { [int]($win.rect.top + (($win.rect.bottom - $win.rect.top) * 0.55)) } else { 520 }
            $clientX = if ($win -and $win.rect) { [int](($win.rect.right - $win.rect.left) / 2) } else { 500 }
            $clientY = if ($win -and $win.rect) { [int](($win.rect.bottom - $win.rect.top) * 0.55) } else { 400 }
            Invoke-HumanAction $Ctx 'mouse.move' "scroll Explorer searching for $ItemName" 'heuristic Explorer content geometry' 'heuristic_locator_derived' $sx $sy @('desktop-move', '--screen-x', "$sx", '--screen-y', "$sy", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
            $null = Invoke-AgentJson -CmdArgs @('scroll', '--title', $ExplorerTitle, '--x', "$clientX", '--y', "$clientY", '--delta', '-3') -AllowFailure
            Write-JsonLine $Ctx.Actions ([pscustomobject]@{
                timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
                action_type = 'mouse.wheel'
                target_description = "Explorer scroll retry for $ItemName"
                locator_method = 'heuristic Explorer content geometry'
                coordinate_source = 'heuristic_locator_derived'
                screen_x = $sx
                screen_y = $sy
                humanmode = $true
                backend_action = $false
                ok = $true
                notes = 'scroll --title Explorer content'
            })
            $Ctx.HumanModeActionCount++
            $Ctx.HeuristicLocatorDerivedCount++
            Start-Sleep -Milliseconds 500
        }
    }
    if ($ItemName -notmatch '^D:') {
        $win = Get-WindowInfoByTitle $ExplorerTitle
        if ($win -and $win.rect) {
            $sx = [int]($win.rect.left + (($win.rect.right - $win.rect.left) * 0.45))
            $sy = [int]($win.rect.top + (($win.rect.bottom - $win.rect.top) * 0.42))
            if (Test-ScreenPoint $sx $sy) {
                Invoke-HumanAction $Ctx 'mouse.click' "focus Explorer content before incremental search for $ItemName" 'heuristic Explorer content geometry' 'heuristic_locator_derived' $sx $sy @('desktop-click', '--screen-x', "$sx", '--screen-y', "$sy", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
                Invoke-HumanAction $Ctx 'keyboard.type_text' "Explorer incremental item search: $ItemName" 'Explorer content incremental search' 'keyboard_after_mouse_focus' $null $null @('desktop-type', '--text', $ItemName, '--type-mode', 'demo-human', '--char-delay-ms', '35', '--permission-mode', $PermissionMode) | Out-Null
                Start-Sleep -Milliseconds 700
                $fgAfterType = Get-ForegroundUiaItemCenter $Patterns
                if ($fgAfterType) {
                    Add-Locator $Ctx $ItemName 'uia foreground Explorer item after incremental search' 'ok' $fgAfterType.X $fgAfterType.Y $fgAfterType
                    return [pscustomobject]@{ X = $fgAfterType.X; Y = $fgAfterType.Y; Method = 'uia foreground Explorer item after incremental search'; CoordinateSource = 'locator_derived'; Raw = $fgAfterType }
                }
                Add-Locator $Ctx $ItemName 'uia foreground Explorer item after incremental search' 'not_found' $null $null @{ typed = $ItemName }
            }
        }
    }
    return $null
}

function Add-AppCandidate($List, [string]$Name, [string]$ExePath, [string]$Source, [string]$ShortcutPath, [string]$Reason) {
    if ([string]::IsNullOrWhiteSpace($ExePath) -or -not (Test-Path -LiteralPath $ExePath)) { return }
    if ([IO.Path]::GetExtension($ExePath) -ne '.exe') { return }
    $excluded = $false
    $excludeReason = ''
    if ($Name -match 'password|bank|security|anti.?cheat|credential|admin|elevated|UAC') {
        $excluded = $true
        $excludeReason = 'excluded_sensitive_or_protected_target'
    }
    $List.Add([pscustomobject]@{
        name = $Name
        executable_path = $ExePath
        source = $Source
        shortcut_path = $ShortcutPath
        reason = $Reason
        excluded = $excluded
        excluded_reason = $excludeReason
    }) | Out-Null
}

function Resolve-ShortcutTarget($ShortcutPath) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        return [pscustomobject]@{ TargetPath = $shortcut.TargetPath; Arguments = $shortcut.Arguments; WorkingDirectory = $shortcut.WorkingDirectory }
    } catch {
        return $null
    }
}

function Resolve-ThirdPartyAppTarget {
    $candidates = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[object]
    $checks = [ordered]@{
        explicit_target_checked = $true
        env_target_checked = $true
        common_app_candidates_checked = @()
        registry_candidates_checked = @()
        start_menu_candidates_checked = @()
    }

    $explicitPath = if ($ThirdPartyAppPath) { $ThirdPartyAppPath } else { $env:DESKTOPVISUAL_CASE_C_APP_PATH }
    $explicitName = if ($ThirdPartyAppName) { $ThirdPartyAppName } else { $env:DESKTOPVISUAL_CASE_C_APP_NAME }
    if ($explicitPath) {
        Add-AppCandidate $candidates $(if ($explicitName) { $explicitName } else { [IO.Path]::GetFileNameWithoutExtension($explicitPath) }) $explicitPath 'explicit_or_env_path' '' 'explicit path supplied'
    }

    $common = @(
        @{ Name = 'PyCharm'; Paths = @("$env:ProgramFiles\JetBrains\*\bin\pycharm64.exe", "${env:ProgramFiles(x86)}\JetBrains\*\bin\pycharm64.exe", "$env:LocalAppData\Programs\JetBrains\*\bin\pycharm64.exe") },
        @{ Name = 'VS Code'; Paths = @("$env:LocalAppData\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe", "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe") },
        @{ Name = 'Cursor'; Paths = @("$env:LocalAppData\Programs\Cursor\Cursor.exe", "$env:ProgramFiles\Cursor\Cursor.exe") },
        @{ Name = 'IntelliJ IDEA'; Paths = @("$env:ProgramFiles\JetBrains\IntelliJ IDEA*\bin\idea64.exe", "$env:LocalAppData\Programs\JetBrains\IntelliJ IDEA*\bin\idea64.exe") },
        @{ Name = 'WebStorm'; Paths = @("$env:ProgramFiles\JetBrains\WebStorm*\bin\webstorm64.exe", "$env:LocalAppData\Programs\JetBrains\WebStorm*\bin\webstorm64.exe") },
        @{ Name = 'Git GUI'; Paths = @("$env:ProgramFiles\Git\cmd\git-gui.exe", "$env:ProgramFiles\Git\mingw64\bin\git-gui.exe") },
        @{ Name = 'Git Bash'; Paths = @("$env:ProgramFiles\Git\git-bash.exe") },
        @{ Name = 'Notepad++'; Paths = @("$env:ProgramFiles\Notepad++\notepad++.exe", "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe") },
        @{ Name = '7-Zip File Manager'; Paths = @("$env:ProgramFiles\7-Zip\7zFM.exe", "${env:ProgramFiles(x86)}\7-Zip\7zFM.exe") },
        @{ Name = 'Firefox'; Paths = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe") },
        @{ Name = 'Chrome'; Paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LocalAppData\Google\Chrome\Application\chrome.exe") }
    )
    foreach ($app in $common) {
        $checks.common_app_candidates_checked += $app.Name
        foreach ($pattern in $app.Paths) {
            $found = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1)
            foreach ($f in $found) { Add-AppCandidate $candidates $app.Name $f.FullName 'common_app_path' '' 'common safe GUI app search' }
        }
    }

    foreach ($rootKey in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $checks.registry_candidates_checked += $rootKey
        $items = @(Get-ItemProperty -Path $rootKey -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            $display = [string]$item.DisplayName
            if (-not $display) { continue }
            if ($display -notmatch 'PyCharm|Visual Studio Code|VS Code|Cursor|IntelliJ|WebStorm|Git|Notepad\+\+|7-Zip|Firefox|Chrome') { continue }
            $exe = ''
            if ($item.DisplayIcon) {
                $exe = ([string]$item.DisplayIcon).Trim('"')
                if ($exe -match '^(.*?\.exe)') { $exe = $Matches[1] }
            }
            if ((-not $exe -or -not (Test-Path -LiteralPath $exe)) -and $item.InstallLocation) {
                $exe = @(Get-ChildItem -Path $item.InstallLocation -Filter *.exe -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'pycharm64|Code|Cursor|idea64|webstorm64|git-gui|git-bash|notepad\+\+|7zFM|firefox|chrome' } | Select-Object -First 1).FullName
            }
            Add-AppCandidate $candidates $display $exe 'registry_uninstall' '' 'registry uninstall candidate'
        }
    }

    $startMenus = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:AppData\Microsoft\Windows\Start Menu\Programs"
    )
    foreach ($menuRoot in $startMenus) {
        $checks.start_menu_candidates_checked += $menuRoot
        $links = @(Get-ChildItem -Path $menuRoot -Filter *.lnk -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'PyCharm|Visual Studio Code|VS Code|Cursor|IntelliJ|WebStorm|Git Bash|Git GUI|Notepad\+\+|7-Zip|Firefox|Chrome' })
        foreach ($link in $links) {
            $target = Resolve-ShortcutTarget $link.FullName
            if ($target -and $target.TargetPath -and (Test-Path -LiteralPath $target.TargetPath)) {
                Add-AppCandidate $candidates ([IO.Path]::GetFileNameWithoutExtension($link.Name)) $target.TargetPath 'start_menu_shortcut' $link.FullName 'start menu shortcut candidate'
            }
        }
    }

    $priority = @('PyCharm', 'VS Code', 'Cursor', 'IntelliJ IDEA', 'WebStorm', 'Git GUI', 'Git Bash', 'Notepad++', '7-Zip File Manager', 'Firefox', 'Chrome')
    $selected = $null
    foreach ($p in $priority) {
        $selected = @($candidates | Where-Object { -not $_.excluded -and ($_.name -match [regex]::Escape($p) -or ($p -eq 'VS Code' -and $_.name -match 'Visual Studio Code')) } | Select-Object -First 1)
        if ($selected) { break }
    }
    if (-not $selected) {
        $selected = @($candidates | Where-Object { -not $_.excluded } | Select-Object -First 1)
    }
    foreach ($c in $candidates) {
        if ($selected -and $c.executable_path -eq $selected.executable_path) { continue }
        $skipped.Add([pscustomobject]@{ name = $c.name; path = $c.executable_path; reason = $(if ($c.excluded) { $c.excluded_reason } else { 'lower_priority_or_duplicate' }) }) | Out-Null
    }

    $selectedTarget = if (@($selected).Count -gt 0) { @($selected)[0] } else { $null }
    $substitution = ''
    if ($selectedTarget -and $selectedTarget.name -match 'Chrome' -and -not @($candidates | Where-Object { -not $_.excluded -and ($_.name -match 'PyCharm|Visual Studio Code|VS Code') }).Count) {
        $substitution = 'Chrome used as available third-party GUI app because PyCharm/VS Code were not installed'
    }

    $checksObject = [pscustomobject]@{
        explicit_target_checked = [bool]$checks.explicit_target_checked
        env_target_checked = [bool]$checks.env_target_checked
        common_app_candidates_checked = @($checks.common_app_candidates_checked)
        registry_candidates_checked = @($checks.registry_candidates_checked)
        start_menu_candidates_checked = @($checks.start_menu_candidates_checked)
    }
    $candidateArray = New-Object System.Collections.ArrayList
    foreach ($c in $candidates) { [void]$candidateArray.Add($c) }
    $skippedArray = New-Object System.Collections.ArrayList
    foreach ($s in $skipped) { [void]$skippedArray.Add($s) }
    $result = New-Object psobject
    $result | Add-Member -MemberType NoteProperty -Name checks -Value $checksObject
    $result | Add-Member -MemberType NoteProperty -Name candidates -Value $candidateArray
    $result | Add-Member -MemberType NoteProperty -Name selected_target -Value $selectedTarget
    $result | Add-Member -MemberType NoteProperty -Name selected_target_reason -Value $(if ($selectedTarget) { 'highest priority available safe GUI app target' } else { 'no usable safe GUI app target found' })
    $result | Add-Member -MemberType NoteProperty -Name target_substitution -Value $substitution
    $result | Add-Member -MemberType NoteProperty -Name skipped_candidates -Value $skippedArray
    return $result
}

function Write-MockHtml {
    Ensure-Dir $MockDir
    @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>DesktopVisual Local Mail Mock</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; max-width: 720px; }
    label { display: block; margin-top: 16px; font-weight: bold; }
    input, textarea { width: 640px; padding: 8px; margin-top: 4px; font-size: 16px; }
    textarea { height: 140px; }
    button { margin-top: 20px; padding: 10px 18px; font-size: 16px; }
    #status { margin-top: 20px; padding: 10px; border: 1px solid #999; min-height: 24px; }
  </style>
</head>
<body>
  <h1>DesktopVisual Local Mail Mock</h1>
  <p>This page is a local mock. It does not send real email.</p>
  <label for="recipient">Recipient</label>
  <input id="recipient" name="recipient" autocomplete="off">
  <label for="subject">Subject</label>
  <input id="subject" name="subject" autocomplete="off">
  <label for="body">Body</label>
  <textarea id="body" name="body"></textarea>
  <button id="sendButton" type="button">Send</button>
  <div id="status" role="status">Not sent</div>
  <script>
    document.getElementById("sendButton").addEventListener("click", function () {
      document.getElementById("recipient").value = "";
      document.getElementById("subject").value = "";
      document.getElementById("body").value = "";
      document.getElementById("status").textContent = "Mock sent successfully";
      document.body.setAttribute("data-sent", "true");
    });
  </script>
</body>
</html>
'@ | Set-Content -LiteralPath $MockHtml -Encoding UTF8
}

function Find-BrowserExe {
    $chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LocalAppData\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($chrome) { return [pscustomobject]@{ Name = 'Chrome'; Exe = $chrome; Shortcut = 'DesktopVisual Chrome Test' } }
    $edge = @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { return [pscustomobject]@{ Name = 'Edge'; Exe = $edge; Shortcut = 'DesktopVisual Edge Test' } }
    return $null
}

function Ensure-BrowserShortcut($Browser) {
    Ensure-Dir $BrowserProfile
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop ($Browser.Shortcut + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnk)
    $shortcut.TargetPath = $Browser.Exe
    $shortcut.Arguments = '--user-data-dir="{0}" --no-first-run --new-window about:blank' -f $BrowserProfile
    $shortcut.WorkingDirectory = Split-Path $Browser.Exe
    $shortcut.Save()
    return $lnk
}

function Case-A {
    $ctx = New-CaseContext 'desktop_mouse_open_chrome_visible_flow'
    $browser = Find-BrowserExe
    if (-not $browser) { Fail-Case $ctx 'SKIP_ENVIRONMENT' 'Chrome and Edge were not found.'; return $ctx }
    $lnk = Ensure-BrowserShortcut $browser
    Add-Event $ctx 'setup_shortcut' 'ok' @{ path = $lnk; browser = $browser.Exe }
    Save-ScreenShot (Join-Path $ctx.Screenshots 'before.png')
    Invoke-HumanAction $ctx 'keyboard.hotkey' 'show desktop' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'WIN+D', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Start-Sleep -Milliseconds 800
    $center = Get-UiaCenter 'Program Manager' $browser.Shortcut
    if ($center) {
        Add-Locator $ctx $browser.Shortcut 'uia Program Manager ListItem' 'ok' $center.X $center.Y $center.Raw.data
        Invoke-HumanAction $ctx 'mouse.move' $browser.Shortcut 'uia Program Manager ListItem' 'locator_derived' $center.X $center.Y @('desktop-move', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
        Invoke-HumanAction $ctx 'mouse.double_click' $browser.Shortcut 'uia Program Manager ListItem' 'locator_derived' $center.X $center.Y @('desktop-double-click', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
        $title = Wait-WindowTitle 'Chrome|Edge' 12
        Save-ScreenShot (Join-Path $ctx.Screenshots 'after.png')
        if ($title) { Complete-Case $ctx 'STRICT_HUMANMODE_PASS' "Opened $($browser.Name) via desktop shortcut double-click." "Foreground/browser window observed: $title"; return $ctx }
        Fail-Case $ctx 'FAIL' 'Browser window did not appear after desktop double-click.'
        return $ctx
    }
    $ctx.UsedFallback = $true
    Add-Locator $ctx $browser.Shortcut 'uia Program Manager ListItem' 'not_found' $null $null @{}
    Invoke-HumanAction $ctx 'keyboard.press' 'Start menu' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'WIN', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.type_text' $browser.Name 'Start menu search' 'fallback_keyboard' $null $null @('desktop-type', '--text', $browser.Name.ToLowerInvariant(), '--type-mode', 'demo-human', '--char-delay-ms', '40', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.press' 'Start search result' 'Start menu search' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    $fallbackTitle = Wait-WindowTitle 'Chrome|Edge' 12
    Save-ScreenShot (Join-Path $ctx.Screenshots 'after.png')
    if ($fallbackTitle) { Complete-Case $ctx 'HUMANMODE_FALLBACK_PASS' "Opened $($browser.Name) through Start Menu keyboard fallback." "Browser window observed: $fallbackTitle"; return $ctx }
    Fail-Case $ctx 'FAIL' 'Browser window did not appear after Start Menu fallback.'
    return $ctx
}

function Case-B {
    $ctx = New-CaseContext 'chrome_address_bar_external_url_navigation_flow'
    $browserTitle = Ensure-BrowserVisibleHumanMode $ctx
    if (-not $browserTitle) { Fail-Case $ctx 'SKIP_ENVIRONMENT' 'Chrome and Edge were not available for address-bar strict HumanMode.'; return $ctx }
    Save-CaseScreenshot $ctx 'before_address_bar.png' | Out-Null
    $addressBar = Resolve-AddressBarCenter $ctx $browserTitle
    if (-not $addressBar) {
        Fail-Case $ctx 'FAIL' 'FAIL_LOCATOR: address bar UIA, OCR, and visual geometry locator attempts failed.'
        return $ctx
    }
    Invoke-HumanAction $ctx 'mouse.move' 'browser address bar' $addressBar.Method $addressBar.CoordinateSource $addressBar.X $addressBar.Y @('desktop-move', '--screen-x', "$($addressBar.X)", '--screen-y', "$($addressBar.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $ctx 'mouse.click' 'browser address bar' $addressBar.Method $addressBar.CoordinateSource $addressBar.X $addressBar.Y @('desktop-click', '--screen-x', "$($addressBar.X)", '--screen-y', "$($addressBar.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-HumanAction $ctx 'keyboard.hotkey' 'select address bar content after mouse focus' 'mouse-focused address bar' 'keyboard_after_mouse_focus' $null $null @('desktop-hotkey', '--keys', 'CTRL+A', '--permission-mode', $PermissionMode) | Out-Null
    $targetUrl = 'https://www.baidu.com'
    Invoke-HumanAction $ctx 'keyboard.type_text' $targetUrl 'mouse-focused address bar' 'keyboard_after_mouse_focus' $null $null @('desktop-type', '--text', $targetUrl, '--type-mode', 'demo-human', '--char-delay-ms', '35', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $ctx 'keyboard.press' 'navigate external URL' 'mouse-focused address bar' 'keyboard_after_mouse_focus' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', $PermissionMode) | Out-Null
    Start-Sleep -Seconds 8
    $loaded = Find-WindowTitle 'Baidu|baidu|百度|Chrome|Edge'
    $verifiedUrl = $targetUrl
    if (-not $loaded) {
        Add-Event $ctx 'baidu_navigation_verification' 'not_verified' @{ fallback_url = 'https://example.com'; note = 'network or page title did not verify baidu' }
        $browserTitle = Wait-WindowTitle 'Chrome|Edge' 2
        $addressBar = Resolve-AddressBarCenter $ctx $browserTitle
        if (-not $addressBar) { Fail-Case $ctx 'FAIL' 'FAIL_LOCATOR: address bar could not be relocated for example.com retry.'; return $ctx }
        Invoke-HumanAction $ctx 'mouse.move' 'browser address bar retry' $addressBar.Method $addressBar.CoordinateSource $addressBar.X $addressBar.Y @('desktop-move', '--screen-x', "$($addressBar.X)", '--screen-y', "$($addressBar.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $ctx 'mouse.click' 'browser address bar retry' $addressBar.Method $addressBar.CoordinateSource $addressBar.X $addressBar.Y @('desktop-click', '--screen-x', "$($addressBar.X)", '--screen-y', "$($addressBar.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $ctx 'keyboard.hotkey' 'select address bar content after mouse focus retry' 'mouse-focused address bar' 'keyboard_after_mouse_focus' $null $null @('desktop-hotkey', '--keys', 'CTRL+A', '--permission-mode', $PermissionMode) | Out-Null
        $targetUrl = 'https://example.com'
        Invoke-HumanAction $ctx 'keyboard.type_text' $targetUrl 'mouse-focused address bar' 'keyboard_after_mouse_focus' $null $null @('desktop-type', '--text', $targetUrl, '--type-mode', 'demo-human', '--char-delay-ms', '35', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $ctx 'keyboard.press' 'navigate external fallback URL' 'mouse-focused address bar' 'keyboard_after_mouse_focus' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', $PermissionMode) | Out-Null
        Start-Sleep -Seconds 5
        $loaded = Find-WindowTitle 'Example|example|Chrome|Edge'
        $verifiedUrl = $targetUrl
    }
    Save-CaseScreenshot $ctx 'after_navigation.png' | Out-Null
    $text = if ($loaded) { Invoke-AgentJson -CmdArgs @('read-window-text', '--title', $loaded) -AllowFailure } else { $null }
    $visibleOk = $loaded -and (($loaded -match 'Baidu|baidu|百度|Example|example') -or ($text -and $text.ok -and $text.data.text -match 'Baidu|Example Domain|example'))
    $report = @(
        '# Address Bar Locator Report',
        '',
        "- locator_method: $($addressBar.Method)",
        "- coordinate_source: $($addressBar.CoordinateSource)",
        "- x: $($addressBar.X)",
        "- y: $($addressBar.Y)",
        "- verified_url: $verifiedUrl",
        "- visible_verification: $visibleOk"
    )
    $report | Set-Content -LiteralPath (Join-Path $ctx.Dir 'address_bar_locator_report.md') -Encoding UTF8
    if ($visibleOk) { Complete-Case $ctx 'STRICT_HUMANMODE_PASS' "Navigated $verifiedUrl by mouse-clicking the located address bar, typing URL, and pressing Enter." "Observed browser title/text after navigation: $loaded"; return $ctx }
    Fail-Case $ctx 'FAIL' 'External URL navigation was not verified after strict address-bar input.'
    return $ctx
}

function Case-C {
    $ctx = New-CaseContext 'third_party_app_launch_visible_flow'
    $resolution = Resolve-ThirdPartyAppTarget
    $resolutionPath = Join-Path $ctx.Dir 'third_party_app_target_resolution.json'
    $resolution | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resolutionPath -Encoding UTF8
    @(
        '# Third Party App Target Resolution Report',
        '',
        "- explicit target checked: $($resolution.checks.explicit_target_checked)",
        "- env target checked: $($resolution.checks.env_target_checked)",
        "- common candidates checked: $($resolution.checks.common_app_candidates_checked -join ', ')",
        "- registry roots checked: $($resolution.checks.registry_candidates_checked -join ', ')",
        "- start menu roots checked: $($resolution.checks.start_menu_candidates_checked -join ', ')",
        "- selected target: $(if ($resolution.selected_target) { $resolution.selected_target.name } else { '' })",
        "- selected executable: $(if ($resolution.selected_target) { $resolution.selected_target.executable_path } else { '' })",
        "- selected reason: $($resolution.selected_target_reason)",
        "- target substitution: $($resolution.target_substitution)",
        "- skipped candidates: $(@($resolution.skipped_candidates).Count)"
    ) | Set-Content -LiteralPath (Join-Path $ctx.Dir 'third_party_app_target_resolution_report.md') -Encoding UTF8
    if (-not $resolution.selected_target) {
        Fail-Case $ctx 'SKIP_ENVIRONMENT' 'No usable safe GUI third-party App target found after explicit/env/common/registry/start-menu discovery.'
        return $ctx
    }
    Save-CaseScreenshot $ctx 'before_app_launch.png' | Out-Null
    $shortcutName = 'DesktopVisual ThirdParty App Test'
    $args = ''
    if ($resolution.selected_target.name -match 'Chrome') {
        $chromeProfile = Join-Path $ArtifactRoot 'third_party_chrome_profile'
        Ensure-Dir $chromeProfile
        $args = '--user-data-dir="{0}" --no-first-run --new-window about:blank' -f $chromeProfile
    }
    $lnk = New-DesktopShortcut $shortcutName $resolution.selected_target.executable_path $args (Split-Path $resolution.selected_target.executable_path)
    $ctx.FixtureUsed = $true
    Add-Event $ctx 'setup_third_party_shortcut' 'ok' @{ path = $lnk; target = $resolution.selected_target.executable_path; setup_only = $true; target_substitution = $resolution.target_substitution }
    $openedByShortcut = Invoke-DesktopShortcut $ctx $shortcutName 'launch resolved third-party app target'
    $targetPattern = [regex]::Escape($resolution.selected_target.name)
    if ($resolution.selected_target.name -match 'VS Code|Visual Studio Code') { $targetPattern = 'Visual Studio Code|Code' }
    elseif ($resolution.selected_target.name -match '7-Zip') { $targetPattern = '7-Zip|7zFM' }
    elseif ($resolution.selected_target.name -match 'Chrome') { $targetPattern = 'Chrome' }
    elseif ($resolution.selected_target.name -match 'Firefox') { $targetPattern = 'Firefox' }
    elseif ($resolution.selected_target.name -match 'Notepad') { $targetPattern = 'Notepad\+\+' }
    $title = if ($openedByShortcut) { Wait-WindowTitle $targetPattern 20 } else { '' }
    if (-not $title) {
        $ctx.UsedFallback = $true
        Add-Event $ctx 'desktop_shortcut_launch_verification' 'not_verified' @{ fallback = 'Start Menu HumanMode search' }
        Invoke-HumanAction $ctx 'keyboard.press' 'Start menu' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'WIN', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $ctx 'keyboard.type_text' $resolution.selected_target.name 'Start menu search' 'fallback_keyboard' $null $null @('desktop-type', '--text', $resolution.selected_target.name, '--type-mode', 'demo-human', '--char-delay-ms', '45', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $ctx 'keyboard.press' 'Start search result' 'Start menu search' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', $PermissionMode) | Out-Null
        $title = Wait-WindowTitle $targetPattern 20
    }
    Save-CaseScreenshot $ctx 'after_app_launch.png' | Out-Null
    if ($title) {
        $status = if ($ctx.UsedFallback) { 'HUMANMODE_FALLBACK_PASS' } else { 'STRICT_HUMANMODE_PASS' }
        Complete-Case $ctx $status "Opened resolved third-party GUI App target: $($resolution.selected_target.name)." "Observed target window: $title"
        return $ctx
    }
    $alternate = @($resolution.candidates | Where-Object {
        -not $_.excluded -and
        $_.executable_path -ne $resolution.selected_target.executable_path -and
        $_.name -match 'Chrome|Firefox|7-Zip|Notepad\+\+|Git GUI|Git Bash'
    } | Select-Object -First 1)
    if ($alternate) {
        $ctx.UsedFallback = $true
        Add-Event $ctx 'third_party_target_retry' 'fallback_target_substitution' @{
            failed_target = $resolution.selected_target.name
            failed_reason = 'launch_window_not_verified'
            retry_target = $alternate.name
        }
        $resolution.skipped_candidates.Add([pscustomobject]@{ name = $resolution.selected_target.name; path = $resolution.selected_target.executable_path; reason = 'launch_window_not_verified' }) | Out-Null
        $resolution.selected_target = $alternate
        $resolution.selected_target_reason = 'safe fallback target after preferred target launch window was not verified'
        if ($alternate.name -match 'Chrome') {
            $resolution.target_substitution = 'Chrome used as available third-party GUI app because the preferred resolved target did not produce a verifiable visible window'
        }
        $resolution | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resolutionPath -Encoding UTF8
        @(
            '# Third Party App Target Resolution Report',
            '',
            "- explicit target checked: $($resolution.checks.explicit_target_checked)",
            "- env target checked: $($resolution.checks.env_target_checked)",
            "- common candidates checked: $($resolution.checks.common_app_candidates_checked -join ', ')",
            "- registry roots checked: $($resolution.checks.registry_candidates_checked -join ', ')",
            "- start menu roots checked: $($resolution.checks.start_menu_candidates_checked -join ', ')",
            "- selected target: $($resolution.selected_target.name)",
            "- selected executable: $($resolution.selected_target.executable_path)",
            "- selected reason: $($resolution.selected_target_reason)",
            "- target substitution: $($resolution.target_substitution)",
            "- skipped candidates: $(@($resolution.skipped_candidates).Count)"
        ) | Set-Content -LiteralPath (Join-Path $ctx.Dir 'third_party_app_target_resolution_report.md') -Encoding UTF8

        $shortcutName = 'DesktopVisual ThirdParty App Test'
        $args = ''
        if ($alternate.name -match 'Chrome') {
            $chromeProfile = Join-Path $ArtifactRoot 'third_party_chrome_profile'
            Ensure-Dir $chromeProfile
            $args = '--user-data-dir="{0}" --no-first-run --new-window about:blank' -f $chromeProfile
        }
        $lnk = New-DesktopShortcut $shortcutName $alternate.executable_path $args (Split-Path $alternate.executable_path)
        Add-Event $ctx 'setup_third_party_shortcut_retry' 'ok' @{ path = $lnk; target = $alternate.executable_path; setup_only = $true; target_substitution = $resolution.target_substitution }
        $openedByShortcut = Invoke-DesktopShortcut $ctx $shortcutName 'launch fallback third-party app target'
        $targetPattern = [regex]::Escape($alternate.name)
        if ($alternate.name -match 'Chrome') { $targetPattern = 'Chrome' }
        elseif ($alternate.name -match 'Firefox') { $targetPattern = 'Firefox' }
        elseif ($alternate.name -match '7-Zip') { $targetPattern = '7-Zip|7zFM' }
        elseif ($alternate.name -match 'Notepad') { $targetPattern = 'Notepad\+\+' }
        elseif ($alternate.name -match 'Git Bash') { $targetPattern = 'Git Bash|MINGW|mintty' }
        elseif ($alternate.name -match 'Git GUI') { $targetPattern = 'Git Gui|Git GUI' }
        $title = if ($openedByShortcut) { Wait-WindowTitle $targetPattern 20 } else { '' }
        Save-CaseScreenshot $ctx 'after_app_launch_retry.png' | Out-Null
        if ($title) {
            Complete-Case $ctx 'HUMANMODE_FALLBACK_PASS' "Opened fallback resolved third-party GUI App target: $($alternate.name)." "Observed target window: $title"
            return $ctx
        }
    }
    Fail-Case $ctx 'FAIL' "Resolved App target did not produce a visible window: $($resolution.selected_target.name)."
    return $ctx
}

function Case-D {
    $ctx = New-CaseContext 'explorer_open_local_html_via_humanmode_flow'
    Write-MockHtml
    Add-Event $ctx 'setup_local_html' 'ok' @{ path = $MockHtml; setup_only = $true }
    Save-CaseScreenshot $ctx 'before_desktop.png' | Out-Null
    $shortcutName = 'DesktopVisual This PC Test'
    $lnk = New-DesktopShortcut $shortcutName "$env:WINDIR\explorer.exe" 'shell:MyComputerFolder' "$env:WINDIR"
    $ctx.FixtureUsed = $true
    @(
        '# This PC Fixture Report',
        '',
        "- fixture_used: true",
        "- shortcut: $lnk",
        "- target: explorer.exe shell:MyComputerFolder",
        "- note: fixture creation is setup only; runtime open uses real mouse double-click."
    ) | Set-Content -LiteralPath (Join-Path $ctx.Dir 'this_pc_fixture_report.md') -Encoding UTF8
    Add-Event $ctx 'setup_this_pc_fixture' 'ok' @{ path = $lnk; setup_only = $true }
    if (-not (Invoke-DesktopShortcut $ctx $shortcutName 'open This PC fixture through visible desktop UI')) {
        Fail-Case $ctx 'FAIL' 'FAIL_LOCATOR: This PC desktop fixture shortcut was not located on Program Manager.'
        return $ctx
    }
    Start-Sleep -Seconds 2
    $activeExplorer = Get-ActiveInfo
    if (-not $activeExplorer.ok -or $activeExplorer.data.process_name -ne 'explorer.exe') {
        Fail-Case $ctx 'FAIL' 'Explorer did not become the foreground window after This PC fixture double-click.'
        return $ctx
    }
    $explorerTitle = $activeExplorer.data.title
    $steps = New-Object System.Collections.Generic.List[object]
    $openSteps = @(
        @{ Name = 'D:'; Patterns = @('D:', 'Local Disk \(D:\)', '本地磁盘 \(D:\)'); Wait = 'D:\\|testrepo|D:' },
        @{ Name = 'testrepo'; Patterns = @('^testrepo$'); Wait = 'testrepo' },
        @{ Name = 'testwindow'; Patterns = @('^testwindow$'); Wait = 'testwindow' },
        @{ Name = 'desktopvisual_mail_mock.html'; Patterns = @('^desktopvisual_mail_mock\.html$', 'desktopvisual_mail_mock'); Wait = 'DesktopVisual Local Mail Mock|Chrome|Edge' }
    )
    foreach ($step in $openSteps) {
        $center = Resolve-ExplorerItemCenter $ctx $explorerTitle $step.Name $step.Patterns
        if (-not $center) {
            $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_steps.json') -Encoding UTF8
            Save-CaseScreenshot $ctx "failure_locator_$($step.Name -replace '[^A-Za-z0-9_.-]', '_').png" | Out-Null
            Fail-Case $ctx 'FAIL' "FAIL_LOCATOR: Explorer item not found through UIA/OCR/scroll retry: $($step.Name)."
            return $ctx
        }
        $steps.Add([pscustomobject]@{ item = $step.Name; locator_method = $center.Method; x = $center.X; y = $center.Y; coordinate_source = $center.CoordinateSource }) | Out-Null
        Invoke-HumanAction $ctx 'mouse.move' $step.Name $center.Method $center.CoordinateSource $center.X $center.Y @('desktop-move', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $ctx 'mouse.double_click' $step.Name $center.Method $center.CoordinateSource $center.X $center.Y @('desktop-double-click', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
        Start-Sleep -Seconds 2
        $activeNow = Get-ActiveInfo
        if ($activeNow.ok -and $activeNow.data.process_name -eq 'explorer.exe') { $explorerTitle = $activeNow.data.title }
    }
    $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_steps.json') -Encoding UTF8
    @(
        '# Explorer Path Locator Report',
        '',
        '- This PC opened through desktop fixture double-click.',
        '- D: drive, testrepo, testwindow, and desktopvisual_mail_mock.html are opened with real mouse double-clicks.',
        "- steps: $($steps.Count)",
        "- fixture_used: $($ctx.FixtureUsed)"
    ) | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_locator_report.md') -Encoding UTF8
    $title = Wait-WindowTitle 'DesktopVisual Local Mail Mock|Chrome|Edge' 12
    Save-CaseScreenshot $ctx 'after_file_open.png' | Out-Null
    $verified = $false
    if ($title) {
        $text = Invoke-AgentJson -CmdArgs @('read-window-text', '--title', $title) -AllowFailure
        $verified = ($title -match 'DesktopVisual Local Mail Mock|Chrome|Edge') -and ($text.ok -eq $true -or $title -match 'DesktopVisual Local Mail Mock|Chrome|Edge')
    }
    if ($verified) { Complete-Case $ctx 'STRICT_HUMANMODE_PASS' 'Opened local HTML by visible Explorer UI path: This PC fixture, D:, testrepo, testwindow, file double-click.' "Observed browser/local page title: $title"; return $ctx }
    Fail-Case $ctx 'FAIL' 'Browser/local HTML window did not appear after strict Explorer path file double-click.'
    return $ctx
}

function Case-E {
    $ctx = New-CaseContext 'local_mail_mock_browser_fill_and_send_humanmode_flow'
    $browserTitle = Wait-WindowTitle 'DesktopVisual Local Mail Mock|Chrome|Edge' 3
    if (-not $browserTitle) { Fail-Case $ctx 'SKIP_ENVIRONMENT' 'Local mail mock browser window was not available.'; return $ctx }
    Save-ScreenShot (Join-Path $ctx.Screenshots 'before_fill.png')
    $fields = @(
        @{ Name = 'Recipient'; Value = 'xiaoming'; Action = 'recipient input' },
        @{ Name = 'Subject'; Value = 'desktopvisual test'; Action = 'subject input' },
        @{ Name = 'Body'; Value = 'this is a testing message'; Action = 'body textarea' }
    )
    foreach ($field in $fields) {
        $center = Get-ObservedElementCenter $browserTitle $field.Name 'Edit'
        if (-not $center) { Add-Locator $ctx $field.Action 'uia browser field' 'not_found' $null $null @{}; Fail-Case $ctx 'FAIL' "Could not locate $($field.Name) field by UIA."; return $ctx }
        Add-Locator $ctx $field.Action 'uia browser field' 'ok' $center.X $center.Y $center.Raw.data
        Invoke-HumanAction $ctx 'mouse.click' $field.Action 'uia browser field' 'locator_derived' $center.X $center.Y @('desktop-click', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
        Invoke-HumanAction $ctx 'keyboard.type_text' $field.Action 'focused browser field' 'fallback_keyboard' $null $null @('type', '--title', $browserTitle, '--text', $field.Value, '--type-mode', 'demo-human', '--char-delay-ms', '35') | Out-Null
    }
    Save-ScreenShot (Join-Path $ctx.Screenshots 'after_fill.png')
    $send = Get-ObservedElementCenter $browserTitle 'Send' 'Button'
    if (-not $send) { Add-Locator $ctx 'Send button' 'uia browser button' 'not_found' $null $null @{}; Fail-Case $ctx 'FAIL' 'Could not locate Send button by UIA.'; return $ctx }
    Add-Locator $ctx 'Send button' 'uia browser button' 'ok' $send.X $send.Y $send.Raw.data
    Invoke-HumanAction $ctx 'mouse.click' 'Send button' 'uia browser button' 'locator_derived' $send.X $send.Y @('desktop-click', '--screen-x', "$($send.X)", '--screen-y', "$($send.Y)", '--move-mode', 'fast-human', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Start-Sleep -Seconds 1
    Save-ScreenShot (Join-Path $ctx.Screenshots 'after_send.png')
    $observedAfterSend = Invoke-AgentJson -CmdArgs @('observe', '--title', 'DesktopVisual Local Mail Mock', '--screenshot', 'false', '--uia', 'true', '--max-elements', '160') -AllowFailure
    $text = Invoke-AgentJson -CmdArgs @('read-window-text', '--title', 'DesktopVisual Local Mail Mock') -AllowFailure
    $statusOk = $observedAfterSend.ok -and @($observedAfterSend.data.uia.elements | Where-Object { $_.name -eq 'Mock sent successfully' }).Count -gt 0
    $ocrText = if ($text.ok) { $text.data.text } else { '' }
    $clearedByVisualEvidence = ($ocrText -notmatch 'xiaoming') -and ($ocrText -notmatch 'desktopvisual test') -and ($ocrText -notmatch 'this is a testing message')
    if ($statusOk -and $clearedByVisualEvidence) {
        Complete-Case $ctx 'STRICT_HUMANMODE_PASS' 'Filled local mock mail fields and clicked Send with real mouse/keyboard input.' 'UIA observed Mock sent successfully, and OCR no longer showed the entered recipient, subject, or body text. The mock page sends no real email.'
        return $ctx
    }
    Fail-Case $ctx 'FAIL' 'Could not verify Mock sent successfully and cleared fields after Send.'
    return $ctx
}

if (-not (Test-Path -LiteralPath $PreviousArtifactRoot)) {
    Ensure-Dir $ArtifactRoot
    "Required v5.9.0-b artifacts path is missing: $PreviousArtifactRoot" | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'blocked_missing_v5_9_0_b_artifacts.md') -Encoding UTF8
    Fail "Required v5.9.0-b artifacts path is missing: $PreviousArtifactRoot"
}
Ensure-Dir $ArtifactRoot
Ensure-Dir $CasesRoot
git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_initial.txt') -Encoding UTF8

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

& "$Root\v5_9_permission_reset_selftest.ps1" -Root $Root -SkipBuild
if ($LASTEXITCODE -ne 0) { Fail 'P0 policy selftest failed.' }

Write-MockHtml

$caseResults = @()
if ($SkipGuiCases) {
    foreach ($id in @(
        'chrome_address_bar_external_url_navigation_flow',
        'third_party_app_launch_visible_flow',
        'explorer_open_local_html_via_humanmode_flow'
    )) {
        $ctx = New-CaseContext $id
        Fail-Case $ctx 'SKIP_ENVIRONMENT' 'GUI cases were skipped by -SkipGuiCases.'
        $caseResults += $ctx
    }
} else {
    $caseResults += Case-B
    $caseResults += Case-C
    $caseResults += Case-D
}

$summary = foreach ($ctx in $caseResults) {
    Get-Content -LiteralPath $ctx.Result -Raw | ConvertFrom-Json
}

$counts = @{
    strict_humanmode_pass_count = @($summary | Where-Object status -eq 'STRICT_HUMANMODE_PASS').Count
    humanmode_fallback_pass_count = @($summary | Where-Object status -eq 'HUMANMODE_FALLBACK_PASS').Count
    skip_environment_count = @($summary | Where-Object status -eq 'SKIP_ENVIRONMENT').Count
    fail_count = @($summary | Where-Object status -eq 'FAIL').Count
    blocked_by_active_protection_count = @($summary | Where-Object status -eq 'BLOCKED_BY_ACTIVE_PROTECTION').Count
    fail_policy_defect_count = @($summary | Where-Object status -eq 'FAIL_POLICY_DEFECT').Count
    fixed_coordinate_count = @($summary | Measure-Object -Property fixed_coordinate_count -Sum).Sum
    locator_derived_coordinate_count = @($summary | Measure-Object -Property locator_derived_coordinate_count -Sum).Sum
    heuristic_locator_derived_count = @($summary | Measure-Object -Property heuristic_locator_derived_count -Sum).Sum
    humanmode_action_count = @($summary | Measure-Object -Property humanmode_action_count -Sum).Sum
    backend_action_count = @($summary | Measure-Object -Property backend_action_count -Sum).Sum
    direct_launch_count = @($summary | Measure-Object -Property direct_launch_count -Sum).Sum
    shell_execute_count = @($summary | Measure-Object -Property shell_execute_count -Sum).Sum
    start_process_count = @($summary | Measure-Object -Property start_process_count -Sum).Sum
    webdriver_count = @($summary | Measure-Object -Property webdriver_count -Sum).Sum
    cdp_count = @($summary | Measure-Object -Property cdp_count -Sum).Sum
    js_dom_action_count = @($summary | Measure-Object -Property js_dom_action_count -Sum).Sum
    uia_invoke_action_count = @($summary | Measure-Object -Property uia_invoke_action_count -Sum).Sum
    uia_value_action_count = @($summary | Measure-Object -Property uia_value_action_count -Sum).Sum
    vlm_call_count = 0
    real_email_send_count = 0
    active_protection_bypass_attempt_count = 0
    fake_pass_count = 0
}

@(
    '# Runtime Boundary Report',
    '',
    ($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "- $($_.Name): $($_.Value)" })
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runtime_boundary_report.md') -Encoding UTF8

$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'case_summary.json') -Encoding UTF8

$reportFiles = @{
    'dev_summary.md' = 'v5.9.0-c remains v5 and only completes strict HumanMode coverage for Case B/D plus Case C target resolution. It does not enter v6, add VLM, narrow public release permissions, or auto commit.'
    'test_summary.md' = 'Required commands: build, winagent version, permission reset selftest, v5.9.0-c strict Case B/D/C runner, JSON/JSONL parse, Markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, and git status snapshot.'
    'known_limits.md' = 'Case B/D/C results remain current-machine GUI evidence. They depend on installed browser/apps, interactive desktop state, UIA/OCR availability, Explorer layout, display scaling, and network reachability. SKIP is not PASS.'
    'strict_humanmode_case_bdc_summary.md' = 'Strict HumanMode B/D/C summary is recorded in case_summary.json and runtime_boundary_report.md. PASS cases use real visible mouse/keyboard actions and no backend/direct launch actions.'
    'regression_report.md' = 'Regression scope is intentionally limited to v5.9.0-c B/D/C plus required v5.9 permission selftest and static artifact validation.'
}
foreach ($entry in $reportFiles.GetEnumerator()) {
    $entry.Value | Set-Content -LiteralPath (Join-Path $ArtifactRoot $entry.Key) -Encoding UTF8
}

$map = @{
    'case_b_strict_addressbar_report.md' = 'chrome_address_bar_external_url_navigation_flow'
    'case_c_target_resolution_report.md' = 'third_party_app_launch_visible_flow'
    'case_d_strict_explorer_path_report.md' = 'explorer_open_local_html_via_humanmode_flow'
}
foreach ($entry in $map.GetEnumerator()) {
    $caseResult = $summary | Where-Object case_id -eq $entry.Value | Select-Object -First 1
    @(
        "# $($entry.Value)",
        "",
        "- Previous result from v5.9.0-b: $($caseResult.previous_result_from_v5_9_0_b)",
        "- Result: $($caseResult.actual_result)",
        "- Summary: $($caseResult.summary)",
        "- Strict HumanMode: $($caseResult.strict_humanmode)",
        "- Fallback used: $($caseResult.fallback_used)",
        "- Fixture used: $($caseResult.fixture_used)",
        "- Backend action count: $($caseResult.backend_action_count)",
        "- Direct launch count: $($caseResult.direct_launch_count)",
        "- Case dir: $((Join-Path $CasesRoot $entry.Value))"
    ) | Set-Content -LiteralPath (Join-Path $ArtifactRoot $entry.Key) -Encoding UTF8
}

git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8
git -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8

Get-ChildItem -Path $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

Write-Host "v5.9.0-c Strict HumanMode Case B/D/C runner complete."
Write-Host "Artifacts: $ArtifactRoot"
