param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\recovery'
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
        throw "$Name expected verifier exit $ExitCode, got $LASTEXITCODE. Output: $(Get-Content -Raw -LiteralPath $stdout)"
    }
    $combined = (Get-Content -Raw -LiteralPath $stdout) + $(if (Test-Path $verify) { Get-Content -Raw -LiteralPath $verify } else { '' })
    if ($Needle -and $combined -notmatch [regex]::Escape($Needle)) {
        throw "$Name expected $Needle in verifier output"
    }
}

$base = @{
    schema_version = '6.8.0.browser_workflow.result'
    workflow_id = 'recovery-success'
    workflow_type = 'browser_wrong_page_recovery'
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
    wrong_page_detected = $true
    recovery_attempted = $true
    recovery_success = $true
    runner_only_workflow_logic = $false
    dom_automation_used = $false
    javascript_automation_used = $false
    webdriver_used = $false
    cdp_used = $false
    fake_form_execution = $false
}

Expect-Verify 'wrong_page_recovery_success' $base 0 '"verification_ok":true'

$failed = $base.Clone()
$failed['workflow_id'] = 'recovery-failed'
$failed['final_status'] = 'BLOCKED'
$failed['recovery_success'] = $false
Expect-Verify 'wrong_page_recovery_failed' $failed 1 'STOP_BROWSER_RECOVERY_FAILED'

$summary = [pscustomobject]@{
    schema_version = '6.8.0.browser_recovery_selftest'
    result = 'PASS'
    recovery_success_accepted = $true
    recovery_failure_rejected = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_recovery_selftest_result.json') -Encoding UTF8
'browser_recovery_selftest PASS'
