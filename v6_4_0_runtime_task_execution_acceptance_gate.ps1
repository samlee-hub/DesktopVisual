param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$VerifierPath = Join-Path $EvidenceRoot 'v6_4_0_verifier_report.json'
$FullRegressionPath = Join-Path $EvidenceRoot 'full_regression_result.json'

$findings = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path $VerifierPath)) {
    $findings.Add('verifier_report missing') | Out-Null
} else {
    $verifier = Get-Content -Raw $VerifierPath | ConvertFrom-Json
    if ($verifier.status -ne 'PASS') { $findings.Add('verifier did not PASS') | Out-Null }
}

if (-not (Test-Path $FullRegressionPath)) {
    $findings.Add('full_regression_result missing') | Out-Null
} else {
    $full = Get-Content -Raw $FullRegressionPath | ConvertFrom-Json
    if ($full.status -ne 'PASS') { $findings.Add("full regression was $($full.status)") | Out-Null }
}

$agents = Get-Content -Raw (Join-Path $Root 'AGENTS.md')
$version = (Get-Content -Raw (Join-Path $Root 'VERSION')).Trim()
$acceptedV640State = (
    $version -eq '6.4.0' -and
    $agents -match 'current_trusted_version:\s*6\.4\.0' -and
    $agents -match 'last_completed_version:\s*6\.4\.0' -and
    $agents -match 'last_completed_status:\s*pass' -and
    $agents -match 'next_planned_version:\s*6\.5\.0'
)
$acceptedV650State = (
    $version -eq '6.5.0' -and
    $agents -match 'current_trusted_version:\s*6\.5\.0' -and
    $agents -match 'last_completed_version:\s*6\.5\.0' -and
    $agents -match 'last_completed_status:\s*pass' -and
    $agents -match 'next_planned_version:\s*6\.6\.0'
)
$acceptedV660State = (
    $version -eq '6.6.0' -and
    $agents -match 'current_trusted_version:\s*6\.6\.0' -and
    $agents -match 'last_completed_version:\s*6\.6\.0' -and
    $agents -match 'last_completed_status:\s*pass' -and
    $agents -match 'next_planned_version:\s*6\.7\.0'
)
$blockedV670RerunState = (
    $version -eq '6.6.0' -and
    $agents -match 'current_trusted_version:\s*6\.6\.0' -and
    $agents -match 'last_completed_version:\s*6\.6\.0' -and
    $agents -match 'last_completed_status:\s*blocked' -and
    $agents -match 'ready_for_next_version:\s*false' -and
    $agents -match 'next_planned_version:\s*6\.7\.0-rerun'
)
$acceptedV670State = (
    $version -eq '6.7.0' -and
    $agents -match 'current_trusted_version:\s*6\.7\.0' -and
    $agents -match 'last_completed_version:\s*6\.7\.0' -and
    $agents -match 'last_completed_status:\s*pass' -and
    $agents -match 'ready_for_next_version:\s*true' -and
    $agents -match 'next_planned_version:\s*6\.8\.0'
)
if (-not ($acceptedV640State -or $acceptedV650State -or $acceptedV660State -or $blockedV670RerunState -or $acceptedV670State)) {
    $findings.Add("VERSION/AGENTS state is $version, expected accepted 6.4.0, accepted 6.5.0, accepted 6.6.0, accepted 6.7.0, or v6.7.0-rerun blocked with v6.6.0 trusted") | Out-Null
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$result = [ordered]@{
    schema_version = '6.4.0.runtime_task_execution.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    accepted = ($status -eq 'PASS')
    conclusion = if ($status -eq 'PASS') { 'v6.4.0 accepted' } else { 'v6.4.0 blocked' }
    verifier_status = if ($verifier) { $verifier.status } else { 'missing' }
    full_regression_status = if ($full) { $full.status } else { 'missing' }
    rc_check_status = if ($full -and $full.rc_check) { $full.rc_check.status } else { 'not_run' }
    v6_5_allowed = ($status -eq 'PASS')
    v6_4_1_allowed = $false
    findings = @($findings)
}
$result | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_4_0_acceptance_gate_result.json')

$lines = @('# v6.4.0 Acceptance Gate Report','')
$lines += "- Status: $status"
$lines += "- Accepted: $($status -eq 'PASS')"
$lines += "- rc_check: $($result.rc_check_status)"
if ($findings.Count -gt 0) {
    $lines += ''
    $lines += '## Findings'
    foreach ($f in $findings) { $lines += "- $f" }
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_4_0_acceptance_gate_report.md')

if ($status -ne 'PASS') {
    "V6_4_0_ACCEPTANCE_GATE_BLOCKED"
    $findings
    exit 1
}

"V6_4_0_ACCEPTANCE_GATE_PASS"
