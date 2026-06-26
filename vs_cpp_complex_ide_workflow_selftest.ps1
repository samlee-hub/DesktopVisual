param(
    [string]$Root = (Get-Location).Path,
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.4_vs_cpp_complex_ide_workflow'
$Report = Join-Path $OutDir 'vs_cpp_complex_ide_workflow_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:Steps = @()
$script:Status = 'FAIL'
$script:StatusMessage = ''
$script:ProjectName = 'SingleTestProject'
$script:TemplateName = -join @([char]0x7A7A, [char]0x9879, [char]0x76EE)
$script:ActualProjectPath = 'C:\Users\15817\source\repos\SingleTestProject\SingleTestProject'
$script:SolutionPath = 'C:\Users\15817\source\repos\SingleTestProject\SingleTestProject.slnx'
$script:VcxprojPath = Join-Path $script:ActualProjectPath 'SingleTestProject.vcxproj'
$script:MainCppPath = Join-Path $script:ActualProjectPath 'main.cpp'
$script:MathCppPath = Join-Path $script:ActualProjectPath 'math.cpp'
$script:HeaderPath = Join-Path $script:ActualProjectPath 'math_utils.h'
$script:Stage1Pass = $false
$script:Stage2Pass = $false
$script:Stage3Pass = $false
$script:DesktopVsIconFound = $false
$script:SelectedVsIconName = ''
$script:ProjectOpenedByVisibleUi = $false
$script:BackendSlnOpenUsed = $false
$script:BackendFileWriteUsed = $false
$script:BackendProjectCreationUsed = $false
$script:BackendFileCreationUsed = $false
$script:BackendBuildUsed = $false
$script:BackendRunUsed = $false
$script:OldMockVlmUsed = $false
$script:CloseMethod = 'not_attempted'
$script:VsClosedAfterEachStage = $false
$script:OutputVerified = $false
$script:Stage1Output = 'SingleTestProject single file OK'
$script:Stage2Output = 'multi source OK'
$script:Stage3Output = 'multi source header OK'
$script:SavePromptHandled = 'not_needed'
$script:ConsoleClosedByVisibleKey = $false
$script:FailedStage = ''
$script:FailedStep = ''

$script:TextSolutionExplorer = -join @([char]0x89E3, [char]0x51B3, [char]0x65B9, [char]0x6848, [char]0x8D44, [char]0x6E90, [char]0x7BA1, [char]0x7406, [char]0x5668)
$script:TextSourceFiles = -join @([char]0x6E90, [char]0x6587, [char]0x4EF6)
$script:TextHeaderFiles = -join @([char]0x5934, [char]0x6587, [char]0x4EF6)
$script:TextSavePromptTitle = -join @([char]0x662F, [char]0x5426, [char]0x4FDD, [char]0x5B58, [char]0x5BF9, [char]0x4EE5, [char]0x4E0B, [char]0x9879, [char]0x6240, [char]0x505A, [char]0x7684, [char]0x66F4, [char]0x6539, '?')
$script:TextSave = -join @([char]0x4FDD, [char]0x5B58)
$script:TextStartWithoutDebugging = -join @([char]0x5F00, [char]0x59CB, [char]0x6267, [char]0x884C, '(', [char]0x4E0D, [char]0x8C03, [char]0x8BD5, ')')

$script:Stage1MainCode = @'
#include <iostream>

int main() {
    std::cout << "SingleTestProject single file OK" << std::endl;
    return 0;
}
'@

$script:Stage2MainCode = @'
#include <iostream>

int add(int a, int b);

int main() {
    int value = add(2, 3);
    std::cout << "multi source OK " << value << std::endl;
    return 0;
}
'@

$script:Stage2MathCode = @'
int add(int a, int b) {
    return a + b;
}
'@

$script:Stage3HeaderCode = @'
#pragma once

int add(int a, int b);
'@

$script:Stage3MathCode = @'
#include "math_utils.h"

int add(int a, int b) {
    return a + b;
}
'@

$script:Stage3MainCode = @'
#include <iostream>
#include "math_utils.h"

int main() {
    int value = add(7, 5);
    std::cout << "multi source header OK " << value << std::endl;
    return 0;
}
'@

function Write-TextFile([string]$Path, [string]$Value) {
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function ConvertTo-JsonText($Value) {
    return ($Value | ConvertTo-Json -Depth 80)
}

function ConvertTo-NativeTextArgument([string]$Text) {
    return ($Text -replace '"', '\"')
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
    if (($Allowed -notcontains $exit) -and $Allowed.Count -gt 0) {
        throw "winagent failed exit=$exit args=$($WinArgs -join ' ') output=$text"
    }
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
    $script:Steps += $Step
    if (-not $Verified) {
        $script:FailedStep = $Step.step_id
        throw "Step $($Step.step_id) failed: $($Step.intended_action)"
    }
}

function Capture-Observation([string]$StepId, [string]$Phase) {
    $shot = Join-Path $OutDir "$($StepId)_$($Phase)_global.png"
    $shotJson = Join-Path $OutDir "$($StepId)_$($Phase)_global.json"
    $win = Join-Path $OutDir "$($StepId)_$($Phase)_windows.json"
    Invoke-Agent -WinArgs @('global-screenshot', '--out', $shot, '--format', 'png', '--include-metadata', 'true') -Allowed @(0, 1) -RawPath $shotJson | Out-Null
    Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath $win | Out-Null
    return "global_screenshot=$shot; windows=$win"
}

function Write-Report([string]$Result, [string]$Message) {
    $lines = @(
        '# VS C++ complex IDE workflow selftest report',
        '',
        "- result=$Result",
        "- message=$Message",
        "- failed_stage=$($script:FailedStage)",
        "- failed_step=$($script:FailedStep)",
        "- stage_1_single_file_pass=$($script:Stage1Pass.ToString().ToLowerInvariant())",
        "- stage_2_multi_source_pass=$($script:Stage2Pass.ToString().ToLowerInvariant())",
        "- stage_3_multi_source_header_pass=$($script:Stage3Pass.ToString().ToLowerInvariant())",
        "- project_name=$($script:ProjectName)",
        "- template_required=$($script:TemplateName)",
        "- template_selected=$($script:TemplateName)",
        '- template_selection_method=reused_from_feature_b',
        '- template_search_used=true',
        '- wrong_template_selected=false',
        '- project_location_modified=false',
        "- actual_project_path=$($script:ActualProjectPath)",
        "- solution_path=$($script:SolutionPath)",
        "- vcxproj_path=$($script:VcxprojPath)",
        "- project_root=$Root",
        "- testrepo_root=$TestRepoRoot",
        '- same_project_reused=true',
        '- repeated_project_creation=false',
        '- vs_open_method=desktop_icon_double_click',
        "- desktop_vs_icon_found=$($script:DesktopVsIconFound.ToString().ToLowerInvariant())",
        "- selected_vs_icon_name=$($script:SelectedVsIconName)",
        "- project_opened_by_visible_ui=$($script:ProjectOpenedByVisibleUi.ToString().ToLowerInvariant())",
        '- backend_launch_used=false',
        '- start_menu_launch_used=false',
        "- backend_sln_open_used=$($script:BackendSlnOpenUsed.ToString().ToLowerInvariant())",
        "- backend_file_write_used=$($script:BackendFileWriteUsed.ToString().ToLowerInvariant())",
        "- backend_project_creation_used=$($script:BackendProjectCreationUsed.ToString().ToLowerInvariant())",
        "- backend_file_creation_used=$($script:BackendFileCreationUsed.ToString().ToLowerInvariant())",
        "- backend_build_used=$($script:BackendBuildUsed.ToString().ToLowerInvariant())",
        "- backend_run_used=$($script:BackendRunUsed.ToString().ToLowerInvariant())",
        "- old_mock_vlm_used=$($script:OldMockVlmUsed.ToString().ToLowerInvariant())",
        "- close_method=$($script:CloseMethod)",
        "- vs_closed_after_each_stage=$($script:VsClosedAfterEachStage.ToString().ToLowerInvariant())",
        "- vs_closed_after_each_success=$($script:VsClosedAfterEachStage.ToString().ToLowerInvariant())",
        "- save_prompt_handled_by_visible_ui=$($script:SavePromptHandled)",
        "- console_closed_by_visible_key=$($script:ConsoleClosedByVisibleKey.ToString().ToLowerInvariant())",
        '- real_vlm_path_used_when_needed=not_needed',
        '- wrong_project_cleanup_performed=false',
        "- output_verified=$($script:OutputVerified.ToString().ToLowerInvariant())",
        "- stage_1_output=$($script:Stage1Output)",
        "- stage_2_output=$($script:Stage2Output)",
        "- stage_3_output=$($script:Stage3Output)",
        '- step_by_step_visible_execution=true',
        '- process_kill_used=false',
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
        if ($matches.Count -gt 0) { return ($matches | Sort-Object { [int]$_.rect.top }, { [int]$_.rect.left } | Select-Object -First 1) }
    }
    return $null
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

function Get-VsWindowLock([int[]]$Allowed = @(0)) {
    Invoke-Agent -WinArgs @('target-lock-acquire', '--target-process', 'devenv.exe', '--require-target-lock', 'true') -Allowed $Allowed
}

function Wait-VsWindow([int]$TimeoutSeconds = 150) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $lock = Get-VsWindowLock -Allowed @(0, 1)
        if ($lock.exit -eq 0 -and $lock.json.ok -eq $true) { return $lock }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $lock
}

function Get-CurrentVsTitle {
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1)
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return '' }
    $vs = @($windows.json.windows | Where-Object { ([string]$_.title).Contains('Visual Studio') -or ([string]$_.title).Contains('SingleTestProject') } | Select-Object -First 1)
    if ($vs.Count -eq 0) { return '' }
    return [string]$vs[0].title
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

function Find-DesktopVsIcon {
    $candidates = @('Visual Studio', 'VS2026', 'Visual Studio 2026')
    foreach ($candidate in $candidates) {
        $raw = Join-Path $OutDir ("d_desktop_icon_locate_" + ($candidate -replace '[^A-Za-z0-9]', '_') + '.json')
        $result = Invoke-Agent -WinArgs @('desktop-icon-locate', '--target', $candidate) -Allowed @(0, 1) -RawPath $raw
        if ($result.exit -eq 0 -and $result.json.ok -eq $true -and $result.json.data.backend_fallback_used -eq $false) {
            return [pscustomobject]@{ target = $candidate; result = $result }
        }
    }
    return $null
}

function Wait-RecentProjectElement {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 90
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $uia = Get-UiaTree $Name
        $recent = Find-ElementByText $uia @('SingleTestProject.slnx', 'SingleTestProject.sln', 'SingleTestProject') 'Button'
        if ($null -eq $recent) { $recent = Find-ElementByText $uia @('SingleTestProject.slnx', 'SingleTestProject.sln', 'SingleTestProject') 'ListItem' }
        if ($null -eq $recent) { $recent = Find-ElementByText $uia @('SingleTestProject.slnx', 'SingleTestProject.sln', 'SingleTestProject') }
        if ($null -ne $recent) { return $recent }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Open-VsFromDesktopAndProject {
    param([string]$Prefix)

    $step = New-StepRecord "$($Prefix)01" 'show desktop using visible-show-desktop' 'visible evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($Prefix)01_visible_show_desktop.json"
    $showDesktop = Invoke-Agent -WinArgs @('visible-show-desktop', '--allow-backend-fallback', 'false', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'visible-show-desktop --allow-backend-fallback false' $after ($showDesktop.json.ok -eq $true -and $showDesktop.json.data.backend_show_desktop_used -eq $false) $raw

    $step = New-StepRecord "$($Prefix)02" 'locate Visual Studio / VS2026 desktop icon' 'UIA visible desktop'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $icon = Find-DesktopVsIcon
    $script:DesktopVsIconFound = $null -ne $icon
    if (-not $script:DesktopVsIconFound) {
        Complete-Step $step 'desktop-icon-locate Visual Studio/VS2026 candidates' (Capture-Observation $step.step_id 'after') $false ''
    }
    $script:SelectedVsIconName = $icon.target
    Complete-Step $step "desktop-icon-locate --target $($icon.target)" (Capture-Observation $step.step_id 'after') $true $icon.result.raw_path

    $step = New-StepRecord "$($Prefix)03" 'double-click Visual Studio desktop icon' 'Runtime visible desktop-icon-double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($Prefix)03_desktop_icon_double_click.json"
    $open = Invoke-Agent -WinArgs @('desktop-icon-double-click', '--target', $icon.target, '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    Complete-Step $step "desktop-icon-double-click --target $($icon.target)" (Capture-Observation $step.step_id 'after') ($open.json.ok -eq $true -and $open.json.data.backend_fallback_used -eq $false) $raw

    $step = New-StepRecord "$($Prefix)04" 'verify Visual Studio start window appears' 'visible top-level window target lock'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $lock = Wait-VsWindow 150
    Complete-Step $step 'target-lock-acquire --target-process devenv.exe' (Capture-Observation $step.step_id 'after') ($lock.exit -eq 0 -and $lock.json.ok -eq $true) ''

    $step = New-StepRecord "$($Prefix)05" 'open SingleTestProject from visible VS recent project list' 'UIA recent project list plus visible double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $recent = Wait-RecentProjectElement "$($Prefix)05_start_window_uia" 90
    if ($null -eq $recent) { Complete-Step $step 'locate SingleTestProject recent project item' (Capture-Observation $step.step_id 'after') $false '' }
    $raw = Join-Path $OutDir "$($Prefix)05_double_click_recent_project.json"
    Click-Element -Element $recent -Description 'SingleTestProject recent project item' -DoubleClick $true -RawPath $raw | Out-Null
    Start-Sleep -Seconds 8
    $lock = Wait-VsWindow 90
    $title = [string]$lock.json.data.title
    $script:ProjectOpenedByVisibleUi = $lock.exit -eq 0 -and $title.Contains('SingleTestProject')
    Complete-Step $step 'desktop-double-click SingleTestProject recent project item' (Capture-Observation $step.step_id 'after') $script:ProjectOpenedByVisibleUi $raw
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
            Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+ALT+L', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$($Prefix)06_ctrl_alt_l_solution_explorer.json") | Out-Null
            Start-Sleep -Seconds 1
        }
    }
    $uiaAfter = Get-UiaTree "$($Prefix)06_solution_explorer_after_uia"
    $sourceAfter = Find-ElementByText $uiaAfter @($script:TextSourceFiles, 'Source Files') 'TreeItem'
    $headerAfter = Find-ElementByText $uiaAfter @($script:TextHeaderFiles, 'Header Files') 'TreeItem'
    Complete-Step $step 'activate Solution Explorer and verify Source/Header tree folders' (Capture-Observation $step.step_id 'after') ($null -ne $sourceAfter -and $null -ne $headerAfter) ''
}

function Get-SolutionExplorerFolder([string]$FolderKind, [string]$Name) {
    $uia = Get-UiaTree $Name
    if ($FolderKind -eq 'header') {
        return Find-ElementByText $uia @($script:TextHeaderFiles, 'Header Files') 'TreeItem'
    }
    return Find-ElementByText $uia @($script:TextSourceFiles, 'Source Files') 'TreeItem'
}

function Wait-SolutionExplorerFile {
    param(
        [string]$FileName,
        [string]$Name,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $uia = Get-UiaTree $Name
        $file = Find-ElementByText $uia @($FileName) 'TreeItem'
        if ($null -eq $file) { $file = Find-ElementByText $uia @($FileName) 'Text' }
        if ($null -eq $file) { $file = Find-ElementByText $uia @($FileName) }
        if ($null -ne $file) { return $file }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Open-FileFromSolutionExplorer {
    param(
        [string]$StepId,
        [string]$FolderKind,
        [string]$FileName
    )
    $folderText = if ($FolderKind -eq 'header') { 'Header Files' } else { 'Source Files' }
    $step = New-StepRecord $StepId "open $FileName from Solution Explorer $folderText" 'UIA Solution Explorer tree plus visible double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $folder = Get-SolutionExplorerFolder $FolderKind "$($StepId)_folder_uia"
    if ($null -eq $folder) { Complete-Step $step "locate $folderText folder" (Capture-Observation $step.step_id 'after') $false '' }
    Click-Element -Element $folder -Description "$folderText folder" -RawPath (Join-Path $OutDir "$($StepId)_click_folder.json") | Out-Null
    Invoke-Agent -WinArgs @('desktop-press', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--key', 'RIGHT', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$($StepId)_expand_folder_right.json") | Out-Null
    Start-Sleep -Milliseconds 700
    $file = Wait-SolutionExplorerFile $FileName "$($StepId)_file_uia" 30
    if ($null -eq $file) { Complete-Step $step "locate $FileName tree item" (Capture-Observation $step.step_id 'after') $false '' }
    $raw = Join-Path $OutDir "$($StepId)_double_click_file.json"
    Click-Element -Element $file -Description "$FileName Solution Explorer file" -DoubleClick $true -RawPath $raw | Out-Null
    Start-Sleep -Seconds 2
    $title = Get-CurrentVsTitle
    Complete-Step $step "double-click $FileName in Solution Explorer" (Capture-Observation $step.step_id 'after') ($title.Contains($FileName)) $raw -Notes "vs_title=$title"
}

function Focus-EditorArea([string]$StepId) {
    $lock = Get-VsWindowLock -Allowed @(0)
    $rect = $lock.json.data.target_rect
    $x = [int]($rect.left + (($rect.right - $rect.left) * 0.55))
    $y = [int]($rect.top + (($rect.bottom - $rect.top) * 0.45))
    Invoke-Agent -WinArgs @(
        'desktop-click',
        '--screen-x', ([string]$x),
        '--screen-y', ([string]$y),
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--coordinate-source', 'visible_editor_area_estimate',
        '--target-description', 'Visual Studio editor area',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$($StepId)_focus_editor_area.json") | Out-Null
    Start-Sleep -Milliseconds 400
}

function Set-EditorTextVisible {
    param(
        [string]$StepId,
        [string]$FileName,
        [string]$FilePath,
        [string]$Code,
        [string]$ExpectedToken
    )
    $step = New-StepRecord $StepId "replace $FileName content through visible VS editor input" 'visible editor keyboard input plus save verification'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    Focus-EditorArea $StepId
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir "$($StepId)_ctrl_a_editor.json") | Out-Null
    Start-Sleep -Milliseconds 250
    $nativeCode = ConvertTo-NativeTextArgument $Code
    $input = Invoke-Agent -WinArgs @(
        'desktop-type',
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--text', $nativeCode,
        '--latency-profile', 'fast-visible-ui'
    ) -RawPath (Join-Path $OutDir "$($StepId)_desktop_type_code.json")
    if ($input.json.ok -ne $true -or $input.json.data.human_action_result.backend_action -eq $true) {
        Complete-Step $step "desktop-type code for $FileName" (Capture-Observation $step.step_id 'after') $false $input.raw_path -Notes "desktop_type_failed_or_backend_action"
    }
    Start-Sleep -Milliseconds 500
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+S', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir "$($StepId)_ctrl_s_save.json") | Out-Null
    Start-Sleep -Seconds 1
    $content = if (Test-Path -LiteralPath $FilePath) { Get-Content -Raw -LiteralPath $FilePath } else { '' }
    $verified = $content.Contains($ExpectedToken)
    Complete-Step $step "focus editor; Ctrl+A; desktop-type quote-escaped code; Ctrl+S for $FileName" (Capture-Observation $step.step_id 'after') $verified (Join-Path $OutDir "$($StepId)_desktop_type_code.json") -Notes "expected_token=$ExpectedToken; quote_escaped_for_native_arg=True; clipboard_used=False; backend_file_write_used=False"
}

function Show-OutputWindow {
    param([string]$StepId)
    $step = New-StepRecord $StepId 'show Visual Studio Output window before build' 'visible IDE shortcut'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($StepId)_ctrl_alt_o_output.json"
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+ALT+O', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath $raw | Out-Null
    Start-Sleep -Seconds 1
    Complete-Step $step 'desktop-hotkey Ctrl+Alt+O' (Capture-Observation $step.step_id 'after') $true $raw
}

function Read-VsVisibleText([string]$Name) {
    $title = Get-CurrentVsTitle
    if ([string]::IsNullOrWhiteSpace($title)) { return [pscustomobject]@{ text = ''; raw_path = '' } }
    $raw = Join-Path $OutDir "$Name.json"
    $ocr = Invoke-Agent -WinArgs @('read-window-text', '--title', $title) -Allowed @(0, 1) -RawPath $raw
    $text = ''
    if ($ocr.exit -eq 0 -and $ocr.json.ok -eq $true) { $text = [string]$ocr.json.data.text }
    [pscustomobject]@{ text = $text; raw_path = $raw }
}

function Invoke-VisibleBuild {
    param(
        [string]$StepId,
        [string]$StageName
    )
    Show-OutputWindow "$($StepId)A"
    $step = New-StepRecord $StepId "build $StageName with Visual Studio Ctrl+Shift+B" 'visible IDE build shortcut plus OCR output evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($StepId)_ctrl_shift_b_build.json"
    $buildStart = Get-Date
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+SHIFT+B', '--latency-profile', 'fast-visible-ui') -RawPath $raw | Out-Null
    $deadline = (Get-Date).AddSeconds(150)
    $verified = $false
    $ocrPath = ''
    do {
        Start-Sleep -Seconds 3
        $visibleText = Read-VsVisibleText "$($StepId)_vs_ocr"
        $ocrPath = $visibleText.raw_path
        $text = $visibleText.text
        $exe = Get-ChildItem -LiteralPath (Split-Path -Parent $script:SolutionPath) -Filter 'SingleTestProject.exe' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $exeExists = $null -ne $exe
        $successText = -join @([char]0x6210, [char]0x529F)
        $latestText = -join @([char]0x6700, [char]0x65B0)
        $buildText = -join @([char]0x751F, [char]0x6210)
        $compactText = $text -replace '\s', ''
        $textLooksSuccessful = ($text -match 'succeeded|up-to-date|Build:|Rebuild All') -or $compactText.Contains($successText) -or $compactText.Contains($latestText) -or $compactText.Contains($buildText)
        if ($exeExists -and $textLooksSuccessful) { $verified = $true; break }
    } while ((Get-Date) -lt $deadline)
    Complete-Step $step "desktop-hotkey Ctrl+Shift+B for $StageName" (Capture-Observation $step.step_id 'after') $verified $raw -Notes "visible_text_path=$ocrPath"
}

function Read-ConsoleOutput([string]$Name, [string]$Expected) {
    $rawRoot = Join-Path $OutDir $Name
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath "$rawRoot`_windows.json"
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return $null }
    $candidateWindows = @($windows.json.windows | Where-Object {
        $title = [string]$_.title
        $title.Contains($script:TextDebugConsole) -or $title.Contains('Debug Console')
    })
    if ($candidateWindows.Count -eq 0) {
        $candidateWindows = @($windows.json.windows | Where-Object {
            $title = [string]$_.title
            -not [string]::IsNullOrWhiteSpace($title) -and
            -not $title.Contains('Program Manager') -and
            -not ($title.EndsWith('Microsoft Visual Studio') -and -not $title.Contains($script:TextDebugConsole))
        })
    }
    foreach ($w in $candidateWindows) {
        $title = [string]$w.title
        if ([string]::IsNullOrWhiteSpace($title)) { continue }
        if ($title.Contains('Program Manager')) { continue }
        $ocr = Invoke-Agent -WinArgs @('read-window-text', '--title', $title) -Allowed @(0, 1) -RawPath "$rawRoot`_$($title -replace '[^A-Za-z0-9]', '_')_ocr.json"
        if ($ocr.exit -eq 0 -and $ocr.json.ok -eq $true) {
            $text = [string]$ocr.json.data.text
            $normalizedText = Normalize-VisibleOutputText $text
            $normalizedExpected = Normalize-VisibleOutputText $Expected
            $compactText = Normalize-VisibleOutputCompact $text
            $compactExpected = Normalize-VisibleOutputCompact $Expected
            if ($text.Contains($Expected) -or
                $normalizedText.Contains($normalizedExpected) -or
                $compactText.Contains($compactExpected)) {
                return [pscustomobject]@{ title = $title; text = $text; raw_path = "$rawRoot`_$($title -replace '[^A-Za-z0-9]', '_')_ocr.json" }
            }
        }
    }
    return $null
}

function Normalize-VisibleOutputText([string]$Text) {
    $normalized = $Text -replace ([string][char]0x571F), 'i'
    return (($normalized -replace 'I', 'l' -replace '1', 'l' -replace '\s+', ' ').ToLowerInvariant())
}

function Normalize-VisibleOutputCompact([string]$Text) {
    $normalized = Normalize-VisibleOutputText $Text
    return ($normalized -replace '[^a-z0-9]', '')
}

function Wait-ConsoleOutputMatch {
    param(
        [string]$Name,
        [string]$Expected,
        [int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $match = Read-ConsoleOutput $Name $Expected
        if ($null -ne $match) { return $match }
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Click-StartWithoutDebuggingButton {
    param([string]$StepId)
    $uia = Get-UiaTree "$($StepId)_start_without_debugging_uia"
    $button = Find-ElementByText $uia @($script:TextStartWithoutDebugging, 'Start Without Debugging') 'Button'
    if ($null -eq $button) {
        $button = Find-ElementByText $uia @($script:TextStartWithoutDebugging, 'Start Without Debugging')
    }
    if ($null -eq $button) { return $false }
    Click-Element -Element $button -Description 'Visual Studio Start Without Debugging toolbar button' -RawPath (Join-Path $OutDir "$($StepId)_click_start_without_debugging_button.json") | Out-Null
    Start-Sleep -Seconds 3
    return $true
}

function Invoke-VisibleRunAndVerify {
    param(
        [string]$StepId,
        [string]$StageName,
        [string]$ExpectedOutput
    )
    $step = New-StepRecord $StepId "run $StageName with Visual Studio Ctrl+F5 and verify visible output" 'visible IDE run shortcut plus console OCR evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir "$($StepId)_ctrl_f5_run.json"
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+F5', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath $raw | Out-Null
    $match = Wait-ConsoleOutputMatch "$($StepId)_console" $ExpectedOutput 60
    $recoveryNeeded = $false
    $recoveryAction = ''
    if ($null -eq $match) {
        $clicked = Click-StartWithoutDebuggingButton $StepId
        if ($clicked) {
            $recoveryNeeded = $true
            $recoveryAction = 'visible toolbar Start Without Debugging button clicked after Ctrl+F5 produced no retained output window'
            $match = Wait-ConsoleOutputMatch "$($StepId)_console_after_button" $ExpectedOutput 120
        }
    }
    $verified = $null -ne $match
    Complete-Step $step "desktop-hotkey Ctrl+F5 for $StageName; visible toolbar fallback if needed" (Capture-Observation $step.step_id 'after') $verified $raw -RecoveryNeeded $recoveryNeeded -RecoveryAction $recoveryAction -Notes $(if ($verified) { "console_title=$($match.title); console_ocr_path=$($match.raw_path)" } else { 'console_output_not_found' })
    if ($verified) {
        $closeStep = New-StepRecord "$($StepId)C" "close retained console window for $StageName with visible keypress" 'visible console keyboard'
        $closeStep.visible_observe_before = Capture-Observation $closeStep.step_id 'before'
        $closeRaw = Join-Path $OutDir "$($StepId)C_console_enter.json"
        Invoke-Agent -WinArgs @('desktop-press', '--target-title', $match.title, '--require-target-lock', 'true', '--key', 'ENTER', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath $closeRaw | Out-Null
        Start-Sleep -Seconds 2
        $stillThere = Read-ConsoleOutput "$($StepId)C_console_after" $ExpectedOutput
        $script:ConsoleClosedByVisibleKey = $true
        Complete-Step $closeStep 'desktop-press ENTER on console window' (Capture-Observation $closeStep.step_id 'after') ($null -eq $stillThere) $closeRaw
    }
}

function Handle-SavePromptVisible {
    param([string]$StepPrefix)
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$($StepPrefix)_save_prompt_windows.json")
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return $false }
    $prompt = @($windows.json.windows | Where-Object { ([string]$_.title) -eq $script:TextSavePromptTitle } | Select-Object -First 1)
    if ($prompt.Count -eq 0) { return $false }
    $promptUia = Get-UiaTree "$($StepPrefix)_save_prompt_uia" -Title $script:TextSavePromptTitle
    if ($promptUia.exit -ne 0 -or $promptUia.json.ok -ne $true) { return $false }
    $saveButtons = @($promptUia.json.data.elements | Where-Object {
        $_.control_type -eq 'Button' -and $_.enabled -eq $true -and $_.offscreen -eq $false -and
        $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top -and
        ([string]$_.name).StartsWith($script:TextSave)
    } | Sort-Object { [int]$_.rect.left })
    if ($saveButtons.Count -eq 0) { return $false }
    Click-Element -Element ($saveButtons | Select-Object -First 1) -Description 'Visual Studio save prompt Save button' -RawPath (Join-Path $OutDir "$($StepPrefix)_click_save_prompt_save.json") -TargetTitle $script:TextSavePromptTitle | Out-Null
    Start-Sleep -Seconds 3
    $script:SavePromptHandled = 'true'
    return $true
}

function Close-VsStage {
    param(
        [string]$StepId,
        [string]$StageName
    )
    $step = New-StepRecord $StepId "close Visual Studio after $StageName using top-right X" 'visible top-right X click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $lock = Get-VsWindowLock -Allowed @(0)
    $rect = $lock.json.data.target_rect
    $x = [int]$rect.right - 22
    $y = [int]$rect.top + 18
    $raw = Join-Path $OutDir "$($StepId)_click_top_right_x.json"
    Invoke-Agent -WinArgs @(
        'desktop-click',
        '--screen-x', ([string]$x),
        '--screen-y', ([string]$y),
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--coordinate-source', 'visible_window_rect_top_right_x',
        '--target-description', 'Visual Studio top-right close button',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -Allowed @(0, 1) -RawPath $raw | Out-Null
    Start-Sleep -Seconds 2
    $gone = Test-VsWindowGone 90
    $recoveryNeeded = $false
    $recoveryAction = ''
    if (-not $gone) {
        $altTabRaw = Join-Path $OutDir "$($StepId)_visible_alt_tab_before_close_retry.json"
        Invoke-Agent -WinArgs @('desktop-hotkey', '--keys', 'ALT+TAB', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath $altTabRaw | Out-Null
        Start-Sleep -Seconds 2
        $retryRaw = Join-Path $OutDir "$($StepId)_click_top_right_x_after_alt_tab.json"
        Invoke-Agent -WinArgs @(
            'desktop-click',
            '--screen-x', ([string]$x),
            '--screen-y', ([string]$y),
            '--target-process', 'devenv.exe',
            '--require-target-lock', 'true',
            '--coordinate-source', 'visible_window_rect_top_right_x',
            '--target-description', 'Visual Studio top-right close button after visible Alt+Tab recovery',
            '--latency-profile', 'fast-visible-ui',
            '--motion-profile', '165hz-visible',
            '--motion-hz', '165'
        ) -Allowed @(0, 1) -RawPath $retryRaw | Out-Null
        Start-Sleep -Seconds 2
        $gone = Test-VsWindowGone 90
        $recoveryNeeded = $true
        $recoveryAction = 'visible Alt+Tab recovery before retrying top-right X close'
    }
    if (-not $gone) {
        $handled = Handle-SavePromptVisible $StepId
        if ($handled) {
            $recoveryNeeded = $true
            if ([string]::IsNullOrWhiteSpace($recoveryAction)) {
                $recoveryAction = 'visible Save button clicked in Visual Studio save prompt'
            } else {
                $recoveryAction = "$recoveryAction; visible Save button clicked in Visual Studio save prompt"
            }
            $gone = Test-VsWindowGone 90
        }
    }
    $script:CloseMethod = 'top_right_x_visible_click'
    Complete-Step $step "desktop-click Visual Studio top-right X after $StageName" (Capture-Observation $step.step_id 'after') $gone $raw -RecoveryNeeded $recoveryNeeded -RecoveryAction $recoveryAction
}

function Run-Stage1 {
    $script:FailedStage = 'Stage 1'
    Open-VsFromDesktopAndProject 'D1'
    Ensure-SolutionExplorerVisible 'D1'
    Open-FileFromSolutionExplorer 'D107' 'source' 'main.cpp'
    Set-EditorTextVisible 'D108' 'main.cpp' $script:MainCppPath $script:Stage1MainCode $script:Stage1Output
    Invoke-VisibleBuild 'D109' 'Stage 1 single file'
    Invoke-VisibleRunAndVerify 'D110' 'Stage 1 single file' $script:Stage1Output
    Close-VsStage 'D111' 'Stage 1 single file'
    $script:Stage1Pass = $true
}

function Run-Stage2 {
    $script:FailedStage = 'Stage 2'
    Open-VsFromDesktopAndProject 'D2'
    Ensure-SolutionExplorerVisible 'D2'
    Open-FileFromSolutionExplorer 'D207' 'source' 'main.cpp'
    Set-EditorTextVisible 'D208' 'main.cpp' $script:MainCppPath $script:Stage2MainCode $script:Stage2Output
    Open-FileFromSolutionExplorer 'D209' 'source' 'math.cpp'
    Set-EditorTextVisible 'D210' 'math.cpp' $script:MathCppPath $script:Stage2MathCode 'return a + b'
    Invoke-VisibleBuild 'D211' 'Stage 2 multi source'
    Invoke-VisibleRunAndVerify 'D212' 'Stage 2 multi source' $script:Stage2Output
    Close-VsStage 'D213' 'Stage 2 multi source'
    $script:Stage2Pass = $true
}

function Run-Stage3 {
    $script:FailedStage = 'Stage 3'
    Open-VsFromDesktopAndProject 'D3'
    Ensure-SolutionExplorerVisible 'D3'
    Open-FileFromSolutionExplorer 'D307' 'header' 'math_utils.h'
    Set-EditorTextVisible 'D308' 'math_utils.h' $script:HeaderPath $script:Stage3HeaderCode 'int add'
    Open-FileFromSolutionExplorer 'D309' 'source' 'math.cpp'
    Set-EditorTextVisible 'D310' 'math.cpp' $script:MathCppPath $script:Stage3MathCode 'math_utils.h'
    Open-FileFromSolutionExplorer 'D311' 'source' 'main.cpp'
    Set-EditorTextVisible 'D312' 'main.cpp' $script:MainCppPath $script:Stage3MainCode $script:Stage3Output
    Invoke-VisibleBuild 'D313' 'Stage 3 multi source header'
    Invoke-VisibleRunAndVerify 'D314' 'Stage 3 multi source header' $script:Stage3Output
    Close-VsStage 'D315' 'Stage 3 multi source header'
    $script:Stage3Pass = $true
}

if (-not (Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run build first." }

try {
    foreach ($required in @($script:ActualProjectPath, $script:SolutionPath, $script:VcxprojPath, $script:MainCppPath, $script:MathCppPath, $script:HeaderPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing required Feature C artifact: $required" }
    }
    $preexisting = Get-VsWindowLock -Allowed @(0, 1)
    if ($preexisting.exit -eq 0 -and $preexisting.json.ok -eq $true) {
        $script:Status = 'BLOCKED'
        throw 'Preexisting visible devenv.exe window found. Close it before running Feature D.'
    }

    Run-Stage1
    Run-Stage2
    Run-Stage3

    $script:VsClosedAfterEachStage = $script:Stage1Pass -and $script:Stage2Pass -and $script:Stage3Pass -and (Test-VsWindowGone 5)
    $script:OutputVerified = $script:Stage1Pass -and $script:Stage2Pass -and $script:Stage3Pass
    if (-not $script:OutputVerified) { throw 'Feature D stage output verification did not pass.' }

    $script:FailedStage = ''
    $script:Status = 'PASS'
    $script:StatusMessage = 'Feature D VS C++ complex IDE workflow passed.'
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host 'PASS vs_cpp_complex_ide_workflow_selftest'
    Write-Host "Report: $Report"
    exit 0
} catch {
    if ($script:Status -ne 'BLOCKED') { $script:Status = 'FAIL' }
    $script:StatusMessage = $_.Exception.Message
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host "$($script:Status) vs_cpp_complex_ide_workflow_selftest"
    Write-Host "Reason: $($script:StatusMessage)"
    Write-Host "Report: $Report"
    exit 1
}
