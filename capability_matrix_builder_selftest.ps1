param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\capability_matrix'
$JsonReport = Join-Path $OutDir 'developer_capability_matrix.json'
$MdReport = Join-Path $OutDir 'developer_capability_matrix.md'
$ReportPath = Join-Path $OutDir 'capability_matrix_builder_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent capability-matrix-build --output $JsonReport --markdown-output $MdReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "capability-matrix-build failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
if (@($report.capabilities).Count -lt 16) { throw 'capability matrix must include at least 16 rows' }
if ($report.developer_build_full_access_default -ne $true) { throw 'developer build must be full access by default' }
if ($report.public_release_permission_policy -ne 'deferred') { throw 'public release permission policy must be deferred' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Capability Matrix Builder Selftest

- status: PASS
- capability_count: $(@($report.capabilities).Count)
- developer_build_full_access_default: true
- public_release_permission_policy: deferred
"@
$global:LASTEXITCODE = 0
Write-Host 'capability_matrix_builder_selftest PASS'
