param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
$Report = Join-Path $OutDir 'code_editor_keyboard_input_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }
function Assert($Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }

function Invoke-Agent {
    param([string[]]$WinArgs, [int[]]$Allowed = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($Allowed -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { return $text | ConvertFrom-Json } catch { Fail "Invalid JSON: $text" }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

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

    def show(self):
        print('Course: ' + self.title)


student = Student('Alice', 18)
course = Course('Python Class and Object')
course.show()
student.introduce()
'@

$result = Invoke-Agent -WinArgs @(
    'visible-text-input',
    '--text', $code,
    '--input-kind', 'code_editor',
    '--input-method', 'code_editor_keyboard',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true'
)

Assert ($result.ok -eq $true) 'code_editor_keyboard dry-run should pass.'
Assert ($result.data.input_method -eq 'code_editor_keyboard') 'input method should be code_editor_keyboard.'
Assert ([int]$result.data.typed_line_count -gt 10) 'Code sample must be represented as multiline input.'
Assert ([int]$result.data.enter_key_event_count -gt 10) 'Code sample newlines must be Enter key events.'
Assert ([int]$result.data.tab_key_event_count -eq 0) 'Python sample uses spaces, not literal tab characters.'
Assert ($result.data.first_pass_multiline_correct -eq $true) 'Code first-pass multiline evidence must be true.'
Assert ($result.data.code_collapsed_to_single_line -eq $false) 'Code must not collapse to one line.'
Assert ($result.data.selfself_autocomplete_artifact -eq $false) 'Code must not contain selfself artifact.'
Assert ($result.data.clipboard_used -eq $false) 'Clipboard must not be used.'
Assert ($result.data.backend_file_write_used -eq $false) 'Backend file write must not be used.'

$bad = Invoke-Agent -WinArgs @(
    'visible-text-input',
    '--text', 'selfself',
    '--input-kind', 'code_editor',
    '--input-method', 'code_editor_keyboard',
    '--target-title', 'dry-run-target',
    '--require-target-lock', 'true',
    '--dry-run', 'true',
    '--allow-dry-run-target', 'true'
) -Allowed @(1)
Assert ($bad.ok -eq $false) 'selfself artifact should fail.'
Assert ($bad.error.code -eq 'FAIL_SELFSELF_AUTOCOMPLETE_ARTIFACT') 'selfself failure code mismatch.'

@(
    '# Code Editor Keyboard Input Selftest',
    '',
    '- result: PASS',
    '- input_method: code_editor_keyboard',
    '- first_pass_multiline_correct: true',
    '- code_collapsed_to_single_line: false',
    '- selfself_autocomplete_artifact: false',
    '- clipboard_used: false',
    '- backend_file_write_used: false'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS code_editor_keyboard_input_selftest'
exit 0
