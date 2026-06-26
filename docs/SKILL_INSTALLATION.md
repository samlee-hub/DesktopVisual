# Skill Installation

Current version: `DesktopVisual 1.0.3`.

The recommended Codex adapter path is:

```text
D:\desktopvisual\adapters\codex\win-desktop-agent
```

The project-local legacy Skill template remains available for compatibility:

```text
D:\desktopvisual\skill_template\win-desktop-agent
```

Install or copy it into the agent's Skill directory according to the host agent's normal Skill installation process. The template is intentionally self-contained and includes:

- `SKILL.md`
- helper scripts for observe, locate, act, Case v2, dogfood, run-task, and report summaries
- reference copies of command protocol, case format, error codes, safety policy, safety model, visible-first contract, visual safety, usage guide, real dev workflow, and known limitations

## v1.0.3 Usage Contract

Installed Skills must treat DesktopVisual as a Windows visible-first desktop runtime, not a background script executor.

Use `visible-app-launch` for app, URL, local shortcut, `.lnk`, `.url`, and webpage shortcut launches. Launch is desktop-first: reveal desktop, observe, locate visible icon/shortcut evidence, double-click with real mouse input, and verify the target window when title/process is supplied. Start Menu visible search is a fallback, not the first choice. Backend launch, ShellExecute, direct file open, and background browser navigation are not default paths.

Fallback order is visible UI path, visible keyboard fallback, then backend fallback. Entering fallback requires two bounded visible attempts or strict surface-impossible evidence; backend fallback also requires keyboard fallback failure. Active protection or security interception is STOP, not fallback.

v1.0.3 supports provider-gated VLM assist through the Runtime bridge. Probe VLM capability once per large task/session, reuse the session cache, and continue Runtime-only when VLM is unavailable. VLM is an assistive perception layer only: it may return visual candidates for UIA/OCR/template locate failures, but it does not directly operate the computer, does not participate in backend fallback, does not run every step, and cannot bypass active protection. Runtime must validate every VLM candidate and bind it to screenshot/frame evidence before any visible retry.

After installation or local edits, run:

```powershell
D:\desktopvisual\skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1
D:\desktopvisual\skill_contract_hardening_selftest.ps1 -Root D:\desktopvisual
D:\desktopvisual\skill_adapter_contract_selftest.ps1 -Root D:\desktopvisual
```

Skill scripts resolve the project root through `-Root`, `DESKTOPVISUAL_ROOT`, upward marker discovery, or legacy `D:\desktopvisual` fallback. Service mode is optional and must be started explicitly by the user; Skill scripts fall back to CLI when service mode is not running.

Agent-neutral adapter documentation is in:

```text
D:\desktopvisual\docs\AGENT_ADAPTERS.md
```
