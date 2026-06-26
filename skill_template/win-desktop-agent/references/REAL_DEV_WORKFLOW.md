# Real Dev Workflow

Current version: `DesktopVisual 1.0.2`.

DesktopVisual keeps configurable real development workflow templates, but it does not access real project paths by default. v1.0.2 does not add complex IDE automation. It only hardens how agents must enter visible runtime workflows.

## Default Behavior

Running without parameters:

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1
```

creates:

```text
D:\desktopvisual\artifacts\real_dev_workflow_report.md
```

with `Result: SKIPPED`. No real project path is accessed.

## Visible Launch Rule

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first.

For developer IDEs, browsers, Explorer, local HTML, localhost, mail pages, communication pages, and coding practice fixtures, the agent must start through visible desktop evidence first when a launch is needed. Start Menu visible search is a fallback, not the first choice. backend fallback is not the default path.

If the first desktop locate or double-click fails, the workflow requires two bounded desktop visible attempts or strict surface-impossible evidence before Start Menu visible search or later fallback.

## Visual Studio C++ Complex IDE Rule

v1.0.4 validates Visual Studio C++ work through step-by-step visible IDE execution. Visual Studio must open through visible desktop icon double-click and must close successful project/file/stage boundaries through the visible top-right X.

`SingleTestProject` is created once as an Empty Project with the VS default location/settings, then reused through visible VS UI. Source and header files are added through Solution Explorer Add/New Item or visible `Ctrl+Shift+A`; backend file creation, source writes, and `.vcxproj` edits are not valid workflow substitutes.

Build and run must use VS UI or visible IDE shortcuts, and output must be verified from visible console/output evidence.

## Configure A Real Window

Provide a user-approved window title:

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1 -TargetTitle "Approved Window Title"
```

The title must resolve to exactly one visible top-level window.

## Configure A Case

Start from:

```text
D:\desktopvisual\cases\real_dev_workflow.template.case
```

Copy it to another file under `D:\desktopvisual\cases`, replace the placeholders, then pass it with `-CaseFile`.

The template supports screenshots, UIA actions, image actions, key presses, waits, and optional state-file reads. Do not point `read_file` or `assert_file_contains` at a real project path until the user approves that exact path.

## Configure A State File

Use `-StateFile` only after approval:

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1 `
  -TargetTitle "Approved Window Title" `
  -StateFile "D:\approved\path\state.txt" `
  -CaseFile "D:\desktopvisual\cases\approved_workflow.case"
```

By default, only these roots are already authorized:

```text
D:\desktopvisual
D:\testrepo\testwindow
```

Any other project path must be approved by the user first. If an unapproved path is passed, the script writes a SKIPPED report and does not read it.

## Fallback Discipline

Layer 1: visible UI path.
Layer 2: visible keyboard fallback.
Layer 3: backend fallback.

Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not disguise clipboard/backend write as visible input success.

## Developer Permission Boundary

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions.

ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

Active protection or security interception is STOP, not fallback. Stop on CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, protected desktop, proctoring, lockdown browser, secure exam browser, anti-cheat, `CredentialUIBroker`, `Consent.exe`, UAC/protected desktop, ACE, EasyAntiCheat, Vanguard, BattlEye, or similar interception.

## Safety Boundary

1. Do not modify real project code unless the user explicitly asked for that exact edit.
2. Do not delete real project files.
3. Do not access Client, Server, UE, game, or other project paths without explicit approval.
4. Do not use this for unauthorized game automation, platform risk-control bypass, active protection bypass, or other unapproved workflows.
5. Only interact with a user-approved target window.
6. command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS.

## VLM Assist

v1.0.3 supports provider-gated VLM assist. Probe once per large task or session with `vlm-capability-probe`, reuse the cache, and do not call VLM on every step. Use VLM only when UIA, OCR, image/template, icon, or other frontend perception/locate evidence is unreliable, or when keyboard fallback leaves the visual state unclear.

VLM supplies visual understanding and candidate bbox/point evidence only. Runtime must validate the candidate, bind it to screenshot/frame/provider/session/raw/parsed evidence, map coordinates, execute any second visible attempt itself, and verify afterward. If `VLM_UNAVAILABLE`, continue Runtime-only visible paths. Do not use VLM after backend fallback starts or to bypass active protection.

## Real Application Validation Strategy

Use `D:\desktopvisual\dogfood_matrix.ps1` when you need evidence that DesktopVisual can operate real Windows applications. A PASS means the app-specific workflow completed inside the bounded dogfood sandbox. A SKIPPED result means the app, a clean target window, or a required capability is unavailable on this system. A FAIL means the script ran and did not achieve its expected result; the generated report must include the reason.

Dogfood scripts must not close pre-existing user windows. They should skip if Notepad, Calculator, Edge, or VS Code already has a user session open. Explorer dogfood operates only inside `D:\desktopvisual\artifacts\dogfood\explorer`.
