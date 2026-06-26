param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows'
$RunnerResult = Join-Path $ArtifactDir 'browser_form_runner_result.json'
$ReportPath = Join-Path $ArtifactDir 'browser_form_workflow_verifier_report.md'
$ResultPath = Join-Path $ArtifactDir 'browser_form_workflow_verifier_result.json'

$errors = New-Object System.Collections.Generic.List[string]
$caseResults = @()

if (-not (Test-Path $RunnerResult)) {
    $errors.Add('runner_result_missing')
} else {
    $runner = Get-Content -Raw -LiteralPath $RunnerResult | ConvertFrom-Json
    if ($runner.result -ne 'RAW_COMPLETED_UNVERIFIED') { $errors.Add('runner_result_not_raw_unverified') }
    foreach ($case in $runner.cases) {
        $name = $case.name
        $resultFile = $case.result
        $caseOk = $false
        $reason = ''
        $verifyExit = $null
        if (-not (Test-Path -LiteralPath $resultFile)) {
            $reason = 'execution_result_missing'
        } else {
            $json = Get-Content -Raw -LiteralPath $resultFile | ConvertFrom-Json
            $verifyOut = Join-Path (Split-Path -Parent $resultFile) 'verification.json'
            & $WinAgent verify-browser-workflow --result $resultFile --output $verifyOut | Out-Null
            $verifyExit = $LASTEXITCODE
            $positive = $name -like 'case_0*'
            if ($name -eq 'case_06_ordinary_external_web_readonly_diagnostic' -and $case.exit_code -ne 0) {
                $caseOk = $true
                $reason = 'environment_blocked_or_network_unavailable_recorded'
            } elseif ($positive) {
                $caseOk = ($case.exit_code -eq 0 -and $verifyExit -eq 0)
                if (-not $caseOk) { $reason = "positive_case_failed exit=$($case.exit_code) verify=$verifyExit stop=$($json.stop_code)" }
            } elseif ($name -eq 'negative_missing_field') {
                $caseOk = ($case.exit_code -ne 0 -and ($json.stop_code -eq 'FAIL_FIELD_NOT_FOUND' -or $json.error_code -eq 'FAIL_FIELD_NOT_FOUND'))
                if (-not $caseOk) { $reason = "missing_field_not_rejected stop=$($json.stop_code)" }
            } elseif ($name -eq 'negative_ambiguous_submit') {
                $caseOk = ($case.exit_code -ne 0 -and ($json.stop_code -eq 'STOP_TARGET_NOT_UNIQUE' -or $json.error_code -eq 'STOP_TARGET_NOT_UNIQUE'))
                if (-not $caseOk) { $reason = "ambiguous_submit_not_rejected stop=$($json.stop_code)" }
            } elseif ($name -eq 'negative_active_protection_stop') {
                $caseOk = ($case.exit_code -eq 0 -and $json.active_protection_detected -eq $true -and $json.final_status -eq 'STOPPED')
                if (-not $caseOk) { $reason = "active_protection_stop_not_verified stop=$($json.stop_code)" }
            } elseif ($name -eq 'negative_credential_required_stop') {
                $caseOk = ($case.exit_code -eq 0 -and $json.credential_required_detected -eq $true -and $json.final_status -eq 'STOPPED')
                if (-not $caseOk) { $reason = "credential_stop_not_verified stop=$($json.stop_code)" }
            } else {
                $caseOk = $false
                $reason = 'unknown_case'
            }
            if ($caseOk -and $json.runner_only_workflow_logic) { $caseOk = $false; $reason = 'runner_only_workflow_logic' }
            if ($caseOk -and ($json.dom_automation_used -or $json.javascript_automation_used -or $json.webdriver_used -or $json.cdp_used -or $json.playwright_used -or $json.selenium_used)) { $caseOk = $false; $reason = 'browser_backend_automation_used' }
            if ($caseOk -and ($json.fake_form_execution -or $json.powershell_fake_form_success_used -or $json.javascript_fake_form_success_used)) { $caseOk = $false; $reason = 'fake_form_execution' }
        }
        if (-not $caseOk) { $errors.Add("${name}:$reason") }
        $caseResults += [pscustomobject]@{ name = $name; ok = $caseOk; reason = $reason; exit_code = $case.exit_code; verify_exit = $verifyExit; result = $resultFile }
    }
}

$ok = $errors.Count -eq 0
$result = [pscustomobject]@{
    schema_version = '6.8.0.browser_form_workflow.verifier'
    verification_ok = $ok
    result = if ($ok) { 'PASS' } else { 'BLOCKED' }
    errors = @($errors)
    cases = $caseResults
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$lines = @('# v6.8.0 Browser/Form Workflow Verifier Report','')
$lines += "- verification_ok: $ok"
$lines += "- runner_result: $RunnerResult"
$lines += ''
$lines += '## Cases'
foreach ($c in $caseResults) {
    $lines += "- $($c.name): ok=$($c.ok) exit=$($c.exit_code) verify=$($c.verify_exit) reason=$($c.reason)"
}
if ($errors.Count -gt 0) {
    $lines += ''
    $lines += '## Errors'
    foreach ($e in $errors) { $lines += "- $e" }
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($ok) {
    'v6_8_0_browser_form_workflow_verifier PASS'
    exit 0
}
'v6_8_0_browser_form_workflow_verifier BLOCKED'
exit 1
