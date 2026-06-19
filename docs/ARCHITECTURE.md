# Public Architecture Summary

DesktopVisual is a Windows-only local runtime distributed as a public binary.

High-level components:

- CLI command dispatcher in `winagent.exe`.
- Target window discovery and target lock.
- Global screenshot and coordinate mapping.
- Foreground preparation and preempt/cache support.
- Real mouse and keyboard input primitives.
- Structured text input policy.
- Safety policy and safety manifest checks.
- JSON command envelopes and Markdown/report-oriented diagnostics.

The public distribution intentionally omits source code, build project files, debug symbols, internal artifacts, and development logs.