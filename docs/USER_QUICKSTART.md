# User Quickstart

Use the GitHub Release package. Do not install DesktopVisual by cloning the repository or downloading the repository ZIP from GitHub `Code` > `Download ZIP`.

The public repository contains documentation, agent instruction files, and checksum text only. The runnable Windows package is attached to the Release.

## Download

From the RC3 Release page, download both files:

- `DesktopVisual-1.0.0-public-rc3.zip`
- `DesktopVisual-1.0.0-public-rc3.sha256.txt`

Release page:

https://github.com/samlee-hub/DesktopVisual/releases/tag/v1.0.0-public-rc3

## Verify

Run PowerShell in the directory where both files were downloaded:

```powershell
Get-FileHash .\DesktopVisual-1.0.0-public-rc3.zip -Algorithm SHA256
Get-Content .\DesktopVisual-1.0.0-public-rc3.sha256.txt
```

The hash from `Get-FileHash` must match the hash in `DesktopVisual-1.0.0-public-rc3.sha256.txt`. If it does not match, delete the download and do not run it.

## Extract

Extract `DesktopVisual-1.0.0-public-rc3.zip`, then open PowerShell from the extracted package root.

The package root is the directory that contains:

- `bin\winagent.exe`
- `AGENTS.md`
- `skills\desktopvisual-visible-ui-first\SKILL.md`
- `selftest.ps1`
- `serve_help_selftest.ps1`
- `public_release_skill_package_selftest.ps1`
- `public_release_acceptance_gate.ps1`

## Agent Usage

When using an agent or coding assistant with DesktopVisual:

1. Open the package root.
2. Read `AGENTS.md`.
3. Read `skills/desktopvisual-visible-ui-first/SKILL.md`.
4. Use `.\bin\winagent.exe version` to confirm runtime availability.
5. Follow the visible UI first priority.

Visible UI mouse/keyboard operation is first. Keyboard shortcut fallback is second. Backend/non-UI operation is last resort.

## First Run On Windows

The public RC binary is not code signed. Windows or security software may ask for confirmation the first time it runs.

Only continue if:

- The file came from the official GitHub Release.
- The SHA256 value matches the published checksum.
- You trust the source and intended local automation use.

If you do not trust the source, do not run it.

## Basic Checks

Run these commands from the extracted package root:

```powershell
.\bin\winagent.exe version
.\bin\winagent.exe serve --help
.\selftest.ps1
.\serve_help_selftest.ps1
.\f12_force_exit_selftest.ps1
.\public_release_safety_policy_selftest.ps1
.\public_release_exam_integrity_policy_selftest.ps1
.\public_release_allowed_context_selftest.ps1
.\public_release_skill_package_selftest.ps1
.\public_release_acceptance_gate.ps1
```

F12 stops the current task without closing `winagent.exe`.

Use DesktopVisual only for tasks where automation is allowed. Do not use it to violate explicit assessment, exam, interview, contest, platform, or security rules.
