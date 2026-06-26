param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.5.0_vlm_assisted_observation_contract'

$VerifierPath = Join-Path $EvidenceRoot 'v6_5_0_verifier_report.json'
$FullRegressionPath = Join-Path $EvidenceRoot 'full_regression_result.json'
$RunnerPath = Join-Path $EvidenceRoot 'v6_5_0_runner_raw_result.json'

$findings = New-Object System.Collections.Generic.List[string]

function Add-Finding($Message) {
    $findings.Add($Message) | Out-Null
}

function Read-JsonOrNull($Path) {
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content -Raw $Path | ConvertFrom-Json } catch { return $null }
}

function Require-ReportPass($Path, $Name) {
    if (-not (Test-Path $Path)) {
        Add-Finding "$Name report missing"
        return
    }
    $text = Get-Content -Raw $Path
    if ($text -notmatch 'Result:\s*PASS') {
        Add-Finding "$Name report does not contain Result: PASS"
    }
}

$runner = Read-JsonOrNull $RunnerPath
if (-not $runner) {
    Add-Finding 'runner raw result missing'
} else {
    if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { Add-Finding 'runner status was not RAW_COMPLETED_UNVERIFIED' }
    if ($runner.result_is_pass -ne $false) { Add-Finding 'runner attempted to count RAW_COMPLETED_UNVERIFIED as PASS' }
    if ($runner.runtime_executed -ne $false) { Add-Finding 'runner runtime_executed was true' }
}

$verifier = Read-JsonOrNull $VerifierPath
if (-not $verifier) {
    Add-Finding 'verifier_report missing'
} else {
    if ($verifier.status -ne 'PASS') { Add-Finding "verifier did not PASS: $($verifier.status)" }
    if ($verifier.runtime_executed -ne $false) { Add-Finding 'verifier runtime_executed not false' }
    if ($verifier.direct_action_allowed -ne $false) { Add-Finding 'verifier direct_action_allowed not false' }
    if ($verifier.coordinate_action_allowed -ne $false) { Add-Finding 'verifier coordinate_action_allowed not false' }
    if ($verifier.runner_only_vlm_contract -ne $false) { Add-Finding 'verifier detected runner-only VLM contract' }
}

Require-ReportPass (Join-Path $EvidenceRoot 'vlm_observation_contract_schema.md') 'contract schema'
Require-ReportPass (Join-Path $EvidenceRoot 'mock_provider_report.md') 'mock provider'
Require-ReportPass (Join-Path $EvidenceRoot 'vlm_output_validator_report.md') 'validator'
Require-ReportPass (Join-Path $EvidenceRoot 'assistive_only_boundary_report.md') 'boundary'

foreach ($requiredSource in @(
    'src\winagent\VLMObservationContract.cpp',
    'src\winagent\VLMProvider.cpp',
    'src\winagent\MockVLMProvider.cpp',
    'src\winagent\VLMObservationValidator.cpp',
    'src\winagent\VLMObservationBoundary.cpp'
)) {
    if (-not (Test-Path (Join-Path $Root $requiredSource))) {
        Add-Finding "bottom-layer implementation missing: $requiredSource"
    }
}

$full = Read-JsonOrNull $FullRegressionPath
if (-not $full) {
    Add-Finding 'full_regression_result missing'
} else {
    if ($full.status -ne 'PASS') { Add-Finding "full regression was $($full.status)" }
    $requiredCommands = @(
        'build',
        'selftest',
        'runtime_context_guard_selftest',
        'browser_surface_normalization_selftest',
        'runtime_session_selftest',
        'runtime_session_cache_selftest',
        'runtime_session_latency_benchmark',
        'plan_compiler_selftest',
        'step_contract_validator_selftest',
        'compiled_plan_executor_selftest',
        'step_execution_verifier_selftest',
        'execution_evidence_pack_selftest',
        'vlm_observation_contract_selftest',
        'mock_vlm_provider_selftest',
        'vlm_observation_validator_selftest',
        'vlm_observation_boundary_selftest',
        'v6_1_2_pre_v6_2_acceptance_gate',
        'v6_1_3_scroll_acceptance_gate',
        'v6_1_4_runtime_guard_acceptance_gate',
        'v6_1_5_safe_context_recovery_acceptance_gate',
        'v6_1_5a_mouse_first_interaction_acceptance_gate',
        'v6_1_6_scope_reset_step_completion_acceptance_gate',
        'v6_2_0_persistent_runtime_acceptance_gate',
        'v6_3_0_plan_compiler_acceptance_gate',
        'v6_4_0_runtime_task_execution_acceptance_gate',
        'v6_5_0_vlm_observation_runner',
        'v6_5_0_vlm_observation_verifier'
    )
    foreach ($name in $requiredCommands) {
        $match = @($full.commands | Where-Object { $_.name -eq $name })
        if ($match.Count -eq 0) {
            Add-Finding "full regression missing $name"
        } elseif ($match[0].status -ne 'PASS') {
            Add-Finding "full regression $name was $($match[0].status)"
        }
    }
}

$agents = Get-Content -Raw (Join-Path $Root 'AGENTS.md')
$version = (Get-Content -Raw (Join-Path $Root 'VERSION')).Trim()
$changelog = Get-Content -Raw (Join-Path $Root 'CHANGELOG.md')
$devStatus = Get-Content -Raw (Join-Path $Root 'docs\DEVELOPMENT_STATUS.md')
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
if (-not ($acceptedV650State -or $acceptedV660State -or $blockedV670RerunState -or $acceptedV670State)) {
    Add-Finding "VERSION/AGENTS state is $version, expected accepted 6.5.0, accepted 6.6.0, accepted 6.7.0, or v6.7.0-rerun blocked with v6.6.0 trusted"
}
if ($changelog -notmatch 'v6\.5\.0') { Add-Finding 'CHANGELOG missing v6.5.0' }
if ($devStatus -notmatch 'v6\.5\.0') { Add-Finding 'DEVELOPMENT_STATUS missing v6.5.0' }

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$result = [ordered]@{
    schema_version = '6.5.0.vlm_observation.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    accepted = ($status -eq 'PASS')
    conclusion = if ($status -eq 'PASS') { 'v6.5.0 accepted' } else { 'v6.5.0 blocked' }
    verifier_status = if ($verifier) { $verifier.status } else { 'missing' }
    full_regression_status = if ($full) { $full.status } else { 'missing' }
    rc_check_status = if ($full -and $full.rc_check) { $full.rc_check.status } else { 'not_run' }
    v6_6_allowed = ($status -eq 'PASS')
    v6_5_1_allowed = $false
    findings = @($findings)
}
$result | ConvertTo-Json -Depth 40 | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_5_0_acceptance_gate_result.json')

$lines = @('# v6.5.0 Acceptance Gate Report','')
$lines += "- Status: $status"
$lines += "- Accepted: $($status -eq 'PASS')"
$lines += "- rc_check: $($result.rc_check_status)"
$lines += "- v6.6.0 allowed: $($status -eq 'PASS')"
$lines += "- v6.5.1 allowed: false"
if ($findings.Count -gt 0) {
    $lines += ''
    $lines += '## Findings'
    foreach ($f in $findings) { $lines += "- $f" }
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_5_0_acceptance_gate_report.md')

if ($status -ne 'PASS') {
    'V6_5_0_ACCEPTANCE_GATE_BLOCKED'
    $findings
    exit 1
}

'V6_5_0_ACCEPTANCE_GATE_PASS'

