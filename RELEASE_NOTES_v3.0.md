# DesktopVisual v3.0.0 Release Notes - Windows Computer Use MVP

## What's New

### TaskRunner

- `winagent run-task --file <task.json> --report <report.md>`
- task.json format with target window, budget, and observe/locate/act steps
- automatic observe-before, locate, act, observe-after, and expect verification
- FailureClassifier with recoverability and recommended user action
- bounded recovery for focus, locator, OCR fallback, and expectation checks
- MVP report sections: Summary, Environment, Step Timeline, Artifacts, Final Recommendation

### Task Examples

- `tasks\testwindow_basic.task.json`
- `tasks\notepad_input.task.json`
- `tasks\calculator_42.task.json`
- `tasks\edge_local_form.task.json`
- `tasks\explorer_temp_folder.task.json`
- `tasks\vscode_edit_save.task.json`

### Service Integration

- `POST /run-task` added to service mode.
- Service mode remains explicit and local; it wraps existing command handlers and writes audit logs.

### Skill Workflow

- Skill guidance now recommends task.json for complex GUI work.
- New helper scripts run and summarize task reports.

## Capability Boundary

Supported: authorized-window observe, selector locate, controlled actions, Case v2, real OCR when Windows provides it, BMP image matching, dogfood scripts, local service mode, task.json orchestration, and bounded recovery.

Not supported: protected desktops, administrator windows, arbitrary user-file operation, autonomous decision-making, credential extraction, unrestricted desktop control, or guaranteed control of every custom-drawn UI.

## Upgrade Notes

All v2.3.0 CLI commands, case files, and service endpoints remain compatible. v3.0.0 adds `run-task` and `/run-task`; it does not remove existing command names or JSON envelopes.
