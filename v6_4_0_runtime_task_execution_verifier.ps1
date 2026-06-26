param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$RunnerResultPath = Join-Path $EvidenceRoot 'v6_4_0_runner_raw_result.json'
if (-not (Test-Path $RunnerResultPath)) {
    throw 'Runner raw result missing.'
}

$runner = Get-Content -Raw $RunnerResultPath | ConvertFrom-Json
$findings = New-Object System.Collections.Generic.List[string]
$positive = @{}
$negative = @{}

function Add-Finding($Message) {
    $findings.Add($Message) | Out-Null
}

function Read-JsonOrNull($Path) {
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content -Raw $Path | ConvertFrom-Json
    } catch {
        return $null
    }
}

foreach ($case in $runner.cases) {
    $result = Read-JsonOrNull $case.result
    $contract = Read-JsonOrNull $case.contract
    $record = [ordered]@{
        exit_code = $case.exit_code
        result = $result
        contract = $contract
        evidence_dir = $case.evidence_dir
    }
    if ($case.group -eq 'positive') { $positive[$case.name] = $record } else { $negative[$case.name] = $record }
}

if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { Add-Finding 'runner status was not RAW_COMPLETED_UNVERIFIED' }

foreach ($name in @('explorer_open_path','browser_open_page','browser_fill_form','local_mock_mail_fill','safe_recovery_during_execution','dry_run_no_runtime_execution')) {
    if (-not $positive.ContainsKey($name)) { Add-Finding "missing positive case $name"; continue }
    $r = $positive[$name]
    if ($r.exit_code -ne 0) { Add-Finding "positive case $name exit_code was $($r.exit_code)" }
    if (-not $r.result) { Add-Finding "positive case $name missing result"; continue }
    $s = $r.result.execution_summary
    if (-not $s.compiled) { Add-Finding "positive case $name not compiled" }
    if (-not $s.validated) { Add-Finding "positive case $name not validated" }
    if (-not $s.step_contract_validator_used) { Add-Finding "positive case $name did not use validator" }
    if (-not $s.evidence_pack_created) { Add-Finding "positive case $name missing evidence pack" }
    if ($s.final_status -ne 'PASS') { Add-Finding "positive case $name final_status was $($s.final_status)" }
    foreach ($file in @('execution_result.json','step_results.jsonl','evidence_index.md','execution_report.md')) {
        if (-not (Test-Path (Join-Path $r.evidence_dir $file))) { Add-Finding "positive case $name missing $file" }
    }
}

foreach ($name in @('explorer_open_path','browser_open_page','browser_fill_form','local_mock_mail_fill','safe_recovery_during_execution')) {
    $s = $positive[$name].result.execution_summary
    if (-not $s.runtime_executed) { Add-Finding "execute-local-safe case $name runtime_executed was false" }
    if (-not $s.session_used) { Add-Finding "execute-local-safe case $name session_used was false" }
    if (-not $s.runtime_context_guard_used) { Add-Finding "execute-local-safe case $name guard was not used" }
    if (-not $s.step_level_verification_complete) { Add-Finding "execute-local-safe case $name step verification incomplete" }
}

$formSummary = $positive['browser_fill_form'].result.execution_summary
if ($formSummary.steps_total -lt 9 -or $formSummary.steps_executed -ne $formSummary.steps_total) { Add-Finding 'browser_fill_form did not execute all expected steps' }
if ($formSummary.wrong_field_input_count -ne 0) { Add-Finding 'browser_fill_form wrong_field_input_count was not zero' }

$mailContractRisk = @($positive['local_mock_mail_fill'].contract.contracts | Select-Object -ExpandProperty risk_level -Unique)
if (-not ($mailContractRisk -contains 'REVERSIBLE_DRAFT' -or $mailContractRisk -contains 'LOW_RISK')) { Add-Finding 'local_mock_mail_fill risk was not draft/low risk' }

$recovery = $positive['safe_recovery_during_execution'].result.execution_summary
if (-not $recovery.recovery_attempted) { Add-Finding 'recovery case did not attempt recovery' }
if (-not $recovery.recovery_success) { Add-Finding 'recovery case did not succeed' }
if (-not $recovery.execution_resumed_from_checkpoint) { Add-Finding 'recovery case did not resume or replay from checkpoint' }

$dry = $positive['dry_run_no_runtime_execution'].result.execution_summary
if ($dry.runtime_executed) { Add-Finding 'dry-run runtime_executed was true' }
if (-not $dry.session_steps_generated) { Add-Finding 'dry-run did not generate session steps' }
if (-not $dry.no_mouse_click_sent) { Add-Finding 'dry-run no_mouse_click_sent was not true' }
if (-not $dry.no_keyboard_type_sent) { Add-Finding 'dry-run no_keyboard_type_sent was not true' }

foreach ($name in @('invalid_step_contract','missing_verification_hint','missing_expected_context','active_protection_blocked','credential_required_blocked','real_commit_without_confirmation','delete_file_without_confirmation','direct_coordinate_unsafe','wrong_context_stops_later_steps','verification_failure_stops_later_steps','stale_target_rejected')) {
    if (-not $negative.ContainsKey($name)) { Add-Finding "missing negative case $name"; continue }
    $r = $negative[$name]
    if ($r.exit_code -eq 0) { Add-Finding "negative case $name unexpectedly succeeded" }
}

foreach ($name in @('wrong_context_stops_later_steps','verification_failure_stops_later_steps','stale_target_rejected')) {
    $s = $negative[$name].result.execution_summary
    if ($s.steps_executed -ne 1) { Add-Finding "$name executed later steps" }
}
if ($negative['stale_target_rejected'].result.step_results[0].runtime_action_executed) { Add-Finding 'stale target action executed' }

$executorSource = Get-Content -Raw (Join-Path $Root 'src\winagent\CompiledPlanExecutor.cpp')
$runnerSource = Get-Content -Raw (Join-Path $Root 'v6_4_0_runtime_task_execution_runner.ps1')
if ($executorSource -notmatch 'ExecuteStepContractJson') { Add-Finding 'bottom-layer executor not found' }
if ($runnerSource -match 'final_status\\s*=\\s*PASS') { Add-Finding 'runner appears to self-certify PASS' }

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
$report = [ordered]@{
    schema_version = '6.4.0.runtime_task_execution.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    verifier_pass = ($status -eq 'PASS')
    findings = @($findings)
    positive_case_count = $positive.Count
    negative_case_count = $negative.Count
    dry_run_runtime_executed = [bool]$dry.runtime_executed
    execute_local_safe_runtime_executed = [bool]$positive['explorer_open_path'].result.execution_summary.runtime_executed
    runtime_session_used = [bool]$positive['explorer_open_path'].result.execution_summary.session_used
    runner_only_executor = $false
}
$reportPath = Join-Path $EvidenceRoot 'v6_4_0_verifier_report.json'
$report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $reportPath

$lines = @('# v6.4.0 Runtime Task Execution Verifier Report','')
$lines += "- Status: $status"
$lines += "- Positive cases: $($positive.Count)"
$lines += "- Negative cases: $($negative.Count)"
$lines += "- Dry-run runtime_executed: $($dry.runtime_executed)"
$lines += "- execute-local-safe runtime_executed: $($positive['explorer_open_path'].result.execution_summary.runtime_executed)"
$lines += ''
if ($findings.Count -gt 0) {
    $lines += '## Findings'
    foreach ($f in $findings) { $lines += "- $f" }
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_4_0_verifier_report.md')

if ($status -ne 'PASS') {
    "V6_4_0_RUNTIME_TASK_EXECUTION_VERIFIER_FAIL"
    $findings
    exit 1
}

"V6_4_0_RUNTIME_TASK_EXECUTION_VERIFIER_PASS"
