# Agent Usage Guide

Current version: `DesktopVisual 1.0.3`.

DesktopVisual is a Windows visible-first desktop runtime, not a background script executor. It can be called by Codex, Claude Code, generic CLI agents, and human scripts. Adapter-specific instructions live under `adapters\`; this guide describes the neutral Runtime contract.

## Core Rule

Agents should prioritize reviewed `task.json`, visible command contracts, and Case v2 files through DesktopVisual instead of issuing free-form clicks. The agent's goal is not the fastest path; it must prefer visible, auditable, human-like desktop operations. Every input action must have observe / locate / act / verify evidence, or an equivalent task/visible command evidence chain.

A task can fail because the path was illegal even when the final application state appears correct.

## Required Loop

1. Run `D:\desktopvisual\bin\winagent.exe version`.
2. Confirm `data.project_root` and `data.manifest_loaded`.
3. Run `safety-report` when the task involves input.
4. For app, URL, local shortcut, `.lnk`, `.url`, or webpage shortcut launches, use `visible-app-launch` before any backend launch path.
5. For an already-open target, run `observe --title "<target>"` and confirm exactly one visible target.
6. Run `locate`, `act`, and post-action `observe`/verification, or run a reviewed `run-task` / `run-case`.
7. Read the generated Markdown report before summarizing the result.

Recommended command order:

```text
version
safety-report
visible-app-launch or observe
locate
act or run-task/run-case
observe
read report
summarize
```

If `winagent serve` is already running, service calls may be used for `/version`, `/safety-report`, `/observe`, `/locate`, `/act`, `/run-case`, `/run-task`, and `/report`. Do not start the service automatically unless the user explicitly asked for service mode. If service mode is unavailable, use the CLI.

## Visible-App-Launch

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first.

Desktop-first means reveal desktop -> observe desktop -> locate visible icon/shortcut through UIA/OCR/visible evidence -> real mouse double-click -> verify target window when `target-title` or `process` is supplied.

Start Menu visible search is a fallback, not the first choice. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.

If the first desktop locate or double-click fails, do not switch directly to Start Menu. The launch path requires two bounded desktop visible attempts or strict surface-impossible evidence.

Final reports should include:

- `runtime_visible_first_launch`
- `launch_strategy`
- `desktop_surface_attempted`
- `desktop_icon_path_used`
- `start_menu_fallback_attempted`
- `backend_launch_used`
- `bounded_recovery_attempted`
- `target_window_verified`

## Task Template Priority

Before writing low-level task steps, check `D:\desktopvisual\tasks\templates` for a matching template. Prefer templates for common workflows such as opening or confirming an authorized app window, focusing a window, filling a form, clicking a button, waiting for text/window state, copying selected text, saving a file, opening a local HTML page, and running a local test page.

Template steps are still reviewed task.json. They expand into ordinary TaskRunner steps and do not grant new permissions. Agents must provide explicit parameters, keep the target window authorized, and read the generated report section `## Templates` after execution. If no template fits, use selector-based `locate`/`act` steps before considering coordinates.

## Action Priority

1. Prefer a bundled task template when it matches the workflow.
2. Prefer `locate`/`act` with selectors for new custom task steps.
3. Locator priority: `uia` selector, then OCR-backed `text` selector when OCR is available, then `image` selector, then `coord` selector.
4. Use `uia-find`, `uia-click`, `uia-type`, `click-image`, and `click-text` as compatibility interfaces when needed.
5. Use visible keyboard fallback only after bounded visible evidence allows it.
6. Use backend fallback only after visible path failure plus keyboard fallback failure.
7. Use coordinate mouse actions last, only against an authorized target window and stable coordinates derived from visible evidence or a reviewed case/task.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not disguise clipboard/backend write as visible input success.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

## Three-Layer Fallback Contract

Layer 1: visible UI path. Use UIA/OCR/visible icon/template evidence, real mouse/keyboard, target-window lock, coordinate mapping, and post-action verification.

Layer 2: visible keyboard fallback. Use shortcuts, Start Menu visible search, address-bar visible navigation, or similar visible keyboard-driven paths only after Layer 1 is proven unavailable.

Layer 3: backend fallback. Use direct launch, backend browser navigation, file writes, clipboard/backend injection, script execution, or similar backend paths only after Layer 1 and Layer 2 fail. backend fallback is not the default path.

Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

Each bounded visible attempt must include pre-action checkpoint, observe / locate / action, failure reason, bounded recovery, re-observe / re-locate, and second visible action.

Active protection or security interception is STOP, not fallback.

## Visual Failure Handling

Locator failure is not permission to guess. The agent must not click nearby positions, broaden the target title, switch windows, silently change locator class, or move to a keyboard/backend layer without the fallback evidence above.

When a locator or action fails, report `error_code`, locator method, requested target, match count if known, whether input was executed, and the report/artifact path. Bounded recovery may re-observe and retry the same visible surface only when a task contract or visible command allows it.

## Developer Permission Boundary

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions.

ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

Stop on real active protection or security interception, including CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, protected desktop, proctoring, lockdown browser, secure exam browser, anti-cheat, `CredentialUIBroker`, and `Consent.exe`.

DesktopVisual v1.1.0 aligns `PUBLIC_DEFAULT` for ordinary visible desktop operations while preserving STOP boundaries for real active protection, security interception, proctoring/lockdown, protected desktop/UAC, and anti-cheat.

## VLM Assist

v1.0.3 supports provider-gated VLM assist. Probe once per large task or session with `vlm-capability-probe`; reuse the cache and do not probe or call VLM on every step.

If `VLM_AVAILABLE`, Runtime may use VLM only after frontend perception/locate failure or unclear keyboard-fallback visual state. VLM returns visual understanding and candidate bbox/point evidence only. Runtime still validates candidates, maps coordinates, performs mouse/keyboard actions, verifies the result, and enforces fallback discipline.

If `VLM_UNAVAILABLE`, continue Runtime-only visible paths and normal fallback policy. VLM must not directly operate the computer, decide backend fallback, participate after backend fallback starts, or bypass active protection. Active protection remains STOP.

## Failure Handling

1. Agent must inspect command JSON and case/task report `error_code`.
2. command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS.
3. If final state appears successful but evidence shows a disallowed fallback, report failure.
4. Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry.
5. Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.

### Agent Response Template

```text
Result: FAILED or BLOCKED
error_code: <CODE>
Meaning: <brief explanation>
Input executed: <yes/no/unknown>
Report: <report path>
Artifacts: <screenshot or state paths>
Next minimal repair entry: <smallest safe next check or fix>
```

## Safety Manifest

Agents should inspect the machine-readable safety boundary before desktop input:

```powershell
D:\desktopvisual\bin\winagent.exe version
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

`version` includes `data.manifest_loaded`. `safety-report` writes `artifacts\safety\safety_report.md` and `.json`. `policy-check` and `consent-check` are dry-run gates and do not perform input. Stop immediately on active protection, protected desktop/security interception, or any manifest-denied immutable boundary.

## Benchmark Evidence

Agents can run benchmark evidence checks when they need reproducible capability evidence:

```powershell
D:\desktopvisual\benchmark_matrix.ps1
D:\desktopvisual\benchmark_selftest.ps1
```

Read `artifacts\benchmark\benchmark_summary.json` and `benchmark_report.md`. Treat SKIPPED as an environment condition, not as PASS.
