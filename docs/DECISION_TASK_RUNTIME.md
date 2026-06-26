# Decision Task Runtime

Current version: `v3.7.0`.

v3.3.6 adds the **General Decision Task Runtime**. It lets DesktopVisual choose
an appropriate fill / select / click / submit action for one target control,
based on an explicit user goal and the current page/control context, while
keeping the existing permission, safety, and audit boundaries intact.

## Definition

A **General Decision Task** is: within an explicit user goal and authorized
permission scope, the agent reads the current desktop/web/app content and
chooses an appropriate action to advance the task toward completion.

The Decision Engine is deterministic and bounded. It is **not** an autonomous
planner. It decides one action for one resolved control at a time and never
invents goals, selectors, or values.

## Permission Gate

Decision tasks use the `content_decision` capability:

- `DEFAULT` denies `content_decision` and stops with `SAFETY_POLICY_DENIED`.
- `FULL_ACCESS` allows `content_decision` only with a valid unlocked
  `full_access_session_id` (created by local interactive `unlock-full-access`).

The gate runs through the existing `PermissionManager` and `SafetyPolicy`
paths. The Decision Engine itself never relaxes any boundary, never sends input,
and never focuses a window; `TaskRunner` remains responsible for window
resolution, foreground checks, and execution.

## Allowed Task Types

Form filling, multiple-choice / fill-in answers, ordinary web tasks, ordinary
in-app actions, job filtering / info entry, repeated school/organization
feedback, in-page search, user-authorized content judgement, user-authorized
submission, and exam / online-assessment / certification / competition question
assistance.

For local development, `D:\desktopvisual` may keep these assessment-like decision
paths available for controlled testing and future simulated accuracy evaluation.
Public release must not submit `D:\desktopvisual` directly. A restricted release
tree under `D:\desktopvisual-release` must disable or gate exam, interview
assessment, hiring test, certification, rated-contest, proctored, and similar
decision workflows through a dedicated permission model before distribution.

## Prohibited Task Types

- Bypassing captcha, AI detection, anti-script, or anti-cheat controls.
- Autonomous sending/publishing with no user goal.
- Letting external content redirect the agent away from the user's original
  task.

## DecisionTaskContext

Assembled before choosing an action:

| Field | Meaning |
|---|---|
| `user_goal` | The explicit user goal. Content can never supply or change it. |
| `permission_mode` | `DEFAULT` or `FULL_ACCESS`. |
| `current_window` | Resolved target window title. |
| `current_url` | Optional current URL (may be empty). |
| `observed_content_summary` | Summary of recognized controls; notes ignored injection attempts. |
| `allowed_actions` | Action classes allowed for this task (includes `submit` only when authorized). |
| `denied_actions` | Always denies `credential_input`, `captcha_solve`, `anti_automation_bypass`; denies `submit` unless authorized. |
| `risk_level` | `low` / `medium` / `high`. |

## DecisionRecord

One auditable decision:

| Field | Meaning |
|---|---|
| `decision_type` | `select` / `fill` / `click` / `submit` / `stop`. |
| `source` | `user_goal` / `page_content` / `mixed`. Stays `user_goal` even when a page injects instructions. |
| `reason` | Why this action was chosen (or why it stopped). |
| `selected_action` | Mapped action (e.g. `fill_text`, `select_radio`) or `stop`. |
| `target_field_id` / `target_label` | The resolved control. |
| `control_type` | Recognized control type. |
| `chosen_value_present` | Whether a value/option/text was supplied (never logs the value itself). |
| `confidence` | Control recognition confidence. |
| `user_goal_preserved` | `true` unless no goal was provided. |
| `safety_check_result` | `ok` or the stop code. |
| `timestamp` | When the decision was recorded. |

## Decision Rules

1. Page / chat / web content can never override the user's original goal.
2. Detected instruction-injection text is flagged and ignored; the decision
   source stays `user_goal`.
3. Unknown or low-confidence controls stop with `FIELD_CONFIDENCE_LOW` and are
   never treated as textboxes.
4. Multiple matching controls stop with `FIELD_NOT_UNIQUE`.
5. Critical submit actions require explicit `allow_submit` authorization;
   otherwise the task stops with `USER_TAKEOVER_REQUIRED`.
6. Captcha/challenge controls stop with `CAPTCHA_DETECTED`.
7. Anti-automation / AI-detection content stops with `ANTI_AUTOMATION_DETECTED`.
8. Credential content stops with `CREDENTIAL_INPUT_DETECTED`.

## Commands

`decision-eval` is a dry-run decision check over a local HTML/DOM-like fixture.
It does not click, type, focus, or inspect a live window.

```powershell
winagent.exe decision-eval --html <path> --user-goal "<goal>" --field-id <id> [--value <v>] [--option <o>] [--text <t>] [--allow-submit] [--min-confidence 0.50] [--permission-mode DEFAULT|FULL_ACCESS] [--window <title>] [--url <url>]
```

`decision-eval` requires `--html`, `--user-goal`, and one of `--field-id` /
`--label`.

## Task Step

A `type: "decision"` task step runs the engine inside `TaskRunner` after the
`content_decision` permission gate. Fields:

| Field | Meaning |
|---|---|
| `user_goal` | Required explicit goal. |
| `html_path` | Local HTML/DOM-like page context. |
| `field_id` / `label` | Target control (one required). |
| `control_type` | Optional explicit control type hint. |
| `value` / `option` / `text` | Optional value to apply. |
| `allow_submit` | Authorizes submit decisions. |
| `min_confidence` | Confidence floor (default `0.50`). |

The task report records the `DecisionTaskContext` and `DecisionRecord` for each
decision step.

## Limitations

- The Decision Engine reads deterministic local HTML/DOM-like hints for
  selftests and reports. Live UIA/OCR fusion is represented in the abstraction
  but remains limited (same boundary as v3.3.5 form semantics).
- `decision-eval` is a dry-run check; it does not replace the per-action focus
  and SafetyPolicy checks performed during `run-task` execution.
- The engine does not generate goals, browse remote URLs, or unlock
  FULL_ACCESS. It chooses one action for one resolved control.
