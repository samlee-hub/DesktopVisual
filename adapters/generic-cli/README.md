# DesktopVisual Generic CLI Adapter

This adapter defines a neutral shell contract for any CLI agent or human script using DesktopVisual as a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime.

Primary flow: `observe-locate-act-verify`.

Use `desktopvisual-agent-contract.md` as the stable command contract. Prefer `run-task` for multi-step work because it returns auditable task artifacts. For TaskSession files, follow with `task-status`, `task-events`, and `task-report`; use `task-cancel` for user cancel, timeout, safety stop, provider unavailable, or confirmation timeout, and `task-confirm` only for explicit confirmation records.

If service mode is explicitly running, DesktopVisual service protocol `1.0` returns `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version` for every endpoint. v5.7 service task endpoints are `/run_task`, `/get_task_status`, `/get_task_events`, `/confirm_task_action`, `/cancel_task`, and `/read_task_report`.

No unrestricted desktop control: callers must target only authorized windows and configured safe paths.

No sensitive flows: callers must not automate credentials, payments, banking, security settings, protected desktops, elevated windows, private user data, or unapproved external websites.

Safety stop rules: stop on any command error, failed report step, locator failure, window ambiguity, safety denial, or emergency stop. Read the report before deciding next steps.

Safety Manifest: call `version` and check `data.manifest_loaded`, then call `safety-report` for machine-readable boundary data. Use `policy-check` and `consent-check` as dry-run gates for new targets.

Example:

```powershell
.\scripts\desktopvisual-version.ps1 -Root D:\desktopvisual
.\scripts\desktopvisual-safety-report.ps1 -Root D:\desktopvisual
.\scripts\desktopvisual-observe.ps1 -Root D:\desktopvisual -Title "Agent Test Window"
.\scripts\desktopvisual-run-task.ps1 -Root D:\desktopvisual -TaskFile D:\desktopvisual\tasks\testwindow_basic.task.json
D:\desktopvisual\bin\winagent.exe run-task --file D:\desktopvisual\tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json
D:\desktopvisual\bin\winagent.exe task-status --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-events --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-report --task-id dev5_0_4_local_form_fill_submit_mock_audit
```

Shared rules are in `..\shared`.
