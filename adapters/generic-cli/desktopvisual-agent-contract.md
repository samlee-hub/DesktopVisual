# DesktopVisual Agent Contract

This is an agent-agnostic contract for DesktopVisual CLI wrappers.

Required flow: `observe-locate-act-verify`.

Service protocol: DesktopVisual exposes local service protocol `1.0` when `winagent.exe serve` is explicitly started. Service responses use top-level `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version`.

## Commands

### version

Returns runtime version, supported commands, `project_root`, and Safety Manifest status through `data.manifest_loaded`.

### safety-report

Returns machine-readable safety boundary data and writes `artifacts\safety\safety_report.md/json`.

### policy-check

Dry-run allow/deny for a title, process, action, and optional path. It performs no input.

### consent-check

Dry-run target consent validation for explicit, unique, visible authorized windows. It performs no input.

### observe

Reads target window state and artifacts without input.

### locate

Locates a selector inside an authorized target window.

### act

Performs one reviewed action against a located target.

### run-case

Runs a reviewed Case v2 file and writes a Markdown report.

### run-task

Runs a reviewed task.json file and writes a Markdown report. This is the preferred path for complex work.

### read-report

Reads an existing report from a safe path.

Service endpoint: `/read-report` (`/report` remains a compatibility alias).

## Unified Return

Wrappers should return:

```json
{
  "ok": true,
  "error_code": "",
  "data": {},
  "artifacts": [],
  "report_path": ""
}
```

For failures, `ok=false` and `error_code` must be set when available.

Safety stop rules: failed commands, failed report steps, locator failures, safety denials, ambiguous windows, and emergency stop must stop the agent. Do not continue with arbitrary clicks.

Service mode does not unlock FULL_ACCESS, does not provide interactive confirmation, and does not bypass PermissionManager, SafetyPolicy, Safety Manifest, foreground checks, or safe read/write roots.

No unrestricted desktop control and no sensitive flows are allowed.

## Visual Studio C++ Complex IDE Workflow

DesktopVisual v1.0.4 accepts the Visual Studio C++ complex IDE workflow only when the path is visible and step-checkpointed. VS launch must be visible desktop icon double-click. Project open must be visible VS UI. `SingleTestProject` must be an Empty Project using default location/settings. Source/header files must be added through visible IDE UI. Code edits, build, run, and output verification must happen through visible VS editor/UI/shortcut surfaces. Backend project creation, file writes, `.vcxproj` edits, `msbuild`, direct exe run, backend `.sln` open, and legacy mock VLM cannot support PASS.
