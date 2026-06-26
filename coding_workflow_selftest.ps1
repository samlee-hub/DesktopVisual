param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts\coding_workflow'
$PermissionArtifacts = Join-Path $Root 'artifacts\permission'
$SessionPath = Join-Path $PermissionArtifacts 'full_access_session.json'
$Report = Join-Path $Artifacts 'coding_workflow_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-AgentJson {
    param(
        [string[]]$CmdArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:Checks += [pscustomobject]@{ Name = $Name; Status = $(if ($Ok) { 'PASS' } else { 'FAIL' }); Detail = $Detail }
    if (-not $Ok) { Fail "$Name failed: $Detail" }
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
New-Item -ItemType Directory -Force -Path $PermissionArtifacts | Out-Null
$script:Checks = @()

$baseHtml = Join-Path $Artifacts 'oj_sample_pass.html'
$compileHtml = Join-Path $Artifacts 'oj_compile_error.html'
$wrongHtml = Join-Path $Artifacts 'oj_wrong_answer.html'
$examHtml = Join-Path $Artifacts 'oj_assessment_allowed.html'
$captchaHtml = Join-Path $Artifacts 'oj_captcha_stop.html'

Write-Utf8 $baseHtml @'
<html data-problem-title="Two Sum">
<head><title>DesktopVisual OJ</title></head>
<body>
  <h1>Two Sum</h1>
  <section id="problem_statement">Given an array of integers nums and an integer target, return indices of the two numbers such that they add up to target.</section>
  <section id="examples">Example: nums = [2,7,11,15], target = 9, output [0,1].</section>
  <section id="constraints">2 <= nums.length <= 10000.</section>
  <select id="language" data-label="Language"><option value="cpp">C++</option><option value="python">Python</option></select>
  <textarea id="code" data-control-type="code_editor" data-label="Code Editor"></textarea>
  <button id="run" data-action="run">Run Code</button>
  <button id="submit">Submit</button>
  <div id="result" data-result="sample_pass">Sample Pass</div>
</body>
</html>
'@

Write-Utf8 $compileHtml ((Get-Content -LiteralPath $baseHtml -Raw) -replace 'data-result="sample_pass">Sample Pass', 'data-result="compile_error">Compile Error')
Write-Utf8 $wrongHtml ((Get-Content -LiteralPath $baseHtml -Raw) -replace 'data-result="sample_pass">Sample Pass', 'data-result="wrong_answer">Wrong Answer')
Write-Utf8 $examHtml @'
<html><body>
  <h1>Hiring Test</h1>
  <section id="problem_statement">Online assessment exam content.</section>
  <textarea id="code" data-control-type="code_editor"></textarea>
  <button id="run">Run Code</button>
</body></html>
'@
Write-Utf8 $captchaHtml @'
<html><body>
  <h1>Practice</h1>
  <section id="problem_statement">Solve after captcha.</section>
  <div>captcha verification required</div>
  <textarea id="code" data-control-type="code_editor"></textarea>
  <button id="run">Run Code</button>
</body></html>
'@

$read = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $baseHtml, '--user-goal', 'practice two sum', '--action', 'read_problem', '--language', 'cpp')
Add-Check 'recognize problem area' ($read.json.ok -and $read.json.data.coding_workflow_context.problem_title -eq 'Two Sum' -and $read.json.data.coding_workflow_context.problem_statement_summary -match 'array of integers') $read.text
Add-Check 'recognize code editor' ($read.json.data.coding_workflow_context.editor_detected -eq $true -and $read.json.data.coding_workflow_context.run_button_detected -eq $true) $read.text

$input = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $baseHtml, '--user-goal', 'enter solution', '--action', 'input_code', '--language', 'cpp', '--code', 'int main(){return 0;}')
Add-Check 'input code action' ($input.json.ok -and $input.json.data.coding_workflow_record.code_summary -match 'code_length=') $input.text

$run = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $baseHtml, '--user-goal', 'run sample', '--action', 'run_code', '--language', 'cpp')
Add-Check 'run code action' ($run.json.ok -and $run.json.data.coding_workflow_context.result_state -eq 'SAMPLE_PASS') $run.text

$compile = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $compileHtml, '--user-goal', 'read compile error', '--action', 'read_result')
Add-Check 'read compile error' ($compile.json.ok -and $compile.json.data.coding_workflow_context.result_state -eq 'COMPILE_ERROR') $compile.text

$wrong = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $wrongHtml, '--user-goal', 'read wrong answer', '--action', 'read_result')
Add-Check 'read wrong answer' ($wrong.json.ok -and $wrong.json.data.coding_workflow_context.result_state -eq 'WRONG_ANSWER') $wrong.text

$pass = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $baseHtml, '--user-goal', 'read passed result', '--action', 'read_result')
Add-Check 'read sample pass' ($pass.json.ok -and $pass.json.data.coding_workflow_context.result_state -eq 'SAMPLE_PASS') $pass.text

$defaultSubmit = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $baseHtml, '--user-goal', 'try submit', '--action', 'submit_if_explicitly_allowed') -AllowedExitCodes @(1)
Add-Check 'default no submit' ($defaultSubmit.json.ok -eq $false -and $defaultSubmit.json.error.code -eq 'USER_TAKEOVER_REQUIRED' -and $defaultSubmit.json.data.coding_workflow_record.submit_clicked -eq $false) $defaultSubmit.text

$allowedSubmit = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $baseHtml, '--user-goal', 'submit solution', '--action', 'submit_if_explicitly_allowed', '--allow-submit')
Add-Check 'explicit submit allowed' ($allowedSubmit.json.ok -and $allowedSubmit.json.data.coding_workflow_record.submit_clicked -eq $true) $allowedSubmit.text

$exam = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $examHtml, '--user-goal', 'solve assessment', '--action', 'read_problem')
Add-Check 'assessment keywords allowed with explicit user goal' ($exam.json.ok -eq $true -and $exam.json.data.coding_workflow_context.problem_title -eq 'Hiring Test') $exam.text

$captcha = Invoke-AgentJson -CmdArgs @('coding-eval', '--html', $captchaHtml, '--user-goal', 'solve practice', '--action', 'read_problem') -AllowedExitCodes @(1)
Add-Check 'captcha stop' ($captcha.json.ok -eq $false -and $captcha.json.error.code -eq 'CAPTCHA_DETECTED') $captcha.text

$proc = $null
try {
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-AgentJson -CmdArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $sessionId = 'coding-selftest-session'
    $session = @{
        session_id = $sessionId
        permission_mode = 'FULL_ACCESS'
        scope = 'session-only'
        ttl_seconds = 900
        created_at_unix_ms = $now
        expires_at_unix_ms = ($now + 900000)
    }
    $session | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8

    $taskPath = Join-Path $Artifacts 'coding_task.task.json'
    $taskReport = Join-Path $Artifacts 'coding_task_report.md'
    $task = @{
        version = 1
        name = 'coding_task_selftest'
        permission_mode = 'FULL_ACCESS'
        full_access_session_id = $sessionId
        target = @{ title = 'Agent Test Window'; process = 'TestWindow.exe' }
        steps = @(
            @{
                name = 'run local oj'
                type = 'coding'
                action = 'run_code'
                html_path = $baseHtml
                user_goal = 'practice two sum'
                language = 'cpp'
                code = 'int main(){return 0;}'
                allow_submit = $false
            }
        )
    }
    $task | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskPath -Encoding UTF8
    $taskResult = Invoke-AgentJson -CmdArgs @('run-task', '--file', $taskPath, '--report', $taskReport)
    $reportText = Get-Content -LiteralPath $taskReport -Raw
    Add-Check 'run-task coding step' ($taskResult.json.ok -and $reportText -match 'CodingWorkflowContext' -and $reportText -match 'SAMPLE_PASS') $taskResult.text
} finally {
    Remove-Item -LiteralPath $SessionPath -ErrorAction SilentlyContinue
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}

$passCount = @($Checks | Where-Object Status -eq 'PASS').Count
$failCount = @($Checks | Where-Object Status -eq 'FAIL').Count
$lines = @(
    '# Coding Workflow Selftest Report',
    '',
    "- Version: $((Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim())",
    "- Result: $(if ($failCount -eq 0) { 'PASS' } else { 'FAIL' })",
    "- PASS: $passCount",
    "- FAIL: $failCount",
    '',
    '| check | status | detail |',
    '|---|---|---|'
)
foreach ($check in $Checks) {
    $detail = ([string]$check.Detail) -replace '\|', '/'
    $lines += "| $($check.Name) | $($check.Status) | $detail |"
}
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host "Coding workflow selftest passed. Report: $Report"
