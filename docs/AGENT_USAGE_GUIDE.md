# Agent Usage Guide

Current version: `v3.3.5`.

DesktopVisual is a Windows Agent Desktop Runtime that can be called by Codex, Claude Code, generic CLI agents, and human scripts. Adapter-specific instructions live under `adapters\`; this guide describes the neutral runtime behavior.

## Core Rule

Agents should prioritize reviewed v3 task.json files or Case v2 files through DesktopVisual instead of issuing free-form clicks.

DEFAULT is the safe permission mode. Use FULL_ACCESS only when the user explicitly requests a broader normal-desktop task and a temporary `full_access_session_id` already exists. Agents must not unlock FULL_ACCESS through service mode, task files, piped input, or automated confirmation text; if a session is needed, ask the user to run `unlock-full-access` in a local terminal and type `ENABLE FULL_ACCESS` themselves.

For app launch work, use `launch-app` only with an existing FULL_ACCESS session and an explicit expected visible `--target-title` plus `--process`. Stop on `WINDOW_NOT_VISIBLE`, `WINDOW_NOT_UNIQUE`, `WINDOW_SPAWN_LOOP`, credential, protected desktop, anti-cheat, or anti-automation errors.

For external web work, use `browser-nav` only with an existing FULL_ACCESS session for non-local URLs. Stop on `USER_TAKEOVER_REQUIRED`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, or `REPEATED_ACTION_LIMIT`; do not automate login, payment, captcha, or detection-bypass flows.

For form work, prefer `form-control` or `form_action` when the task involves selecting options or filling structured controls. Stop on `FIELD_NOT_UNIQUE`, `FIELD_CONFIDENCE_LOW`, or `CAPTCHA_DETECTED`; do not assume unknown controls are textboxes.

## Required Loop

1. Run `D:\desktopvisual\bin\winagent.exe version`.
2. Confirm the authorized target window with `find`.
3. For complex tasks, generate a reviewed task.json and run `run-task`; use bundled task templates when a template matches the workflow. For shorter scripted tasks, run a reviewed Case v2 file with `run-case`.
4. Read the generated Markdown report.
5. Summarize the result, failed step, `error_code`, screenshots, and any read state.

Recommended command order:

```text
version
permission-status
find
observe
run-task or run-case
observe
read report
summarize
```

## Standard Agent Loop

Use this loop for real tasks:

```text
observe -> locate -> act -> observe -> verify
```

`observe` and `locate` are read-only. `observe` should be the first command after target confirmation, and it should be repeated after actions when the agent needs to verify visible state before deciding what to do next.

For complex GUI tasks, prefer:

```text
version -> observe -> generate task.json -> run-task -> read MVP report -> summarize evidence
```

If `winagent serve` is already running, service calls may be used for `/version`, `/observe`, `/locate`, `/act`, `/run-case`, `/run-task`, and `/report`. Do not start the service automatically unless the user explicitly asked for service mode. If service mode is unavailable, use the CLI.

Service requests may pass `permission_mode` and `full_access_session_id` for an already unlocked FULL_ACCESS session. Service requests must not create FULL_ACCESS sessions.

## Task Template Priority

Before writing low-level task steps, check `D:\desktopvisual\tasks\templates` for a matching template. Prefer templates for common workflows such as opening or confirming an authorized app window, focusing a window, filling a form, clicking a button, waiting for text/window state, copying selected text, saving a file, opening a local HTML page, and running a local test page.

Template steps are still reviewed task.json. They expand into ordinary TaskRunner steps and do not grant new permissions. Agents must provide explicit parameters, keep the target window authorized, and read the generated report section `## Templates` after execution. If no template fits, use selector-based `locate`/`act` steps before considering coordinates.

## Action Priority

1. Prefer a bundled task template when it matches the workflow.
2. Prefer `locate`/`act` with selectors for new custom task steps.
3. Locator priority: `uia` selector, then OCR-backed `text` selector when OCR is available, then `image` selector, then `coord` selector.
4. Use `uia-find`, `uia-click`, `uia-type`, `click-image`, and `click-text` as compatibility interfaces when needed.
5. Prefer `hotkey` and `clipboard-paste` for structured text or application commands when they are safer than coordinates.
6. Use coordinate mouse actions (`click`, `double-click`, `right-click`, `scroll`, `drag`) last, only against an authorized target window and stable client coordinates.

If `locate` fails with `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `INVALID_SELECTOR`, `OCR_UNAVAILABLE`, or `OCR_LANGUAGE_UNAVAILABLE`, stop. Do not guess nearby coordinates or switch locator methods without user confirmation.

For agent-authored mouse commands, default `human` uses the local `operator-human` profile. Use `instant` for automated tests that do not need calibrated cursor movement. `fast-human` and `demo-human` are legacy curved-path modes and should be requested only when a reviewed case/task explicitly calls for them.

Use `operator-human` only with `motion-profile-info` showing `source=human`, or when a reviewed test explicitly uses a synthetic/sample profile with `--profile` and `--allow-synthetic-profile`. Do not describe or use `operator-human` as a detection-bypass capability, and never present a `synthetic` profile as a human operator profile. If the profile is missing, invalid, missing source, or not human, stop on the returned `MOTION_PROFILE_*` code instead of continuing with guessed movement, unless the reviewed command or task explicitly declares `fast-human` fallback.

## Failure Handling

1. Agent must inspect command JSON and case report `error_code`.
2. If any `error_code` is present, Agent must stop and explain the failure.
3. Agent must not continue with arbitrary clicks after a failure.
4. Agent must preserve report paths and artifacts for review.

### Error Code Table

| error_code | Meaning | Agent action |
|---|---|---|
| `WINDOW_NOT_FOUND` | The target window does not exist or is not visible. | Ask the user to open the window or confirm the title. |
| `WINDOW_NOT_UNIQUE` | The target title matched more than one visible window. | Ask the user to close duplicates or provide a more precise title. |
| `ASSERTION_FAILED` | Actions completed, but a verification assertion failed. | Summarize completed actions and the failed assertion. |
| `INVALID_ARGUMENT` | A case step or command argument is invalid. | Recommend fixing the case file or command arguments. |
| `SEND_INPUT_FAILED` | Input injection failed, usually because of focus, permission, or desktop state. | Stop and explain likely focus or permission causes. |
| `SCREENSHOT_FAILED` | Screenshot capture failed, often due to window state or capture API limits. | Ask the user to restore the window or review capture support. |
| `SAFETY_POLICY_DENIED` | The safety policy denied the target title or process. | Stop and ask the user to review `config\safety.conf`. |
| `FULL_ACCESS_SESSION_REQUIRED` | FULL_ACCESS was requested without a valid active session. | Stop and ask the user to unlock FULL_ACCESS locally if the task requires it. |
| `USER_TAKEOVER_REQUIRED` | The runtime requires human takeover. | Stop and let the user continue manually. |
| `CREDENTIAL_INPUT_DETECTED` | Credential or password input was detected. | Stop; the user must handle credentials manually. |
| `CAPTCHA_DETECTED` | Captcha or verification was detected. | Stop; the user must handle verification manually. |
| `ANTI_AUTOMATION_DETECTED` | Anti-automation or AI-detection control was detected. | Stop and do not attempt bypass. |
| `ANTI_CHEAT_DETECTED` | Anti-cheat protected software was detected. | Stop; this target is unsupported. |
| `LOOP_GUARD_STOP` | Repetition or no-progress guard stopped execution. | Stop and report the last completed step. |
| `EMERGENCY_STOP` | The configured stop key was pressed. | Stop and preserve the current report. |
| `MOTION_PROFILE_NOT_FOUND` | `operator-human` was requested but no profile exists. | Stop and ask the user to run calibration or choose a documented fallback. |
| `MOTION_PROFILE_INVALID` | The configured motion profile could not be parsed or validated. | Stop and regenerate the profile from raw samples. |
| `MOTION_PROFILE_NOT_HUMAN` | The installed default profile is not `source=human`. | Run `motion_calibration_session.ps1` for a real human profile or use an explicit test profile only in tests. |
| `MOTION_PROFILE_SOURCE_REQUIRED` | Calibration or profile loading requires an explicit `source`. | Re-run `motion-calibrate --source human|synthetic|sample`. |
| `MOTION_PROFILE_TEST_ONLY` | A synthetic/sample profile was requested without explicit test authorization. | Add `--allow-synthetic-profile` only for reviewed tests, not real operator use. |
| `MOTION_PROFILE_INSUFFICIENT_SAMPLES` | Calibration had fewer than 12 valid raw samples. | Collect more Motion Lab samples before retrying calibration. |

### Agent Response Template

```text
Result: FAILED
error_code: <CODE>
Meaning: <brief explanation>
Report: <report path>
Artifacts: <screenshot or state paths>
Next step: I will not continue clicking or typing. Please confirm how to proceed.
```

### Recovery Strategy Boundary

1. `run-task` may use only documented Recovery Strategy Engine actions: re-observe, OCR fallback, target-window re-resolution/activation, wait and re-observe, or explicit stop.
2. Do not retry with arbitrary coordinates.
3. Do not click nearby controls to guess intent.
4. Do not switch to another window without user confirmation.
5. Do not read a new directory without user confirmation.
6. Do not retry `SAFETY_POLICY_DENIED` or auto-pick after `LOCATOR_NOT_UNIQUE`.
7. Continue only after the user confirms the next action.

## Visual Failure Stop

1. For UIA, OCR, image/template, and selector location, the Agent must stop on any locator failure.
2. The Agent must not click nearby positions to guess intent.
3. The Agent must not switch from UIA to OCR or image/template matching after failure without user confirmation.
4. The Agent must not broaden window titles or choose another window after failure without user confirmation.
5. The Agent must report `error_code`, locator method, requested target, match count if known, whether input was executed, and the report/artifact path.
6. The Agent should prefer UIA selectors over text selectors, text selectors over image selectors, and image selectors over coordinate selectors.

Reference: `D:\desktopvisual\docs\VISUAL_SAFETY_FREEZE.md`.

## Agent Adapters

Recommended adapter paths:

```text
D:\desktopvisual\adapters\codex\win-desktop-agent
D:\desktopvisual\adapters\claude-code
D:\desktopvisual\adapters\generic-cli
```

The legacy Codex Skill path remains available at `D:\desktopvisual\skill_template\win-desktop-agent`.

All adapters must follow `observe-locate-act-verify`, safety stop rules, no unrestricted desktop control, and no sensitive flows.

## Safety Manifest

For v3.0.5 and later, agents should inspect the machine-readable safety boundary before desktop input:

```powershell
D:\desktopvisual\bin\winagent.exe version
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

`version` includes `data.manifest_loaded`. `safety-report` writes `artifacts\safety\safety_report.md` and `.json`. `policy-check` and `consent-check` are dry-run gates and do not perform input. Stop immediately on `SAFETY_POLICY_DENIED` or any manifest-denied sensitive category.

## Benchmark Evidence

Agents can run benchmark evidence checks when they need reproducible capability evidence:

```powershell
D:\desktopvisual\benchmark_matrix.ps1
D:\desktopvisual\benchmark_selftest.ps1
```

Read `artifacts\benchmark\benchmark_summary.json` and `benchmark_report.md`. Treat SKIPPED as an environment condition, not as PASS.

## Permission Boundary

1. Agent must ask the user before using a new window.
2. Agent must ask the user before reading a new directory.
3. Agent must ask the user before requesting new permissions.
4. Agent must not control unauthorized windows.
5. Agent must not perform no-title full-screen clicks.

## Release-Freeze Boundary

v3.0.1 is a Windows Computer Use MVP, not official Codex built-in Computer Use. It has CLI, Case v2, dogfood, explicit local service mode, task orchestration, and local Operator Motion Profile support, but no MCP service, automatic Skill installation, unrestricted desktop control, protected-desktop/admin-window control, detection bypass, or autonomous decision-making.

## Example Agent Task

Please use DesktopVisual to test Agent Test Window and summarize the report.

Expected high-level execution:

```powershell
D:\desktopvisual\bin\winagent.exe version
D:\desktopvisual\bin\winagent.exe find --title "Agent Test Window"
D:\desktopvisual\bin\winagent.exe run-task --file D:\desktopvisual\tasks\testwindow_basic.task.json --report D:\desktopvisual\artifacts\mvp_testwindow_report.md
Get-Content D:\desktopvisual\artifacts\mvp_testwindow_report.md
```
