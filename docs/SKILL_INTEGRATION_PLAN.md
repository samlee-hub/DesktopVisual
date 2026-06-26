# Skill Integration Plan

Current version: `DesktopVisual 1.0.3.1`.

## Completed State

DesktopVisual now includes a project-local source-of-truth Skill template and a Codex adapter Skill for the v1.0.3.1 visible-first contract with provider-gated VLM assist and legacy mock VLM quarantine:

```text
observe -> locate -> act -> observe -> verify -> report
```

For complex GUI tasks, the preferred flow is:

```text
version -> observe -> generate reviewed task.json -> run-task -> read MVP report -> summarize
```

For app, URL, local shortcut, `.lnk`, `.url`, and webpage shortcut launches, the required entry is:

```text
version -> safety-report -> visible-app-launch desktop-first -> verify target window -> report evidence
```

Start Menu visible search is a fallback, not the first choice. Backend launch, ShellExecute, direct file open, and background browser navigation are not default paths.

Fallback order is:

```text
visible UI path -> visible keyboard fallback -> backend fallback
```

Entering fallback requires two bounded visible attempts or strict surface-impossible evidence. Backend fallback also requires keyboard fallback failure and a non-convenience reason.

v1.0.3.1 keeps the v1.0.3+ real VLM assist contract as the normal VLM path for agents:

- Probe VLM capability once per large task/session with `vlm-capability-probe`.
- Reuse the session cache when VLM is needed; do not probe every step.
- If VLM is `VLM_UNAVAILABLE` or `VLM_UNKNOWN`, continue Runtime-only and do not fabricate candidates.
- Call `vlm-assist-locate` only for eligible UIA/OCR/template/perception/location ambiguity or unclear keyboard fallback visual state.
- Validate candidates with `vlm-candidate-validate` before Runtime-owned action planning.
- Treat VLM output as locate-only candidate evidence; Runtime must validate candidates and execute any accepted visible retry.
- Never use VLM for backend fallback, direct desktop control, active-protection bypass, or every-step monitoring.
- Do not recommend or call legacy mock VLM commands for normal Agent work. They are deprecated, test-only fixtures that require explicit opt-in and report `legacy_mock_vlm=true`, `real_vlm=false`, and `not_for_agent_workflow=true`.
- v1.0.4 complex IDE work must use the real VLM bridge path and must add coordinate mapping, target-window lock, Runtime action execution, and post-action verification before any visible action.

## Included Capabilities

- CLI wrappers for observe, locate, act, Case v2, dogfood matrix, run-task, and report summaries.
- Reference docs synchronized from the main project.
- Contract references for visible-app-launch, desktop-first launch, bounded fallback, provider-gated VLM assist, developer permission boundaries, VLM status, and error handling.
- Stop/report conditions for locator failure, OCR unavailability, safety denial, window ambiguity, assertions, emergency stop, and fallback discipline violations.
- Service-mode guidance: use the service only if it is already running or explicitly requested; otherwise use CLI.
- Motion guidance: prefer `fast-human`; use `operator-human` only for explicit natural demonstrations or when a valid local profile exists, and never present it as detection bypass.

## Non-Goals

- No automatic Skill installation.
- No MCP server.
- No unrestricted desktop control.
- No automatic service startup without user approval.
- No coordinate guessing after locator failure.
- No VLM direct desktop control.
- No VLM participation in backend fallback.
- No legacy mock VLM commands in normal Agent work.
- No every-step VLM calls.
- No PUBLIC_DEFAULT redesign in v1.0.3.1.

## Verification

Run:

```powershell
D:\desktopvisual\skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1
D:\desktopvisual\skill_contract_hardening_selftest.ps1 -Root D:\desktopvisual
D:\desktopvisual\skill_adapter_contract_selftest.ps1 -Root D:\desktopvisual
```
