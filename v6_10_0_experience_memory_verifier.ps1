param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
$VerifierResult = Join-Path $ArtifactRoot 'verifier_result.json'
$SchemaReport = Join-Path $ArtifactRoot 'memory_schema_report.md'
$StoreReport = Join-Path $ArtifactRoot 'memory_store_report.md'
$FailureReport = Join-Path $ArtifactRoot 'failure_attribution_report.md'
$SafetyReport = Join-Path $ArtifactRoot 'memory_safety_report.md'
$PositiveCases = Join-Path $ArtifactRoot 'positive_cases.md'
$NegativeCases = Join-Path $ArtifactRoot 'negative_cases.md'

if (-not (Test-Path -LiteralPath $RunnerResult)) { throw 'runner_result.json missing' }
$runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { throw "runner status must be RAW_COMPLETED_UNVERIFIED, got $($runner.status)" }
if ($runner.runner_pass -ne $false) { throw 'runner must not self-certify PASS' }
if ($runner.ui_workflow_executed -ne $false) { throw 'runner executed UI workflow' }

$recordsPath = Join-Path $runner.store_root 'memory_records.jsonl'
if (-not (Test-Path -LiteralPath $recordsPath)) { throw 'memory_records.jsonl missing' }
$records = @(Get-Content -LiteralPath $recordsPath | ForEach-Object { $_ | ConvertFrom-Json })
if ($records.Count -ne 4) { throw "expected 4 runner records, got $($records.Count)" }

foreach ($record in $records) {
    if ([string]::IsNullOrWhiteSpace($record.record_id)) { throw 'record_id missing' }
    if ([string]::IsNullOrWhiteSpace($record.evidence_ref) -or -not (Test-Path -LiteralPath $record.evidence_ref)) { throw "invalid evidence_ref: $($record.evidence_ref)" }
    if ($record.runtime_execution_triggered -ne $false) { throw 'record triggered runtime execution' }
    if ($record.step_contract_mutated -ne $false) { throw 'record mutated StepContract' }
    if ($record.memory_execution_influence -ne $false) { throw 'record influences execution' }
}

$explorer = $records | Where-Object { $_.workflow_type -eq 'explorer' } | Select-Object -First 1
$browser = $records | Where-Object { $_.workflow_type -eq 'browser_form' } | Select-Object -First 1
$comm = $records | Where-Object { $_.workflow_type -eq 'communication' } | Select-Object -First 1
$active = $records | Where-Object { $_.failure_code -eq 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK' } | Select-Object -First 1
if ($explorer.execution_result -ne 'success' -or $explorer.normalized_failure_category -ne 'SUCCESS_NO_FAILURE') { throw 'Explorer success case invalid' }
if ($browser.normalized_failure_category -ne 'LOCATOR_FAILURE') { throw 'Browser locator failure not normalized' }
if ($comm.redaction_applied -ne $true) { throw 'Communication redaction not applied' }
$jsonl = Get-Content -Raw -LiteralPath $recordsPath
if ($jsonl -match 'Sensitive draft body fixture') { throw 'Communication plaintext body leaked' }
if ($active.normalized_failure_category -ne 'ACTIVE_PROTECTION') { throw 'Active protection not normalized' }

$safetyOut = Join-Path $ArtifactRoot 'memory_safety_check_result.json'
& $WinAgent memory-safety-check --store-root $runner.store_root --output $safetyOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'memory-safety-check failed on runner store' }
$safety = Get-Content -Raw -LiteralPath $safetyOut | ConvertFrom-Json
if ($safety.status -ne 'PASS') { throw 'memory safety status is not PASS' }

$v610CheckOut = Join-Path $ArtifactRoot 'v6_10_experience_memory_check_result.json'
& $WinAgent v6-10-experience-memory-check --store-root $runner.store_root --output $v610CheckOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'v6-10-experience-memory-check failed on runner store' }
$v610Check = Get-Content -Raw -LiteralPath $v610CheckOut | ConvertFrom-Json
if ($v610Check.status -ne 'PASS') { throw 'v6-10-experience-memory-check did not PASS' }

$query = Get-Content -Raw -LiteralPath $runner.query_output | ConvertFrom-Json
if ($query.record_count -ne 1 -or $query.runtime_execution_triggered -ne $false -or $query.workflow_action_generated -ne $false) {
    throw 'query read-only case failed'
}
$report = Get-Content -Raw -LiteralPath $runner.report_output | ConvertFrom-Json
if ($report.by_failure_category.LOCATOR_FAILURE -ne 1 -or $report.by_failure_category.ACTIVE_PROTECTION -ne 1) {
    throw 'failure attribution report aggregation failed'
}
if ($report.optimization_suggestions_generated -ne $false -or $report.auto_fix_plan_generated -ne $false) {
    throw 'report generated forbidden recommendations'
}

Set-Content -LiteralPath $SchemaReport -Encoding UTF8 -Value @"
# Memory Schema Report

- status: PASS
- checked_record_count: $($records.Count)
- required_fields_present: true
- evidence_refs_valid: true
- raw_completed_unverified_as_success: false
"@
Set-Content -LiteralPath $StoreReport -Encoding UTF8 -Value @"
# Memory Store Report

- status: PASS
- store_root: $($runner.store_root)
- record_count: $($records.Count)
- append_only_jsonl: true
- memory_index_exists: $(Test-Path -LiteralPath (Join-Path $runner.store_root 'memory_index.json'))
"@
Set-Content -LiteralPath $FailureReport -Encoding UTF8 -Value @"
# Failure Attribution Report

- status: PASS
- LOCATOR_FAILURE: $($report.by_failure_category.LOCATOR_FAILURE)
- ACTIVE_PROTECTION: $($report.by_failure_category.ACTIVE_PROTECTION)
- SUCCESS_NO_FAILURE: $($report.by_failure_category.SUCCESS_NO_FAILURE)
- optimization_suggestions_generated: false
- auto_fix_plan_generated: false
"@
Set-Content -LiteralPath $SafetyReport -Encoding UTF8 -Value @"
# Memory Safety Report

- status: PASS
- safety_check_status: $($safety.status)
- memory_execution_influence: false
- runtime_execution_triggered: false
- step_contract_mutated_by_memory: false
- sensitive_plaintext_saved: false
- raw_completed_unverified_marked_success: false
- v6_10_experience_memory_check: $($v610Check.status)
"@
Set-Content -LiteralPath $PositiveCases -Encoding UTF8 -Value @"
# Positive Cases

- Case 1 Explorer success memory: PASS
- Case 2 Browser locator failure memory: PASS
- Case 3 Communication draft success redacted memory: PASS
- Case 4 Active protection stop memory: PASS
- Case 5 Query by workflow_type read-only: PASS
- Case 6 Failure attribution report aggregation: PASS
"@
Set-Content -LiteralPath $NegativeCases -Encoding UTF8 -Value @"
# Negative Cases

- missing evidence_ref: covered by memory_safety_boundary_selftest.ps1
- nonexistent evidence_ref: covered by memory_safety_boundary_selftest.ps1
- RAW_COMPLETED_UNVERIFIED marked success: covered by memory_safety_boundary_selftest.ps1
- Communication plaintext body: covered by memory_safety_boundary_selftest.ps1
- Memory modifies StepContract: covered by memory_safety_boundary_selftest.ps1
- Memory triggers Runtime execution: covered by memory_safety_boundary_selftest.ps1
- Memory query side effect: covered by memory_safety_boundary_selftest.ps1
- Unknown failure maps to success: covered by memory_safety_boundary_selftest.ps1 and failure_attribution_normalizer_selftest.ps1
- Dirty artifact as trusted source: covered by memory_safety_boundary_selftest.ps1
- Runner-only memory logic: covered by memory_safety_boundary_selftest.ps1
"@

$result = [ordered]@{
    schema_version = '6.10.0.experience_memory_verifier'
    status = 'PASS'
    runner_status = $runner.status
    checked_record_count = $records.Count
    memory_schema = 'PASS'
    evidence_refs = 'PASS'
    redaction = 'PASS'
    no_execution_influence = $true
    failure_normalization = 'PASS'
    no_runner_only_logic = $true
    no_old_ui_workflow_rerun = $true
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $VerifierResult -Encoding UTF8
Write-Host 'v6_10_0_experience_memory_verifier PASS'
