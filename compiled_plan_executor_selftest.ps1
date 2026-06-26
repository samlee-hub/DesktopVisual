param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$CaseDir = Join-Path $EvidenceRoot 'selftest\compiled_plan_executor'
New-Item -ItemType Directory -Force -Path $CaseDir | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
}

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Contract = Join-Path $CaseDir 'valid_contract.json'
$Result = Join-Path $CaseDir 'execution_result.json'

@'
{
  "schema_version": "6.3.0.step_contract",
  "contracts": [
    {
      "contract_id": "contract-executor-selftest",
      "task_id": "task-executor-selftest",
      "plan_id": "plan-executor-selftest",
      "step_id": "open-local-path",
      "step_index": 0,
      "step_type": "action",
      "runtime_action": "explorer_open_path",
      "target": "D:\\testrepo\\testwindow",
      "input_text": "",
      "expected_context": {
        "expected_process_pattern": "",
        "expected_title_pattern": "testwindow",
        "required_markers": ["testwindow"],
        "wrong_page_patterns": [],
        "active_protection_patterns": [],
        "credential_required_patterns": [],
        "foreground_required": false,
        "window_binding_required": false
      },
      "action_precondition": {
        "target_required": true,
        "target_unique_required": false,
        "target_inside_viewport_required": false,
        "target_current_observe_required": false,
        "focus_required": false,
        "mouse_first_required": false,
        "text_input_allowed": false,
        "scroll_allowed": false,
        "stale_target_reject_required": true
      },
      "verification_hint": {
        "verify_type": "verify_marker",
        "expected_marker": "testwindow",
        "expected_text": "",
        "expected_window_title": "",
        "expected_url_pattern": "",
        "expected_output_pattern": "",
        "expected_field_value": "",
        "post_action_reobserve_required": true
      },
      "risk_level": "LOW_RISK",
      "confirmation_policy": {
        "confirmation_required": false,
        "confirmation_reason": "",
        "developer_full_access_allowed": true,
        "public_release_confirmation_required": false,
        "manual_handoff_required": false
      },
      "recovery_policy": {
        "recovery_allowed": false,
        "recovery_scope": "none",
        "recovery_target": "",
        "max_recovery_attempts": 0,
        "resume_from_checkpoint_allowed": false,
        "replay_from_checkpoint_allowed": false,
        "stop_if_recovery_fails": true
      },
      "stop_policy": {
        "stop_on_wrong_context": true,
        "stop_on_wrong_field": true,
        "stop_on_target_stale": true,
        "stop_on_target_not_unique": true,
        "stop_on_active_protection": true,
        "stop_on_credential_required": true,
        "stop_on_unverified_result": true,
        "stop_on_runtime_guard_failure": true
      },
      "session_policy": {
        "session_required": true,
        "session_reuse_allowed": true,
        "force_reobserve_before_action": true,
        "cache_policy": "force_reobserve",
        "locator_cache_allowed": false
      },
      "evidence_policy": {
        "raw_evidence_required": true,
        "verifier_required": true,
        "gate_required": true,
        "mouse_evidence_required": false,
        "latency_required": true
      },
      "created_at": "2026-06-14T00:00:00Z",
      "compiler_version": "6.3.0",
      "executable": true
    }
  ]
}
'@ | Set-Content -Encoding UTF8 $Contract

& $WinAgent execute-step-contract --input $Contract --mode execute-local-safe --output $Result --evidence-dir $CaseDir | Out-File -Encoding utf8 (Join-Path $CaseDir 'execute.stdout.json')
if ($LASTEXITCODE -ne 0) {
    throw "execute-step-contract failed with exit code $LASTEXITCODE"
}

$json = Get-Content -Raw $Result | ConvertFrom-Json
if (-not $json.execution_summary.validation_ok) { throw 'validation_ok was not true' }
if (-not $json.execution_summary.runtime_executed) { throw 'runtime_executed was not true' }
if (-not $json.execution_summary.session_used) { throw 'session_used was not true' }
if (-not $json.execution_summary.step_contract_validator_used) { throw 'validator was not used' }
if (-not $json.execution_summary.runtime_context_guard_used) { throw 'runtime context guard was not used' }
if (-not $json.execution_summary.evidence_pack_created) { throw 'evidence pack was not created' }
if ($json.execution_summary.final_status -ne 'PASS') { throw "unexpected final_status $($json.execution_summary.final_status)" }

"COMPILED_PLAN_EXECUTOR_SELFTEST_PASS"
