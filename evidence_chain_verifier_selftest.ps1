param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\evidence_chain'
$JsonReport = Join-Path $OutDir 'evidence_chain_report.json'
$ReportPath = Join-Path $OutDir 'evidence_chain_verifier_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent evidence-chain-verify --output $JsonReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "evidence-chain-verify failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
if (@($report.items).Count -lt 11) { throw 'expected v6.2-v6.11 evidence chain items' }
foreach ($item in @($report.items)) {
    if ($item.final_status_report_present -ne $true) { throw "missing final_status_report for $($item.id)" }
    if ($item.evidence_index_present -ne $true) { throw "missing evidence_index for $($item.id)" }
    if ($item.accepted_or_pass -ne $true) { throw "evidence item not accepted/pass: $($item.id)" }
    if ($item.raw_completed_unverified_as_pass -ne $false) { throw "RAW treated as PASS: $($item.id)" }
}

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Evidence Chain Verifier Selftest

- status: PASS
- chain_items: $(@($report.items).Count)
- raw_completed_unverified_as_pass: false
- old_ui_workflow_rerun: false
"@
$global:LASTEXITCODE = 0
Write-Host 'evidence_chain_verifier_selftest PASS'
