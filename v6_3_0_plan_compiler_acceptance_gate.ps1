param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.3.0_plan_draft_to_step_contract_compiler'
$VerifierScript = Join-Path $Root 'v6_3_0_plan_compiler_verifier.ps1'
$VerifierJsonPath = Join-Path $ArtifactRoot 'v6_3_0_verifier_report.json'
$RunnerResultPath = Join-Path $ArtifactRoot 'v6_3_0_runner_raw_result.json'
$FullRegressionPath = Join-Path $ArtifactRoot 'full_regression_result.json'
$GateJsonPath = Join-Path $ArtifactRoot 'v6_3_0_acceptance_gate_result.json'
$GateMdPath = Join-Path $ArtifactRoot 'v6_3_0_acceptance_gate_report.md'

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw
}

function Add-Finding {
    param([System.Collections.Generic.List[object]]$Findings, [string]$Code, [string]$Message, [string]$Path = '')
    $Findings.Add([pscustomobject]@{ code = $Code; message = $Message; path = $Path; blocking = $true }) | Out-Null
}

function Regression-Command-Pass($Full, [string]$Name) {
    if (-not $Full -or -not $Full.commands) { return $false }
    $entry = @($Full.commands | Where-Object { $_.name -eq $Name } | Select-Object -Last 1)
    return ($entry -and [int]$entry.exit_code -eq 0 -and [string]$entry.status -eq 'PASS')
}

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierScript -Root $Root > (Join-Path $ArtifactRoot 'v6_3_0_gate_verifier.stdout.txt') 2> (Join-Path $ArtifactRoot 'v6_3_0_gate_verifier.stderr.txt')
$verifierExit = $LASTEXITCODE

$findings = [System.Collections.Generic.List[object]]::new()
$verifier = Read-JsonFile $VerifierJsonPath
$runner = Read-JsonFile $RunnerResultPath
$full = Read-JsonFile $FullRegressionPath
$agents = Read-Text (Join-Path $Root 'AGENTS.md')
$version = (Read-Text (Join-Path $Root 'VERSION')).Trim()
$changelog = Read-Text (Join-Path $Root 'CHANGELOG.md')
$devStatus = Read-Text (Join-Path $Root 'docs\DEVELOPMENT_STATUS.md')

if ($verifierExit -ne 0 -or -not $verifier -or $verifier.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_V6_3_VERIFIER_NOT_PASS' 'v6.3.0 verifier did not PASS.' $VerifierJsonPath
}
if (-not $runner -or $runner.status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding $findings 'BLOCKED_RAW_EVIDENCE_NOT_RAW' 'Runner evidence must remain RAW_COMPLETED_UNVERIFIED.' $RunnerResultPath
}
if ($verifier -and $verifier.no_runner_only_compiler -ne $true) {
    Add-Finding $findings 'BLOCKED_RUNNER_ONLY_COMPILER' 'Verifier did not prove bottom-layer compiler implementation.' $VerifierJsonPath
}
if ($verifier -and $verifier.no_runtime_action_executed -ne $true) {
    Add-Finding $findings 'BLOCKED_DRY_RUN_EXECUTED_RUNTIME' 'Verifier detected Runtime execution in compiler/dry-run path.' $VerifierJsonPath
}
if (-not $full -or $full.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_FULL_REGRESSION_NOT_RUN' 'Full required regression result is missing or not PASS.' $FullRegressionPath
}

$requiredCommands = @(
    'build.ps1',
    'selftest.ps1',
    'runtime_context_guard_selftest.ps1',
    'browser_surface_normalization_selftest.ps1',
    'runtime_session_selftest.ps1',
    'runtime_session_cache_selftest.ps1',
    'runtime_session_latency_benchmark.ps1',
    'plan_compiler_selftest.ps1',
    'step_contract_validator_selftest.ps1',
    'v6_1_2_pre_v6_2_acceptance_gate.ps1',
    'v6_1_3_scroll_acceptance_gate.ps1',
    'v6_1_4_runtime_guard_acceptance_gate.ps1',
    'v6_1_5_safe_context_recovery_acceptance_gate.ps1',
    'v6_1_5a_mouse_first_interaction_acceptance_gate.ps1',
    'v6_1_6_scope_reset_step_completion_acceptance_gate.ps1',
    'v6_2_0_persistent_runtime_acceptance_gate.ps1',
    'v6_3_0_plan_compiler_runner.ps1',
    'v6_3_0_plan_compiler_verifier.ps1'
)
foreach ($cmd in $requiredCommands) {
    if (-not (Regression-Command-Pass $full $cmd)) {
        Add-Finding $findings 'BLOCKED_FULL_REGRESSION_NOT_RUN' "Required command did not PASS: $cmd" $FullRegressionPath
    }
}

$acceptedV630State = (
    $version -eq '6.3.0' -and
    $agents -match 'current_trusted_version\s*[:=]\s*6\.3\.0' -and
    $agents -match 'last_completed_version\s*[:=]\s*6\.3\.0' -and
    $agents -match 'last_completed_status\s*[:=]\s*pass' -and
    $agents -match 'ready_for_next_version\s*[:=]\s*true' -and
    $agents -match 'next_planned_version\s*[:=]\s*6\.4\.0'
)
$acceptedV640State = (
    $version -eq '6.4.0' -and
    $agents -match 'current_trusted_version\s*[:=]\s*6\.4\.0' -and
    $agents -match 'last_completed_version\s*[:=]\s*6\.4\.0' -and
    $agents -match 'last_completed_status\s*[:=]\s*pass' -and
    $agents -match 'ready_for_next_version\s*[:=]\s*true' -and
    $agents -match 'next_planned_version\s*[:=]\s*6\.5\.0'
)
$acceptedV650State = (
    $version -eq '6.5.0' -and
    $agents -match 'current_trusted_version\s*[:=]\s*6\.5\.0' -and
    $agents -match 'last_completed_version\s*[:=]\s*6\.5\.0' -and
    $agents -match 'last_completed_status\s*[:=]\s*pass' -and
    $agents -match 'ready_for_next_version\s*[:=]\s*true' -and
    $agents -match 'next_planned_version\s*[:=]\s*6\.6\.0'
)
$acceptedV660State = (
    $version -eq '6.6.0' -and
    $agents -match 'current_trusted_version\s*[:=]\s*6\.6\.0' -and
    $agents -match 'last_completed_version\s*[:=]\s*6\.6\.0' -and
    $agents -match 'last_completed_status\s*[:=]\s*pass' -and
    $agents -match 'ready_for_next_version\s*[:=]\s*true' -and
    $agents -match 'next_planned_version\s*[:=]\s*6\.7\.0'
)
$blockedV670RerunState = (
    $version -eq '6.6.0' -and
    $agents -match 'current_trusted_version\s*[:=]\s*6\.6\.0' -and
    $agents -match 'last_completed_version\s*[:=]\s*6\.6\.0' -and
    $agents -match 'last_completed_status\s*[:=]\s*blocked' -and
    $agents -match 'ready_for_next_version\s*[:=]\s*false' -and
    $agents -match 'next_planned_version\s*[:=]\s*6\.7\.0-rerun'
)
$acceptedV670State = (
    $version -eq '6.7.0' -and
    $agents -match 'current_trusted_version\s*[:=]\s*6\.7\.0' -and
    $agents -match 'last_completed_version\s*[:=]\s*6\.7\.0' -and
    $agents -match 'last_completed_status\s*[:=]\s*pass' -and
    $agents -match 'ready_for_next_version\s*[:=]\s*true' -and
    $agents -match 'next_planned_version\s*[:=]\s*6\.8\.0'
)
if (-not ($acceptedV630State -or $acceptedV640State -or $acceptedV650State -or $acceptedV660State -or $blockedV670RerunState -or $acceptedV670State)) {
    Add-Finding $findings 'BLOCKED_VERSION_STATE_INCONSISTENT' "VERSION/AGENTS state is '$version', expected accepted v6.3.0 or a later accepted version through v6.7.0, or v6.7.0-rerun blocked with v6.6.0 trusted." (Join-Path $Root 'VERSION')
}
if ($changelog -notmatch 'v6\.3\.0' -or $devStatus -notmatch 'v6\.3\.0') {
    Add-Finding $findings 'BLOCKED_DEVELOPMENT_DOCS_INCONSISTENT' 'CHANGELOG.md or DEVELOPMENT_STATUS.md does not document v6.3.0.' ''
}

$accepted = $findings.Count -eq 0
$result = [ordered]@{
    schema_version = 'v6.3.0.plan_compiler.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = if ($accepted) { 'PASS' } else { 'BLOCKED' }
    accepted = [bool]$accepted
    conclusion = if ($accepted) { 'v6.3.0 accepted' } else { 'v6.3.0 blocked' }
    current_version_file = $version
    verifier_status = if ($verifier) { $verifier.status } else { 'MISSING' }
    runner_status = if ($runner) { $runner.status } else { 'MISSING' }
    full_regression_status = if ($full) { $full.status } else { 'MISSING' }
    rc_check_status = if ($full -and $full.rc_check) { $full.rc_check.status } else { 'NOT_RUN' }
    v6_4_allowed = [bool]$accepted
    v6_3_1_allowed = $false
    findings = @($findings.ToArray())
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $GateJsonPath -Encoding UTF8

$findingLines = @($findings.ToArray()) | ForEach-Object { "- $($_.code): $($_.message) $($_.path)" }
if ($findingLines.Count -eq 0) { $findingLines = @('- No blocking findings.') }
@(
    '# v6.3.0 Plan Compiler Acceptance Gate Report',
    '',
    "- Status: $($result.status)",
    "- Accepted: $($result.accepted)",
    "- Conclusion: $($result.conclusion)",
    "- VERSION: $version",
    "- Verifier: $($result.verifier_status)",
    "- Runner: $($result.runner_status)",
    "- Full regression: $($result.full_regression_status)",
    "- rc_check: $($result.rc_check_status)",
    "- v6.4 allowed: $($result.v6_4_allowed)",
    "- v6.3.1 allowed: $($result.v6_3_1_allowed)",
    '',
    '## Findings'
) + $findingLines | Set-Content -LiteralPath $GateMdPath -Encoding UTF8

if (-not $accepted) {
    throw (($findings | ForEach-Object { $_.code }) -join '; ')
}

Write-Output 'V6_3_0_ACCEPTANCE_GATE_PASS'
