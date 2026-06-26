param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling'

$RunnerPath = Join-Path $EvidenceRoot 'v6_6_0_runner_raw_result.json'
$VerifierPath = Join-Path $EvidenceRoot 'v6_6_0_verifier_report.json'
$FullRegressionPath = Join-Path $EvidenceRoot 'full_regression_result.json'
$GateResultPath = Join-Path $EvidenceRoot 'v6_6_0_acceptance_gate_result.json'
$GateReportPath = Join-Path $EvidenceRoot 'v6_6_0_acceptance_gate_report.md'

$findings = New-Object System.Collections.Generic.List[string]

function Add-Finding($Message) { $findings.Add($Message) | Out-Null }

function Read-JsonOrNull($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Require-ReportPass($Path, $Name) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding "$Name report missing"
        return
    }
    $text = Get-Content -LiteralPath $Path -Raw
    if ($text -notmatch '(Result|Status):\s*PASS') {
        Add-Finding "$Name report does not contain PASS status"
    }
}

function Require-CommandPass($Full, $Name) {
    if (-not $Full) { return }
    $match = @($Full.commands | Where-Object { $_.name -eq $Name })
    if ($match.Count -eq 0) {
        Add-Finding "full regression missing $Name"
    } elseif ($match[0].status -ne 'PASS') {
        Add-Finding "full regression $Name was $($match[0].status)"
    }
}

$runner = Read-JsonOrNull $RunnerPath
if (-not $runner) {
    Add-Finding 'runner raw result missing'
} else {
    if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { Add-Finding 'runner status was not RAW_COMPLETED_UNVERIFIED' }
    if ($runner.result_is_pass -ne $false) { Add-Finding 'runner attempted to count RAW_COMPLETED_UNVERIFIED as PASS' }
    if ($runner.runner_only_vlm_candidate_bridge -ne $false) { Add-Finding 'runner_only_vlm_candidate_bridge was not false' }
}

$verifier = Read-JsonOrNull $VerifierPath
if (-not $verifier) {
    Add-Finding 'verifier_report missing'
} else {
    if ($verifier.status -ne 'PASS') { Add-Finding "verifier did not PASS: $($verifier.status)" }
    if ($verifier.direct_action_allowed -ne $false) { Add-Finding 'verifier direct_action_allowed not false' }
    if ($verifier.coordinate_action_allowed -ne $false) { Add-Finding 'verifier coordinate_action_allowed not false' }
    if ($verifier.runner_only_vlm_candidate_bridge -ne $false) { Add-Finding 'verifier detected runner-only candidate bridge' }
    if ($verifier.raw_completed_unverified_counted_as_pass -ne $false) { Add-Finding 'verifier counted raw output as PASS' }
}

Require-ReportPass (Join-Path $EvidenceRoot 'vlm_candidate_bridge_design.md') 'VLM candidate bridge'
Require-ReportPass (Join-Path $EvidenceRoot 'runtime_candidate_validator_report.md') 'RuntimeCandidateValidator'
Require-ReportPass (Join-Path $EvidenceRoot 'locator_candidate_conversion_report.md') 'LocatorCandidate conversion'
Require-ReportPass (Join-Path $EvidenceRoot 'local_safe_action_report.md') 'local-safe action'
Require-ReportPass (Join-Path $EvidenceRoot 'positive_candidate_cases_report.md') 'positive candidate cases'
Require-ReportPass (Join-Path $EvidenceRoot 'negative_candidate_cases_report.md') 'negative candidate cases'

foreach ($requiredSource in @(
    'src\winagent\VLMCandidateBridge.cpp',
    'src\winagent\RuntimeCandidateValidator.cpp',
    'src\winagent\LocatorCandidate.cpp',
    'src\winagent\MockVLMProvider.cpp',
    'src\winagent\WinAgent.cpp'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $requiredSource))) {
        Add-Finding "bottom-layer implementation missing: $requiredSource"
    }
}

$bridgeSource = if (Test-Path -LiteralPath (Join-Path $Root 'src\winagent\VLMCandidateBridge.cpp')) { Get-Content -LiteralPath (Join-Path $Root 'src\winagent\VLMCandidateBridge.cpp') -Raw } else { '' }
$validatorSource = if (Test-Path -LiteralPath (Join-Path $Root 'src\winagent\RuntimeCandidateValidator.cpp')) { Get-Content -LiteralPath (Join-Path $Root 'src\winagent\RuntimeCandidateValidator.cpp') -Raw } else { '' }
$winAgentSource = if (Test-Path -LiteralPath (Join-Path $Root 'src\winagent\WinAgent.cpp')) { Get-Content -LiteralPath (Join-Path $Root 'src\winagent\WinAgent.cpp') -Raw } else { '' }
if ($bridgeSource -notmatch 'ValidateVLMObservationResultJson') { Add-Finding 'VLM result is not validated before candidate validation' }
if ($bridgeSource -notmatch 'ValidateRuntimeCandidatesFromJson') { Add-Finding 'RuntimeCandidateValidator is not invoked by bridge' }
if ($bridgeSource -match 'ClickClientPoint|DoubleClickClientPoint|RightClickClientPoint|SendInput|TypeText|ScrollClientPoint') { Add-Finding 'VLM candidate bridge appears to execute actions' }
if ($validatorSource -notmatch 'CANDIDATE_DIRECT_COORDINATE_FORBIDDEN') { Add-Finding 'direct coordinate rejection missing' }
if ($winAgentSource -notmatch 'EvaluateRuntimeContextGuard') { Add-Finding 'local-safe VLM action path does not use RuntimeContextGuard' }

$full = Read-JsonOrNull $FullRegressionPath
if (-not $full) {
    Add-Finding 'full_regression_result missing'
} else {
    if ($full.status -ne 'PASS' -and $full.status -ne 'PASS_PENDING_GATE') { Add-Finding "full regression was $($full.status)" }
    foreach ($name in @(
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
        'vlm_candidate_bridge_selftest',
        'runtime_candidate_validator_selftest',
        'vlm_locator_candidate_selftest',
        'vlm_assisted_local_safe_action_selftest',
        'v6_1_2_pre_v6_2_acceptance_gate',
        'v6_1_3_scroll_acceptance_gate',
        'v6_1_4_runtime_guard_acceptance_gate',
        'v6_1_5_safe_context_recovery_acceptance_gate',
        'v6_1_5a_mouse_first_interaction_acceptance_gate',
        'v6_1_6_scope_reset_step_completion_acceptance_gate',
        'v6_2_0_persistent_runtime_acceptance_gate',
        'v6_3_0_plan_compiler_acceptance_gate',
        'v6_4_0_runtime_task_execution_acceptance_gate',
        'v6_5_0_vlm_observation_acceptance_gate',
        'v6_6_0_vlm_candidate_runner',
        'v6_6_0_vlm_candidate_verifier'
    )) {
        Require-CommandPass $full $name
    }
}

$agents = Get-Content -LiteralPath (Join-Path $Root 'AGENTS.md') -Raw
$version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$changelog = Get-Content -LiteralPath (Join-Path $Root 'CHANGELOG.md') -Raw
$devStatus = Get-Content -LiteralPath (Join-Path $Root 'docs\DEVELOPMENT_STATUS.md') -Raw
$roadmap = Get-Content -LiteralPath (Join-Path $Root 'docs\ROADMAP.md') -Raw
$architecture = Get-Content -LiteralPath (Join-Path $Root 'docs\ARCHITECTURE.md') -Raw
$knownLimitations = Get-Content -LiteralPath (Join-Path $Root 'docs\KNOWN_LIMITATIONS.md') -Raw
$commandProtocol = Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw

$acceptedV670State = (
    $version -eq '6.7.0' -and
    $agents -match 'current_trusted_version:\s*6\.7\.0' -and
    $agents -match 'last_completed_version:\s*6\.7\.0' -and
    $agents -match 'last_completed_status:\s*pass' -and
    $agents -match 'ready_for_next_version:\s*true' -and
    $agents -match 'next_planned_version:\s*6\.8\.0'
)
if ($version -ne '6.6.0' -and -not $acceptedV670State) { Add-Finding "VERSION is $version, expected 6.6.0 or accepted 6.7.0" }
if (($agents -notmatch 'current_trusted_version:\s*6\.6\.0') -and -not $acceptedV670State) { Add-Finding 'AGENTS current_trusted_version not 6.6.0 or accepted 6.7.0' }
if (($agents -notmatch 'last_completed_version:\s*6\.6\.0') -and -not $acceptedV670State) { Add-Finding 'AGENTS last_completed_version not 6.6.0 or accepted 6.7.0' }
$acceptedV660State = (
    $agents -match 'last_completed_status:\s*pass' -and
    $agents -match 'ready_for_next_version:\s*true' -and
    $agents -match 'next_planned_version:\s*6\.7\.0'
)
$blockedV670RerunState = (
    $agents -match 'last_completed_status:\s*blocked' -and
    $agents -match 'ready_for_next_version:\s*false' -and
    $agents -match 'next_planned_version:\s*6\.7\.0-rerun'
)
if (-not ($acceptedV660State -or $blockedV670RerunState -or $acceptedV670State)) {
    Add-Finding 'AGENTS state is not accepted v6.6.0, blocked v6.7.0-rerun with v6.6.0 trusted, or accepted v6.7.0'
}
if ($agents -notmatch 'Explorer Agent Workflows') { Add-Finding 'AGENTS missing v6.7.0 Explorer Agent Workflows' }
if ($changelog -notmatch 'v6\.6\.0') { Add-Finding 'CHANGELOG missing v6.6.0' }
if (($devStatus -notmatch 'current_trusted_version:\s*6\.6\.0') -and ($devStatus -notmatch 'current_trusted_version:\s*6\.7\.0')) { Add-Finding 'DEVELOPMENT_STATUS current trusted version not 6.6.0 or 6.7.0' }
if ($roadmap -notmatch 'Explorer Agent Workflows') { Add-Finding 'ROADMAP missing v6.7.0 Explorer Agent Workflows' }
if ($architecture -notmatch 'VLM-Assisted Unknown UI Candidate Handling') { Add-Finding 'ARCHITECTURE missing v6.6.0 candidate handling' }
if ($knownLimitations -notmatch 'v6\.6\.0') { Add-Finding 'KNOWN_LIMITATIONS missing v6.6.0' }
foreach ($command in @('vlm-assisted-locate','vlm-assisted-locate-dry-run','vlm-assisted-locate-and-click-local-safe')) {
    if ($commandProtocol -notmatch [regex]::Escape($command)) { Add-Finding "COMMAND_PROTOCOL missing $command" }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$reportedFullRegressionStatus = if ($status -eq 'PASS' -and $full -and $full.status -eq 'PASS_PENDING_GATE') { 'PASS' } elseif ($full) { $full.status } else { 'missing' }
$result = [ordered]@{
    schema_version = '6.6.0.vlm_candidate.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    accepted = ($status -eq 'PASS')
    conclusion = if ($status -eq 'PASS') { 'v6.6.0 accepted' } else { 'v6.6.0 blocked' }
    verifier_status = if ($verifier) { $verifier.status } else { 'missing' }
    full_regression_status = $reportedFullRegressionStatus
    rc_check_status = if ($full -and $full.rc_check) { $full.rc_check.status } else { 'not_run' }
    v6_7_allowed = ($status -eq 'PASS')
    v6_6_1_allowed = $false
    direct_action_allowed = $false
    coordinate_action_allowed = $false
    runner_only_vlm_candidate_bridge = $false
    findings = @($findings)
}
$result | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $GateResultPath -Encoding UTF8

if ($full) {
    $commands = @($full.commands | Where-Object { $_.name -ne 'v6_6_0_vlm_candidate_acceptance_gate' })
    $commands += [pscustomobject]@{
        name = 'v6_6_0_vlm_candidate_acceptance_gate'
        command = '.\v6_6_0_vlm_candidate_acceptance_gate.ps1'
        status = $status
        exit_code = if ($status -eq 'PASS') { 0 } else { 1 }
        duration_ms = 0
    }
    $fullOut = [ordered]@{
        schema_version = $full.schema_version
        generated_at = $full.generated_at
        status = if ($status -eq 'PASS' -and $full.status -eq 'PASS_PENDING_GATE') { 'PASS' } else { $full.status }
        commands = $commands
        optional_commands = $full.optional_commands
        rc_check = $full.rc_check
    }
    $fullOut | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $FullRegressionPath -Encoding UTF8
}

$lines = @('# v6.6.0 Acceptance Gate Report','')
$lines += "- Status: $status"
$lines += "- Accepted: $($status -eq 'PASS')"
$lines += "- Verifier: $($result.verifier_status)"
$lines += "- Full regression: $($result.full_regression_status)"
$lines += "- rc_check: $($result.rc_check_status)"
$lines += "- v6.7.0 allowed: $($status -eq 'PASS')"
$lines += "- v6.6.1 allowed: false"
$lines += "- Direct action allowed: false"
$lines += "- Coordinate action allowed: false"
$lines += "- Runner-only VLM candidate bridge: false"
if ($findings.Count -gt 0) {
    $lines += ''
    $lines += '## Findings'
    foreach ($finding in $findings) { $lines += "- $finding" }
}
[System.IO.File]::WriteAllLines($GateReportPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))

if ($status -ne 'PASS') {
    'V6_6_0_ACCEPTANCE_GATE_BLOCKED'
    $findings
    exit 1
}

'V6_6_0_ACCEPTANCE_GATE_PASS'
