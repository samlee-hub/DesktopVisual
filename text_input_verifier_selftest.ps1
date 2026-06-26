param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_structured_text_input'
$Report = Join-Path $OutDir 'text_input_verifier_report.md'
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

$good = @'
class Student:
    def introduce(self):
        print('Alice')

class Course:
    def show_title(self):
        print('Course: Python Class and Object')

student = Student()
course = Course()
course.show_title()
student.introduce()
'@
$bad = @'
class Student:
    def introduce(self):
        print('Alice')

    class Course:
        def show_title(self):
            print('Course: Python Class and Object')

    student = Student()
    course = Course()
    course.show_title()
student.introduce()
'@
$badTopLevelMethod = @'
class Student:
    def __init__(self, name):
        self.name = name

def introduce(self):
    print(self.name)

student = Student('Alice')
student.introduce()
'@
$badMissingSelf = @'
class Student:
    def introduce():
        print('Alice')

student = Student()
student.introduce()
'@
$badCurrentRegression = @'
class Student:
    def __init__(self, name, age):
        self.name = name
        self.age = age

def introduce():
    print('My name is ' + self.name + ', and I am ' + str(self.age) + ' years old.')

class Course:
    def __init__(self, title):
        self.title = title

def show_title():
    print('Course: ' + self.title)

student = Student('Alice', 18)
course = Course('Python Class and Object')
course.show_title()
student.introduce()
'@
$badDuplicatedReceiver = @'
class Student:
    def __init__(selfself, name, age):
        self.name = name
        self.age = age

    def introduce(selfself):
        print('My name is ' + self.name + ', and I am ' + str(self.age) + ' years old.')

class Course:
    def __init__(self, title):
        self.title = title

    def show_title(selfself):
        print('Course: ' + self.title)

student = Student('Alice', 18)
course = Course('Python Class and Object')
course.show_title()
student.introduce()
'@
$base = @(
    'visible-text-input',
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

$goodResult = Invoke-Agent (@('visible-text-input', '--text', $good) + $base[1..($base.Length - 1)])
Assert ($goodResult.ok -eq $true) 'valid Python code should verify.'
Assert ($goodResult.data.preinput_code_structure_verified -eq $true) 'valid Python code should pass pre-input structure verification.'
Assert ($goodResult.data.structured_input.code_editor.preinput_code_structure_verified -eq $true) 'code editor pre-input structure verification should pass.'
Assert ($goodResult.data.structured_input.code_editor.verification.class_course_not_nested_in_student -eq $true) 'class Course should be top-level.'
Assert ($goodResult.data.structured_input.code_editor.verification.top_level_execution_verified -eq $true) 'top-level execution should verify.'
Assert ($goodResult.data.structured_input.code_editor.verification.receiver_binding_verified -eq $true) 'receiver binding should verify for valid Python class methods.'
Assert ($goodResult.data.structured_input.code_editor.verification.duplicate_receiver_token_detected -eq $false) 'valid Python should not contain duplicated receiver tokens.'
Assert ($goodResult.data.structured_input.code_editor.verification.selfself_present -eq $false) 'valid Python should not contain selfself.'
Assert ($goodResult.data.structured_input.code_editor.repair_edit_policy.repair_replace_not_append -eq $true) 'repair policy must require replace-not-append.'
$classes = @($goodResult.data.structured_input.code_editor.code_write_plan_details.classes)
$studentClass = @($classes | Where-Object { $_.name -eq 'Student' })[0]
$courseClass = @($classes | Where-Object { $_.name -eq 'Course' })[0]
Assert ($null -ne $studentClass) 'CodeWritePlan should explicitly model Student class.'
Assert ($null -ne $courseClass) 'CodeWritePlan should explicitly model Course class.'
Assert (@(@($studentClass.methods) | Where-Object { $_.name -eq 'introduce' -and $_.has_receiver -eq $true }).Count -eq 1) 'CodeWritePlan should model Student.introduce(self).'
Assert (@(@($courseClass.methods) | Where-Object { $_.name -eq 'show_title' -and $_.has_receiver -eq $true }).Count -eq 1) 'CodeWritePlan should model Course.show_title(self).'

$badResult = Invoke-Agent ((@('visible-text-input', '--text', $bad) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($badResult.ok -eq $false) 'nested Course should fail verification.'
Assert ($badResult.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'nested Course should be blocked before visible typing.'
Assert ($badResult.data.preinput_code_structure_verified -eq $false) 'nested Course should fail pre-input structure verification.'
Assert ($badResult.data.structured_input.code_editor.verification.class_course_not_nested_in_student -eq $false) 'nested Course must be rejected.'

$badTopLevelMethodResult = Invoke-Agent ((@('visible-text-input', '--text', $badTopLevelMethod) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($badTopLevelMethodResult.ok -eq $false) 'Python method emitted at top-level should fail verification.'
Assert ($badTopLevelMethodResult.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'top-level self method should be blocked before visible typing.'
Assert ($badTopLevelMethodResult.data.preinput_code_structure_verified -eq $false) 'top-level self method should fail pre-input structure verification.'

$badMissingSelfResult = Invoke-Agent ((@('visible-text-input', '--text', $badMissingSelf) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($badMissingSelfResult.ok -eq $false) 'Python class method missing self should fail verification.'
Assert ($badMissingSelfResult.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'missing self method should be blocked before visible typing.'
Assert ($badMissingSelfResult.data.preinput_code_structure_verified -eq $false) 'missing self method should fail pre-input structure verification.'

$badCurrentRegressionResult = Invoke-Agent ((@('visible-text-input', '--text', $badCurrentRegression) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($badCurrentRegressionResult.ok -eq $false) 'current regression shape should fail before visible typing.'
Assert ($badCurrentRegressionResult.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'current regression shape should be blocked before visible typing.'
Assert ($badCurrentRegressionResult.data.preinput_code_structure_verified -eq $false) 'current regression shape should fail pre-input structure verification.'

$badDuplicatedReceiverResult = Invoke-Agent ((@('visible-text-input', '--text', $badDuplicatedReceiver) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($badDuplicatedReceiverResult.ok -eq $false) 'duplicated receiver token should fail before visible typing.'
Assert ($badDuplicatedReceiverResult.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'duplicated receiver token should be blocked before visible typing.'
Assert ($badDuplicatedReceiverResult.data.preinput_code_structure_verified -eq $false) 'duplicated receiver token should fail pre-input structure verification.'
Assert ($badDuplicatedReceiverResult.data.structured_input.code_editor.verification.duplicate_receiver_token_detected -eq $true) 'selfself must be detected as duplicate receiver token.'
Assert ($badDuplicatedReceiverResult.data.structured_input.code_editor.verification.receiver_binding_verified -eq $false) 'selfself must not satisfy receiver binding.'
Assert ($badDuplicatedReceiverResult.data.structured_input.code_editor.verification.selfself_present -eq $true) 'selfself_present should be true.'

$runSucceededBad = Invoke-Agent ((@('visible-text-input', '--text', $bad, '--verifier-run-succeeded', 'true') + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($runSucceededBad.ok -eq $false) 'run success must not override structure mismatch.'
Assert ($runSucceededBad.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'run success must not bypass pre-input structure validation.'

$clipboard = Invoke-Agent (@('visible-text-input', '--text', $good, '--input-method', 'clipboard_paste') + $base[1..($base.Length - 1)]) -Allowed @(1)
Assert ($clipboard.ok -eq $false) 'clipboard input cannot pass verifier path.'
Assert ($clipboard.error.code -eq 'FAIL_CLIPBOARD_INPUT_NOT_ALLOWED') 'clipboard default failure code mismatch.'

$cppGood = @'
#include <iostream>

int helper() {
    return 1;
}

int main() {
    std::cout << helper();
    return 0;
}
'@
$cppBad = @'
#include <iostream>

int main() {
    int helper() {
        return 1;
    }
    return helper();
}
'@
$javaBad = @'
public class Main {
    public static void main(String[] args) {
        static int helper() {
            return 1;
        }
        System.out.println(helper());
    }
}
'@
$kotlinBad = @'
fun main() {
    fun helper(): Int {
        return 1
    }
    println(helper())
}
'@

$cppGoodResult = Invoke-Agent (@('visible-text-input', '--text', $cppGood) + $base[1..($base.Length - 1)])
Assert ($cppGoodResult.ok -eq $true) 'C++ helper outside main should verify.'
Assert ($cppGoodResult.data.structured_input.code_editor.verification.function_not_nested_in_main -eq $true) 'C++ helper/main scope should verify.'

$cppBadResult = Invoke-Agent ((@('visible-text-input', '--text', $cppBad) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($cppBadResult.ok -eq $false) 'C++ helper inside main should fail verification.'
Assert ($cppBadResult.error.code -eq 'BLOCKED_PREINPUT_CODE_STRUCTURE_INVALID') 'C++ helper-inside-main should be blocked before visible typing.'

$javaBadResult = Invoke-Agent ((@('visible-text-input', '--text', $javaBad) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($javaBadResult.ok -eq $false) 'Java method inside main should fail verification.'

$kotlinBadResult = Invoke-Agent ((@('visible-text-input', '--text', $kotlinBad) + $base[1..($base.Length - 1)])) -Allowed @(1)
Assert ($kotlinBadResult.ok -eq $false) 'Kotlin nested function inside main should fail verification.'

@(
    '# Text Input Verifier Selftest',
    '',
    '- result: PASS',
    '- class_Course_not_nested: PASS',
    '- top_level_execution_not_nested: PASS',
    '- structure_mismatch_rejected: PASS',
    '- python_method_not_top_level: PASS',
    '- python_class_method_requires_self: PASS',
    '- python_duplicate_receiver_token_rejected: PASS',
    '- python_receiver_binding_exact_token: PASS',
    '- repair_replace_not_append_policy: PASS',
    '- run_success_does_not_override_structure_error: PASS',
    '- clipboard_cannot_impersonate_real_keyboard: PASS',
    '- cpp_function_not_nested_in_main: PASS',
    '- java_method_not_nested_in_main: PASS',
    '- kotlin_function_not_nested_in_main: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS text_input_verifier_selftest'
exit 0
