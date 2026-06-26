param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution\selftests\failure_attribution_integrator'
$StoreRoot = Join-Path $OutDir 'store'
$EvidencePath = Join-Path $OutDir 'integrator_evidence.md'
$ReportPath = Join-Path $OutDir 'failure_attribution_integrator_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (Test-Path -LiteralPath $StoreRoot) {
    $storeFull = [IO.Path]::GetFullPath($StoreRoot)
    $outFull = [IO.Path]::GetFullPath($OutDir)
    if (-not $storeFull.StartsWith($outFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected store path: $storeFull"
    }
    Remove-Item -LiteralPath $StoreRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StoreRoot | Out-Null
Set-Content -LiteralPath $EvidencePath -Encoding UTF8 -Value '# integrator selftest evidence'

function Invoke-Record([string]$Name, [hashtable]$Fields, [string]$ExpectedCategory) {
    $inputPath = Join-Path $OutDir "$Name.input.json"
    $outputPath = Join-Path $OutDir "$Name.record.json"
    $record = [ordered]@{
        task_id = "integrator-$Name"
        workflow_type = 'browser_form'
        workflow_id = "workflow-$Name"
        runtime_session_id = "session-$Name"
        step_contract_ref = 'step-contract-ref'
        execution_result = 'failed'
        failure_type = 'unknown'
        failure_code = 'UNSET'
        failure_reason = ''
        evidence_ref = $EvidencePath
        source_version = '6.10.0'
        trusted_version = '6.9.0'
        memory_schema_version = 'experience_memory.v1'
        redaction_applied = $false
    }
    foreach ($key in $Fields.Keys) { $record[$key] = $Fields[$key] }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    $cmd = & $WinAgent experience-memory-record --input $inputPath --store-root $StoreRoot --output $outputPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "experience-memory-record failed for $Name`: $($cmd | Out-String)" }
    $out = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
    if ($out.normalized_failure_category -ne $ExpectedCategory) {
        throw "$Name expected $ExpectedCategory, got $($out.normalized_failure_category)"
    }
    if ($out.runtime_execution_triggered -ne $false) { throw "$Name triggered runtime execution" }
}

Invoke-Record 'browser_locator_failure' @{ failure_type='locator_failure'; failure_code='FAIL_FIELD_NOT_FOUND'; failure_reason='field missing' } 'LOCATOR_FAILURE'
Invoke-Record 'active_protection_stop' @{ workflow_type='vlm_candidate'; execution_result='stopped'; failure_type='active_protection'; failure_code='STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK' } 'ACTIVE_PROTECTION'
Invoke-Record 'raw_completed_unverified' @{ execution_result='raw_completed_unverified'; failure_type='evidence_missing'; failure_code='RAW_COMPLETED_UNVERIFIED' } 'EVIDENCE_MISSING'

$recordsPath = Join-Path $StoreRoot 'memory_records.jsonl'
$lines = @(Get-Content -LiteralPath $recordsPath)
if ($lines.Count -ne 3) { throw "expected 3 integrated records, got $($lines.Count)" }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Failure Attribution Integrator Selftest

- status: PASS
- integrated_record_count: 3
- browser_locator_failure: LOCATOR_FAILURE
- active_protection_stop: ACTIVE_PROTECTION
- raw_completed_unverified: EVIDENCE_MISSING
- runtime_execution_triggered: false
- ui_workflow_executed: false
"@
Write-Host 'failure_attribution_integrator_selftest PASS'
