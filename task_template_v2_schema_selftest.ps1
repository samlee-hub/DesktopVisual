param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_template_v2_schema_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.4.1 Task Template v2 schema and invalid template rejection.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.4.1'
$Report = Join-Path $ArtifactDir 'task_template_v2_schema_selftest_report.md'
$Template = Join-Path $Root 'tasks\templates_v2\local_form_fill_submit.task-template-v2.json'
$InvalidTemplate = Join-Path $Root 'tasks\templates_v2\invalid_missing_profile.task-template-v2.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

function Invoke-JsonCommand {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))

    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit for $($Arguments -join ' '): $text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

foreach ($path in @($Template, $InvalidTemplate)) {
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
}

$valid = Invoke-JsonCommand @('task-template-v2-validate', '--file', $Template)
if (-not $valid.Json.ok) {
    throw "Expected valid template to pass. output=$($valid.Text)"
}
if ($valid.Json.data.template_id -ne 'local_form_fill_submit') {
    throw "Unexpected template_id: $($valid.Json.data.template_id)"
}
if ($valid.Json.data.required_profile -ne 'browser_local') {
    throw "Unexpected required_profile: $($valid.Json.data.required_profile)"
}
if ($valid.Json.data.parameter_count -lt 4 -or $valid.Json.data.step_count -lt 3) {
    throw "Expected template parameters and steps in serialized data."
}
foreach ($field in @('states','preconditions','verification','recovery','confirmation_nodes','final_state_policy')) {
    if ($null -eq $valid.Json.data.$field) {
        throw "Validation data missing $field"
    }
}

$invalid = Invoke-JsonCommand @('task-template-v2-validate', '--file', $InvalidTemplate) -AllowedExitCodes @(1)
if ($invalid.Json.ok -or $invalid.Json.error.code -ne 'TASK_TEMPLATE_V2_SCHEMA_INVALID') {
    throw "Expected invalid template rejection. output=$($invalid.Text)"
}
if ($invalid.Json.error.message -notmatch 'required_profile') {
    throw "Expected invalid template error to mention required_profile. output=$($invalid.Text)"
}

$lines = @(
    '# v5.4.1 Task Template v2 Schema Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Valid template: `{0}`' -f $Template),
    ('- Invalid template: `{0}`' -f $InvalidTemplate),
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
Write-Host 'PASS: v5.4.1 Task Template v2 schema selftest'
Write-Host "Report: $Report"
