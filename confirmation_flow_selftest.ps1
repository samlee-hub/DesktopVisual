param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\confirmation_flow_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.3.4 local mock confirmation flow.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.3.4'
$Report = Join-Path $ArtifactDir 'confirmation_flow_selftest_report.md'
$Flow = Join-Path $Root 'tasks\confirmation\local_mail_mock_send_confirm.json'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
Get-Content -LiteralPath $Flow -Raw | ConvertFrom-Json | Out-Null

$blockedOutput = & $WinAgent confirmation-flow-run --file $Flow
if ($LASTEXITCODE -eq 0) {
    throw "Expected no-confirmation flow to fail. Output: $blockedOutput"
}
$blockedJson = $blockedOutput | ConvertFrom-Json
if ($blockedJson.error.code -ne 'CONFIRMATION_REQUIRED') { throw "Expected CONFIRMATION_REQUIRED, got $($blockedJson.error.code)" }

$output = & $WinAgent confirmation-flow-run --file $Flow --response confirm
if ($LASTEXITCODE -ne 0) {
    throw "confirmation-flow-run confirm failed. Output: $output"
}
$json = $output | ConvertFrom-Json
if (-not $json.ok) { throw 'confirmation-flow-run returned ok=false.' }
if ($json.data.sent_state -ne 'mock_sent') { throw "Expected mock_sent, got $($json.data.sent_state)" }
foreach ($field in @('confirmation_audit', 'confirmation_request', 'confirmation_report', 'sent_state_artifact')) {
    if ($null -eq $json.data.$field) { throw "Flow result missing $field" }
    $full = Join-Path $Root $json.data.$field
    if (-not (Test-Path -LiteralPath $full)) { throw "Expected flow artifact missing: $full" }
}
$auditText = Get-Content -LiteralPath (Join-Path $Root $json.data.confirmation_audit) -Raw
if ($auditText -notmatch 'confirmation_accepted') { throw 'Confirmation audit missing accepted marker.' }
if ($auditText -notmatch 'mock_send') { throw 'Confirmation audit missing mock_send marker.' }

$lines = @(
    '# v5.3.4 Confirmation Flow Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- no confirmation blocked: PASS',
    '- confirmed local mock send: PASS',
    '- audit contains confirmation: PASS',
    '',
    '## Blocked Output',
    '',
    '```json',
    $blockedOutput,
    '```',
    '',
    '## Confirmed Output',
    '',
    '```json',
    $output,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.3.4 Confirmation flow selftest'
Write-Host "Report: $Report"
