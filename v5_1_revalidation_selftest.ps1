param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_1_revalidation_selftest.ps1 [-Root <path>]'
    Write-Host 'Runs Phase 3 v5.1 StepContract and VerificationEngine revalidation checks.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$PhaseDir = Join-Path $Root 'artifacts\dev5.8.7_revalidation\phase_03_v5.1'
$TempDir = Join-Path $PhaseDir 'temp_v5_1_revalidation'
$Report = Join-Path $PhaseDir 'v5_1_revalidation_selftest_report.md'

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$Contract = Join-Path $Root 'tasks\step_contract\valid_local_form_submit.step.json'
$SchemaPath = Join-Path $Root 'tasks\step_contract\step_contract.schema.json'
$SampleLocalForm = Join-Path $Root 'samples\tasks\local_form_submit.task.json'
$SampleProblem = Join-Path $Root 'samples\tasks\local_problem_mock.task.json'
$Pass = Join-Path $Root 'tasks\step_contract\perception_pass.json'
$Missing = Join-Path $Root 'tasks\step_contract\perception_missing_element.json'
$WrongScene = Join-Path $Root 'tasks\step_contract\perception_wrong_scene.json'
$Before = Join-Path $Root 'tasks\step_contract\verification_before_submit.json'
$AfterSuccess = Join-Path $Root 'tasks\step_contract\verification_after_success.json'
$AfterWrongEvent = Join-Path $Root 'tasks\step_contract\verification_after_wrong_event.json'

foreach ($jsonPath in @($Contract, $SchemaPath, $SampleLocalForm, $SampleProblem, $Pass, $Missing, $WrongScene, $Before, $AfterSuccess, $AfterWrongEvent)) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}

function Invoke-JsonCommand {
    param([string[]]$Arguments)
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$outputs = New-Object System.Collections.Generic.List[string]

$schemaResult = Invoke-JsonCommand @('step-contract-validate', '--file', $Contract)
if ($schemaResult.ExitCode -ne 0 -or -not $schemaResult.Json.ok) { throw "StepContract schema validation failed. output=$($schemaResult.Text)" }
$schemaText = [System.IO.File]::ReadAllText([string]$SchemaPath, [System.Text.Encoding]::UTF8)
foreach ($field in @('step_id','name','preconditions','action','verification','timeout_ms','retry_policy','on_failure','safety_requirements','expected_scene_state','expected_change_events','expected_elements')) {
    if ($schemaText -notmatch [regex]::Escape($field)) { throw "Schema missing required field $field" }
}
$outputs.Add($schemaResult.Text) | Out-Null

$missingVerification = Invoke-JsonCommand @('step-contract-validate', '--file', (Join-Path $Root 'tasks\step_contract\invalid_missing_verification.step.json'))
if ($missingVerification.ExitCode -eq 0 -or $missingVerification.Json.ok) { throw "Missing required verification was not rejected." }
$outputs.Add($missingVerification.Text) | Out-Null

$prePass = Invoke-JsonCommand @('step-precondition-check', '--contract', $Contract, '--perception', $Pass)
if ($prePass.ExitCode -ne 0 -or -not $prePass.Json.ok) { throw "Precondition pass failed. output=$($prePass.Text)" }
$outputs.Add($prePass.Text) | Out-Null

$preMissing = Invoke-JsonCommand @('step-precondition-check', '--contract', $Contract, '--perception', $Missing)
if ($preMissing.ExitCode -eq 0 -or $preMissing.Json.ok -or $preMissing.Json.error.message -notmatch 'submit-button') { throw "Missing element test did not fail correctly. output=$($preMissing.Text)" }
$outputs.Add($preMissing.Text) | Out-Null

$preWrongScene = Invoke-JsonCommand @('step-precondition-check', '--contract', $Contract, '--perception', $WrongScene)
if ($preWrongScene.ExitCode -eq 0 -or $preWrongScene.Json.ok -or $preWrongScene.Json.error.message -notmatch 'scene_state') { throw "Wrong scene_state test did not fail correctly. output=$($preWrongScene.Text)" }
$outputs.Add($preWrongScene.Text) | Out-Null

$fieldDrivenContract = Join-Path $TempDir 'field_driven.step.json'
$fieldDrivenPerception = Join-Path $TempDir 'field_driven_perception.json'
@'
{
  "schema_version": "5.1.1",
  "step_id": "field_driven_precondition",
  "name": "Field driven precondition fixture",
  "preconditions": [
    { "type": "scene_state", "expected": "ready" },
    { "type": "element_exists", "element_id": "custom-button" },
    { "type": "target_ready", "expected": true },
    { "type": "window_focused", "expected": true },
    { "type": "profile_active", "profile": "custom_profile" },
    { "type": "safety_allowed", "action": "custom_click" },
    { "type": "capability_available", "capability": "custom_capability" }
  ],
  "action": { "type": "custom_click", "locator": "id:custom-button" },
  "verification": { "type": "text_appeared", "expected_text": "Done", "expected_scene_state": "done" },
  "timeout_ms": 500,
  "retry_policy": { "max_attempts": 1, "backoff_ms": 10 },
  "on_failure": { "strategy": "stop_task", "failure_reason": "PRECONDITION_FAILED" },
  "safety_requirements": { "permission_profile": "DEFAULT", "allow_unrestricted_desktop": false, "requires_human_confirmation": false },
  "expected_scene_state": "done",
  "expected_change_events": ["text_appeared"],
  "expected_elements": ["done-message"]
}
'@ | Set-Content -LiteralPath $fieldDrivenContract -Encoding UTF8
@'
{
  "schema_version": "5.1.2",
  "scene_state": { "status": "ready" },
  "target_ready": true,
  "window": { "focused": true },
  "profile": { "active": "custom_profile" },
  "safety": { "allowed_actions": ["custom_click"] },
  "capabilities": ["custom_capability"],
  "element_graph": { "nodes": [{ "element_id": "custom-button", "role": "button", "text": "Custom" }] }
}
'@ | Set-Content -LiteralPath $fieldDrivenPerception -Encoding UTF8

Get-Content -LiteralPath $fieldDrivenContract -Raw | ConvertFrom-Json | Out-Null
Get-Content -LiteralPath $fieldDrivenPerception -Raw | ConvertFrom-Json | Out-Null
$fieldDriven = Invoke-JsonCommand @('step-precondition-check', '--contract', $fieldDrivenContract, '--perception', $fieldDrivenPerception)
if ($fieldDriven.ExitCode -ne 0 -or -not $fieldDriven.Json.ok) { throw "Field-driven preconditions failed. output=$($fieldDriven.Text)" }
$outputs.Add($fieldDriven.Text) | Out-Null

$verifySuccess = Invoke-JsonCommand @('step-verify', '--contract', $Contract, '--before', $Before, '--after', $AfterSuccess, '--timeout-ms', '1000', '--elapsed-ms', '50')
if ($verifySuccess.ExitCode -ne 0 -or -not $verifySuccess.Json.ok) { throw "Verification text appeared test failed. output=$($verifySuccess.Text)" }
$outputs.Add($verifySuccess.Text) | Out-Null

$verifyTimeout = Invoke-JsonCommand @('step-verify', '--contract', $Contract, '--before', $Before, '--after', $AfterSuccess, '--timeout-ms', '1000', '--elapsed-ms', '1000')
if ($verifyTimeout.ExitCode -eq 0 -or $verifyTimeout.Json.ok -or $verifyTimeout.Json.error.code -ne 'VERIFICATION_TIMEOUT') { throw "Verification timeout did not fail correctly. output=$($verifyTimeout.Text)" }
$outputs.Add($verifyTimeout.Text) | Out-Null

$wrongEvent = Invoke-JsonCommand @('step-verify', '--contract', $Contract, '--before', $Before, '--after', $AfterWrongEvent, '--timeout-ms', '1000', '--elapsed-ms', '50')
if ($wrongEvent.ExitCode -eq 0 -or $wrongEvent.Json.ok -or $wrongEvent.Json.error.message -notmatch 'text_appeared') { throw "Wrong expected event did not fail correctly. output=$($wrongEvent.Text)" }
$outputs.Add($wrongEvent.Text) | Out-Null

$disappearContract = Join-Path $TempDir 'text_element_disappeared.step.json'
$disappearBefore = Join-Path $TempDir 'disappear_before.json'
$disappearAfter = Join-Path $TempDir 'disappear_after.json'
@'
{
  "schema_version": "5.1.1",
  "step_id": "remove_loading",
  "name": "Remove loading marker",
  "preconditions": [
    { "type": "scene_state", "expected": "loading" },
    { "type": "element_exists", "element_id": "loading" },
    { "type": "target_ready", "expected": true },
    { "type": "window_focused", "expected": true },
    { "type": "profile_active", "profile": "browser_local" },
    { "type": "safety_allowed", "action": "wait_mock" },
    { "type": "capability_available", "capability": "minimal_task_session_runner" }
  ],
  "action": { "type": "wait_mock", "locator": "id:loading" },
  "verification": {
    "type": "text_disappeared",
    "expected_text": "Loading",
    "expected_scene_state": "ready",
    "expected_change_events": ["text_disappeared", "element_disappeared", "region_changed"],
    "expected_elements": [{ "element_id": "loading", "condition": "disappeared" }]
  },
  "timeout_ms": 1000,
  "retry_policy": { "max_attempts": 1, "backoff_ms": 10 },
  "on_failure": { "strategy": "stop_task", "failure_reason": "VERIFICATION_TIMEOUT" },
  "safety_requirements": { "permission_profile": "DEFAULT", "allow_unrestricted_desktop": false, "requires_human_confirmation": false },
  "expected_scene_state": "ready",
  "expected_change_events": ["text_disappeared", "element_disappeared", "region_changed"],
  "expected_elements": [{ "element_id": "loading", "condition": "disappeared" }]
}
'@ | Set-Content -LiteralPath $disappearContract -Encoding UTF8
@'
{
  "schema_version": "5.1.3",
  "scene_state": { "status": "loading" },
  "change_events": [],
  "region_changed": false,
  "element_graph": { "nodes": [{ "element_id": "loading", "role": "text", "text": "Loading" }] },
  "text": "Loading"
}
'@ | Set-Content -LiteralPath $disappearBefore -Encoding UTF8
@'
{
  "schema_version": "5.1.3",
  "scene_state": { "status": "ready" },
  "change_events": ["text_disappeared", "element_disappeared", "region_changed"],
  "region_changed": true,
  "element_graph": { "nodes": [] },
  "text": "Ready"
}
'@ | Set-Content -LiteralPath $disappearAfter -Encoding UTF8

foreach ($jsonPath in @($disappearContract, $disappearBefore, $disappearAfter)) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}
$disappear = Invoke-JsonCommand @('step-verify', '--contract', $disappearContract, '--before', $disappearBefore, '--after', $disappearAfter, '--timeout-ms', '1000', '--elapsed-ms', '10')
if ($disappear.ExitCode -ne 0 -or -not $disappear.Json.ok -or $disappear.Json.data.text_disappeared_ok -ne $true) { throw "Text/element disappeared verification failed. output=$($disappear.Text)" }
$outputs.Add($disappear.Text) | Out-Null

$failure = Invoke-JsonCommand @('step-failure-classify', '--error-code', 'VERIFICATION_TIMEOUT', '--step-id', 'click_submit_and_verify')
if ($failure.ExitCode -ne 0 -or -not $failure.Json.ok -or -not $failure.Json.data.failure_reason -or -not $failure.Json.data.recommended_action) { throw "Failure reason classification failed. output=$($failure.Text)" }
$outputs.Add($failure.Text) | Out-Null

$runner = & (Join-Path $Root 'task_session_runner_selftest.ps1') -Root $Root 2>&1
$runnerExit = $LASTEXITCODE
$runnerText = ($runner | Out-String).Trim()
if ($runnerExit -ne 0) { throw "Minimal task runner with verification smoke failed. output=$runnerText" }

$lines = @(
    '# Phase 3 v5.1 Revalidation Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- Scope: StepContract schema, sample parse, preconditions, verification, failure reason subset, minimal task runner smoke.',
    '',
    '## Command Outputs',
    '',
    '```json'
)
$lines += $outputs
$lines += @(
    '```',
    '',
    '## Minimal Runner Output',
    '',
    '```text',
    $runnerText,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: Phase 3 v5.1 revalidation selftest'
Write-Host "Report: $Report"
