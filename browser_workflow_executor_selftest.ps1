param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows\selftest\executor'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function Write-JsonFile($Path, $Object) {
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$spec = @{
    workflow_id = 'executor-dry-run-open'
    task_id = 'executor-dry-run-task'
    workflow_type = 'browser_open_page'
    url = 'file:///D:/testrepo/testwindow/browser_form_v6_8/local_form_basic.html'
    browser = 'auto'
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
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
    session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
    evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $true; latency_required = $true }
}

$input = Join-Path $ArtifactDir 'executor_dry_run.workflow.json'
$result = Join-Path $ArtifactDir 'executor_dry_run.result.json'
$verify = Join-Path $ArtifactDir 'executor_dry_run.verify.json'
$evidence = Join-Path $ArtifactDir 'evidence'
Write-JsonFile $input $spec
& $WinAgent run-browser-workflow --input $input --mode dry-run --output $result --evidence-dir $evidence | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'run-browser-workflow dry-run failed' }
$run = Get-Content -Raw -LiteralPath $result | ConvertFrom-Json
if ($run.final_status -ne 'DRY_RUN_PASS') { throw "expected DRY_RUN_PASS, got $($run.final_status)" }
if (-not $run.workflow_compiled -or -not $run.compiled_step_contract_used -or -not $run.step_contract_validator_used) {
    throw 'executor dry-run did not use compile, StepContract, and validator chain'
}
if (-not $run.compiled_plan_executor_used) { throw 'executor did not call CompiledPlanExecutor' }
if ($run.runtime_session_used) { throw 'dry-run must not execute RuntimeSession' }
if (-not $run.evidence_pack_created) { throw 'executor did not create evidence pack' }
if ($run.runner_only_workflow_logic) { throw 'executor reported runner-only workflow logic' }

& $WinAgent verify-browser-workflow --result $result --output $verify | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'verify-browser-workflow rejected executor dry-run result' }
$verification = Get-Content -Raw -LiteralPath $verify | ConvertFrom-Json
if (-not $verification.verification_ok) { throw 'executor dry-run verification_ok=false' }

$summary = [pscustomobject]@{
    schema_version = '6.8.0.browser_workflow.executor_selftest'
    result = 'PASS'
    dry_run_final_status = $run.final_status
    compiled_plan_executor_used = $run.compiled_plan_executor_used
    step_contract_validator_used = $run.step_contract_validator_used
    verifier_ok = $verification.verification_ok
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_workflow_executor_selftest_result.json') -Encoding UTF8
'browser_workflow_executor_selftest PASS'
