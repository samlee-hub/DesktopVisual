param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\step_verification_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.1.3 Step verification engine.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.1.3'
$Report = Join-Path $ArtifactDir 'step_verification_selftest_report.md'
$Contract = Join-Path $Root 'tasks\step_contract\valid_local_form_submit.step.json'
$Before = Join-Path $Root 'tasks\step_contract\verification_before_submit.json'
$AfterSuccess = Join-Path $Root 'tasks\step_contract\verification_after_success.json'
$AfterWrongEvent = Join-Path $Root 'tasks\step_contract\verification_after_wrong_event.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

foreach ($jsonPath in @($Contract, $Before, $AfterSuccess, $AfterWrongEvent)) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}

function Invoke-JsonCommand {
    param([string[]]$Arguments)
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$success = Invoke-JsonCommand @('step-verify', '--contract', $Contract, '--before', $Before, '--after', $AfterSuccess, '--timeout-ms', '1000', '--elapsed-ms', '50')
if ($success.ExitCode -ne 0 -or -not $success.Json.ok) {
    throw "Expected verification success. output=$($success.Text)"
}
if ($success.Json.data.scene_state_ok -ne $true -or $success.Json.data.text_appeared_ok -ne $true) {
    throw "Expected scene_state and text appeared checks to pass."
}
if ($success.Json.data.region_changed_ok -ne $true) {
    throw "Expected region_changed check to pass."
}

$timeout = Invoke-JsonCommand @('step-verify', '--contract', $Contract, '--before', $Before, '--after', $AfterSuccess, '--timeout-ms', '1000', '--elapsed-ms', '1500')
if ($timeout.ExitCode -eq 0 -or $timeout.Json.ok) {
    throw "Expected verification timeout. output=$($timeout.Text)"
}
if ($timeout.Json.error.code -ne 'VERIFICATION_TIMEOUT') {
    throw "Expected VERIFICATION_TIMEOUT, got $($timeout.Json.error.code)"
}

$wrong = Invoke-JsonCommand @('step-verify', '--contract', $Contract, '--before', $Before, '--after', $AfterWrongEvent, '--timeout-ms', '1000', '--elapsed-ms', '50')
if ($wrong.ExitCode -eq 0 -or $wrong.Json.ok) {
    throw "Expected wrong event verification failure. output=$($wrong.Text)"
}
if ($wrong.Json.error.code -ne 'VERIFICATION_FAILED' -or $wrong.Json.error.message -notmatch 'text_appeared') {
    throw "Expected VERIFICATION_FAILED mentioning text_appeared. output=$($wrong.Text)"
}

$lines = @(
    '# v5.1.3 Step Verification Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '',
    '## Success Output',
    '',
    '```json',
    $success.Text,
    '```',
    '',
    '## Timeout Output',
    '',
    '```json',
    $timeout.Text,
    '```',
    '',
    '## Wrong Event Output',
    '',
    '```json',
    $wrong.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.1.3 Step verification selftest'
Write-Host "Report: $Report"
