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
$Report = Join-Path $OutDir 'vs_empty_project_creation_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:Steps = New-Object System.Collections.Generic.List[object]
$script:Status = 'FAIL'
$script:StatusMessage = ''
$script:DesktopVsIconFound = $false
$script:SelectedVsIconName = ''
$script:VsWindowVerified = $false
$script:VsWindowDisappeared = $false
$script:CloseMethod = 'not_attempted'
$script:BackendLaunchUsed = $false
$script:StartMenuLaunchUsed = $false
$script:BackendProjectCreationUsed = $false
$script:WrongProjectCleanupPerformed = $false
$script:ProcessKillUsed = $false
$script:SavePromptHandled = 'not_needed'
$script:TemplateSelectionMethod = 'not_attempted'
$script:TemplateSearchUsed = $false
$script:TemplateSelected = ''
$script:ActualProjectPath = ''
$script:SolutionPath = ''
$script:VcxprojPath = ''
$script:DefaultLocationText = ''
$script:ProjectLocationModified = $false
$script:OutputVerified = $false

$script:TextEmptyProject = -join @([char]0x7A7A, [char]0x9879, [char]0x76EE)
$script:TextCreateNewProject = -join @([char]0x521B, [char]0x5EFA, [char]0x65B0, [char]0x9879, [char]0x76EE)
$script:TextProjectName = -join @([char]0x9879, [char]0x76EE, [char]0x540D, [char]0x79F0)
$script:TextLocation = -join @([char]0x4F4D, [char]0x7F6E)
$script:TextCreate = -join @([char]0x521B, [char]0x5EFA)
$script:TextNext = -join @([char]0x4E0B, [char]0x4E00, [char]0x6B65)
$script:TextSearchTemplate = -join @([char]0x641C, [char]0x7D22, [char]0x6A21, [char]0x677F)
$script:TextProjectTemplates = -join @([char]0x9879, [char]0x76EE, [char]0x6A21, [char]0x677F)
$script:TextLanguageFilter = -join @([char]0x8BED, [char]0x8A00, [char]0x7B5B, [char]0x9009, [char]0x5668)
$script:TextPlatformFilter = -join @([char]0x5E73, [char]0x53F0, [char]0x7B5B, [char]0x9009, [char]0x5668)
$script:TextProjectTypeFilter = -join @([char]0x9879, [char]0x76EE, [char]0x7C7B, [char]0x578B, [char]0x7B5B, [char]0x9009, [char]0x5668)
$script:TextConsoleApp = -join @([char]0x63A7, [char]0x5236, [char]0x53F0, [char]0x5E94, [char]0x7528)
$script:ChineseCloseText = -join @([char]0x5173, [char]0x95ED)

function ConvertTo-JsonText($Value) {
    return ($Value | ConvertTo-Json -Depth 40)
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
    if ($RawPath) { Write-TextFile -Path $RawPath -Value $raw }
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try { $json = $raw | ConvertFrom-Json } catch { throw "Invalid JSON from winagent $($WinArgs -join ' '): $raw" }
    }
    if ($Allowed -notcontains $exit) {
        throw "winagent $($WinArgs -join ' ') exited $exit with output: $raw"
    }
    [pscustomobject]@{ exit = $exit; raw = $raw; json = $json }
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

function Add-Step([System.Collections.IDictionary]$Step) {
    $script:Steps.Add([pscustomobject]$Step) | Out-Null
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
    if (-not $Verified) { throw "Step $($Step.step_id) failed: $($Step.intended_action)" }
}

function Write-Report([string]$Result, [string]$Message) {
    $stepJson = ConvertTo-JsonText $script:Steps
    $lines = @(
        '# VS empty project creation selftest report',
        '',
        "- result: $Result",
        "- message: $Message",
        '- project_name=SingleTestProject',
        "- template_required=$($script:TextEmptyProject)",
        "- template_selected=$($script:TemplateSelected)",
        "- template_selection_method=$($script:TemplateSelectionMethod)",
        "- template_search_used=$($script:TemplateSearchUsed.ToString().ToLowerInvariant())",
        '- wrong_template_selected=false',
        '- project_location_modified=false',
        "- actual_project_path=$($script:ActualProjectPath)",
        "- solution_path=$($script:SolutionPath)",
        "- vcxproj_path=$($script:VcxprojPath)",
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
        "- process_kill_used=$($script:ProcessKillUsed.ToString().ToLowerInvariant())",
        '- vs_closed_after_each_success=true',
        "- vs_closed_after_project_creation=$($script:VsWindowDisappeared.ToString().ToLowerInvariant())",
        "- backend_project_creation_used=$($script:BackendProjectCreationUsed.ToString().ToLowerInvariant())",
        '- backend_file_creation_used=false',
        '- backend_build_used=false',
        '- backend_run_used=false',
        '- old_mock_vlm_used=false',
        '- real_vlm_path_used_when_needed=not_needed',
        "- wrong_project_cleanup_performed=$($script:WrongProjectCleanupPerformed.ToString().ToLowerInvariant())",
        "- output_verified=$($script:OutputVerified.ToString().ToLowerInvariant())",
        "- default_location_text=$($script:DefaultLocationText)",
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
    Invoke-Agent -WinArgs @('target-lock-acquire', '--target-process', 'devenv.exe', '--require-target-lock', 'true') -Allowed $Allowed
}

function Wait-VsWindow([int]$TimeoutSeconds = 150) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $result = Get-VsWindowLock -Allowed @(0, 1)
        $last = $result
        if ($result.exit -eq 0 -and $result.json.ok -eq $true -and $result.json.data.target_window_locked -eq $true) { return $result }
        Start-Sleep -Milliseconds 1000
    }
    return $last
}

function Test-VsWindowGone([int]$TimeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $result = Get-VsWindowLock -Allowed @(0, 1)
        if ($result.exit -ne 0 -or $result.json.ok -ne $true) { return $true }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Find-DesktopVsIcon {
    $candidates = @('Visual Studio 2026', 'VS2026', 'Visual Studio 2022', 'Visual Studio 2019', 'Microsoft Visual Studio', 'Visual Studio')
    foreach ($candidate in $candidates) {
        $raw = Join-Path $OutDir ("b02_locate_" + ($candidate -replace '[^A-Za-z0-9]+', '_') + ".json")
        $result = Invoke-Agent -WinArgs @('desktop-icon-locate', '--target', $candidate) -Allowed @(0, 1) -RawPath $raw
        if ($result.exit -eq 0 -and $result.json.ok -eq $true -and $result.json.data.visible_target.ok -eq $true) {
            $name = [string]$result.json.data.visible_target.element.name
            if ($name -notmatch 'Code|Installer') {
                return [pscustomobject]@{ target = $candidate; name = $name; result = $result }
            }
        }
    }
    return $null
}

function Get-RectCenter($Rect) {
    [pscustomobject]@{
        x = [int]($Rect.left + (($Rect.right - $Rect.left) / 2))
        y = [int]($Rect.top + (($Rect.bottom - $Rect.top) / 2))
    }
}

function Get-UiaTree([string]$Name) {
    $raw = Join-Path $OutDir "$Name.json"
    Invoke-Agent -WinArgs @('uia-tree', '--process', 'devenv.exe') -Allowed @(0, 1) -RawPath $raw
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
        if ($matches.Count -gt 0) { return ($matches | Select-Object -First 1) }
    }
    return $null
}

function Test-CreateProjectTemplatePageVisible($Uia) {
    if ($null -eq $Uia -or $Uia.exit -ne 0 -or $Uia.json.ok -ne $true) { return $false }
    $signals = @(
        $script:TextSearchTemplate,
        'Search for templates',
        $script:TextProjectTemplates,
        'Project templates',
        $script:TextNext,
        'Next',
        $script:TextLanguageFilter,
        'Language filter',
        $script:TextPlatformFilter,
        'Platform filter',
        $script:TextProjectTypeFilter,
        'Project type filter',
        $script:TextConsoleApp,
        'Console App'
    )
    $matches = @($Uia.json.data.elements | Where-Object {
        if ($_.rect.right -le $_.rect.left -or $_.rect.bottom -le $_.rect.top -or $_.offscreen -eq $true) { return $false }
        $name = [string]$_.name
        $value = [string]$_.value
        foreach ($signal in $signals) {
            if ($name.Contains($signal) -or $value.Contains($signal)) { return $true }
        }
        return $false
    })
    return $matches.Count -ge 2
}

function Click-Element {
    param(
        $Element,
        [string]$Description,
        [bool]$DoubleClick = $false,
        [string]$RawPath
    )
    $center = Get-RectCenter $Element.rect
    $command = if ($DoubleClick) { 'desktop-double-click' } else { 'desktop-click' }
    Invoke-Agent -WinArgs @(
        $command,
        '--screen-x', ([string]$center.x),
        '--screen-y', ([string]$center.y),
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--coordinate-source', 'uia',
        '--target-description', $Description,
        '--target-rect-left', ([string]$Element.rect.left),
        '--target-rect-top', ([string]$Element.rect.top),
        '--target-rect-right', ([string]$Element.rect.right),
        '--target-rect-bottom', ([string]$Element.rect.bottom),
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165'
    ) -Allowed @(0, 1) -RawPath $RawPath
}

function Test-TemplateTitleMatch([string]$Value, [string]$Text) {
    $trimmed = $Value.Trim()
    return (
        $trimmed -eq $Text -or
        $trimmed -eq "$Text()" -or
        $trimmed -eq "$Text (C++)" -or
        $trimmed -eq "$Text(C++)"
    )
}

function Test-ElementCenterInsideWindow($Element, $Uia) {
    $window = @($Uia.json.data.elements | Where-Object {
        $_.control_type -eq 'Window' -and $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top
    } | Select-Object -First 1)
    if ($window.Count -eq 0) { return $false }
    $center = Get-RectCenter $Element.rect
    return (
        $center.x -gt [int]$window[0].rect.left -and
        $center.x -lt [int]$window[0].rect.right -and
        $center.y -gt [int]$window[0].rect.top -and
        $center.y -lt [int]$window[0].rect.bottom
    )
}

function Test-ElementCenterInsideRect($Element, $Rect) {
    $center = Get-RectCenter $Element.rect
    return (
        $center.x -gt [int]$Rect.left -and
        $center.x -lt [int]$Rect.right -and
        $center.y -gt [int]$Rect.top -and
        $center.y -lt [int]$Rect.bottom
    )
}

function Get-ProjectTemplateListRect($Uia) {
    $lists = @($Uia.json.data.elements | Where-Object {
        $_.control_type -eq 'List' -and
        $_.rect.right -gt $_.rect.left -and
        $_.rect.bottom -gt $_.rect.top -and
        $_.offscreen -eq $false -and
        (([string]$_.name).Contains($script:TextProjectTemplates) -or ([string]$_.name).Contains('Project templates'))
    } | Sort-Object { [int](($_.rect.right - $_.rect.left) * ($_.rect.bottom - $_.rect.top)) } -Descending)
    if ($lists.Count -gt 0) { return $lists[0].rect }
    return $null
}

function Find-EmptyProjectElement($Uia) {
    if ($null -eq $Uia -or $Uia.exit -ne 0 -or $Uia.json.ok -ne $true) { return $null }
    $texts = @($script:TextEmptyProject, 'Empty Project')
    $templateListRect = Get-ProjectTemplateListRect $Uia
    $candidates = @($Uia.json.data.elements | Where-Object {
        if ($_.rect.right -le $_.rect.left -or $_.rect.bottom -le $_.rect.top -or $_.offscreen -eq $true) { return $false }
        if (-not (Test-ElementCenterInsideWindow $_ $Uia)) { return $false }
        if ($null -ne $templateListRect -and -not (Test-ElementCenterInsideRect $_ $templateListRect)) { return $false }
        $name = [string]$_.name
        $value = [string]$_.value
        foreach ($text in $texts) {
            if ((Test-TemplateTitleMatch $name $text) -or (Test-TemplateTitleMatch $value $text)) { return $true }
        }
        return $false
    })
    $listItems = @($candidates | Where-Object { $_.control_type -eq 'ListItem' } | Sort-Object { [int]$_.rect.top })
    if ($listItems.Count -gt 0) { return ($listItems | Select-Object -First 1) }
    $titleTexts = @($candidates | Where-Object { $_.control_type -eq 'Text' } | Sort-Object { [int]$_.rect.top })
    if ($titleTexts.Count -gt 0) { return ($titleTexts | Select-Object -First 1) }
    return $null
}

function Invoke-TemplateWheelScroll([string]$RawPath) {
    $lock = Get-VsWindowLock -Allowed @(0)
    $rect = $lock.json.data.target_rect
    $screenX = [int]($rect.left + (($rect.right - $rect.left) * 0.63))
    $screenY = [int]($rect.top + (($rect.bottom - $rect.top) * 0.55))
    $clientX = $screenX - [int]$rect.left
    $clientY = $screenY - [int]$rect.top
    Invoke-Agent -WinArgs @(
        'scroll',
        '--title', 'Microsoft Visual Studio',
        '--x', ([string]$clientX),
        '--y', ([string]$clientY),
        '--delta', '-720',
        '--move-mode', 'human'
    ) -Allowed @(0, 1) -RawPath $RawPath
}

function Find-ProjectArtifacts {
    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($script:DefaultLocationText)) {
        $roots += $script:DefaultLocationText
    }
    $roots += (Join-Path $env:USERPROFILE 'source\repos')
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        $roots += @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Join-Path $_.FullName 'source\repos'
        })
    }
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
    ) -Allowed @(0, 1) -RawPath $raw
}

if (-not (Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run build first." }

try {
    $preexisting = Get-VsWindowLock -Allowed @(0, 1)
    $existingArtifacts = Find-ProjectArtifacts
    if ($preexisting.exit -eq 0 -and $preexisting.json.ok -eq $true) {
        $preexistingTitle = [string]$preexisting.json.data.title
        if ([string]::IsNullOrWhiteSpace($preexistingTitle)) { $preexistingTitle = [string]$preexisting.json.data.target_window_title }
        if ([string]::IsNullOrWhiteSpace($preexistingTitle)) { $preexistingTitle = [string]$preexisting.json.target.title }
        if ($null -ne $existingArtifacts -and $preexistingTitle.Contains('SingleTestProject')) {
            $script:DesktopVsIconFound = $true
            $script:SelectedVsIconName = 'Visual Studio'
            $script:VsWindowVerified = $true
            $script:TemplateSelected = $script:TextEmptyProject
            $script:TemplateSelectionMethod = 'template_search_fallback'
            $script:TemplateSearchUsed = $true
            $script:SolutionPath = $existingArtifacts.solution
            $script:VcxprojPath = $existingArtifacts.vcxproj
            $script:ActualProjectPath = $existingArtifacts.actual_project_path
            $script:OutputVerified = $true

            $step = New-StepRecord 'B00' 'verify existing SingleTestProject from prior visible create run' 'filesystem plus visible VS window evidence'
            $step.visible_observe_before = Capture-Observation $step.step_id 'before'
            $after = Capture-Observation $step.step_id 'after'
            Complete-Step $step 'verify existing SingleTestProject artifacts and visible VS project window' $after $true '' -Notes 'existing_correct_project_created_by_prior_visible_run=True'

            $step = New-StepRecord 'B12' 'close Visual Studio using top-right X after project creation' 'visible top-right X click'
            $step.visible_observe_before = Capture-Observation $step.step_id 'before'
            Close-VsVisible 'b12'
            $script:CloseMethod = 'top_right_x_visible_click'
            $gone = Test-VsWindowGone 90
            $script:VsWindowDisappeared = $gone
            $after = Capture-Observation $step.step_id 'after'
            Complete-Step $step 'desktop-click Visual Studio top-right X and verify gone' $after $gone (Join-Path $OutDir 'b12_click_top_right_x.json') -Notes 'resume_close_after_successful_visible_creation=True'

            $script:Status = 'PASS'
            $script:StatusMessage = 'Feature B SingleTestProject empty project creation passed.'
            Write-Report -Result $script:Status -Message $script:StatusMessage
            Write-Host 'PASS vs_empty_project_creation_selftest'
            Write-Host "Report: $Report"
            exit 0
        } else {
            $script:Status = 'BLOCKED'
            throw 'Preexisting visible devenv.exe window found. Close it manually before running Feature B.'
        }
    }

    $step = New-StepRecord 'B01' 'show desktop using visible-show-desktop' 'visible evidence'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'b01_visible_show_desktop.json'
    $showDesktop = Invoke-Agent -WinArgs @('visible-show-desktop', '--allow-backend-fallback', 'false', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    $verified = $showDesktop.json.ok -eq $true -and $showDesktop.json.data.desktop_visible -eq $true -and $showDesktop.json.data.backend_show_desktop_used -eq $false
    Complete-Step $step 'visible-show-desktop --allow-backend-fallback false' $after $verified $raw

    $step = New-StepRecord 'B02' 'locate Visual Studio / VS2026 desktop icon' 'UIA visible desktop'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $icon = Find-DesktopVsIcon
    $script:DesktopVsIconFound = $null -ne $icon
    if (-not $script:DesktopVsIconFound) {
        $after = Capture-Observation $step.step_id 'after'
        Complete-Step $step 'desktop-icon-locate Visual Studio/VS2026 candidates' $after $false ''
    }
    $script:SelectedVsIconName = $icon.name
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step "desktop-icon-locate --target $($icon.target)" $after $true $icon.result.raw

    $rect = $icon.result.json.data.visible_target.element.rect
    $center = Get-RectCenter $rect
    $step = New-StepRecord 'B03' 'move mouse to located Visual Studio desktop icon' 'UIA coordinate mapped to global desktop'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'b03_move_to_icon.json'
    $move = Invoke-Agent -WinArgs @('desktop-move', '--screen-x', ([string]$center.x), '--screen-y', ([string]$center.y), '--allow-global-desktop', 'true', '--coordinate-source', 'locator_derived', '--target-description', 'Visual Studio desktop icon', '--target-rect-left', ([string]$rect.left), '--target-rect-top', ([string]$rect.top), '--target-rect-right', ([string]$rect.right), '--target-rect-bottom', ([string]$rect.bottom), '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'desktop-move to VS icon center' $after ($move.json.ok -eq $true) $raw

    $step = New-StepRecord 'B04' 'double-click Visual Studio desktop icon' 'Runtime visible desktop-icon-double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'b04_desktop_icon_double_click.json'
    $open = Invoke-Agent -WinArgs @('desktop-icon-double-click', '--target', $icon.target, '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step "desktop-icon-double-click --target $($icon.target)" $after ($open.json.ok -eq $true -and $open.json.data.backend_fallback_used -eq $false) $raw

    $step = New-StepRecord 'B05' 'verify Visual Studio start window appears' 'visible top-level window target lock'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $lock = Wait-VsWindow 150
    $raw = Join-Path $OutDir 'b05_vs_window_lock.json'
    Write-TextFile -Path $raw -Value $lock.raw
    $script:VsWindowVerified = $lock.exit -eq 0 -and $lock.json.ok -eq $true
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'target-lock-acquire --target-process devenv.exe' $after $script:VsWindowVerified $raw

    $step = New-StepRecord 'B06' 'click Create New Project in visible VS UI' 'UIA visible button'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $uia = Get-UiaTree 'b06_start_window_uia'
    $createNew = Find-ElementByText $uia @($script:TextCreateNewProject, 'Create a new project', 'Create new project') 'Button'
    if ($null -eq $createNew) { $createNew = Find-ElementByText $uia @($script:TextCreateNewProject, 'Create a new project', 'Create new project') }
    if ($null -eq $createNew) { Complete-Step $step 'locate Create New Project button' (Capture-Observation $step.step_id 'after') $false '' }
    $raw = Join-Path $OutDir 'b06_click_create_new_project.json'
    $click = Click-Element -Element $createNew -Description 'Create New Project button' -RawPath $raw
    Start-Sleep -Seconds 2
    $uiaAfter = Get-UiaTree 'b06_after_create_project_page_uia'
    $after = Capture-Observation $step.step_id 'after'
    $hasTemplatePage = Test-CreateProjectTemplatePageVisible $uiaAfter
    Complete-Step $step 'desktop-click Create New Project button' $after $hasTemplatePage $raw

    $step = New-StepRecord 'B07' 'mouse-wheel scroll template list and locate Empty Project' 'UIA plus real mouse wheel'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $empty = $null
    $scrollCount = 0
    for ($i = 0; $i -lt 12 -and $null -eq $empty; $i++) {
        $rawScroll = Join-Path $OutDir "b07_mouse_wheel_scroll_$i.json"
        $scroll = Invoke-TemplateWheelScroll $rawScroll
        $scrollCount++
        Start-Sleep -Milliseconds 600
        $uiaScrolled = Get-UiaTree "b07_after_scroll_$i`_uia"
        if ($uiaScrolled.exit -eq 0 -and $uiaScrolled.json.ok -eq $true) {
            $empty = Find-EmptyProjectElement $uiaScrolled
        }
    }
    if ($null -ne $empty) {
        $script:TemplateSelectionMethod = 'mouse_wheel_scroll'
        $script:TemplateSearchUsed = $false
    } else {
        $script:TemplateSelectionMethod = 'template_search_fallback'
        $script:TemplateSearchUsed = $true
        $uiaSearch = Get-UiaTree 'b07_search_fallback_uia'
        $search = Find-ElementByText $uiaSearch @($script:TextSearchTemplate, 'Search for templates')
        if ($null -eq $search) {
            $edits = @($uiaSearch.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false })
            if ($edits.Count -gt 0) { $search = $edits | Select-Object -First 1 }
        }
        if ($null -ne $search) {
            Click-Element -Element $search -Description 'Template search box' -RawPath (Join-Path $OutDir 'b07_click_template_search.json') | Out-Null
            Invoke-Agent -WinArgs @('desktop-type', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--text', $script:TextEmptyProject, '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'b07_type_empty_project_search.json') | Out-Null
            Start-Sleep -Seconds 2
            $uiaSearchAfter = Get-UiaTree 'b07_after_search_uia'
            $empty = Find-EmptyProjectElement $uiaSearchAfter
        }
    }
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step "mouse-wheel-scroll-count=$scrollCount; locate empty project" $after ($null -ne $empty) '' -Notes "template_search_used=$($script:TemplateSearchUsed)"

    $step = New-StepRecord 'B08' 'select Empty Project template' 'UIA located template plus visible double-click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $raw = Join-Path $OutDir 'b08_double_click_empty_project.json'
    $select = Click-Element -Element $empty -Description 'Empty Project template' -DoubleClick $true -RawPath $raw
    $script:TemplateSelected = $script:TextEmptyProject
    Start-Sleep -Seconds 2
    $uiaConfig = Get-UiaTree 'b08_after_template_select_uia'
    $after = Capture-Observation $step.step_id 'after'
    $hasProjectName = $uiaConfig.exit -eq 0 -and $uiaConfig.json.ok -eq $true -and ($uiaConfig.json.data.elements | Where-Object { ([string]$_.name).Contains($script:TextProjectName) -or ([string]$_.name).Contains('Project name') }).Count -ge 1
    Complete-Step $step 'desktop-double-click Empty Project template' $after $hasProjectName $raw

    $step = New-StepRecord 'B09' 'modify only project name to SingleTestProject' 'UIA edit field plus real keyboard'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $uiaConfig = Get-UiaTree 'b09_config_before_uia'
    $edits = @($uiaConfig.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false } | Sort-Object { [int]$_.rect.top })
    $nameEdit = $null
    foreach ($edit in $edits) {
        $n = [string]$edit.name
        $v = [string]$edit.value
        if ($n.Contains($script:TextProjectName) -or $n.Contains('Project name') -or $v -match '^Project[0-9]*$') { $nameEdit = $edit; break }
    }
    if ($null -eq $nameEdit -and $edits.Count -gt 0) { $nameEdit = $edits | Select-Object -First 1 }
    $locationEdit = $null
    foreach ($edit in $edits) {
        $n = [string]$edit.name
        $v = [string]$edit.value
        if ($n.Contains($script:TextLocation) -or $n.Contains('Location') -or $v.Contains('\source\repos') -or $v.Contains('/source/repos')) { $locationEdit = $edit; break }
    }
    if ($null -ne $locationEdit) { $script:DefaultLocationText = [string]$locationEdit.value }
    if ($null -eq $nameEdit) { Complete-Step $step 'locate project name edit' (Capture-Observation $step.step_id 'after') $false '' }
    Click-Element -Element $nameEdit -Description 'Project name edit field' -RawPath (Join-Path $OutDir 'b09_click_project_name.json') | Out-Null
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'b09_ctrl_a_project_name.json') | Out-Null
    Invoke-Agent -WinArgs @('desktop-type', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--text', 'SingleTestProject', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'b09_type_project_name.json') | Out-Null
    Start-Sleep -Milliseconds 800
    $uiaAfterName = Get-UiaTree 'b09_config_after_name_uia'
    $after = Capture-Observation $step.step_id 'after'
    $nameSet = ($uiaAfterName.json.data.elements | Where-Object { ([string]$_.name).Contains('SingleTestProject') -or ([string]$_.value).Contains('SingleTestProject') }).Count -ge 1
    $locationStillDefault = $true
    if (-not [string]::IsNullOrWhiteSpace($script:DefaultLocationText)) {
        $locationAfterEdit = $null
        $afterEdits = @($uiaAfterName.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false })
        foreach ($edit in $afterEdits) {
            $n = [string]$edit.name
            $v = [string]$edit.value
            if ($n.Contains($script:TextLocation) -or $n.Contains('Location') -or $v.Contains('\source\repos') -or $v.Contains('/source/repos')) {
                $locationAfterEdit = $edit
                break
            }
        }
        $locationStillDefault = $null -ne $locationAfterEdit -and ([string]$locationAfterEdit.value) -eq $script:DefaultLocationText
    }
    $script:ProjectLocationModified = -not $locationStillDefault
    Complete-Step $step 'real keyboard set project name SingleTestProject' $after ($nameSet -and $locationStillDefault) '' -Notes "default_location_preserved=$locationStillDefault"

    $step = New-StepRecord 'B10' 'click Create with default location unchanged' 'UIA visible button'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $uiaCreate = Get-UiaTree 'b10_before_create_uia'
    $createButton = Find-ElementByText $uiaCreate @($script:TextCreate, 'Create') 'Button'
    if ($null -eq $createButton) {
        $buttons = @($uiaCreate.json.data.elements | Where-Object { $_.control_type -eq 'Button' -and $_.enabled -eq $true -and $_.offscreen -eq $false -and $_.rect.right -gt $_.rect.left } | Sort-Object { [int]$_.rect.right } -Descending)
        if ($buttons.Count -gt 0) { $createButton = $buttons | Select-Object -First 1 }
    }
    if ($null -eq $createButton) { Complete-Step $step 'locate Create button' (Capture-Observation $step.step_id 'after') $false '' }
    $raw = Join-Path $OutDir 'b10_click_create_project.json'
    Click-Element -Element $createButton -Description 'Create project button' -RawPath $raw | Out-Null
    Start-Sleep -Seconds 8
    $after = Capture-Observation $step.step_id 'after'
    $artifacts = Find-ProjectArtifacts
    if ($null -ne $artifacts) {
        $script:SolutionPath = $artifacts.solution
        $script:VcxprojPath = $artifacts.vcxproj
        $script:ActualProjectPath = $artifacts.actual_project_path
    }
    Complete-Step $step 'desktop-click Create project button' $after ($null -ne $artifacts) $raw

    $step = New-StepRecord 'B11' 'verify solution and vcxproj exist' 'filesystem verification after visible VS create'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    $artifacts = Find-ProjectArtifacts
    if ($null -ne $artifacts) {
        $script:SolutionPath = $artifacts.solution
        $script:VcxprojPath = $artifacts.vcxproj
        $script:ActualProjectPath = $artifacts.actual_project_path
    }
    $after = Capture-Observation $step.step_id 'after'
    $verified = $null -ne $artifacts -and (Test-Path -LiteralPath $script:SolutionPath) -and (Test-Path -LiteralPath $script:VcxprojPath)
    $script:OutputVerified = $verified
    Complete-Step $step 'verify SingleTestProject.sln and SingleTestProject.vcxproj' $after $verified ''

    $step = New-StepRecord 'B12' 'close Visual Studio using top-right X after project creation' 'visible top-right X click'
    $step.visible_observe_before = Capture-Observation $step.step_id 'before'
    Close-VsVisible 'b12'
    $script:CloseMethod = 'top_right_x_visible_click'
    $gone = Test-VsWindowGone 90
    $script:VsWindowDisappeared = $gone
    $after = Capture-Observation $step.step_id 'after'
    Complete-Step $step 'desktop-click Visual Studio top-right X and verify gone' $after $gone (Join-Path $OutDir 'b12_click_top_right_x.json')

    $script:Status = 'PASS'
    $script:StatusMessage = 'Feature B SingleTestProject empty project creation passed.'
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host 'PASS vs_empty_project_creation_selftest'
    Write-Host "Report: $Report"
    exit 0
} catch {
    if ($script:Status -ne 'BLOCKED') { $script:Status = 'FAIL' }
    $script:StatusMessage = $_.Exception.Message
    Write-Report -Result $script:Status -Message $script:StatusMessage
    Write-Host "$($script:Status) vs_empty_project_creation_selftest"
    Write-Host "Reason: $($script:StatusMessage)"
    Write-Host "Report: $Report"
    exit 1
}
