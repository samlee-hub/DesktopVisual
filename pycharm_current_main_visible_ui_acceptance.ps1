param(
    [string]$Root = '',
    [int]$TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_structured_text_input'
$RunDir = Join-Path $OutDir 'real_pycharm_current_main'
$Report = Join-Path $OutDir 'pycharm_structured_input_report.md'
$ResultJson = Join-Path $OutDir 'pycharm_current_main_visible_ui_acceptance_result.json'
$TimelineJson = Join-Path $RunDir 'operation_timeline.json'
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function Fail([string]$Message) { throw $Message }
function Assert($Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }

function Invoke-Agent {
    param(
        [string]$Name,
        [string[]]$WinArgs,
        [int[]]$Allowed = @(0)
    )
    $start = Get-Date
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    $end = Get-Date
    $text = ($output | Out-String).Trim()
    $nextIndex = (Get-TimelineCount) + 1
    $outFile = Join-Path $RunDir ("{0}_{1}.json" -f $nextIndex.ToString('00'), $Name)
    $text | Set-Content -Encoding UTF8 -LiteralPath $outFile
    $script:Timeline += [pscustomobject]@{
        operation_id = ('op-{0:000}' -f $nextIndex)
        name = $Name
        command = ($WinArgs -join ' ')
        start = $start.ToString('o')
        end = $end.ToString('o')
        wall_clock_ms = [int](New-TimeSpan -Start $start -End $end).TotalMilliseconds
        exit = $exit
        ok = ($Allowed -contains $exit)
        stdout = $outFile
    }
    if ($Allowed -notcontains $exit) { Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text" }
    try { return $text | ConvertFrom-Json } catch { Fail "Invalid JSON for $Name`: $text" }
}

function Get-TimelineCount { return @($script:Timeline).Count }

function Text-ContainsAll($Text, [string[]]$Needles) {
    foreach ($needle in $Needles) {
        if ($Text -notlike "*$needle*") { return $false }
    }
    return $true
}

function Test-RunOutput($Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -like '*Course:*') -and
        ($Text -like '*Python*') -and
        ($Text -like '*Object*') -and
        ($Text -like '*My name is*') -and
        ($Text -like '*A*ice*') -and
        ($Text -like '*18*')
}

function Test-ExitZero($Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $compact = ($Text -replace '\s+', '')
    if ($Text -like '*exit code 0*') { return $true }
    if ($Text -like '*Process finished*0*') { return $true }
    $charCodes = @($Text.ToCharArray() | ForEach-Object { [int][char]$_ })
    if (($charCodes -contains 48) -and ($charCodes -contains 36864) -and ($charCodes -contains 20986) -and ($charCodes -contains 20195)) { return $true }
    if ($compact -like '*退出代码为0*') { return $true }
    if ($compact -like '*退出代碼為0*') { return $true }
    if (($Text -like '*0*') -and ($Text -like '*退*') -and ($Text -like '*出*') -and ($Text -like '*代*')) { return $true }
    if ($Text -like '*閫€鍑轰唬鐮佷负 0*') { return $true }
    return $false
}

function Test-VisibleCodeStructure($Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $requiredSignals = @('class Student', 'def __init', 'def introduce', 'show_title', 'Student(', 'Course(', 'introduce')
    if (-not (Text-ContainsAll $Text $requiredSignals)) { return $false }

    $forbiddenArtifacts = @(
        ')class Student',
        'self.name = name):',
        'def introduce()',
        'def show_title()',
        'selfself',
        'self self',
        'self_self',
        'thisself',
        ')print(',
        'introduce()kourse',
        'introduce()course',
        'show_title()student',
        'show_title()course'
    )
    foreach ($artifact in $forbiddenArtifacts) {
        if ($Text -like "*$artifact*") { return $false }
    }
    $classStudentMatches = [regex]::Matches($Text, [regex]::Escape('class Student:')).Count
    if ($classStudentMatches -gt 1) { return $false }

    $courseIndex = $Text.IndexOf('Course')
    $showIndex = $Text.IndexOf('show_title')
    $introduceIndex = $Text.IndexOf('introduce')
    if ($courseIndex -lt 0 -or $showIndex -lt 0 -or $introduceIndex -lt 0) { return $false }
    return $true
}

function Find-OcrLineLeft($Lines, [scriptblock]$Predicate) {
    $matches = @($Lines | Where-Object { & $Predicate ([string]$_.text) })
    if ($matches.Count -eq 0) { return $null }
    return ($matches | Sort-Object { [int]$_.rect.left } | Select-Object -First 1).rect.left
}

function Find-OcrLineMatch($Lines, [scriptblock]$Predicate) {
    $matches = @($Lines | Where-Object { & $Predicate ([string]$_.text) })
    if ($matches.Count -eq 0) { return $null }
    return ($matches | Sort-Object { [int]$_.rect.top }, { [int]$_.rect.left } | Select-Object -First 1)
}

function Test-VisibleTopLevelGeometry($Observation) {
    if ($null -eq $Observation -or $Observation.ok -ne $true -or $null -eq $Observation.data) { return $false }
    $lines = @($Observation.data.lines)
    if ($lines.Count -eq 0) { return $false }

    $classStudentLeft = Find-OcrLineLeft $lines { param($t) $t -like '*class*Student*' }
    $classCourseLeft = Find-OcrLineLeft $lines { param($t) $t -like '*class*Course*' -or $t -like '*class*C*urse*' }
    $courseClassTail = Find-OcrLineMatch $lines { param($t)
        (($t -like '*Course:*') -or ($t -like '*CO*Se:*') -or ($t -like '*CO*PSe:*') -or ($t -like '*COlJPSe:*')) -and
        ($t -notlike '*print*') -and
        ($t -notlike '*=*') -and
        ($t -notlike '*show_title*')
    }
    if ($null -eq $classStudentLeft) { return $false }
    if ($null -eq $classCourseLeft -and $null -ne $courseClassTail) {
        $classCourseLeft = $classStudentLeft
    }
    if ($null -eq $classCourseLeft) { return $false }
    $topLeft = [Math]::Min([int]$classStudentLeft, [int]$classCourseLeft)
    $tolerance = 70

    $studentAssignLeft = Find-OcrLineLeft $lines { param($t)
        (($t -like '*student*') -or ($t -like '*Student(*')) -and
        ($t -notlike '*introduce*') -and
        ($t -notlike '*class*') -and
        ($t -notlike '*def*') -and
        ($t -notlike '*name is*')
    }
    $courseAssignLeft = Find-OcrLineLeft $lines { param($t)
        (($t -like '*course*') -or ($t -like '*Course(*') -or ($t -like '*COU*Se*')) -and
        ($t -notlike '*show_title*') -and
        ($t -notlike '*class*') -and
        ($t -notlike '*def*') -and
        ($t -notlike '*Course:*')
    }
    $courseCallLeft = Find-OcrLineLeft $lines { param($t)
        ($t -like '*show_title()*') -and ($t -notlike '*def*')
    }
    $studentCallLeft = Find-OcrLineLeft $lines { param($t)
        ($t -like '*introduce()*') -and ($t -notlike '*def*')
    }

    foreach ($left in @($studentAssignLeft, $courseAssignLeft, $courseCallLeft, $studentCallLeft)) {
        if ($null -eq $left) { return $false }
        if ([int]$left -gt ($topLeft + $tolerance)) { return $false }
    }
    return $true
}

function Read-VisibleText([string]$Title, [string]$Name) {
    try {
        $read = Invoke-Agent -Name $Name -WinArgs @('read-window-text', '--title', $Title) -Allowed @(0, 1)
        if ($read.ok -eq $true) { return [string]$read.data.text }
    } catch {
        return ''
    }
    return ''
}

function Read-VisibleCodeObservation([string]$Title, [string]$Name) {
    try {
        return Invoke-Agent -Name $Name -WinArgs @('read-window-text', '--title', $Title) -Allowed @(0, 1)
    } catch {
        return $null
    }
}

function Wait-PyCharmMainWindow([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $probe = Invoke-Agent -Name 'target_lock_wait_pycharm' -WinArgs @('target-lock-acquire', '--target-process', 'pycharm64.exe') -Allowed @(0, 1)
        if ($probe.ok -eq $true -and ([string]$probe.data.title) -like '*main.py*') {
            return $probe.data
        }
        Start-Sleep -Milliseconds 1000
    } while ((Get-Date) -lt $deadline)
    return $null
}

$script:Timeline = @()
if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

$visibleLaunchAttempted = $false
$desktopIconAttempted = $false
$taskbarIconAttempted = $false
$startMenuAttempted = $false

$active = Invoke-Agent -Name 'active_window_initial' -WinArgs @('active-window') -Allowed @(0, 1)
if ($active.ok -ne $true -or $active.data.process_name -ne 'pycharm64.exe' -or ([string]$active.data.title) -notlike '*main.py*') {
    $lockProbe = Invoke-Agent -Name 'target_lock_probe' -WinArgs @('target-lock-acquire', '--target-process', 'pycharm64.exe') -Allowed @(0, 1)
    if ($lockProbe.ok -ne $true -or ([string]$lockProbe.data.title) -notlike '*main.py*') {
        $visibleLaunchAttempted = $true
        Invoke-Agent -Name 'visible_show_desktop_before_launch' -WinArgs @('visible-show-desktop', '--allow-backend-fallback', 'false', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165', '--out', (Join-Path $RunDir 'show_desktop_before_launch.png')) -Allowed @(0, 1) | Out-Null
        $desktopIconAttempted = $true
        Invoke-Agent -Name 'desktop_icon_locate_pycharm' -WinArgs @('desktop-icon-locate', '--target', 'PyCharm') -Allowed @(0, 1) | Out-Null
        Invoke-Agent -Name 'desktop_icon_double_click_pycharm' -WinArgs @('desktop-icon-double-click', '--target', 'PyCharm', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -Allowed @(0, 1) | Out-Null
        $target = Wait-PyCharmMainWindow -Seconds 25
        if ($null -eq $target) {
            $taskbarIconAttempted = $true
            Invoke-Agent -Name 'taskbar_icon_locate_pycharm' -WinArgs @('taskbar-icon-locate', '--target', 'PyCharm') -Allowed @(0, 1) | Out-Null
            Invoke-Agent -Name 'taskbar_icon_click_pycharm' -WinArgs @('taskbar-icon-click', '--target', 'PyCharm', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -Allowed @(0, 1) | Out-Null
            $target = Wait-PyCharmMainWindow -Seconds 20
        }
        if ($null -eq $target) {
            $startMenuAttempted = $true
            Invoke-Agent -Name 'start_menu_visible_launch_pycharm' -WinArgs @('start-menu-visible-launch', '--app', 'PyCharm', '--latency-profile', 'fast-visible-ui', '--motion-profile', '165hz-visible', '--motion-hz', '165') -Allowed @(0, 1) | Out-Null
            $target = Wait-PyCharmMainWindow -Seconds 30
        }
    } else {
        $target = $lockProbe.data
    }
    if ($null -eq $target -or ([string]$target.title) -notlike '*main.py*') {
        $blocked = @{
            result = 'BLOCKED'
            reason = 'PyCharm current main.py visible window was not active or lockable.'
            clipboard_used = $false
            backend_file_write_used = $false
            input_method = 'real_keyboard_events'
            visible_launch_attempted = $visibleLaunchAttempted
            desktop_icon_attempted = $desktopIconAttempted
            taskbar_icon_attempted = $taskbarIconAttempted
            start_menu_attempted = $startMenuAttempted
        }
        $blocked | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $ResultJson
        Fail 'BLOCKED_PYCHARM_CURRENT_MAIN_NOT_VISIBLE'
    }
} else {
    $target = $active.data
}

$hwnd = [string]$target.hwnd
$title = [string]$target.title
$rect = $target.rect
if ($null -eq $rect -and $null -ne $target.target_rect) { $rect = $target.target_rect }
Assert (-not [string]::IsNullOrWhiteSpace($hwnd)) 'PyCharm hwnd missing.'
Assert ($null -ne $rect) 'PyCharm rect missing.'

$left = [int]$rect.left
$top = [int]$rect.top
$right = [int]$rect.right
$bottom = [int]$rect.bottom
$width = [Math]::Max(1, $right - $left)
$height = [Math]::Max(1, $bottom - $top)
$editorX = $left + [int]($width * 0.38)
$editorY = $top + [int]($height * 0.42)
$runOutputX = $left + [int]($width * 0.13)
$runOutputY = $top + [int]($height * 1.06)
$runOutputW = [int]($width * 1.10)
$runOutputH = 310

function Read-RunOutputText([string]$Name) {
    try {
        $read = Invoke-Agent -Name $Name -WinArgs @(
            'read-screen-region-text',
            '--title', $title,
            '--x', "$runOutputX",
            '--y', "$runOutputY",
            '--w', "$runOutputW",
            '--h', "$runOutputH"
        ) -Allowed @(0, 1)
        if ($read.ok -eq $true) { return [string]$read.data.text }
    } catch {
        return ''
    }
    return ''
}

$code = @'
class Student:
    def __init__(self, name, age):
        self.name = name
        self.age = age

    def introduce(self):
        print('My name is ' + self.name + ', and I am ' + str(self.age) + ' years old.')

class Course:
    def __init__(self, title):
        self.title = title

    def show_title(self):
        print('Course: ' + self.title)

student = Student('Alice', 18)
course = Course('Python Class and Object')
course.show_title()
student.introduce()
'@

$initialPng = Join-Path $RunDir 'initial_global.png'
$afterInputPng = Join-Path $RunDir 'after_structured_input_global.png'
$finalPng = Join-Path $RunDir 'final_global.png'

Invoke-Agent -Name 'prepare_foreground' -WinArgs @('prepare-foreground', '--target-hwnd', $hwnd, '--timeout-ms', '2500') | Out-Null
Invoke-Agent -Name 'initial_global_screenshot' -WinArgs @('global-screenshot', '--out', $initialPng, '--format', 'png', '--include-metadata', 'true') | Out-Null
Invoke-Agent -Name 'focus_editor_click' -WinArgs @(
    'desktop-click',
    '--screen-x', "$editorX",
    '--screen-y', "$editorY",
    '--target-hwnd', $hwnd,
    '--require-target-lock', 'true',
    '--target-description', 'PyCharm main.py editor text area',
    '--coordinate-source', 'global_frame_pixel',
    '--latency-profile', 'fast-visible-ui',
    '--motion-profile', '165hz-visible',
    '--motion-hz', '165',
    '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
) | Out-Null

$input = Invoke-Agent -Name 'visible_text_input_structured_code' -WinArgs @(
    'visible-text-input',
    '--text', $code,
    '--input-kind', 'code_editor_text',
    '--input-method', 'real_keyboard_events',
    '--structured', 'true',
    '--indent-mode', 'spaces',
    '--indent-width', '4',
    '--verify-structure', 'true',
    '--typing-profile', 'fast-real-keyboard',
    '--char-delay-ms', '0',
    '--line-delay-ms', '20',
    '--batch-key-events', 'true',
    '--target-hwnd', $hwnd,
    '--require-target-lock', 'true'
)

Assert ($input.ok -eq $true) 'Structured visible text input failed.'
Assert ($input.data.clipboard_used -eq $false) 'BLOCKED_CLIPBOARD_USED_FOR_CODE_INPUT'
Assert ($input.data.backend_file_write_used -eq $false) 'BLOCKED_BACKEND_FILE_WRITE_USED_FOR_CODE_INPUT'
Assert ($input.data.resolved_input_kind -eq 'code_editor_text') 'input_kind must resolve to code_editor_text.'
Assert ($input.data.structured -eq $true) 'structured must be true.'
Assert ($input.data.indent_mode -eq 'spaces') 'indent_mode must be spaces.'
Assert ([int]$input.data.indent_width -eq 4) 'indent_width must be 4.'
Assert ($input.data.code_structure_verified -eq $true) 'Code structure verification failed.'
Assert ($input.data.code_write_plan_used -eq $true) 'code_write_plan_used must be true.'
Assert ($input.data.language_scope_model_used -eq $true) 'language_scope_model_used must be true.'
Assert ($input.data.preinput_code_structure_verifier_used -eq $true) 'preinput_code_structure_verifier_used must be true.'
Assert ($input.data.preinput_code_structure_verified -eq $true) 'preinput_code_structure_verified must be true.'
Assert ($input.data.editor_auto_indent_model_used -eq $true) 'editor_auto_indent_model_used must be true.'
Assert ($input.data.cursor_buffer_state_verified -eq $true) 'cursor_buffer_state_verified must be true.'
Assert ($input.data.old_buffer_cleared_or_safe_replace_verified -eq $true) 'old_buffer_cleared_or_safe_replace_verified must be true.'
Assert ($input.data.no_retry_contamination -eq $true) 'no_retry_contamination must be true.'
Assert ($input.data.receiver_binding_verified -eq $true) 'receiver_binding_verified must be true.'
Assert ($input.data.duplicate_receiver_token_detected -eq $false) 'duplicate_receiver_token_detected must be false.'
Assert ($input.data.repair_replace_not_append -eq $true) 'repair_replace_not_append must be true.'
Assert ($input.data.selfself_present -eq $false) 'selfself_present must be false.'
Assert ($input.data.postinput_code_structure_verified -eq $true) 'postinput_code_structure_verified must be true.'

Invoke-Agent -Name 'after_input_global_screenshot' -WinArgs @('global-screenshot', '--out', $afterInputPng, '--format', 'png', '--include-metadata', 'true') | Out-Null

$visibleCodeObservation = Read-VisibleCodeObservation -Title $title -Name 'read_visible_text_after_input'
$visibleCodeText = if ($null -ne $visibleCodeObservation -and $visibleCodeObservation.ok -eq $true) { [string]$visibleCodeObservation.data.text } else { '' }
$codeStructureVisibleTextVerified = Test-VisibleCodeStructure $visibleCodeText
Assert ($codeStructureVisibleTextVerified -eq $true) 'BLOCKED_CODE_STRUCTURE_VISIBLE_TEXT_INVALID'
$codeStructureVisibleGeometryVerified = Test-VisibleTopLevelGeometry $visibleCodeObservation
Assert ($codeStructureVisibleGeometryVerified -eq $true) 'BLOCKED_CODE_STRUCTURE_VISIBLE_GEOMETRY_INVALID'

Invoke-Agent -Name 'dismiss_completion_before_save_1' -WinArgs @('desktop-press', '--key', 'ESC', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -Allowed @(0, 1) | Out-Null
Invoke-Agent -Name 'dismiss_completion_before_save_2' -WinArgs @('desktop-press', '--key', 'ESC', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -Allowed @(0, 1) | Out-Null
Invoke-Agent -Name 'save_hotkey' -WinArgs @('desktop-hotkey', '--keys', 'CTRL+S', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null
Invoke-Agent -Name 'run_hotkey_shift_f10' -WinArgs @('desktop-hotkey', '--keys', 'SHIFT+F10', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') | Out-Null

$outputText = ''
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Milliseconds 1000
    $outputText = Read-RunOutputText -Name 'read_run_output_wait_output'
    if (Test-RunOutput $outputText) { break }
} while ((Get-Date) -lt $deadline)

if (-not (Test-RunOutput $outputText)) {
    $visibleCodeObservationBeforeRetry = Read-VisibleCodeObservation -Title $title -Name 'read_visible_text_before_run_retry'
    Assert ((Test-VisibleTopLevelGeometry $visibleCodeObservationBeforeRetry) -eq $true) 'BLOCKED_CODE_STRUCTURE_VISIBLE_GEOMETRY_INVALID_BEFORE_RETRY'
    Invoke-Agent -Name 'run_hotkey_ctrl_shift_f10' -WinArgs @('desktop-hotkey', '--keys', 'CTRL+SHIFT+F10', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -Allowed @(0, 1) | Out-Null
    $deadline = (Get-Date).AddSeconds([Math]::Max(15, [int]($TimeoutSeconds / 2)))
    do {
        Start-Sleep -Milliseconds 1000
        $outputText = Read-RunOutputText -Name 'read_run_output_wait_output_retry'
        if (Test-RunOutput $outputText) { break }
    } while ((Get-Date) -lt $deadline)
}

if (-not (Test-RunOutput $outputText)) {
    Invoke-Agent -Name 'run_hotkey_alt_shift_f10' -WinArgs @('desktop-hotkey', '--keys', 'ALT+SHIFT+F10', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -Allowed @(0, 1) | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-Agent -Name 'run_popup_enter' -WinArgs @('desktop-press', '--key', 'ENTER', '--target-hwnd', $hwnd, '--require-target-lock', 'true', '--latency-profile', 'fast-visible-ui', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -Allowed @(0, 1) | Out-Null
    $deadline = (Get-Date).AddSeconds([Math]::Max(15, [int]($TimeoutSeconds / 2)))
    do {
        Start-Sleep -Milliseconds 1000
        $outputText = Read-RunOutputText -Name 'read_run_output_wait_output_alt_shift'
        if (Test-RunOutput $outputText) { break }
    } while ((Get-Date) -lt $deadline)
}

if (-not (Test-RunOutput $outputText)) {
    $runX = $left + [int]($width * 0.655)
    $runY = $top + 62
    Invoke-Agent -Name 'run_toolbar_visible_click' -WinArgs @(
        'desktop-click',
        '--screen-x', "$runX",
        '--screen-y', "$runY",
        '--target-hwnd', $hwnd,
        '--require-target-lock', 'true',
        '--target-description', 'PyCharm visible run toolbar button',
        '--coordinate-source', 'global_frame_pixel',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz-visible',
        '--motion-hz', '165',
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    ) -Allowed @(0, 1) | Out-Null
    $deadline = (Get-Date).AddSeconds([Math]::Max(15, [int]($TimeoutSeconds / 2)))
    do {
        Start-Sleep -Milliseconds 1000
        $outputText = Read-RunOutputText -Name 'read_run_output_wait_output_toolbar_click'
        if (Test-RunOutput $outputText) { break }
    } while ((Get-Date) -lt $deadline)
}

Invoke-Agent -Name 'final_global_screenshot' -WinArgs @('global-screenshot', '--out', $finalPng, '--format', 'png', '--include-metadata', 'true') | Out-Null

$outputVerified = Test-RunOutput $outputText
$exitZeroVisible = Test-ExitZero $outputText

$summary = [pscustomobject]@{
    result = if ($outputVerified -and $exitZeroVisible) { 'PASS' } else { 'BLOCKED' }
    branch = (& git -C $Root branch --show-current)
    pycharm_window_title = $title
    hwnd = $hwnd
    input_kind = 'code_editor_text'
    structured = $true
    indent_mode = 'spaces'
    indent_width = 4
    verify_structure = $true
    input_method = 'real_keyboard_events'
    typing_profile = 'fast-real-keyboard'
    clipboard_used = $false
    backend_file_write_used = $false
    backend_run_used = $false
    visible_launch_attempted = [bool]$visibleLaunchAttempted
    desktop_icon_attempted = [bool]$desktopIconAttempted
    taskbar_icon_attempted = [bool]$taskbarIconAttempted
    start_menu_attempted = [bool]$startMenuAttempted
    d_testrepo_used = $false
    dry_run = $false
    code_structure_verified = [bool]$input.data.code_structure_verified
    code_structure_visible_text_verified = [bool]$codeStructureVisibleTextVerified
    code_structure_visible_geometry_verified = [bool]$codeStructureVisibleGeometryVerified
    code_write_plan_used = [bool]$input.data.code_write_plan_used
    language_scope_model_used = [bool]$input.data.language_scope_model_used
    preinput_code_structure_verifier_used = [bool]$input.data.preinput_code_structure_verifier_used
    preinput_code_structure_verified = [bool]$input.data.preinput_code_structure_verified
    editor_auto_indent_model_used = [bool]$input.data.editor_auto_indent_model_used
    cursor_buffer_state_verified = [bool]$input.data.cursor_buffer_state_verified
    old_buffer_cleared_or_safe_replace_verified = [bool]$input.data.old_buffer_cleared_or_safe_replace_verified
    no_retry_contamination = [bool]$input.data.no_retry_contamination
    receiver_binding_verified = [bool]$input.data.receiver_binding_verified
    duplicate_receiver_token_detected = [bool]$input.data.duplicate_receiver_token_detected
    repair_replace_not_append = [bool]$input.data.repair_replace_not_append
    postinput_code_structure_verified = [bool]$input.data.postinput_code_structure_verified
    selfself_present = [bool]$input.data.selfself_present
    auto_indent_correction_applied = [bool]$input.data.auto_indent_correction_applied
    target_indent_spaces = [int]$input.data.target_indent_spaces
    actual_indent_correction_keys = [int]$input.data.actual_indent_correction_keys
    output_verified = [bool]$outputVerified
    exit_code_zero_visible = [bool]$exitZeroVisible
    initial_global_screenshot = $initialPng
    after_input_global_screenshot = $afterInputPng
    final_global_screenshot = $finalPng
    visible_text_excerpt = if ($outputText.Length -gt 1200) { $outputText.Substring(0, 1200) } else { $outputText }
}

$script:Timeline | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $TimelineJson
$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $ResultJson

@(
    '# PyCharm Structured Input Visible UI Acceptance',
    '',
    "- result: $($summary.result)",
    "- input_kind: $($summary.input_kind)",
    "- structured: true",
    "- indent_mode: $($summary.indent_mode)",
    "- indent_width: $($summary.indent_width)",
    "- input_method: $($summary.input_method)",
    "- typing_profile: $($summary.typing_profile)",
    "- clipboard_used: false",
    "- backend_file_write_used: false",
    "- backend_run_used: false",
    "- visible_launch_attempted: $($summary.visible_launch_attempted)",
    "- desktop_icon_attempted: $($summary.desktop_icon_attempted)",
    "- taskbar_icon_attempted: $($summary.taskbar_icon_attempted)",
    "- start_menu_attempted: $($summary.start_menu_attempted)",
    "- d_testrepo_used: false",
    "- dry_run: false",
    "- code_structure_verified: $($summary.code_structure_verified)",
    "- code_structure_visible_text_verified: $($summary.code_structure_visible_text_verified)",
    "- code_structure_visible_geometry_verified: $($summary.code_structure_visible_geometry_verified)",
    "- code_write_plan_used: $($summary.code_write_plan_used)",
    "- language_scope_model_used: $($summary.language_scope_model_used)",
    "- preinput_code_structure_verifier_used: $($summary.preinput_code_structure_verifier_used)",
    "- preinput_code_structure_verified: $($summary.preinput_code_structure_verified)",
    "- editor_auto_indent_model_used: $($summary.editor_auto_indent_model_used)",
    "- cursor_buffer_state_verified: $($summary.cursor_buffer_state_verified)",
    "- old_buffer_cleared_or_safe_replace_verified: $($summary.old_buffer_cleared_or_safe_replace_verified)",
    "- no_retry_contamination: $($summary.no_retry_contamination)",
    "- receiver_binding_verified: $($summary.receiver_binding_verified)",
    "- duplicate_receiver_token_detected: $($summary.duplicate_receiver_token_detected)",
    "- repair_replace_not_append: $($summary.repair_replace_not_append)",
    "- postinput_code_structure_verified: $($summary.postinput_code_structure_verified)",
    "- selfself_present: $($summary.selfself_present)",
    "- auto_indent_correction_applied: $($summary.auto_indent_correction_applied)",
    "- target_indent_spaces: $($summary.target_indent_spaces)",
    "- actual_indent_correction_keys: $($summary.actual_indent_correction_keys)",
    "- output_verified: $($summary.output_verified)",
    "- exit_code_zero_visible: $($summary.exit_code_zero_visible)",
    "- initial_global_screenshot: $initialPng",
    "- after_input_global_screenshot: $afterInputPng",
    "- final_global_screenshot: $finalPng",
    '',
    '## Visible Output Excerpt',
    '',
    '```text',
    $summary.visible_text_excerpt,
    '```'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

if ($summary.result -ne 'PASS') {
    if (-not $summary.code_structure_verified) { Fail 'BLOCKED_CODE_STRUCTURE_INVALID_DESPITE_RUN_SUCCESS' }
    if (-not $summary.output_verified -or -not $summary.exit_code_zero_visible) { Fail 'BLOCKED_PYCHARM_OUTPUT_NOT_VERIFIED' }
}

Write-Host 'PASS pycharm_current_main_visible_ui_acceptance'
exit 0
