# DesktopVisual v3.3 Roadmap

Current version: `v3.3.8`.

## Theme

Task Template Library plus v3.3.x Agent Runtime foundations.

## Completed in v3.3.0

- Added `tasks\templates\` as the reusable task template library.
- Added templates: `open_app`, `focus_window`, `fill_form`, `click_button`, `wait_until_text`, `wait_until_window`, `copy_text`, `save_file`, `open_local_html`, and `run_local_test_page`.
- Added TaskRunner support for `type: "template"` task steps.
- Added template parameter substitution for explicit `${parameter}` placeholders in template step JSON.
- Added template report diagnostics: template name, source step, parameters, expanded steps, expanded step count, and PASS/FAIL result.
- Added a bounded `hotkey` task step for templates and explicit tasks, reusing existing target-window safety and foreground focus paths.
- Added `template_selftest.ps1`.

## Completed in v3.3.1

- Added DEFAULT/FULL_ACCESS permission profiles.
- Added temporary FULL_ACCESS sessions with TTL and `task-only`/`session-only` scope.
- Added `permission-status`, `unlock-full-access`, and `lock-full-access`.
- Extended `policy-check`, TaskRunner, and service audit with permission mode decisions.
- Preserved immutable stops for credentials, captcha, anti-automation, anti-cheat, user takeover, and loop guard.

## Completed in v3.3.2

- Made `unlock-full-access` a local interactive CLI permission selector.
- Added `[1] DEFAULT` and `[2] FULL_ACCESS` numeric selection.
- Required the exact phrase `ENABLE FULL_ACCESS` after the FULL_ACCESS risk warning.
- Rejected non-interactive unlock attempts from piped input, automated flags, task files, and service endpoints.
- Added `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION` and `permission_ux_selftest.ps1`.

## Completed in v3.3.3

- Added `launch-app` for FULL_ACCESS-gated normal user desktop/app launch.
- Supported `exe`, `desktop-shortcut`, `start-menu`, `explorer`, and `this-pc` launch kinds.
- Recorded target window title, process, hwnd, pid, and rect after launch.
- Added launch stops for credential, login/user takeover, protected desktop/UAC, anti-cheat, and anti-automation targets.
- Added launch loop guard with `WINDOW_SPAWN_LOOP`.
- Added `global_desktop_selftest.ps1`.

## Completed in v3.3.4

- Added `browser-nav` for FULL_ACCESS-gated external web/browser navigation.
- DEFAULT rejects non-local external URLs; FULL_ACCESS requires a valid temporary session id.
- Recorded URL, action, page title where available, load result, stop reason, recent action, and audit data.
- Added hard stops for login/credential, captcha/challenge, payment/checkout, and anti-automation/bot-detection URLs.
- Added URL loop/no-progress/repeated-action stop codes.
- Added `external_web_selftest.ps1`.

## Completed in v3.3.5

- Added `FormControl` abstraction and `form-control`.
- Added `form_action` task steps.
- Added control types for textbox, textarea, radio, checkbox, dropdown, button, link, date picker, file upload, code editor, captcha/challenge, and unknown.
- Added action mapping so radio/checkbox/dropdown are not treated as textbox inputs.
- Added `FIELD_NOT_UNIQUE`, `FIELD_CONFIDENCE_LOW`, and captcha/challenge stop handling.
- Added `form_semantics_selftest.ps1` and `docs\FORM_SEMANTICS.md`.

## Completed in v3.3.6

- Added the General Decision Task Runtime: `DecisionTaskContext`, `DecisionRecord`, and a deterministic decision pipeline (read_context, classify_task, choose_action, record_decision).
- Added `decision-eval` for dry-run decision checks over local HTML/DOM-like fixtures.
- Added `type: "decision"` task steps gated on the `content_decision` capability (DEFAULT denies, FULL_ACCESS requires a session).
- Enforced that page/chat/web content never overrides `user_goal`, that injection attempts are flagged and ignored, and that low-confidence/captcha/anti-automation/credential/unauthorized-submit conditions stop with their existing stop codes.
- Recorded decision context and record in task reports.
- Added `decision_task_selftest.ps1` and `docs\DECISION_TASK_RUNTIME.md`.
- Reused existing stop codes and the `content_decision` manifest capability; no new error codes or manifest changes were required.

## Completed in v3.3.7

- Added `SessionCheckpoint` report records with checkpoint id, timestamp, permission mode, task id, step index, window/process, URL, observed summary, recent actions, form-state summary, and suggested recovery actions.
- Added manual `type: "checkpoint"` task steps and root `checkpoint` configuration with interval and temporary-file cleanup.
- Added TaskRunner loop guard configuration for repeated actions, repeated URLs, no progress, repeated window-open markers, scroll no-progress, max steps, and max duration.
- Added `SCROLL_NO_PROGRESS` and emit `REPEATED_ACTION_LIMIT`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, `WINDOW_SPAWN_LOOP`, and `LOOP_GUARD_STOP` for long-task guard stops.
- Added `checkpoint_loopguard_selftest.ps1` and `docs\SESSION_CHECKPOINTS.md`.

## Completed in v3.3.8

- Added `communication_step` TaskRunner support and `CommunicationAction` report records.
- Gated communication actions on the existing `communication` capability (DEFAULT denies, FULL_ACCESS requires a session).
- Enforced send boundaries: `send_message` requires `user_requested_send=true` and one explicit target; missing target, missing authorization, and multi-target send stop with `USER_TAKEOVER_REQUIRED`.
- Stopped on login/account-verification, captcha, credential, and anti-automation surfaces with their existing stop codes.
- Recorded content summary and hash only, never full message content.
- Added `communication_runtime_selftest.ps1` and `docs\COMMUNICATION_RUNTIME.md`.

## Pending in v3.3.9

- Add the Coding and Problem-Solving Web Workflow: `CodingWorkflowContext`, `CodingWorkflowRecord`, and a deterministic read_context -> classify_task -> choose_action -> record pipeline for one authorized coding-practice action.
- Add `coding-eval` for dry-run coding-workflow checks over local HTML/DOM-like OJ fixtures (no input, focus, code execution, or live page access).
- Add `type: "coding"` task steps gated on the `content_decision` capability (DEFAULT denies, FULL_ACCESS requires a session).
- Add opt-in live execution for `type: "coding"` steps with `live_execute=true` and explicit editor/run/result/submit selectors, reusing existing visible-window TaskRunner act/locate paths.
- Support actions read_problem, select_language, input_code, run_code, read_result, revise_code, stop_before_submit, and submit_if_explicitly_allowed.
- Recognize the code editor and Run Code control (reusing FormSemantics); read problem/examples/constraints regions and the result state; default-stop before submit and record a submit only when `allow_submit=true`.
- Do not hard-stop solely on exam/online-assessment/proctored/hiring-test/certification/rated-contest keywords in the development runtime because stage 9 explicitly allows those categories under user authorization; public releases must add an explicit permission policy. Reuse login/credential/captcha/anti-automation and locator stop codes; record a code summary/path only, never full code.
- Add `coding_workflow_selftest.ps1` and `docs\CODING_WORKFLOW.md`.
- Reuse existing stop codes and the `content_decision` manifest capability; no new error codes or manifest changes required.

## Pending in v3.3.10

- Add `benchmarks\full_access\` as the repo-owned FULL_ACCESS benchmark structure with expected outcomes, generated task fixture location, and report placeholders.
- Add `full_access_benchmark_matrix.ps1` for reproducible local scenarios covering DEFAULT denial, FULL_ACCESS-gated app launch, local simulated external web navigation, mixed form semantics, decision tasks, checkpoint/loop guard stops, simulated communication, simulated coding workflow, and detection stop cases.
- Add metrics for unlock, permission mode, form classification, decision tasks, loop guard, user takeover, communication simulation, coding workflow, stop conditions, and report completeness.
- Add `full_access_benchmark_selftest.ps1` and `export_full_access_evidence_pack.ps1`.
- Keep interactive FULL_ACCESS unlock as SKIPPED in automated runs because scripts must not type the exact user confirmation phrase.
- Reuse existing commands, task steps, safety stops, and PermissionManager gates; no new `winagent.exe` commands or error codes added.

## Template Schema

Each template must declare:

- `name`
- `description`
- `required_permissions`
- `allowed_window`
- `expected_result`
- `failure_behavior`
- `steps`

Templates cannot set `allow_unrestricted_desktop=true`.

## Safety Boundary

Templates are deterministic step expanders. They do not grant permissions, broaden windows, infer selectors, bypass SafetyPolicy/Safety Manifest, or enable unrestricted desktop control. Expanded steps run through normal TaskRunner WindowSession, foreground, selector, action, expectation, and failure-stop behavior.

## Follow-Up Candidates

- v3.3.2: add interactive local permission UX and typed FULL_ACCESS confirmation.
- v3.3.3: add global desktop and app launcher runtime.
- v3.3.4: add external web and browser navigation runtime.
- v3.3.5: add form and control semantics engine.
- v3.3.x: add optional parameter defaults if real tasks need them.
- v3.3.x: improve template parameter parsing if tasks require nested objects or arrays.
- v3.4.0: build higher-level service/session reporting on top of templates and permission profiles if v3.3.x remains stable.
