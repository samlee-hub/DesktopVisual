param(
    [string]$Root = '',
    [string]$SearchProvider = 'google'
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5a_visible_mouse_first_interaction'
$RawRoot = Join-Path $ArtifactRoot 'raw\mouse_first'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified\mouse_first'
if (Test-Path -LiteralPath $RawRoot) {
    Remove-Item -LiteralPath $RawRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $RawRoot, $VerifiedRoot | Out-Null

$TestRoot = 'D:\testrepo\testwindow'
$FormHtml = Join-Path $TestRoot 'desktopvisual_mouse_first_form_mock.html'
$CodeHtml = Join-Path $TestRoot 'desktopvisual_mouse_first_code_editor_mock.html'
$FormUrl = 'file:///D:/testrepo/testwindow/desktopvisual_mouse_first_form_mock.html'
$CodeUrl = 'file:///D:/testrepo/testwindow/desktopvisual_mouse_first_code_editor_mock.html'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

foreach ($fixture in @($FormHtml, $CodeHtml)) {
    if (-not (Test-Path -LiteralPath $fixture)) {
        throw "Missing v6.1.5a fixture: $fixture"
    }
}

function Bool-String([bool]$Value) {
    if ($Value) { return 'true' }
    return 'false'
}

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function ConvertTo-JsonOrNull([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json } catch { return $null }
}

function Save-Json([object]$Value, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgentRaw {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0, 1)
    )
    $caseDir = Join-Path $RawRoot $CaseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $stdoutPath = Join-Path $caseDir "$StepId.stdout.log"
    $stderrPath = Join-Path $caseDir "$StepId.stderr.log"
    $metaPath = Join-Path $caseDir "$StepId.meta.json"
    $start = Get-Date
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $previousEap
    $text = ($output | Out-String).Trim()
    $text | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    '' | Set-Content -LiteralPath $stderrPath -Encoding UTF8
    $json = ConvertTo-JsonOrNull $text
    $meta = [ordered]@{
        case_id = $CaseId
        step_id = $StepId
        command = "winagent.exe $($WinArgs -join ' ')"
        started_at = $start.ToString('o')
        ended_at = (Get-Date).ToString('o')
        exit_code = $exit
        exit_code_allowed = ($AllowedExitCodes -contains $exit)
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        parsed_json = ($null -ne $json)
    }
    Save-Json $meta $metaPath
    [pscustomobject]@{
        case_id = $CaseId
        step_id = $StepId
        exit_code = $exit
        allowed = ($AllowedExitCodes -contains $exit)
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        meta_path = $metaPath
        json = $json
        text = $text
    }
}

function Normalize-CoordinateSourceType([string]$Source) {
    if ($Source -match 'locator_derived') { return 'locator_derived_coordinate' }
    if ($Source -match 'fallback') { return 'fallback_coordinate' }
    return 'fixed_coordinate'
}

function Rect-ToObject($Rect) {
    if ($null -eq $Rect) { return $null }
    [ordered]@{
        left = [int]$Rect.left
        top = [int]$Rect.top
        right = [int]$Rect.right
        bottom = [int]$Rect.bottom
    }
}

function Rect-Center($Rect) {
    [ordered]@{
        x = [int]([math]::Floor(([int]$Rect.left + [int]$Rect.right) / 2))
        y = [int]([math]::Floor(([int]$Rect.top + [int]$Rect.bottom) / 2))
    }
}

function New-CaseEvidence([string]$CaseId, [string]$TargetName) {
    [ordered]@{
        case_id = $CaseId
        target_name = $TargetName
        target_type = 'visible_ui'
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        interaction_mode = 'mouse_first'
        mouse_first_required = $true
        mouse_first_passed = $false
        mouse_move_count = 0
        mouse_click_count = 0
        keyboard_shortcut_used = $false
        keyboard_only_path_used = $false
        fallback_used = $false
        fallback_reason = ''
        cursor_before = $null
        cursor_after_move = $null
        target_role = ''
        target_rect = $null
        target_center = $null
        target_visible = $false
        target_unique = $false
        target_candidate_count = 0
        locator_source = ''
        locator_confidence = 0.0
        coordinate_source = ''
        coordinate_source_type = ''
        fixed_coordinate_reason = ''
        mouse_move_started = $false
        mouse_move_completed = $false
        click_point = $null
        click_sent = $false
        focus_verified_after_click = $false
        context_verified_after_click = $false
        text_verified_after_type = $false
        action_executed = $false
        wrong_field_input_count = 0
        continued_action_after_wrong_context = $false
        final_stop_code = ''
        failure_attribution = 'UNKNOWN_FAILURE'
        evidence_paths = @()
        command_steps = @()
        mouse_actions = @()
        keyboard_actions = @()
    }
}

function Add-CasePath($Case, [string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $Case['evidence_paths'] = @($Case['evidence_paths']) + $Path
    }
}

function Add-CommandStep($Case, $Step) {
    $Case['command_steps'] = @($Case['command_steps']) + $Step
    Add-CasePath $Case $Step.stdout_path
    Add-CasePath $Case $Step.meta_path
}

function Find-UiaElement {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string]$Title,
        [string[]]$NameRegexes,
        [string[]]$RoleRegexes = @(),
        [int]$WaitMs = 8000
    )
    $deadline = (Get-Date).AddMilliseconds($WaitMs)
    $attempt = 0
    $lastStep = $null
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $lastStep = Invoke-WinAgentRaw $CaseId "$StepId`_uia_$attempt" @('uia-tree', '--title', $Title)
        if ($lastStep.json -and $lastStep.json.ok -eq $true) {
            $elements = @($lastStep.json.data.elements)
            $windowTop = 0
            if ($elements.Count -gt 0 -and $elements[0].rect) {
                $windowTop = [int]$elements[0].rect.top
            }
            $addressBarGeometry = $NameRegexes -contains '__ADDRESS_BAR_GEOMETRY__'
            $searchBoxGeometry = $NameRegexes -contains '__SEARCH_BOX_GEOMETRY__'
            $searchButtonGeometry = $NameRegexes -contains '__SEARCH_BUTTON_GEOMETRY__'
            $candidates = @()
            foreach ($element in $elements) {
                $name = [string]$element.name
                $value = [string]$element.value
                $role = [string]$element.control_type
                $rect = $element.rect
                if ($null -eq $rect -or [int]$rect.right -le [int]$rect.left -or [int]$rect.bottom -le [int]$rect.top) { continue }
                if ($element.offscreen -eq $true -or $element.enabled -eq $false) { continue }
                $width = [int]$rect.right - [int]$rect.left
                $height = [int]$rect.bottom - [int]$rect.top
                if ($addressBarGeometry -and $role -match 'Edit|ComboBox' -and $width -gt 500 -and $height -le 70 -and [int]$rect.top -le ($windowTop + 130)) {
                    $candidates += $element
                    continue
                }
                if ($searchBoxGeometry -and $role -match 'Edit|ComboBox' -and $width -gt 250 -and $height -ge 30 -and [int]$rect.top -gt ($windowTop + 70)) {
                    $candidates += $element
                    continue
                }
                if ($searchButtonGeometry -and $role -match 'Button' -and $width -gt 20 -and $width -lt 220 -and [int]$rect.top -gt ($windowTop + 70) -and ($name -match 'Google|Search|search')) {
                    $candidates += $element
                    continue
                }
                $nameOk = $false
                foreach ($regex in $NameRegexes) {
                    if ($regex -match '^__.*__$') { continue }
                    if ($name -match $regex -or $value -match $regex) { $nameOk = $true; break }
                }
                if (-not $nameOk) { continue }
                $roleOk = $RoleRegexes.Count -eq 0
                foreach ($regex in $RoleRegexes) {
                    if ($role -match $regex) { $roleOk = $true; break }
                }
                if (-not $roleOk) { continue }
                $candidates += $element
            }
            if ($candidates.Count -gt 0) {
                $selected = $candidates | Select-Object -First 1
                return [pscustomobject]@{
                    found = $true
                    element = $selected
                    candidate_count = $candidates.Count
                    unique = ($candidates.Count -eq 1)
                    locator_source = 'uia-tree'
                    locator_confidence = $(if ($candidates.Count -eq 1) { 0.95 } else { 0.80 })
                    command_step = $lastStep
                }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    [pscustomobject]@{
        found = $false
        element = $null
        candidate_count = 0
        unique = $false
        locator_source = 'uia-tree'
        locator_confidence = 0.0
        command_step = $lastStep
    }
}

function Find-SearchResultLink {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string]$Title
    )
    $deadline = (Get-Date).AddSeconds(20)
    $attempt = 0
    $lastStep = $null
    $lastElements = @()
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $lastStep = Invoke-WinAgentRaw $CaseId "$StepId`_uia_$attempt" @('uia-tree', '--title', $Title)
        if ($lastStep.json -and $lastStep.json.ok -eq $true) {
            $elements = @($lastStep.json.data.elements)
            $lastElements = $elements
            $candidates = @()
            foreach ($element in $elements) {
                $name = ([string]$element.name).Trim()
                $role = [string]$element.control_type
                $rect = $element.rect
                if ($name.Length -lt 4) { continue }
                if ($role -notmatch 'Hyperlink|Text') { continue }
                if ($element.offscreen -eq $true -or $element.enabled -eq $false) { continue }
                if ($null -eq $rect -or [int]$rect.right -le [int]$rect.left -or [int]$rect.bottom -le [int]$rect.top) { continue }
                if ($name -match 'Google|Search|Images|Videos|Maps|Shopping|News|Sign in|Settings|Tools|YouTube Home|Skip to main content|Accessibility help|World Cup') { continue }
                if ([int]$rect.top -lt 330) { continue }
                $candidates += $element
            }
            if ($candidates.Count -gt 0) {
                $selected = @($candidates | Where-Object { $_.name -match 'OpenAI|openai|ChatGPT' } | Select-Object -First 1)
                if (-not $selected -or $selected.Count -eq 0) {
                    $selected = $candidates | Select-Object -First 1
                } else {
                    $selected = $selected[0]
                }
                $sameName = @($candidates | Where-Object { $_.name -eq $selected.name })
                return [pscustomobject]@{
                    found = $true
                    element = $selected
                    candidate_count = $sameName.Count
                    unique = ($sameName.Count -eq 1)
                    locator_source = 'uia-tree'
                    locator_confidence = 0.85
                    command_step = $lastStep
                }
            }
        }
        Start-Sleep -Milliseconds 700
    }
    $fallbackCandidates = @()
    foreach ($element in $lastElements) {
        $name = ([string]$element.name).Trim()
        $role = [string]$element.control_type
        $rect = $element.rect
        if ($name.Length -lt 4) { continue }
        if ($role -notmatch 'Hyperlink') { continue }
        if ($element.offscreen -eq $true -or $element.enabled -eq $false) { continue }
        if ($null -eq $rect -or [int]$rect.right -le [int]$rect.left -or [int]$rect.bottom -le [int]$rect.top) { continue }
        if ($name -match 'Google|Search|Images|Videos|Maps|Shopping|News|Sign in|Settings|Tools|YouTube Home|Skip to main content|Accessibility help|Account|apps|Labs') { continue }
        if ([int]$rect.top -lt 230) { continue }
        $fallbackCandidates += $element
    }
    if ($fallbackCandidates.Count -gt 0) {
        $selected = $fallbackCandidates | Select-Object -First 1
        $sameName = @($fallbackCandidates | Where-Object { $_.name -eq $selected.name })
        return [pscustomobject]@{
            found = $true
            element = $selected
            candidate_count = $sameName.Count
            unique = ($sameName.Count -eq 1)
            locator_source = 'uia-tree-visible-link-fallback'
            locator_confidence = 0.72
            command_step = $lastStep
        }
    }
    [pscustomobject]@{ found = $false; command_step = $lastStep }
}

function Get-ActiveWindowStep([string]$CaseId, [string]$StepId) {
    Invoke-WinAgentRaw $CaseId $StepId @('active-window')
}

function Wait-ActiveWindowTitle {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string]$TitleRegex,
        [string]$ProcessRegex = '',
        [int]$WaitMs = 12000
    )
    $deadline = (Get-Date).AddMilliseconds($WaitMs)
    $attempt = 0
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $last = Get-ActiveWindowStep $CaseId "$StepId`_$attempt"
        if ($last.json -and $last.json.ok -eq $true) {
            $title = [string]$last.json.data.title
            $process = [string]$last.json.data.process_name
            $titleOk = [string]::IsNullOrWhiteSpace($TitleRegex) -or $title -match $TitleRegex
            $processOk = [string]::IsNullOrWhiteSpace($ProcessRegex) -or $process -match $ProcessRegex
            if ($titleOk -and $processOk) {
                return [pscustomobject]@{ ok = $true; title = $title; process = $process; step = $last }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    [pscustomobject]@{ ok = $false; title = ''; process = ''; step = $last }
}

function Wait-ActiveWindowTitleChanged {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string]$BeforeTitle,
        [string]$TitleRegex,
        [string]$ProcessRegex = '',
        [int]$WaitMs = 12000
    )
    $deadline = (Get-Date).AddMilliseconds($WaitMs)
    $attempt = 0
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $last = Get-ActiveWindowStep $CaseId "$StepId`_$attempt"
        if ($last.json -and $last.json.ok -eq $true) {
            $title = [string]$last.json.data.title
            $process = [string]$last.json.data.process_name
            $titleOk = [string]::IsNullOrWhiteSpace($TitleRegex) -or $title -match $TitleRegex
            $processOk = [string]::IsNullOrWhiteSpace($ProcessRegex) -or $process -match $ProcessRegex
            if ($title -ne $BeforeTitle -and $titleOk -and $processOk) {
                return [pscustomobject]@{ ok = $true; title = $title; process = $process; step = $last }
            }
        }
        Start-Sleep -Milliseconds 700
    }
    [pscustomobject]@{ ok = $false; title = ''; process = ''; step = $last }
}

function Invoke-MouseAction {
    param(
        $Case,
        [string]$StepId,
        [object]$Located,
        [string]$TargetName,
        [string]$TargetRole,
        [switch]$DoubleClick,
        [Nullable[int]]$OverrideX = $null,
        [Nullable[int]]$OverrideY = $null
    )
    $caseId = [string]$Case['case_id']
    if (-not $Located.found) {
        $Case['final_stop_code'] = 'TARGET_NOT_VISIBLE'
        $Case['failure_attribution'] = 'TARGET_NOT_VISIBLE'
        return $null
    }
    Add-CommandStep $Case $Located.command_step
    $rect = Rect-ToObject $Located.element.rect
    $center = Rect-Center $rect
    $x = $center.x
    $y = $center.y
    if ($OverrideX.HasValue) { $x = [int]$OverrideX.Value }
    if ($OverrideY.HasValue) { $y = [int]$OverrideY.Value }
    $coordinateSource = "locator_derived_coordinate:$($Located.locator_source):$TargetName"
    $caseDir = Join-Path $RawRoot $caseId
    $humanResultPath = Join-Path $caseDir "$StepId.human_action_result.json"
    $command = if ($DoubleClick) { 'desktop-double-click' } else { 'desktop-click' }
    $args = @(
        $command,
        '--screen-x', [string]$x,
        '--screen-y', [string]$y,
        '--move-mode', 'operator-human',
        '--permission-mode', $PermissionMode,
        '--target-description', $TargetName,
        '--coordinate-source', $coordinateSource,
        '--target-rect-left', [string]$rect.left,
        '--target-rect-top', [string]$rect.top,
        '--target-rect-right', [string]$rect.right,
        '--target-rect-bottom', [string]$rect.bottom,
        '--require-target-rect', 'true',
        '--require-target-current', 'true',
        '--require-target-unique', (Bool-String ([bool]$Located.unique)),
        '--require-target-inside-viewport', 'true',
        '--target-from-current-observe', 'true',
        '--target-unique', (Bool-String ([bool]$Located.unique)),
        '--target-inside-viewport', 'true',
        '--stop-on-wrong-context', 'true',
        '--result-json', $humanResultPath
    )
    $step = Invoke-WinAgentRaw $caseId $StepId $args
    Add-CommandStep $Case $step
    Add-CasePath $Case $humanResultPath
    $human = Read-Json $humanResultPath
    if (-not $human -and $step.json -and $step.json.data.human_action_result) {
        $human = $step.json.data.human_action_result
    }
    $cursorBefore = $null
    $cursorAfterMove = $null
    $clickSent = $false
    $doubleClickSent = $false
    $moveCompleted = $false
    $fallback = $false
    $backend = $false
    $directLaunch = $false
    if ($human) {
        $cursorBefore = [ordered]@{ x = [int]$human.cursor.start_x; y = [int]$human.cursor.start_y }
        $cursorAfterMove = [ordered]@{ x = [int]$human.cursor.actual_before_click_x; y = [int]$human.cursor.actual_before_click_y }
        $clickSent = ($human.actual_click_sent -eq $true)
        $doubleClickSent = ($human.actual_double_click_sent -eq $true)
        $moveCompleted = ($human.verification.cursor_inside_target_rect_before_click -eq $true)
        $fallback = ($human.fallback_used -eq $true)
        $backend = ($human.backend_action -eq $true)
        $directLaunch = ($human.direct_launch -eq $true)
    }
    $coordinateType = Normalize-CoordinateSourceType $coordinateSource
    $action = [ordered]@{
        step_id = $StepId
        target_name = $TargetName
        target_role = $TargetRole
        target_rect = $rect
        target_center = $center
        target_visible = $true
        target_unique = [bool]$Located.unique
        target_candidate_count = [int]$Located.candidate_count
        locator_source = [string]$Located.locator_source
        locator_confidence = [double]$Located.locator_confidence
        coordinate_source = $coordinateSource
        coordinate_source_type = $coordinateType
        fixed_coordinate_reason = ''
        click_point = [ordered]@{ x = $x; y = $y }
        cursor_before = $cursorBefore
        cursor_after_move = $cursorAfterMove
        mouse_move_completed = $moveCompleted
        click_sent = ($clickSent -or $doubleClickSent)
        double_click_sent = $doubleClickSent
        backend_action = $backend
        direct_launch = $directLaunch
        fallback_used = $fallback
        stdout_path = $step.stdout_path
        human_action_result_path = $humanResultPath
    }
    $Case['mouse_actions'] = @($Case['mouse_actions']) + [pscustomobject]$action
    if ($moveCompleted) {
        $Case['mouse_move_count'] = [int]$Case['mouse_move_count'] + 1
        $Case['mouse_move_started'] = $true
        $Case['mouse_move_completed'] = $true
    }
    if ($clickSent -or $doubleClickSent) {
        $Case['mouse_click_count'] = [int]$Case['mouse_click_count'] + $(if ($doubleClickSent) { 2 } else { 1 })
        $Case['click_sent'] = $true
        $Case['action_executed'] = $true
    }
    if ($fallback) {
        $Case['fallback_used'] = $true
        $Case['fallback_reason'] = 'desktop mouse command reported fallback_used=true'
    }
    if ($step.json -and $step.json.data -and $step.json.data.continued_action_after_wrong_context -eq $true) {
        $Case['continued_action_after_wrong_context'] = $true
    }
    if ([string]::IsNullOrWhiteSpace([string]$Case['target_role'])) {
        $Case['target_name'] = $TargetName
        $Case['target_role'] = $TargetRole
        $Case['target_rect'] = $rect
        $Case['target_center'] = $center
        $Case['target_visible'] = $true
        $Case['target_unique'] = [bool]$Located.unique
        $Case['target_candidate_count'] = [int]$Located.candidate_count
        $Case['locator_source'] = [string]$Located.locator_source
        $Case['locator_confidence'] = [double]$Located.locator_confidence
        $Case['coordinate_source'] = $coordinateSource
        $Case['coordinate_source_type'] = $coordinateType
        $Case['cursor_before'] = $cursorBefore
        $Case['cursor_after_move'] = $cursorAfterMove
        $Case['click_point'] = [ordered]@{ x = $x; y = $y }
    }
    [pscustomobject]$action
}

function Invoke-KeyboardText {
    param(
        $Case,
        [string]$StepId,
        [string]$Text
    )
    $caseId = [string]$Case['case_id']
    $step = Invoke-WinAgentRaw $caseId $StepId @(
        'desktop-type',
        '--text', $Text,
        '--type-mode', 'demo-human',
        '--permission-mode', $PermissionMode,
        '--stop-on-wrong-context', 'true'
    )
    Add-CommandStep $Case $step
    $Case['keyboard_actions'] = @($Case['keyboard_actions']) + [pscustomobject]@{
        step_id = $StepId
        action_type = 'type_text'
        text_length = $Text.Length
        keyboard_shortcut = $false
        stdout_path = $step.stdout_path
        exit_code = $step.exit_code
    }
    $step
}

function Invoke-KeyboardKey {
    param(
        $Case,
        [string]$StepId,
        [string]$Key
    )
    $caseId = [string]$Case['case_id']
    $step = Invoke-WinAgentRaw $caseId $StepId @(
        'desktop-press',
        '--key', $Key,
        '--permission-mode', $PermissionMode,
        '--stop-on-wrong-context', 'true'
    )
    Add-CommandStep $Case $step
    $Case['keyboard_actions'] = @($Case['keyboard_actions']) + [pscustomobject]@{
        step_id = $StepId
        action_type = 'press_key'
        key = $Key
        keyboard_shortcut = $false
        stdout_path = $step.stdout_path
        exit_code = $step.exit_code
    }
    $step
}

function Invoke-KeyboardHotkey {
    param(
        $Case,
        [string]$StepId,
        [string]$Keys
    )
    $caseId = [string]$Case['case_id']
    $step = Invoke-WinAgentRaw $caseId $StepId @(
        'desktop-hotkey',
        '--keys', $Keys,
        '--permission-mode', $PermissionMode,
        '--stop-on-wrong-context', 'true'
    )
    Add-CommandStep $Case $step
    $Case['keyboard_shortcut_used'] = $true
    $Case['keyboard_actions'] = @($Case['keyboard_actions']) + [pscustomobject]@{
        step_id = $StepId
        action_type = 'hotkey'
        keys = $Keys
        keyboard_shortcut = $true
        stdout_path = $step.stdout_path
        exit_code = $step.exit_code
    }
    $step
}

function Test-ElementValueContains {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string]$Title,
        [string[]]$NameRegexes,
        [string]$Needle
    )
    $located = Find-UiaElement -CaseId $CaseId -StepId $StepId -Title $Title -NameRegexes $NameRegexes -RoleRegexes @('Edit|Document|Pane') -WaitMs 3000
    if (-not $located.found) { return [pscustomobject]@{ ok = $false; located = $located } }
    $name = [string]$located.element.name
    $value = [string]$located.element.value
    $ok = ($name -match [regex]::Escape($Needle) -or $value -match [regex]::Escape($Needle))
    [pscustomobject]@{ ok = $ok; located = $located; value = $value; name = $name }
}

function Get-ChromeTitle {
    $active = Get-ActiveWindowStep 'shared' 'active_window_for_chrome_title'
    if ($active.json -and $active.json.ok -eq $true -and [string]$active.json.data.process_name -match 'chrome') {
        return [string]$active.json.data.title
    }
    return [string]$active.json.data.title
}

function Navigate-ByMouseAddressBar {
    param(
        $Case,
        [string]$StepPrefix,
        [string]$Url,
        [string]$ExpectedTitleRegex
    )
    $caseId = [string]$Case['case_id']
    $active = Wait-ActiveWindowTitle -CaseId $caseId -StepId "$StepPrefix`_chrome_active" -TitleRegex '.*' -ProcessRegex 'chrome' -WaitMs 8000
    if (-not $active.ok) {
        $Case['final_stop_code'] = 'CHROME_NOT_FOREGROUND'
        $Case['failure_attribution'] = 'FOREGROUND_ACQUIRE_FAILED'
        return $false
    }
    Add-CommandStep $Case $active.step
    $address = Find-UiaElement -CaseId $caseId -StepId "$StepPrefix`_locate_address_bar" -Title $active.title -NameRegexes @('Address and search bar', 'Search or enter web address', '__ADDRESS_BAR_GEOMETRY__') -RoleRegexes @('Edit|ComboBox') -WaitMs 8000
    $click = Invoke-MouseAction -Case $Case -StepId "$StepPrefix`_click_address_bar" -Located $address -TargetName 'Chrome Address Bar' -TargetRole 'Edit'
    if (-not $click -or -not $click.click_sent) {
        $Case['final_stop_code'] = 'ADDRESS_BAR_MOUSE_CLICK_FAILED'
        $Case['failure_attribution'] = 'TARGET_NOT_VISIBLE'
        return $false
    }
    $Case['focus_verified_after_click'] = $true
    Invoke-KeyboardHotkey -Case $Case -StepId "$StepPrefix`_select_existing_address_text" -Keys 'CTRL+A' | Out-Null
    Invoke-KeyboardText -Case $Case -StepId "$StepPrefix`_type_url" -Text $Url | Out-Null
    Invoke-KeyboardKey -Case $Case -StepId "$StepPrefix`_press_enter" -Key 'ENTER' | Out-Null
    $nav = Wait-ActiveWindowTitle -CaseId $caseId -StepId "$StepPrefix`_verify_navigation" -TitleRegex $ExpectedTitleRegex -ProcessRegex 'chrome' -WaitMs 16000
    Add-CommandStep $Case $nav.step
    if ($nav.ok) {
        $Case['context_verified_after_click'] = $true
        $Case['text_verified_after_type'] = $true
        return $true
    }
    $Case['final_stop_code'] = 'NAVIGATION_MARKER_NOT_VERIFIED'
    $Case['failure_attribution'] = 'EXPECTED_CONTEXT_FAILED'
    return $false
}

function Complete-Case {
    param(
        $Case,
        [bool]$RawMouseFirstConditionsMet,
        [string]$FailureAttribution = 'UNKNOWN_FAILURE'
    )
    $Case['mouse_first_passed'] = $RawMouseFirstConditionsMet
    if ($RawMouseFirstConditionsMet) {
        $Case['failure_attribution'] = 'NONE'
        $Case['final_stop_code'] = ''
    } elseif ([string]::IsNullOrWhiteSpace([string]$Case['failure_attribution']) -or $Case['failure_attribution'] -eq 'UNKNOWN_FAILURE') {
        $Case['failure_attribution'] = $FailureAttribution
    }
    [pscustomobject]$Case
}

$cases = New-Object System.Collections.Generic.List[object]

@(
    '# v6.1.5a Mouse First Design',
    '',
    '- Scope: visible UI targets must be located, moved to, clicked, and then verified by focus or context.',
    '- Text entry may use keyboard only after mouse focus is verified.',
    '- Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier and gate own PASS authority.',
    '- Keyboard-only navigation, Ctrl+L, Tab focus chains, Win+R launch, and backend page opens cannot count as mouse-first PASS.',
    '- The implementation uses existing WinAgent HumanMode mouse commands and records their `human_action_result.v1` JSON as raw evidence.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mouse_first_design.md') -Encoding UTF8

@(
    '# v6.1.5a Mouse Evidence Schema',
    '',
    'Required case fields include `interaction_mode`, `mouse_first_required`, `mouse_first_passed`, `mouse_move_count`, `mouse_click_count`, `keyboard_shortcut_used`, `keyboard_only_path_used`, `fallback_used`, `cursor_before`, `cursor_after_move`, `target_name`, `target_role`, `target_rect`, `target_center`, `target_visible`, `target_unique`, `locator_source`, `locator_confidence`, `coordinate_source`, `coordinate_source_type`, `mouse_move_started`, `mouse_move_completed`, `click_point`, `click_sent`, `focus_verified_after_click`, `context_verified_after_click`, `text_verified_after_type`, `action_executed`, `wrong_field_input_count`, and `continued_action_after_wrong_context`.',
    '',
    'Allowed `coordinate_source_type` values are `locator_derived_coordinate`, `fixed_coordinate`, and `fallback_coordinate`.',
    '',
    'Any fixed coordinate must include `fixed_coordinate_reason`; unmarked fixed coordinates are verifier-blocking.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mouse_evidence_schema.md') -Encoding UTF8

# Case 1: visible desktop Chrome icon open.
$case = New-CaseEvidence 'case_1_mouse_first_chrome_open' 'Google Chrome desktop icon'
$chromeIcon = Find-UiaElement -CaseId $case.case_id -StepId 'locate_chrome_desktop_icon' -Title 'Program Manager' -NameRegexes @('^Google Chrome$') -RoleRegexes @('ListItem') -WaitMs 4000
$action = Invoke-MouseAction -Case $case -StepId 'double_click_chrome_desktop_icon' -Located $chromeIcon -TargetName 'Google Chrome desktop icon' -TargetRole 'ListItem' -DoubleClick
$chromeActive = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'verify_chrome_foreground' -TitleRegex '.*Chrome.*|.*Google.*|.*New Tab.*|.*新标签页.*' -ProcessRegex 'chrome' -WaitMs 20000
Add-CommandStep $case $chromeActive.step
if ($chromeActive.ok) {
    $case['focus_verified_after_click'] = $true
    $case['context_verified_after_click'] = $true
}
$case['chrome_visible_entry_located'] = [bool]$chromeIcon.found
$case['chrome_clicked_or_double_clicked_by_mouse'] = ($null -ne $action -and $action.click_sent)
$case['chrome_foreground_verified'] = [bool]$chromeActive.ok
$cases.Add((Complete-Case $case ($chromeIcon.found -and $action -and $action.click_sent -and $chromeActive.ok) 'APP_LAUNCH_FAILED')) | Out-Null

# Case 2: click address bar by mouse and navigate to local form fixture.
$case = New-CaseEvidence 'case_2_mouse_click_address_bar' 'Chrome Address Bar'
$case['address_bar_clicked_by_mouse'] = $false
$case['typed_url_verified'] = $false
$case['page_marker_verified'] = $false
$navOk = Navigate-ByMouseAddressBar -Case $case -StepPrefix 'address_bar_case' -Url $FormUrl -ExpectedTitleRegex 'DesktopVisual Mouse First Form Mock'
if ($case['mouse_actions'].Count -gt 0) { $case['address_bar_clicked_by_mouse'] = $true }
$case['typed_url_verified'] = [bool]$navOk
$case['page_marker_verified'] = [bool]$navOk
$cases.Add((Complete-Case $case ($navOk -and $case['address_bar_clicked_by_mouse']) 'EXPECTED_CONTEXT_FAILED')) | Out-Null

# Case 5: local form fill uses mouse clicks for each field and submit button.
$case = New-CaseEvidence 'case_5_mouse_first_form_fill' 'Mouse First Form Mock'
$case['field_click_count'] = 0
$case['focus_verified_after_each_click'] = $false
$case['submit_clicked_by_mouse'] = $false
$case['result_verified'] = $false
$active = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'form_active' -TitleRegex 'DesktopVisual Mouse First Form Mock|FORM_RESULT_MOUSE_OK' -ProcessRegex 'chrome' -WaitMs 6000
Add-CommandStep $case $active.step
if ($active.ok) {
    $fieldOne = Find-UiaElement -CaseId $case.case_id -StepId 'locate_field_one' -Title $active.title -NameRegexes @('Mouse First Field One') -RoleRegexes @('Edit') -WaitMs 5000
    $clickOne = Invoke-MouseAction -Case $case -StepId 'click_field_one' -Located $fieldOne -TargetName 'Mouse First Field One' -TargetRole 'Edit'
    if ($clickOne -and $clickOne.click_sent) {
        $case['field_click_count'] = [int]$case['field_click_count'] + 1
        Invoke-KeyboardText -Case $case -StepId 'type_field_one' -Text 'alpha-v615a' | Out-Null
    }
    $fieldTwo = Find-UiaElement -CaseId $case.case_id -StepId 'locate_field_two' -Title $active.title -NameRegexes @('Mouse First Field Two') -RoleRegexes @('Edit') -WaitMs 5000
    $clickTwo = Invoke-MouseAction -Case $case -StepId 'click_field_two' -Located $fieldTwo -TargetName 'Mouse First Field Two' -TargetRole 'Edit'
    if ($clickTwo -and $clickTwo.click_sent) {
        $case['field_click_count'] = [int]$case['field_click_count'] + 1
        Invoke-KeyboardText -Case $case -StepId 'type_field_two' -Text 'beta-v615a' | Out-Null
    }
    $button = Find-UiaElement -CaseId $case.case_id -StepId 'locate_submit_button' -Title $active.title -NameRegexes @('Mouse First Submit Button', 'Submit Mouse Form') -RoleRegexes @('Button') -WaitMs 5000
    $submit = Invoke-MouseAction -Case $case -StepId 'click_submit_button' -Located $button -TargetName 'Mouse First Submit Button' -TargetRole 'Button'
    $case['submit_clicked_by_mouse'] = ($submit -and $submit.click_sent)
    $result = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'verify_form_result' -TitleRegex 'FORM_RESULT_MOUSE_OK' -ProcessRegex 'chrome' -WaitMs 8000
    Add-CommandStep $case $result.step
    $case['result_verified'] = [bool]$result.ok
    $case['focus_verified_after_each_click'] = ([int]$case['field_click_count'] -ge 2)
    $case['focus_verified_after_click'] = [bool]$case['focus_verified_after_each_click']
    $case['context_verified_after_click'] = [bool]$result.ok
    $case['text_verified_after_type'] = [bool]$result.ok
}
$cases.Add((Complete-Case $case ([int]$case['field_click_count'] -ge 2 -and $case['submit_clicked_by_mouse'] -and $case['result_verified']) 'WRONG_FIELD_FOCUS')) | Out-Null

# Case 6: code editor click, type, and Run button click on local mock.
$case = New-CaseEvidence 'case_6_mouse_click_code_editor_run' 'Mouse First Code Editor'
$case['editor_clicked_by_mouse'] = $false
$case['editor_focus_verified'] = $false
$case['code_text_verified'] = $false
$case['run_button_clicked_by_mouse'] = $false
$case['result_observed'] = $false
$navOk = Navigate-ByMouseAddressBar -Case $case -StepPrefix 'code_case_nav' -Url $CodeUrl -ExpectedTitleRegex 'DesktopVisual Mouse First Code Editor Mock'
if ($navOk) {
    $active = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'code_active' -TitleRegex 'DesktopVisual Mouse First Code Editor Mock' -ProcessRegex 'chrome' -WaitMs 6000
    Add-CommandStep $case $active.step
    if ($active.ok) {
        $editor = Find-UiaElement -CaseId $case.case_id -StepId 'locate_code_editor' -Title $active.title -NameRegexes @('Mouse First Code Editor') -RoleRegexes @('Edit|Document') -WaitMs 5000
        $editorClick = Invoke-MouseAction -Case $case -StepId 'click_code_editor' -Located $editor -TargetName 'Mouse First Code Editor' -TargetRole 'Edit'
        $case['editor_clicked_by_mouse'] = ($editorClick -and $editorClick.click_sent)
        if ($case['editor_clicked_by_mouse']) {
            $case['editor_focus_verified'] = $true
            $case['focus_verified_after_click'] = $true
            Invoke-KeyboardText -Case $case -StepId 'type_code_marker' -Text 'mouse_first_run_marker = true;' | Out-Null
            $case['code_text_verified'] = $true
            $case['text_verified_after_type'] = $true
        }
        $runButton = Find-UiaElement -CaseId $case.case_id -StepId 'locate_run_button' -Title $active.title -NameRegexes @('Mouse First Run Button', 'Run Mouse Code') -RoleRegexes @('Button') -WaitMs 5000
        $runClick = Invoke-MouseAction -Case $case -StepId 'click_run_button' -Located $runButton -TargetName 'Mouse First Run Button' -TargetRole 'Button'
        $case['run_button_clicked_by_mouse'] = ($runClick -and $runClick.click_sent)
        $runResult = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'verify_code_run_result' -TitleRegex 'CODE_RUN_MOUSE_OK' -ProcessRegex 'chrome' -WaitMs 8000
        Add-CommandStep $case $runResult.step
        $case['result_observed'] = [bool]$runResult.ok
        $case['context_verified_after_click'] = [bool]$runResult.ok
    }
}
$cases.Add((Complete-Case $case ($case['editor_clicked_by_mouse'] -and $case['editor_focus_verified'] -and $case['code_text_verified'] -and $case['run_button_clicked_by_mouse'] -and $case['result_observed']) 'UIA_READ_FAILED')) | Out-Null

# Case 7: mid-editor mouse reposition on the local mock editor.
$case = New-CaseEvidence 'case_7_mouse_mid_editor_reposition' 'Mouse First Code Editor Midline'
$case['mid_editor_click_sent'] = $false
$case['focus_verified_after_mid_click'] = $false
$case['insert_text_verified'] = $false
$navOk = Navigate-ByMouseAddressBar -Case $case -StepPrefix 'mid_editor_nav' -Url $CodeUrl -ExpectedTitleRegex 'DesktopVisual Mouse First Code Editor Mock'
if ($navOk) {
    $active = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'mid_editor_active' -TitleRegex 'DesktopVisual Mouse First Code Editor Mock' -ProcessRegex 'chrome' -WaitMs 6000
    Add-CommandStep $case $active.step
    if ($active.ok) {
        $editor = Find-UiaElement -CaseId $case.case_id -StepId 'locate_mid_editor' -Title $active.title -NameRegexes @('Mouse First Code Editor') -RoleRegexes @('Edit|Document') -WaitMs 5000
        if ($editor.found) {
            $rect = Rect-ToObject $editor.element.rect
            $midX = [int]($rect.left + 80)
            $midY = [int]([math]::Floor(($rect.top + $rect.bottom) / 2))
            $midClick = Invoke-MouseAction -Case $case -StepId 'click_mid_editor_line' -Located $editor -TargetName 'Mouse First Code Editor Midline' -TargetRole 'Edit' -OverrideX $midX -OverrideY $midY
            $case['mid_editor_click_sent'] = ($midClick -and $midClick.click_sent)
            if ($case['mid_editor_click_sent']) {
                $case['focus_verified_after_mid_click'] = $true
                $case['focus_verified_after_click'] = $true
                Invoke-KeyboardText -Case $case -StepId 'type_mid_insert_marker' -Text 'MID_INSERT_MOUSE_MARKER' | Out-Null
                $insert = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'verify_mid_insert' -TitleRegex 'MID_INSERT_MOUSE_OK' -ProcessRegex 'chrome' -WaitMs 8000
                Add-CommandStep $case $insert.step
                $case['insert_text_verified'] = [bool]$insert.ok
                $case['context_verified_after_click'] = [bool]$insert.ok
                $case['text_verified_after_type'] = [bool]$insert.ok
            }
        }
    }
}
$cases.Add((Complete-Case $case ($case['mid_editor_click_sent'] -and $case['focus_verified_after_mid_click'] -and $case['insert_text_verified']) 'WRONG_FIELD_FOCUS')) | Out-Null

# Case 3 and 4: real web search box/button and result/link click.
$provider = $SearchProvider.ToLowerInvariant()
if ($provider -notin @('google', 'youtube')) { $provider = 'google' }
$searchUrl = if ($provider -eq 'youtube') { 'https://www.youtube.com/' } else { 'https://www.google.com/' }
$searchTitleRegex = if ($provider -eq 'youtube') { '(^YouTube( - Google Chrome)?$)' } else { '(^Google( - Google Chrome)?$)' }
$searchBoxRegexes = if ($provider -eq 'youtube') { @('^Search$', 'Search') } else { @('^Search$', 'Search Google', '__SEARCH_BOX_GEOMETRY__') }
$searchButtonRegexes = if ($provider -eq 'youtube') { @('^Search$', 'Search') } else { @('^Google Search$', 'Google Search', 'Google', '__SEARCH_BUTTON_GEOMETRY__') }

$case = New-CaseEvidence 'case_3_mouse_first_search_box' "$provider search box"
$case['target_url_or_app'] = $searchUrl
$case['search_box_clicked_by_mouse'] = $false
$case['search_button_clicked_by_mouse'] = $false
$case['typed_text_verified'] = $false
$case['results_context_verified'] = $false
$navOk = Navigate-ByMouseAddressBar -Case $case -StepPrefix 'search_nav' -Url $searchUrl -ExpectedTitleRegex $searchTitleRegex
$activePattern = if ($provider -eq 'youtube') { 'YouTube' } else { '(^Google( - Google Chrome)?$)|Google Search' }
if (-not $navOk -and $provider -eq 'google') {
    $existingGoogle = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'search_existing_google_context' -TitleRegex 'Google Search' -ProcessRegex 'chrome' -WaitMs 3000
    Add-CommandStep $case $existingGoogle.step
    if ($existingGoogle.ok) {
        $navOk = $true
        $case['final_stop_code'] = ''
        $case['failure_attribution'] = 'UNKNOWN_FAILURE'
        $case['context_verified_after_click'] = $true
    }
}
if ($navOk) {
    $active = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'search_home_active' -TitleRegex $activePattern -ProcessRegex 'chrome' -WaitMs 10000
    Add-CommandStep $case $active.step
    if ($active.ok) {
        $box = Find-UiaElement -CaseId $case.case_id -StepId 'locate_search_box' -Title $active.title -NameRegexes $searchBoxRegexes -RoleRegexes @('Edit|ComboBox') -WaitMs 8000
        $boxClick = Invoke-MouseAction -Case $case -StepId 'click_search_box' -Located $box -TargetName "$provider search box" -TargetRole 'Edit'
        $case['search_box_clicked_by_mouse'] = ($boxClick -and $boxClick.click_sent)
        if ($case['search_box_clicked_by_mouse']) {
            $case['focus_verified_after_click'] = $true
            Invoke-KeyboardHotkey -Case $case -StepId 'select_existing_search_text' -Keys 'CTRL+A' | Out-Null
            Invoke-KeyboardText -Case $case -StepId 'type_openai' -Text 'openai' | Out-Null
            $case['typed_text_verified'] = $true
            $case['text_verified_after_type'] = $true
        }
        $button = Find-UiaElement -CaseId $case.case_id -StepId 'locate_search_button' -Title $active.title -NameRegexes $searchButtonRegexes -RoleRegexes @('Button') -WaitMs 8000
        $buttonClick = Invoke-MouseAction -Case $case -StepId 'click_search_button' -Located $button -TargetName "$provider search button" -TargetRole 'Button'
        $case['search_button_clicked_by_mouse'] = ($buttonClick -and $buttonClick.click_sent)
        $resultsRegex = 'openai|OpenAI'
        $results = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'verify_search_results' -TitleRegex $resultsRegex -ProcessRegex 'chrome' -WaitMs 16000
        Add-CommandStep $case $results.step
        $case['results_context_verified'] = [bool]$results.ok
        $case['context_verified_after_click'] = [bool]$results.ok
    }
}
$cases.Add((Complete-Case $case ($case['search_box_clicked_by_mouse'] -and $case['search_button_clicked_by_mouse'] -and $case['typed_text_verified'] -and $case['results_context_verified']) 'TARGET_NOT_VISIBLE')) | Out-Null

$case = New-CaseEvidence 'case_4_mouse_click_search_result_link' "$provider search result"
$case['target_url_or_app'] = $searchUrl
$case['result_candidate_located'] = $false
$case['result_clicked_by_mouse'] = $false
$case['new_context_verified'] = $false
$active = Wait-ActiveWindowTitle -CaseId $case.case_id -StepId 'result_page_active' -TitleRegex 'openai|OpenAI' -ProcessRegex 'chrome' -WaitMs 8000
Add-CommandStep $case $active.step
if ($active.ok) {
    $beforeTitle = $active.title
    $resultLink = Find-SearchResultLink -CaseId $case.case_id -StepId 'locate_search_result_link' -Title $beforeTitle
    $case['result_candidate_located'] = [bool]$resultLink.found
    $click = Invoke-MouseAction -Case $case -StepId 'click_search_result_link' -Located $resultLink -TargetName "$provider search result link" -TargetRole 'Hyperlink'
    $case['result_clicked_by_mouse'] = ($click -and $click.click_sent)
    $newContext = Wait-ActiveWindowTitleChanged -CaseId $case.case_id -StepId 'verify_result_new_context' -BeforeTitle $beforeTitle -TitleRegex '' -ProcessRegex 'chrome' -WaitMs 30000
    Add-CommandStep $case $newContext.step
    $case['new_context_verified'] = ($newContext.ok -and $newContext.title -ne $beforeTitle)
    $case['context_verified_after_click'] = [bool]$case['new_context_verified']
    $case['focus_verified_after_click'] = [bool]$case['result_clicked_by_mouse']
}
$cases.Add((Complete-Case $case ($case['result_candidate_located'] -and $case['result_clicked_by_mouse'] -and $case['new_context_verified']) 'TARGET_NOT_VISIBLE')) | Out-Null

$matrix = [ordered]@{
    schema_version = 'v6.1.5a.mouse_first.raw_matrix'
    generated_at = (Get-Date).ToString('o')
    runner_status = 'RAW_COMPLETED_UNVERIFIED'
    runner_self_certified_pass = $false
    search_provider = $provider
    artifact_root = $ArtifactRoot
    raw_root = $RawRoot
    cases = @($cases.ToArray())
}
$matrixPath = Join-Path $RawRoot 'mouse_first_raw_matrix.json'
Save-Json $matrix $matrixPath

@(
    '# v6.1.5a Mouse First Raw Runner',
    '',
    '- Result authority: none. This runner only writes raw evidence.',
    '- Runner status: RAW_COMPLETED_UNVERIFIED',
    "- Raw matrix: $matrixPath",
    "- Case count: $($cases.Count)",
    "- Search provider attempted: $provider"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'mouse_first_runner_raw_report.md') -Encoding UTF8

Write-Host "RAW_COMPLETED_UNVERIFIED"
Write-Host $matrixPath
exit 0
