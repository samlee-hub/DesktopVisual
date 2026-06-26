param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\confirmation_gate_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.3.3 confirmation gate behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.3.3'
$Report = Join-Path $ArtifactDir 'confirmation_gate_selftest_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Gate {
    param(
        [string]$Action,
        [string]$Response,
        [string]$ExpectedDecision,
        [string]$Risk = '',
        [string]$PermissionProfile = 'DEFAULT',
        [int]$TimeoutMs = 30000,
        [int]$ElapsedMs = 0
    )
    $args = @('confirmation-gate-check', '--action', $Action, '--permission-profile', $PermissionProfile, '--timeout-ms', "$TimeoutMs", '--elapsed-ms', "$ElapsedMs")
    if ($Response -ne '') { $args += @('--response', $Response) }
    if ($Risk -ne '') { $args += @('--risk-level', $Risk) }
    $output = & $WinAgent @args
    if ($LASTEXITCODE -ne 0) {
        throw "confirmation-gate-check failed for $Action/$Response. Output: $output"
    }
    $json = $output | ConvertFrom-Json
    if (-not $json.ok) { throw "confirmation-gate-check returned ok=false for $Action/$Response" }
    if ($json.data.decision -ne $ExpectedDecision) { throw "Expected $ExpectedDecision for $Action/$Response, got $($json.data.decision)" }
    return $output
}

$outputs = New-Object System.Collections.Generic.List[string]
$outputs.Add((Gate -Action 'send email' -Response '' -ExpectedDecision 'blocked')) | Out-Null
$outputs.Add((Gate -Action 'send email' -Response 'confirm' -ExpectedDecision 'allowed')) | Out-Null
$outputs.Add((Gate -Action 'send email' -Response 'reject' -ExpectedDecision 'stopped')) | Out-Null
$outputs.Add((Gate -Action 'send email' -Response '' -ExpectedDecision 'stopped' -ElapsedMs 31000)) | Out-Null
$outputs.Add((Gate -Action 'submit external form' -Response '' -ExpectedDecision 'blocked' -PermissionProfile 'PUBLIC_RELEASE')) | Out-Null
$blocked = Gate -Action 'captcha solve' -Response 'confirm' -ExpectedDecision 'stopped'
$blockedJson = $blocked | ConvertFrom-Json
if (-not $blockedJson.data.blocked) { throw 'Blocked action must remain blocked.' }
if ($blockedJson.data.allowed) { throw 'Blocked action must not be allowed after confirmation.' }
$outputs.Add($blocked) | Out-Null

$lines = @(
    '# v5.3.3 Confirmation Gate Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- no confirmation -> blocked: PASS',
    '- confirm -> allowed: PASS',
    '- reject -> stopped: PASS',
    '- timeout -> stopped: PASS',
    '- public profile high-risk -> confirmation or stop: PASS',
    '- blocked action no bypass: PASS',
    '',
    '## Outputs',
    '',
    '```json'
) + $outputs + @('```')
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.3.3 Confirmation gate selftest'
Write-Host "Report: $Report"
