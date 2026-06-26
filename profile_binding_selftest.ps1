param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\profile_binding_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.4.2 profile binding resolver behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.4.2'
$Report = Join-Path $ArtifactDir 'profile_binding_selftest_report.md'
$Template = Join-Path $Root 'tasks\templates_v2\local_mail_mock_compose_attach_no_real_send.task-template-v2.json'
$MissingLocatorTemplate = Join-Path $Root 'tasks\templates_v2\invalid_missing_locator_binding.task-template-v2.json'
$Params = Join-Path $Root 'samples\tasks\local_mail_mock_compose_attach_no_real_send.params.json'

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

$resolved = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $Template, '--profile', 'local_mail_mock', '--params-file', $Params)
if (-not $resolved.Json.ok) {
    throw "Expected local_mail_mock profile binding to pass. output=$($resolved.Text)"
}
if ($resolved.Json.data.bound_profile.common_locators -ne $true -or
    $resolved.Json.data.bound_profile.roi_definitions -ne $true -or
    $resolved.Json.data.bound_profile.visual_strategy -ne $true -or
    $resolved.Json.data.bound_profile.recovery_strategy -ne $true -or
    $resolved.Json.data.bound_profile.confirmation_nodes -ne $true) {
    throw "Expected all profile binding sources to participate. output=$($resolved.Text)"
}
if ($resolved.Json.data.bound_profile.can_override_safety_manifest -ne $false) {
    throw 'Profile binding must not override Safety Manifest.'
}
$selectors = @($resolved.Json.data.resolved_steps | Where-Object { $_.selector } | ForEach-Object { $_.selector })
if ($selectors -notcontains 'uia:name=Compose,type=Button') {
    throw "Expected compose_button locator binding. output=$($resolved.Text)"
}
if ($selectors -notcontains 'uia:name=Send Mock,type=Button') {
    throw "Expected mock_send_button locator binding. output=$($resolved.Text)"
}

$missing = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $MissingLocatorTemplate, '--profile', 'local_mail_mock', '--params-file', $Params) -AllowedExitCodes @(1)
if ($missing.Json.ok -or $missing.Json.error.code -ne 'PROFILE_BINDING_MISSING_LOCATOR') {
    throw "Expected missing locator binding failure. output=$($missing.Text)"
}

$lines = @(
    '# v5.4.2 Profile Binding Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- local_mail_mock profile binding: PASS',
    '- missing locator handling: PASS',
    '- profile cannot override safety manifest: PASS',
    '',
    '## Resolved Output',
    '',
    '```json',
    $resolved.Text,
    '```',
    '',
    '## Missing Locator Output',
    '',
    '```json',
    $missing.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.4.2 profile binding selftest'
Write-Host "Report: $Report"
