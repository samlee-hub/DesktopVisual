---
name: win-desktop-agent
description: Use when Codex needs to run authorized Windows desktop GUI tasks through DesktopVisual v1.1.0 visible-first runtime. Use visible-app-launch desktop-first for app/URL/shortcut launch and Visual Studio IDE workflows; use observe-locate-act-verify or reviewed run-task; use memory-frame-first OCR from full-screen frame evidence; use provider-gated VLM assist on the real provider path only for frontend perception/locate failures; use compact progress with full evidence; preserve bounded fallback discipline; report errors and policy violations as failure/BLOCKED, not PASS.
---

# Win Desktop Agent Adapter

DesktopVisual is a Windows visible-first desktop runtime, not a background script executor and not official Codex built-in Computer Use. This Codex adapter is a thin host-specific contract around the same DesktopVisual CLI, scripts, reports, Safety Manifest, and visible input runtime.

Project root resolution: pass `-Root`, set `DESKTOPVISUAL_ROOT`, or keep DesktopVisual at the legacy `D:\desktopvisual` fallback.

Shared adapter rules: `..\..\shared\TASK_FLOW.md`, `SAFETY_RULES.md`, `ERROR_HANDLING.md`, and `REPORT_READING.md`.

safety stop rules: stop on command errors, failed report steps, safety denial, ambiguous windows, active protection/security interception, fallback discipline violation, emergency stop, and invalid motion profiles.

no unrestricted desktop control: this adapter may only operate through DesktopVisual visible-first commands, SafetyPolicy, and task/case reports; it must not take arbitrary global desktop control outside the runtime contract.

no sensitive flows: do not handle credentials, payment submission, protected desktop/UAC prompts, proctoring, anti-cheat, human-verification, or other active protection flows; stop and report the blocker instead of researching bypass.

## Agent Compact Output Policy

Default agent chatter uses compact progress with full evidence retained in artifacts: `report_level=compact`, `evidence_level=full`, `progress_output=compact`, `step_chat_detail=compact`, and `artifact_evidence=full`.

Each normal progress update should be short. Failure output expands and must include the error, evidence, and next repair. compact output must not hide failures and must not reduce audit artifacts.

Use read-once context: create or reuse `agent_context_digest.md` for long version context, and do not repeatedly reread full documents as a default workflow. Search narrowly and do not scan artifacts, `.git`, `bin`, or `obj` unless a verifier explicitly requires that path.

## Required Startup

Before any GUI action:

1. Run `<project_root>\bin\winagent.exe version` and confirm `data.project_root`.
2. Confirm `data.manifest_loaded` from version output.
3. Run `safety-report` for policy visibility when the task involves input.
4. For opening an app, URL, local shortcut, `.lnk`, `.url`, or webpage shortcut, use `visible-app-launch` first.
5. For already-open targets, run `observe --title "<target>"`, confirm one visible target, read `data.safety`, and then locate/act/verify.

## Visible-App-Launch Contract

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches.

App launch is desktop-first. visible-app-launch is desktop-first. Reveal desktop, observe desktop, locate the visible desktop icon/shortcut through UIA/OCR/visible evidence, double-click with real mouse input, and verify the target window when `target-title` or `process` is supplied.

Start Menu visible search is a fallback, not the first choice. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths. backend fallback is not the default path.

One failure cannot directly move to fallback. If the first desktop locate or double-click fails, perform bounded recovery and a second desktop visible attempt, or provide strict surface-impossible evidence.

Required launch evidence includes `runtime_visible_first_launch`, `launch_strategy`, `desktop_surface_attempted`, `desktop_icon_path_used`, `start_menu_fallback_attempted`, `backend_launch_used`, `bounded_recovery_attempted`, and `target_window_verified`.

## Fallback Discipline

Layer 1: visible UI path.
Layer 2: visible keyboard fallback.
Layer 3: backend fallback.

Entering fallback requires two bounded visible attempts or strict surface-impossible evidence. Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure.

Two bounded visible attempts must include pre-action checkpoint, observe / locate / action, failure reason, bounded recovery, re-observe / re-locate, and second visible action.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not switch layers after one locator failure. Do not switch layers after one click failure. Do not disguise clipboard/backend write as visible input success.

The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

Active protection or security interception is STOP, not fallback.

## Locator Priority

Use locators in this order unless a reviewed task declares a stricter path:

1. `uia:` selector.
2. `text:` selector only when `ocr_available=true`.
3. `image:` selector for custom-drawn UI with a reviewed BMP template.
4. `coord:` selector only when supplied by visible evidence, the user, or a reviewed case/task.

## Capture/OCR Pipeline

The full-screen frame source-of-truth is unchanged. All OCR, foreground/window crop OCR, PNG evidence, and VLM transport should remain bound to the same `frame_id` and `screenshot_id`.

OCR memory-frame-first is required. Prefer `ocr-fullscreen-frame`, `ocr-foreground-from-frame`, and `ocr-window-from-frame`; normal OCR must report `png_read_for_ocr=false`. PNG evidence must be retained, but it is saved asynchronously and is not the normal OCR input path.

Flush evidence before failure or BLOCKED with `evidence-flush` / `frame-evidence-flush`. A flush failure is `EVIDENCE_FLUSH_FAILED`, not PASS.

Foreground/window OCR must crop from full-screen frame memory. If crop OCR fails, fallback to full-screen OCR must use the same frame and preserve `same_frame_for_fallback=true`.

VLM transport is provider-dependent transport. Codex CLI currently needs file path input with `--image <png_path>`, so provider input PNG is generated from the frame and must not be treated as a recaptured screenshot or OCR input. Legacy mock VLM is not a normal path.

Locator failure is not permission to guess. Report `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, image/template failure, and click failure with the locator method, target title, error code, whether input was executed, and report/artifact path. Bounded recovery may re-observe and retry the same visible surface only when the task or visible command allows it.

## Developer Permission Contract

Developer mode uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions. Developer mode does not stop on broad category or keyword matching without active protection.

ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

Stop on real active protection or security interception: CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, `CredentialUIBroker`, `Consent.exe`, UAC/protected desktop, proctoring, lockdown browser, secure exam browser, ACE, EasyAntiCheat, Vanguard, BattlEye, or similar anti-cheat/anti-automation mechanisms. Do not research bypass.

## Public Permission Contract

`PUBLIC_DEFAULT` is aligned with ordinary visible desktop capability. It allows ordinary visible desktop action, ordinary third-party app workflows, browser and https pages, localhost pages, Explorer/file manager workflows, local file open, cross-window visible workflow, global desktop visible workflow, and validated absolute screen coordinate action.

`PUBLIC_DEFAULT` must not stop on broad words such as test, exam, challenge, submit, or assessment by themselves. A real exam/proctoring/lockdown browser environment is different and must STOP.

The developer profile is not tightened by public policy changes. Developer mode and public mode both STOP on real active protection or security interception: CAPTCHA, human verification, bot challenge, automation detected, script detected, credential/security handoff, UAC/protected desktop, proctoring, lockdown browser, secure exam browser, ACE, EasyAntiCheat, Vanguard, BattlEye, or other anti-cheat/anti-automation interception.

## VLM Assist

v1.0.3 supports provider-gated VLM assist. v1.0.3.1 keeps the v1.0.3+ normal VLM path on provider-gated VLM assist through the real provider bridge. Probe once per large task or session with `vlm-capability-probe`, reuse the cache, and do not call VLM on every step. If `VLM_AVAILABLE`, Runtime may use `vlm-assist-locate` only after UIA/OCR/image/template/icon frontend perception or locate failure, or for unclear visual state after keyboard fallback, then use `vlm-candidate-validate` before Runtime action planning. If `VLM_UNAVAILABLE`, continue Runtime-only visible paths and do not invent VLM results.

VLM provides visual understanding and candidate bbox/point evidence only. In v1.0.3.1 that evidence is locate-only until Runtime owns action planning and execution. It must not click, type, move the mouse, execute commands, decide backend fallback, run after backend fallback starts, or bypass active protection. Runtime must validate every candidate and bind it to screenshot/frame/provider/session/raw/parsed evidence before using it for a second visible attempt.

Do not use legacy mock VLM commands for normal Agent work. They are deprecated test-only fixtures and are not real VLM success.

For v1.0.5, VLM input images are frame-bound. Codex CLI reports `provider_transport=file_path`, `provider_requires_file_input=true`, and `supports_memory_bytes=false`; future memory bytes transport depends on future provider capability.

v1.0.4 complex IDE workflows must use `RealVlmRuntimeBridge` / the real VLM bridge path, then add coordinate mapping, target-window lock, Runtime visible action execution, and post-action verification before any accepted candidate can influence an action.

## Visual Studio C++ Complex IDE Workflow

Visual Studio C++ workflows must launch VS by visible desktop icon double-click only: show desktop, locate the VS desktop icon by UIA/OCR/visible evidence, move to it, double-click, and verify the VS window. Start Menu search, direct `devenv.exe`, PowerShell launch, ShellExecute, and backend `.sln` open are invalid normal paths.

Use `SingleTestProject` and the Empty Project template for the fixture, keep the VS default location/settings, and reuse the same project after creation. Open the project through visible VS UI, preferably the Start Window Recent Project path.

Add `.cpp` and `.h` files through Solution Explorer visible UI or visible `Ctrl+Shift+A` fallback. Do not backend-create files, write source/header content from scripts, or edit `.vcxproj` as a workflow substitute.

Edit code through the visible VS editor and save visibly. Build with VS UI or `Ctrl+Shift+B`; run with VS UI or `Ctrl+F5`; verify output from a visible console/output surface. Backend `msbuild`, command-line `devenv`, and direct exe runs cannot support PASS.

Each UI action must record a step checkpoint with before/after visible observation, action command, verification result, recovery state, and `next_step_allowed`. Close successful project/file/stage boundaries by visible top-right X, not process kill.

## Execution Workflow

For complex GUI tasks, prefer `run-task` with reviewed task.json. Check `tasks\templates` first and use a bundled template when it matches the workflow.

```powershell
powershell .\scripts\run-task.ps1 -TaskFile D:\desktopvisual\tasks\testwindow_basic.task.json
powershell .\scripts\summarize-task-report.ps1 -ReportFile <report.md>
```

For small single actions, use observe-locate-act-verify:

```powershell
powershell .\scripts\observe-target.ps1 -Title "Agent Test Window"
powershell .\scripts\locate-target.ps1 -Title "Agent Test Window" -Selector "uia:name=Click Me"
powershell .\scripts\act-target.ps1 -Title "Agent Test Window" -Selector "uia:name=Click Me" -Action click
powershell .\scripts\observe-target.ps1 -Title "Agent Test Window"
```

Default mouse behavior for this adapter is `operator-human` through the local calibrated human profile when available. Do not request `instant` unless the user explicitly asks for test-speed automation.

Use `operator-human` only when `motion-profile-info` shows `source=human`, or when a reviewed test explicitly supplies a synthetic/sample profile with `--profile` and `--allow-synthetic-profile`. Do not automatically run human calibration unless the user explicitly asks. Synthetic and sample profiles are for reviewed tests only; never describe them as human profiles. Do not describe `operator-human` as detection bypass, anti-cheat bypass, or human-verification bypass. If `operator-human` returns any `MOTION_PROFILE_*` error, stop and report it instead of silently falling back.

## Service Mode

If `winagent serve` is already running, service calls may be used. If service mode is not running, fall back to CLI. Do not start service mode unless the user explicitly requested it or the task instructions allow it. Service protocol v1.0 responses include top-level `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version`. Service mode does not bypass SafetyPolicy or visible-first discipline.

## Error Handling

Errors and policy violations must be reported as failure or BLOCKED, not PASS.

command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS. If final state appears successful but evidence shows a disallowed fallback, report failure.

Report the failed command, `error_code`, whether input was executed, artifacts/report path, and the next minimal repair entry. Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.

## Scripts

| Script | Purpose |
|---|---|
| `scripts\observe-target.ps1` | Run observe |
| `scripts\locate-target.ps1` | Run locate |
| `scripts\act-target.ps1` | Run act |
| `scripts\desktopvisual-version.ps1` | Run version and show project root |
| `scripts\run-case-v2.ps1` | Run a Case v2 file |
| `scripts\summarize-report.ps1` | Summarize a case report |
| `scripts\run-dogfood-matrix.ps1` | Run real-app dogfood matrix |
| `scripts\run-task.ps1` | Run a v3 task.json |
| `scripts\summarize-task-report.ps1` | Summarize a v3 task report |
| `scripts\selftest-skill-template.ps1` | Verify skill template scripts and references |

## References

- `references\COMMAND_PROTOCOL.md`
- `references\CASE_FORMAT.md`
- `references\ERROR_CODES.md`
- `references\SAFETY.md`
- `references\VISUAL_SAFETY_FREEZE.md`
- `references\AGENT_USAGE_GUIDE.md`
- `references\KNOWN_LIMITATIONS.md`

## Dogfood

Run:

```powershell
powershell .\scripts\run-dogfood-matrix.ps1
```

Read `D:\desktopvisual\artifacts\dogfood_matrix_report.md`. `SKIPPED` is acceptable when an app is missing or an existing user window prevents safe testing. `FAIL` is a stop condition.
