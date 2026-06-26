param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff\selftests\developer_full_access_policy'
$ReportPath = Join-Path $OutDir 'developer_full_access_policy_verifier_selftest_report.md'
$JsonReport = Join-Path $OutDir 'developer_full_access_policy_report.json'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $WinAgent developer-full-access-policy-check --output $JsonReport | Out-Null
if ($LASTEXITCODE -ne 0) { throw "developer-full-access-policy-check failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $JsonReport)) { throw 'developer full access policy report missing' }

$report = Get-Content -Raw -LiteralPath $JsonReport | ConvertFrom-Json
if ($report.status -ne 'PASS') { throw "expected PASS, got $($report.status)" }
if ($report.developer_full_access_default -ne $true) { throw 'developer_full_access_default must remain true' }
if ($report.release_permission_hardening_deferred -ne $false) { throw 'release_permission_hardening_deferred must be false for v1.1.0' }
if ($report.task_keyword_denylist_present -ne $false) { throw 'developer mode task keyword denylist must not exist' }
if ($report.public_release_hardening_implemented -ne $true) { throw 'public release hardening must be implemented for v1.1.0' }
if ($report.public_permission_aligned -ne $true) { throw 'public permission alignment must be true for v1.1.0' }
$allowedStops = @($report.allowed_stop_boundaries)
foreach ($required in @('captcha_or_human_verification','account_security_verification','credential_handoff','active_proctoring_or_lockdown','anti_cheat_or_anti_automation','third_party_automation_interception','explicit_security_or_risk_verification')) {
    if ($allowedStops -notcontains $required) { throw "missing allowed stop boundary: $required" }
}

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Developer Full Access Policy Verifier Selftest

- status: PASS
- developer_full_access_default: true
- release_permission_hardening_deferred: false
- task_keyword_denylist_present: false
- public_release_hardening_implemented: true
- public_permission_aligned: true
"@
$global:LASTEXITCODE = 0
Write-Host 'developer_full_access_policy_verifier_selftest PASS'
