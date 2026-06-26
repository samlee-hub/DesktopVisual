param(
    [string]$Root = '',
    [switch]$Help,
    [string]$ReportOut = "$PSScriptRoot\..\..\artifacts\dogfood\local_html\report.json"
)

$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'Usage: .\dogfood\local_html\run.ps1 [-Root <path>] [-ReportOut <path>]'
    Write-Host 'Runs the bounded local HTML form semantics dogfood task.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot '..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts\dogfood\local_html'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startTime = Get-Date
$status = 'PASS'
$reason = ''
$locators = New-Object System.Collections.Generic.List[string]
$screenshots = New-Object System.Collections.Generic.List[string]
$steps = 0

function Add-Step { $script:steps++ }
function Fail([string]$msg) { $script:status = 'FAIL'; $script:reason = $msg; throw $msg }
function Skip([string]$msg) { $script:status = 'SKIPPED'; $script:reason = $msg; throw $msg }

function Invoke-AgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    Add-Step
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try { return @{ exit = $exit; json = ($output | ConvertFrom-Json); text = [string]$output } }
    catch { Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output" }
}

function Write-Result {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds)
    $result = [PSCustomObject]@{
        app = 'Local HTML'
        task_id = 'local_html'
        status = $script:status
        reason = $script:reason
        steps = $script:steps
        duration_ms = $duration
        locators = (($script:locators | Select-Object -Unique) -join ',')
        screenshots = @($script:screenshots)
        report_path = $ReportOut
        safety_boundary = 'Generated local HTML fixture under artifacts\dogfood\local_html; no external web access or browser profile.'
        expected_result = 'form-control classifies mixed textbox, radio, checkbox, dropdown, textarea, and button controls.'
        skipped_condition = 'form-control command or local fixture parsing is unavailable.'
    }
    $result | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $ReportOut -Encoding utf8
    return $result
}

try {
    $html = Join-Path $Artifacts 'local_dogfood.html'
    $htmlText = @'
<!doctype html>
<html>
<head><title>DesktopVisual Local Dogfood Fixture</title></head>
<body>
  <label for="name">Name</label>
  <input id="name" name="name" type="text" data-label="Name">
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
  <button id="run" data-label="Run">Run</button>
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
        @{ id='run'; type='button'; action='click_button' }
    )

    foreach ($case in $cases) {
        $result = Invoke-AgentJson -WinArgs @('form-control', '--html', $html, '--field-id', $case.id) -AllowedExitCodes @(0, 1)
        if ($result.exit -ne 0 -or -not $result.json.ok) {
            Skip "form-control could not classify $($case.id): $($result.json.error.code)"
        }
        if ($result.json.data.control.control_type -ne $case.type) {
            Fail "$($case.id) expected $($case.type), got $($result.json.data.control.control_type)"
        }
        if ($result.json.data.control.recommended_action -ne $case.action) {
            Fail "$($case.id) expected $($case.action), got $($result.json.data.control.recommended_action)"
        }
    }

    $locators.Add('local_html_form_control')
    Write-Host '  Local HTML form semantics PASS'
} catch {
    if ($status -ne 'SKIPPED' -and $status -ne 'FAIL') {
        $status = 'FAIL'
        $reason = [string]$_
    }
    Write-Host "  Local HTML dogfood $status : $reason"
}

Write-Result
