param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.3.0_plan_draft_to_step_contract_compiler'
$RawRoot = Join-Path $ArtifactRoot 'raw\v6_3_0_runner'
$RunnerResultPath = Join-Path $ArtifactRoot 'v6_3_0_runner_raw_result.json'
$RunnerReportPath = Join-Path $ArtifactRoot 'v6_3_0_runner_raw_report.md'

New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Write-TextFile {
    param([string]$Path, [string]$Text)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Text | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Invoke-WinAgentJson {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0), [string]$OutPath = '')
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($OutPath) { Write-TextFile $OutPath $text | Out-Null }
    $json = $null
    try { $json = $text | ConvertFrom-Json } catch {}
    [pscustomobject]@{
        args = $Arguments
        exit = $exit
        allowed_exit = ($AllowedExitCodes -contains $exit)
        json = $json
        text = $text
    }
}

function New-ExpectedContext {
    param([string]$Process = '(msedge.exe|chrome.exe)', [string]$Title = 'DesktopVisual Mock', [string[]]$Markers = @('DesktopVisual Mock'))
    [ordered]@{
        expected_process_pattern = $Process
        expected_title_pattern = $Title
        required_markers = $Markers
        wrong_page_patterns = @('login', 'captcha', 'wrong page')
        active_protection_patterns = @('captcha', 'human verification', 'automation detected')
        credential_required_patterns = @('password', 'login required', 'credential required')
        foreground_required = $true
        window_binding_required = $true
    }
}

function New-DraftStep {
    param(
        [string]$Id,
        [string]$Summary,
        [string]$Action,
        [string]$Target,
        [string]$InputText = '',
        [string]$Expected = '',
        [string]$Risk = 'LOW_RISK',
        [string]$Confirmation = '',
        [string]$Recovery = 'reobserve only; stop on protection or credentials',
        [string]$Verification = ''
    )
    if ([string]::IsNullOrWhiteSpace($Verification)) { $Verification = $Expected }
    [ordered]@{
        draft_step_id = $Id
        natural_language_summary = $Summary
        proposed_action = $Action
        target_description = $Target
        input_text = $InputText
        expected_result = $Expected
        risk_hint = $Risk
        confirmation_hint = $Confirmation
        recovery_hint = $Recovery
        verification_hint = $Verification
    }
}

function New-Plan {
    param(
        [string]$CaseName,
        [string]$Intent,
        [object[]]$Steps,
        [string]$Risk = 'LOW_RISK',
        [object]$Context = $null,
        [bool]$DeveloperFullAccess = $false,
        [bool]$RequiresConfirmation = $false
    )
    if ($null -eq $Context) { $Context = New-ExpectedContext }
    [ordered]@{
        schema_version = '6.3.0.agent_plan_draft'
        plan_id = "plan-$CaseName"
        task_id = "task-$CaseName"
        intent = $Intent
        goal = $CaseName
        steps = @($Steps)
        risk_summary = $Risk
        allowed_scope = 'local_mock_or_declared_developer_scope'
        developer_full_access = $DeveloperFullAccess
        requires_confirmation = $RequiresConfirmation
        expected_context_summary = $Context
        verification_summary = 'each step has verification_hint'
        recovery_summary = 'bounded reobserve only; stop on active protection or credentials'
    }
}

function Invoke-PositiveCase {
    param([string]$Name, [object]$Plan)
    $dir = Join-Path $RawRoot "positive\$Name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $planPath = Write-JsonFile (Join-Path $dir 'plan_draft.json') $Plan
    $contractPath = Join-Path $dir 'step_contract.json'
    $diagnosticsPath = Join-Path $dir 'compile_diagnostics.json'
    $validationPath = Join-Path $dir 'validation_result.json'
    $sessionStepsPath = Join-Path $dir 'session_steps.json'
    $compile = Invoke-WinAgentJson @('plan-compile', '--input', $planPath, '--output', $contractPath, '--diagnostics', $diagnosticsPath) @(0) (Join-Path $dir 'compile.stdout.json')
    $validate = Invoke-WinAgentJson @('step-contract-validate', '--input', $contractPath, '--result', $validationPath) @(0) (Join-Path $dir 'validate.stdout.json')
    $dryRun = Invoke-WinAgentJson @('step-contract-dry-run', '--input', $contractPath, '--session-steps-output', $sessionStepsPath) @(0) (Join-Path $dir 'dry_run.stdout.json')
    [ordered]@{
        name = $Name
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        plan_draft = $planPath
        step_contract = $contractPath
        diagnostics = $diagnosticsPath
        validation_result = $validationPath
        session_steps = $sessionStepsPath
        compile = $compile
        validate = $validate
        dry_run = $dryRun
    }
}

function Invoke-NegativeCompileCase {
    param([string]$Name, [object]$PlanOrText, [string]$ExpectedCode, [bool]$RawText = $false)
    $dir = Join-Path $RawRoot "negative_compile\$Name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $planPath = Join-Path $dir 'plan_draft.json'
    if ($RawText) { Write-TextFile $planPath ([string]$PlanOrText) | Out-Null } else { Write-JsonFile $planPath $PlanOrText | Out-Null }
    $contractPath = Join-Path $dir 'step_contract.json'
    $diagnosticsPath = Join-Path $dir 'compile_diagnostics.json'
    $compile = Invoke-WinAgentJson @('plan-compile', '--input', $planPath, '--output', $contractPath, '--diagnostics', $diagnosticsPath) @(1) (Join-Path $dir 'compile.stdout.json')
    [ordered]@{
        name = $Name
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        expected_error_code = $ExpectedCode
        plan_draft = $planPath
        step_contract = $contractPath
        diagnostics = $diagnosticsPath
        compile = $compile
    }
}

function Invoke-NegativeValidationCase {
    param([string]$Name, [object]$Contract, [string]$ExpectedPattern)
    $dir = Join-Path $RawRoot "negative_validation\$Name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $contractPath = Write-JsonFile (Join-Path $dir 'step_contract.json') $Contract
    $validationPath = Join-Path $dir 'validation_result.json'
    $validate = Invoke-WinAgentJson @('step-contract-validate', '--input', $contractPath, '--result', $validationPath) @(1) (Join-Path $dir 'validate.stdout.json')
    [ordered]@{
        name = $Name
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        expected_pattern = $ExpectedPattern
        step_contract = $contractPath
        validation_result = $validationPath
        validate = $validate
    }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe: $WinAgent"
}

$positive = [ordered]@{}

$positive.explorer_open_path = Invoke-PositiveCase 'explorer_open_path' (New-Plan 'explorer_open_path' 'explorer_open_path' @(
    (New-DraftStep 'open_path' 'Open D:\testrepo\testwindow.' 'explorer_open_path' 'D:\testrepo\testwindow' '' 'path visible' 'LOW_RISK' '' 'reobserve only; stop on protection' 'path visible')
) 'LOW_RISK' (New-ExpectedContext 'explorer.exe' 'testwindow' @('testwindow')))

$positive.browser_open_page = Invoke-PositiveCase 'browser_open_page' (New-Plan 'browser_open_page' 'browser_open_page' @(
    (New-DraftStep 'normalize_browser_surface' 'Normalize browser surface before page work.' 'browser_surface_normalize' 'browser surface' '' 'browser surface normalized' 'LOW_RISK' '' 'reobserve only; stop on wrong page' 'browser surface normalized'),
    (New-DraftStep 'open_page' 'Open a normal local page.' 'browser_open_page' 'file:///D:/testrepo/testwindow/desktopvisual_mail_mock.html' '' 'page marker visible' 'LOW_RISK' '' 'reobserve only; stop on wrong page' 'page marker visible')
) 'LOW_RISK' (New-ExpectedContext '(msedge.exe|chrome.exe)' 'DesktopVisual Local Mail Mock' @('DesktopVisual Local Mail Mock')))

$formSteps = @(
    (New-DraftStep 'open_form_page' 'Open mock form page.' 'browser_open_page' 'file:///D:/testrepo/testwindow/desktopvisual_mail_mock.html' '' 'form visible' 'LOW_RISK' '' 'reobserve only' 'form visible'),
    (New-DraftStep 'click_field1' 'Click field 1.' 'click_field' 'uia:automation_id=recipient' '' 'recipient focused' 'LOW_RISK' '' 'reobserve only' 'recipient focused'),
    (New-DraftStep 'type_field1' 'Type field 1.' 'type_text' 'uia:automation_id=recipient' 'dv63@example.test' 'dv63@example.test' 'LOW_RISK' '' 'reobserve only' 'dv63@example.test'),
    (New-DraftStep 'verify_field1' 'Verify field 1.' 'verify_field' 'uia:automation_id=recipient' '' 'dv63@example.test' 'LOW_RISK' '' 'reobserve only' 'dv63@example.test'),
    (New-DraftStep 'click_field2' 'Click field 2.' 'click_field' 'uia:automation_id=body' '' 'body focused' 'LOW_RISK' '' 'reobserve only' 'body focused'),
    (New-DraftStep 'type_field2' 'Type field 2.' 'type_text' 'uia:automation_id=body' 'hello from v6.3' 'hello from v6.3' 'LOW_RISK' '' 'reobserve only' 'hello from v6.3'),
    (New-DraftStep 'verify_field2' 'Verify field 2.' 'verify_field' 'uia:automation_id=body' '' 'hello from v6.3' 'LOW_RISK' '' 'reobserve only' 'hello from v6.3'),
    (New-DraftStep 'click_submit' 'Click submit.' 'click_submit' 'uia:automation_id=sendButton' '' 'submitted' 'LOW_RISK' '' 'reobserve only' 'submitted'),
    (New-DraftStep 'verify_result' 'Verify result.' 'verify_result' 'result marker' '' 'Mock sent successfully' 'LOW_RISK' '' 'reobserve only' 'Mock sent successfully')
)
$positive.browser_fill_form = Invoke-PositiveCase 'browser_fill_form' (New-Plan 'browser_fill_form' 'browser_fill_form' $formSteps 'LOW_RISK' (New-ExpectedContext '(msedge.exe|chrome.exe)' 'DesktopVisual Local Mail Mock' @('recipient', 'body', 'sendButton')))

$codeSteps = @(
    (New-DraftStep 'click_editor' 'Click editor before typing code.' 'click_field' 'editor text area' '' 'editor focused' 'LOW_RISK' '' 'reobserve only' 'editor focused'),
    (New-DraftStep 'type_code' 'Type code into editor.' 'type_text' 'editor text area' 'print("DV63")' 'print("DV63")' 'LOW_RISK' '' 'reobserve only' 'print("DV63")'),
    (New-DraftStep 'verify_code' 'Verify typed code.' 'verify_field' 'editor text area' '' 'print("DV63")' 'LOW_RISK' '' 'reobserve only' 'print("DV63")'),
    (New-DraftStep 'click_run' 'Click Run button.' 'run_button_click' 'Run button' '' 'run started' 'LOW_RISK' '' 'reobserve only' 'run started'),
    (New-DraftStep 'verify_output' 'Verify output.' 'verify_result' 'output panel' '' 'DV63' 'LOW_RISK' '' 'reobserve only' 'DV63')
)
$positive.code_editor_run = Invoke-PositiveCase 'code_editor_run' (New-Plan 'code_editor_run' 'code_editor_run' $codeSteps 'LOW_RISK' (New-ExpectedContext '(pycharm64.exe|Code.exe|mock-editor.exe)' 'code editor' @('editor', 'Run', 'output')))

$mailDraftSteps = @(
    (New-DraftStep 'click_recipient' 'Click recipient field.' 'click_field' 'recipient field' '' 'recipient focused' 'REVERSIBLE_DRAFT' '' 'reobserve only' 'recipient focused'),
    (New-DraftStep 'type_recipient' 'Type recipient.' 'type_text' 'recipient field' 'dev@example.test' 'dev@example.test' 'REVERSIBLE_DRAFT' '' 'reobserve only' 'dev@example.test'),
    (New-DraftStep 'verify_recipient' 'Verify recipient.' 'verify_field' 'recipient field' '' 'dev@example.test' 'REVERSIBLE_DRAFT' '' 'reobserve only' 'dev@example.test'),
    (New-DraftStep 'click_body' 'Click body field.' 'click_field' 'body field' '' 'body focused' 'REVERSIBLE_DRAFT' '' 'reobserve only' 'body focused'),
    (New-DraftStep 'type_body' 'Type body draft.' 'type_text' 'body field' 'draft only' 'draft only' 'REVERSIBLE_DRAFT' '' 'reobserve only' 'draft only'),
    (New-DraftStep 'verify_body' 'Verify body draft.' 'verify_field' 'body field' '' 'draft only' 'REVERSIBLE_DRAFT' '' 'reobserve only' 'draft only')
)
$positive.message_or_mail_draft = Invoke-PositiveCase 'message_or_mail_draft' (New-Plan 'message_or_mail_draft' 'message_or_mail_draft' $mailDraftSteps 'REVERSIBLE_DRAFT' (New-ExpectedContext '(msedge.exe|chrome.exe|mail.exe)' 'mock mail' @('recipient', 'body')))

$commitSteps = @(
    (New-DraftStep 'click_send_dev_message' 'Click send for reviewed developer test message.' 'send_message' 'send button for developer test recipient' '' 'message sent marker' 'REAL_COMMIT' 'developer test real commit reviewed' 'reobserve only; stop on protection or credentials' 'message sent marker')
)
$positive.developer_real_commit = Invoke-PositiveCase 'developer_real_commit' (New-Plan 'developer_real_commit' 'developer_real_commit' $commitSteps 'REAL_COMMIT' (New-ExpectedContext '(msedge.exe|chrome.exe|mail.exe)' 'developer test message' @('recipient', 'send')) $true $true)

$negativeCompile = [ordered]@{}
$missingContext = New-Plan 'missing_expected_context' 'browser_open_page' @((New-DraftStep 'bad_step' 'bad step' 'browser_open_page' 'file:///D:/test.html' '' 'marker' 'LOW_RISK' '' 'reobserve only' 'marker')) 'LOW_RISK'
$missingContext.Remove('expected_context_summary')
$negativeCompile.missing_expected_context = Invoke-NegativeCompileCase 'missing_expected_context' $missingContext 'COMPILE_MISSING_EXPECTED_CONTEXT'

$missingVerify = New-Plan 'missing_verification_hint' 'browser_open_page' @((New-DraftStep 'missing_verify' 'missing verify' 'browser_open_page' 'file:///D:/test.html' '' 'marker' 'LOW_RISK'))
$missingVerify.steps[0].Remove('verification_hint')
$negativeCompile.missing_verification_hint = Invoke-NegativeCompileCase 'missing_verification_hint' $missingVerify 'COMPILE_MISSING_VERIFICATION_HINT'

$unsupported = New-Plan 'unsupported_action' 'browser_open_page' @((New-DraftStep 'unsupported_action' 'unsupported' 'teleport_window' 'target' '' 'marker' 'LOW_RISK' '' 'reobserve only' 'marker'))
$negativeCompile.unsupported_action = Invoke-NegativeCompileCase 'unsupported_action' $unsupported 'COMPILE_UNSUPPORTED_ACTION'

$coord = New-Plan 'direct_coordinate' 'browser_open_page' @((New-DraftStep 'direct_coord' 'coord' 'direct_coordinate_click' 'x=100,y=200' '' 'clicked' 'LOW_RISK' '' 'reobserve only' 'clicked'))
$negativeCompile.direct_coordinate = Invoke-NegativeCompileCase 'direct_coordinate' $coord 'COMPILE_UNSAFE_DIRECT_COORDINATE'

$realCommitNoPolicy = New-Plan 'real_commit_no_policy' 'developer_real_commit' @((New-DraftStep 'real_commit' 'real commit' 'send_message' 'send button' '' 'sent' 'REAL_COMMIT' '' 'reobserve only' 'sent')) 'REAL_COMMIT'
$negativeCompile.real_commit_missing_confirmation = Invoke-NegativeCompileCase 'real_commit_missing_confirmation' $realCommitNoPolicy 'COMPILE_CONFIRMATION_REQUIRED'

$badRecovery = New-Plan 'bad_recovery' 'browser_open_page' @((New-DraftStep 'bad_recovery' 'bad recovery' 'browser_open_page' 'target' '' 'marker' 'LOW_RISK' '' 'bypass captcha and continue' 'marker'))
$negativeCompile.recovery_bypass_captcha = Invoke-NegativeCompileCase 'recovery_bypass_captcha' $badRecovery 'COMPILE_RECOVERY_POLICY_INVALID'

$missingStop = New-Plan 'missing_stop_policy' 'browser_open_page' @((New-DraftStep 'missing_stop' 'missing stop' 'browser_open_page' 'target' '' 'marker' 'LOW_RISK' '' 'reobserve only' 'marker'))
$missingStop.stop_policy_missing = $true
$negativeCompile.missing_stop_policy = Invoke-NegativeCompileCase 'missing_stop_policy' $missingStop 'COMPILE_STOP_POLICY_MISSING'

$ambiguous = New-Plan 'ambiguous_target' 'browser_open_page' @((New-DraftStep 'ambiguous' 'ambiguous' 'click_field' 'ambiguous button' '' 'clicked' 'LOW_RISK' '' 'reobserve only' 'clicked'))
$negativeCompile.ambiguous_target = Invoke-NegativeCompileCase 'ambiguous_target' $ambiguous 'COMPILE_TARGET_AMBIGUOUS'

$negativeCompile.invalid_json = Invoke-NegativeCompileCase 'invalid_json' '{ "plan_id": "broken", "steps": [ ' 'COMPILE_SCHEMA_INVALID' $true

$validContract = Read-JsonFile $positive.browser_fill_form.step_contract
$negativeValidation = [ordered]@{}
if ($validContract) {
    $dup = $validContract | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $dup.contracts[1].step_id = $dup.contracts[0].step_id
    $negativeValidation.duplicate_step_id = Invoke-NegativeValidationCase 'duplicate_step_id' $dup 'duplicate'

    $gap = $validContract | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $gap.contracts[1].step_index = 3
    $negativeValidation.step_index_not_continuous = Invoke-NegativeValidationCase 'step_index_not_continuous' $gap 'continuous'

    $active = $validContract | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $active.contracts = @($active.contracts[0])
    $active.contracts[0].risk_level = 'ACTIVE_PROTECTION_BLOCKED'
    $active.contracts[0].runtime_action = 'click'
    $active.contracts[0].executable = $true
    $negativeValidation.active_protection_executable = Invoke-NegativeValidationCase 'active_protection_executable' $active 'ACTIVE_PROTECTION_BLOCKED'

    $credential = $validContract | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $credential.contracts = @($credential.contracts[0])
    $credential.contracts[0].risk_level = 'CREDENTIAL_REQUIRED_BLOCKED'
    $credential.contracts[0].runtime_action = 'click'
    $credential.contracts[0].executable = $true
    $negativeValidation.credential_required_executable = Invoke-NegativeValidationCase 'credential_required_executable' $credential 'CREDENTIAL_REQUIRED_BLOCKED'
}

$runner = [ordered]@{
    schema_version = 'v6.3.0.plan_compiler.runner.raw'
    generated_at = (Get-Date).ToString('o')
    status = 'RAW_COMPLETED_UNVERIFIED'
    raw_completed_unverified = $true
    runtime_executed = $false
    root = $Root
    artifact_root = $ArtifactRoot
    raw_root = $RawRoot
    positive_cases = $positive
    negative_compile_cases = $negativeCompile
    negative_validation_cases = $negativeValidation
    executed_command_names = @('plan-compile', 'step-contract-validate', 'step-contract-dry-run')
}

Write-JsonFile $RunnerResultPath $runner | Out-Null
@(
    '# v6.3.0 Plan Compiler Runner Raw Report',
    '',
    '- Status: RAW_COMPLETED_UNVERIFIED',
    '- This runner does not declare PASS.',
    '- Runtime executed: false',
    "- Raw result: $RunnerResultPath",
    "- Raw root: $RawRoot",
    '',
    '## Positive cases',
    '- explorer_open_path',
    '- browser_open_page',
    '- browser_fill_form',
    '- code_editor_run',
    '- message_or_mail_draft',
    '- developer_real_commit',
    '',
    '## Negative compile cases',
    ($negativeCompile.Keys | ForEach-Object { "- $_" }),
    '',
    '## Negative validation cases',
    ($negativeValidation.Keys | ForEach-Object { "- $_" })
) | Set-Content -LiteralPath $RunnerReportPath -Encoding UTF8

Write-Output 'RAW_COMPLETED_UNVERIFIED'
