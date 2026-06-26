param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$CaseDir = Join-Path $EvidenceRoot 'selftest\execution_evidence_pack'
New-Item -ItemType Directory -Force -Path $CaseDir | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
}

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Contract = Join-Path $CaseDir 'dry_run_contract.json'
$Result = Join-Path $CaseDir 'execution_result.json'

@'
{
  "schema_version": "6.3.0.step_contract",
  "contracts": [
    {
      "contract_id": "contract-evidence-selftest",
      "task_id": "task-evidence-selftest",
      "plan_id": "plan-evidence-selftest",
      "step_id": "dry-run-observe",
      "step_index": 0,
      "step_type": "action",
      "runtime_action": "observe",
      "target": "mock page",
      "input_text": "",
      "expected_context": {
        "expected_process_pattern": "",
        "expected_title_pattern": "mock",
        "required_markers": ["mock"],
        "wrong_page_patterns": [],
        "active_protection_patterns": [],
        "credential_required_patterns": [],
        "foreground_required": false,
        "window_binding_required": false
      },
      "action_precondition": {
        "target_required": false,
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
        "expected_marker": "mock",
        "expected_text": "",
        "expected_window_title": "",
        "expected_url_pattern": "",
        "expected_output_pattern": "",
        "expected_field_value": "",
        "post_action_reobserve_required": true
      },
      "risk_level": "READ_ONLY",
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

& $WinAgent execute-step-contract --input $Contract --mode dry-run --output $Result --evidence-dir $CaseDir | Out-File -Encoding utf8 (Join-Path $CaseDir 'dry_run.stdout.json')
if ($LASTEXITCODE -ne 0) {
    throw "execute-step-contract dry-run failed with exit code $LASTEXITCODE"
}

$json = Get-Content -Raw $Result | ConvertFrom-Json
if ($json.execution_summary.runtime_executed) { throw 'dry-run runtime_executed was not false' }
if (-not $json.execution_summary.session_steps_generated) { throw 'session steps were not generated' }
if (-not (Test-Path (Join-Path $CaseDir 'step_results.jsonl'))) { throw 'step_results.jsonl missing' }
if (-not (Test-Path (Join-Path $CaseDir 'evidence_index.md'))) { throw 'evidence_index.md missing' }
if (-not (Test-Path (Join-Path $CaseDir 'execution_report.md'))) { throw 'execution_report.md missing' }

"EXECUTION_EVIDENCE_PACK_SELFTEST_PASS"
