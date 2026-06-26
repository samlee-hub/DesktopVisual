param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_structured_text_input'
$Report = Join-Path $OutDir 'indentation_controller_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }
function Assert($Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }
function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($Allowed -notcontains $exit) { Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text" }
    try { return $text | ConvertFrom-Json } catch { Fail "Invalid JSON: $text" }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

$code = @'
class Student:
    def introduce(self):
        if True:
            print('Alice')

    def second(self):
        print('Second')

class Course:
    def show_title(self):
        print('Course: Python Class and Object')

student = Student()
'@

$result = Invoke-Agent @(
    'visible-text-input', '--text', $code,
    '--input-kind', 'code_editor_text',
    '--structured', 'true',
    '--indent-mode', 'spaces',
    '--indent-width', '4',
    '--verify-structure', 'true',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true'
)
Assert ($result.ok -eq $true) 'indentation controller dry-run should pass.'
Assert ($result.data.auto_indent_detected -eq $true) 'auto-indent drift should be detected after first line.'
Assert ([int]$result.data.actual_indent_correction_keys -lt 20) 'natural auto-indent should avoid max Shift+Tab correction per line.'

$plans = @($result.data.structured_input.code_editor.line_plans)
$student = $plans | Where-Object { $_.line.content_without_indent -like 'class Student*' } | Select-Object -First 1
$course = $plans | Where-Object { $_.line.content_without_indent -like 'class Course*' } | Select-Object -First 1
$def = $plans | Where-Object { $_.line.content_without_indent -like 'def introduce*' } | Select-Object -First 1
$second = $plans | Where-Object { $_.line.content_without_indent -like 'def second*' } | Select-Object -First 1
$nested = $plans | Where-Object { $_.line.content_without_indent -like "print('Alice')*" } | Select-Object -First 1
$blank = $plans | Where-Object { $_.line.is_blank_line -eq $true } | Select-Object -First 1
$blankTargetIndent = $plans | Where-Object { $_.reset_strategy -eq 'python_block_starter_target_indent_from_semantic_baseline' -and $_.line.content_without_indent -like 'def second*' } | Select-Object -First 1
$topLevelRuntime = $plans | Where-Object { $_.reset_strategy -eq 'shift_tab_to_scope_boundary' -and $_.line.content_without_indent -like 'student = Student*' } | Select-Object -First 1

Assert ($student.line.target_indent_spaces -eq 0) 'top-level Student indent should be 0.'
Assert ($course.line.target_indent_spaces -eq 0) 'top-level Course indent should return to 0.'
Assert ($def.line.target_indent_spaces -eq 4) 'function body header indent should be 4.'
Assert ($second.line.target_indent_spaces -eq 4) 'second method after blank line should remain in class scope.'
Assert ($nested.line.target_indent_spaces -eq 12) 'nested block content should record indent 12.'
Assert ($blank.line.target_indent_spaces -eq 0) 'blank line target indent should normalize to 0.'
Assert ($null -ne $blankTargetIndent) 'method after blank line should type target class indent before Python block-starter text.'
Assert ([int]$blankTargetIndent.spaces_typed -eq 4) 'method after blank line should type one class indent level before def.'
Assert ($null -ne $topLevelRuntime) 'top-level runtime statement after blank line should explicitly dedent to global scope.'
Assert (($plans | Where-Object { $_.natural_auto_indent_used -eq $true }).Count -gt 0) 'natural auto-indent path should be present.'

$boundaryCode = @'
class Student:
    def introduce(self):
        print('Alice')
class Course:
    def show_title(self):
        print('Course: Python Class and Object')
'@
$boundaryResult = Invoke-Agent @(
    'visible-text-input', '--text', $boundaryCode,
    '--input-kind', 'code_editor_text',
    '--structured', 'true',
    '--indent-mode', 'spaces',
    '--indent-width', '4',
    '--verify-structure', 'true',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true'
)
$boundaryPlans = @($boundaryResult.data.structured_input.code_editor.line_plans)
$classNatural = $boundaryPlans | Where-Object { $_.reset_strategy -eq 'natural_python_block_starter_dedent' -and $_.line.content_without_indent -like 'class Course*' } | Select-Object -First 1
Assert ($null -ne $classNatural) 'Python class boundary should follow editor natural block-starter dedent.'

$runtimeBoundaryCode = @'
class Student:
    def introduce(self):
        print('Alice')
student = Student()
student.introduce()
'@
$runtimeBoundaryResult = Invoke-Agent @(
    'visible-text-input', '--text', $runtimeBoundaryCode,
    '--input-kind', 'code_editor_text',
    '--structured', 'true',
    '--indent-mode', 'spaces',
    '--indent-width', '4',
    '--verify-structure', 'true',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true'
)
Assert ($runtimeBoundaryResult.data.auto_indent_correction_applied -eq $true) 'runtime statement scope boundary should apply explicit correction.'
Assert ([int]$runtimeBoundaryResult.data.actual_indent_correction_keys -gt 0) 'Shift+Tab correction keys should be recorded for runtime statement scope boundary.'
$runtimeBoundaryPlans = @($runtimeBoundaryResult.data.structured_input.code_editor.line_plans)
$shiftTab = $runtimeBoundaryPlans | Where-Object { $_.reset_strategy -eq 'shift_tab_to_scope_boundary' -and [int]$_.actual_indent_correction_keys -gt 0 } | Select-Object -First 1
Assert ($null -ne $shiftTab) 'Shift+Tab correction path should be present for runtime statement scope boundary.'

@(
    '# Indentation Controller Selftest',
    '',
    '- result: PASS',
    '- auto_indent_drift_correction: PASS',
    '- top_level_indent_0: PASS',
    '- function_indent_4: PASS',
    '- nested_indent_8_or_more: PASS',
    '- blank_line_handling: PASS',
    '- shift_tab_correction_path: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS indentation_controller_selftest'
exit 0
