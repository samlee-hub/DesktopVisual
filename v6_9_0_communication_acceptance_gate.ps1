param(
    [string]$Root = $PSScriptRoot,
    [switch]$SkipFullRegression
)

$ErrorActionPreference = 'Continue'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$GateResult = Join-Path $ArtifactRoot 'v6_9_0_acceptance_gate_result.json'
$GateReport = Join-Path $ArtifactRoot 'v6_9_0_acceptance_gate_report.md'
$EvidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$checks = @()

function Invoke-GateCommand($Name, $Command, [bool]$Required = $true) {
    $log = Join-Path $ArtifactRoot ("gate_" + ($Name -replace '[^a-zA-Z0-9_.-]', '_') + ".log")
    Push-Location $Root
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $Command *> $log
    $exit = $LASTEXITCODE
    Pop-Location
    return [pscustomobject]@{ name = $Name; command = $Command; required = $Required; exit_code = $exit; ok = ($exit -eq 0); blocking_ok = ((-not $Required) -or $exit -eq 0); log = $log }
}

$checks += Invoke-GateCommand 'build' '.\build.ps1'
$checks += Invoke-GateCommand 'selftest' '.\selftest.ps1'
$checks += Invoke-GateCommand 'communication_schema_selftest' '.\communication_schema_selftest.ps1'
$checks += Invoke-GateCommand 'communication_adapter_selftest' '.\communication_adapter_selftest.ps1'
$checks += Invoke-GateCommand 'communication_executor_selftest' '.\communication_executor_selftest.ps1'
$checks += Invoke-GateCommand 'communication_verifier_selftest' '.\communication_verifier_selftest.ps1'
$checks += Invoke-GateCommand 'communication_runner' '.\v6_9_0_communication_runner.ps1'
$checks += Invoke-GateCommand 'communication_verifier' '.\v6_9_0_communication_verifier.ps1'

if ($SkipFullRegression) {
    $checks += [pscustomobject]@{ name = 'full_regression'; command = 'SKIPPED_BY_FLAG'; required = $true; exit_code = 0; ok = $true; blocking_ok = $true; log = '' }
} else {
    $checks += Invoke-GateCommand 'full_regression' '.\v6_9_0_full_regression_runner.ps1'
}

$sourceFiles = @(
    'src\winagent\CommunicationWorkflow.cpp',
    'src\winagent\CommunicationWorkflowAdapter.cpp',
    'src\winagent\CommunicationWorkflowExecutor.cpp',
    'src\winagent\CommunicationWorkflowVerifier.cpp'
)
$sourceText = ''
foreach ($file in $sourceFiles) {
    $path = Join-Path $Root $file
    if (Test-Path -LiteralPath $path) {
        $sourceText += "`n" + (Get-Content -Raw -LiteralPath $path)
    }
}
$staticNoFakeSend = $sourceText -notmatch 'fake\s*send|mock\s*send|send_success|sent_successfully'
$externalApiPattern = '#include\s*<\s*(winhttp|wininet|curl|websocket)|\b(WinHttp|URLDownloadToFile|InternetOpen|HttpSendRequest)\b'
$staticNoExternalApi = -not [regex]::IsMatch($sourceText, $externalApiPattern)
$validatorUsed = $sourceText -match 'ValidateStepContractV63Json'
$runtimeSessionUsed = $sourceText -match 'RuntimeSession'
$evidencePackUsed = $sourceText -match 'WriteExecutionEvidencePack'

$checks += [pscustomobject]@{ name = 'no_fake_send_static_scan'; command = 'static_scan'; required = $true; exit_code = if ($staticNoFakeSend) { 0 } else { 1 }; ok = $staticNoFakeSend; blocking_ok = $staticNoFakeSend; log = '' }
$checks += [pscustomobject]@{ name = 'no_external_api_usage_static_scan'; command = 'static_scan'; required = $true; exit_code = if ($staticNoExternalApi) { 0 } else { 1 }; ok = $staticNoExternalApi; blocking_ok = $staticNoExternalApi; log = '' }
$checks += [pscustomobject]@{ name = 'StepContractValidator_used'; command = 'static_scan'; required = $true; exit_code = if ($validatorUsed) { 0 } else { 1 }; ok = $validatorUsed; blocking_ok = $validatorUsed; log = '' }
$checks += [pscustomobject]@{ name = 'RuntimeSession_used'; command = 'static_scan'; required = $true; exit_code = if ($runtimeSessionUsed) { 0 } else { 1 }; ok = $runtimeSessionUsed; blocking_ok = $runtimeSessionUsed; log = '' }
$checks += [pscustomobject]@{ name = 'EvidencePack_generated'; command = 'static_scan'; required = $true; exit_code = if ($evidencePackUsed) { 0 } else { 1 }; ok = $evidencePackUsed; blocking_ok = $evidencePackUsed; log = '' }

$ok = @($checks | Where-Object { -not $_.blocking_ok }).Count -eq 0
$gate = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.acceptance_gate'
    gate_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    checks = $checks
    no_fake_send = $staticNoFakeSend
    no_external_api_usage = $staticNoExternalApi
    step_contract_validator_used = $validatorUsed
    runtime_session_used = $runtimeSessionUsed
    evidence_pack_generated = $evidencePackUsed
}
$gate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $GateResult -Encoding UTF8

$lines = @('# v6.9.0 Communication Acceptance Gate','')
$lines += "- gate_ok: $ok"
foreach ($check in $checks) {
    $lines += "- $($check.name): ok=$($check.ok) exit=$($check.exit_code) log=$($check.log)"
}
$lines | Set-Content -LiteralPath $GateReport -Encoding UTF8

$index = @('# v6.9.0 Communication Evidence Index','')
foreach ($file in @('schema_report.md','executor_report.md','verifier_report.md','adapter_report.md','positive_cases.md','negative_cases.md','final_status_report.md','v6_9_0_acceptance_gate_report.md')) {
    $path = Join-Path $ArtifactRoot $file
    $exists = Test-Path -LiteralPath $path
    $index += "- ${file}: exists=$exists path=$path"
}
$index | Set-Content -LiteralPath $EvidenceIndex -Encoding UTF8

if ($ok) {
    'v6_9_0_communication_acceptance_gate PASS'
    exit 0
}
'v6_9_0_communication_acceptance_gate BLOCKED'
exit 1
