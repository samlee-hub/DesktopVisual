param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$Agent = Join-Path $Root 'bin\winagent.exe'

function Fail($Message) {
    Write-Error $Message
    exit 1
}

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $raw = & $Agent @CmdArgs
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Fail "Command failed: $($CmdArgs -join ' ')`n$raw"
    }
    try {
        return $raw | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from command: $($CmdArgs -join ' ')`n$raw"
    }
}

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'build.ps1 failed.' }
}

if (-not (Test-Path $Agent)) { Fail "winagent.exe not found: $Agent" }

$work = Join-Path $Root 'artifacts\form_semantics'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$html = Join-Path $work 'form_semantics.html'
$htmlText = @'
<!doctype html>
<html>
<head><title>Form Semantics Fixture</title></head>
<body>
  <label for="name">Name</label>
  <input id="name" name="name" type="text" data-label="Name" required>

  <fieldset>
    <legend>Choice</legend>
    <input id="choice_a" name="choice" type="radio" value="a" data-label="Choice A">
    <input id="choice_b" name="choice" type="radio" value="b" data-label="Choice B">
  </fieldset>

  <label for="terms">Terms</label>
  <input id="terms" name="terms" type="checkbox" data-label="Terms">

  <label for="country">Country</label>
  <select id="country" name="country" data-label="Country">
    <option value="us">United States</option>
    <option value="ca">Canada</option>
  </select>

  <label for="comments">Comments</label>
  <textarea id="comments" name="comments" data-label="Comments"></textarea>

  <button id="submit" data-label="Submit">Submit</button>
  <textarea id="code" name="code" data-label="Code" data-control-type="code_editor"></textarea>
  <div id="captcha" data-label="Captcha" data-control-type="captcha">captcha challenge</div>
  <div id="mystery" data-label="Mystery">Mystery field</div>
  <input id="dup1" name="dup1" type="text" data-label="Duplicate">
  <input id="dup2" name="dup2" type="text" data-label="Duplicate">
</body>
</html>
'@
Set-Content -LiteralPath $html -Value $htmlText -Encoding UTF8

$cases = @(
    @{ id='name'; type='textbox'; action='fill_text' },
    @{ id='choice'; type='radio'; action='select_radio' },
    @{ id='terms'; type='checkbox'; action='toggle_checkbox' },
    @{ id='country'; type='dropdown'; action='select_option' },
    @{ id='comments'; type='textarea'; action='fill_textarea' },
    @{ id='submit'; type='button'; action='click_button' },
    @{ id='code'; type='code_editor'; action='input_code' }
)

foreach ($case in $cases) {
    $result = Invoke-AgentJson -CmdArgs @('form-control', '--html', $html, '--field-id', $case.id)
    if (-not $result.ok) { Fail "form-control failed for $($case.id)" }
    if ($result.data.control.control_type -ne $case.type) { Fail "$($case.id) expected $($case.type), got $($result.data.control.control_type)" }
    if ($result.data.control.recommended_action -ne $case.action) { Fail "$($case.id) expected action $($case.action), got $($result.data.control.recommended_action)" }
}

$radio = Invoke-AgentJson -CmdArgs @('form-control', '--html', $html, '--field-id', 'choice')
if ($radio.data.control.options.Count -lt 2) { Fail 'radio options were not recorded.' }

$captcha = Invoke-AgentJson -CmdArgs @('form-control', '--html', $html, '--field-id', 'captcha') -AllowFailure
if ($captcha.ok -or $captcha.error.code -ne 'CAPTCHA_DETECTED') { Fail 'captcha/challenge did not stop.' }

$unknown = Invoke-AgentJson -CmdArgs @('form-control', '--html', $html, '--field-id', 'mystery', '--min-confidence', '0.80') -AllowFailure
if ($unknown.ok -or $unknown.error.code -ne 'FIELD_CONFIDENCE_LOW') { Fail 'unknown low-confidence field did not stop.' }

$duplicate = Invoke-AgentJson -CmdArgs @('form-control', '--html', $html, '--label', 'Duplicate') -AllowFailure
if ($duplicate.ok -or $duplicate.error.code -ne 'FIELD_NOT_UNIQUE') { Fail 'duplicate fields did not return FIELD_NOT_UNIQUE.' }

$testWindow = Join-Path 'D:\testrepo\testwindow\bin' 'TestWindow.exe'
if (-not (Test-Path $testWindow)) { Fail "TestWindow.exe not found: $testWindow" }
$proc = Start-Process -FilePath $testWindow -PassThru
try {
    Start-Sleep -Milliseconds 800
    $taskPath = Join-Path $work 'form_action.task.json'
    $report = Join-Path $work 'form_action_report.md'
    $taskJson = @"
{
  "version": 1,
  "name": "form_semantics_task",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    { "name": "select_choice", "type": "form_action", "html_path": "$($html.Replace('\','\\'))", "field_id": "choice", "value": "b" },
    { "name": "fill_code", "type": "form_action", "html_path": "$($html.Replace('\','\\'))", "field_id": "code", "text": "int main() { return 0; }" }
  ]
}
"@
    Set-Content -LiteralPath $taskPath -Value $taskJson -Encoding UTF8
    $task = Invoke-AgentJson -CmdArgs @('run-task', '--file', $taskPath, '--report', $report)
    if (-not $task.ok) { Fail "run-task form_action failed: $($task.error.code)" }
    $reportText = Get-Content -LiteralPath $report -Raw
    if ($reportText -notmatch 'select_radio' -or $reportText -notmatch 'input_code') {
        Fail 'form_action report did not record mapped actions.'
    }
} finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}

Write-Host 'Form semantics selftest passed.'
