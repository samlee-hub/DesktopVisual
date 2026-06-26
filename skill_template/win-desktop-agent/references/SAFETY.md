# Safety

Current version: `DesktopVisual 1.0.2`.

This reference describes the developer-tree safety and permission contract used by the Skill. It does not redesign the future public/formal release policy.

## v1.0.2 Developer Safety Boundary

DesktopVisual v1.0.2 keeps local safety policy at:

```text
D:\desktopvisual\config\safety.conf
```

Current developer-tree configuration:

```text
allowed_titles=
allowed_processes=
allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;${PROJECT_ROOT}\cases;${PROJECT_ROOT}\tasks;D:\testrepo;D:\testrepo\testwindow
allowed_write_roots=${PROJECT_ROOT}\artifacts;${PROJECT_ROOT}\config;D:\testrepo;D:\testrepo\testwindow
max_steps=100
max_duration_ms=120000
emergency_stop_key=F12
allow_absolute_screen_click=true
```

`allow_absolute_screen_click=true` is part of the current developer tree and must not be tightened in v1.0.2. It does not authorize active-protection bypass, protected desktop control, credential handling, or hidden backend automation. DesktopVisual still requires visible-first evidence and policy checks for task success.

## Safety Manifest

DesktopVisual uses:

```text
D:\desktopvisual\config\safety_manifest.json
```

The manifest must keep `default_permission_mode` as `DEVELOPER_CAPABILITY_DISCOVERY` for this developer tree. `DEVELOPER_CAPABILITY_DISCOVERY` and `DEVELOPER_FULL_RUNTIME` keep these capabilities enabled:

- `third_party_apps`
- `external_web`
- `communication`
- `content_decision`
- `cross_window`
- `global_desktop`
- `browser`
- `explorer`
- `local_file_open`
- `localhost`

Use:

```powershell
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

`policy-check` and `consent-check` are dry-run gates and do not perform input.

## Developer Permission Contract

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions.

ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

DesktopVisual v1.1.0 aligns `PUBLIC_DEFAULT` for ordinary visible desktop operations while preserving STOP boundaries for real active protection, security interception, proctoring/lockdown, protected desktop/UAC, and anti-cheat.

## Active Protection STOP

Active protection or security interception is STOP, not fallback.

Stop on real active protection or interception, including:

- CAPTCHA
- human verification
- bot challenge
- automation detected
- script detected
- security verification
- `CredentialUIBroker`
- `Consent.exe`
- UAC/protected desktop
- proctoring
- lockdown browser
- secure exam browser
- ACE
- EasyAntiCheat
- Vanguard
- BattlEye
- other anti-cheat or anti-automation interception

Do not solve, bypass, hide from, disable, hook, patch, or otherwise evade these mechanisms.

## Visible-First Safety

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first. Start Menu visible search is a fallback, not the first choice. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.

Layer 1: visible UI path.
Layer 2: visible keyboard fallback.
Layer 3: backend fallback.

Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not disguise clipboard/backend write as visible input success.

## Window And Process Handling

Input actions should specify an explicit target window title when operating inside an app. The resolved target must be visible and unique unless the command contract explicitly operates on the global desktop surface.

Missing, ambiguous, or changed targets must be reported. Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.

## File Path Allowlist

`read-file`, case `read_file`, and case `assert_file_contains` normalize paths before reading. The normalized path must be under one of the configured read roots. Paths containing `..` traversal are denied before file access.

Writes must stay under configured write roots unless the user explicitly approves another exact path for the current task.

## Focus Verification

Target-window input paths must verify foreground focus before sending input. Failure returns a command error such as `WINDOW_FOCUS_FAILED` and cannot be reported as PASS.

## Operator Motion Profile Boundary

Operator Motion Profile is local movement personalization only. It is not a detection-bypass, anti-cheat, human-verification, or risk-control bypass feature.

`operator-human` preserves SafetyPolicy, unique-title matching when applicable, focus verification, F12 stop, exact final coordinate, and audit requirements. Synthetic/sample profiles require explicit test authorization and must not be represented as human operator profiles.

## VLM Status

v1.0.2 does not enable a real VLM provider. If Runtime reports VLM unavailable, mock-only, or not configured, the agent must not invent VLM results. Self-drawn or custom UI must continue through UIA, OCR, image/template, and visible fallback paths. Real VLM automatic triggering is a v1.0.3 target.

## Stopping on Failure

command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS. If final state appears successful but evidence shows a disallowed fallback, report failure.

Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry.
