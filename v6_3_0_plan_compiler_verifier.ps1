param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.3.0_plan_draft_to_step_contract_compiler'
$RunnerResultPath = Join-Path $ArtifactRoot 'v6_3_0_runner_raw_result.json'
$VerifierJsonPath = Join-Path $ArtifactRoot 'v6_3_0_verifier_report.json'
$VerifierMdPath = Join-Path $ArtifactRoot 'v6_3_0_verifier_report.md'
$ValidatorReportPath = Join-Path $ArtifactRoot 'validator_report.md'
$PositiveReportPath = Join-Path $ArtifactRoot 'positive_compile_cases_report.md'
$NegativeReportPath = Join-Path $ArtifactRoot 'negative_compile_cases_report.md'
$DryRunReportPath = Join-Path $ArtifactRoot 'session_steps_dry_run_report.md'

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Add-Finding {
    param([System.Collections.Generic.List[object]]$Findings, [string]$Code, [string]$Message, [string]$Path = '')
    $Findings.Add([pscustomobject]@{ code = $Code; message = $Message; path = $Path; blocking = $true }) | Out-Null
}

function Obj-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Read-CaseFiles($Case) {
    [pscustomobject]@{
        contract = Read-JsonFile ([string]$Case.step_contract)
        diagnostics = Read-JsonFile ([string]$Case.diagnostics)
        validation = Read-JsonFile ([string]$Case.validation_result)
        session = Read-JsonFile ([string]$Case.session_steps)
    }
}

function Require-StepSchema {
    param($Step, [System.Collections.Generic.List[object]]$Findings, [string]$CaseName)
    $required = @(
        'contract_id','task_id','plan_id','step_id','step_index','step_type','runtime_action',
        'target','input_text','expected_context','action_precondition','verification_hint',
        'risk_level','confirmation_policy','recovery_policy','stop_policy','session_policy',
        'evidence_policy','created_at','compiler_version'
    )
    foreach ($field in $required) {
        if ($null -eq (Obj-Prop $Step $field)) {
            Add-Finding $Findings 'BLOCKED_STEP_CONTRACT_SCHEMA_INCOMPLETE' "$CaseName missing StepContract field $field"
        }
    }
    if (-not $Step.expected_context -or -not $Step.action_precondition -or -not $Step.verification_hint) {
        Add-Finding $Findings 'BLOCKED_CONTRACT_MISSING_EXPECTED_CONTEXT' "$CaseName missing context/precondition/verification object"
    }
    if (-not $Step.evidence_policy.verifier_required -or -not $Step.evidence_policy.gate_required) {
        Add-Finding $Findings 'BLOCKED_EVIDENCE_POLICY_INCOMPLETE' "$CaseName evidence policy does not require verifier/gate"
    }
    if (-not $Step.stop_policy.stop_on_active_protection -or -not $Step.stop_policy.stop_on_credential_required) {
        Add-Finding $Findings 'BLOCKED_PROTECTION_STOP_POLICY_BYPASSED' "$CaseName stop policy misses protection/credential stops"
    }
}

function All-Steps-Have-CoreSchema($Contract, [System.Collections.Generic.List[object]]$Findings, [string]$CaseName) {
    foreach ($step in @($Contract.contracts)) {
        Require-StepSchema $step $Findings $CaseName
    }
}

function Case-Ok($Case, [string]$Name, [System.Collections.Generic.List[object]]$Findings) {
    $files = Read-CaseFiles $Case
    if (-not $files.contract -or -not $files.diagnostics -or -not $files.validation -or -not $files.session) {
        Add-Finding $Findings 'BLOCKED_CASE_EVIDENCE_MISSING' "$Name missing one or more evidence JSON files"
        return $false
    }
    if ($files.diagnostics.compile_ok -ne $true) { Add-Finding $Findings 'BLOCKED_POSITIVE_COMPILE_FAILED' "$Name compile_ok is not true" $Case.diagnostics }
    if ($files.validation.validation_ok -ne $true) { Add-Finding $Findings 'BLOCKED_POSITIVE_VALIDATION_FAILED' "$Name validation_ok is not true" $Case.validation_result }
    if ($files.session.runtime_executed -ne $false) { Add-Finding $Findings 'BLOCKED_DRY_RUN_EXECUTED_RUNTIME' "$Name dry-run runtime_executed is not false" $Case.session_steps }
    if (@($files.session.session_steps).Count -lt 1) { Add-Finding $Findings 'BLOCKED_DRY_RUN_SESSION_STEPS_MISSING' "$Name dry-run emitted no session steps" $Case.session_steps }
    All-Steps-Have-CoreSchema $files.contract $Findings $Name
    return $true
}

$findings = [System.Collections.Generic.List[object]]::new()
$runner = Read-JsonFile $RunnerResultPath
if (-not $runner) {
    Add-Finding $findings 'BLOCKED_RUNNER_EVIDENCE_MISSING' 'Runner raw result is missing.' $RunnerResultPath
} elseif ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding $findings 'BLOCKED_RAW_EVIDENCE_NOT_RAW' 'Runner must produce RAW_COMPLETED_UNVERIFIED, not PASS.' $RunnerResultPath
}

$coreFiles = @(
    'src\winagent\PlanCompiler.h',
    'src\winagent\PlanCompiler.cpp',
    'src\winagent\StepContractValidator.h',
    'src\winagent\StepContractValidator.cpp',
    'src\winagent\StepContract.h'
)
foreach ($rel in $coreFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $rel))) {
        Add-Finding $findings 'BLOCKED_RUNNER_ONLY_COMPILER' "Missing bottom-layer file $rel"
    }
}

$allowedCommands = @('plan-compile', 'step-contract-validate', 'step-contract-dry-run')
foreach ($cmd in @($runner.executed_command_names)) {
    if ($allowedCommands -notcontains [string]$cmd) {
        Add-Finding $findings 'BLOCKED_DRY_RUN_EXECUTED_RUNTIME' "Runner executed disallowed command $cmd"
    }
}

$positiveStatus = [ordered]@{}
if ($runner) {
    foreach ($name in @('explorer_open_path','browser_open_page','browser_fill_form','code_editor_run','message_or_mail_draft','developer_real_commit')) {
        $case = Obj-Prop $runner.positive_cases $name
        if (-not $case) {
            Add-Finding $findings 'BLOCKED_POSITIVE_CASE_MISSING' "Missing positive case $name"
            $positiveStatus[$name] = $false
            continue
        }
        $null = Case-Ok $case $name $findings
        $files = Read-CaseFiles $case
        $positiveStatus[$name] = ($files.diagnostics -and $files.diagnostics.compile_ok -eq $true -and $files.validation.validation_ok -eq $true)
    }
}

$explorer = Read-CaseFiles (Obj-Prop $runner.positive_cases 'explorer_open_path')
if ($explorer.contract) {
    $step = @($explorer.contract.contracts)[0]
    if ($step.runtime_action -ne 'explorer_open_path' -or $step.risk_level -ne 'LOW_RISK') {
        Add-Finding $findings 'BLOCKED_EXPLORER_CASE_INVALID' 'explorer_open_path did not compile to explorer_open_path LOW_RISK.'
    }
}

$browser = Read-CaseFiles (Obj-Prop $runner.positive_cases 'browser_open_page')
if ($browser.contract) {
    $actions = @($browser.contract.contracts | ForEach-Object { $_.runtime_action })
    if ($actions -notcontains 'browser_open_page' -or $actions -notcontains 'browser_surface_normalize') {
        Add-Finding $findings 'BLOCKED_BROWSER_CASE_INVALID' 'browser_open_page case lacks browser open or surface normalization contract.'
    }
}

$form = Read-CaseFiles (Obj-Prop $runner.positive_cases 'browser_fill_form')
if ($form.contract -and @($form.contract.contracts).Count -lt 9) {
    Add-Finding $findings 'BLOCKED_BROWSER_FORM_CASE_INCOMPLETE' 'browser_fill_form must produce at least nine StepContracts.'
}

$editor = Read-CaseFiles (Obj-Prop $runner.positive_cases 'code_editor_run')
if ($editor.contract) {
    $mouseFirst = @($editor.contract.contracts | Where-Object { $_.action_precondition.mouse_first_required -eq $true })
    $outputVerify = @($editor.contract.contracts | Where-Object { $_.verification_hint.verify_type -eq 'output_contains' })
    if ($mouseFirst.Count -lt 1 -or $outputVerify.Count -lt 1) {
        Add-Finding $findings 'BLOCKED_CODE_EDITOR_CASE_INVALID' 'code_editor_run lacks mouse-first or output verification contract.'
    }
}

$draft = Read-CaseFiles (Obj-Prop $runner.positive_cases 'message_or_mail_draft')
if ($draft.contract) {
    $bad = @($draft.contract.contracts | Where-Object { $_.risk_level -ne 'REVERSIBLE_DRAFT' -or $_.stop_policy.stop_on_wrong_field -ne $true })
    if ($bad.Count -gt 0) {
        Add-Finding $findings 'BLOCKED_MESSAGE_DRAFT_CASE_INVALID' 'message_or_mail_draft must be REVERSIBLE_DRAFT with wrong-field stop.'
    }
}

$commit = Read-CaseFiles (Obj-Prop $runner.positive_cases 'developer_real_commit')
if ($commit.contract) {
    $step = @($commit.contract.contracts)[0]
    if ($step.risk_level -ne 'REAL_COMMIT' -or $step.confirmation_policy.developer_full_access_allowed -ne $true -or
        $step.stop_policy.stop_on_active_protection -ne $true -or $step.stop_policy.stop_on_credential_required -ne $true) {
        Add-Finding $findings 'BLOCKED_REAL_COMMIT_POLICY_MISSING' 'developer_real_commit lacks REAL_COMMIT developer policy or stop policy.'
    }
}

$negativeStatus = [ordered]@{}
$expectedCompile = [ordered]@{
    missing_expected_context = 'COMPILE_MISSING_EXPECTED_CONTEXT'
    missing_verification_hint = 'COMPILE_MISSING_VERIFICATION_HINT'
    unsupported_action = 'COMPILE_UNSUPPORTED_ACTION'
    direct_coordinate = 'COMPILE_UNSAFE_DIRECT_COORDINATE'
    real_commit_missing_confirmation = 'COMPILE_CONFIRMATION_REQUIRED'
    recovery_bypass_captcha = 'COMPILE_RECOVERY_POLICY_INVALID'
    missing_stop_policy = 'COMPILE_STOP_POLICY_MISSING'
    ambiguous_target = 'COMPILE_TARGET_AMBIGUOUS'
    invalid_json = 'COMPILE_SCHEMA_INVALID'
}
foreach ($caseName in $expectedCompile.Keys) {
    $case = Obj-Prop $runner.negative_compile_cases $caseName
    $diag = if ($case) { Read-JsonFile ([string]$case.diagnostics) } else { $null }
    $ok = ($diag -and $diag.compile_ok -eq $false -and $diag.error_code -eq $expectedCompile[$caseName])
    $negativeStatus[$caseName] = [bool]$ok
    if (-not $ok) {
        $path = if ($case) { [string]$case.diagnostics } else { '' }
        Add-Finding $findings 'BLOCKED_NEGATIVE_COMPILE_CASE_FAILED' "$caseName expected $($expectedCompile[$caseName])" $path
    }
}

$expectedValidation = [ordered]@{
    duplicate_step_id = 'duplicate'
    step_index_not_continuous = 'continuous'
    active_protection_executable = 'ACTIVE_PROTECTION_BLOCKED'
    credential_required_executable = 'CREDENTIAL_REQUIRED_BLOCKED'
}
foreach ($caseName in $expectedValidation.Keys) {
    $case = Obj-Prop $runner.negative_validation_cases $caseName
    $validation = if ($case) { Read-JsonFile ([string]$case.validation_result) } else { $null }
    $text = if ($validation) { $validation.validation_errors | ConvertTo-Json -Depth 20 } else { '' }
    $ok = ($validation -and $validation.validation_ok -eq $false -and $text -match $expectedValidation[$caseName])
    $negativeStatus[$caseName] = [bool]$ok
    if (-not $ok) {
        $path = if ($case) { [string]$case.validation_result } else { '' }
        Add-Finding $findings 'BLOCKED_NEGATIVE_VALIDATION_CASE_FAILED' "$caseName expected validation error matching $($expectedValidation[$caseName])" $path
    }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$result = [ordered]@{
    schema_version = 'v6.3.0.plan_compiler.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    runner_status = if ($runner) { $runner.status } else { 'MISSING' }
    runtime_executed = if ($runner) { $runner.runtime_executed } else { $null }
    positive_cases = $positiveStatus
    negative_cases = $negativeStatus
    no_runner_only_compiler = ($findings | Where-Object { $_.code -eq 'BLOCKED_RUNNER_ONLY_COMPILER' }).Count -eq 0
    no_runtime_action_executed = ($findings | Where-Object { $_.code -eq 'BLOCKED_DRY_RUN_EXECUTED_RUNTIME' }).Count -eq 0
    findings = @($findings.ToArray())
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $VerifierJsonPath -Encoding UTF8

$findingLines = @($findings.ToArray()) | ForEach-Object { "- $($_.code): $($_.message) $($_.path)" }
if ($findingLines.Count -eq 0) { $findingLines = @('- No blocking findings.') }
@(
    '# v6.3.0 Plan Compiler Verifier Report',
    '',
    "- Status: $status",
    "- Runner status: $($result.runner_status)",
    "- Runtime executed: $($result.runtime_executed)",
    "- No runner-only compiler: $($result.no_runner_only_compiler)",
    "- No Runtime action executed: $($result.no_runtime_action_executed)",
    '',
    '## Findings'
) + $findingLines | Set-Content -LiteralPath $VerifierMdPath -Encoding UTF8

@(
    '# v6.3.0 StepContract Validator Report',
    '',
    "- Status: $status",
    "- Validator implementation: src\winagent\StepContractValidator.h/.cpp",
    "- Validation result fields: validation_ok, validation_errors, validation_warnings, executable, runtime_session_compatible, safe_for_developer_full_access, safe_for_public_release."
) + $findingLines | Set-Content -LiteralPath $ValidatorReportPath -Encoding UTF8

@(
    '# v6.3.0 Positive Compile Cases Report',
    '',
    "- Status: $status",
    '',
    '```json',
    ($positiveStatus | ConvertTo-Json -Depth 20),
    '```'
) | Set-Content -LiteralPath $PositiveReportPath -Encoding UTF8

@(
    '# v6.3.0 Negative Compile Cases Report',
    '',
    "- Status: $status",
    '',
    '```json',
    ($negativeStatus | ConvertTo-Json -Depth 20),
    '```'
) | Set-Content -LiteralPath $NegativeReportPath -Encoding UTF8

@(
    '# v6.3.0 Session Steps Dry-Run Report',
    '',
    "- Status: $status",
    "- Runtime executed: false",
    "- Dry-run output is structured JSON only; no runtime-session-dispatch command is called."
) | Set-Content -LiteralPath $DryRunReportPath -Encoding UTF8

if ($status -ne 'PASS') {
    throw (($findings | ForEach-Object { $_.code }) -join '; ')
}

Write-Output 'V6_3_0_PLAN_COMPILER_VERIFIER_PASS'
