param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
if (Test-Path -LiteralPath $Resolver) {
    $Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
} elseif ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = $PSScriptRoot
}

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_scope_reset_step_completion_closure'
$VerifierResultPath = Join-Path $ArtifactRoot 'scope_reset_verifier_result.json'
$OutputClosurePath = Join-Path $ArtifactRoot 'case2_output_capture_closure.json'
$Content1FinalPath = Join-Path $ArtifactRoot 'content1_final_status_report.md'
$StepSelftestPath = Join-Path $ArtifactRoot 'step_completion_gate_selftest_report.md'
$Case1ReportPath = Join-Path $ArtifactRoot 'case1_valid_pass_freeze_report.md'
$SupersededReportPath = Join-Path $ArtifactRoot 'superseded_v6_1_6_steps_report.md'
$ResultPath = Join-Path $ArtifactRoot 'scope_reset_gate_result.json'
$ReportPath = Join-Path $ArtifactRoot 'scope_reset_gate_report.md'
$FinalGateReportPath = Join-Path $ArtifactRoot 'v6_1_6_scope_reset_acceptance_gate_report.md'

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Read-TextOrEmpty {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -Raw -LiteralPath $Path
}

function Add-Finding {
    param([System.Collections.Generic.List[string]]$Findings, [string]$Code)
    if (-not $Findings.Contains($Code)) { $Findings.Add($Code) | Out-Null }
}

$findings = [System.Collections.Generic.List[string]]::new()

$verifier = Read-JsonFile $VerifierResultPath
$closure = Read-JsonFile $OutputClosurePath
$version = (Read-TextOrEmpty (Join-Path $Root 'VERSION')).Trim()
$content1Final = Read-TextOrEmpty $Content1FinalPath
$stepSelftest = Read-TextOrEmpty $StepSelftestPath
$case1Report = Read-TextOrEmpty $Case1ReportPath

if ($null -eq $verifier -or [string]$verifier.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_SCOPE_RESET_VERIFIER_NOT_PASS'
}
if ($verifier -and $verifier.case1_valid_frozen -ne $true) {
    Add-Finding $findings 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY'
}
if ($verifier -and $verifier.case2_pass -ne $true) {
    Add-Finding $findings 'BLOCKED_CASE2_VERIFIER_NOT_PASS'
}
if ($verifier -and $verifier.step_completion_gate_bottom_layer -ne $true) {
    Add-Finding $findings 'BLOCKED_RUNNER_ONLY_STEP_COMPLETION_GATE'
}
if ($verifier -and $verifier.execution_outcome_classifier_bottom_layer -ne $true) {
    Add-Finding $findings 'BLOCKED_RUNNER_ONLY_EXECUTION_CLASSIFIER'
}
if ($verifier -and $verifier.all_step_completion_gate_results_next_step_allowed -ne $true) {
    Add-Finding $findings 'BLOCKED_STEP_COMPLETION_GATE_MISSING'
}

if ($null -eq $closure -or [string]$closure.status -ne 'OUTPUT_EVIDENCE_CLOSED') {
    Add-Finding $findings 'BLOCKED_CASE2_OUTPUT_CAPTURE_EVIDENCE_INCOMPLETE'
} else {
    if ($closure.screenshot_exists -ne $true -or $closure.screenshot_verified_pycharm_foreground -ne $true -or $closure.screenshot_bottom_run_region_visible -ne $true) {
        Add-Finding $findings 'BLOCKED_CASE2_VISIBLE_SCREEN_EVIDENCE_INCOMPLETE'
    }
    if ($closure.paired_text_contains_dv616_seq -ne $true -or $closure.paired_text_contains_dv616_run_end -ne $true -or $closure.paired_text_contains_exit_code_zero -ne $true) {
        Add-Finding $findings 'BLOCKED_CASE2_OUTPUT_CAPTURE_EVIDENCE_INCOMPLETE'
    }
    if ($closure.current_run_verified -ne $true -or $closure.old_output_reuse_detected -ne $false) {
        Add-Finding $findings 'BLOCKED_STALE_EVIDENCE_USED'
    }
    if ($closure.output_count_between_2_and_10 -ne $true -or [int]$closure.exit_code -ne 0) {
        Add-Finding $findings 'BLOCKED_CASE2_OUTPUT_SEQUENCE_NOT_VERIFIED'
    }
}

if ($content1Final -notmatch 'STEP_COMPLETION_GATE_PASS_READY_FOR_CASE2') {
    Add-Finding $findings 'BLOCKED_STEP_COMPLETION_GATE_NOT_READY'
}
if ($stepSelftest -notmatch 'Status:\s*PASS') {
    Add-Finding $findings 'BLOCKED_STEP_COMPLETION_GATE_SELFTEST_FAILED'
}
if ($case1Report -notmatch 'Status:\s*PASS') {
    Add-Finding $findings 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY'
}
if (-not (Test-Path -LiteralPath $SupersededReportPath)) {
    Add-Finding $findings 'BLOCKED_SUPERSEDED_STEPS_REPORT_MISSING'
}
if ($version -ne '6.1.5a' -and $version -ne '6.1.6' -and $version -ne '6.2.0' -and $version -ne '6.3.0' -and $version -ne '6.4.0' -and $version -ne '6.5.0' -and $version -ne '6.6.0' -and $version -ne '6.7.0') {
    Add-Finding $findings "BLOCKED_VERSION_STATE_UNEXPECTED:$version"
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$conclusion = if ($status -eq 'PASS' -and ($version -eq '6.1.6' -or $version -eq '6.2.0' -or $version -eq '6.3.0' -or $version -eq '6.4.0' -or $version -eq '6.5.0' -or $version -eq '6.6.0' -or $version -eq '6.7.0')) {
    'V6_1_6_ACCEPTED'
} elseif ($status -eq 'PASS') {
    'V6_1_6_ACCEPTED_READY_TO_PROMOTE'
} else {
    'BLOCKED'
}

$result = [ordered]@{
    schema_version = 'v6.1.6.scope_reset_step_completion_acceptance_gate.final'
    generated_at = (Get-Date).ToString('o')
    status = $status
    conclusion = $conclusion
    current_version_file = $version
    case1_valid_frozen = if ($verifier) { [bool]$verifier.case1_valid_frozen } else { $false }
    step_completion_gate_bottom_layer = if ($verifier) { [bool]$verifier.step_completion_gate_bottom_layer } else { $false }
    case2_pass = if ($verifier) { [bool]$verifier.case2_pass } else { $false }
    case2_output_capture_closed = ($closure -and [string]$closure.status -eq 'OUTPUT_EVIDENCE_CLOSED')
    case2_output_capture_method = if ($closure) { [string]$closure.screenshot_capture_method } else { '' }
    case2_paired_text_provenance = if ($closure) { [string]$closure.paired_text_provenance } else { '' }
    case3_case4_deferred = $true
    old_integrated_sequence_deferred = $true
    v6_2_allowed = ($status -eq 'PASS')
    findings = @($findings.ToArray())
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# v6.1.6 Scope Reset Acceptance Gate Report') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- Status: $status") | Out-Null
$lines.Add("- Conclusion: $conclusion") | Out-Null
$lines.Add("- VERSION file: $version") | Out-Null
$lines.Add("- Case1 valid frozen: $($result.case1_valid_frozen)") | Out-Null
$lines.Add("- StepCompletionGate bottom-layer: $($result.step_completion_gate_bottom_layer)") | Out-Null
$lines.Add("- Case2 PASS: $($result.case2_pass)") | Out-Null
$lines.Add("- Case2 output capture closed: $($result.case2_output_capture_closed)") | Out-Null
$lines.Add("- PowerShell CopyFromScreen evidence: $($result.case2_output_capture_method)") | Out-Null
$lines.Add("- Paired output text provenance: $($result.case2_paired_text_provenance)") | Out-Null
$lines.Add("- v6.2 allowed after promotion: $($result.v6_2_allowed)") | Out-Null
$lines.Add("- Case3/Case4: deferred, not current gate blockers") | Out-Null
$lines.Add("- Old integrated sequence: deferred/not active") | Out-Null
if ($findings.Count -gt 0) {
    $lines.Add('') | Out-Null
    $lines.Add('## Findings') | Out-Null
    foreach ($finding in @($findings.ToArray())) { $lines.Add("- $finding") | Out-Null }
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8
$lines | Set-Content -LiteralPath $FinalGateReportPath -Encoding UTF8

if ($status -ne 'PASS') {
    throw ($findings -join '; ')
}

Write-Output $conclusion
