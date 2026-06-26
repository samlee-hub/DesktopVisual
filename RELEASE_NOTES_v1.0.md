# DesktopVisual v1.0.0 Release Notes

## Project Positioning

DesktopVisual v1.0.0 is the first Windows Agent Desktop Runtime release. It is designed for AI agents that need a local, auditable, user-authorized way to interact with specified Windows desktop windows during development and GUI verification.

The runtime is intentionally scoped. It is not a universal desktop controller, not a full computer-use platform, and not a replacement for user review. It provides a stable local CLI, reproducible cases, reports, and safety boundaries for authorized workflows.

## Implemented Capabilities

1. Visible top-level window listing and unique title matching.
2. Window screenshots saved as BMP files.
3. Real mouse clicks using target-window client coordinates.
4. Keyboard key presses and Unicode text input.
5. Observable `human` movement and typing modes.
6. Case execution with stop-on-first-failure behavior.
7. Stable JSON command envelopes for the supported command set.
8. Stable error codes, audit logs, and Markdown case reports.
9. Approved text-file reads for test state verification.
10. Windows UI Automation tree, find, click, and type support.
11. OCR command interfaces that currently return `OCR_UNAVAILABLE` in this build.
12. BMP image template find and click support for authorized GUI tests.
13. Project-local safety policy for allowed titles, allowed processes, case limits, and emergency stop.
14. Project-local Codex Skill template for reviewed manual installation.
15. Release packaging, release verification, and RC acceptance checks.

## Installation And Build

DesktopVisual v1.0.0 uses Windows native APIs and the Visual Studio C++ toolchain. No third-party dependency download is required.

Build the runtime and test window:

```powershell
D:\desktopvisual\build.ps1
```

The build outputs:

```text
D:\desktopvisual\bin\winagent.exe
D:\testrepo\testwindow\bin\TestWindow.exe
```

## Quick Start

Run the core selftest:

```powershell
D:\desktopvisual\selftest.ps1
```

Run the basic and visible demos:

```powershell
D:\desktopvisual\run_demo.ps1
D:\desktopvisual\run_demo.ps1 -Visible
```

Run the full acceptance check:

```powershell
D:\desktopvisual\rc_check.ps1
```

Create and verify a release package:

```powershell
D:\desktopvisual\release.ps1
D:\desktopvisual\verify_release.ps1
```

## Skill Usage

The project includes a local Skill template at:

```text
D:\desktopvisual\skill_template\win-desktop-agent
```

Users should review the template and copy it manually into their Codex skills directory. The project does not auto-install the Skill and does not write to user-home skill directories.

Recommended Skill flow:

1. Check `D:\desktopvisual\bin\winagent.exe`.
2. Run `winagent.exe version`.
3. Prefer `run-case` over free-form clicks.
4. Read the generated Markdown report.
5. Summarize success or explain the `error_code`.
6. Stop on failure until the user confirms the next action.

## Safety Boundary

DesktopVisual is for user-authorized development and test windows. Input actions require a target title that resolves to exactly one visible top-level window, and input actions must pass the project-local safety policy in:

```text
D:\desktopvisual\config\safety.conf
```

Visual locators must stop on zero matches, multiple matches, unavailable locator engines, or any non-empty `error_code`. They must not guess nearby clicks, broaden the target title, switch locator methods, or continue input after failure without user confirmation.

## Known Limitations

1. Administrator windows, elevated processes, protected desktops, and protected applications are not supported.
2. OCR command surfaces exist, but OCR is unavailable in this build and returns `OCR_UNAVAILABLE`.
3. Image matching supports small uncompressed 24-bit and 32-bit BMP templates only.
4. Complex automatic recovery is not implemented.
5. There is no MCP server, HTTP service, autonomous planning layer, or automatic Skill installation.
6. Real application titles, DPI, focus behavior, and localization can affect demos.

## Not Suitable For

1. Unauthorized control of third-party software.
2. Security-control bypass or credential extraction.
3. Protected desktop or elevated window control.
4. Unauthorized game or platform workflow automation.
5. Unauthorized classroom, workplace, or personal-account automation.
6. Unreviewed access to private project paths.

## Roadmap

1. Preserve the frozen CLI protocol, JSON envelopes, audit log shape, and case report format.
2. Keep demos, selftests, release verification, and Skill template checks passing before future changes.
3. Treat OCR availability, service wrappers, and richer recovery as separate post-v1.0 design efforts.
4. Keep Skill installation manual and user-reviewed unless a future release explicitly designs a safer installation flow.
