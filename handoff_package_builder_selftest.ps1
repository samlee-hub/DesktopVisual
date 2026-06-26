param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\handoff_package'
$JsonReport = Join-Path $OutDir 'handoff_package_report.json'
$ReportPath = Join-Path $OutDir 'handoff_package_builder_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent handoff-package-build --output $JsonReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "handoff-package-build failed with exit code $LASTEXITCODE" }
$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
if (@($report.files).Count -lt 10) { throw 'handoff package must include required summary files' }
foreach ($name in @($report.files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $report.package_root $name))) { throw "handoff file missing: $name" }
}
if ($report.runtime_sessions_dump_included -ne $false) { throw 'handoff package must not include runtime_sessions dump' }
if ($report.stash_content_included -ne $false) { throw 'handoff package must not include stash content' }
if ($report.sensitive_communication_content_included -ne $false) { throw 'handoff package must not include sensitive communication content' }
if ($report.public_release_package_generated -ne $false) { throw 'handoff package must not generate public release package' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Handoff Package Builder Selftest

- status: PASS
- required_files_present: true
- runtime_sessions_dump_included: false
- stash_content_included: false
- sensitive_communication_content_included: false
- public_release_package_generated: false
"@
$global:LASTEXITCODE = 0
Write-Host 'handoff_package_builder_selftest PASS'
