param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\release_deferred_ledger'
$JsonReport = Join-Path $OutDir 'release_hardening_deferred_ledger.json'
$MdReport = Join-Path $OutDir 'release_hardening_deferred_ledger.md'
$ReportPath = Join-Path $OutDir 'release_hardening_deferred_ledger_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent release-hardening-deferred-ledger --output $JsonReport --markdown-output $MdReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "release-hardening-deferred-ledger failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS_WITH_RELEASE_DEFERRED_ITEMS') { throw "unexpected status: $($report.status)" }
if ($report.developer_rc_blocker -ne $false) { throw 'deferred public release items must not block Developer RC' }
if (@($report.items).Count -lt 10) { throw 'expected at least ten deferred release items' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Release Hardening Deferred Ledger Selftest

- status: PASS
- deferred_items: $(@($report.items).Count)
- developer_rc_blocker: false
"@
$global:LASTEXITCODE = 0
Write-Host 'release_hardening_deferred_ledger_selftest PASS'
