param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\field_locator'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

$spec = @{
    workflow_id = 'locator-contract-check'
    task_id = 'locator-task'
    workflow_type = 'browser_fill_form'
    url = 'file:///D:/testrepo/testwindow/browser_form_v6_8/local_form_basic.html'
    browser = 'auto'
    expected_title_pattern = 'DesktopVisual Browser Form v6.8'
    expected_url_pattern = 'local_form_basic'
    required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
    allowed_origin = 'file://'
    allowed_url_prefix = 'file:///D:/testrepo/testwindow/browser_form_v6_8/'
    risk_level = 'LOW_RISK'
    form_spec = @{
        fields = @(
            @{ field_id = 'first_name'; field_label = 'First name'; placeholder = 'First name'; name = 'first_name'; expected_role = 'Edit'; value = 'Ada'; required = $true },
            @{ field_id = 'bio'; field_label = 'Bio'; placeholder = 'Short bio'; name = 'bio'; expected_role = 'textarea'; value = 'Runtime locator path'; required = $false }
        )
    }
    expected_context = @{
        expected_process_pattern = 'chrome.exe|msedge.exe'
        expected_title_pattern = 'DesktopVisual Browser Form v6.8'
        required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
        wrong_page_patterns = @('DV_BROWSER_WRONG_PAGE_MARKER')
        active_protection_patterns = @('captcha','human verification')
        credential_required_patterns = @('password','verification code')
    }
    verification_hint = @{ verify_type = 'verify_field_value'; expected_marker = 'DV_BROWSER_FORM_BASIC_MARKER'; expected_text = 'First name'; post_action_reobserve_required = $true }
    recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'browser_allowed_url_prefix'; recovery_target = 'expected_url'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $true; stop_if_recovery_fails = $true }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
    session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
    evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $true; latency_required = $true }
}

$input = Join-Path $ArtifactDir 'locator.workflow.json'
$contractPath = Join-Path $ArtifactDir 'locator.step_contract.json'
$spec | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $input -Encoding UTF8
& $WinAgent compile-browser-workflow --input $input --output $contractPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'compile-browser-workflow failed for locator selftest' }
$contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
$fieldSteps = @($contract.contracts | Where-Object { $_.runtime_action -eq 'browser_fill_form' })
if ($fieldSteps.Count -ne 2) { throw "expected 2 browser_fill_form steps, got $($fieldSteps.Count)" }
foreach ($step in $fieldSteps) {
    if ($step.coordinate_source_type -ne 'runtime_locator') { throw 'field step did not use runtime_locator coordinate source' }
    if ($step.requested_action_backend -ne 'runtime_visible_ui') { throw 'field step did not declare runtime_visible_ui backend' }
    if (-not $step.action_precondition.focus_required -or -not $step.action_precondition.mouse_first_required -or -not $step.action_precondition.target_unique_required) {
        throw 'field step missing focus/mouse-first/unique target preconditions'
    }
    if ($step.verification_hint.verify_type -ne 'verify_field_value') { throw 'field step missing verify_field_value verification' }
}

$locatorSource = Get-Content -Raw -LiteralPath (Join-Path $Root 'src\winagent\WebFormFieldLocator.cpp')
foreach ($required in @('ReadUiaTree','nearby_text_to_field','placeholder_text','STOP_TARGET_NOT_UNIQUE','FAIL_FIELD_NOT_FOUND','coordinateSourceType = L"runtime_locator"')) {
    if ($locatorSource -notmatch [regex]::Escape($required)) { throw "locator source missing required path marker: $required" }
}
foreach ($forbidden in @('WebDriver','Playwright','Selenium','CDP','document.querySelector','InvokePattern','SetValue')) {
    if ($locatorSource -match [regex]::Escape($forbidden)) { throw "locator source contains forbidden backend marker: $forbidden" }
}

$summary = [pscustomobject]@{
    schema_version = '6.8.0.web_form_field_locator_selftest'
    result = 'PASS'
    field_steps = $fieldSteps.Count
    runtime_locator_contract = $true
    uia_visible_text_locator_source = $true
    forbidden_backend_absent = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'web_form_field_locator_selftest_result.json') -Encoding UTF8
'web_form_field_locator_selftest PASS'
