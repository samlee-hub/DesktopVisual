param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution\selftests\memory_safety_boundary'
$EvidencePath = Join-Path $OutDir 'safe_evidence.md'
$ReportPath = Join-Path $OutDir 'memory_safety_boundary_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Content -LiteralPath $EvidencePath -Encoding UTF8 -Value '# safe fixture evidence'

function Write-CaseJson([string]$Name, [hashtable]$Fields) {
    $path = Join-Path $OutDir "$Name.json"
    $base = [ordered]@{
        record_id = "memory-$Name"
        task_id = "task-$Name"
        workflow_type = 'explorer'
        workflow_id = "workflow-$Name"
        runtime_session_id = "session-$Name"
        step_contract_ref = 'step-contract-ref'
        execution_result = 'failed'
        failure_type = 'unknown'
        failure_code = 'UNKNOWN_FAILURE'
        normalized_failure_category = 'UNKNOWN_FAILURE'
        evidence_ref = $EvidencePath
        evidence_hash = 'hash-fixture'
        created_at = '2026-06-17T00:00:00Z'
        source_version = '6.10.0'
        trusted_version = '6.9.0'
        memory_schema_version = 'experience_memory.v1'
        redaction_applied = $false
        memory_execution_influence = $false
        runtime_execution_triggered = $false
        step_contract_mutated = $false
        workflow_action_generated = $false
        trusted_source = $true
        evidence_trusted = $true
        runner_only_memory_logic = $false
    }
    foreach ($key in $Fields.Keys) { $base[$key] = $Fields[$key] }
    $base | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-SafetyCase([string]$Name, [hashtable]$Fields, [string]$ExpectedViolation, [bool]$ShouldPass) {
    $inputPath = Write-CaseJson $Name $Fields
    $outputPath = Join-Path $OutDir "$Name.result.json"
    $cmd = & $WinAgent memory-safety-check --input $inputPath --output $outputPath 2>&1
    $exitCode = $LASTEXITCODE
    if ($ShouldPass) {
        if ($exitCode -ne 0) { throw "$Name should pass: $($cmd | Out-String)" }
        $json = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
        if ($json.status -ne 'PASS') { throw "$Name expected PASS" }
    } else {
        if ($exitCode -eq 0) { throw "$Name should fail but exited 0" }
        $json = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
        if ($json.violations -notcontains $ExpectedViolation) {
            throw "$Name expected $ExpectedViolation, got $($json.violations -join ',')"
        }
    }
}

Invoke-SafetyCase 'safe_record' @{ execution_result='success'; failure_type='none'; failure_code='none'; normalized_failure_category='SUCCESS_NO_FAILURE' } '' $true
Invoke-SafetyCase 'missing_evidence_ref' @{ evidence_ref='' } 'FAIL_MEMORY_EVIDENCE_REF_MISSING' $false
Invoke-SafetyCase 'invalid_evidence_ref' @{ evidence_ref=(Join-Path $OutDir 'missing.md') } 'FAIL_MEMORY_EVIDENCE_REF_INVALID' $false
Invoke-SafetyCase 'raw_completed_as_success' @{ execution_result='success'; failure_type='evidence_missing'; failure_code='RAW_COMPLETED_UNVERIFIED'; normalized_failure_category='EVIDENCE_MISSING' } 'FAIL_RAW_COMPLETED_AS_SUCCESS' $false
Invoke-SafetyCase 'communication_plaintext_body' @{ workflow_type='communication'; redaction_applied=$false; body='plain body must not persist' } 'FAIL_SENSITIVE_CONTENT_NOT_REDACTED' $false
Invoke-SafetyCase 'memory_modifies_stepcontract' @{ memory_execution_influence=$true } 'BLOCK_MEMORY_EXECUTION_INFLUENCE' $false
Invoke-SafetyCase 'memory_triggers_runtime' @{ runtime_execution_triggered=$true } 'BLOCK_MEMORY_EXECUTION_INFLUENCE' $false
Invoke-SafetyCase 'query_generates_action' @{ workflow_action_generated=$true } 'BLOCK_MEMORY_QUERY_SIDE_EFFECT' $false
Invoke-SafetyCase 'unknown_maps_to_success' @{ execution_result='failed'; failure_code='UNSEEN_CODE'; normalized_failure_category='SUCCESS_NO_FAILURE' } 'FAIL_UNKNOWN_FAILURE_MAPPING' $false
Invoke-SafetyCase 'dirty_artifact_source' @{ trusted_source=$false } 'FAIL_UNTRUSTED_MEMORY_SOURCE' $false
Invoke-SafetyCase 'runner_only_logic' @{ runner_only_memory_logic=$true } 'FAIL_RUNNER_ONLY_MEMORY_LOGIC' $false

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Memory Safety Boundary Selftest

- status: PASS
- safe_record: PASS
- missing_evidence_ref: FAIL_MEMORY_EVIDENCE_REF_MISSING
- invalid_evidence_ref: FAIL_MEMORY_EVIDENCE_REF_INVALID
- raw_completed_as_success: FAIL_RAW_COMPLETED_AS_SUCCESS
- communication_plaintext_body: FAIL_SENSITIVE_CONTENT_NOT_REDACTED
- memory_modifies_stepcontract: BLOCK_MEMORY_EXECUTION_INFLUENCE
- memory_triggers_runtime: BLOCK_MEMORY_EXECUTION_INFLUENCE
- query_generates_action: BLOCK_MEMORY_QUERY_SIDE_EFFECT
- unknown_maps_to_success: FAIL_UNKNOWN_FAILURE_MAPPING
- dirty_artifact_source: FAIL_UNTRUSTED_MEMORY_SOURCE
- runner_only_logic: FAIL_RUNNER_ONLY_MEMORY_LOGIC
- ui_workflow_executed: false
"@
Write-Host 'memory_safety_boundary_selftest PASS'
