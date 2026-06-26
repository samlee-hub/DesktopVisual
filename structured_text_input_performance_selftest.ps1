param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'structured_text_input_performance_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

$code = @'
class Person:
    def __init__(self, name, age):
        self.name = name
        self.age = age

    def introduce(self):
        print(f"My name is {self.name}, and I am {self.age} years old.")

print("Course: Python Class and Object")
student = Person("Alice", 18)
student.introduce()
'@

$output = & $WinAgent visible-text-input --text $code --input-kind code --input-method real_keyboard_events --target-title dry-run-target --require-target-lock true --dry-run true --allow-dry-run-target true --typing-profile fast-real-keyboard --char-delay-ms 0 --line-delay-ms 0 --batch-key-events true
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "structured text input performance command exited $exit`: $text" }
$json = $text | ConvertFrom-Json

Assert ($json.ok -eq $true) 'fast real keyboard dry-run must pass.'
Assert ($json.data.typing_profile -eq 'fast-real-keyboard') 'Typing profile must be fast-real-keyboard.'
Assert ($json.data.input_method -eq 'real_keyboard_events') 'Input method must remain real_keyboard_events.'
Assert ($json.data.char_delay_ms -eq 0) 'char-delay must be zero.'
Assert ($json.data.line_delay_ms -eq 0) 'line-delay must be zero.'
Assert ($json.data.batch_key_events -eq $true) 'Batch key events must be enabled.'
Assert ($json.data.clipboard_used -eq $false) 'Clipboard must not be used.'
Assert ($json.data.backend_file_write_used -eq $false) 'Backend file write must not be used.'
Assert ($json.data.first_pass_multiline_correct -eq $true) 'Multiline code must remain structurally correct.'
Assert ($json.data.code_collapsed_to_single_line -eq $false) 'Code must not collapse to one line.'
Assert ($json.data.expensive_observe_after_each_line -eq $false) 'Fast profile must not observe after each line.'

@(
    '# Structured Text Input Performance Report',
    '',
    '- result: PASS',
    '- structured_text_input_fast_path_enabled: true',
    "- typing_profile: $($json.data.typing_profile)",
    "- input_method: $($json.data.input_method)",
    "- char_delay_ms: $($json.data.char_delay_ms)",
    "- line_delay_ms: $($json.data.line_delay_ms)",
    "- batch_key_events: $($json.data.batch_key_events)",
    "- keyboard_event_count: $($json.data.keyboard_event_count)",
    "- keyboard_send_batch_count: $($json.data.keyboard_send_batch_count)",
    '- clipboard_used: false',
    '- backend_file_write_used: false'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS structured_text_input_performance_selftest'
exit 0
