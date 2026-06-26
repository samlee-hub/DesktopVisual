param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_structured_text_input'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) { throw "winagent $($WinArgs -join ' ') exited $exit with output: $output" }
    return $output | ConvertFrom-Json
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$noLock = Invoke-Agent -WinArgs @('visible-text-input', '--text', 'hello', '--dry-run', 'true') -Allowed @(1)
Assert ($noLock.ok -eq $false) 'visible-text-input without target lock should fail.'
Assert ($noLock.error.code -eq 'FAIL_TEXT_INPUT_TARGET_NOT_LOCKED') 'missing lock must return FAIL_TEXT_INPUT_TARGET_NOT_LOCKED.'

$keyboard = Invoke-Agent -WinArgs @('visible-text-input', '--text', 'hello', '--input-kind', 'form_value', '--structured', 'true', '--target-title', 'dry-run-target', '--require-target-lock', 'true', '--dry-run', 'true', '--allow-dry-run-target', 'true')
Assert ($keyboard.ok -eq $true) 'visible-text-input dry-run policy should pass.'
Assert ($keyboard.data.input_method -eq 'real_keyboard_events') 'default input method must be real_keyboard_events.'
Assert ($keyboard.data.structured -eq $true) 'structured strategy must be enabled.'
Assert ($keyboard.data.resolved_input_kind -eq 'form_value') 'form_value kind should be preserved.'
Assert ($keyboard.data.structured_strategy -eq 'single_line_keyboard_policy') 'form_value should use single-line strategy.'
Assert ($keyboard.data.clipboard_used -eq $false) 'clipboard must be false by default.'
Assert ($keyboard.data.backend_file_write_used -eq $false) 'backend file write must be false.'
Assert ($keyboard.data.target_window_locked -eq $true) 'target lock evidence must be true.'

$code = @'
class Student:
    def introduce(self):
        print('Alice')

    def second(self):
        print('Second')

class Course:
    def show_title(self):
        print('Course: Python Class and Object')

student = Student()
course = Course()
course.show_title()
student.introduce()
'@
$structuredCode = Invoke-Agent -WinArgs @('visible-text-input', '--text', $code, '--input-kind', 'code_editor_text', '--structured', 'true', '--indent-mode', 'spaces', '--indent-width', '4', '--verify-structure', 'true', '--target-title', 'dry-run-target', '--require-target-lock', 'true', '--dry-run', 'true', '--allow-dry-run-target', 'true')
Assert ($structuredCode.ok -eq $true) 'structured code dry-run policy should pass.'
Assert ($structuredCode.data.structured_strategy -eq 'code_editor_typing_policy') 'code_editor_text must use CodeEditorTypingPolicy.'
Assert ($structuredCode.data.auto_indent_correction_applied -eq $true) 'code editor input should apply auto-indent correction.'
Assert ($structuredCode.data.code_structure_verified -eq $true) 'code structure must verify.'
Assert ($structuredCode.data.code_write_plan_used -eq $true) 'CodeWritePlan must be used.'
Assert ($structuredCode.data.language_scope_model_used -eq $true) 'LanguageScopeModel must be used.'
Assert ($structuredCode.data.editor_auto_indent_model_used -eq $true) 'EditorAutoIndentModel must be used.'
Assert ($structuredCode.data.cursor_buffer_state_verified -eq $true) 'CursorAndBufferStateGuard must verify cursor/buffer state.'
Assert ($structuredCode.data.old_buffer_cleared_or_safe_replace_verified -eq $true) 'Old buffer clean rewrite must be verified.'
Assert ($structuredCode.data.no_retry_contamination -eq $true) 'Retry contamination must be rejected.'
Assert ($structuredCode.data.receiver_binding_verified -eq $true) 'Receiver binding must verify at visible policy level.'
Assert ($structuredCode.data.duplicate_receiver_token_detected -eq $false) 'Duplicated receiver token must be reported false for valid code.'
Assert ($structuredCode.data.repair_replace_not_append -eq $true) 'Repair edit policy must be replace-not-append.'
Assert ($structuredCode.data.selfself_present -eq $false) 'Valid code must report selfself_present false.'
Assert ($structuredCode.data.clipboard_used -eq $false) 'structured code clipboard must be false.'
Assert ($structuredCode.data.backend_file_write_used -eq $false) 'structured code backend write must be false.'

$clipboard = Invoke-Agent -WinArgs @('visible-text-input', '--text', 'hello', '--target-title', 'dry-run-target', '--require-target-lock', 'true', '--dry-run', 'true', '--allow-dry-run-target', 'true', '--input-method', 'clipboard_paste') -Allowed @(1)
Assert ($clipboard.ok -eq $false) 'unapproved clipboard paste should fail.'
Assert ($clipboard.error.code -eq 'FAIL_CLIPBOARD_INPUT_NOT_ALLOWED') 'clipboard failure code mismatch.'

$backend = Invoke-Agent -WinArgs @('visible-text-input', '--text', 'hello', '--target-title', 'dry-run-target', '--require-target-lock', 'true', '--dry-run', 'true', '--allow-dry-run-target', 'true', '--backend-file-write-used', 'true') -Allowed @(1)
Assert ($backend.ok -eq $false) 'backend file write should fail.'
Assert ($backend.error.code -eq 'FAIL_BACKEND_TEXT_WRITE_FORBIDDEN') 'backend write failure code mismatch.'

$report = Join-Path $OutDir 'visible_text_input_report.md'
@(
    '# Visible Text Input Policy Selftest',
    '',
    '- result: PASS',
    '- default input method: real_keyboard_events',
    '- structured strategy layer: PASS',
    '- code_editor_text CodeEditorTypingPolicy: PASS',
    '- auto_indent_correction_applied: true',
    '- code_structure_verified: true',
    '- code_write_plan_used: true',
    '- language_scope_model_used: true',
    '- editor_auto_indent_model_used: true',
    '- cursor_buffer_state_verified: true',
    '- old_buffer_cleared_or_safe_replace_verified: true',
    '- no_retry_contamination: true',
    '- receiver_binding_verified: true',
    '- duplicate_receiver_token_detected: false',
    '- repair_replace_not_append: true',
    '- selfself_present: false',
    '- clipboard default forbidden: PASS',
    '- backend write forbidden: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS visible_text_input_policy_selftest"
exit 0
