param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'action_batch_performance_report.md'
$Plan = Join-Path $OutDir 'pycharm_current_main_batch_plan.json'
$Result = Join-Path $OutDir 'pycharm_current_main_batch_result.json'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

@'
{
  "dry_run": true,
  "profile": "pycharm-current-main-performance",
  "target": {
    "title": "dry-run-target",
    "process": "pycharm64.exe",
    "allow_dry_run_target": true
  },
  "steps": [
    { "operation_id": "op-001", "action": "foreground-preempt" },
    { "operation_id": "op-002", "action": "acquire-target-lock" },
    { "operation_id": "op-003", "action": "global-screenshot" },
    { "operation_id": "op-004", "action": "focus-editor" },
    { "operation_id": "op-005", "action": "visible-text-input", "typing_profile": "fast-real-keyboard", "char_delay_ms": 0, "line_delay_ms": 0, "batch_key_events": true },
    { "operation_id": "op-006", "action": "save-hotkey" },
    { "operation_id": "op-007", "action": "run-hotkey" },
    { "operation_id": "op-008", "action": "wait-condition", "condition": "wait-until-output-visible", "timeout_ms": 30000 },
    { "operation_id": "op-009", "action": "global-verification-screenshot" },
    { "operation_id": "op-010", "action": "visible-ui-verify" }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $Plan

$output = & $WinAgent visible-action-batch --plan $Plan --out $Result
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "visible-action-batch performance selftest exited $exit`: $text" }
$json = $text | ConvertFrom-Json

Assert ($json.ok -eq $true) 'visible-action-batch performance selftest must pass.'
Assert ($json.data.action_batch_enabled -eq $true) 'Action batch must be enabled.'
Assert ($json.data.profile -eq 'pycharm-current-main-performance') 'PyCharm performance profile must be recognized.'
Assert ($json.data.operation_timeline.Count -eq 10) 'Batch must emit sub-action timeline entries.'
Assert ($json.data.fixed_sleep_total_ms -eq 0) 'Batch must not use fixed sleeps.'
Assert ($json.data.operation_gap_gt_5s_count -eq 0) 'Batch must not have operation gaps over 5 seconds.'
Assert ($json.data.silent_gap_gt_5s_count -eq 0) 'Batch must not have silent gaps over 5 seconds.'
Assert ($json.data.foreground_preempt_full_count -eq 1) 'Batch must run one full foreground preempt.'
Assert ($json.data.target_lock_cache_hit_count -ge 1) 'Batch must reuse target lock cache.'
Assert ($json.data.global_frame_cache_hit_count -ge 1) 'Batch must reuse global frame cache before invalidation.'
Assert ($json.data.structured_text_input_fast_path_enabled -eq $true) 'Batch must enable structured text fast path.'
Assert ($json.data.outer_process_roundtrips_reduced -eq $true) 'Batch must reduce outer process roundtrips.'

@(
    '# Action Batch Performance Report',
    '',
    '- result: PASS',
    '- action_batch_enabled: true',
    "- profile: $($json.data.profile)",
    "- action_count: $($json.data.action_count)",
    "- fixed_sleep_total_ms: $($json.data.fixed_sleep_total_ms)",
    "- operation_gap_gt_5s_count: $($json.data.operation_gap_gt_5s_count)",
    "- silent_gap_gt_5s_count: $($json.data.silent_gap_gt_5s_count)",
    "- foreground_preempt_full_count: $($json.data.foreground_preempt_full_count)",
    "- target_lock_cache_hit_count: $($json.data.target_lock_cache_hit_count)",
    "- global_frame_cache_hit_count: $($json.data.global_frame_cache_hit_count)",
    "- structured_text_input_fast_path_enabled: $($json.data.structured_text_input_fast_path_enabled)",
    "- outer_process_roundtrips_reduced: $($json.data.outer_process_roundtrips_reduced)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS deterministic_action_batch_performance_selftest'
exit 0
