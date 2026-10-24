---
name: desktopvisual
description: Use DesktopVisual 1.2.0 local Windows desktop runtime. Developer root is D:\desktopvisual; normal local-use entrypoint is D:\desktop_release\desktopvisual.ps1.
---

# DesktopVisual

DesktopVisual is a local Windows desktop runtime, not a built-in tool.

Current version: v1.2.0.
Current launch authority: `docs\LAUNCH_CONTRACT.md`.

Developer project path:

D:\desktopvisual

Normal local-use / daily runtime path:

D:\desktop_release

When this developer source is used directly for development, build, or selftest work, the wrapper is:

D:\desktopvisual\desktopvisual.ps1

For normal local use, demo, and Codex default DesktopVisual runtime, use:

D:\desktop_release\desktopvisual.ps1

Daily winagent path:

D:\desktop_release\bin\winagent.exe

Use `D:\desktopvisual` only for development tasks, source edits, build/selftest, or version evolution. Do not treat `D:\desktop_release` as a development main tree.

For app, browser, software, `.lnk`, `.url`, or desktop shortcut startup, follow the Launch Contract: desktop icon double-click first, keyboard/Start Menu second only with evidence, backend third only with Layer 1 and Layer 2 failure evidence. Visible/action `--help` and bare `--dry-run` discovery must be non-executing.

Public release / public restricted release / public-dist are not created by this skill by default.

Do not use v1.1.4 Fast Use Manifest, high-level workflow, student-grade preset, or initial-state surface-decision logic.
