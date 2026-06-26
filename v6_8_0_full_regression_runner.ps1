param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows'
$ReportPath = Join-Path $ArtifactDir 'full_regression_report.md'
$ResultPath = Join-Path $ArtifactDir 'full_regression_result.json'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$commands = @(
    @{ command = '.\build.ps1'; required = $true },
    @{ command = '.\selftest.ps1'; required = $true },
    @{ command = '.\validation_fingerprint_selftest.ps1'; required = $true },
    @{ command = '.\validation_consistency_checker_selftest.ps1'; required = $true },
    @{ command = '.\regression_skip_policy_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_schema_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_compiler_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_executor_selftest.ps1'; required = $true },
    @{ command = '.\web_form_field_locator_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_verifier_selftest.ps1'; required = $true },
    @{ command = '.\browser_recovery_selftest.ps1'; required = $true },
    @{ command = '.\browser_protection_stop_selftest.ps1'; required = $true },
    @{ command = '.\v6_8_0_browser_form_workflow_runner.ps1'; required = $true },
    @{ command = '.\v6_8_0_browser_form_workflow_verifier.ps1'; required = $true },
    @{ command = '.\v6_8_0_browser_form_workflow_acceptance_gate.ps1'; required = $true },
    @{ command = '.\v6_8_0_preflight_validation_acceptance_gate.ps1'; required = $true }
)

foreach ($optional in @('adapter_selftest.ps1','app_profile_selftest.ps1','case_v2_selftest.ps1','selector_selftest.ps1','serve_selftest.ps1')) {
    if (Test-Path (Join-Path $Root $optional)) { $commands += @{ command = ".\$optional"; required = $true } }
}
if (Test-Path (Join-Path $Root 'rc_check.ps1')) {
    $commands += @{ command = '.\rc_check.ps1'; required = $false }
}

$results = @()
foreach ($entry in $commands) {
    $cmd = $entry.command
    $safe = ($cmd -replace '[^a-zA-Z0-9_.-]', '_')
    $stdout = Join-Path $ArtifactDir "full_regression_$safe.log"
    Push-Location $Root
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd *> $stdout
    $exit = $LASTEXITCODE
    Pop-Location
    $results += [pscustomobject]@{ command = $cmd; required = [bool]$entry.required; exit_code = $exit; ok = ($exit -eq 0); blocking_ok = ((-not [bool]$entry.required) -or $exit -eq 0); log = $stdout }
}

$ok = @($results | Where-Object { -not $_.blocking_ok }).Count -eq 0
[pscustomobject]@{
    schema_version = '6.8.0.full_regression'
    regression_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    commands = $results
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$lines = @('# v6.8.0 Full Regression Report','')
$lines += "- regression_ok: $ok"
foreach ($r in $results) {
    $lines += "- $($r.command): required=$($r.required) ok=$($r.ok) blocking_ok=$($r.blocking_ok) exit=$($r.exit_code) log=$($r.log)"
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($ok) {
    'v6_8_0_full_regression_runner PASS'
    exit 0
}
'v6_8_0_full_regression_runner BLOCKED'
exit 1
