param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_structured_text_input'
$Report = Join-Path $OutDir 'code_editor_typing_policy_report.md'
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
function Test-Code([string]$Name, [string]$Code, [bool]$ExpectStructure = $true) {
    $args = @(
        'visible-text-input', '--text', $Code,
        '--input-kind', 'code_editor_text',
        '--structured', 'true',
        '--indent-mode', 'spaces',
        '--indent-width', '4',
        '--verify-structure', 'true',
        '--typing-profile', 'fast-real-keyboard',
        '--target-title', 'dry-run-target',
        '--require-target-lock', 'true',
        '--dry-run', 'true',
        '--allow-dry-run-target', 'true'
    )
    $result = Invoke-Agent $args
    Assert ($result.ok -eq $true) "$Name should pass."
    Assert ($result.data.structured_strategy -eq 'code_editor_typing_policy') "$Name did not use CodeEditorTypingPolicy."
    Assert ($result.data.resolved_input_kind -eq 'code_editor_text') "$Name kind mismatch."
    Assert ($result.data.clipboard_used -eq $false) "$Name used clipboard."
    Assert ($result.data.backend_file_write_used -eq $false) "$Name used backend file write."
    Assert ($result.data.structured_input.code_editor.line_aware -eq $true) "$Name must be line-aware."
    Assert ($result.data.structured_input.code_editor.indent_aware -eq $true) "$Name must be indent-aware."
    Assert ($result.data.structured_input.code_editor.auto_indent_aware -eq $true) "$Name must be auto-indent-aware."
    Assert ($result.data.structured_input.code_editor.editor_auto_indent_model -eq $true) "$Name must build an editor auto-indent model."
    Assert ($result.data.structured_input.code_editor.language_scope_model -eq $true) "$Name must build a language scope model."
    Assert ($result.data.structured_input.code_editor.code_write_plan -eq $true) "$Name must build a code write plan."
    Assert ($result.data.structured_input.code_editor.code_write_plan_used -eq $true) "$Name must report CodeWritePlan used."
    Assert ($result.data.structured_input.code_editor.language_scope_model_used -eq $true) "$Name must report LanguageScopeModel used."
    Assert ($result.data.structured_input.code_editor.editor_auto_indent_model_used -eq $true) "$Name must report EditorAutoIndentModel used."
    Assert ($result.data.structured_input.code_editor.cursor_buffer_state_verified -eq $true) "$Name must verify cursor/buffer state."
    Assert ($result.data.structured_input.code_editor.old_buffer_cleared_or_safe_replace_verified -eq $true) "$Name must verify clean rewrite state."
    Assert ($result.data.structured_input.code_editor.no_retry_contamination -eq $true) "$Name must reject retry contamination."
    Assert ($result.data.structured_input.code_editor.incremental_code_input_verifier_used -eq $true) "$Name must use incremental code verifier."
    Assert ($result.data.structured_input.code_editor.real_keyboard_code_input_policy -eq $true) "$Name must use RealKeyboardCodeInputPolicy."
    Assert ($result.data.structured_input.code_editor.content_insertion_order -eq 'forward') "$Name must use normal forward programmer typing."
    Assert ($result.data.structured_input.code_editor.natural_auto_indent_followed -eq $true) "$Name must follow editor natural auto-indent."
    if ($result.data.structured_input.code_editor.language -eq 'python') {
        Assert ($result.data.structured_input.code_editor.receiver_binding_verified -eq $true) "$Name must verify exact Python receiver binding."
        Assert ($result.data.structured_input.code_editor.duplicate_receiver_token_detected -eq $false) "$Name must reject duplicated receiver tokens."
        Assert ($result.data.structured_input.code_editor.repair_replace_not_append -eq $true) "$Name must require replace-not-append repair semantics."
        Assert ($result.data.structured_input.code_editor.selfself_present -eq $false) "$Name must not contain selfself."
    }
    if ($ExpectStructure) {
        Assert ($result.data.code_structure_verified -eq $true) "$Name structure was not verified."
    }
    return $result
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

$python = @'
class Student:
    def __init__(self, name):
        self.name = name

    def introduce(self):
        print(self.name)

class Course:
    def show_title(self):
        print('Course: Python Class and Object')

student = Student('Alice')
course = Course()
course.show_title()
student.introduce()
'@
$java = @'
public class Main {
    public static void main(String[] args) {
        System.out.println(1);
    }
}
'@
$kotlin = @'
class Course(val title: String) {
    fun showTitle() {
        println(title)
    }
}
'@
$cpp = @'
#include <iostream>

class Course {
public:
    void show() {
        std::cout << 1;
    }
};

int main() {
    Course course;
    course.show();
    return 0;
}
'@
$json = @'
{
    course: {
        title: PythonClassAndObject
    }
}
'@
$xml = @'
<course>
    <title>Python Class and Object</title>
</course>
'@
$markdown = @'
```python
class Student:
    def introduce(self):
        print('inside markdown')
```
'@

$py = Test-Code 'Python class/function indentation' $python
Assert ([int]$py.data.target_indent_spaces -ge 8) 'Python nested block should record indent 8.'
Assert ([int]$py.data.actual_indent_correction_keys -lt 20) 'Python natural auto-indent should not Shift+Tab every line.'
$pyPlans = @($py.data.structured_input.code_editor.line_plans)
$naturalDef = $pyPlans | Where-Object { $_.line.content_without_indent -like 'def __init__*' } | Select-Object -First 1
Assert ($naturalDef.natural_auto_indent_used -eq $true) 'def __init__ should follow class auto-indent.'
$introducePlan = $pyPlans | Where-Object { $_.line.content_without_indent -like 'def introduce*' } | Select-Object -First 1
Assert ($introducePlan.reset_strategy -eq 'python_block_starter_target_indent_from_semantic_baseline') 'method after a blank line should type target class indent before Python block-starter text.'
Assert ([int]$introducePlan.spaces_typed -eq 4) 'method after blank line should type one class indent level.'
$coursePlan = $pyPlans | Where-Object { $_.line.content_without_indent -like 'class Course*' } | Select-Object -First 1
Assert ($coursePlan.reset_strategy -eq 'natural_python_block_starter_dedent') 'top-level class after a blank line should follow Python block-starter natural dedent.'
$studentPlan = $pyPlans | Where-Object { $_.line.content_without_indent -like 'student = Student*' } | Select-Object -First 1
Assert ($studentPlan.reset_strategy -eq 'shift_tab_to_scope_boundary') 'top-level runtime statement after a method block should explicitly dedent to global scope.'
Test-Code 'Java class/method indentation' $java | Out-Null
Test-Code 'Kotlin class/fun indentation' $kotlin | Out-Null
$cppResult = Test-Code 'C++ class/main indentation' $cpp
Assert ($cppResult.data.structured_input.code_editor.language -eq 'cpp') 'C++ language scope model should classify cpp.'
Assert ($cppResult.data.structured_input.code_editor.verification.function_not_nested_in_main -eq $true) 'C++ functions must not be nested in main.'
Test-Code 'JSON indentation' $json | Out-Null
Test-Code 'XML indentation' $xml | Out-Null
Test-Code 'Markdown code block' $markdown | Out-Null

@(
    '# Code Editor Typing Policy Selftest',
    '',
    '- result: PASS',
    '- parse_code_lines: PASS',
    '- line_aware: PASS',
    '- indent_aware: PASS',
    '- auto_indent_aware: PASS',
    '- CodeWritePlan used: PASS',
    '- LanguageScopeModel used: PASS',
    '- EditorAutoIndentModel used: PASS',
    '- CursorAndBufferStateGuard used: PASS',
    '- IncrementalCodeInputVerifier used: PASS',
    '- RealKeyboardCodeInputPolicy used: PASS',
    '- receiver_binding_verified: PASS',
    '- duplicate_receiver_token_detected: false',
    '- repair_replace_not_append: true',
    '- selfself_present: false',
    '- Python: PASS',
    '- Java: PASS',
    '- Kotlin: PASS',
    '- C++: PASS',
    '- JSON: PASS',
    '- XML: PASS',
    '- Markdown code block: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS code_editor_typing_policy_selftest'
exit 0
