# Safety

Current version: `DesktopVisual 1.1.0`.

## v1.1.0 Public And Developer Permission Boundary

Developer mode remains broad: `DEVELOPER_CAPABILITY_DISCOVERY` is the developer default, `DEVELOPER_FULL_RUNTIME` remains equivalent for ordinary capability, and `allow_absolute_screen_click=true` stays enabled in the developer tree.

`PUBLIC_DEFAULT` now allows ordinary visible desktop operation: ordinary third-party app, ordinary browser/https page, localhost page, Explorer/file manager workflow, ordinary local file open, visible mouse move/click/double-click/right-click, validated absolute screen coordinate action, cross-window visible workflow, and global desktop visible workflow.

Public and developer profiles both STOP on real active protection or security interception: real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot challenge, automation detected, script detected, credential/security handoff, UAC/protected desktop, `Consent.exe`, `CredentialUIBroker`, ACE, EasyAntiCheat, Vanguard, BattlEye, and similar anti-cheat or anti-automation mechanisms.

Broad category words are not STOP signals by themselves. Ordinary app, ordinary webpage, https, localhost, IDE, browser, Explorer, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment are allowed when no real active protection or security interception is present.

## v1.0.2 Safety Boundary

DesktopVisual v1.0.2 keeps the local developer-tree safety policy at:

```text
D:\desktopvisual\config\safety.conf
```

Default configuration:

```text
allowed_titles=Agent Test Window;Motion Lab;Untitled - Notepad
allowed_processes=TestWindow.exe;notepad.exe
allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;${PROJECT_ROOT}\cases;${PROJECT_ROOT}\tasks;D:\testrepo\testwindow
allowed_write_roots=${PROJECT_ROOT}\artifacts;${PROJECT_ROOT}\config;D:\testrepo\testwindow
max_steps=100
max_duration_ms=120000
emergency_stop_key=F12
allow_absolute_screen_click=true
```

The policy is loaded by input commands and `run-case`. Tests may override the config path with `DESKTOPVISUAL_SAFETY_CONFIG`, but normal usage should keep the project-local config file.

The developer tree keeps `allow_absolute_screen_click=true` for visible desktop capability discovery. This does not authorize active-protection bypass, protected desktop control, credential handling, or hidden backend automation. Public release policy now allows ordinary visible desktop operations while preserving real active-protection and security-interception STOP boundaries.

## v3.0.5 Safety Manifest

DesktopVisual v3.0.5 adds:

```text
D:\desktopvisual\config\safety_manifest.json
```

The manifest is machine-readable and records the authorized local-window runtime mode, denied sensitive categories, runtime limits, consent requirements, and audit settings. It is merged with `safety.conf` and cannot loosen `safety.conf` hard limits. Empty manifest allowlists do not grant broad access.

Use:

```powershell
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

See `D:\desktopvisual\docs\SAFETY_MODEL.md` for the full authorization, consent, audit, and stop-condition model.

## Window And Process Whitelist

Input actions must still specify a target window title. The resolved unique window must match `allowed_titles`, and its executable name must match `allowed_processes` when those lists are configured.

If the config file is missing or a whitelist is empty, DesktopVisual does not silently switch to unrestricted operation. Action commands still require explicit `--title`, and case actions still require `target_title=`.

## Unique Title Matching

Input actions must resolve the requested title substring to exactly one visible top-level window. Zero matches or multiple matches are failures.

## Developer Global Desktop Click Boundary

Mouse clicks use target-window client coordinates. The tool does not expose unrestricted full-screen absolute coordinate clicking.

`allow_absolute_screen_click=true` records the current developer-tree global desktop capability for visible-first workflows. It does not bypass visible-app-launch/fallback evidence, active-protection STOP boundaries, or target/focus verification where those are required.

## Case Limits

`run-case` enforces:

- `max_steps`
- `max_duration_ms`
- stop on first failed step
- stop on `EMERGENCY_STOP`

These limits prevent unbounded execution and keep reports reviewable.

## Emergency Stop

The default emergency stop key is `F12`. Human cursor movement, `operator-human` synthesized cursor movement, and human typing check this key while they run. If it is pressed, the action returns `EMERGENCY_STOP` and the case stops. `motion-record` also stops on F12 and returns `EMERGENCY_STOPPED`.

The safety selftest documents this behavior but does not automatically simulate F12.

## Audit Log

v0.1.3 writes stable audit lines to `D:\desktopvisual\artifacts\agent_audit.log` with `timestamp`, `command`, `target_title`, `result`, `error_code`, `duration_ms`, and `data`. Audit logs and case reports are used for Agent replay, debugging, and failure review.

## User Authorization

This platform is for user-authorized development and test windows only. It is not for controlling unauthorized software.

Agent adapters and benchmark scripts do not expand this boundary. They must use `observe-locate-act-verify`, safety stop rules, no unrestricted desktop control, and no sensitive flows.

## OCR Boundary

OCR is only for locating or reading text in user-authorized windows. OCR commands must resolve exactly one target window and pass the configured title/process safety policy before OCR runs. OCR must not be used for credential extraction, security-control bypass, or unauthorized workflow automation. Prefer UI Automation over OCR when a target exposes an accessible control tree.

## File Path Allowlist

`read-file`, case `read_file`, and case `assert_file_contains` normalize paths before reading. The normalized path must be under one of `allowed_read_roots`; otherwise the command fails with `SAFETY_POLICY_DENIED` and no file content is read. Paths containing `..` traversal are denied before file access.

`allowed_write_roots` records the approved local output roots for project artifacts and future write-safety checks. The default roots are `D:\desktopvisual` and `D:\testrepo\testwindow`.

## Focus Verification

Input actions may call `ShowWindow` and `SetForegroundWindow`, but the action proceeds only when `GetForegroundWindow()` equals the target HWND. Failure returns `WINDOW_FOCUS_FAILED`. Input success data and case reports include `foreground_before`, `foreground_after`, and `focus_verified`.

## Operator Motion Profile Boundary

Operator Motion Profile is local movement personalization only. It is not a detection-bypass, anti-cheat, human-verification, or risk-control bypass feature.

`motion-record` records only mouse trajectory samples from an authorized Motion Lab window: x/y, timestamp, button state, screen/client coordinates, scenario, and sample id. It does not record application content, window content, keyboard input, or typed text.

`motion-calibrate --source human|synthetic|sample` writes profiles with explicit origin metadata. The default `config\operator_motion_profile.json` is reserved for `source=human`; synthetic selftest profiles live under `artifacts\motion_profile\synthetic`. Profiles store aggregate duration, velocity, curvature, jitter, endpoint-correction, direction, and distance statistics. They declare `privacy.raw_points_stored_in_profile=false`, `contains_keyboard_text=false`, and `contains_screen_content=false`; full raw traces stay in generated artifact directories.

`operator-human` preserves the same SafetyPolicy, unique-title matching, focus verification, F12 stop, exact final coordinate, and audit requirements as other mouse modes. Mouse `human` is the default alias for `operator-human`. If the requested profile is missing, invalid, missing source, or not human, actions fail explicitly instead of silently falling back. Synthetic/sample profiles require explicit test authorization and must not be represented as human operator profiles.

## Visual Locator Failure Stop

Visual locator features include UI Automation, OCR, and image/template matching. They must stop on zero matches, multiple matches, unavailable locator engines, or any non-empty `error_code`. They must not click nearby positions, broaden the target title, switch locator methods, or perform input after failure without explicit user confirmation.

Required failure reports must include `error_code`, locator method, requested window title, requested element/text/template target, match count if known, whether input was executed, and the report or artifact path.

The detailed frozen rules are in `D:\desktopvisual\docs\VISUAL_SAFETY_FREEZE.md`.

## Image Template Boundary

Image template matching is only for authorized windows and self-owned GUI verification. It must not be used for platform risk-control bypass, unauthorized game automation, or other unauthorized workflows. Prefer UI Automation first, OCR second, and image templates only as a supplement when accessible controls and OCR are insufficient.

## Unsupported Targets

Version 1 does not support administrator windows, elevated processes, protected desktops, protected games, or bypassing security controls.

This is not complete unrestricted computer use. UI Automation exists for limited tree and action workflows. OCR depends on Windows WinRT OCR runtime and language support and returns `OCR_UNAVAILABLE` or `OCR_LANGUAGE_UNAVAILABLE` when it cannot run. Service mode is an explicit local wrapper around existing commands and does not expand permissions. `run-task` supports only the configured Recovery Strategy Engine; it cannot guess coordinates, broaden titles, auto-pick ambiguous targets, or continue after safety denial. There is no MCP service, automatic Skill installation, unrestricted recovery, or autonomous decision-making.

## Benchmark Boundary

Benchmarks operate only authorized windows and generated files under `<project_root>\artifacts`. Expected safety-stop tasks must stop on a configured denial, missing/ambiguous window, or locator failure. They must not convert a failed or skipped sensitive prerequisite into PASS.

## Stopping on Failure

Case execution stops immediately on the first failed step and writes a report. Manual stop is available with F12 during human input, by closing the terminal process, or by closing the target test window.






## Project Root Variables

${PROJECT_ROOT} is expanded from the resolved DesktopVisual project root. Use it in `allowed_read_roots` and `allowed_write_roots` so portable copies keep reads and writes inside their own tree.
