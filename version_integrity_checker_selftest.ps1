param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\version_integrity'
$JsonReport = Join-Path $OutDir 'version_integrity_report.json'
$ReportPath = Join-Path $OutDir 'version_integrity_checker_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent version-integrity-check --output $JsonReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "version-integrity-check failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
if ($report.version_file -ne '6.12.0') { throw 'VERSION must be 6.12.0' }
if ($report.runtime_binary_version -ne '6.12.0') { throw 'runtime binary version must be 6.12.0' }
if ($report.tag_v6_11_0_exists -ne $true) { throw 'v6.11.0 tag must exist' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Version Integrity Checker Selftest

- status: PASS
- VERSION: $($report.version_file)
- runtime_binary_version: $($report.runtime_binary_version)
- tag_v6_11_0_exists: true
"@
$global:LASTEXITCODE = 0
Write-Host 'version_integrity_checker_selftest PASS'
