param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$RunnerResult = Join-Path $ArtifactRoot 'communication_runner_result.json'
$ReportPath = Join-Path $ArtifactRoot 'final_status_report.md'
$ResultPath = Join-Path $ArtifactRoot 'communication_workflow_verifier_result.json'

$errors = New-Object System.Collections.Generic.List[string]
$caseResults = @()

if (-not (Test-Path $RunnerResult)) {
    $errors.Add('runner_result_missing')
} else {
    $runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
    if ($runner.result -ne 'RAW_COMPLETED_UNVERIFIED') { $errors.Add('runner_result_not_raw_unverified') }
    if (-not (Test-Path -LiteralPath $runner.fixture_root)) { $errors.Add('fixture_root_missing') }

    foreach ($case in $runner.positive_cases) {
        $ok = $false
        $reason = ''
        if ($case.exit_code -ne 0 -or $case.verify_exit -ne 0) {
            $reason = "positive_case_failed run=$($case.exit_code) verify=$($case.verify_exit)"
        } elseif (-not (Test-Path -LiteralPath $case.result)) {
            $reason = 'result_missing'
        } else {
            $json = Get-Content -Raw -LiteralPath $case.result | ConvertFrom-Json
            $ok = (
                $json.final_status -eq 'PASS' -and
                $json.workflow_executed -eq $true -and
                $json.context_bound -eq $true -and
                $json.step_contract_validator_used -eq $true -and
                $json.runtime_session_used -eq $true -and
                $json.compiled_plan_executor_used -eq $true -and
                $json.evidence_pack_created -eq $true -and
                $json.runner_only_workflow_logic -eq $false -and
                $json.external_api_used -eq $false -and
                $json.fake_send_used -eq $false -and
                $json.send_attempted -eq $false
            )
            if (-not $ok) { $reason = 'positive_result_missing_required_flags' }
        }
        if (-not $ok) { $errors.Add("$($case.name):$reason") }
        $caseResults += [pscustomobject]@{ name = $case.name; kind = 'positive'; ok = $ok; reason = $reason; run_exit = $case.exit_code; verify_exit = $case.verify_exit }
    }

    foreach ($case in $runner.negative_cases) {
        $ok = $case.verify_exit -ne 0
        $reason = if ($ok) { '' } else { 'negative_case_was_accepted' }
        if ($ok -and (Test-Path -LiteralPath $case.verify)) {
            $verifyText = Get-Content -Raw -LiteralPath $case.verify
            if ($verifyText -notmatch [regex]::Escape($case.expected_code)) {
                $ok = $false
                $reason = "expected_code_missing:$($case.expected_code)"
            }
        }
        if (-not $ok) { $errors.Add("$($case.name):$reason") }
        $caseResults += [pscustomobject]@{ name = $case.name; kind = 'negative'; ok = $ok; reason = $reason; verify_exit = $case.verify_exit; expected_code = $case.expected_code }
    }
}

$ok = $errors.Count -eq 0
$result = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.verifier'
    verification_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    errors = @($errors)
    cases = $caseResults
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$lines = @('# v6.9.0 Communication Final Status Report','')
$lines += "- verification_ok: $ok"
$lines += "- runner_result: $RunnerResult"
$lines += ''
$lines += '## Cases'
foreach ($case in $caseResults) {
    $lines += "- $($case.name): kind=$($case.kind) ok=$($case.ok) reason=$($case.reason)"
}
if ($errors.Count -gt 0) {
    $lines += ''
    $lines += '## Errors'
    foreach ($error in $errors) { $lines += "- $error" }
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($ok) {
    'v6_9_0_communication_verifier PASS'
    exit 0
}
'v6_9_0_communication_verifier BLOCKED'
exit 1
