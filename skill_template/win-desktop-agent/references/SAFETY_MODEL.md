# DesktopVisual Safety Model

Current version: `DesktopVisual 1.0.2`.

DesktopVisual is a local authorized Windows visible-first runtime. It is not unrestricted desktop control and not a background script executor. The developer tree is broad for capability discovery, but active protection and security interception remain final stop boundaries.

## Authorization Model

DesktopVisual requires a visible, auditable path for input actions. Most app-internal work should resolve one visible target window before input. Global desktop operations are allowed only through explicit visible command contracts such as `visible-app-launch`, visible desktop icon locate/double-click, visible show desktop, and visible window switching.

Authorization is checked through:

- `config\safety.conf`
- `config\safety_manifest.json`
- visible-first operation policy evidence
- target/window/focus verification where applicable

The manifest cannot turn active protection into an allowed target.

## Developer Permission Modes

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions. `default_permission_mode` must remain `DEVELOPER_CAPABILITY_DISCOVERY` in v1.0.2.

The developer modes keep ordinary capabilities enabled for third-party apps, external web, communication, content decision, cross-window work, global desktop, browser, Explorer, local file open, and localhost.

ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

DesktopVisual v1.1.0 aligns `PUBLIC_DEFAULT` for ordinary visible desktop operations while preserving STOP boundaries for real active protection, security interception, proctoring/lockdown, protected desktop/UAC, and anti-cheat.

## Visible-First Launch Model

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first.

The required order is desktop surface -> observe -> visible icon/shortcut locate -> real mouse double-click -> target window verification when title/process is supplied.

Start Menu visible search is a fallback, not the first choice. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.

If the first desktop locate or double-click fails, the launch path needs two bounded desktop visible attempts or strict surface-impossible evidence before fallback.

Required launch evidence includes `runtime_visible_first_launch`, `launch_strategy`, `desktop_surface_attempted`, `desktop_icon_path_used`, `start_menu_fallback_attempted`, `backend_launch_used`, `bounded_recovery_attempted`, and `target_window_verified`.

## Fallback Model

Layer 1: visible UI path.
Layer 2: visible keyboard fallback.
Layer 3: backend fallback.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not disguise clipboard/backend write as visible input success.

Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

Two bounded visible attempts must include pre-action checkpoint, observe / locate / action, failure reason, bounded recovery, re-observe / re-locate, and second visible action.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

## Commands

Use these commands before automation or during adapter startup:

```powershell
D:\desktopvisual\bin\winagent.exe version
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

`safety-report` writes:

- `artifacts\safety\safety_report.md`
- `artifacts\safety\safety_report.json`

`policy-check` performs a dry-run allow/deny decision. It does not click, type, focus, read UI, or execute the action. `consent-check` verifies target visibility/uniqueness and immutable safety boundaries. It does not pop up UI or send input.

## Active Protection And Protected Desktop Limits

Active protection or security interception is STOP, not fallback.

DesktopVisual must stop on CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, protected desktop, UAC, `CredentialUIBroker`, `Consent.exe`, proctoring, lockdown browser, secure exam browser, ACE, EasyAntiCheat, Vanguard, BattlEye, and similar anti-cheat or anti-automation interception.

DesktopVisual does not solve, bypass, hide from, disable, hook, patch, or otherwise evade these mechanisms.

## VLM Status

v1.0.2 does not enable a real VLM provider. If Runtime reports VLM unavailable, mock-only, or not configured, the agent must not invent VLM results. Self-drawn or custom UI must continue through UIA, OCR, image/template, and visible fallback paths. Real VLM automatic triggering is a v1.0.3 target.

## Agent Stop Conditions

Agents must report failure or BLOCKED on command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation. These cannot be reported as PASS.

If final state appears successful but evidence shows a disallowed fallback, report failure. Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry.

Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.
