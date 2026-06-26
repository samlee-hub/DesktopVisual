param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\verifier'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
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
    & $WinAgent verify-browser-workflow --result $result --output $verify *> $stdout
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

$base = @{
    schema_version = '6.8.0.browser_workflow.result'
    workflow_id = 'verifier-open'
    workflow_type = 'browser_open_page'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $true
    runtime_context_guard_used = $true
    browser_surface_normalizer_used = $true
    step_level_verification_complete = $true
    evidence_pack_created = $true
    browser_opened = $true
    page_loaded = $true
    required_markers_verified = $true
    runner_only_workflow_logic = $false
    dom_automation_used = $false
    javascript_automation_used = $false
    webdriver_used = $false
    cdp_used = $false
    fake_form_execution = $false
}

Expect-Verify 'valid_open_result' $base 0 '"verification_ok":true'

$runnerOnly = $base.Clone()
$runnerOnly['runner_only_workflow_logic'] = $true
Expect-Verify 'runner_only_rejected' $runnerOnly 1 'BLOCKED_RUNNER_ONLY_BROWSER_WORKFLOW'

$dom = $base.Clone()
$dom['cdp_used'] = $true
Expect-Verify 'cdp_rejected' $dom 1 'BLOCKED_BROWSER_BACKEND_AUTOMATION_USED'

$fake = $base.Clone()
$fake['fake_form_execution'] = $true
Expect-Verify 'fake_form_rejected' $fake 1 'BLOCKED_FAKE_FORM_EXECUTION'

$submit = $base.Clone()
$submit['workflow_id'] = 'verifier-submit'
$submit['workflow_type'] = 'browser_submit_form'
$submit['form_fields_total'] = 2
$submit['form_fields_verified'] = 2
$submit['submit_result_verified'] = $false
Expect-Verify 'unverified_submit_rejected' $submit 1 'BLOCKED_UNVERIFIED_FORM_SUBMIT'

$summary = [pscustomobject]@{
    schema_version = '6.8.0.browser_workflow.verifier_selftest'
    result = 'PASS'
    valid_result_accepted = $true
    runner_only_rejected = $true
    backend_automation_rejected = $true
    fake_form_rejected = $true
    unverified_submit_rejected = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_workflow_verifier_selftest_result.json') -Encoding UTF8
'browser_workflow_verifier_selftest PASS'
