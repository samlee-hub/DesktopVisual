# DesktopVisual Core Wait-State Hardening

Current version: `v1.1.6`.

## Purpose

v1.1.6 replaces selected fixed core `Sleep` waits with observable state waits. A state wait waits up to a maximum budget, polls a concrete Runtime state every 30-50 ms, exits as soon as the state is ready, and records the outcome in report/latency evidence.

Fixed sleeps hide whether Runtime was waiting for focus, foreground, recovery context, or editor buffer stability. State waits make those waits auditable through fields such as `wait_site`, `wait_reason`, `wait_budget_ms`, `wait_actual_ms`, `wait_exit_reason`, `wait_state_ready`, and timeout/not-replaced counts.

## Principles

- Maximum budget is preserved: replacing `Sleep(500)` means wait at most about 500 ms.
- Early exit is allowed only when the declared state is satisfied.
- Timeout is recorded and does not silently become success.
- The original recovery order, fallback order, input strategy, and action parameters are preserved.
- No wait is replaced with a hard-coded title, special-case app, or unconditional shorter delay.

## Core Scope

v1.1.6 applies only to core execution-chain waits in:

- `TaskRunner` recovery waits.
- `ForegroundPreparation` foreground/focus/window settling waits.
- `SafeContextRecovery` conservative context recovery waits.
- `CursorAndBufferStateGuard` cursor/buffer visible verification stabilization.
- `CodeEditorTypingPolicy` only where a short wait can be safely observed or explicitly marked as not state-replaced.

## Non-Goals

- Explorer workflow waits are not optimized in v1.1.6.
- Browser workflow waits are not optimized in v1.1.6.
- Full Code workflow behavior is not changed.
- UIA event listener architecture is not refactored.
- VLM providers, VLM timeouts, provider wrappers, OpenAI/Anthropic APIs, daemon/service mode, permissions, and public release policy are not changed.

Workflow-level wait hardening is reserved for v1.1.7.

## Wait Definition

A state wait records:

- `wait_site`: code location.
- `wait_reason`: why Runtime is waiting.
- `wait_budget_ms`: maximum allowed wait.
- `wait_poll_interval_ms`: poll interval, normally 30-50 ms.
- `wait_actual_ms`: elapsed wait time.
- `wait_exit_reason`: `state_ready`, `timeout`, `skipped`, `failed`, or `not_state_replaced`.
- `state_ready` / `wait_state_ready`: whether the state was satisfied.
- `wait_replaced_from_sleep_ms`: original fixed sleep budget when replaced.

The helper is `CoreWaitState` in:

```text
src\winagent\CoreWaitState.h
src\winagent\CoreWaitState.cpp
```

## Latency Fields

v1.1.6 keeps `latency_observability.v1` and adds/fills:

- `fixed_sleep_wait_ms`
- `state_wait_total_ms`
- `state_wait_saved_ms`
- `wait_site`
- `wait_reason`
- `wait_budget_ms`
- `wait_actual_ms`
- `wait_exit_reason`
- `wait_replaced_from_sleep_ms`
- `wait_state_ready`
- `wait_timeout_count`
- `wait_not_replaced_count`
- `wait_not_replaced_reasons`

These fields are emitted by Runtime/report code, including `winagent.exe latency-baseline`; scripts may validate them but do not fabricate them.

## Safe Replacement Criteria

A fixed wait can be replaced when Runtime can observe a state that matches the wait's original reason, such as:

- target window is foreground;
- foreground/focus is stable across polls;
- target window remains valid and responsive;
- recovery context markers are visible;
- visible editor buffer can be read and no old code residue remains.

If Runtime cannot observe a reliable state, the wait remains fixed and is recorded or documented as `not_state_replaced`.

## Retained Waits

Retained waits are allowed when replacing them would be less safe than keeping the original delay. Examples:

- localized Run dialog readiness after `WIN+R`;
- browser address-bar selection/text commit state that is not exposed reliably across browsers;
- editor autocomplete insertion state where UIA/OCR cannot reliably distinguish readiness;
- code editor line delay, because it is input pacing and v1.1.6 must not change character or line delay semantics.

Retained waits must include a reason in Runtime evidence where practical and in `artifacts\dev1.1.6_core_wait_state_hardening\not_replaced_waits.md`.
