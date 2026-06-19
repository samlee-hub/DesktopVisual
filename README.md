# DesktopVisual 1.0.0

DesktopVisual is a Windows visible-first desktop automation runtime for authorized local GUI workflows. This repository is the closed-source public distribution. Source code is not included in this public distribution.

This public repository provides the Windows binary, public-safe documentation, safety notes, command protocol, a Codex skill, checksums, and usage examples.

Version lineage: developer internal v6.12.1 -> DesktopVisual 1.0.0.

## What is included

- `bin/winagent.exe`: unsigned Windows binary.
- `COMMAND_PROTOCOL.md`: public-safe command protocol summary.
- `AGENTS.md`: public-safe agent usage rules.
- `skills/desktopvisual-visible-ui-first/SKILL.md`: visible-first Codex skill.
- `docs/`: public-safe architecture, safety, installation, usage, roadmap, and limitations.
- `checksums/SHA256SUMS.txt`: SHA-256 checksums.
- `manifest/desktopvisual-public-1.0.0.json`: public distribution manifest.
- `scripts/smoke-test.ps1`: local public package smoke test.

## Unsigned binary notice

`winagent.exe` is not code-signed in DesktopVisual 1.0.0. Windows SmartScreen or antivirus tools may require manual review before first run. Only run the binary if you trust this distribution and have verified the checksum.

## Installation

1. Clone or download this repository.
2. Open PowerShell in the repository root.
3. Verify checksums:

```powershell
Get-FileHash -Algorithm SHA256 .\bin\winagent.exe
Get-Content .\checksums\SHA256SUMS.txt
```

4. Run the smoke test:

```powershell
.\scripts\smoke-test.ps1
```

## Quick start

```powershell
.\bin\winagent.exe version
.\bin\winagent.exe help
.\bin\winagent.exe safety-report
```

For GUI input commands, provide an explicit target window title and operate only on windows you are authorized to control.

## Safety boundaries

DesktopVisual 1.0.0 uses visible-first, target-window-locked, user-level Windows input. It is intended for authorized local desktop workflows. It does not bypass UAC, protected desktops, credentials, CAPTCHA, anti-cheat, proctoring, banking, payment, security controls, platform rate limits, or access controls.

Accepted visible input paths use real mouse and keyboard events. Clipboard and backend writes are not part of the accepted visible input path.

## Limitations

- DesktopVisual 1.0.0 is not a universal autonomous IDE developer.
- Visual Studio C++ multi-file workflow is not included in 1.0.0.
- Complex arbitrary app and web automation remains experimental.
- Complex tasks require concrete goals, allowed targets, and constraints.
- Users remain responsible for reviewing outputs and authorizing actions.