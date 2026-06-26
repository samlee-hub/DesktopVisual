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
$RunnerResultPath = Join-Path $ArtifactRoot 'case2_pycharm_runner_result.json'
$RawEvidencePath = Join-Path $ArtifactRoot 'case2_pycharm_raw_evidence.json'
$StepTracePath = Join-Path $ArtifactRoot 'case2_step_completion_trace.json'
$OutcomePath = Join-Path $ArtifactRoot 'case2_execution_outcome.json'
$GeneratedCodePath = Join-Path $ArtifactRoot 'case2_generated_code.py.txt'
$Case1AuditPath = Join-Path $ArtifactRoot 'case1_content1_precondition_audit.json'
$VerifierResultPath = Join-Path $ArtifactRoot 'scope_reset_verifier_result.json'
$Case2VerifierResultPath = Join-Path $ArtifactRoot 'case2_verifier_result.json'
$ReportPath = Join-Path $ArtifactRoot 'scope_reset_verifier_report.md'
$Case2ReportPath = Join-Path $ArtifactRoot 'case2_pycharm_final_report.md'
$RegistryPath = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc_fresh\case_status_registry.json'

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { return $null }
}

function Read-TextOrEmpty {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -Raw -LiteralPath $Path
}

function Save-Json {
    param($Value, [string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-Finding {
    param([System.Collections.Generic.List[string]]$Findings, [string]$Code)
    if (-not $Findings.Contains($Code)) { $Findings.Add($Code) | Out-Null }
}

function Test-GeneratedCode {
    param([string]$Code, [string]$RunId)
    $classCount = ([regex]::Matches($Code, '(?m)^\s*class\s+\w+')).Count
    $hasAssociation = (
        $Code -match '\.assign\(' -or
        $Code -match 'self\.tasks\.append' -or
        $Code -match '\.items\.append\(' -or
        $Code -match '(?m)^\s*def\s+attach_\w+\s*\('
    )
    return [pscustomobject]@{
        class_count = $classCount
        ok = (
            $classCount -ge 2 -and
            $hasAssociation -and
            $Code -match '(?m)^\s*def\s+\w+' -and
            $Code -match 'random\.randint\(2,\s*10\)' -and
            $Code -match '(?m)^\s*while\s+' -and
            $Code -match [regex]::Escape($RunId) -and
            $Code -match 'DV616_SEQ' -and
            $Code -notmatch '(?m)^\s*import\s+(requests|numpy|pandas|PyQt|tkinter|socket|urllib)' -and
            $Code -notmatch '(open\(|socket|requests|urllib|http)'
        )
    }
}

$findings = [System.Collections.Generic.List[string]]::new()

$runner = Read-JsonFile $RunnerResultPath
$raw = Read-JsonFile $RawEvidencePath
$trace = Read-JsonFile $StepTracePath
$outcome = Read-JsonFile $OutcomePath
$case1 = Read-JsonFile $Case1AuditPath
$code = Read-TextOrEmpty $GeneratedCodePath

if ($null -eq $runner -or [string]$runner.status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding $findings 'BLOCKED_CASE2_RUNNER_NOT_RAW_COMPLETED'
}
if ($null -eq $raw -or [string]$raw.status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding $findings 'BLOCKED_CASE2_RAW_EVIDENCE_MISSING_OR_FAILED'
}
if ($null -eq $case1 -or [string]$case1.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY'
}
if ($null -eq $outcome) {
    Add-Finding $findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED'
}

$codeCheck = if ($raw -and $raw.run_id) { Test-GeneratedCode -Code $code -RunId ([string]$raw.run_id) } else { [pscustomobject]@{ ok = $false; class_count = 0 } }
if (-not $codeCheck.ok) {
    Add-Finding $findings 'BLOCKED_GENERATED_CODE_COMPLEXITY_INVALID'
}

$requiredTrue = @(
    'pycharm_opened',
    'editor_clicked_by_mouse',
    'editor_focus_verified',
    'existing_code_checked',
    'existing_code_cleared_if_present',
    'editor_clean_verified',
    'llm_generated_code_saved',
    'generated_code_medium_complexity_verified',
    'code_text_verified',
    'run_via_keyboard_shortcut',
    'run_triggered',
    'execution_started',
    'execution_completed',
    'execution_success',
    'current_run_verified',
    'run_id_marker_verified',
    'output_sequence_verified',
    'output_count_between_2_and_10'
)
foreach ($key in $requiredTrue) {
    if ($null -eq $raw -or $raw.$key -ne $true) {
        Add-Finding $findings "BLOCKED_CASE2_FIELD_FALSE:$key"
    }
}

if ($raw -and [string]$raw.run_trigger_method -ne 'SHIFT+F10') {
    Add-Finding $findings 'BLOCKED_CASE2_RUN_METHOD_NOT_SHIFT_F10'
}
if ($raw -and [int]$raw.exit_code -ne 0) {
    Add-Finding $findings 'BLOCKED_CASE2_EXIT_CODE_NOT_ZERO'
}
if ($raw -and [int]$raw.wrong_field_input_count -ne 0) {
    Add-Finding $findings 'BLOCKED_CASE2_WRONG_FIELD_INPUT'
}
if ($raw -and $raw.continued_action_after_wrong_context -ne $false) {
    Add-Finding $findings 'BLOCKED_CASE2_CONTINUED_AFTER_WRONG_CONTEXT'
}
if ($raw -and $raw.old_output_reuse_detected -ne $false) {
    Add-Finding $findings 'BLOCKED_CASE2_OLD_OUTPUT_REUSE'
}
if ($outcome) {
    if ($outcome.run_triggered -ne $true -and ($outcome.error_detected -eq $true -or [string]$outcome.error_category)) {
        Add-Finding $findings 'BLOCKED_EXECUTION_OUTCOME_MISCLASSIFIED'
    }
    if ($outcome.execution_success -ne $true) {
        Add-Finding $findings 'BLOCKED_PYCHARM_CODE_FIX_EXHAUSTED'
    }
    if ($outcome.expected_output_verified -ne $true) {
        Add-Finding $findings 'BLOCKED_CASE2_OUTPUT_SEQUENCE_NOT_VERIFIED'
    }
}

$traceItems = @($trace)
if ($traceItems.Count -lt 6) {
    Add-Finding $findings 'BLOCKED_CASE2_STEP_TRACE_INCOMPLETE'
}
foreach ($step in $traceItems) {
    if ($step.result.next_step_allowed -ne $true -or $step.result.step_verified -ne $true) {
        Add-Finding $findings "BLOCKED_STEP_COMPLETION_GATE_MISSING:$($step.step_id)"
    }
}

$requiredFiles = @(
    'src\winagent\StepCompletionGate.h',
    'src\winagent\StepCompletionGate.cpp',
    'src\winagent\ExecutionOutcomeClassifier.cpp',
    'src\winagent\ExecutionOutcomeClassifier.h'
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $file))) {
        Add-Finding $findings "BLOCKED_REQUIRED_FILE_MISSING:$file"
    }
}
$stepGateCpp = Read-TextOrEmpty (Join-Path $Root 'src\winagent\StepCompletionGate.cpp')
$classifierCpp = Read-TextOrEmpty (Join-Path $Root 'src\winagent\ExecutionOutcomeClassifier.cpp')
if ($stepGateCpp -notmatch 'EvaluateStepCompletionGate') {
    Add-Finding $findings 'BLOCKED_RUNNER_ONLY_STEP_COMPLETION_GATE'
}
if ($classifierCpp -notmatch 'ClassifyExecutionOutcome' -or $classifierCpp -notmatch 'DV616_SEQ') {
    Add-Finding $findings 'BLOCKED_RUNNER_ONLY_EXECUTION_CLASSIFIER'
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }

if ($status -eq 'PASS') {
    $registry = Read-JsonFile $RegistryPath
    if ($registry) {
        $case2 = @($registry | Where-Object { $_.case_id -eq 'case_2_pycharm_run' })[0]
        if ($case2) {
            $case2.status = 'pass'
            $case2.last_pass_evidence_path = $RawEvidencePath
            $case2.last_failure_evidence_path = ''
            $case2.frozen_after_pass = $true
            $case2.rerun_required = $false
            $case2.invalidated = $false
            $case2.invalidated_reason = 'v6.1.6 scope reset Case2 PyCharm machine evidence verifier PASS'
            $case2.attempt_count = [int]$case2.attempt_count + 1
            $case2.last_run_timestamp = (Get-Date).ToString('o')
            Save-Json $registry $RegistryPath
        }
    }
}

$result = [ordered]@{
    schema_version = 'v6.1.6.scope_reset_step_completion_verifier.content2'
    generated_at = (Get-Date).ToString('o')
    status = $status
    case1_valid_frozen = ($case1 -and [string]$case1.status -eq 'PASS')
    case2_pass = ($status -eq 'PASS')
    case2_frozen_after_pass = ($status -eq 'PASS')
    raw_evidence_path = $RawEvidencePath
    generated_code_path = $GeneratedCodePath
    generated_code_medium_complexity_verified = $codeCheck.ok
    generated_code_class_count = $codeCheck.class_count
    execution_outcome_path = $OutcomePath
    run_triggered = if ($outcome) { [bool]$outcome.run_triggered } else { $false }
    execution_started = if ($outcome) { [bool]$outcome.execution_started } else { $false }
    execution_completed = if ($outcome) { [bool]$outcome.execution_completed } else { $false }
    execution_success = if ($outcome) { [bool]$outcome.execution_success } else { $false }
    exit_code = if ($outcome) { $outcome.exit_code } else { $null }
    error_category = if ($outcome) { [string]$outcome.error_category } else { '' }
    output_count = if ($outcome) { $outcome.output_count } else { 0 }
    output_sequence_verified = if ($outcome) { [bool]$outcome.expected_output_verified } else { $false }
    old_output_reuse_detected = if ($outcome) { [bool]$outcome.old_output_reuse_detected } else { $true }
    all_step_completion_gate_results_next_step_allowed = ($traceItems.Count -ge 6 -and ($traceItems | Where-Object { $_.result.next_step_allowed -ne $true }).Count -eq 0)
    step_completion_trace_path = $StepTracePath
    step_completion_gate_bottom_layer = ($stepGateCpp -match 'EvaluateStepCompletionGate')
    execution_outcome_classifier_bottom_layer = ($classifierCpp -match 'ClassifyExecutionOutcome')
    case3_case4_deferred = $true
    findings = @($findings.ToArray())
}
Save-Json $result $VerifierResultPath
Save-Json $result $Case2VerifierResultPath

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# v6.1.6 Scope Reset StepCompletion Verifier Report') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- Status: $status") | Out-Null
$lines.Add("- Case1 valid frozen: $($result.case1_valid_frozen)") | Out-Null
$lines.Add("- Case2 PASS: $($result.case2_pass)") | Out-Null
$lines.Add("- Case2 frozen_after_pass: $($result.case2_frozen_after_pass)") | Out-Null
$lines.Add("- Generated code medium complexity: $($result.generated_code_medium_complexity_verified)") | Out-Null
$lines.Add("- Run method: SHIFT+F10") | Out-Null
$lines.Add("- run_triggered: $($result.run_triggered)") | Out-Null
$lines.Add("- execution_success: $($result.execution_success)") | Out-Null
$lines.Add("- exit_code: $($result.exit_code)") | Out-Null
$lines.Add("- output_sequence_verified: $($result.output_sequence_verified)") | Out-Null
$lines.Add("- all_step_completion_gate_results_next_step_allowed: $($result.all_step_completion_gate_results_next_step_allowed)") | Out-Null
$lines.Add("- Case3/Case4: deferred, not current gate blockers") | Out-Null
if ($findings.Count -gt 0) {
    $lines.Add('') | Out-Null
    $lines.Add('## Findings') | Out-Null
    foreach ($finding in @($findings.ToArray())) { $lines.Add("- $finding") | Out-Null }
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

@(
    '# Case2 PyCharm Final Report',
    '',
    "- Status: $status",
    "- Raw evidence: $RawEvidencePath",
    "- Generated code: $GeneratedCodePath",
    "- Execution outcome: $OutcomePath",
    "- Step trace: $StepTracePath",
    "- run_triggered: $($result.run_triggered)",
    "- execution_started: $($result.execution_started)",
    "- execution_completed: $($result.execution_completed)",
    "- execution_success: $($result.execution_success)",
    "- exit_code: $($result.exit_code)",
    "- output_count: $($result.output_count)",
    "- output_sequence_verified: $($result.output_sequence_verified)",
    "- old_output_reuse_detected: $($result.old_output_reuse_detected)",
    "- code_fix_attempts: $(if ($raw) { $raw.fix_attempt_count } else { 0 })",
    "- frozen_after_pass: $($result.case2_frozen_after_pass)"
) | Set-Content -LiteralPath $Case2ReportPath -Encoding UTF8

if ($status -ne 'PASS') {
    Write-Output ($findings -join '; ')
    exit 1
}

Write-Output 'CASE2_PYCHARM_VERIFIER_PASS'
exit 0
