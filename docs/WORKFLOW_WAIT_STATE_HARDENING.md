# DesktopVisual v1.1.7 Workflow Wait-State Hardening

Current version: `v1.1.7`.

Current authority: `..\CURRENT_EXECUTION_CONTRACT.md`.

## Purpose

v1.1.7 replaces selected workflow-level fixed `Sleep` waits with bounded state waits that can exit early when the workflow state is ready. The goal is lower latency without changing workflow success criteria, fallback order, action order, safety policy, or permission semantics.

The rule is:

> Wait up to the original budget, poll observable state, continue early only when the declared state predicate is ready.

## Scope

Explorer workflow waits:

- Explorer window readiness.
- Directory/list stability after opening or scrolling.
- Selection changes.
- File appears, disappears, or is renamed.
- Move/delete operation readiness.
- Context menu action result readiness when the result is safely observable.

Browser workflow waits:

- Browser window and foreground readiness.
- Navigation and page readiness.
- Text/title/URL or marker appearance.
- Frame stability after scrolling.
- Form field value appearance.
- Submit result marker readiness.

Code/IDE workflow waits:

- Safe only when editor readiness, buffer text, run output, build output, title/tab changes, save indicators, or status bar readiness are observable.
- v1.1.7 does not change code input strategy, default char/line delay semantics, paste policy, or Run/Build fallback order.
- Current broader IDE executor paths do not expose a stable real IDE wait surface in this workspace; IDE-specific workflow waits may remain blocked or not state-replaced with evidence.

## Non-Goals

v1.1.7 does not:

- Change PermissionManager semantics.
- Modify `config\safety_manifest.json` or `config\safety.conf`.
- Change VLM lazy/cache/degrade behavior, VLM timeout, or provider wrappers.
- Change TaskRunner recovery strategy order.
- Change v1.1.6 core wait behavior except nonbehavioral helper reuse.
- Change mouse or keyboard action parameters.
- Change Explorer, Browser, or Code workflow fallback order.
- Sync `desktop_release`.
- Create a public restricted release.
- Create a public-dist tree.
- Run benchmark or public packaging work; that starts at v1.2.0.

## State Wait Definition

A workflow state wait has:

- `workflow_name`
- `workflow_category`
- `wait_site`
- `wait_reason`
- `wait_state_predicate`
- `wait_budget_ms`
- `wait_poll_interval_ms`
- `wait_actual_ms`
- `wait_exit_reason`
- `wait_replaced_from_sleep_ms`
- `state_wait_saved_ms`

Exit reasons are:

- `state_ready`: the predicate became true before or at the budget.
- `timeout`: the maximum budget elapsed.
- `skipped`: the budget was zero.
- `failed`: predicate execution failed.
- `not_state_replaced`: the fixed wait is retained because no safe predicate exists.

## Principles

Maximum budget principle:

- The original fixed wait budget remains the upper bound.
- A 700 ms workflow wait may exit at 40 ms if state is ready, but it may still wait up to about 700 ms.

Early exit principle:

- Early exit requires a declared predicate such as `WaitUntilExplorerWindowReady`, `WaitUntilFileRenamed`, `WaitUntilBrowserFrameStable`, or `WaitUntilTextAppears`.
- A shorter unconditional sleep is not a valid replacement.

No semantic change principle:

- Workflow action order stays the same.
- Fallback order stays the same.
- Safety stops still win over readiness.
- Existing verification still decides PASS/BLOCKED.

Not-state-replaced principle:

- If a state cannot be observed safely and generically, the wait stays fixed.
- The retained wait must be recorded with a `not_state_replaced` reason in evidence.
- Examples include arbitrary target application readiness after opening an unknown file type, Windows Run dialog input readiness, browser address-bar selection state, and Explorer inline rename edit state across view modes.

## Latency And Report Fields

v1.1.7 extends `latency_observability.v1` with workflow wait fields:

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

Explorer and Browser workflow result JSON also emits:

- `workflow_wait_summary`
- `workflow_waits`

The Runtime/report command emits machine-readable JSON. Evidence files add human-readable replacement and not-replaced summaries.

## Safe Replacement Checklist

A fixed workflow wait can be replaced when all of these are true:

- The predicate observes the same readiness the fixed wait was meant to cover.
- The predicate is generic, not hardcoded to a one-off window title or test case.
- The maximum wait budget is preserved.
- Timeout still allows the original verification/failure path to decide the result.
- No extra click, type, file operation, fallback, or recovery action is introduced.

A fixed workflow wait must remain not state-replaced when:

- The ready state is not observable through available Win32/UIA/window/file evidence.
- The state would require app-specific private knowledge.
- The replacement would change fallback order or success conditions.
- The wait is actually input pacing rather than readiness waiting.

## v1.2.0 Handoff

v1.2.0 should use the workflow wait fields to run benchmark and demo-ready comparisons:

- Compare v1.1.6 and v1.1.7 `workflow_wait_saved_ms`.
- Separate Explorer, Browser, and Code/IDE totals.
- Track timeout and not-replaced counts as residual risk.
- Use real UI sanity evidence before any `desktop_release` sync.
