param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5_safe_context_recovery_dynamic_diagnostics'
$RawRoot = Join-Path $ArtifactRoot 'raw\dynamic_diagnostics'
$VerifiedDynamicRoot = Join-Path $ArtifactRoot 'verified\dynamic_diagnostics'
$VerifiedSafeRoot = Join-Path $ArtifactRoot 'verified\safe_context_recovery'

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$matrixPath = Join-Path $RawRoot 'dynamic_diagnostics_raw_matrix.json'
$matrix = Read-Json $matrixPath
$dynamicVerifierPath = Join-Path $VerifiedDynamicRoot 'dynamic_diagnostics_verifier_result.json'
$dynamicVerifier = Read-Json $dynamicVerifierPath
$safeGatePath = Join-Path $VerifiedSafeRoot 'safe_context_recovery_acceptance_gate_result.json'
$safeGate = Read-Json $safeGatePath
$testMatrixPath = Join-Path $ArtifactRoot 'verified\test_matrix_result.json'
$testMatrix = Read-Json $testMatrixPath

$records = @()
if ($matrix -and $matrix.diagnostic_records) { $records = @($matrix.diagnostic_records) }
$tableRows = @($records) | ForEach-Object {
    '| {0} | {1} | {2} | {3} | {4} | {5} |' -f $_.case_id, $_.diagnostic_category, $_.target_name, $_.final_stop_code, $_.failure_attribution, $_.action_executed
}
$reportLines = @(
    '# v6.1.5 Dynamic Diagnostics Report',
    '',
    "- Runner status: $($matrix.runner_status)",
    "- Verifier status: $($dynamicVerifier.status)",
    "- Attempted categories: $($dynamicVerifier.attempted_categories -join ', ')",
    "- Developer FULL_ACCESS diagnostics: true",
    "- CDP check status: $($matrix.cdp_check_status)",
    '',
    '| case | category | target | final_stop_code | failure_attribution | action_executed |',
    '|---|---|---|---|---|---|'
) + @($tableRows)
$reportLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'dynamic_diagnostics_report.md') -Encoding UTF8

$failureRows = @($records) | ForEach-Object {
    '| {0} | {1} | {2} | active={3}; credential={4} |' -f $_.case_id, $_.final_stop_code, $_.failure_attribution, $_.active_protection_detected, $_.credential_required_detected
}
@(
    '# v6.1.5 Failure Attribution Report',
    '',
    '- Every diagnostic record includes failure_attribution.',
    '- NO_FAILURE is used only for completed diagnostics with no blocking failure.',
    '',
    '| case | final_stop_code | failure_attribution | detection flags |',
    '|---|---|---|---|'
) + @($failureRows) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'failure_attribution_report.md') -Encoding UTF8

$safeStatus = if ($safeGate) { [string]$safeGate.status } else { 'MISSING' }
$dynamicStatus = if ($dynamicVerifier) { [string]$dynamicVerifier.status } else { 'MISSING' }
$testStatus = if ($testMatrix) { [string]$testMatrix.status } else { 'PENDING_FULL_TEST_MATRIX' }
$overallStatus = if ($safeStatus -eq 'PASS' -and $dynamicStatus -eq 'PASS' -and ($testStatus -eq 'PASS' -or $testStatus -eq 'PENDING_FULL_TEST_MATRIX')) { 'PENDING_FULL_TEST_MATRIX' } else { 'BLOCKED' }
if ($safeStatus -eq 'PASS' -and $dynamicStatus -eq 'PASS' -and $testStatus -eq 'PASS') { $overallStatus = 'PASS' }

@(
    '# v6.1.5 Acceptance Gate Report',
    '',
    "- Overall status: $overallStatus",
    "- Safe context recovery gate: $safeStatus",
    "- Dynamic diagnostics verifier: $dynamicStatus",
    "- Required test matrix: $testStatus",
    "- v6.1.6 allowed if overall status PASS: true",
    '- v6.2 allowed: false',
    '',
    'v6.1.5 is Safe Recovery + Dynamic Diagnostics only. Full Dynamic App/Web Developer FULL_ACCESS Automation RC remains reserved for v6.1.6.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'v6_1_5_acceptance_gate_report.md') -Encoding UTF8

Write-Host "v6.1.5 dynamic diagnostics report generated: $(Join-Path $ArtifactRoot 'dynamic_diagnostics_report.md')"
exit 0
