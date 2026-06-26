param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\protection_stop'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function Expect-Verify($Name, $Object, [int]$ExitCode, [string]$Needle) {
    $result = Join-Path $ArtifactDir "$Name.result.json"
    $verify = Join-Path $ArtifactDir "$Name.verify.json"
    $stdout = Join-Path $ArtifactDir "$Name.stdout.json"
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $result -Encoding UTF8
    & $WinAgent verify-browser-workflow --result $result --output $verify *> $stdout
    if ($LASTEXITCODE -ne $ExitCode) {
        throw "$Name expected verifier exit $ExitCode, got $LASTEXITCODE. Output: $(Get-Content -Raw -LiteralPath $stdout)"
    }
    $combined = (Get-Content -Raw -LiteralPath $stdout) + $(if (Test-Path $verify) { Get-Content -Raw -LiteralPath $verify } else { '' })
    if ($Needle -and $combined -notmatch [regex]::Escape($Needle)) {
        throw "$Name expected $Needle in verifier output"
    }
}

function Base-Stop($Type) {
    return @{
        schema_version = '6.8.0.browser_workflow.result'
        workflow_id = "stop-$Type"
        workflow_type = $Type
        execution_mode = 'execute_local_safe'
        final_status = 'STOPPED'
        stop_code = if ($Type -eq 'browser_active_protection_stop') { 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK' } else { 'STOP_CREDENTIAL_REQUIRED' }
        workflow_compiled = $true
        compiled_step_contract_used = $true
        step_contract_validator_used = $true
        runtime_session_used = $true
        runtime_context_guard_used = $true
        browser_surface_normalizer_used = $true
        step_level_verification_complete = $true
        evidence_pack_created = $true
        browser_opened = $true
        active_protection_detected = ($Type -eq 'browser_active_protection_stop')
        credential_required_detected = ($Type -eq 'browser_credential_required_stop')
        runner_only_workflow_logic = $false
        dom_automation_used = $false
        javascript_automation_used = $false
        webdriver_used = $false
        cdp_used = $false
        fake_form_execution = $false
    }
}

Expect-Verify 'active_protection_stop' (Base-Stop 'browser_active_protection_stop') 0 '"verification_ok":true'
Expect-Verify 'credential_required_stop' (Base-Stop 'browser_credential_required_stop') 0 '"verification_ok":true'

$bad = Base-Stop 'browser_active_protection_stop'
$bad['active_protection_detected'] = $false
Expect-Verify 'missing_active_protection_rejected' $bad 1 'BLOCKED_BROWSER_PROTECTION_STOP_FAILED'

$summary = [pscustomobject]@{
    schema_version = '6.8.0.browser_protection_stop_selftest'
    result = 'PASS'
    active_protection_stop_verified = $true
    credential_required_stop_verified = $true
    missing_stop_evidence_rejected = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_protection_stop_selftest_result.json') -Encoding UTF8
'browser_protection_stop_selftest PASS'
