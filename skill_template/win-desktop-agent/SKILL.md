---
name: win-desktop-agent
description: Use when Codex needs to run authorized Windows desktop GUI tasks through DesktopVisual v1.1.0 visible-first runtime. Open apps, URLs, .lnk, .url, webpage shortcuts, and Visual Studio IDE workflows through visible desktop-first paths; use observe / locate / act / verify or task-visible evidence chains; use memory-frame-first OCR from full-screen frame evidence; use provider-gated VLM assist on the real provider path only for frontend perception/locate failures; use compact progress with full evidence; preserve bounded fallback discipline; stop on active protection and report errors instead of guessing coordinates or using backend shortcuts.
---

# Win Desktop Agent - DesktopVisual v1.1.0 Skill Contract

DesktopVisual is a Windows visible-first desktop runtime, not a background script executor. It gives agents a controlled, auditable workflow for authorized Windows desktop tasks through CLI, Skill scripts, explicit local service mode, task templates, reports, Safety Manifest checks, and local visible input primitives.

Project root resolution: pass `-Root`, set `DESKTOPVISUAL_ROOT`, or keep DesktopVisual at the legacy `D:\desktopvisual` fallback.

## Entry Contract

The agent's goal is not the fastest path; it must prefer visible, auditable, human-like desktop operations. Every input action must have observe / locate / act / verify evidence, or an equivalent task/visible command evidence chain. A task can fail because the path was illegal even when the final application state appears correct.

## Agent Compact Output Policy

Default agent chatter uses compact progress with full evidence retained in artifacts: `report_level=compact`, `evidence_level=full`, `progress_output=compact`, `step_chat_detail=compact`, and `artifact_evidence=full`.

Each normal progress update should be short. Failure output expands and must include the error, evidence, and next repair. compact output must not hide failures and must not reduce audit artifacts.

Use read-once context: create or reuse `agent_context_digest.md` for long version context, and do not repeatedly reread full documents as a default workflow. Search narrowly and do not scan artifacts, `.git`, `bin`, or `obj` unless a verifier explicitly requires that path.

Before any GUI action:

1. Run `<project_root>\bin\winagent.exe version` and confirm `data.project_root` plus `data.manifest_loaded`.
2. Run `safety-report` when the task involves desktop input.
3. For opening an app, URL, `.lnk`, `.url`, local shortcut, or webpage shortcut, use the `visible-app-launch` contract below before any backend launch path.
4. For an already-open target, run `observe --title "<target>"`, confirm one visible target window, read `data.safety`, and choose a locator from the priority list.
5. After every key action, observe or read the task report before deciding the next step.

## Visible-App-Launch Contract

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first.

Desktop-first means:

1. Show or reveal the desktop surface.
2. Observe the desktop surface.
3. Locate the target through UIA, OCR, visible icon evidence, or visible shortcut evidence.
4. If a matching desktop icon, `.lnk`, `.url`, or webpage shortcut is found, open it with real mouse movement and double-click.
5. If target-title or process is provided, target_window_verified must be true before the launch is reported successful.

Start Menu visible search is a fallback, not the first choice. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.

If the first desktop locate or double-click fails, do not immediately switch to Start Menu. The launch path needs two bounded desktop visible attempts or strict surface-impossible evidence before Start Menu visible search, address-bar visible navigation, or any later fallback is allowed.

Final reports for launch tasks must preserve the key evidence fields:

- `runtime_visible_first_launch`
- `launch_strategy`
- `desktop_surface_attempted`
- `desktop_icon_path_used`
- `start_menu_fallback_attempted`
- `backend_launch_used`
- `bounded_recovery_attempted`
- `target_window_verified`

## Three-Layer Fallback Contract

Layer 1: visible UI path. Use UIA/OCR/visible icon/template evidence, real mouse/keyboard, target-window lock, coordinate mapping, and post-action verification.

Layer 2: visible keyboard fallback. Use shortcuts, Start Menu visible search, address-bar visible navigation, or other visible keyboard-driven paths only after Layer 1 is proven unavailable by the fallback gate.

Layer 3: backend fallback. Use direct launch, backend browser navigation, file writes, clipboard/backend injection, script execution, or similar backend paths only after visible path failure plus keyboard fallback failure. backend fallback is not the default path.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not switch layers after one locator failure. Do not switch layers after one click failure. Do not disguise clipboard/backend write as visible input success.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Each bounded visible attempt record must include:

- pre-action checkpoint
- observe / locate / action
- failure reason
- bounded recovery
- re-observe / re-locate
- second visible action

Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

Active protection or security interception is STOP, not fallback.

## Locator Priority

Use locators in this order unless a task template or command contract declares a stricter order:

1. `uia:` selector.
2. `text:` selector only when `ocr_available=true`.
3. `image:` selector for custom-drawn UI with a reviewed BMP template.
4. `coord:` selector only when the user, a reviewed case/task, or a visible locate result supplies coordinates.

## Capture/OCR Pipeline Contract

The full-screen frame source-of-truth is unchanged. A full-screen capture creates a `frame_id` and `screenshot_id`, and OCR, foreground/window crop OCR, VLM transport, and PNG evidence must derive from that same frame.

OCR memory-frame-first is required. Normal OCR must use `ocr-fullscreen-frame`, `ocr-foreground-from-frame`, or `ocr-window-from-frame` and must report `png_read_for_ocr=false`. PNG evidence must be retained, but it is audit evidence, not the OCR input path.

PNG evidence is saved asynchronously by default. Before reporting failure or BLOCKED, flush evidence with `evidence-flush` / `frame-evidence-flush`; if flush fails, report `EVIDENCE_FLUSH_FAILED` instead of PASS.

Foreground/window OCR must crop from full-screen frame memory. If the crop fails or is insufficient, OCR fallback must use full-screen OCR on the same frame and preserve `same_frame_for_fallback=true`.

OCR result evidence must bind `frame_id` and `screenshot_id`, include OCR cache/tile cache fields when present, and preserve cache validation evidence.

VLM frame transport is provider-dependent transport. Current Codex CLI VLM uses file path transport with `--image <png_path>`, so the VLM input image is generated from frame bytes and is not a recaptured screenshot. Future providers may use memory bytes/base64 when supported. Do not use legacy mock VLM as a normal path.

## Visual Locator Safety

Locator failure is not permission to guess. `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `IMAGE_MATCH_NOT_FOUND`, and `click_failed` must be reported with the locator method, target title, error code, whether input was executed, and report/artifact path.

Bounded recovery may re-observe and retry the same visible surface only when the task contract or visible command allows it. It must not broaden the title, switch windows, click nearby coordinates, silently change locator class, or move to a keyboard/backend layer without the fallback evidence above.

## Developer Permission Contract

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions. ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

Stop when there is a real active protection or security-interception mechanism, including CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, `CredentialUIBroker`, `Consent.exe`, UAC/protected desktop, proctoring, lockdown browser, secure exam browser, ACE, EasyAntiCheat, Vanguard, BattlEye, or other anti-cheat/anti-automation interception. Do not research or attempt bypass.

## Public Permission Contract

`PUBLIC_DEFAULT` is aligned with ordinary visible desktop capability. It allows ordinary visible desktop action, ordinary third-party app workflows, browser and https pages, localhost pages, Explorer/file manager workflows, local file open, cross-window visible workflow, global desktop visible workflow, and validated absolute screen coordinate action.

`PUBLIC_DEFAULT` must not stop on broad words such as test, exam, challenge, submit, or assessment by themselves. A real exam/proctoring/lockdown browser environment is different and must STOP.

The developer profile is not tightened by public policy changes. Developer mode and public mode both STOP on real active protection or security interception: CAPTCHA, human verification, bot challenge, automation detected, script detected, credential/security handoff, UAC/protected desktop, proctoring, lockdown browser, secure exam browser, ACE, EasyAntiCheat, Vanguard, BattlEye, or other anti-cheat/anti-automation interception.

## VLM Assist Contract

v1.0.3 supports provider-gated VLM assist. v1.0.3.1 keeps the v1.0.3+ normal VLM path on provider-gated VLM assist through the real provider bridge. At the start of a large task or session, run `vlm-capability-probe` once and reuse the session cache; do not probe on every step. If `VLM_AVAILABLE`, Runtime may call `vlm-assist-locate` only after UIA, OCR, image/template, icon, or other frontend perception/locate evidence is unreliable, then use `vlm-candidate-validate` before Runtime action planning. If `VLM_UNAVAILABLE`, continue Runtime-only visible paths and normal fallback discipline; do not invent VLM results.

VLM is an assistive perception layer, not the controller. It may identify visible text, icons, regions, and locate-only candidate bbox/point evidence, but it must not move the mouse, click, type, execute commands, choose backend fallback, or bypass SafetyPolicy. Every VLM candidate must be Runtime validated, coordinate-mapped, bound to `screenshot_id` or `frame_id`, and recorded with provider/session/raw/parsed evidence before Runtime may use the candidate for a second visible attempt.

VLM is not called for every action and is not used after backend fallback starts. In keyboard fallback, VLM may help interpret an unclear visual state, but it must not generate shortcuts or execute actions. Active protection or security interception is STOP, not a reason to call VLM.

Do not use legacy mock VLM commands for normal Agent work. They are deprecated test-only fixtures and are not real VLM success.

For v1.0.5, VLM input image transport is frame-bound. Codex CLI currently needs file path input, so `provider_transport=file_path`, `provider_requires_file_input=true`, and `supports_memory_bytes=false` are expected. The VLM input image comes from the existing frame, not a new screenshot, and OCR must not read the VLM transport PNG.

v1.0.4 complex IDE workflows must use `RealVlmRuntimeBridge` / the real VLM bridge path, then add coordinate mapping, target-window lock, Runtime visible action execution, and post-action verification before any accepted candidate can influence an action.

## Visual Studio C++ Complex IDE Workflow Contract

For Visual Studio C++ workflows, Visual Studio must open by visible desktop icon double-click: reveal/show desktop, locate the Visual Studio/VS desktop icon through UIA/OCR/visible evidence, move the mouse to the icon, double-click it, and verify the VS window. Do not use Start Menu search, PowerShell launch, ShellExecute, direct `devenv.exe`, or backend `.sln` open as the normal path.

Use the fixed project name `SingleTestProject` and the Empty Project template when creating the fixture. Keep the VS default project location and other settings unchanged. Create the project only once, then reuse it through visible VS UI such as the Start Window Recent Project path or a visible File/Open dialog.

Add `.cpp` and `.h` files through Solution Explorer visible IDE UI: right-click Source Files or Header Files, Add, New Item, choose the file type, enter the name, and click Add. If the context menu path fails, select the folder and use visible `Ctrl+Shift+A`. Do not create source/header files through backend writes, scripts, or `.vcxproj` edits.

Code input must occur through the visible VS editor, with visible save evidence. Build through VS UI or visible IDE shortcut such as `Ctrl+Shift+B`. Run through VS UI or visible IDE shortcut such as `Ctrl+F5`, and verify output from a visible console or VS output surface. Do not use backend `msbuild`, `devenv` command line builds, or direct exe runs as acceptance evidence.

Every VS UI action needs a step checkpoint with `step_id`, `intended_action`, `visible_observe_before`, `target_source`, `action_command`, `visible_observe_after`, `verification_result`, `recovery_needed`, optional `recovery_action`, and `next_step_allowed`. If verification fails, stop until visible recovery succeeds or report BLOCKED. Successful project/file/stage boundaries close VS through visible top-right X; normal close must not use process kill.

## Execution Workflow

For complex GUI tasks, prefer `run-task` with reviewed task.json. Check `tasks\templates` first and use a bundled template when it matches the workflow; do not compose coordinate-heavy low-level steps when `click_button`, `fill_form`, `wait_until_text`, `wait_until_window`, `copy_text`, `save_file`, `open_local_html`, or `run_local_test_page` applies.

```powershell
powershell .\scripts\run-task.ps1 -TaskFile D:\desktopvisual\tasks\testwindow_basic.task.json
powershell .\scripts\summarize-task-report.ps1 -ReportFile <report.md>
```

After a template task, read the report's `## Templates` section and summarize the template name, parameters, expanded steps, and result.

For medium scripted tasks, use reviewed Case v2:

```text
case_version=2
target_title="Agent Test Window"
act selector="uia:name=Click Me" action="click" expect_selector_exists="uia:name=Click Me"
```

For small single actions, use observe -> locate -> act -> observe -> verify:

```powershell
powershell .\scripts\observe-target.ps1 -Title "Agent Test Window"
powershell .\scripts\locate-target.ps1 -Title "Agent Test Window" -Selector "uia:name=Click Me"
powershell .\scripts\act-target.ps1 -Title "Agent Test Window" -Selector "uia:name=Click Me" -Action click
powershell .\scripts\observe-target.ps1 -Title "Agent Test Window"
```

Default mouse behavior for this Skill is `human`, which resolves to the local `operator-human` calibrated profile. Do not request `instant` unless the user explicitly asks for test-speed automation.

Use `operator-human` only when `motion-profile-info` shows `source=human`, or when a reviewed test explicitly supplies a synthetic/sample profile with `--profile` and `--allow-synthetic-profile`. Do not automatically run human calibration unless the user explicitly asks. Synthetic and sample profiles are for reviewed tests only; never describe them as human profiles. Do not describe `operator-human` as detection bypass, anti-cheat bypass, or human-verification bypass. If `operator-human` returns any `MOTION_PROFILE_*` error, stop and report it instead of silently falling back, unless the reviewed command or task explicitly declares `fast-human` fallback.

## Service Mode

If `winagent serve` is already running, service calls may be used. If service mode is not running, fall back to CLI. Do not start service mode unless the user explicitly requested it or the task instructions allow it. Service mode does not bypass SafetyPolicy.

## Error Handling Contract

command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS. If final state appears successful but evidence shows a disallowed fallback, report failure.

Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry. Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.

Stop immediately on unrecoverable errors and active-protection stops, including:

- any non-empty `error.code`
- `LOCATOR_NOT_FOUND`
- `LOCATOR_NOT_UNIQUE`
- `OCR_UNAVAILABLE` without a declared UIA alternative or fallback gate
- `SAFETY_POLICY_DENIED`
- `WINDOW_NOT_FOUND`
- `WINDOW_NOT_UNIQUE`
- `ASSERTION_FAILED` or `EXPECT_FAILED`
- `EMERGENCY_STOP`
- `MOTION_PROFILE_NOT_FOUND`
- `MOTION_PROFILE_INVALID`
- `MOTION_PROFILE_NOT_HUMAN`
- `MOTION_PROFILE_SOURCE_REQUIRED`
- `MOTION_PROFILE_TEST_ONLY`
- `MOTION_PROFILE_INSUFFICIENT_SAMPLES`

`run-task` may perform only bounded documented recovery. It may refocus once, reobserve and retry locate once, recheck an expectation once, or use a declared UIA alternative for OCR failure. It must not repeat input unless the task explicitly allows retry.

## Scripts

| Script | Purpose |
|---|---|
| `scripts\observe-target.ps1` | Run observe |
| `scripts\locate-target.ps1` | Run locate |
| `scripts\act-target.ps1` | Run act |
| `scripts\run-case-v2.ps1` | Run a Case v2 file |
| `scripts\summarize-report.ps1` | Summarize a case report |
| `scripts\run-dogfood-matrix.ps1` | Run real-app dogfood matrix |
| `scripts\run-task.ps1` | Run a v3 task.json |
| `scripts\summarize-task-report.ps1` | Summarize a v3 task report |
| `scripts\selftest-skill-template.ps1` | Verify skill template scripts and references |

## References

- `references\AGENT_USAGE_GUIDE.md`
- `references\CASE_FORMAT.md`
- `references\COMMAND_PROTOCOL.md`
- `references\ERROR_CODES.md`
- `references\KNOWN_LIMITATIONS.md`
- `references\REAL_DEV_WORKFLOW.md`
- `references\SAFETY.md`
- `references\SAFETY_MODEL.md`
- `references\VISIBLE_FIRST_CONTRACT.md`
- `references\VISUAL_SAFETY_FREEZE.md`

## Dogfood

Run:

```powershell
powershell .\scripts\run-dogfood-matrix.ps1
```

Read `D:\desktopvisual\artifacts\dogfood_matrix_report.md`. `SKIPPED` is acceptable when an app is missing or an existing user window prevents safe testing. `FAIL` is a stop condition.
