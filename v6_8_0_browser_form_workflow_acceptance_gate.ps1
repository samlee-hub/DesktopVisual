param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows'
$VerifierResult = Join-Path $ArtifactDir 'browser_form_workflow_verifier_result.json'
$GateResult = Join-Path $ArtifactDir 'v6_8_0_acceptance_gate_result.json'
$GateReport = Join-Path $ArtifactDir 'v6_8_0_acceptance_gate_report.md'

$requiredScripts = @(
    'browser_workflow_schema_selftest.ps1',
    'browser_workflow_compiler_selftest.ps1',
    'browser_workflow_executor_selftest.ps1',
    'web_form_field_locator_selftest.ps1',
    'browser_workflow_verifier_selftest.ps1',
    'browser_recovery_selftest.ps1',
    'browser_protection_stop_selftest.ps1'
)

$checks = @()
foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $Root $script
    $log = Join-Path $ArtifactDir ("gate_" + ($script -replace '[^a-zA-Z0-9_.-]', '_') + ".log")
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath *> $log
    $exit = $LASTEXITCODE
    $checks += [pscustomobject]@{ name = $script; exit_code = $exit; ok = ($exit -eq 0); log = $log }
}

if (-not (Test-Path $VerifierResult)) {
    & (Join-Path $Root 'v6_8_0_browser_form_workflow_verifier.ps1') | Out-Null
}
$verifierOk = $false
if (Test-Path $VerifierResult) {
    $verifier = Get-Content -Raw -LiteralPath $VerifierResult | ConvertFrom-Json
    $verifierOk = $verifier.verification_ok -eq $true
}
$checks += [pscustomobject]@{ name = 'browser_form_workflow_verifier'; exit_code = if ($verifierOk) { 0 } else { 1 }; ok = $verifierOk }

$ok = @($checks | Where-Object { -not $_.ok }).Count -eq 0
$gate = [pscustomobject]@{
    schema_version = '6.8.0.browser_form_workflow.acceptance_gate'
    gate_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    checks = $checks
    no_raw_completed_unverified_as_pass = $true
    runner_only_workflow_logic_allowed = $false
    dom_js_webdriver_cdp_allowed = $false
    fake_form_execution_allowed = $false
}
$gate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $GateResult -Encoding UTF8

$lines = @('# v6.8.0 Browser/Form Workflow Acceptance Gate','')
$lines += "- gate_ok: $ok"
foreach ($c in $checks) { $lines += "- $($c.name): ok=$($c.ok) exit=$($c.exit_code)" }
$lines | Set-Content -LiteralPath $GateReport -Encoding UTF8

if ($ok) {
    'v6_8_0_browser_form_workflow_acceptance_gate PASS'
    exit 0
}
'v6_8_0_browser_form_workflow_acceptance_gate BLOCKED'
exit 1
