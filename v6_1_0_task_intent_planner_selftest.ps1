param(
    [string]$Root = '',
    [ValidateSet('all', 'intent', 'draft', 'boundary', 'schema', 'evidence')]
    [string]$Category = 'all',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev6.1.0_task_intent_planner'
$FixtureDir = Join-Path $ArtifactDir 'fixtures'
$Report = Join-Path $ArtifactDir 'task_intent_planner_selftest_report.md'

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

function Get-JsonPathValue {
    param($Object, [string]$Path)
    $cursor = $Object
    foreach ($part in ($Path -split '\.')) {
        if ($null -eq $cursor) { return $null }
        if ($cursor -is [System.Array]) {
            if ($part -notmatch '^\d+$') { return $null }
            $idx = [int]$part
            if ($idx -lt 0 -or $idx -ge $cursor.Count) { return $null }
            $cursor = $cursor[$idx]
            continue
        }
        $prop = $cursor.PSObject.Properties[$part]
        if ($null -eq $prop) { return $null }
        $cursor = $prop.Value
    }
    return $cursor
}

function Test-ExpectedValue {
    param($Actual, $Expected)
    if ($Expected -is [bool]) { return ([bool]$Actual -eq $Expected) }
    return ([string]$Actual -eq [string]$Expected)
}

function TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$GoalOpenPath = (TextFromCodePoints 0x6253, 0x5f00) + ' D:\testrepo\testwindow'
$GoalDeleteFile = (TextFromCodePoints 0x5220, 0x9664) + ' D:\testrepo\testwindow\da.txt'
$GoalLocalForm = TextFromCodePoints 0x6253, 0x5f00, 0x672c, 0x5730, 0x7f51, 0x9875, 0x5e76, 0x586b, 0x5199, 0x8868, 0x5355
$GoalBrowserTitle = TextFromCodePoints 0x6253, 0x5f00, 0x666e, 0x901a, 0x7f51, 0x9875, 0x8bfb, 0x53d6, 0x6807, 0x9898
$GoalAmbiguous = TextFromCodePoints 0x5e2e, 0x6211, 0x5904, 0x7406, 0x4e00, 0x4e0b
$GoalBypassProtection = TextFromCodePoints 0x7ed5, 0x8fc7, 0x9a8c, 0x8bc1, 0x7801, 0x7ee7, 0x7eed, 0x64cd, 0x4f5c

$validIntent = Write-Fixture 'task_intent_valid.json' @'
{
  "task_id": "intent-v6-1-valid",
  "raw_user_goal": "open D:\\testrepo\\testwindow",
  "normalized_goal": "open D:\\testrepo\\testwindow",
  "intent_type": "explorer_open_path",
  "mode": "runtime",
  "target_app": "explorer",
  "target_path": "D:\\testrepo\\testwindow",
  "target_object": "",
  "user_constraints": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "assumptions": ["planner_only_no_execution"],
  "unsupported_reason": ""
}
'@

$missingIntent = Write-Fixture 'task_intent_missing_mode.json' @'
{
  "task_id": "intent-v6-1-missing",
  "raw_user_goal": "open D:\\testrepo\\testwindow",
  "normalized_goal": "open D:\\testrepo\\testwindow",
  "intent_type": "explorer_open_path",
  "target_app": "explorer",
  "target_path": "D:\\testrepo\\testwindow",
  "target_object": "",
  "user_constraints": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "assumptions": [],
  "unsupported_reason": ""
}
'@

$malformedIntent = Write-Fixture 'task_intent_malformed.json' @'
{
  "task_id": "intent-v6-1-malformed",
  "mode": "runtime"
'@

$validDraft = Write-Fixture 'agent_plan_draft_valid.json' @'
{
  "plan_id": "draft-v6-1-valid",
  "task_id": "intent-v6-1-valid",
  "mode": "runtime",
  "intent_type": "explorer_open_path",
  "draft_steps": [
    {
      "step_id": "draft-step-001",
      "description": "Draft a Runtime capability for opening the target path.",
      "expected_runtime_capability": "explorer.open_path",
      "target": "D:\\testrepo\\testwindow",
      "precondition_hint": "Target path is available to Runtime.",
      "verification_hint": "Explorer reports the target path after execution.",
      "risk": "low"
    }
  ],
  "required_runtime_capabilities": ["explorer.open_path"],
  "assumptions": ["planner_only_no_execution"],
  "risk_level": "low",
  "requires_confirmation": false,
  "compile_required": true,
  "executor": "runtime",
  "provider_role": "none",
  "is_executable": false
}
'@

$missingDraft = Write-Fixture 'agent_plan_draft_missing_steps.json' @'
{
  "plan_id": "draft-v6-1-missing",
  "task_id": "intent-v6-1-valid",
  "mode": "runtime",
  "intent_type": "explorer_open_path",
  "required_runtime_capabilities": ["explorer.open_path"],
  "assumptions": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "compile_required": true,
  "executor": "runtime",
  "provider_role": "none",
  "is_executable": false
}
'@

$executableDraft = Write-Fixture 'agent_plan_draft_executable.json' @'
{
  "plan_id": "draft-v6-1-executable",
  "task_id": "intent-v6-1-valid",
  "mode": "runtime",
  "intent_type": "explorer_open_path",
  "draft_steps": [
    {
      "step_id": "draft-step-001",
      "description": "Click the folder immediately.",
      "expected_runtime_capability": "click",
      "target": "D:\\testrepo\\testwindow",
      "precondition_hint": "none",
      "verification_hint": "none",
      "risk": "low"
    }
  ],
  "required_runtime_capabilities": ["click"],
  "assumptions": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "compile_required": true,
  "executor": "runtime",
  "provider_role": "none",
  "is_executable": true
}
'@

$vlmExecutorDraft = Write-Fixture 'agent_plan_draft_vlm_executor.json' @'
{
  "plan_id": "draft-v6-1-vlm-executor",
  "task_id": "intent-v6-1-valid",
  "mode": "vlm_assisted",
  "intent_type": "browser_open_page",
  "draft_steps": [
    {
      "step_id": "draft-step-001",
      "description": "Draft a browser navigation capability.",
      "expected_runtime_capability": "browser.open_page",
      "target": "https://example.com",
      "precondition_hint": "Browser capability exists.",
      "verification_hint": "Runtime can read the page title after execution.",
      "risk": "low"
    }
  ],
  "required_runtime_capabilities": ["browser.open_page"],
  "assumptions": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "compile_required": true,
  "executor": "vlm",
  "provider_role": "assistive_only",
  "is_executable": false
}
'@

$agentDirectDraft = Write-Fixture 'agent_plan_draft_agent_direct_executor.json' @'
{
  "plan_id": "draft-v6-1-agent-direct",
  "task_id": "intent-v6-1-valid",
  "mode": "runtime",
  "intent_type": "browser_open_page",
  "draft_steps": [
    {
      "step_id": "draft-step-001",
      "description": "Draft a browser navigation capability.",
      "expected_runtime_capability": "browser.open_page",
      "target": "https://example.com",
      "precondition_hint": "Browser capability exists.",
      "verification_hint": "Runtime can read the page title after execution.",
      "risk": "low"
    }
  ],
  "required_runtime_capabilities": ["browser.open_page"],
  "assumptions": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "compile_required": true,
  "executor": "agent_direct",
  "provider_role": "none",
  "is_executable": false
}
'@

$vlmDirectRoleDraft = Write-Fixture 'agent_plan_draft_vlm_direct_role.json' @'
{
  "plan_id": "draft-v6-1-vlm-direct",
  "task_id": "intent-v6-1-valid",
  "mode": "vlm_assisted",
  "intent_type": "browser_open_page",
  "draft_steps": [
    {
      "step_id": "draft-step-001",
      "description": "Draft a browser navigation capability.",
      "expected_runtime_capability": "browser.open_page",
      "target": "https://example.com",
      "precondition_hint": "Browser capability exists.",
      "verification_hint": "Runtime can read the page title after execution.",
      "risk": "low"
    }
  ],
  "required_runtime_capabilities": ["browser.open_page"],
  "assumptions": [],
  "risk_level": "low",
  "requires_confirmation": false,
  "compile_required": true,
  "executor": "runtime",
  "provider_role": "direct",
  "is_executable": false
}
'@

$malformedDraft = Write-Fixture 'agent_plan_draft_malformed.json' @'
{
  "plan_id": "draft-v6-1-malformed",
  "mode": "runtime",
  "draft_steps": [
'@

$cases = New-Object System.Collections.Generic.List[object]

function Add-Case {
    param(
        [string]$Name,
        [string]$Group,
        $CommandArgs,
        [bool]$ExpectOk,
        [string]$ExpectedError = '',
        $Expect = $null,
        $NonEmpty = $null,
        $ForbiddenText = $null
    )
    if ($null -eq $Expect) { $Expect = @{} }
    if ($null -eq $NonEmpty) { $NonEmpty = @() }
    if ($null -eq $ForbiddenText) { $ForbiddenText = @() }
    if ($Category -eq 'all' -or $Category -eq $Group) {
        $cases.Add([pscustomobject]@{
            Name = $Name
            Group = $Group
            Arguments = [string[]]$CommandArgs
            ExpectOk = $ExpectOk
            ExpectedError = $ExpectedError
            Expect = $Expect
            NonEmpty = $NonEmpty
            ForbiddenText = $ForbiddenText
        }) | Out-Null
    }
}

Add-Case 'TaskIntent explorer open path' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', $GoalOpenPath) $true '' @{
    'data.intent.intent_type' = 'explorer_open_path'
    'data.intent.target_path' = 'D:\testrepo\testwindow'
    'data.intent.risk_level' = 'low'
    'data.intent.requires_confirmation' = $false
}
Add-Case 'TaskIntent explorer delete file confirmation' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', $GoalDeleteFile) $true '' @{
    'data.intent.intent_type' = 'explorer_delete_file'
    'data.intent.target_path' = 'D:\testrepo\testwindow\da.txt'
    'data.intent.risk_level' = 'medium'
    'data.intent.requires_confirmation' = $true
}
Add-Case 'TaskIntent local form fill' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', $GoalLocalForm) $true '' @{
    'data.intent.intent_type' = 'browser_fill_form'
    'data.intent.target_app' = 'browser'
}
Add-Case 'TaskIntent browser open page' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', $GoalBrowserTitle) $true '' @{
    'data.intent.intent_type' = 'browser_open_page'
    'data.intent.target_app' = 'browser'
}
Add-Case 'TaskIntent empty task rejected' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', '') $false 'FAIL_EMPTY_TASK'
Add-Case 'TaskIntent ambiguous task classified unknown' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', $GoalAmbiguous) $true '' @{
    'data.intent.intent_type' = 'unknown'
    'data.intent.unsupported_reason' = 'ambiguous_task'
}
Add-Case 'TaskIntent active protection bypass blocked' 'intent' @('agent-intent-parse', '--mode', 'runtime', '--goal', $GoalBypassProtection) $true '' @{
    'data.intent.intent_type' = 'unknown'
    'data.intent.risk_level' = 'blocked'
    'data.intent.unsupported_reason' = 'active_protection_bypass'
}
Add-Case 'TaskIntent vlm_assisted mode accepted' 'intent' @('agent-intent-parse', '--mode', 'vlm_assisted', '--goal', $GoalBrowserTitle) $true '' @{
    'data.intent.mode' = 'vlm_assisted'
}

Add-Case 'AgentPlanDraft open path generated' 'draft' @('agent-plan-draft', '--mode', 'runtime', '--goal', $GoalOpenPath) $true '' @{
    'data.plan_draft.intent_type' = 'explorer_open_path'
    'data.plan_draft.executor' = 'runtime'
    'data.plan_draft.compile_required' = $true
    'data.plan_draft.is_executable' = $false
    'data.plan_draft.provider_role' = 'none'
} @('data.plan_draft.draft_steps') @('"action_type"', '"click"', '"type"', '"drag"')
Add-Case 'AgentPlanDraft delete requires confirmation' 'draft' @('agent-plan-draft', '--mode', 'runtime', '--goal', $GoalDeleteFile) $true '' @{
    'data.plan_draft.intent_type' = 'explorer_delete_file'
    'data.plan_draft.executor' = 'runtime'
    'data.plan_draft.requires_confirmation' = $true
    'data.plan_draft.risk_level' = 'medium'
    'data.plan_draft.is_executable' = $false
}
Add-Case 'AgentPlanDraft vlm assistive only' 'draft' @('agent-plan-draft', '--mode', 'vlm_assisted', '--goal', $GoalBrowserTitle) $true '' @{
    'data.plan_draft.mode' = 'vlm_assisted'
    'data.plan_draft.executor' = 'runtime'
    'data.plan_draft.provider_role' = 'assistive_only'
    'data.plan_draft.is_executable' = $false
}
Add-Case 'AgentPlanDraft empty task rejected' 'draft' @('agent-plan-draft', '--mode', 'runtime', '--goal', '') $false 'FAIL_EMPTY_TASK'
Add-Case 'AgentPlanDraft ambiguous task rejected' 'draft' @('agent-plan-draft', '--mode', 'runtime', '--goal', $GoalAmbiguous) $false 'FAIL_AMBIGUOUS_TASK'
Add-Case 'AgentPlanDraft blocked active protection rejected' 'draft' @('agent-plan-draft', '--mode', 'runtime', '--goal', $GoalBypassProtection) $false 'AGENT_PLAN_DRAFT_BLOCKED'

Add-Case 'Planner mode missing rejected' 'boundary' @('agent-intent-parse', '--goal', $GoalOpenPath) $false 'AGENT_MODE_INVALID'
Add-Case 'Planner mode empty rejected' 'boundary' @('agent-intent-parse', '--mode', '', '--goal', $GoalOpenPath) $false 'AGENT_MODE_INVALID'
Add-Case 'Planner mode unknown rejected' 'boundary' @('agent-intent-parse', '--mode', 'unknown', '--goal', $GoalOpenPath) $false 'AGENT_MODE_INVALID'
Add-Case 'Planner validator rejects vlm executor' 'boundary' @('agent-planner-validate', '--check', 'plan-draft', '--file', $vlmExecutorDraft) $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'Planner validator rejects agent_direct executor' 'boundary' @('agent-planner-validate', '--check', 'plan-draft', '--file', $agentDirectDraft) $false 'AGENT_EXECUTOR_INVALID'
Add-Case 'Planner validator rejects vlm direct role' 'boundary' @('agent-planner-validate', '--check', 'plan-draft', '--file', $vlmDirectRoleDraft) $false 'AGENT_PROVIDER_ROLE_INVALID'
Add-Case 'Planner validator rejects executable draft' 'boundary' @('agent-planner-validate', '--check', 'plan-draft', '--file', $executableDraft) $false 'AGENT_PLAN_DRAFT_EXECUTABLE'

Add-Case 'TaskIntent validator accepts valid intent' 'schema' @('agent-planner-validate', '--check', 'intent', '--file', $validIntent) $true
Add-Case 'TaskIntent validator rejects missing fields' 'schema' @('agent-planner-validate', '--check', 'intent', '--file', $missingIntent) $false 'TASK_INTENT_INVALID'
Add-Case 'TaskIntent validator rejects malformed JSON' 'schema' @('agent-planner-validate', '--check', 'intent', '--file', $malformedIntent) $false 'MALFORMED_JSON'
Add-Case 'AgentPlanDraft validator accepts valid draft' 'schema' @('agent-planner-validate', '--check', 'plan-draft', '--file', $validDraft) $true
Add-Case 'AgentPlanDraft validator rejects missing fields' 'schema' @('agent-planner-validate', '--check', 'plan-draft', '--file', $missingDraft) $false 'AGENT_PLAN_DRAFT_INVALID'
Add-Case 'AgentPlanDraft validator rejects malformed JSON' 'schema' @('agent-planner-validate', '--check', 'plan-draft', '--file', $malformedDraft) $false 'MALFORMED_JSON'

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

    $caseFailures = New-Object System.Collections.Generic.List[string]
    if ([bool]$json.ok -ne [bool]$case.ExpectOk) {
        $caseFailures.Add("ok expected $($case.ExpectOk), got $($json.ok)") | Out-Null
    }
    if ($case.ExpectOk -and $exitCode -ne 0) {
        $caseFailures.Add("expected exit 0, got $exitCode") | Out-Null
    }
    if (-not $case.ExpectOk -and $exitCode -eq 0) {
        $caseFailures.Add('expected non-zero exit') | Out-Null
    }
    if (-not $case.ExpectOk -and -not [string]::IsNullOrWhiteSpace($case.ExpectedError)) {
        $actualCode = if ($json.error) { $json.error.code } else { '' }
        if ($actualCode -ne $case.ExpectedError) {
            $caseFailures.Add("error expected $($case.ExpectedError), got $actualCode") | Out-Null
        }
    }

    foreach ($path in $case.Expect.Keys) {
        $actual = Get-JsonPathValue -Object $json -Path $path
        if (-not (Test-ExpectedValue -Actual $actual -Expected $case.Expect[$path])) {
            $caseFailures.Add("$path expected '$($case.Expect[$path])', got '$actual'") | Out-Null
        }
    }

    foreach ($path in $case.NonEmpty) {
        $actual = Get-JsonPathValue -Object $json -Path $path
        if ($null -eq $actual) {
            $caseFailures.Add("$path expected non-empty, got null") | Out-Null
        } elseif ($actual -is [System.Array] -and $actual.Count -eq 0) {
            $caseFailures.Add("$path expected non-empty array") | Out-Null
        } elseif (-not ($actual -is [System.Array]) -and [string]::IsNullOrWhiteSpace([string]$actual)) {
            $caseFailures.Add("$path expected non-empty value") | Out-Null
        }
    }

    foreach ($forbidden in $case.ForbiddenText) {
        if ($text -like "*$forbidden*") {
            $caseFailures.Add("forbidden text appeared in output: $forbidden") | Out-Null
        }
    }

    $status = if ($caseFailures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    if ($status -ne 'PASS') {
        $failures.Add("$($case.Name): $($caseFailures -join '; ')") | Out-Null
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
        case_failures = @($caseFailures)
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

$noFakePass = ($cases.Count -gt 0) -and ($failures.Count -eq 0) -and (@($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0)
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
    '# v6.1.0 Task Intent Planner Selftest Report',
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
    throw "v6.1.0 task intent planner selftest failed. Report: $Report"
}

Write-Host 'PASS: v6.1.0 task intent planner selftest'
Write-Host "Report: $Report"
