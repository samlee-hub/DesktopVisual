# App Profiles

Current version: `v4.7.0`.

DesktopVisual App Profiles are application adapters. They help the runtime recognize a local app or local fixture, rank common locators, define useful OCR ROIs, and choose conservative visual/recovery strategies.

Profiles do not grant permissions. Permission Profile and Safety Manifest decisions remain binding, and profile candidates still pass through the semantic/risk/action gate before any input command can execute.

## Files

Built-in profiles live under:

```text
D:\desktopvisual\profiles
```

The schema reference lives at:

```text
D:\desktopvisual\profiles\schema\app_profile.schema.json
```

v4.5.0 includes safe local profiles for TestWindow, Notepad, Explorer, Calculator, local browser pages, a local problem fixture, and a local mail mock fixture. These are not real-account profiles.

v4.7.0 keeps the App Profile schema stable for the v4 release candidate. Profiles remain application adapters and release evidence, not permission grants.

## Required Fields

Each profile must include:

- `profile_name`
- `app_kind`
- `process_match`
- `title_match`
- `window_class_match`
- `allowed_window_scope`
- `common_locators`
- `roi_definitions`
- `visual_strategy`
- `ocr_strategy`
- `recovery_strategy`
- `safety_overrides`
- `task_templates`
- `confirmation_nodes`
- `version`
- `notes`

`common_locators` entries require at least `name` and `selector`. Optional `semantic_status` and `risk_status` default to `resolved` and `normal` when omitted by the runtime loader.

## Commands

Report loaded and invalid profiles:

```powershell
D:\desktopvisual\bin\winagent.exe profile-report
```

Validate one profile path without crashing the runtime:

```powershell
D:\desktopvisual\bin\winagent.exe profile-report --path D:\desktopvisual\profiles\testwindow.profile.json
```

Use a profile locator through the existing Hybrid Locator:

```powershell
D:\desktopvisual\bin\winagent.exe locate --title "Agent Test Window" --profile testwindow --profile-locator click_button
```

The returned `profile_candidate` is metadata. It records `source="app_profile"` and `action_gate="requires_runtime_safety_policy"`.

## Safety Rules

- App Profiles are not Permission Profiles.
- `safety_overrides` is metadata only and cannot loosen `config\safety_manifest.json` or `config\safety.conf`.
- Public release builds must still be prepared separately under `D:\desktopvisual-release` with restricted exam, assessment, hiring-test, certification, proctored, and rated-contest permissions.
- Local problem and mail mock profiles are fixtures only. They are not Gmail, Outlook, real account, or public assessment profiles.
- Visual-only unresolved candidates remain blocked with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`.
- Captcha, anti-cheat, protected desktop, credential, payment, and high-risk authentication surfaces remain stop conditions.

## Adding A Profile

1. Add a `*.profile.json` file under `profiles`.
2. Keep selectors semantic where possible: prefer UIA name/type, OCR text anchors, or profile context over fixed coordinates.
3. Define ROIs as relative rectangles so they survive window movement and DPI differences.
4. Set `can_relax_safety_manifest` to `false`.
5. Add confirmation nodes for destructive, send, submit, overwrite, or external-navigation actions.
6. Run:

```powershell
D:\desktopvisual\build.ps1
D:\desktopvisual\app_profile_selftest.ps1
D:\desktopvisual\bin\winagent.exe profile-report
```

A malformed profile should appear in `invalid_count` and must not crash the runtime.
