param(
    [string]$Root = $PSScriptRoot,
    [string]$FixtureRoot = 'D:\testrepo\testwindow\browser_form_v6_8'
)

$ErrorActionPreference = 'Continue'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.8.0_browser_and_web_form_agent_workflows'
$RunDir = Join-Path $ArtifactDir 'runner'
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

$fixtureSetup = & (Join-Path $Root 'v6_8_0_browser_fixture_setup.ps1') -FixtureRoot $FixtureRoot
$serverScript = Join-Path $FixtureRoot 'localhost_server.ps1'
$server = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$serverScript,'-Root',$FixtureRoot,'-Port','8768')
Start-Sleep -Milliseconds 700

function FileUrl($Name) {
    return 'file:///' + ((Join-Path $FixtureRoot $Name) -replace '\\','/')
}

function BaseSpec($Id, $Type, $Url, $Marker) {
    return @{
        workflow_id = $Id
        task_id = "$Id-task"
        workflow_type = $Type
        url = $Url
        browser = 'auto'
        expected_title_pattern = 'DesktopVisual Browser Form v6.8'
        expected_url_pattern = if ($Url -like 'file:*') { [IO.Path]::GetFileName(([uri]$Url).LocalPath) } else { 'localhost|example' }
        required_markers = @($Marker)
        allowed_origin = if ($Url -like 'http://localhost*') { 'http://localhost:8768' } elseif ($Url -like 'http*') { 'https://example.com' } else { 'file://' }
        allowed_url_prefix = if ($Url -like 'http://localhost*') { 'http://localhost:8768/' } elseif ($Url -like 'http*') { 'https://example.com/' } else { 'file:///' + ($FixtureRoot -replace '\\','/') + '/' }
        risk_level = 'READ_ONLY'
        expected_context = @{
            expected_process_pattern = 'chrome.exe|msedge.exe'
            expected_title_pattern = 'DesktopVisual Browser Form v6.8|Example Domain|Wrong page|Security verification|Sign in required'
            required_markers = @($Marker)
            wrong_page_patterns = @('DV_BROWSER_WRONG_PAGE_MARKER')
            active_protection_patterns = @('CAPTCHA','human verification','bot challenge')
            credential_required_patterns = @('Password','Verification code')
        }
        verification_hint = @{ verify_type = 'verify_page_loaded'; expected_marker = $Marker; expected_text = $Marker; expected_url_pattern = 'local|localhost|example'; post_action_reobserve_required = $true }
        recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'browser_allowed_url_prefix'; recovery_target = 'expected_url'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $true; stop_if_recovery_fails = $true }
        stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
        session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
        evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $true; latency_required = $true }
    }
}

function RunCase($Name, $Spec, $Mode = 'execute-local-safe') {
    $caseDir = Join-Path $RunDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $input = Join-Path $caseDir 'workflow.json'
    $output = Join-Path $caseDir 'execution_result.json'
    $stdout = Join-Path $caseDir 'stdout.json'
    $Spec | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $input -Encoding UTF8
    & $WinAgent run-browser-workflow --input $input --mode $Mode --output $output --evidence-dir (Join-Path $caseDir 'evidence') *> $stdout
    [pscustomobject]@{
        name = $Name
        exit_code = $LASTEXITCODE
        workflow = $input
        result = $output
        stdout = $stdout
        evidence = Join-Path $caseDir 'evidence'
    }
}

$cases = @()
try {
    $cases += RunCase 'case_01_browser_open_local_page' (BaseSpec 'case-01-open-local' 'browser_open_page' (FileUrl 'local_form_basic.html') 'DV_BROWSER_FORM_BASIC_MARKER')
    $cases += RunCase 'case_02_browser_open_localhost_page' (BaseSpec 'case-02-open-localhost' 'browser_open_page' 'http://localhost:8768/local_form_basic.html' 'DV_BROWSER_FORM_BASIC_MARKER')

    $basic = BaseSpec 'case-03-fill-basic' 'browser_submit_form' (FileUrl 'local_form_basic.html') 'DV_BROWSER_FORM_BASIC_MARKER'
    $basic.risk_level = 'LOW_RISK'
    $basic.form_spec = @{ fields = @(@{ field_id='first_name'; field_label='First name'; placeholder='First name'; name='first_name'; expected_role='Edit'; value='Ada'; required=$true }, @{ field_id='last_name'; field_label='Last name'; placeholder='Last name'; name='last_name'; expected_role='Edit'; value='Lovelace'; required=$true }); submit = @{ label='Submit'; expected_result_marker='DV_BROWSER_FORM_SUCCESS_MARKER'; allow_submit=$true; post_submit_verification_required=$true } }
    $basic.submit_policy = @{ allow_submit=$true; require_post_submit_verification=$true; expected_result_marker='DV_BROWSER_FORM_SUCCESS_MARKER'; real_commit_allowed=$false }
    $basic.verification_hint.verify_type = 'verify_submit_result'
    $basic.verification_hint.expected_result_marker = 'DV_BROWSER_FORM_SUCCESS_MARKER'
    $cases += RunCase 'case_03_browser_fill_form_basic' $basic

    $long = BaseSpec 'case-04-long-scroll' 'browser_submit_form' (FileUrl 'local_form_long_scroll.html') 'DV_BROWSER_FORM_BASIC_MARKER'
    $long.risk_level = 'LOW_RISK'
    $long.form_spec = @{ fields = @(@{ field_id='scroll_name'; field_label='Scroll name'; placeholder='Scroll name'; name='scroll_name'; expected_role='Edit'; value='Scrolled Ada'; required=$true }); submit = @{ label='Submit'; expected_result_marker='DV_BROWSER_FORM_SUCCESS_MARKER'; allow_submit=$true; post_submit_verification_required=$true } }
    $long.submit_policy = @{ allow_submit=$true; require_post_submit_verification=$true; expected_result_marker='DV_BROWSER_FORM_SUCCESS_MARKER'; real_commit_allowed=$false }
    $long.verification_hint.verify_type = 'verify_submit_result'
    $long.verification_hint.expected_result_marker = 'DV_BROWSER_FORM_SUCCESS_MARKER'
    $cases += RunCase 'case_04_browser_fill_form_long_scroll' $long

    $recovery = $basic.Clone()
    $recovery.workflow_id = 'case-05-wrong-page-recovery'
    $recovery.workflow_type = 'browser_wrong_page_recovery'
    $recovery.url = FileUrl 'local_form_wrong_page.html'
    $recovery.required_markers = @('DV_BROWSER_FORM_BASIC_MARKER')
    $recovery.recovery_policy = @{ recovery_allowed=$true; recovery_scope='browser_allowed_url_prefix'; recovery_target='expected_url'; recovery_url=(FileUrl 'local_form_basic.html'); max_recovery_attempts=1; resume_from_checkpoint_allowed=$true; replay_from_checkpoint_allowed=$true; stop_if_recovery_fails=$true }
    $cases += RunCase 'case_05_browser_wrong_page_recovery' $recovery

    $external = BaseSpec 'case-06-external-readonly' 'browser_read_page' 'https://example.com/' 'Example Domain'
    $external.expected_title_pattern = 'Example Domain'
    $external.expected_url_pattern = 'example.com'
    $external.expected_context.expected_title_pattern = 'Example Domain'
    $external.expected_context.required_markers = @('Example Domain')
    $external.verification_hint.expected_text = 'Example Domain'
    $cases += RunCase 'case_06_ordinary_external_web_readonly_diagnostic' $external

    $missing = $basic.Clone()
    $missing.workflow_id = 'negative-missing-field'
    $missing.url = FileUrl 'local_form_missing_field.html'
    $missing.form_spec = @{ fields = @(@{ field_id='does_not_exist'; field_label='Does not exist'; placeholder='Does not exist'; name='does_not_exist'; expected_role='Edit'; value='Nope'; required=$true }); submit = @{ label='Submit'; expected_result_marker='DV_BROWSER_FORM_SUCCESS_MARKER'; allow_submit=$true; post_submit_verification_required=$true } }
    $cases += RunCase 'negative_missing_field' $missing

    $ambSubmit = $basic.Clone()
    $ambSubmit.workflow_id = 'negative-ambiguous-submit'
    $ambSubmit.url = FileUrl 'local_form_ambiguous_submit.html'
    $ambSubmit.form_spec = @{ fields = @(@{ field_id='first_name'; field_label='First name'; placeholder='First name'; name='first_name'; expected_role='Edit'; value='Ada'; required=$true }); submit = @{ label='Submit'; expected_result_marker='DV_BROWSER_FORM_SUCCESS_MARKER'; allow_submit=$true; post_submit_verification_required=$true } }
    $cases += RunCase 'negative_ambiguous_submit' $ambSubmit

    $active = BaseSpec 'negative-active-protection' 'browser_active_protection_stop' (FileUrl 'local_form_active_protection_mock.html') 'DV_BROWSER_ACTIVE_PROTECTION_MARKER'
    $active.risk_level = 'ACTIVE_PROTECTION_BLOCKED'
    $active.verification_hint.verify_type = 'verify_active_protection_stop'
    $cases += RunCase 'negative_active_protection_stop' $active

    $cred = BaseSpec 'negative-credential-required' 'browser_credential_required_stop' (FileUrl 'local_form_credential_required_mock.html') 'DV_BROWSER_CREDENTIAL_REQUIRED_MARKER'
    $cred.risk_level = 'CREDENTIAL_REQUIRED_BLOCKED'
    $cred.verification_hint.verify_type = 'verify_credential_required_stop'
    $cases += RunCase 'negative_credential_required_stop' $cred
} finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
}

$runnerResult = [pscustomobject]@{
    schema_version = '6.8.0.browser_form_workflow.runner'
    result = 'RAW_COMPLETED_UNVERIFIED'
    fixture_setup = $fixtureSetup
    localhost_started = $true
    localhost_port = 8768
    cases = $cases
    cleanup = @{ localhost_stopped = $true }
}
$runnerResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_form_runner_result.json') -Encoding UTF8
$cases | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'browser_form_runner_cases.json') -Encoding UTF8
'v6_8_0_browser_form_workflow_runner RAW_COMPLETED_UNVERIFIED'
