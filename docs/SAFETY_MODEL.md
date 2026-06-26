# DesktopVisual Safety Model

Current version: `v4.7.0`.

DesktopVisual is a local Windows desktop runtime with explicit permission profiles. DEFAULT remains the safe authorized-window runtime. FULL_ACCESS can widen the allowed task surface to normal user desktop, third-party apps, external web, communication, content decisions, cross-window work, and global desktop intent only when a temporary FULL_ACCESS session is active.

## Authorization Model

DesktopVisual requires an explicit target title for window-scoped work. The title must resolve to one visible top-level window before input is sent. Input commands still verify foreground focus before `SendInput`.

Authorization is checked through two layers:

- `config\safety.conf`: hard title/process/root/runtime limits.
- `config\safety_manifest.json`: machine-readable manifest for denied sensitive categories, consent rules, runtime limits, audit settings, and optional additional allowlists.
- `PermissionManager`: DEFAULT/FULL_ACCESS mode gate, temporary FULL_ACCESS session validation, TTL/scope enforcement, and immutable stop-condition decisions.

DEFAULT cannot loosen `safety.conf`. FULL_ACCESS can relax the DEFAULT title/process/action range only after session validation, but it cannot override immutable safety rules, foreground checks, explicit stop conditions, or filesystem read/write roots.

## Safety Manifest

The manifest declares:

- `allowed.window_titles`, `allowed.processes`, `allowed.read_roots`, `allowed.write_roots`, `allowed.actions`
- `denied.window_title_patterns`, `denied.processes`, `denied.sensitive_categories`
- `runtime_limits.max_steps`, `max_duration_ms`, `max_recoveries`, `emergency_stop_key`
- `consent.requires_explicit_target`, `requires_visible_foreground_window`, `allow_background_control`, `allow_unrestricted_desktop`
- `audit.write_audit_log`, `write_markdown_report`, `redact_clipboard_text_in_logs`
- `permission_modes.DEFAULT`
- `permission_modes.FULL_ACCESS`

Default denied categories include password, payment, credential, admin elevation, protected desktop, anti-cheat, and captcha. Default denied title patterns include `password`, `credential`, `payment`, `login`, and `captcha`. Default denied process names include `Consent.exe` and `CredentialUIBroker.exe`.

## Permission Profiles

`DEFAULT` keeps the existing safety boundary. It denies the broad capabilities `third_party_apps`, `external_web`, `communication`, `content_decision`, `cross_window`, and `global_desktop`.

`FULL_ACCESS` allows those broad capabilities only with an active temporary FULL_ACCESS session. Sessions are created only by local interactive `unlock-full-access` confirmation, inspected by `permission-status`, and removed by `lock-full-access`. Sessions have a TTL and a scope (`task-only` or `session-only`). They are stored under `artifacts\permission` and are not written as defaults.

`unlock-full-access` presents `[1] DEFAULT` and `[2] FULL_ACCESS` in a local console. Selecting FULL_ACCESS prints a risk warning and requires typing `ENABLE FULL_ACCESS` exactly. Piped input, non-console runners, automated confirmation flags, task files, and service endpoints cannot unlock FULL_ACCESS and return `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION`.

FULL_ACCESS still stops on `USER_TAKEOVER_REQUIRED`, `CAPTCHA_DETECTED`, and `LOOP_GUARD_STOP`.

## Service Protocol

v3.5.0 stabilizes Service Protocol v1.0 for explicit local `winagent serve` sessions. Service requests use the same PermissionManager, SafetyPolicy, Safety Manifest, foreground checks, read/write roots, TaskRunner limits, and recovery boundaries as CLI requests.

Service mode cannot unlock FULL_ACCESS, cannot provide interactive confirmation, cannot create sessions from request bodies, and cannot offer hidden or background unrestricted desktop control. It may use FULL_ACCESS only when the caller supplies an already valid `full_access_session_id`.

## Developer Tool Dogfood

v3.6.0 dogfood tasks are bounded evidence checks, not permission expansions. They operate only in normal user windows and local artifact directories, skip pre-existing user sessions, and avoid external web, real accounts, browser profiles, payments, passwords, captcha, social apps, games, anti-cheat, UAC, and administrator windows.

Each dogfood task declares a safety boundary, expected result, and SKIPPED condition. Dogfood PASS does not loosen DEFAULT/FULL_ACCESS rules and does not prove arbitrary software control.

v4.6.0 visual dogfood keeps the same boundary while requiring v4 perception evidence in each case. `local_mail_mock` is mock-only and must not send real email. `local_problem_page` is a development benchmark fixture and must not be treated as real exam, hiring-test, certification, proctored, rated-contest, or public assessment automation. Any blocked or unknown high-risk state must stop and be recorded.

v4.7.0 release candidate checks verify the v4 evidence chain and public-release hygiene. They do not grant release permission by themselves. Public release must be prepared separately under `D:\desktopvisual-release` with restricted exam, interview assessment, hiring test, certification, proctored, rated-contest, game-cheat, captcha, anti-cheat, payment, credential, and account-security permissions.

## Global Desktop And App Launch

v3.3.3 adds `launch-app` for FULL_ACCESS-gated normal user desktop launches. Supported launch kinds are `exe`, `desktop-shortcut`, `start-menu`, `explorer`, and `this-pc`.

`launch-app` requires:

- `permission_mode: FULL_ACCESS`
- a valid `full_access_session_id`
- an explicit expected visible target title
- an explicit expected process name

After launch, the runtime waits for exactly one visible matching top-level window and records title, process, hwnd, pid, and rect. If no visible target appears it returns `WINDOW_NOT_VISIBLE`; if multiple visible targets match it returns `WINDOW_NOT_UNIQUE`. The command does not perform hidden background control.

Launch hard stops include credential/password surfaces, login/user-takeover surfaces, UAC/protected desktop targets, anti-cheat targets, and anti-automation targets. Repeated launch attempts and abnormal visible-window growth stop with `WINDOW_SPAWN_LOOP`.

## External Web And Browser Navigation

v3.3.4 adds `browser-nav` for FULL_ACCESS-gated browser navigation. DEFAULT permits local/simulated browser checks but rejects non-local external URLs. FULL_ACCESS permits external URLs only with a valid temporary session id.

`browser-nav` records the requested URL, action, permission mode, session id, load result, page title when available, stop reason, and last action. Local `file://` pages are used by selftests so the navigation logic can be validated without depending on external network availability.

Web hard stops include login/password/credential URLs, captcha/challenge URLs, payment/checkout URLs, and anti-automation/bot-detection URLs. URL redirect loops stop with `URL_REDIRECT_LOOP`. No-progress and repeated-action stops are reserved as `NO_PROGRESS_DETECTED` and `REPEATED_ACTION_LIMIT` for higher-level browser workflows.

The command does not automate credential entry, captcha solving, payment confirmation, detection bypass, or hidden/background browser control.

## Form And Control Semantics

v3.3.5 adds `FormControl` recognition and `form_action` mapping. The runtime distinguishes textboxes, textareas, radio buttons, checkboxes, dropdowns/comboboxes, buttons, links, date pickers, file uploads, code editors, captcha/challenge controls, and unknown fields.

Unknown or low-confidence fields stop with `FIELD_CONFIDENCE_LOW`; multiple matching fields stop with `FIELD_NOT_UNIQUE`; captcha/challenge controls stop with `CAPTCHA_DETECTED`. The runtime must not default unknown controls to textbox behavior.

## Visual Source Providers

v4.1.0 `observe2` visual sources are read-only. UIA and image-template sources can produce standardized candidates for inspection and graph construction. Placeholder local visual, cloud VLM, and agent providers report unavailable or degraded unless future reviewed integrations are added.

v4.2.0 `observe-loop` is also read-only. It may capture screenshots, compute screen deltas, refresh ROI OCR/UIA on changed rounds, and write JSONL/report artifacts. It must not execute actions, run unattended sensitive-page control, or send unresolved visual candidates to input. Safety Manifest denied targets emit `safety_blocked` and stop.

v4.4.0 Dynamic UI Recovery adds PerceptionRouter, SemanticResolver, RiskRouter, and ActionExecutor gate outputs. Runtime-owned recovery may wait/re-observe loading, invalidate stale candidates, rebuild affected perception, and re-locate moved elements. Dialogs require a safe route or user confirmation. Errors stop or escalate by risk. `blocked` is an immediate `STOP` and is not routed to VLM. `unknown` does not auto-execute.

Visual providers cannot click, type, focus, submit, send, browse, or change permission state. A visual-only candidate without semantic support remains `semantic_status="unresolved"` and is blocked by `act` with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`. Captcha, anti-cheat, protected desktop, credential, payment, and high-risk authentication surfaces remain stop conditions; they are not routed to VLM providers for bypass.

## App Profiles

v4.5.0 App Profiles are application adapters, not Permission Profiles. They can describe window matching, common locators, OCR ROIs, visual/OCR/recovery strategies, task templates, and confirmation nodes for local apps or local fixtures.

Profiles cannot grant `FULL_ACCESS`, cannot unlock broad capabilities, cannot loosen `config\safety_manifest.json`, and cannot loosen `config\safety.conf`. `profile-report` exposes `effective_capabilities.can_override_safety_manifest=false`, and profile-derived locator metadata returns `action_gate="requires_runtime_safety_policy"`.

Built-in profiles are local safe adapters only. The local problem and mail mock profiles are fixtures and are not real public assessment or real email profiles. Public release under `D:\desktopvisual-release` must keep restricted permissions for exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows.

## General Decision Tasks

v3.3.6 adds the General Decision Task Runtime. It chooses one fill/select/click/submit action for one resolved control based on an explicit `user_goal` and the current page/control context. It is gated on the `content_decision` capability: `DEFAULT` denies it with `SAFETY_POLICY_DENIED`, and `FULL_ACCESS` requires a valid unlocked session id.

The Decision Engine is deterministic and does not send input, focus windows, browse remote URLs, generate goals, or relax any boundary. `TaskRunner` still performs window resolution, foreground checks, SafetyPolicy, and Safety Manifest checks before any action.

Decision rules are immutable:

- Page, chat, or web content can never override the user's original goal.
- Instruction-injection text (for example "ignore previous instructions") is flagged and ignored; the decision source stays `user_goal`.
- Unknown or low-confidence controls stop with `FIELD_CONFIDENCE_LOW`; multiple matches stop with `FIELD_NOT_UNIQUE`.
- Critical submit actions require explicit `allow_submit` authorization; otherwise the task stops with `USER_TAKEOVER_REQUIRED`.
- Captcha/challenge controls stop with `CAPTCHA_DETECTED`, anti-automation/AI-detection content stops with `ANTI_AUTOMATION_DETECTED`, and credential content stops with `CREDENTIAL_INPUT_DETECTED`.

The runtime does not support bypassing captcha, AI detection, anti-script, or anti-cheat controls, and it does not perform autonomous sending or publishing without a user goal.

`decision-eval` is a dry-run decision check over a local HTML/DOM-like fixture; it does not click, type, focus, or inspect a live window.

## Session Checkpoints And Loop Guard

v3.3.7 adds `SessionCheckpoint` records and TaskRunner loop guard stops for long-running strategy tasks. Checkpoints record observable state, recent actions, and recovery suggestions; they are not rollback guarantees for sent messages, submitted forms, or remote state changes.

Checkpoint triggers include session start, configured time intervals, page completion markers, manual `checkpoint` steps, submit/send/window-switch boundaries, unknown states, and loop guard stops. Temporary checkpoint files are removed at session end when cleanup is enabled, while the task report retains the checkpoint summary.

Loop guard stops include repeated actions (`REPEATED_ACTION_LIMIT`), URL loops (`URL_REDIRECT_LOOP`), no observable progress (`NO_PROGRESS_DETECTED`), repeated window spawning (`WINDOW_SPAWN_LOOP`), scroll no-progress (`SCROLL_NO_PROGRESS`), and max-step/max-duration overruns (`LOOP_GUARD_STOP`). These stops are not auto-recovered by broadening selectors or continuing input.

## Recovery Strategy Engine

v3.4.0 adds a Recovery Strategy Engine for TaskRunner failures. Recovery is finite, reportable, and bounded by the effective `max_recoveries` after Safety Manifest clamping.

Strategy table:

- `LOCATOR_NOT_FOUND`: re-observe -> OCR fallback -> stop.
- `WINDOW_NOT_FOUND`: find process/window -> activate -> stop.
- `LOCATOR_NOT_UNIQUE`: require explicit selector or `nth`; do not auto choose.
- `TEXT_NOT_FOUND`: wait -> re-observe -> stop.
- `SAFETY_POLICY_DENIED`: stop immediately; no recovery attempt.

Recovery never relaxes PermissionManager, SafetyPolicy, Safety Manifest, foreground checks, or immutable stop conditions. It must not guess coordinates, broaden the target window, choose from ambiguous matches, retry safety-denied actions, or continue after protected desktop, credential, captcha, anti-cheat, or loop guard stops.

## Communication Actions

v3.3.8 adds `communication_step` for user-authorized communication actions. DEFAULT denies communication. FULL_ACCESS requires a valid temporary session id and still cannot override credential, captcha, account-verification, anti-automation, protected-desktop, or user-takeover stops.

Communication sends require `user_requested_send=true` and one explicit target from the user task or clear user context. Missing targets, missing send authorization, and group/multi-target sends stop with `USER_TAKEOVER_REQUIRED` in v3.3.8. Full message content is not written to reports or audit logs; the runtime records a summary and content hash.

Page, chat, or third-party content cannot create a new send instruction or override the user's original task.

## Coding Workflows

v3.3.9 adds `coding-eval` and `type: "coding"` task steps for local simulated OJ/programming-practice pages. Coding task steps are gated on the `content_decision` capability: DEFAULT denies them with `SAFETY_POLICY_DENIED`, and FULL_ACCESS requires a valid unlocked session id.

The workflow records `CodingWorkflowContext` and `CodingWorkflowRecord`, including problem summaries, language, editor/run-button detection, result state, revision count, code summary or code path, and whether submit was explicitly allowed. Full code text is not written to reports.

Coding workflow rules are immutable:

- Page/problem content can never override the user's original goal.
- Login or password surfaces stop with `USER_TAKEOVER_REQUIRED`.
- Captcha/challenge surfaces stop with `CAPTCHA_DETECTED`.
- Anti-automation or AI-detection content stops with `ANTI_AUTOMATION_DETECTED`.
- Missing reliable code editor or Run Code control stops with `LOCATOR_NOT_FOUND`.
- Submit requires `allow_submit=true`; otherwise the workflow stops before submit.

The v3.3.9/v3.3.10 development runtime does not hard-stop solely on exam, assessment, hiring-test, certification, or rated-contest keywords because those categories are explicitly allowed by the stage 9 requirements when the user provides the task goal. Public releases must add an explicit permission layer for these categories before enabling them outside controlled local development. That release policy must not allow proctoring bypass, anti-cheat bypass, captcha bypass, credential handling, paid-limit bypass, batch submit, or problem-set scraping.

## Local Development Versus Release Tree

`D:\desktopvisual` is the local development and future evaluation tree. It may keep the broadest project permission surface for controlled local development tests, simulated-exam correctness evaluation, operation-accuracy evaluation, and future runtime optimization. This local posture does not remove immutable stops for credentials, captcha, payment, UAC, protected desktop, anti-cheat, anti-automation bypass, paid-limit bypass, batch submit, or problem-set scraping.

Public release must not be made by submitting `D:\desktopvisual` directly. A release candidate intended for publication must be prepared in:

```text
D:\desktopvisual-release
```

The `D:\desktopvisual-release` tree must contain the restricted permission policy. Exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows must be disabled or gated by a dedicated permission model in that release tree before distribution.

## Full Access Benchmark Evidence

v3.3.10 adds the Full Access benchmark harness as an evidence layer, not a new permission bypass. The matrix runs local simulated scenarios for DEFAULT denial, FULL_ACCESS unlock gating, safe app launch, external-web simulation, mixed forms, decision tasks, checkpoint loop guard, communication, coding workflow, and public-release assessment permission notice coverage.

Evidence packs include selected reports and safety/runtime docs while excluding real account information, real communications, browser profiles, raw motion data, build outputs, and sensitive logs. A PASS is scoped to the listed scenario on the current machine. SKIPPED is not PASS.

## Commands

Use these commands before automation or during adapter startup:

```powershell
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe permission-status
D:\desktopvisual\bin\winagent.exe unlock-full-access --ttl 900 --scope session-only
D:\desktopvisual\bin\winagent.exe lock-full-access
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe policy-check --title "External Browser" --process msedge.exe --action external_web --permission-mode FULL_ACCESS --full-access-session-id <id>
D:\desktopvisual\bin\winagent.exe browser-nav --url https://example.com/ --permission-mode FULL_ACCESS --full-access-session-id <id>
D:\desktopvisual\bin\winagent.exe decision-eval --html .\page.html --user-goal "answer question 1" --field-id q1 --value b
D:\desktopvisual\bin\winagent.exe coding-eval --html .\oj.html --user-goal "practice problem" --action run_code --language cpp
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

`unlock-full-access` is the only command that can create a FULL_ACCESS session, and only after the local interactive flow described above. `safety-report` writes:

- `artifacts\safety\safety_report.md`
- `artifacts\safety\safety_report.json`

`policy-check` performs a dry-run allow/deny decision and accepts `--permission-mode DEFAULT|FULL_ACCESS`. FULL_ACCESS requires `--full-access-session-id`. It does not click, type, focus, read OCR, or inspect the target UI. `consent-check` verifies the requested title is explicit, unique, visible, and not denied by manifest rules. It does not pop up UI or send input.

## Run-Task Integration

`run-task` performs an internal startup permission and policy check. It stops immediately with `FULL_ACCESS_SESSION_REQUIRED` or `SAFETY_POLICY_DENIED` when:

- the task requests `permission_mode: "FULL_ACCESS"` without a valid active `full_access_session_id`
- the task requests `allow_unrestricted_desktop`
- the target title or process matches a denied sensitive rule
- the target is outside `safety.conf`
- manifest allowlists are explicitly configured and the target/action is outside them

Task reports include a `Safety Manifest` section, a `Permission Decision` section, and the initial policy check result.

Task templates are expanded before execution into normal TaskRunner steps. Template declarations are auditable metadata and do not grant permissions. Expanded steps must still pass unique-window resolution, WindowSession reconfirmation, SafetyPolicy, Safety Manifest, foreground focus, selector uniqueness, and expectation checks.

## Foreground And Protected Desktop Limits

DesktopVisual does not support background control. Input is sent only after the target window is focused and `GetForegroundWindow()` matches the target HWND.

DesktopVisual does not control administrator windows, UAC prompts, protected desktops, elevated processes, anti-cheat protected windows, credential dialogs, payment flows, captcha flows, or security-sensitive applications. FULL_ACCESS does not change this.

## Emergency Stop

The default emergency stop key is `F12`. Human cursor movement, operator-human cursor movement, human typing, and motion recording check it during execution. If triggered, the action stops and returns `EMERGENCY_STOP` or `EMERGENCY_STOPPED`.

## Agent Stop Conditions

Agents must stop on:

- `SAFETY_POLICY_DENIED`
- `FULL_ACCESS_SESSION_REQUIRED`
- `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION`
- `USER_TAKEOVER_REQUIRED`
- `CREDENTIAL_INPUT_DETECTED`
- `PROTECTED_DESKTOP_DETECTED`
- `CAPTCHA_DETECTED`
- `ANTI_AUTOMATION_DETECTED`
- `ANTI_CHEAT_DETECTED`
- `LOOP_GUARD_STOP`
- `WINDOW_NOT_FOUND`
- `WINDOW_NOT_UNIQUE`
- `WINDOW_NOT_VISIBLE`
- `WINDOW_SPAWN_LOOP`
- `URL_REDIRECT_LOOP`
- `NO_PROGRESS_DETECTED`
- `REPEATED_ACTION_LIMIT`
- `SCROLL_NO_PROGRESS`
- `LOCATOR_NOT_FOUND`
- `LOCATOR_NOT_UNIQUE`
- `WINDOW_FOCUS_FAILED`
- `EMERGENCY_STOP`
- any `MOTION_PROFILE_*` error
- report failure or failed expectation

Agents must not broaden window titles, guess coordinates, switch to another window, automate sensitive flows, or request unrestricted desktop control after a stop condition.




