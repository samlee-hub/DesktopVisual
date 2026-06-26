param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$RunnerResultPath = Join-Path $EvidenceRoot 'v6_4_0_runner_raw_result.json'

if (-not (Test-Path $RunnerResultPath)) {
    & (Join-Path $Root 'v6_4_0_runtime_task_execution_runner.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'v6.4.0 runner failed while preparing risk cases' }
}

function Read-Json($Path) {
    if (-not (Test-Path $Path)) { throw "missing JSON: $Path" }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

$runner = Read-Json $RunnerResultPath
$required = @{
    real_commit_without_confirmation = 'REAL_COMMIT_CONFIRMATION_REQUIRED'
    delete_file_without_confirmation = 'DESTRUCTIVE_CONFIRMATION_REQUIRED'
    active_protection_blocked = 'STEP_CONTRACT_VALIDATION_FAILED'
    credential_required_blocked = 'STEP_CONTRACT_VALIDATION_FAILED'
}

$failures = New-Object System.Collections.Generic.List[string]
$caseResults = New-Object System.Collections.Generic.List[object]

foreach ($name in $required.Keys) {
    $case = @($runner.cases | Where-Object { $_.name -eq $name }) | Select-Object -First 1
    if (-not $case) {
        $failures.Add("missing runner case $name") | Out-Null
        continue
    }
    $result = Read-Json $case.result
    $summary = $result.execution_summary
    $expectedError = $required[$name]
    $ok = $case.exit_code -ne 0 -and
        $summary.final_status -eq 'BLOCKED' -and
        $summary.runtime_executed -eq $false -and
        $summary.session_used -eq $false -and
        $summary.step_contract_validator_used -eq $true -and
        $summary.error_code -eq $expectedError
    $caseResults.Add([ordered]@{
        name = $name
        ok = $ok
        exit_code = $case.exit_code
        final_status = $summary.final_status
        runtime_executed = $summary.runtime_executed
        session_used = $summary.session_used
        validator_used = $summary.step_contract_validator_used
        error_code = $summary.error_code
    }) | Out-Null
    if (-not $ok) {
        $failures.Add("$name did not block as expected") | Out-Null
    }
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$report = [pscustomobject]@{
    schema_version = '6.4.0.risk_confirmation_cases'
    generated_at = (Get-Date).ToString('o')
    status = $status
    cases = $caseResults.ToArray()
    failures = $failures.ToArray()
}
$report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'risk_confirmation_cases_report.json')

$lines = @('# v6.4.0 Risk / Confirmation Cases Report','')
$lines += "- Status: $status"
$lines += '- Runtime executed for blocked risk cases: false'
$lines += ''
foreach ($case in $caseResults) {
    $lines += "- $($case.name): status=$($case.final_status), error=$($case.error_code), runtime_executed=$($case.runtime_executed)"
}
if ($failures.Count -gt 0) {
    $lines += ''
    $lines += '## Failures'
    foreach ($failure in $failures) { $lines += "- $failure" }
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'risk_confirmation_cases_report.md')

if ($status -ne 'PASS') {
    'V6_4_0_RISK_CONFIRMATION_CASES_FAIL'
    exit 1
}

'V6_4_0_RISK_CONFIRMATION_CASES_PASS'
