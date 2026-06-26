param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\schema'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function Write-JsonFile($Path, $Object) {
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Compile($Name, $Spec, [int]$ExpectedExit, [string]$ExpectedNeedle) {
    $input = Join-Path $ArtifactDir "$Name.workflow.json"
    $output = Join-Path $ArtifactDir "$Name.step_contract.json"
    $stdout = Join-Path $ArtifactDir "$Name.stdout.json"
    Write-JsonFile $input $Spec
    & $WinAgent compile-browser-workflow --input $input --output $output *> $stdout
    $exitCode = $LASTEXITCODE
    $text = Get-Content -Raw -LiteralPath $stdout
    if ($exitCode -ne $ExpectedExit) {
        throw "$Name expected exit $ExpectedExit, got $exitCode. Output: $text"
    }
    if ($ExpectedNeedle -and $text -notmatch [regex]::Escape($ExpectedNeedle)) {
        throw "$Name expected output to contain '$ExpectedNeedle'. Output: $text"
    }
    return [pscustomobject]@{ name = $Name; exit_code = $exitCode; output = $stdout; contract = $output }
}

$base = @{
    workflow_id = 'schema-open-local'
    task_id = 'schema-task'
    workflow_type = 'browser_open_page'
    url = 'file:///D:/testrepo/testwindow/browser_form_v6_8/local_form_basic.html'
    browser = 'chrome'
    expected_title_pattern = 'DesktopVisual Browser Form v6.8'
    expected_url_pattern = 'local_form_basic'
    required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
    allowed_origin = 'file://'
    allowed_url_prefix = 'file:///D:/testrepo/testwindow/browser_form_v6_8/'
    risk_level = 'READ_ONLY'
    expected_context = @{
        expected_process_pattern = 'chrome.exe|msedge.exe'
        expected_title_pattern = 'DesktopVisual Browser Form v6.8'
        required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
        wrong_page_patterns = @('DV_BROWSER_WRONG_PAGE_MARKER')
        active_protection_patterns = @('captcha','human verification')
        credential_required_patterns = @('password','verification code')
    }
    verification_hint = @{
        verify_type = 'verify_page_loaded'
        expected_marker = 'DV_BROWSER_FORM_BASIC_MARKER'
        expected_url_pattern = 'local_form_basic'
        post_action_reobserve_required = $true
    }
    recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'browser_allowed_url_prefix'; recovery_target = 'expected_url'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $true; stop_if_recovery_fails = $true }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true; stop_on_target_not_unique = $true }
    session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
    evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $true; latency_required = $true }
}

$results = @()
$results += Invoke-Compile 'valid_open_page' $base 0 '"compile_ok":true'

$missingContext = $base.Clone()
$missingContext.Remove('expected_context')
$results += Invoke-Compile 'missing_expected_context' $missingContext 1 'COMPILE_MISSING_EXPECTED_CONTEXT'

$missingAllowed = $base.Clone()
$missingAllowed.Remove('allowed_url_prefix')
$results += Invoke-Compile 'missing_allowed_url_prefix' $missingAllowed 1 'COMPILE_ALLOWED_URL_PREFIX_MISSING'

$submitMissingPolicy = $base.Clone()
$submitMissingPolicy['workflow_id'] = 'schema-submit-missing-policy'
$submitMissingPolicy['workflow_type'] = 'browser_submit_form'
$submitMissingPolicy.Remove('submit_policy')
$submitMissingPolicy['form_spec'] = @{ submit = @{ label = 'Submit' } }
$results += Invoke-Compile 'submit_missing_policy' $submitMissingPolicy 1 'COMPILE_SUBMIT_POLICY_MISSING'

$domAction = $base.Clone()
$domAction['workflow_id'] = 'schema-dom-action'
$domAction['requested_action_backend'] = 'playwright'
$results += Invoke-Compile 'dom_backend_rejected' $domAction 1 'COMPILE_BROWSER_BACKEND_AUTOMATION_REJECTED'

$summary = [pscustomobject]@{
    schema_version = '6.8.0.browser_workflow.schema_selftest'
    result = 'PASS'
    cases = $results
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_workflow_schema_selftest_result.json') -Encoding UTF8
'browser_workflow_schema_selftest PASS'
