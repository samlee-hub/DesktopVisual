# DesktopVisual v1.1.0 - Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync

Current trusted version: `DesktopVisual 1.1.0` Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync.

DesktopVisual is a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime for visible-first authorized desktop UI. It is not the official built-in Codex Computer Use feature and not a background script executor.

v1.1.0 aligns public release permissions with normal visible desktop use while preserving active-protection STOP boundaries. `PUBLIC_DEFAULT` allows ordinary visible desktop action, third-party apps, browser/https pages, localhost pages, Explorer/file manager workflows, local file open, cross-window visible workflows, global desktop visible workflows, and validated absolute screen coordinate actions. It does not stop on broad category words such as test, exam, challenge, submit, or assessment by themselves.

v1.1.0 also makes agent output compact by default without reducing evidence: `report_level=compact`, `evidence_level=full`, `progress_output=compact`, `step_chat_detail=compact`, and `artifact_evidence=full`. Failures still expand with error, evidence, and next repair, and full audit artifacts remain the authority.

v1.0.5 remains the accepted full-screen capture/OCR pipeline baseline. The source-of-truth remains a full-screen frame, OCR reads the in-memory frame instead of reading the evidence PNG back from disk, PNG evidence is retained and saved asynchronously, foreground/window OCR crops from the same full-screen frame, fallback OCR uses the same frame, and VLM provider input images are generated from frame-bound bytes.

v1.0.4 remains the trusted Visual Studio C++ complex IDE workflow baseline for visible IDE behavior. The workflow launches Visual Studio only through visible desktop icon double-click, opens `SingleTestProject` through visible VS UI, creates source/header files through visible IDE file-add flows, edits code through the VS editor, builds through VS, runs through VS, verifies visible console output, and closes VS with the visible top-right X after each successful stage.

The v1.0.3+ provider-gated real VLM Runtime Bridge remains the normal VLM path, and legacy mock VLM commands remain quarantined as explicit opt-in test fixtures only. VLM remains assistive only: it does not directly click, type, move the mouse, execute commands, decide backend fallback, bypass safety policy, or run every step.

Developer permissions remain unchanged: `DEVELOPER_CAPABILITY_DISCOVERY` is still the developer default, developer capabilities remain enabled, and `allow_absolute_screen_click=true` remains enabled in the developer tree. Public release policy is now aligned for ordinary visible desktop operations, while real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot/automation challenge, protected desktop/UAC, credential/security handoff, and anti-cheat mechanisms remain STOP boundaries.

**Capability boundary:** visible-first app launch, UIA/OCR/image/template location, provider-gated VLM assist candidates, Runtime candidate validation, focus-verified real keyboard/mouse input primitives, task.json orchestration with bounded recovery, Safety Manifest checks, and Markdown/audit evidence. No active-protection bypass, no protected desktop/UAC control, no VLM direct control, and no autonomous backend fallback decisions.

Current version: `v1.1.0`.

v6.1.4 adds dynamic real UI evidence commands:

```powershell
D:\desktopvisual\v6_1_4_dynamic_ui_runner.ps1 -Root D:\desktopvisual -SkipBuild
D:\desktopvisual\v6_1_4_dynamic_ui_verifier.ps1 -Root D:\desktopvisual
D:\desktopvisual\v6_1_4_dynamic_ui_acceptance_gate.ps1 -Root D:\desktopvisual
```

The runner collects raw evidence only. The verifier independently decides whether PyCharm, WeChat, QQ Mail, and one baseline regression case pass. The acceptance gate rejects missing real dynamic UI evidence, synthetic/placeholder/hardcoded evidence, invalidated evidence, stale target clicks, wrong target clicks, wrong field input, cursor-outside-target clicks, and first-attempt quality below 0.80.

PyCharm must be opened from the desktop shortcut and must type/run the Python loop through the visible PyCharm UI. WeChat may only send `这是一条测试信息` to `文件传输助手`. QQ Mail must use `https://mail.qq.com`, not `v.qq.com`, and may only send to `1581782307@qq.com` with subject `测试邮件` and body `这是一个测试邮件`. Login pages, CAPTCHA, human verification, security verification, account risk verification, or redirection away from QQ Mail stop the run. F12 is the emergency stop key. v6.1.4 does not add an extra send-confirmation popup, but it must verify the target object and content before any send.

The v6.1.4 runner writes heartbeat JSONL every 15 seconds, enforces 60 second command-step timeouts, 15 minute PyCharm/QQ Mail case timeouts, a 10 minute WeChat timeout, and a 45 minute global timeout. Timeout, no-progress, login/security block, or F12 interruption must produce partial artifacts and BLOCKED evidence.

v6.1.3 adds real mouse wheel scroll commands:

```powershell
D:\desktopvisual\bin\winagent.exe adaptive-scroll --title "DesktopVisual Long Scroll Test" --direction down --notches 3 --move-mode human --verify-content-change true
D:\desktopvisual\bin\winagent.exe scroll-and-locate --title "DesktopVisual Long Scroll Test" --target-text "DesktopVisual Target Item 72" --direction down --max-scrolls 20 --notches-per-scroll 3 --move-mode human
D:\desktopvisual\v6_1_3_wheel_scroll_runner.ps1 -Root D:\desktopvisual -SkipBuild
D:\desktopvisual\v6_1_3_wheel_scroll_verifier.ps1 -Root D:\desktopvisual
D:\desktopvisual\v6_1_3_scroll_acceptance_gate.ps1 -Root D:\desktopvisual
```

Strict scroll evidence must be real `SendInput` mouse wheel input using `MOUSEEVENTF_WHEEL`. Scrollbar track clicks, right-rail clicks, scrollbar thumb drags, PageDown/ArrowDown, JS/DOM scroll, WebDriver/CDP/Playwright/Selenium scroll, and UIA ScrollPattern are not strict mouse wheel PASS evidence. If wheel input does not change content after reobserve, the Runtime records `WHEEL_NO_CONTENT_CHANGE`; it does not claim scroll success. Any scrollbar fallback must be diagnostic-only unless wheel was attempted first, content did not change, and `fallback_reason` is recorded.

v6.1.2 adds real UI gate commands:

```powershell
D:\desktopvisual\v6_1_2_real_ui_baseline_runner.ps1 -Root D:\desktopvisual -SkipBuild -Rounds 2
D:\desktopvisual\v6_1_2_real_ui_baseline_verifier.ps1 -Root D:\desktopvisual
D:\desktopvisual\v6_1_2_pre_v6_2_acceptance_gate.ps1 -Root D:\desktopvisual
```

The runner collects raw winagent HumanMode command output, stdout/stderr, exit codes, cursor positions, foreground/window rects, screenshots, overlays, and preliminary UNVERIFIED observations. The verifier independently decides Explorer and browser real UI PASS/FAIL/SKIP from that raw evidence. The pre-v6.2 gate checks required logs, JSON/JSONL parseability, evidence pointers, regressions, synthetic/placeholder/hardcoded evidence scans, and AGENTS.md state before any trusted-version advancement.

v6.1.x planner/intention commands:

```powershell
D:\desktopvisual\bin\winagent.exe agent-intent-parse --mode runtime --goal "open D:\testrepo\testwindow"
D:\desktopvisual\bin\winagent.exe agent-intent-parse --mode runtime --goal "delete D:\testrepo\testwindow\da.txt"
D:\desktopvisual\bin\winagent.exe agent-plan-draft --mode runtime --goal "open D:\testrepo\testwindow"
D:\desktopvisual\bin\winagent.exe agent-plan-draft --mode vlm_assisted --goal "open a normal webpage and read the title"
D:\desktopvisual\bin\winagent.exe agent-planner-validate --check intent --file D:\desktopvisual\artifacts\dev6.1.0_task_intent_planner\fixtures\task_intent_valid.json
D:\desktopvisual\bin\winagent.exe agent-planner-validate --check plan-draft --file D:\desktopvisual\artifacts\dev6.1.0_task_intent_planner\fixtures\agent_plan_draft_valid.json
```

`TaskIntent` includes `task_id`, `raw_user_goal`, `normalized_goal`, `intent_type`, `mode`, target fields, user constraints, risk level, confirmation requirement, assumptions, and unsupported reason. `AgentPlanDraft` includes `plan_id`, `task_id`, `mode`, `intent_type`, `draft_steps`, required Runtime capabilities, assumptions, risk, confirmation requirement, `compile_required=true`, `executor=runtime`, provider role, and `is_executable=false`.

`AgentPlanDraft` is not a `StepContract` and is not directly executable. Runtime remains the only executor. VLM-assisted mode remains assistive only through `provider_role=assistive_only`. Plan-to-StepContract compilation is reserved for v6.2.0.

v6.0.0 added `agent-boundary-validate`:

```powershell
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check mode --mode runtime
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check mode --mode vlm_assisted
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check executor --executor runtime
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check action --humanmode-action true --action-type runtime_step_contract
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check request --file D:\desktopvisual\artifacts\dev6.0.0_agent_boundary\fixtures\agent_task_request_valid.json
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check plan --file D:\desktopvisual\artifacts\dev6.0.0_agent_boundary\fixtures\agent_plan_valid.json
```

Valid modes are `runtime` and `vlm_assisted`. Unknown, empty, or missing mode values fail. `executor=runtime` is the only valid executor; `vlm` and `agent_direct` fail. VLM-assisted mode may help planning and interpretation, but real click/type/drag/scroll/hotkey execution must go through Runtime StepContract or an equivalent Runtime command path. JS, DOM, WebDriver, CDP, UIA InvokePattern, and UIA ValuePattern are not HumanMode Runtime actions.

v6.1.4 still does not enter v6.2, execute v6 natural-language tasks, compile StepContract, call a real VLM API, add Provider API key UI or accounts, add Experience Memory, add Workflow Template behavior, modify developer permission direction, weaken HumanMode, or weaken active-protection STOP.

The old v5.10.1 and old v5.10.2 are INVALIDATED. Old v5.10.1 generated synthetic Adaptive HumanMode case evidence, including placeholder screenshots and synthetic trace rows. Old v5.10.2 generated TaskRuntime handoff evidence through hardcoded/simulated browser form geometry. These artifacts must not be used as PASS evidence or v6 handoff evidence, and `ready_for_v6` true is revoked.

Rebuilt v5.10.2 connects `tasks\localhost_form_fill_submit_humanmode.task.json` through `TaskSession -> StepContract -> TaskRunner -> Adaptive HumanMode Loop -> winagent HumanMode action -> runtime verification`. The TaskRuntime execution writes raw command output, action/locator/adaptive traces, screenshots, and verification artifacts, but it does not self-certify PASS. `v5_10_2_taskruntime_evidence_verifier.ps1` independently decides `REAL_TASKRUNTIME_HUMANMODE_PASS`.

v5.10.0 proved Adaptive HumanMode Control Loop core readiness: observe, locate, validate candidate, move, verify cursor, click/type, verify state, and bounded re-observe/retry/stop. v5.10.1 rebuilt applies that core to real Explorer Case D, file:// browser form Case E, and localhost browser form Case F. v5.10.2 rebuilt integrates real TaskRuntime HumanMode browser flow and final gate validation. v6.0.0 builds only the boundary architecture on top of that accepted handoff.

v5.9.0-b defines HumanMode as real visible mouse and keyboard operation: cursor movement, click/double-click through mouse input events, and text/hotkeys through keyboard input events. UIA/OCR/ElementGraph may observe and locate; UIA InvokePattern, ValuePattern, DOM mutation, JavaScript, Selenium/Playwright/WebDriver/CDP, direct ShellExecute launch, backend typing, and no-open mocks are not HumanMode actions.

v5.9.0-b adds `desktop-move`, `desktop-click`, `desktop-double-click`, `desktop-press`, `desktop-hotkey`, and `desktop-type` for developer-mode visible desktop primitives. It validates Chrome/Edge launch, address-bar navigation, Explorer local HTML open, and local mock mail form fill/send with artifacts under `artifacts\dev5.9.0-b_humanmode_case_runner\`. The local mail mock sends no real email, external webpage Case B tests ordinary navigation only, and active protection still stops.

v5.9.0-a opens developer Runtime exploration for low-level desktop UI primitives, browser navigation, Explorer, third-party apps, local HTML, localhost, ordinary external navigation, ordinary form filling, and mock workflows. Developer mode does not stop merely because content contains words such as test, exam, assessment, quiz, problem, challenge, submit, mail, hiring, recruitment, or coding. It stops when active protection appears: captcha, human verification, script/automation detection, active anti-cheat, active proctoring/lockdown clients, protected desktop/UAC, or other third-party protection mechanisms.

DesktopVisual provides a narrow, authorized loop for finding a target window, capturing it, sending real input, reading state files, running cases/tasks, writing audit logs, and producing Markdown reports.

**v5.9.0-a developer reset note:** v5.x is an internal engineering stage number. v5.9.0-a is not a public release permission normalization pass. v6 has not started. Before public release, DesktopVisual will require a later Release Normalization Pass that maps internal v5.x stages to public prerelease/stable versions and narrows public defaults.

The v0.1.x foundation execution layer is frozen in v0.1.6. The v0.2.x Skill layer is stable in v0.2.3 on top of the frozen CLI protocol, case format, JSON schema, error codes, audit log format, and case report format.

v1.4.0 builds on the v1.3.0 observe baseline with a unified Selector locate/act system. It keeps v1.3.0 commands compatible and adds `coord`, `uia`, `image`, and `text` selectors for read-only location and controlled actions.

The current capabilities are: scoped window discovery, screenshots, focus-verified real mouse/keyboard input primitives, Adaptive HumanMode observe/locate/validate/action/verify/retry diagnostics, Case v1/v2 execution, allowlisted state-file reads, audit logs, Markdown reports, UI Automation tree/find/action support, Windows OCR when available with `OCR_UNAVAILABLE` fallback, BMP template matching, read-only `observe2` hybrid perception reports, provider registry reporting, image-template visual source candidates, read-only `observe-loop` event streams with Screen Delta and Perception Cache accounting, Dynamic UI Recovery routing, App Profile loading and profile locator metadata, v4 visual dogfood evidence for local developer workflows, v4 latency benchmark evidence, v4 release-candidate evidence aggregation, a project-local Skill template, service protocol v1.0, task.json orchestration, DEVELOPER_CAPABILITY_DISCOVERY, PUBLIC_DEFAULT, CI_MOCK, and legacy FULL_ACCESS permission profiles, developer-mode normal desktop/app launch, developer-mode ordinary external web/browser navigation, form/control semantics, General Decision Task Runtime, session checkpoints, loop guard stops, Communication Action Runtime, Coding and Problem-Solving Web Workflow, Full Access benchmark/evidence harness, and local safety policy checks.

## Quick Start

```powershell
D:\desktopvisual\build.ps1
D:\desktopvisual\selftest.ps1
D:\desktopvisual\uia_selftest.ps1
D:\desktopvisual\run_uia_demo.ps1
D:\desktopvisual\run_ocr_demo.ps1
D:\desktopvisual\run_image_demo.ps1
D:\desktopvisual\run_real_dev_workflow.ps1
D:\desktopvisual\safety_selftest.ps1
D:\desktopvisual\focus_selftest.ps1
D:\desktopvisual\read_path_selftest.ps1
D:\desktopvisual\input_primitives_selftest.ps1
D:\desktopvisual\motion_selftest.ps1
D:\desktopvisual\motion_profile_selftest.ps1
D:\desktopvisual\observe_selftest.ps1
D:\desktopvisual\observe2_provider_selftest.ps1
D:\desktopvisual\observe_loop_selftest.ps1
D:\desktopvisual\dynamic_ui_recovery_selftest.ps1
D:\desktopvisual\app_profile_selftest.ps1
D:\desktopvisual\v4_visual_dogfood.ps1
D:\desktopvisual\v4_rc_check.ps1
D:\desktopvisual\v6_0_0_agent_boundary_selftest.ps1
D:\desktopvisual\v6_1_0_task_intent_planner_selftest.ps1
D:\desktopvisual\selector_selftest.ps1
D:\desktopvisual\window_session_selftest.ps1
D:\desktopvisual\template_selftest.ps1
D:\desktopvisual\permission_profile_selftest.ps1
D:\desktopvisual\adapter_selftest.ps1
D:\desktopvisual\benchmark_matrix.ps1
D:\desktopvisual\benchmark_selftest.ps1
D:\desktopvisual\latency_benchmark.ps1
D:\desktopvisual\full_access_benchmark_matrix.ps1
D:\desktopvisual\full_access_benchmark_selftest.ps1
D:\desktopvisual\dogfood_selftest.ps1
D:\desktopvisual\run_demo.ps1
D:\desktopvisual\run_demo.ps1 -Visible
D:\desktopvisual\run_dogfood.ps1
```

## App Profiles

v4.5.0 adds App Profiles under `D:\desktopvisual\profiles`. Profiles describe local app/window matching, common locators, OCR ROIs, visual strategy, recovery strategy, task templates, and confirmation nodes. They are application adapters only; they do not grant permissions or loosen the Safety Manifest.

```powershell
D:\desktopvisual\bin\winagent.exe profile-report
D:\desktopvisual\bin\winagent.exe locate --title "Agent Test Window" --profile testwindow --profile-locator click_button
```

Profile candidates returned by `locate` include `action_gate="requires_runtime_safety_policy"`. Real account profiles, real email sending, public assessment automation, and high-permission public defaults are not part of v4.5.0.

## v4 Visual Dogfood

v4.6.0 adds a bounded visual dogfood suite for local developer workflow fixtures:

```powershell
D:\desktopvisual\v4_visual_dogfood.ps1
```

The suite covers local HTML forms, a local mock problem page, a local mock mail page, an Explorer temp-file flow, Notepad when a clean user-safe target is available, and local PowerShell output reading. Each case records `observe2`, `ElementGraph`, `LocatorCandidate`, `SceneState`, `ChangeEvent`, `observe-loop` delta/ROI metadata, and App Profile evidence where applicable. It is evidence for local v4 perception workflows only; it does not access real accounts, send real email, automate real exams/assessments, or prove arbitrary software control.

## v4 Hybrid Perception Release Candidate

v4.7.0 closes v4.x as a Hybrid Screen Perception Runtime. It provides the engineering foundation for `ScreenFrame`, `ElementGraph`, `LocatorCandidate`, `SceneState`, `ChangeEvent`, `observe2`, Screen Delta, ROI OCR, Perception Cache, provider-ready visual sources, Dynamic UI Recovery, App Profiles, latency evidence, and local visual dogfood evidence.

v4.x is not a complete autonomous Agent, does not fully understand arbitrary screens, and does not include real VLM, OmniParser, YOLO, UGround, model weights, GPU requirements, or real-account benchmarks. v5.0 adds the first task-level execution foundation. v6 is the planned Initial Desktop Agent System boundary and provider architecture phase; v6 has not started in this tree.

## v5 Task Runtime Foundation

v5.8.7 revalidates and hardens the internal v5.x Task Execution Release Candidate track on top of v5.0 Task Session, v5.1 Step Contract, v5.2 recovery, v5.3 Human Confirmation, v5.4 Task Template v2, v5.5 File / Attachment / Cross-window workflows, v5.6 task-level dogfood, and v5.7 service task API. Runtime remains the only action executor. v5 does not depend on VLM, does not route blocked actions through Agent/VLM bypass, and does not claim arbitrary-screen semantic understanding. The implemented v5.0 through v5.8 commands and scripts include:

```powershell
D:\desktopvisual\bin\winagent.exe task-session-validate --file D:\desktopvisual\tasks\session_schema\valid_standard_session.task-session.json
D:\desktopvisual\bin\winagent.exe task-session-transition --file D:\desktopvisual\tasks\session_schema\valid_standard_session.task-session.json --action start_task --from-state pending
D:\desktopvisual\bin\winagent.exe task-session-run --file D:\desktopvisual\tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json
D:\desktopvisual\bin\winagent.exe step-contract-validate --file D:\desktopvisual\tasks\step_contract\valid_local_form_submit.step.json
D:\desktopvisual\bin\winagent.exe step-precondition-check --contract D:\desktopvisual\tasks\step_contract\valid_local_form_submit.step.json --perception D:\desktopvisual\tasks\step_contract\perception_pass.json
D:\desktopvisual\bin\winagent.exe step-verify --contract D:\desktopvisual\tasks\step_contract\valid_local_form_submit.step.json --before D:\desktopvisual\tasks\step_contract\verification_before_submit.json --after D:\desktopvisual\tasks\step_contract\verification_after_success.json --timeout-ms 1000 --elapsed-ms 50
D:\desktopvisual\bin\winagent.exe step-failure-classify --error-code VERIFICATION_TIMEOUT --step-id click_submit_and_verify
D:\desktopvisual\bin\winagent.exe recovery-policy-validate --file D:\desktopvisual\tasks\recovery_policy\valid_standard_recovery_policy.json
D:\desktopvisual\bin\winagent.exe recovery-evaluate --policy D:\desktopvisual\tasks\recovery_policy\valid_standard_recovery_policy.json --failure-reason TARGET_NOT_READY --context D:\desktopvisual\tasks\recovery_policy\delayed_button_not_ready.json --attempt 1
D:\desktopvisual\bin\winagent.exe escalation-request-create --reason semantic_unresolved --task local_form_fill_submit_mock --step click_submit_and_verify --context D:\desktopvisual\tasks\recovery_policy\escalation_semantic_unresolved.json
D:\desktopvisual\bin\winagent.exe safe-stop-check --reason captcha --context D:\desktopvisual\tasks\recovery_policy\blocked_scene_captcha.json
D:\desktopvisual\bin\winagent.exe risk-action-classify --action "send email" --permission-profile DEFAULT
D:\desktopvisual\bin\winagent.exe confirmation-request-create --action "send email" --risk-level high --summary "Review mock email before send." --target-window "Local Mail Mock" --screenshot artifacts/dev5.3.2/screenshots/pre_send_review.bmp --files artifacts/dev5.3.2/mock_attachment.txt --destination qa@example.invalid --timeout-ms 30000 --allowed-responses confirm,reject
D:\desktopvisual\bin\winagent.exe confirmation-gate-check --action "send email" --response confirm --timeout-ms 30000 --elapsed-ms 0
D:\desktopvisual\bin\winagent.exe confirmation-flow-run --file D:\desktopvisual\tasks\confirmation\local_mail_mock_send_confirm.json --response confirm
D:\desktopvisual\bin\winagent.exe task-template-v2-validate --file D:\desktopvisual\tasks\templates_v2\local_form_fill_submit.task-template-v2.json
D:\desktopvisual\bin\winagent.exe task-template-v2-resolve --task D:\desktopvisual\samples\tasks\local_form_fill_submit_v2.task.json
D:\desktopvisual\bin\winagent.exe file-path-resolve --path D:\desktopvisual\artifacts\dev5.5.1\allowed\mock_attachment.txt --allowed-roots D:\desktopvisual\artifacts\dev5.5.1\allowed --extensions .txt,.md --max-bytes 4096
D:\desktopvisual\bin\winagent.exe file-picker-flow --file D:\desktopvisual\tasks\file_workflows\local_mock_file_picker_success.json
D:\desktopvisual\bin\winagent.exe attachment-verify --file D:\desktopvisual\tasks\file_workflows\local_mail_mock_upload_success.json --expected-file mock_attachment.txt
D:\desktopvisual\bin\winagent.exe cross-window-check --file D:\desktopvisual\tasks\file_workflows\cross_window_success.json
D:\desktopvisual\bin\winagent.exe local-mail-attach-flow --file D:\desktopvisual\samples\tasks\local_mail_mock_attach_v55.task.json
D:\desktopvisual\task_dogfood_benchmark.ps1 -Root D:\desktopvisual
D:\desktopvisual\bin\winagent.exe run-task --file D:\desktopvisual\tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json
D:\desktopvisual\bin\winagent.exe task-status --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-events --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-report --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-confirm --task-id dev5_0_4_local_form_fill_submit_mock_audit --response confirm
D:\desktopvisual\bin\winagent.exe task-cancel --file D:\desktopvisual\tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json --reason "user cancel"
```

v5.0 supports TaskSession schema validation, dry-run state transitions, a minimal local mock runner, and task-level artifacts. Under v5.8.7 revalidation, v5.0 TaskSession validation and artifacts expose stable `schema_version`, `runtime_version`, and `protocol_version` fields, and event/result artifacts are parseable JSON/JSONL. v5.1 supports StepContract schema validation, contract-field-driven precondition checks, post-action verification over local perception JSON, and structured failure-reason classification. v5.2 supports RecoveryPolicy validation, low-risk retry decisions, structured EscalationRequest generation, and terminal SafeStop checks. v5.3 supports risk action classification, ConfirmationRequest artifacts, confirmation gate decisions, and a local mock mail confirmation flow. v5.4 supports TaskTemplateV2 validation, profile-bound locator/ROI/strategy resolution, task parameter validation, and built-in safe local templates. v5.5 supports default-deny metadata-only file path resolution with explicit allowed roots, mock file picker flow validation, attachment upload state verification, cross-window return checks, and a local mail mock attach flow with no real send or real upload. v5.6 adds `task_dogfood_benchmark.ps1`, a task-level dogfood benchmark that produces summary JSON, Markdown reports, and per-case evidence for controlled local workflows. v5.7 stabilizes external TaskSession execution through CLI and service protocol: `run-task`, `task-status`, `task-events`, `task-report`, `task-confirm`, `task-cancel`, `/run_task`, `/get_task_status`, `/get_task_events`, `/read_task_report`, `/confirm_task_action`, and `/cancel_task`. v5.8 consolidates feature matrix, evidence, safety, latency, docs, and RC acceptance. It does not depend on VLM/Agent providers, does not automate real web pages, does not promise unfamiliar-screen semantic generalization, and does not bypass SafetyPolicy. See `docs\TASK_RUNTIME.md`, `docs\STEP_CONTRACT.md`, `docs\TASK_RECOVERY.md`, `docs\HUMAN_CONFIRMATION.md`, `docs\TASK_TEMPLATES_V2.md`, `docs\FILE_WORKFLOWS.md`, and `docs\SERVICE_PROTOCOL.md`.

Run the focused v4 RC evidence check:

```powershell
D:\desktopvisual\v4_rc_check.ps1
```

The report is written to:

```text
D:\desktopvisual\artifacts\dev4.7.0\v4_release_candidate_report.md
```

Default RC validation does not create a release package:

```powershell
D:\desktopvisual\rc_check.ps1
```

Create a release package only when explicitly requested:

```powershell
D:\desktopvisual\rc_check.ps1 -IncludeRelease
D:\desktopvisual\release.ps1
D:\desktopvisual\verify_release.ps1
D:\desktopvisual\export_evidence_pack.ps1
```

## Build

```powershell
D:\desktopvisual\build.ps1
```

The script builds:

- `D:\desktopvisual\bin\winagent.exe`
- `D:\testrepo\testwindow\bin\TestWindow.exe`

If `cl.exe` is not already available, the script tries to locate Visual Studio C++ tools through `vswhere.exe` and `VsDevCmd.bat`.

## Portable Mode

DesktopVisual v3.0.5 can run from any clone or portable copy. Root resolution uses this order:

1. `-Root <path>` passed to supported PowerShell scripts.
2. `DESKTOPVISUAL_ROOT`.
3. Upward discovery from the script or executable location by finding `VERSION` and `src`.
4. Legacy fallback `D:\desktopvisual` with a warning.

Portable examples:

```powershell
$env:DESKTOPVISUAL_ROOT = 'D:\desktopvisual_portable_test'
D:\desktopvisual_portable_test\build.ps1 -Root $env:DESKTOPVISUAL_ROOT
D:\desktopvisual_portable_test\selftest.ps1 -Root $env:DESKTOPVISUAL_ROOT
D:\desktopvisual_portable_test\bin\winagent.exe version
```

`winagent.exe version` includes `data.project_root`. Runtime artifacts are written under `<project_root>\artifacts`. The safety config supports `${PROJECT_ROOT}` in read and write roots.

## Selftest

```powershell
D:\desktopvisual\selftest.ps1
```

Selftest verifies version output, command JSON schema, success cases, expected failure cases, stable error codes, audit log output, and case report format.

Safety selftest verifies the v1.0.2 developer policy boundaries:

```powershell
D:\desktopvisual\safety_selftest.ps1
```

The local safety config is:

```text
D:\desktopvisual\config\safety.conf
```

It controls `allowed_titles`, `allowed_processes`, `allowed_read_roots`, `allowed_write_roots`, `max_steps`, `max_duration_ms`, `emergency_stop_key`, and `allow_absolute_screen_click`. The default emergency stop key is `F12`. File reads are limited to `D:\desktopvisual` and `D:\testrepo\testwindow`, and paths containing `..` traversal are denied.

## Safety Manifest

DesktopVisual v3.0.5 adds a machine-readable Safety Manifest at:

```text
D:\desktopvisual\config\safety_manifest.json
```

The manifest records the authorized local-window runtime mode, denied sensitive categories, consent rules, runtime limits, permission modes, and audit settings. DEFAULT keeps the existing authorized-window boundary. FULL_ACCESS allows third-party apps, external web, communication, content decisions, cross-window work, and global desktop intent only when a temporary FULL_ACCESS session is active. FULL_ACCESS cannot override immutable safety stops for credentials, captcha, anti-automation, anti-cheat, protected desktop, or user takeover.

Use these commands to inspect and dry-run the boundary:

```powershell
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe permission-status
D:\desktopvisual\bin\winagent.exe unlock-full-access --ttl 900 --scope session-only
D:\desktopvisual\bin\winagent.exe lock-full-access
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe policy-check --title "External Browser" --process msedge.exe --action external_web --permission-mode FULL_ACCESS --full-access-session-id <id>
D:\desktopvisual\bin\winagent.exe launch-app --kind exe --path "D:\testrepo\testwindow\bin\TestWindow.exe" --target-title "Agent Test Window" --process TestWindow.exe --permission-mode FULL_ACCESS --full-access-session-id <id>
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
D:\desktopvisual\safety_manifest_selftest.ps1
D:\desktopvisual\permission_profile_selftest.ps1
D:\desktopvisual\permission_ux_selftest.ps1
```

`safety-report` writes `artifacts\safety\safety_report.md` and `safety_report.json`. `unlock-full-access` is interactive when run from a local console: choose `[1] DEFAULT` or `[2] FULL_ACCESS`; choosing FULL_ACCESS prints a risk warning and requires typing `ENABLE FULL_ACCESS` exactly. Piped input, task files, automated confirmation flags, and service endpoints cannot unlock FULL_ACCESS. `launch-app` requires FULL_ACCESS and records the launched visible target window. `policy-check` and `consent-check` do not perform input. `run-task` writes Safety Manifest, Permission Decision, and policy-check summaries into task reports and stops immediately on sensitive categories, expired/missing FULL_ACCESS sessions, or `allow_unrestricted_desktop`.

Real-app dogfood is opt-in during selftest so routine tests do not open Notepad:

```powershell
D:\desktopvisual\selftest.ps1 -IncludeDogfood
```

If the dogfood environment is unavailable, selftest records `SKIPPED` without failing.

## Demos

Fast basic demo:

```powershell
D:\desktopvisual\run_demo.ps1
```

Visible action demo:

```powershell
D:\desktopvisual\run_demo.ps1 -Visible
```

The visible demo runs `D:\desktopvisual\cases\visible_action.case`, using human mouse movement and per-character typing.

## Input Primitives

DesktopVisual v1.1.0 adds controlled primitives for agent workflows:

```powershell
D:\desktopvisual\bin\winagent.exe focus --title "Agent Test Window"
D:\desktopvisual\bin\winagent.exe active-window
D:\desktopvisual\bin\winagent.exe mouse-position
D:\desktopvisual\bin\winagent.exe double-click --title "Agent Test Window" --x 80 --y 90
D:\desktopvisual\bin\winagent.exe right-click --title "Agent Test Window" --x 90 --y 150
D:\desktopvisual\bin\winagent.exe scroll --title "Agent Test Window" --x 90 --y 150 --delta -120
D:\desktopvisual\bin\winagent.exe drag --title "Agent Test Window" --from-x 120 --from-y 160 --to-x 180 --to-y 160
D:\desktopvisual\bin\winagent.exe hotkey --title "Agent Test Window" --keys CTRL+A
D:\desktopvisual\bin\winagent.exe clipboard-set --text "hello"
D:\desktopvisual\bin\winagent.exe clipboard-paste --title "Agent Test Window" --text "hello"
```

All target-window input commands require `--title`, must match exactly one visible top-level window, must pass `config\safety.conf`, and must verify foreground focus before sending input. `clipboard-set` only sets clipboard text and returns `text_length`, not the text content.

## Mouse Motion Profiles

Mouse commands support `--move-mode instant|fast-human|demo-human|human|operator-human`. The default is `human`, which uses the local `operator-human` calibrated profile from `config\operator_motion_profile.json`. Automated tests that do not need calibrated movement should request `instant` explicitly.

- `instant`: direct cursor placement for automated tests that explicitly request it.
- `operator-human` / `human`: local calibrated movement from `config\operator_motion_profile.json`; fails explicitly if no valid `source=human` profile exists.
- `fast-human`: legacy bounded curved movement, available only when explicitly requested.
- `demo-human`: legacy slower curved movement for demos and recordings, available only when explicitly requested.

If duration is omitted, v1.2.0 auto-calculates it from distance. Explicit durations are capped at 1500 ms for `fast-human` and 3000 ms for `demo-human`. Mouse action JSON includes `move_profile`, `path_type`, `distance_px`, `duration_ms`, `step_count`, and `emergency_stop_checked`.

## Operator Motion Profile

DesktopVisual v3.0.5 keeps the v3.0.1 Operator Motion Profile feature and fixes its collection boundary. Synthetic selftest profiles prove only that the pipeline works; they are not personal operator behavior. Only a profile generated by `motion_calibration_session.ps1` with `source=human` represents the local operator.

```powershell
D:\desktopvisual\motion_calibration_session.ps1
D:\desktopvisual\bin\winagent.exe motion-record --title "Motion Lab" --scenario horizontal_lr --duration-ms 3000 --out "D:\desktopvisual\artifacts\motion_profile\human\raw\raw_horizontal_lr_001.json"
D:\desktopvisual\bin\winagent.exe motion-calibrate --source human --input "D:\desktopvisual\artifacts\motion_profile\human\raw" --out "D:\desktopvisual\config\operator_motion_profile.json"
D:\desktopvisual\bin\winagent.exe motion-profile-info --profile "D:\desktopvisual\config\operator_motion_profile.json"
D:\desktopvisual\bin\winagent.exe motion-profile-validate --profile "D:\desktopvisual\config\operator_motion_profile.json" --out "D:\desktopvisual\artifacts\motion_profile\validation_report.md"
```

`operator-human` is supported by click, double-click, right-click, scroll, drag, click-image, click-text, act, and task.json act steps. `human` is the default mouse mode and resolves to `operator-human`. By default it reads `config\operator_motion_profile.json` and requires `source=human`. If the profile is missing, invalid, or not human, commands fail explicitly with `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, or `MOTION_PROFILE_NOT_HUMAN`; DesktopVisual does not silently fall back. The only explicit fallback is `--fallback fast-human` on CLI actions or `"fallback": "fast-human"` in task.json act steps.

Tests may use synthetic or sample profiles only with an explicit test profile path and `--allow-synthetic-profile`, for example `--profile D:\desktopvisual\artifacts\motion_profile\synthetic\operator_motion_profile.synthetic.json --allow-synthetic-profile`. The profile is local personalization only. It is not a detection-bypass or anti-cheat feature. Raw trajectory files are generated under `D:\desktopvisual\artifacts\motion_profile\human\raw` for human calibration and under `D:\desktopvisual\artifacts\motion_profile\synthetic\raw` for selftests; the calibrated profile stores aggregate timing, direction, curvature, jitter, and endpoint correction statistics rather than complete raw traces.

## ObserveDesktopVisual v1.3.0 adds a read-only observation command:

```powershell
D:\desktopvisual\bin\winagent.exe observe --title "Agent Test Window" --screenshot true --uia true --max-elements 80
```

`observe` requires `--title` and the title must resolve to exactly one visible top-level window. It does not click, type, focus, or modify window contents. It returns target-window metadata, a v3.2.0 `window_session` record, active-window metadata, current focus status, mouse position, an optional screenshot under `D:\desktopvisual\artifacts\observe_<timestamp>.bmp`, an optional UI Automation element list, safety policy summary, and warnings.

`window_session` records `requested_title`, optional requested process, resolved title, hwnd, pid, process name, window rect, visible/iconic state, foreground status, foreground controllability, DPI, monitor device name, monitor bounds, and monitor work-area bounds. Duplicate windows return `WINDOW_NOT_UNIQUE` with candidate diagnostics instead of choosing the first match.

Agent workflows should use:

```text
observe -> locate -> act -> observe -> verify
```

Case files can run `observe` and optionally write the observation data:

```text
observe D:\desktopvisual\artifacts\observe_case_data.json
```

## Selector Locate And Act

DesktopVisual v1.4.0 adds unified selectors. DesktopVisual v3.1.0 extends them with UIA AutomationId, ClassName, relative locators, near-text locators, explicit `nth`, and fallback chains:

```text
coord:x=80,y=90
uia:name=Click Me
uia:name_contains=Click,type=Button
uia:type=Edit,index=0
uia:automation_id=1001
uia:class_name=Button,name=Click Me,type=Button
relative:relation=below,anchor=uia:name=Click Me,target_role=Edit,nth=0
near_text:text=Click Me,target_role=Edit,position=below,nth=0
chain:uia:automation_id=missing||uia:name=Click Me
image:path=D:\desktopvisual\assets\click_button.bmp,tolerance=10
text:contains=Click Me
```

Use `locate` to resolve a selector without input:

```powershell
D:\desktopvisual\bin\winagent.exe locate --title "Agent Test Window" --selector "uia:name=Click Me"
```

Use `act` to locate and then perform a controlled action:

```powershell
D:\desktopvisual\bin\winagent.exe act --title "Agent Test Window" --selector "uia:name=Click Me" --action click
D:\desktopvisual\bin\winagent.exe act --title "Agent Test Window" --selector "uia:type=Edit,index=0" --action type --text hello
```

New workflows should prefer `observe`, then `locate`/`act`. Existing `uia-click`, `uia-type`, `click-image`, and `click-text` remain compatibility interfaces.

When multiple selector candidates match, new selector forms require explicit `nth` rather than choosing the first candidate. Fallback chains record every attempted selector and failure reason in command output and task reports.

## Case v2

DesktopVisual v1.5.0 introduces a declarative Case v2 format with key=value syntax, variables, wait_until, expect, and post-action verification.

Enable v2 by adding `case_version=2` as the first line:

```text
case_version=2
target_title="Agent Test Window"
set name="btn" value="uia:name=Click Me"
act selector="${btn}" action="click" expect_file_contains_path="D:\testrepo\testwindow\runtime\state.txt" expect_file_contains_text="clicks="
expect selector_exists="uia:name=Click Me"
```

Key features:
- **key=value syntax**: all commands use `key="value"` parameters
- **Quoted strings**: support spaces, `\"`, `\\`, `\n` escapes
- **Variables**: `set name="x" value="y"` and `${x}` substitution
- **wait_until**: polling wait for selector, file_contains, window_title_contains
- **expect**: assertions for selector_exists, file_contains, active_window_title_contains
- **Post-action verification**: `act` supports `expect_selector_exists` and `expect_file_contains_*`
- **Backward compatible**: v1 .case files run unchanged

Selftest:
```powershell
D:\desktopvisual\case_v2_selftest.ps1
```

## UI Automation Tree

```powershell
D:\desktopvisual\uia_selftest.ps1
```

The UIA selftest builds the project, starts `Agent Test Window`, runs `uia-tree`, verifies the `Click Me` button appears in the element list, then runs `uia-find --name "Click Me"` and verifies the returned rectangle.

Manual examples:

```powershell
D:\desktopvisual\bin\winagent.exe uia-tree --title "Agent Test Window"
D:\desktopvisual\bin\winagent.exe uia-find --title "Agent Test Window" --name "Click Me"
D:\desktopvisual\bin\winagent.exe uia-click --title "Agent Test Window" --name "Click Me"
D:\desktopvisual\bin\winagent.exe uia-type --title "Agent Test Window" --name "Input" --text "hello"
```

These commands use Windows native UI Automation COM APIs. `uia-tree` and `uia-find` only read element metadata. `uia-click` tries `InvokePattern` first and falls back to real mouse center click. `uia-type` tries `ValuePattern` first and falls back to center click plus the existing keyboard input path.

UIA action demo:

```powershell
D:\desktopvisual\run_uia_demo.ps1
```

The demo runs `D:\desktopvisual\cases\uia_action.case` and writes `D:\desktopvisual\artifacts\uia_action_report.md`.

## OCR Text Location

```powershell
D:\desktopvisual\run_ocr_demo.ps1
```

The OCR demo starts `Agent Test Window` and runs:

```powershell
D:\desktopvisual\bin\winagent.exe find-text --title "Agent Test Window" --text "Click Me"
D:\desktopvisual\bin\winagent.exe click-text --title "Agent Test Window" --text "Click Me" --move-mode human --move-duration-ms 800
```

Current v2.0+ behavior: DesktopVisual uses Windows built-in WinRT OCR when available. If the Windows OCR runtime or language support is unavailable, OCR commands return `OCR_UNAVAILABLE` or `OCR_LANGUAGE_UNAVAILABLE`; tests and demos may record `SKIPPED` rather than pretending OCR succeeded. No third-party OCR dependency is used.

UI Automation should be preferred over OCR. OCR is only a supplemental locator for authorized test windows, self-drawn UI, or windows that do not expose accessible controls. OCR must not be used for security-control bypass, credential extraction, or unauthorized workflow automation.

## Image Template Location

```powershell
D:\desktopvisual\run_image_demo.ps1
```

The image demo starts `Agent Test Window`, captures a window screenshot, crops a small button template into:

```text
D:\desktopvisual\assets\click_button.bmp
```

Then it runs:

```powershell
D:\desktopvisual\bin\winagent.exe find-image --title "Agent Test Window" --template "D:\desktopvisual\assets\click_button.bmp" --tolerance 10
D:\desktopvisual\bin\winagent.exe click-image --title "Agent Test Window" --template "D:\desktopvisual\assets\click_button.bmp" --move-mode human --move-duration-ms 800 --tolerance 10
```

Template matching supports uncompressed 24-bit and 32-bit BMP. It is not suitable for dynamic complex scenes. DPI, scaling, theme, font, antialiasing, and rendering changes can cause failure. Prefer UI Automation first, OCR second, and image templates only as a supplemental locator.

## Developer Tool Dogfood

```powershell
D:\desktopvisual\dogfood_matrix.ps1
```

The v3.6.0 dogfood matrix runs controlled tests against bounded normal-user desktop and local developer-tool scenarios:

- Notepad
- Calculator
- Explorer
- Local HTML fixture through `form-control`
- PowerShell local read-only/test output through `read-file`
- VS Code when installed

It writes:

- `D:\desktopvisual\artifacts\dogfood\dogfood_report.md`
- `D:\desktopvisual\artifacts\dogfood\dogfood_summary.json`
- `D:\desktopvisual\artifacts\dogfood_matrix_report.md`
- per-app JSON reports under `D:\desktopvisual\artifacts\dogfood\<app>\`
- screenshots under `D:\desktopvisual\artifacts\dogfood\<app>\`

Each task report records its safety boundary, expected result, and SKIPPED condition. All file operations stay under `D:\desktopvisual\artifacts\dogfood`. Local HTML dogfood uses a generated fixture and does not access external websites, browser profiles, logins, payments, passwords, captcha, social apps, games, anti-cheat, UAC, or administrator windows. If a target app already has a user window open, that app dogfood reports `SKIPPED` instead of closing or typing into the user session. A dogfood PASS is bounded evidence for the listed scripted scenario only; it does not prove arbitrary software control.

## Agent Adapters

DesktopVisual v3.0.3 makes the calling layer agent-agnostic. DesktopVisual is not a Codex-only script bundle; it can be called by Codex, Claude Code, generic CLI agents, and human scripts.

Recommended adapter paths:

```text
D:\desktopvisual\adapters\codex\win-desktop-agent
D:\desktopvisual\adapters\claude-code
D:\desktopvisual\adapters\generic-cli
D:\desktopvisual\adapters\shared
```

The legacy Codex Skill path is still available for compatibility:

```text
D:\desktopvisual\skill_template\win-desktop-agent
```

All adapters use the same safety rules: `observe-locate-act-verify`, prefer `run-task` for complex work, read reports after failures, stop on `error_code`, no unrestricted desktop control, and no sensitive flows.

Adapter selftest:

```powershell
D:\desktopvisual\adapter_selftest.ps1
```

More detail:

```text
D:\desktopvisual\docs\AGENT_ADAPTERS.md
```

## Benchmark Evidence

DesktopVisual v3.0.5 adds a benchmark evidence pack so capability claims can be tied to repeatable reports.

Run:

```powershell
D:\desktopvisual\benchmark_matrix.ps1
D:\desktopvisual\benchmark_selftest.ps1
D:\desktopvisual\export_evidence_pack.ps1
```

Outputs:

```text
D:\desktopvisual\artifacts\benchmark\benchmark_report.md
D:\desktopvisual\artifacts\benchmark\benchmark_summary.json
D:\desktopvisual\artifacts\evidence\DesktopVisual-v3.0.4-evidence-pack.zip
```

Benchmarks distinguish PASS, FAIL, and SKIPPED. SKIPPED is not PASS; it records missing or unsafe prerequisites. Benchmark results do not prove arbitrary Windows software control.

## Latency Benchmark Pack

DesktopVisual v4.3.0 adds a low-latency evidence pack for the v4 hybrid perception runtime. It measures the current machine only and does not claim cross-machine latency guarantees.

Run:

```powershell
D:\desktopvisual\latency_benchmark.ps1
```

Outputs:

```text
D:\desktopvisual\artifacts\dev4.3.0\latency\benchmark_config.json
D:\desktopvisual\artifacts\dev4.3.0\latency\latency_results.json
D:\desktopvisual\artifacts\dev4.3.0\latency\latency_summary.md
D:\desktopvisual\artifacts\dev4.3.0\latency\raw_logs\
```

The benchmark records screenshot, UIA, full OCR, ROI OCR, screen delta, ElementGraph-producing `observe2`, hybrid locate, image-template provider, observe-loop event, action-to-verify, cache hit ratio, and `llm_or_vlm_call_count`. Runtime-first local perception is measured before any model provider; the default VLM/LLM call count must remain `0`.

## Full Access and Decision Task Evidence

DesktopVisual v3.3.10 adds a reproducible Full Access benchmark harness for the v3.3.x runtime track. It focuses on evidence chains for permission gates, safe desktop/app launch, local web simulation, form semantics, decision tasks, loop guards, simulated communication, and simulated coding workflows.

Run:

```powershell
D:\desktopvisual\full_access_benchmark_matrix.ps1
D:\desktopvisual\full_access_benchmark_selftest.ps1
D:\desktopvisual\export_full_access_evidence_pack.ps1
```

Outputs:

```text
D:\desktopvisual\artifacts\benchmark\full_access\full_access_benchmark_report.md
D:\desktopvisual\artifacts\benchmark\full_access\full_access_benchmark_summary.json
D:\desktopvisual\artifacts\evidence\DesktopVisual-v3.3.10-full-access-evidence-pack.zip
```

The harness uses local simulations and safe targets. It does not include real account data, real chat/email content, browser profiles, raw motion data, `bin`, `obj`, or sensitive logs. Non-interactive FULL_ACCESS unlock remains `SKIPPED` by design because only a local human console can confirm FULL_ACCESS.

## Service Mode

DesktopVisual v2.3.0 adds explicit local service mode:

```powershell
D:\desktopvisual\bin\winagent.exe serve --host 127.0.0.1 --port 17873 --max-session-ms 3600000
```

DesktopVisual v3.5.0 stabilizes service protocol v1.0 over the local named pipe. v5.7 adds task endpoints for external Agents. Supported endpoints include `/version`, `/health`, `/health-check`, `/capabilities`, `/safety-report`, `/policy-check`, `/consent-check`, `/observe`, `/locate`, `/act`, `/run_task`, `/get_task_status`, `/get_task_events`, `/confirm_task_action`, `/cancel_task`, `/read_task_report`, `/run-task`, `/read-report`, `/report`, and `/shutdown`. Every response uses the unified service envelope: `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version`. Service mode is never started automatically, does not bypass PermissionManager or SafetyPolicy, can use an already unlocked FULL_ACCESS session, cannot unlock FULL_ACCESS by itself, cannot provide interactive confirmation, and writes `D:\desktopvisual\artifacts\service_audit.log` with `permission_mode` and `service_protocol_version`.

## Task Runner

DesktopVisual v3.0.0 adds closed-loop task execution:

```powershell
D:\desktopvisual\bin\winagent.exe run-task --file D:\desktopvisual\tasks\testwindow_basic.task.json --report D:\desktopvisual\artifacts\mvp_testwindow_report.md
```

Task execution performs template expansion, initial PermissionManager gate, initial WindowSession resolution, observe, locate, foreground confirmation, act/hotkey, observe-after, expect verification, failure classification, the Recovery Strategy Engine, and a Markdown report. A task may include `permission_mode` and `full_access_session_id`; FULL_ACCESS is denied without a valid temporary session. Recovery is limited to configured, audited strategies such as re-observe, OCR fallback, target-window re-resolution, or wait and re-observe. It never guesses nearby coordinates, chooses an ambiguous selector, or broadens window scope.

## Recovery Strategy Engine

DesktopVisual v3.4.0 adds configured, auditable recovery for selected task failures:

- `LOCATOR_NOT_FOUND`: re-observe -> OCR fallback -> stop.
- `WINDOW_NOT_FOUND`: find process/window -> activate -> stop.
- `LOCATOR_NOT_UNIQUE`: stop and require explicit selector or `nth`.
- `TEXT_NOT_FOUND`: wait -> re-observe -> stop.
- `SAFETY_POLICY_DENIED`: stop immediately; no recovery attempt is allowed.

Recovery is bounded by the effective `max_recoveries` after Safety Manifest clamping. Reports include `## Recovery Strategy Engine` with each error, strategy, attempt number, result, and details. Service `/run-task` uses the same TaskRunner path, so service reports include the same recovery records.

## Coding Workflow

DesktopVisual v3.3.9 adds a local simulated coding-practice workflow:

```powershell
D:\desktopvisual\bin\winagent.exe coding-eval --html D:\desktopvisual\artifacts\coding_workflow\oj_sample_pass.html --user-goal "practice two sum" --action run_code --language cpp
D:\desktopvisual\coding_workflow_selftest.ps1
```

`coding-eval` and `type: "coding"` task steps record `CodingWorkflowContext` and `CodingWorkflowRecord`: problem summaries, language, editor/run-button detection, result state, code summary or code path, revision count, and submit basis. DEFAULT denies task execution through the `content_decision` capability; FULL_ACCESS requires a valid temporary session id. Submit is not performed unless `allow_submit=true`.

The workflow stops on login/password, captcha, anti-automation/AI-detection, and missing code-editor/run controls. It does not batch submit, scrape problem sets, bypass paid limits, or bypass proctoring, anti-cheat, captcha, credential, or anti-automation controls.

The v3.3.9/v3.3.10 development runtime does not hard-stop solely on exam, assessment, hiring-test, certification, or rated-contest keywords because those categories were explicitly allowed by the stage 9 requirements under a user-authorized task. Public releases must add explicit permission restrictions for these categories before exposing them outside controlled local development.

## Local Development And Release Permission Policy

`D:\desktopvisual` is the local development and future evaluation tree. It intentionally keeps the broadest project permission surface available for controlled local optimization, simulated-exam accuracy measurement, operation-accuracy measurement, and future development tests, while still preserving immutable stops for credentials, captcha, payment, UAC, protected desktop, anti-cheat, and anti-automation bypass.

Do not publish or submit `D:\desktopvisual` as the public release project. Public release work must be prepared in a separate directory:

```text
D:\desktopvisual-release
```

The release project under `D:\desktopvisual-release` must contain the restricted permission policy. In that release tree, exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows must be disabled or gated by a dedicated permission model before distribution. The release tree must not include local artifacts, raw motion data, browser profiles, sensitive logs, or the development tree's unrestricted local-testing posture.

## Task Templates

DesktopVisual v3.3.0 adds reusable task templates under:

```powershell
D:\desktopvisual\tasks\templates
```

Bundled templates: `open_app`, `focus_window`, `fill_form`, `click_button`, `wait_until_text`, `wait_until_window`, `copy_text`, `save_file`, `open_local_html`, and `run_local_test_page`.

Agents should prefer templates over ad hoc coordinate-heavy task steps when a template matches the workflow. A template task step names the template and supplies parameters:

```json
{
  "name": "click via template",
  "type": "template",
  "template": "click_button",
  "parameters": {
    "selector": "uia:name=Click Me,type=Button",
    "expect_selector": "uia:name=Click Me"
  }
}
```

Each template declares `required_permissions`, `allowed_window`, `expected_result`, and `failure_behavior`. Template expansion produces ordinary TaskRunner steps, so SafetyPolicy, Safety Manifest, unique-window checks, foreground checks, selector ambiguity checks, and failure-stop behavior still apply. Task reports include a `## Templates` section with template name, parameters, expanded steps, and PASS/FAIL result.

## Real Dev Workflow

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1
```

Without approved project paths, the script writes a SKIPPED report and does not access real projects:

```text
D:\desktopvisual\artifacts\real_dev_workflow_report.md
```

Configure a workflow by copying:

```text
D:\desktopvisual\cases\real_dev_workflow.template.case
```

and reading:

```text
D:\desktopvisual\docs\REAL_DEV_WORKFLOW.md
```

Any Client, Server, UE, game, or real project state path must be approved before it is read.

## Codex Skill Template

The recommended Codex adapter path is:

```text
D:\desktopvisual\adapters\codex\win-desktop-agent
```

The legacy Skill template path remains compatible:

```text
D:\desktopvisual\skill_template\win-desktop-agent
```

The adapter and legacy template contain `SKILL.md`, scripts for observe/locate/act, Case v2, service-aware workflows, dogfood, `run-task`, task-report summaries, and local reference copies of the command protocol, error codes, safety notes, limitations, and case format.

Manual installation is intentionally user-controlled: copy `D:\desktopvisual\skill_template\win-desktop-agent` into your Codex skills directory only after reviewing it. The project does not auto-install the Skill and does not write into global `.agents`, Codex, or user-home skill directories.

Installation details:

```text
D:\desktopvisual\docs\SKILL_INSTALLATION.md
```

Skill execution loop smoke test:

```powershell
D:\desktopvisual\skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1
D:\desktopvisual\skill_template\win-desktop-agent\scripts\run-skill-basic.ps1
D:\desktopvisual\skill_template\win-desktop-agent\scripts\run-failure-demo.ps1
```

Use the Skill by asking Codex to run an authorized DesktopVisual task or case, read the report, and summarize the result. The Skill should prefer `run-task`, stop on `error_code`, and avoid free-form clicking.

## Reports

Reports are written to:

```text
D:\desktopvisual\artifacts
```

Common reports:

- `basic_click_report.md`
- `visible_action_report.md`
- `selftest_report.md`
- `failure_window_not_found_report.md`
- `failure_assert_report.md`
- `failure_invalid_click_report.md`

## WinAgent CLI Commands

- `winagent.exe version`
- `winagent.exe windows`
- `winagent.exe find --title "Agent Test Window"`
- `winagent.exe screenshot --title "Agent Test Window" --out "D:\desktopvisual\artifacts\before.bmp"`
- `winagent.exe observe --title "Agent Test Window" [--screenshot true|false] [--uia true|false] [--max-elements 80]`
- `winagent.exe observe2 --title "Agent Test Window" [--screenshot] [--include-uia] [--max-elements 50] [--image-template <bmp>] [--tolerance 0..255]`
- `winagent.exe observe-loop --title "Agent Test Window" [--interval-ms 250] [--max-duration-ms 5000] [--max-events 20] [--roi x,y,w,h] [--changed-regions-only] [--out <events.jsonl>]`
- `winagent.exe dynamic-ui-recovery --html <local.html> [--previous-html <local.html>] [--candidate-id <id>] [--semantic-status resolved|unresolved] [--risk-status normal|blocked_sensitive]`
- `winagent.exe locate --title "Agent Test Window" --selector "uia:name=Click Me"`
- `winagent.exe act --title "Agent Test Window" --selector "uia:type=Edit,index=0" --action type --text hello`
- `winagent.exe click --title "Agent Test Window" --x 80 --y 90 [--move-mode human|instant|fast-human|demo-human|operator-human] [--move-duration-ms 800] [--fallback fast-human]`
- `winagent.exe double-click --title "Agent Test Window" --x 80 --y 90 [--move-mode human|instant|fast-human|demo-human|operator-human] [--fallback fast-human]`
- `winagent.exe right-click --title "Agent Test Window" --x 90 --y 150 [--move-mode human|instant|fast-human|demo-human|operator-human] [--fallback fast-human]`
- `winagent.exe scroll --title "Agent Test Window" --x 90 --y 150 --delta -120 [--move-mode human|instant|fast-human|demo-human|operator-human] [--fallback fast-human]`
- `winagent.exe drag --title "Agent Test Window" --from-x 120 --from-y 160 --to-x 180 --to-y 160 [--move-mode human|instant|fast-human|demo-human|operator-human] [--duration-ms 300] [--fallback fast-human]`
- `winagent.exe press --title "Agent Test Window" --key SPACE`
- `winagent.exe hotkey --title "Agent Test Window" --keys CTRL+S`
- `winagent.exe clipboard-set --text "hello"`
- `winagent.exe clipboard-paste --title "Agent Test Window" [--text "hello"]`
- `winagent.exe focus --title "Agent Test Window"`
- `winagent.exe active-window`
- `winagent.exe mouse-position`
- `winagent.exe type --title "Agent Test Window" --text "hello" [--type-mode human|instant|fast-human|demo-human] [--char-delay-ms 80]`
- `winagent.exe read-file --path "D:\testrepo\testwindow\runtime\state.txt"`
- `winagent.exe uia-tree --title "Agent Test Window"`
- `winagent.exe uia-find --title "Agent Test Window" --name "Click Me"`
- `winagent.exe uia-click --title "Agent Test Window" --name "Click Me"`
- `winagent.exe uia-type --title "Agent Test Window" --name "Input" --text "hello"`
- `winagent.exe find-text --title "Agent Test Window" --text "Click Me"`
- `winagent.exe click-text --title "Agent Test Window" --text "Click Me" --move-mode fast-human`
- `winagent.exe find-image --title "Agent Test Window" --template "D:\desktopvisual\assets\click_button.bmp" --tolerance 10`
- `winagent.exe click-image --title "Agent Test Window" --template "D:\desktopvisual\assets\click_button.bmp" --move-mode fast-human --tolerance 10`
- `winagent.exe run-case --file "D:\desktopvisual\cases\basic_click.case" --report "D:\desktopvisual\artifacts\basic_click_report.md"`

`version`, `find`, `screenshot`, `observe`, `observe2`, `observe-loop`, `dynamic-ui-recovery`, `adaptive-locate`, `adaptive-click`, `adaptive-double-click`, `adaptive-type`, `adaptive-run-step`, `agent-boundary-validate`, `locate`, `act`, `click`, `double-click`, `right-click`, `scroll`, `drag`, `press`, `hotkey`, `type`, `clipboard-set`, `clipboard-paste`, `focus`, `active-window`, `mouse-position`, `read-file`, `uia-tree`, `uia-find`, `uia-click`, `uia-type`, `find-text`, `click-text`, `find-image`, `click-image`, `task-session-validate`, `task-session-transition`, `task-session-run`, `task-template-v2-validate`, `task-template-v2-resolve`, `file-path-resolve`, `file-picker-flow`, `attachment-verify`, `cross-window-check`, `local-mail-attach-flow`, `step-contract-validate`, `step-precondition-check`, `step-verify`, `step-failure-classify`, `recovery-policy-validate`, `recovery-evaluate`, `escalation-request-create`, `safe-stop-check`, `risk-action-classify`, `confirmation-request-create`, `confirmation-gate-check`, `confirmation-flow-run`, `run-case`, and `run-task` use the unified JSON envelope documented in `COMMAND_PROTOCOL.md`. `serve` starts an explicit local named-pipe service wrapper; `windows` uses the frozen window listing envelope documented there.

## observe2 Visual Sources

v4.1.0 added `observe2` as a read-only hybrid perception report. It returns `screen_frame`, `providers`, `perception_sources`, `element_graph`, `locator_candidates`, `scene_state`, and `change_events`.

```powershell
D:\desktopvisual\bin\winagent.exe observe2 --title "Agent Test Window" --screenshot --include-uia --max-elements 50
D:\desktopvisual\bin\winagent.exe observe2 --title "Agent Test Window" --screenshot --image-template D:\desktopvisual\artifacts\dev4.1.0\observe2_template.bmp
```

The provider registry reports `uia`, `ocr`, `screen_delta`, `image_template`, `local_visual_provider`, `cloud_vlm`, and `agent_provider`. The image-template provider reuses local BMP template matching. OmniParser, YOLO, UGround, cloud VLM, and agent-provider integrations remain placeholders and report unavailable or degraded when not configured.

Visual providers only produce candidates. A visual-only candidate with `semantic_status="unresolved"` is not executable by `act`; visual selectors such as `visual:id=image_template:0` stop with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`.

## observe-loop Event Streams

v4.2.0 adds a read-only realtime observe loop for low-latency change detection. It writes JSONL events and a Markdown report while using screenshot hashes, changed-region metadata, ROI OCR, UIA refreshes only on changed rounds, and cached unchanged rounds.

```powershell
D:\desktopvisual\bin\winagent.exe observe-loop --title "Agent Test Window" --interval-ms 150 --max-duration-ms 5000 --max-events 8 --roi 0,0,400,300 --changed-regions-only --out D:\desktopvisual\artifacts\dev4.2.0\events.jsonl
D:\desktopvisual\bin\winagent.exe observe2 --loop --title "Agent Test Window" --interval-ms 150 --max-duration-ms 5000 --max-events 8
```

`observe-loop` is observation only. It does not plan tasks, click controls, run VLM monitoring, or escalate every frame to an external model. Safety-manifest denied targets emit `safety_blocked` and stop.

## Dynamic UI Recovery

v4.4.0 adds read-only Dynamic UI Recovery routing for dynamic screens. `observe2` now reports `scene_state.status`, `change_events`, `dynamic_recovery`, `routers`, and `action_decision`.

```powershell
D:\desktopvisual\bin\winagent.exe dynamic-ui-recovery --html D:\desktopvisual\artifacts\dev4.4.0\fixtures\ready.html --candidate-id submit --semantic-status resolved --risk-status normal
```

Scene states are `normal`, `loading`, `dialog_open`, `error`, `success`, `blocked`, and `unknown`. Router decisions are `AUTO_EXECUTE`, `ESCALATE_TO_VLM`, `REQUIRE_HUMAN_CONFIRMATION`, and `STOP`.

Runtime can safely wait and re-observe loading states, invalidate stale candidates, rebuild affected perception, and re-locate moved elements. Dialogs require a safe route or user confirmation. Errors stop or escalate by risk. Blocked states stop immediately and are not routed to VLM bypass. Unknown state is never treated as permission to click.

## Safety Boundary

This tool is only for user-authorized development test windows. It must not be used for security-control bypass, unauthorized automation, or controlling software without authorization.

`click` is real desktop input, not a window-message shortcut. Coordinates are target-window client coordinates, not full-screen absolute coordinates.

Visual locator safety and failure-stop rules are frozen in:

```text
D:\desktopvisual\docs\VISUAL_SAFETY_FREEZE.md
```

UIA, OCR, and image/template locators must stop on zero matches, multiple matches, unavailable locator engines, or any non-empty `error_code`. They must not guess nearby clicks or switch locator methods without user confirmation.

This is not official Codex built-in Computer Use. The platform has limited UIA-located actions, Windows OCR when the OS supports it, minimal BMP template matching, a local named-pipe service wrapper, `run-task` orchestration, and a bounded Recovery Strategy Engine. It does not have MCP, automatic Codex Skill installation, unrestricted desktop control, or autonomous decision-making.

## RC Check

`rc_check.ps1` defaults to non-release RC validation and skips release packaging. It prints `Release packaging skipped. Use -IncludeRelease only when user explicitly requests a release package.` when `package_source.ps1`, `release.ps1`, and `verify_release.ps1` are not run.

Use release packaging only after the user explicitly requests a release package:

```powershell
D:\desktopvisual\rc_check.ps1 -IncludeRelease
```

For public release, do not submit `D:\desktopvisual` directly. Create and review `D:\desktopvisual-release`, apply the restricted release permission policy there, and release only from that separate tree.

## Release Baseline

v3.7.0 is the public release candidate for the v3.x line. It builds on the v1.4 selector/observe/input baseline plus advanced selectors, WindowSession diagnostics, task templates, DEFAULT/FULL_ACCESS permission profiles, interactive temporary FULL_ACCESS sessions, FULL_ACCESS-gated app launch, FULL_ACCESS-gated external web/browser navigation, form/control semantics, General Decision Task Runtime, session checkpoints, loop guard stops, Communication Action Runtime, Coding and Problem-Solving Web Workflow, Full Access benchmark/evidence harness, Recovery Strategy Engine, service protocol v1.0, developer-tool dogfood evidence, Case v2, Windows OCR, service mode, task orchestration, Operator Motion Profile, portable root resolution, agent-agnostic adapters, benchmark evidence reporting, and strict-JSON Safety Manifest consent checks. Future work should preserve the v1.x command compatibility boundary and keep OCR/profile/window-session/template/permission/web-navigation/form-field/decision/checkpoint/communication/coding/benchmark/recovery/service/dogfood failures explicit instead of guessing coordinates, treating unknown fields as textboxes, ignoring loops, sending without user authorization, submitting without `allow_submit=true` or required release permission, treating dogfood PASS as arbitrary software proof, or letting page content override the user goal.




























