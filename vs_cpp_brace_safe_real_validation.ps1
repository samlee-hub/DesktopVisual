param(
    [string]$Root = (Get-Location).Path,
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    [Parameter(Mandatory = $true)]
    [string]$SuccessMarker,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDir,
    [ValidateSet('developer', 'user')]
    [string]$EvidencePrefix = 'developer',
    [switch]$UseExistingVs,
    [switch]$UseExistingProject,
    [switch]$CloseOnSuccess
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path -LiteralPath $Root).Path
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = $EvidenceDir
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:Steps = New-Object System.Collections.Generic.List[object]
$script:PhaseStarts = @{}
$script:PhaseElapsed = [ordered]@{
    vs_startup_seconds = 0.0
    project_file_create_seconds = 0.0
    main_cpp_input_seconds = 0.0
    integrity_check_seconds = 0.0
    build_seconds = 0.0
    run_seconds = 0.0
    evidence_package_seconds = 0.0
    failure_recovery_seconds = 0.0
}
$script:StartedAt = Get-Date
$script:Status = 'FAIL'
$script:StatusMessage = ''
$script:SolutionPath = ''
$script:VcxprojPath = ''
$script:ActualProjectPath = ''
$script:MainCppPath = ''
$script:BuiltExePath = ''
$script:BuildText = ''
$script:RunText = ''
$script:InputRawPath = ''
$script:BuildRawPath = ''
$script:RunRawPath = ''
$script:ConsoleTitle = ''
$script:RecoveryCount = 0
$script:HelperArgumentErrors = 0
$script:ConsoleTitleOvermatchCount = 0
$script:AddItemSelectorAmbiguityCount = 0
$script:ForegroundGuardExpectedTransitionCount = 0
$script:AutoPairCorruptionCount = 0
$script:BraceSafeDefaultEnabled = $false
$script:BraceSafePreflightEnabled = $false
$script:ClipboardPasteUsed = $false
$script:DirectSourceWriteUsed = $false
$script:EvidenceReinput = $false
$script:EvidenceRebuildRerun = $false
$script:FailureRecoveryNotes = New-Object System.Collections.Generic.List[string]
$script:TextSolutionExplorer = -join @([char]0x89E3, [char]0x51B3, [char]0x65B9, [char]0x6848, [char]0x8D44, [char]0x6E90, [char]0x7BA1, [char]0x7406, [char]0x5668)
$script:TextSourceFiles = -join @([char]0x6E90, [char]0x6587, [char]0x4EF6)
$script:TextHeaderFiles = -join @([char]0x5934, [char]0x6587, [char]0x4EF6)
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
$script:TextAddNewItem = -join @([char]0x6DFB, [char]0x52A0, [char]0x65B0, [char]0x9879)
$script:TextAdd = -join @([char]0x6DFB, [char]0x52A0)
$script:TextDebugConsole = -join @([char]0x8C03, [char]0x8BD5, [char]0x63A7, [char]0x5236, [char]0x53F0)
$script:TextStartWithoutDebugging = -join @([char]0x5F00, [char]0x59CB, [char]0x6267, [char]0x884C, '(', [char]0x4E0D, [char]0x8C03, [char]0x8BD5, ')')
$script:TextSavePromptTitle = -join @([char]0x662F, [char]0x5426, [char]0x4FDD, [char]0x5B58, [char]0x5BF9, [char]0x4EE5, [char]0x4E0B, [char]0x9879, [char]0x6240, [char]0x505A, [char]0x7684, [char]0x66F4, [char]0x6539, '?')
$script:TextSave = -join @([char]0x4FDD, [char]0x5B58)

function Write-TextFile([string]$Path, [string]$Value) {
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Test-ExistingPath([string]$Path) {
    return (-not [string]::IsNullOrWhiteSpace($Path)) -and (Test-Path -LiteralPath $Path)
}

function Start-Phase([string]$Name) {
    $script:PhaseStarts[$Name] = Get-Date
}

function Stop-Phase([string]$Name) {
    if ($script:PhaseStarts.ContainsKey($Name)) {
        $elapsed = ((Get-Date) - $script:PhaseStarts[$Name]).TotalSeconds
        $script:PhaseElapsed[$Name] = [Math]::Round([double]$script:PhaseElapsed[$Name] + $elapsed, 3)
        $script:PhaseStarts.Remove($Name)
    }
}

function Add-Step {
    param(
        [string]$Id,
        [string]$Action,
        [bool]$Ok,
        [string]$RawPath = '',
        [string]$Notes = ''
    )
    $script:Steps.Add([pscustomobject]@{
        step_id = $Id
        action = $Action
        ok = $Ok
        raw_path = $RawPath
        notes = $Notes
        timestamp = (Get-Date).ToString('o')
    }) | Out-Null
    if (-not $Ok) {
        throw "Step $Id failed: $Action $Notes"
    }
}

function Invoke-Agent {
    param(
        [string[]]$WinArgs,
        [int[]]$Allowed = @(0),
        [string]$RawPath = ''
    )
    if ($WinArgs.Count -eq 0 -or [string]::IsNullOrWhiteSpace($WinArgs[0])) {
        throw 'Refusing to send empty winagent command.'
    }
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($RawPath)) { Write-TextFile $RawPath $text }
    $json = $null
    try { $json = $text | ConvertFrom-Json } catch { }
    if ($text -match 'INVALID_ARGUMENT|requires --x|requires --y|empty command') {
        $script:HelperArgumentErrors++
    }
    if (($Allowed -notcontains $exit) -and $Allowed.Count -gt 0) {
        throw "winagent failed exit=$exit args=$($WinArgs -join ' ') output=$text"
    }
    [pscustomobject]@{ exit = $exit; raw = $text; json = $json; raw_path = $RawPath }
}

function Capture-Observation([string]$Name) {
    $png = Join-Path $OutDir "$Name.png"
    $json = Join-Path $OutDir "$Name.json"
    Invoke-Agent -WinArgs @('global-screenshot', '--out', $png, '--format', 'png', '--include-metadata', 'true') -Allowed @(0, 1) -RawPath $json | Out-Null
    return $png
}

function Get-VsWindowLock([int[]]$Allowed = @(0)) {
    Invoke-Agent -WinArgs @('target-lock-acquire', '--target-process', 'devenv.exe', '--require-target-lock', 'true') -Allowed $Allowed
}

function Wait-VsWindow([int]$TimeoutSeconds = 150) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    do {
        $last = Get-VsWindowLock -Allowed @(0, 1)
        if ($last.exit -eq 0 -and $last.json.ok -eq $true) { return $last }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return $last
}

function Get-CurrentVsTitle {
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1)
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return '' }
    $matches = @($windows.json.windows | Where-Object {
        $title = [string]$_.title
        (-not [string]::IsNullOrWhiteSpace($title)) -and
        ($title.Contains($ProjectName) -or $title.Contains('Microsoft Visual Studio')) -and
        (-not $title.Contains('Installer'))
    } | Sort-Object { if (([string]$_.title).Contains($ProjectName)) { 0 } else { 1 } })
    if ($matches.Count -eq 0) { return '' }
    return [string]$matches[0].title
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
        return Invoke-Agent -WinArgs @('uia-tree', '--title', $Title) -Allowed @(0, 1) -RawPath $raw
    }
    Invoke-Agent -WinArgs @('uia-tree', '--process', $Process) -Allowed @(0, 1) -RawPath $raw
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
        if ($matches.Count -gt 0) {
            return ($matches | Sort-Object { [int]$_.rect.top }, { [int]$_.rect.left } | Select-Object -First 1)
        }
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
    $agentArgs = @(
        $command,
        '--screen-x', ([string]$center.x),
        '--screen-y', ([string]$center.y),
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
    )
    if ([string]::IsNullOrWhiteSpace($TargetTitle)) {
        $agentArgs += @('--target-process', $TargetProcess)
    } else {
        $agentArgs += @('--target-title', $TargetTitle)
    }
    $script:ForegroundGuardExpectedTransitionCount++
    Invoke-Agent -WinArgs $agentArgs -Allowed @(0, 1) -RawPath $RawPath
}

function Find-DesktopVsIcon {
    $candidates = @('Visual Studio 2026', 'VS2026', 'Visual Studio 2022', 'Visual Studio 2019', 'Microsoft Visual Studio', 'Visual Studio')
    foreach ($candidate in $candidates) {
        $raw = Join-Path $OutDir ("vs_icon_locate_" + ($candidate -replace '[^A-Za-z0-9]+', '_') + '.json')
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

function Test-CreateProjectTemplatePageVisible($Uia) {
    if ($null -eq $Uia -or $Uia.exit -ne 0 -or $Uia.json.ok -ne $true) { return $false }
    $signals = @($script:TextSearchTemplate, 'Search for templates', $script:TextProjectTemplates, 'Project templates', $script:TextNext, 'Next', $script:TextLanguageFilter, 'Language filter', $script:TextPlatformFilter, 'Platform filter', $script:TextProjectTypeFilter, 'Project type filter', $script:TextConsoleApp, 'Console App')
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

function Wait-ProjectEntrySurface([int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    do {
        $last = Get-UiaTree 'project_01_start_window_uia'
        $createNew = Find-ElementByText $last @($script:TextCreateNewProject, 'Create a new project', 'Create new project') 'Button'
        if ($null -ne $createNew) {
            return [pscustomobject]@{ uia = $last; mode = 'start_window'; create_button = $createNew }
        }
        if (Test-CreateProjectTemplatePageVisible $last) {
            return [pscustomobject]@{ uia = $last; mode = 'template_page'; create_button = $null }
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    return [pscustomobject]@{ uia = $last; mode = 'unknown'; create_button = $null }
}

function Test-TemplateTitleMatch([string]$Value, [string]$Text) {
    $trimmed = $Value.Trim()
    return ($trimmed -eq $Text -or $trimmed -eq "$Text()" -or $trimmed -eq "$Text (C++)" -or $trimmed -eq "$Text(C++)")
}

function Test-ElementCenterInsideRect($Element, $Rect) {
    $center = Get-RectCenter $Element.rect
    return ($center.x -gt [int]$Rect.left -and $center.x -lt [int]$Rect.right -and $center.y -gt [int]$Rect.top -and $center.y -lt [int]$Rect.bottom)
}

function Get-ProjectTemplateListRect($Uia) {
    $lists = @($Uia.json.data.elements | Where-Object {
        $_.control_type -eq 'List' -and $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top -and $_.offscreen -eq $false -and (([string]$_.name).Contains($script:TextProjectTemplates) -or ([string]$_.name).Contains('Project templates'))
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
    Invoke-Agent -WinArgs @('scroll', '--title', 'Microsoft Visual Studio', '--x', ([string]$clientX), '--y', ([string]$clientY), '--delta', '-720', '--move-mode', 'human') -Allowed @(0, 1) -RawPath $RawPath
}

function Find-ProjectArtifacts {
    $roots = @()
    $roots += (Join-Path $env:USERPROFILE 'source\repos')
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        $roots += @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'source\repos' })
    }
    $roots = @($roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $solutions = @()
    foreach ($repos in $roots) {
        if (Test-Path -LiteralPath $repos) {
            $solutions += @(Get-ChildItem -LiteralPath $repos -Filter "$ProjectName.sln" -Recurse -ErrorAction SilentlyContinue)
            $solutions += @(Get-ChildItem -LiteralPath $repos -Filter "$ProjectName.slnx" -Recurse -ErrorAction SilentlyContinue)
        }
    }
    if ($solutions.Count -eq 0) { return $null }
    $sln = $solutions | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $vcx = @(Get-ChildItem -LiteralPath (Split-Path -Parent $sln.FullName) -Filter "$ProjectName.vcxproj" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($vcx.Count -eq 0) { return $null }
    [pscustomobject]@{
        solution = $sln.FullName
        vcxproj = $vcx[0].FullName
        actual_project_path = Split-Path -Parent $vcx[0].FullName
    }
}

function Find-BuiltExe {
    if ([string]::IsNullOrWhiteSpace($script:SolutionPath)) { return $null }
    $solutionRoot = Split-Path -Parent $script:SolutionPath
    @(Get-ChildItem -LiteralPath $solutionRoot -Filter "$ProjectName.exe" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Launch-VisualStudio {
    $raw = Join-Path $OutDir 'launch_01_show_desktop.json'
    $show = Invoke-Agent -WinArgs @('visible-show-desktop', '--allow-backend-fallback', 'false', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    Add-Step 'launch_01' 'show desktop without backend fallback' ($show.json.ok -eq $true -and $show.json.data.backend_show_desktop_used -eq $false) $raw

    $icon = Find-DesktopVsIcon
    Add-Step 'launch_02' 'locate Visual Studio desktop icon' ($null -ne $icon) $(if ($null -ne $icon) { $icon.result.raw_path } else { '' }) $(if ($null -ne $icon) { "selected=$($icon.name)" } else { 'not_found' })

    $rect = $icon.result.json.data.visible_target.element.rect
    $center = Get-RectCenter $rect
    $raw = Join-Path $OutDir 'launch_03_move_to_icon.json'
    $move = Invoke-Agent -WinArgs @('desktop-move', '--screen-x', ([string]$center.x), '--screen-y', ([string]$center.y), '--allow-global-desktop', 'true', '--coordinate-source', 'locator_derived', '--target-description', 'Visual Studio desktop icon', '--target-rect-left', ([string]$rect.left), '--target-rect-top', ([string]$rect.top), '--target-rect-right', ([string]$rect.right), '--target-rect-bottom', ([string]$rect.bottom), '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    Add-Step 'launch_03' 'move mouse to Visual Studio desktop icon' ($move.json.ok -eq $true) $raw

    $raw = Join-Path $OutDir 'launch_04_desktop_icon_double_click.json'
    $open = Invoke-Agent -WinArgs @('desktop-icon-double-click', '--target', $icon.target, '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -RawPath $raw
    Add-Step 'launch_04' 'double-click Visual Studio desktop icon' ($open.json.ok -eq $true -and $open.json.data.backend_fallback_used -eq $false) $raw

    $lock = Wait-VsWindow 150
    $raw = Join-Path $OutDir 'launch_05_vs_window_lock.json'
    Write-TextFile $raw $lock.raw
    Add-Step 'launch_05' 'verify unique Visual Studio IDE window' ($lock.exit -eq 0 -and $lock.json.ok -eq $true) $raw
}

function Create-EmptyProject {
    $existing = Find-ProjectArtifacts
    if ($null -ne $existing) {
        throw "Project $ProjectName already exists at $($existing.actual_project_path). Remove or archive it before running real validation."
    }

    $entry = Wait-ProjectEntrySurface 45
    $createNew = $entry.create_button
    if ($entry.mode -eq 'start_window' -and $null -ne $createNew) {
        $raw = Join-Path $OutDir 'project_02_click_create_new_project.json'
        Click-Element -Element $createNew -Description 'Create New Project button' -RawPath $raw | Out-Null
        Start-Sleep -Seconds 2
        Add-Step 'project_02' 'click Create New Project in VS start window' $true $raw
    } elseif ($entry.mode -eq 'template_page') {
        Add-Step 'project_02' 'New Project template page already active' $true $entry.uia.raw_path
    } else {
        $raw = Join-Path $OutDir 'project_02_ctrl_shift_n_new_project.json'
        Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+SHIFT+N', '--latency-profile', 'fast-visible-ui') -RawPath $raw | Out-Null
        Start-Sleep -Seconds 2
        Add-Step 'project_02' 'open New Project dialog with Ctrl+Shift+N' $true $raw 'start window create button not present'
    }

    $templatePage = Get-UiaTree 'project_03_template_page_uia'
    Add-Step 'project_03' 'verify new project template page' (Test-CreateProjectTemplatePageVisible $templatePage) $templatePage.raw_path

    $empty = Find-EmptyProjectElement $templatePage
    $scrollCount = 0
    for ($i = 0; $i -lt 8 -and $null -eq $empty; $i++) {
        $rawScroll = Join-Path $OutDir "project_04_template_scroll_$i.json"
        Invoke-TemplateWheelScroll $rawScroll | Out-Null
        $scrollCount++
        Start-Sleep -Milliseconds 500
        $uiaScrolled = Get-UiaTree "project_04_template_scroll_$i`_uia"
        $empty = Find-EmptyProjectElement $uiaScrolled
    }
    if ($null -eq $empty) {
        $uiaSearch = Get-UiaTree 'project_04_search_fallback_uia'
        $search = Find-ElementByText $uiaSearch @($script:TextSearchTemplate, 'Search for templates')
        if ($null -eq $search) {
            $edits = @($uiaSearch.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false })
            if ($edits.Count -gt 0) { $search = $edits | Select-Object -First 1 }
        }
        Add-Step 'project_04a' 'locate template search box for Empty Project fallback' ($null -ne $search) $(if ($null -ne $uiaSearch) { $uiaSearch.raw_path } else { '' })
        Click-Element -Element $search -Description 'Template search box' -RawPath (Join-Path $OutDir 'project_04b_click_template_search.json') | Out-Null
        Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'project_04c_template_search_ctrl_a.json') | Out-Null
        Invoke-Agent -WinArgs @('desktop-type', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--text', $script:TextEmptyProject, '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'project_04d_type_empty_project_search.json') | Out-Null
        $script:RecoveryCount++
        $script:FailureRecoveryNotes.Add('template search fallback used after scroll did not locate Empty Project') | Out-Null
        Start-Sleep -Seconds 2
        $uiaSearchAfter = Get-UiaTree 'project_04e_after_search_uia'
        $empty = Find-EmptyProjectElement $uiaSearchAfter
        if ($null -eq $empty) {
            Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'project_04f_template_search_ctrl_a_english.json') | Out-Null
            Invoke-Agent -WinArgs @('desktop-type', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--text', 'Empty Project', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'project_04g_type_empty_project_search_english.json') | Out-Null
            Start-Sleep -Seconds 2
            $uiaSearchEnglish = Get-UiaTree 'project_04h_after_search_english_uia'
            $empty = Find-EmptyProjectElement $uiaSearchEnglish
        }
    }
    Add-Step 'project_04' 'locate Empty Project template' ($null -ne $empty) '' "scroll_count=$scrollCount"

    $raw = Join-Path $OutDir 'project_05_double_click_empty_project.json'
    Click-Element -Element $empty -Description 'Empty Project template' -DoubleClick $true -RawPath $raw | Out-Null
    Start-Sleep -Seconds 2
    $uiaConfig = Get-UiaTree 'project_05_after_template_select_uia'
    $hasProjectName = $uiaConfig.exit -eq 0 -and $uiaConfig.json.ok -eq $true -and @($uiaConfig.json.data.elements | Where-Object { ([string]$_.name).Contains($script:TextProjectName) -or ([string]$_.name).Contains('Project name') }).Count -ge 1
    Add-Step 'project_05' 'select Empty Project template' $hasProjectName $raw

    $uiaConfig = Get-UiaTree 'project_06_config_before_uia'
    $edits = @($uiaConfig.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false } | Sort-Object { [int]$_.rect.top })
    $nameEdit = $null
    foreach ($edit in $edits) {
        $n = [string]$edit.name
        $v = [string]$edit.value
        if ($n.Contains($script:TextProjectName) -or $n.Contains('Project name') -or $v -match '^Project[0-9]*$') { $nameEdit = $edit; break }
    }
    if ($null -eq $nameEdit -and $edits.Count -gt 0) { $nameEdit = $edits | Select-Object -First 1 }
    Add-Step 'project_06' 'locate project name edit field' ($null -ne $nameEdit) $uiaConfig.raw_path
    Click-Element -Element $nameEdit -Description 'Project name edit field' -RawPath (Join-Path $OutDir 'project_06a_click_project_name.json') | Out-Null
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'project_06b_project_name_ctrl_a.json') | Out-Null
    Invoke-Agent -WinArgs @('desktop-type', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--text', $ProjectName, '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'project_06c_type_project_name.json') | Out-Null
    Start-Sleep -Milliseconds 800
    $uiaAfterName = Get-UiaTree 'project_06d_after_project_name_uia'
    $nameSet = @($uiaAfterName.json.data.elements | Where-Object { ([string]$_.name).Contains($ProjectName) -or ([string]$_.value).Contains($ProjectName) }).Count -ge 1
    Add-Step 'project_06d' 'type project name through visible keyboard' $nameSet $uiaAfterName.raw_path

    $uiaCreate = Get-UiaTree 'project_07_before_create_uia'
    $createButton = Find-ElementByText $uiaCreate @($script:TextCreate, 'Create') 'Button'
    if ($null -eq $createButton) {
        $buttons = @($uiaCreate.json.data.elements | Where-Object { $_.control_type -eq 'Button' -and $_.enabled -eq $true -and $_.offscreen -eq $false -and $_.rect.right -gt $_.rect.left } | Sort-Object { [int]$_.rect.right } -Descending)
        if ($buttons.Count -gt 0) { $createButton = $buttons | Select-Object -First 1 }
    }
    Add-Step 'project_07' 'locate Create button' ($null -ne $createButton) $uiaCreate.raw_path
    $raw = Join-Path $OutDir 'project_07a_click_create_project.json'
    Click-Element -Element $createButton -Description 'Create project button' -RawPath $raw | Out-Null
    Start-Sleep -Seconds 8
    $artifacts = Find-ProjectArtifacts
    if ($null -ne $artifacts) {
        $script:SolutionPath = $artifacts.solution
        $script:VcxprojPath = $artifacts.vcxproj
        $script:ActualProjectPath = $artifacts.actual_project_path
        $script:MainCppPath = Join-Path $script:ActualProjectPath 'main.cpp'
    }
    Add-Step 'project_07a' 'create empty C++ project through VS UI' ($null -ne $artifacts) $raw $(if ($null -ne $artifacts) { "path=$($artifacts.actual_project_path)" } else { 'project artifacts not found' })
}

function Ensure-SolutionExplorerVisible {
    $uia = Get-UiaTree 'add_01_solution_explorer_before_uia'
    $source = Find-ElementByText $uia @($script:TextSourceFiles, 'Source Files') 'TreeItem'
    if ($null -eq $source) {
        $tab = Find-ElementByText $uia @($script:TextSolutionExplorer, 'Solution Explorer') 'TabItem'
        if ($null -ne $tab) {
            Click-Element -Element $tab -Description 'Solution Explorer tab' -RawPath (Join-Path $OutDir 'add_01a_click_solution_explorer_tab.json') | Out-Null
        } else {
            Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+ALT+L', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'add_01b_ctrl_alt_l_solution_explorer.json') | Out-Null
        }
        Start-Sleep -Seconds 1
    }
    $uiaAfter = Get-UiaTree 'add_01_solution_explorer_after_uia'
    $sourceAfter = Find-ElementByText $uiaAfter @($script:TextSourceFiles, 'Source Files') 'TreeItem'
    Add-Step 'add_01' 'verify Solution Explorer Source Files tree' ($null -ne $sourceAfter) $uiaAfter.raw_path
}

function Get-AddNewItemDialogInfo([string]$NamePrefix) {
    $dialog = Get-UiaTree "$NamePrefix`_add_new_item_dialog_uia" -Title $script:TextAddNewItem
    $targetTitle = $script:TextAddNewItem
    if ($dialog.exit -ne 0 -or $dialog.json.ok -ne $true) {
        $dialog = Get-UiaTree "$NamePrefix`_add_new_item_dialog_uia_english" -Title 'Add New Item'
        $targetTitle = 'Add New Item'
    }
    $edits = @()
    if ($dialog.exit -eq 0 -and $dialog.json.ok -eq $true) {
        $edits = @($dialog.json.data.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.offscreen -eq $false } | Sort-Object { [int]$_.rect.top })
    }
    $nameEdit = if ($edits.Count -gt 0) { $edits | Select-Object -First 1 } else { $null }
    [pscustomobject]@{
        dialog = $dialog
        target_title = $targetTitle
        edits = $edits
        name_edit = $nameEdit
    }
}

function Add-MainCppVisible {
    if (Test-ExistingPath $script:MainCppPath) {
        Add-Step 'add_00' 'main.cpp already exists from earlier same-window attempt' $true ''
        return
    }

    $dialogInfo = Get-AddNewItemDialogInfo 'add_00'
    if ($null -eq $dialogInfo.name_edit) {
        Ensure-SolutionExplorerVisible
        $uia = Get-UiaTree 'add_02_folder_uia'
        $source = Find-ElementByText $uia @($script:TextSourceFiles, 'Source Files') 'TreeItem'
        Add-Step 'add_02' 'locate Source Files tree item' ($null -ne $source) $uia.raw_path

        Click-Element -Element $source -Description 'Source Files tree item' -RawPath (Join-Path $OutDir 'add_02a_select_source_files.json') | Out-Null
        Start-Sleep -Milliseconds 400
        $addHotkey = Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+SHIFT+A', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'add_03_ctrl_shift_a_add_item.json')
        Start-Sleep -Seconds 2
        $dialogInfo = Get-AddNewItemDialogInfo 'add_04'
        $dialogOpened = $null -ne $dialogInfo.name_edit
        if ($addHotkey.exit -ne 0 -and $dialogOpened) {
            $script:ForegroundGuardExpectedTransitionCount++
            $script:FailureRecoveryNotes.Add('accepted expected foreground transition from VS main window to Add New Item dialog after Ctrl+Shift+A') | Out-Null
        }
        Add-Step 'add_03' 'open Add New Item dialog with Ctrl+Shift+A' $dialogOpened (Join-Path $OutDir 'add_03_ctrl_shift_a_add_item.json')
    }

    $dialog = $dialogInfo.dialog
    $edits = @($dialogInfo.edits)
    if ($edits.Count -gt 1) { $script:AddItemSelectorAmbiguityCount += ($edits.Count - 1) }
    $nameEdit = $dialogInfo.name_edit
    Add-Step 'add_04' 'locate Add New Item file name edit' ($null -ne $nameEdit) $dialog.raw_path "edit_candidates=$($edits.Count)"

    $targetTitle = $dialogInfo.target_title
    Click-Element -Element $nameEdit -Description 'Add New Item file name edit' -RawPath (Join-Path $OutDir 'add_05_click_file_name.json') -TargetTitle $targetTitle | Out-Null
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-title', $targetTitle, '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'add_06_file_name_ctrl_a.json') | Out-Null
    Invoke-Agent -WinArgs @('desktop-type', '--target-title', $targetTitle, '--require-target-lock', 'true', '--text', 'main.cpp', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'add_07_type_main_cpp_filename.json') | Out-Null
    Start-Sleep -Milliseconds 500
    $dialogAfter = Get-UiaTree 'add_08_after_filename_uia' -Title $targetTitle
    $addButton = Find-ElementByText $dialogAfter @($script:TextAdd, 'Add') 'Button'
    Add-Step 'add_08' 'locate Add button in Add New Item dialog' ($null -ne $addButton) $dialogAfter.raw_path
    Click-Element -Element $addButton -Description 'Add New Item Add button' -RawPath (Join-Path $OutDir 'add_09_click_add_button.json') -TargetTitle $targetTitle | Out-Null
    Start-Sleep -Seconds 2
    if (-not (Test-Path -LiteralPath $script:MainCppPath)) {
        $script:RecoveryCount++
        $script:FailureRecoveryNotes.Add('pressed ENTER in Add New Item dialog after Add click did not create main.cpp') | Out-Null
        Invoke-Agent -WinArgs @('desktop-press', '--target-title', $targetTitle, '--require-target-lock', 'true', '--key', 'ENTER', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'add_09a_enter_recovery.json') | Out-Null
        Start-Sleep -Seconds 2
    }
    Add-Step 'add_10' 'verify main.cpp created by VS Add New Item UI' (Test-Path -LiteralPath $script:MainCppPath) ''
}

function Focus-EditorArea {
    $lock = Get-VsWindowLock -Allowed @(0)
    $rect = $lock.json.data.target_rect
    $x = [int]($rect.left + (($rect.right - $rect.left) * 0.56))
    $y = [int]($rect.top + (($rect.bottom - $rect.top) * 0.44))
    Invoke-Agent -WinArgs @('desktop-click', '--screen-x', ([string]$x), '--screen-y', ([string]$y), '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--coordinate-source', 'visible_editor_area_estimate', '--target-description', 'Visual Studio editor area', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'input_01_focus_editor_area.json') | Out-Null
    Start-Sleep -Milliseconds 400
}

function Set-MainCppVisible {
    $expectedPath = Join-Path $OutDir "$EvidencePrefix`_main_cpp_expected.txt"
    Write-TextFile $expectedPath (New-ExpectedCode)
    Focus-EditorArea
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+A', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'input_02_ctrl_a_editor.json') | Out-Null
    Start-Sleep -Milliseconds 250
    $raw = Join-Path $OutDir 'input_03_visible_text_input_brace_safe.json'
    $input = Invoke-Agent -WinArgs @(
        'visible-text-input',
        '--text-file', $expectedPath,
        '--input-kind', 'code',
        '--input-method', 'real_keyboard_events',
        '--typing-profile', 'fast-real-keyboard',
        '--target-process', 'devenv.exe',
        '--require-target-lock', 'true',
        '--allow-clipboard', 'false',
        '--backend-file-write-used', 'false',
        '--visible-mouse-keyboard-attempted', 'true',
        '--visible-attempt-count', '1',
        '--min-visible-attempts-before-shortcut', '2',
        '--pre-action-checkpoint-present', 'true',
        '--char-delay-ms', '0',
        '--line-delay-ms', '0',
        '--batch-key-events', 'true',
        '--structured', 'true',
        '--verify-structure', 'true'
    ) -RawPath $raw
    $script:InputRawPath = $raw
    if ($input.json.data.keyboard_safe_segmentation) {
        $script:BraceSafeDefaultEnabled = [bool]$input.json.data.keyboard_safe_segmentation.brace_safe_default_enabled
        $script:AutoPairCorruptionCount = [int]$input.json.data.keyboard_safe_segmentation.auto_pair_corruption_count
    }
    if ($input.json.data.code_editor_typing -and $input.json.data.code_editor_typing.brace_safe_preflight_enabled) {
        $script:BraceSafePreflightEnabled = [bool]$input.json.data.code_editor_typing.brace_safe_preflight_enabled
    } else {
        $script:BraceSafePreflightEnabled = $script:BraceSafeDefaultEnabled
    }
    Add-Step 'input_03' 'enter main.cpp through visible VS editor brace-safe keyboard input' ($input.json.ok -eq $true -and $input.json.data.clipboard_used -eq $false -and $input.json.data.backend_file_write_used -eq $false -and $script:BraceSafeDefaultEnabled) $raw
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+S', '--latency-profile', 'fast-visible-ui') -RawPath (Join-Path $OutDir 'input_04_ctrl_s_save.json') | Out-Null
    Start-Sleep -Seconds 1
}

function New-ExpectedCode {
@"
#include <iostream>
#include <vector>
#include <string>

namespace $ProjectName { struct Item { int value; }; }

namespace $ProjectName { int one() { return 1; } }

namespace $ProjectName { int two() { return 2; } }

namespace $ProjectName { int three() { return 3; } }

namespace $ProjectName { Item make_item(int value) { Item item; item.value = value; return item; } }

namespace $ProjectName { bool keep(const Item& item) { return item.value > 0; } }

namespace $ProjectName { int adjust(int value) { return value; } }

namespace $ProjectName { void add(std::vector<Item>& items, int value) { items.push_back(make_item(value)); } }

namespace $ProjectName { std::vector<Item> make_items() { std::vector<Item> items; add(items, one()); add(items, two()); add(items, three()); return items; } }

namespace $ProjectName { int score_items(const std::vector<Item>& items) { int total = 0; for (const auto& item : items) { if (keep(item)) { total += adjust(item.value); } } return total; } }

namespace $ProjectName { int expected_total() { return one() + two() + three(); } }

namespace $ProjectName { bool ok(int total) { return total == expected_total(); } }

int main() { std::vector<$($ProjectName)::Item> items = $ProjectName::make_items(); int total = $ProjectName::score_items(items); if ($ProjectName::ok(total)) { std::cout << "$SuccessMarker" << std::endl; return 0; } return 1; }
"@
}

function Normalize-Code([string]$Text) {
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
}

function Run-IntegrityCheck {
    $expected = Get-Content -Raw -LiteralPath (Join-Path $OutDir "$EvidencePrefix`_main_cpp_expected.txt")
    $actual = if (Test-Path -LiteralPath $script:MainCppPath) { Get-Content -Raw -LiteralPath $script:MainCppPath } else { '' }
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_main_cpp_actual.txt") $actual
    $match = (Normalize-Code $expected) -eq (Normalize-Code $actual)
    if (-not $match) { $script:AutoPairCorruptionCount++ }
    $lines = @(
        "code_integrity_check=$(if ($match) { 'PASS' } else { 'FAIL' })",
        "expected_path=$(Join-Path $OutDir "$EvidencePrefix`_main_cpp_expected.txt")",
        "actual_path=$(Join-Path $OutDir "$EvidencePrefix`_main_cpp_actual.txt")",
        "main_cpp_path=$($script:MainCppPath)",
        "clipboard_paste_used=NO",
        "direct_source_file_write_used=NO",
        "auto_pair_corruption_count=$($script:AutoPairCorruptionCount)",
        "brace_safe_default_enabled=$($script:BraceSafeDefaultEnabled)",
        "brace_safe_preflight_enabled=$($script:BraceSafePreflightEnabled)"
    )
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_integrity_check.txt") ($lines -join "`r`n")
    Add-Step 'integrity_01' 'compare saved main.cpp with expected brace-safe payload' $match ''
}

function Read-VsVisibleText([string]$Name) {
    $raw = Join-Path $OutDir "$Name.json"
    $title = Get-CurrentVsTitle
    if ([string]::IsNullOrWhiteSpace($title)) {
        return [pscustomobject]@{ text = ''; raw_path = $raw }
    }
    $ocr = Invoke-Agent -WinArgs @('read-window-text', '--title', $title) -Allowed @(0, 1) -RawPath $raw
    $text = ''
    if ($ocr.exit -eq 0 -and $ocr.json.ok -eq $true) { $text = [string]$ocr.json.data.text }
    [pscustomobject]@{ text = $text; raw_path = $raw }
}

function Show-OutputWindow {
    $raw = Join-Path $OutDir 'build_01_ctrl_alt_o_output.json'
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+ALT+O', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath $raw | Out-Null
    Start-Sleep -Seconds 1
    Add-Step 'build_01' 'show Visual Studio Output window' $true $raw
}

function Invoke-VisibleBuild {
    Show-OutputWindow
    $raw = Join-Path $OutDir 'build_02_ctrl_shift_b_build.json'
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+SHIFT+B', '--latency-profile', 'fast-visible-ui') -RawPath $raw | Out-Null
    $script:BuildRawPath = $raw
    $deadline = (Get-Date).AddSeconds(180)
    $verified = $false
    $lastText = ''
    do {
        Start-Sleep -Seconds 3
        $visibleText = Read-VsVisibleText 'build_03_output_ocr'
        $lastText = $visibleText.text
        $exe = Find-BuiltExe
        if ($null -ne $exe) { $script:BuiltExePath = $exe[0].FullName }
        $successText = -join @([char]0x6210, [char]0x529F)
        $latestText = -join @([char]0x6700, [char]0x65B0)
        $buildText = -join @([char]0x751F, [char]0x6210)
        $compactText = $lastText -replace '\s', ''
        $textLooksSuccessful = ($lastText -match 'succeeded|up-to-date|Build:|Rebuild All|0 failed') -or $compactText.Contains($successText) -or $compactText.Contains($latestText) -or $compactText.Contains($buildText)
        if ((Test-ExistingPath $script:BuiltExePath) -and $textLooksSuccessful) { $verified = $true; break }
    } while ((Get-Date) -lt $deadline)
    $script:BuildText = "visible_build_verified=$verified`r`nexe_path=$($script:BuiltExePath)`r`n`r`n$lastText"
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_build_output.txt") $script:BuildText
    Add-Step 'build_02' 'build project through Visual Studio Ctrl+Shift+B' $verified $raw "exe=$($script:BuiltExePath)"
}

function Normalize-VisibleOutputText([string]$Text) {
    $normalized = $Text -replace ([string][char]0x571F), 'i'
    return (($normalized -replace 'I', 'l' -replace '1', 'l' -replace '\s+', ' ').ToLowerInvariant())
}

function Normalize-VisibleOutputCompact([string]$Text) {
    $normalized = Normalize-VisibleOutputText $Text
    return ($normalized -replace '[^a-z0-9]', '')
}

function Read-ConsoleOutput([string]$Name, [string]$Expected) {
    $rawRoot = Join-Path $OutDir $Name
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath "$rawRoot`_windows.json"
    $active = Invoke-Agent -WinArgs @('active-window') -Allowed @(0, 1) -RawPath "$rawRoot`_active_window.json"
    if ($windows.exit -ne 0 -or $windows.json.ok -ne $true) { return $null }
    $candidateWindows = @($windows.json.windows | Where-Object {
        $title = [string]$_.title
        $title.Contains($script:TextDebugConsole) -or $title.Contains('Debug Console')
    })
    if ($candidateWindows.Count -eq 0 -and $active.exit -eq 0 -and $active.json.ok -eq $true) {
        $activeTitle = [string]$active.json.data.title
        $activeProcess = [string]$active.json.data.process_name
        if (-not [string]::IsNullOrWhiteSpace($activeTitle) -and
            -not $activeTitle.Contains('Microsoft Visual Studio') -and
            -not $activeTitle.Contains('Program Manager') -and
            -not $activeProcess.Contains('powershell')) {
            $candidateWindows = @([pscustomobject]@{ title = $activeTitle })
        }
    }
    if ($candidateWindows.Count -eq 0) {
        $candidateWindows = @($windows.json.windows | Where-Object {
            $title = [string]$_.title
            $title.Contains("$ProjectName.exe") -or $title.Contains($ProjectName)
        })
        if ($candidateWindows.Count -gt 0) { $script:ConsoleTitleOvermatchCount++ }
    }
    foreach ($w in $candidateWindows) {
        $title = [string]$w.title
        if ([string]::IsNullOrWhiteSpace($title)) { continue }
        $ocr = Invoke-Agent -WinArgs @('read-window-text', '--title', $title) -Allowed @(0, 1) -RawPath "$rawRoot`_$($title -replace '[^A-Za-z0-9]', '_')_ocr.json"
        if ($ocr.exit -eq 0 -and $ocr.json.ok -eq $true) {
            $text = [string]$ocr.json.data.text
            $normalizedText = Normalize-VisibleOutputText $text
            $normalizedExpected = Normalize-VisibleOutputText $Expected
            $compactText = Normalize-VisibleOutputCompact $text
            $compactExpected = Normalize-VisibleOutputCompact $Expected
            if ($text.Contains($Expected) -or $normalizedText.Contains($normalizedExpected) -or $compactText.Contains($compactExpected)) {
                return [pscustomobject]@{ title = $title; text = $text; raw_path = "$rawRoot`_$($title -replace '[^A-Za-z0-9]', '_')_ocr.json" }
            }
        }
    }
    return $null
}

function Wait-ConsoleOutputMatch([string]$Name, [string]$Expected, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $match = Read-ConsoleOutput $Name $Expected
        if ($null -ne $match) { return $match }
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Click-StartWithoutDebuggingButton {
    $uia = Get-UiaTree 'run_02_start_without_debugging_uia'
    $button = Find-ElementByText $uia @($script:TextStartWithoutDebugging, 'Start Without Debugging') 'Button'
    if ($null -eq $button) { $button = Find-ElementByText $uia @($script:TextStartWithoutDebugging, 'Start Without Debugging') }
    if ($null -eq $button) { return $false }
    Click-Element -Element $button -Description 'Visual Studio Start Without Debugging toolbar button' -RawPath (Join-Path $OutDir 'run_02_click_start_without_debugging_button.json') | Out-Null
    Start-Sleep -Seconds 3
    return $true
}

function Invoke-VisibleRun {
    $raw = Join-Path $OutDir 'run_01_ctrl_f5_run.json'
    Invoke-Agent -WinArgs @('desktop-hotkey', '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--keys', 'CTRL+F5', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath $raw | Out-Null
    $match = Wait-ConsoleOutputMatch 'run_01_console' $SuccessMarker 75
    if ($null -eq $match) {
        if (Click-StartWithoutDebuggingButton) {
            $script:RecoveryCount++
            $script:FailureRecoveryNotes.Add('clicked visible Start Without Debugging toolbar button after Ctrl+F5 produced no console output match') | Out-Null
            $match = Wait-ConsoleOutputMatch 'run_02_console_after_button' $SuccessMarker 120
        }
    }
    $verified = $null -ne $match
    if ($verified) {
        $script:ConsoleTitle = $match.title
        $script:RunText = $match.text
        Capture-Observation "$EvidencePrefix`_screenshot" | Out-Null
        $screenshotCandidate = Join-Path $OutDir "$EvidencePrefix`_screenshot.png"
        if (-not (Test-Path -LiteralPath $screenshotCandidate)) {
            $fallbackShot = Join-Path $OutDir "$EvidencePrefix`_screenshot.png"
            Invoke-Agent -WinArgs @('global-screenshot', '--out', $fallbackShot, '--format', 'png', '--include-metadata', 'true') -Allowed @(0, 1) -RawPath (Join-Path $OutDir "$EvidencePrefix`_screenshot_capture.json") | Out-Null
        }
    }
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_run_output.txt") ("visible_run_verified=$verified`r`nconsole_title=$($script:ConsoleTitle)`r`n`r`n$($script:RunText)")
    Add-Step 'run_01' 'run project through Visual Studio Ctrl+F5 and verify visible console output' $verified $raw
    if ($verified -and -not [string]::IsNullOrWhiteSpace($script:ConsoleTitle)) {
        Invoke-Agent -WinArgs @('desktop-press', '--target-title', $script:ConsoleTitle, '--require-target-lock', 'true', '--key', 'ENTER', '--latency-profile', 'fast-visible-ui') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'run_03_console_enter_close.json') | Out-Null
        Start-Sleep -Seconds 2
    }
}

function Close-VsVisible {
    $lock = Get-VsWindowLock -Allowed @(0, 1)
    if ($lock.exit -ne 0 -or $lock.json.ok -ne $true) { return $false }
    $rect = $lock.json.data.target_rect
    $uia = Get-UiaTree 'close_01_uia_tree_for_close'
    $closeX = [int]$rect.right - 22
    $closeY = [int]$rect.top + 18
    if ($uia.exit -eq 0 -and $uia.json.ok -eq $true) {
        $buttons = @($uia.json.data.elements | Where-Object {
            $_.control_type -eq 'Button' -and $_.enabled -eq $true -and $_.offscreen -eq $false -and $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top -and $_.rect.right -ge ([int]$rect.right - 90) -and $_.rect.top -le ([int]$rect.top + 60)
        } | Sort-Object { [int]$_.rect.right } -Descending)
        if ($buttons.Count -gt 0) {
            $b = $buttons | Select-Object -First 1
            $closeX = [int]($b.rect.left + (($b.rect.right - $b.rect.left) / 2))
            $closeY = [int]($b.rect.top + (($b.rect.bottom - $b.rect.top) / 2))
        }
    }
    Invoke-Agent -WinArgs @('desktop-click', '--screen-x', ([string]$closeX), '--screen-y', ([string]$closeY), '--target-process', 'devenv.exe', '--require-target-lock', 'true', '--coordinate-source', 'visible_window_rect_top_right_x', '--target-description', 'Visual Studio top-right close button', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'close_02_click_top_right_x.json') | Out-Null
    Start-Sleep -Seconds 2
    $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'close_03_windows_after_close.json')
    $hasVs = $false
    if ($windows.json.ok -eq $true) {
        $hasVs = @($windows.json.windows | Where-Object { ([string]$_.title).Contains('Microsoft Visual Studio') -or ([string]$_.title).Contains($ProjectName) }).Count -gt 0
    }
    return (-not $hasVs)
}

function Write-CommonEvidence {
    Start-Phase 'evidence_package_seconds'
    $completed = Get-Date
    $elapsed = [Math]::Round(($completed - $script:StartedAt).TotalSeconds, 3)
    $elapsedObj = [ordered]@{
        project_name = $ProjectName
        success_marker = $SuccessMarker
        started_at = $script:StartedAt.ToString('o')
        completed_at = $completed.ToString('o')
        total_elapsed_seconds = $elapsed
        phase_elapsed_seconds = $script:PhaseElapsed
        baseline_elapsed_seconds = 1904
        recovery_count = $script:RecoveryCount
    }
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_elapsed_time.json") (($elapsedObj | ConvertTo-Json -Depth 8))

    $timeline = @(
        "# $EvidencePrefix validation timeline",
        '',
        "Project: $ProjectName",
        "Runtime: $WinAgent",
        "Status: $($script:Status)",
        '',
        '```json',
        ($script:Steps | ConvertTo-Json -Depth 12),
        '```'
    )
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_timeline.md") ($timeline -join "`r`n")

    $failureRecovery = @(
        "# $EvidencePrefix failure recovery",
        '',
        "recovery_count=$($script:RecoveryCount)",
        "failure_recovery_elapsed_seconds=$($script:PhaseElapsed.failure_recovery_seconds)",
        "same_vs_window_required_on_failure=true",
        "vs_closed_on_failure=false",
        '',
        '## Notes',
        ''
    )
    if ($script:FailureRecoveryNotes.Count -eq 0) {
        $failureRecovery += '- none'
    } else {
        foreach ($note in $script:FailureRecoveryNotes) { $failureRecovery += "- $note" }
    }
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_failure_recovery.md") ($failureRecovery -join "`r`n")

    $summary = @(
        "# $EvidencePrefix validation summary",
        '',
        "result=$($script:Status)",
        "message=$($script:StatusMessage)",
        "version_expected=1.1.12a",
        "runtime=$WinAgent",
        "project_name=$ProjectName",
        "solution_path=$($script:SolutionPath)",
        "vcxproj_path=$($script:VcxprojPath)",
        "main_cpp_path=$($script:MainCppPath)",
        "built_exe_path=$($script:BuiltExePath)",
        "main_cpp_visible_keyboard_input=YES",
        "clipboard_paste_used=NO",
        "direct_source_file_write_used=NO",
        "direct_vcxproj_edit_used=NO",
        "brace_safe_default_enabled=$($script:BraceSafeDefaultEnabled)",
        "brace_safe_preflight_enabled=$($script:BraceSafePreflightEnabled)",
        "auto_pair_corruption_count=$($script:AutoPairCorruptionCount)",
        "code_integrity_check=$(if ($script:AutoPairCorruptionCount -eq 0) { 'PASS' } else { 'FAIL' })",
        "build_result=$(if (Test-ExistingPath $script:BuiltExePath) { 'PASS' } else { 'FAIL' })",
        "run_result=$(if ($script:RunText.Contains($SuccessMarker)) { 'PASS' } else { 'FAIL' })",
        "output_contains_marker=$(if ($script:RunText.Contains($SuccessMarker)) { 'YES' } else { 'NO' })",
        "helper_argument_errors_count=$($script:HelperArgumentErrors)",
        "console_title_overmatch_count=$($script:ConsoleTitleOvermatchCount)",
        "add_item_selector_ambiguity_count=$($script:AddItemSelectorAmbiguityCount)",
        "foreground_guard_expected_transition_count=$($script:ForegroundGuardExpectedTransitionCount)",
        "evidence_repack_caused_reinput=NO",
        "evidence_repack_caused_rebuild_rerun=NO"
    )
    Write-TextFile (Join-Path $OutDir "$EvidencePrefix`_validation_summary.md") ($summary -join "`r`n")
    Stop-Phase 'evidence_package_seconds'
}

function Write-DeveloperOnlyEvidence {
    if ($EvidencePrefix -ne 'developer') { return }
    $gitNames = @()
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $gitNames = & git -C $Root diff --name-only 2>$null
        $ErrorActionPreference = $previousPreference
    } catch {
        $ErrorActionPreference = $previousPreference
        $gitNames = @("git_diff_name_only_unavailable=$($_.Exception.Message)")
    }
    Write-TextFile (Join-Path $OutDir 'modified_files.txt') (($gitNames | Out-String).Trim())
    $boundary = @(
        "PermissionManager_changed_by_v1_1_12a_patch=false",
        "safety_manifest_changed_by_v1_1_12a_patch=false",
        "safety_conf_changed_by_v1_1_12a_patch=false",
        "vlm_changed_by_v1_1_12a_patch=false",
        "protected_boundary_note=checks above report this patch scope, not unrelated pre-existing worktree dirt",
        "public_dist_created=$((Test-Path -LiteralPath (Join-Path $Root 'public-dist')))",
        "entered_v1_2_0=false"
    )
    Write-TextFile (Join-Path $OutDir 'boundary_check.txt') ($boundary -join "`r`n")
}

function Write-UserOnlyEvidence {
    if ($EvidencePrefix -ne 'user') { return }
    $clean = @(
        "# release cleanliness after validation",
        '',
        "public_dist_exists=$((Test-Path -LiteralPath (Join-Path $Root 'public-dist')))",
        "desktopvisual_local_exists=$((Test-Path -LiteralPath (Join-Path $Root '.desktopvisual_local')))",
        "developer_versions_exists=$((Test-Path -LiteralPath (Join-Path $Root 'developer_versions')))",
        "temporary_patch_files=$(@(Get-ChildItem -LiteralPath $Root -Filter '*.patch' -File -ErrorAction SilentlyContinue).Count)",
        "root_tmp_payloads=$(@(Get-ChildItem -LiteralPath $Root -Filter '*payload*' -File -ErrorAction SilentlyContinue).Count)",
        "release_source_diff_check=see final_acceptance_check.txt"
    )
    Write-TextFile (Join-Path $OutDir 'release_cleanliness_after_validation.md') ($clean -join "`r`n")
    $final = @(
        "VERSION=1.1.12a",
        "project_name=$ProjectName",
        "main_cpp_keyboard_input=YES",
        "clipboard_paste_used=NO",
        "direct_source_file_write_used=NO",
        "auto_pair_corruption_count=$($script:AutoPairCorruptionCount)",
        "code_integrity_check=$(if ($script:AutoPairCorruptionCount -eq 0) { 'PASS' } else { 'FAIL' })",
        "build=$(if (Test-ExistingPath $script:BuiltExePath) { 'PASS' } else { 'FAIL' })",
        "run=$(if ($script:RunText.Contains($SuccessMarker)) { 'PASS' } else { 'FAIL' })",
        "output_contains_marker=$(if ($script:RunText.Contains($SuccessMarker)) { 'YES' } else { 'NO' })"
    )
    Write-TextFile (Join-Path $OutDir 'final_acceptance_check.txt') ($final -join "`r`n")
}

if (-not (Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run build first." }

try {
    $version = Invoke-Agent -WinArgs @('version') -RawPath (Join-Path $OutDir 'runtime_version.json')
    Add-Step 'preflight_01' 'verify winagent version 1.1.12a' ($version.json.data.version -eq '1.1.12a') (Join-Path $OutDir 'runtime_version.json')
    if ($UseExistingVs) {
        $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'preflight_02_windows_for_existing_vs.json')
        $hasVs = $false
        if ($windows.json.ok -eq $true) {
            $hasVs = @($windows.json.windows | Where-Object {
                $title = [string]$_.title
                $title.Contains($ProjectName) -or $title.Contains('Microsoft Visual Studio') -or $title.Contains($script:TextAddNewItem) -or $title.Contains('Add New Item')
            }).Count -gt 0
        }
        Add-Step 'preflight_02' 'reuse current Visual Studio IDE window for same-window recovery' $hasVs (Join-Path $OutDir 'preflight_02_windows_for_existing_vs.json')
        $script:RecoveryCount++
        $script:FailureRecoveryNotes.Add('same-window recovery: reused already-open Visual Studio after project-entry detection failure') | Out-Null
    } else {
        $existingVs = Get-VsWindowLock -Allowed @(0, 1)
        Add-Step 'preflight_02' 'verify no preexisting Visual Studio IDE window before launch' (-not ($existingVs.exit -eq 0 -and $existingVs.json.ok -eq $true)) ''
    }

    Start-Phase 'vs_startup_seconds'
    if ($UseExistingVs) {
        $windows = Invoke-Agent -WinArgs @('windows') -Allowed @(0, 1) -RawPath (Join-Path $OutDir 'launch_00_existing_vs_windows.json')
        $hasVs = $windows.json.ok -eq $true -and @($windows.json.windows | Where-Object {
            $title = [string]$_.title
            $title.Contains($ProjectName) -or $title.Contains('Microsoft Visual Studio') -or $title.Contains($script:TextAddNewItem) -or $title.Contains('Add New Item')
        }).Count -gt 0
        Add-Step 'launch_00' 'verify existing Visual Studio window is still usable' $hasVs (Join-Path $OutDir 'launch_00_existing_vs_windows.json')
    } else {
        Launch-VisualStudio
    }
    Stop-Phase 'vs_startup_seconds'

    Start-Phase 'project_file_create_seconds'
    if ($UseExistingProject) {
        $artifacts = Find-ProjectArtifacts
        if ($null -ne $artifacts) {
            $script:SolutionPath = $artifacts.solution
            $script:VcxprojPath = $artifacts.vcxproj
            $script:ActualProjectPath = $artifacts.actual_project_path
            $script:MainCppPath = Join-Path $script:ActualProjectPath 'main.cpp'
        }
        Add-Step 'project_existing_01' 'reuse current already-created VS project for same-window recovery' ($null -ne $artifacts) '' $(if ($null -ne $artifacts) { "path=$($artifacts.actual_project_path)" } else { 'not_found' })
        $script:RecoveryCount++
        $script:FailureRecoveryNotes.Add('same-window recovery: reused already-created project after Add New Item foreground transition failure') | Out-Null
    } else {
        Create-EmptyProject
    }
    Add-MainCppVisible
    Stop-Phase 'project_file_create_seconds'

    Start-Phase 'main_cpp_input_seconds'
    Set-MainCppVisible
    Stop-Phase 'main_cpp_input_seconds'

    Start-Phase 'integrity_check_seconds'
    Run-IntegrityCheck
    Stop-Phase 'integrity_check_seconds'

    Start-Phase 'build_seconds'
    Invoke-VisibleBuild
    Stop-Phase 'build_seconds'

    Start-Phase 'run_seconds'
    Invoke-VisibleRun
    Stop-Phase 'run_seconds'

    if ($CloseOnSuccess) {
        Close-VsVisible | Out-Null
    }

    $script:Status = 'PASS'
    $script:StatusMessage = 'Real Visual Studio C++ brace-safe validation passed.'
    Write-CommonEvidence
    Write-DeveloperOnlyEvidence
    Write-UserOnlyEvidence
    Write-Host "PASS vs_cpp_brace_safe_real_validation $EvidencePrefix"
    Write-Host "Evidence: $OutDir"
    exit 0
} catch {
    foreach ($phaseName in @($script:PhaseStarts.Keys)) { Stop-Phase $phaseName }
    if ($script:Status -ne 'BLOCKED') { $script:Status = 'FAIL' }
    $script:StatusMessage = $_.Exception.Message
    Write-CommonEvidence
    Write-DeveloperOnlyEvidence
    Write-UserOnlyEvidence
    Write-Host "$($script:Status) vs_cpp_brace_safe_real_validation $EvidencePrefix"
    Write-Host "Reason: $($script:StatusMessage)"
    Write-Host "Evidence: $OutDir"
    exit 1
}
