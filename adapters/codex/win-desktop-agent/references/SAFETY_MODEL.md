# DesktopVisual Safety Model

Current version: `v3.0.5`.

DesktopVisual is a local authorized-windows runtime. It is not an unrestricted desktop controller. Every agent, script, adapter, and service request must stay inside an explicit target window, the configured process/title boundary, safe filesystem roots, and the machine-readable Safety Manifest.

## Authorization Model

DesktopVisual requires an explicit target title for window-scoped work. The title must resolve to one visible top-level window before input is sent. Input commands still verify foreground focus before `SendInput`.

Authorization is checked through two layers:

- `config\safety.conf`: hard title/process/root/runtime limits.
- `config\safety_manifest.json`: machine-readable manifest for denied sensitive categories, consent rules, runtime limits, audit settings, and optional additional allowlists.

The manifest cannot loosen `safety.conf`. Empty manifest allowlists mean "do not add more permission"; they do not mean unrestricted access.

## Safety Manifest

The manifest declares:

- `allowed.window_titles`, `allowed.processes`, `allowed.read_roots`, `allowed.write_roots`, `allowed.actions`
- `denied.window_title_patterns`, `denied.processes`, `denied.sensitive_categories`
- `runtime_limits.max_steps`, `max_duration_ms`, `max_recoveries`, `emergency_stop_key`
- `consent.requires_explicit_target`, `requires_visible_foreground_window`, `allow_background_control`, `allow_unrestricted_desktop`
- `audit.write_audit_log`, `write_markdown_report`, `redact_clipboard_text_in_logs`

Default denied categories include password, payment, credential, admin elevation, protected desktop, anti-cheat, and captcha. Default denied process names include `Consent.exe` and `CredentialUIBroker.exe`.

## Commands

Use these commands before automation or during adapter startup:

```powershell
D:\desktopvisual\bin\winagent.exe safety-report
D:\desktopvisual\bin\winagent.exe policy-check --title "Agent Test Window" --process TestWindow.exe --action click
D:\desktopvisual\bin\winagent.exe consent-check --title "Agent Test Window"
```

`safety-report` writes:

- `artifacts\safety\safety_report.md`
- `artifacts\safety\safety_report.json`

`policy-check` performs a dry-run allow/deny decision. It does not click, type, focus, read OCR, or inspect the target UI. `consent-check` verifies the requested title is explicit, unique, visible, and not denied by manifest rules. It does not pop up UI or send input.

## Run-Task Integration

`run-task` performs an internal startup policy check. It stops immediately with `SAFETY_POLICY_DENIED` when:

- the task requests `allow_unrestricted_desktop`
- the target title or process matches a denied sensitive rule
- the target is outside `safety.conf`
- manifest allowlists are explicitly configured and the target/action is outside them

Task reports include a `Safety Manifest` section and the initial policy check result.

## Foreground And Protected Desktop Limits

DesktopVisual does not support background control. Input is sent only after the target window is focused and `GetForegroundWindow()` matches the target HWND.

DesktopVisual does not control administrator windows, UAC prompts, protected desktops, elevated processes, anti-cheat protected windows, credential dialogs, payment flows, captcha flows, or security-sensitive applications. These are denied or unsupported because the runtime is for authorized local GUI testing, not privilege bypass.

## Emergency Stop

The default emergency stop key is `F12`. Human cursor movement, operator-human cursor movement, human typing, and motion recording check it during execution. If triggered, the action stops and returns `EMERGENCY_STOP` or `EMERGENCY_STOPPED`.

## Agent Stop Conditions

Agents must stop on:

- `SAFETY_POLICY_DENIED`
- `WINDOW_NOT_FOUND`
- `WINDOW_NOT_UNIQUE`
- `LOCATOR_NOT_FOUND`
- `LOCATOR_NOT_UNIQUE`
- `WINDOW_FOCUS_FAILED`
- `EMERGENCY_STOP`
- any `MOTION_PROFILE_*` error
- report failure or failed expectation

Agents must not broaden window titles, guess coordinates, switch to another window, automate sensitive flows, or request unrestricted desktop control after a stop condition.
