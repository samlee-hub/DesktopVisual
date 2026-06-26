param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\risk_action_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.3.1 risk action classification.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.3.1'
$Report = Join-Path $ArtifactDir 'risk_action_selftest_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Assert-Risk {
    param(
        [string]$Action,
        [string]$ExpectedRisk,
        [bool]$ExpectedConfirmation,
        [string]$PermissionProfile = 'DEFAULT'
    )
    $output = & $WinAgent risk-action-classify --action $Action --permission-profile $PermissionProfile
    if ($LASTEXITCODE -ne 0) {
        throw "risk-action-classify failed for $Action. Output: $output"
    }
    $json = $output | ConvertFrom-Json
    if (-not $json.ok) { throw "risk-action-classify returned ok=false for $Action" }
    if ($json.data.risk_level -ne $ExpectedRisk) { throw "Expected $ExpectedRisk for $Action, got $($json.data.risk_level)" }
    if ([bool]$json.data.requires_confirmation -ne $ExpectedConfirmation) { throw "Unexpected confirmation flag for $Action" }
    return $output
}

$outputs = New-Object System.Collections.Generic.List[string]
$outputs.Add((Assert-Risk -Action 'local observe state' -ExpectedRisk 'low' -ExpectedConfirmation $false)) | Out-Null
$outputs.Add((Assert-Risk -Action 'open external url for review' -ExpectedRisk 'medium' -ExpectedConfirmation $false)) | Out-Null
foreach ($action in @('send email', 'submit external form', 'delete file', 'overwrite file', 'external upload', 'external download', 'account setting change', 'public posting', 'payment-like action')) {
    $outputs.Add((Assert-Risk -Action $action -ExpectedRisk 'high' -ExpectedConfirmation $true)) | Out-Null
}
$blocked = Assert-Risk -Action 'real exam submission' -ExpectedRisk 'blocked' -ExpectedConfirmation $false -PermissionProfile 'PUBLIC_RELEASE'
$blockedJson = $blocked | ConvertFrom-Json
if (-not $blockedJson.data.blocked) { throw 'Expected public profile real exam submission to be blocked.' }
if ($blockedJson.data.allowed_after_confirmation) { throw 'Blocked action must not be allowed after confirmation.' }
$outputs.Add($blocked) | Out-Null

$lines = @(
    '# v5.3.1 Risk Action Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- Low risk classification: PASS',
    '- Medium risk classification: PASS',
    '- High risk classifications: PASS',
    '- Public profile blocked restriction: PASS',
    '',
    '## Outputs',
    '',
    '```json'
) + $outputs + @('```')
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.3.1 Risk action selftest'
Write-Host "Report: $Report"
