param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$RawRoot = Join-Path $EvidenceRoot 'raw\v6_4_0_runner'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

$WinAgent = Join-Path $Root 'bin\winagent.exe'
if (-not (Test-Path $WinAgent)) {
    throw "winagent.exe missing: $WinAgent"
}

function New-ExpectedContext {
    param(
        [string]$Title = 'mock',
        [string[]]$Markers = @('mock'),
        [string[]]$WrongPatterns = @()
    )
    [ordered]@{
        expected_process_pattern = ''
        expected_title_pattern = $Title
        required_markers = $Markers
        wrong_page_patterns = $WrongPatterns
        active_protection_patterns = @()
        credential_required_patterns = @()
        foreground_required = $false
        window_binding_required = $false
    }
}

function New-Precondition {
    param([bool]$TextAllowed = $false, [bool]$MouseFirst = $false, [bool]$TargetRequired = $true)
    [ordered]@{
        target_required = $TargetRequired
        target_unique_required = $false
        target_inside_viewport_required = $false
        target_current_observe_required = $false
        focus_required = $false
        mouse_first_required = $MouseFirst
        text_input_allowed = $TextAllowed
        scroll_allowed = $false
        stale_target_reject_required = $true
    }
}

function New-Verification {
    param(
        [string]$Type = 'verify_marker',
        [string]$Marker = '',
        [string]$Text = '',
        [string]$WindowTitle = '',
        [string]$Url = '',
        [string]$Output = '',
        [string]$Field = ''
    )
    [ordered]@{
        verify_type = $Type
        expected_marker = $Marker
        expected_text = $Text
        expected_window_title = $WindowTitle
        expected_url_pattern = $Url
        expected_output_pattern = $Output
        expected_field_value = $Field
        post_action_reobserve_required = $true
    }
}

function New-Confirmation {
    param([bool]$Required = $false, [string]$Reason = '')
    [ordered]@{
        confirmation_required = $Required
        confirmation_reason = $Reason
        developer_full_access_allowed = $true
        public_release_confirmation_required = $false
        manual_handoff_required = $false
    }
}

function New-Recovery {
    param([bool]$Allowed = $false, [string]$Scope = 'none', [string]$Target = '', [int]$Attempts = 0, [bool]$Resume = $false, [bool]$Replay = $false)
    [ordered]@{
        recovery_allowed = $Allowed
        recovery_scope = $Scope
        recovery_target = $Target
        max_recovery_attempts = $Attempts
        resume_from_checkpoint_allowed = $Resume
        replay_from_checkpoint_allowed = $Replay
        stop_if_recovery_fails = $true
    }
}

function New-StopPolicy {
    [ordered]@{
        stop_on_wrong_context = $true
        stop_on_wrong_field = $true
        stop_on_target_stale = $true
        stop_on_target_not_unique = $true
        stop_on_active_protection = $true
        stop_on_credential_required = $true
        stop_on_unverified_result = $true
        stop_on_runtime_guard_failure = $true
    }
}

function New-SessionPolicy {
    [ordered]@{
        session_required = $true
        session_reuse_allowed = $true
        force_reobserve_before_action = $true
        cache_policy = 'force_reobserve'
        locator_cache_allowed = $false
    }
}

function New-EvidencePolicy {
    [ordered]@{
        raw_evidence_required = $true
        verifier_required = $true
        gate_required = $true
        mouse_evidence_required = $false
        latency_required = $true
    }
}

function New-Step {
    param(
        [string]$TaskId,
        [string]$PlanId,
        [string]$ContractId,
        [string]$StepId,
        [int]$Index,
        [string]$Action,
        [string]$Target,
        [string]$InputText = '',
        [string]$Risk = 'LOW_RISK',
        [object]$ExpectedContext,
        [object]$Verification,
        [object]$Recovery,
        [object]$Confirmation,
        [bool]$TextAllowed = $false,
        [bool]$MouseFirst = $false,
        [bool]$Executable = $true
    )
    if (-not $ExpectedContext) { $ExpectedContext = New-ExpectedContext -Markers @($Target) }
    if (-not $Verification) { $Verification = New-Verification -Marker $Target }
    if (-not $Recovery) { $Recovery = New-Recovery }
    if (-not $Confirmation) { $Confirmation = New-Confirmation }
    [ordered]@{
        contract_id = $ContractId
        task_id = $TaskId
        plan_id = $PlanId
        step_id = $StepId
        step_index = $Index
        step_type = 'action'
        runtime_action = $Action
        target = $Target
        input_text = $InputText
        expected_context = $ExpectedContext
        action_precondition = New-Precondition -TextAllowed:$TextAllowed -MouseFirst:$MouseFirst
        verification_hint = $Verification
        risk_level = $Risk
        confirmation_policy = $Confirmation
        recovery_policy = $Recovery
        stop_policy = New-StopPolicy
        session_policy = New-SessionPolicy
        evidence_policy = New-EvidencePolicy
        created_at = '2026-06-14T00:00:00Z'
        compiler_version = '6.3.0'
        executable = $Executable
    }
}

function New-Contract {
    param([object[]]$Steps)
    [ordered]@{
        schema_version = '6.3.0.step_contract'
        contracts = $Steps
    }
}

function Save-Json($Path, $Object) {
    $Object | ConvertTo-Json -Depth 40 | Set-Content -Encoding UTF8 $Path
}

function Invoke-Agent {
    param([string[]]$Arguments, [string]$Stdout, [string]$Stderr)
    & $WinAgent @Arguments > $Stdout 2> $Stderr
    return $LASTEXITCODE
}

function Run-Case {
    param(
        [string]$Group,
        [string]$Name,
        [object]$Contract,
        [string]$Mode = 'execute-local-safe',
        [bool]$UseRunAgentTask = $false,
        [bool]$ExpectSuccess = $true
    )
    $CaseDir = Join-Path $RawRoot "$Group\$Name"
    New-Item -ItemType Directory -Force -Path $CaseDir | Out-Null
    $ContractPath = Join-Path $CaseDir 'step_contract.json'
    $ResultPath = Join-Path $CaseDir 'execution_result.json'
    $StdoutPath = Join-Path $CaseDir 'execute.stdout.json'
    $StderrPath = Join-Path $CaseDir 'execute.stderr.txt'
    Save-Json $ContractPath $Contract
    if ($UseRunAgentTask) {
        $RequestPath = Join-Path $CaseDir 'agent_task_request.json'
        Save-Json $RequestPath ([ordered]@{
            schema_version = '6.4.0.agent_task_request'
            task_id = $Contract.contracts[0].task_id
            source = 'v6_4_0_runner'
            step_contract_path = $ContractPath
        })
        $exit = Invoke-Agent -Arguments @('run-agent-task','--request',$RequestPath,'--mode',$Mode,'--output',$ResultPath,'--evidence-dir',$CaseDir) -Stdout $StdoutPath -Stderr $StderrPath
    } else {
        $exit = Invoke-Agent -Arguments @('execute-step-contract','--input',$ContractPath,'--mode',$Mode,'--output',$ResultPath,'--evidence-dir',$CaseDir) -Stdout $StdoutPath -Stderr $StderrPath
    }
    [ordered]@{
        group = $Group
        name = $Name
        mode = $Mode
        expect_success = $ExpectSuccess
        exit_code = $exit
        contract = $ContractPath
        result = $ResultPath
        stdout = $StdoutPath
        stderr = $StderrPath
        evidence_dir = $CaseDir
    }
}

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Run-Case -Group 'positive' -Name 'explorer_open_path' -UseRunAgentTask $true -Contract (New-Contract @(
    (New-Step -TaskId 'task-explorer-open-path' -PlanId 'plan-explorer' -ContractId 'contract-explorer' -StepId 'open-path' -Index 0 -Action 'explorer_open_path' -Target 'D:\testrepo\testwindow testwindow' -ExpectedContext (New-ExpectedContext -Title 'testwindow' -Markers @('testwindow')) -Verification (New-Verification -Type 'verify_marker' -Marker 'testwindow'))
))))

$results.Add((Run-Case -Group 'positive' -Name 'browser_open_page' -Contract (New-Contract @(
    (New-Step -TaskId 'task-browser-open' -PlanId 'plan-browser-open' -ContractId 'contract-browser-open' -StepId 'open-page' -Index 0 -Action 'browser_open_page' -Target 'file:///mock-page.html page-marker' -ExpectedContext (New-ExpectedContext -Title 'mock-page' -Markers @('page-marker') -WrongPatterns @('wrong-page')) -Verification (New-Verification -Type 'verify_url_or_page_marker' -Marker 'page-marker' -Url 'file:///mock-page.html'))
))))

$formSteps = @(
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'open-form' -Index 0 -Action 'browser_open_page' -Target 'file:///mock-form.html form-marker' -ExpectedContext (New-ExpectedContext -Title 'mock-form' -Markers @('form-marker')) -Verification (New-Verification -Type 'verify_marker' -Marker 'form-marker')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'click-field1' -Index 1 -Action 'click' -Target 'field1' -Verification (New-Verification -Type 'verify_marker' -Marker 'field1')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'type-field1' -Index 2 -Action 'type' -Target 'field1 alpha' -InputText 'alpha' -TextAllowed $true -Verification (New-Verification -Type 'verify_field_value' -Field 'alpha')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'verify-field1' -Index 3 -Action 'verify' -Target 'field1 alpha' -Verification (New-Verification -Type 'verify_field_value' -Field 'alpha')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'click-field2' -Index 4 -Action 'click' -Target 'field2' -Verification (New-Verification -Type 'verify_marker' -Marker 'field2')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'type-field2' -Index 5 -Action 'type' -Target 'field2 beta' -InputText 'beta' -TextAllowed $true -Verification (New-Verification -Type 'verify_field_value' -Field 'beta')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'verify-field2' -Index 6 -Action 'verify' -Target 'field2 beta' -Verification (New-Verification -Type 'verify_field_value' -Field 'beta')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'click-submit' -Index 7 -Action 'click_submit' -Target 'submit result-marker' -Verification (New-Verification -Type 'verify_marker' -Marker 'submit')),
    (New-Step -TaskId 'task-browser-form' -PlanId 'plan-browser-form' -ContractId 'contract-browser-form' -StepId 'verify-result' -Index 8 -Action 'verify' -Target 'result-marker' -Verification (New-Verification -Type 'verify_marker' -Marker 'result-marker'))
)
$results.Add((Run-Case -Group 'positive' -Name 'browser_fill_form' -Contract (New-Contract $formSteps)))

$mailSteps = @(
    (New-Step -TaskId 'task-mail-draft' -PlanId 'plan-mail-draft' -ContractId 'contract-mail-draft' -StepId 'recipient' -Index 0 -Action 'type_text' -Target 'recipient dev@example.test' -InputText 'dev@example.test' -Risk 'REVERSIBLE_DRAFT' -TextAllowed $true -Verification (New-Verification -Type 'verify_field_value' -Field 'dev@example.test')),
    (New-Step -TaskId 'task-mail-draft' -PlanId 'plan-mail-draft' -ContractId 'contract-mail-draft' -StepId 'subject' -Index 1 -Action 'type_text' -Target 'subject hello' -InputText 'hello' -Risk 'REVERSIBLE_DRAFT' -TextAllowed $true -Verification (New-Verification -Type 'verify_field_value' -Field 'hello')),
    (New-Step -TaskId 'task-mail-draft' -PlanId 'plan-mail-draft' -ContractId 'contract-mail-draft' -StepId 'body' -Index 2 -Action 'local_mock_mail_fill' -Target 'body draft-body' -InputText 'draft-body' -Risk 'REVERSIBLE_DRAFT' -TextAllowed $true -Verification (New-Verification -Type 'verify_field_value' -Field 'draft-body')),
    (New-Step -TaskId 'task-mail-draft' -PlanId 'plan-mail-draft' -ContractId 'contract-mail-draft' -StepId 'verify-draft' -Index 3 -Action 'verify' -Target 'draft complete' -Risk 'REVERSIBLE_DRAFT' -Verification (New-Verification -Type 'verify_marker' -Marker 'draft'))
)
$results.Add((Run-Case -Group 'positive' -Name 'local_mock_mail_fill' -Contract (New-Contract $mailSteps)))

$recoveryStep = New-Step -TaskId 'task-recovery' -PlanId 'plan-recovery' -ContractId 'contract-recovery' -StepId 'recover-wrong-context' -Index 0 -Action 'browser_open_page' -Target 'wrong-context mock-recover' -ExpectedContext (New-ExpectedContext -Title 'mock' -Markers @('mock-recover')) -Verification (New-Verification -Type 'verify_marker' -Marker 'mock-recover') -Recovery (New-Recovery -Allowed $true -Scope 'local_mock' -Target 'local mock page' -Attempts 1 -Resume $true)
$results.Add((Run-Case -Group 'positive' -Name 'safe_recovery_during_execution' -Contract (New-Contract @($recoveryStep))))

$results.Add((Run-Case -Group 'positive' -Name 'dry_run_no_runtime_execution' -Mode 'dry-run' -Contract (New-Contract @(
    (New-Step -TaskId 'task-dry-run' -PlanId 'plan-dry' -ContractId 'contract-dry' -StepId 'dry-step' -Index 0 -Action 'observe' -Target 'dry marker' -Risk 'READ_ONLY' -Verification (New-Verification -Type 'verify_marker' -Marker 'dry'))
))))

$validBase = New-Step -TaskId 'task-negative' -PlanId 'plan-negative' -ContractId 'contract-negative' -StepId 'negative-step' -Index 0 -Action 'observe' -Target 'negative marker' -Risk 'LOW_RISK' -Verification (New-Verification -Type 'verify_marker' -Marker 'negative')
$invalidDir = Join-Path $RawRoot 'negative\invalid_json'
New-Item -ItemType Directory -Force -Path $invalidDir | Out-Null
$invalidPath = Join-Path $invalidDir 'step_contract.json'
'{"schema_version":"6.3.0.step_contract","contracts":[' | Set-Content -Encoding UTF8 $invalidPath
$invalidResult = Join-Path $invalidDir 'execution_result.json'
$invalidExit = Invoke-Agent -Arguments @('execute-step-contract','--input',$invalidPath,'--mode','execute-local-safe','--output',$invalidResult,'--evidence-dir',$invalidDir) -Stdout (Join-Path $invalidDir 'execute.stdout.json') -Stderr (Join-Path $invalidDir 'execute.stderr.txt')
$results.Add([ordered]@{ group='negative'; name='invalid_step_contract'; mode='execute-local-safe'; expect_success=$false; exit_code=$invalidExit; contract=$invalidPath; result=$invalidResult; evidence_dir=$invalidDir })

$missingVerification = New-Contract @($validBase)
$missingVerification.contracts[0].Remove('verification_hint')
$results.Add((Run-Case -Group 'negative' -Name 'missing_verification_hint' -ExpectSuccess $false -Contract $missingVerification))

$missingContext = New-Contract @($validBase)
$missingContext.contracts[0].Remove('expected_context')
$results.Add((Run-Case -Group 'negative' -Name 'missing_expected_context' -ExpectSuccess $false -Contract $missingContext))

$blockedActive = New-Step -TaskId 'task-active-blocked' -PlanId 'plan-active' -ContractId 'contract-active' -StepId 'active' -Index 0 -Action 'stop' -Target 'active protection' -Risk 'ACTIVE_PROTECTION_BLOCKED' -Executable $false -Verification (New-Verification -Type 'verify_marker' -Marker 'active')
$results.Add((Run-Case -Group 'negative' -Name 'active_protection_blocked' -ExpectSuccess $false -Contract (New-Contract @($blockedActive))))

$blockedCredential = New-Step -TaskId 'task-credential-blocked' -PlanId 'plan-credential' -ContractId 'contract-credential' -StepId 'credential' -Index 0 -Action 'stop' -Target 'credential required' -Risk 'CREDENTIAL_REQUIRED_BLOCKED' -Executable $false -Verification (New-Verification -Type 'verify_marker' -Marker 'credential')
$results.Add((Run-Case -Group 'negative' -Name 'credential_required_blocked' -ExpectSuccess $false -Contract (New-Contract @($blockedCredential))))

$realCommit = New-Step -TaskId 'task-real-commit' -PlanId 'plan-real' -ContractId 'contract-real' -StepId 'real' -Index 0 -Action 'click_submit' -Target 'real commit send' -Risk 'REAL_COMMIT' -Confirmation (New-Confirmation -Required $true -Reason 'real commit') -Verification (New-Verification -Type 'verify_marker' -Marker 'send')
$results.Add((Run-Case -Group 'negative' -Name 'real_commit_without_confirmation' -ExpectSuccess $false -Contract (New-Contract @($realCommit))))

$destructive = New-Step -TaskId 'task-destructive' -PlanId 'plan-destructive' -ContractId 'contract-destructive' -StepId 'delete' -Index 0 -Action 'click_submit' -Target 'delete file' -Risk 'DESTRUCTIVE' -Confirmation (New-Confirmation -Required $true -Reason 'delete file') -Verification (New-Verification -Type 'verify_file_deleted' -Text 'D:\tmp\nonexistent-v6-4.txt')
$results.Add((Run-Case -Group 'negative' -Name 'delete_file_without_confirmation' -ExpectSuccess $false -Contract (New-Contract @($destructive))))

$direct = New-Step -TaskId 'task-direct' -PlanId 'plan-direct' -ContractId 'contract-direct' -StepId 'direct' -Index 0 -Action 'click' -Target 'x=10 y=20' -Verification (New-Verification -Type 'verify_marker' -Marker 'x=10')
$results.Add((Run-Case -Group 'negative' -Name 'direct_coordinate_unsafe' -ExpectSuccess $false -Contract (New-Contract @($direct))))

$wrongSteps = @(
    (New-Step -TaskId 'task-wrong-context' -PlanId 'plan-wrong' -ContractId 'contract-wrong' -StepId 'wrong-context-first' -Index 0 -Action 'browser_open_page' -Target 'wrong-context first' -Verification (New-Verification -Type 'verify_marker' -Marker 'first')),
    (New-Step -TaskId 'task-wrong-context' -PlanId 'plan-wrong' -ContractId 'contract-wrong' -StepId 'should-not-run' -Index 1 -Action 'verify' -Target 'later' -Verification (New-Verification -Type 'verify_marker' -Marker 'later'))
)
$results.Add((Run-Case -Group 'negative' -Name 'wrong_context_stops_later_steps' -ExpectSuccess $false -Contract (New-Contract $wrongSteps)))

$verifyFailSteps = @(
    (New-Step -TaskId 'task-verify-fail' -PlanId 'plan-verify-fail' -ContractId 'contract-verify-fail' -StepId 'verify-fails' -Index 0 -Action 'observe' -Target 'actual marker' -Verification (New-Verification -Type 'verify_marker' -Marker 'missing-marker')),
    (New-Step -TaskId 'task-verify-fail' -PlanId 'plan-verify-fail' -ContractId 'contract-verify-fail' -StepId 'should-not-run' -Index 1 -Action 'observe' -Target 'later marker' -Verification (New-Verification -Type 'verify_marker' -Marker 'later'))
)
$results.Add((Run-Case -Group 'negative' -Name 'verification_failure_stops_later_steps' -ExpectSuccess $false -Contract (New-Contract $verifyFailSteps)))

$staleSteps = @(
    (New-Step -TaskId 'task-stale' -PlanId 'plan-stale' -ContractId 'contract-stale' -StepId 'stale' -Index 0 -Action 'click' -Target 'stale-target marker' -Verification (New-Verification -Type 'verify_marker' -Marker 'marker')),
    (New-Step -TaskId 'task-stale' -PlanId 'plan-stale' -ContractId 'contract-stale' -StepId 'should-not-run' -Index 1 -Action 'verify' -Target 'later' -Verification (New-Verification -Type 'verify_marker' -Marker 'later'))
)
$results.Add((Run-Case -Group 'negative' -Name 'stale_target_rejected' -ExpectSuccess $false -Contract (New-Contract $staleSteps)))

$runnerResult = [ordered]@{
    schema_version = '6.4.0.runtime_task_execution.runner'
    generated_at = (Get-Date).ToString('o')
    status = 'RAW_COMPLETED_UNVERIFIED'
    result_is_pass = $false
    runtime_execution_runner_only = $false
    cases = $results
}
$runnerResultPath = Join-Path $EvidenceRoot 'v6_4_0_runner_raw_result.json'
Save-Json $runnerResultPath $runnerResult

$lines = @('# v6.4.0 Runtime Task Execution Runner Raw Report','')
$lines += '- Status: RAW_COMPLETED_UNVERIFIED'
$lines += '- Runner result is not PASS.'
$lines += ''
foreach ($case in $results) {
    $lines += "- $($case.group)/$($case.name): exit=$($case.exit_code) expect_success=$($case.expect_success)"
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_4_0_runner_raw_report.md')

"RAW_COMPLETED_UNVERIFIED"
exit 0
