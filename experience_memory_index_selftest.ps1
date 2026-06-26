param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution\selftests\experience_memory_index'
$StoreRoot = Join-Path $OutDir 'store'
$EvidencePath = Join-Path $OutDir 'index_evidence.md'
$ReportPath = Join-Path $OutDir 'experience_memory_index_selftest_report.md'
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
Set-Content -LiteralPath $EvidencePath -Encoding UTF8 -Value '# index selftest evidence'

function Add-Record([string]$Name, [string]$Workflow, [string]$Result, [string]$FailureType, [string]$FailureCode) {
    $inputPath = Join-Path $OutDir "$Name.input.json"
    $outputPath = Join-Path $OutDir "$Name.record.json"
    [ordered]@{
        task_id = "index-$Name"
        workflow_type = $Workflow
        workflow_id = "workflow-$Name"
        runtime_session_id = "session-$Name"
        step_contract_ref = 'step-contract-ref'
        execution_result = $Result
        failure_type = $FailureType
        failure_code = $FailureCode
        failure_reason = $FailureCode
        evidence_ref = $EvidencePath
        source_version = '6.10.0'
        trusted_version = '6.9.0'
        memory_schema_version = 'experience_memory.v1'
        redaction_applied = ($Workflow -eq 'communication')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    $cmd = & $WinAgent experience-memory-record --input $inputPath --store-root $StoreRoot --output $outputPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "record failed for $Name`: $($cmd | Out-String)" }
}

Add-Record 'explorer_success' 'explorer' 'success' 'none' 'none'
Add-Record 'browser_locator' 'browser_form' 'failed' 'locator_failure' 'FAIL_FIELD_NOT_FOUND'
Add-Record 'active_protection' 'vlm_candidate' 'stopped' 'active_protection' 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'

$indexPath = Join-Path $StoreRoot 'memory_index.json'
if (-not (Test-Path -LiteralPath $indexPath)) { throw 'memory_index.json missing' }
$index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
if ($index.record_count -ne 3) { throw "expected 3 indexed records, got $($index.record_count)" }
if ($index.by_workflow_type.explorer -ne 1) { throw 'explorer index count mismatch' }
if ($index.by_failure_category.LOCATOR_FAILURE -ne 1) { throw 'LOCATOR_FAILURE index count mismatch' }
if ($index.by_failure_category.ACTIVE_PROTECTION -ne 1) { throw 'ACTIVE_PROTECTION index count mismatch' }
if ($index.runtime_execution_triggered -ne $false) { throw 'index triggered runtime execution' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Experience Memory Index Selftest

- status: PASS
- record_count: 3
- explorer_count: $($index.by_workflow_type.explorer)
- locator_failure_count: $($index.by_failure_category.LOCATOR_FAILURE)
- active_protection_count: $($index.by_failure_category.ACTIVE_PROTECTION)
- read_only_query_index: $($index.read_only_query_index)
- runtime_execution_triggered: false
- ui_workflow_executed: false
"@
Write-Host 'experience_memory_index_selftest PASS'
