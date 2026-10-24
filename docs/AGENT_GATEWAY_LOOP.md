# Agent Gateway Loop (run-task Orchestration Contract)

Current version: v1.0.0 (measured on build_time Oct 24 2026 20:11:04)

This document defines how an agent drives DesktopVisual: DesktopVisual exposes
atomic actions, `run-task` performs deterministic orchestration, and the model
is consulted only after a step fails. It is a protocol, not a script - the step
list is authored per task.

## 1. Responsibility split

| Layer | Owner | Contract |
| --- | --- | --- |
| Atomic actions | DesktopVisual commands | click / type / uia-* / observe / screenshot, each audited |
| Orchestration | `run-task --file <task.json> --report <report.md>` | steps, expects, bounded recovery, checkpoints |
| Judgment on failure | Agent (model) | reads the failure digest + screenshot, emits the corrected remaining steps |

The agent must not pre-plan fallbacks for states it has not observed, and must
not silently take over a step that run-task can execute itself.

## 2. One round

1. Write `task.json` (version 1, target, budget, steps).
2. Run exactly one command:
   `bin/winagent.exe run-task --file <task.json> --report <report.md> --permission-mode <mode>`
3. Read the JSON report emitted next to the markdown report (`report_json` in
   the command's stdout data block, same name as `--report` with `.json`).
4. `ok:true` -> done. `ok:false` -> build the failure digest (section 3).
5. `ok:true` with `deferred_expects > 0` means every action executed but the
   assertions were not evaluated (section 2.1). Judge them from the screenshot
   before reporting success.

One run-task call is one model round trip regardless of step count.

## 2.1 Verify mode

`verify_mode` is a top-level `task.json` field: `engine` (default) or `agent`.

- `engine` - the engine evaluates every `expect` block. Right for structured
  surfaces: UIA-readable text, file assertions, window titles.
- `agent` - the engine executes the steps and returns every declared condition
  unevaluated:

  ```json
  "expect": {"deferred": true, "verify_mode": "agent", "conditions": {"text_contains": "..."}},
  "expect_deferred": true
  ```

  plus a top-level `deferred_expects: N`. The step is PASS and the run can be
  `ok:true`; the caller grounds the conditions on the artifact instead.

Use `agent` for self-drawn surfaces where the assertion source is blind. Measured
on WeChat 4.x (UIA exposes 4 nodes: Window -> Window -> Pane Weixin -> Pane
MMUIRenderSubWindowHW), same four-step task:

- `engine` -> `ok:false`, `EXPECT_FAILED`, 3/4 steps, 1859 ms - the message had
  actually been sent; `text_contains` read a window-only snapshot that cannot see
  the bubble.
- `agent` -> `ok:true`, 3/3 steps, `deferred_expects:1`, 2969 ms.

`verify_mode: agent` changes nothing the engine executes. It only stops the engine
from making a judgment it cannot ground.

Regression measured on the same build: the calculator task under the default mode
still returns `verify_mode "engine"`, `deferred_expects 0` and the evaluated
`{"selector_exists":{"ok":true,...}}`.

## 3. Failure digest

Project only what judgment needs; the full report is not a prompt payload.

```
node -e "const j=JSON.parse(require('fs').readFileSync(P,'utf8'));
console.log(JSON.stringify({final_error:j.final_error,
 steps:j.steps.filter(s=>!s.ok).map(s=>({i:s.index,n:s.name,code:s.failure.code,
 msg:s.failure.message,recommended:s.failure.recommended,sel:s.locate&&s.locate.selector,
 shot:s.screenshot}))}))"
```

Measured digest size for a single failing step: 918 bytes.

Fields that carry the diagnosis:
- `steps[].failure.code` - machine class of the failure
- `steps[].failure.message` - human text, contains the concrete contradiction
- `steps[].locate` - the selector that was tried and whether it resolved
- `steps[].screenshot` - artifact path, the only thing worth looking at
- `steps[].expect` - what was asserted and the observed text

## 4. Decide: retry or stop

| Failure code | Class | Action |
| --- | --- | --- |
| TARGET_NOT_READY, TEXT_NOT_FOUND, LOCATOR_NOT_FOUND, STALE_CANDIDATE | automatic | run-task already retried once; only intervene if it still fails |
| EXPECT_FAILED, LOCATOR_NOT_UNIQUE, MULTIPLE_CANDIDATES_LOW_CONFIDENCE, UNKNOWN_SCENE, SEMANTIC_UNRESOLVED | semantic | read the screenshot, then emit corrected steps. EXPECT_FAILED cannot occur under `verify_mode: agent`; if it does, the task file is missing the field |
| SAFETY_DENIED, CAPTCHA_DETECTED, ANTI_AUTOMATION_DETECTED, ANTI_CHEAT_DETECTED, CREDENTIAL_INPUT_DETECTED | terminal | stop at once, report to the user; never route to a model as a bypass |

## 5. Retry rules

- Emit a new task file containing only the failed step and the steps after it;
  never replay steps that already passed.
- The failed step is re-stated with the corrected selector/action, not deleted.
- One correction per round. If the same step fails twice with the same code,
  escalate to the user instead of guessing again.
- Windows, processes and typed text survive between rounds; assume the state is
  where the previous round left it.

## 6. Contract traps measured on this build

- `coord:x=..,y=..` selectors are CLIENT-relative to the target window. Screen
  pixels passed in produce `LOCATOR_NOT_FOUND: coord selector point is outside
  the target client area.` The `desktop-*` commands, by contrast, take screen
  coordinates, and on a 150% display they take LOGICAL screen coordinates while
  the global screenshot is PHYSICAL.
- `expect.text_contains` resolves through window text/OCR. On UWP/XAML apps the
  window capture can be stale or partial, so the assertion fails while the UI is
  already correct. Prefer `expect.selector_exists` with a UIA locator, e.g.
  `uia:name_contains=显示为 42`.
- `observe` step screenshots are window-only (`PrintWindow`). When a decision
  needs the real pixels, capture a global frame and crop it by the window rect
  scaled by the display DPI ratio.
- `run-task` on a TaskSession file is not the same engine: the minimal runner
  only accepts `local_form_fill_submit_mock` and returns
  `UNSUPPORTED_TASK_TYPE` for anything else. Use version 1 task files.

## 7. Measured baseline

- Calculator 7x6=42, five steps, UIA locators, one run-task call: ok, 2781 ms,
  5/5 steps, 0 recoveries, one model round trip.
- Same task with screen-pixel coords: LOCATOR_NOT_FOUND at step 2 in 188 ms.
- Interactive WeChat task driven one command per model turn: 34 round trips,
  174 s wall clock, 2.95M input tokens, 4.33 s of actual UI execution.
