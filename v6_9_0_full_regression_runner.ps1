param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$ReportPath = Join-Path $ArtifactRoot 'full_regression_report.md'
$ResultPath = Join-Path $ArtifactRoot 'full_regression_result.json'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$commands = @(
    @{ command = '.\build.ps1'; required = $true },
    @{ command = '.\selftest.ps1'; required = $true },
    @{ command = '.\validation_fingerprint_selftest.ps1'; required = $true },
    @{ command = '.\validation_consistency_checker_selftest.ps1'; required = $true },
    @{ command = '.\regression_skip_policy_selftest.ps1'; required = $true },
    @{ command = '.\step_contract_validator_selftest.ps1'; required = $true },
    @{ command = '.\compiled_plan_executor_selftest.ps1'; required = $true },
    @{ command = '.\runtime_session_selftest.ps1'; required = $true },
    @{ command = '.\execution_evidence_pack_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_schema_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_compiler_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_executor_selftest.ps1'; required = $true },
    @{ command = '.\browser_workflow_verifier_selftest.ps1'; required = $true },
    @{ command = '.\browser_recovery_selftest.ps1'; required = $true },
    @{ command = '.\browser_protection_stop_selftest.ps1'; required = $true },
    @{ command = '.\explorer_workflow_schema_selftest.ps1'; required = $true },
    @{ command = '.\explorer_workflow_compiler_selftest.ps1'; required = $true },
    @{ command = '.\explorer_workflow_executor_selftest.ps1'; required = $true },
    @{ command = '.\explorer_workflow_verifier_selftest.ps1'; required = $true },
    @{ command = '.\communication_schema_selftest.ps1'; required = $true },
    @{ command = '.\communication_adapter_selftest.ps1'; required = $true },
    @{ command = '.\communication_executor_selftest.ps1'; required = $true },
    @{ command = '.\communication_verifier_selftest.ps1'; required = $true },
    @{ command = '.\v6_9_0_communication_runner.ps1'; required = $true },
    @{ command = '.\v6_9_0_communication_verifier.ps1'; required = $true },
    @{ command = '.\adapter_selftest.ps1'; required = $true },
    @{ command = '.\app_profile_selftest.ps1'; required = $true },
    @{ command = '.\case_v2_selftest.ps1'; required = $true },
    @{ command = '.\selector_selftest.ps1'; required = $true },
    @{ command = '.\serve_selftest.ps1'; required = $true }
)

$results = @()
foreach ($entry in $commands) {
    $cmd = $entry.command
    $safe = ($cmd -replace '[^a-zA-Z0-9_.-]', '_')
    $stdout = Join-Path $ArtifactRoot "full_regression_$safe.log"
    Push-Location $Root
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd *> $stdout
    $exit = $LASTEXITCODE
    Pop-Location
    $results += [pscustomobject]@{
        command = $cmd
        required = [bool]$entry.required
        exit_code = $exit
        ok = ($exit -eq 0)
        blocking_ok = ((-not [bool]$entry.required) -or $exit -eq 0)
        log = $stdout
    }
}

$ok = @($results | Where-Object { -not $_.blocking_ok }).Count -eq 0
[pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.full_regression'
    regression_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    commands = $results
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$lines = @('# v6.9.0 Communication Full Regression Report','')
$lines += "- regression_ok: $ok"
foreach ($result in $results) {
    $lines += "- $($result.command): required=$($result.required) ok=$($result.ok) blocking_ok=$($result.blocking_ok) exit=$($result.exit_code) log=$($result.log)"
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($ok) {
    'v6_9_0_full_regression_runner PASS'
    exit 0
}
'v6_9_0_full_regression_runner BLOCKED'
exit 1
