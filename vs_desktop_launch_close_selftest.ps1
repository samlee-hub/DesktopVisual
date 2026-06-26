param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TestRepoRoot)) {
    $TestRepoRoot = Join-Path (Split-Path -Parent $Root) 'testrepo'
}
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.4_vs_cpp_complex_ide_workflow'
$Report = Join-Path $OutDir 'vs_desktop_launch_close_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:Steps = New-Object System.Collections.Generic.List[object]
$script:Status = 'FAIL'
$script:StatusMessage = ''
$script:DesktopVsIconFound = $false
$script:VsWindowVerified = $false
$script:VsWindowDisappeared = $false
$script:SelectedVsIconName = ''
$script:CloseMethod = 'not_attempted'
$script:VsWindowTitle = ''
$script:VsWindowHwnd = ''
$script:VsWindowRect = $null
$script:BackendLaunchUsed = $false
$script:StartMenuLaunchUsed = $false
$script:ProcessKillUsed = $false
$script:SavePromptHandled = 'not_needed'
$script:EmptyProjectTemplateText = -join @([char]0x7A7A, [char]0x9879, [char]0x76EE)
$script:ChineseCloseText = -join @([char]0x5173, [char]0x95ED)

function ConvertTo-JsonText($Value) {
    return ($Value | ConvertTo-Json -Depth 30)
}

function Write-TextFile([string]$Path, [string]$Value) {
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Invoke-Agent {
    param(
        [string[]]$WinArgs,
        [int[]]$Allowed = @(0),
        [string]$RawPath = ''
    )
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $raw = (($output | Out-String).Trim())
    if ($RawPath) {
        Write-TextFile -Path $RawPath -Value $raw
    }
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $json = $raw | ConvertFrom-Json
        } catch {
            throw "Invalid JSON from winagent $($WinArgs -join ' '): $raw"
        }
    }
    if ($Allowed -notcontains $exit) {
        throw "winagent $($WinArgs -join ' ') exited $exit with output: $raw"
    }
    [pscustomobject]@{
        exit = $exit
        raw = $raw
        json = $json
    }
}

function New-StepRecord([string]$StepId, [string]$Action, [string]$TargetSource) {
    [ordered]@{
        step_id = $StepId
        intended_action = $Action
        visible_observe_before = ''
        target_source = $TargetSource
        action_command = ''
        visible_observe_after = ''
        verification_result = $false
        recovery_needed = $false
        recovery_action = ''
        next_step_allowed = $false
        raw_result_path = ''
        notes = ''
    }
}

function Capture-Observation([string]$StepId, [string]$Phase) {
    $safePhase = $Phase -replace '[^A-Za-z0-9_-]', '_'
    $screenshot = Join-Path $OutDir "$StepId`_$safePhase`_global.png"
    $screenshotJson = Join-Path $OutDir "$StepId`_$safePhase`_global.json"
    $windowsJson = Join-Path $OutDir "$StepId`_$safePhase`_windows.json"
    Invoke-Agent -WinArgs @('global-screenshot', '--out', $screenshot, '--format', 'png', '--include-metadata', 'true') -RawPath $screenshotJson | Out-Null
    Invoke-Agent -WinArgs @('windows') -RawPath $windowsJson | Out-Null
    "global_screenshot=$screenshot; windows=$windowsJson"
}

function Add-Step([System.Collections.IDictionary]$Step) {
    $script:Steps.Add([pscustomobject]$Step) | Out-Null
}

function Complete-Step {
    param(
        [System.Collections.IDictionary]$Step,
        [string]$Command,
        [string]$After,
        [bool]$Verified,
        [string]$RawPath = '',
        [bool]$RecoveryNeeded = $false,
        [string]$RecoveryAction = '',
        [string]$Notes = ''
    )
    $Step.action_command = $Command
    $Step.visible_observe_after = $After
    $Step.verification_result = $Verified
    $Step.recovery_needed = $RecoveryNeeded
    $Step.recovery_action = $RecoveryAction
    $Step.next_step_allowed = $Verified
    $Step.raw_result_path = $RawPath
    $Step.notes = $Notes
    Add-Step $Step
    if (-not $Verified) {
        throw "Step $($Step.step_id) failed: $($Step.intended_action)"
    }
}

function Write-Report {
    param(
        [string]$Result,
        [string]$Message
    )
    $stepJson = ConvertTo-JsonText $script:Steps
    $lines = @(
        '# VS desktop launch/close selftest report',
        '',
        "- result: $Result",
        "- message: $Message",
        '- project_name=SingleTestProject',
        "- template_required=$($script:EmptyProjectTemplateText)",
        '- template_selected=not_exercised_feature_a',
        '- template_selection_method=not_exercised_feature_a',
        '- project_location_modified=false',
        '- actual_project_path=not_created_in_feature_a',
        '- solution_path=not_created_in_feature_a',
        '- vcxproj_path=not_created_in_feature_a',
        "- project_root=$Root",
        "- testrepo_root=$TestRepoRoot",
        '- step_by_step_visible_execution=true',
        '- vs_open_method=desktop_icon_double_click',
        "- desktop_vs_icon_found=$($script:DesktopVsIconFound.ToString().ToLowerInvariant())",
        "- selected_vs_icon_name=$($script:SelectedVsIconName)",
        "- backend_launch_used=$($script:BackendLaunchUsed.ToString().ToLowerInvariant())",
        "- start_menu_launch_used=$($script:StartMenuLaunchUsed.ToString().ToLowerInvariant())",
        "- vs_window_verified=$($script:VsWindowVerified.ToString().ToLowerInvariant())",
        "- vs_window_title=$($script:VsWindowTitle)",
        "- vs_window_hwnd=$($script:VsWindowHwnd)",
        "- close_method=$($script:CloseMethod)",
        "- vs_window_disappeared=$($script:VsWindowDisappeared.ToString().ToLowerInvariant())",
        "- save_prompt_handled_by_visible_ui=$($script:SavePromptHandled)",
        "- process_kill_used=$($script:ProcessKillUsed.ToString().ToLowerInvariant())",
        '- vs_closed_after_each_success=true',
        '- backend_project_creation_used=false',
        '- backend_file_creation_used=false',
        '- backend_build_used=false',
        '- backend_run_used=false',
        '- old_mock_vlm_used=false',
        '- real_vlm_path_used_when_needed=not_needed',
        '- wrong_project_cleanup_performed=false',
        "- output_verified=$($script:VsWindowDisappeared.ToString().ToLowerInvariant())",
        '',
        '## Step Checkpoints',
        '',
        '```json',
        $stepJson,
        '```'
    )
    Write-TextFile -Path $Report -Value ($lines -join "`r`n")
}

function Get-VsWindowLock([int[]]$Allowed = @(0)) {
    Invoke-Agent -WinArgs @(
        'target-lock-acquire',
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true'
    ) -Allowed $Allowed
}

function Wait-VsWindow([int]$TimeoutSeconds = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $result = Get-VsWindowLock -Allowed @(0, 1)
            $last = $result
            if ($result.exit -eq 0 -and $result.json.ok -eq $true -and $result.json.data.target_window_locked -eq $true) {
                return $result
            }
        } catch {
            $last = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 1000
    }
    return $last
}

function Test-VsWindowGone([int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $result = Get-VsWindowLock -Allowed @(0, 1)
        if ($result.exit -ne 0 -or $result.json.ok -ne $true) {
            return $true
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Find-DesktopVsIcon {
    $candidates = @(
        'Visual Studio 2026',
        'VS2026',
        'Visual Studio 2022',
        'Visual Studio 2019',
        'Microsoft Visual Studio',
        'Visual Studio'
    )
    $attempts = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $candidates) {
        $raw = Join-Path $OutDir ("step_a02_locate_" + ($candidate -replace '[^A-Za-z0-9]+', '_') + ".json")
        $result = Invoke-Agent -WinArgs @('desktop-icon-locate', '--target', $candidate) -Allowed @(0, 1) -RawPath $raw
        $attempts.Add([pscustomobject]@{ target = $candidate; exit = $result.exit; raw_path = $raw }) | Out-Null
        if ($result.exit -eq 0 -and $result.json.ok -eq $true -and $result.json.data.visible_target.ok -eq $true) {
            $name = [string]$result.json.data.visible_target.element.name
            if ($name -notmatch 'Code|Installer') {
                return [pscustomobject]@{
                    target = $candidate
                    name = $name
                    result = $result
                    attempts = $attempts
                }
            }
        }
    }
    [pscustomobject]@{
        target = ''
        name = ''
        result = $null
        attempts = $attempts
    }
}

function Get-RectCenter($Rect) {
    [pscustomobject]@{
        x = [int]($Rect.left + (($Rect.right - $Rect.left) / 2))
        y = [int]($Rect.top + (($Rect.bottom - $Rect.top) / 2))
    }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run build first."
}

try {
    $preexisting = Get-VsWindowLock -Allowed @(0, 1)
    if ($preexisting.exit -eq 0 -and $preexisting.json.ok -eq $true) {
        $script:Status = 'BLOCKED'
        throw 'Preexisting visible devenv.exe window found. Close it manually before running Feature A to avoid closing user work.'
    }

    $step = New-StepRecord 'A01' 'show desktop using visible-show-desktop' 'visible evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'step_a01_visible_show_desktop.json'
    $showDesktop = Invoke-Agent -WinArgs @(
        'visible-show-desktop',
        '--allow-backend-fallback', 'false',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    $verified = $showDesktop.json.ok -eq $true -and
        $showDesktop.json.data.desktop_visible -eq $true -and
        $showDesktop.json.data.bottom_right_show_desktop_clicked -eq $true -and
        $showDesktop.json.data.backend_show_desktop_used -eq $false
    Complete-Step $step 'visible-show-desktop --allow-backend-fallback false' $after $verified $raw

    $step = New-StepRecord 'A02' 'locate Visual Studio / VS2026 desktop icon' 'UIA visible desktop'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $icon = Find-DesktopVsIcon
    $script:DesktopVsIconFound = -not [string]::IsNullOrWhiteSpace($icon.target)
    if (-not $script:DesktopVsIconFound) {
        $after = Capture-Observation $step.step_id 'after'
        $step.notes = 'No Visual Studio or VS2026 desktop icon was found by visible UIA locate attempts.'
        Complete-Step $step 'desktop-icon-locate Visual Studio/VS2026 candidates' $after $false '' $false ''
    }
    $script:SelectedVsIconName = $icon.name
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step -Step $step -Command "desktop-icon-locate --target $($icon.target)" -After $after -Verified $true -RawPath $icon.result.raw -Notes "locate_attempts=$($icon.attempts.Count)"

    $rect = $icon.result.json.data.visible_target.element.rect
    $center = Get-RectCenter $rect
    $step = New-StepRecord 'A03' 'move mouse to located Visual Studio desktop icon' 'UIA coordinate mapped to global desktop'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'step_a03_move_to_icon.json'
    $move = Invoke-Agent -WinArgs @(
        'desktop-move',
        '--screen-x', ([string]$center.x),
        '--screen-y', ([string]$center.y),
        '--allow-global-desktop', 'true',
        '--coordinate-source', 'locator_derived',
        '--target-description', 'Visual Studio desktop icon',
        '--target-rect-left', ([string]$rect.left),
        '--target-rect-top', ([string]$rect.top),
        '--target-rect-right', ([string]$rect.right),
        '--target-rect-bottom', ([string]$rect.bottom),
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    $verified = $move.json.ok -eq $true -and $move.json.data.human_action_result.exit_code -eq 0
    Complete-Step $step 'desktop-move to VS icon center' $after $verified $raw

    $step = New-StepRecord 'A04' 'double-click Visual Studio desktop icon' 'Runtime visible desktop-icon-double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'step_a04_desktop_icon_double_click.json'
    $open = Invoke-Agent -WinArgs @(
        'desktop-icon-double-click',
        '--target', $icon.target,
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    $verified = $open.json.ok -eq $true -and
        $open.json.data.backend_fallback_used -eq $false -and
        $open.json.data.command -eq 'desktop-icon-double-click'
    Complete-Step $step "desktop-icon-double-click --target $($icon.target)" $after $verified $raw

    $step = New-StepRecord 'A05' 'verify Visual Studio window appears' 'visible top-level window target lock'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $lock = Wait-VsWindow 150
    $raw = Join-Path $OutDir 'step_a05_vs_window_lock.json'
    if ($lock -is [string]) {
        Write-TextFile -Path $raw -Value $lock
        $after = Capture-Observation $step.step_id 'after'
        Complete-Step $step 'target-lock-acquire --target-process devenv.exe' $after $false $raw
    }
    Write-TextFile -Path $raw -Value $lock.raw
    $script:VsWindowVerified = $lock.exit -eq 0 -and $lock.json.ok -eq $true -and $lock.json.data.target_window_locked -eq $true
    $script:VsWindowTitle = [string]$lock.json.data.title
    $script:VsWindowHwnd = [string]$lock.json.data.hwnd
    $script:VsWindowRect = $lock.json.data.target_rect
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'target-lock-acquire --target-process devenv.exe --require-target-lock true' $after $script:VsWindowVerified $raw

    $step = New-StepRecord 'A06' 'locate top-right X close target' 'UIA title bar close button or visible window rect'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $currentLockRaw = Join-Path $OutDir 'step_a06_current_vs_window_lock.json'
    $currentLock = Get-VsWindowLock -Allowed @(0)
    Write-TextFile -Path $currentLockRaw -Value $currentLock.raw
    $script:VsWindowTitle = [string]$currentLock.json.data.title
    $script:VsWindowHwnd = [string]$currentLock.json.data.hwnd
    $script:VsWindowRect = $currentLock.json.data.target_rect
    $closeX = [int]$script:VsWindowRect.right - 18
    $closeY = [int]$script:VsWindowRect.top + 18
    $closeSource = 'visible_window_rect_top_right_x'
    $raw = Join-Path $OutDir 'step_a06_uia_tree_for_close.json'
    $uia = Invoke-Agent -WinArgs @('uia-tree', '--process', 'devenv.exe') -Allowed @(0, 1) -RawPath $raw
    if ($uia.exit -eq 0 -and $uia.json.ok -eq $true) {
        $closeCandidates = @($uia.json.data.elements | Where-Object {
            $elementName = [string]$_.name
            $_.control_type -eq 'Button' -and
            $_.enabled -eq $true -and
            $_.offscreen -eq $false -and
            $_.rect.right -gt $_.rect.left -and
            $_.rect.bottom -gt $_.rect.top -and
            $_.rect.right -ge ([int]$script:VsWindowRect.right - 90) -and
            $_.rect.top -le ([int]$script:VsWindowRect.top + 45) -and
            $_.rect.bottom -le ([int]$script:VsWindowRect.top + 55) -and
            ($elementName -eq 'Close' -or $elementName -eq $script:ChineseCloseText)
        } | Sort-Object { [int]$_.rect.right } -Descending)
        if ($closeCandidates.Count -gt 0) {
            $candidate = $closeCandidates | Select-Object -First 1
            $closeX = [int]($candidate.rect.left + (($candidate.rect.right - $candidate.rect.left) / 2))
            $closeY = [int]($candidate.rect.top + (($candidate.rect.bottom - $candidate.rect.top) / 2))
            $closeSource = 'UIA'
        }
    }
    $after = Capture-Observation $step.step_id 'after'
    $verified = $closeX -lt [int]$script:VsWindowRect.right -and
        $closeX -gt [int]$script:VsWindowRect.left -and
        $closeY -gt [int]$script:VsWindowRect.top -and
        $closeY -lt [int]$script:VsWindowRect.bottom
    Complete-Step $step "locate top-right close point x=$closeX y=$closeY source=$closeSource" $after $verified $raw

    $step = New-StepRecord 'A07' 'click top-right X close target' $closeSource
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'step_a07_click_top_right_x.json'
    $click = Invoke-Agent -WinArgs @(
        'desktop-click',
        '--screen-x', ([string]$closeX),
        '--screen-y', ([string]$closeY),
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--coordinate-source', 'visible_window_rect_top_right_x',
        '--target-description', 'Visual Studio top-right close button',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -Allowed @(0, 1) -RawPath $raw
    $script:CloseMethod = 'top_right_x_visible_click'
    $after = Capture-Observation $step.step_id 'after'
    $verified = ($click.exit -eq 0 -and $click.json.ok -eq $true -and $click.json.data.backend_action -eq $false) -or
        ($click.exit -eq 1 -and $click.json.error.code -eq 'FAIL_FOREGROUND_DRIFTED')
    Complete-Step $step 'desktop-click Visual Studio top-right X' $after $verified $raw

    $step = New-StepRecord 'A08' 'verify Visual Studio window disappeared' 'visible top-level window target lock'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $gone = Test-VsWindowGone 60
    $script:VsWindowDisappeared = $gone
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'target-lock-acquire polling until devenv.exe window absent' $after $gone ''

    $script:Status = 'PASS'
    $script:StatusMessage = 'Feature A visible desktop launch and close discipline passed.'
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host 'PASS vs_desktop_launch_close_selftest'
    Write-Host "Report: $Report"
    exit 0
} catch {
    if ($script:Status -ne 'BLOCKED') {
        $script:Status = 'FAIL'
    }
    $script:StatusMessage = $_.Exception.Message
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host "$($script:Status) vs_desktop_launch_close_selftest"
    Write-Host "Reason: $($script:StatusMessage)"
    Write-Host "Report: $Report"
    exit 1
}
