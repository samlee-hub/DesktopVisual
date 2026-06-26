# Agent Adapters

Current version: `v5.8.7`.

DesktopVisual is a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime that can be called by Codex, Claude Code, generic CLI agents, and human scripts. It is not a Codex-only script bundle.

## Layout

```text
adapters\
  codex\win-desktop-agent\
  claude-code\
  generic-cli\
  shared\
```

## Codex

Recommended path:

```text
D:\desktopvisual\adapters\codex\win-desktop-agent
```

Legacy compatible path:

```text
D:\desktopvisual\skill_template\win-desktop-agent
```

The Codex adapter keeps `SKILL.md`, helper scripts, and reference docs. It emphasizes `observe-locate-act-verify`, `run-task` first, report reading after failures, Windows foreground input limits, and no sensitive flows. For v5 TaskSession work, Codex should prefer `run-task --file <task-session.json>`, then read `task-status`, `task-events`, and `task-report`.

## Claude Code

Claude Code should copy or reference:

```text
D:\desktopvisual\adapters\claude-code\DESKTOPVISUAL.md
```

This file explains how to call `winagent.exe`, generate a reviewed `task.json` or TaskSession JSON, run `run-task`, and read reports. It does not assume Claude Code supports Codex Skill format. Claude Code callers can use the service task API when `winagent serve` is explicitly running: `/run_task`, `/get_task_status`, `/get_task_events`, `/read_task_report`, `/confirm_task_action`, and `/cancel_task`.

## Generic CLI

Generic CLI agents should use:

```text
D:\desktopvisual\adapters\generic-cli\desktopvisual-agent-contract.md
```

The contract defines `version`, `observe`, `locate`, `act`, `run-case`, `run-task`, `task-status`, `task-events`, `task-report`, `task-confirm`, `task-cancel`, and `read-report`, with normalized return fields:

```json
{
  "ok": true,
  "error_code": "",
  "data": {},
  "artifacts": [],
  "report_path": ""
}
```

## Shared Rules

All adapters reference shared rules in `adapters\shared`:

- `TASK_FLOW.md`
- `SAFETY_RULES.md`
- `ERROR_HANDLING.md`
- `REPORT_READING.md`

Adapters must use `observe-locate-act-verify`, safety stop rules, service protocol v1.0 envelopes when service mode is explicitly running, no unrestricted desktop control, and no sensitive flows.

## v5.7 TaskSession Examples

Codex CLI style:

```powershell
D:\desktopvisual\bin\winagent.exe run-task --file D:\desktopvisual\tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json
D:\desktopvisual\bin\winagent.exe task-status --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-events --task-id dev5_0_4_local_form_fill_submit_mock_audit
D:\desktopvisual\bin\winagent.exe task-report --task-id dev5_0_4_local_form_fill_submit_mock_audit
```

Claude Code or custom service caller style:

```json
{
  "endpoint": "/run_task",
  "body": {
    "file": "D:\\desktopvisual\\tasks\\session_schema\\local_form_fill_submit_mock_audit.task-session.json"
  }
}
```

Custom agents should poll `/get_task_status`, read `/get_task_events` for step evidence, read `/read_task_report` for human-readable summaries, and call `/cancel_task` on user cancellation, timeout, safety stop, provider unavailable, or confirmation timeout.

Adapters in `D:\desktopvisual` may be used for broad local development/evaluation. Public release adapter documentation must be prepared in `D:\desktopvisual-release` with restricted permissions for exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows.

## Selftest

```powershell
D:\desktopvisual\adapter_selftest.ps1
```
