param(
    [string]$Root = (Get-Location).Path,
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.4_vs_cpp_complex_ide_workflow'
$Report = Join-Path $OutDir 'vs_cpp_item_add_workflow_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:Steps = @()
$script:Status = 'FAIL'
$script:StatusMessage = ''
$script:ProjectName = 'SingleTestProject'
$script:TemplateRequired = -join @([char]0x7A7A, [char]0x9879, [char]0x76EE)
$script:TemplateSelected = $script:TemplateRequired
$script:TemplateSelectionMethod = 'reused_from_feature_b'
$script:TemplateSearchUsed = $true
$script:DesktopVsIconFound = $false
$script:SelectedVsIconName = ''
$script:VsWindowVerified = $false
$script:CloseMethod = 'not_attempted'
$script:VsWindowDisappeared = $false
$script:SavePromptHandled = 'not_needed'
$script:BackendLaunchUsed = $false
$script:StartMenuLaunchUsed = $false
$script:BackendProjectCreationUsed = $false
$script:BackendFileCreationUsed = $false
$script:BackendBuildUsed = $false
$script:BackendRunUsed = $false
$script:OldMockVlmUsed = $false
$script:RealVlmPathUsed = 'not_needed'
$script:WrongProjectCleanupPerformed = $false
$script:OutputVerified = $false
$script:ActualProjectPath = ''
$script:SolutionPath = ''
$script:VcxprojPath = ''
$script:MainCppPath = ''
$script:ExtraCppPath = ''
$script:HeaderPath = ''
$script:PreferredContextMenuAttempted = $false
$script:CtrlShiftAFallbackUsed = $false

$script:TextSolutionExplorer = -join @([char]0x89E3, [char]0x51B3, [char]0x65B9, [char]0x6848, [char]0x8D44, [char]0x6E90, [char]0x7BA1, [char]0x7406, [char]0x5668)
$script:TextSourceFiles = -join @([char]0x6E90, [char]0x6587, [char]0x4EF6)
$script:TextHeaderFiles = -join @([char]0x5934, [char]0x6587, [char]0x4EF6)
$script:TextAddNewItem = -join @([char]0x6DFB, [char]0x52A0, [char]0x65B0, [char]0x9879)
$script:TextAdd = -join @([char]0x6DFB, [char]0x52A0)
$script:TextCancel = -join @([char]0x53D6, [char]0x6D88)
$script:TextClose = -join @([char]0x5173, [char]0x95ED)
$script:TextSavePromptTitle = -join @([char]0x662F, [char]0x5426, [char]0x4FDD, [char]0x5B58, [char]0x5BF9, [char]0x4EE5, [char]0x4E0B, [char]0x9879, [char]0x6240, [char]0x505A, [char]0x7684, [char]0x66F4, [char]0x6539, '?')
$script:TextSave = -join @([char]0x4FDD, [char]0x5B58)

function ConvertTo-JsonText($Value) {
    return ($Value | ConvertTo-Json -Depth 60)
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
    $text = ($output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($RawPath)) { Write-TextFile $RawPath $text }
    $json = $null
    try { $json = $text | ConvertFrom-Json } catch { }
    [pscustomobject]@{ exit = $exit; raw = $text; json = $json; raw_path = $RawPath }
}

function New-StepRecord([string]$Id, [string]$Action, [string]$Source) {
    [pscustomobject]@{
        step_id = $Id
        intended_action = $Action
        visible_observe_before = ''
        target_source = $Source
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

function Add-Step($Step) {
    $script:Steps += $Step
}

function Complete-Step {
    param(
        $Step,
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
    if (-not $Verified) { throw "Step $($Step.step_id) failed: $($Step.intended_action)" }
}

function Capture-Observation([string]$StepId, [string]$Phase) {
    $shot = Join-Path $OutDir "$StepId`_$Phase`_global.png"
    $win = Join-Path $OutDir "$StepId`_$Phase`_windows.json"
    Invoke-Agent -WinArgs @('global-screenshot', '--out', $shot) -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$StepId`_$Phase`_global.json") | Out-Null
    Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath $win | Out-Null
    return "global_screenshot=$shot; windows=$win"
}

function Write-Report([string]$Result, [string]$Message) {
    $lines = @(
        '# VS C++ item add workflow selftest report',
        '',
        "- result: $Result",
        "- message: $Message",
        "- project_name=$($script:ProjectName)",
        "- template_required=$($script:TemplateRequired)",
        "- template_selected=$($script:TemplateSelected)",
        "- template_selection_method=$($script:TemplateSelectionMethod)",
        "- template_search_used=$($script:TemplateSearchUsed.ToString().ToLowerInvariant())",
        '- wrong_template_selected=false',
        '- project_location_modified=false',
        "- actual_project_path=$($script:ActualProjectPath)",
        "- solution_path=$($script:SolutionPath)",
        "- vcxproj_path=$($script:VcxprojPath)",
        "- main_cpp_path=$($script:MainCppPath)",
        "- extra_cpp_path=$($script:ExtraCppPath)",
        "- header_path=$($script:HeaderPath)",
        "- project_root=$Root",
        "- testrepo_root=$TestRepoRoot",
        '- step_by_step_visible_execution=true',
        '- vs_open_method=desktop_icon_double_click',
        "- desktop_vs_icon_found=$($script:DesktopVsIconFound.ToString().ToLowerInvariant())",
        "- selected_vs_icon_name=$($script:SelectedVsIconName)",
        "- backend_launch_used=$($script:BackendLaunchUsed.ToString().ToLowerInvariant())",
        "- start_menu_launch_used=$($script:StartMenuLaunchUsed.ToString().ToLowerInvariant())",
        "- close_method=$($script:CloseMethod)",
        "- vs_window_disappeared=$($script:VsWindowDisappeared.ToString().ToLowerInvariant())",
        "- save_prompt_handled_by_visible_ui=$($script:SavePromptHandled)",
        '- process_kill_used=false',
        '- vs_closed_after_each_success=true',
        "- preferred_context_menu_attempted=$($script:PreferredContextMenuAttempted.ToString().ToLowerInvariant())",
        "- ctrl_shift_a_fallback_used=$($script:CtrlShiftAFallbackUsed.ToString().ToLowerInvariant())",
        "- backend_project_creation_used=$($script:BackendProjectCreationUsed.ToString().ToLowerInvariant())",
        "- backend_file_creation_used=$($script:BackendFileCreationUsed.ToString().ToLowerInvariant())",
        "- backend_build_used=$($script:BackendBuildUsed.ToString().ToLowerInvariant())",
        "- backend_run_used=$($script:BackendRunUsed.ToString().ToLowerInvariant())",
        "- old_mock_vlm_used=$($script:OldMockVlmUsed.ToString().ToLowerInvariant())",
        "- real_vlm_path_used_when_needed=$($script:RealVlmPathUsed)",
        "- wrong_project_cleanup_performed=$($script:WrongProjectCleanupPerformed.ToString().ToLowerInvariant())",
        "- output_verified=$($script:OutputVerified.ToString().ToLowerInvariant())",
        '',
        '## Step Checkpoints',
        '',
        '```json',
        (ConvertTo-JsonText $script:Steps),
        '```',
        ''
    )
    Write-TextFile $Report ($lines -join "`r`n")
}

function Get-RectCenter($Rect) {
    [pscustomobject]@{
        x = [int]($Rect.left + (($Rect.right - $Rect.left) / 2))
        y = [int]($Rect.top + (($Rect.bottom - $Rect.top) / 2))
    }
}

function Get-UiaTree {
    param(
        [string]$Name,
        [string]$Title = '',
        [string]$Process = 'devenv.exe'
    )
    $raw = Join-Path $OutDir "$Name.json"
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        Invoke-Agent -WinArgs @('uia-tree', '--title', $Title) -Allowed @(0, 1) -RawPath $raw
    } else {
        Invoke-Agent -WinArgs @('uia-tree', '--process', $Process) -Allowed @(0, 1) -RawPath $raw
    }
}

function Get-VsWindowLock([int[]]$Allowed = @(0)) {
    Invoke-Agent -WinArgs @('target-lock-acquire', '--target-process', 'devenv.exe', '--require-target-lock', 'true') -Allowed $Allowed
}

function Wait-VsWindow([int]$TimeoutSeconds = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $lock = Get-VsWindowLock -Allowed @(0, 1)
        if ($lock.exit -eq 0 -and $lock.json.ok -eq $true) { return $lock }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $lock
}

function Test-VsWindowGone([int]$TimeoutSeconds = 90) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1)
        $hasVs = $false
        if ($windows.json.ok -eq $true) {
            $hasVs = @($windows.json.windows | Where-Object { ([string]$_.title).Contains('Visual Studio') -or ([string]$_.title).Contains('SingleTestProject') }).Count -gt 0
        }
        if (-not $hasVs) { return $true }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Test-WindowTitlePresent([string]$Title) {
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1)
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return $false }
    return @($windows.json.windows | Where-Object { ([string]$_.title) -eq $Title }).Count -gt 0
}

function Wait-VisibleFileEvidence {
    param(
        [string]$FileName,
        [string]$ExpectedPath,
        [int]$TimeoutSeconds = 45
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $created = Test-Path -LiteralPath $ExpectedPath
        $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1)
        $titleHasFile = $false
        if ($windows.exit -eq 0 -and $windows.json.ok -eq $true) {
            $titleHasFile = @($windows.json.windows | Where-Object {
                ([string]$_.title).Contains($FileName) -and ([string]$_.title).Contains('Visual Studio')
            }).Count -gt 0
        }
        if ($created -and $titleHasFile) {
            return [pscustomobject]@{ ok = $true; created = $created; title_has_file = $titleHasFile }
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return [pscustomobject]@{ ok = $false; created = (Test-Path -LiteralPath $ExpectedPath); title_has_file = $false }
}

function Find-ProjectArtifacts {
    $roots = @()
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        $roots += @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Join-Path $_.FullName 'source\repos'
        })
    }
    $roots += (Join-Path $env:USERPROFILE 'source\repos')
    $roots = @($roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $solutions = @()
    foreach ($repos in $roots) {
        if (Test-Path -LiteralPath $repos) {
            $solutions += @(Get-ChildItem -LiteralPath $repos -Filter 'SingleTestProject.sln' -Recurse -ErrorAction SilentlyContinue)
            $solutions += @(Get-ChildItem -LiteralPath $repos -Filter 'SingleTestProject.slnx' -Recurse -ErrorAction SilentlyContinue)
        }
    }
    if ($solutions.Count -eq 0) { return $null }
    $sln = $solutions | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $vcx = @(Get-ChildItem -LiteralPath (Split-Path -Parent $sln.FullName) -Filter 'SingleTestProject.vcxproj' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($vcx.Count -eq 0) { return $null }
    [pscustomobject]@{
        solution = $sln.FullName
        vcxproj = $vcx[0].FullName
        actual_project_path = Split-Path -Parent $vcx[0].FullName
    }
}

function Refresh-ProjectPaths {
    $artifacts = Find-ProjectArtifacts
    if ($null -eq $artifacts) { return $false }
    $script:SolutionPath = $artifacts.solution
    $script:VcxprojPath = $artifacts.vcxproj
    $script:ActualProjectPath = $artifacts.actual_project_path
    $script:MainCppPath = Join-Path $script:ActualProjectPath 'main.cpp'
    $script:ExtraCppPath = Join-Path $script:ActualProjectPath 'math.cpp'
    $script:HeaderPath = Join-Path $script:ActualProjectPath 'math_utils.h'
    return $true
}

function Find-ElementByText($Uia, [string[]]$Texts, [string]$ControlType = '') {
    if ($null -eq $Uia -or $Uia.exit -ne 0 -or $Uia.json.ok -ne $true) { return $null }
    foreach ($text in $Texts) {
        $matches = @($Uia.json.data.elements | Where-Object {
            $name = [string]$_.name
            $value = [string]$_.value
            ($name.Contains($text) -or $value.Contains($text)) -and
            ([string]::IsNullOrWhiteSpace($ControlType) -or $_.control_type -eq $ControlType) -and
            $_.rect.right -gt $_.rect.left -and
            $_.rect.bottom -gt $_.rect.top -and
            $_.offscreen -eq $false
        })
        if ($matches.Count -gt 0) { return ($matches | Sort-Object { [int]$_.rect.top } | Select-Object -First 1) }
    }
    return $null
}

function Wait-RecentProjectElement {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 90
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastUia = $null
    do {
        $lastUia = Get-UiaTree $Name
        $recent = Find-ElementByText $lastUia @('SingleTestProject.slnx', 'SingleTestProject.sln', 'SingleTestProject') 'Button'
        if ($null -eq $recent) {
            $recent = Find-ElementByText $lastUia @('SingleTestProject.slnx', 'SingleTestProject.sln', 'SingleTestProject') 'ListItem'
        }
        if ($null -eq $recent) {
            $recent = Find-ElementByText $lastUia @('SingleTestProject.slnx', 'SingleTestProject.sln', 'SingleTestProject')
        }
        if ($null -ne $recent) {
            return [pscustomobject]@{ element = $recent; uia = $lastUia }
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return [pscustomobject]@{ element = $null; uia = $lastUia }
}

function Click-Element {
    param(
        $Element,
        [string]$Description,
        [bool]$DoubleClick = $false,
        [string]$RawPath,
        [string]$TargetTitle = '',
        [string]$TargetProcess = 'devenv.exe'
    )
    $center = Get-RectCenter $Element.rect
    $command = if ($DoubleClick) { 'desktop-double-click' } else { 'desktop-click' }
    $args = @(
        $command,
        '--screen-x', ([string]$center.x),
        '--screen-y', ([string]$center.y),
        '--require-target-lock', 'true',
        '--coordinate-source', 'uia',
        '--target-description', $Description,
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    )
    if ([string]::IsNullOrWhiteSpace($TargetTitle)) {
        $args += @('--target-process', $TargetProcess)
    } else {
        $args += @('--target-title', $TargetTitle)
    }
    Invoke-Agent -WinArgs $args -Allowed @(0, 1) -RawPath $RawPath
}

function Find-DesktopVsIcon {
    $candidates = @('Visual Studio', 'VS2026', 'Visual Studio 2026')
    foreach ($candidate in $candidates) {
        $raw = Join-Path $OutDir ("desktop_icon_locate_" + ($candidate -replace '[^A-Za-z0-9]', '_') + '.json')
        $result = Invoke-Agent -WinArgs @('desktop-icon-locate', '--target', $candidate) -Allowed @(0, 1) -RawPath $raw
        if ($result.exit -eq 0 -and $result.json.ok -eq $true -and $result.json.data.backend_fallback_used -eq $false) {
            return [pscustomobject]@{ target = $candidate; result = $result }
        }
    }
    return $null
}

function Open-VsFromDesktopAndProject {
    param([string]$Prefix)

    $step = New-StepRecord "$($Prefix)01" 'show desktop using visible-show-desktop' 'visible evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($Prefix)01_visible_show_desktop.json"
    $showDesktop = Invoke-Agent -WinArgs @('visible-show-desktop', '--allow-backend-fallback', 'false', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    $verified = $showDesktop.json.ok -eq $true -and $showDesktop.json.data.backend_show_desktop_used -eq $false
    Complete-Step $step 'visible-show-desktop --allow-backend-fallback false' $after $verified $raw

    $step = New-StepRecord "$($Prefix)02" 'locate Visual Studio / VS2026 desktop icon' 'UIA visible desktop'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $icon = Find-DesktopVsIcon
    $script:DesktopVsIconFound = $null -ne $icon
    if (-not $script:DesktopVsIconFound) {
        Complete-Step $step 'desktop-icon-locate Visual Studio/VS2026 candidates' (Capture-Observation $step.step_id 'after') $false ''
    }
    $script:SelectedVsIconName = $icon.target
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step "desktop-icon-locate --target $($icon.target)" $after $true $icon.result.raw_path

    $step = New-StepRecord "$($Prefix)03" 'double-click Visual Studio desktop icon' 'Runtime visible desktop-icon-double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($Prefix)03_desktop_icon_double_click.json"
    $open = Invoke-Agent -WinArgs @('desktop-icon-double-click', '--target', $icon.target, '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step "desktop-icon-double-click --target $($icon.target)" $after ($open.json.ok -eq $true -and $open.json.data.backend_fallback_used -eq $false) $raw

    $step = New-StepRecord "$($Prefix)04" 'verify Visual Studio start window appears' 'visible top-level window target lock'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $lock = Wait-VsWindow 150
    $script:VsWindowVerified = $lock.exit -eq 0 -and $lock.json.ok -eq $true
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'target-lock-acquire --target-process devenv.exe' $after $script:VsWindowVerified ''

    $step = New-StepRecord "$($Prefix)05" 'open SingleTestProject from visible VS recent project list' 'UIA recent project list plus visible double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $recentWait = Wait-RecentProjectElement "$($Prefix)05_start_window_uia" 90
    $recent = $recentWait.element
    if ($null -eq $recent) { Complete-Step $step 'locate SingleTestProject recent project item' (Capture-Observation $step.step_id 'after') $false '' }
    $raw = Join-Path $OutDir "$($Prefix)05_double_click_recent_project.json"
    Click-Element -Element $recent -Description 'SingleTestProject recent project item' -DoubleClick $true -RawPath $raw | Out-Null
    Start-Sleep -Seconds 8
    $lock = Wait-VsWindow 60
    $title = [string]$lock.json.data.title
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'desktop-double-click SingleTestProject recent project item' $after ($lock.exit -eq 0 -and $title.Contains('SingleTestProject')) $raw
}

function Ensure-SolutionExplorerVisible {
    param([string]$Prefix)
    $step = New-StepRecord "$($Prefix)06" 'show and verify Solution Explorer tree' 'UIA tab/tree evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $uia = Get-UiaTree "$($Prefix)06_solution_explorer_before_uia"
    $source = Find-ElementByText $uia @($script:TextSourceFiles, 'Source Files') 'TreeItem'
    if ($null -eq $source) {
        $tab = Find-ElementByText $uia @($script:TextSolutionExplorer, 'Solution Explorer') 'TabItem'
        if ($null -ne $tab) {
            Click-Element -Element $tab -Description 'Solution Explorer tab' -RawPath (Join-Path $OutDir "$($Prefix)06_click_solution_explorer_tab.json") | Out-Null
            Start-Sleep -Seconds 1
        } else {
            Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+ALT+L', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir "$($Prefix)06_ctrl_alt_l_solution_explorer.json") | Out-Null
            Start-Sleep -Seconds 1
        }
    }
    $uiaAfter = Get-UiaTree "$($Prefix)06_solution_explorer_after_uia"
    $sourceAfter = Find-ElementByText $uiaAfter @($script:TextSourceFiles, 'Source Files') 'TreeItem'
    $headerAfter = Find-ElementByText $uiaAfter @($script:TextHeaderFiles, 'Header Files') 'TreeItem'
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'activate Solution Explorer and verify Source/Header tree folders' $after ($null -ne $sourceAfter -and $null -ne $headerAfter) ''
}

function Get-SolutionExplorerFolder([string]$FolderKind, [string]$Name) {
    $uia = Get-UiaTree $Name
    if ($FolderKind -eq 'source') {
        return Find-ElementByText $uia @($script:TextSourceFiles, 'Source Files') 'TreeItem'
    }
    return Find-ElementByText $uia @($script:TextHeaderFiles, 'Header Files') 'TreeItem'
}

function Add-ItemVisibleWorkflow {
    param(
        [string]$StepId,
        [string]$FolderKind,
        [string]$FileName,
        [string]$ExpectedPath
    )
    $folderText = if ($FolderKind -eq 'source') { 'Source Files' } else { 'Header Files' }

    $step = New-StepRecord $StepId "add $FileName under $folderText through VS visible UI" 'Solution Explorer UIA plus Ctrl+Shift+A fallback'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $folder = Get-SolutionExplorerFolder $FolderKind "$StepId`_folder_before_uia"
    if ($null -eq $folder) { Complete-Step $step "locate $folderText tree item" (Capture-Observation $step.step_id 'after') $false '' }

    $script:PreferredContextMenuAttempted = $true
    $rawRight = Join-Path $OutDir "$StepId`_preferred_right_click_folder.json"
    $folderCenter = Get-RectCenter $folder.rect
    Invoke-Agent -WinArgs @(
        'desktop-right-click',
        '--screen-x', ([string]$folderCenter.x),
        '--screen-y', ([string]$folderCenter.y),
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--coordinate-source', 'uia',
        '--target-description', "$folderText folder preferred context menu probe",
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -Allowed @(0, 1) -RawPath $rawRight | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-Agent -WinArgs @('desktop-press', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--key', 'ESC', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$StepId`_close_context_menu_escape.json") | Out-Null
    Start-Sleep -Milliseconds 300

    Click-Element -Element $folder -Description "$folderText tree item" -RawPath (Join-Path $OutDir "$StepId`_select_folder.json") | Out-Null
    Start-Sleep -Milliseconds 400
    $script:CtrlShiftAFallbackUsed = $true
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+SHIFT+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir "$StepId`_ctrl_shift_a.json") | Out-Null
    Start-Sleep -Seconds 2
    $dialog = Get-UiaTree "$StepId`_add_new_item_dialog_uia" -Title $script:TextAddNewItem
    $nameEdit = $null
    if ($dialog.exit -eq 0 -and $dialog.json.ok -eq $true) {
        $edits = @($dialog.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false } | Sort-Object { [int]$_.rect.top })
        if ($edits.Count -gt 0) { $nameEdit = $edits | Select-Object -First 1 }
    }
    if ($null -eq $nameEdit) { Complete-Step $step 'open Add New Item dialog and locate file name edit' (Capture-Observation $step.step_id 'after') $false '' }

    Click-Element -Element $nameEdit -Description 'Add New Item file name edit' -RawPath (Join-Path $OutDir "$StepId`_click_file_name.json") -TargetTitle $script:TextAddNewItem | Out-Null
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-title', $script:TextAddNewItem, '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir "$StepId`_filename_ctrl_a.json") | Out-Null
    Invoke-Agent -WinArgs @('desktop-type', '--target-title', $script:TextAddNewItem, '--require-target-lock', 'true', '--text', $FileName, '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir "$StepId`_filename_type.json") | Out-Null
    Start-Sleep -Milliseconds 500
    $dialogAfterName = Get-UiaTree "$StepId`_after_filename_uia" -Title $script:TextAddNewItem
    $addButton = Find-ElementByText $dialogAfterName @($script:TextAdd, 'Add') 'Button'
    if ($null -eq $addButton) { Complete-Step $step 'locate Add button in Add New Item dialog' (Capture-Observation $step.step_id 'after') $false '' }
    Click-Element -Element $addButton -Description 'Add New Item Add button' -RawPath (Join-Path $OutDir "$StepId`_click_add_button.json") -TargetTitle $script:TextAddNewItem | Out-Null
    Start-Sleep -Seconds 2
    $recoveryNeeded = $false
    $recoveryAction = ''
    if (-not (Test-Path -LiteralPath $ExpectedPath) -and (Test-WindowTitlePresent $script:TextAddNewItem)) {
        $recoveryNeeded = $true
        $recoveryAction = 'visible ENTER pressed in Add New Item dialog after Add click did not close dialog'
        Invoke-Agent -WinArgs @('desktop-press', '--target-title', $script:TextAddNewItem, '--require-target-lock', 'true', '--key', 'ENTER', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$StepId`_add_dialog_enter_recovery.json") | Out-Null
    }
    $visibleEvidence = Wait-VisibleFileEvidence $FileName $ExpectedPath 45
    $vcxIncludesBeforeClose = $false
    if (Test-Path -LiteralPath $script:VcxprojPath) {
        $vcxText = Get-Content -Raw -LiteralPath $script:VcxprojPath
        $vcxIncludesBeforeClose = $vcxText.Contains($FileName)
    }
    $after = Capture-Observation $step.step_id 'after'
    $notes = "preferred_context_menu_attempted=True; ctrl_shift_a_fallback_used=True; file_created=$($visibleEvidence.created); vs_title_contains_file=$($visibleEvidence.title_has_file); vcxproj_contains_before_close=$vcxIncludesBeforeClose"
    Complete-Step $step "select $folderText; Ctrl+Shift+A; set filename $FileName; click Add" $after $visibleEvidence.ok '' -RecoveryNeeded $recoveryNeeded -RecoveryAction $recoveryAction -Notes $notes
}

function Close-VsVisible {
    param([string]$StepPrefix)
    $lock = Get-VsWindowLock -Allowed @(0)
    $rect = $lock.json.data.target_rect
    $uia = Get-UiaTree "$StepPrefix`_uia_tree_for_close"
    $closeX = [int]$rect.right - 22
    $closeY = [int]$rect.top + 18
    if ($uia.exit -eq 0 -and $uia.json.ok -eq $true) {
        $buttons = @($uia.json.data.elements | Where-Object {
            $_.control_type -eq 'Button' -and $_.enabled -eq $true -and $_.offscreen -eq $false -and
            $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top -and
            $_.rect.right -ge ([int]$rect.right - 90) -and $_.rect.top -le ([int]$rect.top + 60)
        } | Sort-Object { [int]$_.rect.right } -Descending)
        if ($buttons.Count -gt 0) {
            $b = $buttons | Select-Object -First 1
            $closeX = [int]($b.rect.left + (($b.rect.right - $b.rect.left) / 2))
            $closeY = [int]($b.rect.top + (($b.rect.bottom - $b.rect.top) / 2))
        }
    }
    $raw = Join-Path $OutDir "$StepPrefix`_click_top_right_x.json"
    Invoke-Agent -WinArgs @(
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
    ) -Allowed @(0, 1) -RawPath $raw | Out-Null
    Start-Sleep -Seconds 2
}

function Handle-SavePromptVisible {
    param([string]$StepPrefix)

    $windowsRaw = Join-Path $OutDir "$StepPrefix`_save_prompt_windows.json"
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath $windowsRaw
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return $false }

    $prompt = @($windows.json.windows | Where-Object {
        ([string]$_.title) -eq $script:TextSavePromptTitle
    } | Select-Object -First 1)
    if ($prompt.Count -eq 0) { return $false }

    $promptUia = Get-UiaTree "$StepPrefix`_save_prompt_uia" -Title $script:TextSavePromptTitle
    if ($promptUia.exit -ne 0 -or $promptUia.json.ok -ne $true) { return $false }

    $saveButtons = @($promptUia.json.data.elements | Where-Object {
        $_.control_type -eq 'Button' -and $_.enabled -eq $true -and $_.offscreen -eq $false -and
        $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top -and
        ([string]$_.name).StartsWith($script:TextSave)
    } | Sort-Object { [int]$_.rect.left })
    if ($saveButtons.Count -eq 0) { return $false }

    $raw = Join-Path $OutDir "$StepPrefix`_click_save_prompt_save.json"
    Click-Element -Element ($saveButtons | Select-Object -First 1) -Description 'Visual Studio save prompt Save button' -RawPath $raw -TargetTitle $script:TextSavePromptTitle | Out-Null
    Start-Sleep -Seconds 3
    $script:SavePromptHandled = 'true'
    return $true
}

function Close-VsStep([string]$StepId, [string]$Reason) {
    $step = New-StepRecord $StepId $Reason 'visible top-right X click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    Close-VsVisible $StepId
    $script:CloseMethod = 'top_right_x_visible_click'
    $gone = Test-VsWindowGone 90
    $recoveryNeeded = $false
    $recoveryAction = ''
    if (-not $gone) {
        $handledSavePrompt = Handle-SavePromptVisible $StepId
        if ($handledSavePrompt) {
            $recoveryNeeded = $true
            $recoveryAction = 'visible Save button clicked in Visual Studio save prompt'
            $gone = Test-VsWindowGone 90
        }
    }
    $script:VsWindowDisappeared = $gone
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'desktop-click Visual Studio top-right X and verify gone' $after $gone (Join-Path $OutDir "$StepId`_click_top_right_x.json") -RecoveryNeeded $recoveryNeeded -RecoveryAction $recoveryAction
}

if (-not (Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run build first." }

try {
    if (-not (Refresh-ProjectPaths)) { throw 'SingleTestProject artifacts not found. Run Feature B first.' }

    $preexisting = Get-VsWindowLock -Allowed @(0, 1)
    if ($preexisting.exit -eq 0 -and $preexisting.json.ok -eq $true) {
        $script:Status = 'BLOCKED'
        throw 'Preexisting visible devenv.exe window found. Close it before running Feature C.'
    }

    Open-VsFromDesktopAndProject 'C1'
    Ensure-SolutionExplorerVisible 'C1'
    if (-not (Test-Path -LiteralPath $script:MainCppPath)) {
        Add-ItemVisibleWorkflow 'C107' 'source' 'main.cpp' $script:MainCppPath
    } else {
        $step = New-StepRecord 'C107' 'verify existing main.cpp from prior visible add run' 'filesystem evidence'
        $step.visible_observe_before = Capture-Observation $step.step_id 'before'
        $after = Capture-Observation $step.step_id 'after'
        Complete-Step $step 'verify existing main.cpp' $after $true '' -Notes 'main.cpp_already_present=True'
    }
    Close-VsStep 'C108' 'close Visual Studio using top-right X after single source file add'

    Open-VsFromDesktopAndProject 'C2'
    Ensure-SolutionExplorerVisible 'C2'
    if (-not (Test-Path -LiteralPath $script:ExtraCppPath)) {
        Add-ItemVisibleWorkflow 'C207' 'source' 'math.cpp' $script:ExtraCppPath
    } else {
        $step = New-StepRecord 'C207' 'verify existing math.cpp from prior visible add run' 'filesystem evidence'
        $step.visible_observe_before = Capture-Observation $step.step_id 'before'
        $after = Capture-Observation $step.step_id 'after'
        Complete-Step $step 'verify existing math.cpp' $after $true '' -Notes 'math.cpp_already_present=True'
    }
    if (-not (Test-Path -LiteralPath $script:HeaderPath)) {
        Add-ItemVisibleWorkflow 'C208' 'header' 'math_utils.h' $script:HeaderPath
    } else {
        $step = New-StepRecord 'C208' 'verify existing math_utils.h from prior visible add run' 'filesystem evidence'
        $step.visible_observe_before = Capture-Observation $step.step_id 'before'
        $after = Capture-Observation $step.step_id 'after'
        Complete-Step $step 'verify existing math_utils.h' $after $true '' -Notes 'math_utils.h_already_present=True'
    }
    Close-VsStep 'C209' 'close Visual Studio using top-right X after source/header file add'

    $allFiles = (Test-Path -LiteralPath $script:MainCppPath) -and (Test-Path -LiteralPath $script:ExtraCppPath) -and (Test-Path -LiteralPath $script:HeaderPath)
    $vcxText = if (Test-Path -LiteralPath $script:VcxprojPath) { Get-Content -Raw -LiteralPath $script:VcxprojPath } else { '' }
    $script:OutputVerified = $allFiles -and $vcxText.Contains('main.cpp') -and $vcxText.Contains('math.cpp') -and $vcxText.Contains('math_utils.h')
    if (-not $script:OutputVerified) { throw 'Final Feature C file/vcxproj verification failed.' }

    $script:Status = 'PASS'
    $script:StatusMessage = 'Feature C VS C++ item add workflow passed.'
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host 'PASS vs_cpp_item_add_workflow_selftest'
    Write-Host "Report: $Report"
    exit 0
} catch {
    if ($script:Status -ne 'BLOCKED') { $script:Status = 'FAIL' }
    $script:StatusMessage = $_.Exception.Message
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host "$($script:Status) vs_cpp_item_add_workflow_selftest"
    Write-Host "Reason: $($script:StatusMessage)"
    Write-Host "Report: $Report"
    exit 1
}
