# Recovery Strategy Engine

Current version: `v3.7.0`.

DesktopVisual v3.4.0 replaces scattered TaskRunner recovery decisions with a finite Recovery Strategy Engine. The engine maps known error codes to explicit strategies, respects the effective `max_recoveries` after Safety Manifest clamping, and writes every recovery decision to the task report.

v4.4.0 extends the recovery vocabulary for dynamic UI perception states. The runtime can wait and re-observe `LOADING` or `TARGET_NOT_READY`, invalidate cache and re-locate for `ELEMENT_MOVED`, `STALE_CANDIDATE`, or `PAGE_REPAINT`, and record `ERROR_APPEARED`. `DIALOG_OPEN` requires a classified safe route or human confirmation. `BLOCKED` and `SAFETY_BLOCKED` stop immediately.

## Data Structures

`RecoveryStrategy`:

- `errorCode`
- `strategyName`
- `steps`
- `canAttempt`
- `stopReason`

`RecoveryAttemptRecord`:

- `stepIndex`
- `stepName`
- `errorCode`
- `strategyName`
- `attempt`
- `result`
- `details`
- `strategySteps`

## Strategy Table

| Error | Strategy | Recovery allowed |
| --- | --- | --- |
| `LOCATOR_NOT_FOUND` | `re-observe -> OCR fallback -> stop` | Yes, bounded by `max_recoveries` |
| `WINDOW_NOT_FOUND` | `find process/window -> activate -> stop` | Yes, bounded by `max_recoveries` |
| `LOCATOR_NOT_UNIQUE` | require explicit selector or `nth` | No |
| `TEXT_NOT_FOUND` | `wait -> re-observe -> stop` | Yes, bounded by `max_recoveries` |
| `SAFETY_POLICY_DENIED` | `stop_immediately` | No |

## TaskRunner Integration

`TaskRunner` calls the strategy engine after a failed step classification. Recoverable strategies consume the bounded recovery counter. Non-recoverable strategies are still recorded as `not_attempted` so the report shows why recovery was refused.

Service `/run-task` uses the same TaskRunner implementation, so service-generated reports include the same `## Recovery Strategy Engine` section as CLI reports.

## Report Fields

Task reports include:

- `max_recoveries_effective`
- `recovery_records`
- per-record `error`
- per-record `strategy`
- per-record `attempt`
- per-record `result`
- per-record `details`
- per-record `strategy_steps`

## Boundaries

Recovery does not bypass PermissionManager, SafetyPolicy, Safety Manifest, foreground checks, or immutable stop conditions. It must not guess coordinates, broaden window titles, choose from non-unique matches, retry safety-denied actions, or continue after protected desktop, credential, captcha, anti-cheat, or loop guard stops.

Dynamic UI recovery follows the same boundary. Blocked states are not VLM escalation opportunities; they are terminal stops. Unknown state is not considered target-ready.
