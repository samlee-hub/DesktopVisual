param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\compiler'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function Write-JsonFile($Path, $Object) {
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Base-Workflow([string]$Type) {
    return @{
        workflow_id = "compiler-$Type"
        task_id = "compiler-task-$Type"
        workflow_type = $Type
        url = 'file:///D:/testrepo/testwindow/browser_form_v6_8/local_form_basic.html'
        browser = 'chrome'
        expected_title_pattern = 'DesktopVisual Browser Form v6.8'
        expected_url_pattern = 'local_form_basic'
        required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
        allowed_origin = 'file://'
        allowed_url_prefix = 'file:///D:/testrepo/testwindow/browser_form_v6_8/'
        risk_level = if ($Type -eq 'browser_submit_form') { 'LOW_RISK' } else { 'READ_ONLY' }
        expected_context = @{
            expected_process_pattern = 'chrome.exe|msedge.exe'
            expected_title_pattern = 'DesktopVisual Browser Form v6.8'
            required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
            wrong_page_patterns = @('DV_BROWSER_WRONG_PAGE_MARKER')
            active_protection_patterns = @('captcha','human verification')
            credential_required_patterns = @('password','verification code')
        }
        verification_hint = @{
            verify_type = if ($Type -eq 'browser_locate_text') { 'verify_text_present' } elseif ($Type -eq 'browser_submit_form') { 'verify_submit_result' } else { 'verify_page_loaded' }
            expected_marker = 'DV_BROWSER_FORM_BASIC_MARKER'
            expected_text = 'DV browser form'
            expected_url_pattern = 'local_form_basic'
            post_action_reobserve_required = $true
        }
        recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'browser_allowed_url_prefix'; recovery_target = 'expected_url'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $true; stop_if_recovery_fails = $true }
        stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
        session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
        evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $true; latency_required = $true }
    }
}

function Compile-Workflow($Name, $Spec, [int]$ExpectedExit) {
    $input = Join-Path $ArtifactDir "$Name.workflow.json"
    $contract = Join-Path $ArtifactDir "$Name.step_contract.json"
    $stdout = Join-Path $ArtifactDir "$Name.compile.stdout.json"
    Write-JsonFile $input $Spec
    & $WinAgent compile-browser-workflow --input $input --output $contract *> $stdout
    if ($LASTEXITCODE -ne $ExpectedExit) {
        $text = Get-Content -Raw -LiteralPath $stdout
        throw "$Name expected compile exit $ExpectedExit, got $LASTEXITCODE. Output: $text"
    }
    return [pscustomobject]@{ input = $input; contract = $contract; stdout = $stdout }
}

$submit = Base-Workflow 'browser_submit_form'
$submit['form_spec'] = @{
    fields = @(
        @{ field_id = 'first_name'; field_label = 'First name'; expected_role = 'Edit'; value = 'Ada'; required = $true },
        @{ field_id = 'last_name'; field_label = 'Last name'; expected_role = 'Edit'; value = 'Lovelace'; required = $true }
    )
    submit = @{ label = 'Submit'; expected_result_marker = 'DV_BROWSER_FORM_SUCCESS_MARKER'; allow_submit = $true; post_submit_verification_required = $true }
}
$submit['submit_policy'] = @{ allow_submit = $true; require_post_submit_verification = $true; expected_result_marker = 'DV_BROWSER_FORM_SUCCESS_MARKER'; real_commit_allowed = $false }
$compiledSubmit = Compile-Workflow 'submit_form' $submit 0
$contract = Get-Content -Raw -LiteralPath $compiledSubmit.contract | ConvertFrom-Json
if ($contract.contracts.Count -ne 3) { throw "submit_form expected 3 emitted steps, got $($contract.contracts.Count)" }
if (@($contract.contracts | Where-Object { $_.runtime_action -eq 'browser_fill_form' }).Count -ne 2) { throw 'submit_form missing browser_fill_form field steps' }
if (@($contract.contracts | Where-Object { $_.runtime_action -eq 'browser_submit_form' }).Count -ne 1) { throw 'submit_form missing browser_submit_form submit step' }
foreach ($step in $contract.contracts) {
    if (-not $step.expected_context) { throw 'step missing expected_context' }
    if (-not $step.action_precondition) { throw 'step missing action_precondition' }
    if (-not $step.verification_hint) { throw 'step missing verification_hint' }
    if (-not $step.recovery_policy) { throw 'step missing recovery_policy' }
    if (-not $step.stop_policy) { throw 'step missing stop_policy' }
    if (-not $step.evidence_policy) { throw 'step missing evidence_policy' }
    if ($step.runtime_action -in @('browser_fill_form','browser_submit_form')) {
        if (-not $step.action_precondition.focus_required -or -not $step.action_precondition.mouse_first_required) {
            throw 'form step did not require focus and mouse-first verification'
        }
    }
    if ($step.runtime_action -eq 'browser_fill_form' -and $step.verification_hint.verify_type -ne 'verify_field_value') {
        throw 'field step did not require field value verification'
    }
    if ($step.runtime_action -eq 'browser_submit_form' -and $step.verification_hint.verify_type -ne 'verify_submit_result') {
        throw 'submit step did not require post-submit verification'
    }
}

$validateOut = Join-Path $ArtifactDir 'submit_form.validation.json'
& $WinAgent step-contract-validate --input $compiledSubmit.contract --result $validateOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'StepContractValidator rejected compiled Browser workflow contract' }
$validation = Get-Content -Raw -LiteralPath $validateOut | ConvertFrom-Json
if (-not $validation.validation_ok -or -not $validation.runtime_session_compatible) {
    throw 'compiled Browser contract is not RuntimeSession compatible'
}

$blocked = Base-Workflow 'browser_active_protection_stop'
$blocked['risk_level'] = 'ACTIVE_PROTECTION_BLOCKED'
$blocked['verification_hint']['verify_type'] = 'verify_active_protection_stop'
$compiledBlocked = Compile-Workflow 'active_protection_stop' $blocked 0
$blockedContract = Get-Content -Raw -LiteralPath $compiledBlocked.contract | ConvertFrom-Json
if ($blockedContract.contracts[0].executable -ne $false -or $blockedContract.contracts[0].runtime_action -ne 'non_executable_stop') {
    throw 'active protection stop did not compile to a non-executable stop StepContract'
}

$coord = Base-Workflow 'browser_open_page'
$coord['workflow_id'] = 'compiler-direct-coordinate'
$coord['requested_action_backend'] = 'cdp'
$null = Compile-Workflow 'backend_rejected' $coord 1

$summary = [pscustomobject]@{
    schema_version = '6.8.0.browser_workflow.compiler_selftest'
    result = 'PASS'
    step_contract_validator_used = $true
    runtime_session_compatible = $true
    emitted_submit_steps = $contract.contracts.Count
    blocked_stop_non_executable = $true
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_workflow_compiler_selftest_result.json') -Encoding UTF8
'browser_workflow_compiler_selftest PASS'
