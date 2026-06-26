param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\step_contract_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.1.1 StepContract schema and serialization.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.1.1'
$Report = Join-Path $ArtifactDir 'step_contract_selftest_report.md'
$SchemaFixture = Join-Path $Root 'tasks\step_contract\step_contract.schema.json'
$ValidFixture = Join-Path $Root 'tasks\step_contract\valid_local_form_submit.step.json'
$InvalidFixture = Join-Path $Root 'tasks\step_contract\invalid_missing_verification.step.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

foreach ($jsonPath in @($SchemaFixture, $ValidFixture, $InvalidFixture)) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}

function Invoke-JsonCommand {
    param([string[]]$Arguments)

    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{
        ExitCode = $exit
        Text = $text
        Json = $json
    }
}

$valid = Invoke-JsonCommand @('step-contract-validate', '--file', $ValidFixture)
if ($valid.ExitCode -ne 0 -or -not $valid.Json.ok) {
    throw "Expected valid StepContract to pass. output=$($valid.Text)"
}
if ($valid.Json.data.schema_version -ne '5.1.1') {
    throw "Expected schema_version 5.1.1, got $($valid.Json.data.schema_version)"
}
if ($valid.Json.data.step_id -ne 'click_submit_and_verify') {
    throw "Unexpected step_id: $($valid.Json.data.step_id)"
}
if ($valid.Json.data.precondition_count -lt 6) {
    throw "Expected at least six preconditions."
}
if ($valid.Json.data.expected_change_event_count -ne 3) {
    throw "Expected three expected change events."
}
if ($valid.Json.data.safety_requirements.allow_unrestricted_desktop) {
    throw "StepContract must not allow unrestricted desktop."
}

$invalid = Invoke-JsonCommand @('step-contract-validate', '--file', $InvalidFixture)
if ($invalid.ExitCode -eq 0 -or $invalid.Json.ok) {
    throw "Expected invalid StepContract to fail. output=$($invalid.Text)"
}
if ($invalid.Json.error.code -ne 'STEP_CONTRACT_SCHEMA_INVALID') {
    throw "Expected STEP_CONTRACT_SCHEMA_INVALID, got $($invalid.Json.error.code)"
}
if ($invalid.Json.error.message -notmatch 'verification') {
    throw "Expected missing verification error. output=$($invalid.Text)"
}

$lines = @(
    '# v5.1.1 StepContract Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Schema fixture: `{0}`' -f $SchemaFixture),
    ('- Valid fixture: `{0}`' -f $ValidFixture),
    ('- Invalid fixture: `{0}`' -f $InvalidFixture),
    '',
    '## Valid Output',
    '',
    '```json',
    $valid.Text,
    '```',
    '',
    '## Invalid Output',
    '',
    '```json',
    $invalid.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.1.1 StepContract selftest'
Write-Host "Report: $Report"
