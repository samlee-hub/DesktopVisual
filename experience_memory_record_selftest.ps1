param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution'
$SelftestRoot = Join-Path $ArtifactRoot 'selftests\experience_memory_record'
$StoreRoot = Join-Path $SelftestRoot 'store'
$EvidencePath = Join-Path $SelftestRoot 'explorer_success_evidence.md'
$InputPath = Join-Path $SelftestRoot 'explorer_success_input.json'
$OutputPath = Join-Path $SelftestRoot 'explorer_success_record.json'
$ReportPath = Join-Path $SelftestRoot 'experience_memory_record_selftest_report.md'

New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null
if (Test-Path -LiteralPath $StoreRoot) {
    $storeFull = [IO.Path]::GetFullPath($StoreRoot)
    $selftestFull = [IO.Path]::GetFullPath($SelftestRoot)
    if (-not $storeFull.StartsWith($selftestFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected store path: $storeFull"
    }
    Remove-Item -LiteralPath $StoreRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StoreRoot | Out-Null

Set-Content -LiteralPath $EvidencePath -Encoding UTF8 -Value @'
# Explorer Success Evidence Fixture

- workflow_type: explorer
- execution_result: success
- ui_workflow_executed: false
- fixture_only: true
'@

$inputRecord = [ordered]@{
    task_id = 'record-selftest-explorer-success'
    workflow_type = 'explorer'
    workflow_id = 'explorer-selftest-001'
    runtime_session_id = 'session-selftest-001'
    step_contract_ref = 'artifacts/dev6.10.0_experience_memory_failure_attribution/selftests/experience_memory_record/step_contract_ref.json'
    execution_result = 'success'
    failure_type = 'none'
    failure_reason = ''
    evidence_ref = $EvidencePath
    source_version = '6.10.0'
    trusted_version = '6.9.0'
    memory_schema_version = 'experience_memory.v1'
    redaction_applied = $false
}
$inputRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $InputPath -Encoding UTF8

$commandOutput = & $WinAgent experience-memory-record --input $InputPath --store-root $StoreRoot --output $OutputPath 2>&1
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    $report = @"
# Experience Memory Record Selftest

- status: FAIL
- reason: experience-memory-record command failed
- exit_code: $exitCode
- command_output:

````text
$($commandOutput | Out-String)
````
"@
    Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value $report
    throw "experience-memory-record failed with exit code $exitCode"
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "experience-memory-record did not write output record JSON"
}

$record = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
if ($record.workflow_type -ne 'explorer') {
    throw "workflow_type mismatch: $($record.workflow_type)"
}
if ($record.execution_result -ne 'success') {
    throw "execution_result mismatch: $($record.execution_result)"
}
if ([string]::IsNullOrWhiteSpace($record.record_id)) {
    throw 'record_id missing'
}
if ([string]::IsNullOrWhiteSpace($record.evidence_hash)) {
    throw 'evidence_hash missing'
}
if (-not (Test-Path -LiteralPath $record.evidence_ref)) {
    throw "evidence_ref does not exist: $($record.evidence_ref)"
}
if ($record.normalized_failure_category -ne 'SUCCESS_NO_FAILURE') {
    throw "success record normalized category mismatch: $($record.normalized_failure_category)"
}
if ($record.memory_execution_influence -ne $false) {
    throw 'memory_execution_influence must be false'
}
if ($record.runtime_execution_triggered -ne $false) {
    throw 'runtime_execution_triggered must be false'
}
if ($record.step_contract_mutated -ne $false) {
    throw 'step_contract_mutated must be false'
}

$storePath = Join-Path $StoreRoot 'memory_records.jsonl'
if (-not (Test-Path -LiteralPath $storePath)) {
    throw 'memory_records.jsonl was not created'
}
$lines = @(Get-Content -LiteralPath $storePath)
if ($lines.Count -lt 1) {
    throw 'memory_records.jsonl is empty'
}

$reportPass = @"
# Experience Memory Record Selftest

- status: PASS
- command: experience-memory-record
- workflow_type: $($record.workflow_type)
- execution_result: $($record.execution_result)
- normalized_failure_category: $($record.normalized_failure_category)
- evidence_ref_exists: true
- memory_execution_influence: false
- runtime_execution_triggered: false
- step_contract_mutated: false
- ui_workflow_executed: false
"@
Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value $reportPass
Write-Host 'experience_memory_record_selftest PASS'
