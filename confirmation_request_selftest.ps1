param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\confirmation_request_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.3.2 ConfirmationRequest generation.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.3.2'
$Report = Join-Path $ArtifactDir 'confirmation_request_selftest_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$output = & $WinAgent confirmation-request-create `
    --action 'send email' `
    --risk-level high `
    --summary 'Review mock email before send.' `
    --target-window 'Local Mail Mock' `
    --screenshot 'artifacts/dev5.3.2/screenshots/pre_send_review.bmp' `
    --files 'artifacts/dev5.3.2/mock_attachment.txt' `
    --destination 'qa@example.invalid' `
    --timeout-ms 30000 `
    --allowed-responses 'confirm,reject'
if ($LASTEXITCODE -ne 0) {
    throw "confirmation-request-create failed. Output: $output"
}
$json = $output | ConvertFrom-Json
if (-not $json.ok) { throw 'confirmation-request-create returned ok=false.' }
foreach ($field in @('action', 'risk_level', 'summary', 'target_window', 'screenshot', 'involved_files', 'destination', 'timeout_ms', 'allowed_responses', 'audit_id', 'request_json', 'report_md')) {
    if ($null -eq $json.data.$field) { throw "ConfirmationRequest missing $field" }
}
if ($json.data.risk_level -ne 'high') { throw 'Expected risk_level high.' }
if ($json.data.allowed_responses -notcontains 'confirm') { throw 'allowed_responses missing confirm.' }
if ($json.data.allowed_responses -notcontains 'reject') { throw 'allowed_responses missing reject.' }
foreach ($path in @($json.data.request_json, $json.data.report_md)) {
    $full = Join-Path $Root $path
    if (-not (Test-Path -LiteralPath $full)) { throw "Expected artifact missing: $full" }
}
Get-Content -LiteralPath (Join-Path $Root $json.data.request_json) -Raw | ConvertFrom-Json | Out-Null

$lines = @(
    '# v5.3.2 Confirmation Request Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Request JSON: $($json.data.request_json)",
    "- Report MD: $($json.data.report_md)",
    '',
    '## Output',
    '',
    '```json',
    $output,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.3.2 ConfirmationRequest selftest'
Write-Host "Report: $Report"
