param(
    [string]$Root = '',
    [ValidateSet('all', 'mode', 'executor', 'request', 'plan', 'evidence')]
    [string]$Category = 'all',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.0.0_agent_boundary'
$FixtureDir = Join-Path $ArtifactDir 'fixtures'
$Report = Join-Path $ArtifactDir 'agent_boundary_selftest_report.md'

New-Item -ItemType Directory -Force -Path $FixtureDir | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}

if (-not (Test-Path $WinAgent)) {
    throw "winagent.exe not found: $WinAgent"
}

function Write-Fixture {
    param([string]$Name, [string]$Content)
    $path = Join-Path $FixtureDir $Name
    $Content | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

$validRequest = Write-Fixture 'agent_task_request_valid.json' @'
{
  "task_id": "task-v6-boundary-001",
  "mode": "runtime",
  "user_goal": "Validate the v6 agent boundary.",
  "risk": "low",
  "executor": "runtime",
  "compile_required": true
}
'@

$validVlmRequest = Write-Fixture 'agent_task_request_valid_vlm_assisted.json' @'
{
  "task_id": "task-v6-boundary-002",
  "mode": "vlm_assisted",
  "user_goal": "Use VLM assistance for planning only.",
  "risk": "medium",
  "executor": "runtime",
  "compile_required": true
}
'@

$missingRequest = Write-Fixture 'agent_task_request_missing_user_goal.json' @'
{
  "task_id": "task-v6-boundary-missing",
  "mode": "runtime",
  "risk": "low",
  "executor": "runtime",
  "compile_required": true
}
'@

$malformedRequest = Write-Fixture 'agent_task_request_malformed.json' @'
{
  "task_id": "task-v6-boundary-malformed",
  "mode": "runtime",
  "user_goal": "missing closing brace"
'@

$validPlan = Write-Fixture 'agent_plan_valid.json' @'
{
  "plan_id": "plan-v6-boundary-001",
  "task_id": "task-v6-boundary-001",
  "mode": "runtime",
  "user_goal": "Validate the v6 agent boundary.",
  "risk": "low",
  "executor": "runtime",
  "compile_required": true,
  "steps": [
    {
      "step_id": "step-001",
      "description": "Compile the requested desktop action into a Runtime StepContract.",
      "executor": "runtime",
      "compile_required": true,
      "action_type": "runtime_step_contract"
    }
  ]
}
'@

$validVlmPlan = Write-Fixture 'agent_plan_valid_vlm_assisted.json' @'
{
  "plan_id": "plan-v6-boundary-002",
  "task_id": "task-v6-boundary-002",
  "mode": "vlm_assisted",
  "user_goal": "Use VLM assistance for planning only.",
  "risk": "medium",
  "executor": "runtime",
  "compile_required": true,
  "steps": [
    {
      "step_id": "step-001",
      "description": "VLM may propose a target; Runtime must execute the compiled StepContract.",
      "executor": "runtime",
      "compile_required": true,
      "action_type": "runtime_step_contract"
    }
  ]
}
'@

$emptyStepsPlan = Write-Fixture 'agent_plan_empty_steps.json' @'
{
  "plan_id": "plan-v6-boundary-empty",
  "task_id": "task-v6-boundary-001",
  "mode": "runtime",
  "user_goal": "Validate empty step rejection.",
  "risk": "low",
  "executor": "runtime",
  "compile_required": true,
  "steps": []
}
'@

$vlmExecutorPlan = Write-Fixture 'agent_plan_vlm_executor.json' @'
{
  "plan_id": "plan-v6-boundary-vlm-executor",
  "task_id": "task-v6-boundary-001",
  "mode": "vlm_assisted",
  "user_goal": "Reject VLM direct execution.",
  "risk": "medium",
  "executor": "vlm",
  "compile_required": true,
  "steps": [
    {
      "step_id": "step-001",
      "description": "Invalid direct VLM executor.",
      "executor": "vlm",
      "compile_required": true,
      "action_type": "runtime_step_contract"
    }
  ]
}
'@

$agentDirectPlan = Write-Fixture 'agent_plan_agent_direct_executor.json' @'
{
  "plan_id": "plan-v6-boundary-agent-direct",
  "task_id": "task-v6-boundary-001",
  "mode": "runtime",
  "user_goal": "Reject agent_direct execution.",
  "risk": "medium",
  "executor": "agent_direct",
  "compile_required": true,
  "steps": [
    {
      "step_id": "step-001",
      "description": "Invalid direct agent executor.",
      "executor": "agent_direct",
      "compile_required": true,
      "action_type": "runtime_step_contract"
    }
  ]
}
'@

$jsHumanModePlan = Write-Fixture 'agent_plan_js_humanmode_action.json' @'
{
  "plan_id": "plan-v6-boundary-js",
  "task_id": "task-v6-boundary-001",
  "mode": "runtime",
  "user_goal": "Reject JavaScript as HumanMode action.",
  "risk": "medium",
  "executor": "runtime",
  "compile_required": true,
  "steps": [
    {
      "step_id": "step-001",
      "description": "Invalid JS action.",
      "executor": "runtime",
      "compile_required": true,
      "humanmode_action": true,
      "action_type": "javascript"
    }
  ]
}
'@

$malformedPlan = Write-Fixture 'agent_plan_malformed.json' @'
{
  "plan_id": "plan-v6-boundary-malformed",
  "task_id": "task-v6-boundary-001",
  "mode": "runtime",
  "steps": [
'@

$cases = New-Object System.Collections.Generic.List[object]

function Add-Case {
    param(
        [string]$Name,
        [string]$Group,
        [string[]]$CommandArgs,
        [bool]$ExpectOk,
        [string]$ExpectedError = ''
    )
    if ($Category -eq 'all' -or $Category -eq $Group) {
        $cases.Add([pscustomobject]@{
            Name = $Name
            Group = $Group
            Arguments = $CommandArgs
            ExpectOk = $ExpectOk
            ExpectedError = $ExpectedError
        }) | Out-Null
    }
}

Add-Case 'mode runtime accepted' 'mode' @('agent-boundary-validate', '--check', 'mode', '--mode', 'runtime') $true
Add-Case 'mode vlm_assisted accepted' 'mode' @('agent-boundary-validate', '--check', 'mode', '--mode', 'vlm_assisted') $true
Add-Case 'mode unknown rejected' 'mode' @('agent-boundary-validate', '--check', 'mode', '--mode', 'unknown') $false 'AGENT_MODE_INVALID'
Add-Case 'mode empty rejected' 'mode' @('agent-boundary-validate', '--check', 'mode', '--mode', '') $false 'AGENT_MODE_INVALID'
Add-Case 'mode missing rejected' 'mode' @('agent-boundary-validate', '--check', 'mode') $false 'AGENT_MODE_INVALID'

Add-Case 'executor runtime accepted' 'executor' @('agent-boundary-validate', '--check', 'executor', '--executor', 'runtime') $true
Add-Case 'executor vlm rejected' 'executor' @('agent-boundary-validate', '--check', 'executor', '--executor', 'vlm') $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'executor agent_direct rejected' 'executor' @('agent-boundary-validate', '--check', 'executor', '--executor', 'agent_direct') $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'executor missing rejected' 'executor' @('agent-boundary-validate', '--check', 'executor') $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'Runtime StepContract action accepted' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'runtime_step_contract') $true
Add-Case 'JS HumanMode action rejected' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'javascript') $false 'AGENT_ACTION_BOUNDARY_INVALID'
Add-Case 'DOM HumanMode action rejected' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'dom') $false 'AGENT_ACTION_BOUNDARY_INVALID'
Add-Case 'WebDriver HumanMode action rejected' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'webdriver') $false 'AGENT_ACTION_BOUNDARY_INVALID'
Add-Case 'CDP HumanMode action rejected' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'cdp') $false 'AGENT_ACTION_BOUNDARY_INVALID'
Add-Case 'UIA Invoke HumanMode action rejected' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'uia_invoke') $false 'AGENT_ACTION_BOUNDARY_INVALID'
Add-Case 'UIA Value HumanMode action rejected' 'executor' @('agent-boundary-validate', '--check', 'action', '--humanmode-action', 'true', '--action-type', 'uia_value') $false 'AGENT_ACTION_BOUNDARY_INVALID'

Add-Case 'AgentTaskRequest runtime accepted' 'request' @('agent-boundary-validate', '--check', 'request', '--file', $validRequest) $true
Add-Case 'AgentTaskRequest vlm_assisted accepted' 'request' @('agent-boundary-validate', '--check', 'request', '--file', $validVlmRequest) $true
Add-Case 'AgentTaskRequest missing field rejected' 'request' @('agent-boundary-validate', '--check', 'request', '--file', $missingRequest) $false 'AGENT_REQUEST_INVALID'
Add-Case 'AgentTaskRequest malformed JSON rejected' 'request' @('agent-boundary-validate', '--check', 'request', '--file', $malformedRequest) $false 'MALFORMED_JSON'

Add-Case 'AgentPlan runtime accepted' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $validPlan) $true
Add-Case 'AgentPlan vlm_assisted accepted' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $validVlmPlan) $true
Add-Case 'AgentPlan empty steps rejected' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $emptyStepsPlan) $false 'AGENT_PLAN_INVALID'
Add-Case 'AgentPlan vlm executor rejected' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $vlmExecutorPlan) $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'AgentPlan agent_direct executor rejected' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $agentDirectPlan) $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'AgentPlan JS HumanMode action rejected' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $jsHumanModePlan) $false 'AGENT_ACTION_BOUNDARY_INVALID'
Add-Case 'AgentPlan malformed JSON rejected' 'plan' @('agent-boundary-validate', '--check', 'plan', '--file', $malformedPlan) $false 'MALFORMED_JSON'

if ($cases.Count -eq 0 -and $Category -ne 'evidence') {
    throw "No cases selected for category $Category"
}

$results = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]
$allRawOutput = New-Object System.Collections.Generic.List[string]

foreach ($case in $cases) {
    $output = & $WinAgent @($case.Arguments) 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $allRawOutput.Add($text) | Out-Null

    try {
        $json = $text | ConvertFrom-Json
    } catch {
        throw "Command did not return JSON for '$($case.Name)'. exit=$exitCode output=$text"
    }

    $okMatches = ([bool]$json.ok -eq [bool]$case.ExpectOk)
    $exitMatches = if ($case.ExpectOk) { $exitCode -eq 0 } else { $exitCode -ne 0 }
    $errorMatches = $true
    if (-not $case.ExpectOk -and -not [string]::IsNullOrWhiteSpace($case.ExpectedError)) {
        $errorMatches = ($json.error.code -eq $case.ExpectedError)
    }

    $status = if ($okMatches -and $exitMatches -and $errorMatches) { 'PASS' } else { 'FAIL' }
    if ($status -ne 'PASS') {
        $failures.Add("$($case.Name): expected_ok=$($case.ExpectOk) exit=$exitCode error=$($json.error.code) output=$text") | Out-Null
    }

    $results.Add([pscustomobject]@{
        name = $case.Name
        group = $case.Group
        status = $status
        exit_code = $exitCode
        ok = [bool]$json.ok
        error_code = if ($json.error) { $json.error.code } else { '' }
        command = ($case.Arguments -join ' ')
        output = $text
    }) | Out-Null
}

$invalidatedTokens = @(
    'artifacts\invalidated',
    'dev5.10.1_adaptive_cases_INVALIDATED',
    'dev5.10.2_final_pre_v6_gate_INVALIDATED'
)

$invalidatedEvidenceUsed = $false
foreach ($raw in $allRawOutput) {
    foreach ($token in $invalidatedTokens) {
        if ($raw -like "*$token*") {
            $invalidatedEvidenceUsed = $true
        }
    }
}

if ($invalidatedEvidenceUsed) {
    $failures.Add('Invalidated evidence path appeared in selftest command output.') | Out-Null
}

$noFakePass = $failures.Count -eq 0 -and (@($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0)
if (-not $noFakePass) {
    $failures.Add('No-fake-PASS guard failed: at least one expected command outcome was not independently verified.') | Out-Null
}

$summary = [ordered]@{
    ok = ($failures.Count -eq 0)
    category = $Category
    checked_cases = $results.Count
    no_fake_pass_guard = $noFakePass
    invalidated_evidence_used = $invalidatedEvidenceUsed
    failures = @($failures)
}

$resultText = if ($summary.ok) { 'PASS' } else { 'FAIL' }

$lines = @(
    '# v6.0.0 Agent Boundary Selftest Report',
    '',
    ('- Result: {0}' -f $resultText),
    ('- Category: `{0}`' -f $Category),
    ('- Timestamp: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    ('- WinAgent: `{0}`' -f $WinAgent),
    ('- Checked cases: {0}' -f $results.Count),
    ('- No fake PASS guard: {0}' -f $summary.no_fake_pass_guard),
    ('- Invalidated evidence used: {0}' -f $summary.invalidated_evidence_used),
    '',
    '## Summary JSON',
    '',
    '```json',
    ($summary | ConvertTo-Json -Depth 8),
    '```',
    '',
    '## Case Results',
    ''
)

foreach ($result in $results) {
    $lines += @(
        "### $($result.name)",
        '',
        ('- Group: `{0}`' -f $result.group),
        ('- Status: `{0}`' -f $result.status),
        ('- Exit code: `{0}`' -f $result.exit_code),
        ('- ok: `{0}`' -f $result.ok),
        ('- error_code: `{0}`' -f $result.error_code),
        ('- Command: `{0}`' -f $result.command),
        '',
        '```json',
        $result.output,
        '```',
        ''
    )
}

$lines | Set-Content -LiteralPath $Report -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "v6.0.0 agent boundary selftest failed. Report: $Report"
}

Write-Host 'PASS: v6.0.0 agent boundary selftest'
Write-Host "Report: $Report"
