# Service Protocol

Current version: `v5.10.2`.

DesktopVisual service protocol version: `1.0`.

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. `D:\desktopvisual` is the internal development tree, not the public release tree.

Service mode is an explicit local named-pipe wrapper around existing CLI/runtime actions. It is intended for agent-agnostic callers such as Codex adapters, Claude Code adapters, generic CLI agents, and reviewed local scripts.

v5.10.2 keeps service protocol version `1.0`. It does not add v6 endpoints, VLM providers, Agent Planner behavior, public release permission narrowing, or a new service envelope. TaskRuntime HumanMode browser-flow PASS is established by CLI evidence plus `v5_10_2_taskruntime_evidence_verifier.ps1`; service availability is validated separately and may be recorded as a non-blocking known limit if the local service is not running.

## Transport

- Command: `winagent.exe serve`
- Pipe: `\\.\pipe\DesktopVisualService`
- Request shape: JSON with `endpoint` and `body`.
- Response shape: unified service envelope.

## Unified Response

Every service endpoint returns:

```json
{
  "ok": true,
  "error_code": "",
  "message": "OK",
  "data": {},
  "artifacts": [],
  "report_path": "",
  "duration_ms": 0,
  "service_protocol_version": "1.0"
}
```

Failed responses also include:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  }
}
```

The `error` object is retained for compatibility, but new callers should prefer top-level `error_code` and `message`.

## Endpoints

- `/version`
- `/health`
- `/health-check`
- `/capabilities`
- `/observe`
- `/locate`
- `/act`
- `/run_task`
- `/get_task_status`
- `/get_task_events`
- `/confirm_task_action`
- `/cancel_task`
- `/read_task_report`
- `/run-task`
- `/read-report`
- `/report` (compatibility alias for `/read-report`)
- `/safety-report`
- `/policy-check`
- `/consent-check`
- `/shutdown`

## v5.7 Task API

The v5.7 task API exposes TaskSession execution and artifacts to external Agents without requiring them to know internal script paths.

### run_task

Request:

```json
{
  "endpoint": "/run_task",
  "body": {
    "file": "D:\\desktopvisual\\tasks\\session_schema\\local_form_fill_submit_mock_audit.task-session.json"
  }
}
```

Response `data` includes `task_id`, `current_state`, `machine_readable_status`, and artifact paths for `task_result.json`, `task_events.jsonl`, `task_report.md`, `current_state.json`, `failure_dump.json`, `evidence_index.md`, and the status registry record.

The compatibility endpoint `/run-task` also accepts TaskSession files and routes them through the same stable task API. Legacy TaskRunner files still require `body.report`.

### get_task_status

```json
{
  "endpoint": "/get_task_status",
  "body": {
    "task_id": "dev5_0_4_local_form_fill_submit_mock_audit"
  }
}
```

Returns the registered task status record with `machine_readable_status.state`, `ok`, `terminal`, `cancellable`, and `error_code`.

### get_task_events

```json
{
  "endpoint": "/get_task_events",
  "body": {
    "task_id": "dev5_0_4_local_form_fill_submit_mock_audit"
  }
}
```

Returns `events_path`, `event_count`, and JSONL content. Callers should parse each line as a separate event.

### read_task_report

```json
{
  "endpoint": "/read_task_report",
  "body": {
    "task_id": "dev5_0_4_local_form_fill_submit_mock_audit"
  }
}
```

Returns `report_path`, `content_length`, and Markdown content.

### confirm_task_action

```json
{
  "endpoint": "/confirm_task_action",
  "body": {
    "task_id": "dev5_0_4_local_form_fill_submit_mock_audit",
    "response": "confirm"
  }
}
```

Writes a confirmation artifact with `safety_override=false`. Confirmation does not override SafetyPolicy or blocked actions.

### cancel_task

```json
{
  "endpoint": "/cancel_task",
  "body": {
    "task_id": "dev5_0_4_local_form_fill_submit_mock_audit",
    "reason": "user cancel"
  }
}
```

Cancellation is stable for terminal tasks: completed, failed, stopped, and blocked tasks return `cancelled=false` instead of mutating the result. Non-terminal or pre-run TaskSession cancellation produces stopped artifacts. Supported stop reasons include user cancel, timeout cancel, safety stop, provider unavailable stop, and confirmation timeout stop.

Stopped cancellation artifacts include `task_result.json`, `task_events.jsonl`, `task_report.md`, `failure_dump.json`, `cancel_audit.json`, and `evidence_index.md`. The cancel audit records the stop code and `safety_override=false`.

## Audit

Every service request appends `artifacts\service_audit.log` with:

- timestamp
- session id
- endpoint
- title
- permission mode
- service protocol version
- ok
- error code
- duration ms

## Safety Boundary

Service mode does not unlock FULL_ACCESS, does not provide interactive confirmation, and does not bypass PermissionManager, SafetyPolicy, Safety Manifest, foreground checks, TaskRunner recovery limits, or read/write root checks.

FULL_ACCESS can be used by service requests only when the caller supplies an already valid `full_access_session_id` created by local interactive CLI confirmation.

External callers must not use service mode as a low-level coordinate action channel for TaskSession execution. v5.7 task execution must go through `/run_task` or the compatible Runtime task path so StepContract, Verification, Recovery, Confirmation, SafetyPolicy, and AuditTrail remain in force.

## v5.9.0-a Permission Mode

Service and CLI policy paths accept `DEVELOPER_CAPABILITY_DISCOVERY`, `developer_capability_discovery`, `DEVELOPER_FULL_RUNTIME`, and `developer_full_runtime`. If a request omits `permission_mode`, the internal development tree default is `DEVELOPER_CAPABILITY_DISCOVERY` unless `DESKTOPVISUAL_PERMISSION_MODE` overrides it.

Service mode still does not bypass Runtime policy, active protection STOP, foreground checks, read/write roots, confirmation gates, or audit logging. Legacy `FULL_ACCESS` sessions remain supported but are not required for developer-mode basic UI primitives.

