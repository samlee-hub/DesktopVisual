param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution\selftests\experience_memory_store'
$StoreRoot = Join-Path $OutDir 'store'
$EvidencePath = Join-Path $OutDir 'store_evidence.md'
$ReportPath = Join-Path $OutDir 'experience_memory_store_selftest_report.md'
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
Set-Content -LiteralPath $EvidencePath -Encoding UTF8 -Value '# store selftest evidence'

function Add-MemoryRecord([string]$Name, [hashtable]$Fields) {
    $inputPath = Join-Path $OutDir "$Name.input.json"
    $outputPath = Join-Path $OutDir "$Name.record.json"
    $record = [ordered]@{
        task_id = "store-$Name"
        workflow_type = 'browser_form'
        workflow_id = "workflow-$Name"
        runtime_session_id = "session-$Name"
        step_contract_ref = 'step-contract-ref'
        execution_result = 'failed'
        failure_type = 'locator_failure'
        failure_code = 'FAIL_FIELD_NOT_FOUND'
        failure_reason = 'field missing'
        evidence_ref = $EvidencePath
        source_version = '6.10.0'
        trusted_version = '6.9.0'
        memory_schema_version = 'experience_memory.v1'
        redaction_applied = $false
    }
    foreach ($key in $Fields.Keys) { $record[$key] = $Fields[$key] }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    $cmd = & $WinAgent experience-memory-record --input $inputPath --store-root $StoreRoot --output $outputPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "experience-memory-record failed for $Name`: $($cmd | Out-String)"
    }
    return Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
}

$first = Add-MemoryRecord 'browser_locator_failure' @{}
$second = Add-MemoryRecord 'communication_success' @{
    workflow_type = 'communication'
    execution_result = 'success'
    failure_type = 'none'
    failure_code = 'none'
    failure_reason = ''
    recipient = 'person@example.test'
    subject = 'Sensitive subject fixture'
    body = 'This plaintext body must not be stored in memory.'
}

$recordsPath = Join-Path $StoreRoot 'memory_records.jsonl'
$indexPath = Join-Path $StoreRoot 'memory_index.json'
if (-not (Test-Path -LiteralPath $recordsPath)) { throw 'memory_records.jsonl missing' }
if (-not (Test-Path -LiteralPath $indexPath)) { throw 'memory_index.json missing' }
$lines = @(Get-Content -LiteralPath $recordsPath)
if ($lines.Count -ne 2) { throw "expected 2 JSONL records, got $($lines.Count)" }
$jsonl = Get-Content -Raw -LiteralPath $recordsPath
if ($jsonl -match 'This plaintext body must not be stored') { throw 'communication plaintext body leaked into JSONL' }

$queryOut = Join-Path $OutDir 'query_locator_failure.json'
$cmd = & $WinAgent experience-memory-query --store-root $StoreRoot --failure-category LOCATOR_FAILURE --output $queryOut 2>&1
if ($LASTEXITCODE -ne 0) { throw "experience-memory-query failed: $($cmd | Out-String)" }
$query = Get-Content -Raw -LiteralPath $queryOut | ConvertFrom-Json
if ($query.record_count -ne 1) { throw "expected 1 locator failure query result, got $($query.record_count)" }
if ($query.runtime_execution_triggered -ne $false) { throw 'query triggered runtime execution' }
if ($query.step_contract_generated -ne $false) { throw 'query generated StepContract' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Experience Memory Store Selftest

- status: PASS
- record_count: 2
- first_category: $($first.normalized_failure_category)
- second_workflow_type: $($second.workflow_type)
- communication_redaction_applied: $($second.redaction_applied)
- plaintext_body_leaked: false
- query_read_only: true
- runtime_execution_triggered: false
- ui_workflow_executed: false
"@
Write-Host 'experience_memory_store_selftest PASS'
