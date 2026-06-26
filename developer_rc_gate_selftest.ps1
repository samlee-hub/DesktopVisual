param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\developer_rc_gate'
$JsonReport = Join-Path $OutDir 'developer_rc_gate_report.json'
$ReportPath = Join-Path $OutDir 'developer_rc_gate_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent developer-rc-gate --output $JsonReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "developer-rc-gate failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
if ($report.developer_rc_status -notin @('PASS','PASS_WITH_RELEASE_DEFERRED_ITEMS')) { throw "unexpected developer_rc_status: $($report.developer_rc_status)" }
if ($report.developer_full_access_default -ne $true) { throw 'developer full access must be preserved' }
if ($report.release_permission_hardening_deferred -ne $true) { throw 'release hardening must be deferred' }
if ($report.public_release_hardening_implemented -ne $false) { throw 'public release hardening must not be implemented' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Developer RC Gate Selftest

- status: PASS
- developer_rc_status: $($report.developer_rc_status)
- developer_full_access_default: true
- release_permission_hardening_deferred: true
"@
$global:LASTEXITCODE = 0
Write-Host 'developer_rc_gate_selftest PASS'
