param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$ArtifactDir = Join-Path $ArtifactRoot 'selftest\verifier'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function Base-Result {
    return @{
        schema_version = '6.9.0.communication_workflow.result'
        workflow_id = 'verifier-draft'
        task_id = 'verifier-task'
        type = 'draft'
        execution_mode = 'execute_local_safe'
        final_status = 'PASS'
        workflow_executed = $true
        communication_workflow_executor_used = $true
        task_intent_used = $true
        agent_plan_draft_used = $true
        compiled_step_contract_used = $true
        step_contract_validator_used = $true
        compiled_plan_executor_used = $true
        runtime_session_used = $true
        context_bound = $true
        context_binding_verified = $true
        step_level_verification_complete = $true
        evidence_pack_created = $true
        runner_only_workflow_logic = $false
        external_api_used = $false
        send_attempted = $false
        fake_send_used = $false
        provider_sdk_used = $false
        dom_automation_used = $false
        javascript_automation_used = $false
        webdriver_used = $false
        cdp_used = $false
    }
}

function Write-Result($Name, $Object) {
    $path = Join-Path $ArtifactDir "$Name.result.json"
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Expect-Verify($Name, $Object, [int]$ExitCode, [string]$Needle) {
    $result = Write-Result $Name $Object
    $verify = Join-Path $ArtifactDir "$Name.verify.json"
    $stdout = Join-Path $ArtifactDir "$Name.stdout.json"
    & $WinAgent verify-communication-workflow --result $result --output $verify *> $stdout
    if ($LASTEXITCODE -ne $ExitCode) {
        $text = Get-Content -Raw -LiteralPath $stdout
        throw "$Name expected verifier exit $ExitCode, got $LASTEXITCODE. Output: $text"
    }
    $outText = Get-Content -Raw -LiteralPath $stdout
    $verifyText = if (Test-Path $verify) { Get-Content -Raw -LiteralPath $verify } else { '' }
    if ($Needle -and (($outText + $verifyText) -notmatch [regex]::Escape($Needle))) {
        throw "$Name expected verifier output to contain $Needle"
    }
}

$base = Base-Result
Expect-Verify 'valid_result' $base 0 '"verification_ok":true'

$fake = Base-Result
$fake.fake_send_used = $true
Expect-Verify 'fake_send_rejected' $fake 1 'BLOCKED_FAKE_SEND'

$missingValidator = Base-Result
$missingValidator.step_contract_validator_used = $false
Expect-Verify 'missing_validator_rejected' $missingValidator 1 'BLOCKED_STEP_CONTRACT_VALIDATOR_BYPASSED'

$externalApi = Base-Result
$externalApi.external_api_used = $true
Expect-Verify 'external_api_rejected' $externalApi 1 'BLOCKED_EXTERNAL_COMMUNICATION_API_USED'

$runnerOnly = Base-Result
$runnerOnly.runner_only_workflow_logic = $true
Expect-Verify 'runner_only_rejected' $runnerOnly 1 'BLOCKED_RUNNER_ONLY_COMMUNICATION_WORKFLOW'

$noEvidence = Base-Result
$noEvidence.evidence_pack_created = $false
Expect-Verify 'no_evidence_rejected' $noEvidence 1 'BLOCKED_EVIDENCE_PACK_MISSING'

$missingVerification = Base-Result
$missingVerification.step_level_verification_complete = $false
Expect-Verify 'missing_verification_rejected' $missingVerification 1 'BLOCKED_COMMUNICATION_VERIFICATION_MISSING'

$summary = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.verifier_selftest'
    result = 'PASS'
    fake_send_rejected = $true
    missing_validator_rejected = $true
    external_api_rejected = $true
    runner_only_rejected = $true
    no_evidence_rejected = $true
    missing_verification_rejected = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'communication_verifier_selftest_result.json') -Encoding UTF8

$lines = @('# v6.9.0 Communication Verifier Report','')
$lines += '- result: PASS'
$lines += '- fake_send_rejected: true'
$lines += '- missing_validator_rejected: true'
$lines += '- external_api_rejected: true'
$lines += '- runner_only_rejected: true'
$lines += '- no_evidence_rejected: true'
$lines += '- missing_verification_rejected: true'
$lines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'verifier_report.md') -Encoding UTF8

'communication_verifier_selftest PASS'
