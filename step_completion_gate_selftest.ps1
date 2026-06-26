param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
if (Test-Path -LiteralPath $Resolver) {
    $Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
} elseif ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = $PSScriptRoot
}

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_scope_reset_step_completion_closure'
$SelftestRoot = Join-Path $ArtifactRoot 'step_completion_gate_selftest'
$ReportPath = Join-Path $ArtifactRoot 'step_completion_gate_selftest_report.md'
$ResultPath = Join-Path $ArtifactRoot 'step_completion_gate_selftest_result.json'

New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null

function New-StepInput {
    param(
        [string]$StepId,
        [string]$StepName,
        [string]$StepType,
        [bool]$PreconditionVerified = $true,
        [bool]$ActionExecuted = $true,
        [bool]$PostObserveRequired = $false,
        [bool]$PostObservePerformed = $true,
        [bool]$PostconditionVerified = $true,
        [hashtable]$RawActionEvidence = @{},
        [string]$FailureAttribution = 'STEP_COMPLETION_FAILED'
    )

    [ordered]@{
        step_id = $StepId
        step_name = $StepName
        step_type = $StepType
        expected_context = [ordered]@{ verified = $PreconditionVerified }
        expected_preconditions = [ordered]@{ verified = $PreconditionVerified }
        precondition_verified = $PreconditionVerified
        action_name = $StepName
        action_result = [ordered]@{ action_executed = $ActionExecuted }
        action_executed = $ActionExecuted
        raw_action_evidence = $RawActionEvidence
        post_observe_required = $PostObserveRequired
        post_observe_result = [ordered]@{ performed = $PostObservePerformed }
        post_observe_performed = $PostObservePerformed
        expected_postconditions = [ordered]@{ verified = $PostconditionVerified }
        postcondition_verified = $PostconditionVerified
        failure_attribution_on_fail = $FailureAttribution
    }
}

$cases = @(
    [ordered]@{
        name = 'precondition_failed'
        input = New-StepInput -StepId 'sg-001' -StepName 'precondition failed' -StepType 'generic_action' -PreconditionVerified $false -ActionExecuted $true -PostconditionVerified $true -FailureAttribution 'PRECONDITION_FAILED'
        expect = [ordered]@{ exit_code = 1; action_executed = $false; step_verified = $false; next_step_allowed = $false; stop_code = 'STEP_PRECONDITION_FAILED' }
    },
    [ordered]@{
        name = 'action_not_executed'
        input = New-StepInput -StepId 'sg-002' -StepName 'action not executed' -StepType 'generic_action' -PreconditionVerified $true -ActionExecuted $false -PostconditionVerified $true -FailureAttribution 'ACTION_NOT_EXECUTED'
        expect = [ordered]@{ exit_code = 1; step_verified = $false; next_step_allowed = $false; stop_code = 'STEP_ACTION_NOT_EXECUTED' }
    },
    [ordered]@{
        name = 'post_observe_missing'
        input = New-StepInput -StepId 'sg-003' -StepName 'post observe missing' -StepType 'generic_action' -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $false -PostconditionVerified $true -FailureAttribution 'POST_OBSERVE_MISSING'
        expect = [ordered]@{ exit_code = 1; step_verified = $false; next_step_allowed = $false; stop_code = 'STEP_POST_OBSERVE_MISSING' }
    },
    [ordered]@{
        name = 'postcondition_failed'
        input = New-StepInput -StepId 'sg-004' -StepName 'postcondition failed' -StepType 'generic_action' -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $true -PostconditionVerified $false -FailureAttribution 'POSTCONDITION_FAILED'
        expect = [ordered]@{ exit_code = 1; step_verified = $false; next_step_allowed = $false; stop_code = 'STEP_POSTCONDITION_FAILED' }
    },
    [ordered]@{
        name = 'successful_step'
        input = New-StepInput -StepId 'sg-005' -StepName 'successful step' -StepType 'generic_action' -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $true -PostconditionVerified $true -FailureAttribution 'NONE'
        expect = [ordered]@{ exit_code = 0; step_verified = $true; next_step_allowed = $true; stop_code = 'STEP_OK' }
    },
    [ordered]@{
        name = 'pycharm_editor_click_gate'
        input = New-StepInput -StepId 'sg-006' -StepName 'PyCharm editor click gate' -StepType 'pycharm_editor_click' -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $true -PostconditionVerified $true -RawActionEvidence @{ editor_clicked_by_mouse = $false; editor_focus_verified = $false } -FailureAttribution 'EDITOR_FOCUS_NOT_VERIFIED'
        expect = [ordered]@{ exit_code = 1; step_verified = $false; next_step_allowed = $false; failure_attribution = 'EDITOR_FOCUS_NOT_VERIFIED'; reason_contains = 'code type' }
    },
    [ordered]@{
        name = 'pycharm_code_type_gate'
        input = New-StepInput -StepId 'sg-007' -StepName 'PyCharm code type gate' -StepType 'pycharm_code_type' -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $true -PostconditionVerified $true -RawActionEvidence @{ code_text_verified = $false } -FailureAttribution 'CODE_TEXT_NOT_VERIFIED'
        expect = [ordered]@{ exit_code = 1; step_verified = $false; next_step_allowed = $false; failure_attribution = 'CODE_TEXT_NOT_VERIFIED'; reason_contains = 'run shortcut' }
    },
    [ordered]@{
        name = 'pycharm_run_gate_execution_failed'
        input = New-StepInput -StepId 'sg-008' -StepName 'PyCharm run gate execution failed' -StepType 'pycharm_run' -PreconditionVerified $true -ActionExecuted $true -PostObserveRequired $true -PostObservePerformed $true -PostconditionVerified $true -RawActionEvidence @{ run_triggered = $true; execution_success = $false } -FailureAttribution 'CODE_EXECUTION_ERROR'
        expect = [ordered]@{ exit_code = 1; step_verified = $false; next_step_allowed = $false; run_triggered = $true; failure_attribution = 'CODE_EXECUTION_ERROR'; reason_contains = 'run was triggered' }
    }
)

$results = New-Object System.Collections.Generic.List[object]
$findings = New-Object System.Collections.Generic.List[string]

foreach ($case in $cases) {
    $inputPath = Join-Path $SelftestRoot "$($case.name).input.json"
    $caseResultPath = Join-Path $SelftestRoot "$($case.name).result.json"
    $stdoutPath = Join-Path $SelftestRoot "$($case.name).stdout.txt"

    $case.input | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    if (Test-Path -LiteralPath $caseResultPath) { Remove-Item -LiteralPath $caseResultPath -Force }

    $output = & $WinAgent step-completion-evaluate --input-json $inputPath --result-json $caseResultPath 2>&1
    $exitCode = $LASTEXITCODE
    $output | Out-String | Set-Content -LiteralPath $stdoutPath -Encoding UTF8

    $actual = $null
    if (Test-Path -LiteralPath $caseResultPath) {
        $actual = Get-Content -Raw -LiteralPath $caseResultPath | ConvertFrom-Json
    }

    $passed = $true
    $caseFindings = New-Object System.Collections.Generic.List[string]
    if ($exitCode -ne [int]$case.expect.exit_code) {
        $passed = $false
        $caseFindings.Add("expected exit $($case.expect.exit_code), got $exitCode") | Out-Null
    }
    if ($null -eq $actual) {
        $passed = $false
        $caseFindings.Add('result json missing') | Out-Null
    } else {
        foreach ($key in $case.expect.Keys) {
            if ($key -in @('exit_code','reason_contains')) { continue }
            if ($actual.PSObject.Properties.Name -notcontains $key) {
                $passed = $false
                $caseFindings.Add("missing result field $key") | Out-Null
                continue
            }
            if ($actual.$key -ne $case.expect.$key) {
                $passed = $false
                $caseFindings.Add("$key expected $($case.expect.$key), got $($actual.$key)") | Out-Null
            }
        }
        if ($case.expect.Contains('reason_contains') -and ([string]$actual.reason -notmatch [regex]::Escape([string]$case.expect.reason_contains))) {
            $passed = $false
            $caseFindings.Add("reason does not contain '$($case.expect.reason_contains)'") | Out-Null
        }
    }

    if (-not $passed) {
        $findings.Add("$($case.name): $($caseFindings -join '; ')") | Out-Null
    }

    $results.Add([ordered]@{
        name = $case.name
        passed = $passed
        exit_code = $exitCode
        input_path = $inputPath
        result_path = $caseResultPath
        stdout_path = $stdoutPath
        findings = @($caseFindings.ToArray())
    }) | Out-Null
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED_STEP_COMPLETION_GATE_SELFTEST_FAILED' }
$summary = [ordered]@{
    schema_version = 'v6.1.6.step_completion_gate_selftest'
    generated_at = (Get-Date).ToString('o')
    status = $status
    command = 'winagent.exe step-completion-evaluate'
    cases = @($results.ToArray())
    findings = @($findings.ToArray())
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# StepCompletionGate Selftest Report') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- Status: $status") | Out-Null
$lines.Add("- Command: winagent.exe step-completion-evaluate") | Out-Null
$lines.Add("- Result JSON: $ResultPath") | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| Case | Result | Exit Code | Findings |') | Out-Null
$lines.Add('|---|---|---:|---|') | Out-Null
foreach ($result in @($results.ToArray())) {
    $resultText = if ($result.passed) { 'PASS' } else { 'FAIL' }
    $findingText = if ($result.findings.Count -gt 0) { $result.findings -join '; ' } else { '' }
    $lines.Add("| $($result.name) | $resultText | $($result.exit_code) | $findingText |") | Out-Null
}
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($status -ne 'PASS') {
    throw $status
}

Write-Output 'STEP_COMPLETION_GATE_SELFTEST_PASS'
