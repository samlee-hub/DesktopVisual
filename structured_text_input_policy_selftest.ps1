param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_structured_text_input'
$Report = Join-Path $OutDir 'structured_text_input_policy_report.md'
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

$base = @('--target-title', 'dry-run-target', '--require-target-lock', 'true', '--dry-run', 'true', '--allow-dry-run-target', 'true', '--structured', 'true')

$single = Invoke-Agent (@('visible-text-input', '--text', 'hello search', '--input-kind', 'single_line_input') + $base)
Assert ($single.ok -eq $true) 'single_line_input should pass.'
Assert ($single.data.resolved_input_kind -eq 'single_line_input') 'single_line_input kind mismatch.'
Assert ([int]$single.data.enter_key_event_count -eq 0) 'single_line_input must not add newline.'

$plainText = "line one`nline two"
$multi = Invoke-Agent (@('visible-text-input', '--text', $plainText, '--input-kind', 'multi_line_plain_text') + $base)
Assert ($multi.ok -eq $true) 'multi_line_plain_text should pass.'
Assert ($multi.data.resolved_input_kind -eq 'multi_line_plain_text') 'multi_line_plain_text kind mismatch.'
Assert ([int]$multi.data.enter_key_event_count -eq 1) 'multi_line_plain_text should preserve newline.'
Assert ($multi.data.auto_indent_correction_applied -eq $false) 'plain multiline text must not use code indent control.'

$messageText = "class Note:`n    body as message"
$message = Invoke-Agent (@('visible-text-input', '--text', $messageText, '--input-kind', 'message_text') + $base)
Assert ($message.ok -eq $true) 'message_text should pass.'
Assert ($message.data.resolved_input_kind -eq 'message_text') 'message_text kind mismatch.'
Assert ($message.data.structured_strategy -eq 'message_text_keyboard_policy') 'message_text must not route to code editor policy.'
Assert ($message.data.auto_indent_correction_applied -eq $false) 'message_text must not do code indentation control.'

$code = @'
class Student:
    def introduce(self):
        print('hello')

class Course:
    def show_title(self):
        print('Course: Python Class and Object')

student = Student()
course = Course()
course.show_title()
student.introduce()
'@
$codeResult = Invoke-Agent (@('visible-text-input', '--text', $code, '--input-kind', 'code_editor_text', '--indent-mode', 'spaces', '--indent-width', '4', '--verify-structure', 'true') + $base)
Assert ($codeResult.ok -eq $true) 'code_editor_text should pass.'
Assert ($codeResult.data.structured_strategy -eq 'code_editor_typing_policy') 'code_editor_text must route to CodeEditorTypingPolicy.'
Assert ($codeResult.data.code_structure_verified -eq $true) 'code structure should verify.'
Assert ($codeResult.data.code_write_plan_used -eq $true) 'code_editor_text must use CodeWritePlan.'
Assert ($codeResult.data.language_scope_model_used -eq $true) 'code_editor_text must use LanguageScopeModel.'
Assert ($codeResult.data.editor_auto_indent_model_used -eq $true) 'code_editor_text must use EditorAutoIndentModel.'
Assert ($codeResult.data.cursor_buffer_state_verified -eq $true) 'code_editor_text must verify cursor/buffer state.'
Assert ($codeResult.data.old_buffer_cleared_or_safe_replace_verified -eq $true) 'code_editor_text must verify clean rewrite state.'
Assert ($codeResult.data.no_retry_contamination -eq $true) 'code_editor_text must reject retry contamination.'
Assert ($codeResult.data.receiver_binding_verified -eq $true) 'code_editor_text must verify exact receiver binding.'
Assert ($codeResult.data.duplicate_receiver_token_detected -eq $false) 'code_editor_text must reject duplicated receiver tokens.'
Assert ($codeResult.data.repair_replace_not_append -eq $true) 'repair edits must be replace-not-append.'
Assert ($codeResult.data.selfself_present -eq $false) 'code_editor_text must not contain selfself.'
Assert ($codeResult.data.clipboard_used -eq $false) 'clipboard must be false.'

$inferred = Invoke-Agent (@('visible-text-input', '--text', $code, '--indent-mode', 'spaces', '--indent-width', '4', '--verify-structure', 'true') + $base)
Assert ($inferred.ok -eq $true) 'unspecified input-kind multiline code should pass.'
Assert ($inferred.data.resolved_input_kind -eq 'code_editor_text') 'unspecified multiline code must infer code_editor_text.'

$clipboard = Invoke-Agent (@('visible-text-input', '--text', 'hello', '--input-method', 'clipboard_paste') + $base) -Allowed @(1)
Assert ($clipboard.ok -eq $false) 'default clipboard input must fail.'
Assert ($clipboard.error.code -eq 'FAIL_CLIPBOARD_INPUT_NOT_ALLOWED') 'clipboard failure code mismatch.'

@(
    '# Structured Text Input Policy Selftest',
    '',
    '- result: PASS',
    '- single_line_input_no_newline: PASS',
    '- multi_line_plain_text_newline: PASS',
    '- message_text_no_code_indent_control: PASS',
    '- code_editor_text_routes_to_CodeEditorTypingPolicy: PASS',
    '- code_write_plan_used: PASS',
    '- language_scope_model_used: PASS',
    '- editor_auto_indent_model_used: PASS',
    '- cursor_buffer_state_verified: PASS',
    '- old_buffer_cleared_or_safe_replace_verified: PASS',
    '- no_retry_contamination: PASS',
    '- receiver_binding_verified: PASS',
    '- duplicate_receiver_token_detected: false',
    '- repair_replace_not_append: true',
    '- selfself_present: false',
    '- auto_infer_multiline_code: PASS',
    '- default_clipboard_forbidden: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS structured_text_input_policy_selftest'
exit 0
