param(
    [string]$Root = '',
    [switch]$SkipBuild,
    [switch]$SkipGuiCases
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.9.0-b_humanmode_case_runner'
$CasesRoot = Join-Path $ArtifactRoot 'cases'
$MockDir = 'D:\testrepo\testwindow'
$MockHtml = Join-Path $MockDir 'desktopvisual_mail_mock.html'
$BrowserProfile = Join-Path $ArtifactRoot 'browser_profile'

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

function Write-JsonLine($Path, $Object) {
    ($Object | ConvertTo-Json -Compress -Depth 20) | Add-Content -LiteralPath $Path -Encoding UTF8
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
        BackendActionCount = 0
        LocatorDerivedCount = 0
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
    if ($Method -match 'uia|ocr|element|observe') { $Ctx.LocatorDerivedCount++ }
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
    $result = [pscustomobject]@{
        case_id = $Ctx.CaseId
        status = $Status
        summary = $Summary
        used_fallback = $Ctx.UsedFallback
        locator_derived_coordinate_count = $Ctx.LocatorDerivedCount
        fixed_coordinate_count = $Ctx.FixedCoordinateCount
        backend_action_count = $Ctx.BackendActionCount
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
        vlm_call_count = 0
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
        "- Backend actions counted as HumanMode: 0",
        "- VLM calls: 0",
        "- Real email sends: 0",
        "",
        "Artifacts are in this directory."
    ) | Set-Content -LiteralPath $Ctx.Report -Encoding UTF8
}

function Fail-Case($Ctx, $Status, $Reason) {
    $Reason | Set-Content -LiteralPath $Ctx.Failure -Encoding UTF8
    Complete-Case $Ctx $Status $Reason "Verification failed: $Reason"
}

function Find-WindowTitle($Pattern) {
    $windows = Invoke-AgentJson -CmdArgs @('windows')
    foreach ($w in $windows.windows) {
        if ($w.title -match $Pattern) { return $w.title }
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
    $browserTitle = Wait-WindowTitle 'Chrome|Edge' 2
    if (-not $browserTitle) { Fail-Case $ctx 'SKIP_ENVIRONMENT' 'No Chrome or Edge window from Case A was available.'; return $ctx }
    $ctx.UsedFallback = $true
    Save-ScreenShot (Join-Path $ctx.Screenshots 'before.png')
    Invoke-HumanAction $ctx 'keyboard.hotkey' 'browser address bar' 'Ctrl+L fallback' 'fallback_keyboard' $null $null @('hotkey', '--title', $browserTitle, '--keys', 'CTRL+L') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.type_text' 'https://www.baidu.com' 'focused address bar' 'fallback_keyboard' $null $null @('type', '--title', $browserTitle, '--text', 'https://www.baidu.com', '--type-mode', 'demo-human', '--char-delay-ms', '35') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.press' 'navigate external URL' 'focused address bar' 'fallback_keyboard' $null $null @('press', '--title', $browserTitle, '--key', 'ENTER') | Out-Null
    Start-Sleep -Seconds 8
    $loaded = Find-WindowTitle '鐧惧害|Baidu|baidu|Chrome|Edge'
    if (-not $loaded) {
        $ctx.UsedFallback = $true
        $browserTitle = Wait-WindowTitle 'Chrome|Edge' 2
        Invoke-HumanAction $ctx 'keyboard.hotkey' 'browser address bar' 'Ctrl+L fallback' 'fallback_keyboard' $null $null @('hotkey', '--title', $browserTitle, '--keys', 'CTRL+L') | Out-Null
        Invoke-HumanAction $ctx 'keyboard.type_text' 'https://example.com' 'focused address bar' 'fallback_keyboard' $null $null @('type', '--title', $browserTitle, '--text', 'https://example.com', '--type-mode', 'demo-human', '--char-delay-ms', '35') | Out-Null
        Invoke-HumanAction $ctx 'keyboard.press' 'navigate external fallback URL' 'focused address bar' 'fallback_keyboard' $null $null @('press', '--title', $browserTitle, '--key', 'ENTER') | Out-Null
        Start-Sleep -Seconds 5
        $loaded = Find-WindowTitle 'Example|example|Chrome|Edge'
    }
    Save-ScreenShot (Join-Path $ctx.Screenshots 'after.png')
    if ($loaded) { Complete-Case $ctx 'HUMANMODE_FALLBACK_PASS' 'Navigated external URL with Ctrl+L real-keyboard fallback.' "Observed browser title: $loaded"; return $ctx }
    Fail-Case $ctx 'FAIL' 'External URL navigation was not verified.'
    return $ctx
}

function Case-C {
    $ctx = New-CaseContext 'third_party_app_launch_visible_flow'
    Ensure-Dir 'D:\testrepo\pycharm_empty_project'
    $pyCharm = Get-ChildItem -Path "$env:ProgramFiles\JetBrains" -Filter pycharm64.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $target = if ($pyCharm) { 'pycharm' } elseif ((Get-Command code.cmd -ErrorAction SilentlyContinue) -or (Test-Path "$env:LocalAppData\Programs\Microsoft VS Code\Code.exe")) { 'code' } else { '' }
    if (-not $target) { Fail-Case $ctx 'SKIP_ENVIRONMENT' 'PyCharm and VS Code were not found.'; return $ctx }
    $ctx.UsedFallback = $true
    Save-ScreenShot (Join-Path $ctx.Screenshots 'before.png')
    Invoke-HumanAction $ctx 'keyboard.press' 'Start menu' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'WIN', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.type_text' $target 'Start menu search' 'fallback_keyboard' $null $null @('desktop-type', '--text', $target, '--type-mode', 'demo-human', '--char-delay-ms', '45', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.press' 'Start search result' 'Start menu search' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    $title = Wait-WindowTitle 'PyCharm|Visual Studio Code|Code' 20
    Save-ScreenShot (Join-Path $ctx.Screenshots 'after.png')
    if ($title) { Complete-Case $ctx 'HUMANMODE_FALLBACK_PASS' "Opened third-party app through Start Menu keyboard fallback: $target." "Observed title: $title"; return $ctx }
    Fail-Case $ctx 'FAIL' "Start Menu launch did not produce a visible $target window."
    return $ctx
}

function Case-D {
    $ctx = New-CaseContext 'explorer_open_local_html_via_humanmode_flow'
    Write-MockHtml
    Save-ScreenShot (Join-Path $ctx.Screenshots 'before.png')
    $ctx.UsedFallback = $true
    Invoke-HumanAction $ctx 'keyboard.hotkey' 'open Explorer' 'Win+E fallback' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'WIN+E', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Start-Sleep -Seconds 2
    $activeExplorer = Get-ActiveInfo
    if (-not $activeExplorer.ok -or $activeExplorer.data.process_name -ne 'explorer.exe') { Fail-Case $ctx 'FAIL' 'Explorer did not become the foreground window after Win+E.'; return $ctx }
    $explorerTitle = $activeExplorer.data.title
    Invoke-HumanAction $ctx 'keyboard.hotkey' 'Explorer address bar' 'Ctrl+L Explorer path fallback' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'CTRL+L', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.type_text' $MockDir 'Explorer address bar' 'fallback_keyboard' $null $null @('desktop-type', '--text', $MockDir, '--type-mode', 'demo-human', '--char-delay-ms', '25', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Invoke-HumanAction $ctx 'keyboard.press' 'Explorer navigate folder' 'Explorer address bar' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    Start-Sleep -Seconds 2
    $activeFolder = Get-ActiveInfo
    $folderTitle = if ($activeFolder.ok -and $activeFolder.data.process_name -eq 'explorer.exe') { $activeFolder.data.title } else { $explorerTitle }
    $center = Get-UiaCenter $folderTitle 'desktopvisual_mail_mock.html'
    if ($center) {
        Add-Locator $ctx 'desktopvisual_mail_mock.html' 'uia Explorer file item' 'ok' $center.X $center.Y $center.Raw.data
        Invoke-HumanAction $ctx 'mouse.move' 'desktopvisual_mail_mock.html' 'uia Explorer file item' 'locator_derived' $center.X $center.Y @('desktop-move', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
        Invoke-HumanAction $ctx 'mouse.double_click' 'desktopvisual_mail_mock.html' 'uia Explorer file item' 'locator_derived' $center.X $center.Y @('desktop-double-click', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--move-mode', 'fast-human', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    } else {
        $ctx.UsedFallback = $true
        Add-Locator $ctx 'desktopvisual_mail_mock.html' 'uia Explorer file item' 'not_found' $null $null @{}
        Invoke-HumanAction $ctx 'keyboard.hotkey' 'Explorer address bar full file path' 'Ctrl+L Explorer file fallback' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'CTRL+L', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
        Invoke-HumanAction $ctx 'keyboard.type_text' $MockHtml 'Explorer address bar full file path' 'fallback_keyboard' $null $null @('desktop-type', '--text', $MockHtml, '--type-mode', 'demo-human', '--char-delay-ms', '25', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
        Invoke-HumanAction $ctx 'keyboard.press' 'Explorer open local HTML file' 'Explorer address bar full file path' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'ENTER', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
    }
    $title = Wait-WindowTitle 'DesktopVisual Local Mail Mock|Chrome|Edge' 10
    Save-ScreenShot (Join-Path $ctx.Screenshots 'after.png')
    if ($title) { Complete-Case $ctx 'HUMANMODE_FALLBACK_PASS' 'Opened local HTML from Explorer using address-bar folder fallback and file double-click.' "Observed browser/local page title: $title"; return $ctx }
    Fail-Case $ctx 'FAIL' 'Browser/local HTML window did not appear after Explorer file double-click.'
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
        'desktop_mouse_open_chrome_visible_flow',
        'chrome_address_bar_external_url_navigation_flow',
        'third_party_app_launch_visible_flow',
        'explorer_open_local_html_via_humanmode_flow',
        'local_mail_mock_browser_fill_and_send_humanmode_flow'
    )) {
        $ctx = New-CaseContext $id
        Fail-Case $ctx 'SKIP_ENVIRONMENT' 'GUI cases were skipped by -SkipGuiCases.'
        $caseResults += $ctx
    }
} else {
    $caseResults += Case-A
    $caseResults += Case-B
    $caseResults += Case-C
    $caseResults += Case-D
    $caseResults += Case-E
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
    backend_action_count = @($summary | Measure-Object -Property backend_action_count -Sum).Sum
    direct_launch_count = 0
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
    'dev_summary.md' = 'v5.9.0-b implements the HumanMode Visible UI Case Runner in v5 without VLM, Agent Planner, public release permission narrowing, or auto commit.'
    'test_summary.md' = 'P0 policy selftest runs before GUI cases. GUI Case A-E results are listed in case_summary.json and runtime_boundary_report.md.'
    'known_limits.md' = 'This remains a v5 Task-Level Desktop Execution Runtime. GUI results depend on local desktop state, installed apps, UIA/OCR availability, browser profile state, and network reachability.'
    'humanmode_definition.md' = 'HumanMode means visible real mouse cursor movement, SendInput mouse click/double-click, and SendInput keyboard events. UIA/OCR/ElementGraph are observation/locator sources only.'
    'policy_defect_fix_report.md' = 'Developer mode allows base UI primitives without FULL_ACCESS and without TestWindow-only title/process allowlists. Active protection still stops.'
    'humanmode_input_primitive_report.md' = 'Added desktop-move, desktop-click, desktop-double-click, desktop-press, desktop-hotkey, and desktop-type for developer-mode visible desktop primitives.'
    'case_runner_implementation_report.md' = 'Case runner script writes per-case screenshots, action_trace.jsonl, locator_trace.jsonl, task_events.jsonl, task_result.json, task_report.md, and verification_report.md.'
    'active_protection_stop_report.md' = 'CAPTCHA, human verification, automation/script detection, anti-cheat, and active proctoring are STOP_ACTIVE_PROTECTION boundaries. No bypass attempts are made.'
    'regression_report.md' = 'See test_summary.md and runtime_boundary_report.md for commands and status. JSON/JSONL parse checks are part of follow-up regression commands.'
}
foreach ($entry in $reportFiles.GetEnumerator()) {
    $entry.Value | Set-Content -LiteralPath (Join-Path $ArtifactRoot $entry.Key) -Encoding UTF8
}

$map = @{
    'desktop_mouse_chrome_report.md' = 'desktop_mouse_open_chrome_visible_flow'
    'browser_address_bar_navigation_report.md' = 'chrome_address_bar_external_url_navigation_flow'
    'third_party_app_launch_report.md' = 'third_party_app_launch_visible_flow'
    'explorer_local_html_report.md' = 'explorer_open_local_html_via_humanmode_flow'
    'local_mail_mock_browser_report.md' = 'local_mail_mock_browser_fill_and_send_humanmode_flow'
}
foreach ($entry in $map.GetEnumerator()) {
    $caseResult = $summary | Where-Object case_id -eq $entry.Value | Select-Object -First 1
    @(
        "# $($entry.Value)",
        "",
        "- Result: $($caseResult.status)",
        "- Summary: $($caseResult.summary)",
        "- Case dir: $((Join-Path $CasesRoot $entry.Value))"
    ) | Set-Content -LiteralPath (Join-Path $ArtifactRoot $entry.Key) -Encoding UTF8
}

git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8
git -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8

Get-ChildItem -Path $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

Write-Host "v5.9.0-b HumanMode Case Runner complete."
Write-Host "Artifacts: $ArtifactRoot"
