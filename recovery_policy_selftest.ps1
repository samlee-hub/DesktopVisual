param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\recovery_policy_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.2.1 RecoveryPolicy schema handling.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.2.1'
$Report = Join-Path $ArtifactDir 'recovery_policy_selftest_report.md'
$Valid = Join-Path $Root 'tasks\recovery_policy\valid_standard_recovery_policy.json'
$Invalid = Join-Path $Root 'tasks\recovery_policy\invalid_unknown_strategy.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

foreach ($path in @($Valid, $Invalid)) {
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
}

$validOutput = & $WinAgent recovery-policy-validate --file $Valid
if ($LASTEXITCODE -ne 0) {
    throw "Expected valid recovery policy to pass. Output: $validOutput"
}
$validJson = $validOutput | ConvertFrom-Json
if (-not $validJson.ok) { throw "Valid policy returned ok=false: $validOutput" }
if ($validJson.data.schema_version -ne '5.2.1') { throw 'Unexpected schema_version for valid policy.' }
if ($validJson.data.route_count -ne 9) { throw "Expected 9 routes, got $($validJson.data.route_count)" }
foreach ($strategy in @('re_observe', 're_locate', 'wait_and_retry', 'invalidate_cache', 'use_profile_fallback', 'use_visual_provider', 'ask_user', 'escalate_to_agent', 'stop')) {
    if (($validJson.data.supported_strategies -notcontains $strategy) -and (($validJson.data.supported_strategies | Out-String) -notmatch [regex]::Escape($strategy))) {
        throw "Valid policy missing strategy $strategy"
    }
}

$invalidOutput = & $WinAgent recovery-policy-validate --file $Invalid
if ($LASTEXITCODE -eq 0) {
    throw "Expected invalid recovery policy to fail. Output: $invalidOutput"
}
$invalidJson = $invalidOutput | ConvertFrom-Json
if ($invalidJson.ok) { throw "Invalid policy returned ok=true: $invalidOutput" }
if ($invalidJson.error.code -ne 'RECOVERY_POLICY_SCHEMA_INVALID') {
    throw "Unexpected invalid policy error code: $($invalidJson.error.code)"
}

$lines = @(
    '# v5.2.1 Recovery Policy Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- Valid policy parse: PASS',
    '- Invalid policy handling: PASS',
    '',
    '## Valid Output',
    '',
    '```json',
    $validOutput,
    '```',
    '',
    '## Invalid Output',
    '',
    '```json',
    $invalidOutput,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.2.1 RecoveryPolicy selftest'
Write-Host "Report: $Report"
