# Task Runtime

Current version: `v6.1.4`.

## v6.1.4 Dynamic App/Web Click Accuracy and Offset Diagnostics

v6.1.4 is a v6.1.x real dynamic UI repair stage. It does not enter v6.2 and does not add Persistent Runtime Session, StepContract Compiler, Runtime natural-language execution, VLM Provider/calls, Experience Memory, or Workflow Templates.

The required script-level evidence commands are:

```powershell
D:\desktopvisual\v6_1_4_dynamic_ui_runner.ps1 -Root D:\desktopvisual -SkipBuild
D:\desktopvisual\v6_1_4_dynamic_ui_verifier.ps1 -Root D:\desktopvisual
D:\desktopvisual\v6_1_4_dynamic_ui_acceptance_gate.ps1 -Root D:\desktopvisual
```

The runner must not self-certify PASS. It records raw command output, screenshots, locator traces, focus traces, offset traces, retry/reobserve evidence, and communication target/content checks. The verifier independently decides PASS/FAIL. The acceptance gate rejects missing real dynamic UI evidence.

The runner also records 15 second heartbeat JSONL and enforces 60 second command-step timeouts, 15 minute PyCharm/QQ Mail case timeouts, a 10 minute WeChat case timeout, and a 45 minute global timeout. Timeout, no-progress, environment blocking, and F12 emergency stop must still write partial artifacts and cannot be accepted.

Strict communication targets are fixed: WeChat sends only to `文件传输助手`; QQ Mail uses `https://mail.qq.com` and sends only to `1581782307@qq.com` with subject `测试邮件` and body `这是一个测试邮件`. Login, CAPTCHA, human verification, security verification, account risk verification, or wrong page navigation must STOP/BLOCKED. No extra send-confirmation popup is inserted, but target and content verification are mandatory before send.

## v6.1.3 Mouse Wheel Scroll and Scroll-and-Locate

v6.1.3 is a v6.1.x baseline repair. It makes real mouse wheel input the strict default scroll strategy for new scroll evidence and does not enter v6.2.

`adaptive-scroll` sends real `SendInput` mouse wheel input using `MOUSEEVENTF_WHEEL`, records cursor/window/scroll-region evidence, captures before/after screenshots, computes content signatures, and returns `WHEEL_NO_CONTENT_CHANGE` when verified content does not move. `scroll-and-locate` runs observe/locate, wheel, reobserve, content-change verification, and target locate without automatically clicking the target.

Scrollbar track click, right-rail click, scrollbar thumb drag, PageDown/ArrowDown, JS/DOM/WebDriver/CDP/Playwright/Selenium scroll, and UIA ScrollPattern are not strict mouse wheel PASS evidence. Scrollbar fallback is allowed only after wheel was attempted first, content did not change after reobserve, and `fallback_reason` is recorded; fallback cannot be the core strict PASS for v6.1.3.

Runner/verifier/gate remain separated: `v6_1_3_wheel_scroll_runner.ps1` collects raw evidence only, `v6_1_3_wheel_scroll_verifier.ps1` decides real UI wheel cases, and `v6_1_3_scroll_acceptance_gate.ps1` blocks missing or synthetic evidence. This version does not develop Persistent Runtime Session, PlanDraft to StepContract Compiler, Runtime natural-language execution, VLM Provider, real VLM calls, Experience Memory, Workflow Template behavior, public release permission narrowing, or developer permission direction changes.

## v6.1.2 Real UI Baseline Gate

v6.1.2 is a pre-v6.2 real UI sanity gate for the existing Runtime/HumanMode baseline. It does not add Runtime natural-language execution, does not compile `AgentPlanDraft` to `StepContract`, and does not call a real VLM.

The real UI gate uses a runner/verifier/gate split. `v6_1_2_real_ui_baseline_runner.ps1` collects raw `winagent.exe` HumanMode command output and screenshots only. `v6_1_2_real_ui_baseline_verifier.ps1` independently decides Explorer, Browser Mail Mock, repeatability, and optional localhost results. `v6_1_2_pre_v6_2_acceptance_gate.ps1` checks required regressions, JSON/JSONL parseability, markdown/encoding/protocol consistency, evidence pointers, and final AGENTS.md state.

Explorer Real UI Sanity must open `D:\testrepo\testwindow\desktopvisual_mail_mock.html` through visible Explorer target item rects and mouse double-clicks. Browser Mail Mock Real UI Sanity must type the local `file://` URL through the browser address bar, relocate the window, re-observe, re-locate Recipient/Subject/Body/Send, click/type through HumanMode, click Send, verify `Mock sent successfully`, and verify fields cleared. A repeat browser run is required.

Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, stale coordinates, backend actions, direct file opens, JS/DOM/WebDriver/CDP/Playwright/Selenium actions, and UIA InvokePattern/ValuePattern actions are invalid PASS evidence.

## v6.0.0 Agent Boundary

v6.0.0 adds the validation boundary above Task Runtime. `agent-boundary-validate` checks Runtime/VLM mode selection, Runtime-only executor rules, minimal AgentTaskRequest / AgentPlan / AgentPlanStep shape, and HumanMode action boundaries.

Task Runtime remains the action execution layer. Agent/VLM planning output must compile to StepContract or an equivalent Runtime command path before execution. VLM-assisted mode does not directly click, type, drag, scroll, hotkey, run DOM/JS/WebDriver/CDP, or use UIA InvokePattern/ValuePattern as HumanMode action evidence.

```powershell
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check mode --mode runtime
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check plan --file D:\desktopvisual\artifacts\dev6.0.0_agent_boundary\fixtures\agent_plan_valid.json
```

## v5.10.2 REBUILT Real TaskRuntime Integration and Final Gate

v5.10.2 remains v5. It integrates a real HumanMode browser form flow into TaskRuntime for `tasks\localhost_form_fill_submit_humanmode.task.json` and validates the final Pre-v6 Gate without entering v6, adding VLM providers, developing an Agent Planner, or narrowing public release permissions.

The rebuilt flow is `TaskSession -> StepContract -> TaskRunner -> Adaptive HumanMode Loop -> winagent HumanMode action -> runtime verification`. TaskRuntime writes `task_result.json`, `task_events.jsonl`, `task_report.md`, raw winagent command outputs, action/locator/adaptive traces, HumanActionResult rows, screenshots, overlays, and a verification report. It does not self-certify PASS or set `ready_for_v6`.

`v5_10_2_taskruntime_evidence_verifier.ps1` independently decides `REAL_TASKRUNTIME_HUMANMODE_PASS` or a concrete failure code. The old invalidated v5.10.2 evidence remains invalid and must not be used.

## v5.10.1 REBUILT Real UI Adaptive Cases

v5.10.1 is rebuilt from the trusted v5.10.0 Adaptive HumanMode Control Loop Core baseline. It remains v5 and reruns real UI Case D/E/F evidence without entering v6, adding VLM providers, developing an Agent Planner, narrowing public release permissions, or changing developer capability discovery.

The old v5.10.1 remains invalidated and cannot be used as evidence. Rebuilt v5.10.1 uses a runner/verifier split: `v5_10_1_real_ui_adaptive_cases_runner.ps1` collects raw winagent command evidence only, and `v5_10_1_real_ui_evidence_verifier.ps1` independently decides PASS/FAIL/SKIP. Runner-generated synthetic PASS, placeholder screenshots, hardcoded hwnd/rect, simulated TaskRuntime PASS, backend actions, direct launch, JS/DOM/WebDriver/CDP, and UIA InvokePattern/ValuePattern actions are invalid PASS evidence.

Case D requires real Explorer mouse-target double-clicks through This PC, D:, `testrepo`, `testwindow`, and `desktopvisual_mail_mock.html`. Case E requires two real file:// mock mail form fill/send rounds. Case F requires localhost bound to `127.0.0.1`, address-bar URL input through real HumanMode, form fill/send, status verification, and field-clear verification. v5 still does not promise arbitrary webpage semantic understanding, and v6 has not started.

## v5.10.1/v5.10.2 INVALIDATED

v5.10.1 and v5.10.2 are invalidated. v5.10.1 generated synthetic Adaptive HumanMode case evidence, and v5.10.2 used a hardcoded/simulated browser form path for TaskRuntime handoff evidence.

`ready_for_v6` true is revoked. The old invalidated `tasks\localhost_form_fill_submit_humanmode.task.json` result is not valid PASS evidence. Rebuilt v5.10.2 replaces it with real observe/locate/input/verify TaskRuntime evidence and independent verifier judgment.

v5.10.0 remains the current trusted baseline and proves only the Adaptive HumanMode Control Loop core. Explorer Case D, browser form Case E/F, localhost, and TaskRuntime browser-flow evidence must be rerun with real UI evidence before any handoff claim.

## v5.10.0 Adaptive HumanMode Control Loop Core

v5.10.0 remains v5. It adds a non-VLM Adaptive HumanMode Control Loop inside the Runtime and does not add v6 semantic Agent behavior, VLM providers, an Agent Planner, public release permission narrowing, or a developer permission model rewrite.

HumanMode no longer treats preset coordinate sequences as good evidence. Each click must come from the current observe/locate result, must have a current target rect, must verify `cursor_inside_target_rect_before_click`, must execute through visible paced HumanMode input, and must verify post-action state. On failed verification the Runtime must re-observe, re-locate, retry within budget, or stop with a machine-readable failure reason. It must not guess nearby coordinates or continue stale clicks after foreground/window changes.

The core structures are `AdaptiveTargetSpec`, `AdaptiveTargetCandidate`, `AdaptiveLocateResult`, `AdaptiveActionSpec`, `AdaptiveActionResult`, and `AdaptiveInteractionLoop`. The loop records foreground hwnd/title/process, window/content rects, screenshot path and size, DPI scale where available, locator methods attempted, rejected candidates, screen/window/content-relative coordinates, HumanActionResult, verification result, retry count, and final failure code.

The supported diagnostic commands are:

```powershell
D:\desktopvisual\bin\winagent.exe adaptive-locate --target Send --target-kind browser_button --role button --title "Mail Mock"
D:\desktopvisual\bin\winagent.exe adaptive-click --target Send --target-kind browser_button --role button --title "Mail Mock"
D:\desktopvisual\bin\winagent.exe adaptive-double-click --target testrepo --target-kind explorer_item --role ListItem --title "Explorer"
D:\desktopvisual\bin\winagent.exe adaptive-type --text "hello"
D:\desktopvisual\bin\winagent.exe adaptive-run-step --diagnostic candidate-validation
```

All adaptive commands emit JSON. `adaptive-locate` includes candidates, rejected candidates, selected candidate, locator methods attempted, screenshot path, content rect, and failure reason. `adaptive-click` includes locate/action data, `human_action_result`, verification result, and retry count.

## v5.9.3 Explorer Mouse Target Strictness Fix

v5.9.3 remains v5 and only fixes Explorer Case D mouse-target strictness. It does not add TaskRuntime HumanMode browser-flow integration, VLM providers, Agent Planner behavior, permission-model changes, or public release permission narrowing.

The Case D runner requires `STRICT_MOUSE_TARGET_HUMANMODE_PASS`: each Explorer path step must resolve a target item rect, move the real cursor inside that rect, verify `cursor_inside_target_rect_before_click=true`, perform a real double-click inside the rect, and verify navigation/open. Incremental search may only help locate/select an item; selected item name and selected item rect are required before mouse double-click. Incremental search + Enter, keyboard-assisted/default selection opens, and Explorer address-bar path input are not strict actions. Reading the address/breadcrumb text remains allowed as verification.

## v5.9.2 Active Protection STOP Policy Fix

v5.9.2 remains v5 and only fixes active-protection STOP policy gaps. Task Runtime, CLI, and service policy checks continue to allow developer capability discovery for ordinary Chrome / Explorer / app / browser / local HTML / localhost / ordinary webpage and form exploration.

Ordinary words such as test, exam, assessment, quiz, problem, challenge, mail, submit, hiring, recruitment, coding, and login are not STOP signals by themselves. Concrete active protection signals, including CAPTCHA / human verification, bot challenge, automation or script detection, anti-cheat processes/services, lockdown / secure exam browsers, active proctoring, screen monitoring protection, and protection-bypass requests, stop with `STOP_ACTIVE_PROTECTION` before action execution.

## v5.8 RC Note

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. v5 does not depend on VLM providers and does not claim semantic generalization to unfamiliar screens.

DesktopVisual v5.0 introduces the Task-Level Desktop Execution Runtime foundation. v5.0 is intentionally narrow: it defines TaskSession schema, validates state transitions, runs one local mock task, and writes task-level artifacts. It does not depend on VLM, Agent planners, external web, or real-account automation.

v5.1 StepContract checks sit above this v5.0 foundation as read-only local contract validation, precondition checking, post-action verification, and failure-reason classification. They do not execute actions directly and do not bypass Runtime policy, SafetyPolicy, or confirmation gates.

## Commands

### task-session-validate

```powershell
D:\desktopvisual\bin\winagent.exe task-session-validate --file D:\desktopvisual\tasks\session_schema\valid_standard_session.task-session.json
```

Validates and serializes a v5.0.1 TaskSession schema file. It checks required fields, TaskState enum values, artifact paths, result JSON, STANDARD runtime mode, and escalation reason allowlists. Revalidated v5.0 output includes stable `schema_version`, `runtime_version`, `protocol_version`, and `task_states` fields for auditability.

### task-session-transition

```powershell
D:\desktopvisual\bin\winagent.exe task-session-transition --file D:\desktopvisual\tasks\session_schema\valid_standard_session.task-session.json --action start_task --from-state pending
```

Runs a dry-run state transition. Supported actions are `start_task`, `enter_state`, `transition_to`, `fail_task`, `stop_task`, `complete_task`, and `timeout_task`. Invalid transitions return `TASK_TRANSITION_INVALID`.

### task-session-run

```powershell
D:\desktopvisual\bin\winagent.exe task-session-run --file D:\desktopvisual\tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json
```

Runs the v5.0.3 minimal local mock task `local_form_fill_submit_mock`. It reads a local HTML fixture, validates form and success markers, and writes task artifacts. It does not open a browser, click, type, use OCR/UIA, access the network, or call VLM.

## v5.6 Task-Level Dogfood

The v5.6 dogfood benchmark exercises the Runtime through controlled local task cases:

```powershell
D:\desktopvisual\task_dogfood_benchmark.ps1 -Root D:\desktopvisual
```

The benchmark registry covers local form fill/submit, local problem-page read/run/result fixtures, compile/runtime error mocks, local mail mock attachment flow, Explorer file-select mock, PowerShell run/read/report flow, and a Notepad desktop case that may be SKIPPED with justification when a clean user-safe desktop window is not available.

Dogfood reports include task states, step results, recovery attempts, confirmations, measured latency, artifacts, failure reasons, audit path, workflow scope, fixed-coordinate usage, and external-operation flags. PASS means the local controlled workflow completed on the current machine. SKIPPED is not PASS. Real external mail, upload, exam, hiring-assessment, contest, proctored, payment, credential, captcha, anti-cheat, and public-submission flows remain out of scope.

## TaskState

```json
["pending","running","waiting","verifying","recovering","confirmed","completed","failed","stopped","blocked"]
```

## TaskSession Required Fields

```json
{
  "schema_version": "5.0.1",
  "runtime_version": "5.9.0-a",
  "protocol_version": "5.0",
  "task_id": "example_task",
  "task_type": "local_form_fill_submit_mock",
  "profile": "browser_local",
  "permission_profile": "DEFAULT",
  "capability_profile": ["task_session_schema"],
  "current_state": "pending",
  "started_at": "2026-06-08 00:00:00",
  "updated_at": "2026-06-08 00:00:00",
  "artifacts": {
    "root": "artifacts/dev5.0.4/example",
    "events_jsonl": "artifacts/dev5.0.4/example/task_events.jsonl",
    "result_json": "artifacts/dev5.0.4/example/task_result.json",
    "report_md": "artifacts/dev5.0.4/example/task_report.md"
  },
  "context": {
    "runtime_mode": "STANDARD",
    "task_goal": "Run a local mock task.",
    "allow_unrestricted_desktop": false
  },
  "progress": {
    "total_steps": 0,
    "completed_steps": 0,
    "failed_steps": 0
  },
  "states": ["pending","running","waiting","verifying","recovering","confirmed","completed","failed","stopped","blocked"],
  "result": {
    "task_id": "example_task",
    "state": "pending",
    "status": "not_started",
    "ok": false
  }
}
```

## Artifacts

The v5.0.4 local mock runner writes:

- `task_events.jsonl`
- `task_result.json`
- `task_report.md`
- `current_state.json`
- `failure_dump.json`

`task_events.jsonl`, `task_result.json`, `current_state.json`, and `failure_dump.json` include stable `schema_version`, `runtime_version`, and `protocol_version` fields. Each non-empty JSONL line must parse as JSON.

Screenshots are optional and are not produced by the local-file-only mock runner.

## Safety Boundary

- v5.0 uses `STANDARD` runtime mode by default.
- `allow_unrestricted_desktop=true` is rejected by TaskSession validation.
- The minimal runner is local mock HTML only.
- No VLM or Agent provider is invoked in v5.0.

## v5.9.0-a Task Runtime Permission Profile

TaskRunner and TaskSession may use `DEVELOPER_CAPABILITY_DISCOVERY` as the permission profile. In the internal development tree, absent task permission mode resolves through the configured default permission mode, which is developer capability discovery unless `DESKTOPVISUAL_PERMISSION_MODE` overrides it.

Developer mode allows basic UI actions, browser/Explorer/third-party app/local HTML/localhost/ordinary external navigation, ordinary forms, and mock workflows without a legacy FULL_ACCESS session. Active protection signals stop with `STOP_ACTIVE_PROTECTION` / `BLOCKED_BY_ACTIVE_PROTECTION`; Runtime does not bypass captcha, human verification, anti-cheat, automation detection, or active proctoring.


## v5.9.0-b HumanMode Case Runner

v5.9.0-b adds a script-level HumanMode visible UI Case Runner for v5 boundary evidence. It does not replace TaskSession and does not add v6 Agent planning. The runner uses Runtime commands for real visible desktop input, writes task_events.jsonl, action_trace.jsonl, locator_trace.jsonl, task_result.json, task_report.md, screenshots, and verification reports per case.

Developer mode base UI primitives do not require FULL_ACCESS. Active protection still stops and cannot be routed through recovery, VLM, DOM, browser debugging, or backend launch paths.

## v5.9.0-c Strict HumanMode Case B/D/C Runner

v5.9.0-c keeps the same v5 HumanMode definition and narrows script work to Case B, Case D, and Case C target resolution. It does not add v6 Agent planning, VLM, or public release permission narrowing. PASS evidence requires real visible mouse and keyboard actions with backend/direct launch counts at zero.

## v5.9.0-d Case D Explorer Locator Runner

v5.9.0-d keeps the same v5 HumanMode definition and only fixes Case D Explorer content locator behavior. The runner locks the foreground Explorer hwnd, derives a content rect, scopes UIA/OCR locator evidence to that hwnd and content rect, verifies each navigation level, and allows current-folder incremental search as real keyboard input after content focus. It does not add v6 Agent planning, VLM, permission-model changes, or public release permission narrowing.

## v5.9.0-e HumanMode Motion Pacing

v5.9.0-e remains v5 and only fixes HumanMode mouse pacing plus action result auditability. Runtime mouse actions in HumanMode are visible sequences: move start, multiple move steps, move end, cursor verification, dwell before click, click or double-click, and post-click settle. `desktop-click` and `desktop-double-click` default to this paced behavior.

HumanMode commands return machine-readable `human_action_result.v1` data. Case runners persist pacing fields in `task_result.json`, including `humanmode_pacing_checked`, `min_move_duration_ms`, `min_dwell_before_click_ms`, `min_double_click_interval_ms`, `click_before_move_end_count`, `instant_click_after_move_count`, `human_action_result_count`, `human_action_result_parse_errors`, and `result_contract_version`.

## v5.9.1 Pre-v6 Runtime Handoff

v5.9.1 does not add v6 Agent behavior. It validates whether the current Runtime can be handed to v6: HumanMode evidence must be real and auditable, Task Runtime integration must be explicitly reported, CLI/Service access must remain structured, and active-protection STOP behavior must remain intact. Missing TaskSession/HumanMode integration evidence is a v6 handoff blocker rather than a hidden PASS.


