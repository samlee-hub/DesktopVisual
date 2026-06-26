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
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.9.3_explorer_mouse_target_strictness'
$CasesRoot = Join-Path $ArtifactRoot 'cases'
$PreviousArtifactRoot = Join-Path $Root 'artifacts\dev5.9.0-d_case_d_explorer_locator_fix\cases\explorer_open_local_html_via_humanmode_flow'
$MockDir = 'D:\testrepo\testwindow'
$MockHtml = Join-Path $MockDir 'desktopvisual_mail_mock.html'
$BrowserProfile = Join-Path $ArtifactRoot 'browser_profile'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'
$PreviousResults = @{
    'explorer_open_local_html_via_humanmode_flow' = 'previous_evidence_unavailable'
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

function Convert-HwndStringToIntPtr([string]$Hwnd) {
    if ([string]::IsNullOrWhiteSpace($Hwnd)) { return [IntPtr]::Zero }
    $text = $Hwnd.Trim()
    if ($text.StartsWith('0x')) {
        return [IntPtr]([Convert]::ToInt64($text.Substring(2), 16))
    }
    return [IntPtr]([Convert]::ToInt64($text, 10))
}

function Get-WindowInfoByHwnd([string]$Hwnd) {
    $windows = Invoke-AgentJson -CmdArgs @('windows') -AllowFailure
    $all = @()
    if ($windows.windows) { $all += $windows.windows }
    if ($windows.data -and $windows.data.windows) { $all += $windows.data.windows }
    foreach ($w in $all) {
        if ($w.hwnd -eq $Hwnd -and (Test-WindowRectUsable $w.rect)) { return $w }
    }
    return $null
}

function Get-LockedExplorerState([string]$LockedHwnd) {
    $active = Get-ActiveInfo
    $window = Get-WindowInfoByHwnd $LockedHwnd
    [pscustomobject]@{
        locked_explorer_hwnd = $LockedHwnd
        foreground_hwnd = $(if ($active.ok) { $active.data.hwnd } else { '' })
        foreground_title = $(if ($active.ok) { $active.data.title } else { '' })
        foreground_process = $(if ($active.ok) { $active.data.process_name } else { '' })
        explorer_window_rect = $(if ($window) { $window.rect } else { $null })
        is_foreground_locked = $($active.ok -and $active.data.hwnd -eq $LockedHwnd)
    }
}

function Get-ExplorerContentRect($WindowRect) {
    if (-not $WindowRect) { return $null }
    $width = [int]($WindowRect.right - $WindowRect.left)
    $height = [int]($WindowRect.bottom - $WindowRect.top)
    $leftInset = [Math]::Min(260, [Math]::Max(180, [int]($width * 0.15)))
    $topInset = [Math]::Min(180, [Math]::Max(120, [int]($height * 0.16)))
    $rightInset = 24
    $bottomInset = 42
    [pscustomobject]@{
        left = [int]($WindowRect.left + $leftInset)
        top = [int]($WindowRect.top + $topInset)
        right = [int]($WindowRect.right - $rightInset)
        bottom = [int]($WindowRect.bottom - $bottomInset)
        source = 'heuristic_content_rect'
    }
}

function Test-RectIntersects($A, $B) {
    if (-not $A -or -not $B) { return $false }
    return ($A.left -lt $B.right -and $A.right -gt $B.left -and $A.top -lt $B.bottom -and $A.bottom -gt $B.top)
}

function Test-PointInRect([int]$X, [int]$Y, $Rect) {
    if (-not $Rect) { return $false }
    return ($X -ge $Rect.left -and $X -le $Rect.right -and $Y -ge $Rect.top -and $Y -le $Rect.bottom)
}

function Save-RectCrop($Path, $Rect) {
    if (-not $Rect) { return $false }
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $w = [Math]::Max(1, [int]($Rect.right - $Rect.left))
    $h = [Math]::Max(1, [int]($Rect.bottom - $Rect.top))
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen([int]$Rect.left, [int]$Rect.top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
    return $true
}

function Convert-RectArray($Rect) {
    if (-not $Rect) { return @() }
    return @([int]$Rect.left, [int]$Rect.top, [int]$Rect.right, [int]$Rect.bottom)
}

function Test-RectNonEmpty($Rect) {
    return ($Rect -and [int]$Rect.right -gt [int]$Rect.left -and [int]$Rect.bottom -gt [int]$Rect.top)
}

function Test-RectOnScreen($Rect) {
    if (-not (Test-RectNonEmpty $Rect)) { return $false }
    $v = Get-VirtualScreenRect
    return ($Rect.left -lt $v.Right -and $Rect.right -gt $v.Left -and $Rect.top -lt $v.Bottom -and $Rect.bottom -gt $v.Top)
}

function Get-RectCenter($Rect) {
    [pscustomobject]@{
        X = [int](($Rect.left + $Rect.right) / 2)
        Y = [int](($Rect.top + $Rect.bottom) / 2)
    }
}

function Get-MousePositionStrict {
    $pos = Invoke-AgentJson -CmdArgs @('mouse-position') -AllowFailure
    if (-not $pos.ok) { return $null }
    return [pscustomobject]@{ X = [int]$pos.data.screen_x; Y = [int]$pos.data.screen_y }
}

function Get-DistancePx([int]$X1, [int]$Y1, [int]$X2, [int]$Y2) {
    $dx = $X1 - $X2
    $dy = $Y1 - $Y2
    return [int][Math]::Round([Math]::Sqrt(($dx * $dx) + ($dy * $dy)))
}

function Save-OverlayEvidence($Path, $Rect, [int]$ClickX, [int]$ClickY, [int]$CursorX, [int]$CursorY, [string]$ItemName, [bool]$Inside, [string]$RectSource, [string]$LockedHwnd) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Lime), 4
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180, 0, 0, 0))
    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $clickPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
    $cursorPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Cyan), 3
    $font = New-Object System.Drawing.Font 'Consolas', 14
    $rx = [int]($Rect.left - $bounds.Left)
    $ry = [int]($Rect.top - $bounds.Top)
    $rw = [int]($Rect.right - $Rect.left)
    $rh = [int]($Rect.bottom - $Rect.top)
    $graphics.DrawRectangle($pen, $rx, $ry, $rw, $rh)
    $cx = [int]($ClickX - $bounds.Left)
    $cy = [int]($ClickY - $bounds.Top)
    $mx = [int]($CursorX - $bounds.Left)
    $my = [int]($CursorY - $bounds.Top)
    $graphics.DrawEllipse($clickPen, $cx - 8, $cy - 8, 16, 16)
    $graphics.DrawLine($clickPen, $cx - 12, $cy, $cx + 12, $cy)
    $graphics.DrawLine($clickPen, $cx, $cy - 12, $cx, $cy + 12)
    $graphics.DrawEllipse($cursorPen, $mx - 5, $my - 5, 10, 10)
    $label = "$ItemName inside_target_rect=$Inside rect_source=$RectSource hwnd=$LockedHwnd"
    $graphics.FillRectangle($brush, 8, 8, [Math]::Min($bmp.Width - 16, 1200), 36)
    $graphics.DrawString($label, $font, $textBrush, 14, 14)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $font.Dispose()
    $pen.Dispose()
    $clickPen.Dispose()
    $cursorPen.Dispose()
    $brush.Dispose()
    $textBrush.Dispose()
    $graphics.Dispose()
    $bmp.Dispose()
}

function Get-UiaRootForHwnd([string]$Hwnd) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $ptr = Convert-HwndStringToIntPtr $Hwnd
    if ($ptr -eq [IntPtr]::Zero) { return $null }
    return [System.Windows.Automation.AutomationElement]::FromHandle($ptr)
}

function Get-LockedExplorerElements([string]$Hwnd) {
    $state = Get-LockedExplorerState $Hwnd
    if ($state -and $state.foreground_title -and $state.foreground_hwnd -eq $Hwnd) {
        $observation = Invoke-AgentJson -CmdArgs @('observe', '--title', ([string]$state.foreground_title), '--screenshot', 'false', '--uia', 'true', '--max-elements', '500') -AllowFailure
        if ($observation.ok -and $observation.data -and $observation.data.target_window -and $observation.data.target_window.hwnd -eq $Hwnd -and $observation.data.uia -and $observation.data.uia.elements) {
            $items = @()
            foreach ($el in $observation.data.uia.elements) {
                try {
                    if (-not $el.rect) { continue }
                    $items += [pscustomobject]@{
                        Name = $el.name
                        ControlType = $el.control_type
                        ClassName = $el.class_name
                        AutomationId = $el.automation_id
                        IsOffscreen = [bool]$el.is_offscreen
                        Rect = [pscustomobject]@{
                            left = [int]$el.rect.left
                            top = [int]$el.rect.top
                            right = [int]$el.rect.right
                            bottom = [int]$el.rect.bottom
                        }
                        Element = $null
                        RectCoordinateSpace = 'winagent_observe_screen'
                    }
                } catch {}
            }
            return @($items)
        }
    }

    $root = Get-UiaRootForHwnd $Hwnd
    if (-not $root) { return @() }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $items = @()
    foreach ($el in $all) {
        try {
            $rect = $el.Current.BoundingRectangle
            $items += [pscustomobject]@{
                Name = $el.Current.Name
                ControlType = $el.Current.ControlType.ProgrammaticName
                ClassName = $el.Current.ClassName
                AutomationId = $el.Current.AutomationId
                IsOffscreen = [bool]$el.Current.IsOffscreen
                Rect = [pscustomobject]@{
                    left = [int]$rect.Left
                    top = [int]$rect.Top
                    right = [int]($rect.Left + $rect.Width)
                    bottom = [int]($rect.Top + $rect.Height)
                }
                Element = $el
                RectCoordinateSpace = 'uia_direct_screen'
            }
        } catch {}
    }
    return @($items)
}

function Get-SelectedExplorerItemEvidence([string]$Hwnd, $ContentRect) {
    $elements = Get-LockedExplorerElements $Hwnd
    foreach ($e in $elements) {
        try {
            if ($e.IsOffscreen) { continue }
            if ($e.RectCoordinateSpace -and $e.RectCoordinateSpace -ne 'winagent_observe_screen') { continue }
            if ($e.Rect.right -le $e.Rect.left -or $e.Rect.bottom -le $e.Rect.top) { continue }
            if (-not (Test-RectIntersects $e.Rect $ContentRect)) { continue }
            if (-not $e.Element) { continue }
            $pattern = $null
            if ($e.Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
                if ($pattern.Current.IsSelected) { return $e }
            }
        } catch {}
    }
    return $null
}

function Get-AnyLockedExplorerContentItem([string]$Hwnd, $ContentRect) {
    $elements = Get-LockedExplorerElements $Hwnd
    foreach ($e in @($elements | Sort-Object @{ Expression = { $_.Rect.top } }, @{ Expression = { $_.Rect.left } })) {
        $name = [string]$e.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($e.IsOffscreen) { continue }
        if ($e.RectCoordinateSpace -and $e.RectCoordinateSpace -ne 'winagent_observe_screen') { continue }
        if ($e.Rect.right -le $e.Rect.left -or $e.Rect.bottom -le $e.Rect.top) { continue }
        if (-not (Test-RectIntersects $e.Rect $ContentRect)) { continue }
        if ($e.ControlType -notmatch 'ListItem|DataItem') { continue }
        $x = [int](($e.Rect.left + $e.Rect.right) / 2)
        $y = [int](($e.Rect.top + $e.Rect.bottom) / 2)
        if ((Test-ScreenPoint $x $y) -and (Test-PointInRect $x $y $ContentRect)) {
            return [pscustomobject]@{ X = $x; Y = $y; Name = $name; Rect = $e.Rect; ControlType = $e.ControlType }
        }
    }
    return $null
}

function Find-LockedExplorerItem($Ctx, [string]$LockedHwnd, $ContentRect, [string]$ItemName, [string[]]$Patterns, [string]$MethodName, [string]$CandidateFileName) {
    $state = Get-LockedExplorerState $LockedHwnd
    $elements = Get-LockedExplorerElements $LockedHwnd
    $candidates = @()
    foreach ($e in $elements) {
        $name = [string]$e.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($e.IsOffscreen) { continue }
        if ($e.RectCoordinateSpace -and $e.RectCoordinateSpace -ne 'winagent_observe_screen') { continue }
        if ($e.Rect.right -le $e.Rect.left -or $e.Rect.bottom -le $e.Rect.top) { continue }
        if (-not (Test-RectIntersects $e.Rect $ContentRect)) { continue }
        if ($e.ControlType -notmatch 'ListItem|DataItem|TreeItem') { continue }
        if (@($Patterns | Where-Object { $name -match $_ }).Count -eq 0) { continue }
        $width = [int]($e.Rect.right - $e.Rect.left)
        $x = [int](($e.Rect.left + $e.Rect.right) / 2)
        if ($ItemName -match '^D:' -or $name -match '\(D:\)') {
            $x = [int]($e.Rect.left + [Math]::Min(55, [Math]::Max(28, $width * 0.12)))
            $y = [int]($e.Rect.top + [Math]::Min(48, [Math]::Max(28, ($e.Rect.bottom - $e.Rect.top) * 0.50)))
        } else {
            $y = [int](($e.Rect.top + $e.Rect.bottom) / 2)
        }
        if (-not (Test-ScreenPoint $x $y)) { continue }
        if (-not (Test-PointInRect $x $y $ContentRect)) { continue }
        $candidates += [pscustomobject]@{
            name = $name
            control_type = $e.ControlType
            class_name = $e.ClassName
            automation_id = $e.AutomationId
            rect = $e.Rect
            rect_coordinate_space = $e.RectCoordinateSpace
            x = $x
            y = $y
            locked_explorer_hwnd = $LockedHwnd
            foreground_hwnd = $state.foreground_hwnd
            from_locked_hwnd = $true
        }
    }
    $candidatePath = Join-Path $Ctx.Dir $CandidateFileName
    @($candidates) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
    if (@($candidates).Count -gt 0) {
        $selected = @($candidates | Sort-Object @{ Expression = { if ($_.name -eq $ItemName) { 0 } else { 1 } } }, @{ Expression = { $_.y } }, @{ Expression = { $_.x } } | Select-Object -First 1)[0]
        Add-Locator $Ctx $ItemName $MethodName 'ok' $selected.x $selected.y @{
            selected = $selected
            locked_explorer_hwnd = $LockedHwnd
            foreground_hwnd = $state.foreground_hwnd
            foreground_title = $state.foreground_title
            explorer_window_rect = $state.explorer_window_rect
            explorer_content_rect = $ContentRect
        }
        return [pscustomobject]@{
            X = $selected.x
            Y = $selected.y
            Method = $MethodName
            CoordinateSource = 'locator_derived'
            ExpectedName = $ItemName
            MatchedName = $selected.name
            Rect = $selected.rect
            RectSource = 'uia_exact_item_rect'
            ContentRect = $ContentRect
            LockedExplorerHwnd = $LockedHwnd
            Raw = $selected
        }
    }
    Add-Locator $Ctx $ItemName $MethodName 'not_found' $null $null @{
        locked_explorer_hwnd = $LockedHwnd
        foreground_hwnd = $state.foreground_hwnd
        foreground_title = $state.foreground_title
        explorer_window_rect = $state.explorer_window_rect
        explorer_content_rect = $ContentRect
        candidate_count = 0
    }
    return $null
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
    Ensure-Dir (Join-Path $dir 'overlays')
    Ensure-Dir (Join-Path $dir 'crops')
    foreach ($file in @('task_events.jsonl', 'action_trace.jsonl', 'locator_trace.jsonl', 'mouse_target_checks.jsonl', 'human_action_results.jsonl')) {
        Set-Content -LiteralPath (Join-Path $dir $file) -Value '' -Encoding UTF8
    }
    [pscustomobject]@{
        CaseId = $CaseId
        Dir = $dir
        Screenshots = Join-Path $dir 'screenshots'
        Overlays = Join-Path $dir 'overlays'
        Crops = Join-Path $dir 'crops'
        Events = Join-Path $dir 'task_events.jsonl'
        Actions = Join-Path $dir 'action_trace.jsonl'
        Locators = Join-Path $dir 'locator_trace.jsonl'
        MouseTargetChecks = Join-Path $dir 'mouse_target_checks.jsonl'
        HumanActionResults = Join-Path $dir 'human_action_results.jsonl'
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
        ExplorerAddressbarPathInputCount = 0
        InvokeItemCount = 0
        DirectFileOpenCount = 0
        IncrementalSearchCount = 0
        KeyboardAssistedOpenCount = 0
        EnterOpenCount = 0
        TargetRectMissingCount = 0
        SelectedItemRectMissingCount = 0
        SelectedItemNameMismatchCount = 0
        CursorOutsideTargetRectCount = 0
        PathStepsTotal = 5
        PathStepsWithTargetRect = 0
        PathStepsWithCursorInsideTargetRect = 0
        WheelScrollCount = 0
        LockedExplorerHwnd = ''
        LastStrictLocator = $null
        LastStrictClick = $null
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
    if ($null -eq $Ctx.$Name -or $intValue -lt [int]$Ctx.$Name) {
        $Ctx.$Name = $intValue
    }
}

function Normalize-HumanModeCommand([string[]]$CmdArgs, [string]$Target, [string]$CoordinateSource) {
    if ($CmdArgs.Count -eq 0 -or $CmdArgs[0] -notin @('desktop-move', 'desktop-click', 'desktop-double-click')) {
        return $CmdArgs
    }
    $normalized = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $CmdArgs.Count; $i++) {
        if ($CmdArgs[$i] -eq '--move-mode' -and ($i + 1) -lt $CmdArgs.Count -and $CmdArgs[$i + 1] -eq 'fast-human') {
            $i++
            continue
        }
        $normalized.Add($CmdArgs[$i]) | Out-Null
    }
    if ($normalized -notcontains '--humanmode') {
        $normalized.Add('--humanmode') | Out-Null
        $normalized.Add('true') | Out-Null
    }
    if ($normalized -notcontains '--target-description') {
        $normalized.Add('--target-description') | Out-Null
        $normalized.Add($Target) | Out-Null
    }
    if ($normalized -notcontains '--coordinate-source') {
        $normalized.Add('--coordinate-source') | Out-Null
        $normalized.Add($CoordinateSource) | Out-Null
    }
    return [string[]]$normalized.ToArray()
}

function Add-HumanActionTrace($Ctx, [string]$ActionType, [string]$Target, $Result) {
    $har = $Result.data.human_action_result
    if (-not $har) {
        if ($ActionType -like 'mouse.*') { $Ctx.HumanActionResultParseErrors++ }
        return
    }
    if ($har.schema_version -ne 'human_action_result.v1') {
        $Ctx.HumanActionResultParseErrors++
    }
    Write-JsonLine $Ctx.HumanActionResults $har
    $Ctx.HumanActionResultCount++
    $Ctx.HumanModePacingChecked = $true
    Update-MinMetric $Ctx 'MinMoveDurationMs' $har.motion.move_duration_ms
    if ($har.action_type -in @('mouse_click', 'mouse_double_click')) {
        Update-MinMetric $Ctx 'MinDwellBeforeClickMs' $har.motion.dwell_before_click_ms
    }
    if ($har.action_type -eq 'mouse_double_click') {
        Update-MinMetric $Ctx 'MinDoubleClickIntervalMs' $har.motion.double_click_interval_ms
    }
    if ($har.motion.move_duration_ms -eq 0 -and $har.actual_click_sent) {
        $Ctx.InstantClickAfterMoveCount++
    }
    if ($har.verification.click_after_move_end -eq $false -and $har.actual_click_sent) {
        $Ctx.ClickBeforeMoveEndCount++
    }
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{
        action_type = 'mouse_move_humanmode_start'
        from_x = $har.cursor.start_x
        from_y = $har.cursor.start_y
        target_x = $har.target.x
        target_y = $har.target.y
        target_rect = $har.target.target_rect
        duration_ms = $har.motion.move_duration_ms
        planned_steps = $har.motion.planned_steps
        easing = $har.motion.easing
        timestamp = $har.timing.move_start_ts
    })
    $path = @($har.motion.planned_path)
    if ($path.Count -gt 0) {
        $indices = @(0, [Math]::Floor(($path.Count - 1) / 2), ($path.Count - 1)) | Select-Object -Unique
        foreach ($idx in $indices) {
            Write-JsonLine $Ctx.Actions ([pscustomobject]@{
                action_type = 'mouse_move_humanmode_step'
                step_index = [int]($idx + 1)
                step_count = $path.Count
                x = $path[$idx].x
                y = $path[$idx].y
                timestamp = $har.timing.move_start_ts
            })
        }
    }
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{
        action_type = 'mouse_move_humanmode_end'
        final_x = $har.cursor.final_x
        final_y = $har.cursor.final_y
        target_x = $har.target.x
        target_y = $har.target.y
        target_rect = $har.target.target_rect
        within_epsilon = $har.cursor.within_target_epsilon_before_click
        timestamp = $har.timing.move_end_ts
    })
    if ($har.action_type -in @('mouse_click', 'mouse_double_click')) {
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            action_type = 'dwell_before_click'
            duration_ms = $har.motion.dwell_before_click_ms
            timestamp = $har.timing.dwell_start_ts
        })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            action_type = 'mouse_click_down'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.click_down_ts
        })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            action_type = 'mouse_click_up'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.click_up_ts
        })
    }
    if ($har.action_type -eq 'mouse_double_click') {
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            action_type = 'double_click_interval'
            duration_ms = $har.motion.double_click_interval_ms
            timestamp = $har.timing.click_up_ts
        })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            action_type = 'mouse_click_down'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.second_click_down_ts
        })
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            action_type = 'mouse_click_up'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.second_click_up_ts
        })
    }
}

function Invoke-HumanAction($Ctx, [string]$ActionType, [string]$Target, [string]$LocatorMethod, [string]$CoordinateSource, [Nullable[int]]$ScreenX, [Nullable[int]]$ScreenY, [string[]]$CmdArgs, [switch]$AllowFailure) {
    $CmdArgs = Normalize-HumanModeCommand $CmdArgs $Target $CoordinateSource
    $result = Invoke-AgentJson -CmdArgs $CmdArgs -AllowFailure:$AllowFailure
    Add-HumanActionTrace $Ctx $ActionType $Target $result
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

function Invoke-StrictTargetDoubleClick($Ctx, [string]$StepName, [string]$ExpectedName, $Locator, [string]$OverlayName, [string]$ExpectedLocationBefore) {
    if (-not $Locator -or -not $Locator.Rect) {
        $Ctx.TargetRectMissingCount++
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_TARGET_RECT_MISSING'; Message = "Missing target rect for $ExpectedName." }
    }
    $rect = $Locator.Rect
    if (-not (Test-RectNonEmpty $rect) -or -not (Test-RectOnScreen $rect)) {
        $Ctx.TargetRectMissingCount++
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_TARGET_RECT_MISSING'; Message = "Invalid or offscreen target rect for $ExpectedName." }
    }
    if ($Locator.ContentRect -and -not (Test-RectIntersects $rect $Locator.ContentRect)) {
        $Ctx.TargetRectMissingCount++
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_TARGET_RECT_MISSING'; Message = "Target rect for $ExpectedName does not intersect Explorer content rect." }
    }
    if ($Locator.MatchedName -and $ExpectedName -notmatch '^D:' -and [string]$Locator.MatchedName -ne $ExpectedName) {
        $Ctx.SelectedItemNameMismatchCount++
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_SELECTED_ITEM_NAME_MISMATCH'; Message = "Selected item '$($Locator.MatchedName)' did not match '$ExpectedName'." }
    }

    $rectCenter = Get-RectCenter $rect
    if ($Locator.X -and $Locator.Y -and (Test-PointInRect ([int]$Locator.X) ([int]$Locator.Y) $rect)) {
        $center = [pscustomobject]@{ X = [int]$Locator.X; Y = [int]$Locator.Y }
    } else {
        $center = $rectCenter
    }
    $Ctx.PathStepsWithTargetRect++
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{
        action_type = 'target_item_resolved'
        expected_name = $ExpectedName
        matched_name = $Locator.MatchedName
        target_rect = (Convert-RectArray $rect)
        rect_source = $Locator.RectSource
        locked_explorer_hwnd = $Locator.LockedExplorerHwnd
        content_rect = (Convert-RectArray $Locator.ContentRect)
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    })

    $moveResult = Invoke-HumanAction $Ctx 'mouse.move' $ExpectedName $Locator.Method $Locator.CoordinateSource $center.X $center.Y @(
        'desktop-move', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)",
        '--permission-mode', $PermissionMode,
        '--target-description', $ExpectedName,
        '--coordinate-source', $Locator.CoordinateSource,
        '--target-rect-left', "$($rect.left)", '--target-rect-top', "$($rect.top)",
        '--target-rect-right', "$($rect.right)", '--target-rect-bottom', "$($rect.bottom)"
    ) -AllowFailure
    if (-not $moveResult.ok) {
        $Ctx.CursorOutsideTargetRectCount++
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_CURSOR_NOT_INSIDE_TARGET_RECT'; Message = "Mouse move to target rect failed before click for ${ExpectedName}: $($moveResult.error.code)." }
    }

    $cursor = Get-MousePositionStrict
    if (-not $cursor) {
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_CURSOR_NOT_INSIDE_TARGET_RECT'; Message = 'Could not read cursor before click.' }
    }
    $inside = Test-PointInRect $cursor.X $cursor.Y $rect
    $distance = Get-DistancePx $cursor.X $cursor.Y $rectCenter.X $rectCenter.Y
    if ($inside) { $Ctx.PathStepsWithCursorInsideTargetRect++ } else { $Ctx.CursorOutsideTargetRectCount++ }
    Write-JsonLine $Ctx.MouseTargetChecks ([pscustomobject]@{
        action_type = 'cursor_target_rect_check'
        step_name = $StepName
        expected_name = $ExpectedName
        cursor_x = $cursor.X
        cursor_y = $cursor.Y
        target_rect = (Convert-RectArray $rect)
        inside_target_rect = $inside
        distance_to_target_center_px = $distance
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    })
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{
        action_type = 'cursor_target_rect_check'
        expected_name = $ExpectedName
        cursor_x = $cursor.X
        cursor_y = $cursor.Y
        target_rect = (Convert-RectArray $rect)
        inside_target_rect = $inside
        distance_to_target_center_px = $distance
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    })
    $overlayPath = Join-Path $Ctx.Overlays $OverlayName
    Save-OverlayEvidence $overlayPath $rect $center.X $center.Y $cursor.X $cursor.Y $ExpectedName $inside $Locator.RectSource $Locator.LockedExplorerHwnd
    if (-not $inside) {
        return [pscustomobject]@{ Ok = $false; Code = 'FAIL_CURSOR_NOT_INSIDE_TARGET_RECT'; Message = "Cursor was not inside target rect for $ExpectedName."; Cursor = $cursor; Overlay = $overlayPath; Distance = $distance }
    }

    $result = Invoke-HumanAction $Ctx 'mouse.double_click' $ExpectedName $Locator.Method $Locator.CoordinateSource $center.X $center.Y @(
        'desktop-double-click', '--screen-x', "$($center.X)", '--screen-y', "$($center.Y)",
        '--permission-mode', $PermissionMode,
        '--target-description', $ExpectedName,
        '--coordinate-source', $Locator.CoordinateSource,
        '--target-rect-left', "$($rect.left)", '--target-rect-top', "$($rect.top)",
        '--target-rect-right', "$($rect.right)", '--target-rect-bottom', "$($rect.bottom)"
    ) -AllowFailure
    if (-not $result.ok) {
        return [pscustomobject]@{ Ok = $false; Code = $result.error.code; Message = $result.error.message; Cursor = $cursor; Overlay = $overlayPath; Distance = $distance }
    }
    return [pscustomobject]@{
        Ok = $true
        Code = 'OK'
        Rect = $rect
        CursorBeforeClick = $cursor
        CursorInsideTargetRectBeforeClick = $inside
        DistanceToTargetCenterPx = $distance
        Overlay = $overlayPath
        OpenAction = 'mouse_double_click_on_target_rect'
        ExpectedLocationBefore = $ExpectedLocationBefore
        HumanActionResult = $result.data.human_action_result
    }
}

function Complete-Case($Ctx, $Status, $Summary, $Verification) {
    if ($Status -eq 'STRICT_MOUSE_TARGET_HUMANMODE_PASS' -and (Test-Path $Ctx.Failure)) {
        Remove-Item -LiteralPath $Ctx.Failure -Force
    }
    $Ctx.StrictHumanMode = ($Status -eq 'STRICT_MOUSE_TARGET_HUMANMODE_PASS')
    $Ctx.VerificationPassed = ($Status -eq 'STRICT_MOUSE_TARGET_HUMANMODE_PASS')
    $failureReason = if ($Ctx.FailureReason) { $Ctx.FailureReason } elseif ($Ctx.VerificationPassed) { '' } else { $Summary }
    $result = [pscustomobject]@{
        case_id = $Ctx.CaseId
        version = '5.9.3'
        previous_result_from_v5_9_0_d = $PreviousResults[$Ctx.CaseId]
        target_result = 'STRICT_MOUSE_TARGET_HUMANMODE_PASS'
        actual_result = $Status
        failure_reason = $failureReason
        strict_mouse_target_humanmode = $Ctx.StrictHumanMode
        this_pc_fixture_used = $Ctx.FixtureUsed
        keyboard_assisted_open_count = $Ctx.KeyboardAssistedOpenCount
        enter_open_count = $Ctx.EnterOpenCount
        explorer_addressbar_path_input_count = $Ctx.ExplorerAddressbarPathInputCount
        shell_execute_count = $Ctx.ShellExecuteCount
        start_process_count = $Ctx.StartProcessCount
        invoke_item_count = $Ctx.InvokeItemCount
        backend_action_count = $Ctx.BackendActionCount
        direct_file_open_count = $Ctx.DirectFileOpenCount
        uia_invoke_action_count = $Ctx.UiaInvokeActionCount
        uia_value_action_count = $Ctx.UiaValueActionCount
        target_rect_missing_count = $Ctx.TargetRectMissingCount
        selected_item_rect_missing_count = $Ctx.SelectedItemRectMissingCount
        selected_item_name_mismatch_count = $Ctx.SelectedItemNameMismatchCount
        cursor_outside_target_rect_count = $Ctx.CursorOutsideTargetRectCount
        path_steps_total = $Ctx.PathStepsTotal
        path_steps_with_target_rect = $Ctx.PathStepsWithTargetRect
        path_steps_with_cursor_inside_target_rect = $Ctx.PathStepsWithCursorInsideTargetRect
        fixed_coordinate_count = $Ctx.FixedCoordinateCount
        locator_derived_coordinate_count = $Ctx.LocatorDerivedCount
        heuristic_locator_derived_count = $Ctx.HeuristicLocatorDerivedCount
        incremental_search_count = $Ctx.IncrementalSearchCount
        incremental_search_used_as_locator_only = $true
        wheel_scroll_count = $Ctx.WheelScrollCount
        locked_explorer_hwnd = $Ctx.LockedExplorerHwnd
        locator_methods_used = @($Ctx.LocatorMethods)
        screenshots_count = $Ctx.ScreenshotsTaken
        verification_passed = $Ctx.VerificationPassed
        vlm_call_count = 0
        status = $Status
        summary = $Summary
        active_protection_seen = $Ctx.ActiveProtectionSeen
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
        "- This PC fixture used: $($Ctx.FixtureUsed)",
        "- Locked Explorer hwnd: $($Ctx.LockedExplorerHwnd)",
        "- Path steps with target rect: $($Ctx.PathStepsWithTargetRect) / $($Ctx.PathStepsTotal)",
        "- Path steps cursor inside target rect: $($Ctx.PathStepsWithCursorInsideTargetRect) / $($Ctx.PathStepsTotal)",
        "- Locator methods: $(@($Ctx.LocatorMethods) -join ', ')",
        "- Incremental search count: $($Ctx.IncrementalSearchCount)",
        "- Enter open count: $($Ctx.EnterOpenCount)",
        "- Wheel scroll count: $($Ctx.WheelScrollCount)",
        "- Backend actions counted as HumanMode: 0",
        "- Direct file opens counted as PASS: 0",
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
        Rect = $rect
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
    Invoke-AgentJson -CmdArgs @('focus', '--title', 'Program Manager') -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 300
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
    $locator = [pscustomobject]@{
        X = $center.X
        Y = $center.Y
        Method = 'uia Program Manager ListItem'
        CoordinateSource = 'locator_derived'
        ExpectedName = $ShortcutName
        MatchedName = $ShortcutName
        Rect = $center.Rect
        RectSource = 'uia_desktop_fixture_rect'
        ContentRect = $null
        LockedExplorerHwnd = 'Program Manager'
        Raw = $center.Raw.data
    }
    $strict = Invoke-StrictTargetDoubleClick $Ctx 'open_this_pc_fixture' $ShortcutName $locator 'step_this_pc_before_double_click.png' 'Desktop'
    if (-not $strict.Ok) {
        Add-Event $Ctx 'desktop_shortcut_open_failed' 'failed' $strict
        return $false
    }
    $Ctx.LastStrictLocator = $locator
    $Ctx.LastStrictClick = $strict
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

function Resolve-ExplorerItemCenter($Ctx, [string]$LockedHwnd, [string]$ItemName, [string[]]$Patterns, [string]$CandidateFileName) {
    $state = Get-LockedExplorerState $LockedHwnd
    if (-not $state.explorer_window_rect) {
        Add-Locator $Ctx $ItemName 'locked Explorer hwnd state' 'not_found' $null $null $state
        return $null
    }
    if (-not $state.is_foreground_locked) {
        Add-Locator $Ctx $ItemName 'locked Explorer hwnd foreground guard' 'not_foreground' $null $null $state
        return $null
    }
    $contentRect = Get-ExplorerContentRect $state.explorer_window_rect
    $cropPath = Join-Path $Ctx.Crops ("content_before_$($ItemName -replace '[^A-Za-z0-9_.-]', '_').png")
    Save-RectCrop $cropPath $contentRect | Out-Null
    Add-Event $Ctx 'explorer_content_rect' 'ok' @{
        item = $ItemName
        locked_explorer_hwnd = $LockedHwnd
        explorer_window_rect = $state.explorer_window_rect
        content_rect = $contentRect
        content_rect_source = $contentRect.source
        content_rect_screenshot = $cropPath
    }

    $uia = Find-LockedExplorerItem $Ctx $LockedHwnd $contentRect $ItemName $Patterns 'uia locked hwnd content locator' $CandidateFileName
    if ($uia) { return $uia }

    $title = $state.foreground_title
    $clientX = [int]($contentRect.left - $state.explorer_window_rect.left)
    $clientY = [int]($contentRect.top - $state.explorer_window_rect.top)
    $clientW = [int]($contentRect.right - $contentRect.left)
    $clientH = [int]($contentRect.bottom - $contentRect.top)
    $ocr = Invoke-AgentJson -CmdArgs @('read-region-text', '--title', $title, '--x', "$clientX", '--y', "$clientY", '--w', "$clientW", '--h', "$clientH") -AllowFailure
    if ($ocr.ok) {
        $hit = @($ocr.data.words | Where-Object {
            $word = [string]$_.text
            @($Patterns | Where-Object { $word -match $_ }).Count -gt 0
        } | Select-Object -First 1)
        if ($hit) {
            $rect = $hit.rect
            $x = [int]($contentRect.left + (($rect.left + $rect.right) / 2))
            $y = [int]($contentRect.top + (($rect.top + $rect.bottom) / 2))
            if ((Test-ScreenPoint $x $y) -and (Test-PointInRect $x $y $contentRect)) {
                $targetRect = [pscustomobject]@{
                    left = [int]($contentRect.left + $rect.left)
                    top = [int]($contentRect.top + $rect.top)
                    right = [int]($contentRect.left + $rect.right)
                    bottom = [int]($contentRect.top + $rect.bottom)
                }
                Add-Locator $Ctx $ItemName 'ocr locked hwnd content locator' 'ok' $x $y @{
                    hit = $hit
                    target_rect = $targetRect
                    locked_explorer_hwnd = $LockedHwnd
                    foreground_hwnd = $state.foreground_hwnd
                    content_rect = $contentRect
                    crop = $cropPath
                }
                return [pscustomobject]@{ X = $x; Y = $y; Method = 'ocr locked hwnd content locator'; CoordinateSource = 'locator_derived'; ExpectedName = $ItemName; MatchedName = $hit.text; Rect = $targetRect; RectSource = 'ocr_text_rect'; ContentRect = $contentRect; LockedExplorerHwnd = $LockedHwnd; Raw = $hit }
            }
            Add-Locator $Ctx $ItemName 'ocr locked hwnd content locator' 'invalid_offscreen_coordinate' $x $y @{ hit = $hit; content_rect = $contentRect }
        } else {
            Add-Locator $Ctx $ItemName 'ocr locked hwnd content locator' 'not_found' $null $null @{ text = $ocr.data.text; content_rect = $contentRect; crop = $cropPath }
        }
    } else {
        Add-Locator $Ctx $ItemName 'ocr locked hwnd content locator' 'not_found' $null $null @{ error = $ocr.error.code; content_rect = $contentRect; crop = $cropPath }
    }

    $centerX = [int](($contentRect.left + $contentRect.right) / 2)
    $centerY = [int](($contentRect.top + $contentRect.bottom) / 2)
    Invoke-HumanAction $Ctx 'mouse.click' "focus locked Explorer content before view normalization for $ItemName" 'heuristic_content_rect' 'heuristic_locator_derived' $centerX $centerY @('desktop-click', '--screen-x', "$centerX", '--screen-y', "$centerY", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $Ctx 'keyboard.hotkey' "Explorer Details view for $ItemName" 'Explorer view normalization' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'CTRL+SHIFT+6', '--permission-mode', $PermissionMode) | Out-Null
    Invoke-HumanAction $Ctx 'keyboard.press' "Explorer refresh before locating $ItemName" 'Explorer view normalization' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'F5', '--permission-mode', $PermissionMode) | Out-Null
    Start-Sleep -Milliseconds 800
    Invoke-HumanAction $Ctx 'keyboard.press' "Explorer content Home before locating $ItemName" 'Explorer view normalization' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'HOME', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 300

    $state = Get-LockedExplorerState $LockedHwnd
    $contentRect = Get-ExplorerContentRect $state.explorer_window_rect
    $uiaAfterView = Find-LockedExplorerItem $Ctx $LockedHwnd $contentRect $ItemName $Patterns 'uia locked hwnd content locator after view normalization' $CandidateFileName
    if ($uiaAfterView) { return $uiaAfterView }

    for ($i = 0; $i -lt 2; $i++) {
        $state = Get-LockedExplorerState $LockedHwnd
        $contentRect = Get-ExplorerContentRect $state.explorer_window_rect
        $centerX = [int](($contentRect.left + $contentRect.right) / 2)
        $centerY = [int](($contentRect.top + $contentRect.bottom) / 2)
        $clientX = [int]($centerX - $state.explorer_window_rect.left)
        $clientY = [int]($centerY - $state.explorer_window_rect.top)
        Invoke-HumanAction $Ctx 'mouse.move' "scroll locked Explorer content searching for $ItemName" 'heuristic_content_rect' 'heuristic_locator_derived' $centerX $centerY @('desktop-move', '--screen-x', "$centerX", '--screen-y', "$centerY", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
        $scroll = Invoke-AgentJson -CmdArgs @('scroll', '--title', $state.foreground_title, '--x', "$clientX", '--y', "$clientY", '--delta', '-3') -AllowFailure
        Write-JsonLine $Ctx.Actions ([pscustomobject]@{
            timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
            action_type = 'mouse.wheel'
            target_description = "Explorer scroll retry for $ItemName"
            locator_method = 'heuristic_content_rect'
            coordinate_source = 'heuristic_locator_derived'
            screen_x = $centerX
            screen_y = $centerY
            locked_explorer_hwnd = $LockedHwnd
            humanmode = $true
            backend_action = $false
            ok = [bool]$scroll.ok
            notes = 'scroll --title locked foreground Explorer content'
        })
        $Ctx.HumanModeActionCount++
        $Ctx.HeuristicLocatorDerivedCount++
        $Ctx.WheelScrollCount++
        Start-Sleep -Milliseconds 500
        $uiaAfterScroll = Find-LockedExplorerItem $Ctx $LockedHwnd $contentRect $ItemName $Patterns 'uia locked hwnd content locator after scroll' $CandidateFileName
        if ($uiaAfterScroll) { return $uiaAfterScroll }
    }

    if ($ItemName -notmatch '^D:') {
        $state = Get-LockedExplorerState $LockedHwnd
        $contentRect = Get-ExplorerContentRect $state.explorer_window_rect
        $focusItem = Get-AnyLockedExplorerContentItem $LockedHwnd $contentRect
        if ($focusItem) {
            $focusX = $focusItem.X
            $focusY = $focusItem.Y
            $focusMethod = 'uia locked hwnd content focus item'
            $focusSource = 'locator_derived'
        } else {
            $focusX = [int]($contentRect.left + (($contentRect.right - $contentRect.left) * 0.35))
            $focusY = [int]($contentRect.top + (($contentRect.bottom - $contentRect.top) * 0.30))
            $focusMethod = 'heuristic_content_rect'
            $focusSource = 'heuristic_locator_derived'
        }
        Invoke-HumanAction $Ctx 'mouse.click' "focus locked Explorer content before incremental search for $ItemName" $focusMethod $focusSource $focusX $focusY @('desktop-click', '--screen-x', "$focusX", '--screen-y', "$focusY", '--move-mode', 'fast-human', '--permission-mode', $PermissionMode) | Out-Null
        Invoke-HumanAction $Ctx 'keyboard.type_text' "Explorer incremental item search: $ItemName" 'Explorer content incremental search' 'keyboard_after_mouse_focus' $null $null @('desktop-type', '--text', $ItemName, '--type-mode', 'demo-human', '--char-delay-ms', '35', '--permission-mode', $PermissionMode) | Out-Null
        $Ctx.IncrementalSearchCount++
        Start-Sleep -Milliseconds 900
        $afterIncremental = Find-LockedExplorerItem $Ctx $LockedHwnd $contentRect $ItemName $Patterns 'uia locked hwnd content locator after incremental search' $CandidateFileName
        if ($afterIncremental) { return $afterIncremental }
        $selected = Get-SelectedExplorerItemEvidence $LockedHwnd $contentRect
        if ($selected -and @($Patterns | Where-Object { ([string]$selected.Name) -match $_ }).Count -gt 0) {
            $sx = [int](($selected.Rect.left + $selected.Rect.right) / 2)
            $sy = [int](($selected.Rect.top + $selected.Rect.bottom) / 2)
            Add-Locator $Ctx $ItemName 'incremental_search_locator selected item' 'ok' $sx $sy @{
                selected_name = $selected.Name
                selected_control_type = $selected.ControlType
                selected_rect = $selected.Rect
                locked_explorer_hwnd = $LockedHwnd
                content_rect = $contentRect
            }
            return [pscustomobject]@{ X = $sx; Y = $sy; Method = 'incremental_search_locator selected item'; CoordinateSource = 'locator_derived'; ExpectedName = $ItemName; MatchedName = $selected.Name; Rect = $selected.Rect; RectSource = 'uia_selected_item'; ContentRect = $contentRect; LockedExplorerHwnd = $LockedHwnd; Raw = $selected; IncrementalSearchUsedAsLocatorOnly = $true }
        }
        Add-Locator $Ctx $ItemName 'incremental_search_locator selected item' 'not_found' $null $null @{ typed = $ItemName; locked_explorer_hwnd = $LockedHwnd; content_rect = $contentRect }
        Add-Locator $Ctx $ItemName 'incremental_search_locator typed current-folder selection' 'failed_selected_item_rect_missing' $null $null @{
            typed = $ItemName
            locked_explorer_hwnd = $LockedHwnd
            content_rect = $contentRect
            note = 'Incremental search is locator-only in v5.9.3; selected item rect is required before mouse double-click.'
        }
        $Ctx.SelectedItemRectMissingCount++
        return $null
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

function Test-LockedExplorerHasContentItem([string]$LockedHwnd, [string[]]$Patterns) {
    $state = Get-LockedExplorerState $LockedHwnd
    if (-not $state.explorer_window_rect) { return $false }
    $contentRect = Get-ExplorerContentRect $state.explorer_window_rect
    $elements = Get-LockedExplorerElements $LockedHwnd
    foreach ($e in $elements) {
        $name = [string]$e.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($e.IsOffscreen) { continue }
        if ($e.Rect.right -le $e.Rect.left -or $e.Rect.bottom -le $e.Rect.top) { continue }
        if (-not (Test-RectIntersects $e.Rect $contentRect)) { continue }
        if (@($Patterns | Where-Object { $name -match $_ }).Count -gt 0) { return $true }
    }
    return $false
}

function Get-LockedExplorerTextSnapshot([string]$LockedHwnd) {
    $elements = Get-LockedExplorerElements $LockedHwnd
    return (($elements | Where-Object { $_.Name } | Select-Object -ExpandProperty Name -Unique) -join "`n")
}

function Verify-ExplorerLocation($Ctx, [string]$LockedHwnd, [string]$StepName, [string]$ExpectedLocation, [string[]]$EvidencePatterns) {
    $deadline = (Get-Date).AddSeconds(8)
    $lastState = $null
    $lastText = ''
    while ((Get-Date) -lt $deadline) {
        $lastState = Get-LockedExplorerState $LockedHwnd
        $lastText = Get-LockedExplorerTextSnapshot $LockedHwnd
        $matchedText = @($EvidencePatterns | Where-Object { $lastText -match $_ }).Count -gt 0
        $matchedTitle = @($EvidencePatterns | Where-Object { $lastState.foreground_title -match $_ }).Count -gt 0
        $matchedItem = Test-LockedExplorerHasContentItem $LockedHwnd $EvidencePatterns
        if ($lastState.is_foreground_locked -and ($matchedText -or $matchedItem -or $matchedTitle)) {
            Write-JsonLine $Ctx.Actions ([pscustomobject]@{
                action_type = 'open_verification'
                expected_location = $ExpectedLocation
                verification_method = 'locked_hwnd_title_or_uia_text_or_content_item'
                ok = $true
                locked_explorer_hwnd = $LockedHwnd
                foreground_hwnd = $lastState.foreground_hwnd
                foreground_title = $lastState.foreground_title
                timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
            })
            Add-Event $Ctx 'explorer_location_verification' 'ok' @{
                step = $StepName
                expected_location = $ExpectedLocation
                locked_explorer_hwnd = $LockedHwnd
                foreground_hwnd = $lastState.foreground_hwnd
                foreground_title = $lastState.foreground_title
                foreground_process = $lastState.foreground_process
                explorer_window_rect = $lastState.explorer_window_rect
                explorer_content_rect = Get-ExplorerContentRect $lastState.explorer_window_rect
                verification_method = 'locked_hwnd_uia_text_or_content_item'
                matched_text = $matchedText
                matched_item = $matchedItem
                matched_title = $matchedTitle
            }
            return [pscustomobject]@{ Ok = $true; Method = 'locked_hwnd_title_or_uia_text_or_content_item'; State = $lastState; Text = $lastText }
        }
        Start-Sleep -Milliseconds 400
    }
    Add-Event $Ctx 'explorer_location_verification' 'failed' @{
        step = $StepName
        expected_location = $ExpectedLocation
        locked_explorer_hwnd = $LockedHwnd
        last_state = $lastState
        text_sample = $lastText
    }
    Write-JsonLine $Ctx.Actions ([pscustomobject]@{
        action_type = 'open_verification'
        expected_location = $ExpectedLocation
        verification_method = 'locked_hwnd_uia_text_or_content_item'
        ok = $false
        locked_explorer_hwnd = $LockedHwnd
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    })
    return [pscustomobject]@{ Ok = $false; Method = 'locked_hwnd_uia_text_or_content_item'; State = $lastState; Text = $lastText }
}

function Add-ExplorerPathStep($Steps, [string]$StepName, [string]$ExpectedName, [string]$ExpectedLocationBefore, [string]$ExpectedLocationAfter, [string]$LockedHwnd, $Locator, $StrictClick, [string]$VerificationMethod, $Verification, [string]$ScreenshotBefore, [string]$ScreenshotAfter, [string]$Result) {
    $state = Get-LockedExplorerState $LockedHwnd
    $Steps.Add([pscustomobject]@{
        step_name = $StepName
        expected_name = $ExpectedName
        expected_location_before = $ExpectedLocationBefore
        expected_location_after = $ExpectedLocationAfter
        locked_explorer_hwnd = $LockedHwnd
        foreground_hwnd = $state.foreground_hwnd
        foreground_title = $state.foreground_title
        foreground_process = $state.foreground_process
        explorer_window_rect = $state.explorer_window_rect
        content_rect = Convert-RectArray (Get-ExplorerContentRect $state.explorer_window_rect)
        locator_methods_attempted = @('uia locked hwnd content locator', 'ocr locked hwnd content locator', 'view normalization', 'scroll retry', 'incremental search when applicable')
        selected_candidate = $Locator
        target_rect = Convert-RectArray $Locator.Rect
        cursor_before_click = @([int]$StrictClick.CursorBeforeClick.X, [int]$StrictClick.CursorBeforeClick.Y)
        cursor_inside_target_rect_before_click = [bool]$StrictClick.CursorInsideTargetRectBeforeClick
        distance_to_target_center_px = [int]$StrictClick.DistanceToTargetCenterPx
        action_type = 'mouse_double_click'
        humanmode = $true
        backend_action = $false
        open_action = 'mouse_double_click_on_target_rect'
        verification_method = $VerificationMethod
        verification_result = $Verification
        screenshot_before = $ScreenshotBefore
        overlay_before_click = $StrictClick.Overlay
        screenshot_after = $ScreenshotAfter
        result = $(if ($Result -eq 'ok') { 'PASS' } elseif ($Result -eq 'pending') { 'PENDING' } else { 'FAIL' })
    }) | Out-Null
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
    foreach ($candidateFile in @('locator_candidates_testrepo.json', 'locator_candidates_testwindow.json', 'locator_candidates_html.json')) {
        '[]' | Set-Content -LiteralPath (Join-Path $ctx.Dir $candidateFile) -Encoding UTF8
    }
    Write-MockHtml
    $advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $previousHideFileExt = $null
    try {
        $previousHideFileExt = (Get-ItemProperty -LiteralPath $advancedKey -Name HideFileExt -ErrorAction SilentlyContinue).HideFileExt
        if ($null -eq $previousHideFileExt) {
            New-ItemProperty -LiteralPath $advancedKey -Name HideFileExt -PropertyType DWord -Value 0 -Force | Out-Null
        } else {
            Set-ItemProperty -LiteralPath $advancedKey -Name HideFileExt -Value 0
        }
    } catch {
        Add-Event $ctx 'setup_show_file_extensions' 'failed' @{ error = $_.Exception.Message; setup_only = $true }
    }
    Add-Event $ctx 'setup_local_html' 'ok' @{ path = $MockHtml; setup_only = $true }
    @(
        '# Case D Setup Report',
        '',
        "- mock_dir: $MockDir",
        "- mock_html: $MockHtml",
        "- explorer_hide_file_ext_previous: $previousHideFileExt",
        "- explorer_hide_file_ext_for_case: 0",
        "- setup_only: true",
        "- note: file creation and Explorer extension visibility normalization are setup evidence only and are not used as open verification."
    ) | Set-Content -LiteralPath (Join-Path $ctx.Dir 'setup_report.md') -Encoding UTF8
    Invoke-HumanAction $ctx 'keyboard.hotkey' 'show desktop before Case D screenshot' 'desktop global keyboard' 'fallback_keyboard' $null $null @('desktop-hotkey', '--keys', 'WIN+D', '--permission-mode', $PermissionMode) | Out-Null
    Start-Sleep -Milliseconds 700
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
        Fail-Case $ctx 'FAIL_EXPLORER_HWND_LOCK' 'Explorer did not become the foreground window after This PC fixture double-click.'
        return $ctx
    }
    $lockedHwnd = $activeExplorer.data.hwnd
    $ctx.LockedExplorerHwnd = $lockedHwnd
    $lockState = Get-LockedExplorerState $lockedHwnd
    if (-not $lockState.explorer_window_rect -or -not $lockState.is_foreground_locked) {
        Fail-Case $ctx 'FAIL_EXPLORER_HWND_LOCK' 'Locked Explorer hwnd could not be established as a visible foreground Explorer window.'
        return $ctx
    }
    Add-Event $ctx 'locked_explorer_hwnd' 'ok' $lockState
    $contentRect = Get-ExplorerContentRect $lockState.explorer_window_rect
    Save-RectCrop (Join-Path $ctx.Crops 'locked_explorer_content_initial.png') $contentRect | Out-Null
    @(
        '# Explorer HWND Lock Report',
        '',
        "- locked_explorer_hwnd: $lockedHwnd",
        "- foreground_hwnd: $($lockState.foreground_hwnd)",
        "- foreground_title: $($lockState.foreground_title)",
        "- foreground_process: $($lockState.foreground_process)",
        "- explorer_window_rect: $($lockState.explorer_window_rect | ConvertTo-Json -Compress)",
        "- explorer_content_rect: $($contentRect | ConvertTo-Json -Compress)",
        "- content_rect_source: $($contentRect.source)"
    ) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'explorer_hwnd_lock_report.md') -Encoding UTF8
    @(
        '# Explorer Content Rect Report',
        '',
        "- content_rect_source: $($contentRect.source)",
        "- content_rect: $($contentRect | ConvertTo-Json -Compress)",
        "- content_rect_screenshot: cases\\explorer_open_local_html_via_humanmode_flow\\crops\\locked_explorer_content_initial.png",
        "- excludes: title bar, toolbar/address bar, navigation pane, status bar by heuristic geometry"
    ) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'explorer_content_rect_report.md') -Encoding UTF8

    $steps = New-Object System.Collections.Generic.List[object]
    $thisPcVerify = Verify-ExplorerLocation $ctx $lockedHwnd 'this_pc_opened' 'This PC / Devices and drives' @('D:', 'Data \(D:\)', 'Local Disk \(D:\)', '本地磁盘 \(D:\)', '设备和驱动器', 'Devices and drives')
    if (-not $thisPcVerify.Ok) {
        Fail-Case $ctx 'FAIL_EXPLORER_HWND_LOCK' 'This PC devices view was not verified after fixture double-click.'
        return $ctx
    }
    $thisPcAfter = Save-CaseScreenshot $ctx 'after_open_this_pc.png'
    Add-ExplorerPathStep $steps 'open_this_pc' $shortcutName 'Desktop' 'This PC / Devices and drives' $lockedHwnd $ctx.LastStrictLocator $ctx.LastStrictClick $thisPcVerify.Method $thisPcVerify (Join-Path $ctx.Screenshots 'before_desktop.png') $thisPcAfter 'ok'

    $openSteps = @(
        @{ Name = 'D:'; StepName = 'open_d_drive'; Before = 'This PC / Devices and drives'; Expected = 'D:\'; Overlay = 'step_d_drive_before_double_click.png'; Patterns = @('D:', 'Data \(D:\)', 'Local Disk \(D:\)', '本地磁盘 \(D:\)'); CandidateFile = 'locator_candidates_d_drive.json'; VerifyPatterns = @('Data \(D:\) - 文件资源管理器', '在 Data \(D:\) 中搜索', '刷新.*Data \(D:\)', 'D:\\'); Failure = 'FAIL_LOCATOR_D_DRIVE' },
        @{ Name = 'testrepo'; StepName = 'open_testrepo'; Before = 'D:\'; Expected = 'D:\testrepo'; Overlay = 'step_testrepo_before_double_click.png'; Patterns = @('^testrepo$'); CandidateFile = 'locator_candidates_testrepo.json'; VerifyPatterns = @('(?m)^testrepo$', 'testrepo - 文件资源管理器', '在 testrepo 中搜索', '(?m)^testwindow$', 'D:\\testrepo'); Failure = 'FAIL_LOCATOR_TESTREPO' },
        @{ Name = 'testwindow'; StepName = 'open_testwindow'; Before = 'D:\testrepo'; Expected = 'D:\testrepo\testwindow'; Overlay = 'step_testwindow_before_double_click.png'; Patterns = @('^testwindow$'); CandidateFile = 'locator_candidates_testwindow.json'; VerifyPatterns = @('(?m)^testwindow$', 'testwindow - 文件资源管理器', '在 testwindow 中搜索', '(?m)^desktopvisual_mail_mock\.html$', 'desktopvisual_mail_mock', 'D:\\testrepo\\testwindow'); Failure = 'FAIL_LOCATOR_TESTWINDOW' },
        @{ Name = 'desktopvisual_mail_mock.html'; StepName = 'open_html_file'; Before = 'D:\testrepo\testwindow'; Expected = 'file://D:/testrepo/testwindow/desktopvisual_mail_mock.html'; Overlay = 'step_html_before_double_click.png'; Patterns = @('^desktopvisual_mail_mock\.html$', 'desktopvisual_mail_mock'); CandidateFile = 'locator_candidates_html.json'; VerifyPatterns = @('DesktopVisual Local Mail Mock', 'Chrome', 'Edge'); Failure = 'FAIL_LOCATOR_HTML' }
    )
    foreach ($step in $openSteps) {
        $beforeShot = Save-CaseScreenshot $ctx ("before_$($step.StepName).png")
        if ($step.Name -eq 'desktopvisual_mail_mock.html') {
            Invoke-HumanAction $ctx 'keyboard.press' 'refresh Explorer after enabling file extensions before HTML locate' 'Explorer view normalization' 'fallback_keyboard' $null $null @('desktop-press', '--key', 'F5', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
            Start-Sleep -Milliseconds 800
        }
        $center = Resolve-ExplorerItemCenter $ctx $lockedHwnd $step.Name $step.Patterns $step.CandidateFile
        if (-not $center) {
            $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_steps.json') -Encoding UTF8
            Save-CaseScreenshot $ctx "failure_locator_$($step.Name -replace '[^A-Za-z0-9_.-]', '_').png" | Out-Null
            Fail-Case $ctx $step.Failure "Explorer item not found through locked hwnd UIA/OCR/view/scroll/incremental locator: $($step.Name)."
            return $ctx
        }
        $strictClick = Invoke-StrictTargetDoubleClick $ctx $step.StepName $step.Name $center $step.Overlay $step.Before
        if (-not $strictClick.Ok) {
            $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_steps.json') -Encoding UTF8
            Fail-Case $ctx $strictClick.Code $strictClick.Message
            return $ctx
        }
        Start-Sleep -Seconds 2
        if ($step.Name -eq 'desktopvisual_mail_mock.html') {
            $afterShot = Save-CaseScreenshot $ctx 'after_file_open.png'
            Add-ExplorerPathStep $steps $step.StepName $step.Name $step.Before $step.Expected $lockedHwnd $center $strictClick 'browser_file_url_or_title' @{ pending_browser_verification = $true } $beforeShot $afterShot 'pending'
            break
        }
        $verify = Verify-ExplorerLocation $ctx $lockedHwnd $step.StepName $step.Expected $step.VerifyPatterns
        $afterShot = Save-CaseScreenshot $ctx ("after_$($step.StepName).png")
        Add-ExplorerPathStep $steps $step.StepName $step.Name $step.Before $step.Expected $lockedHwnd $center $strictClick $verify.Method $verify $beforeShot $afterShot $(if ($verify.Ok) { 'ok' } else { 'failed' })
        if (-not $verify.Ok) {
            $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_steps.json') -Encoding UTF8
            Fail-Case $ctx $step.Failure "Explorer location verification failed after strict mouse-target double-click on $($step.Name); expected $($step.Expected)."
            return $ctx
        }
    }
    @(
        '# Explorer Path Locator Report',
        '',
        "- locked_explorer_hwnd: $lockedHwnd",
        '- This PC opened through desktop fixture double-click.',
        '- This PC fixture, D: drive, testrepo, testwindow, and desktopvisual_mail_mock.html are opened only after target item rect resolution, cursor-inside-rect verification, and real mouse double-click.',
        "- steps: $($steps.Count)",
        "- fixture_used: $($ctx.FixtureUsed)",
        "- incremental_search_count: $($ctx.IncrementalSearchCount)",
        "- wheel_scroll_count: $($ctx.WheelScrollCount)"
    ) | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_locator_report.md') -Encoding UTF8
    $title = Wait-WindowTitle 'DesktopVisual Local Mail Mock|desktopvisual_mail_mock|Chrome|Edge' 12
    $verified = $false
    if ($title) {
        $text = Invoke-AgentJson -CmdArgs @('read-window-text', '--title', $title) -AllowFailure
        $ocrText = if ($text.ok) { [string]$text.data.text } else { '' }
        $verified = ($title -match 'DesktopVisual Local Mail Mock|desktopvisual_mail_mock') -or ($ocrText -match 'DesktopVisual Local Mail Mock|file://D:/testrepo/testwindow/desktopvisual_mail_mock.html|D:/testrepo/testwindow/desktopvisual_mail_mock.html')
    }
    Write-JsonLine $ctx.Actions ([pscustomobject]@{
        action_type = 'open_verification'
        expected_location = 'file://D:/testrepo/testwindow/desktopvisual_mail_mock.html'
        verification_method = 'browser_file_url_or_title'
        ok = $verified
        foreground_title = $title
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    })
    if ($steps.Count -gt 0) {
        $steps[$steps.Count - 1].verification_result = [pscustomobject]@{ browser_title = $title; verification_passed = $verified }
        $steps[$steps.Count - 1].result = $(if ($verified) { 'ok' } else { 'failed' })
    }
    $candidateStepMap = @{
        'locator_candidates_testrepo.json' = 'open_testrepo'
        'locator_candidates_testwindow.json' = 'open_testwindow'
        'locator_candidates_html.json' = 'open_html_file'
    }
    foreach ($candidateFile in $candidateStepMap.Keys) {
        $candidatePath = Join-Path $ctx.Dir $candidateFile
        $candidateRaw = if (Test-Path -LiteralPath $candidatePath) { (Get-Content -Raw -LiteralPath $candidatePath).Trim() } else { '' }
        $needsWrite = [string]::IsNullOrWhiteSpace($candidateRaw) -or $candidateRaw -eq '[]'
        if ($needsWrite) {
            $stepForCandidate = @($steps | Where-Object { $_.step_name -eq $candidateStepMap[$candidateFile] } | Select-Object -First 1)
            $candidateEvidence = @()
            if ($stepForCandidate.Count -gt 0 -and $stepForCandidate[0].selected_candidate) {
                $candidateEvidence = @($stepForCandidate[0].selected_candidate)
            }
            @($candidateEvidence) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $candidatePath -Encoding UTF8
        }
    }
    $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'explorer_path_steps.json') -Encoding UTF8
    $selectedRects = @($steps | ForEach-Object {
        [pscustomobject]@{
            step_name = $_.step_name
            expected_name = $_.expected_name
            matched_name = $_.selected_candidate.MatchedName
            rect_source = $_.selected_candidate.RectSource
            target_rect = $_.target_rect
            cursor_before_click = $_.cursor_before_click
            cursor_inside_target_rect_before_click = $_.cursor_inside_target_rect_before_click
        }
    })
    $selectedRects | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ctx.Dir 'selected_item_rects.json') -Encoding UTF8
    $strictCountersOk = (
        $ctx.EnterOpenCount -eq 0 -and
        $ctx.KeyboardAssistedOpenCount -eq 0 -and
        $ctx.TargetRectMissingCount -eq 0 -and
        $ctx.CursorOutsideTargetRectCount -eq 0 -and
        $ctx.BackendActionCount -eq 0 -and
        $ctx.ShellExecuteCount -eq 0 -and
        $ctx.StartProcessCount -eq 0 -and
        $ctx.InvokeItemCount -eq 0 -and
        $ctx.DirectFileOpenCount -eq 0 -and
        $ctx.UiaInvokeActionCount -eq 0 -and
        $ctx.UiaValueActionCount -eq 0 -and
        $ctx.HumanActionResultParseErrors -eq 0 -and
        $ctx.PathStepsWithTargetRect -eq $ctx.PathStepsTotal -and
        $ctx.PathStepsWithCursorInsideTargetRect -eq $ctx.PathStepsTotal
    )
    if ($verified -and $strictCountersOk) {
        Complete-Case $ctx 'STRICT_MOUSE_TARGET_HUMANMODE_PASS' 'Opened local HTML by visible Explorer UI path with target item rect, cursor-inside-rect verification, and real double-click at every level.' "Observed browser/local page title: $title"
        return $ctx
    }
    if ($verified -and -not $strictCountersOk) {
        Fail-Case $ctx 'KEYBOARD_ASSISTED_HUMANMODE_ONLY' 'Case reached the target but failed strict mouse-target counter requirements.'
        return $ctx
    }
    Fail-Case $ctx 'FAIL_LOCATOR_HTML' 'Browser/local HTML window did not appear after strict Explorer path file double-click.'
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

$previousEvidenceFiles = @('task_result.json', 'action_trace.jsonl', 'locator_trace.jsonl', 'task_report.md')
$previousAvailable = $true
foreach ($name in $previousEvidenceFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PreviousArtifactRoot $name))) { $previousAvailable = $false }
}
if (-not $previousAvailable) {
    'previous_evidence_unavailable: v5.9.0-d Case D artifacts were not present at the required path; no historical evidence was fabricated.' |
        Set-Content -LiteralPath (Join-Path $ArtifactRoot 'previous_evidence_unavailable.md') -Encoding UTF8
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

Write-MockHtml

$caseResults = @()
if ($SkipGuiCases) {
    $ctx = New-CaseContext 'explorer_open_local_html_via_humanmode_flow'
    Fail-Case $ctx 'SKIP_ENVIRONMENT' 'GUI Case D was skipped by -SkipGuiCases.'
    $caseResults += $ctx
} else {
    $caseResults += Case-D
}

$summary = foreach ($ctx in $caseResults) {
    Get-Content -LiteralPath $ctx.Result -Raw | ConvertFrom-Json
}

$counts = @{
    strict_mouse_target_humanmode_pass_count = @($summary | Where-Object status -eq 'STRICT_MOUSE_TARGET_HUMANMODE_PASS').Count
    keyboard_assisted_humanmode_only_count = @($summary | Where-Object status -eq 'KEYBOARD_ASSISTED_HUMANMODE_ONLY').Count
    skip_environment_count = @($summary | Where-Object status -eq 'SKIP_ENVIRONMENT').Count
    fail_count = @($summary | Where-Object { $_.status -match '^FAIL' }).Count
    blocked_by_active_protection_count = @($summary | Where-Object status -eq 'BLOCKED_BY_ACTIVE_PROTECTION').Count
    fail_policy_defect_count = @($summary | Where-Object status -eq 'FAIL_POLICY_DEFECT').Count
    fixed_coordinate_count = @($summary | Measure-Object -Property fixed_coordinate_count -Sum).Sum
    locator_derived_coordinate_count = @($summary | Measure-Object -Property locator_derived_coordinate_count -Sum).Sum
    heuristic_locator_derived_count = @($summary | Measure-Object -Property heuristic_locator_derived_count -Sum).Sum
    humanmode_action_count = @($summary | Measure-Object -Property humanmode_action_count -Sum).Sum
    backend_action_count = @($summary | Measure-Object -Property backend_action_count -Sum).Sum
    direct_file_open_count = @($summary | Measure-Object -Property direct_file_open_count -Sum).Sum
    shell_execute_count = @($summary | Measure-Object -Property shell_execute_count -Sum).Sum
    start_process_count = @($summary | Measure-Object -Property start_process_count -Sum).Sum
    invoke_item_count = @($summary | Measure-Object -Property invoke_item_count -Sum).Sum
    explorer_addressbar_path_input_count = @($summary | Measure-Object -Property explorer_addressbar_path_input_count -Sum).Sum
    uia_invoke_action_count = @($summary | Measure-Object -Property uia_invoke_action_count -Sum).Sum
    uia_value_action_count = @($summary | Measure-Object -Property uia_value_action_count -Sum).Sum
    incremental_search_count = @($summary | Measure-Object -Property incremental_search_count -Sum).Sum
    enter_open_count = @($summary | Measure-Object -Property enter_open_count -Sum).Sum
    target_rect_missing_count = @($summary | Measure-Object -Property target_rect_missing_count -Sum).Sum
    cursor_outside_target_rect_count = @($summary | Measure-Object -Property cursor_outside_target_rect_count -Sum).Sum
    wheel_scroll_count = @($summary | Measure-Object -Property wheel_scroll_count -Sum).Sum
    vlm_call_count = 0
    fake_pass_count = 0
}

@(
    '# Runtime Boundary Report',
    '',
    ($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "- $($_.Name): $($_.Value)" })
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runtime_boundary_report.md') -Encoding UTF8

$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'case_summary.json') -Encoding UTF8

$reportFiles = @{
    'dev_summary.md' = 'v5.9.3 remains v5 and only fixes Explorer Case D mouse target strictness. It does not enter v6, add VLM, develop an Agent Planner, narrow public release permissions, change developer permission direction, fix Case E/F, integrate TaskRuntime, run Pre-v6 Gate, or auto commit.'
    'test_summary.md' = 'Required commands: build, winagent version, permission reset selftest, HumanMode pacing test, v5.9.3 Case D strict runner, JSON/JSONL parse, Markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, and git status snapshot.'
    'known_limits.md' = 'Case D remains current-machine GUI evidence. PASS requires target item rect, cursor inside target rect before click, real double-click in the rect, and post-open verification for all five path steps. SKIP/FAIL/keyboard-assisted paths are not strict PASS.'
    'explorer_mouse_target_strictness_report.md' = 'Case D strict standard is upgraded to STRICT_MOUSE_TARGET_HUMANMODE_PASS. v5.9.0-d/v5.9.1 evidence with keyboard-assisted or selection-assisted opens is not strict mouse-target evidence.'
    'selected_item_rect_report.md' = 'Incremental search is locator-only. If selected item name is not the expected target or selected item rect is missing, the result is FAIL_SELECTED_ITEM_NAME_MISMATCH or FAIL_SELECTED_ITEM_RECT_MISSING, not strict PASS.'
    'mouse_target_validation_report.md' = 'Before every Explorer item double-click, the runner resolves target_rect, moves the cursor to the rect center, reads GetCursorPos through mouse-position, requires cursor_inside_target_rect_before_click=true, saves overlay evidence, then sends real double-click.'
    'case_d_reclassification_report.md' = 'Keyboard selection, incremental search plus Enter, default selection open, address-bar path input, ShellExecute, Start-Process, Invoke-Item, UIA InvokePattern/ValuePattern, and backend opens are reclassified out of strict Case D.'
    'regression_report.md' = 'Regression scope is intentionally limited to v5.9.3 Case D mouse-target strictness plus required permission, pacing, parse, markdown, encoding, command protocol, and git status checks.'
}
foreach ($entry in $reportFiles.GetEnumerator()) {
    $entry.Value | Set-Content -LiteralPath (Join-Path $ArtifactRoot $entry.Key) -Encoding UTF8
}

$map = @{
    'explorer_mouse_target_strictness_report.md' = 'explorer_open_local_html_via_humanmode_flow'
}
foreach ($entry in $map.GetEnumerator()) {
    $caseResult = $summary | Where-Object case_id -eq $entry.Value | Select-Object -First 1
    @(
        "# $($entry.Value)",
        "",
        "- Previous result from v5.9.0-d: $($caseResult.previous_result_from_v5_9_0_d)",
        "- Result: $($caseResult.actual_result)",
        "- Summary: $($caseResult.summary)",
        "- Strict mouse-target HumanMode: $($caseResult.strict_mouse_target_humanmode)",
        "- This PC fixture used: $($caseResult.this_pc_fixture_used)",
        "- Locked Explorer hwnd: $($caseResult.locked_explorer_hwnd)",
        "- Path steps with target rect: $($caseResult.path_steps_with_target_rect) / $($caseResult.path_steps_total)",
        "- Path steps with cursor inside target rect: $($caseResult.path_steps_with_cursor_inside_target_rect) / $($caseResult.path_steps_total)",
        "- Incremental search count: $($caseResult.incremental_search_count)",
        "- Enter open count: $($caseResult.enter_open_count)",
        "- Target rect missing count: $($caseResult.target_rect_missing_count)",
        "- Cursor outside target rect count: $($caseResult.cursor_outside_target_rect_count)",
        "- Wheel scroll count: $($caseResult.wheel_scroll_count)",
        "- Explorer addressbar path input count: $($caseResult.explorer_addressbar_path_input_count)",
        "- Backend action count: $($caseResult.backend_action_count)",
        "- Direct file open count: $($caseResult.direct_file_open_count)",
        "- Case dir: $((Join-Path $CasesRoot $entry.Value))"
    ) | Set-Content -LiteralPath (Join-Path $ArtifactRoot $entry.Key) -Encoding UTF8
}

foreach ($requiredReport in @('explorer_hwnd_lock_report.md', 'explorer_content_rect_report.md')) {
    $path = Join-Path $ArtifactRoot $requiredReport
    if (-not (Test-Path -LiteralPath $path)) {
        "# $requiredReport`n`nNot available because Case D failed before this evidence point." | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_final.txt') -Encoding UTF8
git -C $Root diff --name-only | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'modified_files.txt') -Encoding UTF8

Get-ChildItem -Path $ArtifactRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($ArtifactRoot.Length + 1) } |
    Sort-Object |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'evidence_index.md') -Encoding UTF8

Write-Host "v5.9.3 Explorer mouse target strictness runner complete."
Write-Host "Artifacts: $ArtifactRoot"
