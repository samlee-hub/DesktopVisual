# DesktopVisual for Claude Code

DesktopVisual is a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime that Claude Code can call through shell commands. This adapter is not a Codex Skill and does not assume Claude Code supports Codex Skill format.

Primary flow: `observe-locate-act-verify`.

Recommended sequence:

```powershell
$Root = $env:DESKTOPVISUAL_ROOT
if (-not $Root) { $Root = 'D:\desktopvisual' }
& "$Root\bin\winagent.exe" version
& "$Root\bin\winagent.exe" safety-report
& "$Root\bin\winagent.exe" observe --title "Agent Test Window"
& "$Root\bin\winagent.exe" run-task --file "$Root\tasks\testwindow_basic.task.json" --report "$Root\artifacts\claude_code_task_report.md"
Get-Content "$Root\artifacts\claude_code_task_report.md"
```

Prefer generating a reviewed `task.json`, then running `run-task`, instead of issuing many ad hoc clicks. A task report is auditable and exposes the failed step, `error_code`, screenshots, recovery attempts, and recommendation.

Service protocol: when `winagent.exe serve` is explicitly running, service protocol version `1.0` responses use top-level `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version`. Service mode cannot unlock FULL_ACCESS or bypass safety checks.

If a command or report returns `SKIPPED`, summarize the reason and stop unless the user explicitly provides a different authorized environment. If a command returns `FAIL` or `ok=false`, read the report and apply safety stop rules. Do not retry by guessing coordinates.

No unrestricted desktop control: Claude Code must only operate user-authorized windows and configured safe paths.

No sensitive flows: do not automate credential entry, payments, banking, security controls, admin/elevated applications, protected desktops, private user data, or external web workflows not explicitly authorized.

Safety Manifest: v3.0.5 exposes `safety-report`, `policy-check`, and `consent-check`. Check `version.data.manifest_loaded`; use `policy-check` before a new title/process/action; never continue after manifest denial.

Shared rules:

- `..\shared\TASK_FLOW.md`
- `..\shared\SAFETY_RULES.md`
- `..\shared\ERROR_HANDLING.md`
- `..\shared\REPORT_READING.md`
