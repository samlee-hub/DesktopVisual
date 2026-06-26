param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution'
$RunnerRoot = Join-Path $ArtifactRoot 'runner'
$StoreRoot = Join-Path $RunnerRoot 'experience_memory_store'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
New-Item -ItemType Directory -Force -Path $RunnerRoot | Out-Null
if (Test-Path -LiteralPath $StoreRoot) {
    $storeFull = [IO.Path]::GetFullPath($StoreRoot)
    $runnerFull = [IO.Path]::GetFullPath($RunnerRoot)
    if (-not $storeFull.StartsWith($runnerFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected store path: $storeFull"
    }
    Remove-Item -LiteralPath $StoreRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StoreRoot | Out-Null

function New-Evidence([string]$Name, [string]$Text) {
    $path = Join-Path $RunnerRoot "$Name.md"
    Set-Content -LiteralPath $path -Encoding UTF8 -Value $Text
    return $path
}

$explorerEvidence = New-Evidence 'case1_explorer_success_evidence' '# Case 1 Explorer success evidence fixture'
$browserEvidence = New-Evidence 'case2_browser_locator_failure_evidence' '# Case 2 Browser locator failure evidence fixture'
$communicationEvidence = New-Evidence 'case3_communication_draft_success_evidence' '# Case 3 Communication draft success evidence fixture'
$activeProtectionEvidence = New-Evidence 'case4_active_protection_stop_evidence' '# Case 4 Active protection stop evidence fixture'

function Add-Record([string]$Name, [hashtable]$Fields) {
    $inputPath = Join-Path $RunnerRoot "$Name.input.json"
    $outputPath = Join-Path $RunnerRoot "$Name.record.json"
    $record = [ordered]@{
        task_id = "v610-$Name"
        workflow_type = 'explorer'
        workflow_id = "workflow-$Name"
        runtime_session_id = "session-$Name"
        step_contract_ref = 'step-contract-ref'
        execution_result = 'success'
        failure_type = 'none'
        failure_code = 'none'
        failure_reason = ''
        evidence_ref = $explorerEvidence
        source_version = '6.10.0'
        trusted_version = '6.9.0'
        memory_schema_version = 'experience_memory.v1'
        redaction_applied = $false
    }
    foreach ($key in $Fields.Keys) { $record[$key] = $Fields[$key] }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    $cmd = & $WinAgent experience-memory-record --input $inputPath --store-root $StoreRoot --output $outputPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "experience-memory-record failed for $Name`: $($cmd | Out-String)" }
    return $outputPath
}

$records = @()
$records += Add-Record 'case1_explorer_success' @{}
$records += Add-Record 'case2_browser_locator_failure' @{
    workflow_type='browser_form'; execution_result='failed'; failure_type='locator_failure'; failure_code='FAIL_FIELD_NOT_FOUND'; evidence_ref=$browserEvidence
}
$records += Add-Record 'case3_communication_draft_success' @{
    workflow_type='communication'; execution_result='success'; failure_type='none'; failure_code='none'; evidence_ref=$communicationEvidence; recipient='recipient@example.test'; subject='Draft subject fixture'; body='Sensitive draft body fixture'
}
$records += Add-Record 'case4_active_protection_stop' @{
    workflow_type='vlm_candidate'; execution_result='stopped'; failure_type='active_protection'; failure_code='STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'; evidence_ref=$activeProtectionEvidence
}

$queryOut = Join-Path $RunnerRoot 'case5_query_by_workflow_type.json'
& $WinAgent experience-memory-query --store-root $StoreRoot --workflow-type communication --output $queryOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'experience-memory-query failed in runner' }

$reportOut = Join-Path $RunnerRoot 'case6_failure_attribution_report.json'
$reportMd = Join-Path $RunnerRoot 'case6_failure_attribution_report.md'
& $WinAgent experience-memory-report --store-root $StoreRoot --output $reportOut --markdown-output $reportMd | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'experience-memory-report failed in runner' }

$result = [ordered]@{
    schema_version = '6.10.0.experience_memory_runner'
    status = 'RAW_COMPLETED_UNVERIFIED'
    runner_pass = $false
    store_root = $StoreRoot
    record_outputs = $records
    query_output = $queryOut
    report_output = $reportOut
    report_markdown = $reportMd
    ui_workflow_executed = $false
    old_ui_workflow_rerun = $false
    runtime_execution_triggered = $false
    step_contract_mutated_by_memory = $false
    v6_11_template_implemented = $false
    v6_12_rc_implemented = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RunnerResult -Encoding UTF8
Write-Host 'RAW_COMPLETED_UNVERIFIED'
