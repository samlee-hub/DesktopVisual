param(
    [string]$Root = '',
    [switch]$SkipBuild,
    [int]$Rounds = 2
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$RawCasesRoot = Join-Path $RawRoot 'cases'
$MockDir = 'D:\testrepo\testwindow'
$LocalFileHtml = Join-Path $MockDir 'desktopvisual_mail_mock.html'
$LocalhostHtml = Join-Path $MockDir 'mail_mock.html'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

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
        throw "Refusing to clear evidence path outside raw cases root: $fullPath"
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function ConvertTo-JsonSafeValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [char]) { return $Value }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [long] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
    if ($Value -is [datetime]) { return $Value.ToString('o') }
    if ($Value -is [System.Enum]) { return $Value.ToString() }
    if ($Value -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $hash[[string]$key] = ConvertTo-JsonSafeValue $Value[$key]
        }
        return $hash
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $array = @()
        foreach ($item in $Value) {
            $array += ,(ConvertTo-JsonSafeValue $item)
        }
        return ,$array
    }
    $props = @($Value.PSObject.Properties | Where-Object {
        $_.MemberType -eq 'NoteProperty' -or $_.MemberType -eq 'Property' -or $_.MemberType -eq 'ScriptProperty'
    })
    if ($props.Count -gt 0) {
        $hash = [ordered]@{}
        foreach ($prop in $props) {
            $hash[[string]$prop.Name] = ConvertTo-JsonSafeValue $prop.Value
        }
        return $hash
    }
    return [string]$Value
}

function Write-JsonLine([string]$Path, $Object) {
    (ConvertTo-JsonSafeValue $Object | ConvertTo-Json -Compress -Depth 80) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-Hashtable($Object) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object }
    $hash = [ordered]@{}
    foreach ($prop in $Object.PSObject.Properties) {
        $hash[$prop.Name] = $prop.Value
    }
    return $hash
}

function Quote-ProcessArgument([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '\\', '\\' -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Join-ProcessArguments([string[]]$CommandArgs) {
    return (($CommandArgs | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ')
}

function New-RawCase([string]$CaseId) {
    $dir = Join-Path $RawCasesRoot $CaseId
    Clear-CaseDir $dir $RawCasesRoot
    foreach ($sub in @('', 'stdout', 'stderr', 'screenshots', 'overlays', 'crops', 'result_json')) {
        Ensure-Dir (Join-Path $dir $sub)
    }
    foreach ($file in @('raw_command_log.jsonl', 'raw_stdout.jsonl', 'preliminary_observations.jsonl')) {
        Set-Content -LiteralPath (Join-Path $dir $file) -Value '' -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $dir 'raw_stderr.log') -Value '' -Encoding UTF8
    [pscustomobject]@{
        CaseId = $CaseId
        Dir = $dir
        StdoutDir = Join-Path $dir 'stdout'
        StderrDir = Join-Path $dir 'stderr'
        Screenshots = Join-Path $dir 'screenshots'
        Overlays = Join-Path $dir 'overlays'
        Crops = Join-Path $dir 'crops'
        ResultJson = Join-Path $dir 'result_json'
        CommandLog = Join-Path $dir 'raw_command_log.jsonl'
        StdoutLog = Join-Path $dir 'raw_stdout.jsonl'
        StderrLog = Join-Path $dir 'raw_stderr.log'
        Preliminary = Join-Path $dir 'preliminary_observations.jsonl'
        Sequence = 0
    }
}

function Add-Preliminary($Ctx, [string]$Kind, $Details) {
    Write-JsonLine $Ctx.Preliminary ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        case_id = $Ctx.CaseId
        kind = $Kind
        details = $Details
        verified_by_runner = $false
    })
}

function Invoke-WinAgentRaw($Ctx, [string]$Step, [string[]]$CommandArgs, [switch]$AllowFailure) {
    $Ctx.Sequence++
    $seq = '{0:D4}' -f $Ctx.Sequence
    $stdoutPath = Join-Path $Ctx.StdoutDir "$seq-$Step.stdout.json"
    $stderrPath = Join-Path $Ctx.StderrDir "$seq-$Step.stderr.txt"
    $start = Get-Date

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $WinAgent
    $psi.Arguments = Join-ProcessArguments $CommandArgs
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exit = $process.ExitCode
    $end = Get-Date

    $stdout | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    $stderr | Set-Content -LiteralPath $stderrPath -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Add-Content -LiteralPath $Ctx.StderrLog -Encoding UTF8 -Value "[$($start.ToString('o'))] $Step"
        Add-Content -LiteralPath $Ctx.StderrLog -Encoding UTF8 -Value $stderr
    }

    $parsed = $null
    $parseError = ''
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        try {
            $parsed = $stdout.Trim() | ConvertFrom-Json
        } catch {
            $parseError = $_.Exception.Message
        }
    }

    Write-JsonLine $Ctx.CommandLog ([pscustomobject]@{
        timestamp = $start.ToString('o')
        completed_at = $end.ToString('o')
        case_id = $Ctx.CaseId
        sequence = $Ctx.Sequence
        step = $Step
        command_line = @($WinAgent) + $CommandArgs
        command = $(if ($CommandArgs.Count -gt 0) { $CommandArgs[0] } else { '' })
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        exit_code = $exit
        duration_ms = [int]($end - $start).TotalMilliseconds
        stdout_json_parse_error = $parseError
    })
    Write-JsonLine $Ctx.StdoutLog ([pscustomobject]@{
        timestamp = $start.ToString('o')
        case_id = $Ctx.CaseId
        sequence = $Ctx.Sequence
        step = $Step
        command = $(if ($CommandArgs.Count -gt 0) { $CommandArgs[0] } else { '' })
        exit_code = $exit
        stdout = $stdout.Trim()
        parsed_json = $parsed
    })

    if ($exit -ne 0 -and -not $AllowFailure) {
        throw "winagent $($CommandArgs -join ' ') exited $exit. stdout=$stdout stderr=$stderr"
    }

    [pscustomobject]@{
        Ok = ($exit -eq 0)
        ExitCode = $exit
        Stdout = $stdout
        Stderr = $stderr
        Json = $parsed
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
        Step = $Step
        Args = $CommandArgs
    }
}

function Get-RectCenter($Rect) {
    [pscustomobject]@{
        X = [int](($Rect.left + $Rect.right) / 2)
        Y = [int](($Rect.top + $Rect.bottom) / 2)
    }
}

function Test-Rect($Rect) {
    return ($Rect -and [int]$Rect.right -gt [int]$Rect.left -and [int]$Rect.bottom -gt [int]$Rect.top)
}

function Test-WindowTitleMatch([string]$Title, [string]$Pattern) {
    if ($Title -match $Pattern) { return $true }
    $thisPcCn = -join ([char[]]@(0x6b64, 0x7535, 0x8111))
    $fileExplorerCn = -join ([char[]]@(0x6587, 0x4ef6, 0x8d44, 0x6e90, 0x7ba1, 0x7406, 0x5668))
    if ($Pattern -match 'This PC|File Explorer|D:' -and ($Title.Contains($thisPcCn) -or $Title.Contains($fileExplorerCn))) {
        return $true
    }
    return $false
}

function Get-TargetRectArgs($Rect) {
    @(
        '--target-rect-left', "$([int]$Rect.left)",
        '--target-rect-top', "$([int]$Rect.top)",
        '--target-rect-right', "$([int]$Rect.right)",
        '--target-rect-bottom', "$([int]$Rect.bottom)"
    )
}

function Get-WindowByTitlePattern($Ctx, [string]$Pattern, [int]$TimeoutSeconds, [string]$Step) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $res = Invoke-WinAgentRaw $Ctx "$Step-windows" @('windows') -AllowFailure
        $windows = New-Object System.Collections.Generic.List[object]
        if ($res.Json -and $res.Json.windows) {
            foreach ($candidateWindow in @($res.Json.windows)) { $windows.Add($candidateWindow) | Out-Null }
        }
        if ($res.Json -and $res.Json.data -and $res.Json.data.windows) {
            foreach ($candidateWindow in @($res.Json.data.windows)) { $windows.Add($candidateWindow) | Out-Null }
        }
        foreach ($w in $windows) {
            $title = [string]$w.title
            if ((Test-WindowTitleMatch $title $Pattern) -and (Test-Rect $w.rect)) {
                Add-Preliminary $Ctx 'window_candidate_from_windows' @{
                    step = $Step
                    pattern = $Pattern
                    title = $title
                    hwnd = $w.hwnd
                    rect = $w.rect
                }
                return $w
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Get-ActiveRaw($Ctx, [string]$Step) {
    Invoke-WinAgentRaw $Ctx $Step @('active-window') -AllowFailure
}

function Get-MouseRaw($Ctx, [string]$Step) {
    Invoke-WinAgentRaw $Ctx $Step @('mouse-position') -AllowFailure
}

function Invoke-ObserveRaw($Ctx, [string]$Title, [string]$Step, [int]$MaxElements = 500) {
    Invoke-WinAgentRaw $Ctx $Step @('observe', '--title', $Title, '--screenshot', 'false', '--uia', 'true', '--max-elements', "$MaxElements") -AllowFailure
}

function Get-SelectedCandidateFromAdaptiveLocate($Ctx, [string]$Title, [string]$Target, [string]$Role, [string]$Kind, [string]$Step, [string]$Process = '') {
    $locateArgs = @('adaptive-locate', '--target', $Target, '--target-kind', $Kind, '--role', $Role, '--title', $Title)
    if (-not [string]::IsNullOrWhiteSpace($Process)) { $locateArgs += @('--process', $Process) }
    $locate = Invoke-WinAgentRaw $Ctx "$Step-adaptive-locate" $locateArgs -AllowFailure
    if ($locate.Json -and $locate.Json.ok -and $locate.Json.data -and $locate.Json.data.ok -and (Test-Rect $locate.Json.data.selected_candidate.rect)) {
        Add-Preliminary $Ctx 'locator_candidate_from_adaptive_locate' @{
            step = $Step
            target = $Target
            role = $Role
            selected_candidate = $locate.Json.data.selected_candidate
            command_sequence = $Ctx.Sequence
        }
        return $locate.Json.data.selected_candidate
    }
    return $null
}

function Get-ObservedCandidate($Ctx, [string]$Title, [string]$Target, [string]$ControlTypePattern, [string]$Step, $ViewportRect = $null) {
    $observe = Invoke-ObserveRaw $Ctx $Title "$Step-observe" 700
    if (-not ($observe.Json -and $observe.Json.ok -and $observe.Json.data.uia.elements)) { return $null }
    $matches = @()
    foreach ($el in @($observe.Json.data.uia.elements)) {
        if (-not (Test-Rect $el.rect)) { continue }
        if ([bool]$el.is_offscreen) { continue }
        $name = [string]$el.name
        $type = [string]$el.control_type
        if ($name -ne $Target) { continue }
        if ($type -notmatch $ControlTypePattern) { continue }
        if ($ViewportRect) {
            if ([int]$el.rect.left -lt [int]$ViewportRect.left -or [int]$el.rect.right -gt [int]$ViewportRect.right) { continue }
            if ([int]$el.rect.top -lt [int]$ViewportRect.top -or [int]$el.rect.bottom -gt [int]$ViewportRect.bottom) { continue }
        }
        $matches += $el
    }
    if ($matches.Count -lt 1) { return $null }
    $selected = @($matches | Sort-Object @{ Expression = { $_.rect.top } }, @{ Expression = { $_.rect.left } } | Select-Object -First 1)[0]
    Add-Preliminary $Ctx 'locator_candidate_from_observe' @{
        step = $Step
        target = $Target
        control_type_pattern = $ControlTypePattern
        selected_candidate = $selected
        command_sequence = $Ctx.Sequence
    }
    [pscustomobject]@{
        candidate_id = "observe:${Step}:$Target"
        matched_name = $selected.name
        matched_text = $selected.name
        role = $selected.control_type
        source = 'winagent_observe_uia'
        rect = $selected.rect
        center_x = [int](($selected.rect.left + $selected.rect.right) / 2)
        center_y = [int](($selected.rect.top + $selected.rect.bottom) / 2)
        confidence = 0.91
        raw = $selected
    }
}

function Get-BrowserViewportRect($WindowRect) {
    if (-not (Test-Rect $WindowRect)) { return $null }
    $height = [int]($WindowRect.bottom - $WindowRect.top)
    $toolbar = [Math]::Min(140, [Math]::Max(88, [int]($height * 0.11)))
    [pscustomobject]@{
        left = [int]($WindowRect.left + 8)
        top = [int]($WindowRect.top + $toolbar)
        right = [int]($WindowRect.right - 8)
        bottom = [int]($WindowRect.bottom - 8)
        source = 'derived_from_current_browser_window_rect'
    }
}

function Get-DeterministicMockCandidate($Ctx, [string]$Target, [string]$Role, $ViewportRect, [string]$Step) {
    if (-not (Test-Rect $ViewportRect)) { return $null }
    $width = [int]($ViewportRect.right - $ViewportRect.left)
    $top = [int]$ViewportRect.top
    $left = [int]$ViewportRect.left
    $right = [int]$ViewportRect.right
    $rect = $null
    $formLeft = $left + [Math]::Min(56, [Math]::Max(48, [int]($width * 0.06)))
    $fieldRight = [Math]::Min($formLeft + 680, $right - 48)
    if ($Target -eq 'Recipient') {
        $rect = [pscustomobject]@{ left = $formLeft; top = $top + 121; right = $fieldRight; bottom = $top + 162 }
    } elseif ($Target -eq 'Subject') {
        $rect = [pscustomobject]@{ left = $formLeft; top = $top + 202; right = $fieldRight; bottom = $top + 243 }
    } elseif ($Target -eq 'Body') {
        $rect = [pscustomobject]@{ left = $formLeft; top = $top + 282; right = $fieldRight; bottom = $top + 419 }
    } elseif ($Target -eq 'Send') {
        $rect = [pscustomobject]@{ left = $formLeft; top = $top + 438; right = $formLeft + 86; bottom = $top + 479 }
    }
    if (-not (Test-Rect $rect)) { return $null }
    $center = Get-RectCenter $rect
    Add-Preliminary $Ctx 'heuristic_locator_derived' @{
        step = $Step
        target = $Target
        role = $Role
        viewport_rect = $ViewportRect
        selected_rect = $rect
        source = 'deterministic_local_mock_geometry_after_page_title_verified'
    }
    [pscustomobject]@{
        candidate_id = "deterministic-mock:$Target"
        matched_name = $Target
        matched_text = $Target
        role = $Role
        source = 'deterministic_mock_geometry'
        rect = $rect
        center_x = $center.X
        center_y = $center.Y
        confidence = 0.76
    }
}

function Find-BrowserFieldCandidate($Ctx, [string]$Title, [string]$Target, [string]$Kind, [string]$Step, $WindowRect) {
    $role = if ($Kind -eq 'button') { 'Button' } else { 'Edit' }
    $targetKind = if ($Kind -eq 'button') { 'browser_button' } else { 'browser_field' }
    $candidate = Get-SelectedCandidateFromAdaptiveLocate $Ctx $Title $Target $role $targetKind "$Step-$Target" ''
    if ($candidate) { return $candidate }

    $viewport = Get-BrowserViewportRect $WindowRect
    $pattern = if ($Kind -eq 'button') { 'Button' } else { 'Edit|Document' }
    $candidate = Get-ObservedCandidate $Ctx $Title $Target $pattern "$Step-$Target" $viewport
    if ($candidate) { return $candidate }

    return Get-DeterministicMockCandidate $Ctx $Target $role $viewport "$Step-$Target"
}

function Find-ExplorerItemCandidate($Ctx, [string]$Title, [string]$Target, [string]$Step) {
    for ($attempt = 0; $attempt -le 6; $attempt++) {
        $candidate = Get-SelectedCandidateFromAdaptiveLocate $Ctx $Title $Target 'ListItem' 'explorer_item' $Step 'explorer.exe'
        if ($candidate) { return $candidate }
        $candidate = Get-ObservedCandidate $Ctx $Title $Target 'ListItem|DataItem' $Step
        if ($candidate) { return $candidate }
        if ($attempt -lt 6) {
            Add-Preliminary $Ctx 'adaptive_relocate_retry' @{
                step = $Step
                target = $Target
                retry_reason = 'explorer_item_not_visible'
                retry_count = $attempt + 1
                method = 'desktop-press PAGEDOWN then re-observe'
            }
            Invoke-WinAgentRaw $Ctx "$Step-page-down-$($attempt + 1)" @('desktop-press', '--key', 'PAGEDOWN', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
            Start-Sleep -Milliseconds 600
        }
    }
    return $null
}

function Save-WindowScreenshot($Ctx, [string]$Title, [string]$Name) {
    $bmp = Join-Path $Ctx.Screenshots "$Name.bmp"
    Invoke-WinAgentRaw $Ctx "$Name-screenshot" @('screenshot', '--title', $Title, '--out', $bmp) -AllowFailure | Out-Null
    return $bmp
}

function New-OverlayFromScreenshot([string]$ScreenshotPath, [string]$OverlayPath, $WindowRect, $TargetRect, [int]$CursorX, [int]$CursorY, [string]$Label) {
    if (-not (Test-Path -LiteralPath $ScreenshotPath)) { return $false }
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($ScreenshotPath)
    $bmp = New-Object System.Drawing.Bitmap $img
    $img.Dispose()
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Lime), 4
    $cursorPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 0, 0, 0))
    $font = New-Object System.Drawing.Font 'Consolas', 12
    $ox = [int]$WindowRect.left
    $oy = [int]$WindowRect.top
    $x = [int]$TargetRect.left - $ox
    $y = [int]$TargetRect.top - $oy
    $w = [int]$TargetRect.right - [int]$TargetRect.left
    $h = [int]$TargetRect.bottom - [int]$TargetRect.top
    $g.DrawRectangle($pen, $x, $y, $w, $h)
    $cx = $CursorX - $ox
    $cy = $CursorY - $oy
    $g.DrawEllipse($cursorPen, $cx - 6, $cy - 6, 12, 12)
    $g.DrawLine($cursorPen, $cx - 10, $cy, $cx + 10, $cy)
    $g.DrawLine($cursorPen, $cx, $cy - 10, $cx, $cy + 10)
    $g.FillRectangle($bgBrush, 8, 8, [Math]::Min($bmp.Width - 16, 980), 30)
    $g.DrawString($Label, $font, $textBrush, 14, 13)
    $bmp.Save($OverlayPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $font.Dispose()
    $pen.Dispose()
    $cursorPen.Dispose()
    $textBrush.Dispose()
    $bgBrush.Dispose()
    $g.Dispose()
    $bmp.Dispose()
    return $true
}

function Invoke-TargetMouseAction($Ctx, [string]$Step, [string]$Title, $Candidate, [ValidateSet('click','double-click')]$Action, [string]$OverlayName = '') {
    if (-not $Candidate -or -not (Test-Rect $Candidate.rect)) {
        Add-Preliminary $Ctx 'target_rect_missing' @{ step = $Step; title = $Title }
        return $false
    }
    $rect = $Candidate.rect
    $center = Get-RectCenter $rect
    $rectArgs = Get-TargetRectArgs $rect
    $moveResult = Join-Path $Ctx.ResultJson "$Step-move-human-action-result.json"
    $clickResult = Join-Path $Ctx.ResultJson "$Step-$Action-human-action-result.json"
    $baseArgs = @('--screen-x', "$($center.X)", '--screen-y', "$($center.Y)", '--permission-mode', $PermissionMode, '--humanmode', 'true', '--target-description', "$Step $($Candidate.matched_name)", '--coordinate-source', "locator_derived:$($Candidate.source)") + $rectArgs
    Invoke-WinAgentRaw $Ctx "$Step-move" (@('desktop-move') + $baseArgs + @('--result-json', $moveResult)) -AllowFailure | Out-Null
    $mouse = Get-MouseRaw $Ctx "$Step-cursor-before-click"
    $cursorX = if ($mouse.Json.ok) { [int]$mouse.Json.data.screen_x } else { $center.X }
    $cursorY = if ($mouse.Json.ok) { [int]$mouse.Json.data.screen_y } else { $center.Y }
    if (-not [string]::IsNullOrWhiteSpace($OverlayName)) {
        $shot = Save-WindowScreenshot $Ctx $Title "$Step-before-double-click"
        $overlayPath = Join-Path $Ctx.Overlays $OverlayName
        [void](New-OverlayFromScreenshot $shot $overlayPath (Get-ActiveWindowRect $Ctx "$Step-active-for-overlay") $rect $cursorX $cursorY "$Step target=$($Candidate.matched_name)")
    }
    $cmd = if ($Action -eq 'double-click') { 'desktop-double-click' } else { 'desktop-click' }
    Invoke-WinAgentRaw $Ctx "$Step-$Action" (@($cmd) + $baseArgs + @('--result-json', $clickResult)) -AllowFailure | Out-Null
    return $true
}

function Get-ActiveWindowRect($Ctx, [string]$Step) {
    $active = Get-ActiveRaw $Ctx $Step
    if ($active.Json.ok -and $active.Json.data.rect) { return $active.Json.data.rect }
    return [pscustomobject]@{ left = 0; top = 0; right = 1; bottom = 1 }
}

function Write-TestHtmlFiles {
    Ensure-Dir $MockDir
    @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>DesktopVisual Local Mail Mock</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 48px; max-width: 760px; }
    h1 { margin: 0 0 12px 0; font-size: 28px; }
    p { margin: 0 0 20px 0; color: #333; }
    label { display: block; margin-top: 16px; font-weight: 700; }
    input, textarea { display: block; width: 680px; padding: 9px; margin-top: 5px; font-size: 16px; box-sizing: border-box; }
    textarea { height: 136px; resize: none; }
    button { margin-top: 20px; padding: 10px 20px; font-size: 16px; border: 1px solid #555; background: #f2f2f2; }
    #status { margin-top: 18px; padding: 10px; border: 1px solid #999; min-height: 24px; }
  </style>
</head>
<body>
  <h1>DesktopVisual Local Mail Mock</h1>
  <p>This page is a local mock. It does not send real email.</p>
  <label for="recipient">Recipient</label>
  <input aria-label="Recipient" id="recipient" name="recipient" autocomplete="off">
  <label for="subject">Subject</label>
  <input aria-label="Subject" id="subject" name="subject" autocomplete="off">
  <label for="body">Body</label>
  <textarea aria-label="Body" id="body" name="body"></textarea>
  <button aria-label="Send" id="sendButton" type="button">Send</button>
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
'@ | Set-Content -LiteralPath $LocalFileHtml -Encoding UTF8
    Copy-Item -LiteralPath $LocalFileHtml -Destination $LocalhostHtml -Force
}

function Get-EdgeBrowserWindow($Ctx, [int]$TimeoutSeconds = 10) {
    Get-WindowByTitlePattern $Ctx 'DesktopVisual Local Mail Mock.*Microsoft.*Edge|DesktopVisual Localhost Mail Mock.*Microsoft.*Edge|desktopvisual_mail_mock.*Microsoft.*Edge|mail_mock.*Microsoft.*Edge|Microsoft.*Edge|Edge' $TimeoutSeconds 'browser-edge'
}

function Get-ChromeBrowserWindow($Ctx, [int]$TimeoutSeconds = 10) {
    Get-WindowByTitlePattern $Ctx 'DesktopVisual Local Mail Mock|DesktopVisual Localhost Mail Mock|desktopvisual_mail_mock|mail_mock|Google Chrome|Chrome' $TimeoutSeconds 'browser-chrome'
}

function Get-BrowserWindow($Ctx, [int]$TimeoutSeconds = 10) {
    $edge = Get-EdgeBrowserWindow $Ctx ([Math]::Max(1, [int]($TimeoutSeconds / 2)))
    if ($edge) { return $edge }
    Get-ChromeBrowserWindow $Ctx ([Math]::Max(1, $TimeoutSeconds))
}

function Open-BrowserViaRunDialog($Ctx, [string]$Step) {
    foreach ($browserCommand in @('msedge.exe', 'chrome.exe')) {
        Add-Preliminary $Ctx 'browser_bootstrap_via_real_ui' @{
            step = $Step
            command_text = $browserCommand
            method = 'WIN+R addressable app name typed through real HumanMode keyboard'
        }
        Invoke-WinAgentRaw $Ctx "$Step-run-dialog" @('desktop-hotkey', '--keys', 'WIN+R', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        Start-Sleep -Milliseconds 600
        Invoke-WinAgentRaw $Ctx "$Step-run-dialog-type-$($browserCommand.Replace('.','-'))" @('desktop-type', '--text', $browserCommand, '--type-mode', 'demo-human', '--char-delay-ms', '25', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        Invoke-WinAgentRaw $Ctx "$Step-run-dialog-enter-$($browserCommand.Replace('.','-'))" @('desktop-press', '--key', 'ENTER', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        if ($browserCommand -eq 'msedge.exe') {
            $browser = Get-EdgeBrowserWindow $Ctx 10
        } else {
            $browser = Get-ChromeBrowserWindow $Ctx 10
        }
        if ($browser) { return $browser }
    }
    return $null
}

function Get-AddressBarCandidate($Ctx, [string]$Title, [string]$Step) {
    $observe = Invoke-ObserveRaw $Ctx $Title "$Step-addressbar-observe" 700
    if (-not ($observe.Json -and $observe.Json.ok -and $observe.Json.data.uia.elements)) { return $null }
    $edits = @($observe.Json.data.uia.elements | Where-Object {
        $_.control_type -eq 'Edit' -and
        (Test-Rect $_.rect) -and
        -not [bool]$_.is_offscreen
    })
    if ($edits.Count -eq 0) { return $null }
    $candidate = @($edits | Sort-Object @{ Expression = { $_.rect.top } }, @{ Expression = { -([int]$_.rect.right - [int]$_.rect.left) } } | Select-Object -First 1)[0]
    [pscustomobject]@{
        matched_name = if ($candidate.name) { $candidate.name } else { 'browser address bar' }
        source = 'winagent_observe_uia_address_bar'
        rect = $candidate.rect
        center_x = [int](($candidate.rect.left + $candidate.rect.right) / 2)
        center_y = [int](($candidate.rect.top + $candidate.rect.bottom) / 2)
        raw = $candidate
    }
}

function Test-BrowserTargetPageLoaded($Ctx, [string]$ExpectedPattern, [string]$Step) {
    $browser = Get-WindowByTitlePattern $Ctx $ExpectedPattern 4 "$Step-target-window"
    if (-not $browser) {
        $browser = Get-BrowserWindow $Ctx 2
    }
    if (-not $browser) {
        Add-Preliminary $Ctx 'browser_target_page_not_found' @{
            step = $Step
            expected_pattern = $ExpectedPattern
            reason = 'browser window missing'
        }
        return [pscustomobject]@{ ok = $false; browser = $null; title = ''; evidence_text = '' }
    }

    $active = Get-ActiveRaw $Ctx "$Step-active-window"
    $observe = Invoke-ObserveRaw $Ctx $browser.title "$Step-observe-target-page" 700
    $text = Invoke-WinAgentRaw $Ctx "$Step-read-window-text" @('read-window-text', '--title', $browser.title) -AllowFailure
    Save-WindowScreenshot $Ctx $browser.title "$Step-target-page" | Out-Null

    $joined = @(
        [string]$browser.title,
        [string]$active.Stdout,
        [string]$observe.Stdout,
        [string]$text.Stdout
    ) -join "`n"
    $hasTarget = $joined -match $ExpectedPattern
    $hasLoadError = $joined -match 'ERR_|This site can''t be reached|file wasn''t available|404|not found|cannot find'

    Add-Preliminary $Ctx 'browser_target_page_observed' @{
        step = $Step
        expected_pattern = $ExpectedPattern
        title = [string]$browser.title
        matched_expected = [bool]$hasTarget
        load_error_detected = [bool]$hasLoadError
    }

    [pscustomobject]@{
        ok = ($hasTarget -and -not $hasLoadError)
        browser = $browser
        title = [string]$browser.title
        evidence_text = $joined
    }
}

function Open-UrlThroughAddressBar($Ctx, [string]$Url, [string]$Step, [string]$ExpectedPattern = 'DesktopVisual Local Mail Mock') {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $browser = Get-EdgeBrowserWindow $Ctx 4
        if (-not $browser) {
            $browser = Open-BrowserViaRunDialog $Ctx "$Step-open-browser-attempt-$attempt"
            if (-not $browser) {
                $browser = Get-ChromeBrowserWindow $Ctx 4
                if (-not $browser) {
                    Add-Preliminary $Ctx 'browser_window_missing' @{ step = $Step; url = $Url; attempt = $attempt }
                    return $false
                }
            }
        }
        $address = Get-AddressBarCandidate $Ctx $browser.title "$Step-attempt-$attempt"
        if (-not $address) {
            Add-Preliminary $Ctx 'address_bar_missing' @{ step = $Step; title = $browser.title; url = $Url; attempt = $attempt }
            Invoke-WinAgentRaw $Ctx "$Step-attempt-$attempt-focus-addressbar-hotkey" @('desktop-hotkey', '--keys', 'CTRL+L', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        } else {
            Invoke-TargetMouseAction $Ctx "$Step-attempt-$attempt-addressbar" $browser.title $address 'click' | Out-Null
        }
        Invoke-WinAgentRaw $Ctx "$Step-attempt-$attempt-addressbar-select" @('desktop-hotkey', '--keys', 'CTRL+A', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        Invoke-WinAgentRaw $Ctx "$Step-attempt-$attempt-url-type" @('desktop-type', '--text', $Url, '--type-mode', 'demo-human', '--char-delay-ms', '75', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        Invoke-WinAgentRaw $Ctx "$Step-attempt-$attempt-url-enter" @('desktop-press', '--key', 'ENTER', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        Start-Sleep -Seconds 4
        Save-WindowScreenshot $Ctx $browser.title "$Step-attempt-$attempt-after-url-enter" | Out-Null

        $loaded = Test-BrowserTargetPageLoaded $Ctx $ExpectedPattern "$Step-attempt-$attempt"
        if ($loaded.ok) {
            Add-Preliminary $Ctx 'browser_url_open_unverified_complete' @{
                step = $Step
                url = $Url
                attempt = $attempt
                title = $loaded.title
            }
            return $true
        }

        Add-Preliminary $Ctx 'adaptive_relocate_retry' @{
            step = $Step
            url = $Url
            retry_reason = 'target_page_not_verified_after_address_bar_input'
            retry_count = $attempt
            observed_title = $loaded.title
            method = 'reselect address bar, retype URL with slower HumanMode pacing, re-observe'
        }
    }
    Add-Preliminary $Ctx 'browser_target_page_not_found' @{
        step = $Step
        url = $Url
        expected_pattern = $ExpectedPattern
        reason = 'target page not verified after address bar retry budget'
    }
    return $false
}

function Fill-And-Send-MailMock($Ctx, [string]$Title, [string]$StepPrefix) {
    $active = Get-ActiveRaw $Ctx "$StepPrefix-active-before-form"
    $windowRect = if ($active.Json.ok -and $active.Json.data.rect) { $active.Json.data.rect } else { (Get-BrowserWindow $Ctx 2).rect }
    $fields = @(
        @{ Name = 'Recipient'; Value = 'xiaoming'; Kind = 'field'; Failure = 'recipient' },
        @{ Name = 'Subject'; Value = 'desktopvisual test'; Kind = 'field'; Failure = 'subject' },
        @{ Name = 'Body'; Value = 'this is a testing message'; Kind = 'field'; Failure = 'body' }
    )
    foreach ($field in $fields) {
        $candidate = Find-BrowserFieldCandidate $Ctx $Title $field.Name $field.Kind "$StepPrefix-$($field.Name)" $windowRect
        if (-not $candidate) {
            Add-Preliminary $Ctx 'field_locator_failure' @{ step = $StepPrefix; field = $field.Name; failure_code = "FAIL_BROWSER_FIELD_LOCATOR_$($field.Failure.ToUpperInvariant())" }
            return $false
        }
        Invoke-TargetMouseAction $Ctx "$StepPrefix-$($field.Name)-click" $Title $candidate 'click' | Out-Null
        Invoke-WinAgentRaw $Ctx "$StepPrefix-$($field.Name)-type" @('desktop-type', '--text', $field.Value, '--type-mode', 'demo-human', '--char-delay-ms', '25', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
        Invoke-ObserveRaw $Ctx $Title "$StepPrefix-$($field.Name)-verify-observe" 700 | Out-Null
        Invoke-WinAgentRaw $Ctx "$StepPrefix-$($field.Name)-verify-text" @('read-window-text', '--title', $Title) -AllowFailure | Out-Null
    }
    Save-WindowScreenshot $Ctx $Title "$StepPrefix-after-fill" | Out-Null
    $send = Find-BrowserFieldCandidate $Ctx $Title 'Send' 'button' "$StepPrefix-Send" $windowRect
    if (-not $send) {
        Add-Preliminary $Ctx 'send_button_locator_failure' @{ step = $StepPrefix; failure_code = 'FAIL_BROWSER_BUTTON_LOCATOR_SEND' }
        return $false
    }
    Invoke-TargetMouseAction $Ctx "$StepPrefix-Send-click" $Title $send 'click' | Out-Null
    Start-Sleep -Seconds 1
    Save-WindowScreenshot $Ctx $Title "$StepPrefix-after-send" | Out-Null
    Invoke-ObserveRaw $Ctx $Title "$StepPrefix-after-send-observe" 700 | Out-Null
    Invoke-WinAgentRaw $Ctx "$StepPrefix-after-send-text" @('read-window-text', '--title', $Title) -AllowFailure | Out-Null
    Add-Preliminary $Ctx 'form_round_unverified_complete' @{ step = $StepPrefix; title = $Title }
    return $true
}

function Invoke-WindowRelocation($Ctx, [string]$Title, [string]$Step) {
    $before = Get-ActiveRaw $Ctx "$Step-before-window-rect"
    Invoke-WinAgentRaw $Ctx "$Step-window-hotkey-left" @('desktop-hotkey', '--keys', 'WIN+LEFT', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
    Start-Sleep -Seconds 1
    $after = Get-ActiveRaw $Ctx "$Step-after-window-rect"
    Add-Preliminary $Ctx 'window_relocation_attempt' @{
        step = $Step
        before_window_rect = if ($before.Json.ok) { $before.Json.data.rect } else { $null }
        after_window_rect = if ($after.Json.ok) { $after.Json.data.rect } else { $null }
        method = 'desktop-hotkey WIN+LEFT'
    }
}

function Case-D {
    $ctx = New-RawCase 'explorer_open_local_html_via_humanmode_flow'
    Add-Preliminary $ctx 'case_started' @{ case_id = $ctx.CaseId; output = 'raw evidence only' }
    Invoke-WinAgentRaw $ctx 'show-desktop' @('desktop-hotkey', '--keys', 'WIN+D', '--permission-mode', $PermissionMode) -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 800

    $shortcut = Get-SelectedCandidateFromAdaptiveLocate $ctx 'Program Manager' 'DesktopVisual This PC Test' 'ListItem' 'desktop_item' 'step_this_pc' 'explorer.exe'
    if (-not $shortcut) {
        $shortcut = Get-ObservedCandidate $ctx 'Program Manager' 'DesktopVisual This PC Test' 'ListItem' 'step_this_pc'
    }
    if (-not $shortcut) {
        Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'DesktopVisual This PC Test shortcut not found' }
        return
    }
    Invoke-TargetMouseAction $ctx 'step_this_pc' 'Program Manager' $shortcut 'double-click' 'step_this_pc_before_double_click.png' | Out-Null
    Start-Sleep -Seconds 2
    $explorer = Get-WindowByTitlePattern $ctx 'This PC|File Explorer|Data \(D:\)|D:' 12 'case-d-wait-explorer'
    if (-not $explorer) {
        Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'Explorer did not open after This PC shortcut double-click' }
        return
    }

    $steps = @(
        @{ Key = 'd_drive'; Target = 'D:'; Overlay = 'step_d_drive_before_double_click.png'; Expected = 'Data \(D:\)|D:' },
        @{ Key = 'testrepo'; Target = 'testrepo'; Overlay = 'step_testrepo_before_double_click.png'; Expected = 'testrepo' },
        @{ Key = 'testwindow'; Target = 'testwindow'; Overlay = 'step_testwindow_before_double_click.png'; Expected = 'testwindow' },
        @{ Key = 'html'; Target = 'desktopvisual_mail_mock.html'; Overlay = 'step_html_before_double_click.png'; Expected = 'DesktopVisual Local Mail Mock|desktopvisual_mail_mock|Chrome|Edge' }
    )

    foreach ($step in $steps) {
        $active = Get-ActiveRaw $ctx "step_$($step.Key)-active-before"
        $title = if ($active.Json.ok -and $active.Json.data.title) { [string]$active.Json.data.title } else { [string]$explorer.title }
        $candidate = Find-ExplorerItemCandidate $ctx $title $step.Target "step_$($step.Key)"
        if (-not $candidate) {
            Add-Preliminary $ctx 'case_unverified_failure' @{ reason = "Explorer target not found"; target = $step.Target; title = $title }
            return
        }
        Invoke-TargetMouseAction $ctx "step_$($step.Key)" $title $candidate 'double-click' $step.Overlay | Out-Null
        Start-Sleep -Seconds 2
        Get-WindowByTitlePattern $ctx $step.Expected 8 "step_$($step.Key)-verify-window" | Out-Null
        Add-Preliminary $ctx 'case_d_path_step_unverified' @{ step = $step.Key; target = $step.Target; expected = $step.Expected }
    }
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId }
}

function Case-E {
    $ctx = New-RawCase 'local_mail_mock_browser_fill_and_send_humanmode_flow'
    Add-Preliminary $ctx 'case_started' @{ case_id = $ctx.CaseId; rounds_requested = $Rounds; output = 'raw evidence only' }
    $url = 'file:///D:/testrepo/testwindow/desktopvisual_mail_mock.html'
    for ($round = 1; $round -le $Rounds; $round++) {
        $opened = Open-UrlThroughAddressBar $ctx $url "case-e-round-$round-open-file-url"
        if (-not $opened) {
            Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'could not open file URL through browser address bar'; round = $round }
            return
        }
        $loaded = Test-BrowserTargetPageLoaded $ctx 'DesktopVisual Local Mail Mock' "case-e-round-$round-page-confirmed"
        if (-not $loaded.ok) {
            Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'target browser page not verified after file URL'; round = $round; observed_title = $loaded.title }
            return
        }
        $browser = $loaded.browser
        if ($round -eq 1) {
            Invoke-WindowRelocation $ctx $browser.title "case-e-round-$round-relocate"
            $loaded = Test-BrowserTargetPageLoaded $ctx 'DesktopVisual Local Mail Mock' "case-e-round-$round-page-confirmed-after-relocate"
            if (-not $loaded.ok) {
                Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'target browser page not verified after window relocation'; round = $round; observed_title = $loaded.title }
                return
            }
            $browser = $loaded.browser
        }
        Save-WindowScreenshot $ctx $browser.title "case-e-round-$round-before-fill" | Out-Null
        $ok = Fill-And-Send-MailMock $ctx $browser.title "case-e-round-$round"
        if (-not $ok) { return }
        Add-Preliminary $ctx 'case_e_round_unverified_complete' @{ round = $round; title = $browser.title }
    }
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; rounds = $Rounds }
}

function Start-LocalhostServer($Ctx, [int]$Port) {
    $job = Start-Job -ScriptBlock {
        param($PortArg, $HtmlPath)
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$PortArg/")
        $listener.Start()
        try {
            while ($listener.IsListening) {
                $context = $listener.GetContext()
                $path = $context.Request.Url.AbsolutePath
                if ($path -eq '/' -or $path -eq '/mail_mock.html') {
                    $bytes = [System.IO.File]::ReadAllBytes($HtmlPath)
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = 'text/html; charset=utf-8'
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $context.Response.StatusCode = 404
                }
                $context.Response.OutputStream.Close()
            }
        } finally {
            if ($listener.IsListening) { $listener.Stop() }
            $listener.Close()
        }
    } -ArgumentList $Port, $LocalhostHtml
    Start-Sleep -Seconds 2
    Add-Preliminary $Ctx 'localhost_server_started' @{
        port = $Port
        bind = '127.0.0.1'
        job_id = $job.Id
        directory = $MockDir
        command = 'System.Net.HttpListener prefix http://127.0.0.1:<port>/'
    }
    return $job
}

function Case-F {
    $ctx = New-RawCase 'localhost_form_fill_submit_humanmode_flow'
    Add-Preliminary $ctx 'case_started' @{ case_id = $ctx.CaseId; output = 'raw evidence only' }
    $port = 18091
    $job = Start-LocalhostServer $ctx $port
    if (-not $job) { return }
    try {
        $url = "http://127.0.0.1:$port/mail_mock.html"
        $opened = Open-UrlThroughAddressBar $ctx $url 'case-f-open-localhost-url'
        if (-not $opened) {
            Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'could not open localhost URL through browser address bar'; port = $port }
            return
        }
        $loaded = Test-BrowserTargetPageLoaded $ctx 'DesktopVisual Local Mail Mock' 'case-f-page-confirmed'
        if (-not $loaded.ok) {
            Add-Preliminary $ctx 'case_unverified_failure' @{ reason = 'localhost target browser page not verified'; port = $port; observed_title = $loaded.title }
            return
        }
        $browser = $loaded.browser
        Save-WindowScreenshot $ctx $browser.title 'case-f-before-fill' | Out-Null
        $ok = Fill-And-Send-MailMock $ctx $browser.title 'case-f'
        if (-not $ok) { return }
        Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; port = $port; bind = '127.0.0.1' }
    } finally {
        Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        Add-Preliminary $ctx 'localhost_server_stopped' @{ port = $port; bind = '127.0.0.1' }
    }
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $RawRoot
Ensure-Dir $RawCasesRoot
git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_initial.txt') -Encoding UTF8

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found: $WinAgent"
}

Write-TestHtmlFiles

$requiredInputs = @(
    'AGENTS.md','VERSION','README.md','CHANGELOG.md','COMMAND_PROTOCOL.md',
    'config\safety_manifest.json','config\safety.conf','docs\ROADMAP.md',
    'docs\TASK_RUNTIME.md','docs\BENCHMARKS.md','docs\KNOWN_LIMITATIONS.md',
    'docs\SAFETY_MANIFEST.md','docs\PERCEPTION.md','docs\APP_PROFILES.md',
    'src\winagent\AdaptiveHumanMode.h','src\winagent\AdaptiveHumanMode.cpp',
    'src\winagent\InputController.h','src\winagent\InputController.cpp',
    'src\winagent\WinAgent.cpp','src\winagent\TaskRunner.cpp','src\winagent\TaskSession.cpp',
    'v5_10_0_adaptive_humanmode_loop_test.ps1','v5_9_permission_reset_selftest.ps1',
    'v5_9_0_e_humanmode_motion_pacing_test.ps1',
    'artifacts\dev5.10.0_adaptive_humanmode_loop\adaptive_loop_design_report.md',
    'artifacts\invalidation_index.md',
    'artifacts\invalidated\dev5.10.1_adaptive_cases_INVALIDATED\INVALIDATED_DO_NOT_USE.md',
    'artifacts\invalidated\dev5.10.2_final_pre_v6_gate_INVALIDATED\INVALIDATED_DO_NOT_USE.md'
)
$readManifest = foreach ($item in $requiredInputs) {
    $path = Join-Path $Root $item
    [pscustomobject]@{
        path = $item
        exists = (Test-Path -LiteralPath $path)
        length = if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).Length } else { $null }
    }
}
$readManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $RawRoot 'required_file_read_manifest.json') -Encoding UTF8

Case-D
Case-E
Case-F

[pscustomobject]@{
    schema_version = 'v5.10.1.runner.raw'
    version = '5.10.1'
    generated_at = (Get-Date).ToString('o')
    artifact_root = $ArtifactRoot
    raw_root = $RawRoot
    runner_role = 'collect_raw_evidence_only'
    pass_or_fail_decided_by = 'v5_10_1_real_ui_evidence_verifier.ps1'
    rounds_requested = $Rounds
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $RawRoot 'runner_manifest.json') -Encoding UTF8

git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_after_runner.txt') -Encoding UTF8

Write-Host 'v5.10.1 real UI adaptive cases raw runner complete.'
Write-Host "Raw artifacts: $RawRoot"
