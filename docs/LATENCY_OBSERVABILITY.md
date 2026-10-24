# DesktopVisual Latency Observability

Current version: `v1.1.10`.

Current authority: `..\CURRENT_EXECUTION_CONTRACT.md`.

Release channel details: `RELEASE_CHANNELS.md`.

## Purpose

v1.1.4 added a reusable Runtime/report latency schema and first-action baseline. v1.1.5 keeps that schema and adds VLM lazy loading, cache, negative cache, and fast-degradation fields so Runtime-only paths can prove they did not wait for provider probing. v1.1.6 keeps the same schema name and adds core wait-state fields so Runtime can prove which fixed waits were replaced, how long state waits actually took, and which waits remain not state-replaced. v1.1.7 extends the same schema with workflow wait fields for Explorer, Browser, and safely observable Code/IDE workflow waits. v1.1.8 keeps the v1.1.7 fields available while consolidating evidence and preparing field tests. v1.1.9 adds targeted event timeline v2 and wait saved de-duplication evidence for the Visual Studio C++ hardening path. v1.1.10 adds event timeline v2.1 no-overlap and first-action proxy closure evidence without changing VLM lazy/cache/degrade behavior.

## Scope

The v1.1.4 scope was Runtime/report/evidence instrumentation, baseline generation, and selftests. v1.1.5 may extend the same Runtime/report/evidence surface for VLM capability probe/cache/degrade behavior. v1.1.6 may extend the same Runtime/report/evidence surface for core wait-state behavior. v1.1.7 may extend the same Runtime/report/evidence surface for workflow wait-state behavior. v1.1.8 may run the same baseline and selftests. v1.1.9 may add event timeline v2 fixture evidence and de-duplicated wait saved report evidence. v1.1.10 may add event timeline v2.1 and first-action proxy fixture evidence; it must not change VLM behavior or VLM timeout.

v1.1.10 may update evidence indexes, documentation, event timeline fixture reports, and first-action proxy fixture reports. It must not replace additional fixed waits outside the targeted hardening scope, change permission decisions, change VLM provider behavior, or change VLM timeout.

## Metrics Schema

The current schema name is `latency_observability.v1`.

Core task timestamps:

- `task_received_ts`
- `runtime_start_ts`
- `permission_check_start_ts`
- `permission_check_end_ts`
- `policy_check_start_ts`
- `policy_check_end_ts`
- `foreground_prepare_start_ts`
- `foreground_prepare_end_ts`
- `first_observe_start_ts`
- `first_observe_end_ts`
- `first_action_start_ts`
- `first_action_end_ts`
- `task_end_ts`

Core duration fields:

- `total_task_latency_ms`
- `first_action_latency_ms`
- `permission_check_ms`
- `policy_check_ms`
- `foreground_prepare_ms`
- `first_observe_ms`
- `first_action_ms`

Observe and evidence fields:

- `screenshot_ms`
- `uia_ms`
- `ocr_ms`
- `frame_registry_write_ms`
- `evidence_write_ms`
- `observe_total_ms`

VLM fields:

- `vlm_probe_attempted`
- `vlm_probe_ms`
- `vlm_cache_hit`
- `vlm_cache_state`
- `vlm_provider_startup_ms`
- `vlm_exec_ms`
- `vlm_total_ms`
- `vlm_unavailable`
- `vlm_timeout`
- `vlm_required`
- `vlm_assist_allowed`
- `vlm_used_for_action`
- `vlm_degraded_to_runtime_only`
- `vlm_probe_reason`
- `vlm_skip_reason`

Recovery and wait fields:

- `recovery_attempted`
- `recovery_wait_ms`
- `fixed_sleep_wait_ms`
- `state_wait_total_ms`
- `state_wait_saved_ms`
- `wait_reason`
- `wait_site`
- `wait_budget_ms`
- `wait_actual_ms`
- `wait_exit_reason`
- `wait_replaced_from_sleep_ms`
- `wait_state_ready`
- `wait_timeout_count`
- `wait_not_replaced_count`
- `wait_not_replaced_reasons`

Workflow wait fields:

- `workflow_wait_total_ms`
- `workflow_wait_saved_ms`
- `workflow_wait_timeout_count`
- `workflow_wait_not_replaced_count`
- `workflow_wait_sites`
- `workflow_wait_replaced_from_sleep_ms`
- `workflow_wait_exit_reasons`
- `explorer_wait_total_ms`
- `explorer_wait_saved_ms`
- `browser_wait_total_ms`
- `browser_wait_saved_ms`
- `code_workflow_wait_total_ms`
- `code_workflow_wait_saved_ms`

External agent and startup fields:

- `codex_thinking_gap_ms`
- `external_agent_planning_ms`
- `skill_context_load_ms`
- `winagent_process_start_ms`
- `powershell_startup_ms`
- `runner_startup_ms`

Status fields:

- `first_action_reason`
- `unavailable_fields`
- `notes`

## first_action_latency_ms Definition

`first_action_latency_ms` is the elapsed time from when Runtime receives a task or command to the start of the first real externally visible action.

The first real externally visible action includes mouse move, mouse click, keyboard input, paste, window focus action, browser navigation action, file operation action, IDE action, or equivalent user-visible Runtime action.

The following do not count as first action:

- Reading config.
- Parsing JSON.
- Permission checks.
- Policy checks.
- Report generation.
- Pure internal observe.
- Pure internal locate.
- Pure internal VLM probe.
- Pure internal planning.
- Evidence directory creation.

If a task has no real externally visible action, `first_action_latency_ms` is `null` and `first_action_reason` records the reason, such as `no_action_task`, `stopped_before_action`, `blocked_before_action`, or `failed_before_action`.

## Observe Timing Fields

`first_observe_ms` measures the first observe or read-only surface snapshot interval when one occurs.

`observe_total_ms` is the total measured observe path for a scenario. In the v1.1.4 baseline command, the `runtime_foreground_snapshot` scenario performs a read-only foreground-window snapshot and records `first_observe_ms` and `observe_total_ms`. It does not focus a window, move the mouse, type, click, or call VLM.

`screenshot_ms`, `uia_ms`, `ocr_ms`, and `frame_registry_write_ms` are `null` when that sub-path is not executed by the scenario.

## VLM Timing Fields

VLM timing fields are present in the schema even when VLM is not required. A scenario that does not require VLM sets:

- `vlm_required=false`
- `vlm_assist_allowed=false`
- `vlm_probe_attempted=false`
- `vlm_cache_hit=false`
- `vlm_cache_state=not_checked`
- `vlm_used_for_action=false`
- `vlm_degraded_to_runtime_only=false`
- `vlm_skip_reason=not_required` or `runtime_only_path`
- VLM duration fields to `null`

This records the absence of VLM work without implying a zero-cost provider call.

## v1.1.5 VLM Lazy/Cache/Degrade Fields

Runtime-only commands, metadata, no-action baselines, and ordinary observe/UIA/OCR paths must not run PowerShell, `tools\codex_vlm_provider.ps1`, `codex --version`, `codex exec --help`, or `codex exec --image` only to discover VLM capability. They report `vlm_probe_attempted=false` with `vlm_skip_reason=not_required` or `runtime_only_path`.

VLM-required commands set `vlm_required=true`. VLM-assist locate commands set `vlm_assist_allowed=true` and keep `vlm_used_for_action=false` because the provider returns candidates only; Runtime owns any later action.

Capability cache reporting:

- `vlm_cache_hit=false`, `vlm_cache_state=positive_miss_written`: provider was probed and available status was cached.
- `vlm_cache_hit=false`, `vlm_cache_state=negative_miss_written`: provider was probed and unavailable/failed/timeout status was cached.
- `vlm_cache_hit=true`, `vlm_cache_state=positive_hit`: cached available status avoided a repeat probe.
- `vlm_cache_hit=true`, `vlm_cache_state=negative_hit`: cached unavailable/failed/timeout status avoided a repeat slow probe.
- `vlm_cache_state=disabled`: cache was explicitly disabled.

Unavailable provider, missing provider, wrapper failure, unsupported `codex exec --image`, invalid probe output, and probe timeout report `vlm_unavailable=true`. Timeout-like failures also report `vlm_timeout=true`. Non-required VLM-assist paths report `vlm_degraded_to_runtime_only=true` so callers can continue Runtime-only work instead of failing ordinary tasks.

`vlm_probe_reason` records why a real probe ran, such as `vlm_required` or `vlm_assist_allowed`. `vlm_skip_reason` records why no probe ran, such as `not_required`, `runtime_only_path`, `cache_negative`, or `cache_positive_not_needed`.

Capability probe timeout is separate from actual VLM inference timeout. The default capability probe timeout is centralized at 12000 ms. Actual VLM inference timeout remains separately configurable and defaults to 60000 ms for provider locate calls.

## Recovery And Wait-State Timing Fields

`recovery_attempted` records whether a recovery path ran. `recovery_wait_ms` is `null` unless recovery wait timing is actually observed.

`fixed_sleep_wait_ms` records retained fixed waits that still execute because no reliable state predicate is available. In v1.1.6 this should trend down for core waits and remain explicit for `not_state_replaced` cases.

`state_wait_total_ms` records actual elapsed time spent in core state waits. `state_wait_saved_ms` records budget saved when a wait replaced a fixed sleep and exited early because `wait_state_ready=true`.

`wait_site` and `wait_reason` identify the call site and state being waited on. `wait_budget_ms` is the maximum wait budget. `wait_actual_ms` is the measured wait time. `wait_exit_reason` is `state_ready`, `timeout`, `skipped`, `failed`, or `not_state_replaced`.

`wait_replaced_from_sleep_ms` records the original fixed sleep budget for a replaced wait. `wait_timeout_count` counts waits that reached their maximum budget. `wait_not_replaced_count` and `wait_not_replaced_reasons` report waits retained because the Runtime cannot safely observe the relevant state.

v1.1.6 Runtime/report output includes a `core_state_wait_probe` latency scenario and aggregate core wait fields. v1.1.7 adds a `workflow_state_wait_probe` scenario and aggregate workflow wait fields. Scripts validate these fields but do not fabricate them.

## v1.1.7 Workflow Wait-State Timing Fields

`workflow_wait_total_ms` records actual elapsed time spent in stateized workflow waits. `workflow_wait_saved_ms` records saved budget when a workflow wait replaced a fixed sleep and exited early.

`workflow_wait_timeout_count` counts workflow waits that reached their maximum budget. `workflow_wait_not_replaced_count` counts retained fixed workflow waits that were explicitly recorded as `not_state_replaced`.

`workflow_wait_sites`, `workflow_wait_replaced_from_sleep_ms`, and `workflow_wait_exit_reasons` provide machine-readable detail for replacement audit and baseline comparison.

`explorer_wait_total_ms` / `explorer_wait_saved_ms`, `browser_wait_total_ms` / `browser_wait_saved_ms`, and `code_workflow_wait_total_ms` / `code_workflow_wait_saved_ms` split the workflow wait totals by workflow category.

Explorer and Browser workflow result JSON emits `workflow_wait_summary` and `workflow_waits` so real UI sanity evidence can show the exact wait site, reason, budget, actual duration, exit reason, and not-replaced reason.

## Unavailable And Null Semantics

Fields that are not measured in a scenario must be `null` and listed in `unavailable_fields`. They must not be filled with `0` unless a real measured path executed and the measured duration was actually zero.

Unavailable examples in the v1.1.4 baseline include external agent planning time, skill context load time, PowerShell startup time, and pre-main winagent process startup time. Those cannot be measured by the current in-process Runtime command, so they remain `null`.

## Baseline Artifact Layout

The v1.1.4 baseline runner writes:

- `artifacts\dev1.1.4_latency_observability_baseline\latency_baseline_summary.json`
- `artifacts\dev1.1.4_latency_observability_baseline\latency_baseline_runner.log`
- `artifacts\dev1.1.4_latency_observability_baseline\latency_observability_selftest.log`

The Runtime/report command also supports:

```powershell
E:\desktopvisualproject\desktopvisual\bin\winagent.exe latency-baseline --out E:\desktopvisualproject\desktopvisual\artifacts\latency\latest_latency_summary.json
```

The PowerShell runner calls this Runtime/report command. It does not fabricate core latency metrics itself.

The v1.1.5 VLM lazy/cache evidence runner writes:

- `artifacts\dev1.1.5_vlm_lazy_cache_fast_degradation\latency_baseline_v1_1_5.json`
- `artifacts\dev1.1.5_vlm_lazy_cache_fast_degradation\vlm_cache_report.json`
- `artifacts\dev1.1.5_vlm_lazy_cache_fast_degradation\vlm_unavailable_report.json`

The v1.1.6 core wait-state evidence writes:

- `artifacts\dev1.1.6_core_wait_state_hardening\latency_baseline_v1_1_6.json`
- `artifacts\dev1.1.6_core_wait_state_hardening\v1_1_5_vs_v1_1_6_wait_latency_comparison.md`
- `artifacts\dev1.1.6_core_wait_state_hardening\wait_replacement_summary.md`
- `artifacts\dev1.1.6_core_wait_state_hardening\not_replaced_waits.md`

The v1.1.7 workflow wait-state evidence writes:

- `artifacts\dev1.1.7_workflow_wait_state_hardening\latency_baseline_v1_1_7.json`
- `artifacts\dev1.1.7_workflow_wait_state_hardening\v1_1_6_vs_v1_1_7_workflow_wait_latency_comparison.md`
- `artifacts\dev1.1.7_workflow_wait_state_hardening\workflow_wait_replacement_summary.md`
- `artifacts\dev1.1.7_workflow_wait_state_hardening\not_replaced_workflow_waits.md`

The v1.1.8 workspace hygiene evidence writes:

- `artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\latency_baseline_v1_1_8.json`
- `artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\latency_baseline_runner.log`
- `artifacts\EVIDENCE_INDEX.md`
- `artifacts\dev1.1.8_workspace_hygiene_field_test_readiness\workspace_file_classification.md`

## Non-Goals For v1.1.8

- No permission reduction.
- No `desktop_release` sync.
- No public restricted release creation.
- No public-dist tree creation.
- No VLM behavior, timeout, lazy/cache/degrade, or provider wrapper change.
- No CoreWaitState or WorkflowWaitState behavior change.
- No new Sleep replacement.
- No workflow fallback order change.
- No mouse or keyboard action parameter change.
- No benchmark or public packaging work.
- No daemon/service mode.
- No OpenAI or Anthropic native API integration.
- No VLM timeout or provider wrapper change.

## Future Use After v1.1.8

v1.2.0 should use the v1.1.4 through v1.1.8 baseline and evidence index to run benchmark and demo-ready comparisons without redefining earlier baselines after the fact.
